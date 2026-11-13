## McList — Java AbstractSelectionList in GUI pixels: list area between the header and footer separators
## (gui/header_separator above, gui/footer_separator below, 2 px each), gui/menu_list_background tiled at 32 px
## (inworld_ variants in a level), rows `item_height` tall and `row_width` wide centred, selection outline
## (white when focused, 0x808080 otherwise, 1 px black inside), vanilla scroller sprites 6 px wide, wheel scroll by
## item_height / 2, drag on the scrollbar, arrow keys / Enter, double click (< 250 ms) activates.
## Rows are drawn by `draw_row.call(list, i, rect: Rect2 (screen px), hovered: bool, selected: bool)` onto
## `list.body` (a child clipped to the list area, like Java's scissor); `list.text(...)` draws text there.
class_name McList
extends Control

signal selected(i: int)
signal activated(i: int)

var count := 0
var item_height := 36
var row_width := 220
var header_px := 0          # extra GUI px at the top of the list content (vanilla headerHeight)
var scrollbar_inside := false   # Java TransferableSelectionList: scrollbar at the list's right edge - 6
var draw_row: Callable
var sel := -1
var scroll := 0.0           # GUI px
var _last_click := 0
var _drag := false
var _drag_off := 0.0
var _hover := -1
var _mouse := Vector2(-1, -1)
var _in_world := false
var body: Control
var row_widgets := {}       # row -> [[Control, Vector2 GUI offset from the row's content origin], ...]


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = false
	_in_world = UiKit.in_world(self)
	body = Control.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.clip_contents = true
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.draw.connect(_draw_body)
	add_child(body)
	resized.connect(func():
		_clamp()
		_redraw())
	focus_entered.connect(_redraw)
	focus_exited.connect(_redraw)
	mouse_exited.connect(func():
		_hover = -1
		_mouse = Vector2(-1, -1)
		_redraw())


func set_count(n: int) -> void:
	count = n
	if sel >= n:
		sel = n - 1
	_clamp()
	_redraw()


func select(i: int, ensure_visible := true) -> void:
	sel = clampi(i, -1, count - 1)
	if ensure_visible and sel >= 0 and size.y >= item_height * gs():   # unsized lists (before layout) don't scroll
		var top := float(header_px + 4 + sel * item_height)
		var vis := size.y / float(UiKit.scale())
		if top - scroll < 0:
			scroll = top
		elif top + item_height - scroll > vis:
			scroll = top + item_height - vis
		_clamp()
	_redraw()
	selected.emit(sel)


func gs() -> float:
	return float(UiKit.scale())


func row_left() -> float:
	return floorf(size.x / gs() / 2.0) - floorf(row_width / 2.0) + 2.0


func max_scroll() -> float:
	return maxf(0.0, float(header_px + count * item_height + 4) - size.y / gs())


func scrollbar_x() -> float:
	if scrollbar_inside:
		return size.x / gs() - 6.0
	return row_left() + row_width + 6.0 - 2.0


func _clamp() -> void:
	scroll = clampf(scroll, 0.0, max_scroll())


## Row index at a local mouse position, -1 outside rows (Java getEntryAtPosition).
func row_at(p: Vector2) -> int:
	var x := p.x / gs()
	var y := p.y / gs() + scroll - float(header_px) - 4.0
	if x < row_left() or x > row_left() + row_width - 4 or y < 0:
		return -1
	var i := int(y / item_height)
	return i if i < count else -1


## Row rectangle in GUI px relative to the list (Java: rowLeft, rowTop, rowWidth - 4, itemHeight - 4).
func row_rect(i: int) -> Rect2:
	var top := float(header_px + 4 + i * item_height) - scroll
	return Rect2(row_left(), top, row_width - 4, item_height - 4)


func mouse_gui() -> Vector2:
	return _mouse / gs()


func _draw() -> void:
	var s := gs()
	var w := size.x
	var h := size.y
	var bg := UiKit.sprite("gui/inworld_menu_list_background" if _in_world else "gui/menu_list_background")
	if bg != null:
		var k := s * 32.0 / float(bg.get_width())
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
		draw_texture_rect(bg, Rect2(Vector2.ZERO, Vector2(w, h) / k), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.44))
	_draw_chrome()


func _redraw() -> void:
	queue_redraw()
	if body != null:
		body.queue_redraw()
		_place_widgets()


## Interactive controls inside a row (Java ContainerObjectSelectionList children), clipped with the rows.
func add_row_widget(i: int, c: Control, off_gui: Vector2) -> void:
	body.add_child(c)
	if not row_widgets.has(i):
		row_widgets[i] = []
	row_widgets[i].append([c, off_gui])
	_place_widgets()


func clear_row_widgets() -> void:
	for i in row_widgets:
		for e in row_widgets[i]:
			(e[0] as Control).queue_free()
	row_widgets.clear()


func _place_widgets() -> void:
	var s := gs()
	var vis := size.y / s
	for i in row_widgets:
		var r := row_rect(i)
		var on := r.position.y + item_height > 0 and r.position.y < vis
		for e in row_widgets[i]:
			var c: Control = e[0]
			c.visible = on
			if on:
				c.position = (r.position + e[1]) * s


