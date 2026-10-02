class_name VoiceService
extends Node
## Hybrid voice pipeline (CLAUDE.md §13, docs/08):
##   1. If a line has a pre-rendered asset ("audio" id -> res://assets/voice/<id>.ogg|wav), play it.
##   2. Otherwise speak via the device's OFFLINE text-to-speech (Android TTS on the TV).
##   3. If no TTS voice exists, stay silent — subtitles carry the line.
## Callers only call speak(speaker, text, line); a better Graham voice provider can replace
## this node later without touching dialogue or game systems.
## D024: GRAHAM no longer uses device TTS. His lines go to the GrahamVoice autoload (local
## authored clips + name bank); device TTS remains only for the Announcer and, in debug builds,
## as GrahamVoice's flagged developer fallback.

var enabled := true
var graham: GrahamVoiceService = null   # the GrahamVoice autoload (set by the app)
var tts_available := false
var _voices := {}          # speaker -> voice id
var _player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _last_probe := -100.0
var _probes_left := 8      # Android TTS initialises async; give up re-probing after ~40 s


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_pick_voices()


func _pick_voices() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var voices: Array = []
	if DisplayServer.has_method("tts_get_voices"):
		voices = DisplayServer.tts_get_voices()
	if voices.is_empty():
		return
	tts_available = true
	var en_gb: Array = voices.filter(func(v): return str(v.get("language", "")).to_lower().replace("_", "-").begins_with("en-gb"))
	var en: Array = voices.filter(func(v): return str(v.get("language", "")).to_lower().begins_with("en"))
	var pool: Array = en_gb if not en_gb.is_empty() else (en if not en.is_empty() else voices)
	_voices["graham"] = str(pool[0].get("id", ""))
	_voices["announcer"] = str(pool[min(1, pool.size() - 1)].get("id", ""))


func describe() -> String:
	if not tts_available:
		return "no offline TTS voice on this device (subtitles only)"
	return "device TTS graham=%s announcer=%s" % [_voices.get("graham", "?"), _voices.get("announcer", "?")]


## Returns {mode: clip|name|dev_tts|tts|silent, seconds}.
func speak(speaker: String, text: String, line: Dictionary = {}) -> Dictionary:
	if not enabled or text.strip_edges() == "" or line.get("silent", false):
		return {"mode": "silent", "seconds": -1.0}
	if speaker == "graham":
		if graham == null:
			return {"mode": "silent", "seconds": -1.0}
		var l := line.duplicate()
		l["speech"] = text
		return graham.play_line(l)
	var audio_id = line.get("audio")
	if audio_id != null and str(audio_id) != "":
		for ext in ["ogg", "wav"]:
			var path := "res://assets/voice/%s.%s" % [audio_id, ext]
			if ResourceLoader.exists(path):
				_player.stream = load(path)
				_player.play()
				return {"mode": "clip", "seconds": _player.stream.get_length()}
	if not tts_available:
		# Android's TTS engine initialises asynchronously: re-probe occasionally.
		var now := Time.get_ticks_msec() / 1000.0
		if _probes_left > 0 and now - _last_probe > 5.0:
			_last_probe = now
			_probes_left -= 1
			_pick_voices()
		if not tts_available:
			return {"mode": "silent", "seconds": -1.0}
	var pitch := 0.88 if speaker == "graham" else 1.0
	var rate := 1.02 if speaker == "graham" else 0.9
	DisplayServer.tts_speak(text, str(_voices.get(speaker, "")), 90, pitch, rate, _rng.randi(), false)
	return {"mode": "tts", "seconds": -1.0}


func stop() -> void:
	if graham != null:
		graham.stop()
	if tts_available:
		DisplayServer.tts_stop()
	_player.stop()
