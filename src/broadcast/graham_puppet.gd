class_name GrahamPuppet
extends Node2D
## PROVISIONAL Graham Mildew renderer: a procedurally drawn, believable (non-cartoon-proportioned)
## late-40s/50s British presenter bust — dated side-parted hair, big gold glasses, burgundy
## suit, loud tie, heavy makeup and perspiration — composited into the 3D studio as an
## "FMV plate" on a quad and softened by the broadcast shader.
##
## Presentation contract (docs/08 hybrid FMV): callers only use set_mood(), set_activity(),
## speak(seconds), set_pressure(). A future FmvGraham that plays pre-rendered state loops can
## implement the same API without touching the Director, session or presenter.
##
## Canvas: 512 x 640, transparent background.

const W := 512.0
const H := 640.0

# Visible emotional states (docs/02) and activities (CLAUDE.md §4 state list).
var mood := "relaxed"            # relaxed pleased amused irritated angry embarrassed rattled
var activity := "idle"           # idle speaking waiting stare look_off reading laughing
var pressure := 0.1              # 0..1 -> sweat, tie loosened, hair displaced

var _t := 0.0
var _speak_left := 0.0
var _mouth := "rest"
var _mouth_timer := 0.0
var _blink := 0.0
var _blink_timer := 3.0
var _look := Vector2.ZERO         # eye direction (-1..1)
var _look_target := Vector2.ZERO
var _head_turn := 0.0             # -1..1 (look off camera)
var _head_turn_target := 0.0
var _tilt := 0.0
var _tilt_target := 0.0
var _brow := 0.0                  # -1 angry .. +1 raised
var _brow_target := 0.0
var _flush := 0.0
var _flush_target := 0.0
var _laugh := 0.0
var _rng := RandomNumberGenerator.new()

# Palette — late-90s studio grade.
const SKIN := Color(0.86, 0.6, 0.45)
const SKIN_MAKEUP := Color(0.93, 0.66, 0.48)
const SKIN_SHADOW := Color(0.62, 0.38, 0.29)
const HAIR := Color(0.36, 0.29, 0.24)
const HAIR_GREY := Color(0.62, 0.6, 0.57)
const SUIT := Color(0.40, 0.10, 0.15)
const SUIT_DARK := Color(0.20, 0.04, 0.08)
const SUIT_SHEEN := Color(0.62, 0.22, 0.28)
const SHIRT := Color(0.94, 0.93, 0.88)
const TIE_A := Color(0.85, 0.65, 0.12)
const TIE_B := Color(0.35, 0.12, 0.55)
const GOLD := Color(0.86, 0.7, 0.32)


func _ready() -> void:
	_rng.randomize()


func set_mood(m: String) -> void:
	mood = m
	match m:
		"pleased":
			_brow_target = 0.35
			_flush_target = 0.05
		"amused":
			_brow_target = 0.2
			_flush_target = 0.05
		"irritated":
			_brow_target = -0.55
			_flush_target = 0.12
		"angry":
			_brow_target = -1.0
			_flush_target = 0.35
		"embarrassed":
			_brow_target = 0.5
			_flush_target = 0.4
		"rattled":
			_brow_target = 0.75
			_flush_target = 0.1
		_:
			_brow_target = 0.0
			_flush_target = 0.0


func set_activity(a: String) -> void:
	activity = a
	match a:
		"look_off":
			_head_turn_target = 0.8
			_look_target = Vector2(1.0, 0.0)
		"stare":
			_head_turn_target = 0.0
			_look_target = Vector2.ZERO
		"reading":
			_head_turn_target = 0.0
			_look_target = Vector2(0.1, 1.0)
		"waiting":
			_head_turn_target = 0.0
		_:
			_head_turn_target = 0.0
			_look_target = Vector2.ZERO


func set_pressure(p: float) -> void:
	pressure = clampf(p, 0.0, 1.0)


func speak(seconds: float) -> void:
	_speak_left = seconds
	if activity in ["idle", "waiting", "look_off"]:
		activity = "speaking"
		_head_turn_target = 0.0
		_look_target = Vector2.ZERO


func is_speaking() -> bool:
	return _speak_left > 0.0


