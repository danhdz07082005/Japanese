extends Control

var status_label: Label
var users_container: VBoxContainer
var vocab_container: VBoxContainer

var vocab_id_edit = -1 # -1 nghĩa là Đang Thêm Mới, ngược lại là Đang Sửa
var vocab_word: LineEdit
var vocab_romaji: LineEdit
var vocab_meaning: LineEdit
var vocab_level: LineEdit
var vocab_type: OptionButton
var btn_add_vocab: Button

var vbox_user: VBoxContainer
var vbox_vocab: VBoxContainer
var btn_tab_users: Button
var btn_tab_vocab: Button

# Pagination and Search state
var all_users = []
var current_user_page = 0
var items_per_page = 6
var user_search_input: LineEdit
var lbl_user_page: Label
var btn_user_prev: Button
var btn_user_next: Button

var all_vocabs = []
var filtered_vocabs = []
var current_vocab_page = 0
var vocab_search_input: LineEdit
var lbl_vocab_page: Label
var btn_vocab_prev: Button
var btn_vocab_next: Button
var vocab_search_timer: Timer



func _ready():
	_setup_ui()

func _setup_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Title
	var title = Label.new()
	title.text = "BẢNG ĐIỀU KHIỂN ADMIN"
	title.add_theme_font_size_override("font_size", 36)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position.y = 20
	add_child(title)
	
	# Back Button
	var btn_back = Button.new()
	btn_back.text = "Trở về Menu"
	btn_back.position = Vector2(20, 20)
	btn_back.custom_minimum_size = Vector2(150, 40)
	btn_back.pressed.connect(func(): Global.goto_scene("res://scenes/Main.tscn"))
	add_child(btn_back)
	
	status_label = Label.new()
	status_label.position = Vector2(20, 70)
	status_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(status_label)
	
	# Tabs
	var tabs = HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tabs.position.y = 80
	tabs.add_theme_constant_override("separation", 20)
	add_child(tabs)
	
	btn_tab_users = Button.new()
	btn_tab_users.text = "Quản lý Người Dùng"
	btn_tab_users.custom_minimum_size = Vector2(200, 40)
	btn_tab_users.pressed.connect(_show_users_tab)
	tabs.add_child(btn_tab_users)
	
	btn_tab_vocab = Button.new()
	btn_tab_vocab.text = "Quản lý Từ Vựng (Chỉ xem/Đổi Level)"
	btn_tab_vocab.custom_minimum_size = Vector2(350, 40)
	btn_tab_vocab.pressed.connect(_show_vocab_tab)
	tabs.add_child(btn_tab_vocab)
	
	# Main Content Area
	var main_area = CenterContainer.new()
	main_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_area.offset_top = 140
	add_child(main_area)
	
	# === LEFT: QUẢN LÝ NGƯỜI DÙNG ===
	vbox_user = VBoxContainer.new()
	vbox_user.custom_minimum_size = Vector2(800, 0)
	vbox_user.add_theme_constant_override("separation", 10)
	main_area.add_child(vbox_user)
	
	var btn_fetch_users = Button.new()
	btn_fetch_users.text = "Tải / Làm mới danh sách Users"
	btn_fetch_users.pressed.connect(_fetch_users)
	vbox_user.add_child(btn_fetch_users)
	
	var user_filter = HBoxContainer.new()
	user_search_input = LineEdit.new()
	user_search_input.placeholder_text = "🔍 Tìm Username / Role..."
	user_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	user_search_input.text_changed.connect(_on_user_search_changed)
	user_filter.add_child(user_search_input)
	vbox_user.add_child(user_filter)
	
	var scroll_users = ScrollContainer.new()
	scroll_users.custom_minimum_size = Vector2(0, 400)
	vbox_user.add_child(scroll_users)
	
	users_container = VBoxContainer.new()
	users_container.add_theme_constant_override("separation", 10)
	scroll_users.add_child(users_container)
	
	var user_page_hbox = HBoxContainer.new()
	user_page_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_user_prev = Button.new()
	btn_user_prev.text = "◀ Trước"
	btn_user_prev.pressed.connect(_change_user_page.bind(-1))
	lbl_user_page = Label.new()
	lbl_user_page.text = "1 / 1"
	btn_user_next = Button.new()
	btn_user_next.text = "Sau ▶"
	btn_user_next.pressed.connect(_change_user_page.bind(1))
	user_page_hbox.add_child(btn_user_prev)
	user_page_hbox.add_child(lbl_user_page)
	user_page_hbox.add_child(btn_user_next)
	vbox_user.add_child(user_page_hbox)
	
	# === RIGHT: QUẢN LÝ TỪ VỰNG ===
	vbox_vocab = VBoxContainer.new()
	vbox_vocab.custom_minimum_size = Vector2(800, 0)
	vbox_vocab.add_theme_constant_override("separation", 10)
	main_area.add_child(vbox_vocab)
	
	var vocab_top_bar = HBoxContainer.new()
	vocab_top_bar.add_theme_constant_override("separation", 10)
	vbox_vocab.add_child(vocab_top_bar)
	
	var vocab_level_input = LineEdit.new()
	vocab_level_input.placeholder_text = "Nhập Level (vd: 25)"
	vocab_level_input.custom_minimum_size = Vector2(200, 0)
	vocab_top_bar.add_child(vocab_level_input)
	
	var btn_fetch_vocab = Button.new()
	btn_fetch_vocab.text = "Xem Từ Vựng Level"
	btn_fetch_vocab.pressed.connect(func():
		var lvl = int(vocab_level_input.text)
		if lvl <= 0: lvl = 1
		_fetch_vocabularies_for_level(lvl)
	)
	vocab_top_bar.add_child(btn_fetch_vocab)
	
	var btn_all_vocab = Button.new()
	btn_all_vocab.text = "Tải Toàn Bộ Từ Vựng (JMdict)"
	btn_all_vocab.pressed.connect(func():
		status_label.text = "Đang tải danh sách từ vựng JMdict..."
		api_request("/admin/vocabularies", HTTPClient.METHOD_GET, "", _on_vocab_fetched)
	)
	vocab_top_bar.add_child(btn_all_vocab)
	
	vocab_search_timer = Timer.new()
	vocab_search_timer.one_shot = true
	vocab_search_timer.wait_time = 0.4
	vocab_search_timer.timeout.connect(_on_search_timer_timeout)
	add_child(vocab_search_timer)
	
	var vocab_filter = HBoxContainer.new()
	vocab_search_input = LineEdit.new()
	vocab_search_input.placeholder_text = "🔍 Tìm Tiếng Nhật / Romaji / Nghĩa..."
	vocab_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vocab_search_input.text_changed.connect(_on_vocab_search_changed)
	vocab_filter.add_child(vocab_search_input)
	vbox_vocab.add_child(vocab_filter)
	
	var scroll_vocab = ScrollContainer.new()
	scroll_vocab.custom_minimum_size = Vector2(0, 450)
	vbox_vocab.add_child(scroll_vocab)
	
	vocab_container = VBoxContainer.new()
	vocab_container.add_theme_constant_override("separation", 10)
	scroll_vocab.add_child(vocab_container)
	
	var vocab_page_hbox = HBoxContainer.new()
	vocab_page_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_vocab_prev = Button.new()
	btn_vocab_prev.text = "◀ Trước"
	btn_vocab_prev.pressed.connect(_change_vocab_page.bind(-1))
	lbl_vocab_page = Label.new()
	lbl_vocab_page.text = "1 / 1"
	btn_vocab_next = Button.new()
	btn_vocab_next.text = "Sau ▶"
	btn_vocab_next.pressed.connect(_change_vocab_page.bind(1))
	vocab_page_hbox.add_child(btn_vocab_prev)
	vocab_page_hbox.add_child(lbl_vocab_page)
	vocab_page_hbox.add_child(btn_vocab_next)
	vbox_vocab.add_child(vocab_page_hbox)
	
	_show_users_tab()

