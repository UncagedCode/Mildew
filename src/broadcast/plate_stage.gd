class_name PlateStage
extends Control
## Photographic studio plates (D026). Each camera angle is a still photograph of the studio; live
## elements are composited on top so the programme looks filmed rather than rendered:
##   plate -> podium screens (perspective-mapped) -> Graham's cut-out at his mark -> foreground
##   occluder (desk edge etc.) -> additive lamp/rig glows; all under a slow camera drift.
## While a plate is on air the programme viewport's 3D is switched off entirely (cheap on a TV).
## Plates and hotspots are data (config/studio_plates.json); real photographs replace the stand-ins
## without code changes. Cameras without a plate (titles, ident) fall back to the 3D studio.

const MAP_PATH := "res://config/studio_plates.json"
const W := 1440.0
const H := 1080.0
const GRAHAM_FRAME_M := 1.1729        # cut-out frame height in metres (1086 px * 0.00108)

var studio                             # StudioSet
var graham                             # GrahamPresenter
var viewport: SubViewport
var plates := {}
var cam_map := {}
var active := ""                       # plate id on air ("" = 3D)
var show_hotspots := false             # dev calibration overlay
var _tex := {}
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _drift_from := Vector3(0, 0, 1)
var _drift_to := Vector3(0, 0, 1)
var _drift_t := 0.0
var _drift_len := 5.0
var _fg: Control
var _glow: Control
var _soft: Texture2D                   # radial falloff for glows (no visible rings)


func _ready() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	load_map(MAP_PATH)
	_fg = Control.new()
	_fg.size = size
	_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fg.draw.connect(_draw_foreground)
	add_child(_fg)
	_glow = Control.new()
	_glow.size = size
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	_soft = gt
	if studio != null and not studio.cut_made.is_connected(_on_cut):
		studio.cut_made.connect(_on_cut)
		_on_cut(str(studio.current_cam))


func load_map(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	plates = d.get("plates", {})
	cam_map = d.get("cameras", {})
	for id in plates:
		var p := str(plates[id].get("image", ""))
		if p != "" and ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p)


func plate_for_camera(cam: String) -> String:
	var id := str(cam_map.get(cam, ""))
	return id if plates.has(id) and _texture(str(plates[id].get("image", ""))) != null else ""


func _on_cut(cam: String) -> void:
	active = plate_for_camera(cam)
	visible = active != ""
	if viewport != null:
		viewport.disable_3d = active != ""
	_drift_from = Vector3(0, 0, 1)
	_drift_to = _drift_from
	_drift_t = 0.0
	_new_drift()
	queue_redraw()


func _texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex.has(path):
		return _tex[path]
	if not ResourceLoader.exists(path):
		return null
	var st := ResourceLoader.load_threaded_get_status(path)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return null
	var t: Texture2D = ResourceLoader.load_threaded_get(path) if st == ResourceLoader.THREAD_LOAD_LOADED else load(path)
	_tex[path] = t
	return t


# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if active == "":
		if plate_for_camera(str(studio.current_cam) if studio else "") != "":
			_on_cut(str(studio.current_cam))   # texture finished loading after the cut
		return
	_drift_t += delta
	if _drift_t >= _drift_len:
		_drift_from = _drift_to
		_new_drift()
	queue_redraw()
	_fg.queue_redraw()
	_glow.queue_redraw()


func _new_drift() -> void:
	var spec: Dictionary = plates.get(active, {}).get("drift", {})
	var amp := float(spec.get("px", 3.0))
	var zoom := float(spec.get("zoom", 0.006))
	_drift_to = Vector3(_rng.randf_range(-amp, amp), _rng.randf_range(-amp, amp) * 0.6, 1.0 + zoom + _rng.randf_range(0.0, zoom))
	_drift_t = 0.0
	_drift_len = _rng.randf_range(4.0, 8.0)


func _drift_now() -> Vector3:
	var k := clampf(_drift_t / maxf(0.01, _drift_len), 0.0, 1.0)
	return _drift_from.lerp(_drift_to, k * k * (3.0 - 2.0 * k))


func _apply_drift(ci: CanvasItem) -> void:
	var m := _drift_now()
	var c := Vector2(W, H) * 0.5
	ci.draw_set_transform(c + Vector2(m.x, m.y) - c * m.z, 0.0, Vector2(m.z, m.z))


static func _pt(p) -> Vector2:
	return Vector2(float(p[0]) * W, float(p[1]) * H)


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if active == "":
		return
	var spec: Dictionary = plates[active]
	_apply_drift(self)
	var tex := _texture(str(spec.get("image", "")))
	if tex:
		draw_texture_rect(tex, Rect2(0, 0, W, H), false)
	_draw_screens(spec)
	_draw_graham(spec)


func _player_for_podium(n: int) -> Dictionary:
	if studio == null:
		return {}
	for pid in studio.podiums:
		var e: Dictionary = studio.podiums[pid]
		if int(e.screen.info.get("number", 0)) == n:
			return e
	return {}


