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
var is_polling: bool = false
var in_match: bool = false
var current_match_id: String = ""
var current_paragraph: String = ""
var current_romaji: String = ""
var current_input: String = ""
var match_start_time: float = 0.0
var is_typing: bool = false
var is_countdown: bool = false
var countdown_end_time: float = 0.0
var sync_timer: float = 0.0
var current_lobby_code: String = ""
var is_lobby_host: bool = false
var queue_pulse_time: float = 0.0

var poll_timer: Timer

# WebSocket Realtime & Telemetry (GNS301 RFC 6455)
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
	var err = _ws.connect_to_url(ws_url)
	if err != OK:
		print("[PvP Realtime] WebSocket notice: ", err)

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
		
		# Sync progress every 0.8s
		sync_timer += delta
		if sync_timer >= 0.8:
			sync_timer = 0.0
			_send_progress_sync()

	if queue_panel != null and queue_panel.visible:
		queue_pulse_time += delta
		var dots = ["", ".", "..", "..."][int(queue_pulse_time * 2) % 4]
		if is_instance_valid(lbl_queue_status):
			lbl_queue_status.text = "Searching for an worthy opponent" + dots

func _poll_websocket(delta: float):
	_ws.poll()
	var state = _ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _ws_authenticated:
			_ws_authenticated = true
			_ws_send({
				"action": "auth",
				"userId": _get_user_id(),
				"username": Global.get_display_name()
			})

		_ping_timer += delta
		if _ping_timer >= 2.0:
			_ping_timer = 0.0
			var fps = int(Engine.get_frames_per_second())
			_ws_send({ "action": "ping", "t": Time.get_ticks_msec(), "fps": fps })

		while _ws.get_available_packet_count() > 0:
			var pkt_bytes = _ws.get_packet()
			var json_str = pkt_bytes.get_string_from_utf8()
			var json = JSON.new()
			if json.parse(json_str) == OK and json.data is Dictionary:
				_handle_ws_event(json.data)

	elif state == WebSocketPeer.STATE_CLOSED:
		_ws_authenticated = false

func _ws_send(dict_payload: Dictionary):
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(dict_payload))

func _handle_ws_event(data: Dictionary):
	var evt = str(data.get("event", ""))
	match evt:
		"pong":
			var sent_t = int(data.get("t", 0))
			if sent_t > 0:
				_current_ping_ms = Time.get_ticks_msec() - sent_t
		"opp_progress":
			if in_match and current_romaji.length() > 0:
				var opp_p = float(data.get("progress", 0))
				var opp_pct = clampf((opp_p / float(current_romaji.length())) * 100.0, 0.0, 100.0)
				opp_progress_bar.value = opp_pct
		"matched":
			_handle_match_state(data)
		"match_finished":
			if in_match:
				var winner_id = int(data.get("winnerId", -1))
				var reward = int(data.get("reward", 100))
				_show_result_screen(winner_id, reward)

func _chars_match(typed_c: String, target_c: String) -> bool:
	if typed_c == target_c:
		return true
	# Allow '~' and '-' to match any wave dash / tilde variant
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
				_ws_send({ "action": "progress", "userId": _get_user_id(), "progress": current_input.length() })
				_check_completion()
			get_viewport().set_input_as_handled()
		elif event.unicode > 0:
			var ch = char(event.unicode).to_lower()
			if event.unicode >= 32 and event.unicode != 127:
				if current_input.length() < current_romaji.length():
					var cur_target = current_romaji[current_input.length()]
					# If next target is tilde / wave dash / hyphen, allow typing '~' or '-' interchangeably
					if (cur_target == "~" or cur_target == "-" or cur_target == "〜" or cur_target == "～") and (ch == "~" or ch == "-" or ch == "〜" or ch == "～" or ch == "_"):
						ch = cur_target
						
				if current_input.length() < current_romaji.length() + 10:
					current_input += ch
					_update_rich_text()
					_ws_send({ "action": "progress", "userId": _get_user_id(), "progress": current_input.length() })
					_check_completion()
				get_viewport().set_input_as_handled()

# ==================== UI SETUP ====================

func _setup_ui():
	# Dark futuristic arena background
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Background grid lines or gradient overlay
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
	
	# Poll timer
	poll_timer = Timer.new()
	poll_timer.wait_time = 0.5
	poll_timer.autostart = false
	poll_timer.timeout.connect(_poll_status)
	add_child(poll_timer)

