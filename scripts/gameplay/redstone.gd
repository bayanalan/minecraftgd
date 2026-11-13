## Redstone — functional (not update-order-exact) redstone: sources (lever, buttons, pressure plates, redstone
## block/torch, daylight detector, target), directional components (repeater: delay 1-4, locking; comparator:
## compare/subtract, container fullness; observer: 2-tick pulse on observed change), dust networks with 15-level
## decay, consumers (lamps, doors/trapdoors/fence gates, TNT, note blocks, torch inversion, pistons + sticky
## pistons pushing up to 12 blocks, dispensers/droppers, hoppers lock, powered/activator rails).
## Updates: immediate on_changed(world, pos), or request(world, pos) queued and flushed once per tick.
## Parity: Java quasi-connectivity/update order NOT matched (see docs/PARITY_MATRIX.md).
class_name Redstone

const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
const H := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0), "up": Vector3i(0, 1, 0), "down": Vector3i(0, -1, 0)}
const PUSH_LIMIT := 12
static var _depth := 0
static var _pending: Dictionary = {}


## Per-state relevance (built once): 1 = redstone wire, 2 = reacts in _update_consumer. Everything else is inert
## for on_changed, which lets the per-tick flush skip the (pure) power computation for ordinary blocks.
static var _rel := PackedByteArray()


static func _relevance(st: int) -> int:
	if st <= 0:
		return 0
	if _rel.is_empty():
		var b := Res.blocks
		var n_states := b.st_block.size()
		_rel.resize(n_states)
		for s in range(1, n_states):
			_rel[s] = _relevance_of(s)
	return _rel[st] if st < _rel.size() else _relevance_of(st)


static func _relevance_of(st: int) -> int:
	var b := Res.blocks
	var n := b.name_of(st)
	if n == "redstone_wire":
		return 1
	if n in ["repeater", "comparator", "piston", "sticky_piston", "dispenser", "dropper", "hopper", "powered_rail", "activator_rail",
			"redstone_lamp", "tnt", "note_block", "redstone_torch", "redstone_wall_torch"]:
		return 2
	if (n.ends_with("_door") or n.ends_with("_trapdoor") or n.ends_with("_fence_gate")) and b.has_prop(st, "powered"):
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


## Non-directional source power of the block at p (0..15).
static func source_power(world, p: Vector3i) -> int:
	var st := _state(world, p)
	if st <= 0:
		return 0
	var b := Res.blocks
	var n := b.name_of(st)
	if n == "redstone_block":
		return 15
	if (n == "lever" or n.ends_with("_button") or n.ends_with("_pressure_plate") or n == "tripwire_hook" or n == "detector_rail") and b.get_prop(st, "powered") == "true":
		return 15
	if (n == "redstone_torch" or n == "redstone_wall_torch") and b.get_prop(st, "lit") == "true":
		return 15
	if n == "sculk_sensor" or n == "calibrated_sculk_sensor":
		return Sculk.power_at(p)
	if n == "daylight_detector" or n == "target" or n.ends_with("weighted_pressure_plate"):
		return int(b.get_prop(st, "power"))
	return 0


## Power emitted by the block at src into the adjacent block at dst (directional for diodes/observers).
static func emitted(world, src: Vector3i, dst: Vector3i) -> int:
	var st := _state(world, src)
	if st <= 0:
		return 0
	var n := _name(st)
	match n:
		"repeater":
			return 15 if Res.blocks.get_prop(st, "powered") == "true" and src - _dir(st) == dst else 0
		"comparator":
			return comparator_out(world, src, st) if src - _dir(st) == dst else 0
		"observer":
			return 15 if Res.blocks.get_prop(st, "powered") == "true" and src - _dir(st) == dst else 0
		"redstone_wire":
			return int(Res.blocks.get_prop(st, "power"))
	return source_power(world, src)


## Strong power reaching a solid block (sources attached to / diodes pointing into it).
static func strong_into(world, solid: Vector3i, exclude: Vector3i) -> int:
	var best := 0
	for d in DIRS:
		var s: Vector3i = solid + d
		if s == exclude:
			continue
		var st := _state(world, s)
		if st <= 0 or _name(st) == "redstone_wire":
			continue
		best = maxi(best, emitted(world, s, solid))
	return best


