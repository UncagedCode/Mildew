class_name QuizBoard
extends Control
## TV graphic for Real or Mildew? ("claims") and Guess the Genitals ("image") — CP3.
## claims: a teletext-style dossier of four stacked claims; the reveal stamps each REAL / MILDEW.
## image:  a clinical "SPECIMEN" lightbox with the photograph, catalogue number and four candidate
##         species; the reveal names the animal. Both end with a VIEWER INFORMATION fact card
##         (short explanation only; sources live in the Viewer Information Service — docs/07).
## Readability first (docs/01): options, timer and stamps never glitch.

const W := 1440.0
const H := 1080.0
const LETTERS := ["A", "B", "C", "D"]
const OPTION_COLOURS := [Color("#c7362b"), Color("#e2b42c"), Color("#3f9a45"), Color("#2e5fae")]

var f_display: Font
var f_sans: Font
var f_sans_reg: Font
var f_mono: Font
var players := {}

var layout := ""
var _vis := 0.0
var _target := 0.0
var _t := 0.0
var _title := ""
var _prompt := ""
var _options: Array = []
var _variant := ""
var _round := 0
var _of := 0
var _final := false
var _confidence := false
var _category := ""
var _timer := -1.0
var _timer_total := 1.0
var _answered := 0
var _answer_of := 0
var _correct := -1
var _reveal_t := -1.0
var _stamps: Array = []
var _picks := {}                    # option -> [pid]
var _certain := {}
var _fact := ""
var _answer_label := ""
var _path := ""
var _tex: Texture2D = null
var _loading := false
var _crop := {}                     # {x, y, zoom} framing while answering (image layout)
var _zoom := 1.0


func _ready() -> void:
	f_display = load("res://assets/fonts/InterDisplay-BlackItalic.otf")
	f_sans = load("res://assets/fonts/LiberationSans-Bold.ttf")
	f_sans_reg = load("res://assets/fonts/LiberationSans-Regular.ttf")
	f_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_question(evt: Dictionary) -> void:
	layout = str(evt.get("layout", "claims"))
	_title = str(evt.get("title", ""))
	_prompt = str(evt.get("prompt", ""))
	_options = evt.get("options", [])
	_variant = str(evt.get("variant", ""))
	_round = int(evt.get("round", 0))
	_of = int(evt.get("of", 0))
	_final = bool(evt.get("final", false))
	_confidence = bool(evt.get("confidence", false))
	_category = str(evt.get("category", ""))
	_crop = evt.get("crop", {})
	_timer = -1.0
	_answered = 0
	_correct = -1
	_reveal_t = -1.0
	_stamps = []
	_picks = {}
	_certain = {}
	_fact = ""
	_answer_label = ""
	_target = 1.0
	_zoom = float(_crop.get("zoom", 1.0)) if not _crop.is_empty() else 1.0
	var img := str(evt.get("image", ""))
	if img != _path:
		_path = img
		_tex = null
		if img != "" and ResourceLoader.exists(img):
			_loading = ResourceLoader.load_threaded_request(img) == OK
			if not _loading:
				_tex = load(img)


func start_timer(seconds: float) -> void:
	_timer = seconds
	_timer_total = maxf(0.1, seconds)


func stop_timer() -> void:
	_timer = -1.0


func set_answered(n: int, of: int) -> void:
	_answered = n
	_answer_of = of


func reveal(evt: Dictionary) -> void:
	_correct = int(evt.get("correct", -1))
	_stamps = evt.get("stamps", [])
	_fact = str(evt.get("fact", ""))
	_answer_label = str(evt.get("answer_label", ""))
	_certain = evt.get("certain", {})
	_timer = -1.0
	_reveal_t = _t
	_picks = {}
	var picks: Dictionary = evt.get("picks", {})
	for pid in picks:
		var c := int(picks[pid])
		if not _picks.has(c):
			_picks[c] = []
		_picks[c].append(pid)


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
	if _loading:
		var st := ResourceLoader.load_threaded_get_status(_path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_tex = ResourceLoader.load_threaded_get(_path)
			_loading = false
		elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_loading = false
	# The specimen is shown cropped while answering; the reveal pulls back to the whole picture.
	var zt := 1.0 if (_reveal_t >= 0.0 or _crop.is_empty()) else float(_crop.get("zoom", 1.0))
	_zoom = lerpf(_zoom, zt, 1.0 - exp(-delta * 2.0))
	if _vis > 0.0 or _target > 0.0:
		queue_redraw()


# ---------------------------------------------------------------------------

func _draw() -> void:
	if _vis <= 0.001:
		return
	match layout:
		"image":
			_draw_image_layout(_vis)
		_:
			_draw_claims_layout(_vis)
	if _fact != "" and _reveal_t >= 0.0:
		_draw_fact(_vis)


func _grad(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bottom, bottom]))


