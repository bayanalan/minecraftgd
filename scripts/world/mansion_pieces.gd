class_name MansionPieces
extends RefCounted
## Java WoodlandMansionStructure + WoodlandMansionPieces: the 11 x 11 MansionGrid (entrance, recursive corridors,
## edge cleanup, rooms identified as 1x1 / 1x2 / 2x2 with door and stairs flags, the third-floor grid grown from a
## staircase room), then MansionPiecePlacer: outer walls traced around each floor, roofs, corridor floors / carpets,
## indoor walls and doors and one room template per room from the floor's room collection. Every piece is a
## woodland_mansion/<name> template (BlockIgnoreProcessor.STRUCTURE_BLOCK only - template air is placed; rotation +
## Mirror; entities ignored). Data markers: chests (loot chests/woodland_mansion), Mage (evoker), Warrior (vindicator),
## Group of Allays. afterPlace fills cobblestone under the structure's bottom layer down to the ground.

const STEP := {"north": Vector2i(0, -1), "south": Vector2i(0, 1), "west": Vector2i(-1, 0), "east": Vector2i(1, 0), "up": Vector2i.ZERO}
const DIR3 := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0), "up": Vector3i(0, 1, 0)}
const HORIZ := ["north", "east", "south", "west"]      # Direction.Plane.HORIZONTAL
const FROM_2D := ["south", "west", "north", "east"]    # Direction.from2DDataValue
const CW := {"north": "east", "east": "south", "south": "west", "west": "north"}
const CCW := {"north": "west", "west": "south", "south": "east", "east": "north"}
const OPP := {"north": "south", "south": "north", "east": "west", "west": "east", "up": "down", "down": "up"}

const CORRIDOR := 1
const ROOM := 2
const START_ROOM := 3
const BLOCKED := 5
const ROOM_1X1 := 65536
const ROOM_1X2 := 131072
const ROOM_2X2 := 262144
const ORIGIN_FLAG := 1048576
const DOOR_FLAG := 2097152
const STAIRS_FLAG := 4194304
const CORRIDOR_FLAG := 8388608
const TYPE_MASK := 983040
const ID_MASK := 65535

const MIRROR_NONE := 0
const FRONT_BACK := 1
const LEFT_RIGHT := 2


## WoodlandMansionPieces.SimpleGrid (column-major like Java's int[width][height]).
class Grid:
	var w: int
	var h: int
	var outside: int
	var g := PackedInt32Array()

	func _init(pw: int, ph: int, po: int) -> void:
		w = pw
		h = ph
		outside = po
		g.resize(w * h)

	func put(x: int, y: int, v: int) -> void:
		if x >= 0 and x < w and y >= 0 and y < h:
			g[x * h + y] = v

	func fill(x0: int, y0: int, x1: int, y1: int, v: int) -> void:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				put(x, y, v)

	func at(x: int, y: int) -> int:
		return g[x * h + y] if x >= 0 and x < w and y >= 0 and y < h else outside

	func setif(x: int, y: int, old: int, v: int) -> void:
		if at(x, y) == old:
			put(x, y, v)

	func edges_to(x: int, y: int, v: int) -> bool:
		return at(x - 1, y) == v or at(x + 1, y) == v or at(x, y + 1) == v or at(x, y - 1) == v


static func is_house(g: Grid, x: int, y: int) -> bool:
	var v := g.at(x, y)
	return v == 1 or v == 2 or v == 3 or v == 4


