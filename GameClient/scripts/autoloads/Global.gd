extends Node

signal level_changed(new_level)
signal coins_changed(new_amount)

var current_scene = null
var current_custom_test: Dictionary = {}
var solo_target_level = null

# Global caches for instant load times
var kanjivg_data: Dictionary = {}
var stroke_cache: Dictionary = {}

func _ready():
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)
	check_ota_updates()

func check_ota_updates():
	# Skip dummy placeholder URL to avoid DNS resolution hangs on startup
	var url = ""
	if url.is_empty() or "your-server-or-github-pages.com" in url:
		return
		
	var req = HTTPRequest.new()
	add_child(req)
	
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("data"):
		dir.make_dir("data")
		
	var temp_path = "user://data/jmdict_levels_temp.json"
	req.download_file = temp_path 
	
	req.request_completed.connect(func(res, code, headers, body):
		if code == 200:
			var da = DirAccess.open("user://data")
			if da.file_exists("jmdict_levels.json"):
				da.remove("jmdict_levels.json")
			da.rename("jmdict_levels_temp.json", "jmdict_levels.json")
			
			var Curriculum = preload("res://scripts/Curriculum.gd")
			Curriculum.is_json_loaded = false
			print("OTA Update: Đã tải từ điển mới thành công!")
		else:
			var da = DirAccess.open("user://data")
			if da.file_exists("jmdict_levels_temp.json"):
				da.remove("jmdict_levels_temp.json")
		req.queue_free()
	)
	req.request(url)

func get_display_name() -> String:
	return Database.get_account()["display_name"]

func set_display_name(name: String):
	Database.update_account("display_name", name)

func get_current_level() -> int:
	return Database.get_account()["current_level"]

func set_current_level(level: int, learned_words: Array = []):
	Database.update_account("current_level", level)
	emit_signal("level_changed", level)
	sync_progress_to_server(null, learned_words)

func sync_progress_to_server(btn_caller = null, learned_words: Array = []):
	var user_id = Database.get_account().get("user_id", -1)
	if user_id != -1 and Network.is_logged_in:
		if btn_caller: btn_caller.text = "Đang lưu..."
		var req = HTTPRequest.new()
		add_child(req)
		req.request_completed.connect(func(res, code, headers, body):
			if code == 401:
				Network.logout(true)
				goto_scene("res://scenes/Login.tscn")
			elif btn_caller: 
				btn_caller.text = "Đã lưu!" if code == 200 else "Lỗi lưu (" + str(code) + ")"
			req.queue_free()
		)
		var headers = PackedStringArray(["Authorization: Bearer " + Network.jwt_token, "Content-Type: application/json"])
		var url = Network.BASE_URL + "/player/%d/progress?level=%d" % [user_id, Database.get_account().get("current_level", 1)]
		var body_str = JSON.stringify(learned_words)
		req.request(url, headers, HTTPClient.METHOD_PUT, body_str)
	else:
		if btn_caller: btn_caller.text = "Chưa đăng nhập!"

func get_coins() -> int:
	return Database.get_account()["g_coin_balance"]

func add_coins(amount: int):
	var new_balance = get_coins() + amount
	Database.update_account("g_coin_balance", new_balance)
	emit_signal("coins_changed", new_balance)
	sync_coins_to_server()

func sync_coins_to_server():
	var user_id = Database.get_account().get("user_id", -1)
	if user_id != -1 and Network.is_logged_in:
		var req = HTTPRequest.new()
		add_child(req)
		req.request_completed.connect(func(res, code, headers, body):
			if code == 401:
				Network.logout(true)
				goto_scene("res://scenes/Login.tscn")
			req.queue_free()
		)
		var headers = PackedStringArray(["Authorization: Bearer " + Network.jwt_token, "Content-Type: application/json"])
		var url = Network.BASE_URL + "/player/%d/coins?coins=%d" % [user_id, Database.get_account().get("g_coin_balance", 0)]
		req.request(url, headers, HTTPClient.METHOD_PUT)

func goto_scene(path: String):
	call_deferred("_deferred_goto_scene", path)

func _deferred_goto_scene(path):
	current_scene.free()
	var s = ResourceLoader.load(path)
	current_scene = s.instantiate()
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene
