## BookScreen — Java BookViewScreen / BookEditScreen on the installed gui/book.png (192x192): page text at
## (36, 30) 114 px wide, "Page n of m" at the top right, page arrows at (43/116, 157), Done below.
## Edit mode (book and quill): multi-line page editor (Java limit 1024 chars/page, 100 pages), Sign -> title
## (max 32 chars) -> written_book with author. Lectern mode: read-only with "Take Book".
## Book data: components minecraft:writable_book_content {pages: [String]} and minecraft:written_book_content
## {title, author, generation, pages: [String]} (plain strings; JSON text components are flattened on read).
extends Control

var world
var stack: ItemStack            # book being read/edited (held item, or the lectern's book)
var lectern := Vector3i(0, -9999, 0)
var page := 0
var edit: TextEdit
var title_edit: LineEdit
var signing := false
var _page_lbl: Label
var _text_lbl: Label
var _root: Control


## Java BookViewScreen.renderBackground: renderTransparentBackground (0xC0101010 -> 0xD0101010) behind the book.
func _draw() -> void:
	var top := Color8(16, 16, 16, 0xC0)
	var bot := Color8(16, 16, 16, 0xD0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]), PackedColorArray([top, top, bot, bot]))


func closes_on_inventory_key() -> bool:
	return not _editable()


func _editable() -> bool:
	return stack.name() == "writable_book" and lectern.y == -9999


func _pages() -> Array:
	var key := "minecraft:writable_book_content" if stack.name() == "writable_book" else "minecraft:written_book_content"
	var c = stack.components.get(key, {})
	var pg: Array = c.get("pages", []) if c is Dictionary else []
	var out: Array = []
	for p in pg:
		if p is Dictionary:
			out.append(str(p.get("raw", p.get("text", ""))))
		else:
			var s := str(p)
			if s.begins_with("{") or s.begins_with("\""):
				s = world.commands.text_of(s)
			out.append(s)
	if out.is_empty():
		out.append("")
	return out


func _set_pages(pages: Array) -> void:
	stack.components["minecraft:writable_book_content"] = {"pages": pages}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	if lectern.y != -9999:
		page = int(BlockEntities.get_data(world, lectern).get("page", 0))
	_build()


func _build() -> void:
	if _root != null:
		_root.queue_free()
	var s := UiKit.scale()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := TextureRect.new()
	var src := UiKit.sprite("gui/book")
	if src != null:
		var at := AtlasTexture.new()
		at.atlas = src
		var k := src.get_width() / 256.0   # book.png is 256x256 (book in the top-left 192x192)
		at.region = Rect2(0, 0, 192 * k, 192 * k)
		bg.texture = at
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	var ox := (get_viewport_rect().size.x - 192 * s) / 2.0
	_root.add_child(bg)
	bg.position = Vector2(ox, 2 * s)
	bg.size = Vector2(192, 192) * s
	var pages := _pages()
	page = clampi(page, 0, pages.size() - 1)
	if signing:
		var v := VBoxContainer.new()
		v.position = Vector2(ox + 36 * s, 30 * s)
		v.size = Vector2(114, 140) * s
		_root.add_child(v)
		var l1 := UiKit.label("Enter Book Title:")
		l1.add_theme_color_override("font_color", Color.BLACK)
		v.add_child(l1)
		title_edit = LineEdit.new()
		title_edit.max_length = 32
		title_edit.custom_minimum_size = Vector2(114, 16) * s
		v.add_child(title_edit)
		var l2 := UiKit.label("by " + _author())
		l2.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25))
		v.add_child(l2)
		var l3 := UiKit.label("Note! When you sign the book, it will no longer be editable.")
		l3.autowrap_mode = TextServer.AUTOWRAP_WORD
		l3.custom_minimum_size = Vector2(114, 40) * s
		l3.add_theme_color_override("font_color", Color.BLACK)
		v.add_child(l3)
		var row := HBoxContainer.new()
		row.position = Vector2(ox - 4 * s, 196 * s)   # Java: (C-100, 196) / (C+2, 196), 98 each
		row.add_theme_constant_override("separation", 4 * s)
		row.add_child(UiKit.button(Res.tr_key("book.finalizeButton", "Sign and Close"), _sign, 98))
		row.add_child(UiKit.button(Res.tr_key("gui.cancel", "Cancel"), func(): signing = false; _build(), 98))
		_root.add_child(row)
		title_edit.grab_focus()
		return
	_page_lbl = UiKit.label(Res.tr_fmt("book.pageIndicator", [page + 1, pages.size()], "Page %1$s of %2$s"), HORIZONTAL_ALIGNMENT_RIGHT)
	_page_lbl.add_theme_color_override("font_color", Color.BLACK)
	_page_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_page_lbl.position = Vector2(ox + 36 * s, 17 * s)   # Java: right edge at 148, y 18
	_page_lbl.size = Vector2(112, 10) * s
	_root.add_child(_page_lbl)
	if _editable():
		edit = TextEdit.new()
		edit.text = str(pages[page])
		edit.position = Vector2(ox + 36 * s, 30 * s)
		edit.size = Vector2(114, 128) * s
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.add_theme_color_override("font_color", Color.BLACK)
		edit.add_theme_color_override("caret_color", Color.BLACK)
		edit.add_theme_constant_override("line_spacing", UiKit.line_spacing_9())   # Java: 9-px lines
		var sb := StyleBoxEmpty.new()
		edit.add_theme_stylebox_override("normal", sb)
		edit.add_theme_stylebox_override("focus", sb)
		edit.text_changed.connect(_on_edit)
		_root.add_child(edit)
		edit.grab_focus()
	else:
		_text_lbl = UiKit.label(str(pages[page]), HORIZONTAL_ALIGNMENT_LEFT)
		_text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_text_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_text_lbl.add_theme_color_override("font_color", Color.BLACK)
		_text_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		_text_lbl.add_theme_constant_override("line_spacing", UiKit.line_spacing_9())
		_text_lbl.position = Vector2(ox + 36 * s, 30 * s)
		_text_lbl.size = Vector2(114, 128) * s
		_root.add_child(_text_lbl)
	# Java PageButton: widget/page_backward / page_forward (_highlighted), 23 x 13 at (43 / 116, 159)
	var back := _page_button(false)
	back.position = Vector2(ox + 43 * s, 159 * s)
	back.visible = page > 0
	_root.add_child(back)
	var fwd := _page_button(true)
	fwd.position = Vector2(ox + 116 * s, 159 * s)
	fwd.visible = page < pages.size() - 1 or (_editable() and pages.size() < 100)
	_root.add_child(fwd)
	var row2 := HBoxContainer.new()
	row2.position = Vector2(ox - 4 * s, 196 * s)
	row2.add_theme_constant_override("separation", 4 * s)
	if _editable():
		row2.add_child(UiKit.button(Res.tr_key("book.signButton", "Sign"), func(): signing = true; _build(), 98))
		row2.add_child(UiKit.button(Res.tr_key("gui.done", "Done"), _done, 98))
	elif lectern.y != -9999:
		row2.add_child(UiKit.button(Res.tr_key("gui.done", "Done"), _done, 98))
		row2.add_child(UiKit.button(Res.tr_key("lectern.take_book", "Take Book"), _take, 98))
	else:
		row2.add_child(UiKit.button(Res.tr_key("gui.done", "Done"), _done, 200))
	_root.add_child(row2)


