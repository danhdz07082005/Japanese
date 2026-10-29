extends Control

var status_label: Label
var btn_tab_manager: Button
var btn_tab_upload: Button
var panel_manager: Control
var panel_upload: Control

# Manager Tab UI
var search_input: LineEdit
var items_container: VBoxContainer
var scroll_container: ScrollContainer
var lbl_page: Label
var btn_prev: Button
var btn_next: Button

# Upload Tab UI
var name_input: LineEdit
var price_input: LineEdit
var path_input: LineEdit
var type_opt: OptionButton
var btn_browse: Button
var btn_submit: Button
var file_dialog: FileDialog

# State
var all_items: Array = []
var current_page: int = 0
var items_per_page: int = 4
var current_tab: String = "manager" # "manager" or "upload"
var texture_cache: Dictionary = {}

func _ready():
	_setup_ui()
	_set_tab("manager")
	_fetch_items()

func _setup_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Top Header Bar
	var top_bar = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, 70)
	var style_top = StyleBoxFlat.new()
	style_top.bg_color = Color(0.13, 0.15, 0.24, 0.95)
	style_top.content_margin_left = 20
	style_top.content_margin_right = 20
	style_top.content_margin_top = 10
	style_top.content_margin_bottom = 10
	top_bar.add_theme_stylebox_override("panel", style_top)
	add_child(top_bar)
	
	var top_hbox = HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_bar.add_child(top_hbox)
	
	var btn_back = Button.new()
	btn_back.text = "◀ Return to Menu"
	btn_back.custom_minimum_size = Vector2(170, 44)
	btn_back.add_theme_font_size_override("font_size", 17)
	btn_back.pressed.connect(func(): Global.goto_scene("res://scenes/Main.tscn"))
	top_hbox.add_child(btn_back)
	
	var spacer1 = Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer1)
	
	var title = Label.new()
	title.text = "🎨 DESIGNER STUDIO"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
	top_hbox.add_child(title)
	
	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer2)
	
	var designer_lbl = Label.new()
	designer_lbl.text = "Designer: " + Global.get_display_name()
	designer_lbl.add_theme_font_size_override("font_size", 18)
	designer_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	top_hbox.add_child(designer_lbl)
	
	# Main Content Area
	var content_vbox = VBoxContainer.new()
	content_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_vbox.offset_left = 80
	content_vbox.offset_right = -80
	content_vbox.offset_top = 85
	content_vbox.offset_bottom = -20
	content_vbox.add_theme_constant_override("separation", 12)
	add_child(content_vbox)
	
	# Tab Switcher
	var tabs_hbox = HBoxContainer.new()
	tabs_hbox.add_theme_constant_override("separation", 15)
	content_vbox.add_child(tabs_hbox)
	
	btn_tab_manager = Button.new()
	btn_tab_manager.text = "📋 Your Creations (Manager)"
	btn_tab_manager.custom_minimum_size = Vector2(240, 42)
	btn_tab_manager.pressed.connect(func(): _set_tab("manager"))
	tabs_hbox.add_child(btn_tab_manager)
	
	btn_tab_upload = Button.new()
	btn_tab_upload.text = "📤 Upload / Sell New Item"
	btn_tab_upload.custom_minimum_size = Vector2(240, 42)
	btn_tab_upload.pressed.connect(func(): _set_tab("upload"))
	tabs_hbox.add_child(btn_tab_upload)
	
	# Status message
	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	content_vbox.add_child(status_label)
	
	# Setup Manager Panel
	_setup_manager_panel(content_vbox)
	
	# Setup Upload Panel
	_setup_upload_panel(content_vbox)
	
	# Setup File Dialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image Files", "*.mp4, *.webm, *.mov, *.avi, *.mkv ; Video Files", "*.* ; All Files"])
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)