func _draw_body() -> void:
	var s := gs()
	var h := size.y
	var first := maxi(0, int((scroll - header_px - 4) / item_height))
	var last := mini(count - 1, int((scroll + h / s) / item_height) + 1)
	for i in range(first, last + 1):
		var r := row_rect(i)
		var rs := Rect2(r.position * s, r.size * s)
		if rs.end.y < 0 or rs.position.y > h:
			continue
		if i == sel:
			var outer := Color(1, 1, 1) if has_focus() else Color8(128, 128, 128)
			body.draw_rect(Rect2(rs.position - Vector2(2, 2) * s, rs.size + Vector2(4, 4) * s), outer)
			body.draw_rect(Rect2(rs.position - Vector2(1, 1) * s, rs.size + Vector2(2, 2) * s), Color(0, 0, 0))
		if draw_row.is_valid():
			draw_row.call(self, i, rs, i == _hover, i == sel)


func _draw_chrome() -> void:
	var s := gs()
	var w := size.x
	var h := size.y
	# scrollbar
	var ms := max_scroll()
	if ms > 0.0:
		var sx := scrollbar_x() * s
		var vis := h / s
		var content := vis + ms
		var bar_h := clampf(vis * vis / content, 32.0, vis - 8.0)
		var bar_y := scroll * (vis - bar_h) / ms
		var sbg := UiKit.nine("gui/sprites/widget/scroller_background")
		var sth := UiKit.nine("gui/sprites/widget/scroller")
		if sbg != null:
			draw_style_box(sbg, Rect2(sx, 0, 6 * s, h))
		else:
			draw_rect(Rect2(sx, 0, 6 * s, h), Color(0, 0, 0))
		if sth != null:
			draw_style_box(sth, Rect2(sx, bar_y * s, 6 * s, bar_h * s))
		else:
			draw_rect(Rect2(sx, bar_y * s, 6 * s, bar_h * s), Color(0.75, 0.75, 0.75))
	# separators sit just outside the list area
	var hs := UiKit.sprite("gui/inworld_header_separator" if _in_world else "gui/header_separator")
	var fs := UiKit.sprite("gui/inworld_footer_separator" if _in_world else "gui/footer_separator")
	if hs != null:
		draw_texture_rect(hs, Rect2(0, -2 * s, w, 2 * s), false)
	if fs != null:
		draw_texture_rect(fs, Rect2(0, h, w, 2 * s), false)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_mouse = e.position
		if _drag:
			var vis := size.y / gs()
			var ms := max_scroll()
			var bar_h := clampf(vis * vis / (vis + ms), 32.0, vis - 8.0)
			var y: float = e.position.y / gs() - _drag_off
			scroll = clampf(y / maxf(1.0, vis - bar_h) * ms, 0.0, ms)
		var hv := row_at(e.position)
		if hv != _hover or _drag:
			_hover = hv
		_redraw()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll += (-1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0) * item_height / 2.0
			_clamp()
			_redraw()
			accept_event()
			return
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
		grab_focus()
		var gx: float = e.position.x / gs()
		if max_scroll() > 0.0 and gx >= scrollbar_x() and gx < scrollbar_x() + 6:
			var vis := size.y / gs()
			var ms := max_scroll()
			var bar_h := clampf(vis * vis / (vis + ms), 32.0, vis - 8.0)
			var bar_y := scroll * (vis - bar_h) / ms
			var gy: float = e.position.y / gs()
			_drag_off = gy - bar_y if gy >= bar_y and gy <= bar_y + bar_h else bar_h / 2.0
			_drag = true
			accept_event()
			return
		var i := row_at(e.position)
		if i >= 0:
			var now := Time.get_ticks_msec()
			var dbl: bool = i == sel and now - _last_click < 250
			_last_click = now
			if i != sel:
				select(i, false)
			if dbl or e.double_click:
				activated.emit(i)
			accept_event()
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = false
	elif e is InputEventKey and e.pressed and has_focus():
		if e.keycode == KEY_UP:
			select(maxi(0, sel - 1))
			accept_event()
		elif e.keycode == KEY_DOWN:
			select(mini(count - 1, sel + 1))
			accept_event()
		elif (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER or e.keycode == KEY_SPACE) and sel >= 0:
			activated.emit(sel)
			accept_event()


## Text helper for row drawers: Java drawString with drop shadow (color * 0.25, offset 1 GUI px).
func text(pos_gui_screen: Vector2, t: String, col: Color, shadow := true, max_w := -1.0) -> void:
	var s := gs()
	var f := UiKit.font()
	var fs := 8 * int(s)
	var p := pos_gui_screen + Vector2(0, 7 * s)   # baseline: ascent 7
	if shadow and Settings.get_v("text_shadow"):
		body.draw_string(f, p + Vector2(s, s), t, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, col.a))
	body.draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, col)


## Width of a string in GUI px.
static func text_w(t: String) -> float:
	return UiKit.font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
