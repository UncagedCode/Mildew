class_name SimHarness
extends RefCounted
## Headless accelerated broadcast simulation (docs/10 "Full broadcast simulation").
## Runs the real SessionServer + Director with in-process FakePlayerBots over a loopback
## transport that still uses JSON text frames. Used by automated tests and the dev menu.

var session: SessionServer
var bots: Array = []                 # FakePlayerBot
var bot_by_conn := {}
var tv_events: Array = []
var logs: Array = []
var sent_count := 0
var dt := 0.05                       # real seconds per tick
var keep_events := true


func _init(cfg: MildewConfig, store: SaveStore, content: ContentDB, seed: int, time_scale: float) -> void:
	session = SessionServer.new(cfg, store, content, seed)
	session.time_scale = time_scale
	session.send.connect(_on_send)
	session.close_requested.connect(_on_close)
	session.tv_event.connect(func(e): if keep_events: tv_events.append(e))
	session.log_line.connect(func(t): logs.append(t))
	session.open()


func oracle(content_id: String) -> int:
	var item: Dictionary = session.content.get_item(content_id)
	return int(item.get("correct", -1)) if not item.is_empty() else -1


func hole_oracle(content_id: String, variant: String) -> String:
	var item: Dictionary = session.content.get_item(content_id)
	if item.is_empty():
		return ""
	if variant == "scale":
		var k := SegHole.SCALE_KEYS.find(str(item.get("scale", "")))
		return SegHole.SCALE_LABELS[k] if k >= 0 else ""
	return str(item.get("answer", ""))


func add_bot(name: String, personality: String, seed: int = 0) -> FakePlayerBot:
	var bot := FakePlayerBot.new(name, personality, seed)
	bot.room_key = session.join_key
	bot.oracle = oracle
	bot.hole_oracle = hole_oracle
	connect_bot(bot)
	bots.append(bot)
	return bot


func connect_bot(bot: FakePlayerBot) -> void:
	bot.conn_id = session.connect_client({"fake": true, "transport": "loopback"})
	bot.connected = true
	bot_by_conn[bot.conn_id] = bot
	session.receive_text(bot.conn_id, JSON.stringify(bot.hello()))


func disconnect_bot(bot: FakePlayerBot) -> void:
	if not bot.connected:
		return
	bot.connected = false
	bot_by_conn.erase(bot.conn_id)
	session.disconnect_client(bot.conn_id, "sim_disconnect")
	bot.outbox.clear()


func send_raw(bot: FakePlayerBot, text: String) -> void:
	session.receive_text(bot.conn_id, text)


func _on_send(conn_id: int, msg: Dictionary) -> void:
	sent_count += 1
	var bot = bot_by_conn.get(conn_id)
	if bot != null:
		# Round-trip through JSON so bots see exactly what a phone would.
		bot.receive(JSON.parse_string(JSON.stringify(msg)))


func _on_close(conn_id: int, _reason: String) -> void:
	var bot = bot_by_conn.get(conn_id)
	if bot != null:
		bot.connected = false
		bot_by_conn.erase(conn_id)


func step() -> void:
	for bot in bots:
		if not bot.connected:
			continue
		for m in bot.poll(dt):
			if bot.connected:
				session.receive_text(bot.conn_id, JSON.stringify(m))
		# Keepalive like a real controller.
		if int(bot.now / 2.0) != int((bot.now - dt) / 2.0):
			session.receive_text(bot.conn_id, JSON.stringify({"t": "ping", "id": 1, "rtt": 5}))
	session.tick(dt)


## Runs until predicate returns true or max_real_seconds of simulated real time elapse.
func run_until(pred: Callable, max_real_seconds: float) -> bool:
	var t := 0.0
	while t < max_real_seconds:
		if pred.call():
			return true
		step()
		t += dt
	return pred.call()


func events_of(kind: String) -> Array:
	return tv_events.filter(func(e): return e.get("e") == kind)
