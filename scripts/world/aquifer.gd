## Aquifer — Java NoiseBasedAquifer re-implementation (source D): 16x12x16 aquifer grid with random cell
## centres (positional "minecraft:aquifer" random), nearest-4 status blending, barrier pressure, floodedness /
## spread / lava noises from the 26.3 `aquifers` density functions, deep-dark exclusion function, lava below
## Y=-54 and sea level 63 global fluid picker. APPROXIMATION: surface sampling uses the 16-block interpolated
## preliminary surface (chunk_surface_level semantics) instead of exact per-position find_top_surface.
## Contract: Aquifer.new(gen, ctx, cx, cz).substance(x, y, z, density) -> state id, or -1 for "solid".
class_name Aquifer
extends RefCounted

const OFFSETS := [[0, 0], [-2, -1], [-1, -1], [0, -1], [1, -1], [-3, 0], [-2, 0], [-1, 0], [1, 0], [-2, 1], [-1, 1], [0, 1], [1, 1]]
const WAY_BELOW := -2032  # DimensionType.WAY_BELOW_MIN_Y

var gen: VanillaGenerator
var ctx: DensityFunctions.Ctx
var min_gx := 0
var min_gy := 0
var min_gz := 0
var sx := 0
var sy := 0
var sz := 0
var loc_x := PackedInt32Array()
var loc_y := PackedInt32Array()
var loc_z := PackedInt32Array()
var loc_set := PackedByteArray()
var status_level := PackedInt32Array()
var status_fluid := PackedInt32Array()
var status_set := PackedByteArray()
var water := 0
var lava := 0
var sea := 63


func _init(g: VanillaGenerator, c: DensityFunctions.Ctx, cx: int, cz: int) -> void:
	gen = g
	ctx = c
	water = g.S_WATER
	lava = g.S_LAVA
	sea = g.sea_level
	min_gx = floori((cx * 16) / 16.0) - 1
	var max_gx := floori((cx * 16 + 15) / 16.0) + 1
	min_gz = floori((cz * 16) / 16.0) - 1
	var max_gz := floori((cz * 16 + 15) / 16.0) + 1
	min_gy = floori(Coords.MIN_Y / 12.0) - 1
	var max_gy := floori(Coords.MAX_Y / 12.0) + 1
	sx = max_gx - min_gx + 1
	sy = max_gy - min_gy + 1
	sz = max_gz - min_gz + 1
	var n := sx * sy * sz
	loc_x.resize(n)
	loc_y.resize(n)
	loc_z.resize(n)
	loc_set.resize(n)
	status_level.resize(n)
	status_fluid.resize(n)
	status_set.resize(n)
	# precompute every aquifer cell centre (Java: positional random at grid coords)
	for gy in range(min_gy, min_gy + sy):
		for gz in range(min_gz, min_gz + sz):
			for gx in range(min_gx, min_gx + sx):
				var i := _index(gx, gy, gz)
				var r = g.aquifer_rand.at(gx, gy, gz)
				loc_x[i] = gx * 16 + r.next_int_bound(10)
				loc_y[i] = gy * 12 + r.next_int_bound(9)
				loc_z[i] = gz * 16 + r.next_int_bound(10)
				loc_set[i] = 1


func _index(gx: int, gy: int, gz: int) -> int:
	return ((gy - min_gy) * sz + (gz - min_gz)) * sx + (gx - min_gx)


## Global fluid picker: lava below min(-54, sea), water level = sea level.
func _global(y: int) -> Vector2i:
	if y < mini(-54, sea):
		return Vector2i(-54, lava)
	return Vector2i(sea, water)


static func _at(st: Vector2i, y: int) -> int:
	return st.y if y < st.x else 0


static func _sim(a: int, b: int) -> float:
	return 1.0 - absi(b - a) / 25.0


func _location(gx: int, gy: int, gz: int) -> Vector3i:
	var i := _index(gx, gy, gz)
	if i >= 0 and i < loc_set.size() and loc_set[i] == 1:
		return Vector3i(loc_x[i], loc_y[i], loc_z[i])
	var r = gen.aquifer_rand.at(gx, gy, gz)
	var p := Vector3i(gx * 16 + int(r.next_int_bound(10)), gy * 12 + int(r.next_int_bound(9)), gz * 16 + int(r.next_int_bound(10)))
	if i >= 0 and i < loc_set.size():
		loc_set[i] = 1
		loc_x[i] = p.x
		loc_y[i] = p.y
		loc_z[i] = p.z
	return p