## WoodlandMansionPieces.MansionGrid
class MGrid:
	var r: RandomSources.LegacyRandom
	var base: Grid
	var third: Grid
	var rooms: Array = []
	var ex := 7
	var ey := 4

	func _init(rr: RandomSources.LegacyRandom) -> void:
		r = rr
		base = Grid.new(11, 11, 5)
		base.fill(ex, ey, ex + 1, ey + 1, 3)
		base.fill(ex - 1, ey, ex - 1, ey + 1, 2)
		base.fill(ex + 2, ey - 2, ex + 3, ey + 3, 5)
		base.fill(ex + 1, ey - 2, ex + 1, ey - 1, 1)
		base.fill(ex + 1, ey + 2, ex + 1, ey + 3, 1)
		base.put(ex - 1, ey - 1, 1)
		base.put(ex - 1, ey + 2, 1)
		base.fill(0, 0, 11, 1, 5)
		base.fill(0, 9, 11, 11, 5)
		corridor(base, ex, ey - 2, "west", 6)
		corridor(base, ex, ey + 3, "west", 6)
		corridor(base, ex - 2, ey - 1, "west", 3)
		corridor(base, ex - 2, ey + 2, "west", 3)
		while clean_edges(base):
			pass
		rooms = [Grid.new(11, 11, 5), Grid.new(11, 11, 5), Grid.new(11, 11, 5)]
		identify_rooms(base, rooms[0])
		identify_rooms(base, rooms[1])
		(rooms[0] as Grid).fill(ex + 1, ey, ex + 1, ey + 1, CORRIDOR_FLAG)
		(rooms[1] as Grid).fill(ex + 1, ey, ex + 1, ey + 1, CORRIDOR_FLAG)
		third = Grid.new(base.w, base.h, 5)
		setup_third_floor()
		identify_rooms(third, rooms[2])

	func is_room_id(x: int, y: int, floor_i: int, id: int) -> bool:
		return ((rooms[floor_i] as Grid).at(x, y) & ID_MASK) == id

	func get_1x2_dir(x: int, y: int, floor_i: int, id: int) -> String:
		for d in HORIZ:
			var s: Vector2i = STEP[d]
			if is_room_id(x + s.x, y + s.y, floor_i, id):
				return d
		return ""

	func corridor(g: Grid, x: int, y: int, d: String, length: int) -> void:
		if length <= 0:
			return
		var s: Vector2i = STEP[d]
		g.put(x, y, CORRIDOR)
		g.setif(x + s.x, y + s.y, 0, CORRIDOR)
		for i in 8:
			var d2: String = FROM_2D[r.next_int_bound(4)]
			if d2 != OPP[d] and (d2 != "east" or not r.next_bool()):
				var s2: Vector2i = STEP[d2]
				var j := x + s.x
				var k := y + s.y
				if g.at(j + s2.x, k + s2.y) == 0 and g.at(j + s2.x * 2, k + s2.y * 2) == 0:
					corridor(g, x + s.x + s2.x, y + s.y + s2.y, d2, length - 1)
					break
		var s3: Vector2i = STEP[CW[d]]
		var s4: Vector2i = STEP[CCW[d]]
		g.setif(x + s3.x, y + s3.y, 0, ROOM)
		g.setif(x + s4.x, y + s4.y, 0, ROOM)
		g.setif(x + s.x + s3.x, y + s.y + s3.y, 0, ROOM)
		g.setif(x + s.x + s4.x, y + s.y + s4.y, 0, ROOM)
		g.setif(x + s.x * 2, y + s.y * 2, 0, ROOM)
		g.setif(x + s3.x * 2, y + s3.y * 2, 0, ROOM)
		g.setif(x + s4.x * 2, y + s4.y * 2, 0, ROOM)

	func clean_edges(g: Grid) -> bool:
		var changed := false
		for i in g.h:
			for j in g.w:
				if g.at(j, i) != 0:
					continue
				var k := int(MansionPieces.is_house(g, j + 1, i)) + int(MansionPieces.is_house(g, j - 1, i)) + int(MansionPieces.is_house(g, j, i + 1)) + int(MansionPieces.is_house(g, j, i - 1))
				if k >= 3:
					g.put(j, i, ROOM)
					changed = true
				elif k == 2:
					var l := int(MansionPieces.is_house(g, j + 1, i + 1)) + int(MansionPieces.is_house(g, j - 1, i + 1)) + int(MansionPieces.is_house(g, j + 1, i - 1)) + int(MansionPieces.is_house(g, j - 1, i - 1))
					if l <= 1:
						g.put(j, i, ROOM)
						changed = true
		return changed

	func setup_third_floor() -> void:
		var cand: Array = []
		var g1: Grid = rooms[1]
		for i in third.h:
			for j in third.w:
				var k := g1.at(j, i)
				if (k & TYPE_MASK) == ROOM_1X2 and (k & DOOR_FLAG) == DOOR_FLAG:
					cand.append(Vector2i(j, i))
		if cand.is_empty():
			third.fill(0, 0, third.w, third.h, BLOCKED)
			return
		var t: Vector2i = cand[r.next_int_bound(cand.size())]
		var k0 := g1.at(t.x, t.y)
		g1.put(t.x, t.y, k0 | STAIRS_FLAG)
		var d := get_1x2_dir(t.x, t.y, 1, k0 & ID_MASK)
		if d == "":   # (a 1x2 room always has its second cell beside it; Java would throw here)
			third.fill(0, 0, third.w, third.h, BLOCKED)
			return
		var s: Vector2i = STEP[d]
		var l := t.x + s.x
		var m := t.y + s.y
		for n in third.h:
			for o in third.w:
				if not MansionPieces.is_house(base, o, n):
					third.put(o, n, BLOCKED)
				elif o == t.x and n == t.y:
					third.put(o, n, START_ROOM)
				elif o == l and n == m:
					third.put(o, n, START_ROOM)
					(rooms[2] as Grid).put(o, n, CORRIDOR_FLAG)
		var dirs: Array = []
		for d2 in HORIZ:
			var s2: Vector2i = STEP[d2]
			if third.at(l + s2.x, m + s2.y) == 0:
				dirs.append(d2)
		if dirs.is_empty():
			third.fill(0, 0, third.w, third.h, BLOCKED)
			g1.put(t.x, t.y, k0)
			return
		var d3: String = dirs[r.next_int_bound(dirs.size())]
		var s3: Vector2i = STEP[d3]
		corridor(third, l + s3.x, m + s3.y, d3, 4)
		while clean_edges(third):
			pass

	func identify_rooms(g: Grid, fr: Grid) -> void:
		var cells: Array = []
		for i in g.h:
			for j in g.w:
				if g.at(j, i) == ROOM:
					cells.append(Vector2i(j, i))
		cells = Structures._shuffled(cells, r)   # Util.shuffle
		var id := 10
		for cv in cells:
			var k: int = cv.x
			var l: int = cv.y
			if fr.at(k, l) != 0:
				continue
			var m := k
			var n := k
			var o := l
			var p := l
			var q := ROOM_1X1
			if fr.at(k + 1, l) == 0 and fr.at(k, l + 1) == 0 and fr.at(k + 1, l + 1) == 0 and g.at(k + 1, l) == ROOM and g.at(k, l + 1) == ROOM and g.at(k + 1, l + 1) == ROOM:
				n = k + 1
				p = l + 1
				q = ROOM_2X2
			elif fr.at(k - 1, l) == 0 and fr.at(k, l + 1) == 0 and fr.at(k - 1, l + 1) == 0 and g.at(k - 1, l) == ROOM and g.at(k, l + 1) == ROOM and g.at(k - 1, l + 1) == ROOM:
				m = k - 1
				p = l + 1
				q = ROOM_2X2
			elif fr.at(k - 1, l) == 0 and fr.at(k, l - 1) == 0 and fr.at(k - 1, l - 1) == 0 and g.at(k - 1, l) == ROOM and g.at(k, l - 1) == ROOM and g.at(k - 1, l - 1) == ROOM:
				m = k - 1
				o = l - 1
				q = ROOM_2X2
			elif fr.at(k + 1, l) == 0 and g.at(k + 1, l) == ROOM:
				n = k + 1
				q = ROOM_1X2
			elif fr.at(k, l + 1) == 0 and g.at(k, l + 1) == ROOM:
				p = l + 1
				q = ROOM_1X2
			elif fr.at(k - 1, l) == 0 and g.at(k - 1, l) == ROOM:
				m = k - 1
				q = ROOM_1X2
			elif fr.at(k, l - 1) == 0 and g.at(k, l - 1) == ROOM:
				o = l - 1
				q = ROOM_1X2
			var rx := m if r.next_bool() else n
			var ry := o if r.next_bool() else p
			var t := DOOR_FLAG
			if not g.edges_to(rx, ry, CORRIDOR):
				rx = n if rx == m else m
				ry = p if ry == o else o
				if not g.edges_to(rx, ry, CORRIDOR):
					ry = p if ry == o else o
					if not g.edges_to(rx, ry, CORRIDOR):
						rx = n if rx == m else m
						ry = p if ry == o else o
						if not g.edges_to(rx, ry, CORRIDOR):
							t = 0
							rx = m
							ry = o
			for u in range(o, p + 1):
				for v in range(m, n + 1):
					if v == rx and u == ry:
						fr.put(v, u, ORIGIN_FLAG | t | q | id)
					else:
						fr.put(v, u, q | id)
			id += 1


