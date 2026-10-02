extends MildewTest
## Randomised soak: many accelerated sessions with 2-8 bots, random drops/returns and late
## joiners. Every session must reach ENDED or a legitimate CLOSED (everyone left) — never hang.


func test_soak_sessions_never_deadlock() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1998
	var kinds := FakePlayerBot.PERSONALITIES
	var outcomes := {"ended": 0, "closed": 0}
	var sessions := 60
	for s in sessions:
		var h := SimHarness.new(cfg(), temp_store("soak%d" % s), content(), 1000 + s, 20.0)
		h.keep_events = false
		var n := rng.randi_range(2, 8)
		var bots: Array = []
		for i in n:
			var b := h.add_bot("Bot%d" % i, kinds[rng.randi_range(0, kinds.size() - 1)], s * 31 + i)
			bots.append(b)
		bots[0].auto_start_at_count = n
		var t := 0.0
		var done := false
		while t < 120.0:
			h.step()
			t += h.dt
			if h.session.phase in [SessionServer.Phase.ENDED, SessionServer.Phase.CLOSED]:
				done = true
				break
			if h.session.phase == SessionServer.Phase.SHOW and rng.randf() < 0.004:
				var b: FakePlayerBot = bots[rng.randi_range(0, bots.size() - 1)]
				if b.connected:
					h.disconnect_bot(b)
				elif rng.randf() < 0.7:
					h.connect_bot(b)
			if h.session.phase == SessionServer.Phase.SHOW and rng.randf() < 0.001 and bots.size() < 10:
				bots.append(h.add_bot("Late%d" % bots.size(), "fast_random", s * 97 + bots.size()))
		check(done, "session %d (%d players) finished; phase=%s hold=%s seg=%s" % [s, n, h.session.phase_name(), h.session.hold_reason, h.session.diagnostics().segment])
		if done:
			outcomes["ended" if h.session.phase == SessionServer.Phase.ENDED else "closed"] += 1
		for st in h.session.standings():
			check(int(st.score) >= 0, "no negative scores")
	print("      soak outcomes: ", outcomes)
	check(outcomes.ended > sessions / 2, "most soak sessions complete normally")