func _create_header(parent: Control, title_text: String) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
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
	
	_create_header(lobby_panel, "⚔️ PVP TYPING DUEL")
	
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
	
	box.add_child(HSeparator.new())
	
	var join_label = Label.new()
	join_label.text = "Or Join with Room Code:"
	join_label.add_theme_font_size_override("font_size", 16)
	box.add_child(join_label)
	
	var join_hbox = HBoxContainer.new()
	join_hbox.add_theme_constant_override("separation", 10)
	box.add_child(join_hbox)
	
	code_input = LineEdit.new()
	code_input.placeholder_text = "ENTER ROOM CODE"
	code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_input.custom_minimum_size = Vector2(0, 48)
	code_input.add_theme_font_size_override("font_size", 18)
	code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_hbox.add_child(code_input)
	
	btn_join_lobby = _create_styled_button("Join Room", Color(0.5, 0.3, 0.7), Vector2(140, 48))
	btn_join_lobby.pressed.connect(_on_join_lobby_pressed)
	join_hbox.add_child(btn_join_lobby)
	
	box.add_child(HSeparator.new())
	
	btn_back_lobby = _create_styled_button("◀ Return to Main Menu", Color(0.3, 0.3, 0.35), Vector2(480, 50))
	btn_back_lobby.pressed.connect(func(): Global.goto_scene("res://scenes/Main.tscn"))
	box.add_child(btn_back_lobby)

func _create_queue_panel():
	queue_panel = Control.new()
	queue_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_panel.hide()
	add_child(queue_panel)
	
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_panel.add_child(center)
	
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	
	var icon = Label.new()
	icon.text = "⚔️"
	icon.add_theme_font_size_override("font_size", 72)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(icon)
	
	lbl_queue_status = Label.new()
	lbl_queue_status.text = "Searching for an opponent..."
	lbl_queue_status.add_theme_font_size_override("font_size", 28)
	lbl_queue_status.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	lbl_queue_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl_queue_status)
	
	btn_cancel_queue = _create_styled_button("Cancel Queue", Color(0.7, 0.25, 0.25), Vector2(240, 50))
	btn_cancel_queue.pressed.connect(_leave_queue)
	box.add_child(btn_cancel_queue)

func _create_lobby_wait_panel():
	lobby_wait_panel = Control.new()
	lobby_wait_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_wait_panel.hide()
	add_child(lobby_wait_panel)
	
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby_wait_panel.add_child(center)
	
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	
	var title = Label.new()
	title.text = "PRIVATE ROOM CREATED"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	
	lbl_lobby_code = Label.new()
	lbl_lobby_code.text = "ROOM CODE: ------"
	lbl_lobby_code.add_theme_font_size_override("font_size", 42)
	lbl_lobby_code.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	lbl_lobby_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl_lobby_code)
	
	var info = Label.new()
	info.text = "Share this room code with your friend.\nWaiting for them to join..."
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)
	
	btn_cancel_lobby = _create_styled_button("Cancel Room", Color(0.7, 0.25, 0.25), Vector2(240, 50))
	btn_cancel_lobby.pressed.connect(_cancel_lobby)
	box.add_child(btn_cancel_lobby)

