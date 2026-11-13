## McConfirm — Java ConfirmScreen: title (white, centred at y 70), message (wrapped, centred from y 90), two
## 150-px buttons at y = clamp(90 + message height + 20, h/6 + 96, h - 24): yes at C-155, no at C+5. Esc = no.
## Shown over its parent screen (whose own widgets are hidden while open, as vanilla replaces the screen); never
## a keyboard-default destructive action (focus starts on the "no" button).
class_name McConfirm
extends Control

var title_text := ""
var message := ""
var yes_text := ""
var no_text := ""
var on_yes: Callable
var on_no: Callable
var _hidden: Array = []
var _title: Label
var _msg: Label
var _yes: Button
var _no: Button


static func open(parent: Control, title: String, msg: String, yes: String, no: String, yes_cb: Callable, no_cb: Callable = Callable()) -> McConfirm:
	var c := McConfirm.new()
	c.title_text = title
	c.message = msg
	c.yes_text = yes
	c.no_text = no
	c.on_yes = yes_cb
	c.on_no = no_cb
	for ch in parent.get_children():
		if ch is CanvasItem and (ch as CanvasItem).visible:
			(ch as CanvasItem).visible = false
			c._hidden.append(ch)
	parent.add_child(c)
	return c


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	_title = McW.text(title_text, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	_msg = McW.text(message, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_msg)
	_yes = UiKit.button(yes_text, func(): _close(on_yes), 150)
	_no = UiKit.button(no_text, func(): _close(on_no), 150)
	add_child(_yes)
	add_child(_no)
	_layout()
	resized.connect(_layout)
	_no.grab_focus()


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(_title, 0, 70 - 1, gw, 9)
	var mw := minf(gw - 50.0, 300.0)
	_msg.custom_minimum_size = Vector2(mw * s, 0)
	_msg.size = Vector2(mw * s, 0)
	_msg.position = Vector2(c - mw / 2.0, 90 - 1) * s
	var lines := maxi(1, _msg.get_line_count())
	var y := clampf(90.0 + lines * 9.0 + 20.0, gh / 6.0 + 96.0, gh - 24.0)
	McW.place(_yes, c - 155, y, 150, 20)
	McW.place(_no, c + 5, y, 150, 20)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close(on_no)


func _close(cb: Callable) -> void:
	for ch in _hidden:
		if is_instance_valid(ch):
			ch.visible = true
	queue_free()
	if cb.is_valid():
		cb.call()
