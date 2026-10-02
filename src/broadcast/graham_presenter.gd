class_name GrahamPresenter
extends Control
## Low-budget photographic Graham (D021/D022; references/graham/docs/GRAHAM_GODOT_IMPLEMENTATION.md).
##
## Primary mode — COMPOSITED: Graham's alpha cut-outs (config/graham_cutouts.json) drive a Sprite3D
## standing at his mark in the Mildew studio, so Camera 1, wide shots and podium angles all see
## the same presenter in the same set. Life comes from restrained, cheap television:
##   * waist-pivoted breathing and the odd tiny weight shift (allowed: he is a cut-out);
##   * natural blinks from locked blink pairs (never synthesised eyelids);
##   * a non-repeating lower-face speech cycle from a pixel-locked talking set;
##   * idle variants chosen on each new shot so holds don't repeat exactly;
##   * rare frame-sequence motion excerpts (pack) for performance moments.
## Fallback mode — PLATES: if no cut-out map exists, full-frame 4:3 stills are drawn as a 2D
## camera plate on Camera 1 (pack behaviour).
##
## Not authoritative: the Director decides mood/lines; this resolves *semantic states* to assets
## with fallbacks so better stills/puppets/FMV can replace states without touching game logic.

const CUT_MAP := "res://config/graham_cutouts.json"
const PLATE_MAP := "res://config/graham_states.json"
const W := 1440.0
const H := 1080.0
const MOOD_STATE := {
	"relaxed": "restrained_smile", "pleased": "restrained_smile", "amused": "amused",
	"irritated": "return_tense", "angry": "irritated_front", "embarrassed": "disappointed", "rattled": "rattled",
}
## Fallbacks for states a map may not provide (never error on a cosmetic state).
const FALLBACK := {
	"amused": "restrained_smile", "disappointed": "neutral", "rattled": "return_tense", "angry": "irritated_hold",
	"irritated_front": "irritated_hold", "stare": "neutral", "off_air": "reading_cards", "laughing": "presenter_smile",
	"look_off": "irritated_turn", "look_off_left": "neutral", "podium_glance": "restrained_smile",
	"applause_ack": "restrained_smile", "embarrassed": "disappointed", "eyes_closed": "neutral",
	"recovered_presenter": "restrained_smile", "return_tense": "neutral", "irritated_turn": "irritated_hold",
	"irritated_hold": "neutral", "presenting_gesture": "presenting", "open_hand_gesture": "presenting_gesture",
	"presenter_smile": "restrained_smile", "presenting": "restrained_smile", "reading_cards": "neutral",
	"restrained_smile": "neutral",
}

signal state_shown(state: String, resolved: String)

var studio                             # StudioSet
var sprite: Sprite3D                   # composited mode target
var force_visible := false             # dev gallery (plate mode draws regardless of camera)
var mode := "none"                     # "cut" | "plates" | "none"
var pressure := 0.0

var cut := {}                          # parsed graham_cutouts.json
var plates := {}                       # parsed graham_states.json
var _tex := {}
var _requested := {}
var _rng := RandomNumberGenerator.new()

var _state := ""
var _shown := ""
var _frame := ""                       # current frame id (cut mode) / path (plate mode)
var _base := "restrained_smile"
var _was_on_air := false
var _shot_age := 0.0

# blinking
var _blink_in := 3.0
var _blink_left := 0.0
var _blink_double := false
# speech
var _speech_left := 0.0
var _speech_next := 0.0
var _speech_last := ""
var _settle := ""
# breathing / weight shift
var _breath_t := 0.0
var _breath_period := 4.4
var _sway := 0.0
var _sway_target := 0.0
var _sway_in := 6.0
# plate-mode dissolve + operator drift
var _cur: Texture2D = null
var _prev: Texture2D = null
var _fade := 1.0
var _drift_from := Vector3(0, 0, 1)
var _drift_to := Vector3(0, 0, 1)
var _drift_t := 0.0
var _drift_len := 5.0
# motion excerpt (plate frames)
var _motion: Array = []
var _motion_i := -1
var _motion_t := 0.0
var _motion_fps := 12.5
var _motion_then := ""


