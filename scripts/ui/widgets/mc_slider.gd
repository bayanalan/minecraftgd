## McSlider — Java AbstractSliderButton: widget/slider (slider_highlighted when focused) nine-slice track, an
## 8 x 20 widget/slider_handle(_highlighted when hovered/focused) at x + value * (width - 8), centred label text
## (white, 0xA0A0A0 inactive). Click/drag sets the value; arrow keys step; the label comes from `fmt.call(v)`.
## `value` is normalised 0..1; `steps` > 0 snaps to that many intervals; `on_change(v01)` fires on every change.
class_name McSlider
extends Control

var value := 0.0
var steps := 0
var fmt: Callable
var on_change: Callable
var disabled := false
var _drag := false
var _hover := false


static func make(v01: float, nsteps: int, format: Callable, changed: Callable, width := 150) -> McSlider:
	var s := McSlider.new()
	s.value = clampf(v01, 0.0, 1.0)
	s.steps = nsteps
	s.fmt = format
	s.on_change = changed
	s.custom_minimum_size = Vector2(width, 20) * float(UiKit.scale())
	s.size = s.custom_minimum_size
	return s


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)


func _draw() -> void:
	var s := float(UiKit.scale())
	var foc := has_focus() and not disabled
	var track := UiKit.nine("gui/sprites/widget/slider_highlighted" if foc else "gui/sprites/widget/slider")
	if track != null:
		draw_style_box(track, Rect2(Vector2.ZERO, size))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0))
	if not disabled:
		var hx := floorf(value * (size.x / s - 8.0))
		var hs := UiKit.nine("gui/sprites/widget/slider_handle_highlighted" if (_hover or foc) else "gui/sprites/widget/slider_handle")
		if hs != null:
			draw_style_box(hs, Rect2(Vector2(hx, 0) * s, Vector2(8, 20) * s))
	var t := str(fmt.call(value)) if fmt.is_valid() else ""
	var f := UiKit.font()
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var col := McW.GRAY if disabled else Color(1, 1, 1)
	var p := Vector2(floorf((size.x / s - tw) / 2.0), floorf((size.y / s - 8.0) / 2.0) + 7.0) * s
	if Settings.get_v("text_shadow"):
		draw_string(f, p + Vector2(s, s), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), Color(col.r * 0.25, col.g * 0.25, col.b * 0.25))
	draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), col)


## Godot 4.7 asks for a custom tooltip even when tooltip_text is empty: no text -> no tooltip (was an empty box).
func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.strip_edges() == "":
		return null
	return UiKit.tooltip_label(for_text)


func _set_from_x(x: float) -> void:
	var s := float(UiKit.scale())
	set_value((x / s - 4.0) / maxf(1.0, size.x / s - 8.0))


func set_value(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	if steps > 0:
		v = roundf(v * steps) / steps
	if v == value:
		return
	value = v
	queue_redraw()
	if on_change.is_valid():
		on_change.call(value)


func _gui_input(e: InputEvent) -> void:
	if disabled:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			grab_focus()
			_drag = true
			_set_from_x(e.position.x)
			accept_event()
		else:
			if _drag:
				Audio.play_ui("ui.button.click")
			_drag = false
	elif e is InputEventMouseMotion and _drag:
		_set_from_x(e.position.x)
		accept_event()
	elif e is InputEventKey and e.pressed and has_focus():
		var st := 1.0 / float(steps) if steps > 0 else 0.01
		if e.keycode == KEY_LEFT:
			set_value(value - st)
			accept_event()
		elif e.keycode == KEY_RIGHT:
			set_value(value + st)
			accept_event()
