class_name SketchBoard
extends Control
## TV graphic for POLICE SKETCH (CP5): an interview-room evidence board.
##   step   — case files being worked on (a folder per contestant, stamped when evidence is in);
##   reveal — one case at a time: the witness statement, then each drawing / description pinned
##            along a string, mutating as it goes; RECONSTRUCTED or MUTATED stamp;
##   vote   — all first drawings (BEST DRAWING) or the final statements (FUNNIEST MUTATION);
##   results— winners circled, Graham's Choice starred.
## Drawings are rendered from the same normalised stroke lists the phones send (0..1000).

const W := 1440.0
const H := 1080.0
const LETTERS := ["A", "B", "C", "D", "E", "F", "G", "H"]
const PAPER := Color("#f3efe4")
const INK := Color("#1b1b1f")
const TAG := Color("#f2d230")
const CORK := Color("#7a5a3a")

var f_display: Font
var f_sans: Font
var f_mono: Font
var f_hand: Font
var players := {}

var _vis := 0.0
var _target := 0.0
var _t := 0.0
var _phase_t := 0.0
var _phase := ""
var _order: Array = []
var _steps := 0
var _step := 0
var _step_kind := ""
var _timer := -1.0
var _timer_total := 1.0
var _done := {}
var _count := 0
var _count_of := 0
var _chains := {}            # index -> public chain
var _chain_i := -1
var _chain_of := 0
var _vote_cat := ""
var _vote_opts: Array = []
var _results := {}
var _exhibit: Array = []
var _card_dt := 2.0              # seconds between evidence cards (scaled with session time)


func _ready() -> void:
	f_display = load("res://assets/fonts/InterDisplay-BlackItalic.otf")
	f_sans = load("res://assets/fonts/LiberationSans-Bold.ttf")
	f_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")
	f_hand = load("res://assets/fonts/LiberationSerif-BoldItalic.ttf")
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func on_event(evt: Dictionary, time_scale: float) -> void:
	var ts := maxf(time_scale, 0.001)
	_card_dt = 2.0 / ts
	match str(evt.get("e")):
		"ps_show":
			_order = evt.get("order", [])
			_steps = int(evt.get("steps", 2))
			_chains = {}
			_results = {}
			_exhibit = evt.get("exhibit", [])
			_set_phase("exhibit" if not _exhibit.is_empty() else "step")
			_target = 1.0
		"ps_step":
			_set_phase("step")
			_step = int(evt.step)
			_step_kind = str(evt.kind)
			_timer = float(evt.window) / ts
			_timer_total = maxf(0.1, _timer)
			_count_of = int(evt.get("of", 0))
		"ps_progress", "ps_vote_progress":
			_done[str(evt.pid)] = true
			_count = int(evt.count)
			_count_of = int(evt.of)
		"ps_reveal_chain":
			_set_phase("reveal")
			_timer = -1.0
			_chain_i = int(evt.index)
			_chain_of = int(evt.of)
			_chains[_chain_i] = evt.chain
		"ps_vote_open":
			_set_phase("vote")
			_vote_cat = str(evt.category)
			_vote_opts = evt.get("options", [])
			_timer = float(evt.window) / ts
			_timer_total = maxf(0.1, _timer)
			_count_of = int(evt.get("of", 0))
		"ps_results":
			_set_phase("results")
			_timer = -1.0
			_results = evt


func _set_phase(p: String) -> void:
	_phase = p
	_phase_t = _t
	_done = {}
	_count = 0


func hide_board() -> void:
	_target = 0.0
	_vis = 0.0
	queue_redraw()


func is_showing() -> bool:
	return _target > 0.0


func _process(delta: float) -> void:
	_t += delta
	_vis = move_toward(_vis, _target, delta * 4.0)
	if _timer > 0.0:
		_timer = maxf(0.0, _timer - delta)
	if _vis > 0.0 or _target > 0.0:
		queue_redraw()


# ---------------------------------------------------------------------------