func _process(delta: float) -> void:
	_t += delta
	if _speak_left > 0.0:
		_speak_left -= delta
		_mouth_timer -= delta
		if _mouth_timer <= 0.0:
			_mouth_timer = _rng.randf_range(0.07, 0.14)
			var shapes := ["open", "mid", "wide", "o", "closed", "mid"]
			_mouth = shapes[_rng.randi_range(0, shapes.size() - 1)]
		if _speak_left <= 0.0 and activity == "speaking":
			activity = "idle"
	else:
		_mouth = "rest"
	# Blinking (never while staring).
	_blink_timer -= delta
	if _blink_timer <= 0.0 and activity != "stare":
		_blink = 1.0
		_blink_timer = _rng.randf_range(2.2, 5.5)
	_blink = maxf(0.0, _blink - delta * 9.0)
	# Idle micro-movements: small glances, tilts. Waiting = glancing at the floor manager.
	if activity == "waiting" and _rng.randf() < delta * 0.5:
		_look_target = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 0.3))
		_head_turn_target = _look_target.x * 0.35
	elif activity in ["idle", "speaking"] and _rng.randf() < delta * 0.25:
		_look_target = Vector2(_rng.randf_range(-0.15, 0.15), _rng.randf_range(-0.1, 0.1))
	if _rng.randf() < delta * 0.3:
		_tilt_target = _rng.randf_range(-0.04, 0.04) + (-0.05 if mood == "irritated" else 0.0)
	_laugh = move_toward(_laugh, 1.0 if activity == "laughing" else 0.0, delta * 4.0)
	var k := 1.0 - exp(-delta * 7.0)
	_look = _look.lerp(_look_target, k)
	_head_turn = lerpf(_head_turn, _head_turn_target, 1.0 - exp(-delta * 4.0))
	_tilt = lerpf(_tilt, _tilt_target, 1.0 - exp(-delta * 3.0))
	_brow = lerpf(_brow, _brow_target, k)
	_flush = lerpf(_flush, _flush_target, 1.0 - exp(-delta * 1.5))
	queue_redraw()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var breath := sin(_t * 1.6) * 2.5
	var bob := (sin(_t * 9.0) * 1.5 if _speak_left > 0.0 else 0.0) - _laugh * 6.0
	_draw_body(breath)
	var head_c := Vector2(256 + _head_turn * 14.0, 292 + breath * 0.6 + bob)
	draw_set_transform(head_c, _tilt - _laugh * 0.08, Vector2.ONE)
	_draw_head()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _fan(center: Vector2, pts: PackedVector2Array, c_center: Color, c_edge: Color) -> void:
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		draw_polygon(PackedVector2Array([center, a, b]), PackedColorArray([c_center, c_edge, c_edge]))


