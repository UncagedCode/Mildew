class_name SegWriteVote
extends Segment
## Write-then-vote engine for Mildew Survey and Mouthfeel (CP4; docs/04 §3 and §8).
## Server-authoritative: phones only submit text and votes; the server assembles the anonymous
## answer board (player answers + archive filler for small groups + Graham's own entry), forbids
## self-votes, scores, and archives good player answers locally for future reuse.
##
## desc.mode:
##   "popularity"  vote for the best answer (Survey default; Mouthfeel with a category)
##   "archive"     spot which answer came from the Mildew archive
##   "who_said"    guess who wrote the featured answer
##   "chain"       Make It Worse: players take turns making a base item worse, then rate the result
## Sub-phases: intro -> write -> (chain steps) -> vote -> reveal.

const MAX_TEXT := 80
const MAX_CHAIN_TEXT := 60

var item: Dictionary
var game_id := ""
var mode := "popularity"
var category := ""            # Mouthfeel vote category (funniest, most disgusting, ...)
var title := ""
var round_no := 0
var round_of := 0
var graham_answer := false    # Graham anonymously enters (Mouthfeel)
var multiplier := 1.0
var qid := ""
var sub := "intro"
var participants: Array = []
var written := {}             # pid -> text
var answers: Array = []       # [{text, shown, author: pid|"archive"|"graham", match_key}]
var votes := {}               # pid -> answer index (or player index for who_said)
var ratings := {}             # chain: pid -> 1..5
var featured := -1            # who_said: answer index being guessed
var chain_order: Array = []
var chain_step := 0
var chain_text := ""
var chain_parts: Array = []   # [{pid, text}]
var deltas := {}
var altered := -1             # rare Graham alteration (answer index), for the reveal line
var discarded := false
var phase_end := 0.0
var write_s := 45.0
var vote_s := 25.0
var chain_s := 25.0


func _init(desc: Dictionary) -> void:
	kind = "write_vote"
	item = desc.get("item", {})
	game_id = str(desc.get("game_id", ""))
	mode = str(desc.get("mode", "popularity"))
	category = str(desc.get("category", ""))
	title = str(desc.get("title", ""))
	round_no = int(desc.get("round", 0))
	round_of = int(desc.get("of", 0))
	graham_answer = bool(desc.get("graham_answer", false))
	multiplier = float(desc.get("multiplier", 1.0))
	allows_late_join_after = false


func start() -> void:
	session.question_counter += 1
	qid = "%s#%d" % [str(item.get("id", "w")), session.question_counter]
	participants = session.active_player_ids()
	write_s = session.cfg.f("write_vote.write_seconds", 45.0)
	vote_s = session.cfg.f("write_vote.vote_seconds", 25.0)
	chain_s = session.cfg.f("write_vote.chain_step_seconds", 25.0)
	duration = 1.0e9
	session.director.used_content[str(item.get("id", ""))] = true
	session.emit_tv({"e": "wv_show", "qid": qid, "game_id": game_id, "mode": mode, "category": category, "title": title,
		"prompt": _prompt(), "round": round_no, "of": round_of, "image": item.get("image", "")})
	var t := say_at(0.3, "graham", _cat("ask"))
	at(maxf(2.5, t + 0.3), _open_write)
	session.push_screens()


func _prompt() -> String:
	return str(item.get("prompt", item.get("base", "")))


func _cat(suffix: String) -> String:
	return ("mf_" if game_id == "mouthfeel" else "sv_") + suffix


func _open_write() -> void:
	if mode == "chain":
		_start_chain()
		return
	sub = "write"
	phase_end = elapsed + write_s
	session.emit_tv({"e": "wv_write_open", "qid": qid, "window": write_s, "of": participants.size()})
	session.push_screens()


