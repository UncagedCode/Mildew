class_name CctvView
extends Control
## Backstage CCTV cutaways (CP8): low-grade monochrome security footage of the recurring rooms,
## drawn procedurally from the room's props and its persistent state (door, chair, light, figure).
## Shown for a couple of seconds and never explained. Real-looking plates can replace a room later.

const W := 1440.0
const H := 1080.0

var f_mono: Font
var _p := {}
var _t := 0.0
var _until := -1.0
var _start := 0.0


func _ready() -> void:
	f_mono = load("res://assets/fonts/DejaVuSansMono-Bold.ttf")
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_room(params: Dictionary, seconds: float) -> void:
	_p = params
	_start = _t
	_until = _t + seconds
	queue_redraw()


func is_showing() -> bool:
	return _t < _until


func stop() -> void:
	_until = -1.0
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t < _until + 0.1:
		queue_redraw()


func _ink(v: float, a := 1.0) -> Color:
	return Color(v * 0.86, v * 0.95, v * 0.88, a)


func _draw() -> void:
	if _t >= _until or _p.is_empty():
		return
	var st: Dictionary = _p.get("state", {})
	var light := str(st.get("light", "on"))
	var b := 1.0
	if light == "off":
		b = 0.28
	elif light == "flicker":
		b = 0.35 if int(_t * 13.0) % 4 == 0 else 0.95
	draw_rect(Rect2(0, 0, W, H), _ink(0.05 * b + 0.02))
	# one-point perspective box: back wall, floor, side walls
	var bw := Rect2(430, 250, 580, 420)
	var tl := Vector2(0, 0)
	var tr := Vector2(W, 0)
	var bl := Vector2(0, H)
	var br := Vector2(W, H)
	draw_colored_polygon(PackedVector2Array([bl, br, bw.end, Vector2(bw.position.x, bw.end.y)]), _ink(0.30 * b))   # floor
	draw_colored_polygon(PackedVector2Array([tl, bw.position, Vector2(bw.position.x, bw.end.y), bl]), _ink(0.22 * b))  # left wall
	draw_colored_polygon(PackedVector2Array([tr, br, bw.end, Vector2(bw.end.x, bw.position.y)]), _ink(0.20 * b))     # right wall
	draw_colored_polygon(PackedVector2Array([tl, tr, Vector2(bw.end.x, bw.position.y), bw.position]), _ink(0.12 * b)) # ceiling
	draw_rect(bw, _ink(0.36 * b))
	# ceiling light
	draw_rect(Rect2(W * 0.5 - 90, 120, 180, 16), _ink(0.95 if light != "off" else 0.15))
	if b > 0.5:
		draw_circle(Vector2(W * 0.5, 128), 160, _ink(1.0, 0.05))
	for pr in _p.get("props", []):
		_prop(str(pr), bw, b)
	_door(bw, str(_p.get("door_side", "back")), str(st.get("door", "closed")), b)
	_chair(bw, str(st.get("chair", "centre")), b)
	_figure(bw, str(st.get("figure", "none")), b)
	# video noise, scanlines, rolling bar
	for i in 270:
		draw_rect(Rect2(0, i * 4, W, 1), Color(0, 0, 0, 0.25))
	var roll := fmod((_t - _start) * 180.0, H + 200.0) - 100.0
	draw_rect(Rect2(0, roll, W, 60), Color(1, 1, 1, 0.04))
	var seed := int(_t * 30.0)
	for i in 220:
		var x := float((seed * 7919 + i * 104729) % 1440)
		var y := float((seed * 6271 + i * 15485863) % 1080)
		draw_rect(Rect2(x, y, 3, 2), Color(1, 1, 1, 0.09))
	# overlay text
	draw_string(f_mono, Vector2(60, 80), str(_p.get("cam", "CAM")), HORIZONTAL_ALIGNMENT_LEFT, 400, 40, Color(0.9, 0.95, 0.9, 0.9))
	draw_string(f_mono, Vector2(60, 124), str(_p.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 800, 28, Color(0.9, 0.95, 0.9, 0.8))
	if int((_t - _start) * 2.0) % 2 == 0:
		draw_circle(Vector2(W - 400, 70), 10, Color(0.9, 0.15, 0.1, 0.9))
		draw_string(f_mono, Vector2(W - 380, 82), "REC", HORIZONTAL_ALIGNMENT_LEFT, 100, 28, Color(0.9, 0.95, 0.9, 0.9))
	var secs := int(_start) % 60
	draw_string(f_mono, Vector2(60, H - 50), "31-12-98   23:%02d:%02d" % [47 + int(_start / 60.0) % 12, secs], HORIZONTAL_ALIGNMENT_LEFT, 600, 30, Color(0.9, 0.95, 0.9, 0.85))


func _door(bw: Rect2, side: String, door: String, b: float) -> void:
	var r: Rect2
	match side:
		"left":
			r = Rect2(150, 380, 150, 420)
		"right":
			r = Rect2(W - 300, 380, 150, 420)
		_:
			r = Rect2(bw.get_center().x - 70, bw.end.y - 300, 140, 300)
	draw_rect(r, _ink(0.45 * b))
	match door:
		"open":
			draw_rect(r.grow(-8), Color(0, 0, 0, 1))
		"ajar":
			draw_rect(Rect2(r.position + Vector2(8, 8), Vector2(r.size.x * 0.3, r.size.y - 16)), Color(0, 0, 0, 1))
		_:
			draw_circle(r.position + Vector2(r.size.x - 22, r.size.y * 0.55), 6, _ink(0.8 * b))


func _chair(bw: Rect2, pos: String, b: float) -> void:
	var base := {"centre": Vector2(W * 0.5, 820), "left": Vector2(330, 880), "door": Vector2(W * 0.5 + 40, bw.end.y + 40), "fallen": Vector2(W * 0.55, 860)}
	var c: Vector2 = base.get(pos, base.centre)
	var s := 0.6 if pos == "door" else 1.0
	if pos == "fallen":
		draw_rect(Rect2(c + Vector2(-110, -30) * s, Vector2(220, 40) * s), _ink(0.6 * b))
		draw_rect(Rect2(c + Vector2(80, -110) * s, Vector2(30, 120) * s), _ink(0.55 * b))
		return
	draw_rect(Rect2(c + Vector2(-60, -60) * s, Vector2(120, 22) * s), _ink(0.6 * b))
	draw_rect(Rect2(c + Vector2(-60, -190) * s, Vector2(18, 150) * s), _ink(0.55 * b))
	draw_rect(Rect2(c + Vector2(-56, -40) * s, Vector2(10, 90) * s), _ink(0.5 * b))
	draw_rect(Rect2(c + Vector2(46, -40) * s, Vector2(10, 90) * s), _ink(0.5 * b))


func _figure(bw: Rect2, where: String, b: float) -> void:
	if where == "none":
		return
	var c: Vector2 = {"podium": Vector2(W * 0.62, bw.end.y + 10), "far": Vector2(bw.get_center().x, bw.end.y), "door": Vector2(bw.get_center().x, bw.end.y)}.get(where, Vector2(W * 0.5, bw.end.y))
	var h := 300.0 if where != "far" else 190.0
	var col := Color(0.02, 0.02, 0.02, 0.85)
	draw_circle(c + Vector2(0, -h + h * 0.09), h * 0.09, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.13, -h * 0.82), c + Vector2(h * 0.13, -h * 0.82), c + Vector2(h * 0.1, 0), c + Vector2(-h * 0.1, 0)]), col)


