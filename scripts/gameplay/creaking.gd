## Creaking — Java CreakingHeartBlock / CreakingHeartBlockEntity / Creaking (pale garden):
## - heart state: uprooted unless both blocks along its axis are pale oak logs; then dormant by day, awake at night
##   (Java isNaturalNight: sky darken >= 4 in natural dimensions).
## - an awake heart with a survival player within 32 blocks spawns one protector creaking (every 20-24 ticks, 5
##   attempts within 16 blocks horizontally / 8 vertically, on top of a solid block) unless difficulty is Peaceful.
## - the protector is removed (crumbles) at day, beyond 34 blocks, or when its heart is broken; hits on it deal no
##   damage, make the heart emit and grow 1-3 resin clumps on pale oak logs next to the heart.
## - creakings freeze while a player looks at them (Java Creaking.checkCanMove / isLookingAtMe) and only then
##   chase and attack (3 damage).
## Heart positions come from a periodic scan of chunks around the player.
class_name Creaking
extends RefCounted

static var hearts: Array = []          # Vector3i
static var _scan_t := 0
static var _tick_t := 0
static var _heart_id := -1


## Java Level.isNight: skyDarken = (int)((1 - f * rain * thunder) * 11) >= 4, f = 0.5 + 2 * clamp(cos(angle), +-0.25).
static func night(world) -> bool:
	if world.dimension != "overworld":
		return false
	var f := 0.5 + 2.0 * clampf(cos(world.celestial_angle() * TAU), -0.25, 0.25)
	var d := 1.0 - float(world.rain) * 5.0 / 16.0
	var e := 1.0 - float(world.thunder) * 5.0 / 16.0
	return int((1.0 - f * d * e) * 11.0) >= 4


static func _logs_along(world, p: Vector3i, st: int) -> bool:
	var b := Res.blocks
	var ax := b.get_prop(st, "axis") if b.has_prop(st, "axis") else "y"
	var d := Vector3i(0, 1, 0) if ax == "y" else (Vector3i(1, 0, 0) if ax == "x" else Vector3i(0, 0, 1))
	for q in [p + d, p - d]:
		var s: int = world.state_at(q.x, q.y, q.z)
		if s <= 0:
			return false
		var n := b.name_of(s)
		if not (n == "pale_oak_log" or n == "pale_oak_wood" or n == "stripped_pale_oak_log" or n == "stripped_pale_oak_wood"):
			return false
	return true


## The 7 x 7 chunk heart scan, one chunk row per tick (the whole area in one tick was a periodic spike: ~1,200 sections'
## palettes in GDScript); the list is published when the 7th row is done.
static var _scan_row := -1
static var _scan_pc := Vector2i.ZERO
static var _scan_found: Array = []


static func _scan(world) -> void:
	var b := Res.blocks
	if _heart_id < 0:
		_heart_id = b.block_id("creaking_heart")
	if _heart_id < 0:
		return
	if _scan_row < 0:
		_scan_row = 0
		_scan_pc = Vector2i(int(floor(world.player.pos.x)) >> 4, int(floor(world.player.pos.z)) >> 4)
		_scan_found = []
	var pc := _scan_pc
	var hearts_out: Array = _scan_found
	for cz in [pc.y - 3 + _scan_row]:
		for cx in range(pc.x - 3, pc.x + 4):
			var ch: Chunk = world.cm.get_chunk(cx, cz)
			if ch == null or ch.state < Chunk.DECORATED:
				continue
			for s in Coords.SECTIONS:
				var sec: Chunk.Section = ch.sections[s]
				var y0 := Coords.MIN_Y + s * 16
				# palette entries that are creaking hearts, then their cells via the packed index arrays' native find
				# (a per-cell GDScript loop over 4096 cells cost ~6 ms for each section holding a heart)
				var cells := PackedInt32Array()
				for pi in sec.pal.size():
					var pst: int = sec.pal[pi]
					if pst <= 0 or b.st_block[pst] != _heart_id:
						continue
					if sec.pal.size() == 1:
						for li0 in 4096:
							cells.append(li0)
						continue
					var li := sec.wide.find(pi) if sec.wide.size() > 0 else sec.idx.find(pi)
					while li >= 0:
						cells.append(li)
						li = sec.wide.find(pi, li + 1) if sec.wide.size() > 0 else sec.idx.find(pi, li + 1)
				cells.sort()   # y, z, x order as the old cell loop (heart tick order)
				for li2 in cells:
					hearts_out.append(Vector3i(cx * 16 + (li2 & 15), y0 + (li2 >> 8), cz * 16 + ((li2 >> 4) & 15)))
	_scan_row += 1
	if _scan_row >= 7:
		_scan_row = -1
		hearts = _scan_found


