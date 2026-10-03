extends SceneTree
## Large accelerated soak for the CP8 gate: N full Director-generated programmes with 2-8 bots,
## random drops/returns/late joiners. Prints outcome counts, games seen, incidents, programme lengths.
##   godot --headless --path . -s res://tests/tools/soak.gd -- 300
func _initialize() -> void:
	var n := int(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else 100
	var cfg := MildewConfig.load_default()
	var content := ContentDB.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4545
	var out := {"ended": 0, "closed": 0, "hung": 0}
	var games := {}
	var furniture := {}
	var lengths: Array = []
	var incidents := {0: 0, 1: 0, 2: 0, 3: 0}
	var t0 := Time.get_ticks_msec()
	for s in n:
		var store := SaveStore.new("user://soak_tool/%d_%d" % [t0, s])
		store.load_all()
		store.installation.broadcasts_played = rng.randi_range(0, 30)
		var h := SimHarness.new(cfg, store, content, 7000 + s, 20.0)
		var players := rng.randi_range(2, 8)
		var bots: Array = []
		for i in players:
			bots.append(h.add_bot("B%d" % i, FakePlayerBot.PERSONALITIES[rng.randi_range(0, FakePlayerBot.PERSONALITIES.size() - 1)], s * 31 + i))
		bots[0].auto_start_at_count = players
		var t := 0.0
		var held := 0.0
		while t < 400.0:
			h.step()
			t += h.dt
			if h.session.phase in [SessionServer.Phase.ENDED, SessionServer.Phase.CLOSED]:
				break
			if h.session.phase == SessionServer.Phase.SHOW and rng.randf() < 0.003:
				var b: FakePlayerBot = bots[rng.randi_range(0, bots.size() - 1)]
				if b.connected:
					h.disconnect_bot(b)
				elif rng.randf() < 0.7:
					h.connect_bot(b)
			held = held + h.dt if h.session.hold_reason == "players" else 0.0
			if held > 5.0:
				held = 0.0
				bots.append(h.add_bot("A%d" % bots.size(), "fast_random", s * 89 + bots.size()))
		match h.session.phase:
			SessionServer.Phase.ENDED:
				out.ended += 1
				lengths.append(h.session.session_time / 60.0)
			SessionServer.Phase.CLOSED:
				out.closed += 1
			_:
				out.hung += 1
				print("HUNG session %d: seg=%s hold=%s" % [s, h.session.diagnostics().segment, h.session.hold_reason])
		for g in h.session.director.games_this_show:
			games[g] = int(games.get(g, 0)) + 1
		for e in h.tv_events:
			if e.e == "incident":
				incidents[int(e.tier)] = int(incidents.get(int(e.tier), 0)) + 1
			elif e.e in ["advert_show", "poll_show", "special_test", "special_punish", "award"]:
				furniture[e.e] = int(furniture.get(e.e, 0)) + 1
		h.tv_events.clear()
	lengths.sort()
	print("SOAK sessions=%d outcomes=%s wall=%.0fs" % [n, out, (Time.get_ticks_msec() - t0) / 1000.0])
	print("SOAK median programme %.1f min (min %.1f, max %.1f)" % [lengths[lengths.size() / 2] if not lengths.is_empty() else 0.0, lengths.min() if not lengths.is_empty() else 0.0, lengths.max() if not lengths.is_empty() else 0.0])
	print("SOAK games %s" % games)
	print("SOAK furniture %s" % furniture)
	print("SOAK incidents by tier %s" % incidents)
	quit(1 if out.hung > 0 else 0)
