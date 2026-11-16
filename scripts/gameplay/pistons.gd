## Pistons — Java piston block events and moving blocks (PistonBaseBlock.triggerEvent / moveBlocks,
## PistonMovingBlockEntity, PistonHeadRenderer; wiki Piston, Sticky Piston, Piston Head, Moving Piston):
## - A power change queues the piston's block event; events run in the tick's block-event step (after scheduled ticks,
##   before block entities: a 0-1 tick start delay). Extending: the resolved structure (Redstone._resolve: 12 blocks,
##   slime / honey) leaves its cells and every block moves into a moving_piston cell one block ahead; the head grows out
##   of the base as a moving block too. Retracting: the base becomes a moving_piston that shows the head sliding back
##   in; a sticky piston pulls the block in front along (a pulse that ends before the extension finished makes it drop
##   that block instead, Java's event type 2).
## - Moving blocks advance 0.5 per tick (progress 0 -> 1 over 2 game ticks) and turn into their block at the start of
##   the following tick's block-entity step (Java: progress >= 1 at the start of a tick). Entities in the way are pushed
##   (Java moveCollidedEntities: the leading face's swept slab, + 0.01; slime blocks launch them at 1 block / tick);
##   the moved block loses its waterlogging; block-entity data travels with it. A moving cell keeps its block as a
##   "piston" block entity and a scheduled tick, so a save / reload mid-move still finishes it.
## - Rendering: one node per moving block at its interpolated position (partial tick), the head short during the first
##   half of an extension / the second half of a retraction (Java SHORT), kept until the terrain mesh shows the result.
## Contract: static; queue_event(pos), tick(world) every tick (host), render(world, alpha) every frame,
## scheduled(world, pos) (BlockUpdates), finish_all(world) (before saving), reset().
class_name Pistons

class Move:
	var pos := Vector3i.ZERO     # the cell it moves into (holds moving_piston meanwhile)
	var state := 0               # the moving block (head: piston_head; retracting base: the retracted piston)
	var dir := Vector3i.ZERO     # direction of motion
	var extending := true
	var source := false          # the piston's own head (extending) / its base (retracting)
	var start := 0               # game tick of the block event
	var be: Dictionary = {}
	var node: Node3D = null
	var long_mi: MeshInstance3D = null    # source: full-length head
	var short_mi: MeshInstance3D = null   # source: short head
	var head: Node3D = null               # retracting source: the sliding head (the base stays)
	var epoch0 := 0
	var t0_ms := 0
	var shown := false
	var done_epoch := -1
	var done_ms := 0

static var moving: Dictionary = {}    # Vector3i -> Move (in progress)
static var _ghosts: Array = []        # finished Moves still drawn until the terrain mesh has their block
static var _events: Dictionary = {}   # pistons with a block event pending
static var _mesh_cache: Dictionary = {}
static var _hold := -2.0   # render probe --pistonhold=<progress>: moves stay at that progress (-1 off, -2 not read yet)


static func _held(world) -> float:
	if _hold < -1.5:
		var ap = world.get("autoplay")
		_hold = float((ap as Dictionary).get("pistonhold", -1.0)) if ap is Dictionary else -1.0
	return _hold


static func reset() -> void:
	_hold = -2.0
	for p in moving:
		_free_node(moving[p])
	for g in _ghosts:
		_free_node(g)
	moving.clear()
	_ghosts.clear()
	_events.clear()


static func queue_event(p: Vector3i) -> void:
	_events[p] = true


static func busy(p: Vector3i) -> bool:
	return moving.has(p)


static func _now(world) -> int:
	return BlockUpdates._exec_tick if BlockUpdates._exec_tick >= 0 else int(world.game_time)


## Per game tick (block events, then the moving blocks' block-entity step).
static func tick(world) -> void:
	if not _events.is_empty():
		var lst: Array = _events.keys()
		_events.clear()
		for p in lst:
			_event(world, p)
	if moving.is_empty() or _held(world) >= 0.0:
		return
	var t := int(world.game_time)
	var due: Array = []
	for p in moving:
		var m: Move = moving[p]
		var age := t - m.start
		if age >= 2:
			due.append(m)
		elif age >= 0:
			_push_entities(world, m, age)
	for m in due:
		if moving.get(m.pos) == m:
			_finish(world, m)


## Java PistonBaseBlock.triggerEvent: re-checked when it runs (the power may be gone again).
static func _event(world, p: Vector3i) -> void:
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0:
		return
	var n := Res.blocks.name_of(st)
	if n != "piston" and n != "sticky_piston":
		return
	var pw := Redstone.piston_powered(world, p, st)
	var ext := Res.blocks.get_prop(st, "extended") == "true"
	if pw and not ext:
		extend(world, p, st)
	elif not pw and ext:
		retract(world, p, st)