## Floor room collections: template name for a room of each kind on floor 0 / 1 / 2 (Java First / Second /
## ThirdFloorRoomCollection; the third floor uses the second floor's set).
static func room_name(floor_i: int, kind: String, r: RandomSources.LegacyRandom, stairs: bool = false) -> String:
	if floor_i == 0:
		match kind:
			"1x1":
				return "1x1_a" + str(r.next_int_bound(5) + 1)
			"1x1s":
				return "1x1_as" + str(r.next_int_bound(4) + 1)
			"1x2side":
				return "1x2_a" + str(r.next_int_bound(9) + 1)
			"1x2front":
				return "1x2_b" + str(r.next_int_bound(5) + 1)
			"1x2s":
				return "1x2_s" + str(r.next_int_bound(2) + 1)
			"2x2":
				return "2x2_a" + str(r.next_int_bound(4) + 1)
			"2x2s":
				return "2x2_s1"
	match kind:
		"1x1":
			return "1x1_b" + str(r.next_int_bound(4) + 1)
		"1x1s":
			return "1x1_as" + str(r.next_int_bound(4) + 1)
		"1x2side":
			return "1x2_c_stairs" if stairs else "1x2_c" + str(r.next_int_bound(4) + 1)
		"1x2front":
			return "1x2_d_stairs" if stairs else "1x2_d" + str(r.next_int_bound(5) + 1)
		"1x2s":
			return "1x2_se" + str(r.next_int_bound(1) + 1)
		"2x2":
			return "2x2_b" + str(r.next_int_bound(5) + 1)
	return "2x2_s1"


