extends Node
## Mildew application entry.
##   Normal:   SALLOW ident -> MILDEW title menu (remote) -> BEGIN TRANSMISSION -> lobby/show.
##   --mildew-host [--port N --ws-port N --timescale X --save-dir DIR --seed N --bind ADDR]
##             Headless authoritative host (no presentation) for integration tests / dev.
##   --mildew-tour DIR   Scripted run with fake players that captures screenshots.
## Pause / settings / end transmission are always reachable from the remote (BACK / MENU).

var cfg: MildewConfig
var store: SaveStore
var content: ContentDB
var host: MildewHost

var view: ProgrammeView
var sys: SystemLayer
var presenter: Presenter
var audio: AudioDesk
var voice: VoiceService
var dev: DevOverlay

var state := "boot"            # boot ident title viewer settings transmission
var menu_sel := 0
var _pause_open := false
var _pause_mode := "main"      # main settings dev
var _confirm := ""
var _state_t := 0.0
var _args := {}
var dev_build := OS.is_debug_build()


func _ready() -> void:
	_parse_args()
	_register_input()
	cfg = MildewConfig.load_default()
	var save_dir := str(_args.get("save-dir", "user://mildew_save"))
	if _args.has("mildew-tour") and not _args.has("save-dir"):
		save_dir = "user://tour_%d" % Time.get_ticks_usec()   # reproducible: fresh installation
	store = SaveStore.new(save_dir)
	store.load_all()
	content = ContentDB.load_default()
	var v := ContentValidator.new()
	if not v.validate(content):
		push_warning("Content validation errors: %s" % [v.errors])
	host = MildewHost.new()
	host.name = "MildewHost"
	host.setup(cfg, store, content)
	add_child(host)
	if _args.has("mildew-host"):
		_run_headless_host()
		return
	_build_presentation()
	if _args.has("mildew-tour"):
		_run_tour()
		return
	_go("ident")


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k := a[i]
		if k.begins_with("--"):
			var key := k.substr(2)
			if i + 1 < a.size() and not a[i + 1].begins_with("--"):
				_args[key] = a[i + 1]
				i += 1
			else:
				_args[key] = true
		i += 1


func _register_input() -> void:
	var add := func(action: String, keys: Array) -> void:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys:
			var ev := InputEventKey.new()
			ev.keycode = k
			InputMap.action_add_event(action, ev)
	add.call("mildew_pause", [KEY_ESCAPE, KEY_BACK, KEY_MENU, KEY_P])
	add.call("mildew_dev", [KEY_F3])


# ===========================================================================
# Headless host (integration tests)
# ===========================================================================

func _run_headless_host() -> void:
	if _args.has("port"):
		cfg.set_override("network.http_port", int(_args.port))
	if _args.has("ws-port"):
		cfg.set_override("network.ws_port", int(_args["ws-port"]))
	cfg.set_override("network.port_search_span", 1)
	var ok := host.begin(int(_args.get("seed", 0)), str(_args.get("bind", "*")))
	if not ok:
		print("MILDEW_HOST_FAILED ", host.start_error)
		get_tree().quit(2)
		return
	host.session.time_scale = float(_args.get("timescale", 1.0))
	host.tv_event.connect(func(e): print("EVT ", JSON.stringify(e)))
	print("MILDEW_HOST_READY ", JSON.stringify({"http": host.http.port, "ws": host.ws.port, "room": host.session.room_code,
		"key": host.session.join_key, "join_url": host.join_url, "lan": host.lan_ip}))


# ===========================================================================
# Presentation
# ===========================================================================

