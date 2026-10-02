extends SceneTree
## Dev preview: renders GrahamPuppet in each mood to tests/output/graham_moods.png
func _initialize() -> void:
	var moods := ["relaxed", "pleased", "amused", "irritated", "angry", "embarrassed", "rattled", "stare"]
	root.size = Vector2i(2048, 1280)
	var bg := ColorRect.new(); bg.color = Color(0.25, 0.12, 0.35); bg.size = Vector2(2048, 1280); root.add_child(bg)
	var pups: Array = []
	for i in moods.size():
		var g := GrahamPuppet.new()
		g.position = Vector2((i % 4) * 512, (i / 4) * 640)
		root.add_child(g)
		if moods[i] == "stare":
			g.set_activity("stare")
		else:
			g.set_mood(moods[i])
		g.set_pressure(0.2 if i < 4 else 0.8)
		pups.append(g)
	for f in 12:
		await process_frame
	pups[1].speak(2.0)
	for f in 3:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://tests/output/graham_moods.png")
	print("saved")
	quit()
