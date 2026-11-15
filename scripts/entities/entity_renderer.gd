## EntityRenderer — builds box-rig meshes (Java box-UV layout: top/bottom/sides from a texture offset),
## item/block drop meshes and shared materials. Parts are pivoted Node3D children so AI/animation can
## rotate limbs independently of the hitbox. Model units: 1/16 block, Y down (converted on build).
## Contract: build_rig(def, texture) -> Node3D (children "pivot_<part>"); block_item_mesh(state); item_sprite(item).
class_name EntityRenderer

static var _tex_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _part_mesh_cache: Dictionary = {}   # rig part geometry key -> ArrayMesh (shared)
static var entity_shader: Shader


static func texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var img := Res.load_image(path)
	var t: Texture2D = null
	if img != null:
		t = ImageTexture.create_from_image(img)
	_tex_cache[path] = t
	return t


## Several entity textures composited in order (Java render layers drawn over the base: villager type and profession
## overlays); cached per combination.
static func material_layers(paths: Array) -> ShaderMaterial:
	var key := "|".join(paths)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var out: Image = null
	for pth in paths:
		var im: Image = Res.load_image(str(pth)) if Res.mode == "vanilla" else null
		if im == null:
			continue
		im.convert(Image.FORMAT_RGBA8)
		if out == null:
			out = im
		elif im.get_size() == out.get_size():
			out.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i.ZERO)
	if entity_shader == null:
		entity_shader = load("res://shaders/entity.gdshader")
	var m := ShaderMaterial.new()
	m.shader = entity_shader
	m.set_shader_parameter("lit_normals", true)
	if out != null:
		m.set_shader_parameter("tex", ImageTexture.create_from_image(out))
		m.set_shader_parameter("has_tex", true)
	_mat_cache[key] = m
	return m


## Java VillagerType.byBiome
static func villager_type(biome_name: String) -> String:
	var b := biome_name.trim_prefix("minecraft:")
	if b in ["desert", "badlands", "eroded_badlands", "wooded_badlands"]:
		return "desert"
	if b in ["jungle", "sparse_jungle", "bamboo_jungle"]:
		return "jungle"
	if b in ["savanna", "savanna_plateau", "windswept_savanna"]:
		return "savanna"
	if b in ["snowy_plains", "ice_spikes", "snowy_taiga", "frozen_ocean", "deep_frozen_ocean", "frozen_river", "snowy_beach", "grove", "snowy_slopes", "frozen_peaks", "jagged_peaks"]:
		return "snow"
	if b in ["swamp", "mangrove_swamp"]:
		return "swamp"
	if b in ["taiga", "old_growth_pine_taiga", "old_growth_spruce_taiga", "windswept_hills", "windswept_gravelly_hills", "windswept_forest"]:
		return "taiga"
	return "plains"


static func material(path: String) -> ShaderMaterial:
	if _mat_cache.has(path):
		return _mat_cache[path]
	if entity_shader == null:
		entity_shader = load("res://shaders/entity.gdshader")
	var m := ShaderMaterial.new()
	m.shader = entity_shader
	m.set_shader_parameter("lit_normals", true)   # box_arrays meshes carry normals, no baked shade
	var t := texture(path)
	if t != null:
		m.set_shader_parameter("tex", t)
		m.set_shader_parameter("has_tex", true)
	_mat_cache[path] = m
	return m


