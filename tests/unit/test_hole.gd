extends MildewTest
## HOLE (CP2): stage scoring, early lock, partial credit, irreversibility, pass/skip, variants,
## reconnect, late join, no repeats, 2- and 8-player full games, validator.

const SCALE := 12.0


## Harness for a "returning" installation (no warm-up) at a given familiarity level.
func _harness(tag: String, seed: int = 4321, played: int = 3, force := {}) -> SimHarness:
	var store := temp_store(tag)
	store.installation.broadcasts_played = played
	var h := SimHarness.new(cfg(), store, content(), seed, SCALE)
	h.session.director.force = force
	return h


func _ended(h: SimHarness) -> Callable:
	return func(): return h.session.phase == SessionServer.Phase.ENDED or h.session.phase == SessionServer.Phase.CLOSED


func _hole(h: SimHarness) -> SegHole:
	return h.session._current as SegHole


func _until_stage(h: SimHarness, stage: int, max_s: float = 120.0) -> bool:
	return h.run_until(func():
		var seg = h.session._current
		return seg is SegHole and seg.sub == "stage" and seg.stage == stage, max_s)


func _start_two_afk(h: SimHarness) -> Array:
	var a := h.add_bot("Aaron", "afk", 1)
	var b := h.add_bot("Sarah", "afk", 2)
	a.auto_start_at_count = 2
	return [a, b]


func _lock(h: SimHarness, bot: FakePlayerBot, stage: int, label: String) -> void:
	var seg := _hole(h)
	var idx := seg.labels_for_stage(stage).find(label)
	h.send_raw(bot, JSON.stringify({"t": "lock", "q": seg.qid, "s": stage, "c": idx}))


func test_hole_full_game_two_players() -> void:
	var h := _harness("hole2p", 11)
	var a := h.add_bot("Aaron", "risk_taker", 21)
	var b := h.add_bot("Sarah", "cautious", 22)
	a.auto_start_at_count = 2
	check(h.run_until(_ended(h), 600.0), "2-player Hole show ends")
	check_eq(h.session.phase, SessionServer.Phase.ENDED, "ENDED")
	var rounds := h.session.cfg.i("hole.rounds_per_game", 6)
	check_eq(h.events_of("question_show").filter(func(e): return str(e.get("game_id", "")) == "studio_rehearsal").size(), 0, "returning installation skips the warm-up")
	check_eq(h.events_of("hole_round").size(), rounds, "all rounds played")
	check_eq(h.events_of("hole_reveal").size(), rounds, "all rounds revealed")
	var ids := {}
	for e in h.events_of("hole_round"):
		check(not ids.has(e.item_id), "no content repeat within the game (%s)" % e.item_id)
		ids[e.item_id] = true
	for s in h.session.standings():
		var hole_pts := 0
		for e in h.events_of("hole_reveal"):
			hole_pts += int(e.get("deltas", {}).get(s.pid, 0))
		check(hole_pts >= 0 and hole_pts <= int(rounds * 1500 * 1.5), "Hole points in bounds %s" % hole_pts)
	check(a.errors_received.is_empty() and b.errors_received.is_empty(), "no protocol errors: %s %s" % [a.errors_received, b.errors_received])
	check(h.events_of("sting").any(func(e): return e.game_id == "hole"), "Hole sting played")
	check(h.events_of("say").any(func(e): return e.category == "hole_rules"), "Graham explains the rules")


func test_hole_full_game_eight_players() -> void:
	var h := _harness("hole8p", 12)
	var kinds := ["risk_taker", "high_accuracy", "terrible", "afk", "horse", "cautious", "fast_random", "risk_taker"]
	for i in 8:
		var bot := h.add_bot("P%d" % i, kinds[i], 200 + i)
		if i == 0:
			bot.auto_start_at_count = 8
	check(h.run_until(_ended(h), 700.0), "8-player Hole show ends")
	check_eq(h.session.phase, SessionServer.Phase.ENDED, "ENDED")
	check_eq(h.session.standings().size(), 8, "eight in standings")
	var protocol_errors := 0
	for bot in h.bots:
		protocol_errors += bot.errors_received.filter(func(c): return c != Protocol.E_STALE).size()
	check_eq(protocol_errors, 0, "no non-stale protocol errors")


