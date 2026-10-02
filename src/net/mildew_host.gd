class_name MildewHost
extends Node
## Hosts one Mildew broadcast session on this device: authoritative SessionServer +
## controller HTTP server + WebSocket server + (dev) loopback fake players.
## This is the only place that binds the transport-agnostic server to real sockets;
## a future Xbox/PC host reuses it unchanged (pure Godot networking).

signal tv_event(evt: Dictionary)
signal host_log(text: String)

var cfg: MildewConfig
var store: SaveStore
var content: ContentDB
var session: SessionServer
var http := HttpStaticServer.new()
var ws := WsServer.new()

var lan_ip := ""
var join_url := ""       # QR target (includes ephemeral join key; no room code needed)
var short_url := ""      # manual fallback (http://ip:port) + room code
var running := false
var start_error := ""
var log_lines: Array = []

var _ws_to_conn := {}
var _conn_to_ws := {}
var _bots := {}          # conn_id -> FakePlayerBot
var _offline_bots: Array = []
var _bot_counter := 0


func setup(p_cfg: MildewConfig, p_store: SaveStore, p_content: ContentDB) -> void:
	cfg = p_cfg
	store = p_store
	content = p_content


## Starts listening and opens a fresh session (BEGIN TRANSMISSION).
func begin(seed: int = 0, bind_address: String = "*") -> bool:
	stop()
	session = SessionServer.new(cfg, store, content, seed)
	session.send.connect(_on_session_send)
	session.close_requested.connect(_on_session_close)
	session.tv_event.connect(func(e): tv_event.emit(e))
	session.log_line.connect(_log)
	var span := cfg.i("network.port_search_span", 10)
	if not http.start(cfg.i("network.http_port", 8080), span, bind_address):
		start_error = http.last_error
		_log("ERROR " + start_error)
		return false
	if not ws.start(cfg.i("network.ws_port", 8081), span, bind_address):
		start_error = ws.last_error
		http.stop()
		_log("ERROR " + start_error)
		return false
	http.max_request_bytes = cfg.i("network.http_max_request_bytes", 8192)
	http.request_timeout_ms = cfg.i("network.http_request_timeout_ms", 10000)
	http.dynamic_routes = {"/config.js": _config_js, "/api/info": _api_info, "/api/avatar": _api_avatar}
	if not ws.client_connected.is_connected(_on_ws_connected):
		ws.client_connected.connect(_on_ws_connected)
		ws.client_text.connect(_on_ws_text)
		ws.client_disconnected.connect(_on_ws_disconnected)
	refresh_lan()
	running = true
	session.open()
	_log("host up http=%d ws=%d lan=%s room=%s" % [http.port, ws.port, lan_ip, session.room_code])
	return true


func refresh_lan() -> void:
	lan_ip = LanInfo.best_ipv4()
	var host := lan_ip if lan_ip != "" else "127.0.0.1"
	short_url = "http://%s:%d" % [host, http.port]
	join_url = "%s/?k=%s" % [short_url, session.join_key if session else ""]


func stop() -> void:
	if session != null and session.phase != SessionServer.Phase.CLOSED:
		session.close_session("host_stopped")
	http.stop()
	ws.stop()
	_ws_to_conn.clear()
	_conn_to_ws.clear()
	_bots.clear()
	_offline_bots.clear()
	running = false


func _process(delta: float) -> void:
	if not running:
		return
	http.poll()
	ws.poll()
	_tick_bots(delta)
	session.tick(delta)


# --- WebSocket <-> session ---------------------------------------------------

func _on_ws_connected(ws_id: int, addr: String) -> void:
	var cid := session.connect_client({"transport": "ws", "addr": addr})
	_ws_to_conn[ws_id] = cid
	_conn_to_ws[cid] = ws_id


func _on_ws_text(ws_id: int, text: String) -> void:
	var cid = _ws_to_conn.get(ws_id)
	if cid != null:
		session.receive_text(cid, text)


func _on_ws_disconnected(ws_id: int, code: int, reason: String) -> void:
	var cid = _ws_to_conn.get(ws_id)
	_ws_to_conn.erase(ws_id)
	if cid != null:
		_conn_to_ws.erase(cid)
		session.disconnect_client(cid, "ws_closed %d %s" % [code, reason])


func _on_session_send(conn_id: int, msg: Dictionary) -> void:
	if _conn_to_ws.has(conn_id):
		ws.send_text(_conn_to_ws[conn_id], JSON.stringify(msg))
	elif _bots.has(conn_id):
		_bots[conn_id].receive(JSON.parse_string(JSON.stringify(msg)))


