extends MildewTest
## Mildew Survey + Mouthfeel (CP4): write-then-vote engine, archive filler for two players,
## self-vote ban, match bonus, Graham's anonymous answer, Make It Worse, rare answer tampering,
## local answer archive, content + validators.

const SCALE := 12.0


func _harness(tag: String, game: String, seed: int = 4242, force := {}, played := 3) -> SimHarness:
	var store := temp_store(tag)
	store.installation.broadcasts_played = played
	var h := SimHarness.new(cfg(), store, content(), seed, SCALE)
	h.session.director.force = force
	h.session.director.force["game"] = game
	return h


func _ended(h: SimHarness) -> Callable:
	return func(): return h.session.phase == SessionServer.Phase.ENDED or h.session.phase == SessionServer.Phase.CLOSED


func test_content_and_validator() -> void:
	var sv := content().query("mildew_survey")
	var mf := content().query("mouthfeel")
	check(sv.size() >= 40, "40+ survey prompts (%d)" % sv.size())
	check(mf.size() >= 40, "40+ Mouthfeel prompts/components (%d)" % mf.size())
	for f in ["describe", "chain", "reverse"]:
		check(mf.any(func(i): return i.format == f), "Mouthfeel has %s items" % f)
	for it in sv:
		check((it.archive as Array).size() >= 3, "%s has archive filler" % it.id)
	var v := ContentValidator.new()
	check(v.validate(content()), "shipped content validates: %s" % str(v.errors.slice(0, 5)))
	var bad := ContentDB.new()
	var base := {"enabled": true, "quality_status": "draft", "familiarity_tier": 1, "content_tags": ["social"], "min_players": 2, "max_players": 8}
	var a := base.duplicate(true)
	a.merge({"id": "b1", "prompt": "", "archive": ["x"], "modes": ["popularity", "karaoke"]})
	bad.add_pack({"pack_id": "bad1", "content_kind": "mildew_survey", "_path": "b1.json", "items": [a]})
	var c := base.duplicate(true)
	c.merge({"id": "b2", "format": "chain", "base": ""})
	var d := base.duplicate(true)
	d.merge({"id": "b3", "format": "interpretive_dance"})
	bad.add_pack({"pack_id": "bad2", "content_kind": "mouthfeel", "_path": "b2.json", "items": [c, d]})
	check(not v.validate(bad), "bad write/vote content rejected")
	var j := "\n".join(v.errors)
	for frag in ["missing prompt", "archive needs at least 3", "unknown survey mode 'karaoke'", "chain item needs a base", "Make It Worse needs min_players >= 3", "unknown Mouthfeel format"]:
		check(j.contains(frag), "validator catches: %s" % frag)


func test_match_key_and_clean() -> void:
	check_eq(SegWriteVote.match_key("A Dog!"), SegWriteVote.match_key("dogs"), "'A Dog!' matches 'dogs'")
	check_eq(SegWriteVote.match_key("The horse"), SegWriteVote.match_key("a horse"), "articles ignored")
	check(SegWriteVote.match_key("glass") != SegWriteVote.match_key("glas"), "double-s words keep their s")
	check_eq(SegWriteVote.clean_text("  hello​   there\n ", 80), "hello there", "control/zero-width chars and spacing cleaned")
	check_eq(SegWriteVote.clean_text("x".repeat(200), 80).length(), 80, "length capped")


