extends MildewTest
## Graham local authored voice (D024; tools/graham_factory/CLAUDE_INTEGRATION.md):
## index, name bank, local playback API, graceful missing clips, no TTS in release,
## dedicated bus, subtitle == recording, Director preference, pronunciation via the name bank.

const TONE_A := "res://tests/fixtures/voice/tone_a.wav"
const TONE_B := "res://tests/fixtures/voice/tone_b.wav"


func _fixture_index() -> GrahamVoiceIndex:
	var idx := GrahamVoiceIndex.new()
	var real := GrahamVoiceIndex.load_from(GrahamVoiceIndex.DEFAULT_PATH)
	var d := {"clips": real.clips.duplicate(true), "names": {}}
	for k in real.names:
		d.names[k] = real.names[k]
	# Two real ids get local fixture "recordings"; everything else stays missing.
	d.clips["name_aaron"] = {"path": TONE_A, "status": "development", "text": "Aaron.", "mood": "name"}
	d.clips["correct_01"] = {"path": TONE_A, "status": "approved", "text": "That is correct. Well done.", "mood": "pleased"}
	d.clips["closing_01"] = {"path": TONE_A, "status": "development", "text": real.text("closing_01"), "mood": "closing"}
	d.clips["closing_thanks_01"] = {"path": TONE_B, "status": "development", "text": real.text("closing_thanks_01"), "mood": "closing"}
	idx.set_data(d)
	return idx


func _service(idx: GrahamVoiceIndex, dev_build := true, fallback := false) -> GrahamVoiceService:
	var svc := GrahamVoiceService.new()
	svc.index = idx
	svc.dev_build = dev_build
	svc.dev_tts_fallback = fallback
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(svc)
	await tree.process_frame        # playback needs the node inside a running tree
	return svc


func test_index_matches_factory_manifest() -> void:
	var idx := GrahamVoiceIndex.load_from(GrahamVoiceIndex.DEFAULT_PATH)
	var f := FileAccess.open("res://tools/graham_factory/manifest.json", FileAccess.READ)
	check(f != null, "factory manifest readable")
	var man = JSON.parse_string(f.get_as_text())
	for line in man.lines:
		check(idx.has_id(str(line.id)), "index has manifest id %s" % line.id)
		check_eq(idx.text(str(line.id)), str(line.text), "index text for %s matches manifest" % line.id)
		check(GrahamVoiceIndex.STATUSES.has(idx.status(str(line.id))), "status valid for %s" % line.id)
	for n in ["Aaron", "Elijah", "Grace", "Josh", "Donna"]:
		check_eq(idx.name_id(n), "name_" + n.to_lower(), "required name %s in the name bank" % n)
	for id in idx.ids():
		check(idx.status(id) != "approved" or idx.has_clip(id), "approved clip %s really exists" % id)


func test_name_lookup_is_case_insensitive_and_tolerant() -> void:
	var idx := GrahamVoiceIndex.load_from(GrahamVoiceIndex.DEFAULT_PATH)
	for v in ["AARON", " aaron ", "Aaron!", "aaron.", "Aaron"]:
		check_eq(idx.name_id(v), "name_aaron", "'%s' -> name_aaron" % v)
	check_eq(idx.name_id("DoNnA"), "name_donna", "mixed case")
	check_eq(idx.name_id("Aaronson"), "", "no partial matches")
	check_eq(idx.name_id("-Aaron"), "", "a rejected pronunciation never matches a recording")
	check_eq(idx.name_id(""), "", "empty")


func test_playback_api_and_sequences() -> void:
	var svc : GrahamVoiceService = await _service(_fixture_index())
	var started: Array = []
	svc.line_started.connect(func(id): started.append(id))
	var secs := svc.say("correct_01")
	check(secs > 0.5 and secs < 0.7, "say() returns the clip length (%.2f)" % secs)
	check(svc.is_speaking(), "playing asynchronously (call returned immediately)")
	check_eq(started, ["correct_01"], "line_started emitted")
	check(svc.say_name("AARON") > 0.0, "say_name plays name_aaron")
	check_eq(svc.current(), "name_aaron", "new line interrupts the old one")
	var seq := svc.say_sequence(["closing_01", "closing_thanks_01"])
	check(seq > 0.95 and seq < 1.05, "sequence length is the sum (%.2f)" % seq)
	check_eq(svc._queue, ["closing_thanks_01"], "second clip queued behind the first")
	var r := svc.play_line({"text": "x", "speech": "x", "audio": ["closing_01", "closing_thanks_01"]})
	check_eq(r.mode, "clip", "line with an audio sequence plays clips")
	var r2 := svc.play_line({"text": "Aaron. Lovely to have you.", "speech": "Aaron. Lovely to have you.", "voice_name": "Aaron"})
	check_eq(r2.mode, "name", "name-led line speaks the recorded name")
	svc.stop()
	check(not svc.is_speaking(), "stop()")
	svc.queue_free()


func test_missing_clips_fail_gracefully_and_never_use_tts_in_release() -> void:
	var idx := _fixture_index()
	var dev : GrahamVoiceService = await _service(idx, true, false)
	var missing: Array = []
	dev.clip_missing.connect(func(id): missing.append(id))
	check_eq(dev.say("wrong_01"), -1.0, "missing clip returns -1")
	check(missing.has("wrong_01"), "clip_missing signalled")
	check_eq(dev.say("no_such_id"), -1.0, "unknown id returns -1")
	check_eq(dev.say_name("Zebedee"), -1.0, "unknown name returns -1")
	check(not dev.is_speaking(), "nothing plays")
	check_eq(dev.play_line({"text": "Hello.", "speech": "Hello.", "audio": "wrong_01"}).mode, "silent", "unrecorded line is silent (subtitles only)")
	check_eq(dev.say_sequence(["closing_01", "wrong_01"]), -1.0, "a sequence with a gap plays nothing")
	var rel : GrahamVoiceService = await _service(idx, false, true)   # release build, even with the setting on
	rel.say("wrong_01")
	rel.say_name("Zebedee")
	rel.play_line({"text": "Hello.", "speech": "Hello."})
	check_eq(rel.fallback_count, 0, "release builds never reach system TTS")
	check(rel.last_mode != "dev_tts", "release mode never reports dev_tts")
	dev.queue_free()
	rel.queue_free()


