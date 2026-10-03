extends SceneTree
## Renders the CP3 quiz board (question, then reveal + fact card) for given content ids.
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tests/tools/render_quiz.gd -- OUTDIR id1 id2 ...
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	get_root().add_child(root)
	var view := ProgrammeView.new()
	root.add_child(view)
	view.build()
	view.set_layout("full")
	var db := ContentDB.load_default()
	view.quiz.players = {"p1": {"avatar": {"hair": 1}}, "p2": {"avatar": {"hair": 3, "outfit": 2}}}
	for i in range(1, a.size()):
		var it := db.get_item(a[i])
		if it.is_empty():
			continue
		var layout := "image" if str(a[i]).begins_with("gtg.") else "claims"
		var evt := {"layout": layout, "title": "GUESS THE GENITALS" if layout == "image" else "REAL OR MILDEW?", "prompt": it.get("prompt", ""),
			"options": it.options, "image": it.get("image", ""), "crop": it.get("crop", {}), "round": i, "of": 6, "final": false,
			"confidence": i == 2, "variant": it.get("round", "")}
		view.quiz.show_question(evt)
		view.quiz.set_answered(1, 2)
		view.quiz.start_timer(15.0)
		for k in 45: await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out.path_join("%s_q.png" % a[i]))
		var stamps: Array = []
		if layout == "claims":
			for j in it.options.size():
				match str(it.round):
					"which_real": stamps.append("REAL" if j == int(it.correct) else "MILDEW")
					"one_mildew": stamps.append("MILDEW" if j == int(it.correct) else "REAL")
					_: stamps.append("REAL" if j != it.options.size() - 1 else "")
		view.quiz.reveal({"correct": int(it.correct), "stamps": stamps, "fact": it.get("fact", ""), "answer_label": it.get("answer_label", ""),
			"picks": {"p1": int(it.correct), "p2": (int(it.correct) + 1) % it.options.size()}, "certain": {"p2": true}})
		for k in 240: await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out.path_join("%s_r.png" % a[i]))
		print("SHOT ", a[i])
	quit()
