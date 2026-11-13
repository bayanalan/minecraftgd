## DragonFight — the End boss fight (Java EndDragonFight, simplified dragon phase manager, source D/E):
## exit podium at the main island centre, End Crystals on the obsidian spikes (heal the dragon within 32 blocks,
## explode power 6 when hit), dragon phases (holding circle, strafe + dragon fireballs leaving breath clouds,
## landing + perch breath, takeoff, charge), damage reduction off the head (damage/4 + min(damage, 1)),
## death -> XP (12000 first kill, 500 later), active exit portal, dragon egg (first kill), one of 20 End gateways
## (radius 96, y 75, seed-shuffled order) linked to the outer islands ~1024 blocks out. State persists in
## level.json ("end_fight"). APPROXIMATE: no node path-finding graph, single hitbox, no death beam animation.
class_name DragonFight
extends RefCounted

var world
var state: Dictionary
var ready := false


## Adapter so FeaturesExt structure helpers (end_podium, end_gateway, _end_island) can write live blocks.
class LiveWriter:
	var world
	var blocks: BlockRegistry
	var r: RandomSources.Xoroshiro

	func set_block(_c, p: Vector3i, st: int, _mode: int = 0) -> void:
		world.set_block(p.x, p.y, p.z, st)

	func get_block(_c, p: Vector3i) -> int:
		return world.state_at(p.x, p.y, p.z)


func _init(w) -> void:
	world = w
	state = w.level.get("end_fight", {})
	if state.is_empty():
		var order: Array = []
		for i in 20:
			order.append(i)
		var r := RandomSources.LegacyRandom.new(int(w.level.get("seed", 0)))
		for i in range(order.size(), 1, -1):
			var j := r.next_int_bound(i)
			var t = order[i - 1]
			order[i - 1] = order[j]
			order[j] = t
		state = {"killed": false, "previously_killed": false, "gateways": order, "links": {}, "crystals": false, "podium_y": -1}
	w.level["end_fight"] = state


func writer() -> LiveWriter:
	var lw := LiveWriter.new()
	lw.world = world
	lw.blocks = Res.blocks
	lw.r = RandomSources.Xoroshiro.from_seed(int(world.level.get("seed", 0)) ^ 0x5eed)
	return lw


func tick() -> void:
	if world.dimension != "the_end" or not world.spawn_ready:
		return
	if not ready:
		_try_init()
		return
	if respawn_stage >= 0:
		_respawn_tick()
		respawn_time += 1
		return
	if not bool(state["killed"]) and _find("ender_dragon") == null and world.entities.ents.size() < 2000:
		_spawn_dragon()


func _find(id: String):
	for e in world.entities.ents:
		if e.kind == "mob" and e.id == id and not e.dead:
			return e
	return null


func _try_init() -> void:
	var spikes := FeaturesExt.end_spikes_for_seed(int(world.level.get("seed", 0)))
	if not world.cm.is_ready(0, 0):
		return
	for sp in spikes:
		if not world.cm.is_ready(int(sp[0]), int(sp[1])):
			return
	if int(state.get("podium_y", -1)) < 0:
		var c: Chunk = world.cm.get_chunk(0, 0)
		var y := c.heightmap[0] if c != null else 64
		while y > world.gen.sea_level and Res.blocks.name_of(maxi(world.state_at(0, y, 0), 0)) == "bedrock":
			y -= 1
		state["podium_y"] = maxi(y, world.gen.sea_level + 1)
		FeaturesExt.end_podium(writer(), null, Vector3i(0, int(state["podium_y"]), 0), bool(state["killed"]))
	if not bool(state.get("crystals", false)) and not bool(state["killed"]):
		for sp in spikes:
			var e = world.entities.spawn_mob("end_crystal", Vector3(int(sp[0]) + 0.5, int(sp[3]) + 1, int(sp[1]) + 0.5))
			if e != null:
				e.persistent = true
		state["crystals"] = true
	ready = true
	print("[end] fight ready: podium y %d, crystals %d" % [int(state["podium_y"]), crystals_alive()])


func _spawn_dragon() -> void:
	var e = world.entities.spawn_mob("ender_dragon", Vector3(0.5, 128.0, 0.5))
	if e != null:
		e.persistent = true
		e.state = 0
		print("[end] dragon spawned")
		Audio.play("entity.ender_dragon.growl", world.player.pos, "Hostile")