static func _moving_state(f: Vector3i, sticky: bool) -> int:
	var b := Res.blocks
	var ms := b.default_state("moving_piston")
	if ms <= 0:
		return 0
	ms = b.with_prop(ms, "facing", _face(f))
	return b.with_prop(ms, "type", "sticky" if sticky else "normal")


static func _face(f: Vector3i) -> String:
	for k in Redstone.H:
		if Redstone.H[k] == f:
			return k
	return "north"


static func extend(world, p: Vector3i, st: int) -> bool:
	var b := Res.blocks
	var f := Redstone._dir(st)
	var res := Redstone._resolve(world, p, p + f, f, true)
	if res.is_empty():
		return false
	var t := _now(world)
	var sticky := b.name_of(st) == "sticky_piston"
	var ms := _moving_state(f, sticky)
	_destroy(world, res["destroy"])
	_move_blocks(world, res["move"], f, true, t, ms)
	world.set_block(p.x, p.y, p.z, b.with_prop(st, "extended", "true"))
	var head := b.default_state("piston_head")
	head = b.with_prop(b.with_prop(head, "facing", b.get_prop(st, "facing")), "type", "sticky" if sticky else "normal")
	_add(world, p + f, head, f, true, true, t, {}, ms)
	# wiki Piston sounds: extend volume 0.5, pitch 0.6-0.85
	Audio.play("block.piston.extend", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks", 0.5, 0.6 + randf() * 0.25)
	return true


static func retract(world, p: Vector3i, st: int) -> void:
	var b := Res.blocks
	var f := Redstone._dir(st)
	var h := p + f
	var sticky := b.name_of(st) == "sticky_piston"
	var t := _now(world)
	var ms := _moving_state(f, sticky)
	# a head still sliding out finishes first (Java: finalTick of the moving block in front)
	var hm: Move = moving.get(h)
	var short_pulse := hm != null and hm.source and hm.extending
	if short_pulse:
		_finish(world, hm)
	_add(world, p, b.with_prop(st, "extended", "false"), -f, false, true, t, {}, ms)
	var pulled := false
	if sticky:
		var front := h + f
		var fm: Move = moving.get(front)
		if fm != null and fm.extending and fm.dir == f:
			_finish(world, fm)   # the pulse ended mid-push: the block stays where it was going (dropped)
		elif not short_pulse:
			if Redstone._name(world.state_at(h.x, h.y, h.z)) == "piston_head":
				world.set_block(h.x, h.y, h.z, 0)
			var res := Redstone._resolve(world, p, front, -f, false)
			if not res.is_empty() and not (res["move"] as Array).is_empty():
				_destroy(world, res["destroy"])
				_move_blocks(world, res["move"], -f, false, t, ms)
				pulled = true
	if not pulled and Redstone._name(world.state_at(h.x, h.y, h.z)) == "piston_head":
		world.set_block(h.x, h.y, h.z, 0)
	# wiki Piston sounds: contract volume 0.5, pitch 0.6-0.8
	Audio.play("block.piston.contract", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks", 0.5, 0.6 + randf() * 0.2)


static func _destroy(world, lst: Array) -> void:
	for dpos in lst:
		var ds: int = world.state_at(dpos.x, dpos.y, dpos.z)
		var dbe: Dictionary = BlockEntities.get_data(world, dpos).duplicate(true)   # a pushed shulker box keeps its contents
		world.set_block(dpos.x, dpos.y, dpos.z, 0)
		if world.gamerule("doTileDrops", true):
			for s in Loot.block_drops(ds, null, world, dpos, dbe):
				world.entities.spawn_item(Vector3(dpos) + Vector3(0.5, 0.5, 0.5), s)
		if not dbe.is_empty():
			BlockEntities.on_removed(world, dpos, ds)
		Tripwires.on_removed(world, dpos, ds, false)


static func _move_blocks(world, mv: Array, dir: Vector3i, extending: bool, t: int, ms: int) -> void:
	var states := {}
	var bes := {}
	for q in mv:
		states[q] = world.state_at(q.x, q.y, q.z)
		bes[q] = BlockEntities.take(world, q)
	for q in mv:
		if not states.has(q - dir):
			world.set_block(q.x, q.y, q.z, 0)
			BlockUpdates.schedule_neighbors(world, q)
	for q in mv:
		_add(world, q + dir, states[q], dir, extending, false, t, bes[q], ms)


static func _add(world, pos: Vector3i, state: int, dir: Vector3i, extending: bool, source: bool, t: int, be: Dictionary, ms: int) -> void:
	var old: Move = moving.get(pos)
	if old != null:
		_free_node(old)
	var m := Move.new()
	m.pos = pos
	m.state = state
	m.dir = dir
	m.extending = extending
	m.source = source
	m.start = t
	m.be = be
	m.t0_ms = Time.get_ticks_msec()
	moving[pos] = m
	world.set_block(pos.x, pos.y, pos.z, ms if ms > 0 else state)
	var cmv = world.get("cm")
	var ep = cmv.get("block_epoch") if cmv != null else null
	m.epoch0 = int(ep) if ep != null else 0
	var d := {"id": "piston", "state": Res.blocks.state_string(state), "dir": [dir.x, dir.y, dir.z], "ext": extending, "src": source}
	if not be.is_empty():
		d["be"] = be
	BlockEntities.set_data(world, pos, d)
	BlockUpdates.schedule(world, pos, 2)


## The move's block takes its cell (Java PistonMovingBlockEntity.tick at progress >= 1 / finalTick).
static func _finish(world, m: Move) -> void:
	if moving.get(m.pos) == m:
		moving.erase(m.pos)
	var b := Res.blocks
	var cur: int = world.state_at(m.pos.x, m.pos.y, m.pos.z)
	if cur > 0 and b.name_of(cur) == "moving_piston":
		var st := m.state
		if b.get_prop(st, "waterlogged") == "true":
			st = b.with_prop(st, "waterlogged", "false")
		BlockEntities.take(world, m.pos)
		world.set_block(m.pos.x, m.pos.y, m.pos.z, st)
		if not m.be.is_empty():
			BlockEntities.set_data(world, m.pos, m.be)
		BlockUpdates.schedule_neighbors(world, m.pos)
		if Redstone.kind(st) == 0 and Redstone._relevance(st) == 0 and b.name_of(st) != "piston_head":
			BlockUpdates.schedule(world, m.pos, 1)   # its own survival / falling check (Java updateOrDestroy)
	var cmv = world.get("cm")
	var ep = cmv.get("block_epoch") if cmv != null else null
	m.done_epoch = int(ep) if ep != null else 0
	m.done_ms = Time.get_ticks_msec()
	if m.node != null:
		_ghosts.append(m)


## A moving cell's scheduled tick: a live move ends in tick(); one restored from disk ends now from its block entity.
static func scheduled(world, p: Vector3i) -> bool:
	if moving.has(p):
		return true
	var d := BlockEntities.get_data(world, p)
	if str(d.get("id", "")) != "piston":
		return true
	var st := Res.blocks.parse_state(str(d.get("state", "")))
	var m := Move.new()
	m.pos = p
	m.state = maxi(st, 0)
	var dv: Array = d.get("dir", [0, 0, 0])
	m.dir = Vector3i(int(dv[0]), int(dv[1]), int(dv[2]))
	m.extending = bool(d.get("ext", true))
	m.source = bool(d.get("src", false))
	m.be = d.get("be", {})
	_finish(world, m)
	return true


## Finishes every move now (before a save).
static func finish_all(world) -> void:
	var lst: Array = moving.values()
	for m in lst:
		if moving.get(m.pos) == m:
			_finish(world, m)


# ------------------------------------------------------------------ head + base = one block

## The extended piston a head belongs to (the fitting base behind it, Java PistonHeadBlock.isFittingBase), or NONE.
static func head_base(world, h: Vector3i, hs: int) -> Vector3i:
	var b := Res.blocks
	var p: Vector3i = h - (Redstone.H.get(b.get_prop(hs, "facing"), Vector3i.ZERO) as Vector3i)
	var ps: int = world.state_at(p.x, p.y, p.z)
	if ps > 0 and b.get_prop(ps, "extended") == "true" and b.get_prop(ps, "facing") == b.get_prop(hs, "facing") \
			and b.name_of(ps) == ("sticky_piston" if b.get_prop(hs, "type") == "sticky" else "piston"):
		return p
	return Redstone.NONE


## The head was broken: its piston breaks too (Java destroyBlock: drops in survival, effects; creative: no drop).
static func head_broken(world, h: Vector3i, hs: int) -> void:
	var p := head_base(world, h, hs)
	if p == Redstone.NONE:
		return
	var ps: int = world.state_at(p.x, p.y, p.z)
	world.set_block(p.x, p.y, p.z, 0)
	var pl = world.get("player")
	var creative: bool = pl != null and pl.is_creative()
	if not creative and world.gamerule("doTileDrops", true):
		for s in Loot.block_drops(ps, null, world, p):
			world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.25, 0.5), s)
	if world.entities.has_method("spawn_block_particles"):
		world.entities.spawn_block_particles(p, ps)
	BlockProperties.play_block_sound(ps, "break", Vector3(p) + Vector3(0.5, 0.5, 0.5))
	BlockUpdates.schedule_neighbors(world, p)
	Redstone.on_changed(world, p)


