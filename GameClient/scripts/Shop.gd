extends Control

var status_label: Label
var coin_label: Label
var search_input: LineEdit
var grid_container: GridContainer
var scroll_container: ScrollContainer

var btn_tab_shop: Button
var btn_tab_my_themes: Button

var lbl_page: Label
var btn_prev: Button
var btn_next: Button

var is_theme_manager_tab: bool = false
var all_items: Array = []
var filtered_items: Array = []
var current_page: int = 0
var items_per_page: int = 8

# Thumbnail cache: url -> ImageTexture
var texture_cache: Dictionary = {}

func _ready():
	_setup_ui()
	Global.coins_changed.connect(_on_coins_changed)
	_update_coins_display()
	_set_tab(false)
	_sync_user_shop_data()
	_fetch_items()

func _exit_tree():
	if Global.coins_changed.is_connected(_on_coins_changed):
		Global.coins_changed.disconnect(_on_coins_changed)

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
	title.text = "🛒 THEME SHOP & CUSTOMIZATION"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	top_hbox.add_child(title)
	
	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer2)
	
	coin_label = Label.new()
	coin_label.text = "💰 G-Coins: 0"
	coin_label.add_theme_font_size_override("font_size", 22)
	coin_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	top_hbox.add_child(coin_label)
	
	# Main Content Area
	var content_vbox = VBoxContainer.new()
	content_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_vbox.offset_left = 60
	content_vbox.offset_right = -60
	content_vbox.offset_top = 85
	content_vbox.offset_bottom = -20
	content_vbox.add_theme_constant_override("separation", 12)
	add_child(content_vbox)
	
	# Tab Buttons + Search Bar
	var controls_hbox = HBoxContainer.new()
	controls_hbox.add_theme_constant_override("separation", 15)
	content_vbox.add_child(controls_hbox)
	
	btn_tab_shop = Button.new()
	btn_tab_shop.text = "🛍️ Shop Catalog"
	btn_tab_shop.custom_minimum_size = Vector2(180, 42)
	btn_tab_shop.pressed.connect(func(): _set_tab(false))
	controls_hbox.add_child(btn_tab_shop)
	
	btn_tab_my_themes = Button.new()
	btn_tab_my_themes.text = "🖼️ My Themes"
	btn_tab_my_themes.custom_minimum_size = Vector2(180, 42)
	btn_tab_my_themes.pressed.connect(func(): _set_tab(true))
	controls_hbox.add_child(btn_tab_my_themes)
	
	var search_spacer = Control.new()
	search_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_hbox.add_child(search_spacer)
	
	search_input = LineEdit.new()
	search_input.placeholder_text = "🔍 Search themes..."
	search_input.custom_minimum_size = Vector2(280, 42)
	search_input.text_changed.connect(_on_search_changed)
	controls_hbox.add_child(search_input)
	
	# Status message
	status_label = Label.new()
	status_label.text = "Loading catalog..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	content_vbox.add_child(status_label)
	
	# Scrollable Grid for Cards
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_vbox.add_child(scroll_container)
	
	grid_container = GridContainer.new()
	grid_container.columns = 2
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_container.add_theme_constant_override("h_separation", 24)
	grid_container.add_theme_constant_override("v_separation", 20)
	scroll_container.add_child(grid_container)
	
	# Pagination Bar
	var page_hbox = HBoxContainer.new()
	page_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	page_hbox.add_theme_constant_override("separation", 20)
	content_vbox.add_child(page_hbox)
	
	btn_prev = Button.new()
	btn_prev.text = "◀ Previous"
	btn_prev.custom_minimum_size = Vector2(120, 38)
	btn_prev.pressed.connect(func(): _change_page(-1))
	page_hbox.add_child(btn_prev)
	
	lbl_page = Label.new()
	lbl_page.text = "Page 1 / 1"
	lbl_page.add_theme_font_size_override("font_size", 16)
	page_hbox.add_child(lbl_page)
	
	btn_next = Button.new()
	btn_next.text = "Next ▶"
	btn_next.custom_minimum_size = Vector2(120, 38)
	btn_next.pressed.connect(func(): _change_page(1))
	page_hbox.add_child(btn_next)

func _update_coins_display():
	if is_instance_valid(coin_label):
		coin_label.text = "💰 G-Coins: %d" % Global.get_coins()

func _on_coins_changed(_new_amount: int):
	_update_coins_display()
	_render_items()