func podium() -> Vector3:
	return Vector3(0.5, float(state.get("podium_y", 64)) + 1.0, 0.5)


func crystals_alive() -> int:
	var n := 0
	for e in world.entities.ents:
		if e.kind == "mob" and e.id == "end_crystal" and not e.dead:
			n += 1
	return n


## Called by EntityManager when the dragon dies.
func on_dragon_death(e) -> void:
	var first := not bool(state["previously_killed"])
	world.entities.spawn_xp(e.pos, 12000 if first else 500)
	state["killed"] = true
	state["previously_killed"] = true
	var py := int(state.get("podium_y", 64))
	FeaturesExt.end_podium(writer(), null, Vector3i(0, py, 0), true)
	if first:
		world.set_block(0, py + 4, 0, Res.blocks.default_state("dragon_egg"))
	var order: Array = state["gateways"]
	if not order.is_empty():
		var i: int = order.pop_back()
		var gx := floori(96.0 * cos(2.0 * (-PI + 0.15707963267948966 * i)))
		var gz := floori(96.0 * sin(2.0 * (-PI + 0.15707963267948966 * i)))
		FeaturesExt.end_gateway(writer(), null, Vector3i(gx, 75, gz), null, false)
	Audio.play("entity.ender_dragon.death", world.player.pos, "Hostile")
	world.hud.chat_message("The Ender Dragon has been slain")


## Java EndIslandFeature shape (used when no island exists at a gateway exit).
func _island(lw: LiveWriter, o: Vector3i) -> void:
	var es := Res.blocks.default_state("end_stone")
	var fr := float(lw.r.next_int_bound(3)) + 4.0
	var i := 0
	while fr > 0.5:
		for j in range(floori(-fr), ceili(fr) + 1):
			for k in range(floori(-fr), ceili(fr) + 1):
				if float(j * j + k * k) <= (fr + 1.0) * (fr + 1.0):
					world.set_block(o.x + j, o.y + i, o.z + k, es)
		fr -= float(lw.r.next_int_bound(2)) + 0.5
		i -= 1


## Gateway travel: main-island gateways lead ~1024 blocks outward; outer gateways lead back.
func gateway_target(gpos: Vector3i) -> Dictionary:
	var key := "%d,%d,%d" % [gpos.x, gpos.y, gpos.z]
	var links: Dictionary = state.get("links", {})
	if links.has(key):
		var l: Array = links[key]
		return {"kind": "exact", "pos": Vector3(l[0], l[1], l[2])}
	var d := Vector2(gpos.x, gpos.z)
	if d.length() < 1.0:
		d = Vector2(1, 0)
	var out := d.normalized() * (1024.0 if d.length() < 500.0 else 0.0)
	if d.length() >= 500.0:
		return {"kind": "exact", "pos": Vector3(0.5, float(state.get("podium_y", 64)) + 2.0, 60.5)}
	return {"kind": "end_gateway_out", "pos": Vector3(out.x, 75.0, out.y), "from": [gpos.x, gpos.y, gpos.z]}


## After arriving near the outer islands: find ground (or make an island), build the return gateway, link it.
func resolve_outer_arrival(target: Vector3, from: Array) -> Vector3:
	var tx := int(floor(target.x))
	var tz := int(floor(target.z))
	var best := Vector3i(tx, -1, tz)
	for dz in range(-16, 17, 2):
		for dx in range(-16, 17, 2):
			var c: Chunk = world.cm.get_chunk((tx + dx) >> 4, (tz + dz) >> 4)
			if c == null:
				continue
			var h := c.heightmap[((tx + dx) & 15) + ((tz + dz) & 15) * 16]
			if h > best.y and h > 40:
				best = Vector3i(tx + dx, h, tz + dz)
	var lw := writer()
	if best.y < 0:
		best = Vector3i(tx, 75, tz)
		_island(lw, best + Vector3i(0, -1, 0))
	var gw := best + Vector3i(0, 10, 0)
	FeaturesExt.end_gateway(lw, null, gw, null, false)
	var links: Dictionary = state.get("links", {})
	links["%d,%d,%d" % [gw.x, gw.y, gw.z]] = [float(from[0]) + 0.5, float(from[1]) + 2.0, float(from[2]) + 0.5]
	links["%d,%d,%d" % [int(from[0]), int(from[1]), int(from[2])]] = [gw.x + 0.5, gw.y + 2.0, gw.z + 0.5]
	state["links"] = links
	return Vector3(best.x + 0.5, best.y, best.z + 0.5)


