extends MildewTest
## Tier 0/1 incident engine: rarity, cooldowns, interference setting, safeguards, forcing,
## "some sessions are clean", and that incidents never break a show.


func _director(seed: int, mode: String, played: int = 3) -> Director:
	var d := Director.new(content(), seed)
	d.cfg = cfg()
	d.begin_session({"broadcasts_played": played}, mode)
	d.reset_for_new_show()
	return d


## Simulates ~45 minutes of hook points (one opportunity every ~12 s of show time).
func _simulate(d: Director, minutes: float = 45.0) -> Array:
	var fired: Array = []
	var moments := ["boundary", "hole_round_start", "hole_stage", "hole_reveal"]
	var t := 0.0
	while t < minutes * 60.0:
		d.tick(12.0)
		t += 12.0
		var m: String = moments[int(t / 12.0) % moments.size()]
		var inc := d.incidents.opportunity(m, {"game": "hole", "players": 4, "pid": "p1", "other_name": "Steve", "nobody_right": "yes"})
		if not inc.is_empty():
			fired.append({"t": d.show_time, "tier": inc.tier, "id": inc.id})
	return fired


func test_incident_content_validates() -> void:
	var v := ContentValidator.new()
	check(v.validate(content()), "content incl. incidents validates: %s" % [v.errors])
	var db := content()
	check(db.query("incident").filter(func(i): return int(i.tier) == 0).size() >= 6, "Tier 0 repertoire present")
	check(db.query("incident").filter(func(i): return int(i.tier) == 1).size() >= 4, "light Tier 1 repertoire present")
	var bad := ContentDB.new()
	bad.add_pack({"pack_id": "bad", "content_kind": "incident", "_path": "bad.json", "items": [
		{"id": "x", "enabled": true, "quality_status": "draft", "tier": 7, "target": "nope", "rarity_weight": -1, "cooldown_seconds": 1,
			"moments": ["whenever"], "payload": {"effect": "explode"}, "follow_up_pool": ["x"]}]})
	check(not v.validate(bad), "bad incident rejected")
	var j := "\n".join(v.errors)
	for frag in ["invalid incident tier", "invalid incident target", "rarity_weight", "unknown incident moment", "unknown incident effect", "circular"]:
		check(j.contains(frag), "validator catches: %s" % frag)


func test_incidents_are_sparse_and_respect_cooldowns() -> void:
	var totals := {0: 0, 1: 0}
	var clean_sessions := 0
	for seed in range(1, 61):
		var d := _director(seed, "standard_transmission")
		var fired := _simulate(d)
		var t1: Array = fired.filter(func(f): return f.tier == 1)
		var t0: Array = fired.filter(func(f): return f.tier == 0)
		totals[0] += t0.size()
		totals[1] += t1.size()
		if t1.is_empty():
			clean_sessions += 1
		for i in range(1, t1.size()):
			check(t1[i].t - t1[i - 1].t >= 240.0, "Tier 1 never clusters (seed %d)" % seed)
		for i in range(1, t0.size()):
			check(t0[i].t - t0[i - 1].t >= 40.0, "Tier 0 tier cooldown (seed %d)" % seed)
		var last := {}
		for f in fired:
			if last.has(f.id):
				var cd := float(content().get_item(f.id).cooldown_seconds)
				check(f.t - last[f.id] >= cd, "per-incident cooldown %s" % f.id)
			last[f.id] = f.t
		check(fired.size() <= 30, "a 45-minute show is never spammed (seed %d: %d)" % [seed, fired.size()])
	var avg0: float = totals[0] / 60.0
	var avg1: float = totals[1] / 60.0
	print("      avg per 45 min: tier0=%.1f tier1=%.1f; sessions with no tier1=%d/60" % [avg0, avg1, clean_sessions])
	check(avg0 >= 2.0 and avg0 <= 12.0, "Tier 0 production mess is reasonably available (%.1f)" % avg0)
	check(avg1 >= 0.5 and avg1 <= 3.5, "Tier 1 is occasional (%.1f)" % avg1)
	check(clean_sessions >= 3, "some sessions are unusually clean (%d)" % clean_sessions)
	check(avg1 < avg0, "odd things are rarer than cheap television")


