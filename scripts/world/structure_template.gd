## StructureTemplate — Java StructureTemplate loaded from the installed jar's data/minecraft/structure/*.nbt:
## size, palette(s), blocks ordered like Java (full cubes, other, block-entity blocks; each sorted by y,x,z),
## jigsaw block infos, rotation transform (StructureTemplate.transform), state rotation, processors (rule,
## block_ignore, block_rot, gravity, protected_blocks, block_age, jigsaw_replacement) and placement into a
## Features write context clipped to one chunk.
## Contract: StructureTemplate.get(id) (shared, thread-safe cache) -> template or null.
class_name StructureTemplate
extends RefCounted

static var _cache: Dictionary = {}
static var _mutex := Mutex.new()

const DIRS := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0), "up": Vector3i(0, 1, 0), "down": Vector3i(0, -1, 0)}
const CW := {"north": "east", "east": "south", "south": "west", "west": "north", "up": "up", "down": "down"}

var id := ""
var size := Vector3i.ONE
var palettes: Array = []          # Array[PackedInt32Array] state ids
var bx := PackedInt32Array()
var by := PackedInt32Array()
var bz := PackedInt32Array()
var bs := PackedInt32Array()      # palette index per block
var nbt: Dictionary = {}          # block index -> nbt Dictionary (block entities, jigsaws)
var jigsaws: Array = []           # [{pos, front, top, name, target, pool, final_state, rollable, sel, place}]
var full_cube := PackedByteArray()
var ents: Array = []             # [Vector3 local pos, entity id, is_baby, villager profession ("" = none given)]


static func get_template(tid: String) -> StructureTemplate:
	var key := tid.trim_prefix("minecraft:")
	_mutex.lock()
	if _cache.has(key):
		var t = _cache[key]
		_mutex.unlock()
		return t
	_mutex.unlock()
	var t2 := _load_cached(key)
	_mutex.lock()
	_cache[key] = t2
	_mutex.unlock()
	return t2


## Parsed templates are cached as native binary in the private asset cache (<cache>/<version>/templates/), keyed by
## the block-state registry size so a registry change invalidates them. Saves the GDScript NBT parse on later runs.
## CACHE_FORMAT: bumped when the cached fields change (2: template villagers carry their profession).
const CACHE_FORMAT := 2
static func _load_cached(key: String) -> StructureTemplate:
	var dir := AssetImporter.CACHE_ROOT.path_join(Res.version).path_join("templates")
	var f := dir.path_join(key.replace("/", "__") + ".bin")
	var fp := Res.blocks.st_block.size() + CACHE_FORMAT * 16777216
	if FileAccess.file_exists(f):
		var v = bytes_to_var(FileAccess.get_file_as_bytes(f))
		if v is Dictionary and int(v.get("fp", -1)) == fp:
			var t := StructureTemplate.new()
			t.id = key
			t.size = v["size"]
			t.palettes = v["palettes"]
			t.bx = v["bx"]
			t.by = v["by"]
			t.bz = v["bz"]
			t.bs = v["bs"]
			t.nbt = v["nbt"]
			t.jigsaws = v["jigsaws"]
			t.full_cube = v["full"]
			t.ents = v["ents"]
			return t
	var t2 := _load(key)
	if t2 != null and Res.mode == "vanilla":
		DirAccess.make_dir_recursive_absolute(dir)
		var fa := FileAccess.open(f, FileAccess.WRITE)
		if fa != null:
			fa.store_buffer(var_to_bytes({"fp": fp, "size": t2.size, "palettes": t2.palettes, "bx": t2.bx, "by": t2.by, "bz": t2.bz, "bs": t2.bs,
				"nbt": t2.nbt, "jigsaws": t2.jigsaws, "full": t2.full_cube, "ents": t2.ents}))
			fa.close()
	return t2


