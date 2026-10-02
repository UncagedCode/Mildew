class_name SessionServer
extends RefCounted
## The authoritative Mildew server/session (docs/06 layer 3). Transport-agnostic:
##   transports call connect_client / receive_text / disconnect_client and listen to `send`;
##   the broadcast client listens to `tv_event` and reads `tv_snapshot()`.
## All timing is driven by tick(real_dt). "Show time" freezes during manual pause, reconnect
## waits and insufficient-player holds, so nothing progresses while the room cannot play.
## Phones are untrusted: every action is validated against current state; scores, Rot,
## timers and progression are computed here only.

signal send(conn_id: int, msg: Dictionary)
signal close_requested(conn_id: int, reason: String)
signal tv_event(evt: Dictionary)
signal log_line(text: String)

enum Phase { LOBBY, SHOW, ENDED, CLOSED }

const MAX_PLAYERS := 8
const RESERVED_NAMES := ["graham", "graham mildew", "mildew", "announcer"]

var cfg: MildewConfig
var store: SaveStore
var content: ContentDB
var director: Director

var phase: Phase = Phase.LOBBY
var room_code := ""
var join_key := ""
var players := {}                 # player_id -> PlayerState
var conns := {}                   # conn_id -> Dictionary
var time_scale := 1.0
var session_time := 0.0           # scaled time since session open (never freezes)
var manual_pause := false
var hold_reason := ""             # "", "manual", "reconnect", "players"
var question_counter := 0
var invalid_message_count := 0
var rate_limited_count := 0
var show_count := 0

var _next_conn := 1
var _next_player := 1
var _segments: Array = []
var _current: Segment = null
var _lobby_line_cooldown := 0.0
var _lobby_last_count := -1
var _lobby_empty_timer := 0.0
var _lobby_ready_announced := false
var _speech_queue_until := 0.0    # lobby line spacing
var _rng := RandomNumberGenerator.new()
var _pending_tv: Array = []       # lines queued in lobby to avoid overlap


func _init(p_cfg: MildewConfig, p_store: SaveStore, p_content: ContentDB, seed: int = 0) -> void:
	cfg = p_cfg
	store = p_store
	content = p_content
	director = Director.new(content, seed)
	director.cfg = cfg
	if seed == 0:
		_rng.randomize()
	else:
		_rng.seed = seed + 7
	_new_room_identity()


func _new_room_identity() -> void:
	var alphabet: String = str(cfg.get_value("network.room_code_alphabet", "BCDFGHJKLMNPQRSTVWXZ"))
	var length: int = cfg.i("network.room_code_length", 4)
	room_code = ""
	for i in length:
		room_code += alphabet[_rng.randi_range(0, alphabet.length() - 1)]
	join_key = "%08x%08x" % [_rng.randi(), _rng.randi()]


func open() -> void:
	phase = Phase.LOBBY
	director.begin_session(store.installation, str(store.get_setting("interference", "standard_transmission")))
	_log("session open room=%s" % room_code)
	emit_tv({"e": "lobby_open", "room_code": room_code})


# ===========================================================================
# Transport-facing API
# ===========================================================================

func connect_client(meta: Dictionary = {}) -> int:
	var id := _next_conn
	_next_conn += 1
	conns[id] = {
		"id": id, "hello": false, "player_id": "", "fake": bool(meta.get("fake", false)),
		"addr": str(meta.get("addr", "")), "transport": str(meta.get("transport", "ws")),
		"last_seen": session_time, "msg_window_start": session_time, "msg_count": 0,
		"invalid": 0, "rtt": -1, "last_say": -99.0, "connected_at": session_time,
	}
	return id


func receive_text(conn_id: int, text: String) -> void:
	var c = conns.get(conn_id)
	if c == null:
		return
	c.last_seen = session_time
	# Simple accidental-spam rate limit (real time window; scaled time would distort it).
	var max_rate: int = cfg.i("network.max_messages_per_second", 30)
	if session_time - c.msg_window_start > 1.0 * time_scale:
		c.msg_window_start = session_time
		c.msg_count = 0
	c.msg_count += 1
	if c.msg_count > max_rate:
		rate_limited_count += 1
		if c.msg_count == max_rate + 1:
			_error(conn_id, Protocol.E_RATE_LIMIT)
		return
	var parsed := Protocol.parse(text, cfg.i("network.max_message_bytes", 4096))
	if not parsed.ok:
		_invalid(conn_id, parsed.code)
		return
	_handle(conn_id, parsed.msg)


