## Redstone vanilla test matrix (wiki Redstone mechanics + component pages, Java rules): power sources and their strong /
## weak power, conductors, dust, repeaters, comparators, observers, torches (incl. burnout), mechanisms (doors,
## trapdoors, fence gates, lamps, pistons with QC / timing / short pulses / head breaking, dispensers, droppers,
## hoppers, note blocks, TNT, copper bulbs, crafters, rails) and dust placement support. Run by TestRunner (--vanilla)
## in mock worlds whose set_block runs the world's redstone listeners (dust shapes, observers, queued updates).
extends RefCounted


class LiveEnts:
	var ents: Array = []
	var rng := RandomNumberGenerator.new()
	var dropped: Array = []

	func spawn_item(_p, s, _v = false) -> void:
		dropped.append((s as ItemStack).name() if s is ItemStack else str(s))

	func add_child(n) -> void:
		if n is Node:
			(n as Node).free()

	func explode(_a = null, _b = null, _c = null, _d = null) -> void:
		pass


class LiveCM:
	func get_chunk(_x: int, _z: int):
		return null


class LiveWorld:
	var blocks: Dictionary = {}
	var game_time := 1000
	var rng := RandomNumberGenerator.new()
	var entities := LiveEnts.new()
	var cm := LiveCM.new()
	var player = null

	func state_at(x: int, y: int, z: int) -> int:
		return blocks.get(Vector3i(x, y, z), 0)

	## Like WorldManager.set_block: observers, dust shapes, queued redstone update, Support / fluid neighbour updates.
	func set_block(x: int, y: int, z: int, st: int, notify := true) -> int:
		var p := Vector3i(x, y, z)
		var old: int = blocks.get(p, 0)
		if old == st:
			return old
		blocks[p] = st
		if notify:
			Redstone.notify_observers(self, p)
			RedstoneWire.update_around(self, p, RedstoneWire.is_wire(st) and not RedstoneWire.is_wire(old))
			Redstone.request(self, p)
			BlockUpdates.fluids_changed(self, p)
		return old

	func gamerule(_n: String, d = null):
		return d


var t = null
var b: BlockRegistry = null


func run(runner) -> void:
	t = runner
	b = Res.blocks
	_conductivity()
	_sources()
	_torches()
	_buttons_plates()
	_dust()
	_repeaters()
	_comparators()
	_observers()
	_doors()
	_mechanisms()
	_pistons()
	_placement()
	BlockUpdates.reset()
	Redstone.reset()
	Pistons.reset()


func ok(name: String, cond: bool, detail: String = "") -> void:
	t.ok("redstone: " + name, cond, detail)


func S(n: String) -> int:
	return b.default_state(n)


func P(st: int, k: String, v: String) -> int:
	return b.with_prop(st, k, v)


func on(w: LiveWorld, p: Vector3i, k: String) -> bool:
	return b.get_prop(w.state_at(p.x, p.y, p.z), k) == "true"


func pw(w: LiveWorld, p: Vector3i) -> int:
	return int(b.get_prop(w.state_at(p.x, p.y, p.z), "power"))


func nm(w: LiveWorld, p: Vector3i) -> String:
	return b.name_of(maxi(w.state_at(p.x, p.y, p.z), 0))


func fresh() -> LiveWorld:
	BlockUpdates.reset()
	Redstone.reset()
	Pistons.reset()
	var w := LiveWorld.new()
	var stone := S("stone")
	for x in range(-10, 11):
		for z in range(-10, 11):
			w.blocks[Vector3i(x, -1, z)] = stone
	return w


## A block change with its neighbour updates now (a lever flipped, a block placed), plus this tick's block events.
func put(w: LiveWorld, p: Vector3i, st: int) -> void:
	w.set_block(p.x, p.y, p.z, st)
	Redstone.flush(w)
	Pistons.tick(w)


## Blocks set without updates (scenery).
func raw(w: LiveWorld, p: Vector3i, st: int) -> void:
	w.blocks[p] = st


func tick(w: LiveWorld, n: int = 1) -> void:
	for i in n:
		w.game_time += 1
		BlockUpdates.tick_scheduled(w)
		Redstone.flush(w)
		Pistons.tick(w)


func lever(face: String, facing: String, powered: bool) -> int:
	return P(P(P(S("lever"), "face", face), "facing", facing), "powered", "true" if powered else "false")


# ------------------------------------------------------------------ conductivity

func _conductivity() -> void:
	var yes := ["stone", "dirt", "oak_planks", "soul_sand", "mud", "slime_block", "packed_ice", "target", "redstone_lamp", "note_block", "barrier"]
	var no := ["glass", "white_stained_glass", "tinted_glass", "glowstone", "sea_lantern", "oak_leaves", "ice", "honey_block", "tnt", "redstone_block",
		"observer", "piston", "beacon", "spawner", "copper_bulb", "copper_grate", "oak_slab", "oak_stairs", "farmland", "dirt_path", "hopper"]
	var bad: Array = []
	for n in yes:
		if not Redstone.conductor(S(n)):
			bad.append(n)
	for n in no:
		if Redstone.conductor(S(n)):
			bad.append("!" + n)
	ok("conductors (wiki Conductivity: full blocks; not glass, glowstone, leaves, ice, TNT, redstone blocks, observers, pistons, slabs ...)", bad.is_empty(), str(bad))
	ok("a double slab conducts", Redstone.conductor(P(S("oak_slab"), "type", "double")))


# ------------------------------------------------------------------ power sources

