class_name SegDnp
extends Segment
## DO NOT PRESS THAT — one cooperative puzzle (CP6; docs/04 §6). Server-authoritative real-time
## state: phones send absolute control values (switch/dial) or press counts (buttons), so a
## duplicated or delayed message can't double-apply. Mistakes have partial consequences (the
## control jams for a few seconds, the clock loses time, the success tier drops) and Graham names
## the culprit. Team score by success tier, small individual bonus for clean play.

const TIERS := ["perfect", "completed", "barely", "failed"]

var tpl: Dictionary
var game_id := "do_not_press_that"
var round_no := 0
var round_of := 0
var multiplier := 1.0
var punish_pid := ""            # previous culprit: gets the decoy (punishment hook)
var qid := ""
var sub := "intro"
var order: Array = []           # player index -> pid
var puzzle: DnpPuzzle
var phase_end := 0.0
var seconds := 75.0
var mistakes := {}              # pid -> count
var jam_until := {}             # control id -> elapsed
var total_mistakes := 0
var tier := ""
var deltas := {}
var tv_offset := 0.0            # timer irregularity: the TV clock runs this many seconds early
var last_say := -100.0


func _init(desc: Dictionary) -> void:
	kind = "dnp"
	tpl = desc.get("item", {})
	round_no = int(desc.get("round", 0))
	round_of = int(desc.get("of", 0))
	multiplier = float(desc.get("multiplier", 1.0))
	allows_late_join_after = false


func start() -> void:
	session.question_counter += 1
	qid = "%s#%d" % [str(tpl.get("id", "dnp")), session.question_counter]
	order = session.active_player_ids()
	session.director.shuffle(order)
	punish_pid = session.director.dnp_culprit
	var decoy_owner := order.find(punish_pid) if punish_pid != "" else -1
	puzzle = DnpPuzzle.generate(tpl, order.size(), session.director.rng, decoy_owner)
	var errs := puzzle.validate()
	if not errs.is_empty():
		session.director.log_decision("DnpRegenerate", str(tpl.get("id")), errs.slice(0, 3))
		puzzle = DnpPuzzle.generate(tpl, order.size(), session.director.rng, decoy_owner)
	seconds = float(tpl.get("seconds", session.cfg.f("dnp.seconds", 75.0)))
	session.director.used_content[str(tpl.get("id", ""))] = true
	duration = 1.0e9
	var lie: bool = session.director.force.has("dnp_timer_lie")
	if not lie and session.director.interference_mode == "standard_transmission" and session.director.familiarity_tier >= 2:
		lie = session.director.rng.randf() < session.cfg.f("dnp.timer_irregularity_chance", 0.04)
	if lie:
		session.director.force.erase("dnp_timer_lie")
		tv_offset = 12.0
		session.director.log_decision("DnpTimerIrregularity", "tv clock -12s", ["phones keep the real time"])
	for pid in order:
		mistakes[pid] = 0
	session.emit_tv({"e": "dnp_puzzle", "qid": qid, "title": str(tpl.get("title", "")), "flavour": str(tpl.get("flavour", "")),
		"display": puzzle.display, "round": round_no, "of": round_of, "controls": puzzle.controls.filter(func(c): return not c.decoy).size(),
		"players": order})
	var t := say_at(0.3, "graham", "dnp_puzzle_intro")
	var dec := puzzle._ctl("x")
	if punish_pid != "" and decoy_owner >= 0:
		t = say_at(t + 0.2, "graham", "dnp_punish", {"pid": punish_pid, "answer": str(dec.label)})
	elif session.director.rng.randf() < 0.5:
		t = say_at(t + 0.2, "graham", "dnp_dont_touch", {"answer": str(dec.label)})
	at(t + 0.3, _open)
	session.push_screens()


func _open() -> void:
	sub = "play"
	phase_end = elapsed + seconds
	session.emit_tv({"e": "dnp_open", "qid": qid, "window": seconds, "tv_offset": tv_offset, "solved": puzzle.solved_count()})
	session.push_screens()


func update(dt: float) -> void:
	elapsed += dt
	while not _timeline.is_empty() and _timeline[0].at <= elapsed:
		_timeline.pop_front().fn.call()
	match sub:
		"play":
			if puzzle.is_solved():
				_finish(true)
			elif elapsed >= phase_end:
				_finish(false)
		"result":
			if elapsed >= phase_end and _timeline.is_empty():
				done = true


func handle_action(player: PlayerState, msg: Dictionary) -> String:
	if str(msg.get("t")) != Protocol.C_CTL:
		return Protocol.E_INVALID_STATE
	if str(msg.get("q", "")) != qid or sub != "play":
		return Protocol.E_STALE
	var pi := order.find(player.player_id)
	if pi < 0:
		return Protocol.E_NOT_PARTICIPANT
	var id := str(msg.get("c", ""))
	var c := puzzle._ctl(id)
	if c.is_empty() or int(c.owner) != pi:
		return Protocol.E_BAD_PAYLOAD          # not your control
	if float(jam_until.get(id, -1.0)) > elapsed:
		return Protocol.E_JAMMED
	var v = Protocol.get_int(msg, "v")
	var n = Protocol.get_int(msg, "n")
	var r := puzzle.act(id, int(v) if v != null else 0, int(n) if n != null else -1)
	if not r.ok:
		return Protocol.E_BAD_PAYLOAD
	if r.mistake != "":
		_mistake(player.player_id, id, str(r.mistake))
	session.emit_tv({"e": "dnp_state", "qid": qid, "solved": puzzle.solved_count(), "of": puzzle.controls.size() - 1, "mistakes": total_mistakes,
		"pid": player.player_id, "control": str(c.label)})
	session.push_screens()
	return ""


