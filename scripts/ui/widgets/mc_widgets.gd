## McW — vanilla Java widget builders in GUI pixels: CycleButton ("Label: Value", shift-click cycles back),
## on/off switches (OFF/ON value-only 44 px), EditBox (text_field sprite, 0xE0E0E0 text, gray hint, 4 px inset),
## StringWidget / gray info text, tab buttons, and place() for absolute GUI-pixel geometry (x, y, w, h * scale).
class_name McW

const GRAY := Color8(160, 160, 160)      # 0xA0A0A0 (-6250336): inactive text / labels
const DGRAY := Color8(128, 128, 128)     # 0x808080 (-8355712): list secondary text
const EDIT_TEXT := Color8(224, 224, 224) # 0xE0E0E0 EditBox text
const RED := Color8(255, 85, 85)


static func place(c: Control, x: float, y: float, w: float = -1, h: float = -1) -> void:
	var s := float(UiKit.scale())
	c.position = Vector2(x, y) * s
	if w >= 0 and h >= 0:
		# minimum first: a size below the old minimum would be clamped (stale sizes after a GUI scale change)
		c.custom_minimum_size = Vector2(w, h) * s
		c.size = c.custom_minimum_size


## Java CycleButton: shows "<label>: <value>" (or only the value), cycles forward on click, backward with shift.
static func cycle(label: String, values: Array, idx: int, on_change: Callable, width := 150, value_only := false) -> Button:
	var b := UiKit.button("", func(): pass, width)
	b.set_meta("values", values)
	b.set_meta("idx", idx)
	b.set_meta("label", label)
	b.set_meta("value_only", value_only)
	_cycle_text(b)
	# replace the default handler: UiKit.button connected `cb`; cycling needs the modifier state
	for c in b.pressed.get_connections():
		b.pressed.disconnect(c["callable"])
	b.pressed.connect(func():
		Audio.play_ui("ui.button.click")
		var vals: Array = b.get_meta("values")
		var n := vals.size()
		if n == 0:
			return
		var i: int = int(b.get_meta("idx"))
		i = (i + (n - 1 if Input.is_key_pressed(KEY_SHIFT) else 1)) % n
		b.set_meta("idx", i)
		_cycle_text(b)
		on_change.call(i))
	return b


static func cycle_set(b: Button, idx: int) -> void:
	b.set_meta("idx", idx)
	_cycle_text(b)


static func cycle_values(b: Button, values: Array, idx: int) -> void:
	b.set_meta("values", values)
	cycle_set(b, idx)


static func _cycle_text(b: Button) -> void:
	var vals: Array = b.get_meta("values")
	var i: int = int(b.get_meta("idx"))
	var v := str(vals[i]) if i >= 0 and i < vals.size() else ""
	var lab: String = b.get_meta("label")
	b.text = v if bool(b.get_meta("value_only")) or lab == "" else "%s: %s" % [lab, v]


## Java CycleButton.onOffBuilder: "<label>: ON/OFF" (value_only -> just ON / OFF).
static func on_off(label: String, on: bool, on_change: Callable, width := 150, value_only := false) -> Button:
	var vals := [Res.tr_key("options.off", "OFF"), Res.tr_key("options.on", "ON")]
	return cycle(label, vals, 1 if on else 0, func(i): on_change.call(i == 1), width, value_only)


static func is_on(b: Button) -> bool:
	return int(b.get_meta("idx")) == 1


## Java EditBox.
static func edit(text: String, hint := "", max_len := 32) -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	le.placeholder_text = hint
	le.max_length = max_len
	le.add_theme_color_override("font_color", EDIT_TEXT)
	le.add_theme_color_override("font_placeholder_color", Color8(112, 112, 112))
	le.add_theme_color_override("caret_color", EDIT_TEXT)
	le.add_theme_color_override("selection_color", Color(0, 0, 1, 0.5))
	le.add_theme_constant_override("minimum_character_width", 0)
	var s := UiKit.scale()
	for st in ["normal", "focus", "read_only"]:
		var sb: StyleBox = UiKit.nine("gui/sprites/widget/text_field_highlighted" if st == "focus" else "gui/sprites/widget/text_field")
		if sb != null:
			sb = sb.duplicate()
			sb.content_margin_left = 4 * s
			sb.content_margin_right = 4 * s
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
			le.add_theme_stylebox_override(st, sb)
	return le


static func text(t: String, col := Color(1, 1, 1), align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(t, align)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l


## Gray multi-line info text wrapped to `width` GUI px.
static func info(t: String, width: int) -> Label:
	var l := text(t, GRAY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width * UiKit.scale()
	return l


## Java TabButton: tab sprite (selected / highlighted variants), text white (0xA0A0A0 inactive), y +3 when not
## selected, 1 px underline under the selected tab's text.
class TabButton extends Button:
	var selected := false

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		flat = true
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		add_theme_color_override("font_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_hover_pressed_color", Color(0, 0, 0, 0))
		add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))

	func _draw() -> void:
		var s := float(UiKit.scale())
		var hl := is_hovered() or has_focus()
		var spr := "gui/sprites/widget/tab" + ("_selected" if selected else "") + ("_highlighted" if hl else "")
		var sb := UiKit.nine(spr)
		if sb != null:
			draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if selected:
			# Java TabButton: renderMenuBackground(x + 2, y + 2, right - 2, bottom) inside the open tab
			var mb := UiKit.sprite("gui/inworld_menu_background" if UiKit.in_world(self) else "gui/menu_background")
			if mb != null:
				var k := s * 32.0 / float(mb.get_width())
				draw_set_transform(Vector2(2, 2) * s, 0.0, Vector2(k, k))
				draw_texture_rect(mb, Rect2(Vector2.ZERO, (size - Vector2(4, 2) * s) / k), true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var f := UiKit.font()
		var col := Color(1, 1, 1) if not disabled else McW.GRAY
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var top := 0.0 if selected else 3.0
		var bottom := size.y / s
		var ty := floorf(top + (bottom - top - 9.0) / 2.0) + 1.0
		var tx := floorf((size.x / s - tw) / 2.0)
		if Settings.get_v("text_shadow"):
			draw_string(f, Vector2(tx + 1, ty + 7 + 1) * s, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), Color(col.r * 0.25, col.g * 0.25, col.b * 0.25))
		draw_string(f, Vector2(tx, ty + 7) * s, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), col)
		if selected:
			var uw := minf(tw, size.x / s - 4.0)
			var ux := floorf((size.x / s - uw) / 2.0)
			draw_rect(Rect2(Vector2(ux, size.y / s - 2.0) * s, Vector2(uw, 1) * s), col)
