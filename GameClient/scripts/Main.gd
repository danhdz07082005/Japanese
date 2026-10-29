extends Control

var bg: TextureRect
var video_bg: VideoStreamPlayer
var title: Label
var header: HBoxContainer
var name_label: Label
var jlpt_label: Label
var coin_label: Label

var btn_placement: Button
var btn_solo: Button
var btn_pvp: Button
var btn_shop: Button
var btn_admin: Button
var btn_create_test: Button
var btn_enter_test_code: Button
var btn_designer: Button

var enter_code_dialog: AcceptDialog
var code_input: LineEdit

var solo_dialog: ConfirmationDialog
var solo_option_btn: OptionButton

var time_elapsed: float = 0.0
var floating_kanjis: Array = []
var kanji_list = ["水", "火", "木", "金", "土", "日", "月", "風", "空", "桜", "夢", "愛", "心", "星", "光", "剣", "魂", "神"]
const MAX_FLOATING_KANJI: int = 12
const KANJI_FONT_SIZES: Array = [42, 60, 78]

func _ready():
	setup_ui()
	refresh_data()
	_apply_theme_background()
	
	var timer = Timer.new()
	timer.wait_time = 1.2
	timer.autostart = true
	timer.timeout.connect(_spawn_kanji)
	add_child(timer)

func _process(delta):
	time_elapsed += delta
	if is_instance_valid(title):
		title.position.y = 50 + sin(time_elapsed * 1.5) * 10.0
		
	for i in range(floating_kanjis.size() - 1, -1, -1):
		var item = floating_kanjis[i]
		var k = item["node"]
		if is_instance_valid(k):
			item["pos_y"] -= item["speed"] * delta
			item["pos_x"] += sin(time_elapsed * item["sway_freq"] + item["sway_offset"]) * item["sway_amp"] * delta
			k.position = Vector2(item["pos_x"], item["pos_y"])
			
			if item["pos_y"] < -100:
				k.queue_free()
				floating_kanjis.remove_at(i)
			elif item["pos_y"] < 200:
				k.modulate.a = max(0.0, k.modulate.a - delta * 0.5)
		else:
			floating_kanjis.remove_at(i)

func _spawn_kanji():
	if floating_kanjis.size() >= MAX_FLOATING_KANJI:
		return
		
	var k_label = Label.new()
	k_label.text = kanji_list[randi() % kanji_list.size()]
	var size = KANJI_FONT_SIZES[randi() % KANJI_FONT_SIZES.size()]
	k_label.add_theme_font_size_override("font_size", size)
	k_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	var alpha = randf_range(0.06, 0.18)
	k_label.modulate = Color(1, 1, 1, alpha)
	
	var view_size = get_viewport_rect().size
	if view_size.x == 0: view_size = Vector2(1280, 720) # Fallback
	var spawn_x = randf_range(0, view_size.x)
	var spawn_y = view_size.y + 50
	k_label.position = Vector2(spawn_x, spawn_y)
	
	add_child(k_label)
	move_child(k_label, 1) # Put it just above background
	
	floating_kanjis.append({
		"node": k_label,
		"pos_x": spawn_x,
		"pos_y": spawn_y,
		"speed": randf_range(30, 70),
		"sway_freq": randf_range(0.5, 2.0),
		"sway_offset": randf_range(0, PI * 2),
		"sway_amp": randf_range(10, 35)
	})