func _sources() -> void:
	var lamp := S("redstone_lamp")
	var stone := S("stone")
	# lever on top of a block: the block is strongly powered (a lamp beside it lights, dust beside it gets 15); a lamp
	# beside the lever lights; a block the lever merely touches is not powered
	var w := fresh()
	raw(w, Vector3i(0, 0, 0), stone)
	raw(w, Vector3i(1, 0, 0), lamp)
	raw(w, Vector3i(0, 1, 1), lamp)
	raw(w, Vector3i(0, 1, 2), stone)
	raw(w, Vector3i(-1, 0, 0), S("redstone_wire"))
	RedstoneWire.update_around(w, Vector3i(-1, 0, 0), true)
	raw(w, Vector3i(1, 1, 0), stone)
	raw(w, Vector3i(2, 1, 0), lamp)
	raw(w, Vector3i(2, 0, 0), stone)
	put(w, Vector3i(0, 1, 0), lever("floor", "north", true))
	ok("lever: strongly powers its block (lamp beside the block lit, dust beside it 15)", on(w, Vector3i(1, 0, 0), "lit") and pw(w, Vector3i(-1, 0, 0)) == 15, "%s %d" % [on(w, Vector3i(1, 0, 0), "lit"), pw(w, Vector3i(-1, 0, 0))])
	ok("lever: activates the component next to it", on(w, Vector3i(0, 1, 1), "lit"))
	ok("lever: a block it only touches is not powered", not on(w, Vector3i(2, 1, 0), "lit"))
	put(w, Vector3i(0, 1, 0), lever("floor", "north", false))
	ok("lever off: everything off (dust 0, lamp waits 4 ticks)", pw(w, Vector3i(-1, 0, 0)) == 0 and on(w, Vector3i(1, 0, 0), "lit"))
	tick(w, 4)
	ok("lever off: lamps off after 4 ticks", not on(w, Vector3i(1, 0, 0), "lit") and not on(w, Vector3i(0, 1, 1), "lit"))
	# redstone block: powers components and dust next to it, never a block (no strong power)
	w = fresh()
	raw(w, Vector3i(1, 0, 0), stone)
	raw(w, Vector3i(2, 0, 0), lamp)
	raw(w, Vector3i(-1, 0, 0), lamp)
	put(w, Vector3i(0, 0, 0), S("redstone_block"))
	ok("redstone block: lights the lamp beside it, does not power the block beside it", on(w, Vector3i(-1, 0, 0), "lit") and not on(w, Vector3i(2, 0, 0), "lit"))
	# strong-power-down sources: pressure plates, detector rails, lecterns, trapped chests, sculk sensors; behind:
	# lightning rods, tripwire hooks; no strong power: daylight detectors, targets, jukeboxes
	var cases := [
		["stone pressure plate", P(S("stone_pressure_plate"), "powered", "true"), true, 15],
		["light weighted plate (power 7)", P(S("light_weighted_pressure_plate"), "power", "7"), true, 7],
		["detector rail", P(P(S("detector_rail"), "powered", "true"), "shape", "north_south"), true, 15],
		["lectern pulse", P(S("lectern"), "powered", "true"), true, 15],
		["lightning rod (up)", P(P(S("lightning_rod"), "powered", "true"), "facing", "up"), true, 15],
		["daylight detector (power 9)", P(S("daylight_detector"), "power", "9"), false, 9],
		["target (power 5)", P(S("target"), "power", "5"), false, 5],
	]
	for c in cases:
		w = fresh()
		raw(w, Vector3i(0, 0, 0), stone)
		raw(w, Vector3i(1, 0, 0), lamp)
		raw(w, Vector3i(-1, 0, 0), stone)
		raw(w, Vector3i(-1, 1, 0), S("redstone_wire"))
		RedstoneWire.update_around(w, Vector3i(-1, 1, 0), true)
		put(w, Vector3i(0, 1, 0), int(c[1]))
		var strong := on(w, Vector3i(1, 0, 0), "lit")
		ok("%s: strong power into the block below = %s, dust beside it %d" % [c[0], c[2], c[3]], strong == bool(c[2]) and pw(w, Vector3i(-1, 1, 0)) == int(c[3]), "lamp %s dust %d" % [strong, pw(w, Vector3i(-1, 1, 0))])
	# tripwire hook on a wall: strongly powers the wall block
	w = fresh()
	raw(w, Vector3i(0, 0, 0), stone)
	raw(w, Vector3i(-1, 0, 0), lamp)
	put(w, Vector3i(1, 0, 0), P(P(S("tripwire_hook"), "facing", "east"), "powered", "true"))
	ok("tripwire hook: strongly powers the block it hangs on", on(w, Vector3i(-1, 0, 0), "lit"))
	# sculk sensor (Sculk.power): every side, strong down
	w = fresh()
	raw(w, Vector3i(0, 0, 0), stone)
	raw(w, Vector3i(1, 0, 0), lamp)
	Sculk.power[Vector3i(0, 1, 0)] = 10
	raw(w, Vector3i(0, 1, 1), S("redstone_wire"))
	raw(w, Vector3i(0, 0, 1), stone)
	RedstoneWire.update_around(w, Vector3i(0, 1, 1), true)
	put(w, Vector3i(0, 1, 0), S("sculk_sensor"))
	ok("sculk sensor: its level on every side, strong power down", on(w, Vector3i(1, 0, 0), "lit") and pw(w, Vector3i(0, 1, 1)) == 10, str(pw(w, Vector3i(0, 1, 1))))
	Sculk.power.erase(Vector3i(0, 1, 0))
	# jukebox playing: 15 beside it, no strong power
	w = fresh()
	raw(w, Vector3i(1, 0, 0), lamp)
	raw(w, Vector3i(-1, 0, 0), stone)
	raw(w, Vector3i(-2, 0, 0), lamp)
	BlockEntities.playing[Vector3i(0, 0, 0)] = [w.game_time, 100]
	put(w, Vector3i(0, 0, 0), S("jukebox"))
	ok("jukebox: a playing disc lights the lamp beside it, no strong power", on(w, Vector3i(1, 0, 0), "lit") and not on(w, Vector3i(-2, 0, 0), "lit"))
	BlockEntities.playing.erase(Vector3i(0, 0, 0))
	# trapped chest: viewers count, strong power down
	w = fresh()
	raw(w, Vector3i(0, 0, 0), stone)
	raw(w, Vector3i(1, 0, 0), lamp)
	raw(w, Vector3i(0, 1, 0), S("trapped_chest"))
	raw(w, Vector3i(-1, 1, 0), S("redstone_wire"))
	raw(w, Vector3i(-1, 0, 0), stone)
	RedstoneWire.update_around(w, Vector3i(-1, 1, 0), true)
	Redstone.chest_viewers(w, Vector3i(0, 1, 0), Vector3i(0, -9999, 0), 1)
	var tc_on := on(w, Vector3i(1, 0, 0), "lit") and pw(w, Vector3i(-1, 1, 0)) == 1
	Redstone.chest_viewers(w, Vector3i(0, 1, 0), Vector3i(0, -9999, 0), -1)
	ok("trapped chest: 1 per viewer, strong power down; off when closed", tc_on and pw(w, Vector3i(-1, 1, 0)) == 0)


