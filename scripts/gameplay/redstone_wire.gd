## RedstoneWire — redstone dust shape and signal rules (Java RedStoneWireBlock; wiki Redstone Dust):
## - Connections: each horizontal side is UP when dust one block higher can be reached (the block beside it holds the
##   dust and nothing conductive sits above this dust; UP only when that block's face toward this dust is sturdy, else
##   SIDE), SIDE when the block beside connects (dust, a signal source, a repeater along its axis, an observer's back)
##   or, through a non-conductive block, dust one block lower; else NONE. A side axis with no connection at all is
##   drawn through (an isolated dust is a cross "+", one connection makes a straight line), except a dot stays a dot.
##   Right-click toggles an isolated cross <-> dot (Java Edition).
## - Power: max(signal from the non-dust neighbours, adjacent dust - 1): dust beside it, dust one higher when this one
##   has no conductive block above it and the block beside is conductive, dust one lower when the block beside is not
##   conductive (non-conductive blocks pass power up, never down).
## - Output: the block below it and the blocks it points into get its power (weak power: a powered block does not
##   power other dust).
## - Colour per power level: wiki Block colors "Redstone tints" (Java Edition column).
class_name RedstoneWire

const HDIRS := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0)}
const SIDES := ["north", "east", "south", "west"]
const OPP := {"north": "south", "south": "north", "east": "west", "west": "east"}
const UP := Vector3i(0, 1, 0)

## wiki Block colors, Redstone tints (JE): power 0..15.
const COLORS := [0x4C0000, 0x700000, 0x7A0000, 0x840000, 0x8E0000, 0x990000, 0xA30000, 0xAD0000, 0xB70000, 0xC10000,
	0xCC0000, 0xD60000, 0xE00000, 0xEA0600, 0xF41B00, 0xFF3200]

## Signal sources dust points at from any side (Java isSignalSource; repeaters / observers have their own rules).
const SOURCES := ["redstone_block", "redstone_torch", "redstone_wall_torch", "lever", "tripwire_hook", "detector_rail",
	"daylight_detector", "target", "trapped_chest", "lectern", "sculk_sensor", "calibrated_sculk_sensor", "comparator",
	"jukebox"]

static var _wire_id := -2
static var _kind := PackedByteArray()   # per state: 0 none, 1 dust, 2 source (any side), 3 repeater, 4 observer


static func wire_id() -> int:
	if _wire_id == -2:
		_wire_id = Res.blocks.block_id("redstone_wire")
	return _wire_id


static func is_wire(st: int) -> bool:
	return st > 0 and Res.blocks.st_block[st] == wire_id()


static func _kinds() -> PackedByteArray:
	var b := Res.blocks
	if _kind.size() != b.total_states:
		var per := PackedByteArray()
		per.resize(b.names.size())
		for i in b.names.size():
			var n: String = b.names[i]
			if n == "redstone_wire":
				per[i] = 1
			elif n == "repeater":
				per[i] = 3
			elif n == "observer":
				per[i] = 4
			elif n in SOURCES or n.ends_with("_button") or n.ends_with("_pressure_plate") or n.ends_with("lightning_rod"):
				per[i] = 2
		var t := PackedByteArray()
		t.resize(b.total_states)
		for s in range(1, b.total_states):
			t[s] = per[b.st_block[s]]
		_kind = t
	return _kind


## Java isRedstoneConductor (Redstone.conductor: full-collision blocks minus the wiki Conductivity exceptions).
static func conductor(st: int) -> bool:
	return Redstone.conductor(st)


## Java RedStoneWireBlock.shouldConnectTo(state, direction): direction = from the dust toward that block.
static func connects_to(st: int, dir: Vector3i) -> bool:
	if st <= 0:
		return false
	var k := _kinds()[st]
	if k == 1 or k == 2:
		return true
	if k == 3:
		var f: Vector3i = Redstone._dir(st)
		return f == dir or f == -dir
	if k == 4:
		return Redstone._dir(st) == dir
	return false


## Whether dust can rest on this block (wiki Redstone Dust: a sturdy top face - glowstone, glass, upside-down slabs /
## stairs - or a hopper; Java canSurviveOn: isFaceSturdy(UP) or hopper). Leaves give no support (Support's face table).
static func can_survive_on(st: int) -> bool:
	if st <= 0:
		return false
	var b := Res.blocks
	if b.names[b.st_block[st]] == "hopper":
		return true
	return face_sturdy(st, UP)


## Java isFaceSturdy (FULL) of the block's support shape: Support's per-state face table (support.gd), so dust, its
## UP connections and every other support rule agree (leaves: none).
static func face_sturdy(st: int, face: Vector3i) -> bool:
	return Support.sturdy(st, Support.face_of(face), Support.T_FULL)


