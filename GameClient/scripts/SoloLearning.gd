extends Control

const Curriculum = preload("res://scripts/Curriculum.gd")

var vocab_data = []
var current_idx = 0
var state = "READING" # READING, WRITING, SUMMARY

var word_label: Label
var romaji_label: Label
var draw_prompt: Label
var btn_next: Button
var draw_canvas: Control
var tool_container: HBoxContainer

var kanjivg_data = {}
var stroke_cache = {}
var bg_strokes = []
var bg_lines = []
var active_line: Line2D = null
var trace_handle: Node2D = null
var current_stroke_idx = 0
var current_stroke_progress = 0
var active_stroke_points = []
var is_tracing = false
var trace_tolerance = 45.0
var current_stroke_width = 16.0

func _ready():
	var level = Global.get_current_level()
	if Global.get("solo_target_level") != null:
		level = Global.solo_target_level
	setup_ui()
	_load_kanjivg()
	
	word_label.text = "Loading data..."
	word_label.add_theme_font_size_override("font_size", 60)
	word_label.modulate = Color.WHITE
	romaji_label.hide()
	
	_fetch_vocab_from_server(level)

func _has_kanji(text: String) -> bool:
	for c in text:
		var code = c.unicode_at(0)
		if code >= 0x4E00 and code <= 0x9FAF:
			return true
	return false

func _populate_vocab_data(items: Array):
	vocab_data = []
	for item in items:
		var w_jp = str(item.get("wordJp", "")).strip_edges()
		var k = str(item.get("kana", "")).strip_edges()
		var rom = str(item.get("romaji", "")).strip_edges()
		var m = str(item.get("meaning", "")).strip_edges()
		if w_jp.is_empty(): w_jp = k
		if k.is_empty(): k = w_jp
		vocab_data.append({"wordJp": w_jp, "kana": k, "romaji": rom, "meaning": m})

func _fetch_vocab_from_server(level: int):
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_vocab_fetched.bind(req, level))
	
	var headers = PackedStringArray()
	if not Network.jwt_token.is_empty():
		headers.append("Authorization: Bearer " + Network.jwt_token)
	var user_id = Database.get_account().get("user_id", -1)
	var url = Network.BASE_URL + "/player/vocabularies?level=%d" % level
	if user_id != -1:
		url += "&userId=%d" % user_id
	var err = req.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		_fallback_to_curriculum(level)

func _on_vocab_fetched(result, code, headers, body, req: HTTPRequest, level: int):
	req.queue_free()
	if code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.data
			if typeof(data) == TYPE_ARRAY and data.size() > 0:
				_populate_vocab_data(data)
				show_reading_phase()
				return
				
	_fallback_to_curriculum(level)

func _fallback_to_curriculum(level: int):
	var level_data = Curriculum.get_level(level)
	if level_data.size() > 0:
		_populate_vocab_data(level_data)
		show_reading_phase()
		return
		
	vocab_data = [{"wordJp": "Error", "kana": "Error", "romaji": "Failed to fetch from server", "meaning": ""}]
	show_reading_phase()

