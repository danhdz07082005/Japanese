extends Control

var username_input: LineEdit
var password_input: LineEdit
var btn_login: Button
var btn_register: Button
var status_label: Label
var lbl_server_status: Label
var btn_toggle_config: Button

# Server Config Modal Panel
var modal_overlay: CenterContainer
var config_panel: PanelContainer
var url_input: LineEdit
var btn_save_url: Button
var btn_reset_url: Button

func _ready():
	_setup_ui()
	Network.login_success.connect(_on_login_success)
	Network.login_failed.connect(_on_error)
	Network.register_success.connect(_on_register_success)
	Network.register_failed.connect(_on_error)
	Network.server_url_changed.connect(func(_u): _check_server_ping())

	# Initial server health check
	_check_server_ping()

func _setup_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Title
	var title = Label.new()
	title.text = "JAPANESE MASTERY LOGIN"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 80
	add_child(title)
	
	# Centered Container for Login VBox (scales responsively on all screen sizes)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 40
	add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(400, 0)
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
	
	username_input = LineEdit.new()
	username_input.placeholder_text = "Username"
	username_input.custom_minimum_size = Vector2(400, 50)
	vbox.add_child(username_input)
	
	password_input = LineEdit.new()
	password_input.placeholder_text = "Password"
	password_input.secret = true
	password_input.custom_minimum_size = Vector2(400, 50)
	vbox.add_child(password_input)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)
	
	btn_login = Button.new()
	btn_login.text = "Login"
	btn_login.custom_minimum_size = Vector2(190, 50)
	btn_login.pressed.connect(_on_login_pressed)
	hbox.add_child(btn_login)
	
	btn_register = Button.new()
	btn_register.text = "Register"
	btn_register.custom_minimum_size = Vector2(190, 50)
	btn_register.pressed.connect(_on_register_pressed)
	hbox.add_child(btn_register)
	
	# Server status bar with quick config gear button
	var server_bar = HBoxContainer.new()
	server_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	server_bar.add_theme_constant_override("separation", 12)
	vbox.add_child(server_bar)

	lbl_server_status = Label.new()
	lbl_server_status.text = "Server: Connecting..."
	lbl_server_status.add_theme_font_size_override("font_size", 14)
	lbl_server_status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	server_bar.add_child(lbl_server_status)

	btn_toggle_config = Button.new()
	btn_toggle_config.text = "⚙️ Đổi Server"
	btn_toggle_config.flat = true
	btn_toggle_config.add_theme_font_size_override("font_size", 13)
	btn_toggle_config.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	btn_toggle_config.pressed.connect(_toggle_config_panel)
	server_bar.add_child(btn_toggle_config)
	
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.modulate = Color(1.0, 0.4, 0.4)
	vbox.add_child(status_label)

	_create_server_config_modal()

