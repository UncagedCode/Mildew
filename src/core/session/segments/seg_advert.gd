class_name SegAdvert
extends Segment
## Adverts (CP8). mode "single": one advert between games. mode "break": the midpoint
## COMMERCIAL BREAK (~90 s): END OF PART ONE bumper -> two adverts -> interval card -> PART TWO.
## Phones offer a READY button; when everyone is back on the sofa the break skips the rest of the
## interval (it never cuts an advert off mid-scene). This is fiction-dressed pacing, not the real
## TRANSMISSION PAUSED system, which stays available at all times.

var mode := "single"
var ads: Array = []
var sub := ""
var ready := {}
var phase_end := 0.0
var interval_end := 0.0
var _ads_end := 0.0


func _init(desc: Dictionary) -> void:
	kind = "advert"
	mode = str(desc.get("mode", "single"))
	ads = desc.get("ads", [])
	allows_late_join_after = mode == "break"   # late joiners come in after the break


static func ad_seconds(ad: Dictionary) -> float:
	var s := 0.0
	for sc in ad.get("scenes", []):
		s += float(sc.get("t", 3.0))
	return s


func start() -> void:
	duration = 1.0e9
	for a in ads:
		session.director.used_content[str(a.get("id", ""))] = true
	var t := 0.0
	if mode == "break":
		sub = "out"
		session.emit_tv({"e": "break_card", "kind": "out", "title": "END OF PART ONE", "sub": "STRETCH. WEE. FIND A SNACK."})
		var lt := say_at(0.4, "announcer", "break_in")
		if session.director.rng.randf() < 0.25:
			say_at(lt + 0.2, "graham", "break_will_we")
		t = session.cfg.f("break.bumper_seconds", 4.0)
	for a in ads:
		var ad: Dictionary = a
		at(t, func(): _play(ad))
		t += ad_seconds(ad)
	_ads_end = t
	if mode == "break":
		var total: float = session.cfg.f("break.seconds", 90.0)
		var interval := maxf(0.0, total - t - session.cfg.f("break.return_seconds", 3.0))
		at(t, func(): _interval(interval))
		phase_end = t + interval + session.cfg.f("break.return_seconds", 3.0)
	else:
		phase_end = t + 0.3
	session.push_screens()


func _play(ad: Dictionary) -> void:
	sub = "ad"
	session.emit_tv({"e": "advert_show", "id": ad.get("id"), "advert": ad})
	var t := elapsed
	for sc in ad.get("scenes", []):
		var vo := str(sc.get("vo", ""))
		if vo != "":
			var line := {"id": "ad:" + str(ad.get("id")), "speaker": "advert", "category": "advert_vo", "text": vo, "speech": vo,
				"mood": "", "pid": "", "silent": false, "audio": null}
			var dur: float = minf(session.speech_seconds(line), float(sc.get("t", 3.0)))
			at(t + 0.2, func(): session.emit_say(line, dur))
		t += float(sc.get("t", 3.0))


func _interval(seconds: float) -> void:
	sub = "interval"
	if _all_ready():
		seconds = 0.0
	interval_end = elapsed + seconds
	session.emit_tv({"e": "break_card", "kind": "interval", "title": "PART TWO IN A MOMENT", "sub": "PRESS READY ON YOUR UNIT WHEN YOU'RE BACK",
		"seconds": seconds, "ready": ready.size(), "of": _present().size()})
	session.push_screens()


func _back() -> void:
	sub = "in"
	session.emit_tv({"e": "break_card", "kind": "in", "title": "PART TWO", "sub": ""})
	phase_end = elapsed + session.cfg.f("break.return_seconds", 3.0)
	session.push_screens()


func _present() -> Array:
	return session.active_player_ids().filter(func(pid): return session.players[pid].connected)


func _all_ready() -> bool:
	var ps := _present()
	if ps.is_empty():
		return false
	for pid in ps:
		if not ready.has(pid):
			return false
	return true


func update(dt: float) -> void:
	elapsed += dt
	while not _timeline.is_empty() and _timeline[0].at <= elapsed:
		_timeline.pop_front().fn.call()
	if mode == "break" and sub == "interval" and (elapsed >= interval_end or _all_ready()):
		_back()
	if elapsed >= phase_end and _timeline.is_empty() and (mode != "break" or sub == "in"):
		done = true


func handle_action(player: PlayerState, msg: Dictionary) -> String:
	if mode != "break" or str(msg.get("t")) != Protocol.C_READY:
		return Protocol.E_STALE
	ready[player.player_id] = true
	session.emit_tv({"e": "break_ready", "count": ready.size(), "of": _present().size()})
	session.push_screens()
	return ""


func finish() -> void:
	session.emit_tv({"e": "advert_end"})


func screen_for(player: PlayerState) -> Dictionary:
	if mode != "break":
		return {"screen": "watch", "data": {"caption": "A WORD FROM OUR SPONSORS"}}
	var remaining := 0
	if sub == "interval":
		remaining = int(maxf(0.0, interval_end - elapsed) / maxf(session.time_scale, 0.001) * 1000.0)
	return {"screen": "break", "data": {"ready": ready.has(player.player_id), "count": ready.size(), "of": _present().size(),
		"remaining_ms": remaining, "sub": sub}}


func tv_state() -> Dictionary:
	return {"kind": kind, "mode": mode, "sub": sub, "ready": ready.size()}