func disconnect_client(conn_id: int, reason: String = "") -> void:
	var c = conns.get(conn_id)
	if c == null:
		return
	conns.erase(conn_id)
	var pid: String = c.player_id
	if pid == "" or not players.has(pid):
		return
	var p: PlayerState = players[pid]
	if p.conn_id != conn_id:
		return  # an older socket for a player who already reattached
	p.conn_id = -1
	p.connected = false
	_log("disconnect %s (%s) reason=%s" % [pid, p.display_name, reason])
	match phase:
		Phase.LOBBY, Phase.ENDED:
			p.lost_at = session_time
			emit_tv({"e": "player_conn", "pid": pid, "connected": false})
		Phase.SHOW:
			if p.status == PlayerState.Status.ACTIVE:
				p.lost_at = session_time
				p.mid_call_done = false
				director.on_player_lost(pid)
				emit_tv({"e": "player_lost", "pid": pid, "timeout": _reconnect_timeout()})
				_say_now("graham", "reconnect_lost", {"pid": pid})
			elif p.status == PlayerState.Status.WAITING:
				p.lost_at = session_time
			_recompute_hold()


func tick(real_dt: float) -> void:
	var dt := real_dt * time_scale
	session_time += dt
	_check_silent_connections()
	match phase:
		Phase.LOBBY, Phase.ENDED:
			_tick_lobby(dt)
		Phase.SHOW:
			_tick_reconnects()
			_recompute_hold()
			if hold_reason == "" and _current != null:
				director.tick(dt)
				_current.update(dt)
				if _current.done:
					_advance()


# ===========================================================================
# Message handling
# ===========================================================================

func _handle(conn_id: int, msg: Dictionary) -> void:
	var c: Dictionary = conns[conn_id]
	var t: String = msg.t
	if t == Protocol.C_PING:
		var rtt = Protocol.get_int(msg, "rtt")
		if rtt != null:
			c.rtt = int(rtt)
			if players.has(c.player_id):
				players[c.player_id].last_rtt_ms = int(rtt)
		_send(conn_id, {"t": Protocol.S_PONG, "id": msg.get("id"), "st": session_time})
		return
	if t == Protocol.C_HELLO:
		_on_hello(conn_id, msg)
		return
	if not c.hello:
		_invalid(conn_id, Protocol.E_NOT_HELLO)
		return
	match t:
		Protocol.C_CHECK_NAME:
			_on_check_name(conn_id, msg)
		Protocol.C_SAY_NAME:
			_on_say_name(conn_id, msg)
		Protocol.C_CREATE_PROFILE:
			_on_create_profile(conn_id, msg)
		Protocol.C_SELECT_PROFILE:
			_on_select_profile(conn_id, msg)
		Protocol.C_START_SHOW:
			_on_start_show(conn_id)
		Protocol.C_PLAY_AGAIN:
			_on_play_again(conn_id)
		Protocol.C_LEAVE:
			_on_leave(conn_id)
		Protocol.C_READY:
			pass  # used by later checkpoints (commercial break early resume)
		_:
			if Protocol.GAME_ACTIONS.has(t):
				_on_game_action(conn_id, msg)
				return
			_invalid(conn_id, Protocol.E_UNKNOWN_TYPE)


func _on_hello(conn_id: int, msg: Dictionary) -> void:
	var c: Dictionary = conns[conn_id]
	var v = Protocol.get_int(msg, "v")
	if v == null or int(v) != Protocol.VERSION:
		_error(conn_id, Protocol.E_BAD_VERSION, "host speaks protocol %d" % Protocol.VERSION)
		return
	var room = Protocol.get_str(msg, "room", 16)
	var key = Protocol.get_str(msg, "key", 64)
	var ok: bool = (key != null and key == join_key) or (room != null and room.strip_edges().to_upper() == room_code)
	if not ok:
		_error(conn_id, Protocol.E_BAD_ROOM)
		return
	if c.hello and c.player_id != "" and players.has(c.player_id):
		_send_screen(players[c.player_id])  # duplicate hello on a live socket: just resync
		return
	c.hello = true
	# Resume an existing player (reconnect) if the token matches.
	var token = Protocol.get_str(msg, "resume", 64)
	if token != null and token != "":
		for p in players.values():
			if p.resume_token == token and p.is_present():
				_attach(conn_id, p, true)
				return
	_send(conn_id, {"t": Protocol.S_WELCOME, "v": Protocol.VERSION, "conn": conn_id,
		"profiles": _available_profiles(), "phase": phase_name(), "room": room_code})


func _attach(conn_id: int, p: PlayerState, is_resume: bool) -> void:
	if p.conn_id != -1 and p.conn_id != conn_id and conns.has(p.conn_id):
		# Same player opened elsewhere: the newest unit wins; tell the old one honestly.
		var old := p.conn_id
		_send(old, {"t": Protocol.S_KICKED, "reason": "opened_elsewhere"})
		conns[old].player_id = ""
		close_requested.emit(old, "replaced")
	var was_lost := not p.connected and p.lost_at >= 0.0
	p.conn_id = conn_id
	p.connected = true
	conns[conn_id].player_id = p.player_id
	conns[conn_id].hello = true
	_send(conn_id, {"t": Protocol.S_JOINED, "player_id": p.player_id, "resume": p.resume_token,
		"name": p.display_name, "avatar": p.avatar, "number": p.number, "resumed": is_resume})
	if is_resume and was_lost:
		p.lost_at = -1.0
		emit_tv({"e": "player_conn", "pid": p.player_id, "connected": true})
		if phase == Phase.SHOW and p.status == PlayerState.Status.ACTIVE:
			director.on_player_returned(p.player_id)
			emit_tv({"e": "player_back", "pid": p.player_id})
			_say_now("graham", "reconnect_back", {"pid": p.player_id})
	_recompute_hold()
	_send_screen(p)
	_send_status(conn_id)