# ------------------------------------------------------------------ torches

func _torches() -> void:
	var lamp := S("redstone_lamp")
	var stone := S("stone")
	# a torch powers the block above (strong) and components beside it, never its own block
	var w := fresh()
	raw(w, Vector3i(0, 0, 0), stone)
	raw(w, Vector3i(0, 2, 0), stone)
	raw(w, Vector3i(1, 2, 0), lamp)
	raw(w, Vector3i(1, 1, 0), lamp)
	raw(w, Vector3i(1, 0, 0), lamp)
	put(w, Vector3i(0, 1, 0), S("redstone_torch"))
	ok("torch: strongly powers the block above, lights a lamp beside it, not the block it stands on", on(w, Vector3i(1, 2, 0), "lit") and on(w, Vector3i(1, 1, 0), "lit") and not on(w, Vector3i(1, 0, 0), "lit"))
	# inversion: a lever on the wall block turns the wall torch off 2 ticks later, back on 2 ticks after
	w = fresh()
	raw(w, Vector3i(0, 0, 0), stone)
	raw(w, Vector3i(0, 1, 0), stone)
	raw(w, Vector3i(1, 1, 0), P(S("redstone_wall_torch"), "facing", "east"))
	put(w, Vector3i(0, 2, 0), lever("floor", "north", true))
	tick(w, 1)
	var still := on(w, Vector3i(1, 1, 0), "lit")
	tick(w, 1)
	ok("torch: turns off 2 ticks after its block is powered", still and not on(w, Vector3i(1, 1, 0), "lit"))
	put(w, Vector3i(0, 2, 0), lever("floor", "north", false))
	tick(w, 2)
	ok("torch: back on 2 ticks after the power is gone", on(w, Vector3i(1, 1, 0), "lit"))
	# on a redstone block: off
	w = fresh()
	raw(w, Vector3i(0, 0, 0), S("redstone_block"))
	put(w, Vector3i(0, 1, 0), S("redstone_torch"))
	tick(w, 2)
	ok("torch: off on a redstone block", not on(w, Vector3i(0, 1, 0), "lit"))
	# burnout: forced off 8 times within 60 ticks -> stays off, retries 160 ticks later
	w = fresh()
	raw(w, Vector3i(0, 0, 0), stone)
	raw(w, Vector3i(0, 1, 0), S("redstone_torch"))
	for i in 8:
		put(w, Vector3i(1, 0, 0), lever("wall", "east", true))
		tick(w, 3)
		put(w, Vector3i(1, 0, 0), lever("wall", "east", false))
		tick(w, 3)
	var burnt := not on(w, Vector3i(0, 1, 0), "lit")
	tick(w, 200)
	ok("torch burnout: 8 turn-offs in 60 ticks leave it off; it relights later", burnt and on(w, Vector3i(0, 1, 0), "lit"))


# ------------------------------------------------------------------ buttons / plates

func _buttons_plates() -> void:
	var lamp := S("redstone_lamp")
	var stone := S("stone")
	for c in [["stone_button", 20], ["oak_button", 30]]:
		var w := fresh()
		raw(w, Vector3i(0, 0, 0), stone)
		raw(w, Vector3i(1, 0, 0), lamp)
		var bt := P(P(S(str(c[0])), "face", "floor"), "powered", "true")
		w.set_block(0, 1, 0, bt, false)
		Redstone.schedule_tick(w, Vector3i(0, 1, 0), int(c[1]))
		Redstone.on_changed(w, Vector3i(0, 1, 0))
		var lit0 := on(w, Vector3i(1, 0, 0), "lit")
		tick(w, int(c[1]) - 1)
		var held := on(w, Vector3i(0, 1, 0), "powered")
		tick(w, 1)
		var released := not on(w, Vector3i(0, 1, 0), "powered")
		tick(w, 3)
		var lamp_still := on(w, Vector3i(1, 0, 0), "lit")
		tick(w, 1)
		ok("%s: pressed %d ticks (strong power into its block), the lamp goes off 4 ticks after" % [c[0], c[1]], lit0 and held and released and lamp_still and not on(w, Vector3i(1, 0, 0), "lit"))
	# a neighbour change during the press does not release the button early
	var w2 := fresh()
	raw(w2, Vector3i(0, 0, 0), stone)
	w2.set_block(0, 1, 0, P(P(S("stone_button"), "face", "floor"), "powered", "true"), false)
	Redstone.schedule_tick(w2, Vector3i(0, 1, 0), 20)
	tick(w2, 2)
	BlockUpdates.schedule_neighbors(w2, Vector3i(1, 1, 0))
	tick(w2, 5)
	var mid := on(w2, Vector3i(0, 1, 0), "powered")
	tick(w2, 13)
	ok("button: a neighbour update does not end the press early", mid and not on(w2, Vector3i(0, 1, 0), "powered"))


