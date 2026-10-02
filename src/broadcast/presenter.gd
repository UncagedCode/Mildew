class_name Presenter
extends Node
## Broadcast client (docs/06 layer 1): turns authoritative session events into television —
## camera cuts, Graham's visible performance, graphics, audio and voice. Holds no game
## authority; it only renders what the SessionServer decided.

var host: MildewHost
var studio: StudioSet
var gfx: GraphicsLayer
var sys: SystemLayer
var audio: AudioDesk
var voice: VoiceService
var view: ProgrammeView
var hole: HoleBoard

var _sync_timer := 0.0
var _game_title := ""
var _in_question := false
var _say_cam_cooldown := 0.0
var _rng := RandomNumberGenerator.new()


func attach(p_host: MildewHost) -> void:
	host = p_host
	host.tv_event.connect(_on_event)
	_rng.randomize()


func _process(delta: float) -> void:
	if host == null or host.session == null:
		return
	_say_cam_cooldown -= delta
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 0.25
		var snap := host.session.tv_snapshot()
		var plist: Array = snap.players
		studio.sync_podiums(plist.filter(func(p): return p.status in ["active", "waiting"]))
		var pmap := {}
		for p in plist:
			pmap[p.pid] = p
		gfx.players = pmap
		if hole:
			hole.players = pmap
		sys.contestants = plist.filter(func(p): return p.status == "active" and p.connected).size()
		studio.graham.set_pressure(host.session.director.pressure)
		if not studio.graham.is_speaking():
			studio.graham.set_mood(host.session.director.graham_mood)


func _say_ctx_name(evt: Dictionary) -> String:
	return str(evt.get("text", ""))


