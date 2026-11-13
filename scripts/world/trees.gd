## Trees — tree / fallen tree / huge mushroom features for Features. Trunk placers: straight, forking, giant,
## mega_jungle, dark_oak, fancy, bending, upwards_branching, cherry; foliage placers: blob, bush, spruce, pine,
## acacia, fancy, jungle, mega_pine, dark_oak, random_spread, cherry. Blob/bush/spruce/pine/acacia/fancy/jungle
## row logic follows Java FoliagePlacer formulas (source D); multi-branch trunk placers are APPROXIMATIONS.
class_name Trees


static func _valid(f: Features, c: Features.FCtx, p: Vector3i) -> bool:
	var st: int = f.get_block(c, p)
	if st == 0:
		return true
	if st < 0:
		return false
	var fl: int = f.blocks.st_flags[st]
	return (fl & (BlockRegistry.F_REPLACEABLE | BlockRegistry.F_LEAVES)) != 0 and (fl & BlockRegistry.F_LIQUID) == 0


static func _log(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i, axis: String = "y") -> void:
	if not _valid(f, c, p):
		var st: int = f.get_block(c, p)
		if st > 0 and not f.blocks.name_of(st).ends_with("_log"):
			return
	var s: int = f.provide(c, cf["trunk"], p)
	if s > 0 and f.blocks.has_prop(s, "axis"):
		s = f.blocks.with_prop(s, "axis", axis)
	f.set_block(c, p, s, 0)
	c.tree_logs.append(p)


static func _leaf(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i) -> bool:
	if _valid(f, c, p):
		f.set_block(c, p, f.provide(c, cf["foliage"], p), 1)
		c.tree_leaves.append(p)
		c.tree_leaf_set[p] = true
		return true
	return false


static func _row(f: Features, c: Features.FCtx, cf: Dictionary, center: Vector3i, rng: int, ly: int, dbl: bool, kind: String) -> void:
	var i := 1 if dbl else 0
	for j in range(-rng, rng + 1 + i):
		for k in range(-rng, rng + 1 + i):
			var ax := absi(j)
			var az := absi(k)
			if dbl:
				ax = mini(absi(j), absi(j - 1))
				az = mini(absi(k), absi(k - 1))
			# Java DarkOakFoliagePlacer.shouldSkipLocationSigned: double-trunk row 0 drops its four outer corners
			if kind == "dark_oak" and ly == 0 and dbl and (j == -rng or j >= rng) and (k == -rng or k >= rng):
				continue
			if kind == "dark_oak":
				if (ly == -1 and not dbl and ax == rng and az == rng) or (ly == 1 and ax + az > rng * 2 - 2):
					continue
				_leaf(f, c, cf, center + Vector3i(j, ly, k))
				continue
			if _skip(c, kind, ax, ly, az, rng):
				continue
			_leaf(f, c, cf, center + Vector3i(j, ly, k))


static func _skip(c: Features.FCtx, kind: String, x: int, y: int, z: int, rng: int) -> bool:
	match kind:
		"blob", "bush", "cherry":
			return x == rng and z == rng and (c.r.next_int_bound(2) == 0 or y == 0)
		"spruce", "pine":
			return x == rng and z == rng and rng > 0
		"mega_pine":   # Java MegaPineFoliagePlacer.shouldSkipLocation: round rows, no far diagonals
			return x + z >= 7 or x * x + z * z > rng * rng
		"acacia":
			if y == 0:
				return (x > 1 or z > 1) and x != 0 and z != 0
			return x == rng and z == rng and rng > 0
		"fancy":
			return (x + 0.5) * (x + 0.5) + (z + 0.5) * (z + 0.5) > rng * rng
		"jungle":
			return x + z >= 7 or x * x + z * z > rng * rng
		"dark_oak":
			return y == 0 and x == rng and z == rng
	return false


