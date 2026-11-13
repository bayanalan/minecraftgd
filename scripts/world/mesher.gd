## Mesher â€” builds opaque / cutout / translucent vertex arrays for one chunk mesh group (GROUP sections)
## on a worker thread. Cube faces: neighbour culling across section/chunk borders, smooth light + AO,
## GREEDY merging of coplanar faces only when texture layers, uv rotation, tint, light and AO are all
## identical (uniform faces); texture repeat via Texture2DArray UVs > 1. Baked model quads for other shapes.
## Fluids: per-cell surface height from level. Contract: build(job) -> Dictionary of 3 surface arrays or null.
## Invariants: never touches the SceneTree; reads only COW snapshots passed in the job.
class_name Mesher

const GROUP := 4                 # sections per mesh group
const GH := GROUP * 16           # group height
const PX := 18
const PL := PX * PX
const DIR_OFF := [[0, -1, 0], [0, 1, 0], [0, 0, -1], [0, 0, 1], [-1, 0, 0], [1, 0, 0]]
const OPP := [1, 0, 3, 2, 5, 4]
# connected textures: pad offsets of a face's texture +u / +v directions (face_corners order with no uv rotation)
const CTM_DU := [1, 1, -1, 1, PX, -PX]
const CTM_DV := [-PX, PX, -PL, -PL, -PL, -PL]
const SHADE := [0.5, 1.0, 0.8, 0.8, 0.6, 0.6]


class Surf:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var cu := PackedFloat32Array()
	var idx := PackedInt32Array()

	func quad(p: Array, uvs: Array, c: Array, layer: float, overlay: float, sky: Array, blk: Array, flip: bool) -> void:
		var b := v.size()
		for k in 4:
			v.append(p[k])
			uv.append(uvs[k])
			col.append(c[k])
			cu.append(layer)
			cu.append(overlay)
			cu.append(sky[k])
			cu.append(blk[k])
		# Godot front faces are clockwise -> reverse Java's CCW vertex order
		if flip:
			idx.append_array([b + 1, b, b + 3, b + 1, b + 3, b + 2])
		else:
			idx.append_array([b, b + 3, b + 2, b, b + 2, b + 1])

	func to_arrays() -> Array:
		if v.is_empty():
			return []
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_COLOR] = col
		# RGBA half floats (Mesh.ARRAY_CUSTOM_RGBA_HALF), same encoding as the native mesher
		var hb := PackedByteArray()
		hb.resize(cu.size() * 2)
		for q in cu.size():
			hb.encode_half(q * 2, cu[q])
		a[Mesh.ARRAY_CUSTOM0] = hb
		a[Mesh.ARRAY_INDEX] = idx
		return a


## job: {snaps: Array[9] (center = 4), light: Array (halo sections), group: int, blocks, tints: PackedColorArray(256*3)}
static func build(job: Dictionary) -> Dictionary:
	if Native.ok and Native.mesh_ok:
		var b: BlockRegistry = job["blocks"]
		var r: Array = Native.inst.mesh(job["snaps"], job["light"], job["group"], job["tints"], b.st_flags, b.st_cull, b.st_faces, b.st_model, b.models, b.st_tint_color, b.st_level, b.water_layer, b.lava_layer, b.st_emit, int(job.get("opts", 0)), b.water_flow_layer, b.lava_flow_layer, b.water_overlay_layer, b.st_ctm)
		if r.is_empty():
			return {}
		var out := {"opaque": r[0], "cutout": r[1], "translucent": r[2], "y_base": r[3]}
		if r.size() > 4:
			out["vis"] = r[4]   # section visibility masks (Java VisGraph) for TerrainRD's occlusion culling
		return out
	return build_gd(job)


