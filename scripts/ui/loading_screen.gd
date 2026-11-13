## LoadingScreen — progress bar + message while content loads or a world spawns.
extends Control

var bar: ProgressBar
var msg: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme() if Res.is_loaded() else null
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(420, 0)
	cc.add_child(v)
	msg = Label.new()
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.text = "Loading..."
	v.add_child(msg)
	bar = ProgressBar.new()
	bar.max_value = 1.0
	bar.custom_minimum_size = Vector2(400, 16)
	v.add_child(bar)


func set_progress(m: String, f: float) -> void:
	if msg:
		msg.text = m
		bar.value = f
