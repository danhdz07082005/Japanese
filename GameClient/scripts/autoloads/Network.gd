extends Node

const CurriculumScript = preload("res://scripts/Curriculum.gd")

const DEFAULT_SERVER_URL = "http://localhost:8080/api"
const CONFIG_FILE_PATH = "user://server_config.json"

var BASE_URL: String = DEFAULT_SERVER_URL
var jwt_token = ""
var is_logged_in = false

signal login_success(user_data)
signal login_failed(error_msg)
signal register_success(user_data)
signal register_failed(error_msg)
signal server_url_changed(new_url)

var _http_request: HTTPRequest
var _heartbeat_request: HTTPRequest
var _heartbeat_in_flight: bool = false

func _ready():
	_load_server_config()

	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	
	_heartbeat_request = HTTPRequest.new()
	add_child(_heartbeat_request)
	_heartbeat_request.request_completed.connect(_on_heartbeat_completed)
	
	get_tree().set_auto_accept_quit(false)
	
	# Heartbeat timer: check session validity every 10s without spamming
	var timer = Timer.new()
	timer.wait_time = 10.0
	timer.autostart = true
	timer.timeout.connect(_check_heartbeat)
	add_child(timer)

# ==================== DYNAMIC SERVER CONFIG & ONLINE DISCOVERY ====================

func _load_server_config():
	if FileAccess.file_exists(CONFIG_FILE_PATH):
		var file = FileAccess.open(CONFIG_FILE_PATH, FileAccess.READ)
		if file != null:
			var content = file.get_as_text()
			var json = JSON.new()
			if json.parse(content) == OK and json.data is Dictionary:
				var saved_url = str(json.data.get("server_url", "")).strip_edges()
				if not saved_url.is_empty():
					BASE_URL = saved_url
					print("[Network] Loaded dynamic server URL: ", BASE_URL)
					return
	BASE_URL = DEFAULT_SERVER_URL
	print("[Network] Using default server URL: ", BASE_URL)

func set_base_url(raw_url: String) -> String:
	var url = raw_url.strip_edges()
	if url.is_empty():
		url = DEFAULT_SERVER_URL
	
	if not url.begins_with("http://") and not url.begins_with("https://"):
		url = "https://" + url # Default to HTTPS for tunnel links
	
	while url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	
	if not url.ends_with("/api"):
		url += "/api"
		
	BASE_URL = url
	
	# Persist configuration
	var file = FileAccess.open(CONFIG_FILE_PATH, FileAccess.WRITE)
	if file != null:
		var cfg = {
			"server_url": BASE_URL,
			"updated_at": Time.get_datetime_string_from_system()
		}
		file.store_string(JSON.stringify(cfg, "\t"))
	
	print("[Network] Saved new server URL: ", BASE_URL)
	emit_signal("server_url_changed", BASE_URL)
	return BASE_URL

func get_ws_url() -> String:
	var ws_base = BASE_URL
	if ws_base.begins_with("https://"):
		ws_base = "wss://" + ws_base.substr(8)
	elif ws_base.begins_with("http://"):
		ws_base = "ws://" + ws_base.substr(7)
	
	if ws_base.ends_with("/api"):
		ws_base = ws_base.substr(0, ws_base.length() - 4)
	
	while ws_base.ends_with("/"):
		ws_base = ws_base.substr(0, ws_base.length() - 1)
		
	return ws_base + "/ws/pvp"

func check_server_health(callback: Callable):
	var ping_req = HTTPRequest.new()
	add_child(ping_req)
	var start_ms = Time.get_ticks_msec()
	
	ping_req.request_completed.connect(func(result, code, headers, body):
		var elapsed = Time.get_ticks_msec() - start_ms
		var is_online = (code == 200)
		var info = {}
		if is_online:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				info = json.data
		callback.call(is_online, elapsed, info)
		ping_req.queue_free()
	)
	
	var health_url = BASE_URL
	if health_url.ends_with("/api"):
		health_url = health_url.substr(0, health_url.length() - 4)
	health_url += "/api/discovery"
	
	ping_req.request(health_url, PackedStringArray(), HTTPClient.METHOD_GET)

# ==================== AUTH & SESSION ====================

func _check_heartbeat():
	if is_logged_in and jwt_token != "" and not _heartbeat_in_flight:
		var user_id = Database.get_account().get("user_id", -1)
		if user_id != -1:
			_heartbeat_in_flight = true
			var headers = PackedStringArray(["Authorization: Bearer " + jwt_token])
			_heartbeat_request.request(BASE_URL + "/player/%d/heartbeat" % user_id, headers, HTTPClient.METHOD_GET)

func _on_heartbeat_completed(result, code, headers, body):
	_heartbeat_in_flight = false
	if code == 401:
		print("[Heartbeat] Bị đá văng do đăng nhập ở nơi khác!")
		logout(true)
		Global.goto_scene("res://scenes/Login.tscn")

func register(username, password):
	var body = JSON.stringify({"username": username, "password": password})
	var headers = PackedStringArray(["Content-Type: application/json"])
	_http_request.request(BASE_URL + "/auth/register", headers, HTTPClient.METHOD_POST, body)
	_http_request.set_meta("action", "register")

func login(username, password):
	var body = JSON.stringify({"username": username, "password": password})
	var headers = PackedStringArray(["Content-Type: application/json"])
	_http_request.request(BASE_URL + "/auth/login", headers, HTTPClient.METHOD_POST, body)
	_http_request.set_meta("action", "login")

