## Collision — Java-style AABB vs voxel collision: gathers block collision boxes in the swept region and
## clips movement per axis (Y first, then the larger horizontal axis), with step-up support.
## Contract: move(aabb_min, aabb_max, motion, get_state, blocks, step) -> {motion, hit_x, hit_y, hit_z, on_ground}.
## Unloaded columns (state -1) are treated as solid so entities never fall into unloaded terrain.
class_name Collision

const EPS := 1.0e-7

## Fast path (set by WorldManager): when get_state is this world's state_at, gather reads the chunk sections
## directly (one chunk lookup per column instead of three calls per voxel) - same states, same boxes.
static var fast_cm = null
static var fast_world = null
static var native_ok := -1   # RecraftNative.coll_move available (-1 unknown)


static func _is_fast(get_state: Callable) -> bool:
	return fast_cm != null and get_state.get_object() == fast_world and get_state.get_method() == &"state_at"


## Boxes in the region, with an optional cache [key PackedInt32Array, boxes]: reused while the integer region and
## ChunkManager.block_epoch are unchanged (idle mobs gather the same region every tick).
static func gather(mn: Vector3, mx: Vector3, get_state: Callable, blocks: BlockRegistry, cache: Array = []) -> PackedFloat32Array:
	var x0 := int(floor(mn.x - EPS)) - 1
	var y0 := int(floor(mn.y - EPS)) - 1
	var z0 := int(floor(mn.z - EPS)) - 1
	var x1 := int(floor(mx.x + EPS)) + 1
	var y1 := int(floor(mx.y + EPS)) + 1
	var z1 := int(floor(mx.z + EPS)) + 1
	var fast := _is_fast(get_state)
	var key := PackedInt32Array()
	if fast and cache.size() == 2:
		# the region plus the block versions of the chunks it spans (a global epoch was bumped by every edit / chunk
		# commit anywhere, so while flying nothing was ever reused)
		key = PackedInt32Array([x0, y0, z0, x1, y1, z1])
		var chunks: Dictionary = fast_cm.chunks
		for cx in range(x0 >> 4, (x1 >> 4) + 1):
			for cz in range(z0 >> 4, (z1 >> 4) + 1):
				var c: Chunk = chunks.get((cx << 32) | (cz & 0xFFFFFFFF))
				key.append(-1 if c == null else (c.bepoch if c.state >= Chunk.DATA_READY else -2 - c.state))
		if cache[0] == key:
			return cache[1]
	var out := PackedFloat32Array()
	if fast:
		_gather_cm(x0, y0, z0, x1, y1, z1, blocks, out)
		if cache.size() == 2:
			cache[0] = key
			cache[1] = out
		return out
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			for y in range(y0, y1 + 1):
				var st: int = get_state.call(x, y, z)
				if st < 0:
					out.append_array([x, y, z, x + 1, y + 1, z + 1])
					continue
				if st == 0 or (blocks.st_flags[st] & BlockRegistry.F_COLLIDE) == 0:
					continue
				var b := blocks.get_shape(st)
				for i in range(0, b.size(), 6):
					out.append_array([x + b[i], y + b[i + 1], z + b[i + 2], x + b[i + 3], y + b[i + 4], z + b[i + 5]])
	return out


static func _gather_cm(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, blocks: BlockRegistry, out: PackedFloat32Array) -> void:
	var chunks: Dictionary = fast_cm.chunks
	var flags := blocks.st_flags
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var c: Chunk = chunks.get(Coords.chunk_key(x >> 4, z >> 4))
			var ok := c != null and c.state >= Chunk.DATA_READY
			var lx := x & 15
			var lz := z & 15
			for y in range(y0, y1 + 1):
				var st := -1
				if ok:
					if y < Coords.MIN_Y or y >= Coords.MAX_Y:
						st = 0
					else:
						var sec: Chunk.Section = c.sections[(y - Coords.MIN_Y) >> 4]
						var pal := sec.pal
						if pal.size() == 1:
							st = pal[0]
						else:
							var vi := ((y & 15) << 8) | (lz << 4) | lx
							st = pal[sec.wide[vi]] if sec.wide.size() > 0 else pal[sec.idx[vi]]
				if st < 0:
					out.push_back(x)
					out.push_back(y)
					out.push_back(z)
					out.push_back(x + 1)
					out.push_back(y + 1)
					out.push_back(z + 1)
					continue
				if st == 0 or (flags[st] & BlockRegistry.F_COLLIDE) == 0:
					continue
				var b := blocks.get_shape(st)
				for i in range(0, b.size(), 6):
					out.push_back(x + b[i])
					out.push_back(y + b[i + 1])
					out.push_back(z + b[i + 2])
					out.push_back(x + b[i + 3])
					out.push_back(y + b[i + 4])
					out.push_back(z + b[i + 5])