func _setup_manager_panel(parent: Control):
	panel_manager = VBoxContainer.new()
	panel_manager.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_manager.add_theme_constant_override("separation", 12)
	parent.add_child(panel_manager)
	
	# Search Bar
	var search_hbox = HBoxContainer.new()
	panel_manager.add_child(search_hbox)
	
	search_input = LineEdit.new()
	search_input.placeholder_text = "🔍 Search your creations by name or type..."
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.custom_minimum_size = Vector2(0, 40)
	search_input.text_changed.connect(func(_t): current_page = 0; _update_list_ui())
	search_hbox.add_child(search_input)
	
	# Scroll container for items
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_manager.add_child(scroll_container)
	
	items_container = VBoxContainer.new()
	items_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_container.add_theme_constant_override("separation", 12)
	scroll_container.add_child(items_container)
	
	# Pagination Bar
	var page_hbox = HBoxContainer.new()
	page_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	page_hbox.add_theme_constant_override("separation", 20)
	panel_manager.add_child(page_hbox)
	
	btn_prev = Button.new()
	btn_prev.text = "◀ Previous"
	btn_prev.custom_minimum_size = Vector2(120, 38)
	btn_prev.pressed.connect(func(): current_page -= 1; _update_list_ui())
	page_hbox.add_child(btn_prev)
	
	lbl_page = Label.new()
	lbl_page.text = "Page 1 / 1"
	lbl_page.add_theme_font_size_override("font_size", 16)
	page_hbox.add_child(lbl_page)
	
	btn_next = Button.new()
	btn_next.text = "Next ▶"
	btn_next.custom_minimum_size = Vector2(120, 38)
	btn_next.pressed.connect(func(): current_page += 1; _update_list_ui())
	page_hbox.add_child(btn_next)

func _setup_upload_panel(parent: Control):
	panel_upload = CenterContainer.new()
	panel_upload.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_upload.hide()
	parent.add_child(panel_upload)
	
	var form_card = PanelContainer.new()
	form_card.custom_minimum_size = Vector2(650, 0)
	var style_form = StyleBoxFlat.new()
	style_form.bg_color = Color(0.13, 0.15, 0.24, 0.95)
	style_form.set_corner_radius_all(14)
	style_form.border_width_left = 2
	style_form.border_width_right = 2
	style_form.border_width_top = 2
	style_form.border_width_bottom = 2
	style_form.border_color = Color(0.3, 0.35, 0.55, 0.8)
	style_form.content_margin_left = 35
	style_form.content_margin_right = 35
	style_form.content_margin_top = 30
	style_form.content_margin_bottom = 30
	form_card.add_theme_stylebox_override("panel", style_form)
	panel_upload.add_child(form_card)
	
	var form_vbox = VBoxContainer.new()
	form_vbox.add_theme_constant_override("separation", 18)
	form_card.add_child(form_vbox)
	
	var form_title = Label.new()
	form_title.text = "SELL A NEW CREATION"
	form_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form_title.add_theme_font_size_override("font_size", 24)
	form_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	form_vbox.add_child(form_title)
	
	var form_sub = Label.new()
	form_sub.text = "Upload custom themes, wallpapers, or frames. Submitted items are published immediately to the Shop Catalog!"
	form_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_sub.add_theme_font_size_override("font_size", 14)
	form_sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	form_vbox.add_child(form_sub)
	
	form_vbox.add_child(HSeparator.new())
	
	# Field: Name
	var name_lbl = Label.new()
	name_lbl.text = "Item Name:"
	form_vbox.add_child(name_lbl)
	name_input = LineEdit.new()
	name_input.placeholder_text = "e.g., Cyberpunk Tokyo Night"
	name_input.custom_minimum_size = Vector2(0, 42)
	form_vbox.add_child(name_input)
	
	# Field: Type & Price Row
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 20)
	form_vbox.add_child(row2)
	
	var type_vbox = VBoxContainer.new()
	type_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(type_vbox)
	var type_lbl = Label.new()
	type_lbl.text = "Category:"
	type_vbox.add_child(type_lbl)
	type_opt = OptionButton.new()
	type_opt.add_item("THEME")
	type_opt.add_item("AVATAR_FRAME")
	type_opt.add_item("PARTICLE")
	type_opt.add_item("BGM")
	type_opt.custom_minimum_size = Vector2(0, 42)
	type_vbox.add_child(type_opt)
	
	var price_vbox = VBoxContainer.new()
	price_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(price_vbox)
	var price_lbl = Label.new()
	price_lbl.text = "Price (G-Coins):"
	price_vbox.add_child(price_lbl)
	price_input = LineEdit.new()
	price_input.placeholder_text = "e.g., 500"
	price_input.custom_minimum_size = Vector2(0, 42)
	price_vbox.add_child(price_input)
	
	# Field: File Upload
	var file_lbl = Label.new()
	file_lbl.text = "Asset File / Image:"
	form_vbox.add_child(file_lbl)
	
	var file_hbox = HBoxContainer.new()
	file_hbox.add_theme_constant_override("separation", 10)
	form_vbox.add_child(file_hbox)
	
	path_input = LineEdit.new()
	path_input.placeholder_text = "Select a local file (.png, .jpg, .webp, .mp4) or leave empty for metadata only"
	path_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_input.custom_minimum_size = Vector2(0, 42)
	file_hbox.add_child(path_input)
	
	btn_browse = Button.new()
	btn_browse.text = "📁 Browse..."
	btn_browse.custom_minimum_size = Vector2(130, 42)
	btn_browse.pressed.connect(func(): file_dialog.popup_centered_ratio(0.7))
	file_hbox.add_child(btn_browse)
	
	form_vbox.add_child(HSeparator.new())
	
	# Submit Button
	btn_submit = Button.new()
	btn_submit.text = "🚀 Publish to Shop"
	btn_submit.custom_minimum_size = Vector2(0, 48)
	btn_submit.add_theme_font_size_override("font_size", 18)
	var st_sub = StyleBoxFlat.new()
	st_sub.bg_color = Color(0.2, 0.6, 0.4)
	st_sub.set_corner_radius_all(8)
	btn_submit.add_theme_stylebox_override("normal", st_sub)
	btn_submit.pressed.connect(_on_submit_pressed)
	form_vbox.add_child(btn_submit)

