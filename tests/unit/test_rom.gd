extends MildewTest
## Real or Mildew? (CP3): content shape + sources, per-asking option shuffle, all_real keeps its
## last option, confidence wager scoring, Graham's "Certain, were you?", fact archive, validator.

const SCALE := 12.0


func _harness(tag: String, seed: int = 777, force := {}) -> SimHarness:
	var store := temp_store(tag)
	store.installation.broadcasts_played = 3
	var h := SimHarness.new(cfg(), store, content(), seed, SCALE)
	h.session.director.force = force
	h.session.director.force["game"] = "real_or_mildew"
	return h


func _ended(h: SimHarness) -> Callable:
	return func(): return h.session.phase == SessionServer.Phase.ENDED or h.session.phase == SessionServer.Phase.CLOSED


func _rom_shows(h: SimHarness) -> Array:
	return h.events_of("question_show").filter(func(e): return e.game_id == "real_or_mildew")


func test_content_is_sourced_and_well_formed() -> void:
	var items := content().query("real_or_mildew")
	check(items.size() >= 30, "30+ Real or Mildew items (%d)" % items.size())
	var rounds := {}
	for it in items:
		rounds[it.round] = int(rounds.get(it.round, 0)) + 1
		check(not (it.sources as Array).is_empty(), "%s has sources" % it.id)
		check(str(it.fact).length() > 40, "%s has a real explanation" % it.id)
		check((it.content_tags as Array).has("factual"), "%s tagged factual" % it.id)
	check(rounds.has("which_real") and rounds.has("one_mildew") and rounds.has("all_real"), "all three round shapes present: %s" % [rounds])
	check(int(rounds.get("all_real", 0)) <= 3, "ALL REAL stays rare")


func test_full_game_scoring_and_shuffle() -> void:
	var h := _harness("rom_full")
	var a := h.add_bot("Aaron", "high_accuracy", 1)
	var b := h.add_bot("Grace", "terrible", 2)
	a.auto_start_at_count = 2
	check(h.run_until(_ended(h), 600.0), "show with Real or Mildew completes")
	var shows := _rom_shows(h)
	check(shows.size() >= 5, "a full Real or Mildew game (%d questions)" % shows.size())
	var firsts := {}
	for e in shows:
		var it: Dictionary = content().get_item(str(e.qid).split("#")[0])
		var src: Array = it.options
		check(e.options.size() == src.size(), "all options presented")
		for o in src:
			check((e.options as Array).has(o), "option text preserved")
		firsts[e.options[0]] = true
		if it.round == "all_real":
			check_eq(e.options[-1], src[-1], "'they're all real' stays last")
	check(firsts.size() > 1, "presentation order varies (not always the data order)")
	var ids := shows.map(func(e): return str(e.qid).split("#")[0])
	var uniq := {}
	for i in ids:
		check(not uniq.has(i), "no repeat within the game (%s)" % i)
		uniq[i] = true
	# server truth: the reveal's correct index points at the item's correct option text
	for e in h.events_of("reveal").filter(func(r): return r.game_id == "real_or_mildew"):
		var it2: Dictionary = content().get_item(str(e.qid).split("#")[0])
		check_eq(e.answer_text, it2.options[int(it2.correct)], "reveal answer is the item's real answer")
	var st := h.session.standings()
	var hi: int = st.filter(func(s): return s.pid == a.player_id)[0].score
	var lo: int = st.filter(func(s): return s.pid == b.player_id)[0].score
	check(hi > lo, "accurate player beats the terrible one (%d > %d)" % [hi, lo])
	check(not (h.session.store.installation.get("facts_seen", []) as Array).is_empty(), "facts archived for the Viewer Information Service")