func _build_presentation() -> void:
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(1920, 1080)
	root.add_child(bg)
	view = ProgrammeView.new()
	root.add_child(view)
	view.build()
	sys = SystemLayer.new()
	root.add_child(sys)
	audio = AudioDesk.new()
	add_child(audio)
	voice = VoiceService.new()
	add_child(voice)
	voice.enabled = bool(store.get_setting("voice", true))
	view.gfx.subtitles_enabled = bool(store.get_setting("subtitles", true))
	presenter = Presenter.new()
	presenter.studio = view.studio
	presenter.gfx = view.gfx
	presenter.sys = sys
	presenter.audio = audio
	presenter.voice = voice
	presenter.view = view
	presenter.hole = view.hole
	add_child(presenter)
	presenter.attach(host)
	dev = DevOverlay.new()
	dev.host = host
	dev.graham = view.graham
	dev.visible = false
	root.add_child(dev)
	get_tree().root.size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	pass  # canvas_items stretch mode scales the 1920x1080 reference to 720p/4K


func _go(s: String) -> void:
	state = s
	_state_t = 0.0
	menu_sel = 0
	_confirm = ""
	match s:
		"ident":
			view.studio.play_ident()
			view.gfx.dog_visible = false
			view.gfx.menu_items = []
			audio.play("ident_sallow")
		"title":
			view.set_layout("full")
			view.gfx.dog_visible = false
			view.gfx.hide_slate()
			view.studio.cut_to("cam_logo", false)
			view.studio.graham.set_activity("idle")
			audio.music("lobby_bed", -12.0)
			_title_menu()
		"viewer":
			_viewer_menu()
		"settings":
			_settings_menu(view.gfx)
		"transmission":
			view.gfx.menu_items = []
			view.gfx.menu_title = ""
			view.gfx.menu_footer = ""
			view.gfx.dog_visible = true


func _title_menu() -> void:
	var g := view.gfx
	g.menu_title = "INTERACTIVE HOME EDITION"
	g.menu_items = [
		{"label": "BEGIN TRANSMISSION", "desc": "Start a broadcast. Contestants join on their phones over this Wi-Fi. No internet required."},
		{"label": "VIEWER INFORMATION", "desc": "The Mildew Viewer Information Service: sources for facts shown on the programme."},
		{"label": "BROADCAST SETTINGS", "desc": "Transmission type, subtitles, presenter voice and reset options."},
	]
	if dev_build:
		g.menu_items.append({"label": "DEVELOPER DIAGNOSTICS", "desc": "Development build only: network/Director overlay (F3)."})
	g.menu_selected = menu_sel
	g.menu_footer = "USE THE ARROWS AND OK ON YOUR REMOTE"


func _viewer_menu() -> void:
	var g := view.gfx
	g.menu_title = "VIEWER INFORMATION SERVICE"
	g.menu_items = _viewer_items()
	g.menu_selected = menu_sel
	g.menu_footer = "MILDEW VIEWER INFORMATION SERVICE · P.O. BOX 1998"


## Viewer Information Service: legitimate sources only (never incidents). CP2: picture credits for
## the real photographs used in HOLE, straight from each item's media metadata.
func _viewer_items() -> Array:
	var items: Array = [{"label": "BACK", "desc": "Facts and pictures used on the programme, with their sources. Scroll for picture credits."}]
	for it in content.query("hole", "", 5, 0):
		var media: Array = it.get("media", [])
		if media.is_empty() or str(media[0].get("source", "")) != "Wikimedia Commons":
			continue
		var m: Dictionary = media[0]
		items.append({"label": "PICTURE: " + str(it.get("answer", "")).to_upper(),
			"desc": "Photograph: %s. Licence: %s. Via Wikimedia Commons. Cropped and resized. %s" % [m.get("creator", "Unknown"), m.get("licence", ""), str(m.get("source_page", "")).uri_decode()]})
	return items