func _shadow(font: Font, pos: Vector2, text: String, width: float, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, depth := 3) -> void:
	for i in range(depth, 0, -1):
		draw_string(font, pos + Vector2(i, i), text, align, width, fs, Color(0.08, 0.02, 0.12, 0.9 * col.a))
	draw_string(font, pos, text, align, width, fs, col)


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


func _header(a: float, accent: Color) -> void:
	# title tab + round counter + the round instruction
	var tab := PackedVector2Array([Vector2(70, 46), Vector2(620, 46), Vector2(650, 98), Vector2(50, 98)])
	draw_colored_polygon(tab, Color(accent, a))
	draw_string(f_sans, Vector2(76, 86), _title, HORIZONTAL_ALIGNMENT_LEFT, 560, 38, Color(0.1, 0.02, 0.14, a))
	var rc := "FINAL QUESTION" if _final else ("%d / %d" % [_round, _of] if _of > 0 else "")
	draw_string(f_mono, Vector2(W - 560, 86), rc, HORIZONTAL_ALIGNMENT_RIGHT, 480, 32, Color(1, 1, 1, a))
	if _confidence and _reveal_t < 0.0:
		var pulse := 0.6 + 0.4 * sin(_t * 5.0)
		draw_string(f_mono, Vector2(W - 560, 126), "CONFIDENCE ROUND", HORIZONTAL_ALIGNMENT_RIGHT, 480, 26, Color(1, 0.85, 0.2, a * pulse))


func _timer_bar(rect: Rect2, a: float) -> void:
	draw_rect(rect, Color(0, 0, 0, 0.6 * a))
	if _timer >= 0.0:
		var frac := _timer / _timer_total
		var col := Color("#3ec9c1").lerp(Color("#ff3b30"), 1.0 - frac)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * frac, rect.size.y)), Color(col, a))
		draw_string(f_mono, Vector2(rect.end.x - 120, rect.end.y + 34), "%2d" % int(ceil(_timer)), HORIZONTAL_ALIGNMENT_RIGHT, 120, 34, Color(1, 1, 1, a))
	if _answer_of > 0 and _correct < 0:
		draw_string(f_mono, Vector2(rect.position.x, rect.end.y + 34), "ANSWERS IN: %d/%d" % [_answered, _answer_of], HORIZONTAL_ALIGNMENT_LEFT, 600, 28, Color(1, 0.85, 0.3, a))


func _chips(i: int, right_edge: float, y: float, a: float) -> void:
	if not _picks.has(i):
		return
	var x := right_edge
	for pid in _picks[i]:
		x -= 52.0
		var r := Rect2(Vector2(x, y), Vector2(46, 46))
		AvatarPainter.draw(self, r, players.get(pid, {}).get("avatar", {}))
		draw_rect(r, Color(1, 0.85, 0.3, a) if _certain.has(pid) else Color(1, 1, 1, a), false, 3.0 if _certain.has(pid) else 2.0)


# ---------------------------------------------------------------------------
# Real or Mildew? — the claims dossier
# ---------------------------------------------------------------------------

