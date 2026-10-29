extends SceneTree

func _init():
	var path_str = "M54.5,15.79c0,6.07-0.29,55.49-0.29,60.55"
	var curve = Curve2D.new()
	var regex = RegEx.new()
	regex.compile("([A-Za-z])|(-?[0-9]*\\.?[0-9]+)")
	var matches = regex.search_all(path_str)
	
	var i = 0
	var cmd = ""
	var current_pos = Vector2()
	
	while i < matches.size():
		var m = matches[i].get_string()
		if m.length() == 1 and m.to_lower() >= "a" and m.to_lower() <= "z":
			cmd = m
			i += 1
		else:
			pass # implicit repeated command
			
		if i >= matches.size(): break
			
		if cmd == "M":
			var x = matches[i].get_string().to_float()
			var y = matches[i+1].get_string().to_float()
			current_pos = Vector2(x, y)
			curve.add_point(current_pos)
			i += 2
		elif cmd == "c":
			var dx1 = matches[i].get_string().to_float()
			var dy1 = matches[i+1].get_string().to_float()
			var dx2 = matches[i+2].get_string().to_float()
			var dy2 = matches[i+3].get_string().to_float()
			var dx = matches[i+4].get_string().to_float()
			var dy = matches[i+5].get_string().to_float()
			var p_next = current_pos + Vector2(dx, dy)
			
			var pt_count = curve.get_point_count()
			if pt_count > 0:
				curve.set_point_out(pt_count - 1, Vector2(dx1, dy1))
			curve.add_point(p_next, Vector2(dx2, dy2) - Vector2(dx, dy))
			current_pos = p_next
			i += 6
		elif cmd == "s":
			var dx2 = matches[i].get_string().to_float()
			var dy2 = matches[i+1].get_string().to_float()
			var dx = matches[i+2].get_string().to_float()
			var dy = matches[i+3].get_string().to_float()
			
			var pt_count = curve.get_point_count()
			var p_in = Vector2()
			if pt_count > 0:
				p_in = -curve.get_point_out(pt_count - 1)
				curve.set_point_out(pt_count - 1, -p_in)
				
			var p_next = current_pos + Vector2(dx, dy)
			curve.add_point(p_next, Vector2(dx2, dy2) - Vector2(dx, dy))
			current_pos = p_next
			i += 4
		else:
			i += 1
			
	var pts = curve.tessellate(5, 4.0)
	print("Tessellated points: ", pts.size())
	for p in pts:
		print(" - ", p)
	quit()
