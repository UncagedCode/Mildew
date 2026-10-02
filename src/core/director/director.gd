class_name Director
extends RefCounted
## The Mildew Director (docs/03_DIRECTOR_SYSTEM.md) — Checkpoint 1 minimal implementation.
##
## Authoritative over pacing/segment planning, content selection, Graham's visible mood and
## hidden relationships, line selection, tone tracking and the hidden axes. Every decision is
## explainable through `decision_log` (dev-only; never shown to players).
##
## Platform-agnostic: pure RefCounted, deterministic given `rng.seed`, no scene-tree access.
## CP1 scope: skeleton planning with unresolved future slots, rehearsal content selection,
## mood + relationship updates from answers/disconnects, line pools with anti-repetition.
## Later checkpoints extend: game tags, incidents, interference, rooms, Announcer progression.

const MOODS := ["relaxed", "pleased", "amused", "irritated", "angry", "embarrassed", "rattled"]
const TONES := ["comedy", "competitive", "gross", "tense", "quiet", "chaotic", "unsettling"]
const RELATIONSHIP_TRAITS := ["favourite", "irritant", "disappointment", "target", "pet_project", "interesting", "pity", "grudge"]
const LOG_LIMIT := 300
const LINE_HISTORY := 14

## Format registry (docs/03 "Game tags"). Unimplemented launch games stay listed so the skeleton
## can show them as future candidates; only `implemented` formats are ever scheduled.
const FORMATS := {
	"hole": {"title": "HOLE", "kind": "game", "implemented": true,
		"tags": ["visual", "trivia", "high-energy", "good-opener", "good-middle", "good-reset", "short", "2-player-safe", "high-content-dependency"]},
	"studio_rehearsal": {"title": "STUDIO REHEARSAL", "kind": "warmup", "implemented": true, "tags": ["trivia", "short"]},
	"guess_the_genitals": {"title": "GUESS THE GENITALS", "kind": "game", "implemented": false, "tags": ["visual", "trivia", "gross", "good-opener", "good-finale"]},
	"real_or_mildew": {"title": "REAL OR MILDEW?", "kind": "game", "implemented": false, "tags": ["trivia", "good-middle", "good-reset"]},
	"mildew_survey": {"title": "MILDEW SURVEY", "kind": "game", "implemented": false, "tags": ["social", "writing", "good-middle"]},
	"mouthfeel": {"title": "MOUTHFEEL", "kind": "game", "implemented": false, "tags": ["writing", "gross", "good-middle", "good-finale"]},
	"police_sketch": {"title": "POLICE SKETCH", "kind": "game", "implemented": false, "tags": ["drawing", "social", "long"]},
	"do_not_press_that": {"title": "DO NOT PRESS THAT", "kind": "game", "implemented": false, "tags": ["cooperation", "chaotic", "tense"]},
	"basement": {"title": "THE BASEMENT", "kind": "game", "implemented": false, "tags": ["deduction", "discussion", "long", "unsettling-capable"]},
}

var rng := RandomNumberGenerator.new()
var content: ContentDB
var cfg: MildewConfig = null       # optional; tuning falls back to defaults without it
var broadcasts_played := 0
var force := {}                    # dev overrides: hole_variant, hole_item, game
var games_this_show: Array = []
var incidents: IncidentEngine

# --- Hidden axes (0..1). Never shown to players. ---
var degradation := 0.0
var complicity := 0.0
var pressure := 0.0
var familiarity_tier := 1          # installation/category content tier currently allowed
var interference_mode := "standard_transmission"
var announcer_stage := 0

# --- Tone: rolling recent density per channel (decays over show time). ---
var tone := {}

# --- Graham: visible emotional state (presentation reads this). ---
var graham_mood := "relaxed"
var _mood_hold := 0.0               # seconds of show time before drifting back toward baseline

# --- Relationships: player_id -> {trait: weight 0..1} ---
var relationships := {}
var player_stats := {}             # player_id -> {answered, correct, wrong_streak, correct_streak, missed_streak, fastest}

var skeleton: Array = []          # planned slots (resolved / unresolved), for debug overlay
var used_content := {}            # content ids used this session
var recent_installation_content: Array = []
var decision_log: Array = []
var show_time := 0.0
var _line_history: Array = []
var _lines_by_category := {}      # speaker:category -> Array[item]


