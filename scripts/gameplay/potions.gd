## Potions — Java PotionBrewing mixes (source D) and potion effect definitions; brewing stand step (fuel: blaze
## powder = 20 brews, 400 ticks per brew), drinking, splash (4-block radius, distance-scaled), lingering clouds.
## Potion stacks: item potion / splash_potion / lingering_potion with components
## {"minecraft:potion_contents": {"potion": "minecraft:<id>"}}.
## Contract: brew_result(bottle, ingredient) -> ItemStack or null; apply(player, potion_id, scale); step(be).
class_name Potions
extends RefCounted

# potion id -> [[effect, amplifier, ticks], ...]
const EFFECTS := {
	"night_vision": [["night_vision", 0, 3600]], "long_night_vision": [["night_vision", 0, 9600]],
	"invisibility": [["invisibility", 0, 3600]], "long_invisibility": [["invisibility", 0, 9600]],
	"leaping": [["jump_boost", 0, 3600]], "long_leaping": [["jump_boost", 0, 9600]], "strong_leaping": [["jump_boost", 1, 1800]],
	"fire_resistance": [["fire_resistance", 0, 3600]], "long_fire_resistance": [["fire_resistance", 0, 9600]],
	"swiftness": [["speed", 0, 3600]], "long_swiftness": [["speed", 0, 9600]], "strong_swiftness": [["speed", 1, 1800]],
	"slowness": [["slowness", 0, 1800]], "long_slowness": [["slowness", 0, 4800]], "strong_slowness": [["slowness", 3, 400]],
	"turtle_master": [["slowness", 3, 400], ["resistance", 2, 400]], "long_turtle_master": [["slowness", 3, 800], ["resistance", 2, 800]],
	"strong_turtle_master": [["slowness", 5, 400], ["resistance", 3, 400]],
	"water_breathing": [["water_breathing", 0, 3600]], "long_water_breathing": [["water_breathing", 0, 9600]],
	"healing": [["instant_health", 0, 1]], "strong_healing": [["instant_health", 1, 1]],
	"harming": [["instant_damage", 0, 1]], "strong_harming": [["instant_damage", 1, 1]],
	"poison": [["poison", 0, 900]], "long_poison": [["poison", 0, 1800]], "strong_poison": [["poison", 1, 432]],
	"regeneration": [["regeneration", 0, 900]], "long_regeneration": [["regeneration", 0, 1800]], "strong_regeneration": [["regeneration", 1, 450]],
	"strength": [["strength", 0, 3600]], "long_strength": [["strength", 0, 9600]], "strong_strength": [["strength", 1, 1800]],
	"weakness": [["weakness", 0, 1800]], "long_weakness": [["weakness", 0, 4800]],
	"luck": [["luck", 0, 6000]], "slow_falling": [["slow_falling", 0, 1800]], "long_slow_falling": [["slow_falling", 0, 4800]],
	"wind_charged": [["wind_charged", 0, 3600]], "weaving": [["weaving", 0, 3600]], "oozing": [["oozing", 0, 3600]], "infested": [["infested", 0, 3600]],
}

# wiki Effect colors (Java): effect -> RGB; potions without effects (water, awkward ...) #385DC6
const EFFECT_COLORS := {
	"speed": 0x33EBFF, "slowness": 0x8BAFE0, "haste": 0xD9C043, "mining_fatigue": 0x4A4217, "strength": 0xFFC700,
	"instant_health": 0xF82423, "instant_damage": 0xA9656A, "jump_boost": 0xFDFF84, "nausea": 0x551D4A, "regeneration": 0xCD5CAB,
	"resistance": 0x9146F0, "fire_resistance": 0xFF9900, "water_breathing": 0x98DAC0, "invisibility": 0xF6F6F6, "blindness": 0x1F1F23,
	"night_vision": 0xC2FF66, "hunger": 0x587653, "weakness": 0x484D48, "poison": 0x87A363, "wither": 0x736156,
	"health_boost": 0xF87D23, "absorption": 0x2552A5, "saturation": 0xF82423, "glowing": 0x94A061, "levitation": 0xCEFFFF,
	"luck": 0x59C106, "unluck": 0xC0A44D, "slow_falling": 0xF3CFB9, "conduit_power": 0x1DC2D1, "dolphins_grace": 0x88A3BE,
	"bad_omen": 0x0B6138, "hero_of_the_village": 0x44FF44, "darkness": 0x292721, "trial_omen": 0x16A6A6, "raid_omen": 0xDE4058,
	"wind_charged": 0xBDC9FF, "weaving": 0x78695A, "oozing": 0x99FFA3, "infested": 0x8C9B8C,
}


