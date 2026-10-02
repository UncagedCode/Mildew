class_name SegHole
extends Segment
## One round of HOLE (docs/04 §2, docs/12 Hole ledger). Server-authoritative.
##
##   intro -> stage 1 (extreme close-up) -> stage 2 (partial zoom-out) -> stage 3 (broader context)
##         -> stage 4 (multiple-choice safety net; omitted in the ADVANCED OPEN GUESS variant)
##         -> closing -> reveal
##
## On stages 1-3 a contestant may LOCK IN one of the candidate identities; earlier = more points,
## and a lock can never be changed. "SHOW ME MORE" (pass) lets the room skip ahead once every
## unlocked contestant has passed; the round closes as soon as everyone has locked. Timers always
## resolve, so absent/silent phones can never deadlock a round.
## Wrong = 0 (never negative). Optional small partial credit for the right broad category on
## stages 1-3. Variants: "standard", "scale" (how big is it?), "open" (no safety net).

const SCALE_LABELS := ["MICROSCOPIC", "A FEW CENTIMETRES", "PERSON-SIZED", "ENORMOUS"]
const SCALE_KEYS := ["microscopic", "centimetres", "human", "enormous"]

var item: Dictionary
var game_id := "hole"
var variant := "standard"
var qid := ""
var round_no := 1
var round_count := 1
var multiplier := 1.0
var sub := "intro"                 # intro | stage | closing | reveal
var stage := 0
var final_stage := 4
var participants: Array = []
var options: Array = []            # labels offered on stages 1..3
var option_cats: Array = []
var net: Array = []                # labels offered on the safety-net stage
var answer := ""
var answer_cat := ""
var locks := {}                    # pid -> {label, stage, t}
var passes := {}                   # pid -> stage passed
var stage_started := 0.0
var stage_lengths: Array = [0.0, 9.0, 8.0, 8.0, 12.0]
var lock_grace := 0.5
var close_t := 1.3
var reveal_min := 7.0
var intro_t := 2.6
var closing_at := 0.0
var reveal_end := 0.0
var deltas := {}
var outcome := {}                  # pid -> {label, stage, correct, partial, points}
var _early_lock_called := false


func _init(desc: Dictionary) -> void:
	kind = "hole_round"
	item = desc.get("item", {})
	game_id = str(desc.get("game_id", "hole"))
	variant = str(desc.get("variant", "standard"))
	round_no = int(desc.get("round", 1))
	round_count = int(desc.get("of", 1))
	multiplier = float(desc.get("multiplier", 1.0))
	allows_late_join_after = false


func start() -> void:
	var cfg: MildewConfig = session.cfg
	session.question_counter += 1
	qid = "%s#%d" % [str(item.get("id", "hole")), session.question_counter]
	participants = session.active_player_ids()
	var sl = cfg.get_value("hole.stage_seconds", [9.0, 8.0, 8.0, 12.0])
	stage_lengths = [0.0]
	for v in sl:
		stage_lengths.append(float(v))
	lock_grace = cfg.f("hole.lock_grace_seconds", 0.5)
	close_t = cfg.f("hole.close_seconds", 1.3)
	reveal_min = cfg.f("hole.reveal_min_seconds", 7.0)
	intro_t = cfg.f("hole.intro_seconds", 2.6)
	_build_options()
	if variant == "open":
		final_stage = 3
		stage_lengths[3] = cfg.f("hole.open_final_stage_seconds", 11.0)
	duration = 1.0e9
	session.emit_tv({"e": "hole_round", "qid": qid, "item_id": item.get("id"), "image": item.get("image", ""),
		"stages": item.get("stages", []), "round": round_no, "of": round_count, "variant": variant,
		"studio_hole": bool(item.get("studio_hole", false)), "final_stage": final_stage})
	var cat := "hole_round_start"
	if variant == "scale":
		cat = "hole_scale_intro"
	elif variant == "open":
		cat = "hole_open_intro"
	say_at(0.2, "graham", cat, {"count": round_no})
	session.push_screens()


