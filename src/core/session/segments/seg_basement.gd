class_name SegBasement
extends Segment
## THE BASEMENT — one authored case (CP7; docs/04 §7).
##   setup   — TV shows the mystery; Graham reads it.
##   discuss — every phone holds private evidence; the group talks out loud. A limited number of
##             optional investigations (team-wide limit, one per player) return a private finding.
##             Ends when everyone presses READY or the clock runs out.
##   theory  — each player submits their own answer to every question (no forced consensus).
##   reveal  — the TV shows whether the group agreed, then the best-supported explanation;
##             partial credit per question, small bonus for unused investigations when right.

var case: Dictionary
var game_id := "basement"
var multiplier := 1.0
var qid := ""
var sub := "setup"
var order: Array = []
var deal: BasementCase
var phase_end := 0.0
var ready := {}
var findings := {}            # pid -> {id, label, text}
var used_inv := {}            # investigation id -> pid
var inv_limit := 2
var theories := {}            # pid -> {question_id: option}
var deltas := {}
var discuss_s := 150.0
var theory_s := 45.0


func _init(desc: Dictionary) -> void:
	kind = "basement"
	case = desc.get("item", {})
	multiplier = float(desc.get("multiplier", 1.0))
	allows_late_join_after = false


func start() -> void:
	session.question_counter += 1
	qid = "%s#%d" % [str(case.get("id", "bas")), session.question_counter]
	order = session.active_player_ids()
	session.director.shuffle(order)
	deal = BasementCase.deal(case, order.size(), session.director.rng)
	var errs := deal.validate()
	if not errs.is_empty():
		session.director.log_decision("BasementRedeal", str(case.get("id")), errs.slice(0, 3))
		deal = BasementCase.deal(case, order.size(), session.director.rng)
	inv_limit = maxi(2, int(ceil(order.size() / 2.0)))
	discuss_s = session.cfg.f("basement.discuss_seconds", 120.0) + session.cfg.f("basement.discuss_seconds_per_player", 10.0) * order.size()
	theory_s = session.cfg.f("basement.theory_seconds", 45.0)
	session.director.used_content[str(case.get("id", ""))] = true
	duration = 1.0e9
	session.emit_tv({"e": "bas_case", "qid": qid, "game_id": game_id, "title": str(case.get("title", "")), "setup": str(case.get("setup", "")),
		"location": str(case.get("location", "")), "investigations": (case.get("investigations", []) as Array).map(func(i): return i.label),
		"inv_limit": inv_limit, "players": order})
	var t := say_at(0.3, "graham", "bas_setup")
	at(t + 0.4, _open_discuss)
	session.push_screens()


func _open_discuss() -> void:
	sub = "discuss"
	phase_end = elapsed + discuss_s
	session.emit_tv({"e": "bas_discuss", "qid": qid, "window": discuss_s, "of": _present().size()})
	session.push_screens()


func _present() -> Array:
	return order.filter(func(pid): return session.players.has(pid) and session.players[pid].is_active())


func _all(d: Dictionary) -> bool:
	for pid in _present():
		if not d.has(pid):
			return false
	return true


func update(dt: float) -> void:
	elapsed += dt
	while not _timeline.is_empty() and _timeline[0].at <= elapsed:
		_timeline.pop_front().fn.call()
	match sub:
		"discuss":
			if elapsed >= phase_end or _all(ready):
				_open_theory()
		"theory":
			if elapsed >= phase_end or _all(theories):
				_reveal()
		"reveal":
			if elapsed >= phase_end and _timeline.is_empty():
				done = true


func _open_theory() -> void:
	sub = "theory"
	phase_end = elapsed + theory_s
	session.emit_tv({"e": "bas_theory", "qid": qid, "window": theory_s, "of": _present().size(),
		"questions": (case.get("questions", []) as Array).map(func(q): return q.ask)})
	say_at(0.1, "graham", "bas_theory")
	session.push_screens()


