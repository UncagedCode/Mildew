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

var rng := RandomNumberGenerator.new()
var content: ContentDB

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
	show_time = 0.0
	for t in TONES:
		tone[t] = 0.0


# ---------------------------------------------------------------------------
# Episode planning
# ---------------------------------------------------------------------------

## Builds the partial episode skeleton. CP1: only the Studio Rehearsal format exists, so the
## Director resolves the opening slot to it and records the remaining standard-broadcast slots
## as unresolved (they become live as games land in CP2+).
func plan_episode(player_ids: Array, question_count: int) -> Array:
	var n := player_ids.size()
	skeleton = [
		{"slot": "opening", "state": "resolved", "content": "opening_titles + welcome + intros"},
		{"slot": "game_1", "state": "resolved", "content": "studio_rehearsal"},
		{"slot": "interstitial", "state": "unresolved", "content": "(adverts arrive CP8)"},
		{"slot": "game_2", "state": "unresolved", "content": "(no further formats implemented at CP1)"},
		{"slot": "midpoint_break", "state": "unresolved", "content": "(CP8)"},
		{"slot": "finale", "state": "unresolved", "content": "(CP8; ~1.5x scoring)"},
		{"slot": "awards_credits", "state": "resolved", "content": "scores + sign-off (CP1 minimal)"},
	]
	var questions := pick_questions("studio_rehearsal", question_count, n)
	log_decision("SelectGame", "studio_rehearsal", [
		"only implemented format at CP1",
		"tags: trivia, short, good-opener, 2-player-safe",
		"player_count=%d compatible (2..8)" % n,
		"questions=%s" % str(questions.map(func(q): return q.get("id"))),
	])
	var plan: Array = []
	plan.append({"kind": "opening"})
	plan.append({"kind": "link", "lines": [["announcer", "sponsor"], ["graham", "show_open"], ["graham", "show_open_2"]], "camera": "cam1"})
	plan.append({"kind": "intros"})
	plan.append({"kind": "sting", "game_id": "studio_rehearsal", "title": "STUDIO REHEARSAL"})
	plan.append({"kind": "link", "lines": [["graham", "rehearsal_intro"]], "camera": "cam1"})
	for q in questions:
		plan.append({"kind": "question", "item": q, "game_id": "studio_rehearsal"})
	plan.append({"kind": "scores", "final": true})
	plan.append({"kind": "sign_off"})
	return plan


## Content selection with repetition control: avoid items used this session, then items in
## recent installation history; deliberately allow repeats only when the library is exhausted.
func pick_questions(game_id: String, count: int, player_count: int) -> Array:
	var pool := content.query("multiple_choice", game_id, familiarity_tier, player_count) if content else []
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
	_shuffle(fresh)
	_shuffle(stale)
	var chosen := fresh.slice(0, count)
	if chosen.size() < count:
		chosen.append_array(stale.slice(0, count - chosen.size()))
		log_decision("ContentRepeat", game_id, ["fresh pool exhausted (%d fresh); reusing installation-recent items" % fresh.size()])
	for item in chosen:
		used_content[str(item.get("id"))] = true
	return chosen


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


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
		"silent": bool(picked.get("silent", false)),
		"audio": picked.get("audio", null),
	}


func _fill(text: String, ctx: Dictionary, speech: bool) -> String:
	var name := str(ctx.get("speech_name" if speech else "name", ctx.get("name", "")))
	var answer := str(ctx.get("answer", ""))
	return text.replace("{name}", name).replace("{secs}", str(ctx.get("secs", ""))) \
		.replace("{answer}", answer).replace("{count}", str(ctx.get("count", ""))) \
		.replace("{points}", str(ctx.get("points", "")))


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
		"show_time": show_time,
	}
