class_name ContentValidator
extends RefCounted
## Content validation (docs/07 "Content validators"). Returns errors (block) and warnings.
## Run headless: godot --headless --script res://tests/run_tests.gd -- --suite content
## Release mode additionally blocks placeholder factual content and unapproved factual media.

const TAGS_PATH := "res://config/content_tags.json"

var errors: Array[String] = []
var warnings: Array[String] = []
var _tags: Dictionary = {}


var _release := false


func validate(db: ContentDB, release_mode: bool = false) -> bool:
	_release = release_mode
	errors.clear()
	warnings.clear()
	_tags = MildewConfig._read_json(TAGS_PATH)
	var quality_states: Array = _tags.get("quality_states", [])
	var known_content_tags: Array = _tags.get("content_tags", [])
	var known_director_tags: Array = _tags.get("director_tags", [])
	var moods: Array = _tags.get("graham_moods", [])
	for e in db.load_errors:
		errors.append(e)

	var seen_ids := {}
	var seen_packs := {}
	for pack in db.packs:
		var ppath := str(pack.get("_path", "?"))
		var pid := str(pack.get("pack_id", ""))
		if pid == "":
			errors.append("%s: missing pack_id" % ppath)
		elif seen_packs.has(pid):
			errors.append("%s: duplicate pack_id %s" % [ppath, pid])
		seen_packs[pid] = true
		var kind := str(pack.get("content_kind", ""))
		if kind == "":
			errors.append("%s: missing content_kind" % ppath)
		if typeof(pack.get("items")) != TYPE_ARRAY:
			errors.append("%s: items must be an array" % ppath)
			continue
		for item in pack["items"]:
			if typeof(item) != TYPE_DICTIONARY:
				errors.append("%s: non-object item" % ppath)
				continue
			var id := str(item.get("id", ""))
			var where := "%s[%s]" % [ppath.get_file(), id]
			if id == "":
				errors.append("%s: item missing id" % ppath)
			elif seen_ids.has(id):
				errors.append("%s: duplicate id (also in %s)" % [where, seen_ids[id]])
			seen_ids[id] = ppath.get_file()
			if typeof(item.get("enabled")) != TYPE_BOOL:
				errors.append("%s: enabled must be boolean" % where)
			var qs = item.get("quality_status")
			if not quality_states.has(qs):
				errors.append("%s: unsupported quality_status %s" % [where, str(qs)])
			for tag in item.get("content_tags", []):
				if not known_content_tags.has(tag):
					errors.append("%s: unknown content tag '%s'" % [where, tag])
			for tag in item.get("director_tags", []):
				if not known_director_tags.has(tag):
					errors.append("%s: unknown director tag '%s'" % [where, tag])
			match kind:
				"multiple_choice":
					_validate_multiple_choice(item, where, release_mode)
				"hole":
					_validate_hole(item, where, release_mode)
				"incident":
					_validate_incident(item, where)
				"real_or_mildew":
					_validate_real_or_mildew(item, where, release_mode)
				"guess_the_genitals":
					_validate_gtg(item, where, release_mode)
				"mildew_survey":
					_validate_survey(item, where)
				"interference":
					_validate_interference(item, where)
				"basement":
					_validate_basement(item, where)
				"do_not_press_that":
					_validate_common_game(item, where)
					if str(item.get("title", "")) == "" or (item.get("labels", []) as Array).size() < 6:
						errors.append("%s: puzzle needs a title and 6+ control labels" % where)
					if not ["lamps", "gauge", "card"].has(str(item.get("display", ""))) or not ["switch", "dial", "button"].has(str(item.get("controls", ""))):
						errors.append("%s: unknown display/control kind" % where)
					var rng := RandomNumberGenerator.new()
					for n in range(2, 9):
						rng.seed = hash("%s/%d" % [item.get("id"), n])
						var errs := DnpPuzzle.generate(item, n, rng).validate()
						if not errs.is_empty():
							errors.append("%s: unsatisfiable layout for %d players: %s" % [where, n, errs[0]])
				"police_sketch":
					_validate_common_game(item, where)
					if str(item.get("prompt", "")).strip_edges() == "" or str(item.get("prompt", "")).length() > 140:
						errors.append("%s: sketch prompt missing or too long" % where)
					if not ["standard", "body_part"].has(str(item.get("variant", "standard"))):
						errors.append("%s: unknown sketch variant '%s'" % [where, str(item.get("variant"))])
				"mouthfeel":
					_validate_mouthfeel(item, where, release_mode)
				"graham_lines", "announcer_lines":
					_validate_line(item, where, moods)
				_:
					warnings.append("%s: no validator for content_kind '%s'" % [where, kind])
	return errors.is_empty()