func _settings_items() -> Array:
	var inter := str(store.get_setting("interference", "standard_transmission"))
	var labels := {"standard_transmission": "STANDARD TRANSMISSION", "supervised_transmission": "SUPERVISED TRANSMISSION", "clean_transmission": "CLEAN TRANSMISSION"}
	var items := [
		{"key": "interference", "label": "TRANSMISSION", "value": labels.get(inter, inter),
			"desc": "Controls unexpected fictional broadcast interruptions, unusual controller messages and unsettling audiovisual events. Standard is the intended experience; Supervised reduces them; Clean suppresses them where possible. Real connection problems are always shown plainly."},
		{"key": "subtitles", "label": "SUBTITLES", "value": "ON" if store.get_setting("subtitles", true) else "OFF", "desc": "Teletext-style subtitles for the presenter and announcer."},
		{"key": "voice", "label": "PRESENTER VOICE", "value": "ON" if store.get_setting("voice", true) else "OFF", "desc": "Uses this device's offline text-to-speech: " + (voice.describe() if voice else "n/a")},
		{"key": "reset_players", "label": "RESET PLAYERS", "desc": "Deletes all contestant profiles on this television. Broadcast history is kept."},
		{"key": "reset_history", "label": "RESET BROADCAST HISTORY", "desc": "Clears what this installation has seen (familiarity, history). Contestant profiles are kept."},
		{"key": "reset_all", "label": "RESET MILDEW", "desc": "Erases everything: profiles, history and the installation itself. Cannot be undone."},
		{"key": "back", "label": "BACK", "desc": ""},
	]
	if _confirm != "":
		for it in items:
			if it.key == _confirm:
				it.label = "PRESS OK AGAIN TO CONFIRM"
	return items


func _settings_menu(target) -> void:
	var items := _settings_items()
	if target is GraphicsLayer:
		target.menu_title = "BROADCAST SETTINGS"
		target.menu_items = items
		target.menu_selected = menu_sel
		target.menu_footer = "◀ ▶ CHANGE · OK SELECT · BACK RETURN"
	else:
		target.pause_title = "BROADCAST SETTINGS"
		target.pause_items = items
		target.pause_selected = menu_sel


func _apply_setting(key: String, dir: int) -> bool:
	match key:
		"interference":
			var order := ["standard_transmission", "supervised_transmission", "clean_transmission"]
			var cur := order.find(str(store.get_setting("interference", "standard_transmission")))
			store.set_setting("interference", order[(cur + dir + order.size()) % order.size()])
		"subtitles":
			store.set_setting("subtitles", not bool(store.get_setting("subtitles", true)))
			view.gfx.subtitles_enabled = bool(store.get_setting("subtitles", true))
		"voice":
			store.set_setting("voice", not bool(store.get_setting("voice", true)))
			voice.enabled = bool(store.get_setting("voice", true))
		"reset_players", "reset_history", "reset_all":
			if dir != 0:
				return false
			if _confirm != key:
				_confirm = key
				return false
			_confirm = ""
			match key:
				"reset_players":
					store.reset_players()
				"reset_history":
					store.reset_broadcast_history()
				"reset_all":
					store.reset_mildew()
			sys.toast("DONE.")
		"back":
			return true
	return false


# ===========================================================================
# Input
# ===========================================================================

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _unhandled_input(event: InputEvent) -> void:
	if state == "boot" or _args.has("mildew-host"):
		return
	if event.is_action_pressed("mildew_dev") and dev_build:
		dev.visible = not dev.visible
		return
	if dev.visible and event is InputEventKey and event.pressed and not event.echo:
		if _dev_key(event.keycode):
			return
	if event.is_action_pressed("mildew_pause") or event.is_action_pressed("ui_cancel"):
		_back()
		return
	var up := event.is_action_pressed("ui_up")
	var down := event.is_action_pressed("ui_down")
	var left := event.is_action_pressed("ui_left")
	var right := event.is_action_pressed("ui_right")
	var ok := event.is_action_pressed("ui_accept")
	if not (up or down or left or right or ok):
		return
	if _pause_open:
		_pause_input(up, down, left, right, ok)
		return
	match state:
		"ident":
			if ok:
				_go("title")
		"title":
			var n := view.gfx.menu_items.size()
			if up or down:
				menu_sel = (menu_sel + (1 if down else -1) + n) % n
				view.gfx.menu_selected = menu_sel
				audio.play("tick")
			elif ok:
				audio.play("lock")
				match menu_sel:
					0:
						_begin_transmission()
					1:
						_go("viewer")
					2:
						_go("settings")
					3:
						dev.visible = not dev.visible
		"viewer":
			var n := view.gfx.menu_items.size()
			if up or down:
				menu_sel = (menu_sel + (1 if down else -1) + n) % n
				view.gfx.menu_selected = menu_sel
				audio.play("tick")
			elif ok and menu_sel == 0:
				_go("title")
		"settings":
			var items := _settings_items()
			if up or down:
				_confirm = ""
				menu_sel = (menu_sel + (1 if down else -1) + items.size()) % items.size()
			elif left or right or ok:
				var done := _apply_setting(items[menu_sel].key, (-1 if left else 1) if (left or right) else 0)
				if done:
					_go("title")
					return
			_settings_menu(view.gfx)
		"transmission":
			if ok:
				_remote_ok()


