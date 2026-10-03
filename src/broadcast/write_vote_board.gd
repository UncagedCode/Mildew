class_name WriteVoteBoard
extends Control
## TV graphic for the write-then-vote games (CP4): MILDEW SURVEY (a cream questionnaire card on a
## clipboard-blue set) and MOUTHFEEL (a tasting-menu card on gravy brown). Phases:
##   write  — the prompt, a sealed-envelope marker per contestant, the deadline bar;
##   vote   — the anonymous answer cards (or one featured answer for WHO SAID THAT?);
##   chain  — Make It Worse: the dish so far, growing one horrible addition at a time;
##   reveal — vote chips land on cards, authors are unmasked (ARCHIVE / GRAHAM MILDEW included).
## Readability first (docs/01): answer text is never glitched or obscured.

const W := 1440.0
const H := 1080.0
const LETTERS := ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]

var f_display: Font
var f_sans: Font
var f_sans_reg: Font
var f_serif: Font
var f_mono: Font
var players := {}

var _game := ""
var _mode := ""
var _phase := ""             # write | vote | chain | rate | reveal
var _title := ""
var _category := ""
var _prompt := ""
var _round := 0
var _of := 0
var _vis := 0.0
var _target := 0.0
var _t := 0.0
var _phase_t := 0.0
var _timer := -1.0
var _timer_total := 1.0
var _submitted := {}         # pid -> true (writing / voting progress)
var _count := 0
var _count_of := 0
var _answers: Array = []     # shown text
var _featured := -1
var _reveal := {}
var _chain_text := ""
var _chain_pid := ""
var _chain_step := 0
var _chain_of := 0


func _ready() -> void:
	f_display = load("res://assets/fonts/InterDisplay-BlackItalic.otf")
	f_sans = load("res://assets/fonts/LiberationSans-Bold.ttf")
	f_sans_reg = load("res://assets/fonts/LiberationSans-Regular.ttf")
	f_serif = load("res://assets/fonts/LiberationSerif-BoldItalic.ttf")
	f_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------------------------------------------------------------------------
# Event API (Presenter)
# ---------------------------------------------------------------------------

func on_event(evt: Dictionary, time_scale: float) -> void:
	var ts := maxf(time_scale, 0.001)
	match str(evt.get("e")):
		"wv_show":
			_game = str(evt.get("game_id", ""))
			_mode = str(evt.get("mode", "popularity"))
			_title = str(evt.get("title", ""))
			_category = str(evt.get("category", ""))
			_prompt = str(evt.get("prompt", ""))
			_round = int(evt.get("round", 0))
			_of = int(evt.get("of", 0))
			_answers = []
			_reveal = {}
			_featured = -1
			_chain_text = ""
			_set_phase("write")
			_timer = -1.0
			_target = 1.0
		"wv_write_open":
			_set_phase("write")
			_start_timer(float(evt.window) / ts)
			_count_of = int(evt.get("of", 0))
		"wv_progress", "wv_vote_progress":
			_submitted[str(evt.pid)] = true
			_count = int(evt.count)
			_count_of = int(evt.of)
		"wv_chain":
			_set_phase("chain")
			_chain_text = str(evt.text)
			_chain_pid = str(evt.get("pid", ""))
			_chain_step = int(evt.step)
			_chain_of = int(evt.of)
			_start_timer(0.0)
			_timer = -1.0
		"wv_chain_final":
			_set_phase("rate")
			_chain_text = str(evt.text)
			_start_timer(float(evt.window) / ts)
			_count_of = int(evt.get("of", 0))
		"wv_vote_open":
			_set_phase("vote")
			_answers = evt.get("answers", [])
			_featured = int(evt.get("featured", -1))
			_start_timer(float(evt.window) / ts)
			_count_of = int(evt.get("of", 0))
		"wv_reveal":
			_set_phase("reveal")
			_reveal = evt
			_timer = -1.0
			if evt.has("answers"):
				_answers = (evt.answers as Array).map(func(a): return a.text)


func _set_phase(p: String) -> void:
	_phase = p
	_phase_t = _t
	_submitted = {}
	_count = 0


func _start_timer(seconds: float) -> void:
	_timer = seconds
	_timer_total = maxf(0.1, seconds)


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
# Palette per game
# ---------------------------------------------------------------------------

func _mf() -> bool:
	return _game == "mouthfeel"


func _bg() -> Color:
	return Color(0.16, 0.09, 0.04) if _mf() else Color(0.04, 0.07, 0.26)


func _paper() -> Color:
	return Color("#efe2c2") if _mf() else Color("#f6efd8")