func _set_tab(is_manager: bool):
	is_theme_manager_tab = is_manager
	current_page = 0
	
	var active_style = StyleBoxFlat.new()
	active_style.bg_color = Color(0.25, 0.45, 0.75)
	active_style.set_corner_radius_all(8)
	
	var inactive_style = StyleBoxFlat.new()
	inactive_style.bg_color = Color(0.16, 0.18, 0.26)
	inactive_style.set_corner_radius_all(8)
	
	if is_theme_manager_tab:
		btn_tab_my_themes.add_theme_stylebox_override("normal", active_style)
		btn_tab_shop.add_theme_stylebox_override("normal", inactive_style)
	else:
		btn_tab_shop.add_theme_stylebox_override("normal", active_style)
		btn_tab_my_themes.add_theme_stylebox_override("normal", inactive_style)
		
	_render_items()

func _on_search_changed(_t: String):
	current_page = 0
	_render_items()

func _change_page(dir: int):
	current_page += dir
	_render_items()

# ==================== DATA & NETWORKING ====================

func _get_user_id() -> int:
	return int(Database.get_account().get("user_id", -1))

func _get_headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + Network.jwt_token, "Content-Type: application/json"])

func _get_purchased_ids() -> Array:
	var acc = Database.get_account()
	var role = str(acc.get("role", "PLAYER"))
	var list: Array = []
	if acc.has("purchased_theme_ids") and acc["purchased_theme_ids"] is Array:
		for val in acc["purchased_theme_ids"]:
			var ival = int(val)
			if not list.has(ival):
				list.append(ival)
		
	# ONLY actual DESIGNER or ADMIN accounts automatically own what they created
	var uid = _get_user_id()
	if uid > 0 and (role == "DESIGNER" or role == "ADMIN"):
		for item in all_items:
			if int(item.get("designerId", -99)) == uid:
				var i_id = int(item.get("id", 0))
				if not list.has(i_id):
					list.append(i_id)
				
	return list

func _save_purchased_id(id_val: int):
	var acc = Database.get_account()
	var list: Array = []
	if acc.has("purchased_theme_ids") and acc["purchased_theme_ids"] is Array:
		list = acc["purchased_theme_ids"].duplicate()
	if not list.has(id_val):
		list.append(id_val)
	Database.update_account("purchased_theme_ids", list)

func _get_active_theme_url() -> String:
	return str(Database.get_account().get("menu_theme_url", ""))

func _sync_user_shop_data():
	var uid = _get_user_id()
	if uid <= 0: return
	
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, headers, body):
		req.queue_free()
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				var sdata = json.data
				var clean_list: Array = []
				if sdata.has("purchasedItemIds") and sdata["purchasedItemIds"] is Array:
					for p_id in sdata["purchasedItemIds"]:
						var ival = int(p_id)
						if not clean_list.has(ival):
							clean_list.append(ival)
				Database.update_account("purchased_theme_ids", clean_list)
				
				var act_url = sdata.get("activeThemeUrl")
				if act_url != null and not str(act_url).is_empty() and str(act_url) != "null":
					Database.update_account("menu_theme_url", str(act_url))
				else:
					Database.update_account("menu_theme_url", "")
					var da = DirAccess.open("user://")
					if da != null:
						if da.file_exists("user://menu_theme_cache.dat"):
							da.remove("user://menu_theme_cache.dat")
						if da.file_exists("user://menu_theme_video.ogv"):
							da.remove("user://menu_theme_video.ogv")
							
				if sdata.has("gCoin"):
					Database.update_account("g_coin_balance", int(sdata["gCoin"]))
					_update_coins_display()
				_render_items()
	)
	req.request(Network.BASE_URL + "/shop/user/%d" % uid, _get_headers(), HTTPClient.METHOD_GET)

func _fetch_items():
	status_label.text = "Loading shop items..."
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
				var raw_data = json.data
				var raw_list = []
				if raw_data is Array:
					raw_list = raw_data
				elif raw_data is Dictionary and raw_data.has("value") and raw_data["value"] is Array:
					raw_list = raw_data["value"]
					
				all_items.clear()
				var uid = _get_user_id()
				for item in raw_list:
					if item is Dictionary:
						var is_app = item.get("isApproved", item.get("approved", item.get("is_approved", true)))
						var typ = str(item.get("type", "THEME"))
						# Show approved themes OR designer's own creations
						if (bool(is_app) or int(item.get("designerId", -99)) == uid) and typ == "THEME":
							all_items.append(item)
							
				status_label.text = ""
				_render_items()
			else:
				status_label.text = "Failed to parse shop catalog."
		else:
			status_label.text = "Error loading shop: %d" % code
	)
	req.request(Network.BASE_URL + "/shop/items", _get_headers(), HTTPClient.METHOD_GET)

