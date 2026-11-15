## GameRules — per-world rules with the 26.x ids, types, defaults and categories (wiki: Game rule, Java 26.3). Values
## persist in level.json. Older worlds and code use the pre-26.1 camelCase names: LEGACY maps them to the new ids
## (raids / elytra_movement_check / player_movement_check mean the opposite of disableRaids /
## disableElytraMovementCheck / disablePlayerMovementCheck).
## Contract: defaults() -> Dictionary, SPEC[id] = [default, category], canonical(name), validate(name, value),
## migrate(saved dict), lang_key(id).
class_name GameRules

const SPEC := {
	"command_block_output": [true, "chat"], "log_admin_commands": [true, "chat"], "send_command_feedback": [true, "chat"],
	"show_advancement_messages": [true, "chat"], "show_death_messages": [true, "chat"],
	"block_drops": [true, "drops"], "block_explosion_drop_decay": [true, "drops"], "entity_drops": [true, "drops"],
	"mob_drops": [true, "drops"], "mob_explosion_drop_decay": [true, "drops"], "projectiles_can_break_blocks": [true, "drops"],
	"tnt_explosion_drop_decay": [false, "drops"],
	"command_blocks_work": [true, "misc"], "global_sound_events": [true, "misc"], "max_block_modifications": [32768, "misc"],
	"max_command_forks": [65536, "misc"], "max_command_sequence_length": [65536, "misc"], "reduced_debug_info": [false, "misc"],
	"tnt_explodes": [true, "misc"],
	"forgive_dead_players": [true, "mobs"], "max_entity_cramming": [24, "mobs"], "mob_griefing": [true, "mobs"],
	"raids": [true, "mobs"], "universal_anger": [false, "mobs"],
	"allow_entering_nether_using_portals": [true, "player"], "drowning_damage": [true, "player"],
	"elytra_movement_check": [true, "player"], "ender_pearls_vanish_on_death": [true, "player"], "fall_damage": [true, "player"],
	"fire_damage": [true, "player"], "fire_spread_radius_around_player": [128, "player"], "freeze_damage": [true, "player"],
	"immediate_respawn": [false, "player"], "keep_inventory": [false, "player"], "limited_crafting": [false, "player"],
	"locator_bar": [true, "player"], "natural_health_regeneration": [true, "player"], "player_movement_check": [true, "player"],
	"players_nether_portal_creative_delay": [0, "player"], "players_nether_portal_default_delay": [80, "player"],
	"players_sleeping_percentage": [100, "player"], "pvp": [true, "player"], "respawn_radius": [10, "player"],
	"spectators_generate_chunks": [true, "player"],
	"spawn_mobs": [true, "spawning"], "spawn_monsters": [true, "spawning"], "spawn_patrols": [true, "spawning"],
	"spawn_phantoms": [true, "spawning"], "spawn_wandering_traders": [true, "spawning"], "spawn_wardens": [true, "spawning"],
	"spawner_blocks_work": [true, "spawning"],
	"advance_time": [true, "updates"], "advance_weather": [true, "updates"], "lava_source_conversion": [false, "updates"],
	"max_snow_accumulation_height": [1, "updates"], "random_tick_speed": [3, "updates"], "spread_vines": [true, "updates"],
	"water_source_conversion": [true, "updates"],
}

