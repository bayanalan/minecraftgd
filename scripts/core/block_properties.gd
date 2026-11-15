## BlockProperties — original, code-authored gameplay metadata for block families (hardness, tools, light,
## collision class, friction, sounds). Source-of-truth class D/E (documented knowledge), see docs/DECISIONS.md.
## Why: Java hardness/light/collision are code-defined, not present in resource JSON.
## Contract: get_props(name) -> Dictionary with keys listed in DEFAULTS. Pure; safe from any thread.
class_name BlockProperties

const DEFAULTS := {
	"hardness": 1.0, "resistance": 1.0, "tool": "", "tier": 0, "requires_tool": false,
	"light": 0, "collide": true, "friction": 0.6, "speed": 1.0, "jump": 1.0, "replaceable": false,
	"gravity": false, "flammable": false, "sound": "stone", "climbable": false, "liquid": "",
	"opacity": -1, "waterloggable": false, "render": "", "drops_self": true, "fence_like": false,
}

# Java instabreak blocks (destroy time 0) not covered by a family rule
const INSTABREAK := ["short_grass", "tall_grass", "fern", "large_fern", "short_dry_grass", "tall_dry_grass", "bush", "firefly_bush",
	"dead_bush", "leaf_litter", "wildflowers", "pink_petals", "dandelion", "poppy", "blue_orchid", "allium", "azure_bluet", "oxeye_daisy",
	"cornflower", "lily_of_the_valley", "wither_rose", "torchflower", "open_eyeblossom", "closed_eyeblossom", "cactus_flower", "sunflower",
	"lilac", "rose_bush", "peony", "pitcher_plant", "mangrove_propagule", "wheat", "carrots", "potatoes", "beetroots", "torchflower_crop",
	"pitcher_crop", "sweet_berry_bush", "flower_pot", "azalea", "flowering_azalea", "spore_blossom", "nether_sprouts", "pale_hanging_moss",
	"nether_wart", "decorated_pot", "fire", "soul_fire", "redstone_torch", "redstone_wall_torch", "end_rod", "tripwire_hook"]
# Java strength(hardness, resistance) for plants the families get wrong
const SPECIAL_STRENGTH := {"cocoa": [0.2, 3.0], "chorus_flower": [0.4, 0.4], "chorus_plant": [0.4, 0.4], "bamboo_sapling": [1.0, 1.0], "bamboo": [1.0, 1.0]}