## GDScript implementation (fallback and reference for the native port).
static func build_gd(job: Dictionary) -> Dictionary:
	var blocks: BlockRegistry = job["blocks"]
	var snaps: Array = job["snaps"]
	var g: int = job["group"]
	var light_secs: Array = job["light"]
	var tints: PackedColorArray = job["tints"]
	var opts := int(job.get("opts", 0))   # Advanced video: 1 = no smart leaf culling, 2 = no face merging
	var y_base := Coords.MIN_Y + g * GH
	var flags := blocks.st_flags
	var cullm := blocks.st_cull
	var faces := blocks.st_faces
	var ctm := blocks.st_ctm
	# ---- padded state + light arrays (18 x 18 x GH+2)
	var H := GH + 2
	var pad := PackedInt32Array()
	pad.resize(PL * H)
	var plight := PackedByteArray()
	plight.resize(PL * H)
	var center: Array = snaps[4]
	for ly in H:
		var y := y_base + ly - 1
		var o := ly * PL
		if y < Coords.MIN_Y or y >= Coords.MAX_Y:
			for k in PL:
				plight[o + k] = 0xF0 if y >= Coords.MAX_Y else 0
			continue
		var s := (y - Coords.MIN_Y) >> 4
		var ls = light_secs[s]
		if ls is int:
			for k in PL:
				plight[o + k] = ls
		else:
			var lo := (y & 15) * PL
			var lsb: PackedByteArray = ls
			for k in PL:
				plight[o + k] = lsb[lo + k]
		# centre 16x16
		var e: Array = center[s]
		var pal: PackedInt32Array = e[0]
		var base_k := (y & 15) << 8
		if pal.size() == 1:
			var vv := pal[0]
			if vv != 0:
				for z in 16:
					var ro := o + (z + 1) * PX + 1
					for x in 16:
						pad[ro + x] = vv
		else:
			var wide: PackedInt32Array = e[2]
			var idxa: PackedByteArray = e[1]
			var use_wide := wide.size() > 0
			for z in 16:
				var ro2 := o + (z + 1) * PX + 1
				var ko := base_k | (z << 4)
				for x in 16:
					pad[ro2 + x] = pal[wide[ko | x]] if use_wide else pal[idxa[ko | x]]
		# borders from neighbours
		for z in range(-1, 17):
			for x in [-1, 16]:
				pad[o + (z + 1) * PX + x + 1] = _nstate(snaps, x, y, z)
		for x in range(0, 16):
			pad[o + x + 1] = _nstate(snaps, x, y, -1)
			pad[o + 17 * PX + x + 1] = _nstate(snaps, x, y, 16)
	# ---- skip check: group is empty?
	var any := false
	for s2 in range(g * GROUP, g * GROUP + GROUP):
		var e2: Array = center[s2]
		var p2: PackedInt32Array = e2[0]
		if not (p2.size() == 1 and p2[0] == 0):
			any = true
			break
	if not any:
		return {}
	var opaque := Surf.new()
	var cutout := Surf.new()
	var trans := Surf.new()
	var dir_step := PackedInt32Array([-PL, PL, -PX, PX, -1, 1])
	# greedy masks per direction: key per cell (0 = none)
	var masks: Array = []
	for d in 6:
		var m := PackedInt64Array()
		m.resize(16 * 16 * GH)
		masks.append(m)
	var mask_cls := PackedByteArray()
	mask_cls.resize(6 * 16 * 16 * GH)
	var descs: Array = []       # greedy face descriptors [fdata, tint, centre, mode, skies, blks, aos]
	var desc_ix := {}
	for ly in range(1, GH + 1):
		for z in 16:
			var row := ly * PL + (z + 1) * PX + 1
			for x in 16:
				var i := row + x
				var st := pad[i]
				if st == 0:
					continue
				var fl := flags[st]
				if fl & BlockRegistry.F_AIR:
					continue
				var ci := z * 16 + x
				if fl & BlockRegistry.F_CUBE:
					var surf_cls := 0 if (fl & (BlockRegistry.F_CUTOUT | BlockRegistry.F_TRANSLUCENT)) == 0 else (1 if (fl & BlockRegistry.F_CUTOUT) else 2)
					for d in 6:
						var n := pad[i + dir_step[d]]
						if (cullm[n] >> OPP[d]) & 1:
							continue
						if (fl & BlockRegistry.F_LEAVES) and (opts & 1) == 0:
							# cutout leaves: skipped only behind a leaf that is itself backed by a leaf / occluder
							# (see native/src/mesher.cpp); kept at the padded range's edge
							if flags[n] & BlockRegistry.F_LEAVES:
								var ax := x + 1 + (-2 if d == 4 else (2 if d == 5 else 0))
								var az := z + 1 + (-2 if d == 2 else (2 if d == 3 else 0))
								var ay := ly + (-2 if d == 0 else (2 if d == 1 else 0))
								if ax >= 0 and ax < PX and az >= 0 and az < PX and ay >= 0 and ay <= GH + 1:
									var n2 := pad[ay * PL + az * PX + ax]
									if (flags[n2] & BlockRegistry.F_LEAVES) or ((cullm[n2] >> OPP[d]) & 1):
										continue
						elif n == st and (fl & BlockRegistry.F_SELF_CULL):
							continue
						var fdata := faces[st * 6 + d]
						if opts & 4 and st < ctm.size() and ctm[st] >= 0:
							# connected textures: the variant without the frame on edges shared with the same glass
							var cu: int = CTM_DU[d]
							var cv: int = CTM_DV[d]
							var cmask := (1 if pad[i - cv] == st else 0) | (2 if pad[i + cu] == st else 0) | (4 if pad[i + cv] == st else 0) | (8 if pad[i - cu] == st else 0)
							fdata = (fdata & ~0xFFF) | (ctm[st] + cmask)
						var tint := _tint_for(fl, blocks, st, tints, ci, 0) if (fdata >> 28) & 1 else 0xFFFFFF
						var res: Array
						if fl & BlockRegistry.F_NO_AO:
							# Java tesselateWithoutAO: the neighbour's light (emitters raise block light to their emission)
							var lt0 := plight[i + dir_step[d]]
							res = [true, (lt0 >> 4) * 4, maxi(lt0 & 15, blocks.st_emit[st]) * 4, 3, 0]
						else:
							res = _face_light(pad, plight, flags, i, d)
						if res[0]:
							res = [false, [res[1], res[1], res[1], res[1]], [res[2], res[2], res[2], res[2]], [res[3], res[3], res[3], res[3]], res[4]]
						var md := 0 if (opts & 2) else _face_mode(res)
						if md != 0:
							# greedy candidate (see native/src/mesher.cpp FaceDescs: merge modes 1 both, 2 width, 3 height)
							var dkey := "%d:%d:%d:%d:%s:%s:%s" % [fdata & 0x0FFFFFFF, tint & 0xFFFFFF, int(res[4]), md, str(res[1]), str(res[2]), str(res[3])]
							var di: int = desc_ix.get(dkey, -1)
							if di < 0:
								di = descs.size()
								desc_ix[dkey] = di
								descs.append([fdata & 0x0FFFFFFF, tint & 0xFFFFFF, int(res[4]), md, res[1], res[2], res[3]])
							var mi := ((ly - 1) * 16 + z) * 16 + x
							var mk: PackedInt64Array = masks[d]
							mk[mi] = di + 1
							mask_cls[d * 16 * 16 * GH + mi] = surf_cls
						else:
							var surf: Surf = opaque if surf_cls == 0 else (cutout if surf_cls == 1 else trans)
							_emit_cube_face(surf, x, ly - 1, z, d, 1, 1, fdata, tint, res)
				elif fl & BlockRegistry.F_MODEL:
					var surf2: Surf = cutout if (fl & BlockRegistry.F_CUTOUT) else (trans if (fl & BlockRegistry.F_TRANSLUCENT) else opaque)
					_emit_model(surf2, blocks, pad, plight, i, x, ly - 1, z, st, fl, tints, ci)
				if fl & (BlockRegistry.F_FLUID | BlockRegistry.F_WATERLOGGED):
					_emit_fluid(trans if (fl & BlockRegistry.F_LAVA) == 0 else opaque, blocks, pad, plight, i, x, ly - 1, z, st, fl, tints, ci)
	# ---- greedy merge per direction
	for d in 6:
		_greedy(masks[d], mask_cls, d, opaque, cutout, trans, descs)
	return {"opaque": opaque.to_arrays(), "cutout": cutout.to_arrays(), "translucent": trans.to_arrays(), "y_base": y_base}


