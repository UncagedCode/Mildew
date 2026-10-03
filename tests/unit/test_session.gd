extends MildewTest
## Session/server authority, player counts, reconnect, late join, invalid actions.

const SCALE := 12.0


func _harness(tag: String, seed: int = 1234) -> SimHarness:
	var c := cfg()
	return SimHarness.new(c, temp_store(tag), content(), seed, SCALE)


func _ended(h: SimHarness) -> Callable:
	return func(): return h.session.phase == SessionServer.Phase.ENDED or h.session.phase == SessionServer.Phase.CLOSED


func test_two_player_full_show() -> void:
	var h := _harness("2p")
	var a := h.add_bot("Aaron", "high_accuracy", 11)
	var b := h.add_bot("Sarah", "fast_random", 12)
	a.auto_start_at_count = 2
	check(h.run_until(_ended(h), 400.0), "2-player show reaches the end")
	check_eq(h.session.phase, SessionServer.Phase.ENDED, "phase ENDED (not closed)")
	var warm := h.session.cfg.i("show.warmup_questions", 2)
	var rounds := h.session.cfg.i("hole.rounds_per_game", 6)
	var rehearsal := func(e): return str(e.get("game_id", "")) == "studio_rehearsal"
	check_eq(h.events_of("question_show").filter(rehearsal).size(), warm, "new installation gets the rehearsal warm-up")
	check_eq(h.events_of("reveal").filter(rehearsal).size(), warm, "warm-up reveals")
	check(h.events_of("sting").size() >= 3, "a multi-game programme (rehearsal + games)")
	check_eq(h.events_of("hole_round").size(), rounds, "a full game of Hole")
	check_eq(h.events_of("hole_reveal").size(), rounds, "every Hole round revealed")
	check(h.events_of("sign_off").size() == 1, "sign-off reached")
	var st := h.session.standings()
	check_eq(st.size(), 2, "two players in standings")
	check(int(st[0].score) >= int(st[1].score), "standings sorted")
	for s in st:
		check(int(s.score) >= 0, "no negative score")
		var earned := 0
		for e in h.tv_events.filter(func(x): return x.has("deltas")):   # every scoring event carries its deltas
			earned += int(e.get("deltas", {}).get(s.pid, 0))
		check_eq(int(s.score), earned, "score equals the sum of awarded points")
	var nonstale := (a.errors_received + b.errors_received).filter(func(c): return c != Protocol.E_STALE)
	check(nonstale.is_empty(), "bots got no errors (late answers aside): %s %s" % [a.errors_received, b.errors_received])


func test_eight_player_full_show() -> void:
	var h := _harness("8p", 99)
	var kinds := ["fast_random", "high_accuracy", "terrible", "afk", "horse", "cautious", "fast_random", "high_accuracy"]
	var names := ["Aaron", "Sarah", "Claire", "Steve", "Horse Bot", "Daniel", "Sam", "Stacy"]
	for i in 8:
		var bot := h.add_bot(names[i], kinds[i], 100 + i)
		if i == 0:
			bot.auto_start_at_count = 8
	check(h.run_until(_ended(h), 500.0), "8-player show reaches the end")
	check_eq(h.session.phase, SessionServer.Phase.ENDED, "phase ENDED")
	check_eq(h.session.standings().size(), 8, "eight players in standings")
	var numbers := {}
	for p in h.session.players.values():
		numbers[p.number] = true
	check_eq(numbers.size(), 8, "unique podium numbers")
	var afk_calls := h.events_of("say").filter(func(e): return e.category == "afk_player")
	var called := {}
	for e in afk_calls:
		check(not called.has(e.get("pid", "")), "afk call-out at most once per player")
		called[e.get("pid", "")] = true


func test_ninth_player_rejected() -> void:
	var h := _harness("9p")
	for i in 8:
		h.add_bot("P%d" % i, "fast_random", 300 + i)
	h.run_until(func(): return h.session.players.size() == 8, 10.0)
	var ninth := h.add_bot("Ninth", "fast_random", 399)
	h.run_until(func(): return not ninth.errors_received.is_empty(), 5.0)
	check(ninth.errors_received.has(Protocol.E_ROOM_FULL), "ninth player gets room_full (got %s)" % [ninth.errors_received])
	check_eq(h.session.players.size(), 8, "still eight players")