func _back() -> void:
	match state:
		"viewer", "settings":
			_go("title")
		"transmission":
			if _pause_open and _pause_mode != "main":
				_open_pause("main")
			elif _pause_open:
				_close_pause()
			else:
				_open_pause("main")
		"title":
			pass  # Android: leaving the app is the OS's job (Home button)


func _remote_ok() -> void:
	var s := host.session
	if s == null:
		return
	if s.phase == SessionServer.Phase.LOBBY:
		if not s.start_show():
			sys.toast("AT LEAST TWO CONTESTANTS MUST JOIN FIRST")
	elif s.phase == SessionServer.Phase.ENDED:
		s.return_to_lobby()
	elif s.phase == SessionServer.Phase.CLOSED:
		_end_transmission()


func _begin_transmission() -> void:
	audio.stop_music()
	if not host.begin():
		sys.network_ok = false
		sys.network_error = host.start_error
		return
	sys.network_ok = true
	_go("transmission")


func _end_transmission() -> void:
	_close_pause()
	host.stop()
	voice.stop()
	sys.join_target = 0.0
	sys.late_hint = false
	sys.hold_reason = ""
	_go("title")


func _open_pause(mode: String) -> void:
	_pause_open = true
	_pause_mode = mode
	menu_sel = 0
	_confirm = ""
	if host.session and host.session.phase == SessionServer.Phase.SHOW:
		host.session.set_manual_pause(true)
	_refresh_pause()


func _refresh_pause() -> void:
	match _pause_mode:
		"main":
			sys.pause_title = "TRANSMISSION PAUSED"
			sys.pause_items = [
				{"key": "resume", "label": "RESUME", "desc": "Continue the programme. Phones show that the transmission is paused."},
				{"key": "settings", "label": "BROADCAST SETTINGS", "desc": "Transmission type, subtitles, presenter voice."},
				{"key": "end", "label": "END TRANSMISSION", "desc": "Stops the broadcast now and returns to the title screen. Scores so far are saved."},
			]
			if dev_build:
				sys.pause_items.append({"key": "dev", "label": "DEVELOPER TOOLS", "desc": "Fake players, disconnect simulation, timescale, diagnostics overlay."})
		"settings":
			_settings_menu(sys)
			return
		"dev":
			sys.pause_title = "DEVELOPER TOOLS"
			sys.pause_items = [
				{"key": "add_bot", "label": "ADD FAKE PLAYER", "desc": "Adds a loopback bot contestant (real protocol)."},
				{"key": "drop_bot", "label": "SIMULATE DISCONNECT", "desc": "Drops a fake player's connection (30 s reconnect window)."},
				{"key": "reconnect_bot", "label": "SIMULATE RECONNECT", "desc": "Reconnects the most recently dropped fake player."},
				{"key": "remove_bot", "label": "REMOVE FAKE PLAYER", "desc": ""},
				{"key": "timescale", "label": "TIMESCALE", "value": "x%.0f" % (host.session.time_scale if host.session else 1.0), "desc": "Accelerates all server timers."},
				{"key": "overlay", "label": "TOGGLE DIAGNOSTICS OVERLAY", "desc": "Network + Director state (also F3)."},
				{"key": "gallery", "label": "GRAHAM GALLERY: NEXT STATE", "desc": "Cuts to Camera 1 and steps through every Graham state with its fallback chain (F11)."},
				{"key": "graham_speak", "label": "GRAHAM: SPEECH BURST", "desc": "Plays the talking cycle on Camera 1 (F12)."},
				{"key": "back", "label": "BACK", "desc": ""},
			]
	sys.pause_selected = menu_sel


