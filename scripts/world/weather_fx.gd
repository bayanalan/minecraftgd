## WeatherFX — falling rain and snow (Java WeatherEffectRenderer): every column within 10 blocks of the camera
## (5 with Fast graphics) whose biome has precipitation gets a camera-facing quad from max(camera y - r, motion
## blocking height) to max(camera y + r, height), textured with environment/rain.png (snow.png where the height
## adjusted temperature is below 0.15), scrolling by Java's per-column speed (3..4 / 32 texture heights per tick),
## alpha ((1 - (d² / r²)²) * 0.5 + 0.5) * rain level, lit by the column's light.
##
## Cost model (rain must cost ~nothing): the columns are grouped in world-aligned 4 x 4 tiles, one MultiMesh pair per
## tile with a tight AABB, so Godot drops the tiles outside the view (most of the 21 x 21 area); each tile draws the
## streak mesh with only as many texture repeats as its tallest column crosses (4 when standing on the ground instead
## of 7). Everything that changes per frame (camera height / distance, alpha, scroll, partial tick) is computed in
## shaders/weather.gdshader from the column's constant data, and a column's data (height, precipitation, light,
## per-column random values) is only recomputed when it can change: when it enters the area, when the camera crosses a
## block level, when a block in it changes (WorldManager.set_block) and once per second round-robin.
class_name WeatherFX
extends Node3D

const TILE := 4
const MAXREP := 6   # a column is at most 2 r = 20 blocks = 5 texture heights tall: 6 repeats with the offset
const INVALID := -999999
var world
var frozen := false
var full_quads := false

var _precip := {}   # column key -> (precipitation << 16) | (y >> 4) (biome cache)
var _rng := RandomNumberGenerator.new()
var _mat: Array = []                 # [rain, snow] ShaderMaterial shared by every tile
var _meshes: Array = [[], []]        # per kind: streak meshes with 1..MAXREP texture repeats (index = repeats - 1)
var _full_quad: ArrayMesh = null
var _cols := {}                      # column key -> Col
var _tiles := {}                     # tile key -> Tile
var _pool: Array = []                # hidden tiles
var _dirty_cols := {}                # column keys changed by set_block
var _rr: Array = []                  # round-robin refresh order (column keys)
var _rr_i := 0
var _active := false
var _cx := INVALID
var _cy := INVALID
var _cz := INVALID
var _r := 0
var _org := Vector3i(INVALID, 0, 0)
var _lvl := -1.0


class Col:
	var x := 0
	var z := 0
	var k1 := INVALID     # motion-blocking height (INVALID: chunk not ready)
	var kind := 0         # 0 none, 1 rain, 2 snow
	var light := 0        # (sky << 4) | block at max(camera y, height)
	var top := 0          # state under the motion-blocking height (rain splashes / smoke, Particles)
	var a := 0.0          # per-column random values (Java seeds a RandomSource with the column hash)
	var b := 0.0
	var c := 0.0
	var d := 0.0
	var j := 0            # rain scroll offset hash & 0xFF


class Tile:
	var key := 0
	var tx := 0
	var tz := 0
	var mmi: Array = []   # [rain, snow] MultiMeshInstance3D
	var mm: Array = []    # [rain, snow] MultiMesh
	var cols: Array = []  # Col
	var dirty := true
	var reps := [-1, -1]


## One quad per vertical run of visible texels (alpha > 0) of the weather texture, `reps` copies each (and both u wraps
## when the texture scrolls sideways): VERTEX = corner (0 / 1, 0 / 1), UV = (run column u, run start v), UV2 = (run end
## v, repeat + 16 * u wrap). Drawn instead of the whole column quad (see the shader): same pixels, ~40x fewer fragments.
static func _streak_mesh(img: Image, u_wraps: int, reps: int) -> ArrayMesh:
	var w := img.get_width()
	var h := img.get_height()
	var runs: Array = []   # [x, y0, y1)
	for x in w:
		var y := 0
		while y < h:
			if img.get_pixel(x, y).a <= 0.0:
				y += 1
				continue
			var y0 := y
			while y < h and img.get_pixel(x, y).a > 0.0:
				y += 1
			runs.append(Vector3i(x, y0, y))
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for r in runs:
		for wrap in u_wraps:
			for k in reps:
				var b := verts.size()
				for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
					verts.append(Vector3(corner.x, corner.y, 0))
					uv.append(Vector2(float(r.x) / w, float(r.y) / h))
					uv2.append(Vector2(float(r.z) / h, float(k + 16 * wrap)))
				idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-64, -64, -64), Vector3(128, 512, 128))
	return mesh


