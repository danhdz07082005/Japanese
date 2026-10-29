extends Control

# UI Panels
var lobby_panel: Control
var lobby_wait_panel: Control
var queue_panel: Control
var match_panel: Control
var result_panel: Control
var locked_panel: Control

# Lobby UI
var code_input: LineEdit
var lbl_lobby_code: Label
var btn_random_match: Button
var btn_create_lobby: Button
var btn_join_lobby: Button
var btn_back_lobby: Button
var btn_cancel_lobby: Button

# Match UI
var lbl_status: Label
var lbl_timer: Label
var lbl_ping: Label
var lbl_my_name: Label
var lbl_opp_name: Label
var my_progress_bar: ProgressBar
var opp_progress_bar: ProgressBar
var lbl_jp_paragraph: Label
var rich_romaji: RichTextLabel
var btn_quit_match: Button

# Result UI
var lbl_result_title: Label
var lbl_result_desc: Label
var btn_return_menu: Button

# Queue UI
var lbl_queue_status: Label
var btn_cancel_queue: Button

# State variables
var in_match: bool = false
var current_match_id: String = ""
var current_paragraph: String = ""
var current_romaji: String = ""
var current_input: String = ""
var match_start_time: float = 0.0
var is_typing: bool = false
var is_countdown: bool = false
var countdown_end_time: float = 0.0
var current_lobby_code: String = ""
var is_lobby_host: bool = false
var queue_pulse_time: float = 0.0

# WebSocket Realtime (GNS301 RFC 6455)
var _ws: WebSocketPeer = WebSocketPeer.new()
var _ws_authenticated: bool = false
var _ping_timer: float = 0.0
var _current_ping_ms: int = 0

func _ready():
	_setup_ui()
	_connect_websocket()

	var current_lvl = Global.get_current_level()
	if current_lvl < 25:
		_show_locked_panel()
	else:
		_show_panel(lobby_panel)

func _connect_websocket():
	var ws_url = Network.get_ws_url()
	print("[PvP Realtime] Connecting to WebSocket: ", ws_url)
	var err = _ws.connect_to_url(ws_url)
	if err != OK:
		print("[PvP Realtime] Failed to initiate connection: ", err)

func _process(delta: float):
	_poll_websocket(delta)

	if is_countdown:
		var remain = countdown_end_time - (Time.get_ticks_msec() / 1000.0)
		if is_instance_valid(lbl_status):
			if remain > 0:
				lbl_status.text = "Starting in: %d" % int(ceil(remain))
				lbl_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			else:
				lbl_status.text = "TYPE!"
				lbl_status.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		if is_instance_valid(lbl_timer):
			lbl_timer.text = "0.00 s"
	elif is_typing:
		var elapsed = (Time.get_ticks_msec() / 1000.0) - match_start_time
		if is_instance_valid(lbl_status):
			lbl_status.text = "TYPE AS FAST AS YOU CAN!"
			lbl_status.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
		if is_instance_valid(lbl_timer):
			lbl_timer.text = "%.2f s" % elapsed

	if queue_panel != null and queue_panel.visible:
		queue_pulse_time += delta
		var dots = ["", ".", "..", "..."][int(queue_pulse_time * 2) % 4]
		if is_instance_valid(lbl_queue_status):
			lbl_queue_status.text = "Searching for an worthy opponent" + dots

# ==================== WEBSOCKET PACKET PROCESSING ====================

func _poll_websocket(delta: float):
	_ws.poll()
	var state = _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _ws_authenticated:
			_ws_authenticated = true
			var auth_pkt = {
				"action": "auth",
				"userId": _get_user_id(),
				"username": Global.get_display_name()
			}
			_ws_send(auth_pkt)

		# Regular Ping-Pong for RTT measurement & FPS telemetry
		_ping_timer += delta
		if _ping_timer >= 2.0:
			_ping_timer = 0.0
			var fps = int(Engine.get_frames_per_second())
			_ws_send({ "action": "ping", "t": Time.get_ticks_msec(), "fps": fps })

		# Process incoming realtime packets
		while _ws.get_available_packet_count() > 0:
			var pkt_bytes = _ws.get_packet()
			var json_str = pkt_bytes.get_string_from_utf8()
			var json = JSON.new()
			if json.parse(json_str) == OK and json.data is Dictionary:
				_handle_server_event(json.data)

	elif state == WebSocketPeer.STATE_CLOSED:
		_ws_authenticated = false

