## MobControl — the vanilla mob "controls" layer (Java net.minecraft.world.entity.ai.control + navigation):
## LookControl (head turns toward a look target at bounded speeds, eases back to the body), BodyRotationControl
## (body follows the movement direction; standing still it follows the head after 10 ticks), the LookAtPlayer /
## RandomLookAround goals, PathNavigation (MobPath jobs, waypoint following, corner cutting, stuck detection) and
## MoveControl (turns up to 90 degrees per tick toward the next waypoint, jumps onto higher nodes).
class_name MobControl

const NO_GOAL := Vector3i(0, -9999, 0)


## Java Mth.wrapDegrees
static func wrap_deg(d: float) -> float:
	var f := fmod(d, 360.0)
	if f >= 180.0:
		f -= 360.0
	elif f < -180.0:
		f += 360.0
	return f


## Java LookControl.rotateTowards
static func rot_towards(from: float, to: float, mx: float) -> float:
	return from + clampf(wrap_deg(to - from), -mx, mx)


## Java Mth.rotateIfNecessary
static func rot_if_needed(cur: float, target: float, mx: float) -> float:
	return target + clampf(wrap_deg(cur - target), -mx, mx)


## Java MoveControl.rotlerp
static func rotlerp(cur: float, target: float, mx: float) -> float:
	var r := cur + clampf(wrap_deg(target - cur), -mx, mx)
	if r < 0.0:
		r += 360.0
	elif r > 360.0:
		r -= 360.0
	return r


## Java LookControl.setLookAt(x, y, z, yMaxRotSpeed, xMaxRotAngle): look there for the next 2 ticks
static func set_look(e, at: Vector3, ymax: float = 10.0, xmax: float = 40.0) -> void:
	e.look_at = at
	e.look_cd = 2
	e.look_ymax = ymax
	e.look_xmax = xmax


## Java LookControl.tick (+ clampHeadRotationToBody while navigating)
static func look_tick(e, navigating: bool) -> void:
	e.head_pitch = 0.0   # Java resetXRotOnTick
	if e.look_cd > 0:
		e.look_cd -= 1
		var d: Vector3 = e.look_at - (e.pos + Vector3(0, e.h * 0.85, 0))
		var hz := Vector2(d.x, d.z).length()
		if hz > 1e-5:
			e.head_yaw = rot_towards(e.head_yaw, rad_to_deg(atan2(-d.x, d.z)), e.look_ymax)
		if hz > 1e-5 or absf(d.y) > 1e-5:
			e.head_pitch = rot_towards(0.0, -rad_to_deg(atan2(d.y, hz)), e.look_xmax)
	else:
		e.head_yaw = rot_towards(e.head_yaw, e.body_yaw, 10.0)
	if navigating:
		e.head_yaw = rot_if_needed(e.head_yaw, e.body_yaw, 75.0)


## Java BodyRotationControl.clientTick (after movement; prev = position at the start of the tick)
static func body_tick(e) -> void:
	var dx: float = e.pos.x - e.prev.x
	var dz: float = e.pos.z - e.prev.z
	if dx * dx + dz * dz > 2.5000003e-7:
		e.body_yaw = e.yaw
		e.head_yaw = rot_if_needed(e.head_yaw, e.body_yaw, 75.0)
		e.head_last = e.head_yaw
		e.head_stable = 0
	elif absf(wrap_deg(e.head_yaw - e.head_last)) > 15.0:
		e.head_stable = 0
		e.head_last = e.head_yaw
		e.body_yaw = rot_if_needed(e.body_yaw, e.head_yaw, 75.0)
	else:
		e.head_stable += 1
		if e.head_stable > 10:
			var f := clampf((e.head_stable - 10) / 10.0, 0.0, 1.0)
			e.body_yaw = rot_if_needed(e.body_yaw, e.head_yaw, 75.0 * (1.0 - f))


## Java LookAtPlayerGoal (range 6, 8 for monsters / traders; chance 0.02 per goal update = every other tick; looks
## 40..79 ticks) and RandomLookAroundGoal (0.02; 20..39 ticks; a starting stroll interrupts it). busy: a running
## higher-priority goal owns LOOK (attack, tempt, breed).
static func look_goals(em, e, p, dist: float, moving: bool, busy: bool) -> void:
	if busy:
		e.look_goal = 0
		return
	var range_ := 8.0 if e.def["kind"] == "hostile" or e.def.get("trader", false) else 6.0
	var can_see_p: bool = not p.dead and p.mode != Player.Mode.SPECTATOR and dist <= range_
	if e.look_goal == 1:
		e.look_t -= 1
		if e.look_t <= 0 or not can_see_p:
			e.look_goal = 0
		else:
			set_look(e, p.pos + Vector3(0, p.eye_height(), 0))
	elif e.look_goal == 2:
		e.look_t -= 1
		if e.look_t <= 0 or moving:
			e.look_goal = 0
		else:
			set_look(e, e.pos + Vector3(e.look_dir.x, e.h * 0.85, e.look_dir.y))
	if e.look_goal == 0 and e.age % 2 == 0:
		var rng: RandomNumberGenerator = em.rng
		if can_see_p and rng.randf() < 0.02:
			e.look_goal = 1
			e.look_t = 40 + rng.randi_range(0, 39)
			set_look(e, p.pos + Vector3(0, p.eye_height(), 0))
		elif not moving and rng.randf() < 0.02:
			var a := rng.randf() * TAU
			e.look_goal = 2
			e.look_dir = Vector2(cos(a), sin(a))
			e.look_t = 20 + rng.randi_range(0, 19)