func _create_match_panel():
	match_panel = Control.new()
	match_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	match_panel.hide()
	add_child(match_panel)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_left = 60
	main_vbox.offset_right = -60
	main_vbox.offset_top = 20
	main_vbox.offset_bottom = -20
	main_vbox.add_theme_constant_override("separation", 14)
	match_panel.add_child(main_vbox)
	
	# Top bar: You vs Opponent + Quit button
	var top_bar = HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 45)
	main_vbox.add_child(top_bar)
	
	lbl_my_name = Label.new()
	lbl_my_name.text = "YOU: " + Global.get_display_name()
	lbl_my_name.add_theme_font_size_override("font_size", 20)
	lbl_my_name.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	top_bar.add_child(lbl_my_name)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	
	lbl_opp_name = Label.new()
	lbl_opp_name.text = "OPPONENT: ..."
	lbl_opp_name.add_theme_font_size_override("font_size", 20)
	lbl_opp_name.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	top_bar.add_child(lbl_opp_name)
	
	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer2)
	
	btn_quit_match = Button.new()
	btn_quit_match.text = "Forfeit Match"
	btn_quit_match.custom_minimum_size = Vector2(130, 38)
	btn_quit_match.pressed.connect(_quit_match)
	top_bar.add_child(btn_quit_match)
	
	# Progress Bars
	var prog_vbox = VBoxContainer.new()
	prog_vbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(prog_vbox)
	
	var my_lbl = Label.new()
	my_lbl.text = "Your Progress:"
	my_lbl.add_theme_font_size_override("font_size", 14)
	prog_vbox.add_child(my_lbl)
	
	my_progress_bar = ProgressBar.new()
	my_progress_bar.custom_minimum_size = Vector2(0, 20)
	my_progress_bar.max_value = 100
	my_progress_bar.value = 0
	my_progress_bar.show_percentage = true
	prog_vbox.add_child(my_progress_bar)
	
	var opp_lbl = Label.new()
	opp_lbl.text = "Opponent Progress:"
	opp_lbl.add_theme_font_size_override("font_size", 14)
	prog_vbox.add_child(opp_lbl)
	
	opp_progress_bar = ProgressBar.new()
	opp_progress_bar.custom_minimum_size = Vector2(0, 20)
	opp_progress_bar.max_value = 100
	opp_progress_bar.value = 0
	opp_progress_bar.show_percentage = true
	prog_vbox.add_child(opp_progress_bar)
	
	# Status & Live Timer
	var status_hbox = HBoxContainer.new()
	status_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	status_hbox.add_theme_constant_override("separation", 30)
	main_vbox.add_child(status_hbox)
	
	lbl_status = Label.new()
	lbl_status.text = "Starting in: 3"
	lbl_status.add_theme_font_size_override("font_size", 28)
	status_hbox.add_child(lbl_status)
	
	lbl_timer = Label.new()
	lbl_timer.text = "0.00 s"
	lbl_timer.add_theme_font_size_override("font_size", 28)
	lbl_timer.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	status_hbox.add_child(lbl_timer)
	
	# Japanese Paragraph Card
	var jp_panel = PanelContainer.new()
	jp_panel.custom_minimum_size = Vector2(0, 120)
	jp_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style_jp = StyleBoxFlat.new()
	style_jp.bg_color = Color(0.12, 0.14, 0.22, 0.9)
	style_jp.set_corner_radius_all(10)
	style_jp.content_margin_left = 20
	style_jp.content_margin_right = 20
	style_jp.content_margin_top = 15
	style_jp.content_margin_bottom = 15
	jp_panel.add_theme_stylebox_override("panel", style_jp)
	main_vbox.add_child(jp_panel)
	
	lbl_jp_paragraph = Label.new()
	lbl_jp_paragraph.text = "日本語テキスト"
	lbl_jp_paragraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_jp_paragraph.add_theme_font_size_override("font_size", 26)
	lbl_jp_paragraph.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	lbl_jp_paragraph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_jp_paragraph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	jp_panel.add_child(lbl_jp_paragraph)
	
	# Romaji Typing Area with RichText
	var romaji_panel = PanelContainer.new()
	romaji_panel.custom_minimum_size = Vector2(0, 140)
	romaji_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style_ro = StyleBoxFlat.new()
	style_ro.bg_color = Color(0.08, 0.1, 0.16, 0.95)
	style_ro.set_corner_radius_all(10)
	style_ro.border_width_left = 2
	style_ro.border_width_right = 2
	style_ro.border_width_top = 2
	style_ro.border_width_bottom = 2
	style_ro.border_color = Color(0.2, 0.4, 0.7, 0.6)
	style_ro.content_margin_left = 20
	style_ro.content_margin_right = 20
	style_ro.content_margin_top = 15
	style_ro.content_margin_bottom = 15
	romaji_panel.add_theme_stylebox_override("panel", style_ro)
	main_vbox.add_child(romaji_panel)
	
	rich_romaji = RichTextLabel.new()
	rich_romaji.bbcode_enabled = true
	rich_romaji.text = ""
	rich_romaji.add_theme_font_size_override("normal_font_size", 24)
	rich_romaji.fit_content = false
	rich_romaji.scroll_active = true
	romaji_panel.add_child(rich_romaji)
	
	var hint_lbl = Label.new()
	hint_lbl.text = "💡 Type using your keyboard. Correct letters appear in green."
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 14)
	hint_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	main_vbox.add_child(hint_lbl)