## The extended base was broken: the head goes with it (no drop; Java: the head can no longer survive).
static func base_broken(world, p: Vector3i, ps: int) -> void:
	var b := Res.blocks
	var h := p + Redstone._dir(ps)
	var hs: int = world.state_at(h.x, h.y, h.z)
	if hs > 0 and b.name_of(hs) == "piston_head" and b.get_prop(hs, "facing") == b.get_prop(ps, "facing"):
		world.set_block(h.x, h.y, h.z, 0)
		BlockUpdates.schedule_neighbors(world, h)


# ------------------------------------------------------------------ entities

const _NO_PUSH := ["frame", "painting", "bobber", "lead_knot", "marker"]


static func _push_entities(world, m: Move, age: int) -> void:
	var b := Res.blocks
	var cst := m.state
	if m.source and not m.extending:
		return
	if cst <= 0 or (b.st_flags[cst] & BlockRegistry.F_COLLIDE) == 0:
		return
	var boxes := b.get_shape(cst)
	if boxes.is_empty():
		return
	var d := 0.5
	var dv := Vector3(m.dir)
	var org := Vector3(m.pos) - dv * (1.0 - float(age) * 0.5)
	var slabs: Array = []   # Java PistonMath.getMovementArea of each box: its leading face swept by d
	for i in range(0, boxes.size(), 6):
		var mn := org + Vector3(boxes[i], boxes[i + 1], boxes[i + 2])
		var mx := org + Vector3(boxes[i + 3], boxes[i + 4], boxes[i + 5])
		var smn := mn
		var smx := mx
		if dv.x > 0:
			smn.x = mx.x
			smx.x = mx.x + d
		elif dv.x < 0:
			smx.x = mn.x
			smn.x = mn.x - d
		elif dv.y > 0:
			smn.y = mx.y
			smx.y = mx.y + d
		elif dv.y < 0:
			smx.y = mn.y
			smn.y = mn.y - d
		elif dv.z > 0:
			smn.z = mx.z
			smx.z = mx.z + d
		else:
			smx.z = mn.z
			smn.z = mn.z - d
		slabs.append([smn, smx])
	var slime := b.name_of(cst) == "slime_block"
	var gs := Callable(world, "state_at")
	var pl = world.get("player")
	if pl != null and not pl.dead and not pl.is_spectator():
		var e2 := _push_amount(slabs, dv, pl.aabb_min(), pl.aabb_max(), d)
		if e2 > 0.0:
			var r := Collision.move(pl.aabb_min(), pl.aabb_max(), dv * e2, gs, b, 0.0, false)
			pl.pos += r["motion"]
			if slime:
				pl.vel = _launch(pl.vel, m.dir)
	var em = world.get("entities")
	if em == null or em.get("ents") == null:
		return
	for e in em.ents:
		if e.dead or e.kind in _NO_PUSH:
			continue
		var hw: float = e.w * 0.5
		var emn := Vector3(e.pos.x - hw, e.pos.y, e.pos.z - hw)
		var emx := Vector3(e.pos.x + hw, e.pos.y + e.h, e.pos.z + hw)
		var e3 := _push_amount(slabs, dv, emn, emx, d)
		if e3 > 0.0:
			var r2 := Collision.move(emn, emx, dv * e3, gs, b, 0.0, false)
			e.pos += r2["motion"]
			if slime:
				e.vel = _launch(e.vel, m.dir)


