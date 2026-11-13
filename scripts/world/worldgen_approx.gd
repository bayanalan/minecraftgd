## ApproxGenerator — ORIGINAL approximate terrain ("approx_original"), clearly labelled non-vanilla.
## Why: playable fallback when no installed worldgen data exists (placeholder mode). Uses Java-style
## Perlin climate noises but a hand-made height/biome mapping — never claimed as seed parity.
## Contract: WorldGenerator API; pure per (seed, chunk).
class_name ApproxGenerator
extends WorldGenerator

var n_cont: MCNoise.Normal
var n_eros: MCNoise.Normal
var n_ridge: MCNoise.Normal
var n_temp: MCNoise.Normal
var n_hum: MCNoise.Normal
var n_detail: MCNoise.Normal
var n_cave: MCNoise.Normal
var n_sp1: MCNoise.Normal
var n_sp2: MCNoise.Normal
var b_plains := 0
var b_forest := 0
var b_desert := 0
var b_snowy := 0
var b_ocean := 0
var b_beach := 0
var b_taiga := 0
var b_mount := 0
var b_birch := 0


func _setup() -> void:
	generator_id = "approx_original"
	var pr := RandomSources.Xoroshiro.from_seed(seed).fork_positional()
	n_cont = MCNoise.Normal.create(pr.from_hash("recraft:continents"), -9, PackedFloat64Array([1, 1, 2, 2, 2, 1, 1, 1, 1]))
	n_eros = MCNoise.Normal.create(pr.from_hash("recraft:erosion"), -9, PackedFloat64Array([1, 1, 0, 1, 1]))
	n_ridge = MCNoise.Normal.create(pr.from_hash("recraft:ridge"), -7, PackedFloat64Array([1, 2, 1, 0, 0, 0]))
	n_temp = MCNoise.Normal.create(pr.from_hash("recraft:temperature"), -10, PackedFloat64Array([1.5, 0, 1, 0, 0, 0]))
	n_hum = MCNoise.Normal.create(pr.from_hash("recraft:humidity"), -8, PackedFloat64Array([1, 1, 0, 0, 0, 0]))
	n_detail = MCNoise.Normal.create(pr.from_hash("recraft:detail"), -5, PackedFloat64Array([1, 1, 1]))
	n_cave = MCNoise.Normal.create(pr.from_hash("recraft:cave"), -7, PackedFloat64Array([1, 0.5]))
	n_sp1 = MCNoise.Normal.create(pr.from_hash("recraft:sp1"), -7, PackedFloat64Array([1]))
	n_sp2 = MCNoise.Normal.create(pr.from_hash("recraft:sp2"), -7, PackedFloat64Array([1]))
	b_plains = biomes.id("plains")
	b_forest = biomes.id("forest")
	b_desert = biomes.id("desert")
	b_snowy = biomes.id("snowy_plains")
	b_ocean = biomes.id("ocean")
	b_beach = biomes.id("beach")
	b_taiga = biomes.id("taiga")
	b_mount = biomes.id("windswept_hills")
	b_birch = biomes.id("birch_forest")


func _climate(x: float, z: float) -> Vector4:
	var c := n_cont.value(x * 0.25, 0, z * 0.25)
	var e := n_eros.value(x * 0.25, 0, z * 0.25)
	var w := n_ridge.value(x * 0.25, 0, z * 0.25)
	var pv := 1.0 - absf(3.0 * absf(w) - 2.0)
	var base: float
	if c < -0.455:
		base = 30.0 + (c + 1.05) * 20.0
	elif c < -0.19:
		base = 42.0 + (c + 0.455) / 0.265 * 16.0
	elif c < -0.11:
		base = 58.0 + (c + 0.19) / 0.08 * 6.0
	else:
		base = 64.0 + minf((c + 0.11) * 30.0, 18.0)
	var mount := clampf((c + 0.11) / 0.35, 0.0, 1.0) * clampf((0.1 - e) / 0.9, 0.0, 1.0)
	var h := base + mount * (40.0 + 90.0 * clampf(pv, 0.0, 1.0)) + (1.0 - absf(e)) * 6.0 * clampf(c + 0.2, 0.0, 1.0)
	return Vector4(h, c, e, mount)


