class_name BasementBoard
extends Control
## TV graphic for THE BASEMENT (CP7): a case file under a bare bulb.
##   case/discuss — the setup on a typed case sheet, the investigation budget (used ones crossed out
##                  with who used them), READY lamps per contestant, the discussion clock;
##   theory       — the questions and THEORIES FILED count;
##   reveal       — per question: how the group split (AGREED / SPLIT), the best-supported answer,
##                  then WHAT HAPPENED, with an UNRESOLVED stamp for open cases.

const W := 1440.0
const H := 1080.0
const PAPER := Color("#ece4cf")
const INK := Color("#26221c")
const AMBER := Color("#e0a040")

var f_display: Font
var f_sans: Font
var f_mono: Font
var f_serif: Font
var players := {}

var _vis := 0.0
var _target := 0.0
var _t := 0.0
var _phase_t := 0.0
var _phase := ""
var _title := ""
var _setup := ""
var _location := ""
var _invs: Array = []
var _inv_used := {}            # label -> pid
var _inv_limit := 2
var _order: Array = []
var _ready_pids := {}
var _questions: Array = []
var _filed := 0
var _of := 0
var _timer := -1.0
var _timer_total := 1.0
var _reveal := {}
var _step_dt := 2.5


func _ready() -> void:
	f_display = load("res://assets/fonts/InterDisplay-BlackItalic.otf")
	f_sans = load("res://assets/fonts/LiberationSans-Bold.ttf")
	f_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")
	f_serif = load("res://assets/fonts/LiberationSerif-BoldItalic.ttf")
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func on_event(evt: Dictionary, time_scale: float) -> void:
	var ts := maxf(time_scale, 0.001)
	_step_dt = 2.5 / ts
	match str(evt.get("e")):
		"bas_case":
			_title = str(evt.title)
			_setup = str(evt.setup)
			_location = str(evt.get("location", ""))
			_invs = evt.get("investigations", [])
			_inv_limit = int(evt.get("inv_limit", 2))
			_order = evt.get("players", [])
			_inv_used = {}
			_ready_pids = {}
			_reveal = {}
			_filed = 0
			_set_phase("case")
			_target = 1.0
		"bas_discuss":
			_set_phase("discuss")
			_timer = float(evt.window) / ts
			_timer_total = maxf(0.1, _timer)
			_of = int(evt.get("of", 0))
		"bas_investigated":
			_inv_used[str(evt.label)] = str(evt.pid)
		"bas_ready":
			_ready_pids[str(evt.pid)] = true
		"bas_theory":
			_set_phase("theory")
			_questions = evt.get("questions", [])
			_timer = float(evt.window) / ts
			_timer_total = maxf(0.1, _timer)
			_of = int(evt.get("of", 0))
		"bas_theory_in":
			_filed = int(evt.count)
			_of = int(evt.of)
		"bas_reveal":
			_set_phase("reveal")
			_reveal = evt
			_timer = -1.0


func _set_phase(p: String) -> void:
	_phase = p
	_phase_t = _t


func hide_board() -> void:
	_target = 0.0
	_vis = 0.0
	queue_redraw()


func is_showing() -> bool:
	return _target > 0.0


func _process(delta: float) -> void:
	_t += delta
	_vis = move_toward(_vis, _target, delta * 3.0)
	if _timer > 0.0:
		_timer = maxf(0.0, _timer - delta)
	if _vis > 0.0 or _target > 0.0:
		queue_redraw()


func _name(pid: String) -> String:
	return str(players.get(pid, {}).get("name", "?")).to_upper()


func _wrap(font: Font, text: String, width: float, fs: int) -> Array:
	var out: Array = []
	var cur := ""
	for word in text.split(" ", false):
		var trial := word if cur == "" else cur + " " + word
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and cur != "":
			out.append(cur)
			cur = word
		else:
			cur = trial
	if cur != "":
		out.append(cur)
	return out


