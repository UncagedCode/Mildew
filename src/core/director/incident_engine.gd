class_name IncidentEngine
extends RefCounted
## Broadcast irregularities (docs/03 "Incident tiers", docs/02 wrong-camera/audio grammar).
## CP2 scope: Tier 0 (normal production mess) and light Tier 1 (odd). Data-driven from
## content_kind "incident" (schemas/incident.schema.json).
##
## Principles enforced here:
##  * maximum repertoire != maximum frequency: low base rates, per-tier + per-incident cooldowns;
##  * some sessions are unusually clean (per-session temperament roll);
##  * horror-saturation safeguard (no Tier 1 while recent unsettling density is high);
##  * comedy-saturation safeguard (a long clean stretch raises the chance of a cheap reminder);
##  * the player setting changes eligibility: SUPERVISED damps Tier 1, CLEAN suppresses Tier 1+
##    and keeps only mild production mess;
##  * incidents are presentation only: they never touch scores, timers or real connection status.

const MOMENTS := ["boundary", "hole_round_start", "hole_stage", "hole_reveal"]
const EFFECTS := ["mic_pop", "feedback", "lower_third_typo", "early_applause", "late_cut", "wrong_camera",
	"off_mic_cue", "signal_tear", "empty_corridor", "hole_doorway", "wrong_name", "production_caption",
	"wrong_audience_reaction", "floor_shot"]

var director  # Director (untyped: avoids a cyclic class reference)
var items: Array = []
var temperament := 1.0            # per-session multiplier (0.25 = unusually clean)
var last_fired := {}              # id -> show_time
var last_tier := {}               # tier -> show_time
var last_any := -1.0e9
var fired_log: Array = []         # [{t, id, tier, moment}] (dev only; never shown to players)
var count_by_tier := {0: 0, 1: 0}


func _init(p_director) -> void:
	director = p_director
	if director.content != null:
		items = director.content.query("incident", "", 5, 0)


func reset_for_new_show() -> void:
	last_fired.clear()
	last_tier.clear()
	last_any = -1.0e9
	fired_log.clear()
	count_by_tier = {0: 0, 1: 0}
	# Temperament: most sessions normal, a few unusually clean, a few a bit busier.
	var r: float = director.rng.randf()
	temperament = 0.25 if r < 0.15 else (1.35 if r > 0.85 else 1.0)
	director.log_decision("IncidentTemperament", "%.2f" % temperament, ["roll=%.2f" % r, "mode=%s" % director.interference_mode])


func _mode_multiplier(tier: int, item: Dictionary) -> float:
	match str(director.interference_mode):
		"clean_transmission":
			if tier >= 1:
				return 0.0
			return 0.5 if item.get("clean_safe", false) else 0.0
		"supervised_transmission":
			return 1.0 if tier == 0 else 0.35
	return 1.0


