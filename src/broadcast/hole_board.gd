class_name HoleBoard
extends Control
## HOLE broadcast graphic (inside the 4:3 programme, under subtitles/lower-thirds).
## A chunky chrome "HOLE-O-SCOPE" monitor shows the mystery opening; each reveal stage is a
## slow camera pull-back to a wider crop. Stage lamps show what a lock is worth right now.
## Reveal pulls all the way out, slaps the answer across the monitor and shows who locked what.
## Readability (docs/01 #97): stage value, timer and options are large and never glitched.

const W := 1440.0
const H := 1080.0
const LETTERS := ["A", "B", "C", "D"]
const OPTION_COLOURS := [Color("#c7362b"), Color("#e2b42c"), Color("#3f9a45"), Color("#2e5fae")]

var f_display: Font
var f_sans: Font
var f_sans_italic: Font
var f_mono: Font

var players := {}                  # pid -> public info (avatars)
var _t := 0.0
var _vis := 0.0
var _target_vis := 0.0

var _path := ""
var _tex: Texture2D = null
var _loading := false
var _stages: Array = []            # [{x,y,zoom}] x3
var _crop := Vector3(0.5, 0.5, 6.0)        # current (x, y, zoom)
var _crop_target := Vector3(0.5, 0.5, 6.0)
var _round := 1
var _of := 1
var _variant := "standard"
var _stage := 0
var _final_stage := 4
var _points := 0
var _timer := -1.0
var _timer_total := 1.0
var _locked := {}                  # pid -> stage locked (who, not what)
var _of_players := 0
var _options: Array = []           # safety net labels
var _net := 0.0                    # 0..1 safety-net layout blend
var _closed := false
var _answer := ""
var _outcome := {}
var _reveal_t := -1.0
var _studio := false
var _static := 0.0                 # tuning-in static when a new image arrives


func _ready() -> void:
	f_display = load("res://assets/fonts/InterDisplay-BlackItalic.otf")
	f_sans = load("res://assets/fonts/LiberationSans-Bold.ttf")
	f_sans_italic = load("res://assets/fonts/LiberationSans-BoldItalic.ttf")
	f_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------------------------------------------------------------------------
# API (Presenter)
# ---------------------------------------------------------------------------

func prepare_round(evt: Dictionary) -> void:
	_round = int(evt.get("round", 1))
	_of = int(evt.get("of", 1))
	_variant = str(evt.get("variant", "standard"))
	_final_stage = int(evt.get("final_stage", 4))
	_stages = evt.get("stages", [])
	_studio = bool(evt.get("studio_hole", false))
	_stage = 0
	_locked.clear()
	_options = []
	_closed = false
	_answer = ""
	_outcome = {}
	_reveal_t = -1.0
	_timer = -1.0
	_net = 0.0
	_static = 1.0
	if not _stages.is_empty():
		_crop_target = _stage_vec(0)
		_crop = _crop_target
	var path := str(evt.get("image", ""))
	if path != _path:
		_path = path
		_tex = null
		_loading = false
		if path != "" and ResourceLoader.exists(path):
			if ResourceLoader.load_threaded_request(path, "Texture2D") == OK:
				_loading = true
			else:
				_tex = load(path)


func _stage_vec(i: int) -> Vector3:
	if i >= _stages.size():
		return Vector3(0.5, 0.5, 1.0)
	var s: Dictionary = _stages[i]
	return Vector3(float(s.get("x", 0.5)), float(s.get("y", 0.5)), float(s.get("zoom", 1.0)))


func set_stage(evt: Dictionary) -> void:
	_stage = int(evt.get("stage", 1))
	_points = int(evt.get("points", 0))
	_timer = float(evt.get("window", 8.0))
	_timer_total = maxf(0.1, _timer)
	_of_players = int(evt.get("of", _of_players))
	_target_vis = 1.0
	# Stage 4 (safety net) keeps the stage-3 framing; the options do the work.
	_crop_target = _stage_vec(mini(_stage, 3) - 1)
	if evt.get("safety_net", false):
		_options = evt.get("options", [])


