class_name WorldState
extends RefCounted
## The studio complex behind the programme (CP8; CLAUDE.md §10, docs/03 Tier 4).
## Recurring rooms with persistent per-installation state (door, chair, light, figure) that drift
## and revert non-linearly, plus data-driven event chains that advance at most one step per
## broadcast. Nothing here is ever listed, catalogued or explained to players.

const STATE_KEYS := ["door", "chair", "light", "figure"]
const DRIFT := {"door": ["open", "closed", "ajar"], "chair": ["centre", "left", "door", "fallen"], "light": ["on", "off", "flicker"]}

var director
var rooms := {}               # id -> room dict (content)
var chains: Array = []
var state := {}               # room id -> {door, chair, light, figure}
var chain_steps := {}         # chain id -> next step index
var rooms_seen: Array = []
var advanced_this_show := false
var last_shown := {}          # room id -> state snapshot shown this installation (for callbacks)


func _init(p_director) -> void:
	director = p_director
	if director.content != null:
		for r in director.content.query("room", "", 5, 0):
			rooms[str(r.id)] = r
		chains = director.content.query("event_chain", "", 5, 0)


func load_from(installation: Dictionary) -> void:
	state = (installation.get("rooms", {}) as Dictionary).duplicate(true)
	chain_steps = (installation.get("chains", {}) as Dictionary).duplicate(true)
	rooms_seen = (installation.get("rooms_seen", []) as Array).duplicate()
	last_shown = (installation.get("rooms_last_shown", {}) as Dictionary).duplicate(true)
	advanced_this_show = false
	for id in rooms:
		if not state.has(id):
			state[id] = (rooms[id].get("default", {}) as Dictionary).duplicate()


func save_into(installation: Dictionary) -> void:
	installation["rooms"] = state.duplicate(true)
	installation["chains"] = chain_steps.duplicate(true)
	installation["rooms_seen"] = rooms_seen.duplicate()
	installation["rooms_last_shown"] = last_shown.duplicate(true)


## A CCTV cutaway of some room. tier 1 = just a look; tier 2 = maybe something changed since last
## time (or quietly changed back). Returns the presentation payload.
func cctv(tier: int, room_id: String = "") -> Dictionary:
	var ids: Array = rooms.keys()
	if ids.is_empty():
		return {}
	var rng: RandomNumberGenerator = director.rng
	var id := room_id if rooms.has(room_id) else str(ids[rng.randi_range(0, ids.size() - 1)])
	var st: Dictionary = state.get(id, {})
	var change := ""
	if tier >= 2:
		var defaults: Dictionary = rooms[id].get("default", {})
		var drifted := STATE_KEYS.filter(func(k): return st.get(k) != defaults.get(k))
		if not drifted.is_empty() and rng.randf() < 0.35:
			var k: String = drifted[rng.randi_range(0, drifted.size() - 1)]
			st[k] = defaults.get(k)            # non-linear: it's back to normal now
			change = "revert:" + k
		else:
			var keys: Array = DRIFT.keys()
			var k2: String = keys[rng.randi_range(0, keys.size() - 1)]
			var opts: Array = (DRIFT[k2] as Array).filter(func(v): return v != st.get(k2))
			st[k2] = opts[rng.randi_range(0, opts.size() - 1)]
			change = k2 + "=" + str(st[k2])
	state[id] = st
	return _show(id, change)


func _show(id: String, change: String) -> Dictionary:
	if not rooms_seen.has(id):
		rooms_seen.append(id)
	var prev: Dictionary = last_shown.get(id, {})
	var st: Dictionary = (state.get(id, {}) as Dictionary).duplicate()
	last_shown[id] = st.duplicate()
	var r: Dictionary = rooms[id]
	director.log_decision("Room", id, ["state=%s" % str(st), "change=%s" % change, "differs_from_last_seen=%s" % str(not prev.is_empty() and prev != st)])
	return {"room": id, "name": str(r.get("name", "")), "cam": str(r.get("cam", "CAM")), "props": r.get("props", []),
		"door_side": str(r.get("door", "back")), "state": st, "changed": change}


func _requires_ok(c: Dictionary, ctx: Dictionary) -> bool:
	var req: Dictionary = c.get("requires", {})
	for rid in req.get("rooms_seen", []):
		if not rooms_seen.has(rid):
			return false
	if int(director.announcer_stage) < int(req.get("announcer_stage", 0)):
		return false
	if bool(req.get("returning_players", false)) and not bool(ctx.get("returning_players", false)):
		return false
	var sm: Array = req.get("seed_mod", [])
	if sm.size() == 2 and int(ctx.get("installation_seed", 0)) % int(sm[0]) != int(sm[1]):
		return false   # some legends belong to some households only
	return int(director.familiarity_tier) >= int(c.get("min_familiarity", 1))


## Maybe advance one chain step this broadcast. Returns the step payload (with a CCTV view) or {}.
func maybe_advance(ctx: Dictionary) -> Dictionary:
	if advanced_this_show:
		return {}
	var forced := str(director.force.get("chain_step", ""))
	var rng: RandomNumberGenerator = director.rng
	var mode := str(director.interference_mode)
	for c in chains:
		var id := str(c.id)
		var step := int(chain_steps.get(id, 0))
		var steps: Array = c.get("steps", [])
		if step >= steps.size():
			continue
		var tier := int(c.get("tier", 2))
		if forced == id:
			director.force.erase("chain_step")
		else:
			if forced != "" or mode == "clean_transmission" or (mode == "supervised_transmission" and tier >= 2):
				continue
			if not _requires_ok(c, ctx):
				continue
			var chance: float = {2: 0.2, 3: 0.1, 4: 0.5}.get(tier, 0.2)
			if rng.randf() >= chance:
				continue
		var s: Dictionary = steps[step]
		var rid := str(s.get("room", ""))
		var st: Dictionary = state.get(rid, {})
		for k in s.get("set", {}):
			st[k] = s.set[k]
		state[rid] = st
		chain_steps[id] = step + 1
		advanced_this_show = true
		director.log_decision("ChainStep", "%s#%d" % [id, step + 1], ["tier=%d" % tier, "forced" if forced == id else "eligible+roll"])
		var out := _show(rid, "chain:%s" % id)
		out["tier"] = tier
		out["chain"] = id
		out["step"] = step + 1
		if s.has("interfere"):
			out["interfere"] = str(s.interfere)
		if s.has("line"):
			out["line"] = s.line
		return out
	return {}
