class_name PrivateInterference
extends RefCounted
## Private controller interference (docs/03 "Private interference engine", CLAUDE.md §9).
## Brief messages/vibrations sent to ONE or SOME phones only — never recoverable in a history,
## never persisted, never shown on the TV, never touching scores, timers, input or real network
## status. Data-driven from content_kind "interference".
##
## Frequency philosophy: STANDARD TRANSMISSION makes every payload *eligible*; it does not make them
## frequent. Low per-moment hazard, per-item + global cooldowns, a per-session temperament (some
## sessions get almost nothing), a cap per show, and the horror-saturation safeguard.
##
## Each payload carries an internal source (production / announcer / graham / unknown /
## unknown_impersonating_source / corruption / archive) for logging and future logic only.
## Players are never told the source.

const MOMENTS := ["question_open", "write_open", "vote_open", "hole_stage", "boundary"]
const SOURCES := ["production", "announcer", "graham", "unknown", "unknown_impersonating_source", "corruption", "archive"]
const STYLES := ["overlay", "field", "unit", "buzz"]
const TARGETS := ["single_phone", "multiple_phones", "all_phones", "fragments"]
## Vibration that is *reminiscent of* a ringing phone — never an imitation of the OS call UI.
const RING := [400, 200, 400, 1400, 400, 200, 400]

var director
var items: Array = []
var temperament := 1.0
var last_fired := {}
var last_any := -1.0e9
var fired := 0
var fired_log: Array = []      # dev only


func _init(p_director) -> void:
	director = p_director
	if director.content != null:
		items = director.content.query("interference", "", 5, 0)


func reset_for_new_show() -> void:
	last_fired.clear()
	last_any = -1.0e9
	fired = 0
	fired_log.clear()
	var r: float = director.rng.randf()
	# ~30% of sessions are nearly silent; most normal; a few livelier.
	temperament = 0.15 if r < 0.3 else (1.6 if r > 0.9 else 1.0)
	director.log_decision("InterferenceTemperament", "%.2f" % temperament, ["roll=%.2f" % r, "mode=%s" % director.interference_mode])


## ctx: {players: [{pid, name}], game}. Returns [] or [{pid, msg}] deliveries.
func opportunity(moment: String, ctx: Dictionary) -> Array:
	var mode := str(director.interference_mode)
	if mode == "clean_transmission":
		director.force.erase("interfere")
		return []
	var players: Array = ctx.get("players", [])
	if players.is_empty():
		return []
	var now: float = director.show_time
	var forced := str(director.force.get("interfere", ""))
	if forced != "":
		for it in items:
			if str(it.id) == forced and (it.get("moments", MOMENTS) as Array).has(moment):
				director.force.erase("interfere")
				director.log_decision("Interference", forced, ["forced by developer", "moment=%s" % moment])
				return _fire(it, moment, players, now)
		return []
	var cap := int(director.cfg.i("interference.max_per_show", 6)) if director.cfg else 6
	if fired >= cap:
		return []
	if now - last_any < (float(director.cfg.f("interference.global_cooldown_seconds", 150.0)) if director.cfg else 150.0):
		return []
	if float(director.tone.get("unsettling", 0.0)) > 0.45:
		return []   # horror-saturation safeguard
	var cands: Array = []
	var weights: Array = []
	for it in items:
		var tier := int(it.get("tier", 1))
		if not (it.get("moments", MOMENTS) as Array).has(moment):
			continue
		if mode == "supervised_transmission" and (tier >= 2 or not ["production", "archive"].has(str(it.get("source", "")))):
			continue
		if int(it.get("minimum_familiarity", 1)) > int(director.familiarity_tier):
			continue
		if players.size() < int(it.get("min_players", 1)):
			continue
		if now - float(last_fired.get(str(it.id), -1.0e9)) < float(it.get("cooldown_seconds", 900.0)):
			continue
		if tier >= 3 and float(director.tone.get("unsettling", 0.0)) > 0.2:
			continue
		var w := float(it.get("rarity_weight", 1.0))
		if w <= 0.0:
			continue
		cands.append(it)
		weights.append(w)
	if cands.is_empty():
		return []
	var base := float(director.cfg.f("interference.base_chance", 0.035)) if director.cfg else 0.035
	var chance := base * temperament * (0.35 if mode == "supervised_transmission" else 1.0) * float(ctx.get("chance_scale", 1.0))
	if director.rng.randf() >= chance:
		return []
	var total := 0.0
	for w in weights:
		total += w
	var roll: float = director.rng.randf() * total
	for i in cands.size():
		roll -= weights[i]
		if roll <= 0.0:
			director.log_decision("Interference", str(cands[i].id), ["moment=%s chance=%.3f temperament=%.2f" % [moment, chance, temperament],
				"source=%s (never shown)" % cands[i].get("source", "unknown")])
			return _fire(cands[i], moment, players, now)
	return []


func _fire(it: Dictionary, moment: String, players: Array, now: float) -> Array:
	last_fired[str(it.id)] = now
	last_any = now
	fired += 1
	var tier := int(it.get("tier", 1))
	if tier >= 2:
		director._tone("unsettling", 0.1 * tier)
		director.degradation = clampf(director.degradation + 0.03, 0, 1)
	var rng: RandomNumberGenerator = director.rng
	var order: Array = players.duplicate()
	director.shuffle(order)
	var style := str(it.get("style", "overlay"))
	var ms := int(it.get("ms", 1300))
	var out: Array = []
	var target := str(it.get("target", "single_phone"))
	var texts: Array = it.get("texts", [])
	match target:
		"fragments":
			# Distributed: complementary/conflicting fragments to different phones; some get nothing.
			var frags: Array = it.get("fragments", [])
			for i in mini(frags.size(), order.size()):
				if frags[i] != "":
					out.append({"pid": order[i].pid, "msg": _msg(str(frags[i]), style, ms, it, order, i)})
		"all_phones":
			var t := _pick(texts, rng)
			for i in order.size():
				out.append({"pid": order[i].pid, "msg": _msg(t, style, ms, it, order, i)})
		"multiple_phones":
			var n := clampi(rng.randi_range(2, 3), 1, order.size())
			for i in n:
				out.append({"pid": order[i].pid, "msg": _msg(_pick(texts, rng), style, ms, it, order, i)})
		_:
			out.append({"pid": order[0].pid, "msg": _msg(_pick(texts, rng), style, ms, it, order, 0)})
	fired_log.append({"t": snappedf(now, 0.1), "id": it.id, "moment": moment, "to": out.map(func(o): return o.pid)})
	return out


func _pick(arr: Array, rng: RandomNumberGenerator) -> String:
	return "" if arr.is_empty() else str(arr[rng.randi_range(0, arr.size() - 1)])


## {other} = another contestant's name (never the recipient's own).
func _msg(text: String, style: String, ms: int, it: Dictionary, order: Array, i: int) -> Dictionary:
	var other := ""
	if order.size() > 1:
		other = str(order[(i + 1) % order.size()].name).to_upper()
	text = text.replace("{other}", other)
	var m := {"t": Protocol.S_INTERFERE, "style": style, "text": text, "ms": ms}
	match str(it.get("buzz", "")):
		"ring":
			m["buzz"] = RING
		"short":
			m["buzz"] = [60]
		"double":
			m["buzz"] = [80, 120, 80]
	if it.has("after"):
		m["after"] = str(it.after)   # "message changes on touch" (extremely rare)
	return m
