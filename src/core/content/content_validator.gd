class_name ContentValidator
extends RefCounted
## Content validation (docs/07 "Content validators"). Returns errors (block) and warnings.
## Run headless: godot --headless --script res://tests/run_tests.gd -- --suite content
## Release mode additionally blocks placeholder factual content and unapproved factual media.

const TAGS_PATH := "res://config/content_tags.json"

var errors: Array[String] = []
var warnings: Array[String] = []
var _tags: Dictionary = {}


func validate(db: ContentDB, release_mode: bool = false) -> bool:
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
	# Unbalanced braces indicate a broken insertion slot.
	if text.count("{") != text.count("}"):
		errors.append("%s: unbalanced insertion slot braces" % where)