static func place(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var tp: Dictionary = cf["tp"]
	var fp: Dictionary = cf["fp"]
	var ttype := str(tp.get("type", "minecraft:straight_trunk_placer")).trim_prefix("minecraft:")
	var ftype := str(fp.get("type", "minecraft:blob_foliage_placer")).trim_prefix("minecraft:").trim_suffix("_foliage_placer")
	var h := int(tp.get("base_height", 4)) + c.r.next_int_bound(int(tp.get("height_rand_a", 2)) + 1) + c.r.next_int_bound(int(tp.get("height_rand_b", 0)) + 1)
	var fh := _foliage_height(f, c, fp, ftype, h)
	var radius := f.sample_int(c, fp.get("radius", 2))
	var offset := f.sample_int(c, fp.get("offset", 0))
	var dbl := ttype in ["giant_trunk_placer", "mega_jungle_trunk_placer", "dark_oak_trunk_placer"]
	c.tree_logs = []
	c.tree_leaves = []
	c.tree_leaf_set = {}
	if p.y < Coords.MIN_Y + 1 or p.y + h + 1 >= Coords.MAX_Y:
		return false
	# space check along trunk
	for y in h:
		for dx in (2 if dbl else 1):
			for dz in (2 if dbl else 1):
				if not _valid(f, c, p + Vector3i(dx, y, dz)):
					return false
	# Java 26.x TrunkPlacer.placeBelowTrunkBlock under every trunk column: below_trunk_provider (soil_beneath_tree:
	# dirt unless the block is in cannot_replace_below_tree_trunk) - air under an overhanging 2x2 corner becomes dirt
	for dx in (2 if dbl else 1):
		for dz in (2 if dbl else 1):
			var below: Vector3i = p + Vector3i(dx, -1, dz)
			var soil: int = f.provide(c, cf["soil"], below)
			if soil > 0:
				f.set_block(c, below, soil, 0)
	var atts: Array = []   # [pos, radius_offset, double]
	match ttype:
		"straight_trunk_placer":
			for y in h:
				_log(f, c, cf, p + Vector3i(0, y, 0))
			atts.append([p + Vector3i(0, h, 0), 0, false])
		"dark_oak_trunk_placer":
			# Java DarkOakTrunkPlacer: 2x2 trunk that may shift sideways near the top, plus random hanging logs in the
			# 4x4 ring around the top (each with its own foliage attachment)
			var dir2: Vector3i = [Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)][c.r.next_int_bound(4)]
			var si := h - c.r.next_int_bound(4)
			var sj := 2 - c.r.next_int_bound(3)
			var nx := p.x
			var nz := p.z
			var top := p.y + h - 1
			for q in h:
				if q >= si and sj > 0:
					nx += dir2.x
					nz += dir2.z
					sj -= 1
				var b := Vector3i(nx, p.y + q, nz)
				if _valid(f, c, b):
					for o in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)]:
						_log(f, c, cf, b + o)
			atts.append([Vector3i(nx, top, nz), 0, true])
			for q in range(-1, 3):
				for r in range(-1, 3):
					if (q < 0 or q > 1 or r < 0 or r > 1) and c.r.next_int_bound(3) <= 0:
						var s2 := c.r.next_int_bound(3) + 2
						for t2 in s2:
							_log(f, c, cf, Vector3i(p.x + q, top - t2 - 1, p.z + r))
						atts.append([Vector3i(p.x + q, top, p.z + r), 0, false])
		"giant_trunk_placer":
			for y in h:
				for dx in 2:
					for dz in 2:
						_log(f, c, cf, p + Vector3i(dx, y, dz))
			atts.append([p + Vector3i(0, h, 0), 0, true])
		"mega_jungle_trunk_placer":
			for y in h:
				for dx in 2:
					for dz in 2:
						_log(f, c, cf, p + Vector3i(dx, y, dz))
			atts.append([p + Vector3i(0, h, 0), 0, true])
			# Java MegaJungleTrunkPlacer: branches of 5 upright logs out from the trunk centre (1.5, 1.5) at
			# (int)(1.5F + Mth.cos(f) * l), rising every second log; foliage (radius -2) on the last one
			var y2 := h - 2 - c.r.next_int_bound(4)
			while y2 > h / 2:
				var a := _f32(c.r.next_float() * _f32(TAU))
				var bx := 0
				var bz := 0
				for k in 5:
					bx = int(_f32(1.5 + _f32(_mth_cos(a) * k)))
					bz = int(_f32(1.5 + _f32(_mth_sin(a) * k)))
					_log(f, c, cf, p + Vector3i(bx, y2 - 3 + k / 2, bz))
				atts.append([p + Vector3i(bx, y2, bz), -2, false])
				y2 -= 2 + c.r.next_int_bound(4)
		"cherry_trunk_placer":
			_cherry_trunk(f, c, cf, tp, p, h, atts)
		"poplar_trunk_placer":
			_poplar_trunk(f, c, cf, tp, p, h, atts)
		"forking_trunk_placer", "bending_trunk_placer", "upwards_branching_trunk_placer":
			var dir: Vector3i = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)][c.r.next_int_bound(4)]
			var bend := h - c.r.next_int_bound(4) - 1
			var bl := 3 - c.r.next_int_bound(3)
			var q := p
			for y in h:
				if y >= bend and bl > 0:
					q += dir
					bl -= 1
				_log(f, c, cf, Vector3i(q.x, p.y + y, q.z))
			atts.append([Vector3i(q.x, p.y + h, q.z), 0, false])
			if ttype != "bending_trunk_placer" and c.r.next_bool():
				var d2: Vector3i = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)][c.r.next_int_bound(4)]
				if d2 != dir:
					var s := bend - c.r.next_int_bound(2) - 1
					var q2 := Vector3i(p.x, p.y + s, p.z)
					for k in 1 + c.r.next_int_bound(3):
						q2 += d2 + Vector3i(0, 1, 0)
						_log(f, c, cf, q2)
					atts.append([q2 + Vector3i(0, 1, 0), 0, false])
		"fancy_trunk_placer":
			_fancy_trunk(f, c, cf, p, h, atts)
		_:
			for y in h:
				_log(f, c, cf, p + Vector3i(0, y, 0))
			atts.append([p + Vector3i(0, h, 0), 0, false])
	for at in atts:
		_foliage(f, c, cf, fp, ftype, at[0], int(at[1]), at[2], fh, radius, offset)
	_decorators(f, c, cf, p, h)
	return true


static func _foliage_height(f: Features, c: Features.FCtx, fp: Dictionary, ftype: String, h: int) -> int:
	match ftype:
		"spruce":
			return maxi(4, h - f.sample_int(c, fp.get("trunk_height", 1)))
		"pine":
			return f.sample_int(c, fp.get("height", 4))
		"mega_pine":
			return f.sample_int(c, fp.get("crown_height", 13))
		"jungle", "blob", "bush", "fancy", "cherry", "poplar":
			return int(f.sample_int(c, fp.get("height", 3)))
		"acacia", "dark_oak":
			return 0 if ftype == "acacia" else 4
		"random_spread":
			return f.sample_int(c, fp.get("foliage_height", 2))
	return 3


