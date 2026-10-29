extends Control

var list_container: VBoxContainer
var status_label: Label
var create_dialog: AcceptDialog
var title_input: LineEdit
var code_input: LineEdit
var level_input: SpinBox
var coin_input: SpinBox
var attempts_input: SpinBox
var questions_container: VBoxContainer
var current_edit_id: int = -1

var attempts_dialog: AcceptDialog
var attempts_container: VBoxContainer

var all_tests = []
var current_page = 0
var items_per_page = 5

var search_input: LineEdit
var btn_prev: Button
var btn_next: Button
var lbl_page: Label

func _ready():
	_setup_ui()
	_fetch_tests()

func _setup_ui():
	var bg = ColorRect.new()
	bg.color = Color(0.12, 0.15, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var title = Label.new()
	title.text = "CUSTOM TEST MANAGER"
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 40
	add_child(title)
	
	var btn_back = Button.new()
	btn_back.text = "Back"
	btn_back.custom_minimum_size = Vector2(120, 50)
	btn_back.position = Vector2(30, 30)
	btn_back.pressed.connect(func(): Global.goto_scene("res://scenes/Main.tscn"))
	add_child(btn_back)
	
	var btn_create = Button.new()
	btn_create.text = "+ Create New Test"
	btn_create.custom_minimum_size = Vector2(250, 50)
	btn_create.position = Vector2(1280 - 280, 30) # Assuming 1280 width
	btn_create.pressed.connect(_on_create_new_pressed)
	add_child(btn_create)
	
	status_label = Label.new()
	status_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	status_label.position.y = 120
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(status_label)
	
	var filter_hbox = HBoxContainer.new()
	filter_hbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	filter_hbox.position.y = 100
	filter_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(filter_hbox)
	
	search_input = LineEdit.new()
	search_input.custom_minimum_size = Vector2(300, 40)
	search_input.placeholder_text = "🔍 Search by Code / Title..."
	search_input.text_changed.connect(_on_search_changed)
	filter_hbox.add_child(search_input)
	
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 180
	scroll.offset_bottom = -50
	scroll.offset_left = 100
	scroll.offset_right = -100
	add_child(scroll)
	
	list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.add_theme_constant_override("separation", 15)
	scroll.add_child(list_container)
	
	var page_hbox = HBoxContainer.new()
	page_hbox.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	page_hbox.position.y = -50
	page_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	page_hbox.add_theme_constant_override("separation", 20)
	add_child(page_hbox)
	
	btn_prev = Button.new()
	btn_prev.text = "◀ Prev"
	btn_prev.custom_minimum_size = Vector2(80, 40)
	btn_prev.pressed.connect(func(): _change_page(-1))
	page_hbox.add_child(btn_prev)
	
	lbl_page = Label.new()
	lbl_page.text = "1 / 1"
	page_hbox.add_child(lbl_page)
	
	btn_next = Button.new()
	btn_next.text = "Next ▶"
	btn_next.custom_minimum_size = Vector2(80, 40)
	btn_next.pressed.connect(func(): _change_page(1))
	page_hbox.add_child(btn_next)
	
	_setup_dialog()
	_setup_attempts_dialog()

func _setup_attempts_dialog():
	attempts_dialog = AcceptDialog.new()
	attempts_dialog.title = "Attempt History"
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 300)
	
	attempts_container = VBoxContainer.new()
	attempts_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attempts_container.add_theme_constant_override("separation", 10)
	scroll.add_child(attempts_container)
	
	attempts_dialog.add_child(scroll)
	add_child(attempts_dialog)

