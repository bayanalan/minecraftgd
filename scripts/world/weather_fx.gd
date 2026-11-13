## WeatherFX — falling rain and snow (Java WeatherEffectRenderer): every column within 10 blocks of the camera
## (5 with Fast graphics) whose biome has precipitation gets a camera-facing quad from max(camera y - r, motion
## blocking height) to max(camera y + r, height), textured with environment/rain.png (snow.png where the height
## adjusted temperature is below 0.15), scrolling by Java's per-column speed (3..4 / 32 texture heights per tick),
## alpha ((1 - (d² / r²)²) * 0.5 + 0.5) * rain level, lit by the column's light. Two MultiMeshes refreshed once per
## game tick; the per-frame part (billboarding, partial-tick scroll) is in shaders/weather.gdshader.
class_name WeatherFX
extends Node3D

const MAXN := 441
var world
var _mm: Array = []      # [rain, snow] MultiMesh
var _mat: Array = []
var _precip := {}         # column key -> 0 none, 1 rain, 2 snow (biome cached)
var _rng := RandomNumberGenerator.new()


## Copies of every visible-texel run per column instance: a column is at most 20 blocks = 5 texture heights tall, so a
## run can appear at 7 texture repeats (shaders/weather.gdshader picks and clips them).
const REPEATS := 7


## One quad per vertical run of visible texels (alpha > 0) of the weather texture, REPEATS copies each (and both u wraps
## when the texture scrolls sideways): VERTEX = corner (0 / 1, 0 / 1), UV = (run column u, run start v), UV2 = (run end
## v, repeat + 16 * u wrap). Drawn instead of the whole column quad (see the shader): same pixels, ~40x fewer
## fragments.
static func _streak_mesh(img: Image, u_wraps: int) -> ArrayMesh:
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
			for k in REPEATS:
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
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _streak_mesh(img, 1 if k == 0 else 2)   # rain never scrolls sideways (u offset 0)
		_streak_meshes.append(mm.mesh)
		mm.instance_count = MAXN
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/weather.gdshader")
		m.set_shader_parameter("texel_w", 1.0 / img.get_width())
		if Res.mode == "vanilla":
			m.set_shader_parameter("tex", ImageTexture.create_from_image(img))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mm.append(mm)
		_mat.append(m)


## Verification (--raincheck): frozen keeps the current columns and partial tick; full_quad draws the whole column quads
## with the previous shader (shaders/weather_full.gdshader) instead of the visible-texel runs.
var frozen := false
var _streak_meshes: Array = []
var _full_quad: ArrayMesh = null


func set_full_quad(on: bool) -> void:
	if _full_quad == null:
		_full_quad = ArrayMesh.new()
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		_full_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_full_quad.custom_aabb = AABB(Vector3(-64, -64, -64), Vector3(128, 512, 128))
	for k in 2:
		(_mm[k] as MultiMesh).mesh = _full_quad if on else _streak_meshes[k]
		(_mat[k] as ShaderMaterial).shader = load("res://shaders/weather_full.gdshader" if on else "res://shaders/weather.gdshader")


func set_partial(pt: float) -> void:
	if frozen:
		return
	for m in _mat:
		(m as ShaderMaterial).set_shader_parameter("partial", pt)


## Java Biome.getPrecipitationAt for a column at height y: 0 none, 1 rain, 2 snow.
func _precip_at(x: int, y: int, z: int) -> int:
	var key := (x << 32) ^ (z & 0xFFFFFFFF)
	var v = _precip.get(key)
	if v != null and (int(v) & 0xFFFF) == (y >> 4):
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


func tick() -> void:
	if frozen:
		return
	var lvl: float = world.rain
	if lvl <= 0.0 or world.dimension != "overworld" or str(Settings.get_v("weather_fx")) == "off":
		for mm in _mm:
			(mm as MultiMesh).visible_instance_count = 0
		return
	var cam: Vector3 = world.camera.global_position + Vector3(world.cm.origin)
	var cx := floori(cam.x)
	var cy := floori(cam.y)
	var cz := floori(cam.z)
	var r := 5 if str(Settings.get_v("graphics")) == "fast" else 10
	var ticks: int = world.game_time
	var n := [0, 0]
	var orgv := Vector3(world.cm.origin)
	var last_ck := 0x7FFFFFFFFFFFFFFF
	var ch: Chunk = null
	for z in range(cz - r, cz + r + 1):
		for x in range(cx - r, cx + r + 1):
			var ck := ((x >> 4) << 32) | ((z >> 4) & 0xFFFFFFFF)
			if ck != last_ck:
				last_ck = ck
				ch = world.cm.chunks.get(ck)
			if ch == null or ch.heightmap.is_empty():
				continue
			var k1: int = ch.heightmap[(x & 15) + (z & 15) * 16]
			var l1 := maxi(cy - r, k1)
			var i2 := maxi(cy + r, k1)
			if i2 - l1 == 0:
				continue
			var pr := _precip_at(x, maxi(cy, k1), z)
			if pr == 0:
				continue
			var kind := pr - 1
			if n[kind] >= MAXN:
				continue
			_rng.seed = x * x * 3121 + x * 45238971 ^ z * z * 418711 + z * 13761
			var lt: int = world.cm.get_light(x, maxi(cy, k1), z)
			var sky := (lt >> 4) & 15
			var blk := lt & 15
			var u_off := 0.0
			var v_off := 0.0
			var spd := 0.0
			if kind == 0:
				# Java createRainColumnInstance
				var j := (x * x * 3121 + x * 45238971 + z * z * 418711 + z * 13761) & 0xFF
				var f := 3.0 + _rng.randf()
				spd = -f / 32.0
				v_off = fmod(-float((ticks & 131071) + j) / 32.0 * f, 32.0)
			else:
				# Java createSnowColumnInstance (light raised: (l * 3 + 15) / 4)
				var t := float(ticks & 511)
				u_off = _rng.randf() + t * 0.01 * _rng.randfn()
				v_off = _rng.randf() + t * _rng.randfn() * 0.001 - t / 512.0
				spd = -1.0 / 512.0
				sky = (sky * 3 + 15) / 4
				blk = (blk * 3 + 15) / 4
			var dx := x + 0.5 - cam.x
			var dz := z + 0.5 - cam.z
			var f3 := (dx * dx + dz * dz) / float(r * r)
			var a := ((1.0 - f3 * f3) * 0.5 + 0.5) * lvl
			var mm: MultiMesh = _mm[kind]
			var xf := Transform3D(Basis(Vector3(spd, 0, 0), Vector3(0, float(i2 - l1), 0), Vector3(0, 0, 1)), Vector3(x + 0.5, l1, z + 0.5) - orgv)
			mm.set_instance_transform(n[kind], xf)
			mm.set_instance_custom_data(n[kind], Color(u_off, v_off, clampf(a, 0.0, 1.0), float(blk * 16 + sky) / 255.0))
			n[kind] += 1
	for k in 2:
		(_mm[k] as MultiMesh).visible_instance_count = n[k]
