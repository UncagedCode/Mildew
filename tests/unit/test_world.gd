extends MildewTest
## CP8 part 2: recurring rooms with persistent non-linear state, event chains (incl. Tier 4
## prerequisites), Tier 2/3 incidents (rare, never mid-game, comedic reset after), Announcer drift,
## punishment segment, THE TEST interruption game.

const SCALE := 12.0


func _director(seed: int, played := 15, mode := "standard_transmission") -> Director:
	var d := Director.new(content(), seed)
	d.cfg = cfg()
	d.begin_session({"broadcasts_played": played}, mode)
	d.reset_for_new_show()
	return d


func test_rooms_persist_and_drift() -> void:
	var d := _director(1)
	check(d.world.rooms.size() >= 4, "4-5 recurring rooms (%d)" % d.world.rooms.size())
	var changes := {}
	var reverts := 0
	for i in 60:
		var v := d.world.cctv(2)
		changes[str(v.changed).split("=")[0]] = true
		if str(v.changed).begins_with("revert"):
			reverts += 1
	check(changes.size() >= 3, "rooms change in several ways: %s" % str(changes.keys()))
	check(reverts > 0, "rooms also go back to normal (non-linear)")
	var inst := {}
	d.world.save_into(inst)
	var d2 := Director.new(content(), 2)
	d2.cfg = cfg()
	d2.begin_session(inst, "standard_transmission")
	check_eq(d2.world.state, d.world.state, "room states persist across sessions")
	check_eq(d2.world.rooms_seen, d.world.rooms_seen, "rooms seen persist")


func test_chains_and_tier4_prerequisites() -> void:
	var d := _director(3, 20)
	var steps := 0
	for i in 30:
		d.world.advanced_this_show = false
		if not d.world.maybe_advance({"returning_players": false, "installation_seed": 1}).is_empty():
			steps += 1
	check(steps > 0, "chains advance over broadcasts")
	check(not d.world.chain_steps.has("chain.legend_locked_room"), "Tier 4 never fires without its prerequisites")
	# satisfy prerequisites; dev-force one step
	d.announcer_stage = 2
	d.world.rooms_seen = ["room.tape_room", "room.corridor"]
	d.world.advanced_this_show = false
	d.force["chain_step"] = "chain.legend_locked_room"
	var s := d.world.maybe_advance({"returning_players": true, "installation_seed": 3})
	check_eq(str(s.get("chain", "")), "chain.legend_locked_room", "developer-testable Tier 4 step")
	check_eq(int(s.get("tier", 0)), 4, "tier 4")
	check(s.has("interfere"), "chain step can carry a private phone message")
	var once := d.world.maybe_advance({"returning_players": true, "installation_seed": 3})
	check(once.is_empty(), "at most one chain step per broadcast")
	var dc := _director(4, 20, "clean_transmission")
	var any := false
	for i in 30:
		dc.world.advanced_this_show = false
		if not dc.world.maybe_advance({}).is_empty():
			any = true
	check(not any, "CLEAN TRANSMISSION: chains never advance")


func test_tier2_3_rates_and_rules() -> void:
	var counts := {2: 0, 3: 0}
	var mid_hits := 0
	for seed in range(1, 61):
		var d := _director(seed, 15)
		var t := 0.0
		while t < 2700.0:
			t += 30.0
			d.show_time = t
			for k in d.tone.keys():
				d.tone[k] = maxf(0.0, float(d.tone[k]) - 0.05)
			var mid := int(t / 30.0) % 3 != 0
			var inc := d.incidents.opportunity("boundary", {"players": 4, "mid_game": mid})
			if not inc.is_empty() and int(inc.tier) >= 2:
				counts[int(inc.tier)] += 1
				if mid:
					mid_hits += 1
	print("      per 45 min: tier2=%.2f tier3=%.2f" % [counts[2] / 60.0, counts[3] / 60.0])
	check(counts[2] > 0 and counts[2] / 60.0 < 1.5, "Tier 2 uncommon (%.2f per show)" % (counts[2] / 60.0))
	check(counts[3] / 60.0 < 0.5, "Tier 3 rare (%.2f per show)" % (counts[3] / 60.0))
	check_eq(mid_hits, 0, "major incidents never land between rounds of a game")
	var ds := _director(9, 15, "supervised_transmission")
	var sup3 := 0
	for i in 500:
		ds.show_time += 300.0
		var inc2 := ds.incidents.opportunity("boundary", {"players": 4})
		if not inc2.is_empty() and int(inc2.tier) >= 3:
			sup3 += 1
	check_eq(sup3, 0, "SUPERVISED: no Tier 3")


