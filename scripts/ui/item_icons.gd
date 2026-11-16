## ItemIcons — GUI icons for items: flat sprites from item models (layer0/layer1 of the user's textures),
## isometric block icons software-rasterised from baked block quads using the Java GUI transform
## (rotation x=30°, y=225°, scale 0.625) with face shading. Cached per item; main thread only.
## Contract: icon(item) -> Texture2D; average_color(state) -> Color.
class_name ItemIcons

const SIZE := 32
static var _cache: Dictionary = {}
static var _colors: Dictionary = {}


## Stack-aware icon: dyed leather (Java item tint "minecraft:dye" on layer0, overlay layer untinted).
static var _dyed: Dictionary = {}


static func icon_for(s: ItemStack) -> Texture2D:
	if s == null or s.is_empty():
		return null
	var dc = s.components.get("minecraft:dyed_color")
	if dc == null and s.name().begins_with("leather_") and s.name() != "leather":
		dc = 0xA06540   # Java item tint minecraft:dye default
	if dc == null or Res.mode != "vanilla":
		return icon(s.item)
	var key := "%d:%d" % [s.item, int(dc)]
	if _dyed.has(key):
		return _dyed[key]
	var tex: Texture2D = null
	var m := Res.baker.resolve(Res.items.model_ref[s.item]) if Res.items.model_ref[s.item] != "" else {}
	var tx: Dictionary = m.get("textures", {})
	if tx.has("layer0"):
		var base := Res.load_image(Res.baker.resolve_tex(tx, "#layer0"))
		if base != null:
			base.convert(Image.FORMAT_RGBA8)
			var c := Color8((int(dc) >> 16) & 255, (int(dc) >> 8) & 255, int(dc) & 255)
			for y in base.get_height():
				for x in base.get_width():
					var px := base.get_pixel(x, y)
					base.set_pixel(x, y, Color(px.r * c.r, px.g * c.g, px.b * c.b, px.a))
			if tx.has("layer1"):
				var ov := Res.load_image(Res.baker.resolve_tex(tx, "#layer1"))
				if ov != null:
					ov.convert(Image.FORMAT_RGBA8)
					base.blend_rect(ov, Rect2i(Vector2i.ZERO, ov.get_size()), Vector2i.ZERO)
			base.resize(SIZE, SIZE, Image.INTERPOLATE_NEAREST)
			tex = ImageTexture.create_from_image(base)
	if tex == null:
		tex = icon(s.item)
	_dyed[key] = tex
	return tex


static func icon(item: int) -> Texture2D:
	if _cache.has(item):
		return _cache[item]
	var sp := _special(item)
	if sp != null:
		_cache[item] = sp
		return sp
	var img := _make(item)
	var t: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	_cache[item] = t
	return t


## Items Java draws with special (block-entity) renderers: chests, shulker boxes, heads, banners, pots, conduit.
## Rendered once through an orthographic SubViewport with the base item model's display.gui transform.
static func _special(item: int) -> Texture2D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or DisplayServer.get_name() == "headless":
		return null
	var holder := BERender.item_node(item, "gui")
	if holder == null:
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE * 2, SIZE * 2)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.position = Vector3(0, 0, 4)
	cam.near = 0.05
	cam.far = 10.0
	vp.add_child(cam)
	vp.add_child(holder)
	BERender.set_light(holder, Vector2(0.0, 1.0), true)
	tree.root.add_child.call_deferred(vp)
	return vp.get_texture()


const DISPLAY_DEFAULTS := {
	"gui": {"rotation": [30, 225, 0], "translation": [0, 0, 0], "scale": [0.625, 0.625, 0.625]},
	"ground": {"rotation": [0, 0, 0], "translation": [0, 3, 0], "scale": [0.25, 0.25, 0.25]},
	"firstperson_righthand": {"rotation": [0, 45, 0], "translation": [0, 0, 0], "scale": [0.4, 0.4, 0.4]},
}


## display.<context> of an item's model (26.x items/<name>.json -> base/model ref -> model parents).
static func display(item_name: String, context: String) -> Dictionary:
	var j = Res.read_json("assets/minecraft/items/%s.json" % item_name)
	return model_display(_base_ref(j.get("model", {}) if j is Dictionary else {}), context)