static func _load(key: String) -> StructureTemplate:
	if Res.jar == null:
		return null
	var data := Res.jar.read_bytes("data/minecraft/structure/%s.nbt" % key)
	if data.is_empty():
		return null
	var root := NBT.parse(data)
	if root.is_empty():
		return null
	var t := StructureTemplate.new()
	t.id = key
	var sz: Array = root.get("size", [1, 1, 1])
	t.size = Vector3i(int(sz[0]), int(sz[1]), int(sz[2]))
	var blocks := Res.blocks
	var pal_lists: Array = []
	if root.has("palettes"):
		pal_lists = root["palettes"]
	else:
		pal_lists = [root.get("palette", [])]
	for pl in pal_lists:
		var ids := PackedInt32Array()
		for e in pl:
			# 26.x palettes use {id, properties}; older data {Name, Properties}
			var nm := str(e.get("Name", e.get("id", "minecraft:air")))
			var props: Dictionary = e.get("Properties", e.get("properties", {}))
			var st := blocks.state_of(nm, props)
			if st < 0:
				st = blocks.default_state(nm.trim_prefix("minecraft:"))
			ids.append(maxi(st, 0) if nm != "minecraft:structure_void" else -2)
		t.palettes.append(ids)
	# Java Palette ordering: full cubes, others, block entities — each sorted by (y, x, z)
	var full: Array = []
	var other: Array = []
	var withn: Array = []
	var p0: PackedInt32Array = t.palettes[0] if not t.palettes.is_empty() else PackedInt32Array()
	for e2 in root.get("blocks", []):
		var pos: Array = e2.get("pos", [0, 0, 0])
		var si := int(e2.get("state", 0))
		var rec := [int(pos[1]), int(pos[0]), int(pos[2]), si, e2.get("nbt", null)]
		var st0: int = p0[si] if si < p0.size() else 0
		if rec[4] != null:
			withn.append(rec)
		elif st0 > 0 and (blocks.st_flags[st0] & BlockRegistry.F_FULL_SHAPE) != 0:
			full.append(rec)
		else:
			other.append(rec)
	for en in root.get("entities", []):
		var ep: Array = en.get("pos", [0.5, 0.0, 0.5])
		var enb: Dictionary = en.get("nbt", {})
		var eid := str(enb.get("id", "")).trim_prefix("minecraft:")
		if eid != "":
			# village villagers come as unemployed / nitwit templates (VillagerData.profession)
			var vd = enb.get("VillagerData", {})
			var vprof := str((vd as Dictionary).get("profession", "")).trim_prefix("minecraft:") if vd is Dictionary else ""
			t.ents.append([Vector3(float(ep[0]), float(ep[1]), float(ep[2])), eid, int(enb.get("Age", 0)) < 0, vprof])
	# (y, x, z) order via native sorts of packed keys (sort_custom with a lambda was the template-load hot spot)
	var all: Array = _sorted_yxz(full) + _sorted_yxz(other) + _sorted_yxz(withn)
	var n_full := full.size()
	for i in all.size():
		var r: Array = all[i]
		t.by.append(r[0])
		t.bx.append(r[1])
		t.bz.append(r[2])
		t.bs.append(r[3])
		t.full_cube.append(1 if i < n_full else 0)
		if r[4] != null:
			t.nbt[i] = r[4]
			var st1: int = p0[r[3]] if r[3] < p0.size() else 0
			if st1 > 0 and blocks.name_of(st1) == "jigsaw":
				var ori := blocks.get_prop(st1, "orientation")
				var parts := ori.split("_")
				var d: Dictionary = r[4]
				var front := parts[0] if parts.size() > 0 else "north"
				var joint := str(d.get("joint", ""))
				var rollable := joint == "rollable" if joint != "" else (front != "up" and front != "down")
				t.jigsaws.append({"pos": Vector3i(r[1], r[0], r[2]), "front": front, "top": parts[1] if parts.size() > 1 else "up",
					"name": str(d.get("name", "minecraft:empty")), "target": str(d.get("target", "minecraft:empty")),
					"pool": str(d.get("pool", "minecraft:empty")), "final_state": str(d.get("final_state", "minecraft:air")),
					"rollable": rollable, "sel": int(d.get("selection_priority", 0)), "place": int(d.get("placement_priority", 0))})
	return t