func add_lock(pid: String, stage: int, of: int) -> void:
	_locked[pid] = stage
	_of_players = of


func close_locks() -> void:
	_closed = true
	_timer = -1.0


func reveal(evt: Dictionary) -> void:
	_answer = str(evt.get("answer", ""))
	_outcome = evt.get("outcome", {})
	_reveal_t = _t
	_timer = -1.0
	_crop_target = Vector3(0.5, 0.5, 1.0)
	_target_vis = 1.0


func hide_board() -> void:
	_target_vis = 0.0


func is_showing() -> bool:
	return _target_vis > 0.0


# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_vis = move_toward(_vis, _target_vis, delta * 3.5)
	if _loading:
		var st := ResourceLoader.load_threaded_get_status(_path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_tex = ResourceLoader.load_threaded_get(_path)
			_loading = false
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loading = false
	if _tex != null:
		_static = move_toward(_static, 0.0, delta * 2.5)
	# Camera pull-back: ease the crop toward its target (zoom in log space feels like a dolly).
	var k := 1.0 - exp(-delta * (2.2 if _reveal_t < 0.0 else 1.6))
	var lz := lerpf(log(_crop.z), log(_crop_target.z), k)
	_crop = Vector3(lerpf(_crop.x, _crop_target.x, k), lerpf(_crop.y, _crop_target.y, k), exp(lz))
	if _timer > 0.0:
		_timer = maxf(0.0, _timer - delta)
	_net = move_toward(_net, 1.0 if (not _options.is_empty() and _reveal_t < 0.0) else 0.0, delta * 3.0)
	if _vis > 0.0 or _target_vis > 0.0:
		queue_redraw()


func _draw() -> void:
	if _vis <= 0.001:
		return
	var a := _vis
	# Backdrop: purple with slowly zooming concentric rings (the Hole motif).
	draw_rect(Rect2(0, 0, W, H), Color(0.13, 0.03, 0.2, 0.92 * a))
	var c := Vector2(W * 0.5, H * 0.45)
	for i in 14:
		var r := fmod(_t * 60.0 + i * 90.0, 1260.0)
		var col := Color("#ff4fa3") if i % 2 == 0 else Color("#3ec9c1")
		draw_arc(c, r, 0, TAU, 96, Color(col, 0.10 * a * (1.0 - r / 1260.0)), 26.0)
	# Monitor rect: shrinks upward when the safety net options appear.
	var mon := _lerp_rect(Rect2(220, 118, 1000, 750), Rect2(370, 96, 700, 525), _net)
	_draw_monitor(mon, a)
	_draw_title_tab(mon, a)
	if _reveal_t >= 0.0:
		_draw_reveal(mon, a)
	else:
		_draw_stage_lamps(mon, a)
		if _net > 0.01:
			_draw_options(a * _net)
		_draw_lock_strip(a)


func _draw_title_tab(mon: Rect2, a: float) -> void:
	var y := mon.position.y - 8
	var tab := PackedVector2Array([Vector2(mon.position.x + 10, y - 50), Vector2(mon.position.x + 470, y - 50), Vector2(mon.position.x + 500, y), Vector2(mon.position.x - 10, y)])
	draw_colored_polygon(tab, Color(0.98, 0.82, 0.25, a))
	var label := "HOLE %d OF %d" % [_round, _of]
	if _variant == "scale":
		label = "SCALE ROUND"
	elif _variant == "open":
		label = "NO SAFETY NET"
	draw_string(f_sans, Vector2(mon.position.x + 24, y - 14), label, HORIZONTAL_ALIGNMENT_LEFT, 460, 32, Color(0.18, 0.03, 0.22, a))
	var q := "HOW BIG IS THIS HOLE?" if _variant == "scale" else "WHAT IS THIS HOLE?"
	draw_string(f_sans_italic, Vector2(mon.end.x - 520, y - 14), q, HORIZONTAL_ALIGNMENT_RIGHT, 520, 32, Color(1, 1, 1, a))


func _draw_monitor(mon: Rect2, a: float) -> void:
	# chunky chrome bezel
	draw_rect(mon.grow(26), Color(0.08, 0.05, 0.12, a))
	_grad(mon.grow(20), Color(0.86, 0.87, 0.93, a), Color(0.42, 0.42, 0.5, a))
	draw_rect(mon.grow(6), Color(0.05, 0.05, 0.07, a))
	draw_rect(mon, Color(0.02, 0.02, 0.03, a))
	if _tex != null:
		var tw := float(_tex.get_width())
		var th := float(_tex.get_height())
		var z := maxf(1.0, _crop.z)
		# hand-held operator drift on close-ups only
		var drift := Vector2(sin(_t * 0.9), cos(_t * 0.7)) * 0.004 * clampf((z - 1.0) / 4.0, 0.0, 1.0)
		var sw := tw / z
		var sh := th / z
		var sx := clampf((_crop.x + drift.x) * tw - sw * 0.5, 0.0, tw - sw)
		var sy := clampf((_crop.y + drift.y) * th - sh * 0.5, 0.0, th - sh)
		draw_texture_rect_region(_tex, mon, Rect2(sx, sy, sw, sh), Color(1, 1, 1, a))
	if _static > 0.0 or _tex == null:
		var amt := 1.0 if _tex == null else _static
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_t * 30.0)
		for i in 90:
			var yy := mon.position.y + rng.randf() * mon.size.y
			draw_rect(Rect2(mon.position.x, yy, mon.size.x, rng.randf_range(2, 9)), Color(1, 1, 1, rng.randf_range(0.05, 0.35) * amt * a))
		if _tex == null:
			draw_string(f_mono, Vector2(mon.position.x, mon.get_center().y), "PLEASE STAND BY", HORIZONTAL_ALIGNMENT_CENTER, mon.size.x, 40, Color(1, 1, 1, a))
	# glass: scanlines + corner glare
	for i in int(mon.size.y / 6.0):
		draw_line(Vector2(mon.position.x, mon.position.y + i * 6.0), Vector2(mon.end.x, mon.position.y + i * 6.0), Color(0, 0, 0, 0.10 * a), 2.0)
	draw_colored_polygon(PackedVector2Array([mon.position, mon.position + Vector2(mon.size.x * 0.32, 0), mon.position + Vector2(0, mon.size.y * 0.42)]), Color(1, 1, 1, 0.05 * a))
	# REC-style zoom readout (bottom-left inside the monitor)
	if _reveal_t < 0.0:
		draw_string(f_mono, mon.position + Vector2(18, mon.size.y - 18), "ZOOM x%.1f" % _crop.z, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 0.6, 0.75 * a))


