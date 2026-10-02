class_name SaveStore
extends RefCounted
## Versioned local persistence for Mildew (docs/09_PERSISTENCE_PROFILES_AND_SAVE.md).
##
## Scopes stored here:
##   * player profiles      -> <dir>/profiles.json
##   * installation memory  -> <dir>/installation.json   (seed, broadcasts, familiarity, settings...)
## Session memory is NOT stored here (it lives in SessionServer and dies with the broadcast).
##
## Every file carries "schema_version". load() migrates older files forward, writing a
## .bak copy first. Unknown fields are preserved (never silently dropped).

const SCHEMA_VERSION := 1
const PROFILE_LIMIT := 64

var base_dir: String
var profiles: Dictionary = {}      # profile_id -> profile dict (player_profile.schema.json)
var installation: Dictionary = {}
var last_migration_log: Array[String] = []


func _init(dir: String = "user://mildew_save") -> void:
	base_dir = dir


func load_all() -> void:
	DirAccess.make_dir_recursive_absolute(base_dir)
	var p := _read(base_dir.path_join("profiles.json"))
	p = _migrate(p, "profiles")
	profiles = {}
	for prof in p.get("profiles", []):
		if typeof(prof) == TYPE_DICTIONARY and prof.has("profile_id"):
			profiles[prof["profile_id"]] = prof
	var inst := _read(base_dir.path_join("installation.json"))
	installation = _migrate(inst, "installation")
	if not installation.has("installation_seed"):
		installation = _new_installation()
		save_installation()


func _new_installation() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return {
		"schema_version": SCHEMA_VERSION,
		# Hidden; never shown in normal UI (dev overlay only).
		"installation_seed": "%08x%08x" % [rng.randi(), rng.randi()],
		"created_unix": int(Time.get_unix_time_from_system()),
		"broadcasts_played": 0,
		"category_familiarity": {},
		"recent_content_history": [],
		"room_states": {},
		"advert_history": {},
		"announcer_stage": 0,
		"incident_flags": {},
		"settings": {"interference": "standard_transmission", "subtitles": true},
	}


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		last_migration_log.append("corrupt file %s ignored (backup kept)" % path)
		_backup(path, "corrupt")
		return {}
	return parsed


func _backup(path: String, tag: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, "%s.%s.bak" % [path, tag])


## Migration chain. Add `_migrate_<kind>_v<N>_to_v<N+1>` functions as the schema evolves.
func _migrate(data: Dictionary, kind: String) -> Dictionary:
	if data.is_empty():
		return data
	var v := int(data.get("schema_version", 0))
	if v > SCHEMA_VERSION:
		# Save from a newer build: do not destroy it. Keep data, operate read-mostly.
		last_migration_log.append("%s schema %d newer than supported %d; preserved as-is" % [kind, v, SCHEMA_VERSION])
		return data
	if v < SCHEMA_VERSION:
		_backup(base_dir.path_join("%s.json" % kind), "v%d" % v)
	while v < SCHEMA_VERSION:
		var fn := "_migrate_%s_v%d_to_v%d" % [kind, v, v + 1]
		if has_method(fn):
			data = call(fn, data)
			last_migration_log.append("%s migrated v%d -> v%d" % [kind, v, v + 1])
		else:
			data["schema_version"] = v + 1
		v += 1
	return data


## v0 = pre-release/unversioned saves (e.g. hand-made test fixtures): add required fields.
func _migrate_profiles_v0_to_v1(data: Dictionary) -> Dictionary:
	var list: Array = data.get("profiles", [])
	for prof in list:
		if typeof(prof) != TYPE_DICTIONARY:
			continue
		if not prof.has("speech_name"):
			prof["speech_name"] = prof.get("display_name", "")
		for k in ["games_played", "wins", "lifetime_rot"]:
			if not prof.has(k):
				prof[k] = 0
		if not prof.has("avatar"):
			prof["avatar"] = {}
		prof["schema_version"] = 1
	data["profiles"] = list
	data["schema_version"] = 1
	return data


func _migrate_installation_v0_to_v1(data: Dictionary) -> Dictionary:
	var fresh := _new_installation()
	for k in fresh.keys():
		if not data.has(k):
			data[k] = fresh[k]
	data["schema_version"] = 1
	return data


func save_profiles() -> void:
	var list := profiles.values()
	list.sort_custom(func(a, b): return int(a.get("last_seen_unix", 0)) > int(b.get("last_seen_unix", 0)))
	if list.size() > PROFILE_LIMIT:
		list = list.slice(0, PROFILE_LIMIT)
	_write(base_dir.path_join("profiles.json"), {"schema_version": SCHEMA_VERSION, "profiles": list})


func save_installation() -> void:
	installation["schema_version"] = SCHEMA_VERSION
	_write(base_dir.path_join("installation.json"), installation)


func _write(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(base_dir)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveStore: cannot write %s" % tmp)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, path)


func create_profile(display_name: String, speech_name: String, avatar: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pid := "prof_%08x%04x" % [rng.randi(), rng.randi() & 0xffff]
	var prof := {
		"schema_version": SCHEMA_VERSION,
		"profile_id": pid,
		"display_name": display_name,
		"speech_name": speech_name,
		"avatar": avatar,
		"games_played": 0,
		"wins": 0,
		"lifetime_rot": 0,
		"memorable_outcomes": [],
		"selected_prizes": [],
		"persistent_titles": [],
		"graham_traces": [],
		"created_unix": int(Time.get_unix_time_from_system()),
		"last_seen_unix": int(Time.get_unix_time_from_system()),
	}
	profiles[pid] = prof
	return prof


func find_profile_by_name(name: String) -> Dictionary:
	var key := normalize_name(name)
	for prof in profiles.values():
		if normalize_name(prof.get("display_name", "")) == key:
			return prof
	return {}


static func normalize_name(name: String) -> String:
	return " ".join(name.strip_edges().to_lower().split(" ", false))


func get_setting(key: String, default_value = null):
	return installation.get("settings", {}).get(key, default_value)


func set_setting(key: String, value) -> void:
	if not installation.has("settings"):
		installation["settings"] = {}
	installation["settings"][key] = value
	save_installation()


# --- Reset scopes (docs/09: real settings operations, require UI confirmation) ---

func reset_players() -> void:
	profiles.clear()
	save_profiles()


func reset_broadcast_history() -> void:
	var keep_settings = installation.get("settings", {})
	var seed = installation.get("installation_seed")
	installation = _new_installation()
	installation["installation_seed"] = seed
	installation["settings"] = keep_settings
	save_installation()


func reset_mildew() -> void:
	profiles.clear()
	save_profiles()
	installation = _new_installation()  # fresh installation seed
	save_installation()