static func _sorted_yxz(recs: Array) -> Array:
	var keys := PackedInt64Array()
	keys.resize(recs.size())
	for i in recs.size():
		var r: Array = recs[i]
		keys[i] = ((((int(r[0]) + 512) * 1024 + int(r[1]) + 512) * 1024 + int(r[2]) + 512) << 24) | i
	keys.sort()
	var out: Array = []
	out.resize(recs.size())
	for i in keys.size():
		out[i] = recs[keys[i] & 0xFFFFFF]
	return out


# ------------------------------------------------------------------ transforms (Java Rotation: 0 none, 1 cw90, 2 cw180, 3 ccw90)

static func transform(p: Vector3i, rot: int, pivot: Vector3i = Vector3i.ZERO) -> Vector3i:
	var l := pivot.x
	var m := pivot.z
	match rot:
		3:
			return Vector3i(l - m + p.z, p.y, l + m - p.x)
		1:
			return Vector3i(l + m - p.z, p.y, m - l + p.x)
		2:
			return Vector3i(l + l - p.x, p.y, m + m - p.z)
	return p


## Java StructureTemplate.transform with a Mirror (1 FRONT_BACK: x negated, 2 LEFT_RIGHT: z negated) applied before
## the rotation about the pivot.
static func transform_m(p: Vector3i, rot: int, mirror: int, pivot: Vector3i) -> Vector3i:
	if mirror == 1:
		p = Vector3i(-p.x, p.y, p.z)
	elif mirror == 2:
		p = Vector3i(p.x, p.y, -p.z)
	return transform(p, rot, pivot)


## Java StructureTemplate.transform(Vec3, Mirror, Rotation, pivot) for entity positions: a block spans [x, x + 1], so
## mirroring and turning a continuous position adds 1 where Java does (a rotated cage keeps its allays inside).
static func transform_vec(p: Vector3, rot: int, mirror: int, pivot: Vector3i) -> Vector3:
	var d := p.x
	var e := p.y
	var f := p.z
	var mirrored := true
	if mirror == 2:
		f = 1.0 - f
	elif mirror == 1:
		d = 1.0 - d
	else:
		mirrored = false
	var i := float(pivot.x)
	var j := float(pivot.z)
	match rot:
		3:
			return Vector3(i - j + f, e, i + j + 1.0 - d)
		1:
			return Vector3(i + j + 1.0 - f, e, j - i + d)
		2:
			return Vector3(i + i + 1.0 - d, e, j + j + 1.0 - f)
	return Vector3(d, e, f) if mirrored else p


## Java StructureTemplate.getBoundingBox(pos, rotation, pivot, mirror): [min, max] inclusive.
func box_m(origin: Vector3i, rot: int, mirror: int, pivot: Vector3i) -> Array:
	var a := transform_m(Vector3i.ZERO, rot, mirror, pivot)
	var b := transform_m(size - Vector3i.ONE, rot, mirror, pivot)
	return [origin + Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z)), origin + Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))]


const MIRROR_X := {"east": "west", "west": "east"}
const MIRROR_Z := {"north": "south", "south": "north"}


## BlockState.mirror for the properties structure blocks use; mode 1 Mirror.FRONT_BACK (x), 2 LEFT_RIGHT (z): facings
## along the mirrored axis flip, the matching connection pair swaps, 16-step rotations reflect, chest halves swap, door
## hinges swap (DoorBlock.mirror cycles the hinge); stairs facing along the axis turn round with their inner / outer
## side swapped (StairBlock.mirror).
static func mirror_state(blocks: BlockRegistry, st: int, mode: int = 1) -> int:
	if st <= 0 or mode == 0:
		return st
	var key := st * 8 + 3 + mode
	_xf_mutex.lock()
	var hit = _xf_cache.get(key)
	_xf_mutex.unlock()
	if hit != null:
		return hit
	var r := _mirror_state(blocks, st, mode)
	_xf_mutex.lock()
	_xf_cache[key] = r
	_xf_mutex.unlock()
	return r


