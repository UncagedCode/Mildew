extends SceneTree
## Renders one frame from the middle of every scene of every advert, plus poll/awards/break cards.
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tests/tools/render_ads.gd -- OUTDIR
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	get_root().add_child(root)
	var view := ProgrammeView.new()
	root.add_child(view)
	view.build()
	view.set_layout("full")
	view.gfx.dog_visible = false
	var p := view.ads
	var db := ContentDB.load_default()
	for ad in db.query("advert"):
		var acc := 0.0
		for i in ad.scenes.size():
			p.play(ad, 1.0)
			p._start = p._t - (acc + float(ad.scenes[i].t) * 0.7)
			acc += float(ad.scenes[i].t)
			for k in 3: await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png(out.path_join("%s_%d.png" % [ad.id, i]))
	p.players = {"p1": {"name": "Aaron", "avatar": {"hair": 1}}, "p2": {"name": "Grace", "avatar": {"hair": 3}}}
	p.show_poll({"prompt": "Should the studio fridge be cleaned?", "options": ["YES", "NO", "BURN IT"]})
	p.poll_result({"tally": [1, 0, 3]})
	for k in 60: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join("poll.png"))
	p.show_award({"title": "MOST ROT", "pid": "p1"})
	p.show_award({"title": "GRAHAM'S FAVOURITE", "pid": "p2"})
	p.show_award({"title": "TONIGHT'S STAR PRIZE", "pid": "p2", "prize": "A TIN OF HAMCO HAM, SIGNED"})
	for k in 40: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join("awards.png"))
	p.show_card({"kind": "interval", "title": "PART TWO IN A MOMENT", "sub": "PRESS READY ON YOUR UNIT WHEN YOU'RE BACK", "seconds": 50}, 1.0)
	p.set_ready(2, 4)
	for k in 10: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join("interval.png"))
	quit()
