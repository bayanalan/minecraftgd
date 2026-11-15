## Villagers (wiki Villager, Job site block, Trading, Zombie Villager): job site claiming, work + restocking, gathering
## and gossip sharing, curing zombie villagers.
## - Job sites: an unemployed villager (not a nitwit, not a baby) searches "the nearest unclaimed site in a 48-block
##   sphere" while it is day, walks there under a provisional claim (dropped after 60 s without reaching it, it may try
##   again at once) and claims it fully within 2 blocks of the site's centre: it takes the block's profession (novice
##   trade set), green particles. A removed site makes a villager that never traded unemployed again (traded villagers
##   keep their profession forever and only claim matching sites); failing to reach the site several times unclaims it
##   (angry particles). Job site blocks and bells are indexed per chunk from the section palettes when chunks load
##   (Interest.POI) and when placed - no block scans.
## - Schedule (Java): work 2000-9000 (stand next to the site - "the 8 surrounding spaces at foot height or the 9 blocks
##   below" - and wander a little), gather 9000-11000 at the nearest bell, then wander / sleep. Working "resupplies any
##   locked trades" up to twice a day (Trading.restock) and plays the profession's work sound.
## - Gossip: villagers that meet while gathering share their gossip; the listener gets each type's value minus its
##   sharing cost (wiki table: trading 20, major_positive 100 - never shared, minor_positive 5, minor_negative 20,
##   major_negative 10), keeping the higher value, capped at the type's maximum.
## - Curing: a golden apple on a zombie villager with Weakness starts the cure: 3600-6000 ticks, Weakness replaced by
##   Strength (I, not difficulty-dependent), shudder, entity.zombie_villager.cure; every tick a 1 % chance to look for
##   iron bars / beds in the 9 x 9 x 9 cube around it, each found (max 14) with a 30 % chance to cut one more tick. The
##   villager keeps profession, trades, level, experience, gossip and type, drops picked-up items, gets Nausea 10 s;
##   the curer gains major_positive 20 + minor_positive 25 gossip (wiki Villager).
## - Beds (wiki Villager): every villager claims the nearest bed (the head of a #minecraft:beds bed) no other villager
##   claimed - green particles; the claim is dropped when the bed is gone. "At sunset" (schedule rest 12000 .. 10) it
##   walks home and lies down in it (eyes open, the hitbox a 0.2 cube on the pillow, the bed occupied) "until morning";
##   it wakes early when hurt, when a bell rings, when its bed is broken or used by a player (who kicks it out), and goes
##   back to bed when it can. Villagers without a bed keep wandering and looking for one.
## - Raids (wiki Villager / Raid): within the raid's 96-block area villagers neither claim job sites nor work; before the
##   first wave they rush to their meeting bell and the first one there rings it (Bells.ring sends villagers within 32
##   to a bed); during the raid they hide in a house - their own bed within 32 blocks, else the nearest bed - and wake
##   up for it; after a victory they cheer (entity.villager.celebrate).
## - Iron golems (wiki Iron Golem): while gossiping (5 villagers) or every 5 s while panicking (3 villagers) a villager
##   summons a golem when at least that many villagers within 10 blocks (itself included) each slept within the last 20
##   minutes and saw no golem within 16 blocks (scanned every 10 s) in the last 30 s; up to 10 tries in the 17 x 13 x 17
##   box, the topmost air / liquid block on a solid one in the column, the block and the two above not full blocks or
##   rails, the two above not water, no entity in the way; the villagers within 10 blocks then count it as seen.
class_name Villagers
extends RefCounted

const JOB_BLOCKS := {"blast_furnace": "armorer", "smoker": "butcher", "cartography_table": "cartographer",
	"brewing_stand": "cleric", "composter": "farmer", "barrel": "fisherman", "fletching_table": "fletcher",
	"cauldron": "leatherworker", "water_cauldron": "leatherworker", "lava_cauldron": "leatherworker",
	"powder_snow_cauldron": "leatherworker", "lectern": "librarian", "stonecutter": "mason", "loom": "shepherd",
	"smithing_table": "toolsmith", "grindstone": "weaponsmith"}   # wiki Job site block ("any cauldron" for leatherworkers)
