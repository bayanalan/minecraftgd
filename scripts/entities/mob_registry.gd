## MobRegistry — data records for living mobs: stats, hitbox, category, behaviour archetype, drops table,
## sounds prefix, texture and an ORIGINAL box-rig definition (part boxes with Java-style box UV offsets,
## pivots and dimensions documented from reference observation; source D). Unlisted mobs use a generic
## quadruped/humanoid rig with their own texture and are reported in docs/MOB_PARITY.md as "visible".
## Contract: get_def(id) -> Dictionary; ALL lists every 26.3 living mob id in scope.
class_name MobRegistry

const ALL := ["allay", "armadillo", "axolotl", "bat", "camel", "camel_husk", "cat", "chicken", "cod", "copper_golem", "cow", "donkey",
	"frog", "glow_squid", "happy_ghast", "horse", "mooshroom", "mule", "ocelot", "parrot", "pig", "rabbit", "salmon", "sheep",
	"skeleton_horse", "sniffer", "snow_golem", "squid", "strider", "sulfur_cube", "tadpole", "tropical_fish", "turtle", "villager",
	"wandering_trader", "zombie_horse", "bee", "cave_spider", "dolphin", "drowned", "enderman", "fox", "goat", "iron_golem", "llama",
	"nautilus", "panda", "piglin", "polar_bear", "pufferfish", "spider", "trader_llama", "wolf", "zombie_nautilus", "zombified_piglin",
	"blaze", "bogged", "breeze", "creaking", "creeper", "elder_guardian", "endermite", "evoker", "ghast", "guardian", "hoglin", "husk",
	"magma_cube", "parched", "phantom", "piglin_brute", "pillager", "ravager", "shulker", "silverfish", "skeleton", "slime", "stray",
	"vex", "vindicator", "warden", "witch", "wither_skeleton", "zoglin", "zombie", "zombie_villager", "ender_dragon", "wither", "giant", "illusioner"]

# part: [name, pivot(x,y,z) in model px (Y down), box origin offset, size, uv, rot_x_deg]
const QUAD_BODY_ROT := 90.0