func _ellipse_pts(c: Vector2, rx: float, ry: float, n: int = 40, a0: float = 0.0, a1: float = TAU) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := lerpf(a0, a1, float(i) / float(n if a1 - a0 >= TAU - 0.001 else n - 1))
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw_body(breath: float) -> void:
	var y := 470.0 - breath
	var loosen := clampf((pressure - 0.55) * 2.5, 0.0, 1.0)
	# Jacket
	var jacket := PackedVector2Array([Vector2(18, H), Vector2(40, y + 70), Vector2(110, y + 8), Vector2(256, y - 14),
		Vector2(402, y + 8), Vector2(472, y + 70), Vector2(494, H)])
	_fan(Vector2(256, y + 120), jacket, SUIT, SUIT_DARK)
	# Shoulder sheen (cheap shiny suit)
	draw_polygon(PackedVector2Array([Vector2(80, y + 30), Vector2(150, y + 4), Vector2(175, y + 20), Vector2(100, y + 52)]),
		PackedColorArray([SUIT_SHEEN.lerp(SUIT, 0.6), SUIT_SHEEN, SUIT, SUIT]))
	draw_polygon(PackedVector2Array([Vector2(432, y + 30), Vector2(362, y + 4), Vector2(337, y + 20), Vector2(412, y + 52)]),
		PackedColorArray([SUIT_SHEEN.lerp(SUIT, 0.6), SUIT_SHEEN, SUIT, SUIT]))
	# Shirt V
	var collar_open := loosen * 10.0
	draw_colored_polygon(PackedVector2Array([Vector2(196, y - 4), Vector2(316, y - 4), Vector2(256, y + 150)]), SHIRT)
	draw_colored_polygon(PackedVector2Array([Vector2(214 - collar_open, y - 10), Vector2(256, y + 18 + collar_open), Vector2(236, y + 34)]), SHIRT.darkened(0.08))
	draw_colored_polygon(PackedVector2Array([Vector2(298 + collar_open, y - 10), Vector2(256, y + 18 + collar_open), Vector2(276, y + 34)]), SHIRT.darkened(0.08))
	# Tie (loud 90s diagonal stripes); knot drops when Pressure is high.
	var kn := y + 18 + loosen * 26.0
	var tie := PackedVector2Array([Vector2(245, kn), Vector2(267, kn), Vector2(278, kn + 150), Vector2(256, kn + 178), Vector2(234, kn + 150)])
	draw_colored_polygon(tie, TIE_A)
	for i in range(-2, 10):
		var sy := kn + i * 18.0
		var stripe := PackedVector2Array([Vector2(230, sy + 10), Vector2(282, sy - 6), Vector2(282, sy + 2), Vector2(230, sy + 18)])
		var clipped := Geometry2D.intersect_polygons(stripe, tie)
		for poly in clipped:
			draw_colored_polygon(poly, TIE_B)
	draw_colored_polygon(PackedVector2Array([Vector2(244, kn - 6), Vector2(268, kn - 6), Vector2(264, kn + 14), Vector2(248, kn + 14)]), TIE_A.darkened(0.15))
	# Lapels
	draw_polygon(PackedVector2Array([Vector2(196, y - 6), Vector2(256, y + 150), Vector2(214, y + 190), Vector2(150, y + 40)]),
		PackedColorArray([SUIT_SHEEN, SUIT, SUIT_DARK, SUIT]))
	draw_polygon(PackedVector2Array([Vector2(316, y - 6), Vector2(256, y + 150), Vector2(298, y + 190), Vector2(362, y + 40)]),
		PackedColorArray([SUIT_SHEEN, SUIT, SUIT_DARK, SUIT]))
	# Pocket square + lapel pin
	draw_colored_polygon(PackedVector2Array([Vector2(340, y + 118), Vector2(378, y + 112), Vector2(366, y + 96), Vector2(352, y + 100)]), Color(0.1, 0.7, 0.7))
	draw_circle(Vector2(190, y + 60), 5.0, GOLD)
	# Neck
	var neck := PackedVector2Array([Vector2(204, 380), Vector2(308, 380), Vector2(318, y + 4), Vector2(194, y + 4)])
	draw_polygon(neck, PackedColorArray([SKIN_SHADOW, SKIN_SHADOW, SKIN, SKIN]))