func _validate_common_game(item: Dictionary, where: String) -> void:
	var tier = item.get("familiarity_tier")
	if typeof(tier) not in [TYPE_INT, TYPE_FLOAT] or int(tier) < 1 or int(tier) > 5:
		errors.append("%s: invalid familiarity_tier %s" % [where, str(tier)])
	var mn = item.get("min_players", null)
	var mx = item.get("max_players", null)
	if typeof(mn) not in [TYPE_INT, TYPE_FLOAT] or typeof(mx) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s: min_players/max_players required" % where)
	elif int(mn) < 2 or int(mx) > 8 or int(mn) > int(mx):
		errors.append("%s: malformed player-count constraint %s..%s" % [where, mn, mx])
	if typeof(item.get("content_tags")) != TYPE_ARRAY:
		errors.append("%s: content_tags array required" % where)


func _validate_multiple_choice(item: Dictionary, where: String, release_mode: bool) -> void:
	_validate_common_game(item, where)
	if str(item.get("prompt", "")).strip_edges() == "":
		errors.append("%s: missing prompt" % where)
	var options = item.get("options")
	if typeof(options) != TYPE_ARRAY or options.size() < 2 or options.size() > 4:
		errors.append("%s: options must have 2-4 entries" % where)
		return
	for o in options:
		if typeof(o) != TYPE_STRING or o.strip_edges() == "":
			errors.append("%s: empty option text" % where)
	var correct = item.get("correct")
	if typeof(correct) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s: missing correct answer" % where)
	elif int(correct) < 0 or int(correct) >= options.size():
		errors.append("%s: correct index %s out of range (answer count mismatch)" % [where, str(correct)])
	var lowered := {}
	for o in options:
		var k := str(o).strip_edges().to_lower()
		if lowered.has(k):
			errors.append("%s: duplicate option '%s'" % [where, o])
		lowered[k] = true
	_validate_factual(item, where, release_mode)


const ROM_ROUNDS := ["which_real", "one_mildew", "all_real"]
const ROM_CATEGORIES := ["medicine", "biology", "history", "food", "inventions", "advertising", "scientific_oddities", "historical_customs", "disasters", "strange_objects"]


## Real or Mildew? (docs/04 §4): always factual -> sources required; round shape must be consistent.
func _validate_real_or_mildew(item: Dictionary, where: String, release_mode: bool) -> void:
	var it := item.duplicate()
	it["factual"] = true
	_validate_multiple_choice(it, where, release_mode)
	var rnd := str(item.get("round", ""))
	if not ROM_ROUNDS.has(rnd):
		errors.append("%s: invalid round '%s'" % [where, rnd])
	if not ROM_CATEGORIES.has(str(item.get("category", ""))):
		errors.append("%s: unknown Real or Mildew category '%s'" % [where, str(item.get("category", ""))])
	if str(item.get("fact", "")).strip_edges() == "":
		errors.append("%s: missing factual explanation" % where)
	var opts: Array = item.get("options", [])
	if rnd == "all_real" and int(item.get("correct", -1)) != opts.size() - 1:
		errors.append("%s: all_real round must have the 'all real' option last and correct" % where)
	for o in opts:
		if str(o).length() > 120:
			errors.append("%s: option longer than 120 characters (unreadable on TV)" % where)