const DEFS := {
	"pig": {"hp": 10, "speed": 0.25, "w": 0.9, "h": 0.9, "kind": "passive", "tex": "entity/pig/pig_temperate", "tex_size": [64, 64], "food": ["carrot", "potato", "beetroot"], "xp": [1, 3],
		"parts": [["head", [0, 12, -6], [-4, -4, -8], [8, 8, 8], [0, 0], 0], ["snout", [0, 12, -6], [-2, 0, -9], [4, 3, 1], [16, 16], 0],
			["body", [0, 11, 2], [-5, -10, -7], [10, 16, 8], [28, 8], 90], ["leg0", [-3, 18, 7], [-2, 0, -2], [4, 6, 4], [0, 16], 0],
			["leg1", [3, 18, 7], [-2, 0, -2], [4, 6, 4], [0, 16], 0], ["leg2", [-3, 18, -5], [-2, 0, -2], [4, 6, 4], [0, 16], 0], ["leg3", [3, 18, -5], [-2, 0, -2], [4, 6, 4], [0, 16], 0]]},
	"cow": {"hp": 10, "speed": 0.2, "w": 0.9, "h": 1.4, "kind": "passive", "tex": "entity/cow/cow_temperate", "tex_size": [64, 64], "food": ["wheat"], "xp": [1, 3],
		"parts": [["head", [0, 4, -8], [-4, -4, -6], [8, 8, 6], [0, 0], 0], ["horn0", [0, 4, -8], [-5, -5, -4], [1, 3, 1], [22, 0], 0], ["horn1", [0, 4, -8], [4, -5, -4], [1, 3, 1], [22, 0], 0],
			["body", [0, 5, 2], [-6, -10, -7], [12, 18, 10], [18, 4], 90], ["udder", [0, 5, 2], [-2, 2, -8], [4, 6, 1], [52, 0], 90],
			["leg0", [-4, 12, 7], [-2, 0, -2], [4, 12, 4], [0, 16], 0], ["leg1", [4, 12, 7], [-2, 0, -2], [4, 12, 4], [0, 16], 0],
			["leg2", [-4, 12, -6], [-2, 0, -2], [4, 12, 4], [0, 16], 0], ["leg3", [4, 12, -6], [-2, 0, -2], [4, 12, 4], [0, 16], 0]]},
	"sheep": {"hp": 8, "speed": 0.23, "w": 0.9, "h": 1.3, "kind": "passive", "tex": "entity/sheep/sheep", "tex_size": [64, 32], "food": ["wheat"], "xp": [1, 3],
		"parts": [["head", [0, 6, -8], [-3, -4, -6], [6, 6, 8], [0, 0], 0], ["body", [0, 5, 2], [-4, -10, -7], [8, 16, 6], [28, 8], 90],
			["leg0", [-3, 12, 7], [-2, 0, -2], [4, 12, 4], [0, 16], 0], ["leg1", [3, 12, 7], [-2, 0, -2], [4, 12, 4], [0, 16], 0],
			["leg2", [-3, 12, -5], [-2, 0, -2], [4, 12, 4], [0, 16], 0], ["leg3", [3, 12, -5], [-2, 0, -2], [4, 12, 4], [0, 16], 0]]},
	"chicken": {"hp": 4, "speed": 0.25, "w": 0.4, "h": 0.7, "baby_w": 0.3, "baby_h": 0.4, "kind": "passive", "tex": "entity/chicken/chicken_temperate", "tex_size": [64, 32], "food": ["wheat_seeds", "melon_seeds", "pumpkin_seeds", "beetroot_seeds", "torchflower_seeds", "pitcher_pod"], "xp": [1, 3],
		"parts": [["head", [0, 15, -4], [-2, -6, -2], [4, 6, 3], [0, 0], 0], ["bill", [0, 15, -4], [-2, -4, -4], [4, 2, 2], [14, 0], 0], ["chin", [0, 15, -4], [-1, -2, -3], [2, 2, 2], [14, 4], 0],
			["body", [0, 16, 0], [-3, -4, -3], [6, 8, 6], [0, 9], 90], ["leg0", [-2, 19, 1], [-1, 0, -3], [3, 5, 3], [26, 0], 0], ["leg1", [1, 19, 1], [-1, 0, -3], [3, 5, 3], [26, 0], 0],
			["wing0", [-4, 13, 0], [0, 0, -3], [1, 4, 6], [24, 13], 0], ["wing1", [4, 13, 0], [-1, 0, -3], [1, 4, 6], [24, 13], 0]]},
	# wiki (Attribute / Hitbox / Zombie): zombie types armor 2, follow range 35, baby hitbox 0.49 x 0.98, baby zombie
	# speed 0.345; drowned step height 1
	"zombie": {"hp": 20, "speed": 0.23, "baby_speed": 0.345, "w": 0.6, "h": 1.95, "baby_w": 0.49, "baby_h": 0.98, "kind": "hostile", "tex": "entity/zombie/zombie", "tex_size": [64, 64], "attack": 3.0, "armor_points": 2, "follow_range": 35.0, "burns": true, "xp": [5, 5], "rig": "humanoid"},
	"husk": {"hp": 20, "speed": 0.23, "baby_speed": 0.345, "w": 0.6, "h": 1.95, "baby_w": 0.49, "baby_h": 0.98, "kind": "hostile", "tex": "entity/zombie/husk", "tex_size": [64, 64], "attack": 3.0, "armor_points": 2, "follow_range": 35.0, "xp": [5, 5], "rig": "humanoid"},
	"drowned": {"hp": 20, "speed": 0.23, "baby_speed": 0.345, "w": 0.6, "h": 1.95, "baby_w": 0.49, "baby_h": 0.98, "kind": "hostile", "tex": "entity/zombie/drowned", "tex_size": [64, 64], "attack": 3.0, "armor_points": 2, "follow_range": 35.0, "step_height": 1.0, "burns": true, "xp": [5, 5], "rig": "humanoid"},
	"skeleton": {"hp": 20, "speed": 0.25, "w": 0.6, "h": 1.99, "kind": "hostile", "tex": "entity/skeleton/skeleton", "tex_size": [64, 32], "attack": 2.0, "ranged": true, "burns": true, "xp": [5, 5], "rig": "skeleton"},
	"stray": {"hp": 20, "speed": 0.25, "w": 0.6, "h": 1.99, "kind": "hostile", "tex": "entity/skeleton/stray", "tex_size": [64, 32], "attack": 2.0, "ranged": true, "burns": true, "xp": [5, 5], "rig": "skeleton"},
	"creeper": {"hp": 20, "speed": 0.25, "w": 0.6, "h": 1.7, "kind": "hostile", "tex": "entity/creeper/creeper", "tex_size": [64, 32], "explodes": true, "xp": [5, 5],
		"parts": [["head", [0, 6, 0], [-4, -8, -4], [8, 8, 8], [0, 0], 0], ["body", [0, 6, 0], [-4, 0, -2], [8, 12, 4], [16, 16], 0],
			["leg0", [-2, 18, 4], [-2, 0, -2], [4, 6, 4], [0, 16], 0], ["leg1", [2, 18, 4], [-2, 0, -2], [4, 6, 4], [0, 16], 0],
			["leg2", [-2, 18, -4], [-2, 0, -2], [4, 6, 4], [0, 16], 0], ["leg3", [2, 18, -4], [-2, 0, -2], [4, 6, 4], [0, 16], 0]]},
	"spider": {"hp": 16, "speed": 0.3, "w": 1.4, "h": 0.9, "kind": "hostile", "tex": "entity/spider/spider", "tex_size": [64, 32], "attack": 2.0, "climbs": true, "xp": [5, 5],
		"parts": [["head", [0, 15, -3], [-4, -4, -8], [8, 8, 8], [32, 4], 0], ["neck", [0, 15, 0], [-3, -3, -3], [6, 6, 6], [0, 0], 0], ["body", [0, 15, 9], [-5, -4, -6], [10, 8, 12], [0, 12], 0],
			["leg0", [-4, 15, 2], [-15, -1, -1], [16, 2, 2], [18, 0], 0], ["leg1", [4, 15, 2], [-1, -1, -1], [16, 2, 2], [18, 0], 0],
			["leg2", [-4, 15, 1], [-15, -1, -1], [16, 2, 2], [18, 0], 0], ["leg3", [4, 15, 1], [-1, -1, -1], [16, 2, 2], [18, 0], 0],
			["leg4", [-4, 15, 0], [-15, -1, -1], [16, 2, 2], [18, 0], 0], ["leg5", [4, 15, 0], [-1, -1, -1], [16, 2, 2], [18, 0], 0],
			["leg6", [-4, 15, -1], [-15, -1, -1], [16, 2, 2], [18, 0], 0], ["leg7", [4, 15, -1], [-1, -1, -1], [16, 2, 2], [18, 0], 0]]},
	"cave_spider": {"hp": 12, "speed": 0.3, "w": 0.7, "h": 0.5, "kind": "hostile", "tex": "entity/spider/cave_spider", "tex_size": [64, 32], "attack": 2.0, "climbs": true, "xp": [5, 5], "rig_of": "spider", "scale": 0.7},
}