func _draw_screens(spec: Dictionary) -> void:
	for s in spec.get("screens", []):
		var n := int(s.get("podium", 0))
		var e: Dictionary = {}
		if n == 0 and studio != null and studio.podiums.has(str(studio.framed_pid)):
			e = studio.podiums[str(studio.framed_pid)]       # close-up plate shows whoever is framed
		elif n > 0:
			e = _player_for_podium(n)
		if e.is_empty():
			continue                                         # unused podium: the plate's screen stays off
		var q: Array = s.quad
		var pts := PackedVector2Array([_pt(q[0]), _pt(q[1]), _pt(q[2]), _pt(q[3])])
		var vp: SubViewport = (e.screen as Control).get_viewport() as SubViewport
		if vp == null:
			continue
		var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		var tint := Color(0.92, 0.95, 0.92)
		draw_polygon(pts, PackedColorArray([tint, tint, tint, tint]), uvs, vp.get_texture())
		# glass: darker corners + a soft reflection band, so it sits in the photograph
		var shade := Color(0, 0, 0, 0.28)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), shade, 3.0)
		var a := pts[0].lerp(pts[3], 0.08)
		var b := pts[1].lerp(pts[2], 0.08)
		var c := pts[1].lerp(pts[2], 0.32)
		var d := pts[0].lerp(pts[3], 0.18)
		draw_polygon(PackedVector2Array([a, b, c, d]), PackedColorArray([Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)]))


func _draw_graham(spec: Dictionary) -> void:
	var g: Dictionary = spec.get("graham", {})
	if g.is_empty() or graham == null or graham.sprite == null:
		return
	var tex: Texture2D = graham.sprite.texture
	if tex == null:
		return
	var h_px := float(g.get("height", 0.8)) * H
	var w_px := h_px * float(tex.get_width()) / float(tex.get_height())
	var anchor := _pt(g.get("anchor", [0.5, 1.0]))
	var breath: float = graham.sprite.scale.y
	var sway_m: float = graham.sprite.position.x - (StudioSet.GRAHAM_POS.x)
	var sway_px := sway_m / GRAHAM_FRAME_M * h_px
	var hh := h_px * breath
	var rect := Rect2(anchor.x - w_px * 0.5 + sway_px, anchor.y - hh, w_px, hh)
	var shade: Color = Color(g.get("tint", "#ffffff"))
	draw_texture_rect(tex, rect, false, shade)


func _draw_foreground() -> void:
	if active == "":
		return
	var spec: Dictionary = plates[active]
	_apply_drift(_fg)
	var occ := _texture(str(spec.get("foreground", "")))
	if occ:
		_fg.draw_texture_rect(occ, Rect2(0, 0, W, H), false)
	if show_hotspots:
		_draw_hotspots(spec)


func _draw_glow() -> void:
	if active == "":
		return
	var spec: Dictionary = plates[active]
	_apply_drift(_glow)
	# Answer lamps on podiums that have locked in.
	for l in spec.get("lamps", []):
		var e := _player_for_podium(int(l.get("podium", 0)))
		if e.is_empty() or float(e.screen.lit) < 0.5:
			continue
		var q: Array = l.quad
		var pts := PackedVector2Array([_pt(q[0]), _pt(q[1]), _pt(q[2]), _pt(q[3])])
		var col := Color(1.0, 0.75, 0.3, 0.55)
		_glow.draw_polygon(pts, PackedColorArray([col, col, col, col]))
		var cen := (pts[0] + pts[2]) * 0.5
		var r := pts[0].distance_to(pts[1]) * 0.8
		_glow.draw_texture_rect(_soft, Rect2(cen - Vector2(r, r * 0.6), Vector2(r * 2, r * 1.2)), false, Color(1.0, 0.75, 0.35, 0.35))
	# Rig lights: a living bloom with the odd tired flicker.
	for i in spec.get("lights", []).size():
		var li: Dictionary = spec.lights[i]
		var p := _pt(li.at)
		var r := float(li.get("r", 0.02)) * W
		var col := Color(li.get("colour", "#ffffff"))
		var flick := 0.85 + 0.15 * sin(_t * 1.7 + i * 2.1)
		if fmod(_t + i * 3.7, 23.0) < 0.12:
			flick *= 0.35
		var rr := r * 3.2
		_glow.draw_texture_rect(_soft, Rect2(p - Vector2(rr, rr), Vector2(rr * 2, rr * 2)), false, Color(col, 0.22 * flick))


func _draw_hotspots(spec: Dictionary) -> void:
	var g: Dictionary = spec.get("graham", {})
	if not g.is_empty():
		var a := _pt(g.anchor)
		var h := float(g.height) * H
		_fg.draw_rect(Rect2(a.x - h * 0.375, a.y - h, h * 0.75, h), Color(1, 1, 0, 0.8), false, 2.0)
		_fg.draw_circle(a, 6, Color(1, 1, 0))
	for s in spec.get("screens", []):
		var q: Array = s.quad
		_fg.draw_polyline(PackedVector2Array([_pt(q[0]), _pt(q[1]), _pt(q[2]), _pt(q[3]), _pt(q[0])]), Color(0, 1, 1), 2.0)
	for l in spec.get("lamps", []):
		var q: Array = l.quad
		_fg.draw_polyline(PackedVector2Array([_pt(q[0]), _pt(q[1]), _pt(q[2]), _pt(q[3]), _pt(q[0])]), Color(1, 0.5, 0), 2.0)
	for li in spec.get("lights", []):
		_fg.draw_arc(_pt(li.at), float(li.get("r", 0.02)) * W, 0, TAU, 24, Color(1, 0, 1), 2.0)