func _set_tab(tab_name: String):
	current_tab = tab_name
	
	var active_style = StyleBoxFlat.new()
	active_style.bg_color = Color(0.3, 0.4, 0.75)
	active_style.set_corner_radius_all(8)
	
	var inactive_style = StyleBoxFlat.new()
	inactive_style.bg_color = Color(0.16, 0.18, 0.26)
	inactive_style.set_corner_radius_all(8)
	
	if tab_name == "manager":
		panel_manager.show()
		panel_upload.hide()
		btn_tab_manager.add_theme_stylebox_override("normal", active_style)
		btn_tab_upload.add_theme_stylebox_override("normal", inactive_style)
	else:
		panel_manager.hide()
		panel_upload.show()
		btn_tab_upload.add_theme_stylebox_override("normal", active_style)
		btn_tab_manager.add_theme_stylebox_override("normal", inactive_style)

func _on_file_selected(path: String):
	if is_instance_valid(path_input):
		path_input.text = path

# ==================== DATA & API ====================

func _get_user_id() -> int:
	var acc = Database.get_account()
	if acc.has("user_id") and int(acc["user_id"]) > 0:
		return int(acc["user_id"])
	if acc.has("id") and int(acc["id"]) > 0:
		return int(acc["id"])
	return -1

func _get_headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + Network.jwt_token, "Content-Type: application/json"])

func _fetch_items():
	var uid = _get_user_id()
	status_label.text = "Loading your creations..."
	
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, headers, body):
		req.queue_free()
		if code == 401:
			Network.logout(true)
			Global.goto_scene("res://scenes/Login.tscn")
			return
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var data = json.data
				if data is Array:
					all_items = data
				elif data is Dictionary and data.has("value") and data["value"] is Array:
					all_items = data["value"]
				else:
					all_items = []
				current_page = 0
				_update_list_ui()
				status_label.text = "Loaded %d items successfully." % all_items.size()
			else:
				status_label.text = "Parse error loading items."
		else:
			status_label.text = "Error fetching items: %d" % code
	)
	req.request(Network.BASE_URL + "/shop/items/designer/%d" % uid, _get_headers(), HTTPClient.METHOD_GET)

