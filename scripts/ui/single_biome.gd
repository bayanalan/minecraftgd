## SingleBiome — Java CreateBuffetWorldScreen (`world.single_biome`): title at y 8, search box (26.x:
## createWorld.customize.buffet.search) at (C-100, 22), McList y 48..h-37 of biomes (biome.minecraft.<id>) sorted
## by name, 16-px rows, name at (+5, +2). Done (C-155, h-28, 150) needs a selection | Cancel (C+5, h-28, 150).
## Lists the overworld biomes the Recraft single-biome generator supports.
extends Control

var model: Dictionary
var list: McList
var _all: Array = []      # [id, name]
var _shown: Array = []
var _title: Label
var _search: LineEdit
var _done: Button
var _cancel: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	for b in BiomeRegistry.OVERWORLD_26_3:
		_all.append([b, Res.tr_key("biome.minecraft." + b, str(b).capitalize())])
	_all.sort_custom(func(a, b): return str(a[1]) < str(b[1]))
	_title = McW.text(Res.tr_key("createWorld.customize.buffet.title", "Single Biome Customization"), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	_search = McW.edit("", Res.tr_key("createWorld.customize.buffet.search", "Search..."), 64)
	_search.text_changed.connect(func(_t): _filter())
	add_child(_search)
	list = McList.new()
	list.item_height = 16
	list.row_width = 220
	list.draw_row = func(l: McList, i: int, r: Rect2, _h: bool, _s: bool):
		l.text(r.position + Vector2(5, 2) * l.gs(), _shown[i][1], Color(1, 1, 1))
	list.selected.connect(func(i): _done.disabled = i < 0)
	list.activated.connect(func(_i): _finish())
	add_child(list)
	_done = UiKit.button(Res.tr_key("gui.done", "Done"), _finish, 150)
	_cancel = UiKit.button(Res.tr_key("gui.cancel", "Cancel"), func(): queue_free(), 150)
	add_child(_done)
	add_child(_cancel)
	_layout()
	resized.connect(_layout)
	_filter()
	var cur := str(model.get("single_biome", "plains"))
	for i in _shown.size():
		if _shown[i][0] == cur:
			list.select(i)
	_done.disabled = list.sel < 0


func _filter() -> void:
	var q := _search.text.strip_edges().to_lower()
	_shown = _all.filter(func(e): return q == "" or str(e[1]).to_lower().contains(q))
	list.set_count(_shown.size())
	list.sel = -1
	if _done != null:
		_done.disabled = true


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(_title, 0, 8 - 1, gw, 9)
	McW.place(_search, c - 100, 22, 200, 20)
	McW.place(list, 0, 48, gw, maxf(0.0, gh - 37 - 48))
	McW.place(_done, c - 155, gh - 28, 150, 20)
	McW.place(_cancel, c + 5, gh - 28, 150, 20)


func _finish() -> void:
	if list.sel < 0:
		return
	var b: String = _shown[list.sel][0]
	model["single_biome"] = b
	queue_free()


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
