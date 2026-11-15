// Generates scripts/core/block_sounds.gd (block id -> Java block sound type, per-type volume/pitch, per-type event
// overrides) from Minecraft Wiki data, mapped to ids through the game's own English block names.
// Sources (read 2026-11-14, Java Edition rows only; Bedrock-only rows/entries, April Fools and "upcoming" 26.4 /
// Fourth Drop 2026 entries skipped, "until Fourth Drop 2026" entries kept):
//   https://minecraft.wiki/w/Block_sound_type  (?action=raw: the "List" table - type, blocks, volume, pitch)
//   https://minecraft.wiki/w/Template:Sound_table/Block/<Type>/JE  (the event ids each type plays; read in batches via
//     https://minecraft.wiki/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&titles=Template:Sound_table/Block/<Type>/JE|...)
//   Blocks the list leaves out (see PAGE): the block's own page, https://minecraft.wiki/w/<Block>?action=raw and
//     https://minecraft.wiki/api.php?action=query&prop=templates&redirects=1&titles=<Block>|...&tltemplates=Template:Sound_table/Block/<Type>/JE|...
//     (Concrete_Slab, Concrete_Stairs, Wool_Slab, Wool_Stairs, Copper_Torch, Golden_Dandelion, Polished_Cinnabar[_Slab|_Stairs|_Wall],
//     Polished_Sulfur[_Slab|_Stairs|_Wall], Dead_Coral_Fan, Water_Cauldron, Potted_Golden_Dandelion, Potted_Poplar_Sapling,
//     Poplar_Sapling, Wooden_Stairs; "All ..." links cross-checked on Flower, Sunflower, Lilac, Peony, Rose_Bush, Torchflower,
//     Wither_Rose, Terracotta, Banner, Bed, Mushroom_Block, Shelf, Copper_Bars, Lightning_Rod, Copper_Lantern, Copper_Chain,
//     Coral, Coral_Block, Concrete_Powder, Shulker_Box, Carpet)
// The block names are the wiki's {{BlockLink}} names; "@x" entries are the wiki's "All ..." links expanded by id rules
// below (the expansion rule is noted on each). Nothing from the jar is written out: the jar is only read for the
// English names (assets/minecraft/lang/en_us.json), the block id list (assets/minecraft/blockstates/*.json) and the
// flower tags (data/minecraft/tags/block/flowers.json, small_flowers.json).
// Usage: node tools/gen_block_sounds.js [path to 26.3.jar] [out .gd]
//   defaults: %APPDATA%/.minecraft/versions/26.3/26.3.jar  scripts/core/block_sounds.gd
const fs = require("fs"), path = require("path"), zlib = require("zlib");

// ---------------------------------------------------------------- wiki data
// type id = the sound event group the type plays (block.<type>.break ...); `wiki` = the wiki's JE name when it differs.
// vp = [volume, pitch] from the List table (Java Edition values).
const T = {
	amethyst_block: { wiki: "amethyst", vp: [1.0, 1.0], blocks: ["Block of Amethyst", "Budding Amethyst"] },
	amethyst_cluster: { vp: [1.0, 1.0], blocks: ["Amethyst Cluster"] },
	ancient_debris: { vp: [1.0, 1.0], blocks: ["Ancient Debris"] },
	anvil: { vp: [0.3, 1.0], blocks: ["Anvil", "Bell", "Chipped Anvil", "Damaged Anvil"] },
	azalea: { vp: [1.0, 1.0], blocks: ["Azalea"] },
	azalea_leaves: { vp: [1.0, 1.0], blocks: ["Azalea Leaves", "Flowering Azalea Leaves"] },
	bamboo: { vp: [1.0, 1.0], blocks: ["Bamboo"] },
	bamboo_sapling: { vp: [1.0, 1.0], blocks: ["Bamboo Shoot"] },
	bamboo_wood: { vp: [1.0, 1.0], blocks: ["Block of Bamboo", "Block of Stripped Bamboo", "Bamboo Button", "Bamboo Door",
		"Bamboo Fence", "Bamboo Fence Gate", "Bamboo Mosaic", "Bamboo Mosaic Slab", "Bamboo Mosaic Stairs", "Bamboo Planks",
		"Bamboo Pressure Plate", "Bamboo Sign", "Bamboo Slab", "Bamboo Stairs", "Bamboo Trapdoor", "Bamboo Wall Sign"] },
	bamboo_wood_hanging_sign: { vp: [1.0, 1.0], blocks: ["Bamboo Hanging Sign", "Bamboo Wall Hanging Sign"] },
	basalt: { vp: [1.0, 1.0], blocks: ["Basalt", "Polished Basalt", "Smooth Basalt"] },
	big_dripleaf: { vp: [1.0, 1.0], blocks: ["Big Dripleaf", "Big Dripleaf Stem"] },
	bone_block: { vp: [1.0, 1.0], blocks: ["Bone Block"] },
	cactus_flower: { vp: [1.0, 1.0], blocks: ["Cactus Flower"] },
	calcite: { vp: [1.0, 1.0], blocks: ["Calcite"] },
	candle: { vp: [1.0, 1.0], blocks: ["Black Candle", "Blue Candle", "Brown Candle", "Candle", "Cyan Candle", "Gray Candle",
		"Green Candle", "Light Blue Candle", "Light Gray Candle", "Lime Candle", "Magenta Candle", "Orange Candle", "Pink Candle",
		"Purple Candle", "Red Candle", "White Candle", "Yellow Candle"] },
	cave_vines: { vp: [1.0, 1.0], blocks: ["Cave Vines", "Cave Vines Plant"] },
	chain: { vp: [1.0, 1.0], blocks: ["@copper:copper_chain", "Iron Chain"] },
	cherry_leaves: { vp: [1.0, 1.0], blocks: ["Cherry Leaves"] },
	cherry_sapling: { vp: [1.0, 1.0], blocks: ["Cherry Sapling"] },
	cherry_wood: { vp: [1.0, 1.0], blocks: ["Cherry Button", "Cherry Door", "Cherry Fence", "Cherry Fence Gate", "Cherry Log",
		"Cherry Planks", "Cherry Pressure Plate", "Cherry Sign", "Cherry Slab", "Cherry Stairs", "Cherry Trapdoor",
		"Cherry Wall Sign", "Cherry Wood", "Stripped Cherry Log", "Stripped Cherry Wood"] },
	cherry_wood_hanging_sign: { vp: [1.0, 1.0], blocks: ["Cherry Hanging Sign", "Cherry Wall Hanging Sign"] },
	chiseled_bookshelf: { vp: [1.0, 1.0], blocks: ["@shelves", "Chiseled Bookshelf"] },
	cinnabar: { vp: [1.0, 1.0], blocks: ["Chiseled Cinnabar", "Cinnabar", "Cinnabar Slab", "Cinnabar Stairs", "Cinnabar Wall",
		"Cinnabar Brick Slab", "Cinnabar Brick Stairs", "Cinnabar Brick Wall", "Cinnabar Bricks"] },
	cobweb: { vp: [1.0, 1.0], blocks: ["Cobweb"] },
	copper: { vp: [1.0, 1.0], blocks: ["@copper:chiseled_copper", "@copper:copper_bars", "@copper:copper_block",
		"@copper:copper_chest", "@copper:copper_door", "@copper:copper_trapdoor",
		"@copper:cut_copper", "@copper:cut_copper_slab", "@copper:cut_copper_stairs", "@copper:lightning_rod"] },
	// (lead decision: the wiki lists statues under copper, but its statue page has no Java sounds section and 26.3's
	// sounds.json defines block.copper_golem_statue.break / fall / hit / place / step, which the game would only add for a
	// dedicated sound type - so the statues use those events)
	copper_golem_statue: { vp: [1.0, 1.0], blocks: ["@copper:copper_golem_statue"] },
	copper_bulb: { vp: [1.0, 1.0], blocks: ["@copper:copper_bulb"] },
	copper_grate: { vp: [1.0, 1.0], blocks: ["@copper:copper_grate"] },
	coral_block: { vp: [1.0, 1.0], blocks: ["@coral_blocks", "Honeycomb Block"] },
	creaking_heart: { vp: [1.0, 1.0], blocks: ["Creaking Heart"] },
	crop: { vp: [1.0, 1.0], blocks: ["Beetroots", "Carrots", "Pitcher Crop", "Pitcher Plant", "Potatoes", "Torchflower Crop", "Wheat"] },
	// JE: Decorated Pot "popped off" = decorated_pot, "shattered" = decorated_pot_cracked (same block; the block maps to
	// decorated_pot, the game picks decorated_pot_cracked when the pot shatters).
	decorated_pot: { vp: [1.0, 1.0], blocks: ["Decorated Pot"] },
	decorated_pot_cracked: { vp: [1.0, 1.0], blocks: [] },
	deepslate: { vp: [1.0, 1.0], blocks: ["Cobbled Deepslate", "Cobbled Deepslate Slab", "Cobbled Deepslate Stairs",
		"Cobbled Deepslate Wall", "Deepslate", "Deepslate Coal Ore", "Deepslate Copper Ore", "Deepslate Diamond Ore",
		"Deepslate Emerald Ore", "Deepslate Gold Ore", "Deepslate Iron Ore", "Deepslate Lapis Lazuli Ore",
		"Deepslate Redstone Ore", "Infested Deepslate", "Reinforced Deepslate"] },
	deepslate_bricks: { vp: [1.0, 1.0], blocks: ["Chiseled Deepslate", "Cracked Deepslate Bricks", "Deepslate Brick Slab",
		"Deepslate Brick Stairs", "Deepslate Brick Wall", "Deepslate Bricks"] },
	deepslate_tiles: { vp: [1.0, 1.0], blocks: ["Cracked Deepslate Tiles", "Deepslate Tile Slab", "Deepslate Tile Stairs",
		"Deepslate Tile Wall", "Deepslate Tiles"] },
	dried_ghast: { vp: [1.0, 1.0], blocks: ["Dried Ghast"] },
	dripstone_block: { vp: [1.0, 1.0], blocks: ["Dripstone Block"] },
	empty: { vp: [1.0, 1.0], blocks: ["Bubble Column", "Lava", "Water"] },
	flowering_azalea: { vp: [1.0, 1.0], blocks: ["Flowering Azalea"] },
	froglight: { vp: [1.0, 1.0], blocks: ["Ochre Froglight", "Pearlescent Froglight", "Verdant Froglight"] },
	frogspawn: { vp: [1.0, 1.0], blocks: ["Frogspawn"] },
	fungus: { vp: [1.0, 1.0], blocks: ["Crimson Fungus", "Warped Fungus"] },
	gilded_blackstone: { vp: [1.0, 1.0], blocks: ["Gilded Blackstone"] },
	// Blue Ice / Frosted Ice / Ice / Packed Ice are glass "until Fourth Drop 2026" (they get their own types then).
	glass: { vp: [1.0, 1.0], blocks: ["@stained_glass", "@stained_glass_panes", "Blue Ice", "End Portal Frame", "Frosted Ice",
		"Glass", "Glass Pane", "Glowstone", "Ice", "Nether Portal", "Packed Ice", "Redstone Lamp", "Sea Lantern", "Tinted Glass"] },
	glow_lichen: { vp: [1.0, 1.0], blocks: ["Glow Lichen"] },
	grass: { vp: [1.0, 1.0], blocks: ["Acacia Leaves", "Acacia Sapling", "@flowers", "@mushrooms", "Birch Leaves", "Birch Sapling",
		"Bush", "Closed Eyeblossom", "Dark Oak Leaves", "Dark Oak Sapling", "Dead Bush", "Dirt Path", "Dried Kelp Block", "Fern",
		"Grass Block", "Hay Bale", "Jungle Leaves", "Jungle Sapling", "Large Fern", "Mangrove Leaves", "Mangrove Propagule",
		"Mycelium", "Oak Leaves", "Oak Sapling", "Open Eyeblossom", "Pale Oak Leaves", "Pale Oak Sapling", "Short Dry Grass",
		"Short Grass", "Spruce Leaves", "Spruce Sapling", "Sugar Cane", "Tall Dry Grass", "Tall Grass", "Target", "TNT"] },
	gravel: { vp: [1.0, 1.0], blocks: ["Clay", "Coarse Dirt", "Dirt", "Farmland", "Gravel", "Podzol"] },
	hanging_roots: { vp: [1.0, 1.0], blocks: ["Hanging Roots"] },
	hanging_sign: { vp: [1.0, 1.0], blocks: ["Acacia Hanging Sign", "Acacia Wall Hanging Sign", "Birch Hanging Sign",
		"Birch Wall Hanging Sign", "Dark Oak Hanging Sign", "Dark Oak Wall Hanging Sign", "Jungle Hanging Sign",
		"Jungle Wall Hanging Sign", "Mangrove Hanging Sign", "Mangrove Wall Hanging Sign", "Oak Hanging Sign",
		"Oak Wall Hanging Sign", "Pale Oak Hanging Sign", "Pale Oak Wall Hanging Sign", "Poplar Hanging Sign",
		"Poplar Wall Hanging Sign", "Spruce Hanging Sign", "Spruce Wall Hanging Sign"] },
	hard_crop: { vp: [1.0, 1.0], blocks: ["Attached Melon Stem", "Attached Pumpkin Stem", "Melon Stem", "Pumpkin Stem"] },
	heavy_core: { vp: [1.0, 1.0], blocks: ["Heavy Core"] },
	honey_block: { vp: [1.0, 1.0], blocks: ["Honey Block"] },
	iron: { vp: [1.0, 1.0], blocks: ["Block of Iron", "Heavy Weighted Pressure Plate", "Iron Bars", "Iron Door", "Iron Trapdoor"] },
	ladder: { vp: [1.0, 1.0], blocks: ["Ladder"] },
	lantern: { vp: [1.0, 1.0], blocks: ["Lantern", "Soul Lantern", "@copper:copper_lantern"] },
	// JE swaps the large / medium bud sounds (MC-248223) until 26.4: Medium Amethyst Bud plays large_amethyst_bud and back.
	large_amethyst_bud: { vp: [1.0, 1.0], blocks: ["Medium Amethyst Bud"] },
	leaf_litter: { vp: [1.0, 1.0], blocks: ["Leaf Litter"] },
	lily_pad: { vp: [1.0, 1.0], blocks: ["Lily Pad"] },
	lodestone: { vp: [1.0, 1.0], blocks: ["Lodestone"] },
	mangrove_roots: { vp: [1.0, 1.0], blocks: ["Mangrove Roots"] },
	medium_amethyst_bud: { vp: [1.0, 1.0], blocks: ["Large Amethyst Bud"] },
	metal: { vp: [1.0, 1.5], blocks: ["Activator Rail", "Detector Rail", "Block of Diamond", "Block of Emerald", "Block of Gold",
		"Light Weighted Pressure Plate", "Hopper", "Powered Rail", "Rail", "Block of Redstone", "Sniffer Egg", "Turtle Egg"] },
	moss: { vp: [1.0, 1.0], blocks: ["Moss Block", "Pale Moss Block"] },
	moss_carpet: { vp: [1.0, 1.0], blocks: ["Moss Carpet", "Pale Hanging Moss", "Pale Moss Carpet"] },
	mud: { vp: [1.0, 1.0], blocks: ["Mud"] },
	mud_bricks: { vp: [1.0, 1.0], blocks: ["Mud Brick Slab", "Mud Brick Stairs", "Mud Brick Wall", "Mud Bricks"] },
	muddy_mangrove_roots: { vp: [1.0, 1.0], blocks: ["Muddy Mangrove Roots"] },
	nether_bricks: { vp: [1.0, 1.0], blocks: ["Chiseled Nether Bricks", "Cracked Nether Bricks", "Nether Brick Fence",
		"Nether Brick Slab", "Nether Brick Stairs", "Nether Brick Wall", "Nether Bricks", "Red Nether Brick Slab",
		"Red Nether Brick Stairs", "Red Nether Brick Wall", "Red Nether Bricks"] },
	nether_gold_ore: { vp: [1.0, 1.0], blocks: ["Nether Gold Ore"] },
	nether_ore: { vp: [1.0, 1.0], blocks: ["Nether Quartz Ore"] },
	nether_sprouts: { vp: [1.0, 1.0], blocks: ["Nether Sprouts"] },
	nether_wart: { vp: [1.0, 1.0], blocks: ["Nether Wart"] },
	nether_wood: { vp: [1.0, 1.0], blocks: ["Crimson Button", "Crimson Door", "Crimson Fence", "Crimson Fence Gate", "Crimson Planks",
		"Crimson Pressure Plate", "Crimson Sign", "Crimson Slab", "Crimson Stairs", "Crimson Trapdoor", "Crimson Wall Sign",
		"Warped Button", "Warped Door", "Warped Fence", "Warped Fence Gate", "Warped Planks", "Warped Pressure Plate",
		"Warped Sign", "Warped Slab", "Warped Stairs", "Warped Trapdoor", "Warped Wall Sign"] },
	nether_wood_hanging_sign: { vp: [1.0, 1.0], blocks: ["Crimson Hanging Sign", "Crimson Wall Hanging Sign", "Warped Hanging Sign",
		"Warped Wall Hanging Sign"] },
	netherite_block: { vp: [1.0, 1.0], blocks: ["Block of Netherite"] },
	netherrack: { vp: [1.0, 1.0], blocks: ["Netherrack"] },
	nylium: { vp: [1.0, 1.0], blocks: ["Crimson Nylium", "Warped Nylium"] },
	packed_mud: { vp: [1.0, 1.0], blocks: ["Packed Mud"] },
	pink_petals: { vp: [1.0, 1.0], blocks: ["Pink Petals", "Wildflowers"] },
	pointed_dripstone: { vp: [1.0, 1.0], blocks: ["Pointed Dripstone"] },
	polished_deepslate: { vp: [1.0, 1.0], blocks: ["Polished Deepslate", "Polished Deepslate Slab", "Polished Deepslate Stairs",
		"Polished Deepslate Wall"] },
	polished_tuff: { vp: [1.0, 1.0], blocks: ["Polished Tuff", "Polished Tuff Slab", "Polished Tuff Stairs", "Polished Tuff Wall"] },
	poplar_leaves: { vp: [1.0, 1.0], blocks: ["Orange Poplar Leaves", "Red Poplar Leaves", "Yellow Poplar Leaves"] },
	potent_sulfur: { vp: [1.0, 1.0], blocks: ["Potent Sulfur"] },
	powder_snow: { vp: [1.0, 1.0], blocks: ["Powder Snow"] },
	red_shrub: { vp: [1.0, 1.0], blocks: ["Red Shrub"] },
	resin: { vp: [1.0, 1.0], blocks: ["Resin Clump", "Block of Resin"] },
	resin_bricks: { vp: [1.0, 1.0], blocks: ["Chiseled Resin Bricks", "Resin Brick Slab", "Resin Brick Stairs", "Resin Brick Wall",
		"Resin Bricks"] },
	rooted_dirt: { vp: [1.0, 1.0], blocks: ["Rooted Dirt"] },
	roots: { vp: [1.0, 1.0], blocks: ["Crimson Roots", "Warped Roots"] },
	sand: { vp: [1.0, 1.0], blocks: ["@concrete_powder", "Sand", "Red Sand"] },
	scaffolding: { vp: [1.0, 1.0], blocks: ["Scaffolding"] },
	sculk: { vp: [1.0, 1.0], blocks: ["Sculk"] },
	sculk_catalyst: { vp: [1.0, 1.0], blocks: ["Sculk Catalyst"] },
	sculk_sensor: { vp: [1.0, 1.0], blocks: ["Sculk Sensor", "Calibrated Sculk Sensor"] },
	sculk_shrieker: { vp: [1.0, 1.0], blocks: ["Sculk Shrieker"] },
	sculk_vein: { vp: [1.0, 1.0], blocks: ["Sculk Vein"] },
	shelf_mushroom: { vp: [1.0, 1.0], blocks: ["Shelf Mushroom"] },
	shroomlight: { vp: [1.0, 1.0], blocks: ["Shroomlight"] },
	slime_block: { vp: [1.0, 1.0], blocks: ["Sea Pickle", "Slime Block"] },
	small_amethyst_bud: { vp: [1.0, 1.0], blocks: ["Small Amethyst Bud"] },
	small_dripleaf: { vp: [1.0, 1.0], blocks: ["Small Dripleaf"] },
	snow: { vp: [1.0, 1.0], blocks: ["Snow", "Snow Block"] },
	soul_sand: { vp: [1.0, 1.0], blocks: ["Soul Sand"] },
	soul_soil: { vp: [1.0, 1.0], blocks: ["Soul Soil"] },
	spawner: { vp: [1.0, 1.0], blocks: ["Monster Spawner"] },
	sponge: { vp: [1.0, 1.0], blocks: ["Sponge"] },
	spore_blossom: { vp: [1.0, 1.0], blocks: ["Spore Blossom"] },
	stem: { vp: [1.0, 1.0], blocks: ["Crimson Hyphae", "Crimson Stem", "Stripped Crimson Hyphae", "Stripped Crimson Stem",
		"Stripped Warped Hyphae", "Stripped Warped Stem", "Warped Hyphae", "Warped Stem"] },
	stone: { vp: [1.0, 1.0], blocks: ["Air", "Andesite", "Andesite Slab", "Andesite Stairs", "Andesite Wall", "Barrier", "Beacon",
		"Bedrock", "@concrete", "@glazed_terracotta", "@shulker_boxes", "@terracotta", "Blackstone", "Blackstone Slab",
		"Blackstone Stairs", "Blackstone Wall", "Blast Furnace", "Block of Coal", "Block of Lapis Lazuli", "Block of Quartz",
		"Block of Raw Copper", "Block of Raw Gold", "Block of Raw Iron", "Brewing Stand", "Brick Slab", "Brick Stairs",
		"Brick Wall", "Bricks", "Cauldron", "Cave Air", "@command_blocks", "Redstone Comparator", "Chiseled Polished Blackstone",
		"Chiseled Quartz Block", "Chiseled Red Sandstone", "Chiseled Sandstone", "Chiseled Stone Bricks", "Coal Ore",
		"Cobblestone", "Cobblestone Slab", "Cobblestone Stairs", "Cobblestone Wall", "Conduit", "Copper Ore",
		"Cracked Polished Blackstone Bricks", "Cracked Stone Bricks", "Crafter", "Creeper Head", "Creeper Wall Head",
		"Crying Obsidian", "Cut Red Sandstone", "Cut Red Sandstone Slab", "Cut Sandstone", "Cut Sandstone Slab",
		"Dark Prismarine", "Dark Prismarine Slab", "Dark Prismarine Stairs", "@dead_coral", "@dead_coral_blocks", "Diamond Ore",
		"Diorite", "Diorite Slab", "Diorite Stairs", "Diorite Wall", "Dispenser", "Dragon Egg", "Dragon Head", "Dragon Wall Head",
		"Dropper", "Emerald Ore", "Enchanting Table", "End Gateway", "End Portal", "End Stone", "End Stone Brick Slab",
		"End Stone Brick Stairs", "End Stone Brick Wall", "End Stone Bricks", "Ender Chest", "Flower Pot", "Furnace", "Gold Ore",
		"Granite", "Granite Slab", "Granite Stairs", "Granite Wall", "Grindstone", "Infested Chiseled Stone Bricks",
		"Infested Cobblestone", "Infested Cracked Stone Bricks", "Infested Mossy Stone Bricks", "Infested Stone",
		"Infested Stone Bricks", "Iron Ore", "Jigsaw Block", "Lapis Lazuli Ore", "Lava Cauldron", "Lever", "Light", "Magma Block",
		"Mossy Cobblestone", "Mossy Cobblestone Slab", "Mossy Cobblestone Stairs", "Mossy Cobblestone Wall",
		"Mossy Stone Brick Slab", "Mossy Stone Brick Stairs", "Mossy Stone Brick Wall", "Mossy Stone Bricks", "Moving Piston",
		"Observer", "Obsidian", "Petrified Oak Slab", "Piglin Head", "Piglin Wall Head", "Piston", "Piston Head", "Player Head",
		"Player Wall Head", "Polished Andesite", "Polished Andesite Slab", "Polished Andesite Stairs", "Polished Blackstone",
		"Polished Blackstone Brick Slab", "Polished Blackstone Brick Stairs", "Polished Blackstone Brick Wall",
		"Polished Blackstone Bricks", "Polished Blackstone Button", "Polished Blackstone Pressure Plate",
		"Polished Blackstone Slab", "Polished Blackstone Stairs", "Polished Blackstone Wall", "Polished Diorite",
		"Polished Diorite Slab", "Polished Diorite Stairs", "Polished Granite", "Polished Granite Slab", "Polished Granite Stairs",
		"Potted Acacia Sapling", "Potted Allium", "Potted Azalea Bush", "Potted Azure Bluet", "Potted Bamboo",
		"Potted Birch Sapling", "Potted Blue Orchid", "Potted Brown Mushroom", "Potted Cactus", "Potted Cherry Sapling",
		"Potted Closed Eyeblossom", "Potted Cornflower", "Potted Crimson Fungus", "Potted Crimson Roots", "Potted Dandelion",
		"Potted Dark Oak Sapling", "Potted Dead Bush", "Potted Fern", "Potted Flowering Azalea Bush", "Potted Jungle Sapling",
		"Potted Lily of the Valley", "Potted Mangrove Propagule", "Potted Oak Sapling", "Potted Open Eyeblossom",
		"Potted Orange Tulip", "Potted Oxeye Daisy", "Potted Pale Oak Sapling", "Potted Pink Tulip", "Potted Poppy",
		"Potted Red Mushroom", "Potted Red Tulip", "Potted Spruce Sapling", "Potted Torchflower", "Potted Warped Fungus",
		"Potted Warped Roots", "Potted White Tulip", "Potted Wither Rose", "Powder Snow Cauldron", "Prismarine",
		"Prismarine Brick Slab", "Prismarine Brick Stairs", "Prismarine Bricks", "Prismarine Slab", "Prismarine Stairs",
		"Prismarine Wall", "Purpur Block", "Purpur Pillar", "Purpur Slab", "Purpur Stairs", "Quartz Bricks", "Quartz Pillar",
		"Quartz Slab", "Quartz Stairs", "Red Sandstone", "Red Sandstone Slab", "Red Sandstone Stairs", "Red Sandstone Wall",
		"Redstone Ore", "Redstone Dust", "Redstone Repeater", "Respawn Anchor", "Sandstone", "Sandstone Slab", "Sandstone Stairs",
		"Sandstone Wall", "Skeleton Skull", "Skeleton Wall Skull", "Smoker", "Smooth Quartz", "Smooth Quartz Slab",
		"Smooth Quartz Stairs", "Smooth Red Sandstone", "Smooth Red Sandstone Slab", "Smooth Red Sandstone Stairs",
		"Smooth Sandstone", "Smooth Sandstone Slab", "Smooth Sandstone Stairs", "Smooth Stone", "Smooth Stone Slab",
		"Sticky Piston", "Stone", "Stone Brick Slab", "Stone Brick Stairs", "Stone Brick Wall", "Stone Bricks", "Stone Button",
		"Stone Pressure Plate", "Stone Slab", "Stone Stairs", "Stonecutter", "Structure Block", "Structure Void", "Tripwire",
		"Void Air", "Wither Skeleton Skull", "Wither Skeleton Wall Skull", "Zombie Head", "Zombie Wall Head"] },
	straw_bed: { vp: [1.0, 1.0], blocks: ["Straw Bed"] },
	suspicious_gravel: { vp: [1.0, 1.0], blocks: ["Suspicious Gravel"] },
	suspicious_sand: { vp: [1.0, 1.0], blocks: ["Suspicious Sand"] },
	sulfur: { vp: [1.0, 1.0], blocks: ["Chiseled Sulfur", "Sulfur", "Sulfur Slab", "Sulfur Stairs", "Sulfur Wall", "Sulfur Brick Slab",
		"Sulfur Brick Stairs", "Sulfur Brick Wall", "Sulfur Bricks", "Sulfur Spike"] },
	sweet_berry_bush: { vp: [1.0, 1.0], blocks: ["Firefly Bush", "Sweet Berry Bush"] },
	trial_spawner: { vp: [1.0, 1.0], blocks: ["Trial Spawner"] },
	tuff: { vp: [1.0, 1.0], blocks: ["Chiseled Tuff", "Tuff", "Tuff Slab", "Tuff Stairs", "Tuff Wall"] },
	tuff_bricks: { vp: [1.0, 1.0], blocks: ["Chiseled Tuff Bricks", "Tuff Brick Slab", "Tuff Brick Stairs", "Tuff Brick Wall", "Tuff Bricks"] },
	// JE twisting_vines exists but no block uses it (twisting vines play weeping_vines, MC-257454).
	twisting_vines: { vp: [1.0, 0.5], blocks: [] },
	vault: { vp: [1.0, 1.0], blocks: ["Vault"] },
	vine: { vp: [1.0, 1.0], blocks: ["Vines"] },
	wart_block: { vp: [1.0, 1.0], blocks: ["Nether Wart Block", "Warped Wart Block"] },
	weeping_vines: { vp: [1.0, 1.0], blocks: ["Twisting Vines", "Twisting Vines Plant", "Weeping Vines", "Weeping Vines Plant"] },
	wet_grass: { vp: [1.0, 1.0], blocks: ["@coral", "@coral_fans", "Kelp", "Kelp Plant", "Seagrass", "Tall Seagrass"] },
	wet_sponge: { vp: [1.0, 1.0], blocks: ["Wet Sponge"] },
	wood: { vp: [1.0, 1.0], blocks: [
		...woodSet("Acacia"), ...woodSet("Birch"), ...woodSet("Dark Oak"), ...woodSet("Jungle"), ...woodSet("Mangrove"),
		...woodSet("Oak"), ...woodSet("Pale Oak"), ...woodSet("Spruce"),
		// the wiki's poplar entries (no "Poplar Stairs" entry is listed)
		"Poplar Button", "Poplar Door", "Poplar Fence", "Poplar Fence Gate", "Poplar Log", "Poplar Planks", "Poplar Pressure Plate",
		"Poplar Sign", "Poplar Slab", "Poplar Trapdoor", "Poplar Wall Sign", "Poplar Wood", "Stripped Poplar Log", "Stripped Poplar Wood",
		"Barrel", "Bee Nest", "Beehive", "@banners", "@beds", "Bookshelf", "@mushroom_blocks", "Campfire", "Cartography Table",
		"Carved Pumpkin", "Chest", "Chorus Flower", "Chorus Plant", "Cocoa", "Composter", "Crafting Table", "Daylight Detector",
		"End Rod", "Fletching Table", "Jack o'Lantern", "Jukebox", "Lectern", "Loom", "Melon", "Mushroom Stem", "Note Block",
		"Pumpkin", "Redstone Torch", "Redstone Wall Torch", "Smithing Table", "Soul Campfire", "Soul Torch", "Soul Wall Torch",
		"Torch", "Trapped Chest", "Tripwire Hook", "Wall Torch"] },
	wool: { vp: [1.0, 1.0], blocks: ["@carpets", "@wool", "Cactus", "Cake", "Cake with Candle", "Fire", "Soul Fire",
		...["Black", "Blue", "Brown", "Cyan", "Gray", "Green", "Light Blue", "Light Gray", "Lime", "Magenta", "Orange", "Pink",
			"Purple", "Red", "White", "Yellow"].map(c => "Cake with " + c + " Candle")] },
};
function woodSet(w) {
	return ["Button", "Door", "Fence", "Fence Gate", "Log", "Planks", "Pressure Plate", "Sign", "Slab", "Stairs", "Trapdoor",
		"Wall Sign", "Wood"].map(s => w + " " + s).concat(["Stripped " + w + " Log", "Stripped " + w + " Wood"]);
}

