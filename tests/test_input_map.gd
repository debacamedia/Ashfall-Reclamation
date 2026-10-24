extends "res://tests/test_case.gd"
## Checks that every action the player uses exists in the Input Map and that
## pressing its key actually triggers the action.

const REQUIRED := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"jump": KEY_SPACE, "sprint": KEY_SHIFT, "crouch": KEY_C, "pause": KEY_ESCAPE,
	"toggle_debug": KEY_F3, "reload": KEY_R, "interact": KEY_E, "inventory": KEY_TAB, "use_medkit": KEY_H,
}


func test_actions_exist() -> void:
	for action: String in REQUIRED:
		check(InputMap.has_action(action), "missing input action: " + action)


func test_keys_trigger_actions() -> void:
	for action: String in REQUIRED:
		var press := InputEventKey.new()
		press.physical_keycode = REQUIRED[action]
		press.pressed = true
		check(InputMap.event_is_action(press, action), "%s does not trigger '%s'" % [OS.get_keycode_string(REQUIRED[action]), action])


func test_ctrl_also_crouches() -> void:
	var press := InputEventKey.new()
	press.physical_keycode = KEY_CTRL
	press.pressed = true
	check(InputMap.event_is_action(press, "crouch"), "Ctrl should also crouch")


func test_left_mouse_fires() -> void:
	check(InputMap.has_action("fire"), "missing input action: fire")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	check(InputMap.event_is_action(click, "fire"), "left mouse button should trigger 'fire'")


func test_right_mouse_aims() -> void:
	check(InputMap.has_action("aim"), "missing input action: aim")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	check(InputMap.event_is_action(press, "aim"), "right mouse button should aim")