func _build_options() -> void:
	if variant == "scale":
		options = SCALE_LABELS.duplicate()
		option_cats = SCALE_KEYS.duplicate()
		var k := SCALE_KEYS.find(str(item.get("scale", "centimetres")))
		answer = SCALE_LABELS[maxi(0, k)]
		answer_cat = ""
		net = options.duplicate()
		return
	answer = str(item.get("answer", ""))
	answer_cat = str(item.get("category", ""))
	var cands: Array = item.get("candidates", []).duplicate()
	session.director.shuffle(cands)
	options = cands.map(func(c): return str(c.get("label", "")))
	option_cats = cands.map(func(c): return str(c.get("category", "")))
	net = item.get("safety_net", []).duplicate()
	session.director.shuffle(net)


func stage_points(s: int) -> int:
	var key := "hole.final_multiple_choice_points" if s >= 4 else "hole.lock_stage_%d_points" % s
	var defaults := {1: 1500, 2: 1100, 3: 750, 4: 500}
	return int(round(session.cfg.i(key, defaults.get(mini(s, 4), 500)) * multiplier))


func labels_for_stage(s: int) -> Array:
	return net if (s >= 4 and final_stage == 4) else options


func update(dt: float) -> void:
	elapsed += dt
	while not _timeline.is_empty() and _timeline[0].at <= elapsed:
		_timeline.pop_front().fn.call()
	match sub:
		"intro":
			if elapsed >= intro_t:
				_begin_stage(1)
		"stage":
			if _everyone_locked():
				_close()
			elif elapsed >= stage_started + float(stage_lengths[stage]) or (stage < final_stage and _everyone_passed_or_locked()):
				if stage < final_stage:
					_begin_stage(stage + 1)
				else:
					_close()
		"closing":
			if elapsed >= closing_at + close_t:
				_reveal()
		"reveal":
			if elapsed >= reveal_end and _timeline.is_empty():
				done = true


func _present_participants() -> Array:
	var out: Array = []
	for pid in participants:
		var p: PlayerState = session.players.get(pid)
		if p != null and p.is_active():
			out.append(pid)
	return out


func _everyone_locked() -> bool:
	var present := _present_participants()
	if present.is_empty():
		return true
	for pid in present:
		if not locks.has(pid):
			return false
	return true


func _everyone_passed_or_locked() -> bool:
	var present := _present_participants()
	for pid in present:
		if not locks.has(pid) and int(passes.get(pid, 0)) < stage:
			return false
	return true


func _begin_stage(s: int) -> void:
	sub = "stage"
	stage = s
	stage_started = elapsed
	var is_net := s >= 4
	var evt := {"e": "hole_stage", "qid": qid, "stage": s, "final": s == final_stage, "points": stage_points(s),
		"safety_net": is_net, "window": float(stage_lengths[s]) / maxf(session.time_scale, 0.001),
		"locked": locks.size(), "of": participants.size()}
	if is_net:
		evt["options"] = net
	session.emit_tv(evt)
	if s >= 2:
		var cat := "hole_safety_net" if is_net else ("hole_last_look" if s == final_stage else "hole_stage_more")
		say_at(elapsed + 0.15, "graham", cat, {"points": fmt_points(stage_points(s))})
	session.push_screens()


