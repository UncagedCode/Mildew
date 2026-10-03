extends SceneTree
## Renders each recurring room as a CCTV cutaway in a few states.
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	get_root().add_child(root)
	var view := ProgrammeView.new()
	root.add_child(view)
	view.build()
	view.set_layout("full")
	var db := ContentDB.load_default()
	var states := [{"door": "closed", "chair": "centre", "light": "on", "figure": "none"}, {"door": "open", "chair": "door", "light": "on", "figure": "far"},
		{"door": "ajar", "chair": "fallen", "light": "on", "figure": "podium"}, {"door": "closed", "chair": "centre", "light": "off", "figure": "none"}]
	var i := 0
	for r in db.query("room"):
		var st: Dictionary = states[i % states.size()]
		view.cctv.show_room({"room": r.id, "name": r.name, "cam": r.cam, "props": r.props, "door_side": r.door, "state": st,
			"plates": r.get("plates", {}), "figure_pos": r.get("figure_pos", []), "figure_plate": r.get("figure_plate", ""), "figure_plates": r.get("figure_plates", {})}, 5.0)
		for k in 8: await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out.path_join("%s.png" % r.id))
		i += 1
	quit()
