## Lighting â€” skylight + blocklight (0..15) for one chunk computed from its 3x3 neighbourhood.
## Why: deterministic, order-independent light that crosses chunk borders, done on worker threads.
## Algorithm: direct sky above each column's heightmap is 15 (implicit); BFS seeds only where height
## differences expose cells to direct sky, plus emitting blocks (palette pre-scan). BFS decrements by
## max(1, opacity). Output: 24 sections of 18x18x16 light bytes (sky<<4|block) incl. a 1-block halo,
## or an int for uniform sections. Contract: compute(snaps[9], heightmaps[9], blocks) -> Array.
class_name Lighting

const W := 48
const LAYER := W * W
const HALO := 18
const HSEC := HALO * HALO * 16
static var profile := false


static func compute(snaps: Array, hms: Array, blocks: BlockRegistry) -> Array:
	if Native.ok and Native.light_ok:
		return Native.inst.light(snaps, hms, blocks.st_opacity, blocks.st_emit)
	return compute_gd(snaps, hms, blocks)


## GDScript implementation (fallback and reference for the native port).
static func compute_gd(snaps: Array, hms: Array, blocks: BlockRegistry) -> Array:
	var opac := blocks.st_opacity
	var emit := blocks.st_emit
	var sky := PackedByteArray()
	sky.resize(LAYER * Coords.HEIGHT)
	var blk := PackedByteArray()
	blk.resize(LAYER * Coords.HEIGHT)
	# region heightmap 48x48 (missing chunk => MAX_Y, i.e. never sky-lit)
	var hm := PackedInt32Array()
	hm.resize(LAYER)
	for cz in 3:
		for cx in 3:
			var h = hms[cz * 3 + cx]
			for z in 16:
				for x in 16:
					hm[(cz * 16 + z) * W + cx * 16 + x] = (h as PackedInt32Array)[x + z * 16] if h != null else Coords.MAX_Y
	var q := PackedInt32Array()
	var touched := PackedByteArray()
	touched.resize(Coords.SECTIONS)
	# --- sky seeds
	for z in W:
		for x in W:
			var h0 := hm[z * W + x]
			if h0 >= Coords.MAX_Y:
				continue
			# the blocking cell itself (water/leaves) receives 15-opacity
			if h0 > Coords.MIN_Y:
				var st0 := _state(snaps, x, h0 - 1, z)
				var o0 := opac[st0]
				if o0 < 15:
					var v0 := 15 - maxi(o0, 1)
					var i0 := ((h0 - 1 - Coords.MIN_Y) * W + z) * W + x
					if v0 > sky[i0]:
						sky[i0] = v0
						q.append(i0)
			var mn := h0
			if x > 0: mn = mini(mn, hm[z * W + x - 1])
			if x < W - 1: mn = mini(mn, hm[z * W + x + 1])
			if z > 0: mn = mini(mn, hm[(z - 1) * W + x])
			if z < W - 1: mn = mini(mn, hm[(z + 1) * W + x])
			for y in range(maxi(mn, Coords.MIN_Y), h0 - 1):
				var st := _state(snaps, x, y, z)
				var o := opac[st]
				if o >= 15:
					continue
				var i := ((y - Coords.MIN_Y) * W + z) * W + x
				var v := 15 - maxi(o, 1)
				if v > sky[i]:
					sky[i] = v
					q.append(i)
	var t1 := Time.get_ticks_usec()
	var nsky := q.size()
	_bfs(q, sky, hm, snaps, opac, true, touched)
	var t2 := Time.get_ticks_usec()
	var skypops := q.size()
	# --- block light seeds (scan only sections whose palette contains an emitter)
	q = PackedInt32Array()
	for ci in 9:
		var snap = snaps[ci]
		if snap == null:
			continue
		var ox := (ci % 3) * 16
		var oz := (ci / 3) * 16
		for s in Coords.SECTIONS:
			var e: Array = snap[s]
			var pal: PackedInt32Array = e[0]
			var has := false
			for p in pal:
				if emit[p] > 0:
					has = true
					break
			if not has:
				continue
			for k in 4096:
				var st2 := _sec_state(e, k)
				var em := emit[st2]
				if em > 0:
					var y2 := Coords.MIN_Y + s * 16 + (k >> 8)
					var i2 := ((y2 - Coords.MIN_Y) * W + oz + ((k >> 4) & 15)) * W + ox + (k & 15)
					if em > blk[i2]:
						blk[i2] = em
						q.append(i2)
						touched[s] = 1
	var t3 := Time.get_ticks_usec()
	_bfs(q, blk, hm, snaps, opac, false, touched)
	var t4 := Time.get_ticks_usec()
	# --- output halo sections for the centre chunk (x,z in -1..16 => region 15..32)
	var minh := Coords.MAX_Y
	var maxh := Coords.MIN_Y
	for z in range(15, 33):
		for x in range(15, 33):
			var hh := hm[z * W + x]
			minh = mini(minh, hh)
			maxh = maxi(maxh, hh)
	var out: Array = []
	out.resize(Coords.SECTIONS)
	for s in Coords.SECTIONS:
		var y0 := Coords.MIN_Y + s * 16
		if touched[s] == 0 and (s == 0 or touched[s - 1] == 0) and (s == Coords.SECTIONS - 1 or touched[s + 1] == 0):
			if y0 >= maxh:
				out[s] = 0xF0
				continue
			if y0 + 16 <= minh - 16:
				out[s] = 0
				continue
		var arr := PackedByteArray()
		arr.resize(HSEC)
		var o := 0
		for ly in 16:
			var y := y0 + ly
			var base := (y - Coords.MIN_Y) * LAYER
			for z in range(15, 33):
				var row := base + z * W
				var hrow := z * W
				for x in range(15, 33):
					var sv := 15 if y >= hm[hrow + x] else sky[row + x]
					arr[o] = (sv << 4) | blk[row + x]
					o += 1
		out[s] = arr
	if profile:
		print("[light] seeds %d sky-bfs %d pops %.1f ms, blk seeds+scan %.1f ms, blk-bfs %d pops %.1f ms, output %.1f ms" % [nsky, skypops, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, q.size(), (t4 - t3) / 1000.0, (Time.get_ticks_usec() - t4) / 1000.0])
	return out