func _draw_head() -> void:
	# All coordinates relative to head centre (0,0).
	var flush_col := SKIN_MAKEUP.lerp(Color(0.95, 0.4, 0.35), _flush * 0.6)
	# Ears
	for side in [-1.0, 1.0]:
		var ear := _ellipse_pts(Vector2(side * 96, 8), 16, 30, 18)
		_fan(Vector2(side * 94, 8), ear, SKIN, SKIN_SHADOW)
	# Face: egg shape, slightly jowly.
	var face := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		var rx := 92.0 + 6.0 * pow(maxf(0.0, sin(a)), 3.0)     # jowls
		var ry := 128.0 if sin(a) > 0 else 120.0
		var x := cos(a) * rx * (1.0 - 0.12 * maxf(0.0, sin(a)) * absf(cos(a)))
		face.append(Vector2(x, sin(a) * ry))
	_fan(Vector2(0, -6), face, flush_col, SKIN_SHADOW.lerp(flush_col, 0.35))
	# Stubble/jaw shadow + nasolabial and under-eye ageing lines
	draw_arc(Vector2(0, 30), 70, deg_to_rad(30), deg_to_rad(150), 24, Color(0.45, 0.32, 0.3, 0.18), 18.0)
	for side in [-1.0, 1.0]:
		draw_polyline(PackedVector2Array([Vector2(side * 20, 34), Vector2(side * 36, 56), Vector2(side * 40, 78)]), Color(0.5, 0.28, 0.24, 0.4), 2.5)
		draw_arc(Vector2(side * 38, 0), 16, deg_to_rad(30), deg_to_rad(150), 8, Color(0.5, 0.3, 0.26, 0.3), 1.5)
		# blusher (heavy studio makeup)
		_fan(Vector2(side * 52, 30), _ellipse_pts(Vector2(side * 52, 30), 26, 16, 16), Color(0.95, 0.5, 0.45, 0.35 + _flush * 0.3), Color(0.95, 0.5, 0.45, 0.0))
	# Hair: dated side-parted bouffant, grey at the temples. Pressure displaces a strand.
	var hair := PackedVector2Array([Vector2(-98, -10), Vector2(-104, -60), Vector2(-90, -110), Vector2(-55, -142), Vector2(-10, -152),
		Vector2(40, -150), Vector2(80, -132), Vector2(102, -96), Vector2(104, -40), Vector2(96, -12), Vector2(88, -56),
		Vector2(70, -92), Vector2(30, -106), Vector2(-28, -102), Vector2(-40, -110), Vector2(-62, -92), Vector2(-84, -50)])
	draw_colored_polygon(hair, HAIR)
	draw_colored_polygon(PackedVector2Array([Vector2(-98, -10), Vector2(-104, -60), Vector2(-90, -66), Vector2(-86, -16)]), HAIR_GREY)
	draw_colored_polygon(PackedVector2Array([Vector2(96, -12), Vector2(104, -40), Vector2(94, -60), Vector2(88, -16)]), HAIR_GREY)
	# volume highlight + side parting
	draw_polyline(PackedVector2Array([Vector2(-34, -104), Vector2(-28, -140), Vector2(-18, -150)]), HAIR.darkened(0.4), 3.0)
	draw_polyline(PackedVector2Array([Vector2(-10, -142), Vector2(40, -140), Vector2(76, -120)]), HAIR.lightened(0.25), 4.0)
	if pressure > 0.6:
		draw_polyline(PackedVector2Array([Vector2(-24, -104), Vector2(-14, -80), Vector2(-20, -60)]), HAIR, 4.0)
	# Brows (mood-driven)
	for side in [-1.0, 1.0]:
		var inner := Vector2(side * 16, -38 - _brow * 7 + (8 if _brow < -0.3 else 0) * (-_brow))
		var outer := Vector2(side * 62, -46 - _brow * 4)
		draw_polygon(PackedVector2Array([inner, outer, outer + Vector2(side * 2, 9), inner + Vector2(0, 10)]),
			PackedColorArray([HAIR.darkened(0.3), HAIR, HAIR, HAIR.darkened(0.3)]))
	# Eyes
	var eye_open := 1.0 - _blink
	if activity == "laughing":
		eye_open = 0.25
	elif mood == "rattled":
		eye_open = 1.15
	elif mood == "amused":
		eye_open = 0.75
	var gaze := _look * Vector2(6.0, 4.0)
	for side in [-1.0, 1.0]:
		var ec := Vector2(side * 38, -16)
		if eye_open > 0.12:
			var white := _ellipse_pts(ec, 17, 9.0 * eye_open, 20)
			draw_colored_polygon(white, Color(0.96, 0.94, 0.9))
			draw_circle(ec + gaze, 7.0 * minf(1.0, eye_open + 0.2), Color(0.3, 0.2, 0.12))
			draw_circle(ec + gaze, 3.4 * minf(1.0, eye_open + 0.2), Color(0.04, 0.03, 0.03))
			draw_circle(ec + gaze + Vector2(-2, -2), 1.6, Color(1, 1, 1, 0.9))
			draw_arc(ec, 18, PI + 0.25, TAU - 0.25, 12, Color(0.35, 0.2, 0.17), 2.5)
		else:
			draw_arc(ec + Vector2(0, -2), 17, 0.2, PI - 0.2, 12, Color(0.35, 0.2, 0.17), 3.0)
	# Glasses: big 90s gold frames with a lens glare.
	for side in [-1.0, 1.0]:
		var gc := Vector2(side * 39, -14)
		var lens := Rect2(gc - Vector2(29, 22), Vector2(58, 46))
		draw_rect(lens, Color(0.8, 0.85, 1.0, 0.08), true)
		draw_rect(lens, GOLD, false, 3.0)
		draw_line(lens.position + Vector2(8, 38), lens.position + Vector2(30, 6), Color(1, 1, 1, 0.22), 5.0)
	draw_line(Vector2(-10, -18), Vector2(10, -18), GOLD, 3.0)
	draw_line(Vector2(-68, -24), Vector2(-94, -16), GOLD, 3.0)
	draw_line(Vector2(68, -24), Vector2(94, -16), GOLD, 3.0)
	# Nose
	draw_polygon(PackedVector2Array([Vector2(-4, -10), Vector2(6, -10), Vector2(16, 34), Vector2(-14, 34)]),
		PackedColorArray([SKIN_MAKEUP, SKIN_MAKEUP, SKIN_SHADOW, SKIN_SHADOW]))
	draw_circle(Vector2(-8, 34), 4.0, Color(0.38, 0.2, 0.17))
	draw_circle(Vector2(9, 34), 4.0, Color(0.38, 0.2, 0.17))
	# Mouth
	_draw_mouth(Vector2(0, 66))
	# Sweat sheen (studio lights; increases with Pressure / anger)
	var sweat := clampf(0.25 + pressure * 0.8 + _flush * 0.5, 0.0, 1.0)
	for p in [Vector2(-40, -70), Vector2(22, -76), Vector2(64, -54), Vector2(-70, 8), Vector2(74, 20), Vector2(0, -88)]:
		draw_line(p, p + Vector2(5, -3), Color(1, 1, 1, 0.06 + sweat * 0.22), 2.0 + sweat)
	draw_circle(Vector2(4, 14), 4.0, Color(1, 1, 1, 0.25 + sweat * 0.2))  # nose shine