func _create_server_config_modal():
	modal_overlay = CenterContainer.new()
	modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_overlay.visible = false
	add_child(modal_overlay)

	config_panel = PanelContainer.new()
	config_panel.custom_minimum_size = Vector2(460, 0)
	var style_modal = StyleBoxFlat.new()
	style_modal.bg_color = Color(0.12, 0.14, 0.22, 0.98)
	style_modal.set_corner_radius_all(10)
	style_modal.border_width_left = 2
	style_modal.border_width_right = 2
	style_modal.border_width_top = 2
	style_modal.border_width_bottom = 2
	style_modal.border_color = Color(0.25, 0.5, 0.85, 0.8)
	style_modal.content_margin_left = 20
	style_modal.content_margin_right = 20
	style_modal.content_margin_top = 20
	style_modal.content_margin_bottom = 20
	config_panel.add_theme_stylebox_override("panel", style_modal)
	modal_overlay.add_child(config_panel)

	var p_box = VBoxContainer.new()
	p_box.add_theme_constant_override("separation", 12)
	config_panel.add_child(p_box)

	var title = Label.new()
	title.text = "🌐 CẤU HÌNH SERVER KẾT NỐI (ONLINE / TUNNEL)"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.2, 0.9, 0.7))
	p_box.add_child(title)

	var hint = Label.new()
	hint.text = "Dán link Cloudflare Tunnel (https://xxx.trycloudflare.com) hoặc Localhost:"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	p_box.add_child(hint)

	url_input = LineEdit.new()
	url_input.text = Network.BASE_URL
	url_input.custom_minimum_size = Vector2(420, 40)
	p_box.add_child(url_input)

	var b_row = HBoxContainer.new()
	b_row.alignment = BoxContainer.ALIGNMENT_CENTER
	b_row.add_theme_constant_override("separation", 10)
	p_box.add_child(b_row)

	btn_save_url = Button.new()
	btn_save_url.text = "Lưu & Kết Nối"
	btn_save_url.custom_minimum_size = Vector2(130, 36)
	btn_save_url.pressed.connect(_on_save_url_pressed)
	b_row.add_child(btn_save_url)

	btn_reset_url = Button.new()
	btn_reset_url.text = "Mặc Định (Localhost)"
	btn_reset_url.custom_minimum_size = Vector2(150, 36)
	btn_reset_url.pressed.connect(func():
		url_input.text = Network.DEFAULT_SERVER_URL
		_on_save_url_pressed()
	)
	b_row.add_child(btn_reset_url)

	var btn_close = Button.new()
	btn_close.text = "Đóng"
	btn_close.custom_minimum_size = Vector2(80, 36)
	btn_close.pressed.connect(func(): modal_overlay.visible = false)
	b_row.add_child(btn_close)

func _toggle_config_panel():
	modal_overlay.visible = not modal_overlay.visible
	if modal_overlay.visible:
		url_input.text = Network.BASE_URL

func _on_save_url_pressed():
	var new_url = Network.set_base_url(url_input.text)
	modal_overlay.visible = false
	status_label.modulate = Color(0.3, 0.9, 1.0)
	status_label.text = "Server URL updated: " + new_url
	_check_server_ping()

func _check_server_ping():
	lbl_server_status.text = "Server: Checking..."
	lbl_server_status.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))

	Network.check_server_health(func(is_online, latency_ms, _info):
		if is_online:
			lbl_server_status.text = "Server: 🟢 Online (%d ms)" % latency_ms
			lbl_server_status.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		else:
			lbl_server_status.text = "Server: 🔴 Offline"
			lbl_server_status.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	)

func _on_login_pressed():
	if username_input.text.is_empty() or password_input.text.is_empty():
		status_label.modulate = Color(1.0, 0.4, 0.4)
		status_label.text = "Please fill in all fields"
		return
	status_label.modulate = Color(0.8, 0.8, 0.8)
	status_label.text = "Connecting..."
	Network.login(username_input.text, password_input.text)

func _on_register_pressed():
	if username_input.text.is_empty() or password_input.text.is_empty():
		status_label.modulate = Color(1.0, 0.4, 0.4)
		status_label.text = "Please fill in all fields"
		return
	status_label.modulate = Color(0.8, 0.8, 0.8)
	status_label.text = "Connecting..."
	Network.register(username_input.text, password_input.text)

func _on_login_success(_data):
	status_label.modulate = Color(0.4, 1.0, 0.4)
	status_label.text = "Login successful!"
	await get_tree().create_timer(0.5).timeout
	Global.goto_scene("res://scenes/Main.tscn")

func _on_register_success(_data):
	status_label.modulate = Color(0.4, 1.0, 0.4)
	status_label.text = "Registration successful!"
	await get_tree().create_timer(0.5).timeout
	Global.goto_scene("res://scenes/Main.tscn")

func _on_error(msg):
	status_label.modulate = Color(1.0, 0.4, 0.4)
	status_label.text = msg