# ------------------------------------------------------------------ dust

func _dust() -> void:
	var lamp := S("redstone_lamp")
	var stone := S("stone")
	var wire := S("redstone_wire")
	# 15 levels: lever, 16 dust
	var w := fresh()
	raw(w, Vector3i(0, 0, 0), lever("floor", "north", true))
	for x in range(1, 17):
		raw(w, Vector3i(x, -1, 0), stone)
		w.set_block(x, 0, 0, wire)
	Redstone.flush(w)
	ok("dust: 15 next to the lever, 1 fifteen blocks on, 0 after", pw(w, Vector3i(1, 0, 0)) == 15 and pw(w, Vector3i(15, 0, 0)) == 1 and pw(w, Vector3i(16, 0, 0)) == 0,
		"%s %d %d %d" % [nm(w, Vector3i(0, 0, 0)), pw(w, Vector3i(1, 0, 0)), pw(w, Vector3i(15, 0, 0)), pw(w, Vector3i(16, 0, 0))])
	# dust pointing into a block powers it weakly: the lamp beside the block lights, dust beside it gets nothing
	w = fresh()
	raw(w, Vector3i(-1, 0, 0), S("redstone_block"))
	raw(w, Vector3i(2, 0, 0), stone)
	raw(w, Vector3i(2, 0, 1), lamp)
	w.set_block(0, 0, 0, wire)
	w.set_block(1, 0, 0, wire)
	w.set_block(3, 0, 0, wire)
	Redstone.flush(w)
	Redstone.on_changed(w, Vector3i(-1, 0, 0))
	ok("dust into a block: weak power lights a lamp beside the block", on(w, Vector3i(2, 0, 1), "lit"))
	ok("dust into a block: a weakly powered block does not power dust", pw(w, Vector3i(3, 0, 0)) == 0, str(pw(w, Vector3i(3, 0, 0))))
	# torch tower: a torch under a block strongly powers it; the dust on top gets 15
	w = fresh()
	raw(w, Vector3i(0, 0, 0), stone)
	raw(w, Vector3i(0, 2, 0), stone)
	w.set_block(0, 3, 0, wire)
	put(w, Vector3i(0, 1, 0), S("redstone_torch"))
	ok("dust on a block a torch powers from below: 15", pw(w, Vector3i(0, 3, 0)) == 15)


# ------------------------------------------------------------------ repeaters

func _repeaters() -> void:
	var lamp := S("redstone_lamp")
	var stone := S("stone")
	for delay in range(1, 5):
		var w := fresh()
		raw(w, Vector3i(0, 0, 0), P(P(S("repeater"), "facing", "east"), "delay", str(delay)))
		raw(w, Vector3i(-1, 0, 0), lamp)
		put(w, Vector3i(1, 0, 0), S("redstone_block"))
		tick(w, delay * 2 - 1)
		var early := on(w, Vector3i(-1, 0, 0), "lit")
		tick(w, 1)
		ok("repeater delay %d: output after %d ticks" % [delay, delay * 2], not early and on(w, Vector3i(-1, 0, 0), "lit"))
	# pulse extension: a 1-tick input keeps a delay-4 repeater on for 8 ticks
	var w2 := fresh()
	raw(w2, Vector3i(0, 0, 0), P(P(S("repeater"), "facing", "east"), "delay", "4"))
	put(w2, Vector3i(1, 0, 0), S("redstone_block"))
	tick(w2, 1)
	put(w2, Vector3i(1, 0, 0), 0)
	tick(w2, 7)
	var on8 := on(w2, Vector3i(0, 0, 0), "powered")
	tick(w2, 7)
	var on15 := on(w2, Vector3i(0, 0, 0), "powered")
	tick(w2, 1)
	ok("repeater: a short pulse is extended to its delay (on 8 ticks for delay 4)", on8 and on15 and not on(w2, Vector3i(0, 0, 0), "powered"))
	# locking: a powered repeater pointing into its side
	var w3 := fresh()
	raw(w3, Vector3i(0, 0, 0), P(S("repeater"), "facing", "east"))
	raw(w3, Vector3i(0, 0, 1), P(P(S("repeater"), "facing", "south"), "powered", "true"))
	raw(w3, Vector3i(0, 0, 2), S("redstone_block"))   # (keeps the locking repeater on)
	Redstone.on_changed(w3, Vector3i(0, 0, 1))
	put(w3, Vector3i(1, 0, 0), S("redstone_block"))
	tick(w3, 4)
	ok("repeater: locked by a powered repeater at its side (output frozen)", on(w3, Vector3i(0, 0, 0), "locked") and not on(w3, Vector3i(0, 0, 0), "powered"))
	# a lever at the side does not lock (diodes only)
	var w4 := fresh()
	raw(w4, Vector3i(0, 0, 0), P(S("repeater"), "facing", "east"))
	put(w4, Vector3i(0, 0, 1), lever("floor", "north", true))
	ok("repeater: only diodes lock it", not on(w4, Vector3i(0, 0, 0), "locked"))
	# strong output: dust beside the block it points into gets 15
	var w5 := fresh()
	raw(w5, Vector3i(0, 0, 0), P(S("repeater"), "facing", "east"))
	raw(w5, Vector3i(-1, 0, 0), stone)
	w5.set_block(-2, 0, 0, S("redstone_wire"))
	put(w5, Vector3i(1, 0, 0), S("redstone_block"))
	tick(w5, 2)
	ok("repeater: strongly powers the block in front (dust beyond it 15)", pw(w5, Vector3i(-2, 0, 0)) == 15)


# ------------------------------------------------------------------ comparators

