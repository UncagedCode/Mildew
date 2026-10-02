class_name MildewTest
extends RefCounted
## Minimal test base. Test files live in res://tests/unit/, extend MildewTest and define
## `func test_*()` methods. Run: godot --headless --path . --script res://tests/run_tests.gd

var failures: Array[String] = []
var checks := 0
var current := ""


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append("%s: %s" % [current, msg])


func check_eq(actual, expected, msg: String) -> void:
	checks += 1
	if typeof(actual) != typeof(expected) and not (typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]):
		failures.append("%s: %s (type %s != %s; %s vs %s)" % [current, msg, type_string(typeof(actual)), type_string(typeof(expected)), str(actual), str(expected)])
	elif actual != expected:
		failures.append("%s: %s (got %s, expected %s)" % [current, msg, str(actual), str(expected)])


## Fresh, isolated save directory per test.
func temp_store(tag: String) -> SaveStore:
	var dir := "user://test_saves/%s_%d" % [tag, Time.get_ticks_usec()]
	var s := SaveStore.new(dir)
	s.load_all()
	return s


func cfg() -> MildewConfig:
	return MildewConfig.load_default()


func content() -> ContentDB:
	return ContentDB.load_default()
