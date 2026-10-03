class_name SegSketch
extends Segment
## POLICE SKETCH (CP5; docs/04 §5). Drawing/interpretation chains, server-authoritative.
## Every player starts a chain from their own prompt; all chains advance together, so each step
## every player is drawing or describing *somebody else's* chain:
##   step 0 draw the prompt -> step 1 describe that drawing -> step 2 draw that description -> ...
## Chain length: 2 for 2–3 players (the explicit 2-player flow: A draws, B interprets, and the
## other way round with a new prompt), 4 for 4+ players.
## Then the mutation chains are revealed, players vote in two categories (FUNNIEST MUTATION,
## BEST DRAWING — never their own), and chain fidelity is scored by local word overlap with the
## original prompt (the original artist scores when the chain reconstructs it).
## Drawings travel as compact stroke lists (bounded; see validate_strokes) only to the phone that
## needs them and to the TV — never broadcast to every phone.

const MAX_STROKES := 300
const MAX_POINTS := 6000        # total coordinate pairs per drawing
const MAX_TEXT := 70
const STOP := ["a", "an", "the", "of", "in", "on", "at", "to", "with", "and", "its", "it", "is", "that", "has", "who", "what", "your",
	"someone", "something", "some", "by", "for", "from", "just", "very", "clearly", "like", "this", "out"]

var items: Array = []
var game_id := "police_sketch"
var title := "POLICE SKETCH"
var multiplier := 1.0
var qid := ""
var sub := "intro"              # intro | step | reveal | vote | results
var order: Array = []           # pids, chain c belongs to order[c]
var chains: Array = []          # [{owner, item_id, prompt, variant, steps: [{kind, pid, strokes, text, missing}]}]
var steps_total := 2
var step := 0
var submitted := {}             # pid -> true for the current step / vote
var votes := {}                 # category -> {pid: option}
var categories := ["funniest", "drawing"]
var cat_i := 0
var vote_options := {}          # category -> [{label, chain, step_i, pid}]
var deltas := {}
var phase_end := 0.0
var draw_s := 50.0
var describe_s := 30.0
var vote_s := 20.0
var exhibit: Dictionary = {}


func _init(desc: Dictionary) -> void:
	kind = "sketch"
	items = desc.get("items", [])
	multiplier = float(desc.get("multiplier", 1.0))
	allows_late_join_after = false


func start() -> void:
	session.question_counter += 1
	qid = "ps#%d" % session.question_counter
	order = session.active_player_ids()
	session.director.shuffle(order)
	var n := order.size()
	steps_total = 2 if n < 4 else mini(4, session.cfg.i("police_sketch.max_chain_steps", 4))
	draw_s = session.cfg.f("police_sketch.draw_seconds", 50.0)
	describe_s = session.cfg.f("police_sketch.describe_seconds", 30.0)
	vote_s = session.cfg.f("police_sketch.vote_seconds", 20.0)
	duration = 1.0e9
	for c in n:
		var it: Dictionary = items[c % maxi(1, items.size())] if not items.is_empty() else {"id": "ps.none", "prompt": "A suspicious pigeon"}
		session.director.used_content[str(it.get("id", ""))] = true
		chains.append({"owner": order[c], "item_id": str(it.get("id", "")), "prompt": str(it.get("prompt", "")),
			"variant": str(it.get("variant", "standard")), "steps": []})
	# Local historical drawing reuse (docs/04 §5 "Persistent reuse"): rarely, an old exhibit.
	var arch: Array = session.store.installation.get("sketch_archive", [])
	if not arch.is_empty() and (session.director.force.get("ps_exhibit", false) or session.director.rng.randf() < session.cfg.f("police_sketch.exhibit_chance", 0.25)):
		session.director.force.erase("ps_exhibit")
		exhibit = arch[session.director.rng.randi_range(0, arch.size() - 1)]
		session.director.log_decision("SketchExhibit", str(exhibit.get("prompt", "")), ["local archive size=%d" % arch.size()])
	session.emit_tv({"e": "ps_show", "qid": qid, "game_id": game_id, "title": title, "chains": n, "steps": steps_total,
		"order": order, "exhibit": exhibit.get("strokes", []) if not exhibit.is_empty() else []})
	var t := 0.4
	if not exhibit.is_empty():
		t = say_at(t, "graham", "ps_exhibit") + 0.4
	at(t + 0.2, func(): _open_step(0))
	session.push_screens()


