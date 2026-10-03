extends SceneTree
## Renders the CP5 Police Sketch board phases.
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tests/tools/render_sketch.gd -- OUTDIR
var out := ""


func _shot(name: String, frames := 40) -> void:
	for k in frames: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("SHOT ", name)


func _pigeon() -> Array:
	# a crude hand-made "pigeon" so the render resembles a real phone drawing
	var body: Array = []
	for i in 40:
		var a := TAU * i / 39.0
		body.append_array([500 + int(cos(a) * 260), 560 + int(sin(a) * 170)])
	var head: Array = []
	for i in 30:
		var a := TAU * i / 29.0
		head.append_array([700 + int(cos(a) * 90), 330 + int(sin(a) * 90)])
	return [{"w": 2, "p": body}, {"w": 2, "p": head}, {"w": 1, "p": [780, 330, 860, 350, 780, 370]},
		{"w": 3, "p": [420, 720, 400, 860]}, {"w": 3, "p": [560, 720, 580, 860]},
		{"w": 2, "p": [300, 450, 360, 380, 450, 420, 520, 360, 600, 430]}, {"w": 1, "p": [720, 300, 722, 302]}]


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	get_root().add_child(root)
	var view := ProgrammeView.new()
	root.add_child(view)
	view.build()
	view.set_layout("full")
	var b := view.ps
	b.players = {"p1": {"name": "Aaron", "avatar": {"hair": 1}}, "p2": {"name": "Grace", "avatar": {"hair": 3, "outfit": 2}},
		"p3": {"name": "Josh", "avatar": {"hair": 4, "glasses": 1}}, "p4": {"name": "Donna", "avatar": {"hair": 2, "outfit": 5}}}
	b.on_event({"e": "ps_show", "order": ["p1", "p2", "p3", "p4"], "steps": 4, "exhibit": []}, 1.0)
	b.on_event({"e": "ps_step", "step": 0, "kind": "draw", "window": 50.0, "of": 4}, 1.0)
	b.on_event({"e": "ps_progress", "pid": "p2", "count": 1, "of": 4}, 1.0)
	await _shot("ps_step")
	var chain := {"owner": "p1", "prompt": "A suspicious-looking pigeon wearing something it clearly stole", "variant": "standard", "fidelity": 0.25,
		"reconstructed": false, "steps": [
		{"kind": "draw", "pid": "p2", "strokes": _pigeon(), "text": "", "missing": false},
		{"kind": "describe", "pid": "p3", "strokes": [], "text": "A fat duck stealing a hat from a policeman", "missing": false},
		{"kind": "draw", "pid": "p4", "strokes": _pigeon().slice(0, 4), "text": "", "missing": false},
		{"kind": "describe", "pid": "p1", "strokes": [], "text": "A potato in a crash helmet", "missing": false}]}
	b.on_event({"e": "ps_reveal_chain", "index": 0, "of": 4, "chain": chain}, 1.0)
	await _shot("ps_reveal", 700)
	b.on_event({"e": "ps_vote_open", "category": "drawing", "options": [{"label": "A", "chain": 0, "step_i": 0}, {"label": "B", "chain": 0, "step_i": 2}], "window": 20.0, "of": 4}, 1.0)
	await _shot("ps_vote")
	b.on_event({"e": "ps_show", "order": ["p1", "p2"], "steps": 2, "exhibit": _pigeon()}, 1.0)
	await _shot("ps_exhibit")
	quit()
