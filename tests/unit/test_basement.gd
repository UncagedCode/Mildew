extends MildewTest
## The Basement (CP7): every case deals validly for 2–8 players (no missing evidence/theory path),
## 2-player multi-clue hands, investigation budget, individual theories, partial credit, unresolved cases.

const SCALE := 12.0


func _harness(tag: String, seed: int = 7070, force := {}) -> SimHarness:
	var store := temp_store(tag)
	store.installation.broadcasts_played = 12
	var h := SimHarness.new(cfg(), store, content(), seed, SCALE)
	h.session.director.force = force
	h.session.director.force["playlist"] = ["basement"]
	return h


func _ended(h: SimHarness) -> Callable:
	return func(): return h.session.phase == SessionServer.Phase.ENDED or h.session.phase == SessionServer.Phase.CLOSED


func test_all_cases_deal_for_every_count() -> void:
	var cases := content().query("basement")
	check(cases.size() >= 6, "6–8 cases (%d)" % cases.size())
	check(cases.any(func(c): return bool(c.unresolved)), "partially unresolved cases exist")
	check(cases.any(func(c): return not bool(c.unresolved)), "definitive cases exist")
	check(cases.any(func(c): return c.evidence.any(func(e): return e.kind == "unreliable")), "unreliable clues supported")
	var tones := {}
	for c in cases:
		tones[c.tone] = true
	check(tones.size() >= 4, "tone variety (%s)" % str(tones.keys()))
	var rng := RandomNumberGenerator.new()
	var bad := 0
	for c in cases:
		for n in range(2, 9):
			for s in 30:
				rng.seed = hash("%s/%d/%d" % [c.id, n, s])
				var d := BasementCase.deal(c, n, rng)
				var errs := d.validate()
				if not errs.is_empty():
					bad += 1
					if bad <= 3:
						check(false, "%s n=%d: %s" % [c.id, n, errs])
				if n == 2:
					check(d.hands[0].size() >= 3 and d.hands[1].size() >= 3, "2 players each hold several clues")
	check_eq(bad, 0, "every deal valid")


func test_partial_credit_scoring() -> void:
	var c: Dictionary = content().get_item("bas.birthday_cake")
	var d := BasementCase.deal(c, 3, RandomNumberGenerator.new())
	check_eq(d.score({"who": 0, "how": 0, "why": 0}).fraction, 1.0, "best answers score fully")
	var part: float = d.score({"who": 0, "how": 3, "why": 1}).fraction
	check(part > 0.33 and part < 1.0, "partial credit (%.2f)" % part)
	check_eq(d.score({}).fraction, 0.0, "no theory, no points")


func test_full_case_with_bots() -> void:
	var h := _harness("bas_full")
	var bots: Array = []
	for i in 4:
		bots.append(h.add_bot("P%d" % i, ["high_accuracy", "cautious", "fast_random", "high_accuracy"][i], 300 + i))
	bots[0].auto_start_at_count = 4
	check(h.run_until(_ended(h), 900.0), "show with The Basement completes")
	var rev := h.events_of("bas_reveal")
	check(rev.size() >= 1, "case revealed")
	var r: Dictionary = rev[0]
	check((r.theories as Dictionary).size() >= 3, "individual theories filed")
	check(r.has("agreed") and r.has("best"), "group agreement + best-supported answer shown")
	check((r.deltas as Dictionary).values().any(func(v): return int(v) > 0), "accurate theories score")
	var inv := h.events_of("bas_investigated")
	check(inv.size() <= 2, "investigation budget respected (%d)" % inv.size())


func test_investigation_rules_and_private_findings() -> void:
	var h := _harness("bas_inv", 7071)
	var a := h.add_bot("Aaron", "afk", 1)
	var b := h.add_bot("Grace", "afk", 2)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return a.last_screen.get("screen") == "bas_evidence" and a.last_screen.data.live, 600.0), "evidence screen live")
	var q: String = a.last_screen.data.qid
	h.send_raw(a, JSON.stringify({"t": "investigate", "q": q, "i": 0}))
	h.run_until(func(): return false, 0.3)
	check(not (a.last_screen.data.finding as Dictionary).is_empty(), "investigator gets a private finding")
	check((b.last_screen.data.finding as Dictionary).is_empty(), "the other player doesn't see it")
	h.send_raw(a, JSON.stringify({"t": "investigate", "q": q, "i": 1}))
	h.send_raw(b, JSON.stringify({"t": "investigate", "q": q, "i": 0}))
	h.run_until(func(): return false, 0.3)
	check(a.errors_received.has(Protocol.E_ALREADY_ANSWERED), "one investigation each")
	check(b.errors_received.has(Protocol.E_STALE), "an investigation can only be used once")
	for x in [a, b]:
		h.send_raw(x, JSON.stringify({"t": "ready", "q": q}))
	check(h.run_until(func(): return a.last_screen.get("screen") == "bas_theory", 30.0), "everyone ready ends discussion early")
	h.send_raw(a, JSON.stringify({"t": "theory", "q": q, "a": {"zzz": 9}}))
	h.run_until(func(): return false, 0.3)
	check(a.errors_received.has(Protocol.E_BAD_PAYLOAD), "malformed theory refused")