static func _mirror_state(blocks: BlockRegistry, st: int, mode: int) -> int:
	var out := st
	var flip: Dictionary = MIRROR_X if mode == 1 else MIRROR_Z
	var f := blocks.get_prop(st, "facing")
	if flip.has(f):
		out = blocks.with_prop(out, "facing", flip[f])
		var sh := blocks.get_prop(st, "shape")
		if sh.begins_with("inner_") or sh.begins_with("outer_"):
			out = blocks.with_prop(out, "shape", sh.replace("left", "#").replace("right", "left").replace("#", "right"))
	var pa := "east" if mode == 1 else "north"
	var pb := "west" if mode == 1 else "south"
	if blocks.has_prop(st, pa) and blocks.has_prop(st, pb):
		out = blocks.with_prop(blocks.with_prop(out, pa, blocks.get_prop(st, pb)), pb, blocks.get_prop(st, pa))
	var r := blocks.get_prop(st, "rotation")
	if r != "":
		var j := int(r)
		j = j - 16 if j > 8 else j
		# Mirror.mirror(rotation, 16): FRONT_BACK (16 - j) % 16, LEFT_RIGHT (8 - j + 16) % 16
		out = blocks.with_prop(out, "rotation", str((16 - j) % 16 if mode == 1 else (8 - j + 16) % 16))
	var hg := blocks.get_prop(st, "hinge")
	if hg == "left" or hg == "right":
		out = blocks.with_prop(out, "hinge", "right" if hg == "left" else "left")
	var ty := blocks.get_prop(st, "type")
	if (ty == "left" or ty == "right") and (blocks.name_of(st).ends_with("chest")):
		out = blocks.with_prop(out, "type", "right" if ty == "left" else "left")
	return out


static func rot_dir(d: String, rot: int) -> String:
	var r := d
	for i in rot:
		r = CW.get(r, r)
	return r


## Bounding box [min, max] (inclusive) of the template placed at `origin` with rotation.
func box(origin: Vector3i, rot: int) -> Array:
	var a := transform(Vector3i.ZERO, rot)
	var b := transform(size - Vector3i.ONE, rot)
	return [origin + Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z)), origin + Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))]


## Jigsaw infos in Java order (shuffled by the caller), world positions and rotated facings.
func jigsaws_at(origin: Vector3i, rot: int) -> Array:
	var out: Array = []
	for j in jigsaws:
		var e: Dictionary = j.duplicate()
		e["pos"] = origin + transform(j["pos"], rot)
		e["front"] = rot_dir(j["front"], rot)
		e["top"] = rot_dir(j["top"], rot)
		out.append(e)
	return out


## BlockState.rotate for the properties used by structure blocks.
## rotate_state / mirror_state results by (state, rotation): pure functions of the state, looked up for every block
## of every placed template (property-string work per call); shared by the worker threads under a mutex.
static var _xf_cache: Dictionary = {}
static var _xf_mutex := Mutex.new()


static func rotate_state(blocks: BlockRegistry, st: int, rot: int) -> int:
	if rot == 0 or st <= 0:
		return st
	var key := st * 8 + rot
	_xf_mutex.lock()
	var hit = _xf_cache.get(key)
	_xf_mutex.unlock()
	if hit != null:
		return hit
	var r := _rotate_state(blocks, st, rot)
	_xf_mutex.lock()
	_xf_cache[key] = r
	_xf_mutex.unlock()
	return r