func _close_pause() -> void:
	_pause_open = false
	sys.pause_items = []
	if host.session and host.session.manual_pause:
		host.session.set_manual_pause(false)


func _pause_input(up: bool, down: bool, left: bool, right: bool, ok: bool) -> void:
	var items: Array = sys.pause_items
	if up or down:
		_confirm = ""
		menu_sel = (menu_sel + (1 if down else -1) + items.size()) % items.size()
		sys.pause_selected = menu_sel
		if _pause_mode == "settings":
			_settings_menu(sys)
		return
	var key: String = items[menu_sel].key
	match _pause_mode:
		"main":
			if not ok:
				return
			match key:
				"resume":
					_close_pause()
				"settings":
					_pause_mode = "settings"
					menu_sel = 0
					_settings_menu(sys)
				"end":
					_end_transmission()
				"dev":
					_pause_mode = "dev"
					menu_sel = 0
					_refresh_pause()
		"settings":
			if _apply_setting(key, (-1 if left else 1) if (left or right) else 0):
				_open_pause("main")
				return
			_settings_menu(sys)
		"dev":
			if not ok and key != "timescale":
				return
			_dev_action(key)
			if key == "back":
				_pause_mode = "main"
				menu_sel = 0
			_refresh_pause()


func _dev_action(key: String) -> void:
	if host.session == null:
		return
	match key:
		"add_bot":
			host.add_fake_player()
		"drop_bot":
			host.drop_fake_player()
		"reconnect_bot":
			host.reconnect_fake_player()
		"remove_bot":
			host.remove_fake_player()
		"timescale":
			host.session.time_scale = 1.0 if host.session.time_scale > 1.0 else 4.0
		"overlay":
			dev.visible = not dev.visible
		"gallery":
			dev.visible = true
			dev.page = 3
			view.studio._do_cut("cam1")
			dev.gallery_next(1)
		"graham_speak":
			view.studio._do_cut("cam1")
			view.graham.speak(3.0)
		"start":
			host.session.start_show()


func _dev_key(code: int) -> bool:
	match code:
		KEY_F4:
			dev.page = (dev.page + 1) % DevOverlay.PAGES
		KEY_F11:
			dev.page = 3
			view.studio._do_cut("cam1")
			dev.gallery_next(1)
		KEY_F12:
			view.studio._do_cut("cam1")
			view.graham.speak(3.0)
		KEY_F5:
			_dev_action("add_bot")
		KEY_F6:
			_dev_action("remove_bot")
		KEY_F7:
			_dev_action("drop_bot")
		KEY_F8:
			_dev_action("reconnect_bot")
		KEY_F9:
			_dev_action("timescale")
		KEY_F10:
			_dev_action("start")
		_:
			return false
	return true


func _process(delta: float) -> void:
	_state_t += delta
	if state == "ident" and _state_t > 4.2:
		_go("title")


# ===========================================================================
# Screenshot tour (dev): scripted programme with fake players
# ===========================================================================

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := str(_args["mildew-tour"])
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(dir.path_join(name + ".png"))
	print("TOUR_SHOT ", name)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_event(kind: String, timeout: float = 60.0) -> void:
	var got := [false]
	var cb := func(e): if e.get("e") == kind: got[0] = true
	host.tv_event.connect(cb)
	var t := 0.0
	while not got[0] and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	host.tv_event.disconnect(cb)


