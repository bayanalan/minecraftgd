## PauseMenu — Java 26.3 Game Menu (PauseScreen): blurred world + in-world menu background, title "Game Menu" at
## y 40, a 2-column GridLayout (cell padding 4,4,4,0: full rows 204 wide, pairs 98 + 8 + 98) aligned at 25 % of the
## height: Back to Game / Advancements | Statistics / Give Feedback | Report Bugs / Options... | World Options (26.3
## moved World Options into Open to LAN's place) / Save and Quit to Title. Feedback / bug links are Mojang's
## services: shown disabled with the reason. Single-player pauses the simulation.
extends Control

var world
var _buttons: Array = []   # [Button, row, column (0, 1) or -1 full row]
var _title: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	world.paused = not Net.active()   # LAN games keep running while the menu is open
	UiKit.inworld_background(self)
	_title = UiKit.label(Res.tr_key("menu.game", "Game Menu"))
	add_child(_title)
	_add(Res.tr_key("menu.returnToGame", "Back to Game"), func(): world.close_screen(), 0, -1)
	_add(Res.tr_key("gui.advancements", "Advancements"), _advancements, 1, 0)
	_add(Res.tr_key("gui.stats", "Statistics"), _stats, 1, 1)
	var fb := _add(Res.tr_key("menu.sendFeedback", "Give Feedback"), func(): pass, 2, 0)
	var bug := _add(Res.tr_key("menu.reportBugs", "Report Bugs"), func(): pass, 2, 1)
	for b in [fb, bug]:
		b.disabled = true
		b.tooltip_text = "Opens Mojang's feedback / bug tracker in Minecraft; not available in Recraft"
	_add(Res.tr_key("menu.options", "Options..."), _options, 3, 0)
	_add(Res.tr_key("menu.worldOptions", "World Options..."), _world_options, 3, 1)
	_add(Res.tr_key("menu.returnToMenu", "Save and Quit to Title"), func(): world.app.leave_world(), 4, -1)
	_layout()
	resized.connect(_layout)


func _add(text: String, cb: Callable, row: int, col: int) -> Button:
	var b := UiKit.button(text, cb, 204 if col < 0 else 98)
	add_child(b)
	_buttons.append([b, row, col])
	return b


## Java: FrameLayout.alignInRectangle(grid, 0, 0, width, height, 0.5, 0.25); rows 24 apart (4 padding + 20).
func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var rows := 5
	var grid_w := 212.0
	var grid_h := rows * 24.0
	var gx := floorf((gw - grid_w) * 0.5)
	# 26.3 centres the title + button grid block vertically (the title sits 12 above the first row)
	var gy := floorf((gh - (grid_h + 16.0)) * 0.5) + 16.0
	for e in _buttons:
		var b: Button = e[0]
		var col: int = e[2]
		var x := gx + 4.0 + (0.0 if col <= 0 else 106.0)
		var y := gy + 4.0 + float(e[1]) * 24.0
		b.position = Vector2(x, y) * s
		b.size = Vector2(204 if col < 0 else 98, 20) * s
	_title.position = Vector2(0, gy - 16.0) * s
	_title.size = Vector2(gw, 9) * s

## Statistics / Advancements replace the Game Menu (Java opens them with the pause screen as parent).
func _stats() -> void:
	var w = world
	var sc = load("res://scripts/ui/stats_screen.gd").new()
	sc.world = w
	sc.on_close = Callable(w, "open_pause_menu")   # bound to the world: a lambda made here dies with this menu
	w.open_screen(sc)


func _advancements() -> void:
	var w = world
	var sc = load("res://scripts/ui/advancements_screen.gd").new()
	sc.world = w
	sc.on_close = Callable(w, "open_pause_menu")
	w.open_screen(sc)

## Options replaces the pause menu as the world's screen (sized to the viewport by open_screen; as a child of this
## menu its full-rect layout collapsed to 0x0) and Done returns to the pause menu, like Java.
func _options() -> void:
	var w = world
	var o = load("res://scripts/ui/options_menu.gd").new()
	o.back = Callable(w, "open_pause_menu")
	w.open_screen(o)
	w.paused = not Net.active()


func _world_options() -> void:
	var w = world
	var o = load("res://scripts/ui/world_options.gd").new()
	o.world = w
	w.open_screen(o)