func _update_list_ui():
	for c in items_container.get_children():
		c.queue_free()
		
	var q = search_input.text.strip_edges().to_lower()
	var filtered = []
	
	for item in all_items:
		var n = str(item.get("name", "")).to_lower()
		var typ = str(item.get("type", "")).to_lower()
		if q.is_empty() or q in n or q in typ:
			filtered.append(item)
			
	var total_pages = ceili(float(filtered.size()) / items_per_page)
	if total_pages == 0: total_pages = 1
	if current_page >= total_pages: current_page = total_pages - 1
	if current_page < 0: current_page = 0
	
	lbl_page.text = "Page %d / %d (%d items)" % [current_page + 1, total_pages, filtered.size()]
	btn_prev.disabled = (current_page == 0)
	btn_next.disabled = (current_page >= total_pages - 1)
	
	if filtered.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No items submitted yet.\nSwitch to 'Upload / Sell New Item' tab to create your first item!"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 18)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
		items_container.add_child(empty_lbl)
		return
		
	var start_idx = current_page * items_per_page
	var end_idx = min(start_idx + items_per_page, filtered.size())
	
	for i in range(start_idx, end_idx):
		var item = filtered[i]
		var card = _create_designer_row(item)
		items_container.add_child(card)

func _create_designer_row(item: Dictionary) -> PanelContainer:
	var name_str = str(item.get("name", "Unknown"))
	var type_str = str(item.get("type", "N/A"))
	var price_val = int(item.get("price", 0))
	var secure_url = str(item.get("secureUrl", item.get("secure_url", "")))
	var is_approved = bool(item.get("isApproved", item.get("approved", false)))
	
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 100)
	
	var style_row = StyleBoxFlat.new()
	style_row.bg_color = Color(0.14, 0.16, 0.25, 0.9)
	style_row.set_corner_radius_all(10)
	style_row.content_margin_left = 15
	style_row.content_margin_right = 15
	style_row.content_margin_top = 10
	style_row.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style_row)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	panel.add_child(hbox)
	
	# Thumbnail
	var thumb_container = PanelContainer.new()
	thumb_container.custom_minimum_size = Vector2(130, 80)
	var st_th = StyleBoxFlat.new()
	st_th.bg_color = Color(0.1, 0.12, 0.18)
	st_th.set_corner_radius_all(8)
	thumb_container.add_theme_stylebox_override("panel", st_th)
	
	var thumb_rect = TextureRect.new()
	thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	thumb_container.add_child(thumb_rect)
	hbox.add_child(thumb_container)
	
	_load_thumbnail(secure_url, thumb_rect)
	
	# Info VBox
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(info_vbox)
	
	var lbl_name = Label.new()
	lbl_name.text = name_str
	lbl_name.add_theme_font_size_override("font_size", 20)
	info_vbox.add_child(lbl_name)
	
	var lbl_type = Label.new()
	lbl_type.text = "Type: " + type_str
	lbl_type.add_theme_font_size_override("font_size", 14)
	lbl_type.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	info_vbox.add_child(lbl_type)
	
	# Price
	var lbl_price = Label.new()
	lbl_price.text = "%d G-Coins" % price_val
	lbl_price.add_theme_font_size_override("font_size", 18)
	lbl_price.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	lbl_price.custom_minimum_size = Vector2(120, 0)
	lbl_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lbl_price)
	
	# Status Badge
	var status_badge = PanelContainer.new()
	status_badge.custom_minimum_size = Vector2(140, 36)
	var st_badge = StyleBoxFlat.new()
	st_badge.set_corner_radius_all(6)
	st_badge.bg_color = Color(0.15, 0.45, 0.25)
	status_badge.add_theme_stylebox_override("panel", st_badge)
	
	var lbl_status = Label.new()
	lbl_status.text = "Active (On Sale)"
	lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_status.add_theme_font_size_override("font_size", 14)
	lbl_status.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	status_badge.add_child(lbl_status)
	hbox.add_child(status_badge)
	
	# Test Theme Button (for designer to preview their own creations)
	var item_id = int(item.get("id", 0))
	var active_url = str(Database.get_account().get("menu_theme_url", ""))
	var is_active = (not secure_url.is_empty() and secure_url == active_url)
	var uid = _get_user_id()
	
	if type_str == "THEME":
		var btn_test = Button.new()
		btn_test.custom_minimum_size = Vector2(130, 36)
		btn_test.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_test.add_theme_font_size_override("font_size", 13)
		if is_active:
			btn_test.text = "Equipped (Remove)"
			var st_act = StyleBoxFlat.new()
			st_act.set_corner_radius_all(6)
			st_act.bg_color = Color(0.2, 0.6, 0.45)
			btn_test.add_theme_stylebox_override("normal", st_act)
			btn_test.pressed.connect(func():
				Database.update_account("menu_theme_url", "")
				var da = DirAccess.open("user://")
				if da != null:
					if da.file_exists("user://menu_theme_cache.dat"): da.remove("user://menu_theme_cache.dat")
					if da.file_exists("user://menu_theme_video.ogv"): da.remove("user://menu_theme_video.ogv")
				var u_req = HTTPRequest.new()
				add_child(u_req)
				u_req.request_completed.connect(func(r, c, h, b): u_req.queue_free())
				u_req.request(Network.BASE_URL + "/shop/items/unequip?userId=%d" % uid, _get_headers(), HTTPClient.METHOD_POST, "")
				status_label.text = "Theme unequipped from your menu."
				_update_list_ui()
			)
		else:
			btn_test.text = "🎨 Test Theme"
			var st_t = StyleBoxFlat.new()
			st_t.set_corner_radius_all(6)
			st_t.bg_color = Color(0.25, 0.45, 0.8)
			btn_test.add_theme_stylebox_override("normal", st_t)
			btn_test.pressed.connect(func():
				Database.update_account("menu_theme_url", secure_url)
				_cache_theme_file(secure_url)
				var a_req = HTTPRequest.new()
				add_child(a_req)
				a_req.request_completed.connect(func(r, c, h, b): a_req.queue_free())
				a_req.request(Network.BASE_URL + "/shop/items/%d/apply?userId=%d" % [item_id, uid], _get_headers(), HTTPClient.METHOD_POST, "")
				status_label.text = "✨ Theme '%s' applied to your menu for testing!" % name_str
				_update_list_ui()
			)
		hbox.add_child(btn_test)
	
	return panel