// Event ids per type, from the JE sound table templates, only for types that do not simply play
// block.<type>.{break,step,place,hit,fall}. "" = the template has no row for that event (nothing listed).
// "intentionally_empty" = the template's minecraft:intentionally_empty (no sound).
const EV = {
	bamboo_sapling: { break: "block.bamboo_sapling.break", step: "block.bamboo.step", place: "block.bamboo_sapling.place",
		hit: "block.bamboo_sapling.hit", fall: "block.bamboo.fall" },
	cactus_flower: { break: "block.cactus_flower.break", step: "", place: "block.cactus_flower.place", hit: "", fall: "" },
	crop: { break: "block.crop.break", step: "block.grass.step", place: "item.crop.plant", hit: "block.grass.hit",
		fall: "block.grass.fall" },
	decorated_pot_cracked: { break: "block.decorated_pot.shatter", step: "block.decorated_pot.step",
		place: "block.decorated_pot.place", hit: "block.decorated_pot.hit", fall: "block.decorated_pot.fall" },
	dried_ghast: { break: "block.dried_ghast.break", step: "block.dried_ghast.step", place: "block.dried_ghast.place", hit: "",
		fall: "block.dried_ghast.fall" },
	empty: { break: "intentionally_empty", step: "intentionally_empty", place: "intentionally_empty", hit: "intentionally_empty",
		fall: "intentionally_empty" },
	glow_lichen: { break: "block.grass.break", step: "block.vine.step", place: "block.grass.place", hit: "block.grass.hit",
		fall: "block.grass.fall" },
	hard_crop: { break: "block.wood.break", step: "block.wood.step", place: "item.crop.plant", hit: "block.wood.hit",
		fall: "block.wood.fall" },
	large_amethyst_bud: { break: "block.large_amethyst_bud.break", step: "block.amethyst_cluster.step",
		place: "block.large_amethyst_bud.place", hit: "block.amethyst_cluster.hit", fall: "block.amethyst_cluster.fall" },
	lily_pad: { break: "block.big_dripleaf.break", step: "block.big_dripleaf.step", place: "block.lily_pad.place",
		hit: "block.big_dripleaf.hit", fall: "block.big_dripleaf.fall" },
	medium_amethyst_bud: { break: "block.medium_amethyst_bud.break", step: "block.amethyst_cluster.step",
		place: "block.medium_amethyst_bud.place", hit: "block.amethyst_cluster.hit", fall: "block.amethyst_cluster.fall" },
	nether_wart: { break: "block.nether_wart.break", step: "block.stone.step", place: "item.nether_wart.plant",
		hit: "block.stone.hit", fall: "block.stone.fall" },
	red_shrub: { break: "block.red_shrub.break", step: "", place: "block.red_shrub.place", hit: "", fall: "" },
	resin: { break: "block.resin.break", step: "block.resin.step", place: "block.resin.place", hit: "", fall: "block.resin.fall" },
	// the template writes "shelf_mushroom.break" / "shelf_mushroom.step" without the block. prefix; the jar's
	// sounds.json has block.shelf_mushroom.{break,step,place,fall}, which is what is used here.
	shelf_mushroom: { break: "block.shelf_mushroom.break", step: "block.shelf_mushroom.step",
		place: "block.shelf_mushroom.place", hit: "", fall: "block.shelf_mushroom.fall" },
	small_amethyst_bud: { break: "block.small_amethyst_bud.break", step: "block.amethyst_cluster.step",
		place: "block.small_amethyst_bud.place", hit: "block.amethyst_cluster.hit", fall: "block.amethyst_cluster.fall" },
	sweet_berry_bush: { break: "block.sweet_berry_bush.break", step: "block.grass.step", place: "block.sweet_berry_bush.place",
		hit: "block.grass.hit", fall: "block.grass.fall" },
	twisting_vines: { break: "block.weeping_vines.break", step: "block.weeping_vines.step", place: "block.weeping_vines.place",
		hit: "block.weeping_vines.hit", fall: "block.weeping_vines.fall" },
};

