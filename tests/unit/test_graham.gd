extends MildewTest
## Composited Graham (D021/D022): the semantic state map is complete and safe. Director/presenter
## code only ever asks for semantic states; every one must resolve to a real frame without cycles.


func _presenter_cut() -> GrahamPresenter:
	var g := GrahamPresenter.new()
	g.cut = GrahamPresenter._read_json(GrahamPresenter.CUT_MAP)
	g.mode = "cut"
	return g


func test_cutout_map_frames_exist() -> void:
	var cut := GrahamPresenter._read_json(GrahamPresenter.CUT_MAP)
	check(not cut.is_empty(), "graham_cutouts.json present")
	var frames: Dictionary = cut.get("frames", {})
	for k in frames:
		check(ResourceLoader.exists(str(frames[k])), "frame %s imported (%s)" % [k, frames[k]])
	for s in cut.get("states", {}):
		var e: Dictionary = cut.states[s]
		check(frames.has(str(e.frame)), "state %s frame exists" % s)
		for b in e.get("blink", []):
			check(frames.has(str(b)), "state %s blink frame %s exists" % [s, b])
		for v in e.get("variants", []):
			check(frames.has(str(v)), "state %s variant %s exists" % [s, v])
		check(["none", "quiet", "standard"].has(str(e.get("camera_motion", "quiet"))), "state %s camera_motion valid" % s)
	for t in cut.get("talk_cycle", []):
		check(frames.has(str(t)), "talk cycle frame %s exists" % t)
	check((cut.get("talk_cycle", []) as Array).size() >= 4, "enough mouth shapes to avoid a two-frame flap")
	check(cut.states.has("neutral"), "neutral exists (ultimate fallback)")


func test_every_semantic_state_resolves_without_cycles() -> void:
	var g := _presenter_cut()
	for s in g.all_states():
		var chain: Array = g.fallback_chain(s)
		check(chain.size() <= 6, "fallback chain for %s is short: %s" % [s, chain])
		var seen := {}
		for c in chain:
			check(not seen.has(c), "no cycle in fallback chain for %s: %s" % [s, chain])
			seen[c] = true
		check(g.has_state(g.resolve(s)), "%s resolves to an available state (%s)" % [s, g.resolve(s)])
	for m in GrahamPresenter.MOOD_STATE.values():
		check(g.has_state(g.resolve(m)), "mood state %s resolves" % m)
	check_eq(g.resolve("totally_unknown_state"), "neutral", "unknown states fall back to neutral, never error")
	g.free()


func test_shot_hints_reference_known_states() -> void:
	var g := _presenter_cut()
	var shots := GrahamPresenter._read_json("res://config/graham_shots.json")
	check(not shots.is_empty(), "graham_shots.json present")
	for cat in shots:
		if str(cat).begins_with("_"):
			continue
		var h: Dictionary = shots[cat]
		for key in ["lead", "settle"]:
			var s := str(h.get(key, ""))
			if s != "":
				check(g.has_state(g.resolve(s)) and (g.all_states().has(s)), "shot %s.%s = %s is a known state" % [cat, key, s])
		for c in h.get("cutaway", []):
			check(["cam1", "cam2", "cam3", "cam4", "subject", "corridor", "floor"].has(str(c)), "shot %s cutaway %s is a known camera" % [cat, c])
	g.free()
