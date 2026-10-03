class_name AdvertPlayer
extends Control
## Fake late-90s adverts and break bumpers (CP8), drawn as cheap regional motion graphics:
## gradient backdrops with sunbursts / stripes / checks / bubbles, a procedurally drawn packshot
## (can, box, jar, bottle, tub, bar, crisp packet), bouncing headlines, small print.
## Adverts come from data (content/adverts/*.json); nothing here is a real brand.

const W := 1440.0
const H := 1080.0

var f_display: Font
var f_sans: Font
var f_mono: Font
var f_serif: Font

var _ad := {}
var _t := 0.0
var _start := 0.0
var _scale := 1.0
var _card := {}               # bumper/interval card: {kind, seconds, title, sub}
var _card_t := 0.0
var _ready_n := 0
var _ready_of := 0
var _showing := false
var _poll := {}               # {prompt, options, tally}
var _awards: Array = []       # [{title, name, avatar, prize, t}]
var players := {}


func _ready() -> void:
	f_display = load("res://assets/fonts/InterDisplay-BlackItalic.otf")
	f_sans = load("res://assets/fonts/LiberationSans-Bold.ttf")
	f_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")
	f_serif = load("res://assets/fonts/LiberationSerif-BoldItalic.ttf")
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func play(ad: Dictionary, time_scale: float) -> void:
	_ad = ad
	_card = {}
	_start = _t
	_scale = maxf(time_scale, 0.001)
	_showing = true


func show_card(card: Dictionary, time_scale: float) -> void:
	_card = card
	_ad = {}
	_card_t = _t
	_scale = maxf(time_scale, 0.001)
	_showing = true


func show_poll(evt: Dictionary) -> void:
	_ad = {}
	_card = {}
	_awards = []
	_poll = {"prompt": str(evt.prompt), "options": evt.options, "tally": [], "count": 0, "t": _t}
	_showing = true


func poll_progress(count: int) -> void:
	_poll["count"] = count


func poll_result(evt: Dictionary) -> void:
	_poll["tally"] = evt.get("tally", [])
	_poll["rt"] = _t


func show_award(evt: Dictionary) -> void:
	if _awards.is_empty():
		_ad = {}
		_card = {}
		_poll = {}
	var p: Dictionary = players.get(str(evt.get("pid", "")), {})
	_awards.append({"title": str(evt.title), "name": str(p.get("name", "?")).to_upper(), "avatar": p.get("avatar", {}), "prize": str(evt.get("prize", "")), "t": _t})
	_showing = true


func set_ready(n: int, of: int) -> void:
	_ready_n = n
	_ready_of = of


func stop() -> void:
	_showing = false
	_ad = {}
	_card = {}
	_poll = {}
	_awards = []
	queue_redraw()


func is_showing() -> bool:
	return _showing


func _process(delta: float) -> void:
	_t += delta
	if _showing:
		queue_redraw()


# ---------------------------------------------------------------------------

func _draw() -> void:
	if not _showing:
		return
	if not _card.is_empty():
		_draw_card()
		return
	if not _poll.is_empty():
		_draw_poll()
		return
	if not _awards.is_empty():
		_draw_awards()
		return
	var scenes: Array = _ad.get("scenes", [])
	if scenes.is_empty():
		return
	var el := (_t - _start) * _scale        # programme seconds into the advert
	var acc := 0.0
	var idx := scenes.size() - 1
	for i in scenes.size():
		if el < acc + float(scenes[i].t):
			idx = i
			break
		acc += float(scenes[i].t)
	var s: Dictionary = scenes[idx]
	var local := clampf(el - acc, 0.0, float(s.t))
	_draw_scene(s, local, float(s.t))
	# cheap video-wipe between scenes
	if local < 0.18 and idx > 0:
		draw_rect(Rect2(0, 0, W * (1.0 - local / 0.18), H), Color(1, 1, 1, 0.85))


