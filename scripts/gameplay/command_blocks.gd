## Command blocks (Java CommandBlockEntity / BaseCommandBlock): impulse blocks run once per rising redstone edge
## (or once when switched to "Always Active"), repeating blocks run every game tick while active, chain blocks run
## when the block facing into them ran this tick (conditional ones only if that block succeeded). Commands run at
## the block centre with no player source; SuccessCount / LastOutput are stored in the block entity and sent to
## chat when the commandBlockOutput gamerule is on (creative players only). Chains are capped by
## maxCommandChainLength (and 1024 per tick here).
## APPROXIMATE: Java's "conditional" checks the block behind on its own last result; here it follows the chain's
## previous block in the same tick.
class_name CommandBlocks
extends RefCounted

const DIRS := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0), "up": Vector3i(0, 1, 0), "down": Vector3i(0, -1, 0)}
const KINDS := ["command_block", "chain_command_block", "repeating_command_block"]

static var _queue: Array = []


static func is_command_block(nm: String) -> bool:
	return nm in KINDS


static func data(world, p: Vector3i) -> Dictionary:
	var d := BlockEntities.get_data(world, p)
	if d.is_empty() or str(d.get("id", "")) != "command_block":
		d = {"id": "command_block", "Command": "", "auto": false, "powered": false, "SuccessCount": 0, "LastOutput": ""}
		BlockEntities.set_data(world, p, d)
	return d


## Redstone hook (Redstone._update_consumer).
static func on_power(world, p: Vector3i, powered: bool) -> void:
	var d := data(world, p)
	var was := bool(d.get("powered", false))
	d["powered"] = powered
	var st: int = world.state_at(p.x, p.y, p.z)
	if powered and not was and not bool(d.get("auto", false)) and st > 0 and Res.blocks.name_of(st) == "command_block":
		queue(p)


static func queue(p: Vector3i) -> void:
	if not _queue.has(p):
		_queue.append(p)


## Per game tick (host).
static func tick(world) -> void:
	var q := _queue
	_queue = []
	for p in q:
		run_chain(world, p)
	var b := Res.blocks
	for c in BlockEntities.chunks_with(world, ["command_block"]):
		var ch: Chunk = c
		if ch.block_entities.is_empty():
			continue
		for k in ch.block_entities.keys():
			var d: Dictionary = ch.block_entities[k]
			if str(d.get("id", "")) != "command_block" or not (bool(d.get("auto", false)) or bool(d.get("powered", false))):
				continue
			var p := Vector3i(ch.cx * 16 + (k & 15), (k >> 8) + Coords.MIN_Y, ch.cz * 16 + ((k >> 4) & 15))
			var st: int = world.state_at(p.x, p.y, p.z)
			if st > 0 and b.name_of(st) == "repeating_command_block":
				run_chain(world, p)


static func run_chain(world, start: Vector3i) -> void:
	var b := Res.blocks
	var cur := start
	var prev_ok := true
	var limit := mini(int(world.gamerule("maxCommandChainLength", 65536)), 1024)
	for i in limit:
		var st: int = world.state_at(cur.x, cur.y, cur.z)
		var nm := b.name_of(st) if st > 0 else ""
		if not is_command_block(nm) or (i > 0 and nm != "chain_command_block"):
			return
		var d := data(world, cur)
		if i > 0 and not (bool(d.get("auto", false)) or bool(d.get("powered", false))):
			return
		var cond := b.has_prop(st, "conditional") and b.get_prop(st, "conditional") == "true"
		var ok := false
		if not cond or prev_ok:
			ok = execute(world, cur, d)
		prev_ok = ok
		cur += DIRS.get(str(b.get_prop(st, "facing")) if b.has_prop(st, "facing") else "up", Vector3i(0, 1, 0))


static func execute(world, p: Vector3i, d: Dictionary) -> bool:
	var cmd := str(d.get("Command", "")).strip_edges()
	if cmd == "":
		d["SuccessCount"] = 0
		return false
	var cp: CommandParser = world.commands
	var ctx := CommandParser.Ctx.new()
	ctx.pos = Vector3(p) + Vector3(0.5, 0.5, 0.5)
	var saved: Array = cp.feedback
	cp.feedback = []
	var r := cp.run(cmd.trim_prefix("/"), ctx)
	d["SuccessCount"] = r
	d["LastOutput"] = "\n".join(cp.feedback)
	if world.gamerule("commandBlockOutput", true) and not cp.feedback.is_empty() and world.player.is_creative():
		world.hud.chat_message("[@: %s]" % d["LastOutput"])
	cp.feedback = saved
	return r > 0
