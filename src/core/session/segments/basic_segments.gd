class_name BasicSegments
extends RefCounted
## Factory for the simple presentational segments (opening, links, intros, stings, scores,
## sign-off). The question segment lives in seg_question.gd.


static func make(desc: Dictionary, session) -> Segment:
	match str(desc.get("kind")):
		"opening":
			return SegOpening.new(desc).setup(session)
		"link":
			return SegLink.new(desc).setup(session)
		"intros":
			return SegIntros.new(desc).setup(session)
		"sting":
			return SegSting.new(desc).setup(session)
		"question":
			return SegQuestion.new(desc).setup(session)
		"hole_round":
			return SegHole.new(desc).setup(session)
		"scores":
			return SegScores.new(desc).setup(session)
		"sign_off":
			return SegSignOff.new(desc).setup(session)
	push_error("Unknown segment kind %s" % desc.get("kind"))
	return SegLink.new({"lines": []}).setup(session)


class SegOpening extends Segment:
	func _init(_desc: Dictionary) -> void:
		kind = "opening"

	func start() -> void:
		duration = session.cfg.f("show.opening_titles_seconds", 9.0)
		session.emit_tv({"e": "opening_titles", "duration": duration})
		say_at(maxf(0.0, duration - 3.0), "announcer", "show_open")


class SegLink extends Segment:
	var lines: Array = []
	var camera := "cam1"

	func _init(desc: Dictionary) -> void:
		kind = "link"
		lines = desc.get("lines", [])
		camera = str(desc.get("camera", "cam1"))

	func start() -> void:
		session.emit_tv({"e": "camera", "cam": camera})
		var t := 0.4
		for l in lines:
			t = say_at(t, str(l[0]), str(l[1])) + 0.35
		duration = t + 0.3


class SegIntros extends Segment:
	func _init(_desc: Dictionary) -> void:
		kind = "intros"

	func start() -> void:
		var t := 0.3
		var per: float = session.cfg.f("show.intro_seconds_per_player", 3.6)
		for p in session.active_players_sorted():
			var pid: String = p.player_id
			at(t, func(): session.emit_tv({"e": "intro_player", "pid": pid, "number": p.number}))
			var cat := "intro_returning" if p.returning and session.director.rng.randf() < 0.6 else "intro_player"
			var end := say_at(t + 0.5, "graham", cat, {"pid": pid, "count": p.number})
			t = maxf(t + per, end + 0.4)
		at(t, func(): session.emit_tv({"e": "camera", "cam": "cam2"}))
		duration = t + 0.6


class SegSting extends Segment:
	var game_id := ""
	var title := ""

	func _init(desc: Dictionary) -> void:
		kind = "sting"
		game_id = str(desc.get("game_id", ""))
		title = str(desc.get("title", ""))

	func start() -> void:
		duration = session.cfg.f("show.sting_seconds", 4.5)
		session.emit_tv({"e": "sting", "game_id": game_id, "title": title, "duration": duration})


class SegScores extends Segment:
	var final := false

	func _init(desc: Dictionary) -> void:
		kind = "scores"
		final = bool(desc.get("final", false))

	func start() -> void:
		var standings: Array = session.standings()
		session.director.on_scores(standings)
		at(0.0, func(): session.emit_tv({"e": "camera", "cam": "cam1"}))
		var end := say_at(0.3, "graham", "scores_intro")
		at(end + 0.2, func(): session.emit_tv({"e": "scores", "standings": session.standings(), "final": final}))
		duration = maxf(session.cfg.f("show.scoreboard_seconds", 8.0), end + 6.0)

	func screen_for(player: PlayerState) -> Dictionary:
		if elapsed < 0.5:
			return super.screen_for(player)
		var st: Array = session.standings()
		var rank := 1
		for i in st.size():
			if st[i].pid == player.player_id:
				rank = int(st[i].rank)
		return {"screen": "scores", "data": {"rank": rank, "of": st.size(), "score": player.score}}


class SegSignOff extends Segment:
	func _init(_desc: Dictionary) -> void:
		kind = "sign_off"

	func start() -> void:
		var st: Array = session.standings()
		var t := 0.4
		session.emit_tv({"e": "camera", "cam": "cam1"})
		if st.size() >= 2 and int(st[0].score) == int(st[1].score):
			t = say_at(t, "graham", "tie") + 0.4
		elif st.size() >= 1 and int(st[0].score) > 0:
			var winner_pid: String = st[0].pid
			at(t, func(): session.emit_tv({"e": "winner", "pid": winner_pid}))
			t = say_at(t, "graham", "winner", {"pid": winner_pid}) + 0.5
		t = say_at(t, "graham", "sign_off") + 0.6
		at(t, func(): session.emit_tv({"e": "sign_off"}))
		t = say_at(t + 0.4, "announcer", "closedown") + 1.0
		duration = t

	func finish() -> void:
		session.end_show()