## display.<context> walking a model's parents.
static func model_display(ref: String, context: String) -> Dictionary:
	for guard in 8:
		if ref == "":
			break
		var mj = Res.read_json("assets/minecraft/models/%s.json" % ref.trim_prefix("minecraft:"))
		if not (mj is Dictionary):
			break
		var disp = mj.get("display", {})
		if disp is Dictionary and disp.get(context) is Dictionary:
			return disp[context]
		ref = str(mj.get("parent", ""))
	return DISPLAY_DEFAULTS.get(context, {})

static func _base_ref(m) -> String:
	if not (m is Dictionary):
		return ""
	if m.get("base") is String:
		return m["base"]
	if m.get("model") is String:
		return m["model"]
	for k in ["fallback", "on_false", "model"]:
		var r := _base_ref(m.get(k))
		if r != "":
			return r
	for c in m.get("cases", []):
		var r2 := _base_ref((c as Dictionary).get("model"))
		if r2 != "":
			return r2
	return ""


## Flat item layers (layer0..2 of a generated model) composited at their native resolution (the GUI icon is
## resized from this; held / dropped items extrude it). Cached per model.
static var _flat: Dictionary = {}
static var _tint_cache: Dictionary = {}


## 26.3 items/<name>.json tint sources, one colour per tintindex (layer0 = 0, layer1 = 1): constant, grass (colormap
## at the given temperature / downfall), dye / potion / firework / map colour / team defaults. Flat icons multiplied
## their layers by none of these (short grass, ferns, vines, lily pads, potions came out grey).
static func layer_tints(item_name: String) -> Array:
	if _tint_cache.has(item_name):
		return _tint_cache[item_name]
	var out: Array = []
	if Res.mode == "vanilla":
		var j = Res.read_json("assets/minecraft/items/%s.json" % item_name)
		for t in _find_tints(j.get("model") if j is Dictionary else null):
			out.append(_tint_color(t))
	_tint_cache[item_name] = out
	return out


static func _find_tints(m) -> Array:
	if not (m is Dictionary):
		return []
	if m.get("tints") is Array:
		return m["tints"]
	for k in ["fallback", "on_false", "on_true", "model"]:
		var r := _find_tints(m.get(k))
		if not r.is_empty():
			return r
	for c in m.get("cases", []):
		var r2 := _find_tints((c as Dictionary).get("model") if c is Dictionary else null)
		if not r2.is_empty():
			return r2
	return []


static func _argb(v: int) -> Color:
	return Color8((v >> 16) & 255, (v >> 8) & 255, v & 255)


static func _tint_color(t) -> Color:
	if not (t is Dictionary):
		return Color(1, 1, 1)
	match str(t.get("type", "")).trim_prefix("minecraft:"):
		"constant":
			return _argb(int(t.get("value", -1)))
		"grass":
			return Res.colormap(Res.grass_colormap, float(t.get("temperature", 0.5)), float(t.get("downfall", 1.0)), Color8(0x91, 0xBD, 0x59))
		"dye", "potion", "firework", "map_color", "team":
			return _argb(int(t.get("default", -1)))
	return Color(1, 1, 1)


static func _tint_layer(im: Image, c: Color) -> void:
	if c == Color(1, 1, 1):
		return
	for y in im.get_height():
		for x in im.get_width():
			var px := im.get_pixel(x, y)
			im.set_pixel(x, y, Color(px.r * c.r, px.g * c.g, px.b * c.b, px.a))


static func flat_image(ref: String) -> Image:
	if _flat.has(ref):
		return _flat[ref]
	var out: Image = null
	if Res.mode == "vanilla" and ref != "":
		var tex: Dictionary = Res.baker.resolve(ref)["textures"]
		var tints := layer_tints(ref.get_file())
		for li in 3:
			var k := "layer%d" % li
			if not tex.has(k):
				continue
			var im := Res.load_image(Res.baker.resolve_tex(tex, "#" + k))
			if im == null:
				continue
			im.convert(Image.FORMAT_RGBA8)
			if im.get_height() > im.get_width():
				im = im.get_region(Rect2i(0, 0, im.get_width(), im.get_width()))   # animated strip: first frame
			if li < tints.size():
				_tint_layer(im, tints[li])
			if out == null:
				out = im
			else:
				if im.get_size() != out.get_size():
					im.resize(out.get_width(), out.get_height(), Image.INTERPOLATE_NEAREST)
				out.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i.ZERO)
	_flat[ref] = out
	return out