func _accent() -> Color:
	return Color("#a8c43a") if _mf() else Color("#ff9a1f")


func _ink() -> Color:
	return Color("#3a1c0c") if _mf() else Color("#1d2a6b")


func _prompt_font() -> Font:
	return f_serif if _mf() else f_sans


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _vis <= 0.001:
		return
	var a := _vis
	draw_rect(Rect2(0, 0, W, H), Color(_bg(), 0.94 * a))
	_backdrop(a)
	_header(a)
	match _phase:
		"write":
			_draw_prompt_card(Rect2(110, 150, W - 220, 470), a, 64)
			_draw_envelopes(a, 700)
			_timer_bar(Rect2(110, 650, W - 220, 22), a)
		"chain", "rate":
			_draw_chain(a)
		"vote":
			if _mode == "who_said":
				_draw_who_said(a, false)
			else:
				_draw_prompt_strip(a)
				_draw_cards(a, false)
				_timer_bar(Rect2(110, 1000, W - 220, 16), a)
		"reveal":
			if _mode == "who_said":
				_draw_who_said(a, true)
			elif _mode == "chain":
				_draw_chain(a)
			else:
				_draw_prompt_strip(a)
				_draw_cards(a, true)


func _backdrop(a: float) -> void:
	if _mf():
		# faint tablecloth check
		for y in range(0, int(H), 60):
			for x in range(0, int(W), 60):
				if (x / 60 + y / 60) % 2 == 0:
					draw_rect(Rect2(x, y, 60, 60), Color(1, 0.9, 0.7, 0.025 * a))
	else:
		for i in 24:   # graph-paper rules
			draw_rect(Rect2(0, i * 45, W, 1), Color(0.5, 0.65, 1.0, 0.07 * a))
			draw_rect(Rect2(i * 60, 0, 1, H), Color(0.5, 0.65, 1.0, 0.05 * a))


func _header(a: float) -> void:
	var tab := PackedVector2Array([Vector2(70, 40), Vector2(640, 40), Vector2(670, 96), Vector2(50, 96)])
	draw_colored_polygon(tab, Color(_accent(), a))
	draw_string(f_sans, Vector2(76, 82), _title, HORIZONTAL_ALIGNMENT_LEFT, 580, 38, Color(0.08, 0.04, 0.02, a))
	var sub := ""
	match _mode:
		"archive":
			sub = "ARCHIVE ROUND"
		"who_said":
			sub = "WHO SAID THAT?"
		"chain":
			sub = ""
		_:
			sub = _category if _category != "" else ""
	if _of > 0:
		sub = ("%s   " % sub if sub != "" else "") + "%d / %d" % [_round, _of]
	draw_string(f_mono, Vector2(700, 80), sub, HORIZONTAL_ALIGNMENT_LEFT, 700, 28, Color(1, 1, 1, 0.92 * a))


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


## Fit text into a box: shrink the font until the wrapped lines fit; returns [lines, size].
func _fit(font: Font, text: String, box: Vector2, max_fs: int, min_fs: int = 20) -> Array:
	var fs := max_fs
	while fs > min_fs:
		var lines := _wrap(font, text, box.x, fs)
		if lines.size() * fs * 1.18 <= box.y:
			return [lines, fs]
		fs -= 2
	return [_wrap(font, text, box.x, min_fs), min_fs]


func _text_block(font: Font, text: String, r: Rect2, max_fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, min_fs := 20) -> void:
	var fit := _fit(font, text, r.size, max_fs, min_fs)
	var lines: Array = fit[0]
	var fs: int = fit[1]
	var lh := fs * 1.18
	var y := r.position.y + (r.size.y - lines.size() * lh) * 0.5 + fs * 0.92
	for l in lines:
		draw_string(font, Vector2(r.position.x, y), l, align, r.size.x, fs, col)
		y += lh