func _ws_send(dict_payload: Dictionary):
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var text = JSON.stringify(dict_payload)
		_ws.send_text(text)

func _handle_server_event(data: Dictionary):
	var evt = str(data.get("event", ""))

	match evt:
		"pong":
			var sent_t = int(data.get("t", 0))
			if sent_t > 0:
				_current_ping_ms = Time.get_ticks_msec() - sent_t
				if is_instance_valid(lbl_ping):
					var current_fps = int(Engine.get_frames_per_second())
					lbl_ping.text = "⚡ %d ms | 🎮 %d FPS" % [_current_ping_ms, current_fps]

		"queue_joined":
			_show_panel(queue_panel)

		"lobby_created":
			current_lobby_code = str(data.get("code", ""))
			is_lobby_host = true
			lbl_lobby_code.text = "ROOM CODE: %s" % current_lobby_code
			_show_panel(lobby_wait_panel)

		"matched":
			_handle_matched_event(data)

		"start":
			is_countdown = false
			is_typing = true
			match_start_time = Time.get_ticks_msec() / 1000.0
			_update_rich_text()

		"opp_progress":
			var p = float(data.get("progress", 0))
			_set_opp_progress(p)

		"match_finished":
			var winner_id = int(data.get("winnerId", -1))
			var reward = int(data.get("reward", 0))
			_show_result_screen(winner_id, reward)

		"opponent_left":
			var win_id = int(data.get("winnerId", _get_user_id()))
			var r = int(data.get("reward", 35))
			_show_result_screen(win_id, r)

		"error":
			var msg = str(data.get("message", "Unknown error"))
			print("[PvP Realtime] Server error: ", msg)

func _handle_matched_event(data: Dictionary):
	current_match_id = str(data.get("matchId", ""))
	current_paragraph = str(data.get("paragraph", ""))
	var rom = data.get("romajiParagraph", "")
	if rom != null and not str(rom).is_empty():
		current_romaji = str(rom).to_lower()
	else:
		current_romaji = current_paragraph.to_lower()
	current_romaji = current_romaji.replace("〜", "~").replace("～", "~")

	if data.has("opponentName"):
		lbl_opp_name.text = "OPPONENT: " + str(data["opponentName"])

	in_match = true
	_show_panel(match_panel)
	current_input = ""
	lbl_jp_paragraph.text = current_paragraph
	lbl_my_name.text = "YOU: " + Global.get_display_name()
	_update_rich_text()
	_set_progress(0, 0)

	var countdown_ms = int(data.get("countdownMs", 3000))
	countdown_end_time = (Time.get_ticks_msec() / 1000.0) + (countdown_ms / 1000.0)
	is_countdown = true
	is_typing = false

func _chars_match(typed_c: String, target_c: String) -> bool:
	if typed_c == target_c:
		return true
	if (typed_c == "~" or typed_c == "-") and (target_c == "~" or target_c == "-" or target_c == "〜" or target_c == "～"):
		return true
	return false

func _unhandled_input(event: InputEvent):
	if not is_typing:
		return
		
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_BACKSPACE:
			if current_input.length() > 0:
				current_input = current_input.substr(0, current_input.length() - 1)
				_update_rich_text()
				_send_progress_sync()
				_check_completion()
			get_viewport().set_input_as_handled()
		elif event.unicode > 0:
			var ch = char(event.unicode).to_lower()
			if event.unicode >= 32 and event.unicode != 127:
				if current_input.length() < current_romaji.length():
					var cur_target = current_romaji[current_input.length()]
					if (cur_target == "~" or cur_target == "-" or cur_target == "〜" or cur_target == "～") and (ch == "~" or ch == "-" or ch == "〜" or ch == "～" or ch == "_"):
						ch = cur_target
						
				if current_input.length() < current_romaji.length() + 10:
					current_input += ch
					_update_rich_text()
					_send_progress_sync()
					_check_completion()
				get_viewport().set_input_as_handled()

# ==================== UI SETUP ====================

func _setup_ui():
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var overlay = ColorRect.new()
	overlay.color = Color(0.12, 0.16, 0.3, 0.25)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	_create_locked_panel()
	_create_lobby_panel()
	_create_lobby_wait_panel()
	_create_queue_panel()
	_create_match_panel()
	_create_result_panel()

func _create_header(parent: Control, title_text: String) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 25
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var title = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(title)
	
	parent.add_child(box)
	return box