func setup_ui():
	# Background with Gradient
	bg = TextureRect.new()
	var bg_tex = GradientTexture2D.new()
	bg_tex.fill = GradientTexture2D.FILL_LINEAR
	bg_tex.fill_from = Vector2(0.5, 0)
	bg_tex.fill_to = Vector2(0.5, 1)
	var grad = Gradient.new()
	grad.set_color(0, Color(0.05, 0.05, 0.12))
	grad.set_color(1, Color(0.15, 0.2, 0.35))
	bg_tex.gradient = grad
	bg.texture = bg_tex
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	
	# Video Background (plays animated .ogv themes)
	video_bg = VideoStreamPlayer.new()
	video_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video_bg.expand = true
	video_bg.loop = true
	video_bg.volume_db = -80.0
	video_bg.hide()
	add_child(video_bg)
	
	# Header Background (Semi-transparent)
	var header_bg = ColorRect.new()
	header_bg.color = Color(0, 0, 0, 0.4)
	header_bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header_bg.custom_minimum_size = Vector2(0, 70)
	add_child(header_bg)
	
	# Header (Top Bar)
	header = HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.custom_minimum_size = Vector2(0, 70)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 60)
	add_child(header)
	
	name_label = _create_header_label(24, Color(0.95, 0.95, 0.95))
	header.add_child(name_label)
	
	jlpt_label = _create_header_label(24, Color(0.4, 1.0, 0.5))
	header.add_child(jlpt_label)
	
	coin_label = _create_header_label(24, Color(1.0, 0.85, 0.3))
	header.add_child(coin_label)
	
	# Title
	title = Label.new()
	title.text = "JAPANESE MASTERY"
	title.add_theme_font_size_override("font_size", 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 50
	
	# Title styling
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_shadow_color", Color(1.0, 0.6, 0.0, 0.4))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 20)
	
	add_child(title)
	
	# Buttons Container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.position.y = 300
	vbox.add_theme_constant_override("separation", 15)
	add_child(vbox)
	
	btn_placement = create_menu_btn("Level-Up Test")
	btn_placement.pressed.connect(_on_placement_pressed)
	vbox.add_child(btn_placement)
	
	btn_solo = create_menu_btn("Solo Learning (Level X)")
	btn_solo.pressed.connect(_on_solo_pressed)
	vbox.add_child(btn_solo)
	
	btn_pvp = create_menu_btn("⚔️ PvP Arena (Locked)")
	btn_pvp.pressed.connect(_on_pvp_pressed)
	vbox.add_child(btn_pvp)
	
	btn_shop = create_menu_btn("🛒 Shop & Themes")
	btn_shop.pressed.connect(_on_shop_pressed)
	vbox.add_child(btn_shop)
	
	btn_create_test = create_menu_btn("📝 Create New Test")
	btn_create_test.pressed.connect(_on_create_test_pressed)
	btn_create_test.hide()
	vbox.add_child(btn_create_test)
	
	btn_enter_test_code = create_menu_btn("🔑 Enter Test Code")
	btn_enter_test_code.pressed.connect(_on_enter_test_code_pressed)
	btn_enter_test_code.hide()
	vbox.add_child(btn_enter_test_code)
	
	btn_admin = create_menu_btn("⚙️ Admin Control Panel")
	btn_admin.pressed.connect(func(): Global.goto_scene("res://scenes/AdminPanel.tscn"))
	btn_admin.hide()
	vbox.add_child(btn_admin)
	
	btn_designer = create_menu_btn("🎨 Designer Studio")
	btn_designer.pressed.connect(func(): Global.goto_scene("res://scenes/DesignerPanel.tscn"))
	btn_designer.hide()
	vbox.add_child(btn_designer)
	
	var btn_logout = Button.new()
	btn_logout.text = "Logout"
	btn_logout.position = Vector2(20, 15)
	btn_logout.custom_minimum_size = Vector2(120, 40)
	btn_logout.add_theme_font_size_override("font_size", 20)
	var style_lo = StyleBoxFlat.new()
	style_lo.bg_color = Color(0.8, 0.2, 0.2, 0.8)
	style_lo.corner_radius_top_left = 8
	style_lo.corner_radius_bottom_right = 8
	style_lo.corner_radius_top_right = 8
	style_lo.corner_radius_bottom_left = 8
	btn_logout.add_theme_stylebox_override("normal", style_lo)
	var style_lo_h = style_lo.duplicate()
	style_lo_h.bg_color = Color(1.0, 0.3, 0.3, 1.0)
	btn_logout.add_theme_stylebox_override("hover", style_lo_h)
	btn_logout.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_logout.pressed.connect(_on_logout_pressed)
	add_child(btn_logout)

func _create_header_label(font_size: int, font_color: Color) -> Label:
	var lbl = Label.new()
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", font_color)
	lbl.add_theme_color_override("font_shadow_color", Color(0,0,0,0.5))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	return lbl

func create_menu_btn(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(450, 65)
	btn.add_theme_font_size_override("font_size", 26)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var style_n = StyleBoxFlat.new()
	style_n.bg_color = Color(0.18, 0.22, 0.35, 0.9)
	style_n.corner_radius_top_left = 30
	style_n.corner_radius_bottom_right = 30
	style_n.corner_radius_top_right = 8
	style_n.corner_radius_bottom_left = 8
	style_n.border_width_bottom = 6
	style_n.border_color = Color(0.1, 0.12, 0.2)
	style_n.shadow_color = Color(0, 0, 0, 0.4)
	style_n.shadow_size = 6
	style_n.shadow_offset = Vector2(0, 4)
	
	var style_h = style_n.duplicate()
	style_h.bg_color = Color(0.25, 0.32, 0.48, 1.0)
	style_h.shadow_size = 10
	style_h.shadow_offset = Vector2(0, 6)
	style_h.border_color = Color(0.15, 0.18, 0.3)
	
	var style_p = style_n.duplicate()
	style_p.bg_color = Color(0.12, 0.15, 0.25, 1.0)
	style_p.border_width_bottom = 0
	style_p.shadow_size = 0
	style_p.shadow_offset = Vector2(0, 0)
	style_p.content_margin_top = 6 # simulate press down
	
	var style_d = style_n.duplicate()
	style_d.bg_color = Color(0.15, 0.15, 0.15, 0.7)
	style_d.border_color = Color(0.1, 0.1, 0.1, 0.7)
	style_d.shadow_size = 0
	
	btn.add_theme_stylebox_override("normal", style_n)
	btn.add_theme_stylebox_override("hover", style_h)
	btn.add_theme_stylebox_override("pressed", style_p)
	btn.add_theme_stylebox_override("disabled", style_d)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	return btn

func refresh_data():
	var level = Global.get_current_level()
	name_label.text = "Player: " + Global.get_display_name()
	jlpt_label.text = "Level: " + str(level)
	coin_label.text = "G-Coins: " + str(Global.get_coins())
	
	btn_placement.disabled = false
	btn_placement.text = "Level-Up Test (Lv %d -> %d)" % [level, level + 1]
	
	btn_solo.disabled = false
	btn_solo.text = "Learn (Level %d)" % level
	
	if level >= 25:
		btn_pvp.text = "⚔️ PvP Arena"
	else:
		btn_pvp.text = "⚔️ PvP Arena (Locked - Lv 25+)"
	btn_pvp.disabled = false
	
	btn_shop.text = "🛒 Shop & Themes"
	btn_shop.disabled = false
	
	var account = Database.get_account()
	var role = ""
	if account.has("role"):
		role = account["role"]
		
	if role == "ADMIN":
		btn_admin.show()
		btn_designer.hide()
		jlpt_label.hide()
		coin_label.show()
		btn_placement.hide()
		btn_solo.hide()
		btn_pvp.hide()
		btn_shop.show()
		btn_create_test.hide()
		btn_enter_test_code.hide()
	elif role == "DESIGNER":
		btn_admin.hide()
		btn_designer.show()
		jlpt_label.hide()
		coin_label.show()
		btn_placement.hide()
		btn_solo.hide()
		btn_pvp.hide()
		btn_shop.show()
		btn_create_test.hide()
		btn_enter_test_code.hide()
	elif role == "SENSEI":
		btn_admin.hide()
		btn_designer.hide()
		jlpt_label.hide()
		coin_label.show()
		btn_placement.hide()
		btn_solo.hide()
		btn_pvp.hide()
		btn_shop.show()
		btn_create_test.show()
		btn_enter_test_code.hide()
	else: # PLAYER
		btn_admin.hide()
		btn_designer.hide()
		jlpt_label.show()
		coin_label.show()
		btn_placement.show()
		btn_solo.show()
		btn_pvp.show()
		btn_shop.show()
		btn_create_test.hide()
		btn_enter_test_code.show()

func _on_placement_pressed():
	Global.goto_scene("res://scenes/LevelTest.tscn")

func _on_pvp_pressed():
	var level = Global.get_current_level()
	if level < 25:
		var dlg = AcceptDialog.new()
		dlg.title = "PvP Arena Locked"
		dlg.dialog_text = "You must reach Level 25 or higher to enter the PvP Arena!\nCurrent Level: %d" % level
		dlg.dialog_autowrap = true
		add_child(dlg)
		dlg.popup_centered(Vector2i(380, 150))
		return
	Global.goto_scene("res://scenes/PvP.tscn")

func _on_shop_pressed():
	Global.goto_scene("res://scenes/Shop.tscn")

func _is_video_url(url: String) -> bool:
	var lower = url.to_lower()
	for ext in [".mp4", ".webm", ".mov", ".mkv", ".avi", ".ogv"]:
		if lower.ends_with(ext):
			return true
	if "/video/upload/" in lower:
		return true
	return false

func _get_image_fetch_url(url: String) -> String:
	if url.is_empty():
		return ""
	var clean_url = url.strip_edges()
	var lower = clean_url.to_lower()
	for ext in [".mp4", ".webm", ".mov", ".mkv", ".avi"]:
		if lower.ends_with(ext):
			return clean_url.substr(0, clean_url.length() - ext.length()) + ".jpg"
	return clean_url

func _get_video_fetch_url(url: String) -> String:
	if url.is_empty(): return ""
	var clean_url = url.strip_edges()
	var ogv_url = clean_url
	var last_dot = ogv_url.rfind(".")
	if last_dot != -1:
		ogv_url = ogv_url.substr(0, last_dot) + ".ogv"
	else:
		ogv_url += ".ogv"
	
	if "/upload/" in ogv_url and not "/f_ogv/" in ogv_url:
		ogv_url = ogv_url.replace("/upload/", "/upload/f_ogv/")
		
	return ogv_url

func _play_cached_video_if_exists() -> bool:
	if FileAccess.file_exists("user://menu_theme_video.ogv") and is_instance_valid(video_bg):
		var stream = VideoStreamTheora.new()
		stream.file = "user://menu_theme_video.ogv"
		video_bg.stream = stream
		video_bg.show()
		video_bg.play()
		return true
	return false

func _apply_theme_background():
	var theme_url = str(Database.get_account().get("menu_theme_url", ""))
	if theme_url.is_empty():
		# Reset to default gradient if no theme is equipped
		if is_instance_valid(video_bg):
			video_bg.stop()
			video_bg.hide()
		if is_instance_valid(bg):
			var bg_tex = GradientTexture2D.new()
			bg_tex.width = 1280
			bg_tex.height = 720
			bg_tex.fill_from = Vector2(0.5, 0)
			bg_tex.fill_to = Vector2(0.5, 1)
			var grad = Gradient.new()
			grad.set_color(0, Color(0.08, 0.1, 0.18))
			grad.set_color(1, Color(0.15, 0.2, 0.35))
			bg_tex.gradient = grad
			bg.texture = bg_tex
		return
		
	# Tier 1: Check local image cache for instant poster display
	if FileAccess.file_exists("user://menu_theme_cache.dat"):
		var f = FileAccess.open("user://menu_theme_cache.dat", FileAccess.READ)
		if f:
			var bytes = f.get_buffer(f.get_length())
			f.close()
			var img = _load_image_from_buffer_safe(bytes)
			if img != null and is_instance_valid(bg):
				bg.texture = ImageTexture.create_from_image(img)
				bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	
	var is_video = _is_video_url(theme_url)
	if is_video:
		_play_cached_video_if_exists()
	else:
		if is_instance_valid(video_bg):
			video_bg.stop()
			video_bg.hide()
		
	# Tier 2: Refresh/Download image snapshot
	var fetch_url = _get_image_fetch_url(theme_url)
	if not fetch_url.is_empty():
		var req = HTTPRequest.new()
		add_child(req)
		req.request_completed.connect(func(res, code, headers, body):
			req.queue_free()
			if code == 200:
				var img = _load_image_from_buffer_safe(body)
				if img != null and is_instance_valid(bg):
					var tex = ImageTexture.create_from_image(img)
					bg.texture = tex
					bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
					var cf = FileAccess.open("user://menu_theme_cache.dat", FileAccess.WRITE)
					if cf:
						cf.store_buffer(body)
						cf.close()
		)
		req.request(fetch_url)
		
	# Tier 3: If video, download .ogv stream from Cloudinary
	if is_video:
		var v_url = _get_video_fetch_url(theme_url)
		var v_req = HTTPRequest.new()
		add_child(v_req)
		v_req.request_completed.connect(func(res, code, headers, body):
			v_req.queue_free()
			if code == 200 and body.size() > 0:
				var vf = FileAccess.open("user://menu_theme_video.ogv", FileAccess.WRITE)
				if vf:
					vf.store_buffer(body)
					vf.close()
					_play_cached_video_if_exists()
		)
		v_req.request(v_url)

func _load_image_from_buffer_safe(body: PackedByteArray) -> Image:
	if body.size() < 4:
		return null
	var img = Image.new()
	# PNG magic bytes: 89 50 4E 47
	if body[0] == 0x89 and body[1] == 0x50 and body[2] == 0x4E and body[3] == 0x47:
		if img.load_png_from_buffer(body) == OK: return img
	# JPEG magic bytes: FF D8 FF
	elif body[0] == 0xFF and body[1] == 0xD8 and body[2] == 0xFF:
		if img.load_jpg_from_buffer(body) == OK: return img
	# WebP magic bytes: RIFF .... WEBP
	elif body[0] == 0x52 and body[1] == 0x49 and body[2] == 0x46 and body[3] == 0x46:
		if img.load_webp_from_buffer(body) == OK: return img
	
	# Fallback attempts
	if img.load_webp_from_buffer(body) == OK: return img
	if img.load_png_from_buffer(body) == OK: return img
	if img.load_jpg_from_buffer(body) == OK: return img
	return null

func _on_solo_pressed():
	if solo_dialog == null:
		_setup_solo_dialog()
		
	solo_option_btn.clear()
	var level = Global.get_current_level()
	for i in range(1, level + 1):
		solo_option_btn.add_item("Level %d" % i, i)
		
	# Select the current level by default
	solo_option_btn.select(level - 1)
	
	solo_dialog.popup_centered()

func _setup_solo_dialog():
	solo_dialog = ConfirmationDialog.new()
	solo_dialog.title = "Select Level"
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	
	var lbl = Label.new()
	lbl.text = "Which level do you want to learn/review?"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	
	solo_option_btn = OptionButton.new()
	solo_option_btn.custom_minimum_size = Vector2(250, 40)
	vbox.add_child(solo_option_btn)
	
	solo_dialog.add_child(vbox)
	solo_dialog.confirmed.connect(_on_solo_confirmed)
	add_child(solo_dialog)

func _on_solo_confirmed():
	var selected_id = solo_option_btn.get_item_id(solo_option_btn.selected)
	# Normally SoloLearning.gd takes Global.get_current_level(). 
	# Let's set a temporary variable in Global or just pass it.
	Global.set("solo_target_level", selected_id)
	Global.goto_scene("res://scenes/SoloLearning.tscn")
	
func _on_create_test_pressed():
	print("Switching to Test Manager...")
	Global.goto_scene("res://scenes/SenseiTestManager.tscn")
	
func _on_enter_test_code_pressed():
	if enter_code_dialog == null:
		_setup_code_dialog()
	code_input.text = ""
	enter_code_dialog.popup_centered()

func _setup_code_dialog():
	enter_code_dialog = AcceptDialog.new()
	enter_code_dialog.title = "Enter Test"
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	
	var lbl = Label.new()
	lbl.text = "Please enter the Sensei's Test Code:"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	
	code_input = LineEdit.new()
	code_input.placeholder_text = "Example: 12345"
	code_input.custom_minimum_size = Vector2(250, 40)
	vbox.add_child(code_input)
	
	enter_code_dialog.add_child(vbox)
	enter_code_dialog.register_text_enter(code_input)
	
	enter_code_dialog.confirmed.connect(_on_test_code_confirmed)
	add_child(enter_code_dialog)

func _on_test_code_confirmed():
	var code = code_input.text.strip_edges()
	if code.is_empty():
		return
	print("Fetching test with code: ", code)
	
	btn_enter_test_code.text = "Searching..."
	btn_enter_test_code.disabled = true
	
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_test_fetch_completed.bind(req))
	
	var user_id = Database.get_account().get("user_id", -1)
	var headers = PackedStringArray(["Authorization: Bearer " + Network.jwt_token])
	req.request(Network.BASE_URL + "/player/%d/custom-tests/%s" % [user_id, code], headers, HTTPClient.METHOD_GET)

func _on_test_fetch_completed(res, code, headers, body, req: HTTPRequest):
	req.queue_free()
	btn_enter_test_code.text = "🔑 Enter Test Code"
	btn_enter_test_code.disabled = false
	
	if code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var test_data = json.data
			var user_lvl = Global.get_current_level()
			var min_lvl = test_data.get("minLevel", 1)
			if user_lvl < min_lvl:
				OS.alert("Your level (%d) is not high enough for this test (requires Level %d)." % [user_lvl, min_lvl], "Ineligible")
				return
			
			Global.current_custom_test = test_data
			Global.goto_scene("res://scenes/CustomTestRoom.tscn")
		else:
			OS.alert("Invalid test data.", "Error")
	elif code == 400:
		var error_msg = body.get_string_from_utf8()
		OS.alert(error_msg, "Cannot enter")
	else:
		OS.alert("Test code not found or invalid.", "Error (" + str(code) + ")")

func _on_logout_pressed():
	Network.logout()
	Global.goto_scene("res://scenes/Login.tscn")
