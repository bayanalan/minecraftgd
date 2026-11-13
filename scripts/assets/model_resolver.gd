## ModelBaker — resolves vanilla-format block models (parents, texture vars, elements, rotations, uvlock)
## into baked quads in block-local space. Works for imported Java models and original placeholder models.
## Contract: bake(model_id, rx, ry, uvlock) -> {quads: PackedFloat32Array, boxes: Array[AABB], ok: bool}
## Quad layout (QUAD_FLOATS floats): 4 x (x,y,z,u,v), layer, tintindex, cullface, dir, shade
## (shade: 0 none, 1 by the face direction, 2 + d by direction d - 26.x element "shade_direction_override").
## shade_of(q, o) gives the brightness factor.
## Invariants: dirs 0=down 1=up 2=north 3=south 4=west 5=east (Java Direction order); positions 0..1.
class_name ModelBaker
extends RefCounted

const QUAD_FLOATS := 25
const DIR_NAMES := ["down", "up", "north", "south", "west", "east"]
const SHADE := [0.5, 1.0, 0.8, 0.8, 0.6, 0.6]   # Java Level.getShade (overworld) per direction


## Directional shade factor of baked quad o (see the quad layout): Java ModelBlockRenderer uses Level.getShade(dir, shade).
static func shade_of(q: PackedFloat32Array, o: int) -> float:
	var s := q[o + 24]
	if s > 1.5:
		return SHADE[clampi(int(s) - 2, 0, 5)]
	return SHADE[int(q[o + 23])] if s > 0.5 else 1.0


const DIR_VEC := [Vector3(0, -1, 0), Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]

var source: Callable          # func(path: String) -> Variant (parsed json or null)
var texture_layer: Callable   # func(tex_name: String) -> int
var model_cache: Dictionary = {}
var bake_cache: Dictionary = {}
var errors: Array = []


func _init(json_source: Callable, layer_fn: Callable) -> void:
	source = json_source
	texture_layer = layer_fn


static func norm_id(id: String) -> String:
	var s := id.trim_prefix("minecraft:")
	return s


func resolve(id: String, depth: int = 0) -> Dictionary:
	id = norm_id(id)
	if model_cache.has(id):
		return model_cache[id]
	var out := {"textures": {}, "elements": null, "ao": true, "builtin": ""}
	if depth > 32:
		return out
	if id.begins_with("builtin/"):
		out["builtin"] = id
		model_cache[id] = out
		return out
	var j = source.call("assets/minecraft/models/" + id + ".json")
	if not (j is Dictionary):
		errors.append("missing model " + id)
		model_cache[id] = out
		return out
	if j.has("parent"):
		var par := resolve(str(j["parent"]), depth + 1)
		out["textures"] = (par["textures"] as Dictionary).duplicate()
		out["elements"] = par["elements"]
		out["ao"] = par["ao"]
		out["builtin"] = par["builtin"]
	if j.get("textures") is Dictionary:
		for k in j["textures"]:
			var tv = j["textures"][k]
			if tv is Dictionary:
				tv = tv.get("sprite", "")
			out["textures"][k] = str(tv)
	if j.get("elements") is Array:
		out["elements"] = j["elements"]
	if j.has("ambientocclusion"):
		out["ao"] = bool(j["ambientocclusion"])
	model_cache[id] = out
	return out


func resolve_tex(textures: Dictionary, ref: String) -> String:
	var r := ref
	for i in 16:
		if r.begins_with("#"):
			r = str(textures.get(r.substr(1), ""))
		else:
			break
	if r.is_empty() or r.begins_with("#"):
		return ""
	return norm_id(r)


static func _rot_point(p: Vector3, axis: String, ang_deg: float, origin: Vector3, rescale: bool) -> Vector3:
	var a := deg_to_rad(ang_deg)
	var q := p - origin
	var c := cos(a)
	var s := sin(a)
	var r := q
	var sc := Vector3.ONE
	match axis:
		"x":
			r = Vector3(q.x, q.y * c - q.z * s, q.y * s + q.z * c)
			sc = Vector3(1, 1.0 / c, 1.0 / c) if rescale else Vector3.ONE
		"y":
			r = Vector3(q.x * c + q.z * s, q.y, -q.x * s + q.z * c)
			sc = Vector3(1.0 / c, 1, 1.0 / c) if rescale else Vector3.ONE
		"z":
			r = Vector3(q.x * c - q.y * s, q.x * s + q.y * c, q.z)
			sc = Vector3(1.0 / c, 1.0 / c, 1) if rescale else Vector3.ONE
	return r * sc + origin