func _comparators() -> void:
	var stone := S("stone")
	var cmp := P(S("comparator"), "facing", "east")
	var out := Vector3i(-1, 0, 0)
	# reads a composter (level 5), also through a conductive block; 2-tick delay
	var w := fresh()
	raw(w, Vector3i(0, 0, 0), cmp)
	w.set_block(-1, 0, 0, S("redstone_wire"))
	put(w, Vector3i(1, 0, 0), P(S("composter"), "level", "5"))
	tick(w, 1)
	var early := pw(w, out)
	tick(w, 1)
	ok("comparator: reads a composter (5) 2 ticks later", early == 0 and pw(w, out) == 5, "%d %d" % [early, pw(w, out)])
	w = fresh()
	raw(w, Vector3i(0, 0, 0), cmp)
	raw(w, Vector3i(1, 0, 0), stone)
	w.set_block(-1, 0, 0, S("redstone_wire"))
	put(w, Vector3i(2, 0, 0), P(S("composter"), "level", "6"))
	Redstone.on_changed(w, Vector3i(0, 0, 0))
	tick(w, 2)
	ok("comparator: reads through a conductive block", pw(w, out) == 6, str(pw(w, out)))
	# compare / subtract against side inputs (any signal source: a target, a lever)
	var cases := [["compare", 3, 7], ["subtract", 3, 4], ["compare", 8, 0], ["subtract", 8, 0], ["compare", 7, 7], ["subtract", 7, 0]]
	for c in cases:
		w = fresh()
		raw(w, Vector3i(0, 0, 0), P(cmp, "mode", str(c[0])))
		raw(w, Vector3i(1, 0, 0), P(S("composter"), "level", "7"))
		w.set_block(-1, 0, 0, S("redstone_wire"))
		put(w, Vector3i(0, 0, 1), P(S("target"), "power", str(c[1])))
		Redstone.on_changed(w, Vector3i(0, 0, 0))
		tick(w, 2)
		ok("comparator %s: rear 7, side %d -> %d" % [c[0], c[1], c[2]], pw(w, out) == int(c[2]), str(pw(w, out)))
	w = fresh()
	raw(w, Vector3i(0, 0, 0), cmp)
	raw(w, Vector3i(1, 0, 0), P(S("composter"), "level", "7"))
	w.set_block(-1, 0, 0, S("redstone_wire"))
	put(w, Vector3i(0, 0, -1), lever("floor", "north", true))
	Redstone.on_changed(w, Vector3i(0, 0, 0))
	tick(w, 2)
	ok("comparator: a lever at its side is a side input (15 > 7 -> off)", pw(w, out) == 0)


# ------------------------------------------------------------------ observers

func _observers() -> void:
	var lamp := S("redstone_lamp")
	var stone := S("stone")
	var w := fresh()
	raw(w, Vector3i(0, 0, 0), P(S("observer"), "facing", "east"))
	raw(w, Vector3i(-1, 0, 0), stone)
	raw(w, Vector3i(-2, 0, 0), lamp)
	w.set_block(1, 0, 0, stone)
	tick(w, 1)
	var t1 := on(w, Vector3i(0, 0, 0), "powered")
	tick(w, 1)
	var t2 := on(w, Vector3i(0, 0, 0), "powered") and on(w, Vector3i(-2, 0, 0), "lit")
	tick(w, 2)
	ok("observer: a change in front pulses 2 ticks later for 2 ticks, strongly powering the block behind", not t1 and t2 and not on(w, Vector3i(0, 0, 0), "powered"))
	# it sees a lamp switching (redstone state changes notify observers)
	w = fresh()
	raw(w, Vector3i(1, 0, 0), lamp)
	raw(w, Vector3i(0, 0, 0), P(S("observer"), "facing", "east"))
	put(w, Vector3i(2, 0, 0), S("redstone_block"))
	tick(w, 2)
	ok("observer: sees a lamp light up", on(w, Vector3i(0, 0, 0), "powered"))


# ------------------------------------------------------------------ doors, trapdoors, fence gates

func _door(w: LiveWorld, n: String, p: Vector3i) -> void:
	var d := P(P(S(n), "facing", "north"), "half", "lower")
	raw(w, p, d)
	raw(w, p + Vector3i(0, 1, 0), P(d, "half", "upper"))


