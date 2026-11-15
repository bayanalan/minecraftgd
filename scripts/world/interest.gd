## Interest — which block-change listeners have anything to do near a position (exact skip filter, no behaviour
## change). Every set_block used to run the redstone consumer / wire scan (49 + lookups), the observer scan and the coral
## scan around the changed block, ~60 world lookups per change even with no redstone, observer or coral anywhere (a
## flowing-water front in freshly generated terrain changes hundreds of blocks per tick). Each section caches the OR of
## its palette's interest bits (palettes only grow until replaced; stale entries make the filter conservative), so a
## change only calls the listeners whose blocks exist within reach.
class_name Interest

const WIRE := 1        # redstone wire (Redstone._relevance 1)
const CONSUMER := 2    # reacts in Redstone._update_consumer (Redstone._relevance 2)
const OBSERVER := 4
const CORAL := 8
const RS_INERT := 16   # air / cave air / void air / water / lava: never a power source, conductor or redstone component
const ROD := 128      # lightning rods (BlockEntities.index_chunk indexes rods of loaded sections)
const SENSOR := 32    # pressure plates and tripwire strings (Sensors.tick skips entity boxes far from any)
const POI := 64       # villager job site blocks, bells and beds (Villagers.index_chunk)

static var _tab := PackedByteArray()


static func table() -> PackedByteArray:
	var b := Res.blocks
	if _tab.size() != b.total_states:
		var t := PackedByteArray()
		t.resize(b.total_states)
		var obs := b.block_id("observer")
		var rods := {}
		var sens := {}
		var poi := {}
		for bi in b.names.size():
			if b.names[bi].ends_with("lightning_rod"):
				rods[bi] = true
			if b.names[bi] == "tripwire" or Sensors.is_plate(b.names[bi]):
				sens[bi] = true
			if Villagers.is_poi_block(b.names[bi]):
				poi[bi] = true
		for s in range(1, b.total_states):
			var m := Redstone._relevance_of(s) & 3
			if b.st_block[s] == obs:
				m |= OBSERVER
			if Growth.is_coral_state(s):
				m |= CORAL
			var bn: String = b.names[b.st_block[s]]
			if bn == "air" or bn == "cave_air" or bn == "void_air" or bn == "water" or bn == "lava":
				m |= RS_INERT
			if rods.has(b.st_block[s]):
				m |= ROD
			if sens.has(b.st_block[s]):
				m |= SENSOR
			if poi.has(b.st_block[s]):
				m |= POI
			t[s] = m
		_tab = t
	return _tab


static func section_mask(sec: Chunk.Section) -> int:
	if sec.rs < 0 or sec.rs_n != sec.pal.size():
		var t := table()
		var m := 0
		for s in sec.pal:
			if s > 0 and s < t.size():
				m |= t[s]
		sec.rs = m
		sec.rs_n = sec.pal.size()
	return sec.rs


## A change between two redstone-inert states (fluid flow, air) cannot change any power level or wire connection.
static func rs_inert_change(old: int, st: int) -> bool:
	var t := table()
	var n := t.size()
	return (old == 0 or (old > 0 and old < n and (t[old] & RS_INERT) != 0)) and (st == 0 or (st > 0 and st < n and (t[st] & RS_INERT) != 0))


## Interest bits of one state (0 outside the table).
static func of(st: int) -> int:
	var t := table()
	return t[st] if st > 0 and st < t.size() else 0


## OR of the interest bits of every loaded section within r blocks of p (all bits when p's own chunk is not in the
## chunk table: no data to decide on, e.g. test worlds).
static func near(world, p: Vector3i, r: int) -> int:
	var cmv = world.cm
	var chunks = cmv.get("chunks") if cmv != null else null
	if not (chunks is Dictionary) or not (chunks as Dictionary).has(((p.x >> 4) << 32) | ((p.z >> 4) & 0xFFFFFFFF)):
		return 0xFF
	var s0 := clampi((p.y - r - Coords.MIN_Y) >> 4, 0, Coords.SECTIONS - 1)
	var s1 := clampi((p.y + r - Coords.MIN_Y) >> 4, 0, Coords.SECTIONS - 1)
	var m := 0
	for cx in range((p.x - r) >> 4, ((p.x + r) >> 4) + 1):
		for cz in range((p.z - r) >> 4, ((p.z + r) >> 4) + 1):
			var ch: Chunk = chunks.get((cx << 32) | (cz & 0xFFFFFFFF))
			if ch == null or ch.sections.is_empty():
				continue
			for s in range(s0, s1 + 1):
				m |= section_mask(ch.sections[s])
	return m