// Blocks the "Block sound type" list does not name for Java Edition, taken from each block's own wiki page (the
// Java sound table its Sounds section transcludes, checked with api.php?action=query&prop=templates&tltemplates=
// Template:Sound_table/Block/<Type>/JE, or the section text where noted).
const PAGE = {
	stone: [
		"@colored:concrete_slab",    // Concrete Slab: Sound table/Block/Stone/JE
		"@colored:concrete_stairs",  // Concrete Stairs: Sound table/Block/Stone/JE
		"@dead_coral_fans",          // Dead Coral Fan (covers the wall fans): Sound table/Block/Stone/JE (the list has it BE-only)
		"Water Cauldron",            // Water Cauldron -> Cauldron: Sound table/Block/Stone/JE (the list has it BE-only)
		"Potted Golden Dandelion",   // -> Flower Pot: Sound table/Block/Stone/JE
		"Potted Poplar Sapling",     // -> Flower Pot: Sound table/Block/Stone/JE
	],
	wool: ["@colored:wool_slab", "@colored:wool_stairs"],  // Wool Slab / Wool Stairs: Sound table/Block/Wool/JE
	wood: [
		"Copper Torch", "Copper Wall Torch",  // Copper Torch (covers the wall torch): Sound table/Block/Wood/JE
		"Poplar Stairs",                      // -> Wooden Stairs, Sounds "Normal wood": {{SoundEvents|#block.wood}}
	],
	grass: [
		"Poplar Sapling",    // -> Sapling: Sound table/Block/Grass/JE (+ Cherry sapling/JE for the cherry one)
		"Golden Dandelion",  // Golden Dandelion: Sound table/Block/Grass/JE (also in the #flowers tag)
	],
	cinnabar: ["Polished Cinnabar", "Polished Cinnabar Slab", "Polished Cinnabar Stairs", "Polished Cinnabar Wall"],  // each page: Cinnabar/JE
	sulfur: ["Polished Sulfur", "Polished Sulfur Slab", "Polished Sulfur Stairs", "Polished Sulfur Wall"],  // each page: Sulfur/JE
};