func _on_check_name(conn_id: int, msg: Dictionary) -> void:
	var name = Protocol.get_str(msg, "name", 64)
	if name == null:
		_invalid(conn_id, Protocol.E_BAD_PAYLOAD)
		return
	_send(conn_id, _name_check(name))


func _name_check(raw: String) -> Dictionary:
	var name := _clean_name(raw)
	var res := {"t": Protocol.S_NAME_RESULT, "name": name, "ok": false}
	var err := _validate_name(name, cfg.i("lobby.max_display_name_chars", 16))
	if err != "":
		res.code = Protocol.E_NAME_INVALID
		res.detail = err
		return res
	var key := SaveStore.normalize_name(name)
	for p in players.values():
		if p.is_present() and SaveStore.normalize_name(p.display_name) == key:
			res.code = Protocol.E_NAME_TAKEN
			return res
	var match_prof := store.find_profile_by_name(name)
	if not match_prof.is_empty() and not _profile_in_use(match_prof.profile_id):
		res.code = "match_profile"
		res.match_profile = {"id": match_prof.profile_id, "name": match_prof.display_name, "avatar": match_prof.get("avatar", {})}
		return res
	res.ok = true
	res.reserved = RESERVED_NAMES.has(key)
	return res


static func _clean_name(raw: String) -> String:
	return " ".join(raw.strip_edges().split(" ", false))


## Names must be speakable and renderable by the TV fonts (Latin / Greek / Cyrillic).
static func _validate_name(name: String, max_len: int) -> String:
	if name.length() < 1:
		return "empty"
	if name.length() > max_len:
		return "too_long"
	var letters := 0
	for i in name.length():
		var cp := name.unicode_at(i)
		if cp < 32 or cp == 127:
			return "control_characters"
		if "<>{}[]\\\"`|^~_=+*#@$%".contains(name[i]):
			return "unsupported_characters"
		var ok_range := cp < 0x0250 or (cp >= 0x0370 and cp <= 0x04FF)
		if not ok_range:
			return "unsupported_characters"
		if name[i].to_lower() != name[i].to_upper() or (cp >= 48 and cp <= 57):
			letters += 1
	if letters == 0:
		return "needs_letters"
	return ""


func _on_say_name(conn_id: int, msg: Dictionary) -> void:
	var c: Dictionary = conns[conn_id]
	var speech = Protocol.get_str(msg, "speech", 64)
	if speech == null:
		_invalid(conn_id, Protocol.E_BAD_PAYLOAD)
		return
	speech = _clean_name(speech)
	if _validate_name(speech, cfg.i("lobby.max_speech_name_chars", 40)) != "":
		_invalid(conn_id, Protocol.E_NAME_INVALID)
		return
	if session_time - float(c.last_say) < 0.6 * time_scale:
		return  # ignore button-mashing; not an error
	c.last_say = session_time
	var line := director.line("graham", "pronounce", {"name": speech, "speech_name": speech})
	if not line.is_empty():
		line["pronunciation_test"] = true
		emit_say(line, speech_seconds(line))


func _on_create_profile(conn_id: int, msg: Dictionary) -> void:
	var c: Dictionary = conns[conn_id]
	if c.player_id != "":
		_invalid(conn_id, Protocol.E_INVALID_STATE)
		return
	var claim = Protocol.get_str(msg, "claim", 64)
	var name_raw = Protocol.get_str(msg, "name", 64)
	var speech_raw = Protocol.get_str(msg, "speech", 64)
	if name_raw == null:
		_invalid(conn_id, Protocol.E_BAD_PAYLOAD)
		return
	if claim != null and claim != "":
		# "That's me": associate with the matching inactive profile (never automatic).
		var prof: Dictionary = store.profiles.get(claim, {})
		if prof.is_empty() or SaveStore.normalize_name(prof.display_name) != SaveStore.normalize_name(_clean_name(name_raw)) or _profile_in_use(claim):
			_error(conn_id, Protocol.E_PROFILE_UNAVAILABLE)
			return
		_admit(conn_id, prof, false)
		return
	var check := _name_check(name_raw)
	if not check.ok:
		_error(conn_id, Protocol.E_NAME_TAKEN if check.code in [Protocol.E_NAME_TAKEN, "match_profile"] else Protocol.E_NAME_INVALID, str(check.get("detail", check.code)))
		return
	var speech: String = check.name
	if speech_raw != null:
		var s := _clean_name(speech_raw)
		if s != "" and _validate_name(s, cfg.i("lobby.max_speech_name_chars", 40)) == "":
			speech = s
	var avatar := _sanitize_avatar(msg.get("avatar"))
	if _present_count() >= MAX_PLAYERS:
		_error(conn_id, Protocol.E_ROOM_FULL)
		return
	var prof: Dictionary
	if c.fake:
		prof = {"profile_id": "fake_%d" % conn_id, "display_name": check.name, "speech_name": speech, "avatar": avatar, "games_played": 0, "fake": true}
	else:
		prof = store.create_profile(check.name, speech, avatar)
		store.save_profiles()
	if check.get("reserved", false):
		_say_now("graham", "reserved_name", {})
	_admit(conn_id, prof, true)


