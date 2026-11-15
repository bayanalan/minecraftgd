## BERender — blocks Java draws with block-entity renderers (their JSON models are particle-only, so the voxel
## mesher has nothing to draw). Geometry follows the Java model layer definitions:
## - Chests (ChestRenderer + ChestModel single / double left / right; normal, trapped, ender, copper variants):
##   lid.xRot = -(1 - (1 - openness)^3) * pi/2 while the chest's screen is open (ChestLidController 0.1/tick).
## - Shulker boxes (ShulkerBoxRenderer + ShulkerModel; lid rises 8 px and turns 270 degrees while open).
## - Skulls / heads (SkullBlockRenderer: SkullModel 8x8x8 (+hat for players), PiglinHeadModel, DragonHeadModel;
##   floor rotation 0-15, wall heads 4 px off the wall at y 4 px).
## - Banners (BannerRenderer: flag 20x40x1 / pole / bar at 2/3 scale, flag sway by position + game time).
## - Bell body (BellModel; swings per BellRenderer while Bells.swing has it), decorated pot (DecoratedPotRenderer
##   neck/top/bottom/4 sides), conduit (ConduitRenderer: shell while inactive; active: cage turning -0.0375 rad per
##   tick about (0.5, 1, 0.5) and bobbing 0.3 + g x 0.2, two wind shells (16 and 14 px, orientation every 66 ticks,
##   22-frame animated texture at 3 ticks a frame), camera-facing eye (open while it hunts) at half size).
## - Monster spawner / trial spawner mob previews (SpawnerRenderer).
## Instances are Node3Ds outside the chunk meshes, kept in sync by scanning loaded chunk palettes incrementally
## (3 chunks per frame within RADIUS; block changes of tracked blocks rescan their chunk immediately).
## APPROXIMATE: banner flag base is the dye-tinted banner_base texture, pattern layers are offset 0.04 px each instead of
## Java's draw order, no christmas chests.
class_name BERender
extends RefCounted

const RADIUS := 5
const NONE := Vector3i(0, -9999, 0)
const DYE := {"white": Color(0.98, 0.98, 0.98), "orange": Color(0.98, 0.5, 0.11), "magenta": Color(0.78, 0.31, 0.75), "light_blue": Color(0.23, 0.7, 0.85),
	"yellow": Color(1.0, 0.85, 0.24), "lime": Color(0.5, 0.78, 0.12), "pink": Color(0.95, 0.55, 0.67), "gray": Color(0.28, 0.31, 0.33),
	"light_gray": Color(0.62, 0.62, 0.59), "cyan": Color(0.09, 0.61, 0.61), "purple": Color(0.54, 0.2, 0.72), "blue": Color(0.24, 0.27, 0.67),
	"brown": Color(0.51, 0.33, 0.2), "green": Color(0.37, 0.49, 0.09), "red": Color(0.69, 0.18, 0.15), "black": Color(0.11, 0.11, 0.13)}
const STEP := {"north": Vector3(0, 0, -1), "south": Vector3(0, 0, 1), "west": Vector3(-1, 0, 0), "east": Vector3(1, 0, 0)}
const YROT := {"south": 0.0, "west": 90.0, "north": 180.0, "east": 270.0}   # Java Direction.toYRot

static var _ids: Dictionary = {}       # block id -> kind
static var _chunks: Dictionary = {}    # chunk key -> Array[[Vector3i, state]]
static var _nodes: Dictionary = {}     # Vector3i -> Node3D
static var _queue: Array = []
static var _dirty: Dictionary = {}
static var _last_ms := 0
static var _scanned: Dictionary = {}   # chunk key -> Chunk instance whose tracked blocks _chunks holds
static var _qset: Dictionary = {}
static var _ver := 0
static var _synced_ver := -1
static var _synced_origin := Vector3i(1 << 30, 0, 0)
static var _last_pc := Vector2i(1 << 30, 0)
static var _frame := 0
static var _anim: Array = []           # [pos, node, lid, flag, is_chest]
static var _spinners: Array = []       # [pos, spin node] - monster spawner mob previews
static var _books: Array = []          # [pos, parts dict, state dict] - enchanting table books
static var _conduits: Array = []       # [pos, parts dict] - conduits (active parts posed while Conduits.active has them)
static var _wind_mats: Array = []      # [horizontal ShaderMaterial, vertical ShaderMaterial, frames h, frames v]
static var _wind_frame := -1
static var _book_acc := 0.0
static var _book_rng := RandomNumberGenerator.new()
static var golem_open: Dictionary = {}  # chest pos -> game time until which a copper golem holds it open
static var _light_slot := -1
static var _portal_mats: Dictionary = {}   # "end_portal" / "end_gateway" -> ShaderMaterial
static var _trk := PackedByteArray()   # per state: 1 = drawn by this renderer


static func setup() -> void:
	clear()
	_ids.clear()
	ensure_ids()


static func ensure_ids() -> void:
	if not _ids.is_empty():
		return
	var b := Res.blocks
	for i in b.names.size():
		var n: String = b.names[i]
		var kind := ""
		if n == "chest" or n == "trapped_chest" or n == "ender_chest" or n.ends_with("copper_chest"):
			kind = "chest"
		elif n.ends_with("shulker_box"):
			kind = "shulker"
		elif n.ends_with("_skull") or (n.ends_with("_head") and not n.begins_with("piston")):
			kind = "skull"
		elif n.ends_with("_banner"):
			kind = "banner"
		elif n == "bell":
			kind = "bell"
		elif n == "decorated_pot":
			kind = "pot"
		elif n == "conduit":
			kind = "conduit"
		elif Shelf.is_shelf(n):
			kind = "shelf"
		elif n == "end_portal" or n == "end_gateway":
			kind = n
		elif n == "spawner" or n == "trial_spawner":
			kind = n
		elif n == "enchanting_table":
			kind = "enchanting_table"
		elif n == "campfire" or n == "soul_campfire":
			kind = "campfire"
		if kind != "":
			_ids[i] = kind


## Contents changed (shelf items): rebuild that block's node on the next sync.
static func refresh(p: Vector3i) -> void:
	if _nodes.has(p):
		var nd: Node3D = _nodes[p]
		if is_instance_valid(nd):
			nd.queue_free()
		_nodes.erase(p)
		_ver += 1


static func clear() -> void:
	for p in _nodes:
		if is_instance_valid(_nodes[p]):
			(_nodes[p] as Node).queue_free()
	_nodes.clear()
	_chunks.clear()
	_queue.clear()
	_dirty.clear()
	_scanned.clear()
	_qset.clear()
	_anim.clear()
	_spinners.clear()
	_books.clear()
	_conduits.clear()
	_ver += 1
	_trk = PackedByteArray()


static func tracked(st: int) -> bool:
	return st > 0 and _ids.has(Res.blocks.st_block[st])


## Block change hook: rescan that chunk on the next frame.
static func on_block_changed(p: Vector3i, old: int, new_st: int) -> void:
	if tracked(old) or tracked(new_st):
		_dirty[Coords.chunk_key(p.x >> 4, p.z >> 4)] = Vector2i(p.x >> 4, p.z >> 4)