# ------------------------------------------------------------------ dragon AI

## Phases: 0 holding circle, 1 strafe, 2 landing approach, 3 perched, 4 takeoff, 5 charge.
# ------------------------------------------------------------------ Java EnderDragon AI (phases on a node graph)

# Java EnderDragon.nodeAdjacency: outer ring 0..11 (radius 60), inner ring 12..19 (radius 40, +10 up), centre 20..23
const ADJ := [6146, 8197, 8202, 16404, 32808, 32848, 65696, 131392, 131712, 263424, 526848, 525313, 1581057, 3166214, 2138120,
	6373424, 4358208, 12910976, 9044480, 9706496, 15216640, 13688832, 11763712, 8257536]
enum Ph { HOLDING, STRAFE, LANDING_APPROACH, LANDING, SITTING_SCANNING, SITTING_ATTACKING, SITTING_FLAMING, TAKEOFF, CHARGING, DYING }
static var _nodes: Array = []


static func _node_pos(em: EntityManager, i: int) -> Vector3:
	if _nodes.size() != 24:
		_nodes = []
		for k in 24:
			var j := 5
			var x: int
			var z: int
			if k < 12:
				x = floori(60.0 * cos(2.0 * (-PI + PI / 12.0 * k)))
				z = floori(60.0 * sin(2.0 * (-PI + PI / 12.0 * k)))
			elif k < 20:
				x = floori(40.0 * cos(2.0 * (-PI + PI / 8.0 * (k - 12))))
				z = floori(40.0 * sin(2.0 * (-PI + PI / 8.0 * (k - 12))))
				j += 10
			else:
				x = floori(20.0 * cos(2.0 * (-PI + PI / 4.0 * (k - 20))))
				z = floori(20.0 * sin(2.0 * (-PI + PI / 4.0 * (k - 20))))
			var h := 60
			var ch: Chunk = em.world.cm.get_chunk(x >> 4, z >> 4)
			if ch != null and not ch.heightmap.is_empty():
				h = ch.heightmap[(x & 15) + (z & 15) * 16]
			_nodes.append(Vector3(x, maxi(10, h + j), z))
	return _nodes[i]


## Java EnderDragon.findClosestNode (only the inner nodes once no crystal is left)
static func _closest(em: EntityManager, at: Vector3, crystals: int) -> int:
	var best := 0
	var bd := 1.0e9
	for k in range(0 if crystals > 0 else 12, 24):
		var d := _node_pos(em, k).distance_squared_to(at.floor())
		if d < bd:
			bd = d
			best = k
	return best


## Java EnderDragon.findPath: A* over the node graph; the nodes after the start (plus an optional final point).
static func _path(em: EntityManager, from: int, to: int, crystals: int) -> Array:
	var lo := 0 if crystals > 0 else 12
	var g := {from: 0.0}
	var prev := {}
	var open := [from]
	var closed := {}
	while not open.is_empty():
		var best := 0
		for oi in open.size():
			if float(g[open[oi]]) + _node_pos(em, open[oi]).distance_to(_node_pos(em, to)) < float(g[open[best]]) + _node_pos(em, open[best]).distance_to(_node_pos(em, to)):
				best = oi
		var cur: int = open.pop_at(best)
		if cur == to:
			break
		closed[cur] = true
		for nb in range(lo, 24):
			if (int(ADJ[cur]) >> nb) & 1 == 0 or closed.has(nb):
				continue
			var ng: float = float(g[cur]) + _node_pos(em, cur).distance_to(_node_pos(em, nb))
			if not g.has(nb) or ng < float(g[nb]):
				g[nb] = ng
				prev[nb] = cur
				if not open.has(nb):
					open.append(nb)
	var out: Array = []
	var c := to
	while c != from and prev.has(c):
		out.push_front(_node_pos(em, c))
		c = prev[c]
	if out.is_empty() and from != to:
		out.append(_node_pos(em, to))
	return out


static func _set_phase(e: EntityManager.Ent, ph: int) -> void:
	e.state = ph
	e.rt["path"] = []
	e.rt["t"] = 0
	e.rt.erase("tgt")


