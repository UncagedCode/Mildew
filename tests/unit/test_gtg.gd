extends MildewTest
## Guess the Genitals (CP3): animal-only enforcement, licensed media, pacing (accessible first,
## decoys capped and never first), final question value, Rot, repeat-animal callback.

const SCALE := 12.0


func _harness(tag: String, seed: int = 9001, played := 9) -> SimHarness:
	var store := temp_store(tag)
	store.installation.broadcasts_played = played
	var h := SimHarness.new(cfg(), store, content(), seed, SCALE)
	h.session.director.force["game"] = "guess_the_genitals"
	return h


func test_content_is_animal_only_and_licensed() -> void:
	var items := content().query("guess_the_genitals")
	check(items.size() >= 10, "Guess the Genitals items present (%d)" % items.size())
	for it in items:
		check(["animal", "decoy"].has(it.kingdom_class), "%s classified" % it.id)
		check(str(it.taxon) != "" and not str(it.taxon).to_lower().contains("homo"), "%s names a non-human taxon" % it.id)
		check(not (it.media as Array).is_empty() and str(it.media[0].licence) != "", "%s has licence metadata" % it.id)
		check(ResourceLoader.exists(str(it.image)), "%s image imported" % it.id)
		check(not (it.sources as Array).is_empty(), "%s has a sourced fact" % it.id)
	check(items.filter(func(i): return i.decoy).size() >= 2, "'Genital or Something Else?' decoys present")


func test_validator_enforces_animal_only() -> void:
	var v := ContentValidator.new()
	var bad := ContentDB.new()
	var base := {"enabled": true, "quality_status": "draft", "familiarity_tier": 1, "content_tags": ["factual"], "min_players": 2, "max_players": 8,
		"prompt": "WHOSE IS IT?", "options": ["a", "b", "c", "d"], "correct": 0, "fact": "f", "image": "res://assets/content/gtg/walrus.jpg",
		"media": [{"asset_path": "x", "source": "s", "licence": "CC0", "approval_status": "approved"}],
		"sources": [{"title": "t", "publisher_or_organisation": "p", "reference": "r", "supported_claim": "c"}]}
	var human := base.duplicate(true)
	human.merge({"id": "h1", "taxon": "Homo sapiens", "kingdom_class": "animal"})
	var tagged := base.duplicate(true)
	tagged.merge({"id": "h2", "taxon": "Equus", "kingdom_class": "animal"})
	tagged.content_tags = ["factual", "human"]
	var nometa := base.duplicate(true)
	nometa.merge({"id": "h3", "taxon": "", "kingdom_class": "plant"})
	nometa.media = []
	bad.add_pack({"pack_id": "bad", "content_kind": "guess_the_genitals", "_path": "bad.json", "items": [human, tagged, nometa]})
	check(not v.validate(bad), "bad Guess the Genitals items rejected")
	var j := "\n".join(v.errors)
	for frag in ["human anatomy is not allowed", "forbidden tag 'human'", "missing taxon", "kingdom_class must be", "image without media/licence metadata"]:
		check(j.contains(frag), "validator catches: %s" % frag)


func test_pacing_decoys_and_final() -> void:
	for seed in [1, 2, 3, 4, 5]:
		var d := Director.new(content(), seed)
		d.cfg = cfg()
		d.begin_session({"broadcasts_played": 12}, "standard_transmission")
		var plan := d.plan_game("guess_the_genitals", 4)
		var qs := plan.filter(func(s): return s.kind == "question")
		check(qs.size() >= 6, "a proper game (%d questions)" % qs.size())
		check(not bool(qs[0].item.get("decoy", false)), "never opens on a decoy (seed %d)" % seed)
		check(qs.filter(func(s): return s.item.get("decoy", false)).size() <= 2, "decoys capped")
		check(bool(qs[-1].final) and float(qs[-1].multiplier) >= 1.5, "FINAL GENITAL worth more")
		var first_real: Array = qs.filter(func(s): return not s.item.get("decoy", false))
		check(float(first_real[0].item.get("weirdness", 1)) <= float(first_real[-1].item.get("weirdness", 1)), "accessible before bizarre")


func test_full_game_with_bots() -> void:
	var h := _harness("gtg_full")
	var a := h.add_bot("Aaron", "horse", 1)
	var b := h.add_bot("Grace", "high_accuracy", 2)
	a.auto_start_at_count = 2
	check(h.run_until(func(): return h.session.phase == SessionServer.Phase.ENDED, 600.0), "show with Guess the Genitals completes")
	var shows := h.events_of("question_show").filter(func(e): return e.game_id == "guess_the_genitals")
	check(shows.size() >= 6, "Guess the Genitals played (%d)" % shows.size())
	check(shows.all(func(e): return str(e.image) != "" and e.layout == "image"), "every question shows a specimen")
	check(bool(shows[-1].final), "last one is the FINAL GENITAL")
	var grace: PlayerState = h.session.players[b.player_id]
	check(grace.score > 0, "accurate player scores")
	check(grace.rot >= 0, "Rot is tracked")
	check(h.events_of("reveal").filter(func(e): return e.game_id == "guess_the_genitals").all(func(e): return str(e.fact) != ""), "every reveal carries a fact")