func handle_action(player: PlayerState, msg: Dictionary) -> String:
	var pid := player.player_id
	if not order.has(pid):
		return Protocol.E_NOT_PARTICIPANT
	if str(msg.get("q", "")) != qid:
		return Protocol.E_STALE
	match str(msg.get("t")):
		Protocol.C_INVESTIGATE:
			if sub != "discuss":
				return Protocol.E_STALE
			if findings.has(pid):
				return Protocol.E_ALREADY_ANSWERED
			if used_inv.size() >= inv_limit:
				return Protocol.E_STALE   # budget used up meanwhile
			var i = Protocol.get_int(msg, "i")
			var invs: Array = case.get("investigations", [])
			if i == null or int(i) < 0 or int(i) >= invs.size():
				return Protocol.E_BAD_PAYLOAD
			var node: Dictionary = invs[int(i)]
			if used_inv.has(node.id):
				return Protocol.E_STALE   # somebody already did that one (race)
			used_inv[node.id] = pid
			findings[pid] = {"id": node.id, "label": node.label, "text": node.text}
			session.emit_tv({"e": "bas_investigated", "qid": qid, "pid": pid, "label": node.label, "used": used_inv.size(), "limit": inv_limit})
			session.push_screens()
			return ""
		Protocol.C_READY:
			if sub != "discuss":
				return Protocol.E_STALE
			ready[pid] = true
			session.emit_tv({"e": "bas_ready", "qid": qid, "pid": pid, "count": ready.size(), "of": _present().size()})
			session.push_screens()
			return ""
		Protocol.C_THEORY:
			if sub != "theory":
				return Protocol.E_STALE
			if theories.has(pid):
				return Protocol.E_ALREADY_ANSWERED
			var a = msg.get("a")
			if typeof(a) != TYPE_DICTIONARY:
				return Protocol.E_BAD_PAYLOAD
			var clean := {}
			for qd in case.get("questions", []):
				if a.has(qd.id):
					var k := int(a[qd.id]) if typeof(a[qd.id]) in [TYPE_INT, TYPE_FLOAT] else -1
					if k < 0 or k >= (qd.options as Array).size():
						return Protocol.E_BAD_PAYLOAD
					clean[qd.id] = k
			if clean.is_empty():
				return Protocol.E_BAD_PAYLOAD
			theories[pid] = clean
			session.emit_tv({"e": "bas_theory_in", "qid": qid, "pid": pid, "count": theories.size(), "of": _present().size()})
			session.push_screens()
			return ""
	return Protocol.E_INVALID_STATE


