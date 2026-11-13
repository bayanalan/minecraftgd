## ShapeUpdates — Java Block.updateShape / getStateForPlacement for blocks whose state follows their neighbours:
## fences / walls / glass panes / bars connect (FenceBlock, WallBlock, IronBarsBlock connectsTo), walls raise their post
## and switch sides between low / tall by what sits above (WallBlock.makeWallState / shouldRaisePost), fence gates
## sink into walls (in_wall), stairs form inner / outer corners (StairBlock.getStairsShape), and dirt paths / farmland
## turn to dirt under a solid block (DirtPathBlock / FarmBlock canSurvive, BlockState.isSolid).
## WorldManager.set_block calls on_changed for gameplay edits (not world generation, whose states come complete).
class_name ShapeUpdates

const K_NONE := 0
const K_FENCE := 1
const K_WALL := 2
const K_PANE := 3
const K_STAIRS := 4
const K_GATE := 5
const K_SOIL := 6       # dirt_path, farmland
const K_EXCEPT := 7     # Java Block.isExceptionForConnection: never connects by a sturdy side

const SIDES := ["north", "south", "west", "east"]
const SIDE_OFF := [Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
const OPP := {"north": "south", "south": "north", "west": "east", "east": "west"}
const CW := {"north": "east", "east": "south", "south": "west", "west": "north"}
const CCW := {"north": "west", "west": "south", "south": "east", "east": "north"}
# Java WallBlock test shapes (x0, z0, x1, z1 in 16ths): post and the four sides
const POST_TEST := Rect2(7, 7, 2, 2)
const SIDE_TEST := {"north": Rect2(7, 0, 2, 9), "south": Rect2(7, 7, 2, 9), "west": Rect2(0, 7, 9, 2), "east": Rect2(7, 7, 9, 2)}

static var _kind := PackedByteArray()
static var _wooden := PackedByteArray()


static func _k(bid: int) -> int:
	var b := Res.blocks
	if _kind.size() != b.names.size():
		_kind = PackedByteArray()
		_kind.resize(b.names.size())
		_kind.fill(255)
		_wooden = PackedByteArray()
		_wooden.resize(b.names.size())
	var k := _kind[bid]
	if k != 255:
		return k
	var n: String = b.names[bid]
	var vanilla := Res.mode == "vanilla"
	k = K_NONE
	if n.ends_with("_fence_gate"):
		k = K_GATE
	elif n.ends_with("_fence"):
		k = K_FENCE
		_wooden[bid] = 1 if (Tags.has_block("wooden_fences", n) if vanilla else n != "nether_brick_fence") else 0
	elif (vanilla and Tags.has_block("walls", n)) or (not vanilla and n.ends_with("_wall") and not n.contains("_wall_")):
		k = K_WALL
	elif n.ends_with("glass_pane") or n.ends_with("_bars") or n == "iron_bars":
		k = K_PANE
	elif n.ends_with("_stairs"):
		k = K_STAIRS
	elif n == "dirt_path" or n == "farmland":
		k = K_SOIL
	elif n in ["barrier", "carved_pumpkin", "jack_o_lantern", "melon", "pumpkin"] or n.ends_with("shulker_box") or (vanilla and Tags.has_block("leaves", n)) or n.ends_with("_leaves"):
		k = K_EXCEPT
	_kind[bid] = k
	return k


## Fills the per-block kind table up front (main thread): worldgen workers read it in Features._post_process.
static func prime() -> void:
	for bid in Res.blocks.names.size():
		_k(bid)


static func kind_of(st: int) -> int:
	return K_NONE if st <= 0 else _k(Res.blocks.st_block[st])


## Java BlockState.isFaceSturdy for a full side: a full-cube collision shape.
static func _sturdy(st: int) -> bool:
	return st > 0 and (Res.blocks.st_flags[st] & BlockRegistry.F_FULL_SHAPE) != 0


## Java BlockState.isSolid (legacy solid): the collision bounds' average size >= 0.7291666 or height >= 1.
static func is_solid(st: int) -> bool:
	if st <= 0 or (Res.blocks.st_flags[st] & BlockRegistry.F_COLLIDE) == 0:
		return false
	var sh := Res.blocks.get_shape(st)
	if sh.is_empty():
		return false
	var mn := Vector3(sh[0], sh[1], sh[2])
	var mx := Vector3(sh[3], sh[4], sh[5])
	for i in range(6, sh.size(), 6):
		mn = mn.min(Vector3(sh[i], sh[i + 1], sh[i + 2]))
		mx = mx.max(Vector3(sh[i + 3], sh[i + 4], sh[i + 5]))
	var d := mx - mn
	return (d.x + d.y + d.z) / 3.0 >= 0.7291666 or d.y >= 1.0


## Java FenceGateBlock.connectsToDirection: the gate's facing axis is perpendicular to the side.
static func _gate_connects(st: int, side: String) -> bool:
	var f := Res.blocks.get_prop(st, "facing")
	return (f in ["north", "south"]) != (side in ["north", "south"])


static func _connects(kind: int, self_bid: int, nst: int, side: String) -> bool:
	if nst <= 0:
		return false
	var nk := kind_of(nst)
	var sturdy := nk != K_EXCEPT and _sturdy(nst)
	match kind:
		K_FENCE:
			var nb := Res.blocks.st_block[nst]
			return sturdy or (nk == K_FENCE and _wooden[nb] == _wooden[self_bid]) or (nk == K_GATE and _gate_connects(nst, side))
		K_WALL:
			return nk == K_WALL or sturdy or nk == K_PANE or (nk == K_GATE and _gate_connects(nst, side))
		K_PANE:
			return sturdy or nk == K_PANE or nk == K_WALL
	return false


## The block above covers a test rectangle on its bottom face (Java isCovered(aboveShape.getFaceShape(DOWN), test)).
static func _covers(above: int, r: Rect2, side: String) -> bool:
	if above <= 0 or (Res.blocks.st_flags[above] & BlockRegistry.F_COLLIDE) == 0:
		return false
	if kind_of(above) == K_WALL:
		if side == "":
			return Res.blocks.get_prop(above, "up") == "true"
		return Res.blocks.get_prop(above, side) != "none"
	var sh := Res.blocks.get_shape(above)
	for i in range(0, sh.size(), 6):
		if sh[i + 1] > 0.0001:
			continue
		if sh[i] * 16.0 <= r.position.x + 0.01 and sh[i + 2] * 16.0 <= r.position.y + 0.01 and sh[i + 3] * 16.0 >= r.end.x - 0.01 and sh[i + 5] * 16.0 >= r.end.y - 0.01:
			return true
	return false


## The state a connecting block / stairs / gate should have at p (unchanged for other blocks).
static func computed(world, p: Vector3i, st: int) -> int:
	var k := kind_of(st)
	var b := Res.blocks
	match k:
		K_FENCE, K_PANE:
			var bid := b.st_block[st]
			for i in 4:
				var q: Vector3i = p + SIDE_OFF[i]
				var c := _connects(k, bid, world.state_at(q.x, q.y, q.z), OPP[SIDES[i]])
				if b.has_prop(st, SIDES[i]):
					st = b.with_prop(st, SIDES[i], "true" if c else "false")
		K_WALL:
			var bid2 := b.st_block[st]
			var above: int = world.state_at(p.x, p.y + 1, p.z)
			var vals := {}
			for i in 4:
				var q2: Vector3i = p + SIDE_OFF[i]
				var c2 := _connects(k, bid2, world.state_at(q2.x, q2.y, q2.z), OPP[SIDES[i]])
				vals[SIDES[i]] = "none" if not c2 else ("tall" if _covers(above, SIDE_TEST[SIDES[i]], SIDES[i]) else "low")
				st = b.with_prop(st, SIDES[i], vals[SIDES[i]])
			# Java WallBlock.shouldRaisePost
			var up := false
			if kind_of(above) == K_WALL and b.get_prop(above, "up") == "true":
				up = true
			else:
				var nn: bool = vals["north"] == "none"
				var sn: bool = vals["south"] == "none"
				var wn: bool = vals["west"] == "none"
				var en: bool = vals["east"] == "none"
				if (nn and sn and wn and en) or nn != sn or wn != en:
					up = true
				elif (vals["north"] == "tall" and vals["south"] == "tall") or (vals["east"] == "tall" and vals["west"] == "tall"):
					up = false
				else:
					up = (above > 0 and Res.mode == "vanilla" and Tags.has_block("wall_post_override", b.name_of(above))) or _covers(above, POST_TEST, "")
			st = b.with_prop(st, "up", "true" if up else "false")
		K_GATE:
			var f := b.get_prop(st, "facing")
			var a: Vector3i = SIDE_OFF[SIDES.find(CW.get(f, "east"))]
			var s1: int = world.state_at(p.x + a.x, p.y, p.z + a.z)
			var s2: int = world.state_at(p.x - a.x, p.y, p.z - a.z)
			if b.has_prop(st, "in_wall"):
				st = b.with_prop(st, "in_wall", "true" if kind_of(s1) == K_WALL or kind_of(s2) == K_WALL else "false")
		K_STAIRS:
			if b.has_prop(st, "shape"):
				st = b.with_prop(st, "shape", _stairs_shape(world, p, st))
	return st


static func _is_stairs(st: int) -> bool:
	return kind_of(st) == K_STAIRS


## Java StairBlock.getStairsShape / canTakeShape
static func _stairs_shape(world, p: Vector3i, st: int) -> String:
	var b := Res.blocks
	var f := b.get_prop(st, "facing")
	var half := b.get_prop(st, "half")
	var fo: Vector3i = SIDE_OFF[SIDES.find(f)] if SIDES.has(f) else Vector3i.ZERO
	var front: int = world.state_at(p.x + fo.x, p.y, p.z + fo.z)
	if _is_stairs(front) and b.get_prop(front, "half") == half:
		var f1 := b.get_prop(front, "facing")
		if (f1 in ["north", "south"]) != (f in ["north", "south"]) and _can_take(world, p, st, OPP.get(f1, f1)):
			return "outer_left" if f1 == CCW.get(f, "") else "outer_right"
	var back: int = world.state_at(p.x - fo.x, p.y, p.z - fo.z)
	if _is_stairs(back) and b.get_prop(back, "half") == half:
		var f2 := b.get_prop(back, "facing")
		if (f2 in ["north", "south"]) != (f in ["north", "south"]) and _can_take(world, p, st, f2):
			return "inner_left" if f2 == CCW.get(f, "") else "inner_right"
	return "straight"


static func _can_take(world, p: Vector3i, st: int, face: String) -> bool:
	if not SIDES.has(face):
		return true
	var o: Vector3i = SIDE_OFF[SIDES.find(face)]
	var n: int = world.state_at(p.x + o.x, p.y, p.z + o.z)
	var b := Res.blocks
	return not _is_stairs(n) or b.get_prop(n, "facing") != b.get_prop(st, "facing") or b.get_prop(n, "half") != b.get_prop(st, "half")


static func _relevant(st: int) -> bool:
	return st > 0 and ((Res.blocks.st_flags[st] & BlockRegistry.F_COLLIDE) != 0 or kind_of(st) != K_NONE)


## A gameplay block change at p (old -> st): fix the block itself, then its six neighbours. Changes between
## non-colliding, non-connecting states (water flowing, plants) cannot affect any connection and return at once.
static func on_changed(world, p: Vector3i, old: int, st: int) -> void:
	if not (_relevant(old) or _relevant(st)):
		return
	var b := Res.blocks
	if st > 0 and kind_of(st) != K_NONE and kind_of(st) != K_SOIL and kind_of(st) != K_EXCEPT:
		var ns := computed(world, p, st)
		if ns != st:
			world.set_block(p.x, p.y, p.z, ns, false)
			st = ns
	for d in [Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 1, 0)]:
		var q: Vector3i = p + d
		var qs: int = world.state_at(q.x, q.y, q.z)
		if qs <= 0:
			continue
		var k := kind_of(qs)
		if k == K_NONE or k == K_EXCEPT:
			continue
		if k == K_SOIL:
			if d.y == -1 and is_solid(st) and not b.name_of(st).ends_with("_fence_gate"):
				world.set_block(q.x, q.y, q.z, b.default_state("dirt"), false)
			continue
		if d.y != 0 and k != K_WALL:
			continue
		var nq := computed(world, q, qs)
		if nq != qs:
			world.set_block(q.x, q.y, q.z, nq, false)