static var _ext: Dictionary = {}


## [ArrayMesh, Texture2D] of a flat item model extruded like Java's ItemModelGenerator (held / dropped items); cached.
static func extruded_model(ref: String) -> Array:
	if _ext.has(ref):
		return _ext[ref]
	var img := flat_image(ref)
	var r: Array = []
	if img != null:
		var tex := ImageTexture.create_from_image(img)
		r = [ViewModel.extruded(tex), tex]
	_ext[ref] = r
	return r


## display.<ctx> of an item in that context (its context model, then the parents; Java defaults when absent).
static func item_display(item: int, ctx: String) -> Dictionary:
	var ref := ItemRegistry.ctx_model(Res.items.names[item], ctx) if Res.mode == "vanilla" else ""
	if ref == "":
		ref = Res.items.model_ref[item]
	return model_display(ref, ctx)


static func _make(item: int) -> Image:
	if item <= 0:
		return null
	var model: String = Res.items.model_ref[item]
	var pb: int = Res.items.place_block[item]
	_parts = composite_parts(Res.items.names[item]) if Res.mode == "vanilla" else []
	if model.begins_with("block/") or (model == "" and pb > 0):
		if pb > 0:
			return _render_block(pb, model)
	if Res.mode == "vanilla" and model != "":
		var m := Res.baker.resolve(model)
		var tex: Dictionary = m["textures"]
		if m["elements"] is Array and pb > 0:
			return _render_block(pb, model)
		var out: Image = null
		var tints2 := layer_tints(Res.items.names[item])
		for li in 3:
			var k := "layer%d" % li
			if not tex.has(k):
				continue
			var im := Res.load_image(Res.baker.resolve_tex(tex, "#" + k))
			if im == null:
				continue
			im.convert(Image.FORMAT_RGBA8)
			if im.get_height() > im.get_width():
				im = im.get_region(Rect2i(0, 0, im.get_width(), im.get_width()))
			if li < tints2.size():
				_tint_layer(im, tints2[li])
			if out == null:
				out = im
			else:
				out.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i.ZERO)
		if out != null:
			out.resize(SIZE, SIZE, Image.INTERPOLATE_NEAREST)
			return out
	if pb > 0:
		return _render_block(pb, model)
	# original fallback: coloured square with initial
	var f := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := Color.from_hsv(float(hash(Res.items.names[item]) % 360) / 360.0, 0.5, 0.8)
	f.fill_rect(Rect2i(6, 6, 20, 20), c)
	return f


static func average_color(st: int) -> Color:
	if _colors.has(st):
		return _colors[st]
	var blocks := Res.blocks
	var layer := 0
	if blocks.st_flags[st] & BlockRegistry.F_CUBE:
		layer = blocks.st_faces[st * 6 + 1] & 0xFFF
	elif blocks.st_model[st] >= 0:
		layer = int((blocks.models[blocks.st_model[st]] as PackedFloat32Array)[20])
	var im: Image = Res.atlas.images[layer]
	var acc := Color(0, 0, 0)
	var n := 0
	for y in range(0, 16, 2):
		for x in range(0, 16, 2):
			var c := im.get_pixel(x, y)
			if c.a > 0.5:
				acc += c
				n += 1
	var res := acc / maxi(n, 1)
	if blocks.st_flags[st] & (BlockRegistry.F_TINT_GRASS | BlockRegistry.F_TINT_FOLIAGE):
		res *= Color(0.55, 0.8, 0.4)
	res.a = 1.0
	_colors[st] = res
	return res


