## CreativeTabs — the creative inventory's per-tab item order, following Java's hand-written CreativeModeTabs lists
## (they are code, not data in the jar): wood sets in wood order, stone families with their stairs / slab / wall,
## metals, colour sets in Java's DyeColor creative order, natural blocks by layer, tools by tier, ... Items the
## installed version lacks are skipped; registry items not named here are appended to their best-guess tab by
## CreativeScreen. The Search tab is every tab's items in tab order without duplicates (Java ItemStackLinkedSet).
class_name CreativeTabs

const COLORS := ["white", "light_gray", "gray", "black", "brown", "red", "orange", "yellow", "lime", "green", "cyan", "light_blue", "blue",
	"purple", "magenta", "pink"]
const WOODS := ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "pale_oak", "poplar", "bamboo", "crimson", "warped"]
## Not in any creative tab in Java (obtained in survival only)
const EXCLUDED := ["written_book", "filled_map", "petrified_oak_slab", "abandoned_camp_map", "buried_ancient_city_map",
	"buried_mineshaft_map", "buried_treasure_map", "buried_trial_chambers_map", "desert_pyramid_map", "desert_village_map",
	"jungle_pyramid_map", "ocean_monument_map", "plains_village_map", "savanna_village_map", "snowy_village_map", "swamp_hut_map",
	"taiga_village_map", "warm_ocean_ruins_map", "woodland_mansion_map"]
const TIERS := ["wooden", "stone", "copper", "iron", "golden", "diamond", "netherite"]
const CORALS := ["tube", "brain", "bubble", "fire", "horn"]
const OXI := ["", "exposed_", "weathered_", "oxidized_"]


static func _wood_set(w: String) -> Array:
	if w == "bamboo":
		return ["bamboo_block", "stripped_bamboo_block", "bamboo_planks", "bamboo_mosaic", "bamboo_stairs", "bamboo_mosaic_stairs", "bamboo_slab",
			"bamboo_mosaic_slab", "bamboo_fence", "bamboo_fence_gate", "bamboo_door", "bamboo_trapdoor", "bamboo_pressure_plate", "bamboo_button"]
	var log := "_stem" if w in ["crimson", "warped"] else "_log"
	var wood := "_hyphae" if w in ["crimson", "warped"] else "_wood"
	var out := [w + log, w + wood, "stripped_" + w + log, "stripped_" + w + wood, w + "_planks"]
	for s in ["_stairs", "_slab", "_fence", "_fence_gate", "_door", "_trapdoor", "_pressure_plate", "_button"]:
		out.append(w + s)
	return out


static func _colors(suffix: String) -> Array:
	var out := []
	for c in COLORS:
		out.append(c + suffix)
	return out


static func _copper_blocks(waxed: bool) -> Array:
	# Java: copper_block, chiseled_copper, copper_grate, cut_copper, cut_copper_stairs, cut_copper_slab, copper_door, copper_trapdoor,
	# copper_bulb (then exposed / weathered / oxidized), the same set waxed
	var out := []
	var w := "waxed_" if waxed else ""
	for o in OXI:
		var base: String = (w + o + "copper") if o != "" else (w + "copper_block")
		out.append(base)
		out.append(w + o + "chiseled_copper")
		out.append(w + o + "copper_grate")
		out.append(w + o + "cut_copper")
		out.append(w + o + "cut_copper_stairs")
		out.append(w + o + "cut_copper_slab")
		out.append(w + o + "copper_door")
		out.append(w + o + "copper_trapdoor")
		out.append(w + o + "copper_bulb")
		out.append(w + o + "copper_bars")
		out.append(w + o + "copper_chain")
		out.append(w + o + "lightning_rod")
	return out


