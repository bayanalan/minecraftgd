## Redstone — Java redstone signal rules (wiki Redstone mechanics, Redstone Torch, Lever, Repeater, Comparator, ...):
## - Signals: every component has Java's weak signal (getSignal: what an adjacent block receives from it, _weak) and
##   strong signal (getDirectSignal: what it pushes into an adjacent block, _strong). Levers / buttons strongly power the
##   block they hang on, plates / detector rails / lecterns / trapped chests / sculk sensors the block below, torches the
##   block above (and never weakly power their own block), lightning rods / tripwire hooks the block behind them,
##   repeaters / comparators / observers their output side; redstone blocks, daylight detectors, targets and jukeboxes
##   only weakly. A conductor (Java isRedstoneConductor, wiki Conductivity: full-collision blocks except glass, stained /
##   tinted glass, glowstone, sea lanterns, leaves, ice, honey, TNT, redstone blocks, observers, pistons, beacons,
##   spawners, copper bulbs / grates; soul sand and mud always) passes on the strongest strong signal it receives
##   (Level.getSignal). Dust under / pointing into a block powers it that way too ("weakly powered"): components beside it
##   react, other dust does not (dust ignores dust signals while it computes its own level).
## - Inputs: Level.hasNeighborSignal for lamps, doors (either half; both halves switch, door / trapdoor / gate sounds),
##   trapdoors, fence gates, note blocks, TNT, bells, hoppers, crafters, copper bulbs (toggle on each rising edge),
##   command blocks, powered / activator rails; pistons, dispensers and droppers also from the block above
##   (quasi-connectivity); torches from the block they hang on; repeaters / comparators from behind (plus the power of
##   dust there) with side inputs (repeaters: diodes only -> locked; comparators: any signal source).
## - Timing: torches 2 ticks (burnout: 8 forced turn-offs within 60 ticks, retry after 160), repeaters 2 x delay (once on
##   they stay on for their delay: pulse extension), comparators 2 ticks (stored output), lamps off after 4 ticks,
##   observers 2 + 2, buttons 20 (stone) / 30 (wooden), pistons via Pistons (block events, 2-tick moving blocks).
## Updates: immediate on_changed(world, pos), or request(world, pos) queued and flushed once per tick. Every change
## re-checks the wires and consumers within 2 blocks (Java's neighbour-update reach).
## Parity: Java's update ORDER is not matched (QC "budding" without a block update, 0-tick pulses, update-order races).
class_name Redstone

const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
const H := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0), "up": Vector3i(0, 1, 0), "down": Vector3i(0, -1, 0)}
const UP := Vector3i(0, 1, 0)
const DOWN := Vector3i(0, -1, 0)
const PUSH_LIMIT := 12
const NONE := Vector3i(0, -99999, 0)
static var _depth := 0
static var _pending: Dictionary = {}
static var _no_dust := false   # Java RedStoneWireBlock.shouldSignal == false: dust computing its level ignores dust


# ------------------------------------------------------------------ per-state tables

## Signal kinds (Java getSignal / getDirectSignal shapes).
const K_WIRE := 1
const K_BLOCK := 2        # redstone block: 15 on every side, never strong
const K_ATTACHED := 3     # lever / buttons (powered): every side; strong into the block they hang on
const K_PLATE := 4        # pressure plates (powered / weighted power): every side; strong into the block below
const K_TORCH := 5        # standing torch (lit): every side but down; strong up
const K_WALL_TORCH := 6   # wall torch (lit): every side but its wall; strong up
const K_HOOK := 7         # tripwire hook (powered): every side; strong into its wall
const K_DETECTOR := 8     # detector rail (powered): every side; strong down
const K_LEVEL := 9        # daylight detector / target (power): every side, never strong
const K_OBSERVER := 10    # its back (powered): weak + strong
const K_REPEATER := 11    # its front (powered): weak + strong 15
const K_COMPARATOR := 12  # its front: weak + strong = stored output
const K_ROD := 13         # lightning rod (powered): every side; strong into the block behind it
const K_SCULK := 14       # sculk sensors (Sculk.power_at): every side; strong down
const K_LECTERN := 15     # lectern (powered page-turn pulse): every side; strong down
const K_TRAPPED := 16     # trapped chest: players viewing (1-15) on every side; strong down
const K_JUKEBOX := 17     # jukebox while a disc plays: every side, never strong

## wiki Conductivity (Java): full blocks that do not conduct.
const NEVER_COND := ["redstone_block", "observer", "piston", "sticky_piston", "glass", "tinted_glass", "glowstone", "sea_lantern",
	"ice", "frosted_ice", "honey_block", "tnt", "beacon", "spawner", "trial_spawner"]

static var _kind := PackedByteArray()
static var _cond := PackedByteArray()


static func _tables() -> void:
	var b := Res.blocks
	var nb := b.names.size()
	var per := PackedByteArray()
	per.resize(nb)
	var pc := PackedByteArray()   # 0 = by collision shape, 1 = never, 2 = always
	pc.resize(nb)
	for i in nb:
		var n: String = b.names[i]
		per[i] = _kind_of_name(n)
		if n in NEVER_COND or n.ends_with("_stained_glass") or n.ends_with("_leaves") or n.ends_with("copper_grate") or n.ends_with("copper_bulb"):
			pc[i] = 1
		elif n == "soul_sand" or n == "mud" or n == "barrier":
			pc[i] = 2   # (barriers: full collision in Java, their model has no box to measure)
	var k := PackedByteArray()
	k.resize(b.total_states)
	var c := PackedByteArray()
	c.resize(b.total_states)
	var full := BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_COLLIDE
	for s in range(1, b.total_states):
		var bi: int = b.st_block[s]
		k[s] = per[bi]
		c[s] = 1 if pc[bi] == 2 or (pc[bi] == 0 and (b.st_flags[s] & full) == full) else 0
	_kind = k
	_cond = c


static func _kind_of_name(n: String) -> int:
	if n == "redstone_wire":
		return K_WIRE
	if n == "redstone_block":
		return K_BLOCK
	if n == "lever" or n.ends_with("_button"):
		return K_ATTACHED
	if n.ends_with("_pressure_plate"):
		return K_PLATE
	if n == "redstone_torch":
		return K_TORCH
	if n == "redstone_wall_torch":
		return K_WALL_TORCH
	if n == "tripwire_hook":
		return K_HOOK
	if n == "detector_rail":
		return K_DETECTOR
	if n == "daylight_detector" or n == "target":
		return K_LEVEL
	if n == "observer":
		return K_OBSERVER
	if n == "repeater":
		return K_REPEATER
	if n == "comparator":
		return K_COMPARATOR
	if n.ends_with("lightning_rod"):
		return K_ROD
	if n == "sculk_sensor" or n == "calibrated_sculk_sensor":
		return K_SCULK
	if n == "lectern":
		return K_LECTERN
	if n == "trapped_chest":
		return K_TRAPPED
	if n == "jukebox":
		return K_JUKEBOX
	return 0


## Signal kind of a state (0 = no signal source).
static func kind(st: int) -> int:
	if st <= 0:
		return 0
	if _kind.size() != Res.blocks.total_states:
		_tables()
	return _kind[st] if st < _kind.size() else 0


## Java isRedstoneConductor.
static func conductor(st: int) -> bool:
	if st <= 0:
		return false
	if _cond.size() != Res.blocks.total_states:
		_tables()
	return st < _cond.size() and _cond[st] != 0