func _doors() -> void:
	var stone := S("stone")
	for n in ["oak_door", "iron_door", "cherry_door", "copper_door"]:
		var w := fresh()
		_door(w, n, Vector3i(0, 0, 0))
		put(w, Vector3i(1, 0, 0), lever("floor", "north", true))
		var opened := on(w, Vector3i(0, 0, 0), "open") and on(w, Vector3i(0, 1, 0), "open") and on(w, Vector3i(0, 0, 0), "powered") and on(w, Vector3i(0, 1, 0), "powered")
		put(w, Vector3i(1, 0, 0), lever("floor", "north", false))
		ok("%s: a lever opens both halves and closes them again" % n, opened and not on(w, Vector3i(0, 0, 0), "open") and not on(w, Vector3i(0, 1, 0), "open"))
	# power at the upper half opens the whole door
	var w2 := fresh()
	_door(w2, "oak_door", Vector3i(0, 0, 0))
	raw(w2, Vector3i(2, 1, 0), stone)
	raw(w2, Vector3i(2, 0, 0), stone)
	put(w2, Vector3i(1, 1, 0), lever("wall", "west", true))
	ok("door: power at the upper half opens the whole door", on(w2, Vector3i(0, 0, 0), "open") and on(w2, Vector3i(0, 1, 0), "open"))
	# a door under a powered block (lever on top of the block above the door)
	var w3 := fresh()
	_door(w3, "iron_door", Vector3i(0, 0, 0))
	raw(w3, Vector3i(0, 2, 0), stone)
	put(w3, Vector3i(0, 3, 0), lever("floor", "north", true))
	ok("iron door: opened by a lever on the block above it (strong power)", on(w3, Vector3i(0, 0, 0), "open"))
	# a button, a pressure plate, a redstone torch
	var w4 := fresh()
	_door(w4, "oak_door", Vector3i(0, 0, 0))
	put(w4, Vector3i(1, 0, 0), P(P(S("oak_button"), "face", "floor"), "powered", "true"))
	ok("door: a pressed button next to it opens it", on(w4, Vector3i(0, 0, 0), "open"))
	var w5 := fresh()
	_door(w5, "oak_door", Vector3i(0, 0, 0))
	put(w5, Vector3i(0, 0, 1), P(S("oak_pressure_plate"), "powered", "true"))
	ok("door: a pressed plate in front opens it", on(w5, Vector3i(0, 0, 0), "open"))
	var w6 := fresh()
	_door(w6, "oak_door", Vector3i(0, 0, 0))
	put(w6, Vector3i(1, 0, 0), S("redstone_torch"))
	ok("door: a redstone torch beside it opens it", on(w6, Vector3i(0, 0, 0), "open"))
	# dust pointing at the door
	var w7 := fresh()
	_door(w7, "oak_door", Vector3i(0, 0, 0))
	raw(w7, Vector3i(3, 0, 0), S("redstone_block"))
	w7.set_block(2, 0, 0, S("redstone_wire"))
	w7.set_block(1, 0, 0, S("redstone_wire"))
	Redstone.flush(w7)
	ok("door: dust leading into it opens it", on(w7, Vector3i(0, 0, 0), "open"))
	# trapdoors and fence gates
	for n in ["oak_trapdoor", "iron_trapdoor", "oak_fence_gate", "crimson_fence_gate"]:
		var w8 := fresh()
		raw(w8, Vector3i(0, 0, 0), S(n))
		put(w8, Vector3i(1, 0, 0), lever("floor", "north", true))
		var op := on(w8, Vector3i(0, 0, 0), "open") and on(w8, Vector3i(0, 0, 0), "powered")
		put(w8, Vector3i(1, 0, 0), lever("floor", "north", false))
		ok("%s: opens with a lever, closes when it is off" % n, op and not on(w8, Vector3i(0, 0, 0), "open"))
	# placed next to a powered lever: open (Java getStateForPlacement)
	var w9 := fresh()
	raw(w9, Vector3i(1, 0, 0), lever("floor", "north", true))
	var placed := Redstone.placed_state(w9, Vector3i(0, 0, 0), P(S("oak_door"), "half", "lower"))
	ok("door placed next to a powered lever comes open and powered", b.get_prop(placed, "open") == "true" and b.get_prop(placed, "powered") == "true")
	# a door opened by hand while powered stays as set until the power changes
	var w10 := fresh()
	_door(w10, "oak_door", Vector3i(0, 0, 0))
	put(w10, Vector3i(1, 0, 0), lever("floor", "north", true))
	raw(w10, Vector3i(0, 0, 0), P(w10.state_at(0, 0, 0), "open", "false"))
	raw(w10, Vector3i(0, 1, 0), P(w10.state_at(0, 1, 0), "open", "false"))
	Redstone.on_changed(w10, Vector3i(1, 0, 0))
	ok("door: closed by hand while powered, it stays closed", not on(w10, Vector3i(0, 0, 0), "open"))
	ok("door sounds per set (wiki): oak / iron / copper / cherry / bamboo trapdoor / crimson gate",
		Redstone.door_sound("oak_door", true) == "block.wooden_door.open" and Redstone.door_sound("iron_door", false) == "block.iron_door.close"
		and Redstone.door_sound("exposed_copper_door", true) == "block.copper_door.open" and Redstone.door_sound("cherry_door", true) == "block.cherry_wood_door.open"
		and Redstone.door_sound("bamboo_trapdoor", true) == "block.bamboo_wood_trapdoor.open" and Redstone.door_sound("crimson_fence_gate", true) == "block.nether_wood_fence_gate.open"
		and Redstone.door_sound("oak_fence_gate", false) == "block.fence_gate.close" and Redstone.door_sound("iron_trapdoor", true) == "block.iron_trapdoor.open")


# ------------------------------------------------------------------ other mechanisms

