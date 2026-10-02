class_name SegQuestion
extends Segment
## Generic server-authoritative multiple-choice question (CP1 Studio Rehearsal; the same
## engine will back Real or Mildew? / Guess the Genitals in CP3).
## Sub-phases: read -> answer -> lock -> reveal. The answer window closes early once every
## present participant has answered; silent players never deadlock it (timer resolves).

var item: Dictionary
var game_id := ""
var qid := ""
var sub := "read"
var participants: Array = []      # player_ids snapshot at start
var answers := {}                 # pid -> {c, t}
var read_t := 3.0
var answer_window := 20.0
var lock_t := 1.4
var reveal_min := 6.5
var open_at := 0.0
var lock_at := 0.0
var reveal_end := 0.0
var multiplier := 1.0
var results: Array = []
var deltas := {}


func _init(desc: Dictionary) -> void:
	kind = "question"
	item = desc.get("item", {})
	game_id = str(desc.get("game_id", ""))
	multiplier = float(desc.get("multiplier", 1.0))
	allows_late_join_after = false


func start() -> void:
	session.question_counter += 1
	qid = "%s#%d" % [str(item.get("id", "q")), session.question_counter]
	participants = session.active_player_ids()
	read_t = session.cfg.f("show.question_read_seconds", 3.0)
	answer_window = session.cfg.f("show.question_answer_seconds", 20.0)
	lock_t = session.cfg.f("show.question_lock_seconds", 1.4)
	reveal_min = session.cfg.f("show.question_reveal_seconds", 6.5)
	duration = 1.0e9
	session.emit_tv({"e": "question_show", "qid": qid, "game_id": game_id, "prompt": item.get("prompt", ""),
		"options": item.get("options", []), "number": session.question_counter})
	say_at(0.2, "graham", "question_read")
	session.push_screens()


func update(dt: float) -> void:
	elapsed += dt
	while not _timeline.is_empty() and _timeline[0].at <= elapsed:
		_timeline.pop_front().fn.call()
	match sub:
		"read":
			if elapsed >= read_t:
				_open()
		"answer":
			if elapsed >= open_at + answer_window or _all_answered():
				_lock()
		"lock":
			if elapsed >= lock_at + lock_t:
				_reveal()
		"reveal":
			if elapsed >= reveal_end and _timeline.is_empty():
				done = true


func _open() -> void:
	sub = "answer"
	open_at = elapsed
	session.emit_tv({"e": "question_open", "qid": qid, "window": answer_window})
	session.push_screens()


func _all_answered() -> bool:
	var waiting := 0
	for pid in participants:
		var p: PlayerState = session.players.get(pid)
		if p == null or not p.is_active():
			continue
		if not answers.has(pid):
			waiting += 1
	return waiting == 0


func _lock() -> void:
	sub = "lock"
	lock_at = elapsed
	session.emit_tv({"e": "question_locked", "qid": qid, "answered": answers.size(), "of": participants.size()})
	session.push_screens()


