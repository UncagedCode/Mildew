extends SceneTree
## Renders STAND-IN studio plates from the 3D set and computes their hotspots (D026).
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tests/tools/render_plates.gd
## Writes assets/studio/plates/standin_*.jpg (+ _fg.png foreground layers) and config/studio_plates.json.
## Real photographic plates replace these entries (same schema; hotspots authored by hand).

const OUT := "res://assets/studio/plates_standin/"
const MAP := "res://config/studio_plates_standin.json"   # never overwrites the real plate map
const W := 1440.0
const H := 1080.0
var view: ProgrammeView

const SHOTS := {
	"cam1": "standin_cam1", "cam2": "standin_wide_master", "cam3": "standin_podium_row", "cam4": "standin_presenter_wide",
	"cam_podium": "standin_podium_closeup", "cam_corridor": "standin_corridor", "cam_doorway": "standin_corridor_doorway",
	"cam_floor": "standin_floor_wrong_camera",
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	get_root().add_child(root)
	view = ProgrammeView.new()
	root.add_child(view)
	view.build()
	view.set_layout("full")
	_run()


func _project(cam: Camera3D, p: Vector3) -> Array:
	if cam.is_position_behind(p):
		return []
	var v := cam.unproject_position(p)
	return [snappedf(v.x / W, 0.0001), snappedf(v.y / H, 0.0001)]


func _inside(pts: Array) -> bool:
	for p in pts:
		if p.is_empty() or p[0] < -0.05 or p[0] > 1.05 or p[1] < -0.05 or p[1] > 1.05:
			return false
	return true


func _run() -> void:
	var st: StudioSet = view.studio
	view.plates.plates = {}
	view.plates.cam_map = {}
	view.gfx.visible = false
	view.hole.visible = false
	st.graham_sprite.visible = false
	var players: Array = []
	for i in 8:
		players.append({"pid": "p%d" % (i + 1), "number": i + 1, "name": "", "avatar": {}})
	st.sync_podiums(players)
	var off := StandardMaterial3D.new()
	off.albedo_color = Color(0.11, 0.12, 0.13)
	off.roughness = 0.12
	off.metallic_specular = 0.9
	for pid in st.podiums:
		(st.podiums[pid].face as MeshInstance3D).material_override = off
	for i in 150: await process_frame
	var plates := {}
	var cameras := {}
	for cam_name in SHOTS:
		var id: String = SHOTS[cam_name]
		if cam_name == "cam_podium":
			st.frame_podium("p4")
		else:
			st._do_cut(cam_name)
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		var img := view.viewport.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_jpg(ProjectSettings.globalize_path(OUT + id + ".jpg"), 0.9)
		var cam: Camera3D = st.cameras[cam_name]
		var spec := {"image": OUT + id + ".jpg", "standin": true, "drift": {"px": 2.0 if cam_name == "cam1" else 4.0, "zoom": 0.004}}
		# Graham's mark
		var foot := _project(cam, StudioSet.GRAHAM_POS + Vector3(0, 0.65, 0))
		var top := _project(cam, StudioSet.GRAHAM_POS + Vector3(0, 0.65 + PlateStage.GRAHAM_FRAME_M, 0))
		if not foot.is_empty() and not top.is_empty() and foot[0] > -0.2 and foot[0] < 1.2 and top[1] < 1.0:
			spec["graham"] = {"anchor": foot, "height": snappedf(foot[1] - top[1], 0.0001)}
		# podium screens + lamps
		var screens: Array = []
		var lamps: Array = []
		for pid in st.podiums:
			if cam_name == "cam_podium" and pid != "p4":
				continue
			var e: Dictionary = st.podiums[pid]
			var n := int(e.screen.info.get("number", 0))
			var face: MeshInstance3D = e.face
			var q: Array = []
			for c in [Vector3(-0.37, 0.2775, 0), Vector3(0.37, 0.2775, 0), Vector3(0.37, -0.2775, 0), Vector3(-0.37, -0.2775, 0)]:
				q.append(_project(cam, face.global_transform * c))
			if _inside(q):
				screens.append({"podium": 0 if cam_name == "cam_podium" else n, "quad": q})
			var lamp: MeshInstance3D = e.lamp
			var lq: Array = []
			for c in [Vector3(-0.4, 0.04, 0.031), Vector3(0.4, 0.04, 0.031), Vector3(0.4, -0.04, 0.031), Vector3(-0.4, -0.04, 0.031)]:
				lq.append(_project(cam, lamp.global_transform * c))
			if _inside(lq) and cam_name != "cam_podium":
				lamps.append({"podium": n, "quad": lq})
		spec["screens"] = screens
		spec["lamps"] = lamps
		var lights: Array = []
		for pl in st.par_lenses:
			var lens: MeshInstance3D = pl[0]
			var at := _project(cam, lens.global_position)
			var edge := _project(cam, lens.global_position + cam.global_transform.basis.x * 0.12 * lens.global_transform.basis.get_scale().x)
			if _inside([at]) and not edge.is_empty():
				lights.append({"at": at, "r": snappedf(absf(edge[0] - at[0]), 0.0001), "colour": "#" + (pl[1] as Color).to_html(false)})
		spec["lights"] = lights
		# foreground layer: only the set pieces in front of Graham, on transparent black
		if spec.has("graham"):
			var hidden: Array = []
			for nd in _all_visuals(st):
				if not st.foreground_nodes.has(nd) and nd.visible:
					nd.visible = false
					hidden.append(nd)
			view.viewport.transparent_bg = true
			var we: WorldEnvironment = _find_env(st)
			var bg := we.environment.background_mode
			we.environment.background_mode = Environment.BG_CLEAR_COLOR
			for i in 3: await process_frame
			await RenderingServer.frame_post_draw
			var fg := view.viewport.get_texture().get_image()
			if not fg.is_invisible():
				fg.save_png(ProjectSettings.globalize_path(OUT + id + "_fg.png"))
				spec["foreground"] = OUT + id + "_fg.png"
			we.environment.background_mode = bg
			view.viewport.transparent_bg = false
			for nd in hidden:
				nd.visible = true
		plates[id] = spec
		cameras[cam_name] = id
		print("PLATE ", id, " screens=", spec.screens.size(), " graham=", spec.has("graham"), " lights=", lights.size())
	var out := {"version": 1, "_comment": "Studio plates (D026). Stand-ins rendered by tests/tools/render_plates.gd; replace entries with photographic plates (same schema). Coordinates are normalised to the 4:3 programme frame. graham.anchor = bottom-centre of Graham's cut-out frame (crop line); graham.height = cut-out frame height / frame height. screens[].podium 0 = the contestant currently framed.",
		"cameras": cameras, "plates": plates}
	var f := FileAccess.open(MAP, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("PLATES_DONE ", plates.size())
	quit()


func _all_visuals(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is GeometryInstance3D:
			out.append(c)
		out.append_array(_all_visuals(c))
	return out


func _find_env(n: Node) -> WorldEnvironment:
	for c in n.get_children():
		if c is WorldEnvironment:
			return c
	return null