## Java AbstractDragonPhaseInstance navigateToNextPathNode: the next node, 0..20 blocks above it.
static func _next_node(e: EntityManager.Ent, rng: RandomNumberGenerator) -> void:
	var path: Array = e.rt.get("path", [])
	if not path.is_empty():
		var n: Vector3 = path.pop_front()
		e.rt["tgt"] = Vector3(n.x, n.y + rng.randf() * 20.0, n.z)


static func _forward(yr: float) -> Vector3:
	return Vector3(sin(deg_to_rad(yr)), 0.0, -cos(deg_to_rad(yr)))


static func _nearest_player(em: EntityManager, at: Vector3, r: float, p: Player) -> Player:
	if p.dead or not (p.mode == Player.Mode.SURVIVAL or p.mode == Player.Mode.ADVENTURE):
		return null
	return p if p.pos.distance_to(at) <= r else null


## Java HoldingPatternPhase / StrafePlayerPhase / TakeoffPhase findNewTarget: path one step around the ring.
static func _ring_step(em: EntityManager, e: EntityManager.Ent, crystals: int, rng: RandomNumberGenerator, toward := -1) -> void:
	var j := _closest(em, e.pos, crystals)
	var k := j if toward < 0 else toward
	if toward < 0:
		var cw: bool = e.rt.get("cw", false)
		if rng.randi_range(0, 7) == 0:
			cw = not cw
			e.rt["cw"] = cw
			k = j + 6
		k += 1 if cw else -1
	if crystals > 0:
		k = posmod(k, 12)
	else:
		k = ((k - 12) & 7) + 12
	e.rt["path"] = _path(em, j, k, crystals)
	_next_node(e, rng)