func test_full_survey_three_players() -> void:
	var h := _harness("sv_full", "mildew_survey", 4243, {"survey_mode": "who_said"})
	var a := h.add_bot("Aaron", "fast_random", 1)
	var b := h.add_bot("Grace", "high_accuracy", 2)
	var c := h.add_bot("Josh", "fast_random", 3)
	a.auto_start_at_count = 3
	check(h.run_until(_ended(h), 900.0), "show with the Mildew Survey completes")
	var shows := h.events_of("wv_show").filter(func(e): return e.game_id == "mildew_survey")
	check(shows.size() >= 3, "survey rounds played (%d)" % shows.size())
	var reveals := h.events_of("wv_reveal").filter(func(e): return str(e.qid).begins_with("sv."))
	check_eq(reveals.size(), shows.size(), "every round reveals")
	check(reveals.any(func(e): return e.mode == "who_said"), "a WHO SAID THAT? round ran")
	var total := 0
	for p in [a, b, c]:
		total += h.session.players[p.player_id].score
		check(not p.errors_received.has(Protocol.E_SELF_VOTE), "bots never attempted a self-vote")
	check(total > 0, "votes became points")
	for e in reveals.filter(func(r): return r.mode == "popularity"):
		for pid in e.votes:
			var idx := int(e.votes[pid])
			check(e.answers[idx].author != pid, "no vote counted for own answer")
	check(not (h.session.store.installation.get("archive_answers", {}) as Dictionary).is_empty(), "winning answers enter the local archive")


func test_two_player_archive_filler_and_self_vote() -> void:
	var h := _harness("sv_two", "mildew_survey", 4244)
	var a := h.add_bot("Aaron", "afk", 1)
	var b := h.add_bot("Grace", "afk", 2)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return a.last_screen.get("screen") == "wv_write", 600.0), "write screen reached")
	var qid: String = a.last_screen.data.qid
	h.send_raw(a, JSON.stringify({"t": "submit", "q": qid, "text": "A wet sock"}))
	h.send_raw(b, JSON.stringify({"t": "submit", "q": qid, "text": "Ham"}))
	h.send_raw(a, JSON.stringify({"t": "submit", "q": qid, "text": "again"}))
	check(h.run_until(func(): return a.last_screen.get("screen") == "wv_vote", 120.0), "vote screen reached")
	var board: Dictionary = h.events_of("wv_vote_open").filter(func(e): return e.qid == qid)[0]
	check((board.answers as Array).size() >= 3, "two players + archive filler gives a real vote (%d answers)" % board.answers.size())
	var own := int(a.last_screen.data.own)
	check(own >= 0 and board.answers[own] == "A wet sock", "phone knows which answer is its own")
	h.send_raw(a, JSON.stringify({"t": "vote", "q": qid, "c": own}))
	h.run_until(func(): return false, 1.0)
	check(a.errors_received.has(Protocol.E_SELF_VOTE), "self-vote refused")
	check(a.errors_received.has(Protocol.E_ALREADY_ANSWERED), "double submit refused")
	var other: int = (own + 1) % board.answers.size()
	h.send_raw(a, JSON.stringify({"t": "vote", "q": qid, "c": other}))
	check(h.run_until(func(): return h.events_of("wv_reveal").any(func(e): return e.qid == qid), 120.0), "revealed")
	var rev: Dictionary = h.events_of("wv_reveal").filter(func(e): return e.qid == qid)[0]
	check(rev.answers.any(func(x): return x.kind == "archive"), "archive answers identified at the reveal")
	if rev.answers[other].kind == "player":
		check(int(rev.deltas[b.player_id]) >= 500, "Grace's answer earned the vote")
	else:
		check_eq(int(rev.deltas.get(b.player_id, 0)), 0, "archive answers cannot earn player points")


func test_match_bonus() -> void:
	var h := _harness("sv_match", "mildew_survey", 4245)
	var a := h.add_bot("Aaron", "horse", 1)
	var b := h.add_bot("Grace", "horse", 2)
	var c := h.add_bot("Josh", "fast_random", 3)
	a.auto_start_at_count = 3
	check(h.run_until(func(): return h.events_of("say").any(func(e): return e.category == "wv_match"), 600.0), "Graham calls out a match")
	var rev: Dictionary = h.events_of("wv_reveal")[0]
	check(int(rev.deltas[a.player_id]) >= 250 and int(rev.deltas[b.player_id]) >= 250, "both matching players get the bonus")