func _create_result_panel():
	result_panel = Control.new()
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.hide()
	add_child(result_panel)
	
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(center)
	
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(450, 0)
	box.add_theme_constant_override("separation", 22)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	
	lbl_result_title = Label.new()
	lbl_result_title.text = "VICTORY!"
	lbl_result_title.add_theme_font_size_override("font_size", 44)
	lbl_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl_result_title)
	
	lbl_result_desc = Label.new()
	lbl_result_desc.text = "Reward: +100 G-Coins"
	lbl_result_desc.add_theme_font_size_override("font_size", 22)
	lbl_result_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl_result_desc)
	
	btn_return_menu = _create_styled_button("Return to Main Menu", Color(0.2, 0.5, 0.35), Vector2(300, 50))
	btn_return_menu.pressed.connect(_on_return_pressed)
	box.add_child(btn_return_menu)

func _create_styled_button(text: String, bg_color: Color, min_size: Vector2) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 20)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.set_corner_radius_all(10)
	style_normal.shadow_size = 4
	style_normal.shadow_offset = Vector2(0, 3)
	style_normal.shadow_color = Color(0, 0, 0, 0.4)
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

func _get_headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + Network.jwt_token, "Content-Type: application/json"])

func _api_request(endpoint: String, method: int, body_str: String, callback: Callable):
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, headers, body):
		if code == 401:
			Network.logout(true)
			Global.goto_scene("res://scenes/Login.tscn")
			return
		callback.call(code, body)
		req.queue_free()
	)
	req.request(Network.BASE_URL + endpoint, _get_headers(), method, body_str)

func _on_random_match_pressed():
	var uid = _get_user_id()
	_show_panel(queue_panel)
	queue_pulse_time = 0.0
	_api_request("/pvp/queue/join/%d" % uid, HTTPClient.METHOD_POST, "", func(code, body):
		if code == 200:
			is_polling = true
			poll_timer.start()
		else:
			var resp = body.get_string_from_utf8()
			if "BANNED" in resp:
				Global.goto_scene("res://scenes/Main.tscn")
			else:
				_show_panel(lobby_panel)
	)

func _leave_queue():
	is_polling = false
	poll_timer.stop()
	var uid = _get_user_id()
	_api_request("/pvp/queue/leave/%d" % uid, HTTPClient.METHOD_POST, "", func(code, body):
		_show_panel(lobby_panel)
	)

func _on_create_lobby_pressed():
	var uid = _get_user_id()
	_api_request("/pvp/lobby/create/%d" % uid, HTTPClient.METHOD_POST, "", func(code, body):
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				current_lobby_code = str(json.data.get("lobbyCode", "ERROR"))
				is_lobby_host = true
				lbl_lobby_code.text = "ROOM CODE: %s" % current_lobby_code
				_show_panel(lobby_wait_panel)
				is_polling = true
				poll_timer.start()
		else:
			print("Failed to create lobby: ", body.get_string_from_utf8())
	)

func _cancel_lobby():
	is_polling = false
	poll_timer.stop()
	var uid = _get_user_id()
	if not current_lobby_code.is_empty():
		_api_request("/pvp/lobby/cancel/%s/%d" % [current_lobby_code, uid], HTTPClient.METHOD_POST, "", func(c, b): pass)
	current_lobby_code = ""
	is_lobby_host = false
	_show_panel(lobby_panel)

func _on_join_lobby_pressed():
	var code = code_input.text.strip_edges().to_upper()
	if code.is_empty():
		return
	var uid = _get_user_id()
	_api_request("/pvp/lobby/join/%s/%d" % [code, uid], HTTPClient.METHOD_POST, "", func(code_num, body):
		if code_num == 200:
			current_lobby_code = code
			is_lobby_host = false
			_show_panel(queue_panel)
			lbl_queue_status.text = "Joined room %s! Waiting for match..." % code
			is_polling = true
			poll_timer.start()
		else:
			print("Failed to join lobby: ", body.get_string_from_utf8())
	)

func _poll_status():
	if not is_polling:
		return
	var uid = _get_user_id()
	_api_request("/pvp/status/%d" % uid, HTTPClient.METHOD_GET, "", func(code, body):
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				var data = json.data
				var status = data.get("status", "NONE")
				if status == "MATCHED":
					_handle_match_state(data)
				elif status == "NONE" and in_match:
					in_match = false
					is_polling = false
					poll_timer.stop()
					_show_panel(lobby_panel)
	)