## Blockstate rotation: X first then Y, both negated (matches Java's rotationYXZ(-y,-x,0)).
static func _state_rot(p: Vector3, rx: int, ry: int) -> Vector3:
	var q := p - Vector3(0.5, 0.5, 0.5)
	if rx != 0:
		var a := deg_to_rad(-rx)
		var c := roundf(cos(a))
		var s := roundf(sin(a))
		q = Vector3(q.x, q.y * c - q.z * s, q.y * s + q.z * c)
	if ry != 0:
		var b := deg_to_rad(-ry)
		var c2 := roundf(cos(b))
		var s2 := roundf(sin(b))
		q = Vector3(q.x * c2 + q.z * s2, q.y, -q.x * s2 + q.z * c2)
	return q + Vector3(0.5, 0.5, 0.5)


static func dir_of_vec(v: Vector3) -> int:
	var best := 0
	var bd := -2.0
	for i in 6:
		var d: float = v.dot(DIR_VEC[i])
		if d > bd:
			bd = d
			best = i
	return best


static func default_uv(dir: int, f: Vector3, t: Vector3) -> Array:
	match dir:
		0: return [f.x, 16.0 - t.z, t.x, 16.0 - f.z]
		1: return [f.x, f.z, t.x, t.z]
		2: return [16.0 - t.x, 16.0 - t.y, 16.0 - f.x, 16.0 - f.y]
		3: return [f.x, 16.0 - t.y, t.x, 16.0 - f.y]
		4: return [f.z, 16.0 - t.y, t.z, 16.0 - f.y]
		_: return [16.0 - t.z, 16.0 - t.y, 16.0 - f.z, 16.0 - f.y]


## Java FaceInfo vertex order for each direction (min/max picks): returns 4 corner points.
static func face_corners(dir: int, a: Vector3, b: Vector3) -> Array:
	match dir:
		0: return [Vector3(a.x, a.y, b.z), Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z)]
		1: return [Vector3(a.x, b.y, a.z), Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z)]
		2: return [Vector3(b.x, b.y, a.z), Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z)]
		3: return [Vector3(a.x, b.y, b.z), Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z)]
		4: return [Vector3(a.x, b.y, a.z), Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z)]
		_: return [Vector3(b.x, b.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z)]


