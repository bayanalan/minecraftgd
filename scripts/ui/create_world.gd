## CreateWorld — Java CreateWorldScreen (`world.create`): TabNavigationBar (Game / World / More; tabs
## roundToward((min(400, w) - 28) / 3, 2) wide, 24 high, centred at y 0, header separator under it,
## tab_header_background behind), each tab's grid aligned in the tab area at (0.5, 1/6), footer 33 high with
## Create New World | Cancel (150 each, 8 apart) under the footer separator. One settings model `st` is shared by
## all tabs (switching tabs never resets values).
##  Game: World Name (EditBox 208, label above), Game Mode (Survival / Hardcore / Creative, 210), Difficulty
##   (locked Hard in Hardcore), Allow Commands (off + locked in Hardcore).
##  World: World Type (150) | Customize (150: Superflat / Single Biome editors), seed (308), switch grid
##   (Generate Structures + info, Bonus Chest), Recraft generator profile (documented addition).
##  More: Game Rules (editor), Experiments / Data Packs (not supported: disabled with the reason).
extends Control

var app
var prefill: Dictionary = {}
var st := {
	"name": "New World", "mode": 0, "difficulty": 2, "cheats": false, "type": 0, "seed": "", "structures": true,
	"bonus": false, "profile": 0, "flat_layers": [["bedrock", 1], ["dirt", 2], ["grass_block", 1]], "flat_biome": "plains",
	"single_biome": "plains", "rules": {},
}
var name_edit: LineEdit
var seed_edit: LineEdit
var _tabs: Array = []
var _pages: Array = []
var _page_h: Array = []
var _cur := 0
var _bg_tile: Control
var _footer_sep: Control
var _header_sep: Control
var _create_btn: Button
var _cancel_btn: Button
var _mode_btn: Button
var _diff_btn: Button
var _cheat_btn: Button
var _type_btn: Button
var _cust_btn: Button

