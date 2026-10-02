class_name StudioSet
extends Node3D
## PROVISIONAL Mildew studio (docs/08): cheap 1998 regional-TV set built procedurally.
## Owns the studio cameras and implements live camera grammar:
##   cam1 Graham frontal medium · cam2 studio wide · cam3 contestant/podium angle ·
##   cam4 utility/roaming · podium close-ups · titles/ident rigs.
## Normal cuts carry small live-TV imperfections (late cuts, operator drift) so that
## deliberately wrong cameras (later incidents) read as wrong.

signal cut_made(cam: String)

const GRAHAM_POS := Vector3(-4.2, 0.0, 0.4)
const PODIUM_AREA_X := Vector2(-0.6, 7.2)
const PODIUM_Z := 0.9

var cameras := {}
var current_cam := ""
var graham                         # GrahamPresenter (assigned by ProgrammeView)
var graham_sprite: Sprite3D        # Graham's photographic cut-out, standing at his mark (D022)
var podiums := {}               # pid -> {node, screen: PodiumScreen, lamp: MeshInstance3D, target: Vector3}
var _drift := {}                # cam -> base transform (handheld cams)
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _pending_cut := ""
var _pending_at := 0.0
var _titles: Node3D
var _titles_t := -1.0
var _titles_len := 9.0
var _title_logo: Node3D
var _title_bits: Array = []
var _ident: Node3D
var _ident_logo: Node3D
var _logo_mat: ShaderMaterial
var _font_display: Font
var _font_serif: Font


func build() -> void:
	_rng.randomize()
	_font_display = load("res://assets/fonts/InterDisplay-BlackItalic.otf")
	_font_serif = load("res://assets/fonts/LiberationSerif-BoldItalic.ttf")
	_logo_mat = ShaderMaterial.new()
	_logo_mat.shader = load("res://assets/shaders/chrome.gdshader")
	_build_environment()
	_build_set()
	_build_corridor()
	_build_graham()
	_build_cameras()
	_build_titles_rig()
	_build_ident_rig()


# ---------------------------------------------------------------------------
# Materials / helpers
# ---------------------------------------------------------------------------

func _mat(c: Color, rough: float = 0.6, metal: float = 0.0, emissive: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _text3d(text: String, font: Font, font_size: int, depth: float, pixel: float, mat: Material, parent: Node) -> MeshInstance3D:
	var tm := TextMesh.new()
	tm.text = text
	tm.font = font
	tm.font_size = font_size
	tm.depth = depth
	tm.pixel_size = pixel
	tm.curve_step = 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	# Warm, soft, slightly flat 1990s studio light (reference): a big frontal key, gentle fill,
	# coloured PAR spill on the set, a touch of haze. Graham's cut-out is unshaded (lit in the photo).
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.58, 0.55)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.02
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.78)
	key.light_energy = 0.85
	key.rotation_degrees = Vector3(-30, 8, 0)
	add_child(key)
	for spec in [[Vector3(-7, 5, 4), Color(1.0, 0.45, 0.7), 1.2], [Vector3(8, 5, 4), Color(0.4, 0.7, 1.0), 1.2],
			[Vector3(2, 6, -2), Color(0.85, 0.75, 1.0), 1.4], [GRAHAM_POS + Vector3(0, 3.2, 2.5), Color(1.0, 0.88, 0.72), 1.5]]:
		var l := OmniLight3D.new()
		l.position = spec[0]
		l.light_color = spec[1]
		l.light_energy = spec[2]
		l.omni_range = 14.0
		add_child(l)