// wiki BlockLink name -> game English name, where they differ
const ALIAS = { "wheat": "wheat crops", "redstone dust": "redstone wire", "potted azalea bush": "potted azalea",
	"potted flowering azalea bush": "potted flowering azalea", "smooth quartz": "smooth quartz block" };

// ---------------------------------------------------------------- jar reading (zip central directory, no deps)
function openJar(p) {
	const buf = fs.readFileSync(p);
	let eocd = buf.length - 22; while (eocd >= 0 && buf.readUInt32LE(eocd) !== 0x06054b50) eocd--;
	if (eocd < 0) throw new Error("not a zip: " + p);
	const n = buf.readUInt16LE(eocd + 10); let off = buf.readUInt32LE(eocd + 16); const ents = {};
	for (let i = 0; i < n; i++) {
		const method = buf.readUInt16LE(off + 10), csize = buf.readUInt32LE(off + 20), nl = buf.readUInt16LE(off + 28),
			el = buf.readUInt16LE(off + 30), cl = buf.readUInt16LE(off + 32), lho = buf.readUInt32LE(off + 42);
		ents[buf.toString("utf8", off + 46, off + 46 + nl)] = { method, csize, lho }; off += 46 + nl + el + cl;
	}
	return {
		names: Object.keys(ents),
		read(name) {
			const e = ents[name]; if (!e) throw new Error("missing in jar: " + name);
			const s = e.lho + 30 + buf.readUInt16LE(e.lho + 26) + buf.readUInt16LE(e.lho + 28); const d = buf.subarray(s, s + e.csize);
			return (e.method === 8 ? zlib.inflateRawSync(d) : d).toString("utf8");
		},
	};
}
const jarPath = process.argv[2] || path.join(process.env.APPDATA || "", ".minecraft/versions/26.3/26.3.jar");
const outPath = process.argv[3] || path.join(__dirname, "../scripts/core/block_sounds.gd");
const jar = openJar(jarPath);
const lang = JSON.parse(jar.read("assets/minecraft/lang/en_us.json"));
// blockstates/*.json = the block ids; item_frame / glow_item_frame are entity render models there, not blocks.
const NOT_BLOCKS = new Set(["item_frame", "glow_item_frame"]);
const ids = jar.names.map(n => (n.match(/^assets\/minecraft\/blockstates\/([a-z0-9_]+)\.json$/) || [])[1]).filter(Boolean)
	.filter(i => !NOT_BLOCKS.has(i)).sort();