static func _clip(boxes: PackedFloat32Array, mn: Vector3, mx: Vector3, axis: int, d: float) -> float:
	if absf(d) < EPS:
		return 0.0
	var a1 := (axis + 1) % 3
	var a2 := (axis + 2) % 3
	for i in range(0, boxes.size(), 6):
		var bmn := Vector3(boxes[i], boxes[i + 1], boxes[i + 2])
		var bmx := Vector3(boxes[i + 3], boxes[i + 4], boxes[i + 5])
		if bmx[a1] <= mn[a1] + EPS or bmn[a1] >= mx[a1] - EPS:
			continue
		if bmx[a2] <= mn[a2] + EPS or bmn[a2] >= mx[a2] - EPS:
			continue
		if d > 0.0 and bmn[axis] >= mx[axis] - EPS:
			d = minf(d, bmn[axis] - mx[axis])
		elif d < 0.0 and bmx[axis] <= mn[axis] + EPS:
			d = maxf(d, bmx[axis] - mn[axis])
	return d


static func collide(boxes: PackedFloat32Array, mn: Vector3, mx: Vector3, m: Vector3) -> Vector3:
	var out := Vector3.ZERO
	var dy := _clip(boxes, mn, mx, 1, m.y)
	mn.y += dy
	mx.y += dy
	out.y = dy
	var order := [0, 2] if absf(m.x) >= absf(m.z) else [2, 0]
	for a in order:
		var dd := _clip(boxes, mn, mx, a, m[a])
		mn[a] += dd
		mx[a] += dd
		out[a] = dd
	return out


static func move(mn: Vector3, mx: Vector3, m: Vector3, get_state: Callable, blocks: BlockRegistry, step: float, on_ground_before: bool, cache: Array = []) -> Dictionary:
	var smn := mn.min(mn + m) - Vector3(0, 0, 0)
	var smx := mx.max(mx + m) + Vector3(0, step, 0)
	var boxes := gather(smn.min(mn), smx.max(mx), get_state, blocks, cache)
	if native_ok < 0:
		native_ok = 1 if Native.inst != null and Native.inst.has_method("coll_move") else 0
	if native_ok == 1:
		# RecraftNative.coll_move: the same clip / step-up arithmetic as below
		var r: PackedFloat32Array = Native.inst.coll_move(boxes, PackedFloat32Array([mn.x, mn.y, mn.z, mx.x, mx.y, mx.z, m.x, m.y, m.z, step, 1.0 if on_ground_before else 0.0]))[0]
		return {"motion": Vector3(r[0], r[1], r[2]), "hit_x": r[3] > 0.5, "hit_y": r[4] > 0.5, "hit_z": r[5] > 0.5, "on_ground": r[6] > 0.5}
	var res := collide(boxes, mn, mx, m)
	var hit_x := absf(res.x - m.x) > EPS
	var hit_z := absf(res.z - m.z) > EPS
	var hit_y := absf(res.y - m.y) > EPS
	var on_ground := hit_y and m.y < 0.0
	if step > 0.0 and (on_ground or on_ground_before) and (hit_x or hit_z):
		# try stepping: up, horizontal, down
		var up := collide(boxes, mn, mx, Vector3(m.x, step, m.z))
		var up_only := collide(boxes, mn, mx, Vector3(0, step, 0))
		if up_only.y < step:
			var horiz := collide(boxes, mn + up_only, mx + up_only, Vector3(m.x, 0, m.z))
			var alt := up_only + horiz
			if Vector2(alt.x, alt.z).length_squared() > Vector2(up.x, up.z).length_squared():
				up = alt
		var down := collide(boxes, mn + up, mx + up, Vector3(0, -up.y + m.y, 0))
		up += down
		if Vector2(up.x, up.z).length_squared() > Vector2(res.x, res.z).length_squared() + EPS:
			res = up
			hit_x = absf(res.x - m.x) > EPS
			hit_z = absf(res.z - m.z) > EPS
			hit_y = absf(res.y - m.y) > EPS
			on_ground = true
	return {"motion": res, "hit_x": hit_x, "hit_y": hit_y, "hit_z": hit_z, "on_ground": on_ground}


static func overlaps_any(mn: Vector3, mx: Vector3, get_state: Callable, blocks: BlockRegistry) -> bool:
	var boxes := gather(mn, mx, get_state, blocks)
	for i in range(0, boxes.size(), 6):
		if boxes[i] < mx.x - EPS and boxes[i + 3] > mn.x + EPS and boxes[i + 1] < mx.y - EPS and boxes[i + 4] > mn.y + EPS and boxes[i + 2] < mx.z - EPS and boxes[i + 5] > mn.z + EPS:
			return true
	return false