func test_intents_resolve_to_known_ids() -> void:
	var svc : GrahamVoiceService = await _service(_fixture_index())
	check(not svc.intents.is_empty(), "intents loaded")
	for k in svc.intents:
		if str(k).begins_with("_"):
			continue
		for o in svc.intents[k]:
			for id in o.get("sequence", [o.get("id", "")]):
				check(svc.index.has_id(str(id)), "intent %s -> known id %s" % [k, id])
	check(svc.say_intent("correct_answer", {"mood": "pleased"}) > 0.0, "intent plays an available clip")
	check(svc.say_intent("sign_off") < 0.0, "intent whose sequence is incomplete does not play")
	check_eq(svc.say_intent("not_an_intent"), -1.0, "unknown intent is harmless")
	svc.queue_free()


func test_dedicated_bus_with_broadcast_treatment() -> void:
	GrahamVoiceService.ensure_bus()
	var b := AudioServer.get_bus_index(GrahamVoiceService.BUS)
	check(b != -1, "Graham bus exists")
	check(AudioServer.get_bus_effect_count(b) >= 3, "EQ/compression chain on the Graham bus")
	check_eq(str(AudioServer.get_bus_send(b)), "Master", "Graham bus feeds Master")
	var svc : GrahamVoiceService = await _service(_fixture_index())
	check_eq(str(svc._player.bus), GrahamVoiceService.BUS, "Graham plays through his own bus")
	svc.queue_free()


func test_voiced_lines_match_recordings() -> void:
	var v := ContentValidator.new()
	check(v.validate(content()), "content incl. voiced lines validates: %s" % [v.errors])
	var voiced := content().query("graham_lines").filter(func(l): return l.has("audio"))
	check(voiced.size() >= 15, "voiced lines present (%d)" % voiced.size())
	var bad := ContentDB.new()
	bad.add_pack({"pack_id": "bad", "content_kind": "graham_lines", "speaker": "graham", "_path": "bad.json", "items": [
		{"id": "b1", "category": "x", "text": "That is correct. Well done!", "audio": "correct_01", "enabled": true, "quality_status": "draft"},
		{"id": "b2", "category": "x", "text": "Hi.", "audio": "nope_99", "enabled": true, "quality_status": "draft"}]})
	check(not v.validate(bad), "bad voiced lines rejected")
	var j := "\n".join(v.errors)
	check(j.contains("differs from the recorded voice text"), "subtitle/recording mismatch caught")
	check(j.contains("unknown Graham voice id"), "unknown voice id caught")
	v.validate(content(), true)
	check("\n".join(v.warnings).contains("not approved for release"), "release validation reports development/missing clips")


func test_director_prefers_recorded_lines() -> void:
	var d := Director.new(content(), 11)
	d.cfg = cfg()
	d.begin_session({"broadcasts_played": 3}, "standard_transmission")
	var voiced := 0
	var runs := 300
	d.voice = _fixture_index()
	for i in runs:
		d._line_history.clear()
		if str(d.line("graham", "single_correct", {"name": "Sam"}).get("audio", "")) == "correct_01":
			voiced += 1
	var with_clip := float(voiced) / runs
	voiced = 0
	d.voice = GrahamVoiceIndex.load_from(GrahamVoiceIndex.DEFAULT_PATH)
	for i in runs:
		d._line_history.clear()
		if str(d.line("graham", "single_correct", {"name": "Sam"}).get("audio", "")) == "correct_01":
			voiced += 1
	var without := float(voiced) / runs
	check(with_clip > without + 0.15, "recorded line preferred when its clip exists (%.2f vs %.2f)" % [with_clip, without])
	var l := d.line("graham", "intro_player", {"name": "Aaron", "speech_name": "Aaron", "count": 1})
	check(str(l.text).begins_with("Aaron") == (str(l.voice_name) == "Aaron"), "voice_name set exactly for name-led lines")


func test_pronunciation_check_uses_the_name_bank() -> void:
	GrahamVoiceIndex.set_shared(_fixture_index())
	var store := temp_store("voicename")
	var h := SimHarness.new(cfg(), store, content(), 21, 1.0)
	var cid := h.session.connect_client({"transport": "test"})
	h.session.receive_text(cid, JSON.stringify({"t": "hello", "v": 1, "key": h.session.join_key}))
	h.session.receive_text(cid, JSON.stringify({"t": "say_name", "speech": "aaron"}))
	var says := h.events_of("say").filter(func(e): return e.get("pronunciation_test", false))
	check(not says.is_empty(), "pronunciation line emitted")
	if not says.is_empty():
		check_eq(str(says[-1].text), "Aaron.", "subtitle is exactly the recorded name")
		check_eq(str(says[-1].audio), "name_aaron", "name clip requested")
	h.session.session_time += 5.0
	h.session.receive_text(cid, JSON.stringify({"t": "say_name", "speech": "Zebedee"}))
	var says2 := h.events_of("say").filter(func(e): return e.get("pronunciation_test", false))
	check(says2.size() >= 2 and str(says2[-1].get("audio", "")) != "name_aaron", "unknown name does not borrow a recording")
	GrahamVoiceIndex.set_shared(null)
