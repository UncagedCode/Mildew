class_name AudioDesk
extends Node
## Programme audio: music beds, stings, UI sounds and layered audience reactions.
## Silence is a deliberate asset: nothing here auto-fills gaps.

const SFX := ["correct", "wrong", "lock", "tick", "static_burst", "whoosh", "sting_game", "ident_sallow",
	"applause_small", "applause_medium", "applause_big"]

var _streams := {}
var _music: AudioStreamPlayer
var _pool: Array = []
var _crowd: AudioStreamPlayer
var music_volume_db := -8.0


func _ready() -> void:
	for n in SFX + ["theme_opening", "lobby_bed"]:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	if _streams.has("lobby_bed"):
		var bed: AudioStreamWAV = _streams["lobby_bed"]
		bed.loop_mode = AudioStreamWAV.LOOP_FORWARD
		bed.loop_end = int(bed.get_length() * bed.mix_rate)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_crowd = AudioStreamPlayer.new()
	add_child(_crowd)
	for i in 5:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


func play(name: String, volume_db: float = 0.0) -> void:
	if not _streams.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = volume_db
			p.play()
			return
	_pool[0].stream = _streams[name]
	_pool[0].play()


func applause(size: String) -> void:
	var n := "applause_" + size
	if _streams.has(n):
		_crowd.stream = _streams[n]
		_crowd.volume_db = -4.0
		_crowd.play()


func music(name: String, volume_db: float = -8.0) -> void:
	if not _streams.has(name):
		_music.stop()
		return
	if _music.stream == _streams[name] and _music.playing:
		return
	_music.stream = _streams[name]
	_music.volume_db = volume_db
	_music.play()


func stop_music() -> void:
	_music.stop()


func duck(on: bool) -> void:
	_music.volume_db = music_volume_db - (10.0 if on else 0.0)