const SEARCH_R := 48.0
const CLAIM_TICKS := 1200
const CLAIM_REACH := 2.0
const WORK_START := 2000
const GATHER_START := 9000
const GATHER_END := 11000
const NIGHT := 12000
const MEET_R := 48.0          # (the wiki gives no meeting point range: the job site search range)
const GOSSIP_COST := {"trading": 20, "major_positive": 100, "minor_positive": 5, "minor_negative": 20, "major_negative": 10}
const NONE := Vector3i(0, -99999, 0)
const HOME_R := 48.0          # (the wiki gives no bed claiming range: the 48-block bed range of villager breeding)
const SLEEP_REACH := 2.0      # (not on the wiki: Java SleepInBed starts within 2 blocks of the bed's centre)
const WAKE_T := 10            # wiki Villager schedule: rest from 12000 until 10 (06:00:36)
const SLEEP_SIZE := 0.2       # wiki Villager: the sleeping hitbox "reduces to a cube" on the pillow (Java 0.2)
const RAID_R := 96.0          # wiki Raid: the raid's area (its bar shows within 96 blocks)
const HIDE_R := 32.0          # wiki Bell: villagers run to the nearest bed within 32 blocks
const BELL_RING_R := 3.0      # (not on the wiki: Java RingBell rings within 3 blocks)
const GOLEM_SEEN_T := 600     # wiki Iron Golem: no golem detected in the last 30 s ...
const GOLEM_SCAN_T := 200     # ... scanned every 10 s ...
const GOLEM_SCAN_R := 16.0    # ... within 16 blocks on each axis
const GOLEM_SLEPT_T := 24000  # ... the villager slept within the last 20 minutes
const GOLEM_GROUP_R := 10.0   # ... participants within 10 blocks on each axis
## bed facing -> sleep_dir index (render rotation: Java sleepDirectionToRotation south 90, west 0, north 270, east 180)
const FACINGS := ["south", "west", "north", "east"]
const FACING_VEC := [Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 0)]

static var _poi: Dictionary = {}   # chunk key -> PackedInt32Array [x, y, z]*: job site blocks, bells and bed heads seen there
static var _sleepers: Dictionary = {}   # bed head -> the villager asleep in it (the bed's "occupied")


static func _ck(cx: int, cz: int) -> int:
	return (cx << 32) | (cz & 0xFFFFFFFF)


# ------------------------------------------------------------------ POI index

## Job sites / bells of a chunk that became ready (BlockEntities.index_chunk): only sections whose palette holds one.
static func index_chunk(c: Chunk, any: bool = true) -> void:
	if not any:
		_poi.erase(_ck(c.cx, c.cz))   # (none in its palettes)
		return
	var found := PackedInt32Array()
	var t := PackedByteArray()
	for si in c.sections.size():
		var sec: Chunk.Section = c.sections[si]
		if (Interest.section_mask(sec) & Interest.POI) == 0:
			continue
		if t.is_empty():
			t = Interest.table()
		for i in BlockEntities.section_find(sec, t, Interest.POI):
			if not _poi_state(sec.get_at(i)):
				continue   # (the foot half of a bed)
			found.append(c.cx * 16 + (i & 15))
			found.append(Coords.MIN_Y + si * 16 + (i >> 8))
			found.append(c.cz * 16 + ((i >> 4) & 15))
	var k := _ck(c.cx, c.cz)
	if found.is_empty():
		_poi.erase(k)
	else:
		_poi[k] = found


## A job site block, bell or bed placed (BlockEntities.on_placed; beds come as their foot half: the head is indexed).
static func poi_placed(p: Vector3i, st: int = -1) -> void:
	if st > 0 and Res.blocks.has_prop(st, "part") and Res.blocks.get_prop(st, "part") == "foot":
		var f := FACINGS.find(Res.blocks.get_prop(st, "facing"))
		if f >= 0:
			p += FACING_VEC[f]
	var k := _ck(p.x >> 4, p.z >> 4)
	var a: PackedInt32Array = _poi.get(k, PackedInt32Array())
	for i in range(0, a.size(), 3):
		if a[i] == p.x and a[i + 1] == p.y and a[i + 2] == p.z:
			return
	a.append(p.x)
	a.append(p.y)
	a.append(p.z)
	_poi[k] = a


## Job site blocks, bells and the 16 #minecraft:beds colours (the 26.3 straw bed is not in the tag).
static func is_poi_block(name: String) -> bool:
	return JOB_BLOCKS.has(name) or name == "bell" or is_bed_name(name)


static func is_bed_name(name: String) -> bool:
	return name.ends_with("_bed") and name != "straw_bed"


## A POI state worth indexing: not the foot half of a bed.
static func _poi_state(st: int) -> bool:
	return st > 0 and not (Res.blocks.has_prop(st, "part") and Res.blocks.get_prop(st, "part") == "foot")


## The head half of a villager bed.
static func is_bed_head(st: int) -> bool:
	return st > 0 and is_bed_name(Res.blocks.name_of(st)) and Res.blocks.get_prop(st, "part") == "head"


static func _job_of(world, p: Vector3i) -> String:
	var st: int = world.state_at(p.x, p.y, p.z)
	return str(JOB_BLOCKS.get(Res.blocks.name_of(st), "")) if st > 0 else ""


## Nearest indexed block within r of `at`: kind "bell", or a job site (of profession `prof`, any when ""), not in taken.
static func _nearest(world, at: Vector3, r: float, kind: String, prof: String, taken: Dictionary) -> Vector3i:
	var best := NONE
	var bd := r * r
	var cx0 := floori(at.x - r) >> 4
	var cx1 := floori(at.x + r) >> 4
	var cz0 := floori(at.z - r) >> 4
	var cz1 := floori(at.z + r) >> 4
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var a = _poi.get(_ck(cx, cz))
			if a == null:
				continue
			var arr: PackedInt32Array = a
			for i in range(0, arr.size(), 3):
				var p := Vector3i(arr[i], arr[i + 1], arr[i + 2])
				var d := (Vector3(p) + Vector3(0.5, 0.5, 0.5)).distance_squared_to(at)
				if d >= bd or taken.has(p):
					continue
				if kind == "bell":
					if Res.blocks.name_of(world.state_at(p.x, p.y, p.z)) != "bell":
						continue
				elif kind == "bed":
					if not is_bed_head(world.state_at(p.x, p.y, p.z)):
						continue
				else:
					var jp := _job_of(world, p)
					if jp == "" or (prof != "" and jp != prof):
						continue
				bd = d
				best = p
	return best