func _draw_stage_lamps(mon: Rect2, a: float) -> void:
	# Right-hand column: the four reveal stages and what a lock is worth.
	var vals := [1500, 1100, 750, 500]
	var x := mon.end.x + 46.0
	if _net > 0.5:
		x = mon.end.x + 60.0
	var n := _final_stage
	for i in n:
		var s := i + 1
		var r := Rect2(x, mon.position.y + 10 + i * 96, 150, 80)
		var lit := s == _stage
		var past := s < _stage
		var base := Color(0.25, 0.08, 0.32) if not lit else Color(1.0, 0.82, 0.2)
		if past:
			base = Color(0.12, 0.05, 0.15)
		var pulse := 0.85 + 0.15 * sin(_t * 8.0) if lit else 1.0
		_grad(r, Color(base.lightened(0.15) * pulse, a), Color(base.darkened(0.25), a))
		draw_rect(r, Color(0.85, 0.85, 0.95, a * (1.0 if lit else 0.5)), false, 3.0)
		var label := "LOOK %d" % s if s < 4 else "CHOICE"
		var txt_col := Color(0.18, 0.03, 0.22, a) if lit else Color(1, 1, 1, a * (0.35 if past else 0.85))
		draw_string(f_mono, r.position + Vector2(0, 28), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, txt_col)
		draw_string(f_sans, r.position + Vector2(0, 66), _fmt(vals[i]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 34, txt_col)
		if past:
			draw_line(r.position + Vector2(10, r.size.y * 0.55), r.end - Vector2(10, r.size.y * 0.45), Color(1, 0.3, 0.3, a * 0.8), 4.0)


func _draw_lock_strip(a: float) -> void:
	var y := 905.0 if _net < 0.5 else 632.0
	var bar := Rect2(220, y, 1000, 22)
	draw_rect(bar, Color(0, 0, 0, 0.6 * a))
	if _timer >= 0.0 and not _closed:
		var frac := _timer / _timer_total
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(Color("#3ec9c1").lerp(Color("#ff3b30"), 1.0 - frac), a))
	var msg := ""
	if _closed:
		msg = "LOCKS CLOSED"
	elif _stage > 0:
		msg = "LOCK IN NOW FOR %s" % _fmt(_points)
	draw_string(f_sans, Vector2(bar.position.x, bar.end.y + 50), msg, HORIZONTAL_ALIGNMENT_LEFT, 640, 42, Color(1, 0.88, 0.3, a))
	# who has locked (never what): podium-coloured chips with a padlock
	var x := bar.end.x
	draw_string(f_mono, Vector2(bar.end.x - 300, bar.end.y + 50), "LOCKED %d/%d" % [_locked.size(), _of_players], HORIZONTAL_ALIGNMENT_RIGHT, 300, 30, Color(1, 1, 1, a))
	var cx := bar.end.x - 330.0
	for pid in _locked.keys():
		cx -= 52.0
		var r := Rect2(cx, bar.end.y + 14, 46, 46)
		AvatarPainter.draw(self, r, players.get(pid, {}).get("avatar", {}))
		draw_rect(r, Color(1, 0.85, 0.3, a), false, 3.0)
		_padlock(r.end - Vector2(6, 6), a)