func _para(font: Font, text: String, pos: Vector2, width: float, fs: int, col: Color, max_lines := 99) -> float:
	var lines := _wrap(font, text, width, fs)
	var y := pos.y
	for i in mini(lines.size(), max_lines):
		draw_string(font, Vector2(pos.x, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, width, fs, col)
		y += fs * 1.3
	return y


func _draw() -> void:
	if _vis <= 0.001:
		return
	var a := _vis
	draw_rect(Rect2(0, 0, W, H), Color(0.05, 0.045, 0.04, 0.97 * a))
	# bare bulb pool of light
	var flick := 0.92 + 0.08 * sin(_t * 23.0) * sin(_t * 3.1)
	for i in 8:
		draw_circle(Vector2(W * 0.5, 120), 900.0 - i * 100.0, Color(1, 0.75, 0.4, 0.018 * a * flick))
	draw_string(f_mono, Vector2(80, 80), "THE BASEMENT", HORIZONTAL_ALIGNMENT_LEFT, 600, 30, Color(AMBER, a))
	if _location != "":
		draw_string(f_mono, Vector2(0, 80), "LOCATION: " + _location.to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, W - 260, 22, Color(0.75, 0.7, 0.6, a))
	match _phase:
		"case", "discuss":
			_draw_case(a)
		"theory":
			_draw_theory(a)
		"reveal":
			_draw_reveal(a)


func _sheet(r: Rect2, a: float, tilt: float) -> void:
	draw_set_transform(r.get_center(), tilt, Vector2.ONE)
	var lr := Rect2(-r.size * 0.5, r.size)
	draw_rect(Rect2(lr.position + Vector2(10, 12), lr.size), Color(0, 0, 0, 0.55 * a))
	draw_rect(lr, Color(PAPER, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_case(a: float) -> void:
	var r := Rect2(110, 120, W - 220, 470)
	_sheet(r, a, -0.006)
	draw_string(f_mono, r.position + Vector2(40, 54), "CASE FILE", HORIZONTAL_ALIGNMENT_LEFT, 400, 24, Color(0.6, 0.12, 0.1, a))
	draw_string(f_sans, r.position + Vector2(40, 120), _title, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 48, Color(INK, a))
	_para(f_serif, _setup, r.position + Vector2(40, 190), r.size.x - 80, 36, Color(INK, a), 7)
	# investigations budget
	var y := 640.0
	draw_string(f_mono, Vector2(110, y), "INVESTIGATIONS: %d OF %d USED" % [_inv_used.size(), _inv_limit], HORIZONTAL_ALIGNMENT_LEFT, 800, 26, Color(AMBER, a))
	y += 50
	for lab in _invs:
		var used := _inv_used.has(str(lab))
		var col := Color(0.55, 0.52, 0.48, a) if used else Color(0.95, 0.92, 0.85, a)
		draw_string(f_sans, Vector2(130, y), str(lab), HORIZONTAL_ALIGNMENT_LEFT, 700, 30, col)
		if used:
			var w := f_sans.get_string_size(str(lab), HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			draw_line(Vector2(126, y - 10), Vector2(134 + w, y - 10), Color(0.8, 0.15, 0.1, a), 4.0)
			draw_string(f_mono, Vector2(150 + w, y), "— " + _name(_inv_used[str(lab)]), HORIZONTAL_ALIGNMENT_LEFT, 400, 22, Color(0.8, 0.7, 0.5, a))
		y += 46
	# ready lamps
	var x := W - 110 - _order.size() * 92
	for pid in _order:
		var c := Vector2(x + 46, 700)
		AvatarPainter.draw(self, Rect2(c - Vector2(36, 36), Vector2(72, 72)), players.get(str(pid), {}).get("avatar", {}))
		draw_circle(c + Vector2(0, 64), 12, Color(0.3, 0.95, 0.4, a) if _ready_pids.has(str(pid)) else Color(0.25, 0.22, 0.2, a))
		x += 92
	draw_string(f_mono, Vector2(W - 110 - _order.size() * 92, 800), "READY TO FILE", HORIZONTAL_ALIGNMENT_LEFT, 400, 20, Color(0.75, 0.7, 0.6, a))
	if _phase == "discuss":
		_clock(a, "DISCUSS IT OUT LOUD")


func _clock(a: float, label: String) -> void:
	if _timer < 0.0:
		return
	var br := Rect2(110, 990, W - 220, 14)
	draw_rect(br, Color(0.15, 0.13, 0.1, a))
	draw_rect(Rect2(br.position, Vector2(br.size.x * _timer / _timer_total, br.size.y)), Color(AMBER, a))
	draw_string(f_mono, Vector2(110, 975), label, HORIZONTAL_ALIGNMENT_LEFT, 800, 24, Color(0.9, 0.85, 0.75, a))
	var s := int(ceil(_timer))
	draw_string(f_mono, Vector2(0, 975), "%d:%02d" % [s / 60, s % 60], HORIZONTAL_ALIGNMENT_RIGHT, W - 110, 30, Color(1, 1, 1, a))


func _draw_theory(a: float) -> void:
	draw_string(f_display, Vector2(0, 220), "FILE YOUR THEORY", HORIZONTAL_ALIGNMENT_CENTER, W, 80, Color(1, 1, 1, a))
	var y := 340.0
	for q in _questions:
		draw_string(f_sans, Vector2(0, y), str(q), HORIZONTAL_ALIGNMENT_CENTER, W, 44, Color(PAPER, a))
		y += 80
	draw_string(f_mono, Vector2(0, y + 60), "THEORIES FILED: %d / %d" % [_filed, _of], HORIZONTAL_ALIGNMENT_CENTER, W, 34, Color(AMBER, a))
	_clock(a, "EACH OF YOU, PRIVATELY")


func _draw_reveal(a: float) -> void:
	var qs: Array = _reveal.get("questions", [])
	var tallies: Dictionary = _reveal.get("tallies", {})
	var best: Dictionary = _reveal.get("best", {})
	var agreed: Dictionary = _reveal.get("agreed", {})
	var rt := _t - _phase_t
	var y := 130.0
	var qh := minf(260.0, 560.0 / maxf(1, qs.size()))
	for i in qs.size():
		var q: Dictionary = qs[i]
		var appear := clampf((rt - i * _step_dt) / (_step_dt * 0.3), 0.0, 1.0)
		if appear <= 0.0:
			continue
		var ca := a * appear
		draw_string(f_sans, Vector2(110, y + 34), str(q.ask), HORIZONTAL_ALIGNMENT_LEFT, 900, 32, Color(PAPER, ca))
		var ag := bool(agreed.get(q.id, false))
		draw_string(f_mono, Vector2(0, y + 34), "AGREED" if ag else "SPLIT", HORIZONTAL_ALIGNMENT_RIGHT, W - 110, 26, Color(0.4, 0.9, 0.5, ca) if ag else Color(1, 0.6, 0.2, ca))
		var opts: Array = q.options
		var t: Array = tallies.get(q.id, [])
		var total := 0
		for v in t:
			total += int(v)
		var show_best := rt > i * _step_dt + _step_dt * 0.8
		var bw := (W - 220 - (opts.size() - 1) * 12) / opts.size()
		for k in opts.size():
			var r := Rect2(110 + k * (bw + 12), y + 56, bw, qh - 80)
			var is_best := show_best and int(best.get(q.id, -1)) == k
			draw_rect(r, Color(0.16, 0.14, 0.12, ca))
			var frac := float(t[k]) / maxf(1.0, total) if k < t.size() else 0.0
			draw_rect(Rect2(Vector2(r.position.x, r.end.y - r.size.y * frac), Vector2(r.size.x, r.size.y * frac)), Color(AMBER.darkened(0.3), 0.7 * ca))
			if is_best:
				draw_rect(r.grow(4), Color(0.4, 0.95, 0.5, ca), false, 5.0)
			var lines := _wrap(f_sans, str(opts[k]), r.size.x - 20, 22)
			var ly := r.position.y + 34
			for l in lines.slice(0, 3):
				draw_string(f_sans, Vector2(r.position.x + 10, ly), l, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 22, Color(1, 1, 1, ca))
				ly += 28
			if k < t.size() and int(t[k]) > 0:
				draw_string(f_mono, Vector2(r.position.x, r.end.y - 12), "%d" % int(t[k]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 30, Color(1, 1, 1, ca))
		y += qh
	var wt := rt - qs.size() * _step_dt
	if wt > 0.0:
		var wa := a * clampf(wt / (_step_dt * 0.4), 0.0, 1.0)
		var r2 := Rect2(110, 720, W - 220, 250)
		_sheet(r2, wa, 0.004)
		draw_string(f_mono, r2.position + Vector2(30, 44), "WHAT HAPPENED", HORIZONTAL_ALIGNMENT_LEFT, 600, 24, Color(0.6, 0.12, 0.1, wa))
		_para(f_serif, str(_reveal.get("reveal", "")), r2.position + Vector2(30, 94), r2.size.x - 60, 30, Color(INK, wa), 5)
		if bool(_reveal.get("unresolved", false)) and wt > _step_dt:
			draw_set_transform(Vector2(W - 300, 712), -0.12, Vector2.ONE)
			draw_rect(Rect2(-190, -40, 380, 80), Color(0.75, 0.1, 0.1, wa), false, 5.0)
			draw_string(f_sans, Vector2(-190, 18), "UNRESOLVED", HORIZONTAL_ALIGNMENT_CENTER, 380, 48, Color(0.75, 0.1, 0.1, wa))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