# Exact-name overrides: [hardness, resistance, tool, light]
const EXACT := {
	"air": [0, 0, "", 0], "cave_air": [0, 0, "", 0], "void_air": [0, 0, "", 0],
	"stone": [1.5, 6, "pickaxe", 0], "granite": [1.5, 6, "pickaxe", 0], "diorite": [1.5, 6, "pickaxe", 0],
	"andesite": [1.5, 6, "pickaxe", 0], "cobblestone": [2, 6, "pickaxe", 0], "mossy_cobblestone": [2, 6, "pickaxe", 0],
	"deepslate": [3, 6, "pickaxe", 0], "cobbled_deepslate": [3.5, 6, "pickaxe", 0], "tuff": [1.5, 6, "pickaxe", 0],
	"calcite": [0.75, 0.75, "pickaxe", 0], "dripstone_block": [1.5, 1, "pickaxe", 0], "pointed_dripstone": [1.5, 3, "pickaxe", 0],
	"bedrock": [-1, 3600000, "", 0], "obsidian": [50, 1200, "pickaxe", 0], "crying_obsidian": [50, 1200, "pickaxe", 10],
	"reinforced_deepslate": [55, 1200, "", 0], "barrier": [-1, 3600000, "", 0], "end_portal_frame": [-1, 3600000, "", 1],
	"dirt": [0.5, 0.5, "shovel", 0], "coarse_dirt": [0.5, 0.5, "shovel", 0], "rooted_dirt": [0.5, 0.5, "shovel", 0],
	"grass_block": [0.6, 0.6, "shovel", 0], "podzol": [0.5, 0.5, "shovel", 0], "mycelium": [0.6, 0.6, "shovel", 0],
	"farmland": [0.6, 0.6, "shovel", 0], "dirt_path": [0.65, 0.65, "shovel", 0], "mud": [0.5, 0.5, "shovel", 0],
	"clay": [0.6, 0.6, "shovel", 0], "sand": [0.5, 0.5, "shovel", 0], "red_sand": [0.5, 0.5, "shovel", 0],
	"gravel": [0.6, 0.6, "shovel", 0], "suspicious_sand": [0.25, 0.25, "", 0], "suspicious_gravel": [0.25, 0.25, "", 0],
	"snow": [0.1, 0.1, "shovel", 0], "snow_block": [0.2, 0.2, "shovel", 0], "powder_snow": [0.25, 0.25, "", 0],
	"ice": [0.5, 0.5, "pickaxe", 0], "packed_ice": [0.5, 0.5, "pickaxe", 0], "blue_ice": [2.8, 2.8, "pickaxe", 0],
	"glass": [0.3, 0.3, "", 0], "tinted_glass": [0.3, 0.3, "", 0], "glowstone": [0.3, 0.3, "", 15],
	"sea_lantern": [0.3, 0.3, "", 15], "shroomlight": [1, 1, "hoe", 15], "jack_o_lantern": [1, 1, "axe", 15],
	"torch": [0, 0, "", 14], "wall_torch": [0, 0, "", 14], "soul_torch": [0, 0, "", 10], "soul_wall_torch": [0, 0, "", 10],
	"lantern": [3.5, 3.5, "pickaxe", 15], "soul_lantern": [3.5, 3.5, "pickaxe", 10], "campfire": [2, 2, "axe", 15],
	"soul_campfire": [2, 2, "axe", 10], "fire": [0, 0, "", 15], "soul_fire": [0, 0, "", 10], "lava": [100, 100, "", 15],
	"water": [100, 100, "", 0], "bubble_column": [0, 0, "", 0], "magma_block": [0.5, 0.5, "pickaxe", 3],
	"end_rod": [0, 0, "", 14], "beacon": [3, 3, "", 15], "conduit": [3, 3, "pickaxe", 15], "redstone_lamp": [0.3, 0.3, "", 0],
	"crafting_table": [2.5, 2.5, "axe", 0], "furnace": [3.5, 3.5, "pickaxe", 0], "blast_furnace": [3.5, 3.5, "pickaxe", 0],
	"smoker": [3.5, 3.5, "pickaxe", 0], "chest": [2.5, 2.5, "axe", 0], "trapped_chest": [2.5, 2.5, "axe", 0],
	"ender_chest": [22.5, 600, "pickaxe", 7], "barrel": [2.5, 2.5, "axe", 0], "bookshelf": [1.5, 1.5, "axe", 0],
	"chiseled_bookshelf": [1.5, 1.5, "axe", 0], "lectern": [2.5, 2.5, "axe", 0], "jukebox": [2, 6, "axe", 0],
	"note_block": [0.8, 0.8, "axe", 0], "enchanting_table": [5, 1200, "pickaxe", 7], "anvil": [5, 1200, "pickaxe", 0],
	"chipped_anvil": [5, 1200, "pickaxe", 0], "damaged_anvil": [5, 1200, "pickaxe", 0], "brewing_stand": [0.5, 0.5, "pickaxe", 1],
	"cauldron": [2, 2, "pickaxe", 0], "hopper": [3, 4.8, "pickaxe", 0], "dispenser": [3.5, 3.5, "pickaxe", 0],
	"dropper": [3.5, 3.5, "pickaxe", 0], "observer": [3, 3, "pickaxe", 0], "piston": [1.5, 1.5, "pickaxe", 0],
	"sticky_piston": [1.5, 1.5, "pickaxe", 0], "tnt": [0, 0, "", 0], "spawner": [5, 5, "pickaxe", 0],
	"cobweb": [4, 4, "sword", 0], "ladder": [0.4, 0.4, "axe", 0], "scaffolding": [0, 0, "", 0], "cactus": [0.4, 0.4, "", 0],
	"sugar_cane": [0, 0, "", 0], "bamboo": [1, 1, "axe", 0], "pumpkin": [1, 1, "axe", 0], "carved_pumpkin": [1, 1, "axe", 0],
	"melon": [1, 1, "axe", 0], "hay_block": [0.5, 0.5, "hoe", 0], "sponge": [0.6, 0.6, "hoe", 0], "wet_sponge": [0.6, 0.6, "hoe", 0],
	"netherrack": [0.4, 0.4, "pickaxe", 0], "soul_sand": [0.5, 0.5, "shovel", 0], "soul_soil": [0.5, 0.5, "shovel", 0],
	"basalt": [1.25, 4.2, "pickaxe", 0], "blackstone": [1.5, 6, "pickaxe", 0], "end_stone": [3, 9, "pickaxe", 0],
	"ancient_debris": [30, 1200, "pickaxe", 0], "netherite_block": [50, 1200, "pickaxe", 0], "iron_block": [5, 6, "pickaxe", 0],
	"gold_block": [3, 6, "pickaxe", 0], "diamond_block": [5, 6, "pickaxe", 0], "emerald_block": [5, 6, "pickaxe", 0],
	"lapis_block": [3, 3, "pickaxe", 0], "redstone_block": [5, 6, "pickaxe", 0], "coal_block": [5, 6, "pickaxe", 0],
	"copper_block": [3, 6, "pickaxe", 0], "amethyst_block": [1.5, 1.5, "pickaxe", 0], "budding_amethyst": [1.5, 1.5, "pickaxe", 0],
	"amethyst_cluster": [1.5, 1.5, "pickaxe", 5], "moss_block": [0.1, 0.1, "hoe", 0], "sculk": [0.2, 0.2, "hoe", 0],
	"sculk_sensor": [1.5, 1.5, "hoe", 1], "sculk_catalyst": [3, 3, "hoe", 6], "sculk_shrieker": [3, 3, "hoe", 0],
	"bone_block": [2, 2, "pickaxe", 0], "dried_kelp_block": [0.5, 2.5, "hoe", 0], "slime_block": [0, 0, "", 0],
	"honey_block": [0, 0, "", 0], "iron_bars": [5, 6, "pickaxe", 0], "chain": [5, 6, "pickaxe", 0], "bell": [5, 5, "pickaxe", 0],
	"packed_mud": [1, 3, "", 0], "mud_bricks": [1.5, 3, "pickaxe", 0], "bricks": [2, 6, "pickaxe", 0],
	"stone_bricks": [1.5, 6, "pickaxe", 0], "terracotta": [1.25, 4.2, "pickaxe", 0], "prismarine": [1.5, 6, "pickaxe", 0],
	"cake": [0.5, 0.5, "", 0], "respawn_anchor": [50, 1200, "pickaxe", 0], "lodestone": [3.5, 3.5, "pickaxe", 0],
	"frogspawn": [0, 0, "", 0], "turtle_egg": [0.5, 0.5, "", 0], "sniffer_egg": [0.5, 0.5, "", 0], "dragon_egg": [3, 9, "", 1],
	"composter": [0.6, 0.6, "axe", 0], "grindstone": [2, 6, "pickaxe", 0], "stonecutter": [3.5, 3.5, "pickaxe", 0],
	"loom": [2.5, 2.5, "axe", 0], "smithing_table": [2.5, 2.5, "axe", 0], "cartography_table": [2.5, 2.5, "axe", 0],
	"fletching_table": [2.5, 2.5, "axe", 0], "target": [0.5, 0.5, "hoe", 0], "crafter": [1.5, 3.5, "pickaxe", 0],
	"trial_spawner": [50, 50, "pickaxe", 0], "vault": [50, 50, "pickaxe", 0], "heavy_core": [10, 1200, "pickaxe", 0],
	"redstone_ore": [3, 3, "pickaxe", 0], "deepslate_redstone_ore": [4.5, 3, "pickaxe", 0], "redstone_torch": [0, 0, "", 7],
	"redstone_wall_torch": [0, 0, "", 7], "redstone_wire": [0, 0, "", 0], "repeater": [0, 0, "", 0], "comparator": [0, 0, "", 0],
	"lever": [0.5, 0.5, "", 0], "daylight_detector": [0.2, 0.2, "axe", 0], "tripwire_hook": [0, 0, "", 0], "tripwire": [0, 0, "", 0],
	"glow_lichen": [0.2, 0.2, "axe", 7], "big_dripleaf": [0.1, 0.1, "axe", 0], "small_dripleaf": [0, 0, "shears", 0],
	"cave_vines": [0, 0, "", 0], "cave_vines_plant": [0, 0, "", 0], "vine": [0.2, 0.2, "axe", 0], "lily_pad": [0, 0, "", 0],
	"kelp": [0, 0, "", 0], "kelp_plant": [0, 0, "", 0], "seagrass": [0, 0, "", 0], "tall_seagrass": [0, 0, "", 0],
	"sea_pickle": [0, 0, "", 6], "brown_mushroom": [0, 0, "", 1], "nether_portal": [-1, 0, "", 11], "end_portal": [-1, 3600000, "", 15],
	"end_gateway": [-1, 3600000, "", 15], "light": [-1, 3600000, "", 15], "structure_void": [0, 0, "", 0],
	"ochre_froglight": [0.3, 0.3, "", 15], "verdant_froglight": [0.3, 0.3, "", 15], "pearlescent_froglight": [0.3, 0.3, "", 15],
	"copper_bulb": [3, 6, "pickaxe", 0], "creaking_heart": [10, 10, "axe", 0], "resin_block": [0, 0, "", 0],
}