func _draw_claims_layout(a: float) -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.03, 0.1, 0.9 * a))
	for i in 30:   # faint teletext scan texture
		draw_rect(Rect2(0, i * 36, W, 2), Color(0.3, 0.4, 1.0, 0.04 * a))
	_header(a, Color(0.35, 0.95, 0.55))
	var pr := Rect2(50, 120, W - 100, 92)
	draw_rect(pr, Color(0.0, 0.0, 0.55, 0.95 * a))
	draw_rect(pr, Color(1, 1, 0.3, 0.8 * a), false, 3.0)
	var plines := _wrap(f_sans, _prompt, pr.size.x - 40, 38)
	var py := pr.position.y + pr.size.y * 0.5 - (plines.size() - 1) * 22 + 13
	for l in plines:
		draw_string(f_sans, Vector2(pr.position.x, py), l, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 38, Color(1, 1, 0.35, a))
		py += 44
	var top := 236.0
	var rh := 166.0
	for i in _options.size():
		var r := Rect2(50, top + i * (rh + 14), W - 100, rh)
		var dim := 1.0
		var good := false
		if _correct >= 0:
			good = i == _correct
			dim = 1.0 if good else 0.55
		var base := Color(0.08, 0.1, 0.32).lerp(Color(0.08, 0.42, 0.16), 1.0 if good else 0.0)
		_grad(r, Color(base.lightened(0.12), 0.97 * a * dim), Color(base.darkened(0.3), 0.97 * a * dim))
		draw_rect(r, Color(0.8, 0.84, 0.95, a * dim), false, 3.0)
		var dc := r.position + Vector2(56, r.size.y * 0.5)
		draw_circle(dc, 36, Color(OPTION_COLOURS[i], a * dim))
		draw_string(f_sans, dc + Vector2(-36, 16), LETTERS[i], HORIZONTAL_ALIGNMENT_CENTER, 72, 44, Color(1, 1, 1, a * dim))
		var text := str(_options[i])
		var fs := 34
		var lines := _wrap(f_sans_reg, text, r.size.x - 360, fs)
		while lines.size() > 3 and fs > 24:
			fs -= 2
			lines = _wrap(f_sans_reg, text, r.size.x - 360, fs)
		var ly := r.position.y + r.size.y * 0.5 - (lines.size() - 1) * (fs + 8) * 0.5 + fs * 0.35
		for l in lines:
			draw_string(f_sans_reg, Vector2(r.position.x + 112, ly), l, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 360, fs, Color(1, 1, 1, a * dim))
			ly += fs + 8
		_chips(i, r.end.x - 14, r.end.y - 56, a)
		# reveal stamps
		if _reveal_t >= 0.0 and i < _stamps.size() and str(_stamps[i]) != "":
			var k := clampf((_t - _reveal_t - 0.25 - i * 0.18) * 5.0, 0.0, 1.0)
			if k > 0.0:
				var real: bool = _stamps[i] == "REAL"
				var sc := 1.0 + (1.0 - k) * 1.6
				var c := r.position + Vector2(r.size.x - 180, 56)
				draw_set_transform(c, -0.12, Vector2(sc, sc))
				var col := Color(0.25, 0.9, 0.35, a * k) if real else Color(1.0, 0.25, 0.3, a * k)
				draw_rect(Rect2(-110, -34, 220, 68), col, false, 6.0)
				draw_string(f_display, Vector2(-110, 18), str(_stamps[i]), HORIZONTAL_ALIGNMENT_CENTER, 220, 46, col)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _reveal_t < 0.0:
		_timer_bar(Rect2(50, H - 92, W - 100, 18), a)


# ---------------------------------------------------------------------------
# Guess the Genitals — the specimen lightbox
# ---------------------------------------------------------------------------

