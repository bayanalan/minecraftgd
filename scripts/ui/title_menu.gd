## TitleMenu — Java 26.3 TitleScreen layout in GUI pixels (UI spec 5.2): unblurred PanoramaBg (owned by the app); logo
## gui/title/minecraft.png (256 x 44 at y 30) + edition.png (128 x 14 at y 67) from the user's assets; yellow
## splash (texts/splashes.txt) rotated -20 deg at (C + 123, 69), pulsing; buttons from y = G_h / 4 + 48:
## Singleplayer, Multiplayer, Realms (no service: disabled with the reason), then Options... | Quit Game (98 each,
## 12 px lower) with the language / accessibility icon buttons beside them. Bottom: version (left) and the "not an
## official product" notice (right) instead of Mojang's copyright line.
extends Control

var app
var _logo: TextureRect
var _edition: TextureRect
var _splash: Label
var _btns: Array = []   # [Control, x (GUI, from centre), row y offset, width]
var _info: Label
var _legal: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	# the project's own logo ("Minecraft GDScript Edition", res://logo.png) replaces the vanilla logo + edition strip
	var own_logo: Texture2D = load("res://logo.png") if ResourceLoader.exists("res://logo.png") else null
	var logo_tex: Texture2D = UiKit.sprite("gui/title/minecraft") if Res.mode == "vanilla" and own_logo == null else null
	if own_logo != null:
		_logo = TextureRect.new()
		_logo.texture = own_logo
		_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_logo.stretch_mode = TextureRect.STRETCH_SCALE
		_logo.set_meta("aspect", float(own_logo.get_height()) / float(own_logo.get_width()))
		add_child(_logo)
	elif logo_tex != null:
		var at := AtlasTexture.new()
		at.atlas = logo_tex
		# the 26.x logo is a 4x texture (1024 x 256): logo 256 x 44 GUI px in its top part
		var k := float(logo_tex.get_width()) / 256.0
		at.region = Rect2(0, 0, 256 * k, 44 * k)
		_logo = TextureRect.new()
		_logo.texture = at
		_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # the 4x texture must not set a 1024-px minimum size (logo drawn too big, off centre)
		_logo.stretch_mode = TextureRect.STRETCH_SCALE
		add_child(_logo)
		var ed_tex: Texture2D = UiKit.sprite("gui/title/edition")
		if ed_tex != null:
			var at2 := AtlasTexture.new()
			at2.atlas = ed_tex
			var k2 := float(ed_tex.get_width()) / 128.0
			at2.region = Rect2(0, 0, 128 * k2, 14 * k2)
			_edition = TextureRect.new()
			_edition.texture = at2
			_edition.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			_edition.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_edition.stretch_mode = TextureRect.STRETCH_SCALE
			add_child(_edition)
	else:
		var title := UiKit.label("RECRAFT")
		title.add_theme_font_size_override("font_size", 32 * UiKit.scale())
		_logo = null
		add_child(title)
		_btns.append([title, -100, -60, 200])
	_splash = UiKit.label(_pick_splash())
	_splash.add_theme_color_override("font_color", Color8(255, 255, 0))
	_splash.add_theme_color_override("font_shadow_color", Color8(63, 63, 0))
	add_child(_splash)
	_add(UiKit.button(Res.tr_key("menu.singleplayer", "Singleplayer"), func(): app.show_world_list()), -100, 0, 200)
	_add(UiKit.button(Res.tr_key("menu.multiplayer", "Multiplayer"), func(): _show_multiplayer()), -100, 24, 200)
	var realms := UiKit.button(Res.tr_key("menu.online", "Minecraft Realms"), func(): pass)
	realms.disabled = true
	realms.tooltip_text = "Realms is Mojang's online service; not available in Recraft"
	_add(realms, -100, 48, 200)
	_add(UiKit.button(Res.tr_key("menu.options", "Options..."), func(): app.show_options(Callable(app, "show_title")), 98), -100, 84, 98)
	_add(UiKit.button(Res.tr_key("menu.quit", "Quit Game"), func(): app.quit(), 98), 2, 84, 98)
	var lang_btn := _icon_button("gui/sprites/icon/language", func():
		var l = load("res://scripts/ui/language_screen.gd").new()
		l.on_close = Callable(app, "show_title")   # bound to the app: a lambda made here dies with this screen
		app._set_screen(l))
	lang_btn.tooltip_text = Res.tr_key("options.language", "Language...")
	_add(lang_btn, -124, 84, 20)
	var acc_btn := _icon_button("gui/sprites/icon/accessibility", func():
		var om = load("res://scripts/ui/options_menu.gd").new()
		var a: Control = om._accessibility()
		om.free()
		a.set("on_close", Callable(app, "show_title"))
		app._set_screen(a))
	acc_btn.tooltip_text = Res.tr_key("options.accessibility", "Accessibility Settings...")
	_add(acc_btn, 104, 84, 20)
	_info = UiKit.label("Recraft (Minecraft %s assets)" % Res.version if Res.mode == "vanilla" else "Recraft", HORIZONTAL_ALIGNMENT_LEFT)
	add_child(_info)
	_legal = UiKit.label(LEGAL_1 + " " + LEGAL_2, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_legal)
	_layout()
	resized.connect(_layout)


