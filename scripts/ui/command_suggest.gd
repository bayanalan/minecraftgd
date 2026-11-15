## CommandSuggest — Java CommandSuggestions for the chat box: completions for the argument under the cursor from
## each command's syntax (selectors, item / block / entity / effect / enchantment / biome / structure ids, game
## rules, keywords, the targeted block's coordinates) and the usage line of the command when nothing matches.
class_name CommandSuggest

# argument kinds: "players" "item" "block" "entity" "pos" "effect" "ench" "biome" "structure" "rule" "int" "text"
# or a literal list
const SYNTAX := {
	"gamemode": [["survival", "creative", "adventure", "spectator"], "players"],
	"defaultgamemode": [["survival", "creative", "adventure", "spectator"]],
	"difficulty": [["peaceful", "easy", "normal", "hard"]],
	"give": ["players", "item", "int"],
	"clear": ["players", "item", "int"],
	"tp": ["players", "pos"],
	"teleport": ["players", "pos"],
	"time": [["set", "add", "query"], ["day", "night", "noon", "midnight", "daytime", "gametime"]],
	"weather": [["clear", "rain", "thunder"], "int"],
	"setblock": ["pos", "block", ["destroy", "keep", "replace"]],
	"fill": ["pos", "pos", "block", ["destroy", "hollow", "keep", "outline", "replace"]],
	"clone": ["pos", "pos", "pos"],
	"summon": ["entity", "pos"],
	"kill": ["players"],
	"effect": [["give", "clear"], "players", "effect", "int", "int"],
	"enchant": ["players", "ench", "int"],
	"experience": [["add", "set", "query"], "players", "int", ["points", "levels"]],
	"xp": [["add", "set", "query"], "players", "int", ["points", "levels"]],
	"spawnpoint": ["players", "pos"],
	"setworldspawn": ["pos"],
	"locate": [["biome", "structure", "poi"], "locate_target"],
	"gamerule": ["rule", ["true", "false"]],
	"tell": ["players", "text"], "msg": ["players", "text"], "w": ["players", "text"],
	"say": ["text"], "me": ["text"],
	"title": ["players", ["title", "subtitle", "actionbar", "clear", "reset", "times"]],
	"spectate": ["players"],
	"ride": ["players", ["mount", "dismount"]],
	"damage": ["players", "int"],
	"tick": [["query", "rate", "freeze", "unfreeze", "step", "sprint"]],
	"worldborder": [["add", "center", "damage", "get", "set", "warning"]],
	"item": [["replace", "modify"]],
	"execute": [["align", "anchored", "as", "at", "facing", "if", "in", "positioned", "rotated", "run", "store", "summon", "unless"]],
}

const USAGE := {
	"gamemode": "<gamemode> [<target>]", "give": "<targets> <item> [<count>]", "tp": "<targets> <location>",
	"teleport": "<targets> <location>", "time": "set|add|query <time>", "weather": "clear|rain|thunder [<duration>]",
	"setblock": "<pos> <block> [destroy|keep|replace]", "fill": "<from> <to> <block> [destroy|hollow|keep|outline|replace]",
	"summon": "<entity> [<pos>] [<nbt>]", "kill": "[<targets>]", "effect": "give|clear <targets> <effect> [<seconds>] [<amplifier>]",
	"enchant": "<targets> <enchantment> [<level>]", "locate": "biome|structure|poi <id>", "gamerule": "<rule> [<value>]",
	"difficulty": "[peaceful|easy|normal|hard]", "clear": "[<targets>] [<item>] [<maxCount>]", "experience": "add|set|query <targets> <amount> [points|levels]",
}


