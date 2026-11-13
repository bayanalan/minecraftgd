## MobPath — vanilla-style ground pathfinding for mobs (Java PathFinder + WalkNodeEvaluator, simplified):
## A* over block nodes (feet cell; 4 straight + 4 diagonal neighbours, one-block jumps, drops of up to 3 blocks),
## path-type maluses (water 8, fire floor 16, honey 8; lava / fire / cactus / berry bush / powder snow / fences /
## closed doors blocked), visited-node cap = follow range x 16, walked-distance cap = follow range, best partial
## path when the goal is unreachable (Java Path.canReach false), goal accepted within Manhattan distance 1.
## A search is a job stepped against a time budget (EntityManager runs jobs within a per-tick budget), so a long
## search never lands in one frame. Stroll / panic jobs pick their random target first (Java DefaultRandomPos /
## LandRandomPos: 10 tries, best walk-target value: animals prefer grass, monsters darkness).
class_name MobPath
extends RefCounted

const MAX_FALL := 3
const DXS := [0, 0, 1, -1, 1, 1, -1, -1]
const DZS := [1, -1, 0, 0, 1, -1, 1, -1]
const C_WATER := 32
const C_BLOCK := 64      # impassable (lava, fire, cactus, sweet berry bush, powder snow, wither rose, closed door)
const C_FIRE := 128      # damaging floor (magma block, lit campfire): malus 16
const C_STICKY := 256    # honey block floor: malus 8
const C_OPEN_DOOR := 512
const C_GRASS := 1024    # grass block (Java animal walk-target value 10)

static var _cls := PackedInt32Array()   # per block state: top height in 16ths (0..24) | flags; -1 = not computed
# probe statistics (--mobprobe)
static var stat_jobs := 0
static var stat_reached := 0
static var stat_us := 0
static var stat_max_us := 0
static var stat_nodes := 0
static var stat_t := PackedInt64Array([0, 0, 0, 0])   # native path: grid, class table, search, convert (us)
var _us := 0

var cm
var blocks: BlockRegistry
var start := Vector3i.ZERO
var start_fy := 0.0       # the mob's feet height (start node floor)
var goal := Vector3i.ZERO
var goal_pos := Vector3.INF
var reach := 1
var max_nodes := 256
var max_dist := 16.0
var h := 1.8
var land := true          # water nodes cost 8 (Java PathType.WATER malus for land mobs)
var mode := 0             # 0 path to goal_pos, 1 stroll (pick a random target first), 2 panic (random, 5/4)
var monster := false
var rng: RandomNumberGenerator
var done := false
var result: Array = []    # Array[Vector3i]: nodes after the start node
var reached := false

var _hc := 2              # head-room cells above the feet cell
var _cells := {}
var _nodes := {}
var _g := {}
var _from := {}
var _closed := {}
var _heap_k := PackedInt64Array()
var _heap_f := PackedFloat64Array()
var _visited := 0
var _best := 0
var _best_h := INF
var _started := false


static var _cls_full := false
static var _native := -1


func _init(chunk_manager, reg: BlockRegistry) -> void:
	cm = chunk_manager
	blocks = reg
	if _cls.size() != blocks.total_states:
		_cls = PackedInt32Array()
		_cls.resize(blocks.total_states)
		_cls.fill(-1)
		_cls_full = false


## Path class of every block state (for the native search); built once per registry, at world load.
static func class_table(reg: BlockRegistry) -> PackedInt32Array:
	var mp := MobPath.new(null, reg)
	if not _cls_full:
		for st in reg.total_states:
			if _cls[st] < 0:
				mp._state_class(st)
		_cls_full = true
	return _cls


static func native_ok() -> bool:
	if _native < 0:
		_native = 1 if Native.inst != null and Native.inst.has_method("path_find") else 0
	return _native == 1