func _tex_mat(path: String, uv: Vector2 = Vector2.ONE, rough: float = 0.85, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var m := _mat(tint, rough)
	m.albedo_texture = load(path)
	m.uv1_scale = Vector3(uv.x, uv.y, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


## Brushed "chrome" trim. True metal reads black without reflections to pick up, so this is a bright
## polished grey with a hot specular and a faint self-lit sheen, which is how studio trim reads on tape.
func _chrome() -> StandardMaterial3D:
	var m := _mat(Color(0.8, 0.81, 0.84), 0.22, 0.25)
	m.metallic_specular = 0.9
	m.emission_enabled = true
	m.emission = Color(0.55, 0.56, 0.6)
	m.emission_energy_multiplier = 0.18
	return m


func _quad(size: Vector2, pos: Vector3, rot_y: float, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi


## Studio C after the reference video (references/graham): sponge-painted sage flats on a painted
## blue wall, chrome-banded MILDEW signs, coloured PAR cans, navy ring carpet. Textures are owned
## (tools/art/gen_studio_ref.py). No broadcaster branding anywhere.
func _build_set() -> void:
	var studio := "res://assets/textures/studio/"
	var carpet := _tex_mat(studio + "carpet_navy.png", Vector2(15, 10), 0.95, Color(0.82, 0.82, 0.86))
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 20)
	floor_mesh.mesh = plane
	floor_mesh.material_override = carpet
	floor_mesh.position = Vector3(1, 0, 0)
	add_child(floor_mesh)
	var green := _tex_mat(studio + "sponge_green.png", Vector2(1, 2))
	var blue := _tex_mat(studio + "wall_blue.png", Vector2(3, 1), 0.9, Color(0.62, 0.66, 0.8))
	var cream := _tex_mat(studio + "cream.png", Vector2(1, 3))
	var chrome := _chrome()
	# Contestant riser (low, carpeted edge with a chrome nosing)
	_box(Vector3(12.5, 0.24, 4.5), Vector3(3.4, 0.12, -0.2), _mat(Color(0.12, 0.2, 0.42), 0.7))
	_box(Vector3(12.5, 0.05, 0.07), Vector3(3.4, 0.25, 2.05), chrome)
	# Painted blue back wall across the whole studio
	_quad(Vector2(30, 8), Vector3(1, 4, -7.2), 0.0, blue)
	# Sage sponge-painted flats with chrome edges, gently curving round the contestant area
	var green_dark := _tex_mat(studio + "sponge_green.png", Vector2(1, 2), 0.85, Color(0.78, 0.86, 0.78))
	for i in 7:
		var x := -1.4 + i * 1.95
		var z := -4.4 - 0.18 * pow((x - 3.4) / 3.0, 2.0)
		var rot := -atan((x - 3.4) / 14.0)
		var flat := _box(Vector3(1.96, 4.0, 0.12), Vector3(x, 2.0, z), green if i % 2 == 0 else green_dark)
		flat.rotation.y = rot
		_box(Vector3(0.05, 4.0, 0.16), Vector3(x - 0.98, 2.0, z + 0.02), chrome).rotation.y = rot
		_box(Vector3(1.98, 0.08, 0.18), Vector3(x, 4.02, z + 0.02), chrome).rotation.y = rot
	# Big MILDEW sign over the contestants (same artwork as Graham's)
	_sign(Vector3(3.4, 5.0, -4.1), Vector2(5.4, 2.0))
	# Lighting trusses with PAR cans and coloured lenses (they appear at the top of Graham's shot too)
	var truss := _mat(Color(0.12, 0.12, 0.13), 0.45, 0.7)
	_box(Vector3(18, 0.18, 0.18), Vector3(2.0, 6.6, 1.2), truss)
	for i in 10:
		_par_can(Vector3(-6.0 + i * 1.75, 6.3, 1.2), PAR_COLOURS[i % PAR_COLOURS.size()], Vector3(-35, 0, 0))
	_build_presenter_area(green, blue, cream, chrome)


const PAR_COLOURS := [Color(1.0, 0.85, 0.25), Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.55), Color(1.0, 0.97, 0.9),
	Color(0.15, 0.15, 0.15), Color(1.0, 0.3, 0.55), Color(0.25, 0.55, 1.0), Color(0.35, 1.0, 0.45)]


## A sign: sponge-painted face with the lettering baked in, chrome bands top and bottom. With
## wrap > 0 the outer 15% each side folds forward (the reference sign wraps round the presenter).
func _sign(centre: Vector3, size: Vector2, rot_y: float = 0.0, wrap: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = centre
	root.rotation.y = rot_y
	add_child(root)
	var chrome := _chrome()
	var parts := [[0.0, 1.0]] if wrap <= 0.0 else [[0.0, 0.15], [0.15, 0.85], [0.85, 1.0]]
	for part in parts:
		var u0: float = part[0]
		var u1: float = part[1]
		var w := size.x * (u1 - u0)
		var seg := Node3D.new()
		root.add_child(seg)
		if wrap > 0.0 and u0 == 0.0:
			seg.position = Vector3(-size.x * 0.35, 0, 0)
			seg.rotation.y = wrap
			seg.position += Vector3(-w * 0.5 * cos(wrap), 0, w * 0.5 * sin(wrap))
		elif wrap > 0.0 and u1 == 1.0:
			seg.position = Vector3(size.x * 0.35, 0, 0)
			seg.rotation.y = -wrap
			seg.position += Vector3(w * 0.5 * cos(wrap), 0, w * 0.5 * sin(wrap))
		else:
			seg.position = Vector3((u0 + u1 - 1.0) * 0.5 * size.x, 0, 0)
		var face := _tex_mat("res://assets/textures/studio/sign_face.png", Vector2(u1 - u0, 1.0), 0.75)
		face.uv1_offset = Vector3(u0, 0, 0)
		_box(Vector3(w, size.y, 0.14), Vector3(0, 0, -0.08), _mat(Color(0.3, 0.38, 0.27), 0.8), seg)
		_quad(Vector2(w, size.y), Vector3.ZERO, 0.0, face, seg)
		for dy in [size.y * 0.5, -size.y * 0.5]:
			_box(Vector3(w + 0.02, size.y * 0.055, 0.2), Vector3(0, dy, 0.0), chrome, seg)
	return root


## A PAR can on a yoke: black body, glowing coloured lens, a soft cone of coloured light.
func _par_can(pos: Vector3, colour: Color, rot_deg: Vector3, scale_: float = 1.0) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = rot_deg
	root.scale = Vector3.ONE * scale_
	add_child(root)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.13
	cyl.bottom_radius = 0.15
	cyl.height = 0.36
	cyl.radial_segments = 20
	body.mesh = cyl
	body.material_override = _mat(Color(0.06, 0.06, 0.07), 0.4, 0.6)
	body.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(body)
	var lit := colour.v > 0.3
	var lens := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.12
	disc.bottom_radius = 0.12
	disc.height = 0.02
	disc.radial_segments = 20
	lens.mesh = disc
	lens.material_override = _mat(colour, 0.2, 0.0, 1.7 if lit else 0.0)
	lens.rotation_degrees = Vector3(90, 0, 0)
	lens.position = Vector3(0, 0, 0.19)
	root.add_child(lens)
	if lit:
		var l := SpotLight3D.new()
		l.light_color = colour
		l.light_energy = 1.2
		l.spot_range = 9.0
		l.spot_angle = 22.0
		l.position = Vector3(0, 0, 0.25)
		root.add_child(l)


## Graham's corner, built to the reference composition (cam1 medium shot): a sign 3.3 m behind
## him, a row of PAR cans just inside the top of frame, angled green flats on the left, a cream
## pillar with a red-framed monitor on the right, a chrome-rimmed round table at his waist and a
## green box step. His low desk (top 0.72 m) hides the cut-out's crop line in wide shots.
func _build_presenter_area(green: Material, blue: Material, cream: Material, chrome: Material) -> void:
	var g := GRAHAM_POS
	_quad(Vector2(9, 6), g + Vector3(0, 3, -4.7), 0.0, blue)                           # painted wall behind
	_sign(g + Vector3(0, 1.55, -3.3), Vector2(2.5, 1.15), 0.0, deg_to_rad(32))
	_box(Vector3(2.0, 0.96, 0.2), g + Vector3(0, 0.48, -3.42), green)                   # flat under the sign
	_box(Vector3(5.2, 1.2, 0.1), g + Vector3(0, 3.45, -4.75), _mat(Color(0.015, 0.015, 0.025), 1.0))   # black lighting pelmet
	_box(Vector3(5.2, 0.04, 0.14), g + Vector3(0, 2.86, -4.72), _chrome())
	# lamp bar just inside the top of the frame
	_box(Vector3(4.6, 0.06, 0.06), g + Vector3(0, 2.86, -4.6), _mat(Color(0.1, 0.1, 0.11), 0.4, 0.7))
	var sign_spot := SpotLight3D.new()
	sign_spot.light_color = Color(1.0, 0.9, 0.75)
	sign_spot.light_energy = 2.2
	sign_spot.spot_range = 8.0
	sign_spot.spot_angle = 28.0
	sign_spot.position = g + Vector3(0, 3.4, 0.5)
	add_child(sign_spot)
	sign_spot.look_at(g + Vector3(0, 1.5, -3.3), Vector3.UP)
	var cols := [Color(1.0, 0.85, 0.25), Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.55), Color(1.0, 0.97, 0.9),
		Color(0.08, 0.08, 0.08), Color(1.0, 0.3, 0.55), Color(0.25, 0.55, 1.0), Color(0.35, 1.0, 0.45)]
	for i in cols.size():
		_par_can(g + Vector3(-1.75 + i * 0.5, 2.7, -4.6), cols[i], Vector3(-10, 0, 0), 0.62)
	# angled green flats, left
	var f1 := _box(Vector3(1.3, 3.2, 0.1), g + Vector3(-2.2, 1.6, -3.0), green)
	f1.rotation.y = deg_to_rad(40)
	var f2 := _box(Vector3(0.9, 2.6, 0.1), g + Vector3(-1.6, 1.3, -3.9), green)
	f2.rotation.y = deg_to_rad(-10)
	# cream pillar with a red-framed CRT monitor, right
	_box(Vector3(0.9, 3.4, 0.6), g + Vector3(1.45, 1.7, -2.7), cream)
	_box(Vector3(0.6, 0.5, 0.08), g + Vector3(1.3, 1.72, -2.37), _mat(Color(0.7, 0.12, 0.1), 0.35))
	_box(Vector3(0.48, 0.38, 0.06), g + Vector3(1.3, 1.72, -2.33), _mat(Color(0.2, 0.22, 0.23), 0.15, 0.0, 0.25))
	_box(Vector3(0.05, 3.4, 0.62), g + Vector3(0.98, 1.7, -2.7), chrome)
	# round table behind him with a chrome rim, and a green box step
	var tab := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.85
	tc.bottom_radius = 0.85
	tc.height = 1.0
	tc.radial_segments = 40
	tab.mesh = tc
	tab.material_override = green
	tab.position = g + Vector3(0, 0.5, -1.25)
	add_child(tab)
	var rim := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.84
	tor.outer_radius = 0.885
	tor.rings = 40
	rim.mesh = tor
	rim.material_override = chrome
	rim.position = g + Vector3(0, 1.01, -1.25)
	add_child(rim)
	_box(Vector3(0.8, 0.42, 0.6), g + Vector3(-1.2, 0.21, -1.55), _mat(Color(0.12, 0.32, 0.22), 0.7))
	# Graham's low desk: dark edge only just visible at the bottom of Camera 1, like the reference.
	_box(Vector3(1.7, 0.7, 0.6), g + Vector3(0, 0.35, 0.45), _mat(Color(0.16, 0.17, 0.2), 0.5))
	_box(Vector3(1.78, 0.04, 0.68), g + Vector3(0, 0.72, 0.45), chrome)
	var m := _text3d("M", _font_display, 120, 0.06, 0.004, _logo_mat, self)
	m.position = g + Vector3(0, 0.38, 0.76)


## Service corridor behind Studio C (recurring backstage location; docs/02 "Recurring rooms").
## Breeze block, scuffed lino, one fluorescent tube that flickers, a fire door, and a dark open
## doorway at the far end. Lives off-set (x -40) so only its own cameras ever see it.
const CORRIDOR := Vector3(-40, 0, 0)
var _tube_mat: StandardMaterial3D
var _tube_light: OmniLight3D


func _build_corridor() -> void:
	var o := CORRIDOR
	var block := _mat(Color(0.62, 0.62, 0.58), 0.95)
	var lino := _mat(Color(0.33, 0.35, 0.3), 0.6)
	var paint := _mat(Color(0.45, 0.5, 0.42), 0.8)   # institutional green dado
	_box(Vector3(2.4, 0.05, 14), o + Vector3(0, 0, -6), lino)
	_box(Vector3(2.4, 0.05, 14), o + Vector3(0, 2.7, -6), _mat(Color(0.7, 0.7, 0.66), 0.9))
	for side in [-1, 1]:
		_box(Vector3(0.2, 2.7, 14), o + Vector3(side * 1.2, 1.35, -6), block)
		_box(Vector3(0.22, 1.0, 14), o + Vector3(side * 1.19, 0.5, -6), paint)
		for i in 14:   # mortar lines
			_box(Vector3(0.21, 0.015, 14), o + Vector3(side * 1.19, 1.05 + i * 0.12, -6), _mat(Color(0.5, 0.5, 0.47), 1.0))
	# far wall with a dark open doorway
	_box(Vector3(2.4, 2.7, 0.2), o + Vector3(-0.75, 1.35, -13), block)
	_box(Vector3(2.4, 2.7, 0.2), o + Vector3(1.75, 1.35, -13), block)
	_box(Vector3(0.9, 0.6, 0.2), o + Vector3(0.5, 2.4, -13), block)
	_box(Vector3(0.9, 2.1, 0.1), o + Vector3(0.5, 1.05, -13.6), _mat(Color(0.0, 0.0, 0.0), 1.0))
	_box(Vector3(0.06, 2.1, 0.25), o + Vector3(0.03, 1.05, -13), _mat(Color(0.3, 0.3, 0.3), 0.6, 0.5))
	# fire door (closed) on the left, with push bar and sign
	_box(Vector3(0.05, 2.0, 1.0), o + Vector3(-1.08, 1.0, -5), _mat(Color(0.55, 0.2, 0.15), 0.6))
	_box(Vector3(0.06, 0.06, 0.8), o + Vector3(-1.04, 1.0, -5), _mat(Color(0.75, 0.75, 0.75), 0.3, 0.8))
	# fluorescent tube
	_tube_mat = _mat(Color(0.9, 1.0, 0.95), 0.3, 0.0, 2.5)
	_box(Vector3(0.1, 0.05, 1.3), o + Vector3(0, 2.62, -4), _tube_mat)
	_tube_light = OmniLight3D.new()
	_tube_light.light_color = Color(0.85, 1.0, 0.9)
	_tube_light.light_energy = 1.6
	_tube_light.omni_range = 9.0
	_tube_light.position = o + Vector3(0, 2.4, -4)
	add_child(_tube_light)
	var far := OmniLight3D.new()
	far.light_color = Color(0.8, 0.85, 0.8)
	far.light_energy = 0.35
	far.omni_range = 6.0
	far.position = o + Vector3(0, 2.3, -10)
	add_child(far)
	_cam("cam_corridor", o + Vector3(0.35, 1.7, 0.6), o + Vector3(0.1, 1.2, -13), 55.0, true)
	_cam("cam_doorway", o + Vector3(0.6, 1.35, -9.5), o + Vector3(0.5, 1.05, -13.6), 32.0, true)
	# a camera left pointing at the studio floor (wrong-camera grammar)
	_cam("cam_floor", Vector3(-1.5, 2.2, 6.0), Vector3(-0.8, 0.0, 4.2), 40.0, true)


func _build_graham() -> void:
	# Photographic cut-out (1086x1448 master, imported at 815x1086). Frame height ≈ 1.17 m:
	# top of head ≈ 1.80 m, crop line ≈ 0.65 m (hidden by the lectern top at 1.0 m).
	graham_sprite = Sprite3D.new()
	graham_sprite.pixel_size = 0.00108
	graham_sprite.shaded = false
	graham_sprite.double_sided = false
	graham_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	graham_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	graham_sprite.centered = true
	graham_sprite.offset = Vector2(0, 543)          # pivot at the bottom edge (breathing scales from the waist)
	graham_sprite.position = GRAHAM_POS + Vector3(0, 0.65, 0.0)
	add_child(graham_sprite)


func _cam(name: String, pos: Vector3, target: Vector3, fov: float, handheld: bool = false) -> Camera3D:
	var c := Camera3D.new()
	c.fov = fov
	add_child(c)
	c.look_at_from_position(pos, target, Vector3.UP)
	cameras[name] = c
	if handheld:
		_drift[name] = c.transform
	return c


func _build_cameras() -> void:
	# Camera 1: Graham medium close-up (head, tie, cards, lectern edge at the bottom).
	# Camera 1: Graham medium shot as in the reference — head near the top, cards at the bottom,
	# the sign behind him and coloured PAR cans just inside the top of frame.
	_cam("cam1", GRAHAM_POS + Vector3(0.02, 1.45, 2.45), GRAHAM_POS + Vector3(0, 1.40, 0), 24.0)
	_cam("cam2", Vector3(-0.3, 4.4, 13.5), Vector3(-0.3, 2.3, -1.5), 56.0)
	_cam("cam3", Vector3(-2.2, 2.3, 7.0), Vector3(3.4, 1.2, 0.6), 40.0, true)
	_cam("cam4", Vector3(8.5, 0.9, 7.5), Vector3(0.5, 3.5, -3.5), 52.0, true)
	_cam("cam_logo", Vector3(1.4, 2.6, 6.5), Vector3(1.4, 3.3, -3.8), 50.0, true)
	_cam("cam_podium", Vector3(2, 2, 4), Vector3(2, 1.2, 0.9), 26.0)


func _build_titles_rig() -> void:
	_titles = Node3D.new()
	_titles.position = Vector3(0, 0, -400)
	add_child(_titles)
	var tunnel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 7.0
	cyl.height = 120.0
	cyl.radial_segments = 32
	cyl.rings = 1
	tunnel.mesh = cyl
	var tm := ShaderMaterial.new()
	tm.shader = load("res://assets/shaders/tunnel.gdshader")
	tunnel.material_override = tm
	tunnel.rotation_degrees = Vector3(90, 0, 0)
	tunnel.position = Vector3(0, 0, -50)
	_titles.add_child(tunnel)
	_title_logo = Node3D.new()
	_titles.add_child(_title_logo)
	var tl := _text3d("MILDEW", _font_display, 260, 0.6, 0.012, _logo_mat, _title_logo)
	tl.position = Vector3(0, 0, 0)
	var q_mat := _mat(Color(0.95, 0.85, 0.2), 0.3, 0.0, 1.2)
	var g_mat := _mat(Color(0.5, 0.85, 0.3), 0.3, 0.0, 1.0)
	for i in 16:
		var bit: MeshInstance3D
		if i % 2 == 0:
			bit = _text3d("?", _font_display, 200, 0.2, 0.01, q_mat if i % 4 == 0 else _logo_mat, _titles)
		else:
			bit = MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			bit.mesh = sm
			bit.material_override = g_mat
			_titles.add_child(bit)
		bit.set_meta("seed", Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-3, 3), _rng.randf_range(0, 1)))
		_title_bits.append(bit)
	var flare_tex: Texture2D = load("res://assets/textures/flare.png")
	for i in 3:
		var f := Sprite3D.new()
		f.texture = flare_tex
		f.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		f.shaded = false
		f.pixel_size = 0.03
		f.modulate = [Color(1, 0.9, 0.7, 0.9), Color(0.6, 0.9, 1, 0.7), Color(1, 0.5, 0.9, 0.6)][i]
		f.set_meta("idx", i)
		_titles.add_child(f)
		_title_bits.append(f)
	var tc := Camera3D.new()
	tc.fov = 60
	_titles.add_child(tc)
	tc.position = Vector3(0, 0, 8)
	cameras["cam_titles"] = tc


