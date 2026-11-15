## VoxelRaycast — Amanatides-Woo DDA through the block grid, refined against each block's outline
## boxes (slabs, stairs, torches...). Returns hit block, face normal and exact hit point.
## Contract: cast(origin, dir, max_dist, get_state: Callable(x,y,z)->int, blocks) -> {} or
## {pos: Vector3i, normal: Vector3i, point: Vector3, state: int, dist: float}. Fluids are skipped
## unless include_fluids. World coordinates (not floating-origin visual coordinates).
class_name VoxelRaycast


## sources_only (with include_fluids; Java ClipContext.Fluid.SOURCE_ONLY, the empty bucket): flowing fluid is passed
## through, waterlogged blocks are also hit on their water (FluidState shape) besides their outline.
static func cast(origin: Vector3, dir: Vector3, max_dist: float, get_state: Callable, blocks: BlockRegistry, include_fluids: bool = false, sources_only: bool = false) -> Dictionary:
	dir = dir.normalized()
	var x := int(floor(origin.x))
	var y := int(floor(origin.y))
	var z := int(floor(origin.z))
	var step_x := 1 if dir.x > 0 else -1
	var step_y := 1 if dir.y > 0 else -1
	var step_z := 1 if dir.z > 0 else -1
	var t_dx := absf(1.0 / dir.x) if dir.x != 0.0 else INF
	var t_dy := absf(1.0 / dir.y) if dir.y != 0.0 else INF
	var t_dz := absf(1.0 / dir.z) if dir.z != 0.0 else INF
	var t_x := ((x + 1 - origin.x) if dir.x > 0 else (origin.x - x)) * t_dx if dir.x != 0.0 else INF
	var t_y := ((y + 1 - origin.y) if dir.y > 0 else (origin.y - y)) * t_dy if dir.y != 0.0 else INF
	var t_z := ((z + 1 - origin.z) if dir.z > 0 else (origin.z - z)) * t_dz if dir.z != 0.0 else INF
	var normal := Vector3i.ZERO
	var t := 0.0
	for i in 256:
		var st: int = get_state.call(x, y, z)
		if st > 0:
			var fl := blocks.st_flags[st]
			var solidish := (fl & BlockRegistry.F_AIR) == 0 and ((fl & BlockRegistry.F_LIQUID) == 0 or (include_fluids and not (sources_only and blocks.st_level[st] != 0)))
			if solidish:
				var boxes := blocks.get_outline(st)
				if include_fluids and (fl & BlockRegistry.F_LIQUID):
					boxes = PackedFloat32Array([0, 0, 0, 1, 0.875, 1])
				elif sources_only and include_fluids and (fl & BlockRegistry.F_WATERLOGGED):
					boxes = boxes + PackedFloat32Array([0, 0, 0, 1, 0.875, 1])
				var best := INF
				var bn := normal
				for b in range(0, boxes.size(), 6):
					var r := _ray_box(origin, dir, Vector3(x + boxes[b], y + boxes[b + 1], z + boxes[b + 2]), Vector3(x + boxes[b + 3], y + boxes[b + 4], z + boxes[b + 5]))
					if r.x >= 0.0 and r.x < best:
						best = r.x
						bn = Vector3i(int(r.y), int(r.z), int(r.w))
				if best <= max_dist:
					return {"pos": Vector3i(x, y, z), "normal": bn, "point": origin + dir * best, "state": st, "dist": best}
		if t > max_dist:
			break
		if t_x < t_y and t_x < t_z:
			x += step_x
			t = t_x
			t_x += t_dx
			normal = Vector3i(-step_x, 0, 0)
		elif t_y < t_z:
			y += step_y
			t = t_y
			t_y += t_dy
			normal = Vector3i(0, -step_y, 0)
		else:
			z += step_z
			t = t_z
			t_z += t_dz
			normal = Vector3i(0, 0, -step_z)
	return {}


## Slab test; returns Vector4(t, nx, ny, nz) or t=-1.
static func _ray_box(o: Vector3, d: Vector3, mn: Vector3, mx: Vector3) -> Vector4:
	var tmin := -INF
	var tmax := INF
	var n := Vector3.ZERO
	for a in 3:
		if absf(d[a]) < 1e-12:
			if o[a] < mn[a] or o[a] > mx[a]:
				return Vector4(-1, 0, 0, 0)
			continue
		var t1 := (mn[a] - o[a]) / d[a]
		var t2 := (mx[a] - o[a]) / d[a]
		var nn := -1.0
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
			nn = 1.0
		if t1 > tmin:
			tmin = t1
			n = Vector3.ZERO
			n[a] = nn
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return Vector4(-1, 0, 0, 0)
	if tmax < 0.0:
		return Vector4(-1, 0, 0, 0)
	return Vector4(maxf(tmin, 0.0), n.x, n.y, n.z)
