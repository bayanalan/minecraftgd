## Glint — the enchantment glint (minecraft.wiki "Enchantment glint"): which stacks shimmer (enchanted items, the
## enchantment_glint_override component, and the items that always glint: enchanted golden apples, Nether stars, End
## crystals, bottles o' enchanting, lodestone compasses, written books, enchanted books, debug sticks) and the GUI
## overlay drawn with the game's own glint texture (textures/misc/enchanted_glint_item) and core/glint shader math
## (shaders/glint_gui.gdshader). Glint Speed / Glint Strength come from the options (defaults 50 % / 75 %).
## The pattern follows each item's UV in the items atlas (wiki: "tied to the dimensions of the atlas"); the vanilla
## atlas layout isn't public, so each item gets a fixed pseudo-random 16 px cell of a 512 x 512 atlas.
## Contract: Glint.has_glint(stack); Glint.begin(ci) at the start of a CanvasItem's _draw, Glint.add(ci, tex, rect,
## stack) per drawn icon (the layer is a child of ci drawn just above it).
class_name Glint

const ALWAYS := ["enchanted_golden_apple", "nether_star", "end_crystal", "experience_bottle", "written_book",
	"enchanted_book", "debug_stick"]
const ATLAS_CELLS := 32   # 512 px / 16 px

static var _mat: ShaderMaterial
static var _tex: Texture2D
static var _armor_tex: Texture2D
static var _shader3d: Shader
static var _mats3d: Array = []   # WeakRefs of 3D glint materials (options updates)


static func has_glint(st: ItemStack) -> bool:
	if st == null or st.is_empty():
		return false
	var c := st.components
	if c.has("minecraft:enchantment_glint_override"):
		return bool(c["minecraft:enchantment_glint_override"])
	var en: Variant = c.get("minecraft:enchantments", null)
	if en is Dictionary and not (en as Dictionary).is_empty():
		return true
	var nm := st.name()
	if nm == "compass" and c.has("minecraft:lodestone_tracker"):
		return true
	return ALWAYS.has(nm)


static func texture() -> Texture2D:
	if _tex == null:
		var im: Image = Res.load_image("misc/enchanted_glint_item")
		if im == null:
			im = Image.create(1, 1, false, Image.FORMAT_RGBA8)
			im.fill(Color(0.5, 0.25, 0.8, 1.0))
		_tex = ImageTexture.create_from_image(im)
	return _tex


static func gui_material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/glint_gui.gdshader")
		_mat.set_shader_parameter("glint_tex", texture())
		apply_options()
		Settings.changed.connect(_on_setting)
	return _mat


## Glint Speed / Glint Strength options (Settings "glint_speed" / "glint_strength").
static func apply_options() -> void:
	if _mat == null:
		return
	var sp := float(Settings.get_v("glint_speed"))
	var al := float(Settings.get_v("glint_strength"))
	_mat.set_shader_parameter("glint_speed", sp)
	_mat.set_shader_parameter("glint_alpha", al)
	var keep: Array = []
	for w in _mats3d:
		var m: ShaderMaterial = (w as WeakRef).get_ref()
		if m != null:
			m.set_shader_parameter("glint_speed", sp)
			m.set_shader_parameter("glint_alpha", al)
			keep.append(w)
	_mats3d = keep


static func _on_setting(key: String) -> void:
	if key == "glint_speed" or key == "glint_strength":
		apply_options()


## The item's stand-in atlas cell as the vertex colour the shader reads (rg = UV origin, b = UV size).
static func sprite_color(st: ItemStack) -> Color:
	var h := hash(st.name())
	var cell := absi(h) % (ATLAS_CELLS * ATLAS_CELLS)
	var inv := 1.0 / ATLAS_CELLS
	return Color(float(cell % ATLAS_CELLS) * inv, float(cell / ATLAS_CELLS) * inv, inv, 1.0)


## Next-pass material for a 3D item mesh textured with item_tex (UV = the item sprite 0..1), or for worn armour
## (armour: the armour texture's UVs, enchanted_glint_armor at scale 0.16).
static func material_3d(item_tex: Texture2D, st: ItemStack, armour := false) -> ShaderMaterial:
	if _shader3d == null:
		_shader3d = load("res://shaders/glint_3d.gdshader")
		gui_material()
	var m := ShaderMaterial.new()
	m.shader = _shader3d
	m.render_priority = 1
	if armour:
		if _armor_tex == null:
			var im: Image = Res.load_image("misc/enchanted_glint_armor")
			_armor_tex = ImageTexture.create_from_image(im) if im != null else texture()
		m.set_shader_parameter("glint_tex", _armor_tex)
		m.set_shader_parameter("glint_scale", 0.16)
		m.set_shader_parameter("sprite", Vector3(0, 0, 1))
	else:
		m.set_shader_parameter("glint_tex", texture())
		var c := sprite_color(st)
		m.set_shader_parameter("sprite", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("item_tex", item_tex)
	m.set_shader_parameter("use_mask", item_tex != null)
	m.set_shader_parameter("glint_speed", float(Settings.get_v("glint_speed")))
	m.set_shader_parameter("glint_alpha", float(Settings.get_v("glint_strength")))
	_mats3d.append(weakref(m))
	if _mats3d.size() > 256:
		apply_options()   # (drops freed entries)
	return m


static func _layer(ci: CanvasItem) -> Layer:
	var l: Layer = ci.get_meta("glint_layer") if ci.has_meta("glint_layer") else null
	if l == null or not is_instance_valid(l):
		l = Layer.new()
		ci.add_child(l)
		ci.set_meta("glint_layer", l)
	return l


## Start of ci's _draw: forget last frame's icons (and follow ci's draw scale).
static func begin(ci: CanvasItem, draw_scale: float = 1.0) -> void:
	if not ci.has_meta("glint_layer"):
		return
	var l := _layer(ci)
	l.items.clear()
	l.scale = Vector2(draw_scale, draw_scale)
	l.queue_redraw()


static func add(ci: CanvasItem, tex: Texture2D, rect: Rect2, st: ItemStack, draw_scale: float = 1.0) -> void:
	if tex == null:
		return
	var l := _layer(ci)
	l.scale = Vector2(draw_scale, draw_scale)
	l.items.append([tex, rect, sprite_color(st)])
	l.queue_redraw()


class Layer extends Node2D:
	var items: Array = []

	func _init() -> void:
		material = Glint.gui_material()   # (a child draws right after its parent: above the icons, below later siblings)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		for it in items:
			draw_texture_rect(it[0], it[1], false, it[2])