# wiki Light (light-emitting blocks table): emitters the EXACT table above does not cover (every copper lantern: 15)
const EXTRA_LIGHT := {"large_amethyst_bud": 4, "medium_amethyst_bud": 2, "small_amethyst_bud": 1, "calibrated_sculk_sensor": 1,
	"copper_torch": 14, "copper_wall_torch": 14, "lava_cauldron": 15, "firefly_bush": 2}

# Suffix/prefix family rules evaluated in order: [match_kind, token, hardness, resistance, tool]
const FAMILIES := [
	["suffix", "_planks", 2, 3, "axe"], ["suffix", "_log", 2, 2, "axe"], ["suffix", "_wood", 2, 2, "axe"],
	["suffix", "_stem", 2, 2, "axe"], ["suffix", "_hyphae", 2, 2, "axe"], ["suffix", "_leaves", 0.2, 0.2, "hoe"],
	["suffix", "_wool", 0.8, 0.8, "shears"], ["suffix", "_carpet", 0.1, 0.1, ""], ["suffix", "_concrete_powder", 0.5, 0.5, "shovel"],
	["suffix", "_concrete", 1.8, 1.8, "pickaxe"], ["suffix", "_glazed_terracotta", 1.4, 1.4, "pickaxe"],
	["suffix", "_terracotta", 1.25, 4.2, "pickaxe"], ["suffix", "_stained_glass_pane", 0.3, 0.3, ""],
	["suffix", "_stained_glass", 0.3, 0.3, ""], ["suffix", "glass_pane", 0.3, 0.3, ""], ["suffix", "_bed", 0.2, 0.2, ""],
	["suffix", "_banner", 1, 1, "axe"], ["suffix", "_sign", 1, 1, "axe"], ["suffix", "_door", 3, 3, "axe"],
	["suffix", "_trapdoor", 3, 3, "axe"], ["suffix", "_fence_gate", 2, 3, "axe"], ["suffix", "_pressure_plate", 0.5, 0.5, "pickaxe"],
	["suffix", "_button", 0.5, 0.5, ""], ["suffix", "_sapling", 0, 0, ""], ["suffix", "_tulip", 0, 0, ""],
	["suffix", "_mushroom_block", 0.2, 0.2, "axe"], ["suffix", "_coral_block", 1.5, 6, "pickaxe"], ["suffix", "_coral_fan", 0, 0, ""],
	["suffix", "_coral_wall_fan", 0, 0, ""], ["suffix", "_coral", 0, 0, ""], ["suffix", "_candle", 0.1, 0.1, ""],
	["suffix", "candle_cake", 0.5, 0.5, ""], ["suffix", "_shulker_box", 2, 2, "pickaxe"], ["suffix", "shulker_box", 2, 2, "pickaxe"],
	["suffix", "_ore", 3, 3, "pickaxe"], ["prefix", "deepslate_", 3.5, 6, "pickaxe"], ["prefix", "raw_", 5, 6, "pickaxe"],
	["suffix", "_bricks", 1.5, 6, "pickaxe"], ["suffix", "sandstone", 0.8, 0.8, "pickaxe"], ["suffix", "_copper", 3, 6, "pickaxe"],
	["prefix", "polished_", 1.5, 6, "pickaxe"], ["suffix", "_froglight", 0.3, 0.3, ""], ["suffix", "_head", 1, 1, ""],
	["suffix", "_skull", 1, 1, ""], ["suffix", "_nylium", 0.4, 0.4, "pickaxe"], ["suffix", "_fungus", 0, 0, ""],
	["suffix", "_roots", 0, 0, ""], ["suffix", "_flower_pot", 0, 0, ""], ["prefix", "potted_", 0, 0, ""],
	["suffix", "_cushion", 0.2, 0.2, ""], ["prefix", "quartz", 0.8, 0.8, "pickaxe"], ["prefix", "purpur", 1.5, 6, "pickaxe"],
	["prefix", "prismarine", 1.5, 6, "pickaxe"], ["prefix", "dark_prismarine", 1.5, 6, "pickaxe"], ["suffix", "_rail", 0.7, 0.7, "pickaxe"],
	["prefix", "rail", 0.7, 0.7, "pickaxe"], ["prefix", "infested_", 0.75, 0.75, ""], ["suffix", "_shelf", 2, 3, "axe"],
	["prefix", "sulfur", 1.5, 6, "pickaxe"], ["prefix", "cinnabar", 1.5, 6, "pickaxe"], ["suffix", "_mushroom", 0, 0, ""],
	["suffix", "_vines", 0, 0, ""], ["suffix", "_lantern", 3.5, 3.5, "pickaxe"], ["suffix", "_chest", 2.5, 2.5, "axe"],
	["suffix", "_bulb", 3, 6, "pickaxe"], ["suffix", "_grate", 3, 6, "pickaxe"], ["suffix", "_chain", 5, 6, "pickaxe"],
]