func _on_select_profile(conn_id: int, msg: Dictionary) -> void:
	var c: Dictionary = conns[conn_id]
	var pid = Protocol.get_str(msg, "profile_id", 64)
	if pid == null or c.player_id != "":
		_invalid(conn_id, Protocol.E_BAD_PAYLOAD if pid == null else Protocol.E_INVALID_STATE)
		return
	var prof: Dictionary = store.profiles.get(pid, {})
	if prof.is_empty() or _profile_in_use(pid):
		_error(conn_id, Protocol.E_PROFILE_UNAVAILABLE)
		return
	_admit(conn_id, prof, false)


static func _sanitize_avatar(raw) -> Dictionary:
	var spec := {"hair": 6, "hair_colour": 6, "skin": 5, "glasses": 3, "outfit": 8, "accessory": 6}
	var out := {}
	for k in spec.keys():
		var v = 0
		if typeof(raw) == TYPE_DICTIONARY:
			var iv = Protocol.get_int(raw, k)
			if iv != null:
				v = clampi(int(iv), 0, spec[k] - 1)
		out[k] = v
	return out


func _admit(conn_id: int, prof: Dictionary, is_new: bool) -> void:
	if _present_count() >= MAX_PLAYERS:
		_error(conn_id, Protocol.E_ROOM_FULL)
		return
	var p := PlayerState.new()
	p.player_id = "p%d" % _next_player
	_next_player += 1
	p.profile_id = str(prof.get("profile_id", ""))
	p.display_name = str(prof.get("display_name", "?"))
	p.speech_name = str(prof.get("speech_name", p.display_name))
	p.avatar = prof.get("avatar", {})
	p.is_fake = bool(prof.get("fake", false)) or bool(conns[conn_id].fake)
	p.returning = not is_new and int(prof.get("games_played", 0)) > 0
	p.number = _free_podium_number()
	p.resume_token = "%08x%08x%08x" % [_rng.randi(), _rng.randi(), _rng.randi()]
	p.joined_at = session_time
	match phase:
		Phase.LOBBY, Phase.ENDED:
			p.status = PlayerState.Status.ACTIVE
		Phase.SHOW:
			# Late join: wait safely until the next game boundary, unless the show is held
			# for lack of players (then they are exactly what we're waiting for).
			p.status = PlayerState.Status.ACTIVE if hold_reason == "players" else PlayerState.Status.WAITING
	players[p.player_id] = p
	_log("admit %s '%s' status=%s new=%s fake=%s" % [p.player_id, p.display_name, p.status_name(), is_new, p.is_fake])
	emit_tv({"e": "player_joined", "pid": p.player_id, "info": p.public_info()})
	if phase == Phase.SHOW:
		_say_now("graham", "late_join", {"pid": p.player_id})
	elif not is_new and int(prof.get("games_played", 0)) > 0:
		_queue_lobby_line("graham", "lobby_returning", {"pid": p.player_id})
	else:
		_queue_lobby_line("graham", "lobby_join", {"pid": p.player_id})
	_attach(conn_id, p, false)
	push_screens()


func _on_start_show(conn_id: int) -> void:
	var p := _player_for(conn_id)
	if p == null or phase != Phase.LOBBY:
		_invalid(conn_id, Protocol.E_INVALID_STATE)
		return
	if captain_id() != p.player_id:
		_error(conn_id, Protocol.E_NOT_CAPTAIN)
		return
	if _connected_active_count() < cfg.i("product.min_players", 2):
		_error(conn_id, Protocol.E_NOT_ENOUGH_PLAYERS)
		return
	start_show()


func _on_play_again(conn_id: int) -> void:
	var p := _player_for(conn_id)
	if p == null or phase != Phase.ENDED:
		_invalid(conn_id, Protocol.E_INVALID_STATE)
		return
	if captain_id() != p.player_id:
		_error(conn_id, Protocol.E_NOT_CAPTAIN)
		return
	return_to_lobby()


func _on_leave(conn_id: int) -> void:
	var p := _player_for(conn_id)
	if p == null:
		conns[conn_id].hello = false
		return
	_log("leave %s" % p.player_id)
	conns[conn_id].player_id = ""
	p.conn_id = -1
	p.connected = false
	if phase == Phase.SHOW:
		p.status = PlayerState.Status.LEFT
		emit_tv({"e": "player_left", "pid": p.player_id})
		_say_now("graham", "player_left_show", {"pid": p.player_id})
	else:
		players.erase(p.player_id)
		emit_tv({"e": "player_left", "pid": p.player_id})
		_queue_lobby_line("graham", "lobby_left", {"name": p.display_name, "speech_name": p.speech_name})
	_send(conn_id, {"t": Protocol.S_WELCOME, "v": Protocol.VERSION, "conn": conn_id,
		"profiles": _available_profiles(), "phase": phase_name(), "room": room_code})
	_recompute_hold()
	push_screens()