func _col(hex: String) -> Color:
	return Color(hex) if hex.begins_with("#") else Color.WHITE


func _draw_scene(s: Dictionary, lt: float, dur: float) -> void:
	var bg: Array = s.get("bg", ["#333333", "#111111"])
	var c1 := _col(str(bg[0]))
	var c2 := _col(str(bg[1] if bg.size() > 1 else bg[0]))
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(W, 0), Vector2(W, H), Vector2(0, H)]), PackedColorArray([c1, c1, c2, c2]))
	var ctr := Vector2(W * 0.5, H * 0.45)
	match str(s.get("pattern", "plain")):
		"sunburst":
			for i in 20:
				var a0 := lt * 0.4 + TAU * i / 20.0
				draw_colored_polygon(PackedVector2Array([ctr, ctr + Vector2(cos(a0), sin(a0)) * 1500, ctr + Vector2(cos(a0 + 0.16), sin(a0 + 0.16)) * 1500]), Color(1, 1, 1, 0.12))
		"stripes":
			for i in 30:
				var x := fmod(i * 120.0 + lt * 160.0, W + 240.0) - 240.0
				draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 60, 0), Vector2(x + 260, H), Vector2(x + 200, H)]), Color(1, 1, 1, 0.1))
		"checker":
			for y in 10:
				for x in 13:
					if (x + y) % 2 == 0:
						draw_rect(Rect2(x * 120 - fmod(lt * 40.0, 120.0), y * 120, 120, 120), Color(0, 0, 0, 0.12))
		"grid":
			for i in 25:
				draw_rect(Rect2(0, i * 48 + fmod(lt * 30.0, 48.0), W, 2), Color(1, 1, 1, 0.08))
				draw_rect(Rect2(i * 64, 0, 2, H), Color(1, 1, 1, 0.06))
		"bubbles":
			for i in 24:
				var bx := fmod(i * 173.0, W)
				var by := H - fmod(lt * (60.0 + i * 7.0) + i * 97.0, H + 100.0)
				draw_arc(Vector2(bx, by), 18.0 + (i % 5) * 9.0, 0, TAU, 32, Color(1, 1, 1, 0.35), 3.0)
	var has_product := s.has("product")
	if has_product:
		var p: Dictionary = s.product
		var pin := clampf(lt / 0.5, 0.0, 1.0)
		var prot := 0.0
		var psc := lerpf(0.4, 1.35, ease(pin, 0.4))
		match str(s.get("anim", "")):
			"spin":
				prot = sin(lt * 2.0) * 0.25
			"bounce":
				psc *= 1.0 + 0.04 * sin(lt * 9.0)
		_draw_product(Vector2(W * 0.5, H * 0.42), psc, prot, p)
	# headline
	var head := str(s.get("headline", ""))
	if head != "":
		var hin := clampf((lt - 0.15) / 0.35, 0.0, 1.0)
		var hy := H * (0.80 if has_product else 0.45)
		var off := Vector2.ZERO
		var hsc := 1.0
		match str(s.get("anim", "zoom")):
			"slide":
				off.x = (1.0 - ease(hin, 0.3)) * -W
			"bounce":
				hsc = 1.0 + 0.3 * exp(-lt * 6.0) * sin(lt * 18.0)
			_:
				hsc = lerpf(2.4, 1.0, ease(hin, 0.3))
		var fs := 92 if head.length() <= 14 else (70 if head.length() <= 24 else 54)
		draw_set_transform(Vector2(W * 0.5, hy) + off, -0.04, Vector2(hsc, hsc))
		var lines := _wrap(f_display, head, W - 160, fs)
		var y := -((lines.size() - 1) * fs * 0.55)
		for l in lines:
			for k in range(8, 0, -2):
				draw_string(f_display, Vector2(-W * 0.5 + k, y + k), l, HORIZONTAL_ALIGNMENT_CENTER, W, fs, Color(0, 0, 0, 0.5 * hin))
			draw_string(f_display, Vector2(-W * 0.5, y), l, HORIZONTAL_ALIGNMENT_CENTER, W, fs, Color(1, 1, 1, hin))
			y += fs * 1.05
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var sub := str(s.get("sub", ""))
	if sub != "":
		var sa := clampf((lt - 0.6) / 0.3, 0.0, 1.0)
		var sy := H * (0.90 if has_product else 0.62)
		var tw := f_sans.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		draw_rect(Rect2(W * 0.5 - tw * 0.5 - 20, sy - 40, tw + 40, 54), Color(0, 0, 0, 0.55 * sa))
		draw_string(f_sans, Vector2(0, sy), sub, HORIZONTAL_ALIGNMENT_CENTER, W, 34, Color(1, 0.95, 0.4, sa))
	var tag := str(s.get("tag", ""))
	if tag != "":
		draw_string(f_mono, Vector2(0, H - 22), tag, HORIZONTAL_ALIGNMENT_CENTER, W, 16, Color(1, 1, 1, 0.75))


