extends SceneTree
## Headless test runner.
##
## Run from the project folder:
##   godot --headless --path . -s res://tests/test_runner.gd
## (On macOS, `godot` is /Applications/Godot.app/Contents/MacOS/Godot.)
## Exit code is 0 when every test passes, 1 otherwise.
##
## A test fails if any check() fails OR if any script error is logged while it
## runs (a crashed test must never count as a pass).

const SUITES := [
	"res://tests/test_input_map.gd",
	"res://tests/test_player_controller.gd",
	"res://tests/test_health_component.gd",
	"res://tests/test_hitscan_weapon.gd",
	"res://tests/test_target_dummy.gd",
	"res://tests/test_player_health.gd",
	"res://tests/test_raider.gd",
	"res://tests/test_interaction.gd",
	"res://tests/test_inventory.gd",
	"res://tests/test_aim_and_ladders.gd",
	"res://tests/test_salvage.gd",
	"res://tests/test_save.gd",
	"res://tests/test_weapons.gd",
	"res://tests/test_crafting.gd",
	"res://tests/test_gun_crafting.gd",
	"res://tests/test_regions.gd",
	"res://tests/test_art_pack.gd",
	"res://tests/test_art_pack2.gd",
	"res://tests/test_audio.gd",
	"res://tests/test_outpost_17.gd",
	"res://tests/test_construction.gd",
	"res://tests/test_art_pack3.gd",
	"res://tests/test_early_zone.gd",
	"res://tests/test_sites.gd",
	"res://tests/test_performance.gd",
	"res://tests/test_gear_and_guns.gd",
	"res://tests/test_spare_guns.gd",
	"res://tests/test_backpacks.gd",
	"res://tests/test_map.gd",
	"res://tests/test_truck.gd",
	"res://tests/test_settlement.gd",
]


## Records engine and script errors logged while a test runs.
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors.append("%s (%s:%d %s) %s" % [code, file.get_file(), line, function, rationale])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var passed := 0
	var failed := 0
	# Optional filter: godot ... -s res://tests/test_runner.gd -- ladder
	# runs only suites or tests whose name contains "ladder".
	var only := " ".join(OS.get_cmdline_user_args())
	for path in SUITES:
		var script := load(path) as GDScript
		print("\n== %s" % path.get_file())
		if script == null or not script.can_instantiate():
			failed += 1
			print("  FAIL  (suite didn't load: parse error?)")
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			if only != "" and not (only in name or only in path.get_file()):
				continue
			catcher.errors.clear()
			var suite: Node = script.new()
			root.add_child(suite)
			await Callable(suite, name).call()
			var failures: PackedStringArray = suite.failures.duplicate()
			for e in catcher.errors:
				failures.append("ERROR: " + e)
			if failures.is_empty():
				passed += 1
				print("  PASS  %s" % name)
			else:
				failed += 1
				print("  FAIL  %s" % name)
				for f in failures:
					print("        - %s" % f)
			suite.queue_free()
			await process_frame
	OS.remove_logger(catcher)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