## Total input power received by the block at p (direct emitters + strongly powered solid neighbours).
static func power_at(world, p: Vector3i) -> int:
	var best := source_power(world, p)
	for d in DIRS:
		var q: Vector3i = p + d
		best = maxi(best, emitted(world, q, p))
		var st := _state(world, q)
		if st > 0 and (Res.blocks.st_flags[st] & BlockRegistry.F_OPAQUE) != 0:
			best = maxi(best, strong_into(world, q, p))
	return best


static func container_signal(world, p: Vector3i) -> int:
	var d: Dictionary = BlockEntities.get_data(world, p)
	if d.is_empty() or not d.has("items"):
		return 0
	var items: Array = d["items"]
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


## Java ComparatorBlock: rear input (incl. container fullness) vs. the stronger side input.
static func comparator_out(world, p: Vector3i, st: int) -> int:
	var f := _dir(st)
	var rear := p + f
	var rs := _state(world, rear)
	var r := 0
	if rs > 0 and not BlockEntities.get_data(world, rear).is_empty() and BlockEntities.get_data(world, rear).has("items"):
		r = container_signal(world, rear)
	else:
		r = emitted(world, rear, p)
		if rs > 0 and (Res.blocks.st_flags[rs] & BlockRegistry.F_OPAQUE) != 0:
			r = maxi(r, strong_into(world, rear, p))
	var side := 0
	for s in [Vector3i(f.z, 0, -f.x), Vector3i(-f.z, 0, f.x)]:
		var sp: Vector3i = p + s
		var sn := _name(_state(world, sp))
		if sn == "redstone_wire" or sn == "repeater" or sn == "comparator" or sn == "redstone_block":
			side = maxi(side, emitted(world, sp, p))
	if Res.blocks.get_prop(st, "mode") == "subtract":
		return maxi(r - side, 0)
	return r if r >= side else 0


# ------------------------------------------------------------------ updates

static func request(world, p: Vector3i) -> void:
	_pending[p] = true


## Called once per game tick by the world.
static func flush(world) -> void:
	if _pending.is_empty():
		return
	var lst: Array = _pending.keys()
	_pending.clear()
	for p in lst.slice(0, 256):
		on_changed(world, p)


## Observer hook: a block at p changed -> observers watching p pulse after 2 ticks.
static func notify_observers(world, p: Vector3i) -> void:
	for d in DIRS:
		var q: Vector3i = p + d
		var st := _state(world, q)
		if st > 0 and _name(st) == "observer" and q + _dir(st) == p and Res.blocks.get_prop(st, "powered") != "true":
			BlockUpdates.schedule(world, q, 2)


static func on_changed(world, p: Vector3i) -> void:
	if _depth > 8:
		return
	_depth += 1
	_update_wires(world, p)
	for d in DIRS + [Vector3i.ZERO]:
		_update_consumer(world, p + d)
		for d2 in DIRS:
			_update_consumer(world, p + d + d2)
	_depth -= 1


static func _update_wires(world, p: Vector3i) -> void:
	var b := Res.blocks
	var net := {}
	var q: Array = []
	for d in DIRS + [Vector3i.ZERO]:
		var s: Vector3i = p + d
		var st := _state(world, s)
		if _relevance(st) == 1:
			net[s] = true
			q.append(s)
	while not q.is_empty() and net.size() < 4096:
		var c: Vector3i = q.pop_back()
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			for dy in [0, 1, -1]:
				var n: Vector3i = c + d + Vector3i(0, dy, 0)
				if net.has(n):
					continue
				var st := _state(world, n)
				if st > 0 and b.name_of(st) == "redstone_wire":
					net[n] = true
					q.append(n)
	if net.is_empty():
		return
	var power := {}
	var bq: Array = []
	for w in net:
		var sp := 0
		for d in DIRS:
			var nb: Vector3i = w + d
			var nst := _state(world, nb)
			if nst > 0 and b.name_of(nst) != "redstone_wire":
				sp = maxi(sp, emitted(world, nb, w))
				if (b.st_flags[nst] & BlockRegistry.F_OPAQUE) != 0:
					sp = maxi(sp, strong_into(world, nb, w))
		power[w] = sp
		if sp > 0:
			bq.append(w)
	while not bq.is_empty():
		var c: Vector3i = bq.pop_front()
		var v: int = power[c] - 1
		if v <= 0:
			continue
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			for dy in [0, 1, -1]:
				var n: Vector3i = c + d + Vector3i(0, dy, 0)
				if net.has(n) and int(power[n]) < v:
					power[n] = v
					bq.append(n)
	var changed: Array = []
	for w in net:
		var st := _state(world, w)
		var ns := b.with_prop(st, "power", str(power[w]))
		if ns != st:
			world.set_block(w.x, w.y, w.z, ns, false)
			changed.append(w)
	# consumers next to any wire whose level changed (and behind solid blocks the wire points into)
	var seen := {}
	for w in changed:
		for d in DIRS:
			var c: Vector3i = w + d
			if seen.has(c):
				continue
			seen[c] = true
			var cs := _state(world, c)
			if cs > 0 and b.name_of(cs) != "redstone_wire":
				_update_consumer(world, c)
				if (b.st_flags[cs] & BlockRegistry.F_OPAQUE) != 0:
					for d2 in DIRS:
						if not seen.has(c + d2):
							_update_consumer(world, c + d2)


