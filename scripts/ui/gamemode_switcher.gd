## GameModeSwitcher — Java GameModeSwitcherScreen (F3 + F4): gui/container/gamemode_switcher (125 x 75) with four
## 26 px slots 31 px apart (Creative grass block, Survival iron sword, Adventure map, Spectator ender eye), the
## selected slot framed (gamemode_switcher/selection), its name above, "[ F4 ] Next" below. F4 (or hovering) moves the
## selection; releasing F3 switches to it (Java: /gamemode) and closes.
extends Control

const MODES := [["creative", "grass_block", Player.Mode.CREATIVE], ["survival", "iron_sword", Player.Mode.SURVIVAL],
	["adventure", "map", Player.Mode.ADVENTURE], ["spectator", "ender_eye", Player.Mode.SPECTATOR]]
var world
var sel := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Java getDefaultSelected: the previous game mode, else Survival from Creative / Creative otherwise
	var prev: int = world.prev_gamemode
	if prev < 0 or prev == world.player.mode:
		prev = Player.Mode.SURVIVAL if world.player.mode == Player.Mode.CREATIVE else Player.Mode.CREATIVE
	for i in 4:
		if MODES[i][2] == prev:
			sel = i


func _process(_d: float) -> void:
	queue_redraw()
	if not Input.is_action_pressed("debug"):
		_apply()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F4:
		sel = (sel + 1) % 4
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var s := UiKit.scale()
		var m: Vector2 = get_local_mouse_position() / s
		var c := size / s / 2.0
		for i in 4:
			if Rect2(Vector2(c.x - 59.5 + i * 31, c.y - 31), Vector2(26, 26)).has_point(m):
				sel = i


func _apply() -> void:
	set_process(false)
	var m: int = MODES[sel][2]
	if m != world.player.mode:
		world.prev_gamemode = world.player.mode
		world.commands.execute("gamemode " + str(MODES[sel][0]))
	world.close_screen()


func on_escape() -> void:
	world.close_screen()


func _draw() -> void:
	var s := UiKit.scale()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var c := size / s / 2.0
	var font := UiKit.font()
	var bg := UiKit.sprite("gui/container/gamemode_switcher")
	if bg != null:
		draw_texture_rect_region(bg, Rect2(Vector2(c.x - 62, c.y - 31 - 27), Vector2(125, 75)), Rect2(Vector2.ZERO, Vector2(125, 75)))
	var title := Res.tr_key("gameMode." + str(MODES[sel][0]), str(MODES[sel][0]).capitalize() + " Mode")
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string(font, Vector2(c.x - tw / 2.0 + 1, c.y - 31 - 20 + 8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.25, 0.25, 0.25))
	draw_string(font, Vector2(c.x - tw / 2.0, c.y - 31 - 20 + 7), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	var slot := UiKit.sprite("gui/sprites/gamemode_switcher/slot")
	var selection := UiKit.sprite("gui/sprites/gamemode_switcher/selection")
	for i in 4:
		var p := Vector2(c.x - 59.5 + i * 31, c.y - 31)
		if slot != null:
			draw_texture_rect(slot, Rect2(p, Vector2(26, 26)), false)
		var ic := ItemIcons.icon(Res.items.id(str(MODES[i][1])))
		if ic != null:
			draw_texture_rect(ic, Rect2(p + Vector2(5, 5), Vector2(16, 16)), false)
		if i == sel and selection != null:
			draw_texture_rect(selection, Rect2(p, Vector2(26, 26)), false)
	var next := Res.tr_key("debug.gamemodes.select_next", "%s Next").replace("%s", Res.tr_key("debug.gamemodes.press_f4", "[ F4 ]"))
	var nw := font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	draw_string(font, Vector2(c.x - nw / 2.0, c.y + 5 + 7), next, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