static func tick_dragon(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float) -> void:
	var fight: DragonFight = em.world.dragon_fight
	var rng := em.rng
	var pod := fight.podium() if fight != null else Vector3(0.5, 64, 0.5)
	var crystals := fight.crystals_alive() if fight != null else 0
	var yr: float = e.rt.get("yr", fposmod(e.yaw + 180.0, 360.0))
	# Java DragonFlightHistory.record(y, yRot) every tick (64 samples; the renderer curves the neck / tail from it)
	var hist: PackedFloat32Array = e.rt.get("hist", PackedFloat32Array())
	var hi: int = int(e.rt.get("hist_i", -1))
	if hist.size() != 128:
		hist.resize(128)
		for k in 64:
			hist[k * 2] = wrapf(yr, -180.0, 180.0)
			hist[k * 2 + 1] = e.pos.y
		hi = 0
	hi = (hi + 1) & 63
	hist[hi * 2] = wrapf(yr, -180.0, 180.0)
	hist[hi * 2 + 1] = e.pos.y
	e.rt["hist"] = hist
	e.rt["hist_i"] = hi
	e.rt["egg_d"] = e.pos.distance_to(pod)
	var t: int = int(e.rt.get("t", 0)) + 1
	e.rt["t"] = t
	var fly_speed := 0.6
	var turn := -1.0
	var sitting := false
	var head := e.pos + _forward(yr) * 6.5 + Vector3(0, 2.0, 0)
	match e.state:
		Ph.HOLDING:
			var tg = e.rt.get("tgt")
			if tg == null or e.pos.distance_squared_to(tg) < 100.0 or e.pos.distance_squared_to(tg) > 22500.0:
				var path: Array = e.rt.get("path", [])
				if path.is_empty():
					if tg != null and rng.randi_range(0, crystals + 2) == 0:
						_set_phase(e, Ph.LANDING_APPROACH)
					else:
						var tp := _nearest_player(em, pod, 128.0, p)
						var d0 := pod.distance_squared_to(tp.pos) / 512.0 if tp != null else 64.0
						if tg != null and tp != null and (rng.randi_range(0, int(d0 + 2.0) - 1) == 0 or rng.randi_range(0, crystals + 1) == 0):
							_set_phase(e, Ph.STRAFE)
						else:
							_ring_step(em, e, crystals, rng)
				else:
					_next_node(e, rng)
		Ph.STRAFE:
			var tp2 := _nearest_player(em, e.pos, 150.0, p)
			if tp2 == null:
				_set_phase(e, Ph.HOLDING)
			else:
				var hd := Vector2(tp2.pos.x - e.pos.x, tp2.pos.z - e.pos.z).length()
				e.rt["tgt"] = Vector3(tp2.pos.x, tp2.pos.y + minf(0.4 + hd / 80.0 - 1.0, 10.0), tp2.pos.z)
				if tp2.pos.distance_squared_to(e.pos) < 4096.0:
					var to_p := Vector3(tp2.pos.x - e.pos.x, 0, tp2.pos.z - e.pos.z).normalized()
					var ang := rad_to_deg(acos(clampf(_forward(yr).dot(to_p), -1.0, 1.0))) + 0.5
					e.charge += 1
					if e.charge >= 5 and ang >= 0.0 and ang < 10.0:
						var from := head - _forward(yr)
						em.spawn_projectile("dragon_fireball", from, (tp2.pos + Vector3(0, 0.9, 0) - from).normalized() * 0.8, e)
						Audio.play("entity.ender_dragon.shoot", e.pos, "Hostile")
						e.charge = 0
						_set_phase(e, Ph.HOLDING)
				elif e.charge > 0:
					e.charge -= 1
		Ph.LANDING_APPROACH:
			var tg2 = e.rt.get("tgt")
			if tg2 == null or e.pos.distance_squared_to(tg2) < 100.0 or e.pos.distance_squared_to(tg2) > 22500.0:
				var path2: Array = e.rt.get("path", [])
				if path2.is_empty() and tg2 == null:
					var tp3 := _nearest_player(em, pod, 128.0, p)
					var j2: int
					if tp3 != null:
						var pv := Vector3(tp3.pos.x, 0, tp3.pos.z).normalized()
						j2 = _closest(em, Vector3(-pv.x * 40.0, 105.0, -pv.z * 40.0), crystals)
					else:
						j2 = _closest(em, Vector3(40.0, pod.y, 0.0), crystals)
					var pth := _path(em, _closest(em, e.pos, crystals), j2, crystals)
					pth.append(pod)
					e.rt["path"] = pth
					_next_node(e, rng)
				elif path2.is_empty():
					_set_phase(e, Ph.LANDING)
				else:
					_next_node(e, rng)
		Ph.LANDING:
			fly_speed = 1.5
			e.rt["tgt"] = pod
			var hv := Vector2(e.vel.x, e.vel.z).length() + 1.0
			turn = minf(hv, 40.0) / hv
			if e.pos.distance_squared_to(pod) < 1.0:
				_set_phase(e, Ph.SITTING_SCANNING)
				e.rt["flames"] = 0
		Ph.SITTING_SCANNING:
			sitting = true
			var near := _nearest_player(em, e.pos, 20.0, p)
			if near != null and absf(near.pos.y - e.pos.y) <= 10.0:
				if t > 25:
					_set_phase(e, Ph.SITTING_ATTACKING)
					Audio.play("entity.ender_dragon.growl", e.pos, "Hostile")
				else:
					var dxh := near.pos.x - head.x
					var dzh := near.pos.z - head.z
					var d2 := clampf(MobControl.wrap_deg(180.0 - rad_to_deg(atan2(dxh, dzh)) - yr), -100.0, 100.0)
					var f2 := sqrt(dxh * dxh + dzh * dzh) + 1.0
					var yra0: float = float(e.rt.get("yra", 0.0)) * 0.8 + d2 * (0.7 / minf(f2, 40.0) / f2)
					e.rt["yra"] = yra0
					yr += yra0
			elif t >= 100:
				var far := _nearest_player(em, e.pos, 150.0, p)
				if far != null:
					_set_phase(e, Ph.CHARGING)
					e.rt["tgt"] = far.pos
				else:
					_set_phase(e, Ph.TAKEOFF)
		Ph.SITTING_ATTACKING:
			sitting = true
			if t >= 40:
				_set_phase(e, Ph.SITTING_FLAMING)
				e.rt["flames"] = int(e.rt.get("flames", 0)) + 1
		Ph.SITTING_FLAMING:
			sitting = true
			if t == 10:
				# Java SittingFlamingPhase: a dragon breath cloud in front of the head
				var cp := head + _forward(yr) * 2.0
				em.spawn_cloud(Vector3(cp.x, pod.y, cp.z))
			if t >= 200:
				_set_phase(e, Ph.TAKEOFF if int(e.rt.get("flames", 0)) >= 4 else Ph.SITTING_SCANNING)
		Ph.TAKEOFF:
			if t == 1:
				var hl := _forward(yr)
				_ring_step(em, e, crystals, rng, _closest(em, Vector3(-hl.x * 40.0, 105.0, -hl.z * 40.0), crystals))
			elif Vector2(e.pos.x - pod.x, e.pos.z - pod.z).length() > 10.0 or e.pos.y > pod.y + 10.0:
				_set_phase(e, Ph.HOLDING)
		Ph.CHARGING:
			fly_speed = 3.0
			var tg3 = e.rt.get("tgt")
			if tg3 == null or int(e.rt.get("since", 0)) >= 10:
				e.rt.erase("since")
				_set_phase(e, Ph.HOLDING)
			elif int(e.rt.get("since", 0)) > 0 or e.pos.distance_squared_to(tg3) < 100.0 or e.pos.distance_squared_to(tg3) > 22500.0:
				e.rt["since"] = int(e.rt.get("since", 0)) + 1
		Ph.DYING:
			# Java EnderDragon.tickDeath: 200 ticks rising 0.1 and spinning 20 degrees, explosion particles at the end
			e.vel = Vector3.ZERO
			e.pos.y += 0.1
			yr += 20.0
			if t >= 180:
				Particles.emit("explosion", e.pos + Vector3(rng.randf_range(-4, 4), rng.randf_range(-2, 2), rng.randf_range(-4, 4)))
			if t >= 200:
				if fight != null:
					fight.on_dragon_death(e)
				em._remove(e)
				return
			e.rt["yr"] = yr
			e.yaw = yr + 180.0
			e.body_yaw = e.yaw
			_flap(e, true)
			return
	# Java EnderDragon.aiStep: flight toward the phase's target (sitting: on the podium)
	if sitting:
		e.vel = Vector3.ZERO
		e.pos = pod
	else:
		var tgt = e.rt.get("tgt")
		if tgt != null:
			var dv: Vector3 = tgt - e.pos
			var dsq := dv.length_squared()
			var horiz := Vector2(dv.x, dv.z).length()
			var dy := clampf(dv.y / horiz, -fly_speed, fly_speed) if horiz > 0.0 else dv.y
			e.vel.y += dy * 0.01
			yr = MobControl.wrap_deg(yr)
			var v34 := dv.normalized()
			var v35 := Vector3(sin(deg_to_rad(yr)), e.vel.y, -cos(deg_to_rad(yr))).normalized()
			var f8 := maxf((v35.dot(v34) + 0.5) / 1.5, 0.0)
			if absf(dv.x) > 1e-5 or absf(dv.z) > 1e-5:
				var f9 := clampf(MobControl.wrap_deg(180.0 - rad_to_deg(atan2(dv.x, dv.z)) - yr), -50.0, 50.0)
				if turn < 0.0:
					var hs := Vector2(e.vel.x, e.vel.z).length() + 1.0
					turn = 0.7 / minf(hs, 40.0) / hs
				var yra: float = float(e.rt.get("yra", 0.0)) * 0.8 + f9 * turn
				e.rt["yra"] = yra
				yr += yra * 0.1
			var f19 := 2.0 / (dsq + 1.0)
			e.vel += _forward(yr) * (0.06 * (f8 * f19 + (1.0 - f19)))
			e.pos += e.vel
			var v36 := e.vel.normalized()
			var d8 := 0.8 + 0.15 * (v36.dot(v35) + 1.0) / 2.0
			e.vel = Vector3(e.vel.x * d8, e.vel.y * 0.91, e.vel.z * d8)
	e.rt["yr"] = yr
	e.yaw = yr + 180.0   # Java's dragon faces (sin yRot, -cos yRot): the renderer's 180 - body yaw = -yRot
	e.body_yaw = e.yaw
	_flap(e, sitting)
	var vulnerable := not p.dead and (p.mode == Player.Mode.SURVIVAL or p.mode == Player.Mode.ADVENTURE)
	# Java EnderDragon: wings knock entities back, the head hurts them (not while perched)
	if vulnerable and not sitting and e.attack_cd <= 0:
		if p.pos.distance_to(head) < 3.0:
			p.hurt(10.0, "mob")
			e.attack_cd = 10
		elif p.pos.distance_to(e.pos) < 5.0:
			var kb := Vector3(p.pos.x - e.pos.x, 0, p.pos.z - e.pos.z)
			var kd := maxf(kb.length_squared(), 0.1)
			p.vel += Vector3(kb.x / kd * 4.0, 0.2, kb.z / kd * 4.0)
			p.hurt(5.0, "mob")
			e.attack_cd = 10
	_check_crystals(em, e)