func _mechanisms() -> void:
	var rb := S("redstone_block")
	# quasi-connectivity: dispensers / droppers react to power at the block above them, crafters and lamps do not
	var w := fresh()
	raw(w, Vector3i(0, 0, 0), S("dispenser"))
	raw(w, Vector3i(3, 0, 0), S("dropper"))
	raw(w, Vector3i(6, 0, 0), S("crafter"))
	raw(w, Vector3i(9, 0, 0), S("redstone_lamp"))
	for x in [1, 4, 7, 10]:
		put(w, Vector3i(x, 1, 0), rb)
	ok("quasi-connectivity: dispensers / droppers powered from the block above them; crafters / lamps not",
		on(w, Vector3i(0, 0, 0), "triggered") and on(w, Vector3i(3, 0, 0), "triggered") and not on(w, Vector3i(6, 0, 0), "triggered") and not on(w, Vector3i(9, 0, 0), "lit"))
	w = fresh()
	raw(w, Vector3i(0, 0, 0), S("crafter"))
	put(w, Vector3i(1, 0, 0), rb)
	ok("crafter: triggered by power next to it", on(w, Vector3i(0, 0, 0), "triggered"))
	# hopper locked
	w = fresh()
	raw(w, Vector3i(0, 0, 0), S("hopper"))
	put(w, Vector3i(1, 0, 0), lever("floor", "north", true))
	var locked := not on(w, Vector3i(0, 0, 0), "enabled")
	put(w, Vector3i(1, 0, 0), lever("floor", "north", false))
	ok("hopper: locked while powered", locked and on(w, Vector3i(0, 0, 0), "enabled"))
	# note block: powered on the rising edge
	w = fresh()
	raw(w, Vector3i(0, 0, 0), S("note_block"))
	put(w, Vector3i(1, 0, 0), rb)
	ok("note block: powered (plays) when a signal arrives", on(w, Vector3i(0, 0, 0), "powered"))
	# TNT primes
	w = fresh()
	raw(w, Vector3i(0, 0, 0), S("tnt"))
	put(w, Vector3i(1, 0, 0), rb)
	var tnt_ok := w.state_at(0, 0, 0) == 0 and w.entities.ents.size() == 1 and int(w.entities.ents[0].fuse) == 80
	ok("TNT: powered TNT becomes primed TNT (fuse 80)", tnt_ok)
	# copper bulb toggles on every rising edge
	w = fresh()
	raw(w, Vector3i(0, 0, 0), S("copper_bulb"))
	put(w, Vector3i(1, 0, 0), rb)
	var lit1 := on(w, Vector3i(0, 0, 0), "lit") and on(w, Vector3i(0, 0, 0), "powered")
	put(w, Vector3i(1, 0, 0), 0)
	var lit2 := on(w, Vector3i(0, 0, 0), "lit") and not on(w, Vector3i(0, 0, 0), "powered")
	put(w, Vector3i(1, 0, 0), rb)
	ok("copper bulb: each pulse toggles it (on, stays on, off)", lit1 and lit2 and not on(w, Vector3i(0, 0, 0), "lit"))
	# activator rail
	w = fresh()
	raw(w, Vector3i(0, 0, 0), P(S("activator_rail"), "shape", "north_south"))
	put(w, Vector3i(1, 0, 0), rb)
	ok("activator rail: powered by a redstone block", on(w, Vector3i(0, 0, 0), "powered"))


# ------------------------------------------------------------------ pistons

func _pistons() -> void:
	var stone := S("stone")
	var rb := S("redstone_block")
	# push timing: the block event this tick, blocks moving for 2 ticks, solid at the third
	var w := fresh()
	raw(w, Vector3i(0, 0, 0), P(S("piston"), "facing", "east"))
	raw(w, Vector3i(1, 0, 0), stone)
	raw(w, Vector3i(2, 0, 0), S("dirt"))
	put(w, Vector3i(0, 1, 0), rb)
	var ev := on(w, Vector3i(0, 0, 0), "extended") and nm(w, Vector3i(1, 0, 0)) == "moving_piston" and nm(w, Vector3i(2, 0, 0)) == "moving_piston" and nm(w, Vector3i(3, 0, 0)) == "moving_piston" and Pistons.moving.size() == 3
	tick(w, 1)
	var mid := nm(w, Vector3i(3, 0, 0)) == "moving_piston"
	tick(w, 1)
	ok("piston: blocks move for 2 ticks (moving_piston cells), then land", ev and mid and nm(w, Vector3i(1, 0, 0)) == "piston_head" and nm(w, Vector3i(2, 0, 0)) == "stone" and nm(w, Vector3i(3, 0, 0)) == "dirt" and Pistons.moving.is_empty())
	put(w, Vector3i(0, 1, 0), 0)
	var head_gone := w.state_at(1, 0, 0) == 0 and nm(w, Vector3i(0, 0, 0)) == "moving_piston"
	tick(w, 2)
	ok("piston: retracts (head in, base moving 2 ticks), the pushed blocks stay", head_gone and nm(w, Vector3i(0, 0, 0)) == "piston" and not on(w, Vector3i(0, 0, 0), "extended") and nm(w, Vector3i(2, 0, 0)) == "stone")
	# quasi-connectivity: a redstone block diagonally above powers the piston (not a lamp in the same spot)
	w = fresh()
	raw(w, Vector3i(0, 0, 0), P(S("sticky_piston"), "facing", "north"))
	put(w, Vector3i(1, 1, 0), rb)
	ok("piston: quasi-connectivity (power at the block above it)", on(w, Vector3i(0, 0, 0), "extended"))
	# a piston is not powered through its front
	w = fresh()
	raw(w, Vector3i(0, 0, 0), P(S("piston"), "facing", "east"))
	put(w, Vector3i(1, 0, 0), rb)
	ok("piston: not powered from its face", not on(w, Vector3i(0, 0, 0), "extended"))
	# sticky: pulls back; a short pulse drops the block
	w = fresh()
	raw(w, Vector3i(0, 0, 0), P(S("sticky_piston"), "facing", "east"))
	raw(w, Vector3i(1, 0, 0), stone)
	put(w, Vector3i(0, 1, 0), rb)
	tick(w, 2)
	put(w, Vector3i(0, 1, 0), 0)
	tick(w, 2)
	ok("sticky piston: pulls the block back", nm(w, Vector3i(1, 0, 0)) == "stone" and w.state_at(2, 0, 0) == 0 and nm(w, Vector3i(0, 0, 0)) == "sticky_piston")
	w = fresh()
	raw(w, Vector3i(0, 0, 0), P(S("sticky_piston"), "facing", "east"))
	raw(w, Vector3i(1, 0, 0), stone)
	put(w, Vector3i(0, 1, 0), rb)
	tick(w, 1)
	put(w, Vector3i(0, 1, 0), 0)
	tick(w, 3)
	ok("sticky piston: a pulse shorter than the extension drops the block", nm(w, Vector3i(2, 0, 0)) == "stone" and w.state_at(1, 0, 0) == 0 and not on(w, Vector3i(0, 0, 0), "extended"))
	# a sticky piston does not pull a block that breaks when pushed (torch) nor glazed terracotta
	w = fresh()
	raw(w, Vector3i(0, 0, 0), P(S("sticky_piston"), "facing", "east"))
	raw(w, Vector3i(2, 0, 0), S("orange_glazed_terracotta"))
	raw(w, Vector3i(1, 0, 0), stone)
	put(w, Vector3i(0, 1, 0), rb)
	tick(w, 2)
	var pushed := nm(w, Vector3i(3, 0, 0)) == "orange_glazed_terracotta"
	put(w, Vector3i(0, 1, 0), 0)
	tick(w, 2)
	ok("sticky piston: pulls the block in front only (glazed terracotta is pushed, never pulled)", pushed and nm(w, Vector3i(1, 0, 0)) == "stone" and nm(w, Vector3i(3, 0, 0)) == "orange_glazed_terracotta")
	# breakable blocks drop: a torch in front breaks
	w = fresh()
	raw(w, Vector3i(0, 0, 0), P(S("piston"), "facing", "east"))
	raw(w, Vector3i(1, 0, 0), S("pumpkin"))
	put(w, Vector3i(0, 1, 0), rb)
	tick(w, 2)
	ok("piston: a pumpkin in front breaks and drops", w.entities.dropped.has("pumpkin") and nm(w, Vector3i(1, 0, 0)) == "piston_head")
	# entities on a block pushed up ride on it (Java moveCollidedEntities: overlap + 0.01 per tick); slime launches them
	for blk in ["stone", "slime_block"]:
		w = fresh()
		raw(w, Vector3i(0, 0, 0), P(S("piston"), "facing", "up"))
		raw(w, Vector3i(0, 1, 0), S(blk))
		var e := EntityManager.Ent.new()
		e.kind = "mob"
		e.pos = Vector3(0.5, 2.0, 0.5)
		e.w = 0.6
		e.h = 1.8
		w.entities.ents.append(e)
		put(w, Vector3i(1, 0, 0), rb)
		tick(w, 2)
		if blk == "stone":
			ok("piston: an entity standing on the pushed block is lifted with it", e.pos.y >= 3.0 and e.pos.y < 3.1, str(e.pos))
		else:
			ok("piston: a pushed slime block launches the entity (1 block / tick)", is_equal_approx(e.vel.y, 1.0), str(e.vel))
	# head + base are one block: breaking the head breaks the piston (it drops), breaking the base removes the head
	w = fresh()
	var base := P(P(S("sticky_piston"), "facing", "east"), "extended", "true")
	var head := P(P(S("piston_head"), "facing", "east"), "type", "sticky")
	raw(w, Vector3i(0, 0, 0), base)
	raw(w, Vector3i(1, 0, 0), head)
	ok("piston head: survives with its piston behind it", BlockUpdates._has_support(w, Vector3i(1, 0, 0), head))
	w.set_block(1, 0, 0, 0)
	Interaction.on_block_broken(w, Vector3i(1, 0, 0), head)
	ok("piston: breaking the head breaks the piston, which drops (the head never does)", w.state_at(0, 0, 0) == 0 and w.entities.dropped == ["sticky_piston"], str(w.entities.dropped))
	w = fresh()
	raw(w, Vector3i(0, 0, 0), base)
	raw(w, Vector3i(1, 0, 0), head)
	w.set_block(0, 0, 0, 0)
	Interaction.on_block_broken(w, Vector3i(0, 0, 0), base)
	ok("piston: breaking the base removes the head (no drop)", w.state_at(1, 0, 0) == 0 and w.entities.dropped.is_empty())
	ok("piston head: without its piston it cannot stay", not BlockUpdates._has_support(w, Vector3i(1, 0, 0), head))
	ok("piston: the head drops nothing", Loot.block_drops(head, null, w, Vector3i(1, 0, 0)).is_empty())