func _draw_product(c: Vector2, sc: float, rot: float, p: Dictionary) -> void:
	var cols: Array = p.get("colours", ["#c8202f", "#f2e2c0"])
	var a := _col(str(cols[0]))
	var b := _col(str(cols[1] if cols.size() > 1 else cols[0]))
	var label := str(p.get("label", ""))
	draw_set_transform(c, rot, Vector2(sc, sc))
	draw_circle(Vector2(0, 250), 10, Color(0, 0, 0, 0))   # keep transform origin stable
	var shadow := Color(0, 0, 0, 0.35)
	match str(p.get("shape", "box")):
		"can":
			draw_rect(Rect2(-130, -170, 260, 340), a)
			draw_rect(Rect2(-130, -60, 260, 120), b)
			draw_rect(Rect2(-130, -170, 260, 20), a.lightened(0.3))
			draw_rect(Rect2(-130, 150, 260, 20), a.darkened(0.3))
			draw_rect(Rect2(-130, -170, 50, 340), Color(1, 1, 1, 0.15))
		"jar", "tub":
			var h := 200.0 if str(p.shape) == "tub" else 300.0
			draw_rect(Rect2(-160, -h * 0.5, 320, h), a)
			draw_rect(Rect2(-170, -h * 0.5 - 36, 340, 40), b.darkened(0.2))
			draw_rect(Rect2(-160, -40, 320, 80), b)
		"bottle":
			draw_rect(Rect2(-110, -90, 220, 280), a)
			draw_colored_polygon(PackedVector2Array([Vector2(-110, -90), Vector2(110, -90), Vector2(40, -170), Vector2(-40, -170)]), a)
			draw_rect(Rect2(-40, -230, 80, 64), b.darkened(0.3))
			draw_rect(Rect2(-110, 0, 220, 110), b)
			draw_rect(Rect2(-110, -90, 40, 280), Color(1, 1, 1, 0.18))
		"bar":
			draw_set_transform(c, rot - 0.2, Vector2(sc, sc))
			draw_rect(Rect2(-300, -70, 600, 140), a)
			draw_rect(Rect2(-180, -70, 360, 140), b)
			draw_rect(Rect2(-300, -70, 600, 20), Color(1, 1, 1, 0.15))
		"packet":
			draw_colored_polygon(PackedVector2Array([Vector2(-150, -190), Vector2(150, -190), Vector2(170, 190), Vector2(-170, 190)]), a)
			for k in 8:
				draw_rect(Rect2(-150 + k * 38, -200, 18, 16), a.darkened(0.25))
				draw_rect(Rect2(-170 + k * 43, 186, 20, 16), a.darkened(0.25))
			draw_circle(Vector2(0, 30), 110, b)
		_:
			draw_rect(Rect2(-180, -160, 360, 320), a)
			draw_colored_polygon(PackedVector2Array([Vector2(180, -160), Vector2(230, -200), Vector2(230, 120), Vector2(180, 160)]), a.darkened(0.35))
			draw_colored_polygon(PackedVector2Array([Vector2(-180, -160), Vector2(-130, -200), Vector2(230, -200), Vector2(180, -160)]), a.lightened(0.2))
			draw_rect(Rect2(-180, -50, 360, 100), b)
	var fs := 58 if label.length() <= 8 else (42 if label.length() <= 12 else 30)
	draw_string(f_display, Vector2(-300, 20), label, HORIZONTAL_ALIGNMENT_CENTER, 600, fs, Color(0.08, 0.05, 0.05))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(c + Vector2(0, 230 * sc), 0.1, shadow)


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


