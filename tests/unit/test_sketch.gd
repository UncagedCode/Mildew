extends MildewTest
## Police Sketch (CP5): chain assignment, explicit 2-player flow, 8-player chains, bounded strokes,
## no self-votes, fidelity scoring, local exhibit archive, reconnect restores the right screen.

const SCALE := 12.0


func _harness(tag: String, seed: int = 5150, force := {}) -> SimHarness:
	var store := temp_store(tag)
	store.installation.broadcasts_played = 3
	var h := SimHarness.new(cfg(), store, content(), seed, SCALE)
	h.session.director.force = force
	h.session.director.force["playlist"] = ["police_sketch"]
	return h


func _ended(h: SimHarness) -> Callable:
	return func(): return h.session.phase == SessionServer.Phase.ENDED or h.session.phase == SessionServer.Phase.CLOSED


func _sketch(h: SimHarness) -> SegSketch:
	return h.session._current as SegSketch


func test_content_and_stroke_bounds() -> void:
	var items := content().query("police_sketch")
	check(items.size() >= 30, "30+ prompts (%d)" % items.size())
	check(items.any(func(i): return i.variant == "body_part"), "Body Part variant scaffolding")
	var ok = SegSketch.validate_strokes([{"w": 2, "p": [0, 0, 500, 500, 1200, -5]}])
	check(ok != null and ok[0].p == [0, 0, 500, 500, 1000, 0], "coordinates clamped to 0..1000")
	check(SegSketch.validate_strokes([{"w": 2, "p": [1, 2, 3]}]) == null, "odd coordinate list rejected")
	check(SegSketch.validate_strokes("nope") == null, "non-array rejected")
	var big: Array = []
	for i in 301:
		big.append({"w": 1, "p": [1, 1]})
	check(SegSketch.validate_strokes(big) == null, "more than 300 strokes rejected")
	var pts: Array = []
	for i in 6001:
		pts.append_array([i % 1000, i % 1000])
	check(SegSketch.validate_strokes([{"w": 1, "p": pts}]) == null, "more than 6000 points rejected")
	check(SegSketch.fidelity("A suspicious-looking pigeon wearing something it clearly stole", "pigeon wearing a stolen hat") >= 0.3, "fidelity: partial reconstruction scores")
	check_eq(SegSketch.fidelity("A haunted microwave", "a haunted microwave"), 1.0, "fidelity: exact")
	check_eq(SegSketch.fidelity("A haunted microwave", "a sad horse"), 0.0, "fidelity: miss")


func test_chain_assignment_is_a_rotation() -> void:
	var s := SegSketch.new({"items": []})
	for n in [2, 3, 4, 5, 8]:
		s.order = range(n).map(func(i): return "p%d" % i)
		for step in 4:
			var seen := {}
			for pid in s.order:
				seen[s._chain_for(pid, step)] = true
				check_eq(s._pid_for(s._chain_for(pid, step), step), pid, "inverse mapping (n=%d step=%d)" % [n, step])
			check_eq(seen.size(), n, "every chain has exactly one worker per step (n=%d)" % n)
		for c in n:
			var who := {}
			for step in mini(n, 4):
				who[s._pid_for(c, step)] = true
			check_eq(who.size(), mini(n, 4), "nobody works on the same chain twice (n=%d)" % n)


func test_two_player_flow_and_fidelity() -> void:
	var h := _harness("ps_two")
	var a := h.add_bot("Aaron", "afk", 1)
	var b := h.add_bot("Grace", "afk", 2)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return a.last_screen.get("screen") == "ps_draw", 600.0), "draw screen reached")
	var seg := _sketch(h)
	check_eq(seg.steps_total, 2, "2 players: draw then interpret")
	var line := [{"w": 2, "p": [100, 100, 900, 900]}]
	for bot in [a, b]:
		h.send_raw(bot, JSON.stringify({"t": "draw", "q": bot.last_screen.data.qid, "strokes": line}))
	check(h.run_until(func(): return a.last_screen.get("screen") == "ps_describe" and b.last_screen.get("screen") == "ps_describe", 60.0), "both swap to interpreting")
	check_eq((a.last_screen.data.strokes as Array).size(), 1, "the interpreter receives the other player's drawing")
	# Aaron reconstructs Grace's prompt exactly; Grace writes nonsense.
	var ca := seg._chain_for(a.player_id, 1)
	var prompt_a: String = seg.chains[ca].prompt
	h.send_raw(a, JSON.stringify({"t": "submit", "q": a.last_screen.data.qid, "text": prompt_a.substr(0, 60)}))
	h.send_raw(b, JSON.stringify({"t": "submit", "q": b.last_screen.data.qid, "text": "zzz qqq"}))
	check(h.run_until(func(): return not h.events_of("ps_reveal_chain").is_empty(), 60.0), "reveal started")
	check(int(seg.deltas[a.player_id]) > 0, "an accurate interpretation scores")
	check(bool(seg.chains[ca].get("reconstructed", false)), "chain marked reconstructed")
	check(int(seg.deltas[str(seg.chains[ca].owner)]) >= 500, "the original artist scores when the chain reconstructs the prompt")
	check(h.run_until(func(): return a.last_screen.get("screen") == "ps_vote", 120.0), "voting reached")
	var own: Array = a.last_screen.data.own
	check(own.size() == 1, "own case marked")
	h.send_raw(a, JSON.stringify({"t": "vote", "q": a.last_screen.data.qid, "c": own[0]}))
	h.run_until(func(): return false, 0.5)
	check(a.errors_received.has(Protocol.E_SELF_VOTE), "self-vote refused")
	check(h.run_until(_ended(h), 900.0), "show completes")
	check(h.events_of("ps_show").size() == 2, "2 players get two rounds (roles swap with new prompts)")
	check(not (h.session.store.installation.get("sketch_archive", []) as Array).is_empty(), "a drawing joins the local exhibit archive")