func _build_ident_rig() -> void:
	_ident = Node3D.new()
	_ident.position = Vector3(400, 0, 0)
	add_child(_ident)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(40, 24)
	bg.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/backdrop.gdshader")
	sm.set_shader_parameter("top", Color(0.82, 0.74, 0.55))
	sm.set_shader_parameter("bottom", Color(0.42, 0.32, 0.2))
	sm.set_shader_parameter("sheen", 0.4)
	bg.material_override = sm
	bg.position = Vector3(0, 0, -6)
	_ident.add_child(bg)
	_ident_logo = Node3D.new()
	_ident.add_child(_ident_logo)
	var gold := ShaderMaterial.new()
	gold.shader = load("res://assets/shaders/chrome.gdshader")
	gold.set_shader_parameter("tint", Color(1.0, 0.8, 0.45))
	var s := _text3d("Sallow", _font_serif, 180, 0.4, 0.012, gold, _ident_logo)
	s.position = Vector3(0, 0.6, 0)
	var e := _text3d("ENTERTAINMENT LTD", _font_serif, 44, 0.08, 0.012, gold, _ident_logo)
	e.position = Vector3(0, -0.85, 0)
	var pr := _text3d("PRESENTS", _font_serif, 30, 0.05, 0.012, gold, _ident_logo)
	pr.position = Vector3(0, -1.9, 0)
	var ic := Camera3D.new()
	ic.fov = 50
	_ident.add_child(ic)
	ic.position = Vector3(0, 0, 8)
	cameras["cam_ident"] = ic


