## UiKit — shared GUI toolkit: pixel-scaled theme built from the user's imported GUI sprites
## (gui/sprites/widget/button*.png nine-slices, slots, backgrounds) and the bitmap font (font/ascii.png via
## the installed font provider JSON) with an original fallback look in placeholder mode.
## Contract: theme() -> Theme; button(text, cb); label(text); sprite(path) -> Texture2D; scale() -> int.
class_name UiKit

static var _theme: Theme
static var _font: Font
static var _sprites: Dictionary = {}


## The GUI scale every screen lays out and draws with. Committed by apply_scale (Java Minecraft.resizeDisplay):
## changing the setting or the window size re-lays-out the open screens at once, so sizes, text and sprites never mix
## two scales (they did: widgets drew text at the new scale inside boxes sized at the old one until a restart).
static var _scale := 0


static func scale() -> int:
	if _scale <= 0:
		_scale = Settings.gui_scale()
	return _scale


## Applies the current effective GUI scale (setting + window size) to the GUI under roots: a new theme, every size
## baked at the old scale (minimum sizes, font / constant overrides, absolutely placed controls) converted, then each
## screen's own layout re-run (Java Screen.resize -> init). Returns true when the scale changed.
static func apply_scale(roots: Array) -> bool:
	var ns := Settings.gui_scale()
	var old := scale()
	if ns == old:
		return false
	_scale = ns
	reset_theme()
	var nt := theme()
	var k := float(ns) / float(old)
	# snapshot first: resizing a parent runs its handlers (e.g. McButton._fit), which would otherwise re-fit children
	# that are then scaled a second time
	var snap: Array = []
	for r in roots:
		if r != null and is_instance_valid(r):
			for ch in r.get_children():   # the roots themselves are sized to the window, not in GUI pixels
				_snapshot(ch, snap)
	for e in snap:
		if is_instance_valid(e[0]):
			_rescale_control(e, nt, k)
	for r in roots:
		if r != null and is_instance_valid(r):
			_relayout_node(r)
	return true


static func _snapshot(n: Node, out: Array) -> void:
	if n is Control:
		var c := n as Control
		out.append([c, c.position, c.size, c.custom_minimum_size])
	for ch in n.get_children():
		_snapshot(ch, out)


static func _rescale_control(e: Array, nt: Theme, k: float) -> void:
	if true:
		var c: Control = e[0]
		var old_pos: Vector2 = e[1]
		var old_size: Vector2 = e[2]
		var old_min: Vector2 = e[3]
		if c.theme != null and c.theme.has_meta("uikit"):
			c.theme = nt
		if old_min != Vector2.ZERO:
			c.custom_minimum_size = (old_min * k).round()
		if c.has_theme_font_size_override("font_size"):
			c.add_theme_font_size_override("font_size", int(roundf(c.get_theme_font_size("font_size") * k)))
		for cn in ["shadow_offset_x", "shadow_offset_y", "icon_max_width", "outline_size"]:
			if c.has_theme_constant_override(cn):
				c.add_theme_constant_override(cn, int(roundf(c.get_theme_constant(cn) * k)))
		if c.has_theme_constant_override("line_spacing"):
			c.add_theme_constant_override("line_spacing", line_spacing_9())
		# placed once at creation (top-left anchors, not container-managed): position / size baked at the old scale;
		# controls placed by a screen's _layout are placed again right after
		var free_placed := c.anchor_left == 0.0 and c.anchor_top == 0.0 and c.anchor_right == 0.0 and c.anchor_bottom == 0.0
		if free_placed and not (c.get_parent() is Container):
			c.position = (old_pos * k).round()
			c.size = (old_size * k).round()


static func _relayout_node(n: Node) -> void:
	if n.has_method("_layout"):
		n.call("_layout")
	if n is McList:
		(n as McList)._redraw()
	if n is CanvasItem:
		(n as CanvasItem).queue_redraw()
	for ch in n.get_children():
		_relayout_node(ch)


static func sprite(path: String) -> Texture2D:
	if _sprites.has(path):
		return _sprites[path]
	var img := Res.load_image(path) if Res.mode == "vanilla" else null
	var t: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	_sprites[path] = t
	return t


static func font() -> Font:
	if _font != null:
		return _font
	_font = _bitmap_font()
	if _font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
		sf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font = sf
	return _font


