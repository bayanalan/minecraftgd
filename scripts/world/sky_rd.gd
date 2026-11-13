class_name SkyRD
extends RefCounted
## Java 26.3 sky and clouds drawn with RenderingDevice inside the 3D frame (CompositorEffects), replacing Godot's sky
## pass (its own render pass + sky setup, ~0.25 ms GPU at 2880x1800) and adding the cloud layer:
## - Sky (after the opaque terrain): one full-screen triangle at the far plane, depth-tested, so only pixels nothing
##   else covered are shaded. Per pixel it evaluates exactly what Java rasterises (colour math in sRGB like Java's
##   gamma framebuffer): clear colour = fog colour; sky disc (octagonal fan 16 above the camera, radius 512, fogged with
##   the interpolated spherical / cylindrical distances over FogSkyEnd); sunrise / sunset fan; sun and moon quads
##   (additive). Then the stars (1500 quads, additive) and, while the camera is below the horizon height, the dark disc
##   last, as in LevelRenderer. Nether: fog colour; End: end_sky texture box.
## - Clouds (after the translucent terrain): CloudRenderer's cell faces (12 x 4 x 12 blocks per clouds.png pixel; fast:
##   a flat layer), built natively near to far when the camera enters another cell (RecraftNative.cloud_faces), drawn
##   by vertex pulling (clouds.vsh): face shades 0.7 / 1.0 / 0.8 / 0.9, Java's cloud colour (timeline + weather),
##   alpha fading to 0 at the cloud distance (clouds.fsh), depth tested and written so only the nearest surface shows.

const UBO_BYTES := 320
const CELL := 12.0
const CLOUD_HEIGHT_BLOCKS := 4.0

var rd: RenderingDevice
var world
var ubo: RID
var sh_sky: RID
var sh_stars: RID
var sh_clouds: RID
var pipes: Dictionary = {}
var samp_nearest: RID
var samp_repeat: RID
var white_tex: RID
var stars_buf: RID
var stars_verts := 0
var cloud_buf: RID
var cloud_cap := 0
var cloud_faces := 0
var cloud_cells := PackedByteArray()
var cloud_w := 0
var cloud_h := 0
var _cloud_key: Array = []
# cloud face lists are built on a worker (a rebuild every 12 blocks of camera movement cost ~1 ms on the main thread);
# the uploaded list stays in use, positioned relative to the cell it was built for, until the new one arrives
var _built_cell := Vector2i.ZERO
var _cloud_pending := false
var _cloud_result: Array = []
var _cloud_mutex := Mutex.new()
var _uset_sky: RID
var _uset_sky_tex: Array = []
var _uset_stars: RID
var _uset_clouds: RID
var _samples := RenderingDevice.TEXTURE_SAMPLES_1
var sun_tex: Texture2D
var moon_tex: Texture2D
var end_tex: Texture2D
# per frame (update)
var star_brightness := 0.0
var dark_disc := false
var clouds_mode := 2   # 0 off, 1 fast, 2 fancy
var sky_mode := 0      # 0 overworld, 1 fog colour only (Nether), 2 End
var debug := 0         # --skydbg: 1 skip the sky, 2 flat colour sky shader (cost experiments)


func _init(p_world) -> void:
	world = p_world
	rd = RenderingServer.get_rendering_device()
	if p_world != null:
		debug = int(p_world.autoplay.get("skydbg", "0"))
	ubo = rd.uniform_buffer_create(UBO_BYTES)
	var ss := RDSamplerState.new()
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	samp_nearest = rd.sampler_create(ss)
	var sr := RDSamplerState.new()
	sr.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sr.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sr.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sr.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	samp_repeat = rd.sampler_create(sr)
	var tf := RDTextureFormat.new()
	tf.width = 1
	tf.height = 1
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	white_tex = rd.texture_create(tf, RDTextureView.new(), [PackedByteArray([255, 255, 255, 255])])
	# stars: 6 vertices per quad (vec4 each)
	var q := SkyStars.star_quads()
	var sv := PackedFloat32Array()
	for b0 in range(0, q.size(), 4):
		for k in [0, 1, 2, 0, 2, 3]:
			var v: Vector3 = q[b0 + k]
			sv.append_array([v.x, v.y, v.z, 1.0])
	stars_verts = sv.size() / 4
	stars_buf = rd.storage_buffer_create(sv.size() * 4, sv.to_byte_array())
	_load_clouds()
	sh_sky = _compile(SKY_VS, SKY_FS.replace("void main() {", "void main() {\n\tfrag = vec4(0.5, 0.6, 0.9, 1.0); return;") if debug == 2 else SKY_FS)
	sh_stars = _compile(STARS_VS, STARS_FS)
	sh_clouds = _compile(CLOUDS_VS.replace("	v_col = (topc", "	gl_Position = vec4(2.0, 2.0, 2.0, 1.0);   // experiment\n	v_col = (topc") if debug == 8 else CLOUDS_VS, CLOUDS_FS)