static func draw_strokes_on(ci: CanvasItem, r: Rect2, strokes: Array, col: Color, paper: Color) -> void:
	var sx := r.size.x / 1000.0
	var sy := r.size.y / 1000.0
	var sc := minf(sx, sy)
	for s in strokes:
		var p: Array = s.get("p", [])
		if p.size() < 2:
			continue
		var w: float = [6.0, 6.0, 14.0, 40.0][clampi(int(s.get("w", 1)), 1, 3)]
		if bool(s.get("e", false)):
			w = 40.0
		var c := paper if bool(s.get("e", false)) else col
		var pts := PackedVector2Array()
		for i in range(0, p.size() - 1, 2):
			pts.append(r.position + Vector2(float(p[i]) * sx, float(p[i + 1]) * sy))
		var width := maxf(1.5, w * sc)
		if pts.size() == 1:
			ci.draw_circle(pts[0], width * 0.5, c)
		else:
			ci.draw_polyline(pts, c, width, true)
			ci.draw_circle(pts[0], width * 0.5, c)
			ci.draw_circle(pts[pts.size() - 1], width * 0.5, c)


func _draw() -> void:
	if _vis <= 0.001:
		return
	var a := _vis
	draw_rect(Rect2(0, 0, W, H), Color(0.09, 0.1, 0.11, 0.95 * a))
	for i in 18:   # breeze-block wall
		for j in 12:
			draw_rect(Rect2(i * 80 + (40 if j % 2 else 0), j * 90, 76, 86), Color(1, 1, 1, 0.025 * a))
	_header(a)
	match _phase:
		"exhibit":
			_draw_exhibit(a)
		"step":
			_draw_folders(a)
		"reveal":
			_draw_chain(a)
		"vote":
			_draw_vote(a, false)
		"results":
			_draw_vote(a, true)


func _header(a: float) -> void:
	var tab := PackedVector2Array([Vector2(70, 40), Vector2(620, 40), Vector2(650, 96), Vector2(50, 96)])
	draw_colored_polygon(tab, Color(TAG, a))
	draw_string(f_sans, Vector2(76, 82), "POLICE SKETCH", HORIZONTAL_ALIGNMENT_LEFT, 560, 38, Color(0.08, 0.08, 0.08, a))
	var sub := ""
	match _phase:
		"step":
			sub = "%s · STAGE %d OF %d" % ["DRAWING" if _step_kind == "draw" else "WITNESS STATEMENTS", _step + 1, _steps]
		"reveal":
			sub = "CASE %d OF %d" % [_chain_i + 1, _chain_of]
		"vote", "results":
			sub = "FUNNIEST MUTATION" if _vote_cat == "funniest" else "BEST DRAWING"
		"exhibit":
			sub = "EXHIBIT · PREVIOUS INTERVIEW"
	draw_string(f_mono, Vector2(690, 80), sub, HORIZONTAL_ALIGNMENT_LEFT, 720, 28, Color(1, 1, 1, 0.9 * a))


func _name(pid: String) -> String:
	return str(players.get(pid, {}).get("name", "?")).to_upper()


func _paper(r: Rect2, a: float, tilt: float) -> void:
	draw_set_transform(r.get_center(), tilt, Vector2.ONE)
	var lr := Rect2(-r.size * 0.5, r.size)
	draw_rect(Rect2(lr.position + Vector2(8, 10), lr.size), Color(0, 0, 0, 0.5 * a))
	draw_rect(lr, Color(PAPER, a))
	draw_circle(Vector2(0, lr.position.y + 10), 9, Color(0.75, 0.1, 0.1, a))   # pin
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _text_in(r: Rect2, text: String, fs: int, col: Color, font: Font = null) -> void:
	var fnt := font if font != null else f_hand
	while fs > 14:
		var lines := _wrap(fnt, text, r.size.x, fs)
		var fits := lines.all(func(l): return fnt.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= r.size.x)
		if fits and lines.size() * fs * 1.15 <= r.size.y:
			var y := r.position.y + (r.size.y - lines.size() * fs * 1.15) * 0.5 + fs * 0.9
			for l in lines:
				draw_string(fnt, Vector2(r.position.x, y), l, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)
				y += fs * 1.15
			return
		fs -= 2
	draw_string(fnt, r.position + Vector2(0, 20), text.substr(0, 60), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, col)


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