static func follow_range(e) -> float:
	return float(e.def.get("follow_range", 35.0 if e.id in ["zombie", "husk", "drowned", "zombie_villager"] else 16.0))


static func _job(em, e, mode: int) -> MobPath:
	var j := MobPath.new(em.world.cm, Res.blocks)
	j.start = Vector3i(floori(e.pos.x), floori(e.pos.y + 0.49), floori(e.pos.z))
	j.start_fy = e.pos.y
	j.mode = mode
	j.rng = em.rng
	j.h = e.h
	j.monster = e.def["kind"] == "hostile"
	var fr := follow_range(e)
	j.max_nodes = int(fr * 16.0)
	j.max_dist = fr
	return j


## Java PathNavigation.moveTo(target): a new path when the goal block changes (a moving target is re-pathed every
## 4..10 ticks, +5 / +10 when far: MeleeAttackGoal), searched by EntityManager within its per-tick budget.
static func nav_to(em, e, target: Vector3, dist: float) -> void:
	var gb := Vector3i(floori(target.x), floori(target.y + 0.49), floori(target.z))
	var active: bool = e.nav_job != null or e.path_i < e.path.size()
	if gb == e.nav_goal and (active or e.nav_cd > 0):
		return
	if active and e.nav_cd > 0 and Vector3(gb - e.nav_goal).length() < 4.0:
		return
	var j := _job(em, e, 0)
	j.goal_pos = target
	e.nav_job = j
	e.nav_goal = gb
	e.nav_cd = 4 + em.rng.randi_range(0, 6) + (10 if dist > 32.0 else (5 if dist > 16.0 else 0))
	em.nav_queue(e)


## Stroll (mode 1: Java RandomStrollGoal, 10 / 7 blocks) or panic (mode 2: PanicGoal, 5 / 4 blocks) path.
static func nav_random(em, e, mode: int) -> void:
	e.nav_job = _job(em, e, mode)
	e.nav_goal = NO_GOAL
	em.nav_queue(e)


static func nav_stop(e) -> void:
	e.nav_job = null
	e.path = []
	e.path_i = 0
	e.nav_goal = NO_GOAL


## Java PathNavigation.isDone (no pending search either)
static func nav_idle(e) -> bool:
	return e.nav_job == null and e.path_i >= e.path.size()


## Java PathNavigation.followThePath + doStuckDetection: the current waypoint (bottom centre of the next node),
## INF when the path is done.
static func nav_next(e, speed: float) -> Vector3:
	if e.path_i >= e.path.size():
		return Vector3.INF
	var n: Vector3i = e.path[e.path_i]
	var c := Vector3(n.x + 0.5, n.y, n.z + 0.5)
	var md: float = e.w / 2.0 if e.w > 0.75 else 0.75 - e.w / 2.0
	if (absf(e.pos.x - c.x) < md and absf(e.pos.z - c.z) < md and absf(e.pos.y - n.y) < 1.0) or _next_in_direction(e, c):
		e.path_i += 1
		if e.path_i >= e.path.size():
			return Vector3.INF
		n = e.path[e.path_i]
		c = Vector3(n.x + 0.5, n.y, n.z + 0.5)
	if e.age - e.nav_stuck_t > 100:
		var f := speed if speed >= 1.0 else speed * speed
		var f1 := f * 100.0 * 0.25
		if e.pos.distance_squared_to(e.nav_stuck_pos) < f1 * f1:
			nav_stop(e)
			e.nav_stuck_t = e.age
			return Vector3.INF
		e.nav_stuck_t = e.age
		e.nav_stuck_pos = e.pos
	return c


## Java PathNavigation.shouldTargetNextNodeInDirection: skip a waypoint the mob has effectively passed.
static func _next_in_direction(e, c: Vector3) -> bool:
	if e.path_i + 1 >= e.path.size():
		return false
	if e.pos.distance_to(c) >= 2.0:
		return false
	var n2: Vector3i = e.path[e.path_i + 1]
	var a: Vector3 = c - e.pos
	var b: Vector3 = Vector3(n2.x + 0.5, n2.y, n2.z + 0.5) - e.pos
	var d0 := a.length_squared()
	var d1 := b.length_squared()
	if not (d1 < d0) and not (d0 < 0.5):
		return false
	return b.normalized().dot(a.normalized()) < 0.0


## Java MoveControl.tick (MOVE_TO): 0 = arrived, 1 = walk, 2 = walk + jump (waypoint above the step height and
## close horizontally).
static func move_control(e, wanted: Vector3) -> int:
	var d: Vector3 = wanted - e.pos
	if d.length_squared() < 2.5000003e-7:
		return 0
	e.yaw = rotlerp(e.yaw, rad_to_deg(atan2(-d.x, d.z)), 90.0)
	if d.y > float(e.def.get("step_height", 0.6)) and d.x * d.x + d.z * d.z < maxf(1.0, e.w):
		return 2
	return 1
