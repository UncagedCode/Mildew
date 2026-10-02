extends SceneTree
## Headless test runner.
##   godot --headless --path . --script res://tests/run_tests.gd [-- --filter <substring>]
## Exit code 0 = all passed. Writes tests/output/unit_results.json.

func _initialize() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	var i := args.find("--filter")
	if i != -1 and i + 1 < args.size():
		filter = args[i + 1]
	var total_checks := 0
	var total_tests := 0
	var all_failures: Array = []
	var per_file := {}
	var dir := DirAccess.open("res://tests/unit")
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var started := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load("res://tests/unit/" + f)
		var inst = script.new()
		var methods: Array = []
		for m in script.get_script_method_list():
			if str(m.name).begins_with("test_") and not methods.has(m.name):
				methods.append(m.name)
		var file_fail := 0
		for m in methods:
			if filter != "" and not ("%s.%s" % [f, m]).contains(filter):
				continue
			inst.current = "%s.%s" % [f.get_basename(), m]
			var before: int = inst.failures.size()
			var t0 := Time.get_ticks_msec()
			await inst.call(m)
			total_tests += 1
			var ok: bool = inst.failures.size() == before
			if not ok:
				file_fail += 1
			print("%s %s (%d ms)" % ["PASS" if ok else "FAIL", inst.current, Time.get_ticks_msec() - t0])
			for k in range(before, inst.failures.size()):
				print("      ", inst.failures[k])
		total_checks += inst.checks
		all_failures.append_array(inst.failures)
		per_file[f] = {"failed_tests": file_fail, "checks": inst.checks}
	var summary := {"tests": total_tests, "checks": total_checks, "failures": all_failures,
		"files": per_file, "duration_ms": Time.get_ticks_msec() - started, "godot": Engine.get_version_info().string}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var out := FileAccess.open("res://tests/output/unit_results.json", FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify(summary, "\t"))
	print("\n%d tests, %d checks, %d failures" % [total_tests, total_checks, all_failures.size()])
	quit(0 if all_failures.is_empty() else 1)