func bake(model_id: String, rx: int = 0, ry: int = 0, uvlock: bool = false) -> Dictionary:
	var key := "%s|%d|%d|%s" % [model_id, rx, ry, uvlock]
	if bake_cache.has(key):
		return bake_cache[key]
	var m := resolve(model_id)
	var quads := PackedFloat32Array()
	var boxes: Array = []
	var res := {"quads": quads, "boxes": boxes, "ok": true, "ao": m["ao"], "particle": ""}
	res["particle"] = resolve_tex(m["textures"], "#particle")
	var els = m["elements"]
	if not (els is Array):
		res["ok"] = false
		bake_cache[key] = res
		return res
	for e in els:
		if not (e is Dictionary):
			continue
		var fa: Array = e.get("from", [0, 0, 0])
		var ta: Array = e.get("to", [16, 16, 16])
		var f := Vector3(float(fa[0]), float(fa[1]), float(fa[2]))
		var t := Vector3(float(ta[0]), float(ta[1]), float(ta[2]))
		var erot = e.get("rotation", null)
		var has_erot := erot is Dictionary and absf(float(erot.get("angle", 0.0))) > 0.001
		var r_axis := ""
		var r_ang := 0.0
		var r_org := Vector3(8, 8, 8)
		var r_rescale := false
		if has_erot:
			r_axis = str(erot.get("axis", "y"))
			r_ang = float(erot.get("angle", 0.0))
			var oa: Array = erot.get("origin", [8, 8, 8])
			r_org = Vector3(float(oa[0]), float(oa[1]), float(oa[2]))
			r_rescale = bool(erot.get("rescale", false))
		# collision/outline box (axis aligned, after state rotation)
		var c1 := _state_rot(f / 16.0, rx, ry)
		var c2 := _state_rot(t / 16.0, rx, ry)
		var bmin := Vector3(minf(c1.x, c2.x), minf(c1.y, c2.y), minf(c1.z, c2.z))
		var bmax := Vector3(maxf(c1.x, c2.x), maxf(c1.y, c2.y), maxf(c1.z, c2.z))
		if not has_erot and (bmax - bmin).length_squared() > 0.0:
			boxes.append(AABB(bmin, bmax - bmin))
		var faces = e.get("faces", {})
		if not (faces is Dictionary):
			continue
		for dname in faces:
			var dir := DIR_NAMES.find(str(dname))
			if dir < 0:
				continue
			var fd: Dictionary = faces[dname]
			var tex := resolve_tex(m["textures"], str(fd.get("texture", "")))
			if tex.is_empty():
				errors.append("unresolved texture in " + model_id)
				continue
			var layer: int = texture_layer.call(tex)
			var uv: Array = fd.get("uv", default_uv(dir, f, t))
			var frot := int(fd.get("rotation", 0)) / 90
			var corners := face_corners(dir, f, t)
			var pts: Array = []
			for k in 4:
				var p: Vector3 = corners[k]
				if has_erot:
					p = _rot_point(p, r_axis, r_ang, r_org, r_rescale)
				pts.append(_state_rot(p / 16.0, rx, ry))
			var ndir := dir
			if rx != 0 or ry != 0:
				var nv := _state_rot(DIR_VEC[dir] + Vector3(0.5, 0.5, 0.5), rx, ry) - Vector3(0.5, 0.5, 0.5)
				ndir = dir_of_vec(nv)
			var cull := -1
			if fd.has("cullface"):
				cull = DIR_NAMES.find(str(fd["cullface"]))
				if cull >= 0 and (rx != 0 or ry != 0):
					var cv := _state_rot(DIR_VEC[cull] + Vector3(0.5, 0.5, 0.5), rx, ry) - Vector3(0.5, 0.5, 0.5)
					cull = dir_of_vec(cv)
			var uvs: Array = []
			if uvlock and (rx != 0 or ry != 0):
				# world-aligned projection for the rotated face (Java uvlock semantics)
				var pmin := Vector3(INF, INF, INF)
				var pmax := Vector3(-INF, -INF, -INF)
				for p in pts:
					pmin = pmin.min(p)
					pmax = pmax.max(p)
				var luv := default_uv(ndir, pmin * 16.0, pmax * 16.0)
				var lc := face_corners(ndir, pmin, pmax)
				# map each rotated point to the nearest canonical corner of the new face
				for p in pts:
					var bi := 0
					var bd := INF
					for k in 4:
						var d: float = (p as Vector3).distance_squared_to(lc[k])
						if d < bd:
							bd = d
							bi = k
					var su: float = luv[0] if (bi == 0 or bi == 1) else luv[2]
					var sv: float = luv[1] if (bi == 0 or bi == 3) else luv[3]
					uvs.append(Vector2(su, sv) / 16.0)
			else:
				for k in 4:
					var i := (k + frot) % 4
					var su: float = float(uv[0]) if (i == 0 or i == 1) else float(uv[2])
					var sv: float = float(uv[1]) if (i == 0 or i == 3) else float(uv[3])
					uvs.append(Vector2(su, sv) / 16.0)
			for k in 4:
				var p: Vector3 = pts[k]
				var u: Vector2 = uvs[k]
				quads.append_array([p.x, p.y, p.z, u.x, u.y])
			quads.append(float(layer))
			quads.append(float(int(fd.get("tintindex", -1))))
			quads.append(float(cull))
			quads.append(float(ndir))
			# 26.x cross models (plants) use "shade_direction_override": "up" instead of "shade": false (full brightness)
			var sdo := DIR_NAMES.find(str(e.get("shade_direction_override", "")))
			quads.append(0.0 if not bool(e.get("shade", true)) else (2.0 + sdo if sdo >= 0 else 1.0))
	res["quads"] = quads
	bake_cache[key] = res
	return res


