## FlatGenerator — Superflat worlds with configurable layers (bottom-up [block, thickness]) and one biome.
## Contract: settings.flat_layers = [["bedrock",1],["dirt",2],["grass_block",1]], settings.flat_biome = "plains".
## Identical output for positive and negative chunk coordinates (tested).
class_name FlatGenerator
extends WorldGenerator

var column := PackedInt32Array()
var surface_y := Coords.MIN_Y
var biome_id := 0


func _setup() -> void:
	generator_id = "flat"
	var layers: Array = settings.get("flat_layers", [["bedrock", 1], ["dirt", 2], ["grass_block", 1]])
	column.resize(Coords.HEIGHT)
	column.fill(0)
	var y := 0
	for l in layers:
		var st := blocks.parse_state(str(l[0]))
		if st < 0:
			st = blocks.STONE
		for i in int(l[1]):
			if y < Coords.HEIGHT:
				column[y] = st
				y += 1
	surface_y = Coords.MIN_Y + y - 1
	biome_id = biomes.id(str(settings.get("flat_biome", "plains")))


func surface_height(_x: int, _z: int) -> int:
	return surface_y


func generate(ch: Chunk) -> void:
	var col := PackedInt32Array()
	col.resize(98304)
	for y in Coords.HEIGHT:
		var v := column[y]
		if v == 0:
			continue
		var o := y << 8
		for i in 256:
			col[o + i] = v
	ch.fill_from_column(col)
	ch.biomes.fill(biome_id)
	ch.gen_surface.resize(256)
	ch.gen_surface.fill(surface_y)
	ch.gen_top.resize(256)
	ch.gen_top.fill(column[maxi(0, surface_y - Coords.MIN_Y)])
	ch.recompute_heightmap(blocks)