# ---------------------------------------------------------------------------
# Podiums
# ---------------------------------------------------------------------------

func sync_podiums(players: Array) -> void:
	var present := {}
	for p in players:
		present[p.pid] = true
		if not podiums.has(p.pid):
			_add_podium(p)
		var entry: Dictionary = podiums[p.pid]
		entry.screen.set_info(p)
	for pid in podiums.keys():
		if not present.has(pid):
			podiums[pid].node.queue_free()
			podiums.erase(pid)
	_layout_podiums()


func _add_podium(p: Dictionary) -> void:
	var root := Node3D.new()
	add_child(root)
	var colours := [Color(0.07, 0.5, 0.52), Color(0.6, 0.12, 0.42), Color(0.78, 0.58, 0.12), Color(0.35, 0.14, 0.6)]
	var col: Color = colours[(int(p.get("number", 1)) - 1) % colours.size()]
	_box(Vector3(0.95, 1.15, 0.7), Vector3(0, 0.88, 0), _mat(col, 0.35, 0.2), root)
	_box(Vector3(1.05, 0.07, 0.8), Vector3(0, 1.49, 0), _mat(Color(0.85, 0.68, 0.3), 0.25, 0.85), root)
	_box(Vector3(0.08, 1.15, 0.08), Vector3(-0.48, 0.88, 0.36), _mat(Color(0.85, 0.85, 0.9), 0.15, 0.95), root)
	_box(Vector3(0.08, 1.15, 0.08), Vector3(0.48, 0.88, 0.36), _mat(Color(0.85, 0.85, 0.9), 0.15, 0.95), root)
	var lamp := _box(Vector3(0.8, 0.08, 0.06), Vector3(0, 0.42, 0.37), _mat(Color(0.3, 0.25, 0.1), 0.4, 0.0, 0.2), root)
	# CRT monitor on the podium
	_box(Vector3(0.86, 0.66, 0.5), Vector3(0, 1.86, -0.05), _mat(Color(0.12, 0.12, 0.13), 0.6), root)
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 240)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var screen := PodiumScreen.new()
	screen.size = Vector2(320, 240)
	vp.add_child(screen)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.74, 0.555)
	face.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_texture = vp.get_texture()
	face.material_override = fm
	face.position = Vector3(0, 1.87, 0.205)
	root.add_child(face)
	root.scale = Vector3(0.01, 0.01, 0.01)
	podiums[p.pid] = {"node": root, "screen": screen, "lamp": lamp, "target": Vector3.ZERO, "colour": col}