func _paper_card(r: Rect2, a: float, tilt := 0.0) -> void:
	draw_set_transform(r.get_center(), tilt, Vector2.ONE)
	var lr := Rect2(-r.size * 0.5, r.size)
	draw_rect(Rect2(lr.position + Vector2(10, 12), lr.size), Color(0, 0, 0, 0.45 * a))
	draw_rect(lr, Color(_paper(), a))
	if _mf():
		draw_rect(lr.grow(-14), Color(_ink(), 0.6 * a), false, 2.0)
		draw_rect(lr.grow(-20), Color(_ink(), 0.35 * a), false, 1.0)
	else:
		for i in range(1, int(lr.size.y / 46)):
			draw_rect(Rect2(lr.position.x, lr.position.y + i * 46, lr.size.x, 1.5), Color(0.45, 0.6, 0.9, 0.35 * a))
		draw_rect(Rect2(lr.position.x + 70, lr.position.y, 2.5, lr.size.y), Color(0.85, 0.2, 0.2, 0.55 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_prompt_card(r: Rect2, a: float, fs: int) -> void:
	_paper_card(r, a, -0.012)
	var label := "TONIGHT'S DISH" if _mf() else "QUESTION"
	draw_string(f_mono, r.position + Vector2(96, 48), label, HORIZONTAL_ALIGNMENT_LEFT, 400, 22, Color(_ink(), 0.7 * a))
	if _mf() and _category != "":
		draw_string(f_mono, r.position + Vector2(r.size.x - 640, 48), "VOTE: " + _category, HORIZONTAL_ALIGNMENT_RIGHT, 600, 22, Color(0.55, 0.1, 0.05, a))
	_text_block(_prompt_font(), _prompt, Rect2(r.position + Vector2(96, 70), r.size - Vector2(150, 110)), fs, Color(_ink(), a))


func _draw_prompt_strip(a: float) -> void:
	var r := Rect2(110, 116, W - 220, 92)
	draw_rect(r, Color(_paper(), 0.95 * a))
	_text_block(_prompt_font(), _prompt, r.grow_individual(-24, -6, -24, -6), 34, Color(_ink(), a), HORIZONTAL_ALIGNMENT_CENTER, 18)


func _avatar(pid: String, r: Rect2, a: float) -> void:
	AvatarPainter.draw(self, r, players.get(pid, {}).get("avatar", {}))
	draw_rect(r, Color(1, 1, 1, a), false, 2.0)


func _name(pid: String) -> String:
	return str(players.get(pid, {}).get("name", "?")).to_upper()


func _draw_envelopes(a: float, y: float) -> void:
	var ids: Array = players.keys()
	if ids.is_empty():
		return
	var w := minf(150.0, (W - 220) / ids.size())
	var x0 := W * 0.5 - w * ids.size() * 0.5
	for i in ids.size():
		var pid: String = ids[i]
		var x := x0 + i * w
		var done := _submitted.has(pid)
		var env := Rect2(x + 10, y + 20, w - 20, (w - 20) * 0.66)
		draw_rect(env, Color(_paper(), a if done else 0.25 * a))
		draw_polyline(PackedVector2Array([env.position, env.position + Vector2(env.size.x * 0.5, env.size.y * 0.55), Vector2(env.end.x, env.position.y)]), Color(_ink(), (0.8 if done else 0.3) * a), 2.0)
		if done:
			draw_circle(env.get_center() + Vector2(0, env.size.y * 0.18), 14, Color(0.7, 0.08, 0.08, a))
		var av := Rect2(Vector2(x + w * 0.5 - 30, y + 30 + env.size.y), Vector2(60, 60))
		_avatar(pid, av, a)
		draw_string(f_sans, Vector2(x, av.end.y + 30), _name(pid), HORIZONTAL_ALIGNMENT_CENTER, w, 20, Color(1, 1, 1, a))
	if _count_of > 0:
		draw_string(f_mono, Vector2(110, y + 250), "ANSWERS SEALED: %d/%d" % [_count, _count_of], HORIZONTAL_ALIGNMENT_LEFT, 700, 28, Color(1, 0.85, 0.3, a))


func _timer_bar(rect: Rect2, a: float) -> void:
	if _timer < 0.0:
		return
	draw_rect(rect, Color(0, 0, 0, 0.6 * a))
	var frac := _timer / _timer_total
	var col := _accent().lerp(Color("#ff3b30"), 1.0 - frac)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * frac, rect.size.y)), Color(col, a))
	draw_string(f_mono, Vector2(rect.end.x - 120, rect.position.y - 8), "%2d" % int(ceil(_timer)), HORIZONTAL_ALIGNMENT_RIGHT, 120, 30, Color(1, 1, 1, a))
	if _phase == "vote" and _count_of > 0:
		draw_string(f_mono, Vector2(rect.position.x, rect.position.y - 8), "VOTES IN: %d/%d" % [_count, _count_of], HORIZONTAL_ALIGNMENT_LEFT, 600, 26, Color(1, 0.85, 0.3, a))


func _grid(n: int) -> Array:
	var cols := 1 if n <= 3 else 2
	var rows := int(ceil(float(n) / cols))
	var top := 236.0
	var bottom := 960.0
	var gap := 16.0
	var ch := minf(190.0, (bottom - top - gap * (rows - 1)) / rows)
	var cw := (W - 220 - gap * (cols - 1)) / cols
	var out: Array = []
	for i in n:
		var c := i % cols
		var r := i / cols
		out.append(Rect2(110 + c * (cw + gap), top + r * (ch + gap), cw, ch))
	return out