func test_hole_stage_scoring_and_partial_credit() -> void:
	var h := _harness("holescore", 13)
	var ab := _start_two_afk(h)
	var a: FakePlayerBot = ab[0]
	var b: FakePlayerBot = ab[1]
	check(_until_stage(h, 1), "stage 1 reached")
	var seg := _hole(h)
	if seg.variant == "scale":
		check(false, "first round should not be a scale round")
		return
	_lock(h, a, 1, seg.answer)
	# b: a wrong candidate from the SAME broad category (partial credit), else a different one.
	var same := ""
	var other := ""
	for i in seg.options.size():
		if seg.options[i] == seg.answer:
			continue
		if seg.option_cats[i] == seg.answer_cat and same == "":
			same = seg.options[i]
		elif seg.option_cats[i] != seg.answer_cat and other == "":
			other = seg.options[i]
	h.send_raw(b, JSON.stringify({"t": "pass", "q": seg.qid, "s": 1}))
	check(_until_stage(h, 2, 20.0), "b passing advances to stage 2 (a already locked)")
	_lock(h, b, 2, same if same != "" else other)
	check(h.run_until(func(): return h.events_of("hole_reveal").size() == 1, 30.0), "revealed")
	var d: Dictionary = h.events_of("hole_reveal")[0].deltas
	check_eq(int(d[a.player_id]), 1500, "correct at first glance = 1,500")
	if same != "":
		check_eq(int(d[b.player_id]), 200, "right category at stage 2 = 20% of 1,100 rounded = 200")
		check(h.events_of("hole_reveal")[0].outcome[b.player_id].partial, "flagged as partial")
	else:
		check_eq(int(d[b.player_id]), 0, "wrong = 0")
	# Round 2: a locks at stage 3 (750), b at the safety net (500).
	check(h.run_until(func(): return h.events_of("hole_round").size() == 2, 40.0), "round 2")
	check(_until_stage(h, 3, 60.0), "stage 3 reached by timer")
	seg = _hole(h)
	if seg.variant == "standard":
		_lock(h, a, 3, seg.answer)
		check(_until_stage(h, 4, 30.0), "safety net reached")
		check_eq(seg.labels_for_stage(4).size(), 4, "safety net offers four options")
		_lock(h, b, 4, seg.answer)
		check(h.run_until(func(): return h.events_of("hole_reveal").size() == 2, 30.0), "revealed 2")
		var d2: Dictionary = h.events_of("hole_reveal")[1].deltas
		check_eq(int(d2[a.player_id]), 750, "correct at stage 3 = 750")
		check_eq(int(d2[b.player_id]), 500, "correct on the safety net = 500")