func test_eight_player_chains() -> void:
	var h := _harness("ps_eight", 5151)
	var bots: Array = []
	for i in 8:
		bots.append(h.add_bot("P%d" % i, ["fast_random", "high_accuracy", "cautious", "terrible"][i % 4], i + 1))
	bots[0].auto_start_at_count = 8
	check(h.run_until(_ended(h), 1200.0), "8-player show with Police Sketch completes")
	var chains := h.events_of("ps_reveal_chain")
	check_eq(chains.size(), 8, "eight chains revealed")
	for e in chains:
		check_eq((e.chain.steps as Array).size(), 4, "4+ players: four-step chains (draw/describe/draw/describe)")
		var kinds: Array = e.chain.steps.map(func(s): return s.kind)
		check_eq(kinds, ["draw", "describe", "draw", "describe"], "alternating chain")
	check(h.events_of("ps_vote_open").size() == 2, "two voting categories")
	var res: Dictionary = h.events_of("ps_results")[0]
	var total := 0
	for pid in res.deltas:
		total += int(res.deltas[pid])
	check(total > 0, "votes and fidelity produced points")
	for b in bots:
		check(not b.errors_received.has(Protocol.E_SELF_VOTE), "bots never self-vote")
		check(not b.errors_received.has(Protocol.E_BAD_PAYLOAD), "bot drawings validate")


func test_frame_limits() -> void:
	var h := _harness("ps_frames", 5152)
	var a := h.add_bot("Aaron", "afk", 1)
	h.add_bot("Grace", "afk", 2)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return a.last_screen.get("screen") == "ps_draw", 600.0), "draw screen reached")
	var long_text := "x".repeat(6000)
	h.send_raw(a, JSON.stringify({"t": "submit", "q": "nope", "text": long_text}))
	h.run_until(func(): return false, 0.3)
	check(a.errors_received.has(Protocol.E_TOO_LARGE), "non-drawing frames keep the small size limit")
	var pts: Array = []
	for i in 2500:
		pts.append_array([i % 1000, (i * 7) % 1000])
	var msg := JSON.stringify({"t": "draw", "q": a.last_screen.data.qid, "strokes": [{"w": 1, "p": pts}]})
	check(msg.length() > 4096 and msg.length() < 49152, "a busy drawing is between the limits (%d bytes)" % msg.length())
	var before := a.errors_received.size()
	h.send_raw(a, msg)
	h.run_until(func(): return false, 0.3)
	check_eq(a.errors_received.size(), before, "drawing frame accepted")
	check(_sketch(h).submitted.has(a.player_id), "drawing stored")


func test_reconnect_gets_its_task_back() -> void:
	var h := _harness("ps_rc", 5153)
	var a := h.add_bot("Aaron", "afk", 1)
	h.add_bot("Grace", "afk", 2)
	h.add_bot("Josh", "afk", 3)
	a.auto_start_at_count = 3
	check(h.run_until(func(): return a.last_screen.get("screen") == "ps_draw", 600.0), "draw screen reached")
	var q: String = a.last_screen.data.qid
	var prompt: String = a.last_screen.data.prompt
	h.disconnect_bot(a)
	h.run_until(func(): return false, 1.0)
	h.connect_bot(a)
	check(h.run_until(func(): return a.last_screen.get("screen") == "ps_draw", 30.0), "draw screen restored after reconnect")
	check_eq(a.last_screen.data.qid, q, "same step")
	check_eq(a.last_screen.data.prompt, prompt, "same prompt")
