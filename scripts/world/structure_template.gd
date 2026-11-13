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
var ents: Array = []             # [Vector3 local pos, entity id, is_baby]


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
static func _load_cached(key: String) -> StructureTemplate:
	var dir := AssetImporter.CACHE_ROOT.path_join(Res.version).path_join("templates")
	var f := dir.path_join(key.replace("/", "__") + ".bin")
	var fp := Res.blocks.st_block.size()
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
			t.ents.append([Vector3(float(ep[0]), float(ep[1]), float(ep[2])), eid, int(enb.get("Age", 0)) < 0])
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
static func rotate_state(blocks: BlockRegistry, st: int, rot: int) -> int:
	if rot == 0 or st <= 0:
		return st
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
func place(f: Features, c: Features.FCtx, origin: Vector3i, rot: int, procs: Array, ignore_air: bool, gravity: bool, cmin: Vector3i, cmax: Vector3i, palette_idx: int = 0) -> void:
	# template entities (villagers, golems, animals): Java addEntitiesToWorld, clipped to the chunk
	for en in ents:
		var lp0: Vector3 = en[0]
		var tp: Vector3
		match rot:
			1:
				tp = Vector3(-lp0.z, lp0.y, lp0.x)
			2:
				tp = Vector3(-lp0.x, lp0.y, -lp0.z)
			3:
				tp = Vector3(lp0.z, lp0.y, -lp0.x)
			_:
				tp = lp0
		var wpos := Vector3(origin) + tp
		if gravity:
			wpos.y = f.height(c, "WORLD_SURFACE_WG", int(floor(wpos.x)), int(floor(wpos.z))) + lp0.y
		if wpos.x >= cmin.x and wpos.x < cmax.x + 1 and wpos.z >= cmin.z and wpos.z < cmax.z + 1:
			c.entities.append({"k": "mob", "id": en[1], "p": [wpos.x, wpos.y, wpos.z], "b": -24000 if en[2] else 0})
	var blocks := f.blocks
	var pal: PackedInt32Array = palettes[clampi(palette_idx, 0, palettes.size() - 1)]
	var jig := blocks.block_id("jigsaw")
	var sblock := blocks.block_id("structure_block")
	var two_pass := _capped_any(procs)
	var final_states: Dictionary = _process_all(f, c, origin, rot, procs, ignore_air, pal, jig, sblock) if two_pass else {}
	for i in bx.size():
		var lp := Vector3i(bx[i], by[i], bz[i])
		var wp := origin + transform(lp, rot)
		if wp.x < cmin.x or wp.x > cmax.x or wp.z < cmin.z or wp.z > cmax.z:
			continue
		if two_pass:
			# two-pass path (capped processors): states decided over the whole template
			if not final_states.has(i):
				continue
			var stf: int = final_states[i]
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
		st = rotate_state(blocks, st, rot)
		if gravity:
			wp.y = f.height(c, "WORLD_SURFACE_WG", wp.x, wp.z) - 1 + lp.y
		if wp.y < f.gen.gen_min_y or wp.y >= f.gen.gen_min_y + f.gen.gen_depth:
			continue
		f.set_block(c, wp, st)
		_block_entity(c, blocks, wp, st, data)


static func _block_entity(c: Features.FCtx, blocks: BlockRegistry, wp: Vector3i, st: int, data) -> void:
	if data is Dictionary and (data as Dictionary).has("LootTable"):
		c.block_entities[wp] = {"id": blocks.name_of(st), "loot_table": str(data["LootTable"]).trim_prefix("minecraft:"), "loot_seed": int(data.get("LootTableSeed", 0))}
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