func _reveal() -> void:
	sub = "reveal"
	var correct_idx := int(item.get("correct", -1))
	var base := int(round(float(item.get("points", 1000)) * multiplier))
	var speed_frac: float = session.cfg.f("scoring.speed_bonus_fraction_max", 0.15)
	results.clear()
	deltas.clear()
	var picks := {}
	for pid in participants:
		var p: PlayerState = session.players.get(pid)
		if p == null:
			continue
		var a = answers.get(pid)
		var answered: bool = a != null
		var is_correct: bool = answered and int(a.c) == correct_idx
		var elapsed_s: float = float(a.t) if answered else answer_window
		var pts := 0
		if is_correct:
			var speed := clampf(1.0 - elapsed_s / answer_window, 0.0, 1.0)
			var bonus := int(round(base * speed_frac * speed / 10.0)) * 10
			pts = base + bonus
			var streak: int = int(session.director.stats(pid).correct_streak) + 1
			if streak >= 3:
				pts += 50  # small streak bonus only (docs/05)
		p.score += pts  # wrong / no answer = 0, never negative
		deltas[pid] = pts
		if answered:
			picks[pid] = int(a.c)
		results.append({"pid": pid, "answered": answered, "correct": is_correct, "elapsed": elapsed_s, "points": pts})
		p.history.append({"qid": qid, "content_id": item.get("id"), "answered": answered, "correct": is_correct, "elapsed": elapsed_s, "points": pts})
	var reaction: Dictionary = session.director.on_question_result(results, answer_window)
	var options: Array = item.get("options", [])
	var answer_text: String = str(options[correct_idx]) if correct_idx >= 0 and correct_idx < options.size() else ""
	session.emit_tv({"e": "reveal", "qid": qid, "correct": correct_idx, "answer_text": answer_text,
		"picks": picks, "deltas": deltas, "standings": session.standings()})
	session.push_screens()
	var t := 0.6
	if item.has("reveal_line"):
		var line := {"id": "%s.reveal" % item.get("id"), "speaker": "graham", "category": "reveal",
			"text": str(item.reveal_line), "speech": str(item.reveal_line), "mood": session.director.graham_mood, "silent": false}
		var dur: float = session.speech_seconds(line)
		at(t, func(): session.emit_say(line, dur))
		t += dur + 0.3
	else:
		t = say_at(t, "graham", "reveal", {"answer": answer_text}) + 0.3
	if reaction.category != "":
		t = say_at(t, "graham", reaction.category, reaction.ctx) + 0.3
	for extra in reaction.extra:
		t = say_at(t, "graham", extra.category, extra.ctx) + 0.3
	reveal_end = elapsed + maxf(reveal_min, t + 0.5)


func handle_action(player: PlayerState, msg: Dictionary) -> String:
	if str(msg.get("t")) != Protocol.C_ANSWER:
		return Protocol.E_INVALID_STATE
	if sub != "answer":
		return Protocol.E_INVALID_STATE
	if str(msg.get("q", "")) != qid:
		return Protocol.E_STALE
	if not participants.has(player.player_id):
		return Protocol.E_NOT_PARTICIPANT
	if answers.has(player.player_id):
		return Protocol.E_ALREADY_ANSWERED
	var c = Protocol.get_int(msg, "c")
	if c == null or int(c) < 0 or int(c) >= (item.get("options", []) as Array).size():
		return Protocol.E_BAD_PAYLOAD
	answers[player.player_id] = {"c": int(c), "t": elapsed - open_at}
	session.emit_tv({"e": "answer_in", "pid": player.player_id, "count": answers.size(), "of": participants.size()})
	return ""


func screen_for(player: PlayerState) -> Dictionary:
	if not participants.has(player.player_id):
		return {"screen": "watch", "data": {"caption": "YOU WILL JOIN AT THE NEXT SEGMENT"}}
	var options: Array = item.get("options", [])
	match sub:
		"read":
			return {"screen": "get_ready", "data": {"caption": "QUESTION INCOMING", "number": session.question_counter}}
		"answer":
			if answers.has(player.player_id):
				var c := int(answers[player.player_id].c)
				return {"screen": "locked", "data": {"qid": qid, "choice": c, "text": options[c]}}
			var remaining: float = maxf(0.0, open_at + answer_window - elapsed) / maxf(session.time_scale, 0.001)
			return {"screen": "question", "data": {"qid": qid, "prompt": item.get("prompt", ""), "options": options,
				"remaining_ms": int(remaining * 1000.0), "total_ms": int(answer_window / maxf(session.time_scale, 0.001) * 1000.0)}}
		"lock":
			if answers.has(player.player_id):
				var c2 := int(answers[player.player_id].c)
				return {"screen": "locked", "data": {"qid": qid, "choice": c2, "text": options[c2]}}
			return {"screen": "locked", "data": {"qid": qid, "choice": -1, "text": ""}}
		_:
			var correct_idx := int(item.get("correct", -1))
			var mine = answers.get(player.player_id)
			return {"screen": "result", "data": {
				"answered": mine != null,
				"correct": mine != null and int(mine.c) == correct_idx,
				"points": int(deltas.get(player.player_id, 0)),
				"answer_text": str(options[correct_idx]) if correct_idx >= 0 else "",
				"score": player.score,
			}}


func tv_state() -> Dictionary:
	return {"kind": kind, "sub": sub, "qid": qid, "answered": answers.size(), "of": participants.size(),
		"remaining": maxf(0.0, open_at + answer_window - elapsed) if sub == "answer" else 0.0}