const HUMANOID := [["head", [0, 0, 0], [-4, -8, -4], [8, 8, 8], [0, 0], 0], ["body", [0, 0, 0], [-4, 0, -2], [8, 12, 4], [16, 16], 0],
	["arm0", [-5, 2, 0], [-3, -2, -2], [4, 12, 4], [40, 16], 0], ["arm1", [5, 2, 0], [-1, -2, -2], [4, 12, 4], [40, 16], 0],
	["leg0", [-1.9, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 16], 0], ["leg1", [1.9, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 16], 0]]
const SKELETON := [["head", [0, 0, 0], [-4, -8, -4], [8, 8, 8], [0, 0], 0], ["body", [0, 0, 0], [-4, 0, -2], [8, 12, 4], [16, 16], 0],
	["arm0", [-5, 2, 0], [-1, -2, -1], [2, 12, 2], [40, 16], 0], ["arm1", [5, 2, 0], [-1, -2, -1], [2, 12, 2], [40, 16], 0],
	["leg0", [-2, 12, 0], [-1, 0, -1], [2, 12, 2], [0, 16], 0], ["leg1", [2, 12, 0], [-1, 0, -1], [2, 12, 2], [0, 16], 0]]
const QUADRUPED := [["head", [0, 12, -6], [-4, -4, -8], [8, 8, 8], [0, 0], 0], ["body", [0, 11, 2], [-5, -10, -7], [10, 16, 8], [28, 8], 90],
	["leg0", [-3, 18, 7], [-2, 0, -2], [4, 6, 4], [0, 16], 0], ["leg1", [3, 18, 7], [-2, 0, -2], [4, 6, 4], [0, 16], 0],
	["leg2", [-3, 18, -5], [-2, 0, -2], [4, 6, 4], [0, 16], 0], ["leg3", [3, 18, -5], [-2, 0, -2], [4, 6, 4], [0, 16], 0]]