static func _powered_any(world, p: Vector3i) -> bool:
	if power_at(world, p) > 0:
		return true
	for d in DIRS:
		var q: Vector3i = p + d
		var qs := _state(world, q)
		if qs > 0 and (Res.blocks.st_flags[qs] & BlockRegistry.F_OPAQUE) and strong_into(world, q, p) > 0:
			return true
	return false


static func _diode_input(world, p: Vector3i, st: int) -> int:
	var rear := p + _dir(st)
	var r := emitted(world, rear, p)
	var rs := _state(world, rear)
	if rs > 0 and (Res.blocks.st_flags[rs] & BlockRegistry.F_OPAQUE) != 0:
		r = maxi(r, strong_into(world, rear, p))
	return r


static func _repeater_locked(world, p: Vector3i, st: int) -> bool:
	var f := _dir(st)
	for s in [Vector3i(f.z, 0, -f.x), Vector3i(-f.z, 0, f.x)]:
		var sp: Vector3i = p + s
		var ss := _state(world, sp)
		var sn := _name(ss)
		if (sn == "repeater" or sn == "comparator") and emitted(world, sp, p) > 0:
			return true
	return false


static func _update_consumer(world, p: Vector3i) -> void:
	var b := Res.blocks
	var st := _state(world, p)
	if (_relevance(st) & 2) == 0:
		return
	var n := b.name_of(st)
	match n:
		"repeater":
			var locked := _repeater_locked(world, p, st)
			if b.get_prop(st, "locked") != ("true" if locked else "false"):
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "locked", "true" if locked else "false"), false)
				st = _state(world, p)
			if not locked and (_diode_input(world, p, st) > 0) != (b.get_prop(st, "powered") == "true"):
				BlockUpdates.schedule(world, p, int(b.get_prop(st, "delay")) * 2)
			return
		"comparator":
			var out := comparator_out(world, p, st)
			if (out > 0) != (b.get_prop(st, "powered") == "true"):
				BlockUpdates.schedule(world, p, 2)
			return
		"piston", "sticky_piston":
			var pw := _powered_any(world, p)
			if pw != (b.get_prop(st, "extended") == "true"):
				BlockUpdates.schedule(world, p, 1)
			return
		"dispenser", "dropper":
			var pw2 := _powered_any(world, p)
			var was := b.get_prop(st, "triggered") == "true"
			if pw2 and not was:
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "triggered", "true"), false)
				BlockUpdates.schedule(world, p, 4)
			elif not pw2 and was:
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "triggered", "false"), false)
			return
		"hopper":
			var en := not _powered_any(world, p)
			if (b.get_prop(st, "enabled") == "true") != en:
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "enabled", "true" if en else "false"), false)
			return
		"powered_rail", "activator_rail":
			var pw3 := _powered_any(world, p)
			if (b.get_prop(st, "powered") == "true") != pw3:
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "powered", "true" if pw3 else "false"), false)
			return
	var powered := _powered_any(world, p)
	if n == "redstone_lamp":
		var lit := b.get_prop(st, "lit") == "true"
		if lit != powered:
			world.set_block(p.x, p.y, p.z, b.with_prop(st, "lit", "true" if powered else "false"), false)
	elif (n.ends_with("_door") or n.ends_with("_trapdoor") or n.ends_with("_fence_gate")) and b.has_prop(st, "powered"):
		if (b.get_prop(st, "powered") == "true") != powered:
			var ns := b.with_prop(b.with_prop(st, "powered", "true" if powered else "false"), "open", "true" if powered else "false")
			world.set_block(p.x, p.y, p.z, ns, false)
			if n.ends_with("_door"):
				var o := p + (Vector3i(0, 1, 0) if b.get_prop(st, "half") == "lower" else Vector3i(0, -1, 0))
				var os := _state(world, o)
				if os > 0 and b.name_of(os) == n:
					world.set_block(o.x, o.y, o.z, b.with_prop(b.with_prop(os, "powered", "true" if powered else "false"), "open", "true" if powered else "false"), false)
	elif n == "tnt" and powered:
		world.set_block(p.x, p.y, p.z, 0)
		MiscEntities.spawn_tnt(world.entities, Vector3(p) + Vector3(0.5, 0.0, 0.5), 80)
	elif CommandBlocks.is_command_block(n):
		CommandBlocks.on_power(world, p, powered)
	elif n == "note_block":
		var was2 := b.get_prop(st, "powered") == "true"
		if was2 != powered:
			world.set_block(p.x, p.y, p.z, b.with_prop(st, "powered", "true" if powered else "false"), false)
			if powered:
				BlockEntities.play_note(world, p)
	elif n == "redstone_torch" or n == "redstone_wall_torch":
		var attached := p + Vector3i(0, -1, 0)
		if n == "redstone_wall_torch":
			attached = p - _dir(st)
		var in_p := false
		for d in DIRS:
			var a2: Vector3i = attached + d
			if a2 != p and emitted(world, a2, attached) > 0:
				in_p = true
		var lit2 := b.get_prop(st, "lit") == "true"
		if lit2 == in_p:
			world.set_block(p.x, p.y, p.z, b.with_prop(st, "lit", "false" if in_p else "true"), false)
			on_changed(world, p)