func _layout_podiums() -> void:
	var ids := podiums.keys()
	ids.sort_custom(func(a, b): return int(podiums[a].screen.info.get("number", 0)) < int(podiums[b].screen.info.get("number", 0)))
	var n := ids.size()
	var spacing := clampf((PODIUM_AREA_X.y - PODIUM_AREA_X.x) / maxf(1.0, n), 1.05, 1.9)
	var start := (PODIUM_AREA_X.x + PODIUM_AREA_X.y) * 0.5 - spacing * (n - 1) * 0.5
	for i in n:
		var x := start + i * spacing
		var z := PODIUM_Z - 0.05 * pow(x - 3.3, 2.0)
		podiums[ids[i]].target = Vector3(x, 0.3, z)
		podiums[ids[i]].node.rotation.y = -0.22 - (x - 3.3) * 0.04


func light_podium(pid: String, on: bool) -> void:
	if podiums.has(pid):
		var lamp: MeshInstance3D = podiums[pid].lamp
		var m: StandardMaterial3D = lamp.material_override
		m.emission = Color(1.0, 0.85, 0.3) if on else Color(0.3, 0.25, 0.1)
		m.emission_energy_multiplier = 3.5 if on else 0.2
		podiums[pid].screen.lit = 1.0 if on else 0.0