func _on_session_close(conn_id: int, reason: String) -> void:
	if _conn_to_ws.has(conn_id):
		ws.close(_conn_to_ws[conn_id], 4000, reason)
	elif _bots.has(conn_id):
		var bot: FakePlayerBot = _bots[conn_id]
		bot.connected = false
		_bots.erase(conn_id)


# --- HTTP dynamic routes ------------------------------------------------------

func _config_js() -> Dictionary:
	var js := "window.MILDEW_CONFIG = %s;" % JSON.stringify({
		"wsPort": ws.port, "protocol": Protocol.VERSION,
		"pingMs": cfg.i("network.client_ping_interval_ms", 2000),
		"maxName": cfg.i("lobby.max_display_name_chars", 16),
	})
	return {"status": 200, "type": "text/javascript; charset=utf-8", "body": js.to_utf8_buffer()}


func _api_info() -> Dictionary:
	var body := JSON.stringify({"protocol": Protocol.VERSION, "ws_port": ws.port, "phase": session.phase_name() if session else "none"})
	return {"status": 200, "type": "application/json", "body": body.to_utf8_buffer()}


func _api_avatar() -> Dictionary:
	return {"status": 200, "type": "application/json", "body": FileAccess.get_file_as_bytes("res://config/avatar_parts.json")}


# --- Dev: fake players over loopback ---------------------------------------------

func add_fake_player(personality: String = "") -> FakePlayerBot:
	var names: Array = cfg.get_value("dev.fake_player_names", ["Bot"])
	var name: String = names[_bot_counter % names.size()]
	if _bot_counter >= names.size():
		name += " %d" % (_bot_counter / names.size() + 1)
	_bot_counter += 1
	if personality == "":
		personality = FakePlayerBot.PERSONALITIES[_bot_counter % FakePlayerBot.PERSONALITIES.size()]
	var bot := FakePlayerBot.new(name, personality)
	bot.room_key = session.join_key
	bot.oracle = func(content_id: String) -> int: return int(content.get_item(content_id).get("correct", -1))
	bot.hole_oracle = func(content_id: String, variant: String) -> String:
		var it: Dictionary = content.get_item(content_id)
		if variant == "scale":
			var k := SegHole.SCALE_KEYS.find(str(it.get("scale", "")))
			return SegHole.SCALE_LABELS[k] if k >= 0 else ""
		return str(it.get("answer", ""))
	_connect_bot(bot)
	return bot


func _connect_bot(bot: FakePlayerBot) -> void:
	bot.conn_id = session.connect_client({"fake": true, "transport": "loopback", "addr": "loopback"})
	bot.connected = true
	_bots[bot.conn_id] = bot
	session.receive_text(bot.conn_id, JSON.stringify(bot.hello()))


## Simulates a dropped phone (dev). Returns the bot so it can be reconnected.
func drop_fake_player() -> FakePlayerBot:
	for cid in _bots.keys():
		var bot: FakePlayerBot = _bots[cid]
		_bots.erase(cid)
		bot.connected = false
		session.disconnect_client(cid, "dev_simulated_drop")
		_offline_bots.append(bot)
		return bot
	return null


func reconnect_fake_player() -> FakePlayerBot:
	if _offline_bots.is_empty():
		return null
	var bot: FakePlayerBot = _offline_bots.pop_front()
	_connect_bot(bot)
	return bot


func remove_fake_player() -> void:
	for cid in _bots.keys():
		session.receive_text(cid, JSON.stringify({"t": "leave"}))
		_bots.erase(cid)
		return


func fake_count() -> int:
	return _bots.size()


func _tick_bots(delta: float) -> void:
	for cid in _bots.keys():
		var bot: FakePlayerBot = _bots.get(cid)
		if bot == null:
			continue
		for m in bot.poll(delta):
			if _bots.has(cid):
				session.receive_text(cid, JSON.stringify(m))
		if int(bot.now / 2.0) != int((bot.now - delta) / 2.0) and _bots.has(cid):
			session.receive_text(cid, JSON.stringify({"t": "ping", "id": 0, "rtt": 1}))


func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 400:
		log_lines.pop_front()
	host_log.emit(text)


func diagnostics() -> Dictionary:
	var d := session.diagnostics() if session else {}
	d["lan_ip"] = lan_ip
	d["lan_candidates"] = LanInfo.candidates()
	d["http_port"] = http.port
	d["ws_port"] = ws.port
	d["join_url"] = join_url
	d["short_url"] = short_url
	d["ws_peers"] = ws.peer_count()
	d["http_served"] = http.requests_served
	d["http_rejected"] = http.requests_rejected
	d["fake_players"] = _bots.size()
	return d