## Nether / End mobs (rigs from the Java model layouts, source D; behaviour flags drive EntityManager AI).
## Extra part fields: [6] = rot_z degrees. Flags: fire_immune, flies, hover_y, fireball (small|large), neutral,
## group_anger, teleports, splits, size (slime scale), lava_walker, water_hurts, spawn (on_ground|in_lava|in_water|air).
const DEFS2 := {
	# wiki (Zombified Piglin / Piglin Brute): fixed-weapon attack = Normal damage with the weapon (golden sword 8,
	# golden axe 13); zombified piglin armor 2, follow range 35; piglin brute follow range 12; babies 0.49 x 0.98
	"zombified_piglin": {"hp": 20, "speed": 0.23, "baby_speed": 0.345, "w": 0.6, "h": 1.95, "baby_w": 0.49, "baby_h": 0.98, "kind": "hostile", "neutral": true, "group_anger": true, "tex": "entity/piglin/zombified_piglin", "tex_size": [64, 64], "attack": 8.0, "armor_points": 2, "follow_range": 35.0, "fire_immune": true, "xp": [5, 5], "rig": "piglin"},
	"piglin": {"hp": 16, "speed": 0.35, "w": 0.6, "h": 1.95, "baby_w": 0.49, "baby_h": 0.98, "kind": "hostile", "gold_peace": true, "tex": "entity/piglin/piglin", "tex_size": [64, 64], "attack": 5.0, "xp": [5, 5], "rig": "piglin"},
	"piglin_brute": {"hp": 50, "speed": 0.35, "w": 0.6, "h": 1.95, "kind": "hostile", "tex": "entity/piglin/piglin_brute", "tex_size": [64, 64], "attack": 13.0, "follow_range": 12.0, "xp": [20, 20], "rig": "piglin"},
	# wiki (Attribute): ghast movement speed 0.7 (unused: _ghast flies with its own constants), flying speed 0.06,
	# follow range 100; blaze follow range 48
	"ghast": {"hp": 10, "speed": 0.7, "fly_speed": 0.06, "follow_range": 100.0, "w": 4.0, "h": 4.0, "kind": "hostile", "flies": true, "fireball": "large", "fire_immune": true, "tex": "entity/ghast/ghast", "tex_size": [64, 32], "scale": 4.5, "xp": [5, 5], "spawn": "on_ground", "spawn_chance": 0.05, "rig": "ghast"},
	"blaze": {"hp": 20, "speed": 0.23, "follow_range": 48.0, "w": 0.6, "h": 1.8, "kind": "hostile", "flies": true, "hover_y": 2.5, "fireball": "small", "fire_immune": true, "water_hurts": true, "tex": "entity/blaze/blaze", "tex_size": [64, 32], "attack": 6.0, "xp": [10, 10], "rig": "blaze"},
	# wiki (Hitbox / Magma Cube): big cube 2.0808 wide x 2.08 tall (0.5202 / 0.52 per size); magma cube armor 3 per size
	"magma_cube": {"hp": 16, "speed": 0.2, "w": 2.0808, "h": 2.08, "kind": "hostile", "hops": true, "splits": true, "size": 4, "armor_points": 12, "fire_immune": true, "tex": "entity/slime/magmacube", "tex_size": [64, 32], "attack": 6.0, "xp": [4, 4], "rig": "magma_cube"},
	"slime": {"hp": 16, "speed": 0.2, "w": 2.0808, "h": 2.08, "kind": "hostile", "hops": true, "splits": true, "size": 4, "tex": "entity/slime/slime", "tex_size": [64, 32], "attack": 4.0, "xp": [4, 4], "rig": "slime"},
	"wither_skeleton": {"hp": 20, "speed": 0.25, "w": 0.7, "h": 2.4, "kind": "hostile", "fire_immune": true, "wither_hit": true, "tex": "entity/skeleton/wither_skeleton", "tex_size": [64, 32], "attack": 8.0, "scale": 1.2, "xp": [5, 5], "rig": "skeleton"},
	# wiki (Attribute / Hitbox / Zoglin): knockback resistance 0.6, attack knockback 1, baby hoglin 0.75 x 0.85, zoglins
	# immune to fire
	"hoglin": {"hp": 40, "speed": 0.3, "w": 1.3965, "h": 1.4, "baby_w": 0.75, "baby_h": 0.85, "kind": "hostile", "tex": "entity/hoglin/hoglin", "tex_size": [128, 64], "attack": 6.0, "attack_knockback": 1.0, "knockback_resistance": 0.6, "food": ["crimson_fungus"], "xp": [5, 5], "rig": "hoglin"},
	"zoglin": {"hp": 40, "speed": 0.3, "w": 1.3965, "h": 1.4, "kind": "hostile", "fire_immune": true, "tex": "entity/hoglin/zoglin", "tex_size": [128, 64], "attack": 6.0, "attack_knockback": 1.0, "knockback_resistance": 0.6, "xp": [5, 5], "rig": "hoglin"},
	"strider": {"hp": 20, "speed": 0.175, "w": 0.9, "h": 1.7, "kind": "passive", "lava_walker": true, "fire_immune": true, "water_hurts": true, "food": ["warped_fungus"], "tempt": ["warped_fungus_on_a_stick"], "tex": "entity/strider/strider", "tex_size": [64, 128], "xp": [1, 3], "spawn": "in_lava", "rig": "strider"},
	"enderman": {"hp": 40, "speed": 0.3, "follow_range": 64.0, "step_height": 1.0, "w": 0.6, "h": 2.9, "kind": "hostile", "neutral": true, "teleports": true, "water_hurts": true, "tex": "entity/enderman/enderman", "tex_size": [64, 32], "attack": 7.0, "xp": [5, 5], "rig": "enderman"},
	"endermite": {"hp": 8, "speed": 0.25, "w": 0.4, "h": 0.3, "kind": "hostile", "tex": "entity/endermite/endermite", "tex_size": [64, 32], "attack": 2.0, "xp": [3, 3], "rig": "endermite"},
	# wiki (Attribute): shulker / ender dragon movement speed 0.7 (unused: stationary / DragonFight); enderman follow
	# range 64, step height 1
	"shulker": {"hp": 30, "speed": 0.7, "w": 1.0, "h": 1.0, "kind": "hostile", "stationary": true, "shoots": "shulker_bullet", "teleports": true, "tex": "entity/shulker/shulker", "tex_size": [64, 64], "xp": [5, 5], "rig": "shulker"},
	"ender_dragon": {"hp": 200, "speed": 0.7, "w": 5.0, "h": 3.0, "kind": "hostile", "boss": true, "dragon": true, "flies": true, "fire_immune": true, "tex": "entity/enderdragon/dragon", "tex_size": [256, 256], "xp": [0, 0], "rig": "dragon",
		"children": {"wing1": "wing0", "wing4": "wing0", "wing6": "wing4", "wing3": "wing2", "wing5": "wing2", "wing7": "wing5", "jaw": "head", "lip": "head"}},
	"end_crystal": {"hp": 1, "speed": 0.0, "w": 2.0, "h": 2.0, "kind": "passive", "stationary": true, "crystal": true, "fire_immune": true, "tex": "entity/end_crystal/end_crystal", "tex_size": [64, 32], "xp": [0, 0], "rig": "crystal"},
	"silverfish": {"hp": 8, "speed": 0.25, "w": 0.4, "h": 0.3, "kind": "hostile", "tex": "entity/silverfish/silverfish", "tex_size": [64, 32], "attack": 1.0, "xp": [5, 5], "rig": "endermite"},
}

