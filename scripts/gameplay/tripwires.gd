## Tripwires — tripwire hooks and string (minecraft.wiki Tripwire Hook / String, Java Edition):
## - A circuit is two hooks facing each other with a straight horizontal line of 1-40 tripwire between them. Both hooks
##   and the strings of a valid line are "attached" (extended hooks, the lowered string model).
## - An entity whose box meets a string's box (attached: 0.0625 .. 0.15625 high; detached: 0 .. 0.5) powers that string;
##   the hooks of a valid line with a powered (not disarmed) string output 15 (strong power into the block they hang
##   on). A powered string re-checks every 10 game ticks and turns off once no entity touches it. Spectators, area effect
##   clouds, markers, thrown eyes of ender and the ender dragon never trigger it (Sensors._boxes).
## - Breaking a string without shears counts as a powered string for 10 game ticks (the hooks pulse 5 redstone ticks),
##   then the hooks detach; shears disarm it first: the hooks detach at once without a pulse. Breaking a hook (or the
##   block it hangs on) detaches its line without a pulse.
## - Strings connect (north / south / east / west) to strings and to hooks facing them.
## - Sounds (Java): attach 0.4 / 0.7, click on 0.4 / 0.6, click off 0.4 / 0.5, detach 0.4 / 12/11 .. 4/3.
## Contract: static; on_placed / on_removed(world, pos, state[, sheared]) from block placement / breaking,
## check_pressed(world, pos, state, boxes) from the Sensors entity loop, scheduled(world, pos, state) from Redstone.
class_name Tripwires

const MAX_STRINGS := 40
const NONE := Vector3i(0, -99999, 0)
const H4 := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0)}
const PULSE := 10   # game ticks a string broken without shears keeps its hooks powered (5 redstone ticks)
const RECHECK := 10  # wiki String: a powered string schedules its next check 10 game ticks later

static var _pulse: Dictionary = {}   # hook pos -> game tick its broken-string pulse ends


static func is_hook(st: int) -> bool:
	return st > 0 and Res.blocks.name_of(st) == "tripwire_hook"


static func is_wire(st: int) -> bool:
	return st > 0 and Res.blocks.name_of(st) == "tripwire"


static func _facing(st: int) -> Vector3i:
	return H4.get(Res.blocks.get_prop(st, "facing"), Vector3i.ZERO)


static func _on(st: int, prop: String) -> bool:
	return Res.blocks.get_prop(st, prop) == "true"


static func _with(st: int, prop: String, v: bool) -> int:
	return Res.blocks.with_prop(st, prop, "true" if v else "false") if Res.blocks.has_prop(st, prop) else st


## Recomputes the line of the hook at hp (state hst): both hooks' attached / powered, the strings' attached. removing:
## the hook itself is being removed. changed / changed_st: a string that just changed (or was removed) at that spot.
static func calc_hook(world, hp: Vector3i, hst: int, removing := false, changed := NONE, changed_st := 0, pulse := false) -> void:
	var f := _facing(hst)
	if f == Vector3i.ZERO:
		return
	var strings: Array = []
	var other := NONE
	var other_st := 0
	var valid := not removing
	var powered := false
	for i in range(1, MAX_STRINGS + 2):
		var q := hp + f * i
		var qs: int = changed_st if q == changed else int(world.state_at(q.x, q.y, q.z))
		if is_hook(qs):
			if _facing(qs) == -f:
				other = q
				other_st = qs
			break
		if not is_wire(qs):
			valid = false
			break
		if _on(qs, "disarmed"):
			valid = false
		elif _on(qs, "powered"):
			powered = true
		if q != changed or is_wire(world.state_at(q.x, q.y, q.z)):
			strings.append(q)
	if other == NONE or other == hp + f:
		valid = false   # (no facing hook, or no string between the two)
	powered = powered and valid
	_set_hook(world, hp, hst, valid, powered, removing)
	if other != NONE:
		_set_hook(world, other, other_st, valid, powered, false)
	for q in strings:
		var ss: int = world.state_at(q.x, q.y, q.z)
		if is_wire(ss) and _on(ss, "attached") != valid:
			world.set_block(q.x, q.y, q.z, _with(ss, "attached", valid), false)
	if changed != NONE and not removing:
		BlockUpdates.schedule(world, hp, RECHECK)
	if pulse:
		# both hooks hold the broken string's pulse (their neighbour updates must not end it early)
		for h in [hp, other]:
			if h != NONE:
				_pulse[h] = int(world.game_time) + PULSE
				BlockUpdates.schedule(world, h, PULSE)