func _add(c: Control, x: int, y: int, w: int) -> void:
	add_child(c)
	_btns.append([c, x, y, w])


func _icon_button(sprite_path: String, cb: Callable) -> Button:
	var b := UiKit.button("", cb, 20)
	var ic := UiKit.sprite(sprite_path)
	if ic != null:
		b.icon = ic
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", 15 * UiKit.scale())
	return b


func _pick_splash() -> String:
	if Res.mode != "vanilla" or Res.jar == null:
		return ""
	var txt: String = Res.jar.read_text("assets/minecraft/texts/splashes.txt")
	var lines := Array(txt.split("\n", false))
	lines = lines.filter(func(l): return str(l).strip_edges() != "")
	if lines.is_empty():
		return ""
	var r := RandomNumberGenerator.new()
	r.randomize()
	return str(lines[r.randi_range(0, lines.size() - 1)]).strip_edges()


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	if _logo != null:
		if _logo.has_meta("aspect"):
			# own logo (MINECRAFT + GDScript Edition in one image): 300 GUI px wide so the word matches the vanilla logo's
			# size; height from its aspect ratio (447 x 111 -> 300 x 75), top at the vanilla y 30
			_logo.position = Vector2(c - OWN_LOGO_W / 2.0, 30) * s
			_logo.size = Vector2(OWN_LOGO_W, roundf(OWN_LOGO_W * float(_logo.get_meta("aspect")))) * s
		else:
			_logo.position = Vector2(c - 128, 30) * s
			_logo.size = Vector2(256, 44) * s
		if _edition != null:
			_edition.position = Vector2(c - 64, 30 + 44 - 7) * s
			_edition.size = Vector2(128, 14) * s
	var top := floorf(gh / 4.0 + 48.0)
	for e in _btns:
		var ctl: Control = e[0]
		ctl.position = Vector2(c + float(e[1]), top + float(e[2])) * s
		ctl.size = Vector2(float(e[3]), 20) * s
	_info.position = Vector2(2, gh - 10) * s
	_info.size = Vector2(gw / 2, 9) * s
	# Java: right-aligned at width - textWidth - 2; the full notice wraps to two lines when it would run into the
	# version text (large GUI scales) instead of running off the screen
	var f := UiKit.font()
	var full := LEGAL_1 + " " + LEGAL_2
	var tw := f.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var iw := f.get_string_size(_info.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var lines := 1
	if tw + iw + 8.0 <= gw:
		_legal.text = full
	else:
		_legal.text = LEGAL_1 + "\n" + LEGAL_2
		lines = 2
		tw = maxf(f.get_string_size(LEGAL_1, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, f.get_string_size(LEGAL_2, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
	_legal.position = Vector2(gw - tw - 2, gh - 10 * lines) * s
	_legal.size = Vector2(tw, 9 * lines) * s
	_splash.position = _splash_at(c) * s
	_splash.size = Vector2(0, 0)

const OWN_LOGO_W := 300.0
const LEGAL_1 := "Not an official Minecraft product."
const LEGAL_2 := "Not approved by or associated with Mojang or Microsoft."


## Splash anchor: vanilla (C + 123, 69) at the right end of the 256-px logo; with the project's wider logo the same spot
## relative to its right edge and the line between the word and the edition text.
func _splash_at(c: float) -> Vector2:
	if _logo != null and _logo.has_meta("aspect"):
		return Vector2(c + OWN_LOGO_W / 2.0 - 5.0, 30.0 + roundf(OWN_LOGO_W * float(_logo.get_meta("aspect")) * 0.6))
	return Vector2(c + 123, 69)


func _show_multiplayer() -> void:
	var m = load("res://scripts/ui/multiplayer_screen.gd").new()
	m.app = app
	app._set_screen(m)


func _process(_delta: float) -> void:
	if _splash != null:
		# Java: rotate -20 deg, scale (1.8 - |sin(t)| * 0.1) * 100 / (width + 32)
		var f := 1.8 - absf(sin(float(Time.get_ticks_msec() % 1000) / 1000.0 * TAU)) * 0.1
		var w := maxf(1.0, _splash.get_theme_font("font").get_string_size(_splash.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
		f = f * 100.0 / (w + 32.0)
		_splash.pivot_offset = _splash.size / 2.0
		_splash.rotation = deg_to_rad(-20.0)
		_splash.scale = Vector2(f, f)
		var s := float(UiKit.scale())
		_splash.position = _splash_at(floorf(size.x / s / 2.0)) * s - _splash.size / 2.0