## Per-state relevance (built once): 1 = redstone wire, 2 = reacts in _update_consumer. Everything else is inert
## for on_changed, which lets the per-tick flush skip the (pure) power computation for ordinary blocks.
static var _rel := PackedByteArray()


static func _relevance(st: int) -> int:
	if st <= 0:
		return 0
	if _rel.size() != Res.blocks.total_states:
		var b := Res.blocks
		var t := PackedByteArray()
		t.resize(b.total_states)
		for s in range(1, b.total_states):
			t[s] = _relevance_of(s)
		_rel = t
	return _rel[st] if st < _rel.size() else _relevance_of(st)


static func _relevance_of(st: int) -> int:
	var b := Res.blocks
	var n := b.name_of(st)
	if n == "redstone_wire":
		return 1
	if n in ["repeater", "comparator", "piston", "sticky_piston", "dispenser", "dropper", "crafter", "hopper", "powered_rail", "activator_rail",
			"redstone_lamp", "tnt", "note_block", "redstone_torch", "redstone_wall_torch", "bell"]:
		return 2
	if (n.ends_with("_door") or n.ends_with("_trapdoor") or n.ends_with("_fence_gate") or n.ends_with("copper_bulb") or Shelf.is_shelf(n)) and b.has_prop(st, "powered"):
		return 2
	if CommandBlocks.is_command_block(n):
		return 2
	return 0


static func _state(world, p: Vector3i) -> int:
	return world.state_at(p.x, p.y, p.z)


static func _name(st: int) -> String:
	return Res.blocks.name_of(st) if st > 0 else "air"


static func _dir(st: int) -> Vector3i:
	return H.get(Res.blocks.get_prop(st, "facing"), Vector3i.ZERO)


## The block a lever / button hangs on (Java FaceAttachedHorizontalDirectionalBlock.getConnectedDirection opposite).
static func attached_block(st: int, p: Vector3i) -> Vector3i:
	match Res.blocks.get_prop(st, "face"):
		"floor":
			return p + DOWN
		"ceiling":
			return p + UP
	return p - _dir(st)


static func _on(st: int, prop: String) -> bool:
	return Res.blocks.get_prop(st, prop) == "true"


static func _plate(st: int) -> int:
	var b := Res.blocks
	if b.has_prop(st, "power"):
		return int(b.get_prop(st, "power"))   # weighted plates
	return 15 if b.get_prop(st, "powered") == "true" else 0


# ------------------------------------------------------------------ signals

## Java getSignal: the weak signal the block at src (state st) gives the adjacent block at dst.
static func _weak(world, src: Vector3i, st: int, dst: Vector3i) -> int:
	match kind(st):
		0:
			return 0
		K_WIRE:
			return 0 if _no_dust else RedstoneWire.signal_to(world, src, st, dst)
		K_BLOCK:
			return 15
		K_ATTACHED, K_HOOK, K_DETECTOR, K_ROD, K_LECTERN:
			return 15 if _on(st, "powered") else 0
		K_PLATE:
			return _plate(st)
		K_TORCH:
			return 15 if _on(st, "lit") and dst != src + DOWN else 0
		K_WALL_TORCH:
			return 15 if _on(st, "lit") and dst != src - _dir(st) else 0
		K_LEVEL:
			return int(Res.blocks.get_prop(st, "power"))
		K_OBSERVER, K_REPEATER:
			return 15 if _on(st, "powered") and dst == src - _dir(st) else 0
		K_COMPARATOR:
			return comparator_output(world, src, st) if dst == src - _dir(st) else 0
		K_SCULK:
			return Sculk.power_at(src)
		K_TRAPPED:
			return trapped_signal(src)
		K_JUKEBOX:
			return 15 if BlockEntities.jukebox_playing(world, src) else 0
	return 0


## Java getDirectSignal: the strong signal the block at src (state st) pushes into the adjacent block at dst.
static func _strong(world, src: Vector3i, st: int, dst: Vector3i) -> int:
	match kind(st):
		0:
			return 0
		K_WIRE:
			return 0 if _no_dust else RedstoneWire.signal_to(world, src, st, dst)   # (dust's direct signal = its signal)
		K_ATTACHED:
			return 15 if _on(st, "powered") and dst == attached_block(st, src) else 0
		K_PLATE:
			return _plate(st) if dst == src + DOWN else 0
		K_TORCH, K_WALL_TORCH:
			return 15 if _on(st, "lit") and dst == src + UP else 0
		K_HOOK, K_ROD:
			return 15 if _on(st, "powered") and dst == src - _dir(st) else 0
		K_DETECTOR, K_LECTERN:
			return 15 if _on(st, "powered") and dst == src + DOWN else 0
		K_OBSERVER, K_REPEATER, K_COMPARATOR:
			return _weak(world, src, st, dst)
		K_SCULK:
			return Sculk.power_at(src) if dst == src + DOWN else 0
		K_TRAPPED:
			return trapped_signal(src) if dst == src + DOWN else 0
	return 0


## Java Level.getDirectSignalTo: the strongest strong signal reaching the block at q.
static func direct_to(world, q: Vector3i) -> int:
	var best := 0
	for d in DIRS:
		var r: Vector3i = q + d
		var rs := _state(world, r)
		if rs > 0 and kind(rs) != 0:
			best = maxi(best, _strong(world, r, rs, q))
			if best >= 15:
				return 15
	return best


## Java Level.getSignal: what the block at dst receives from its neighbour src (a conductor passes on the strong power
## it receives).
static func signal_from(world, src: Vector3i, dst: Vector3i) -> int:
	var st := _state(world, src)
	if st <= 0:
		return 0
	var w := _weak(world, src, st, dst)
	if w < 15 and conductor(st):
		w = maxi(w, direct_to(world, src))
	return w


## Java Level.hasNeighborSignal.
static func has_neighbor_signal(world, p: Vector3i) -> bool:
	for d in DIRS:
		if signal_from(world, p + d, p) > 0:
			return true
	return false


## Java Level.getBestNeighborSignal.
static func best_neighbor_signal(world, p: Vector3i) -> int:
	var best := 0
	for d in DIRS:
		best = maxi(best, signal_from(world, p + d, p))
		if best >= 15:
			return 15
	return best


## (kept names) weak signal src -> dst; the input power a block receives; whether it is powered.
static func emitted(world, src: Vector3i, dst: Vector3i) -> int:
	var st := _state(world, src)
	return _weak(world, src, st, dst) if st > 0 else 0


static func power_at(world, p: Vector3i) -> int:
	return best_neighbor_signal(world, p)


static func _powered_any(world, p: Vector3i) -> bool:
	return has_neighbor_signal(world, p)


## The level a source gives out on its strongest side (0..15).
static func source_power(world, p: Vector3i) -> int:
	var st := _state(world, p)
	if st <= 0 or kind(st) == 0:
		return 0
	var best := 0
	for d in DIRS:
		best = maxi(best, _weak(world, p, st, p + d))
	return best


## Pistons: any side but the front, or (quasi-connectivity) anything that would power the block above
## (Java PistonBaseBlock.getNeighborSignal).
static func piston_powered(world, p: Vector3i, st: int) -> bool:
	var f := _dir(st)
	for d in DIRS:
		if d != f and signal_from(world, p + d, p) > 0:
			return true
	var a := p + UP
	for d in DIRS:
		if d != DOWN and signal_from(world, a + d, a) > 0:
			return true
	return false


