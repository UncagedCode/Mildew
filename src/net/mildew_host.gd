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

# --- Phone dev panel (debug builds only; D023) ---
var dev_enabled := false         # set by the app: OS.is_debug_build()
var dev_pin := ""                # 4 digits shown on the TV; stable for the app run
var dev_handler: Callable        # (cmd: String, args: Dictionary) -> {ok: bool, msg: String}
var dev_extra: Callable          # () -> Dictionary of app-level state (TV screen, overlay)
var _dev_ws := {}                # ws_id -> true (authenticated dev sockets)
var _dev_fail := {}              # ws_id -> wrong PIN attempts
var _dev_push := 0.0
var _dev_events: Array = []      # recent TV events, compact
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
	if dev_enabled:
		if dev_pin == "":
			dev_pin = "%04d" % randi_range(0, 9999)
		http.dynamic_routes["/dev"] = _dev_page
		session.tv_event.connect(_dev_note_event)
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
	_dev_ws.clear()
	_dev_fail.clear()
	running = false


func _process(delta: float) -> void:
	if not running:
		return
	http.poll()
	ws.poll()
	_tick_bots(delta)
	session.tick(delta)
	if not _dev_ws.is_empty():
		_dev_push -= delta
		if _dev_push <= 0.0:
			_dev_push = 0.5
			_dev_broadcast_state()


# --- WebSocket <-> session ---------------------------------------------------

func _on_ws_connected(ws_id: int, addr: String) -> void:
	var cid := session.connect_client({"transport": "ws", "addr": addr})
	_ws_to_conn[ws_id] = cid
	_conn_to_ws[cid] = ws_id


func _on_ws_text(ws_id: int, text: String) -> void:
	if _dev_ws.has(ws_id):
		_dev_message(ws_id, text)
		return
	if dev_enabled and text.length() < 256 and text.contains("dev_hello"):
		_dev_hello(ws_id, text)
		return
	var cid = _ws_to_conn.get(ws_id)
	if cid != null:
		session.receive_text(cid, text)


func _on_ws_disconnected(ws_id: int, code: int, reason: String) -> void:
	_dev_ws.erase(ws_id)
	_dev_fail.erase(ws_id)
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
		# D024: names Graham has a recording for; the pronunciation check only runs for these
		# (or, in debug builds, through the flagged system-TTS developer fallback).
		"voiceNames": GrahamVoiceIndex.shared().spoken_names(),
		"devTts": dev_enabled and bool(store.get_setting("dev_tts_fallback", true)) if store else false,
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
	bot.oracle = func(content_id: String) -> String:
		var it: Dictionary = content.get_item(content_id)
		var opts: Array = it.get("options", [])
		var c := int(it.get("correct", -1))
		return str(opts[c]) if c >= 0 and c < opts.size() else ""
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


# --- Phone dev panel (debug builds only) -------------------------------------------
# A phone opens http://<tv>:<port>/dev, enters the PIN shown on the TV, and drives the developer
# tools over the normal WebSocket port. Dev sockets are detached from the game session (they are
# never players) and the route does not exist in release builds.

func _dev_page() -> Dictionary:
	var body := FileAccess.get_file_as_bytes("res://devpanel/dev.html")
	if body.is_empty():
		return {"status": 404, "type": "text/plain", "body": "Not found".to_utf8_buffer()}
	return {"status": 200, "type": "text/html; charset=utf-8", "body": body}


func _dev_hello(ws_id: int, text: String) -> void:
	var m = JSON.parse_string(text)
	if typeof(m) != TYPE_DICTIONARY or str(m.get("t", "")) != "dev_hello":
		return
	if str(m.get("pin", "")) != dev_pin:
		_dev_fail[ws_id] = int(_dev_fail.get(ws_id, 0)) + 1
		ws.send_text(ws_id, JSON.stringify({"t": "dev_denied", "msg": "Wrong PIN. It is shown on the TV lobby screen."}))
		if int(_dev_fail[ws_id]) >= 3:
			ws.close(ws_id, 4003, "dev pin")
		return
	var cid = _ws_to_conn.get(ws_id)
	if cid != null:
		_ws_to_conn.erase(ws_id)
		_conn_to_ws.erase(cid)
		session.disconnect_client(cid, "dev_panel")   # never a player
	_dev_ws[ws_id] = true
	_log("dev panel connected (ws %d)" % ws_id)
	ws.send_text(ws_id, JSON.stringify({"t": "dev_welcome", "catalogue": _dev_catalogue()}))
	ws.send_text(ws_id, JSON.stringify(_dev_state()))


