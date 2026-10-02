extends MildewTest
## Photographic studio plates (D026): the plate map is complete and sane, so swapping stand-ins for
## real photographs can only fail loudly in tests, never silently on the TV.

func _map() -> Dictionary:
	var f := FileAccess.open(PlateStage.MAP_PATH, FileAccess.READ)
	check(f != null, "studio_plates.json present")
	return JSON.parse_string(f.get_as_text()) if f else {}


func _in01(p) -> bool:
	return typeof(p) == TYPE_ARRAY and p.size() == 2 and float(p[0]) >= -0.06 and float(p[0]) <= 1.06 and float(p[1]) >= -0.06 and float(p[1]) <= 1.06


func test_plate_map_is_complete() -> void:
	var m := _map()
	var plates: Dictionary = m.get("plates", {})
	var cams: Dictionary = m.get("cameras", {})
	for cam in ["cam1", "cam2", "cam3", "cam_podium"]:
		check(cams.has(cam) and plates.has(str(cams[cam])), "camera %s has a plate" % cam)
	for id in plates:
		var p: Dictionary = plates[id]
		check(ResourceLoader.exists(str(p.get("image", ""))), "%s image imported (%s)" % [id, p.get("image")])
		if p.has("foreground"):
			check(ResourceLoader.exists(str(p.foreground)), "%s foreground imported" % id)
		if p.has("graham"):
			# the anchor (cut-out crop line) may sit below the frame edge, as in Camera 1
			check(float(p.graham.anchor[0]) > -0.1 and float(p.graham.anchor[0]) < 1.1 and float(p.graham.anchor[1]) > 0.0 and float(p.graham.anchor[1]) < 2.0, "%s graham anchor sane" % id)
			check(float(p.graham.height) > 0.02 and float(p.graham.height) < 1.6, "%s graham height sane" % id)
		var seen := {}
		for s in p.get("screens", []):
			check(int(s.podium) >= 0 and int(s.podium) <= 8, "%s screen podium number valid" % id)
			check(not seen.has(int(s.podium)), "%s podium %s mapped once" % [id, s.podium])
			seen[int(s.podium)] = true
			check(s.quad.size() == 4, "%s screen quad has 4 corners" % id)
			for q in s.quad:
				check(_in01(q), "%s screen corner in frame" % id)
		for l in p.get("lights", []):
			check(_in01(l.at), "%s light in frame" % id)
	check(plates.has(str(cams.get("cam1", ""))) and plates[str(cams.cam1)].has("graham"), "Camera 1 plate places Graham")
	var wide: Dictionary = plates.get(str(cams.get("cam2", "")), {})
	check(wide.get("screens", []).size() == 8, "wide plate maps all eight podium screens")


func test_cameras_in_map_exist_in_studio() -> void:
	var st := StudioSet.new()
	st.build()
	for cam in _map().get("cameras", {}):
		check(st.cameras.has(cam), "mapped camera %s exists" % cam)
	st.free()
