class_name Segment
extends RefCounted
## One step of the broadcast timeline. Driven by SessionServer with *show time* (which freezes
## during manual pause / reconnect waits). Segments never talk to transports directly.

var session  # SessionServer (untyped to avoid cyclic class references)
var kind := "segment"
var elapsed := 0.0
var duration := 1.0
var done := false
var allows_late_join_after := true   # safe boundary for integrating late joiners
var _timeline: Array = []            # [{at, fn: Callable}] fired once as elapsed passes `at`


func setup(p_session) -> Segment:
	session = p_session
	return self


func start() -> void:
	pass


func update(dt: float) -> void:
	elapsed += dt
	while not _timeline.is_empty() and _timeline[0].at <= elapsed:
		var ev = _timeline.pop_front()
		ev.fn.call()
	if elapsed >= duration and _timeline.is_empty():
		done = true


func at(t: float, fn: Callable) -> void:
	_timeline.append({"at": t, "fn": fn})
	_timeline.sort_custom(func(a, b): return a.at < b.at)


## Queue a spoken line at time t; returns the time the line finishes.
func say_at(t: float, speaker: String, category: String, ctx: Dictionary = {}) -> float:
	var line: Dictionary = session.director.line(speaker, category, session.line_ctx(ctx))
	if line.is_empty():
		return t
	var dur: float = session.speech_seconds(line)
	at(t, func(): session.emit_say(line, dur))
	return t + dur


func handle_action(_player: PlayerState, _msg: Dictionary) -> String:
	return Protocol.E_STALE   # nothing open to answer (late arrival after the segment moved on)


func screen_for(_player: PlayerState) -> Dictionary:
	return {"screen": "watch", "data": {"caption": "PLEASE WATCH YOUR TELEVISION"}}


func tv_state() -> Dictionary:
	return {"kind": kind, "elapsed": elapsed, "duration": duration}


func finish() -> void:
	pass