## Scheduled tick for redstone components (called from BlockUpdates._scheduled). Returns true if handled.
static func scheduled(world, p: Vector3i, st: int) -> bool:
	var b := Res.blocks
	var n := b.name_of(st)
	match n:
		"repeater":
			if _repeater_locked(world, p, st):
				return true
			var want := _diode_input(world, p, st) > 0
			if want != (b.get_prop(st, "powered") == "true"):
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "powered", "true" if want else "false"), false)
				_after_output(world, p, st)
			return true
		"comparator":
			var on := comparator_out(world, p, st) > 0
			world.set_block(p.x, p.y, p.z, b.with_prop(st, "powered", "true" if on else "false"), false)
			_after_output(world, p, st)
			return true
		"observer":
			var pw := b.get_prop(st, "powered") == "true"
			world.set_block(p.x, p.y, p.z, b.with_prop(st, "powered", "false" if pw else "true"), false)
			if not pw:
				BlockUpdates.schedule(world, p, 2)
			_after_output(world, p, st)
			return true
		"piston", "sticky_piston":
			var want2 := _powered_any(world, p)
			if want2 and b.get_prop(st, "extended") != "true":
				_extend(world, p, st)
			elif not want2 and b.get_prop(st, "extended") == "true":
				_retract(world, p, st, n == "sticky_piston")
			return true
		"dispenser", "dropper":
			_dispense(world, p, st, n == "dropper")
			return true
	return false


static func _after_output(world, p: Vector3i, st: int) -> void:
	var out := p - _dir(st)
	on_changed(world, out)
	var os := _state(world, out)
	if os > 0 and (Res.blocks.st_flags[os] & BlockRegistry.F_OPAQUE) != 0:
		for d in DIRS:
			on_changed(world, out + d)


# ------------------------------------------------------------------ pistons