func surface_height(x: int, z: int) -> int:
	return int(_climate(x, z).x)


func _biome_for(x: float, z: float, h: float, c: float, mount: float) -> int:
	var t := n_temp.value(x * 0.25, 0, z * 0.25)
	var hu := n_hum.value(x * 0.25, 0, z * 0.25)
	if c < -0.19:
		return b_ocean
	if h < 66.0 and c < -0.11:
		return b_beach
	if mount > 0.5:
		return b_mount
	if t < -0.45:
		return b_snowy
	if t > 0.55:
		return b_desert
	if t < -0.15:
		return b_taiga
	if hu > 0.3:
		return b_birch if t > 0.2 else b_forest
	if hu > 0.0:
		return b_forest
	return b_plains


func generate(ch: Chunk) -> void:
	var x0 := ch.cx * 16
	var z0 := ch.cz * 16
	# coarse 5x5 height/climate grid, bilinear inside the chunk
	var grid: Array = []
	for gz in 5:
		for gx in 5:
			grid.append(_climate(x0 + gx * 4, z0 + gz * 4))
	var heights := PackedFloat32Array()
	heights.resize(256)
	var mounts := PackedFloat32Array()
	mounts.resize(256)
	for z in 16:
		for x in 16:
			var gx := x >> 2
			var gz := z >> 2
			var fx := (x & 3) / 4.0
			var fz := (z & 3) / 4.0
			var a: Vector4 = grid[gz * 5 + gx]
			var b: Vector4 = grid[gz * 5 + gx + 1]
			var c: Vector4 = grid[(gz + 1) * 5 + gx]
			var d: Vector4 = grid[(gz + 1) * 5 + gx + 1]
			var v := a.lerp(b, fx).lerp(c.lerp(d, fx), fz)
			heights[x + z * 16] = v.x + n_detail.value((x0 + x) * 0.5, 0, (z0 + z) * 0.5) * (2.0 + v.w * 8.0)
			mounts[x + z * 16] = v.w
	# biomes per quart column (same for all heights)
	for qz in 4:
		for qx in 4:
			var i := qx * 4 + 2 + (qz * 4 + 2) * 16
			var g: Vector4 = grid[qz * 5 + qx]
			var bio := _biome_for(x0 + qx * 4 + 2, z0 + qz * 4 + 2, heights[i], g.y, g.w)
			for qy in 96:
				ch.biomes[qx + qz * 4 + qy * 16] = bio
	ch.gen_surface.resize(256)
	ch.gen_top.resize(256)
	var col := PackedInt32Array()
	col.resize(98304)
	var s_ore_coal := _st("coal_ore")
	for z in 16:
		for x in 16:
			var h := int(heights[x + z * 16])
			var ci := (z << 4) | x
			var top := maxi(h, Coords.SEA_LEVEL)
			for y in range(Coords.MIN_Y, top + 1):
				var v := S_WATER
				if y == Coords.MIN_Y:
					v = S_BEDROCK
				elif y <= h:
					v = S_DEEPSLATE if y < 0 else S_STONE
					if y < Coords.MIN_Y + 5 and ((x * 7 + z * 13 + y * 3 + ch.cx * 5 + ch.cz) & 7) < (Coords.MIN_Y + 5 - y):
						v = S_BEDROCK
				col[((y - Coords.MIN_Y) << 8) | ci] = v
	# caves: coarse 3D noise every 2 blocks
	for z in range(0, 16, 2):
		for x in range(0, 16, 2):
			var top2 := int(heights[x + z * 16]) - 6
			for y in range(Coords.MIN_Y + 5, mini(top2, 120), 2):
				var wx := x0 + x
				var wz := z0 + z
				var cheese := n_cave.value(wx * 0.6, y * 1.2, wz * 0.6)
				if cheese > 0.55 or absf(n_sp1.value(wx, y * 1.5, wz)) + absf(n_sp2.value(wx, y * 1.5, wz)) < 0.06:
					var fill := S_LAVA if y < -54 else S_AIR
					for dy in 2:
						for dz in 2:
							for dx in 2:
								var ii := ((y + dy - Coords.MIN_Y) << 8) | ((z + dz) << 4) | (x + dx)
								if col[ii] != S_BEDROCK:
									col[ii] = fill
	# surface layer by biome
	var snow_st := _st("snow_block", S_GRASS)
	for z in 16:
		for x in 16:
			var h := int(heights[x + z * 16])
			var bio := ch.biomes[(x >> 2) + (z >> 2) * 4]
			var top_st := S_GRASS
			var under := S_DIRT
			if bio == b_desert or bio == b_beach:
				top_st = S_SAND
				under = S_SAND
			elif bio == b_snowy:
				top_st = snow_st
			elif bio == b_mount and mounts[x + z * 16] > 0.7 and h > 120:
				top_st = S_STONE
				under = S_STONE
			if h < Coords.SEA_LEVEL:
				top_st = S_SAND if h > Coords.SEA_LEVEL - 4 else S_GRAVEL
				under = top_st
			for d in 4:
				var ii2 := ((h - d - Coords.MIN_Y) << 8) | (z << 4) | x
				if col[ii2] == S_STONE:
					col[ii2] = top_st if d == 0 else under
			ch.gen_surface[x + z * 16] = h
			ch.gen_top[x + z * 16] = col[((h - Coords.MIN_Y) << 8) | (z << 4) | x]
	var r := FeaturesBasic.chunk_rng(seed, ch.cx, ch.cz, 77)
	if s_ore_coal != S_STONE:
		for i in 18:
			var ox: int = r.next_int_bound(16)
			var oz: int = r.next_int_bound(16)
			var oy: int = r.next_int_bound(120)
			for k in 6:
				var px: int = clampi(ox + r.next_int_bound(3) - 1, 0, 15)
				var pz: int = clampi(oz + r.next_int_bound(3) - 1, 0, 15)
				var py: int = clampi(oy + r.next_int_bound(3) - 1, Coords.MIN_Y, Coords.MAX_Y - 1)
				var ii3 := ((py - Coords.MIN_Y) << 8) | (pz << 4) | px
				if col[ii3] == S_STONE:
					col[ii3] = s_ore_coal
	ch.fill_from_column(col)
	ch.recompute_heightmap(blocks)


