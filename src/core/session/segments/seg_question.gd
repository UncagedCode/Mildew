class_name SegQuestion
extends Segment
## Generic server-authoritative multiple-choice question: Studio Rehearsal (CP1), Real or Mildew?
## and Guess the Genitals (CP3). Options are shuffled per asking (an `all_real` round keeps its
## "they're all real" option last). Optional: image, TV layout, confidence wager (I'M CERTAIN = x2),
## final-question multiplier, factual explanation shown after the reveal and archived for the
## Viewer Information Service (sources never shown during play — docs/07).
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
var options: Array = []           # shuffled presentation order
var correct_idx := -1
var layout := "panel"             # panel (rehearsal) | claims (Real or Mildew?) | image (Guess the Genitals)
var title := ""
var confidence := false           # I'M CERTAIN wager available
var final_q := false
var round_no := 0
var round_of := 0
var reaction_prefix := ""         # game-specific Graham line prefix, e.g. "rom" / "gtg"


func _init(desc: Dictionary) -> void:
	kind = "question"
	item = desc.get("item", {})
	game_id = str(desc.get("game_id", ""))
	multiplier = float(desc.get("multiplier", 1.0))
	layout = str(desc.get("layout", "panel"))
	title = str(desc.get("title", ""))
	confidence = bool(desc.get("confidence", false))
	final_q = bool(desc.get("final", false))
	round_no = int(desc.get("round", 0))
	round_of = int(desc.get("of", 0))
	reaction_prefix = str(desc.get("prefix", ""))
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
	_shuffle()
	session.director.used_content[str(item.get("id", ""))] = true
	session.emit_tv({"e": "question_show", "qid": qid, "game_id": game_id, "prompt": item.get("prompt", ""),
		"options": options, "number": session.question_counter, "layout": layout, "title": title,
		"image": item.get("image", ""), "crop": item.get("crop", {}), "round": round_no, "of": round_of,
		"final": final_q, "confidence": confidence, "category": item.get("category", ""), "variant": str(item.get("round", ""))})
	if final_q and reaction_prefix != "":
		say_at(0.2, "graham", reaction_prefix + "_final")
	elif confidence and reaction_prefix != "":
		say_at(0.2, "graham", reaction_prefix + "_certain_intro")
	elif reaction_prefix != "":
		say_at(0.2, "graham", reaction_prefix + "_ask")
	else:
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


static func grossness(it: Dictionary) -> int:
	var g := 0
	for t in it.get("content_tags", []):
		if str(t).begins_with("grossness_"):
			g = maxi(g, int(str(t).substr(10)))
	return g


