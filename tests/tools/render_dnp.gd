extends SceneTree
## Renders the CP6 Do Not Press That board for each display kind + a tier stamp.
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tests/tools/render_dnp.gd -- OUTDIR
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
	var b := view.dnp
	b.players = {"p1": {"name": "Aaron"}, "p2": {"name": "Grace"}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for id in ["dnp.studio_power", "dnp.pressure_valves", "dnp.gas_oven"]:
		var tpl := db.get_item(id)
		var p := DnpPuzzle.generate(tpl, 3, rng)
		b.on_event({"e": "dnp_puzzle", "title": tpl.title, "flavour": tpl.flavour, "display": p.display, "round": 2, "of": 4, "controls": 4}, 1.0)
		b.on_event({"e": "dnp_open", "window": 75.0, "tv_offset": 0.0, "solved": 1}, 1.0)
		b.on_event({"e": "dnp_state", "solved": 2, "of": 4, "mistakes": 1}, 1.0)
		if id == "dnp.pressure_valves":
			b.on_event({"e": "dnp_mistake", "pid": "p1"}, 1.0)
		for k in 30: await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out.path_join(id + ".png"))
	b.on_event({"e": "dnp_result", "tier": "failed"}, 1.0)
	for k in 40: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join("tier.png"))
	quit()