## A potion's colour: its effects' colours averaged, weighted by amplifier + 1 (the weighting is not on the wiki: Java
## PotionContents); no effects -> #385DC6 (wiki Effect colors: water bottle).
static func color_of(potion: String) -> Color:
	var efs: Array = EFFECTS.get(potion, [])
	if efs.is_empty():
		return Color8(0x38, 0x5D, 0xC6)
	var acc := Vector3.ZERO
	var wsum := 0.0
	for e in efs:
		var c := int(EFFECT_COLORS.get(str(e[0]), 0x385DC6))
		var wt := float(int(e[1]) + 1)
		acc += Vector3((c >> 16) & 255, (c >> 8) & 255, c & 255) * wt
		wsum += wt
	acc /= wsum * 255.0
	return Color(acc.x, acc.y, acc.z)


## True when every effect of the potion is instant (healing / harming): lingering clouds use the instant potency 1/2,
## otherwise the duration scale 1/4 (wiki Area Effect Cloud).
static func all_instant(potion: String) -> bool:
	var efs: Array = EFFECTS.get(potion, [])
	for e in efs:
		if str(e[0]) != "instant_health" and str(e[0]) != "instant_damage":
			return false
	return not efs.is_empty()


# [from, ingredient, to]
const MIXES := [
	["water", "glowstone_dust", "thick"], ["water", "redstone", "mundane"], ["water", "nether_wart", "awkward"],
	["water", "fermented_spider_eye", "weakness"], ["water", "sugar", "mundane"], ["water", "rabbit_foot", "mundane"],
	["water", "glistering_melon_slice", "mundane"], ["water", "spider_eye", "mundane"], ["water", "ghast_tear", "mundane"],
	["water", "blaze_powder", "mundane"], ["water", "magma_cream", "mundane"], ["water", "breeze_rod", "mundane"],
	["awkward", "breeze_rod", "wind_charged"], ["awkward", "slime_block", "oozing"], ["awkward", "stone", "infested"], ["awkward", "cobweb", "weaving"],
	["awkward", "golden_carrot", "night_vision"], ["night_vision", "redstone", "long_night_vision"],
	["night_vision", "fermented_spider_eye", "invisibility"], ["long_night_vision", "fermented_spider_eye", "long_invisibility"],
	["invisibility", "redstone", "long_invisibility"],
	["awkward", "magma_cream", "fire_resistance"], ["fire_resistance", "redstone", "long_fire_resistance"],
	["awkward", "rabbit_foot", "leaping"], ["leaping", "redstone", "long_leaping"], ["leaping", "glowstone_dust", "strong_leaping"],
	["leaping", "fermented_spider_eye", "slowness"], ["long_leaping", "fermented_spider_eye", "long_slowness"],
	["slowness", "redstone", "long_slowness"], ["slowness", "glowstone_dust", "strong_slowness"],
	["awkward", "turtle_helmet", "turtle_master"], ["turtle_master", "redstone", "long_turtle_master"], ["turtle_master", "glowstone_dust", "strong_turtle_master"],
	["swiftness", "fermented_spider_eye", "slowness"], ["long_swiftness", "fermented_spider_eye", "long_slowness"],
	["awkward", "sugar", "swiftness"], ["swiftness", "redstone", "long_swiftness"], ["swiftness", "glowstone_dust", "strong_swiftness"],
	["awkward", "pufferfish", "water_breathing"], ["water_breathing", "redstone", "long_water_breathing"],
	["awkward", "glistering_melon_slice", "healing"], ["healing", "glowstone_dust", "strong_healing"],
	["healing", "fermented_spider_eye", "harming"], ["strong_healing", "fermented_spider_eye", "strong_harming"],
	["harming", "glowstone_dust", "strong_harming"], ["poison", "fermented_spider_eye", "harming"],
	["long_poison", "fermented_spider_eye", "harming"], ["strong_poison", "fermented_spider_eye", "strong_harming"],
	["awkward", "spider_eye", "poison"], ["poison", "redstone", "long_poison"], ["poison", "glowstone_dust", "strong_poison"],
	["awkward", "ghast_tear", "regeneration"], ["regeneration", "redstone", "long_regeneration"], ["regeneration", "glowstone_dust", "strong_regeneration"],
	["awkward", "blaze_powder", "strength"], ["strength", "redstone", "long_strength"], ["strength", "glowstone_dust", "strong_strength"],
	["weakness", "redstone", "long_weakness"], ["awkward", "phantom_membrane", "slow_falling"], ["slow_falling", "redstone", "long_slow_falling"],
]


## 26.x data-driven brewing (data/minecraft/recipe type minecraft:brewing): [input items, input potions (empty =
## any), reagent items, output item, output potion ("" = keep the input potion)].
static var data_mixes: Array = []