static func _set_hook(world, hp: Vector3i, hst: int, attached: bool, powered: bool, removed: bool) -> void:
	var was_att := _on(hst, "attached")
	var was_pow := _on(hst, "powered")
	if not removed:
		var ns := _with(_with(hst, "attached", attached), "powered", powered)
		if ns != hst:
			world.set_block(hp.x, hp.y, hp.z, ns, false)
		if powered != was_pow:
			Redstone.on_changed(world, hp)
			Redstone.on_changed(world, hp - _facing(hst))   # the block it hangs on (strongly powered)
	else:
		attached = false
		powered = false
	var at := Vector3(hp) + Vector3(0.5, 0.5, 0.5)
	if powered and not was_pow:
		Audio.play("block.tripwire.click_on", at, "Blocks", 0.4, 0.6)
	elif not powered and was_pow:
		Audio.play("block.tripwire.click_off", at, "Blocks", 0.4, 0.5)
	elif attached and not was_att:
		Audio.play("block.tripwire.attach", at, "Blocks", 0.4, 0.7)
	elif not attached and was_att:
		Audio.play("block.tripwire.detach", at, "Blocks", 0.4, 1.2 / (randf() * 0.2 + 0.9))


## A string at q changed to cst (or was removed): the hooks of its lines recompute (one hook per axis does the line).
static func _update_source(world, q: Vector3i, cst: int, pulse := false) -> void:
	for d in [Vector3i(0, 0, 1), Vector3i(-1, 0, 0)]:
		for i in range(1, MAX_STRINGS + 2):
			var h: Vector3i = q + d * i
			var hs: int = world.state_at(h.x, h.y, h.z)
			if is_hook(hs):
				if _facing(hs) == -d:
					calc_hook(world, h, hs, false, q, cst, pulse)
				break
			if not is_wire(hs):
				break


## Java TripWireBlock.shouldConnectTo: strings join strings and hooks facing them.
static func update_shape(world, q: Vector3i) -> void:
	var st: int = world.state_at(q.x, q.y, q.z)
	if not is_wire(st):
		return
	var ns := st
	for side in H4:
		var v: Vector3i = H4[side]
		var n := q + v
		var nst: int = world.state_at(n.x, n.y, n.z)
		ns = _with(ns, side, is_wire(nst) or (is_hook(nst) and _facing(nst) == -v))
	if ns != st:
		world.set_block(q.x, q.y, q.z, ns, false)


static func _shape_around(world, p: Vector3i) -> void:
	update_shape(world, p)
	for side in H4:
		update_shape(world, p + H4[side])


## After a tripwire or hook was placed.
static func on_placed(world, p: Vector3i, st: int) -> void:
	if is_wire(st):
		_shape_around(world, p)
		_update_source(world, p, world.state_at(p.x, p.y, p.z))
	elif is_hook(st):
		_shape_around(world, p + _facing(st))
		calc_hook(world, p, world.state_at(p.x, p.y, p.z))


## After a tripwire / hook at p (old state st) was removed. sheared: the string was cut with shears (disarmed: no pulse).
static func on_removed(world, p: Vector3i, st: int, sheared: bool) -> void:
	if is_wire(st):
		_shape_around(world, p)
		var cst := _with(_with(st, "powered", true), "disarmed", sheared or _on(st, "disarmed"))
		_update_source(world, p, cst, not (sheared or _on(st, "disarmed")))
	elif is_hook(st):
		_pulse.erase(p)
		calc_hook(world, p, st, true)
		_shape_around(world, p + _facing(st))


## Java TripWireBlock.checkPressed: an entity box crossing the string's box powers it; powered strings re-check every
## 10 game ticks. boxes: Sensors._boxes(world).
static func check_pressed(world, q: Vector3i, st: int, boxes: Array) -> void:
	var att := _on(st, "attached")
	var mn := Vector3(q) + Vector3(0.0, 0.0625 if att else 0.0, 0.0)
	var mx := Vector3(q) + Vector3(1.0, 0.15625 if att else 0.5, 1.0)
	var pressed := false
	for bx in boxes:
		if not bx[3]:
			continue
		var a: Vector3 = bx[0]
		var c: Vector3 = bx[1]
		if a.x < mx.x and c.x > mn.x and a.y < mx.y and c.y > mn.y and a.z < mx.z and c.z > mn.z:
			pressed = true
			break
	if pressed != _on(st, "powered"):
		var ns := _with(st, "powered", pressed)
		world.set_block(q.x, q.y, q.z, ns)
		_update_source(world, q, ns)
	if pressed:
		BlockUpdates.schedule(world, q, RECHECK)


static func scheduled(world, p: Vector3i, st: int) -> void:
	if is_wire(st):
		if _on(st, "powered"):
			check_pressed(world, p, st, Sensors._boxes(world))
		return
	if not is_hook(st):
		return
	# Java TripWireHookBlock.canSurvive: it needs a solid block behind it
	var bk := p - _facing(st)
	var bs: int = world.state_at(bk.x, bk.y, bk.z)
	if bs == 0 or (bs > 0 and (Res.blocks.st_flags[bs] & BlockRegistry.F_COLLIDE) == 0):
		world.set_block(p.x, p.y, p.z, 0)
		if world.gamerule("doTileDrops", true) and world.get("entities") != null:
			world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.5, 0.5), ItemStack.named("tripwire_hook", 1))
		on_removed(world, p, st, false)
		return
	var now := int(world.game_time)
	if _pulse.has(p):
		if now < int(_pulse[p]):
			BlockUpdates.schedule(world, p, int(_pulse[p]) - now)
			return
		_pulse.erase(p)
	calc_hook(world, p, st)


static func reset() -> void:
	_pulse.clear()