## Presentation order is random per asking; scoring follows the shuffled index.
func _shuffle() -> void:
	var src: Array = item.get("options", [])
	var src_correct := int(item.get("correct", -1))
	var order: Array = range(src.size())
	var fixed_last := str(item.get("round", "")) == "all_real" or bool(item.get("fixed_last", false))
	var movable: Array = order.slice(0, order.size() - 1) if fixed_last else order.duplicate()
	if not bool(item.get("no_shuffle", false)):
		session.director.shuffle(movable)
	if fixed_last:
		movable.append(order[-1])
	options = movable.map(func(i): return src[i])
	correct_idx = movable.find(src_correct)


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
	var base := int(round(float(item.get("points", 1000)) * multiplier))
	var speed_frac: float = session.cfg.f("scoring.speed_bonus_fraction_max", 0.15)
	var certain_mult: float = session.cfg.f("scoring.confidence_multiplier", 2.0)
	var gross := SegQuestion.grossness(item) >= 3
	results.clear()
	deltas.clear()
	var picks := {}
	var certain := {}
	for pid in participants:
		var p: PlayerState = session.players.get(pid)
		if p == null:
			continue
		var a = answers.get(pid)
		var answered: bool = a != null
		var is_correct: bool = answered and int(a.c) == correct_idx
		var is_certain: bool = answered and bool(a.get("k", false))
		var elapsed_s: float = float(a.t) if answered else answer_window
		var pts := 0
		if is_correct:
			var speed := clampf(1.0 - elapsed_s / answer_window, 0.0, 1.0)
			var bonus := int(round(base * speed_frac * speed / 10.0)) * 10
			pts = base + bonus
			var streak: int = int(session.director.stats(pid).correct_streak) + 1
			if streak >= 3:
				pts += 50  # small streak bonus only (docs/05)
			if is_certain:
				pts = int(round(pts * certain_mult / 10.0)) * 10
			if gross and elapsed_s < answer_window * 0.25:
				p.add_rot(1)  # fast recognition of something revolting is noted (docs/05 Rot)
		p.score += pts  # wrong / no answer = 0, never negative (a confident wrong answer costs only pride)
		deltas[pid] = pts
		if answered:
			picks[pid] = int(a.c)
			if is_certain:
				certain[pid] = true
		results.append({"pid": pid, "answered": answered, "correct": is_correct, "elapsed": elapsed_s, "points": pts, "certain": is_certain, "choice": int(a.c) if answered else -1})
		p.history.append({"qid": qid, "content_id": item.get("id"), "answered": answered, "correct": is_correct, "elapsed": elapsed_s, "points": pts, "certain": is_certain})
	var reaction: Dictionary = session.director.on_question_result(results, answer_window, item, options)
	var answer_text: String = str(options[correct_idx]) if correct_idx >= 0 and correct_idx < options.size() else ""
	var stamps: Array = []
	if layout == "claims":
		for i in options.size():
			match str(item.get("round", "")):
				"which_real":
					stamps.append("REAL" if i == correct_idx else "MILDEW")
				"one_mildew":
					stamps.append("MILDEW" if i == correct_idx else "REAL")
				"all_real":
					stamps.append("REAL" if i != options.size() - 1 else "")
				_:
					stamps.append("")
	var fact := str(item.get("fact", ""))
	if fact != "":
		session.note_fact(str(item.get("id", "")))
	session.emit_tv({"e": "reveal", "qid": qid, "game_id": game_id, "correct": correct_idx, "answer_text": answer_text,
		"picks": picks, "certain": certain, "deltas": deltas, "standings": session.standings(), "layout": layout,
		"stamps": stamps, "fact": fact, "answer_label": str(item.get("answer_label", answer_text)),
		"image": item.get("image", ""), "gross": gross})
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
	var fact_hold := 0.0
	if fact != "":
		fact_hold = clampf(fact.length() / 18.0, 4.0, 9.0)   # readable time for the fact card
	reveal_end = elapsed + maxf(reveal_min + fact_hold * 0.5, t + 0.5)


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
	if c == null or int(c) < 0 or int(c) >= options.size():
		return Protocol.E_BAD_PAYLOAD
	var k := confidence and int(msg.get("k", 0)) == 1
	answers[player.player_id] = {"c": int(c), "t": elapsed - open_at, "k": k}
	session.emit_tv({"e": "answer_in", "pid": player.player_id, "count": answers.size(), "of": participants.size()})
	return ""


func screen_for(player: PlayerState) -> Dictionary:
	if not participants.has(player.player_id):
		return {"screen": "watch", "data": {"caption": "YOU WILL JOIN AT THE NEXT SEGMENT"}}
	var head := title if title != "" else ""
	if round_of > 0:
		head = "%s · %s" % [title, "FINAL QUESTION" if final_q else "QUESTION %d OF %d" % [round_no, round_of]]
	match sub:
		"read":
			return {"screen": "get_ready", "data": {"caption": "QUESTION INCOMING", "number": session.question_counter, "header": head}}
		"answer":
			if answers.has(player.player_id):
				var c := int(answers[player.player_id].c)
				return {"screen": "locked", "data": {"qid": qid, "choice": c, "text": options[c], "certain": bool(answers[player.player_id].k), "header": head}}
			var remaining: float = maxf(0.0, open_at + answer_window - elapsed) / maxf(session.time_scale, 0.001)
			return {"screen": "question", "data": {"qid": qid, "prompt": item.get("prompt", ""), "options": options,
				"remaining_ms": int(remaining * 1000.0), "total_ms": int(answer_window / maxf(session.time_scale, 0.001) * 1000.0),
				"confidence": confidence, "long": layout == "claims", "header": head}}
		"lock":
			if answers.has(player.player_id):
				var c2 := int(answers[player.player_id].c)
				return {"screen": "locked", "data": {"qid": qid, "choice": c2, "text": options[c2], "certain": bool(answers[player.player_id].k), "header": head}}
			return {"screen": "locked", "data": {"qid": qid, "choice": -1, "text": "", "header": head}}
		_:
			var mine = answers.get(player.player_id)
			return {"screen": "result", "data": {
				"answered": mine != null,
				"correct": mine != null and int(mine.c) == correct_idx,
				"certain": mine != null and bool(mine.k),
				"points": int(deltas.get(player.player_id, 0)),
				"answer_text": str(item.get("answer_label", options[correct_idx] if correct_idx >= 0 else "")),
				"score": player.score,
				"header": head,
			}}


func tv_state() -> Dictionary:
	return {"kind": kind, "sub": sub, "qid": qid, "answered": answers.size(), "of": participants.size(),
		"remaining": maxf(0.0, open_at + answer_window - elapsed) if sub == "answer" else 0.0}