static func _movable(st: int) -> int:
	# 0 = blocks the piston, 1 = movable, 2 = destroyed when pushed
	if st <= 0:
		return 1
	var b := Res.blocks
	var n := b.name_of(st)
	if n in ["obsidian", "crying_obsidian", "bedrock", "end_portal_frame", "end_portal", "nether_portal", "barrier", "end_gateway", "respawn_anchor", "reinforced_deepslate", "piston_head", "moving_piston", "enchanting_table", "ender_chest", "spawner", "beacon", "jukebox", "lodestone"]:
		return 0
	if (n == "piston" or n == "sticky_piston") and b.get_prop(st, "extended") == "true":
		return 0
	if n.ends_with("chest") or n.ends_with("shulker_box") or n in ["furnace", "blast_furnace", "smoker", "barrel", "hopper", "dispenser", "dropper", "lectern", "beehive", "bee_nest"]:
		return 0   # block entities are immovable
	if (b.st_flags[st] & (BlockRegistry.F_REPLACEABLE | BlockRegistry.F_LIQUID)) != 0 or (b.st_flags[st] & BlockRegistry.F_COLLIDE) == 0:
		return 2
	if b.hardness[b.st_block[st]] < 0:
		return 0
	return 1


static func _extend(world, p: Vector3i, st: int) -> void:
	var b := Res.blocks
	var f := _dir(st)
	var line: Array = []
	var q := p + f
	var destroy := Vector3i(0, -99999, 0)
	while true:
		var qs := _state(world, q)
		if qs < 0:
			return
		var m := _movable(qs)
		if qs == 0:
			break
		if m == 0:
			return
		if m == 2:
			destroy = q
			break
		line.append([q, qs])
		if line.size() > PUSH_LIMIT:
			return
		q += f
	if destroy.y != -99999:
		var ds := _state(world, destroy)
		world.set_block(destroy.x, destroy.y, destroy.z, 0)
		if world.gamerule("doTileDrops", true):
			for s in Loot.block_drops(ds, null, world, destroy):
				world.entities.spawn_item(Vector3(destroy) + Vector3(0.5, 0.5, 0.5), s)
	for i in range(line.size() - 1, -1, -1):
		var e: Array = line[i]
		var to: Vector3i = e[0] + f
		world.set_block(to.x, to.y, to.z, e[1])
	world.set_block(p.x, p.y, p.z, b.with_prop(st, "extended", "true"), false)
	var head := b.default_state("piston_head")
	head = b.with_prop(head, "facing", b.get_prop(st, "facing"))
	head = b.with_prop(head, "type", "sticky" if b.name_of(st) == "sticky_piston" else "normal")
	var h := p + f
	world.set_block(h.x, h.y, h.z, head)
	Audio.play("block.piston.extend", Vector3(p), "Blocks")
	for e in line:
		request(world, e[0] + f)
	request(world, h)


static func _retract(world, p: Vector3i, st: int, sticky: bool) -> void:
	var b := Res.blocks
	var f := _dir(st)
	var h := p + f
	if _name(_state(world, h)) == "piston_head":
		world.set_block(h.x, h.y, h.z, 0)
	world.set_block(p.x, p.y, p.z, b.with_prop(st, "extended", "false"), false)
	if sticky:
		var front := h + f
		var fs := _state(world, front)
		if fs > 0 and _movable(fs) == 1:
			world.set_block(front.x, front.y, front.z, 0)
			world.set_block(h.x, h.y, h.z, fs)
			request(world, front)
	Audio.play("block.piston.contract", Vector3(p), "Blocks")
	request(world, h)


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
		Audio.play("block.dispenser.fail", Vector3(p), "Blocks")
		return
	var k: int = slots[world.rng.randi_range(0, slots.size() - 1)]
	var s := ItemStack.from_dict(items[k])
	var f := _dir(st)
	var front := p + f
	var out := Vector3(p) + Vector3(0.5, 0.5, 0.5) + Vector3(f) * 0.7
	var nm := s.name()
	var used := true
	if not dropper and nm in ["arrow", "snowball", "egg", "fire_charge"]:
		world.entities.spawn_projectile("small_fireball" if nm == "fire_charge" else nm, out, Vector3(f) * 1.1 + Vector3(0, 0.1, 0), null)
	elif not dropper and (nm == "water_bucket" or nm == "lava_bucket") and _state(world, front) == 0:
		world.set_block(front.x, front.y, front.z, Res.blocks.WATER if nm == "water_bucket" else Res.blocks.LAVA)
		BlockUpdates.schedule(world, front, 1)
		items[k] = ItemStack.named("bucket", 1).to_dict()
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
	Audio.play("block.dispenser.dispense", Vector3(p), "Blocks")