func test_hole_lock_rules() -> void:
	var h := _harness("holerules", 14)
	var ab := _start_two_afk(h)
	var a: FakePlayerBot = ab[0]
	var b: FakePlayerBot = ab[1]
	check(h.run_until(func(): return h.session._current is SegHole, 120.0), "round started")
	var seg := _hole(h)
	h.send_raw(a, JSON.stringify({"t": "lock", "q": seg.qid, "s": 1, "c": 0}))
	h.step()
	check(a.errors_received.has(Protocol.E_INVALID_STATE), "cannot lock during the intro")
	check(_until_stage(h, 1), "stage 1")
	h.send_raw(a, JSON.stringify({"t": "lock", "q": "nonsense#1", "s": 1, "c": 0}))
	h.send_raw(a, JSON.stringify({"t": "lock", "q": seg.qid, "s": 2, "c": 0}))
	h.send_raw(a, JSON.stringify({"t": "lock", "q": seg.qid, "s": 1, "c": 99}))
	h.send_raw(a, JSON.stringify({"t": "lock", "q": seg.qid, "s": "1", "c": 0}))
	h.step()
	check_eq(a.errors_received.count(Protocol.E_STALE), 2, "wrong qid / future stage rejected as stale")
	check_eq(a.errors_received.count(Protocol.E_BAD_PAYLOAD), 2, "bad index / non-integer stage rejected")
	check(seg.locks.is_empty(), "no lock recorded from invalid messages")
	h.send_raw(a, JSON.stringify({"t": "lock", "q": seg.qid, "s": 1, "c": 0}))
	h.step()
	check(seg.locks.has(a.player_id), "valid lock recorded")
	var first: String = seg.locks[a.player_id].label
	h.send_raw(a, JSON.stringify({"t": "lock", "q": seg.qid, "s": 1, "c": 1}))
	h.send_raw(a, JSON.stringify({"t": "pass", "q": seg.qid, "s": 1}))
	h.step()
	check_eq(a.errors_received.count(Protocol.E_ALREADY_ANSWERED), 2, "once locked, it is locked")
	check_eq(seg.locks[a.player_id].label, first, "lock unchanged")
	check_eq(a.last_screen.screen, "hole_locked", "phone shows the locked state")
	# Points are computed by the server only: a client-supplied 'points' is ignored.
	h.send_raw(b, JSON.stringify({"t": "lock", "q": seg.qid, "s": 1, "c": 0, "points": 999999}))
	check(h.run_until(func(): return h.events_of("hole_reveal").size() == 1, 60.0), "revealed")
	for pid in h.events_of("hole_reveal")[0].deltas.keys():
		check(int(h.events_of("hole_reveal")[0].deltas[pid]) <= 1500, "server-side points only")


func test_hole_grace_window_and_pass_rules() -> void:
	var h := _harness("holegrace", 15)
	var ab := _start_two_afk(h)
	var a: FakePlayerBot = ab[0]
	var b: FakePlayerBot = ab[1]
	check(_until_stage(h, 1), "stage 1")
	var seg := _hole(h)
	h.send_raw(a, JSON.stringify({"t": "pass", "q": seg.qid, "s": 1}))
	h.send_raw(b, JSON.stringify({"t": "pass", "q": seg.qid, "s": 1}))
	h.step()
	h.step()
	check_eq(seg.stage, 2, "everyone passed -> next reveal immediately")
	# a's stage-1 tap arriving just after the advance counts at stage 1 (server grace window).
	h.send_raw(a, JSON.stringify({"t": "lock", "q": seg.qid, "s": 1, "c": seg.options.find(seg.answer)}))
	h.step()
	check(seg.locks.has(a.player_id) and int(seg.locks[a.player_id].stage) == 1, "late tap within grace counts at the stage it was made")
	# After the grace window, a stale stage is refused.
	h.run_until(func(): return seg.elapsed - seg.stage_started > seg.lock_grace * SCALE + 0.5, 10.0)
	h.send_raw(b, JSON.stringify({"t": "lock", "q": seg.qid, "s": 1, "c": 0}))
	h.step()
	check(b.errors_received.has(Protocol.E_STALE), "stale stage after grace rejected")
	check(_until_stage(h, 4, 60.0), "safety net")
	h.send_raw(b, JSON.stringify({"t": "pass", "q": seg.qid, "s": 4}))
	h.step()
	check(b.errors_received.has(Protocol.E_INVALID_STATE), "no passing on the final stage")


func test_hole_everyone_locked_skips_ahead() -> void:
	var h := _harness("holeskip", 16)
	var ab := _start_two_afk(h)
	check(_until_stage(h, 1), "stage 1")
	var seg := _hole(h)
	var t0 := seg.elapsed
	h.send_raw(ab[0], JSON.stringify({"t": "lock", "q": seg.qid, "s": 1, "c": 0}))
	h.send_raw(ab[1], JSON.stringify({"t": "lock", "q": seg.qid, "s": 1, "c": 1}))
	h.step()
	h.step()
	check(seg.sub == "closing" or seg.sub == "reveal", "round closes as soon as everyone has locked")
	check(seg.elapsed - t0 < 1.5, "no waiting for the stage timer")
	check(h.events_of("hole_stage").filter(func(e): return e.qid == seg.qid and e.stage == 2).is_empty(), "no further reveals")


