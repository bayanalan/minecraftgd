## PackScreen — Java PackSelectionScreen (`options.resourcepacks`): title (y 8) and drop info (y 20), two 200-px
## TransferableSelectionLists (x = C-204 and C+4, y 32..h-51, 36-px rows, bold underlined list titles): pack
## icon 32x32, name, two gray description lines. Hovering the icon shows transferable_list sprites: available ->
## select (whole icon); selected -> unselect (left half), move up / move down (right half, top / bottom); clicks
## act on the same regions. "Default" (the installed game assets) is fixed at the bottom of Selected.
## Footer: Open Pack Folder (C-154, h-48) | Done (C+4, h-48). Recraft applies pack changes on the next start
## (stated under the title); the selection is saved on Done.
extends Control

var on_close: Callable
var _avail: McList
var _sel: McList
var _a: Array = []      # pack names
var _s: Array = []      # enabled, highest priority first
var _meta := {}         # name -> [icon Texture2D, description]
var _title: Label
var _info: Label
var _open_btn: Button
var _done: Button
var _start: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	_s = (Settings.get_v("resource_packs") as Array).duplicate()
	_start = _s.duplicate()
	for p in Res.available_packs():
		if not _s.has(p):
			_a.append(p)
	_title = McW.text(Res.tr_key("pack.title", "Select Resource Packs"), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	_info = McW.text(Res.tr_key("pack.dropInfo", "Drag and drop files into this window to add packs") + "  (Recraft: changes apply on the next start)", McW.GRAY, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_info)
	_avail = _mk_list(true)
	_sel = _mk_list(false)
	_open_btn = UiKit.button(Res.tr_key("pack.openFolder", "Open Pack Folder"), func():
		DirAccess.make_dir_recursive_absolute(Res.PACK_DIR)
		OS.shell_open(ProjectSettings.globalize_path(Res.PACK_DIR)), 150)
	_done = UiKit.button(Res.tr_key("gui.done", "Done"), close, 150)
	add_child(_open_btn)
	add_child(_done)
	_refresh()
	_layout()
	resized.connect(_layout)


func _mk_list(available: bool) -> McList:
	var l := McList.new()
	l.item_height = 36
	l.row_width = 200
	l.header_px = 13
	l.scrollbar_inside = true
	l.draw_row = func(ls: McList, i: int, r: Rect2, h: bool, _s2: bool): _draw_pack(ls, i, r, h, available)
	l.draw.connect(func(): _draw_head(l, available))
	l.gui_input.connect(func(e): _click(l, e, available))
	add_child(l)
	return l


func _refresh() -> void:
	_avail.set_count(_a.size())
	_sel.set_count(_s.size() + 1)
	_avail.sel = -1
	_sel.sel = -1


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(_title, 0, 8 - 1, gw, 9)
	McW.place(_info, 0, 20 - 1, gw, 9)
	McW.place(_avail, c - 204, 32, 200, maxf(0.0, gh - 51 - 32))
	McW.place(_sel, c + 4, 32, 200, maxf(0.0, gh - 51 - 32))
	McW.place(_open_btn, c - 154, gh - 48, 150, 20)
	McW.place(_done, c + 4, gh - 48, 150, 20)


func _draw_head(l: McList, available: bool) -> void:
	var s := l.gs()
	var t := Res.tr_key("pack.available.title" if available else "pack.selected.title", "Available" if available else "Selected")
	var tw := McList.text_w(t) + 1.0
	var x := floorf((200.0 - tw) / 2.0)
	var y := 3.0 - l.scroll
	if y + 9.0 < 0:
		return
	var f := UiKit.font()
	for dx in [0.0, 1.0]:   # Java bold: second pass 1 px right
		if Settings.get_v("text_shadow"):
			l.draw_string(f, Vector2(x + dx + 1, y + 8) * s, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), Color(0.25, 0.25, 0.25))
		l.draw_string(f, Vector2(x + dx, y + 7) * s, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), Color(1, 1, 1))
	l.draw_rect(Rect2(Vector2(x, y + 8) * s, Vector2(tw, 1) * s), Color(1, 1, 1))   # underline


func _pack_name(i: int, available: bool) -> String:
	if available:
		return _a[i]
	return _s[i] if i < _s.size() else ""