func test_start_requires_two_and_captain() -> void:
	var h := _harness("start")
	var a := h.add_bot("Aaron", "fast_random", 1)
	h.run_until(func(): return a.player_id != "", 5.0)
	h.session.receive_text(a.conn_id, JSON.stringify({"t": "start_show"}))
	h.step()
	check(a.errors_received.has(Protocol.E_NOT_ENOUGH_PLAYERS), "single player cannot start")
	var b := h.add_bot("Sarah", "fast_random", 2)
	h.run_until(func(): return b.player_id != "", 5.0)
	h.session.receive_text(b.conn_id, JSON.stringify({"t": "start_show"}))
	h.step()
	check(b.errors_received.has(Protocol.E_NOT_CAPTAIN), "non-captain cannot start")
	check_eq(h.session.phase, SessionServer.Phase.LOBBY, "still in lobby")
	h.session.receive_text(a.conn_id, JSON.stringify({"t": "start_show"}))
	h.step()
	check_eq(h.session.phase, SessionServer.Phase.SHOW, "captain starts show with two")


func test_invalid_actions_rejected() -> void:
	var h := _harness("invalid")
	# Before hello.
	var raw_conn := h.session.connect_client({"fake": true})
	var errs: Array = []
	h.session.send.connect(func(cid, m): if cid == raw_conn and m.t == "error": errs.append(m.code))
	h.session.receive_text(raw_conn, JSON.stringify({"t": "answer", "q": "x", "c": 0}))
	h.session.receive_text(raw_conn, "{not json")
	h.session.receive_text(raw_conn, JSON.stringify({"t": "give_me_points", "points": 99999}))
	h.session.receive_text(raw_conn, JSON.stringify({"t": "hello", "v": 1, "room": "ZZZZ"}))
	h.session.receive_text(raw_conn, JSON.stringify({"t": "hello", "v": 99, "key": h.session.join_key}))
	h.session.receive_text(raw_conn, JSON.stringify({"t": "hello", "v": 1, "key": h.session.join_key, "pad": "x".repeat(5000)}))
	check(errs.has(Protocol.E_NOT_HELLO), "action before hello rejected")
	check(errs.has(Protocol.E_BAD_JSON), "bad json rejected")
	check(errs.has(Protocol.E_UNKNOWN_TYPE), "unknown type rejected")
	check(errs.has(Protocol.E_BAD_ROOM), "wrong room code rejected")
	check(errs.has(Protocol.E_BAD_VERSION), "wrong protocol version rejected")
	check(errs.has(Protocol.E_TOO_LARGE), "oversize message rejected")
	# Lobby: answering is invalid state.
	var a := h.add_bot("Aaron", "afk", 5)
	var b := h.add_bot("Sarah", "afk", 6)
	h.run_until(func(): return a.player_id != "" and b.player_id != "", 5.0)
	h.send_raw(a, JSON.stringify({"t": "answer", "q": "x", "c": 0}))
	check(a.errors_received.has(Protocol.E_INVALID_STATE), "answer in lobby is invalid_state")
	# Start and wait for the answer window.
	h.session.receive_text(a.conn_id, JSON.stringify({"t": "start_show"}))
	check(h.run_until(func(): return a.last_screen.get("screen") == "question", 200.0), "reached a question")
	var qid: String = a.last_screen.data.qid
	h.send_raw(a, JSON.stringify({"t": "answer", "q": "stale#0", "c": 0}))
	check(a.errors_received.has(Protocol.E_STALE), "stale question id rejected")
	h.send_raw(a, JSON.stringify({"t": "answer", "q": qid, "c": 7}))
	check(a.errors_received.has(Protocol.E_BAD_PAYLOAD), "out-of-range choice rejected")
	h.send_raw(a, JSON.stringify({"t": "answer", "q": qid, "c": "1"}))
	h.send_raw(a, JSON.stringify({"t": "answer", "q": qid, "c": 1.5}))
	var before := h.session.invalid_message_count
	h.send_raw(a, JSON.stringify({"t": "answer", "q": qid, "c": 1}))
	check_eq(h.session.invalid_message_count, before, "valid answer accepted")
	h.send_raw(a, JSON.stringify({"t": "answer", "q": qid, "c": 2}))
	check(a.errors_received.has(Protocol.E_ALREADY_ANSWERED), "second answer rejected (locked)")
	var score_before: int = h.session.players[a.player_id].score
	h.send_raw(a, JSON.stringify({"t": "answer", "q": qid, "c": 1, "score": 999999}))
	check_eq(h.session.players[a.player_id].score, score_before, "client-supplied score ignored")


