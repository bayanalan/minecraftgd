## DensityFunctions — compiles the installed version's worldgen/density_function JSON (26.3 schema: add,
## mul, noise(+shift), gradient, lerp, range_choice, interval_select, spline, interpolated(cell sizes),
## find_top_surface, old_blended_noise, cache...) into an immutable shared DAG and evaluates it in BATCHES
## (arrays of points) so interpreter overhead is paid per node, not per voxel.
## Why: GDScript is slow per call; batching + memo + 2D-column dedupe + selective branch evaluation keep
## per-chunk cost bounded while producing the same values as per-point evaluation.
## Contract: DFCompiler.new(seed, json_source).get_df(name_or_json) -> DF; DF.batch(ctx, pts) -> PackedFloat64Array;
## DF.point(ctx, x, y, z) -> float. Ctx holds per-job memo (never share a Ctx between threads).
## Parity: structure/constants come from the user's 26.3 data; noise normalisation & float32 spline rounding are
## documented approximations (docs/DECISIONS.md) — output is NOT claimed bit-exact.
class_name DensityFunctions

enum K { CONST, ADD, MUL, SUB, DIV, MIN, MAX, ABS, SQUARE, CUBE, HALF_NEG, QUARTER_NEG, SQUEEZE, NEGATE, CLAMP,
	RANGE, LERP, GRADIENT, NOISE, SHIFT_A, SHIFT_B, SHIFT, BLENDED, INTERP, PASS, ONE, ZERO, SPLINE, INTERVAL,
	TOP_SURFACE, END_ISLANDS, DIST }


class Pts:
	var id := 0
	var n := 0
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var zs := PackedInt32Array()
	var root: Pts = null           # top-level batch (self for roots)
	var parent: Pts = null         # direct parent batch (sub-batches only)
	var inv := PackedInt32Array()  # lazily built: root index -> position in this batch (-1 if absent)
	var ridx := PackedInt32Array() # indices into root (empty for roots)
	var cols: Pts = null           # unique (x,z) columns of a ROOT batch (y=0)
	var col_of := PackedInt32Array()
	var kind := 0                  # 0 generic, 1 corner grid, 2 chunk blocks
	var cells := PackedInt32Array() # cell-major sub-batch: active cell ids (4x8x4 cells), 128 blocks each
	var grid := {}                 # kind 1: {cxz, cy, nx, ny, nz, x0, y0, z0}

	func is_root() -> bool:
		return root == self


class Ctx:
	var next_id := 1
	var memo_id := PackedInt32Array()
	var memo_val: Array = []
	var memo2_id := PackedInt32Array()
	var memo2_val: Array = []
	var x0 := 0
	var z0 := 0
	var corner_cache: Dictionary = {}   # "cxz,cy" -> Pts corner grid for current chunk
	var point_cache: Dictionary = {}    # Vector4i(node, x, y, z) -> value (2D/expensive point evals)
	var has_chunk := false
	var prof: Dictionary = {}   # node id -> [inclusive usec, calls, points] when profiling

	func _init(node_count: int) -> void:
		memo_id.resize(node_count)
		memo_val.resize(node_count)
		memo2_id.resize(node_count)
		memo2_val.resize(node_count)

	func new_root(xs: PackedInt32Array, ys: PackedInt32Array, zs: PackedInt32Array, kind: int = 0) -> Pts:
		var p := Pts.new()
		p.id = next_id
		next_id += 1
		p.n = xs.size()
		p.xs = xs
		p.ys = ys
		p.zs = zs
		p.root = p
		p.kind = kind
		# unique columns
		var seen := {}
		p.col_of.resize(p.n)
		var cx := PackedInt32Array()
		var cz := PackedInt32Array()
		for i in p.n:
			var key := Vector2i(xs[i], zs[i])
			var ci = seen.get(key)
			if ci == null:
				ci = cx.size()
				seen[key] = ci
				cx.append(xs[i])
				cz.append(zs[i])
			p.col_of[i] = ci
		var c := Pts.new()
		c.id = next_id
		next_id += 1
		c.n = cx.size()
		c.xs = cx
		c.zs = cz
		var cy := PackedInt32Array()
		cy.resize(c.n)
		c.ys = cy
		c.root = c
		c.cols = c
		c.col_of.resize(c.n)
		for i in c.n:
			c.col_of[i] = i
		p.cols = c
		return p

	## Root batch covering every block of the current chunk (index = ((y-MIN_Y)<<8)|(z<<4)|x); coordinates lazy.
	func chunk_blocks() -> Pts:
		if corner_cache.has("blocks"):
			return corner_cache["blocks"]
		var p := Pts.new()
		p.id = next_id
		next_id += 1
		p.n = 98304
		p.root = p
		p.kind = 2
		var c := Pts.new()
		c.id = next_id
		next_id += 1
		c.n = 256
		c.root = c
		c.cols = c
		c.xs.resize(256)
		c.zs.resize(256)
		c.ys.resize(256)
		c.col_of.resize(256)
		for i in 256:
			c.xs[i] = x0 + (i & 15)
			c.zs[i] = z0 + (i >> 4)
			c.col_of[i] = i
		p.cols = c
		p.col_of.resize(98304)
		for i in 98304:
			p.col_of[i] = i & 255
		corner_cache["blocks"] = p
		return p

	func ensure_coords(p: Pts) -> void:
		if p.kind != 2 or p.xs.size() == p.n:
			return
		p.xs.resize(p.n)
		p.ys.resize(p.n)
		p.zs.resize(p.n)
		for i in p.n:
			p.xs[i] = x0 + (i & 15)
			p.zs[i] = z0 + ((i >> 4) & 15)
			p.ys[i] = Coords.MIN_Y + (i >> 8)

	func sub(parent: Pts, idx: PackedInt32Array) -> Pts:
		if parent.kind == 2 and parent.xs.size() != parent.n:
			var q := Pts.new()
			q.id = next_id
			next_id += 1
			q.n = idx.size()
			q.root = parent
			q.ridx = idx
			q.parent = parent
			q.xs.resize(q.n)
			q.ys.resize(q.n)
			q.zs.resize(q.n)
			for i in q.n:
				var j := idx[i]
				q.xs[i] = x0 + (j & 15)
				q.zs[i] = z0 + ((j >> 4) & 15)
				q.ys[i] = Coords.MIN_Y + (j >> 8)
			return q
		var p := Pts.new()
		p.id = next_id
		next_id += 1
		p.n = idx.size()
		p.root = parent.root
		p.kind = 0
		p.xs.resize(p.n)
		p.ys.resize(p.n)
		p.zs.resize(p.n)
		p.ridx.resize(p.n)
		p.parent = parent
		var pr := parent.ridx
		var proot := parent.is_root()
		for i in p.n:
			var j := idx[i]
			p.xs[i] = parent.xs[j]
			p.ys[i] = parent.ys[j]
			p.zs[i] = parent.zs[j]
			p.ridx[i] = j if proot else pr[j]
		return p

	## Corner grid for cell size (cxz, cy) covering the current chunk.
	func corners(cxz: int, cy: int) -> Pts:
		var key := "%d,%d" % [cxz, cy]
		if corner_cache.has(key):
			return corner_cache[key]
		var nx := 16 / cxz + 1
		var ny := Coords.HEIGHT / cy + 1
		var xs := PackedInt32Array()
		var ys := PackedInt32Array()
		var zs := PackedInt32Array()
		for iy in ny:
			for iz in nx:
				for ix in nx:
					xs.append(x0 + ix * cxz)
					ys.append(Coords.MIN_Y + iy * cy)
					zs.append(z0 + iz * cxz)
		var p := new_root(xs, ys, zs, 1)
		p.grid = {"cxz": cxz, "cy": cy, "nx": nx, "ny": ny}
		corner_cache[key] = p
		return p