## Job sites claimed (or provisionally claimed) by other villagers.
static func _taken(em, e) -> Dictionary:
	var out := {}
	for v in MobBehaviors.near_list(em, "villager"):
		if v == e:
			continue
		var j = v.data.get("job")
		if j is Array:
			out[Vector3i(int(j[0]), int(j[1]), int(j[2]))] = true
		var pj = v.rt.get("pjob")
		if pj is Array:
			out[pj[0]] = true
	return out


# ------------------------------------------------------------------ per-tick goal

static func _traded(e) -> bool:
	return int(e.data.get("vxp", 0)) > 0 or int(e.data.get("level", 1)) > 1


static func _set_prof(em, e, prof: String) -> void:
	Trading.set_profession(e, prof, em.rng)
	MobBehaviors.villager_layers(e)


static func _particles(e, kind: String) -> void:
	for i in 5:
		Particles.emit(kind, e.pos + Vector3(randf_range(-0.5, 0.5), 1.0 + randf(), randf_range(-0.5, 0.5)))


## The villager's navigation goal this tick (EntityManager._tick_mob): Vector3.INF = nothing to do (stroll as usual),
## else walk there.
static func tick(em, e) -> Vector3:
	var uh := int(e.rt.get("unhappy", 0))
	if uh > 0:
		if uh == 1:
			e.rt.erase("unhappy")
		else:
			e.rt["unhappy"] = uh - 1
	var w = em.world
	var now := int(w.game_time)
	var t := int(w.day_time) % 24000
	if now >= int(e.rt.get("golem_scan", 0)):
		_golem_sense(em, e, now)
	if (now + e.uid) % 20 == 0:
		_check_home(em, e)
	if not e.data.has("home") and now >= int(e.rt.get("home_scan", 0)):
		_find_home(em, e, now)
	var rd := raid_at(w, e.pos)
	if not rd.is_empty():
		e.rt.erase("pjob")   # wiki Villager: no job site / profession claiming during raids
		return _raid_goal(em, e, rd)
	e.rt.erase("hide")
	if t >= NIGHT or t < WAKE_T:
		var bg := _bed_goal(em, e, now)
		if bg != Vector3.INF or e.data.has("sleep"):
			return bg
	if e.baby_age < 0:
		return Vector3.INF   # (babies wander / play and take no profession)
	var prof := str(e.data.get("prof", "none"))
	if prof == "nitwit":
		return _gather(em, e, now) if t >= GATHER_START and t < GATHER_END else Vector3.INF
	if (now + e.uid) % 20 == 0:
		_check_job(em, e)
	# provisional claim: walk to the site, claim it within 2 blocks of its centre
	var pj = e.rt.get("pjob")
	if pj is Array:
		var pp: Vector3i = pj[0]
		var jp := _job_of(w, pp)
		if jp == "" or (prof != "none" and jp != prof) or now > int(pj[1]) or t >= NIGHT:
			e.rt.erase("pjob")
		elif (Vector3(pp) + Vector3(0.5, 0.5, 0.5)).distance_to(e.pos + Vector3(0, 0.5, 0)) <= CLAIM_REACH:
			e.rt.erase("pjob")
			e.data["job"] = [pp.x, pp.y, pp.z]
			e.rt.erase("job_fail")
			if prof == "none":
				_set_prof(em, e, jp)
			_particles(e, "happy_villager")
		else:
			return Vector3(pp) + Vector3(0.5, 0.0, 0.5)
	# job search (day only, not while claiming): unemployed -> any free site, traded but site lost -> a matching one
	if not e.data.has("job") and not e.rt.has("pjob") and t < NIGHT and now >= int(e.rt.get("job_scan", 0)):
		e.rt["job_scan"] = now + 20 + em.rng.randi_range(0, 19)   # (the wiki gives no search interval)
		var site := _nearest(w, e.pos, SEARCH_R, "job", "" if prof == "none" else prof, _taken(em, e))
		if site != NONE:
			e.rt["pjob"] = [site, now + CLAIM_TICKS]
			return Vector3(site) + Vector3(0.5, 0.0, 0.5)
	if e.data.has("job") and t >= WORK_START and t < GATHER_START:
		return _work(em, e, now)
	if t >= GATHER_START and t < GATHER_END:
		return _gather(em, e, now)
	return Vector3.INF