func test_reconnect_within_window_resumes() -> void:
	var h := _harness("reconnect")
	var a := h.add_bot("Aaron", "fast_random", 21)
	var b := h.add_bot("Sarah", "fast_random", 22)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return b.last_screen.get("screen") == "question", 200.0), "question reached")
	var pid := b.player_id
	h.disconnect_bot(b)
	h.step()
	check_eq(h.session.hold_reason, "reconnect", "show held for reconnect")
	var seg_elapsed: float = h.session._current.elapsed
	# Wait ~10s of the 30s window (scaled time).
	h.run_until(func(): return false, 10.0 / SCALE)
	check_eq(h.session._current.elapsed, seg_elapsed, "show time frozen during reconnect wait")
	check(h.events_of("player_lost").size() == 1, "player_lost emitted")
	h.connect_bot(b)  # bot re-sends hello with its resume token
	h.step()
	check_eq(b.player_id, pid, "same player id after resume")
	check_eq(h.session.hold_reason, "", "hold cleared immediately on reconnect")
	check(h.events_of("player_back").size() == 1, "player_back emitted")
	check(h.run_until(_ended(h), 400.0), "show completes after reconnect")
	check_eq(h.session.standings().size(), 2, "both players still in standings")


func test_reconnect_timeout_drops_and_continues() -> void:
	var h := _harness("drop")
	var a := h.add_bot("Aaron", "fast_random", 31)
	var b := h.add_bot("Sarah", "fast_random", 32)
	var c := h.add_bot("Claire", "fast_random", 33)
	a.auto_start_at_count = 3
	check(h.run_until(func(): return c.last_screen.get("screen") == "question", 200.0), "question reached")
	h.disconnect_bot(c)
	check(h.run_until(func(): return h.events_of("player_dropped").size() == 1, 40.0 / SCALE + 1.0), "player dropped after 30s window")
	check(h.events_of("say").filter(func(e): return e.category == "reconnect_mid").size() == 1, "Graham calls out at ~15s")
	check(h.events_of("say").filter(func(e): return e.category == "reconnect_failed").size() == 1, "Graham comments on failure to return")
	check_eq(h.session.hold_reason, "", "show continues with two remaining")
	check(h.run_until(_ended(h), 400.0), "show completes")


func test_all_disconnect_ends_transmission() -> void:
	var h := _harness("allgone")
	var a := h.add_bot("Aaron", "fast_random", 41)
	var b := h.add_bot("Sarah", "fast_random", 42)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return h.session.phase == SessionServer.Phase.SHOW, 20.0), "show started")
	h.run_until(func(): return false, 2.0)
	h.disconnect_bot(a)
	h.run_until(func(): return false, 5.0 / SCALE)
	h.disconnect_bot(b)
	check(h.run_until(func(): return h.session.phase == SessionServer.Phase.CLOSED, 45.0 / SCALE + 1.0), "session closed after everyone failed to return")
	check(h.events_of("all_gone").size() == 1, "all_gone emitted once")
	check(h.events_of("say").filter(func(e): return e.category == "all_gone").size() == 1, "Graham visibly annoyed line")
	check_eq(h.session.director.graham_mood, "angry", "Graham angry")
	var dropped := h.events_of("player_dropped")
	check_eq(dropped.size(), 2, "each player got their full window before the session ended")
	var closed_at: float = h.events_of("session_closed")[0].st
	var first_drop: float = dropped[0].st
	check(closed_at - first_drop >= 4.0, "session did not end at the first player's window (%.1fs later)" % (closed_at - first_drop))


