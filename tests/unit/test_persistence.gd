extends MildewTest
## Versioned saves, migration, reset scopes, installation seed.


func test_save_load_roundtrip() -> void:
	var s := temp_store("rt")
	var seed: String = s.installation.installation_seed
	check(seed.length() == 16, "installation seed generated")
	s.create_profile("Aaron", "Aaron", {"hair": 1})
	s.save_profiles()
	s.set_setting("interference", "supervised_transmission")
	var r := SaveStore.new(s.base_dir)
	r.load_all()
	check_eq(r.profiles.size(), 1, "profile reloads")
	check_eq(r.installation.installation_seed, seed, "installation seed persists")
	check_eq(r.get_setting("interference"), "supervised_transmission", "setting persists")
	check_eq(int(r.installation.schema_version), SaveStore.SCHEMA_VERSION, "schema version stored")


func test_migration_v0_profiles() -> void:
	var dir := "user://test_saves/mig_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("profiles.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"profiles": [{"profile_id": "old1", "display_name": "Neil", "custom_future_field": 7}]}))
	f.close()
	var s := SaveStore.new(dir)
	s.load_all()
	var p: Dictionary = s.profiles.get("old1", {})
	check(not p.is_empty(), "legacy profile loaded")
	check_eq(p.get("speech_name"), "Neil", "speech_name backfilled")
	check_eq(int(p.get("lifetime_rot", -1)), 0, "lifetime_rot backfilled")
	check_eq(int(p.get("custom_future_field", 0)), 7, "unknown fields preserved")
	check(FileAccess.file_exists(dir.path_join("profiles.json.v0.bak")), "backup written before migration")
	check(s.last_migration_log.size() >= 1, "migration logged")


func test_newer_schema_preserved() -> void:
	var dir := "user://test_saves/newer_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("installation.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema_version": 99, "installation_seed": "abc", "mystery": true}))
	f.close()
	var s := SaveStore.new(dir)
	s.load_all()
	check_eq(s.installation.get("installation_seed"), "abc", "newer-schema save not wiped")
	check(s.installation.get("mystery", false), "newer fields kept")


func test_reset_scopes() -> void:
	var s := temp_store("reset")
	s.create_profile("Aaron", "Aaron", {})
	s.save_profiles()
	s.installation.broadcasts_played = 5
	s.save_installation()
	var seed: String = s.installation.installation_seed
	s.reset_broadcast_history()
	check_eq(s.profiles.size(), 1, "reset broadcast history keeps players")
	check_eq(int(s.installation.broadcasts_played), 0, "broadcast history cleared")
	check_eq(s.installation.installation_seed, seed, "seed kept on broadcast-history reset")
	s.reset_players()
	check_eq(s.profiles.size(), 0, "reset players clears profiles")
	s.create_profile("Sarah", "Sarah", {})
	s.reset_mildew()
	check_eq(s.profiles.size(), 0, "full reset clears profiles")
	check(s.installation.installation_seed != seed, "full reset creates a fresh installation seed")


func test_show_updates_profiles_and_installation() -> void:
	var store := temp_store("showsave")
	var c := cfg()
	var s := SessionServer.new(c, store, content(), 77)
	s.time_scale = 12.0
	s.open()
	var conns: Array = []
	for n in ["Aaron", "Sarah"]:
		var cid := s.connect_client({"transport": "ws"})
		conns.append(cid)
		s.receive_text(cid, JSON.stringify({"t": "hello", "v": 1, "key": s.join_key}))
		s.receive_text(cid, JSON.stringify({"t": "create_profile", "name": n}))
	check(s.start_show(), "show starts from TV remote path")
	var t := 0.0
	while s.phase == SessionServer.Phase.SHOW and t < 400.0:
		for cid in conns:
			s.receive_text(cid, JSON.stringify({"t": "ping", "id": 1}))
		s.tick(0.1)
		t += 0.1
	check_eq(s.phase, SessionServer.Phase.ENDED, "show ended")
	check_eq(int(store.installation.broadcasts_played), 1, "broadcast counted")
	check_eq((store.installation.recent_content_history as Array).size(), 3, "content history recorded")
	for prof in store.profiles.values():
		check_eq(int(prof.games_played), 1, "games_played incremented for %s" % prof.display_name)