func flash_podium(pid: String, text: String) -> void:
	if podiums.has(pid):
		podiums[pid].screen.flash = 1.0
		podiums[pid].screen.delta_text = text


# ---------------------------------------------------------------------------
# Cameras: live cut grammar
# ---------------------------------------------------------------------------

## Cut to camera `name`. Ordinary live TV: occasionally slightly late.
func cut_to(name: String, allow_imperfection: bool = true) -> void:
	if not cameras.has(name) or name == current_cam:
		return
	if allow_imperfection and _rng.randf() < 0.12 and current_cam != "":
		_pending_cut = name
		_pending_at = _t + _rng.randf_range(0.15, 0.4)
		return
	_do_cut(name)


func _do_cut(name: String) -> void:
	_pending_cut = ""
	current_cam = name
	(cameras[name] as Camera3D).make_current()
	cut_made.emit(name)


func frame_podium(pid: String) -> void:
	if not podiums.has(pid):
		return
	var t: Vector3 = podiums[pid].target
	var c: Camera3D = cameras["cam_podium"]
	c.look_at_from_position(t + Vector3(-0.7, 2.0, 3.1), t + Vector3(0, 1.75, 0), Vector3.UP)
	current_cam = ""
	_do_cut("cam_podium")


func play_titles(duration: float) -> void:
	_titles_len = duration
	_titles_t = 0.0
	_do_cut("cam_titles")