static func _nstate(snaps: Array, x: int, y: int, z: int) -> int:
	var ci := (((z + 16) >> 4)) * 3 + ((x + 16) >> 4)
	var snap = snaps[ci]
	if snap == null:
		return 0
	var e: Array = snap[(y - Coords.MIN_Y) >> 4]
	var pal: PackedInt32Array = e[0]
	if pal.size() == 1:
		return pal[0]
	var k := ((y & 15) << 8) | ((z & 15) << 4) | (x & 15)
	var wide: PackedInt32Array = e[2]
	if wide.size() > 0:
		return pal[wide[k]]
	var idx: PackedByteArray = e[1]
	return pal[idx[k]]


static func _tint_for(fl: int, blocks: BlockRegistry, st: int, tints: PackedColorArray, ci: int, _overlay: int) -> int:
	var c := Color.WHITE
	if fl & BlockRegistry.F_TINT_GRASS:
		c = tints[ci]
	elif fl & BlockRegistry.F_TINT_FOLIAGE:
		c = tints[256 + ci]
	elif fl & BlockRegistry.F_TINT_WATER:
		c = tints[512 + ci]
	elif fl & BlockRegistry.F_TINT_DRY:
		c = tints[768 + ci] if tints.size() >= 1024 else tints[256 + ci]
	elif fl & BlockRegistry.F_TINT_CONST:
		return blocks.st_tint_color[st]
	else:
		return 0xFFFFFF
	return (c.r8 << 16) | (c.g8 << 8) | c.b8


## Returns [uniform:bool, sky(0-15) or Array, block, ao] â€” per-vertex arrays when not uniform.
## Java ModelBlockRenderer.AmbientOcclusionFace.calculate for a full-block face. Samples in the layer in front of the
## face: the two sides (A, B), the corner (replaced by side A when both sides block view: opaque cubes) and the block
## in front itself. Shade: 0.2 for every sample with a full collision shape (Block.getShadeBrightness), averaged
## over the four -> per vertex 1 - 0.2 * (occluding sides / corner) - 0.2 * centre. Light: Java blend() - samples
## with sky = block = 0 take the front block's value, then the average of the four (stored to the nearest level).
## Returns [uniform, sky(s), blk(s), ao(s), centre]: ao = 3 - occluding sides / corner (0 .. 3).
static func _face_light(pad: PackedInt32Array, plight: PackedByteArray, flags: PackedInt32Array, i: int, d: int) -> Array:
	var f0 := i + (PL if d == 1 else (-PL if d == 0 else (PX if d == 3 else (-PX if d == 2 else (1 if d == 5 else -1)))))
	return _face_light_at(pad, plight, flags, f0, d, plight[f0], 1 if (flags[pad[f0]] & BlockRegistry.F_FULL_SHAPE) != 0 else 0)