## Java EnderDragon.checkCrystals: heal 1 every 10 ticks from the tracked crystal (the healing beam is drawn to it);
## 1 tick in 10 the nearest crystal within the dragon's box grown by 32 becomes the tracked one (or none).
static func _check_crystals(em: EntityManager, e: EntityManager.Ent) -> void:
	var nc = e.rt.get("crystal")
	if nc != null:
		if not (nc is EntityManager.Ent) or (nc as EntityManager.Ent).dead or not em.ents.has(nc):
			e.rt.erase("crystal")
		elif e.age % 10 == 0 and e.hp < float(e.def["hp"]):
			e.hp = minf(e.hp + 1.0, float(e.def["hp"]))
	if em.rng.randi_range(0, 9) == 0:
		var best = null
		var bd := INF
		var hw := 8.0 + 32.0   # Java dragon box 16 x 8, inflated by 32
		for o in em.ents:
			if o.kind == "mob" and o.id == "end_crystal" and not o.dead:
				var d: Vector3 = o.pos - e.pos
				if absf(d.x) <= hw and absf(d.z) <= hw and d.y >= -32.0 - 2.0 and d.y <= 8.0 + 32.0:
					var ds := d.length_squared()
					if ds < bd:
						bd = ds
						best = o
		if best == null:
			e.rt.erase("crystal")
		else:
			e.rt["crystal"] = best


