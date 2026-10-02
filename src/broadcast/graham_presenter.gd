class_name GrahamPresenter
extends Control
## Low-budget photoreal Graham (D021; references/graham/docs/GRAHAM_GODOT_IMPLEMENTATION.md).
##
## Graham is a *camera plate*: full-frame 4:3 stills of the canonical performance, shown when the
## broadcast is on Camera 1. Life comes from television, not from animating a cut-out:
##   * operator micro-motion (slow 0.2-0.7% push / 1-3 px drift, sometimes none) - never "breathing";
##   * short dissolves for minor substitutions, camera bridges for emotional changes;
##   * a randomised (never ABCD) speech-cycle bridge, at most ~1.5 s on screen per line;
##   * rare frame-sequence motion excerpts (no runtime video decoding dependency).
##
## Not authoritative: the Director decides mood/lines; this node resolves *semantic states* to
## whatever assets exist (config/graham_states.json, with fallbacks) so better stills, alpha
## puppets or FMV can replace individual states without touching Director/game logic.
## Public API is compatible with the old procedural puppet (set_mood/set_activity/speak/...).

const MAP_PATH := "res://config/graham_states.json"
const W := 1440.0
const H := 1080.0
## Director mood -> preferred visual state (GRAHAM_DIRECTOR_MAPPING.md). Missing states fall back.
const MOOD_STATE := {
	"relaxed": "restrained_smile", "pleased": "restrained_smile", "amused": "amused",
	"irritated": "return_tense", "angry": "angry", "embarrassed": "disappointed", "rattled": "rattled",
}

signal state_shown(state: String, resolved: String)

var studio                             # StudioSet: plate is visible only on Camera 1
var force_visible := false             # dev gallery / tests
var states := {}
var default_state := "neutral"
var motion_defs := {}
var profiles := {}
var pressure := 0.0

var _tex := {}                         # path -> Texture2D (loaded)
var _requested := {}                   # path -> true (threaded load in flight)
var _cur: Texture2D = null
var _prev: Texture2D = null
var _fade := 1.0                       # 0 -> 1 dissolve progress
var _fade_len := 0.12
var _state := ""                       # requested semantic state
var _shown := ""                       # resolved state actually on the plate
var _base := "restrained_smile"        # idle state implied by mood/activity
var _was_visible := false
var _shot_age := 0.0

# speech bridge
var _speech_left := 0.0
var _speech_frames: Array = []
var _speech_next := 0.0
var _speech_last := -1
var _settle := ""
var _rng := RandomNumberGenerator.new()

# operator micro-motion
var _m_from := Vector3(0, 0, 1)        # (dx, dy, scale)
var _m_to := Vector3(0, 0, 1)
var _m_t := 0.0
var _m_len := 4.0
var _exposure := 1.0

# motion excerpt playback
var _motion: Array = []                # paths
var _motion_i := -1
var _motion_t := 0.0
var _motion_fps := 12.5
var _motion_then := ""
var _motion_tex: Texture2D = null


func _ready() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	load_map()
	# Preload every still plate + speech frame off the main thread (≈15 textures at 960x720).
	for s in states.values():
		if s.get("asset"):
			_request(str(s.asset))
		for p in s.get("speech_cycle", []):
			_request(str(p))
	set_state(_base, "cut")