static func building() -> Array:
	var out := []
	for w in WOODS:
		out.append_array(_wood_set(w))
	out.append_array(["stone", "stone_stairs", "stone_slab", "stone_pressure_plate", "stone_button", "cobblestone", "cobblestone_stairs",
		"cobblestone_slab", "cobblestone_wall", "mossy_cobblestone", "mossy_cobblestone_stairs", "mossy_cobblestone_slab", "mossy_cobblestone_wall",
		"smooth_stone", "smooth_stone_slab", "stone_bricks", "cracked_stone_bricks", "stone_brick_stairs", "stone_brick_slab", "stone_brick_wall",
		"chiseled_stone_bricks", "mossy_stone_bricks", "mossy_stone_brick_stairs", "mossy_stone_brick_slab", "mossy_stone_brick_wall"])
	for s in ["granite", "diorite", "andesite"]:
		out.append_array([s, s + "_stairs", s + "_slab", s + "_wall", "polished_" + s, "polished_" + s + "_stairs", "polished_" + s + "_slab"])
	out.append_array(["deepslate", "cobbled_deepslate", "cobbled_deepslate_stairs", "cobbled_deepslate_slab", "cobbled_deepslate_wall",
		"chiseled_deepslate", "polished_deepslate", "polished_deepslate_stairs", "polished_deepslate_slab", "polished_deepslate_wall",
		"deepslate_bricks", "cracked_deepslate_bricks", "deepslate_brick_stairs", "deepslate_brick_slab", "deepslate_brick_wall", "deepslate_tiles",
		"cracked_deepslate_tiles", "deepslate_tile_stairs", "deepslate_tile_slab", "deepslate_tile_wall", "reinforced_deepslate",
		"tuff", "tuff_stairs", "tuff_slab", "tuff_wall", "chiseled_tuff", "polished_tuff", "polished_tuff_stairs", "polished_tuff_slab",
		"polished_tuff_wall", "tuff_bricks", "tuff_brick_stairs", "tuff_brick_slab", "tuff_brick_wall", "chiseled_tuff_bricks",
		"cinnabar", "cinnabar_stairs", "cinnabar_slab", "cinnabar_wall", "chiseled_cinnabar", "polished_cinnabar", "polished_cinnabar_stairs",
		"polished_cinnabar_slab", "polished_cinnabar_wall", "cinnabar_bricks", "cinnabar_brick_stairs", "cinnabar_brick_slab", "cinnabar_brick_wall",
		"sulfur", "sulfur_stairs", "sulfur_slab", "sulfur_wall", "chiseled_sulfur", "polished_sulfur", "polished_sulfur_stairs",
		"polished_sulfur_slab", "polished_sulfur_wall", "sulfur_bricks", "sulfur_brick_stairs", "sulfur_brick_slab", "sulfur_brick_wall",
		"potent_sulfur", "bricks", "brick_stairs", "brick_slab", "brick_wall", "packed_mud", "mud_bricks", "mud_brick_stairs", "mud_brick_slab", "mud_brick_wall",
		"resin_bricks", "resin_brick_stairs", "resin_brick_slab", "resin_brick_wall", "chiseled_resin_bricks",
		"sandstone", "sandstone_stairs", "sandstone_slab", "sandstone_wall", "chiseled_sandstone", "smooth_sandstone", "smooth_sandstone_stairs",
		"smooth_sandstone_slab", "cut_sandstone", "cut_sandstone_slab", "red_sandstone", "red_sandstone_stairs", "red_sandstone_slab",
		"red_sandstone_wall", "chiseled_red_sandstone", "smooth_red_sandstone", "smooth_red_sandstone_stairs", "smooth_red_sandstone_slab",
		"cut_red_sandstone", "cut_red_sandstone_slab", "sea_lantern", "prismarine", "prismarine_stairs", "prismarine_slab", "prismarine_wall",
		"prismarine_bricks", "prismarine_brick_stairs", "prismarine_brick_slab", "dark_prismarine", "dark_prismarine_stairs", "dark_prismarine_slab",
		"netherrack", "nether_bricks", "cracked_nether_bricks", "nether_brick_stairs", "nether_brick_slab", "nether_brick_wall", "nether_brick_fence",
		"chiseled_nether_bricks", "red_nether_bricks", "red_nether_brick_stairs", "red_nether_brick_slab", "red_nether_brick_wall",
		"basalt", "smooth_basalt", "polished_basalt", "blackstone", "gilded_blackstone", "blackstone_stairs", "blackstone_slab", "blackstone_wall",
		"chiseled_polished_blackstone", "polished_blackstone", "polished_blackstone_stairs", "polished_blackstone_slab", "polished_blackstone_wall",
		"polished_blackstone_pressure_plate", "polished_blackstone_button", "polished_blackstone_bricks", "cracked_polished_blackstone_bricks",
		"polished_blackstone_brick_stairs", "polished_blackstone_brick_slab", "polished_blackstone_brick_wall",
		"end_stone", "end_stone_bricks", "end_stone_brick_stairs", "end_stone_brick_slab", "end_stone_brick_wall",
		"purpur_block", "purpur_pillar", "purpur_stairs", "purpur_slab",
		"coal_block", "iron_block", "iron_bars", "iron_door", "iron_trapdoor", "heavy_weighted_pressure_plate", "iron_chain", "chain",
		"gold_block", "light_weighted_pressure_plate", "redstone_block", "emerald_block", "lapis_block", "diamond_block", "netherite_block",
		"quartz_block", "chiseled_quartz_block", "quartz_bricks", "quartz_pillar", "quartz_stairs", "quartz_slab", "smooth_quartz",
		"smooth_quartz_stairs", "smooth_quartz_slab", "amethyst_block"])
	out.append_array(_copper_blocks(false))
	out.append_array(_copper_blocks(true))
	return out