func _create_locked_panel():
	locked_panel = Control.new()
	locked_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(locked_panel)
	
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	locked_panel.add_child(center)
	
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)
	
	var icon = Label.new()
	icon.text = "🔒"
	icon.add_theme_font_size_override("font_size", 72)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(icon)
	
	var title = Label.new()
	title.text = "PVP ARENA IS LOCKED"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	
	var desc = Label.new()
	desc.text = "You must reach Level 25 or higher to enter the PvP Arena.\nCurrent Level: %d" % Global.get_current_level()
	desc.add_theme_font_size_override("font_size", 20)
	desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(desc)
	
	var btn_back = _create_styled_button("Return to Main Menu", Color(0.2, 0.3, 0.5), Vector2(280, 50))
	btn_back.pressed.connect(func(): Global.goto_scene("res://scenes/Main.tscn"))
	box.add_child(btn_back)

func _create_lobby_panel():
	lobby_panel = Control.new()
	lobby_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(lobby_panel)
	
	_create_header(lobby_panel, "⚔️ PVP TYPING DUEL (REALTIME WSS)")
	
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 80
	lobby_panel.add_child(center)
	
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(480, 0)
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	
	var sub_label = Label.new()
	sub_label.text = "Compete 1v1 against other learners in real-time speed typing!"
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.add_theme_font_size_override("font_size", 16)
	sub_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	box.add_child(sub_label)
	
	box.add_child(HSeparator.new())
	
	btn_random_match = _create_styled_button("⚡ Quick Match (Matchmaking)", Color(0.2, 0.55, 0.35), Vector2(480, 60))
	btn_random_match.pressed.connect(_on_random_match_pressed)
	box.add_child(btn_random_match)
	
	btn_create_lobby = _create_styled_button("🚪 Create Private Room", Color(0.25, 0.4, 0.75), Vector2(480, 60))
	btn_create_lobby.pressed.connect(_on_create_lobby_pressed)
	box.add_child(btn_create_lobby)
	
	var join_row = HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	
	code_input = LineEdit.new()
	code_input.placeholder_text = "ENTER ROOM CODE"
	code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_input.custom_minimum_size = Vector2(300, 50)
	code_input.add_theme_font_size_override("font_size", 20)
	join_row.add_child(code_input)
	
	btn_join_lobby = _create_styled_button("Join Room", Color(0.5, 0.35, 0.7), Vector2(170, 50))
	btn_join_lobby.pressed.connect(_on_join_lobby_pressed)
	join_row.add_child(btn_join_lobby)
	box.add_child(join_row)
	
	box.add_child(HSeparator.new())
	
	btn_back_lobby = _create_styled_button("Back to Main Menu", Color(0.3, 0.3, 0.4), Vector2(480, 48))
	btn_back_lobby.pressed.connect(func(): Global.goto_scene("res://scenes/Main.tscn"))
	box.add_child(btn_back_lobby)

func _create_lobby_wait_panel():
	lobby_wait_panel = Control.new()
	lobby_wait_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(lobby_wait_panel)
	
	_create_header(lobby_wait_panel, "ROOM CREATED")
	
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_wait_panel.add_child(center)
	
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	
	lbl_lobby_code = Label.new()
	lbl_lobby_code.text = "ROOM CODE: ----"
	lbl_lobby_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_lobby_code.add_theme_font_size_override("font_size", 42)
	lbl_lobby_code.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
	box.add_child(lbl_lobby_code)
	
	var desc = Label.new()
	desc.text = "Share this code with your rival to duel!\nWaiting for opponent to connect via WebSocket..."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	box.add_child(desc)
	
	btn_cancel_lobby = _create_styled_button("Cancel & Exit Room", Color(0.7, 0.25, 0.25), Vector2(300, 50))
	btn_cancel_lobby.pressed.connect(_cancel_lobby)
	box.add_child(btn_cancel_lobby)

func _create_queue_panel():
	queue_panel = Control.new()
	queue_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(queue_panel)
	
	_create_header(queue_panel, "MATCHMAKING")
	
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_panel.add_child(center)
	
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	
	lbl_queue_status = Label.new()
	lbl_queue_status.text = "Searching for an worthy opponent..."
	lbl_queue_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_queue_status.add_theme_font_size_override("font_size", 26)
	lbl_queue_status.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	box.add_child(lbl_queue_status)
	
	btn_cancel_queue = _create_styled_button("Cancel Queue", Color(0.7, 0.25, 0.25), Vector2(260, 50))
	btn_cancel_queue.pressed.connect(_leave_queue)
	box.add_child(btn_cancel_queue)