## Box with Java box-UV. o = min corner (model px, Y down), s = size, uv = texture offset, ts = texture size.
## inflate: Java CubeDeformation (geometry grows on every side; UVs keep the base size).
static func box_arrays(o: Vector3, s: Vector3, uv: Vector2, ts: Vector2, st: SurfaceTool, inflate: float = 0.0, tint: Color = Color.WHITE, y_up: bool = false, mirror: bool = false) -> void:
	var x0 := o.x - inflate
	var y0 := o.y - inflate
	var z0 := o.z - inflate
	var x1 := o.x + s.x + inflate
	if mirror:
		# Java ModelPart.Cube mirror: min / max x swapped (every face keeps its UV rect, so the texture is mirrored),
		# polygons turned to face outward again (normal x flipped, vertex order reversed)
		var xt := x0
		x0 = x1
		x1 = xt
	var y1 := o.y + s.y + inflate
	var z1 := o.z + s.z + inflate
	var w := s.x
	var h := s.y
	var d := s.z
	var u := uv.x
	var v := uv.y
	# faces: [corners (model space, Y down), uv rect, normal]; corner i takes uv [(pos.x, pos.y), (end.x, pos.y),
	# (end.x, end.y), (pos.x, end.y)][i] - negative sizes run the rect backwards. Java ModelPart.Cube polygons exactly:
	# side faces have min x (north), max z (west), min z (east), max x (south) at their low u, the top (Java DOWN, min
	# y) has max z at low v, the bottom (Java UP) min z at low v (the faces were mirrored before: arrow heads at the
	# fletching end, every mob face flipped)
	var faces := [
		# top (model -Y = world up)
		[[Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1)], Rect2(u + d, v + d, w, -d), Vector3(0, 1, 0)],
		# bottom
		[[Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0)], Rect2(u + d + w, v, w, d), Vector3(0, -1, 0)],
		# north (-z) front
		[[Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0)], Rect2(u + d + w, v + d, -w, h), Vector3(0, 0, -1)],
		# south (+z) back
		[[Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)], Rect2(u + d + w + d + w, v + d, -w, h), Vector3(0, 0, 1)],
		# west (-x)
		[[Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0)], Rect2(u + d, v + d, -d, h), Vector3(-1, 0, 0)],
		# east (+x)
		[[Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1)], Rect2(u + d + w + d, v + d, -d, h), Vector3(1, 0, 0)],
	]
	for f in faces:
		var c: Array = f[0]
		var r: Rect2 = f[1]
		var uvs := [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)]
		# the face normal in our model space (Java's flipped on x and y; f[2] lists x in Java's sense): the entity shader
		# lights it like Java's entity shader (EntityRenderer.material sets lit_normals)
		var fn: Vector3 = f[2]
		var nrm := Vector3(fn.x if mirror else -fn.x, fn.y, fn.z)
		var pts: Array = []
		for p in c:
			pts.append(Vector3(-(p as Vector3).x, -(p as Vector3).y, (p as Vector3).z) / 16.0)
		for idx in ([0, 2, 1, 0, 3, 2] if mirror else [0, 1, 2, 0, 2, 3]):
			st.set_color(Color(tint.r, tint.g, tint.b))
			st.set_normal(nrm)
			st.set_uv(uvs[idx] / ts)
			st.add_vertex(pts[idx])


static func build_rig(def: Dictionary) -> Node3D:
	var root := Node3D.new()
	var ts_a: Array = def.get("tex_size", [64, 64])
	var ts := Vector2(ts_a[0], ts_a[1])
	var mat := material(str(def.get("tex", "")))
	var model := Node3D.new()
	model.name = "model"
	# model px: Y down with origin 24px above feet (Java renders at y offset 1.501)
	model.position = Vector3(0, float(def.get("model_y", 1.5)), 0) * float(def.get("scale", 1.0))
	model.scale = Vector3.ONE * float(def.get("scale", 1.0))
	root.add_child(model)
	_add_parts(model, def.get("parts", []), ts, mat)
	# extra texture layers on the same model (Java render layers with their own texture: breeze wind, ...)
	for layer in def.get("layers", []):
		var lts_a: Array = layer.get("tex_size", [64, 64])
		_add_parts(model, layer.get("parts", []), Vector2(lts_a[0], lts_a[1]), material(str(layer.get("tex", ""))))
	# Java part hierarchy: child pivots / rotations are relative to their parent part (child -> parent)
	var nest: Dictionary = (def.get("nest", {}) as Dictionary).duplicate()
	for layer2 in def.get("layers", []):
		nest.merge(layer2.get("nest", {}))
	for cn in nest:
		var ch := model.find_child(str(cn), true, false) as Node3D
		var pa := model.find_child(str(nest[cn]), true, false) as Node3D
		if ch != null and pa != null and ch.get_parent() != pa:
			ch.get_parent().remove_child(ch)
			pa.add_child(ch)
	# Java block-model render layers (mooshroom mushrooms, snow golem pumpkin): the pose-stack ops in Java model space
	# (blocks), the block model's [0, 1]^3 space after them; ours = S * J (our block meshes are centred in x / z)
	for bl in def.get("block_layers", []):
		var bst := Res.blocks.default_state(str(bl.get("state", ""))) if Res.blocks != null else -1
		if bst <= 0:
			continue
		var bmesh := block_item_mesh(bst)
		if bmesh == null:
			continue
		var j := Transform3D.IDENTITY
		for op in bl.get("ops", []):
			match str(op[0]):
				"t":
					j = j * Transform3D(Basis(), Vector3(float(op[1]), float(op[2]), float(op[3])))
				"ry":
					j = j * Transform3D(Basis(Vector3.UP, deg_to_rad(float(op[1]))), Vector3.ZERO)
				"s":
					j = j * Transform3D(Basis.from_scale(Vector3(float(op[1]), float(op[2]), float(op[3]))), Vector3.ZERO)
		var bmi := MeshInstance3D.new()
		bmi.mesh = bmesh
		bmi.transform = Transform3D(Basis.from_scale(Vector3(-1, -1, 1)), Vector3.ZERO) * j * Transform3D(Basis(), Vector3(0.5, 0.0, 0.5))
		var parent_name := str(bl.get("parent", ""))
		var host: Node3D = model.find_child(parent_name, true, false) as Node3D if parent_name != "" else model
		(host if host != null else model).add_child(bmi)
	for hn in def.get("hidden", []):
		var hnode := model.find_child(str(hn), true, false) as Node3D
		if hnode != null:
			hnode.visible = false
	return root