func _show_users_tab():
	vbox_user.show()
	vbox_vocab.hide()
	btn_tab_users.modulate = Color(0.4, 1.0, 0.4)
	btn_tab_vocab.modulate = Color(1.0, 1.0, 1.0)
	status_label.text = ""

func _show_vocab_tab():
	vbox_user.hide()
	vbox_vocab.show()
	btn_tab_vocab.modulate = Color(0.4, 1.0, 0.4)
	btn_tab_users.modulate = Color(1.0, 1.0, 1.0)
	status_label.text = ""
	if all_vocabs.is_empty():
		_fetch_vocabularies_for_level(1)

func _on_user_search_changed(t: String):
	current_user_page = 0
	_update_users_ui()

func _change_user_page(dir: int):
	current_user_page += dir
	_update_users_ui()
	
func _on_vocab_search_changed(t: String):
	var q = t.strip_edges()
	if q.is_empty():
		if is_instance_valid(vocab_search_timer):
			vocab_search_timer.stop()
		filtered_vocabs = all_vocabs
		current_vocab_page = 0
		_update_vocab_ui()
		return
	if is_instance_valid(vocab_search_timer):
		vocab_search_timer.start(0.4)

func _on_search_timer_timeout():
	var q = vocab_search_input.text.strip_edges()
	if q.is_empty():
		filtered_vocabs = all_vocabs
		current_vocab_page = 0
		_update_vocab_ui()
		return
		
	status_label.text = "Đang tìm kiếm '%s' trên server..." % q
	api_request("/admin/vocabularies?q=" + q.uri_encode(), HTTPClient.METHOD_GET, "", func(code, body):
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var arr: Array = json.data
				filtered_vocabs = arr
				current_vocab_page = 0
				_update_vocab_ui()
				status_label.text = "Tìm thấy %d từ vựng!" % filtered_vocabs.size()
		else:
			status_label.text = "Lỗi tìm kiếm: " + str(code)
	)

