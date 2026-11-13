## FlatCustomize — Java CreateFlatWorldScreen (`world.superflat_customize`): title at y 8, column headers "Layer
## Material" (C-121, 32) and "Height" (right edge C+127), McList y 43..h-60 (24-px rows, top layer first): slot
## sprite + item icon, block name at +23, "Top - n" / "Bottom - n" / "n" right-aligned (-8). Remove Layer (C-155,
## h-52) | Presets (C+5, h-52), Done (C-155, h-28) | Cancel (C+5, h-28). Presets: Java PresetFlatWorldScreen —
## share box with the preset code ("minecraft:bedrock,2*minecraft:dirt,minecraft:grass_block;minecraft:plains")
## and the presets of the installed flat_level_generator_preset data in #visible tag order.
extends Control

var model: Dictionary            # CreateWorld settings (flat_layers bottom-first [[block, n]], flat_biome)
var _layers: Array = []
var _biome := "plains"
var list: McList
var _labels: Array = []
var _btn: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	_layers = model.get("flat_layers", []).duplicate(true)
	_biome = str(model.get("flat_biome", "plains"))
	for t in [Res.tr_key("createWorld.customize.flat.title", "Superflat Customization"),
			Res.tr_key("createWorld.customize.flat.tile", "Layer Material"), Res.tr_key("createWorld.customize.flat.height", "Height")]:
		var l := McW.text(t, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER if _labels.is_empty() else HORIZONTAL_ALIGNMENT_LEFT)
		add_child(l)
		_labels.append(l)
	list = McList.new()
	list.item_height = 24
	list.row_width = 220
	list.draw_row = _draw_row
	list.selected.connect(func(_i): _sync())
	add_child(list)
	_btn.append(UiKit.button(Res.tr_key("createWorld.customize.flat.removeLayer", "Remove Layer"), _remove, 150))
	_btn.append(UiKit.button(Res.tr_key("createWorld.customize.presets", "Presets"), _presets, 150))
	_btn.append(UiKit.button(Res.tr_key("gui.done", "Done"), func():
		model["flat_layers"] = _layers
		model["flat_biome"] = _biome
		queue_free(), 150))
	_btn.append(UiKit.button(Res.tr_key("gui.cancel", "Cancel"), func(): queue_free(), 150))
	for b in _btn:
		add_child(b)
	_refresh()
	_layout()
	resized.connect(_layout)


func _refresh() -> void:
	list.set_count(_layers.size())
	_sync()


func _sync() -> void:
	_btn[0].disabled = list.sel < 0 or list.sel >= _layers.size()


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(_labels[0], 0, 8 - 1, gw, 9)
	McW.place(_labels[1], c - 121, 32 - 1, 120, 9)
	McW.place(_labels[2], c + 127 - McList.text_w(_labels[2].text), 32 - 1, 60, 9)
	McW.place(list, 0, 43, gw, maxf(0.0, gh - 60 - 43))
	McW.place(_btn[0], c - 155, gh - 52, 150, 20)
	McW.place(_btn[1], c + 5, gh - 52, 150, 20)
	McW.place(_btn[2], c - 155, gh - 28, 150, 20)
	McW.place(_btn[3], c + 5, gh - 28, 150, 20)


## Rows are top layer first.
func _layer_at(i: int) -> Array:
	return _layers[_layers.size() - 1 - i]


func _draw_row(l: McList, i: int, r: Rect2, _h: bool, _s: bool) -> void:
	var s := l.gs()
	var ly: Array = _layer_at(i)
	var blk := str(ly[0]).trim_prefix("minecraft:")
	var slot := UiKit.sprite("gui/sprites/container/slot")
	if slot != null:
		l.body.draw_texture_rect(slot, Rect2(r.position + Vector2(1, 1) * s, Vector2(18, 18) * s), false)
	var it := Res.items.id(blk) if Res.items != null else -1
	if it >= 0:
		var ic := ItemIcons.icon(it)
		if ic != null:
			l.body.draw_texture_rect(ic, Rect2(r.position + Vector2(2, 2) * s, Vector2(16, 16) * s), false)
	var nm := Res.block_display_name(blk)
	l.text(r.position + Vector2(23, 3) * s, nm, Color(1, 1, 1), false)
	var n := str(ly[1])
	var ht := Res.tr_key("createWorld.customize.flat.layer.top", "Top - %s") if i == 0 else (Res.tr_key("createWorld.customize.flat.layer.bottom", "Bottom - %s") if i == _layers.size() - 1 else Res.tr_key("createWorld.customize.flat.layer", "%s"))
	ht = ht.replace("%s", n)
	l.text(Vector2(r.position.x + (220.0 - McList.text_w(ht) - 8.0) * s, r.position.y + 3 * s), ht, Color(1, 1, 1), false)


func _remove() -> void:
	if list.sel < 0 or list.sel >= _layers.size():
		return
	_layers.remove_at(_layers.size() - 1 - list.sel)
	list.select(mini(list.sel, _layers.size() - 1))
	_refresh()


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()


## Java preset code for the current layers.
func code() -> String:
	var parts: Array = []
	for ly in _layers:
		var b := "minecraft:" + str(ly[0]).trim_prefix("minecraft:")
		parts.append(b if int(ly[1]) == 1 else "%d*%s" % [int(ly[1]), b])
	return ",".join(parts) + ";minecraft:" + _biome.trim_prefix("minecraft:")


