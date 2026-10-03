class_name GraphicsLayer
extends Control
## Programme graphics package (inside the 4:3 frame, under the broadcast treatment).
## 1998 regional-ITV energy: slanted gradient lower-thirds, chrome-bevelled quiz boards,
## teletext subtitles (Ceefax 888 style), a channel DOG, sting cards and slates.
## Readability rule (docs/01 #97): question text/timers are large, high contrast and
## never subjected to fictional glitches.

const W := 1440.0
const H := 1080.0
const OPTION_COLOURS := [Color("#c7362b"), Color("#e2b42c"), Color("#3f9a45"), Color("#2e5fae")]
const LETTERS := ["A", "B", "C", "D"]
const SPEAKER_COLOURS := {"graham": Color(1, 1, 1), "announcer": Color(0.35, 1, 1), "test": Color(1, 1, 0.3)}

var f_display: Font
var f_sans: Font
var f_sans_italic: Font
var f_mono: Font
var f_serif: Font

var _t := 0.0
var players := {}                  # pid -> public info (avatars for chips/scoreboard)

# Subtitles
var subtitles_enabled := true
## Returns true while a game graphic owns the lower frame (answer panels, lock strip). Teletext
## subtitles then move to the top of the picture, as Ceefax 888 did over lower-frame captions.
var bottom_busy: Callable = Callable()
var _sub_text := ""
var _sub_speaker := "graham"
var _sub_until := 0.0

# Lower third
var _lt_name := ""
var _lt_sub := ""
var _lt_t := -1.0
var _lt_dur := 0.0

# Question board
var _q_visible := 0.0
var _q_target := 0.0
var _q_prompt := ""
var _q_options: Array = []
var _q_title := ""
var _q_timer := -1.0
var _q_total := 1.0
var _q_answered := 0
var _q_of := 0
var _q_correct := -1
var _q_picks := {}                 # option index -> Array[pid]
var _q_reveal_t := -1.0

# Scoreboard
var _sb_visible := 0.0
var _sb_target := 0.0
var _sb_rows: Array = []
var _sb_t := 0.0
var _sb_title := "THE SCORES"

# Sting
var _st_t := -1.0
var _st_dur := 4.0
var _st_title := ""
var _st_style := ""

# Slate / menu
var _slate := ""
var _slate_sub := ""
var menu_title := ""
var menu_items: Array = []         # [{label, value?, desc?}]
var menu_selected := 0
var menu_footer := ""
var dog_visible := true

# Confetti
var _confetti: Array = []

# Irregularities (fictional, inside the programme only)
var _tear_until := -1.0
var _cap_text := ""
var _cap_until := -1.0


func _ready() -> void:
	f_display = load("res://assets/fonts/InterDisplay-BlackItalic.otf")
	f_sans = load("res://assets/fonts/LiberationSans-Bold.ttf")
	f_sans_italic = load("res://assets/fonts/LiberationSans-BoldItalic.ttf")
	f_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")
	f_serif = load("res://assets/fonts/LiberationSerif-BoldItalic.ttf")
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	_q_visible = move_toward(_q_visible, _q_target, delta * 4.0)
	_sb_visible = move_toward(_sb_visible, _sb_target, delta * 4.0)
	if _q_timer > 0.0:
		_q_timer = maxf(0.0, _q_timer - delta)
	if _st_t >= 0.0:
		_st_t += delta
		if _st_t > _st_dur:
			_st_t = -1.0
	if _lt_t >= 0.0:
		_lt_t += delta
		if _lt_t > _lt_dur:
			_lt_t = -1.0
	if _sb_target > 0.0:
		_sb_t += delta
	for c in _confetti:
		c.p += c.v * delta
		c.v.y += 260.0 * delta
		c.r += c.w * delta
	_confetti = _confetti.filter(func(c): return c.p.y < H + 40)
	queue_redraw()


# ---------------------------------------------------------------------------
# API used by the Presenter
# ---------------------------------------------------------------------------

func show_subtitle(text: String, speaker: String, seconds: float) -> void:
	_sub_text = text
	_sub_speaker = speaker
	_sub_until = _t + maxf(1.2, seconds)


