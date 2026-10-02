class_name GrahamVoiceService
extends Node
## Graham's local authored voice (tools/graham_factory/CLAUDE_INTEGRATION.md; D024).
## Registered as the autoload "GrahamVoice". Plays pre-rendered clips shipped inside the game,
## looked up by semantic id through GrahamVoiceIndex. There is NO cloud or runtime speech
## synthesis here: a missing clip is a logged gap, and the subtitle carries the line.
##
##   GrahamVoice.say("correct_01")                       -> seconds (or -1 if no local clip)
##   GrahamVoice.say_name("Aaron")                       -> name_aaron
##   GrahamVoice.say_intent("wrong_answer", {"mood": "irritated"})
##   GrahamVoice.say_sequence(["closing_01", "closing_thanks_01"])
##   await GrahamVoice.wait_finished()                   # only when a caller explicitly wants to wait
##
## All playback is asynchronous. Graham speaks one thing at a time: a new line interrupts the old.
## Development-only fallback: in debug builds (and only if enabled) a missing clip may be read by
## the device's system TTS so developers hear *something*; it is flagged loudly and can never run
## in a release build.

signal line_started(id: String)
signal line_finished(id: String)
signal clip_missing(id: String)

const INTENTS_PATH := "res://config/graham_voice_intents.json"
const BUS := "Graham"

var index: GrahamVoiceIndex
var intents := {}
var enabled := true                      # player setting PRESENTER VOICE
var dev_build := OS.is_debug_build()
var dev_tts_fallback := true             # debug builds only (BROADCAST SETTINGS in debug)
var fallback_count := 0                  # dev diagnostics
var missing_log: Array = []              # ids requested without a local clip (dev diagnostics)
var last_mode := ""                      # clip | dev_tts | silent

var _player: AudioStreamPlayer
var _queue: Array = []
var _current := ""
var _warned := {}
var _streams := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_ensure()


