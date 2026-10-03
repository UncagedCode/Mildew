extends MildewTest
## Private phone interference (CP4; docs/03, CLAUDE.md §9): ephemeral, targeted, sparse,
## respects the transmission setting, never reaches the TV, never touches scores.

const SCALE := 12.0


func _director(mode: String, seed: int, played := 12) -> Director:
	var d := Director.new(content(), seed)
	d.cfg = cfg()
	d.begin_session({"broadcasts_played": played}, mode)
	return d


func _players(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"pid": "p%d" % i, "name": ["Aaron", "Grace", "Josh", "Donna", "Elijah"][i % 5]})
	return out


## A simulated 45-minute show: a phone moment every ~25 s.
func _soak(d: Director, n: int) -> Array:
	var got: Array = []
	var t := 0.0
	while t < 2700.0:
		t += 25.0
		d.show_time = t
		for k in d.tone.keys():
			d.tone[k] = maxf(0.0, float(d.tone[k]) - 0.03)
		got.append_array(d.interference.opportunity(["question_open", "write_open", "vote_open", "hole_stage", "boundary"][int(t / 25.0) % 5], {"players": _players(n)}))
	return got


func test_content_validates() -> void:
	var items := content().query("interference")
	check(items.size() >= 15, "private interference repertoire (%d)" % items.size())
	for t in [1, 2, 3]:
		check(items.any(func(i): return int(i.tier) == t), "tier %d payloads exist" % t)
	check(items.any(func(i): return i.target == "fragments"), "distributed fragments exist")
	check(items.any(func(i): return i.source == "unknown_impersonating_source"), "impersonation exists")
	var v := ContentValidator.new()
	var bad := ContentDB.new()
	bad.add_pack({"pack_id": "b", "content_kind": "interference", "_path": "b.json", "items": [
		{"id": "x1", "enabled": true, "quality_status": "draft", "tier": 2, "source": "ghost", "style": "overlay", "target": "single_phone",
			"texts": ["INCOMING CALL — SLIDE TO ANSWER"], "ms": 9000}]})
	check(not v.validate(bad), "bad payload rejected")
	var j := "\n".join(v.errors)
	for frag in ["unknown interference source", "ms must be", "must not imitate the phone's own call UI"]:
		check(j.contains(frag), "validator catches: %s" % frag)


func test_sparse_in_standard_and_some_sessions_quiet() -> void:
	var counts: Array = []
	for seed in range(1, 41):
		counts.append(_soak(_director("standard_transmission", seed), 4).size())
	var total := 0
	var quiet := 0
	for c in counts:
		total += c
		if c <= 1:
			quiet += 1
		check(c <= 12, "never spammy (a show got %d deliveries)" % c)
	var avg := float(total) / counts.size()
	print("      avg private deliveries per 45-min show: %.2f, quiet sessions %d/40" % [avg, quiet])
	check(avg > 0.3 and avg < 6.0, "maximum repertoire is not maximum frequency (avg %.2f)" % avg)
	check(quiet >= 4, "some sessions contain very little (%d/40)" % quiet)


func test_settings_respected() -> void:
	var clean := 0
	var supervised_bad := 0
	var supervised := 0
	for seed in range(1, 31):
		clean += _soak(_director("clean_transmission", seed), 4).size()
		var d := _director("supervised_transmission", seed)
		var got := _soak(d, 4)
		supervised += got.size()
		for entry in d.interference.fired_log:
			var it: Dictionary = content().get_item(str(entry.id))
			if int(it.tier) >= 2 or not ["production", "archive"].has(str(it.source)):
				supervised_bad += 1
	check_eq(clean, 0, "CLEAN TRANSMISSION suppresses private interference")
	check_eq(supervised_bad, 0, "SUPERVISED keeps only mild production/archive notes")
	var d2 := _director("clean_transmission", 5)
	d2.force["interfere"] = "p.help_me"
	check(d2.interference.opportunity("question_open", {"players": _players(3)}).is_empty(), "even a dev force can't override CLEAN")
	check(not d2.force.has("interfere"), "force consumed")


func test_distributed_fragments() -> void:
	var d := _director("standard_transmission", 9)
	d.force["interfere"] = "p.distributed_green_room"
	var got := d.interference.opportunity("boundary", {"players": _players(4)})
	check_eq(got.size(), 3, "three fragments, one contestant gets nothing")
	var pids := {}
	var texts := {}
	for g in got:
		pids[g.pid] = true
		texts[g.msg.text] = true
		check_eq(g.msg.t, Protocol.S_INTERFERE, "private message type")
	check_eq(pids.size(), 3, "each fragment to a different phone")
	check(texts.has("GREEN ROOM") and texts.has("OPEN IT"), "fragments delivered")


func test_other_player_reference_never_self() -> void:
	var d := _director("standard_transmission", 11)
	for k in 10:
		d.force["interfere"] = "p.about_other"
		d.interference.last_fired.clear()
		var got := d.interference.opportunity("vote_open", {"players": _players(3)})
		check_eq(got.size(), 1, "one recipient")
		var me: String = _players(3).filter(func(p): return p.pid == got[0].pid)[0].name.to_upper()
		var txt: String = got[0].msg.text
		check(not txt.contains(me) or txt.count(me) == 0, "never names the recipient (%s -> %s)" % [me, txt])


func test_live_delivery_is_private_and_ephemeral() -> void:
	var store := temp_store("intf_live")
	store.installation.broadcasts_played = 9
	var h := SimHarness.new(cfg(), store, content(), 3131, SCALE)
	h.session.director.force["game"] = "real_or_mildew"
	h.session.director.force["interfere"] = "p.ham"
	var a := h.add_bot("Aaron", "fast_random", 1)
	var b := h.add_bot("Grace", "fast_random", 2)
	var c := h.add_bot("Josh", "fast_random", 3)
	a.auto_start_at_count = 3
	check(h.run_until(func(): return a.interferences.size() + b.interferences.size() + c.interferences.size() > 0, 600.0), "forced private message delivered")
	var recv := [a, b, c].filter(func(x): return not x.interferences.is_empty())
	check_eq(recv.size(), 1, "only one phone saw it")
	var txt: String = recv[0].interferences[0].text
	check(txt.contains("HAM"), "the payload text: %s" % txt)
	for e in h.tv_events:
		check(not JSON.stringify(e).contains(txt), "never on the TV / TV event stream")
	var scores_before := h.session.standings()
	h.run_until(func(): return false, 2.0)
	check(not JSON.stringify(recv[0].last_screen).contains(txt), "not part of any screen state (unrecoverable)")
	check_eq(h.session.standings().size(), scores_before.size(), "scores untouched")