func show_lower_third(name: String, sub: String, seconds: float = 4.0) -> void:
	_lt_name = name
	_lt_sub = sub
	_lt_t = 0.0
	_lt_dur = seconds


func show_question(title: String, prompt: String, options: Array) -> void:
	_q_title = title
	_q_prompt = prompt
	_q_options = options
	_q_target = 1.0
	_q_timer = -1.0
	_q_correct = -1
	_q_picks = {}
	_q_answered = 0
	_q_reveal_t = -1.0


func start_timer(seconds: float) -> void:
	_q_timer = seconds
	_q_total = maxf(0.1, seconds)


func stop_timer() -> void:
	_q_timer = -1.0


func set_answered(n: int, of: int) -> void:
	_q_answered = n
	_q_of = of


func reveal(correct: int, picks: Dictionary) -> void:
	_q_correct = correct
	_q_timer = -1.0
	_q_reveal_t = _t
	_q_picks = {}
	for pid in picks.keys():
		var c := int(picks[pid])
		if not _q_picks.has(c):
			_q_picks[c] = []
		_q_picks[c].append(pid)


func hide_question() -> void:
	_q_target = 0.0


func show_scores(rows: Array, title: String = "THE SCORES") -> void:
	_sb_rows = rows
	_sb_target = 1.0
	_sb_t = 0.0
	_sb_title = title


func hide_scores() -> void:
	_sb_target = 0.0


func play_sting(title: String, seconds: float, style: String = "") -> void:
	_st_title = title
	_st_style = style
	_st_t = 0.0
	_st_dur = seconds


func show_slate(title: String, sub: String = "") -> void:
	_slate = title
	_slate_sub = sub


func hide_slate() -> void:
	_slate = ""


func confetti(count: int = 160) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var cols := [Color("#ff4fa3"), Color("#ffd23f"), Color("#3ec9c1"), Color("#9b5de5"), Color("#c8e86f"), Color.WHITE]
	for i in count:
		_confetti.append({"p": Vector2(rng.randf_range(0, W), rng.randf_range(-300, -10)), "v": Vector2(rng.randf_range(-60, 60), rng.randf_range(80, 260)),
			"r": rng.randf() * TAU, "w": rng.randf_range(-8, 8), "c": cols[i % cols.size()], "s": rng.randf_range(8, 16)})


## Brief analogue signal tear (cheap TV, Tier 0). Never used while a question is up.
func signal_tear(seconds: float) -> void:
	_tear_until = _t + seconds


## A production-monitor caption leaking to air (Tier 1).
func production_caption(text: String, seconds: float) -> void:
	_cap_text = text
	_cap_until = _t + seconds


func is_question_visible() -> bool:
	return _q_target > 0.0


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _st_t >= 0.0:
		_draw_sting()
	if _q_visible > 0.0:
		_draw_question(_q_visible)
	if _sb_visible > 0.0:
		_draw_scores(_sb_visible)
	if _lt_t >= 0.0:
		_draw_lower_third()
	if _slate != "":
		_draw_slate()
	if not menu_items.is_empty():
		_draw_menu()
	for c in _confetti:
		draw_set_transform(c.p, c.r, Vector2.ONE)
		draw_rect(Rect2(-c.s * 0.5, -c.s * 0.25, c.s, c.s * 0.5), c.c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if dog_visible and _slate == "":
		draw_string(f_serif, Vector2(W - 210, 78), "Sallow", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1, 1, 1, 0.42))
	if subtitles_enabled and _t < _sub_until and _sub_text != "":
		_draw_subtitles()
	if _t < _cap_until and _cap_text != "":
		var cw := f_mono.get_string_size(_cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_rect(Rect2(64, 96, cw + 28, 42), Color(0, 0, 0, 0.85))
		draw_string(f_mono, Vector2(78, 126), _cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.9))
	if _t < _tear_until:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_t * 50.0)
		for i in 7:
			var y := rng.randf() * H
			var hh := rng.randf_range(6.0, 40.0)
			draw_rect(Rect2(rng.randf_range(-60, 60), y, W + 120, hh), Color(1, 1, 1, rng.randf_range(0.08, 0.28)))
			draw_rect(Rect2(0, y + hh, W, 3), Color(0, 0, 0, 0.4))


