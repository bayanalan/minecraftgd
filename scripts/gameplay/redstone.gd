## Redstone — functional (not update-order-exact) redstone: sources (lever, buttons, pressure plates, redstone
## block/torch, daylight detector, target, tripwire hooks, detector rails, playing jukeboxes, lectern page pulses),
## directional components (repeater: delay 1-4, locking; comparator: compare/subtract, container fullness; observer:
## 2-tick pulse on observed change), dust networks with 15-level decay (dust weakly powers the block under it and the
## blocks it points into), consumers (lamps, doors/trapdoors/fence gates, TNT, note blocks, bells, torch inversion,
## pistons + sticky pistons moving up to 12 blocks incl. slime / honey structures, dispensers/droppers, hoppers lock,
## powered/activator rails passing power 8 rails along the track).
## Updates: immediate on_changed(world, pos), or request(world, pos) queued and flushed once per tick.
## Parity: Java quasi-connectivity/update order NOT matched (see docs/PARITY_MATRIX.md).
class_name Redstone

const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
const H := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0), "up": Vector3i(0, 1, 0), "down": Vector3i(0, -1, 0)}
const PUSH_LIMIT := 12
const NONE := Vector3i(0, -99999, 0)
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
	if n in ["repeater", "comparator", "piston", "sticky_piston", "dispenser", "dropper", "crafter", "hopper", "powered_rail", "activator_rail",
			"redstone_lamp", "tnt", "note_block", "redstone_torch", "redstone_wall_torch", "bell"]:
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
	if n.ends_with("lightning_rod") and b.get_prop(st, "powered") == "true":
		return 15   # wiki Lightning Rod: 15 for 8 ticks when struck
	if n == "sculk_sensor" or n == "calibrated_sculk_sensor":
		return Sculk.power_at(p)
	if n == "daylight_detector" or n == "target" or n.ends_with("weighted_pressure_plate"):
		return int(b.get_prop(st, "power"))
	if n == "lectern" and b.get_prop(st, "powered") == "true":
		return 15   # wiki Lectern: a full-strength pulse of 2 game ticks when a page is turned
	if n == "jukebox" and BlockEntities.jukebox_playing(world, p):
		return 15   # wiki Jukebox: 15 while a disc's music plays (ends with the track)
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


## Total input power received by the block at p (direct emitters + powered solid neighbours: strongly powered, or
## weakly powered by dust - a weakly powered block still activates the components next to it).
static func power_at(world, p: Vector3i) -> int:
	var best := source_power(world, p)
	for d in DIRS:
		var q: Vector3i = p + d
		best = maxi(best, emitted(world, q, p))
		var st := _state(world, q)
		if st > 0 and (Res.blocks.st_flags[st] & BlockRegistry.F_OPAQUE) != 0:
			best = maxi(best, maxi(strong_into(world, q, p), dust_into(world, q)))
	return best


const _HSIDE := {Vector3i(1, 0, 0): "west", Vector3i(-1, 0, 0): "east", Vector3i(0, 0, 1): "north", Vector3i(0, 0, -1): "south"}


## Weak power redstone dust gives a solid block: dust on top of it, or dust beside it that connects toward it (Java
## RedStoneWireBlock.getSignal: up always, a side only when that side's connection is set; never down).
static func dust_into(world, solid: Vector3i) -> int:
	var b := Res.blocks
	var best := 0
	var up := _state(world, solid + Vector3i(0, 1, 0))
	if up > 0 and _relevance(up) == 1:
		best = int(b.get_prop(up, "power"))
	for d in _HSIDE:
		var w: Vector3i = solid + d
		var ws := _state(world, w)
		if ws > 0 and _relevance(ws) == 1 and b.get_prop(ws, _HSIDE[d]) != "none":
			best = maxi(best, int(b.get_prop(ws, "power")))
	return best


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