const PIGLIN := [["head", [0, 0, 0], [-5, -8, -4], [10, 8, 8], [0, 0], 0], ["nose", [0, 0, 0], [-2, -4, -5], [4, 4, 1], [31, 1], 0],
	["ear0", [-4.5, -6, 0], [-1, 0, -2], [1, 5, 4], [39, 6], 0, 30], ["ear1", [4.5, -6, 0], [0, 0, -2], [1, 5, 4], [51, 6], 0, -30],
	["body", [0, 0, 0], [-4, 0, -2], [8, 12, 4], [16, 16], 0], ["arm0", [-5, 2, 0], [-3, -2, -2], [4, 12, 4], [40, 16], 0],
	["arm1", [5, 2, 0], [-1, -2, -2], [4, 12, 4], [32, 48], 0], ["leg0", [-1.9, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 16], 0],
	["leg1", [1.9, 12, 0], [-2, 0, -2], [4, 12, 4], [16, 48], 0]]
const BLAZE := [["head", [0, 0, 0], [-4, -4, -4], [8, 8, 8], [0, 0], 0],
	["rodA0", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0], ["rodA1", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0], ["rodA2", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0], ["rodA3", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0],
	["rodB0", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0], ["rodB1", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0], ["rodB2", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0], ["rodB3", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0],
	["rodC0", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0], ["rodC1", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0], ["rodC2", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0], ["rodC3", [0, 0, 0], [0, 0, 0], [2, 8, 2], [0, 16], 0]]