## Every 20 ticks: the claimed site must still be a job site of the villager's profession (when its chunk is loaded);
## without a site, a villager that never traded becomes unemployed.
static func _check_job(em, e) -> void:
	var w = em.world
	var prof := str(e.data.get("prof", "none"))
	var j = e.data.get("job")
	if j is Array:
		var jp := Vector3i(int(j[0]), int(j[1]), int(j[2]))
		if w.cm != null and w.cm.get_chunk(jp.x >> 4, jp.z >> 4) == null:
			return
		var jb := _job_of(w, jp)
		if jb != "" and (prof == "none" or jb == prof):
			return
		e.data.erase("job")
	if prof != "none" and prof != "nitwit" and not e.rt.has("pjob") and not _traded(e):
		_set_prof(em, e, "none")


## Work time: go to the job site; next to it, work (restock, work sound) and wander a little.
static func _work(em, e, now: int) -> Vector3:
	var j: Array = e.data["job"]
	var jp := Vector3i(int(j[0]), int(j[1]), int(j[2]))
	var fp := Vector3i(floori(e.pos.x), floori(e.pos.y), floori(e.pos.z))
	var reached := absi(jp.x - fp.x) <= 1 and absi(jp.z - fp.z) <= 1 and (jp.y == fp.y or jp.y == fp.y - 1) and jp != fp
	if not reached:
		# a path that ended short of the site counts as a failed attempt; several -> unclaimed (wiki)
		if MobControl.nav_idle(e) and e.nav_cd <= 0 and e.nav_goal == jp:
			var f := int(e.rt.get("job_fail", 0)) + 1
			e.rt["job_fail"] = f
			if f > 3:   # (the wiki says "several times": 3 tries)
				e.data.erase("job")
				e.rt.erase("job_fail")
				for i in 5:
					Particles.emit("angry_villager", Vector3(jp) + Vector3(randf(), 1.0 + randf() * 0.5, randf()))
				if not _traded(e):
					_set_prof(em, e, "none")
				return Vector3.INF
		return Vector3(jp) + Vector3(0.5, 0.0, 0.5)
	e.rt.erase("job_fail")
	if now >= int(e.rt.get("work_t", 0)):
		e.rt["work_t"] = now + 300 + em.rng.randi_range(0, 299)   # (the wiki gives no work interval: "randomly")
		var prof := str(e.data.get("prof", "none"))
		_restock(em, e)
		Audio.play("entity.villager.work_" + prof, Vector3(jp) + Vector3(0.5, 0.5, 0.5), "Neutral", 1.0, randf_range(0.8, 1.2))
	return Vector3.INF   # (next to the site: the usual short strolls - "gather supplies" - and back)


## wiki Trading: working at the job site resupplies the offers "up to twice per day" when a trade was used.
static func _restock(em, e) -> void:
	var day := int(em.world.day_time) / 24000
	if int(e.data.get("restock_day", -1)) != day:
		e.data["restock_day"] = day
		e.data["restocks"] = 0
	if int(e.data.get("restocks", 0)) >= 2:
		return
	var used := false
	for o in e.data.get("offers", []):
		if int(o.get("uses", 0)) > 0:
			used = true
			break
	if not used:
		return
	Trading.restock(e)
	e.data["restocks"] = int(e.data.get("restocks", 0)) + 1
	e.data["last_restock"] = int(em.world.game_time)


## Gather time: to the nearest bell (meeting point), mingle, share gossip with villagers met there.
static func _gather(em, e, now: int) -> Vector3:
	if now >= int(e.rt.get("bell_t", 0)):
		e.rt["bell_t"] = now + 200 + em.rng.randi_range(0, 99)
		e.rt["bell"] = _nearest(em.world, e.pos, MEET_R, "bell", "", {})
	if (now + e.uid) % 20 == 0:
		_meet(em, e, now)
	var bell: Vector3i = e.rt.get("bell", NONE)
	if bell != NONE and Vector2(e.pos.x - bell.x - 0.5, e.pos.z - bell.z - 0.5).length() > 4.0:
		return Vector3(bell) + Vector3(0.5, 0.0, 0.5)
	return Vector3.INF


## Two adult villagers within 2 blocks share gossip (both ways), each at most once a minute (the wiki gives no interval).
static func _meet(em, e, now: int) -> void:
	if now < int(e.rt.get("gossip_t", 0)):
		return
	for v in MobBehaviors.near_list(em, "villager"):
		if v == e or v.dead or v.baby_age < 0 or now < int(v.rt.get("gossip_t", 0)) or v.pos.distance_squared_to(e.pos) > 4.0:
			continue
		share_gossip(v, e)
		share_gossip(e, v)
		e.rt["gossip_t"] = now + 1200
		v.rt["gossip_t"] = now + 1200
		summon_golem(em, e, 5)   # wiki Iron Golem: gossiping villagers (5) can summon a golem
		return


## The listener takes each of the speaker's gossip values minus the sharing cost (keeping its own when higher).
static func share_gossip(from, to) -> void:
	var g = from.data.get("gossip")
	if not (g is Dictionary) or (g as Dictionary).is_empty():
		return
	var tg: Dictionary = to.data.get("gossip", {})
	for k in g:
		var v := int(g[k]) - int(GOSSIP_COST.get(k, 1000))
		if v <= 0:
			continue
		var mx := int((Trading.GOSSIP.get(k, [0, 0, 0, 0]) as Array)[2])
		tg[k] = mini(mx, maxi(int(tg.get(k, 0)), v))
	if not tg.is_empty():
		to.data["gossip"] = tg