func setup_ui():
	var bg = ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	draw_canvas = Control.new()
	draw_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draw_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	draw_canvas.gui_input.connect(_on_canvas_gui_input)
	add_child(draw_canvas)
	
	var btn_back = Button.new()
	btn_back.text = "Back to Menu"
	btn_back.position = Vector2(20, 20)
	btn_back.custom_minimum_size = Vector2(150, 40)
	btn_back.pressed.connect(func(): Global.goto_scene("res://scenes/Main.tscn"))
	add_child(btn_back)
	
	var btn_skip = Button.new()
	btn_skip.text = "Skip ⏭️"
	btn_skip.anchor_left = 1.0
	btn_skip.anchor_right = 1.0
	btn_skip.anchor_top = 0.0
	btn_skip.anchor_bottom = 0.0
	btn_skip.offset_left = -170
	btn_skip.offset_right = -20
	btn_skip.offset_top = 20
	btn_skip.offset_bottom = 60
	btn_skip.custom_minimum_size = Vector2(150, 40)
	btn_skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btn_skip.pressed.connect(_skip_vocab)
	add_child(btn_skip)
	
	word_label = Label.new()
	word_label.add_theme_font_size_override("font_size", 200)
	word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	word_label.set_anchors_preset(Control.PRESET_CENTER)
	word_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	word_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	word_label.position.y = -50
	add_child(word_label)
	
	romaji_label = Label.new()
	romaji_label.add_theme_font_size_override("font_size", 32)
	romaji_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	romaji_label.offset_left = 50
	romaji_label.offset_top = 80
	romaji_label.offset_right = -200 # Avoid overlapping with Skip button
	romaji_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	romaji_label.modulate = Color(0.6, 0.8, 1.0)
	add_child(romaji_label)
	
	draw_prompt = Label.new()
	draw_prompt.text = "Trace the character"
	draw_prompt.add_theme_font_size_override("font_size", 36)
	draw_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draw_prompt.set_anchors_preset(Control.PRESET_TOP_WIDE)
	draw_prompt.position.y = 80
	draw_prompt.modulate = Color.WHITE
	draw_prompt.hide()
	add_child(draw_prompt)
	
	tool_container = HBoxContainer.new()
	tool_container.hide()
	add_child(tool_container)
	
	btn_next = Button.new()
	btn_next.text = "Start Tracing"
	btn_next.custom_minimum_size = Vector2(250, 60)
	btn_next.add_theme_font_size_override("font_size", 24)
	btn_next.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	btn_next.grow_horizontal = Control.GROW_DIRECTION_BOTH
	btn_next.position.y = -100
	btn_next.pressed.connect(_on_next_pressed)
	add_child(btn_next)

func show_reading_phase():
	state = "READING"
	draw_canvas.hide()
	tool_container.hide()
	draw_prompt.hide()
	
	var vocab = vocab_data[current_idx]
	var target_word = str(vocab.get("wordJp", vocab.get("kana", ""))).strip_edges()
	var kana = str(vocab.get("kana", "")).strip_edges()
	var rom = str(vocab.get("romaji", "")).strip_edges()
	var m = str(vocab.get("meaning", "")).strip_edges()
	if target_word.is_empty(): target_word = kana
	
	if target_word.length() > 4:
		word_label.add_theme_font_size_override("font_size", 100)
	elif target_word.length() > 2:
		word_label.add_theme_font_size_override("font_size", 140)
	else:
		word_label.add_theme_font_size_override("font_size", 200)
		
	word_label.text = target_word
	word_label.modulate = Color.WHITE
	
	if target_word != kana and not kana.is_empty():
		romaji_label.text = "Reading: %s (%s)" % [kana, rom]
	else:
		romaji_label.text = "Reading: " + rom
	if not m.is_empty():
		romaji_label.text += "\nMeaning: " + m
	romaji_label.show()
	romaji_label.modulate = Color(0.6, 0.8, 1.0)
	
	btn_next.show()
	btn_next.text = "Start Tracing"

func show_writing_phase():
	state = "WRITING"
	word_label.modulate = Color(1, 1, 1, 0.0) # Hide text, show only paths
	romaji_label.hide()
	
	draw_canvas.show()
	tool_container.hide() # Tracing doesn't need pen/eraser tools
	draw_prompt.show()
	draw_prompt.text = "Trace the word"
	draw_prompt.modulate = Color.WHITE
	
	btn_next.hide()
	btn_next.text = "Continue ⏭️"
	_start_tracing_mode()

func show_summary():
	state = "SUMMARY"
	draw_canvas.hide()
	tool_container.hide()
	draw_prompt.hide()
	
	word_label.text = "Completed Level " + str(Global.get_current_level()) + "!"
	word_label.add_theme_font_size_override("font_size", 60)
	word_label.modulate = Color.WHITE
	
	romaji_label.text = "Take the Level-up Test to unlock the next level."
	romaji_label.show()
	
	btn_next.text = "Main Menu"
	btn_next.show()

func _skip_vocab():
	current_idx += 1
	if current_idx >= vocab_data.size():
		show_summary()
	else:
		show_reading_phase()