func test_one_remaining_holds_until_join() -> void:
	var h := _harness("one_left")
	var a := h.add_bot("Aaron", "fast_random", 51)
	var b := h.add_bot("Sarah", "fast_random", 52)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return h.session.phase == SessionServer.Phase.SHOW, 20.0), "show started")
	h.disconnect_bot(b)
	check(h.run_until(func(): return h.session.hold_reason == "players", 40.0 / SCALE + 1.0), "held for players after drop")
	var seg_elapsed: float = h.session._current.elapsed
	h.run_until(func(): return false, 3.0)
	check_eq(h.session._current.elapsed, seg_elapsed, "no progress while one player remains")
	var c := h.add_bot("Claire", "fast_random", 53)
	check(h.run_until(func(): return h.session.hold_reason == "", 5.0), "hold resolves when a new player joins")
	check(h.session.players[c.player_id].status == PlayerState.Status.ACTIVE, "new player active immediately")
	check(h.run_until(_ended(h), 400.0), "show completes")


func test_late_join_waits_for_boundary() -> void:
	var h := _harness("late")
	var a := h.add_bot("Aaron", "fast_random", 61)
	var b := h.add_bot("Sarah", "fast_random", 62)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return a.last_screen.get("screen") == "question", 200.0), "question reached")
	var c := h.add_bot("Claire", "fast_random", 63)
	h.run_until(func(): return c.player_id != "", 5.0)
	var pc: PlayerState = h.session.players[c.player_id]
	check_eq(pc.status, PlayerState.Status.WAITING, "late joiner waits")
	check_eq(c.last_screen.get("screen"), "spectator", "late joiner sees spectator screen")
	check(h.events_of("say").filter(func(e): return e.category == "late_join").size() == 1, "Graham notes lateness")
	check(not c.screens_seen.has("question"), "late joiner never injected mid-game")
	check(h.run_until(func(): return pc.status == PlayerState.Status.ACTIVE, 300.0), "late joiner integrated at a game boundary")
	var q_count_at_integration := h.events_of("question_show").filter(func(e): return str(e.get("game_id", "")) == "studio_rehearsal").size()
	check_eq(q_count_at_integration, h.session.cfg.i("show.warmup_questions", 2), "integrated only after the rehearsal warm-up finished")
	check_eq(h.events_of("hole_round").size(), 0, "...and before the next game began")
	check(h.run_until(_ended(h), 300.0), "show completes")


func test_duplicate_active_name_rejected() -> void:
	var h := _harness("dupe")
	var a := h.add_bot("Stacy", "fast_random", 71)
	h.run_until(func(): return a.player_id != "", 5.0)
	var b := h.add_bot("  stacy ", "fast_random", 72)
	h.run_until(func(): return not b.errors_received.is_empty(), 5.0)
	check(b.errors_received.has(Protocol.E_NAME_TAKEN), "case/space-insensitive duplicate rejected: %s" % [b.errors_received])