func test_hole_silent_players_never_deadlock() -> void:
	var h := _harness("holesilent", 17)
	_start_two_afk(h)
	check(h.run_until(_ended(h), 600.0), "AFK-only Hole game still completes on timers")
	for e in h.events_of("hole_reveal"):
		for pid in e.deltas.keys():
			check_eq(int(e.deltas[pid]), 0, "no lock = 0 points")
	check(h.events_of("say").any(func(e): return e.category == "hole_nobody_locked" or e.category == "afk_player"), "Graham notices nobody playing")


func test_hole_reconnect_mid_round_keeps_lock() -> void:
	var h := _harness("holerc", 18)
	var ab := _start_two_afk(h)
	var a: FakePlayerBot = ab[0]
	check(_until_stage(h, 1), "stage 1")
	var seg := _hole(h)
	_lock(h, a, 1, seg.answer)
	h.step()
	h.disconnect_bot(a)
	h.run_until(func(): return h.session.hold_reason == "reconnect", 5.0)
	var stage_before := seg.stage
	h.run_until(func(): return false, 1.0)   # 12 show-seconds: inside the 30 s window
	check_eq(seg.stage, stage_before, "round frozen while a contestant reconnects")
	h.connect_bot(a)
	h.run_until(func(): return h.session.hold_reason == "", 5.0)
	check_eq(a.last_screen.get("screen"), "hole_locked", "reconnected phone shows its lock")
	check_eq(str(a.last_screen.data.label), seg.answer, "lock preserved across reconnect")
	check(h.run_until(func(): return h.events_of("hole_reveal").size() == 1, 60.0), "round completes")
	check_eq(int(h.events_of("hole_reveal")[0].deltas[a.player_id]), 1500, "points awarded after reconnect")


func test_hole_late_join_waits_for_game_end() -> void:
	var h := _harness("holelate", 19)
	var a := h.add_bot("Aaron", "fast_random", 31)
	var b := h.add_bot("Sarah", "fast_random", 32)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return h.events_of("hole_round").size() == 2, 300.0), "mid-game")
	var c := h.add_bot("Claire", "fast_random", 33)
	h.run_until(func(): return c.player_id != "", 5.0)
	var pc: PlayerState = h.session.players[c.player_id]
	check_eq(pc.status, PlayerState.Status.WAITING, "late joiner waits during Hole")
	h.run_until(func(): return pc.status == PlayerState.Status.ACTIVE or h.session.phase != SessionServer.Phase.SHOW, 600.0)
	check_eq(h.events_of("hole_reveal").size(), h.session.cfg.i("hole.rounds_per_game", 6), "never integrated mid-game")
	check(not c.screens_seen.has("hole_pick"), "late joiner never given a pick screen mid-game")


func test_hole_scale_variant() -> void:
	var h := _harness("holescale", 20, 3, {"hole_variant": "scale"})
	var ab := _start_two_afk(h)
	check(h.run_until(func(): return h.events_of("hole_round").any(func(e): return e.variant == "scale"), 400.0), "a SCALE round is scheduled")
	check(_until_stage(h, 1, 30.0), "scale stage 1")
	var seg := _hole(h)
	check_eq(seg.variant, "scale", "current round is the scale round")
	check_eq(seg.options, SegHole.SCALE_LABELS, "options are the four sizes")
	check(SegHole.SCALE_LABELS.has(seg.answer), "answer is a size")
	h.step()
	check_eq(ab[0].last_screen.data.get("prompt"), "HOW BIG IS THIS HOLE?", "phone asks for size")