## The same for an arbitrary sample layer f with the caller's centre light / centre shade (model quads inside their block
## sample their own layer: Java AmbientOcclusionFace with blockpos = pos).
static func _face_light_at(pad: PackedInt32Array, plight: PackedByteArray, flags: PackedInt32Array, f: int, d: int, lf: int, center: int) -> Array:
	# tangent steps (A, B) for this face plane
	var sa: int
	var sb: int
	if d <= 1:
		sa = 1
		sb = PX
	elif d <= 3:
		sa = 1
		sb = PL
	else:
		sa = PX
		sb = PL
	var occ := BlockRegistry.F_FULL_SHAPE
	var vb := BlockRegistry.F_OPAQUE
	var oa_n := (flags[pad[f - sa]] & occ) != 0
	var oa_p := (flags[pad[f + sa]] & occ) != 0
	var ob_n := (flags[pad[f - sb]] & occ) != 0
	var ob_p := (flags[pad[f + sb]] & occ) != 0
	var va_n := (flags[pad[f - sa]] & vb) != 0
	var va_p := (flags[pad[f + sa]] & vb) != 0
	var vb_n := (flags[pad[f - sb]] & vb) != 0
	var vb_p := (flags[pad[f + sb]] & vb) != 0
	var la_n := plight[f - sa]
	var la_p := plight[f + sa]
	var lb_n := plight[f - sb]
	var lb_p := plight[f + sb]
	var skies := [0, 0, 0, 0]
	var blks := [0, 0, 0, 0]
	var aos := [0, 0, 0, 0]
	var uniform := true
	var corners := [[-1, -1], [1, -1], [1, 1], [-1, 1]]
	for k in 4:
		var ca: int = corners[k][0]
		var cb: int = corners[k][1]
		var s1 := oa_n if ca < 0 else oa_p
		var s2 := ob_n if cb < 0 else ob_p
		var l1 := la_n if ca < 0 else la_p
		var l2 := lb_n if cb < 0 else lb_p
		var cidx := f + ca * sa + cb * sb
		var cc: bool
		var l3: int
		if (va_n if ca < 0 else va_p) and (vb_n if cb < 0 else vb_p):
			cc = s1
			l3 = l1
		else:
			cc = (flags[pad[cidx]] & occ) != 0
			l3 = plight[cidx]
		var ao := 3 - (int(s1) + int(s2) + int(cc))
		var a1: int = lf if l1 == 0 else l1
		var a2: int = lf if l2 == 0 else l2
		var a3: int = lf if l3 == 0 else l3
		# Java blend(): the average of the 4 samples kept in quarter levels (sum 0..60), not rounded to a whole level
		skies[k] = (lf >> 4) + (a1 >> 4) + (a2 >> 4) + (a3 >> 4)
		blks[k] = (lf & 15) + (a1 & 15) + (a2 & 15) + (a3 & 15)
		aos[k] = ao
		if k > 0 and (skies[k] != skies[0] or blks[k] != blks[0] or aos[k] != aos[0]):
			uniform = false
	if uniform:
		return [true, skies[0], blks[0], aos[0], center]
	return [false, skies, blks, aos, center]

const AO_CURVE := [0.4, 0.6, 0.8, 1.0]   # Java: 1 - 0.2 per occluding sample (sides / corner); centre handled separately


## Corner order for (dir) in Java FaceInfo order mapped to plane corner signs [A,B] used by _face_light.
static func _corner_signs(d: int) -> Array:
	match d:
		0: return [[-1, 1], [-1, -1], [1, -1], [1, 1]]
		1: return [[-1, -1], [-1, 1], [1, 1], [1, -1]]
		2: return [[1, 1], [1, -1], [-1, -1], [-1, 1]]
		3: return [[-1, 1], [-1, -1], [1, -1], [1, 1]]
		4: return [[-1, 1], [-1, -1], [1, -1], [1, 1]]
		_: return [[1, 1], [1, -1], [-1, -1], [-1, 1]]


static func _sign_to_k(sa: int, sb: int) -> int:
	if sa < 0 and sb < 0:
		return 0
	if sa > 0 and sb < 0:
		return 1
	if sa > 0 and sb > 0:
		return 2
	return 3


## Emit a (possibly merged) cube face. x,y,z local (y relative to group base); w spans A-axis, h spans B-axis.
static func _emit_cube_face(surf: Surf, x: int, y: int, z: int, d: int, w: int, h: int, fdata: int, tint: int, res: Array) -> void:
	var a := Vector3(x, y, z)
	var b: Vector3
	# A/B axes: d<=1: A=x, B=z ; d<=3: A=x, B=y ; else A=z, B=y
	if d <= 1:
		b = Vector3(x + w, y + 1, z + h)
	elif d <= 3:
		b = Vector3(x + w, y + h, z + 1)
	else:
		b = Vector3(x + 1, y + h, z + w)
	var pts := ModelBaker.face_corners(d, a, b)
	var rf := (fdata >> 24) & 7
	var layer := float(fdata & 0xFFF)
	var ovl := float(((fdata >> 12) & 0xFFF) - 1)
	var ua_is_a := (rf & 1) == 0  # U along A axis unless rotated 90/270
	var ext_a := float(w)
	var ext_b := float(h)
	var uvs := []
	var cols := []
	var skies := []
	var blks := []
	var signs := _corner_signs(d)
	var shade: float = SHADE[d]
	var tc := Color8((tint >> 16) & 255, (tint >> 8) & 255, tint & 255)
	for k in 4:
		var cuv := ModelBaker.canon_uv(k, rf)
		var u := cuv.x * (ext_a if ua_is_a else ext_b)
		var v := cuv.y * (ext_b if ua_is_a else ext_a)
		uvs.append(Vector2(u, v))
		var sk: int
		var bl: int
		var ao: int
		if res[0]:
			sk = res[1]
			bl = res[2]
			ao = res[3]
		else:
			var kk := _sign_to_k(signs[k][0], signs[k][1])
			sk = res[1][kk]
			bl = res[2][kk]
			ao = res[3][kk]
		var c := tc
		c.a = shade * (AO_CURVE[ao] - 0.2 * int(res[4]))
		cols.append(c)
		skies.append(sk / 60.0)   # quarter levels (Java sample_lightmap interpolates between levels)
		blks.append(bl / 60.0)
	surf.quad(pts, uvs, cols, layer, ovl, skies, blks, false)   # Java: fixed 0-1-2 / 2-3-0 triangulation, no AO flip