## Classifies a baked quad list as a full cube: returns {} if not a cube, else
## {faces: [6 x [layer, tint, rotflip]], overlays: [6 x [layer, tint] or null]}.
static func analyze_cube(quads: PackedFloat32Array) -> Dictionary:
	var n := quads.size() / QUAD_FLOATS
	if n < 6 or n > 12:
		return {}
	var faces: Array = [null, null, null, null, null, null]
	var overlays: Array = [null, null, null, null, null, null]
	for qi in n:
		var o := qi * QUAD_FLOATS
		var dir := int(quads[o + 23])
		var cull := int(quads[o + 22])
		if cull != dir:
			return {}
		var mn := Vector3(INF, INF, INF)
		var mx := Vector3(-INF, -INF, -INF)
		for k in 4:
			var p := Vector3(quads[o + k * 5], quads[o + k * 5 + 1], quads[o + k * 5 + 2])
			mn = mn.min(p)
			mx = mx.max(p)
		var ext := mx - mn
		var full := false
		match dir:
			0: full = is_equal_approx(mx.y, 0.0) and is_equal_approx(ext.x, 1.0) and is_equal_approx(ext.z, 1.0)
			1: full = is_equal_approx(mn.y, 1.0) and is_equal_approx(ext.x, 1.0) and is_equal_approx(ext.z, 1.0)
			2: full = is_equal_approx(mx.z, 0.0) and is_equal_approx(ext.x, 1.0) and is_equal_approx(ext.y, 1.0)
			3: full = is_equal_approx(mn.z, 1.0) and is_equal_approx(ext.x, 1.0) and is_equal_approx(ext.y, 1.0)
			4: full = is_equal_approx(mx.x, 0.0) and is_equal_approx(ext.z, 1.0) and is_equal_approx(ext.y, 1.0)
			5: full = is_equal_approx(mn.x, 1.0) and is_equal_approx(ext.z, 1.0) and is_equal_approx(ext.y, 1.0)
		if not full:
			return {}
		var rf := uv_rotflip(quads, o)
		if rf < 0:
			return {}
		var entry := [int(quads[o + 20]), int(quads[o + 21]) >= 0, rf]
		if faces[dir] == null:
			faces[dir] = entry
		elif overlays[dir] == null:
			overlays[dir] = entry
		else:
			return {}
	for d in 6:
		if faces[d] == null:
			return {}
	return {"faces": faces, "overlays": overlays}


## Detects which of the 8 rotation/mirror variants of the full [0,1] UV square a quad uses (-1 if partial). The UVs
## are matched to the face's canonical corners by vertex POSITION (face_corners order, as the cube renderers draw
## them): a state-rotated model (x / y rotations: sideways logs, pillars ...) lists its vertices in another order.
static func uv_rotflip(q: PackedFloat32Array, o: int) -> int:
	var corners := face_corners(int(q[o + 23]), Vector3.ZERO, Vector3.ONE)
	var uv: Array = [null, null, null, null]
	for k in 4:
		var u := q[o + k * 5 + 3]
		var v := q[o + k * 5 + 4]
		if not ((is_zero_approx(u) or is_equal_approx(u, 1.0)) and (is_zero_approx(v) or is_equal_approx(v, 1.0))):
			return -1
		var pos := Vector3(q[o + k * 5], q[o + k * 5 + 1], q[o + k * 5 + 2])
		for c in 4:
			if pos.is_equal_approx(corners[c]):
				uv[c] = Vector2(roundf(u), roundf(v))
	for c in 4:
		if uv[c] == null:
			return -1
	for rf in 8:
		var ok := true
		for c in 4:
			if uv[c] != canon_uv(c, rf):
				ok = false
				break
		if ok:
			return rf
	return -1


## Canonical UV corner for vertex k under rotation r (bits 0-1) and horizontal mirror (bit 2).
static func canon_uv(k: int, rf: int) -> Vector2:
	var i := (k + (rf & 3)) % 4
	var u := 0.0 if (i == 0 or i == 1) else 1.0
	var v := 0.0 if (i == 0 or i == 3) else 1.0
	if rf & 4:
		u = 1.0 - u
	return Vector2(u, v)