## Builds a FontFile from the installed ascii bitmap provider (8x8 cells, per-glyph widths from pixels).
static func _bitmap_font() -> Font:
	if Res.mode != "vanilla":
		return null
	# chars rows contain \u0000 padding; remap before parsing to avoid NUL warnings
	var raw := Res.jar.read_text("assets/minecraft/font/include/default.json").replace("\\u0000", "\\u0001") if Res.jar != null else ""
	var prov = JSON.parse_string(raw) if raw != "" else null
	var chars: Array = []
	var file := "font/ascii"
	var ascent := 7
	if prov is Dictionary:
		for p in prov.get("providers", []):
			if p is Dictionary and str(p.get("type", "")) == "bitmap" and str(p.get("file", "")).ends_with("ascii.png"):
				chars = p.get("chars", [])
				file = str(p["file"]).trim_prefix("minecraft:").trim_suffix(".png")
				ascent = int(p.get("ascent", 7))
				break
	var img := Res.load_image(file)
	if img == null or chars.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	var cell_w := img.get_width() / 16
	var cell_h := img.get_height() / chars.size()
	var f := FontFile.new()
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.fixed_size = 8
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	var size := Vector2i(8, 0)
	f.set_texture_image(0, size, 0, img)
	f.set_cache_ascent(0, 8, ascent)
	f.set_cache_descent(0, 8, 8 - ascent + 1)
	for row in chars.size():
		var line := str(chars[row])
		for col in line.length():
			var ch := line.unicode_at(col)
			if ch <= 1:
				continue
			var x0 := col * cell_w
			var y0 := row * cell_h
			var w := 0
			for x in range(cell_w - 1, -1, -1):
				var any := false
				for y in cell_h:
					if img.get_pixel(x0 + x, y0 + y).a > 0.1:
						any = true
						break
				if any:
					w = x + 1
					break
			if ch == 32:
				w = 3
			f.set_glyph_advance(0, 8, ch, Vector2(w + 1, 0))
			f.set_glyph_offset(0, size, ch, Vector2(0, -ascent))
			f.set_glyph_size(0, size, ch, Vector2(cell_w, cell_h))
			f.set_glyph_uv_rect(0, size, ch, Rect2(x0, y0, cell_w, cell_h))
			f.set_glyph_texture_idx(0, size, ch, 0)
	f.fallbacks = [SystemFont.new()]
	return f


static func _nine(path: String, _margin: int = 0) -> StyleBox:
	return nine(path)


static var _nines: Dictionary = {}


## Java GuiSpriteScaling from the sprite's .png.mcmeta (nine_slice border / tile / stretch), as a StyleBoxTexture
## whose texture is the sprite pre-scaled by the GUI scale (nearest), so borders and texels are exactly one GUI
## pixel at any scale; nine-slice edges + centre tile like vanilla (stretch_inner false).
static func nine(path: String, s: int = 0) -> StyleBoxTexture:
	if s <= 0:
		s = scale()
	var key := "%s@%d" % [path, s]
	if _nines.has(key):
		return _nines[key]
	var img := Res.load_image(path) if Res.mode == "vanilla" else null
	if img == null:
		_nines[key] = null
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var b := sprite_border(path)
	if s > 1:
		img.resize(img.get_width() * s, img.get_height() * s, Image.INTERPOLATE_NEAREST)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_left = b[0] * s
	sb.texture_margin_top = b[1] * s
	sb.texture_margin_right = b[2] * s
	sb.texture_margin_bottom = b[3] * s
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	_nines[key] = sb
	return sb


## Nine-slice border [left, top, right, bottom] in sprite pixels from gui/sprites/<path>.png.mcmeta (0 = stretch).
static func sprite_border(path: String) -> Array:
	var raw := Res.jar.read_text("assets/minecraft/textures/" + path + ".png.mcmeta") if Res.jar != null else ""
	var j = JSON.parse_string(raw) if raw != "" else null
	if j is Dictionary:
		var sc = j.get("gui", {}).get("scaling", {})
		if sc is Dictionary and str(sc.get("type", "")) == "nine_slice":
			var bd = sc.get("border", 0)
			if bd is Dictionary:
				return [int(bd.get("left", 0)), int(bd.get("top", 0)), int(bd.get("right", 0)), int(bd.get("bottom", 0))]
			return [int(bd), int(bd), int(bd), int(bd)]
	return [0, 0, 0, 0]