func _on_event(evt: Dictionary) -> void:
	match str(evt.get("e")):
		"lobby_open":
			_lobby()
		"say":
			_say(evt)
		"incident":
			_incident(evt)
		"player_joined":
			audio.applause("small")
			var info: Dictionary = evt.get("info", {})
			if host.session.phase == SessionServer.Phase.LOBBY:
				gfx.show_lower_third(str(info.get("name", "")), "CONTESTANT No. %d" % int(info.get("number", 0)), 3.5)
		"show_start":
			audio.stop_music()
			sys.join_target = 0.0
			sys.late_hint = true
			view.set_layout("full")
			gfx.menu_items = []
		"opening_titles":
			studio.play_titles(float(evt.duration) / maxf(host.session.time_scale, 0.001))
			audio.play("theme_opening")
			gfx.dog_visible = false
		"segment":
			gfx.dog_visible = true
			if str(evt.kind) != "hole_round" and hole and hole.is_showing():
				hole.hide_board()
				_in_question = false
			if str(evt.kind) == "intros":
				audio.applause("medium")
				studio.cut_to("cam2", false)
		"camera":
			studio.cut_to(str(evt.cam))
		"intro_player":
			studio.frame_podium(str(evt.pid))
			var p: Dictionary = gfx.players.get(str(evt.pid), {})
			gfx.show_lower_third(str(p.get("name", "")), ("RETURNING CONTESTANT" if p.get("returning", false) else "CONTESTANT No. %d" % int(evt.number)), 3.2)
			audio.applause("small")
		"sting":
			_game_title = str(evt.title)
			var style := str(evt.get("style", ""))
			gfx.play_sting(_game_title, float(evt.duration) / maxf(host.session.time_scale, 0.001), style)
			if style == "hole":
				audio.play("sting_hole")
				get_tree().create_timer(1.36 / maxf(1.0, host.session.time_scale)).timeout.connect(func(): audio.applause("medium"))
			else:
				audio.play("sting_game")
				audio.play("whoosh", -6.0)
		# ---------------- HOLE ----------------
		"hole_round":
			_in_question = false
			hole.prepare_round(evt)
			for pid in studio.podiums.keys():
				studio.light_podium(pid, false)
			studio.cut_to("cam1")
		"hole_stage":
			_in_question = true
			hole.set_stage(evt)
			if int(evt.stage) == 1:
				audio.play("whoosh", -4.0)
				studio.graham.set_activity("reading")
			else:
				audio.play("zoom_servo", -6.0)
			if evt.get("safety_net", false):
				audio.play("whoosh", -6.0)
		"hole_lock":
			hole.add_lock(str(evt.pid), int(evt.stage), int(evt.of))
			studio.light_podium(str(evt.pid), true)
			audio.play("lock", -6.0)
			if int(evt.stage) == 1:
				audio.crowd("ooh", -10.0)   # somebody's gambling on a glimpse
		"hole_closed":
			hole.close_locks()
			studio.graham.set_activity("idle")
		"hole_reveal":
			hole.reveal(evt)
			_hole_reaction(evt)
		"question_show":
			_in_question = true
			for pid in studio.podiums.keys():
				studio.light_podium(pid, false)
			gfx.show_question(_game_title if _game_title != "" else "MILDEW", str(evt.prompt), evt.options)
			gfx.set_answered(0, host.session.active_player_ids().size())
			audio.play("whoosh", -4.0)
			studio.cut_to("cam2")
			studio.graham.set_activity("reading")
		"question_open":
			gfx.start_timer(float(evt.window) / maxf(host.session.time_scale, 0.001))
			studio.graham.set_activity("idle")
		"answer_in":
			gfx.set_answered(int(evt.count), int(evt.of))
			studio.light_podium(str(evt.pid), true)
			audio.play("lock", -6.0)
		"question_locked":
			gfx.stop_timer()
		"reveal":
			gfx.reveal(int(evt.correct), evt.get("picks", {}))
			var deltas: Dictionary = evt.get("deltas", {})
			var right := 0
			for pid in deltas.keys():
				if int(deltas[pid]) > 0:
					right += 1
					studio.flash_podium(pid, "+%s" % PodiumScreen._fmt(int(deltas[pid])))
			audio.play("correct" if right > 0 else "wrong")
			if right == 0:
				pass  # deliberate silence from the audience
			elif right == deltas.size():
				audio.applause("medium")
			else:
				audio.applause("small")
			get_tree().create_timer(4.5 / maxf(1.0, host.session.time_scale * 0.5)).timeout.connect(func():
				if host.session and host.session.phase == SessionServer.Phase.SHOW and gfx.is_question_visible():
					gfx.hide_question())
		"segment_question_end":
			gfx.hide_question()
		"scores":
			gfx.hide_question()
			_in_question = false
			var st: Array = evt.standings
			gfx.show_scores(st, "THE SCORES")
			audio.play("whoosh", -4.0)
			studio.cut_to("cam2")
		"winner":
			gfx.hide_scores()
			studio.frame_podium(str(evt.pid))
			gfx.confetti()
			audio.applause("big")
		"sign_off":
			gfx.hide_scores()
			studio.cut_to("cam2")
			audio.play("theme_opening", -6.0)
		"show_ended":
			gfx.hide_question()
			gfx.hide_scores()
			gfx.show_slate("END OF TRANSMISSION", "THE FLOOR CAPTAIN MAY REQUEST ANOTHER BROADCAST")
			sys.late_hint = false
		"hold":
			sys.hold_reason = str(evt.reason)
			sys.hold_detail = evt.get("detail", {})
			sys.hold_since = sys._t
			if evt.reason == "reconnect" or evt.reason == "players":
				studio.graham.set_activity("waiting")
				audio.duck(true)
			elif evt.reason == "":
				studio.graham.set_activity("idle")
				audio.duck(false)
		"player_lost":
			studio.cut_to("cam1")
		"player_back":
			audio.applause("small")
		"player_dropped":
			pass
		"all_gone":
			studio.graham.set_mood("angry")
			studio.cut_to("cam1", false)
		"session_closed":
			gfx.show_slate("END OF TRANSMISSION", "")
			sys.hold_reason = ""


## Audience + podium response to a Hole reveal; then cut back to Graham for his verdict.
func _hole_reaction(evt: Dictionary) -> void:
	var outcome: Dictionary = evt.get("outcome", {})
	var right := 0
	var first_glance := 0
	var locked := 0
	for pid in outcome.keys():
		var o: Dictionary = outcome[pid]
		if str(o.get("label", "")) != "":
			locked += 1
		if o.get("correct", false):
			right += 1
			if int(o.get("stage", 0)) == 1:
				first_glance += 1
		if int(o.get("points", 0)) > 0:
			studio.flash_podium(pid, "+%s" % PodiumScreen._fmt(int(o.points)))
	var scale := maxf(1.0, host.session.time_scale)
	get_tree().create_timer(0.9 / scale).timeout.connect(func():
		if evt.get("studio_hole", false):
			audio.silence_audience()   # nobody claps for that
			return
		audio.play("correct" if right > 0 else "wrong")
		if first_glance > 0:
			audio.crowd("ooh")
			audio.applause("medium")
		elif right == 0 and locked > 0:
			audio.crowd("aww")
		elif right == 0:
			pass  # deliberate silence
		elif right == outcome.size():
			audio.applause("medium")
		else:
			audio.applause("small"))
	var crowd_cam := ""
	if not evt.get("studio_hole", false):
		if first_glance > 0 or (right > 0 and right == outcome.size()):
			crowd_cam = "cam_audience" if _rng.randf() < 0.45 else ""
		elif right == 0:
			crowd_cam = "cam_audience_meh" if _rng.randf() < 0.5 else ""
	get_tree().create_timer(4.2 / scale).timeout.connect(func():
		if host.session and host.session.phase == SessionServer.Phase.SHOW and hole.is_showing():
			hole.hide_board()
			_in_question = false
			if crowd_cam != "" and _audience_cutaway(crowd_cam, 1.4 / scale):
				return
			studio.cut_to("cam1"))