func _status(p: Vector3i) -> Vector2i:
	var gx := floori(p.x / 16.0)
	var gy := floori(p.y / 12.0)
	var gz := floori(p.z / 16.0)
	var i := _index(gx, gy, gz)
	if i >= 0 and i < status_set.size() and status_set[i] == 1:
		return Vector2i(status_level[i], status_fluid[i])
	var s := _compute_fluid(p.x, p.y, p.z)
	if i >= 0 and i < status_set.size():
		status_set[i] = 1
		status_level[i] = s.x
		status_fluid[i] = s.y
	return s


func _compute_fluid(x: int, y: int, z: int) -> Vector2i:
	var glob := _global(y)
	var min_surface := 2147483647
	var hi := y + 12
	var lo := y - 12
	var flooded := false
	for o in OFFSETS:
		var ox: int = x + o[0] * 16
		var oz: int = z + o[1] * 16
		var q: int = gen.chunk_surface(ctx, ox, oz)
		var r := q + 8
		var center: bool = o[0] == 0 and o[1] == 0
		if center and lo > r:
			return glob
		var above := hi > r
		if above or center:
			var g2 := _global(r)
			if _at(g2, r) != 0:
				if center:
					flooded = true
				if above:
					return g2
		min_surface = mini(min_surface, q)
	var lvl := _surface_level(x, y, z, glob, min_surface, flooded)
	return Vector2i(lvl, _fluid_type(x, y, z, glob, lvl))


func _surface_level(x: int, y: int, z: int, glob: Vector2i, min_surface: int, flooded: bool) -> int:
	var d: float
	var e: float
	if gen.aq_exclusion.point(ctx, x, y, z) > 0.0:
		d = -1.0
		e = -1.0
	else:
		var m := min_surface + 8 - y
		var f := clampf(remap(float(m), 0.0, 64.0, 1.0, 0.0), 0.0, 1.0) if flooded else 0.0
		var g := clampf(gen.aq_flood.point(ctx, x, y, z), -1.0, 1.0)
		var h := remap(f, 1.0, 0.0, -0.3, 0.8)
		var o := remap(f, 1.0, 0.0, -0.8, 0.4)
		d = g - o
		e = g - h
	if e > 0.0:
		return glob.x
	if d > 0.0:
		var px := floori(x / 16.0)
		var py := floori(y / 40.0)
		var pz := floori(z / 16.0)
		var r := py * 40 + 20
		var dd := gen.aq_spread.point(ctx, px, py, pz) * 10.0
		var t := int(floorf(dd / 3.0)) * 3
		return mini(min_surface, r + t)
	return WAY_BELOW


func _fluid_type(x: int, y: int, z: int, glob: Vector2i, lvl: int) -> int:
	if lvl <= -10 and lvl != WAY_BELOW and glob.y != lava:
		var d := gen.aq_lava.point(ctx, floori(x / 64.0), floori(y / 40.0), floori(z / 64.0))
		if absf(d) > 0.3:
			return lava
	return glob.y


func _pressure(y: int, a: Vector2i, b: Vector2i, x: int, z: int, barrier: Array) -> float:
	var sa := _at(a, y)
	var sb := _at(b, y)
	if (sa == lava and sb == water) or (sa == water and sb == lava):
		return 2.0
	var j := absi(a.x - b.x)
	if j == 0:
		return 0.0
	var k := 0.5 * (a.x + b.x)
	var l := y + 0.5 - k
	var m := j / 2.0
	var t := m - absf(l)
	var v: float
	if l > 0.0:
		v = t / 1.5 if t > 0.0 else t / 2.5
	else:
		var u := 3.0 + t
		v = u / 3.0 if u > 0.0 else u / 10.0
	var xb := 0.0
	if v >= -2.0 and v <= 2.0:
		if barrier.is_empty():
			barrier.append(gen.aq_barrier.point(ctx, x, y, z))
		xb = barrier[0]
	return 2.0 * (xb + v)


