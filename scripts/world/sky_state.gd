class_name SkyState
extends RefCounted
## Java 26.3 sky / fog / light environment for the camera, recomputed every frame (WorldManager._update_sky):
## - base attributes from the dimension type (minecraft:visual/*), biome sky / fog colours blended with Java's
##   CubicSampler gaussian kernel over the 6x6x6 biome quarts around the camera;
## - the dimension's timelines (day.json: sky / fog / cloud colour multipliers, sky light colour and factor, star
##   brightness, sunrise-sunset colour, sun / moon / star angles; moon.json: moon phase);
## - weather and the camera (FogRenderer colour logic: sunrise tint towards the sun, render-distance blend towards the
##   sky colour, rain / thunder darkening, void darkening near the world bottom).
## All colours are sRGB (Java renders in gamma space); shaders convert after mixing.

const GAUSS := [0.0, 1.0, 4.0, 6.0, 4.0, 1.0, 0.0]   # CubicSampler.GAUSSIAN_SAMPLE_KERNEL

var timelines: Array = []
var sky_color := Color(0.47, 0.65, 1.0)
var fog_color := Color(0.75, 0.85, 1.0)
var cloud_color := Color(1, 1, 1, 0.8)
var sky_light_color := Color(1, 1, 1)
var sky_light_factor := 1.0
var ambient_color := Color(0.04, 0.04, 0.04)
var star_brightness := 0.0
var sunrise := Color(0, 0, 0, 0)
var sun_angle := 0.0     # radians (0: overhead at noon)
var moon_angle := PI
var star_angle := 0.0
var moon_phase := "full_moon"
var _bio_key := Vector3i(1 << 30, 0, 0)
var _bio_sky: Array = []    # 216 sRGB colours of the quarts around the camera
var _bio_fog: Array = []


var _attr: Dictionary = {}   # parsed dimension attributes (per dimension; parsing the hex strings every frame cost)


func setup(dim_type: Dictionary) -> void:
	timelines = Timeline.for_dimension(dim_type)
	_bio_key = Vector3i(1 << 30, 0, 0)
	_attr = {}
	_ukey = Vector4i(-2147483648, 0, 0, 0)   # recompute the per-tick part for the new dimension


func _ac(dt: Dictionary, key: String, default: Color) -> Color:
	var v = _attr.get(key)
	if v == null:
		v = attr_color(dt, key, default)
		_attr[key] = v
	return v


func _af(dt: Dictionary, key: String, default: float) -> float:
	var v = _attr.get(key)
	if v == null:
		v = attr_float(dt, key, default)
		_attr[key] = v
	return v


static func attr_color(dim_type: Dictionary, key: String, default: Color) -> Color:
	var a = dim_type.get("attributes", {})
	if a is Dictionary and a.get(key) is String:
		var v = Timeline._parse(a[key])
		if v is Color:
			return v
	return default


static func attr_float(dim_type: Dictionary, key: String, default: float) -> float:
	var a = dim_type.get("attributes", {})
	if a is Dictionary and (a.get(key) is float or a.get(key) is int):
		return float(a[key])
	return default


func _tl(base, track: String, ticks: float) -> Variant:
	var v = base
	for t in timelines:
		v = (t as Timeline).modify(v, track, ticks)
	return v