func _init(p_content: ContentDB = null, seed: int = 0) -> void:
	content = p_content
	if seed == 0:
		rng.randomize()
	else:
		rng.seed = seed
	for t in TONES:
		tone[t] = 0.0
	_index_lines()
	incidents = IncidentEngine.new(self)


func _index_lines() -> void:
	_lines_by_category.clear()
	if content == null:
		return
	for kind in ["graham_lines", "announcer_lines"]:
		for item in content.query(kind):
			var key := "%s:%s" % [str(item.get("speaker", "graham")), str(item.get("category", ""))]
			if not _lines_by_category.has(key):
				_lines_by_category[key] = []
			_lines_by_category[key].append(item)


## Called at BEGIN TRANSMISSION / show start with installation memory.
func begin_session(installation: Dictionary, settings_interference: String) -> void:
	interference_mode = settings_interference
	announcer_stage = int(installation.get("announcer_stage", 0))
	var played := int(installation.get("broadcasts_played", 0))
	broadcasts_played = played
	# Familiarity: installation experience gradually allows higher tiers (docs/03 Familiarity).
	familiarity_tier = clampi(1 + played / 3, 1, 5)
	recent_installation_content = installation.get("recent_content_history", []).duplicate()
	log_decision("BeginSession", "familiarity_tier=%d" % familiarity_tier, [
		"broadcasts_played=%d" % played,
		"interference=%s (eligible repertoire, not frequency)" % interference_mode,
		"announcer_stage=%d" % announcer_stage,
		"seed=%d" % rng.seed,
	])


func reset_for_new_show() -> void:
	degradation = rng.randf_range(0.0, 0.08)
	complicity = 0.0
	pressure = rng.randf_range(0.05, 0.15)
	graham_mood = "relaxed"
	_mood_hold = 0.0
	relationships.clear()
	player_stats.clear()
	used_content.clear()
	games_this_show.clear()
	show_time = 0.0
	for t in TONES:
		tone[t] = 0.0
	incidents.reset_for_new_show()


# ---------------------------------------------------------------------------
# Episode planning
# ---------------------------------------------------------------------------

func _cf(path: String, default_value: float) -> float:
	return cfg.f(path, default_value) if cfg != null else default_value


func _ci(path: String, default_value: int) -> int:
	return cfg.i(path, default_value) if cfg != null else default_value


## Builds the partial episode skeleton (docs/03 "Episode planning model"): the opening game is
## resolved now, later slots stay unresolved candidates. CP2: Hole is the only launch game
## implemented, so it is resolved into the opening slot; a short Studio Rehearsal warm-up runs
## only for brand-new installations. Returns the segment descriptors to run.
func plan_episode(player_ids: Array, _legacy_question_count: int = 0) -> Array:
	var n := player_ids.size()
	var opener := choose_game("good-opener", n)
	var warmup := broadcasts_played < _ci("show.warmup_max_broadcasts", 2)
	var future: Array = FORMATS.keys().filter(func(k): return not FORMATS[k].implemented)
	skeleton = [
		{"slot": "opening", "state": "resolved", "content": "opening_titles + welcome + intros"},
		{"slot": "warmup", "state": "resolved" if warmup else "skipped", "content": "studio_rehearsal" if warmup else "(returning installation)"},
		{"slot": "game_1", "state": "resolved", "content": opener},
		{"slot": "interstitial", "state": "unresolved", "content": "(adverts arrive CP8)"},
		{"slot": "game_2", "state": "unresolved", "content": "candidates: %s (not yet implemented)" % ", ".join(future.slice(0, 3))},
		{"slot": "midpoint_break", "state": "unresolved", "content": "(CP8)"},
		{"slot": "finale", "state": "unresolved", "content": "(CP8; ~1.5x scoring)"},
		{"slot": "awards_credits", "state": "resolved", "content": "scores + sign-off"},
	]
	var plan: Array = []
	plan.append({"kind": "opening"})
	plan.append({"kind": "link", "lines": [["announcer", "sponsor"], ["graham", "show_open"], ["graham", "show_open_2"]], "camera": "cam1"})
	plan.append({"kind": "intros"})
	if warmup:
		var qs := pick_items("multiple_choice", "studio_rehearsal", _ci("show.warmup_questions", 2), n)
		log_decision("Warmup", "studio_rehearsal", ["broadcasts_played=%d < %d" % [broadcasts_played, _ci("show.warmup_max_broadcasts", 2)], "questions=%s" % str(qs.map(func(q): return q.get("id")))])
		plan.append({"kind": "sting", "game_id": "studio_rehearsal", "title": "STUDIO REHEARSAL"})
		plan.append({"kind": "link", "lines": [["graham", "rehearsal_intro"]], "camera": "cam1"})
		for i in qs.size():
			plan.append({"kind": "question", "item": qs[i], "game_id": "studio_rehearsal", "mid_game": i > 0})
	plan.append_array(plan_game(opener, n))
	plan.append({"kind": "scores", "final": true})
	plan.append({"kind": "sign_off"})
	return plan