## Returns the fluid/air state for an air-density block, or -1 when the aquifer turns it into solid stone.
## Hot path: helpers inlined (GDScript calls are expensive and contend across worker threads); status index of a
## cell centre equals its grid index because centres lie inside their own 16x12x16 cell.
func substance(x: int, y: int, z: int, density: float) -> int:
	if density > 0.0:
		return -1
	var lava_y := mini(-54, sea)
	if y < lava_y:
		return lava
	var l := (x - 5) >> 4
	var m := floori((y + 1) / 12.0)
	var n := (z - 5) >> 4
	var d0 := 2147483647
	var d1 := 2147483647
	var d2 := 2147483647
	var i0 := 0
	var i1 := 0
	var i2 := 0
	var lxa := loc_x
	var lya := loc_y
	var lza := loc_z
	var _sx := sx
	var _sz := sz
	var _mgx := min_gx
	var _mgy := min_gy
	var _mgz := min_gz
	for w in 2:
		for xx in range(-1, 2):
			for yy in 2:
				var gi := ((m + xx - _mgy) * _sz + (n + yy - _mgz)) * _sx + (l + w - _mgx)
				var dx := lxa[gi] - x
				var dy := lya[gi] - y
				var dz := lza[gi] - z
				var dist := dx * dx + dy * dy + dz * dz
				if d0 >= dist:
					i2 = i1
					d2 = d1
					i1 = i0
					d1 = d0
					i0 = gi
					d0 = dist
				elif d1 >= dist:
					i2 = i1
					d2 = d1
					i1 = gi
					d1 = dist
				elif d2 >= dist:
					i2 = gi
					d2 = dist
	var ss := status_set
	if ss[i0] == 0:
		_fill_status(i0)
	var lv0 := status_level[i0]
	var fl0 := status_fluid[i0]
	var st := fl0 if y < lv0 else 0
	var sim01 := 1.0 - absi(d1 - d0) / 25.0
	if sim01 <= 0.0:
		return st
	if st == water and y - 1 < lava_y:
		return st
	_bar_set = false
	if ss[i1] == 0:
		_fill_status(i1)
	var lv1 := status_level[i1]
	var fl1 := status_fluid[i1]
	var e := sim01 * _press(y, lv0, fl0, lv1, fl1, x, z)
	if density + e > 0.0:
		return -1
	if ss[i2] == 0:
		_fill_status(i2)
	var lv2 := status_level[i2]
	var fl2 := status_fluid[i2]
	var f := 1.0 - absi(d2 - d0) / 25.0
	if f > 0.0:
		var g := sim01 * f * _press(y, lv0, fl0, lv2, fl2, x, z)
		if density + g > 0.0:
			return -1
	var h := 1.0 - absi(d2 - d1) / 25.0
	if h > 0.0:
		var g2 := sim01 * h * _press(y, lv1, fl1, lv2, fl2, x, z)
		if density + g2 > 0.0:
			return -1
	return st


var _bar_set := false
var _bar := 0.0


func _fill_status(i: int) -> void:
	var s := _compute_fluid(loc_x[i], loc_y[i], loc_z[i])
	status_set[i] = 1
	status_level[i] = s.x
	status_fluid[i] = s.y


func _press(y: int, la: int, fa: int, lb: int, fb: int, x: int, z: int) -> float:
	var sa := fa if y < la else 0
	var sb := fb if y < lb else 0
	if (sa == lava and sb == water) or (sa == water and sb == lava):
		return 2.0
	var j := absi(la - lb)
	if j == 0:
		return 0.0
	var k := 0.5 * (la + lb)
	var l := y + 0.5 - k
	var t := j / 2.0 - absf(l)
	var v: float
	if l > 0.0:
		v = t / 1.5 if t > 0.0 else t / 2.5
	else:
		var u := 3.0 + t
		v = u / 3.0 if u > 0.0 else u / 10.0
	var xb := 0.0
	if v >= -2.0 and v <= 2.0:
		if not _bar_set:
			_bar = gen.aq_barrier.point(ctx, x, y, z)
			_bar_set = true
		xb = _bar
	return 2.0 * (xb + v)