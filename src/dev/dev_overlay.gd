class_name DevOverlay
extends Control
## Development-only Director/network diagnostics (docs/10). Never available in release builds.

var host: MildewHost
var graham: GrahamPresenter
var f_mono: Font
var voice: GrahamVoiceService     # GrahamVoice autoload (voice browser page)
var page := 0                 # 0 network, 1 director, 2 logs, 3 Graham gallery, 4 voice browser
const PAGES := 5
const VOICE_PAGE := 4
var gallery_i := 0
var voice_sel := 0


func _ready() -> void:
	f_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	if visible:
		queue_redraw()


func _line(y: float, text: String, col := Color(0.7, 1, 0.7)) -> float:
	draw_string(f_mono, Vector2(30, y), text, HORIZONTAL_ALIGNMENT_LEFT, 1860, 17, col)
	return y + 21.0


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1920 if page != 3 else 700, 1080), Color(0, 0, 0, 0.82))
	var y := 34.0
	y = _line(y, "MILDEW DEV OVERLAY  [F3 toggle · F4 page · F5 add bot · F6 remove bot · F7 drop bot · F8 reconnect bot · F9 timescale · F10 start · F11/F12 gallery]  page %d/%d" % [page + 1, PAGES], Color(1, 1, 0.3))
	if page == 3:
		_draw_gallery(y)
		return
	if page == VOICE_PAGE:
		_draw_voice(y)
		return
	if host == null or host.session == null:
		_line(y, "host not running")
		return
	var d := host.diagnostics()
	y = _line(y, "FPS %d  frame %.1f ms  static_mem %.1f MB  draw_calls %d  device=%s %s" % [Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), OS.get_model_name(), OS.get_name()], Color(1, 0.8, 0.4))
	match page:
		0:
			y = _line(y, "protocol=%s phase=%s segment=%s hold=%s time_scale=%.1f session_t=%.1f" % [d.protocol, d.phase, d.segment, d.hold, d.time_scale, d.session_time])
			y = _line(y, "LAN ip=%s http=%d ws=%d ws_peers=%d http_served=%d http_rejected=%d invalid_msgs=%d rate_limited=%d" % [d.lan_ip, d.http_port, d.ws_port, d.ws_peers, d.http_served, d.http_rejected, d.invalid_total, d.rate_limited])
			y = _line(y, "join_url=%s  short=%s  room=%s" % [d.join_url, d.short_url, host.session.room_code])
			y = _line(y, "LAN candidates: %s" % str(d.lan_candidates))
			y += 10
			y = _line(y, "CONNECTIONS", Color(1, 1, 0.3))
			for c in d.conns:
				y = _line(y, "  conn %-3d %-9s player=%-4s rtt=%4sms invalid=%d addr=%s" % [c.id, c.transport, c.player, str(c.rtt), c.invalid, c.addr])
			y += 10
			y = _line(y, "PLAYERS", Color(1, 1, 0.3))
			for p in host.session.players.values():
				y = _line(y, "  %-4s #%d %-16s status=%-8s conn=%s score=%d rot=%d fake=%s token=%s…" % [p.player_id, p.number, p.display_name, p.status_name(), p.connected, p.score, p.rot, p.is_fake, p.resume_token.substr(0, 6)])
		1:
			var s := host.session.director.snapshot()
			y = _line(y, "graham_mood=%s pressure=%.2f degradation=%.2f complicity=%.2f familiarity_tier=%d interference=%s announcer_stage=%d" % [s.graham_mood, s.pressure, s.degradation, s.complicity, s.familiarity_tier, s.interference_mode, s.announcer_stage])
			y = _line(y, "installation_seed=%s broadcasts=%s" % [host.store.installation.get("installation_seed"), host.store.installation.get("broadcasts_played")])
			y = _line(y, "tone=%s" % str(s.tone))
			y = _line(y, "SKELETON", Color(1, 1, 0.3))
			for slot in s.skeleton:
				y = _line(y, "  %-15s %-10s %s" % [slot.slot, slot.state, slot.content])
			y = _line(y, "RELATIONSHIPS", Color(1, 1, 0.3))
			for pid in s.relationships.keys():
				var r: Dictionary = s.relationships[pid]
				var parts: Array = []
				for k in r.keys():
					if float(r[k]) > 0.0:
						parts.append("%s=%.2f" % [k, r[k]])
				y = _line(y, "  %s: %s" % [pid, ", ".join(parts)])
			y = _line(y, "DECISION LOG (latest)", Color(1, 1, 0.3))
			var log: Array = host.session.director.decision_log
			for e in log.slice(maxi(0, log.size() - 18)):
				y = _line(y, "  [%6.1f] %s(%s) %s" % [e.t, e.kind, e.choice, "; ".join(e.reasons)])
		2:
			y = _line(y, "HOST LOG", Color(1, 1, 0.3))
			for l in host.log_lines.slice(maxi(0, host.log_lines.size() - 44)):
				y = _line(y, "  " + str(l))


