# Godot 4.x example only. Adapt node paths to the Mildew project.
# The important contract is semantic states + fallbacks, not this exact scene layout.
extends Control
class_name GrahamPresenter

@export_file("*.json") var state_map_path: String
@onready var plate_a: TextureRect = $PlateA
@onready var plate_b: TextureRect = $PlateB
@onready var camera_motion: AnimationPlayer = $CameraMotion

var _states: Dictionary = {}
var _current_state := ""
var _front_is_a := true
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
    _rng.randomize()
    _load_state_map()
    show_state("neutral", "cut")

func _load_state_map() -> void:
    if state_map_path.is_empty():
        push_error("GrahamPresenter: state_map_path not set")
        return
    var file := FileAccess.open(state_map_path, FileAccess.READ)
    if file == null:
        push_error("GrahamPresenter: cannot open state map")
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("GrahamPresenter: invalid state JSON")
        return
    _states = parsed.get("states", {})

func resolve_state(state_id: String) -> Dictionary:
    var visited: Dictionary = {}
    var cursor := state_id
    while not cursor.is_empty() and not visited.has(cursor):
        visited[cursor] = true
        var data: Dictionary = _states.get(cursor, {})
        var asset = data.get("asset")
        if asset != null and str(asset) != "":
            return {"id": cursor, "data": data}
        cursor = str(data.get("fallback", ""))
    return {"id": "neutral", "data": _states.get("neutral", {})}

func show_state(state_id: String, transition := "broadcast_bridge") -> void:
    var resolved := resolve_state(state_id)
    var real_id: String = resolved.id
    var data: Dictionary = resolved.data
    var asset_path := str(data.get("asset", ""))
    if asset_path.is_empty():
        return

    var texture := load(asset_path) as Texture2D
    if texture == null:
        push_warning("GrahamPresenter: missing texture %s" % asset_path)
        return

    var incoming := plate_b if _front_is_a else plate_a
    var outgoing := plate_a if _front_is_a else plate_b
    incoming.texture = texture

    match transition:
        "cut":
            incoming.modulate.a = 1.0
            outgoing.modulate.a = 0.0
        "dissolve_short":
            incoming.modulate.a = 0.0
            var tween := create_tween().set_parallel(true)
            tween.tween_property(incoming, "modulate:a", 1.0, 0.12)
            tween.tween_property(outgoing, "modulate:a", 0.0, 0.12)
        _:
            # For actual emotional changes, the caller should normally bridge via
            # another camera/graphic and then call this while Graham is off-screen.
            incoming.modulate.a = 1.0
            outgoing.modulate.a = 0.0

    _front_is_a = not _front_is_a
    _current_state = real_id
    _start_micro_camera_motion(str(data.get("camera_motion", "quiet")))

func _start_micro_camera_motion(profile: String) -> void:
    # Keep this extremely small. It represents old live-camera drift.
    var target := plate_a if _front_is_a else plate_b
    var max_scale := 0.0
    var max_px := 0.0
    match profile:
        "standard":
            max_scale = 0.006
            max_px = 3.0
        "quiet":
            max_scale = 0.003
            max_px = 2.0
        _:
            return

    var duration := _rng.randf_range(3.5, 7.5)
    var base_scale := Vector2.ONE
    var target_scale := Vector2.ONE * (1.0 + _rng.randf_range(0.0, max_scale))
    var target_pos := Vector2(_rng.randf_range(-max_px, max_px), _rng.randf_range(-max_px, max_px))
    target.scale = base_scale
    target.position = Vector2.ZERO
    var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(target, "scale", target_scale, duration)
    tween.tween_property(target, "position", target_pos, duration)

func current_state() -> String:
    return _current_state