## Java PistonMovingBlockEntity.getMovement over the boxes the entity touches: min(movement, d) + 0.01, 0 if none.
static func _push_amount(slabs: Array, dv: Vector3, emn: Vector3, emx: Vector3, d: float) -> float:
	var best := 0.0
	for s in slabs:
		var amn: Vector3 = s[0]
		var amx: Vector3 = s[1]
		if amn.x < emx.x and amx.x > emn.x and amn.y < emx.y and amx.y > emn.y and amn.z < emx.z and amx.z > emn.z:
			var mvd := 0.0
			if dv.x > 0:
				mvd = amx.x - emn.x
			elif dv.x < 0:
				mvd = emx.x - amn.x
			elif dv.y > 0:
				mvd = amx.y - emn.y
			elif dv.y < 0:
				mvd = emx.y - amn.y
			elif dv.z > 0:
				mvd = amx.z - emn.z
			else:
				mvd = emx.z - amn.z
			best = maxf(best, mvd)
	return minf(best, d) + 0.01 if best > 0.0 else 0.0


## Slime block push: the velocity along the push axis becomes the push direction's step (1 block / tick).
static func _launch(v: Vector3, dir: Vector3i) -> Vector3:
	if dir.x != 0:
		v.x = float(dir.x)
	elif dir.y != 0:
		v.y = float(dir.y)
	else:
		v.z = float(dir.z)
	return v