func test_returning_profile_flow_and_persistence() -> void:
	var store := temp_store("profiles")
	var c := cfg()
	var s := SessionServer.new(c, store, content(), 5)
	s.time_scale = SCALE
	var inbox := {}
	s.send.connect(func(cid, m):
		if not inbox.has(cid): inbox[cid] = []
		inbox[cid].append(m))
	s.open()
	# A real (non-fake) phone creates Stacy.
	var c1 := s.connect_client({"transport": "ws"})
	s.receive_text(c1, JSON.stringify({"t": "hello", "v": 1, "room": s.room_code.to_lower()}))
	check_eq(inbox[c1][0].t, "welcome", "room code accepted case-insensitively")
	s.receive_text(c1, JSON.stringify({"t": "check_name", "name": "Stacy"}))
	check(inbox[c1].back().ok, "fresh name ok")
	s.receive_text(c1, JSON.stringify({"t": "create_profile", "name": "Stacy", "speech": "Stay see", "avatar": {"hair": 99, "glasses": 1}}))
	var joined = inbox[c1].filter(func(m): return m.t == "joined")
	check_eq(joined.size(), 1, "Stacy joined")
	check_eq(store.profiles.size(), 1, "profile persisted")
	var prof: Dictionary = store.profiles.values()[0]
	check_eq(prof.speech_name, "Stay see", "pronunciation form stored separately")
	check_eq(int(prof.avatar.hair), 5, "avatar values clamped server-side")
	# Stacy leaves; a new person types 'stacy'.
	s.receive_text(c1, JSON.stringify({"t": "leave"}))
	var c2 := s.connect_client({"transport": "ws"})
	s.receive_text(c2, JSON.stringify({"t": "hello", "v": 1, "key": s.join_key}))
	var welcome: Dictionary = inbox[c2][0]
	check_eq(welcome.profiles.size(), 1, "inactive returning profile offered")
	s.receive_text(c2, JSON.stringify({"t": "check_name", "name": "stacy"}))
	check_eq(inbox[c2].back().code, "match_profile", "name matches inactive profile -> ask, never auto-merge")
	s.receive_text(c2, JSON.stringify({"t": "create_profile", "name": "stacy"}))
	check_eq(inbox[c2].back().code, Protocol.E_NAME_TAKEN, "must disambiguate or claim")
	s.receive_text(c2, JSON.stringify({"t": "create_profile", "name": "Stacy B"}))
	check_eq(store.profiles.size(), 2, "distinguishable new profile created")
	# Third phone claims the original Stacy.
	var c3 := s.connect_client({"transport": "ws"})
	s.receive_text(c3, JSON.stringify({"t": "hello", "v": 1, "key": s.join_key}))
	s.receive_text(c3, JSON.stringify({"t": "create_profile", "name": "STACY", "claim": prof.profile_id}))
	var j3 = inbox[c3].filter(func(m): return m.t == "joined")
	check_eq(j3.size(), 1, "claim associates with the returning profile")
	var p3: PlayerState = s.players[j3[0].player_id]
	check_eq(p3.profile_id, prof.profile_id, "same profile id")
	# Reload from disk.
	var reloaded := SaveStore.new(store.base_dir)
	reloaded.load_all()
	check_eq(reloaded.profiles.size(), 2, "profiles reload from disk")


func test_manual_pause_freezes_show() -> void:
	var h := _harness("pause")
	var a := h.add_bot("Aaron", "afk", 81)
	var b := h.add_bot("Sarah", "afk", 82)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return a.last_screen.get("screen") == "question", 200.0), "question reached")
	h.session.set_manual_pause(true)
	h.step()
	check_eq(h.session.hold_reason, "manual", "manual pause holds")
	var e: float = h.session._current.elapsed
	h.run_until(func(): return false, 5.0)
	check_eq(h.session._current.elapsed, e, "segment frozen while paused")
	h.session.set_manual_pause(false)
	h.step()
	check(h.session._current.elapsed > e, "resumes after unpause")


func test_silent_players_never_deadlock() -> void:
	var h := _harness("afk")
	var a := h.add_bot("Aaron", "afk", 91)
	var b := h.add_bot("Sarah", "afk", 92)
	a.auto_start_at_count = 2
	check(h.run_until(_ended(h), 400.0), "show with two silent players still completes (timers resolve)")
	for s in h.session.standings():
		check_eq(int(s.score), 0, "no points for no answers")
	check(h.events_of("say").filter(func(e): return e.category == "nobody_answered").size() >= 1, "Graham notices nobody answered")


func test_scoring_bounds_and_speed_bonus() -> void:
	var h := _harness("score")
	var a := h.add_bot("Aaron", "afk", 101)
	var b := h.add_bot("Sarah", "afk", 102)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return a.last_screen.get("screen") == "question", 200.0), "question reached")
	var qid: String = a.last_screen.data.qid
	var correct := h.correct_index(qid, a.last_screen.data.options)
	h.send_raw(a, JSON.stringify({"t": "answer", "q": qid, "c": correct}))
	h.send_raw(b, JSON.stringify({"t": "answer", "q": qid, "c": (correct + 1) % 4}))
	check(h.run_until(func(): return h.events_of("reveal").size() == 1, 30.0), "reveal")
	var deltas: Dictionary = h.events_of("reveal")[0].deltas
	check(int(deltas[a.player_id]) >= 1000 and int(deltas[a.player_id]) <= 1150, "fast correct = 1000 + capped bonus (got %s)" % deltas[a.player_id])
	check_eq(int(deltas[b.player_id]), 0, "wrong answer = 0, not negative")