func _grad_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


func _chrome_frame(r: Rect2, thickness: float = 6.0) -> void:
	draw_rect(r.grow(thickness), Color(0.12, 0.08, 0.18), false, thickness * 2.0)
	draw_rect(r.grow(thickness * 0.5), Color(0.82, 0.84, 0.92), false, thickness)
	draw_line(r.position + Vector2(-thickness, -thickness * 0.5), Vector2(r.end.x + thickness, r.position.y - thickness * 0.5), Color(1, 1, 1, 0.9), 2.0)


func _shadow_text(font: Font, pos: Vector2, text: String, align: int, width: float, fsize: int, col: Color, depth: int = 4) -> void:
	for i in range(depth, 0, -1):
		draw_string(font, pos + Vector2(i, i), text, align, width, fsize, Color(0.12, 0.02, 0.18, 0.9))
	draw_string_outline(font, pos, text, align, width, fsize, 4, Color(0.05, 0.0, 0.1))
	draw_string(font, pos, text, align, width, fsize, col)


func _draw_subtitles() -> void:
	var col: Color = SPEAKER_COLOURS.get(_sub_speaker, Color.WHITE)
	var lines := _wrap(_sub_text, 34)
	if lines.size() > 3:
		lines = lines.slice(lines.size() - 3)
	var fs := 40
	var y := H - 70.0 - (lines.size() - 1) * 52.0
	if bottom_busy.is_valid() and bottom_busy.call():
		y = 62.0
	for line in lines:
		var tw := f_mono.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := (W - tw) * 0.5
		draw_rect(Rect2(x - 12, y - 40, tw + 24, 52), Color.BLACK)
		draw_string(f_mono, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		y += 52.0


static func _wrap(text: String, max_chars: int) -> Array:
	var out: Array = []
	var cur := ""
	for word in text.split(" ", false):
		if cur.length() + word.length() + 1 > max_chars and cur != "":
			out.append(cur)
			cur = word
		else:
			cur = word if cur == "" else cur + " " + word
	if cur != "":
		out.append(cur)
	return out


func _draw_lower_third() -> void:
	var t_in := smoothstep(0.0, 0.35, _lt_t)
	var t_out := 1.0 - smoothstep(_lt_dur - 0.35, _lt_dur, _lt_t)
	var k := t_in * t_out
	var x0 := lerpf(-900.0, 70.0, k)
	var y0 := 660.0
	var bar := PackedVector2Array([Vector2(x0, y0), Vector2(x0 + 840, y0), Vector2(x0 + 800, y0 + 104), Vector2(x0 - 40, y0 + 104)])
	draw_polygon(bar, PackedColorArray([Color("#c2185b"), Color("#4a148c"), Color("#311b92"), Color("#ad1457")]))
	draw_line(Vector2(x0, y0), Vector2(x0 + 840, y0), Color(0.95, 0.85, 0.5), 5.0)
	draw_line(Vector2(x0 - 40, y0 + 104), Vector2(x0 + 800, y0 + 104), Color(0.2, 0.0, 0.25), 4.0)
	var tag := PackedVector2Array([Vector2(x0 + 10, y0 - 46), Vector2(x0 + 420, y0 - 46), Vector2(x0 + 412, y0 - 4), Vector2(x0 + 2, y0 - 4)])
	draw_colored_polygon(tag, Color("#ffd23f"))
	draw_string(f_sans, Vector2(x0 + 24, y0 - 14), _lt_sub.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 380, 28, Color("#2b0a3d"))
	_shadow_text(f_sans_italic, Vector2(x0 + 30, y0 + 74), _lt_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 760, 62, Color.WHITE, 3)


func _draw_question(vis: float) -> void:
	var slide := (1.0 - vis) * -60.0
	modulate_alpha(vis)
	var panel := Rect2(90, 150 + slide, 1260, 300)
	# title tab
	var tab := PackedVector2Array([Vector2(110, panel.position.y - 50), Vector2(560, panel.position.y - 50), Vector2(590, panel.position.y), Vector2(90, panel.position.y)])
	draw_colored_polygon(tab, Color(0.85, 0.68, 0.3, vis))
	draw_string(f_sans, Vector2(120, panel.position.y - 14), _q_title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 440, 30, Color(0.15, 0.03, 0.2, vis))
	_grad_rect(panel, Color(0.1, 0.18, 0.62, 0.96 * vis), Color(0.05, 0.06, 0.28, 0.96 * vis))
	_chrome_frame(panel)
	for i in 6:
		draw_line(Vector2(panel.position.x, panel.position.y + 30 + i * 46), Vector2(panel.end.x, panel.position.y + 30 + i * 46), Color(1, 1, 1, 0.025 * vis), 20.0)
	var lines := _wrap(_q_prompt, 30)
	var fs := 64 if lines.size() <= 2 else 52
	var lh := fs + 12.0
	var y := panel.position.y + panel.size.y * 0.5 - (lines.size() - 1) * lh * 0.5 + fs * 0.35
	for line in lines:
		_shadow_text(f_sans, Vector2(panel.position.x, y), line, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, fs, Color(1, 1, 1, vis), 3)
		y += lh
	# timer bar (theatrical) + answered counter (real)
	var bar := Rect2(90, panel.end.y + 22, 1260, 24)
	draw_rect(bar, Color(0, 0, 0, 0.6 * vis))
	if _q_timer >= 0.0:
		var frac := _q_timer / _q_total
		var col := Color("#3ec9c1").lerp(Color("#ff3b30"), 1.0 - frac)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(col, vis))
		draw_string(f_mono, Vector2(bar.end.x - 120, bar.end.y + 40), "%2d" % int(ceil(_q_timer)), HORIZONTAL_ALIGNMENT_RIGHT, 120, 40, Color(1, 1, 1, vis))
	if _q_of > 0 and _q_correct < 0:
		draw_string(f_mono, Vector2(bar.position.x, bar.end.y + 40), "ANSWERS IN: %d/%d" % [_q_answered, _q_of], HORIZONTAL_ALIGNMENT_LEFT, 600, 30, Color(1, 0.85, 0.3, vis))
	# options
	for i in _q_options.size():
		var col_i := i % 2
		var row := i / 2
		var r := Rect2(90 + col_i * 640, 560 + row * 165 + slide, 620, 138)
		var dim := 1.0
		var glow := 0.0
		if _q_correct >= 0:
			if i == _q_correct:
				glow = 0.5 + 0.5 * sin((_t - _q_reveal_t) * 10.0)
			else:
				dim = 0.35
		var base := Color(0.16, 0.06, 0.3).lerp(Color(0.1, 0.55, 0.2), 1.0 if i == _q_correct else 0.0)
		_grad_rect(r, Color(base.lightened(0.15 + glow * 0.3), vis * dim), Color(base.darkened(0.3), vis * dim))
		draw_rect(r, Color(0.82, 0.84, 0.92, vis * dim), false, 4.0)
		var disc_c := r.position + Vector2(62, r.size.y * 0.5)
		draw_circle(disc_c, 44, Color(0, 0, 0, 0.5 * vis))
		draw_circle(disc_c, 40, Color(OPTION_COLOURS[i], vis * dim))
		draw_string(f_sans, disc_c + Vector2(-40, 18), LETTERS[i], HORIZONTAL_ALIGNMENT_CENTER, 80, 50, Color(1, 1, 1, vis * dim))
		var olines := _wrap(str(_q_options[i]), 20)
		var ofs := 46 if olines.size() == 1 else 36
		var oy := r.position.y + r.size.y * 0.5 + ofs * 0.35 - (olines.size() - 1) * (ofs + 4) * 0.5
		for ol in olines:
			_shadow_text(f_sans, Vector2(r.position.x + 122, oy), ol, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 140, ofs, Color(1, 1, 1, vis * dim), 2)
			oy += ofs + 4
		# who picked what (after reveal)
		if _q_picks.has(i):
			var x := r.end.x - 10.0
			for pid in _q_picks[i]:
				x -= 60.0
				var chip := Rect2(Vector2(x, r.end.y - 36), Vector2(54, 54))
				AvatarPainter.draw(self, chip, players.get(pid, {}).get("avatar", {}))
				draw_rect(chip, Color.WHITE, false, 2.0)
	modulate_alpha(1.0)


