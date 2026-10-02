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
			gfx.play_sting(_game_title, float(evt.duration) / maxf(host.session.time_scale, 0.001))
			audio.play("sting_game")
			audio.play("whoosh", -6.0)
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


func _lobby() -> void:
	gfx.hide_slate()
	gfx.hide_scores()
	gfx.hide_question()
	_game_title = ""
	view.set_layout("lobby")
	sys.join_target = 1.0
	sys.late_hint = false
	sys.set_join(host.join_url, host.short_url, host.session.room_code)
	studio.cut_to("cam2", false)
	studio.graham.set_activity("waiting")
	audio.music("lobby_bed", -10.0)


func _say(evt: Dictionary) -> void:
	var speaker := str(evt.get("speaker", "graham"))
	var text := str(evt.get("text", ""))
	var dur := float(evt.get("duration", 2.0))
	var sub_speaker := "test" if evt.get("pronunciation_test", false) else speaker
	if not evt.get("silent", false):
		gfx.show_subtitle(text if speaker == "graham" else "ANNOUNCER: " + text, sub_speaker, dur)
	voice.speak(speaker, str(evt.get("speech", text)), evt)
	if speaker == "graham":
		studio.graham.set_mood(str(evt.get("mood", "relaxed")))
		if evt.get("silent", false):
			studio.graham.set_activity("stare")
		else:
			studio.graham.speak(dur)
		# Ordinary grammar: talking Graham is usually on Cam 1, unless graphics own the frame.
		if not _in_question and _say_cam_cooldown <= 0.0 and host.session.phase != SessionServer.Phase.LOBBY:
			if studio.current_cam != "cam_titles" and studio.current_cam != "cam_podium":
				studio.cut_to("cam1" if _rng.randf() < 0.85 else "cam2")
				_say_cam_cooldown = 2.5
		elif host.session.phase == SessionServer.Phase.LOBBY and _rng.randf() < 0.5:
			studio.cut_to("cam1" if studio.current_cam != "cam1" else "cam2")