## Java EnderDragon.aiStep flap time: 0.2 / (horizontal speed * 10 + 1) * 2^vy per tick (0.1 perched).
static func _flap(e: EntityManager.Ent, sitting: bool) -> void:
	var fl: float = e.rt.get("flap", 0.0)
	e.rt["flap_o"] = fl
	var hv := Vector2(e.vel.x, e.vel.z).length()
	var f7 := 0.2 / (hv * 10.0 + 1.0) * pow(2.0, e.vel.y)
	e.rt["flap"] = fl + (0.1 if sitting else f7)


## Called by EntityManager instead of removing the dragon: the 200-tick death animation.
static func start_dying(e: EntityManager.Ent) -> void:
	_set_phase(e, Ph.DYING)
	e.hp = 1.0

# ------------------------------------------------------------------ dragon respawn (Java EndDragonFight.tryRespawn,
# DragonRespawnAnimation): 4 crystals on the exit portal's sides -> crystals beam up, the pillars are blown up and
# rebuilt one by one (with invulnerable crystals beaming at the centre), the crystals explode, a new dragon spawns.
enum Rs { START, PREPARING, PILLARS, SUMMONING, END }
var respawn_stage := -1
var respawn_time := 0
var respawn_crystals: Array = []


func try_respawn() -> void:
	if not bool(state["killed"]) or respawn_stage >= 0:
		return
	var py := int(state.get("podium_y", -1))
	if py < 0:
		return
	var found: Array = []
	for d in [Vector3i(0, 0, -2), Vector3i(2, 0, 0), Vector3i(0, 0, 2), Vector3i(-2, 0, 0)]:
		var bmin := Vector3(d.x, py + 1, d.z)
		var lst: Array = []
		for e in world.entities.ents:
			if e.kind == "mob" and e.id == "end_crystal" and not e.dead:
				if e.pos.x + 1.0 > bmin.x and e.pos.x - 1.0 < bmin.x + 1.0 and e.pos.z + 1.0 > bmin.z and e.pos.z - 1.0 < bmin.z + 1.0 and e.pos.y + 2.0 > bmin.y and e.pos.y < bmin.y + 1.0:
					lst.append(e)
		if lst.is_empty():
			return
		found.append_array(lst)
	# respawnDragon: the exit portal goes back to an inactive one
	FeaturesExt.end_podium(writer(), null, Vector3i(0, py, 0), false)
	respawn_stage = Rs.START
	respawn_time = 0
	respawn_crystals = found


func _set_stage(st: int) -> void:
	respawn_time = -1   # incremented after this tick
	if st == Rs.END:
		respawn_stage = -1
		respawn_crystals = []
		state["killed"] = false
		_spawn_dragon()
	else:
		respawn_stage = st


func _beam_all(target) -> void:
	for c in respawn_crystals:
		if target == null:
			c.data.erase("BeamTarget")
		else:
			c.data["BeamTarget"] = target