## Trapped chests: players with the chest open (Java TrappedChestBlockEntity open count, clamped to 15).
static var _trapped: Dictionary = {}


static func trapped_signal(p: Vector3i) -> int:
	return mini(int(_trapped.get(p, 0)), 15)


## A container screen opened (+1) / closed (-1) a trapped chest (both halves of a large one).
static func chest_viewers(world, p: Vector3i, p2: Vector3i, delta: int) -> void:
	for q in [p, p2]:
		if q.y < -9000:
			continue
		var n := maxi(0, int(_trapped.get(q, 0)) + delta)
		if n == 0:
			_trapped.erase(q)
		else:
			_trapped[q] = n
		on_changed(world, q)
		on_changed(world, q + DOWN)


# ------------------------------------------------------------------ comparators / measuring

static func container_signal(world, p: Vector3i) -> int:
	var d: Dictionary = BlockEntities.get_data(world, p)
	if d.is_empty() or not d.has("items"):
		return 0
	if str(d.get("id", "")) == "crafter":
		return Crafter.signal_strength(d)
	return items_signal(d["items"])


## Comparator fullness of a slot list: floor(1 + sum(count / max stack) / slots x 14), 0 when empty.
static func items_signal(items: Array) -> int:
	if items.is_empty():
		return 0
	var f := 0.0
	var any := false
	for it in items:
		var s := ItemStack.from_dict(it)
		if not s.is_empty():
			f += float(s.count) / float(maxi(s.max_stack(), 1))
			any = true
	if not any:
		return 0
	return int(floor(1.0 + f / float(items.size()) * 14.0))


static var _song_signal: Dictionary = {}   # jukebox_song id -> comparator_output (26.3 data)


## Comparator reading of a measurable block at q (Java getAnalogOutputSignal), -1 when it has none.
## wiki: Redstone_Comparator (measuring block state), Respawn_Anchor, Lectern, Shelf, Composter.
static func measure(world, q: Vector3i, qs: int, f: Vector3i) -> int:
	if qs <= 0:
		return -1
	var b := Res.blocks
	var n := b.name_of(qs)
	if Shelf.is_shelf(n):
		# Java ShelfBlock: read only from its back (the comparator behind the shelf)
		return Shelf.comparator(world, q) if Shelf.FRONT.get(b.get_prop(qs, "facing"), Vector3i.ZERO) == -f else 0
	match n:
		"cake":
			return (7 - int(b.get_prop(qs, "bites"))) * 2   # 2 per slice left, full cake 14
		"composter":
			return int(b.get_prop(qs, "level"))   # 0-8 (8 = bone meal ready)
		"water_cauldron", "powder_snow_cauldron":
			return int(b.get_prop(qs, "level"))
		"lava_cauldron":
			return 3
		"cauldron":
			return 0
		"end_portal_frame":
			return 15 if b.get_prop(qs, "eye") == "true" else 0
		"respawn_anchor":
			return [0, 3, 7, 11, 15][clampi(int(b.get_prop(qs, "charges")), 0, 4)]
		"beehive", "bee_nest":
			return int(b.get_prop(qs, "honey_level"))   # honey amount, max 5
		"jukebox":
			return _disc_signal(BlockEntities.get_data(world, q))
		"lectern":
			return _lectern_signal(BlockEntities.get_data(world, q))
		"detector_rail":
			return Sensors.detector_signal(world, q, qs)
	if n.ends_with("copper_bulb"):
		return 15 if b.get_prop(qs, "lit") == "true" else 0
	if CommandBlocks.is_command_block(n):
		return mini(int(BlockEntities.get_data(world, q).get("SuccessCount", 0)), 15)
	var d: Dictionary = BlockEntities.get_data(world, q)
	if not d.is_empty() and d.has("items"):
		return container_signal(world, q)
	return -1


## Jukebox: the playing disc's jukebox_song comparator_output (0 without a disc).
static func _disc_signal(d: Dictionary) -> int:
	if not d.has("disc"):
		return 0
	var song := str((d["disc"] as Dictionary).get("id", "")).trim_prefix("minecraft:").trim_prefix("music_disc_")
	if not _song_signal.has(song):
		var sj = Res.read_json("data/minecraft/jukebox_song/%s.json" % song)
		_song_signal[song] = int(sj.get("comparator_output", 0)) if sj is Dictionary else 0
	return int(_song_signal[song])


## Lectern: floor(1 + (page - 1) / (pages - 1) * 14) with 1-based pages; a one-page book gives 15, no book 0.
static func _lectern_signal(d: Dictionary) -> int:
	if not d.has("book"):
		return 0
	var bk := ItemStack.from_dict(d["book"])
	var c = bk.components.get("minecraft:writable_book_content" if bk.name() == "writable_book" else "minecraft:written_book_content", {})
	var pages: int = (c.get("pages", []) as Array).size() if c is Dictionary and c.get("pages") is Array else 0
	if pages <= 1:
		return 15
	var page := clampi(int(d.get("page", 0)), 0, pages - 1)   # stored 0-based
	return int(floor(1.0 + float(page) / float(pages - 1) * 14.0))


## Java DiodeBlock.getInputSignal: the rear block's signal toward the diode, or the power of dust there.
static func _diode_input(world, p: Vector3i, st: int) -> int:
	var rear := p + _dir(st)
	var i := signal_from(world, rear, p)
	if i >= 15:
		return i
	var rs := _state(world, rear)
	if rs > 0 and kind(rs) == K_WIRE:
		i = maxi(i, int(Res.blocks.get_prop(rs, "power")))
	return i


## Java DiodeBlock.getAlternateSignal: the stronger side input (repeaters: only diodes pointing in; comparators:
## redstone blocks 15, dust its power, any other signal source its signal).
static func _side_input(world, p: Vector3i, st: int, diodes_only: bool) -> int:
	var f := _dir(st)
	var best := 0
	for s in [Vector3i(f.z, 0, -f.x), Vector3i(-f.z, 0, f.x)]:
		var sp: Vector3i = p + s
		var ss := _state(world, sp)
		var k := kind(ss)
		if k == 0:
			continue
		if diodes_only:
			if k == K_REPEATER or k == K_COMPARATOR:
				best = maxi(best, signal_from(world, sp, p))
		elif k == K_BLOCK:
			best = 15
		elif k == K_WIRE:
			best = maxi(best, int(Res.blocks.get_prop(ss, "power")))
		else:
			best = maxi(best, signal_from(world, sp, p))
	return best


static func _repeater_locked(world, p: Vector3i, st: int) -> bool:
	return _side_input(world, p, st, true) > 0


## Java ComparatorBlock.calculateOutputSignal (rear input incl. a measured block, also through one conductor, vs. the
## stronger side input).
static func comparator_calc(world, p: Vector3i, st: int) -> int:
	var f := _dir(st)
	var rear := p + f
	var rs := _state(world, rear)
	var r := _diode_input(world, p, st)
	var m := measure(world, rear, rs, f)
	if m >= 0:
		r = m
	elif r < 15 and conductor(rs):
		# wiki: Redstone_Comparator - a measured block may sit behind a conductive block (unless that is powered 15)
		var far := rear + f
		var m2 := measure(world, far, _state(world, far), f)
		if m2 >= 0:
			r = m2
	if r <= 0:
		return 0
	var side := _side_input(world, p, st, false)
	if Res.blocks.get_prop(st, "mode") == "subtract":
		return maxi(r - side, 0)
	return r if r >= side else 0


