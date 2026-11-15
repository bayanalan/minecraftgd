## Portals — Nether portal frames (Java PortalShape: obsidian frame, interior 2..21 wide x 3..21 tall), lighting,
## breaking, linking (portal index per dimension in level.json, like Java's POI portal search: 16 blocks in the
## Nether, 128 in the Overworld) and creation at the destination (Java PortalForcer.createPortal incl. the
## forced obsidian platform); End portal frames (12 eyes -> 3x3 end_portal), End spawn platform.
## Contract: static helpers taking the WorldManager; all block access through world.state_at/set_block.
class_name Portals
extends RefCounted

const MAX_SIZE := 21


static func _name(st: int) -> String:
	return Res.blocks.name_of(st) if st > 0 else "air"


static func _is_frame(world, p: Vector3i) -> bool:
	return _name(world.state_at(p.x, p.y, p.z)) == "obsidian"


static func _is_empty(world, p: Vector3i) -> bool:
	var n := _name(world.state_at(p.x, p.y, p.z))
	return n == "air" or n == "cave_air" or n == "fire" or n == "soul_fire" or n == "nether_portal"


## Java PortalShape for the given axis ("x" = portal spans x). Returns {} or {bottom_left, width, height, axis}.
static func shape(world, pos: Vector3i, axis: String) -> Dictionary:
	var right := Vector3i(1, 0, 0) if axis == "x" else Vector3i(0, 0, 1)
	var left := -right
	# lowest empty cell in the column
	var p := pos
	var guard := 0
	while p.y > Coords.MIN_Y and _is_empty(world, p + Vector3i(0, -1, 0)) and guard < MAX_SIZE:
		p.y -= 1
		guard += 1
	# walk left to the frame
	var d := 0
	while d <= MAX_SIZE:
		var q := p + left * d
		if not _is_empty(world, q) or not _is_frame(world, q + Vector3i(0, -1, 0)):
			break
		d += 1
	if not _is_frame(world, p + left * d):
		return {}
	var bl := p + left * (d - 1)
	# width
	var w := 0
	while w <= MAX_SIZE:
		var q2 := bl + right * w
		if not _is_empty(world, q2) or not _is_frame(world, q2 + Vector3i(0, -1, 0)):
			break
		w += 1
	if w < 2 or w > MAX_SIZE or not _is_frame(world, bl + right * w):
		return {}
	# height
	var h := 0
	var ok := true
	while h < MAX_SIZE and ok:
		for i in w:
			var q3 := bl + right * i + Vector3i(0, h, 0)
			if not _is_empty(world, q3):
				ok = false
				break
		if not ok:
			break
		if not _is_frame(world, bl + left + Vector3i(0, h, 0)) or not _is_frame(world, bl + right * w + Vector3i(0, h, 0)):
			break
		h += 1
	if h < 3:
		return {}
	for i in w:
		if not _is_frame(world, bl + right * i + Vector3i(0, h, 0)):
			return {}
	return {"bl": bl, "w": w, "h": h, "axis": axis}


## Flint & steel / fire inside an obsidian frame: fill with nether_portal. Returns true when lit.
static func try_light(world, pos: Vector3i) -> bool:
	if world.dimension == "the_end":
		return false
	for axis in ["x", "z"]:
		var s := shape(world, pos, axis)
		if not s.is_empty():
			fill(world, s)
			register(world, world.dimension, s["bl"], axis)
			return true
	return false


static func fill(world, s: Dictionary) -> void:
	var right := Vector3i(1, 0, 0) if s["axis"] == "x" else Vector3i(0, 0, 1)
	var st := Res.blocks.state_of("nether_portal", {"axis": s["axis"]})
	if st < 0:
		st = Res.blocks.default_state("nether_portal")
	for h in int(s["h"]):
		for i in int(s["w"]):
			var q: Vector3i = s["bl"] + right * i + Vector3i(0, h, 0)
			world.set_block(q.x, q.y, q.z, st)


## Called when a block changes next to portal blocks: Java breaks the whole portal when its frame is invalid.
static func on_block_changed(world, p: Vector3i, old_st: int, new_st: int) -> void:
	var old_n := _name(old_st)
	if old_n != "obsidian" and old_n != "nether_portal":
		return
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var q: Vector3i = p + d
		var st: int = world.state_at(q.x, q.y, q.z)
		if _name(st) == "nether_portal":
			var axis := Res.blocks.get_prop(st, "axis")
			if axis == "":
				axis = "x"
			if shape(world, q, axis).is_empty():
				_remove_connected(world, q)


static func _remove_connected(world, start: Vector3i) -> void:
	var stack: Array = [start]
	var seen := {}
	var n := 0
	while not stack.is_empty() and n < 2000:
		var q: Vector3i = stack.pop_back()
		if seen.has(q):
			continue
		seen[q] = true
		if _name(world.state_at(q.x, q.y, q.z)) != "nether_portal":
			continue
		world.set_block(q.x, q.y, q.z, 0)
		n += 1
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			stack.append(q + d)
	_unregister_near(world, world.dimension, start)


