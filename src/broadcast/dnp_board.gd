class_name DnpBoard
extends Control
## TV graphic for DO NOT PRESS THAT (CP6): a 1970s control-room mimic panel.
## Shows the shared information the instructions refer to (lamps / pressure gauge / canteen card),
## a SYSTEMS OK meter, mistakes as red strikes with the culprit's name, the clock, and the success
## tier stamp. The rare timer irregularity makes this clock run early; phones keep the real time.

const W := 1440.0
const H := 1080.0
const LAMP_COL := {"RED": Color("#ff3b30"), "GREEN": Color("#3ee05a"), "BLUE": Color("#3a7bff"), "AMBER": Color("#ffb020"),
	"WHITE": Color("#f4f1e6"), "PINK": Color("#ff6fb5"), "VIOLET": Color("#9a5cff"), "GREY": Color("#9a9a96")}
const TIER_TEXT := {"perfect": "PERFECT", "completed": "COMPLETED", "barely": "BARELY COMPLETED", "failed": "FAILED SPECTACULARLY"}

var f_display: Font
var f_sans: Font
var f_mono: Font
var players := {}

var _vis := 0.0
var _target := 0.0
var _t := 0.0
var _title := ""
var _flavour := ""
var _display := {}
var _round := 0
var _of := 0
var _solved := 0
var _total := 1
var _mistakes := 0
var _timer := -1.0
var _timer_total := 1.0
var _offset := 0.0
var _flash_name := ""
var _flash_t := -100.0
var _tier := ""
var _tier_t := 0.0


func _ready() -> void:
	f_display = load("res://assets/fonts/InterDisplay-BlackItalic.otf")
	f_sans = load("res://assets/fonts/LiberationSans-Bold.ttf")
	f_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func on_event(evt: Dictionary, time_scale: float) -> void:
	var ts := maxf(time_scale, 0.001)
	match str(evt.get("e")):
		"dnp_puzzle":
			_title = str(evt.title)
			_flavour = str(evt.get("flavour", ""))
			_display = evt.get("display", {})
			_round = int(evt.get("round", 0))
			_of = int(evt.get("of", 0))
			_total = maxi(1, int(evt.get("controls", 1)))
			_solved = 0
			_mistakes = 0
			_tier = ""
			_timer = -1.0
			_offset = 0.0
			_target = 1.0
		"dnp_open":
			_timer = float(evt.window) / ts
			_timer_total = maxf(0.1, _timer)
			_offset = float(evt.get("tv_offset", 0.0)) / ts
			_solved = int(evt.get("solved", 0))
		"dnp_state":
			_solved = int(evt.solved)
			_total = maxi(1, int(evt.of))
			_mistakes = int(evt.mistakes)
		"dnp_mistake":
			_mistakes += 1
			_flash_name = str(players.get(str(evt.pid), {}).get("name", "SOMEBODY")).to_upper()
			_flash_t = _t
			_timer = maxf(0.0, _timer - 5.0 / ts)
		"dnp_result":
			_tier = str(evt.tier)
			_tier_t = _t
			_timer = -1.0


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


func _draw() -> void:
	if _vis <= 0.001:
		return
	var a := _vis
	draw_rect(Rect2(0, 0, W, H), Color(0.12, 0.13, 0.12, 0.96 * a))
	# mimic-panel bezel
	draw_rect(Rect2(40, 30, W - 80, H - 60), Color(0.3, 0.33, 0.3, a), false, 6.0)
	for i in 6:
		draw_circle(Vector2(60 + i * (W - 120) / 5.0, 50), 6, Color(0.55, 0.55, 0.5, a))
	draw_rect(Rect2(70, 70, W - 140, 90), Color(0.05, 0.05, 0.05, a))
	draw_string(f_mono, Vector2(90, 128), "DO NOT PRESS THAT" + ("   %d/%d" % [_round, _of] if _of > 0 else ""), HORIZONTAL_ALIGNMENT_LEFT, 700, 30, Color(1, 0.75, 0.15, a))
	draw_string(f_sans, Vector2(0, 230), _title, HORIZONTAL_ALIGNMENT_CENTER, W, 64, Color(1, 1, 1, a))
	draw_string(f_mono, Vector2(0, 280), _flavour.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(0.7, 0.75, 0.7, a))
	_draw_display(Rect2(140, 320, W - 280, 380), a)
	_draw_status(a)
	if _tier != "":
		_draw_tier(a)