func _draw_cards(a: float, revealed: bool) -> void:
	var rects := _grid(_answers.size())
	var tally: Array = _reveal.get("tally", [])
	var winner := int(_reveal.get("winner", -1))
	var gchoice := int(_reveal.get("graham_choice", -1))
	var info: Array = _reveal.get("answers", [])
	var votes: Dictionary = _reveal.get("votes", {})
	var rt := _t - _phase_t
	for i in _answers.size():
		var r: Rect2 = rects[i]
		var appear := clampf((_t - _phase_t) * 4.0 - i * 0.25, 0.0, 1.0) if not revealed else 1.0
		var ca := a * appear
		var is_win := revealed and i == winner
		var is_arch := revealed and _mode == "archive" and i < info.size() and str(info[i].kind) == "archive"
		var paper := _paper()
		if is_win or is_arch:
			paper = paper.lerp(Color("#ffd23f"), 0.45 + 0.1 * sin(_t * 6.0))
		elif revealed:
			paper = paper.darkened(0.25)
		draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0, 0, 0, 0.4 * ca))
		draw_rect(r, Color(paper, ca))
		draw_rect(r, Color(_ink(), 0.5 * ca), false, 2.0)
		var badge := Rect2(r.position + Vector2(12, 12), Vector2(46, 46))
		draw_rect(badge, Color(_accent(), ca))
		draw_string(f_sans, badge.position + Vector2(0, 36), LETTERS[i % LETTERS.size()], HORIZONTAL_ALIGNMENT_CENTER, 46, 32, Color(0.08, 0.04, 0.02, ca))
		var text_r := Rect2(r.position + Vector2(72, 8), r.size - Vector2(84 + (150 if revealed else 0), 16 + (36 if revealed else 0)))
		_text_block(_prompt_font() if _mf() else f_sans, "“%s”" % str(_answers[i]), text_r, 34, Color(_ink(), ca), HORIZONTAL_ALIGNMENT_LEFT, 18)
		if not revealed:
			continue
		# author unmasked + vote chips
		var land := clampf((rt - 0.4 - i * 0.18) * 3.0, 0.0, 1.0)
		var who := ""
		var wcol := Color(_ink(), ca)
		if i < info.size():
			match str(info[i].kind):
				"archive":
					who = "FROM THE ARCHIVE"
					wcol = Color(0.45, 0.25, 0.05, ca)
				"graham":
					who = "GRAHAM MILDEW"
					wcol = Color(0.6, 0.05, 0.1, ca)
				_:
					who = _name(str(info[i].author))
		draw_string(f_mono, Vector2(r.position.x + 72, r.end.y - 12), who, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.6, 22, Color(wcol, wcol.a * land))
		var x := r.end.x - 12
		for pid in votes:
			if int(votes[pid]) == i:
				x -= 40
				_avatar(str(pid), Rect2(Vector2(x, r.end.y - 46), Vector2(34, 34)), ca * land)
		if i < tally.size() and int(tally[i]) > 0 and _mode != "archive":
			draw_string(f_display, Vector2(r.end.x - 160, r.position.y + 50), "%d VOTE%s" % [int(tally[i]), "" if int(tally[i]) == 1 else "S"], HORIZONTAL_ALIGNMENT_RIGHT, 150, 26, Color(0.7, 0.1, 0.05, ca * land))
		if i == gchoice:
			_star(Vector2(r.position.x + r.size.x * 0.5 + 10, r.end.y - 20), 14, Color(0.85, 0.12, 0.2, ca * land))
			draw_string(f_mono, Vector2(r.position.x + r.size.x * 0.5 + 30, r.end.y - 12), "GRAHAM'S CHOICE", HORIZONTAL_ALIGNMENT_LEFT, 250, 18, Color(0.85, 0.12, 0.2, ca * land))


