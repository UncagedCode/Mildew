class_name DevOverlay
extends Control
## Development-only Director/network diagnostics (docs/10). Never available in release builds.

var host: MildewHost
var f_mono: Font
var page := 0                 # 0 network, 1 director, 2 logs


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
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0, 0, 0, 0.82))
	var y := 34.0
	y = _line(y, "MILDEW DEV OVERLAY  [F3 toggle · F4 page · F5 add bot · F6 remove bot · F7 drop bot · F8 reconnect bot · F9 timescale · F10 start]  page %d/3" % (page + 1), Color(1, 1, 0.3))
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
