## Bells (minecraft.wiki Bell, Java Edition):
## - Rung by using one of the sides it swings toward (floor bells: the two faces along their facing; wall bells: the
##   two faces across it; ceiling bells: any side), by a projectile hit, or once by a rising redstone signal (toward
##   its facing). Sound block.bell.use (Blocks, volume 2.0 on the sound's own 12 = the wiki's 24; the pitch variants
##   0.93 / 0.95 / 0.97 come from the sound definition).
## - Ringing with a raider within 32 blocks makes the raiders within 48 blocks glow for 3 s (block.bell.resonate,
##   volume 1.0); the wiki gives no delay, so it happens at once here.
## - Villagers within 32 blocks run to the nearest bed within 32 blocks (EntityManager follows rt["bell_home"]).
## - The swing (Java BellRenderer): body xRot / zRot = +-sin(t / pi) / (4 + t / 3) toward the rung side for the
##   bell's 50-tick shake (BellBlockEntity; the wiki gives no duration); BERender poses it from `swing`.
class_name Bells

const SHAKE_TICKS := 50        # Java BellBlockEntity shake length (not on the wiki)
const RAIDER_TRIGGER := 32.0   # wiki Bell: a raid mob within a 32 block spherical range ...
const RAIDER_GLOW := 48.0      # ... gives the raid mobs within 48 blocks Glowing
const GLOW_TICKS := 60         # ... for 3 seconds
const VILLAGER_HEAR := 32.0    # wiki Bell: villagers within 32 blocks ...
const BED_SEARCH := 32         # ... run to the nearest bed within 32 blocks

static var swing: Dictionary = {}   # bell pos -> [game tick rung, rung side (Vector3i, horizontal)]
static var _bed := PackedByteArray()


static func reset() -> void:
	swing.clear()


## Right-click on a bell (hit = VoxelRaycast result). Returns true when it rang.
static func use(world, p: Vector3i, st: int, hit: Dictionary) -> bool:
	var n: Vector3i = hit.get("normal", Vector3i.UP)
	if n.y != 0:
		return false
	var b := Res.blocks
	var f: Vector3i = Redstone.H.get(b.get_prop(st, "facing"), Vector3i(0, 0, -1))
	var along := (n.x != 0) == (f.x != 0)
	match b.get_prop(st, "attachment"):
		"floor":
			if not along:
				return false
		"single_wall", "double_wall":
			if along:
				return false
	ring(world, p, n)
	return true


## Rings the bell at p, swinging away from side `side` (ZERO: toward the bell's facing - redstone).
static func ring(world, p: Vector3i, side: Vector3i) -> void:
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0 or Res.blocks.name_of(st) != "bell":
		return
	if side == Vector3i.ZERO:
		side = Redstone.H.get(Res.blocks.get_prop(st, "facing"), Vector3i(0, 0, -1))
	var now := int(world.game_time)
	for q in swing.keys():
		if now - int(swing[q][0]) >= SHAKE_TICKS:
			swing.erase(q)
	swing[p] = [now, side]
	var c := Vector3(p) + Vector3(0.5, 0.5, 0.5)
	Audio.play("block.bell.use", c, "Blocks", 2.0)
	if world.get("dimension") != null:
		Sculk.vibrate(world, c, true)   # (GameEvent.BLOCK_CHANGE)
	var em = world.get("entities")
	if em == null:
		return
	var raider := false
	for e in em.ents:
		if not e.dead and Raids.is_raider(e) and e.pos.distance_to(c) <= RAIDER_TRIGGER:
			raider = true
			break
	if raider:
		Audio.play("block.bell.resonate", c, "Blocks", 1.0)
		for e in em.ents:
			if not e.dead and Raids.is_raider(e) and e.pos.distance_to(c) <= RAIDER_GLOW:
				MobBehaviors.add_effect(e, "glowing", 0, GLOW_TICKS)   # (the Glowing effect: GlowOutline draws the outline)
	var bed := Vector3.INF
	var bed_done := false
	for e in em.ents:
		if e.dead or e.kind != "mob" or e.id != "villager" or e.pos.distance_to(c) > VILLAGER_HEAR:
			continue
		if not bed_done:
			bed = _nearest_bed(world, c, BED_SEARCH)
			bed_done = true
		if bed == Vector3.INF:
			break
		e.rt["bell_home"] = bed
		e.rt["bell_tries"] = 0


## Nearest bed block (centre of its top) within r blocks of `at`; INF when none (chunk palettes are checked first).
static func _nearest_bed(world, at: Vector3, r: int) -> Vector3:
	var cm = world.get("cm")
	if cm == null:
		return Vector3.INF
	var b := Res.blocks
	if _bed.size() != b.total_states:
		var per_block := PackedByteArray()
		per_block.resize(b.names.size())
		for i in b.names.size():
			per_block[i] = 1 if str(b.names[i]).ends_with("_bed") else 0
		_bed.resize(b.total_states)
		for s in range(1, b.total_states):
			_bed[s] = per_block[b.st_block[s]]
	var best := Vector3.INF
	var bd := float(r * r) + 0.001
	for cz in range((int(floor(at.z)) - r) >> 4, ((int(floor(at.z)) + r) >> 4) + 1):
		for cx in range((int(floor(at.x)) - r) >> 4, ((int(floor(at.x)) + r) >> 4) + 1):
			var ch: Chunk = cm.get_chunk(cx, cz)
			if ch == null or ch.state < Chunk.DECORATED:
				continue
			for s in Coords.SECTIONS:
				var sec: Chunk.Section = ch.sections[s]
				var y0 := Coords.MIN_Y + s * 16
				if absf(float(y0) + 8.0 - at.y) > float(r) + 8.0:
					continue
				var pal := sec.pal
				var has := false
				for st in pal:
					if st > 0 and st < _bed.size() and _bed[st] != 0:
						has = true
						break
				if not has:
					continue
				var uni := pal.size() == 1
				var use_w := sec.wide.size() > 0
				for li in 4096:
					var st2: int = pal[0] if uni else (pal[sec.wide[li]] if use_w else pal[sec.idx[li]])
					if st2 <= 0 or _bed[st2] == 0:
						continue
					var q := Vector3(cx * 16 + (li & 15) + 0.5, y0 + (li >> 8) + 0.5625, cz * 16 + ((li >> 4) & 15) + 0.5)
					var d2 := q.distance_squared_to(at)
					if d2 < bd:
						bd = d2
						best = q
	return best


## Java BellRenderer body angles for the shake at tick t (partial included) rung from `side`: [xRot, zRot].
static func swing_angles(t: float, side: Vector3i) -> Vector2:
	if t < 0.0 or t >= SHAKE_TICKS:
		return Vector2.ZERO
	var j := sin(t / PI) / (4.0 + t / 3.0)
	if side == Vector3i(0, 0, -1):
		return Vector2(-j, 0.0)
	if side == Vector3i(0, 0, 1):
		return Vector2(j, 0.0)
	if side == Vector3i(1, 0, 0):
		return Vector2(0.0, -j)
	if side == Vector3i(-1, 0, 0):
		return Vector2(0.0, j)
	return Vector2.ZERO