## Merge mode of a lit face: 1 uniform, 2 constant along a (corners 0 = 1, 3 = 2), 3 constant along b (0 = 3, 1 = 2), 0 none.
static func _face_mode(res: Array) -> int:
	var sk: Array = res[1]
	var bl: Array = res[2]
	var ao: Array = res[3]
	var ca: bool = sk[0] == sk[1] and bl[0] == bl[1] and ao[0] == ao[1] and sk[3] == sk[2] and bl[3] == bl[2] and ao[3] == ao[2]
	var cb: bool = sk[0] == sk[3] and bl[0] == bl[3] and ao[0] == ao[3] and sk[1] == sk[2] and bl[1] == bl[2] and ao[1] == ao[2]
	return 1 if (ca and cb) else (2 if ca else (3 if cb else 0))


static func _greedy(mask: PackedInt64Array, cls: PackedByteArray, d: int, opaque: Surf, cutout: Surf, trans: Surf, descs: Array) -> void:
	var cbase := d * 16 * 16 * GH
	# iterate slices along the face normal axis; plane coords (A,B)
	if d <= 1:
		for ly in GH:
			var o := ly * 256
			for z in 16:
				var x := 0
				while x < 16:
					var mi := o + z * 16 + x
					var key := mask[mi]
					if key == 0:
						x += 1
						continue
					var md: int = descs[key - 1][3]
					var w := 1
					while md != 3 and x + w < 16 and mask[mi + w] == key:
						w += 1
					var h := 1
					var done := md == 2
					while z + h < 16 and not done:
						for k in w:
							if mask[o + (z + h) * 16 + x + k] != key:
								done = true
								break
						if not done:
							h += 1
					for hh in h:
						for k in w:
							mask[o + (z + hh) * 16 + x + k] = 0
					_emit_key(opaque, cutout, trans, cls[cbase + mi], x, ly, z, d, w, h, descs[key - 1])
					x += w
	elif d <= 3:
		for z in 16:
			for ly in GH:
				var x2 := 0
				while x2 < 16:
					var mi2 := (ly * 16 + z) * 16 + x2
					var key2 := mask[mi2]
					if key2 == 0:
						x2 += 1
						continue
					var md2: int = descs[key2 - 1][3]
					var w2 := 1
					while md2 != 3 and x2 + w2 < 16 and mask[mi2 + w2] == key2:
						w2 += 1
					var h2 := 1
					var done2 := md2 == 2
					while ly + h2 < GH and not done2:
						for k in w2:
							if mask[((ly + h2) * 16 + z) * 16 + x2 + k] != key2:
								done2 = true
								break
						if not done2:
							h2 += 1
					for hh in h2:
						for k in w2:
							mask[((ly + hh) * 16 + z) * 16 + x2 + k] = 0
					_emit_key(opaque, cutout, trans, cls[cbase + mi2], x2, ly, z, d, w2, h2, descs[key2 - 1])
					x2 += w2
	else:
		for x in 16:
			for ly in GH:
				var z2 := 0
				while z2 < 16:
					var mi3 := (ly * 16 + z2) * 16 + x
					var key3 := mask[mi3]
					if key3 == 0:
						z2 += 1
						continue
					var md3: int = descs[key3 - 1][3]
					var w3 := 1
					while md3 != 3 and z2 + w3 < 16 and mask[mi3 + w3 * 16] == key3:
						w3 += 1
					var h3 := 1
					var done3 := md3 == 2
					while ly + h3 < GH and not done3:
						for k in w3:
							if mask[((ly + h3) * 16 + z2 + k) * 16 + x] != key3:
								done3 = true
								break
						if not done3:
							h3 += 1
					for hh in h3:
						for k in w3:
							mask[((ly + hh) * 16 + z2 + k) * 16 + x] = 0
					_emit_key(opaque, cutout, trans, cls[cbase + mi3], x, ly, z2, d, w3, h3, descs[key3 - 1])
					z2 += w3


static func _emit_key(opaque: Surf, cutout: Surf, trans: Surf, cl: int, x: int, y: int, z: int, d: int, w: int, h: int, desc: Array) -> void:
	var fdata: int = desc[0]
	var tint: int = desc[1]
	var res := [false, desc[4], desc[5], desc[6], desc[2]]
	var surf: Surf = opaque if cl == 0 else (cutout if cl == 1 else trans)
	_emit_cube_face(surf, x, y, z, d, w, h, fdata, tint, res)