static func _protector(world, h: Vector3i):
	for e in world.entities.ents:
		if e.kind == "mob" and e.id == "creaking" and not e.dead and e.data.get("heart") is Array and Vector3i(e.data["heart"][0], e.data["heart"][1], e.data["heart"][2]) == h:
			return e
	return null


## Java Creaking.tearDown: the protector crumbles.
## 45 ticks of twitching (EntityManager._tick_dying), then it crumbles into pale oak particles.
static func tear_down(world, e) -> void:
	if e.data.has("tear"):
		return
	e.data["tear"] = 0
	e.vel = Vector3.ZERO
	Audio.play("entity.creaking.twitch", e.pos, "Hostile")


static func tick(world) -> void:
	if world.cm == null or world.player == null or world.dimension != "overworld":
		return
	_scan_t -= 1
	if _scan_t <= 0 or _scan_row >= 0:
		if _scan_row < 0:
			_scan_t = 100
		_scan(world)
	_tick_t -= 1
	if _tick_t > 0 or hearts.is_empty():
		return
	_tick_t = 20 + world.rng.randi_range(0, 4)
	var b := Res.blocks
	var p: Player = world.player
	var is_night := night(world)
	for h in hearts.duplicate():
		var st: int = world.state_at(h.x, h.y, h.z)
		if st <= 0 or b.st_block[st] != _heart_id:
			continue
		var want := "uprooted"
		if _logs_along(world, h, st):
			want = "awake" if is_night else "dormant"
		if b.has_prop(st, "creaking_heart_state") and b.get_prop(st, "creaking_heart_state") != want:
			st = b.with_prop(st, "creaking_heart_state", want)
			world.set_block(h.x, h.y, h.z, st, false)
		var prot = _protector(world, h)
		if prot != null:
			if (not is_night and not prot.persistent) or prot.pos.distance_to(Vector3(h)) > 34.0 or want == "uprooted":
				tear_down(world, prot)
			continue
		if want != "awake" or world.difficulty == 0 or not world.gamerule("doMobSpawning", true):
			continue
		if p.dead or p.is_creative() or p.is_spectator() or p.pos.distance_to(Vector3(h)) > 32.0:
			continue
		# Java SpawnUtil.trySpawnMob(CREAKING, 5 attempts, 16 xz, 8 y, ON_TOP_OF_COLLIDER_NO_LEAVES)
		for attempt in 5:
			var q := Vector3i(h.x + world.rng.randi_range(-16, 16), h.y + 8, h.z + world.rng.randi_range(-16, 16))
			for dy in 16:
				var y := q.y - dy
				var below: int = world.state_at(q.x, y - 1, q.z)
				if below > 0 and (b.st_flags[below] & BlockRegistry.F_COLLIDE) != 0 and (b.st_flags[below] & BlockRegistry.F_LEAVES) == 0 \
						and world.state_at(q.x, y, q.z) == 0 and world.state_at(q.x, y + 1, q.z) == 0 and world.state_at(q.x, y + 2, q.z) == 0:
					var c = world.entities.spawn_mob("creaking", Vector3(q.x + 0.5, y, q.z + 0.5))
					if c != null:
						c.data["heart"] = [h.x, h.y, h.z]
						Audio.play("entity.creaking.spawn", c.pos, "Hostile")
						Audio.play("block.creaking_heart.spawn", Vector3(h), "Blocks")
					break
			if _protector(world, h) != null:
				break