func _prop(kind: String, bw: Rect2, b: float) -> void:
	match kind:
		"sofa":
			draw_rect(Rect2(bw.position.x - 40, bw.end.y - 40, 420, 120), _ink(0.5 * b))
			draw_rect(Rect2(bw.position.x - 40, bw.end.y - 130, 420, 100), _ink(0.42 * b))
		"fridge":
			draw_rect(Rect2(bw.end.x - 170, bw.end.y - 330, 150, 330), _ink(0.7 * b))
			draw_rect(Rect2(bw.end.x - 160, bw.end.y - 220, 8, 60), _ink(0.3 * b))
		"plant":
			draw_rect(Rect2(bw.end.x + 60, bw.end.y + 80, 60, 70), _ink(0.4 * b))
			draw_circle(Vector2(bw.end.x + 90, bw.end.y + 40), 60, _ink(0.33 * b))
		"podiums":
			for i in 4:
				draw_rect(Rect2(bw.position.x + 30 + i * 140, bw.end.y - 140, 100, 140), _ink(0.5 * b))
				draw_string(f_mono, Vector2(bw.position.x + 30 + i * 140, bw.end.y - 90), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 100, 36, _ink(0.2 * b))
		"lamp_stand":
			draw_rect(Rect2(bw.end.x + 120, 300, 12, 560), _ink(0.4 * b))
			draw_rect(Rect2(bw.end.x + 80, 280, 90, 50), _ink(0.6 * b))
		"fire_extinguisher":
			draw_rect(Rect2(260, 720, 50, 120), _ink(0.55 * b))
		"doors":
			for i in 3:
				var x := 60.0 + i * 120.0
				draw_rect(Rect2(x, 340 + i * 40, 70, 380 - i * 70), _ink(0.4 * b))
				draw_rect(Rect2(W - x - 70, 340 + i * 40, 70, 380 - i * 70), _ink(0.38 * b))
		"shelves":
			for i in 5:
				draw_rect(Rect2(bw.position.x + 20, bw.position.y + 40 + i * 70, bw.size.x - 40, 10), _ink(0.55 * b))
				for k in 12:
					draw_rect(Rect2(bw.position.x + 30 + k * 44, bw.position.y + 2 + i * 70, 30, 38), _ink((0.4 + 0.03 * (k % 3)) * b))
		"boxes":
			draw_rect(Rect2(260, 760, 200, 150), _ink(0.5 * b))
			draw_rect(Rect2(300, 640, 150, 120), _ink(0.45 * b))
		"mannequin":
			var c := Vector2(bw.end.x + 180, 900)
			draw_circle(c + Vector2(0, -360), 34, _ink(0.6 * b))
			draw_rect(Rect2(c + Vector2(-45, -320), Vector2(90, 220)), _ink(0.6 * b))
			draw_rect(Rect2(c + Vector2(-8, -100), Vector2(16, 100)), _ink(0.5 * b))
		"tv_trolley":
			draw_rect(Rect2(W * 0.5 + 180, 700, 200, 140), _ink(0.5 * b))
			draw_rect(Rect2(W * 0.5 + 200, 715, 160, 105), _ink(0.15 + 0.1 * sin(_t * 9.0) * b))
			draw_rect(Rect2(W * 0.5 + 190, 840, 180, 60), _ink(0.35 * b))