func _change_vocab_page(dir: int):
	current_vocab_page += dir
	_update_vocab_ui()

func _get_headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + Network.jwt_token, "Content-Type: application/json"])

func api_request(endpoint: String, method: int, body_str: String, callback: Callable):
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

# ================= QUẢN LÝ USER =================
func _fetch_users():
	status_label.text = "Đang tải danh sách User..."
	api_request("/admin/users", HTTPClient.METHOD_GET, "", _on_users_fetched)

func _on_users_fetched(code, body):
	if code == 200:
		status_label.text = "Tải Users thành công!"
		var json = JSON.new()
		json.parse(body.get_string_from_utf8())
		var arr: Array = json.data
		arr.sort_custom(_sort_by_id_desc)
		all_users = arr
		current_user_page = 0
		_update_users_ui()
	else:
		status_label.text = "Lỗi tải Users: " + str(code)

func _update_users_ui():
	for c in users_container.get_children():
		c.queue_free()
		
	var filtered = []
	var q = user_search_input.text.strip_edges().to_lower()
	if q.is_empty():
		filtered = all_users
	else:
		for u in all_users:
			var username = u.get("username", "").to_lower()
			var role = u.get("role", "").to_lower()
			if q in username or q in role:
				filtered.append(u)
				
	var total_pages = ceili(float(filtered.size()) / items_per_page)
	if total_pages == 0: total_pages = 1
	if current_user_page >= total_pages: current_user_page = total_pages - 1
	if current_user_page < 0: current_user_page = 0
	
	lbl_user_page.text = "%d / %d" % [current_user_page + 1, total_pages]
	btn_user_prev.disabled = (current_user_page == 0)
	btn_user_next.disabled = (current_user_page >= total_pages - 1)
	
	var start_idx = current_user_page * items_per_page
	var end_idx = min(start_idx + items_per_page, filtered.size())
	
	for i in range(start_idx, end_idx):
		var u = filtered[i]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		
		var lbl = Label.new()
		lbl.text = u["username"] + " (Lv " + str(u.get("level", 1)) + ")"
		lbl.custom_minimum_size = Vector2(150, 0)
		row.add_child(lbl)
		
		var role_opt = OptionButton.new()
		role_opt.add_item("PLAYER")
		role_opt.add_item("SENSEI")
		role_opt.add_item("DESIGNER")
		role_opt.add_item("ADMIN")
		# Set current role
		for opt_idx in range(role_opt.item_count):
			if role_opt.get_item_text(opt_idx) == u.get("role", "PLAYER"):
				role_opt.selected = opt_idx
		row.add_child(role_opt)
		
		var btn_role = Button.new()
		btn_role.text = "Đổi Role"
		btn_role.pressed.connect(func(): _change_user_role(u["id"], role_opt.get_item_text(role_opt.selected)))
		row.add_child(btn_role)
		
		var lvl_edit = LineEdit.new()
		lvl_edit.text = str(u.get("level", 1))
		lvl_edit.custom_minimum_size = Vector2(50, 0)
		row.add_child(lvl_edit)
		
		var btn_lvl = Button.new()
		btn_lvl.text = "Đổi Lv"
		btn_lvl.pressed.connect(func(): _change_user_level(u["id"], int(lvl_edit.text)))
		row.add_child(btn_lvl)
		
		var btn_del = Button.new()
		btn_del.text = "Xóa"
		btn_del.modulate = Color(1.0, 0.4, 0.4)
		btn_del.pressed.connect(func(): _delete_user(u["id"]))
		row.add_child(btn_del)
		
		users_container.add_child(row)

func _change_user_role(id, new_role):
	status_label.text = "Đang đổi role..."
	api_request("/admin/users/%d/role?role=%s" % [id, new_role], HTTPClient.METHOD_PUT, "", func(c, b):
		status_label.text = "Đổi role thành công!" if c == 200 else "Lỗi đổi role"
		_fetch_users()
	)

func _change_user_level(id, new_lvl):
	status_label.text = "Đang đổi level..."
	api_request("/admin/users/%d/level?level=%d" % [id, new_lvl], HTTPClient.METHOD_PUT, "", func(c, b):
		status_label.text = "Đổi level thành công!" if c == 200 else "Lỗi đổi level"
		_fetch_users()
	)

func _delete_user(id):
	status_label.text = "Đang xóa user..."
	api_request("/admin/users/%d" % id, HTTPClient.METHOD_DELETE, "", func(c, b):
		status_label.text = "Xóa user thành công!" if c == 200 else "Lỗi xóa user"
		_fetch_users()
	)