func _get_filtered_items() -> Array:
	var term = search_input.text.strip_edges().to_lower()
	var purchased_ids = _get_purchased_ids()
	var uid = _get_user_id()
	var role = str(Database.get_account().get("role", "PLAYER"))
	var res = []
	
	for item in all_items:
		var n = str(item.get("name", "")).to_lower()
		var item_id = int(item.get("id", 0))
		var is_owner = (uid > 0 and int(item.get("designerId", -99)) == uid and (role == "DESIGNER" or role == "ADMIN"))
		var is_purchased = purchased_ids.has(item_id) or is_owner
		
		# If on My Themes tab, only show purchased/owned items
		if is_theme_manager_tab and not is_purchased:
			continue
			
		if term.is_empty() or term in n:
			res.append(item)
			
	return res

func _render_items():
	for c in grid_container.get_children():
		c.queue_free()
		
	filtered_items = _get_filtered_items()
	
	var total_pages = ceili(float(filtered_items.size()) / items_per_page)
	if total_pages == 0: total_pages = 1
	if current_page >= total_pages: current_page = total_pages - 1
	if current_page < 0: current_page = 0
	
	lbl_page.text = "Page %d / %d (%d items)" % [current_page + 1, total_pages, filtered_items.size()]
	btn_prev.disabled = (current_page == 0)
	btn_next.disabled = (current_page >= total_pages - 1)
	
	if filtered_items.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No themes found." if not is_theme_manager_tab else "You have not purchased or created any themes yet.\nCheck out the Shop Catalog to browse themes!"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 18)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		grid_container.add_child(empty_lbl)
		return
		
	var start_idx = current_page * items_per_page
	var end_idx = min(start_idx + items_per_page, filtered_items.size())
	
	var active_url = _get_active_theme_url()
	var purchased_ids = _get_purchased_ids()
	var uid = _get_user_id()
	
	for i in range(start_idx, end_idx):
		var item = filtered_items[i]
		var card = _create_item_card(item, active_url, purchased_ids, uid)
		grid_container.add_child(card)

func _create_item_card(item: Dictionary, active_url: String, purchased_ids: Array, uid: int) -> PanelContainer:
	var item_id = int(item.get("id", 0))
	var name_str = str(item.get("name", "Unknown Theme"))
	var price_val = int(item.get("price", 0))
	var secure_url = str(item.get("secureUrl", ""))
	var role = str(Database.get_account().get("role", "PLAYER"))
	var is_owner = (uid > 0 and int(item.get("designerId", -99)) == uid and (role == "DESIGNER" or role == "ADMIN"))
	var is_purchased = purchased_ids.has(item_id) or is_owner
	var is_active = is_purchased and (not secure_url.is_empty() and secure_url == active_url)
	
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(500, 150)
	
	var style_card = StyleBoxFlat.new()
	style_card.bg_color = Color(0.14, 0.16, 0.25, 0.95)
	style_card.set_corner_radius_all(12)
	style_card.border_width_left = 2
	style_card.border_width_right = 2
	style_card.border_width_top = 2
	style_card.border_width_bottom = 2
	style_card.border_color = Color(0.3, 0.7, 1.0, 0.8) if is_active else Color(0.2, 0.24, 0.35, 0.8)
	style_card.content_margin_left = 15
	style_card.content_margin_right = 15
	style_card.content_margin_top = 15
	style_card.content_margin_bottom = 15
	card.add_theme_stylebox_override("panel", style_card)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	card.add_child(hbox)
	
	# Thumbnail Preview
	var thumb_container = PanelContainer.new()
	thumb_container.custom_minimum_size = Vector2(160, 110)
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
	
	# Details VBox
	var details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 6)
	hbox.add_child(details)
	
	var lbl_name = Label.new()
	lbl_name.text = name_str + (" (Your Creation)" if is_owner else "")
	lbl_name.add_theme_font_size_override("font_size", 20)
	lbl_name.add_theme_color_override("font_color", Color(1, 1, 1))
	details.add_child(lbl_name)
	
	var lbl_type = Label.new()
	lbl_type.text = "Owned / Creator" if is_owner else "Custom Menu Theme"
	lbl_type.add_theme_font_size_override("font_size", 14)
	lbl_type.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6) if is_owner else Color(0.65, 0.75, 0.9))
	details.add_child(lbl_type)
	
	var lbl_price = Label.new()
	lbl_price.text = "FREE (Owner)" if is_owner else "💰 Price: %d G-Coins" % price_val
	lbl_price.add_theme_font_size_override("font_size", 16)
	lbl_price.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	details.add_child(lbl_price)
	
	var action_spacer = Control.new()
	action_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(action_spacer)
	
	# Action Button
	var btn_action = Button.new()
	btn_action.custom_minimum_size = Vector2(170, 40)
	btn_action.add_theme_font_size_override("font_size", 16)
	btn_action.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	details.add_child(btn_action)
	
	if is_active:
		btn_action.text = "Equipped (Remove)"
		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.2, 0.6, 0.45)
		st.set_corner_radius_all(6)
		btn_action.add_theme_stylebox_override("normal", st)
		btn_action.pressed.connect(func(): _unequip_theme())
	elif is_purchased:
		btn_action.text = "Equip Theme"
		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.25, 0.45, 0.8)
		st.set_corner_radius_all(6)
		btn_action.add_theme_stylebox_override("normal", st)
		btn_action.pressed.connect(func(): _equip_theme(item))
	else:
		btn_action.text = "Buy (%d GC)" % price_val
		var user_coins = Global.get_coins()
		var can_afford = user_coins >= price_val
		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.8, 0.55, 0.15) if can_afford else Color(0.4, 0.4, 0.4)
		st.set_corner_radius_all(6)
		btn_action.add_theme_stylebox_override("normal", st)
		btn_action.disabled = not can_afford
		btn_action.pressed.connect(func(): _buy_item(item))
		
	return card

