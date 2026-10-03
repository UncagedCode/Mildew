class_name FakePlayerBot
extends RefCounted
## Development fake player (docs/10 "Fake player system"). Speaks the real controller protocol
## (JSON text through SessionServer.receive_text) so bots exercise the same validation paths
## as phones. Personalities shape timing/accuracy to drive Graham/Director logic.
##
## "Oracle" knowledge (correct answers) is injected by dev tooling only; real phones never
## receive answers.

const PERSONALITIES := ["fast_random", "high_accuracy", "terrible", "afk", "horse", "cautious", "risk_taker"]

var name := "Bot"
var personality := "fast_random"
var conn_id := -1
var player_id := ""
var resume_token := ""
var room_key := ""
var oracle: Callable              # func(content_id: String) -> String (correct option TEXT; options are shuffled per asking)
var hole_oracle: Callable         # func(content_id: String, variant: String) -> String (answer label)
var hole_handled := {}            # "qid:stage" -> true
var rng := RandomNumberGenerator.new()
var outbox: Array = []            # [{at, msg}]
var now := 0.0
var last_screen := {}
var answered_qids := {}
var auto_start_at_count := 0      # captain bot starts the show at this many players (0 = never)
var auto_play_again := false
var _start_sent := false
var _again_sent := false
var connected := true
var errors_received: Array = []
var screens_seen: Array = []


func _init(p_name: String, p_personality: String, seed: int = 0) -> void:
	name = p_name
	personality = p_personality if PERSONALITIES.has(p_personality) else "fast_random"
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()


func hello() -> Dictionary:
	var m := {"t": Protocol.C_HELLO, "v": Protocol.VERSION, "key": room_key}
	if resume_token != "":
		m["resume"] = resume_token
	return m


## Feed one server message; may schedule outgoing messages.
func receive(msg: Dictionary) -> void:
	match str(msg.get("t")):
		Protocol.S_WELCOME:
			if player_id == "":
				var avatar := {"hair": rng.randi_range(0, 5), "hair_colour": rng.randi_range(0, 5), "skin": rng.randi_range(0, 4),
					"glasses": rng.randi_range(0, 2), "outfit": rng.randi_range(0, 7), "accessory": rng.randi_range(0, 5)}
				_queue(0.2, {"t": Protocol.C_CREATE_PROFILE, "name": name, "speech": name, "avatar": avatar})
		Protocol.S_JOINED:
			player_id = str(msg.get("player_id"))
			resume_token = str(msg.get("resume"))
		Protocol.S_ERROR:
			errors_received.append(str(msg.get("code")))
		Protocol.S_SCREEN:
			last_screen = msg
			screens_seen.append(str(msg.get("screen")))
			_on_screen(str(msg.get("screen")), msg.get("data", {}))


func _on_screen(screen: String, data: Dictionary) -> void:
	match screen:
		"lobby":
			_again_sent = false
			if data.get("captain", false) and auto_start_at_count > 0 and int(data.get("count", 0)) >= auto_start_at_count and not _start_sent:
				_start_sent = true
				_queue(0.3, {"t": Protocol.C_START_SHOW})
		"question":
			var qid := str(data.get("qid", ""))
			if answered_qids.has(qid) or personality == "afk":
				return
			answered_qids[qid] = true
			var options: Array = data.get("options", [])
			var window := float(data.get("total_ms", 20000)) / 1000.0
			var choice := _choose(qid, options)
			var delay := _delay(window)
			if delay < window:
				_queue(delay, {"t": Protocol.C_ANSWER, "q": qid, "c": choice})
		"hole_pick":
			_on_hole_pick(data)
		"ended":
			if data.get("captain", false) and auto_play_again and not _again_sent:
				_again_sent = true
				_start_sent = false
				_queue(1.0, {"t": Protocol.C_PLAY_AGAIN})


## Hole: decide at which reveal stage to gamble (docs/10 personalities: risk-taker, cautious...).
func _on_hole_pick(data: Dictionary) -> void:
	var qid := str(data.get("qid", ""))
	var stage := int(data.get("stage", 1))
	var key := "%s:%d" % [qid, stage]
	if hole_handled.has(key) or personality == "afk":
		return
	hole_handled[key] = true
	var options: Array = data.get("options", [])
	var window := float(data.get("total_ms", 8000)) / 1000.0
	var final_stage := int(data.get("final_stage", 4))
	var lock_stage := 2
	var accuracy := 0.5
	match personality:
		"risk_taker":
			lock_stage = 1
			accuracy = 0.45
		"high_accuracy":
			lock_stage = 2
			accuracy = 0.85
		"cautious":
			lock_stage = final_stage
			accuracy = 0.95
		"terrible":
			lock_stage = rng.randi_range(1, 2)
			accuracy = 0.1
		"horse":
			lock_stage = 2
			accuracy = 0.3
		_:
			lock_stage = rng.randi_range(1, final_stage)
			accuracy = 0.4
	if stage < lock_stage:
		if data.get("can_pass", false) and rng.randf() < 0.7:
			_queue(rng.randf_range(0.4, minf(2.0, window * 0.5)), {"t": Protocol.C_PASS, "q": qid, "s": stage})
		return
	var answer := ""
	if hole_oracle.is_valid():
		answer = str(hole_oracle.call(qid.split("#")[0], str(data.get("variant", "standard"))))
	var idx := options.find(answer)
	var choice := rng.randi_range(0, maxi(0, options.size() - 1))
	if idx >= 0 and rng.randf() < accuracy:
		choice = idx
	elif idx >= 0 and options.size() > 1:
		while choice == idx:
			choice = rng.randi_range(0, options.size() - 1)
	if personality == "horse":
		for i in options.size():
			var o := str(options[i]).to_lower()
			if o.contains("horse") or o.contains("pig") or o.contains("whale") or o.contains("cow"):
				choice = i
				break
	var delay := rng.randf_range(0.5, maxf(0.6, window * 0.6))
	if delay < window:
		_queue(delay, {"t": Protocol.C_LOCK, "q": qid, "s": stage, "c": choice})


func _choose(qid: String, options: Array) -> int:
	var correct := -1
	if oracle.is_valid():
		correct = options.find(str(oracle.call(qid.split("#")[0])))
	match personality:
		"high_accuracy", "cautious":
			if correct >= 0 and rng.randf() < 0.9:
				return correct
		"terrible":
			if correct >= 0 and options.size() > 1:
				var wrong := range(options.size()).filter(func(i): return i != correct)
				return wrong[rng.randi_range(0, wrong.size() - 1)]
		"horse":
			for i in options.size():
				if str(options[i]).to_lower().contains("horse"):
					return i
			return 0
	return rng.randi_range(0, max(0, options.size() - 1))


func _delay(window: float) -> float:
	match personality:
		"fast_random":
			return rng.randf_range(0.6, 2.0)
		"high_accuracy":
			return rng.randf_range(1.5, window * 0.4)
		"terrible":
			return rng.randf_range(1.0, window * 0.7)
		"cautious":
			return rng.randf_range(window * 0.5, window * 0.9)
		"horse":
			return rng.randf_range(0.8, 3.0)
	return rng.randf_range(1.0, window * 0.6)


func _queue(delay: float, msg: Dictionary) -> void:
	outbox.append({"at": now + delay, "msg": msg})


## Advance bot time (seconds, *real* time from the phone's perspective) and return due messages.
func poll(dt: float) -> Array:
	now += dt
	var due: Array = []
	var keep: Array = []
	for o in outbox:
		if o.at <= now:
			due.append(o.msg)
		else:
			keep.append(o)
	outbox = keep
	return due