# ------------------------------------------------------------------ placement support

func _placement() -> void:
	var w := fresh()
	var wire := S("redstone_wire")
	var cases := [["stone", true], ["redstone_wire", false], ["glass", true], ["hopper", true], ["glowstone", true], ["oak_leaves", false],
		["air", false], ["oak_slab", false], ["oak_fence", false], ["oak_trapdoor", false], ["soul_sand", true]]
	var bad: Array = []
	for c in cases:
		raw(w, Vector3i(0, 0, 0), S(str(c[0])) if str(c[0]) != "air" else 0)
		if BlockUpdates._has_support(w, Vector3i(0, 1, 0), wire) != bool(c[1]):
			bad.append(c[0])
	raw(w, Vector3i(0, 0, 0), P(S("oak_slab"), "type", "top"))
	if not BlockUpdates._has_support(w, Vector3i(0, 1, 0), wire):
		bad.append("top slab")
	raw(w, Vector3i(0, 0, 0), P(S("oak_stairs"), "half", "top"))
	if not BlockUpdates._has_support(w, Vector3i(0, 1, 0), wire):
		bad.append("upside-down stairs")
	ok("dust survives only on a sturdy top or a hopper (not on dust, leaves, bottom slabs, fences, air)", bad.is_empty(), str(bad))
	# the same rule refuses the placement (Support.placement): dust on dust is never placed
	var w2 := fresh()
	raw(w2, Vector3i(0, 0, 0), wire)
	ok("dust placement on dust is refused (Support rule)", Support.kind_of(wire) == Support.K_WIRE and not Support.can_survive(w2, Vector3i(0, 1, 0), wire))
	# dust on a block a piston pushes away pops off when the block has gone (Support on the moved cells' changes)
	var w3 := fresh()
	raw(w3, Vector3i(0, 0, 0), P(S("piston"), "facing", "east"))
	raw(w3, Vector3i(1, 0, 0), S("stone"))
	raw(w3, Vector3i(1, 1, 0), wire)
	put(w3, Vector3i(0, 1, 0), S("redstone_block"))
	tick(w3, 3)
	ok("dust on a pushed block pops off (no floating dust)", w3.state_at(1, 1, 0) == 0 and w3.entities.dropped.has("redstone"), str(w3.entities.dropped))