## Break bumpers: "END OF PART ONE" / interval / "PART TWO", in the programme's own livery.
func _draw_card() -> void:
	var el := (_t - _card_t) * _scale
	draw_rect(Rect2(0, 0, W, H), Color(0.06, 0.12, 0.08))
	for i in 18:
		var r := 120.0 + i * 60.0 + fmod(el * 40.0, 60.0)
		draw_arc(Vector2(W * 0.5, H * 0.45), r, 0, TAU, 96, Color(0.35, 0.8, 0.45, 0.06), 6.0)
	draw_string(f_display, Vector2(0, H * 0.36), "MILDEW", HORIZONTAL_ALIGNMENT_CENTER, W, 150, Color(0.75, 0.95, 0.5))
	draw_string(f_sans, Vector2(0, H * 0.50), str(_card.get("title", "")), HORIZONTAL_ALIGNMENT_CENTER, W, 56, Color(1, 1, 1))
	var sub := str(_card.get("sub", ""))
	if sub != "":
		draw_string(f_mono, Vector2(0, H * 0.58), sub, HORIZONTAL_ALIGNMENT_CENTER, W, 28, Color(0.9, 0.9, 0.8))
	if str(_card.get("kind", "")) == "interval":
		var left := maxf(0.0, float(_card.get("seconds", 0.0)) - el)
		var s := int(ceil(left))
		draw_string(f_mono, Vector2(0, H * 0.72), "THE PROGRAMME WILL RETURN IN %d:%02d" % [s / 60, s % 60], HORIZONTAL_ALIGNMENT_CENTER, W, 34, Color(1, 0.85, 0.3))
		if _ready_of > 0:
			draw_string(f_mono, Vector2(0, H * 0.80), "BACK ON THE SOFA: %d / %d" % [_ready_n, _ready_of], HORIZONTAL_ALIGNMENT_CENTER, W, 30, Color(0.7, 0.95, 0.6))
	draw_string(f_mono, Vector2(0, H - 40), "SALLOW ENTERTAINMENT LTD", HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color(0.6, 0.7, 0.6))