func logout(local_only: bool = false):
	var user_id = Database.get_account().get("user_id", -1)
	if not local_only and user_id != -1 and jwt_token != "":
		var req = HTTPRequest.new()
		add_child(req)
		req.request_completed.connect(func(res, code, headers, body): req.queue_free())
		var headers = PackedStringArray(["Authorization: Bearer " + jwt_token, "Content-Type: application/json"])
		req.request(BASE_URL + ("/auth/logout/%d" % user_id), headers, HTTPClient.METHOD_POST)

	jwt_token = ""
	is_logged_in = false
	Database.reset_session()
	
	var da = DirAccess.open("user://")
	if da != null:
		if da.file_exists("user://menu_theme_cache.dat"):
			da.remove("user://menu_theme_cache.dat")
		if da.file_exists("user://menu_theme_video.ogv"):
			da.remove("user://menu_theme_video.ogv")

func _on_request_completed(result, response_code, headers, body):
	var action = _http_request.get_meta("action")
	var response_str = body.get_string_from_utf8()
	
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(response_str)
		if parse_result == OK:
			var data = json.data
			jwt_token = data.get("token", "")
			is_logged_in = true
			
			var uid = int(data.get("id", -1))
			Database.update_account("user_id", uid)
			Database.update_account("display_name", data.get("username", "Player"))
			Database.update_account("current_level", data.get("level", 1))
			Database.update_account("role", data.get("role", "PLAYER"))
			Database.update_account("g_coin_balance", data.get("gCoin", 0))
			
			var p_ids = data.get("purchasedItemIds", [])
			Database.update_account("purchased_theme_ids", p_ids if p_ids is Array else [])
			
			var act_url = data.get("activeThemeUrl")
			if act_url != null and str(act_url) != "" and str(act_url) != "null":
				Database.update_account("menu_theme_url", str(act_url))
			else:
				Database.update_account("menu_theme_url", "")
				var l_da = DirAccess.open("user://")
				if l_da != null:
					if l_da.file_exists("user://menu_theme_cache.dat"):
						l_da.remove("user://menu_theme_cache.dat")
					if l_da.file_exists("user://menu_theme_video.ogv"):
						l_da.remove("user://menu_theme_video.ogv")
			
			fetch_user_shop_data(uid)
			fetch_and_sync_vocabularies()
			
			if action == "login":
				emit_signal("login_success", data)
			else:
				emit_signal("register_success", data)
		else:
			_handle_error(action, "Lỗi phân tích JSON từ server")
	else:
		var err_msg = "Thất bại! Mã lỗi: " + str(response_code)
		var json = JSON.new()
		if json.parse(response_str) == OK and json.data is Dictionary:
			if json.data.has("message"):
				err_msg = json.data["message"]
		_handle_error(action, err_msg)

func _handle_error(action, msg):
	if action == "login":
		emit_signal("login_failed", msg)
	else:
		emit_signal("register_failed", msg)

func fetch_user_shop_data(uid: int):
	if uid <= 0: return
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, headers, body):
		req.queue_free()
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				var sdata = json.data
				if sdata.has("purchasedItemIds") and sdata["purchasedItemIds"] is Array:
					Database.update_account("purchased_theme_ids", sdata["purchasedItemIds"])
				else:
					Database.update_account("purchased_theme_ids", [])
				var act_url = sdata.get("activeThemeUrl")
				if act_url != null and str(act_url) != "" and str(act_url) != "null":
					Database.update_account("menu_theme_url", str(act_url))
				else:
					Database.update_account("menu_theme_url", "")
				if sdata.has("gCoin"):
					Database.update_account("g_coin_balance", int(sdata["gCoin"]))
	)
	var hdrs = PackedStringArray(["Authorization: Bearer " + jwt_token, "Content-Type: application/json"])
	req.request(BASE_URL + "/shop/user/%d" % uid, hdrs, HTTPClient.METHOD_GET)

func fetch_and_sync_vocabularies():
	var req = HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(res, code, headers, body):
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Array:
				var arr = json.data
				for v in arr:
					var lvl = int(v.get("levelRequired", 1))
					if not CurriculumScript.LEVELS.has(lvl):
						CurriculumScript.LEVELS[lvl] = []
					
					var exists = false
					for item in CurriculumScript.LEVELS[lvl]:
						if item["kana"] == v["wordJp"]:
							item["romaji"] = v["romaji"]
							exists = true
							break
					
					if not exists:
						CurriculumScript.LEVELS[lvl].append({"kana": v["wordJp"], "romaji": v["romaji"]})
		req.queue_free()
	)
	var headers = PackedStringArray(["Content-Type: application/json"])
	if jwt_token != "":
		headers.append("Authorization: Bearer " + jwt_token)
	req.request(BASE_URL + "/admin/vocabularies", headers, HTTPClient.METHOD_GET)

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_logged_in and jwt_token != "":
			var user_id = Database.get_account().get("user_id", -1)
			if user_id != -1:
				var req = HTTPRequest.new()
				add_child(req)
				var headers = PackedStringArray(["Authorization: Bearer " + jwt_token, "Content-Type: application/json"])
				req.request(BASE_URL + ("/auth/logout/%d" % user_id), headers, HTTPClient.METHOD_POST)
				
				var t = Timer.new()
				t.wait_time = 0.5
				t.one_shot = true
				add_child(t)
				t.start()
				await t.timeout
		get_tree().quit()