## clouds.png from the user's assets: bit0 cloud (alpha >= 10, Java isCellEmpty), bits 1..4 north / east / south /
## west neighbour empty (wrapping).
func _load_clouds() -> void:
	var img: Image = Res.load_image("environment/clouds") if Res.mode == "vanilla" else null
	if img == null:
		return
	img.convert(Image.FORMAT_RGBA8)
	cloud_w = img.get_width()
	cloud_h = img.get_height()
	var data := img.get_data()
	var solid := PackedByteArray()
	solid.resize(cloud_w * cloud_h)
	for i in cloud_w * cloud_h:
		solid[i] = 1 if data[i * 4 + 3] >= 10 else 0
	cloud_cells.resize(cloud_w * cloud_h)
	for z in cloud_h:
		for x in cloud_w:
			var i := x + z * cloud_w
			if solid[i] == 0:
				cloud_cells[i] = 0
				continue
			var c := 1
			if solid[x + ((z - 1 + cloud_h) % cloud_h) * cloud_w] == 0:
				c |= 2
			if solid[(x + 1) % cloud_w + z * cloud_w] == 0:
				c |= 4
			if solid[x + ((z + 1) % cloud_h) * cloud_w] == 0:
				c |= 8
			if solid[(x - 1 + cloud_w) % cloud_w + z * cloud_w] == 0:
				c |= 16
			cloud_cells[i] = c


func destroy() -> void:
	for p in pipes.values():
		rd.free_rid(p)
	pipes.clear()
	for us in [_uset_sky, _uset_stars, _uset_clouds]:
		if (us as RID).is_valid() and rd.uniform_set_is_valid(us):
			rd.free_rid(us)
	for r in [sh_sky, sh_stars, sh_clouds, stars_buf, cloud_buf, ubo, samp_nearest, samp_repeat, white_tex]:
		if (r as RID).is_valid():
			rd.free_rid(r)


## Attachable effects: sky after the opaque pass, clouds after the sky (after TerrainRD's translucent pass when listed
## after it).
func sky_effect() -> CompositorEffect:
	return Effect.new(self, 0, CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE)


func clouds_effect() -> CompositorEffect:
	return Effect.new(self, 1, CompositorEffect.EFFECT_CALLBACK_TYPE_POST_SKY)


# ---------------------------------------------------------------- per frame (main thread, WorldManager._update_sky)