const NO_COLLIDE_TOKENS := ["torch", "sapling", "_tulip", "flower", "short_grass", "tall_grass", "fern", "dead_bush", "seagrass",
	"_coral", "_fan", "kelp", "_button", "pressure_plate", "lever", "redstone_wire", "tripwire", "_rail", "rail", "sign",
	"_banner", "vine", "_roots", "_fungus", "_mushroom", "fire", "sugar_cane", "wheat", "carrots", "potatoes", "beetroots",
	"nether_wart", "sweet_berry_bush", "cobweb", "glow_lichen", "sculk_vein", "spore_blossom", "hanging_roots", "moss_carpet_x",
	"pink_petals", "wildflowers", "leaf_litter", "bush", "firefly_bush", "lily_of_the_valley", "dandelion", "poppy", "orchid",
	"allium", "azure_bluet", "oxeye_daisy", "cornflower", "wither_rose", "torchflower", "pitcher", "sunflower", "lilac", "rose_bush",
	"peony", "melon_stem", "pumpkin_stem", "attached_", "cave_vines", "twisting_vines", "weeping_vines", "nether_portal",
	"end_portal", "end_gateway", "structure_void", "light", "air", "water", "lava", "bubble_column", "frogspawn", "powder_snow",
	"small_dripleaf", "red_shrub", "shelf_mushroom", "_shrub", "cactus_flower", "eyeblossom", "short_dry_grass", "tall_dry_grass",
	"cushion", "string", "hanging_moss", "dripleaf_stem", "propagule", "sprouts"]

## Blocks with Java's WATERLOGGED property (SimpleWaterloggedBlock; wiki Waterlogging, Java "Source" column). The jar's
## blockstate files only name the properties their models use, so most of these get the property from here. Not
## waterloggable in Java: fence gates, candle cakes, jack o'lanterns, sea lanterns (an older name pattern gave it them).
const WATERLOGGABLE := ["chest", "rail", "ladder", "scaffolding", "conduit", "light", "barrier", "pointed_dripstone", "big_dripleaf",
	"big_dripleaf_stem", "small_dripleaf", "sea_pickle", "hanging_roots", "glow_lichen", "lightning_rod", "heavy_core", "decorated_pot",
	"campfire", "soul_campfire", "candle", "lantern", "soul_lantern", "sculk_sensor", "calibrated_sculk_sensor", "sculk_shrieker",
	"sculk_vein", "resin_clump", "mangrove_roots", "mangrove_propagule", "dried_ghast", "amethyst_cluster", "small_amethyst_bud",
	"medium_amethyst_bud", "large_amethyst_bud", "chain"]
const WATERLOGGABLE_SUFFIX := ["_slab", "_stairs", "_wall", "_fence", "_trapdoor", "_sign", "_pane", "_bars", "_chain", "_lantern", "_coral",
	"_coral_fan", "_coral_wall_fan", "_candle", "_rail", "_leaves", "_shelf", "_grate", "_chest", "_lightning_rod", "copper_golem_statue"]