# ------------------------------------------------------------------ beds and sleeping

## "Stand still" goal (EntityManager: no navigation and no stroll this tick) - hiding indoors, waiting at the bed.
const STAY := Vector3(0.0, -1.0e9, 0.0)


## Beds claimed by other villagers.
static func _taken_beds(em, e) -> Dictionary:
	var out := {}
	for v in MobBehaviors.near_list(em, "villager"):
		if v != e:
			var h = v.data.get("home")
			if h is Array:
				out[Vector3i(int(h[0]), int(h[1]), int(h[2]))] = true
	return out


static func _home_of(e) -> Vector3i:
	var h = e.data.get("home")
	return Vector3i(int(h[0]), int(h[1]), int(h[2])) if h is Array else NONE


## Claims the nearest free bed within 48 blocks (Java AcquirePoi takes a home as soon as it finds one - green
## particles), retried every 40-79 ticks while the villager has none (the wiki gives no interval).
static func _find_home(em, e, now: int) -> void:
	e.rt["home_scan"] = now + 40 + em.rng.randi_range(0, 39)
	var b := _nearest(em.world, e.pos, HOME_R, "bed", "", _taken_beds(em, e))
	if b == NONE:
		return
	e.data["home"] = [b.x, b.y, b.z]
	e.rt.erase("home_fail")
	_particles(e, "happy_villager")


## Every 20 ticks: the claimed bed must still be there (when its chunk is loaded).
static func _check_home(em, e) -> void:
	var hp := _home_of(e)
	if hp == NONE:
		return
	var w = em.world
	if w.cm != null and w.cm.get_chunk(hp.x >> 4, hp.z >> 4) == null:
		return
	if is_bed_head(w.state_at(hp.x, hp.y, hp.z)):
		return
	e.data.erase("home")
	if e.data.has("sleep"):
		wake(em, e)


## True while a villager sleeps in the bed (Java BedBlock OCCUPIED; kept here, not as a block state change).
static func bed_occupied(hp: Vector3i) -> bool:
	var s = _sleepers.get(hp)
	if s == null:
		return false
	if s.dead or not (s.data.get("sleep") is Array):
		_sleepers.erase(hp)
		return false
	return true


## Rest time: walk home; within 2 blocks of the bed's centre lie down (not within 100 ticks of getting up - Java
## SleepInBed; not while the bed is taken). INF: no bed - keep wandering.
static func _bed_goal(em, e, now: int) -> Vector3:
	if e.data.has("sleep"):
		return STAY
	var hp := _home_of(e)
	if hp == NONE or e.rt.has("bell_home"):
		return Vector3.INF
	var c := Vector3(hp) + Vector3(0.5, 0.5, 0.5)
	if c.distance_to(e.pos) <= SLEEP_REACH:
		var p = em.world.get("player")
		var by_player: bool = p != null and p.sleeping and p.bed_pos == hp
		if now - int(e.rt.get("woken", -1000)) >= 100 and not bed_occupied(hp) and not by_player:
			start_sleep(em, e, hp)
		return STAY
	# a path that ended short of the bed several times: the bed is forgotten (Java drops an unreachable home)
	if MobControl.nav_idle(e) and e.nav_cd <= 0 and e.nav_goal == hp:
		var f := int(e.rt.get("home_fail", 0)) + 1
		e.rt["home_fail"] = f
		if f > 3:   # (the wiki gives no number: 3 tries, as for job sites)
			e.data.erase("home")
			e.rt.erase("home_fail")
			return Vector3.INF
	return Vector3(hp) + Vector3(0.5, 0.0, 0.5)


## Lies down in the bed (Java LivingEntity.startSleeping / setPosToBed: on the head half, 0.6875 up).
static func start_sleep(em, e, hp: Vector3i) -> void:
	var st: int = em.world.state_at(hp.x, hp.y, hp.z)
	e.data["sleep"] = [hp.x, hp.y, hp.z]
	e.data["last_slept"] = int(em.world.game_time)
	e.rt["sleep_dir"] = maxi(0, FACINGS.find(Res.blocks.get_prop(st, "facing")))
	e.rt.erase("home_fail")
	_sleepers[hp] = e
	e.pos = Vector3(hp) + Vector3(0.5, 0.6875, 0.5)
	e.prev = e.pos
	e.vel = Vector3.ZERO
	e.w = SLEEP_SIZE
	e.h = SLEEP_SIZE
	e.has_target = false
	MobControl.nav_stop(e)