static func _rotate_state(blocks: BlockRegistry, st: int, rot: int) -> int:
	var out := st
	var f := blocks.get_prop(st, "facing")
	if f != "" and f != "up" and f != "down":
		out = blocks.with_prop(out, "facing", rot_dir(f, rot))
	var ax := blocks.get_prop(st, "axis")
	if ax != "" and rot % 2 == 1:
		if ax == "x":
			out = blocks.with_prop(out, "axis", "z")
		elif ax == "z":
			out = blocks.with_prop(out, "axis", "x")
	var r := blocks.get_prop(st, "rotation")
	if r != "":
		out = blocks.with_prop(out, "rotation", str((int(r) + rot * 4) % 16))
	if blocks.has_prop(st, "north") and blocks.has_prop(st, "east"):
		var vals := {}
		for d in ["north", "east", "south", "west"]:
			vals[rot_dir(d, rot)] = blocks.get_prop(st, d)
		for d in vals:
			out = blocks.with_prop(out, d, vals[d])
	var ori := blocks.get_prop(st, "orientation")
	if ori != "":
		var ps := ori.split("_")
		if ps.size() == 2:
			out = blocks.with_prop(out, "orientation", rot_dir(ps[0], rot) + "_" + rot_dir(ps[1], rot))
	var shape := blocks.get_prop(st, "shape")
	if shape.contains("_") and (shape.begins_with("north") or shape.begins_with("east") or shape.begins_with("south") or shape.begins_with("west") or shape.begins_with("ascending")):
		out = blocks.with_prop(out, "shape", _rot_rail(shape, rot))
	return out


static func _rot_rail(shape: String, rot: int) -> String:
	if shape.begins_with("ascending_"):
		return "ascending_" + rot_dir(shape.substr(10), rot)
	var ps := shape.split("_")
	if ps.size() != 2:
		return shape
	var a := rot_dir(ps[0], rot)
	var b := rot_dir(ps[1], rot)
	var order := ["north", "south", "east", "west"]
	if a in ["north", "south"] and b in ["north", "south"]:
		return "north_south"
	if a in ["east", "west"] and b in ["east", "west"]:
		return "east_west"
	if order.find(a) > order.find(b):
		var t := a
		a = b
		b = t
	if a == "east" or a == "west":
		var t2 := a
		a = b
		b = t2
	return a + "_" + b


# ------------------------------------------------------------------ placement

## Place into chunk-clipped writes. procs: compiled processor list (Structures.compile_processors).
## ignore_air: legacy elements / STRUCTURE_AND_AIR. gravity: terrain_matching projection (offset -1).
func place(f: Features, c: Features.FCtx, origin: Vector3i, rot: int, procs: Array, ignore_air: bool, gravity: bool, cmin: Vector3i, cmax: Vector3i, palette_idx: int = 0, mirror: int = 0, pivot: Vector3i = Vector3i.ZERO, markers: String = "", entities: bool = true) -> void:
	var xf := mirror != 0 or pivot != Vector3i.ZERO
	var marks: Array = []   # DATA structure blocks: [world pos, metadata] (TemplateStructurePiece.handleDataMarker)
	# template entities (villagers, golems, animals): Java addEntitiesToWorld, clipped to the chunk
	for en in (ents if entities else []):
		var lp0: Vector3 = en[0]
		var tp := transform_vec(lp0, rot, mirror, pivot)
		var wpos := Vector3(origin) + tp
		if gravity:
			wpos.y = f.height(c, "WORLD_SURFACE_WG", int(floor(wpos.x)), int(floor(wpos.z))) + lp0.y
		if wpos.x >= cmin.x and wpos.x < cmax.x + 1 and wpos.z >= cmin.z and wpos.z < cmax.z + 1:
			var ed := {"k": "mob", "id": en[1], "p": [wpos.x, wpos.y, wpos.z], "b": -24000 if en[2] else 0}
			if en.size() > 3 and str(en[3]) != "":
				ed["vp"] = str(en[3])   # (EntityManager._deser: the villager's profession)
			c.entities.append(ed)
	var blocks := f.blocks
	var pal: PackedInt32Array = palettes[clampi(palette_idx, 0, palettes.size() - 1)]
	var jig := blocks.block_id("jigsaw")
	var sblock := blocks.block_id("structure_block")
	var two_pass := _capped_any(procs)
	var final_states: Dictionary = _process_all(f, c, origin, rot, procs, ignore_air, pal, jig, sblock) if two_pass else {}
	for i in bx.size():
		var lp := Vector3i(bx[i], by[i], bz[i])
		var wp := origin + (transform_m(lp, rot, mirror, pivot) if xf else transform(lp, rot))
		if wp.x < cmin.x or wp.x > cmax.x or wp.z < cmin.z or wp.z > cmax.z:
			continue
		if two_pass:
			# two-pass path (capped processors): states decided over the whole template
			if not final_states.has(i):
				continue
			var stf: int = final_states[i]
			if mirror != 0:
				stf = mirror_state(blocks, stf, mirror)
			stf = rotate_state(blocks, stf, rot)
			if gravity:
				wp.y = f.height(c, "WORLD_SURFACE_WG", wp.x, wp.z) - 1 + lp.y
			if wp.y < f.gen.gen_min_y or wp.y >= f.gen.gen_min_y + f.gen.gen_depth:
				continue
			f.set_block(c, wp, stf)
			_block_entity(c, blocks, wp, stf, nbt.get(i))
			continue
		var st: int = pal[bs[i]] if bs[i] < pal.size() else 0
		if st == -2:
			continue   # structure_void
		var bid := blocks.st_block[st] if st > 0 else 0
		if bid == sblock:
			if markers != "":
				var md = nbt.get(i)
				if md is Dictionary and str(md.get("mode", "")).to_upper() == "DATA":
					marks.append([wp, str(md.get("metadata", ""))])
			continue
		var data = nbt.get(i)
		if bid == jig and st > 0:
			# JigsawReplacementProcessor: final_state from nbt (default air)
			var fs := str((data as Dictionary).get("final_state", "minecraft:air")) if data is Dictionary else "minecraft:air"
			if fs.trim_prefix("minecraft:").begins_with("structure_void"):
				continue   # Java JigsawReplacementProcessor: a structure_void final state places nothing
			st = blocks.parse_state(fs)
			if st < 0:
				st = 0
			data = null
			if st == 0 and ignore_air:
				continue
		elif st == 0 and ignore_air:
			continue
		# Java order: processors see the unrotated state at the pre-gravity world position, then rotate
		var ok := true
		for pr in procs:
			st = Structures.process(f, c, pr, st, wp, lp)
			if st < -1:
				ok = false
				break
		if not ok or st < 0:
			continue
		if mirror != 0:
			st = mirror_state(blocks, st, mirror)
		st = rotate_state(blocks, st, rot)
		if gravity:
			wp.y = f.height(c, "WORLD_SURFACE_WG", wp.x, wp.z) - 1 + lp.y
		if wp.y < f.gen.gen_min_y or wp.y >= f.gen.gen_min_y + f.gen.gen_depth:
			continue
		f.set_block(c, wp, st)
		_block_entity(c, blocks, wp, st, data)
	for mk in marks:
		_data_marker(f, c, markers, str(mk[1]), mk[0], rot, cmin, cmax)


