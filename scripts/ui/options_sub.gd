## OptionsSub — Java OptionsSubScreen + OptionsList: HeaderAndFooterLayout (33 / 33) with the title centred in
## the header, an McList between the separators with 25-px rows 310 wide: pairs of 150-px widgets at C-155 and
## C+5, `big` 310-px widgets, and section headers (26.x addHeader: centred white text). Footer: Done (200) or
## custom buttons. Widgets bind straight to Settings keys through the helpers below; vanilla options Recraft does
## not implement are shown as disabled buttons whose tooltip gives the reason (never a dead control).
class_name OptionsSub
extends Control

var title := ""
var rows: Array = []        # ["header", text] | [Control] | [Control, Control] | ["big", Control] | ["at", [Control, x, w], ...]
var footer: Array = []      # [[text, callable, width]]; empty = Done (200)
var on_close: Callable
var list: McList
var _title: Label
var _foot: Array = []
var item_height := 25
var row_width := 310


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	_title = McW.text(title, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	list = McList.new()
	list.item_height = item_height
	list.row_width = row_width
	list.draw_row = _draw_row
	add_child(list)
	list.set_count(rows.size())
	list.sel = -1
	for i in rows.size():
		var r: Array = rows[i]
		if r.is_empty() or (r[0] is String and r[0] == "header"):
			continue
		if r[0] is String and r[0] == "at":
			for k in range(1, r.size()):
				var e: Array = r[k]
				_size(e[0], e[2])
				list.add_row_widget(i, e[0], Vector2(e[1], 5 if e[0] is Label else 0))
			continue
		if r[0] is String and r[0] == "big":
			_size(r[1], 310)
			list.add_row_widget(i, r[1], Vector2(-2, 0))
		else:
			_size(r[0], 150)
			list.add_row_widget(i, r[0], Vector2(-2, 5 if r[0] is Label else 0))
			if r.size() > 1 and r[1] != null:
				_size(r[1], 150)
				list.add_row_widget(i, r[1], Vector2(158, 0))
	if footer.is_empty():
		footer = [[Res.tr_key("gui.done", "Done"), func(): close(), 200]]
	for f in footer:
		var b := UiKit.button(f[0], f[1], f[2])
		add_child(b)
		_foot.append([b, f[2]])
	_layout()
	resized.connect(_layout)


static func _size(c: Control, w: int) -> void:
	c.custom_minimum_size = Vector2(w, 20) * float(UiKit.scale())
	c.size = c.custom_minimum_size


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	McW.place(_title, 0, 12 - 1, gw, 9)
	McW.place(list, 0, 33, gw, maxf(0.0, gh - 66))
	var total := 0.0
	for f in _foot:
		total += float(f[1])
	total += 8.0 * (_foot.size() - 1)
	var x := floorf((gw - total) / 2.0)
	for f in _foot:
		McW.place(f[0], x, gh - 27, f[1], 20)
		x += float(f[1]) + 8.0
	list._redraw()


func _draw_row(l: McList, i: int, r: Rect2, _h: bool, _s: bool) -> void:
	var row: Array = rows[i]
	if row.size() >= 2 and row[0] is String and row[0] == "header":
		var s := l.gs()
		var t := str(row[1])
		var x := r.position.x + floorf((310.0 - 4.0 - McList.text_w(t)) / 2.0) * s
		l.text(Vector2(x, r.position.y + 6 * s), t, Color(1, 1, 1))


func close() -> void:
	Settings.save()
	var top := get_parent() != null and not get_parent().has_method("_restore")   # a screen of its own (not inside Options)
	queue_free()
	if on_close.is_valid():
		on_close.call()
	elif top:
		UiKit.return_fallback(self)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


# ---------------------------------------------------------------- binding helpers

## Cycle over `values` of a Settings key with display `names`.
static func cyc(label: String, key: String, values: Array, names: Array, tip := "") -> Button:
	var idx := maxi(0, values.find(Settings.get_v(key)))
	var b := McW.cycle(label, names, idx, func(i): Settings.set_v(key, values[i]))
	b.tooltip_text = tip
	return b


static func tog(label: String, key: String, tip := "", invert := false) -> Button:
	var on := bool(Settings.get_v(key)) != invert
	var b := McW.on_off(label, on, func(v): Settings.set_v(key, v != invert))
	b.tooltip_text = tip
	return b


## Slider over [mn, mx] with `step`; `fmt(v) -> String` builds the label from the real value.
static func sld(key: String, mn: float, mx: float, step: float, fmt: Callable, width := 150) -> McSlider:
	var v := float(Settings.get_v(key))
	var n := int(roundf((mx - mn) / step)) if step > 0 else 0
	var to_v := func(t: float) -> float: return mn + t * (mx - mn)
	var s := McSlider.make((v - mn) / maxf(0.0001, mx - mn), n, func(t): return fmt.call(to_v.call(t)),
		func(t):
			var nv: float = to_v.call(t)
			Settings.set_v(key, int(roundf(nv)) if step >= 1.0 and is_equal_approx(step, roundf(step)) else nv), width)
	return s


## Slider stepping through an explicit value list (Java OptionInstance with a value list).
static func sld_list(key: String, values: Array, fmt: Callable, width := 150) -> McSlider:
	var idx := maxi(0, values.find(Settings.get_v(key)))
	var n := maxi(1, values.size() - 1)
	return McSlider.make(float(idx) / n, n, func(t): return fmt.call(values[int(roundf(t * n))]),
		func(t): Settings.set_v(key, values[int(roundf(t * n))]), width)


static func btn(text: String, cb: Callable) -> Button:
	return UiKit.button(text, cb, 150)


## A vanilla option Recraft does not implement: disabled, reason in the tooltip.
static func na(text: String, reason: String) -> Button:
	var b := UiKit.button(text, func(): pass, 150)
	b.disabled = true
	b.tooltip_text = reason
	return b


static func pct(label: String) -> Callable:
	return func(v): return (Res.tr_key("options.off", "OFF") if v <= 0.0 else "%d%%" % int(roundf(v * 100.0))).insert(0, label + ": ")