## Writes the frame's sky / cloud parameters. Colours sRGB.
func update(cam: Camera3D, origin: Vector3i, mode: int, sky_color: Color, fog_color: Color, sky_end: float,
		sunrise: Color, sunrise_side: float, sun_angle: float, moon_angle: float, celestial_alpha: float,
		p_dark_disc: bool, stars: float, star_angle: float, cloud_color: Color, cloud_height: float, ticks: float,
		p_clouds: int, cloud_range_chunks: int, cloud_end: float) -> void:
	sky_mode = mode
	dark_disc = p_dark_disc and mode == 0
	star_brightness = stars if mode == 0 else 0.0
	clouds_mode = p_clouds if mode == 0 and cloud_w > 0 and Native.inst != null and Native.inst.has_method("cloud_faces") else 0
	var b := PackedByteArray()
	b.resize(UBO_BYTES)
	_v4(b, 0, sky_color.r, sky_color.g, sky_color.b, float(mode))
	_v4(b, 16, fog_color.r, fog_color.g, fog_color.b, sky_end)
	_v4(b, 32, sunrise.r, sunrise.g, sunrise.b, sunrise.a)
	_v4(b, 48, sunrise_side, sun_angle, moon_angle, celestial_alpha)
	_v4(b, 64, 1.0 if dark_disc else 0.0, 1.0 if sun_tex != null else 0.0, 1.0 if end_tex != null else 0.0, star_brightness)
	var bs := cam.global_transform.basis
	var vp := cam.get_viewport().get_visible_rect().size
	var ty := tan(deg_to_rad(cam.fov) * 0.5)
	var tx := ty * (vp.x / maxf(vp.y, 1.0))
	_v4(b, 80, bs.x.x, bs.x.y, bs.x.z, tx)
	_v4(b, 96, bs.y.x, bs.y.y, bs.y.z, ty)
	_v4(b, 112, -bs.z.x, -bs.z.y, -bs.z.z, 0.0)
	_v4(b, 128, vp.x, vp.y, 0.0, 0.0)
	var vpr := Projection.create_depth_correction(true) * cam.get_camera_projection() * Projection(Transform3D(bs, Vector3.ZERO).affine_inverse())
	_m4(b, 144, vpr)
	var star_m := Basis(Vector3.UP, deg_to_rad(-90.0)) * Basis(Vector3.RIGHT, star_angle)
	_m4(b, 208, vpr * Projection(Transform3D(star_m, Vector3.ZERO)))
	_v4(b, 272, cloud_color.r, cloud_color.g, cloud_color.b, cloud_color.a)
	if clouds_mode > 0:
		# Java CloudRenderer.render: drift 0.03 blocks per tick along x, z offset 3.96, cells of 12 blocks
		var cw := cam.global_position + Vector3(origin)
		var d := float(cw.x) + ticks * 0.03
		var e := float(cw.z) + 3.96
		var ww := float(cloud_w) * CELL
		var hh := float(cloud_h) * CELL
		d -= floorf(d / ww) * ww
		e -= floorf(e / hh) * hh
		var ccx := int(floor(d / CELL))
		var ccz := int(floor(e / CELL))
		var m := d - float(ccx) * CELL
		var n := e - float(ccz) * CELL
		var rel_y := cloud_height - float(cw.y)
		var rel := 0 if rel_y + CLOUD_HEIGHT_BLOCKS < 0.0 else (1 if rel_y > 0.0 else 2)
		var radius := int(ceil(float(cloud_range_chunks) * 16.0 / CELL))
		_take_cloud_result()
		# offset of the uploaded list's cell (_built_cell) from the camera cell, wrapped around the texture
		var dcx := posmod(ccx - _built_cell.x + cloud_w / 2, cloud_w) - cloud_w / 2
		var dcz := posmod(ccz - _built_cell.y + cloud_h / 2, cloud_h) - cloud_h / 2
		_v4(b, 288, -(float(dcx) * CELL + m), rel_y, -(float(dcz) * CELL + n), CLOUD_HEIGHT_BLOCKS if clouds_mode == 2 else 0.0)
		_v4(b, 304, cloud_end, 0.0, 0.0, 0.0)
		var key := [ccx, ccz, rel, clouds_mode, radius]
		if key != _cloud_key and not _cloud_pending:
			_cloud_key = key
			_cloud_pending = true
			WorkerThreadPool.add_task(_build_clouds.bind(ccx, ccz, rel, clouds_mode == 2, radius))
	rd.buffer_update(ubo, 0, UBO_BYTES, b)


## Worker: the face list (pure native function over the immutable cell array).
func _build_clouds(ccx: int, ccz: int, rel: int, fancy: bool, radius: int) -> void:
	var r: Array = Native.inst.cloud_faces(cloud_cells, cloud_w, cloud_h, ccx, ccz, rel, 1 if fancy else 0, radius)
	_cloud_mutex.lock()
	_cloud_result = [r[0], int(r[1]), Vector2i(ccx, ccz)]
	_cloud_mutex.unlock()