## Every tick while asleep (EntityManager._tick_mob): true = still asleep (no AI this tick). Wakes at 10 (morning),
## for a bell, a raid, or when the bed is gone.
static func sleep_tick(em, e) -> bool:
	var s: Array = e.data["sleep"]
	var hp := Vector3i(int(s[0]), int(s[1]), int(s[2]))
	var w = em.world
	var t := int(w.day_time) % 24000
	if (t >= WAKE_T and t < NIGHT) or e.rt.has("bell_home"):
		wake(em, e)
		return false
	var fresh: bool = not e.rt.has("sleep_dir")   # (asleep in a loaded save)
	if fresh or (int(w.game_time) + e.uid) % 20 == 0:
		# the bed (when its chunk is loaded) and raids, every 20 ticks
		var st: int = w.state_at(hp.x, hp.y, hp.z)
		var loaded: bool = w.cm == null or w.cm.get_chunk(hp.x >> 4, hp.z >> 4) != null
		var rd := raid_at(w, e.pos)
		if (loaded and not is_bed_head(st)) or (not rd.is_empty() and str(rd.get("state", "")) != "over"):
			wake(em, e)   # (bed gone; a raid replaces the rest: up and hiding)
			return false
		if fresh:
			e.rt["sleep_dir"] = maxi(0, FACINGS.find(Res.blocks.get_prop(st, "facing"))) if st > 0 else 0
			e.w = SLEEP_SIZE
			e.h = SLEEP_SIZE
	if _sleepers.get(hp) != e:
		_sleepers[hp] = e
	e.pos = Vector3(hp) + Vector3(0.5, 0.6875, 0.5)
	e.vel = Vector3.ZERO
	e.limb_amt = 0.0
	e.head_yaw = e.body_yaw
	e.head_pitch = 0.0
	return true


## Gets up (Java LivingEntity.stopSleeping): back to its size, standing beside the bed.
static func wake(em, e) -> void:
	var s = e.data.get("sleep")
	if not (s is Array):
		return
	var hp := Vector3i(int(s[0]), int(s[1]), int(s[2]))
	e.data.erase("sleep")
	e.rt.erase("sleep_dir")
	if _sleepers.get(hp) == e:
		_sleepers.erase(hp)
	var now := int(em.world.game_time)
	e.data["last_slept"] = now
	e.rt["woken"] = now
	var baby: bool = e.baby_age < 0
	e.w = float(e.def.get("baby_w", float(e.def["w"]) * 0.5)) if baby else float(e.def["w"])
	e.h = float(e.def.get("baby_h", float(e.def["h"]) * 0.5)) if baby else float(e.def["h"])
	e.pos = _stand_up(em.world, hp)
	e.prev = e.pos
	e.vel = Vector3.ZERO


## A player using a bed a villager sleeps in kicks the villager out (wiki Villager; the player does not lie down on that
## use - Java BedBlock). True when someone was woken.
static func kick_out(em, hp: Vector3i) -> bool:
	if not bed_occupied(hp):
		return false
	wake(em, _sleepers[hp])
	return true


## A free spot beside the bed (a side of the head, else of the foot: floor below, two free blocks), else on top of it.
## (The wiki gives no stand-up rule; Java BedBlock.findStandUpPosition is more elaborate.)
static func _stand_up(w, hp: Vector3i) -> Vector3:
	var st: int = w.state_at(hp.x, hp.y, hp.z)
	var f := FACINGS.find(Res.blocks.get_prop(st, "facing")) if st > 0 else -1
	var foot: Vector3i = hp - (FACING_VEC[f] as Vector3i) if f >= 0 else hp
	var fl := Res.blocks.st_flags
	for base in [hp, foot]:
		for d in FACING_VEC:
			var q: Vector3i = (base as Vector3i) + (d as Vector3i)
			if q == hp or q == foot:
				continue
			var below: int = w.state_at(q.x, q.y - 1, q.z)
			var a: int = w.state_at(q.x, q.y, q.z)
			var b: int = w.state_at(q.x, q.y + 1, q.z)
			if below > 0 and (fl[below] & BlockRegistry.F_COLLIDE) != 0 and (a <= 0 or (fl[a] & BlockRegistry.F_COLLIDE) == 0) and (b <= 0 or (fl[b] & BlockRegistry.F_COLLIDE) == 0):
				return Vector3(q) + Vector3(0.5, 0.0, 0.5)
	return Vector3(hp) + Vector3(0.5, 0.5625, 0.5)


# ------------------------------------------------------------------ raids

## The raid whose area (96 blocks around its centre) holds `at` ({} when none); any state, "over" included.
static func raid_at(w, at: Vector3) -> Dictionary:
	var lv = w.get("level")
	if not (lv is Dictionary):
		return {}
	var r = (lv as Dictionary).get("raid")
	if not (r is Dictionary):
		return {}
	var c = r.get("center")
	if not (c is Array) or Vector3(float(c[0]), float(c[1]), float(c[2])).distance_squared_to(at) > RAID_R * RAID_R:
		return {}
	return r