func modulate_alpha(_a: float) -> void:
	pass  # (alpha is applied per draw call; hook kept for future group fades)


func _draw_scores(vis: float) -> void:
	var r := Rect2(110, 150, 1220, 780)
	_grad_rect(r, Color(0.2, 0.06, 0.35, 0.95 * vis), Color(0.05, 0.02, 0.12, 0.95 * vis))
	_chrome_frame(r)
	_shadow_text(f_display, Vector2(r.position.x, r.position.y + 96), _sb_title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 84, Color(1, 0.95, 0.85, vis), 6)
	var n := _sb_rows.size()
	var row_h := clampf(560.0 / maxf(1, n), 60.0, 120.0)
	for i in n:
		var row: Dictionary = _sb_rows[i]
		var appear := clampf((_sb_t - 0.25 * (n - 1 - i)) * 3.0, 0.0, 1.0)
		if appear <= 0.0:
			continue
		var y := r.position.y + 150 + i * row_h
		var rr := Rect2(r.position.x + 40 + (1.0 - appear) * 300, y, r.size.x - 80, row_h - 12)
		var colours := [Color(0.07, 0.5, 0.52), Color(0.6, 0.12, 0.42), Color(0.78, 0.58, 0.12), Color(0.35, 0.14, 0.6)]
		var pc: Color = colours[(int(row.get("number", 1)) - 1) % colours.size()]
		_grad_rect(rr, Color(pc.lightened(0.15), appear * vis), Color(pc.darkened(0.35), appear * vis))
		draw_rect(rr, Color(1, 1, 1, 0.5 * appear * vis), false, 2.0)
		var av := Rect2(rr.position + Vector2(10, 6), Vector2(rr.size.y - 12, rr.size.y - 12))
		AvatarPainter.draw(self, av, players.get(row.pid, {}).get("avatar", {}))
		var fs := int(clampf(row_h * 0.45, 28, 52))
		draw_string(f_sans, Vector2(av.end.x + 24, rr.position.y + rr.size.y * 0.5 + fs * 0.36), "%d." % int(row.get("rank", i + 1)), HORIZONTAL_ALIGNMENT_LEFT, 80, fs, Color(1, 0.9, 0.5, appear * vis))
		_shadow_text(f_sans, Vector2(av.end.x + 90, rr.position.y + rr.size.y * 0.5 + fs * 0.36), str(row.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 560, fs, Color(1, 1, 1, appear * vis), 2)
		var shown := int(lerpf(0.0, float(row.get("score", 0)), clampf((_sb_t - 0.4) / 1.4, 0.0, 1.0)))
		draw_rect(Rect2(rr.end.x - 300, rr.position.y + 8, 286, rr.size.y - 16), Color(0, 0, 0, 0.75 * appear * vis))
		draw_string(f_mono, Vector2(rr.end.x - 300, rr.position.y + rr.size.y * 0.5 + fs * 0.36), PodiumScreen._fmt(shown), HORIZONTAL_ALIGNMENT_RIGHT, 274, fs, Color(1, 0.8, 0.2, appear * vis))


func _draw_sting() -> void:
	if _st_style == "hole":
		_draw_sting_hole()
		return
	var p := _st_t / _st_dur
	var fade := smoothstep(0.0, 0.08, p) * (1.0 - smoothstep(0.85, 1.0, p))
	var c := Vector2(W * 0.5, H * 0.5)
	# Per-game palette: REAL OR MILDEW? = teletext green/blue, GUESS THE GENITALS = surgical pink/cream.
	var bg := Color(0.12, 0.02, 0.22)
	var ca := Color("#ff4fa3")
	var cb := Color("#3ec9c1")
	match _st_style:
		"rom":
			bg = Color(0.0, 0.02, 0.35)
			ca = Color("#3cff6a")
			cb = Color("#2040ff")
		"gtg":
			bg = Color(0.32, 0.05, 0.12)
			ca = Color("#ff8fa8")
			cb = Color("#f4e9c8")
		"survey":   # clipboard orange / biro blue
			bg = Color(0.05, 0.08, 0.3)
			ca = Color("#ff9a1f")
			cb = Color("#f6efd8")
		"ps":       # interview-room grey / evidence-tag yellow
			bg = Color(0.1, 0.11, 0.12)
			ca = Color("#f2d230")
			cb = Color("#8fa3b0")
		"mf":       # bile green / gravy brown
			bg = Color(0.18, 0.1, 0.03)
			ca = Color("#a8c43a")
			cb = Color("#e0b07a")
	draw_rect(Rect2(0, 0, W, H), Color(bg, fade))
	if _st_style == "rom":
		for i in 40:   # teletext page flicker
			if (int(_st_t * 12.0) + i) % 5 == 0:
				draw_rect(Rect2(0, i * 27, W, 14), Color(cb, 0.25 * fade))
	var rays := 24
	for i in rays:
		var a0 := _st_t * 0.6 + TAU * i / rays
		var a1 := a0 + TAU / rays * 0.5
		var col := ca if i % 2 == 0 else cb
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * 1400, c + Vector2(cos(a1), sin(a1)) * 1400]), Color(col, 0.55 * fade))
	draw_circle(c, 300, Color(0.98, 0.85, 0.2, fade))
	draw_circle(c, 284, Color(0.2, 0.04, 0.32, fade))
	var bounce := 1.0 + 0.25 * exp(-_st_t * 5.0) * sin(_st_t * 20.0)
	draw_set_transform(c, -0.06, Vector2(bounce, bounce))
	var words := _st_title.split(" ")
	var fs := 120 if _st_title.length() < 12 else 96
	var y := -((words.size() - 1) * fs * 0.5) + fs * 0.35
	for w in words:
		_shadow_text(f_display, Vector2(-W * 0.5, y), w, HORIZONTAL_ALIGNMENT_CENTER, W, fs, Color(1, 1, 1, fade), 10)
		y += fs * 1.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## HOLE!: black beat -> a hole punches open -> rings tunnel outward -> title on the brass hit.