func _ready() -> void:
	for k in 2:
		var img: Image = Res.load_image("environment/" + ("rain" if k == 0 else "snow")) if Res.mode == "vanilla" else null
		if img == null:
			img = Image.create(1, 1, false, Image.FORMAT_RGBA8)
			img.fill(Color(1, 1, 1, 1))
		for reps in range(1, MAXREP + 1):
			(_meshes[k] as Array).append(_streak_mesh(img, 1 if k == 0 else 2, reps))   # rain never scrolls sideways
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/weather.gdshader")
		m.set_shader_parameter("texel_w", 1.0 / img.get_width())
		m.set_shader_parameter("snow", k == 1)
		if Res.mode == "vanilla":
			m.set_shader_parameter("tex", ImageTexture.create_from_image(img))
		_mat.append(m)


func _new_tile() -> Tile:
	if not _pool.is_empty():
		return _pool.pop_back()
	var t := Tile.new()
	for k in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = TILE * TILE
		mm.visible_instance_count = 0
		mm.mesh = _meshes[k][MAXREP - 1]
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mat[k]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		t.mm.append(mm)
		t.mmi.append(mi)
	return t


func _free_tile(t: Tile) -> void:
	for mi in t.mmi:
		(mi as MultiMeshInstance3D).visible = false
	t.cols.clear()
	t.reps = [-1, -1]
	_pool.append(t)


## --raincheck: whole column quads with shaders/weather_full.gdshader (same instance data) instead of the runs.
func set_full_quad(on: bool) -> void:
	if _full_quad == null:
		_full_quad = ArrayMesh.new()
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		_full_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_full_quad.custom_aabb = AABB(Vector3(-64, -64, -64), Vector3(128, 512, 128))
	full_quads = on
	for k in 2:
		(_mat[k] as ShaderMaterial).shader = load("res://shaders/weather_full.gdshader" if on else "res://shaders/weather.gdshader")
	for t in _tiles.values():
		(t as Tile).reps = [-1, -1]
		(t as Tile).dirty = true
	_update_tiles()


## Frozen (--raincheck): the shaders use this time instead of the running tick + partial tick.
func set_partial(pt: float) -> void:
	var want := (float(int(world.game_time) & 131071) + pt) if frozen else -1.0
	if (want < 0.0) == (_fixed < 0.0):
		return
	_fixed = want
	for m in _mat:
		(m as ShaderMaterial).set_shader_parameter("fixed_time", want)


var _fixed := -1.0


## A block changed (WorldManager.set_block): its column's height / light may have changed.
func block_changed(x: int, z: int) -> void:
	if _active and absi(x - _cx) <= _r and absi(z - _cz) <= _r:
		_dirty_cols[(x << 32) ^ (z & 0xFFFFFFFF)] = true


## Java Biome.getPrecipitationAt for a column at height y: 0 none, 1 rain, 2 snow.
func _precip_at(x: int, y: int, z: int) -> int:
	var key := (x << 32) ^ (z & 0xFFFFFFFF)
	var v = _precip.get(key)
	if v != null and (int(v) & 0xFFFF) == ((y >> 4) & 0xFFFF):
		return int(v) >> 16
	var r := 0
	var ch: Chunk = world.cm.get_chunk(x >> 4, z >> 4)
	if ch != null and not ch.biomes.is_empty():
		var bio := ch.biome_at(x & 15, y, z & 15)
		if bio >= 0 and world.biomes.precipitation[bio] != 0:
			var t: float = world.biomes.temperature[bio]
			if y > 80:
				t -= float(y - 80) * 0.05 / 40.0
			r = 2 if t < 0.15 else 1
	if _precip.size() > 20000:
		_precip.clear()
	_precip[key] = (r << 16) | ((y >> 4) & 0xFFFF)
	return r


