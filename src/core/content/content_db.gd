class_name ContentDB
extends RefCounted
## Loads all data-driven content packs from res://content (recursively).
## A pack is a JSON object: {pack_id, content_kind, game_id?, speaker?, items:[...]}.
## Content is separate from code (docs/07). Items can be disabled without deletion.

const CONTENT_ROOT := "res://content"

var packs: Array[Dictionary] = []
var items_by_id: Dictionary = {}          # id -> item (with "_pack" back-reference id)
var items_by_kind: Dictionary = {}        # content_kind -> Array[item]
var load_errors: Array[String] = []


static func load_default() -> ContentDB:
	var db := ContentDB.new()
	db.load_dir(CONTENT_ROOT)
	return db


func load_dir(root: String) -> void:
	for path in _list_json(root):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			load_errors.append("cannot open %s" % path)
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			load_errors.append("%s: not a JSON object" % path)
			continue
		parsed["_path"] = path
		add_pack(parsed)


func add_pack(pack: Dictionary) -> void:
	packs.append(pack)
	var kind: String = str(pack.get("content_kind", "unknown"))
	if not items_by_kind.has(kind):
		items_by_kind[kind] = []
	for item in pack.get("items", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		item["_pack"] = pack.get("pack_id", "")
		item["_kind"] = kind
		if pack.has("game_id") and not item.has("game_id"):
			item["game_id"] = pack["game_id"]
		if pack.has("speaker") and not item.has("speaker"):
			item["speaker"] = pack["speaker"]
		items_by_kind[kind].append(item)
		var id := str(item.get("id", ""))
		if id != "" and not items_by_id.has(id):
			items_by_id[id] = item


## Enabled items of a kind, optionally filtered by game, max familiarity tier and player count.
func query(kind: String, game_id: String = "", max_tier: int = 5, player_count: int = 0) -> Array:
	var out: Array = []
	for item in items_by_kind.get(kind, []):
		if not item.get("enabled", false):
			continue
		if game_id != "" and str(item.get("game_id", "")) != game_id:
			continue
		if int(item.get("familiarity_tier", 1)) > max_tier:
			continue
		if player_count > 0:
			if player_count < int(item.get("min_players", 2)) or player_count > int(item.get("max_players", 8)):
				continue
		out.append(item)
	return out


func get_item(id: String) -> Dictionary:
	return items_by_id.get(id, {})


static func _list_json(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := root.path_join(name)
		if dir.current_is_dir():
			out.append_array(_list_json(full))
		elif name.ends_with(".json"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