## Damage hook: protectors take no damage while their heart stands. Returns true when the hit was absorbed.
static func absorb_hit(world, e) -> bool:
	if e.id != "creaking" or not (e.data.get("heart") is Array):
		return false
	var h := Vector3i(e.data["heart"][0], e.data["heart"][1], e.data["heart"][2])
	var st: int = world.state_at(h.x, h.y, h.z)
	if st <= 0 or Res.blocks.name_of(st) != "creaking_heart":
		e.data.erase("heart")
		return false
	Audio.play("entity.creaking.sway", e.pos, "Hostile")
	e.hurt_time = 10
	# Java CreakingHeartBlockEntity.creakingHurt: particle trail to the heart and resin clumps on nearby pale oak logs
	for i in 8:
		Particles.emit("dust", Vector3(e.pos).lerp(Vector3(h) + Vector3(0.5, 0.5, 0.5), float(i) / 8.0) + Vector3(0, e.h * 0.6, 0), Vector3.ZERO, Color(0.9, 0.5, 0.15))
	_grow_resin(world, h, world.rng.randi_range(2, 3))
	return true


## Java CreakingHeartBlockEntity.spreadResin: breadth-first over pale oak logs connected to the heart (depth 2, 64
## blocks); the first log with a free face gets a resin clump on it (2-3 clumps per hit).
static func _grow_resin(world, h: Vector3i, n: int) -> void:
	var b := Res.blocks
	var resin: int = b.default_state("resin_clump")
	if resin < 0:
		return
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	var face_of := {Vector3i(1, 0, 0): "west", Vector3i(-1, 0, 0): "east", Vector3i(0, 0, 1): "north", Vector3i(0, 0, -1): "south", Vector3i(0, 1, 0): "down", Vector3i(0, -1, 0): "up"}
	for k in n:
		var seen := {h: true}
		var frontier: Array = [[h, 0]]
		var placed := false
		var visited := 0
		while not frontier.is_empty() and not placed and visited < 64:
			var cur: Array = frontier.pop_front()
			var pos: Vector3i = cur[0]
			visited += 1
			var sh := dirs.duplicate()
			sh.shuffle()
			var ps: int = world.state_at(pos.x, pos.y, pos.z)
			if pos != h and ps > 0 and b.name_of(ps).contains("pale_oak_log"):
				for d in sh:
					var q: Vector3i = pos + d
					var qs: int = world.state_at(q.x, q.y, q.z)
					var face: String = face_of[d]
					if qs == 0:
						world.set_block(q.x, q.y, q.z, b.with_prop(resin, face, "true") if b.has_prop(resin, face) else resin)
						placed = true
						break
					if qs > 0 and b.name_of(qs) == "resin_clump" and b.has_prop(qs, face) and b.get_prop(qs, face) == "false":
						world.set_block(q.x, q.y, q.z, b.with_prop(qs, face, "true"))
						placed = true
						break
			if placed or int(cur[1]) >= 2:
				continue
			for d2 in sh:
				var nq: Vector3i = pos + d2
				if seen.has(nq):
					continue
				var ns: int = world.state_at(nq.x, nq.y, nq.z)
				if ns > 0 and b.name_of(ns).contains("pale_oak_log"):
					seen[nq] = true
					frontier.append([nq, int(cur[1]) + 1])

## Java Creaking.checkCanMove: frozen while a survival player within 32 blocks looks at it with line of sight.
static func looked_at(world, e) -> bool:
	var p: Player = world.player
	if p.dead or p.is_spectator() or p.is_creative():
		return false
	var eye: Vector3 = p.eye_pos()
	for hy in [e.h * 0.9, e.h * 0.5, e.h * 0.1]:
		var tgt: Vector3 = e.pos + Vector3(0, hy, 0)
		var dv := tgt - eye
		var dist := dv.length()
		if dist > 32.0 or dist < 0.01:
			continue
		# Java isLookingAtMe: view . dir > 1 - 0.025 / distance-scaled cone (approximated with 0.5 / dist)
		if p.look_dir().dot(dv / dist) > 1.0 - 0.5 / dist * 0.5 - 0.02:
			var hit := VoxelRaycast.cast(eye, dv / dist, dist, world.state_at, Res.blocks)
			if hit.is_empty() or float(hit.get("dist", 0.0)) >= dist - 0.5:
				return true
	return false


## Breaking a heart tears its protector down.
static func on_block_changed(world, pos: Vector3i, old: int) -> void:
	if old <= 0 or Res.blocks.name_of(old) != "creaking_heart":
		return
	var prot = _protector(world, pos)
	if prot != null:
		tear_down(world, prot)