class DF:
	var id := 0
	var k := 0
	var a: DF
	var b: DF
	var c: DF
	var v0 := 0.0
	var v1 := 0.0
	var v2 := 0.0
	var v3 := 0.0
	var is2d := false
	var noise: MCNoise.Normal
	var blended: MCNoise.Blended
	var axis := 1
	var cxz := 4
	var cy := 8
	var spline: Dictionary = {}
	var funcs: Array = []
	var thresholds := PackedFloat64Array()
	var lower := 0
	var name := ""
	var lo := -INF     # static bounds (Java minValue/maxValue) used to skip operands exactly
	var hi := INF
	var end_noise: MCNoise.Simplex
	var _end_cache: Dictionary = {}   # Vector2i(x/8, z/8) -> value (DF graphs are per worker thread)

	# ------------------------------------------------------------ batch
	func batch(ctx: Ctx, pts: Pts) -> PackedFloat64Array:
		if k == K.CONST:
			var o := PackedFloat64Array()
			o.resize(pts.n)
			o.fill(v0)
			return o
		if is2d and pts != pts.root.cols:
			var cv := batch(ctx, pts.root.cols)
			var o2 := PackedFloat64Array()
			o2.resize(pts.n)
			var co := pts.root.col_of
			if pts.is_root():
				for i in pts.n:
					o2[i] = cv[co[i]]
			else:
				var ri := pts.ridx
				for i in pts.n:
					o2[i] = cv[co[ri[i]]]
			return o2
		if ctx.memo_id[id] == pts.id:
			return ctx.memo_val[id]
		if ctx.memo2_id[id] == pts.id:
			return ctx.memo2_val[id]
		if not pts.is_root() and ctx.memo2_id[id] != 0:
			# value cached on an ancestor sub-batch? gather through its inverse index map
			var anc := pts.parent
			while anc != null and not anc.is_root():
				if anc.id == ctx.memo2_id[id]:
					if anc.inv.is_empty():
						anc.inv.resize(anc.root.n)
						anc.inv.fill(-1)
						for t in anc.n:
							anc.inv[anc.ridx[t]] = t
					var av: PackedFloat64Array = ctx.memo2_val[id]
					var og := PackedFloat64Array()
					og.resize(pts.n)
					var rr := pts.ridx
					var ai := anc.inv
					for i in pts.n:
						og[i] = av[ai[rr[i]]]
					return og
				anc = anc.parent
		if not pts.is_root() and ctx.memo_id[id] == pts.root.id:
			var rv: PackedFloat64Array = ctx.memo_val[id]
			var o3 := PackedFloat64Array()
			o3.resize(pts.n)
			var ri2 := pts.ridx
			for i in pts.n:
				o3[i] = rv[ri2[i]]
			return o3
		var tp := Time.get_ticks_usec() if not ctx.prof.is_empty() or ctx.prof.has(-1) else 0
		var r := _compute(ctx, pts)
		if tp != 0:
			var e = ctx.prof.get(id, [0, 0, 0])
			e[0] += Time.get_ticks_usec() - tp
			e[1] += 1
			e[2] += pts.n
			ctx.prof[id] = e
		if pts.is_root():
			ctx.memo_id[id] = pts.id
			ctx.memo_val[id] = r
		else:
			ctx.memo2_id[id] = pts.id
			ctx.memo2_val[id] = r
		return r

	func _compute(ctx: Ctx, pts: Pts) -> PackedFloat64Array:
		var n := pts.n
		var o := PackedFloat64Array()
		o.resize(n)
		match k:
			K.MIN, K.MAX, K.MUL:
				var xa := a.batch(ctx, pts)
				if not pts.cells.is_empty():
					# cell-major block batches: operands are cheap interpolations; keep the fast layout
					var yf := b.batch(ctx, pts)
					for i in n:
						o[i] = minf(xa[i], yf[i]) if k == K.MIN else (maxf(xa[i], yf[i]) if k == K.MAX else xa[i] * yf[i])
					return o
				var need := PackedInt32Array()
				for i in n:
					var va := xa[i]
					if k == K.MIN:
						if va < b.lo:
							o[i] = va
						else:
							need.append(i)
					elif k == K.MAX:
						if va > b.hi:
							o[i] = va
						else:
							need.append(i)
					else:
						if va == 0.0:
							o[i] = 0.0
						else:
							need.append(i)
				if need.is_empty():
					return o
				var yb: PackedFloat64Array
				if need.size() == n:
					yb = b.batch(ctx, pts)
					if k == K.MIN:
						for i in n:
							o[i] = minf(xa[i], yb[i])
					elif k == K.MAX:
						for i in n:
							o[i] = maxf(xa[i], yb[i])
					else:
						for i in n:
							o[i] = xa[i] * yb[i]
					return o
				yb = b.batch(ctx, ctx.sub(pts, need))
				for t in need.size():
					var i := need[t]
					if k == K.MIN:
						o[i] = minf(xa[i], yb[t])
					elif k == K.MAX:
						o[i] = maxf(xa[i], yb[t])
					else:
						o[i] = xa[i] * yb[t]
			K.ADD, K.SUB, K.DIV:
				var x := a.batch(ctx, pts)
				var y := b.batch(ctx, pts)
				if k == K.ADD:
					for i in n:
						o[i] = x[i] + y[i]
				elif k == K.MUL:
					for i in n:
						o[i] = x[i] * y[i]
				elif k == K.SUB:
					for i in n:
						o[i] = x[i] - y[i]
				elif k == K.DIV:
					for i in n:
						o[i] = x[i] / y[i] if y[i] != 0.0 else 0.0
				elif k == K.MIN:
					for i in n:
						o[i] = minf(x[i], y[i])
				else:
					for i in n:
						o[i] = maxf(x[i], y[i])
			K.ABS, K.SQUARE, K.CUBE, K.HALF_NEG, K.QUARTER_NEG, K.SQUEEZE, K.NEGATE, K.CLAMP, K.PASS:
				var x2 := a.batch(ctx, pts)
				match k:
					K.ABS:
						for i in n:
							o[i] = absf(x2[i])
					K.SQUARE:
						for i in n:
							o[i] = x2[i] * x2[i]
					K.CUBE:
						for i in n:
							o[i] = x2[i] * x2[i] * x2[i]
					K.HALF_NEG:
						for i in n:
							o[i] = x2[i] if x2[i] > 0.0 else x2[i] * 0.5
					K.QUARTER_NEG:
						for i in n:
							o[i] = x2[i] if x2[i] > 0.0 else x2[i] * 0.25
					K.SQUEEZE:
						for i in n:
							var e := clampf(x2[i], -1.0, 1.0)
							o[i] = e / 2.0 - e * e * e / 24.0
					K.NEGATE:
						for i in n:
							o[i] = -x2[i]
					K.CLAMP:
						for i in n:
							o[i] = clampf(x2[i], v0, v1)
					_:
						return x2
			K.ONE:
				o.fill(1.0)
			K.ZERO:
				pass
			K.GRADIENT:
				ctx.ensure_coords(pts)
				var arr := pts.ys if axis == 1 else (pts.xs if axis == 0 else pts.zs)
				for i in n:
					o[i] = _gradient(arr[i])
			K.LERP:
				var al := a.batch(ctx, pts)
				var need1 := PackedInt32Array()
				var need2 := PackedInt32Array()
				for i in n:
					if al[i] != 1.0:
						need1.append(i)
					if al[i] != 0.0:
						need2.append(i)
				var f1 := PackedFloat64Array()
				var f2 := PackedFloat64Array()
				f1.resize(n)
				f2.resize(n)
				if need1.size() == n:
					f1 = b.batch(ctx, pts)
				elif not need1.is_empty():
					var r1v := b.batch(ctx, ctx.sub(pts, need1))
					for t in need1.size():
						f1[need1[t]] = r1v[t]
				if need2.size() == n:
					f2 = c.batch(ctx, pts)
				elif not need2.is_empty():
					var r2v := c.batch(ctx, ctx.sub(pts, need2))
					for t in need2.size():
						f2[need2[t]] = r2v[t]
				for i in n:
					var av := al[i]
					if av == 0.0:
						o[i] = f1[i]
					elif av == 1.0:
						o[i] = f2[i]
					else:
						o[i] = f1[i] + av * (f2[i] - f1[i])
			K.RANGE:
				var inp := a.batch(ctx, pts)
				if not pts.cells.is_empty():
					var rb := b.batch(ctx, pts)
					var rc := c.batch(ctx, pts)
					for i in n:
						o[i] = rb[i] if (inp[i] >= v0 and inp[i] < v1) else rc[i]
					return o
				var ins := PackedInt32Array()
				var outs := PackedInt32Array()
				for i in n:
					if inp[i] >= v0 and inp[i] < v1:
						ins.append(i)
					else:
						outs.append(i)
				if outs.is_empty():
					return b.batch(ctx, pts)
				if ins.is_empty():
					return c.batch(ctx, pts)
				var s1 := ctx.sub(pts, ins)
				var r1 := b.batch(ctx, s1)
				for i in ins.size():
					o[ins[i]] = r1[i]
				var s2 := ctx.sub(pts, outs)
				var r2 := c.batch(ctx, s2)
				for i in outs.size():
					o[outs[i]] = r2[i]
			K.INTERVAL:
				var inp2 := a.batch(ctx, pts)
				var groups: Array = []
				for f in funcs:
					groups.append(PackedInt32Array())
				var tn := thresholds.size()
				for i in n:
					var gi := 0
					while gi < tn and inp2[i] >= thresholds[gi]:
						gi += 1
					var ga: PackedInt32Array = groups[gi]
					ga.append(i)
				for gi in groups.size():
					var g: PackedInt32Array = groups[gi]
					if g.is_empty():
						continue
					if g.size() == n:
						return (funcs[gi] as DF).batch(ctx, pts)
					var sp := ctx.sub(pts, g)
					var rr := (funcs[gi] as DF).batch(ctx, sp)
					for i in g.size():
						o[g[i]] = rr[i]
			K.NOISE, K.SHIFT_A, K.SHIFT_B, K.SHIFT:
				var sx := PackedFloat64Array()
				var sz := PackedFloat64Array()
				var sy := PackedFloat64Array()
				var has_shift := a != null
				if has_shift:
					sx = a.batch(ctx, pts)
					sz = c.batch(ctx, pts) if c != null else PackedFloat64Array()
					sy = b.batch(ctx, pts) if b != null else PackedFloat64Array()
				ctx.ensure_coords(pts)
				var nz := noise
				for i in n:
					var x3 := float(pts.xs[i])
					var y3 := float(pts.ys[i])
					var z3 := float(pts.zs[i])
					match k:
						K.NOISE:
							var px := x3 * v0
							var py := y3 * v1
							var pz := z3 * v0
							if has_shift:
								px += sx[i]
								if sy.size() > 0:
									py += sy[i]
								if sz.size() > 0:
									pz += sz[i]
							o[i] = nz.value(px, py, pz)
						K.SHIFT_A:
							o[i] = nz.value(x3 * 0.25, 0.0, z3 * 0.25) * 4.0
						K.SHIFT_B:
							o[i] = nz.value(z3 * 0.25, x3 * 0.25, 0.0) * 4.0
						_:
							o[i] = nz.value(x3 * 0.25, y3 * 0.25, z3 * 0.25) * 4.0
			K.BLENDED:
				ctx.ensure_coords(pts)
				for i in n:
					o[i] = blended.value(pts.xs[i], pts.ys[i], pts.zs[i])
			K.INTERP:
				return _interp_batch(ctx, pts)
			K.SPLINE:
				var coords := {}
				_collect_coords(ctx, pts, spline, coords)
				for i in n:
					o[i] = _spline_eval(spline, coords, i)
			K.TOP_SURFACE:
				ctx.ensure_coords(pts)
				for i in n:
					o[i] = point(ctx, pts.xs[i], 0, pts.zs[i])
			K.END_ISLANDS, K.DIST:
				ctx.ensure_coords(pts)
				for i in n:
					o[i] = point(ctx, pts.xs[i], pts.ys[i], pts.zs[i])
		return o

	func _end_islands(x: int, z: int) -> float:
		var key := Vector2i(x / 8, z / 8)
		var c = _end_cache.get(key)
		if c != null:
			return c
		var v := (MCNoise.end_height(end_noise, key.x, key.y) - 8.0) / 128.0
		if _end_cache.size() > 65536:
			_end_cache.clear()
		_end_cache[key] = v
		return v

	func _gradient(t: int) -> float:
		if v0 == v1:
			return v2
		var f := clampf((float(t) - v0) / (v1 - v0), 0.0, 1.0)
		return v2 + f * (v3 - v2)

	## Interpolated: trilinear over the chunk's corner grid when evaluated on chunk blocks (or any point set
	## lying inside the current chunk), direct input evaluation otherwise (Java NoiseChunk semantics).
	func _interp_batch(ctx: Ctx, pts: Pts) -> PackedFloat64Array:
		if pts.root.kind == 1 and pts.root.grid.get("cxz", 0) == cxz and pts.root.grid.get("cy", 0) == cy:
			return a.batch(ctx, pts)
		if not ctx.has_chunk:
			return a.batch(ctx, pts)
		var cp := ctx.corners(cxz, cy)
		var cv := a.batch(ctx, cp)
		var nx: int = cp.grid["nx"]
		var o := PackedFloat64Array()
		o.resize(pts.n)
		if not pts.cells.is_empty() and cxz == 4 and cy == 8:
			return _interp_cells(cv, nx, pts)
		if pts.is_root() and pts.kind == 2:
			# fast path: full chunk column in YZX order
			var fx := 1.0 / cxz
			var fyc := 1.0 / cy
			var layer := nx * nx
			for ly in Coords.HEIGHT:
				var iy := ly / cy
				var ty := (ly % cy) * fyc
				var b0 := iy * layer
				var b1 := b0 + layer
				var base := ly << 8
				for lz in 16:
					var iz := lz / cxz
					var tz := (lz % cxz) * fx
					for ix in 16 / cxz:
						var i00 := b0 + iz * nx + ix
						var i01 := b0 + (iz + 1) * nx + ix
						var i10 := b1 + iz * nx + ix
						var i11 := b1 + (iz + 1) * nx + ix
						var c000 := cv[i00]
						var c100 := cv[i00 + 1]
						var c001 := cv[i01]
						var c101 := cv[i01 + 1]
						var c010 := cv[i10]
						var c110 := cv[i10 + 1]
						var c011 := cv[i11]
						var c111 := cv[i11 + 1]
						var y00 := c000 + ty * (c010 - c000)
						var y10 := c100 + ty * (c110 - c100)
						var y01 := c001 + ty * (c011 - c001)
						var y11 := c101 + ty * (c111 - c101)
						var zz0 := y00 + tz * (y01 - y00)
						var zz1 := y10 + tz * (y11 - y10)
						var row := base | (lz << 4) | (ix * cxz)
						for sx in cxz:
							o[row + sx] = zz0 + (sx * fx) * (zz1 - zz0)
			return o
		if pts.root.kind == 2 and cxz == 4 and cy == 8:
			# points inside the current chunk given by block index: inline trilinear (no calls)
			var ri := pts.ridx
			var layer2 := nx * nx
			for i in pts.n:
				var bi := ri[i]
				var lx := bi & 15
				var lz := (bi >> 4) & 15
				var ly := bi >> 8
				var b0 := (ly >> 3) * layer2 + (lz >> 2) * nx + (lx >> 2)
				var b1 := b0 + layer2
				var tx := (lx & 3) * 0.25
				var tz := (lz & 3) * 0.25
				var ty := (ly & 7) * 0.125
				var x00 := cv[b0] + tx * (cv[b0 + 1] - cv[b0])
				var x10 := cv[b1] + tx * (cv[b1 + 1] - cv[b1])
				var x01 := cv[b0 + nx] + tx * (cv[b0 + nx + 1] - cv[b0 + nx])
				var x11 := cv[b1 + nx] + tx * (cv[b1 + nx + 1] - cv[b1 + nx])
				var y0 := x00 + ty * (x10 - x00)
				var y1 := x01 + ty * (x11 - x01)
				o[i] = y0 + tz * (y1 - y0)
			return o
		ctx.ensure_coords(pts)
		for i in pts.n:
			o[i] = _interp_at(ctx, cp, cv, nx, pts.xs[i], pts.ys[i], pts.zs[i])
		return o

	## Cell-major sub-batch: cells listed in pts.cells, 128 blocks per cell ordered (ly, lz, lx).
	func _interp_cells(cv: PackedFloat64Array, nx: int, pts: Pts) -> PackedFloat64Array:
		var o := PackedFloat64Array()
		o.resize(pts.n)
		var layer := nx * nx
		var w := 0
		for cell in pts.cells:
			var ix := cell & 3
			var iz := (cell >> 2) & 3
			var iy := cell >> 4
			var b0 := iy * layer + iz * nx + ix
			var b1 := b0 + layer
			var c000 := cv[b0]
			var c100 := cv[b0 + 1]
			var c001 := cv[b0 + nx]
			var c101 := cv[b0 + nx + 1]
			var c010 := cv[b1]
			var c110 := cv[b1 + 1]
			var c011 := cv[b1 + nx]
			var c111 := cv[b1 + nx + 1]
			for ly in 8:
				var ty := ly * 0.125
				var y00 := c000 + ty * (c010 - c000)
				var y10 := c100 + ty * (c110 - c100)
				var y01 := c001 + ty * (c011 - c001)
				var y11 := c101 + ty * (c111 - c101)
				for lz in 4:
					var tz := lz * 0.25
					var z0 := y00 + tz * (y01 - y00)
					var z1 := y10 + tz * (y11 - y10)
					var dz := z1 - z0
					o[w] = z0
					o[w + 1] = z0 + 0.25 * dz
					o[w + 2] = z0 + 0.5 * dz
					o[w + 3] = z0 + 0.75 * dz
					w += 4
		return o

	## Interval bound of this node over one 4x8x4 cell (corner min/max for interpolated inputs).
	func interval(ctx: Ctx, cv_cache: Dictionary, cell: int) -> Vector2:
		match k:
			K.CONST:
				return Vector2(v0, v0)
			K.ONE:
				return Vector2(1, 1)
			K.ZERO:
				return Vector2(0, 0)
			K.PASS:
				return a.interval(ctx, cv_cache, cell)
			K.INTERP:
				if cxz != 4 or cy != 8:
					return Vector2(-INF, INF)
				var bounds: Array
				if cv_cache.has(id):
					bounds = cv_cache[id]
				else:
					bounds = _cell_bounds(a.batch(ctx, ctx.corners(cxz, cy)))
					cv_cache[id] = bounds
				return Vector2((bounds[0] as PackedFloat64Array)[cell], (bounds[1] as PackedFloat64Array)[cell])
			K.ADD, K.SUB, K.MUL, K.MIN, K.MAX:
				var x := a.interval(ctx, cv_cache, cell)
				var y := b.interval(ctx, cv_cache, cell)
				match k:
					K.ADD:
						return Vector2(x.x + y.x, x.y + y.y)
					K.SUB:
						return Vector2(x.x - y.y, x.y - y.x)
					K.MIN:
						return Vector2(minf(x.x, y.x), minf(x.y, y.y))
					K.MAX:
						return Vector2(maxf(x.x, y.x), maxf(x.y, y.y))
					_:
						if is_inf(x.x) or is_inf(x.y) or is_inf(y.x) or is_inf(y.y):
							return Vector2(-INF, INF)
						var p1 := x.x * y.x
						var p2 := x.x * y.y
						var p3 := x.y * y.x
						var p4 := x.y * y.y
						return Vector2(minf(minf(p1, p2), minf(p3, p4)), maxf(maxf(p1, p2), maxf(p3, p4)))
			K.ABS:
				var x2 := a.interval(ctx, cv_cache, cell)
				if x2.x >= 0.0:
					return x2
				if x2.y <= 0.0:
					return Vector2(-x2.y, -x2.x)
				return Vector2(0.0, maxf(-x2.x, x2.y))
			K.SQUEEZE, K.CLAMP, K.HALF_NEG, K.QUARTER_NEG, K.CUBE:
				var x3 := a.interval(ctx, cv_cache, cell)
				return Vector2(_mono(x3.x), _mono(x3.y))
			K.SQUARE:
				var x4 := a.interval(ctx, cv_cache, cell)
				var lo := 0.0 if (x4.x <= 0.0 and x4.y >= 0.0) else minf(x4.x * x4.x, x4.y * x4.y)
				return Vector2(lo, maxf(x4.x * x4.x, x4.y * x4.y))
			K.NEGATE:
				var x5 := a.interval(ctx, cv_cache, cell)
				return Vector2(-x5.y, -x5.x)
			K.RANGE:
				var iv := a.interval(ctx, cv_cache, cell)
				if iv.x >= v0 and iv.y < v1:
					return b.interval(ctx, cv_cache, cell)
				if iv.y < v0 or iv.x >= v1:
					return c.interval(ctx, cv_cache, cell)
				var r1 := b.interval(ctx, cv_cache, cell)
				var r2 := c.interval(ctx, cv_cache, cell)
				return Vector2(minf(r1.x, r2.x), maxf(r1.y, r2.y))
		return Vector2(-INF, INF)

	## Vectorised interval bounds over all 768 cells: returns [lo, hi] PackedFloat64Array(768); memo in cache.
	func interval_all(ctx: Ctx, cache: Dictionary) -> Array:
		var key := -1 - id
		if cache.has(key):
			return cache[key]
		var lo := PackedFloat64Array()
		var hi := PackedFloat64Array()
		lo.resize(768)
		hi.resize(768)
		match k:
			K.CONST, K.ONE, K.ZERO:
				var v := 1.0 if k == K.ONE else (v0 if k == K.CONST else 0.0)
				lo.fill(v)
				hi.fill(v)
			K.PASS:
				return a.interval_all(ctx, cache)
			K.INTERP:
				if cxz != 4 or cy != 8:
					lo.fill(-INF)
					hi.fill(INF)
				else:
					var bb := _cell_bounds(a.batch(ctx, ctx.corners(cxz, cy)))
					lo = bb[0]
					hi = bb[1]
			K.ADD, K.SUB, K.MUL, K.MIN, K.MAX:
				var x: Array = a.interval_all(ctx, cache)
				var y: Array = b.interval_all(ctx, cache)
				var xl: PackedFloat64Array = x[0]
				var xh: PackedFloat64Array = x[1]
				var yl: PackedFloat64Array = y[0]
				var yh: PackedFloat64Array = y[1]
				for i in 768:
					match k:
						K.ADD:
							lo[i] = xl[i] + yl[i]
							hi[i] = xh[i] + yh[i]
						K.SUB:
							lo[i] = xl[i] - yh[i]
							hi[i] = xh[i] - yl[i]
						K.MIN:
							lo[i] = minf(xl[i], yl[i])
							hi[i] = minf(xh[i], yh[i])
						K.MAX:
							lo[i] = maxf(xl[i], yl[i])
							hi[i] = maxf(xh[i], yh[i])
						_:
							if is_inf(xl[i]) or is_inf(xh[i]) or is_inf(yl[i]) or is_inf(yh[i]):
								lo[i] = -INF
								hi[i] = INF
							else:
								var p1 := xl[i] * yl[i]
								var p2 := xl[i] * yh[i]
								var p3 := xh[i] * yl[i]
								var p4 := xh[i] * yh[i]
								lo[i] = minf(minf(p1, p2), minf(p3, p4))
								hi[i] = maxf(maxf(p1, p2), maxf(p3, p4))
			K.ABS, K.SQUEEZE, K.CLAMP, K.HALF_NEG, K.QUARTER_NEG, K.CUBE, K.SQUARE, K.NEGATE:
				var x2: Array = a.interval_all(ctx, cache)
				var al: PackedFloat64Array = x2[0]
				var ah: PackedFloat64Array = x2[1]
				for i in 768:
					var l := al[i]
					var h := ah[i]
					match k:
						K.ABS:
							if l >= 0.0:
								lo[i] = l
								hi[i] = h
							elif h <= 0.0:
								lo[i] = -h
								hi[i] = -l
							else:
								lo[i] = 0.0
								hi[i] = maxf(-l, h)
						K.SQUARE:
							lo[i] = 0.0 if (l <= 0.0 and h >= 0.0) else minf(l * l, h * h)
							hi[i] = maxf(l * l, h * h)
						K.NEGATE:
							lo[i] = -h
							hi[i] = -l
						_:
							lo[i] = _mono(l)
							hi[i] = _mono(h)
			K.GRADIENT:
				if axis != 1:
					lo.fill(self.lo)
					hi.fill(self.hi)
				else:
					for cell in 768:
						var gy0 := -64 + (cell >> 4) * 8
						var g1 := _gradient(gy0)
						var g2 := _gradient(gy0 + 7)
						lo[cell] = minf(g1, g2)
						hi[cell] = maxf(g1, g2)
			K.RANGE:
				var iv: Array = a.interval_all(ctx, cache)
				var rb: Array = b.interval_all(ctx, cache)
				var rc: Array = c.interval_all(ctx, cache)
				var il: PackedFloat64Array = iv[0]
				var ih: PackedFloat64Array = iv[1]
				for i in 768:
					if il[i] >= v0 and ih[i] < v1:
						lo[i] = rb[0][i]
						hi[i] = rb[1][i]
					elif ih[i] < v0 or il[i] >= v1:
						lo[i] = rc[0][i]
						hi[i] = rc[1][i]
					else:
						lo[i] = minf(rb[0][i], rc[0][i])
						hi[i] = maxf(rb[1][i], rc[1][i])
			_:
				# static Java-style min/max bounds are always valid (conservative) cell bounds
				lo.fill(self.lo)
				hi.fill(self.hi)
		var res := [lo, hi]
		cache[key] = res
		return res

	static func _cell_bounds(cv: PackedFloat64Array) -> Array:
		var lo := PackedFloat64Array()
		var hi := PackedFloat64Array()
		lo.resize(768)
		hi.resize(768)
		for cell in 768:
			var b0 := (cell >> 4) * 25 + ((cell >> 2) & 3) * 5 + (cell & 3)
			var a0 := cv[b0]
			var a1 := cv[b0 + 1]
			var a2 := cv[b0 + 5]
			var a3 := cv[b0 + 6]
			var a4 := cv[b0 + 25]
			var a5 := cv[b0 + 26]
			var a6 := cv[b0 + 30]
			var a7 := cv[b0 + 31]
			lo[cell] = minf(minf(minf(a0, a1), minf(a2, a3)), minf(minf(a4, a5), minf(a6, a7)))
			hi[cell] = maxf(maxf(maxf(a0, a1), maxf(a2, a3)), maxf(maxf(a4, a5), maxf(a6, a7)))
		return [lo, hi]

	func _mono(x: float) -> float:
		match k:
			K.SQUEEZE:
				var e := clampf(x, -1.0, 1.0)
				return e / 2.0 - e * e * e / 24.0
			K.CLAMP:
				return clampf(x, v0, v1)
			K.HALF_NEG:
				return x if x > 0.0 else x * 0.5
			K.QUARTER_NEG:
				return x if x > 0.0 else x * 0.25
			K.CUBE:
				return x * x * x
		return x

	func _interp_at(ctx: Ctx, cp: Pts, cv: PackedFloat64Array, nx: int, x: int, y: int, z: int) -> float:
		var lx := x - ctx.x0
		var lz := z - ctx.z0
		var ly := y - Coords.MIN_Y
		if lx < 0 or lx > 15 or lz < 0 or lz > 15 or ly < 0 or ly >= Coords.HEIGHT:
			return a.point(ctx, x, y, z)
		var ix := lx / cxz
		var iz := lz / cxz
		var iy := ly / cy
		var tx := float(lx % cxz) / cxz
		var tz := float(lz % cxz) / cxz
		var ty := float(ly % cy) / cy
		var layer := nx * nx
		var b0 := iy * layer
		var b1 := b0 + layer
		var c000 := cv[b0 + iz * nx + ix]
		var c100 := cv[b0 + iz * nx + ix + 1]
		var c001 := cv[b0 + (iz + 1) * nx + ix]
		var c101 := cv[b0 + (iz + 1) * nx + ix + 1]
		var c010 := cv[b1 + iz * nx + ix]
		var c110 := cv[b1 + iz * nx + ix + 1]
		var c011 := cv[b1 + (iz + 1) * nx + ix]
		var c111 := cv[b1 + (iz + 1) * nx + ix + 1]
		var x00 := c000 + tx * (c100 - c000)
		var x10 := c010 + tx * (c110 - c010)
		var x01 := c001 + tx * (c101 - c001)
		var x11 := c011 + tx * (c111 - c011)
		var y0 := x00 + ty * (x10 - x00)
		var y1 := x01 + ty * (x11 - x01)
		return y0 + tz * (y1 - y0)

	# ------------------------------------------------------------ point
	func point(ctx: Ctx, x: int, y: int, z: int) -> float:
		if is2d and k != K.CONST:
			var key := Vector4i(id, x, 0, z)
			var cached = ctx.point_cache.get(key)
			if cached != null:
				return cached
			var r := _point(ctx, x, y, z)
			ctx.point_cache[key] = r
			return r
		return _point(ctx, x, y, z)

	func _point(ctx: Ctx, x: int, y: int, z: int) -> float:
		match k:
			K.CONST:
				return v0
			K.ADD:
				return a.point(ctx, x, y, z) + b.point(ctx, x, y, z)
			K.MUL:
				var l := a.point(ctx, x, y, z)
				return 0.0 if l == 0.0 else l * b.point(ctx, x, y, z)
			K.SUB:
				return a.point(ctx, x, y, z) - b.point(ctx, x, y, z)
			K.DIV:
				var d := b.point(ctx, x, y, z)
				return a.point(ctx, x, y, z) / d if d != 0.0 else 0.0
			K.MIN:
				var m1 := a.point(ctx, x, y, z)
				return m1 if m1 < b.lo else minf(m1, b.point(ctx, x, y, z))
			K.MAX:
				var m2 := a.point(ctx, x, y, z)
				return m2 if m2 > b.hi else maxf(m2, b.point(ctx, x, y, z))
			K.ABS:
				return absf(a.point(ctx, x, y, z))
			K.SQUARE:
				var s := a.point(ctx, x, y, z)
				return s * s
			K.CUBE:
				var s2 := a.point(ctx, x, y, z)
				return s2 * s2 * s2
			K.HALF_NEG:
				var h := a.point(ctx, x, y, z)
				return h if h > 0.0 else h * 0.5
			K.QUARTER_NEG:
				var q := a.point(ctx, x, y, z)
				return q if q > 0.0 else q * 0.25
			K.SQUEEZE:
				var e := clampf(a.point(ctx, x, y, z), -1.0, 1.0)
				return e / 2.0 - e * e * e / 24.0
			K.NEGATE:
				return -a.point(ctx, x, y, z)
			K.CLAMP:
				return clampf(a.point(ctx, x, y, z), v0, v1)
			K.PASS:
				return a.point(ctx, x, y, z)
			K.ONE:
				return 1.0
			K.ZERO:
				return 0.0
			K.GRADIENT:
				return _gradient(y if axis == 1 else (x if axis == 0 else z))
			K.LERP:
				var al := a.point(ctx, x, y, z)
				if al == 0.0:
					return b.point(ctx, x, y, z)
				if al == 1.0:
					return c.point(ctx, x, y, z)
				var f1 := b.point(ctx, x, y, z)
				return f1 + al * (c.point(ctx, x, y, z) - f1)
			K.RANGE:
				var iv := a.point(ctx, x, y, z)
				return b.point(ctx, x, y, z) if iv >= v0 and iv < v1 else c.point(ctx, x, y, z)
			K.INTERVAL:
				var iv2 := a.point(ctx, x, y, z)
				var gi := 0
				while gi < thresholds.size() and iv2 >= thresholds[gi]:
					gi += 1
				return (funcs[gi] as DF).point(ctx, x, y, z)
			K.NOISE:
				var px := x * v0
				var py := y * v1
				var pz := z * v0
				if a != null:
					px += a.point(ctx, x, y, z)
					if b != null:
						py += b.point(ctx, x, y, z)
					if c != null:
						pz += c.point(ctx, x, y, z)
				return noise.value(px, py, pz)
			K.SHIFT_A:
				return noise.value(x * 0.25, 0.0, z * 0.25) * 4.0
			K.SHIFT_B:
				return noise.value(z * 0.25, x * 0.25, 0.0) * 4.0
			K.SHIFT:
				return noise.value(x * 0.25, y * 0.25, z * 0.25) * 4.0
			K.BLENDED:
				return blended.value(x, y, z)
			K.INTERP:
				if ctx.has_chunk:
					var cp := ctx.corners(cxz, cy)
					var cv := a.batch(ctx, cp)
					return _interp_at(ctx, cp, cv, cp.grid["nx"], x, y, z)
				return a.point(ctx, x, y, z)
			K.SPLINE:
				return _spline_point(ctx, spline, x, y, z)
			K.TOP_SURFACE:
				var top := floori(c.point(ctx, x, 0, z))
				var yy := floori(float(top) / v0) * int(v0)
				var res := float(lower)
				while yy >= lower:
					if a.point(ctx, x, yy, z) > 0.0:
						res = float(yy)
						break
					yy -= int(v0)
				return res
			K.END_ISLANDS:
				return _end_islands(x, z)
			K.DIST:
				return Vector3(x - v0, y - v1, z - v2).length()
		return 0.0

	# ------------------------------------------------------------ splines
	func _collect_coords(ctx: Ctx, pts: Pts, sp: Dictionary, out: Dictionary) -> void:
		var cdf: DF = sp["coord"]
		if not out.has(cdf.id):
			out[cdf.id] = cdf.batch(ctx, pts)
		for v in sp["values"]:
			if v is Dictionary:
				_collect_coords(ctx, pts, v, out)

	func _spline_eval(sp: Dictionary, coords: Dictionary, i: int) -> float:
		var f: float = (coords[(sp["coord"] as DF).id] as PackedFloat64Array)[i]
		return _spline_core(sp, f, func(v): return _spline_eval(v, coords, i) if v is Dictionary else float(v))

	func _spline_point(ctx: Ctx, sp: Dictionary, x: int, y: int, z: int) -> float:
		var f := (sp["coord"] as DF).point(ctx, x, y, z)
		return _spline_core(sp, f, func(v): return _spline_point(ctx, v, x, y, z) if v is Dictionary else float(v))

	## Java CubicSpline.Multipoint.apply (float math emulated in double).
	func _spline_core(sp: Dictionary, f: float, valfn: Callable) -> float:
		var locs: PackedFloat64Array = sp["locs"]
		var ders: PackedFloat64Array = sp["ders"]
		var vals: Array = sp["values"]
		var last := locs.size() - 1
		var i := -1
		var lo := 0
		var hi := locs.size()
		while lo < hi:
			var mid := (lo + hi) >> 1
			if f < locs[mid]:
				hi = mid
			else:
				lo = mid + 1
		i = lo - 1
		if i < 0:
			var v0s: float = valfn.call(vals[0])
			return v0s if ders[0] == 0.0 else v0s + ders[0] * (f - locs[0])
		if i == last:
			var vl: float = valfn.call(vals[last])
			return vl if ders[last] == 0.0 else vl + ders[last] * (f - locs[last])
		var g := locs[i]
		var h := locs[i + 1]
		var kk := (f - g) / (h - g)
		var m: float = valfn.call(vals[i])
		var nn: float = valfn.call(vals[i + 1])
		var o := ders[i]
		var p := ders[i + 1]
		var q := o * (h - g) - (nn - m)
		var r := -p * (h - g) + (nn - m)
		return (m + kk * (nn - m)) + kk * (1.0 - kk) * (q + kk * (r - q))