func _draw_mouth(c: Vector2) -> void:
	var lip := Color(0.62, 0.3, 0.3)
	var dark := Color(0.18, 0.05, 0.06)
	var teeth := Color(0.97, 0.95, 0.88)
	var shape := _mouth
	if shape == "rest":
		match mood:
			"irritated":
				shape = "tight"
			"angry":
				shape = "frown"
			"rattled", "embarrassed":
				shape = "forced"
			"amused":
				shape = "smirk"
			_:
				shape = "stare" if activity == "stare" else "smile"
	if activity == "laughing":
		shape = "laugh"
	match shape:
		"smile", "forced":
			var w := 46.0 if shape == "smile" else 40.0
			var pts := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				pts.append(c + Vector2(lerpf(-w, w, t), -6 + 4.0 * sin(t * PI) - (8.0 if i == 0 or i == 12 else 0.0)))
			for i in range(12, -1, -1):
				var t := float(i) / 12.0
				pts.append(c + Vector2(lerpf(-w, w, t) * 0.92, 6 + 16.0 * sin(t * PI)))
			draw_colored_polygon(pts, dark)
			draw_rect(Rect2(c + Vector2(-w * 0.75, -4), Vector2(w * 1.5, 11)), teeth)
			draw_polyline(pts, lip, 3.0)
		"smirk":
			draw_polyline(PackedVector2Array([c + Vector2(-34, 2), c + Vector2(0, 6), c + Vector2(36, -8)]), lip.darkened(0.2), 5.0)
		"tight":
			draw_line(c + Vector2(-30, 4), c + Vector2(30, 4), lip.darkened(0.3), 4.0)
		"frown":
			draw_polyline(PackedVector2Array([c + Vector2(-32, 12), c + Vector2(0, 2), c + Vector2(32, 12)]), lip.darkened(0.3), 5.0)
		"stare":
			draw_line(c + Vector2(-26, 6), c + Vector2(26, 6), lip.darkened(0.2), 3.0)
		"closed":
			draw_polyline(PackedVector2Array([c + Vector2(-30, 2), c + Vector2(0, 6), c + Vector2(30, 2)]), lip, 4.0)
		"laugh":
			var lp := _ellipse_pts(c + Vector2(0, 10), 40, 28, 24)
			draw_colored_polygon(lp, dark)
			draw_rect(Rect2(c + Vector2(-30, -14), Vector2(60, 10)), teeth)
			draw_polyline(lp + PackedVector2Array([lp[0]]), lip, 3.0)
		_:
			var open: float = {"open": 18.0, "mid": 11.0, "wide": 14.0, "o": 16.0}.get(shape, 10.0)
			var wid: float = {"open": 30.0, "mid": 32.0, "wide": 40.0, "o": 20.0}.get(shape, 30.0)
			var mp := _ellipse_pts(c + Vector2(0, 6), wid, open, 22)
			draw_colored_polygon(mp, dark)
			draw_rect(Rect2(c + Vector2(-wid * 0.7, 6 - open), Vector2(wid * 1.4, minf(7.0, open * 0.6))), teeth)
			draw_polyline(mp + PackedVector2Array([mp[0]]), lip, 3.0)
