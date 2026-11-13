## JavaPieces — Java StructurePiece machinery + the hand-coded scattered features, run per chunk while the chunk's
## features are placed (Java StructureStart.placeInChunk -> piece.postProcess with the chunk's box):
## orientation transforms (getWorldX / Y / Z, the state mirror + rotation of setOrientation), generateBox (plain and
## with a BlockSelector), generateAirBox, placeBlock, fillColumnDown, createChest (reorient), createDispenser.
## Pieces: SwampHutPiece, JungleTemplePiece, DesertPyramidPiece (classic body + hidden chamber + the 1.20 cellar; its
## suspicious sand is placed by Structures._pyramid_after). The piece's ground height (updateAverageGroundHeight / the lowest ground
## for the pyramid) is computed once from the noise heights over the whole box when the start is built: Java uses the
## first chunk to place it, which this parallel generator cannot know.
class_name JavaPieces
extends RefCounted

const DIRS := ["north", "east", "south", "west"]   # Direction.Plane.HORIZONTAL order


class P:
	var f: Features
	var c: Features.FCtx
	var r
	var b: BlockRegistry
	var bmin: Vector3i
	var bmax: Vector3i
	var oi := 0   # 0 north, 1 east, 2 south, 3 west, 4 none (absolute)
	var _ocache: Dictionary = {}   # state -> oriented state
	var ori := "north":
		set(v):
			ori = v
			oi = {"north": 0, "east": 1, "south": 2, "west": 3}.get(v, 4)
			_ocache = {}
	var cmin: Vector3i
	var cmax: Vector3i
	var keep_ids: Dictionary = {}   # MineShaftPiece.canBeReplaced: block ids never overwritten
	var floor_h: Dictionary = {}    # OCEAN_FLOOR_WG height per column (isInterior), memoised for this placement
	var repl_ids: Dictionary = {}   # isReplaceableByStructures extras (glow lichen, seagrass, tall seagrass)

	# orientation "" = Java null: absolute coordinates, no state transform
	func wx(x: int, z: int) -> int:
		match oi:
			3:
				return bmax.x - z
			1:
				return bmin.x + z
			4:
				return x
		return bmin.x + x

	func wy(y: int) -> int:
		return y if oi == 4 else bmin.y + y

	func wz(x: int, z: int) -> int:
		match oi:
			0:
				return bmax.z - z
			2:
				return bmin.z + z
			4:
				return z
		return bmin.z + x

	func wpos(x: int, y: int, z: int) -> Vector3i:
		match oi:
			0:
				return Vector3i(bmin.x + x, bmin.y + y, bmax.z - z)
			2:
				return Vector3i(bmin.x + x, bmin.y + y, bmin.z + z)
			3:
				return Vector3i(bmax.x - z, bmin.y + y, bmin.z + x)
			1:
				return Vector3i(bmin.x + z, bmin.y + y, bmin.z + x)
		return Vector3i(x, y, z)

	func inside(p: Vector3i) -> bool:
		return p.x >= cmin.x and p.x <= cmax.x and p.z >= cmin.z and p.z <= cmax.z and p.y >= cmin.y and p.y <= cmax.y

	## StructurePiece.setOrientation: SOUTH mirror LEFT_RIGHT; WEST mirror LEFT_RIGHT + CW90; EAST CW90.
	func orient(st: int) -> int:
		if st <= 0 or oi == 0 or oi == 4:
			return st
		var hit = _ocache.get(st)
		if hit != null:
			return hit
		var out := st
		if oi == 2 or oi == 3:
			out = JavaPieces.mirror_z(b, out)
		if oi == 3 or oi == 1:
			out = StructureTemplate.rotate_state(b, out, 1)
		_ocache[st] = out
		return out

	func place(st: int, x: int, y: int, z: int) -> void:
		var p := wpos(x, y, z)
		if inside(p):
			if not keep_ids.is_empty():
				var cur := f.get_block(c, p)
				if cur > 0 and keep_ids.has(b.st_block[cur]):
					return
			var os := orient(st)
			f.set_block(c, p, os)
			if os > 0 and JavaPieces.shape_check(b, os):
				c.postproc.append_array([p.x, p.y, p.z])

	## BlockState.isAir (air, cave air, void air); outside the chunk reads as air (StructurePiece.getBlock).
	var _cave_air := -2
	var _void_air := -2

	func is_air_at(x: int, y: int, z: int) -> bool:
		var st := get_at(x, y, z)
		if st <= 0:
			return true
		if _cave_air == -2:
			_cave_air = b.default_state("cave_air")
			_void_air = b.default_state("void_air")
		return st == _cave_air or st == _void_air

	func get_at(x: int, y: int, z: int) -> int:
		var p := wpos(x, y, z)
		return f.get_block(c, p) if inside(p) else 0

	## The part of a local box inside this chunk (local coordinates [x0, y0, z0, x1, y1, z1]), [] when none.
	func clip(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> Array:
		var ax0 := x0
		var ax1 := x1
		var az0 := z0
		var az1 := z1
		match oi:
			0:
				ax0 = maxi(x0, cmin.x - bmin.x)
				ax1 = mini(x1, cmax.x - bmin.x)
				az0 = maxi(z0, bmax.z - cmax.z)
				az1 = mini(z1, bmax.z - cmin.z)
			2:
				ax0 = maxi(x0, cmin.x - bmin.x)
				ax1 = mini(x1, cmax.x - bmin.x)
				az0 = maxi(z0, cmin.z - bmin.z)
				az1 = mini(z1, cmax.z - bmin.z)
			3:
				az0 = maxi(z0, bmax.x - cmax.x)
				az1 = mini(z1, bmax.x - cmin.x)
				ax0 = maxi(x0, cmin.z - bmin.z)
				ax1 = mini(x1, cmax.z - bmin.z)
			1:
				az0 = maxi(z0, cmin.x - bmin.x)
				az1 = mini(z1, cmax.x - bmin.x)
				ax0 = maxi(x0, cmin.z - bmin.z)
				ax1 = mini(x1, cmax.z - bmin.z)
			4:
				ax0 = maxi(x0, cmin.x)
				ax1 = mini(x1, cmax.x)
				az0 = maxi(z0, cmin.z)
				az1 = mini(z1, cmax.z)
		var oy := 0 if oi == 4 else bmin.y
		var ay0 := maxi(y0, cmin.y - oy)
		var ay1 := mini(y1, cmax.y - oy)
		if ax0 > ax1 or az0 > az1 or ay0 > ay1:
			return []
		return [ax0, ay0, az0, ax1, ay1, az1]

	func box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, edge: int, inner: int, existing_only := false) -> void:
		var cl := clip(x0, y0, z0, x1, y1, z1)
		if cl.is_empty():
			return
		for y in range(cl[1], cl[4] + 1):
			for x in range(cl[0], cl[3] + 1):
				for z in range(cl[2], cl[5] + 1):
					if existing_only and is_air_at(x, y, z):
						continue
					var e := y == y0 or y == y1 or x == x0 or x == x1 or z == z0 or z == z1
					place(edge if e else inner, x, y, z)

	## generateBox with a BlockSelector (sel.call(random, x, y, z, wall) -> state), random drawn per position.
	func box_sel(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, always_replace: bool, sel: Callable) -> void:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				for z in range(z0, z1 + 1):
					if always_replace and is_air_at(x, y, z):
						continue
					var e := y == y0 or y == y1 or x == x0 or x == x1 or z == z0 or z == z1
					place(sel.call(e), x, y, z)

	func air(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> void:
		var cl := clip(x0, y0, z0, x1, y1, z1)
		if cl.is_empty():
			return
		for y in range(cl[1], cl[4] + 1):
			for x in range(cl[0], cl[3] + 1):
				for z in range(cl[2], cl[5] + 1):
					place(0, x, y, z)

	## fillColumnDown: from (x, y, z) down while the block is air / liquid / glow lichen / seagrass (state unrotated).
	func column_down(st: int, x: int, y: int, z: int) -> void:
		var p := wpos(x, y, z)
		if not inside(p):
			return
		while p.y > f.gen.gen_min_y + 1:
			var cur := f.get_block(c, p)
			if not (cur <= 0 or (b.st_flags[cur] & BlockRegistry.F_LIQUID) != 0 or b.name_of(cur) in ["glow_lichen", "seagrass", "tall_seagrass"]):
				break
			f.set_block(c, p, st)
			p.y -= 1

	func _solid_render(st: int) -> bool:
		return st > 0 and (b.st_flags[st] & BlockRegistry.F_FULL_SHAPE) != 0 and (b.st_flags[st] & (BlockRegistry.F_CUTOUT | BlockRegistry.F_TRANSLUCENT)) == 0

	## createChest with StructurePiece.reorient (face away from the one solid side, else turn off walls).
	func chest(x: int, y: int, z: int, loot: String) -> void:
		var p := wpos(x, y, z)
		if not inside(p) or b.name_of(maxi(0, f.get_block(c, p))) == "chest":
			return
		var dirv := {"north": Vector3i(0, 0, -1), "east": Vector3i(1, 0, 0), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0)}
		var opp := {"north": "south", "south": "north", "east": "west", "west": "east"}
		var cw := {"north": "east", "east": "south", "south": "west", "west": "north"}
		var facing := ""
		var keep := false
		for d in JavaPieces.DIRS:
			var s := f.get_block(c, p + dirv[d])
			if b.name_of(maxi(0, s)) == "chest":
				keep = true
				break
			if _solid_render(s):
				if facing != "":
					facing = ""
					break
				facing = d
		var fc := "north"
		if keep:
			fc = "north"
		elif facing != "":
			fc = opp[facing]
		else:
			if _solid_render(f.get_block(c, p + dirv[fc])):
				fc = opp[fc]
			if _solid_render(f.get_block(c, p + dirv[fc])):
				fc = cw[fc]
			if _solid_render(f.get_block(c, p + dirv[fc])):
				fc = opp[fc]
		f.set_block(c, p, b.with_prop(b.default_state("chest"), "facing", fc))
		c.block_entities[p] = {"id": "chest", "loot_table": loot, "loot_seed": int(r.next_long()) if r.has_method("next_long") else 0}

	func dispenser(x: int, y: int, z: int, facing: String, loot: String) -> void:
		var p := wpos(x, y, z)
		if not inside(p) or b.name_of(maxi(0, f.get_block(c, p))) == "dispenser":
			return
		place(b.with_prop(b.default_state("dispenser"), "facing", facing), x, y, z)
		c.block_entities[p] = {"id": "dispenser", "loot_table": loot, "loot_seed": int(r.next_long()) if r.has_method("next_long") else 0}

	func s(name: String) -> int:
		return b.default_state(name)

	func sp(name: String, props: Dictionary) -> int:
		var st := b.default_state(name)
		for k in props:
			st = b.with_prop(st, k, str(props[k]))
		return st


## StructurePiece.SHAPE_CHECK_BLOCKS: fences of the classic woods, the nether brick fence, iron bars (torches and
## ladders are in the Java set too; they never change shape where pieces put them).
static var _shape_ids: Dictionary = {}


static func shape_check(b: BlockRegistry, st: int) -> bool:
	if _shape_ids.is_empty():
		var d := {-1: true}
		for nm in ["nether_brick_fence", "oak_fence", "spruce_fence", "dark_oak_fence", "acacia_fence", "birch_fence", "jungle_fence", "iron_bars"]:
			d[b.block_id(nm)] = true
		_shape_ids = d
	return _shape_ids.has(b.st_block[st])


## BlockState.mirror(Mirror.LEFT_RIGHT): z-axis facings flip, north / south connections swap, 16-step rotations reflect,
## z-facing stairs turn round with inner / outer sides swapped (StairBlock.mirror).
static func mirror_z(b: BlockRegistry, st: int) -> int:
	var out := st
	var fc := b.get_prop(st, "facing")
	if fc == "north" or fc == "south":
		out = b.with_prop(out, "facing", "south" if fc == "north" else "north")
		var sh := b.get_prop(st, "shape")
		if sh.begins_with("inner_") or sh.begins_with("outer_"):
			out = b.with_prop(out, "shape", sh.replace("left", "#").replace("right", "left").replace("#", "right"))
	if b.has_prop(st, "north") and b.has_prop(st, "south"):
		out = b.with_prop(b.with_prop(out, "north", b.get_prop(st, "south")), "south", b.get_prop(st, "north"))
	var rr := b.get_prop(st, "rotation")
	if rr != "":
		var j := int(rr)
		j = j - 16 if j > 8 else j
		out = b.with_prop(out, "rotation", str(posmod(8 - j, 16)))
	return out