func update(dt: float) -> void:
	elapsed += dt
	while not _timeline.is_empty() and _timeline[0].at <= elapsed:
		_timeline.pop_front().fn.call()
	match sub:
		"write":
			if elapsed >= phase_end or _all_in(written):
				_close_write()
		"chain":
			if elapsed >= phase_end or written.has(_chain_pid()):
				_chain_next()
		"vote":
			if elapsed >= phase_end or _all_in(votes if mode != "chain" else ratings):
				_reveal()
		"reveal":
			if elapsed >= phase_end and _timeline.is_empty():
				done = true


func _present() -> Array:
	return participants.filter(func(pid): return session.players.has(pid) and session.players[pid].is_active())


func _all_in(d: Dictionary) -> bool:
	var skip := str(answers[featured].author) if (sub == "vote" and mode == "who_said" and featured >= 0) else ""
	for pid in _present():
		if pid != skip and not d.has(pid):
			return false
	return true


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

static func clean_text(raw: String, max_len: int) -> String:
	var out := ""
	for i in raw.length():
		var cp := raw.unicode_at(i)
		if cp < 32 or cp == 127 or (cp >= 0x200B and cp <= 0x200F) or cp == 0xFEFF:
			continue
		out += raw[i]
	out = " ".join(out.strip_edges().split(" ", false))
	return out.substr(0, max_len)


## Local, offline match normalisation (docs/04 §3 Match): case, punctuation, articles, plurals.
static func match_key(text: String) -> String:
	var t := text.to_lower()
	var clean := ""
	for ch in t:
		clean += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == " " else " "
	var words: Array = []
	for w in clean.split(" ", false):
		if w in ["a", "an", "the", "some", "my", "your", "of"]:
			continue
		if w.length() > 3 and w.ends_with("s") and not w.ends_with("ss"):
			w = w.substr(0, w.length() - 1)
		words.append(w)
	return " ".join(words)


func _close_write() -> void:
	sub = "assemble"
	for pid in written:
		answers.append({"text": written[pid], "shown": written[pid], "author": pid, "match_key": match_key(written[pid])})
	# Rare Graham interference with an answer (docs/04 §3 "Rare manipulation"; dev-forceable).
	var force := str(session.director.force.get("alter_answer", ""))
	if (force != "" and not answers.is_empty()) or (answers.size() >= 3 and session.director.rng.randf() < session.cfg.f("write_vote.alteration_chance", 0.02)):
		session.director.force.erase("alter_answer")
		var idx: int = session.director.rng.randi_range(0, answers.size() - 1)
		if force == "discard":
			answers.remove_at(idx)
			discarded = true
		else:
			answers[idx].shown = "GRAHAM MILDEW"
			altered = idx
		session.director.log_decision("AnswerTampering", "discard" if discarded else "rename", ["forced" if force != "" else "rare roll"])
	if graham_answer:
		var ga := _pick_unused(item.get("graham_answers", []))
		if ga != "":
			answers.append({"text": ga, "shown": ga, "author": "graham", "match_key": match_key(ga)})
	var need := maxi(int(item.get("min_answers", 4)), 3) if mode != "who_said" else 3
	if mode == "archive":
		need = maxi(need, answers.size() + 1)
	var pool := _archive_pool()
	while answers.size() < need and not pool.is_empty():
		var a: String = pool.pop_back()
		answers.append({"text": a, "shown": a, "author": "archive", "match_key": match_key(a)})
	session.director.shuffle(answers)
	if mode == "who_said":
		var mine: Array = range(answers.size()).filter(func(i): return session.players.has(answers[i].author))
		featured = mine[session.director.rng.randi_range(0, mine.size() - 1)] if not mine.is_empty() else -1
	_open_vote()


func _pick_unused(arr: Array) -> String:
	if arr.is_empty():
		return ""
	return str(arr[session.director.rng.randi_range(0, arr.size() - 1)])