func _timer_bar(rect: Rect2, a: float, label: String) -> void:
	if _timer < 0.0:
		return
	draw_rect(rect, Color(0, 0, 0, 0.6 * a))
	var frac := _timer / _timer_total
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * frac, rect.size.y)), Color(TAG.lerp(Color("#ff3b30"), 1.0 - frac), a))
	draw_string(f_mono, Vector2(rect.end.x - 120, rect.position.y - 10), "%2d" % int(ceil(_timer)), HORIZONTAL_ALIGNMENT_RIGHT, 120, 30, Color(1, 1, 1, a))
	if _count_of > 0:
		draw_string(f_mono, Vector2(rect.position.x, rect.position.y - 10), "%s: %d/%d" % [label, _count, _count_of], HORIZONTAL_ALIGNMENT_LEFT, 700, 26, Color(TAG, a))


func _draw_exhibit(a: float) -> void:
	var r := Rect2(W * 0.5 - 300, 160, 600, 600)
	_paper(r, a, -0.03)
	draw_set_transform(r.get_center(), -0.03, Vector2.ONE)
	draw_strokes_on(self, Rect2(-r.size * 0.5 + Vector2(30, 40), r.size - Vector2(60, 70)), _exhibit, Color(INK, a), Color(PAPER, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_string(f_mono, Vector2(0, 850), "EXHIBIT %03d · ORIGIN UNKNOWN" % (absi(_exhibit.size() * 37) % 1000), HORIZONTAL_ALIGNMENT_CENTER, W, 30, Color(TAG, a))


func _draw_folders(a: float) -> void:
	var n := _order.size()
	if n == 0:
		return
	var cols := mini(4, n)
	var rows := int(ceil(float(n) / cols))
	var fw := 280.0
	var fh := 250.0 if rows > 1 else 330.0
	var x0 := W * 0.5 - (cols * fw + (cols - 1) * 40) * 0.5
	for i in n:
		var pid := str(_order[i])
		var r := Rect2(x0 + (i % cols) * (fw + 40), 170 + (i / cols) * (fh + 50), fw, fh)
		var done := _done.has(pid)
		draw_rect(Rect2(r.position + Vector2(0, -22), Vector2(120, 26)), Color("#c9a35a", a))
		draw_rect(r, Color(Color("#d9b46a") if done else Color("#8e7647"), a))
		draw_string(f_mono, r.position + Vector2(10, -3), "CASE %d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, 120, 18, Color(0.15, 0.1, 0.05, a))
		var av := Rect2(r.position + Vector2(fw * 0.5 - 50, 34), Vector2(100, 100))
		AvatarPainter.draw(self, av, players.get(pid, {}).get("avatar", {}))
		draw_string(f_sans, Vector2(r.position.x, av.end.y + 36), _name(pid), HORIZONTAL_ALIGNMENT_CENTER, fw, 26, Color(0.1, 0.07, 0.03, a))
		if done:
			draw_set_transform(r.get_center() + Vector2(0, fh * 0.32), -0.18, Vector2.ONE)
			draw_rect(Rect2(-110, -24, 220, 48), Color(0.75, 0.08, 0.08, 0.9 * a), false, 4.0)
			draw_string(f_sans, Vector2(-110, 12), "SUBMITTED", HORIZONTAL_ALIGNMENT_CENTER, 220, 30, Color(0.75, 0.08, 0.08, 0.9 * a))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var hint := "DRAW WHAT THE WITNESS SAYS" if _step_kind == "draw" else "DESCRIBE THE DRAWING ON YOUR UNIT"
	draw_string(f_display, Vector2(0, 930), hint, HORIZONTAL_ALIGNMENT_CENTER, W, 44, Color(1, 1, 1, a))
	_timer_bar(Rect2(110, 990, W - 220, 18), a, "EVIDENCE IN")


func _draw_chain(a: float) -> void:
	var ch: Dictionary = _chains.get(_chain_i, {})
	if ch.is_empty():
		return
	var steps: Array = ch.get("steps", [])
	var cards := 1 + steps.size()
	var cw := minf(300.0, (W - 120 - (cards - 1) * 24) / cards)
	var ch_h := cw * 1.25
	var x0 := W * 0.5 - (cards * cw + (cards - 1) * 24) * 0.5
	var y := 300.0
	var rt := _t - _phase_t
	# the string the evidence hangs on
	draw_line(Vector2(40, y - 30), Vector2(W - 40, y - 30), Color(0.75, 0.1, 0.1, 0.8 * a), 3.0)
	for k in cards:
		var appear := clampf((rt - k * _card_dt) / (_card_dt * 0.33), 0.0, 1.0)
		if appear <= 0.0:
			continue
		var ca := a * appear
		var r := Rect2(x0 + k * (cw + 24), y + (1.0 - appear) * 40.0, cw, ch_h)
		var tilt: float = [-0.03, 0.02, -0.015, 0.025, -0.02][k % 5]
		_paper(r, ca, tilt)
		var inner := r.grow(-18)
		if k == 0:
			draw_string(f_mono, r.position + Vector2(14, 40), "WITNESS STATEMENT" if str(ch.get("variant", "")) != "body_part" else "GRAHAM'S DESCRIPTION", HORIZONTAL_ALIGNMENT_LEFT, cw - 20, 16, Color(0.6, 0.1, 0.1, ca))
			_text_in(Rect2(inner.position + Vector2(0, 34), inner.size - Vector2(0, 34)), "“%s”" % str(ch.get("prompt", "")), 34, Color(INK, ca))
			continue
		var e: Dictionary = steps[k - 1]
		if bool(e.get("missing", false)):
			_text_in(inner, "NO EVIDENCE SUBMITTED", 26, Color(0.6, 0.1, 0.1, ca), f_mono)
		elif str(e.kind) == "draw":
			draw_strokes_on(self, Rect2(inner.position + Vector2(0, 6), Vector2(inner.size.x, inner.size.x)), e.get("strokes", []), Color(INK, ca), Color(PAPER, ca))
		else:
			_text_in(inner, "“%s”" % str(e.get("text", "")), 34, Color(Color("#1d2a6b"), ca))
		var av := Rect2(Vector2(r.position.x + 8, r.end.y + 14), Vector2(54, 54))
		AvatarPainter.draw(self, av, players.get(str(e.pid), {}).get("avatar", {}))
		draw_string(f_sans, Vector2(av.end.x + 8, av.position.y + 36), _name(str(e.pid)), HORIZONTAL_ALIGNMENT_LEFT, cw - 70, 22, Color(1, 1, 1, ca))
	var stamp_t := (rt - cards * _card_dt) / (_card_dt * 0.5)
	if stamp_t > 0.0:
		var good := bool(ch.get("reconstructed", false))
		var sa := a * clampf(stamp_t * 4.0, 0.0, 1.0)
		var scale := 1.0 + 0.6 * exp(-stamp_t * 8.0)
		draw_set_transform(Vector2(W * 0.5, 870), -0.08, Vector2(scale, scale))
		var col := Color(0.1, 0.55, 0.2, sa) if good else Color(0.8, 0.1, 0.1, sa)
		draw_rect(Rect2(-300, -50, 600, 100), col, false, 6.0)
		draw_string(f_sans, Vector2(-300, 22), "RECONSTRUCTED" if good else "MUTATED", HORIZONTAL_ALIGNMENT_CENTER, 600, 64, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_string(f_mono, Vector2(0, 960), "FIDELITY %d%%" % int(round(float(ch.get("fidelity", 0.0)) * 100.0)), HORIZONTAL_ALIGNMENT_CENTER, W, 28, Color(1, 1, 1, sa))


func _draw_vote(a: float, results: bool) -> void:
	var opts: Array = _vote_opts
	if results:
		opts = (_results.get("options", {}) as Dictionary).get(_vote_cat, opts) if not _results.is_empty() else opts
	var n := opts.size()
	if n == 0:
		return
	var winner := int(_results.get(_vote_cat, -1)) if results else -1
	var gc := int(_results.get("graham_choice", -1)) if results and _vote_cat == "drawing" else -1
	if _vote_cat == "drawing":
		var cols := mini(4, n)
		var rows := int(ceil(float(n) / cols))
		var cw := minf(290.0, (W - 160 - (cols - 1) * 30) / cols)
		var chh := minf(cw * 1.1, (780.0 - (rows - 1) * 40) / rows)
		var x0 := W * 0.5 - (cols * cw + (cols - 1) * 30) * 0.5
		for i in n:
			var o = opts[i]
			var r := Rect2(x0 + (i % cols) * (cw + 30), 150 + (i / cols) * (chh + 40), cw, chh)
			_paper(r, a, [-0.02, 0.015, -0.01, 0.02][i % 4])
			var ch: Dictionary = _chains.get(int(o.get("chain", -1)) if typeof(o) == TYPE_DICTIONARY else -1, {})
			var st: Array = ch.get("steps", [])
			var k := int(o.get("step_i", 0)) if typeof(o) == TYPE_DICTIONARY else 0
			if k < st.size():
				var side := minf(r.size.x, r.size.y) - 40
				draw_strokes_on(self, Rect2(r.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)), st[k].get("strokes", []), Color(INK, a), Color(PAPER, a))
			draw_rect(Rect2(r.position + Vector2(8, 8), Vector2(40, 40)), Color(TAG, a))
			draw_string(f_sans, r.position + Vector2(8, 40), LETTERS[i % 8], HORIZONTAL_ALIGNMENT_CENTER, 40, 30, Color(0.1, 0.1, 0.1, a))
			_marks(r, i, winner, gc, a)
	else:
		for i in n:
			var label: String = str(opts[i].get("label", "")) if typeof(opts[i]) == TYPE_DICTIONARY else str(opts[i])
			var r := Rect2(140, 150 + i * minf(96.0, 760.0 / n), W - 280, minf(84.0, 760.0 / n - 12))
			draw_rect(r, Color(PAPER, a))
			draw_rect(Rect2(r.position, Vector2(60, r.size.y)), Color(TAG, a))
			draw_string(f_sans, r.position + Vector2(0, r.size.y * 0.5 + 12), LETTERS[i % 8], HORIZONTAL_ALIGNMENT_CENTER, 60, 34, Color(0.1, 0.1, 0.1, a))
			draw_string(f_hand, r.position + Vector2(80, r.size.y * 0.5 + 12), label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 100, 32, Color(INK, a))
			_marks(r, i, winner, -1, a)
	if not results:
		_timer_bar(Rect2(110, 1000, W - 220, 16), a, "VOTES IN")


func _marks(r: Rect2, i: int, winner: int, gc: int, a: float) -> void:
	if i == winner:
		var pulse := 0.7 + 0.3 * sin(_t * 6.0)
		draw_arc(r.get_center(), maxf(r.size.x, r.size.y) * 0.56, 0, TAU, 64, Color(0.85, 0.1, 0.1, a * pulse), 6.0)
	if i == gc:
		var c := Vector2(r.end.x - 24, r.position.y + 24)
		var pts := PackedVector2Array()
		for k in 10:
			var ang := -PI / 2 + k * PI / 5
			pts.append(c + Vector2(cos(ang), sin(ang)) * (22.0 if k % 2 == 0 else 10.0))
		draw_colored_polygon(pts, Color(0.85, 0.12, 0.2, a))