## Picks an implemented game for a slot role tag (good-opener / good-middle / good-finale),
## avoiding games already used this show. Logged with reasons (docs/03 "Director logging").
func choose_game(role_tag: String, player_count: int) -> String:
	if force.has("game") and FORMATS.has(force.game) and FORMATS[force.game].implemented:
		log_decision("SelectGame", force.game, ["forced by developer"])
		return str(force.game)
	var cands: Array = []
	for k in FORMATS.keys():
		var f: Dictionary = FORMATS[k]
		if f.kind != "game" or not f.implemented or games_this_show.has(k):
			continue
		cands.append(k)
	if cands.is_empty():
		cands = ["hole"]
	cands.sort_custom(func(a, b): return int(FORMATS[a].tags.has(role_tag)) > int(FORMATS[b].tags.has(role_tag)))
	var pick: String = cands[0]
	games_this_show.append(pick)
	log_decision("SelectGame", pick, [
		"role=%s tags=%s" % [role_tag, ",".join(FORMATS[pick].tags)],
		"player_count=%d (2-player-safe=%s)" % [player_count, FORMATS[pick].tags.has("2-player-safe")],
		"implemented candidates=%s" % str(cands),
		"recent games excluded=%s" % str(games_this_show.slice(0, games_this_show.size() - 1)),
	])
	return pick


## Expands a game into its segments (sting, rules link, rounds, outro).
func plan_game(game_id: String, player_count: int) -> Array:
	var out: Array = []
	match game_id:
		"hole":
			var rounds := _ci("hole.rounds_per_game", 6)
			var items := pick_hole_items(rounds, player_count)
			var variants := choose_hole_variants(items)
			out.append({"kind": "sting", "game_id": "hole", "title": "HOLE!", "style": "hole", "seconds": 4.2})
			out.append({"kind": "link", "lines": [["graham", "hole_intro"], ["graham", "hole_rules"]], "camera": "cam1"})
			for i in items.size():
				out.append({"kind": "hole_round", "item": items[i], "game_id": "hole", "variant": variants[i],
					"round": i + 1, "of": items.size(), "mid_game": i > 0})
			out.append({"kind": "link", "lines": [["graham", "hole_outro"]], "camera": "cam1", "mid_game": false})
	return out


## Hole content: weighted, no repeats within the session, installation-recent items avoided,
## at most N studio-world holes per game.
func pick_hole_items(count: int, player_count: int) -> Array:
	var chosen := pick_items("hole", "hole", count, player_count, _ci("hole.max_studio_holes_per_game", 1))
	if force.has("hole_item"):
		var forced: Dictionary = content.get_item(str(force.hole_item)) if content else {}
		if not forced.is_empty() and not chosen.has(forced):
			chosen[mini(1, chosen.size() - 1)] = forced
			used_content[str(forced.get("id"))] = true
			log_decision("ForceContent", str(forced.get("id")), ["forced by developer"])
	return chosen