func load_map(path: String = MAP_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("GrahamPresenter: no state map at %s" % path)
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	states = d.get("states", {})
	default_state = str(d.get("default_state", "neutral"))
	motion_defs = d.get("motion", {})
	profiles = d.get("profile", {}).get("camera_motion_profiles", {})


## Follows fallbacks until an asset exists. Never errors on a missing cosmetic state.
func resolve(state: String) -> String:
	var s := state
	for i in 8:
		var e: Dictionary = states.get(s, {})
		if e.is_empty():
			s = default_state
			continue
		if e.get("asset") != null and str(e.get("asset")) != "":
			return s
		var fb = e.get("fallback")
		s = str(fb) if fb != null else default_state
	return default_state


func fallback_chain(state: String) -> Array:
	var out: Array = [state]
	var s := state
	for i in 8:
		var e: Dictionary = states.get(s, {})
		if e.is_empty() or (e.get("asset") != null and str(e.get("asset")) != ""):
			break
		s = str(e.get("fallback")) if e.get("fallback") != null else default_state
		out.append(s)
	return out


func _request(path: String) -> void:
	if _tex.has(path) or _requested.has(path) or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_request(path, "Texture2D") == OK:
		_requested[path] = true
	else:
		_tex[path] = load(path)


func _get(path: String) -> Texture2D:
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
	if ResourceLoader.exists(path):
		_tex[path] = load(path)   # last resort (should not happen once preloading has finished)
		return _tex[path]
	return null


func is_ready() -> bool:
	return _requested.is_empty()


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## mode: "cut" (hard), "dissolve" (80-160 ms), "auto" (hidden swap if off-air, else dissolve).
func set_state(state: String, mode: String = "auto") -> void:
	_state = state
	var r := resolve(state)
	var path := str(states.get(r, {}).get("asset", ""))
	var t := _get(path)
	if t == null:
		_request(path)
		_shown = r
		return
	if t == _cur and _motion_i < 0:
		_shown = r
		return
	var dissolve := mode == "dissolve" or (mode == "auto" and _plate_visible())
	_prev = _cur if dissolve else null
	_cur = t
	_fade = 0.0 if dissolve else 1.0
	_fade_len = _rng.randf_range(0.08, 0.16)
	if r != _shown:
		_new_motion_segment(true)
	_shown = r
	state_shown.emit(state, r)


func current_state() -> String:
	return _shown


func shot_age() -> float:
	return _shot_age


## Visible speech bridge. Returns how long the mouth is visibly "speaking" (≤ 1.5 s).
## The broadcast should cut away after that while the voice continues.
func speak(seconds: float, settle_state: String = "") -> float:
	var prof: Dictionary = states.get("presenting", {})
	_speech_frames = prof.get("speech_cycle", [])
	_settle = settle_state if settle_state != "" else _base
	var cap: float = minf(1.5, seconds)
	var bridge := minf(cap, _rng.randf_range(0.5, 1.2)) if seconds > 1.6 else cap
	_speech_left = bridge
	_speech_next = 0.0
	if _speech_frames.is_empty():
		set_state("presenting", "cut")
	return bridge


func is_speaking() -> bool:
	return _speech_left > 0.0


## Puppet-compatible: mood changes the *implied* idle state; it becomes visible at the next
## camera return rather than as a slideshow swap on a live shot (GRAHAM_PERFORMANCE rule 2).
func set_mood(mood: String) -> void:
	var s: String = MOOD_STATE.get(mood, "restrained_smile")
	if mood == "pleased" and _rng.randf() < 0.3:
		s = "presenter_smile"
	_base = s
	if not _plate_visible() and not is_speaking() and _motion_i < 0:
		set_state(_base, "cut")


func set_activity(activity: String) -> void:
	match activity:
		"reading", "waiting":
			_base_activity("reading_cards")
		"stare":
			set_state("stare", "cut")
			_m_from = _m_to   # a stare holds the camera still
			_m_len = 999.0
		"look_off":
			set_state("irritated_turn", "cut")
		_:
			_base_activity(_base if _base != "reading_cards" else "restrained_smile")


func _base_activity(s: String) -> void:
	if is_speaking():
		_settle = s
	else:
		set_state(s, "auto")


func set_pressure(p: float) -> void:
	pressure = p


## Rare full-motion beat from the zero-cost excerpts (e.g. "irritated_turn_hold", "recover_to_camera").
func play_motion(name: String, then_state: String = "") -> bool:
	var def: Dictionary = motion_defs.get(name, {})
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
	_speech_left = 0.0
	return true


func is_playing_motion() -> bool:
	return _motion_i >= 0


func _plate_visible() -> bool:
	return visible and (force_visible or (studio != null and str(studio.current_cam) == "cam1"))


# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var vis := force_visible or (studio != null and str(studio.current_cam) == "cam1")
	if vis and not _was_visible:
		_shot_age = 0.0
		_new_motion_segment(true)
	_was_visible = vis
	_shot_age += delta
	_fade = minf(1.0, _fade + delta / maxf(0.01, _fade_len))
	if _fade >= 1.0:
		_prev = null
	# speech bridge: 5-8 changes/s, random order, never the same frame twice running
	if _speech_left > 0.0:
		_speech_left -= delta
		_speech_next -= delta
		if _speech_next <= 0.0 and not _speech_frames.is_empty():
			var choices: Array = range(_speech_frames.size())
			choices.erase(_speech_last)
			_speech_last = choices[_rng.randi_range(0, choices.size() - 1)]
			var t := _get(str(_speech_frames[_speech_last]))
			if t != null:
				_cur = t
				_prev = null
				_fade = 1.0
			_speech_next = 1.0 / _rng.randf_range(5.0, 8.0)
		if _speech_left <= 0.0:
			set_state(_settle if _settle != "" else _base, "cut")
	# motion excerpt
	if _motion_i >= 0:
		_motion_t += delta
		var want := int(_motion_t * _motion_fps)
		if want >= _motion.size():
			_motion_i = -1
			_motion_tex = null
			set_state(_motion_then if _motion_then != "" else _base, "cut")
		elif want != _motion_i or _motion_tex == null:
			var t := _get(str(_motion[want]))
			if t != null:
				_motion_tex = t
				_motion_i = want
	# operator micro-motion
	_m_t += delta
	if _m_t >= _m_len:
		_new_motion_segment(false)
	if _rng.randf() < delta * 0.25:
		_exposure = _rng.randf_range(0.985, 1.015)   # brief exposure/colour fluctuation
	else:
		_exposure = lerpf(_exposure, 1.0, delta * 2.0)
	if vis:
		queue_redraw()


func _new_motion_segment(reset: bool) -> void:
	var prof_name := str(states.get(_shown, {}).get("camera_motion", "quiet"))
	if pressure > 0.6 and prof_name == "standard":
		prof_name = "quiet"
	var prof: Dictionary = profiles.get(prof_name, {"max_scale_delta": 0.003, "max_translation_px": 2, "duration_seconds": [4.0, 8.0]})
	var ref_scale := W / 960.0
	var tr := float(prof.get("max_translation_px", 2)) * ref_scale
	var sd := float(prof.get("max_scale_delta", 0.003))
	var dur: Array = prof.get("duration_seconds", [3.0, 7.0])
	_m_from = Vector3(0, 0, 1) if reset else _current_motion()
	if _rng.randf() < 0.15 or sd <= 0.0:
		_m_to = _m_from   # occasionally the operator leaves it alone
	else:
		_m_to = Vector3(_rng.randf_range(-tr, tr), _rng.randf_range(-tr, tr), 1.0 + _rng.randf_range(0.0, sd))
	_m_t = 0.0
	_m_len = _rng.randf_range(float(dur[0]), float(dur[1]))


func _current_motion() -> Vector3:
	var k := clampf(_m_t / maxf(0.01, _m_len), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return _m_from.lerp(_m_to, k)


func _draw() -> void:
	if not (force_visible or (studio != null and str(studio.current_cam) == "cam1")):
		return
	var m := _current_motion()
	var c := Vector2(W, H) * 0.5
	draw_set_transform(c + Vector2(m.x, m.y), 0.0, Vector2(m.z, m.z))
	var r := Rect2(-c, Vector2(W, H))
	var mod := Color(_exposure, _exposure, _exposure)
	draw_rect(r, Color.BLACK)
	var main := _motion_tex if _motion_i >= 0 and _motion_tex != null else _cur
	if _prev != null and _fade < 1.0 and _motion_i < 0:
		draw_texture_rect(_prev, r, false, mod)
		draw_texture_rect(main, r, false, Color(mod, _fade))
	elif main != null:
		draw_texture_rect(main, r, false, mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