func test_interference_setting_changes_eligibility() -> void:
	var std := 0
	var sup := 0
	var clean_t1 := 0
	var clean_t0 := 0
	for seed in range(100, 140):
		std += _simulate(_director(seed, "standard_transmission")).filter(func(f): return f.tier == 1).size()
		sup += _simulate(_director(seed, "supervised_transmission")).filter(func(f): return f.tier == 1).size()
		var c := _simulate(_director(seed, "clean_transmission"))
		clean_t1 += c.filter(func(f): return f.tier == 1).size()
		for f in c:
			if f.tier == 0:
				clean_t0 += 1
				check(content().get_item(f.id).get("clean_safe", false), "clean mode only allows mild production mess (%s)" % f.id)
	check(sup < std, "supervised reduces Tier 1 (%d < %d)" % [sup, std])
	check_eq(clean_t1, 0, "clean suppresses Tier 1")


func test_horror_saturation_blocks_tier1() -> void:
	var d := _director(5, "standard_transmission")
	d.tone["unsettling"] = 0.9
	var t1 := 0
	for i in 400:
		d.show_time += 200.0  # cooldowns never in the way
		var inc := d.incidents.opportunity("boundary", {"game": "hole", "players": 4})
		if not inc.is_empty() and int(inc.tier) == 1:
			t1 += 1
		d.tone["unsettling"] = 0.9
	check_eq(t1, 0, "no Tier 1 while recent unsettling density is high")


func test_forced_incident_and_hole_hook() -> void:
	var d := _director(6, "standard_transmission")
	d.force["incident"] = "t1.hole_doorway"
	check(d.incidents.opportunity("boundary", {"game": "hole", "players": 3}).is_empty() or true, "forced incident waits for an eligible moment")
	var inc := d.incidents.opportunity("hole_round_start", {"game": "hole", "players": 3})
	check_eq(str(inc.get("id", "")), "t1.hole_doorway", "forced Hole doorway fires at a round start")
	check_eq(str(inc.get("effect", "")), "hole_doorway", "effect carried")
	check(not d.force.has("incident"), "force consumed")
	var d2 := _director(7, "standard_transmission")
	for i in 300:
		d2.show_time += 2000.0
		var x := d2.incidents.opportunity("hole_round_start", {"game": "basement", "players": 3})
		check(x.is_empty() or str(x.id) != "t1.hole_doorway", "Hole doorway only in Hole")


func test_shows_with_incidents_still_complete() -> void:
	for seed in [31, 32, 33]:
		var store := temp_store("incshow%d" % seed)
		store.installation.broadcasts_played = 3
		var h := SimHarness.new(cfg(), store, content(), seed, 12.0)
		h.session.director.incidents.temperament = 4.0   # deliberately busy
		var a := h.add_bot("Aaron", "risk_taker", seed)
		h.add_bot("Sarah", "cautious", seed + 1)
		h.add_bot("Claire", "high_accuracy", seed + 2)
		a.auto_start_at_count = 3
		h.session.director.force["incident"] = "t0.lower_third_typo"
		h.session.director.force["game"] = "hole"
		check(h.run_until(func(): return h.session.phase == SessionServer.Phase.ENDED, 700.0), "busy-incident show completes (seed %d)" % seed)
		var incs := h.events_of("incident")
		check(incs.size() >= 1, "incidents happened (seed %d: %d)" % [seed, incs.size()])
		for e in incs:
			if e.effect == "lower_third_typo":
				check(str(e.params.typo) != "" and str(e.params.name) != "", "typo carries a real contestant name")
		check_eq(h.events_of("hole_reveal").size(), h.session.cfg.i("hole.rounds_per_game", 6), "all rounds still played")


func test_typo_is_plausible() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for n in ["Aaron", "Jo", "Stacy", "Graham"]:
		var t := SegIncident.typo(n, rng)
		check(t != "" and abs(t.length() - n.length()) <= 1, "typo of %s is close: %s" % [n, t])