func choose_hole_variants(items: Array) -> Array:
	var variants: Array = []
	for i in items.size():
		variants.append("standard")
	if items.size() < 3:
		return variants
	var forced := str(force.get("hole_variant", ""))
	# Developer force (dev panel / tour): the very first eligible round, so it can be watched now.
	if forced in ["scale", "open"]:
		for i in items.size():
			if not items[i].get("studio_hole", false):
				variants[i] = forced
				log_decision("Variant", "hole:%s@%d" % [forced, i + 1], ["forced by developer"])
				return variants
	# One SCALE round in the middle of the game, preferring items whose size is surprising.
	if forced == "scale" or (forced == "" and rng.randf() < _cf("hole.scale_round_chance", 0.6)):
		var best := -1
		for i in range(2, items.size() - 1):
			if items[i].get("studio_hole", false):
				continue
			if best == -1 or (str(items[i].get("scale")) != "centimetres" and str(items[best].get("scale")) == "centimetres"):
				best = i
		if best >= 0:
			variants[best] = "scale"
			log_decision("Variant", "hole:scale@%d" % (best + 1), ["item=%s scale=%s" % [items[best].get("id"), items[best].get("scale")]])
	# ADVANCED OPEN GUESS: no safety net, only for seasoned installations (docs/04 Hole variants).
	if forced == "open" or (forced == "" and familiarity_tier >= _ci("hole.open_round_min_familiarity", 4) and rng.randf() < _cf("hole.open_round_chance", 0.5)):
		for i in range(items.size() - 1, 0, -1):
			if variants[i] == "standard" and not items[i].get("studio_hole", false):
				variants[i] = "open"
				log_decision("Variant", "hole:open@%d" % (i + 1), ["familiarity_tier=%d" % familiarity_tier])
				break
	return variants


## Generic content selection with repetition control: never repeat within a session; avoid
## installation-recent items; weighted by item "weight"; deliberate repeats only when exhausted.
func pick_items(kind: String, game_id: String, count: int, player_count: int, max_studio: int = 99) -> Array:
	var pool := content.query(kind, game_id, familiarity_tier, player_count) if content else []
	var fresh: Array = []
	var stale: Array = []
	for item in pool:
		var id := str(item.get("id"))
		if used_content.has(id):
			continue
		if recent_installation_content.has(id):
			stale.append(item)
		else:
			fresh.append(item)
	_weighted_shuffle(fresh)
	_weighted_shuffle(stale)
	var ordered := fresh + stale
	var chosen: Array = []
	var studio := 0
	for item in ordered:
		if chosen.size() >= count:
			break
		if item.get("studio_hole", false):
			if studio >= max_studio:
				continue
			studio += 1
		chosen.append(item)
	if chosen.size() > fresh.size():
		log_decision("ContentRepeat", game_id, ["fresh pool exhausted (%d fresh); reusing installation-recent items" % fresh.size()])
	for item in chosen:
		used_content[str(item.get("id"))] = true
	log_decision("SelectContent", game_id, ["picked=%s" % str(chosen.map(func(q): return q.get("id"))),
		"pool=%d fresh=%d tier<=%d" % [pool.size(), fresh.size(), familiarity_tier]])
	return chosen


## Back-compat (CP1 tests): rehearsal question picking.
func pick_questions(game_id: String, count: int, player_count: int) -> Array:
	return pick_items("multiple_choice", game_id, count, player_count)


## Efraimidis-Spirakis weighted random order (weight from item.weight, default 1).
func _weighted_shuffle(arr: Array) -> void:
	var keyed: Array = []
	for it in arr:
		var w := maxf(0.0001, float(it.get("weight", 1.0)))
		keyed.append([pow(rng.randf(), 1.0 / w), it])
	keyed.sort_custom(func(a, b): return a[0] > b[0])
	arr.clear()
	for k in keyed:
		arr.append(k[1])


func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _shuffle(arr: Array) -> void:
	shuffle(arr)


# ---------------------------------------------------------------------------
# Lines
# ---------------------------------------------------------------------------