## VIEWER POLL: a 90s phone-in results board.
func _draw_poll() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.08, 0.05, 0.25))
	for i in 30:
		draw_rect(Rect2(0, i * 36, W, 2), Color(0.5, 0.4, 1.0, 0.08))
	draw_rect(Rect2(60, 60, W - 120, 90), Color(1, 0.85, 0.2))
	draw_string(f_display, Vector2(0, 128), "VIEWER POLL", HORIZONTAL_ALIGNMENT_CENTER, W, 64, Color(0.1, 0.05, 0.25))
	var lines := _wrap(f_sans, str(_poll.prompt), W - 200, 46)
	var y := 230.0
	for l in lines:
		draw_string(f_sans, Vector2(0, y), l, HORIZONTAL_ALIGNMENT_CENTER, W, 46, Color(1, 1, 1))
		y += 56
	var opts: Array = _poll.options
	var tally: Array = _poll.get("tally", [])
	var total := 0
	for v in tally:
		total += int(v)
	var reveal := not tally.is_empty()
	var grow := clampf((_t - float(_poll.get("rt", _t))) * 1.5, 0.0, 1.0) if reveal else 0.0
	y = maxf(y + 30, 420.0)
	var bh := minf(110.0, 520.0 / maxf(1, opts.size()))
	for i in opts.size():
		var r := Rect2(140, y + i * bh, W - 280, bh - 20)
		draw_rect(r, Color(0, 0, 0, 0.4))
		var frac := (float(tally[i]) / maxf(1.0, total)) if reveal and i < tally.size() else 0.0
		draw_rect(Rect2(r.position, Vector2(r.size.x * frac * grow, r.size.y)), Color(0.3, 0.8, 1.0, 0.8))
		draw_string(f_sans, r.position + Vector2(20, r.size.y * 0.5 + 14), str(opts[i]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 200, 38, Color(1, 1, 1))
		if reveal:
			draw_string(f_mono, Vector2(r.end.x - 180, r.position.y + r.size.y * 0.5 + 14), "%d%%" % int(round(frac * 100.0 * grow)), HORIZONTAL_ALIGNMENT_RIGHT, 160, 38, Color(1, 0.9, 0.3))
	if not reveal:
		draw_string(f_mono, Vector2(0, H - 70), "VOTE ON YOUR UNIT NOW · VOTES IN: %d" % int(_poll.get("count", 0)), HORIZONTAL_ALIGNMENT_CENTER, W, 30, Color(1, 0.85, 0.3))
	else:
		draw_string(f_mono, Vector2(0, H - 70), "THESE RESULTS ARE FINAL AND MEANINGLESS", HORIZONTAL_ALIGNMENT_CENTER, W, 24, Color(0.8, 0.8, 1))


## THE MILDEW AWARDS: gold-foil cards, one per award, the star prize last.
func _draw_awards() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.12, 0.02, 0.06))
	for i in 24:
		var a0 := _t * 0.2 + TAU * i / 24.0
		draw_colored_polygon(PackedVector2Array([Vector2(W * 0.5, -100), Vector2(W * 0.5, -100) + Vector2(cos(a0), sin(a0)) * 1600, Vector2(W * 0.5, -100) + Vector2(cos(a0 + 0.1), sin(a0 + 0.1)) * 1600]), Color(1, 0.8, 0.3, 0.05))
	draw_string(f_display, Vector2(0, 120), "THE MILDEW AWARDS", HORIZONTAL_ALIGNMENT_CENTER, W, 72, Color(1, 0.85, 0.35))
	var n := _awards.size()
	var y := 190.0
	var ch := minf(200.0, 820.0 / maxf(1, n))
	for i in n:
		var aw: Dictionary = _awards[i]
		var a := clampf((_t - float(aw.t)) * 3.0, 0.0, 1.0)
		var r := Rect2(160 + (1.0 - a) * 300.0, y + i * ch, W - 320, ch - 20)
		var gold := Color(0.85, 0.65, 0.2, a)
		draw_rect(r, Color(0.2, 0.06, 0.1, a))
		draw_rect(r, gold, false, 4.0)
		AvatarPainter.draw(self, Rect2(r.position + Vector2(16, 12), Vector2(r.size.y - 24, r.size.y - 24)), aw.avatar)
		var tx := r.position.x + r.size.y + 10
		draw_string(f_mono, Vector2(tx, r.position.y + 44), str(aw.title), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - r.size.y - 30, 26, gold)
		draw_string(f_display, Vector2(tx, r.position.y + 44 + minf(70.0, r.size.y * 0.45)), str(aw.name), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - r.size.y - 30, 52, Color(1, 1, 1, a))
		if str(aw.prize) != "":
			draw_string(f_sans, Vector2(tx, r.end.y - 14), "WINS: " + str(aw.prize), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - r.size.y - 30, 26, Color(1, 0.9, 0.5, a))