static func colored() -> Array:
	var out := []
	out.append_array(_colors("_wool"))
	out.append_array(_colors("_wool_stairs"))
	out.append_array(_colors("_wool_slab"))
	out.append_array(_colors("_carpet"))
	out.append("terracotta")
	out.append_array(_colors("_terracotta"))
	out.append_array(_colors("_concrete"))
	out.append_array(_colors("_concrete_stairs"))
	out.append_array(_colors("_concrete_slab"))
	out.append_array(_colors("_concrete_powder"))
	out.append_array(_colors("_glazed_terracotta"))
	out.append_array(["glass", "tinted_glass"])
	out.append_array(_colors("_stained_glass"))
	out.append("glass_pane")
	out.append_array(_colors("_stained_glass_pane"))
	out.append("shulker_box")
	out.append_array(_colors("_shulker_box"))
	out.append_array(_colors("_bed"))
	out.append("candle")
	out.append_array(_colors("_candle"))
	out.append_array(_colors("_banner"))
	out.append_array(_colors("_cushion"))
	return out


static func natural() -> Array:
	var out := ["grass_block", "podzol", "mycelium", "dirt_path", "dirt", "coarse_dirt", "rooted_dirt", "farmland", "mud", "clay", "gravel", "sand",
		"sandstone", "red_sand", "red_sandstone", "ice", "packed_ice", "blue_ice", "snow_block", "snow", "moss_block", "moss_carpet",
		"pale_moss_block", "pale_moss_carpet", "pale_hanging_moss", "stone", "deepslate", "granite", "diorite", "andesite", "calcite", "tuff",
		"dripstone_block", "pointed_dripstone", "sulfur", "sulfur_spike", "potent_sulfur", "cinnabar", "prismarine", "magma_block", "obsidian", "crying_obsidian", "netherrack",
		"crimson_nylium", "warped_nylium", "soul_sand", "soul_soil", "bone_block", "blackstone", "basalt", "smooth_basalt", "end_stone"]
	for o in ["coal", "iron", "copper", "gold", "redstone", "emerald", "lapis", "diamond"]:
		out.append_array([o + "_ore", "deepslate_" + o + "_ore"])
	out.append_array(["nether_gold_ore", "nether_quartz_ore", "ancient_debris", "raw_iron_block", "raw_copper_block", "raw_gold_block",
		"glowstone", "amethyst_block", "budding_amethyst", "small_amethyst_bud", "medium_amethyst_bud", "large_amethyst_bud", "amethyst_cluster"])
	for w in ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove"]:
		out.append(w + "_log")
	out.append_array(["mangrove_roots", "muddy_mangrove_roots", "cherry_log", "pale_oak_log", "poplar_log", "mushroom_stem", "crimson_stem",
		"warped_stem"])
	for w in ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "pale_oak", "yellow_poplar", "orange_poplar",
			"red_poplar", "azalea", "flowering_azalea"]:
		out.append(w + "_leaves")
	out.append_array(["brown_mushroom_block", "red_mushroom_block", "nether_wart_block", "warped_wart_block", "shroomlight"])
	for w in ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak"]:
		out.append(w + "_sapling")
	out.append_array(["mangrove_propagule", "cherry_sapling", "pale_oak_sapling", "poplar_sapling", "azalea", "flowering_azalea", "brown_mushroom",
		"red_mushroom", "shelf_mushroom", "red_shrub",
		"crimson_fungus", "warped_fungus", "short_grass", "fern", "bush", "short_dry_grass", "tall_dry_grass", "dead_bush", "dandelion", "golden_dandelion",
		"poppy", "blue_orchid", "allium", "azure_bluet", "red_tulip", "orange_tulip", "white_tulip", "pink_tulip", "oxeye_daisy", "cornflower",
		"lily_of_the_valley", "torchflower", "cactus_flower", "closed_eyeblossom", "open_eyeblossom", "wither_rose", "wildflowers", "pink_petals",
		"leaf_litter", "spore_blossom", "firefly_bush", "bamboo", "sugar_cane", "cactus", "crimson_roots", "warped_roots", "nether_sprouts",
		"weeping_vines", "twisting_vines", "vine", "tall_grass", "large_fern", "sunflower", "lilac", "rose_bush", "peony", "pitcher_plant",
		"big_dripleaf", "small_dripleaf", "chorus_plant", "chorus_flower", "glow_lichen", "hanging_roots", "frogspawn", "turtle_egg", "sniffer_egg",
		"dried_ghast", "wheat_seeds", "cocoa_beans", "pumpkin_seeds", "melon_seeds", "beetroot_seeds", "torchflower_seeds", "pitcher_pod",
		"glow_berries", "sweet_berries", "nether_wart", "lily_pad", "seagrass", "sea_pickle", "kelp", "dried_kelp_block"])
	for c in CORALS:
		out.append(c + "_coral_block")
	for c in CORALS:
		out.append("dead_" + c + "_coral_block")
	for c in CORALS:
		out.append(c + "_coral")
	for c in CORALS:
		out.append("dead_" + c + "_coral")
	for c in CORALS:
		out.append(c + "_coral_fan")
	for c in CORALS:
		out.append("dead_" + c + "_coral_fan")
	out.append_array(["sponge", "wet_sponge", "melon", "pumpkin", "carved_pumpkin", "jack_o_lantern", "hay_block", "bee_nest", "honeycomb_block",
		"slime_block", "honey_block", "resin_block", "ochre_froglight", "verdant_froglight", "pearlescent_froglight", "sculk", "sculk_vein",
		"sculk_catalyst", "sculk_shrieker", "sculk_sensor", "cobweb", "bedrock"])
	return out


