class_name GrahamVoiceIndex
extends RefCounted
## Graham's local authored-voice index (tools/graham_factory/CLAUDE_INTEGRATION.md, D024).
## Pure data: semantic dialogue id -> local asset path + status, and player name -> name id.
## Rebuilt by tools/graham_factory/sync_godot.py; gameplay code never changes when clips are added.
## No network, no cloud speech: this only ever points at files shipped inside the game.

const DEFAULT_PATH := "res://config/graham_voice_index.json"
const STATUSES := ["missing", "development", "approved"]

var clips := {}      # id -> {path, status, text, mood}
var names := {}      # normalised name -> id
var source := ""

static var _shared: GrahamVoiceIndex = null


static func shared() -> GrahamVoiceIndex:
	if _shared == null:
		_shared = load_from(DEFAULT_PATH)
	return _shared


static func set_shared(idx: GrahamVoiceIndex) -> void:
	_shared = idx


static func load_from(path: String) -> GrahamVoiceIndex:
	var idx := GrahamVoiceIndex.new()
	idx.source = path
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			idx.set_data(d)
	return idx


func set_data(d: Dictionary) -> void:
	clips = d.get("clips", {}).duplicate(true)
	names.clear()
	for k in d.get("names", {}):
		names[normalise_name(str(k))] = str(d.names[k])


## "  AARON! " -> "aaron". Only letters (any script), digits, spaces, apostrophes and hyphens survive.
static func normalise_name(name: String) -> String:
	var out := ""
	for ch in name.strip_edges().to_lower():
		if ch == " " or ch == "'" or ch == "-" or ch.to_upper() != ch.to_lower() or (ch >= "0" and ch <= "9"):
			out += ch
	return out.strip_edges()


func has_id(id: String) -> bool:
	return clips.has(id)


func path(id: String) -> String:
	return str(clips.get(id, {}).get("path", ""))


func status(id: String) -> String:
	return str(clips.get(id, {}).get("status", "missing")) if clips.has(id) else "unknown"


func text(id: String) -> String:
	return str(clips.get(id, {}).get("text", ""))


## True when a local file is actually present for this id (development or approved).
func has_clip(id: String) -> bool:
	var p := path(id)
	return p != "" and status(id) != "missing" and ResourceLoader.exists(p)


func name_id(name: String) -> String:
	return str(names.get(normalise_name(name), ""))


func has_name(name: String) -> bool:
	var id := name_id(name)
	return id != "" and has_clip(id)


## Names Graham can actually say right now (for the phone wizard).
func spoken_names() -> Array:
	var out: Array = []
	for n in names:
		if has_clip(str(names[n])):
			out.append(n)
	out.sort()
	return out


func ids() -> Array:
	var out: Array = clips.keys()
	out.sort()
	return out


func counts() -> Dictionary:
	var c := {"approved": 0, "development": 0, "missing": 0}
	for id in clips:
		var s := status(id)
		if s == "missing" or not has_clip(id):
			c.missing += 1
		else:
			c[s] = int(c.get(s, 0)) + 1
	return c


## Ids referenced by a line's "audio" field (a single id or an ordered sequence).
static func line_ids(audio) -> Array:
	if audio == null:
		return []
	if typeof(audio) == TYPE_ARRAY:
		return (audio as Array).map(func(x): return str(x))
	var s := str(audio)
	return [] if s == "" else [s]


func all_present(ids_: Array) -> bool:
	if ids_.is_empty():
		return false
	for id in ids_:
		if not has_clip(str(id)):
			return false
	return true