func _dev_message(ws_id: int, text: String) -> void:
	var m = JSON.parse_string(text)
	if typeof(m) != TYPE_DICTIONARY:
		return
	if str(m.get("t", "")) == "ping":
		ws.send_text(ws_id, JSON.stringify({"t": "pong"}))
		return
	if str(m.get("t", "")) != "dev":
		return
	var cmd := str(m.get("cmd", ""))
	var args: Dictionary = m.get("args", {}) if typeof(m.get("args")) == TYPE_DICTIONARY else {}
	var r: Dictionary = {"ok": false, "msg": "no handler"}
	if dev_handler.is_valid():
		r = dev_handler.call(cmd, args)
	_log("dev %s %s -> %s" % [cmd, JSON.stringify(args), r.get("msg", "")])
	if _dev_ws.has(ws_id):   # a restart command may have closed every socket
		ws.send_text(ws_id, JSON.stringify({"t": "dev_result", "cmd": cmd, "ok": bool(r.get("ok", false)), "msg": str(r.get("msg", ""))}))
	_dev_broadcast_state()


func _dev_note_event(e: Dictionary) -> void:
	var kind := str(e.get("e", ""))
	if kind in ["podium", "ping", "answered", "player_rtt"]:
		return
	var detail := ""
	match kind:
		"say":
			detail = "%s: %s" % [e.get("speaker", ""), str(e.get("text", "")).left(80)]
		"incident":
			detail = "%s (tier %s)" % [e.get("id", ""), e.get("tier", "")]
		"hole_round":
			detail = "%s · %s" % [e.get("variant", ""), e.get("item_id", "")]
		"hole_lock":
			detail = "%s at look %s" % [e.get("pid", ""), e.get("stage", "")]
		"hole_reveal":
			detail = str(e.get("answer", ""))
		"hold":
			detail = str(e.get("reason", "")) if str(e.get("reason", "")) != "" else "released"
		"sting":
			detail = str(e.get("game_id", e.get("title", "")))
	_dev_events.append({"t": snappedf(session.session_time if session else 0.0, 0.1), "e": kind, "d": detail})
	if _dev_events.size() > 40:
		_dev_events.pop_front()


func _dev_catalogue() -> Dictionary:
	var items: Array = []
	for it in content.query("hole", "", 5, 0):
		items.append({"id": it.id, "label": str(it.get("answer", it.id)), "tier": int(it.get("familiarity_tier", 1))})
	var incs: Array = []
	for it in content.query("incident", "", 5, 0):
		incs.append({"id": it.id, "tier": int(it.get("tier", 0)), "moments": it.get("moments", [])})
	var privs: Array = []
	for it in content.query("interference", "", 5, 0):
		privs.append({"id": it.id, "tier": int(it.get("tier", 1)), "source": str(it.get("source", ""))})
	var games: Array = Director.FORMATS.keys().filter(func(k): return Director.FORMATS[k].kind == "game" and Director.FORMATS[k].implemented)
	return {"personalities": FakePlayerBot.PERSONALITIES, "hole_items": items, "hole_variants": ["standard", "scale", "open"],
		"private": privs, "games": games,
		"incidents": incs, "interference": ["standard_transmission", "supervised_transmission", "clean_transmission"],
		"timescales": [1, 2, 4, 8]}


func _dev_state() -> Dictionary:
	var ps: Array = []
	if session:
		for p in session.players.values():
			ps.append({"pid": p.player_id, "name": p.display_name, "score": p.score, "connected": p.connected,
				"fake": p.is_fake, "status": PlayerState.Status.keys()[p.status], "number": p.number})
	var d: Dictionary = session.director.snapshot() if session and session.director else {}
	var st := {
		"t": "dev_state", "phase": session.phase_name() if session else "none",
		"segment": session._current.kind if session and session._current != null else "",
		"segments_left": session._segments.size() if session else 0,
		"hold": session.hold_reason if session else "", "manual_pause": session.manual_pause if session else false,
		"time_scale": session.time_scale if session else 1.0, "room": session.room_code if session else "",
		"players": ps, "bots_online": _bots.size(), "bots_offline": _offline_bots.size(),
		"force": session.director.force.duplicate() if session else {},
		"director": {"mood": d.get("graham_mood", ""), "pressure": d.get("pressure", 0.0), "degradation": d.get("degradation", 0.0),
			"complicity": d.get("complicity", 0.0), "familiarity": d.get("familiarity_tier", 1), "interference": d.get("interference_mode", ""),
			"show_time": d.get("show_time", 0.0), "incidents": d.get("incidents", {}).get("log", []).slice(-8)},
		"decisions": session.director.decision_log.slice(-10) if session else [],
		"events": _dev_events.slice(-25),
	}
	if dev_extra.is_valid():
		st["app"] = dev_extra.call()
	return st


func _dev_broadcast_state() -> void:
	if _dev_ws.is_empty():
		return
	var txt := JSON.stringify(_dev_state())
	for wid in _dev_ws.keys():
		ws.send_text(wid, txt)