## Authored archive answers + locally archived past player answers (never attributed).
func _archive_pool() -> Array:
	var pool: Array = (item.get("archive", []) as Array).duplicate()
	var local: Dictionary = session.store.installation.get("archive_answers", {})
	for a in local.get(str(item.get("id", "")), []):
		if not pool.has(a):
			pool.append(a)
	var taken := answers.map(func(x): return x.match_key)
	pool = pool.filter(func(a): return not taken.has(match_key(str(a))))
	session.director.shuffle(pool)
	return pool


# ---------------------------------------------------------------------------
# Make It Worse chain
# ---------------------------------------------------------------------------

func _start_chain() -> void:
	chain_order = _present()
	session.director.shuffle(chain_order)
	chain_text = str(item.get("base", item.get("prompt", "")))
	chain_step = 0
	sub = "chain"
	phase_end = elapsed + chain_s
	session.emit_tv({"e": "wv_chain", "qid": qid, "text": chain_text, "step": 0, "of": chain_order.size(), "pid": _chain_pid()})
	session.push_screens()


func _chain_pid() -> String:
	return str(chain_order[chain_step]) if chain_step < chain_order.size() else ""


func _chain_next() -> void:
	var pid := _chain_pid()
	if written.has(pid):
		chain_parts.append({"pid": pid, "text": written[pid]})
		chain_text = "%s, %s" % [chain_text, written[pid]]
	chain_step += 1
	while chain_step < chain_order.size() and not (session.players.has(_chain_pid()) and session.players[_chain_pid()].is_active()):
		chain_step += 1
	if chain_step >= chain_order.size():
		sub = "vote"
		phase_end = elapsed + vote_s
		session.emit_tv({"e": "wv_chain_final", "qid": qid, "text": chain_text, "window": vote_s, "of": _present().size()})
		say_at(0.2, "graham", "mf_chain_final")
		session.push_screens()
		return
	phase_end = elapsed + chain_s
	session.emit_tv({"e": "wv_chain", "qid": qid, "text": chain_text, "step": chain_step, "of": chain_order.size(), "pid": _chain_pid()})
	session.push_screens()


# ---------------------------------------------------------------------------
# Voting
# ---------------------------------------------------------------------------

func _open_vote() -> void:
	sub = "vote"
	phase_end = elapsed + vote_s
	var board := answers.map(func(a): return a.shown)
	session.emit_tv({"e": "wv_vote_open", "qid": qid, "answers": board, "window": vote_s, "mode": mode,
		"featured": featured, "of": _present().size(), "category": category})
	if discarded:
		say_at(0.2, "graham", "wv_discarded")
	session.push_screens()


func _vote_options_for(pid: String) -> Array:
	if mode == "who_said":
		return participants.map(func(p): return session.players[p].display_name if session.players.has(p) else "?")
	return answers.map(func(a): return a.shown)


func handle_action(player: PlayerState, msg: Dictionary) -> String:
	var t := str(msg.get("t"))
	if str(msg.get("q", "")) != qid:
		return Protocol.E_STALE
	if not participants.has(player.player_id):
		return Protocol.E_NOT_PARTICIPANT
	match t:
		Protocol.C_SUBMIT:
			var raw = Protocol.get_str(msg, "text", 400)
			if raw == null:
				return Protocol.E_BAD_PAYLOAD
			var text := clean_text(str(raw), MAX_CHAIN_TEXT if mode == "chain" else MAX_TEXT)
			if text == "":
				return Protocol.E_BAD_PAYLOAD
			if sub == "write":
				if written.has(player.player_id):
					return Protocol.E_ALREADY_ANSWERED
				written[player.player_id] = text
				session.emit_tv({"e": "wv_progress", "qid": qid, "pid": player.player_id, "count": written.size(), "of": _present().size()})
				return ""
			if sub == "chain":
				if _chain_pid() != player.player_id:
					return Protocol.E_STALE
				written[player.player_id] = text
				return ""
			return Protocol.E_STALE
		Protocol.C_VOTE:
			if sub != "vote":
				return Protocol.E_STALE
			var c = Protocol.get_int(msg, "c")
			if c == null:
				return Protocol.E_BAD_PAYLOAD
			if mode == "chain":
				if ratings.has(player.player_id):
					return Protocol.E_ALREADY_ANSWERED
				if int(c) < 1 or int(c) > 5:
					return Protocol.E_BAD_PAYLOAD
				ratings[player.player_id] = int(c)
			else:
				if votes.has(player.player_id):
					return Protocol.E_ALREADY_ANSWERED
				var n := _vote_options_for(player.player_id).size()
				if int(c) < 0 or int(c) >= n:
					return Protocol.E_BAD_PAYLOAD
				if mode == "popularity" and str(answers[int(c)].author) == player.player_id and not bool(item.get("self_vote", false)):
					return Protocol.E_SELF_VOTE
				if mode == "who_said" and featured >= 0 and str(answers[featured].author) == player.player_id:
					return Protocol.E_SELF_VOTE   # the author sits this one out
				votes[player.player_id] = int(c)
			session.emit_tv({"e": "wv_vote_progress", "qid": qid, "pid": player.player_id, "count": (ratings if mode == "chain" else votes).size(), "of": _present().size()})
			return ""
	return Protocol.E_INVALID_STATE