func _setup_dialog():
	create_dialog = AcceptDialog.new()
	create_dialog.title = "Test Information"
	create_dialog.ok_button_text = "Save"
	create_dialog.confirmed.connect(_on_dialog_confirmed)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	
	title_input = LineEdit.new()
	title_input.placeholder_text = "Test Title (e.g., N5 Test)"
	title_input.custom_minimum_size = Vector2(300, 40)
	vbox.add_child(title_input)
	
	code_input = LineEdit.new()
	code_input.placeholder_text = "Test Code (e.g., TEST-01)"
	code_input.custom_minimum_size = Vector2(300, 40)
	vbox.add_child(code_input)
	
	var hbox_lvl = HBoxContainer.new()
	var lbl_lvl = Label.new()
	lbl_lvl.text = "Min Level:"
	lbl_lvl.custom_minimum_size = Vector2(150, 0)
	hbox_lvl.add_child(lbl_lvl)
	level_input = SpinBox.new()
	level_input.min_value = 1
	level_input.max_value = 24
	hbox_lvl.add_child(level_input)
	vbox.add_child(hbox_lvl)
	
	var hbox1 = HBoxContainer.new()
	var lbl1 = Label.new()
	lbl1.text = "G-Coin Reward:"
	lbl1.custom_minimum_size = Vector2(150, 0)
	hbox1.add_child(lbl1)
	coin_input = SpinBox.new()
	coin_input.max_value = 10000
	hbox1.add_child(coin_input)
	vbox.add_child(hbox1)
	
	var hbox2 = HBoxContainer.new()
	var lbl2 = Label.new()
	lbl2.text = "Max Attempts (<10):"
	lbl2.custom_minimum_size = Vector2(150, 0)
	hbox2.add_child(lbl2)
	attempts_input = SpinBox.new()
	attempts_input.min_value = 1
	attempts_input.max_value = 9
	attempts_input.value = 1
	hbox2.add_child(attempts_input)
	vbox.add_child(hbox2)
	
	var q_label = Label.new()
	q_label.text = "Question List:"
	vbox.add_child(q_label)
	
	var q_scroll = ScrollContainer.new()
	q_scroll.custom_minimum_size = Vector2(500, 200)
	vbox.add_child(q_scroll)
	
	questions_container = VBoxContainer.new()
	questions_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_scroll.add_child(questions_container)
	
	var btn_add_q = Button.new()
	btn_add_q.text = "+ Add Question"
	btn_add_q.pressed.connect(_add_question_row)
	vbox.add_child(btn_add_q)
	
	create_dialog.add_child(vbox)
	add_child(create_dialog)

func _add_question_row(q_data: Dictionary = {}):
	var panel = PanelContainer.new()
	var q_style = StyleBoxFlat.new()
	q_style.bg_color = Color(0.2, 0.22, 0.25)
	q_style.corner_radius_top_left = 5
	q_style.corner_radius_bottom_right = 5
	q_style.corner_radius_top_right = 5
	q_style.corner_radius_bottom_left = 5
	q_style.content_margin_left = 10
	q_style.content_margin_top = 10
	q_style.content_margin_right = 10
	q_style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", q_style)
	
	var q_vbox = VBoxContainer.new()
	panel.add_child(q_vbox)
	
	var row1 = HBoxContainer.new()
	var q_input = LineEdit.new()
	q_input.placeholder_text = "Question content"
	q_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_input.text = q_data.get("questionText", "")
	row1.add_child(q_input)
	
	var btn_del_q = Button.new()
	btn_del_q.text = "Delete"
	btn_del_q.modulate = Color(1.0, 0.4, 0.4)
	btn_del_q.pressed.connect(func(): panel.queue_free())
	row1.add_child(btn_del_q)
	q_vbox.add_child(row1)
	
	var row2 = HBoxContainer.new()
	var a_input = LineEdit.new()
	a_input.placeholder_text = "Answer A"
	a_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a_input.text = q_data.get("answerA", "")
	row2.add_child(a_input)
	
	var b_input = LineEdit.new()
	b_input.placeholder_text = "Answer B"
	b_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_input.text = q_data.get("answerB", "")
	row2.add_child(b_input)
	q_vbox.add_child(row2)
	
	var row3 = HBoxContainer.new()
	var c_input = LineEdit.new()
	c_input.placeholder_text = "Answer C"
	c_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c_input.text = q_data.get("answerC", "")
	row3.add_child(c_input)
	
	var d_input = LineEdit.new()
	d_input.placeholder_text = "Answer D"
	d_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d_input.text = q_data.get("answerD", "")
	row3.add_child(d_input)
	q_vbox.add_child(row3)
	
	var row4 = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = "Correct Answer:"
	row4.add_child(lbl)
	
	var correct_input = OptionButton.new()
	correct_input.add_item("A", 0)
	correct_input.add_item("B", 1)
	correct_input.add_item("C", 2)
	correct_input.add_item("D", 3)
	
	var correct = q_data.get("correctAnswer", "A")
	if correct == "A": correct_input.selected = 0
	elif correct == "B": correct_input.selected = 1
	elif correct == "C": correct_input.selected = 2
	elif correct == "D": correct_input.selected = 3
	else: correct_input.selected = 0
	
	row4.add_child(correct_input)
	q_vbox.add_child(row4)
	
	# Metadata for saving later
	panel.set_meta("q_input", q_input)
	panel.set_meta("a_input", a_input)
	panel.set_meta("b_input", b_input)
	panel.set_meta("c_input", c_input)
	panel.set_meta("d_input", d_input)
	panel.set_meta("correct_input", correct_input)
	
	questions_container.add_child(panel)