func _on_game_action(conn_id: int, msg: Dictionary) -> void:
	var p := _player_for(conn_id)
	if p == null or phase != Phase.SHOW or _current == null:
		_invalid(conn_id, Protocol.E_INVALID_STATE)
		return
	if hold_reason != "":
		_invalid(conn_id, Protocol.E_INVALID_STATE)
		return
	if p.status != PlayerState.Status.ACTIVE:
		_invalid(conn_id, Protocol.E_NOT_PARTICIPANT)
		return
	var err := _current.handle_action(p, msg)
	if err != "":
		_invalid(conn_id, err)
		return
	_send_screen(p)


# ===========================================================================
# Show flow
# ===========================================================================

## Begins the broadcast (phone captain or TV remote). Returns false if not allowed.
func start_show() -> bool:
	if phase != Phase.LOBBY or _connected_active_count() < cfg.i("product.min_players", 2):
		return false
	# Lobby stragglers who never reconnected do not get a podium in the show.
	for p in players.values():
		if not p.connected:
			players.erase(p.player_id)
	director.reset_for_new_show()
	question_counter = 0
	for p in players.values():
		p.score = 0
		p.rot = 0
		p.history.clear()
		p.status = PlayerState.Status.ACTIVE
	var plan := director.plan_episode(active_player_ids(), cfg.i("show.rehearsal_question_count", 3))
	_segments.clear()
	for desc in plan:
		_segments.append(desc)
	phase = Phase.SHOW
	show_count += 1
	_pending_tv.clear()
	_log("show start players=%d" % players.size())
	emit_tv({"e": "show_start", "players": _public_players()})
	_advance()
	return true


func _advance() -> void:
	var prev: Segment = _current
	if prev != null:
		prev.finish()  # may end the show (sign-off)
		var allow: bool = prev.allows_late_join_after
		# Never integrate late joiners when the next segment continues a game in progress
		# (the planner marks every segment after a game's first round as mid_game).
		if allow and not _segments.is_empty() and bool(_segments[0].get("mid_game", false)):
			allow = false
		if allow:
			_integrate_waiting()
		# Broadcast irregularity opportunity between segments (presentation-only; never blocks).
		if phase == Phase.SHOW and not _segments.is_empty() and prev.kind != "incident":
			var nxt: Dictionary = _segments[0]
			if str(nxt.get("kind")) not in ["sign_off"]:
				var inc: Dictionary = director.incidents.opportunity("boundary", {"game": str(nxt.get("game_id", "")),
					"players": _connected_active_count(), "next": str(nxt.get("kind"))})
				if not inc.is_empty():
					_segments.push_front({"kind": "incident", "incident": inc})
	if phase != Phase.SHOW:
		return
	if _segments.is_empty():
		_current = null
		end_show()
		return
	var desc: Dictionary = _segments.pop_front()
	_current = BasicSegments.make(desc, self)
	_log("segment %s" % _current.kind)
	emit_tv({"e": "segment", "kind": _current.kind})
	_current.start()
	push_screens()


func _integrate_waiting() -> void:
	for p in players.values():
		if p.status == PlayerState.Status.WAITING and p.connected:
			p.status = PlayerState.Status.ACTIVE
			emit_tv({"e": "player_integrated", "pid": p.player_id})
			_log("integrate late joiner %s" % p.player_id)


func end_show() -> void:
	if phase != Phase.SHOW:
		return
	_persist_results()
	phase = Phase.ENDED
	_current = null
	_segments.clear()
	hold_reason = ""
	manual_pause = false
	emit_tv({"e": "show_ended", "standings": standings()})
	_log("show ended")
	push_screens()
	_broadcast_status()


func return_to_lobby() -> void:
	if phase == Phase.CLOSED:
		return
	phase = Phase.LOBBY
	for p in players.values():
		if not p.is_present():
			players.erase(p.player_id)
		else:
			p.status = PlayerState.Status.ACTIVE
			p.score = 0
	_lobby_ready_announced = false
	_lobby_last_count = -1
	emit_tv({"e": "lobby_open", "room_code": room_code})
	push_screens()


## TV remote: END TRANSMISSION, or everyone left. Always allowed (never blocked by fiction).
func close_session(reason: String) -> void:
	if phase == Phase.SHOW:
		_persist_results()
	phase = Phase.CLOSED
	_current = null
	emit_tv({"e": "session_closed", "reason": reason})
	for cid in conns.keys():
		_send(cid, {"t": Protocol.S_SCREEN, "screen": "closed", "data": {"reason": reason}, "seq": 0})
	_log("session closed: %s" % reason)