static func add_data_mix(j: Dictionary) -> void:
	var inp: Dictionary = j.get("input", {}) if j.get("input") is Dictionary else {}
	var out: Dictionary = j.get("output", {}) if j.get("output") is Dictionary else {}
	var items := Crafting._ingredient(inp.get("item", inp.get("items", "")))
	var pots := {}
	var pc = inp.get("potion_contents", {})
	if pc is Dictionary:
		var pv = pc.get("potions", pc.get("potion", null))
		if pv is String:
			pots[str(pv).trim_prefix("minecraft:")] = true
		elif pv is Array:
			for v in pv:
				pots[str(v).trim_prefix("minecraft:")] = true
	var opot := ""
	var oc = out.get("components", {})
	if oc is Dictionary and oc.get("minecraft:potion_contents") is Dictionary:
		opot = str(oc["minecraft:potion_contents"].get("potion", "")).trim_prefix("minecraft:")
	data_mixes.append([items, pots, Crafting._ingredient(j.get("reagent", {})), str(out.get("id", "")).trim_prefix("minecraft:"), opot])


static func potion_of(s: ItemStack) -> String:
	var pc = s.components.get("minecraft:potion_contents", {})
	if pc is Dictionary:
		return str(pc.get("potion", "")).trim_prefix("minecraft:")
	return ""


static func make(item: String, potion: String) -> ItemStack:
	var s := ItemStack.named(item, 1)
	s.components["minecraft:potion_contents"] = {"potion": "minecraft:" + potion}
	return s


static func is_bottle(s: ItemStack) -> bool:
	return not s.is_empty() and s.name() in ["potion", "splash_potion", "lingering_potion"]


static func brew_result(bottle: ItemStack, ing: String):
	if not is_bottle(bottle):
		return null
	Crafting.load_all()
	if not data_mixes.is_empty():
		var p0 := potion_of(bottle)
		for m in data_mixes:
			if (m[0] as Dictionary).has(bottle.name()) and ((m[1] as Dictionary).is_empty() or (m[1] as Dictionary).has(p0)) and (m[2] as Dictionary).has(ing):
				return make(str(m[3]) if str(m[3]) != "" else bottle.name(), str(m[4]) if str(m[4]) != "" else p0)
		return null
	if ing == "gunpowder" and bottle.name() == "potion":
		return make("splash_potion", potion_of(bottle))
	if ing == "dragon_breath" and bottle.name() == "splash_potion":
		return make("lingering_potion", potion_of(bottle))
	var p := potion_of(bottle)
	for m in MIXES:
		if m[0] == p and m[1] == ing:
			return make(bottle.name(), m[2])
	return null


## Java BrewingStandBlockEntity.serverTick (one tick).
static func step(d: Dictionary) -> bool:
	var items: Array = d.get("items", [])
	if items.size() < 5:
		items.resize(5)
		for i in 5:
			if items[i] == null:
				items[i] = {}
	var changed := false
	var fuel_st := ItemStack.from_dict(items[4])
	if int(d.get("fuel", 0)) <= 0 and fuel_st.name() == "blaze_powder":
		d["fuel"] = 20
		fuel_st.count -= 1
		items[4] = fuel_st.to_dict() if fuel_st.count > 0 else {}
		changed = true
	var ing := ItemStack.from_dict(items[3])
	var valid := false
	if not ing.is_empty():
		for i in 3:
			if brew_result(ItemStack.from_dict(items[i]), ing.name()) != null:
				valid = true
	var t := int(d.get("brew", 0))
	if t > 0:
		t -= 1
		if t == 0 and valid:
			for i in 3:
				var r = brew_result(ItemStack.from_dict(items[i]), ing.name())
				if r != null:
					items[i] = (r as ItemStack).to_dict()
			ing.count -= 1
			items[3] = ing.to_dict() if ing.count > 0 else ({} if ing.name() != "dragon_breath" else {})
			changed = true
		elif not valid or ing.name() != str(d.get("brewing_item", "")):
			t = 0
		d["brew"] = t
		changed = true
	elif valid and int(d.get("fuel", 0)) > 0:
		d["fuel"] = int(d["fuel"]) - 1
		d["brew"] = 400
		d["brewing_item"] = ing.name()
		changed = true
	d["items"] = items
	return changed


## Apply a potion's effects (scale < 1 for splash distance; instant effects scale the amount).
## wiki Splash Potion: instant effects scale linearly with distance; other effects keep their level, their duration
## scales and is rounded to the nearest tick, and nothing applies at 1 second (20 ticks) or less.
static func apply(p: Player, potion: String, scale: float = 1.0) -> void:
	for e in EFFECTS.get(potion, []):
		var id: String = e[0]
		if id == "instant_health":
			p.heal(float(4 << int(e[1])) * scale)
		elif id == "instant_damage":
			p.hurt(float(6 << int(e[1])) * scale, "magic", true)
		else:
			var ticks := roundi(float(e[2]) * scale)
			if ticks > 20:
				p.add_effect(id, int(e[1]), ticks)