static func _emit_model(surf: Surf, blocks: BlockRegistry, pad: PackedInt32Array, plight: PackedByteArray, i: int, x: int, y: int, z: int, st: int, fl: int, tints: PackedColorArray, ci: int) -> void:
	var q: PackedFloat32Array = blocks.models[blocks.st_model[st]]
	var n := q.size() / ModelBaker.QUAD_FLOATS
	var cullm := blocks.st_cull
	var steps := [-PL, PL, -PX, PX, -1, 1]
	var tint_c := _tint_for(fl, blocks, st, tints, ci, 0)
	var tcol := Color8((tint_c >> 16) & 255, (tint_c >> 8) & 255, tint_c & 255)
	var own := plight[i]
	var flags := blocks.st_flags
	var no_ao := (fl & BlockRegistry.F_NO_AO) != 0
	var full := (fl & BlockRegistry.F_FULL_SHAPE) != 0
	var em: int = blocks.st_emit[st]
	for qi in n:
		var o := qi * ModelBaker.QUAD_FLOATS
		var cf := int(q[o + 22])
		if cf >= 0:
			var nb := pad[i + steps[cf]]
			if (cullm[nb] >> OPP[cf]) & 1:
				continue
			if nb == st and (fl & BlockRegistry.F_SELF_CULL):
				continue
		var dirn := int(q[o + 23])
		var shade: float = ModelBaker.shade_of(q, o)
		var c := tcol if q[o + 21] >= 0.0 else Color.WHITE
		var pts := []
		var uvs := []
		var mn := [32.0, 32.0, 32.0]
		var mx := [-32.0, -32.0, -32.0]
		for k in 4:
			pts.append(Vector3(x + q[o + k * 5], y + q[o + k * 5 + 1], z + q[o + k * 5 + 2]))
			uvs.append(Vector2(q[o + k * 5 + 3], q[o + k * 5 + 4]))
			for a2 in 3:
				mn[a2] = minf(mn[a2], q[o + k * 5 + a2])
				mx[a2] = maxf(mx[a2], q[o + k * 5 + a2])
		# Java calculateShape flag 0: the quad lies on the block boundary in its direction (or the block is a full cube)
		var on_face := false
		match dirn:
			0: on_face = mn[1] == mx[1] and (mn[1] < 1.0e-4 or full)
			1: on_face = mn[1] == mx[1] and (mx[1] > 0.9999 or full)
			2: on_face = mn[2] == mx[2] and (mn[2] < 1.0e-4 or full)
			3: on_face = mn[2] == mx[2] and (mx[2] > 0.9999 or full)
			4: on_face = mn[0] == mx[0] and (mn[0] < 1.0e-4 or full)
			_: on_face = mn[0] == mx[0] and (mx[0] > 0.9999 or full)
		var cols := []
		var sks := []
		var bls := []
		if no_ao:
			# Java renderModelFaceFlat (see native/src/mesher.cpp emit_model)
			var lt: int = plight[i + steps[cf]] if cf >= 0 else (plight[i + steps[dirn]] if on_face else own)
			var c0 := c
			c0.a = shade
			var sk0 := (lt >> 4) / 15.0
			var bl0 := maxi(lt & 15, em) / 15.0
			for k in 4:
				cols.append(c0)
				sks.append(sk0)
				bls.append(bl0)
		else:
			# Java AmbientOcclusionFace for model quads (see native/src/mesher.cpp emit_model)
			var fi: int = i + steps[dirn]
			var base: int = fi if on_face else i
			var lf: int = plight[fi] if (on_face or (flags[pad[fi]] & BlockRegistry.F_OPAQUE) == 0) else own
			var ctr: int = (1 if (flags[pad[fi]] & BlockRegistry.F_FULL_SHAPE) != 0 else 0) if on_face else (1 if full else 0)
			var r := _face_light_at(pad, plight, flags, base, dirn, lf, ctr)
			var sky_c: Array = r[1] if not r[0] else [r[1], r[1], r[1], r[1]]
			var blk_c: Array = r[2] if not r[0] else [r[2], r[2], r[2], r[2]]
			var ao_c: Array = r[3] if not r[0] else [r[3], r[3], r[3], r[3]]
			var br := []
			for k in 4:
				br.append(AO_CURVE[ao_c[k]] - 0.2 * int(r[4]))
			var ia := 0 if dirn <= 3 else 2
			var ib := 2 if dirn <= 1 else 1
			for k in 4:
				var pa := clampf(q[o + k * 5 + ia], 0.0, 1.0)
				var pb := clampf(q[o + k * 5 + ib], 0.0, 1.0)
				var w0 := (1.0 - pa) * (1.0 - pb)
				var w1 := pa * (1.0 - pb)
				var w2 := pa * pb
				var w3 := (1.0 - pa) * pb
				var b: float = w0 * br[0] + w1 * br[1] + w2 * br[2] + w3 * br[3]
				var sv: float = w0 * sky_c[0] + w1 * sky_c[1] + w2 * sky_c[2] + w3 * sky_c[3]
				var bv: float = w0 * blk_c[0] + w1 * blk_c[1] + w2 * blk_c[2] + w3 * blk_c[3]
				var ck := c
				ck.a = shade * b
				cols.append(ck)
				sks.append(sv / 60.0)
				bls.append(bv / 60.0)
		surf.quad(pts, uvs, cols, q[o + 20], -1.0, sks, bls, false)


## Java LiquidBlockRenderer (port; native mesher.cpp emit_fluid is the same code). Same fluid = fluid or waterlogged
## cell of the same kind.
static func _same_fluid(fl: int, is_lava: bool) -> bool:
	return (fl & (BlockRegistry.F_FLUID | BlockRegistry.F_WATERLOGGED)) != 0 and ((fl & BlockRegistry.F_LAVA) != 0) == is_lava


