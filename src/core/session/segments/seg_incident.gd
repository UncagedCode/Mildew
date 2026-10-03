class_name SegIncident
extends Segment
## A short broadcast irregularity at a segment boundary (Tier 0-3, and chain steps). Presentation only.
var inc: Dictionary

func _init(desc: Dictionary) -> void:
	kind = "incident"
	inc = desc.get("incident", {})
	allows_late_join_after = false

func start() -> void:
	var params: Dictionary = inc.get("params", {}).duplicate()
	if inc.get("effect") == "lower_third_typo":
		var ps: Array = session.active_players_sorted()
		if ps.is_empty():
			duration = 0.1
			return
		var p: PlayerState = ps[session.director.rng.randi_range(0, ps.size() - 1)]
		params["name"] = p.display_name
		params["typo"] = SegIncident.typo(p.display_name, session.director.rng)
		params["number"] = p.number
	var world = session.director.world
	var tier := int(inc.get("tier", 0))
	match str(inc.get("effect")):
		"cctv_cutaway":
			params.merge(world.cctv(tier), true)
		"room_callback":
			var seen: Array = world.rooms_seen
			params.merge(world.cctv(2, str(seen[session.director.rng.randi_range(0, seen.size() - 1)]) if not seen.is_empty() else ""), true)
		"chain_step":
			if params.has("interfere"):
				session.director.force["interfere"] = str(params.interfere)
				session._interference_opportunity("boundary", "")
	emit_incident(session, inc, params)
	var t := 0.35
	var lead := 0.35
	match str(inc.get("effect")):
		"graham_snap":
			lead = 1.6          # the noise, then he stops smiling
		"silent_stare":
			lead = float(inc.get("duration", 8.0)) - 1.5   # nothing happens for a while. Nothing at all.
		"cctv_cutaway", "room_callback", "chain_step":
			lead = float(inc.get("duration", 2.6)) + 0.3   # back in the studio before anybody speaks
	t = lead
	for l in inc.get("lines", []):
		t = say_at(t, str(l[0]), str(l[1])) + 0.2
	# Tonal whiplash: after a sinister beat, straight back to something stupid (docs/03).
	if tier >= 2 and session.director.rng.randf() < 0.6:
		t = say_at(t + 0.4, "graham", "incident_reset") + 0.2
	duration = maxf(float(inc.get("duration", 1.5)), t) + 0.3

static func emit_incident(s, i: Dictionary, params: Dictionary) -> void:
	s.emit_tv({"e": "incident", "id": i.get("id"), "tier": i.get("tier"), "effect": i.get("effect"), "params": params,
		"duration": float(i.get("duration", 1.5)) / maxf(s.time_scale, 0.001)})

## A believable caption-desk mistake: swapped or doubled letters, never a real-world insult.
static func typo(name: String, rng: RandomNumberGenerator) -> String:
	if name.length() < 3:
		return name + name.right(1)
	var i := rng.randi_range(1, name.length() - 2)
	if rng.randf() < 0.5:
		return name.substr(0, i) + name[i + 1] + name[i] + name.substr(i + 2)
	return name.substr(0, i) + name[i] + name.substr(i)