## Picks a line for speaker/category given context {name, speech_name, secs, answer, count}.
## Returns {} when no line exists. Result: {id, speaker, text, speech, mood, silent}.
func line(speaker: String, category: String, ctx: Dictionary = {}) -> Dictionary:
	var key := "%s:%s" % [speaker, category]
	var pool: Array = _lines_by_category.get(key, [])
	var eligible: Array = []
	for item in pool:
		var moods: Array = item.get("moods", [])
		if speaker == "graham" and not moods.is_empty() and not moods.has(graham_mood):
			continue
		if speaker == "announcer" and int(item.get("stage", 0)) > announcer_stage:
			continue
		eligible.append(item)
	if eligible.is_empty():
		return {}
	var fresh := eligible.filter(func(it): return not _line_history.has(it.get("id")))
	var choice_pool := fresh if not fresh.is_empty() else eligible
	var total := 0.0
	for it in choice_pool:
		total += float(it.get("weight", 1.0))
	var roll := rng.randf() * total
	var picked: Dictionary = choice_pool[0]
	for it in choice_pool:
		roll -= float(it.get("weight", 1.0))
		if roll <= 0.0:
			picked = it
			break
	_line_history.append(picked.get("id"))
	if _line_history.size() > LINE_HISTORY:
		_line_history.pop_front()
	var text := _fill(str(picked.get("text", "")), ctx, false)
	var speech := _fill(str(picked.get("text", "")), ctx, true)
	return {
		"id": picked.get("id"),
		"speaker": speaker,
		"category": category,
		"text": text,
		"speech": speech,
		"mood": graham_mood,
		"pid": str(ctx.get("pid", "")),
		"silent": bool(picked.get("silent", false)),
		"audio": picked.get("audio", null),
	}


func _fill(text: String, ctx: Dictionary, speech: bool) -> String:
	var name := str(ctx.get("speech_name" if speech else "name", ctx.get("name", "")))
	var answer := str(ctx.get("answer", ""))
	return text.replace("{name}", name).replace("{secs}", str(ctx.get("secs", ""))) \
		.replace("{answer}", answer).replace("{count}", str(ctx.get("count", ""))) \
		.replace("{points}", str(ctx.get("points", ""))).replace("{other}", str(ctx.get("other_name", "")))


# ---------------------------------------------------------------------------
# Reactions / state updates
# ---------------------------------------------------------------------------

func set_mood(mood: String, hold_seconds: float, reason: String) -> void:
	if not MOODS.has(mood):
		return
	if mood != graham_mood:
		log_decision("GrahamMood", mood, ["from=%s" % graham_mood, reason, "hold=%.0fs" % hold_seconds])
	graham_mood = mood
	_mood_hold = hold_seconds


func rel(pid: String) -> Dictionary:
	if not relationships.has(pid):
		var r := {}
		for t in RELATIONSHIP_TRAITS:
			r[t] = 0.0
		relationships[pid] = r
	return relationships[pid]


func stats(pid: String) -> Dictionary:
	if not player_stats.has(pid):
		player_stats[pid] = {"answered": 0, "correct": 0, "wrong_streak": 0, "correct_streak": 0, "missed_streak": 0, "fastest": 999.0, "afk_called": false}
	return player_stats[pid]


func _bump(pid: String, trait_name: String, amount: float) -> void:
	var r := rel(pid)
	r[trait_name] = clampf(float(r[trait_name]) + amount, 0.0, 1.0)


## results: Array of {pid, answered, correct, elapsed, points}. Returns the reaction plan:
## {category, ctx, extra:[{category, ctx}], tone_delta}
func on_question_result(results: Array, answer_window: float) -> Dictionary:
	var correct: Array = results.filter(func(r): return r.correct)
	var answered: Array = results.filter(func(r): return r.answered)
	for r in results:
		var s := stats(r.pid)
		if r.answered:
			s.answered += 1
			s.missed_streak = 0
		else:
			s.missed_streak += 1
		if r.correct:
			s.correct += 1
			s.correct_streak += 1
			s.wrong_streak = 0
			s.fastest = minf(s.fastest, r.elapsed)
			_bump(r.pid, "favourite", 0.04)
			if r.elapsed < answer_window * 0.15:
				_bump(r.pid, "interesting", 0.06)
		elif r.answered:
			s.wrong_streak += 1
			s.correct_streak = 0
			_bump(r.pid, "disappointment", 0.05 * s.wrong_streak)
		else:
			_bump(r.pid, "irritant", 0.05)
	var plan := {"category": "", "ctx": {}, "extra": []}
	var reasons: Array = ["answered=%d/%d" % [answered.size(), results.size()], "correct=%d" % correct.size()]
	if answered.is_empty():
		plan.category = "nobody_answered"
		set_mood("irritated", 40.0, "nobody answered")
		pressure = clampf(pressure + 0.05, 0, 1)
	elif correct.size() == results.size():
		plan.category = "all_correct"
		if rng.randf() < 0.6:
			set_mood("pleased", 30.0, "everyone correct")
		_tone("competitive", 0.15)
	elif correct.is_empty():
		plan.category = "all_wrong"
		set_mood("irritated" if rng.randf() < 0.5 else "amused", 30.0, "nobody correct")
		_tone("comedy", 0.25)
	elif correct.size() == 1:
		plan.category = "single_correct"
		plan.ctx = {"pid": correct[0].pid}
		_tone("competitive", 0.2)
	else:
		plan.category = "some_correct"
		_tone("competitive", 0.1)
	# Fast-correct call-out (docs/04 Graham hooks): only sometimes, so it stays special.
	if not correct.is_empty():
		var fastest = correct[0]
		for r in correct:
			if r.elapsed < fastest.elapsed:
				fastest = r
		if fastest.elapsed < minf(2.5, answer_window * 0.2) and rng.randf() < 0.7:
			plan.extra.append({"category": "fast_correct", "ctx": {"pid": fastest.pid, "secs": "%.1f" % fastest.elapsed}})
			reasons.append("fast_correct %s %.2fs" % [fastest.pid, fastest.elapsed])
	# AFK notice (once per player per show).
	for r in results:
		var s := stats(r.pid)
		if s.missed_streak >= 2 and not s.afk_called:
			s.afk_called = true
			plan.extra.append({"category": "afk_player", "ctx": {"pid": r.pid}})
			reasons.append("afk %s" % r.pid)
			break
	degradation = clampf(degradation + rng.randf_range(0.0, 0.02), 0, 1)
	log_decision("QuestionReaction", plan.category, reasons)
	return plan