func test_forced_incidents_play_out() -> void:
	for id in ["t2.cctv_room", "t3.graham_snap", "t3.silent_stare", "t2.banging"]:
		var store := temp_store("inc_" + id)
		store.installation.broadcasts_played = 15
		var h := SimHarness.new(cfg(), store, content(), 4040, SCALE)
		h.session.director.force["incident"] = id
		h.session.director.force["playlist"] = ["hole"]
		var a := h.add_bot("Aaron", "fast_random", 1)
		h.add_bot("Grace", "fast_random", 2)
		a.auto_start_at_count = 2
		check(h.run_until(func(): return h.events_of("incident").any(func(e): return e.id == id), 600.0), "%s fired" % id)
		var e: Dictionary = h.events_of("incident").filter(func(x): return x.id == id)[0]
		if id == "t2.cctv_room":
			check(e.params.has("room") and e.params.has("state"), "CCTV cutaway carries a room and its state")
		if id == "t3.graham_snap":
			check(h.run_until(func(): return h.events_of("say").any(func(s): return s.category == "incident_snap"), 30.0), "'I said stop.'")
			check(h.run_until(func(): return h.events_of("say").any(func(s): return s.category == "incident_snap_recover"), 30.0), "'Anyway!'")
		check(h.run_until(func(): return h.session.phase == SessionServer.Phase.ENDED, 900.0), "%s: show still completes" % id)


func test_punishment_segment() -> void:
	var store := temp_store("punish")
	store.installation.broadcasts_played = 6
	var h := SimHarness.new(cfg(), store, content(), 4141, SCALE)
	h.session.director.force["playlist"] = ["hole", "real_or_mildew"]
	h.session.director.force["punish"] = true
	var a := h.add_bot("Aaron", "afk", 1)
	var b := h.add_bot("Grace", "afk", 2)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return not h.events_of("special_punish").is_empty(), 1200.0), "EASY QUESTION segment appears between games")
	var ev: Dictionary = h.events_of("special_punish")[0]
	var victim: FakePlayerBot = a if ev.pid == a.player_id else b
	var other: FakePlayerBot = b if victim == a else a
	check(h.run_until(func(): return victim.last_screen.get("screen") == "question", 30.0), "victim's phone gets the question")
	check_eq(other.last_screen.get("screen"), "watch", "everyone else watches")
	var before: int = h.session.players[victim.player_id].score
	var right := (victim.last_screen.data.options as Array).find(ev.options[0]) if false else -1
	# answer correctly using the TV event (options shuffled; the item lists the right one first)
	var item: Dictionary = h.session._current.item
	right = (ev.options as Array).find(item.options[int(item.correct)])
	h.send_raw(victim, JSON.stringify({"t": "answer", "q": victim.last_screen.data.qid, "c": right}))
	check(h.run_until(func(): return not h.events_of("special_punish_result").is_empty(), 30.0), "result shown")
	check(bool(h.events_of("special_punish_result")[0].ok), "HE'S DONE IT!")
	check_eq(h.session.players[victim.player_id].score, before + 100, "a token reward")


func test_the_test_interruption() -> void:
	var store := temp_store("thetest")
	store.installation.broadcasts_played = 15
	var h := SimHarness.new(cfg(), store, content(), 4242, SCALE)
	h.session.director.force["playlist"] = ["hole", "real_or_mildew", "guess_the_genitals"]
	h.session.director.force["the_test"] = true
	h.session.director.force["furniture"] = "break"
	var a := h.add_bot("Aaron", "afk", 1)
	var b := h.add_bot("Grace", "afk", 2)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return a.last_screen.get("screen") == "test_q", 1500.0), "THE TEST reaches the phones")
	var qa: String = a.last_screen.data.ask
	for i in 3:
		for bot in [a, b]:
			if bot.last_screen.get("screen") == "test_q":
				h.send_raw(bot, JSON.stringify({"t": "answer", "q": bot.last_screen.data.qid, "c": 0}))
		h.run_until(func(): return false, 0.3)
	check(h.run_until(func(): return not h.events_of("special_test_end").is_empty(), 60.0), "the programme resumes")
	check(h.events_of("say").any(func(s): return s.category == "test_after"), "Graham apologises for the interruption")
	check(not (h.session.store.installation.get("the_test", []) as Array).is_empty(), "answers kept locally")
	check(not JSON.stringify(h.tv_events.filter(func(e): return e.e == "special_test")).contains(qa), "the questions never appear on the TV")


func test_announcer_drifts_slowly() -> void:
	var store := temp_store("announcer")
	var stage := 0
	for i in 12:
		var h := SimHarness.new(cfg(), store, content(), 5000 + i, 30.0)
		h.session.director.force["playlist"] = ["real_or_mildew"]
		var a := h.add_bot("A", "fast_random", 1)
		h.add_bot("B", "fast_random", 2)
		a.auto_start_at_count = 2
		h.run_until(func(): return h.session.phase == SessionServer.Phase.ENDED, 900.0)
		var s := int(store.installation.get("announcer_stage", 0))
		check(s >= stage and s <= stage + 1, "announcer stage moves one step at most per broadcast")
		stage = s
	check(stage >= 1 and stage <= 3, "after 12 broadcasts the Announcer has drifted (stage %d)" % stage)
	check(store.installation.has("rooms"), "room state saved with the installation")