# ------------------------------------------------------------------ MansionPiecePlacer

var r: RandomSources.LegacyRandom
var pieces: Array = []
var start_x := 0
var start_y := 0
# PlacementData: position, rotation, wall type
var pd_pos := Vector3i.ZERO
var pd_rot := 0
var pd_wall := ""


static func rd(d: String, rot: int) -> Vector3i:
	return DIR3[StructureTemplate.rot_dir(d, rot)]


func _piece(name: String, pos: Vector3i, rot: int, mirror: int = MIRROR_NONE) -> void:
	var loc := "woodland_mansion/" + name
	var tpl := StructureTemplate.get_template(loc)
	if tpl == null:
		return
	var el := {"t": "single", "loc": loc, "legacy": false, "proj": "rigid", "procs": [], "markers": "woodland_mansion", "mirror": mirror, "noents": true}
	pieces.append({"el": el, "pos": pos, "rot": rot, "mirror": mirror, "box": tpl.box_m(pos, rot, mirror, Vector3i.ZERO)})


func _wall_piece(pd: Dictionary) -> void:
	_piece(str(pd["wall"]), pd["pos"] + rd("east", pd["rot"]) * 7, pd["rot"])
	pd["pos"] = pd["pos"] + rd("south", pd["rot"]) * 8


func _turn(pd: Dictionary) -> void:
	pd["pos"] = pd["pos"] + rd("south", pd["rot"]) * -1
	_piece("wall_corner", pd["pos"], pd["rot"])
	pd["pos"] = pd["pos"] + rd("south", pd["rot"]) * -7
	pd["pos"] = pd["pos"] + rd("west", pd["rot"]) * -6
	pd["rot"] = (int(pd["rot"]) + 1) % 4


func _inner_turn(pd: Dictionary) -> void:
	pd["pos"] = pd["pos"] + rd("south", pd["rot"]) * 6
	pd["pos"] = pd["pos"] + rd("east", pd["rot"]) * 8
	pd["rot"] = (int(pd["rot"]) + 3) % 4


func _outer_walls(pd: Dictionary, g: Grid, d0: String, sx: int, sy: int, ex: int, ey: int) -> void:
	var i := sx
	var j := sy
	var d := d0
	var guard := 0
	while true:
		guard += 1
		if guard > 4096:
			break
		var s: Vector2i = STEP[d]
		var sc: Vector2i = STEP[CCW[d]]
		if not is_house(g, i + s.x, j + s.y):
			_turn(pd)
			d = CW[d]
			if i != ex or j != ey or d0 != d:
				_wall_piece(pd)
		elif is_house(g, i + s.x, j + s.y) and is_house(g, i + s.x + sc.x, j + s.y + sc.y):
			_inner_turn(pd)
			i += s.x
			j += s.y
			d = CCW[d]
		else:
			i += s.x
			j += s.y
			if i != ex or j != ey or d0 != d:
				_wall_piece(pd)
		if i == ex and j == ey and d0 == d:
			break