# ------------------------------------------------------------------ portal index (POI equivalent)

static func register(world, dim: String, bl: Vector3i, axis: String) -> void:
	var idx: Dictionary = world.level.get("portals", {})
	var lst: Array = idx.get(dim, [])
	for e in lst:
		if Vector3i(int(e[0]), int(e[1]), int(e[2])).distance_squared_to(bl) < 4:
			return
	lst.append([bl.x, bl.y, bl.z, axis])
	idx[dim] = lst
	world.level["portals"] = idx


static func _unregister_near(world, dim: String, p: Vector3i) -> void:
	var idx: Dictionary = world.level.get("portals", {})
	var lst: Array = idx.get(dim, [])
	var keep: Array = []
	for e in lst:
		if Vector3i(int(e[0]), int(e[1]), int(e[2])).distance_squared_to(p) > 22 * 22:
			keep.append(e)
	idx[dim] = keep
	world.level["portals"] = idx


## Nearest registered portal within the Java search radius (Chebyshev, horizontal).
static func find_registered(world, dim: String, target: Vector3i) -> Array:
	var radius := 16 if dim == "the_nether" else 128
	var best: Array = []
	var bd := 1 << 60
	var idx: Dictionary = world.level.get("portals", {})
	for e in idx.get(dim, []):
		var p := Vector3i(int(e[0]), int(e[1]), int(e[2]))
		if maxi(absi(p.x - target.x), absi(p.z - target.z)) > radius:
			continue
		var d := p.distance_squared_to(target)
		if d < bd:
			bd = d
			best = e
	return best


## Destination point when entering a nether portal (coordinate scale 8, Java clamp to world border).
static func scaled_target(from_dim: String, to_dim: String, p: Vector3) -> Vector3:
	var s := 1.0
	if from_dim == "overworld" and to_dim == "the_nether":
		s = 1.0 / 8.0
	elif from_dim == "the_nether" and to_dim == "overworld":
		s = 8.0
	return Vector3(clampf(floorf(p.x * s), -29999984.0, 29999984.0), p.y, clampf(floorf(p.z * s), -29999984.0, 29999984.0))


## After arriving: link to an existing portal or build one (PortalForcer.createPortal). Returns the player position.
static func arrive_nether_portal(world, target: Vector3i, axis: String) -> Vector3:
	var dim: String = world.dimension
	var e := find_registered(world, dim, target)
	if not e.is_empty():
		var bl := Vector3i(int(e[0]), int(e[1]), int(e[2]))
		if _name(world.state_at(bl.x, bl.y, bl.z)) == "nether_portal":
			var right := Vector3i(1, 0, 0) if str(e[3]) == "x" else Vector3i(0, 0, 1)
			return Vector3(bl) + Vector3(right) * 0.5 + Vector3(0.5, 0.0, 0.5)
	var gmin: int = world.gen.gen_min_y
	var gdepth: int = world.gen.gen_depth
	var top: int = gmin + (128 if dim == "the_nether" else gdepth) - 1
	var bottom: int = gmin
	var right2 := Vector3i(1, 0, 0) if axis == "x" else Vector3i(0, 0, 1)
	var fwd := Vector3i(0, 0, 1) if axis == "x" else Vector3i(1, 0, 0)
	# wiki Nether portal: the closest spot (3D) within 16 blocks horizontally, any height, with a 3 x 4 area of buildable
	# blocks (4 along the portal's axis, 3 across) and 4 air blocks above all 12; else a 1 x 4 strip the same way
	var cols := {}
	var best := _find_spot(world, target, right2, fwd, bottom, top, 1, cols)
	if best.y == -99999:
		best = _find_spot(world, target, right2, fwd, bottom, top, 0, cols)
	var forced := best.y == -99999
	if forced:
		# wiki: Nether_portal - y clamped between 70 and 10 below the world height (118 Nether, 310 Overworld)
		best = Vector3i(target.x, clampi(target.y, 70, top + 1 - 10), target.z)
		# obsidian platform with air above (Java forced creation)
		for i in range(-1, 2):
			for j in range(0, 2):
				for k in range(-1, 3):
					var q := best + right2 * j + fwd * i + Vector3i(0, k, 0)
					world.set_block(q.x, q.y, q.z, Res.blocks.default_state("obsidian") if k < 0 else 0)
	var obs := Res.blocks.default_state("obsidian")
	for o in range(-1, 3):
		for p in range(-1, 4):
			if o == -1 or o == 2 or p == -1 or p == 3:
				var q2 := best + right2 * o + Vector3i(0, p, 0)
				world.set_block(q2.x, q2.y, q2.z, obs)
	var pst := Res.blocks.state_of("nether_portal", {"axis": axis})
	if pst < 0:
		pst = Res.blocks.default_state("nether_portal")
	for o in 2:
		for p in 3:
			var q3 := best + right2 * o + Vector3i(0, p, 0)
			world.set_block(q3.x, q3.y, q3.z, pst)
	register(world, dim, best, axis)
	return Vector3(best) + Vector3(right2) * 0.5 + Vector3(0.5, 0.0, 0.5)