## Start data: bounding box (min, size by orientation), orientation, ground y; from the start random like Java's
## piece constructors (getRandomHorizontalDirection).
static func scattered(st: Structures, kind: String, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var size: Vector3i = {"swamp_hut": Vector3i(7, 7, 9), "jungle_temple": Vector3i(12, 10, 15), "desert_pyramid": Vector3i(21, 15, 21)}[kind]
	var ori: String = DIRS[r.next_int_bound(4)]
	var x := sc.x * 16
	var z := sc.y * 16
	var bmin := Vector3i(x, 64, z)
	var bmax := Vector3i(x + size.x - 1, 64 + size.y - 1, z + size.z - 1) if ori == "north" or ori == "south" else Vector3i(x + size.z - 1, 64 + size.y - 1, z + size.x - 1)
	if kind != "swamp_hut":
		# SinglePieceStructure: no start when the lowest corner (first occupied, WORLD_SURFACE_WG) is below sea level
		var lo := 1 << 30
		for cxz in [Vector2i(x, z), Vector2i(x, z + size.z), Vector2i(x + size.x, z), Vector2i(x + size.x, z + size.z)]:
			lo = mini(lo, st.base_height(cxz.x, cxz.y, false) - 1)
		if lo < st.gen.sea_level:
			return {}
	var ground := 0
	if kind == "desert_pyramid":
		# updateHeightPositionToLowestGroundHeight(level, -random.nextInt(3)): the lowest WORLD_SURFACE_WG height
		var lo2 := 1 << 30
		for zz in range(bmin.z, bmax.z + 1):
			for xx in range(bmin.x, bmax.x + 1):
				lo2 = mini(lo2, st.base_height(xx, zz, false))
		ground = lo2 - r.next_int_bound(3)
	else:
		# updateAverageGroundHeight: mean MOTION_BLOCKING_NO_LEAVES height (no trees exist at this step)
		var tot := 0
		var n := 0
		for zz in range(bmin.z, bmax.z + 1):
			for xx in range(bmin.x, bmax.x + 1):
				tot += st.base_height(xx, zz, false)
				n += 1
		ground = tot / maxi(1, n)
	var dy := ground - bmin.y
	bmin.y += dy
	bmax.y += dy
	var el := {"t": "java", "kind": kind, "bmin": bmin, "bmax": bmax, "ori": ori}
	# references reach below the floor (columns down, the pyramid hidden chamber)
	var reach := [bmin - Vector3i(0, 16, 0), bmax]
	var res := {"pieces": [{"el": el, "pos": bmin, "rot": 0, "box": reach, "sbox": [bmin, bmax]}], "center": (bmin + bmax) / 2, "box": reach}
	if kind == "desert_pyramid":
		# DesertPyramidStructure.afterPlace: the candidates sorted (y, z, x), shuffled by a positional random at the
		# piece box centre, the first 5..7 suspicious sand, the rest plain sand; plus the roof position
		var ps := pyramid_sand(bmin, bmax, ori, st.gen.seed)
		var cand: Array = ps["cand"]
		cand.sort_custom(func(a: Vector3i, b2: Vector3i) -> bool: return a.y < b2.y if a.y != b2.y else (a.z < b2.z if a.z != b2.z else a.x < b2.x))
		var ctr := Vector3i(bmin.x + (bmax.x - bmin.x + 1) / 2, bmin.y + (bmax.y - bmin.y + 1) / 2, bmin.z + (bmax.z - bmin.z + 1) / 2)
		var sr: RandomSources.LegacyRandom = RandomSources.LegacyRandom.new(st.gen.seed).fork_positional().at(ctr.x, ctr.y, ctr.z)
		cand = Structures._shuffled(cand, sr)
		var npick := mini(cand.size(), 5 + sr.next_int_bound(3))
		res["after"] = "pyramid"
		res["sus"] = cand.slice(0, npick)
		res["sand"] = cand.slice(npick)
		res["sus_roof"] = ps["roof"]
	return res


static func place(st: Structures, c: Features.FCtx, el: Dictionary, cmin: Vector3i, cmax: Vector3i) -> void:
	var p := P.new()
	p.f = st.f
	p.c = c
	p.r = c.r
	p.b = st.f.blocks
	p.bmin = el.get("bmin", el.get("min", Vector3i.ZERO))
	p.bmax = el.get("bmax", el.get("max", Vector3i.ZERO))
	p.ori = str(el.get("ori", ""))
	p.cmin = Vector3i(cmin.x, st.gen.gen_min_y, cmin.z)
	p.cmax = Vector3i(cmax.x, st.gen.gen_min_y + st.gen.gen_depth - 1, cmax.z)
	match str(el["kind"]):
		"mineshaft":
			p.ori = str(el.get("ori", ""))
			var t0 := Time.get_ticks_usec() if st.f.profiling else 0
			_place_mineshaft(p, el)
			if st.f.profiling:
				var pk := "    ms " + str(el["k"])
				st.f.profile[pk] = int(st.f.profile.get(pk, 0)) + Time.get_ticks_usec() - t0
		"buried_treasure":
			p.ori = ""
			_buried_treasure(p)
		"fortress":
			_place_fortress(p, el)
		"stronghold":
			_place_stronghold(p, el)
		"monument":
			_place_monument(p, el)
		"swamp_hut":
			_swamp_hut(p)
		"jungle_temple":
			_jungle_temple(p)
		"desert_pyramid":
			_desert_pyramid(p)


static func _stairs(p: P, name: String, facing: String, extra: Dictionary = {}) -> int:
	var st := p.b.with_prop(p.b.default_state(name), "facing", facing)
	for k in extra:
		st = p.b.with_prop(st, k, str(extra[k]))
	return st


# ------------------------------------------------------------------ SwampHutPiece

static func _swamp_hut(p: P) -> void:
	var pl := p.s("spruce_planks")
	var lg := p.s("oak_log")
	var fence := p.s("oak_fence")
	p.box(1, 1, 1, 5, 1, 7, pl, pl)
	p.box(1, 4, 2, 5, 4, 7, pl, pl)
	p.box(2, 1, 0, 4, 1, 0, pl, pl)
	p.box(2, 2, 2, 3, 3, 2, pl, pl)
	p.box(1, 2, 3, 1, 3, 6, pl, pl)
	p.box(5, 2, 3, 5, 3, 6, pl, pl)
	p.box(2, 2, 7, 4, 3, 7, pl, pl)
	p.box(1, 0, 2, 1, 3, 2, lg, lg)
	p.box(5, 0, 2, 5, 3, 2, lg, lg)
	p.box(1, 0, 7, 1, 3, 7, lg, lg)
	p.box(5, 0, 7, 5, 3, 7, lg, lg)
	p.place(fence, 2, 3, 2)
	p.place(fence, 3, 3, 7)
	p.place(0, 1, 3, 4)
	p.place(0, 5, 3, 4)
	p.place(0, 5, 3, 5)
	p.place(p.s("potted_red_mushroom"), 1, 3, 5)
	p.place(p.s("crafting_table"), 3, 2, 6)
	p.place(p.s("cauldron"), 4, 2, 6)
	p.place(fence, 1, 2, 1)
	p.place(fence, 5, 2, 1)
	var n := _stairs(p, "spruce_stairs", "north")
	var e := _stairs(p, "spruce_stairs", "east")
	var w := _stairs(p, "spruce_stairs", "west")
	var s := _stairs(p, "spruce_stairs", "south")
	p.box(0, 4, 1, 6, 4, 1, n, n)
	p.box(0, 4, 2, 0, 4, 7, e, e)
	p.box(6, 4, 2, 6, 4, 7, w, w)
	p.box(0, 4, 8, 6, 4, 8, s, s)
	p.place(p.b.with_prop(n, "shape", "outer_right"), 0, 4, 1)
	p.place(p.b.with_prop(n, "shape", "outer_left"), 6, 4, 1)
	p.place(p.b.with_prop(s, "shape", "outer_left"), 0, 4, 8)
	p.place(p.b.with_prop(s, "shape", "outer_right"), 6, 4, 8)
	for i in [2, 7]:
		for j in [1, 5]:
			p.column_down(lg, j, -1, i)
	# the witch and the black cat at (2, 2, 5), persistent
	var wp := p.wpos(2, 2, 5)
	if p.inside(wp):
		p.c.entities.append({"k": "mob", "id": "witch", "p": [wp.x + 0.5, wp.y, wp.z + 0.5], "b": 0, "pers": true})
		p.c.entities.append({"k": "mob", "id": "cat", "p": [wp.x + 0.5, wp.y, wp.z + 0.5], "b": 0, "pers": true, "d": {"variant": "all_black"}})


# ------------------------------------------------------------------ JungleTemplePiece

static func _jungle_temple(p: P) -> void:
	var cob := p.s("cobblestone")
	var mossy := p.s("mossy_cobblestone")
	var r = p.r
	# MossStoneSelector: cobblestone below 0.4, else mossy cobblestone
	var stone := func(_wall: bool) -> int: return cob if r.next_float() < 0.4 else mossy
	var W := 12
	var D := 15
	p.box_sel(0, -4, 0, W - 1, 0, D - 1, false, stone)
	p.box_sel(2, 1, 2, 9, 2, 2, false, stone)
	p.box_sel(2, 1, 12, 9, 2, 12, false, stone)
	p.box_sel(2, 1, 3, 2, 2, 11, false, stone)
	p.box_sel(9, 1, 3, 9, 2, 11, false, stone)
	p.box_sel(1, 3, 1, 10, 6, 1, false, stone)
	p.box_sel(1, 3, 13, 10, 6, 13, false, stone)
	p.box_sel(1, 3, 2, 1, 6, 12, false, stone)
	p.box_sel(10, 3, 2, 10, 6, 12, false, stone)
	p.box_sel(2, 3, 2, 9, 3, 12, false, stone)
	p.box_sel(2, 6, 2, 9, 6, 12, false, stone)
	p.box_sel(3, 7, 3, 8, 7, 11, false, stone)
	p.box_sel(4, 8, 4, 7, 8, 10, false, stone)
	p.air(3, 1, 3, 8, 2, 11)
	p.air(4, 3, 6, 7, 3, 9)
	p.air(2, 4, 2, 9, 5, 12)
	p.air(4, 6, 5, 7, 6, 9)
	p.air(5, 7, 6, 6, 7, 8)
	p.air(5, 1, 2, 6, 2, 2)
	p.air(5, 2, 12, 6, 2, 12)
	p.air(5, 5, 1, 6, 5, 1)
	p.air(5, 5, 13, 6, 5, 13)
	p.place(0, 1, 5, 5)
	p.place(0, 10, 5, 5)
	p.place(0, 1, 5, 9)
	p.place(0, 10, 5, 9)
	for i in [0, 14]:
		p.box_sel(2, 4, i, 2, 5, i, false, stone)
		p.box_sel(4, 4, i, 4, 5, i, false, stone)
		p.box_sel(7, 4, i, 7, 5, i, false, stone)
		p.box_sel(9, 4, i, 9, 5, i, false, stone)
	p.box_sel(5, 6, 0, 6, 6, 0, false, stone)
	for l in [0, 11]:
		for j in range(2, 13, 2):
			p.box_sel(l, 4, j, l, 5, j, false, stone)
		p.box_sel(l, 6, 5, l, 6, 5, false, stone)
		p.box_sel(l, 6, 9, l, 6, 9, false, stone)
	p.box_sel(2, 7, 2, 2, 9, 2, false, stone)
	p.box_sel(9, 7, 2, 9, 9, 2, false, stone)
	p.box_sel(2, 7, 12, 2, 9, 12, false, stone)
	p.box_sel(9, 7, 12, 9, 9, 12, false, stone)
	p.box_sel(4, 9, 4, 4, 9, 4, false, stone)
	p.box_sel(7, 9, 4, 7, 9, 4, false, stone)
	p.box_sel(4, 9, 10, 4, 9, 10, false, stone)
	p.box_sel(7, 9, 10, 7, 9, 10, false, stone)
	p.box_sel(5, 9, 7, 6, 9, 7, false, stone)
	var e := _stairs(p, "cobblestone_stairs", "east")
	var w := _stairs(p, "cobblestone_stairs", "west")
	var s := _stairs(p, "cobblestone_stairs", "south")
	var n := _stairs(p, "cobblestone_stairs", "north")
	p.place(n, 5, 9, 6)
	p.place(n, 6, 9, 6)
	p.place(s, 5, 9, 8)
	p.place(s, 6, 9, 8)
	p.place(n, 4, 0, 0)
	p.place(n, 5, 0, 0)
	p.place(n, 6, 0, 0)
	p.place(n, 7, 0, 0)
	p.place(n, 4, 1, 8)
	p.place(n, 4, 2, 9)
	p.place(n, 4, 3, 10)
	p.place(n, 7, 1, 8)
	p.place(n, 7, 2, 9)
	p.place(n, 7, 3, 10)
	p.box_sel(4, 1, 9, 4, 1, 9, false, stone)
	p.box_sel(7, 1, 9, 7, 1, 9, false, stone)
	p.box_sel(4, 1, 10, 7, 2, 10, false, stone)
	p.box_sel(5, 4, 5, 6, 4, 5, false, stone)
	p.place(e, 4, 4, 5)
	p.place(w, 7, 4, 5)
	for k in 4:
		p.place(s, 5, -k, 6 + k)
		p.place(s, 6, -k, 6 + k)
		p.air(5, -k, 7 + k, 6, -k, 9 + k)
	p.air(1, -3, 12, 10, -1, 13)
	p.air(1, -3, 1, 3, -1, 13)
	p.air(1, -3, 1, 9, -1, 5)
	for i1 in range(1, 14, 2):
		p.box_sel(1, -3, i1, 1, -2, i1, false, stone)
	for j1 in range(2, 13, 2):
		p.box_sel(1, -1, j1, 3, -1, j1, false, stone)
	p.box_sel(2, -2, 1, 5, -2, 1, false, stone)
	p.box_sel(7, -2, 1, 9, -2, 1, false, stone)
	p.box_sel(6, -3, 1, 6, -3, 1, false, stone)
	p.box_sel(6, -1, 1, 6, -1, 1, false, stone)
	p.place(p.sp("tripwire_hook", {"facing": "east", "attached": true}), 1, -3, 8)
	p.place(p.sp("tripwire_hook", {"facing": "west", "attached": true}), 4, -3, 8)
	var tw_ew := p.sp("tripwire", {"east": true, "west": true, "attached": true})
	p.place(tw_ew, 2, -3, 8)
	p.place(tw_ew, 3, -3, 8)
	var rs_ns := p.sp("redstone_wire", {"north": "side", "south": "side"})
	for zz in [7, 6, 5, 4, 3, 2]:
		p.place(rs_ns, 5, -3, zz)
	p.place(p.sp("redstone_wire", {"north": "side", "west": "side"}), 5, -3, 1)
	p.place(p.sp("redstone_wire", {"east": "side"}), 4, -3, 1)
	p.place(mossy, 3, -3, 1)
	p.dispenser(3, -2, 1, "north", "chests/jungle_temple_dispenser")
	p.place(p.sp("vine", {"south": true}), 3, -2, 2)
	p.place(p.sp("tripwire_hook", {"facing": "north", "attached": true}), 7, -3, 1)
	p.place(p.sp("tripwire_hook", {"facing": "south", "attached": true}), 7, -3, 5)
	var tw_ns := p.sp("tripwire", {"north": true, "south": true, "attached": true})
	p.place(tw_ns, 7, -3, 2)
	p.place(tw_ns, 7, -3, 3)
	p.place(tw_ns, 7, -3, 4)
	p.place(p.sp("redstone_wire", {"east": "side", "west": "side"}), 8, -3, 6)
	p.place(p.sp("redstone_wire", {"west": "side", "south": "side"}), 9, -3, 6)
	p.place(p.sp("redstone_wire", {"north": "side", "south": "up"}), 9, -3, 5)
	p.place(mossy, 9, -3, 4)
	p.place(p.sp("redstone_wire", {"north": "side"}), 9, -2, 4)
	p.dispenser(9, -2, 3, "west", "chests/jungle_temple_dispenser")
	p.place(p.sp("vine", {"east": true}), 8, -1, 3)
	p.place(p.sp("vine", {"east": true}), 8, -2, 3)
	p.chest(8, -3, 3, "chests/jungle_temple")
	p.place(mossy, 9, -3, 2)
	p.place(mossy, 8, -3, 1)
	p.place(mossy, 4, -3, 5)
	p.place(mossy, 5, -2, 5)
	p.place(mossy, 5, -1, 5)
	p.place(mossy, 6, -3, 5)
	p.place(mossy, 7, -2, 5)
	p.place(mossy, 7, -1, 5)
	p.place(mossy, 8, -3, 5)
	p.box_sel(9, -1, 1, 9, -1, 5, false, stone)
	p.air(8, -3, 8, 10, -1, 10)
	var chis := p.s("chiseled_stone_bricks")
	p.place(chis, 8, -2, 11)
	p.place(chis, 9, -2, 11)
	p.place(chis, 10, -2, 11)
	var lever := p.sp("lever", {"facing": "north", "face": "wall"})
	p.place(lever, 8, -2, 12)
	p.place(lever, 9, -2, 12)
	p.place(lever, 10, -2, 12)
	p.box_sel(8, -3, 8, 8, -3, 10, false, stone)
	p.box_sel(10, -3, 8, 10, -3, 10, false, stone)
	p.place(mossy, 10, -2, 9)
	p.place(p.sp("redstone_wire", {"north": "side"}), 8, -2, 9)
	p.place(p.sp("redstone_wire", {"south": "side"}), 8, -2, 10)
	p.place(p.s("redstone_wire"), 10, -1, 9)
	p.place(p.sp("sticky_piston", {"facing": "up"}), 9, -2, 8)
	p.place(p.sp("sticky_piston", {"facing": "west"}), 10, -2, 8)
	p.place(p.sp("sticky_piston", {"facing": "west"}), 10, -1, 8)
	p.place(p.sp("repeater", {"facing": "north"}), 10, -2, 10)
	p.chest(9, -3, 10, "chests/jungle_temple")


# ------------------------------------------------------------------ DesertPyramidPiece (classic body)

static func _desert_pyramid(p: P) -> void:
	var W := 21
	var D := 21
	var ss := p.s("sandstone")
	var cut := p.s("cut_sandstone")
	var chis := p.s("chiseled_sandstone")
	var ot := p.s("orange_terracotta")
	var bt := p.s("blue_terracotta")
	p.box(0, -4, 0, W - 1, 0, D - 1, ss, ss)
	for i in range(1, 10):
		p.box(i, i, i, W - 1 - i, i, D - 1 - i, ss, ss)
		p.box(i + 1, i, i + 1, W - 2 - i, i, D - 2 - i, 0, 0)
	for x in W:
		for z in D:
			p.column_down(ss, x, -5, z)
	var n := _stairs(p, "sandstone_stairs", "north")
	var s := _stairs(p, "sandstone_stairs", "south")
	var e := _stairs(p, "sandstone_stairs", "east")
	var w := _stairs(p, "sandstone_stairs", "west")
	p.box(0, 0, 0, 4, 9, 4, ss, 0)
	p.box(1, 10, 1, 3, 10, 3, ss, ss)
	p.place(n, 2, 10, 0)
	p.place(s, 2, 10, 4)
	p.place(e, 0, 10, 2)
	p.place(w, 4, 10, 2)
	p.box(W - 5, 0, 0, W - 1, 9, 4, ss, 0)
	p.box(W - 4, 10, 1, W - 2, 10, 3, ss, ss)
	p.place(n, W - 3, 10, 0)
	p.place(s, W - 3, 10, 4)
	p.place(e, W - 5, 10, 2)
	p.place(w, W - 1, 10, 2)
	p.box(8, 0, 0, 12, 4, 4, ss, 0)
	p.box(9, 1, 0, 11, 3, 4, 0, 0)
	for q in [Vector2i(9, 1), Vector2i(9, 2), Vector2i(9, 3), Vector2i(10, 3), Vector2i(11, 3), Vector2i(11, 2), Vector2i(11, 1)]:
		p.place(cut, q.x, q.y, 1)
	p.box(4, 1, 1, 8, 3, 3, ss, 0)
	p.box(4, 1, 2, 8, 2, 2, 0, 0)
	p.box(12, 1, 1, 16, 3, 3, ss, 0)
	p.box(12, 1, 2, 16, 2, 2, 0, 0)
	p.box(5, 4, 5, W - 6, 4, D - 6, ss, ss)
	p.box(9, 4, 9, 11, 4, 11, 0, 0)
	p.box(8, 1, 8, 8, 3, 8, cut, cut)
	p.box(12, 1, 8, 12, 3, 8, cut, cut)
	p.box(8, 1, 12, 8, 3, 12, cut, cut)
	p.box(12, 1, 12, 12, 3, 12, cut, cut)
	p.box(1, 1, 5, 4, 4, 11, ss, ss)
	p.box(W - 5, 1, 5, W - 2, 4, 11, ss, ss)
	p.box(6, 7, 9, 6, 7, 11, ss, ss)
	p.box(W - 7, 7, 9, W - 7, 7, 11, ss, ss)
	p.box(5, 5, 9, 5, 7, 11, cut, cut)
	p.box(W - 6, 5, 9, W - 6, 7, 11, cut, cut)
	p.place(0, 5, 5, 10)
	p.place(0, 5, 6, 10)
	p.place(0, 6, 6, 10)
	p.place(0, W - 6, 5, 10)
	p.place(0, W - 6, 6, 10)
	p.place(0, W - 7, 6, 10)
	p.box(2, 4, 4, 2, 6, 4, 0, 0)
	p.box(W - 3, 4, 4, W - 3, 6, 4, 0, 0)
	p.place(n, 2, 4, 5)
	p.place(n, 2, 3, 4)
	p.place(n, W - 3, 4, 5)
	p.place(n, W - 3, 3, 4)
	p.box(1, 1, 3, 2, 2, 3, ss, ss)
	p.box(W - 3, 1, 3, W - 2, 2, 3, ss, ss)
	p.place(ss, 1, 1, 2)
	p.place(ss, W - 2, 1, 2)
	p.place(p.s("sandstone_slab"), 1, 2, 2)
	p.place(p.s("sandstone_slab"), W - 2, 2, 2)
	p.place(w, 2, 1, 2)
	p.place(e, W - 3, 1, 2)
	p.box(4, 3, 5, 4, 3, 17, ss, ss)
	p.box(W - 5, 3, 5, W - 5, 3, 17, ss, ss)
	p.box(3, 1, 5, 4, 2, 16, 0, 0)
	p.box(W - 6, 1, 5, W - 5, 2, 16, 0, 0)
	for l in range(5, 18, 2):
		p.place(cut, 4, 1, l)
		p.place(chis, 4, 2, l)
		p.place(cut, W - 5, 1, l)
		p.place(chis, W - 5, 2, l)
	for q2 in [Vector2i(10, 7), Vector2i(10, 8), Vector2i(9, 9), Vector2i(11, 9), Vector2i(8, 10), Vector2i(12, 10), Vector2i(7, 10), Vector2i(13, 10), Vector2i(9, 11), Vector2i(11, 11), Vector2i(10, 12), Vector2i(10, 13)]:
		p.place(ot, q2.x, 0, q2.y)
	p.place(bt, 10, 0, 10)
	# the towers' front patterns (x = 0 and x = W - 1), then the two facades (x = 2 and W - 3)
	var col := [[cut, ot, cut], [cut, ot, cut], [ot, chis, ot], [cut, ot, cut], [ot, chis, ot], [ot, ot, ot], [cut, cut, cut]]
	for j1 in [0, W - 1]:
		for yy in 7:
			for zz in 3:
				p.place(col[yy][zz], j1, 2 + yy, 1 + zz)
	for k1 in [2, W - 3]:
		for yy2 in 7:
			for dx in 3:
				p.place(col[yy2][dx], k1 - 1 + dx, 2 + yy2, 0)
	p.box(8, 4, 0, 12, 6, 0, cut, cut)
	p.place(0, 8, 6, 0)
	p.place(0, 12, 6, 0)
	p.place(ot, 9, 5, 0)
	p.place(chis, 10, 5, 0)
	p.place(ot, 11, 5, 0)
	# hidden chamber: shaft, pressure plate over 9 TNT, four chests
	p.box(8, -14, 8, 12, -11, 12, cut, cut)
	p.box(8, -10, 8, 12, -10, 12, chis, chis)
	p.box(8, -9, 8, 12, -9, 12, cut, cut)
	p.box(8, -8, 8, 12, -1, 12, ss, ss)
	p.box(9, -11, 9, 11, -1, 11, 0, 0)
	p.place(p.s("stone_pressure_plate"), 10, -11, 10)
	p.box(9, -13, 9, 11, -13, 11, p.s("tnt"), 0)
	for side in [[8, 10, 7, 10], [12, 10, 13, 10], [10, 8, 10, 7], [10, 12, 10, 13]]:
		p.place(0, side[0], -11, side[1])
		p.place(0, side[0], -10, side[1])
		p.place(chis, side[2], -10, side[3])
		p.place(cut, side[2], -11, side[3])
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		p.chest(10 + d.x * 2, -11, 10 + d.y * 2, "chests/desert_pyramid")
	_pyramid_cellar(p)


## DesertPyramidPiece.addCellar (1.20): a sand-filled stairwell from the south-east end of the side corridor down to a
## 7 x 7 cellar under the hall (cut / chiseled sandstone rings, terracotta floor star, sand niches in the walls) and a
## collapsed sand roof patch in the hall floor. The sand of the room, the niches and the roof patch is placed by
## Structures._pyramid_after (DesertPyramidStructure.afterPlace: some of it suspicious sand).
const CELLAR := Vector3i(16, -4, 13)


static func _pyramid_cellar(p: P) -> void:
	var i := CELLAR.x
	var j := CELLAR.y
	var k := CELLAR.z
	var stair := p.b.with_prop(p.b.default_state("sandstone_stairs"), "facing", "west")   # rotate(COUNTERCLOCKWISE_90)
	p.place(stair, 13, -1, 17)
	p.place(stair, 14, -2, 17)
	p.place(stair, 15, -3, 17)
	var sand := p.s("sand")
	var ss := p.s("sandstone")
	var bl: bool = p.r.next_bool() if p.r != null else false
	for dx in range(-4, 1):
		p.place(sand, i + dx, j + 4, k + 4)
	p.place(sand, i - 2, j + 3, k + 4)
	p.place(sand if bl else ss, i - 1, j + 3, k + 4)
	p.place(sand if not bl else ss, i, j + 3, k + 4)
	p.place(sand, i - 1, j + 2, k + 4)
	p.place(ss, i, j + 2, k + 4)
	p.place(sand, i, j + 1, k + 4)
	# addCellarRoom: rings of cut / chiseled / cut sandstone
	var cut := p.s("cut_sandstone")
	var chis := p.s("chiseled_sandstone")
	for ring in [[j + 1, cut], [j + 2, chis], [-1, cut]]:
		var y: int = ring[0]
		var stt: int = ring[1]
		p.box(i - 3, y, k - 3, i - 3, y, k + 2, stt, stt, true)
		p.box(i + 3, y, k - 3, i + 3, y, k + 2, stt, stt, true)
		p.box(i - 3, y, k - 3, i + 3, y, k - 2, stt, stt, true)
		p.box(i - 3, y, k + 3, i + 3, y, k + 3, stt, stt, true)
	# placeCollapsedRoof: sand, a third sandstone (level random)
	for x in range(i - 2, i + 3):
		for z in range(k - 2, k + 3):
			p.place(ss if (p.r != null and p.r.next_float() < 0.33) else sand, x, j + 4, z)
	var ot := p.s("orange_terracotta")
	var bt := p.s("blue_terracotta")
	p.place(bt, i, j, k)
	for q in [Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(3, 0)]:
		p.place(ot, i + q.x, j, k + q.y)
	p.place(ot, i + 4, j + 1, k)
	p.place(chis, i + 4, j + 2, k)
	p.place(ot, i - 3, j, k)
	p.place(ot, i - 4, j + 1, k)
	p.place(chis, i - 4, j + 2, k)
	p.place(ot, i, j, k + 3)
	p.place(ot, i, j, k - 3)
	p.place(ot, i, j + 1, k - 4)
	p.place(chis, i, -2, k - 4)


## The cellar suspicious-sand candidates (placeSand / placeSandBox, world positions) and the collapsed roof random
## position (RandomSource.create(world seed).forkPositional().at(roof corner)): fixed by the piece box and the seed.
static func pyramid_sand(bmin: Vector3i, bmax: Vector3i, ori: String, world_seed: int) -> Dictionary:
	var p := P.new()
	p.bmin = bmin
	p.bmax = bmax
	p.ori = ori
	var i := CELLAR.x
	var j := CELLAR.y
	var k := CELLAR.z
	var cand := {}
	for y in range(j + 1, j + 4):
		for x in range(i - 2, i + 3):
			for z in range(k - 2, k + 3):
				cand[p.wpos(x, y, z)] = true
	for q in [Vector3i(i + 3, j + 1, k), Vector3i(i + 3, j + 2, k), Vector3i(i - 3, j + 1, k), Vector3i(i - 3, j + 2, k),
			Vector3i(i, j + 1, k + 3), Vector3i(i, j + 2, k + 3), Vector3i(i, j + 1, k - 3), Vector3i(i, j + 2, k - 3)]:
		cand[p.wpos(q.x, q.y, q.z)] = true
	var corner := p.wpos(i - 2, j + 4, k - 2)
	var rr: RandomSources.LegacyRandom = RandomSources.LegacyRandom.new(world_seed).fork_positional().at(corner.x, corner.y, corner.z)
	var ri := rr.range_int(i - 2, i + 2)
	var rj := rr.range_int(k - 2, k + 2)
	return {"cand": cand.keys(), "roof": p.wpos(ri, j + 4, rj)}


# ------------------------------------------------------------------ MineshaftStructure / MineshaftPieces

## Java MineshaftStructure.findGenerationPoint: random.nextDouble(), a room at chunk + 2 (y 50), its children
## (corridors 70 %, stairs 10 %, crossings 20 %, depth <= 8, within 80 blocks), then moveBelowSeaLevel (mesa: lifted
## to a random height up to the surface). Piece dictionaries: k (room / corridor / crossing / stairs), min, max, ori.
static func mineshaft(st: Structures, cfg: Dictionary, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var mesa := str(cfg.get("mineshaft_type", "normal")) == "mesa"
	r.next_double()
	var pieces: Array = []
	var rx := sc.x * 16 + 2
	var rz := sc.y * 16 + 2
	var room := {"k": "room", "min": Vector3i(rx, 50, rz), "ori": "", "depth": 0, "entr": []}
	room["max"] = Vector3i(rx + 7 + r.next_int_bound(6), 54 + r.next_int_bound(6), rz + 7 + r.next_int_bound(6))
	pieces.append(room)
	_ms_room_children(room, pieces, r)
	var bmin := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var bmax := -bmin
	for pc in pieces:
		bmin = Vector3i(mini(bmin.x, pc["min"].x), mini(bmin.y, pc["min"].y), mini(bmin.z, pc["min"].z))
		bmax = Vector3i(maxi(bmax.x, pc["max"].x), maxi(bmax.y, pc["max"].y), maxi(bmax.z, pc["max"].z))
	var sea: int = st.gen.sea_level
	var dy := 0
	if mesa:
		var ctr := Vector3i(bmin.x + (bmax.x - bmin.x + 1) / 2, bmin.y + (bmax.y - bmin.y + 1) / 2, bmin.z + (bmax.z - bmin.z + 1) / 2)
		var j := st.base_height(ctr.x, ctr.z, false)
		var k := sea if j <= sea else r.next_int_bound(j - sea + 1) + sea
		dy = k - ctr.y
	else:
		# StructurePiecesBuilder.moveBelowSeaLevel(sea, minY, random, 10)
		var i := sea - 10
		var j2 := (bmax.y - bmin.y + 1) + st.gen.gen_min_y + 1
		if j2 < i:
			j2 += r.next_int_bound(i - j2)
		dy = j2 - bmax.y
	var out: Array = []
	for pc2 in pieces:
		pc2["min"] = pc2["min"] + Vector3i(0, dy, 0)
		pc2["max"] = pc2["max"] + Vector3i(0, dy, 0)
		var ent: Array = []
		for eb in pc2.get("entr", []):
			ent.append([eb[0] + Vector3i(0, dy, 0), eb[1] + Vector3i(0, dy, 0)])
		pc2["entr"] = ent
		pc2["t"] = "java"
		pc2["kind"] = "mineshaft"
		pc2["mesa"] = mesa
		out.append({"el": pc2, "pos": pc2["min"], "rot": 0, "box": [pc2["min"], pc2["max"]]})
	return {"pieces": out, "center": room["min"], "box": [bmin + Vector3i(0, dy, 0), bmax + Vector3i(0, dy, 0)]}


static func _collides(pieces: Array, mn: Vector3i, mx: Vector3i) -> bool:
	for pc in pieces:
		var a: Vector3i = pc["min"]
		var b2: Vector3i = pc["max"]
		if mx.x >= a.x and mn.x <= b2.x and mx.z >= a.z and mn.z <= b2.z and mx.y >= a.y and mn.y <= b2.y:
			return true
	return false


const MS_CROSS := {"north": [Vector3i(-1, 0, -4), Vector3i(3, 0, 0)], "south": [Vector3i(-1, 0, 0), Vector3i(3, 0, 4)],
	"west": [Vector3i(-4, 0, -1), Vector3i(0, 0, 3)], "east": [Vector3i(0, 0, -1), Vector3i(4, 0, 3)]}
const MS_STAIRS := {"north": [Vector3i(0, -5, -8), Vector3i(2, 2, 0)], "south": [Vector3i(0, -5, 0), Vector3i(2, 2, 8)],
	"west": [Vector3i(-8, -5, 0), Vector3i(0, 2, 2)], "east": [Vector3i(0, -5, 0), Vector3i(8, 2, 2)]}


## MineshaftPieces.generateAndAddPiece + createRandomShaftPiece.
static func _ms_add(start: Dictionary, pieces: Array, r, x: int, y: int, z: int, d: String, depth: int):
	if depth > 8:
		return null
	if absi(x - start["min"].x) > 80 or absi(z - start["min"].z) > 80:
		return null
	var nd := depth + 1
	var i: int = r.next_int_bound(100)
	var pc = null
	if i >= 80:
		var h := 6 if r.next_int_bound(4) == 0 else 2
		var cb: Array = MS_CROSS[d]
		var mn: Vector3i = cb[0] + Vector3i(x, y, z)
		var mx: Vector3i = cb[1] + Vector3i(x, y + h, z)
		if not _collides(pieces, mn, mx):
			pc = {"k": "crossing", "min": mn, "max": mx, "ori": "", "dir": d, "two": (mx.y - mn.y + 1) > 3, "depth": nd}
	elif i >= 70:
		var sb: Array = MS_STAIRS[d]
		var mn2: Vector3i = sb[0] + Vector3i(x, y, z)
		var mx2: Vector3i = sb[1] + Vector3i(x, y, z)
		if not _collides(pieces, mn2, mx2):
			pc = {"k": "stairs", "min": mn2, "max": mx2, "ori": d, "depth": nd}
	else:
		var n: int = r.next_int_bound(3) + 2
		while n > 0:
			var j := n * 5
			var cb3: Array = {"north": [Vector3i(0, 0, -(j - 1)), Vector3i(2, 2, 0)], "south": [Vector3i(0, 0, 0), Vector3i(2, 2, j - 1)],
				"west": [Vector3i(-(j - 1), 0, 0), Vector3i(0, 2, 2)], "east": [Vector3i(0, 0, 0), Vector3i(j - 1, 2, 2)]}[d]
			var mn3: Vector3i = cb3[0] + Vector3i(x, y, z)
			var mx3: Vector3i = cb3[1] + Vector3i(x, y, z)
			if not _collides(pieces, mn3, mx3):
				var rails: bool = r.next_int_bound(3) == 0
				var spider: bool = not rails and r.next_int_bound(23) == 0
				var secs := ((mx3.z - mn3.z + 1) if d == "north" or d == "south" else (mx3.x - mn3.x + 1)) / 5
				pc = {"k": "corridor", "min": mn3, "max": mx3, "ori": d, "rails": rails, "spider": spider, "secs": secs, "depth": nd}
				break
			n -= 1
	if pc == null:
		return null
	pieces.append(pc)
	match str(pc["k"]):
		"crossing":
			_ms_crossing_children(start, pc, pieces, r)
		"stairs":
			_ms_stairs_children(start, pc, pieces, r)
		"corridor":
			_ms_corridor_children(start, pc, pieces, r)
	return pc


static func _ms_room_children(room: Dictionary, pieces: Array, r) -> void:
	var mn: Vector3i = room["min"]
	var mx: Vector3i = room["max"]
	var dep: int = room["depth"]
	var xs := mx.x - mn.x + 1
	var zs := mx.z - mn.z + 1
	var j := (mx.y - mn.y + 1) - 3 - 1
	if j <= 0:
		j = 1
	for side in ["north", "south", "west", "east"]:
		var span := xs if side == "north" or side == "south" else zs
		var k := 0
		while k < span:
			k += r.next_int_bound(span)
			if k + 3 > span:
				break
			var yy: int = mn.y + r.next_int_bound(j) + 1
			var pc = null
			match side:
				"north":
					pc = _ms_add(room, pieces, r, mn.x + k, yy, mn.z - 1, side, dep)
					if pc != null:
						room["entr"].append([Vector3i(pc["min"].x, pc["min"].y, mn.z), Vector3i(pc["max"].x, pc["max"].y, mn.z + 1)])
				"south":
					pc = _ms_add(room, pieces, r, mn.x + k, yy, mx.z + 1, side, dep)
					if pc != null:
						room["entr"].append([Vector3i(pc["min"].x, pc["min"].y, mx.z - 1), Vector3i(pc["max"].x, pc["max"].y, mx.z)])
				"west":
					pc = _ms_add(room, pieces, r, mn.x - 1, yy, mn.z + k, side, dep)
					if pc != null:
						room["entr"].append([Vector3i(mn.x, pc["min"].y, pc["min"].z), Vector3i(mn.x + 1, pc["max"].y, pc["max"].z)])
				"east":
					pc = _ms_add(room, pieces, r, mx.x + 1, yy, mn.z + k, side, dep)
					if pc != null:
						room["entr"].append([Vector3i(mx.x - 1, pc["min"].y, pc["min"].z), Vector3i(mx.x, pc["max"].y, pc["max"].z)])
			k += 4


static func _ms_corridor_children(start: Dictionary, pc: Dictionary, pieces: Array, r) -> void:
	var mn: Vector3i = pc["min"]
	var mx: Vector3i = pc["max"]
	var i: int = pc["depth"]
	var j: int = r.next_int_bound(4)
	var d: String = pc["ori"]
	var yy := 0
	match d:
		"north":
			yy = mn.y - 1 + r.next_int_bound(3)
			if j <= 1:
				_ms_add(start, pieces, r, mn.x, yy, mn.z - 1, d, i)
			elif j == 2:
				_ms_add(start, pieces, r, mn.x - 1, yy, mn.z, "west", i)
			else:
				_ms_add(start, pieces, r, mx.x + 1, yy, mn.z, "east", i)
		"south":
			yy = mn.y - 1 + r.next_int_bound(3)
			if j <= 1:
				_ms_add(start, pieces, r, mn.x, yy, mx.z + 1, d, i)
			elif j == 2:
				_ms_add(start, pieces, r, mn.x - 1, yy, mx.z - 3, "west", i)
			else:
				_ms_add(start, pieces, r, mx.x + 1, yy, mx.z - 3, "east", i)
		"west":
			yy = mn.y - 1 + r.next_int_bound(3)
			if j <= 1:
				_ms_add(start, pieces, r, mn.x - 1, yy, mn.z, d, i)
			elif j == 2:
				_ms_add(start, pieces, r, mn.x, yy, mn.z - 1, "north", i)
			else:
				_ms_add(start, pieces, r, mn.x, yy, mx.z + 1, "south", i)
		"east":
			yy = mn.y - 1 + r.next_int_bound(3)
			if j <= 1:
				_ms_add(start, pieces, r, mx.x + 1, yy, mn.z, d, i)
			elif j == 2:
				_ms_add(start, pieces, r, mx.x - 3, yy, mn.z - 1, "north", i)
			else:
				_ms_add(start, pieces, r, mx.x - 3, yy, mx.z + 1, "south", i)
	if i < 8:
		if d != "north" and d != "south":
			var i1 := mn.x + 3
			while i1 + 3 <= mx.x:
				var j1: int = r.next_int_bound(5)
				if j1 == 0:
					_ms_add(start, pieces, r, i1, mn.y, mn.z - 1, "north", i + 1)
				elif j1 == 1:
					_ms_add(start, pieces, r, i1, mn.y, mx.z + 1, "south", i + 1)
				i1 += 5
		else:
			var k := mn.z + 3
			while k + 3 <= mx.z:
				var l: int = r.next_int_bound(5)
				if l == 0:
					_ms_add(start, pieces, r, mn.x - 1, mn.y, k, "west", i + 1)
				elif l == 1:
					_ms_add(start, pieces, r, mx.x + 1, mn.y, k, "east", i + 1)
				k += 5


static func _ms_crossing_children(start: Dictionary, pc: Dictionary, pieces: Array, r) -> void:
	var mn: Vector3i = pc["min"]
	var mx: Vector3i = pc["max"]
	var i: int = pc["depth"]
	match str(pc["dir"]):
		"north":
			_ms_add(start, pieces, r, mn.x + 1, mn.y, mn.z - 1, "north", i)
			_ms_add(start, pieces, r, mn.x - 1, mn.y, mn.z + 1, "west", i)
			_ms_add(start, pieces, r, mx.x + 1, mn.y, mn.z + 1, "east", i)
		"south":
			_ms_add(start, pieces, r, mn.x + 1, mn.y, mx.z + 1, "south", i)
			_ms_add(start, pieces, r, mn.x - 1, mn.y, mn.z + 1, "west", i)
			_ms_add(start, pieces, r, mx.x + 1, mn.y, mn.z + 1, "east", i)
		"west":
			_ms_add(start, pieces, r, mn.x + 1, mn.y, mn.z - 1, "north", i)
			_ms_add(start, pieces, r, mn.x + 1, mn.y, mx.z + 1, "south", i)
			_ms_add(start, pieces, r, mn.x - 1, mn.y, mn.z + 1, "west", i)
		"east":
			_ms_add(start, pieces, r, mn.x + 1, mn.y, mn.z - 1, "north", i)
			_ms_add(start, pieces, r, mn.x + 1, mn.y, mx.z + 1, "south", i)
			_ms_add(start, pieces, r, mx.x + 1, mn.y, mn.z + 1, "east", i)
	if pc["two"]:
		if r.next_bool():
			_ms_add(start, pieces, r, mn.x + 1, mn.y + 4, mn.z - 1, "north", i)
		if r.next_bool():
			_ms_add(start, pieces, r, mn.x - 1, mn.y + 4, mn.z + 1, "west", i)
		if r.next_bool():
			_ms_add(start, pieces, r, mx.x + 1, mn.y + 4, mn.z + 1, "east", i)
		if r.next_bool():
			_ms_add(start, pieces, r, mn.x + 1, mn.y + 4, mx.z + 1, "south", i)


static func _ms_stairs_children(start: Dictionary, pc: Dictionary, pieces: Array, r) -> void:
	var mn: Vector3i = pc["min"]
	var mx: Vector3i = pc["max"]
	var i: int = pc["depth"]
	match str(pc["ori"]):
		"north":
			_ms_add(start, pieces, r, mn.x, mn.y, mn.z - 1, "north", i)
		"south":
			_ms_add(start, pieces, r, mn.x, mn.y, mx.z + 1, "south", i)
		"west":
			_ms_add(start, pieces, r, mn.x - 1, mn.y, mn.z, "west", i)
		"east":
			_ms_add(start, pieces, r, mx.x + 1, mn.y, mn.z, "east", i)


## MineShaftPiece.isInInvalidLocation: liquid on the faces of the box grown by 1 (within this chunk), or a
## mineshaft-blocking biome (the deep dark) at its centre.
static func _ms_invalid(p: P) -> bool:
	var i := maxi(p.bmin.x - 1, p.cmin.x)
	var j := maxi(p.bmin.y - 1, p.cmin.y)
	var k := maxi(p.bmin.z - 1, p.cmin.z)
	var l := mini(p.bmax.x + 1, p.cmax.x)
	var i1 := mini(p.bmax.y + 1, p.cmax.y)
	var j1 := mini(p.bmax.z + 1, p.cmax.z)
	if i > l or k > j1:
		return true
	var mid := Vector3i((i + l) / 2, (j + i1) / 2, (k + j1) / 2)
	var bio := p.f.biome_at(p.c, mid)
	if _ms_block_bio.is_empty():
		_ms_block_bio = Tags.resolve("worldgen/biome", "#minecraft:mineshaft_blocking").duplicate()
		_ms_block_bio["__ready"] = true
	if bio >= 0 and _ms_block_bio.has(str(p.f.gen.biomes.names[bio])):
		return true
	var fl := p.b.st_flags
	var c := p.c
	if not c.flat.is_empty() and c.has[4] != 0:
		# the faces clipped to this chunk all lie in the origin chunk (flat slot 4): read the array directly
		var flat: PackedInt32Array = c.flat
		var liq := BlockRegistry.F_LIQUID
		var y0 := maxi(j, -64)
		var y1 := mini(i1, 319)
		for yy3 in [y0, y1]:
			var rowb: int = 4 * 98304 + ((yy3 + 64) << 8)
			for x4 in range(i, l + 1):
				for z4 in range(k, j1 + 1):
					var s4 := flat[rowb + ((z4 & 15) << 4) + (x4 & 15)]
					if s4 > 0 and (fl[s4] & liq) != 0:
						return true
		for y5 in range(y0, y1 + 1):
			var rowb2: int = 4 * 98304 + ((y5 + 64) << 8)
			for x5 in range(i, l + 1):
				var s5 := flat[rowb2 + ((k & 15) << 4) + (x5 & 15)]
				var s6 := flat[rowb2 + ((j1 & 15) << 4) + (x5 & 15)]
				if (s5 > 0 and (fl[s5] & liq) != 0) or (s6 > 0 and (fl[s6] & liq) != 0):
					return true
			for z5 in range(k, j1 + 1):
				var s7 := flat[rowb2 + ((z5 & 15) << 4) + (i & 15)]
				var s8 := flat[rowb2 + ((z5 & 15) << 4) + (l & 15)]
				if (s7 > 0 and (fl[s7] & liq) != 0) or (s8 > 0 and (fl[s8] & liq) != 0):
					return true
		return false
	for x in range(i, l + 1):
		for z in range(k, j1 + 1):
			for yy in [j, i1]:
				var s := p.f.get_block(p.c, Vector3i(x, yy, z))
				if s > 0 and (fl[s] & BlockRegistry.F_LIQUID) != 0:
					return true
	for x2 in range(i, l + 1):
		for y in range(j, i1 + 1):
			for zz in [k, j1]:
				var s2 := p.f.get_block(p.c, Vector3i(x2, y, zz))
				if s2 > 0 and (fl[s2] & BlockRegistry.F_LIQUID) != 0:
					return true
	for z2 in range(k, j1 + 1):
		for y2 in range(j, i1 + 1):
			for xx in [i, l]:
				var s3 := p.f.get_block(p.c, Vector3i(xx, y2, z2))
				if s3 > 0 and (fl[s3] & BlockRegistry.F_LIQUID) != 0:
					return true
	return false


static var _ms_block_bio: Dictionary = {}


static func _sturdy(b: BlockRegistry, st: int) -> bool:
	return st > 0 and (b.st_flags[st] & BlockRegistry.F_COLLIDE) != 0 and (b.st_flags[st] & BlockRegistry.F_FULL_SHAPE) != 0


## StructurePiece.isInterior: the block above is in the box and below the OCEAN_FLOOR_WG height.
static func _interior(p: P, x: int, y: int, z: int) -> bool:
	var q := p.wpos(x, y + 1, z)
	if not p.inside(q):
		return false
	var key := Vector2i(q.x, q.z)
	var h = p.floor_h.get(key)
	if h == null:
		h = p.f.height(p.c, "OCEAN_FLOOR_WG", q.x, q.z)
		p.floor_h[key] = h
	return q.y < int(h)


static func _place_mineshaft(p: P, el: Dictionary) -> void:
	var mesa := bool(el.get("mesa", false))
	var planks_n := "dark_oak_planks" if mesa else "oak_planks"
	var planks := p.s(planks_n)
	var wood := p.s("dark_oak_log" if mesa else "oak_log")
	var fence := p.s("dark_oak_fence" if mesa else "oak_fence")
	for nm in [planks_n, "dark_oak_log" if mesa else "oak_log", "dark_oak_fence" if mesa else "oak_fence", "iron_chain", "chain"]:
		var bid := p.b.block_id(nm)
		if bid >= 0:
			p.keep_ids[bid] = true
	var ti := Time.get_ticks_usec() if p.f.profiling else 0
	var bad := _ms_invalid(p)
	if p.f.profiling:
		p.f.profile["    ms invalid-check"] = int(p.f.profile.get("    ms invalid-check", 0)) + Time.get_ticks_usec() - ti
	if bad:
		return
	var cave_air := p.s("cave_air")
	match str(el["k"]):
		"room":
			var mn := p.bmin
			var mx := p.bmax
			p.box(mn.x, mn.y, mn.z, mx.x, mn.y, mx.z, p.s("dirt"), p.s("dirt"), true)
			p.box(mn.x, mn.y + 1, mn.z, mx.x, mini(mn.y + 3, mx.y), mx.z, cave_air, cave_air)
			for eb in el.get("entr", []):
				p.box(eb[0].x, eb[1].y - 2, eb[0].z, eb[1].x, eb[1].y, eb[1].z, cave_air, cave_air)
			# generateUpperHalfSphere(minX, minY + 4, minZ, maxX, maxY, maxZ)
			var y0 := mn.y + 4
			var fx := float(mx.x - mn.x + 1)
			var fy := float(mx.y - y0 + 1)
			var fz := float(mx.z - mn.z + 1)
			var cx := mn.x + fx / 2.0
			var cz := mn.z + fz / 2.0
			for y in range(y0, mx.y + 1):
				var f5 := float(y - y0) / fy
				for x in range(mn.x, mx.x + 1):
					var f6 := (float(x) - cx) / (fx * 0.5)
					for z in range(mn.z, mx.z + 1):
						var f7 := (float(z) - cz) / (fz * 0.5)
						if f6 * f6 + f5 * f5 + f7 * f7 <= 1.05:
							p.place(cave_air, x, y, z)
		"crossing":
			var mn2 := p.bmin
			var mx2 := p.bmax
			if bool(el["two"]):
				p.box(mn2.x + 1, mn2.y, mn2.z, mx2.x - 1, mn2.y + 2, mx2.z, cave_air, cave_air)
				p.box(mn2.x, mn2.y, mn2.z + 1, mx2.x, mn2.y + 2, mx2.z - 1, cave_air, cave_air)
				p.box(mn2.x + 1, mx2.y - 2, mn2.z, mx2.x - 1, mx2.y, mx2.z, cave_air, cave_air)
				p.box(mn2.x, mx2.y - 2, mn2.z + 1, mx2.x, mx2.y, mx2.z - 1, cave_air, cave_air)
				p.box(mn2.x + 1, mn2.y + 3, mn2.z + 1, mx2.x - 1, mn2.y + 3, mx2.z - 1, cave_air, cave_air)
			else:
				p.box(mn2.x + 1, mn2.y, mn2.z, mx2.x - 1, mx2.y, mx2.z, cave_air, cave_air)
				p.box(mn2.x, mn2.y, mn2.z + 1, mx2.x, mx2.y, mx2.z - 1, cave_air, cave_air)
			for q in [Vector2i(mn2.x + 1, mn2.z + 1), Vector2i(mn2.x + 1, mx2.z - 1), Vector2i(mx2.x - 1, mn2.z + 1), Vector2i(mx2.x - 1, mx2.z - 1)]:
				if p.get_at(q.x, mx2.y + 1, q.y) != 0:
					p.box(q.x, mn2.y, q.y, q.x, mx2.y, q.y, planks, cave_air)
			for x2 in range(mn2.x, mx2.x + 1):
				for z2 in range(mn2.z, mx2.z + 1):
					_ms_planks(p, planks, x2, mn2.y - 1, z2)
		"stairs":
			p.box(0, 5, 0, 2, 7, 1, cave_air, cave_air)
			p.box(0, 0, 7, 2, 2, 8, cave_air, cave_air)
			for i in 5:
				p.box(0, 5 - i - (1 if i < 4 else 0), 2 + i, 2, 7 - i, 2 + i, cave_air, cave_air)
		"corridor":
			_ms_corridor(p, el, planks, wood, fence, cave_air)


static func _ms_planks(p: P, planks: int, x: int, y: int, z: int) -> void:
	if _interior(p, x, y, z):
		var q := p.wpos(x, y, z)
		if not _sturdy(p.b, p.f.get_block(p.c, q)):
			p.f.set_block(p.c, q, planks)


static func _ms_corridor(p: P, el: Dictionary, planks: int, wood: int, fence: int, cave_air: int) -> void:
	var r = p.r
	var secs: int = el["secs"]
	var i1 := secs * 5 - 1
	p.box(0, 0, 0, 2, 1, i1, cave_air, cave_air)
	_maybe_box(p, 0.8, 0, 2, 0, 2, 2, i1, cave_air, cave_air, false, false)
	if bool(el["spider"]):
		_maybe_box(p, 0.6, 0, 0, 0, 2, 1, i1, p.s("cobweb"), cave_air, false, true)
	var placed_spider := false
	for j1 in secs:
		var k1 := 2 + j1 * 5
		_ms_support(p, 0, 0, k1, 2, 2, planks, fence, cave_air)
		for wb in [[0.1, 0, k1 - 1], [0.1, 2, k1 - 1], [0.1, 0, k1 + 1], [0.1, 2, k1 + 1], [0.05, 0, k1 - 2], [0.05, 2, k1 - 2], [0.05, 0, k1 + 2], [0.05, 2, k1 + 2]]:
			_ms_cobweb(p, float(wb[0]), int(wb[1]), 2, int(wb[2]))
		if r.next_int_bound(100) == 0:
			p.chest(2, 0, k1 - 1, "chests/abandoned_mineshaft")
		if r.next_int_bound(100) == 0:
			p.chest(0, 0, k1 + 1, "chests/abandoned_mineshaft")
		if bool(el["spider"]) and not placed_spider:
			var i2: int = k1 - 1 + r.next_int_bound(3)
			var sp := p.wpos(1, 0, i2)
			if p.inside(sp) and _interior(p, 1, 0, i2):
				placed_spider = true
				p.f.set_block(p.c, sp, p.s("spawner"))
				p.c.block_entities[sp] = {"id": "spawner", "mob": "cave_spider"}
	for j2 in 3:
		for l2 in range(0, i1 + 1):
			_ms_planks(p, planks, j2, -1, l2)
	_ms_double_support(p, 0, -1, 2, planks, wood, fence)
	if secs > 1:
		_ms_double_support(p, 0, -1, i1 - 2, planks, wood, fence)
	if bool(el["rails"]):
		var rail := p.sp("rail", {"shape": "north_south"})
		for j3 in range(0, i1 + 1):
			var bs := p.get_at(1, -1, j3)
			if bs != 0 and p._solid_render(bs):
				var fch := 0.7 if _interior(p, 1, 0, j3) else 0.9
				if r.next_float() < fch:
					p.place(rail, 1, 0, j3)


static func _maybe_box(p: P, chance: float, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, edge: int, inner: int, require_non_air: bool, require_sky: bool) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				if p.r.next_float() > chance:
					continue
				if require_non_air and p.is_air_at(x, y, z):
					continue
				if require_sky and not _interior(p, x, y, z):
					continue
				var e := y == y0 or y == y1 or x == x0 or x == x1 or z == z0 or z == z1
				p.place(edge if e else inner, x, y, z)


static func _ms_cobweb(p: P, chance: float, x: int, y: int, z: int) -> void:
	if _interior(p, x, y, z) and p.r.next_float() < chance:
		# hasSturdyNeighbours(.., 2): two of the six neighbours present a sturdy face
		var q := p.wpos(x, y, z)
		var n := 0
		for d in [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]:
			var o: Vector3i = q + d
			if p.inside(o) and _sturdy(p.b, p.f.get_block(p.c, o)):
				n += 1
				if n >= 2:
					p.place(p.s("cobweb"), x, y, z)
					return


static func _ms_support(p: P, x0: int, y0: int, z: int, y1: int, x1: int, planks: int, fence: int, cave_air: int) -> void:
	for i in range(x0, x1 + 1):
		if p.get_at(i, y1 + 1, z) == 0:
			return
	p.box(x0, y0, z, x0, y1 - 1, z, p.b.with_prop(fence, "west", "true"), cave_air)
	p.box(x1, y0, z, x1, y1 - 1, z, p.b.with_prop(fence, "east", "true"), cave_air)
	if p.r.next_int_bound(4) == 0:
		p.box(x0, y1, z, x0, y1, z, planks, cave_air)
		p.box(x1, y1, z, x1, y1, z, planks, cave_air)
	else:
		p.box(x0, y1, z, x1, y1, z, planks, cave_air)
		if p.r.next_float() < 0.05:
			p.place(p.sp("wall_torch", {"facing": "south"}), x0 + 1, y1, z - 1)
		if p.r.next_float() < 0.05:
			p.place(p.sp("wall_torch", {"facing": "north"}), x0 + 1, y1, z + 1)


## placeDoubleLowerOrUpperSupport: under the corridor's planks at both sides a log pillar down to sturdy ground (<= 20)
## or, failing that, a fence + chain up to a ceiling (<= 50).
static func _ms_double_support(p: P, x: int, y: int, z: int, planks: int, wood: int, fence: int) -> void:
	for xx in [x, x + 2]:
		var cur := p.get_at(xx, y, z)
		if cur > 0 and p.b.st_block[cur] == p.b.st_block[planks]:
			_ms_pillar(p, wood, fence, xx, y, z)


static func _ms_repl(p: P, st: int) -> bool:
	if st <= 0 or (p.b.st_flags[st] & BlockRegistry.F_LIQUID) != 0:
		return true
	if p.repl_ids.is_empty():
		for nm in ["glow_lichen", "seagrass", "tall_seagrass"]:
			p.repl_ids[p.b.block_id(nm)] = true
	return p.repl_ids.has(p.b.st_block[st])


static func _ms_pillar(p: P, wood: int, fence: int, x: int, y: int, z: int) -> void:
	var q := p.wpos(x, y, z)
	if not p.inside(q):
		return
	var i := q.y
	var j := 1
	var down := true
	var up := true
	var chain := p.b.default_state("iron_chain") if p.b.block_id("iron_chain") >= 0 else p.b.default_state("chain")
	var lava_id := p.b.block_id("lava")
	while down or up:
		if down:
			var py := i - j
			var bs := p.f.get_block(p.c, Vector3i(q.x, py, q.z))
			var repl := _ms_repl(p, bs) and (bs <= 0 or p.b.st_block[bs] != lava_id)
			if not repl and _sturdy(p.b, bs):
				for yy in range(i - j + 1, i):
					p.f.set_block(p.c, Vector3i(q.x, yy, q.z), wood)
				return
			down = j <= 20 and repl and py > p.f.gen.gen_min_y + 1
		if up:
			var bs2 := p.f.get_block(p.c, Vector3i(q.x, i + j, q.z))
			var repl2 := _ms_repl(p, bs2)
			if not repl2 and _sturdy(p.b, bs2) and (p.b.st_flags[bs2] & BlockRegistry.F_GRAVITY) == 0:
				p.f.set_block(p.c, Vector3i(q.x, i + 1, q.z), fence)
				for yy2 in range(i + 2, i + j):
					p.f.set_block(p.c, Vector3i(q.x, yy2, q.z), chain)
				return
			up = j <= 50 and repl2
		j += 1

# ------------------------------------------------------------------ BuriedTreasurePieces

## Java BuriedTreasureStructure: one piece at chunk + 9 (y 90).
static func buried_treasure(sc: Vector2i) -> Dictionary:
	var pos := Vector3i(sc.x * 16 + 9, 90, sc.y * 16 + 9)
	var el := {"t": "java", "kind": "buried_treasure", "bmin": pos, "bmax": pos, "ori": ""}
	return {"pieces": [{"el": el, "pos": pos, "rot": 0, "box": [Vector3i(pos.x - 1, -64, pos.z - 1), Vector3i(pos.x + 1, 90, pos.z + 1)]}], "center": pos, "box": [pos, pos]}


## BuriedTreasurePiece.postProcess: from the OCEAN_FLOOR_WG height down to the first sandstone / stone / andesite /
## granite / diorite below; the 6 neighbours that are air or liquid become that stone (unless air / liquid below them
## and not up) or the block found there (sand when it was air / liquid); the chest goes there.
static func _buried_treasure(p: P) -> void:
	var b := p.b
	var x := p.bmin.x
	var z := p.bmin.z
	if not p.inside(Vector3i(x, 0, z)):
		return
	var y: int = p.f.height(p.c, "OCEAN_FLOOR_WG", x, z)
	var stones := {}
	for nm in ["sandstone", "stone", "andesite", "granite", "diorite"]:
		stones[b.default_state(nm)] = true
	var empty := func(st: int) -> bool: return st <= 0 or (b.st_flags[st] & BlockRegistry.F_LIQUID) != 0
	while y > p.f.gen.gen_min_y:
		var q := Vector3i(x, y, z)
		var bs := p.f.get_block(p.c, q)
		var bs1 := p.f.get_block(p.c, q + Vector3i(0, -1, 0))
		if stones.has(bs1):
			var bs2: int = bs if not empty.call(bs) else b.default_state("sand")
			for d in [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]:
				var bp: Vector3i = q + d
				if not p.inside(bp):
					continue
				var bs3 := p.f.get_block(p.c, bp)
				if empty.call(bs3):
					var bs4 := p.f.get_block(p.c, bp + Vector3i(0, -1, 0))
					if empty.call(bs4) and d != Vector3i(0, 1, 0):
						p.f.set_block(p.c, bp, bs1)
					else:
						p.f.set_block(p.c, bp, bs2)
			p.bmin = q
			p.bmax = q
			p.chest(x, y, z, "chests/buried_treasure")
			return
		y -= 1


# ------------------------------------------------------------------ NetherFortressPieces

## Java NetherFortressPieces piece weights: kind, weight, max count (0 = unlimited), allowed twice in a row.
const NF_BRIDGE := [["straight", 30, 0, true], ["crossing", 10, 4, false], ["room_crossing", 10, 4, false],
	["stairs_room", 10, 3, false], ["throne", 5, 2, false], ["entrance", 5, 1, false]]
const NF_CASTLE := [["c_corridor", 25, 0, true], ["c_crossing", 15, 5, false], ["c_right", 5, 10, false],
	["c_left", 5, 10, false], ["c_stairs", 10, 3, true], ["c_balcony", 7, 2, false], ["c_stalk", 5, 2, false]]
## createPiece boxes (BoundingBox.orientBox offset x, y, z, width, height, depth)
const NF_BOX := {"straight": [-1, -3, 0, 5, 10, 19], "crossing": [-8, -3, 0, 19, 10, 19], "room_crossing": [-2, 0, 0, 7, 9, 7],
	"stairs_room": [-2, 0, 0, 7, 11, 7], "throne": [-2, 0, 0, 7, 8, 9], "entrance": [-5, -3, 0, 13, 14, 13],
	"end": [-1, -3, 0, 5, 10, 8], "c_corridor": [-1, 0, 0, 5, 7, 5], "c_crossing": [-1, 0, 0, 5, 7, 5],
	"c_right": [-1, 0, 0, 5, 7, 5], "c_left": [-1, 0, 0, 5, 7, 5], "c_stairs": [-1, -7, 0, 5, 14, 10],
	"c_balcony": [-3, 0, 0, 9, 7, 9], "c_stalk": [-5, -3, 0, 13, 14, 13]}


## BoundingBox.orientBox
static func orient_box(x: int, y: int, z: int, ox: int, oy: int, oz: int, w: int, h: int, d: int, dir: String) -> Array:
	match dir:
		"north":
			return [Vector3i(x + ox, y + oy, z - d + 1 + oz), Vector3i(x + w - 1 + ox, y + h - 1 + oy, z + oz)]
		"west":
			return [Vector3i(x - d + 1 + oz, y + oy, z + ox), Vector3i(x + oz, y + h - 1 + oy, z + w - 1 + ox)]
		"east":
			return [Vector3i(x + oz, y + oy, z + ox), Vector3i(x + d - 1 + oz, y + h - 1 + oy, z + w - 1 + ox)]
	return [Vector3i(x + ox, y + oy, z + oz), Vector3i(x + w - 1 + ox, y + h - 1 + oy, z + d - 1 + oz)]


class NFStart:
	var pieces: Array = []
	var pending: Array = []
	var bridge: Array = []
	var castle: Array = []
	var prev := ""
	var x0 := 0
	var z0 := 0
	var r


## NetherFortressStructure.generatePieces: the start bridge crossing (random facing) at the chunk's (2, 64, 2), then
## children of a random pending piece until none are left; the whole fortress moved to a random height in 48..70.
static func fortress(_st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var s := NFStart.new()
	s.r = r
	var x := sc.x * 16 + 2
	var z := sc.y * 16 + 2
	var dir: String = DIRS[r.next_int_bound(4)]
	for w in NF_BRIDGE:
		s.bridge.append({"k": w[0], "w": w[1], "max": w[2], "row": w[3], "n": 0})
	for w2 in NF_CASTLE:
		s.castle.append({"k": w2[0], "w": w2[1], "max": w2[2], "row": w2[3], "n": 0})
	var start := {"k": "crossing", "min": Vector3i(x, 64, z), "max": Vector3i(x + 18, 73, z + 18), "ori": dir, "depth": 0}
	s.x0 = x
	s.z0 = z
	s.pieces.append(start)
	_nf_children(s, start)
	while not s.pending.is_empty():
		var i: int = r.next_int_bound(s.pending.size())
		var pc: Dictionary = s.pending.pop_at(i)
		_nf_children(s, pc)
	var bmin := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var bmax := -bmin
	for pc2 in s.pieces:
		bmin = bmin.min(pc2["min"])
		bmax = bmax.max(pc2["max"])
	# StructurePiecesBuilder.moveInsideHeights(random, 48, 70)
	var rng := 70 - 48 + 1 - (bmax.y - bmin.y + 1)
	var yy := 48 + r.next_int_bound(rng) if rng > 1 else 48
	var dy := Vector3i(0, yy - bmin.y, 0)
	var out: Array = []
	for pc3 in s.pieces:
		pc3["min"] = pc3["min"] + dy
		pc3["max"] = pc3["max"] + dy
		pc3["t"] = "java"
		pc3["kind"] = "fortress"
		out.append({"el": pc3, "pos": pc3["min"], "rot": 0, "box": [pc3["min"], pc3["max"]]})
	return {"pieces": out, "center": start["min"], "box": [bmin + dy, bmax + dy]}


static func _nf_children(s: NFStart, pc: Dictionary) -> void:
	match str(pc["k"]):
		"crossing":
			_nf_fwd(s, pc, 8, 3, false)
			_nf_left(s, pc, 3, 8, false)
			_nf_right(s, pc, 3, 8, false)
		"straight":
			_nf_fwd(s, pc, 1, 3, false)
		"room_crossing":
			_nf_fwd(s, pc, 2, 0, false)
			_nf_left(s, pc, 0, 2, false)
			_nf_right(s, pc, 0, 2, false)
		"stairs_room":
			_nf_right(s, pc, 6, 2, false)
		"entrance":
			_nf_fwd(s, pc, 5, 3, true)
		"c_corridor", "c_stairs":
			_nf_fwd(s, pc, 1, 0, true)
		"c_crossing":
			_nf_fwd(s, pc, 1, 0, true)
			_nf_left(s, pc, 0, 1, true)
			_nf_right(s, pc, 0, 1, true)
		"c_right":
			_nf_right(s, pc, 0, 1, true)
		"c_left":
			_nf_left(s, pc, 0, 1, true)
		"c_balcony":
			var i := 5 if pc["ori"] == "west" or pc["ori"] == "north" else 1
			_nf_left(s, pc, 0, i, s.r.next_int_bound(8) > 0)
			_nf_right(s, pc, 0, i, s.r.next_int_bound(8) > 0)
		"c_stalk":
			_nf_fwd(s, pc, 5, 3, true)
			_nf_fwd(s, pc, 5, 11, true)


## NetherBridgePiece.generateChildForward / Left / Right
static func _nf_fwd(s: NFStart, pc: Dictionary, xo: int, yo: int, castle: bool) -> void:
	var mn: Vector3i = pc["min"]
	var mx: Vector3i = pc["max"]
	var d: int = pc["depth"]
	match str(pc["ori"]):
		"north":
			_nf_add(s, mn.x + xo, mn.y + yo, mn.z - 1, "north", d, castle)
		"south":
			_nf_add(s, mn.x + xo, mn.y + yo, mx.z + 1, "south", d, castle)
		"west":
			_nf_add(s, mn.x - 1, mn.y + yo, mn.z + xo, "west", d, castle)
		"east":
			_nf_add(s, mx.x + 1, mn.y + yo, mn.z + xo, "east", d, castle)


static func _nf_left(s: NFStart, pc: Dictionary, yo: int, zo: int, castle: bool) -> void:
	var mn: Vector3i = pc["min"]
	var d: int = pc["depth"]
	if pc["ori"] == "north" or pc["ori"] == "south":
		_nf_add(s, mn.x - 1, mn.y + yo, mn.z + zo, "west", d, castle)
	else:
		_nf_add(s, mn.x + zo, mn.y + yo, mn.z - 1, "north", d, castle)


static func _nf_right(s: NFStart, pc: Dictionary, yo: int, zo: int, castle: bool) -> void:
	var mn: Vector3i = pc["min"]
	var mx: Vector3i = pc["max"]
	var d: int = pc["depth"]
	if pc["ori"] == "north" or pc["ori"] == "south":
		_nf_add(s, mx.x + 1, mn.y + yo, mn.z + zo, "east", d, castle)
	else:
		_nf_add(s, mn.x + zo, mn.y + yo, mx.z + 1, "south", d, castle)


## generateAndAddPiece: beyond 112 blocks from the start a bridge end filler is made (and dropped, as in Java).
static func _nf_add(s: NFStart, x: int, y: int, z: int, dir: String, depth: int, castle: bool) -> void:
	if absi(x - s.x0) > 112 or absi(z - s.z0) > 112:
		_nf_create(s, "end", x, y, z, dir, depth)
		return
	var pc = _nf_generate(s, s.castle if castle else s.bridge, x, y, z, dir, depth + 1)
	if pc != null:
		s.pieces.append(pc)
		s.pending.append(pc)


## NetherBridgePiece.generatePiece: up to 5 weighted picks (a failed placement falls through to the next entries of
## the same pick), else a bridge end filler.
static func _nf_generate(s: NFStart, weights: Array, x: int, y: int, z: int, dir: String, depth: int):
	var total := 0
	var valid := false
	for w in weights:
		if int(w["max"]) > 0 and int(w["n"]) < int(w["max"]):
			valid = true
		total += int(w["w"])
	var ok := valid and total > 0 and depth <= 30
	var attempts := 0
	while attempts < 5 and ok:
		attempts += 1
		var pick: int = s.r.next_int_bound(total)
		for w2 in weights:
			pick -= int(w2["w"])
			if pick < 0:
				var mx := int(w2["max"])
				if not (mx == 0 or int(w2["n"]) < mx) or (str(w2["k"]) == s.prev and not bool(w2["row"])):
					break
				var pc = _nf_create(s, str(w2["k"]), x, y, z, dir, depth)
				if pc != null:
					w2["n"] = int(w2["n"]) + 1
					s.prev = str(w2["k"])
					if not (mx == 0 or int(w2["n"]) < mx):
						weights.erase(w2)
					return pc
	return _nf_create(s, "end", x, y, z, dir, depth)


## Piece createPiece: the oriented box must clear y 10 and every placed piece; constructors draw their random.
static func _nf_create(s: NFStart, k: String, x: int, y: int, z: int, dir: String, depth: int):
	var bx: Array = NF_BOX[k]
	var b := orient_box(x, y, z, bx[0], bx[1], bx[2], bx[3], bx[4], bx[5], dir)
	if b[0].y <= 10 or _collides(s.pieces, b[0], b[1]):
		return null
	var pc := {"k": k, "min": b[0], "max": b[1], "ori": dir, "depth": depth}
	if k == "end":
		pc["seed"] = s.r.next_int()
	elif k == "c_right" or k == "c_left":
		pc["chest"] = s.r.next_int_bound(3) == 0
	return pc


static func _place_fortress(p: P, el: Dictionary) -> void:
	var nb := p.s("nether_bricks")
	var fe := p.s("nether_brick_fence")
	match str(el["k"]):
		"crossing":
			_nf_bridge_crossing(p, nb)
		"end":
			_nf_end(p, nb, int(el["seed"]))
		"straight":
			_nf_straight(p, nb, fe)
		"room_crossing":
			_nf_room_crossing(p, nb, fe)
		"stairs_room":
			_nf_stairs_room(p, nb, fe)
		"throne":
			_nf_throne(p, nb, fe)
		"entrance":
			_nf_castle_hall(p, nb, fe, false)
		"c_stalk":
			_nf_castle_hall(p, nb, fe, true)
		"c_corridor":
			_nf_small_corridor(p, nb, fe)
		"c_crossing":
			_nf_small_crossing(p, nb)
		"c_right":
			_nf_turn(p, nb, fe, el, true)
		"c_left":
			_nf_turn(p, nb, fe, el, false)
		"c_stairs":
			_nf_corridor_stairs(p, nb, fe)
		"c_balcony":
			_nf_balcony(p, nb, fe)


static func _nf_down(p: P, nb: int, x0: int, x1: int, z0: int, z1: int) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			p.column_down(nb, x, -1, z)


static func _nf_bridge_crossing(p: P, nb: int) -> void:
	p.box(7, 3, 0, 11, 4, 18, nb, nb)
	p.box(0, 3, 7, 18, 4, 11, nb, nb)
	p.air(8, 5, 0, 10, 7, 18)
	p.air(0, 5, 8, 18, 7, 10)
	p.box(7, 5, 0, 7, 5, 7, nb, nb)
	p.box(7, 5, 11, 7, 5, 18, nb, nb)
	p.box(11, 5, 0, 11, 5, 7, nb, nb)
	p.box(11, 5, 11, 11, 5, 18, nb, nb)
	p.box(0, 5, 7, 7, 5, 7, nb, nb)
	p.box(11, 5, 7, 18, 5, 7, nb, nb)
	p.box(0, 5, 11, 7, 5, 11, nb, nb)
	p.box(11, 5, 11, 18, 5, 11, nb, nb)
	p.box(7, 2, 0, 11, 2, 5, nb, nb)
	p.box(7, 2, 13, 11, 2, 18, nb, nb)
	p.box(7, 0, 0, 11, 1, 3, nb, nb)
	p.box(7, 0, 15, 11, 1, 18, nb, nb)
	for x in range(7, 12):
		for z in 3:
			p.column_down(nb, x, -1, z)
			p.column_down(nb, x, -1, 18 - z)
	p.box(0, 2, 7, 5, 2, 11, nb, nb)
	p.box(13, 2, 7, 18, 2, 11, nb, nb)
	p.box(0, 0, 7, 3, 1, 11, nb, nb)
	p.box(15, 0, 7, 18, 1, 11, nb, nb)
	for x2 in 3:
		for z2 in range(7, 12):
			p.column_down(nb, x2, -1, z2)
			p.column_down(nb, 18 - x2, -1, z2)


static func _nf_end(p: P, nb: int, seed: int) -> void:
	var rr := RandomSources.LegacyRandom.new(seed)
	for x in 5:
		for y in range(3, 5):
			var zz := rr.next_int_bound(8)
			p.box(x, y, 0, x, y, zz, nb, nb)
	var z1 := rr.next_int_bound(8)
	p.box(0, 5, 0, 0, 5, z1, nb, nb)
	z1 = rr.next_int_bound(8)
	p.box(4, 5, 0, 4, 5, z1, nb, nb)
	for x2 in 5:
		var z2 := rr.next_int_bound(5)
		p.box(x2, 2, 0, x2, 2, z2, nb, nb)
	for x3 in 5:
		for y3 in 2:
			var z3 := rr.next_int_bound(3)
			p.box(x3, y3, 0, x3, y3, z3, nb, nb)


static func _nf_straight(p: P, nb: int, fe: int) -> void:
	p.box(0, 3, 0, 4, 4, 18, nb, nb)
	p.air(1, 5, 0, 3, 7, 18)
	p.box(0, 5, 0, 0, 5, 18, nb, nb)
	p.box(4, 5, 0, 4, 5, 18, nb, nb)
	p.box(0, 2, 0, 4, 2, 5, nb, nb)
	p.box(0, 2, 13, 4, 2, 18, nb, nb)
	p.box(0, 0, 0, 4, 1, 3, nb, nb)
	p.box(0, 0, 15, 4, 1, 18, nb, nb)
	for x in 5:
		for z in 3:
			p.column_down(nb, x, -1, z)
			p.column_down(nb, x, -1, 18 - z)
	for xx in [0, 4]:
		p.box(xx, 1, 1, xx, 4, 1, fe, fe)
		p.box(xx, 3, 4, xx, 4, 4, fe, fe)
		p.box(xx, 3, 14, xx, 4, 14, fe, fe)
		p.box(xx, 1, 17, xx, 4, 17, fe, fe)


static func _nf_room_crossing(p: P, nb: int, fe: int) -> void:
	p.box(0, 0, 0, 6, 1, 6, nb, nb)
	p.air(0, 2, 0, 6, 7, 6)
	p.box(0, 2, 0, 1, 6, 0, nb, nb)
	p.box(0, 2, 6, 1, 6, 6, nb, nb)
	p.box(5, 2, 0, 6, 6, 0, nb, nb)
	p.box(5, 2, 6, 6, 6, 6, nb, nb)
	p.box(0, 2, 0, 0, 6, 1, nb, nb)
	p.box(0, 2, 5, 0, 6, 6, nb, nb)
	p.box(6, 2, 0, 6, 6, 1, nb, nb)
	p.box(6, 2, 5, 6, 6, 6, nb, nb)
	p.box(2, 6, 0, 4, 6, 0, nb, nb)
	p.box(2, 5, 0, 4, 5, 0, fe, fe)
	p.box(2, 6, 6, 4, 6, 6, nb, nb)
	p.box(2, 5, 6, 4, 5, 6, fe, fe)
	p.box(0, 6, 2, 0, 6, 4, nb, nb)
	p.box(0, 5, 2, 0, 5, 4, fe, fe)
	p.box(6, 6, 2, 6, 6, 4, nb, nb)
	p.box(6, 5, 2, 6, 5, 4, fe, fe)
	_nf_down(p, nb, 0, 6, 0, 6)


static func _nf_stairs_room(p: P, nb: int, fe: int) -> void:
	p.box(0, 0, 0, 6, 1, 6, nb, nb)
	p.air(0, 2, 0, 6, 10, 6)
	p.box(0, 2, 0, 1, 8, 0, nb, nb)
	p.box(5, 2, 0, 6, 8, 0, nb, nb)
	p.box(0, 2, 1, 0, 8, 6, nb, nb)
	p.box(6, 2, 1, 6, 8, 6, nb, nb)
	p.box(1, 2, 6, 5, 8, 6, nb, nb)
	p.box(0, 3, 2, 0, 5, 4, fe, fe)
	p.box(6, 3, 2, 6, 5, 2, fe, fe)
	p.box(6, 3, 4, 6, 5, 4, fe, fe)
	p.place(nb, 5, 2, 5)
	p.box(4, 2, 5, 4, 3, 5, nb, nb)
	p.box(3, 2, 5, 3, 4, 5, nb, nb)
	p.box(2, 2, 5, 2, 5, 5, nb, nb)
	p.box(1, 2, 5, 1, 6, 5, nb, nb)
	p.box(1, 7, 1, 5, 7, 4, nb, nb)
	p.air(6, 8, 2, 6, 8, 4)
	p.box(2, 6, 0, 4, 8, 0, nb, nb)
	p.box(2, 5, 0, 4, 5, 0, fe, fe)
	_nf_down(p, nb, 0, 6, 0, 6)


static func _nf_throne(p: P, nb: int, fe: int) -> void:
	p.air(0, 2, 0, 6, 7, 7)
	p.box(1, 0, 0, 5, 1, 7, nb, nb)
	p.box(1, 2, 1, 5, 2, 7, nb, nb)
	p.box(1, 3, 2, 5, 3, 7, nb, nb)
	p.box(1, 4, 3, 5, 4, 7, nb, nb)
	p.box(1, 2, 0, 1, 4, 2, nb, nb)
	p.box(5, 2, 0, 5, 4, 2, nb, nb)
	p.box(1, 5, 2, 1, 5, 3, nb, nb)
	p.box(5, 5, 2, 5, 5, 3, nb, nb)
	p.box(0, 5, 3, 0, 5, 8, nb, nb)
	p.box(6, 5, 3, 6, 5, 8, nb, nb)
	p.box(1, 5, 8, 5, 5, 8, nb, nb)
	p.place(fe, 1, 6, 3)
	p.place(fe, 5, 6, 3)
	p.box(0, 6, 3, 0, 6, 8, fe, fe)
	p.box(6, 6, 3, 6, 6, 8, fe, fe)
	p.box(1, 6, 8, 5, 7, 8, fe, fe)
	p.box(2, 8, 8, 4, 8, 8, fe, fe)
	var sp := p.wpos(3, 5, 5)
	if p.inside(sp):
		p.f.set_block(p.c, sp, p.s("spawner"))
		p.c.block_entities[sp] = {"id": "spawner", "mob": "blaze"}
	_nf_down(p, nb, 0, 6, 0, 6)


## CastleEntrance and CastleStalkRoom share the 13 x 14 x 13 hall shell; the entrance has the lava well, the stalk
## room the stairs and nether wart beds.
static func _nf_castle_hall(p: P, nb: int, fe: int, stalk: bool) -> void:
	p.box(0, 3, 0, 12, 4, 12, nb, nb)
	p.air(0, 5, 0, 12, 13, 12)
	p.box(0, 5, 0, 1, 12, 12, nb, nb)
	p.box(11, 5, 0, 12, 12, 12, nb, nb)
	p.box(2, 5, 11, 4, 12, 12, nb, nb)
	p.box(8, 5, 11, 10, 12, 12, nb, nb)
	p.box(5, 9, 11, 7, 12, 12, nb, nb)
	p.box(2, 5, 0, 4, 12, 1, nb, nb)
	p.box(8, 5, 0, 10, 12, 1, nb, nb)
	p.box(5, 9, 0, 7, 12, 1, nb, nb)
	p.box(2, 11, 2, 10, 12, 10, nb, nb)
	if not stalk:
		p.box(5, 8, 0, 7, 8, 0, fe, fe)
	var i := 1
	while i <= 11:
		p.box(i, 10, 0, i, 11, 0, fe, fe)
		p.box(i, 10, 12, i, 11, 12, fe, fe)
		p.box(0, 10, i, 0, 11, i, fe, fe)
		p.box(12, 10, i, 12, 11, i, fe, fe)
		p.place(nb, i, 13, 0)
		p.place(nb, i, 13, 12)
		p.place(nb, 0, 13, i)
		p.place(nb, 12, 13, i)
		if i != 11:
			p.place(fe, i + 1, 13, 0)
			p.place(fe, i + 1, 13, 12)
			p.place(fe, 0, 13, i + 1)
			p.place(fe, 12, 13, i + 1)
		i += 2
	p.place(fe, 0, 13, 0)
	p.place(fe, 0, 13, 12)
	p.place(fe, 12, 13, 12)
	p.place(fe, 12, 13, 0)
	var k := 3
	while k <= 9:
		p.box(1, 7, k, 1, 8, k, fe, fe)
		p.box(11, 7, k, 11, 8, k, fe, fe)
		k += 2
	if stalk:
		var sn := _stairs(p, "nether_brick_stairs", "north")
		for j in 7:
			var zz := j + 4
			for x in range(5, 8):
				p.place(sn, x, 5 + j, zz)
			if zz >= 5 and zz <= 8:
				p.box(5, 5, zz, 7, j + 4, zz, nb, nb)
			elif zz >= 9 and zz <= 10:
				p.box(5, 8, zz, 7, j + 4, zz, nb, nb)
			if j >= 1:
				p.air(5, 6 + j, zz, 7, 9 + j, zz)
		for x2 in range(5, 8):
			p.place(sn, x2, 12, 11)
		p.box(5, 6, 7, 5, 7, 7, fe, fe)
		p.box(7, 6, 7, 7, 7, 7, fe, fe)
		p.air(5, 13, 12, 7, 13, 12)
		p.box(2, 5, 2, 3, 5, 3, nb, nb)
		p.box(2, 5, 9, 3, 5, 10, nb, nb)
		p.box(2, 5, 4, 2, 5, 8, nb, nb)
		p.box(9, 5, 2, 10, 5, 3, nb, nb)
		p.box(9, 5, 9, 10, 5, 10, nb, nb)
		p.box(10, 5, 4, 10, 5, 8, nb, nb)
		var se := _stairs(p, "nether_brick_stairs", "east")
		var sw := _stairs(p, "nether_brick_stairs", "west")
		for zz2 in [2, 3, 9, 10]:
			p.place(sw, 4, 5, zz2)
			p.place(se, 8, 5, zz2)
		var soul := p.s("soul_sand")
		var wart := p.s("nether_wart")
		p.box(3, 4, 4, 4, 4, 8, soul, soul)
		p.box(8, 4, 4, 9, 4, 8, soul, soul)
		p.box(3, 5, 4, 4, 5, 8, wart, wart)
		p.box(8, 5, 4, 9, 5, 8, wart, wart)
	p.box(4, 2, 0, 8, 2, 12, nb, nb)
	p.box(0, 2, 4, 12, 2, 8, nb, nb)
	p.box(4, 0, 0, 8, 1, 3, nb, nb)
	p.box(4, 0, 9, 8, 1, 12, nb, nb)
	p.box(0, 0, 4, 3, 1, 8, nb, nb)
	p.box(9, 0, 4, 12, 1, 8, nb, nb)
	for x3 in range(4, 9):
		for z3 in 3:
			p.column_down(nb, x3, -1, z3)
			p.column_down(nb, x3, -1, 12 - z3)
	for x4 in 3:
		for z4 in range(4, 9):
			p.column_down(nb, x4, -1, z4)
			p.column_down(nb, 12 - x4, -1, z4)
	if not stalk:
		p.box(5, 5, 5, 7, 5, 7, nb, nb)
		p.air(6, 1, 6, 6, 4, 6)
		p.place(nb, 6, 0, 6)
		p.place(p.s("lava"), 6, 5, 6)


static func _nf_small_corridor(p: P, nb: int, fe: int) -> void:
	p.box(0, 0, 0, 4, 1, 4, nb, nb)
	p.air(0, 2, 0, 4, 5, 4)
	p.box(0, 2, 0, 0, 5, 4, nb, nb)
	p.box(4, 2, 0, 4, 5, 4, nb, nb)
	p.box(0, 3, 1, 0, 4, 1, fe, fe)
	p.box(0, 3, 3, 0, 4, 3, fe, fe)
	p.box(4, 3, 1, 4, 4, 1, fe, fe)
	p.box(4, 3, 3, 4, 4, 3, fe, fe)
	p.box(0, 6, 0, 4, 6, 4, nb, nb)
	_nf_down(p, nb, 0, 4, 0, 4)


static func _nf_small_crossing(p: P, nb: int) -> void:
	p.box(0, 0, 0, 4, 1, 4, nb, nb)
	p.air(0, 2, 0, 4, 5, 4)
	p.box(0, 2, 0, 0, 5, 0, nb, nb)
	p.box(4, 2, 0, 4, 5, 0, nb, nb)
	p.box(0, 2, 4, 0, 5, 4, nb, nb)
	p.box(4, 2, 4, 4, 5, 4, nb, nb)
	p.box(0, 6, 0, 4, 6, 4, nb, nb)
	_nf_down(p, nb, 0, 4, 0, 4)


## CastleSmallCorridorRightTurnPiece / LeftTurnPiece (a chest in one of three).
static func _nf_turn(p: P, nb: int, fe: int, el: Dictionary, right: bool) -> void:
	p.box(0, 0, 0, 4, 1, 4, nb, nb)
	p.air(0, 2, 0, 4, 5, 4)
	if right:
		p.box(0, 2, 0, 0, 5, 4, nb, nb)
		p.box(0, 3, 1, 0, 4, 1, fe, fe)
		p.box(0, 3, 3, 0, 4, 3, fe, fe)
		p.box(4, 2, 0, 4, 5, 0, nb, nb)
		p.box(1, 2, 4, 4, 5, 4, nb, nb)
	else:
		p.box(4, 2, 0, 4, 5, 4, nb, nb)
		p.box(4, 3, 1, 4, 4, 1, fe, fe)
		p.box(4, 3, 3, 4, 4, 3, fe, fe)
		p.box(0, 2, 0, 0, 5, 0, nb, nb)
		p.box(0, 2, 4, 3, 5, 4, nb, nb)
	p.box(1, 3, 4, 1, 4, 4, fe, fe)
	p.box(3, 3, 4, 3, 4, 4, fe, fe)
	if bool(el.get("chest", false)):
		p.chest(1 if right else 3, 2, 3, "chests/nether_bridge")
	p.box(0, 6, 0, 4, 6, 4, nb, nb)
	_nf_down(p, nb, 0, 4, 0, 4)


static func _nf_corridor_stairs(p: P, nb: int, fe: int) -> void:
	var st := _stairs(p, "nether_brick_stairs", "south")
	for i in 10:
		var j := maxi(1, 7 - i)
		var k := mini(maxi(j + 5, 14 - i), 13)
		p.box(0, 0, i, 4, j, i, nb, nb)
		p.air(1, j + 1, i, 3, k - 1, i)
		if i <= 6:
			p.place(st, 1, j + 1, i)
			p.place(st, 2, j + 1, i)
			p.place(st, 3, j + 1, i)
		p.box(0, k, i, 4, k, i, nb, nb)
		p.box(0, j + 1, i, 0, k - 1, i, nb, nb)
		p.box(4, j + 1, i, 4, k - 1, i, nb, nb)
		if (i & 1) == 0:
			p.box(0, j + 2, i, 0, j + 3, i, fe, fe)
			p.box(4, j + 2, i, 4, j + 3, i, fe, fe)
		for x in 5:
			p.column_down(nb, x, -1, i)


static func _nf_balcony(p: P, nb: int, fe: int) -> void:
	p.box(0, 0, 0, 8, 1, 8, nb, nb)
	p.air(0, 2, 0, 8, 5, 8)
	p.box(0, 6, 0, 8, 6, 5, nb, nb)
	p.box(0, 2, 0, 2, 5, 0, nb, nb)
	p.box(6, 2, 0, 8, 5, 0, nb, nb)
	p.box(1, 3, 0, 1, 4, 0, fe, fe)
	p.box(7, 3, 0, 7, 4, 0, fe, fe)
	p.box(0, 2, 4, 8, 2, 8, nb, nb)
	p.air(1, 1, 4, 2, 2, 4)
	p.air(6, 1, 4, 7, 2, 4)
	p.box(1, 3, 8, 7, 3, 8, fe, fe)
	p.place(fe, 0, 3, 8)
	p.place(fe, 8, 3, 8)
	p.box(0, 3, 6, 0, 3, 7, fe, fe)
	p.box(8, 3, 6, 8, 3, 7, fe, fe)
	p.box(0, 3, 4, 0, 5, 5, nb, nb)
	p.box(8, 3, 4, 8, 5, 5, nb, nb)
	p.box(1, 3, 5, 2, 5, 5, nb, nb)
	p.box(6, 3, 5, 7, 5, 5, nb, nb)
	p.box(1, 4, 5, 1, 5, 5, fe, fe)
	p.box(7, 4, 5, 7, 5, 5, fe, fe)
	_nf_down(p, nb, 0, 8, 0, 5)


# ------------------------------------------------------------------ StrongholdPieces

## Java StrongholdPieces.STRONGHOLD_PIECE_WEIGHTS: kind, weight, max count (0 = unlimited), minimum depth exclusive
## (library > 4, portal room > 5).
const SH_WEIGHTS := [["straight", 40, 0, -1], ["prison", 5, 5, -1], ["left_turn", 20, 0, -1], ["right_turn", 20, 0, -1],
	["room_crossing", 10, 6, -1], ["straight_stairs", 5, 5, -1], ["stairs_down", 5, 5, -1], ["five_crossing", 5, 4, -1],
	["chest_corridor", 5, 4, -1], ["library", 10, 2, 4], ["portal_room", 20, 1, 5]]
const SH_BOX := {"straight": [-1, -1, 0, 5, 5, 7], "prison": [-1, -1, 0, 9, 5, 11], "left_turn": [-1, -1, 0, 5, 5, 5],
	"right_turn": [-1, -1, 0, 5, 5, 5], "room_crossing": [-4, -1, 0, 11, 7, 11], "straight_stairs": [-1, -7, 0, 5, 11, 8],
	"stairs_down": [-1, -7, 0, 5, 11, 5], "five_crossing": [-4, -3, 0, 10, 9, 11], "chest_corridor": [-1, -1, 0, 5, 5, 7],
	"library": [-4, -1, 0, 14, 11, 15], "portal_room": [-4, -1, 0, 11, 8, 16]}
enum { DOOR_OPENING, DOOR_WOOD, DOOR_GRATES, DOOR_IRON }


class SHStart:
	var pieces: Array = []
	var pending: Array = []
	var weights: Array = []
	var total := 0
	var prev := ""
	var imposed := ""
	var portal = null
	var x0 := 0
	var z0 := 0
	var r


## StrongholdStructure.generatePieces: retried with world seed + attempt until a portal room was placed; the start
## spiral stairs (random facing) at the chunk's (2, 64, 2), a five-way crossing forced next, children of random
## pending pieces, then moveBelowSeaLevel(sea, minY, random, 10).
static func stronghold(st: Structures, sc: Vector2i) -> Dictionary:
	return stronghold_for(st.gen.seed, st.gen.sea_level, st.gen.gen_min_y, sc)


static func stronghold_for(world_seed: int, sea_level: int, min_y: int, sc: Vector2i) -> Dictionary:
	var attempt := 0
	var s: SHStart
	var start: Dictionary
	while true:
		var r := Structures.large_feature_seed(world_seed + attempt, sc.x, sc.y)
		attempt += 1
		s = SHStart.new()
		s.r = r
		for w in SH_WEIGHTS:
			s.weights.append({"k": w[0], "w": w[1], "max": w[2], "min_depth": w[3], "n": 0})
		var x := sc.x * 16 + 2
		var z := sc.y * 16 + 2
		var dir: String = DIRS[r.next_int_bound(4)]
		start = {"k": "stairs_down", "min": Vector3i(x, 64, z), "max": Vector3i(x + 4, 74, z + 4), "ori": dir, "depth": 0, "door": DOOR_OPENING, "src": true}
		s.x0 = x
		s.z0 = z
		s.pieces.append(start)
		_sh_children(s, start)
		while not s.pending.is_empty():
			var i: int = r.next_int_bound(s.pending.size())
			var pc: Dictionary = s.pending.pop_at(i)
			_sh_children(s, pc)
		# moveBelowSeaLevel
		var bmin := Vector3i(1 << 30, 1 << 30, 1 << 30)
		var bmax := -bmin
		for pc2 in s.pieces:
			bmin = bmin.min(pc2["min"])
			bmax = bmax.max(pc2["max"])
		var lim: int = sea_level - 10
		var j: int = (bmax.y - bmin.y + 1) + min_y + 1
		if j < lim:
			j += r.next_int_bound(lim - j)
		var dy := Vector3i(0, j - bmax.y, 0)
		for pc3 in s.pieces:
			pc3["min"] = pc3["min"] + dy
			pc3["max"] = pc3["max"] + dy
		if s.portal != null or attempt > 64:
			break
	var out: Array = []
	var omin := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var omax := -omin
	for pc4 in s.pieces:
		pc4["t"] = "java"
		pc4["kind"] = "stronghold"
		omin = omin.min(pc4["min"])
		omax = omax.max(pc4["max"])
		out.append({"el": pc4, "pos": pc4["min"], "rot": 0, "box": [pc4["min"], pc4["max"]]})
	var ctr: Vector3i = start["min"]
	if s.portal != null:
		ctr = (s.portal["min"] + s.portal["max"]) / 2
	return {"pieces": out, "center": ctr, "box": [omin, omax]}


static func _sh_children(s: SHStart, pc: Dictionary) -> void:
	match str(pc["k"]):
		"stairs_down":
			if bool(pc.get("src", false)):
				s.imposed = "five_crossing"
			_sh_fwd(s, pc, 1, 1)
		"straight":
			_sh_fwd(s, pc, 1, 1)
			if pc["left"]:
				_sh_left(s, pc, 1, 2)
			if pc["right"]:
				_sh_right(s, pc, 1, 2)
		"chest_corridor", "prison", "straight_stairs":
			_sh_fwd(s, pc, 1, 1)
		"left_turn":
			if pc["ori"] != "north" and pc["ori"] != "east":
				_sh_right(s, pc, 1, 1)
			else:
				_sh_left(s, pc, 1, 1)
		"right_turn":
			if pc["ori"] != "north" and pc["ori"] != "east":
				_sh_left(s, pc, 1, 1)
			else:
				_sh_right(s, pc, 1, 1)
		"room_crossing":
			_sh_fwd(s, pc, 4, 1)
			_sh_left(s, pc, 1, 4)
			_sh_right(s, pc, 1, 4)
		"five_crossing":
			var i := 3
			var j := 5
			if pc["ori"] == "west" or pc["ori"] == "north":
				i = 8 - i
				j = 8 - j
			_sh_fwd(s, pc, 5, 1)
			if pc["ll"]:
				_sh_left(s, pc, i, 1)
			if pc["lh"]:
				_sh_left(s, pc, j, 7)
			if pc["rl"]:
				_sh_right(s, pc, i, 1)
			if pc["rh"]:
				_sh_right(s, pc, j, 7)
		"portal_room":
			s.portal = pc


static func _sh_fwd(s: SHStart, pc: Dictionary, xo: int, yo: int) -> void:
	var mn: Vector3i = pc["min"]
	var mx: Vector3i = pc["max"]
	var d: int = pc["depth"]
	match str(pc["ori"]):
		"north":
			_sh_add(s, mn.x + xo, mn.y + yo, mn.z - 1, "north", d)
		"south":
			_sh_add(s, mn.x + xo, mn.y + yo, mx.z + 1, "south", d)
		"west":
			_sh_add(s, mn.x - 1, mn.y + yo, mn.z + xo, "west", d)
		"east":
			_sh_add(s, mx.x + 1, mn.y + yo, mn.z + xo, "east", d)


static func _sh_left(s: SHStart, pc: Dictionary, yo: int, zo: int) -> void:
	var mn: Vector3i = pc["min"]
	var d: int = pc["depth"]
	if pc["ori"] == "north" or pc["ori"] == "south":
		_sh_add(s, mn.x - 1, mn.y + yo, mn.z + zo, "west", d)
	else:
		_sh_add(s, mn.x + zo, mn.y + yo, mn.z - 1, "north", d)


static func _sh_right(s: SHStart, pc: Dictionary, yo: int, zo: int) -> void:
	var mn: Vector3i = pc["min"]
	var mx: Vector3i = pc["max"]
	var d: int = pc["depth"]
	if pc["ori"] == "north" or pc["ori"] == "south":
		_sh_add(s, mx.x + 1, mn.y + yo, mn.z + zo, "east", d)
	else:
		_sh_add(s, mn.x + zo, mn.y + yo, mx.z + 1, "south", d)


## generateAndAddPiece: depth <= 50, within 112 blocks of the start.
static func _sh_add(s: SHStart, x: int, y: int, z: int, dir: String, depth: int) -> void:
	if depth > 50 or absi(x - s.x0) > 112 or absi(z - s.z0) > 112:
		return
	var pc = _sh_from_door(s, x, y, z, dir, depth + 1)
	if pc != null:
		s.pieces.append(pc)
		s.pending.append(pc)


## generatePieceFromSmallDoor: the imposed piece first, 5 weighted picks, else a filler corridor up to the piece
## in the way.
static func _sh_from_door(s: SHStart, x: int, y: int, z: int, dir: String, depth: int):
	var valid := false
	s.total = 0
	for w in s.weights:
		if int(w["max"]) > 0 and int(w["n"]) < int(w["max"]):
			valid = true
		s.total += int(w["w"])
	if not valid:
		return null
	if s.imposed != "":
		var ip = _sh_create(s, s.imposed, x, y, z, dir, depth)
		s.imposed = ""
		if ip != null:
			return ip
	var attempts := 0
	while attempts < 5:
		attempts += 1
		var pick: int = s.r.next_int_bound(s.total)
		for w2 in s.weights:
			pick -= int(w2["w"])
			if pick < 0:
				var mx := int(w2["max"])
				var can := (mx == 0 or int(w2["n"]) < mx) and depth > int(w2["min_depth"])
				if not can or str(w2["k"]) == s.prev:
					break
				var pc = _sh_create(s, str(w2["k"]), x, y, z, dir, depth)
				if pc != null:
					w2["n"] = int(w2["n"]) + 1
					s.prev = str(w2["k"])
					if not (mx == 0 or int(w2["n"]) < mx):
						s.weights.erase(w2)
					return pc
	# FillerCorridor.findPieceBox
	var fb := orient_box(x, y, z, -1, -1, 0, 5, 5, 4, dir)
	var hit = _sh_hit(s.pieces, fb[0], fb[1])
	if hit == null or hit["min"].y != fb[0].y:
		return null
	for i in range(3, 0, -1):
		var tb := orient_box(x, y, z, -1, -1, 0, 5, 5, i - 1, dir)
		var hm: Vector3i = hit["min"]
		var hx: Vector3i = hit["max"]
		if not (hx.x >= tb[0].x and hm.x <= tb[1].x and hx.y >= tb[0].y and hm.y <= tb[1].y and hx.z >= tb[0].z and hm.z <= tb[1].z):
			var box := orient_box(x, y, z, -1, -1, 0, 5, 5, i, dir)
			if box[0].y <= 1:
				return null
			var steps: int = (box[1].z - box[0].z + 1) if dir == "north" or dir == "south" else (box[1].x - box[0].x + 1)
			return {"k": "filler", "min": box[0], "max": box[1], "ori": dir, "depth": depth, "steps": steps}
	return null


static func _sh_hit(pieces: Array, mn: Vector3i, mx: Vector3i):
	for pc in pieces:
		var a: Vector3i = pc["min"]
		var b2: Vector3i = pc["max"]
		if mx.x >= a.x and mn.x <= b2.x and mx.z >= a.z and mn.z <= b2.z and mx.y >= a.y and mn.y <= b2.y:
			return pc
	return null


## createPiece for each kind (isOkBox: min y > 10, no collision), then the constructor's random draws.
static func _sh_create(s: SHStart, k: String, x: int, y: int, z: int, dir: String, depth: int):
	var bx: Array = SH_BOX[k]
	var b := orient_box(x, y, z, bx[0], bx[1], bx[2], bx[3], bx[4], bx[5], dir)
	if b[0].y <= 10 or _collides(s.pieces, b[0], b[1]):
		if k != "library":
			return null
		b = orient_box(x, y, z, bx[0], bx[1], bx[2], bx[3], 6, bx[5], dir)
		if b[0].y <= 10 or _collides(s.pieces, b[0], b[1]):
			return null
	var pc := {"k": k, "min": b[0], "max": b[1], "ori": dir, "depth": depth, "door": DOOR_OPENING}
	if k == "portal_room":
		return pc
	pc["door"] = _sh_random_door(s.r)
	match k:
		"straight":
			pc["left"] = s.r.next_int_bound(2) == 0
			pc["right"] = s.r.next_int_bound(2) == 0
		"room_crossing":
			pc["type"] = s.r.next_int_bound(5)
		"five_crossing":
			pc["ll"] = s.r.next_bool()
			pc["lh"] = s.r.next_bool()
			pc["rl"] = s.r.next_bool()
			pc["rh"] = s.r.next_int_bound(3) > 0
		"library":
			pc["tall"] = b[1].y - b[0].y + 1 > 6
	return pc


static func _sh_random_door(r) -> int:
	match r.next_int_bound(5):
		2:
			return DOOR_WOOD
		3:
			return DOOR_GRATES
		4:
			return DOOR_IRON
	return DOOR_OPENING


# --- placement

static func _place_stronghold(p: P, el: Dictionary) -> void:
	var sb := p.s("stone_bricks")
	var ca := p.s("cave_air")
	var slab := p.s("smooth_stone_slab")
	var r = p.r
	var cracked := p.s("cracked_stone_bricks")
	var mossy := p.s("mossy_stone_bricks")
	var infested := p.s("infested_stone_bricks")
	# StrongholdPieces.SmoothStoneSelector
	var sel := func(wall: bool) -> int:
		if not wall:
			return ca
		var f: float = r.next_float()
		if f < 0.2:
			return cracked
		if f < 0.5:
			return mossy
		if f < 0.55:
			return infested
		return sb
	var door: int = el.get("door", DOOR_OPENING)
	match str(el["k"]):
		"stairs_down":
			p.box_sel(0, 0, 0, 4, 10, 4, true, sel)
			_sh_door(p, door, 1, 7, 0)
			_sh_door(p, DOOR_OPENING, 1, 1, 4)
			for q in [[sb, 2, 6, 1], [sb, 1, 5, 1], [slab, 1, 6, 1], [sb, 1, 5, 2], [sb, 1, 4, 3], [slab, 1, 5, 3], [sb, 2, 4, 3],
					[sb, 3, 3, 3], [slab, 3, 4, 3], [sb, 3, 3, 2], [sb, 3, 2, 1], [slab, 3, 3, 1], [sb, 2, 2, 1], [sb, 1, 1, 1],
					[slab, 1, 2, 1], [sb, 1, 1, 2], [slab, 1, 1, 3]]:
				p.place(q[0], q[1], q[2], q[3])
		"straight":
			p.box_sel(0, 0, 0, 4, 4, 6, true, sel)
			_sh_door(p, door, 1, 1, 0)
			_sh_door(p, DOOR_OPENING, 1, 1, 6)
			var te := _wall_torch(p, "east")
			var tw := _wall_torch(p, "west")
			_sh_maybe(p, 0.1, 1, 2, 1, te)
			_sh_maybe(p, 0.1, 3, 2, 1, tw)
			_sh_maybe(p, 0.1, 1, 2, 5, te)
			_sh_maybe(p, 0.1, 3, 2, 5, tw)
			if el["left"]:
				p.box(0, 1, 2, 0, 3, 4, ca, ca)
			if el["right"]:
				p.box(4, 1, 2, 4, 3, 4, ca, ca)
		"chest_corridor":
			p.box_sel(0, 0, 0, 4, 4, 6, true, sel)
			_sh_door(p, door, 1, 1, 0)
			_sh_door(p, DOOR_OPENING, 1, 1, 6)
			p.box(3, 1, 2, 3, 1, 4, sb, sb)
			p.place(slab, 3, 1, 1)
			p.place(slab, 3, 1, 5)
			p.place(slab, 3, 2, 2)
			p.place(slab, 3, 2, 4)
			for i in range(2, 5):
				p.place(slab, 2, 1, i)
			p.chest(3, 2, 3, "chests/stronghold_corridor")
		"filler":
			for i in int(el["steps"]):
				for x in 5:
					p.place(sb, x, 0, i)
					p.place(sb, x, 4, i)
				for y in range(1, 4):
					p.place(sb, 0, y, i)
					p.place(ca, 1, y, i)
					p.place(ca, 2, y, i)
					p.place(ca, 3, y, i)
					p.place(sb, 4, y, i)
		"left_turn", "right_turn":
			p.box_sel(0, 0, 0, 4, 4, 4, true, sel)
			_sh_door(p, door, 1, 1, 0)
			var flip: bool = el["ori"] != "north" and el["ori"] != "east"
			var right_side := flip if el["k"] == "left_turn" else not flip
			if right_side:
				p.box(4, 1, 1, 4, 3, 3, ca, ca)
			else:
				p.box(0, 1, 1, 0, 3, 3, ca, ca)
		"straight_stairs":
			p.box_sel(0, 0, 0, 4, 10, 7, true, sel)
			_sh_door(p, door, 1, 7, 0)
			_sh_door(p, DOOR_OPENING, 1, 1, 7)
			var cs := _stairs(p, "cobblestone_stairs", "south")
			for i in 6:
				for x in range(1, 4):
					p.place(cs, x, 6 - i, 1 + i)
					if i < 5:
						p.place(sb, x, 5 - i, 1 + i)
		"room_crossing":
			_sh_room_crossing(p, el, sel, sb, ca, slab, door)
		"prison":
			_sh_prison(p, sel, ca, door)
		"library":
			_sh_library(p, el, sel, door)
		"five_crossing":
			_sh_five_crossing(p, el, sel, ca, slab, door)
		"portal_room":
			_sh_portal_room(p, sel)


static func _wall_torch(p: P, facing: String) -> int:
	return p.b.with_prop(p.b.default_state("wall_torch"), "facing", facing)


## maybeGenerateBlock
static func _sh_maybe(p: P, chance: float, x: int, y: int, z: int, st: int) -> void:
	if p.r.next_float() < chance:
		p.place(st, x, y, z)


## StrongholdPiece.generateSmallDoor
static func _sh_door(p: P, kind: int, x: int, y: int, z: int) -> void:
	var sb := p.s("stone_bricks")
	var ca := p.s("cave_air")
	match kind:
		DOOR_OPENING:
			p.box(x, y, z, x + 2, y + 2, z, ca, ca)
		DOOR_WOOD, DOOR_IRON:
			for q in [[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [2, 1], [2, 0]]:
				p.place(sb, x + q[0], y + q[1], z)
			var dn := "oak_door" if kind == DOOR_WOOD else "iron_door"
			var d0 := p.b.with_prop(p.b.default_state(dn), "facing", "north")
			p.place(d0, x + 1, y, z)
			p.place(p.b.with_prop(d0, "half", "upper"), x + 1, y + 1, z)
			if kind == DOOR_IRON:
				var bt := p.b.with_prop(p.b.default_state("stone_button"), "face", "wall")
				p.place(p.b.with_prop(bt, "facing", "north"), x + 2, y + 1, z + 1)
				p.place(p.b.with_prop(bt, "facing", "south"), x + 2, y + 1, z - 1)
		DOOR_GRATES:
			var bars := p.s("iron_bars")
			p.place(ca, x + 1, y, z)
			p.place(ca, x + 1, y + 1, z)
			for q2 in [[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [2, 1], [2, 0]]:
				p.place(bars, x + q2[0], y + q2[1], z)


static func _sh_room_crossing(p: P, el: Dictionary, sel: Callable, sb: int, ca: int, slab: int, door: int) -> void:
	p.box_sel(0, 0, 0, 10, 6, 10, true, sel)
	_sh_door(p, door, 4, 1, 0)
	p.box(4, 1, 10, 6, 3, 10, ca, ca)
	p.box(0, 1, 4, 0, 3, 6, ca, ca)
	p.box(10, 1, 4, 10, 3, 6, ca, ca)
	match int(el["type"]):
		0:
			p.place(sb, 5, 1, 5)
			p.place(sb, 5, 2, 5)
			p.place(sb, 5, 3, 5)
			p.place(_wall_torch(p, "west"), 4, 3, 5)
			p.place(_wall_torch(p, "east"), 6, 3, 5)
			p.place(_wall_torch(p, "south"), 5, 3, 4)
			p.place(_wall_torch(p, "north"), 5, 3, 6)
			for q in [[4, 4], [4, 5], [4, 6], [6, 4], [6, 5], [6, 6], [5, 4], [5, 6]]:
				p.place(slab, q[0], 1, q[1])
		1:
			for i in 5:
				p.place(sb, 3, 1, 3 + i)
				p.place(sb, 7, 1, 3 + i)
				p.place(sb, 3 + i, 1, 3)
				p.place(sb, 3 + i, 1, 7)
			p.place(sb, 5, 1, 5)
			p.place(sb, 5, 2, 5)
			p.place(sb, 5, 3, 5)
			p.place(p.s("water"), 5, 4, 5)
		2:
			var cob := p.s("cobblestone")
			for i2 in range(1, 10):
				p.place(cob, 1, 3, i2)
				p.place(cob, 9, 3, i2)
			for i3 in range(1, 10):
				p.place(cob, i3, 3, 1)
				p.place(cob, i3, 3, 9)
			for q2 in [[5, 1, 4], [5, 1, 6], [5, 3, 4], [5, 3, 6], [4, 1, 5], [6, 1, 5], [4, 3, 5], [6, 3, 5]]:
				p.place(cob, q2[0], q2[1], q2[2])
			for y in range(1, 4):
				p.place(cob, 4, y, 4)
				p.place(cob, 6, y, 4)
				p.place(cob, 4, y, 6)
				p.place(cob, 6, y, 6)
			p.place(_wall_torch(p, "north"), 5, 3, 5)
			var pl := p.s("oak_planks")
			for i4 in range(2, 9):
				p.place(pl, 2, 3, i4)
				p.place(pl, 3, 3, i4)
				if i4 <= 3 or i4 >= 7:
					p.place(pl, 4, 3, i4)
					p.place(pl, 5, 3, i4)
					p.place(pl, 6, 3, i4)
				p.place(pl, 7, 3, i4)
				p.place(pl, 8, 3, i4)
			var ld := p.b.with_prop(p.b.default_state("ladder"), "facing", "west")
			p.place(ld, 9, 1, 3)
			p.place(ld, 9, 2, 3)
			p.place(ld, 9, 3, 3)
			p.chest(3, 4, 8, "chests/stronghold_crossing")


static func _sh_prison(p: P, sel: Callable, ca: int, door: int) -> void:
	p.box_sel(0, 0, 0, 8, 4, 10, true, sel)
	_sh_door(p, door, 1, 1, 0)
	p.box(1, 1, 10, 3, 3, 10, ca, ca)
	p.box_sel(4, 1, 1, 4, 3, 1, false, sel)
	p.box_sel(4, 1, 3, 4, 3, 3, false, sel)
	p.box_sel(4, 1, 7, 4, 3, 7, false, sel)
	p.box_sel(4, 1, 9, 4, 3, 9, false, sel)
	var bars := p.s("iron_bars")
	for y in range(1, 4):
		p.place(bars, 4, y, 4)
		p.place(bars, 4, y, 5)
		p.place(bars, 4, y, 6)
		p.place(bars, 5, y, 5)
		p.place(bars, 6, y, 5)
		p.place(bars, 7, y, 5)
	p.place(bars, 4, 3, 2)
	p.place(bars, 4, 3, 8)
	var d := p.b.with_prop(p.b.default_state("iron_door"), "facing", "west")
	var du := p.b.with_prop(d, "half", "upper")
	p.place(d, 4, 1, 2)
	p.place(du, 4, 2, 2)
	p.place(d, 4, 1, 8)
	p.place(du, 4, 2, 8)


static func _sh_library(p: P, el: Dictionary, sel: Callable, door: int) -> void:
	var tall := bool(el["tall"])
	var h := 11 if tall else 6
	p.box_sel(0, 0, 0, 13, h - 1, 14, true, sel)
	_sh_door(p, door, 4, 1, 0)
	var web := p.s("cobweb")
	_maybe_box(p, 0.07, 2, 1, 1, 11, 4, 13, web, web, false, false)
	var pl := p.s("oak_planks")
	var bs := p.s("bookshelf")
	for z in range(1, 14):
		if (z - 1) % 4 == 0:
			p.box(1, 1, z, 1, 4, z, pl, pl)
			p.box(12, 1, z, 12, 4, z, pl, pl)
			p.place(_wall_torch(p, "east"), 2, 3, z)
			p.place(_wall_torch(p, "west"), 11, 3, z)
			if tall:
				p.box(1, 6, z, 1, 9, z, pl, pl)
				p.box(12, 6, z, 12, 9, z, pl, pl)
		else:
			p.box(1, 1, z, 1, 4, z, bs, bs)
			p.box(12, 1, z, 12, 4, z, bs, bs)
			if tall:
				p.box(1, 6, z, 1, 9, z, bs, bs)
				p.box(12, 6, z, 12, 9, z, bs, bs)
	var z2 := 3
	while z2 < 12:
		p.box(3, 1, z2, 4, 3, z2, bs, bs)
		p.box(6, 1, z2, 7, 3, z2, bs, bs)
		p.box(9, 1, z2, 10, 3, z2, bs, bs)
		z2 += 2
	if tall:
		var fe := p.s("oak_fence")
		p.box(1, 5, 1, 3, 5, 13, pl, pl)
		p.box(10, 5, 1, 12, 5, 13, pl, pl)
		p.box(4, 5, 1, 9, 5, 2, pl, pl)
		p.box(4, 5, 12, 9, 5, 13, pl, pl)
		p.place(pl, 9, 5, 11)
		p.place(pl, 8, 5, 11)
		p.place(pl, 9, 5, 10)
		p.box(3, 6, 3, 3, 6, 11, fe, fe)
		p.box(10, 6, 3, 10, 6, 9, fe, fe)
		p.box(4, 6, 2, 9, 6, 2, fe, fe)
		p.box(4, 6, 12, 7, 6, 12, fe, fe)
		p.place(fe, 3, 6, 2)
		p.place(fe, 3, 6, 12)
		p.place(fe, 10, 6, 2)
		for i in 3:
			p.place(fe, 8 + i, 6, 12 - i)
			if i != 2:
				p.place(fe, 8 + i, 6, 11 - i)
		var ld := p.b.with_prop(p.b.default_state("ladder"), "facing", "south")
		for y in range(1, 8):
			p.place(ld, 10, y, 13)
		for q in [[6, 9, 7], [7, 9, 7], [6, 8, 7], [7, 8, 7], [6, 7, 7], [7, 7, 7], [5, 7, 7], [8, 7, 7], [6, 7, 6], [6, 7, 8], [7, 7, 6], [7, 7, 8]]:
			p.place(fe, q[0], q[1], q[2])
		var torch := p.s("torch")
		for q2 in [[5, 8, 7], [8, 8, 7], [6, 8, 6], [6, 8, 8], [7, 8, 6], [7, 8, 8]]:
			p.place(torch, q2[0], q2[1], q2[2])
	p.chest(3, 3, 5, "chests/stronghold_library")
	if tall:
		p.place(p.s("cave_air"), 12, 9, 1)
		p.chest(12, 8, 1, "chests/stronghold_library")


static func _sh_five_crossing(p: P, el: Dictionary, sel: Callable, ca: int, slab: int, door: int) -> void:
	p.box_sel(0, 0, 0, 9, 8, 10, true, sel)
	_sh_door(p, door, 4, 3, 0)
	if el["ll"]:
		p.box(0, 3, 1, 0, 5, 3, ca, ca)
	if el["rl"]:
		p.box(9, 3, 1, 9, 5, 3, ca, ca)
	if el["lh"]:
		p.box(0, 5, 7, 0, 7, 9, ca, ca)
	if el["rh"]:
		p.box(9, 5, 7, 9, 7, 9, ca, ca)
	p.box(5, 1, 10, 7, 3, 10, ca, ca)
	p.box_sel(1, 2, 1, 8, 2, 6, false, sel)
	p.box_sel(4, 1, 5, 4, 4, 9, false, sel)
	p.box_sel(8, 1, 5, 8, 4, 9, false, sel)
	p.box_sel(1, 4, 7, 3, 4, 9, false, sel)
	p.box_sel(1, 3, 5, 3, 3, 6, false, sel)
	p.box(1, 3, 4, 3, 3, 4, slab, slab)
	p.box(1, 4, 6, 3, 4, 6, slab, slab)
	p.box_sel(5, 1, 7, 7, 1, 8, false, sel)
	p.box(5, 1, 9, 7, 1, 9, slab, slab)
	p.box(5, 2, 7, 7, 2, 7, slab, slab)
	p.box(4, 5, 7, 4, 5, 9, slab, slab)
	p.box(8, 5, 7, 8, 5, 9, slab, slab)
	var dbl := p.b.with_prop(slab, "type", "double")
	p.box(5, 5, 7, 7, 5, 9, dbl, dbl)
	p.place(_wall_torch(p, "south"), 6, 5, 6)


static func _sh_portal_room(p: P, sel: Callable) -> void:
	p.box_sel(0, 0, 0, 10, 7, 15, false, sel)
	_sh_door(p, DOOR_GRATES, 4, 1, 0)
	p.box_sel(1, 6, 1, 1, 6, 14, false, sel)
	p.box_sel(9, 6, 1, 9, 6, 14, false, sel)
	p.box_sel(2, 6, 1, 8, 6, 2, false, sel)
	p.box_sel(2, 6, 14, 8, 6, 14, false, sel)
	p.box_sel(1, 1, 1, 2, 1, 4, false, sel)
	p.box_sel(8, 1, 1, 9, 1, 4, false, sel)
	var lava := p.s("lava")
	p.box(1, 1, 1, 1, 1, 3, lava, lava)
	p.box(9, 1, 1, 9, 1, 3, lava, lava)
	p.box_sel(3, 1, 8, 7, 1, 12, false, sel)
	p.box(4, 1, 9, 6, 1, 11, lava, lava)
	var bars := p.s("iron_bars")
	var z := 3
	while z < 14:
		p.box(0, 3, z, 0, 4, z, bars, bars)
		p.box(10, 3, z, 10, 4, z, bars, bars)
		z += 2
	var x := 2
	while x < 9:
		p.box(x, 3, 15, x, 4, 15, bars, bars)
		x += 2
	var stn := _stairs(p, "stone_brick_stairs", "north")
	p.box_sel(4, 1, 5, 6, 1, 7, false, sel)
	p.box_sel(4, 2, 6, 6, 2, 7, false, sel)
	p.box_sel(4, 3, 7, 6, 3, 7, false, sel)
	for x2 in range(4, 7):
		p.place(stn, x2, 1, 4)
		p.place(stn, x2, 2, 5)
		p.place(stn, x2, 3, 6)
	var fr := p.s("end_portal_frame")
	var eyes: Array = []
	var all := true
	for i in 12:
		var e: bool = p.r.next_float() > 0.9
		eyes.append(e)
		all = all and e
	var spots := [["north", 4, 8], ["north", 5, 8], ["north", 6, 8], ["south", 4, 12], ["south", 5, 12], ["south", 6, 12],
		["east", 3, 9], ["east", 3, 10], ["east", 3, 11], ["west", 7, 9], ["west", 7, 10], ["west", 7, 11]]
	for i2 in 12:
		var sp: Array = spots[i2]
		p.place(p.b.with_prop(p.b.with_prop(fr, "facing", sp[0]), "eye", "true" if eyes[i2] else "false"), sp[1], 3, sp[2])
	if all:
		var portal := p.s("end_portal")
		for xx in range(4, 7):
			for zz in range(9, 12):
				p.place(portal, xx, 3, zz)
	var spw := p.wpos(5, 3, 6)
	if p.inside(spw):
		p.f.set_block(p.c, spw, p.s("spawner"))
		p.c.block_entities[spw] = {"id": "spawner", "mob": "silverfish"}


# ------------------------------------------------------------------ OceanMonumentPieces

## Direction 3D data values (DOWN, UP, NORTH, SOUTH, WEST, EAST) and steps
const MD_DOWN := 0
const MD_UP := 1
const MD_NORTH := 2
const MD_SOUTH := 3
const MD_WEST := 4
const MD_EAST := 5
const MD_STEP := [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
const MD_OPP := [1, 0, 3, 2, 5, 4]


## OceanMonumentPieces.RoomDefinition
class MRoom:
	var index := 0
	var conn: Array = [null, null, null, null, null, null]
	var open: Array = [false, false, false, false, false, false]
	var claimed := false
	var source := false
	var scan := 0

	func _init(i: int) -> void:
		index = i

	func set_conn(d: int, o: MRoom) -> void:
		conn[d] = o
		o.conn[JavaPieces.MD_OPP[d]] = self

	func update_openings() -> void:
		for i in 6:
			open[i] = conn[i] != null

	func find_source(n: int) -> bool:
		if source:
			return true
		scan = n
		for i in 6:
			var o = conn[i]
			if o != null and open[i] and o.scan != n and o.find_source(n):
				return true
		return false

	func special() -> bool:
		return index >= 75

	func count_open() -> int:
		var k := 0
		for i in 6:
			if open[i]:
				k += 1
		return k


## OceanMonumentStructure.findGenerationPoint: every biome within 29 blocks of the chunk's (9, sea level, 9) must be
## an ocean or river (#required_ocean_monument_surrounding).
static var _mo_ring: Dictionary = {}


static func monument_surroundings_ok(st: Structures, sc: Vector2i) -> bool:
	if _mo_ring.is_empty():
		var d := {"__": true}
		for nm in Tags.resolve("worldgen/biome", "#minecraft:required_ocean_monument_surrounding"):
			var bid = st.gen.biome_ids.get(str(nm).trim_prefix("minecraft:"))
			if bid != null:
				d[int(bid)] = true
		_mo_ring = d
	var x := sc.x * 16 + 9
	var z := sc.y * 16 + 9
	var y: int = st.gen.sea_level
	if st.gen.native_tg >= 0 and Native.density_ok and Native.inst.has_method("tg_biomes_within"):
		var ids: PackedInt32Array = Native.inst.tg_biomes_within(st.gen.native_tg, x, y, z, 29)[0]
		for b in ids:
			if not _mo_ring.has(b):
				return false
		return true
	for qz in range((z - 29) >> 2, ((z + 29) >> 2) + 1):
		for qx in range((x - 29) >> 2, ((x + 29) >> 2) + 1):
			for qy in range((y - 29) >> 2, ((y + 29) >> 2) + 1):
				if not _mo_ring.has(st.biome_id_at(qx * 4, qy * 4, qz * 4)):
					return false
	return true


## MonumentBuilding: random facing, the 58 x 23 x 58 building at (chunk - 29, 39, chunk - 29); the 5 x 5 x 3 room
## graph (entry at grid (2, 0, 0), the 2 x 2 x 2 core at a random (0..3, 0, 2), openings pruned while every room
## still reaches the entry), rooms fitted by the seven fitters, two wing rooms and the penthouse.
static func monument(st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	if not monument_surroundings_ok(st, sc):
		return {}
	return monument_layout(sc, r)


static func monument_layout(sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var dir: String = DIRS[r.next_int_bound(4)]
	var west := sc.x * 16 - 29
	var north := sc.y * 16 - 29
	var bp := P.new()
	bp.bmin = Vector3i(west, 39, north)
	bp.bmax = Vector3i(west + 57, 61, north + 57)
	bp.ori = dir
	# generateRoomGraph
	var rooms: Array = []
	rooms.resize(75)
	for x in 5:
		for z in 4:
			rooms[z * 5 + x] = MRoom.new(z * 5 + x)
	for x2 in 5:
		for z2 in 4:
			rooms[25 + z2 * 5 + x2] = MRoom.new(25 + z2 * 5 + x2)
	for x3 in range(1, 4):
		for z3 in 2:
			rooms[50 + z3 * 5 + x3] = MRoom.new(50 + z3 * 5 + x3)
	var source: MRoom = rooms[2]
	for x4 in 5:
		for z4 in 5:
			for y4 in 3:
				var idx := y4 * 25 + z4 * 5 + x4
				if rooms[idx] == null:
					continue
				for d in 6:
					var stp: Vector3i = MD_STEP[d]
					var nx := x4 + stp.x
					var ny := y4 + stp.y
					var nz := z4 + stp.z
					if nx >= 0 and nx < 5 and nz >= 0 and nz < 5 and ny >= 0 and ny < 3:
						var nidx := ny * 25 + nz * 5 + nx
						if rooms[nidx] != null:
							if nz == z4:
								(rooms[idx] as MRoom).set_conn(d, rooms[nidx])
							else:
								(rooms[idx] as MRoom).set_conn(MD_OPP[d], rooms[nidx])
	var top := MRoom.new(1003)
	var left := MRoom.new(1001)
	var right := MRoom.new(1002)
	(rooms[52] as MRoom).set_conn(MD_UP, top)
	(rooms[25] as MRoom).set_conn(MD_SOUTH, left)
	(rooms[29] as MRoom).set_conn(MD_SOUTH, right)
	top.claimed = true
	left.claimed = true
	right.claimed = true
	source.source = true
	var core: MRoom = rooms[10 + r.next_int_bound(4)]
	core.claimed = true
	core.conn[MD_EAST].claimed = true
	core.conn[MD_NORTH].claimed = true
	core.conn[MD_EAST].conn[MD_NORTH].claimed = true
	core.conn[MD_UP].claimed = true
	core.conn[MD_EAST].conn[MD_UP].claimed = true
	core.conn[MD_NORTH].conn[MD_UP].claimed = true
	core.conn[MD_EAST].conn[MD_NORTH].conn[MD_UP].claimed = true
	var lst: Array = []
	for rm in rooms:
		if rm != null:
			(rm as MRoom).update_openings()
			lst.append(rm)
	top.update_openings()
	lst = Structures._shuffled(lst, r)
	var n := 1
	for rm2 in lst:
		var room: MRoom = rm2
		var k := 0
		var att := 0
		while k < 2 and att < 5:
			att += 1
			var d2: int = r.next_int_bound(6)
			if room.open[d2]:
				var o: int = MD_OPP[d2]
				room.open[d2] = false
				room.conn[d2].open[o] = false
				var ok1 := room.find_source(n)
				n += 1
				var ok2 := false
				if ok1:
					ok2 = room.conn[d2].find_source(n)
					n += 1
				if ok1 and ok2:
					k += 1
				else:
					room.open[d2] = true
					room.conn[d2].open[o] = true
	lst.append(top)
	lst.append(left)
	lst.append(right)
	# MonumentBuilding constructor
	source.claimed = true
	var children: Array = []
	children.append(_mo_child("entry", source, 1, 1, 1, dir))
	children.append(_mo_child("core", core, 2, 2, 2, dir))
	for rm3 in lst:
		var q: MRoom = rm3
		if q.claimed or q.special():
			continue
		var ce = q.conn[MD_EAST]
		var cn = q.conn[MD_NORTH]
		var cu = q.conn[MD_UP]
		if q.open[MD_EAST] and not ce.claimed and q.open[MD_UP] and not cu.claimed and ce.open[MD_UP] and not ce.conn[MD_UP].claimed:
			q.claimed = true
			ce.claimed = true
			cu.claimed = true
			ce.conn[MD_UP].claimed = true
			children.append(_mo_child("double_xy", q, 2, 2, 1, dir))
		elif q.open[MD_NORTH] and not cn.claimed and q.open[MD_UP] and not cu.claimed and cn.open[MD_UP] and not cn.conn[MD_UP].claimed:
			q.claimed = true
			cn.claimed = true
			cu.claimed = true
			cn.conn[MD_UP].claimed = true
			children.append(_mo_child("double_yz", q, 1, 2, 2, dir))
		elif q.open[MD_NORTH] and not cn.claimed:
			q.claimed = true
			cn.claimed = true
			children.append(_mo_child("double_z", q, 1, 1, 2, dir))
		elif q.open[MD_EAST] and not ce.claimed:
			q.claimed = true
			ce.claimed = true
			children.append(_mo_child("double_x", q, 2, 1, 1, dir))
		elif q.open[MD_UP] and not cu.claimed:
			q.claimed = true
			cu.claimed = true
			children.append(_mo_child("double_y", q, 1, 2, 1, dir))
		elif not q.open[MD_WEST] and not q.open[MD_EAST] and not q.open[MD_NORTH] and not q.open[MD_SOUTH] and not q.open[MD_UP]:
			q.claimed = true
			children.append(_mo_child("simple_top", q, 1, 1, 1, dir))
		else:
			q.claimed = true
			var ch := _mo_child("simple", q, 1, 1, 1, dir)
			ch["design"] = r.next_int_bound(3)
			children.append(ch)
	var mv := bp.wpos(9, 0, 22)
	for ch2 in children:
		ch2["min"] = ch2["min"] + mv
		ch2["max"] = ch2["max"] + mv
	var kseed := r.next_int()
	var w1a := bp.wpos(1, 1, 1)
	var w1b := bp.wpos(23, 8, 21)
	var w2a := bp.wpos(34, 1, 1)
	var w2b := bp.wpos(56, 8, 21)
	var pa := bp.wpos(22, 13, 22)
	var pb := bp.wpos(35, 17, 35)
	children.append({"k": "wing", "min": w1a.min(w1b), "max": w1a.max(w1b), "ori": dir, "design": kseed & 1})
	children.append({"k": "wing", "min": w2a.min(w2b), "max": w2a.max(w2b), "ori": dir, "design": (kseed + 1) & 1})
	children.append({"k": "penthouse", "min": pa.min(pb), "max": pa.max(pb), "ori": dir})
	var building := {"k": "building", "min": bp.bmin, "max": bp.bmax, "ori": dir}
	var out: Array = []
	var omin := bp.bmin
	var omax := bp.bmax
	for pc in [building] + children:
		pc["t"] = "java"
		pc["kind"] = "monument"
		omin = omin.min(pc["min"])
		omax = omax.max(pc["max"])
		out.append({"el": pc, "pos": pc["min"], "rot": 0, "box": [pc["min"], pc["max"]]})
	return {"pieces": out, "center": (bp.bmin + bp.bmax) / 2, "box": [omin, omax]}


## OceanMonumentPiece room box (makeBoundingBox from the room's grid index), relative to the building's (9, 0, 22).
static func _mo_child(k: String, rm: MRoom, w: int, h: int, d: int, dir: String) -> Dictionary:
	var i := rm.index
	var j := i % 5
	var kk := i / 5 % 5
	var l := i / 25
	var size := Vector3i(w * 8 - 1, h * 4 - 1, d * 8 - 1) if dir == "north" or dir == "south" else Vector3i(d * 8 - 1, h * 4 - 1, w * 8 - 1)
	var off := Vector3i(kk * 8, l * 4, j * 8)
	match dir:
		"north":
			off = Vector3i(j * 8, l * 4, -(kk + d) * 8 + 1)
		"south":
			off = Vector3i(j * 8, l * 4, kk * 8)
		"west":
			off = Vector3i(-(kk + d) * 8 + 1, l * 4, j * 8)
	# the opening flags the piece reads (this room and the rooms it spans)
	var flags := {"r": rm.open.duplicate(), "up_null": rm.conn[MD_UP] == null}
	for nm in ["e", "n", "u"]:
		var dd: int = {"e": MD_EAST, "n": MD_NORTH, "u": MD_UP}[nm]
		var o = rm.conn[dd]
		if o != null:
			flags[nm] = o.open.duplicate()
			flags[nm + "_up_null"] = o.conn[MD_UP] == null
			var ou = o.conn[MD_UP]
			if ou != null:
				flags[nm + "u"] = ou.open.duplicate()
				flags[nm + "u_up_null"] = ou.conn[MD_UP] == null
	return {"k": k, "min": off, "max": off + size, "ori": dir, "idx": i, "f": flags}


# --- placement

static func _place_monument(p: P, el: Dictionary) -> void:
	var L := p.s("prismarine_bricks")
	var G := p.s("prismarine")
	var B := p.s("dark_prismarine")
	var LAMP := p.s("sea_lantern")
	match str(el["k"]):
		"building":
			_mo_building(p, L, G, B, LAMP)
		"entry":
			_mo_entry(p, el, L)
		"core":
			_mo_core(p, L, G, B, LAMP)
		"simple":
			_mo_simple(p, el, L, G, B, LAMP)
		"simple_top":
			_mo_simple_top(p, el, L, G, B)
		"double_y":
			_mo_double_y(p, el, L, G)
		"double_x":
			_mo_double_x(p, el, L, G, LAMP)
		"double_z":
			_mo_double_z(p, el, L, G, LAMP)
		"double_xy":
			_mo_double_xy(p, el, L, G, LAMP)
		"double_yz":
			_mo_double_yz(p, el, L, G, B, LAMP)
		"wing":
			_mo_wing(p, el, L, B, LAMP)
		"penthouse":
			_mo_penthouse(p, L, G, B, LAMP)


static var _mo_keep: Dictionary = {}


## generateWaterBox: water below sea level, air above, ice / packed ice / blue ice / water kept.
static func _mo_water(p: P, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int) -> void:
	var cl := p.clip(x0, y0, z0, x1, y1, z1)
	if cl.is_empty():
		return
	if _mo_keep.is_empty():
		var d := {"__": true}
		for nm in ["ice", "packed_ice", "blue_ice", "water"]:
			d[p.b.block_id(nm)] = true
		_mo_keep = d
	var water := p.s("water")
	var sea: int = p.f.gen.sea_level
	for y in range(cl[1], cl[4] + 1):
		var wy := p.wy(y)
		var st := water if wy < sea else 0
		for x in range(cl[0], cl[3] + 1):
			for z in range(cl[2], cl[5] + 1):
				var cur := p.get_at(x, y, z)
				if cur > 0 and _mo_keep.has(p.b.st_block[cur]):
					continue
				p.place(st, x, y, z)


## generateBoxOnFillOnly: only where the block is the plain water source.
static func _mo_on_fill(p: P, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, st: int) -> void:
	var cl := p.clip(x0, y0, z0, x1, y1, z1)
	if cl.is_empty():
		return
	var water := p.s("water")
	for y in range(cl[1], cl[4] + 1):
		for x in range(cl[0], cl[3] + 1):
			for z in range(cl[2], cl[5] + 1):
				if p.get_at(x, y, z) == water:
					p.place(st, x, y, z)


static func _mo_floor(p: P, x: int, z: int, opening: bool, L: int, G: int) -> void:
	if opening:
		p.box(x, 0, z, x + 2, 0, z + 7, G, G)
		p.box(x + 5, 0, z, x + 7, 0, z + 7, G, G)
		p.box(x + 3, 0, z, x + 4, 0, z + 2, G, G)
		p.box(x + 3, 0, z + 5, x + 4, 0, z + 7, G, G)
		p.box(x + 3, 0, z + 2, x + 4, 0, z + 2, L, L)
		p.box(x + 3, 0, z + 5, x + 4, 0, z + 5, L, L)
		p.box(x + 2, 0, z + 3, x + 2, 0, z + 4, L, L)
		p.box(x + 5, 0, z + 3, x + 5, 0, z + 4, L, L)
	else:
		p.box(x, 0, z, x + 7, 0, z + 7, G, G)


static func _mo_hits(p: P, x0: int, z0: int, x1: int, z1: int) -> bool:
	var a := p.wpos(x0, 0, z0)
	var b2 := p.wpos(x1, 0, z1)
	return maxi(a.x, b2.x) >= p.cmin.x and mini(a.x, b2.x) <= p.cmax.x and maxi(a.z, b2.z) >= p.cmin.z and mini(a.z, b2.z) <= p.cmax.z


static func _mo_elder(p: P, x: int, y: int, z: int) -> void:
	var wp := p.wpos(x, y, z)
	if p.inside(wp):
		p.c.entities.append({"k": "mob", "id": "elder_guardian", "p": [wp.x + 0.5, wp.y, wp.z + 0.5], "b": 0, "pers": true})


static func _mo_building(p: P, L: int, G: int, B: int, LAMP: int) -> void:
	var i: int = maxi(p.f.gen.sea_level, 64) - p.bmin.y
	_mo_water(p, 0, 0, 0, 58, i, 58)
	_mo_wing_shell(p, false, 0, L, G)
	_mo_wing_shell(p, true, 33, L, G)
	# entrance arches
	if _mo_hits(p, 22, 5, 35, 17):
		_mo_water(p, 25, 0, 0, 32, 8, 20)
		for a in 4:
			var z := 5 + a * 4
			p.box(24, 2, z, 24, 4, z, L, L)
			p.box(22, 4, z, 23, 4, z, L, L)
			p.place(L, 25, 5, z)
			p.place(L, 26, 6, z)
			p.place(LAMP, 26, 5, z)
			p.box(33, 2, z, 33, 4, z, L, L)
			p.box(34, 4, z, 35, 4, z, L, L)
			p.place(L, 32, 5, z)
			p.place(L, 31, 6, z)
			p.place(LAMP, 31, 5, z)
			p.box(27, 6, z, 30, 6, z, G, G)
	# entrance wall
	if _mo_hits(p, 15, 20, 42, 21):
		p.box(15, 0, 21, 42, 0, 21, G, G)
		_mo_water(p, 26, 1, 21, 31, 3, 21)
		p.box(21, 12, 21, 36, 12, 21, G, G)
		p.box(17, 11, 21, 40, 11, 21, G, G)
		p.box(16, 10, 21, 41, 10, 21, G, G)
		p.box(15, 7, 21, 42, 9, 21, G, G)
		p.box(16, 6, 21, 41, 6, 21, G, G)
		p.box(17, 5, 21, 40, 5, 21, G, G)
		p.box(21, 4, 21, 36, 4, 21, G, G)
		p.box(22, 3, 21, 26, 3, 21, G, G)
		p.box(31, 3, 21, 35, 3, 21, G, G)
		p.box(23, 2, 21, 25, 2, 21, G, G)
		p.box(32, 2, 21, 34, 2, 21, G, G)
		p.box(28, 4, 20, 29, 4, 21, L, L)
		p.place(L, 27, 3, 21)
		p.place(L, 30, 3, 21)
		p.place(L, 26, 2, 21)
		p.place(L, 31, 2, 21)
		p.place(L, 25, 1, 21)
		p.place(L, 32, 1, 21)
		for a2 in 7:
			p.place(B, 28 - a2, 6 + a2, 21)
			p.place(B, 29 + a2, 6 + a2, 21)
		for a3 in 4:
			p.place(B, 28 - a3, 9 + a3, 21)
			p.place(B, 29 + a3, 9 + a3, 21)
		p.place(B, 28, 12, 21)
		p.place(B, 29, 12, 21)
		for a4 in 3:
			p.place(B, 22 - a4 * 2, 8, 21)
			p.place(B, 22 - a4 * 2, 9, 21)
			p.place(B, 35 + a4 * 2, 8, 21)
			p.place(B, 35 + a4 * 2, 9, 21)
		_mo_water(p, 15, 13, 21, 42, 15, 21)
		_mo_water(p, 15, 1, 21, 15, 6, 21)
		_mo_water(p, 16, 1, 21, 16, 5, 21)
		_mo_water(p, 17, 1, 21, 20, 4, 21)
		_mo_water(p, 21, 1, 21, 21, 3, 21)
		_mo_water(p, 22, 1, 21, 22, 2, 21)
		_mo_water(p, 23, 1, 21, 24, 1, 21)
		_mo_water(p, 42, 1, 21, 42, 6, 21)
		_mo_water(p, 41, 1, 21, 41, 5, 21)
		_mo_water(p, 37, 1, 21, 40, 4, 21)
		_mo_water(p, 36, 1, 21, 36, 3, 21)
		_mo_water(p, 33, 1, 21, 34, 1, 21)
		_mo_water(p, 35, 1, 21, 35, 2, 21)
	# roof
	if _mo_hits(p, 21, 21, 36, 36):
		p.box(21, 0, 22, 36, 0, 36, G, G)
		_mo_water(p, 21, 1, 22, 36, 23, 36)
		for a5 in 4:
			p.box(21 + a5, 13 + a5, 21 + a5, 36 - a5, 13 + a5, 21 + a5, L, L)
			p.box(21 + a5, 13 + a5, 36 - a5, 36 - a5, 13 + a5, 36 - a5, L, L)
			p.box(21 + a5, 13 + a5, 22 + a5, 21 + a5, 13 + a5, 35 - a5, L, L)
			p.box(36 - a5, 13 + a5, 22 + a5, 36 - a5, 13 + a5, 35 - a5, L, L)
		p.box(25, 16, 25, 32, 16, 32, G, G)
		p.box(25, 17, 25, 25, 19, 25, L, L)
		p.box(32, 17, 25, 32, 19, 25, L, L)
		p.box(25, 17, 32, 25, 19, 32, L, L)
		p.box(32, 17, 32, 32, 19, 32, L, L)
		for q in [[26, 26, 27, 27], [26, 31, 27, 30], [31, 31, 30, 30], [31, 26, 30, 27]]:
			p.place(L, q[0], 20, q[1])
			p.place(L, q[2], 21, q[3])
			p.place(LAMP, q[2], 20, q[3])
		p.box(28, 21, 27, 29, 21, 27, G, G)
		p.box(27, 21, 28, 27, 21, 29, G, G)
		p.box(28, 21, 30, 29, 21, 30, G, G)
		p.box(30, 21, 28, 30, 21, 29, G, G)
	# lower wall
	if _mo_hits(p, 0, 21, 6, 58):
		p.box(0, 0, 21, 6, 0, 57, G, G)
		_mo_water(p, 0, 1, 21, 6, 7, 57)
		p.box(4, 4, 21, 6, 4, 53, G, G)
		for a6 in 4:
			p.box(a6, a6 + 1, 21, a6, a6 + 1, 57 - a6, L, L)
		var zz := 23
		while zz < 53:
			p.place(L, 5, 5, zz)
			zz += 3
		p.place(L, 5, 5, 52)
		for a7 in 4:
			p.box(a7, a7 + 1, 21, a7, a7 + 1, 57 - a7, L, L)
		p.box(4, 1, 52, 6, 3, 52, G, G)
		p.box(5, 1, 51, 5, 3, 53, G, G)
	if _mo_hits(p, 51, 21, 58, 58):
		p.box(51, 0, 21, 57, 0, 57, G, G)
		_mo_water(p, 51, 1, 21, 57, 7, 57)
		p.box(51, 4, 21, 53, 4, 53, G, G)
		for a8 in 4:
			p.box(57 - a8, a8 + 1, 21, 57 - a8, a8 + 1, 57 - a8, L, L)
		var zz2 := 23
		while zz2 < 53:
			p.place(L, 52, 5, zz2)
			zz2 += 3
		p.place(L, 52, 5, 52)
		p.box(51, 1, 52, 53, 3, 52, G, G)
		p.box(52, 1, 51, 52, 3, 53, G, G)
	if _mo_hits(p, 0, 51, 57, 57):
		p.box(7, 0, 51, 50, 0, 57, G, G)
		_mo_water(p, 7, 1, 51, 50, 10, 57)
		for a9 in 4:
			p.box(a9 + 1, a9 + 1, 57 - a9, 56 - a9, a9 + 1, 57 - a9, L, L)
	# middle wall
	if _mo_hits(p, 7, 21, 13, 50):
		p.box(7, 0, 21, 13, 0, 50, G, G)
		_mo_water(p, 7, 1, 21, 13, 10, 50)
		p.box(11, 8, 21, 13, 8, 53, G, G)
		for b1 in 4:
			p.box(b1 + 7, b1 + 5, 21, b1 + 7, b1 + 5, 54, L, L)
		var z3 := 21
		while z3 <= 45:
			p.place(L, 12, 9, z3)
			z3 += 3
	if _mo_hits(p, 44, 21, 50, 54):
		p.box(44, 0, 21, 50, 0, 50, G, G)
		_mo_water(p, 44, 1, 21, 50, 10, 50)
		p.box(44, 8, 21, 46, 8, 53, G, G)
		for b2 in 4:
			p.box(50 - b2, b2 + 5, 21, 50 - b2, b2 + 5, 54, L, L)
		var z4 := 21
		while z4 <= 45:
			p.place(L, 45, 9, z4)
			z4 += 3
	if _mo_hits(p, 8, 44, 49, 54):
		p.box(14, 0, 44, 43, 0, 50, G, G)
		_mo_water(p, 14, 1, 44, 43, 10, 50)
		var x5 := 12
		while x5 <= 45:
			p.place(L, x5, 9, 45)
			p.place(L, x5, 9, 52)
			if x5 in [12, 18, 24, 33, 39, 45]:
				p.place(L, x5, 9, 47)
				p.place(L, x5, 9, 50)
				p.place(L, x5, 10, 45)
				p.place(L, x5, 10, 46)
				p.place(L, x5, 10, 51)
				p.place(L, x5, 10, 52)
				p.place(L, x5, 11, 47)
				p.place(L, x5, 11, 50)
				p.place(L, x5, 12, 48)
				p.place(L, x5, 12, 49)
			x5 += 3
		for b3 in 3:
			p.box(8 + b3, 5 + b3, 54, 49 - b3, 5 + b3, 54, G, G)
		p.box(11, 8, 54, 46, 8, 54, L, L)
		p.box(14, 8, 44, 43, 8, 53, G, G)
	# upper wall
	if _mo_hits(p, 14, 21, 20, 43):
		p.box(14, 0, 21, 20, 0, 43, G, G)
		_mo_water(p, 14, 1, 22, 20, 14, 43)
		p.box(18, 12, 22, 20, 12, 39, G, G)
		p.box(18, 12, 21, 20, 12, 21, L, L)
		for b4 in 4:
			p.box(b4 + 14, b4 + 9, 21, b4 + 14, b4 + 9, 43 - b4, L, L)
		var z6 := 23
		while z6 <= 39:
			p.place(L, 19, 13, z6)
			z6 += 3
	if _mo_hits(p, 37, 21, 43, 43):
		p.box(37, 0, 21, 43, 0, 43, G, G)
		_mo_water(p, 37, 1, 22, 43, 14, 43)
		p.box(37, 12, 22, 39, 12, 39, G, G)
		p.box(37, 12, 21, 39, 12, 21, L, L)
		for b5 in 4:
			p.box(43 - b5, b5 + 9, 21, 43 - b5, b5 + 9, 43 - b5, L, L)
		var z7 := 23
		while z7 <= 39:
			p.place(L, 38, 13, z7)
			z7 += 3
	if _mo_hits(p, 15, 37, 42, 43):
		p.box(21, 0, 37, 36, 0, 43, G, G)
		_mo_water(p, 21, 1, 37, 36, 14, 43)
		p.box(21, 12, 37, 36, 12, 39, G, G)
		for b6 in 4:
			p.box(15 + b6, b6 + 9, 43 - b6, 42 - b6, b6 + 9, 43 - b6, L, L)
		var x8 := 21
		while x8 <= 36:
			p.place(L, x8, 13, 38)
			x8 += 3
	# corner and edge pillars down to the sea floor
	for px in 7:
		var pz := 0
		while pz < 7:
			if pz == 0 and px == 3:
				pz = 6
			var xx := px * 9
			var zz3 := pz * 9
			for a in 4:
				for b in 4:
					p.place(L, xx + a, 0, zz3 + b)
					p.column_down(L, xx + a, -1, zz3 + b)
			if px != 0 and px != 6:
				pz += 6
			else:
				pz += 1
	for e in 5:
		_mo_water(p, -1 - e, e * 2, -1 - e, -1 - e, 23, 58 + e)
		_mo_water(p, 58 + e, e * 2, -1 - e, 58 + e, 23, 58 + e)
		_mo_water(p, -e, e * 2, -1 - e, 57 + e, 23, -1 - e)
		_mo_water(p, -e, e * 2, 58 + e, 57 + e, 23, 58 + e)


static func _mo_wing_shell(p: P, flipped: bool, xo: int, L: int, G: int) -> void:
	if not _mo_hits(p, xo, 0, xo + 23, 20):
		return
	p.box(xo, 0, 0, xo + 24, 0, 20, G, G)
	_mo_water(p, xo, 1, 0, xo + 24, 10, 20)
	for j in 4:
		p.box(xo + j, j + 1, j, xo + j, j + 1, 20, L, L)
		p.box(xo + j + 7, j + 5, j + 7, xo + j + 7, j + 5, 20, L, L)
		p.box(xo + 17 - j, j + 5, j + 7, xo + 17 - j, j + 5, 20, L, L)
		p.box(xo + 24 - j, j + 1, j, xo + 24 - j, j + 1, 20, L, L)
		p.box(xo + j + 1, j + 1, j, xo + 23 - j, j + 1, j, L, L)
		p.box(xo + j + 8, j + 5, j + 7, xo + 16 - j, j + 5, j + 7, L, L)
	p.box(xo + 4, 4, 4, xo + 6, 4, 20, G, G)
	p.box(xo + 7, 4, 4, xo + 17, 4, 6, G, G)
	p.box(xo + 18, 4, 4, xo + 20, 4, 20, G, G)
	p.box(xo + 11, 8, 11, xo + 13, 8, 20, G, G)
	p.place(L, xo + 12, 9, 12)
	p.place(L, xo + 12, 9, 15)
	p.place(L, xo + 12, 9, 18)
	var j1 := xo + (19 if flipped else 5)
	var k1 := xo + (5 if flipped else 19)
	var l := 20
	while l >= 5:
		p.place(L, j1, 5, l)
		l -= 3
	l = 19
	while l >= 7:
		p.place(L, k1, 5, l)
		l -= 3
	for m in 4:
		var mx := xo + 24 - (17 - m * 3) if flipped else xo + 17 - m * 3
		p.place(L, mx, 5, 5)
	p.place(L, k1, 5, 5)
	p.box(xo + 11, 1, 12, xo + 13, 7, 12, G, G)
	p.box(xo + 12, 1, 11, xo + 12, 7, 13, G, G)


static func _mo_entry(p: P, el: Dictionary, L: int) -> void:
	var o: Array = el["f"]["r"]
	p.box(0, 3, 0, 2, 3, 7, L, L)
	p.box(5, 3, 0, 7, 3, 7, L, L)
	p.box(0, 2, 0, 1, 2, 7, L, L)
	p.box(6, 2, 0, 7, 2, 7, L, L)
	p.box(0, 1, 0, 0, 1, 7, L, L)
	p.box(7, 1, 0, 7, 1, 7, L, L)
	p.box(0, 1, 7, 7, 3, 7, L, L)
	p.box(1, 1, 0, 2, 3, 0, L, L)
	p.box(5, 1, 0, 6, 3, 0, L, L)
	if o[MD_NORTH]:
		_mo_water(p, 3, 1, 7, 4, 2, 7)
	if o[MD_WEST]:
		_mo_water(p, 0, 1, 3, 1, 2, 4)
	if o[MD_EAST]:
		_mo_water(p, 6, 1, 3, 7, 2, 4)


## The four side walls of a one-room cell at height y (3 high), with a 2-wide opening where the side is open.
static func _mo_walls_y(p: P, o: Array, y: int, L: int, G: int) -> void:
	if o[MD_SOUTH]:
		p.box(2, y, 0, 2, y + 2, 0, L, L)
		p.box(5, y, 0, 5, y + 2, 0, L, L)
		p.box(3, y + 2, 0, 4, y + 2, 0, L, L)
	else:
		p.box(0, y, 0, 7, y + 2, 0, L, L)
		p.box(0, y + 1, 0, 7, y + 1, 0, G, G)
	if o[MD_NORTH]:
		p.box(2, y, 7, 2, y + 2, 7, L, L)
		p.box(5, y, 7, 5, y + 2, 7, L, L)
		p.box(3, y + 2, 7, 4, y + 2, 7, L, L)
	else:
		p.box(0, y, 7, 7, y + 2, 7, L, L)
		p.box(0, y + 1, 7, 7, y + 1, 7, G, G)
	if o[MD_WEST]:
		p.box(0, y, 2, 0, y + 2, 2, L, L)
		p.box(0, y, 5, 0, y + 2, 5, L, L)
		p.box(0, y + 2, 3, 0, y + 2, 4, L, L)
	else:
		p.box(0, y, 0, 0, y + 2, 7, L, L)
		p.box(0, y + 1, 0, 0, y + 1, 7, G, G)
	if o[MD_EAST]:
		p.box(7, y, 2, 7, y + 2, 2, L, L)
		p.box(7, y, 5, 7, y + 2, 5, L, L)
		p.box(7, y + 2, 3, 7, y + 2, 4, L, L)
	else:
		p.box(7, y, 0, 7, y + 2, 7, L, L)
		p.box(7, y + 1, 0, 7, y + 1, 7, G, G)


static func _mo_simple(p: P, el: Dictionary, L: int, G: int, B: int, LAMP: int) -> void:
	var f: Dictionary = el["f"]
	var o: Array = f["r"]
	if int(el["idx"]) / 25 > 0:
		_mo_floor(p, 0, 0, o[MD_DOWN], L, G)
	if f["up_null"]:
		_mo_on_fill(p, 1, 4, 1, 6, 4, 6, G)
	var design := int(el["design"])
	var pillar: bool = design != 0 and p.r.next_bool() and not o[MD_DOWN] and not o[MD_UP] and _count(o) > 1
	if design == 0:
		for c in [[0, 0, 2, 2, 0, 1, 1], [5, 0, 7, 2, 7, 6, 1], [0, 5, 2, 7, 0, 1, 6], [5, 5, 7, 7, 7, 6, 6]]:
			# corner blocks: light top / bottom, gray middle ring, a lamp in the middle
			p.box(c[0], 1, c[1], c[2], 1, c[3], L, L)
			p.box(c[0], 3, c[1], c[2], 3, c[3], L, L)
		p.box(0, 2, 0, 0, 2, 2, G, G)
		p.box(1, 2, 0, 2, 2, 0, G, G)
		p.place(LAMP, 1, 2, 1)
		p.box(7, 2, 0, 7, 2, 2, G, G)
		p.box(5, 2, 0, 6, 2, 0, G, G)
		p.place(LAMP, 6, 2, 1)
		p.box(0, 2, 5, 0, 2, 7, G, G)
		p.box(1, 2, 7, 2, 2, 7, G, G)
		p.place(LAMP, 1, 2, 6)
		p.box(7, 2, 5, 7, 2, 7, G, G)
		p.box(5, 2, 7, 6, 2, 7, G, G)
		p.place(LAMP, 6, 2, 6)
		if o[MD_SOUTH]:
			p.box(3, 3, 0, 4, 3, 0, L, L)
		else:
			p.box(3, 3, 0, 4, 3, 1, L, L)
			p.box(3, 2, 0, 4, 2, 0, G, G)
			p.box(3, 1, 0, 4, 1, 1, L, L)
		if o[MD_NORTH]:
			p.box(3, 3, 7, 4, 3, 7, L, L)
		else:
			p.box(3, 3, 6, 4, 3, 7, L, L)
			p.box(3, 2, 7, 4, 2, 7, G, G)
			p.box(3, 1, 6, 4, 1, 7, L, L)
		if o[MD_WEST]:
			p.box(0, 3, 3, 0, 3, 4, L, L)
		else:
			p.box(0, 3, 3, 1, 3, 4, L, L)
			p.box(0, 2, 3, 0, 2, 4, G, G)
			p.box(0, 1, 3, 1, 1, 4, L, L)
		if o[MD_EAST]:
			p.box(7, 3, 3, 7, 3, 4, L, L)
		else:
			p.box(6, 3, 3, 7, 3, 4, L, L)
			p.box(7, 2, 3, 7, 2, 4, G, G)
			p.box(6, 1, 3, 7, 1, 4, L, L)
	elif design == 1:
		p.box(2, 1, 2, 2, 3, 2, L, L)
		p.box(2, 1, 5, 2, 3, 5, L, L)
		p.box(5, 1, 5, 5, 3, 5, L, L)
		p.box(5, 1, 2, 5, 3, 2, L, L)
		p.place(LAMP, 2, 2, 2)
		p.place(LAMP, 2, 2, 5)
		p.place(LAMP, 5, 2, 5)
		p.place(LAMP, 5, 2, 2)
		p.box(0, 1, 0, 1, 3, 0, L, L)
		p.box(0, 1, 1, 0, 3, 1, L, L)
		p.box(0, 1, 7, 1, 3, 7, L, L)
		p.box(0, 1, 6, 0, 3, 6, L, L)
		p.box(6, 1, 7, 7, 3, 7, L, L)
		p.box(7, 1, 6, 7, 3, 6, L, L)
		p.box(6, 1, 0, 7, 3, 0, L, L)
		p.box(7, 1, 1, 7, 3, 1, L, L)
		for q in [[1, 0], [0, 1], [1, 7], [0, 6], [6, 7], [7, 6], [6, 0], [7, 1]]:
			p.place(G, q[0], 2, q[1])
		if not o[MD_SOUTH]:
			p.box(1, 3, 0, 6, 3, 0, L, L)
			p.box(1, 2, 0, 6, 2, 0, G, G)
			p.box(1, 1, 0, 6, 1, 0, L, L)
		if not o[MD_NORTH]:
			p.box(1, 3, 7, 6, 3, 7, L, L)
			p.box(1, 2, 7, 6, 2, 7, G, G)
			p.box(1, 1, 7, 6, 1, 7, L, L)
		if not o[MD_WEST]:
			p.box(0, 3, 1, 0, 3, 6, L, L)
			p.box(0, 2, 1, 0, 2, 6, G, G)
			p.box(0, 1, 1, 0, 1, 6, L, L)
		if not o[MD_EAST]:
			p.box(7, 3, 1, 7, 3, 6, L, L)
			p.box(7, 2, 1, 7, 2, 6, G, G)
			p.box(7, 1, 1, 7, 1, 6, L, L)
	else:
		_mo_ring_walls(p, L, B)
		if o[MD_SOUTH]:
			_mo_water(p, 3, 1, 0, 4, 2, 0)
		if o[MD_NORTH]:
			_mo_water(p, 3, 1, 7, 4, 2, 7)
		if o[MD_WEST]:
			_mo_water(p, 0, 1, 3, 0, 2, 4)
		if o[MD_EAST]:
			_mo_water(p, 7, 1, 3, 7, 2, 4)
	if pillar:
		p.box(3, 1, 3, 4, 1, 4, L, L)
		p.box(3, 2, 3, 4, 2, 4, G, G)
		p.box(3, 3, 3, 4, 3, 4, L, L)


static func _count(o: Array) -> int:
	var k := 0
	for v in o:
		if v:
			k += 1
	return k


## Design 2 / sponge room walls: light bands at y 1 and 3, dark band at y 2, dark door frames.
static func _mo_ring_walls(p: P, L: int, B: int) -> void:
	p.box(0, 1, 0, 0, 1, 7, L, L)
	p.box(7, 1, 0, 7, 1, 7, L, L)
	p.box(1, 1, 0, 6, 1, 0, L, L)
	p.box(1, 1, 7, 6, 1, 7, L, L)
	p.box(0, 2, 0, 0, 2, 7, B, B)
	p.box(7, 2, 0, 7, 2, 7, B, B)
	p.box(1, 2, 0, 6, 2, 0, B, B)
	p.box(1, 2, 7, 6, 2, 7, B, B)
	p.box(0, 3, 0, 0, 3, 7, L, L)
	p.box(7, 3, 0, 7, 3, 7, L, L)
	p.box(1, 3, 0, 6, 3, 0, L, L)
	p.box(1, 3, 7, 6, 3, 7, L, L)
	p.box(0, 1, 3, 0, 2, 4, B, B)
	p.box(7, 1, 3, 7, 2, 4, B, B)
	p.box(3, 1, 0, 4, 2, 0, B, B)
	p.box(3, 1, 7, 4, 2, 7, B, B)


static func _mo_simple_top(p: P, el: Dictionary, L: int, G: int, B: int) -> void:
	var f: Dictionary = el["f"]
	var o: Array = f["r"]
	if int(el["idx"]) / 25 > 0:
		_mo_floor(p, 0, 0, o[MD_DOWN], L, G)
	if f["up_null"]:
		_mo_on_fill(p, 1, 4, 1, 6, 4, 6, G)
	var sponge := p.s("wet_sponge")
	for x in range(1, 7):
		for z in range(1, 7):
			if p.r.next_int_bound(3) != 0:
				var y := 2 + (0 if p.r.next_int_bound(4) == 0 else 1)
				p.box(x, y, z, x, 3, z, sponge, sponge)
	_mo_ring_walls(p, L, B)
	if o[MD_SOUTH]:
		_mo_water(p, 3, 1, 0, 4, 2, 0)


static func _mo_double_y(p: P, el: Dictionary, L: int, G: int) -> void:
	var f: Dictionary = el["f"]
	var o: Array = f["r"]
	if int(el["idx"]) / 25 > 0:
		_mo_floor(p, 0, 0, o[MD_DOWN], L, G)
	if f.get("u_up_null", true):
		_mo_on_fill(p, 1, 8, 1, 6, 8, 6, G)
	p.box(0, 4, 0, 0, 4, 7, L, L)
	p.box(7, 4, 0, 7, 4, 7, L, L)
	p.box(1, 4, 0, 6, 4, 0, L, L)
	p.box(1, 4, 7, 6, 4, 7, L, L)
	p.box(2, 4, 1, 2, 4, 2, L, L)
	p.box(1, 4, 2, 1, 4, 2, L, L)
	p.box(5, 4, 1, 5, 4, 2, L, L)
	p.box(6, 4, 2, 6, 4, 2, L, L)
	p.box(2, 4, 5, 2, 4, 6, L, L)
	p.box(1, 4, 5, 1, 4, 5, L, L)
	p.box(5, 4, 5, 5, 4, 6, L, L)
	p.box(6, 4, 5, 6, 4, 5, L, L)
	_mo_walls_y(p, o, 1, L, G)
	_mo_walls_y(p, f.get("u", o), 5, L, G)


static func _mo_double_x(p: P, el: Dictionary, L: int, G: int, LAMP: int) -> void:
	var f: Dictionary = el["f"]
	var o: Array = f["r"]
	var e: Array = f["e"]
	if int(el["idx"]) / 25 > 0:
		_mo_floor(p, 8, 0, e[MD_DOWN], L, G)
		_mo_floor(p, 0, 0, o[MD_DOWN], L, G)
	if f["up_null"]:
		_mo_on_fill(p, 1, 4, 1, 7, 4, 6, G)
	if f["e_up_null"]:
		_mo_on_fill(p, 8, 4, 1, 14, 4, 6, G)
	for y in [[3, L], [2, G], [1, L]]:
		p.box(0, y[0], 0, 0, y[0], 7, y[1], y[1])
		p.box(15, y[0], 0, 15, y[0], 7, y[1], y[1])
		p.box(1, y[0], 0, 15, y[0], 0, y[1], y[1])
		p.box(1, y[0], 7, 14, y[0], 7, y[1], y[1])
	p.box(5, 1, 0, 10, 1, 4, L, L)
	p.box(6, 2, 0, 9, 2, 3, G, G)
	p.box(5, 3, 0, 10, 3, 4, L, L)
	p.place(LAMP, 6, 2, 3)
	p.place(LAMP, 9, 2, 3)
	if o[MD_SOUTH]:
		_mo_water(p, 3, 1, 0, 4, 2, 0)
	if o[MD_NORTH]:
		_mo_water(p, 3, 1, 7, 4, 2, 7)
	if o[MD_WEST]:
		_mo_water(p, 0, 1, 3, 0, 2, 4)
	if e[MD_SOUTH]:
		_mo_water(p, 11, 1, 0, 12, 2, 0)
	if e[MD_NORTH]:
		_mo_water(p, 11, 1, 7, 12, 2, 7)
	if e[MD_EAST]:
		_mo_water(p, 15, 1, 3, 15, 2, 4)


static func _mo_double_z(p: P, el: Dictionary, L: int, G: int, LAMP: int) -> void:
	var f: Dictionary = el["f"]
	var o: Array = f["r"]
	var nn: Array = f["n"]
	if int(el["idx"]) / 25 > 0:
		_mo_floor(p, 0, 8, nn[MD_DOWN], L, G)
		_mo_floor(p, 0, 0, o[MD_DOWN], L, G)
	if f["up_null"]:
		_mo_on_fill(p, 1, 4, 1, 6, 4, 7, G)
	if f["n_up_null"]:
		_mo_on_fill(p, 1, 4, 8, 6, 4, 14, G)
	for y in [[3, L], [2, G], [1, L]]:
		p.box(0, y[0], 0, 0, y[0], 15, y[1], y[1])
		p.box(7, y[0], 0, 7, y[0], 15, y[1], y[1])
		p.box(1, y[0], 0, 7, y[0], 0, y[1], y[1])
		p.box(1, y[0], 15, 6, y[0], 15, y[1], y[1])
	p.box(1, 1, 1, 1, 1, 2, L, L)
	p.box(6, 1, 1, 6, 1, 2, L, L)
	p.box(1, 3, 1, 1, 3, 2, L, L)
	p.box(6, 3, 1, 6, 3, 2, L, L)
	p.box(1, 1, 13, 1, 1, 14, L, L)
	p.box(6, 1, 13, 6, 1, 14, L, L)
	p.box(1, 3, 13, 1, 3, 14, L, L)
	p.box(6, 3, 13, 6, 3, 14, L, L)
	p.box(2, 1, 6, 2, 3, 6, L, L)
	p.box(5, 1, 6, 5, 3, 6, L, L)
	p.box(2, 1, 9, 2, 3, 9, L, L)
	p.box(5, 1, 9, 5, 3, 9, L, L)
	p.box(3, 2, 6, 4, 2, 6, L, L)
	p.box(3, 2, 9, 4, 2, 9, L, L)
	p.box(2, 2, 7, 2, 2, 8, L, L)
	p.box(5, 2, 7, 5, 2, 8, L, L)
	p.place(LAMP, 2, 2, 5)
	p.place(LAMP, 5, 2, 5)
	p.place(LAMP, 2, 2, 10)
	p.place(LAMP, 5, 2, 10)
	p.place(L, 2, 3, 5)
	p.place(L, 5, 3, 5)
	p.place(L, 2, 3, 10)
	p.place(L, 5, 3, 10)
	if o[MD_SOUTH]:
		_mo_water(p, 3, 1, 0, 4, 2, 0)
	if o[MD_EAST]:
		_mo_water(p, 7, 1, 3, 7, 2, 4)
	if o[MD_WEST]:
		_mo_water(p, 0, 1, 3, 0, 2, 4)
	if nn[MD_NORTH]:
		_mo_water(p, 3, 1, 15, 4, 2, 15)
	if nn[MD_WEST]:
		_mo_water(p, 0, 1, 11, 0, 2, 12)
	if nn[MD_EAST]:
		_mo_water(p, 7, 1, 11, 7, 2, 12)


static func _mo_double_xy(p: P, el: Dictionary, L: int, G: int, LAMP: int) -> void:
	var f: Dictionary = el["f"]
	var o: Array = f["r"]
	var e: Array = f["e"]
	var u: Array = f["u"]
	var eu: Array = f["eu"]
	if int(el["idx"]) / 25 > 0:
		_mo_floor(p, 8, 0, e[MD_DOWN], L, G)
		_mo_floor(p, 0, 0, o[MD_DOWN], L, G)
	if f["u_up_null"]:
		_mo_on_fill(p, 1, 8, 1, 7, 8, 6, G)
	if f["eu_up_null"]:
		_mo_on_fill(p, 8, 8, 1, 14, 8, 6, G)
	for y in range(1, 8):
		var st := G if y == 2 or y == 6 else L
		p.box(0, y, 0, 0, y, 7, st, st)
		p.box(15, y, 0, 15, y, 7, st, st)
		p.box(1, y, 0, 15, y, 0, st, st)
		p.box(1, y, 7, 14, y, 7, st, st)
	p.box(2, 1, 3, 2, 7, 4, L, L)
	p.box(3, 1, 2, 4, 7, 2, L, L)
	p.box(3, 1, 5, 4, 7, 5, L, L)
	p.box(13, 1, 3, 13, 7, 4, L, L)
	p.box(11, 1, 2, 12, 7, 2, L, L)
	p.box(11, 1, 5, 12, 7, 5, L, L)
	p.box(5, 1, 3, 5, 3, 4, L, L)
	p.box(10, 1, 3, 10, 3, 4, L, L)
	p.box(5, 7, 2, 10, 7, 5, L, L)
	p.box(5, 5, 2, 5, 7, 2, L, L)
	p.box(10, 5, 2, 10, 7, 2, L, L)
	p.box(5, 5, 5, 5, 7, 5, L, L)
	p.box(10, 5, 5, 10, 7, 5, L, L)
	p.place(L, 6, 6, 2)
	p.place(L, 9, 6, 2)
	p.place(L, 6, 6, 5)
	p.place(L, 9, 6, 5)
	p.box(5, 4, 3, 6, 4, 4, L, L)
	p.box(9, 4, 3, 10, 4, 4, L, L)
	p.place(LAMP, 5, 4, 2)
	p.place(LAMP, 5, 4, 5)
	p.place(LAMP, 10, 4, 2)
	p.place(LAMP, 10, 4, 5)
	if o[MD_SOUTH]:
		_mo_water(p, 3, 1, 0, 4, 2, 0)
	if o[MD_NORTH]:
		_mo_water(p, 3, 1, 7, 4, 2, 7)
	if o[MD_WEST]:
		_mo_water(p, 0, 1, 3, 0, 2, 4)
	if e[MD_SOUTH]:
		_mo_water(p, 11, 1, 0, 12, 2, 0)
	if e[MD_NORTH]:
		_mo_water(p, 11, 1, 7, 12, 2, 7)
	if e[MD_EAST]:
		_mo_water(p, 15, 1, 3, 15, 2, 4)
	if u[MD_SOUTH]:
		_mo_water(p, 3, 5, 0, 4, 6, 0)
	if u[MD_NORTH]:
		_mo_water(p, 3, 5, 7, 4, 6, 7)
	if u[MD_WEST]:
		_mo_water(p, 0, 5, 3, 0, 6, 4)
	if eu[MD_SOUTH]:
		_mo_water(p, 11, 5, 0, 12, 6, 0)
	if eu[MD_NORTH]:
		_mo_water(p, 11, 5, 7, 12, 6, 7)
	if eu[MD_EAST]:
		_mo_water(p, 15, 5, 3, 15, 6, 4)


static func _mo_double_yz(p: P, el: Dictionary, L: int, G: int, B: int, LAMP: int) -> void:
	var f: Dictionary = el["f"]
	var o: Array = f["r"]
	var nn: Array = f["n"]
	var u: Array = f["u"]
	var nu: Array = f["nu"]
	if int(el["idx"]) / 25 > 0:
		_mo_floor(p, 0, 8, nn[MD_DOWN], L, G)
		_mo_floor(p, 0, 0, o[MD_DOWN], L, G)
	if f["u_up_null"]:
		_mo_on_fill(p, 1, 8, 1, 6, 8, 7, G)
	if f["nu_up_null"]:
		_mo_on_fill(p, 1, 8, 8, 6, 8, 14, G)
	for y in range(1, 8):
		var st := G if y == 2 or y == 6 else L
		p.box(0, y, 0, 0, y, 15, st, st)
		p.box(7, y, 0, 7, y, 15, st, st)
		p.box(1, y, 0, 6, y, 0, st, st)
		p.box(1, y, 15, 6, y, 15, st, st)
	for y2 in range(1, 8):
		var st2 := LAMP if y2 == 2 or y2 == 6 else B
		p.box(3, y2, 7, 4, y2, 8, st2, st2)
	if o[MD_SOUTH]:
		_mo_water(p, 3, 1, 0, 4, 2, 0)
	if o[MD_EAST]:
		_mo_water(p, 7, 1, 3, 7, 2, 4)
	if o[MD_WEST]:
		_mo_water(p, 0, 1, 3, 0, 2, 4)
	if nn[MD_NORTH]:
		_mo_water(p, 3, 1, 15, 4, 2, 15)
	if nn[MD_WEST]:
		_mo_water(p, 0, 1, 11, 0, 2, 12)
	if nn[MD_EAST]:
		_mo_water(p, 7, 1, 11, 7, 2, 12)
	if u[MD_SOUTH]:
		_mo_water(p, 3, 5, 0, 4, 6, 0)
	if u[MD_EAST]:
		_mo_water(p, 7, 5, 3, 7, 6, 4)
		p.box(5, 4, 2, 6, 4, 5, L, L)
		p.box(6, 1, 2, 6, 3, 2, L, L)
		p.box(6, 1, 5, 6, 3, 5, L, L)
	if u[MD_WEST]:
		_mo_water(p, 0, 5, 3, 0, 6, 4)
		p.box(1, 4, 2, 2, 4, 5, L, L)
		p.box(1, 1, 2, 1, 3, 2, L, L)
		p.box(1, 1, 5, 1, 3, 5, L, L)
	if nu[MD_NORTH]:
		_mo_water(p, 3, 5, 15, 4, 6, 15)
	if nu[MD_WEST]:
		_mo_water(p, 0, 5, 11, 0, 6, 12)
		p.box(1, 4, 10, 2, 4, 13, L, L)
		p.box(1, 1, 10, 1, 3, 10, L, L)
		p.box(1, 1, 13, 1, 3, 13, L, L)
	if nu[MD_EAST]:
		_mo_water(p, 7, 5, 11, 7, 6, 12)
		p.box(5, 4, 10, 6, 4, 13, L, L)
		p.box(6, 1, 10, 6, 3, 10, L, L)
		p.box(6, 1, 13, 6, 3, 13, L, L)


static func _mo_core(p: P, L: int, G: int, B: int, LAMP: int) -> void:
	_mo_on_fill(p, 1, 8, 0, 14, 8, 14, G)
	p.box(0, 7, 0, 0, 7, 15, L, L)
	p.box(15, 7, 0, 15, 7, 15, L, L)
	p.box(1, 7, 0, 15, 7, 0, L, L)
	p.box(1, 7, 15, 14, 7, 15, L, L)
	for y in range(1, 7):
		var st := G if y == 2 or y == 6 else L
		for x in [0, 15]:
			p.box(x, y, 0, x, y, 1, st, st)
			p.box(x, y, 6, x, y, 9, st, st)
			p.box(x, y, 14, x, y, 15, st, st)
		p.box(1, y, 0, 1, y, 0, st, st)
		p.box(6, y, 0, 9, y, 0, st, st)
		p.box(14, y, 0, 14, y, 0, st, st)
		p.box(1, y, 15, 14, y, 15, st, st)
	p.box(6, 3, 6, 9, 6, 9, B, B)
	var gold := p.s("gold_block")
	p.box(7, 4, 7, 8, 5, 8, gold, gold)
	for y2 in [3, 6]:
		for x2 in [6, 9]:
			p.place(LAMP, x2, y2, 6)
			p.place(LAMP, x2, y2, 9)
	for q in [[5, 1, 6, 5, 2, 6], [5, 1, 9, 5, 2, 9], [10, 1, 6, 10, 2, 6], [10, 1, 9, 10, 2, 9], [6, 1, 5, 6, 2, 5], [9, 1, 5, 9, 2, 5],
			[6, 1, 10, 6, 2, 10], [9, 1, 10, 9, 2, 10], [5, 2, 5, 5, 6, 5], [5, 2, 10, 5, 6, 10], [10, 2, 5, 10, 6, 5], [10, 2, 10, 10, 6, 10],
			[5, 7, 1, 5, 7, 6], [10, 7, 1, 10, 7, 6], [5, 7, 9, 5, 7, 14], [10, 7, 9, 10, 7, 14], [1, 7, 5, 6, 7, 5], [1, 7, 10, 6, 7, 10],
			[9, 7, 5, 14, 7, 5], [9, 7, 10, 14, 7, 10], [2, 1, 2, 2, 1, 3], [3, 1, 2, 3, 1, 2], [13, 1, 2, 13, 1, 3], [12, 1, 2, 12, 1, 2],
			[2, 1, 12, 2, 1, 13], [3, 1, 13, 3, 1, 13], [13, 1, 12, 13, 1, 13], [12, 1, 13, 12, 1, 13]]:
		p.box(q[0], q[1], q[2], q[3], q[4], q[5], L, L)


static func _mo_wing(p: P, el: Dictionary, L: int, B: int, LAMP: int) -> void:
	if int(el["design"]) == 0:
		for i in 4:
			p.box(10 - i, 3 - i, 20 - i, 12 + i, 3 - i, 20, L, L)
		p.box(7, 0, 6, 15, 0, 16, L, L)
		p.box(6, 0, 6, 6, 3, 20, L, L)
		p.box(16, 0, 6, 16, 3, 20, L, L)
		p.box(7, 1, 7, 7, 1, 20, L, L)
		p.box(15, 1, 7, 15, 1, 20, L, L)
		p.box(7, 1, 6, 9, 3, 6, L, L)
		p.box(13, 1, 6, 15, 3, 6, L, L)
		p.box(8, 1, 7, 9, 1, 7, L, L)
		p.box(13, 1, 7, 14, 1, 7, L, L)
		p.box(9, 0, 5, 13, 0, 5, L, L)
		p.box(10, 0, 7, 12, 0, 7, B, B)
		p.box(8, 0, 10, 8, 0, 12, B, B)
		p.box(14, 0, 10, 14, 0, 12, B, B)
		var z := 18
		while z >= 7:
			p.place(LAMP, 6, 3, z)
			p.place(LAMP, 16, 3, z)
			z -= 3
		p.place(LAMP, 10, 0, 10)
		p.place(LAMP, 12, 0, 10)
		p.place(LAMP, 10, 0, 12)
		p.place(LAMP, 12, 0, 12)
		p.place(LAMP, 8, 3, 6)
		p.place(LAMP, 14, 3, 6)
		for q in [[4, 4], [18, 4], [4, 18], [18, 18]]:
			p.place(L, q[0], 2, q[1])
			p.place(LAMP, q[0], 1, q[1])
			p.place(L, q[0], 0, q[1])
		p.place(L, 9, 7, 20)
		p.place(L, 13, 7, 20)
		p.box(6, 0, 21, 7, 4, 21, L, L)
		p.box(15, 0, 21, 16, 4, 21, L, L)
		_mo_elder(p, 11, 2, 16)
	else:
		p.box(9, 3, 18, 13, 3, 20, L, L)
		p.box(9, 0, 18, 9, 2, 18, L, L)
		p.box(13, 0, 18, 13, 2, 18, L, L)
		for x in [9, 13]:
			p.place(L, x, 6, 20)
			p.place(LAMP, x, 5, 20)
			p.place(L, x, 4, 20)
		p.box(7, 3, 7, 15, 3, 14, L, L)
		for x2 in [10, 12]:
			p.box(x2, 0, 10, x2, 6, 10, L, L)
			p.box(x2, 0, 12, x2, 6, 12, L, L)
			p.place(LAMP, x2, 0, 10)
			p.place(LAMP, x2, 0, 12)
			p.place(LAMP, x2, 4, 10)
			p.place(LAMP, x2, 4, 12)
		for x3 in [8, 14]:
			p.box(x3, 0, 7, x3, 2, 7, L, L)
			p.box(x3, 0, 14, x3, 2, 14, L, L)
		p.box(8, 3, 8, 8, 3, 13, B, B)
		p.box(14, 3, 8, 14, 3, 13, B, B)
		_mo_elder(p, 11, 5, 13)


static func _mo_penthouse(p: P, L: int, G: int, B: int, LAMP: int) -> void:
	p.box(2, -1, 2, 11, -1, 11, L, L)
	p.box(0, -1, 0, 1, -1, 11, G, G)
	p.box(12, -1, 0, 13, -1, 11, G, G)
	p.box(2, -1, 0, 11, -1, 1, G, G)
	p.box(2, -1, 12, 11, -1, 13, G, G)
	p.box(0, 0, 0, 0, 0, 13, L, L)
	p.box(13, 0, 0, 13, 0, 13, L, L)
	p.box(1, 0, 0, 12, 0, 0, L, L)
	p.box(1, 0, 13, 12, 0, 13, L, L)
	var i := 2
	while i <= 11:
		p.place(LAMP, 0, 0, i)
		p.place(LAMP, 13, 0, i)
		p.place(LAMP, i, 0, 0)
		i += 3
	p.box(2, 0, 3, 4, 0, 9, L, L)
	p.box(9, 0, 3, 11, 0, 9, L, L)
	p.box(4, 0, 9, 9, 0, 11, L, L)
	p.place(L, 5, 0, 8)
	p.place(L, 8, 0, 8)
	p.place(L, 10, 0, 10)
	p.place(L, 3, 0, 10)
	p.box(3, 0, 3, 3, 0, 7, B, B)
	p.box(10, 0, 3, 10, 0, 7, B, B)
	p.box(6, 0, 10, 7, 0, 10, B, B)
	for x in [3, 10]:
		var k := 2
		while k <= 8:
			p.box(x, 0, k, x, 2, k, L, L)
			k += 3
	p.box(5, 0, 10, 5, 2, 10, L, L)
	p.box(8, 0, 10, 8, 2, 10, L, L)
	p.box(6, -1, 7, 7, -1, 8, B, B)
	_mo_water(p, 6, -1, 3, 7, -1, 4)
	_mo_elder(p, 6, 1, 6)