## Java FluidState.getOwnHeight: amount / 9 (source and falling 8, flowing level L: 8 - L).
static func _own_h(blocks: BlockRegistry, st: int) -> float:
	if (blocks.st_flags[st] & BlockRegistry.F_FLUID) == 0:
		return 8.0 / 9.0
	var lv := blocks.st_level[st]
	return 8.0 / 9.0 if lv == 0 or lv >= 8 else (8.0 - lv) / 9.0


## Java LiquidBlockRenderer.getHeight: 1 under the same fluid, its own height, 0 for a non-solid cell, -1 solid.
static func _cell_h(blocks: BlockRegistry, pad: PackedInt32Array, j: int, is_lava: bool) -> float:
	var st := pad[j]
	var fl := blocks.st_flags[st]
	if _same_fluid(fl, is_lava):
		return 1.0 if _same_fluid(blocks.st_flags[pad[j + PL]], is_lava) else _own_h(blocks, st)
	return -1.0 if fl & BlockRegistry.F_SOLID else 0.0


## Java calculateAverageHeight / addWeightedHeight (heights >= 0.8 weigh 10, solid neighbours -1 are left out).
static func _avg_h(blocks: BlockRegistry, pad: PackedInt32Array, cur: float, h1: float, h2: float, diag: int, is_lava: bool) -> float:
	if h2 >= 1.0 or h1 >= 1.0:
		return 1.0
	var s := 0.0
	var w := 0.0
	if h2 > 0.0 or h1 > 0.0:
		var f := _cell_h(blocks, pad, diag, is_lava)
		if f >= 1.0:
			return 1.0
		if f >= 0.8:
			s += f * 10.0
			w += 10.0
		elif f >= 0.0:
			s += f
			w += 1.0
	for v in [cur, h2, h1]:
		if v >= 0.8:
			s += v * 10.0
			w += 10.0
		elif v >= 0.0:
			s += v
			w += 1.0
	return s / w


## Java FlowingFluid.getFlow (horizontal part; directions NORTH, EAST, SOUTH, WEST).
static func _flow(blocks: BlockRegistry, pad: PackedInt32Array, i: int, st: int, is_lava: bool) -> Vector2:
	var own := _own_h(blocks, st)
	var d0 := 0.0
	var d1 := 0.0
	for k in 4:
		var step: int = [-PX, 1, PX, -1][k]
		var sx: int = [0, 1, 0, -1][k]
		var sz: int = [-1, 0, 1, 0][k]
		var nb := pad[i + step]
		var nf := blocks.st_flags[nb]
		var nfl := (nf & (BlockRegistry.F_FLUID | BlockRegistry.F_WATERLOGGED)) != 0
		if nfl and not _same_fluid(nf, is_lava):
			continue
		var f := _own_h(blocks, nb) if nfl else 0.0
		var f1 := 0.0
		if f == 0.0:
			if (nf & BlockRegistry.F_COLLIDE) == 0:
				var b2 := pad[i + step - PL]
				var bf := blocks.st_flags[b2]
				var bfl := (bf & (BlockRegistry.F_FLUID | BlockRegistry.F_WATERLOGGED)) != 0
				if not bfl or _same_fluid(bf, is_lava):
					f = _own_h(blocks, b2) if bfl else 0.0
					if f > 0.0:
						f1 = own - (f - 0.8888889)
		elif f > 0.0:
			f1 = own - f
		if f1 != 0.0:
			d0 += sx * f1
			d1 += sz * f1
	return Vector2(d0, d1)


static func _maxlight(a: int, b: int) -> int:
	return maxi(a & 0xF0, b & 0xF0) | maxi(a & 15, b & 15)