static var _cmp_out: Dictionary = {}      # Vector3i -> comparator output since its last scheduled update (Java BE)


## The comparator's current output (the stored value of its last update; a powered comparator without one - loaded
## from disk - recomputes it).
static func comparator_output(world, p: Vector3i, st: int) -> int:
	if Res.blocks.get_prop(st, "powered") != "true":
		return 0
	if _cmp_out.has(p):
		return int(_cmp_out[p])
	return comparator_calc(world, p, st)


# ------------------------------------------------------------------ updates

static func request(world, p: Vector3i) -> void:
	# on_changed only touches wires / consumers within 2 blocks: nothing to queue when none exist there (block entity
	# writes of freshly loaded structures used to queue hundreds of full neighbourhood scans per tick)
	if world.get("cm") != null and (Interest.near(world, p, 2) & (Interest.WIRE | Interest.CONSUMER)) == 0:
		return
	_pending[p] = true


## Called once per game tick by the world.
static func flush(world) -> void:
	if _pending.is_empty():
		return
	var lst: Array = _pending.keys()
	_pending.clear()
	for p in lst.slice(0, 256):
		on_changed(world, p)


static func reset() -> void:
	_pending.clear()
	_cmp_out.clear()
	_trapped.clear()
	_torch_offs.clear()
	_torch_restart.clear()
	_rail_done.clear()
	_due.clear()
	_depth = 0
	_no_dust = false


## Observer hook: a block at p changed -> observers watching p pulse after 2 ticks.
static func notify_observers(world, p: Vector3i) -> void:
	for d in DIRS:
		var q: Vector3i = p + d
		var st := _state(world, q)
		if st > 0 and kind(st) == K_OBSERVER and q + _dir(st) == p and Res.blocks.get_prop(st, "powered") != "true":
			schedule_tick(world, q, 2)


## A redstone state change (set without the world's listeners): observers watching it still see it.
static func _put(world, p: Vector3i, st: int) -> void:
	world.set_block(p.x, p.y, p.z, st, false)
	if world.get("cm") == null or (Interest.near(world, p, 1) & Interest.OBSERVER) != 0:
		notify_observers(world, p)


## Offsets within 2 blocks (taxicab): Java's neighbour-update reach of one change.
static var _reach: Array = []


static func _reach2() -> Array:
	if _reach.is_empty():
		var seen := {}
		for d in DIRS + [Vector3i.ZERO]:
			for d2 in DIRS + [Vector3i.ZERO]:
				var o: Vector3i = d + d2
				if not seen.has(o):
					seen[o] = true
					_reach.append(o)
	return _reach


static func on_changed(world, p: Vector3i) -> void:
	if _depth > 8:
		return
	if _depth == 0 and not _rail_done.is_empty():
		_rail_done.clear()
	_depth += 1
	var reach := _reach2()
	_update_wires(world, p, reach)
	for o in reach:
		_update_consumer(world, p + o)
	_depth -= 1


static func _update_wires(world, p: Vector3i, reach: Array) -> void:
	var b := Res.blocks
	var net := {}
	var q: Array = []
	for o in reach:
		var s: Vector3i = p + o
		if _relevance(_state(world, s)) == 1:
			net[s] = true
			q.append(s)
	if net.is_empty():
		return
	while not q.is_empty() and net.size() < 4096:
		var c: Vector3i = q.pop_back()
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			for dy in [0, 1, -1]:
				var n: Vector3i = c + d + Vector3i(0, dy, 0)
				if net.has(n):
					continue
				if RedstoneWire.is_wire(_state(world, n)):
					net[n] = true
					q.append(n)
	# Java calculateTargetStrength: the best neighbour signal with dust signals off, then adjacent dust - 1
	var power := {}
	var bq: Array = []
	_no_dust = true
	for w in net:
		var sp := best_neighbor_signal(world, w)
		power[w] = sp
		if sp > 0:
			bq.append(w)
	_no_dust = false
	# dust -> dust minus 1 along Java's directed links (RedstoneWire.power_targets: a conductive block above the lower
	# dust cuts the climb; non-conductive blocks pass power up, never down)
	while not bq.is_empty():
		var c: Vector3i = bq.pop_front()
		var v: int = power[c] - 1
		if v <= 0:
			continue
		for n in RedstoneWire.power_targets(world, c):
			if net.has(n) and int(power[n]) < v:
				power[n] = v
				bq.append(n)
	var changed: Array = []
	for w in net:
		var st := _state(world, w)
		var ns := b.with_prop(st, "power", str(power[w]))
		if ns != st:
			_put(world, w, ns)
			changed.append(w)
	# consumers next to any wire whose level changed (and beside the conductors it powers)
	var seen := {}
	for w in changed:
		for d in DIRS:
			var c: Vector3i = w + d
			if seen.has(c):
				continue
			seen[c] = true
			var cs := _state(world, c)
			if cs > 0 and not RedstoneWire.is_wire(cs):
				_update_consumer(world, c)
				if conductor(cs):
					for d2 in DIRS:
						if not seen.has(c + d2):
							_update_consumer(world, c + d2)


static func _door_like(n: String) -> bool:
	return n.ends_with("_door") or n.ends_with("_trapdoor") or n.ends_with("_fence_gate")


## Java BlockSetType / WoodType open / close sounds of a door, trapdoor or fence gate.
static func door_sound(n: String, open: bool) -> String:
	var suffix := ".open" if open else ".close"
	var t := Sensors.set_type(n)   # wooden / cherry_wood / bamboo_wood / nether_wood
	if n.ends_with("_fence_gate"):
		return ("block.fence_gate" if t == "wooden" else "block.%s_fence_gate" % t) + suffix
	var what := "door" if n.ends_with("_door") else "trapdoor"
	if n.begins_with("iron_"):
		return "block.iron_%s%s" % [what, suffix]
	if n.contains("copper_"):
		return "block.copper_%s%s" % [what, suffix]
	return "block.%s_%s%s" % [t, what, suffix]


