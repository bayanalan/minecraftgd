## WorldGenerator — base class + factory for versioned chunk generators.
## Why: saves persist generator_id/version so terrain never silently changes (spec §1/§22A).
## Contract: generate(chunk) fills blocks + biomes deterministically from (seed, cx, cz) only, from any
## worker thread; decorate(chunk, neighbours) places cross-chunk-safe features. Must be pure: no shared RNG.
class_name WorldGenerator
extends RefCounted

const PROFILES := {
	"java_26_3": "Java 26.3 data-driven (installed worldgen JSON; parity unverified)",
	"java_1_18_2_exact": "Java 1.18.2 (reference data absent -> APPROXIMATE, labelled)",
	"hybrid_1_18_2_terrain_26_3_content": "Hybrid 1.18.2 terrain + 26.3 content (NOT vanilla-exact)",
	"approx_original": "Original approximate terrain (placeholder mode)",
	"flat": "Superflat",
}

var seed: int = 0
var blocks: BlockRegistry
var biomes: BiomeRegistry
var generator_id := "approx_original"
var generator_version := 1
var settings: Dictionary = {}
var structures_enabled := true
var aborted := false    # set on shutdown: long jobs return early (results are discarded)
var dimension := "overworld"      # overworld | the_nether | the_end
var gen_min_y := -64              # generation range (WorldGenerationContext min_y / height)
var gen_depth := 384

# frequently used states
var S_AIR := 0
var S_STONE := 0
var S_DEEPSLATE := 0
var S_WATER := 0
var S_LAVA := 0
var S_BEDROCK := 0
var S_DIRT := 0
var S_GRASS := 0
var S_SAND := 0
var S_GRAVEL := 0
var S_SNOW_BLOCK := 0


func _st(name: String, fallback: int = -1) -> int:
	var s := blocks.default_state(name) if blocks.block_id(name) >= 0 else -1
	if s < 0:
		return fallback if fallback >= 0 else blocks.STONE
	return s


func setup(p_seed: int, p_blocks: BlockRegistry, p_biomes: BiomeRegistry, p_settings: Dictionary) -> void:
	seed = p_seed
	blocks = p_blocks
	biomes = p_biomes
	settings = p_settings
	structures_enabled = bool(p_settings.get("structures", true))
	S_AIR = 0
	S_STONE = _st("stone")
	S_DEEPSLATE = _st("deepslate", S_STONE)
	S_WATER = _st("water")
	S_LAVA = _st("lava")
	S_BEDROCK = _st("bedrock")
	S_DIRT = _st("dirt")
	S_GRASS = _st("grass_block", S_DIRT)
	S_SAND = _st("sand")
	S_GRAVEL = _st("gravel")
	S_SNOW_BLOCK = _st("snow_block")
	_setup()


func _setup() -> void:
	pass


func generate(_c: Chunk) -> void:
	pass


## Called once the 3x3 neighbourhood has DATA_READY; `get_block`/`set_block` callables address world coords
## restricted to that neighbourhood. Default: nothing.
func decorate(_c: Chunk, _region: ChunkRegion) -> void:
	pass


## Separate feature stage (Features.compute) before decoration? Generators returning true get
## compute_features() called once 3x3 terrain exists; decorate() then applies the 3x3 write lists.
func uses_feature_stage() -> bool:
	return false


func compute_features(_c: Chunk, _region: ChunkRegion) -> PackedInt32Array:
	return PackedInt32Array()


## Spawn-height estimate used for safe spawning.
func surface_height(_x: int, _z: int) -> int:
	return 80


static func create(id: String) -> WorldGenerator:
	match id:
		"flat":
			return FlatGenerator.new()
		"approx_dims":
			return ApproxDimGenerator.new()
		"java_26_3", "java_1_18_2_exact", "hybrid_1_18_2_terrain_26_3_content":
			if Res.mode == "vanilla":
				var g := VanillaGenerator.new()
				g.generator_id = id
				return g
			return ApproxGenerator.new()
		_:
			return ApproxGenerator.new()
