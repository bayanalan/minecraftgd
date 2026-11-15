## Copper — Java WeatheringCopper / HoneycombItem / AxeItem for the copper families (blocks, cut copper and its
## stairs / slabs, chiseled, grates, bulbs, doors, trapdoors, bars, chains, lanterns, chests, golem statues, lightning
## rods): random-tick oxidation (ChangeOverTimeBlock.changeOverTime), axe scraping / wax removal, honeycomb waxing,
## and the lightning strike clean-up (LightningBolt.clearCopperOnLightningStrike).
## Contract: static functions; names are block ids without the namespace.
class_name Copper

const STAGES := ["", "exposed_", "weathered_", "oxidized_"]
const FAMILIES := ["chiseled_copper", "copper_bars", "copper_block", "copper_bulb", "copper_chain", "copper_chest", "copper_door",
	"copper_golem_statue", "copper_grate", "copper_lantern", "copper_trapdoor", "cut_copper", "cut_copper_slab", "cut_copper_stairs",
	"lightning_rod"]


## [family base, stage 0..3, waxed] of a copper-family block name, or [] for other blocks.
static func parse(name: String) -> Array:
	var n := name
	var waxed := false
	if n.begins_with("waxed_"):
		waxed = true
		n = n.trim_prefix("waxed_")
	var stage := 0
	for i in range(1, 4):
		if n.begins_with(STAGES[i]):
			stage = i
			n = n.trim_prefix(STAGES[i])
			break
	if stage > 0 and n == "copper":
		n = "copper_block"   # exposed_copper / weathered_copper / oxidized_copper
	if not FAMILIES.has(n):
		return []
	return [n, stage, waxed]


static func name_of(base: String, stage: int, waxed: bool) -> String:
	var n := base
	if stage > 0:
		n = STAGES[stage] + ("copper" if base == "copper_block" else base)
	return ("waxed_" + n) if waxed else n


## The state of block `name` keeping every property `st` shares with it (-1 if the block does not exist).
static func convert_state(st: int, name: String) -> int:
	var b := Res.blocks
	var id := b.block_id(name)
	if id < 0:
		return -1
	var out := b.block_default[id]
	for pr in b.block_props[b.st_block[st]]:
		var k: String = pr[0]
		if b.has_prop(out, k):
			out = b.with_prop(out, k, b.get_prop(st, k))
	return out