## Item tint of a block item's tinted faces (Java item tint sources: grass at temperature 0.5 / downfall 1.0,
## default foliage, constant colours such as spruce / birch leaves).
static func block_tint(st: int) -> Color:
	var blocks := Res.blocks
	var fl := blocks.st_flags[st]
	if fl & BlockRegistry.F_TINT_GRASS:
		# items/grass_block.json: minecraft:grass at temperature 0.5, downfall 1.0 (the colormap there, #7cbd6b)
		return Res.colormap(Res.grass_colormap, 0.5, 1.0, Color8(0x7C, 0xBD, 0x6B))
	if fl & BlockRegistry.F_TINT_FOLIAGE:
		return Color8(0x48, 0xB5, 0x18)
	if fl & BlockRegistry.F_TINT_CONST:
		var v := blocks.st_tint_color[st]
		return Color8((v >> 16) & 255, (v >> 8) & 255, v & 255)
	return Color(1, 1, 1)


## Direction whose light a baked quad takes (26.x shade_direction_override); -1 for unshaded quads (full brightness).
static func _shade_dir(q: PackedFloat32Array, o: int) -> int:
	var s := q[o + 24]
	if s >= 2.0:
		return clampi(int(s) - 2, 0, 5)
	return int(q[o + 23]) if s > 0.5 else -1


## Java GUI 3D item lighting (Lighting ITEMS_3D: DIFFUSE_LIGHT_0 / 1 through scaling(1, -1, 1).rotateYXZ(1.0821041,
## 3.2375858, 0).rotateYXZ(-pi / 8, 3 pi / 4, 0); the y flips of the lights and the GUI pose cancel in the dot product)
## on the face normal after the display rotation: min(1, (max(0, L0.n) + max(0, L1.n)) * 0.6 + 0.4). The standard block
## display [30, 225, 0] gives top 1.0, left (east) 0.651, right (north) 0.400.
const GUI_L0 := Vector3(-0.933439, 0.262695, -0.2443)
const GUI_L1 := Vector3(-0.103571, 0.976607, 0.188446)
static func gui_light(rot: Basis, dir: int) -> float:
	if dir < 0:
		return 1.0
	var n: Vector3 = (rot * (DIR_VEC[clampi(dir, 0, 5)] as Vector3)).normalized()
	return minf(1.0, (maxf(0.0, GUI_L0.dot(n)) + maxf(0.0, GUI_L1.dot(n))) * 0.6 + 0.4)