## Door / trapdoor / fence gate open-close sound: volume 1, pitch 0.9-1.0 (wiki Door / Trapdoor / Fence Gate sounds).
static func play_door_sound(p: Vector3i, n: String, open: bool) -> void:
	Audio.play(door_sound(n, open), Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks", 1.0, 0.9 + randf() * 0.1)


## Java DoorBlock / TrapDoorBlock / FenceGateBlock.neighborChanged: a power change sets POWERED and OPEN (a door reads
## both halves and switches both).
static func _door_update(world, p: Vector3i, st: int, n: String) -> void:
	var b := Res.blocks
	if n.ends_with("_door"):
		var lower := b.get_prop(st, "half") == "lower"
		var o := p + (UP if lower else DOWN)
		var os := _state(world, o)
		var pair := os > 0 and b.st_block[os] == b.st_block[st]
		var pw := has_neighbor_signal(world, p) or has_neighbor_signal(world, o)
		if _on(st, "powered") == pw:
			return
		var flip := _on(st, "open") != pw
		var v := "true" if pw else "false"
		_put(world, p, b.with_prop(b.with_prop(st, "powered", v), "open", v))
		if pair:
			_put(world, o, b.with_prop(b.with_prop(os, "powered", v), "open", v))
		if flip:
			play_door_sound(p, n, pw)
		return
	var pw2 := has_neighbor_signal(world, p)
	if _on(st, "powered") == pw2:
		return
	var v2 := "true" if pw2 else "false"
	var ns := b.with_prop(st, "powered", v2)
	var flip2 := _on(st, "open") != pw2
	if flip2:
		ns = b.with_prop(ns, "open", v2)
	_put(world, p, ns)
	if flip2:
		play_door_sound(p, n, pw2)
	if n.ends_with("_trapdoor") and b.get_prop(ns, "waterlogged") == "true":
		BlockUpdates.schedule(world, p, 5)


## Java getStateForPlacement: doors (either half's space), trapdoors and fence gates placed with power come open.
static func placed_state(world, p: Vector3i, st: int) -> int:
	var b := Res.blocks
	if st <= 0 or not b.has_prop(st, "powered"):
		return st
	var n := b.name_of(st)
	if not _door_like(n):
		return st
	var pw := has_neighbor_signal(world, p) or (n.ends_with("_door") and has_neighbor_signal(world, p + UP))
	if not pw:
		return st
	return b.with_prop(b.with_prop(st, "powered", "true"), "open", "true")


static func _update_consumer(world, p: Vector3i) -> void:
	var b := Res.blocks
	var st := _state(world, p)
	if (_relevance(st) & 2) == 0:
		return
	var n := b.name_of(st)
	match n:
		"repeater":
			# Java RepeaterBlock.updateShape (LOCKED) + DiodeBlock.checkTickOnNeighbor
			var locked := _repeater_locked(world, p, st)
			if _on(st, "locked") != locked:
				_put(world, p, b.with_prop(st, "locked", "true" if locked else "false"))
				st = _state(world, p)
			if not locked and (_diode_input(world, p, st) > 0) != _on(st, "powered"):
				schedule_tick(world, p, int(b.get_prop(st, "delay")) * 2)
			return
		"comparator":
			# a strength change also needs the delayed update (Java ComparatorBlock.checkTickOnNeighbor), not only on/off
			var out := comparator_calc(world, p, st)
			if (out > 0) != _on(st, "powered") or out != comparator_output(world, p, st):
				schedule_tick(world, p, 2)
			return
		"piston", "sticky_piston":
			# Java checkIfExtend: a block event (run with this tick's block events: Pistons.tick)
			if piston_powered(world, p, st) != _on(st, "extended"):
				Pistons.queue_event(p)
			return
		"dispenser", "dropper":
			# Java DispenserBlock.neighborChanged: its own position or the block above (quasi-connectivity)
			var pw2 := has_neighbor_signal(world, p) or has_neighbor_signal(world, p + UP)
			var was := _on(st, "triggered")
			if pw2 and not was:
				_put(world, p, b.with_prop(st, "triggered", "true"))
				schedule_tick(world, p, 4)
			elif not pw2 and was:
				_put(world, p, b.with_prop(st, "triggered", "false"))
			return
		"crafter":
			# CrafterBlock.neighborChanged: a rising edge schedules the craft in 4 ticks; losing power clears both flags
			var pw3 := has_neighbor_signal(world, p)
			var was3 := _on(st, "triggered")
			if pw3 and not was3:
				_put(world, p, b.with_prop(st, "triggered", "true"))
				BlockEntities.get_data(world, p)["craft_at"] = int(world.game_time) + 4
				schedule_tick(world, p, 4)
			elif not pw3 and was3:
				_put(world, p, b.with_prop(b.with_prop(st, "triggered", "false"), "crafting", "false"))
			return
		"hopper":
			var en := not has_neighbor_signal(world, p)
			if _on(st, "enabled") != en:
				_put(world, p, b.with_prop(st, "enabled", "true" if en else "false"))
			return
		"powered_rail", "activator_rail":
			_update_rails(world, p, st)
			return
		"bell":
			# Java BellBlock.neighborChanged: a rising signal rings it once (toward its facing)
			var pwb := has_neighbor_signal(world, p)
			if _on(st, "powered") != pwb:
				_put(world, p, b.with_prop(st, "powered", "true" if pwb else "false"))
				if pwb:
					Bells.ring(world, p, Vector3i.ZERO)
			return
		"redstone_torch", "redstone_wall_torch":
			# wiki: Redstone_Torch - a torch changes state 2 game ticks after its input changes
			if _on(st, "lit") == _torch_input(world, p, st):
				schedule_tick(world, p, 2)
			return
	if _door_like(n):
		_door_update(world, p, st, n)
		return
	var powered := has_neighbor_signal(world, p)
	if n == "redstone_lamp":
		# wiki: Redstone_Lamp - lights instantly, turns off 4 game ticks after losing power
		var lit := _on(st, "lit")
		if powered and not lit:
			_put(world, p, b.with_prop(st, "lit", "true"))
		elif not powered and lit:
			schedule_tick(world, p, 4)
	elif n.ends_with("copper_bulb"):
		# Java CopperBulbBlock.checkAndFlip: each rising edge toggles LIT (turn on / off sound)
		if _on(st, "powered") != powered:
			var ns := b.with_prop(st, "powered", "true" if powered else "false")
			if powered:
				var lit2 := not _on(st, "lit")
				ns = b.with_prop(ns, "lit", "true" if lit2 else "false")
				Audio.play("block.copper_bulb.turn_on" if lit2 else "block.copper_bulb.turn_off", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks")
			_put(world, p, ns)
	elif Shelf.is_shelf(n):
		Shelf.on_power(world, p, st, powered)
	elif n == "tnt" and powered:
		# Java TntBlock.neighborChanged: primes (fuse 80) and is removed
		world.set_block(p.x, p.y, p.z, 0)
		MiscEntities.spawn_tnt(world.entities, Vector3(p) + Vector3(0.5, 0.0, 0.5), 80)
	elif CommandBlocks.is_command_block(n):
		CommandBlocks.on_power(world, p, powered)
	elif n == "note_block":
		if _on(st, "powered") != powered:
			_put(world, p, b.with_prop(st, "powered", "true" if powered else "false"))
			if powered:
				BlockEntities.play_note(world, p)


## Java RedstoneTorchBlock.hasNeighborSignal: the block it hangs on gives it a signal (wall torches: the wall block).
static func _torch_input(world, p: Vector3i, st: int) -> bool:
	var attached := p + DOWN
	if kind(st) == K_WALL_TORCH:
		attached = p - _dir(st)
	return signal_from(world, attached, p) > 0


## wiki: Redstone_Torch burnout - forced off 8 times within 60 game ticks it stays off (smoke, fizz at volume 0.5,
## pitch 1.8-3.4) until fewer than eight changes remain in the window; it retries 160 ticks later.
const TORCH_WINDOW := 60
const TORCH_MAX_TOGGLES := 8
const TORCH_RESTART := 160
static var _torch_offs: Dictionary = {}   # Vector3i -> Array of game times the torch was forced off
static var _torch_restart: Dictionary = {}   # Vector3i -> game time a burnt-out torch retries


static func _torch_tick(world, p: Vector3i, st: int) -> void:
	var b := Res.blocks
	var t := int(world.game_time)
	var hist: Array = _torch_offs.get(p, [])
	while not hist.is_empty() and t - int(hist[0]) > TORCH_WINDOW:
		hist.pop_front()
	var lit := _on(st, "lit")
	var inp := _torch_input(world, p, st)
	if lit and inp:
		_put(world, p, b.with_prop(st, "lit", "false"))
		hist.append(t)
		if hist.size() >= TORCH_MAX_TOGGLES:
			Audio.play("block.redstone_torch.burnout", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks", 0.5, 2.6 + (randf() - randf()) * 0.8)
			Particles.emit("smoke", Vector3(p) + Vector3(0.5, 0.7, 0.5))
			_torch_restart[p] = t + TORCH_RESTART
			schedule_tick(world, p, TORCH_RESTART)
		on_changed(world, p)
	elif not lit and not inp:
		if hist.size() < TORCH_MAX_TOGGLES:
			_torch_restart.erase(p)
			_put(world, p, b.with_prop(st, "lit", "true"))
			on_changed(world, p)
		elif _torch_restart.has(p):
			schedule_tick(world, p, maxi(1, int(_torch_restart[p]) - t))   # (an earlier update replaced the retry)
	if hist.is_empty():
		_torch_offs.erase(p)
	else:
		_torch_offs[p] = hist


## A component's own scheduled tick (Java scheduleTick: an already scheduled one stays). BlockUpdates also ticks blocks
## for support checks after neighbour changes; those must not run the component early (a repeater would skip its
## delay), so the component's own due tick is remembered here.
static var _due: Dictionary = {}   # Vector3i -> game tick of the component's own scheduled tick


static func _tick_now(world) -> int:
	return BlockUpdates._exec_tick if BlockUpdates._exec_tick >= 0 else int(world.game_time)


static func schedule_tick(world, p: Vector3i, delay: int) -> void:
	var due := _tick_now(world) + maxi(1, delay)
	var cur = _due.get(p)
	if cur == null or int(cur) < _tick_now(world) or due < int(cur):
		_due[p] = due
	BlockUpdates.schedule(world, p, delay)


## True (and the own tick re-queued) when a tick arrives before the component's own one.
static func _early(world, p: Vector3i) -> bool:
	var cur = _due.get(p)
	if cur == null:
		return false
	var now := _tick_now(world)
	if now < int(cur):
		BlockUpdates.schedule(world, p, int(cur) - now)
		return true
	_due.erase(p)
	return false


## Only the support check of a neighbour-change tick (the block pops off without its support).
static func _support_only(world, p: Vector3i, st: int) -> void:
	if Support.kind_of(st) != Support.K_NONE:
		if Support.tick(world, p, st):   # (support.gd: Java canSurvive -> destroyBlock)
			BlockUpdates.schedule_neighbors(world, p)
		return
	if BlockUpdates._has_support(world, p, st):
		return
	world.set_block(p.x, p.y, p.z, 0)
	if world.gamerule("doTileDrops", true):
		for s in Loot.block_drops(st, null, world, p):
			world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.3, 0.5), s)
	BlockUpdates.schedule_neighbors(world, p)
	on_changed(world, p)


## Scheduled tick for redstone components (called from BlockUpdates._scheduled). Returns true if handled.
static func scheduled(world, p: Vector3i, st: int) -> bool:
	var b := Res.blocks
	var n := b.name_of(st)
	if _early(world, p):
		_support_only(world, p, st)
		return true
	if kind(st) == K_ATTACHED and n.ends_with("_button"):
		# Java ButtonBlock.tick: released after its press time (wiki: stone 20, wooden 30 game ticks)
		if _on(st, "powered"):
			_put(world, p, b.with_prop(st, "powered", "false"))
			on_changed(world, p)
			Audio.play("block.%s_button.click_off" % Sensors.set_type(n), Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks")
			return true
		return false
	match n:
		"repeater":
			# Java DiodeBlock.tick: off when the input is gone; on otherwise, and a pulse shorter than the delay is
			# extended (the repeater schedules its own turn-off one delay later)
			if _repeater_locked(world, p, st):
				return true
			var on := _on(st, "powered")
			var want := _diode_input(world, p, st) > 0
			if on and not want:
				_put(world, p, b.with_prop(st, "powered", "false"))
				_after_output(world, p, st)
			elif not on:
				_put(world, p, b.with_prop(st, "powered", "true"))
				if not want:
					schedule_tick(world, p, int(b.get_prop(st, "delay")) * 2)
				_after_output(world, p, st)
			return true
		"comparator":
			# Java ComparatorBlock.refreshOutputState
			var old := comparator_output(world, p, st)
			var cv := comparator_calc(world, p, st)
			_cmp_out[p] = cv
			var want2 := cv > 0
			if want2 != _on(st, "powered"):
				_put(world, p, b.with_prop(st, "powered", "true" if want2 else "false"))
			if old != cv or want2 != _on(st, "powered"):
				_after_output(world, p, st)
			return true
		"redstone_lamp":
			if _on(st, "lit") and not has_neighbor_signal(world, p):
				_put(world, p, b.with_prop(st, "lit", "false"))
			return true
		"redstone_torch", "redstone_wall_torch":
			_torch_tick(world, p, st)
			return false   # BlockUpdates still runs its support check (torch on a removed block pops off)
		"observer":
			var pw := _on(st, "powered")
			_put(world, p, b.with_prop(st, "powered", "false" if pw else "true"))
			if not pw:
				schedule_tick(world, p, 2)
			_after_output(world, p, st)
			return true
		"piston", "sticky_piston":
			Pistons.queue_event(p)   # (older saves: a pending piston tick becomes its block event)
			return true
		"moving_piston":
			return Pistons.scheduled(world, p)
		"dispenser", "dropper":
			_dispense(world, p, st, n == "dropper")
			return true
		"crafter":
			var cd := BlockEntities.get_data(world, p)
			if _on(st, "crafting") and int(world.game_time) >= int(cd.get("crafting_until", 0)):
				_put(world, p, b.with_prop(st, "crafting", "false"))   # CrafterBlockEntity tick: the crafting look ends
				st = world.state_at(p.x, p.y, p.z)
			if cd.has("craft_at") and int(world.game_time) >= int(cd["craft_at"]):
				cd.erase("craft_at")
				Crafter.craft(world, p, st)
			return true
		"tripwire", "tripwire_hook":
			Tripwires.scheduled(world, p, st)
			return true
		"detector_rail":
			Sensors.detector_check(world, p, st)
			return false   # BlockUpdates still runs the rail's support check
		"lectern":
			if _on(st, "powered"):
				_put(world, p, b.with_prop(st, "powered", "false"))
				on_changed(world, p)
			return true
	return false


## wiki Lectern: turning a page sends a 2-game-tick full-strength pulse (Java LecternBlock.signalPageChange) and plays
## item.book.page_turn (Blocks, volume 2.0, pitch 0.9-1.0).
static func lectern_pulse(world, p: Vector3i) -> void:
	var st := _state(world, p)
	if st <= 0 or _name(st) != "lectern":
		return
	if Res.blocks.get_prop(st, "powered") != "true":
		_put(world, p, Res.blocks.with_prop(st, "powered", "true"))
		on_changed(world, p)
	schedule_tick(world, p, 2)
	Audio.play("item.book.page_turn", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks", 2.0, 0.9 + randf() * 0.1)


# ------------------------------------------------------------------ powered / activator rails

## wiki Powered Rail / Activator Rail: a rail receiving a signal powers the connected rails of its own kind up to eight
## away along the track (one source: up to 17 rails); a gap, a turn onto another axis or another rail kind ends it.
## Slopes link to the rail one block up / down. Applied instantly over the whole affected stretch.
const RAIL_REACH := 8
static var _rail_done: Dictionary = {}   # rails settled during the current top-level update


static func _rail_exits(st: int) -> Array:
	return Vehicles.EXITS.get(Res.blocks.get_prop(st, "shape"), [])


## The rail of the same kind that the track at c (state cst) continues into through exit e, or NONE.
static func _rail_link(world, c: Vector3i, cst: int, e: Vector3i) -> Vector3i:
	var b := Res.blocks
	var h := Vector3i(e.x, 0, e.z)
	var tries: Array = [c + h + Vector3i(0, 1, 0)] if e.y == 1 else [c + h, c + h + Vector3i(0, -1, 0)]
	for q in tries:
		var qs := _state(world, q)
		if qs <= 0 or b.st_block[qs] != b.st_block[cst]:
			continue
		for qe in _rail_exits(qs):
			if qe.x == -h.x and qe.z == -h.z:
				return q
	return NONE


static func _update_rails(world, p: Vector3i, st: int) -> void:
	if _rail_done.has(p):
		return
	var b := Res.blocks
	var ex := _rail_exits(st)
	if ex.size() < 2:
		return
	var sides: Array = [[], []]
	var seen := {p: true}
	for s in 2:
		var lst: Array = sides[s]
		var c := p
		var cst := st
		var e: Vector3i = ex[s]
		for i in RAIL_REACH * 2:
			var q := _rail_link(world, c, cst, e)
			if q == NONE or seen.has(q):
				break
			seen[q] = true
			var qs := _state(world, q)
			lst.append([q, qs])
			var nxt := Vector3i.ZERO
			for qe in _rail_exits(qs):
				if not (qe.x == -e.x and qe.z == -e.z):
					nxt = qe
			if nxt == Vector3i.ZERO:
				break
			c = q
			cst = qs
			e = nxt
	var chain: Array = (sides[0] as Array).duplicate()
	chain.reverse()
	var at := chain.size()
	chain.append([p, st])
	chain.append_array(sides[1])
	var n := chain.size()
	var direct := PackedByteArray()
	direct.resize(n)
	for i in n:
		direct[i] = 1 if has_neighbor_signal(world, chain[i][0]) else 0
	for i in range(maxi(0, at - RAIL_REACH), mini(n, at + RAIL_REACH + 1)):
		var on := false
		for j in range(maxi(0, i - RAIL_REACH), mini(n, i + RAIL_REACH + 1)):
			if direct[j] != 0:
				on = true
				break
		var q2: Vector3i = chain[i][0]
		var qs2: int = chain[i][1]
		_rail_done[q2] = true
		if (b.get_prop(qs2, "powered") == "true") != on:
			_put(world, q2, b.with_prop(qs2, "powered", "true" if on else "false"))


## Java DiodeBlock / ObserverBlock.updateNeighborsInFront: the output block and its neighbours.
static func _after_output(world, p: Vector3i, st: int) -> void:
	on_changed(world, p - _dir(st))


# ------------------------------------------------------------------ pistons (structure; motion: Pistons)

## wiki Piston (Java): pumpkins / melons, cactus, cake, chorus, bamboo, leaves, dragon eggs, cocoa, sea pickles, candles,
## flower pots, eggs, dripstone, amethyst buds, dripleaves, lily pads, suspicious sand / gravel, carpets (not moss),
## repeaters / comparators, ladders, snow, azaleas and mob heads break when pushed (Java PushReaction.DESTROY).
const BREAK_PUSHED := ["pumpkin", "carved_pumpkin", "jack_o_lantern", "melon", "cactus", "cake", "chorus_flower", "chorus_plant", "bamboo",
	"dragon_egg", "cocoa", "sea_pickle", "flower_pot", "turtle_egg", "sniffer_egg", "pointed_dripstone", "amethyst_cluster", "large_amethyst_bud",
	"medium_amethyst_bud", "small_amethyst_bud", "big_dripleaf", "big_dripleaf_stem", "small_dripleaf", "lily_pad", "frogspawn",
	"suspicious_sand", "suspicious_gravel", "decorated_pot", "scaffolding", "repeater", "comparator", "ladder", "snow", "azalea",
	"flowering_azalea"]


static func _movable(st: int) -> int:
	# 0 = blocks the piston, 1 = movable, 2 = destroyed when pushed
	if st <= 0:
		return 1
	var b := Res.blocks
	var n := b.name_of(st)
	# wiki: Piston (Java "cannot be pushed" lists)
	if n in ["obsidian", "crying_obsidian", "bedrock", "end_portal_frame", "end_portal", "nether_portal", "barrier", "end_gateway", "respawn_anchor", "reinforced_deepslate", "piston_head", "moving_piston", "enchanting_table", "ender_chest", "spawner", "beacon", "jukebox", "lodestone",
			"calibrated_sculk_sensor", "sculk_sensor", "sculk_catalyst", "sculk_shrieker", "creaking_heart", "grindstone", "jigsaw", "light", "structure_block", "trial_spawner", "vault", "potent_sulfur", "test_block", "test_instance_block"] or CommandBlocks.is_command_block(n):
		return 0
	if (n == "piston" or n == "sticky_piston") and b.get_prop(st, "extended") == "true":
		return 0
	if n.ends_with("shulker_box"):
		return 2   # wiki: Shulker_Box - breaks and drops as an item when pushed
	if n.ends_with("chest") or Shelf.is_shelf(n) or n in ["furnace", "blast_furnace", "smoker", "barrel", "hopper", "dispenser", "dropper", "lectern", "beehive", "bee_nest", "brewing_stand", "chiseled_bookshelf", "conduit", "crafter", "daylight_detector"]:
		return 0   # block entities are immovable
	# wiki: Piston - bells, campfires and lanterns break when pushed; two-block doors / beds break instead of tearing
	if n == "bell" or n.ends_with("campfire") or (n.ends_with("lantern") and n != "sea_lantern" and n != "jack_o_lantern") or n.ends_with("_door") or n.ends_with("_bed"):
		return 2
	if n in BREAK_PUSHED or n.ends_with("_leaves") or n.ends_with("candle") or n.ends_with("candle_cake") or n.begins_with("potted_") or (n.ends_with("_carpet") and not n.ends_with("moss_carpet")) \
			or n.ends_with("_skull") or (n.ends_with("_head") and n != "piston_head"):
		return 2
	if (b.st_flags[st] & (BlockRegistry.F_REPLACEABLE | BlockRegistry.F_LIQUID)) != 0 or (b.st_flags[st] & BlockRegistry.F_COLLIDE) == 0:
		return 2
	if b.hardness[b.st_block[st]] < 0:
		return 0
	return 1


## Slime 1 / honey 2 / other 0 (wiki Slime Block / Honey Block: they pull the blocks they touch along).
static func _sticky(st: int) -> int:
	if st <= 0:
		return 0
	var n := Res.blocks.name_of(st)
	return 1 if n == "slime_block" else (2 if n == "honey_block" else 0)


## wiki Slime Block: slime and honey never stick to each other; glazed terracotta is never pulled (push only).
static func _sticks(a: int, c: int) -> bool:
	var sa := _sticky(a)
	var sc := _sticky(c)
	if sa == 0 and sc == 0:
		return false
	if sa != 0 and sc != 0 and sa != sc:
		return false
	return not _push_only(a) and not _push_only(c)


static func _push_only(st: int) -> bool:
	return st > 0 and Res.blocks.name_of(st).ends_with("glazed_terracotta")


## Blocks a piston at `piston` moves when the block at `start` travels along `dir` (Java PistonStructureResolver as the
## wiki describes it: the pushed line, blocks stuck to slime / honey in it (incl. the blocks behind a sticky block) and
## their own lines; at most 12 blocks; an immovable block in a moving line or the piston itself stops everything;
## immovable or breakable blocks merely touching a sticky block stay behind; breakable blocks in a pushed line break).
## Returns {"move": [Vector3i], "destroy": [Vector3i]} or {} when the piston cannot move them.
static func _resolve(world, piston: Vector3i, start: Vector3i, dir: Vector3i, pushing: bool) -> Dictionary:
	var res := {"move": [], "destroy": []}
	var st0 := _state(world, start)
	if st0 < 0:
		return {}
	if st0 == 0:
		return res
	var m0 := _movable(st0)
	if not pushing and (m0 != 1 or _push_only(st0)):
		return res   # (nothing a sticky piston can pull)
	if m0 == 0:
		return {}
	if m0 == 2:
		(res["destroy"] as Array).append(start)
		return res
	var moving := {}
	if not _add_line(world, piston, start, dir, res, moving):
		return {}
	var mv: Array = res["move"]
	var i := 0
	while i < mv.size():
		var q: Vector3i = mv[i]
		var qs := _state(world, q)
		if _sticky(qs) != 0:
			for d in DIRS:
				if d == dir or d == -dir:
					continue
				var nb: Vector3i = q + d
				if moving.has(nb) or nb == piston:
					continue
				var ns := _state(world, nb)
				if ns <= 0 or not _sticks(qs, ns) or _movable(ns) != 1:
					continue
				if not _add_line(world, piston, nb, dir, res, moving):
					return {}
		i += 1
	return res


## Adds the block at `origin` (plus the sticky chain behind it and the line it pushes ahead) to res.move.
static func _add_line(world, piston: Vector3i, origin: Vector3i, dir: Vector3i, res: Dictionary, moving: Dictionary) -> bool:
	if moving.has(origin):
		return true
	var mv: Array = res["move"]
	var cur := _state(world, origin)
	# blocks behind a sticky block that stick to it come along
	var back: Array = []
	var q := origin
	while _sticky(cur) != 0:
		var bq := q - dir
		var bs := _state(world, bq)
		if bs <= 0 or bq == piston or moving.has(bq) or not _sticks(cur, bs) or _movable(bs) != 1:
			break
		back.append(bq)
		if mv.size() + back.size() + 1 > PUSH_LIMIT:
			return false
		q = bq
		cur = bs
	for k in range(back.size() - 1, -1, -1):
		moving[back[k]] = true
		mv.append(back[k])
	moving[origin] = true
	mv.append(origin)
	if mv.size() > PUSH_LIMIT:
		return false
	# the line ahead is pushed
	var f := origin + dir
	while true:
		if moving.has(f):
			return true
		var fs := _state(world, f)
		if fs < 0 or f == piston:
			return false
		if fs == 0:
			return true
		var fm := _movable(fs)
		if fm == 0:
			return false
		if fm == 2:
			if not (res["destroy"] as Array).has(f):
				(res["destroy"] as Array).append(f)
			return true
		moving[f] = true
		mv.append(f)
		if mv.size() > PUSH_LIMIT:
			return false
		f += dir
	return true


## Extension / retraction now (the block event): Pistons runs the 2-tick motion.
static func _extend(world, p: Vector3i, st: int) -> bool:
	return Pistons.extend(world, p, st)


static func _retract(world, p: Vector3i, st: int, _sticky_flag: bool = true) -> void:
	Pistons.retract(world, p, st)


# ------------------------------------------------------------------ dispensers

static func _dispense(world, p: Vector3i, st: int, dropper: bool) -> void:
	var d := BlockEntities.ensure_loot(world, p)
	if d.is_empty():
		return
	var items: Array = d.get("items", [])
	var slots: Array = []
	for i in items.size():
		if not ItemStack.from_dict(items[i]).is_empty():
			slots.append(i)
	if slots.is_empty():
		Audio.play("block.dispenser.fail", Vector3(p), "Blocks", 1.0, 1.2)   # wiki: Dispenser sounds (volume 1, pitch 1.2)
		return
	var k: int = slots[world.rng.randi_range(0, slots.size() - 1)]
	var s := ItemStack.from_dict(items[k])
	var f := _dir(st)
	var front := p + f
	var out := Vector3(p) + Vector3(0.5, 0.5, 0.5) + Vector3(f) * 0.7
	var nm := s.name()
	var used := true
	var launched := false
	# Java DispenseItemBehavior (buckets): an empty bucket picks up the source / waterlogged water in front
	# (BucketPickup.pickupBlock; consumeWithRemainder: the filled bucket replaces it or goes into a free slot, else out)
	var filled := Interaction.bucket_pickup(world, front, false) if not dropper and nm == "bucket" else ""
	if not dropper and nm in ["arrow", "snowball", "egg", "fire_charge"]:
		world.entities.spawn_projectile("small_fireball" if nm == "fire_charge" else nm, out, Vector3(f) * 1.1 + Vector3(0, 0.1, 0), null)
		launched = true
	elif not dropper and (nm == "water_bucket" or nm == "lava_bucket" or MobBuckets.is_bucket(nm)) and Interaction.bucket_empty(world, front, nm != "lava_bucket", Interaction.NO_POS, MobBuckets.empty_sound(nm)):
		# DispensibleContainerItem.emptyContents at the block in front: air, a block the fluid replaces, or (water) a
		# waterloggable block, which it waterlogs; a bucket that can't empty there is dropped like any item
		MobBuckets.release(world, s, Interaction.last_empty)   # (a mob bucket releases its mob: wiki Bucket of Aquatic Mob)
		items[k] = ItemStack.named("bucket", 1).to_dict()
		used = false
	elif filled != "":
		s.count -= 1
		items[k] = s.to_dict() if s.count > 0 else ItemStack.named(filled, 1).to_dict()
		if s.count > 0:
			var put := false
			for i2 in items.size():
				if ItemStack.from_dict(items[i2]).is_empty():
					items[i2] = ItemStack.named(filled, 1).to_dict()
					put = true
					break
			if not put and items.size() < 9:
				items.append(ItemStack.named(filled, 1).to_dict())
			elif not put:
				world.entities.spawn_item(out, ItemStack.named(filled, 1), true)
		used = false
	elif not dropper and nm == "flint_and_steel" and _state(world, front) == 0:
		world.set_block(front.x, front.y, front.z, Res.blocks.default_state("fire"))
		used = false
	elif not dropper and nm == "bone_meal":
		BlockUpdates.bonemeal(world, front, _state(world, front))
	else:
		var one := s.copy()
		one.count = 1
		world.entities.spawn_item(out, one, true)
	if used:
		s.count -= 1
		items[k] = s.to_dict() if s.count > 0 else {}
	d["items"] = items
	BlockEntities.set_data(world, p, d)
	if launched:
		Audio.play("block.dispenser.launch", Vector3(p), "Blocks", 1.0, 1.2)   # wiki: Dispenser - projectile launch (1, 1.2)
	else:
		Audio.play("block.dispenser.dispense", Vector3(p), "Blocks")
