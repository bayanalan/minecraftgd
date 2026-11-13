## WorldOptions — Java 26.3 World Options (`game.world_options`), opened from the Game Menu: in-world background,
## tab bar General | Multiplayer (vanilla TabButton geometry), 2-column grid of 150-px controls (cell padding 4)
## aligned in the tab area at (0.5, 1/6), footer Done (200). Every control acts on the running world:
##  General: Default Game Mode, Personal Game Mode (/gamemode; needs commands), Allow Commands, Difficulty
##   (hardcore-locked with the vanilla tooltips), Edit Game Rules... (runtime rules editor).
##  Multiplayer: LAN World on/off (Net.host / Net.stop), Port Number (1024..65535, locked while hosting),
##   Command Access / Force Game Mode shown with Recraft's fixed LAN behaviour (host-only commands; joiners use
##   the default game mode) and the reason.
extends Control

var world
var _tabs: Array = []
var _pages: Array = []
var _page_h: Array = []
var _cur := 0
var _done: Button
var _header_sep: Control
var _bg: Control
var _port: LineEdit
var _port_err: Label
var _lan: Button
var _sub: Control

const MODES := ["survival", "creative", "adventure", "spectator"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	world.paused = not Net.active()
	UiKit._blur(self)
	var bg := UiKit.sprite("gui/inworld_menu_background")
	if bg != null:
		_bg = UiKit.TileRect.make(bg, 32)
		_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
		add_child(_bg)
	_header_sep = UiKit.TileRect.make(UiKit.sprite("gui/inworld_header_separator"), 32)
	_header_sep.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(_header_sep)
	for i in 2:
		var t := McW.TabButton.new()
		t.text = Res.tr_key(["options.worldOptions.general.title", "options.worldOptions.multiplayer.title"][i], ["General", "Multiplayer"][i])
		t.pressed.connect(func():
			Audio.play_ui("ui.button.click")
			_show(i))
		add_child(t)
		_tabs.append(t)
	_build_general()
	_build_multiplayer()
	_done = UiKit.button(Res.tr_key("gui.done", "Done"), close, 200)
	add_child(_done)
	_show(0)
	_layout()
	resized.connect(_layout)


func _page(h: int) -> Control:
	var p := Control.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	_pages.append(p)
	_page_h.append(h)
	return p


func _cell(p: Control, c: Control, col: int, row: int, w := 150) -> Control:
	p.add_child(c)
	McW.place(c, 4 + col * 158, row * 24, w, 20)
	return c


func _mode_names() -> Array:
	return MODES.map(func(m): return Res.tr_key("selectWorld.gameMode." + m, str(m).capitalize()))


func _build_general() -> void:
	var p := _page(68)
	var hc: bool = world.hardcore
	var cmds := bool(world.level.get("allow_commands", false))
	var dgm := McW.cycle(Res.tr_key("options.worldOptions.game_mode", "Default Game Mode"), _mode_names(), clampi(int(world.level.get("game_mode", 0)), 0, 3), func(i): world.level["game_mode"] = i)
	dgm.disabled = hc
	dgm.tooltip_text = Res.tr_key("options.worldOptions.game_mode.disabled.tooltip" if hc else "options.worldOptions.game_mode.tooltip", "")
	_cell(p, dgm, 0, 0)
	var pgm := McW.cycle(Res.tr_key("options.worldOptions.personal_game_mode", "Personal Game Mode"), _mode_names(), clampi(int(world.player.mode), 0, 3), func(i): world.commands.execute("/gamemode " + MODES[i]))
	pgm.disabled = hc or not cmds
	pgm.tooltip_text = Res.tr_key("options.worldOptions.game_mode.disabled.tooltip", "") if hc else (Res.tr_key("options.worldOptions.personal_game_mode.tooltip", "") if cmds else "Requires Allow Commands")
	_cell(p, pgm, 1, 0)
	var ac := McW.on_off(Res.tr_key("selectWorld.allowCommands.new", "Allow Commands"), cmds, func(v):
		world.level["allow_commands"] = v
		pgm.disabled = hc or not v, 150)
	ac.disabled = hc
	ac.tooltip_text = Res.tr_key("options.worldOptions.allow_commands.disabled.tooltip" if hc else "options.worldOptions.allow_commands.tooltip", "")
	_cell(p, ac, 0, 1)
	var diffs := ["peaceful", "easy", "normal", "hard"].map(func(d): return Res.tr_key("options.difficulty." + d, str(d).capitalize()))
	var df := McW.cycle(Res.tr_key("options.difficulty", "Difficulty"), diffs, clampi(int(world.difficulty), 0, 3), func(i): world.difficulty = i)
	if hc:
		McW.cycle_values(df, [Res.tr_key("options.difficulty.hardcore", "Hardcore")], 0)
		df.disabled = true
		df.tooltip_text = Res.tr_key("options.worldOptions.difficulty.disabled.hardcore.tooltip", "")
	_cell(p, df, 1, 1)
	var gr := UiKit.button(Res.tr_key("editGamerule.inGame.button", "Edit Game Rules..."), _rules, 308)
	gr.disabled = hc
	gr.tooltip_text = Res.tr_key("editGamerule.inGame.disabled.hardcore.tooltip", "") if hc else ""
	_cell(p, gr, 0, 2, 308)


func _build_multiplayer() -> void:
	var p := _page(92)
	var hosting: bool = Net.is_host()
	_lan = McW.on_off(Res.tr_key("lanServer.title", "LAN World"), hosting, func(v): _set_lan(v), 308)
	_lan.disabled = Net.is_client()
	_cell(p, _lan, 0, 0, 308)
	var lab := McW.text(Res.tr_key("lanServer.port", "Port Number"))
	p.add_child(lab)
	McW.place(lab, 6, 24 + 6 - 1, 150, 9)
	_port = McW.edit(str(Net.port if hosting else Net.DEFAULT_PORT), "", 5)
	_port.editable = not hosting
	_port.text_changed.connect(func(_t): _check_port())
	_cell(p, _port, 1, 1)
	_port_err = McW.text("", McW.RED, HORIZONTAL_ALIGNMENT_CENTER)
	_port_err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(_port_err)
	McW.place(_port_err, 0, 24 * 3 + 2, 316, 20)
	var ca := McW.on_off(Res.tr_key("options.worldOptions.guest.command_access", "Command Access"), false, func(_v): pass)
	ca.disabled = true
	ca.tooltip_text = "Recraft LAN: commands are host-only"
	_cell(p, ca, 0, 2)
	var fg := McW.on_off(Res.tr_key("options.worldOptions.guest.force_game_mode", "Force Game Mode"), true, func(_v): pass)
	fg.disabled = true
	fg.tooltip_text = "Recraft LAN: joining players always use the world's default game mode"
	_cell(p, fg, 1, 2)


func _check_port() -> bool:
	var t := _port.text.strip_edges()
	var ok := t == "" or (t.is_valid_int() and int(t) >= 1024 and int(t) <= 65535)
	_port.add_theme_color_override("font_color", McW.EDIT_TEXT if ok else McW.RED)
	_port_err.text = "" if ok else Res.tr_key("lanServer.port.invalid", "Not a valid port.").split("\n")[0]
	_lan.disabled = (not ok and not Net.is_host()) or Net.is_client()
	return ok


func _set_lan(on: bool) -> void:
	if on and not Net.active():
		if not _check_port():
			McW.cycle_set(_lan, 0)
			return
		var t := _port.text.strip_edges()
		var msg := Net.host(world, int(t) if t != "" else Net.DEFAULT_PORT)
		world.hud.chat_message(msg)
		if not Net.is_host():
			McW.cycle_set(_lan, 0)
			_port_err.text = Res.tr_key("lanServer.port.unavailable", "Port not available.").split("\n")[0]
		else:
			_port.text = str(Net.port)
	elif not on and Net.is_host():
		Net.stop()
		world.hud.chat_message("Local game closed")
	_port.editable = not Net.is_host()
	world.paused = not Net.active()


func _rules() -> void:
	var scr = load("res://scripts/ui/game_rules_screen.gd").new()
	scr.rules = world.gamerules.duplicate()
	scr.runtime = true
	scr.on_done = func(r):
		for k in r:
			world.gamerules[k] = r[k]
		world.level["gamerules"] = world.gamerules
	for ch in get_children():
		ch.set_meta("was_visible", ch.visible)
		ch.visible = false
	_sub = scr
	scr.tree_exited.connect(func():
		_sub = null
		if not is_inside_tree():
			return
		for ch in get_children():
			if ch.has_meta("was_visible"):
				ch.visible = ch.get_meta("was_visible")
		_show(_cur))
	add_child(scr)


func _show(i: int) -> void:
	_cur = i
	for k in _pages.size():
		_pages[k].visible = k == i
		_tabs[k].selected = k == i
		_tabs[k].queue_redraw()


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	var tw := float(int(roundf((minf(400.0, gw) - 28.0) / 2.0 / 2.0)) * 2)
	var tx := floorf((gw - tw * 2.0) / 2.0)
	for i in 2:
		McW.place(_tabs[i], tx + tw * i, 0, tw, 24)
	if _bg != null:
		McW.place(_bg, 0, 24, gw, gh - 24)
		_bg.queue_redraw()
	McW.place(_header_sep, 0, 22, gw, 2)
	McW.place(_done, c - 100, gh - 27, 200, 20)
	var area_h := gh - 33.0 - 24.0
	for k in _pages.size():
		McW.place(_pages[k], c - 158, floorf(24.0 + maxf(0.0, area_h - float(_page_h[k])) / 6.0))


## Esc closes the open game rules editor first, then this screen (back to the Game Menu).
func on_escape() -> void:
	if _sub != null and is_instance_valid(_sub):
		_sub.queue_free()
		return
	close()


func close() -> void:
	world.open_screen(load("res://scripts/ui/pause_menu.gd").new())


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and _sub == null:
		get_viewport().set_input_as_handled()
		close()