## Private interference (docs/03): ephemeral phone payloads; source is internal only.
func _validate_interference(item: Dictionary, where: String) -> void:
	var tier = item.get("tier")
	if typeof(tier) not in [TYPE_INT, TYPE_FLOAT] or int(tier) < 1 or int(tier) > 4:
		errors.append("%s: invalid interference tier %s" % [where, str(tier)])
	if not PrivateInterference.SOURCES.has(item.get("source")):
		errors.append("%s: unknown interference source '%s'" % [where, str(item.get("source"))])
	if not PrivateInterference.STYLES.has(item.get("style")):
		errors.append("%s: unknown interference style '%s'" % [where, str(item.get("style"))])
	var target := str(item.get("target", ""))
	if not PrivateInterference.TARGETS.has(target):
		errors.append("%s: unknown interference target '%s'" % [where, target])
	for m in item.get("moments", []):
		if not PrivateInterference.MOMENTS.has(m):
			errors.append("%s: unknown interference moment '%s'" % [where, m])
	if target == "fragments":
		if (item.get("fragments", []) as Array).size() < 2:
			errors.append("%s: distributed interference needs 2+ fragments" % where)
	elif str(item.get("style")) != "buzz" and (item.get("texts", []) as Array).is_empty():
		errors.append("%s: interference needs texts" % where)
	var ms := int(item.get("ms", 0))
	if ms < 200 or ms > 4000:
		errors.append("%s: ms must be 200..4000 (brief, never lingering)" % where)
	for t in item.get("texts", []) + item.get("fragments", []):
		if str(t).length() > 48:
			errors.append("%s: interference text too long to flash: %s" % [where, t])
		var low := str(t).to_lower()
		for bad in ["incoming call", "accept", "decline", "slide to answer"]:
			if low.contains(bad):
				errors.append("%s: must not imitate the phone's own call UI ('%s')" % [where, bad])


## The Basement (docs/04 §7): structure + every player count 2–8 deals a valid hand.
const BASEMENT_KINDS := ["key", "support", "red_herring", "unreliable"]


func _validate_basement(item: Dictionary, where: String) -> void:
	_validate_common_game(item, where)
	for f in ["title", "setup", "reveal"]:
		if str(item.get(f, "")).strip_edges() == "":
			errors.append("%s: case missing %s" % [where, f])
	var ev: Array = item.get("evidence", [])
	if ev.size() < 8:
		errors.append("%s: needs 8+ evidence cards for 8 players" % where)
	var qids: Array = (item.get("questions", []) as Array).map(func(q): return str(q.get("id", "")))
	for e in ev:
		if not BASEMENT_KINDS.has(str(e.get("kind", ""))):
			errors.append("%s: evidence %s has unknown kind" % [where, e.get("id")])
		for s in e.get("supports", []):
			if not qids.has(s):
				errors.append("%s: evidence %s supports unknown question %s" % [where, e.get("id"), s])
	for q in item.get("questions", []):
		var opts: Array = q.get("options", [])
		var cr: Array = q.get("credit", [])
		if opts.size() < 2 or opts.size() != cr.size():
			errors.append("%s: question %s options/credit mismatch" % [where, q.get("id")])
		elif cr.max() <= 0.0:
			errors.append("%s: question %s has no creditable answer" % [where, q.get("id")])
	if (item.get("investigations", []) as Array).is_empty():
		errors.append("%s: no optional investigations" % where)
	var rng := RandomNumberGenerator.new()
	for n in range(2, 9):
		for s in 5:
			rng.seed = hash("%s/%d/%d" % [item.get("id"), n, s])
			var errs := BasementCase.deal(item, n, rng).validate()
			if not errs.is_empty():
				errors.append("%s: invalid deal for %d players: %s" % [where, n, errs[0]])
				return


## Mildew Survey (docs/04 §3): a prompt, enough archive filler for a 2-player vote, known round formats.
const SURVEY_MODES := ["popularity", "archive", "who_said"]


func _validate_survey(item: Dictionary, where: String) -> void:
	_validate_common_game(item, where)
	var p := str(item.get("prompt", "")).strip_edges()
	if p == "":
		errors.append("%s: missing prompt" % where)
	elif p.length() > 110:
		errors.append("%s: prompt longer than 110 characters (unreadable on TV)" % where)
	_validate_answer_list(item.get("archive", []), 3, where, "archive")
	var modes = item.get("modes", SURVEY_MODES)
	if typeof(modes) != TYPE_ARRAY or (modes as Array).is_empty():
		errors.append("%s: modes must be a non-empty array" % where)
	else:
		for m in modes:
			if not SURVEY_MODES.has(m):
				errors.append("%s: unknown survey mode '%s'" % [where, str(m)])