## The whole search in RecraftNative.path_find (microseconds instead of milliseconds): the chunks around the start
## by reference (Chunk.sec_refs), the class table, the parameters.
func _native_search() -> void:
	var t0 := Time.get_ticks_usec()
	var r := int(ceil(max_dist)) + 2
	var cx0 := (start.x - r) >> 4
	var cz0 := (start.z - r) >> 4
	var gw := ((start.x + r) >> 4) - cx0 + 1
	var gh := ((start.z + r) >> 4) - cz0 + 1
	var grid: Array = []
	grid.resize(gw * gh)
	for j in gh:
		for i in gw:
			var c: Chunk = cm.chunks.get(((cx0 + i) << 32) | ((cz0 + j) & 0xFFFFFFFF))
			if c != null and c.state >= Chunk.DATA_READY:
				grid[j * gw + i] = c.sec_refs()
	var gp := Vector3i(floori(goal_pos.x), floori(goal_pos.y + 0.49), floori(goal_pos.z)) if mode == 0 else Vector3i.ZERO
	var p := PackedInt32Array([start.x, start.y, start.z, roundi(start_fy * 1000.0), gp.x, gp.y, gp.z, reach, max_nodes,
		roundi(max_dist), roundi(h * 1000.0), 1 if land else 0, mode | (4 if monster else 0), rng.randi() & 0x7FFFFFFF if rng != null else 1])
	var t1 := Time.get_ticks_usec()
	var tab := class_table(blocks)
	var t2 := Time.get_ticks_usec()
	var res: Array = Native.inst.path_find(grid, gw, gh, cx0, cz0, tab, p)
	var t3 := Time.get_ticks_usec()
	stat_t[0] += t1 - t0
	stat_t[1] += t2 - t1
	stat_t[2] += t3 - t2
	var nodes: PackedInt32Array = res[0]
	result = []
	for k in range(0, nodes.size(), 3):
		result.append(Vector3i(nodes[k], nodes[k + 1], nodes[k + 2]))
	reached = int(res[1]) == 1
	_visited = int(res[2])
	goal = Vector3i(int(res[3]), int(res[4]), int(res[5]))
	goal_pos = Vector3(goal.x + 0.5, goal.y, goal.z + 0.5)
	done = true
	stat_t[3] += Time.get_ticks_usec() - t3


static func _key(x: int, y: int, z: int) -> int:
	return ((x + 33554432) << 36) | ((z + 33554432) << 10) | (y + 256)


func _state_class(st: int) -> int:
	var c := _cls[st]
	if c >= 0:
		return c
	var f := blocks.st_flags[st]
	c = 0
	var nm := blocks.name_of(st)
	if f & BlockRegistry.F_LAVA:
		c |= C_BLOCK
	elif f & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED):
		c |= C_WATER
	match nm:
		"fire", "soul_fire", "cactus", "sweet_berry_bush", "powder_snow", "wither_rose", "lava_cauldron", "pointed_dripstone":
			c |= C_BLOCK
		"magma_block":
			c |= C_FIRE
		"campfire", "soul_campfire":
			if blocks.get_prop(st, "lit") == "true":
				c |= C_FIRE
		"honey_block":
			c |= C_STICKY
		"grass_block":
			c |= C_GRASS
	if nm.ends_with("_door"):
		c |= C_OPEN_DOOR if blocks.get_prop(st, "open") == "true" else C_BLOCK
	elif f & BlockRegistry.F_COLLIDE:
		var boxes: PackedFloat32Array = blocks.shapes[blocks.st_shape[st]]
		var top := 0.0
		for i in range(0, boxes.size(), 6):
			top = maxf(top, boxes[i + 4])
		c |= clampi(roundi(top * 16.0), 1 if boxes.size() > 0 else 0, 24)
	_cls[st] = c
	return c


func _cell(x: int, y: int, z: int) -> int:
	var k := _key(x, y, z)
	var v = _cells.get(k)
	if v != null:
		return v
	var c := C_BLOCK
	if y >= Coords.MAX_Y:
		c = 0
	elif y >= Coords.MIN_Y:
		var st: int = cm.get_block(x, y, z)
		c = C_BLOCK if st < 0 else (0 if st == 0 else _state_class(st))
	_cells[k] = c
	return c


## Standing at node (x, y, z): Vector2(malus, floor height), or x = -1 blocked / -2 open with no floor.
func _node(x: int, y: int, z: int) -> Vector2:
	var k := _key(x, y, z)
	var v = _nodes.get(k)
	if v != null:
		return v
	var r := _node_calc(x, y, z)
	_nodes[k] = r
	return r