func _chain_for(pid: String, s: int) -> int:
	## Player order[i] works on chain (i - s) mod n at step s.
	var n := order.size()
	var i := order.find(pid)
	if i < 0:
		return -1
	return posmod(i - s, n)


func _pid_for(c: int, s: int) -> String:
	return str(order[(c + s) % order.size()])


func step_kind(s: int) -> String:
	return "draw" if s % 2 == 0 else "describe"


func _open_step(s: int) -> void:
	step = s
	sub = "step"
	submitted = {}
	var win := draw_s if step_kind(s) == "draw" else describe_s
	phase_end = elapsed + win
	for c in chains.size():
		chains[c].steps.append({"kind": step_kind(s), "pid": _pid_for(c, s), "strokes": [], "text": "", "missing": true})
	session.emit_tv({"e": "ps_step", "qid": qid, "step": s, "of_steps": steps_total, "kind": step_kind(s), "window": win, "of": _present().size()})
	if s == 0:
		say_at(0.1, "graham", "ps_draw_open")
	elif s == 1:
		say_at(0.1, "graham", "ps_describe_open")
	session.push_screens()


func _present() -> Array:
	return order.filter(func(pid): return session.players.has(pid) and session.players[pid].is_active())


func _all_in() -> bool:
	for pid in _present():
		if not submitted.has(pid):
			return false
	return true


func update(dt: float) -> void:
	elapsed += dt
	while not _timeline.is_empty() and _timeline[0].at <= elapsed:
		_timeline.pop_front().fn.call()
	match sub:
		"step":
			if elapsed >= phase_end or _all_in():
				if step + 1 < steps_total:
					_open_step(step + 1)
				else:
					_start_reveal()
		"vote":
			if elapsed >= phase_end or _all_in():
				cat_i += 1
				if cat_i < categories.size():
					_open_vote()
				else:
					_results()
		"reveal", "results":
			if elapsed >= phase_end and _timeline.is_empty():
				if sub == "reveal":
					cat_i = 0
					_open_vote()
				else:
					done = true


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## Bounds a phone drawing: <=300 strokes, <=6000 points, coordinates 0..1000, widths 1..3.
## Returns the cleaned stroke list or null when malformed.
static func validate_strokes(raw) -> Variant:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() > MAX_STROKES:
		return null
	var out: Array = []
	var total := 0
	for s in raw:
		if typeof(s) != TYPE_DICTIONARY:
			return null
		var p = s.get("p")
		if typeof(p) != TYPE_ARRAY or (p as Array).size() % 2 != 0 or (p as Array).size() < 2:
			return null
		total += (p as Array).size() / 2
		if total > MAX_POINTS:
			return null
		var pts := PackedInt32Array()
		for v in p:
			if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
				return null
			pts.append(clampi(int(v), 0, 1000))
		var w := clampi(int(s.get("w", 1)), 1, 3)
		out.append({"w": w, "e": bool(s.get("e", false)), "p": Array(pts)})
	return out


func handle_action(player: PlayerState, msg: Dictionary) -> String:
	var t := str(msg.get("t"))
	var pid := player.player_id
	if not order.has(pid):
		return Protocol.E_NOT_PARTICIPANT
	if t == Protocol.C_VOTE:
		if sub != "vote" or str(msg.get("q", "")) != _vote_qid():
			return Protocol.E_STALE if sub != "vote" else Protocol.E_STALE
		if submitted.has(pid):
			return Protocol.E_ALREADY_ANSWERED
		var c = Protocol.get_int(msg, "c")
		var opts: Array = vote_options.get(categories[cat_i], [])
		if c == null or int(c) < 0 or int(c) >= opts.size():
			return Protocol.E_BAD_PAYLOAD
		if _own_option(opts[int(c)], pid):
			return Protocol.E_SELF_VOTE
		submitted[pid] = true
		votes[categories[cat_i]][pid] = int(c)
		session.emit_tv({"e": "ps_vote_progress", "qid": qid, "pid": pid, "count": submitted.size(), "of": _present().size()})
		return ""
	if sub != "step" or str(msg.get("q", "")) != _step_qid():
		return Protocol.E_STALE
	if submitted.has(pid):
		return Protocol.E_ALREADY_ANSWERED
	var c := _chain_for(pid, step)
	var entry: Dictionary = chains[c].steps[step]
	match t:
		Protocol.C_DRAW:
			if step_kind(step) != "draw":
				return Protocol.E_INVALID_STATE
			var strokes = validate_strokes(msg.get("strokes"))
			if strokes == null:
				return Protocol.E_BAD_PAYLOAD
			entry.strokes = strokes
			entry.missing = (strokes as Array).is_empty()
		Protocol.C_SUBMIT:
			if step_kind(step) != "describe":
				return Protocol.E_INVALID_STATE
			var raw = Protocol.get_str(msg, "text", 400)
			if raw == null:
				return Protocol.E_BAD_PAYLOAD
			var text := SegWriteVote.clean_text(str(raw), MAX_TEXT)
			if text == "":
				return Protocol.E_BAD_PAYLOAD
			entry.text = text
			entry.missing = false
		_:
			return Protocol.E_INVALID_STATE
	submitted[pid] = true
	session.emit_tv({"e": "ps_progress", "qid": qid, "pid": pid, "count": submitted.size(), "of": _present().size()})
	return ""


