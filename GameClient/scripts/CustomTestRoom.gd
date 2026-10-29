extends Control

var question_pool = []
var current_q_idx = 0
var score = 0
var passing_score = 0
var test_data = {}

var state = "PLAYING"
var current_q = {}
var selected_option = -1

var bg: ColorRect
var title_label: Label
var progress_label: Label
var word_label: Label
var prompt_label: Label
var options_container: GridContainer
var btn_submit: Button
var btn_back: Button
var feedback_label: Label

func _ready():
	test_data = Global.current_custom_test
	question_pool = test_data.get("questions", [])
	passing_score = question_pool.size() # Pass if 100% correct
	
	setup_ui()
	if question_pool.is_empty():
		OS.alert("This test has no questions!", "Error")
		Global.goto_scene("res://scenes/Main.tscn")
		return
		
	next_question()

func setup_ui():
	bg = ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	btn_back = Button.new()
	btn_back.text = "Cancel & Main Menu"
	btn_back.position = Vector2(20, 20)
	btn_back.custom_minimum_size = Vector2(200, 40)
	btn_back.pressed.connect(func(): Global.goto_scene("res://scenes/Main.tscn"))
	add_child(btn_back)
	
	title_label = Label.new()
	title_label.text = test_data.get("title", "Test")
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_label.position.y = 20
	add_child(title_label)
	
	progress_label = Label.new()
	progress_label.add_theme_font_size_override("font_size", 24)
	progress_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	progress_label.position = Vector2(-200, 20)
	add_child(progress_label)
	
	word_label = Label.new()
	word_label.add_theme_font_size_override("font_size", 80)
	word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	word_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	word_label.position.y = 100
	add_child(word_label)
	
	prompt_label = Label.new()
	prompt_label.add_theme_font_size_override("font_size", 30)
	prompt_label.modulate = Color(0.7, 0.7, 0.7)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	prompt_label.position.y = 280
	add_child(prompt_label)
	
	options_container = GridContainer.new()
	options_container.columns = 2
	options_container.set_anchors_preset(Control.PRESET_CENTER)
	options_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	options_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	options_container.add_theme_constant_override("h_separation", 30)
	options_container.add_theme_constant_override("v_separation", 30)
	options_container.position.y = 100
	add_child(options_container)
	
	btn_submit = Button.new()
	btn_submit.text = "Confirm"
	btn_submit.custom_minimum_size = Vector2(200, 60)
	btn_submit.add_theme_font_size_override("font_size", 24)
	btn_submit.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	btn_submit.grow_horizontal = Control.GROW_DIRECTION_BOTH
	btn_submit.position.y = -80
	btn_submit.pressed.connect(_on_submit_pressed)
	add_child(btn_submit)
	
	feedback_label = Label.new()
	feedback_label.add_theme_font_size_override("font_size", 40)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	feedback_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	feedback_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	feedback_label.hide()
	add_child(feedback_label)

func next_question():
	if current_q_idx >= question_pool.size():
		show_summary()
		return
		
	state = "PLAYING"
	progress_label.text = "Question %d / %d" % [current_q_idx + 1, question_pool.size()]
	
	var q_data = question_pool[current_q_idx]
	word_label.text = q_data.get("questionText", "")
	prompt_label.text = "Choose the correct answer:"
	
	var correct_letter = q_data.get("correctAnswer", "A")
	var correct_ans = q_data.get("answer" + correct_letter, "")
	
	var options = []
	if q_data.has("answerA") and not q_data["answerA"].is_empty(): options.append(q_data["answerA"])
	if q_data.has("answerB") and not q_data["answerB"].is_empty(): options.append(q_data["answerB"])
	if q_data.has("answerC") and not q_data["answerC"].is_empty(): options.append(q_data["answerC"])
	if q_data.has("answerD") and not q_data["answerD"].is_empty(): options.append(q_data["answerD"])
	
	# Nếu không có đáp án nhiễu, tạo bừa từ các câu khác
	if options.is_empty() or (options.size() == 1 and options[0] == correct_ans):
		options = [correct_ans]
		var fake_pool = []
		for q in question_pool:
			if q.get("correctAnswer", "") != correct_ans:
				fake_pool.append(q.get("correctAnswer", ""))
		fake_pool.shuffle()
		for i in range(min(3, fake_pool.size())):
			options.append(fake_pool[i])
			
	if not options.has(correct_ans):
		options.append(correct_ans)
		
	options.shuffle()
	
	current_q = {
		"correct": correct_ans,
		"options": options
	}
	
	for child in options_container.get_children():
		child.queue_free()
		
	selected_option = -1
	
	for i in range(options.size()):
		var btn = Button.new()
		btn.text = options[i]
		btn.custom_minimum_size = Vector2(250, 80)
		btn.add_theme_font_size_override("font_size", 30)
		btn.pressed.connect(_on_option_pressed.bind(i))
		options_container.add_child(btn)
		
	word_label.show()
	prompt_label.show()
	options_container.show()
	
	btn_submit.text = "Confirm"
	btn_submit.disabled = true
	btn_submit.show()
	
	feedback_label.hide()