static func _emit_fluid(surf: Surf, blocks: BlockRegistry, pad: PackedInt32Array, plight: PackedByteArray, i: int, x: int, y: int, z: int, st: int, fl: int, tints: PackedColorArray, ci: int) -> void:
	var is_lava := (fl & BlockRegistry.F_LAVA) != 0
	var still := float(blocks.lava_layer if is_lava else blocks.water_layer)
	var flow := float(blocks.lava_flow_layer if is_lava else blocks.water_flow_layer)
	var c := Color.WHITE if is_lava else tints[512 + ci]
	var fflags := blocks.st_flags
	var up_same := _same_fluid(fflags[pad[i + PL]], is_lava)
	var dn := pad[i - PL]
	var draw_down := not _same_fluid(fflags[dn], is_lava) and not ((blocks.st_cull[dn] >> 1) & 1)
	var h := _cell_h(blocks, pad, i, is_lava)
	var cnw := 1.0
	var cne := 1.0
	var csw := 1.0
	var cse := 1.0
	if h < 1.0:
		var hn := _cell_h(blocks, pad, i - PX, is_lava)
		var hs := _cell_h(blocks, pad, i + PX, is_lava)
		var he := _cell_h(blocks, pad, i + 1, is_lava)
		var hw := _cell_h(blocks, pad, i - 1, is_lava)
		cne = _avg_h(blocks, pad, h, hn, he, i - PX + 1, is_lava)
		cnw = _avg_h(blocks, pad, h, hn, hw, i - PX - 1, is_lava)
		cse = _avg_h(blocks, pad, h, hs, he, i + PX + 1, is_lava)
		csw = _avg_h(blocks, pad, h, hs, hw, i + PX - 1, is_lava)
	var lt := _maxlight(plight[i], plight[i + PL])
	var sk := (lt >> 4) / 15.0
	var bl := (lt & 15) / 15.0
	var sks := [sk, sk, sk, sk]
	var bls := [bl, bl, bl, bl]
	var x0 := float(x)
	var z0 := float(z)
	var y0 := float(y)
	var bottom := 0.001 if draw_down else 0.0
	# top (Java: corners lowered 0.001 once the top is drawn; the sides use the lowered values too)
	if not up_same and not (minf(minf(cnw, csw), minf(cse, cne)) >= 1.0 and (blocks.st_cull[pad[i + PL]] & 1)):
		cnw -= 0.001
		csw -= 0.001
		cse -= 0.001
		cne -= 0.001
		var fv := _flow(blocks, pad, i, st, is_lava)
		var uvc: Array
		var layer := still
		if fv.x == 0.0 and fv.y == 0.0:
			uvc = [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
		else:
			layer = flow
			var ang := atan2(fv.y, fv.x) - PI / 2.0
			var s := sin(ang) * 0.25
			var co := cos(ang) * 0.25
			uvc = [Vector2(0.5 + (-co - s), 0.5 + (-co + s)), Vector2(0.5 + (-co + s), 0.5 + (co + s)), Vector2(0.5 + (co + s), 0.5 + (co - s)), Vector2(0.5 + (co - s), 0.5 + (-co - s))]
		# NW (x0, z0), SW (x0, z1), SE (x1, z1), NE (x1, z0)
		var pts := [Vector3(x0, y0 + cnw, z0), Vector3(x0, y0 + csw, z0 + 1.0), Vector3(x0 + 1.0, y0 + cse, z0 + 1.0), Vector3(x0 + 1.0, y0 + cne, z0)]
		var cc := c
		cc.a = SHADE[1]
		var cs := [cc, cc, cc, cc]
		surf.quad(pts, uvc, cs, layer, -1.0, sks, bls, false)
		if not is_lava:
			surf.quad([pts[3], pts[2], pts[1], pts[0]], [uvc[3], uvc[2], uvc[1], uvc[0]], cs, layer, -1.0, sks, bls, false)
	if draw_down:
		var lt2 := _maxlight(plight[i - PL], plight[i])
		var sk2 := (lt2 >> 4) / 15.0
		var bl2 := (lt2 & 15) / 15.0
		var cd := c
		cd.a = SHADE[0]
		var yb := y0 + bottom
		surf.quad([Vector3(x0, yb, z0 + 1.0), Vector3(x0, yb, z0), Vector3(x0 + 1.0, yb, z0), Vector3(x0 + 1.0, yb, z0 + 1.0)],
			[Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)], [cd, cd, cd, cd], still, -1.0, [sk2, sk2, sk2, sk2], [bl2, bl2, bl2, bl2], false)
	# sides (Java order NORTH, SOUTH, WEST, EAST; 0.001 inside the cell; flow sprite u 0..0.5, v (1 - h) / 2..0.5)
	for k in 4:
		var d: int = [2, 3, 4, 5][k]
		var nb := pad[i + [-PX, PX, -1, 1][k]]
		var nf := fflags[nb]
		if _same_fluid(nf, is_lava):
			continue
		if (blocks.st_cull[nb] >> OPP[d]) & 1:
			continue
		var p1: Vector3
		var p2: Vector3
		var h1: float
		var h2: float
		match k:
			0:
				h1 = cnw; h2 = cne; p1 = Vector3(x0, 0, z0 + 0.001); p2 = Vector3(x0 + 1.0, 0, z0 + 0.001)
			1:
				h1 = cse; h2 = csw; p1 = Vector3(x0 + 1.0, 0, z0 + 1.0 - 0.001); p2 = Vector3(x0, 0, z0 + 1.0 - 0.001)
			2:
				h1 = csw; h2 = cnw; p1 = Vector3(x0 + 0.001, 0, z0 + 1.0); p2 = Vector3(x0 + 0.001, 0, z0)
			_:
				h1 = cne; h2 = cse; p1 = Vector3(x0 + 1.0 - 0.001, 0, z0); p2 = Vector3(x0 + 1.0 - 0.001, 0, z0 + 1.0)
		var overlay := not is_lava and (nf & BlockRegistry.F_SELF_CULL) != 0 and (nf & (BlockRegistry.F_FLUID | BlockRegistry.F_WATERLOGGED)) == 0
		var sl := float(blocks.water_overlay_layer) if overlay else flow
		var sc := c
		sc.a = SHADE[d]
		var sv := [Vector3(p1.x, y0 + h1, p1.z), Vector3(p2.x, y0 + h2, p2.z), Vector3(p2.x, y0 + bottom, p2.z), Vector3(p1.x, y0 + bottom, p1.z)]
		var su := [Vector2(0.0, (1.0 - h1) * 0.5), Vector2(0.5, (1.0 - h2) * 0.5), Vector2(0.5, 0.5), Vector2(0.0, 0.5)]
		surf.quad(sv, su, [sc, sc, sc, sc], sl, -1.0, sks, bls, false)
		if not overlay:
			surf.quad([sv[3], sv[2], sv[1], sv[0]], [su[3], su[2], su[1], su[0]], [sc, sc, sc, sc], sl, -1.0, sks, bls, false)