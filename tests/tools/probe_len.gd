extends SceneTree
## Prints simulated show lengths and game lists (dev probe).
func _initialize() -> void:
	var cfg := MildewConfig.load_default()
	var content := ContentDB.load_default()
	for seed in [1, 2, 3, 4]:
		var store := SaveStore.new("user://probe_%d_%d" % [seed, Time.get_ticks_msec()])
		store.load_all()
		store.installation.broadcasts_played = 6
		var h := SimHarness.new(cfg, store, content, seed, 20.0)
		var n: int = [2, 4, 6, 8][seed - 1]
		var a := h.add_bot("A", "fast_random", seed * 10)
		for i in n - 1:
			h.add_bot("B%d" % i, ["high_accuracy", "cautious", "fast_random"][i % 3], seed * 10 + i + 1)
		a.auto_start_at_count = n
		h.run_until(func(): return h.session.phase == SessionServer.Phase.ENDED, 3000.0)
		print("PROBE players=%d minutes=%.1f games=%s" % [n, h.session.session_time / 60.0, str(h.session.director.games_this_show)])
	quit()