func _draw_image_layout(a: float) -> void:
	_grad(Rect2(0, 0, W, H), Color(0.86, 0.88, 0.84, a), Color(0.66, 0.7, 0.66, a))   # clinical pale-green wall
	for i in 24:
		draw_line(Vector2(0, i * 46), Vector2(W, i * 46), Color(0, 0.1, 0.05, 0.05 * a), 1.0)
	_header(a, Color(1.0, 0.55, 0.65))
	draw_string(f_sans, Vector2(76, 86), _title, HORIZONTAL_ALIGNMENT_LEFT, 560, 38, Color(0.1, 0.02, 0.14, a))
	# lightbox
	var box := Rect2(60, 128, 820, 615)
	draw_rect(box.grow(14), Color(0.18, 0.19, 0.2, a))
	draw_rect(box.grow(6), Color(0.85, 0.86, 0.88, a))
	draw_rect(box, Color(0.97, 0.97, 0.95, a))
	if _tex != null:
		var tw := float(_tex.get_width())
		var th := float(_tex.get_height())
		var z := maxf(1.0, _zoom)
		# fit (letterbox) within the lightbox, then zoom about the crop centre
		var scale := minf(box.size.x / tw, box.size.y / th)
		var src_w := minf(tw, box.size.x / scale / z)
		var src_h := minf(th, box.size.y / scale / z)
		var cx := float(_crop.get("x", 0.5)) if not _crop.is_empty() and _reveal_t < 0.0 else 0.5
		var cy := float(_crop.get("y", 0.5)) if not _crop.is_empty() and _reveal_t < 0.0 else 0.5
		var sx := clampf(cx * tw - src_w * 0.5, 0.0, tw - src_w)
		var sy := clampf(cy * th - src_h * 0.5, 0.0, th - src_h)
		var dst_size := Vector2(src_w, src_h) * scale * z
		var dst := Rect2(box.position + (box.size - dst_size) * 0.5, dst_size)
		draw_texture_rect_region(_tex, dst, Rect2(sx, sy, src_w, src_h), Color(1, 1, 1, a))
	else:
		draw_string(f_mono, Vector2(box.position.x, box.get_center().y), "SPECIMEN LOADING", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 34, Color(0.3, 0.3, 0.3, a))
	# catalogue label
	var lab := Rect2(box.position.x, box.end.y + 26, box.size.x, 54)
	draw_rect(lab, Color(0.98, 0.95, 0.82, a))
	draw_rect(lab, Color(0.25, 0.2, 0.15, a), false, 2.0)
	var cat := "SPECIMEN No. %03d" % (100 + _round * 7)
	if _reveal_t >= 0.0 and _answer_label != "":
		cat = "SPECIMEN: " + _answer_label.to_upper()
	draw_string(f_mono, lab.position + Vector2(18, 38), cat, HORIZONTAL_ALIGNMENT_LEFT, lab.size.x - 36, 28, Color(0.15, 0.1, 0.05, a))
	# options column
	var ox := box.end.x + 50
	var ow := W - ox - 50
	for i in _options.size():
		var r := Rect2(ox, 140 + i * 152, ow, 136)
		var dim := 1.0
		var good := false
		if _correct >= 0:
			good = i == _correct
			dim = 1.0 if good else 0.45
		var base := Color(0.22, 0.12, 0.3).lerp(Color(0.1, 0.5, 0.2), 1.0 if good else 0.0)
		_grad(r, Color(base.lightened(0.12), a * dim), Color(base.darkened(0.25), a * dim))
		draw_rect(r, Color(0.9, 0.9, 0.95, a * dim), false, 3.0)
		var dc := r.position + Vector2(46, r.size.y * 0.5)
		draw_circle(dc, 30, Color(OPTION_COLOURS[i], a * dim))
		draw_string(f_sans, dc + Vector2(-30, 14), LETTERS[i], HORIZONTAL_ALIGNMENT_CENTER, 60, 36, Color(1, 1, 1, a * dim))
		var lines := _wrap(f_sans, str(_options[i]), r.size.x - 110, 32)
		var ly := r.position.y + r.size.y * 0.5 - (lines.size() - 1) * 19 + 11
		for l in lines:
			_shadow(f_sans, Vector2(r.position.x + 92, ly), l, r.size.x - 100, 32, Color(1, 1, 1, a * dim), HORIZONTAL_ALIGNMENT_LEFT, 2)
			ly += 38
		_chips(i, r.end.x - 8, r.end.y - 50, a)
	if _reveal_t < 0.0:
		_timer_bar(Rect2(60, H - 120, W - 120, 18), a)


# ---------------------------------------------------------------------------

func _draw_fact(a: float) -> void:
	var k := clampf((_t - _reveal_t - 2.4) * 2.5, 0.0, 1.0)
	if k <= 0.0:
		return
	var lines := _wrap(f_sans_reg, _fact, W - 220, 30)
	if lines.size() > 4:
		lines = lines.slice(0, 4)
	var hh := 76.0 + lines.size() * 40.0
	var r := Rect2(60, H - hh - 36 + (1.0 - k) * 80.0, W - 120, hh)
	draw_rect(r, Color(0, 0, 0, 0.92 * a * k))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 44)), Color(0.0, 0.0, 0.7, a * k))
	draw_string(f_mono, r.position + Vector2(18, 32), "MILDEW VIEWER INFORMATION SERVICE", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36, 26, Color(1, 1, 0.3, a * k))
	var y := r.position.y + 86
	for l in lines:
		draw_string(f_sans_reg, Vector2(r.position.x + 40, y), l, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 30, Color(1, 1, 1, a * k))
		y += 40