# ================= QUẢN LÝ TỪ VỰNG =================
func _fetch_vocabularies_for_level(level: int):
	status_label.text = "Đang tải danh sách Từ Vựng Level %d..." % level
	api_request("/admin/vocabularies?level=%d" % level, HTTPClient.METHOD_GET, "", func(code, body):
		if code == 200:
			_on_vocab_fetched(code, body)
		else:
			var Curriculum = preload("res://scripts/Curriculum.gd")
			var level_data = Curriculum.get_level(level)
			if level_data.size() > 0:
				status_label.text = "Tải Từ vựng Level %d thành công (Offline)!" % level
				var arr = []
				for v in level_data:
					var new_v = v.duplicate()
					new_v["levelRequired"] = level
					if not new_v.has("wordJp"):
						new_v["wordJp"] = v.get("kana", "")
					arr.append(new_v)
				all_vocabs = arr
				filtered_vocabs = all_vocabs
				current_vocab_page = 0
				_update_vocab_ui()
			else:
				status_label.text = "Lỗi tải Từ vựng: " + str(code)
	)

func _on_vocab_fetched(code, body):
	if code == 200:
		status_label.text = "Tải Từ vựng thành công (Server)!"
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var arr: Array = json.data
			arr.sort_custom(_sort_by_id_desc)
			all_vocabs = arr
			filtered_vocabs = all_vocabs
			current_vocab_page = 0
			if is_instance_valid(vocab_search_input):
				vocab_search_input.text = ""
			_update_vocab_ui()
	else:
		status_label.text = "Lỗi tải Từ vựng: " + str(code)

func _update_vocab_ui():
	for c in vocab_container.get_children():
		c.queue_free()
		
	var total_pages = ceili(float(filtered_vocabs.size()) / items_per_page)
	if total_pages == 0: total_pages = 1
	if current_vocab_page >= total_pages: current_vocab_page = total_pages - 1
	if current_vocab_page < 0: current_vocab_page = 0
	
	lbl_vocab_page.text = "%d / %d" % [current_vocab_page + 1, total_pages]
	btn_vocab_prev.disabled = (current_vocab_page == 0)
	btn_vocab_next.disabled = (current_vocab_page >= total_pages - 1)
	
	var start_idx = current_vocab_page * items_per_page
	var end_idx = min(start_idx + items_per_page, filtered_vocabs.size())
	
	for i in range(start_idx, end_idx):
		var v = filtered_vocabs[i]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		
		var lvl_req = v.get("levelRequired", v.get("level", 1))
		var w_jp = str(v.get("wordJp", "")).strip_edges()
		var kana = str(v.get("kana", "")).strip_edges()
		var rom = str(v.get("romaji", "")).strip_edges()
		var m = str(v.get("meaning", "")).strip_edges()
		
		var display_jp = ""
		if not w_jp.is_empty() and w_jp != kana:
			display_jp = "%s (%s)" % [w_jp, kana]
		elif not kana.is_empty():
			display_jp = "%s (%s)" % [kana, rom] if not rom.is_empty() else kana
		else:
			display_jp = rom
			
		var lbl = Label.new()
		lbl.text = "[Lv%s] %s - %s" % [str(lvl_req), display_jp, m]
		lbl.custom_minimum_size = Vector2(480, 0)
		lbl.clip_text = true
		row.add_child(lbl)
		
		# Chỉ cho phép đổi level nếu từ vựng có ID (tức là được lưu trong Database)
		if v.has("id") and v["id"] != null and int(v["id"]) > 0:
			var lvl_edit = LineEdit.new()
			lvl_edit.text = str(lvl_req)
			lvl_edit.custom_minimum_size = Vector2(80, 0)
			row.add_child(lvl_edit)
			
			var btn_edit = Button.new()
			btn_edit.text = "Lưu Level"
			btn_edit.pressed.connect(func(): _change_vocab_level(v["id"], int(lvl_edit.text)))
			row.add_child(btn_edit)
		else:
			var lbl_dynamic = Label.new()
			lbl_dynamic.text = "(JMdict - Không thể đổi Level)"
			lbl_dynamic.modulate = Color(0.6, 0.6, 0.6)
			row.add_child(lbl_dynamic)
		
		vocab_container.add_child(row)

func _change_vocab_level(id, new_lvl):
	status_label.text = "Đang đổi level từ vựng..."
	api_request("/admin/vocabularies/%d/level?level=%d" % [id, new_lvl], HTTPClient.METHOD_PUT, "", func(c, b):
		status_label.text = "Đổi level thành công! Vui lòng tải lại Level để xem cập nhật." if c == 200 else "Lỗi đổi level"
	)

func _sort_by_id_desc(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("id", 0)) > int(b.get("id", 0))
