extends SceneTree
func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1998
	var kinds := FakePlayerBot.PERSONALITIES
	var target := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 1
	var found := 0
	for s in 300:
		var store := SaveStore.new("user://dbg_soak_%d_%d" % [s, Time.get_ticks_usec()])
		store.load_all()
		var h := SimHarness.new(MildewConfig.load_default(), store, ContentDB.load_default(), 1000 + s, 20.0)
		var n := rng.randi_range(2, 8)
		var bots: Array = []
		for i in n:
			bots.append(h.add_bot("Bot%d" % i, kinds[rng.randi_range(0, kinds.size() - 1)], s * 31 + i))
		bots[0].auto_start_at_count = n
		var t := 0.0
		while t < 120.0:
			h.step()
			t += h.dt
			if h.session.phase in [SessionServer.Phase.ENDED, SessionServer.Phase.CLOSED]:
				break
			if h.session.phase == SessionServer.Phase.SHOW and rng.randf() < 0.004:
				var b: FakePlayerBot = bots[rng.randi_range(0, bots.size() - 1)]
				if b.connected:
					h.disconnect_bot(b)
				elif rng.randf() < 0.7:
					h.connect_bot(b)
			if h.session.phase == SessionServer.Phase.SHOW and rng.randf() < 0.001 and bots.size() < 10:
				bots.append(h.add_bot("Late%d" % bots.size(), "fast_random", s * 97 + bots.size()))
		if h.session.phase == SessionServer.Phase.SHOW and found < 1:
			found += 1
			print('STUCK session ', s, ' hold=', h.session.hold_reason)
			for l in h.logs.slice(-25):
				print(l)
			for p in h.session.players.values():
				print(p.player_id, " ", p.display_name, " status=", p.status_name(), " connected=", p.connected, " lost_at=", p.lost_at, " conn=", p.conn_id)
	quit()