func _step_qid() -> String:
	return "%s/%d" % [qid, step]


func _vote_qid() -> String:
	return "%s/v%d" % [qid, cat_i]


func _own_option(opt: Dictionary, pid: String) -> bool:
	if str(opt.get("pid", "")) == pid:
		return true
	return false


## What the player at step s of chain c is working from: the prompt, a drawing or a description.
func _source(c: int, s: int) -> Dictionary:
	if s == 0:
		return {"text": chains[c].prompt}
	# walk back to the most recent non-missing entry of the needed kind
	var need := "draw" if step_kind(s) == "describe" else "describe"
	for k in range(s - 1, -1, -1):
		var e: Dictionary = chains[c].steps[k]
		if e.kind == need and not e.missing:
			return {"strokes": e.strokes} if need == "draw" else {"text": e.text}
	if need == "describe":
		return {"text": chains[c].prompt}   # nobody described it: the witness statement stands
	return {"strokes": [], "missing": true}


# ---------------------------------------------------------------------------
# Reveal, votes, scoring
# ---------------------------------------------------------------------------

static func words(text: String) -> Array:
	var out: Array = []
	for w in SegWriteVote.match_key(text).split(" ", false):
		if not STOP.has(w) and w.length() > 1 and not out.has(w):
			out.append(w)
	return out


## Fraction of the original prompt's content words recovered by a guess (0..1).
static func fidelity(prompt: String, guess: String) -> float:
	var pw := words(prompt)
	if pw.is_empty():
		return 0.0
	var gw := words(guess)
	var hit := 0
	for w in pw:
		if gw.has(w):
			hit += 1
	return float(hit) / pw.size()


func _start_reveal() -> void:
	sub = "reveal"
	deltas.clear()
	for pid in order:
		deltas[pid] = 0
	var per_word: float = session.cfg.f("police_sketch.describe_points", 400.0)
	var t := say_at(0.3, "graham", "ps_reveal_intro") + 0.3
	for c in chains.size():
		var ch: Dictionary = chains[c]
		var last_text := ""
		for e in ch.steps:
			if e.kind == "describe" and not e.missing:
				var f := fidelity(ch.prompt, e.text)
				e["fidelity"] = snappedf(f, 0.01)
				_award(str(e.pid), int(round(per_word * f * multiplier / 10.0)) * 10)
				last_text = e.text
		var fin := fidelity(ch.prompt, last_text) if last_text != "" else 0.0
		ch["fidelity"] = snappedf(fin, 0.01)
		if fin >= session.cfg.f("police_sketch.reconstructed_threshold", 0.5):
			_award(str(ch.owner), int(session.cfg.f("police_sketch.reconstructed_bonus", 500.0) * multiplier))
			ch["reconstructed"] = true
		var cc := c
		at(t, func(): session.emit_tv({"e": "ps_reveal_chain", "qid": qid, "index": cc, "of": chains.size(), "chain": _public_chain(cc)}))
		var dur: float = 2.2 + ch.steps.size() * session.cfg.f("police_sketch.reveal_seconds_per_step", 2.4)
		# Sparse commentary: Graham reacts to some chains, not all (docs/04 §5).
		var line := ""
		if bool(ch.get("reconstructed", false)):
			line = "ps_faithful"
		elif session.director.rng.randf() < 0.45:
			line = "ps_mutated" if session.director.rng.randf() < 0.5 else "ps_comment"
		if line != "":
			var artist := _first_artist(c)
			t = maxf(t + dur, say_at(t + dur * 0.55, "graham", line, {"pid": artist}) + 0.3)
		else:
			t += dur
	phase_end = elapsed + t + 0.5
	session.push_screens()