static func _track_table() -> PackedByteArray:
	var b := Res.blocks
	if _trk.size() != b.total_states:
		var t := PackedByteArray()
		t.resize(b.total_states)
		for s in b.total_states:
			t[s] = 1 if (s > 0 and _ids.has(b.st_block[s])) else 0
		_trk = t
	return _trk


## Collects the tracked blocks of one chunk (palette check per section, then a direct index walk).
static func _scan(world, cx: int, cz: int) -> void:
	var key := Coords.chunk_key(cx, cz)
	var ch: Chunk = world.cm.get_chunk(cx, cz)
	if ch == null or ch.state < Chunk.DECORATED:
		_scanned.erase(key)
		if _chunks.erase(key):
			_ver += 1
		return
	_scanned[key] = ch
	var trk := _track_table()
	var found: Array = []
	for s in Coords.SECTIONS:
		var sec: Chunk.Section = ch.sections[s]
		var pal := sec.pal
		var has := false
		for st in pal:
			if trk[st] != 0:
				has = true
				break
		if not has:
			continue
		var y0 := Coords.MIN_Y + s * 16
		var wide := sec.wide
		var idx := sec.idx
		var uni := pal.size() == 1
		var use_w := wide.size() > 0
		for li in 4096:
			var st2: int = pal[0] if uni else (pal[wide[li]] if use_w else pal[idx[li]])
			if trk[st2] != 0:
				found.append([Vector3i(cx * 16 + (li & 15), y0 + (li >> 8), cz * 16 + ((li >> 4) & 15)), st2])
	if found.is_empty():
		if _chunks.erase(key):
			_ver += 1
	elif found != _chunks.get(key):
		_chunks[key] = found
		_ver += 1


## Per frame (main thread). Chunks are scanned when they enter RADIUS, are (re)loaded or decorated, or a tracked block
## changes; nodes are re-synced only when the scanned set changed; only lids / banner flags animate every frame.
static func update(world) -> void:
	if _ids.is_empty() or world.cm == null or world.player == null:
		return
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _last_ms) / 1000.0, 0.0, 0.25)
	_last_ms = now
	_frame += 1
	var cm = world.cm
	var pc := Vector2i(int(floor(world.player.pos.x)) >> 4, int(floor(world.player.pos.z)) >> 4)
	if not _dirty.is_empty():
		for k in _dirty.keys():
			var c: Vector2i = _dirty[k]
			if absi(c.x - pc.x) <= RADIUS and absi(c.y - pc.y) <= RADIUS:
				_scan(world, c.x, c.y)
		_dirty.clear()
	if pc != _last_pc or _frame % 15 == 0:
		_last_pc = pc
		for ring in RADIUS + 1:
			for dz in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					if maxi(absi(dx), absi(dz)) != ring:
						continue
					var cc := pc + Vector2i(dx, dz)
					var key := Coords.chunk_key(cc.x, cc.y)
					var ch: Chunk = cm.get_chunk(cc.x, cc.y)
					if ch != null and ch.state >= Chunk.DECORATED:
						if _scanned.get(key) != ch and not _qset.has(key):
							_qset[key] = true
							_queue.append(cc)
					elif _scanned.has(key):
						_scanned.erase(key)
						if _chunks.erase(key):
							_ver += 1
		for key in _scanned.keys():
			var sc: Chunk = _scanned[key]
			if absi(sc.cx - pc.x) > RADIUS or absi(sc.cz - pc.y) > RADIUS:
				_scanned.erase(key)
				if _chunks.erase(key):
					_ver += 1
	for i in 3:
		if _queue.is_empty():
			break
		var c2: Vector2i = _queue.pop_front()
		_qset.erase(Coords.chunk_key(c2.x, c2.y))
		_scan(world, c2.x, c2.y)
	if _ver != _synced_ver:
		_synced_ver = _ver
		_sync_nodes(world)
	var org: Vector3i = cm.origin
	if org != _synced_origin:
		_synced_origin = org
		for p in _nodes:
			var nd: Node3D = _nodes[p]
			if is_instance_valid(nd):
				nd.position = world.vis(Vector3(p))
	if not _portal_mats.is_empty():
		# Java GameTime uniform: ((game time % 24000) + partial tick) / 24000
		var gtu := fposmod(float(world.game_time), 24000.0) / 24000.0
		for k in _portal_mats:
			(_portal_mats[k] as ShaderMaterial).set_shader_parameter("game_time", gtu)
	if not _spinners.is_empty():
		_spin_tick(world, dt)
	if not _books.is_empty():
		_book_update(world, dt)
	if not Bells.swing.is_empty():
		_bell_update(world)
	if not _conduits.is_empty():
		_conduit_update(world)
	if not _anim.is_empty():
		var open_a := NONE
		var open_b := NONE
		var scr = world.screen
		if scr != null and scr.get("kind") != null and scr.get("pos") is Vector3i and scr.get("entity") == null:
			open_a = scr.get("pos")
			if scr.get("pos2") is Vector3i:
				open_b = scr.get("pos2")
		var gt := float(world.game_time)
		for e in _anim:
			var p: Vector3i = e[0]
			var nd2: Node3D = e[1]
			if not is_instance_valid(nd2):
				continue
			var lid = e[2]
			if lid != null:
				var target := 1.0 if (p == open_a or p == open_b or int(golem_open.get(p, -1)) >= int(gt)) else 0.0
				var prev := float(nd2.get_meta("open", 0.0))
				if prev != target:
					var cur := move_toward(prev, target, 2.0 * dt)
					nd2.set_meta("open", cur)
					if e[4]:
						var f := 1.0 - cur
						(lid as Node3D).rotation.x = -(1.0 - f * f * f) * PI / 2.0
					else:
						(lid as Node3D).position.y = 0.5 * cur
						(lid as Node3D).rotation.y = -deg_to_rad(270.0) * cur
			var flag = e[3]
			if flag != null:
				var k := fposmod(float(p.x * 7 + p.y * 9 + p.z * 13) + gt, 100.0) / 100.0
				(flag as Node3D).rotation.x = -(-0.0125 + 0.01 * cos(TAU * k)) * PI
	# light: every 250 ms an eighth of the nodes re-sample the light at their block
	var slot := now / 250
	if slot != _light_slot:
		_light_slot = slot
		for p in _nodes:
			if (slot + p.x + p.z) % 8 == 0:
				_relight(world, p, _nodes[p])


static func _relight(world, p: Vector3i, nd) -> void:
	if not is_instance_valid(nd):
		return
	var l: int = world.cm.get_light(p.x, p.y, p.z)
	for mi in _meshes(nd):
		mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))