## Parses a preset code (Java PresetFlatWorldScreen.fromString); false when invalid.
func apply_code(t: String) -> bool:
	var halves := t.strip_edges().split(";")
	var out: Array = []
	for part in halves[0].split(",", false):
		var p := part.strip_edges()
		var n := 1
		if p.contains("*"):
			var a := p.split("*")
			if not a[0].is_valid_int():
				return false
			n = int(a[0])
			p = a[1]
		p = p.trim_prefix("minecraft:")
		if n < 1 or n > 384 or Res.blocks == null or Res.blocks.block_id(p) < 0:
			return false
		out.append([p, n])
	if out.is_empty():
		return false
	_layers = out
	if halves.size() > 1 and halves[1].strip_edges() != "":
		_biome = halves[1].strip_edges().trim_prefix("minecraft:")
	_refresh()
	return true


func _presets() -> void:
	var p := FlatPresets.new()
	p.owner_screen = self
	for ch in get_children():
		ch.set_meta("was_visible", ch.visible)
		ch.visible = false
	p.tree_exited.connect(func():
		if not is_inside_tree():
			return
		for ch in get_children():
			if ch.has_meta("was_visible"):
				ch.visible = ch.get_meta("was_visible"))
	add_child(p)


class FlatPresets extends Control:
	var owner_screen
	var list: McList
	var _presets: Array = []   # [display item, name, code]
	var _edit: LineEdit
	var _labels: Array = []
	var _use: Button
	var _cancel: Button

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		theme = UiKit.theme()
		UiKit.background(self)
		var tag = Res.read_json("data/minecraft/tags/worldgen/flat_level_generator_preset/visible.json")
		var ids: Array = tag.get("values", []) if tag is Dictionary else []
		for id in ids:
			var nm := str(id).trim_prefix("minecraft:")
			var j = Res.read_json("data/minecraft/worldgen/flat_level_generator_preset/%s.json" % nm)
			if not (j is Dictionary):
				continue
			var st: Dictionary = j.get("settings", {})
			var parts: Array = []
			for ly in st.get("layers", []):
				parts.append(str(ly["block"]) if int(ly["height"]) == 1 else "%d*%s" % [int(ly["height"]), str(ly["block"])])
			_presets.append([str(j.get("display", "minecraft:stone")).trim_prefix("minecraft:"),
				Res.tr_key("flat_world_preset.minecraft." + nm, nm.capitalize()), ",".join(parts) + ";" + str(st.get("biome", "minecraft:plains"))])
		for t in [Res.tr_key("createWorld.customize.presets.title", "Select a Preset"),
				Res.tr_key("createWorld.customize.presets.share", "Want to share your preset with someone? Use the box below!"),
				Res.tr_key("createWorld.customize.presets.list", "Alternatively, here are some we made earlier!")]:
			var l := McW.text(t, Color(1, 1, 1) if _labels.is_empty() else McW.GRAY, HORIZONTAL_ALIGNMENT_CENTER if _labels.is_empty() else HORIZONTAL_ALIGNMENT_LEFT)
			add_child(l)
			_labels.append(l)
		_edit = McW.edit(owner_screen.code(), "", 1230)
		_edit.text_changed.connect(func(_t): _use.disabled = _edit.text.strip_edges() == "")
		add_child(_edit)
		list = McList.new()
		list.item_height = 24
		list.row_width = 220
		list.draw_row = _draw_row
		list.selected.connect(func(i):
			if i >= 0:
				_edit.text = _presets[i][2]
				_use.disabled = false)
		list.activated.connect(func(_i): _apply())
		add_child(list)
		list.set_count(_presets.size())
		list.sel = -1
		_use = UiKit.button(Res.tr_key("createWorld.customize.presets.select", "Use Preset"), _apply, 150)
		_cancel = UiKit.button(Res.tr_key("gui.cancel", "Cancel"), func(): queue_free(), 150)
		add_child(_use)
		add_child(_cancel)
		_layout()
		resized.connect(_layout)

	func _layout() -> void:
		var s := float(UiKit.scale())
		var gw := size.x / s
		var gh := size.y / s
		var c := floorf(gw / 2.0)
		McW.place(_labels[0], 0, 8 - 1, gw, 9)
		McW.place(_labels[1], 50, 30 - 1, gw - 100, 9)
		McW.place(_edit, 50, 40, gw - 100, 20)
		McW.place(_labels[2], 50, 70 - 1, gw - 100, 9)
		McW.place(list, 0, 80, gw, maxf(0.0, gh - 37 - 80))
		McW.place(_use, c - 155, gh - 28, 150, 20)
		McW.place(_cancel, c + 5, gh - 28, 150, 20)

	func _draw_row(l: McList, i: int, r: Rect2, _h: bool, _s: bool) -> void:
		var s := l.gs()
		var slot := UiKit.sprite("gui/sprites/container/slot")
		if slot != null:
			l.body.draw_texture_rect(slot, Rect2(r.position + Vector2(1, 1) * s, Vector2(18, 18) * s), false)
		var it := Res.items.id(_presets[i][0]) if Res.items != null else -1
		if it >= 0:
			var ic := ItemIcons.icon(it)
			if ic != null:
				l.body.draw_texture_rect(ic, Rect2(r.position + Vector2(2, 2) * s, Vector2(16, 16) * s), false)
		l.text(r.position + Vector2(23, 5) * s, _presets[i][1], Color(1, 1, 1), false)

	func _apply() -> void:
		if owner_screen.apply_code(_edit.text):
			queue_free()
		else:
			_edit.add_theme_color_override("font_color", McW.RED)