static func _foliage(f: Features, c: Features.FCtx, cf: Dictionary, fp: Dictionary, ftype: String, at: Vector3i, ro: int, dbl: bool, fh: int, radius: int, offset: int) -> void:
	match ftype:
		"cherry":
			_cherry_foliage(f, c, cf, fp, at + Vector3i(0, offset, 0), radius + ro - 1, fh, dbl)
		"poplar":
			_poplar_foliage(f, c, cf, fp, at + Vector3i(0, offset, 0), radius + ro, fh, dbl)
		"blob":
			for l in range(offset, offset - fh - 1, -1):
				var m := maxi(radius + ro - 1 - int(l / 2.0), 0)
				_row(f, c, cf, at, m, l, dbl, ftype)
		"bush":
			for l in range(offset, offset - fh - 1, -1):
				var m2 := maxi(radius + ro - 1 - l, 0)
				_row(f, c, cf, at, m2, l, dbl, "bush")
		"spruce":
			var i := c.r.next_int_bound(2)
			var j := 1
			var k := 0
			for l in range(offset, -fh - 1, -1):
				_row(f, c, cf, at, i, l, dbl, "spruce")
				if i >= j:
					i = k
					k = 1
					j = mini(j + 1, radius + ro)
				else:
					i += 1
		"pine":
			var i2 := 0
			for l in range(offset, offset - fh - 1, -1):
				_row(f, c, cf, at, i2, l, dbl, "pine")
				if i2 >= 1 and l == offset - fh + 1:
					i2 -= 1
				elif i2 < radius + ro:
					i2 += 1
		"mega_pine":
			# Java MegaPineFoliagePlacer.createFoliage: the radius grows by floor(depth / crown height * 3.5) (float32)
			# below the top, every second row one wider when the smooth radius repeats (vanilla giant spruce / pine cone)
			var y := at.y
			var prev := 0
			for l in range(y - fh + offset, y + offset + 1):
				var k := y - l
				var sm := radius + ro + int(floor(_f32(_f32(float(k) / float(fh)) * 3.5)))
				var rr := sm + 1 if k > 0 and sm == prev and (l & 1) == 0 else sm
				_row(f, c, cf, Vector3i(at.x, l, at.z), rr, 0, dbl, "mega_pine")
				prev = sm
		"acacia":
			var base := at + Vector3i(0, offset, 0)
			_row(f, c, cf, base, radius + ro, -1 - fh, dbl, "acacia")
			_row(f, c, cf, base, radius - 1, -fh, dbl, "acacia")
			_row(f, c, cf, base, radius + ro - 1, 0, dbl, "acacia")
		"fancy":
			for l in range(offset, offset - fh - 1, -1):
				var m3 := radius + (1 if l != offset and l != offset - fh else 0)
				_row(f, c, cf, at, m3, l, dbl, "fancy")
		"jungle":
			var cnt := fh if dbl else 1 + c.r.next_int_bound(2)
			for l in range(offset, offset - cnt - 1, -1):
				_row(f, c, cf, at, radius + ro + 1 - l, l, dbl, "jungle")
		"dark_oak":
			# Java DarkOakFoliagePlacer.createFoliage
			var base2 := at + Vector3i(0, offset, 0)
			if dbl:
				_row(f, c, cf, base2, radius + 2, -1, true, "dark_oak")
				_row(f, c, cf, base2, radius + 3, 0, true, "dark_oak")
				_row(f, c, cf, base2, radius + 2, 1, true, "dark_oak")
				if c.r.next_bool():
					_row(f, c, cf, base2, radius, 2, true, "dark_oak")
			else:
				_row(f, c, cf, base2, radius + 2, -1, false, "dark_oak")
				_row(f, c, cf, base2, radius + 1, 0, false, "dark_oak")
		"random_spread":
			var cnt2 := int(fp.get("leaf_placement_attempts", 50))
			for n in cnt2:
				var q := at + Vector3i(c.r.next_int_bound(radius * 2 + 1) - radius, c.r.next_int_bound(fh + 1) - fh / 2, c.r.next_int_bound(radius * 2 + 1) - radius)
				_leaf(f, c, cf, q)
		_:
			for l in range(offset, offset - 3, -1):
				_row(f, c, cf, at, maxi(radius - int(l / 2.0), 0), l, dbl, "blob")


## Rounds to float32 (Java float arithmetic in placer formulas).
## Java FancyTrunkPlacer (the classic BigTree): tree height j = h + 2, trunk floor(j * 0.618); from j - 5 down to
## 30 % of j one limb per level (Java min(1, ..) = 1) at a random angle, radius treeShape * (r + 0.328); a limb is kept
## when the 5-block rise above its end and the slope back to the trunk (0.381 per block) are free; branches below
## 20 % of j carry no foliage. Foliage clusters (FancyFoliagePlacer) at every kept limb end and the top.
static func _fancy_trunk(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i, h: int, atts: Array) -> void:
	var jh := h + 2
	var tk := int(floor(jh * 0.618))
	var i1 := p.y + tk
	var j1 := jh - 5
	var coords: Array = [[p + Vector3i(0, j1, 0), i1]]   # [foliage attachment, branch base y]
	while j1 >= 0:
		var fs := _fancy_shape(jh, j1)
		if fs >= 0.0:
			var d2 := float(fs) * (c.r.next_float() + 0.328)
			var d3 := _f32(c.r.next_float() * 2.0) * PI
			var bp := p + Vector3i(int(floor(d2 * sin(d3) + 0.5)), j1 - 1, int(floor(d2 * cos(d3) + 0.5)))
			if _fancy_limb(f, c, cf, bp, bp + Vector3i(0, 5, 0), false):
				var dx := p.x - bp.x
				var dz := p.z - bp.z
				var d6 := float(bp.y) - sqrt(float(dx * dx + dz * dz)) * 0.381
				var j2 := i1 if d6 > float(i1) else int(d6)
				if _fancy_limb(f, c, cf, Vector3i(p.x, j2, p.z), bp, false):
					coords.append([bp, j2])
		j1 -= 1
	_fancy_limb(f, c, cf, p, p + Vector3i(0, tk, 0), true)
	for fc in coords:
		var by: int = fc[1]
		var base := Vector3i(p.x, by, p.z)
		if base != fc[0] and float(by - p.y) >= float(jh) * 0.2:
			_fancy_limb(f, c, cf, base, fc[0], true)
	for fc2 in coords:
		if float(int(fc2[1]) - p.y) >= float(jh) * 0.2:
			atts.append([fc2[0], 0, false])