func _lobby() -> void:
	if hole:
		hole.hide_board()
	gfx.hide_slate()
	gfx.hide_scores()
	gfx.hide_question()
	_game_title = ""
	view.set_layout("lobby")
	sys.join_target = 1.0
	sys.late_hint = false
	sys.set_join(host.join_url, host.short_url, host.session.room_code)
	sys.dev_hint = ("DEV PANEL  %s/dev  PIN %s" % [host.short_url.replace("http://", ""), host.dev_pin]) if host.dev_enabled else ""
	studio.cut_to("cam2", false)
	studio.graham.set_activity("waiting")
	audio.music("lobby_bed", -10.0)


func _say(evt: Dictionary) -> void:
	var speaker := str(evt.get("speaker", "graham"))
	var text := str(evt.get("text", ""))
	var dur := float(evt.get("duration", 2.0))
	var sub_speaker := "test" if evt.get("pronunciation_test", false) else speaker
	var spoken: Dictionary = voice.speak(speaker, str(evt.get("speech", text)), evt) if voice else {}
	if not evt.get("silent", false):
		var shown := text
		if speaker == "announcer":
			shown = "ANNOUNCER: " + text
		elif speaker == "floor":
			shown = "(OFF MIC) " + text
		elif str(spoken.get("mode", "")) == "dev_tts":
			shown = "[DEV TTS] " + text      # developer fallback must be obvious (D024)
		# An authored clip may run longer than the estimated reading time.
		dur = maxf(dur, float(spoken.get("seconds", -1.0)) + 0.4)
		gfx.show_subtitle(shown, sub_speaker, dur)
	if speaker != "graham":
		return
	_shot_graham_line(evt, dur)


# ---------------------------------------------------------------------------
# Graham editing grammar (D021/D022; pack GRAHAM_PERFORMANCE_AND_EDITING_RULES):
# a line starts on Graham (Camera 1) in the state its category calls for; long lines cut away to
# the contestant / wide / podiums while the voice continues; sometimes we come back for a reaction.
# If a game graphic owns the frame, the voice simply plays over it.
# ---------------------------------------------------------------------------

var _shots := {}
var _shot_seq := 0


