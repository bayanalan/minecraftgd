## ApproxDimGenerator — ORIGINAL placeholder Nether/End terrain for Original Placeholder Mode (no vanilla data):
## Nether = 3D-noise caverns in netherrack between bedrock floor/roof (y 0..127), lava sea below y 32, glowstone
## clusters on ceilings, soul sand patches; End = central end-stone island plus outer islands placed with the
## Java End-island height field (MCNoise.end_height). Clearly labelled APPROXIMATE / ORIGINAL in PARITY_MATRIX.
## Contract: WorldGenerator API; settings["dimension"] selects the_nether | the_end.
class_name ApproxDimGenerator
extends WorldGenerator

var cave: MCNoise.Normal
var detail: MCNoise.Normal
var end_noise: MCNoise.Simplex
var S_NETHERRACK := 0
var S_END_STONE := 0
var S_GLOW := 0
var S_SOUL := 0


func _setup() -> void:
	dimension = str(settings.get("dimension", "the_nether"))
	gen_min_y = 0
	gen_depth = 128 if dimension == "the_nether" else 256
	var pr := RandomSources.Xoroshiro.from_seed(seed).fork_positional()
	cave = MCNoise.Normal.create(pr.from_hash("recraft:nether_cave"), -6, PackedFloat64Array([1.0, 1.0, 0.5]))
	detail = MCNoise.Normal.create(pr.from_hash("recraft:nether_detail"), -3, PackedFloat64Array([1.0]))
	end_noise = MCNoise.end_simplex(seed)
	S_NETHERRACK = _st("netherrack")
	S_END_STONE = _st("end_stone")
	S_GLOW = _st("glowstone")
	S_SOUL = _st("soul_sand", S_NETHERRACK)
	generator_id = "approx_dims"


func surface_height(_x: int, _z: int) -> int:
	return 64


func generate(ch: Chunk) -> void:
	var col := PackedInt32Array()
	col.resize(98304)
	if dimension == "the_end":
		_end(ch, col)
	else:
		_nether(ch, col)
	ch.biomes.fill(0)
	ch.fill_from_column(col)
	ch.recompute_heightmap(blocks)


func _nether(ch: Chunk, col: PackedInt32Array) -> void:
	var r := RandomSources.Xoroshiro.from_seed(seed ^ (ch.cx * 341873128712) ^ (ch.cz * 132897987541))
	for z in 16:
		for x in 16:
			var wx := ch.cx * 16 + x
			var wz := ch.cz * 16 + z
			var soul := detail.value(wx * 0.5, 0.0, wz * 0.5) > 0.35
			for y in 128:
				var i := ((y + 64) << 8) | (z << 4) | x
				if y <= 4 and r.next_int_bound(5) >= y:
					col[i] = S_BEDROCK
					continue
				if y >= 123 and r.next_int_bound(5) >= 127 - y:
					col[i] = S_BEDROCK
					continue
				# density: caverns, thicker near floor and roof
				var d := cave.value(wx, y * 2.0, wz)
				var edge := clampf((24.0 - y) / 24.0, 0.0, 1.0) + clampf((y - 100.0) / 28.0, 0.0, 1.0)
				if d + edge * 1.5 > -0.05:
					col[i] = S_SOUL if soul and y < 40 and d + edge * 1.5 < 0.15 else S_NETHERRACK
				elif y < 32:
					col[i] = S_LAVA
			# glowstone under ceilings
			if r.next_int_bound(64) == 0:
				for y2 in range(118, 30, -1):
					var i2 := ((y2 + 64) << 8) | (z << 4) | x
					if col[i2] == 0 and col[i2 + 256] == S_NETHERRACK:
						col[i2] = S_GLOW
						break


func _end(ch: Chunk, col: PackedInt32Array) -> void:
	for z in 16:
		for x in 16:
			var wx := ch.cx * 16 + x
			var wz := ch.cz * 16 + z
			var h := (MCNoise.end_height(end_noise, wx / 8, wz / 8) - 8.0) / 128.0
			if h <= -0.05:
				continue
			var thick := int(h * 60.0)
			var top := 56 + int(h * 10.0)
			for y in range(maxi(top - thick, 1), top + 1):
				col[((y + 64) << 8) | (z << 4) | x] = S_END_STONE