func _handle_match_state(data: Dictionary):
	current_match_id = str(data.get("matchId", ""))
	current_paragraph = str(data.get("paragraph", "No Text"))
	var rom = data.get("romajiParagraph", "")
	if rom != null and not str(rom).is_empty():
		current_romaji = str(rom).to_lower()
	else:
		current_romaji = current_paragraph.to_lower()
	current_romaji = current_romaji.replace("〜", "~").replace("～", "~")
		
	var state = str(data.get("state", ""))
	if data.has("opponentName"):
		lbl_opp_name.text = "OPPONENT: " + str(data["opponentName"])
		
	if not in_match:
		in_match = true
		_show_panel(match_panel)
		current_input = ""
		lbl_jp_paragraph.text = current_paragraph
		lbl_my_name.text = "YOU: " + Global.get_display_name()
		_update_rich_text()
		_set_progress(0, 0)
		
	if state == "COUNTDOWN":
		is_typing = false
		var countdown_ms = int(data.get("countdown", 3000))
		countdown_end_time = (Time.get_ticks_msec() / 1000.0) + (countdown_ms / 1000.0)
		is_countdown = true
		_update_rich_text()
	elif state == "PLAYING":
		if is_countdown or not is_typing:
			is_countdown = false
			is_typing = true
			match_start_time = Time.get_ticks_msec() / 1000.0
			_update_rich_text()
		var my_p = float(data.get("myProgress", 0))
		var opp_p = float(data.get("oppProgress", 0))
		_set_progress(my_p, opp_p)
	elif state == "FINISHED":
		is_typing = false
		is_countdown = false
		var winner_id = int(data.get("winnerId", -1))
		var reward = int(data.get("reward", 0))
		_show_result_screen(winner_id, reward)

func _set_progress(my_p: float, opp_p: float):
	if current_romaji.length() == 0:
		return
	var my_pct = clampf((my_p / float(current_romaji.length())) * 100.0, 0.0, 100.0)
	var opp_pct = clampf((opp_p / float(current_romaji.length())) * 100.0, 0.0, 100.0)
	my_progress_bar.value = my_pct
	opp_progress_bar.value = opp_pct

func _send_progress_sync():
	var uid = _get_user_id()
	_api_request("/pvp/match/progress/%d?progress=%d" % [uid, current_input.length()], HTTPClient.METHOD_POST, "", func(c, b): pass)

func _check_completion():
	if current_romaji.is_empty(): return
	if current_input.length() != current_romaji.length(): return
	for i in range(current_romaji.length()):
		if not _chars_match(current_input[i], current_romaji[i]):
			return
	is_typing = false
	var elapsed_ms = int(((Time.get_ticks_msec() / 1000.0) - match_start_time) * 1000.0)
	var uid = _get_user_id()
	_ws_send({ "action": "finish", "userId": uid, "timeMs": elapsed_ms })
	_api_request("/pvp/match/finish/%d?timeMs=%d" % [uid, elapsed_ms], HTTPClient.METHOD_POST, "", func(c, b): pass)

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
				# Green for correct
				sb += "[color=#00FF88]%s[/color]" % target_c
			else:
				# Red for wrong
				has_error = true
				sb += "[color=#FF3344]%s[/color]" % target_c
		elif i == current_input.length() and not has_error:
			# Yellow underline for next character
			sb += "[color=#FFEE00][u]%s[/u][/color]" % target_c
		else:
			# Light gray for remaining
			sb += "[color=#8888AA]%s[/color]" % target_c
			
	rich_romaji.text = sb
	_set_progress(current_input.length(), opp_progress_bar.value * current_romaji.length() / 100.0)

func _quit_match():
	is_polling = false
	poll_timer.stop()
	in_match = false
	is_typing = false
	var uid = _get_user_id()
	_api_request("/pvp/match/quit/%d" % uid, HTTPClient.METHOD_POST, "", func(c, b):
		Global.goto_scene("res://scenes/Main.tscn")
	)

func _show_result_screen(winner_id: int, reward: int):
	is_polling = false
	poll_timer.stop()
	in_match = false
	is_typing = false
	
	_show_panel(result_panel)
	var uid = _get_user_id()
	if winner_id == uid:
		lbl_result_title.text = "🏆 VICTORY!"
		lbl_result_title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		lbl_result_desc.text = "You won the typing duel!\nReward: +%d G-Coins" % reward
		Global.add_coins(reward)
	else:
		lbl_result_title.text = "💀 DEFEAT..."
		lbl_result_title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		lbl_result_desc.text = "Opponent was faster this time.\nPenalty: -100 G-Coins"

func _on_return_pressed():
	var uid = _get_user_id()
	_api_request("/pvp/match/ack/%d" % uid, HTTPClient.METHOD_POST, "", func(c, b):
		Global.goto_scene("res://scenes/Main.tscn")
	)