func _padlock(p: Vector2, a: float) -> void:
	draw_rect(Rect2(p - Vector2(10, 8), Vector2(20, 16)), Color(1, 0.85, 0.3, a))
	draw_arc(p - Vector2(0, 8), 7, PI, TAU, 12, Color(1, 0.85, 0.3, a), 3.0)


func _draw_options(a: float) -> void:
	for i in _options.size():
		var r := Rect2(90 + (i % 2) * 640, 720 + (i / 2) * 150, 620, 128)
		_grad(r, Color(0.2, 0.08, 0.36, a), Color(0.08, 0.03, 0.16, a))
		draw_rect(r, Color(0.82, 0.84, 0.92, a), false, 4.0)
		var dc := r.position + Vector2(60, r.size.y * 0.5)
		draw_circle(dc, 40, Color(0, 0, 0, 0.5 * a))
		draw_circle(dc, 36, Color(OPTION_COLOURS[i], a))
		draw_string(f_sans, dc + Vector2(-40, 16), LETTERS[i], HORIZONTAL_ALIGNMENT_CENTER, 80, 44, Color(1, 1, 1, a))
		var fs := 40 if str(_options[i]).length() < 20 else 32
		_shadow(f_sans, Vector2(r.position.x + 116, r.position.y + r.size.y * 0.5 + fs * 0.35), str(_options[i]).to_upper(), r.size.x - 130, fs, Color(1, 1, 1, a))


