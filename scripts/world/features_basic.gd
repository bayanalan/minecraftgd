## FeaturesBasic — deterministic, order-independent decoration helpers shared by generators:
## trees (oak/birch/spruce/jungle/acacia/dark oak/cherry/pale oak/poplar shapes), ore blobs, plants.
## Why: every feature originates in one chunk with a positional seed; decorating chunk C replays all
## features of its 3x3 neighbourhood and clips writes to C, so results never depend on load order.
## Contract: decorate_region(gen, center, region, per_chunk_fn) ; tree(region, rng, x, y, z, kind, blocks).
## Approximation note: shapes are original approximations of vanilla trunk/foliage placers (source E).
class_name FeaturesBasic


static func chunk_rng(seed: int, cx: int, cz: int, salt: int) -> RandomSources.Xoroshiro:
	return RandomSources.Xoroshiro.from_seed(seed ^ (cx * 341873128712) ^ (cz * 132897987541) ^ salt)


static func put(region: ChunkRegion, x: int, y: int, z: int, st: int, blocks: BlockRegistry, only_replaceable: bool = true) -> void:
	if only_replaceable:
		var cur := region.get_block(x, y, z)
		if cur < 0:
			return
		if cur != 0 and (blocks.st_flags[cur] & (BlockRegistry.F_REPLACEABLE | BlockRegistry.F_LEAVES)) == 0:
			return
		if (blocks.st_flags[cur] & BlockRegistry.F_LIQUID) != 0 and (blocks.st_flags[st] & BlockRegistry.F_LEAVES) == 0:
			return
	region.set_block(x, y, z, st)


static func st(blocks: BlockRegistry, name: String, props: Dictionary = {}) -> int:
	var s := blocks.state_of(name, props)
	return s


static func tree(region: ChunkRegion, r, x: int, y: int, z: int, kind: String, blocks: BlockRegistry) -> void:
	var log_name := kind + "_log"
	var leaf_name := kind + "_leaves"
	if blocks.block_id(log_name) < 0:
		log_name = "oak_log"
	if blocks.block_id(leaf_name) < 0:
		leaf_name = "oak_leaves"
	var logs := st(blocks, log_name, {"axis": "y"})
	var leaves := st(blocks, leaf_name, {"persistent": "false", "distance": "1"})
	if logs < 0 or leaves < 0:
		return
	match kind:
		"spruce":
			var h: int = 6 + r.next_int_bound(4)
			var top := y + h
			var radius := 0
			var max_r: int = 2 + r.next_int_bound(2)
			for yy in range(top + 1, y + 2, -1):
				for dx in range(-radius, radius + 1):
					for dz in range(-radius, radius + 1):
						if absi(dx) == radius and absi(dz) == radius and radius > 0:
							continue
						put(region, x + dx, yy, z + dz, leaves, blocks)
				radius += 1
				if radius > max_r:
					radius = 1
			for i in h:
				put(region, x, y + i, z, logs, blocks, false)
		"birch", "oak", "cherry", "poplar", "pale_oak", "dark_oak", "acacia", "jungle", "mangrove":
			var h2: int = (5 if kind == "birch" else 4) + r.next_int_bound(3)
			if kind == "jungle":
				h2 += 2 + r.next_int_bound(5)
			if kind == "poplar":
				h2 += 3
			var top2 := y + h2
			for yy in range(top2 - 3, top2 + 1):
				var dy := yy - top2
				var rad := 1 if dy >= 0 else 2
				if kind == "poplar":
					rad = 1 if dy >= -1 else 2
				for dx in range(-rad, rad + 1):
					for dz in range(-rad, rad + 1):
						if absi(dx) == rad and absi(dz) == rad and (dy >= 0 or r.next_int_bound(2) == 0):
							continue
						put(region, x + dx, yy, z + dz, leaves, blocks)
			for i in h2:
				put(region, x, y + i, z, logs, blocks, false)
		_:
			for i in 5:
				put(region, x, y + i, z, logs, blocks, false)


static func ore_blob(region: ChunkRegion, r, x: int, y: int, z: int, size: int, ore: int, replace_a: int, replace_b: int, ore_b: int) -> void:
	var c: Chunk = region.chunks[4]
	for i in size:
		var px: int = x + r.next_int_bound(3) - 1
		var py: int = y + r.next_int_bound(3) - 1
		var pz: int = z + r.next_int_bound(3) - 1
		x = px
		y = py
		z = pz
		if (px >> 4) != c.cx or (pz >> 4) != c.cz:
			continue
		var cur := c.get_block(px & 15, py, pz & 15)
		if cur == replace_a:
			c.set_block(px & 15, py, pz & 15, ore)
		elif cur == replace_b and ore_b >= 0:
			c.set_block(px & 15, py, pz & 15, ore_b)