## Java handleDataMarker of the template pieces: igloo / shipwreck / ocean ruin chests get their loot tables, ocean
## ruin drowned, end city chests (loot below the marker), sentries (shulkers) and the ship's elytra item frame.
static func _data_marker(f: Features, c: Features.FCtx, kind: String, name: String, wp: Vector3i, rot: int, cmin: Vector3i, cmax: Vector3i) -> void:
	var inside := func(q: Vector3i) -> bool: return q.x >= cmin.x and q.x <= cmax.x and q.z >= cmin.z and q.z <= cmax.z
	var b := f.blocks
	var seed: int = c.r.next_long() if c.r != null else 0
	var below := wp + Vector3i(0, -1, 0)
	match kind:
		"igloo":
			if name == "chest" and inside.call(wp):
				f.set_block(c, wp, 0)
				if b.name_of(maxi(0, f.get_block(c, below))) == "chest":
					c.block_entities[below] = {"id": "chest", "loot_table": "chests/igloo_chest", "loot_seed": seed}
		"shipwreck":
			var tables := {"map_chest": "chests/shipwreck_map", "treasure_chest": "chests/shipwreck_treasure", "supply_chest": "chests/shipwreck_supply"}
			if tables.has(name) and inside.call(below):
				c.block_entities[below] = {"id": "chest", "loot_table": tables[name], "loot_seed": seed}
		"ocean_ruin_big", "ocean_ruin_small":
			if not inside.call(wp):
				return
			var cur := f.get_block(c, wp)
			var wet: bool = cur > 0 and ((b.st_flags[cur] & BlockRegistry.F_WATERLOGGED) != 0 or b.name_of(cur) == "water")
			if name == "chest":
				f.set_block(c, wp, b.with_prop(b.default_state("chest"), "waterlogged", "true" if wet else "false"))
				c.block_entities[wp] = {"id": "chest", "loot_table": "chests/underwater_ruin_big" if kind == "ocean_ruin_big" else "chests/underwater_ruin_small", "loot_seed": seed}
			elif name == "drowned":
				c.entities.append({"k": "mob", "id": "drowned", "p": [wp.x + 0.5, wp.y, wp.z + 0.5], "b": 0, "pers": true})
				f.set_block(c, wp, 0 if wp.y > f.gen.sea_level else b.WATER)
		"woodland_mansion":
			# WoodlandMansionPiece.handleDataMarker
			if not inside.call(wp):
				return
			if name.begins_with("Chest"):
				var face := "north"   # plain "Chest": the chest's default state
				match name:
					"ChestWest":
						face = rot_dir("west", rot)
					"ChestEast":
						face = rot_dir("east", rot)
					"ChestSouth":
						face = rot_dir("south", rot)
					"ChestNorth":
						face = rot_dir("north", rot)
				if b.name_of(maxi(0, f.get_block(c, wp))) == "chest":
					return
				f.set_block(c, wp, b.with_prop(b.default_state("chest"), "facing", face))
				c.block_entities[wp] = {"id": "chest", "loot_table": "chests/woodland_mansion", "loot_seed": seed}
			else:
				var mobs: Array = []
				match name:
					"Mage":
						mobs = ["evoker"]
					"Warrior":
						mobs = ["vindicator"]
					"Group of Allays":
						for k in (c.r.next_int_bound(3) if c.r != null else 0) + 1:
							mobs.append("allay")
					_:
						return
				for id in mobs:
					c.entities.append({"k": "mob", "id": id, "p": [wp.x + 0.5, wp.y, wp.z + 0.5], "b": 0, "pers": true})
				f.set_block(c, wp, 0)
		"end_city":
			if name.begins_with("Chest"):
				if inside.call(below):
					c.block_entities[below] = {"id": b.name_of(maxi(0, f.get_block(c, below))), "loot_table": "chests/end_city_treasure", "loot_seed": seed}
			elif inside.call(wp):
				if name.begins_with("Sentry"):
					c.entities.append({"k": "mob", "id": "shulker", "p": [wp.x + 0.5, wp.y, wp.z + 0.5], "b": 0, "pers": true})
				elif name.begins_with("Elytra"):
					# ItemFrame(pos, rotation.rotate(SOUTH)) holding an elytra
					var face: String = rot_dir("south", rot)
					var nv: Vector3i = {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0)}[face]
					var fp := Vector3(wp) + Vector3(0.5, 0.125, 0.5) - Vector3(nv) * (0.5 - 1.0 / 32.0)
					c.entities.append({"k": "frame", "id": "item_frame", "p": [fp.x, fp.y, fp.z], "y": 0.0, "d": {"n": [nv.x, nv.y, nv.z], "rot": 0}, "s": ItemStack.named("elytra", 1).to_dict()})