func _validate_answer_list(arr, need: int, where: String, field: String) -> void:
	if typeof(arr) != TYPE_ARRAY or (arr as Array).size() < need:
		errors.append("%s: %s needs at least %d answers (two-player votes)" % [where, field, need])
		return
	for a in arr:
		if str(a).strip_edges() == "" or str(a).length() > SegWriteVote.MAX_TEXT:
			errors.append("%s: %s answer empty or longer than %d characters" % [where, field, SegWriteVote.MAX_TEXT])


## Mouthfeel (docs/04 §8): describe (write + vote), chain (Make It Worse), reverse (multiple choice).
const MOUTHFEEL_FORMATS := ["describe", "chain", "reverse"]


func _validate_mouthfeel(item: Dictionary, where: String, release_mode: bool) -> void:
	var fmt := str(item.get("format", ""))
	if not MOUTHFEEL_FORMATS.has(fmt):
		errors.append("%s: unknown Mouthfeel format '%s'" % [where, fmt])
		return
	match fmt:
		"describe":
			_validate_common_game(item, where)
			if str(item.get("prompt", "")).strip_edges() == "":
				errors.append("%s: missing prompt" % where)
			_validate_answer_list(item.get("archive", []), 2, where, "archive")
			_validate_answer_list(item.get("graham_answers", []), 1, where, "graham_answers")
		"chain":
			_validate_common_game(item, where)
			if str(item.get("base", "")).strip_edges() == "":
				errors.append("%s: chain item needs a base" % where)
			if int(item.get("min_players", 2)) < 3:
				errors.append("%s: Make It Worse needs min_players >= 3" % where)
		"reverse":
			_validate_multiple_choice(item, where, release_mode)
			if str(item.get("description", "")).strip_edges() == "":
				errors.append("%s: reverse item needs Graham's description" % where)


const GTG_FORBIDDEN_TAGS := ["human", "people", "sexual_activity", "explicit"]


## Guess the Genitals (docs/04 §1, docs/13): ANIMAL ONLY, clinical; every item needs a species,
## a sourced biological fact and licensed media. Human anatomy is rejected outright.
func _validate_gtg(item: Dictionary, where: String, release_mode: bool) -> void:
	var it := item.duplicate()
	it["factual"] = true
	_validate_multiple_choice(it, where, release_mode)
	var tags: Array = item.get("content_tags", [])
	for t in GTG_FORBIDDEN_TAGS:
		if tags.has(t):
			errors.append("%s: forbidden tag '%s' (animal-only content rule)" % [where, t])
	var taxon := str(item.get("taxon", "")).strip_edges()
	if taxon == "":
		errors.append("%s: missing taxon (animal-only enforcement needs a species or group)" % where)
	elif taxon.to_lower().contains("homo sapiens") or taxon.to_lower() == "human":
		errors.append("%s: human anatomy is not allowed in Guess the Genitals" % where)
	if not ["animal", "decoy"].has(str(item.get("kingdom_class", ""))):
		errors.append("%s: kingdom_class must be 'animal' or 'decoy'" % where)
	if str(item.get("kingdom_class", "")) == "decoy" and not bool(item.get("decoy", false)):
		errors.append("%s: decoy class but decoy flag not set" % where)
	if str(item.get("fact", "")).strip_edges() == "":
		errors.append("%s: missing biological fact" % where)
	var img := str(item.get("image", ""))
	if img == "":
		errors.append("%s: missing image" % where)
	elif not ResourceLoader.exists(img) and not FileAccess.file_exists(img):
		errors.append("%s: missing referenced asset %s" % [where, img])
	else:
		_validate_media(item, where, release_mode)


