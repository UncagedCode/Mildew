class_name ProgrammeView
extends Control
## Composites the 4:3 programme (its own SubViewport: 3D studio + graphics) into the 16:9
## output with the broadcast treatment. Layouts: "full" (centred 4:3 broadcast),
## "lobby" (programme monitor on the left; real join info in the system layer).

const PROG_W := 1440
const PROG_H := 1080

var viewport: SubViewport
var studio: StudioSet
var gfx: GraphicsLayer
var hole: HoleBoard
var graham: GrahamPresenter
var screen: TextureRect
var material_crt: ShaderMaterial
var _target := Rect2(240, 0, 1440, 1080)


func build() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.size = Vector2i(PROG_W, PROG_H)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	studio = StudioSet.new()
	viewport.add_child(studio)
	studio.build()
	graham = GrahamPresenter.new()
	graham.studio = studio
	viewport.add_child(graham)         # plate-mode fallback draws here; composited mode drives a 3D sprite
	graham.attach_sprite(studio.graham_sprite)
	studio.graham = graham
	hole = HoleBoard.new()
	viewport.add_child(hole)       # game boards sit under the graphics package (subtitles, lower-thirds)
	gfx = GraphicsLayer.new()
	viewport.add_child(gfx)
	gfx.bottom_busy = hole.is_showing
	screen = TextureRect.new()
	screen.texture = viewport.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	material_crt = ShaderMaterial.new()
	material_crt.shader = load("res://assets/shaders/broadcast_crt.gdshader")
	screen.material = material_crt
	add_child(screen)
	_apply(_target)


func set_layout(mode: String) -> void:
	match mode:
		"lobby":
			_target = Rect2(70, 150, 1040, 780)
		_:
			_target = Rect2(240, 0, 1440, 1080)


func set_treatment(param: String, value) -> void:
	material_crt.set_shader_parameter(param, value)


func _process(delta: float) -> void:
	var cur := Rect2(screen.position, screen.size)
	var k := 1.0 - exp(-delta * 5.0)
	_apply(Rect2(cur.position.lerp(_target.position, k), cur.size.lerp(_target.size, k)))


func _apply(r: Rect2) -> void:
	screen.position = r.position
	screen.size = r.size
