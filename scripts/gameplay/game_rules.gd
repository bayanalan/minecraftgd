## GameRules — per-world rules with types/defaults (Java names). Values persist in level.json.
## Contract: defaults() -> Dictionary, SPEC[name] = [default, category], validate(name, value).
class_name GameRules

const SPEC := {
	"doDaylightCycle": [true, "updates"], "doWeatherCycle": [true, "updates"], "doMobSpawning": [true, "spawning"],
	"doMobLoot": [true, "drops"], "doTileDrops": [true, "drops"], "doEntityDrops": [true, "drops"], "doFireTick": [true, "updates"],
	"randomTickSpeed": [3, "updates"], "keepInventory": [false, "player"], "mobGriefing": [true, "mobs"],
	"naturalRegeneration": [true, "player"], "doImmediateRespawn": [false, "player"], "showDeathMessages": [true, "chat"],
	"announceAdvancements": [true, "chat"], "commandBlockOutput": [true, "chat"], "sendCommandFeedback": [true, "chat"],
	"reducedDebugInfo": [false, "misc"], "spectatorsGenerateChunks": [true, "player"], "playersSleepingPercentage": [100, "player"],
	"spawnRadius": [10, "player"], "maxEntityCramming": [24, "mobs"], "universalAnger": [false, "mobs"], "forgiveDeadPlayers": [true, "mobs"],
	"doInsomnia": [true, "spawning"], "doPatrolSpawning": [true, "spawning"], "doTraderSpawning": [true, "spawning"],
	"doWardenSpawning": [true, "spawning"], "fallDamage": [true, "player"], "fireDamage": [true, "player"], "drowningDamage": [true, "player"],
	"freezeDamage": [true, "player"], "doLimitedCrafting": [false, "player"], "maxCommandChainLength": [65536, "misc"],
	"waterSourceConversion": [true, "updates"], "lavaSourceConversion": [false, "updates"], "snowAccumulationHeight": [1, "updates"],
	"tntExplodes": [true, "misc"], "projectilesCanBreakBlocks": [true, "misc"], "blockExplosionDropDecay": [true, "drops"],
	"mobExplosionDropDecay": [true, "drops"], "disableRaids": [false, "mobs"], "spawnChunkRadius": [2, "misc"], "pvp": [true, "player"],
}


static func defaults() -> Dictionary:
	var d := {}
	for k in SPEC:
		d[k] = SPEC[k][0]
	return d


static func validate(name: String, v: String):
	if not SPEC.has(name):
		return null
	var def = SPEC[name][0]
	if def is bool:
		if v == "true":
			return true
		if v == "false":
			return false
		return null
	if v.is_valid_int():
		return int(v)
	return null
