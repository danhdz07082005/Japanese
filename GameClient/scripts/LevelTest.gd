extends Control

const Curriculum = preload("res://scripts/Curriculum.gd")

var vocab_data = []
var question_pool = []
var current_q_idx = 0
var score = 0
var passing_score = 8 # Requires 8/10 to pass

var state = "PLAYING" # PLAYING, RESULT, SUMMARY
var current_q = {}
var selected_option = -1

# UI Elements
var bg: ColorRect
var progress_label: Label
var word_label: Label
var prompt_label: Label
var options_container: GridContainer
var btn_submit: Button
var btn_back: Button
var feedback_label: Label

func _ready():
	var level = Global.get_current_level()
	setup_ui()
	
	word_label.text = "Loading data..."
	word_label.show()
	prompt_label.hide()
	options_container.hide()
	btn_submit.hide()
	progress_label.hide()
	
	_fetch_vocab_from_server(level)

func _fetch_vocab_from_server(level: int):
	var level_data = Curriculum.get_level(level)
	if level_data.size() > 0:
		vocab_data = level_data
		_setup_question_pool()
		return
		
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_vocab_fetched.bind(req, level))
	
	var headers = PackedStringArray(["Authorization: Bearer " + Network.jwt_token])
	var user_id = Database.get_account().get("user_id", -1)
	var url = Network.BASE_URL + "/player/vocabularies?level=%d" % level
	if user_id != -1:
		url += "&userId=%d" % user_id
	req.request(url, headers, HTTPClient.METHOD_GET)

func _on_vocab_fetched(result, code, headers, body, req: HTTPRequest, level: int):
	req.queue_free()
	var loaded_successfully = false
	if code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.data
			if typeof(data) == TYPE_ARRAY and data.size() > 0:
				vocab_data = []
				for item in data:
					vocab_data.append({
						"kana": item.get("wordJp", ""),
						"romaji": item.get("romaji", ""),
						"meaning": item.get("meaning", "")
					})
				loaded_successfully = true
				
	if not loaded_successfully:
		vocab_data = [{"kana": "Error", "romaji": "Error"}]

	_setup_question_pool()

func _setup_question_pool():

	var base_pool = vocab_data.duplicate()
	base_pool.shuffle()
	if base_pool.size() > 10:
		base_pool.resize(10)
		
	question_pool = []
	for v in base_pool:
		question_pool.append({"vocab": v, "type": "kana_romaji"})
		question_pool.append({"vocab": v, "type": "meaning"})
		
	question_pool.shuffle()
	passing_score = int(question_pool.size() * 0.8)
		
	progress_label.show()
	next_question()

func setup_ui():
	# Background
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
	
	progress_label = Label.new()
	progress_label.add_theme_font_size_override("font_size", 24)
	progress_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	progress_label.position = Vector2(-200, 20)
	add_child(progress_label)
	
	word_label = Label.new()
	word_label.add_theme_font_size_override("font_size", 120)
	word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	word_label.position.y = 80
	add_child(word_label)
	
	prompt_label = Label.new()
	prompt_label.add_theme_font_size_override("font_size", 30)
	prompt_label.modulate = Color(0.7, 0.7, 0.7)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	prompt_label.position.y = 250
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
	feedback_label.add_theme_font_size_override("font_size", 30)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.set_anchors_preset(Control.PRESET_CENTER)
	feedback_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	feedback_label.custom_minimum_size = Vector2(900, 0)
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.position.y = 50
	feedback_label.hide()
	add_child(feedback_label)

func next_question():
	if current_q_idx >= question_pool.size():
		show_summary()
		return
		
	state = "PLAYING"
	progress_label.text = "Question %d / %d" % [current_q_idx + 1, question_pool.size()]
	
	var q_info = question_pool[current_q_idx]
	var vocab = q_info["vocab"]
	var type_req = q_info["type"]
	
	var correct_ans = ""
	var pool = []
	
	if type_req == "meaning":
		var m = vocab.get("meaning", "")
		if m == "": m = vocab.get("romaji", "N/A")
		correct_ans = m
		for v in vocab_data:
			var vm = v.get("meaning", "")
			if vm == "": vm = v.get("romaji", "N/A")
			if vm != correct_ans and not pool.has(vm): pool.append(vm)
		word_label.text = vocab.get("kana", "")
		prompt_label.text = "Choose the meaning:"
	else:
		var q_type = ["kana_to_romaji", "romaji_to_kana"][randi() % 2]
		if q_type == "kana_to_romaji":
			correct_ans = vocab["romaji"]
			for v in vocab_data:
				if v["romaji"] != correct_ans and not pool.has(v["romaji"]): pool.append(v["romaji"])
			word_label.text = vocab["kana"]
			prompt_label.text = "Choose the reading:"
		else:
			correct_ans = vocab["kana"]
			for v in vocab_data:
				if v["kana"] != correct_ans and not pool.has(v["kana"]): pool.append(v["kana"])
			word_label.text = vocab["romaji"]
			prompt_label.text = "Choose the character:"
		
	pool.shuffle()
	var options = []
	for i in range(min(3, pool.size())):
		options.append(pool[i])
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
		btn.custom_minimum_size = Vector2(400, 100)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", 24)
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
			Global.add_coins(5)
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
	feedback_label.position.y = -50
	
	if score >= passing_score:
		var current_lvl = Global.get_current_level()
		
		var learned = []
		for v in vocab_data:
			if v.has("kana") and v["kana"] != "Error":
				learned.append(v["kana"])
				
		Global.set_current_level(current_lvl + 1, learned)
		feedback_label.text = "CONGRATULATIONS!\nYou scored %d/%d.\nYou reached Level %d!" % [score, question_pool.size(), current_lvl + 1]
		feedback_label.modulate = Color(0.4, 1.0, 0.4)
		Global.add_coins(100)
	else:
		feedback_label.text = "TOO BAD...\nYou scored %d/%d.\nYou need %d to pass.\nPlease study more and try again!" % [score, question_pool.size(), passing_score]
		feedback_label.modulate = Color(1.0, 0.4, 0.4)
		
	btn_submit.text = "Main Menu"