## During a raid: before the first wave run to the meeting bell and ring it (the first villager within reach); then hide
## in a house - the villager's bed within 32 blocks, else the nearest bed - and stay there (fleeing raiders comes first:
## EntityManager). After a victory, cheer (entity.villager.celebrate; how often is not on the wiki: 1 in 100 per tick).
static func _raid_goal(em, e, rd: Dictionary) -> Vector3:
	var w = em.world
	var now := int(w.game_time)
	if str(rd.get("state", "")) == "over":
		if bool(rd.get("victory", false)) and em.rng.randi_range(0, 99) == 0:
			Audio.play("entity.villager.celebrate", e.pos, "Neutral", 1.0, em.rng.randf_range(0.8, 1.2))
		return Vector3.INF
	if e.data.has("sleep"):
		wake(em, e)
	if int(rd.get("wave", 0)) == 0 and not rd.has("rang") and e.baby_age >= 0:
		if now >= int(e.rt.get("bell_t", 0)):
			e.rt["bell_t"] = now + 200 + em.rng.randi_range(0, 99)
			e.rt["bell"] = _nearest(w, e.pos, MEET_R, "bell", "", {})
		var bell: Vector3i = e.rt.get("bell", NONE)
		if bell != NONE:
			if (Vector3(bell) + Vector3(0.5, 0.5, 0.5)).distance_to(e.pos + Vector3(0, 0.5, 0)) > BELL_RING_R:
				return Vector3(bell) + Vector3(0.5, 0.0, 0.5)
			rd["rang"] = true
			Bells.ring(w, bell, Vector3i.ZERO)   # (sends the villagers within 32 blocks to a bed)
	var hide = e.rt.get("hide")
	if not (hide is Vector3i) or ((now + e.uid) % 20 == 0 and not is_bed_head(w.state_at(hide.x, hide.y, hide.z))):
		var hp := _home_of(e)
		if hp == NONE or (Vector3(hp) + Vector3(0.5, 0.0, 0.5)).distance_to(e.pos) > HIDE_R:
			hp = _nearest(w, e.pos, HIDE_R, "bed", "", {})
		if hp == NONE:
			e.rt.erase("hide")
			return Vector3.INF
		e.rt["hide"] = hp
		hide = hp
	var hv := Vector3(hide) + Vector3(0.5, 0.0, 0.5)
	if Vector2(hv.x - e.pos.x, hv.z - e.pos.z).length() > 1.5 or absf(hv.y - e.pos.y) > 2.0:
		return hv
	return STAY


# ------------------------------------------------------------------ iron golem summoning

## Java GolemSensor (wiki Iron Golem): every 10 s, an iron golem within 16 blocks on each axis counts as seen for 30 s.
static func _golem_sense(em, e, now: int) -> void:
	e.rt["golem_scan"] = now + GOLEM_SCAN_T
	for g in MobBehaviors.near_list(em, "iron_golem"):
		var d: Vector3 = g.pos - e.pos
		if not g.dead and absf(d.x) <= GOLEM_SCAN_R and absf(d.y) <= GOLEM_SCAN_R and absf(d.z) <= GOLEM_SCAN_R:
			e.rt["golem_seen"] = now
			return


## wiki Iron Golem: slept within the last 20 minutes (asleep counts) and no golem seen / summoned near it in 30 s.
static func wants_golem(e, now: int) -> bool:
	if not e.data.has("sleep"):
		if not e.data.has("last_slept") or now - int(e.data["last_slept"]) >= GOLEM_SLEPT_T:
			return false
	return not e.rt.has("golem_seen") or now - int(e.rt["golem_seen"]) >= GOLEM_SEEN_T


## A villager tries to summon an iron golem (min_n: 5 gossiping, 3 panicking): enough willing villagers within 10
## blocks on each axis (counted up to 5), a spawn spot found; the villagers there then count the golem as seen.
static func summon_golem(em, e, min_n: int) -> bool:
	var now := int(em.world.game_time)
	var group: Array = []
	var n := 0
	for v in MobBehaviors.near_list(em, "villager"):
		if v.dead:
			continue
		var d: Vector3 = v.pos - e.pos
		if absf(d.x) > GOLEM_GROUP_R or absf(d.y) > GOLEM_GROUP_R or absf(d.z) > GOLEM_GROUP_R:
			continue
		group.append(v)
		if n < 5 and wants_golem(v, now):
			n += 1
	if n < min_n:
		return false
	var at := _golem_spot(em, e)
	if at == Vector3.INF:
		return false
	var g = em.spawn_mob("iron_golem", at)
	if g == null:
		return false
	for v in group:
		v.rt["golem_seen"] = now
	return true