static func _sec_state(e: Array, k: int) -> int:
	var pal: PackedInt32Array = e[0]
	if pal.size() == 1:
		return pal[0]
	var wide: PackedInt32Array = e[2]
	if wide.size() > 0:
		return pal[wide[k]]
	var idx: PackedByteArray = e[1]
	return pal[idx[k]]


static func _state(snaps: Array, x: int, y: int, z: int) -> int:
	if y < Coords.MIN_Y or y >= Coords.MAX_Y:
		return 0
	var snap = snaps[(z >> 4) * 3 + (x >> 4)]
	if snap == null:
		return -1  # missing chunk: callers treat as opaque
	var e: Array = snap[(y - Coords.MIN_Y) >> 4]
	var pal: PackedInt32Array = e[0]
	if pal.size() == 1:
		return pal[0]
	var k := ((y & 15) << 8) | ((z & 15) << 4) | (x & 15)
	var wide: PackedInt32Array = e[2]
	if wide.size() > 0:
		return pal[wide[k]]
	var idx: PackedByteArray = e[1]
	return pal[idx[k]]


## Lazily expanded per-section opacity arrays for the 3x3 region (index ci*24+s): int (uniform) or bytes.
static func _opac_sec(cache: Array, snaps: Array, opac: PackedByteArray, ci: int, s: int) -> Variant:
	var key := ci * Coords.SECTIONS + s
	var v = cache[key]
	if v != null:
		return v
	var snap = snaps[ci]
	if snap == null:
		cache[key] = 15
		return 15
	var e: Array = snap[s]
	var pal: PackedInt32Array = e[0]
	if pal.size() == 1:
		cache[key] = int(opac[pal[0]])
		return cache[key]
	var po := PackedByteArray()
	po.resize(pal.size())
	var all_same := true
	for i in pal.size():
		po[i] = opac[pal[i]]
		if po[i] != po[0]:
			all_same = false
	if all_same:
		cache[key] = int(po[0])
		return cache[key]
	var out := PackedByteArray()
	out.resize(4096)
	var wide: PackedInt32Array = e[2]
	if wide.size() > 0:
		for k in 4096:
			out[k] = po[wide[k]]
	else:
		var idx: PackedByteArray = e[1]
		for k in 4096:
			out[k] = po[idx[k]]
	cache[key] = out
	return out


static func _bfs(q: PackedInt32Array, lt: PackedByteArray, hm: PackedInt32Array, snaps: Array, opac: PackedByteArray, is_sky: bool, touched: PackedByteArray) -> void:
	var cache: Array = []
	cache.resize(9 * Coords.SECTIONS)
	var head := 0
	var dxs := PackedInt32Array([0, 0, 0, 0, -1, 1])
	var dys := PackedInt32Array([-1, 1, 0, 0, 0, 0])
	var dzs := PackedInt32Array([0, 0, -1, 1, 0, 0])
	while head < q.size():
		var i := q[head]
		head += 1
		var v := lt[i]
		if v <= 1:
			continue
		var x := i % W
		var z := (i / W) % W
		var yy := i / LAYER
		touched[yy >> 4] = 1
		for d in 6:
			var nx := x + dxs[d]
			var ny := yy + dys[d]
			var nz := z + dzs[d]
			if nx < 0 or nx >= W or nz < 0 or nz >= W or ny < 0 or ny >= Coords.HEIGHT:
				continue
			if is_sky and ny + Coords.MIN_Y >= hm[nz * W + nx]:
				continue
			var ni := (ny * W + nz) * W + nx
			if lt[ni] >= v - 1:
				continue
			var sec = _opac_sec(cache, snaps, opac, (nz >> 4) * 3 + (nx >> 4), ny >> 4)
			var o: int = sec if sec is int else (sec as PackedByteArray)[((ny & 15) << 8) | ((nz & 15) << 4) | (nx & 15)]
			if o >= 15:
				continue
			var nv := v - maxi(1, o)
			if nv > lt[ni]:
				lt[ni] = nv
				q.append(ni)

## Light lookup in a computed halo section array for local x,z in -1..16.
static func halo_get(sections: Array, x: int, y: int, z: int) -> int:
	if y >= Coords.MAX_Y:
		return 0xF0
	if y < Coords.MIN_Y:
		return 0
	var s = sections[(y - Coords.MIN_Y) >> 4]
	if s is int:
		return s
	return (s as PackedByteArray)[((y & 15) * HALO + (z + 1)) * HALO + (x + 1)]