func _validate_hole(item: Dictionary, where: String, release_mode: bool) -> void:
	_validate_common_game(item, where)
	var cats: Array = _tags.get("hole_categories", [])
	var scales: Array = _tags.get("hole_scales", [])
	var img := str(item.get("image", ""))
	if img == "":
		errors.append("%s: hole item missing image" % where)
	elif not ResourceLoader.exists(img) and not FileAccess.file_exists(img):
		errors.append("%s: missing referenced asset %s" % [where, img])
	var answer := str(item.get("answer", "")).strip_edges()
	if answer == "":
		errors.append("%s: missing correct answer" % where)
	if not cats.has(item.get("category")):
		errors.append("%s: unknown hole category '%s'" % [where, str(item.get("category"))])
	if not scales.has(item.get("scale")):
		errors.append("%s: invalid scale '%s'" % [where, str(item.get("scale"))])
	var labels: Array = []
	var cands = item.get("candidates")
	if typeof(cands) != TYPE_ARRAY or cands.size() < 4 or cands.size() > 10:
		errors.append("%s: candidates must have 4-10 entries" % where)
	else:
		for c in cands:
			if typeof(c) != TYPE_DICTIONARY or str(c.get("label", "")).strip_edges() == "":
				errors.append("%s: candidate missing label" % where)
				continue
			var lab := str(c.label)
			if labels.has(lab):
				errors.append("%s: duplicate candidate '%s'" % [where, lab])
			labels.append(lab)
			if not cats.has(c.get("category")):
				errors.append("%s: candidate '%s' has unknown category '%s'" % [where, lab, str(c.get("category"))])
			elif lab == answer and str(c.category) != str(item.get("category")):
				errors.append("%s: answer candidate category differs from item category" % where)
		if answer != "" and not labels.has(answer):
			errors.append("%s: answer '%s' is not among the candidates" % [where, answer])
	var net = item.get("safety_net")
	if typeof(net) != TYPE_ARRAY or net.size() != 4:
		errors.append("%s: safety_net must have exactly 4 options" % where)
	else:
		var seen := {}
		for o in net:
			if seen.has(o):
				errors.append("%s: duplicate safety_net option '%s'" % [where, o])
			seen[o] = true
			if not labels.has(o):
				errors.append("%s: safety_net option '%s' is not a candidate" % [where, o])
		if not net.has(answer):
			errors.append("%s: safety_net does not contain the answer" % where)
	var stages = item.get("stages")
	if typeof(stages) != TYPE_ARRAY or stages.size() != 3:
		errors.append("%s: stages must define 3 reveal crops" % where)
	else:
		var prev_zoom := 1.0e9
		for st in stages:
			if typeof(st) != TYPE_DICTIONARY:
				errors.append("%s: malformed stage" % where)
				continue
			var z := float(st.get("zoom", 0))
			var sx := float(st.get("x", -1))
			var sy := float(st.get("y", -1))
			if z < 1.0 or sx < 0.0 or sx > 1.0 or sy < 0.0 or sy > 1.0:
				errors.append("%s: stage crop out of range %s" % [where, str(st)])
			if z >= prev_zoom:
				errors.append("%s: each reveal stage must be wider than the last" % where)
			prev_zoom = z
	if typeof(item.get("weight", 1.0)) not in [TYPE_INT, TYPE_FLOAT] or float(item.get("weight", 1.0)) <= 0.0:
		errors.append("%s: weight must be a positive number" % where)
	var rl := str(item.get("reveal_line", ""))
	if rl.count("{") != rl.count("}"):
		errors.append("%s: unbalanced insertion slot braces" % where)
	_validate_media(item, where, release_mode)
	_validate_factual(item, where, release_mode)


## Every shipped image needs provenance/licence metadata, factual or not (docs/07).
func _validate_incident(item: Dictionary, where: String) -> void:
	var targets := ["tv_video", "tv_audio", "single_phone", "multiple_phones", "all_phones", "graham", "announcer", "audience", "scoreboard", "room", "game_injection", "mixed"]
	var tier = item.get("tier")
	if typeof(tier) not in [TYPE_INT, TYPE_FLOAT] or int(tier) < 0 or int(tier) > 4:
		errors.append("%s: invalid incident tier %s" % [where, str(tier)])
	if not targets.has(item.get("target")):
		errors.append("%s: invalid incident target %s" % [where, str(item.get("target"))])
	if float(item.get("rarity_weight", -1)) < 0.0:
		errors.append("%s: rarity_weight must be >= 0" % where)
	if float(item.get("cooldown_seconds", -1)) < 0.0:
		errors.append("%s: cooldown_seconds must be >= 0" % where)
	var moments: Array = item.get("moments", [])
	if moments.is_empty():
		errors.append("%s: incident has no moments" % where)
	for m in moments:
		if not IncidentEngine.MOMENTS.has(m):
			errors.append("%s: unknown incident moment '%s'" % [where, m])
	var payload: Dictionary = item.get("payload", {})
	if not IncidentEngine.EFFECTS.has(payload.get("effect")):
		errors.append("%s: unknown incident effect '%s'" % [where, str(payload.get("effect"))])
	for fu in item.get("follow_up_pool", []):
		if str(fu) == str(item.get("id")):
			errors.append("%s: incident lists itself as a follow-up (circular)" % where)


