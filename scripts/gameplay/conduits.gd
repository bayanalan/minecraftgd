## Conduits (minecraft.wiki Conduit / Conduit Power, Java Edition):
## - Active while the conduit is waterlogged, the 26 blocks around it are water (source, flowing or waterlogged) and at
##   least 16 frame blocks (prismarine, prismarine bricks, dark prismarine, sea lantern; not slabs / stairs / walls)
##   stand in the three 5 x 5 rings centred on it, one around each axis (42 positions).
## - Range 16 x floor(frame / 7) blocks (32 at 16 .. 96 at 42), a sphere: players in it touching water or rain get
##   Conduit Power for 13 s ("activates every second").
## - A complete frame attacks one hostile mob within 8 blocks that touches water or rain: 4 HP every 2 s (sound
##   block.conduit.attack.target), keeping the target until it dies or leaves; the eye is open while it hunts.
## - Sounds: activate (0.9), deactivate (0.7), ambient_short every 3-5 s while active (the ambient loop is not played).
## - Render state for BERender: `active` pos -> {"frame", "range", "hunt", "since"} (since: game tick it activated).
## Contract: static; tick(world) every game tick (host) - O(conduits), work every 20 ticks.
class_name Conduits

const FRAME_BLOCKS := ["prismarine", "prismarine_bricks", "dark_prismarine", "sea_lantern"]
const MIN_FRAME := 16
const FULL_FRAME := 42
const ATTACK_RANGE := 8.0
const ATTACK_DAMAGE := 4.0
const EFFECT_TICKS := 260   # wiki Conduit Power: 0:13

static var active: Dictionary = {}     # Vector3i -> {"frame": int, "range": int, "hunt": bool, "since": int}
static var _targets: Dictionary = {}   # Vector3i -> Ent being attacked
static var _ambient: Dictionary = {}   # Vector3i -> game tick of the next ambient_short
static var _offs: Array = []


static func reset() -> void:
	active.clear()
	_targets.clear()
	_ambient.clear()


## The 42 frame positions: on the shell of the 5 x 5 x 5 cube and in one of the three axis planes.
static func frame_offsets() -> Array:
	if _offs.is_empty():
		for x in range(-2, 3):
			for y in range(-2, 3):
				for z in range(-2, 3):
					if maxi(absi(x), maxi(absi(y), absi(z))) == 2 and (x == 0 or y == 0 or z == 0):
						_offs.append(Vector3i(x, y, z))
	return _offs


static func _watery(st: int) -> bool:
	if st <= 0:
		return false
	var fl := Res.blocks.st_flags[st]
	return ((fl & BlockRegistry.F_LIQUID) != 0 and (fl & BlockRegistry.F_LAVA) == 0) or (fl & BlockRegistry.F_WATERLOGGED) != 0


## Frame blocks counted for the conduit at p, or 0 when it is not in water (not waterlogged / a gap in the 3 x 3 x 3).
static func frame_count(world, p: Vector3i) -> int:
	var b := Res.blocks
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0 or b.get_prop(st, "waterlogged") != "true":
		return 0
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				if (x != 0 or y != 0 or z != 0) and not _watery(world.state_at(p.x + x, p.y + y, p.z + z)):
					return 0
	var n := 0
	for o in frame_offsets():
		var q: Vector3i = p + o
		var qs: int = world.state_at(q.x, q.y, q.z)
		if qs > 0 and b.name_of(qs) in FRAME_BLOCKS:
			n += 1
	return n


## wiki Conduit: range 16 x floor(frame / 7), nothing below 16 frame blocks.
static func range_for(frame: int) -> int:
	return 0 if frame < MIN_FRAME else (frame / 7) * 16


static func tick(world) -> void:
	var now := int(world.game_time)
	if now % 20 != 0:
		return
	var seen: Dictionary = {}
	for c in BlockEntities.chunks_with(world, ["conduit"]):
		var ch: Chunk = c
		for k in ch.block_entities:
			var d = ch.block_entities[k]
			if not (d is Dictionary) or str((d as Dictionary).get("id", "")) != "conduit":
				continue
			var p := BlockEntities.pos_of(ch, k)
			var st: int = world.state_at(p.x, p.y, p.z)
			if st <= 0 or Res.blocks.name_of(st) != "conduit":
				continue
			seen[p] = true
			_update(world, p, now)
	for p in active.keys():
		if not seen.has(p):
			active.erase(p)
			_targets.erase(p)
			_ambient.erase(p)


static func _update(world, p: Vector3i, now: int) -> void:
	var c := Vector3(p) + Vector3(0.5, 0.5, 0.5)
	var frame := frame_count(world, p)
	var rng := range_for(frame)
	var was: bool = active.has(p)
	if rng <= 0:
		if was:
			active.erase(p)
			_targets.erase(p)
			_ambient.erase(p)
			Audio.play("block.conduit.deactivate", c, "Blocks", 0.7)
		return
	if not was:
		Audio.play("block.conduit.activate", c, "Blocks", 0.9)
		active[p] = {"since": now}
		_ambient[p] = now + world.rng.randi_range(60, 100)
	var a: Dictionary = active[p]
	a["frame"] = frame
	a["range"] = rng
	a["hunt"] = frame >= FULL_FRAME
	if now >= int(_ambient.get(p, 0)):
		Audio.play("block.conduit.ambient.short", c, "Blocks", 1.0)
		_ambient[p] = now + world.rng.randi_range(60, 100)   # wiki: every 3-5 seconds while active
	# Conduit Power for players in range touching water or rain
	var players: Array = [world.player]
	players.append_array(Net.proxies())
	for pl in players:
		if pl == null or pl.dead or pl.pos.distance_to(c) > float(rng):
			continue
		if pl.get("in_water") == true or BlockUpdates._raining_at(world, Vector3i((pl.pos + Vector3(0, 1.0, 0)).floor())):
			pl.add_effect("conduit_power", 0, EFFECT_TICKS)
	if a["hunt"] and now % 40 == 0:
		_attack(world, p, c)
	elif not a["hunt"]:
		_targets.erase(p)


## wiki Conduit: one hostile mob at a time within 8 blocks, in contact with water or rain, 4 HP every 2 seconds.
static func _attack(world, p: Vector3i, c: Vector3) -> void:
	var em = world.get("entities")
	if em == null:
		return
	var t = _targets.get(p)
	if t != null and (not is_instance_valid(t) or t.dead or t.pos.distance_to(c) > ATTACK_RANGE or not _wet(world, t)):
		t = null
	if t == null:
		var bd := ATTACK_RANGE + 0.001
		for e in em.ents:
			if e.kind != "mob" or e.dead or str(e.def.get("kind", "")) != "hostile":
				continue
			var dd: float = e.pos.distance_to(c)
			if dd < bd and _wet(world, e):
				bd = dd
				t = e
	if t == null:
		_targets.erase(p)
		return
	_targets[p] = t
	em._damage(t, ATTACK_DAMAGE, null)
	Audio.play("block.conduit.attack.target", c, "Blocks", 1.0)


static func _wet(world, e) -> bool:
	var q := Vector3i((e.pos + Vector3(0, 0.1, 0)).floor())
	return _watery(world.state_at(q.x, q.y, q.z)) or BlockUpdates._raining_at(world, Vector3i((e.pos + Vector3(0, e.h, 0)).floor()))