func _draw_display(r: Rect2, a: float) -> void:
	draw_rect(r, Color(0.04, 0.05, 0.04, a))
	draw_rect(r, Color(0.45, 0.5, 0.45, a), false, 3.0)
	match str(_display.get("kind", "")):
		"lamps":
			var lamps: Array = _display.get("lamps", [])
			var n := lamps.size()
			var w := r.size.x / maxf(1.0, n)
			for i in n:
				var l: Dictionary = lamps[i]
				var c := r.position + Vector2(w * (i + 0.5), r.size.y * 0.42)
				var col: Color = LAMP_COL.get(str(l.colour), Color.WHITE)
				draw_circle(c, 62, Color(0.15, 0.15, 0.15, a))
				if bool(l.lit):
					draw_circle(c, 70, Color(col, 0.18 * a))
					draw_circle(c, 52, Color(col, a))
					draw_circle(c + Vector2(-16, -18), 14, Color(1, 1, 1, 0.45 * a))
				else:
					draw_circle(c, 52, Color(col.darkened(0.8), a))
				var lab := str(l.get("label", ""))
				if lab != "":
					draw_string(f_mono, Vector2(r.position.x + w * i, r.position.y + r.size.y - 50), lab, HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(0.9, 0.9, 0.85, a))
		"gauge":
			var c2 := r.get_center() + Vector2(0, 70)
			var rad := 230.0
			draw_arc(c2, rad, PI, TAU, 64, Color(0.85, 0.85, 0.8, a), 6.0)
			for k in 11:
				var ang := PI + PI * k / 10.0
				draw_line(c2 + Vector2(cos(ang), sin(ang)) * (rad - 24), c2 + Vector2(cos(ang), sin(ang)) * rad, Color(0.85, 0.85, 0.8, a), 4.0)
				draw_string(f_mono, c2 + Vector2(cos(ang), sin(ang)) * (rad - 56) + Vector2(-16, 10), str(k), HORIZONTAL_ALIGNMENT_CENTER, 32, 24, Color(0.9, 0.9, 0.85, a))
			var g := float(_display.get("gauge", 0)) + 0.06 * sin(_t * 9.0)   # needle tremble
			var na := PI + PI * g / 10.0
			draw_line(c2, c2 + Vector2(cos(na), sin(na)) * (rad - 30), Color(1, 0.3, 0.2, a), 6.0)
			draw_circle(c2, 14, Color(0.2, 0.2, 0.2, a))
			draw_string(f_mono, Vector2(r.position.x, r.end.y - 16), "PRESSURE", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, Color(0.8, 0.8, 0.75, a))
		"card":
			var card: Dictionary = _display.get("card", {})
			var cr := Rect2(r.get_center() - Vector2(320, 160), Vector2(640, 320))
			draw_rect(cr, Color("#f3efe4", a))
			draw_string(f_mono, cr.position + Vector2(24, 44), "CANTEEN STOCK CARD", HORIZONTAL_ALIGNMENT_LEFT, 600, 24, Color(0.5, 0.1, 0.1, a))
			var y := cr.position.y + 110
			for it in card:
				draw_string(f_sans, Vector2(cr.position.x + 40, y), str(it), HORIZONTAL_ALIGNMENT_LEFT, 300, 40, Color(0.1, 0.1, 0.12, a))
				for k in int(card[it]):
					draw_circle(Vector2(cr.position.x + 380 + k * 56, y - 14), 20, Color(0.15, 0.2, 0.5, a))
				y += 80


func _draw_status(a: float) -> void:
	var br := Rect2(140, 740, W - 280, 40)
	draw_rect(br, Color(0.04, 0.05, 0.04, a))
	var frac := float(_solved) / maxf(1.0, _total)
	draw_rect(Rect2(br.position, Vector2(br.size.x * frac, br.size.y)), Color(0.25, 0.85, 0.35, a))
	draw_string(f_mono, Vector2(br.position.x, br.position.y - 12), "SYSTEMS OK: %d / %d" % [_solved, _total], HORIZONTAL_ALIGNMENT_LEFT, 600, 26, Color(0.8, 0.95, 0.8, a))
	for k in mini(_mistakes, 8):
		var c := Vector2(br.end.x - 30 - k * 46, br.position.y - 24)
		draw_line(c + Vector2(-14, -14), c + Vector2(14, 14), Color(1, 0.2, 0.15, a), 6.0)
		draw_line(c + Vector2(-14, 14), c + Vector2(14, -14), Color(1, 0.2, 0.15, a), 6.0)
	if _timer >= 0.0:
		var shown := maxf(0.0, _timer - _offset)
		var blink := shown <= 0.0 and int(_t * 3.0) % 2 == 0
		var col := Color(1, 0.25, 0.2, a) if shown < 10.0 else Color(1, 0.85, 0.3, a)
		if not blink:
			draw_string(f_mono, Vector2(0, 900), "%02d" % int(ceil(shown)), HORIZONTAL_ALIGNMENT_CENTER, W, 110, col)
	var ft := _t - _flash_t
	if ft < 2.2:
		var fa := a * clampf(2.2 - ft, 0.0, 1.0)
		draw_rect(Rect2(0, 800, W, 130), Color(0.6, 0.05, 0.05, 0.85 * fa))
		draw_string(f_display, Vector2(0, 890), "JAMMED BY %s" % _flash_name, HORIZONTAL_ALIGNMENT_CENTER, W, 70, Color(1, 1, 1, fa))


func _draw_tier(a: float) -> void:
	var tt := _t - _tier_t
	var sc := 1.0 + 0.8 * exp(-tt * 7.0)
	var col := Color(0.2, 0.85, 0.3) if _tier in ["perfect", "completed"] else (Color(1, 0.7, 0.1) if _tier == "barely" else Color(1, 0.2, 0.15))
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.45 * a))
	draw_set_transform(Vector2(W * 0.5, H * 0.5), -0.06, Vector2(sc, sc))
	draw_rect(Rect2(-560, -90, 1120, 180), Color(col, a), false, 10.0)
	var txt: String = TIER_TEXT.get(_tier, _tier.to_upper())
	draw_string(f_display, Vector2(-560, 36), txt, HORIZONTAL_ALIGNMENT_CENTER, 1120, 96 if txt.length() < 12 else 70, Color(col, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