## Hole round outcome -> Graham reaction plan + relationship/tone updates.
## results: [{pid, answered(locked), correct, partial, stage, points}]
func on_hole_result(results: Array, item: Dictionary, variant: String) -> Dictionary:
	var correct: Array = results.filter(func(r): return r.correct)
	var locked: Array = results.filter(func(r): return r.answered)
	var reasons: Array = ["locked=%d/%d" % [locked.size(), results.size()], "correct=%d" % correct.size(), "variant=%s" % variant]
	for r in results:
		var s := stats(r.pid)
		if r.answered:
			s.answered += 1
			s.missed_streak = 0
		else:
			s.missed_streak += 1
		if r.correct:
			s.correct += 1
			s.correct_streak += 1
			s.wrong_streak = 0
			_bump(r.pid, "favourite", 0.03 + 0.03 * (4 - mini(int(r.stage), 4)) / 3.0)
			if int(r.stage) == 1:
				_bump(r.pid, "interesting", 0.08)
		elif r.answered:
			s.wrong_streak += 1
			s.correct_streak = 0
			if int(r.stage) == 1 and not r.get("partial", false):
				_bump(r.pid, "target", 0.05)   # confidently wrong from a glimpse: Graham remembers
			_bump(r.pid, "disappointment", 0.04 * s.wrong_streak)
		else:
			_bump(r.pid, "irritant", 0.05)
	var plan := {"category": "", "ctx": {}, "extra": []}
	if item.get("studio_hole", false):
		set_mood("rattled", 25.0, "studio hole revealed")
		pressure = clampf(pressure + 0.06, 0, 1)
		degradation = clampf(degradation + 0.03, 0, 1)
		_tone("unsettling", 0.2)
		log_decision("HoleReaction", "studio_hole", reasons)
		return plan  # no commentary: never explain it, just move on
	if locked.is_empty():
		plan.category = "hole_nobody_locked"
		set_mood("irritated", 30.0, "nobody locked in")
	elif correct.is_empty():
		plan.category = "hole_nobody_right"
		plan.ctx = {"answer": str(item.get("answer", ""))}
		set_mood("amused" if rng.randf() < 0.6 else "irritated", 25.0, "nobody right")
		_tone("comedy", 0.25)
	elif correct.size() == results.size() and results.size() > 1:
		plan.category = "hole_all_correct"
		_tone("competitive", 0.1)
	elif correct.size() == 1 and results.size() > 2:
		plan.category = "hole_single_correct"
		plan.ctx = {"pid": correct[0].pid}
		_tone("competitive", 0.2)
	# Extras: first-glance genius, confident early failure, partial credit (max two).
	var glance: Array = correct.filter(func(r): return int(r.stage) == 1)
	if not glance.is_empty() and rng.randf() < 0.8:
		plan.extra.append({"category": "hole_first_glance", "ctx": {"pid": glance[0].pid}})
		reasons.append("first_glance %s" % glance[0].pid)
	var early_wrong: Array = results.filter(func(r): return r.answered and not r.correct and not r.get("partial", false) and int(r.stage) == 1)
	if not early_wrong.is_empty() and plan.extra.size() < 2 and rng.randf() < 0.6:
		plan.extra.append({"category": "hole_early_wrong", "ctx": {"pid": early_wrong[0].pid}})
		reasons.append("early_wrong %s" % early_wrong[0].pid)
	var partial: Array = results.filter(func(r): return r.get("partial", false))
	if not partial.is_empty() and plan.extra.size() < 2 and rng.randf() < 0.5:
		plan.extra.append({"category": "hole_partial", "ctx": {"pid": partial[0].pid}})
	for r in results:
		var s := stats(r.pid)
		if s.missed_streak >= 2 and not s.afk_called and plan.extra.size() < 2:
			s.afk_called = true
			plan.extra.append({"category": "afk_player", "ctx": {"pid": r.pid}})
			reasons.append("afk %s" % r.pid)
			break
	_tone("gross", 0.05 * float(_grossness(item)))
	degradation = clampf(degradation + rng.randf_range(0.0, 0.015), 0, 1)
	log_decision("HoleReaction", plan.category if plan.category != "" else "(reveal line only)", reasons)
	return plan