static func functional() -> Array:
	var out := ["torch", "soul_torch", "copper_torch", "redstone_torch", "lantern", "soul_lantern"]
	for o in OXI:
		out.append(o + "copper_lantern")
	for o in OXI:
		out.append("waxed_" + o + "copper_lantern")
	out.append_array(["iron_chain", "chain", "end_rod", "sea_lantern", "redstone_lamp"])
	for o in OXI:
		out.append(o + "copper_bulb")
	out.append_array(["glowstone", "shroomlight", "ochre_froglight", "verdant_froglight", "pearlescent_froglight", "crying_obsidian", "glow_lichen",
		"magma_block", "crafting_table", "stonecutter", "cartography_table", "fletching_table", "smithing_table", "grindstone", "loom", "furnace",
		"smoker", "blast_furnace", "campfire", "soul_campfire", "anvil", "chipped_anvil", "damaged_anvil", "composter", "note_block", "jukebox",
		"enchanting_table", "end_crystal", "brewing_stand", "cauldron", "bell", "beacon", "conduit", "lodestone", "ladder", "scaffolding",
		"bee_nest", "beehive", "suspicious_sand", "suspicious_gravel", "lightning_rod", "flower_pot", "decorated_pot", "armor_stand",
		"item_frame", "glow_item_frame", "painting", "bookshelf", "chiseled_bookshelf", "lectern"])
	for w in WOODS:
		out.append(w + "_shelf")
	out.append("tinted_glass")
	for w in WOODS:
		out.append_array([w + "_sign", w + "_hanging_sign"])
	out.append("chest")
	for o in OXI:
		out.append(o + "copper_chest")
	for o in OXI:
		out.append("waxed_" + o + "copper_chest")
	for o in OXI:
		out.append(o + "copper_golem_statue")
	for o in OXI:
		out.append("waxed_" + o + "copper_golem_statue")
	out.append_array(["barrel", "ender_chest", "shulker_box"])
	out.append_array(_colors("_shulker_box"))
	out.append("respawn_anchor")
	out.append("straw_bed")
	out.append_array(_colors("_bed"))
	out.append("candle")
	out.append_array(_colors("_candle"))
	out.append_array(_colors("_banner"))
	out.append_array(["skeleton_skull", "wither_skeleton_skull", "player_head", "zombie_head", "creeper_head", "piglin_head", "dragon_head",
		"dragon_egg", "end_portal_frame", "ender_eye", "vault", "heavy_core", "creaking_heart", "infested_stone", "infested_cobblestone",
		"infested_stone_bricks", "infested_mossy_stone_bricks", "infested_cracked_stone_bricks", "infested_chiseled_stone_bricks",
		"infested_deepslate"])
	return out