# ---------------------------------------------------------------------------
# Reveal + scoring
# ---------------------------------------------------------------------------

func _reveal() -> void:
	sub = "reveal"
	deltas.clear()
	for pid in participants:
		deltas[pid] = 0
	var per_vote := int(round(session.cfg.f("write_vote.points_per_vote", 500.0) * multiplier))
	var tally: Array = []
	tally.resize(answers.size())
	tally.fill(0)
	var winner := -1
	var lines: Array = []
	match mode:
		"chain":
			var total := 0
			for pid in ratings:
				total += int(ratings[pid])
			var contributors := chain_parts.map(func(p): return p.pid)
			var share := int(round(total * session.cfg.f("write_vote.chain_points_per_star", 60.0) * multiplier / maxf(1.0, contributors.size()) / 10.0)) * 10 if not contributors.is_empty() else 0
			for pid in contributors:
				_award(pid, share)
			var avg := float(total) / maxf(1.0, ratings.size())
			if avg >= 4.0:
				for pid in contributors:
					session.players[pid].add_rot(1)
			lines.append(["mf_chain_good" if avg >= 3.0 else "mf_chain_bad", {}])
			session.emit_tv({"e": "wv_reveal", "qid": qid, "mode": mode, "text": chain_text, "parts": chain_parts,
				"ratings": ratings, "average": snappedf(avg, 0.1), "deltas": deltas, "standings": session.standings()})
		"archive":
			var arch := range(answers.size()).filter(func(i): return answers[i].author == "archive")
			for pid in votes:
				if arch.has(int(votes[pid])):
					_award(pid, per_vote)
			for i in answers.size():
				tally[i] = votes.values().count(i)
			_emit_board_reveal(tally, -1, "archive")
			lines.append(["sv_archive_reveal", {}])
		"who_said":
			var author := str(answers[featured].author) if featured >= 0 else ""
			var author_idx := participants.find(author)
			var right := 0
			for pid in votes:
				if int(votes[pid]) == author_idx:
					_award(pid, per_vote)
					right += 1
			# the author is rewarded for being unguessable
			if author != "" and session.players.has(author):
				_award(author, int(per_vote * 0.5) * (votes.size() - right))
			session.emit_tv({"e": "wv_reveal", "qid": qid, "mode": mode, "answers": answers.map(_public_answer), "featured": featured,
				"votes": votes, "guess_names": _vote_options_for(""), "author_index": author_idx, "deltas": deltas, "standings": session.standings()})
			lines.append(["sv_who_said_reveal", {"pid": author}])
		_:
			for pid in votes:
				tally[int(votes[pid])] += 1
			for i in answers.size():
				var a: Dictionary = answers[i]
				if session.players.has(a.author):
					_award(a.author, tally[i] * per_vote)
				if winner < 0 or tally[i] > tally[winner]:
					winner = i
			if winner >= 0 and tally[winner] == 0:
				winner = -1
			# Match bonus: independent players writing the same simple thing.
			var keys := {}
			for a in answers:
				if session.players.has(a.author) and a.match_key != "":
					if not keys.has(a.match_key):
						keys[a.match_key] = []
					keys[a.match_key].append(a.author)
			var matched := false
			for k in keys:
				if keys[k].size() >= 2:
					matched = true
					for pid in keys[k]:
						_award(pid, int(session.cfg.f("write_vote.match_bonus", 250.0)))
			# Graham's Choice (Mouthfeel): a modest bonus for one player answer he likes.
			var gchoice := -1
			if game_id == "mouthfeel":
				var cands := range(answers.size()).filter(func(i): return session.players.has(answers[i].author))
				if not cands.is_empty():
					cands.sort_custom(func(x, y): return float(session.director.rel(answers[x].author).get("favourite", 0.0)) > float(session.director.rel(answers[y].author).get("favourite", 0.0)))
					gchoice = cands[0] if session.director.rng.randf() < 0.7 else cands[session.director.rng.randi_range(0, cands.size() - 1)]
					_award(answers[gchoice].author, int(session.cfg.f("write_vote.graham_choice_bonus", 250.0)))
			_emit_board_reveal(tally, winner, "", gchoice)
			if altered >= 0:
				lines.append(["wv_altered", {"pid": str(answers[altered].author)}])
			if winner >= 0:
				var wa: String = str(answers[winner].author)
				if wa == "graham":
					lines.append(["wv_graham_won", {}])
				elif wa == "archive":
					lines.append(["wv_archive_won", {}])
				else:
					lines.append([_cat("winner"), {"pid": wa, "answer": answers[winner].text}])
					_archive_answer(answers[winner].text)
			else:
				lines.append([_cat("no_votes"), {}])
			if matched:
				lines.append(["wv_match", {}])
			if gchoice >= 0:
				lines.append(["mf_graham_choice", {"pid": str(answers[gchoice].author), "answer": answers[gchoice].text}])
	for pid in deltas:
		if session.players.has(pid):
			session.players[pid].history.append({"qid": qid, "content_id": item.get("id"), "points": deltas[pid], "kind": "write_vote"})
	session.push_screens()
	var t := 1.2
	for l in lines:
		t = say_at(t, "graham", l[0], l[1]) + 0.3
	phase_end = elapsed + maxf(session.cfg.f("write_vote.reveal_seconds", 8.0), t + 0.6)