## Java FancyTrunkPlacer.treeShape (float arithmetic).
static func _fancy_shape(height: int, y: int) -> float:
	if float(y) < _f32(float(height) * _f32(0.3)):
		return -1.0
	var hf := _f32(float(height) / 2.0)
	var f1 := _f32(hf - float(y))
	if f1 == 0.0:
		return _f32(hf * 0.5)
	if absf(f1) >= hf:
		return 0.0
	var f2 := _f32(sqrt(_f32(_f32(hf * hf) - _f32(f1 * f1))))
	return _f32(f2 * 0.5)


## Java FancyTrunkPlacer.makeLimb: the cells from a to b (float steps, floor(0.5 + j * step)); place -> logs with the
## limb's axis, else -> true when every cell is free (air / replaceable / log).
static func _fancy_limb(f: Features, c: Features.FCtx, cf: Dictionary, a: Vector3i, b: Vector3i, place: bool) -> bool:
	if not place and a == b:
		return true
	var d := b - a
	var steps := maxi(absi(d.x), maxi(absi(d.y), absi(d.z)))
	if steps == 0:
		_log(f, c, cf, a, "y")
		return true
	var fx := _f32(float(d.x) / float(steps))
	var fy := _f32(float(d.y) / float(steps))
	var fz := _f32(float(d.z) / float(steps))
	for j in steps + 1:
		var q := a + Vector3i(int(floor(_f32(0.5 + _f32(float(j) * fx)))), int(floor(_f32(0.5 + _f32(float(j) * fy)))), int(floor(_f32(0.5 + _f32(float(j) * fz)))))
		if place:
			var ix := absi(q.x - a.x)
			var iz := absi(q.z - a.z)
			var km := maxi(ix, iz)
			_log(f, c, cf, q, "y" if km == 0 else ("x" if ix == km else "z"))
		elif not _valid(f, c, q):
			var st := f.get_block(c, q)
			if st <= 0 or not f.blocks.name_of(st).ends_with("_log"):
				return false
	return true


## Java Mth.sin / Mth.cos: the 65536-entry float sine table.
static func _mth_sin(v: float) -> float:
	return _f32(sin(float(int(v * 10430.378350470453) & 65535) * TAU / 65536.0))


static func _mth_cos(v: float) -> float:
	return _f32(sin(float(int(v * 10430.378350470453 + 16384.0) & 65535) * TAU / 65536.0))


static func _f32(v: float) -> float:
	return PackedFloat32Array([v])[0]


static func _air(f: Features, c: Features.FCtx, q: Vector3i) -> bool:
	return f.get_block(c, q) == 0


## Java TrunkVine / LeaveVine addHangingVine: vine on the face toward the support, extended down up to 4 blocks.
static func _hanging_vine(f: Features, c: Features.FCtx, q: Vector3i, face: String, extend: bool) -> void:
	var vine: int = f.blocks.default_state("vine")
	if vine < 0:
		return
	var st := f.blocks.with_prop(vine, face, "true")
	f.set_block(c, q, st, 2)
	if not extend:
		return
	var k := 4
	var d := q + Vector3i(0, -1, 0)
	while k > 0 and _air(f, c, d):
		f.set_block(c, d, st, 2)
		d += Vector3i(0, -1, 0)
		k -= 1


static func _by_y(a: Vector3i, b: Vector3i) -> bool:
	return a.y < b.y