# ==================== BUY / EQUIP ACTIONS ====================

func _buy_item(item: Dictionary):
	var item_id = int(item.get("id", 0))
	var price_val = int(item.get("price", 0))
	var uid = _get_user_id()
	
	if Global.get_coins() < price_val:
		status_label.text = "Not enough G-Coins to purchase this theme!"
		return
		
	status_label.text = "Purchasing '%s'..." % str(item.get("name", ""))
	
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, headers, body):
		req.queue_free()
		var resp_str = body.get_string_from_utf8()
		
		if code == 200:
			var json = JSON.new()
			if json.parse(resp_str) == OK and json.data is Dictionary:
				var user_data = json.data
				if user_data.has("gCoin"):
					Database.update_account("g_coin_balance", int(user_data["gCoin"]))
					Global.emit_signal("coins_changed", int(user_data["gCoin"]))
				else:
					Global.add_coins(-price_val)
			else:
				Global.add_coins(-price_val)
				
			_save_purchased_id(item_id)
			status_label.text = "🎉 Successfully purchased '%s'! You can equip it now." % str(item.get("name", ""))
			_render_items()
		elif "You already own this item" in resp_str:
			# Player already owns this theme on server!
			_save_purchased_id(item_id)
			status_label.text = "✨ You already own '%s'! You can equip it now." % str(item.get("name", ""))
			_render_items()
		else:
			status_label.text = "Purchase failed: %s" % resp_str
	)
	var url = Network.BASE_URL + "/shop/items/%d/buy?userId=%d" % [item_id, uid]
	req.request(url, _get_headers(), HTTPClient.METHOD_POST, "")

func _equip_theme(item: Dictionary):
	var item_id = int(item.get("id", 0))
	var url = str(item.get("secureUrl", ""))
	var uid = _get_user_id()
	
	Database.update_account("menu_theme_url", url)
	status_label.text = "✨ Theme equipped! Main menu will now display '%s'." % str(item.get("name", ""))
	
	# Cache theme file locally for instant loading
	_cache_theme_file(url)
	
	# Inform server
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, headers, body): req.queue_free())
	req.request(Network.BASE_URL + "/shop/items/%d/apply?userId=%d" % [item_id, uid], _get_headers(), HTTPClient.METHOD_POST, "")
	
	_render_items()

func _unequip_theme():
	var uid = _get_user_id()
	Database.update_account("menu_theme_url", "")
	status_label.text = "Theme removed. Default background restored."
	
	# Remove cached theme files if exist
	var da = DirAccess.open("user://")
	if da != null:
		if da.file_exists("user://menu_theme_cache.dat"):
			da.remove("user://menu_theme_cache.dat")
		if da.file_exists("user://menu_theme_video.ogv"):
			da.remove("user://menu_theme_video.ogv")
		
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, headers, body): req.queue_free())
	req.request(Network.BASE_URL + "/shop/items/unequip?userId=%d" % uid, _get_headers(), HTTPClient.METHOD_POST, "")
	
	_render_items()

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

# ==================== THUMBNAIL LOADER ====================

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