## Called at hook points. Returns {} or an incident dict {id, tier, effect, params, lines}.
func opportunity(moment: String, ctx: Dictionary = {}) -> Dictionary:
	var now: float = director.show_time
	var forced := str(director.force.get("incident", ""))
	if forced != "":
		for it in items:
			if str(it.id) == forced and (it.get("moments", []) as Array).has(moment) and _game_ok(it, ctx):
				director.force.erase("incident")
				director.log_decision("Incident", forced, ["forced by developer", "moment=%s" % moment])
				return _fire(it, moment, ctx, now)
	var base := {0: 0.05, 1: 0.008}
	var tier_cd := {0: 40.0, 1: 240.0}
	var quiet_for := now - last_any
	# Comedy-saturation safeguard: a long completely normal stretch invites a cheap reminder.
	var reminder := clampf((quiet_for - 200.0) / 200.0, 0.0, 1.0)
	var unsettling: float = float(director.tone.get("unsettling", 0.0))
	var candidates: Array = []
	var weights: Array = []
	for it in items:
		var tier := int(it.get("tier", 0))
		if tier > 1:
			continue  # CP2: Tier 2+ machinery not yet enabled
		if not (it.get("moments", []) as Array).has(moment) or not _game_ok(it, ctx):
			continue
		var pc := int(ctx.get("players", 2))
		if pc < int(it.get("min_players", 2)) or pc > int(it.get("max_players", 8)):
			continue
		if int(it.get("minimum_familiarity", 1)) > int(director.familiarity_tier):
			continue
		if now - float(last_fired.get(str(it.id), -1.0e9)) < float(it.get("cooldown_seconds", 300.0)):
			continue
		if now - float(last_tier.get(tier, -1.0e9)) < float(tier_cd.get(tier, 120.0)):
			continue
		if tier >= 1 and unsettling > 0.5:
			continue  # horror-saturation safeguard
		if it.has("needs") and not _needs_ok(it.needs, ctx):
			continue
		var w := float(it.get("rarity_weight", 1.0)) * _mode_multiplier(tier, it)
		if w <= 0.0:
			continue
		candidates.append(it)
		weights.append(w)
	if candidates.is_empty():
		return {}
	# Roll once per tier present, Tier 1 first (rarer), then Tier 0.
	for tier in [1, 0]:
		var idx: Array = []
		for i in candidates.size():
			if int(candidates[i].get("tier", 0)) == tier:
				idx.append(i)
		if idx.is_empty():
			continue
		var chance: float = base[tier] * temperament * (1.0 + reminder * (1.5 if tier == 0 else 1.0))
		chance *= float(ctx.get("chance_scale", 1.0))
		if director.rng.randf() >= chance:
			continue
		var total := 0.0
		for i in idx:
			total += weights[i]
		var roll: float = director.rng.randf() * total
		for i in idx:
			roll -= weights[i]
			if roll <= 0.0:
				var it: Dictionary = candidates[i]
				director.log_decision("Incident", str(it.id), ["tier=%d moment=%s" % [tier, moment], "chance=%.3f temperament=%.2f" % [chance, temperament],
					"quiet_for=%.0fs reminder=%.2f unsettling=%.2f" % [quiet_for, reminder, unsettling]])
				return _fire(it, moment, ctx, now)
	return {}


func _game_ok(it: Dictionary, ctx: Dictionary) -> bool:
	var g := str(ctx.get("game", ""))
	var allowed: Array = it.get("allowed_games", [])
	if not allowed.is_empty() and not allowed.has(g):
		return false
	var forbidden: Array = it.get("forbidden_games", [])
	return not forbidden.has(g)


func _needs_ok(needs: Array, ctx: Dictionary) -> bool:
	for n in needs:
		if not ctx.has(n) or (typeof(ctx[n]) == TYPE_STRING and ctx[n] == ""):
			return false
	return true


func _fire(it: Dictionary, moment: String, ctx: Dictionary, now: float) -> Dictionary:
	var tier := int(it.get("tier", 0))
	last_fired[str(it.id)] = now
	last_tier[tier] = now
	last_any = now
	count_by_tier[tier] = int(count_by_tier.get(tier, 0)) + 1
	fired_log.append({"t": snappedf(now, 0.1), "id": it.id, "tier": tier, "moment": moment})
	if tier >= 1:
		director._tone("unsettling", 0.08)
		director.degradation = clampf(director.degradation + 0.02, 0, 1)
	else:
		director._tone("comedy", 0.05)
	var payload: Dictionary = it.get("payload", {})
	var params: Dictionary = payload.duplicate(true)
	params.erase("effect")
	params.erase("lines")
	if payload.has("captions"):
		var caps: Array = payload.captions
		params["caption"] = caps[director.rng.randi_range(0, caps.size() - 1)]
	return {"id": it.id, "tier": tier, "effect": str(payload.get("effect", "")), "params": params,
		"lines": payload.get("lines", []), "duration": float(payload.get("duration", 1.5)), "moment": moment}