func _page_button(forward: bool) -> TextureButton:
	var b := TextureButton.new()
	var base := "gui/sprites/widget/page_" + ("forward" if forward else "backward")
	b.texture_normal = UiKit.sprite(base)
	b.texture_hover = UiKit.sprite(base + "_highlighted")
	b.texture_focused = b.texture_hover
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.size = Vector2(23, 13) * UiKit.scale()
	b.custom_minimum_size = b.size
	b.pressed.connect(func():
		Audio.play_ui("item.book.page_turn")
		_turn(1 if forward else -1))
	return b


func _author() -> String:
	return Net.my_name if Net.active() else "Player"


func _on_edit() -> void:
	var t := edit.text
	if t.length() > 1024:
		t = t.substr(0, 1024)
		edit.text = t
	var pages := _pages()
	pages[page] = t
	_set_pages(pages)


func _turn(d: int) -> void:
	var pages := _pages()
	if _editable() and page + d >= pages.size() and pages.size() < 100:
		pages.append("")
		_set_pages(pages)
	page = clampi(page + d, 0, _pages().size() - 1)
	if lectern.y != -9999:
		var ld := BlockEntities.get_data(world, lectern)
		ld["page"] = page
		BlockEntities.set_data(world, lectern, ld)
	Audio.play("item.book.page_turn", world.player.pos, "Players")
	_build()


func _sign() -> void:
	var t := title_edit.text.strip_edges()
	if t == "":
		return
	var pages := _pages()
	while pages.size() > 1 and str(pages[pages.size() - 1]) == "":
		pages.pop_back()
	var wb := ItemStack.named("written_book", 1)
	wb.components["minecraft:written_book_content"] = {"title": t, "author": _author(), "generation": 0, "pages": pages}
	var inv: Inventory = world.player.inventory
	inv.set_slot(inv.selected, wb)
	world.inv_changed()
	Audio.play("item.book.put", world.player.pos, "Players")
	world.close_screen()


func _done() -> void:
	world.inv_changed()
	world.close_screen()


func _take() -> void:
	var ld := BlockEntities.get_data(world, lectern)
	if ld.has("book"):
		var b := ItemStack.from_dict(ld["book"])
		if world.player.inventory.add(b) > 0:
			world.entities.spawn_item(Vector3(lectern) + Vector3(0.5, 1.1, 0.5), b)
		ld.erase("book")
		BlockEntities.set_data(world, lectern, ld)
		var st: int = world.state_at(lectern.x, lectern.y, lectern.z)
		if st > 0 and Res.blocks.has_prop(st, "has_book"):
			world.set_block(lectern.x, lectern.y, lectern.z, Res.blocks.with_prop(st, "has_book", "false"))
		world.inv_changed()
	world.close_screen()