const idSet = new Set(ids);
function tag(n) {
	const o = new Set();
	for (let v of JSON.parse(jar.read("data/minecraft/tags/block/" + n + ".json")).values) {
		if (typeof v !== "string") v = v.id;
		if (v.startsWith("#")) for (const x of tag(v.replace("#minecraft:", ""))) o.add(x); else o.add(v.replace("minecraft:", ""));
	}
	return o;
}

// ---------------------------------------------------------------- name -> ids
const norm = s => s.toLowerCase().replace(/’/g, "'").trim();
const byName = {};
for (const id of ids) { const nm = lang["block.minecraft." + id]; if (nm) (byName[norm(nm)] = byName[norm(nm)] || []).push(id); }
const COLORS = ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray", "light_gray", "cyan", "purple",
	"blue", "brown", "green", "red", "black"];
const CORALS = ["tube", "brain", "bubble", "fire", "horn"];
const OXI = ["", "exposed_", "weathered_", "oxidized_", "waxed_", "waxed_exposed_", "waxed_weathered_", "waxed_oxidized_"];
const ex = list => list.filter(i => idSet.has(i));
function expand(tok) {
	const [k, arg] = tok.slice(1).split(":");
	switch (k) {
		// "All Copper X" = every oxidation stage, waxed and unwaxed (Block of Copper's stages are named <stage>_copper)
		case "copper": return arg === "copper_block"
			? ex(OXI.map(p => p === "" ? "copper_block" : p === "waxed_" ? "waxed_copper_block" : p + "copper"))
			: ex(OXI.map(p => p + arg));
		case "concrete": return ex(COLORS.map(c => c + "_concrete"));
		case "concrete_powder": return ex(COLORS.map(c => c + "_concrete_powder"));
		case "glazed_terracotta": return ex(COLORS.map(c => c + "_glazed_terracotta"));
		case "terracotta": return ex(["terracotta", ...COLORS.map(c => c + "_terracotta")]);
		case "shulker_boxes": return ex(["shulker_box", ...COLORS.map(c => c + "_shulker_box")]);
		case "stained_glass": return ex(COLORS.map(c => c + "_stained_glass"));
		case "stained_glass_panes": return ex(COLORS.map(c => c + "_stained_glass_pane"));
		case "carpets": return ex(COLORS.map(c => c + "_carpet"));
		case "wool": return ex(COLORS.map(c => c + "_wool"));
		case "banners": return ex(COLORS.flatMap(c => [c + "_banner", c + "_wall_banner"]));
		case "beds": return ex(COLORS.map(c => c + "_bed"));
		case "command_blocks": return ex(["command_block", "chain_command_block", "repeating_command_block"]);
		case "coral": return ex(CORALS.map(c => c + "_coral"));
		case "coral_fans": return ex(CORALS.flatMap(c => [c + "_coral_fan", c + "_coral_wall_fan"]));
		case "coral_blocks": return ex(CORALS.map(c => c + "_coral_block"));
		case "dead_coral": return ex(CORALS.map(c => "dead_" + c + "_coral"));
		case "dead_coral_blocks": return ex(CORALS.map(c => "dead_" + c + "_coral_block"));
		case "dead_coral_fans": return ex(CORALS.flatMap(c => ["dead_" + c + "_coral_fan", "dead_" + c + "_coral_wall_fan"]));
		case "colored": return ex(COLORS.map(c => c + "_" + arg));
		case "mushroom_blocks": return ex(["brown_mushroom_block", "red_mushroom_block"]);
		case "mushrooms": return ex(["brown_mushroom", "red_mushroom"]);
		case "shelves": return ids.filter(i => /_shelf$/.test(i) && i !== "chiseled_bookshelf");
		// "All Flowers" = the jar's #flowers tag; entries the wiki lists under another type keep that type.
		case "flowers": return [...tag("flowers")].filter(i => idSet.has(i));
	}
	throw new Error("unknown expansion " + tok);
}