const MAGMA := [["cube0", [0, 0, 0], [-4, 16, -4], [8, 1, 8], [0, 0], 0], ["cube1", [0, 0, 0], [-4, 17, -4], [8, 1, 8], [0, 1], 0],
	["cube2", [0, 0, 0], [-4, 18, -4], [8, 1, 8], [24, 10], 0], ["cube3", [0, 0, 0], [-4, 19, -4], [8, 1, 8], [24, 19], 0],
	["cube4", [0, 0, 0], [-4, 20, -4], [8, 1, 8], [0, 4], 0], ["cube5", [0, 0, 0], [-4, 21, -4], [8, 1, 8], [0, 5], 0],
	["cube6", [0, 0, 0], [-4, 22, -4], [8, 1, 8], [0, 6], 0], ["cube7", [0, 0, 0], [-4, 23, -4], [8, 1, 8], [0, 7], 0],
	["core", [0, 0, 0], [-2, 18, -2], [4, 4, 4], [0, 16], 0]]
const SLIME := [["inner", [0, 0, 0], [-3, 17, -3], [6, 6, 6], [0, 16], 0], ["eye0", [0, 0, 0], [-3.25, 18, -3.5], [2, 2, 2], [32, 0], 0],
	["eye1", [0, 0, 0], [1.25, 18, -3.5], [2, 2, 2], [32, 4], 0], ["mouth", [0, 0, 0], [0, 21, -3.5], [1, 1, 1], [32, 8], 0],
	["outer", [0, 0, 0], [-4, 16, -4], [8, 8, 8], [0, 0], 0]]
const ENDERMAN := [["head", [0, -14, 0], [-4, -8, -4], [8, 8, 8], [0, 0], 0], ["body", [0, -14, 0], [-4, 0, -2], [8, 12, 4], [32, 16], 0],
	["arm0", [-5, -12, 0], [-1, -2, -1], [2, 30, 2], [56, 0], 0], ["arm1", [5, -12, 0], [-1, -2, -1], [2, 30, 2], [56, 0], 0],
	["leg0", [-2, -6, 0], [-1, 0, -1], [2, 30, 2], [56, 0], 0], ["leg1", [2, -6, 0], [-1, 0, -1], [2, 30, 2], [56, 0], 0]]
const HOGLIN := [["body", [0, 7, 0], [-8, -7, -13], [16, 14, 26], [1, 1], 0], ["head", [0, 2, -12], [-7, -3, -19], [14, 6, 19], [61, 1], 50],
	["leg0", [-4, 10, -8.5], [-3, 0, -3], [6, 14, 6], [66, 42], 0], ["leg1", [4, 10, -8.5], [-3, 0, -3], [6, 14, 6], [41, 42], 0],
	["leg2", [-5, 13, 10], [-2.5, 0, -2.5], [5, 11, 5], [21, 45], 0], ["leg3", [5, 13, 10], [-2.5, 0, -2.5], [5, 11, 5], [0, 45], 0]]
const STRIDER := [["body", [0, 1, 0], [-8, -6, -8], [16, 14, 16], [0, 0], 0],
	["leg0", [-4, 8, 0], [-2, 0, -2], [4, 16, 4], [0, 32], 0], ["leg1", [4, 8, 0], [-2, 0, -2], [4, 16, 4], [0, 55], 0]]
const SHULKER := [["base", [0, 24, 0], [-8, -8, -8], [16, 8, 16], [0, 28], 0], ["lid", [0, 24, 0], [-8, -16, -8], [16, 12, 16], [0, 0], 0],
	["shead", [0, 12, 0], [-3, 0, -3], [6, 6, 6], [0, 52], 0]]
const ENDERMITE := [["seg0", [0, 21, -3.5], [-2, 0, -1], [4, 3, 2], [0, 0], 0], ["seg1", [0, 20, -1], [-3, 0, -2.5], [6, 4, 5], [0, 5], 0],
	["seg2", [0, 21, 2.5], [-1.5, 0, -0.5], [3, 3, 1], [0, 14], 0], ["seg3", [0, 22, 3.5], [-0.5, 0, -0.5], [1, 2, 1], [0, 18], 0]]


