extends SceneTree
## Renders the CP7 Basement board: case file, theory, reveal.
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	get_root().add_child(root)
	var view := ProgrammeView.new()
	root.add_child(view)
	view.build()
	view.set_layout("full")
	var c := ContentDB.load_default().get_item("bas.footsteps")
	var b := view.bas
	b.players = {"p1": {"name": "Aaron", "avatar": {"hair": 1}}, "p2": {"name": "Grace", "avatar": {"hair": 3}}, "p3": {"name": "Josh", "avatar": {"hair": 4}}}
	b.on_event({"e": "bas_case", "title": c.title, "setup": c.setup, "location": c.location, "investigations": c.investigations.map(func(i): return i.label), "inv_limit": 2, "players": ["p1", "p2", "p3"]}, 1.0)
	b.on_event({"e": "bas_discuss", "window": 150.0, "of": 3}, 1.0)
	b.on_event({"e": "bas_investigated", "pid": "p2", "label": c.investigations[1].label}, 1.0)
	b.on_event({"e": "bas_ready", "pid": "p1"}, 1.0)
	for k in 30: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join("bas_case.png"))
	var qs: Array = c.questions.map(func(q): return {"id": q.id, "ask": q.ask, "options": q.options})
	b.on_event({"e": "bas_reveal", "questions": qs, "tallies": {"what": [1, 0, 2, 0], "who": [0, 0, 1, 2]}, "best": {"what": 0, "who": 3}, "agreed": {"what": false, "who": false},
		"reveal": c.reveal, "unresolved": true}, 1.0)
	for k in 600: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join("bas_reveal.png"))
	quit()