# ==================== UPLOAD ITEM ====================

func _on_submit_pressed():
	var n = name_input.text.strip_edges()
	var p_str = price_input.text.strip_edges()
	var fpath = path_input.text.strip_edges()
	
	if n.is_empty() or p_str.is_empty():
		status_label.text = "Please enter an item name and price."
		return
		
	if not p_str.is_valid_int() or p_str.to_int() < 0:
		status_label.text = "Price must be a positive integer."
		return
		
	var price_val = p_str.to_int()
	var typ = type_opt.get_item_text(type_opt.selected)
	var uid = _get_user_id()
	
	if fpath.is_empty() or not FileAccess.file_exists(fpath):
		status_label.text = "Please browse and select a valid image or video file to upload."
		return
		
	_upload_with_file(n, typ, price_val, uid, fpath)

func _upload_with_file(name_str: String, type_str: String, price_val: int, uid: int, file_path: String):
	status_label.text = "Uploading file to server & Cloudinary..."
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		status_label.text = "Cannot read file at path: " + file_path
		return
		
	var file_bytes = file.get_buffer(file.get_length())
	file.close()
	
	var boundary = "----GodotUploadBoundary" + str(Time.get_ticks_msec())
	var body = PackedByteArray()
	
	# Helper for form fields
	var fields = {
		"name": name_str,
		"type": type_str,
		"price": str(price_val),
		"designerId": str(uid)
	}
	for k in fields:
		body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
		body.append_array(('Content-Disposition: form-data; name="' + k + '"\r\n\r\n').to_utf8_buffer())
		body.append_array((fields[k] + "\r\n").to_utf8_buffer())
		
	# File field
	var fname = file_path.get_file()
	var mime = "image/png"
	var fl = fname.to_lower()
	if fl.ends_with(".jpg") or fl.ends_with(".jpeg"): mime = "image/jpeg"
	elif fl.ends_with(".webp"): mime = "image/webp"
	elif fl.ends_with(".png"): mime = "image/png"
	elif fl.ends_with(".mp4"): mime = "video/mp4"
	elif fl.ends_with(".webm"): mime = "video/webm"
	elif fl.ends_with(".mov"): mime = "video/quicktime"
	elif fl.ends_with(".avi"): mime = "video/x-msvideo"
	elif fl.ends_with(".mkv"): mime = "video/x-matroska"
	
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(('Content-Disposition: form-data; name="file"; filename="' + fname + '"\r\n').to_utf8_buffer())
	body.append_array(('Content-Type: ' + mime + '\r\n\r\n').to_utf8_buffer())
	body.append_array(file_bytes)
	body.append_array("\r\n".to_utf8_buffer())
	body.append_array(("--" + boundary + "--\r\n").to_utf8_buffer())
	
	var headers = PackedStringArray([
		"Authorization: Bearer " + Network.jwt_token,
		"Content-Type: multipart/form-data; boundary=" + boundary
	])
	
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, hdrs, res_body):
		req.queue_free()
		if code == 200:
			status_label.text = "🎉 Successfully uploaded and published '%s'!" % name_str
			name_input.text = ""
			price_input.text = ""
			path_input.text = ""
			_set_tab("manager")
			_fetch_items()
		else:
			status_label.text = "Upload failed (%d): %s" % [code, res_body.get_string_from_utf8()]
	)
	req.request_raw(Network.BASE_URL + "/shop/items", headers, HTTPClient.METHOD_POST, body)