func _star(c: Vector2, rad: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var ang := -PI / 2 + k * PI / 5
		pts.append(c + Vector2(cos(ang), sin(ang)) * (rad if k % 2 == 0 else rad * 0.45))
	draw_colored_polygon(pts, col)


func _draw_who_said(a: float, revealed: bool) -> void:
	var text := str(_answers[_featured]) if _featured >= 0 and _featured < _answers.size() else ""
	var r := Rect2(160, 150, W - 320, 400)
	_paper_card(r, a, 0.01)
	draw_string(f_mono, r.position + Vector2(96, 48), "WHO WROTE THIS?", HORIZONTAL_ALIGNMENT_LEFT, 600, 24, Color(_ink(), 0.75 * a))
	_text_block(_prompt_font(), "“%s”" % text, Rect2(r.position + Vector2(96, 70), r.size - Vector2(150, 100)), 58, Color(_ink(), a))
	var names: Array = _reveal.get("guess_names", [])
	var ids: Array = players.keys()
	var author_i := int(_reveal.get("author_index", -1))
	var votes: Dictionary = _reveal.get("votes", {})
	var n := ids.size()
	var w := minf(170.0, (W - 220) / maxf(1.0, n))
	var x0 := W * 0.5 - w * n * 0.5
	for i in n:
		var pid: String = ids[i]
		var x := x0 + i * w
		var av := Rect2(Vector2(x + w * 0.5 - 50, 620), Vector2(100, 100))
		var hit := revealed and names.size() > 0 and author_i >= 0 and author_i < names.size() and str(names[author_i]).to_upper() == _name(pid)
		if hit:
			draw_rect(av.grow(10), Color(1, 0.82, 0.2, a * (0.7 + 0.3 * sin(_t * 8.0))))
		_avatar(pid, av, a * (1.0 if (hit or not revealed) else 0.45))
		draw_string(f_sans, Vector2(x, av.end.y + 34), _name(pid), HORIZONTAL_ALIGNMENT_CENTER, w, 24, Color(1, 1, 1, a))
		if revealed:
			var k := 0
			for voter in votes:
				if names.size() > int(votes[voter]) and str(names[int(votes[voter])]).to_upper() == _name(pid):
					_avatar(str(voter), Rect2(Vector2(x + 8 + k * 36, av.end.y + 52), Vector2(30, 30)), a)
					k += 1
	if not revealed:
		_timer_bar(Rect2(110, 940, W - 220, 18), a)
	elif author_i >= 0:
		draw_string(f_display, Vector2(0, 960), "IT WAS %s" % str(names[author_i]).to_upper() if author_i < names.size() else "", HORIZONTAL_ALIGNMENT_CENTER, W, 54, Color(1, 0.85, 0.25, a))


func _draw_chain(a: float) -> void:
	var r := Rect2(130, 140, W - 260, 560)
	_paper_card(r, a, -0.008)
	draw_string(f_mono, r.position + Vector2(96, 50), "MAKE IT WORSE" if _phase == "chain" else "THE FINISHED DISH", HORIZONTAL_ALIGNMENT_LEFT, 600, 26, Color(0.6, 0.1, 0.05, a))
	_text_block(f_serif, _chain_text, Rect2(r.position + Vector2(96, 70), r.size - Vector2(150, 100)), 60, Color(_ink(), a), HORIZONTAL_ALIGNMENT_CENTER, 24)
	if _phase == "chain":
		if _chain_pid != "":
			var av := Rect2(Vector2(W * 0.5 - 60, 740), Vector2(120, 120))
			_avatar(_chain_pid, av, a)
			var dots := ".".repeat(int(_t * 2.0) % 4)
			draw_string(f_display, Vector2(0, 920), "%s IS MAKING IT WORSE%s" % [_name(_chain_pid), dots], HORIZONTAL_ALIGNMENT_CENTER, W, 44, Color(1, 1, 1, a))
			draw_string(f_mono, Vector2(0, 970), "STEP %d OF %d" % [_chain_step + 1, _chain_of], HORIZONTAL_ALIGNMENT_CENTER, W, 26, Color(1, 0.85, 0.3, a))
	elif _phase == "rate":
		draw_string(f_display, Vector2(0, 800), "RATE IT ON YOUR DEVICE. 1 TO 5.", HORIZONTAL_ALIGNMENT_CENTER, W, 50, Color(1, 1, 1, a))
		_timer_bar(Rect2(110, 900, W - 220, 18), a)
	else:
		var avg := float(_reveal.get("average", 0.0))
		var shown := minf(avg, (_t - _phase_t) * 2.5)
		for k in 5:
			var c := Vector2(W * 0.5 - 240 + k * 120, 800)
			_star(c, 46, Color(0.3, 0.2, 0.1, a))
			var fill := clampf(shown - k, 0.0, 1.0)
			if fill > 0.0:
				_star(c, 46 * fill, Color(1, 0.8, 0.15, a))
		draw_string(f_display, Vector2(0, 910), "%.1f OUT OF 5" % avg, HORIZONTAL_ALIGNMENT_CENTER, W, 48, Color(1, 1, 1, a))
		var parts: Array = _reveal.get("parts", [])
		var x := W * 0.5 - parts.size() * 40
		for p in parts:
			_avatar(str(p.pid), Rect2(Vector2(x + 6, 950), Vector2(68, 68)), a)
			x += 80