func play_ident() -> void:
	_do_cut("cam_ident")


func _process(delta: float) -> void:
	_t += delta
	if _pending_cut != "" and _t >= _pending_at:
		_do_cut(_pending_cut)
	# Operator drift on handheld/roaming cameras.
	for name in _drift.keys():
		var base: Transform3D = _drift[name]
		var c: Camera3D = cameras[name]
		var off := Vector3(sin(_t * 0.31 + name.length()) * 0.06, sin(_t * 0.23) * 0.04, 0.0)
		if name == "cam4":
			off.x += sin(_t * 0.08) * 1.2
		c.transform = base.translated(off)
		c.rotation.z = sin(_t * 0.17) * 0.006
	# Podium arrival animation
	for pid in podiums.keys():
		var e: Dictionary = podiums[pid]
		var node: Node3D = e.node
		node.position = node.position.lerp(e.target, 1.0 - exp(-delta * 5.0))
		node.scale = node.scale.lerp(Vector3.ONE, 1.0 - exp(-delta * 6.0))
	if _titles_t >= 0.0:
		_animate_titles(delta)
	if _ident_logo:
		_ident_logo.rotation.y = sin(_t * 0.6) * 0.25
	if _tube_light and current_cam in ["cam_corridor", "cam_doorway"]:
		var on := not (sin(_t * 23.0) > 0.86 or sin(_t * 3.1 + 1.0) > 0.97)   # cheap tube flicker
		_tube_light.light_energy = 1.6 if on else 0.15
		_tube_mat.emission_energy_multiplier = 2.5 if on else 0.1