## Graham gallery (pack GRAHAM_GODOT_IMPLEMENTATION "Development debug controls"): every semantic
## state, what it resolves to, its fallback chain and blink/variant frames. F11 = show next state
## on Camera 1, F12 = speech burst. The overlay is translucent on this page so Graham stays visible.
func gallery_next(dir: int = 1) -> String:
	if graham == null:
		return ""
	var states := graham.all_states()
	gallery_i = (gallery_i + dir + states.size()) % states.size()
	var st: String = states[gallery_i]
	graham.set_state(st, "cut")
	return st


func _draw_gallery(y: float) -> void:
	if graham == null:
		_line(y, "no presenter")
		return
	y = _line(y, "GRAHAM GALLERY  mode=%s  shown=%s  speaking=%s  ready=%s" % [graham.mode, graham.current_state(), graham.is_speaking(), graham.is_ready()], Color(1, 1, 0.3))
	var states := graham.all_states()
	var cut_states: Dictionary = graham.cut.get("states", {})
	for i in states.size():
		var st: String = states[i]
		var chain := graham.fallback_chain(st)
		var e: Dictionary = cut_states.get(st, {})
		var info := "frame=%s" % e.get("frame", "-") if not e.is_empty() else "MISSING -> " + " -> ".join(chain.slice(1))
		if e.has("blink"):
			info += "  blink=%s" % str(e.blink)
		if e.has("variants"):
			info += "  variants=%s" % str(e.variants)
		y = _line(y, "%s %-20s %s" % [">" if i == gallery_i else " ", st, info], Color(1, 1, 1) if i == gallery_i else Color(0.7, 1, 0.7))


## Developer Voice Browser (CLAUDE_INTEGRATION.md task 7): every semantic voice id, its status
## and text. Remote: pause → DEVELOPER TOOLS → VOICE BROWSER (◀ ▶ select, OK play). Phone: /dev panel.
func voice_ids() -> Array:
	return voice.index.ids() if voice and voice.index else []


func voice_step(dir: int) -> String:
	var ids := voice_ids()
	if ids.is_empty():
		return ""
	voice_sel = (voice_sel + dir + ids.size()) % ids.size()
	return str(ids[voice_sel])


func voice_play_selected() -> float:
	var ids := voice_ids()
	if ids.is_empty():
		return -1.0
	return voice.say(str(ids[clampi(voice_sel, 0, ids.size() - 1)]))


func _draw_voice(y: float) -> void:
	y = _line(y, "GRAHAM VOICE BROWSER  (local authored clips · no cloud speech)", Color(1, 1, 0.3))
	if voice == null or voice.index == null:
		_line(y, "GrahamVoice autoload not available")
		return
	var dg := voice.diagnostics()
	var c: Dictionary = dg.counts
	y = _line(y, "approved %d · development %d · missing %d · playing: %s · dev TTS fallback: %s (used %d) · bus: %s" % [c.approved, c.development, c.missing,
		dg.playing if dg.playing != "" else "-", "on" if dg.dev_tts_fallback else "off", dg.fallbacks, GrahamVoiceService.BUS], Color(1, 0.8, 0.4))
	y += 6.0
	var ids := voice_ids()
	for i in ids.size():
		var id: String = ids[i]
		var st := voice.index.status(id)
		var col := Color(0.55, 1, 0.55) if st == "approved" else (Color(1, 0.85, 0.4) if st == "development" else Color(1, 0.45, 0.4))
		if i == voice_sel:
			draw_rect(Rect2(24, y - 16, 1872, 21), Color(1, 1, 1, 0.12))
		var mark := "▶" if dg.playing == id else (">" if i == voice_sel else " ")
		y = _line(y, "%s %-22s %-11s %s" % [mark, id, st.to_upper(), voice.index.text(id)], col)
	y += 8.0
	var names: Array = voice.index.names.keys()
	names.sort()
	_line(y, "name bank: %s   recent missing: %s" % [", ".join(names), ", ".join(dg.missing)], Color(0.7, 0.85, 1))