## Java GUI item render types cull back faces: a quad is drawn only if its normal (the winding's, oriented by the face
## direction) faces the viewer after the display rotation (+z = towards the camera here).
const DIR_VEC := [Vector3(0, -1, 0), Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
static func _front(pts: Array, d: int, rot: Basis) -> bool:
	var n: Vector3 = ((pts[1] as Vector3) - (pts[0] as Vector3)).cross((pts[2] as Vector3) - (pts[0] as Vector3))
	if n.length_squared() < 1e-12:
		n = ((pts[2] as Vector3) - (pts[0] as Vector3)).cross((pts[3] as Vector3) - (pts[0] as Vector3))
	var dv: Vector3 = DIR_VEC[clampi(d, 0, 5)]
	if n.dot(dv) < 0.0:
		n = -n
	if absf(n.dot(dv)) < 1e-6 * n.length():
		n = dv
	return (rot * n).z > 1e-5


static func _quads_for(st: int, model: String = "") -> Array:
	var blocks := Res.blocks
	var out: Array = []
	var fl := blocks.st_flags[st]
	var tint := block_tint(st)
	if model != "" and Res.mode == "vanilla":
		# the item's own model (fence / wall inventory models, ...), as Java renders block items
		var bk: Dictionary = Res.baker.bake(model)
		var bq: PackedFloat32Array = bk.get("quads", PackedFloat32Array())
		if bk.get("ok", false) and bq.size() > 0:
			for qi in bq.size() / ModelBaker.QUAD_FLOATS:
				var o := qi * ModelBaker.QUAD_FLOATS
				var pts0: Array = []
				var uv0: Array = []
				for k in 4:
					pts0.append(Vector3(bq[o + k * 5], bq[o + k * 5 + 1], bq[o + k * 5 + 2]))
					uv0.append(Vector2(bq[o + k * 5 + 3], bq[o + k * 5 + 4]))
				out.append([pts0, uv0, int(bq[o + 20]), int(bq[o + 23]), tint if bq[o + 21] >= 0.0 else Color.WHITE, _shade_dir(bq, o)])
			return out
	if fl & BlockRegistry.F_CUBE:
		for d in 6:
			var f := blocks.st_faces[st * 6 + d]
			var pts := ModelBaker.face_corners(d, Vector3.ZERO, Vector3.ONE)
			var uv: Array = []
			for k in 4:
				uv.append(ModelBaker.canon_uv(k, (f >> 24) & 7))
			var ov := ((f >> 12) & 0xFFF) - 1
			var tinted := (f >> 28) & 1
			out.append([pts, uv, f & 0xFFF, d, tint if tinted and ov < 0 else Color.WHITE])
			if ov >= 0:
				out.append([pts, uv, ov, d, tint if tinted else Color.WHITE])
	elif blocks.st_model[st] >= 0:
		var q: PackedFloat32Array = blocks.models[blocks.st_model[st]]
		for qi in q.size() / ModelBaker.QUAD_FLOATS:
			var o := qi * ModelBaker.QUAD_FLOATS
			var pts2: Array = []
			var uv2: Array = []
			for k in 4:
				pts2.append(Vector3(q[o + k * 5], q[o + k * 5 + 1], q[o + k * 5 + 2]))
				uv2.append(Vector2(q[o + k * 5 + 3], q[o + k * 5 + 4]))
			out.append([pts2, uv2, int(q[o + 20]), int(q[o + 23]), tint if q[o + 21] >= 0.0 else Color.WHITE, _shade_dir(q, o)])
	elif fl & BlockRegistry.F_FLUID:
		for d in 6:
			var pts3 := ModelBaker.face_corners(d, Vector3.ZERO, Vector3.ONE)
			out.append([pts3, [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)], blocks.water_layer if not (fl & BlockRegistry.F_LAVA) else blocks.lava_layer, d, Color8(0x3F, 0x76, 0xE4) if not (fl & BlockRegistry.F_LAVA) else Color.WHITE])
	return out


## Java GUI item rendering of a block model: the model's display.gui transform (block default rotation 30 / 225 / 0,
## scale 0.625; stairs and fences 30 / 135; walls ...) applied as translation, rotationXYZ, scale about the block
## centre, 16 px per block unit scaled to SIZE.
const SIZE_HI := 64   # native rasteriser: block icons at screen resolution for GUI scale 4
static var _tex_bytes: Dictionary = {}   # atlas layer -> [PackedByteArray RGBA8, w, h]
static var _native_icons := -1


## 26.x composite item models (beds: head + foot translated by (0, 0, 1)): [[model ref, translation], ...], [] when the
## item is not a composite of block models.
static var _parts: Array = []
static func composite_parts(item_name: String) -> Array:
	var j = Res.read_json("assets/minecraft/items/%s.json" % item_name)
	if not (j is Dictionary) or not (j.get("model") is Dictionary):
		return []
	var m: Dictionary = j["model"]
	if str(m.get("type", "")).trim_prefix("minecraft:") != "composite":
		return []
	var out: Array = []
	for sm in m.get("models", []):
		if not (sm is Dictionary) or str(sm.get("type", "")).trim_prefix("minecraft:") != "model":
			continue
		var tr = (sm.get("transformation", {}) as Dictionary).get("translation", [0, 0, 0]) if sm.get("transformation") is Dictionary else [0, 0, 0]
		out.append([ModelBaker.norm_id(str(sm.get("model", ""))), Vector3(float(tr[0]), float(tr[1]), float(tr[2]))])
	return out


## The quads of the item: every part of a composite (offset) or the single model.
static func _item_quads(st: int, model: String) -> Array:
	if _parts.is_empty():
		return _quads_for(st, model)
	var out: Array = []
	for part in _parts:
		for q in _quads_for(st, str(part[0])):
			var moved: Array = []
			for pt in q[0]:
				moved.append((pt as Vector3) + (part[1] as Vector3))
			var q2: Array = q.duplicate()
			q2[0] = moved
			out.append(q2)
	return out