## Java PlayerModel (wide arms, 64x64 skin): base parts + hat overlay.
## Java PlayerModel (wide arms): base boxes + second skin layers (index 9: [name, origin, size, uv, inflate]) - hat
## inflated 0.5, jacket / sleeves / pants 0.25 - toggled by Skin Customization (EntityRenderer.apply_skin_parts).
const PLAYER := [["head", [0, 0, 0], [-4, -8, -4], [8, 8, 8], [0, 0], 0], ["hat", [0, 0, 0], [-4, -8, -4], [8, 8, 8], [32, 0], 0, 0, 0, 0.5],
	["body", [0, 0, 0], [-4, 0, -2], [8, 12, 4], [16, 16], 0, 0, 0, 0.0, [["jacket", [-4, 0, -2], [8, 12, 4], [16, 32], 0.25]]],
	["arm0", [-5, 2, 0], [-3, -2, -2], [4, 12, 4], [40, 16], 0, 0, 0, 0.0, [["right_sleeve", [-3, -2, -2], [4, 12, 4], [40, 32], 0.25]]],
	["arm1", [5, 2, 0], [-1, -2, -2], [4, 12, 4], [32, 48], 0, 0, 0, 0.0, [["left_sleeve", [-1, -2, -2], [4, 12, 4], [48, 48], 0.25]]],
	["leg0", [-1.9, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 16], 0, 0, 0, 0.0, [["right_pants_leg", [-2, 0, -2], [4, 12, 4], [0, 32], 0.25]]],
	["leg1", [1.9, 12, 0], [-2, 0, -2], [4, 12, 4], [16, 48], 0, 0, 0, 0.0, [["left_pants_leg", [-2, 0, -2], [4, 12, 4], [0, 48], 0.25]]]]


const CRYSTAL := [["base", [0, 24, 0], [-6, -4, -6], [12, 4, 12], [0, 16], 0], ["glass", [0, 4, 0], [-4, -4, -4], [8, 8, 8], [0, 0], 0],
	["cube", [0, 4, 0], [-3, -3, -3], [6, 6, 6], [32, 0], 0]]


## EnderDragonModel laid out in a static flight pose (neck/tail segments are separate parts; source D).
static func dragon_parts() -> Array:
	var parts: Array = [["body", [0, 4, 8], [-12, 0, -16], [24, 24, 64], [0, 0], 0]]
	for i in 5:
		parts.append(["neck%d" % i, [0, 10, -13 - 10 * i], [-5, -5, -5], [10, 10, 10], [192, 104], 0])
	parts.append(["head", [0, 10, -63], [-8, -8, -10], [16, 16, 16], [112, 30], 0])
	parts.append(["lip", [0, 10, -63], [-6, -1, -24], [12, 5, 16], [176, 44], 0])
	parts.append(["jaw", [0, 14, -71], [-6, 0, -16], [12, 4, 16], [176, 65], 0])
	for j in 12:
		parts.append(["tail%d" % j, [0, 10, 61 + 10 * j], [-5, -5, -5], [10, 10, 10], [192, 104], 0])
	parts.append(["wing0", [12, 5, 2], [0, -4, -4], [56, 8, 8], [112, 88], 0])
	parts.append(["wing1", [12, 5, 2], [0, 0, 2], [56, 0, 56], [-56, 88], 0])
	parts.append(["wing2", [-12, 5, 2], [-56, -4, -4], [56, 8, 8], [112, 88], 0])
	parts.append(["wing3", [-12, 5, 2], [-56, 0, 2], [56, 0, 56], [-56, 88], 0])
	parts.append(["wing4", [68, 5, 2], [0, -2, -2], [56, 4, 4], [112, 136], 0])
	parts.append(["wing5", [-68, 5, 2], [-56, -2, -2], [56, 4, 4], [112, 136], 0])
	parts.append(["wing6", [68, 5, 2], [0, 0, 2], [56, 0, 56], [-56, 144], 0])    # Java wing tip membranes
	parts.append(["wing7", [-68, 5, 2], [-56, 0, 2], [56, 0, 56], [-56, 144], 0])
	parts.append(["leg0", [12, 20, 2], [-4, -4, -4], [8, 24, 8], [112, 104], 0])
	parts.append(["leg1", [-12, 20, 2], [-4, -4, -4], [8, 24, 8], [112, 104], 0])
	parts.append(["leg2", [16, 16, 42], [-8, -4, -8], [16, 32, 16], [0, 0], 0])
	parts.append(["leg3", [-16, 16, 42], [-8, -4, -8], [16, 32, 16], [0, 0], 0])
	return parts


