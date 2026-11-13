## SignScreen — Java SignEditScreen / HangingSignEditScreen: gradient dim (renderTransparentBackground), "Edit Sign
## Message" centred at y 40, the sign drawn large from the 26.x GUI textures - gui/signs/<wood> (24 x 26: board +
## stick) at 4x with its board centred on y 90, or gui/hanging_signs/<wood> (16 x 16) at 4.5x centred on y 125 - and
## the four lines edited in place (centred, sign dye colour, 10 / 9 px apart, each limited to the sign width: 90 px,
## hanging 60 px). Enter / Down: next line, Up: previous; Done (C-100, h/4 + 144, 200) saves. One side (front/back).
extends Control

var world
var pos := Vector3i.ZERO
var front := true
var edits: Array = []
var max_w := 90.0
var _hanging := false
var _tex: Texture2D
var _title: Label
var _done_btn: Button
var _color := Color(0, 0, 0)


func closes_on_inventory_key() -> bool:
	return false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	var nm := Res.blocks.name_of(world.state_at(pos.x, pos.y, pos.z))
	_hanging = nm.ends_with("hanging_sign")
	if _hanging:
		max_w = 60.0
	var wood := nm.trim_suffix("_wall_hanging_sign").trim_suffix("_hanging_sign").trim_suffix("_wall_sign").trim_suffix("_sign")
	_tex = UiKit.sprite(("gui/hanging_signs/" if _hanging else "gui/signs/") + wood)
	var d := Signs.data(world, pos)
	var side := "front" if front else "back"
	var lines: Array = d.get(side, ["", "", "", ""])
	var dye := str(d.get(side + "_color", d.get("color", "black")))
	_color = DYE_TEXT.get(dye, Color(0, 0, 0))
	_title = McW.text(Res.tr_key("sign.edit", "Edit Sign Message"), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	for i in 4:
		var e := LineEdit.new()
		e.text = str(lines[i]) if i < lines.size() else ""
		e.alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.max_length = 384
		for st in ["normal", "focus", "read_only"]:
			e.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		e.add_theme_color_override("font_color", _color)
		e.add_theme_color_override("caret_color", _color)
		e.add_theme_color_override("selection_color", Color(0, 0, 1, 0.4))
		e.add_theme_constant_override("minimum_character_width", 0)
		e.text_changed.connect(_limit.bind(i))
		e.text_submitted.connect(func(_t): _next(i))
		add_child(e)
		edits.append(e)
	_done_btn = UiKit.button(Res.tr_key("gui.done", "Done"), _done, 200)
	add_child(_done_btn)
	_layout()
	resized.connect(_layout)
	(edits[0] as LineEdit).grab_focus()


## Java DyeColor.getTextColor for sign text (default black).
const DYE_TEXT := {"white": Color8(255, 255, 255), "orange": Color8(255, 104, 31), "magenta": Color8(255, 0, 255),
	"light_blue": Color8(154, 192, 205), "yellow": Color8(255, 255, 0), "lime": Color8(191, 255, 0), "pink": Color8(255, 105, 180),
	"gray": Color8(128, 128, 128), "light_gray": Color8(211, 211, 211), "cyan": Color8(0, 255, 255), "purple": Color8(160, 32, 240),
	"blue": Color8(0, 0, 255), "brown": Color8(139, 69, 19), "green": Color8(0, 255, 0), "red": Color8(255, 0, 0), "black": Color8(0, 0, 0)}


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(_title, 0, 40 - 1, gw, 9)
	var cy := 125.0 if _hanging else 90.0
	var lh := 9.0 if _hanging else 10.0
	for i in 4:
		McW.place(edits[i], c - max_w / 2.0 - 4.0, cy - 2.0 * lh + lh * i - 1.0, max_w + 8.0, lh)
	McW.place(_done_btn, c - 100, floorf(gh / 4.0) + 144, 200, 20)
	queue_redraw()


func _draw() -> void:
	# Java renderTransparentBackground: 0xC0101010 -> 0xD0101010
	var top := Color8(16, 16, 16, 0xC0)
	var bot := Color8(16, 16, 16, 0xD0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]), PackedColorArray([top, top, bot, bot]))
	if _tex == null:
		return
	var s := float(UiKit.scale())
	var c := floorf(size.x / s / 2.0)
	if _hanging:
		# Java HangingSignEditScreen: translate(0, -13) then scale 4.5 around the line centre (y 125)
		draw_texture_rect(_tex, Rect2(Vector2(c - 36, 125 - 13 - 36) * s, Vector2(72, 72) * s), false)
	else:
		# board rows 0..11 centred on y 90, stick rows 12..25 below it
		draw_texture_rect(_tex, Rect2(Vector2(c - 48, 90 - 24) * s, Vector2(96, 104) * s), false)

func _limit(t: String, i: int) -> void:
	var f := UiKit.font()
	var e: LineEdit = edits[i]
	var s := t
	while s.length() > 0 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > max_w:
		s = s.substr(0, s.length() - 1)
	if s != t:
		e.text = s
		e.caret_column = s.length()


func _next(i: int) -> void:
	if i < 3:
		(edits[i + 1] as LineEdit).grab_focus()
	else:
		_done()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var cur := -1
		for i in 4:
			if (edits[i] as LineEdit).has_focus():
				cur = i
		if cur >= 0 and event.keycode == KEY_DOWN:
			(edits[mini(cur + 1, 3)] as LineEdit).grab_focus()
			get_viewport().set_input_as_handled()
		elif cur >= 0 and event.keycode == KEY_UP:
			(edits[maxi(cur - 1, 0)] as LineEdit).grab_focus()
			get_viewport().set_input_as_handled()


func _done() -> void:
	var d := Signs.data(world, pos)
	var lines: Array = []
	for e in edits:
		lines.append((e as LineEdit).text)
	d["front" if front else "back"] = lines
	BlockEntities.set_data(world, pos, d)
	Signs.mark_dirty()
	world.close_screen()
