extends SceneTree
## Renders plate cameras with live contestants to check screen/lamp compositing (dev tool).
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tests/tools/render_plate_check.gd -- OUTDIR
func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	get_root().add_child(root)
	var view := ProgrammeView.new()
	root.add_child(view)
	view.build()
	view.set_layout("full")
	var names := ["Aaron", "Grace", "Josh", "Donna", "Elijah"]
	var players: Array = []
	for i in names.size():
		players.append({"pid": "p%d" % (i + 1), "number": [1, 2, 4, 6, 8][i], "name": names[i], "score": i * 1100,
			"avatar": {"hair": i, "outfit": i + 2, "skin": i % 3, "hair_colour": i}})
	view.studio.sync_podiums(players)
	view.plates.show_hotspots = "--hot" in OS.get_cmdline_user_args()
	for i in 60: await process_frame
	view.studio.light_podium("p2", true)
	view.studio.light_podium("p4", true)
	for shot in ["cam2", "cam3", "podium"]:
		if shot == "podium":
			view.studio.frame_podium("p3")
		else:
			view.studio._do_cut(shot)
		for i in 15: await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out.path_join("plate_%s.png" % shot))
		print("SHOT ", shot, " plate=", view.plates.active)
	quit()