# ==================== THUMBNAIL LOADER ====================

func _get_image_fetch_url(url: String) -> String:
	if url.is_empty():
		return ""
	var clean_url = url.strip_edges()
	var lower = clean_url.to_lower()
	for ext in [".mp4", ".webm", ".mov", ".mkv", ".avi"]:
		if lower.ends_with(ext):
			return clean_url.substr(0, clean_url.length() - ext.length()) + ".jpg"
	return clean_url

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

func _load_thumbnail(url: String, target_rect: TextureRect):
	if url.is_empty():
		return
		
	var fetch_url = _get_image_fetch_url(url)
		
	if texture_cache.has(fetch_url):
		target_rect.texture = texture_cache[fetch_url]
		return
		
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, headers, body):
		req.queue_free()
		if code == 200:
			var img = _load_image_from_buffer_safe(body)
			if img != null:
				var tex = ImageTexture.create_from_image(img)
				texture_cache[fetch_url] = tex
				if is_instance_valid(target_rect):
					target_rect.texture = tex
	)
	req.request(fetch_url)

func _is_video_url(url: String) -> bool:
	var lower = url.to_lower()
	for ext in [".mp4", ".webm", ".mov", ".mkv", ".avi", ".ogv"]:
		if lower.ends_with(ext):
			return true
	if "/video/upload/" in lower:
		return true
	return false

func _get_video_fetch_url(url: String) -> String:
	if url.is_empty():
		return ""
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

func _cache_theme_file(url: String):
	if url.is_empty(): return
	var img_url = _get_image_fetch_url(url)
		
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, headers, body):
		req.queue_free()
		if code == 200:
			var f = FileAccess.open("user://menu_theme_cache.dat", FileAccess.WRITE)
			if f:
				f.store_buffer(body)
				f.close()
	)
	req.request(img_url)
	
	if _is_video_url(url):
		var v_url = _get_video_fetch_url(url)
		var v_req = HTTPRequest.new()
		add_child(v_req)
		v_req.request_completed.connect(func(res, code, headers, body):
			v_req.queue_free()
			if code == 200 and body.size() > 0:
				var vf = FileAccess.open("user://menu_theme_video.ogv", FileAccess.WRITE)
				if vf:
					vf.store_buffer(body)
					vf.close()
		)
		v_req.request(v_url)