func _animate_titles(delta: float) -> void:
	_titles_t += delta
	var p := clampf(_titles_t / _titles_len, 0.0, 1.0)
	# Logo hurtles out of the tunnel, spins, lands front-and-centre.
	var arrive := smoothstep(0.15, 0.7, p)
	_title_logo.position = Vector3(-3.6 * arrive + 0.0, -0.9 * arrive, lerpf(-90.0, -0.5, arrive))
	_title_logo.rotation = Vector3(0, (1.0 - arrive) * TAU * 2.0, (1.0 - arrive) * 0.8 + 0.06)
	_title_logo.scale = Vector3.ONE * (0.6 + 0.4 * arrive + 0.05 * sin(_titles_t * 9.0) * (1.0 - smoothstep(0.7, 0.8, p)))
	for bit in _title_bits:
		if bit is Sprite3D:
			var idx: int = bit.get_meta("idx")
			bit.position = Vector3(-6 + p * 12 + idx * 1.5, 2.5 - idx * 1.8, -4 - idx * 2)
			bit.scale = Vector3.ONE * (0.6 + 0.6 * sin(_titles_t * 3.0 + idx))
		else:
			var s: Vector3 = bit.get_meta("seed")
			var z := fmod(_titles_t * 26.0 + s.z * 80.0, 80.0)
			bit.position = Vector3(s.x * 1.3, s.y * 1.3, -80.0 + z)
			bit.rotation = Vector3(_titles_t * 2.0 + s.x, _titles_t * 3.0, 0)
	if p >= 1.0:
		_titles_t = -1.0