## Java CubicSampler.gaussianSampleVec3 of the biome sky / fog colours around `pos` (block coordinates).
func _biome_blend(world, pos: Vector3) -> Array:
	if world.cm != null and Native.ok and Native.inst != null and Native.inst.has_method("sky_blend"):
		# native (it cost up to ~0.9 ms in GDScript when the camera crossed a quart boundary)
		var ccx := int(floor(pos.x / 16.0))
		var ccz := int(floor(pos.z / 16.0))
		var b9: Array = []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var ch: Chunk = world.cm.get_chunk(ccx + dx, ccz + dz)
				b9.append(ch.biomes if ch != null and ch.state >= Chunk.DATA_READY else null)
		var dfog0 := _ac(world.dim_type, "minecraft:visual/fog_color", Color8(0xc0, 0xd8, 0xff))
		var r: PackedColorArray = Native.inst.sky_blend(b9, ccx, ccz, pos.x, pos.y, pos.z, world.biomes.sky, world.biomes.fog,
			PackedColorArray([Color8(0x78, 0xa7, 0xff), dfog0]))[0]
		return [r[0], r[1]]
	var q := (pos - Vector3(2, 2, 2)) * 0.25
	var base := Vector3i(int(floor(q.x)), int(floor(q.y)), int(floor(q.z)))
	if base != _bio_key:
		_bio_key = base
		_bio_sky = []
		_bio_fog = []
		var dfog := attr_color(world.dim_type, "minecraft:visual/fog_color", Color8(0xc0, 0xd8, 0xff))
		for l in 6:
			for n in 6:
				for s in 6:
					var bx := (base.x - 2 + l) * 4
					var by := (base.y - 2 + n) * 4
					var bz := (base.z - 2 + s) * 4
					var c: Chunk = world.cm.get_chunk(bx >> 4, bz >> 4) if world.cm != null else null
					var bio := -1
					if c != null and c.state >= Chunk.DATA_READY:
						bio = c.biome_at(bx & 15, clampi(by, Coords.MIN_Y, Coords.MAX_Y - 1), bz & 15)
					var sk: Color = world.biomes.sky[bio] if bio >= 0 and bio < world.biomes.sky.size() else Color8(0x78, 0xa7, 0xff)
					var fg: Color = world.biomes.fog[bio] if bio >= 0 and bio < world.biomes.fog.size() else dfog
					_bio_sky.append(sk)
					_bio_fog.append(fg)
	var d := q - Vector3(base)
	var sum := 0.0
	var sky := Color(0, 0, 0)
	var fog := Color(0, 0, 0)
	var i := 0
	for l in 6:
		var h := lerpf(GAUSS[l + 1], GAUSS[l], d.x)
		for n in 6:
			var o := lerpf(GAUSS[n + 1], GAUSS[n], d.y)
			for s in 6:
				var w := h * o * lerpf(GAUSS[s + 1], GAUSS[s], d.z)
				sum += w
				sky += _bio_sky[i] * w
				fog += _bio_fog[i] * w
				i += 1
	if sum <= 0.0:
		return [_bio_sky[0], _bio_fog[0]]
	return [sky / sum, fog / sum]


## Timeline / biome / weather part (depends on the game tick, camera block and weather only): sky colour, fog base,
## light colours, celestial angles. update() reruns it when one of those changes (20 x / s instead of every frame).
func _update_slow(world, cam_pos: Vector3, ticks: float, rain: float, thunder: float) -> void:
	var dt: Dictionary = world.dim_type
	var bl := _biome_blend(world, cam_pos)
	var sky: Color = _tl(bl[0], "minecraft:visual/sky_color", ticks)
	var fog: Color = _tl(bl[1], "minecraft:visual/fog_color", ticks)
	sky_light_color = _tl(_ac(dt, "minecraft:visual/sky_light_color", Color(1, 1, 1)), "minecraft:visual/sky_light_color", ticks)
	var slf: float = _tl(_af(dt, "minecraft:visual/sky_light_factor", 1.0), "minecraft:visual/sky_light_factor", ticks)
	ambient_color = _ac(dt, "minecraft:visual/ambient_light_color", Color(0, 0, 0))
	cloud_color = _tl(_ac(dt, "minecraft:visual/cloud_color", Color(1, 1, 1, 0.8)), "minecraft:visual/cloud_color", ticks)
	star_brightness = maxf(0.0, float(_tl(0.0, "minecraft:visual/star_brightness", ticks))) * (1.0 - rain)
	var sr = _tl(Color(0, 0, 0, 0), "minecraft:visual/sunrise_sunset_color", ticks)
	sunrise = sr if sr is Color else Color(0, 0, 0, 0)
	sun_angle = deg_to_rad(float(_tl(0.0, "minecraft:visual/sun_angle", ticks)))
	moon_angle = deg_to_rad(float(_tl(180.0, "minecraft:visual/moon_angle", ticks)))
	star_angle = deg_to_rad(float(_tl(0.0, "minecraft:visual/star_angle", ticks)))
	var mp = _tl("full_moon", "minecraft:visual/moon_phase", ticks + float(world.game_time / 24000) * 24000.0)
	moon_phase = str(mp)
	# weather (ClientLevel.getSkyColor): grey towards luminance
	if rain > 0.0:
		var lum := (sky.r * 0.3 + sky.g * 0.59 + sky.b * 0.11) * 0.6
		var m := 1.0 - rain * 0.75
		sky = Color(sky.r * m + lum * (1.0 - m), sky.g * m + lum * (1.0 - m), sky.b * m + lum * (1.0 - m))
	if thunder > 0.0:
		var lum2 := (sky.r * 0.3 + sky.g * 0.59 + sky.b * 0.11) * 0.2
		var m2 := 1.0 - thunder * 0.75
		sky = Color(sky.r * m2 + lum2 * (1.0 - m2), sky.g * m2 + lum2 * (1.0 - m2), sky.b * m2 + lum2 * (1.0 - m2))
	# ClientLevel.getCloudColor: towards 0.6 x grey with rain, 0.2 x grey with thunder (95 %)
	if rain > 0.0:
		var cg := (cloud_color.r * 0.3 + cloud_color.g * 0.59 + cloud_color.b * 0.11) * 0.6
		var k := rain * 0.95
		cloud_color = Color(lerpf(cloud_color.r, cg, k), lerpf(cloud_color.g, cg, k), lerpf(cloud_color.b, cg, k), cloud_color.a)
	if thunder > 0.0:
		var cg2 := (cloud_color.r * 0.3 + cloud_color.g * 0.59 + cloud_color.b * 0.11) * 0.2
		var k2 := thunder * 0.95
		cloud_color = Color(lerpf(cloud_color.r, cg2, k2), lerpf(cloud_color.g, cg2, k2), lerpf(cloud_color.b, cg2, k2), cloud_color.a)
	# sky light factor: the timeline value is the clear-weather daylight; rain / thunder darken the daylight part
	if rain > 0.0 or thunder > 0.0:
		var g := clampf(((slf - 0.05) / 0.95 - 0.2) / 0.8, 0.0, 1.0)
		g *= (1.0 - rain * 5.0 / 16.0) * (1.0 - thunder * 5.0 / 16.0)
		slf = (g * 0.8 + 0.2) * 0.95 + 0.05
	sky_light_factor = slf
	_sky_c = sky
	_fog_c = fog