func _run_tour() -> void:
	_go("ident")
	await _wait(1.6)
	await _shot("01_ident")
	await _wait(3.8)
	await _shot("02_title")
	_go("viewer")
	menu_sel = 4
	view.gfx.menu_selected = 4
	await _wait(0.4)
	await _shot("02b_viewer_credits")
	_go("settings")
	menu_sel = 6
	_settings_menu(view.gfx)
	await _wait(0.4)
	await _shot("02c_settings")
	_go("title")
	_begin_transmission()
	await _wait(1.0)
	await _shot("03_lobby_empty")
	for i in int(_args.get("bots", 4)):
		host.add_fake_player(["risk_taker", "high_accuracy", "cautious", "horse", "terrible", "afk", "fast_random", "high_accuracy"][i % 8])
		await _wait(0.6)
	await _wait(2.5)
	await _shot("04_lobby_full")
	if _args.has("force-variant"):
		host.session.director.force["hole_variant"] = str(_args["force-variant"])
	if _args.has("force-item"):
		host.session.director.force["hole_item"] = str(_args["force-item"])
	host.session.time_scale = float(_args.get("timescale", 2.0))
	host.session.start_show()
	await _wait(2.5)
	await _shot("05_opening_titles")
	await _wait_event("intro_player")
	await _wait(1.0)
	await _shot("06_intro")
	await _wait_event("question_open", 40.0)
	await _wait(0.6)
	await _shot("07_rehearsal_question")
	await _wait_event_where("sting", func(e): return e.get("game_id") == "hole", 200.0)
	await _wait(0.12)
	await _shot("08_hole_sting_a")
	await _wait(0.75)
	await _shot("08_hole_sting_b")
	await _wait_event_where("hole_stage", func(e): return int(e.stage) == 1, 60.0)
	await _wait(1.4)
	await _shot("09_hole_stage1")
	await _wait_event("hole_lock", 30.0)
	await _wait(0.4)
	await _shot("10_hole_locked_in")
	await _wait_event_where("hole_stage", func(e): return int(e.stage) == 3, 30.0)
	await _wait(1.6)
	await _shot("11_hole_stage3")
	await _wait_event_where("hole_stage", func(e): return int(e.stage) == 4, 30.0)
	await _wait(1.2)
	await _shot("12_hole_safety_net")
	await _wait_event("hole_reveal", 40.0)
	await _wait(2.2)
	await _shot("13_hole_reveal")
	await _wait(2.6)
	await _shot("14_hole_after_reveal")
	await _wait_event_where("hole_round", func(e): return e.get("variant") == "scale", 90.0)
	await _wait_event("hole_stage", 30.0)
	await _wait(1.4)
	await _shot("15_hole_scale_round")
	host.drop_fake_player()
	await _wait(1.0)
	await _shot("16_reconnect_hold")
	host.reconnect_fake_player()
	await _wait(0.5)
	_open_pause("main")
	await _wait(0.4)
	await _shot("17_pause")
	_close_pause()
	host.session.time_scale = 4.0
	await _wait_event("scores", 400.0)
	await _wait(2.5)
	await _shot("18_scores")
	await _wait_event("winner", 60.0)
	await _wait(1.0)
	await _shot("19_winner")
	await _wait_event("show_ended", 60.0)
	await _wait(1.0)
	await _shot("20_ended")
	dev.visible = true
	dev.page = 1
	await _wait(0.3)
	await _shot("21_dev_director")
	dev.page = 0
	await _wait(0.3)
	await _shot("22_dev_network")
	print("TOUR_DONE")
	get_tree().quit()


func _wait_event_where(kind: String, pred: Callable, timeout: float = 60.0) -> void:
	var got := [false]
	var cb := func(e): if e.get("e") == kind and pred.call(e): got[0] = true
	host.tv_event.connect(cb)
	var t := 0.0
	while not got[0] and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	host.tv_event.disconnect(cb)
	if not got[0]:
		print("TOUR_TIMEOUT waiting for ", kind)