# ------------------------------------------------------------------ rendering

## Per frame: moving blocks at their interpolated positions (Java getProgress(partialTick) = lerp(progressO, progress)).
static func render(world, alpha: float) -> void:
	if moving.is_empty() and _ghosts.is_empty():
		return
	var t := int(world.game_time)
	var now := Time.get_ticks_msec()
	var cm = world.cm
	for p in moving:
		var m: Move = moving[p]
		if m.node == null:
			_make_node(world, m)
		if not m.shown:
			# drawn once the terrain mesh no longer shows the blocks where they started (both at once z-fought)
			var fr: Vector3i = m.pos - m.dir
			m.shown = now - m.t0_ms > 150 or (cm.mesh_caught_up(m.pos.x, m.pos.y, m.pos.z, m.epoch0) and cm.mesh_caught_up(fr.x, fr.y, fr.z, m.epoch0))
		m.node.visible = m.shown
		var hold := _held(world)
		_place(world, m, hold if hold >= 0.0 else clampf((float(t - m.start) + alpha) * 0.5, 0.0, 1.0))
	var i := 0
	while i < _ghosts.size():
		var g: Move = _ghosts[i]
		if g.node == null or now - g.done_ms > 400 or cm.mesh_caught_up(g.pos.x, g.pos.y, g.pos.z, g.done_epoch):
			_free_node(g)
			_ghosts.remove_at(i)
		else:
			_place(world, g, 1.0)
			i += 1


static func _mesh(st: int) -> ArrayMesh:
	if not _mesh_cache.has(st):
		_mesh_cache[st] = EntityRenderer.block_item_mesh(st) if st > 0 else null
	return _mesh_cache[st]


static func _mi(parent: Node3D, st: int) -> MeshInstance3D:
	var mesh := _mesh(st)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


static func _make_node(world, m: Move) -> void:
	var b := Res.blocks
	m.node = Node3D.new()
	m.node.visible = false
	world.add_child(m.node)
	if not m.source:
		_mi(m.node, m.state)
	else:
		var hs: int = m.state
		var holder := m.node
		if not m.extending:
			# the base stays (extended look) while the head slides back into it
			_mi(m.node, b.with_prop(m.state, "extended", "true"))
			m.head = Node3D.new()
			m.node.add_child(m.head)
			holder = m.head
			hs = b.with_prop(b.with_prop(b.default_state("piston_head"), "facing", b.get_prop(m.state, "facing")), "type", "sticky" if b.name_of(m.state) == "sticky_piston" else "normal")
		m.long_mi = _mi(holder, b.with_prop(hs, "short", "false"))
		m.short_mi = _mi(holder, b.with_prop(hs, "short", "true"))
	_relight(world, m)


static func _place(world, m: Move, prog: float) -> void:
	if m.node == null:
		return
	var off := -Vector3(m.dir) * (1.0 - prog)
	var base := Vector3(m.pos) + Vector3(0.5, 0.0, 0.5)
	var short := false
	if m.source and not m.extending:
		m.node.position = world.vis(base)
		if m.head != null:
			m.head.position = off
		short = prog >= 0.5
	else:
		m.node.position = world.vis(base + off)
		short = prog <= 0.5
	if m.long_mi != null and m.short_mi != null:
		m.long_mi.visible = not short
		m.short_mi.visible = short
	if Engine.get_process_frames() % 4 == 0:
		_relight(world, m)


static func _relight(world, m: Move) -> void:
	var l: int = world.cm.get_light(m.pos.x, m.pos.y, m.pos.z)
	if l == 0:
		for dd in Redstone.DIRS:
			var q: Vector3i = m.pos + dd
			l = maxi(l, int(world.cm.get_light(q.x, q.y, q.z)))
	var lv := Vector2((l >> 4) / 15.0, (l & 15) / 15.0)
	_light_all(m.node, lv)


static func _light_all(n: Node, lv: Vector2) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).set_instance_shader_parameter("light", lv)
		else:
			_light_all(c, lv)


static func _free_node(m: Move) -> void:
	if m.node != null and is_instance_valid(m.node):
		m.node.queue_free()
	m.node = null