func _mistake(pid: String, id: String, kind_: String) -> void:
	mistakes[pid] = int(mistakes.get(pid, 0)) + 1
	total_mistakes += 1
	jam_until[id] = elapsed + session.cfg.f("dnp.jam_seconds", 5.0)
	phase_end -= session.cfg.f("dnp.mistake_time_penalty", 5.0)
	session.director.log_decision("DnpMistake", kind_, ["pid=%s control=%s" % [pid, id]])
	session.emit_tv({"e": "dnp_mistake", "qid": qid, "pid": pid, "kind": kind_, "control": str(puzzle._ctl(id).label)})
	if elapsed - last_say > 6.0:
		last_say = elapsed
		var blamed := pid
		# Very rarely Graham blames the wrong person — only someone he's already targeting.
		if order.size() > 2 and session.director.rng.randf() < 0.06:
			for other in order:
				if other != pid and float(session.director.rel(other).get("target", 0.0)) > 0.3:
					blamed = other
					session.director.log_decision("DnpWrongBlame", other, ["actual=%s" % pid])
					break
		say_at(elapsed + 0.1, "graham", "dnp_decoy" if kind_ == "decoy" else "dnp_mistake", {"pid": blamed})


func _finish(solved: bool) -> void:
	sub = "result"
	var left := maxf(0.0, phase_end - elapsed)
	if not solved:
		tier = "failed"
	elif total_mistakes == 0:
		tier = "perfect"
	elif total_mistakes <= 2 and left > seconds * 0.15:
		tier = "completed"
	else:
		tier = "barely"
	var team := int({"perfect": 1200, "completed": 900, "barely": 500, "failed": 0}[tier] * multiplier)
	for pid in order:
		deltas[pid] = 0
		if not session.players.has(pid):
			continue
		var pts := team
		if tier != "failed" and int(mistakes.get(pid, 0)) == 0:
			pts += int(session.cfg.f("dnp.clean_bonus", 100.0))
		session.players[pid].score += pts
		deltas[pid] = pts
		session.players[pid].history.append({"qid": qid, "content_id": tpl.get("id"), "points": pts, "kind": "dnp"})
	# Culprit of this puzzle (most mistakes) is remembered for the next one's punishment hook.
	var culprit := ""
	for pid in mistakes:
		if int(mistakes[pid]) > 0 and (culprit == "" or int(mistakes[pid]) > int(mistakes[culprit])):
			culprit = pid
	session.director.dnp_culprit = culprit
	if culprit != "":
		var r: Dictionary = session.director.rel(culprit)
		if r.has("irritant"):
			r.irritant = minf(1.0, float(r.irritant) + 0.1)
	var targets := {}
	for c in puzzle.controls:
		targets[str(c.label)] = c.target
	session.emit_tv({"e": "dnp_result", "qid": qid, "tier": tier, "solved": solved, "mistakes": total_mistakes, "culprit": culprit,
		"deltas": deltas, "standings": session.standings()})
	var t := say_at(0.6, "graham", "dnp_" + tier, {"pid": culprit})
	phase_end = elapsed + maxf(5.0, t + 0.8)
	session.push_screens()


func screen_for(player: PlayerState) -> Dictionary:
	var pi := order.find(player.player_id)
	if pi < 0:
		return {"screen": "watch", "data": {"caption": "YOU WILL JOIN AT THE NEXT SEGMENT"}}
	var head := "DO NOT PRESS THAT · %d OF %d" % [round_no, round_of] if round_of > 0 else "DO NOT PRESS THAT"
	match sub:
		"intro":
			var pv := puzzle.panel_for(pi)
			return {"screen": "dnp_panel", "data": {"qid": qid, "header": head, "title": str(tpl.get("title", "")), "live": false,
				"controls": pv.controls, "instructions": pv.instructions, "remaining_ms": 0, "total_ms": 1}}
		"play":
			var pv2 := puzzle.panel_for(pi)
			var remaining := int(maxf(0.0, phase_end - elapsed) / maxf(session.time_scale, 0.001) * 1000.0)
			for c in pv2.controls:
				var j := float(jam_until.get(c.id, -1.0)) - elapsed
				c["jammed_ms"] = int(maxf(0.0, j) / maxf(session.time_scale, 0.001) * 1000.0)
			return {"screen": "dnp_panel", "data": {"qid": qid, "header": head, "title": str(tpl.get("title", "")), "live": true,
				"controls": pv2.controls, "instructions": pv2.instructions, "remaining_ms": remaining,
				"total_ms": int(seconds / maxf(session.time_scale, 0.001) * 1000.0)}}
		_:
			return {"screen": "dnp_result", "data": {"header": head, "tier": tier, "points": int(deltas.get(player.player_id, 0)),
				"mistakes": int(mistakes.get(player.player_id, 0)), "score": player.score}}


func tv_state() -> Dictionary:
	return {"kind": kind, "sub": sub, "solved": puzzle.solved_count() if puzzle else 0}
