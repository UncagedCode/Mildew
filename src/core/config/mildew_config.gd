class_name MildewConfig
extends RefCounted
## Loads machine-readable design constants (config/design_constants.json — product rules,
## from the handoff package) and runtime tuning (config/runtime.json — implementation values).
## Platform-agnostic: no scene tree access. Values may be overridden per-instance for tests.

const DESIGN_PATH := "res://config/design_constants.json"
const RUNTIME_PATH := "res://config/runtime.json"

var design: Dictionary = {}
var runtime: Dictionary = {}
var _overrides: Dictionary = {}


static func load_default() -> MildewConfig:
	var c := MildewConfig.new()
	c.design = _read_json(DESIGN_PATH)
	c.runtime = _read_json(RUNTIME_PATH)
	return c


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MildewConfig: cannot open %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MildewConfig: %s is not a JSON object" % path)
		return {}
	return parsed


## Look up a dotted path such as "broadcast.reconnect_timeout_seconds".
## Searches overrides, then runtime, then design constants.
func get_value(path: String, default_value = null):
	if _overrides.has(path):
		return _overrides[path]
	for source in [runtime, design]:
		var v = _dig(source, path)
		if v != null:
			return v
	return default_value


func set_override(path: String, value) -> void:
	_overrides[path] = value


func f(path: String, default_value: float = 0.0) -> float:
	return float(get_value(path, default_value))


func i(path: String, default_value: int = 0) -> int:
	return int(get_value(path, default_value))


static func _dig(d: Dictionary, path: String):
	var cur = d
	for part in path.split("."):
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(part):
			return null
		cur = cur[part]
	return cur