func _persist_results() -> void:
	var st := standings()
	var top_score := int(st[0].score) if not st.is_empty() else 0
	for p in players.values():
		if p.is_fake or not store.profiles.has(p.profile_id):
			continue
		if p.status == PlayerState.Status.WAITING:
			continue
		var prof: Dictionary = store.profiles[p.profile_id]
		prof.games_played = int(prof.get("games_played", 0)) + 1
		if top_score > 0 and p.score == top_score:
			prof.wins = int(prof.get("wins", 0)) + 1
		prof.lifetime_rot = int(prof.get("lifetime_rot", 0)) + p.rot
		prof.last_seen_unix = int(Time.get_unix_time_from_system())
	store.save_profiles()
	store.installation.broadcasts_played = int(store.installation.get("broadcasts_played", 0)) + 1
	var hist: Array = store.installation.get("recent_content_history", [])
	for id in director.used_content.keys():
		hist.erase(id)
		hist.append(id)
	while hist.size() > 200:
		hist.pop_front()
	store.installation.recent_content_history = hist
	store.save_installation()


# ===========================================================================
# Holds: manual pause, reconnect windows, insufficient players
# ===========================================================================

func set_manual_pause(paused: bool) -> void:
	manual_pause = paused
	_recompute_hold()


func _reconnect_timeout() -> float:
	return cfg.f("broadcast.reconnect_timeout_seconds", 30.0)


func _tick_reconnects() -> void:
	var timeout := _reconnect_timeout()
	for p in players.values():
		if p.status != PlayerState.Status.ACTIVE or p.connected or p.lost_at < 0.0:
			continue
		var waited: float = session_time - p.lost_at
		if waited >= timeout * 0.5 and not p.mid_call_done:
			p.mid_call_done = true
			_say_now("graham", "reconnect_mid", {"pid": p.player_id})
		if waited >= timeout:
			p.status = PlayerState.Status.DROPPED
			p.lost_at = -1.0
			director.on_player_failed_return(p.player_id)
			emit_tv({"e": "player_dropped", "pid": p.player_id})
			_log("dropped %s after %.1fs" % [p.player_id, waited])
			if _connected_present_count() == 0:
				if _any_in_reconnect_window():
					continue  # others may still return; give them their full window
				_all_gone()
				return
			_say_now("graham", "reconnect_failed", {"pid": p.player_id})
	# Waiting late-joiners who vanish are simply removed (no show pause for spectators).
	for p in players.values():
		if p.status == PlayerState.Status.WAITING and not p.connected and p.lost_at >= 0.0 and session_time - p.lost_at >= timeout:
			p.status = PlayerState.Status.DROPPED


func _any_in_reconnect_window() -> bool:
	for p in players.values():
		if p.status == PlayerState.Status.ACTIVE and not p.connected and p.lost_at >= 0.0:
			return true
	return false


func _all_gone() -> void:
	director.on_all_gone()
	var line := director.line("graham", "all_gone", {})
	if not line.is_empty():
		emit_say(line, speech_seconds(line))
	emit_tv({"e": "all_gone"})
	close_session("all_contestants_left")


func _recompute_hold() -> void:
	if phase != Phase.SHOW:
		if hold_reason != "":
			hold_reason = ""
			_broadcast_status()
		return
	var reason := ""
	if manual_pause:
		reason = "manual"
	else:
		for p in players.values():
			if p.status == PlayerState.Status.ACTIVE and not p.connected:
				reason = "reconnect"
				break
		if reason == "" and _connected_active_count() < cfg.i("product.min_players", 2):
			reason = "players"
	if reason != hold_reason:
		var prev := hold_reason
		hold_reason = reason
		emit_tv({"e": "hold", "reason": reason, "prev": prev, "detail": _hold_detail()})
		if reason == "players":
			_integrate_waiting()
			# Re-check: integrating a waiting player may already resolve the hold.
			if _connected_active_count() >= cfg.i("product.min_players", 2):
				hold_reason = ""
				emit_tv({"e": "hold", "reason": "", "prev": "players", "detail": {}})
			else:
				_say_now("graham", "waiting_players", {})
		_broadcast_status()
		push_screens()


func _hold_detail() -> Dictionary:
	var lost: Array = []
	for p in players.values():
		if p.status == PlayerState.Status.ACTIVE and not p.connected and p.lost_at >= 0.0:
			lost.append({"pid": p.player_id, "name": p.display_name,
				"remaining": maxf(0.0, _reconnect_timeout() - (session_time - p.lost_at)) / maxf(time_scale, 0.001)})
	return {"lost": lost, "reason": hold_reason}


func _broadcast_status() -> void:
	for cid in conns.keys():
		_send_status(cid)


func _send_status(conn_id: int) -> void:
	if not conns.has(conn_id) or conns[conn_id].player_id == "":
		return
	_send(conn_id, {"t": Protocol.S_STATUS, "paused": hold_reason != "", "reason": hold_reason, "detail": _hold_detail()})


# ===========================================================================
# Lobby chatter (Graham waiting for contestants)
# ===========================================================================