func _create_match_panel():
	match_panel = Control.new()
	match_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(match_panel)
	
	var top_bar = HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 40
	top_bar.offset_right = -40
	top_bar.offset_top = 20
	match_panel.add_child(top_bar)
	
	lbl_status = Label.new()
	lbl_status.text = "PREPARING..."
	lbl_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_status.add_theme_font_size_override("font_size", 22)
	top_bar.add_child(lbl_status)

	lbl_ping = Label.new()
	lbl_ping.text = "⚡ 0 ms"
	lbl_ping.add_theme_font_size_override("font_size", 16)
	lbl_ping.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	top_bar.add_child(lbl_ping)
	
	lbl_timer = Label.new()
	lbl_timer.text = "0.00 s"
	lbl_timer.add_theme_font_size_override("font_size", 24)
	lbl_timer.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	top_bar.add_child(lbl_timer)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_CENTER)
	main_vbox.custom_minimum_size = Vector2(900, 0)
	main_vbox.add_theme_constant_override("separation", 20)
	match_panel.add_child(main_vbox)
	
	var bars_panel = PanelContainer.new()
	main_vbox.add_child(bars_panel)
	
	var bars_vbox = VBoxContainer.new()
	bars_vbox.add_theme_constant_override("separation", 14)
	bars_panel.add_child(bars_vbox)
	
	var my_box = VBoxContainer.new()
	lbl_my_name = Label.new()
	lbl_my_name.text = "YOU"
	lbl_my_name.add_theme_color_override("font_color", Color(0.2, 0.9, 0.5))
	my_box.add_child(lbl_my_name)
	my_progress_bar = ProgressBar.new()
	my_progress_bar.custom_minimum_size = Vector2(0, 24)
	my_progress_bar.show_percentage = true
	my_box.add_child(my_progress_bar)
	bars_vbox.add_child(my_box)
	
	var opp_box = VBoxContainer.new()
	lbl_opp_name = Label.new()
	lbl_opp_name.text = "OPPONENT"
	lbl_opp_name.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	opp_box.add_child(lbl_opp_name)
	opp_progress_bar = ProgressBar.new()
	opp_progress_bar.custom_minimum_size = Vector2(0, 24)
	opp_progress_bar.show_percentage = true
	opp_box.add_child(opp_progress_bar)
	bars_vbox.add_child(opp_box)
	
	var text_panel = PanelContainer.new()
	main_vbox.add_child(text_panel)
	
	var text_vbox = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 15)
	text_panel.add_child(text_vbox)
	
	lbl_jp_paragraph = Label.new()
	lbl_jp_paragraph.text = ""
	lbl_jp_paragraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_jp_paragraph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_jp_paragraph.add_theme_font_size_override("font_size", 28)
	text_vbox.add_child(lbl_jp_paragraph)
	
	rich_romaji = RichTextLabel.new()
	rich_romaji.bbcode_enabled = true
	rich_romaji.fit_content = true
	rich_romaji.scroll_active = false
	rich_romaji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rich_romaji.add_theme_font_size_override("normal_font_size", 22)
	text_vbox.add_child(rich_romaji)
	
	btn_quit_match = _create_styled_button("Forfeit Match", Color(0.5, 0.2, 0.2), Vector2(200, 40))
	btn_quit_match.pressed.connect(_quit_match)
	main_vbox.add_child(btn_quit_match)

func _create_result_panel():
	result_panel = Control.new()
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(result_panel)
	
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(center)
	
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 25)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	
	lbl_result_title = Label.new()
	lbl_result_title.text = "RESULT"
	lbl_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_result_title.add_theme_font_size_override("font_size", 48)
	box.add_child(lbl_result_title)
	
	lbl_result_desc = Label.new()
	lbl_result_desc.text = ""
	lbl_result_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_result_desc.add_theme_font_size_override("font_size", 22)
	box.add_child(lbl_result_desc)
	
	btn_return_menu = _create_styled_button("Return to Arena Menu", Color(0.2, 0.5, 0.8), Vector2(280, 55))
	btn_return_menu.pressed.connect(_on_return_pressed)
	box.add_child(btn_return_menu)

func _create_styled_button(text: String, bg_color: Color, min_size: Vector2) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 17)
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", style_normal)
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", style_hover)
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	return btn

func _show_panel(panel: Control):
	locked_panel.hide()
	lobby_panel.hide()
	lobby_wait_panel.hide()
	queue_panel.hide()
	match_panel.hide()
	result_panel.hide()
	
	if panel != null:
		panel.show()