func _first_artist(c: int) -> String:
	for e in chains[c].steps:
		if e.kind == "draw" and not e.missing:
			return str(e.pid)
	return str(chains[c].owner)


func _public_chain(c: int) -> Dictionary:
	var ch: Dictionary = chains[c]
	return {"owner": ch.owner, "prompt": ch.prompt, "variant": ch.variant, "fidelity": ch.get("fidelity", 0.0),
		"reconstructed": ch.get("reconstructed", false),
		"steps": ch.steps.map(func(e): return {"kind": e.kind, "pid": e.pid, "strokes": e.strokes, "text": e.text, "missing": e.missing})}


func _open_vote() -> void:
	sub = "vote"
	submitted = {}
	var cat: String = categories[cat_i]
	var opts: Array = []
	if cat == "funniest":
		for c in chains.size():
			var last := ""
			for e in chains[c].steps:
				if e.kind == "describe" and not e.missing:
					last = e.text
			opts.append({"label": "CHAIN %d: “%s”" % [c + 1, last if last != "" else chains[c].prompt], "chain": c, "pid": chains[c].owner})
	else:
		for c in chains.size():
			for k in chains[c].steps.size():
				var e: Dictionary = chains[c].steps[k]
				if e.kind == "draw" and not e.missing and k == 0:
					var who: String = session.players[e.pid].display_name if session.players.has(e.pid) else "?"
					opts.append({"label": "%s'S DRAWING (CHAIN %d)" % [who.to_upper(), c + 1], "chain": c, "step_i": k, "pid": e.pid})
	vote_options[cat] = opts
	votes[cat] = {}
	if opts.size() < 2:
		phase_end = elapsed   # nothing meaningful to vote on
	else:
		phase_end = elapsed + vote_s
		session.emit_tv({"e": "ps_vote_open", "qid": qid, "category": cat, "options": opts.map(func(o): return {"label": o.label, "chain": o.chain, "step_i": o.get("step_i", -1)}),
			"window": vote_s, "of": _present().size()})
		say_at(0.1, "graham", "ps_vote_funny" if cat == "funniest" else "ps_vote_drawing")
	session.push_screens()


func _results() -> void:
	sub = "results"
	var winners := {}
	for cat in categories:
		var opts: Array = vote_options.get(cat, [])
		var tally := {}
		for pid in votes.get(cat, {}):
			var o := int(votes[cat][pid])
			tally[o] = int(tally.get(o, 0)) + 1
		var best := -1
		for o in tally:
			if best < 0 or tally[o] > tally[best]:
				best = o
			var opt: Dictionary = opts[o]
			if cat == "funniest":
				# every contributor to a funny chain shares in its votes
				var who := {}
				for e in chains[int(opt.chain)].steps:
					if not e.missing:
						who[str(e.pid)] = true
				for pid in who:
					_award(pid, int(session.cfg.f("police_sketch.funny_vote_points", 200.0) * multiplier) * int(tally[o]))
			else:
				_award(str(opt.pid), int(session.cfg.f("police_sketch.drawing_vote_points", 400.0) * multiplier) * int(tally[o]))
		winners[cat] = best
	# Graham's Choice: modest, sometimes his favourite, sometimes not.
	var gc := -1
	var dopts: Array = vote_options.get("drawing", [])
	if not dopts.is_empty():
		gc = session.director.rng.randi_range(0, dopts.size() - 1)
		_award(str(dopts[gc].pid), int(session.cfg.f("police_sketch.graham_choice_bonus", 250.0)))
	_archive_best(dopts, winners.get("drawing", -1))
	for pid in deltas:
		if session.players.has(pid):
			session.players[pid].history.append({"qid": qid, "content_id": "police_sketch", "points": deltas[pid], "kind": "sketch"})
	session.emit_tv({"e": "ps_results", "qid": qid, "funniest": winners.get("funniest", -1), "drawing": winners.get("drawing", -1),
		"graham_choice": gc, "options": {"funniest": vote_options.get("funniest", []).map(func(o): return o.label),
		"drawing": dopts.map(func(o): return {"label": o.label, "chain": o.chain, "step_i": o.get("step_i", 0)})},
		"deltas": deltas, "standings": session.standings()})
	var t := 0.6
	if gc >= 0:
		t = say_at(t, "graham", "ps_graham_choice", {"pid": str(dopts[gc].pid)}) + 0.3
	phase_end = elapsed + maxf(6.0, t + 1.0)
	session.push_screens()


