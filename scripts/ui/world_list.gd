## WorldList — Java SelectWorldScreen (`world.select`): title at y 8, search EditBox (C-100, 22, 200 x 20), McList
## y 48..h-64 with 36-px rows 270 wide (WorldSelectionList): 32x32 icon (save icon.png or misc/unknown_server),
## name (white), "folder (date)" and "Mode, Cheats, Version: v" (0x808080) without shadow; hovering darkens the
## icon (0xA0909090) and shows world_list/join(_highlighted) — clicking the icon plays. Footer: Play Selected
## World | Create New World (150 each at h-52), Edit | Delete | Re-Create | Back (72 each at h-28).
extends Control

var app
var list: McList
var worlds: Array = []      # all saves
var shown: Array = []       # filtered by the search box
var search: LineEdit
var _title: Label
var _b_play: Button
var _b_create: Button
var _b_edit: Button
var _b_del: Button
var _b_re: Button
var _b_back: Button
var _icons := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	_title = McW.text(Res.tr_key("selectWorld.title", "Select World"), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	search = McW.edit("", Res.tr_key("selectWorld.search", "search for worlds"), 64)
	search.text_changed.connect(func(_t): _filter())
	add_child(search)
	list = McList.new()
	list.item_height = 36
	list.row_width = 270
	list.draw_row = _draw_row
	list.selected.connect(func(_i): _update_buttons())
	list.activated.connect(func(_i): _play())
	list.gui_input.connect(_list_click)
	add_child(list)
	_b_play = UiKit.button(Res.tr_key("selectWorld.select", "Play Selected World"), _play, 150)
	_b_create = UiKit.button(Res.tr_key("selectWorld.create", "Create New World"), func(): app.show_create_world(), 150)
	_b_edit = UiKit.button(Res.tr_key("selectWorld.edit", "Edit"), _edit, 72)
	_b_del = UiKit.button(Res.tr_key("selectWorld.delete", "Delete"), _delete, 72)
	_b_re = UiKit.button(Res.tr_key("selectWorld.recreate", "Re-Create"), _recreate, 72)
	_b_back = UiKit.button(Res.tr_key("gui.back", "Back"), func(): app.show_title(), 72)
	for b in [_b_play, _b_create, _b_edit, _b_del, _b_re, _b_back]:
		add_child(b)
	_layout()
	resized.connect(_layout)
	_refresh()
	list.grab_focus()


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(_title, 0, 8 - 1, gw, 9)
	McW.place(search, c - 100, 22, 200, 20)
	McW.place(list, 0, 48, gw, maxf(0.0, gh - 64 - 48))
	McW.place(_b_play, c - 154, gh - 52, 150, 20)
	McW.place(_b_create, c + 4, gh - 52, 150, 20)
	McW.place(_b_edit, c - 154, gh - 28, 72, 20)
	McW.place(_b_del, c - 76, gh - 28, 72, 20)
	McW.place(_b_re, c + 4, gh - 28, 72, 20)
	McW.place(_b_back, c + 82, gh - 28, 72, 20)


func _refresh() -> void:
	worlds = SaveManager.list_worlds()
	_icons.clear()
	_filter()


func _filter() -> void:
	var q := search.text.strip_edges().to_lower()
	shown = worlds.filter(func(w): return q == "" or str(w.get("name", "")).to_lower().contains(q) or str(w.get("folder", "")).to_lower().contains(q))
	list.set_count(shown.size())
	list.select(0 if shown.size() > 0 else -1)
	_update_buttons()


func _update_buttons() -> void:
	var w := _sel()
	var has := not w.is_empty()
	_b_play.disabled = not has or w.get("corrupt", false)
	_b_edit.disabled = not has
	_b_del.disabled = not has
	_b_re.disabled = not has or w.get("corrupt", false)


func _sel() -> Dictionary:
	return shown[list.sel] if list.sel >= 0 and list.sel < shown.size() else {}


## en_US FormatStyle.SHORT: "11/12/26, 9:41 PM".
static func short_date(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	var h12 := int(d["hour"]) % 12
	if h12 == 0:
		h12 = 12
	return "%d/%d/%02d, %d:%02d %s" % [d["month"], d["day"], int(d["year"]) % 100, h12, d["minute"], "PM" if int(d["hour"]) >= 12 else "AM"]


func _icon(w: Dictionary) -> Texture2D:
	var f := str(w.get("folder", ""))
	if _icons.has(f):
		return _icons[f]
	var t: Texture2D = null
	var p := SaveManager.ROOT.path_join(f).path_join("icon.png")
	if FileAccess.file_exists(p):
		var im := Image.load_from_file(p)
		if im != null:
			t = ImageTexture.create_from_image(im)
	if t == null:
		t = UiKit.sprite("misc/unknown_server")
	_icons[f] = t
	return t


func _info(w: Dictionary) -> Array:
	# [text, color] pieces of Java LevelSummary.getInfo()
	if w.get("corrupt", false):
		return [[Res.tr_key("selectWorld.recovery", "Damaged world data (level.json unreadable)"), McW.RED]]
	var out: Array = []
	if w.get("hardcore", false):
		out.append([Res.tr_key("gameMode.hardcore", "Hardcore Mode!"), Color8(255, 0, 0)])
	else:
		var m: String = ["survival", "creative", "adventure", "spectator"][clampi(int(w.get("game_mode", 0)), 0, 3)]
		out.append([Res.tr_key("gameMode." + m, m.capitalize() + " Mode"), McW.DGRAY])
	var t := ""
	if w.get("allow_commands", false):
		t += ", " + Res.tr_key("selectWorld.commands", "Cheats")
	t += ", " + Res.tr_key("selectWorld.version", "Version:") + " " + str(w.get("content_version", Res.version))
	out.append([t, McW.DGRAY])
	return out


func _draw_row(l: McList, i: int, r: Rect2, hovered: bool, _selected: bool) -> void:
	var w: Dictionary = shown[i]
	var s := l.gs()
	var x := r.position.x
	var y := r.position.y
	var nm := str(w.get("name", ""))
	if nm == "":
		nm = Res.tr_key("selectWorld.world", "World") + " " + str(i + 1)
	var id := str(w.get("folder", ""))
	if int(w.get("last_played", 0)) > 0:
		id += " (" + short_date(int(w["last_played"])) + ")"
	var tx := x + 35 * s
	l.text(Vector2(tx, y + 1 * s), nm, Color(1, 1, 1), false, r.size.x - 35 * s)
	l.text(Vector2(tx, y + 12 * s), id, McW.DGRAY, false, r.size.x - 35 * s)
	var px := tx
	for piece in _info(w):
		l.text(Vector2(px, y + 21 * s), piece[0], piece[1], false)
		px += McList.text_w(piece[0]) * s
	var ic := _icon(w)
	if ic != null:
		l.body.draw_texture_rect(ic, Rect2(x, y, 32 * s, 32 * s), false)
	if hovered:
		l.body.draw_rect(Rect2(x, y, 32 * s, 32 * s), Color8(0x90, 0x90, 0x90, 0xA0))
		var over_icon := l.mouse_gui().x * s - x < 32 * s
		var spr := "gui/sprites/world_list/" + ("error" if w.get("corrupt", false) else "join") + ("_highlighted" if over_icon else "")
		var t := UiKit.sprite(spr)
		if t != null:
			l.body.draw_texture_rect(t, Rect2(x, y, 32 * s, 32 * s), false)


func _list_click(e: InputEvent) -> void:
	# Java WorldListEntry.mouseClicked: a click on the icon joins straight away
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := list.row_at(e.position)
		if i >= 0:
			var r := list.row_rect(i)
			if e.position.x / list.gs() - r.position.x < 32:
				list.select(i, false)
				_play()


func _play() -> void:
	var w := _sel()
	if w.is_empty() or w.get("corrupt", false):
		return
	app.start_world(w["folder"])


func _edit() -> void:
	var w := _sel()
	if w.is_empty():
		return
	var e = load("res://scripts/ui/edit_world.gd").new()
	e.app = app
	e.world = w
	app._set_screen(e)


func _recreate() -> void:
	# Java: Re-Create opens Create New World pre-filled from the save's settings (new folder, never overwrites)
	var w := _sel()
	if w.is_empty():
		return
	var c = load("res://scripts/ui/create_world.gd").new()
	c.app = app
	c.prefill = w
	app._set_screen(c)


func _delete() -> void:
	var w := _sel()
	if w.is_empty():
		return
	McConfirm.open(self, Res.tr_key("selectWorld.deleteQuestion", "Are you sure you want to delete this world?"),
		Res.tr_key("selectWorld.deleteWarning", "'%s' will be lost forever! (A long time!)").replace("%s", str(w.get("name", w["folder"]))),
		Res.tr_key("selectWorld.deleteButton", "Delete"), Res.tr_key("gui.cancel", "Cancel"),
		func():
			SaveManager.delete_world(w["folder"])
			_refresh())