class DFCompiler:
	var seed := 0
	var source: Callable          # path -> parsed json
	var rand   # RandomSources.XoroPositional, or LegacyPositional when legacy_random_source
	var legacy := false
	var named: Dictionary = {}
	var noises: Dictionary = {}
	var nodes: Array = []
	var prefix := "data/minecraft/worldgen/"

	func _init(p_seed: int, src: Callable, p_legacy := false) -> void:
		seed = p_seed
		source = src
		legacy = p_legacy
		rand = RandomSources.root_positional(seed, legacy)

	func node_count() -> int:
		return nodes.size()

	## Flattened graph for the native engine (RecraftNative.df_graph, native/src/density.cpp):
	## [node ints (15/node), node floats (6/node), interval funcs, interval thresholds (same offsets), noises,
	##  blended noises, splines, end simplex permutations]. -1 = no reference.
	func export_native() -> Array:
		var ni := PackedInt32Array()
		var nf := PackedFloat64Array()
		var funcs := PackedInt32Array()
		var thr := PackedFloat64Array()
		var noise_ids := {}
		var noise_list: Array = []
		var bl_ids := {}
		var bl_list: Array = []
		var sp_ids := {}
		var sp_list: Array = []
		var end_ids := {}
		var end_list: Array = []
		for d in nodes:
			var df: DF = d
			var nid := -1
			if df.noise != null:
				var key := df.noise.get_instance_id()
				if not noise_ids.has(key):
					noise_ids[key] = noise_list.size()
					noise_list.append(_export_noise(df.noise))
				nid = noise_ids[key]
			var bid := -1
			if df.blended != null:
				var bkey := df.blended.get_instance_id()
				if not bl_ids.has(bkey):
					bl_ids[bkey] = bl_list.size()
					bl_list.append(_export_blended(df.blended))
				bid = bl_ids[bkey]
			var sid := -1
			if df.k == K.SPLINE:
				sid = _export_spline(df.spline, sp_ids, sp_list)
			var eid := -1
			if df.end_noise != null:
				var ekey := df.end_noise.get_instance_id()
				if not end_ids.has(ekey):
					end_ids[ekey] = end_list.size()
					end_list.append(df.end_noise.p.slice(0, 256))
				eid = end_ids[ekey]
			var foff := funcs.size()
			for fi in df.funcs.size():
				funcs.append((df.funcs[fi] as DF).id)
				thr.append(df.thresholds[fi] if fi < df.thresholds.size() else 0.0)
			ni.append_array([df.k, df.a.id if df.a != null else -1, df.b.id if df.b != null else -1, df.c.id if df.c != null else -1,
				df.axis, df.cxz, df.cy, 1 if df.is2d else 0, df.lower, nid, bid, sid, foff, df.funcs.size(), eid])
			nf.append_array([df.v0, df.v1, df.v2, df.v3, df.lo, df.hi])
		return [ni, nf, funcs, thr, noise_list, bl_list, sp_list, end_list]

	func _export_noise(n: MCNoise.Normal) -> Array:
		if n.o_n == 0:
			n._flatten()
		var perm := PackedInt32Array()
		for k in n.o_n:
			perm.append_array((n.o_perm[k] as PackedInt32Array).slice(0, 256))
		return [perm, n.o_off, n.o_in, n.o_amp]

	func _export_blended(b: MCNoise.Blended) -> Array:
		var perm := PackedInt32Array()
		var off := PackedFloat64Array()
		var present := PackedInt32Array()
		var octs: Array = b.main_oct + b.min_oct + b.max_oct
		for imp in octs:
			if imp != null:
				perm.append_array((imp as MCNoise.Improved).p.slice(0, 256))
				off.append_array([imp.xo, imp.yo, imp.zo])
				present.append(1)
			else:
				var z := PackedInt32Array()
				z.resize(256)
				perm.append_array(z)
				off.append_array([0.0, 0.0, 0.0])
				present.append(0)
		return [perm, off, present, PackedFloat64Array([b.xz_mul, b.y_mul, b.xz_factor, b.y_factor, b.smear])]

	func _export_spline(sp: Dictionary, ids: Dictionary, out: Array) -> int:
		if ids.has(sp):
			return ids[sp]
		var idx := out.size()
		out.append(null)
		ids[sp] = idx
		var vals := PackedFloat64Array()
		var vs := PackedInt32Array()
		for v in sp["values"]:
			if v is Dictionary:
				vals.append(0.0)
				vs.append(_export_spline(v, ids, out))
			else:
				vals.append(float(v))
				vs.append(-1)
		out[idx] = [(sp["coord"] as DF).id, sp["locs"], sp["ders"], vals, vs]
		return idx

	func _new(kind: int) -> DF:
		var d := DF.new()
		d.k = kind
		d.id = nodes.size()
		nodes.append(d)
		return d

	func noise(name: String) -> MCNoise.Normal:
		var key := name if name.contains(":") else "minecraft:" + name
		if noises.has(key):
			return noises[key]
		var j = source.call(prefix + "noise/" + key.trim_prefix("minecraft:") + ".json")
		if not (j is Dictionary):
			push_warning("missing noise " + key)
			j = {"base_octave": 0}
		var nn := MCNoise.Normal.from_params(rand.from_hash(key), j)
		noises[key] = nn
		return nn

	func get_df(v) -> DF:
		if v is float or v is int:
			var d := _new(K.CONST)
			d.v0 = float(v)
			d.is2d = true
			return d
		if v is String:
			var key: String = v if v.contains(":") else "minecraft:" + v
			if named.has(key):
				return named[key]
			var j = source.call(prefix + "density_function/" + key.trim_prefix("minecraft:") + ".json")
			if j == null:
				push_warning("missing density function " + key)
				var z := _new(K.ZERO)
				z.is2d = true
				named[key] = z
				return z
			var d2 := get_df(j)
			if d2.name == "" or not d2.name.contains(":"):
				d2.name = key
			named[key] = d2
			return d2
		if not (v is Dictionary):
			return get_df(0.0)
		var t := str(v.get("type", "")).trim_prefix("minecraft:")
		var d3: DF
		match t:
			"add", "mul", "sub", "div", "min", "max":
				d3 = _new({"add": K.ADD, "mul": K.MUL, "sub": K.SUB, "div": K.DIV, "min": K.MIN, "max": K.MAX}[t])
				d3.a = get_df(v.get("left", v.get("argument1", 0.0)))
				d3.b = get_df(v.get("right", v.get("argument2", 0.0)))
				d3.is2d = d3.a.is2d and d3.b.is2d
				# constant folding
				if d3.a.k == K.CONST and d3.b.k == K.CONST:
					var c := _new(K.CONST)
					c.is2d = true
					var x: float = d3.a.v0
					var y: float = d3.b.v0
					c.v0 = {K.ADD: x + y, K.MUL: x * y, K.SUB: x - y, K.DIV: x / y if y != 0.0 else 0.0, K.MIN: minf(x, y), K.MAX: maxf(x, y)}[d3.k]
					return c
			"abs", "square", "cube", "half_negative", "quarter_negative", "squeeze", "negate":
				d3 = _new({"abs": K.ABS, "square": K.SQUARE, "cube": K.CUBE, "half_negative": K.HALF_NEG, "quarter_negative": K.QUARTER_NEG, "squeeze": K.SQUEEZE, "negate": K.NEGATE}[t])
				d3.a = get_df(v.get("input", v.get("argument", 0.0)))
				d3.is2d = d3.a.is2d
			"clamp":
				d3 = _new(K.CLAMP)
				d3.a = get_df(v.get("input", 0.0))
				d3.v0 = float(v.get("min", -1e30))
				d3.v1 = float(v.get("max", 1e30))
				d3.is2d = d3.a.is2d
			"cache", "flat_cache", "cache_2d", "cache_once", "cache_all_in_cell", "blend_density", "slice":
				var inner := get_df(v.get("input", v.get("argument", 0.0)))
				return inner
			"blend_alpha":
				d3 = _new(K.ONE)
				d3.is2d = true
			"blend_offset", "beardifier":
				d3 = _new(K.ZERO)
				d3.is2d = true
			"range_choice":
				d3 = _new(K.RANGE)
				d3.a = get_df(v.get("input", 0.0))
				d3.b = get_df(v.get("when_in_range", 0.0))
				d3.c = get_df(v.get("when_out_of_range", 0.0))
				d3.v0 = float(v.get("min_inclusive", -1e30))
				d3.v1 = float(v.get("max_exclusive", 1e30))
				d3.is2d = d3.a.is2d and d3.b.is2d and d3.c.is2d
			"lerp":
				d3 = _new(K.LERP)
				d3.a = get_df(v.get("alpha", 0.0))
				d3.b = get_df(v.get("first", 0.0))
				d3.c = get_df(v.get("second", 0.0))
				d3.is2d = d3.a.is2d and d3.b.is2d and d3.c.is2d
			"gradient", "y_clamped_gradient":
				d3 = _new(K.GRADIENT)
				d3.axis = {"x": 0, "y": 1, "z": 2}.get(str(v.get("axis", "y")), 1)
				d3.v0 = float(v.get("from_coordinate", v.get("from_y", 0)))
				d3.v1 = float(v.get("to_coordinate", v.get("to_y", 1)))
				d3.v2 = float(v.get("from_value", 0.0))
				d3.v3 = float(v.get("to_value", 1.0))
				d3.is2d = false
			"noise", "shifted_noise":
				d3 = _new(K.NOISE)
				d3.noise = noise(str(v.get("noise", "")))
				d3.v0 = float(v.get("xz_scale", 1.0))
				d3.v1 = float(v.get("y_scale", 1.0))
				if v.has("shift_x"):
					d3.a = get_df(v["shift_x"])
				if v.has("shift_y"):
					d3.b = get_df(v["shift_y"])
				if v.has("shift_z"):
					d3.c = get_df(v["shift_z"])
				if d3.a == null and (d3.b != null or d3.c != null):
					d3.a = get_df(0.0)
				d3.is2d = d3.v1 == 0.0 and (d3.a == null or d3.a.is2d) and (d3.b == null or d3.b.is2d) and (d3.c == null or d3.c.is2d)
			"shift_a", "shift_b", "shift":
				d3 = _new({"shift_a": K.SHIFT_A, "shift_b": K.SHIFT_B, "shift": K.SHIFT}[t])
				d3.noise = noise(str(v.get("noise", v.get("argument", ""))))
				d3.is2d = t != "shift"
			"old_blended_noise":
				d3 = _new(K.BLENDED)
				# Java RandomState: legacy sources seed BlendedNoise from LegacyRandomSource(seed) directly
				d3.blended = MCNoise.Blended.create(RandomSources.LegacyRandom.new(seed) if legacy else rand.from_hash("minecraft:terrain"), float(v.get("xz_scale", 0.25)), float(v.get("y_scale", 0.125)), float(v.get("xz_factor", 80.0)), float(v.get("y_factor", 160.0)), float(v.get("smear_scale_multiplier", 8.0)))
			"interpolated":
				d3 = _new(K.INTERP)
				d3.a = get_df(v.get("input", v.get("argument", 0.0)))
				d3.cxz = int(v.get("cell_size_xz", 4))
				d3.cy = int(v.get("cell_size_y", 8))
				d3.is2d = d3.a.is2d
			"spline":
				d3 = _new(K.SPLINE)
				d3.spline = _spline(v.get("spline", {}))
				d3.is2d = _spline_2d(d3.spline)
			"interval_select":
				d3 = _new(K.INTERVAL)
				d3.a = get_df(v.get("input", 0.0))
				d3.is2d = d3.a.is2d
				for f in v.get("functions", []):
					var fd := get_df(f)
					d3.funcs.append(fd)
					d3.is2d = d3.is2d and fd.is2d
				for th in v.get("thresholds", []):
					d3.thresholds.append(float(th))
			"find_top_surface":
				d3 = _new(K.TOP_SURFACE)
				d3.a = get_df(v.get("density", 0.0))
				d3.c = get_df(v.get("upper_bound", 320))
				d3.v0 = float(v.get("cell_height", 8))
				d3.lower = int(v.get("lower_bound", Coords.MIN_Y))
				d3.is2d = true
			"end_islands", "end_outer_islands":
				d3 = _new(K.END_ISLANDS)
				d3.is2d = true
				d3.end_noise = MCNoise.end_simplex(seed)
				d3.lo = -0.84375
				d3.hi = 0.5625
			"distance_to_point":
				d3 = _new(K.DIST)
				var pnt: Array = v.get("point", [0, 0, 0]) if v.get("point") is Array else [0, 0, 0]
				d3.v0 = float(pnt[0])
				d3.v1 = float(pnt[1])
				d3.v2 = float(pnt[2])
			"constant":
				return get_df(float(v.get("argument", 0.0)))
			_:
				push_warning("unsupported density function type " + t)
				d3 = _new(K.ZERO)
				d3.is2d = true
		d3.name = t
		_bounds(d3)
		return d3

	## Conservative static value bounds (Java DensityFunction.minValue/maxValue).
	func _bounds(d: DF) -> void:
		match d.k:
			K.CONST:
				d.lo = d.v0
				d.hi = d.v0
			K.ONE:
				d.lo = 1.0
				d.hi = 1.0
			K.ZERO:
				d.lo = 0.0
				d.hi = 0.0
			K.ADD:
				d.lo = d.a.lo + d.b.lo
				d.hi = d.a.hi + d.b.hi
			K.SUB:
				d.lo = d.a.lo - d.b.hi
				d.hi = d.a.hi - d.b.lo
			K.MUL:
				if is_inf(d.a.lo) or is_inf(d.a.hi) or is_inf(d.b.lo) or is_inf(d.b.hi):
					return
				var p := [d.a.lo * d.b.lo, d.a.lo * d.b.hi, d.a.hi * d.b.lo, d.a.hi * d.b.hi]
				d.lo = p.min()
				d.hi = p.max()
			K.MIN:
				d.lo = minf(d.a.lo, d.b.lo)
				d.hi = minf(d.a.hi, d.b.hi)
			K.MAX:
				d.lo = maxf(d.a.lo, d.b.lo)
				d.hi = maxf(d.a.hi, d.b.hi)
			K.ABS:
				d.lo = maxf(0.0, maxf(d.a.lo, -d.a.hi))
				d.hi = maxf(absf(d.a.lo), absf(d.a.hi))
			K.SQUARE:
				d.lo = 0.0
				d.hi = maxf(d.a.lo * d.a.lo, d.a.hi * d.a.hi)
			K.CUBE:
				d.lo = d.a.lo * d.a.lo * d.a.lo
				d.hi = d.a.hi * d.a.hi * d.a.hi
			K.HALF_NEG:
				d.lo = d.a.lo if d.a.lo > 0.0 else d.a.lo * 0.5
				d.hi = d.a.hi if d.a.hi > 0.0 else d.a.hi * 0.5
			K.QUARTER_NEG:
				d.lo = d.a.lo if d.a.lo > 0.0 else d.a.lo * 0.25
				d.hi = d.a.hi if d.a.hi > 0.0 else d.a.hi * 0.25
			K.SQUEEZE:
				d.lo = -0.5 + 1.0 / 24.0 if d.a.lo <= -1.0 else clampf(d.a.lo, -1, 1) / 2.0 - pow(clampf(d.a.lo, -1, 1), 3) / 24.0
				d.hi = 0.5 - 1.0 / 24.0 if d.a.hi >= 1.0 else clampf(d.a.hi, -1, 1) / 2.0 - pow(clampf(d.a.hi, -1, 1), 3) / 24.0
			K.NEGATE:
				d.lo = -d.a.hi
				d.hi = -d.a.lo
			K.CLAMP:
				d.lo = clampf(d.a.lo, d.v0, d.v1) if not is_inf(d.a.lo) else d.v0
				d.hi = clampf(d.a.hi, d.v0, d.v1) if not is_inf(d.a.hi) else d.v1
			K.RANGE:
				d.lo = minf(d.b.lo, d.c.lo)
				d.hi = maxf(d.b.hi, d.c.hi)
			K.LERP:
				if d.a.lo >= 0.0 and d.a.hi <= 1.0:
					d.lo = minf(d.b.lo, d.c.lo)
					d.hi = maxf(d.b.hi, d.c.hi)
			K.GRADIENT:
				d.lo = minf(d.v2, d.v3)
				d.hi = maxf(d.v2, d.v3)
			K.NOISE:
				d.lo = -d.noise.max_val
				d.hi = d.noise.max_val
			K.SHIFT_A, K.SHIFT_B, K.SHIFT:
				d.lo = -d.noise.max_val * 4.0
				d.hi = d.noise.max_val * 4.0
			K.INTERP:
				d.lo = d.a.lo
				d.hi = d.a.hi
			K.INTERVAL:
				var l := INF
				var h := -INF
				for f in d.funcs:
					l = minf(l, (f as DF).lo)
					h = maxf(h, (f as DF).hi)
				d.lo = l
				d.hi = h

	func _spline(s) -> Dictionary:
		var out := {"coord": get_df(s.get("coordinate", 0.0)), "locs": PackedFloat64Array(), "ders": PackedFloat64Array(), "values": []}
		for p in s.get("points", []):
			out["locs"].append(float(p.get("location", 0.0)))
			out["ders"].append(float(p.get("derivative", 0.0)))
			var val = p.get("value", 0.0)
			out["values"].append(_spline(val) if val is Dictionary else float(val))
		return out

	func _spline_2d(sp: Dictionary) -> bool:
		if not (sp["coord"] as DF).is2d:
			return false
		for v in sp["values"]:
			if v is Dictionary and not _spline_2d(v):
				return false
		return true