## The column's current height / precipitation / light; true when anything the tile draws changed.
func _compute(col: Col) -> bool:
	var ch: Chunk = world.cm.chunks.get(((col.x >> 4) << 32) | ((col.z >> 4) & 0xFFFFFFFF))
	var k1 := INVALID
	var kind := 0
	var lt := 0
	if ch != null and not ch.heightmap.is_empty():
		k1 = ch.heightmap[(col.x & 15) + (col.z & 15) * 16]
		var yy := maxi(_cy, k1)
		kind = _precip_at(col.x, yy, col.z)
		if kind != 0:
			lt = world.cm.get_light(col.x, yy, col.z)
		col.top = world.state_at(col.x, k1 - 1, col.z)
	if k1 == col.k1 and kind == col.kind and lt == col.light:
		return false
	col.k1 = k1
	col.kind = kind
	col.light = lt
	return true


func _new_col(x: int, z: int) -> Col:
	var col := Col.new()
	col.x = x
	col.z = z
	# Java createRainColumnInstance / createSnowColumnInstance: RandomSource seeded with this hash per column; rain
	# speed 3 + nextFloat, snow u / v drift nextFloat + t x nextGaussian terms (same draw order)
	_rng.seed = x * x * 3121 + x * 45238971 ^ z * z * 418711 + z * 13761
	col.a = _rng.randf()
	col.b = _rng.randfn()
	col.c = _rng.randf()
	col.d = _rng.randfn()
	col.j = (x * x * 3121 + x * 45238971 + z * z * 418711 + z * 13761) & 0xFF
	_compute(col)
	return col


func _hide_all() -> void:
	for t in _tiles.values():
		_free_tile(t)
	_tiles.clear()
	_cols.clear()
	_rr.clear()
	_dirty_cols.clear()
	_cx = INVALID
	_cy = INVALID
	_active = false


func tick() -> void:
	if frozen:
		return
	var lvl: float = world.rain
	if lvl <= 0.0 or world.dimension != "overworld" or str(Settings.get_v("weather_fx")) == "off":
		if _active:
			_hide_all()
		return
	_active = true
	if lvl != _lvl:
		_lvl = lvl
		for m in _mat:
			(m as ShaderMaterial).set_shader_parameter("level", lvl)
	var cam: Vector3 = world.camera.global_position + Vector3(world.cm.origin)
	var cx := floori(cam.x)
	var cy := floori(cam.y)
	var cz := floori(cam.z)
	var r := 5 if str(Settings.get_v("graphics")) == "fast" else 10
	var org: Vector3i = world.cm.origin
	if r != _r or org != _org:
		_hide_all()
		_active = true
		_r = r
		_org = org
		for m in _mat:
			(m as ShaderMaterial).set_shader_parameter("radius", float(r))
	var relight := cy != _cy
	_cy = cy
	if cx != _cx or cz != _cz:
		_reframe(cx, cz, r)
	if relight:
		# light / precipitation are taken at max(camera y, height)
		for col in _cols.values():
			if _compute(col):
				_tile_of(col).dirty = true
		for t in _tiles.values():
			(t as Tile).dirty = true   # repeats / bounds follow the camera height
	else:
		for key in _dirty_cols:
			var dc = _cols.get(key)
			if dc != null and _compute(dc):
				_tile_of(dc).dirty = true
		# round robin: every column refreshed once a second (light from nearby block changes, chunks that just loaded)
		var n := mini(_rr.size(), maxi(1, _rr.size() / 20))
		for i in n:
			_rr_i = (_rr_i + 1) % _rr.size()
			var rc = _cols.get(_rr[_rr_i])
			if rc != null and _compute(rc):
				_tile_of(rc).dirty = true
	_dirty_cols.clear()
	_update_tiles()


func _tile_of(col: Col) -> Tile:
	return _tiles[((col.x >> 2) << 32) ^ ((col.z >> 2) & 0xFFFFFFFF)]