func _node_calc(x: int, y: int, z: int) -> Vector2:
	var c0 := _cell(x, y, z)
	if c0 & C_BLOCK:
		return Vector2(-1, 0)
	var t0 := c0 & 31
	var mal := 0.0
	var fy := float(y)
	if c0 & C_FIRE:
		mal = 16.0
	if t0 > 8:
		return Vector2(-1, 0)
	if t0 > 0:
		fy = y + t0 / 16.0
	elif c0 & C_WATER:
		if _cell(x, y + 1, z) & C_WATER:
			return Vector2(-1, 0)   # under the surface: floating mobs path along the top
		if land:
			mal = maxf(mal, 8.0)
	else:
		var c1 := _cell(x, y - 1, z)
		var t1 := c1 & 31
		if c1 & C_BLOCK and t1 == 0:
			return Vector2(-1, 0)
		if t1 < 8:
			return Vector2(-2, 0)
		if t1 > 16 or c1 & C_BLOCK:
			return Vector2(-1, 0)   # fences / walls / cactus underfoot
		fy = y - 1 + t1 / 16.0
		if c1 & C_FIRE:
			mal = maxf(mal, 16.0)
		if c1 & C_STICKY:
			mal = maxf(mal, 8.0)
	var top := int(ceil(fy + h - 0.001))
	for cy in range(y + 1, top):
		var c := _cell(x, cy, z)
		if c & (C_BLOCK | 31):
			return Vector2(-1, 0)
	return Vector2(mal, fy)


## Java WalkNodeEvaluator.findAcceptedNode: same level, else one-block jump, else drop up to MAX_FALL.
func _accept(cx: int, cy: int, cz: int, cfy: float, nx: int, nz: int) -> int:
	var v := _node(nx, cy, nz)
	if v.x >= 0.0:
		return cy if v.y - cfy <= 1.125 else -99999
	if v.x == -1.0:
		if _cell(cx, cy + _hc, cz) & (C_BLOCK | 31):
			return -99999   # no head room to jump
		var u := _node(nx, cy + 1, nz)
		if u.x >= 0.0 and u.y - cfy <= 1.25:
			return cy + 1
		return -99999
	for d in range(1, MAX_FALL + 2):
		var w := _node(nx, cy - d, nz)
		if w.x >= 0.0:
			return cy - d
		if w.x == -1.0:
			return -99999
	return -99999


func _heap_push(k: int, f: float) -> void:
	_heap_k.append(k)
	_heap_f.append(f)
	var i := _heap_k.size() - 1
	while i > 0:
		var pi := (i - 1) >> 1
		if _heap_f[pi] <= f:
			break
		_heap_k[i] = _heap_k[pi]
		_heap_f[i] = _heap_f[pi]
		i = pi
	_heap_k[i] = k
	_heap_f[i] = f


func _heap_pop() -> int:
	var top := _heap_k[0]
	var n := _heap_k.size() - 1
	var lk := _heap_k[n]
	var lf := _heap_f[n]
	_heap_k.resize(n)
	_heap_f.resize(n)
	if n > 0:
		var i := 0
		while true:
			var l := i * 2 + 1
			if l >= n:
				break
			var r := l + 1
			var m := r if r < n and _heap_f[r] < _heap_f[l] else l
			if _heap_f[m] >= lf:
				break
			_heap_k[i] = _heap_k[m]
			_heap_f[i] = _heap_f[m]
			i = m
		_heap_k[i] = lk
		_heap_f[i] = lf
	return top


static func _unkey(k: int) -> Vector3i:
	return Vector3i((k >> 36) - 33554432, (k & 1023) - 256, ((k >> 10) & 67108863) - 33554432)


func _hdist(x: int, y: int, z: int) -> float:
	return Vector3(x - goal.x, y - goal.y, z - goal.z).length()


## Java RandomPos / LandRandomPos: up to 10 random offsets (+-hr, +-vr), moved onto the ground, scored by the walk
## target value; null target = Vector3i(0, -9999, 0).
func _pick_random(hr: int, vr: int) -> Vector3i:
	var best := Vector3i(0, -9999, 0)
	var best_v := -INF
	for _i in 10:
		var x := start.x + rng.randi_range(-hr, hr)
		var y := start.y + rng.randi_range(-vr, vr)
		var z := start.z + rng.randi_range(-hr, hr)
		var ok := false
		for d in 2 * vr + 1:   # settle on the ground: up out of solids, down through air
			var v := _node(x, y, z)
			if v.x >= 0.0:
				ok = true
				break
			y += 1 if v.x == -1.0 else -1
		if not ok:
			continue
		var c0 := _cell(x, y, z)
		if land and c0 & C_WATER:
			continue
		var val := 0.0
		var sl: int = cm.get_light(x, y, z)
		var lv := maxf((sl >> 4) * 1.0, (sl & 15) * 1.0) / 15.0
		if monster:
			val = 0.5 - lv
		else:
			val = 10.0 if blocks.name_of(maxi(cm.get_block(x, y - 1, z), 0)) == "grass_block" else lv - 0.5
		if val > best_v:
			best_v = val
			best = Vector3i(x, y, z)
	return best