## Text before the cursor -> [token start index, candidates (sorted), usage hint].
static func suggest(world, text: String) -> Array:
	if not text.begins_with("/"):
		return [0, [], ""]
	var body := text.substr(1)
	var toks := body.split(" ")
	var cur := toks[toks.size() - 1]
	var start := text.length() - cur.length()
	# Java: the command tree is filtered by permission - without Allow Commands only the level-0 commands appear
	var allowed: bool = world == null or bool(world.level.get("allow_commands", false))
	if toks.size() == 1:
		var cmds: Array = []
		for c in CommandParser.IMPLEMENTED:
			if c.begins_with(cur) and (allowed or c in CommandParser.NO_PERMISSION):
				cmds.append(c)
		cmds.sort()
		return [start, cmds, ""]
	var cmd := toks[0]
	if not allowed and not (cmd in CommandParser.NO_PERMISSION):
		return [start, [], ""]
	var syn: Array = SYNTAX.get(cmd, [])
	var ai := toks.size() - 2
	# positions take three tokens
	var slot := -1
	var k := 0
	var arg_in_pos := 0
	for si in syn.size():
		var width := 3 if str(syn[si]) == "pos" else 1
		if ai < k + width:
			slot = si
			arg_in_pos = ai - k
			break
		k += width
	var usage := "/" + cmd + " " + str(USAGE.get(cmd, ""))
	if slot < 0:
		return [start, [], usage]
	var kind = syn[slot]
	var cands: Array = []
	if kind is Array:
		cands = (kind as Array).duplicate()
	else:
		match str(kind):
			"players":
				cands = ["@a", "@e", "@p", "@r", "@s", "Player"]
			"item":
				cands = _ids(Res.items.names)
			"block":
				cands = _ids(Res.blocks.names)
			"entity":
				cands = []
				for m in MobRegistry.ALL:
					cands.append("minecraft:" + m)
				cands.append_array(["minecraft:item", "minecraft:tnt", "minecraft:lightning_bolt", "minecraft:experience_orb"])
			"effect":
				cands = _ids(["speed", "slowness", "haste", "mining_fatigue", "strength", "instant_health", "instant_damage", "jump_boost",
					"nausea", "regeneration", "resistance", "fire_resistance", "water_breathing", "invisibility", "blindness", "night_vision",
					"hunger", "weakness", "poison", "wither", "health_boost", "absorption", "saturation", "glowing", "levitation", "luck",
					"unluck", "slow_falling", "conduit_power", "dolphins_grace", "bad_omen", "hero_of_the_village", "darkness",
					"trial_omen", "raid_omen", "wind_charged", "weaving", "oozing", "infested"])
			"ench":
				cands = _ids(Enchanting.defs.keys().map(func(x): return str(x).trim_prefix("minecraft:")))
			"rule":
				cands = GameRules.SPEC.keys()   # (26.x ids)
				cands.sort()
			"locate_target":
				var mode := toks[1] if toks.size() > 2 else ""
				if mode == "biome" and world != null and world.biomes != null:
					cands = Array(world.biomes.names)
				elif mode == "structure":
					cands = _ids(["ancient_city", "bastion_remnant", "buried_treasure", "desert_pyramid", "end_city", "fortress", "igloo",
						"jungle_pyramid", "mansion", "mineshaft", "mineshaft_mesa", "monument", "nether_fossil", "ocean_ruin_cold",
						"ocean_ruin_warm", "pillager_outpost", "ruined_portal", "shipwreck", "stronghold", "swamp_hut", "trail_ruins",
						"trial_chambers", "village_desert", "village_plains", "village_savanna", "village_snowy", "village_taiga"])
			"pos":
				# Java: the targeted block's coordinates, else ~ ~ ~
				var tgt: Dictionary = world.target if world != null else {}
				if tgt.has("pos"):
					var tp: Vector3i = tgt["pos"]
					var coords := [str(tp.x), str(tp.y), str(tp.z)]
					cands = [" ".join(coords.slice(arg_in_pos))]
				else:
					cands = [" ".join(["~", "~", "~"].slice(arg_in_pos))]
	var out: Array = []
	var cl := cur.to_lower()
	for c in cands:
		var cs := str(c)
		if cl == "" or cs.to_lower().begins_with(cl) or cs.to_lower().trim_prefix("minecraft:").begins_with(cl):
			out.append(cs)
	if not (kind is Array) and str(kind) != "pos":
		out.sort()
	return [start, out.slice(0, 200), usage]


static func _ids(names) -> Array:
	var out: Array = []
	for n in names:
		if str(n) != "air":
			out.append("minecraft:" + str(n))
	return out