var _ukey := Vector4i(-2147483648, 0, 0, 0)
var _wkey := Vector2i(-1, -1)
var _sky_c := Color(0, 0, 0)
var _fog_c := Color(0, 0, 0)


func update(world, cam_pos: Vector3, look: Vector3, ticks: float, rd_chunks: int, rain: float, thunder: float) -> void:
	var key := Vector4i(int(ticks), int(floor(cam_pos.x)), int(floor(cam_pos.y)), int(floor(cam_pos.z)))
	var wkey := Vector2i(int(rain * 512.0), int(thunder * 512.0))
	if key != _ukey or wkey != _wkey:
		_ukey = key
		_wkey = wkey
		_update_slow(world, cam_pos, ticks, rain, thunder)
	var sky: Color = _sky_c
	var fog: Color = _fog_c
	# FogRenderer colour: sunrise tint looking towards the sun, blend towards the sky colour, weather, void
	if rd_chunks >= 4 and sunrise.a > 0.0:
		var sx := -1.0 if sin(sun_angle) > 0.0 else 1.0
		var nd := maxf(0.0, look.x * sx) * sunrise.a
		if nd > 0.0:
			fog = Color(lerpf(fog.r, sunrise.r, nd), lerpf(fog.g, sunrise.g, nd), lerpf(fog.b, sunrise.b, nd))
	var gk := 1.0 - pow(0.25 + 0.75 * float(rd_chunks) / 32.0, 0.25)
	fog = Color(fog.r + (sky.r - fog.r) * gk, fog.g + (sky.g - fog.g) * gk, fog.b + (sky.b - fog.b) * gk)
	if rain > 0.0:
		var o := 1.0 - rain * 0.5
		var p := 1.0 - rain * 0.4
		fog = Color(fog.r * o, fog.g * o, fog.b * p)
	if thunder > 0.0:
		var t2 := 1.0 - thunder * 0.5
		fog = Color(fog.r * t2, fog.g * t2, fog.b * t2)
	var u := cam_pos.y - float(world.dim_type.get("min_y", -64.0))
	if u < 1.0:
		u = maxf(u, 0.0)
		fog = Color(fog.r * u * u, fog.g * u * u, fog.b * u * u)
	sky_color = sky
	fog_color = Color(clampf(fog.r, 0.0, 1.0), clampf(fog.g, 0.0, 1.0), clampf(fog.b, 0.0, 1.0))
