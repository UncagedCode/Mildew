extends MildewTest
## Director determinism/line pools and content validation.


func test_content_library_validates() -> void:
	var db := content()
	var v := ContentValidator.new()
	var ok := v.validate(db)
	check(ok, "shipped content validates: %s" % [v.errors])
	check(db.query("multiple_choice", "studio_rehearsal").size() >= 3, "enough rehearsal questions")
	check(db.query("graham_lines").size() > 40, "Graham line pool loaded")


func test_validator_catches_problems() -> void:
	var db := ContentDB.new()
	db.add_pack({"_path": "a.json", "pack_id": "t1", "content_kind": "multiple_choice", "items": [
		{"id": "x", "enabled": true, "quality_status": "draft", "familiarity_tier": 1, "content_tags": ["food"], "min_players": 2, "max_players": 8,
			"prompt": "Q", "options": ["a", "b"], "correct": 5},
		{"id": "x", "enabled": true, "quality_status": "final", "familiarity_tier": 9, "content_tags": ["not_a_tag"], "min_players": 6, "max_players": 3,
			"prompt": "Q", "options": ["a", "a"], "correct": 0},
		{"id": "fact1", "enabled": true, "quality_status": "reviewed", "familiarity_tier": 2, "content_tags": ["factual"], "min_players": 2, "max_players": 8,
			"prompt": "Q", "options": ["a", "b"], "correct": 0, "media": [{"asset_path": "res://nope.png", "source": "", "licence": "", "approval_status": "pending"}]},
		{"id": "fact2", "enabled": true, "quality_status": "placeholder", "familiarity_tier": 2, "content_tags": ["factual"], "min_players": 2, "max_players": 8,
			"prompt": "Q", "options": ["a", "b"], "correct": 1},
	]})
	var v := ContentValidator.new()
	check(not v.validate(db), "invalid pack fails")
	var joined := "\n".join(v.errors)
	for needle in ["duplicate id", "out of range", "unsupported quality_status", "invalid familiarity_tier", "unknown content tag",
			"malformed player-count", "duplicate option", "missing source metadata", "licence metadata", "missing referenced asset"]:
		check(joined.contains(needle), "validator reports '%s'" % needle)
	check(not joined.contains("fact2"), "placeholder factual without source only warns in dev mode")
	var rv := ContentValidator.new()
	rv.validate(db, true)
	check("\n".join(rv.errors).contains("placeholder factual content blocked"), "release mode blocks placeholder factual")


func test_director_lines_avoid_repeats_and_fill_slots() -> void:
	var d := Director.new(content(), 4242)
	var seen := {}
	var prev := ""
	for i in 6:
		var l := d.line("graham", "lobby_join", {"name": "Aaron", "speech_name": "Air-on"})
		check(not l.is_empty(), "line found")
		check(l.id != prev, "no immediate repeat")
		check(l.text.contains("Aaron") or not l.text.contains("{"), "display slot filled")
		check(not l.speech.contains("Aaron") or not l.text.contains("Aaron"), "speech uses pronunciation form")
		prev = l.id
		seen[l.id] = true
	check(seen.size() >= 4, "variety across lines")


func test_director_deterministic_with_seed() -> void:
	var a := Director.new(content(), 99)
	var b := Director.new(content(), 99)
	var qa := a.pick_questions("studio_rehearsal", 3, 4).map(func(q): return q.id)
	var qb := b.pick_questions("studio_rehearsal", 3, 4).map(func(q): return q.id)
	check_eq(qa, qb, "same seed -> same selection")
	var unique := {}
	for id in qa:
		unique[id] = true
	check_eq(unique.size(), 3, "no repeats within a game")


func test_director_prefers_unseen_installation_content() -> void:
	var d := Director.new(content(), 5)
	var all := content().query("multiple_choice", "studio_rehearsal").map(func(q): return q.id)
	d.recent_installation_content = all.slice(0, all.size() - 3)
	var picked := d.pick_questions("studio_rehearsal", 3, 2).map(func(q): return q.id)
	for id in picked:
		check(not d.recent_installation_content.has(id), "picked unseen %s" % id)


func test_director_skeleton_and_logs() -> void:
	var d := Director.new(content(), 3)
	d.begin_session({"broadcasts_played": 7}, "standard_transmission")
	check_eq(d.familiarity_tier, 3, "familiarity tier grows with installation experience")
	var plan := d.plan_episode(["p1", "p2"], 3)
	check_eq(plan.filter(func(s): return s.kind == "question").size(), 3, "three questions planned")
	check(d.skeleton.filter(func(s): return s.state == "unresolved").size() >= 3, "future slots left unresolved")
	check(d.decision_log.filter(func(e): return e.kind == "SelectGame").size() == 1, "selection explained in log")


func test_director_mood_reacts() -> void:
	var d := Director.new(content(), 8)
	d.on_question_result([{"pid": "p1", "answered": false, "correct": false, "elapsed": 20.0}, {"pid": "p2", "answered": false, "correct": false, "elapsed": 20.0}], 20.0)
	check_eq(d.graham_mood, "irritated", "nobody answering irritates Graham")
	d.tick(60.0)
	check_eq(d.graham_mood, "relaxed", "mood drifts back")
	d.on_all_gone()
	check_eq(d.graham_mood, "angry", "everyone leaving angers Graham")