static func _render_block(st: int, model: String = "") -> Image:
	if _native_icons < 0:
		_native_icons = 1 if Native.inst != null and Native.inst.has_method("icon_raster") else 0
	if _native_icons == 1:
		return _render_block_native(st, model)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var zbuf := PackedFloat32Array()
	zbuf.resize(SIZE * SIZE)
	zbuf.fill(-INF)
	var gd := model_display(model, "gui") if model != "" and Res.mode == "vanilla" else DISPLAY_DEFAULTS["gui"]
	var gr: Array = gd.get("rotation", [30, 225, 0])
	var gt: Array = gd.get("translation", [0, 0, 0])
	var gs: Array = gd.get("scale", [0.625, 0.625, 0.625])
	var rot := Basis(Vector3.RIGHT, deg_to_rad(float(gr[0]))) * Basis(Vector3.UP, deg_to_rad(float(gr[1]))) * Basis(Vector3.BACK, deg_to_rad(float(gr[2])))
	rot = rot * Basis.from_scale(Vector3(float(gs[0]), float(gs[1]), float(gs[2])))
	var toff := Vector3(float(gt[0]), float(gt[1]), float(gt[2])) / 16.0
	var scale := float(SIZE)
	var lrot := Basis(Vector3.RIGHT, deg_to_rad(float(gr[0]))) * Basis(Vector3.UP, deg_to_rad(float(gr[1]))) * Basis(Vector3.BACK, deg_to_rad(float(gr[2])))
	var is_flat := (Res.blocks.st_flags[st] & BlockRegistry.F_MODEL) != 0 and Res.blocks.st_cull[st] == 0 and Res.blocks.st_shape[st] == 0
	var tl := (Res.blocks.st_flags[st] & BlockRegistry.F_TRANSLUCENT) != 0
	for q in _item_quads(st, model):
		var pts: Array = q[0]
		var uvs: Array = q[1]
		var layer: int = q[2]
		var li := clampi(layer, 0, Res.atlas.images.size() - 1)
		var im: Image = Res.atlas.hires.get(li, Res.atlas.images[li])   # native resolution (straw bed 64 px)
		var tint: Color = q[4]
		if not _front(q[0], int(q[3]), rot):
			continue
		var sh := gui_light(lrot, int(q[5]) if q.size() > 5 else int(q[3]))
		var sp: Array = []
		for p in pts:
			var v: Vector3 = (p as Vector3) - Vector3(0.5, 0.5, 0.5)
			if is_flat:
				v = Vector3(v.x, v.y, v.z)
			var r: Vector3 = rot * v + toff
			sp.append(Vector3(SIZE / 2.0 + r.x * scale, SIZE / 2.0 - r.y * scale, r.z))
		for tri in [[0, 1, 2], [0, 2, 3]]:
			_raster(img, zbuf, sp[tri[0]], sp[tri[1]], sp[tri[2]], uvs[tri[0]], uvs[tri[1]], uvs[tri[2]], im, tint * sh, tl)
	return img