func _on_option_pressed(idx: int):
	if state != "PLAYING": return
	selected_option = idx
	btn_submit.disabled = false
	
	var i = 0
	for btn in options_container.get_children():
		if i == idx:
			btn.modulate = Color(0.5, 0.8, 1.0)
		else:
			btn.modulate = Color.WHITE
		i += 1

func _on_submit_pressed():
	if state == "PLAYING":
		var is_correct = (current_q["options"][selected_option] == current_q["correct"])
		
		if is_correct:
			score += 1
			feedback_label.text = "Correct!"
			feedback_label.modulate = Color(0.4, 1.0, 0.4)
		else:
			feedback_label.text = "Wrong! Answer: " + current_q["correct"]
			feedback_label.modulate = Color(1.0, 0.4, 0.4)
			
		state = "RESULT"
		word_label.hide()
		prompt_label.hide()
		options_container.hide()
		
		btn_submit.text = "Next"
		feedback_label.show()
		
	elif state == "RESULT":
		current_q_idx += 1
		next_question()
		
	elif state == "SUMMARY":
		Global.goto_scene("res://scenes/Main.tscn")

func show_summary():
	state = "SUMMARY"
	word_label.hide()
	prompt_label.hide()
	options_container.hide()
	progress_label.hide()
	btn_back.hide()
	
	feedback_label.show()
	
	var passed = (score >= passing_score and passing_score > 0)
	var reward = test_data.get("rewardGcoin", 0)
	
	if passed:
		feedback_label.text = "CONGRATULATIONS!\nYou scored a perfect %d/%d.\nSubmitting results to server..." % [score, question_pool.size()]
		feedback_label.modulate = Color(0.4, 1.0, 0.4)
	else:
		feedback_label.text = "TOO BAD...\nYou scored %d/%d.\nRecording attempt..." % [score, question_pool.size()]
		feedback_label.modulate = Color(1.0, 0.4, 0.4)
		
	btn_submit.hide()
	
	var user_id = Database.get_account().get("user_id", -1)
	var test_code = test_data.get("testCode", "")
	
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, hdrs, body):
		req.queue_free()
		btn_submit.show()
		btn_submit.text = "Main Menu"
		
		if code == 200:
			if passed and reward > 0:
				feedback_label.text = "CONGRATULATIONS!\nYou scored a perfect %d/%d.\nYou received %d G-Coins!" % [score, question_pool.size(), reward]
				# Cập nhật số dư locally
				var json = JSON.new()
				if json.parse(body.get_string_from_utf8()) == OK:
					var new_gcoin = json.data.get("gcoin", Database.get_account().get("g_coin_balance", 0))
					Database.update_account("g_coin_balance", new_gcoin)
					# Không gọi add_coins vì API đã update trên server, ta chỉ sync UI
					# Nhưng để update UI nhanh ta có thể hack nhỏ
					Global.emit_signal("coins_changed", new_gcoin)
			elif not passed:
				feedback_label.text = "TOO BAD...\nYou scored %d/%d.\nYou need 100%% (%d questions) to get the reward.\nBetter luck next time!" % [score, question_pool.size(), passing_score]
		else:
			feedback_label.text = "Error saving results! (Error code: %d)" % code
	)
	
	var body_dict = {
		"score": score,
		"passed": passed
	}
	var body_str = JSON.stringify(body_dict)
	var headers = PackedStringArray(["Authorization: Bearer " + Network.jwt_token, "Content-Type: application/json"])
	req.request(Network.BASE_URL + "/player/%d/custom-tests/%s/submit" % [user_id, test_code], headers, HTTPClient.METHOD_POST, body_str)