func _ready() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	cut = _read_json(CUT_MAP)
	plates = _read_json(PLATE_MAP)
	mode = "cut" if not cut.is_empty() else ("plates" if not plates.is_empty() else "none")
	if mode == "cut":
		for p in cut.get("frames", {}).values():
			_request(str(p))
	elif mode == "plates":
		for s in plates.get("states", {}).values():
			if s.get("asset"):
				_request(str(s.asset))
			for p in s.get("speech_cycle", []):
				_request(str(p))
	set_state(_base, "cut")


func attach_sprite(s: Sprite3D) -> void:
	sprite = s
	_apply_frame()


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}


# ---------------------------------------------------------------------------
# State resolution
# ---------------------------------------------------------------------------

func has_state(state: String) -> bool:
	if mode == "cut":
		return cut.get("states", {}).has(state)
	var e: Dictionary = plates.get("states", {}).get(state, {})
	return e.get("asset") != null and str(e.get("asset", "")) != ""


## Follows fallbacks until an available state is found.
func resolve(state: String) -> String:
	var s := state
	for i in 10:
		if has_state(s):
			return s
		if mode == "plates":
			var e: Dictionary = plates.get("states", {}).get(s, {})
			if e.has("fallback") and e.fallback != null:
				s = str(e.fallback)
				continue
		s = str(FALLBACK.get(s, "neutral"))
	return "neutral" if has_state("neutral") else s


func fallback_chain(state: String) -> Array:
	var out: Array = [state]
	var s := state
	for i in 10:
		if has_state(s):
			break
		s = str(FALLBACK.get(s, "neutral"))
		out.append(s)
	return out


func all_states() -> Array:
	var names := {}
	for k in FALLBACK.keys():
		names[k] = true
	for k in MOOD_STATE.values():
		names[k] = true
	var src: Dictionary = cut.get("states", {}) if mode == "cut" else plates.get("states", {})
	for k in src.keys():
		names[k] = true
	var out := names.keys()
	out.sort()
	return out


func _frame_path(frame: String) -> String:
	return str(cut.get("frames", {}).get(frame, ""))


func _request(path: String) -> void:
	if path == "" or _tex.has(path) or _requested.has(path) or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_request(path, "Texture2D") == OK:
		_requested[path] = true
	else:
		_tex[path] = load(path)