static func redstone() -> Array:
	return ["redstone", "redstone_torch", "redstone_block", "repeater", "comparator", "target", "waxed_copper_bulb", "waxed_exposed_copper_bulb",
		"waxed_weathered_copper_bulb", "waxed_oxidized_copper_bulb", "lever", "oak_button", "stone_button", "oak_pressure_plate",
		"stone_pressure_plate", "light_weighted_pressure_plate", "heavy_weighted_pressure_plate", "sculk_sensor", "calibrated_sculk_sensor",
		"sculk_shrieker", "amethyst_block", "white_wool", "tripwire_hook", "string", "lectern", "daylight_detector", "lightning_rod", "piston",
		"sticky_piston", "slime_block", "honey_block", "dispenser", "dropper", "crafter", "hopper", "chest", "copper_chest", "barrel",
		"chiseled_bookshelf", "furnace", "trapped_chest", "jukebox", "decorated_pot", "observer", "note_block", "composter", "cauldron", "rail",
		"powered_rail", "detector_rail", "activator_rail", "minecart", "hopper_minecart", "chest_minecart", "furnace_minecart", "tnt_minecart",
		"oak_chest_boat", "bamboo_chest_raft", "oak_door", "iron_door", "oak_fence_gate", "oak_trapdoor", "iron_trapdoor", "tnt", "redstone_lamp",
		"bell", "big_dripleaf", "armor_stand", "redstone_ore"]


static func tools() -> Array:
	var out := []
	for t in TIERS:
		out.append_array([t + "_shovel", t + "_pickaxe", t + "_axe", t + "_hoe"])
	out.append_array(["bucket", "water_bucket", "cod_bucket", "salmon_bucket", "tropical_fish_bucket", "pufferfish_bucket", "axolotl_bucket",
		"tadpole_bucket", "sulfur_cube_bucket", "lava_bucket", "powder_snow_bucket", "milk_bucket", "fishing_rod", "flint_and_steel", "fire_charge", "bone_meal", "shears",
		"brush", "name_tag", "lead", "bundle"])
	out.append_array(_colors("_bundle"))
	out.append_array(["compass", "recovery_compass", "clock", "spyglass", "map", "writable_book", "wind_charge", "ender_pearl", "ender_eye",
		"elytra", "firework_rocket", "saddle"])
	out.append_array(_colors("_harness"))
	out.append_array(["carrot_on_a_stick", "warped_fungus_on_a_stick"])
	for w in WOODS:
		if w == "bamboo":
			out.append_array(["bamboo_raft", "bamboo_chest_raft"])
		elif w not in ["crimson", "warped"]:
			out.append_array([w + "_boat", w + "_chest_boat"])
	out.append_array(["rail", "powered_rail", "detector_rail", "activator_rail", "minecart", "hopper_minecart", "chest_minecart",
		"furnace_minecart", "tnt_minecart", "trial_key", "ominous_trial_key"])
	for d in ["13", "cat", "blocks", "chirp", "creator", "creator_music_box", "far", "lava_chicken", "mall", "mellohi", "stal", "strad", "ward",
			"11", "wait", "otherside", "5", "pigstep", "relic", "precipice", "tears", "bounce"]:
		out.append("music_disc_" + d)
	out.append("goat_horn")
	return out