func _tick_lobby(dt: float) -> void:
	# Remove lobby players whose phones never came back.
	var grace: float = cfg.f("lobby.disconnected_player_grace_seconds", 45.0)
	for p in players.values():
		if not p.connected and p.lost_at >= 0.0 and session_time - p.lost_at > grace:
			players.erase(p.player_id)
			emit_tv({"e": "player_left", "pid": p.player_id})
			push_screens()
	if phase != Phase.LOBBY:
		return
	_lobby_line_cooldown -= dt
	var count := _connected_active_count()
	if count != _lobby_last_count:
		_lobby_last_count = count
		if count == 1:
			var only := active_players_sorted()
			_queue_lobby_line("graham", "lobby_one", {"pid": only[0].player_id} if not only.is_empty() else {})
		elif count >= 2 and not _lobby_ready_announced:
			_lobby_ready_announced = true
			var cap := captain_id()
			_queue_lobby_line("graham", "lobby_ready", {"pid": cap} if cap != "" else {})
		push_screens()
	if count == 0:
		_lobby_empty_timer -= dt
		if _lobby_empty_timer <= 0.0:
			_lobby_empty_timer = _rng.randf_range(16.0, 28.0)
			_queue_lobby_line("graham", "lobby_empty", {})
	# Flush queued lines one at a time so Graham never talks over himself.
	if not _pending_tv.is_empty() and session_time >= _speech_queue_until:
		var item = _pending_tv.pop_front()
		var line := director.line(item.speaker, item.category, line_ctx(item.ctx))
		if not line.is_empty():
			var dur := speech_seconds(line)
			emit_say(line, dur)
			_speech_queue_until = session_time + dur + 0.6


func _queue_lobby_line(speaker: String, category: String, ctx: Dictionary) -> void:
	# Keep the queue short: newest context matters most in a busy lobby.
	if _pending_tv.size() >= 3:
		_pending_tv.pop_front()
	_pending_tv.append({"speaker": speaker, "category": category, "ctx": ctx.duplicate()})


func _say_now(speaker: String, category: String, ctx: Dictionary) -> void:
	var line := director.line(speaker, category, line_ctx(ctx))
	if not line.is_empty():
		emit_say(line, speech_seconds(line))


# ===========================================================================
# Helpers used by segments & presentation
# ===========================================================================

func line_ctx(ctx: Dictionary) -> Dictionary:
	var out := ctx.duplicate()
	if ctx.has("pid") and players.has(ctx.pid):
		var p: PlayerState = players[ctx.pid]
		out["name"] = p.display_name
		out["speech_name"] = p.speech_name
	return out


func speech_seconds(line: Dictionary) -> float:
	if line.get("silent", false):
		return 3.0  # deliberate silence is an asset
	var words := str(line.get("speech", line.get("text", ""))).split(" ", false).size()
	return words / cfg.f("show.words_per_second_speech", 2.6) + cfg.f("show.speech_padding_seconds", 0.7)


func emit_say(line: Dictionary, duration: float) -> void:
	var evt := line.duplicate()
	evt["e"] = "say"
	evt["duration"] = duration / maxf(time_scale, 0.001)
	emit_tv(evt)


func emit_tv(evt: Dictionary) -> void:
	evt["st"] = session_time
	tv_event.emit(evt)


func push_screens() -> void:
	for p in players.values():
		if p.connected:
			_send_screen(p)


func _send_screen(p: PlayerState) -> void:
	if p.conn_id == -1:
		return
	var sc := screen_for(p)
	p.screen_seq += 1
	sc["t"] = Protocol.S_SCREEN
	sc["seq"] = p.screen_seq
	_send(p.conn_id, sc)


func screen_for(p: PlayerState) -> Dictionary:
	match phase:
		Phase.LOBBY:
			var count := _connected_active_count()
			return {"screen": "lobby", "data": {"number": p.number, "captain": captain_id() == p.player_id,
				"count": count, "min": cfg.i("product.min_players", 2), "can_start": count >= cfg.i("product.min_players", 2),
				"name": p.display_name, "avatar": p.avatar}}
		Phase.ENDED:
			var st := standings()
			var rank := 0
			for s in st:
				if s.pid == p.player_id:
					rank = int(s.rank)
			return {"screen": "ended", "data": {"captain": captain_id() == p.player_id, "rank": rank, "of": st.size(), "score": p.score}}
		Phase.CLOSED:
			return {"screen": "closed", "data": {}}
		_:
			if p.status == PlayerState.Status.WAITING:
				return {"screen": "spectator", "data": {"caption": "YOU WILL JOIN AT THE NEXT SEGMENT"}}
			if p.status != PlayerState.Status.ACTIVE:
				return {"screen": "closed", "data": {}}
			if _current == null:
				return {"screen": "watch", "data": {"caption": "PLEASE WATCH YOUR TELEVISION"}}
			return _current.screen_for(p)