## wiki Iron Golem: up to 10 tries in the 17 x 13 x 17 box around the villager - a random column (x / z +-8), the
## topmost air or liquid block (from 6 above down to 6 below) on a solid one; the block and the two above it not full
## blocks or rails, the two above not water, no entity in the golem's box. (Redstone power is not checked here.)
static func _golem_spot(em, e) -> Vector3:
	var w = em.world
	var fl := Res.blocks.st_flags
	var c := Vector3i(e.pos.floor())
	var gd := MobRegistry.get_def("iron_golem")
	var gw := float(gd.get("w", 1.4)) * 0.5
	var gh := float(gd.get("h", 2.7))
	for i in 10:
		var x: int = c.x + em.rng.randi_range(-8, 8)
		var z: int = c.z + em.rng.randi_range(-8, 8)
		var fy := -99999
		for y in range(c.y + 6, c.y - 7, -1):
			var a: int = w.state_at(x, y, z)
			var b: int = w.state_at(x, y - 1, z)
			if (a <= 0 or (fl[a] & (BlockRegistry.F_AIR | BlockRegistry.F_LIQUID)) != 0) and b > 0 and (fl[b] & BlockRegistry.F_COLLIDE) != 0:
				fy = y
				break
		if fy == -99999:
			continue
		var ok := true
		for dy in 3:
			var s: int = w.state_at(x, fy + dy, z)
			if s <= 0:
				continue
			if (fl[s] & BlockRegistry.F_FULL_SHAPE) != 0 or Res.blocks.name_of(s).ends_with("rail"):
				ok = false
			elif dy > 0 and (fl[s] & BlockRegistry.F_LIQUID) != 0 and (fl[s] & BlockRegistry.F_LAVA) == 0:
				ok = false
		if not ok:
			continue
		var pos := Vector3(x + 0.5, fy, z + 0.5)
		var blocked := false
		for o in em.ents:
			if o.dead or o.kind != "mob":
				continue
			var ow: float = o.w * 0.5
			if o.pos.x - ow < pos.x + gw and o.pos.x + ow > pos.x - gw and o.pos.z - ow < pos.z + gw and o.pos.z + ow > pos.z - gw and o.pos.y < pos.y + gh and o.pos.y + o.h > pos.y:
				blocked = true
				break
		if not blocked:
			return pos
	return Vector3.INF


# ------------------------------------------------------------------ curing

## Golden apple on a zombie villager with Weakness (EntityManager.player_interact). True when the cure started.
static func try_cure(em, e, p: Player, held: ItemStack) -> bool:
	if e.id != "zombie_villager" or held.is_empty() or held.name() != "golden_apple" or e.data.has("cure"):
		return false
	if not MobBehaviors.has_effect(e, "weakness"):
		return false
	if not p.is_creative():
		p.inventory.consume_held()
	var t: int = em.rng.randi_range(3600, 6000)
	e.data["cure"] = t
	e.data["curer"] = true   # (the local player: the gossip goes to it)
	e.persistent = true      # wiki: converting zombie villagers do not despawn
	(e.data["fx"] as Dictionary).erase("weakness")
	MobBehaviors.add_effect(e, "strength", 0, t)
	Audio.play("entity.zombie_villager.cure", e.pos, "Hostile", 1.0 + randf(), 0.3 + randf() * 0.7)
	return true


## Every tick while curing.
static func cure_tick(em, e) -> void:
	var t := int(e.data["cure"])
	var dec := 1
	if em.rng.randf() < 0.01:
		var n := 0
		var b := Res.blocks
		var c := Vector3i(floori(e.pos.x), floori(e.pos.y), floori(e.pos.z))
		for dx in range(-4, 5):
			for dy in range(-4, 5):
				for dz in range(-4, 5):
					if n >= 14:
						break
					var st: int = em.world.state_at(c.x + dx, c.y + dy, c.z + dz)
					if st <= 0:
						continue
					var nm := b.name_of(st)
					if nm == "iron_bars" or nm.ends_with("_bed"):
						n += 1
						if em.rng.randf() < 0.3:
							dec += 1
	t -= dec
	if t > 0:
		e.data["cure"] = t
		return
	_convert(em, e)


static func _convert(em, e) -> void:
	var v = em.spawn_mob("villager", e.pos, e.baby_age < 0)
	if v == null:
		return
	for k in ["prof", "vtype", "level", "offers", "vxp", "gossip", "CustomName"]:
		if e.data.has(k):
			v.data[k] = e.data[k]
	if str(v.data.get("prof", "")) == "":
		v.data["prof"] = "none"
	v.yaw = e.yaw
	v.body_yaw = e.body_yaw
	v.baby_age = e.baby_age
	# wiki Zombie Villager: picked-up equipment drops when cured
	for hk in ["held", "offhand"]:
		var hn := str(e.data.get(hk, ""))
		if hn != "" and Res.items.id(hn) > 0:
			em.spawn_item(e.pos + Vector3(0, 1, 0), ItemStack.named(hn, 1))
	MobBehaviors.add_effect(v, "nausea", 0, 200)
	if e.data.get("curer", false):
		Trading.gossip(v, "major_positive")
		Trading.gossip(v, "minor_positive")
		if em.world.get("advancements") != null:
			em.world.advancements.trigger("cured_zombie_villager", {})
	MobBehaviors.villager_layers(v)
	Audio.play("entity.zombie_villager.converted", e.pos, "Hostile", 2.0, randf_range(0.8, 1.2))
	em._remove(e)


## wiki Zombie Villager: naturally spawned ones "have a random profession, and can also spawn with unemployed or
## nitwit outfits".
static func zombie_profession(e, rng: RandomNumberGenerator) -> void:
	var all: Array = Trading.PROFESSIONS + ["none"]
	e.data["prof"] = all[rng.randi_range(0, all.size() - 1)]