func _award(pid: String, pts: int) -> void:
	if pts <= 0 or not session.players.has(pid):
		return
	session.players[pid].score += pts
	deltas[pid] = int(deltas.get(pid, 0)) + pts


func _public_answer(a: Dictionary) -> Dictionary:
	var who := str(a.author)
	return {"text": a.shown, "author": who if session.players.has(who) else who, "kind": "player" if session.players.has(who) else who}


func _emit_board_reveal(tally: Array, winner: int, highlight: String, gchoice: int = -1) -> void:
	session.emit_tv({"e": "wv_reveal", "qid": qid, "mode": mode, "answers": answers.map(_public_answer), "tally": tally,
		"winner": winner, "highlight": highlight, "graham_choice": gchoice, "votes": votes, "deltas": deltas, "standings": session.standings()})


## Good player answers join the local archive pool (unattributed, local only — docs/04 §3).
func _archive_answer(text: String) -> void:
	var store = session.store
	var arch: Dictionary = store.installation.get("archive_answers", {})
	var key := str(item.get("id", ""))
	var list: Array = arch.get(key, [])
	if not list.has(text):
		list.append(text)
	while list.size() > 12:
		list.pop_front()
	arch[key] = list
	store.installation.archive_answers = arch


# ---------------------------------------------------------------------------
# Phone screens
# ---------------------------------------------------------------------------