func test_hole_open_variant_has_no_safety_net() -> void:
	var h := _harness("holeopen", 21, 12, {"hole_variant": "open"})
	_start_two_afk(h)
	check(h.run_until(_ended(h), 600.0), "game ends")
	var open_rounds: Array = h.events_of("hole_round").filter(func(e): return e.variant == "open")
	check_eq(open_rounds.size(), 1, "one ADVANCED OPEN GUESS round")
	if open_rounds.size() == 1:
		var q: String = open_rounds[0].qid
		check(h.events_of("hole_stage").filter(func(e): return e.qid == q and e.stage == 4).is_empty(), "no multiple-choice safety net")


func test_director_hole_variants_and_studio_gating() -> void:
	var c := content()
	var new_install := 0
	var seasoned_open := 0
	var studio_counts: Array = []
	for seed in range(1, 41):
		var d := Director.new(c, seed)
		d.cfg = cfg()
		d.begin_session({"broadcasts_played": 0}, "standard_transmission")
		d.reset_for_new_show()
		var items := d.pick_hole_items(6, 4)
		var v := d.choose_hole_variants(items)
		check(not v.has("open"), "no open-guess rounds for a new installation")
		check(items.all(func(it): return int(it.familiarity_tier) <= 1), "new installation: tier-1 items only")
		check(not items.any(func(it): return it.get("studio_hole", false)), "studio hole never on a new installation")
		new_install += 1
		var d2 := Director.new(c, seed)
		d2.cfg = cfg()
		d2.begin_session({"broadcasts_played": 15}, "standard_transmission")
		d2.reset_for_new_show()
		var items2 := d2.pick_hole_items(6, 4)
		var v2 := d2.choose_hole_variants(items2)
		if v2.has("open"):
			seasoned_open += 1
		check(v2[0] == "standard", "first round is always a standard round")
		studio_counts.append(items2.filter(func(it): return it.get("studio_hole", false)).size())
	check(seasoned_open > 0, "seasoned installations sometimes get an open round")
	check(studio_counts.max() <= 1, "at most one studio hole per game")
	check(studio_counts.min() == 0, "studio hole is not guaranteed")


func test_hole_content_validates_and_validator_catches_bad_items() -> void:
	var v := ContentValidator.new()
	var db := content()
	check(v.validate(db), "shipped content validates: %s" % [v.errors])
	check(db.query("hole", "hole").size() >= 20, "at least 20 Hole items (PoC target 20-30)")
	var bad := ContentDB.new()
	var good: Dictionary = db.query("hole", "hole")[0].duplicate(true)
	var items: Array = []
	var b1 := good.duplicate(true); b1.id = "bad.answer"; b1.answer = "Not listed"
	var b2 := good.duplicate(true); b2.id = "bad.net"; b2.safety_net = [b2.candidates[1].label, b2.candidates[2].label, b2.candidates[3].label, b2.candidates[4].label]
	var b3 := good.duplicate(true); b3.id = "bad.stages"; b3.stages = [{"x": 0.5, "y": 0.5, "zoom": 1.5}, {"x": 0.5, "y": 0.5, "zoom": 3.0}, {"x": 0.5, "y": 0.5, "zoom": 1.2}]
	var b4 := good.duplicate(true); b4.id = "bad.image"; b4.image = "res://assets/content/hole/nope.jpg"
	var b5 := good.duplicate(true); b5.id = "bad.media"; b5.media = []
	var b6 := good.duplicate(true); b6.id = "bad.scale"; b6.scale = "medium"
	items = [b1, b2, b3, b4, b5, b6]
	bad.add_pack({"pack_id": "bad", "content_kind": "hole", "game_id": "hole", "items": items, "_path": "bad.json"})
	check(not v.validate(bad), "bad pack fails")
	var joined := "\n".join(v.errors)
	check(joined.contains("not among the candidates"), "answer-not-in-candidates caught")
	check(joined.contains("safety_net does not contain the answer"), "safety net without answer caught")
	check(joined.contains("wider than the last"), "non-widening stages caught")
	check(joined.contains("missing referenced asset"), "missing image caught")
	check(joined.contains("licence metadata"), "missing media licence caught")
	check(joined.contains("invalid scale"), "invalid scale caught")