func _shot_hint(category: String) -> Dictionary:
	if _shots.is_empty():
		var f := FileAccess.open("res://config/graham_shots.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_shots = d
	var h: Dictionary = (_shots.get("default", {}) as Dictionary).duplicate()
	h.merge(_shots.get(category, {}), true)
	return h


func _shot_graham_line(evt: Dictionary, dur: float) -> void:
	var g = studio.graham
	var cat := str(evt.get("category", ""))
	var hint := _shot_hint(cat)
	g.set_mood(str(evt.get("mood", "relaxed")))
	if evt.get("silent", false):
		g.set_state("stare", "cut")
		if host.session.phase != SessionServer.Phase.LOBBY and not _graphic_owns_frame():
			studio.cut_to("cam1", false)
		return
	var lead := str(hint.get("lead", ""))
	var settle := str(hint.get("settle", ""))
	if _graphic_owns_frame() or studio.current_cam in ["cam_titles", "cam_ident"]:
		# Voice over the graphic; quietly put Graham in the right state for when we come back.
		if lead != "":
			g.set_state(lead, "cut")
		elif settle != "":
			g.set_state(settle, "cut")
		return
	if host.session.phase == SessionServer.Phase.LOBBY:
		# Lobby monitor: Graham chatting to the room; keep him on camera, mouth moving briefly.
		if studio.current_cam != "cam1" and _rng.randf() < 0.6:
			studio.cut_to("cam1", false)
		g.speak(dur, settle)
		return
	_shot_seq += 1
	var seq := _shot_seq
	var scale := maxf(1.0, host.session.time_scale)
	if studio.current_cam != "cam1" and studio.current_cam != "cam_podium":
		studio.cut_to("cam1")
	elif studio.current_cam == "cam_podium" and _say_cam_cooldown <= 0.0:
		studio.cut_to("cam1")
	if lead != "":
		g.set_state(lead, "cut")
	var visible_for := dur
	if bool(hint.get("talk", true)):
		visible_for = g.speak(dur, settle)
	else:
		visible_for = minf(dur, _rng.randf_range(0.9, 1.8))
		if settle != "":
			get_tree().create_timer(maxf(0.2, dur) / scale).timeout.connect(func(): g.set_state(settle, "auto"))
	var cutaways: Array = hint.get("cutaway", [])
	if dur > visible_for + 0.6 and not cutaways.is_empty():
		var target := str(cutaways[_rng.randi_range(0, cutaways.size() - 1)])
		var pid := str(evt.get("pid", ""))
		get_tree().create_timer(visible_for / scale).timeout.connect(func():
			if seq != _shot_seq or _graphic_owns_frame():
				return
			if target == "subject" and pid != "" and studio.podiums.has(pid):
				studio.frame_podium(pid)
			elif target != "subject":
				studio.cut_to(target)
			else:
				studio.cut_to("cam2"))
		var back := float(hint.get("return", 0.35))
		if _rng.randf() < back:
			get_tree().create_timer((dur + 0.35) / scale).timeout.connect(func():
				if seq != _shot_seq or _graphic_owns_frame():
					return
				g.set_state(settle if settle != "" else ("reading_cards" if _rng.randf() < 0.4 else "restrained_smile"), "cut")
				studio.cut_to("cam1", false))
	_say_cam_cooldown = 1.5


# ---------------------------------------------------------------------------
# Broadcast irregularities (Tier 0/1). Presentation only; never touches real status UI (D006)
# and never covers an active question/timer (docs/01 #97).
# ---------------------------------------------------------------------------

func _incident(evt: Dictionary) -> void:
	var p: Dictionary = evt.get("params", {})
	var dur := float(evt.get("duration", 1.5))
	var g = studio.graham
	var back := studio.current_cam if studio.current_cam in ["cam1", "cam2", "cam3", "cam4"] else "cam1"
	var later := func(t: float, f: Callable): get_tree().create_timer(t).timeout.connect(f)
	match str(evt.get("effect")):
		"mic_pop":
			audio.play("mic_pop", -2.0)
		"feedback":
			audio.play("feedback", -12.0)
		"lower_third_typo":
			gfx.show_lower_third(str(p.get("typo", "")), "CONTESTANT No. %d" % int(p.get("number", 0)), dur * 0.45)
			later.call(dur * 0.45, func(): gfx.show_lower_third(str(p.get("name", "")), "CONTESTANT No. %d" % int(p.get("number", 0)), dur * 0.55))
		"early_applause":
			audio.applause("small")
			later.call(0.7, func(): audio.silence_audience())
		"late_cut":
			if not _graphic_owns_frame():
				studio._do_cut("cam4")
				later.call(minf(0.7, dur), func(): studio._do_cut(back))
		"wrong_camera":
			if not _graphic_owns_frame():
				studio._do_cut("cam1")
				g.set_state("look_off_left", "cut")
		"signal_tear":
			gfx.signal_tear(minf(0.6, dur))
			audio.play("static_burst", -14.0)
		"empty_corridor":
			if not _graphic_owns_frame():
				studio._do_cut("cam_corridor")
				later.call(dur, func(): studio._do_cut(back))
		"hole_doorway":
			if not _graphic_owns_frame():
				studio._do_cut("cam_doorway")
				audio.duck(true)
				later.call(dur, func():
					audio.duck(false)
					g.set_state("irritated_turn", "cut")
					studio._do_cut("cam1"))
		"production_caption":
			gfx.production_caption(str(p.get("caption", "")), dur)
		"wrong_audience_reaction":
			audio.applause("big")
		"floor_shot":
			if not _graphic_owns_frame():
				studio._do_cut("cam_floor")
				later.call(dur, func(): studio._do_cut(back))
		"off_mic_cue", "wrong_name":
			pass  # carried by the line itself


## Audience reaction cutaway (photographic plate only), then back to Graham. False if unavailable.
func _audience_cutaway(cam: String, seconds: float) -> bool:
	if view == null or view.plates == null or view.plates.plate_for_camera(cam) == "":
		return false
	studio._do_cut(cam)
	get_tree().create_timer(seconds).timeout.connect(func():
		if studio.current_cam == cam:
			studio.cut_to("cam1", false))
	return true


func _graphic_owns_frame() -> bool:
	return _in_question or (hole != null and hole.is_showing()) or gfx.is_question_visible()