## Pivots for a part list. Java ModelPart pose: translate(pivot / 16), rotationZYX(zRot, yRot, xRot); our model space
## is Java's flipped on x and y (S = diag(-1, -1, 1)), so S R S = Rz(z) Ry(-y) Rx(-x) in ZYX order.
static func _add_parts(model: Node3D, parts: Array, ts: Vector2, mat: Material) -> void:
	for p in parts:
		var pivot := Node3D.new()
		pivot.name = str(p[0])
		pivot.rotation_order = EULER_ORDER_ZYX
		var pv: Array = p[1]
		pivot.position = Vector3(-float(pv[0]), -float(pv[1]), float(pv[2])) / 16.0
		if float(p[5]) != 0.0:
			pivot.rotation.x = deg_to_rad(-float(p[5]))
		if p.size() > 6 and float(p[6]) != 0.0:
			pivot.rotation.z = deg_to_rad(float(p[6]))
		if p.size() > 7 and float(p[7]) != 0.0:
			pivot.rotation.y = deg_to_rad(-float(p[7]))   # Java yRot (model flipped on x/y)
		# part meshes depend only on the box geometry and texture size: built once, shared by every instance
		var pk := str(ts) + str(p)
		var pm: ArrayMesh = _part_mesh_cache.get(pk)
		if pm == null:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var o: Array = p[2]
			var s: Array = p[3]
			var uv: Array = p[4]
			box_arrays(Vector3(o[0], o[1], o[2]), Vector3(s[0], s[1], s[2]), Vector2(uv[0], uv[1]), ts, st, float(p[8]) if p.size() > 8 else 0.0, Color.WHITE, false, p.size() > 10 and bool(p[10]))
			pm = st.commit()
			_part_mesh_cache[pk] = pm
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		pivot.add_child(mi)
		# extra boxes on the same pivot (Java PlayerModel second skin layers): [[name, origin, size, uv, inflate], ...]
		if p.size() > 9 and p[9] is Array:
			for ex in p[9]:
				var ek := str(ts) + str(ex)
				var em: ArrayMesh = _part_mesh_cache.get(ek)
				if em == null:
					var st2 := SurfaceTool.new()
					st2.begin(Mesh.PRIMITIVE_TRIANGLES)
					var eo: Array = ex[1]
					var es: Array = ex[2]
					var eu: Array = ex[3]
					box_arrays(Vector3(eo[0], eo[1], eo[2]), Vector3(es[0], es[1], es[2]), Vector2(eu[0], eu[1]), ts, st2, float(ex[4]), Color.WHITE, false, ex.size() > 5 and bool(ex[5]))
					em = st2.commit()
					_part_mesh_cache[ek] = em
				var emi := MeshInstance3D.new()
				emi.name = str(ex[0])
				emi.mesh = em
				emi.material_override = mat
				pivot.add_child(emi)
		model.add_child(pivot)


const HEAD_ATTACH := ["nose", "ear0", "ear1", "snout", "horn0", "horn1", "bill", "chin", "muzzle", "beak", "hat_rim"]


