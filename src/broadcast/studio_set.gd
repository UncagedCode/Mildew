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
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.08, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.52, 0.62)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.82)
	key.light_energy = 0.75
	key.rotation_degrees = Vector3(-38, 12, 0)
	add_child(key)
	for spec in [[Vector3(-7, 5, 4), Color(1.0, 0.3, 0.75), 2.2], [Vector3(8, 5, 4), Color(0.2, 0.85, 0.95), 2.2],
			[Vector3(0, 6, -3), Color(0.7, 0.4, 1.0), 2.5], [GRAHAM_POS + Vector3(0, 3.5, 3.5), Color(1.0, 0.85, 0.7), 1.6]]:
		var l := OmniLight3D.new()
		l.position = spec[0]
		l.light_color = spec[1]
		l.light_energy = spec[2]
		l.omni_range = 14.0
		add_child(l)


func _build_set() -> void:
	# Carpet floor
	var carpet := _mat(Color.WHITE, 0.95)
	carpet.albedo_texture = load("res://assets/textures/carpet.png")
	carpet.uv1_scale = Vector3(6, 4, 1)
	carpet.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 20)
	floor_mesh.mesh = plane
	floor_mesh.material_override = carpet
	floor_mesh.position = Vector3(1, 0, 0)
	add_child(floor_mesh)
	# Stage riser with chrome nosing
	_box(Vector3(17, 0.3, 5.5), Vector3(1.2, 0.15, -0.6), _mat(Color(0.08, 0.32, 0.36), 0.5))
	_box(Vector3(17, 0.06, 0.08), Vector3(1.2, 0.31, 2.16), _mat(Color(0.9, 0.78, 0.4), 0.2, 0.9))
	# Back wall: loud gradient panels in gold MDF frames
	var bd := load("res://assets/shaders/backdrop.gdshader")
	# Reference set (references/graham): curved sage-green MDF panels, chrome trim, blue cyc behind.
	var palettes := [[Color(0.47, 0.6, 0.42), Color(0.3, 0.44, 0.3)], [Color(0.16, 0.24, 0.55), Color(0.08, 0.12, 0.34)],
		[Color(0.52, 0.64, 0.46), Color(0.33, 0.46, 0.33)]]
	for i in 7:
		var x := -8.4 + i * 2.8
		var z := -4.6 - 0.5 * pow((x - 1.2) / 8.0, 2.0) * 4.0
		var sm := ShaderMaterial.new()
		sm.shader = bd
		var pal: Array = palettes[i % palettes.size()]
		sm.set_shader_parameter("top", pal[0])
		sm.set_shader_parameter("bottom", pal[1])
		var panel := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2.6, 6.5)
		panel.mesh = q
		panel.material_override = sm
		panel.position = Vector3(x, 3.25, z)
		panel.rotation.y = -atan((x - 1.2) / 18.0)
		add_child(panel)
		var trim := _mat(Color(0.82, 0.84, 0.88), 0.18, 0.95)
		_box(Vector3(2.7, 0.12, 0.12), panel.position + Vector3(0, 3.25, 0.06), trim)
		_box(Vector3(0.12, 6.5, 0.12), panel.position + Vector3(-1.35, 0, 0.06), trim)
	# Giant extruded chrome MILDEW logo
	var logo := _text3d("MILDEW", _font_display, 260, 0.35, 0.012, _logo_mat, self)
	logo.position = Vector3(1.2, 4.6, -3.8)
	logo.rotation_degrees = Vector3(0, 0, 3)
	var logo_shadow := _text3d("MILDEW", _font_display, 260, 0.05, 0.012, _mat(Color(0.05, 0.0, 0.08)), self)
	logo_shadow.position = Vector3(1.32, 4.48, -4.05)
	logo_shadow.rotation_degrees = Vector3(0, 0, 3)
	# Mildew green "spores" stuck on the set (cheap foam decoration)
	for i in 14:
		var s := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = _rng.randf_range(0.08, 0.22)
		sp.height = sp.radius * 2.0
		s.mesh = sp
		s.material_override = _mat(Color(0.45, 0.7, 0.25), 0.4, 0.0, 0.25)
		s.position = Vector3(_rng.randf_range(-7.5, 9.5), _rng.randf_range(0.8, 6.0), -4.5)
		add_child(s)
	# Curtains
	var cm := _mat(Color.WHITE, 0.9)
	cm.albedo_texture = load("res://assets/textures/curtain.png")
	cm.uv1_scale = Vector3(2, 1, 1)
	for side in [-1, 1]:
		var c := MeshInstance3D.new()
		var cq := QuadMesh.new()
		cq.size = Vector2(4.0, 7.5)
		c.mesh = cq
		c.material_override = cm
		c.position = Vector3(1.2 + side * 10.6, 3.75, -3.0)
		c.rotation.y = -side * 0.6
		add_child(c)
	# Lighting trusses with lamp cans
	var truss := _mat(Color(0.15, 0.15, 0.17), 0.5, 0.6)
	_box(Vector3(20, 0.25, 0.25), Vector3(1.2, 7.2, 1.5), truss)
	_box(Vector3(20, 0.25, 0.25), Vector3(1.2, 7.2, -2.0), truss)
	for i in 9:
		var lamp_col: Color = [Color(1, 0.3, 0.7), Color(0.2, 0.9, 1.0), Color(1, 0.85, 0.4)][i % 3]
		_box(Vector3(0.35, 0.45, 0.35), Vector3(-7.5 + i * 2.2, 6.85, 1.5), _mat(Color(0.1, 0.1, 0.1)))
		_box(Vector3(0.26, 0.05, 0.26), Vector3(-7.5 + i * 2.2, 6.6, 1.5), _mat(lamp_col, 0.3, 0.0, 3.0))
	# Plastic plants in pots
	for px in [-7.6, 9.8]:
		_box(Vector3(0.7, 0.8, 0.7), Vector3(px, 0.7, 1.4), _mat(Color(0.75, 0.6, 0.3), 0.4, 0.3))
		for k in 7:
			var leaf := MeshInstance3D.new()
			var lm := SphereMesh.new()
			lm.radius = 0.35
			lm.height = 1.2
			leaf.mesh = lm
			leaf.material_override = _mat(Color(0.18, 0.55, 0.22), 0.2)
			leaf.position = Vector3(px + _rng.randf_range(-0.35, 0.35), 1.5 + _rng.randf_range(0.0, 0.9), 1.4 + _rng.randf_range(-0.3, 0.3))
			leaf.rotation = Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf(), _rng.randf_range(-0.6, 0.6))
			add_child(leaf)
	# Graham's mark: curved green MILDEW sign behind him (as in the reference set) and a low
	# sage lectern in front whose top hides the cut-out's crop line.
	var sign_mat := _mat(Color(0.5, 0.62, 0.44), 0.7)
	var sign := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.2
	cyl.bottom_radius = 3.2
	cyl.height = 1.5
	cyl.radial_segments = 48
	sign.mesh = cyl
	sign.material_override = sign_mat
	sign.position = GRAHAM_POS + Vector3(0, 1.95, -3.75)
	add_child(sign)
	var chrome := _mat(Color(0.85, 0.86, 0.9), 0.15, 0.95)
	for dy in [0.78, -0.78]:
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 3.16
		tor.outer_radius = 3.3
		tor.rings = 48
		ring.mesh = tor
		ring.material_override = chrome
		ring.position = sign.position + Vector3(0, dy, 0)
		add_child(ring)
	var gold_letters := _mat(Color(0.98, 0.72, 0.22), 0.35, 0.3, 0.15)
	var word := _text3d("MILDEW", _font_display, 72, 0.1, 0.006, gold_letters, self)
	word.position = GRAHAM_POS + Vector3(0, 1.84, -0.47)
	word.rotation_degrees = Vector3(0, 0, 2)
	var word_shadow := _text3d("MILDEW", _font_display, 72, 0.03, 0.006, _mat(Color(0.45, 0.2, 0.05)), self)
	word_shadow.position = word.position + Vector3(0.03, -0.035, -0.05)
	word_shadow.rotation_degrees = Vector3(0, 0, 2)
	var desk_mat := _mat(Color(0.46, 0.58, 0.42), 0.55)
	_box(Vector3(1.9, 0.98, 0.7), GRAHAM_POS + Vector3(0, 0.49, 0.5), desk_mat)
	_box(Vector3(2.0, 0.05, 0.8), GRAHAM_POS + Vector3(0, 1.0, 0.5), chrome)
	var m := _text3d("M", _font_display, 160, 0.08, 0.004, _logo_mat, self)
	m.position = GRAHAM_POS + Vector3(0, 0.55, 0.88)


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
	_cam("cam1", GRAHAM_POS + Vector3(0.04, 1.62, 2.75), GRAHAM_POS + Vector3(0, 1.47, 0), 22.0)
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