## The camera moved to another column: drop the columns / tiles that left the area, add the new ones.
func _reframe(cx: int, cz: int, r: int) -> void:
	for key in _cols.keys():
		var col: Col = _cols[key]
		if absi(col.x - cx) > r or absi(col.z - cz) > r:
			var t: Tile = _tile_of(col)
			t.cols.erase(col)
			t.dirty = true
			_cols.erase(key)
			if t.cols.is_empty():
				_tiles.erase(t.key)
				_free_tile(t)
	for z in range(cz - r, cz + r + 1):
		for x in range(cx - r, cx + r + 1):
			var key := (x << 32) ^ (z & 0xFFFFFFFF)
			if _cols.has(key):
				continue
			var col := _new_col(x, z)
			_cols[key] = col
			var tk := ((x >> 2) << 32) ^ ((z >> 2) & 0xFFFFFFFF)
			var t = _tiles.get(tk)
			if t == null:
				t = _new_tile()
				t.key = tk
				t.tx = x >> 2
				t.tz = z >> 2
				_tiles[tk] = t
			(t as Tile).cols.append(col)
			(t as Tile).dirty = true
	_rr = _cols.keys()
	_cx = cx
	_cz = cz


## Rebuilds the instance buffers of changed tiles: transform = per-column constants for the shader (origin = column
## centre at its motion-blocking height, basis columns = random values / scroll hash / light), never per frame.
func _update_tiles() -> void:
	var ox := float(_org.x)
	var oz := float(_org.z)
	var r := _r
	var cy := _cy
	for tv in _tiles.values():
		var t: Tile = tv
		if not t.dirty:
			continue
		t.dirty = false
		var b0 := PackedFloat32Array()
		var b1 := PackedFloat32Array()
		var n := [0, 0]
		var kmin := [INVALID, INVALID]
		var kmax := [INVALID, INVALID]
		for cv in t.cols:
			var col: Col = cv
			if col.kind == 0 or col.k1 == INVALID or col.k1 >= cy + r + 3:
				continue   # no precipitation, not loaded, or the column ends below its height (height 0)
			var k := col.kind - 1
			var o: int = n[k] * 12
			var row := PackedFloat32Array([col.a, col.d, 0.0, col.x + 0.5 - ox, col.b, float(col.j), 0.0, float(col.k1), col.c, float(col.light), 1.0, col.z + 0.5 - oz])
			# rows of the 3x4 transform: MODEL_MATRIX[0] = (a, b, c), [1] = (d, j, light), [2] = (0, 0, 1), [3] = origin
			if k == 0:
				if b0.is_empty():
					b0.resize(TILE * TILE * 12)
				for i in 12:
					b0[o + i] = row[i]
			else:
				if b1.is_empty():
					b1.resize(TILE * TILE * 12)
				for i in 12:
					b1[o + i] = row[i]
			n[k] += 1
			kmin[k] = col.k1 if kmin[k] == INVALID else mini(kmin[k], col.k1)
			kmax[k] = col.k1 if kmax[k] == INVALID else maxi(kmax[k], col.k1)
		for k in 2:
			var mi: MultiMeshInstance3D = t.mmi[k]
			var mm: MultiMesh = t.mm[k]
			if n[k] == 0:
				mi.visible = false
				mm.visible_instance_count = 0
				continue
			# texture repeats the tallest column of this tile crosses (+2 blocks: the camera height is per frame)
			var lo := maxi(cy - r, kmin[k]) - 2
			var hi := maxi(cy + r, kmax[k]) + 2
			var hmax := mini(2 * r, hi - lo)
			var reps := MAXREP if full_quads else clampi(int(ceil(hmax / 4.0)) + 1, 1, MAXREP)
			if reps != t.reps[k]:
				t.reps[k] = reps
				mm.mesh = _full_quad if full_quads else _meshes[k][reps - 1]
			mm.buffer = b0 if k == 0 else b1
			mm.visible_instance_count = n[k]
			mi.custom_aabb = AABB(Vector3(t.tx * TILE - ox - 1.0, lo, t.tz * TILE - oz - 1.0), Vector3(TILE + 2.0, hi - lo, TILE + 2.0))
			mi.visible = true