## Java StructureTemplate.placeInWorld: a placed block with block entity data that is a RandomizableContainer (chests,
## barrels, shulker boxes, dispensers, droppers, hoppers, crafters, decorated pots) gets LootTableSeed = random.nextLong()
## from the structure's per-chunk random - consumed even without a loot table, so later pieces' features (snow / ice
## piles, hay) draw the same numbers as Java.
static func _random_container(n: String) -> bool:
	return (n.ends_with("chest") and n != "ender_chest") or n == "barrel" or n.ends_with("shulker_box") or n in ["dispenser", "dropper", "hopper", "crafter", "decorated_pot"]


static func _block_entity(c: Features.FCtx, blocks: BlockRegistry, wp: Vector3i, st: int, data) -> void:
	var seed := 0
	if data is Dictionary and st > 0 and c.r != null and _random_container(blocks.name_of(st)):
		seed = c.r.next_long()
	if data is Dictionary and (data as Dictionary).has("LootTable"):
		c.block_entities[wp] = {"id": blocks.name_of(st), "loot_table": str(data["LootTable"]).trim_prefix("minecraft:"), "loot_seed": seed if seed != 0 else int(data.get("LootTableSeed", 0))}
	elif data is Dictionary and (data as Dictionary).has("normal_config"):
		c.block_entities[wp] = {"id": "trial_spawner", "normal": str(data["normal_config"]), "ominous": str(data.get("ominous_config", ""))}
	elif data is Dictionary and str(data.get("id", "")) == "minecraft:vault":
		c.block_entities[wp] = {"id": "vault", "config": data.get("config", {})}
	elif data is Dictionary and data.get("SpawnData") is Dictionary:
		var sent = (data["SpawnData"] as Dictionary).get("entity", {})
		c.block_entities[wp] = {"id": "spawner", "mob": str(sent.get("id", "minecraft:pig")).trim_prefix("minecraft:") if sent is Dictionary else "pig"}