static func stat_reset() -> void:
	stat_t = PackedInt64Array([0, 0, 0, 0])
	stat_jobs = 0
	stat_reached = 0
	stat_us = 0
	stat_max_us = 0
	stat_nodes = 0


## Runs the search until it finishes or Time.get_ticks_usec() passes deadline_us; true when done.
func step(deadline_us: int) -> bool:
	if done:
		return true
	var t0 := Time.get_ticks_usec()
	var fin := _step(deadline_us)
	_us += Time.get_ticks_usec() - t0
	if fin:
		stat_jobs += 1
		stat_reached += 1 if reached else 0
		stat_us += _us
		stat_max_us = maxi(stat_max_us, _us)
		stat_nodes += _visited
	return fin


func _step(deadline_us: int) -> bool:
	if not _started and native_ok():
		_started = true
		_native_search()
		return true
	if not _started:
		_started = true
		_hc = maxi(1, int(ceil(h)))
		if mode != 0:
			var t := _pick_random(10, 7) if mode == 1 else _pick_random(5, 4)
			if t.y == -9999:
				done = true
				return true
			goal = t
			goal_pos = Vector3(t.x + 0.5, t.y, t.z + 0.5)
		else:
			goal = Vector3i(floori(goal_pos.x), floori(goal_pos.y + 0.49), floori(goal_pos.z))
		var sk := _key(start.x, start.y, start.z)
		_g[sk] = 0.0
		_best = sk
		_best_h = _hdist(start.x, start.y, start.z)
		_heap_push(sk, _best_h)
	var n := 0
	var sk0 := _key(start.x, start.y, start.z)
	while not _heap_k.is_empty():
		n += 1
		if n % 4 == 0 and Time.get_ticks_usec() >= deadline_us:
			return false
		var k := _heap_pop()
		if _closed.has(k):
			continue
		_closed[k] = true
		var c := _unkey(k)
		var hd := _hdist(c.x, c.y, c.z)
		if absi(c.x - goal.x) + absi(c.y - goal.y) + absi(c.z - goal.z) <= reach:
			_best = k
			reached = true
			break
		if hd < _best_h:
			_best_h = hd
			_best = k
		_visited += 1
		if _visited >= max_nodes:
			break
		var gc: float = _g[k]
		var cfy: float = start_fy if k == sk0 else _node(c.x, c.y, c.z).y
		var ok_dirs := 0
		for d in 8:
			var dx: int = DXS[d]
			var dz: int = DZS[d]
			var ny := -99999
			if d < 4:
				ny = _accept(c.x, c.y, c.z, cfy, c.x + dx, c.z + dz)
				if ny == c.y:
					ok_dirs |= 1 << d
			else:
				# Java isDiagonalValid: both side nodes walkable on this level, diagonal node on this level too
				var sa := 4 if dx > 0 else 8      # +x / -x bit
				var sb := 1 if dz > 0 else 2      # +z / -z bit
				if (ok_dirs & sa) and (ok_dirs & sb):
					var v := _node(c.x + dx, c.y, c.z + dz)
					if v.x >= 0.0 and v.y - cfy <= 0.6:
						ny = c.y
			if ny == -99999:
				continue
			var nx := c.x + dx
			var nz := c.z + dz
			var nk := _key(nx, ny, nz)
			if _closed.has(nk):
				continue
			if Vector3(nx - start.x, ny - start.y, nz - start.z).length() > max_dist:
				continue   # Java PathFinder: nodes beyond the follow range are not expanded
			var nv := _node(nx, ny, nz)
			var ng := gc + Vector3(dx, ny - c.y, dz).length() + maxf(nv.x, 0.0)
			var og = _g.get(nk)
			if og != null and og <= ng:
				continue
			_g[nk] = ng
			_from[nk] = k
			_heap_push(nk, ng + _hdist(nx, ny, nz))
	# Java Path: the reached node, else the visited node closest to the target
	var out: Array = []
	var cur := _best
	var sk2 := _key(start.x, start.y, start.z)
	while cur != sk2 and _from.has(cur):
		out.append(_unkey(cur))
		cur = _from[cur]
	out.reverse()
	result = out
	done = true
	return true
