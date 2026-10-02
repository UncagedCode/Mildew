extends SceneTree
## Renders a few programme camera shots to PNG (xvfb): godot --path . --rendering-driver opengl3 -s res://tests/tools/render_shots.gd -- OUTDIR [state]
var view: ProgrammeView
var out := "user://shots"
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	get_root().add_child(root)
	view = ProgrammeView.new()
	root.add_child(view)
	view.build()
	view.set_layout("full")
	if a.size() > 1 and a[1] == "gallery":
		_gallery()
	else:
		_run(a[1] if a.size() > 1 else "restrained_smile")

func _gallery() -> void:
	for i in 40: await process_frame
	view.studio._do_cut("cam1")
	for st in view.graham.all_states():
		view.graham.set_state(st, "cut")
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out.path_join("gallery_%s.png" % st))
	print("GALLERY_DONE ", view.graham.all_states().size())
	quit()

func _run(state: String) -> void:
	for i in 40: await process_frame
	view.graham.set_state(state, "cut")
	for shot in ["cam1", "cam2", "cam3", "cam4"]:
		view.studio._do_cut(shot)
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out.path_join("%s_%s.png" % [shot, state]))
		print("SHOT ", shot)
	quit()