static func is_waterloggable(name: String) -> bool:
	if name in WATERLOGGABLE:
		return true
	if name == "jack_o_lantern" or name == "sea_lantern":
		return false
	for suf in WATERLOGGABLE_SUFFIX:
		if name.ends_with(suf):
			return true
	return false

const REPLACEABLE := ["air", "cave_air", "void_air", "water", "lava", "short_grass", "tall_grass", "fern", "large_fern",
	"dead_bush", "vine", "snow", "fire", "soul_fire", "seagrass", "tall_seagrass", "glow_lichen", "light", "structure_void",
	"crimson_roots", "warped_roots", "nether_sprouts", "hanging_roots", "bubble_column", "short_dry_grass", "tall_dry_grass",
	"leaf_litter", "bush", "red_shrub", "resin_clump"]   # (= 26.3 #replaceable)

const GRAVITY := ["sand", "red_sand", "gravel", "suspicious_sand", "suspicious_gravel", "anvil", "chipped_anvil",
	"damaged_anvil", "dragon_egg", "scaffolding", "pointed_dripstone"]

const NEEDS_TOOL_TOKENS := ["stone", "ore", "deepslate", "cobble", "brick", "obsidian", "concrete", "terracotta", "iron_",
	"gold_block", "diamond_block", "emerald_block", "lapis_block", "redstone_block", "coal_block", "netherite", "copper",
	"andesite", "diorite", "granite", "tuff", "calcite", "basalt", "blackstone", "end_stone", "netherrack", "prismarine",
	"purpur", "quartz", "sandstone", "furnace", "smoker", "anvil", "dispenser", "dropper", "observer", "hopper", "cauldron",
	"enchanting_table", "bell", "lantern", "chain", "magma", "amethyst", "dripstone", "raw_", "spawner", "crafter", "sulfur",
	"cinnabar", "trial_spawner", "vault", "heavy_core", "ice", "grindstone", "stonecutter", "lodestone", "respawn_anchor",
	"conduit", "bone_block", "mud_bricks", "bars", "brewing_stand", "_bulb", "_grate"]


