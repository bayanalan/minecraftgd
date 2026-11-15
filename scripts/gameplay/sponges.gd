## Sponges (wiki Sponge): a placed sponge absorbs nearby water when it is placed and whenever a neighbour changes
## (water flowing next to it): flowing and source water up to 6 blocks away by taxicab distance, spreading only
## through water, nearest first, at most 118 blocks (wiki Sponge, Java Edition; Java SpongeBlock.tryAbsorbWater via
## BlockUpdates.fluids_changed). Water blocks and bubble columns become air, waterlogged blocks give up their water,
## kelp / seagrass break with their drops (Java SpongeBlock.removeWaterBreadthFirstSearch); a sponge that took any
## becomes a wet sponge (block.sponge.absorb). A wet sponge placed where water evaporates (the Nether) dries at once
## with a puff of steam (block.wet_sponge.dries, pitch 0.7-0.84 - wiki Sponge sounds; Java level event 2009: 8 cloud
## particles 1.2 above). Item-form sponges do nothing.
class_name Sponges

const MAX_DEPTH := 6     # wiki: "up to 6 blocks away" (taxicab)
const MAX_COUNT := 118   # wiki: "does not absorb more than 118 blocks of water"
const DIRS := [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]   # Direction.values()

static var _ids := PackedInt32Array()   # [sponge, wet_sponge, kelp, kelp_plant, seagrass, tall_seagrass, bubble_column] block ids


static func ids() -> PackedInt32Array:
	if _ids.is_empty():
		var b := Res.blocks
		for nm in ["sponge", "wet_sponge", "kelp", "kelp_plant", "seagrass", "tall_seagrass", "bubble_column"]:
			_ids.append(b.block_id(nm))
	return _ids


## SpongeBlock.onPlace / neighborChanged -> tryAbsorbWater; WetSpongeBlock.onPlace (placed = the change was at p).
static func on_update(world, p: Vector3i, st: int, placed: bool) -> void:
	var b := Res.blocks
	var bid := b.st_block[st]
	var ii := ids()
	if bid == ii[0]:
		if absorb(world, p) > 0:
			world.set_block(p.x, p.y, p.z, b.default_state("wet_sponge"), false)   # (Java flag 2: no neighbour updates)
			Audio.play("block.sponge.absorb", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks", 1.0, 1.0)
			dry_check(world, p)
	elif bid == ii[1] and placed:
		dry_check(world, p)


## WetSpongeBlock.onPlace where water evaporates: back to a dry sponge.
static func dry_check(world, p: Vector3i) -> void:
	if not Interaction.water_evaporates(world):
		return
	world.set_block(p.x, p.y, p.z, Res.blocks.default_state("sponge"), false)
	Audio.play("block.wet_sponge.dries", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks", 1.0, (1.0 + randf() * 0.2) * 0.7)
	for i in 8:
		Particles.emit("cloud", Vector3(p) + Vector3(randf(), 1.2, randf()))


## SpongeBlock.removeWaterBreadthFirstSearch from the sponge at `start`: the number of water blocks taken.
static func absorb(world, start: Vector3i) -> int:
	var q: Array = [start]
	var dq := PackedInt32Array([0])
	var seen := {start: true}
	var n := 0
	var i := 0
	while i < q.size():
		var p: Vector3i = q[i]
		var d := dq[i]
		i += 1
		if i > 1:
			if not _take(world, p):
				continue
			n += 1
			if n >= MAX_COUNT:
				break
		if d >= MAX_DEPTH:
			continue
		for dv in DIRS:
			var np: Vector3i = p + dv
			if seen.has(np):
				continue
			seen[np] = true
			q.append(np)
			dq.append(d + 1)
	return n


## One visited position: false when it holds no water (not taken, not spread through).
static func _take(world, p: Vector3i) -> bool:
	if p.y < Coords.MIN_Y or p.y >= Coords.MAX_Y:
		return false
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0:
		return false
	var b := Res.blocks
	var fl := b.st_flags[st]
	var water := ((fl & BlockRegistry.F_LIQUID) != 0 and (fl & BlockRegistry.F_LAVA) == 0) or (fl & BlockRegistry.F_WATERLOGGED) != 0
	if not water:
		return false
	if b.has_prop(st, "waterlogged"):
		# SimpleWaterloggedBlock.pickupBlock: dry again (gone with its drops when it can't stay without water)
		world.set_block(p.x, p.y, p.z, b.with_prop(st, "waterlogged", "false"))
		return true
	if fl & BlockRegistry.F_LIQUID:
		world.set_block(p.x, p.y, p.z, 0)   # (LiquidBlock: the source's pickupBlock, or any water block -> air)
		return true
	var ii := ids()
	var bid := b.st_block[st]
	if bid == ii[6]:
		world.set_block(p.x, p.y, p.z, 0)   # BubbleColumnBlock.pickupBlock
		return true
	if bid == ii[2] or bid == ii[3] or bid == ii[4] or bid == ii[5]:
		if world.gamerule("doTileDrops", true) and world.get("entities") != null:
			for s in Loot.block_drops(st, null, world, p):
				world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.5, 0.5), s)
		world.set_block(p.x, p.y, p.z, 0)
		return true
	return false