func test_answer_tampering_rename() -> void:
	var h := _harness("sv_alter", "mildew_survey", 4246, {"alter_answer": "rename"})
	var a := h.add_bot("Aaron", "fast_random", 1)
	h.add_bot("Grace", "fast_random", 2)
	h.add_bot("Josh", "fast_random", 3)
	a.auto_start_at_count = 3
	check(h.run_until(func(): return not h.events_of("wv_vote_open").is_empty(), 600.0), "vote opened")
	check((h.events_of("wv_vote_open")[0].answers as Array).has("GRAHAM MILDEW"), "an answer is displayed as GRAHAM MILDEW")
	check(h.run_until(func(): return h.events_of("say").any(func(e): return e.category == "wv_altered"), 120.0), "Graham: 'Charming.'")
	check(h.session.director.decision_log.any(func(d): return str(d).contains("AnswerTampering")), "tampering logged for the Director debug view")
	check(h.session.director.force.get("alter_answer", "") == "", "force consumed (once, not every round)")


func test_mouthfeel_full_with_chain() -> void:
	var h := _harness("mf_full", "mouthfeel", 4247, {"mf_chain": true})
	var a := h.add_bot("Aaron", "fast_random", 1)
	h.add_bot("Grace", "high_accuracy", 2)
	h.add_bot("Josh", "fast_random", 3)
	a.auto_start_at_count = 3
	check(h.run_until(_ended(h), 900.0), "show with Mouthfeel completes")
	var shows := h.events_of("wv_show").filter(func(e): return e.game_id == "mouthfeel")
	check(shows.any(func(e): return e.mode == "chain"), "Make It Worse ran")
	check(shows.filter(func(e): return e.mode == "popularity").all(func(e): return str(e.category) != ""), "describe rounds have a vote category")
	check(h.events_of("question_show").any(func(e): return e.game_id == "mouthfeel"), "reverse round (Graham describes) ran")
	var finals := h.events_of("wv_chain_final")
	check(not finals.is_empty() and str(finals[0].text).contains(","), "chain grew: %s" % (finals[0].text if not finals.is_empty() else "-"))
	var revs := h.events_of("wv_reveal").filter(func(e): return str(e.qid).begins_with("mf.") and e.mode == "popularity")
	check(revs.all(func(e): return e.answers.any(func(x): return x.kind == "graham")), "Graham enters anonymously every describe round")
	var chain_rev := h.events_of("wv_reveal").filter(func(e): return e.mode == "chain")
	check(not chain_rev.is_empty() and float(chain_rev[0].average) >= 1.0, "chain rated")


func test_mouthfeel_two_players_no_chain() -> void:
	var h := _harness("mf_two", "mouthfeel", 4248, {"mf_chain": true})
	var a := h.add_bot("Aaron", "fast_random", 1)
	h.add_bot("Grace", "fast_random", 2)
	a.auto_start_at_count = 2
	check(h.run_until(_ended(h), 900.0), "two-player Mouthfeel completes")
	check(not h.events_of("wv_show").any(func(e): return e.mode == "chain"), "Make It Worse needs 3+")
	var boards := h.events_of("wv_vote_open").filter(func(e): return str(e.qid).begins_with("mf."))
	check(not boards.is_empty() and boards.all(func(e): return (e.answers as Array).size() >= 3), "two players still get a real vote")


func test_director_mixes_games() -> void:
	var seen := {}
	for seed in range(1, 13):
		var d := Director.new(content(), seed)
		d.cfg = cfg()
		d.begin_session({"broadcasts_played": 6}, "standard_transmission")
		d.plan_episode(["a", "b", "c"])
		for i in d.games_this_show.size():
			seen[d.games_this_show[i]] = true
			if i > 0:
				check(not (Director.FORMATS[d.games_this_show[i]].tags.has("writing") and Director.FORMATS[d.games_this_show[i - 1]].tags.has("writing")),
					"no two writing games back to back (%s)" % str(d.games_this_show))
	check(seen.size() >= 5, "all five implemented games get scheduled across seeds: %s" % str(seen.keys()))