func _cell(base: Vector3i, rot: int, i: int, j: int, east_extra: int = 0) -> Vector3i:
	return base + rd("south", rot) * (8 + (i - start_y) * 8) + rd("east", rot) * (east_extra + (j - start_x) * 8)


func _roof(pos: Vector3i, rot: int, g: Grid, up: Grid) -> void:
	for i in g.h:
		for j in g.w:
			var bp := _cell(pos, rot, i, j)
			var covered := up != null and is_house(up, j, i)
			if is_house(g, j, i) and not covered:
				_piece("roof", bp + Vector3i(0, 3, 0), rot)
				if not is_house(g, j + 1, i):
					_piece("roof_front", bp + rd("east", rot) * 6, rot)
				if not is_house(g, j - 1, i):
					_piece("roof_front", bp + rd("east", rot) * 0 + rd("south", rot) * 7, (rot + 2) % 4)
				if not is_house(g, j, i - 1):
					_piece("roof_front", bp + rd("west", rot) * 1, (rot + 3) % 4)
				if not is_house(g, j, i + 1):
					_piece("roof_front", bp + rd("east", rot) * 6 + rd("south", rot) * 6, (rot + 1) % 4)
	if up != null:
		for i in g.h:
			for j in g.w:
				var bp := _cell(pos, rot, i, j)
				if is_house(g, j, i) and is_house(up, j, i):
					if not is_house(g, j + 1, i):
						_piece("small_wall", bp + rd("east", rot) * 7, rot)
					if not is_house(g, j - 1, i):
						_piece("small_wall", bp + rd("west", rot) * 1 + rd("south", rot) * 6, (rot + 2) % 4)
					if not is_house(g, j, i - 1):
						_piece("small_wall", bp + rd("west", rot) * 0 + rd("north", rot) * 1, (rot + 3) % 4)
					if not is_house(g, j, i + 1):
						_piece("small_wall", bp + rd("east", rot) * 6 + rd("south", rot) * 7, (rot + 1) % 4)
					if not is_house(g, j + 1, i):
						if not is_house(g, j, i - 1):
							_piece("small_wall_corner", bp + rd("east", rot) * 7 + rd("north", rot) * 2, rot)
						if not is_house(g, j, i + 1):
							_piece("small_wall_corner", bp + rd("east", rot) * 8 + rd("south", rot) * 7, (rot + 1) % 4)
					if not is_house(g, j - 1, i):
						if not is_house(g, j, i - 1):
							_piece("small_wall_corner", bp + rd("west", rot) * 2 + rd("north", rot) * 1, (rot + 3) % 4)
						if not is_house(g, j, i + 1):
							_piece("small_wall_corner", bp + rd("west", rot) * 1 + rd("south", rot) * 8, (rot + 2) % 4)
	for i in g.h:
		for j in g.w:
			var bp := _cell(pos, rot, i, j)
			var covered := up != null and is_house(up, j, i)
			if is_house(g, j, i) and not covered:
				if not is_house(g, j + 1, i):
					var bp2 := bp + rd("east", rot) * 6
					if not is_house(g, j, i + 1):
						_piece("roof_corner", bp2 + rd("south", rot) * 6, rot)
					elif is_house(g, j + 1, i + 1):
						_piece("roof_inner_corner", bp2 + rd("south", rot) * 5, rot)
					if not is_house(g, j, i - 1):
						_piece("roof_corner", bp2, (rot + 3) % 4)
					elif is_house(g, j + 1, i - 1):
						_piece("roof_inner_corner", bp + rd("east", rot) * 9 + rd("north", rot) * 2, (rot + 1) % 4)
				if not is_house(g, j - 1, i):
					var bp3 := bp + rd("east", rot) * 0 + rd("south", rot) * 0
					if not is_house(g, j, i + 1):
						_piece("roof_corner", bp3 + rd("south", rot) * 6, (rot + 1) % 4)
					elif is_house(g, j - 1, i + 1):
						_piece("roof_inner_corner", bp3 + rd("south", rot) * 8 + rd("west", rot) * 3, (rot + 3) % 4)
					if not is_house(g, j, i - 1):
						_piece("roof_corner", bp3, (rot + 2) % 4)
					elif is_house(g, j - 1, i - 1):
						_piece("roof_inner_corner", bp3 + rd("south", rot) * 1, (rot + 2) % 4)