func _tex_for(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	if _requested.has(path):
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_tex[path] = ResourceLoader.load_threaded_get(path)
			_requested.erase(path)
			return _tex[path]
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return null
		_requested.erase(path)
	if path != "" and ResourceLoader.exists(path):
		_tex[path] = load(path)
		return _tex[path]
	return null


func is_ready() -> bool:
	return _requested.is_empty()


# ---------------------------------------------------------------------------
# API (compatible with the old puppet)
# ---------------------------------------------------------------------------

## mode_hint: "cut" hard swap, "dissolve" soft (plate mode), "auto".
func set_state(state: String, mode_hint: String = "auto") -> void:
	_state = state
	var r := resolve(state)
	_shown = r
	if mode == "cut":
		var e: Dictionary = cut.get("states", {}).get(r, {})
		var f := str(e.get("frame", ""))
		var variants: Array = e.get("variants", [])
		if not variants.is_empty() and not on_air() and _rng.randf() < 0.35:
			f = str(variants[_rng.randi_range(0, variants.size() - 1)])
		_frame = f
		_apply_frame()
	elif mode == "plates":
		var path := str(plates.states[r].asset)
		var t := _tex_for(path)
		if t != null and t != _cur:
			var dissolve := mode_hint == "dissolve" or (mode_hint == "auto" and on_air())
			_prev = _cur if dissolve else null
			_cur = t
			_fade = 0.0 if dissolve else 1.0
	state_shown.emit(state, r)


func current_state() -> String:
	return _shown


func shot_age() -> float:
	return _shot_age


## Visible speech. Returns how long the mouth visibly moves before the broadcast should cut away
## (the voice continues over graphics; GRAHAM_PERFORMANCE rule 7).
func speak(seconds: float, settle_state: String = "") -> float:
	_settle = settle_state if settle_state != "" else _base
	var cap := 3.0 if mode == "cut" else 1.5   # a locked talking set can stay on screen longer
	var visible_for := minf(seconds, cap) if seconds <= cap + 0.6 else _rng.randf_range(1.2, cap)
	_speech_left = visible_for
	_speech_next = 0.0
	_blink_left = 0.0
	if mode == "cut":
		set_state("presenting", "cut")
	return visible_for


func is_speaking() -> bool:
	return _speech_left > 0.0


## Mood changes the *implied* idle state; visible on the next camera return rather than as a
## slideshow swap on a live shot (GRAHAM_PERFORMANCE rule 2).
func set_mood(mood: String) -> void:
	var s: String = MOOD_STATE.get(mood, "restrained_smile")
	if mood == "pleased" and _rng.randf() < 0.3:
		s = "presenter_smile"
	_base = s
	if not on_air() and not is_speaking() and _motion_i < 0:
		set_state(_base, "cut")


func set_activity(activity: String) -> void:
	match activity:
		"reading", "waiting":
			_idle("reading_cards")
		"stare":
			set_state("stare", "cut")
		"look_off":
			set_state("look_off", "cut")
		_:
			_idle(_base if _base != "reading_cards" else "restrained_smile")


func _idle(s: String) -> void:
	if is_speaking():
		_settle = s
	else:
		set_state(s, "auto")


func set_pressure(p: float) -> void:
	pressure = p


## Rare full-motion beat (pack excerpts; plate mode only — they carry the reference set).
func play_motion(name: String, then_state: String = "") -> bool:
	if mode != "plates":
		return false
	var def: Dictionary = plates.get("motion", {}).get(name, {})
	if def.is_empty():
		return false
	_motion.clear()
	for i in int(def.get("frames", 0)):
		var p := "%s/%03d.jpg" % [str(def.dir), i]
		_motion.append(p)
		_request(p)
	_motion_fps = float(def.get("fps", 12.5))
	_motion_i = 0
	_motion_t = 0.0
	_motion_then = then_state
	return true


func on_air() -> bool:
	if force_visible:
		return true
	if studio == null:
		return false
	var cam := str(studio.current_cam)
	if mode == "cut":
		return cam in ["cam1", "cam2", "cam3", "cam4"]
	return cam == "cam1"


# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var air := on_air()
	if air and not _was_on_air:
		_shot_age = 0.0
		_drift_from = Vector3(0, 0, 1)
		_new_drift()
	_was_on_air = air
	_shot_age += delta
	if _speech_left > 0.0:
		_speech_left -= delta
		_speech_next -= delta
		if _speech_next <= 0.0:
			_next_mouth()
			_speech_next = 1.0 / _rng.randf_range(6.0, 9.0)
		if _speech_left <= 0.0:
			set_state(_settle if _settle != "" else _base, "cut")
	elif mode == "cut":
		_tick_blink(delta)
	_tick_body(delta)
	if mode == "plates":
		_fade = minf(1.0, _fade + delta / 0.12)
		_drift_t += delta
		if _drift_t >= _drift_len:
			_drift_from = _drift_now()
			_new_drift()
		if _motion_i >= 0:
			_motion_t += delta
			var want := int(_motion_t * _motion_fps)
			if want >= _motion.size():
				_motion_i = -1
				set_state(_motion_then if _motion_then != "" else _base, "cut")
			else:
				_motion_i = want
		if air:
			queue_redraw()


func _next_mouth() -> void:
	if mode == "cut":
		var cyc: Array = cut.get("talk_cycle", []).duplicate()
		cyc.erase(_speech_last)
		if cyc.is_empty():
			return
		_speech_last = str(cyc[_rng.randi_range(0, cyc.size() - 1)])
		_frame = _speech_last
		_apply_frame()
	elif mode == "plates":
		var frames: Array = plates.get("states", {}).get("presenting", {}).get("speech_cycle", [])
		if frames.is_empty():
			return
		var i := _rng.randi_range(0, frames.size() - 1)
		var t := _tex_for(str(frames[i]))
		if t != null:
			_cur = t
			_prev = null
			_fade = 1.0


func _tick_blink(delta: float) -> void:
	var e: Dictionary = cut.get("states", {}).get(_shown, {})
	var blinks: Array = e.get("blink", [])
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0:
			_frame = str(e.get("frame", _frame))
			_apply_frame()
			if _blink_double:
				_blink_double = false
				_blink_in = 0.16
		return
	if blinks.is_empty():
		return
	_blink_in -= delta
	if _blink_in <= 0.0:
		_frame = str(blinks[_rng.randi_range(0, blinks.size() - 1)])
		_apply_frame()
		_blink_left = _rng.randf_range(0.09, 0.15)
		_blink_double = _rng.randf() < 0.12
		_blink_in = _rng.randf_range(2.2, 6.0) * (0.7 if pressure > 0.6 else 1.0)  # stressed people blink more


func _tick_body(delta: float) -> void:
	if sprite == null:
		return
	var still: bool = str(cut.get("states", {}).get(_shown, {}).get("camera_motion", "quiet")) == "none"
	_breath_t += delta
	var breath := 0.0 if still else sin(_breath_t * TAU / _breath_period) * 0.0032
	_sway_in -= delta
	if _sway_in <= 0.0:
		_sway_target = 0.0 if _rng.randf() < 0.5 else _rng.randf_range(-0.012, 0.012)
		_sway_in = _rng.randf_range(4.0, 9.0)
		_breath_period = _rng.randf_range(3.8, 5.2)
	_sway = lerpf(_sway, _sway_target, 1.0 - exp(-delta * 0.8))
	sprite.scale = Vector3(1.0, 1.0 + breath, 1.0)
	sprite.rotation.z = 0.0 if still else _sway * 0.15
	var base_pos: Vector3 = StudioSet.GRAHAM_POS + Vector3(0, 0.65, 0)
	sprite.position = base_pos + Vector3(0.0 if still else _sway, 0, 0)


func _apply_frame() -> void:
	if mode != "cut" or sprite == null:
		return
	var t := _tex_for(_frame_path(_frame))
	if t != null:
		sprite.texture = t


# ---------------------------------------------------------------------------
# Plate mode drawing (fallback only)
# ---------------------------------------------------------------------------

func _new_drift() -> void:
	_drift_to = Vector3(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3), 1.0 + _rng.randf_range(0.0, 0.005))
	if _rng.randf() < 0.15:
		_drift_to = _drift_from
	_drift_t = 0.0
	_drift_len = _rng.randf_range(3.0, 7.0)


func _drift_now() -> Vector3:
	var k := clampf(_drift_t / maxf(0.01, _drift_len), 0.0, 1.0)
	return _drift_from.lerp(_drift_to, k * k * (3.0 - 2.0 * k))


func _draw() -> void:
	if mode != "plates" or not on_air():
		return
	var m := _drift_now()
	var c := Vector2(W, H) * 0.5
	draw_set_transform(c + Vector2(m.x, m.y), 0.0, Vector2(m.z, m.z))
	var r := Rect2(-c, Vector2(W, H))
	var main := _cur
	if _motion_i >= 0 and _motion_i < _motion.size():
		var mt := _tex_for(str(_motion[_motion_i]))
		if mt != null:
			main = mt
	if _prev != null and _fade < 1.0:
		draw_texture_rect(_prev, r, false)
		if main:
			draw_texture_rect(main, r, false, Color(1, 1, 1, _fade))
	elif main != null:
		draw_texture_rect(main, r, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