func _fetch_tests():
	status_label.text = "Loading data..."
	for child in list_container.get_children():
		child.queue_free()
		
	var user_id = Database.get_account().get("user_id", -1)
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_fetch_completed.bind(req))
	
	var headers = PackedStringArray(["Authorization: Bearer " + Network.jwt_token])
	req.request(Network.BASE_URL + "/sensei/%d/custom-tests" % user_id, headers, HTTPClient.METHOD_GET)

func _on_fetch_completed(res, code, headers, body, req: HTTPRequest):
	req.queue_free()
	if code == 200:
		status_label.text = ""
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var arr: Array = json.data
			arr.sort_custom(_sort_by_id_desc)
			all_tests = arr
			current_page = 0
			_update_list_ui()
	else:
		status_label.text = "Error loading data: " + str(code)

func _on_search_changed(new_text: String):
	current_page = 0
	_update_list_ui()

func _change_page(dir: int):
	current_page += dir
	_update_list_ui()

func _update_list_ui():
	for child in list_container.get_children():
		child.queue_free()
		
	var filtered = []
	var q = search_input.text.strip_edges().to_lower()
	if q.is_empty():
		filtered = all_tests
	else:
		for test in all_tests:
			var test_code = test.get("testCode", "").to_lower()
			var title = test.get("title", "").to_lower()
			if q in test_code or q in title:
				filtered.append(test)
				
	if filtered.is_empty():
		status_label.text = "No matching tests found."
		btn_prev.disabled = true
		btn_next.disabled = true
		lbl_page.text = "0 / 0"
		return
		
	status_label.text = ""
	var total_pages = ceili(float(filtered.size()) / items_per_page)
	if current_page >= total_pages: current_page = total_pages - 1
	if current_page < 0: current_page = 0
	
	lbl_page.text = "%d / %d" % [current_page + 1, total_pages]
	btn_prev.disabled = (current_page == 0)
	btn_next.disabled = (current_page == total_pages - 1)
	
	var start_idx = current_page * items_per_page
	var end_idx = min(start_idx + items_per_page, filtered.size())
	
	for i in range(start_idx, end_idx):
		_add_test_item(filtered[i])

func _add_test_item(item: Dictionary):
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.25, 0.35)
	style.corner_radius_top_left = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	panel.add_theme_stylebox_override("panel", style)
	
	var hbox = HBoxContainer.new()
	panel.add_child(hbox)
	
	var info = Label.new()
	info.text = "Code: %s | %s (Min Lv: %d)\nReward: %d G-Coin | Max: %d attempts" % [item.get("testCode", "N/A"), item.get("title", ""), int(item.get("minLevel", 1)), int(item.get("rewardGcoin", 0)), int(item.get("maxAttempts", 0))]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)
	
	var btn_view = Button.new()
	btn_view.text = "History"
	btn_view.custom_minimum_size = Vector2(80, 0)
	btn_view.modulate = Color(0.4, 1.0, 0.4)
	btn_view.pressed.connect(_on_view_attempts_pressed.bind(item))
	hbox.add_child(btn_view)
	
	var btn_edit = Button.new()
	btn_edit.text = "Edit"
	btn_edit.custom_minimum_size = Vector2(80, 0)
	btn_edit.pressed.connect(_on_edit_pressed.bind(item))
	hbox.add_child(btn_edit)
	
	var btn_del = Button.new()
	btn_del.text = "Delete"
	btn_del.custom_minimum_size = Vector2(80, 0)
	btn_del.modulate = Color(1.0, 0.4, 0.4)
	btn_del.pressed.connect(_on_delete_pressed.bind(item["id"]))
	hbox.add_child(btn_del)
	
	list_container.add_child(panel)