## Rotation of a 1x1 room: Java addRoom1x1 (the room faces its door; a room without a door is a secret room).
func _room_1x1(pos: Vector3i, rot: int, d: String, floor_i: int) -> void:
	var rot2 := 0
	var name := room_name(floor_i, "1x1", r)
	if d != "east":
		if d == "north":
			rot2 = 3
		elif d == "south":
			rot2 = 1
		elif d == "west":
			rot2 = 2
		else:
			name = room_name(floor_i, "1x1s", r)
	# StructureTemplate.getZeroPositionWithTransform((1, 0, 0), NONE, rot2, 7, 7), then BlockPos.rotate(rotation)
	var zp := Vector3i(1, 0, 0)
	match rot2:
		3:
			zp = zp + Vector3i(0, 0, 6)
		1:
			zp = zp + Vector3i(6, 0, 0)
		2:
			zp = zp + Vector3i(6, 0, 6)
	rot2 = (rot2 + rot) % 4
	zp = StructureTemplate.transform(zp, rot)
	_piece(name, pos + Vector3i(zp.x, 0, zp.z), rot2)


func _room_1x2(pos: Vector3i, rot: int, front: String, side: String, floor_i: int, stairs: bool) -> void:
	var E := rd("east", rot)
	var S := rd("south", rot)
	var W := rd("west", rot)
	var N := rd("north", rot)
	if side == "east" and front == "south":
		_piece(room_name(floor_i, "1x2side", r, stairs), pos + E, rot)
	elif side == "east" and front == "north":
		_piece(room_name(floor_i, "1x2side", r, stairs), pos + E + S * 6, rot, LEFT_RIGHT)
	elif side == "west" and front == "north":
		_piece(room_name(floor_i, "1x2side", r, stairs), pos + E * 7 + S * 6, (rot + 2) % 4)
	elif side == "west" and front == "south":
		_piece(room_name(floor_i, "1x2side", r, stairs), pos + E * 7, rot, FRONT_BACK)
	elif side == "south" and front == "east":
		_piece(room_name(floor_i, "1x2side", r, stairs), pos + E, (rot + 1) % 4, LEFT_RIGHT)
	elif side == "south" and front == "west":
		_piece(room_name(floor_i, "1x2side", r, stairs), pos + E * 7, (rot + 1) % 4)
	elif side == "north" and front == "west":
		_piece(room_name(floor_i, "1x2side", r, stairs), pos + E * 7 + S * 6, (rot + 1) % 4, FRONT_BACK)
	elif side == "north" and front == "east":
		_piece(room_name(floor_i, "1x2side", r, stairs), pos + E + S * 6, (rot + 3) % 4)
	elif side == "south" and front == "north":
		_piece(room_name(floor_i, "1x2front", r, stairs), pos + E + N * 8, rot)
	elif side == "north" and front == "south":
		_piece(room_name(floor_i, "1x2front", r, stairs), pos + E * 7 + S * 14, (rot + 2) % 4)
	elif side == "west" and front == "east":
		_piece(room_name(floor_i, "1x2front", r, stairs), pos + E * 15, (rot + 1) % 4)
	elif side == "east" and front == "west":
		_piece(room_name(floor_i, "1x2front", r, stairs), pos + W * 7 + S * 6, (rot + 3) % 4)
	elif side == "up" and front == "east":
		_piece(room_name(floor_i, "1x2s", r), pos + E * 15, (rot + 1) % 4)
	elif side == "up" and front == "south":
		_piece(room_name(floor_i, "1x2s", r), pos + E + N * 0, rot)