static func _sync_nodes(world) -> void:
	var want := {}
	for key in _chunks:
		for e in _chunks[key]:
			want[e[0]] = e[1]
	for p in _nodes.keys():
		var nd: Node3D = _nodes[p]
		if not want.has(p) or not is_instance_valid(nd) or int(nd.get_meta("st", -1)) != int(want[p]):
			if is_instance_valid(nd):
				nd.queue_free()
			_nodes.erase(p)
	for p in want:
		if _nodes.has(p):
			continue
		var nd2: Node3D = _make(world, p, int(want[p]))
		if nd2 == null:
			continue
		nd2.set_meta("st", int(want[p]))
		nd2.position = world.vis(Vector3(p))
		_nodes[p] = nd2
		_relight(world, p, nd2)
	_anim.clear()
	_spinners.clear()
	_books.clear()
	_conduits.clear()
	for p in _nodes:
		var nd3: Node3D = _nodes[p]
		if nd3.has_meta("conduit"):
			_conduits.append([p, nd3.get_meta("conduit")])
		if nd3.has_meta("book"):
			_books.append([p, nd3.get_meta("book"), {"open": 0.0, "o_open": 0.0, "rot": 0.0, "o_rot": 0.0, "t_rot": 0.0,
				"flip": 0.0, "o_flip": 0.0, "flip_t": 0.0, "flip_a": 0.0, "time": float(_book_rng.randi_range(0, 1000))}])
		if nd3.has_meta("spin"):
			_spinners.append([p, nd3.get_meta("spin")])
		var lid = nd3.get_meta("lid") if nd3.has_meta("lid") else null
		var flag = nd3.get_meta("flag") if nd3.has_meta("flag") else null
		if lid != null or flag != null:
			_anim.append([p, nd3, lid, flag, str(nd3.get_meta("kind", "")) == "chest"])