func _validate_media(item: Dictionary, where: String, release_mode: bool) -> void:
	var media = item.get("media", [])
	if typeof(media) != TYPE_ARRAY or media.is_empty():
		errors.append("%s: image without media/licence metadata" % where)
		return
	for m in media:
		for k in ["asset_path", "source", "licence", "approval_status"]:
			if typeof(m) != TYPE_DICTIONARY or str(m.get(k, "")).strip_edges() == "":
				errors.append("%s: media missing '%s' (licence metadata)" % [where, k])
		if typeof(m) == TYPE_DICTIONARY and release_mode and str(m.get("approval_status")) != "approved":
			errors.append("%s: media not approved for release" % where)


func _validate_factual(item: Dictionary, where: String, release_mode: bool) -> void:
	var factual: bool = item.get("factual", false) or (item.get("content_tags", []) as Array).has("factual")
	if not factual:
		return
	var sources = item.get("sources", [])
	var qs := str(item.get("quality_status"))
	if typeof(sources) != TYPE_ARRAY or sources.is_empty():
		if qs in ["reviewed", "approved"] or release_mode:
			errors.append("%s: factual item missing source metadata" % where)
		else:
			warnings.append("%s: factual item has no sources yet (%s)" % [where, qs])
	else:
		for s in sources:
			for k in ["title", "publisher_or_organisation", "reference", "supported_claim"]:
				if typeof(s) != TYPE_DICTIONARY or str(s.get(k, "")).strip_edges() == "":
					errors.append("%s: source missing '%s'" % [where, k])
	for m in item.get("media", []):
		for k in ["asset_path", "source", "licence", "approval_status"]:
			if typeof(m) != TYPE_DICTIONARY or str(m.get(k, "")).strip_edges() == "":
				errors.append("%s: factual media missing '%s' (licence metadata)" % [where, k])
		if typeof(m) == TYPE_DICTIONARY:
			var ap := str(m.get("asset_path", ""))
			if ap != "" and not ResourceLoader.exists(ap) and not FileAccess.file_exists(ap):
				errors.append("%s: missing referenced asset %s" % [where, ap])
			if release_mode and str(m.get("approval_status")) != "approved":
				errors.append("%s: factual media not approved for release" % where)
	if release_mode and qs == "placeholder":
		errors.append("%s: placeholder factual content blocked in release mode" % where)


func _validate_line(item: Dictionary, where: String, moods: Array) -> void:
	if str(item.get("text", "")).strip_edges() == "":
		errors.append("%s: empty line text" % where)
	if str(item.get("category", "")) == "":
		errors.append("%s: missing category" % where)
	for m in item.get("moods", []):
		if not moods.has(m):
			errors.append("%s: unknown mood '%s'" % [where, m])
	var text := str(item.get("text", ""))
	# Authored Graham audio (D024): ids must exist, and the subtitle must be exactly what was recorded.
	if item.has("audio"):
		var vidx := GrahamVoiceIndex.shared()
		var ids := GrahamVoiceIndex.line_ids(item.get("audio"))
		var recorded: Array = []
		for id in ids:
			if not vidx.has_id(id):
				errors.append("%s: unknown Graham voice id '%s'" % [where, id])
			else:
				recorded.append(vidx.text(id))
				if _release and vidx.status(id) != "approved":
					warnings.append("%s: voice clip '%s' is %s, not approved for release" % [where, id, vidx.status(id)])
		if recorded.size() == ids.size() and not ids.is_empty() and " ".join(recorded) != text:
			errors.append("%s: subtitle text differs from the recorded voice text \"%s\"" % [where, " ".join(recorded)])
	# Unbalanced braces indicate a broken insertion slot.
	if text.count("{") != text.count("}"):
		errors.append("%s: unbalanced insertion slot braces" % where)