func standings() -> Array:
	var list: Array = []
	for p in players.values():
		if p.status == PlayerState.Status.ACTIVE or p.status == PlayerState.Status.DROPPED or p.status == PlayerState.Status.LEFT:
			if p.status == PlayerState.Status.ACTIVE or p.score > 0:
				list.append({"pid": p.player_id, "name": p.display_name, "score": p.score, "rot": p.rot, "number": p.number, "status": p.status_name()})
	list.sort_custom(func(a, b): return a.score > b.score or (a.score == b.score and a.number < b.number))
	var rank := 0
	var last := -1
	for i in list.size():
		if list[i].score != last:
			rank = i + 1
			last = list[i].score
		list[i]["rank"] = rank
	return list


func active_player_ids() -> Array:
	return active_players_sorted().map(func(p): return p.player_id)


func active_players_sorted() -> Array:
	var list: Array = players.values().filter(func(p): return p.status == PlayerState.Status.ACTIVE)
	list.sort_custom(func(a, b): return a.number < b.number)
	return list


func captain_id() -> String:
	# Floor captain: earliest-joined connected active player.
	var best: PlayerState = null
	for p in players.values():
		if p.status == PlayerState.Status.ACTIVE and p.connected:
			if best == null or p.joined_at < best.joined_at:
				best = p
	return best.player_id if best != null else ""


func phase_name() -> String:
	return ["lobby", "show", "ended", "closed"][phase]


func _free_podium_number() -> int:
	var used := {}
	for p in players.values():
		if p.is_present():
			used[p.number] = true
	for n in range(1, MAX_PLAYERS + 1):
		if not used.has(n):
			return n
	return MAX_PLAYERS


func _present_count() -> int:
	return players.values().filter(func(p): return p.is_present()).size()


func _connected_present_count() -> int:
	return players.values().filter(func(p): return p.is_present() and p.connected).size()


func _connected_active_count() -> int:
	return players.values().filter(func(p): return p.status == PlayerState.Status.ACTIVE and p.connected).size()


func _profile_in_use(profile_id: String) -> bool:
	for p in players.values():
		if p.profile_id == profile_id and p.is_present():
			return true
	return false


func _available_profiles() -> Array:
	var list: Array = []
	for prof in store.profiles.values():
		if _profile_in_use(prof.profile_id):
			continue
		list.append({"id": prof.profile_id, "name": prof.display_name, "avatar": prof.get("avatar", {}),
			"games_played": int(prof.get("games_played", 0)), "last_seen": int(prof.get("last_seen_unix", 0))})
	list.sort_custom(func(a, b): return a.last_seen > b.last_seen)
	return list.slice(0, 12)


func _public_players() -> Array:
	return active_players_sorted().map(func(p): return p.public_info())


func _player_for(conn_id: int) -> PlayerState:
	var c = conns.get(conn_id)
	if c == null or c.player_id == "":
		return null
	return players.get(c.player_id)


func _check_silent_connections() -> void:
	var limit: float = cfg.f("network.client_silence_timeout_ms", 9000.0) / 1000.0 * time_scale
	for cid in conns.keys():
		var c: Dictionary = conns[cid]
		if c.fake:
			continue
		if session_time - float(c.last_seen) > limit:
			_log("conn %d silent for %.1fs; closing" % [cid, (session_time - float(c.last_seen)) / time_scale])
			close_requested.emit(cid, "silent")
			disconnect_client(cid, "silent")


func _send(conn_id: int, msg: Dictionary) -> void:
	if conns.has(conn_id):
		send.emit(conn_id, msg)


func _error(conn_id: int, code: String, detail: String = "") -> void:
	var m := {"t": Protocol.S_ERROR, "code": code}
	if detail != "":
		m["detail"] = detail
	_send(conn_id, m)


func _invalid(conn_id: int, code: String) -> void:
	invalid_message_count += 1
	if conns.has(conn_id):
		conns[conn_id].invalid += 1
	_error(conn_id, code)


func _log(text: String) -> void:
	log_line.emit("[%.2f] %s" % [session_time, text])


func tv_snapshot() -> Dictionary:
	return {
		"phase": phase_name(),
		"room_code": room_code,
		"join_key": join_key,
		"players": players.values().filter(func(p): return p.is_present() or p.score > 0).map(func(p): return p.public_info()),
		"captain": captain_id(),
		"hold": hold_reason,
		"hold_detail": _hold_detail(),
		"segment": _current.tv_state() if _current != null else {},
		"standings": standings(),
	}


func diagnostics() -> Dictionary:
	var list: Array = []
	for c in conns.values():
		list.append({"id": c.id, "player": c.player_id, "rtt": c.rtt, "invalid": c.invalid, "fake": c.fake, "addr": c.addr, "transport": c.transport})
	return {"protocol": Protocol.VERSION, "phase": phase_name(), "conns": list, "invalid_total": invalid_message_count,
		"rate_limited": rate_limited_count, "hold": hold_reason, "time_scale": time_scale, "session_time": session_time,
		"segments_remaining": _segments.size(), "segment": _current.kind if _current != null else ""}