## Main thread: upload a finished face list.
func _take_cloud_result() -> void:
	if not _cloud_pending:
		return
	_cloud_mutex.lock()
	var res := _cloud_result
	_cloud_result = []
	_cloud_mutex.unlock()
	if res.is_empty():
		return
	_cloud_pending = false
	var data: PackedByteArray = res[0]
	_built_cell = res[2]
	cloud_faces = int(res[1])
	if cloud_faces == 0:
		return
	if data.size() > cloud_cap:
		if cloud_buf.is_valid():
			if _uset_clouds.is_valid() and rd.uniform_set_is_valid(_uset_clouds):
				rd.free_rid(_uset_clouds)
			_uset_clouds = RID()
			rd.free_rid(cloud_buf)
		cloud_cap = int(data.size() * 1.5) + 4096
		cloud_buf = rd.storage_buffer_create(cloud_cap)
	rd.buffer_update(cloud_buf, 0, data.size(), data)


static func _v4(b: PackedByteArray, off: int, x: float, y: float, z: float, w: float) -> void:
	b.encode_float(off, x)
	b.encode_float(off + 4, y)
	b.encode_float(off + 8, z)
	b.encode_float(off + 12, w)


static func _m4(b: PackedByteArray, off: int, p: Projection) -> void:
	for c in 4:
		var col: Vector4 = p[c]
		_v4(b, off + c * 16, col.x, col.y, col.z, col.w)


# ---------------------------------------------------------------- rendering (effect callbacks)

func render(render_data: RenderData, which: int) -> void:
	var rsb: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	if rsb == null:
		return
	if which == 1 and (clouds_mode == 0 or cloud_faces == 0 or not cloud_buf.is_valid()):
		return
	var msaa := rsb.get_msaa_3d()
	var ms := msaa != RenderingServer.VIEWPORT_MSAA_DISABLED
	var fb := FramebufferCacheRD.get_cache_multipass([rsb.get_color_layer(0, ms), rsb.get_depth_layer(0, ms)], [], 1)
	var fmt := rd.framebuffer_get_format(fb)
	_samples = [RenderingDevice.TEXTURE_SAMPLES_1, RenderingDevice.TEXTURE_SAMPLES_2, RenderingDevice.TEXTURE_SAMPLES_4, RenderingDevice.TEXTURE_SAMPLES_8][clampi(msaa, 0, 3)]
	var isz := rsb.get_internal_size()   # 3D buffer size (render scale)
	var dl := rd.draw_list_begin(fb, RenderingDevice.DRAW_DEFAULT_ALL)
	if which == 0:
		draw_sky(dl, fmt, _samples, isz)
	else:
		draw_clouds(dl, fmt, _samples)
	rd.draw_list_end()


## Sky into an open draw list (TerrainRD draws it after the opaque terrain in the same render pass: a separate
## pass would load and store the full colour + depth buffers again).
func draw_sky(dl: int, fmt: int, samples: int, isz: Vector2i) -> void:
	_samples = samples
	if debug == 1:
		return
	var pc := PackedFloat32Array([0.0, float(isz.x), float(isz.y), 0.0]).to_byte_array()
	rd.draw_list_bind_render_pipeline(dl, _pipe(fmt, 0))
	rd.draw_list_bind_uniform_set(dl, _sky_uset(), 0)
	rd.draw_list_set_push_constant(dl, pc, pc.size())
	rd.draw_list_draw(dl, false, 1, 3)
	if star_brightness > 0.0:
		rd.draw_list_bind_render_pipeline(dl, _pipe(fmt, 1))
		rd.draw_list_bind_uniform_set(dl, _stars_uset(), 0)
		rd.draw_list_draw(dl, false, 1, stars_verts)
	if dark_disc:
		var pc2 := PackedFloat32Array([1.0, float(isz.x), float(isz.y), 0.0]).to_byte_array()
		rd.draw_list_bind_render_pipeline(dl, _pipe(fmt, 0))
		rd.draw_list_bind_uniform_set(dl, _sky_uset(), 0)
		rd.draw_list_set_push_constant(dl, pc2, pc2.size())
		rd.draw_list_draw(dl, false, 1, 3)