func _draw_sting_hole() -> void:
	var t := _st_t * (4.2 / maxf(0.5, _st_dur))   # authored against the 4.2 s audio sting
	var fade := 1.0 - smoothstep(3.7, 4.2, t)
	var c := Vector2(W * 0.5, H * 0.5)
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, fade))
	if t < 0.25:
		return  # a beat of black
	# purple field with the zooming ring tunnel
	draw_rect(Rect2(0, 0, W, H), Color(0.16, 0.02, 0.26, fade))
	var speed := 1.0 + 3.0 * smoothstep(0.3, 1.36, t)
	for i in 18:
		var r := fmod(t * 140.0 * speed + i * 70.0, 1260.0)
		var col := Color("#ff4fa3") if i % 3 == 0 else (Color("#ffd23f") if i % 3 == 1 else Color("#3ec9c1"))
		draw_arc(c, r, 0, TAU, 96, Color(col, 0.55 * fade * smoothstep(0.0, 120.0, r)), 22.0)
	# the hole itself: dives open with the slide whistle, slams on the timpani
	var hr := lerpf(10.0, 330.0, smoothstep(0.25, 1.0, t)) * (1.0 + 0.06 * exp(-maxf(0.0, t - 1.0) * 8.0) * sin((t - 1.0) * 40.0))
	draw_circle(c, hr + 18.0, Color(0.98, 0.85, 0.2, fade))
	draw_circle(c, hr, Color(0.02, 0.0, 0.04, fade))
	if t < 1.36:
		return
	var k := t - 1.36
	var bounce := 1.0 + 0.35 * exp(-k * 6.0) * sin(k * 24.0)
	draw_set_transform(c, -0.08 + 0.03 * sin(t * 3.0), Vector2(bounce, bounce))
	_shadow_text(f_display, Vector2(-W * 0.5, 52), _st_title, HORIZONTAL_ALIGNMENT_CENTER, W, 190, Color(1, 1, 1, fade), 12)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_slate() -> void:
	# Generic colour-bar slate (not a copy of any real test card).
	var bars := [Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0), Color(0, 0.75, 0.75), Color(0, 0.75, 0), Color(0.75, 0, 0.75), Color(0.75, 0, 0), Color(0, 0, 0.75)]
	for i in bars.size():
		draw_rect(Rect2(i * W / bars.size(), 0, W / bars.size() + 1, H * 0.68), bars[i])
	draw_rect(Rect2(0, H * 0.68, W, H * 0.32), Color(0.05, 0.05, 0.08))
	var box := Rect2(W * 0.5 - 520, H * 0.68 - 170, 1040, 230)
	draw_rect(box, Color.BLACK)
	draw_rect(box, Color.WHITE, false, 4.0)
	draw_string(f_sans, Vector2(box.position.x, box.position.y + 100), _slate, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 70, Color.WHITE)
	if _slate_sub != "":
		draw_string(f_mono, Vector2(box.position.x, box.position.y + 170), _slate_sub, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 30, Color(1, 1, 0.4))