static func _meshes(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out


## Box in Java block-entity pixel space (Y up, no flip: chests, bells, pots).
static func _part(parent: Node3D, pivot: Vector3, o: Vector3, s: Vector3, uv: Vector2, ts: Vector2, tex: String, inflate := 0.0, tint := Color.WHITE) -> Node3D:
	var pv := Node3D.new()
	pv.position = pivot / 16.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	EntityRenderer.box_arrays(o, s, uv, ts, st, inflate, tint, true)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.scale = Vector3(-1, -1, 1)    # box_arrays emits flipped entity space; undo it
	mi.material_override = EntityRenderer.material(tex)
	pv.add_child(mi)
	parent.add_child(pv)
	return pv


## Box in Java entity-model space (Y down; the caller's node supplies the Java scale(-1,-1,1)-equivalent frame).
static func _epart(parent: Node3D, pivot: Vector3, o: Vector3, s: Vector3, uv: Vector2, ts: Vector2, tex: String, inflate := 0.0, tint := Color.WHITE) -> Node3D:
	var pv := Node3D.new()
	pv.position = Vector3(-pivot.x, -pivot.y, pivot.z) / 16.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	EntityRenderer.box_arrays(o, s, uv, ts, st, inflate, tint)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = EntityRenderer.material(tex)
	pv.add_child(mi)
	parent.add_child(pv)
	return pv


## Single textured quad (block-entity pixel space); corners counter-clockwise from top-left, uv rect in texture px.
static func _quad(parent: Node3D, c: Array, uv: Rect2, ts: Vector2, tex: String, shade: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs := [uv.position, Vector2(uv.position.x, uv.end.y), uv.end, Vector2(uv.end.x, uv.position.y)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(shade, shade, shade))
		st.set_uv(uvs[idx] / ts)
		st.add_vertex((c[idx] as Vector3) / 16.0)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = EntityRenderer.material(tex)
	parent.add_child(mi)


## Java TheEndPortalRenderer.renderCube: end portals draw only their top (y 0.75) and bottom (y 0.375) faces
## (TheEndPortalBlockEntity.shouldRenderFace: Y axis), end gateways all six faces of the full cube (offsets 1 / 0;
## faces against opaque neighbours are hidden by the depth test).
static func _portal_faces(model: Node3D, kind: String) -> void:
	var up := 0.75 if kind == "end_portal" else 1.0
	var dn := 0.375 if kind == "end_portal" else 0.0
	var faces := [[Vector3(0, up, 1), Vector3(1, up, 1), Vector3(1, up, 0), Vector3(0, up, 0)],
		[Vector3(0, dn, 0), Vector3(1, dn, 0), Vector3(1, dn, 1), Vector3(0, dn, 1)]]
	if kind == "end_gateway":
		faces.append_array([[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
			[Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)],
			[Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)],
			[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)]])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		for idx in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(f[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = portal_material(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(mi)


## Java BookModel (entity/enchanting_table_book, 64 x 32) under EnchantTableRenderer's translate(0.5, 0.75, 0.5):
## lids 6 x 10 px at z -1 / +1, seam, page blocks 5 x 8 x 1 and two flipping pages; the renderer adds a bob
## 0.1 + sin(time * 0.1) * 0.01, turns the book by -rot about Y and tilts it 80 degrees about Z.
static func _book_parts(inner: Node3D) -> Dictionary:
	var tex := "entity/enchanting_table_book"
	var ts := Vector2(64, 32)
	var yaw := Node3D.new()
	yaw.position = Vector3(0, 0.85, 0)
	inner.add_child(yaw)
	var tilt := Node3D.new()
	tilt.rotation.z = deg_to_rad(80.0)
	yaw.add_child(tilt)
	var d := {"yaw": yaw}
	d["left_lid"] = _part(tilt, Vector3(0, 0, -1), Vector3(-6, -5, -0.005), Vector3(6, 10, 0.005), Vector2(0, 0), ts, tex)
	d["right_lid"] = _part(tilt, Vector3(0, 0, 1), Vector3(0, -5, -0.005), Vector3(6, 10, 0.005), Vector2(16, 0), ts, tex)
	var seam := _part(tilt, Vector3.ZERO, Vector3(-1, -5, 0), Vector3(2, 10, 0.005), Vector2(12, 0), ts, tex)
	seam.rotation.y = PI / 2.0
	d["left_pages"] = _part(tilt, Vector3.ZERO, Vector3(0, -4, -0.99), Vector3(5, 8, 1), Vector2(0, 10), ts, tex)
	d["right_pages"] = _part(tilt, Vector3.ZERO, Vector3(0, -4, -0.01), Vector3(5, 8, 1), Vector2(12, 10), ts, tex)
	d["flip1"] = _part(tilt, Vector3.ZERO, Vector3(0, -4, 0), Vector3(5, 8, 0.005), Vector2(24, 10), ts, tex)
	d["flip2"] = _part(tilt, Vector3.ZERO, Vector3(0, -4, 0), Vector3(5, 8, 0.005), Vector2(24, 10), ts, tex)
	return d


static func _wrap_pi(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


## Java EnchantingTableBlockEntity.bookAnimationTick (20 per second): opens and turns toward the nearest player
## within 3 blocks, idles with tRot += 0.02 otherwise, random page flips.
static func _book_tick(b: Dictionary, p: Vector3i, pp: Vector3) -> void:
	b["o_open"] = b["open"]
	b["o_rot"] = b["rot"]
	var c := Vector3(p) + Vector3(0.5, 0.5, 0.5)
	if pp.distance_squared_to(c) < 9.0:   # Level.getNearestPlayer(..., 3.0): d^2 < 3^2
		b["t_rot"] = atan2(pp.z - c.z, pp.x - c.x)
		b["open"] = float(b["open"]) + 0.1
		if float(b["open"]) < 0.5 or _book_rng.randi_range(0, 39) == 0:
			var f0: float = b["flip_t"]
			while f0 == float(b["flip_t"]):
				b["flip_t"] = float(b["flip_t"]) + float(_book_rng.randi_range(0, 3) - _book_rng.randi_range(0, 3))
	else:
		b["t_rot"] = float(b["t_rot"]) + 0.02
		b["open"] = float(b["open"]) - 0.1
	b["rot"] = _wrap_pi(b["rot"])
	b["t_rot"] = _wrap_pi(b["t_rot"])
	b["rot"] = float(b["rot"]) + _wrap_pi(float(b["t_rot"]) - float(b["rot"])) * 0.4
	b["open"] = clampf(b["open"], 0.0, 1.0)
	b["time"] = float(b["time"]) + 1.0
	b["o_flip"] = b["flip"]
	var h := clampf((float(b["flip_t"]) - float(b["flip"])) * 0.4, -0.2, 0.2)
	b["flip_a"] = float(b["flip_a"]) + (h - float(b["flip_a"])) * 0.9
	b["flip"] = float(b["flip"]) + float(b["flip_a"])


## Ticks the books at 20 / s and poses them with the partial tick (Java EnchantTableRenderer + BookModel.setupAnim).
static func _book_update(world, dt: float) -> void:
	_book_acc += dt
	var ticks := mini(int(_book_acc * 20.0), 5)
	_book_acc = minf(_book_acc - ticks / 20.0, 0.05)
	var pp: Vector3 = world.player.pos + Vector3(0, 0.0, 0)
	var pt := clampf(_book_acc * 20.0, 0.0, 1.0)
	for e in _books:
		var p: Vector3i = e[0]
		var d: Dictionary = e[1]
		var b: Dictionary = e[2]
		if not is_instance_valid(d["yaw"]):
			continue
		for t in ticks:
			_book_tick(b, p, pp)
		var tf := float(b["time"]) + pt
		(d["yaw"] as Node3D).position.y = 0.75 + 0.1 + sin(tf * 0.1) * 0.01
		(d["yaw"] as Node3D).rotation.y = -(float(b["o_rot"]) + _wrap_pi(float(b["rot"]) - float(b["o_rot"])) * pt)
		var fl := lerpf(b["o_flip"], b["flip"], pt)
		var j := clampf((fl + 0.25 - floorf(fl + 0.25)) * 1.6 - 0.3, 0.0, 1.0)
		var k := clampf((fl + 0.75 - floorf(fl + 0.75)) * 1.6 - 0.3, 0.0, 1.0)
		var f := (sin(tf * 0.02) * 0.1 + 1.25) * lerpf(b["o_open"], b["open"], pt)
		(d["left_lid"] as Node3D).rotation.y = PI + f
		(d["right_lid"] as Node3D).rotation.y = -f
		(d["left_pages"] as Node3D).rotation.y = f
		(d["right_pages"] as Node3D).rotation.y = -f
		(d["flip1"] as Node3D).rotation.y = f - f * 2.0 * j
		(d["flip2"] as Node3D).rotation.y = f - f * 2.0 * k
		var sx := sin(f) / 16.0
		for nm in ["left_pages", "right_pages", "flip1", "flip2"]:
			(d[nm] as Node3D).position.x = sx


## Java SpawnerRenderer.renderEntityInSpawner: the spawner's mob at translate(0.5, 0.4, 0.5), turned by spin x 10
## degrees, then down 0.2, tilted -30 degrees about X and scaled 0.53125 (divided by max(width, height) when that is
## over 1).
static func _spawner_mob(inner: Node3D, mob: String) -> bool:
	if mob == "":
		return false
	var def: Dictionary = MobRegistry.get_def(mob)
	if def.is_empty():
		return false
	var rig := EntityRenderer.build_rig(def)
	EntityRenderer.group_head(rig)
	var f := 0.53125
	var g := maxf(float(def.get("w", 0.6)), float(def.get("h", 1.8)))
	if g > 1.0:
		f /= g
	var spin := Node3D.new()
	spin.position = Vector3(0, 0.4, 0)
	var tilt := Node3D.new()
	tilt.position = Vector3(0, -0.2, 0)
	tilt.rotation.x = deg_to_rad(-30.0)
	tilt.scale = Vector3.ONE * f
	tilt.add_child(rig)
	spin.add_child(tilt)
	inner.add_child(spin)
	return true


## Java BaseSpawner.clientTick: while a player is within 16 blocks, spin += 1000 / (spawnDelay + 200) degrees per
## tick (shown x 10).
static func _spin_tick(world, dt: float) -> void:
	var pp: Vector3 = world.player.pos
	for e in _spinners:
		var p: Vector3i = e[0]
		var sn = e[1]
		if not is_instance_valid(sn) or (Vector3(p) + Vector3(0.5, 0.5, 0.5)).distance_to(pp) > 16.0:
			continue
		var delay := _spin_delay(world, p)
		(sn as Node3D).rotation.y = fposmod((sn as Node3D).rotation.y + deg_to_rad(dt * 20.0 * 1000.0 / (delay + 200.0) * 10.0), TAU)


## Trial spawners spin like spawners with the time to their next spawn as the delay (20 while waiting).
static func _spin_delay(world, p: Vector3i) -> int:
	var d := BlockEntities.get_data(world, p)
	if str(d.get("id", "")) == "trial_spawner":
		return maxi(0, int(d.get("next", 0)) - int(world.game_time)) if str(d.get("state", "")) == "active" else 20
	return maxi(0, int(d.get("delay", 20)))


## Partial tick (0..1) of the world's 20 / s clock.
static func _partial(world) -> float:
	var acc = world.get("tick_accum")
	return clampf(float(acc) / 0.05, 0.0, 1.0) if acc != null else 0.0


## Java BellRenderer: while shaking, bell_body.xRot / zRot follow Bells.swing_angles (50 ticks), then rest.
static func _bell_update(world) -> void:
	var now := int(world.game_time)
	var pt := _partial(world)
	for p in Bells.swing.keys():
		var e: Array = Bells.swing[p]
		var t := float(now - int(e[0])) + pt
		var nd = _nodes.get(p)
		var body = nd.get_meta("bell_body") if nd != null and is_instance_valid(nd) and (nd as Node3D).has_meta("bell_body") else null
		var ang := Bells.swing_angles(t, e[1])
		if body != null and is_instance_valid(body):
			(body as Node3D).rotation = Vector3(ang.x, 0.0, ang.y)
		if t >= Bells.SHAKE_TICKS:
			Bells.swing.erase(p)


## Java ConduitRenderer active parts (hidden until Conduits.active lists the conduit).
static func _conduit_parts(inner: Node3D, shell: Node3D) -> Dictionary:
	var d := {"shell": shell}
	var act := Node3D.new()
	act.visible = false
	inner.add_child(act)
	d["act"] = act
	var cage_pos := Node3D.new()
	act.add_child(cage_pos)
	var cage_rot := Node3D.new()
	cage_pos.add_child(cage_rot)
	_epart(cage_rot, Vector3.ZERO, Vector3(-4, -4, -4), Vector3(8, 8, 8), Vector2(0, 0), Vector2(32, 16), "entity/conduit/cage")
	d["cage_pos"] = cage_pos
	d["cage_rot"] = cage_rot
	var wind := Node3D.new()
	wind.position = Vector3(0, 0.5, 0)
	act.add_child(wind)
	var inner_wind := Node3D.new()
	inner_wind.scale = Vector3.ONE * 0.875
	inner_wind.rotation = Vector3(PI, 0.0, PI)
	wind.add_child(inner_wind)
	d["wind"] = wind
	d["wind_meshes"] = [_wind_box(wind), _wind_box(inner_wind)]
	var eye_pos := Node3D.new()
	act.add_child(eye_pos)
	var eye_bb := Node3D.new()
	eye_pos.add_child(eye_bb)
	var eye_z := Node3D.new()
	eye_z.rotation.z = PI
	eye_bb.add_child(eye_z)
	d["eye_pos"] = eye_pos
	d["eye_bb"] = eye_bb
	d["eye_open"] = _epart(eye_z, Vector3.ZERO, Vector3(-4, -4, 0), Vector3(8, 8, 0), Vector2(0, 0), Vector2(16, 16), "entity/conduit/open_eye", 0.01)
	d["eye_closed"] = _epart(eye_z, Vector3.ZERO, Vector3(-4, -4, 0), Vector3(8, 8, 0), Vector2(0, 0), Vector2(16, 16), "entity/conduit/closed_eye", 0.01)
	return d


static func _wind_box(parent: Node3D) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	EntityRenderer.box_arrays(Vector3(-8, -8, -8), Vector3(16, 16, 16), Vector2(0, 0), Vector2(64, 32), st)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wm := _wind_materials()
	if not wm.is_empty():
		mi.material_override = wm[0]
	parent.add_child(mi)
	return mi


## The wind / wind_vertical textures are 22-frame strips (64 x 32 frames, 3 ticks each: .mcmeta): one material each,
## its texture swapped to the current frame (shared by every conduit, like Java's animated atlas sprites).
static func _wind_materials() -> Array:
	if not _wind_mats.is_empty():
		return _wind_mats
	var out: Array = []
	for nm in ["entity/conduit/wind", "entity/conduit/wind_vertical"]:
		var m := (EntityRenderer.material(nm) as ShaderMaterial).duplicate() as ShaderMaterial
		var frames: Array = []
		var im: Image = Res.load_image(nm) if Res.mode == "vanilla" else null
		if im != null:
			im.convert(Image.FORMAT_RGBA8)
			for i in im.get_height() / 32:
				frames.append(ImageTexture.create_from_image(im.get_region(Rect2i(0, i * 32, 64, 32))))
		if not frames.is_empty():
			m.set_shader_parameter("tex", frames[0])
			m.set_shader_parameter("has_tex", true)
		out.append([m, frames])
	_wind_mats = out
	return out


static func _conduit_update(world) -> void:
	var now := int(world.game_time)
	var pt := _partial(world)
	var gt := float(now) + pt
	var wm := _wind_materials()
	var wf := (now / 3)
	if wf != _wind_frame and wm.size() == 2:
		_wind_frame = wf
		for e in wm:
			var frames: Array = e[1]
			if not frames.is_empty():
				(e[0] as ShaderMaterial).set_shader_parameter("tex", frames[wf % frames.size()])
	var cam = world.get("camera")
	var axis := Vector3(0.5, 1.0, 0.5).normalized()
	for e in _conduits:
		var p: Vector3i = e[0]
		var d: Dictionary = e[1]
		var act = d.get("act")
		if act == null or not is_instance_valid(act):
			continue
		var a = Conduits.active.get(p)
		var on: bool = a != null
		if (act as Node3D).visible != on:
			(act as Node3D).visible = on
			(d["shell"] as Node3D).visible = not on
		if not on:
			continue
		# ConduitBlockEntity: activeRotation counts the ticks it has been active (x -0.0375 rad); the bob uses tickCount
		var f := -0.0375 * (gt - float(a.get("since", now)))
		var g := sin(gt * 0.1) / 2.0 + 0.5
		g = g * g + g
		(d["cage_pos"] as Node3D).position = Vector3(0, 0.3 + g * 0.2, 0)
		(d["cage_rot"] as Node3D).basis = Basis(axis, f)
		var i := (now / 66) % 3
		(d["wind"] as Node3D).rotation = Vector3(PI / 2.0, 0, 0) if i == 1 else (Vector3(0, 0, PI / 2.0) if i == 2 else Vector3.ZERO)
		if wm.size() == 2:
			for mi in d["wind_meshes"]:
				(mi as MeshInstance3D).material_override = wm[1 if i == 1 else 0][0]
		(d["eye_pos"] as Node3D).position = Vector3(0, 0.3 + g * 0.2, 0)
		var hunt: bool = bool(a.get("hunt", false))
		(d["eye_open"] as Node3D).visible = hunt
		(d["eye_closed"] as Node3D).visible = not hunt
		if cam != null and is_instance_valid(cam):
			var bb: Node3D = d["eye_bb"]
			var tr := bb.global_transform
			tr.basis = (cam as Node3D).global_transform.basis.orthonormalized().scaled(Vector3.ONE * 0.5)
			bb.global_transform = tr


static func portal_material(kind: String) -> ShaderMaterial:
	if _portal_mats.has(kind):
		return _portal_mats[kind]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/end_portal.gdshader")
	m.set_shader_parameter("sky_tex", UiKit.sprite("environment/end_sky"))
	m.set_shader_parameter("portal_tex", UiKit.sprite("entity/end_portal/end_portal"))
	m.set_shader_parameter("layers", 15 if kind == "end_portal" else 16)
	_portal_mats[kind] = m
	return m


static func _make(world, p: Vector3i, st: int) -> Node3D:
	if _ids.get(Res.blocks.st_block[st], "") == "conduit" and BlockEntities.get_data(world, p).is_empty():
		BlockEntities.set_data(world, p, {"id": "conduit"})   # (conduits placed before they had block entity data)
	var r := build(st, BlockEntities.get_data(world, p))
	if r != null:
		world.add_child(r)
	return r


## Model node tree in block coordinates (0..1, y up) for state st; be = block entity data (banner patterns).
static func build(st: int, be: Dictionary) -> Node3D:
	var b := Res.blocks
	var nm := b.name_of(st)
	var kind: String = _ids.get(b.st_block[st], "")
	var root := Node3D.new()
	root.set_meta("kind", kind)
	var inner := Node3D.new()      # Java: translate(0.5, 0, 0.5) + rotation about the block centre
	inner.position = Vector3(0.5, 0, 0.5)
	root.add_child(inner)
	var model := Node3D.new()      # back to block-corner origin
	model.position = Vector3(-0.5, 0, -0.5)
	inner.add_child(model)
	var face := b.get_prop(st, "facing") if b.has_prop(st, "facing") else ""
	match kind:
		"shelf":
			inner.rotation.y = {"north": 0.0, "east": -PI / 2.0, "south": PI, "west": PI / 2.0}.get(face, 0.0)
			Shelf.build_items(model, be)
		"chest":
			var type := b.get_prop(st, "type") if b.has_prop(st, "type") else "single"
			var base := "ender" if nm == "ender_chest" else ("trapped" if nm == "trapped_chest" else "normal")
			if nm.ends_with("copper_chest"):
				var ox := nm.replace("waxed_", "").trim_suffix("copper_chest").trim_suffix("_")
				base = "copper" if ox == "" else "copper_" + ox
			var tex := "entity/chest/" + base + ("" if type == "single" else "_" + type)
			var ts := Vector2(64, 64)
			inner.rotation.y = -deg_to_rad(float(YROT.get(face, 180.0)))
			var x0 := 1.0
			var w := 14.0
			var lock_x := 7.0
			var lock_w := 2.0
			if type == "left":
				x0 = 0.0
				w = 15.0
				lock_x = 0.0
				lock_w = 1.0
			elif type == "right":
				w = 15.0
				lock_x = 15.0
				lock_w = 1.0
			_part(model, Vector3.ZERO, Vector3(x0, 0, 1), Vector3(w, 10, 14), Vector2(0, 19), ts, tex)
			var lid := _part(model, Vector3(0, 9, 1), Vector3(x0, 0, 0), Vector3(w, 5, 14), Vector2(0, 0), ts, tex)
			_part(lid, Vector3.ZERO, Vector3(lock_x, -2, 14), Vector3(lock_w, 4, 1), Vector2(0, 0), ts, tex)
			root.set_meta("lid", lid)
		"shulker":
			var color := nm.trim_suffix("shulker_box").trim_suffix("_")
			var tex2 := "entity/shulker/shulker" + ("" if color == "" else "_" + color)
			# Java: translate(0.5,0.5,0.5), Direction.getRotation(), scale(1,-1,-1), translate(0,-1,0)
			var c := Node3D.new()
			c.position = Vector3(0, 0.5, 0)
			c.scale = Vector3.ONE * 0.9995
			inner.add_child(c)
			match face:
				"down":
					c.rotation.x = PI
				"north":
					c.rotation.x = -PI / 2
				"south":
					c.rotation.x = PI / 2
				"east":
					c.rotation.z = -PI / 2
				"west":
					c.rotation.z = PI / 2
			var holder := Node3D.new()
			holder.rotation.y = PI
			c.add_child(holder)
			var rigb := Node3D.new()
			rigb.position = Vector3(0, -0.5, 0)
			holder.add_child(rigb)
			_epart(rigb, Vector3.ZERO, Vector3(-8, -8, -8), Vector3(16, 8, 16), Vector2(0, 28), Vector2(64, 64), tex2)
			var lidp := Node3D.new()
			holder.add_child(lidp)
			var rigl := Node3D.new()
			rigl.position = Vector3(0, -0.5, 0)
			lidp.add_child(rigl)
			_epart(rigl, Vector3.ZERO, Vector3(-8, -16, -8), Vector3(16, 12, 16), Vector2(0, 0), Vector2(64, 64), tex2)
			root.set_meta("lid", lidp)
			model.queue_free()
		"skull":
			var wall := nm.contains("_wall_")
			var rot := 0.0
			if wall:
				var stp: Vector3 = STEP.get(face, Vector3.ZERO)
				inner.position = Vector3(0.5 - stp.x * 0.25, 0.25, 0.5 - stp.z * 0.25)
				rot = 180.0 + float(YROT.get(face, 0.0))
			else:
				rot = 22.5 * b.get_prop(st, "rotation").to_int()
			var head := Node3D.new()      # Java scale(-1,-1,1) frame == our entity space; head.yRot = rot
			head.rotation.y = -deg_to_rad(rot)
			inner.add_child(head)
			var mob := nm.replace("_wall_", "_").trim_suffix("_skull").trim_suffix("_head")
			match mob:
				"dragon":
					var dt := "entity/enderdragon/dragon"
					var d := Node3D.new()
					d.position = Vector3(0, 0.374375, 0)
					d.scale = Vector3.ONE * 0.75
					head.add_child(d)
					var dts := Vector2(256, 256)
					_epart(d, Vector3.ZERO, Vector3(-6, -1, -24), Vector3(12, 5, 16), Vector2(176, 44), dts, dt)
					_epart(d, Vector3.ZERO, Vector3(-8, -8, -10), Vector3(16, 16, 16), Vector2(112, 30), dts, dt)
					_epart(d, Vector3.ZERO, Vector3(-5, -12, -4), Vector3(2, 4, 6), Vector2(0, 0), dts, dt)
					_epart(d, Vector3.ZERO, Vector3(3, -12, -4), Vector3(2, 4, 6), Vector2(0, 0), dts, dt)
					_epart(d, Vector3.ZERO, Vector3(-5, -3, -22), Vector3(2, 2, 4), Vector2(112, 0), dts, dt)
					_epart(d, Vector3.ZERO, Vector3(3, -3, -22), Vector3(2, 2, 4), Vector2(112, 0), dts, dt)
					_epart(d, Vector3(0, 4, -8), Vector3(-6, 0, -16), Vector3(12, 4, 16), Vector2(176, 65), dts, dt)
				"piglin":
					var pt := "entity/piglin/piglin"
					var pts := Vector2(64, 64)
					_epart(head, Vector3.ZERO, Vector3(-5, -8, -4), Vector3(10, 8, 8), Vector2(0, 0), pts, pt)
					_epart(head, Vector3.ZERO, Vector3(-2, -4, -5), Vector3(4, 4, 1), Vector2(31, 1), pts, pt)
					_epart(head, Vector3.ZERO, Vector3(2, -2, -5), Vector3(1, 2, 1), Vector2(2, 4), pts, pt)
					_epart(head, Vector3.ZERO, Vector3(-3, -2, -5), Vector3(1, 2, 1), Vector2(2, 0), pts, pt)
					var le := _epart(head, Vector3(4.5, -6, 0), Vector3(0, 0, -2), Vector3(1, 5, 4), Vector2(51, 6), pts, pt)
					le.rotation.z = deg_to_rad(-30.0)
					var re := _epart(head, Vector3(-4.5, -6, 0), Vector3(-1, 0, -2), Vector3(1, 5, 4), Vector2(39, 6), pts, pt)
					re.rotation.z = deg_to_rad(30.0)
				_:
					var tex3 := "entity/skeleton/skeleton"
					var tsz := Vector2(64, 32)
					match mob:
						"wither_skeleton":
							tex3 = "entity/skeleton/wither_skeleton"
						"zombie":
							tex3 = "entity/zombie/zombie"
							tsz = Vector2(64, 64)
						"creeper":
							tex3 = "entity/creeper/creeper"
						"player":
							tex3 = "entity/player/wide/steve"
							tsz = Vector2(64, 64)
					_epart(head, Vector3.ZERO, Vector3(-4, -8, -4), Vector3(8, 8, 8), Vector2(0, 0), tsz, tex3)
					if mob == "player":
						_epart(head, Vector3.ZERO, Vector3(-4, -8, -4), Vector3(8, 8, 8), Vector2(32, 0), tsz, tex3, 0.25)
			model.queue_free()
		"banner":
			var color2 := nm.trim_suffix("_wall_banner").trim_suffix("_banner")
			var tint: Color = DYE.get(color2, Color.WHITE)
			var tb := "entity/banner/banner_base"
			var t := Node3D.new()
			inner.add_child(t)
			var wall2 := nm.ends_with("_wall_banner")
			if wall2:
				inner.position = Vector3(0.5, -1.0 / 6.0, 0.5)
				inner.rotation.y = -deg_to_rad(float(YROT.get(face, 0.0)))
				t.position = Vector3(0, -0.3125, -0.4375)
			else:
				inner.position = Vector3(0.5, 0.5, 0.5)
				inner.rotation.y = -deg_to_rad(22.5 * b.get_prop(st, "rotation").to_int())
			# Java scale(2/3, -2/3, -2/3) == our entity space turned 180 degrees about Y, scaled
			var sc := Node3D.new()
			sc.scale = Vector3.ONE * (2.0 / 3.0)
			sc.rotation.y = PI
			t.add_child(sc)
			var ts4 := Vector2(64, 64)
			var flag := _epart(sc, Vector3(0, -32, 0), Vector3(-10, 0, -2), Vector3(20, 40, 1), Vector2(0, 0), ts4, tb, 0.0, tint)
			root.set_meta("flag", flag)
			# pattern layers (block entity "patterns"), each slightly in front of the previous one
			var li := 0
			for l in be.get("patterns", []):
				li += 1
				var stl := SurfaceTool.new()
				stl.begin(Mesh.PRIMITIVE_TRIANGLES)
				EntityRenderer.box_arrays(Vector3(-10, 0, -2), Vector3(20, 40, 1), Vector2(0, 0), ts4, stl, 0.04 * li, DYE.get(str(l.get("color", "white")), Color.WHITE))
				var mil := MeshInstance3D.new()
				mil.mesh = stl.commit()
				mil.material_override = EntityRenderer.material(Banners.texture(str(l.get("pattern", ""))))
				flag.add_child(mil)
			if not wall2:
				_epart(sc, Vector3.ZERO, Vector3(-1, -30, -1), Vector3(2, 42, 2), Vector2(44, 0), ts4, tb)
			_epart(sc, Vector3.ZERO, Vector3(-10, -32, -1), Vector3(20, 2, 2), Vector2(0, 42), ts4, tb)
			model.queue_free()
		"end_portal", "end_gateway":
			_portal_faces(model, kind)
		"enchanting_table":
			root.set_meta("book", _book_parts(inner))
			model.queue_free()
		"campfire":
			# Java CampfireRenderer: slot l at (0.5, 0.44921875, 0.5), turned -toYRot of the direction (l + facing 2D) % 4,
			# laid flat (X 90), shifted (-0.3125, -0.3125, 0) and scaled 0.375 (FIXED display)
			var its: Array = be.get("items", [])
			var f2d: int = {"south": 0, "west": 1, "north": 2, "east": 3}.get(face, 0)
			var any := false
			for l in mini(4, its.size()):
				var cs := ItemStack.from_dict(its[l])
				if cs.is_empty():
					continue
				var nd := HeldItems.item_node(cs, "fixed", false)
				if nd == null:
					continue
				var yr: float = [0.0, 90.0, 180.0, 270.0][(l + f2d) % 4]
				var hold := Node3D.new()
				hold.transform = Transform3D(Basis(), Vector3(0.5, 0.44921875, 0.5)) * Transform3D(Basis(Vector3.UP, deg_to_rad(-yr)), Vector3.ZERO) * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3.ZERO) * Transform3D(Basis(), Vector3(-0.3125, -0.3125, 0.0)) * Transform3D(Basis.from_scale(Vector3.ONE * 0.375), Vector3.ZERO)
				hold.add_child(nd)
				model.add_child(hold)
				any = true
			if not any:
				root.queue_free()
				return null
		"spawner", "trial_spawner":
			# trial spawners (TrialSpawnerRenderer) show the mob they spawn next while waiting for players / active
			var smob := str(be.get("mob", ""))
			if kind == "trial_spawner":
				var tss := b.get_prop(st, "trial_spawner_state")
				smob = Trials.display_mob(be) if str(be.get("id", "")) == "trial_spawner" and (tss == "waiting_for_players" or tss == "active") else ""
			if not _spawner_mob(inner, smob):
				root.queue_free()
				return null
			root.set_meta("spin", inner.get_child(inner.get_child_count() - 1))
			model.queue_free()
		"bell":
			# Java BellModel: bell_body (pivot 8, 12, 8) with bell_base as its child, so the lip swings with the body
			var body := _part(model, Vector3(8, 12, 8), Vector3(-3, -6, -3), Vector3(6, 7, 6), Vector2(0, 0), Vector2(32, 32), "entity/bell/bell_body")
			_part(body, Vector3(-8, -12, -8), Vector3(4, 4, 4), Vector3(8, 2, 8), Vector2(0, 13), Vector2(32, 32), "entity/bell/bell_body")
			root.set_meta("bell_body", body)
		"pot":
			inner.rotation.y = deg_to_rad(180.0 - float(YROT.get(face, 180.0)))
			var bt := "entity/decorated_pot/decorated_pot_base"
			var sd := "entity/decorated_pot/decorated_pot_side"
			var neck := Node3D.new()
			neck.position = Vector3(0, 37, 16) / 16.0
			neck.rotation.x = PI
			model.add_child(neck)
			_part(neck, Vector3.ZERO, Vector3(4, 17, 4), Vector3(8, 3, 8), Vector2(0, 0), Vector2(32, 32), bt, -0.1)
			_part(neck, Vector3.ZERO, Vector3(5, 20, 5), Vector3(6, 1, 6), Vector2(0, 5), Vector2(32, 32), bt, 0.2)
			var t32 := Vector2(32, 32)
			_quad(model, [Vector3(1, 16, 1), Vector3(1, 16, 15), Vector3(15, 16, 15), Vector3(15, 16, 1)], Rect2(14, 13, 14, 14), t32, bt, 1.0)
			_quad(model, [Vector3(1, 0, 15), Vector3(1, 0, 1), Vector3(15, 0, 1), Vector3(15, 0, 15)], Rect2(0, 13, 14, 14), t32, bt, 0.5)
			var s16 := Vector2(16, 16)
			var sr := Rect2(1, 0, 14, 16)
			# Java PotDecorations (back, left, right, front): a sherd shows its <name>_pottery_pattern, bricks / none
			# the plain side (model: front = z 1, back = z 15, left = x 15, right = x 1 before the facing turn)
			var sh: Array = be.get("sherds", []) if be.get("sherds", []) is Array else []
			var side := func(i: int) -> String:
				var it := str(sh[i]).trim_prefix("minecraft:") if i < sh.size() else ""
				return "entity/decorated_pot/" + it.trim_suffix("_sherd") + "_pattern" if it.ends_with("_pottery_sherd") else sd
			_quad(model, [Vector3(1, 16, 15), Vector3(1, 0, 15), Vector3(15, 0, 15), Vector3(15, 16, 15)], sr, s16, side.call(0), 0.8)
			_quad(model, [Vector3(15, 16, 1), Vector3(15, 0, 1), Vector3(1, 0, 1), Vector3(1, 16, 1)], sr, s16, side.call(3), 0.8)
			_quad(model, [Vector3(15, 16, 15), Vector3(15, 0, 15), Vector3(15, 0, 1), Vector3(15, 16, 1)], sr, s16, side.call(1), 0.6)
			_quad(model, [Vector3(1, 16, 1), Vector3(1, 0, 1), Vector3(1, 0, 15), Vector3(1, 16, 15)], sr, s16, side.call(2), 0.6)
		"conduit":
			var cs := Node3D.new()
			cs.position = Vector3(0, 0.5, 0)
			inner.add_child(cs)
			_epart(cs, Vector3.ZERO, Vector3(-3, -3, -3), Vector3(6, 6, 6), Vector2(0, 0), Vector2(32, 16), "entity/conduit/base")
			if str(be.get("id", "")) == "conduit":
				root.set_meta("conduit", _conduit_parts(inner, cs))
			model.queue_free()
		_:
			root.queue_free()
			return null
	return root


## Item form (Java *SpecialRenderer defaults): chests facing south, skulls rotated 180, banners rotation 0,
## shulker boxes up. be may carry banner patterns.
static func item_state(item_block: int) -> int:
	var b := Res.blocks
	var st := item_block
	if b.has_prop(st, "facing"):
		st = b.with_prop(st, "facing", "up" if b.name_of(st).ends_with("shulker_box") else "south")
	if b.has_prop(st, "rotation"):
		st = b.with_prop(st, "rotation", "8" if b.name_of(st).ends_with("_skull") or b.name_of(st).ends_with("_head") else "0")
	if b.has_prop(st, "type"):
		st = b.with_prop(st, "type", "single")
	return st


## Special item model (Java SpecialModelWrapper) with the item model's display transform for context` (gui, ground,
## firstperson_righthand, ...): holder -> model offset by -0.5 (Java ItemRenderer translate(-0.5)). Null for other items.
static func item_node(item: int, context: String, be: Dictionary = {}, using := false) -> Node3D:
	if item <= 0 or Res.mode != "vanilla":
		return null
	if Res.items.names[item] == "shield":
		return shield_node(context, using, be)
	var pb: int = Res.items.place_block[item]
	ensure_ids()
	if pb <= 0 or not tracked(pb):
		return null
	var node := build(item_state(pb), be)
	if node == null:
		return null
	var holder := Node3D.new()
	holder.transform = display_transform(ItemIcons.display(Res.items.names[item], context), context.ends_with("lefthand"))
	node.position += Vector3(-0.5, -0.5, -0.5)
	holder.add_child(node)
	holder.set_meta("special", true)
	return holder


## Java ShieldModel (plate 12x22x1, handle 2x6x6) under the item's special transformation scale(1,-1,-1);
## display from item/shield or item/shield_blocking (Java items/shield.json using_item condition).
static func shield_node(context: String, blocking: bool, be: Dictionary = {}) -> Node3D:
	var h := Node3D.new()
	h.transform = display_transform(ItemIcons.model_display("item/shield_blocking" if blocking else "item/shield", context), context.ends_with("lefthand"))
	var m := Node3D.new()
	m.position = Vector3(-0.5, -0.5, -0.5)
	m.rotation.y = PI    # Java scale(1,-1,-1) == our flipped entity space turned 180 degrees about Y
	h.add_child(m)
	# Java ShieldSpecialRenderer: plain shields use shield_base_nopattern; decorated ones shield_base + base colour +
	# pattern layers (entity/shield/<pattern>) on the plate
	var base_col = be.get("base_color")
	var layers: Array = be.get("patterns", [])
	var decorated: bool = base_col != null
	var tex := "entity/shield/shield_base" if decorated else "entity/shield/shield_base_nopattern"
	_epart(m, Vector3.ZERO, Vector3(-6, -11, -2), Vector3(12, 22, 1), Vector2(0, 0), Vector2(64, 64), tex)
	_epart(m, Vector3.ZERO, Vector3(-1, -3, -1), Vector3(2, 6, 6), Vector2(26, 0), Vector2(64, 64), tex)
	if decorated:
		var all: Array = [{"pattern": "minecraft:base", "color": str(base_col)}]
		all.append_array(layers)
		var li := 0
		for l in all:
			li += 1
			var asset := Banners.texture(str(l.get("pattern", ""))).replace("entity/banner/", "entity/shield/")
			_epart(m, Vector3.ZERO, Vector3(-6, -11, -2), Vector3(12, 22, 1), Vector2(0, 0), Vector2(64, 64), asset, 0.01 * li, DYE.get(str(l.get("color", "white")), Color.WHITE))
	h.set_meta("special", true)
	return h


## Java ItemTransform.apply: translate(t/16), rotationXYZ, scale; left-hand contexts mirror x translation and the
## y/z rotations.
static func display_transform(d: Dictionary, left := false) -> Transform3D:
	var r: Array = d.get("rotation", [0, 0, 0])
	var t: Array = d.get("translation", [0, 0, 0])
	var sc: Array = d.get("scale", [1, 1, 1])
	var m := -1.0 if left else 1.0
	var basis := Basis(Vector3.RIGHT, deg_to_rad(float(r[0]))) * Basis(Vector3.UP, deg_to_rad(m * float(r[1]))) * Basis(Vector3(0, 0, 1), deg_to_rad(m * float(r[2])))
	return Transform3D(basis.scaled_local(Vector3(float(sc[0]), float(sc[1]), float(sc[2]))), Vector3(m * float(t[0]), float(t[1]), float(t[2])) / 16.0)


static func set_light(n: Node, v: Vector2, gui: bool = false) -> void:
	for mi in _meshes(n):
		(mi as MeshInstance3D).set_instance_shader_parameter("light", v)
		if gui:
			(mi as MeshInstance3D).set_instance_shader_parameter("gui_items", 1.0)   # Java ITEMS_3D lighting