## Java GhastModel: 16^3 body + 9 tentacles whose lengths come from RandomSource.create(1660L).nextInt(7) + 8.
static func ghast_parts() -> Array:
	var parts: Array = [["body", [0, 17.6, 0], [-8, -8, -8], [16, 16, 16], [0, 0], 0]]
	var r := RandomSources.LegacyRandom.new(1660)
	for i in 9:
		var fx := ((float(i % 3) - float(i / 3 % 2) * 0.5 + 0.25) / 2.0 * 2.0 - 1.0) * 5.0
		var fz := (float(i / 3) / 2.0 * 2.0 - 1.0) * 5.0
		var ln := r.next_int_bound(7) + 8
		parts.append(["tent%d" % i, [fx, 24.6, fz], [-1, 0, -1], [2, ln, 2], [0, 0], 0])
	return parts


static func has_def(id: String) -> bool:
	return DEFS.has(id) or DEFS2.has(id) or MobRegistryOverworld.DEFS.has(id)


static func implemented() -> PackedStringArray:
	var out := PackedStringArray(DEFS.keys())
	out.append_array(PackedStringArray(DEFS2.keys()))
	out.append_array(PackedStringArray(MobRegistryOverworld.DEFS.keys()))
	return out


## Mob definition: stats + rig. Rigs transcribed from Java's model layer definitions (MobRigs) replace the older
## approximations / borrowed rigs (and their compensating scale factors).
static func get_def(id: String) -> Dictionary:
	var d := _get_def_base(id)
	if d.is_empty():
		return d
	if id == "mooshroom":
		var mb: Array = []
		for bl in MobRigs.MOOSHROOM_BLOCKS:
			var b2: Dictionary = (bl as Dictionary).duplicate()
			b2["state"] = "brown_mushroom" if str(d.get("tex", "")).ends_with("brown") else "red_mushroom"
			mb.append(b2)
		d["block_layers"] = mb
	var r := MobRigs.rig(id)
	if not r.is_empty():
		for k in r:
			d[k] = r[k]
		if not r.has("scale") and id in ["armadillo", "sniffer", "copper_golem", "breeze", "camel", "camel_husk"]:
			d.erase("scale")
	return d


static func _get_def_base(id: String) -> Dictionary:
	if MobRegistryOverworld.DEFS.has(id):
		var d3: Dictionary = MobRegistryOverworld.DEFS[id].duplicate()
		if d3.has("rig_of"):
			d3["parts"] = DEFS[d3["rig_of"]]["parts"]
		elif not d3.has("parts"):
			match str(d3.get("rig", "humanoid")):
				"ghast":
					d3["parts"] = ghast_parts()
				"slime":
					d3["parts"] = SLIME
				"skeleton":
					d3["parts"] = SKELETON
				_:
					d3["parts"] = HUMANOID
		return d3
	if DEFS2.has(id):
		var d2: Dictionary = DEFS2[id].duplicate()
		match str(d2.get("rig", "")):
			"piglin":
				d2["parts"] = PIGLIN
			"ghast":
				d2["parts"] = ghast_parts()
			"blaze":
				d2["parts"] = BLAZE
			"magma_cube":
				d2["parts"] = MAGMA
			"slime":
				d2["parts"] = SLIME
			"skeleton":
				d2["parts"] = SKELETON
			"hoglin":
				d2["parts"] = HOGLIN
			"strider":
				d2["parts"] = STRIDER
			"enderman":
				d2["parts"] = ENDERMAN
			"shulker":
				d2["parts"] = SHULKER
			"endermite":
				d2["parts"] = ENDERMITE
			"dragon":
				d2["parts"] = dragon_parts()
			"crystal":
				d2["parts"] = CRYSTAL
			_:
				d2["parts"] = HUMANOID
		return d2
	if DEFS.has(id):
		var d: Dictionary = DEFS[id].duplicate()
		if d.has("rig_of"):
			d["parts"] = DEFS[d["rig_of"]]["parts"]
		elif not d.has("parts"):
			d["parts"] = SKELETON if d.get("rig", "") == "skeleton" else HUMANOID
		return d
	return {}