## Java TreeDecorator implementations (26.3 types): trunk_vine, leave_vine, cocoa, beehive, alter_ground,
## attached_to_leaves, creaking_heart, pale_moss, place_on_ground, shelf_mushroom (APPROXIMATE: block on trunk sides).
static func _decorators(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i, h: int) -> void:
	var logs: Array = c.tree_logs.duplicate()
	var leaves: Array = c.tree_leaves.duplicate()
	logs.sort_custom(_by_y)
	leaves.sort_custom(_by_y)
	var hd := [[Vector3i(-1, 0, 0), "east"], [Vector3i(1, 0, 0), "west"], [Vector3i(0, 0, -1), "south"], [Vector3i(0, 0, 1), "north"]]
	for d in cf["decorators"]:
		if not (d is Dictionary):
			continue
		var t := str(d.get("type", "")).trim_prefix("minecraft:")
		var prob := float(d.get("probability", 1.0))
		match t:
			"trunk_vine":
				for q in logs:
					for dv in hd:
						if c.r.next_int_bound(3) > 0:
							continue
						var n: Vector3i = q + dv[0]
						if _air(f, c, n):
							_hanging_vine(f, c, n, dv[1], false)
			"leave_vine":
				for q in leaves:
					for dv in hd:
						if c.r.next_float() < prob:
							var n2: Vector3i = q + dv[0]
							if _air(f, c, n2):
								_hanging_vine(f, c, n2, dv[1], true)
			"cocoa":
				if c.r.next_float() >= prob or logs.is_empty():
					continue
				var y0: int = logs[0].y
				var cocoa: int = f.blocks.default_state("cocoa")
				for q in logs:
					if q.y - y0 > 2:
						continue
					for dv in hd:
						if c.r.next_float() <= 0.25:
							# the pod sits next to the log and faces it
							var n3: Vector3i = q + dv[0]
							if cocoa > 0 and _air(f, c, n3):
								var cs := f.blocks.with_prop(cocoa, "age", str(c.r.next_int_bound(3)))
								cs = f.blocks.with_prop(cs, "facing", dv[1])   # Java: pod at pos + opposite(dir), facing dir (toward the log)
								f.set_block(c, n3, cs, 2)
			"beehive":
				if c.r.next_float() >= prob or logs.is_empty():
					continue
				var hy: int = maxi(leaves[0].y - 1, logs[0].y + 1) if not leaves.is_empty() else mini(logs[0].y + 1 + c.r.next_int_bound(3), logs[logs.size() - 1].y)
				var cands: Array = []
				for q in logs:
					if q.y == hy:
						for dv2 in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1)]:
							cands.append(q + dv2)
				for i in range(cands.size() - 1, 0, -1):
					var j := c.r.next_int_bound(i + 1)
					var tmp = cands[i]
					cands[i] = cands[j]
					cands[j] = tmp
				var nest: int = f.blocks.default_state("bee_nest")
				for q2 in cands:
					if nest > 0 and _air(f, c, q2) and _air(f, c, q2 + Vector3i(0, 0, 1)):
						f.set_block(c, q2, f.blocks.with_prop(nest, "facing", "south"), 2)
						break
			"alter_ground":
				if logs.is_empty() or not d.has("_prov"):
					continue
				var ly: int = logs[0].y
				for q in logs:
					if q.y != ly:
						continue
					for off in [Vector3i(-1, 0, -1), Vector3i(2, 0, -1), Vector3i(-1, 0, 2), Vector3i(2, 0, 2)]:
						_alter_circle(f, c, d, q + off)
					for k in 5:
						var r := c.r.next_int_bound(64)
						var lx := r % 8
						var lz := r / 8
						if lx == 0 or lx == 7 or lz == 0 or lz == 7:
							_alter_circle(f, c, d, q + Vector3i(-3 + lx, 0, -3 + lz))
			"attached_to_leaves":
				if not d.has("_prov"):
					continue
				var dirs: Array = d.get("directions", ["down"])
				var need := int(d.get("required_empty_blocks", 1))
				var exz := int(d.get("exclusion_radius_xz", 0))
				var exy := int(d.get("exclusion_radius_y", 0))
				var excluded := {}
				var sh := leaves.duplicate()
				for i in range(sh.size() - 1, 0, -1):
					var j2 := c.r.next_int_bound(i + 1)
					var tmp2 = sh[i]
					sh[i] = sh[j2]
					sh[j2] = tmp2
				var dv3 := {"down": Vector3i(0, -1, 0), "up": Vector3i(0, 1, 0), "north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0)}
				for q in sh:
					var dir: Vector3i = dv3.get(str(dirs[c.r.next_int_bound(dirs.size())]).trim_prefix("minecraft:"), Vector3i(0, -1, 0))
					var tgt: Vector3i = q + dir
					if excluded.has(tgt) or c.r.next_float() >= prob:
						continue
					var ok := true
					for k2 in range(1, need + 1):
						if not _air(f, c, q + dir * k2):
							ok = false
							break
					if not ok:
						continue
					for ex in range(-exz, exz + 1):
						for ey in range(-exy, exy + 1):
							for ez in range(-exz, exz + 1):
								excluded[tgt + Vector3i(ex, ey, ez)] = true
					f.set_block(c, tgt, f.provide(c, d["_prov"], tgt), 2)
			"creaking_heart":
				if c.r.next_float() >= prob or logs.is_empty():
					continue
				var heart: int = f.blocks.default_state("creaking_heart")
				if heart < 0:
					continue
				var sh2 := logs.duplicate()
				for i in range(sh2.size() - 1, 0, -1):
					var j3 := c.r.next_int_bound(i + 1)
					var tmp3 = sh2[i]
					sh2[i] = sh2[j3]
					sh2[j3] = tmp3
				for q in sh2:
					var all_logs := true
					for n6 in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
						var ns: int = f.get_block(c, q + n6)
						if ns <= 0 or not f.blocks.name_of(ns).ends_with("_log"):
							all_logs = false
							break
					if all_logs:
						var hs := heart
						if f.blocks.has_prop(hs, "creaking_heart_state"):
							hs = f.blocks.with_prop(hs, "creaking_heart_state", "dormant")
						if f.blocks.has_prop(hs, "natural"):
							hs = f.blocks.with_prop(hs, "natural", "true")
						f.set_block(c, q, hs, 0)
						break
			"pale_moss":
				if logs.is_empty():
					continue
				if c.r.next_float() < float(d.get("ground_probability", 0.0)) and d.has("_patch"):
					f.place_feature(c, d["_patch"], logs[0] + Vector3i(0, 1, 0))
				var tp := float(d.get("trunk_probability", 0.0))
				var lp := float(d.get("leaves_probability", 0.0))
				for q in logs:
					if c.r.next_float() < tp and _air(f, c, q + Vector3i(0, -1, 0)):
						_moss_hanger(f, c, q + Vector3i(0, -1, 0))
				for q in leaves:
					if c.r.next_float() < lp and _air(f, c, q + Vector3i(0, -1, 0)):
						_moss_hanger(f, c, q + Vector3i(0, -1, 0))
			"place_on_ground":
				if logs.is_empty() or not d.has("_prov"):
					continue
				var oy: int = logs[0].y
				var mn := Vector3i(logs[0].x, oy, logs[0].z)
				var mx := mn
				for q in logs:
					if q.y == oy:
						mn = Vector3i(mini(mn.x, q.x), oy, mini(mn.z, q.z))
						mx = Vector3i(maxi(mx.x, q.x), oy, maxi(mx.z, q.z))
				var rad := int(d.get("radius", 2))
				var hgt := int(d.get("height", 1))
				for k3 in int(d.get("tries", 128)):
					var q3 := Vector3i(c.r.next_int_bound(mx.x - mn.x + 2 * rad + 1) + mn.x - rad, c.r.next_int_bound(2 * hgt + 1) + oy - hgt, c.r.next_int_bound(mx.z - mn.z + 2 * rad + 1) + mn.z - rad)
					var above := q3 + Vector3i(0, 1, 0)
					var as_: int = f.get_block(c, above)
					var bs: int = f.get_block(c, q3)
					# Java PlaceOnGroundDecorator: air / vine above, solid-render ground (full opaque cube), and
					# MOTION_BLOCKING_NO_LEAVES <= y + 1 (no collidable / fluid non-leaf block above; scanned 64)
					var fl3: int = f.blocks.st_flags[bs] if bs > 0 else 0
					if (as_ == 0 or (as_ > 0 and f.blocks.name_of(as_) == "vine")) and bs > 0 and (fl3 & BlockRegistry.F_OPAQUE) != 0 and (fl3 & BlockRegistry.F_FULL_SHAPE) != 0:
						var covered := false
						for yy in range(q3.y + 2, mini(q3.y + 65, Coords.MAX_Y)):
							var s4: int = f.get_block(c, Vector3i(q3.x, yy, q3.z))
							if s4 > 0:
								var f4: int = f.blocks.st_flags[s4]
								if (f4 & BlockRegistry.F_LEAVES) == 0 and (f4 & (BlockRegistry.F_COLLIDE | BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0:
									covered = true
									break
						if not covered:
							f.set_block(c, above, f.provide(c, d["_prov"], above), 2)
			"shelf_mushroom":
				var shelf: int = f.blocks.default_state("shelf_mushroom")
				if shelf < 0 or logs.size() < 3 or c.r.next_float() >= prob:
					continue
				for k4 in 1 + c.r.next_int_bound(3):
					var q4: Vector3i = logs[1 + c.r.next_int_bound(logs.size() - 1)]
					var dv4: Array = hd[c.r.next_int_bound(4)]
					var n4: Vector3i = q4 + dv4[0]
					if _air(f, c, n4):
						var ss := shelf
						if f.blocks.has_prop(ss, "facing"):
							ss = f.blocks.with_prop(ss, "facing", {"east": "west", "west": "east", "south": "north", "north": "south"}[dv4[1]])
						f.set_block(c, n4, ss, 2)


## Java AlterGroundDecorator.placeCircle / placeBlockAt.
static func _alter_circle(f: Features, c: Features.FCtx, d: Dictionary, q: Vector3i) -> void:
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if absi(dx) == 2 and absi(dz) == 2:
				continue
			var base := q + Vector3i(dx, 0, dz)
			for dy in range(2, -4, -1):
				var pp := base + Vector3i(0, dy, 0)
				var st: int = f.get_block(c, pp)
				if st > 0 and f._is_dirt(st):
					f.set_block(c, pp, f.provide(c, d["_prov"], base), 2)
					break
				if st != 0 and dy < 0:
					break


## Java PaleMossDecorator.addMossHanger.
static func _moss_hanger(f: Features, c: Features.FCtx, q: Vector3i) -> void:
	var moss: int = f.blocks.default_state("pale_hanging_moss")
	if moss < 0:
		return
	var pos := q
	while _air(f, c, pos + Vector3i(0, -1, 0)) and not (c.r.next_float() < 0.5):
		f.set_block(c, pos, f.blocks.with_prop(moss, "tip", "false") if f.blocks.has_prop(moss, "tip") else moss, 2)
		pos += Vector3i(0, -1, 0)
	f.set_block(c, pos, f.blocks.with_prop(moss, "tip", "true") if f.blocks.has_prop(moss, "tip") else moss, 2)

static func fallen(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var below: int = f.get_block(c, p + Vector3i(0, -1, 0))
	if below <= 0 or (f.blocks.st_flags[below] & BlockRegistry.F_FULL_SHAPE) == 0 or f.get_block(c, p) != 0:
		return false
	_log(f, c, cf, p)
	var length := f.sample_int(c, cf["len"])
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	var d: Vector3i = dirs[c.r.next_int_bound(4)]
	var start := p + d * (2 + c.r.next_int_bound(2))
	for k in length:
		var q := start + d * k
		var bl: int = f.get_block(c, q + Vector3i(0, -1, 0))
		if f.get_block(c, q) != 0 or bl <= 0 or (f.blocks.st_flags[bl] & BlockRegistry.F_COLLIDE) == 0:
			break
		_log(f, c, cf, q, "x" if d.x != 0 else "z")
	return true


## Java HugeRedMushroomFeature / HugeBrownMushroomFeature (AbstractHugeMushroomFeature.place):
## height 4 + r(3), doubled 1 in 12; isValidPosition: dirt or #mushroom_grow_block below, the stem column (red) /
## the cap layers above y 3 (brown) free of everything but air and leaves (Java passes treeHeight -1 to
## getTreeRadiusForHeight there); stem and cap replace anything not solid-render. Red cap: three side rings (radius,
## no corners) and a radius - 1 top (full); brown cap: one radius layer without corners. Cap faces as Java sets them.
static func mushroom(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i, red: bool) -> bool:
	var h := 4 + c.r.next_int_bound(3)
	if c.r.next_int_bound(12) == 0:
		h *= 2
	var r: int = cf["radius"]
	if p.y < Coords.MIN_Y + 1 or p.y + h + 1 >= Coords.MAX_Y:
		return false
	var below: int = f.get_block(c, p + Vector3i(0, -1, 0))
	if below <= 0:
		return false
	var bn := f.blocks.name_of(below)
	if not (f._tag_blocks("dirt").has(bn) or f._tag_blocks("mushroom_grow_block").has(bn)):
		return false
	for j in h + 1:
		var k := 0 if red else (0 if j <= 3 else r)
		for l in range(-k, k + 1):
			for i1 in range(-k, k + 1):
				var st: int = f.get_block(c, p + Vector3i(l, j, i1))
				if st != 0 and (st < 0 or (f.blocks.st_flags[st] & BlockRegistry.F_LEAVES) == 0):
					return false
	for y in h:
		var q0 := p + Vector3i(0, y, 0)
		if not _solid_render(f, c, q0):
			f.set_block(c, q0, f.provide(c, cf["stem"], p), 0)
	if red:
		var kk := r - 2
		for y in range(h - 3, h + 1):
			var j2 := r if y < h else r - 1
			for l2 in range(-j2, j2 + 1):
				for i2 in range(-j2, j2 + 1):
					var e4 := l2 == -j2 or l2 == j2
					var e5 := i2 == -j2 or i2 == j2
					if y >= h or e4 != e5:
						var q := p + Vector3i(l2, y, i2)
						if not _solid_render(f, c, q):
							var cs: int = f.provide(c, cf["cap"], p)
							if f.blocks.has_prop(cs, "west"):
								cs = _faces(f.blocks, cs, {"up": y >= h - 1, "west": l2 < -kk, "east": l2 > kk, "north": i2 < -kk, "south": i2 > kk})
							f.set_block(c, q, cs, 0)
	else:
		for l3 in range(-r, r + 1):
			for i3 in range(-r, r + 1):
				var f0 := l3 == -r
				var f1 := l3 == r
				var f2 := i3 == -r
				var f3 := i3 == r
				var f4 := f0 or f1
				var f5 := f2 or f3
				if not f4 or not f5:
					var q2 := p + Vector3i(l3, h, i3)
					if not _solid_render(f, c, q2):
						var cs2: int = f.provide(c, cf["cap"], p)
						if f.blocks.has_prop(cs2, "west"):
							cs2 = _faces(f.blocks, cs2, {"west": f0 or (f5 and l3 == 1 - r), "east": f1 or (f5 and l3 == r - 1),
								"north": f2 or (f4 and i3 == 1 - r), "south": f3 or (f4 and i3 == r - 1)})
						f.set_block(c, q2, cs2, 0)
	return true


static func _faces(b: BlockRegistry, st: int, faces: Dictionary) -> int:
	for k in faces:
		st = b.with_prop(st, k, "true" if faces[k] else "false")
	return st


## Java BlockState.isSolidRender (approximation: an opaque full cube).
static func _solid_render(f: Features, c: Features.FCtx, q: Vector3i) -> bool:
	var st: int = f.get_block(c, q)
	return st < 0 or (st > 0 and (f.blocks.st_flags[st] & BlockRegistry.F_OPAQUE) != 0)

# ---------------------------------------------------------------- cherry (Java CherryTrunkPlacer / CherryFoliagePlacer)

const _HORIZ := [Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)]   # N E S W (Direction.Plane.HORIZONTAL)


static func _uni(c: Features.FCtx, v, lo_def: int, hi_def: int) -> int:
	var lo := int(v.get("min_inclusive", lo_def)) if v is Dictionary else lo_def
	var hi := int(v.get("max_inclusive", hi_def)) if v is Dictionary else hi_def
	return lo + c.r.next_int_bound(hi - lo + 1) if hi >= lo else lo


static func _cherry_trunk(f: Features, c: Features.FCtx, cf: Dictionary, tp: Dictionary, p: Vector3i, h: int, atts: Array) -> void:
	var bso = tp.get("branch_start_offset_from_top", {"min_inclusive": -4, "max_inclusive": -3})
	var i := maxi(0, h - 1 + _uni(c, bso, -4, -3))
	# secondBranchStartOffsetFromTop = UniformInt(min, max - 1)
	var j := maxi(0, h - 1 + _uni(c, {"min_inclusive": int(bso.get("min_inclusive", -4)), "max_inclusive": int(bso.get("max_inclusive", -3)) - 1}, -4, -4))
	if j >= i:
		j += 1
	var k := f.sample_int(c, tp.get("branch_count", 1))
	var three := k == 3
	var two := k >= 2
	var l := h if three else (maxi(i, j) + 1 if two else i + 1)
	for m in l:
		_log(f, c, cf, p + Vector3i(0, m, 0))
	if three:
		atts.append([p + Vector3i(0, l, 0), 0, false])
	var di := c.r.next_int_bound(4)
	atts.append(_cherry_branch(f, c, cf, tp, p, h, _HORIZ[di], i, i < l - 1))
	if two:
		atts.append(_cherry_branch(f, c, cf, tp, p, h, _HORIZ[(di + 2) % 4], j, j < l - 1))


static func _cherry_branch(f: Features, c: Features.FCtx, cf: Dictionary, tp: Dictionary, p: Vector3i, h: int, dir: Vector3i, start: int, below: bool) -> Array:
	var m := p + Vector3i(0, start, 0)
	var i := h - 1 + f.sample_int(c, tp.get("branch_end_offset_from_top", {"type": "uniform", "min_inclusive": -1, "max_inclusive": 0}))
	var bl := below or i < start
	var j := f.sample_int(c, tp.get("branch_horizontal_length", {"type": "uniform", "min_inclusive": 2, "max_inclusive": 4})) + (1 if bl else 0)
	var target := p + dir * j + Vector3i(0, i, 0)
	var axis := "x" if dir.x != 0 else "z"
	for q in (2 if bl else 1):
		m += dir
		_log(f, c, cf, m, axis)
	var vdir := Vector3i(0, 1, 0) if target.y > m.y else Vector3i(0, -1, 0)
	while true:
		var md: int = absi(target.x - m.x) + absi(target.y - m.y) + absi(target.z - m.z)
		if md == 0:
			return [target + Vector3i(0, 1, 0), 0, false]
		var fr := float(absi(target.y - m.y)) / float(md)
		var vert := c.r.next_float() < fr
		m += vdir if vert else dir
		_log(f, c, cf, m, "y" if vert else axis)
	return [target + Vector3i(0, 1, 0), 0, false]


## Java CherryFoliagePlacer.createFoliage (pos = attachment + offset, i = radius + radiusOffset - 1).
static func _cherry_foliage(f: Features, c: Features.FCtx, cf: Dictionary, fp: Dictionary, pos: Vector3i, i: int, fh: int, dbl: bool) -> void:
	_cherry_row(f, c, cf, fp, pos, i - 2, fh - 3, dbl)
	_cherry_row(f, c, cf, fp, pos, i - 1, fh - 4, dbl)
	for j in range(fh - 5, -1, -1):
		_cherry_row(f, c, cf, fp, pos, i, j, dbl)
	var hc := float(fp.get("hanging_leaves_chance", 0.16666667))
	var he := float(fp.get("hanging_leaves_extension_chance", 0.33333334))
	_cherry_row(f, c, cf, fp, pos, i, -1, dbl)
	_hanging_below(f, c, cf, pos, i, -1, dbl, hc, he)
	_cherry_row(f, c, cf, fp, pos, i - 1, -2, dbl)
	_hanging_below(f, c, cf, pos, i - 1, -2, dbl, hc, he)


static func _cherry_row(f: Features, c: Features.FCtx, cf: Dictionary, fp: Dictionary, pos: Vector3i, rng: int, ly: int, dbl: bool) -> void:
	var e := 1 if dbl else 0
	var wide := float(fp.get("wide_bottom_layer_hole_chance", 0.25))
	var corner := float(fp.get("corner_hole_chance", 0.25))
	for j in range(-rng, rng + e + 1):
		for k in range(-rng, rng + e + 1):
			var ax := mini(absi(j), absi(j - 1)) if dbl else absi(j)
			var az := mini(absi(k), absi(k - 1)) if dbl else absi(k)
			# CherryFoliagePlacer.shouldSkipLocation
			var skip := false
			if ly == -1 and (ax == rng or az == rng) and c.r.next_float() < wide:
				skip = true
			else:
				var cornerp := ax == rng and az == rng
				if rng > 2:
					skip = cornerp or (ax + az > rng * 2 - 2 and c.r.next_float() < corner)
				else:
					skip = cornerp and c.r.next_float() < corner
			if not skip:
				_leaf(f, c, cf, pos + Vector3i(j, ly, k))


## FoliagePlacer.placeLeavesRowWithHangingLeavesBelow (after the row itself): hanging leaves under placed edge leaves.
static func _hanging_below(f: Features, c: Features.FCtx, cf: Dictionary, pos: Vector3i, rng: int, ly: int, dbl: bool, chance: float, ext: float) -> void:
	var e := 1 if dbl else 0
	var logp := pos + Vector3i(0, -1, 0)
	for di in 4:
		var dir: Vector3i = _HORIZ[di]
		var d2: Vector3i = _HORIZ[(di + 1) % 4]   # getClockWise
		var j := rng + e if (d2.x > 0 or d2.z > 0) else rng
		var m := pos + Vector3i(0, ly - 1, 0) + d2 * j - dir * rng
		var k := -rng
		while k < rng + e:
			if c.tree_leaf_set.has(m + Vector3i(0, 1, 0)) and _try_ext(f, c, cf, chance, logp, m):
				_try_ext(f, c, cf, ext, logp, m + Vector3i(0, -1, 0))
			k += 1
			m += dir


static func _try_ext(f: Features, c: Features.FCtx, cf: Dictionary, chance: float, logp: Vector3i, q: Vector3i) -> bool:
	if absi(q.x - logp.x) + absi(q.y - logp.y) + absi(q.z - logp.z) >= 7:
		return false
	if c.r.next_float() > chance:
		return false
	return _leaf(f, c, cf, q)


# ---------------------------------------------------------------- poplar (26.x; the placer code is not public)
# Shape matched to vanilla 26.3 dappled forests (reference screenshots 2026-11-13) with the 26.3 parameters: a dense,
# rounded dome crown - circular layers on an ellipse profile centred 60 % down (domed top, rounded underside, about
# twice as wide as tall), `height` 5-6 layers from one block above the top log, `radius` 5-8 - and branch_amount (1-4)
# branches rising diagonally from trunk_height_above_branches below the top, each under a small crown lobe (radius - 2,
# one layer lower): the bumps and two-lobed crowns seen from above. side_hole_chance opens holes only in layer rims.

static func _poplar_trunk(f: Features, c: Features.FCtx, cf: Dictionary, tp: Dictionary, p: Vector3i, h: int, atts: Array) -> void:
	for y in h:
		_log(f, c, cf, p + Vector3i(0, y, 0))
	atts.append([p + Vector3i(0, h, 0), 0, false])
	var above := int(tp.get("trunk_height_above_branches", 4))
	var by := clampi(h - above, 2, h - 1)
	var n := f.sample_int(c, tp.get("branch_amount", 1))
	var used := {}
	for b in n:
		var dir: Vector3i = _POPLAR_DIRS[c.r.next_int_bound(8)]
		var ln := 2 + c.r.next_int_bound(2)
		if used.has(dir):
			continue
		used[dir] = true
		var axis := "x" if absi(dir.x) >= absi(dir.z) else "z"
		var q := p + Vector3i(0, by, 0)
		for k in ln:
			q += dir
			if k > 0:
				q.y += 1
			if q.y - p.y >= h:
				break
			_log(f, c, cf, q, axis)
		atts.append([Vector3i(q.x, p.y + h - 1, q.z), -2, false])


const _POPLAR_DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1)]


static func _poplar_foliage(f: Features, c: Features.FCtx, cf: Dictionary, fp: Dictionary, top: Vector3i, radius: int, layers: int, _dbl: bool) -> void:
	var hole := float(fp.get("side_hole_chance", 0.15))
	layers = maxi(layers, 3)
	# ellipse centred 60 % down the crown: a domed top and a shorter rounded underside (vanilla's mushroom-cap look)
	var cy := float(layers - 1) * 0.6
	var at := cy + 0.75
	var ab := float(layers - 1) - cy + 0.75
	for i in layers:
		var d := (cy - float(i)) / at if float(i) <= cy else (float(i) - cy) / ab
		var rr := maxf(1.0, float(radius) * sqrt(maxf(0.0, 1.0 - d * d)))
		var lim := rr * rr + rr * 0.6        # rounded circle: no lone corner blocks
		var ir := rr - 1.0
		var inner := ir * ir + ir * 0.6      # inside this the layer is solid; between it and lim is the rim
		var ri := int(ceil(rr))
		for dx in range(-ri, ri + 1):
			for dz in range(-ri, ri + 1):
				var d2 := float(dx * dx + dz * dz)
				if d2 > lim:
					continue
				if d2 > inner and c.r.next_float() < hole:
					continue   # dappled rim
				_leaf(f, c, cf, top + Vector3i(dx, -i, dz))