func _on_next_pressed():
	if state == "READING":
		show_writing_phase()
	elif state == "WRITING":
		current_idx += 1
		if current_idx >= vocab_data.size():
			show_summary()
		else:
			show_reading_phase()
	elif state == "SUMMARY":
		Global.goto_scene("res://scenes/Main.tscn")

func _load_kanjivg():
	if not Global.kanjivg_data.is_empty():
		kanjivg_data = Global.kanjivg_data
		stroke_cache = Global.stroke_cache
		return
		
	if not FileAccess.file_exists("res://kanjivg_paths.json"):
		print("SoloLearning: res://kanjivg_paths.json not found!")
		return
	var file = FileAccess.open("res://kanjivg_paths.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			Global.kanjivg_data = json.data
			Global.stroke_cache = stroke_cache
			kanjivg_data = Global.kanjivg_data
			print("SoloLearning: Loaded %d characters from kanjivg_paths.json" % kanjivg_data.size())

func _get_strokes_for_character(c: String) -> Array:
	if c.is_empty():
		return []
		
	# 0. Normalize full-width characters
	var code = c.unicode_at(0)
	if code >= 0xFF01 and code <= 0xFF5E:
		c = char(code - 0xFEE0)
		code = c.unicode_at(0)
	elif code == 0x3000:
		c = " "
		
	if stroke_cache.has(c):
		return stroke_cache[c]
		
	var strokes: Array = []
	
	# 1. Fast in-memory lookup from pre-parsed KanjiVG data (O(1))
	if kanjivg_data.has(c):
		strokes = kanjivg_data[c]
	# 2. Circle fallback for ○ (0x25CB)
	elif c == "○":
		strokes.append("M54.5,15.5 C40,15.5 25,25 25,54.5 C25,84 40,93.5 54.5,93.5 C69,93.5 84,84 84,54.5 C84,25 69,15.5 54.5,15.5")
	# 3. Ditto fallback for 〃 (0x3003)
	elif c == "〃" or code == 0x3003:
		strokes.append("M35,75 L45,65")
		strokes.append("M55,75 L65,65")
	# 4. Tilde with underline fallback for ~ / 〜 / ～ (0x301C, 0xFF5E)
	elif c == "~" or c == "〜" or c == "～" or code == 0x301C or code == 0xFF5E:
		strokes.append("M20,40 C35,25 45,55 60,40 C75,25 85,45 88,40")
		strokes.append("M18,80 L90,80")
	# 5. Prolonged sound mark fallback for ー / ― / — (0x30FC)
	elif c == "ー" or c == "―" or c == "—" or code == 0x30FC:
		strokes.append("M15,54.5 L94,54.5")
		
	# 6. Fallback to individual SVG files in res://kanji/{hex}.svg if not in JSON
	if strokes.is_empty():
		var hex_str = "%05x" % code
		var svg_path = "res://kanji/%s.svg" % hex_str
		if FileAccess.file_exists(svg_path):
			var sf = FileAccess.open(svg_path, FileAccess.READ)
			if sf:
				var xml = sf.get_as_text()
				var re = RegEx.new()
				re.compile('<path[^>]*d="([^"]+)"')
				var matches = re.search_all(xml)
				for m in matches:
					strokes.append(m.get_string(1))
				
	if strokes.size() > 0:
		stroke_cache[c] = strokes
		return strokes
		
	return []

func _start_tracing_mode():
	current_stroke_idx = 0
	current_stroke_progress = 0
	active_stroke_points.clear()
	is_tracing = false
	bg_strokes.clear()
	
	var vocab = str(vocab_data[current_idx].get("wordJp", vocab_data[current_idx].get("kana", ""))).strip_edges()
	if vocab.is_empty():
		vocab = str(vocab_data[current_idx].get("kana", ""))
	
	draw_prompt.text = "Trace the word"
	draw_prompt.modulate = Color.WHITE
	btn_next.hide()
	btn_next.text = "Continue ⏭️"
	
	var max_scale = 4.0
	var screen_width = get_viewport_rect().size.x - 200.0
	var required_width = max(1.0, vocab.length() * 109.0 + (vocab.length() - 1) * 20.0)
	var scale_factor = min(max_scale, screen_width / required_width)
	
	current_stroke_width = 36.0 * (scale_factor / max_scale)
	trace_tolerance = max(6.0, current_stroke_width * 0.6)
	
	var char_size = 109.0 * scale_factor
	var spacing = 20.0 * (scale_factor / max_scale)
	var total_width = vocab.length() * char_size + (vocab.length() - 1) * spacing
	
	var center = get_viewport_rect().size / 2.0
	var start_x = center.x - total_width / 2.0
	var start_y = center.y - char_size / 2.0
	
	for i in range(vocab.length()):
		var char_to_trace = vocab[i]
		var char_offset = Vector2(start_x + i * (char_size + spacing), start_y)
		var paths = _get_strokes_for_character(char_to_trace)
		for path_str in paths:
			var curve = parse_svg_path(path_str)
			# FIX 1: Use get_baked_points() with a small interval so straight lines 
			# also have dense, evenly spaced points every ~2 pixels in SVG space.
			curve.bake_interval = 2.0
			var baked = curve.get_baked_points()
			var final_points = []
			for pt in baked:
				final_points.append(pt * scale_factor + char_offset)
			if final_points.size() > 0:
				bg_strokes.append(final_points)
				
	_init_trace_lines()

func parse_svg_path(path_str: String) -> Curve2D:
	var curve = Curve2D.new()
	var regex = RegEx.new()
	regex.compile("([A-Za-z])|(-?[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?)")
	var matches = regex.search_all(path_str)
	
	var i = 0
	var cmd = ""
	var current_pos = Vector2()
	var prev_ctrl_offset = Vector2()
	
	while i < matches.size():
		var m = matches[i].get_string()
		if m.length() == 1 and ((m >= "A" and m <= "Z") or (m >= "a" and m <= "z")):
			cmd = m
			i += 1
		if i >= matches.size(): break
		
		if cmd == "M":
			var x = matches[i].get_string().to_float()
			var y = matches[i+1].get_string().to_float()
			current_pos = Vector2(x, y)
			curve.add_point(current_pos)
			prev_ctrl_offset = Vector2()
			i += 2
		elif cmd == "m":
			var dx = matches[i].get_string().to_float()
			var dy = matches[i+1].get_string().to_float()
			current_pos = current_pos + Vector2(dx, dy)
			curve.add_point(current_pos)
			prev_ctrl_offset = Vector2()
			i += 2
		elif cmd == "L":
			var x = matches[i].get_string().to_float()
			var y = matches[i+1].get_string().to_float()
			current_pos = Vector2(x, y)
			curve.add_point(current_pos)
			prev_ctrl_offset = Vector2()
			i += 2
		elif cmd == "l":
			var dx = matches[i].get_string().to_float()
			var dy = matches[i+1].get_string().to_float()
			current_pos = current_pos + Vector2(dx, dy)
			curve.add_point(current_pos)
			prev_ctrl_offset = Vector2()
			i += 2
		elif cmd == "H":
			var x = matches[i].get_string().to_float()
			current_pos = Vector2(x, current_pos.y)
			curve.add_point(current_pos)
			prev_ctrl_offset = Vector2()
			i += 1
		elif cmd == "h":
			var dx = matches[i].get_string().to_float()
			current_pos = Vector2(current_pos.x + dx, current_pos.y)
			curve.add_point(current_pos)
			prev_ctrl_offset = Vector2()
			i += 1
		elif cmd == "V":
			var y = matches[i].get_string().to_float()
			current_pos = Vector2(current_pos.x, y)
			curve.add_point(current_pos)
			prev_ctrl_offset = Vector2()
			i += 1
		elif cmd == "v":
			var dy = matches[i].get_string().to_float()
			current_pos = Vector2(current_pos.x, current_pos.y + dy)
			curve.add_point(current_pos)
			prev_ctrl_offset = Vector2()
			i += 1
		elif cmd == "C":
			var x1 = matches[i].get_string().to_float()
			var y1 = matches[i+1].get_string().to_float()
			var x2 = matches[i+2].get_string().to_float()
			var y2 = matches[i+3].get_string().to_float()
			var x = matches[i+4].get_string().to_float()
			var y = matches[i+5].get_string().to_float()
			var p1 = Vector2(x1, y1)
			var p2 = Vector2(x2, y2)
			var p_next = Vector2(x, y)
			
			var pt_count = curve.get_point_count()
			if pt_count > 0:
				curve.set_point_out(pt_count - 1, p1 - current_pos)
			curve.add_point(p_next, p2 - p_next)
			prev_ctrl_offset = p2 - p_next
			current_pos = p_next
			i += 6
		elif cmd == "c":
			var dx1 = matches[i].get_string().to_float()
			var dy1 = matches[i+1].get_string().to_float()
			var dx2 = matches[i+2].get_string().to_float()
			var dy2 = matches[i+3].get_string().to_float()
			var dx = matches[i+4].get_string().to_float()
			var dy = matches[i+5].get_string().to_float()
			var p1 = current_pos + Vector2(dx1, dy1)
			var p2 = current_pos + Vector2(dx2, dy2)
			var p_next = current_pos + Vector2(dx, dy)
			
			var pt_count = curve.get_point_count()
			if pt_count > 0:
				curve.set_point_out(pt_count - 1, p1 - current_pos)
			curve.add_point(p_next, p2 - p_next)
			prev_ctrl_offset = p2 - p_next
			current_pos = p_next
			i += 6
		elif cmd == "S":
			var x2 = matches[i].get_string().to_float()
			var y2 = matches[i+1].get_string().to_float()
			var x = matches[i+2].get_string().to_float()
			var y = matches[i+3].get_string().to_float()
			var p2 = Vector2(x2, y2)
			var p_next = Vector2(x, y)
			
			var pt_count = curve.get_point_count()
			if pt_count > 0:
				curve.set_point_out(pt_count - 1, -prev_ctrl_offset)
			curve.add_point(p_next, p2 - p_next)
			prev_ctrl_offset = p2 - p_next
			current_pos = p_next
			i += 4
		elif cmd == "s":
			var dx2 = matches[i].get_string().to_float()
			var dy2 = matches[i+1].get_string().to_float()
			var dx = matches[i+2].get_string().to_float()
			var dy = matches[i+3].get_string().to_float()
			var p2 = current_pos + Vector2(dx2, dy2)
			var p_next = current_pos + Vector2(dx, dy)
			
			var pt_count = curve.get_point_count()
			if pt_count > 0:
				curve.set_point_out(pt_count - 1, -prev_ctrl_offset)
			curve.add_point(p_next, p2 - p_next)
			prev_ctrl_offset = p2 - p_next
			current_pos = p_next
			i += 4
		else:
			i += 1
			
	return curve

func _init_trace_lines():
	for child in draw_canvas.get_children():
		child.queue_free()
	bg_lines.clear()
	
	if bg_strokes.is_empty():
		draw_prompt.text = "No tracing data available for this word."
		btn_next.text = "Continue ⏭️"
		btn_next.show()
		btn_next.disabled = false
		return
		
	for i in range(bg_strokes.size()):
		var line = Line2D.new()
		line.width = current_stroke_width
		line.antialiased = true
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.default_color = Color(0.5, 0.5, 0.5, 1.0) if i == 0 else Color(0.25, 0.25, 0.25, 0.6)
		for pt in bg_strokes[i]:
			line.add_point(pt)
		draw_canvas.add_child(line)
		bg_lines.append(line)
		
	active_line = Line2D.new()
	active_line.width = current_stroke_width
	active_line.antialiased = true
	active_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	active_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	active_line.joint_mode = Line2D.LINE_JOINT_ROUND
	active_line.default_color = Color(1.0, 1.0, 1.0, 1.0) # Active stroke is pure white
	draw_canvas.add_child(active_line)
	
	_create_trace_handle()
	_update_bg_lines()
	_update_trace_visuals()

func _create_trace_handle():
	trace_handle = Node2D.new()
	trace_handle.z_index = 10
	
	# Attach an inline drawing script to render the blue circle + rounded arrow
	var handle_script = GDScript.new()
	handle_script.source_code = """
extends Node2D

var radius: float = 12.0

func _draw():
	# 1. Outer dark border / shadow for contrast
	draw_circle(Vector2.ZERO, radius + 1.5, Color(0.08, 0.12, 0.16, 0.6))
	
	# 2. Sky-blue circle body (matches your image)
	draw_circle(Vector2.ZERO, radius, Color(0.29, 0.75, 0.98, 1.0))
	
	# 3. Rounded dark arrow pointing RIGHT (0 radians) so Node2D.rotation aims it
	var arrow_color = Color(0.09, 0.13, 0.16, 1.0)
	var thickness = max(3.5, radius * 0.24)
	var len_x = radius * 0.48
	var wing_x = radius * 0.08
	var wing_y = radius * 0.42
	
	var p_tail = Vector2(-len_x, 0)
	var p_tip = Vector2(len_x, 0)
	var p_top = Vector2(wing_x, -wing_y)
	var p_bot = Vector2(wing_x, wing_y)
	
	# Shaft + Wings with rounded caps
	draw_line(p_tail, p_tip, arrow_color, thickness, true)
	draw_line(p_top, p_tip, arrow_color, thickness, true)
	draw_line(p_bot, p_tip, arrow_color, thickness, true)
	
	# Fill the rounded joints cleanly
	draw_circle(p_tail, thickness * 0.5, arrow_color)
	draw_circle(p_tip, thickness * 0.5, arrow_color)
	draw_circle(p_top, thickness * 0.5, arrow_color)
	draw_circle(p_bot, thickness * 0.5, arrow_color)
"""
	handle_script.reload()
	trace_handle.set_script(handle_script)
	trace_handle.set("radius", max(8.0, current_stroke_width * 0.6))
	draw_canvas.add_child(trace_handle)
	trace_handle.queue_redraw()

func _update_trace_handle(tip_pos: Vector2, point_idx: int):
	if not is_instance_valid(trace_handle):
		return
	if current_stroke_idx >= bg_strokes.size() or bg_strokes.is_empty():
		trace_handle.hide()
		return
		
	var stroke: Array = bg_strokes[current_stroke_idx]
	if stroke.is_empty():
		trace_handle.hide()
		return
		
	trace_handle.show()
	trace_handle.position = tip_pos
	
	# Look a few points ahead along the stroke so the arrow rotates smoothly around curves
	var look_ahead_idx = min(point_idx + 6, stroke.size() - 1)
	var from_idx = max(0, look_ahead_idx - 6)
	if look_ahead_idx > from_idx:
		var dir: Vector2 = stroke[look_ahead_idx] - stroke[from_idx]
		if dir.length_squared() > 0.01:
			trace_handle.rotation = dir.angle()

func _process(_delta):
	if state == "WRITING" and is_tracing:
		var mouse_pos = draw_canvas.get_local_mouse_position()
		_process_tracing(mouse_pos)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if is_tracing:
			is_tracing = false
			if is_instance_valid(draw_canvas):
				_render_active_stroke(draw_canvas.get_local_mouse_position())

func _update_bg_lines():
	for i in range(bg_lines.size()):
		if i < current_stroke_idx:
			bg_lines[i].default_color = Color(0.2, 0.75, 0.35, 1.0) # Finished: Green
		elif i == current_stroke_idx:
			bg_lines[i].default_color = Color(0.65, 0.65, 0.7, 1.0) # Target: Gray/White guide
		else:
			bg_lines[i].default_color = Color(0.22, 0.22, 0.25, 0.45) # Upcoming: Dim
			
	if current_stroke_idx < bg_strokes.size() and not bg_strokes[current_stroke_idx].is_empty():
		_update_trace_handle(bg_strokes[current_stroke_idx][0], 0)
	elif is_instance_valid(trace_handle):
		trace_handle.hide()

func _update_trace_visuals():
	if bg_strokes.is_empty():
		return
		
	_update_bg_lines()
	_render_active_stroke(draw_canvas.get_local_mouse_position())
			
	if current_stroke_idx >= bg_strokes.size():
		draw_prompt.text = "Perfect!"
		draw_prompt.modulate = Color(0.4, 1.0, 0.4)
		btn_next.text = "Continue ⏭️"
		btn_next.show()
		btn_next.disabled = false

func _render_active_stroke(pos: Vector2):
	if not is_instance_valid(active_line): return
	if current_stroke_idx >= bg_strokes.size():
		active_line.clear_points()
		if is_instance_valid(trace_handle):
			trace_handle.hide()
		return
		
	var current_stroke: Array = bg_strokes[current_stroke_idx]
	if active_stroke_points.is_empty():
		active_line.clear_points()
		if not current_stroke.is_empty():
			_update_trace_handle(current_stroke[0], 0)
		return
		
	var pts = active_stroke_points.duplicate()
	
	# Project the tip of the line directly under the mouse cursor on the active segment
	if is_tracing and current_stroke_progress < current_stroke.size() and current_stroke_progress > 0:
		var prev_pt = current_stroke[current_stroke_progress - 1]
		var next_pt = current_stroke[current_stroke_progress]
		var proj = Geometry2D.get_closest_point_to_segment(pos, prev_pt, next_pt)
		if pos.distance_to(proj) <= trace_tolerance:
			pts.append(proj)
			
	active_line.points = pts
	
	# Keep the blue arrow badge glued to the live tip of the stroke!
	if not pts.is_empty():
		_update_trace_handle(pts[-1], current_stroke_progress)

func _on_canvas_gui_input(event):
	if state != "WRITING": return
	if current_stroke_idx >= bg_strokes.size(): return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_tracing = event.pressed
			var mouse_pos = draw_canvas.get_local_mouse_position()
			if is_tracing:
				_process_tracing(mouse_pos)
			else:
				_render_active_stroke(mouse_pos)

func _process_tracing(pos: Vector2):
	if current_stroke_idx >= bg_strokes.size(): return
	
	var current_stroke: Array = bg_strokes[current_stroke_idx]
	if current_stroke.is_empty(): return
	if current_stroke_progress >= current_stroke.size(): return
	
	# 1. Start stroke only when the player clicks near the start point
	if current_stroke_progress == 0:
		if pos.distance_to(current_stroke[0]) <= trace_tolerance:
			active_stroke_points = [current_stroke[0]]
			current_stroke_progress = 1
			_render_active_stroke(pos)
		return # Return immediately: prevents skipping ahead on frame 1
		
	# 2. Advance through stroke segments as the mouse moves forward
	while current_stroke_progress < current_stroke.size():
		var pA: Vector2 = current_stroke[current_stroke_progress - 1]
		var pB: Vector2 = current_stroke[current_stroke_progress]
		var proj: Vector2 = Geometry2D.get_closest_point_to_segment(pos, pA, pB)
		
		# If mouse strayed too far from the active segment, stop advancing
		if pos.distance_to(proj) > trace_tolerance:
			break
			
		# If the perpendicular projection has reached near pB, the player traversed this segment!
		if proj.distance_to(pB) < 3.0:
			active_stroke_points.append(pB)
			current_stroke_progress += 1
		else:
			# Still actively traversing segment [pA, pB]
			break
			
	# 3. Check if stroke completed (reached the last point)
	if current_stroke_progress >= current_stroke.size():
		current_stroke_idx += 1
		current_stroke_progress = 0
		active_stroke_points.clear()
		_update_bg_lines()
		active_line.clear_points()
		
		if current_stroke_idx >= bg_strokes.size():
			is_tracing = false
			draw_prompt.text = "Perfect!"
			draw_prompt.modulate = Color(0.4, 1.0, 0.4)
			btn_next.text = "Continue ⏭️"
			btn_next.show()
			btn_next.disabled = false
		return
		
	_render_active_stroke(pos)