## pre-26.1 name -> 26.x id (wiki: Game rule history / rename list)
const LEGACY := {
	"commandBlockOutput": "command_block_output", "logAdminCommands": "log_admin_commands",
	"sendCommandFeedback": "send_command_feedback", "announceAdvancements": "show_advancement_messages",
	"showDeathMessages": "show_death_messages", "doTileDrops": "block_drops", "blockExplosionDropDecay": "block_explosion_drop_decay",
	"doEntityDrops": "entity_drops", "doMobLoot": "mob_drops", "mobExplosionDropDecay": "mob_explosion_drop_decay",
	"projectilesCanBreakBlocks": "projectiles_can_break_blocks", "tntExplosionDropDecay": "tnt_explosion_drop_decay",
	"commandBlocksEnabled": "command_blocks_work", "globalSoundEvents": "global_sound_events",
	"commandModificationBlockLimit": "max_block_modifications", "maxCommandForkCount": "max_command_forks",
	"maxCommandChainLength": "max_command_sequence_length", "reducedDebugInfo": "reduced_debug_info", "tntExplodes": "tnt_explodes",
	"forgiveDeadPlayers": "forgive_dead_players", "maxEntityCramming": "max_entity_cramming", "mobGriefing": "mob_griefing",
	"disableRaids": "raids", "universalAnger": "universal_anger",
	"allowEnteringNetherUsingPortals": "allow_entering_nether_using_portals", "drowningDamage": "drowning_damage",
	"disableElytraMovementCheck": "elytra_movement_check", "enderPearlsVanishOnDeath": "ender_pearls_vanish_on_death",
	"fallDamage": "fall_damage", "fireDamage": "fire_damage", "freezeDamage": "freeze_damage",
	"doImmediateRespawn": "immediate_respawn", "keepInventory": "keep_inventory", "doLimitedCrafting": "limited_crafting",
	"locatorBar": "locator_bar", "naturalRegeneration": "natural_health_regeneration",
	"disablePlayerMovementCheck": "player_movement_check", "playersNetherPortalCreativeDelay": "players_nether_portal_creative_delay",
	"playersNetherPortalDefaultDelay": "players_nether_portal_default_delay", "playersSleepingPercentage": "players_sleeping_percentage",
	"spawnRadius": "respawn_radius", "spectatorsGenerateChunks": "spectators_generate_chunks",
	"doMobSpawning": "spawn_mobs", "spawnMonsters": "spawn_monsters", "doPatrolSpawning": "spawn_patrols",
	"doInsomnia": "spawn_phantoms", "doTraderSpawning": "spawn_wandering_traders", "doWardenSpawning": "spawn_wardens",
	"spawnerBlocksEnabled": "spawner_blocks_work", "doDaylightCycle": "advance_time", "doWeatherCycle": "advance_weather",
	"lavaSourceConversion": "lava_source_conversion", "snowAccumulationHeight": "max_snow_accumulation_height",
	"randomTickSpeed": "random_tick_speed", "doVinesSpread": "spread_vines", "waterSourceConversion": "water_source_conversion",
}
const INVERTED_LEGACY := ["disableRaids", "disableElytraMovementCheck", "disablePlayerMovementCheck"]

## wiki: Game rule - integer bounds ([min, max], max -1 = none); values outside are rejected like /gamerule does.
const RANGE := {"random_tick_speed": [0, -1], "players_sleeping_percentage": [0, -1], "respawn_radius": [0, -1],
	"max_entity_cramming": [0, -1], "max_command_sequence_length": [0, -1], "max_command_forks": [1, -1],
	"max_block_modifications": [1, -1], "max_snow_accumulation_height": [0, 8], "players_nether_portal_creative_delay": [0, -1],
	"players_nether_portal_default_delay": [0, -1], "fire_spread_radius_around_player": [-1, -1]}


static func defaults() -> Dictionary:
	var d := {}
	for k in SPEC:
		d[k] = SPEC[k][0]
	return d


## 26.x id of a rule name (accepts "minecraft:" ids and the old camelCase names); "" for unknown rules.
static func canonical(name: String) -> String:
	var n := name.trim_prefix("minecraft:")
	if SPEC.has(n):
		return n
	return str(LEGACY.get(n, ""))


static func is_inverted_legacy(name: String) -> bool:
	return INVERTED_LEGACY.has(name)


## Rules saved by older versions under their camelCase names (inverted ones flipped); dropped rules are ignored.
static func migrate(saved: Dictionary) -> Dictionary:
	var out := {}
	for k in saved:
		var id := canonical(str(k))
		if id == "":
			continue
		var v = saved[k]
		if is_inverted_legacy(str(k)) and v is bool:
			v = not v
		out[id] = v
	return out


## Translation key of a rule's name (26.3's en_us keeps most rules under their old names).
static func lang_key(id: String) -> String:
	for old in LEGACY:
		if LEGACY[old] == id and not INVERTED_LEGACY.has(old):
			return "gamerule." + old
	return "gamerule.minecraft." + id


static func validate(name: String, v: String):
	var id := canonical(name)
	if id == "":
		return null
	var def = SPEC[id][0]
	if def is bool:
		if v == "true":
			return true
		if v == "false":
			return false
		return null
	if v.is_valid_int() or (v.begins_with("-") and v.substr(1).is_valid_int()):
		var r: Array = RANGE.get(id, [-2147483648, -1])
		if int(v) < int(r[0]) or (int(r[1]) >= 0 and int(v) > int(r[1])):
			return null
		return int(v)
	return null