static func fmt_points(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _close() -> void:
	sub = "closing"
	closing_at = elapsed
	session.emit_tv({"e": "hole_closed", "qid": qid, "locked": locks.size(), "of": participants.size()})
	session.push_screens()


func _reveal() -> void:
	sub = "reveal"
	var partial_frac: float = session.cfg.f("hole.partial_credit_fraction", 0.2)
	var results: Array = []
	deltas.clear()
	outcome.clear()
	var gross := _grossness()
	for pid in participants:
		var p: PlayerState = session.players.get(pid)
		if p == null:
			continue
		var lk = locks.get(pid)
		var pts := 0
		var correct := false
		var partial := false
		var label := ""
		var at_stage := 0
		if lk != null:
			label = str(lk.label)
			at_stage = int(lk.stage)
			correct = label == answer
			if correct:
				pts = stage_points(at_stage)
			elif at_stage <= 3 and answer_cat != "" and _category_of(label) == answer_cat and not item.get("no_partial", false):
				partial = true
				pts = int(round(stage_points(at_stage) * partial_frac / 50.0)) * 50
		p.score += pts
		if correct and at_stage == 1 and gross >= 2:
			p.add_rot(gross)  # recognising something revolting from a glimpse is noted (docs/05 Rot)
		deltas[pid] = pts
		outcome[pid] = {"label": label, "stage": at_stage, "correct": correct, "partial": partial, "points": pts}
		results.append({"pid": pid, "answered": lk != null, "correct": correct, "partial": partial, "stage": at_stage,
			"elapsed": float(lk.t) if lk != null else 99.0, "points": pts})
		p.history.append({"qid": qid, "content_id": item.get("id"), "game": "hole", "answered": lk != null,
			"correct": correct, "stage": at_stage, "points": pts})
	var reaction: Dictionary = session.director.on_hole_result(results, item, variant)
	session.emit_tv({"e": "hole_reveal", "qid": qid, "answer": answer, "outcome": outcome, "deltas": deltas,
		"standings": session.standings(), "studio_hole": bool(item.get("studio_hole", false))})
	session.push_screens()
	var t := 0.7
	if item.get("studio_hole", false):
		t = say_at(t, "graham", "hole_studio_reveal") + 0.4
	else:
		var rl := str(item.get("reveal_line", ""))
		if variant == "scale":
			t = say_at(t, "graham", "hole_scale_reveal", {"answer": answer.to_lower()}) + 0.3
		if rl != "":
			var line := {"id": "%s.reveal" % item.get("id"), "speaker": "graham", "category": "hole_reveal",
				"text": rl, "speech": rl, "mood": session.director.graham_mood, "silent": false}
			var dur: float = session.speech_seconds(line)
			at(t, func(): session.emit_say(line, dur))
			t += dur + 0.3
		else:
			t = say_at(t, "graham", "hole_reveal", {"answer": answer}) + 0.3
	if str(reaction.get("category", "")) != "":
		t = say_at(t, "graham", reaction.category, reaction.ctx) + 0.3
	for extra in reaction.get("extra", []):
		t = say_at(t, "graham", extra.category, extra.ctx) + 0.3
	reveal_end = elapsed + maxf(reveal_min, t + 0.6)


func _category_of(label: String) -> String:
	var i := options.find(label)
	return str(option_cats[i]) if i >= 0 and i < option_cats.size() else ""


func _grossness() -> int:
	for t in item.get("content_tags", []):
		if str(t).begins_with("grossness_"):
			return int(str(t).substr(10))
	return 0


# ---------------------------------------------------------------------------
# Phone actions
# ---------------------------------------------------------------------------

func handle_action(player: PlayerState, msg: Dictionary) -> String:
	var t := str(msg.get("t"))
	if t != Protocol.C_LOCK and t != Protocol.C_PASS:
		return Protocol.E_INVALID_STATE
	if str(msg.get("q", "")) != qid:
		return Protocol.E_STALE
	if not participants.has(player.player_id):
		return Protocol.E_NOT_PARTICIPANT
	if sub != "stage":
		return Protocol.E_INVALID_STATE
	if locks.has(player.player_id):
		return Protocol.E_ALREADY_ANSWERED   # once locked, it is locked
	var s = Protocol.get_int(msg, "s")
	if s == null:
		return Protocol.E_BAD_PAYLOAD
	var eff := int(s)
	if eff != stage:
		# A tap that left the phone just before the reveal advanced counts at the stage the
		# contestant was looking at, within a short server-side grace window.
		if eff == stage - 1 and (elapsed - stage_started) <= lock_grace * session.time_scale and t == Protocol.C_LOCK:
			pass
		else:
			return Protocol.E_STALE
	if t == Protocol.C_PASS:
		if eff >= final_stage:
			return Protocol.E_INVALID_STATE
		passes[player.player_id] = maxi(int(passes.get(player.player_id, 0)), eff)
		session.emit_tv({"e": "hole_pass", "pid": player.player_id})
		return ""
	var c = Protocol.get_int(msg, "c")
	var labels := labels_for_stage(eff)
	if c == null or int(c) < 0 or int(c) >= labels.size():
		return Protocol.E_BAD_PAYLOAD
	locks[player.player_id] = {"label": str(labels[int(c)]), "stage": eff, "t": elapsed}
	session.emit_tv({"e": "hole_lock", "pid": player.player_id, "stage": eff, "locked": locks.size(), "of": participants.size()})
	if eff == 1 and not _early_lock_called and session.director.rng.randf() < 0.55:
		_early_lock_called = true
		say_at(elapsed + 0.3, "graham", "hole_early_lock", {"pid": player.player_id})
	return ""


func screen_for(player: PlayerState) -> Dictionary:
	if not participants.has(player.player_id):
		return {"screen": "watch", "data": {"caption": "YOU WILL JOIN AT THE NEXT SEGMENT"}}
	var pid := player.player_id
	var head := "HOLE %d OF %d" % [round_no, round_count]
	match sub:
		"intro":
			var cap := "WHAT IS THIS HOLE?"
			if variant == "scale":
				cap = "HOW BIG IS THIS HOLE?"
			return {"screen": "get_ready", "data": {"caption": cap, "header": head}}
		"stage":
			if locks.has(pid):
				return {"screen": "hole_locked", "data": _locked_data(pid, head)}
			if int(passes.get(pid, 0)) >= stage:
				return {"screen": "hole_waiting", "data": {"header": head, "caption": "WAITING FOR A BETTER LOOK", "stage": stage}}
			var remaining: float = maxf(0.0, stage_started + float(stage_lengths[stage]) - elapsed) / maxf(session.time_scale, 0.001)
			return {"screen": "hole_pick", "data": {
				"qid": qid, "stage": stage, "final_stage": final_stage, "safety_net": stage >= 4,
				"options": labels_for_stage(stage), "points": stage_points(stage),
				"next_points": stage_points(stage + 1) if stage < final_stage else 0,
				"can_pass": stage < final_stage, "header": head, "variant": variant,
				"prompt": "HOW BIG IS THIS HOLE?" if variant == "scale" else "WHAT IS THIS HOLE?",
				"remaining_ms": int(remaining * 1000.0), "total_ms": int(float(stage_lengths[stage]) / maxf(session.time_scale, 0.001) * 1000.0)}}
		"closing":
			if locks.has(pid):
				return {"screen": "hole_locked", "data": _locked_data(pid, head)}
			return {"screen": "locked", "data": {"qid": qid, "choice": -1, "text": ""}}
		_:
			var o: Dictionary = outcome.get(pid, {})
			return {"screen": "hole_result", "data": {"answer": answer, "label": o.get("label", ""), "stage": o.get("stage", 0),
				"correct": o.get("correct", false), "partial": o.get("partial", false), "points": int(o.get("points", 0)),
				"score": player.score, "header": head}}
	return {"screen": "watch", "data": {}}


func _locked_data(pid: String, head: String) -> Dictionary:
	var lk: Dictionary = locks[pid]
	return {"qid": qid, "label": lk.label, "stage": lk.stage, "points": stage_points(int(lk.stage)), "header": head}


func tv_state() -> Dictionary:
	return {"kind": kind, "sub": sub, "qid": qid, "stage": stage, "variant": variant, "locked": locks.size(),
		"of": participants.size(), "item": item.get("id"), "round": round_no}