## Java Block.getShape (outline / selection box) for blocks whose shape is code, not their model's element boxes:
## crops by age, plants, saplings, mushrooms, stems, vines ... In 16ths. Empty = use the model's boxes.
static func java_outline(name: String, sp: Dictionary) -> PackedFloat32Array:
	var age := int(sp.get("age", "0"))
	var b := func(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> PackedFloat32Array:
		return PackedFloat32Array([x0 / 16.0, y0 / 16.0, z0 / 16.0, x1 / 16.0, y1 / 16.0, z1 / 16.0])
	match name:
		"wheat":
			return b.call(0, 0, 0, 16, 2 + 2 * clampi(age, 0, 7), 16)
		"carrots", "potatoes":
			return b.call(0, 0, 0, 16, [2, 3, 4, 5, 6, 7, 8, 9][clampi(age, 0, 7)], 16)
		"beetroots":
			return b.call(0, 0, 0, 16, [2, 4, 6, 8][clampi(age, 0, 3)], 16)
		"nether_wart":
			return b.call(0, 0, 0, 16, [5, 8, 11, 14][clampi(age, 0, 3)], 16)
		"torchflower_crop":
			return b.call(5, 0, 5, 11, 6 if age == 0 else 10, 11)
		"sweet_berry_bush":
			return b.call(3, 0, 3, 13, 8, 13) if age == 0 else b.call(1, 0, 1, 15, 16, 15)
		"melon_stem", "pumpkin_stem":
			return b.call(7, 0, 7, 9, 2 + 2 * clampi(age, 0, 7), 9)
		"attached_melon_stem", "attached_pumpkin_stem":
			return b.call(6, 0, 6, 10, 10, 10)
		"short_grass", "fern", "dead_bush", "crimson_roots", "warped_roots", "bush", "firefly_bush", "small_dripleaf", "short_dry_grass":
			return b.call(2, 0, 2, 14, 13, 14)
		"tall_grass", "large_fern", "sugar_cane", "tall_seagrass", "tall_dry_grass":
			return b.call(2, 0, 2, 14, 16, 14)
		"brown_mushroom", "red_mushroom":
			return b.call(5, 0, 5, 11, 6, 11)
		"crimson_fungus", "warped_fungus":
			return b.call(4, 0, 4, 12, 9, 12)
		"nether_sprouts":
			return b.call(2, 0, 2, 14, 3, 14)
		"seagrass":
			return b.call(2, 0, 2, 14, 12, 14)
		"bamboo_sapling":
			return b.call(4, 0, 4, 12, 12, 12)
		"kelp":
			return b.call(0, 0, 0, 16, 9, 16)
		"fire", "soul_fire":
			return b.call(0, 0, 0, 16, 1, 16)
		"lily_pad":
			return b.call(1, 0, 1, 15, 1.5, 15)
		"leaf_litter":
			return b.call(0, 0, 0, 16, 1, 16)
		"pink_petals", "wildflowers":
			return b.call(0, 0, 0, 16, 3, 16)
		"pale_hanging_moss", "cave_vines", "cave_vines_plant", "weeping_vines_plant", "twisting_vines_plant":
			return b.call(1, 0, 1, 15, 16, 15)
		"weeping_vines":
			return b.call(4, 9, 4, 12, 16, 12)
		"twisting_vines":
			return b.call(4, 0, 4, 12, 15, 12)
		"hanging_roots":
			return b.call(2, 10, 2, 14, 16, 14)
		"spore_blossom":
			return b.call(2, 13, 2, 14, 16, 14)
		"redstone_wire":
			# Java RedStoneWireBlock: the centre dot plus an arm to each connected side
			var wx0 := 0.0 if sp.get("west", "none") != "none" else 3.0
			var wx1 := 16.0 if sp.get("east", "none") != "none" else 13.0
			var wz0 := 0.0 if sp.get("north", "none") != "none" else 3.0
			var wz1 := 16.0 if sp.get("south", "none") != "none" else 13.0
			return b.call(wx0, 0, 3, wx1, 1, 13) + b.call(3, 0, wz0, 13, 1, wz1)
	# code shapes of small blocks (Java getShape, not the model's element boxes)
	var facing := str(sp.get("facing", "north"))
	if name in ["torch", "soul_torch", "redstone_torch", "copper_torch"]:
		return b.call(6, 0, 6, 10, 10, 10)
	if name in ["wall_torch", "soul_wall_torch", "redstone_wall_torch", "copper_wall_torch"]:
		return {"north": b.call(5.5, 3, 11, 10.5, 13, 16), "south": b.call(5.5, 3, 0, 10.5, 13, 5), "west": b.call(11, 3, 5.5, 16, 13, 10.5), "east": b.call(0, 3, 5.5, 5, 13, 10.5)}.get(facing, b.call(5.5, 3, 11, 10.5, 13, 16))
	if name == "lantern" or name == "soul_lantern" or name.ends_with("copper_lantern"):
		if sp.get("hanging", "false") == "true":
			return b.call(5, 1, 5, 11, 8, 11) + b.call(6, 8, 6, 10, 10, 10)
		return b.call(5, 0, 5, 11, 7, 11) + b.call(6, 7, 6, 10, 9, 10)
	if name == "flower_pot" or name.begins_with("potted_"):
		return b.call(5, 0, 5, 11, 6, 11)
	if name == "ladder":
		return {"north": b.call(0, 0, 13, 16, 16, 16), "south": b.call(0, 0, 0, 16, 16, 3), "west": b.call(13, 0, 0, 16, 16, 16), "east": b.call(0, 0, 0, 3, 16, 16)}.get(facing, b.call(0, 0, 13, 16, 16, 16))
	if name == "rail" or name.ends_with("_rail"):
		return b.call(0, 0, 0, 16, 8, 16) if str(sp.get("shape", "")).begins_with("ascending") else b.call(0, 0, 0, 16, 2, 16)
	if name.ends_with("_wall_sign"):
		return {"north": b.call(0, 4.5, 14, 16, 12.5, 16), "south": b.call(0, 4.5, 0, 16, 12.5, 2), "east": b.call(0, 4.5, 0, 2, 12.5, 16), "west": b.call(14, 4.5, 0, 16, 12.5, 16)}.get(facing, b.call(0, 4.5, 14, 16, 12.5, 16))
	if name.ends_with("_sign") and not name.ends_with("_hanging_sign"):
		return b.call(4, 0, 4, 12, 16, 12)
	if name.ends_with("_hanging_sign") and not name.contains("_wall_"):
		return b.call(3, 0, 3, 13, 16, 13)
	if name.ends_with("_wall_banner"):
		return {"north": b.call(0, 0, 14, 16, 12.5, 16), "south": b.call(0, 0, 0, 16, 12.5, 2), "west": b.call(14, 0, 0, 16, 12.5, 16), "east": b.call(0, 0, 0, 2, 12.5, 16)}.get(facing, b.call(0, 0, 14, 16, 12.5, 16))
	if name.ends_with("_banner"):
		return b.call(4, 0, 4, 12, 16, 12)
	if name.ends_with("_wall_head") or name.ends_with("_wall_skull"):
		var pw := 1.0 if name == "piglin_wall_head" else 0.0
		return {"north": b.call(4 - pw, 4, 8, 12 + pw, 12, 16), "south": b.call(4 - pw, 4, 0, 12 + pw, 12, 8), "east": b.call(0, 4, 4 - pw, 8, 12, 12 + pw), "west": b.call(8, 4, 4 - pw, 16, 12, 12 + pw)}.get(facing, b.call(4, 4, 8, 12, 12, 16))
	if (name.ends_with("_head") and name != "piston_head") or name.ends_with("_skull"):
		return b.call(3, 0, 3, 13, 8, 13) if name == "piglin_head" else b.call(4, 0, 4, 12, 8, 12)
	if name == "candle" or name.ends_with("_candle"):
		match int(sp.get("candles", "1")):
			2:
				return b.call(5, 0, 6, 11, 6, 9)
			3:
				return b.call(5, 0, 6, 10, 6, 11)
			4:
				return b.call(5, 0, 5, 11, 6, 10)
		return b.call(7, 0, 7, 9, 6, 9)
	if name == "end_rod" or name.ends_with("lightning_rod"):
		if facing == "up" or facing == "down":
			return b.call(6, 0, 6, 10, 16, 10)
		return b.call(6, 6, 0, 10, 10, 16) if facing == "north" or facing == "south" else b.call(0, 6, 6, 16, 10, 10)
	if name == "repeater" or name == "comparator":
		return b.call(0, 0, 0, 16, 2, 16)
	if name == "daylight_detector":
		return b.call(0, 0, 0, 16, 6, 16)
	if name.ends_with("_sapling") or name == "mangrove_propagule":
		return b.call(2, 0, 2, 14, 12, 14)
	if name in ["dandelion", "poppy", "blue_orchid", "allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley", "wither_rose", "torchflower", "open_eyeblossom", "closed_eyeblossom"] or name.ends_with("_tulip"):
		return b.call(5, 0, 5, 11, 10, 11)
	return PackedFloat32Array()


static func get_props(name: String) -> Dictionary:
	var p := DEFAULTS.duplicate()
	var hit := false
	if EXACT.has(name):
		var e: Array = EXACT[name]
		p["hardness"] = float(e[0]); p["resistance"] = float(e[1]); p["tool"] = e[2]; p["light"] = int(e[3])
		hit = true
	else:
		for f in FAMILIES:
			var ok: bool = name.ends_with(f[1]) if f[0] == "suffix" else name.begins_with(f[1])
			if ok:
				p["hardness"] = float(f[2]); p["resistance"] = float(f[3]); p["tool"] = f[4]
				hit = true
				break
	if EXTRA_LIGHT.has(name):
		p["light"] = int(EXTRA_LIGHT[name])
	elif name.ends_with("copper_lantern"):
		p["light"] = 15
	if not hit:
		# derived shapes inherit base material hardness (oak_stairs -> oak_planks etc.)
		for suf in ["_stairs", "_slab", "_wall", "_fence"]:
			if name.ends_with(suf):
				var base := name.trim_suffix(suf)
				var cand := [base, base + "s", base + "_planks", base + "_block"]
				if base in ["spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "bamboo", "crimson", "warped", "pale_oak", "poplar", "oak"]:
					cand = [base + "_planks"]
				for c in cand:
					if is_known(c):
						var sub := get_props(c)
						p["hardness"] = sub["hardness"]; p["resistance"] = sub["resistance"]; p["tool"] = sub["tool"]
						break
				hit = true
				break
	# Java Properties.instabreak() / strength(0): plants, crops, small redstone parts, pots (they fell through to the 1.0
	# default and took half a second to break)
	if INSTABREAK.has(name) or name.ends_with("_sapling") or name.ends_with("_tulip") or name.begins_with("potted_") or name.ends_with("_stem") and (name.contains("melon") or name.contains("pumpkin")):
		p["hardness"] = 0.0
		p["resistance"] = 0.0
	elif SPECIAL_STRENGTH.has(name):
		p["hardness"] = float(SPECIAL_STRENGTH[name][0])
		p["resistance"] = float(SPECIAL_STRENGTH[name][1])
	if is_waterloggable(name):
		p["waterloggable"] = true
	for t in NO_COLLIDE_TOKENS:
		if name == t or (t.length() > 3 and name.contains(t)):
			# exclusions where token matches but block has collision
			if name.ends_with("_block") or name.ends_with("_planks") or name.ends_with("_ore") or name.ends_with("_wall") or name.ends_with("_log") or name in ["mushroom_stem", "light_gray_wool", "sugar_cane_x"] or name.contains("lightning") or name.contains("lightweight") or name.ends_with("_stairs") or name.ends_with("_slab") or name.ends_with("_carpet") or name.contains("light_gray") or name.contains("light_blue") or name.ends_with("_coral_block") or name.contains("redstone_lamp") or name.contains("daylight") or name.contains("candle") or name.contains("lantern") or name.contains("_hyphae") or name.ends_with("_stem") and not name.contains("melon") and not name.contains("pumpkin") or name.ends_with("_wood") or name.ends_with("_trapdoor") or name.ends_with("_door") or name == "big_dripleaf" or name.ends_with("_fence") or name.ends_with("froglight") or name.ends_with("_shelf") or name.begins_with("potted_") or name.contains("campfire") or name.contains("cauldron") or name.ends_with("shroomlight") or name == "chorus_flower" or name.contains("azalea") or name.ends_with("_leaves") or name.ends_with("mangrove_roots"):
				continue
			p["collide"] = false
			break
	if name.ends_with("_pressure_plate") or name.ends_with("_button") or name.ends_with("_sign"):
		p["collide"] = false
	if REPLACEABLE.has(name):
		p["replaceable"] = true
	if GRAVITY.has(name) or name.ends_with("_concrete_powder"):
		p["gravity"] = true
	# "flammable" = catches fire from lava (F_FLAMMABLE, RandomTickable._ignited_by_lava). wiki Fire: hay bales and moss carpets
	# do not; nether wood (crimson / warped) and nether brick never burn
	var nether_wood := name.contains("crimson") or name.contains("warped") or name.begins_with("nether_brick")
	if not nether_wood and (name.ends_with("_planks") or name.ends_with("_log") or name.ends_with("_leaves") or name.ends_with("_wool") or name.ends_with("_wood") or name == "bookshelf" or (name.ends_with("_carpet") and not name.ends_with("moss_carpet")) or name == "tnt" or name.ends_with("_fence") or name.ends_with("_cushion")):
		p["flammable"] = true
	if name in ["ice", "packed_ice", "frosted_ice"]:
		p["friction"] = 0.98
	elif name == "blue_ice":
		p["friction"] = 0.989
	elif name == "slime_block":
		p["friction"] = 0.8
	if name in ["soul_sand", "honey_block"]:
		p["speed"] = 0.4
	if name == "honey_block":
		p["jump"] = 0.5
	if name in ["ladder", "vine", "scaffolding", "cave_vines", "cave_vines_plant", "twisting_vines", "twisting_vines_plant", "weeping_vines", "weeping_vines_plant"]:
		p["climbable"] = true
	if name == "water" or name == "bubble_column":
		p["liquid"] = "water"
	elif name == "lava":
		p["liquid"] = "lava"
	# tool requirement (blocks that drop nothing without the right tool)
	if p["tool"] == "pickaxe":
		for t in NEEDS_TOOL_TOKENS:
			if name.contains(t):
				p["requires_tool"] = true
				break
		if name.ends_with("_slab") or name.ends_with("_stairs") or name.ends_with("_wall"):
			p["requires_tool"] = true
	if name in ["cobweb"]:
		p["requires_tool"] = true
	# wiki hardness / harvest data per block id (the family rules above are only the fallback)
	if BlockHardness.HARDNESS.has(name):
		p["hardness"] = float(BlockHardness.HARDNESS[name])
		p["requires_tool"] = BlockHardness.NEEDS_TOOL.has(name)
	p["sound"] = sound_group(name)
	if name.ends_with("_leaves") or name.contains("glass") or name in ["ice", "water", "cobweb", "frosted_ice", "slime_block", "honey_block"]:
		p["opacity"] = 1 if (name.ends_with("_leaves") or name in ["water", "ice", "frosted_ice", "cobweb"]) else 0
	if name in ["water", "bubble_column"]:
		p["opacity"] = 1
	if name.ends_with("_fence") or name.ends_with("_wall") or name.ends_with("_fence_gate"):
		p["fence_like"] = true
	if name in ["short_grass", "tall_grass", "fern", "large_fern", "dead_bush", "seagrass", "tall_seagrass", "vine", "air", "water", "lava", "fire"]:
		p["drops_self"] = false
	if name.ends_with("_leaves"):
		p["drops_self"] = false
	return p


static func is_known(name: String) -> bool:
	if EXACT.has(name):
		return true
	for f in FAMILIES:
		if (name.ends_with(f[1]) if f[0] == "suffix" else name.begins_with(f[1])):
			return true
	return false


## Sound type volume / pitch (Java SoundType; most are 1.0 / 1.0) - BlockSounds.VOLUME_PITCH when generated.
static func sound_volume_pitch(group: String) -> Array:
	var t = BlockSounds.VOLUME_PITCH.get(group, null)
	return t if t is Array else [1.0, 1.0]


## Java block sounds by kind: place / break at (volume + 1) / 2 and pitch x 0.8 (BlockItem.place, level event 2001),
## mining hit at (volume + 1) / 8 and pitch x 0.5 (continueDestroyBlock), fall at volume x 0.5 and pitch x 0.75.
static func play_block_sound(st: int, kind: String, at: Vector3, bus: String = "Blocks") -> void:
	if st <= 0:
		return
	var g := str(Res.blocks.block_info[Res.blocks.st_block[st]]["sound"])
	var vp := sound_volume_pitch(g)
	var v := float(vp[0])
	var pt := float(vp[1])
	match kind:
		"place", "break":
			Audio.play(sound_event(g, kind), at, bus, (v + 1.0) / 2.0, pt * 0.8)
		"hit":
			Audio.play(sound_event(g, kind), at, bus, (v + 1.0) / 8.0, pt * 0.5)
		"fall":
			Audio.play(sound_event(g, kind), at, bus, v * 0.5, pt * 0.75)


## Sound event of a block sound type ("break", "step", "place", "hit", "fall"); some types reuse other events.
static func sound_event(group: String, kind: String) -> String:
	var ev = BlockSounds.EVENTS.get(group, null)
	if ev is Dictionary and (ev as Dictionary).has(kind):
		return str(ev[kind])
	return "block." + group + "." + kind


static func sound_group(name: String) -> String:
	if BlockSounds.TYPE.has(name):
		return str(BlockSounds.TYPE[name])
	if name.ends_with("_planks") or name.ends_with("_log") or name.ends_with("_wood") or name.contains("oak") or name.contains("spruce") or name.contains("birch") or name.contains("jungle") or name.contains("acacia") or name.contains("mangrove") or name.contains("crafting_table") or name.contains("bookshelf") or name.contains("chest") or name.contains("barrel") or name.contains("poplar"):
		return "wood"
	if name.contains("grass") or name.ends_with("_leaves") or name.contains("sapling") or name.contains("fern") or name.contains("flower") or name.contains("tulip") or name.contains("hay") or name.contains("vine") or name.contains("moss"):
		return "grass"
	if name.contains("sand") and not name.contains("sandstone") or name.contains("concrete_powder"):
		return "sand"
	if name.contains("gravel") or name.contains("dirt") or name == "farmland" or name == "clay" or name == "podzol" or name == "mycelium" or name == "mud":
		return "gravel"
	if name.contains("snow"):
		return "snow"
	if name.contains("wool") or name.contains("carpet") or name.contains("cushion"):
		return "wool"
	if name.contains("glass") or name.contains("ice") or name == "glowstone" or name == "sea_lantern" or name == "beacon":
		return "glass"
	if name.contains("deepslate"):
		return "deepslate"
	if name.contains("copper"):
		return "copper"
	if name.contains("netherrack"):
		return "netherrack"
	return "stone"