static func _capped_any(procs: Array) -> bool:
	for pr in procs:
		if str(pr["t"]) == "capped":
			return true
	return false


## Java StructureTemplate.processBlockInfos + CappedProcessor.finalizeProcessing over the WHOLE template (every chunk
## computes the same result): per-block processors in order, then each capped processor applies its delegate to up to
## limit blocks of the processed list in Util.shuffle order (random = settings.getRandom(pos): LegacyRandom of the
## template position's seed), counting only blocks it changed. Returns block index -> state (skipped blocks absent).
func _process_all(f: Features, c: Features.FCtx, origin: Vector3i, rot: int, procs: Array, ignore_air: bool, pal: PackedInt32Array, jig: int, sblock: int) -> Dictionary:
	var blocks := f.blocks
	var idx := PackedInt32Array()
	var sts := PackedInt32Array()
	var wps: Array = []
	for i in bx.size():
		var lp := Vector3i(bx[i], by[i], bz[i])
		var wp := origin + transform(lp, rot)
		var st: int = pal[bs[i]] if bs[i] < pal.size() else 0
		if st == -2:
			continue
		var bid := blocks.st_block[st] if st > 0 else 0
		if bid == sblock:
			continue
		var data = nbt.get(i)
		if bid == jig and st > 0:
			var fs := str((data as Dictionary).get("final_state", "minecraft:air")) if data is Dictionary else "minecraft:air"
			if fs.trim_prefix("minecraft:").begins_with("structure_void"):
				continue
			st = maxi(blocks.parse_state(fs), 0)
		if st == 0 and ignore_air:
			continue
		var ok := true
		for pr in procs:
			if str(pr["t"]) == "capped":
				continue
			st = Structures.process(f, c, pr, st, wp, lp)
			if st < 0:
				ok = false
				break
		if not ok:
			continue
		idx.append(i)
		sts.append(st)
		wps.append(wp)
	for pr in procs:
		if str(pr["t"]) != "capped" or idx.is_empty():
			continue
		var r := RandomSources.LegacyRandom.new(RandomSources.pos_seed(origin.x, origin.y, origin.z))
		var lim = pr["limit"]
		var limit := 1
		if lim is Dictionary:
			var lo := int(lim.get("min_inclusive", 0))
			limit = lo + r.next_int_bound(maxi(1, int(lim.get("max_inclusive", lo)) - lo + 1))
		else:
			limit = int(lim)
		var j := mini(limit, idx.size())
		if j < 1:
			continue
		var order: Array = range(idx.size())
		for k in range(order.size(), 1, -1):
			var sw := r.next_int_bound(k)
			var tmp = order[k - 1]
			order[k - 1] = order[sw]
			order[sw] = tmp
		var done := 0
		for l in order:
			if done >= j:
				break
			var ns := Structures.process(f, c, pr["delegate"], sts[l], wps[l], Vector3i.ZERO)
			if ns >= 0 and ns != sts[l]:
				sts[l] = ns
				done += 1
	var out := {}
	for k in idx.size():
		out[idx[k]] = sts[k]
	return out