func _room_2x2(pos: Vector3i, rot: int, front: String, side: String, floor_i: int) -> void:
	var i := 0
	var j := 0
	var rot2 := rot
	var mirror := MIRROR_NONE
	if side == "east" and front == "south":
		i = -7
	elif side == "east" and front == "north":
		i = -7
		j = 6
		mirror = LEFT_RIGHT
	elif side == "north" and front == "east":
		i = 1
		j = 14
		rot2 = (rot + 3) % 4
	elif side == "north" and front == "west":
		i = 7
		j = 14
		rot2 = (rot + 3) % 4
		mirror = LEFT_RIGHT
	elif side == "south" and front == "west":
		i = 7
		j = -8
		rot2 = (rot + 1) % 4
	elif side == "south" and front == "east":
		i = 1
		j = -8
		rot2 = (rot + 1) % 4
		mirror = LEFT_RIGHT
	elif side == "west" and front == "north":
		i = 15
		j = 6
		rot2 = (rot + 2) % 4
	elif side == "west" and front == "south":
		i = 15
		mirror = FRONT_BACK
	_piece(room_name(floor_i, "2x2", r), pos + rd("east", rot) * i + rd("south", rot) * j, rot2, mirror)


func create(pos: Vector3i, rot: int, mg: MGrid) -> void:
	var pd := {"pos": pos, "rot": rot, "wall": "wall_flat"}
	# entrance
	_piece("entrance", pd["pos"] + rd("west", rot) * 9, rot)
	pd["pos"] = pd["pos"] + rd("south", rot) * 16
	var pd2 := {"pos": pd["pos"] + Vector3i(0, 8, 0), "rot": pd["rot"], "wall": "wall_window"}
	var g: Grid = mg.base
	var g3: Grid = mg.third
	start_x = mg.ex + 1
	start_y = mg.ey + 1
	var i := mg.ex + 1
	var j := mg.ey
	_outer_walls(pd, g, "south", start_x, start_y, i, j)
	_outer_walls(pd2, g, "south", start_x, start_y, i, j)
	var pd3 := {"pos": pd["pos"] + Vector3i(0, 19, 0), "rot": pd["rot"], "wall": "wall_window"}
	var found := false
	for k in g3.h:
		if found:
			break
		for l in range(g3.w - 1, -1, -1):
			if is_house(g3, l, k):
				pd3["pos"] = pd3["pos"] + rd("south", rot) * (8 + (k - start_y) * 8)
				pd3["pos"] = pd3["pos"] + rd("east", rot) * ((l - start_x) * 8)
				_wall_piece(pd3)
				_outer_walls(pd3, g3, "south", l, k, l, k)
				found = true
				break
	_roof(pos + Vector3i(0, 16, 0), rot, g, g3)
	_roof(pos + Vector3i(0, 27, 0), rot, g3, null)
	for fl in 3:
		var bpos := pos + Vector3i(0, 8 * fl + (3 if fl == 2 else 0), 0)
		var rooms_g: Grid = mg.rooms[fl]
		var gg: Grid = g3 if fl == 2 else g
		var carpet_s := "carpet_south_1" if fl == 0 else "carpet_south_2"
		var carpet_w := "carpet_west_1" if fl == 0 else "carpet_west_2"
		for m in gg.h:
			for n in gg.w:
				if gg.at(n, m) != CORRIDOR:
					continue
				var bp2 := _cell(bpos, rot, m, n)
				_piece("corridor_floor", bp2, rot)
				if gg.at(n, m - 1) == CORRIDOR or (rooms_g.at(n, m - 1) & CORRIDOR_FLAG) == CORRIDOR_FLAG:
					_piece("carpet_north", bp2 + rd("east", rot) * 1 + Vector3i(0, 1, 0), rot)
				if gg.at(n + 1, m) == CORRIDOR or (rooms_g.at(n + 1, m) & CORRIDOR_FLAG) == CORRIDOR_FLAG:
					_piece("carpet_east", bp2 + rd("south", rot) * 1 + rd("east", rot) * 5 + Vector3i(0, 1, 0), rot)
				if gg.at(n, m + 1) == CORRIDOR or (rooms_g.at(n, m + 1) & CORRIDOR_FLAG) == CORRIDOR_FLAG:
					_piece(carpet_s, bp2 + rd("south", rot) * 5 + rd("west", rot) * 1, rot)
				if gg.at(n - 1, m) == CORRIDOR or (rooms_g.at(n - 1, m) & CORRIDOR_FLAG) == CORRIDOR_FLAG:
					_piece(carpet_w, bp2 + rd("west", rot) * 1 + rd("north", rot) * 1, rot)
		var wall_n := "indoors_wall_1" if fl == 0 else "indoors_wall_2"
		var door_n := "indoors_door_1" if fl == 0 else "indoors_door_2"
		var lst: Array = []
		for o in gg.h:
			for p in gg.w:
				var stair_top := fl == 2 and gg.at(p, o) == START_ROOM
				if gg.at(p, o) != ROOM and not stair_top:
					continue
				var q := rooms_g.at(p, o)
				var rt := q & TYPE_MASK
				var sid := q & ID_MASK
				stair_top = stair_top and (q & CORRIDOR_FLAG) == CORRIDOR_FLAG
				lst.clear()
				if (q & DOOR_FLAG) == DOOR_FLAG:
					for d in HORIZ:
						var s: Vector2i = STEP[d]
						if gg.at(p + s.x, o + s.y) == CORRIDOR:
							lst.append(d)
				var d2 := ""
				if not lst.is_empty():
					d2 = lst[r.next_int_bound(lst.size())]
				elif (q & ORIGIN_FLAG) == ORIGIN_FLAG:
					d2 = "up"
				var bp3 := _cell(bpos, rot, o, p, -1)
				if is_house(gg, p - 1, o) and not mg.is_room_id(p - 1, o, fl, sid):
					_piece(door_n if d2 == "west" else wall_n, bp3, rot)
				if gg.at(p + 1, o) == CORRIDOR and not stair_top:
					_piece(door_n if d2 == "east" else wall_n, bp3 + rd("east", rot) * 8, rot)
				if is_house(gg, p, o + 1) and not mg.is_room_id(p, o + 1, fl, sid):
					_piece(door_n if d2 == "south" else wall_n, bp3 + rd("south", rot) * 7 + rd("east", rot) * 7, (rot + 1) % 4)
				if gg.at(p, o - 1) == CORRIDOR and not stair_top:
					_piece(door_n if d2 == "north" else wall_n, bp3 + rd("north", rot) * 1 + rd("east", rot) * 7, (rot + 1) % 4)
				if rt == ROOM_1X1:
					_room_1x1(bp3, rot, d2, fl)
				elif rt == ROOM_1X2 and d2 != "":
					var d3 := mg.get_1x2_dir(p, o, fl, sid)
					_room_1x2(bp3, rot, d3, d2, fl, (q & STAIRS_FLAG) == STAIRS_FLAG)
				elif rt == ROOM_2X2 and d2 != "" and d2 != "up":
					var d4: String = CW[d2]
					var s4: Vector2i = STEP[d4]
					if not mg.is_room_id(p + s4.x, o + s4.y, fl, sid):
						d4 = OPP[d4]
					_room_2x2(bp3, rot, d4, d2, fl)
				elif rt == ROOM_2X2 and d2 == "up":
					_piece(room_name(fl, "2x2s", r), bp3 + rd("east", rot) * 1, rot)