func decorate(ch: Chunk, region: ChunkRegion) -> void:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var oc: Chunk = region.chunks[(dz + 1) * 3 + (dx + 1)]
			if oc == null or oc.gen_surface.is_empty():
				continue
			var r := FeaturesBasic.chunk_rng(seed, oc.cx, oc.cz, 1234)
			var bio := oc.biomes[5]
			var count := 0
			var kind := "oak"
			if bio == b_forest:
				count = 6
			elif bio == b_birch:
				count = 6
				kind = "birch"
			elif bio == b_taiga or bio == b_snowy:
				count = 3 if bio == b_taiga else 1
				kind = "spruce"
			elif bio == b_plains:
				count = 1 if r.next_int_bound(3) == 0 else 0
			elif bio == b_mount:
				count = 1
				kind = "spruce"
			for i in count:
				var lx: int = r.next_int_bound(16)
				var lz: int = r.next_int_bound(16)
				var h := oc.gen_surface[lx + lz * 16]
				if h < Coords.SEA_LEVEL or oc.gen_top[lx + lz * 16] != S_GRASS:
					continue
				FeaturesBasic.tree(region, r, oc.cx * 16 + lx, h + 1, oc.cz * 16 + lz, kind, blocks)
			# grass/flowers only on own chunk
			if oc == ch:
				var grass := _st("short_grass", -1)
				var poppy := _st("poppy", -1)
				for i in (12 if bio == b_plains else 4):
					var lx2: int = r.next_int_bound(16)
					var lz2: int = r.next_int_bound(16)
					var h2 := ch.gen_surface[lx2 + lz2 * 16]
					if ch.gen_top[lx2 + lz2 * 16] == S_GRASS and ch.get_block(lx2, h2 + 1, lz2) == 0:
						var pl := grass if r.next_int_bound(8) > 0 else poppy
						if pl > 0:
							ch.set_block(lx2, h2 + 1, lz2, pl)
	ch.recompute_heightmap(blocks)