static func combat() -> Array:
	var out := []
	for t in TIERS:
		out.append(t + "_sword")
	for t in TIERS:
		out.append(t + "_spear")
	for t in TIERS:
		out.append(t + "_axe")
	out.append_array(["trident", "mace", "shield"])
	for m in ["leather", "chainmail", "copper", "iron", "golden", "diamond", "netherite"]:
		out.append_array([m + "_helmet", m + "_chestplate", m + "_leggings", m + "_boots"])
	out.append("turtle_helmet")
	for m in ["leather", "copper", "iron", "golden", "diamond", "netherite"]:
		out.append(m + "_horse_armor")
	out.append("wolf_armor")
	for m in ["copper", "iron", "golden", "diamond", "netherite"]:
		out.append(m + "_nautilus_armor")
	out.append_array(["totem_of_undying", "tnt", "end_crystal", "snowball", "egg", "brown_egg", "blue_egg", "wind_charge", "bow", "crossbow",
		"firework_rocket", "arrow", "spectral_arrow", "tipped_arrow"])
	return out


static func food() -> Array:
	return ["apple", "golden_apple", "enchanted_golden_apple", "melon_slice", "sweet_berries", "glow_berries", "chorus_fruit", "carrot",
		"golden_carrot", "potato", "baked_potato", "poisonous_potato", "beetroot", "dried_kelp", "beef", "cooked_beef", "porkchop",
		"cooked_porkchop", "mutton", "cooked_mutton", "chicken", "cooked_chicken", "rabbit", "cooked_rabbit", "cod", "cooked_cod", "salmon",
		"cooked_salmon", "tropical_fish", "pufferfish", "bread", "cookie", "cake", "pumpkin_pie", "rotten_flesh", "spider_eye", "mushroom_stew",
		"beetroot_soup", "rabbit_stew", "suspicious_stew", "milk_bucket", "honey_bottle", "ominous_bottle", "potion", "splash_potion",
		"lingering_potion"]


static func ingredients() -> Array:
	var out := ["coal", "charcoal", "raw_iron", "raw_copper", "raw_gold", "emerald", "lapis_lazuli", "diamond", "ancient_debris", "quartz",
		"amethyst_shard", "iron_nugget", "gold_nugget", "copper_nugget", "iron_ingot", "copper_ingot", "gold_ingot", "netherite_scrap",
		"netherite_ingot", "stick", "flint", "wheat", "bone", "string", "feather", "snowball", "egg", "leather", "rabbit_hide", "honeycomb",
		"resin_clump", "ink_sac", "glow_ink_sac", "turtle_scute", "armadillo_scute", "slime_ball", "clay_ball", "prismarine_shard",
		"prismarine_crystals", "nautilus_shell", "heart_of_the_sea", "fire_charge", "blaze_rod", "breeze_rod", "heavy_core", "nether_star",
		"ender_pearl", "ender_eye", "shulker_shell", "popped_chorus_fruit", "echo_shard", "disc_fragment_5"]
	out.append_array(_colors("_dye"))
	# Java: then the brewing ingredients group
	out.append_array(["bowl", "brick", "nether_brick", "resin_brick", "paper", "book", "firework_star", "glass_bottle", "nether_wart",
		"redstone", "glowstone_dust", "gunpowder", "dragon_breath", "fermented_spider_eye", "blaze_powder", "sugar", "rabbit_foot",
		"glistering_melon_slice", "spider_eye", "pufferfish", "magma_cream", "golden_carrot", "ghast_tear", "turtle_helmet", "phantom_membrane",
		"experience_bottle", "enchanted_book", "netherite_upgrade_smithing_template"])
	for t in ["sentry", "vex", "wild", "coast", "dune", "wayfinder", "raiser", "shaper", "host", "ward", "silence", "tide", "snout", "rib",
			"eye", "spire", "flow", "bolt"]:
		out.append(t + "_armor_trim_smithing_template")
	for s in ["angler", "archer", "arms_up", "blade", "brewer", "burn", "danger", "explorer", "flow", "friend", "guster", "heart", "heartbreak",
			"howl", "miner", "mourner", "plenty", "prize", "scrape", "sheaf", "shelter", "skull", "snort"]:
		out.append(s + "_pottery_sherd")
	for b in ["flower", "creeper", "skull", "mojang", "globe", "piglin", "flow", "guster", "field_masoned", "bordure_indented"]:
		out.append(b + "_banner_pattern")
	return out


## Tab id -> ordered item names (CreativeScreen.TABS ids).
static func lists() -> Dictionary:
	return {"building_blocks": building(), "colored_blocks": colored(), "natural_blocks": natural(), "functional_blocks": functional(),
		"redstone_blocks": redstone(), "tools_and_utilities": tools(), "combat": combat(), "food_and_drinks": food(), "ingredients": ingredients()}