## Java ComparatorBlock: rear input (incl. container fullness) vs. the stronger side input.
static func comparator_out(world, p: Vector3i, st: int) -> int:
	var f := _dir(st)
	var rear := p + f
	var rs := _state(world, rear)
	var r := measure(world, rear, rs, f)
	if r < 0:
		r = emitted(world, rear, p)
		if rs > 0 and (Res.blocks.st_flags[rs] & BlockRegistry.F_OPAQUE) != 0:
			r = maxi(r, maxi(strong_into(world, rear, p), dust_into(world, rear)))
			# wiki: Redstone_Comparator - a measured block may sit behind a conductive block (unless that is powered 15)
			if r < 15:
				var far := rear + f
				var m := measure(world, far, _state(world, far), f)
				if m >= 0:
					r = m
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
	if _depth == 0 and not _rail_done.is_empty():
		_rail_done.clear()
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
		r = maxi(r, maxi(strong_into(world, rear, p), dust_into(world, rear)))
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
			# a strength change also needs the delayed update (Java ComparatorBlock.checkTickOnNeighbor), not only on/off
			var out := comparator_out(world, p, st)
			if (out > 0) != (b.get_prop(st, "powered") == "true") or out != int(_cmp_out.get(p, -1)):
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
		"crafter":
			# CrafterBlock.neighborChanged: a rising edge schedules the craft in 4 ticks; losing power clears both flags
			var pw3 := _powered_any(world, p)
			var was3 := b.get_prop(st, "triggered") == "true"
			if pw3 and not was3:
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "triggered", "true"), false)
				BlockEntities.get_data(world, p)["craft_at"] = int(world.game_time) + 4
				BlockUpdates.schedule(world, p, 4)
			elif not pw3 and was3:
				world.set_block(p.x, p.y, p.z, b.with_prop(b.with_prop(st, "triggered", "false"), "crafting", "false"), false)
			return
		"hopper":
			var en := not _powered_any(world, p)
			if (b.get_prop(st, "enabled") == "true") != en:
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "enabled", "true" if en else "false"), false)
			return
		"powered_rail", "activator_rail":
			_update_rails(world, p, st)
			return
		"bell":
			# Java BellBlock.neighborChanged: a rising signal rings it once (toward its facing)
			var pwb := _powered_any(world, p)
			if (b.get_prop(st, "powered") == "true") != pwb:
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "powered", "true" if pwb else "false"), false)
				if pwb:
					Bells.ring(world, p, Vector3i.ZERO)
			return
	if n == "redstone_torch" or n == "redstone_wall_torch":
		# wiki: Redstone_Torch - a torch changes state 2 game ticks after its input changes
		if (b.get_prop(st, "lit") == "true") == _torch_input(world, p, st):
			BlockUpdates.schedule(world, p, 2)
		return
	var powered := _powered_any(world, p)
	if n == "redstone_lamp":
		# wiki: Redstone_Lamp - lights instantly, turns off 4 game ticks after losing power
		var lit := b.get_prop(st, "lit") == "true"
		if powered and not lit:
			world.set_block(p.x, p.y, p.z, b.with_prop(st, "lit", "true"), false)
		elif not powered and lit:
			BlockUpdates.schedule(world, p, 4)
	elif (n.ends_with("_door") or n.ends_with("_trapdoor") or n.ends_with("_fence_gate")) and b.has_prop(st, "powered"):
		if (b.get_prop(st, "powered") == "true") != powered:
			var ns := b.with_prop(b.with_prop(st, "powered", "true" if powered else "false"), "open", "true" if powered else "false")
			world.set_block(p.x, p.y, p.z, ns, false)
			if n.ends_with("_door"):
				var o := p + (Vector3i(0, 1, 0) if b.get_prop(st, "half") == "lower" else Vector3i(0, -1, 0))
				var os := _state(world, o)
				if os > 0 and b.name_of(os) == n:
					world.set_block(o.x, o.y, o.z, b.with_prop(b.with_prop(os, "powered", "true" if powered else "false"), "open", "true" if powered else "false"), false)
	elif Shelf.is_shelf(n) and b.has_prop(st, "powered"):
		Shelf.on_power(world, p, st, powered)
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


## The block a redstone torch is attached to receives power (the torch then turns off).
static func _torch_input(world, p: Vector3i, st: int) -> bool:
	var attached := p + Vector3i(0, -1, 0)
	if _name(st) == "redstone_wall_torch":
		attached = p - _dir(st)
	for d in DIRS:
		var a2: Vector3i = attached + d
		if a2 != p and emitted(world, a2, attached) > 0:
			return true
	return false


## wiki: Redstone_Torch burnout - forced off 8 times within 60 game ticks it stays off (smoke, fizz at volume 0.5,
## pitch 1.8-3.4) until fewer than eight changes remain in the window; it retries 160 ticks later.
const TORCH_WINDOW := 60
const TORCH_MAX_TOGGLES := 8
const TORCH_RESTART := 160
static var _torch_offs: Dictionary = {}   # Vector3i -> Array of game times the torch was forced off
static var _torch_restart: Dictionary = {}   # Vector3i -> game time a burnt-out torch retries
static var _cmp_out: Dictionary = {}      # Vector3i -> comparator output at its last scheduled update