## The most-voted drawing joins the local exhibit archive (local only, never attributed later).
func _archive_best(dopts: Array, best: int) -> void:
	if dopts.is_empty():
		return
	var o: Dictionary = dopts[best if best >= 0 else 0]
	var e: Dictionary = chains[int(o.chain)].steps[int(o.get("step_i", 0))]
	var arch: Array = session.store.installation.get("sketch_archive", [])
	arch.append({"strokes": e.strokes, "prompt": chains[int(o.chain)].prompt})
	while arch.size() > 12:
		arch.pop_front()
	session.store.installation.sketch_archive = arch


func _award(pid: String, pts: int) -> void:
	if pts <= 0 or not session.players.has(pid):
		return
	session.players[pid].score += pts
	deltas[pid] = int(deltas.get(pid, 0)) + pts


# ---------------------------------------------------------------------------
# Phone screens
# ---------------------------------------------------------------------------

func screen_for(player: PlayerState) -> Dictionary:
	var pid := player.player_id
	if not order.has(pid):
		return {"screen": "watch", "data": {"caption": "YOU WILL JOIN AT THE NEXT SEGMENT"}}
	var remaining := int(maxf(0.0, phase_end - elapsed) / maxf(session.time_scale, 0.001) * 1000.0)
	var head := title
	match sub:
		"intro":
			return {"screen": "get_ready", "data": {"caption": "FIND A PEN. YOU ARE A POLICE ARTIST NOW.", "header": head}}
		"step":
			var hdr := "%s · %d OF %d" % [head, step + 1, steps_total]
			if submitted.has(pid):
				return {"screen": "wv_wait", "data": {"header": hdr, "caption": "EVIDENCE SUBMITTED. WAITING FOR THE OTHERS."}}
			var c := _chain_for(pid, step)
			var src := _source(c, step)
			var total := int((draw_s if step_kind(step) == "draw" else describe_s) / maxf(session.time_scale, 0.001) * 1000.0)
			if step_kind(step) == "draw":
				var witness := "THE WITNESS SAYS:" if step == 0 else "THE LAST WITNESS SAID:"
				if step == 0 and chains[c].variant == "body_part":
					witness = "GRAHAM DESCRIBES:"
				return {"screen": "ps_draw", "data": {"qid": _step_qid(), "header": hdr, "witness": witness, "prompt": str(src.get("text", "")),
					"remaining_ms": remaining, "total_ms": total}}
			return {"screen": "ps_describe", "data": {"qid": _step_qid(), "header": hdr, "strokes": src.get("strokes", []), "missing": src.get("missing", false),
				"remaining_ms": remaining, "total_ms": total, "max": MAX_TEXT}}
		"reveal":
			return {"screen": "watch", "data": {"caption": "THE EVIDENCE IS ON YOUR TELEVISION"}}
		"vote":
			var cat: String = categories[cat_i]
			if submitted.has(pid):
				return {"screen": "wv_wait", "data": {"header": head, "caption": "VOTE RECEIVED."}}
			var opts: Array = vote_options.get(cat, [])
			var own: Array = []
			for i in opts.size():
				if _own_option(opts[i], pid):
					own.append(i)
			return {"screen": "ps_vote", "data": {"qid": _vote_qid(), "header": head, "ask": "FUNNIEST MUTATION" if cat == "funniest" else "BEST DRAWING",
				"options": opts.map(func(o): return o.label), "own": own, "remaining_ms": remaining}}
		_:
			return {"screen": "wv_result", "data": {"header": head, "points": int(deltas.get(pid, 0)), "score": player.score}}


func tv_state() -> Dictionary:
	return {"kind": kind, "sub": sub, "step": step, "submitted": submitted.size()}