func _meta_of(name: String) -> Array:
	if _meta.has(name):
		return _meta[name]
	var icon: Texture2D = null
	var desc := ""
	if name == "":
		icon = UiKit.sprite("misc/unknown_pack")
		desc = Res.tr_key("resourcePack.vanilla.description", "The default look and feel of Minecraft")
	else:
		var root := Res.PACK_DIR.path_join(name)
		var mcmeta := ""
		var png := PackedByteArray()
		if DirAccess.dir_exists_absolute(root):
			if FileAccess.file_exists(root.path_join("pack.mcmeta")):
				mcmeta = FileAccess.get_file_as_string(root.path_join("pack.mcmeta"))
			if FileAccess.file_exists(root.path_join("pack.png")):
				png = FileAccess.get_file_as_bytes(root.path_join("pack.png"))
		elif FileAccess.file_exists(root):
			var z := ZIPReader.new()
			if z.open(root) == OK:
				var files := z.get_files()
				if files.has("pack.mcmeta"):
					mcmeta = z.read_file("pack.mcmeta").get_string_from_utf8()
				if files.has("pack.png"):
					png = z.read_file("pack.png")
				z.close()
		var j = JSON.parse_string(mcmeta) if mcmeta != "" else null
		if j is Dictionary:
			var d = j.get("pack", {}).get("description", "")
			desc = _flatten(d)
		if png.size() > 0:
			var im := Image.new()
			if im.load_png_from_buffer(png) == OK:
				icon = ImageTexture.create_from_image(im)
		if icon == null:
			icon = UiKit.sprite("misc/unknown_pack")
	_meta[name] = [icon, desc]
	return _meta[name]


## Text component (string / object / array) to plain text.
static func _flatten(c) -> String:
	if c is String:
		return c
	if c is Array:
		return "".join(c.map(func(x): return _flatten(x)))
	if c is Dictionary:
		var t := str(c.get("text", c.get("translate", "")))
		for e in c.get("extra", []):
			t += _flatten(e)
		return t
	return str(c)


func _draw_pack(l: McList, i: int, r: Rect2, hovered: bool, available: bool) -> void:
	var s := l.gs()
	var nm := _pack_name(i, available)
	var m := _meta_of(nm)
	var x := r.position.x
	var y := r.position.y
	if m[0] != null:
		l.body.draw_texture_rect(m[0], Rect2(x, y, 32 * s, 32 * s), false)
	var title := nm if nm != "" else Res.tr_key("resourcePack.vanilla.name", "Default")
	l.text(Vector2(x + 34 * s, y + 1 * s), title, Color(1, 1, 1))
	var lines := GameRulesWrap.split(str(m[1]), 157.0)
	for k in mini(2, lines.size()):
		l.text(Vector2(x + 34 * s, y + (12 + 10 * k) * s), lines[k], McW.DGRAY)
	if hovered and nm != "":
		l.body.draw_rect(Rect2(x, y, 32 * s, 32 * s), Color8(0x90, 0x90, 0x90, 0xA0))
		var mp := l.mouse_gui() - Vector2(x, y) / s
		var spr: Array = []
		if available:
			spr.append("select" + ("_highlighted" if mp.x < 32 else ""))
		else:
			spr.append("unselect" + ("_highlighted" if mp.x < 16 else ""))
			if i > 0:
				spr.append("move_up" + ("_highlighted" if mp.x > 16 and mp.x < 32 and mp.y < 16 else ""))
			if i < _s.size() - 1:
				spr.append("move_down" + ("_highlighted" if mp.x > 16 and mp.x < 32 and mp.y > 16 else ""))
		for sp in spr:
			var t := UiKit.sprite("gui/sprites/transferable_list/" + sp)
			if t != null:
				l.body.draw_texture_rect(t, Rect2(x, y, 32 * s, 32 * s), false)


func _click(l: McList, e: InputEvent, available: bool) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var i := l.row_at(e.position)
	if i < 0:
		return
	var nm := _pack_name(i, available)
	if nm == "":
		return
	var r := l.row_rect(i)
	var mp: Vector2 = e.position / l.gs() - r.position
	if mp.x >= 32 or mp.x < 0:
		return
	if available:
		_a.erase(nm)
		_s.insert(0, nm)
	elif mp.x < 16:
		_s.erase(nm)
		_a.append(nm)
	elif mp.y < 16 and i > 0:
		_s.remove_at(i)
		_s.insert(i - 1, nm)
	elif mp.y >= 16 and i < _s.size() - 1:
		_s.remove_at(i)
		_s.insert(i + 1, nm)
	Audio.play_ui("ui.button.click")
	_refresh()


func close() -> void:
	if _s != _start:
		Settings.set_v("resource_packs", _s)
	Settings.save()
	queue_free()
	if on_close.is_valid():
		on_close.call()


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


## Word wrap helper (Java Font.split) shared with the game rules screen.
class GameRulesWrap:
	static func split(t: String, w: float) -> Array:
		var out: Array = []
		for para in t.split("\n"):
			var cur := ""
			for word in para.split(" "):
				var cand := word if cur == "" else cur + " " + word
				if McList.text_w(cand) > w and cur != "":
					out.append(cur)
					cur = word
				else:
					cur = cand
			out.append(cur)
		return out