static func _torch_tick(world, p: Vector3i, st: int) -> void:
	var b := Res.blocks
	var t := int(world.game_time)
	var hist: Array = _torch_offs.get(p, [])
	while not hist.is_empty() and t - int(hist[0]) > TORCH_WINDOW:
		hist.pop_front()
	var lit := b.get_prop(st, "lit") == "true"
	var inp := _torch_input(world, p, st)
	if lit and inp:
		world.set_block(p.x, p.y, p.z, b.with_prop(st, "lit", "false"), false)
		hist.append(t)
		if hist.size() >= TORCH_MAX_TOGGLES:
			Audio.play("block.redstone_torch.burnout", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks", 0.5, 2.6 + (randf() - randf()) * 0.8)
			Particles.emit("smoke", Vector3(p) + Vector3(0.5, 0.7, 0.5))
			_torch_restart[p] = t + TORCH_RESTART
			BlockUpdates.schedule(world, p, TORCH_RESTART)
		on_changed(world, p)
	elif not lit and not inp:
		if hist.size() < TORCH_MAX_TOGGLES:
			_torch_restart.erase(p)
			world.set_block(p.x, p.y, p.z, b.with_prop(st, "lit", "true"), false)
			on_changed(world, p)
		elif _torch_restart.has(p):
			BlockUpdates.schedule(world, p, maxi(1, int(_torch_restart[p]) - t))   # (an earlier update replaced the retry)
	if hist.is_empty():
		_torch_offs.erase(p)
	else:
		_torch_offs[p] = hist


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
			var cv := comparator_out(world, p, st)
			_cmp_out[p] = cv
			world.set_block(p.x, p.y, p.z, b.with_prop(st, "powered", "true" if cv > 0 else "false"), false)
			_after_output(world, p, st)
			return true
		"redstone_lamp":
			if b.get_prop(st, "lit") == "true" and not _powered_any(world, p):
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "lit", "false"), false)
			return true
		"redstone_torch", "redstone_wall_torch":
			_torch_tick(world, p, st)
			return false   # BlockUpdates still runs its support check (torch on a removed block pops off)
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
		"crafter":
			var cd := BlockEntities.get_data(world, p)
			if b.get_prop(st, "crafting") == "true" and int(world.game_time) >= int(cd.get("crafting_until", 0)):
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "crafting", "false"), false)   # CrafterBlockEntity tick: the crafting look ends
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
			if b.get_prop(st, "powered") == "true":
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "powered", "false"), false)
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
		world.set_block(p.x, p.y, p.z, Res.blocks.with_prop(st, "powered", "true"), false)
		on_changed(world, p)
	BlockUpdates.schedule(world, p, 2)
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
		direct[i] = 1 if power_at(world, chain[i][0]) > 0 else 0
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
			world.set_block(q2.x, q2.y, q2.z, b.with_prop(qs2, "powered", "true" if on else "false"), false)


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
	# wiki: Piston (Java "cannot be pushed" lists)
	if n in ["obsidian", "crying_obsidian", "bedrock", "end_portal_frame", "end_portal", "nether_portal", "barrier", "end_gateway", "respawn_anchor", "reinforced_deepslate", "piston_head", "moving_piston", "enchanting_table", "ender_chest", "spawner", "beacon", "jukebox", "lodestone",
			"calibrated_sculk_sensor", "sculk_sensor", "sculk_catalyst", "sculk_shrieker", "creaking_heart", "grindstone", "jigsaw", "light", "structure_block", "trial_spawner", "vault", "potent_sulfur"] or CommandBlocks.is_command_block(n):
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


## Moves a resolved structure one block along dir: breakable blocks drop, block-entity data travels with its block.
static func _apply_move(world, res: Dictionary, dir: Vector3i) -> void:
	for dpos in res["destroy"]:
		var ds := _state(world, dpos)
		var dbe: Dictionary = BlockEntities.get_data(world, dpos).duplicate(true)   # a pushed shulker box keeps its contents
		world.set_block(dpos.x, dpos.y, dpos.z, 0)
		if world.gamerule("doTileDrops", true):
			for s in Loot.block_drops(ds, null, world, dpos, dbe):
				world.entities.spawn_item(Vector3(dpos) + Vector3(0.5, 0.5, 0.5), s)
		if not dbe.is_empty():
			BlockEntities.on_removed(world, dpos, ds)
		Tripwires.on_removed(world, dpos, ds, false)
	var mv: Array = res["move"]
	var states := {}
	var bes := {}
	for q in mv:
		states[q] = _state(world, q)
		var d := BlockEntities.take(world, q)
		if not d.is_empty():
			bes[q] = d
	for q in mv:
		if not states.has(q - dir):
			world.set_block(q.x, q.y, q.z, 0)
	for q in mv:
		var to: Vector3i = q + dir
		world.set_block(to.x, to.y, to.z, states[q])
		if bes.has(q):
			BlockEntities.set_data(world, to, bes[q])
	for q in mv:
		request(world, q + dir)
		if not states.has(q - dir):
			request(world, q)


static func _extend(world, p: Vector3i, st: int) -> void:
	var b := Res.blocks
	var f := _dir(st)
	var res := _resolve(world, p, p + f, f, true)
	if res.is_empty():
		return
	_apply_move(world, res, f)
	world.set_block(p.x, p.y, p.z, b.with_prop(st, "extended", "true"), false)
	var head := b.default_state("piston_head")
	head = b.with_prop(head, "facing", b.get_prop(st, "facing"))
	head = b.with_prop(head, "type", "sticky" if b.name_of(st) == "sticky_piston" else "normal")
	var h := p + f
	world.set_block(h.x, h.y, h.z, head)
	Audio.play("block.piston.extend", Vector3(p), "Blocks")
	request(world, h)


static func _retract(world, p: Vector3i, st: int, sticky: bool) -> void:
	var b := Res.blocks
	var f := _dir(st)
	var h := p + f
	if _name(_state(world, h)) == "piston_head":
		world.set_block(h.x, h.y, h.z, 0)
	world.set_block(p.x, p.y, p.z, b.with_prop(st, "extended", "false"), false)
	if sticky:
		var res := _resolve(world, p, h + f, -f, false)
		if not res.is_empty():
			_apply_move(world, res, -f)
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