func screen_for(player: PlayerState) -> Dictionary:
	var pid := player.player_id
	if not participants.has(pid):
		return {"screen": "watch", "data": {"caption": "YOU WILL JOIN AT THE NEXT SEGMENT"}}
	var head := "%s · %d OF %d" % [title, round_no, round_of] if round_of > 0 else title
	var remaining := int(maxf(0.0, phase_end - elapsed) / maxf(session.time_scale, 0.001) * 1000.0)
	match sub:
		"intro", "assemble":
			return {"screen": "get_ready", "data": {"caption": "GET YOUR THUMBS READY", "header": head}}
		"write":
			if written.has(pid):
				return {"screen": "wv_wait", "data": {"header": head, "caption": "SUBMITTED. WAITING FOR THE OTHERS.", "mine": written[pid]}}
			return {"screen": "wv_write", "data": {"qid": qid, "header": head, "prompt": _prompt(), "max": MAX_TEXT, "remaining_ms": remaining,
				"total_ms": int(write_s / maxf(session.time_scale, 0.001) * 1000.0), "hint": str(item.get("hint", "")), "category": category}}
		"chain":
			if _chain_pid() == pid and not written.has(pid):
				return {"screen": "wv_write", "data": {"qid": qid, "header": head + " · MAKE IT WORSE", "prompt": chain_text, "max": MAX_CHAIN_TEXT,
					"remaining_ms": remaining, "total_ms": int(chain_s / maxf(session.time_scale, 0.001) * 1000.0),
					"hint": "ADD ONE HORRIBLE THING TO IT.", "chain": true}}
			var whose: String = session.players[_chain_pid()].display_name if session.players.has(_chain_pid()) else "SOMEBODY"
			return {"screen": "wv_wait", "data": {"header": head + " · MAKE IT WORSE", "caption": "%s IS MAKING IT WORSE." % whose.to_upper(), "mine": chain_text}}
		"vote":
			if mode == "chain":
				if ratings.has(pid):
					return {"screen": "wv_wait", "data": {"header": head, "caption": "RATING RECEIVED."}}
				return {"screen": "wv_rate", "data": {"qid": qid, "header": head, "text": chain_text, "remaining_ms": remaining}}
			if votes.has(pid):
				return {"screen": "wv_wait", "data": {"header": head, "caption": "VOTE RECEIVED."}}
			if mode == "who_said" and featured >= 0 and str(answers[featured].author) == pid:
				return {"screen": "wv_wait", "data": {"header": head, "caption": "THAT'S YOURS. KEEP A STRAIGHT FACE."}}
			var opts := _vote_options_for(pid)
			var own := -1
			if mode == "popularity" and not bool(item.get("self_vote", false)):
				for i in answers.size():
					if str(answers[i].author) == pid:
						own = i
			var ask: String = {"popularity": "VOTE FOR THE BEST" if category == "" else "VOTE: " + category.to_upper(),
				"archive": "WHICH ONE CAME FROM THE ARCHIVE?", "who_said": "WHO WROTE: \"%s\"?" % (answers[featured].shown if featured >= 0 else "")}.get(mode, "VOTE")
			return {"screen": "wv_vote", "data": {"qid": qid, "header": head, "ask": ask, "options": opts, "own": own, "remaining_ms": remaining}}
		_:
			return {"screen": "wv_result", "data": {"header": head, "points": int(deltas.get(pid, 0)), "score": player.score,
				"mine": str(written.get(pid, "")), "votes": _votes_for(pid)}}


func _votes_for(pid: String) -> int:
	var n := 0
	for i in answers.size():
		if str(answers[i].author) == pid:
			n += votes.values().count(i)
	return n


func tv_state() -> Dictionary:
	return {"kind": kind, "sub": sub, "qid": qid, "written": written.size(), "votes": votes.size(), "mode": mode}