// explicit list names first, then the list's "All ..." expansions, then the per-page additions (PAGE); an id keeps
// the first type it gets. Two different types for one id are reported, except an "All ..." expansion meeting an
// id the list names explicitly elsewhere (e.g. #flowers holds cherry_leaves, listed as cherry_leaves).
const typeOf = {}, conflicts = [], unresolved = [];
const passes = [
	Object.entries(T).flatMap(([ty, d]) => d.blocks.filter(b => b[0] !== "@").map(b => [ty, b])),
	Object.entries(T).flatMap(([ty, d]) => d.blocks.filter(b => b[0] === "@").map(b => [ty, b])),
	Object.entries(PAGE).flatMap(([ty, l]) => l.map(b => [ty, b])),
];
const explicit = new Set();
passes.forEach((list, pi) => { for (const [ty, b] of list) {
	let got;
	if (b[0] === "@") got = expand(b);
	else { const n = norm(b); got = byName[ALIAS[n] || n]; if (!got) { unresolved.push(ty + ": " + b); continue; } }
	for (const id of got) {
		if (typeOf[id] === undefined) { typeOf[id] = ty; if (pi === 0) explicit.add(id); }
		else if (typeOf[id] !== ty && !(pi === 1 && explicit.has(id))) conflicts.push(id + ": " + typeOf[id] + " vs " + ty);
	}
} });
for (const ty of Object.keys(PAGE)) if (!T[ty]) throw new Error("PAGE type not in T: " + ty);