## Idempotent setup (also called lazily, so the service works before/without _ready).
func _ensure() -> void:
	if _player != null:
		return
	_rng.randomize()
	ensure_bus()
	_player = AudioStreamPlayer.new()
	_player.name = "GrahamVoicePlayer"
	_player.bus = BUS
	add_child(_player)
	_player.finished.connect(_on_finished)
	if index == null:
		index = GrahamVoiceIndex.shared()
	if intents.is_empty():
		var f := FileAccess.open(INTENTS_PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				intents = d


## The broadcast treatment lives on its own bus (default_bus_layout.tres). If a layout without it
## is loaded, recreate it so Graham never ends up on the dry Master bus by accident.
static func ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	AudioServer.add_bus()
	var b := AudioServer.bus_count - 1
	AudioServer.set_bus_name(b, BUS)
	AudioServer.set_bus_send(b, "Master")
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 130.0
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 7200.0
	var comp := AudioEffectCompressor.new()
	comp.threshold = -18.0
	comp.ratio = 4.0
	comp.gain = 3.0
	AudioServer.add_bus_effect(b, hp)
	AudioServer.add_bus_effect(b, lp)
	AudioServer.add_bus_effect(b, comp)


func reload_index() -> void:
	index = GrahamVoiceIndex.load_from(GrahamVoiceIndex.DEFAULT_PATH)
	GrahamVoiceIndex.set_shared(index)
	_streams.clear()
	_warned.clear()


func has_clip(id: String) -> bool:
	return index != null and index.has_clip(id)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func say(id: String, fallback_text: String = "") -> float:
	return say_sequence([id], fallback_text)


func say_name(name: String) -> float:
	_ensure()
	var id := index.name_id(name) if index else ""
	if id == "":
		_note_missing("name:" + GrahamVoiceIndex.normalise_name(name))
		return _fallback(name)
	return say(id, name)


func say_intent(intent: String, ctx: Dictionary = {}) -> float:
	_ensure()
	var options: Array = intents.get(intent, [])
	if options.is_empty():
		_note_missing("intent:" + intent)
		return -1.0
	var mood := str(ctx.get("mood", ""))
	var playable: Array = []
	var preferred: Array = []
	for o in options:
		var seq: Array = o.get("sequence", [o.get("id", "")])
		if not index.all_present(seq):
			continue
		playable.append(seq)
		var moods: Array = o.get("moods", [])
		if mood != "" and moods.has(mood):
			preferred.append(seq)
	var pool := preferred if not preferred.is_empty() else playable
	if pool.is_empty():
		var first: Dictionary = options[0]
		var seq0: Array = first.get("sequence", [first.get("id", "")])
		for id in seq0:
			_note_missing(str(id))
		return _fallback(" ".join(seq0.map(func(i): return index.text(str(i)))))
	return say_sequence(pool[_rng.randi_range(0, pool.size() - 1)])


## Plays ids back to back. Returns total seconds, or -1 if any clip is missing (nothing plays).
func say_sequence(ids: Array, fallback_text: String = "") -> float:
	_ensure()
	if not enabled or ids.is_empty():
		last_mode = "silent"
		return -1.0
	var total := 0.0
	for id in ids:
		var s := _stream(str(id))
		if s == null:
			_note_missing(str(id))
			if fallback_text == "":
				fallback_text = " ".join(ids.map(func(i): return index.text(str(i)) if index else ""))
			return _fallback(fallback_text)
		total += s.get_length()
	stop()
	_queue = ids.slice(1).map(func(i): return str(i))
	_play(str(ids[0]))
	last_mode = "clip"
	return total


## A game line from the Director ({text, speech, audio, voice_name, ...}). Used by the presenter.
## Returns {mode: clip|name|dev_tts|silent, seconds}.
func play_line(line: Dictionary) -> Dictionary:
	_ensure()
	if not enabled or line.get("silent", false):
		return {"mode": "silent", "seconds": -1.0}
	var ids := GrahamVoiceIndex.line_ids(line.get("audio"))
	if not ids.is_empty() and index.all_present(ids):
		return {"mode": "clip", "seconds": say_sequence(ids)}
	for id in ids:
		_note_missing(str(id))
	var vname := str(line.get("voice_name", ""))
	if vname != "" and index.has_name(vname):
		# Lines that open with the contestant's name: Graham says the name; the subtitle carries the rest.
		return {"mode": "name", "seconds": say_name(vname)}
	var secs := _fallback(str(line.get("speech", line.get("text", ""))))
	return {"mode": last_mode, "seconds": secs}


func is_speaking() -> bool:
	return _player != null and _player.playing


func current() -> String:
	return _current if is_speaking() else ""


func stop() -> void:
	_ensure()
	_queue.clear()
	if _player and _player.playing:
		var was := _current
		_player.stop()
		_current = ""
		line_finished.emit(was)
	if dev_build and dev_tts_fallback and DisplayServer.get_name() != "headless" and DisplayServer.has_method("tts_stop"):
		DisplayServer.tts_stop()


## Explicit wait for callers that need it; gameplay does not block on Graham by default.
func wait_finished(timeout: float = 30.0) -> void:
	var t := 0.0
	while (is_speaking() or not _queue.is_empty()) and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()


func diagnostics() -> Dictionary:
	_ensure()
	return {"counts": index.counts() if index else {}, "playing": current(), "fallbacks": fallback_count,
		"missing": missing_log.slice(-12), "enabled": enabled, "dev_tts_fallback": dev_build and dev_tts_fallback}


# ---------------------------------------------------------------------------

func _stream(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	if index == null or not index.has_clip(id):
		return null
	var s = load(index.path(id))
	if s is AudioStream:
		_streams[id] = s
		return s
	return null


func _play(id: String) -> void:
	_current = id
	_player.stream = _streams[id]
	_player.play()
	line_started.emit(id)


func _on_finished() -> void:
	var done := _current
	_current = ""
	line_finished.emit(done)
	if not _queue.is_empty():
		var nxt: String = _queue.pop_front()
		if _stream(nxt) != null:
			_play(nxt)


func _note_missing(id: String) -> void:
	missing_log.append(id)
	if missing_log.size() > 50:
		missing_log.pop_front()
	clip_missing.emit(id)
	if dev_build and not _warned.has(id):
		_warned[id] = true
		push_warning("GrahamVoice: no local clip for '%s' (status %s). Add it via tools/graham_factory/sync_godot.py." % [id, index.status(id) if index else "?"])


## Developer-only: never reachable in a release build.
func _fallback(text: String) -> float:
	last_mode = "silent"
	if not dev_build or not dev_tts_fallback or text.strip_edges() == "":
		return -1.0
	if DisplayServer.get_name() == "headless" or not DisplayServer.has_method("tts_get_voices"):
		return -1.0
	var voices: Array = DisplayServer.tts_get_voices()
	if voices.is_empty():
		return -1.0
	var en: Array = voices.filter(func(v): return str(v.get("language", "")).to_lower().begins_with("en"))
	var v: Dictionary = (en if not en.is_empty() else voices)[0]
	fallback_count += 1
	last_mode = "dev_tts"
	print("GrahamVoice DEV TTS FALLBACK (not a release path): ", text)
	DisplayServer.tts_speak(text, str(v.get("id", "")), 90, 0.88, 1.02, _rng.randi(), true)
	return -1.0