func _roar() -> void:
	Audio.play("entity.ender_dragon.growl", world.player.pos, "Hostile", 1.0, 0.8 + world.rng.randf() * 0.3)


func _respawn_tick() -> void:
	var t := respawn_time
	var centre := Vector3i(0, 128, 0)
	match respawn_stage:
		Rs.START:
			_beam_all(centre)
			_set_stage(Rs.PREPARING)
		Rs.PREPARING:
			if t < 100:
				if t == 0 or t == 50 or t == 51 or t == 52 or t >= 95:
					_roar()
			else:
				_set_stage(Rs.PILLARS)
		Rs.PILLARS:
			var start := t % 40 == 0
			var done := t % 40 == 39
			if start or done:
				var spikes := FeaturesExt.end_spikes_for_seed(int(world.level.get("seed", 0)))
				var j := t / 40
				if j < spikes.size():
					var sp: Array = spikes[j]
					if start:
						_beam_all(Vector3i(int(sp[0]), int(sp[3]) + 1, int(sp[1])))
					else:
						_rebuild_spike(sp)
				elif start:
					_set_stage(Rs.SUMMONING)
		Rs.SUMMONING:
			if t >= 100:
				_reset_spike_crystals()
				for c in respawn_crystals:
					c.data.erase("BeamTarget")
					if not c.dead:
						world.entities.explode(c.pos, 6.0, false)
						world.entities._remove(c)
				_set_stage(Rs.END)
			elif t >= 80:
				_roar()
			elif t == 0:
				_beam_all(centre)
			elif t < 5:
				_roar()


## The respawn step for one pillar: clear a 21^3 box around its top, a power 5 explosion, then SpikeFeature again
## with an invulnerable crystal beaming at (0, 128, 0).
func _rebuild_spike(sp: Array) -> void:
	var cx: int = sp[0]
	var cz: int = sp[1]
	var h: int = sp[3]
	for y in range(h - 10, h + 11):
		for z in range(cz - 10, cz + 11):
			for x in range(cx - 10, cx + 11):
				if world.state_at(x, y, z) > 0:
					world.set_block(x, y, z, 0)
	world.entities.explode(Vector3(cx + 0.5, h, cz + 0.5), 5.0, true)
	var lw := writer()
	var shim := SpikeShim.new()
	shim.lw = lw
	FeaturesExt.place_spike(shim, null, sp)
	for e in world.entities.ents:
		if e.kind == "mob" and e.id == "end_crystal" and not e.dead and absf(e.pos.x - (cx + 0.5)) < 1.0 and absf(e.pos.z - (cz + 0.5)) < 1.0 and absf(e.pos.y - (h + 1)) < 2.0:
			world.entities._remove(e)
	var ce = world.entities.spawn_mob("end_crystal", Vector3(cx + 0.5, h + 1, cz + 0.5))
	if ce != null:
		ce.persistent = true
		ce.data["Invulnerable"] = true
		ce.data["BeamTarget"] = Vector3i(0, 128, 0)


## resetSpikeCrystals: the spike crystals become vulnerable and stop beaming.
func _reset_spike_crystals() -> void:
	for e in world.entities.ents:
		if e.kind == "mob" and e.id == "end_crystal" and not respawn_crystals.has(e):
			e.data.erase("Invulnerable")
			e.data.erase("BeamTarget")


## EndDragonFight.onCrystalDestroyed: destroying one of the respawn crystals aborts the sequence (spike crystals reset,
## the exit portal back to active).
func on_crystal_destroyed(c) -> void:
	if respawn_stage >= 0 and respawn_crystals.has(c):
		respawn_stage = -1
		respawn_time = 0
		_reset_spike_crystals()
		for o in respawn_crystals:
			o.data.erase("BeamTarget")
		respawn_crystals = []
		FeaturesExt.end_podium(writer(), null, Vector3i(0, int(state.get("podium_y", 64)), 0), true)


## Lets FeaturesExt.place_spike (worldgen signature: f.blocks, f.gen.gen_min_y, f.set_block) write live blocks.
class SpikeShim:
	var lw: LiveWriter
	var blocks: BlockRegistry:
		get:
			return Res.blocks
	var gen: Dictionary = {"gen_min_y": 0}

	func set_block(_c, p: Vector3i, st: int, _mode: int = 0) -> void:
		if lw.world.state_at(p.x, p.y, p.z) != st:
			lw.world.set_block(p.x, p.y, p.z, st)
