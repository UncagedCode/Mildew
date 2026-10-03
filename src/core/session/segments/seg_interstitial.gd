class_name SegInterstitial
extends Segment
## Short programme furniture between games (CP8).
##   kind "poll"   — VIEWER POLL: everyone votes on a silly question (no points); TV shows the split.
##   kind "awards" — end-of-show MILDEW AWARDS (Most Rot, Graham's Favourite, Fastest Finger,
##                   Graham's Disappointment) and the winner's dreadful prize.

const PRIZES := ["a tin of Hamco ham, signed", "a Mildew tea towel (used)", "a framed photograph of Graham",
	"a weekend in the Green Room", "a year's supply of Gravy & Mint crisps", "Graham's old tie",
	"a voucher for Dampco (one room)", "a rubber chicken from the prop store", "the podium 4 lamp"]

var mode := "poll"
var item: Dictionary
var qid := ""
var votes := {}
var phase_end := 0.0
var sub := ""
var awards: Array = []


func _init(desc: Dictionary) -> void:
	mode = str(desc.get("mode", "poll"))
	kind = mode
	item = desc.get("item", {})


func start() -> void:
	duration = 1.0e9
	session.question_counter += 1
	qid = "%s#%d" % [mode, session.question_counter]
	match mode:
		"poll":
			session.director.used_content[str(item.get("id", ""))] = true
			sub = "vote"
			var t := say_at(0.3, "graham", "poll_intro")
			session.emit_tv({"e": "poll_show", "qid": qid, "prompt": str(item.get("prompt", "")), "options": item.get("options", []),
				"window": session.cfg.f("poll.seconds", 15.0) + t})
			phase_end = t + session.cfg.f("poll.seconds", 15.0)
		"awards":
			_plan_awards()
	session.push_screens()


func update(dt: float) -> void:
	elapsed += dt
	while not _timeline.is_empty() and _timeline[0].at <= elapsed:
		_timeline.pop_front().fn.call()
	if mode == "poll" and sub == "vote" and (elapsed >= phase_end or _all_voted()):
		_poll_result()
	elif sub == "done" and elapsed >= phase_end and _timeline.is_empty():
		done = true


func _all_voted() -> bool:
	for pid in session.active_player_ids():
		if session.players[pid].connected and not votes.has(pid):
			return false
	return not votes.is_empty()


func _poll_result() -> void:
	sub = "done"
	var opts: Array = item.get("options", [])
	var tally: Array = []
	tally.resize(opts.size())
	tally.fill(0)
	for pid in votes:
		tally[int(votes[pid])] += 1
	var unanimous: bool = votes.size() > 1 and tally.max() == votes.size()
	session.emit_tv({"e": "poll_result", "qid": qid, "tally": tally, "votes": votes})
	var t := say_at(1.2, "graham", "poll_unanimous" if unanimous else "poll_result")
	phase_end = elapsed + maxf(5.0, t + 0.8)
	session.push_screens()


func handle_action(player: PlayerState, msg: Dictionary) -> String:
	if mode != "poll" or sub != "vote" or str(msg.get("q", "")) != qid or str(msg.get("t")) != Protocol.C_VOTE:
		return Protocol.E_STALE
	if votes.has(player.player_id):
		return Protocol.E_ALREADY_ANSWERED
	var c = Protocol.get_int(msg, "c")
	if c == null or int(c) < 0 or int(c) >= (item.get("options", []) as Array).size():
		return Protocol.E_BAD_PAYLOAD
	votes[player.player_id] = int(c)
	session.emit_tv({"e": "poll_progress", "count": votes.size()})
	session.push_screens()
	return ""


# ---------------------------------------------------------------------------
# Awards
# ---------------------------------------------------------------------------

func _plan_awards() -> void:
	var ps: Array = session.active_players_sorted()
	if ps.is_empty():
		sub = "done"
		phase_end = 0.0
		return
	var d = session.director
	var pick := func(score_fn: Callable) -> String:
		var best := ""
		var bv := -1.0e9
		for p in ps:
			var v: float = score_fn.call(p)
			if v > bv:
				bv = v
				best = p.player_id
		return best if bv > 0.0 else ""
	var cands := [
		["MOST ROT", pick.call(func(p): return float(p.rot))],
		["GRAHAM'S FAVOURITE", pick.call(func(p): return float(d.rel(p.player_id).get("favourite", 0.0)) + 0.01 * p.score / 1000.0)],
		["FASTEST FINGER", pick.call(func(p): return 30.0 - float(d.stats(p.player_id).get("fastest", 999.0)))],
		["GRAHAM'S DISAPPOINTMENT", pick.call(func(p): return float(d.rel(p.player_id).get("disappointment", 0.0)) + float(d.rel(p.player_id).get("irritant", 0.0)))],
	]
	awards = cands.filter(func(c): return c[1] != "").slice(0, 3)
	var t := say_at(0.3, "graham", "awards_intro") + 0.3
	for i in awards.size():
		var a: Array = awards[i]
		var title: String = a[0]
		var pid: String = a[1]
		at(t, func(): session.emit_tv({"e": "award", "title": title, "pid": pid, "index": i}))
		t = say_at(t + 0.4, "graham", "award_given", {"pid": pid, "answer": title}) + 0.8
	var st: Array = session.standings()
	if not st.is_empty() and int(st[0].score) > 0 and (st.size() < 2 or int(st[0].score) != int(st[1].score)):
		var prize: String = PRIZES[d.rng.randi_range(0, PRIZES.size() - 1)]
		var wpid: String = st[0].pid
		at(t, func(): session.emit_tv({"e": "award", "title": "TONIGHT'S STAR PRIZE", "pid": wpid, "prize": prize.to_upper(), "index": awards.size()}))
		t = say_at(t + 0.4, "graham", "prize", {"pid": wpid, "answer": prize}) + 1.0
	sub = "done"
	phase_end = t + 1.0


func screen_for(player: PlayerState) -> Dictionary:
	if mode == "poll" and sub == "vote":
		if votes.has(player.player_id):
			return {"screen": "wv_wait", "data": {"header": "VIEWER POLL", "caption": "THANK YOU FOR YOUR OPINION. IT HAS BEEN NOTED."}}
		return {"screen": "wv_vote", "data": {"qid": qid, "header": "VIEWER POLL", "ask": str(item.get("prompt", "")), "options": item.get("options", []),
			"own": -1, "remaining_ms": int(maxf(0.0, phase_end - elapsed) / maxf(session.time_scale, 0.001) * 1000.0)}}
	return {"screen": "watch", "data": {"caption": "PLEASE WATCH YOUR TELEVISION"}}
