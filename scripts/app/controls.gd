## Controls — InputMap actions with Java-style default bindings (physical keycodes, layout independent),
## user rebinding persisted in Settings "keybinds", conflict detection.
## Contract: setup() (idempotent), rebind(action, event), conflicts() -> Array, label(action) -> String.
class_name Controls

const DEFAULTS := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "jump": KEY_SPACE,
	"sneak": KEY_SHIFT, "sprint": KEY_CTRL, "inventory": KEY_E, "drop": KEY_Q, "swap_offhand": KEY_F,
	"chat": KEY_T, "command": KEY_SLASH, "player_list": KEY_TAB, "debug": KEY_F3, "perspective": KEY_F5,
	"hide_hud": KEY_F1, "screenshot": KEY_F2, "pause": KEY_ESCAPE, "fullscreen": KEY_F11,
	"attack": -MOUSE_BUTTON_LEFT, "use": -MOUSE_BUTTON_RIGHT, "pick_block": -MOUSE_BUTTON_MIDDLE,
	"hotbar_1": KEY_1, "hotbar_2": KEY_2, "hotbar_3": KEY_3, "hotbar_4": KEY_4, "hotbar_5": KEY_5,
	"hotbar_6": KEY_6, "hotbar_7": KEY_7, "hotbar_8": KEY_8, "hotbar_9": KEY_9,
}


static func _event_for(code: int) -> InputEvent:
	if code < 0:
		var m := InputEventMouseButton.new()
		m.button_index = -code as MouseButton
		return m
	var k := InputEventKey.new()
	k.physical_keycode = code as Key
	return k


static func setup() -> void:
	var custom: Dictionary = Settings.get_v("keybinds")
	for a in DEFAULTS:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
		else:
			InputMap.add_action(a)
		var code: int = int(custom.get(a, DEFAULTS[a]))
		InputMap.action_add_event(a, _event_for(code))


static func rebind(action: String, code: int) -> void:
	var custom: Dictionary = Settings.get_v("keybinds").duplicate()
	custom[action] = code
	Settings.set_v("keybinds", custom)
	Settings.save()
	setup()


static func reset_all() -> void:
	Settings.set_v("keybinds", {})
	Settings.save()
	setup()


static func code_of(action: String) -> int:
	var custom: Dictionary = Settings.get_v("keybinds")
	return int(custom.get(action, DEFAULTS.get(action, 0)))


static func label(action: String) -> String:
	var c := code_of(action)
	if c < 0:
		return ["", "Left Button", "Right Button", "Middle Button"][clampi(-c, 0, 3)]
	return OS.get_keycode_string(c as Key)


static func conflicts() -> Array:
	var seen := {}
	var out: Array = []
	for a in DEFAULTS:
		var c := code_of(a)
		if seen.has(c):
			out.append([seen[c], a])
		else:
			seen[c] = a
	return out