func _draw_menu() -> void:
	# "Interactive home edition" menu, inside the programme frame.
	var n := menu_items.size()
	var top := 560.0 if n <= 4 else 330.0
	# Long menus scroll: a window of rows around the selection (settings, picture credits).
	var long_desc := menu_selected < n and str(menu_items[menu_selected].get("desc", "")).length() > 220
	var rows := mini(n, 4 if long_desc else 6)
	var first := clampi(menu_selected - 2, 0, maxi(0, n - rows))
	if menu_title != "":
		_shadow_text(f_display, Vector2(0, top - 40), menu_title, HORIZONTAL_ALIGNMENT_CENTER, W, 58, Color(1, 0.95, 0.8), 5)
	if first > 0:
		draw_string(f_mono, Vector2(0, top - 4), "▲", HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(1, 1, 0.4))
	if first + rows < n:
		draw_string(f_mono, Vector2(0, top + rows * 74 + 6), "▼", HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(1, 1, 0.4))
	for i in range(first, first + rows):
		var it: Dictionary = menu_items[i]
		var sel := i == menu_selected
		var r := Rect2(W * 0.5 - 400, top + (i - first) * 74, 800, 62)
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		_grad_rect(r, Color(0.1, 0.18, 0.62, 0.95) if not sel else Color(0.95, 0.75, 0.15).lerp(Color(1, 0.9, 0.4), pulse), Color(0.04, 0.06, 0.3, 0.95) if not sel else Color(0.8, 0.5, 0.05))
		draw_rect(r, Color(0.85, 0.85, 0.95), false, 3.0)
		var label := str(it.get("label", ""))
		if it.has("value"):
			label += ":  " + str(it.value)
		draw_string(f_sans, Vector2(r.position.x, r.position.y + 43), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 32, Color(0.12, 0.02, 0.2) if sel else Color.WHITE)
	var desc := ""
	if menu_selected < menu_items.size():
		desc = str(menu_items[menu_selected].get("desc", ""))
	var y := top + rows * 74 + 34
	var dfs := 20 if long_desc else 26
	var dlh := 26.0 if long_desc else 34.0
	var dlines := _wrap(desc, 100 if long_desc else 56)
	var max_lines := int((H - 170 - y) / dlh)
	if dlines.size() > max_lines:
		dlines = dlines.slice(0, max_lines)
		dlines[-1] = str(dlines[-1]) + " …"
	for line in dlines:
		draw_string(f_mono, Vector2(0, y), line, HORIZONTAL_ALIGNMENT_CENTER, W, dfs, Color(0.85, 1, 0.75))
		y += dlh
	if menu_footer != "":
		draw_rect(Rect2(0, H - 160, W, 50), Color(0, 0, 0, 0.75))
		draw_string(f_mono, Vector2(0, H - 125), menu_footer, HORIZONTAL_ALIGNMENT_CENTER, W, 26, Color(1, 1, 0.4))