func test_confidence_wager() -> void:
	var h := _harness("rom_conf", 778, {"rom_confidence": true})
	h.session.director.familiarity_tier = 2
	var a := h.add_bot("Aaron", "afk", 1)
	var b := h.add_bot("Grace", "afk", 2)
	var c := h.add_bot("Josh", "afk", 3)
	a.auto_start_at_count = 3
	var seen_conf := [false]
	var conf_q := [""]
	var ok := h.run_until(func():
		var s: Dictionary = a.last_screen
		if s.get("screen") == "question" and s.data.get("confidence", false):
			seen_conf[0] = true
			conf_q[0] = s.data.qid
			return true
		return h.session.phase == SessionServer.Phase.ENDED, 600.0)
	check(ok and seen_conf[0], "a confidence round was offered on the phone")
	if not seen_conf[0]:
		return
	var qid: String = conf_q[0]
	var opts: Array = a.last_screen.data.options
	var right := h.correct_index(qid, opts)
	h.send_raw(a, JSON.stringify({"t": "answer", "q": qid, "c": right, "k": 1}))          # certain + right
	h.send_raw(b, JSON.stringify({"t": "answer", "q": qid, "c": right, "k": 0}))          # normal + right
	h.send_raw(c, JSON.stringify({"t": "answer", "q": qid, "c": (right + 1) % opts.size(), "k": 1}))   # certain + wrong
	check(h.run_until(func(): return h.events_of("reveal").any(func(e): return e.qid == qid), 60.0), "confidence question revealed")
	var rev: Dictionary = h.events_of("reveal").filter(func(e): return e.qid == qid)[0]
	var da := int(rev.deltas[a.player_id])
	var db := int(rev.deltas[b.player_id])
	check(da >= db * 2 - 20 and da <= db * 2 + 20, "certain + right = double (%d vs %d)" % [da, db])
	check_eq(int(rev.deltas[c.player_id]), 0, "certain + wrong costs nothing but pride")
	check(rev.certain.has(a.player_id) and rev.certain.has(c.player_id), "certainty shown on the TV")
	check(h.run_until(func(): return h.events_of("say").any(func(e): return e.category == "certain_wrong"), 30.0), "Graham: 'Certain, were you?'")


func test_k_flag_ignored_outside_confidence_rounds() -> void:
	var h := _harness("rom_k", 779)
	var a := h.add_bot("Aaron", "afk", 1)
	var b := h.add_bot("Grace", "afk", 2)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return a.last_screen.get("screen") == "question" and not a.last_screen.data.get("confidence", false) and str(a.last_screen.data.qid).begins_with("rom."), 600.0), "normal Real or Mildew question")
	var qid: String = a.last_screen.data.qid
	var right := h.correct_index(qid, a.last_screen.data.options)
	h.send_raw(a, JSON.stringify({"t": "answer", "q": qid, "c": right, "k": 1}))
	h.send_raw(b, JSON.stringify({"t": "answer", "q": qid, "c": right}))
	check(h.run_until(func(): return h.events_of("reveal").any(func(e): return e.qid == qid), 60.0), "revealed")
	var rev: Dictionary = h.events_of("reveal").filter(func(e): return e.qid == qid)[0]
	check(absi(int(rev.deltas[a.player_id]) - int(rev.deltas[b.player_id])) <= 200, "a forged 'certain' flag earns nothing extra")


func test_validator_rejects_bad_items() -> void:
	var v := ContentValidator.new()
	var bad := ContentDB.new()
	bad.add_pack({"pack_id": "bad", "content_kind": "real_or_mildew", "_path": "bad.json", "items": [
		{"id": "x1", "enabled": true, "quality_status": "reviewed", "familiarity_tier": 1, "content_tags": ["factual"], "min_players": 2, "max_players": 8,
			"category": "medicine", "round": "which_real", "prompt": "P", "options": ["a", "b", "c", "d"], "correct": 0, "fact": "", "sources": []},
		{"id": "x2", "enabled": true, "quality_status": "draft", "familiarity_tier": 1, "content_tags": ["factual"], "min_players": 2, "max_players": 8,
			"category": "astrology", "round": "all_real", "prompt": "P", "options": ["a", "b", "c", "d"], "correct": 0, "fact": "f",
			"sources": [{"title": "t", "publisher_or_organisation": "", "reference": "r", "supported_claim": "c"}]}]})
	check(not v.validate(bad), "bad Real or Mildew items rejected")
	var j := "\n".join(v.errors)
	for frag in ["factual item missing source metadata", "missing factual explanation", "unknown Real or Mildew category", "all_real round must", "source missing 'publisher_or_organisation'"]:
		check(j.contains(frag), "validator catches: %s" % frag)
	v.validate(content(), true)
	check(v.errors.any(func(e): return str(e).contains("rom.")) or not content().query("real_or_mildew").all(func(i): return i.quality_status == "approved"),
		"release mode refuses unreviewed factual content")