static func _grossness(item: Dictionary) -> int:
	for t in item.get("content_tags", []):
		if str(t).begins_with("grossness_"):
			return int(str(t).substr(10))
	return 0


func on_player_lost(pid: String) -> void:
	pressure = clampf(pressure + 0.08, 0, 1)
	_tone("tense", 0.1)
	log_decision("PlayerLost", pid, ["pressure=%.2f" % pressure])


func on_player_failed_return(pid: String) -> void:
	_bump(pid, "grudge", 0.15)
	set_mood("irritated", 45.0, "%s did not return" % pid)


func on_all_gone() -> void:
	set_mood("angry", 999.0, "every contestant left")


func on_player_returned(pid: String) -> void:
	pressure = clampf(pressure - 0.04, 0, 1)
	log_decision("PlayerReturned", pid, ["pressure=%.2f" % pressure])


func tick(dt: float) -> void:
	show_time += dt
	for t in TONES:
		tone[t] = maxf(0.0, float(tone[t]) - dt * 0.004)
	pressure = maxf(0.0, pressure - dt * 0.0008)
	if _mood_hold > 0.0:
		_mood_hold -= dt
		if _mood_hold <= 0.0 and graham_mood != "relaxed" and graham_mood != "angry":
			set_mood("relaxed", 0.0, "mood hold expired")


func _tone(channel: String, amount: float) -> void:
	tone[channel] = clampf(float(tone[channel]) + amount, 0.0, 1.0)


## Standings-based relationship nudges at the end of a game (resent dominant winner, pity last).
func on_scores(standings: Array) -> void:
	if standings.size() < 2:
		return
	var top = standings[0]
	var last = standings[standings.size() - 1]
	if int(top.score) > 0 and int(top.score) >= 2 * max(1, int(standings[1].score)):
		_bump(top.pid, "irritant", 0.05)
	_bump(last.pid, "pity", 0.05)


func log_decision(kind: String, choice: String, reasons: Array) -> void:
	var entry := {"t": snappedf(show_time, 0.01), "kind": kind, "choice": choice, "reasons": reasons}
	decision_log.append(entry)
	if decision_log.size() > LOG_LIMIT:
		decision_log.pop_front()


func snapshot() -> Dictionary:
	return {
		"degradation": degradation,
		"complicity": complicity,
		"pressure": pressure,
		"familiarity_tier": familiarity_tier,
		"interference_mode": interference_mode,
		"announcer_stage": announcer_stage,
		"graham_mood": graham_mood,
		"tone": tone.duplicate(),
		"relationships": relationships.duplicate(true),
		"skeleton": skeleton.duplicate(true),
		"used_content": used_content.keys(),
		"incidents": {"temperament": incidents.temperament, "count": incidents.count_by_tier.duplicate(), "log": incidents.fired_log.duplicate()},
		"show_time": show_time,
	}