func _draw_reveal(mon: Rect2, a: float) -> void:
	var t := _t - _reveal_t
	var k := smoothstep(0.6, 1.1, t)
	if k <= 0.0:
		return
	# answer banner across the lower monitor
	var by := mon.end.y - 150.0
	var slide := (1.0 - k) * -1300.0
	var band := PackedVector2Array([Vector2(mon.position.x - 60 + slide, by), Vector2(mon.end.x + 40 + slide, by), Vector2(mon.end.x + 10 + slide, by + 112), Vector2(mon.position.x - 90 + slide, by + 112)])
	draw_polygon(band, PackedColorArray([Color("#c2185b"), Color("#4a148c"), Color("#311b92"), Color("#ad1457")]))
	draw_line(Vector2(mon.position.x - 60 + slide, by), Vector2(mon.end.x + 40 + slide, by), Color(0.95, 0.85, 0.5, a), 5.0)
	var txt := "IT'S " + _answer.to_upper()
	if _variant == "scale":
		txt = "SIZE: " + _answer.to_upper()
	var fs := 64 if txt.length() < 24 else 48
	_shadow(f_display, Vector2(mon.position.x + slide, by + 78), txt, mon.size.x, fs, Color(1, 1, 1, a), true)
	# results row: who locked what, when, and what it earned
	var ids: Array = _outcome.keys()
	if ids.is_empty():
		return
	var n := ids.size()
	var cw := minf(250.0, 1300.0 / n)
	var x0 := (W - cw * n) * 0.5
	for i in n:
		var pid: String = ids[i]
		var o: Dictionary = _outcome[pid]
		var appear := clampf((t - 1.2 - i * 0.12) * 4.0, 0.0, 1.0)
		if appear <= 0.0:
			continue
		var r := Rect2(x0 + i * cw + 6, 900 + (1.0 - appear) * 60, cw - 12, 150)
		var good: bool = o.get("correct", false)
		var part: bool = o.get("partial", false)
		var base := Color(0.1, 0.45, 0.2) if good else (Color(0.55, 0.42, 0.08) if part else Color(0.3, 0.08, 0.12))
		if str(o.get("label", "")) == "":
			base = Color(0.18, 0.18, 0.2)
		_grad(r, Color(base.lightened(0.15), a * appear), Color(base.darkened(0.3), a * appear))
		draw_rect(r, Color(1, 1, 1, 0.5 * a * appear), false, 2.0)
		var av := Rect2(r.position + Vector2(8, 8), Vector2(56, 56))
		AvatarPainter.draw(self, av, players.get(pid, {}).get("avatar", {}))
		var nm := str(players.get(pid, {}).get("name", "?")).to_upper()
		draw_string(f_sans, Vector2(av.end.x + 8, r.position.y + 34), nm, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 22, Color(1, 1, 1, a * appear))
		var st := int(o.get("stage", 0))
		var when := "NO LOCK" if st == 0 else ("LOOK %d" % st if st < 4 else "CHOICE")
		draw_string(f_mono, Vector2(av.end.x + 8, r.position.y + 62), when, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 20, Color(1, 0.9, 0.5, a * appear))
		var lab := str(o.get("label", ""))
		if lab != "":
			draw_string(f_sans, Vector2(r.position.x + 10, r.position.y + 100), lab.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 20, Color(1, 1, 1, 0.9 * a * appear))
		var pts := int(o.get("points", 0))
		draw_string(f_sans, Vector2(r.position.x + 10, r.position.y + 136), ("+" + _fmt(pts)) if pts > 0 else "0", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 30, Color(1, 0.85, 0.2, a * appear) if pts > 0 else Color(1, 1, 1, 0.5 * a * appear))


# ---------------------------------------------------------------------------

static func _lerp_rect(a: Rect2, b: Rect2, t: float) -> Rect2:
	return Rect2(a.position.lerp(b.position, t), a.size.lerp(b.size, t))


func _grad(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


func _shadow(font: Font, pos: Vector2, text: String, width: float, fs: int, col: Color, centre: bool = false) -> void:
	var align := HORIZONTAL_ALIGNMENT_CENTER if centre else HORIZONTAL_ALIGNMENT_LEFT
	for i in range(3, 0, -1):
		draw_string(font, pos + Vector2(i, i), text, align, width, fs, Color(0.12, 0.02, 0.18, 0.9 * col.a))
	draw_string_outline(font, pos, text, align, width, fs, 4, Color(0.05, 0.0, 0.1, col.a))
	draw_string(font, pos, text, align, width, fs, col)


static func _fmt(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
