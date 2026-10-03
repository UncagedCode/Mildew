extends MildewTest
## CP8 programme furniture: adverts, midpoint commercial break (early resume when everyone's back),
## viewer polls, awards, run-over trimming, and the full Director-generated programme.

const SCALE := 12.0


func test_content() -> void:
	var ads := content().query("advert")
	check(ads.size() >= 8, "8–12 adverts (%d)" % ads.size())
	var brands := {}
	for a in ads:
		brands[a.brand] = true
	check(brands.size() >= 5, "five+ brands (%d)" % brands.size())
	check(content().query("poll").size() >= 10, "viewer polls")
	var v := ContentValidator.new()
	check(v.validate(content()), "all content validates: %s" % str(v.errors.slice(0, 4)))


func test_programme_skeleton() -> void:
	for seed in [1, 2, 3, 4, 5, 6]:
		var d := Director.new(content(), seed)
		d.cfg = cfg()
		d.begin_session({"broadcasts_played": 8}, "standard_transmission")
		var plan := d.plan_episode(["a", "b", "c", "d"])
		var kinds: Array = plan.map(func(s): return s.kind)
		check_eq(plan.filter(func(s): return s.kind == "advert" and s.get("mode") == "break").size(), 1, "exactly one midpoint commercial break")
		check(kinds.has("awards") and kinds.find("awards") < kinds.rfind("scores"), "awards before the final scoreboard")
		check_eq(d.games_this_show.size(), 5, "five games")
		# the break sits between the 3rd and 4th game
		var bi: int = kinds.find("advert") if plan.filter(func(s): return s.kind == "advert").size() == 1 else plan.find(plan.filter(func(s): return s.get("mode") == "break")[0])
		var before := plan.slice(0, bi).filter(func(s): return int(s.get("game_index", 0)) > 0).map(func(s): return int(s.game_index))
		check(before.max() == 3, "break after game 3 of 5 (%s)" % str(before.max()))


func test_full_broadcast_with_break_and_awards() -> void:
	var store := temp_store("bcast")
	store.installation.broadcasts_played = 8
	var h := SimHarness.new(cfg(), store, content(), 8080, SCALE)
	var bots: Array = []
	for i in 4:
		bots.append(h.add_bot("P%d" % i, ["high_accuracy", "fast_random", "cautious", "horse"][i], 500 + i))
	bots[0].auto_start_at_count = 4
	check(h.run_until(func(): return h.session.phase == SessionServer.Phase.ENDED, 1500.0), "full programme completes")
	check(not h.events_of("advert_show").is_empty(), "adverts aired")
	var cards := h.events_of("break_card")
	check(cards.any(func(c): return c.kind == "out") and cards.any(func(c): return c.kind == "in"), "break bumpers out and back")
	check(not h.events_of("break_ready").is_empty(), "contestants pressed READY during the break")
	check(not h.events_of("award").is_empty(), "awards handed out")
	check(h.events_of("say").any(func(e): return e.speaker == "advert"), "advert voice-over subtitled")
	var mins := h.session.session_time / 60.0
	print("      simulated programme: %.1f min, games %s" % [mins, h.session.director.games_this_show])
	check(mins > 15.0 and mins < 60.0, "programme length plausible (%.1f min)" % mins)


func test_break_resumes_early_when_everyone_is_back() -> void:
	var store := temp_store("brk")
	var h := SimHarness.new(cfg(), store, content(), 8081, SCALE)
	h.session.director.force["playlist"] = ["hole", "real_or_mildew"]
	h.session.director.force["furniture"] = "break"
	var a := h.add_bot("Aaron", "fast_random", 1)
	var b := h.add_bot("Grace", "fast_random", 2)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return h.events_of("break_card").any(func(c): return c.kind == "in"), 1200.0), "break completes")
	var outs := h.events_of("break_card").filter(func(c): return c.kind == "out")
	var ins := h.events_of("break_card").filter(func(c): return c.kind == "in")
	var dur: float = float(ins[0].st) - float(outs[0].st)
	check(dur < 88.0, "everyone READY: the break ends before its full 90 s (%.1f s)" % dur)


func test_overrun_trims_future_rounds_only() -> void:
	var d := Director.new(content(), 3)
	d.cfg = cfg()
	d.begin_session({"broadcasts_played": 8}, "standard_transmission")
	d.force["playlist"] = ["real_or_mildew", "guess_the_genitals", "hole"]
	var plan := d.plan_episode(["a", "b", "c"])
	var segs: Array = plan.filter(func(s): return int(s.get("game_index", 0)) >= 2)
	var before_g2 := segs.filter(func(s): return int(s.game_index) == 2 and s.kind == "question").size()
	d.show_time = 44.0 * 60.0
	var removed := d.maybe_trim(segs, 2)
	check(removed > 0, "running late: rounds removed (%d)" % removed)
	check_eq(segs.filter(func(s): return int(s.game_index) == 2 and s.kind == "question").size(), before_g2, "the game in progress is never cut")
	for gi in [3]:
		check(segs.filter(func(s): return int(s.get("game_index", 0)) == gi and Director.ROUND_KINDS.has(s.kind)).size() >= 2, "future games keep at least two rounds")
	check(d.decision_log.any(func(e): return str(e).contains("Overrun")), "overrun logged")
	d.show_time = 5.0 * 60.0
	check_eq(d.maybe_trim(segs, 2), 0, "on time: nothing trimmed")


func test_all_games_can_appear() -> void:
	var seen := {}
	for seed in range(1, 40):
		var d := Director.new(content(), seed)
		d.cfg = cfg()
		d.begin_session({"broadcasts_played": 20}, "standard_transmission")
		d.plan_episode(["a", "b", "c", "d"])
		for g in d.games_this_show:
			seen[g] = true
	check_eq(seen.size(), 8, "all eight games get scheduled across programmes: %s" % str(seen.keys()))