func has_clouds() -> bool:
	return clouds_mode != 0 and cloud_faces > 0 and cloud_buf.is_valid()


## Clouds into an open draw list (after TerrainRD's translucent terrain, same render pass).
func draw_clouds(dl: int, fmt: int, samples: int) -> void:
	if not has_clouds():
		return
	_samples = samples
	rd.draw_list_bind_render_pipeline(dl, _pipe(fmt, 2 if clouds_mode == 2 else 3))
	rd.draw_list_bind_uniform_set(dl, _clouds_uset(), 0)
	rd.draw_list_draw(dl, false, 1, cloud_faces * 6)


func _tex_rid(t: Texture2D) -> RID:
	if t == null:
		return white_tex
	var r := RenderingServer.texture_get_rd_texture(t.get_rid())
	return r if r.is_valid() else white_tex


func _sky_uset() -> RID:
	var texs := [_tex_rid(sun_tex), _tex_rid(moon_tex), _tex_rid(end_tex)]
	if _uset_sky.is_valid() and rd.uniform_set_is_valid(_uset_sky) and texs == _uset_sky_tex:
		return _uset_sky
	if _uset_sky.is_valid() and rd.uniform_set_is_valid(_uset_sky):
		rd.free_rid(_uset_sky)
	_uset_sky_tex = texs
	_uset_sky = rd.uniform_set_create([_u_ubo(0), _u_tex(1, samp_nearest, texs[0]), _u_tex(2, samp_nearest, texs[1]), _u_tex(3, samp_repeat, texs[2])], sh_sky, 0)
	return _uset_sky


func _stars_uset() -> RID:
	if not (_uset_stars.is_valid() and rd.uniform_set_is_valid(_uset_stars)):
		_uset_stars = rd.uniform_set_create([_u_ubo(0), _u_buf(4, stars_buf)], sh_stars, 0)
	return _uset_stars


func _clouds_uset() -> RID:
	if not (_uset_clouds.is_valid() and rd.uniform_set_is_valid(_uset_clouds)):
		_uset_clouds = rd.uniform_set_create([_u_ubo(0), _u_buf(5, cloud_buf)], sh_clouds, 0)
	return _uset_clouds


