extends MildewTest
## DO NOT PRESS THAT (CP6): automated role-allocation validation for every template × 2–8 players ×
## many seeds; mistakes have partial consequences; latency-tolerant actions; tiers; punishment hook;
## timer irregularity is TV-only; reconnect returns the live panel.

const SCALE := 12.0


func _harness(tag: String, seed: int = 6060, force := {}) -> SimHarness:
	var store := temp_store(tag)
	store.installation.broadcasts_played = 6
	var h := SimHarness.new(cfg(), store, content(), seed, SCALE)
	h.session.director.force = force
	h.session.director.force["playlist"] = ["do_not_press_that"]
	return h


func _ended(h: SimHarness) -> Callable:
	return func(): return h.session.phase == SessionServer.Phase.ENDED or h.session.phase == SessionServer.Phase.CLOSED


func test_every_layout_is_satisfiable() -> void:
	var tpls := content().query("do_not_press_that")
	check(tpls.size() >= 8, "8–12 puzzle templates (%d)" % tpls.size())
	var rng := RandomNumberGenerator.new()
	var bad := 0
	var checked := 0
	for tpl in tpls:
		for n in range(2, 9):
			for seed in 40:
				rng.seed = hash("%s/%d/%d" % [tpl.id, n, seed])
				var p := DnpPuzzle.generate(tpl, n, rng, (seed % (n + 1)) - 1)
				var errs := p.validate()
				checked += 1
				if not errs.is_empty():
					bad += 1
					if bad <= 5:
						check(false, "%s n=%d seed=%d: %s" % [tpl.id, n, seed, errs])
	check_eq(bad, 0, "all %d generated layouts valid (nobody holds their own instruction, everyone has a job, solvable)" % checked)


func test_rules_and_consequences() -> void:
	var tpl: Dictionary = content().get_item("dnp.studio_power")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var p := DnpPuzzle.generate(tpl, 3, rng)
	var dec := p.act("x", 1)
	check_eq(dec.mistake, "decoy", "touching the decoy is a mistake")
	var nev: Array = p.controls.filter(func(c): return c.never)
	if not nev.is_empty():
		check_eq(p.act(nev[0].id, 1).mistake, "never", "switching on the NEVER control is a mistake")
	if p.order.size() == 2:
		var b: Dictionary = p._ctl(p.order[1])
		check_eq(p.act(b.id, 1 - int(b.value)).mistake, "order", "touching B before A is right is a mistake")
	var t2: Dictionary = content().get_item("dnp.autocue")
	var q := DnpPuzzle.generate(t2, 2, rng)
	var btn: Dictionary = q.controls.filter(func(c): return c.type == "button" and not c.decoy)[0]
	q.act(btn.id, 0, 1)
	var dup := q.act(btn.id, 0, 1)
	check(bool(dup.get("dup", false)), "a re-sent press is ignored (latency tolerance)")
	check_eq(int(btn.value), 1, "one press counted once")
	for k in range(2, int(btn.target) + 2):
		q.act(btn.id, 0, k)
	check_eq(int(btn.value), 0, "over-pressing resets the counter (recovery step)")


func test_full_game_bots_and_tiers() -> void:
	var h := _harness("dnp_full")
	var bots: Array = []
	for i in 4:
		bots.append(h.add_bot("P%d" % i, "fast_random", 100 + i))
	bots[0].auto_start_at_count = 4
	check(h.run_until(_ended(h), 900.0), "show with Do Not Press That completes")
	var res := h.events_of("dnp_result")
	check(res.size() >= 4, "a game of 4+ puzzles (%d)" % res.size())
	for r in res:
		check(DnpBoard.TIER_TEXT.has(r.tier), "tier %s" % r.tier)
	check(res.any(func(r): return r.tier != "failed"), "bots can solve puzzles by following instructions")
	for b in bots:
		check(not b.errors_received.has(Protocol.E_BAD_PAYLOAD), "bots only touch their own controls")


func test_mistake_jams_and_names_culprit() -> void:
	var h := _harness("dnp_mistake", 6061)
	var a := h.add_bot("Aaron", "afk", 1)
	var b := h.add_bot("Grace", "afk", 2)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return a.last_screen.get("screen") == "dnp_panel" and a.last_screen.data.live and b.last_screen.data.get("live", false), 600.0), "live panels")
	var seg := h.session._current as SegDnp
	var owner_bot: FakePlayerBot = a if seg.puzzle._ctl("x").owner == seg.order.find(a.player_id) else b
	var q: String = owner_bot.last_screen.data.qid
	var t0 := seg.phase_end
	h.send_raw(owner_bot, JSON.stringify({"t": "ctl", "q": q, "c": "x", "v": 1}))
	h.run_until(func(): return false, 0.2)
	check(h.events_of("dnp_mistake").size() == 1, "decoy press registered as a mistake")
	check(seg.phase_end < t0, "a mistake costs time")
	h.send_raw(owner_bot, JSON.stringify({"t": "ctl", "q": q, "c": "x", "v": 1}))
	h.run_until(func(): return false, 0.2)
	check(owner_bot.errors_received.has(Protocol.E_JAMMED), "the control jams for a few seconds")
	check(h.run_until(func(): return h.events_of("say").any(func(e): return e.category in ["dnp_decoy", "dnp_mistake"]), 30.0), "Graham names the culprit")
	var other: FakePlayerBot = b if owner_bot == a else a
	var foreign: Dictionary = seg.puzzle.controls.filter(func(c): return int(c.owner) == seg.order.find(owner_bot.player_id) and not c.decoy)[0]
	h.send_raw(other, JSON.stringify({"t": "ctl", "q": q, "c": foreign.id, "v": 1}))
	h.run_until(func(): return false, 0.2)
	check(other.errors_received.has(Protocol.E_BAD_PAYLOAD), "you can't operate somebody else's control")
	# reconnect returns the live panel with current values
	h.disconnect_bot(other)
	h.run_until(func(): return false, 1.0)
	h.connect_bot(other)
	check(h.run_until(func(): return other.last_screen.get("screen") == "dnp_panel", 30.0), "reconnected phone gets its panel back")
	check(h.run_until(_ended(h), 900.0), "show completes after a failed/odd puzzle")
	check(h.session.director.decision_log.any(func(d): return str(d).contains("DnpMistake")), "mistakes logged")


func test_timer_irregularity_is_tv_only() -> void:
	var h := _harness("dnp_timer", 6062, {"dnp_timer_lie": true})
	var a := h.add_bot("Aaron", "afk", 1)
	h.add_bot("Grace", "afk", 2)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return not h.events_of("dnp_open").is_empty(), 600.0), "puzzle opened")
	var ev: Dictionary = h.events_of("dnp_open")[0]
	check(float(ev.tv_offset) > 0.0, "TV clock runs early")
	check(h.run_until(func(): return a.last_screen.get("screen") == "dnp_panel" and a.last_screen.data.live, 10.0), "panel live")
	var real_ms := int(a.last_screen.data.remaining_ms)
	check(real_ms > int(float(ev.tv_offset) / SCALE * 1000.0), "phone shows the real remaining time (%d ms)" % real_ms)