// ---------------------------------------------------------------- checks against the jar's sounds.json (if given)
const soundsPath = process.env.SOUNDS_JSON;
if (soundsPath) {
	const snd = JSON.parse(fs.readFileSync(soundsPath, "utf8"));
	for (const ty of Object.keys(T)) for (const e of ["break", "step", "place", "hit", "fall"]) {
		const ev = EV[ty] ? EV[ty][e] : "block." + ty + "." + e;
		if (ev && ev !== "intentionally_empty" && !snd[ev]) console.log("event not in sounds.json:", ty, e, ev);
	}
}

// ---------------------------------------------------------------- GDScript output
const unmapped = ids.filter(i => typeOf[i] === undefined);
const fmt = v => Number.isInteger(v) ? v.toFixed(1) : String(v);
function pack(entries) {
	let s = "", line = "\t";
	for (const e of entries) { if (line.length + e.length > 118) { s += line.trimEnd() + "\n"; line = "\t"; } line += e + " "; }
	return s + line.trimEnd() + "\n";
}
let gd = "## BlockSounds - generated by tools/gen_block_sounds.js from minecraft.wiki \"Block sound type\" (Java Edition).\n";
gd += "## TYPE: block id -> sound type (the block.<type>.* event group, unless EVENTS overrides it). VOLUME_PITCH: the type's\n";
gd += "## volume / pitch multipliers where not 1.0 / 1.0. EVENTS: per-event ids for types that play other groups' events\n";
gd += "## (\"\" = no event listed for it, \"intentionally_empty\" = silent). Regenerate: node tools/gen_block_sounds.js\n";
gd += "class_name BlockSounds\n\n";
gd += "const TYPE := {\n" + pack(Object.keys(typeOf).sort().map(k => `"${k}": "${typeOf[k]}",`)) + "}\n\n";
gd += "const VOLUME_PITCH := {\n" + pack(Object.keys(T).filter(k => T[k].vp[0] !== 1 || T[k].vp[1] !== 1)
	.map(k => `"${k}": [${fmt(T[k].vp[0])}, ${fmt(T[k].vp[1])}],`)) + "}\n\n";
gd += "const EVENTS := {\n";
for (const k of Object.keys(EV).sort()) {
	const e = EV[k];
	gd += `\t"${k}": {"break": "${e.break}", "step": "${e.step}", "place": "${e.place}", "hit": "${e.hit}", "fall": "${e.fall}"},\n`;
}
gd += "}\n";
fs.writeFileSync(outPath, gd);
console.log("block ids", ids.length, "mapped", Object.keys(typeOf).length, "unmapped", unmapped.length);
if (unresolved.length) console.log("wiki names not found in en_us.json:\n  " + unresolved.join("\n  "));
if (conflicts.length) console.log("listed under two types (first kept):\n  " + conflicts.join("\n  "));
console.log("unmapped ids:\n  " + unmapped.map(i => i + " (" + (lang["block.minecraft." + i] || "-") + ")").join("\n  "));
