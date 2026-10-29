import os
script_dir = os.path.dirname(os.path.abspath(__file__))
curriculum_path = os.path.join(script_dir, 'Curriculum.gd')

with open(curriculum_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# keep lines up to 122
lines = lines[:122]
lines.append('\t]\n}\n\n')

extra_code = """static var extended_levels: Dictionary = {}
static var is_json_loaded: bool = false

static func get_level(level: int) -> Array:
	if LEVELS.has(level):
		return LEVELS[level].duplicate()
		
	if not is_json_loaded:
		_load_extended_json()
		
	var key = str(level)
	if extended_levels.has(key):
		return extended_levels[key].duplicate()
		
	return []

static func _load_extended_json():
	var file = FileAccess.open("res://data/jmdict_levels.json", FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var json = JSON.new()
		if json.parse(content) == OK:
			extended_levels = json.data
		is_json_loaded = true
"""
lines.append(extra_code)

with open(curriculum_path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print('Updated Curriculum.gd')