## Java mob models make the nose / ears / snout / horns / bill / beak (and a neck sharing the head pivot: horse,
## llama) children of the head part, so they turn with it. Our flat rigs list them as siblings: re-parent them under
## the head pivot keeping their rest transform (model-space pose unchanged until the head rotates).
static func group_head(root: Node3D) -> void:
	var model: Node3D = root.get_node_or_null("model")
	if model == null:
		return
	var head: Node3D = model.get_node_or_null("head")
	if head == null:
		return
	head.set_meta("r0", head.rotation)
	var inv := head.transform.affine_inverse()
	for c in model.get_children():
		var nm := str(c.name)
		if c == head or not c is Node3D:
			continue
		if HEAD_ATTACH.has(nm) or (nm == "neck" and (c as Node3D).position.is_equal_approx(head.position)):
			var t: Transform3D = inv * (c as Node3D).transform
			model.remove_child(c)
			head.add_child(c)
			(c as Node3D).transform = t


## Re-parents parts (child name -> parent name) keeping their rest pose: Java part hierarchies our flat rigs list as
## siblings (dragon wing -> wing tip -> tip membrane, jaw -> head ...).
static func group_children(root: Node3D, children: Dictionary) -> void:
	var model: Node3D = root.get_node_or_null("model")
	if model == null:
		return
	for cn in children:
		var c: Node3D = model.find_child(str(cn), true, false)
		var par: Node3D = model.find_child(str(children[cn]), true, false)
		if c == null or par == null or c == par:
			continue
		var t: Transform3D = par.global_transform.affine_inverse() * c.global_transform if c.is_inside_tree() else (_model_xf(model, par).affine_inverse() * _model_xf(model, c))
		c.get_parent().remove_child(c)
		par.add_child(c)
		c.transform = t


static func _model_xf(model: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D()
	var cur: Node = n
	while cur != null and cur != model:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Java PlayerModelPart toggles (Skin Customization): hides / shows the player rig's second-layer parts.
const SKIN_PARTS := {"hat": "skin_hat", "jacket": "skin_jacket", "left_sleeve": "skin_left_sleeve", "right_sleeve": "skin_right_sleeve",
	"left_pants_leg": "skin_left_pants_leg", "right_pants_leg": "skin_right_pants_leg"}


static func apply_skin_parts(rig: Node) -> void:
	if rig == null:
		return
	for nm in SKIN_PARTS:
		var n := rig.find_child(nm, true, false)
		if n is Node3D:
			(n as Node3D).visible = bool(Settings.get_v(SKIN_PARTS[nm]))


## Small 3D block mesh for dropped block items (uses the shared voxel materials).
static func block_item_mesh(state: int) -> ArrayMesh:
	var blocks := Res.blocks
	var fl := blocks.st_flags[state]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var cust := PackedFloat32Array()
	var idx := PackedInt32Array()
	var tint := ItemIcons.block_tint(state)   # Java item tints (held grass block / leaves are green)
	var add_quad := func(pts: Array, quv: Array, layer: float, ovl: float, shade: float, tinted: bool):
		var b := verts.size()
		var tc: Color = tint if tinted else Color(1, 1, 1)
		for k in 4:
			verts.append(pts[k] - Vector3(0.5, 0.0, 0.5))
			uvs.append(quv[k])
			cols.append(Color(tc.r, tc.g, tc.b, shade))
			cust.append_array([layer, ovl, 1.0, 0.0])
		idx.append_array([b, b + 3, b + 2, b, b + 2, b + 1])
	if fl & BlockRegistry.F_CUBE:
		for d in 6:
			var f := blocks.st_faces[state * 6 + d]
			var pts := ModelBaker.face_corners(d, Vector3.ZERO, Vector3.ONE)
			var quv: Array = []
			for k in 4:
				quv.append(ModelBaker.canon_uv(k, (f >> 24) & 7))
			add_quad.call(pts, quv, float(f & 0xFFF), float(((f >> 12) & 0xFFF) - 1), Mesher.SHADE[d], ((f >> 28) & 1) == 1)
	elif fl & BlockRegistry.F_MODEL:
		var q: PackedFloat32Array = blocks.models[blocks.st_model[state]]
		for qi in q.size() / ModelBaker.QUAD_FLOATS:
			var o := qi * ModelBaker.QUAD_FLOATS
			var pts2: Array = []
			var quv2: Array = []
			for k in 4:
				pts2.append(Vector3(q[o + k * 5], q[o + k * 5 + 1], q[o + k * 5 + 2]))
				quv2.append(Vector2(q[o + k * 5 + 3], q[o + k * 5 + 4]))
			add_quad.call(pts2, quv2, q[o + 20], -1.0, ModelBaker.shade_of(q, o), q[o + 21] >= 0.0)
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_CUSTOM0] = cust
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	m.surface_set_material(0, Res.mat_item_block if Res.mat_item_block != null else Res.mat_cutout)
	return m