func _on_view_attempts_pressed(item: Dictionary):
	var test_id = item["id"]
	var total_q = item.get("questions", []).size()
	
	for child in attempts_container.get_children():
		child.queue_free()
		
	var lbl = Label.new()
	lbl.text = "Loading data..."
	attempts_container.add_child(lbl)
	attempts_dialog.popup_centered()
	
	var user_id = Database.get_account().get("user_id", -1)
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, hdrs, body):
		req.queue_free()
		for child in attempts_container.get_children():
			child.queue_free()
			
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var attempts = json.data
				if attempts.is_empty():
					var empty_lbl = Label.new()
					empty_lbl.text = "No attempts yet."
					attempts_container.add_child(empty_lbl)
				else:
					for attempt in attempts:
						var a_lbl = Label.new()
						var status = "✅ PASS" if attempt.get("passed", false) else "❌ FAIL"
						a_lbl.text = "- Player: %s | Correct: %d/%d | %s | %s" % [attempt.get("playerName", "Unknown"), attempt.get("score", 0), total_q, status, attempt.get("attemptTime", "").substr(0, 10)]
						attempts_container.add_child(a_lbl)
			else:
				var err = Label.new()
				err.text = "Data parsing error"
				attempts_container.add_child(err)
		else:
			var err = Label.new()
			err.text = "Error fetching data: " + str(code)
			attempts_container.add_child(err)
	)
	var headers = PackedStringArray(["Authorization: Bearer " + Network.jwt_token])
	req.request(Network.BASE_URL + "/sensei/%d/tests/%d/attempts" % [user_id, test_id], headers, HTTPClient.METHOD_GET)

func _sort_by_id_desc(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("id", 0)) > int(b.get("id", 0))

func _on_create_new_pressed():
	current_edit_id = -1
	title_input.text = ""
	code_input.text = ""
	level_input.value = 1
	coin_input.value = 100
	attempts_input.value = 1
	for child in questions_container.get_children():
		child.queue_free()
	_add_question_row()
	create_dialog.popup_centered()

func _on_edit_pressed(item: Dictionary):
	current_edit_id = item["id"]
	title_input.text = item.get("title", "")
	code_input.text = item.get("testCode", "")
	level_input.value = item.get("minLevel", 1)
	coin_input.value = item.get("rewardGcoin", 100)
	attempts_input.value = item.get("maxAttempts", 1)
	
	for child in questions_container.get_children():
		child.queue_free()
		
	var questions = item.get("questions", [])
	if questions.is_empty():
		_add_question_row()
	else:
		for q in questions:
			_add_question_row(q)
			
	create_dialog.popup_centered()

func _on_dialog_confirmed():
	var title_val = title_input.text.strip_edges()
	var code_val = code_input.text.strip_edges()
	if title_val.is_empty() or code_val.is_empty():
		return
		
	var user_id = Database.get_account().get("user_id", -1)
	
	var questions_data = []
	for panel in questions_container.get_children():
		if panel.has_meta("q_input"):
			var q_text = panel.get_meta("q_input").text.strip_edges()
			var a_text = panel.get_meta("a_input").text.strip_edges()
			var b_text = panel.get_meta("b_input").text.strip_edges()
			var c_text = panel.get_meta("c_input").text.strip_edges()
			var d_text = panel.get_meta("d_input").text.strip_edges()
			var correct_idx = panel.get_meta("correct_input").selected
			
			var correct_letter = "A"
			if correct_idx == 1: correct_letter = "B"
			elif correct_idx == 2: correct_letter = "C"
			elif correct_idx == 3: correct_letter = "D"
			
			if not q_text.is_empty():
				questions_data.append({
					"questionText": q_text,
					"answerA": a_text,
					"answerB": b_text,
					"answerC": c_text,
					"answerD": d_text,
					"correctAnswer": correct_letter
				})
	
	var body_dict = {
		"title": title_val,
		"testCode": code_val,
		"minLevel": int(level_input.value),
		"rewardGcoin": int(coin_input.value),
		"maxAttempts": int(attempts_input.value),
		"questions": questions_data
	}
	
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_save_completed.bind(req))
	
	var headers = PackedStringArray(["Authorization: Bearer " + Network.jwt_token, "Content-Type: application/json"])
	var body_str = JSON.stringify(body_dict)
	
	if current_edit_id == -1:
		req.request(Network.BASE_URL + "/sensei/%d/custom-tests" % user_id, headers, HTTPClient.METHOD_POST, body_str)
	else:
		req.request(Network.BASE_URL + "/sensei/%d/custom-tests/%d" % [user_id, current_edit_id], headers, HTTPClient.METHOD_PUT, body_str)

func _on_save_completed(res, code, headers, body, req: HTTPRequest):
	req.queue_free()
	if code == 200:
		_fetch_tests()
	else:
		status_label.text = "Error saving data: " + str(code)

func _on_delete_pressed(id: int):
	var user_id = Database.get_account().get("user_id", -1)
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, hdrs, bdy):
		req.queue_free()
		_fetch_tests()
	)
	var headers = PackedStringArray(["Authorization: Bearer " + Network.jwt_token])
	req.request(Network.BASE_URL + "/sensei/%d/custom-tests/%d" % [user_id, id], headers, HTTPClient.METHOD_DELETE)