## Java getConnectingSide: "up", "side" or "none" for one horizontal side of the dust at p.
static func side_of(world, p: Vector3i, side: String, can_up: bool) -> String:
	var d: Vector3i = HDIRS[side]
	var q := p + d
	var qs: int = world.state_at(q.x, q.y, q.z)
	if can_up:
		var bn := Res.blocks.name_of(qs) if qs > 0 else ""
		if (bn.ends_with("_trapdoor") or can_survive_on(qs)) and is_wire(world.state_at(q.x, q.y + 1, q.z)):
			return "up" if face_sturdy(qs, -d) else "side"
	if connects_to(qs, d):
		return "side"
	if not conductor(qs) and is_wire(world.state_at(q.x, q.y - 1, q.z)):
		return "side"
	return "none"


static func _sides(st: int) -> Dictionary:
	var b := Res.blocks
	var out := {}
	for s in SIDES:
		out[s] = b.get_prop(st, s)
	return out


static func is_dot(st: int) -> bool:
	var b := Res.blocks
	for s in SIDES:
		if b.get_prop(st, s) != "none":
			return false
	return true


static func is_cross(st: int) -> bool:
	var b := Res.blocks
	for s in SIDES:
		if b.get_prop(st, s) != "side":
			return false
	return true


## Java getConnectionState: the shape for the dust at p, starting from `st` (a dot stays a dot while nothing
## connects; an axis without connections is drawn through).
static func connection_state(world, p: Vector3i, st: int) -> int:
	var b := Res.blocks
	var was_dot := is_dot(st)
	var can_up := not conductor(world.state_at(p.x, p.y + 1, p.z))
	var sd := {}
	for s in SIDES:
		sd[s] = side_of(world, p, s, can_up)
	var n_on: bool = sd["north"] != "none"
	var s_on: bool = sd["south"] != "none"
	var e_on: bool = sd["east"] != "none"
	var w_on: bool = sd["west"] != "none"
	if not (was_dot and not n_on and not s_on and not e_on and not w_on):
		var no_ns := not n_on and not s_on
		var no_ew := not e_on and not w_on
		if not w_on and no_ns:
			sd["west"] = "side"
		if not e_on and no_ns:
			sd["east"] = "side"
		if not n_on and no_ew:
			sd["north"] = "side"
		if not s_on and no_ew:
			sd["south"] = "side"
	var ns := st
	for s in SIDES:
		ns = b.with_prop(ns, s, sd[s])
	return ns


## Positions whose dust shape may depend on a block change at p: p, its 4 sides, and dust one above / below those
## sides (Java updateShape + updateIndirectNeighbourShapes), plus the dust above p (its up connections).
static func update_around(world, p: Vector3i, placed: bool) -> void:
	_fix(world, p, placed)
	_fix(world, p + UP, false)
	_fix(world, p - UP, false)
	for s in SIDES:
		var q: Vector3i = p + HDIRS[s]
		_fix(world, q, false)
		_fix(world, q + UP, false)
		_fix(world, q - UP, false)


static func _fix(world, q: Vector3i, placed: bool) -> void:
	var st: int = world.state_at(q.x, q.y, q.z)
	if not is_wire(st):
		return
	# a newly placed dust starts as a cross (Java getStateForPlacement uses crossState), so it never starts as a dot
	var base := st
	if placed:
		for s in SIDES:
			base = Res.blocks.with_prop(base, s, "side")
	var ns := connection_state(world, q, base)
	if ns != st:
		world.set_block(q.x, q.y, q.z, ns, false)


## Right-click (Java useWithoutItem): an isolated cross becomes a dot and back.
static func toggle(world, p: Vector3i, st: int) -> bool:
	if not is_cross(st) and not is_dot(st):
		return false
	var b := Res.blocks
	var ns := st
	for s in SIDES:
		ns = b.with_prop(ns, s, "none" if is_cross(st) else "side")
	ns = connection_state(world, p, ns)
	if ns == st:
		return false
	world.set_block(p.x, p.y, p.z, ns, false)
	Redstone.on_changed(world, p)
	return true


## Java getSignal of the dust at src toward the block at dst (adjacent): the block below gets its power, a block
## beside it only when the dust points that way, nothing upward.
static func signal_to(world, src: Vector3i, st: int, dst: Vector3i) -> int:
	var pw := int(Res.blocks.get_prop(st, "power"))
	if pw <= 0:
		return 0
	var d := dst - src
	if d.y < 0:
		return pw
	if d.y > 0:
		return 0
	for s in SIDES:
		if HDIRS[s] == d:
			return pw if Res.blocks.get_prop(st, s) != "none" else 0
	return 0


## Dust neighbours of c that receive power from c (directed: up only past a non-conductive block above c, down only
## from a conductive block under c through a non-conductive block beside c).
static func power_targets(world, c: Vector3i) -> Array:
	var out: Array = []
	var above_free := not conductor(world.state_at(c.x, c.y + 1, c.z))
	var below_cond := conductor(world.state_at(c.x, c.y - 1, c.z))
	for s in SIDES:
		var q: Vector3i = c + HDIRS[s]
		if is_wire(world.state_at(q.x, q.y, q.z)):
			out.append(q)
		if above_free and is_wire(world.state_at(q.x, q.y + 1, q.z)):
			out.append(q + UP)
		if below_cond and not conductor(world.state_at(q.x, q.y, q.z)) and is_wire(world.state_at(q.x, q.y - 1, q.z)):
			out.append(q - UP)
	return out
