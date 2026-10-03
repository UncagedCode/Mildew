class_name SegSpecial
extends Segment
## Rare programme specials (CP8).
##   mode "punish"   — {NAME}'S EASY QUESTION (docs/01 §4): Graham singles out one contestant with a
##                     ridiculous question. Only their phone answers; the rest watch. Success is
##                     celebrated absurdly (+100), failure gets "Extraordinary." Theatrical, about
##                     in-game behaviour only.
##   mode "the_test" — THE TEST, a hidden Interruption Game: the programme is replaced by a test card
##                     and every phone gets a few unexplained questions (different per phone). Unscored;
##                     answers stay local and are never shown back. Then Graham apologises.

var mode := "punish"
var pid := ""
var item: Dictionary
var qid := ""
var sub := ""
var options: Array = []
var correct := 0
var answer := -1
var phase_end := 0.0
var test_qs := {}          # pid -> [[q, options]]
var test_i := {}           # pid -> index answered so far
var test_answers := {}


func _init(desc: Dictionary) -> void:
	kind = "special"
	mode = str(desc.get("mode", "punish"))
	pid = str(desc.get("pid", ""))
	item = desc.get("item", {})


func start() -> void:
	duration = 1.0e9
	session.question_counter += 1
	qid = "%s#%d" % [mode, session.question_counter]
	if mode == "punish":
		_start_punish()
	else:
		_start_test()
	session.push_screens()


func _start_punish() -> void:
	if not session.players.has(pid):
		sub = "done"
		phase_end = 0.0
		return
	options = (item.get("options", []) as Array).duplicate()
	var right: String = options[int(item.get("correct", 0))]
	session.director.shuffle(options)
	correct = options.find(right)
	var name: String = session.players[pid].display_name
	session.emit_tv({"e": "special_punish", "qid": qid, "pid": pid, "title": "%s'S EASY QUESTION" % name.to_upper(),
		"prompt": str(item.get("prompt", "")), "options": options})
	var t := say_at(0.3, "graham", "punish_intro", {"pid": pid})
	sub = "ask"
	phase_end = t + session.cfg.f("special.punish_seconds", 12.0)
	session.director.log_decision("Punishment", pid, ["easy question %s" % item.get("id")])


func _start_test() -> void:
	var qs: Array = item.get("questions", [])
	for p in session.active_player_ids():
		var mine := qs.duplicate()
		session.director.shuffle(mine)
		test_qs[p] = mine.slice(0, 3)
		test_i[p] = 0
	session.emit_tv({"e": "special_test", "qid": qid})
	sub = "test"
	phase_end = session.cfg.f("special.test_seconds", 18.0)
	session.director._tone("unsettling", 0.3)
	session.director.log_decision("InterruptionGame", "THE TEST", ["familiarity=%d" % session.director.familiarity_tier])


func update(dt: float) -> void:
	elapsed += dt
	while not _timeline.is_empty() and _timeline[0].at <= elapsed:
		_timeline.pop_front().fn.call()
	match sub:
		"ask":
			if answer >= 0 or elapsed >= phase_end:
				_punish_result()
		"test":
			var all_done := true
			for p in test_qs:
				if int(test_i[p]) < (test_qs[p] as Array).size() and session.players.has(p) and session.players[p].connected:
					all_done = false
			if elapsed >= phase_end or all_done:
				_test_end()
		_:
			if elapsed >= phase_end and _timeline.is_empty():
				done = true


func _punish_result() -> void:
	sub = "done"
	var ok := answer == correct
	if ok and session.players.has(pid):
		session.players[pid].score += 100
	session.emit_tv({"e": "special_punish_result", "qid": qid, "pid": pid, "correct": correct, "answer": answer, "ok": ok})
	var t := say_at(0.8, "graham", "punish_success" if ok else "punish_fail", {"pid": pid})
	phase_end = elapsed + maxf(4.0, t + 0.8)
	session.push_screens()


func _test_end() -> void:
	sub = "done"
	var store_answers: Array = session.store.installation.get("the_test", [])
	store_answers.append(test_answers)
	session.store.installation.the_test = store_answers.slice(maxi(0, store_answers.size() - 10))
	session.emit_tv({"e": "special_test_end", "qid": qid})
	var t := say_at(1.2, "graham", "test_after")
	phase_end = elapsed + maxf(3.0, t + 0.5)
	session.push_screens()


func handle_action(player: PlayerState, msg: Dictionary) -> String:
	if str(msg.get("t")) != Protocol.C_ANSWER or str(msg.get("q", "")) != qid:
		return Protocol.E_STALE
	var c = Protocol.get_int(msg, "c")
	if c == null:
		return Protocol.E_BAD_PAYLOAD
	if sub == "ask":
		if player.player_id != pid:
			return Protocol.E_NOT_PARTICIPANT
		if int(c) < 0 or int(c) >= options.size():
			return Protocol.E_BAD_PAYLOAD
		answer = int(c)
		return ""
	if sub == "test" and test_qs.has(player.player_id):
		var i := int(test_i[player.player_id])
		var qs: Array = test_qs[player.player_id]
		if i >= qs.size():
			return Protocol.E_ALREADY_ANSWERED
		if int(c) < 0 or int(c) >= (qs[i][1] as Array).size():
			return Protocol.E_BAD_PAYLOAD
		if not test_answers.has(player.player_id):
			test_answers[player.player_id] = []
		test_answers[player.player_id].append([qs[i][0], qs[i][1][int(c)]])
		test_i[player.player_id] = i + 1
		session.push_screens()
		return ""
	return Protocol.E_STALE


func screen_for(player: PlayerState) -> Dictionary:
	var p := player.player_id
	match sub:
		"ask":
			if p == pid:
				return {"screen": "question", "data": {"qid": qid, "header": "YOUR EASY QUESTION", "prompt": str(item.get("prompt", "")),
					"options": options, "remaining_ms": int(maxf(0.0, phase_end - elapsed) / maxf(session.time_scale, 0.001) * 1000.0),
					"total_ms": int(session.cfg.f("special.punish_seconds", 12.0) / maxf(session.time_scale, 0.001) * 1000.0)}}
			var who: String = session.players[pid].display_name if session.players.has(pid) else "THEM"
			return {"screen": "watch", "data": {"caption": "WATCH %s. DON'T HELP." % who.to_upper()}}
		"test":
			if test_qs.has(p) and int(test_i[p]) < (test_qs[p] as Array).size():
				var q: Array = test_qs[p][int(test_i[p])]
				return {"screen": "test_q", "data": {"qid": qid, "ask": q[0], "options": q[1]}}
			return {"screen": "test_wait", "data": {}}
	return {"screen": "watch", "data": {"caption": "PLEASE WATCH YOUR TELEVISION"}}
