class_name AvatarPainter
extends RefCounted
## Draws a contestant avatar into a CanvasItem rect. Mirrors drawAvatar() in controller/app.js
## (same normalised coordinates, same config/avatar_parts.json table).

static var _parts: Dictionary = {}


static func parts() -> Dictionary:
	if _parts.is_empty():
		_parts = MildewConfig._read_json("res://config/avatar_parts.json")
	return _parts


static func _pick(arr: Array, i) -> Variant:
	return arr[clampi(int(i), 0, arr.size() - 1)]


static func draw(ci: CanvasItem, rect: Rect2, a: Dictionary, crt_bg: bool = true) -> void:
	var P := parts()
	var W := rect.size.x
	var H := rect.size.y
	var o := rect.position
	var X := func(v: float) -> float: return o.x + v * W
	var Y := func(v: float) -> float: return o.y + v * H
	var skin := Color(str(_pick(P.skin, a.get("skin", 0))))
	var hair_c := Color(str(_pick(P.hair_colour, a.get("hair_colour", 0))[1]))
	var outfit: Array = _pick(P.outfit, a.get("outfit", 0))
	if crt_bg:
		ci.draw_rect(rect, Color("#16204a"))
		ci.draw_rect(Rect2(o, Vector2(W, H * 0.5)), Color("#23305e"))
		for yy in range(0, int(H), 4):
			ci.draw_line(Vector2(o.x, o.y + yy), Vector2(o.x + W, o.y + yy), Color(1, 1, 1, 0.04))
	# shoulders
	var sh := PackedVector2Array()
	sh.append(Vector2(X.call(0.08), Y.call(1.0)))
	sh.append(Vector2(X.call(0.16), Y.call(0.78)))
	for i in 9:
		var t := float(i) / 8.0
		sh.append(Vector2(X.call(lerpf(0.16, 0.84, t)), Y.call(0.78 - 0.1 * sin(t * PI))))
	sh.append(Vector2(X.call(0.92), Y.call(1.0)))
	ci.draw_colored_polygon(sh, Color(str(outfit[1])))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(X.call(0.40), Y.call(0.74)), Vector2(X.call(0.5), Y.call(0.9)), Vector2(X.call(0.6), Y.call(0.74))]), Color(str(outfit[2])))
	if int(a.get("outfit", 0)) == 7:
		for i in 6:
			ci.draw_rect(Rect2(X.call(0.16 + i * 0.13), Y.call(0.8), W * 0.05, H * 0.2), Color(0, 0, 0, 0.18))
	# neck, head, ears
	ci.draw_rect(Rect2(X.call(0.44), Y.call(0.6), W * 0.12, H * 0.14), skin)
	_ellipse(ci, Vector2(X.call(0.5), Y.call(0.45)), W * 0.17, H * 0.21, skin)
	_ellipse(ci, Vector2(X.call(0.33), Y.call(0.47)), W * 0.03, H * 0.05, skin)
	_ellipse(ci, Vector2(X.call(0.67), Y.call(0.47)), W * 0.03, H * 0.05, skin)
	# hair
	match int(a.get("hair", 0)):
		0:
			_half_ellipse(ci, Vector2(X.call(0.5), Y.call(0.30)), W * 0.18, H * 0.10, hair_c)
			_ellipse(ci, Vector2(X.call(0.42), Y.call(0.27)), W * 0.12, H * 0.06, hair_c)
		1:
			_ellipse(ci, Vector2(X.call(0.38), Y.call(0.33)), W * 0.10, H * 0.12, hair_c)
			_ellipse(ci, Vector2(X.call(0.62), Y.call(0.33)), W * 0.10, H * 0.12, hair_c)
		2:
			_half_ellipse(ci, Vector2(X.call(0.5), Y.call(0.30)), W * 0.18, H * 0.10, hair_c)
			ci.draw_rect(Rect2(X.call(0.31), Y.call(0.30), W * 0.06, H * 0.30), hair_c)
			ci.draw_rect(Rect2(X.call(0.63), Y.call(0.30), W * 0.06, H * 0.30), hair_c)
		3:
			_ellipse(ci, Vector2(X.call(0.33), Y.call(0.38)), W * 0.04, H * 0.07, hair_c)
			_ellipse(ci, Vector2(X.call(0.67), Y.call(0.38)), W * 0.04, H * 0.07, hair_c)
		4:
			for i in 9:
				var ang := PI + i * PI / 8.0
				ci.draw_circle(Vector2(X.call(0.5 + 0.17 * cos(ang)), Y.call(0.33 + 0.12 * sin(ang))), W * 0.06, hair_c)
		_:
			_half_ellipse(ci, Vector2(X.call(0.5), Y.call(0.32)), W * 0.20, H * 0.13, hair_c)
			ci.draw_rect(Rect2(X.call(0.30), Y.call(0.32), W * 0.07, H * 0.24), hair_c)
			ci.draw_rect(Rect2(X.call(0.63), Y.call(0.32), W * 0.07, H * 0.24), hair_c)
	# face
	ci.draw_circle(Vector2(X.call(0.44), Y.call(0.45)), W * 0.016, Color("#1a1410"))
	ci.draw_circle(Vector2(X.call(0.56), Y.call(0.45)), W * 0.016, Color("#1a1410"))
	ci.draw_arc(Vector2(X.call(0.5), Y.call(0.52)), W * 0.06, 0.15 * PI, 0.85 * PI, 10, Color("#5a2a22"), maxf(1.0, W * 0.012))
	# glasses
	var gl := int(a.get("glasses", 0))
	if gl == 1 or gl == 2:
		var frame := Color("#d8b44a") if gl == 1 else Color("#222222")
		var fill := Color(0.24, 0.12, 0.31, 0.55) if gl == 2 else Color(1, 1, 1, 0.08)
		for cx in [0.43, 0.57]:
			var r := Rect2(X.call(cx - 0.055), Y.call(0.415), W * 0.11, H * 0.075)
			ci.draw_rect(r, fill)
			ci.draw_rect(r, frame, false, maxf(1.0, W * 0.014))
		ci.draw_line(Vector2(X.call(0.485), Y.call(0.45)), Vector2(X.call(0.515), Y.call(0.45)), frame, maxf(1.0, W * 0.014))
	# accessory
	match int(a.get("accessory", 0)):
		1:
			var bow := Color("#c21f3a")
			ci.draw_colored_polygon(PackedVector2Array([Vector2(X.call(0.5), Y.call(0.76)), Vector2(X.call(0.42), Y.call(0.72)), Vector2(X.call(0.42), Y.call(0.80))]), bow)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(X.call(0.5), Y.call(0.76)), Vector2(X.call(0.58), Y.call(0.72)), Vector2(X.call(0.58), Y.call(0.80))]), bow)
		2:
			ci.draw_circle(Vector2(X.call(0.33), Y.call(0.53)), W * 0.018, Color("#e8c547"))
		3:
			_ellipse(ci, Vector2(X.call(0.5), Y.call(0.505)), W * 0.07, H * 0.018, hair_c)
		4:
			ci.draw_rect(Rect2(X.call(0.62), Y.call(0.80), W * 0.05, H * 0.07), Color("#2a5bd7"))
			ci.draw_circle(Vector2(X.call(0.645), Y.call(0.90)), W * 0.035, Color("#e8c547"))
		5:
			_ellipse(ci, Vector2(X.call(0.5), Y.call(0.235)), W * 0.06, H * 0.025, Color("#ff4fa3"))


static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)


static func _half_ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)