## WoodlandMansionStructure.findGenerationPoint + generatePieces. Biome test on the generation stub (chunk block 7, 7
## at the lowest corner height), nothing below y 60.
static func generate(st: Structures, cfg: Dictionary, sc: Vector2i, r: RandomSources.LegacyRandom, any_biome: bool = false) -> Dictionary:
	var rot := r.next_int_bound(4)
	var i := 5
	var j := 5
	match rot:
		1:
			i = -5
		2:
			i = -5
			j = -5
		3:
			j = -5
	var k := sc.x * 16 + 7
	var l := sc.y * 16 + 7
	var lo := 1 << 30
	for cxz in [Vector2i(k, l), Vector2i(k, l + j), Vector2i(k + i, l), Vector2i(k + i, l + j)]:
		lo = mini(lo, st.base_height(cxz.x, cxz.y, false) - 1)
	if lo < 60:
		return {}
	if not any_biome and not (cfg["biomes"] as Dictionary).has(st.biome_id_at(k, lo, l)):   # (/place structure: no biome test)
		return {}
	var start := Vector3i(k, lo, l)
	var mg := MGrid.new(r)
	var pl := MansionPieces.new()
	pl.r = r
	pl.create(start, rot, mg)
	var res := StructuresLegacy._pieces_result(pl.pieces, start)
	if not res.is_empty():
		res["after"] = "mansion"
	return res