## Closest origin (the frame's first inner column, floor level + 1) within 16 blocks of target whose footprint (4 along
## `right` from -1 .. 2, 2 x half + 1 across) has a buildable floor and 4 free blocks above every column; NONE-style
## y -99999 when there is none. cols caches the per-column candidate heights between the two passes.
static func _find_spot(world, target: Vector3i, right: Vector3i, fwd: Vector3i, bottom: int, top: int, half: int, cols: Dictionary) -> Vector3i:
	var lo := bottom + 1
	var hi := top - 3
	var best := Vector3i(0, -99999, 0)
	if hi < lo:
		return best
	var bd := 1 << 60
	for dz in range(-16, 17):
		for dx in range(-16, 17):
			var ox := target.x + dx
			var oz := target.z + dz
			var h2 := dx * dx + dz * dz
			if h2 >= bd:
				continue
			var first: Array = []
			var rest: Array = []
			for j in range(-1, 3):
				for s in range(-half, half + 1):
					var c: Array = _column(world, Vector2i(ox + right.x * j + fwd.x * s, oz + right.z * j + fwd.z * s), lo, hi, cols)
					if first.is_empty() and rest.is_empty():
						first = c
					rest.append(c)
			for y in first[1]:
				var dy: int = int(y) - target.y
				if h2 + dy * dy >= bd:
					continue
				var ok := true
				for c2 in rest:
					if (c2[0] as PackedByteArray)[int(y) - lo] == 0:
						ok = false
						break
				if ok:
					bd = h2 + dy * dy
					best = Vector3i(ox, int(y), oz)
	return best


## [PackedByteArray flags (y - lo), Array of heights] for the column: 1 where the block below is buildable (solid, not
## a fluid) and the 4 blocks from y up are free (air, or replaceable non-fluid blocks such as grass).
static func _column(world, c: Vector2i, lo: int, hi: int, cols: Dictionary) -> Array:
	var got = cols.get(c)
	if got != null:
		return got
	var b := Res.blocks
	var n := hi - lo + 1
	var flags := PackedByteArray()
	flags.resize(n)
	var ys: Array = []
	var ch: Chunk = world.cm.get_chunk(c.x >> 4, c.y >> 4) if world.get("cm") != null else null
	if ch != null and ch.state >= Chunk.DECORATED:
		var lx := c.x & 15
		var lz := c.y & 15
		var run := 0          # free blocks counted downward from the top
		var y := hi + 3
		while y >= lo - 1:
			var st := ch.get_block(lx, y, lz)
			var fl: int = b.st_flags[st] if st > 0 else 0
			var free := st == 0 or ((fl & BlockRegistry.F_REPLACEABLE) != 0 and (fl & BlockRegistry.F_LIQUID) == 0)
			var solid := st > 0 and (fl & BlockRegistry.F_COLLIDE) != 0 and (fl & BlockRegistry.F_LIQUID) == 0 and not free
			# y is the floor of the spot y + 1 when the 4 blocks above it are free
			if solid and run >= 4 and y + 1 <= hi:
				flags[y + 1 - lo] = 1
				ys.append(y + 1)
			run = run + 1 if free else 0
			y -= 1
	var out := [flags, ys]
	cols[c] = out
	return out


# ------------------------------------------------------------------ End portal

const FRAME_RING := [Vector3i(-1, 0, -2), Vector3i(0, 0, -2), Vector3i(1, 0, -2), Vector3i(-1, 0, 2), Vector3i(0, 0, 2), Vector3i(1, 0, 2),
	Vector3i(-2, 0, -1), Vector3i(-2, 0, 0), Vector3i(-2, 0, 1), Vector3i(2, 0, -1), Vector3i(2, 0, 0), Vector3i(2, 0, 1)]


## After an eye is inserted at `p`: if a complete 12-frame ring with eyes surrounds a 3x3 area, open the portal.
static func try_open_end_portal(world, p: Vector3i) -> bool:
	for cz in range(-2, 3):
		for cx in range(-2, 3):
			var c := p + Vector3i(cx, 0, cz)
			var all := true
			for o in FRAME_RING:
				var q: Vector3i = c + o
				var st: int = world.state_at(q.x, q.y, q.z)
				if _name(st) != "end_portal_frame" or Res.blocks.get_prop(st, "eye") != "true":
					all = false
					break
			if all:
				var portal := Res.blocks.default_state("end_portal")
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						world.set_block(c.x + dx, c.y, c.z + dz, portal)
				Audio.play("block.end_portal.spawn", Vector3(c), "Blocks")
				return true
	return false


## Java ServerLevel.makeObsidianPlatform / EndPlatformFeature at (100, 49, 0): 5x5 obsidian, air above.
static func end_platform(world) -> Vector3:
	var o := Vector3i(100, 49, 0)
	var obs := Res.blocks.default_state("obsidian")
	for i in range(-2, 3):
		for j in range(-2, 3):
			for k in range(-1, 3):
				world.set_block(o.x + j, o.y + k, o.z + i, obs if k == -1 else 0)
	return Vector3(100.5, 49.0, 0.5)