## Java ChangeOverTimeBlock.changeOverTime: 0.05688889 per random tick, then getNextState - a less weathered copper
## block of the same kind within Manhattan distance 4 stops it; otherwise (more weathered + 1) / (all + 1), squared,
## x 0.75 while unaffected.
static func random_tick(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	if rng.randf() >= 0.05688889:
		return
	var b := Res.blocks
	var me := parse(b.name_of(st))
	if me.is_empty() or me[2] or int(me[1]) >= 3:
		return
	var age: int = me[1]
	var same := 0
	var older := 0
	for dy in range(-4, 5):
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				var md := absi(dx) + absi(dy) + absi(dz)
				if md == 0 or md > 4:
					continue
				var s2: int = world.state_at(p.x + dx, p.y + dy, p.z + dz)
				if s2 <= 0:
					continue
				var o := parse(b.name_of(s2))
				if o.is_empty() or o[2]:
					continue   # (waxed blocks are not ChangeOverTimeBlocks)
				var a2: int = o[1]
				if a2 < age:
					return
				if a2 > age:
					older += 1
				else:
					same += 1
	var f := float(older + 1) / float(older + same + 1)
	var chance := f * f * (0.75 if age == 0 else 1.0)
	if rng.randf() < chance:
		var ns := convert_state(st, name_of(me[0], age + 1, false))
		if ns > 0:
			world.set_block(p.x, p.y, p.z, ns)


## Axe / honeycomb on a copper-family block (Java AxeItem.useOn: wax off first, then scrape; HoneycombItem.useOn).
## Returns true when it acted.
static func use_item(world, pos: Vector3i, st: int, held: ItemStack, p: Player) -> bool:
	if held.is_empty():
		return false
	var b := Res.blocks
	var me := parse(b.name_of(st))
	if me.is_empty():
		return false
	var item := held.name()
	var target := ""
	var sound := ""
	var particle := ""
	if item == "honeycomb":
		if me[2]:
			return false
		target = name_of(me[0], me[1], true)
		sound = "item.honeycomb.wax_on"
		particle = "wax_on"
	elif item.ends_with("_axe"):
		if me[2]:
			target = name_of(me[0], me[1], false)
			sound = "item.axe.wax_off"
			particle = "wax_off"
		elif int(me[1]) > 0:
			target = name_of(me[0], int(me[1]) - 1, false)
			sound = "item.axe.scrape"
			particle = "scrape"
		else:
			return false
	else:
		return false
	var ns := convert_state(st, target)
	if ns <= 0:
		return false
	world.set_block(pos.x, pos.y, pos.z, ns)
	# doors: the other half follows (Java DoorBlock keeps both halves the same block)
	if b.has_prop(st, "half") and b.name_of(st).ends_with("_door"):
		var oy := 1 if b.get_prop(st, "half") == "lower" else -1
		var os: int = world.state_at(pos.x, pos.y + oy, pos.z)
		if os > 0 and b.st_block[os] == b.st_block[st]:
			world.set_block(pos.x, pos.y + oy, pos.z, convert_state(os, target))
	Audio.play(sound, Vector3(pos) + Vector3(0.5, 0.5, 0.5), "Blocks")
	# Java GlowParticle providers: wax on (0.91, 0.55, 0.08), wax off (1.0, 0.9, 1.0), scrape (0.29, 0.58, 0.51)
	var pc: Color = {"wax_on": Color(0.91, 0.55, 0.08), "wax_off": Color(1.0, 0.9, 1.0), "scrape": Color(0.29, 0.58, 0.51)}[particle]
	for i in 6:
		Particles.emit(particle, Vector3(pos) + Vector3(randf(), randf(), randf()), Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.02, pc)
	if item == "honeycomb":
		if not p.is_creative():
			p.inventory.consume_held()
		if world.get("advancements") != null and world.advancements != null:
			world.advancements.trigger("item_used_on_block", {"item": "honeycomb", "block": b.name_of(st)})
	else:
		Interaction.damage_tool(p, 1)
	return true


## Java LightningBolt.clearCopperOnLightningStrike: the struck copper block (or the one a struck lightning rod stands
## on) loses all oxidation, then 3..5 random walks of 1..8 steps scrape one stage off the blocks they reach.
static func lightning_clean(world, strike: Vector3i, rng: RandomNumberGenerator) -> void:
	var b := Res.blocks
	var p := strike
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0:
		return
	var me := parse(b.name_of(st))
	if not me.is_empty() and me[0] == "lightning_rod":
		var f := b.get_prop(st, "facing")
		var back := {"up": Vector3i(0, -1, 0), "down": Vector3i(0, 1, 0), "north": Vector3i(0, 0, 1), "south": Vector3i(0, 0, -1),
			"west": Vector3i(1, 0, 0), "east": Vector3i(-1, 0, 0)}.get(f, Vector3i(0, -1, 0))
		p = strike + back
		st = world.state_at(p.x, p.y, p.z)
		me = parse(b.name_of(st)) if st > 0 else []
	if me.is_empty() or me[2]:
		return
	var clean := convert_state(st, name_of(me[0], 0, false))
	if clean > 0:
		world.set_block(p.x, p.y, p.z, clean)
	for walk in rng.randi_range(3, 5):
		var cur := p
		for step in rng.randi_range(1, 8):
			var moved := false
			for attempt in 10:
				var q := cur + Vector3i(rng.randi_range(-1, 1), rng.randi_range(-1, 1), rng.randi_range(-1, 1))
				var qs: int = world.state_at(q.x, q.y, q.z)
				var qm := parse(b.name_of(qs)) if qs > 0 else []
				if qm.is_empty() or qm[2]:
					continue
				if int(qm[1]) > 0:
					world.set_block(q.x, q.y, q.z, convert_state(qs, name_of(qm[0], int(qm[1]) - 1, false)))
				cur = q
				moved = true
				break
			if not moved:
				break