static func _flat(c: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.border_color = border
	s.set_border_width_all(2)
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var fs := 8 * scale()
	t.default_font = font()
	t.default_font_size = fs
	var bn := _nine("gui/sprites/widget/button", 3)
	var bh := _nine("gui/sprites/widget/button_highlighted", 3)
	var bd := _nine("gui/sprites/widget/button_disabled", 3)
	if bn == null:
		bn = _flat(Color(0.42, 0.42, 0.42), Color(0, 0, 0))
		bh = _flat(Color(0.5, 0.55, 0.75), Color(1, 1, 1))
		bd = _flat(Color(0.2, 0.2, 0.2), Color(0, 0, 0))
	for st in ["normal", "pressed"]:
		t.set_stylebox(st, "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("focus", "Button", bh)
	t.set_stylebox("disabled", "Button", bd)
	t.set_color("font_color", "Button", Color(1, 1, 1))
	# 1.20+ AbstractButton: white text (hovered too), 0xA0A0A0 when inactive
	for st in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(st, "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.63, 0.63, 0.63))
	t.set_color("font_shadow_color", "Button", Color(0.25, 0.25, 0.25) if Settings.get_v("text_shadow") else Color(0, 0, 0, 0))
	t.set_constant("shadow_offset_x", "Button", scale())
	t.set_constant("shadow_offset_y", "Button", scale())
	t.set_color("font_color", "Label", Color(1, 1, 1))
	t.set_color("font_shadow_color", "Label", Color(0.25, 0.25, 0.25) if Settings.get_v("text_shadow") else Color(0, 0, 0, 0))
	t.set_constant("shadow_offset_x", "Label", scale())
	t.set_constant("shadow_offset_y", "Label", scale())
	t.set_constant("line_spacing", "Label", line_spacing_9())   # multi-line text advances 9 GUI px like Java
	var tf := _nine("gui/sprites/widget/text_field", 1)
	var tfh := _nine("gui/sprites/widget/text_field_highlighted", 1)
	t.set_stylebox("normal", "LineEdit", tf if tf != null else _flat(Color(0, 0, 0), Color(0.63, 0.63, 0.63)))
	t.set_stylebox("focus", "LineEdit", tfh if tfh != null else _flat(Color(0, 0, 0), Color(1, 1, 1)))
	var sl := _nine("gui/sprites/widget/slider", 3)
	if sl != null:
		t.set_stylebox("slider", "HSlider", sl)
	var sh := sprite("gui/sprites/widget/slider_handle")
	if sh != null:
		t.set_icon("grabber", "HSlider", sh)
		t.set_icon("grabber_highlight", "HSlider", sprite("gui/sprites/widget/slider_handle_highlighted"))
	var tip := tooltip_style()
	if tip != null:
		t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", Color(1, 1, 1))
	t.set_color("font_shadow_color", "TooltipLabel", Color(0.25, 0.25, 0.25) if Settings.get_v("text_shadow") else Color(0, 0, 0, 0))
	t.set_constant("shadow_offset_x", "TooltipLabel", scale())
	t.set_constant("shadow_offset_y", "TooltipLabel", scale())
	var panel := _flat(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0))
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_meta("uikit", true)   # replaced on GUI scale changes (apply_scale)
	_theme = t
	return t


## Java TooltipRenderUtil: gui/sprites/tooltip/background (nine-slice 9) + frame (nine-slice 10, stretched) drawn
## 12 GUI px outside the text box; composited into one 100 x 100 nine-slice (border 10), pre-scaled per GUI scale,
## content inset 12 px.
static var _tips: Dictionary = {}


static func tooltip_style(s: int = 0) -> StyleBoxTexture:
	if s <= 0:
		s = scale()
	if _tips.has(s):
		return _tips[s]
	var bg := Res.load_image("gui/sprites/tooltip/background") if Res.mode == "vanilla" else null
	var fr := Res.load_image("gui/sprites/tooltip/frame") if Res.mode == "vanilla" else null
	if bg == null:
		return null
	var im := bg.duplicate()
	im.convert(Image.FORMAT_RGBA8)
	if fr != null and fr.get_size() == im.get_size():
		var f2 := fr.duplicate()
		f2.convert(Image.FORMAT_RGBA8)
		im.blend_rect(f2, Rect2i(Vector2i.ZERO, f2.get_size()), Vector2i.ZERO)
	if s > 1:
		im.resize(im.get_width() * s, im.get_height() * s, Image.INTERPOLATE_NEAREST)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(im)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_texture_margin(side, 10 * s)
		sb.set_content_margin(side, 12 * s)
	_tips[s] = sb
	return sb


## Java tooltip rendering in GUI units on a canvas already scaled by the GUI scale: lines = [[text, Color], ...];
## DefaultTooltipPositioner (mouse + (12, -12), flipped left / clamped at the edges); box w = widest line, h = 10
## per line - 2, +2 after the first line; sprites drawn 12 px around the box; text with shadow.
static func draw_tooltip(ci: CanvasItem, mouse: Vector2, lines: Array, gui_size: Vector2) -> void:
	if lines.is_empty():
		return
	var f := font()
	var w := 0.0
	for l in lines:
		w = maxf(w, f.get_string_size(str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
	var h := lines.size() * 10.0 - 2.0 + (2.0 if lines.size() > 1 else 0.0)
	var x := mouse.x + 12.0
	var y := mouse.y - 12.0
	if x + w > gui_size.x:
		x = maxf(mouse.x - 24.0 - w, 4.0)
	if y + h + 3.0 > gui_size.y:
		y = gui_size.y - h - 3.0
	y = maxf(y, 4.0)
	var sb := tooltip_style(1)
	if sb != null:
		ci.draw_style_box(sb, Rect2(x - 12.0, y - 12.0, w + 24.0, h + 24.0))
	else:
		ci.draw_rect(Rect2(x - 3, y - 3, w + 6, h + 6), Color8(16, 0, 16, 240))
	var ty := y
	for i in lines.size():
		var col: Color = lines[i][1]
		if Settings.get_v("text_shadow"):
			ci.draw_string(f, Vector2(x + 1, ty + 8), str(lines[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, col.a))
		ci.draw_string(f, Vector2(x, ty + 7), str(lines[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
		ty += 12.0 if i == 0 else 10.0


## Line spacing that makes multi-line Labels / TextEdits advance exactly 9 GUI px per line like Java's font
## (Font.get_height includes the taller system fallback font kept for non-ASCII glyphs).
static func line_spacing_9() -> int:
	var s := scale()
	return int(9 * s - font().get_height(8 * s))


## Tooltip body: Java splits widget tooltips at 170 GUI px.
static func tooltip_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	var w := font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	l.add_theme_constant_override("line_spacing", line_spacing_9() + scale())   # Java tooltip lines: 10 px
	if w > 170.0 or text.contains("\n"):
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = minf(w, 170.0) * scale()
	return l


## Never leave an empty screen when a screen's return callback is gone (e.g. a lambda owned by a freed screen):
## the title outside a world, the Game Menu in one.
static func return_fallback(from: Node) -> void:
	var app = from.get_tree().current_scene if from.is_inside_tree() else null
	if app == null or not app.has_method("show_title"):
		return
	var w = app.get("world")
	if w != null and is_instance_valid(w) and w.has_method("open_pause_menu"):
		w.open_pause_menu()
	else:
		app.show_title()


static func reset_theme() -> void:
	_theme = null
	_nines.clear()
	_tips.clear()


static func button(text: String, cb: Callable, width: int = 200) -> Button:
	var b := McButton.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 20) * scale()
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func():
		Audio.play_ui("ui.button.click")
		cb.call())
	return b


static func label(text: String, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	return l


## Java Screen.renderBackground: no level -> the app's panorama, blurred (Menu Background Blurriness), under
## gui/menu_background; in a level -> the blurred world under gui/inworld_menu_background. Both tile at 32 x 32
## GUI pixels. `_dim` is kept for old callers; the level state decides.
static func background(root: Control, _dim: bool = true) -> void:
	var iw := in_world(root)
	_blur(root)
	var tex := sprite("gui/inworld_menu_background" if iw else "gui/menu_background") if Res.mode == "vanilla" else null
	if tex != null:
		root.add_child(TileRect.make(tex, 32))
	else:
		var cr := ColorRect.new()
		cr.color = Color(0, 0, 0, 0.45)
		cr.set_anchors_preset(Control.PRESET_FULL_RECT)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(cr)


## Pause / in-world screens (kept name).
static func inworld_background(root: Control) -> void:
	background(root)


static func in_world(n: Node) -> bool:
	var tree := n.get_tree() if n.is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	var app = tree.current_scene if tree != null else null
	if app == null:
		return false
	var w = app.get("world")
	return w != null and is_instance_valid(w)


static func _blur(root: Control) -> void:
	var r := float(Settings.get_v("menu_blur"))
	if r <= 0.0:
		return
	var blur := ColorRect.new()
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/menu_blur.gdshader")
	m.set_shader_parameter("radius", r)
	blur.material = m
	root.add_child(blur)


## Full-rect control tiling a texture so `gui_px` texels... one tile spans `gui_px` GUI pixels (Java blit with
## texture size 32 x 32 over a 16 x 16 image: each texel is 2 GUI pixels).
class TileRect extends Control:
	var tex: Texture2D
	var gui_px := 32
	var region := Rect2()   # optional sub-rectangle of the parent to fill; empty = full rect

	static func make(t: Texture2D, px: int) -> TileRect:
		var r := TileRect.new()
		r.tex = t
		r.gui_px = px
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.resized.connect(r.queue_redraw)
		return r

	func _draw() -> void:
		if tex == null:
			return
		var k := float(UiKit.scale()) * float(gui_px) / float(tex.get_width())
		var rr := region if region.size != Vector2.ZERO else Rect2(Vector2.ZERO, size)
		draw_set_transform(rr.position, 0.0, Vector2(k, k))
		draw_texture_rect(tex, Rect2(Vector2.ZERO, rr.size / k), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Vertical centred column container helper.
static func column(root: Control, sep: int = 4) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep * scale())
	cc.add_child(v)
	return v