func _u_ubo(b: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u.binding = b
	u.add_id(ubo)
	return u


func _u_buf(b: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = b
	u.add_id(rid)
	return u


func _u_tex(b: int, s: RID, t: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = b
	u.add_id(s)
	u.add_id(t)
	return u


func _compile(vs: String, fs: String) -> RID:
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_vertex = vs
	src.source_fragment = fs.replace("//COMMON", COMMON)
	src.source_vertex = vs.replace("//COMMON", COMMON)
	var spirv := rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_vertex != "" or spirv.compile_error_fragment != "":
		push_error("SkyRD shader: %s %s" % [spirv.compile_error_vertex, spirv.compile_error_fragment])
		return RID()
	return rd.shader_create_from_spirv(spirv)


## 0 sky (full screen, far plane), 1 stars (additive), 2 fancy clouds (culled), 3 fast clouds (both sides).
func _pipe(fmt: int, kind: int) -> RID:
	var k := fmt * 8 + kind
	if pipes.has(k):
		return pipes[k]
	var rs := RDPipelineRasterizationState.new()
	rs.cull_mode = RenderingDevice.POLYGON_CULL_BACK if kind == 2 else RenderingDevice.POLYGON_CULL_DISABLED
	# Java's cloud faces are CCW seen from outside; measured: through Godot's depth-corrected projection they are
	# front faces as COUNTER_CLOCKWISE (CLOCKWISE culled the outer faces and showed only the inside faces)
	rs.front_face = RenderingDevice.POLYGON_FRONT_FACE_COUNTER_CLOCKWISE
	var ms := RDPipelineMultisampleState.new()
	ms.sample_count = _samples
	var ds := RDPipelineDepthStencilState.new()
	ds.enable_depth_test = true
	ds.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER_OR_EQUAL   # reverse Z: depth 0 passes only on cleared pixels
	ds.enable_depth_write = kind >= 2
	var bs := RDPipelineColorBlendState.new()
	var att := RDPipelineColorBlendStateAttachment.new()
	if kind >= 2 and debug == 4:   # experiment (--skydbg=4): clouds without colour writes (vertex / depth cost only)
		att.write_r = false
		att.write_g = false
		att.write_b = false
		att.write_a = false
	if kind == 1:
		att.enable_blend = true
		att.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		att.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		att.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ZERO
		att.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	elif kind >= 2:
		att.set_as_mix()
	bs.attachments = [att]
	var sh: RID = [sh_sky, sh_stars, sh_clouds, sh_clouds][kind]
	var p := rd.render_pipeline_create(sh, fmt, -1, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, rs, ms, ds, bs)
	pipes[k] = p
	return p


class Effect:
	extends CompositorEffect
	var sky: SkyRD
	var which: int

	func _init(p_sky: SkyRD, p_which: int, p_type: int) -> void:
		sky = p_sky
		which = p_which
		effect_callback_type = p_type
		needs_motion_vectors = false

	func _render_callback(_type: int, render_data: RenderData) -> void:
		sky.render(render_data, which)


const COMMON := """
layout(set = 0, binding = 0, std140) uniform Sky {
	vec4 sky_color;     // rgb (sRGB), mode
	vec4 fog_color;     // rgb (sRGB), FogSkyEnd
	vec4 sunrise;       // rgba (sRGB)
	vec4 misc;          // sunrise side, sun angle, moon angle, celestial alpha
	vec4 flags;         // dark disc, has sun/moon textures, has end texture, star brightness
	vec4 cam_right;     // xyz, tan(half horizontal fov)
	vec4 cam_up;        // xyz, tan(half vertical fov)
	vec4 cam_fwd;
	vec4 viewport;
	mat4 vp_rot;        // view (rotation only) projection, depth corrected
	mat4 star_mvp;
	vec4 cloud_color;   // rgba (sRGB)
	vec4 cloud_offset;  // camera-relative offset of cell (0, 0), cell height
	vec4 cloud_misc;    // FogCloudsEnd
} u;
float lin_fog(float d, float s, float e) {
	if (d <= s) return 0.0;
	if (d >= e) return 1.0;
	return (d - s) / (e - s);
}
vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}
"""

const SKY_VS := """
#version 450
void main() {
	vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
	gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
"""

const SKY_FS := """
#version 450
//COMMON
layout(set = 0, binding = 1) uniform sampler2D sun_tex;
layout(set = 0, binding = 2) uniform sampler2D moon_tex;
layout(set = 0, binding = 3) uniform sampler2D end_tex;
layout(push_constant, std430) uniform PC { vec4 pass; } pc;   // x: pass (0 sky, 1 dark disc), yz: 3D buffer size
layout(location = 0) out vec4 frag;

// one disc: hit of the plane at plane_y (geometry radius 512, fog distances of the untranslated +-16 geometry)
vec4 sky_disc(vec3 d, float plane_y, vec3 col) {
	float t = plane_y / d.y;
	if (t <= 0.0) return vec4(0.0);
	vec2 p = d.xz * t;
	float r = length(p);
	const float SEG = 0.785398163;
	float phi = atan(p.y, p.x);
	float k = floor((phi + 3.14159265) / SEG);
	float mid = (k + 0.5) * SEG - 3.14159265;
	float rc = 512.0 * cos(SEG * 0.5) / cos(phi - mid);
	if (r > rc) return vec4(0.0);
	float uu = r / rc;
	float sph = mix(16.0, 512.249939, uu);
	float cyl = mix(16.0, 512.0, uu);
	float sky_end = u.fog_color.w;
	float f = max(lin_fog(sph, 0.0, sky_end), lin_fog(cyl, sky_end, sky_end));
	return vec4(mix(col, u.fog_color.rgb, f), 1.0);
}

vec3 ray_tri(vec3 d, vec3 a, vec3 b, vec3 c) {
	vec3 e1 = b - a;
	vec3 e2 = c - a;
	vec3 pv = cross(d, e2);
	float det = dot(e1, pv);
	if (abs(det) < 1e-6) return vec3(-1.0);
	float inv = 1.0 / det;
	vec3 tv = -a;
	float uu = dot(tv, pv) * inv;
	if (uu < 0.0 || uu > 1.0) return vec3(-1.0);
	vec3 qv = cross(tv, e1);
	float v = dot(d, qv) * inv;
	if (v < 0.0 || uu + v > 1.0) return vec3(-1.0);
	float t = dot(e2, qv) * inv;
	return vec3(t, uu, v);
}

vec3 sunrise_fan(vec3 d, vec3 col) {
	float a = u.sunrise.a;
	float s = u.misc.x;
	vec3 apex = vec3(-100.0 * s, 0.0, 0.0);
	for (int k = 0; k < 16; k++) {
		float g0 = float(k) * 6.28318531 / 16.0;
		float g1 = float(k + 1) * 6.28318531 / 16.0;
		vec3 r0 = vec3(-120.0 * s * cos(g0), 40.0 * a * cos(g0), 120.0 * s * sin(g0));
		vec3 r1 = vec3(-120.0 * s * cos(g1), 40.0 * a * cos(g1), 120.0 * s * sin(g1));
		vec3 h = ray_tri(d, apex, r0, r1);
		if (h.x > 0.0) {
			float w_apex = 1.0 - h.y - h.z;
			col = mix(col, u.sunrise.rgb, a * w_apex);
		}
	}
	return col;
}

vec4 celestial_sun(vec3 d, float ang, float hs) {
	vec3 dirv = vec3(-sin(ang), cos(ang), 0.0);
	float dd = dot(d, dirv);
	if (dd <= 0.0) return vec4(0.0);
	vec3 p = d * (100.0 / dd);
	float lx = dot(p, vec3(0.0, 0.0, 1.0)) / hs;
	float lz = dot(p, vec3(-cos(ang), -sin(ang), 0.0)) / hs;
	if (abs(lx) > 1.0 || abs(lz) > 1.0) return vec4(0.0);
	if (u.flags.y < 0.5) return vec4(1.0, 1.0, 0.9, 1.0);
	return texture(sun_tex, vec2(lx, lz) * 0.5 + 0.5);
}

vec4 celestial_moon(vec3 d, float ang, float hs) {
	vec3 dirv = vec3(-sin(ang), cos(ang), 0.0);
	float dd = dot(d, dirv);
	if (dd <= 0.0) return vec4(0.0);
	vec3 p = d * (100.0 / dd);
	float lx = dot(p, vec3(0.0, 0.0, 1.0)) / hs;
	float lz = dot(p, vec3(-cos(ang), -sin(ang), 0.0)) / hs;
	if (abs(lx) > 1.0 || abs(lz) > 1.0) return vec4(0.0);
	if (u.flags.y < 0.5) return vec4(1.0, 1.0, 0.9, 1.0);
	return texture(moon_tex, vec2(1.0) - (vec2(lx, lz) * 0.5 + 0.5));
}

vec3 end_sky(vec3 dir) {
	vec3 a = abs(dir);
	vec2 uv;
	if (a.x >= a.y && a.x >= a.z) uv = dir.zy / a.x;
	else if (a.y >= a.z) uv = dir.xz / a.y;
	else uv = dir.xy / a.z;
	vec3 t = u.flags.z > 0.5 ? texture(end_tex, uv * 8.0).rgb : vec3(0.5, 0.45, 0.55);
	return t * (40.0 / 255.0);
}

void main() {
	vec2 uv = gl_FragCoord.xy / pc.pass.yz;
	vec2 ndc = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
	vec3 d = normalize(u.cam_fwd.xyz + u.cam_right.xyz * (ndc.x * u.cam_right.w) + u.cam_up.xyz * (ndc.y * u.cam_up.w));
	int mode = int(u.sky_color.w + 0.5);
	if (pc.pass.x > 0.5) {
		// dark disc (camera below the horizon height), drawn last like LevelRenderer
		if (d.y >= 0.0) discard;
		vec4 bot = sky_disc(d, -4.0, vec3(0.0));
		if (bot.a <= 0.0) discard;
		frag = vec4(to_linear(clamp(bot.rgb, 0.0, 1.0)), 1.0);
		return;
	}
	vec3 col = u.fog_color.rgb;
	if (mode == 2) {
		col = end_sky(d);
	} else if (mode == 0) {
		if (d.y > 0.0) {
			vec4 top = sky_disc(d, 16.0, u.sky_color.rgb);
			if (top.a > 0.0) col = top.rgb;
		}
		if (u.sunrise.a > 0.0) col = sunrise_fan(d, col);
		if (u.misc.w > 0.0) {
			vec4 sun = celestial_sun(d, u.misc.y, 30.0);
			col += sun.rgb * sun.a * u.misc.w;
			vec4 moon = celestial_moon(d, u.misc.z, 20.0);
			col += moon.rgb * moon.a * u.misc.w;
		}
	}
	frag = vec4(to_linear(clamp(col, 0.0, 1.0)), 1.0);
}
"""

const STARS_VS := """
#version 450
//COMMON
layout(set = 0, binding = 4, std430) restrict readonly buffer Stars { vec4 sv[]; };
void main() {
	gl_Position = u.star_mvp * vec4(sv[gl_VertexIndex].xyz, 1.0);
	gl_Position.z = 0.0;
}
"""

const STARS_FS := """
#version 450
//COMMON
layout(location = 0) out vec4 frag;
void main() {
	// Java stars: colour (b, b, b, b), blended SRC_ALPHA / ONE in sRGB -> adds b * b
	float b = u.flags.w * u.flags.w;
	frag = vec4(to_linear(vec3(b)), 1.0);
}
"""

const CLOUDS_VS := """
#version 450
//COMMON
layout(set = 0, binding = 5, std430) restrict readonly buffer Faces { uvec2 fc[]; };
layout(location = 0) out float v_dist;
layout(location = 1) out vec4 v_col;
const int packedX = 0xF03CC3;
const int packedY = 0x6666F0;
const int packedZ = 0xC3F066;
vec3 vtx(int i) {
	return vec3(float((packedX >> i) & 1), float((packedY >> i) & 1), float((packedZ >> i) & 1));
}
const vec4 FACE[6] = vec4[](vec4(0.7, 0.7, 0.7, 1.0), vec4(1.0), vec4(0.8, 0.8, 0.8, 1.0), vec4(0.8, 0.8, 0.8, 1.0),
	vec4(0.9, 0.9, 0.9, 1.0), vec4(0.9, 0.9, 0.9, 1.0));
const int CORNER[6] = int[](0, 1, 2, 2, 3, 0);
void main() {
	int f = gl_VertexIndex / 6;
	int q = CORNER[gl_VertexIndex % 6];
	uvec2 e = fc[f];
	int dx = int(e.x << 16u) >> 16;
	int dz = int(e.x) >> 16;
	int flags = int(e.y);
	int dir = flags & 7;
	bool inside = (flags & 16) != 0;
	bool topc = (flags & 32) != 0;
	vec3 fv = vtx(dir * 4 + (inside ? 3 - q : q));
	vec3 cs = vec3(12.0, u.cloud_offset.w, 12.0);
	vec3 pos = fv * cs + vec3(float(dx), 0.0, float(dz)) * cs + u.cloud_offset.xyz;
	gl_Position = u.vp_rot * vec4(pos, 1.0);
	v_dist = length(pos);
	v_col = (topc ? FACE[1] : FACE[dir]) * u.cloud_color;
}
"""

const CLOUDS_FS := """
#version 450
//COMMON
layout(location = 0) in float v_dist;
layout(location = 1) in vec4 v_col;
layout(location = 0) out vec4 frag;
void main() {
	vec4 c = v_col;
	c.a *= 1.0 - lin_fog(v_dist, 0.0, u.cloud_misc.x);
	frag = vec4(to_linear(clamp(c.rgb, 0.0, 1.0)), c.a);
}
"""