const MODES := ["survival", "hardcore", "creative"]
const TYPES := ["normal", "flat", "large_biomes", "amplified", "single_biome_surface"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # sized by bootstrap's screen host
	theme = UiKit.theme()
	_apply_prefill()
	UiKit._blur(self)
	var bg := UiKit.sprite("gui/menu_background")
	if bg != null:
		_bg_tile = UiKit.TileRect.make(bg, 32)
		_bg_tile.set_anchors_preset(Control.PRESET_TOP_LEFT)
		add_child(_bg_tile)
	_header_sep = _sep("gui/header_separator")
	_footer_sep = _sep("gui/footer_separator")
	for i in 3:
		var t := McW.TabButton.new()
		t.text = Res.tr_key("createWorld.tab.%s.title" % ["game", "world", "more"][i], ["Game", "World", "More"][i])
		t.pressed.connect(func():
			Audio.play_ui("ui.button.click")
			_show(i))
		add_child(t)
		_tabs.append(t)
	_build_game()
	_build_world()
	_build_more()
	_create_btn = UiKit.button(Res.tr_key("selectWorld.create", "Create New World"), _create, 150)
	_cancel_btn = UiKit.button(Res.tr_key("gui.cancel", "Cancel"), func(): app.show_world_list(), 150)
	add_child(_create_btn)
	add_child(_cancel_btn)
	_sync()
	_show(0)
	_layout()
	resized.connect(_layout)
	name_edit.text_submitted.connect(func(_t): _create())
	name_edit.grab_focus()


func _apply_prefill() -> void:
	if prefill.is_empty():
		return
	st["name"] = str(prefill.get("name", "New World"))
	st["mode"] = 1 if prefill.get("hardcore", false) else (2 if int(prefill.get("game_mode", 0)) == 1 else 0)
	st["difficulty"] = int(prefill.get("difficulty", 2))
	st["cheats"] = bool(prefill.get("allow_commands", false))
	st["seed"] = str(prefill.get("seed_text", "")) if str(prefill.get("seed_text", "")) != "" else str(prefill.get("seed", ""))
	var gs: Dictionary = prefill.get("generator_settings", {})
	st["structures"] = bool(gs.get("structures", true))
	st["bonus"] = bool(prefill.get("bonus_chest", false))
	st["type"] = maxi(0, ["default", "flat", "large_biomes", "amplified", "single_biome"].find(str(gs.get("world_type", "default"))))
	if gs.has("flat_layers"):
		st["flat_layers"] = gs["flat_layers"]
	st["flat_biome"] = str(gs.get("flat_biome", "plains"))
	st["single_biome"] = str(gs.get("single_biome", "plains"))
	st["profile"] = maxi(0, ["java_26_3", "java_1_18_2_exact", "hybrid_1_18_2_terrain_26_3_content"].find(str(prefill.get("generator_id", "java_26_3"))))
	var gr: Dictionary = GameRules.migrate(prefill.get("gamerules", {}))
	for k in gr:
		if GameRules.SPEC.has(k) and gr[k] != GameRules.SPEC[k][0]:
			st["rules"][k] = gr[k]


func _sep(path: String) -> Control:
	var t := UiKit.TileRect.make(UiKit.sprite(path), 32)
	t.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(t)
	return t


func _page(h: int) -> Control:
	var p := Control.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	_pages.append(p)
	_page_h.append(h)
	return p


func _add(p: Control, c: Control, x: float, y: float, w: float, h: float) -> Control:
	p.add_child(c)
	McW.place(c, x, y, w, h)
	return c


func _build_game() -> void:
	var p := _page(117)
	p.set_meta("w", 210)
	# Label glyphs sit 1 GUI px lower than Java drawString: text widgets are placed at y - 1
	_add(p, McW.text(Res.tr_key("selectWorld.enterName", "World Name")), 2, -1, 208, 9)
	name_edit = McW.edit(str(st["name"]), "", 32)
	name_edit.text_changed.connect(func(t):
		st["name"] = t
		_create_btn.disabled = t.strip_edges() == "")
	_add(p, name_edit, 1, 13, 208, 20)
	var mode_names := MODES.map(func(m): return Res.tr_key("selectWorld.gameMode." + m, str(m).capitalize()))
	_mode_btn = McW.cycle(Res.tr_key("selectWorld.gameMode", "Game Mode"), mode_names, int(st["mode"]), func(i):
		st["mode"] = i
		_sync(), 210)
	_add(p, _mode_btn, 0, 41, 210, 20)
	var diffs := ["peaceful", "easy", "normal", "hard"].map(func(d): return Res.tr_key("options.difficulty." + d, str(d).capitalize()))
	_diff_btn = McW.cycle(Res.tr_key("options.difficulty", "Difficulty"), diffs, int(st["difficulty"]), func(i): st["difficulty"] = i, 210)
	_add(p, _diff_btn, 0, 69, 210, 20)
	_cheat_btn = McW.on_off(Res.tr_key("selectWorld.allowCommands.new", "Allow Commands"), bool(st["cheats"]), func(v):
		st["cheats"] = v
		st["cheats_set"] = true, 210)
	_cheat_btn.tooltip_text = Res.tr_key("selectWorld.allowCommands.info", "Commands like /gamemode, /experience")
	_add(p, _cheat_btn, 0, 97, 210, 20)


func _build_world() -> void:
	var p := _page(160)
	p.set_meta("w", 310)
	var type_names := TYPES.map(func(t): return Res.tr_key("generator.minecraft." + t, str(t).capitalize()))
	_type_btn = McW.cycle(Res.tr_key("selectWorld.mapType", "World Type"), type_names, int(st["type"]), func(i):
		st["type"] = i
		_sync(), 150)
	_add(p, _type_btn, 0, 0, 150, 20)
	_cust_btn = UiKit.button(Res.tr_key("selectWorld.customizeType", "Customize"), _customize, 150)
	_add(p, _cust_btn, 160, 0, 150, 20)
	_add(p, McW.text(Res.tr_key("selectWorld.enterSeed", "Seed for the world generator")), 2, 27, 308, 9)
	seed_edit = McW.edit(str(st["seed"]), Res.tr_key("selectWorld.seedInfo", "Leave blank for a random seed"), 32)
	seed_edit.text_changed.connect(func(t): st["seed"] = t)
	_add(p, seed_edit, 1, 41, 308, 20)
	# SwitchGrid (308 wide): label left, 44-px value-only switch right, gray info under the label
	var y := 69.0
	for sw in [["selectWorld.mapFeatures", "Generate Structures", "structures", "selectWorld.mapFeatures.info", "Villages, Shipwrecks, etc."],
			["selectWorld.bonusItems", "Bonus Chest", "bonus", "", ""]]:
		_add(p, McW.text(Res.tr_key(sw[0], sw[1])), 1, y + 4, 250, 9)   # Java: centred in the 20-px row (y + 5)
		var key: String = sw[2]
		_add(p, McW.on_off("", bool(st[key]), func(v): st[key] = v, 44, true), 264, y, 44, 20)
		y += 24
		if sw[3] != "":
			_add(p, McW.text(Res.tr_key(sw[3], sw[4]), McW.GRAY), 1, y - 3, 308, 9)
			y += 12
	# Recraft addition: terrain generator profile (UI_LAYOUT_DECISIONS.md)
	var profiles := ["Java 26.3", "Java 1.18.2 terrain (approximate)", "Hybrid 1.18.2 terrain + 26.3 content"]
	if Res.mode != "vanilla":
		profiles = ["Original approximate terrain"]
	var pb := McW.cycle("Generator", profiles, mini(int(st["profile"]), profiles.size() - 1), func(i): st["profile"] = i, 308)
	_add(p, pb, 1, y + 4, 308, 20)
	_page_h[_page_h.size() - 1] = int(y + 24)


func _build_more() -> void:
	var p := _page(76)
	p.set_meta("w", 210)
	_add(p, UiKit.button(Res.tr_key("selectWorld.gameRules", "Game Rules"), _game_rules, 210), 0, 0, 210, 20)
	var ex := UiKit.button(Res.tr_key("selectWorld.experiments", "Experiments"), func(): pass, 210)
	ex.disabled = true
	ex.tooltip_text = "Recraft has no experimental feature packs to enable"
	_add(p, ex, 0, 28, 210, 20)
	var dp := UiKit.button(Res.tr_key("selectWorld.dataPacks", "Data Packs"), func(): pass, 210)
	dp.disabled = true
	dp.tooltip_text = "Recraft uses the installed 26.3 data; extra data packs are not supported"
	_add(p, dp, 0, 56, 210, 20)


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
	var tw := float(int(roundf((minf(400.0, gw) - 28.0) / 3.0 / 2.0)) * 2)
	var tx := floorf((gw - tw * 3.0) / 2.0)
	for i in 3:
		McW.place(_tabs[i], tx + tw * i, 0, tw, 24)
	var footer_h := 33.0
	if _bg_tile != null:
		McW.place(_bg_tile, 0, 24, gw, gh - 24)
		_bg_tile.queue_redraw()
	McW.place(_header_sep, 0, 22, gw, 2)
	var fy := float(int((gh - footer_h - 2.0) / 2.0) * 2)
	McW.place(_footer_sep, 0, fy, gw, 2)
	var by := floorf(gh - footer_h + (footer_h - 20.0) / 2.0)
	McW.place(_create_btn, c - 154, by, 150, 20)
	McW.place(_cancel_btn, c + 4, by, 150, 20)
	var area_top := 24.0
	var area_h := gh - footer_h - area_top
	for k in _pages.size():
		var pw := float(_pages[k].get_meta("w"))
		var ph := float(_page_h[k])
		McW.place(_pages[k], floorf((gw - pw) / 2.0), floorf(area_top + maxf(0.0, area_h - ph) / 6.0))


func _sync() -> void:
	var hc := int(st["mode"]) == 1
	_diff_btn.disabled = hc
	if hc:
		McW.cycle_set(_diff_btn, 3)
		McW.cycle_set(_cheat_btn, 0)
		st["cheats"] = false
	else:
		McW.cycle_set(_diff_btn, int(st["difficulty"]))
		# Java WorldCreationUiState.isAllowCommands: follows Creative until the player sets it
		if not bool(st.get("cheats_set", false)):
			st["cheats"] = int(st["mode"]) == 2
			McW.cycle_set(_cheat_btn, 1 if st["cheats"] else 0)
	_cheat_btn.disabled = hc
	var m: String = MODES[int(st["mode"])]
	_mode_btn.tooltip_text = Res.tr_key("selectWorld.gameMode.%s.info" % m, "")
	_cust_btn.disabled = not (int(st["type"]) == 1 or int(st["type"]) == 4)
	_type_btn.tooltip_text = Res.tr_key("generator.minecraft.amplified.info", "") if int(st["type"]) == 3 else ""


func _customize() -> void:
	var scr: Control
	if int(st["type"]) == 1:
		scr = load("res://scripts/ui/flat_customize.gd").new()
	else:
		scr = load("res://scripts/ui/single_biome.gd").new()
	scr.set("model", st)
	_open_sub(scr)


func _game_rules() -> void:
	var scr = load("res://scripts/ui/game_rules_screen.gd").new()
	scr.rules = st["rules"]
	scr.on_done = func(r): st["rules"] = r
	_open_sub(scr)


## Sub-screens replace this one visually and return to it (state kept, as Java re-opens the parent screen).
func _open_sub(scr: Control) -> void:
	for ch in get_children():
		ch.set_meta("was_visible", ch.visible)
		ch.visible = false
	scr.tree_exited.connect(func():
		if not is_inside_tree():
			return
		for ch in get_children():
			if ch.has_meta("was_visible"):
				ch.visible = ch.get_meta("was_visible")
		_show(_cur)
		_sync())
	add_child(scr)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		app.show_world_list()


func _create() -> void:
	var seed := RandomSources.parse_seed(str(st["seed"]))
	var mi := int(st["mode"])
	var mode: int = [0, 0, 1][mi]
	var hardcore := mi == 1
	var profile := "approx_original"
	if Res.mode == "vanilla":
		profile = ["java_26_3", "java_1_18_2_exact", "hybrid_1_18_2_terrain_26_3_content"][int(st["profile"])]
	var t := int(st["type"])
	var gs := {"structures": bool(st["structures"]), "world_type": ["default", "flat", "large_biomes", "amplified", "single_biome"][t]}
	if t == 1:
		profile = "flat"
		gs["flat_layers"] = st["flat_layers"]
		gs["flat_biome"] = st["flat_biome"]
	if t == 4:
		gs["single_biome"] = st["single_biome"]
	var gr := GameRules.defaults()
	gr.merge(st["rules"], true)
	var nm := str(st["name"]).strip_edges()
	var meta := {
		"name": nm if nm != "" else "New World",
		"seed": seed, "seed_text": str(st["seed"]), "game_mode": mode, "hardcore": hardcore,
		"difficulty": 3 if hardcore else int(st["difficulty"]), "allow_commands": bool(st["cheats"]) and not hardcore,
		"generator_id": profile, "generator_version": 1, "generator_settings": gs, "bonus_chest": bool(st["bonus"]),
		"content_version": Res.version, "asset_mode": Res.mode, "gamerules": gr,
	}
	var sm := SaveManager.new()
	var folder := sm.create_world(meta)
	app.start_world(folder)
