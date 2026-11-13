## McButton — Java AbstractButton text rendering on top of the themed nine-slice sprite: white text (0xA0A0A0
## when inactive; `mc_color` meta overrides), drop shadow, centred at y = (h - 9) / 2 + 1, and Java
## renderScrollingString when the label is wider than the button minus 2 px each side: the text ping-pongs
## inside a clipped strip with Java's timing (period max(overflow / 2, 3) s). Godot's own label drawing is made
## transparent and clip_text keeps long labels from widening the button.
class_name McButton
extends Button

var _clip: Control
var _scroll := false


func _ready() -> void:
	clip_text = true
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color", "font_shadow_color"]:
		add_theme_color_override(c, Color(0, 0, 0, 0))
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.draw.connect(_draw_text)
	add_child(_clip)
	resized.connect(_fit)
	_fit()
	set_process(false)


func _fit() -> void:
	if _clip == null:
		return
	var s := float(UiKit.scale())
	_clip.position = Vector2(2 * s, 0)
	_clip.size = Vector2(maxf(0.0, size.x - 4 * s), size.y)
	_clip.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and _clip != null:
		_clip.queue_redraw()


func _process(_d: float) -> void:
	if _scroll:
		_clip.queue_redraw()
	else:
		set_process(false)


func _draw_text() -> void:
	if text == "":
		return
	var s := float(UiKit.scale())
	var f := UiKit.font()
	var col: Color = get_meta("mc_color") if has_meta("mc_color") else (McW.GRAY if disabled else Color(1, 1, 1))
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var avail := _clip.size.x / s
	var x := 0.0
	var was := _scroll
	_scroll = tw > avail
	if _scroll:
		var k := tw - avail
		var d := float(Time.get_ticks_msec()) / 1000.0
		var e := maxf(k * 0.5, 3.0)
		var t := sin(PI / 2.0 * cos(TAU * d / e)) / 2.0 + 0.5
		x = -lerpf(0.0, k, t)
		if not was:
			set_process(true)
	else:
		x = floorf(avail / 2.0) - floorf(tw / 2.0)
	var y := floorf((size.y / s - 9.0) / 2.0) + 1.0 + 7.0
	if Settings.get_v("text_shadow"):
		_clip.draw_string(f, Vector2(x + 1, y + 1) * s, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, col.a))
	_clip.draw_string(f, Vector2(x, y) * s, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8 * s), col)


## Godot 4.7 asks for a custom tooltip even when tooltip_text is empty: no text -> no tooltip (was an empty box).
func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.strip_edges() == "":
		return null
	return UiKit.tooltip_label(for_text)


## Text colour override (Java ChatFormatting on the message); null clears it.
func set_color(c) -> void:
	if c == null:
		remove_meta("mc_color")
	else:
		set_meta("mc_color", c)
	if _clip != null:
		_clip.queue_redraw()
