extends SceneTree
## Renders the CP4 write/vote board through each phase (survey + mouthfeel + chain + who said).
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tests/tools/render_wv.gd -- OUTDIR
var view: ProgrammeView
var out := ""


func _shot(name: String, frames := 40) -> void:
	for k in frames: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("SHOT ", name)


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	get_root().add_child(root)
	view = ProgrammeView.new()
	root.add_child(view)
	view.build()
	view.set_layout("full")
	var b := view.wv
	b.players = {"p1": {"name": "Aaron", "avatar": {"hair": 1}}, "p2": {"name": "Grace", "avatar": {"hair": 3, "outfit": 2}},
		"p3": {"name": "Josh", "avatar": {"hair": 4, "glasses": 1}}, "p4": {"name": "Donna", "avatar": {"hair": 2, "outfit": 5}}}
	b.on_event({"e": "wv_show", "game_id": "mildew_survey", "mode": "popularity", "title": "MILDEW SURVEY", "prompt": "What's the worst thing to discover underneath a hotel mattress?", "round": 1, "of": 4}, 1.0)
	b.on_event({"e": "wv_write_open", "window": 45.0, "of": 4}, 1.0)
	b.on_event({"e": "wv_progress", "pid": "p2", "count": 1, "of": 4}, 1.0)
	b.on_event({"e": "wv_progress", "pid": "p4", "count": 2, "of": 4}, 1.0)
	await _shot("sv_write")
	var answers := ["A second, smaller guest", "Ham", "My nan's dentures and a note that says sorry", "Warmth", "Another mattress"]
	b.on_event({"e": "wv_vote_open", "answers": answers, "window": 25.0, "mode": "popularity", "featured": -1, "of": 4}, 1.0)
	b.on_event({"e": "wv_vote_progress", "pid": "p1", "count": 1, "of": 4}, 1.0)
	await _shot("sv_vote", 60)
	b.on_event({"e": "wv_reveal", "mode": "popularity", "answers": [
		{"text": answers[0], "author": "archive", "kind": "archive"}, {"text": answers[1], "author": "p1", "kind": "player"},
		{"text": answers[2], "author": "p2", "kind": "player"}, {"text": answers[3], "author": "graham", "kind": "graham"},
		{"text": answers[4], "author": "p3", "kind": "player"}],
		"tally": [0, 1, 2, 0, 1], "winner": 2, "graham_choice": -1, "votes": {"p1": 2, "p3": 2, "p2": 1, "p4": 4}, "deltas": {}}, 1.0)
	await _shot("sv_reveal", 120)
	b.on_event({"e": "wv_show", "game_id": "mildew_survey", "mode": "who_said", "title": "MILDEW SURVEY", "prompt": "What's in the locked room?", "round": 3, "of": 4}, 1.0)
	b.on_event({"e": "wv_vote_open", "answers": ["Neil's other shoes", "Ham", "Carol"], "window": 25.0, "mode": "who_said", "featured": 0, "of": 4}, 1.0)
	await _shot("sv_who", 50)
	b.on_event({"e": "wv_reveal", "mode": "who_said", "answers": [{"text": "Neil's other shoes", "author": "p3", "kind": "player"}],
		"featured": 0, "votes": {"p1": 2, "p2": 1, "p4": 2}, "guess_names": ["Aaron", "Grace", "Josh", "Donna"], "author_index": 2, "deltas": {}}, 1.0)
	await _shot("sv_who_reveal", 60)
	b.on_event({"e": "wv_show", "game_id": "mouthfeel", "mode": "popularity", "title": "MOUTHFEEL", "category": "MOST DISGUSTING", "prompt": "COLD PORRIDGE + CARPET UNDERLAY", "round": 1, "of": 5}, 1.0)
	b.on_event({"e": "wv_write_open", "window": 45.0, "of": 4}, 1.0)
	await _shot("mf_write")
	var mfa := ["Like chewing a wet doormat that's had good news", "Firm at the edges. Forgiving in the middle. Like a vicar.", "Spongy then gritty then personal", "A damp hug that won't end"]
	b.on_event({"e": "wv_vote_open", "answers": mfa, "window": 25.0, "mode": "popularity", "featured": -1, "of": 4, "category": "MOST DISGUSTING"}, 1.0)
	b.on_event({"e": "wv_reveal", "mode": "popularity", "answers": [
		{"text": mfa[0], "author": "p1", "kind": "player"}, {"text": mfa[1], "author": "graham", "kind": "graham"},
		{"text": mfa[2], "author": "p2", "kind": "player"}, {"text": mfa[3], "author": "p4", "kind": "player"}],
		"tally": [1, 2, 1, 0], "winner": 1, "graham_choice": 2, "votes": {"p2": 1, "p3": 1, "p4": 0, "p1": 2}, "deltas": {}}, 1.0)
	await _shot("mf_reveal", 120)
	b.on_event({"e": "wv_show", "game_id": "mouthfeel", "mode": "chain", "title": "MAKE IT WORSE", "prompt": "A CHEESE SANDWICH", "round": 5, "of": 5}, 1.0)
	b.on_event({"e": "wv_chain", "text": "A CHEESE SANDWICH, but warm, with hair in it", "step": 2, "of": 4, "pid": "p3"}, 1.0)
	await _shot("mf_chain")
	b.on_event({"e": "wv_chain_final", "text": "A CHEESE SANDWICH, but warm, with hair in it, served in a shoe, left out overnight", "window": 25.0, "of": 4}, 1.0)
	b.on_event({"e": "wv_reveal", "mode": "chain", "text": "A CHEESE SANDWICH, but warm, with hair in it, served in a shoe, left out overnight",
		"parts": [{"pid": "p1"}, {"pid": "p2"}, {"pid": "p3"}, {"pid": "p4"}], "ratings": {}, "average": 4.2, "deltas": {}}, 1.0)
	await _shot("mf_chain_reveal", 120)
	quit()