## _render_block through RecraftNative.icon_raster at SIZE_HI px (same projection, shading and raster rules).
static func _render_block_native(st: int, model: String) -> Image:
	var sz := SIZE_HI
	var gd := model_display(model, "gui") if model != "" and Res.mode == "vanilla" else DISPLAY_DEFAULTS["gui"]
	var gr: Array = gd.get("rotation", [30, 225, 0])
	var gt: Array = gd.get("translation", [0, 0, 0])
	var gs: Array = gd.get("scale", [0.625, 0.625, 0.625])
	var rot := Basis(Vector3.RIGHT, deg_to_rad(float(gr[0]))) * Basis(Vector3.UP, deg_to_rad(float(gr[1]))) * Basis(Vector3.BACK, deg_to_rad(float(gr[2])))
	rot = rot * Basis.from_scale(Vector3(float(gs[0]), float(gs[1]), float(gs[2])))
	var toff := Vector3(float(gt[0]), float(gt[1]), float(gt[2])) / 16.0
	var lrot := Basis(Vector3.RIGHT, deg_to_rad(float(gr[0]))) * Basis(Vector3.UP, deg_to_rad(float(gr[1]))) * Basis(Vector3.BACK, deg_to_rad(float(gr[2])))
	var qa := PackedFloat32Array()
	var texs: Array = []
	var tsz := PackedInt32Array()
	var tix := {}
	# translucent block items (stained glass, ice, slime, honey) blend: texture index + 0.5 (see native/src/icons.cpp)
	var tl := 0.5 if (Res.blocks.st_flags[st] & BlockRegistry.F_TRANSLUCENT) != 0 else 0.0
	for q in _item_quads(st, model):
		if not _front(q[0], int(q[3]), rot):
			continue
		var li := clampi(int(q[2]), 0, Res.atlas.images.size() - 1)
		if not tix.has(li):
			var tb = _tex_bytes.get(li)
			if tb == null:
				var im: Image = Res.atlas.hires.get(li, Res.atlas.images[li])
				if im.get_format() != Image.FORMAT_RGBA8 or im.is_compressed():
					im = im.duplicate()
					if im.is_compressed():
						im.decompress()
					im.convert(Image.FORMAT_RGBA8)
				tb = [im.get_data(), im.get_width(), im.get_height()]
				_tex_bytes[li] = tb
			tix[li] = texs.size()
			texs.append(tb[0])
			tsz.append_array([int(tb[1]), int(tb[2])])
		var pts: Array = q[0]
		var uvs: Array = q[1]
		for k in 4:
			var r: Vector3 = rot * ((pts[k] as Vector3) - Vector3(0.5, 0.5, 0.5)) + toff
			var uv: Vector2 = uvs[k]
			qa.append_array([sz / 2.0 + r.x * sz, sz / 2.0 - r.y * sz, r.z, uv.x, uv.y])
		var mul: Color = (q[4] as Color) * gui_light(lrot, int(q[5]) if q.size() > 5 else int(q[3]))
		qa.append_array([float(tix[li]) + tl, mul.r, mul.g, mul.b])
	var res: Array = Native.inst.icon_raster(qa, texs, tsz, sz)
	return Image.create_from_data(sz, sz, false, Image.FORMAT_RGBA8, res[0])


## tl: translucent block item (Java translucent item sheet: stained glass, ice, slime, honey) - texels blend over what is
## already drawn ("over" with straight alpha), others are written opaque (cutout: alpha < 0.1 discarded).
static func _raster(img: Image, zb: PackedFloat32Array, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, tex: Image, mul: Color, tl := false) -> void:
	var minx := clampi(int(floor(minf(a.x, minf(b.x, c.x)))), 0, SIZE - 1)
	var maxx := clampi(int(ceil(maxf(a.x, maxf(b.x, c.x)))), 0, SIZE - 1)
	var miny := clampi(int(floor(minf(a.y, minf(b.y, c.y)))), 0, SIZE - 1)
	var maxy := clampi(int(ceil(maxf(a.y, maxf(b.y, c.y)))), 0, SIZE - 1)
	var area := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if absf(area) < 1e-6:
		return
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var px := x + 0.5
			var py := y + 0.5
			var w0 := ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / area
			var w1 := ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / area
			var w2 := 1.0 - w0 - w1
			if w0 < -0.001 or w1 < -0.001 or w2 < -0.001:
				continue
			var z := a.z * w0 + b.z * w1 + c.z * w2
			if z < zb[y * SIZE + x]:
				continue
			var uv := ua * w0 + ub * w1 + uc * w2
			var tw := tex.get_width()
			var th := tex.get_height()
			var tx := clampi(int(fposmod(uv.x, 1.0001) * tw), 0, tw - 1)
			var ty := clampi(int(fposmod(uv.y, 1.0001) * th), 0, th - 1)
			var col := tex.get_pixel(tx, ty)
			if col.a < 0.1:
				continue
			zb[y * SIZE + x] = z
			var o := col * mul
			o.a = 1.0
			if tl and col.a < 1.0:
				var dst := img.get_pixel(x, y)
				var oa := col.a + dst.a * (1.0 - col.a)
				var orgb := (Color(o.r, o.g, o.b) * col.a + Color(dst.r, dst.g, dst.b) * dst.a * (1.0 - col.a)) / maxf(oa, 1e-6)
				o = Color(orgb.r, orgb.g, orgb.b, oa)
			img.set_pixel(x, y, o)