func _show_locked_panel():
	_show_panel(locked_panel)

# ==================== ACTIONS & NETWORKING ====================

func _get_user_id() -> int:
	return int(Database.get_account().get("user_id", -1))

func _on_random_match_pressed():
	_show_panel(queue_panel)
	queue_pulse_time = 0.0
	_ws_send({
		"action": "join_queue",
		"userId": _get_user_id(),
		"username": Global.get_display_name()
	})

func _leave_queue():
	_ws_send({ "action": "leave_queue", "userId": _get_user_id() })
	_show_panel(lobby_panel)

func _on_create_lobby_pressed():
	_ws_send({
		"action": "create_lobby",
		"userId": _get_user_id(),
		"username": Global.get_display_name()
	})

func _cancel_lobby():
	current_lobby_code = ""
	is_lobby_host = false
	_show_panel(lobby_panel)

func _on_join_lobby_pressed():
	var code = code_input.text.strip_edges().to_upper()
	if code.is_empty():
		return
	current_lobby_code = code
	is_lobby_host = false
	_show_panel(queue_panel)
	lbl_queue_status.text = "Joining room %s..." % code
	_ws_send({
		"action": "join_lobby",
		"code": code,
		"userId": _get_user_id(),
		"username": Global.get_display_name()
	})

func _set_progress(my_p: float, opp_p: float):
	if current_romaji.length() == 0:
		return
	var my_pct = clampf((my_p / float(current_romaji.length())) * 100.0, 0.0, 100.0)
	var opp_pct = clampf((opp_p / float(current_romaji.length())) * 100.0, 0.0, 100.0)
	my_progress_bar.value = my_pct
	opp_progress_bar.value = opp_pct

func _set_opp_progress(opp_p: float):
	if current_romaji.length() == 0:
		return
	var opp_pct = clampf((opp_p / float(current_romaji.length())) * 100.0, 0.0, 100.0)
	opp_progress_bar.value = opp_pct

func _send_progress_sync():
	_ws_send({
		"action": "progress",
		"userId": _get_user_id(),
		"progress": current_input.length()
	})

func _check_completion():
	if current_romaji.is_empty(): return
	if current_input.length() != current_romaji.length(): return
	for i in range(current_romaji.length()):
		if not _chars_match(current_input[i], current_romaji[i]):
			return
	is_typing = false
	var elapsed_ms = int(((Time.get_ticks_msec() / 1000.0) - match_start_time) * 1000.0)
	_ws_send({
		"action": "finish",
		"userId": _get_user_id(),
		"timeMs": elapsed_ms
	})

func _update_rich_text():
	if current_romaji.is_empty():
		rich_romaji.text = ""
		return
		
	var sb = ""
	var has_error = false
	
	for i in range(current_romaji.length()):
		var target_c = current_romaji[i]
		if i < current_input.length():
			var typed_c = current_input[i]
			if _chars_match(typed_c, target_c) and not has_error:
				sb += "[color=#00FF88]%s[/color]" % target_c
			else:
				has_error = true
				sb += "[color=#FF3344]%s[/color]" % target_c
		elif i == current_input.length() and not has_error:
			sb += "[color=#FFEE00][u]%s[/u][/color]" % target_c
		else:
			sb += "[color=#8888AA]%s[/color]" % target_c
			
	rich_romaji.text = sb
	if current_romaji.length() > 0:
		var my_pct = clampf((float(current_input.length()) / float(current_romaji.length())) * 100.0, 0.0, 100.0)
		my_progress_bar.value = my_pct

func _quit_match():
	in_match = false
	is_typing = false
	Global.goto_scene("res://scenes/Main.tscn")

func _show_result_screen(winner_id: int, reward: int):
	in_match = false
	is_typing = false
	
	_show_panel(result_panel)
	var uid = _get_user_id()
	if winner_id == uid:
		lbl_result_title.text = "🏆 CHIẾN THẮNG (VICTORY)!"
		lbl_result_title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		lbl_result_desc.text = "Bạn đã thắng trận đấu gõ tốc độ!\nPhần thưởng: +%d G-Coins" % reward
		Global.add_coins(reward)
	else:
		lbl_result_title.text = "💀 THẤT BẠI (DEFEAT)..."
		lbl_result_title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		lbl_result_desc.text = "Đối thủ gõ nhanh hơn trong trận này.\nKhuyến khích: +%d G-Coins" % reward
		Global.add_coins(reward)

func _on_return_pressed():
	_show_panel(lobby_panel)