func _reveal() -> void:
	sub = "reveal"
	var qs: Array = case.get("questions", [])
	var tallies := {}
	for qd in qs:
		var t: Array = []
		t.resize((qd.options as Array).size())
		t.fill(0)
		for pid in theories:
			if theories[pid].has(qd.id):
				t[int(theories[pid][qd.id])] += 1
		tallies[qd.id] = t
	var best := deal.best_answers()
	var per_q: float = session.cfg.f("basement.points_per_question", 600.0)
	var unused := inv_limit - used_inv.size()
	var fractions := {}
	for pid in order:
		deltas[pid] = 0
		if not session.players.has(pid):
			continue
		var sc := deal.score(theories.get(pid, {}))
		fractions[pid] = sc.fraction
		var pts := 0
		for qd in qs:
			pts += int(round(per_q * float(sc.per.get(qd.id, 0.0)) * multiplier / 10.0)) * 10
		# investigation efficiency: right answers without using every investigation
		if float(sc.fraction) >= 0.66 and unused > 0:
			pts += int(session.cfg.f("basement.efficiency_bonus", 100.0)) * unused
		session.players[pid].score += pts
		deltas[pid] = pts
		session.players[pid].history.append({"qid": qid, "content_id": case.get("id"), "points": pts, "kind": "basement"})
		if float(sc.fraction) >= 0.66:
			var r: Dictionary = session.director.rel(pid)
			r.interesting = minf(1.0, float(r.get("interesting", 0.0)) + 0.05)
	var agreed := {}
	for qd in qs:
		var t2: Array = tallies[qd.id]
		agreed[qd.id] = t2.max() == theories.size() and theories.size() > 1
	session.emit_tv({"e": "bas_reveal", "qid": qid, "questions": qs.map(func(q): return {"id": q.id, "ask": q.ask, "options": q.options}),
		"tallies": tallies, "best": best, "agreed": agreed, "reveal": str(case.get("reveal", "")), "unresolved": bool(case.get("unresolved", false)),
		"theories": theories, "fractions": fractions, "deltas": deltas, "standings": session.standings()})
	var t := say_at(0.6, "graham", "bas_group_agreed" if agreed.values().all(func(x): return x) else "bas_group_split")
	t += 0.4
	var line_text := str(case.get("graham_reveal", ""))
	var text_t: float = t + session.cfg.f("basement.reveal_read_seconds", 7.0)
	if line_text != "":
		var line := {"id": "case:" + str(case.get("id")), "speaker": "graham", "category": "bas_case_reveal", "text": line_text, "speech": line_text,
			"mood": session.director.graham_mood, "pid": "", "silent": false, "audio": null}
		var dur: float = session.speech_seconds(line)
		at(text_t, func(): session.emit_say(line, dur))
		text_t += dur + 0.3
	if bool(case.get("unresolved", false)):
		text_t = say_at(text_t, "graham", "bas_unresolved") + 0.3
	phase_end = elapsed + maxf(10.0, text_t + 1.5)
	session.push_screens()


func screen_for(player: PlayerState) -> Dictionary:
	var pid := player.player_id
	var pi := order.find(pid)
	if pi < 0:
		return {"screen": "watch", "data": {"caption": "YOU WILL JOIN AT THE NEXT SEGMENT"}}
	var head := str(case.get("title", "THE BASEMENT"))
	var remaining := int(maxf(0.0, phase_end - elapsed) / maxf(session.time_scale, 0.001) * 1000.0)
	match sub:
		"setup", "discuss":
			var invs: Array = case.get("investigations", [])
			var opts: Array = []
			for i in invs.size():
				opts.append({"i": i, "label": invs[i].label, "taken": used_inv.has(invs[i].id)})
			return {"screen": "bas_evidence", "data": {"qid": qid, "header": "THE BASEMENT", "title": head, "live": sub == "discuss",
				"cards": deal.hand_for(pi), "finding": findings.get(pid, {}), "investigations": opts,
				"can_investigate": not findings.has(pid) and used_inv.size() < inv_limit, "inv_left": inv_limit - used_inv.size(),
				"ready": ready.has(pid), "remaining_ms": remaining if sub == "discuss" else 0,
				"total_ms": int(discuss_s / maxf(session.time_scale, 0.001) * 1000.0)}}
		"theory":
			if theories.has(pid):
				return {"screen": "wv_wait", "data": {"header": "THE BASEMENT", "caption": "THEORY FILED. WAITING FOR THE OTHERS."}}
			return {"screen": "bas_theory", "data": {"qid": qid, "header": "THE BASEMENT", "title": head,
				"questions": (case.get("questions", []) as Array).map(func(q): return {"id": q.id, "ask": q.ask, "options": q.options}),
				"cards": deal.hand_for(pi), "finding": findings.get(pid, {}), "remaining_ms": remaining,
				"total_ms": int(theory_s / maxf(session.time_scale, 0.001) * 1000.0)}}
		_:
			return {"screen": "wv_result", "data": {"header": "THE BASEMENT", "points": int(deltas.get(pid, 0)), "score": player.score}}


func tv_state() -> Dictionary:
	return {"kind": kind, "sub": sub, "ready": ready.size(), "theories": theories.size()}
