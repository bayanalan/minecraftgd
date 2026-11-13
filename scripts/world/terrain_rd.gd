class_name TerrainRD
extends RefCounted
## RenderingDevice terrain renderer (Video setting "Terrain Renderer: RenderingDevice"), drawn inside Forward+ through
## CompositorEffects. Replaces one Godot mesh instance per chunk group:
## - Geometry: mesh jobs pack their quads on the worker (RecraftNative.tr_pack: 20-byte vertices, quads sorted into 7
##   face-direction buckets, AO-flipped quads pre-rotated so one index pattern fits all). Uploads go into 64 MB storage
##   buffer pages (first-fit free lists); each vertex carries its group slot (tr_stamp) -> chunk origin buffer.
## - Culling: one native call per frame (tr_cull_all) tests every group against the frustum and drops face-direction
##   buckets that face away from the camera (Sodium-style), writing indexed indirect draw commands over a static quad
##   index buffer. One indirect draw per (material, page): opaque + cutout right after Godot's opaque pass (it clears
##   colour when it starts; depth testing keeps Godot's opaque objects correct), translucent after the sky, far-first.
## - Shading: shaders/voxel_common.gdshaderinc ported + Godot's depth-fog formula; camera matrices from Camera3D with
##   Godot's API depth correction (which already maps to reverse Z).

const VERT_BYTES := 20
const PAGE_QUADS := 800000          # 64 MB per storage buffer page (a shader binding addresses ~128 MB)
const MAX_SLOTS := 32768            # groups per page (15-bit slot in each vertex)
const MAX_CMDS := 131072            # indirect commands per frame
const FRAME_BYTES := 1424           # fog colour, fog params, globals, origin (ivec4) @48, view-projection @64, camera @128,
                                    # lightmap 256 x RGBA8 (uvec4[64]) @144 (WorldManager.lightmap_img), overlay palette
                                    # 64 x uint (uvec4[16]) @1168 (overlay_layers)

var rd: RenderingDevice
var h := -1                          # native culler handle
var pages: Array = []                # per page: position stream (8 bytes / vertex: w0, w1)
var attr_bufs: Array = []            # per page: attribute stream (12 bytes / vertex: w2, w3, w4)
var varrays: Array = []              # per page: vertex array (attribute 0: uvec2 positions, attribute 1: uvec3 attributes)
var planar := false                  # two planar streams (position / attributes); measured neutral on Adreno D3D12 -> off (--trplanar=1)
var vformat := -1
var page_log: PackedStringArray = []   # benchmark: page allocation log (printed after the run, never mid-frame)
var origins: Array = []              # per page: storage buffer of ivec4 group origins (by slot)
var slot_free: Array = []            # per page: Array of free slots
var slot_next: Array = []            # per page: next never-used slot
var allocs: Dictionary = {}          # group key -> [page, start, count, slot]
var index_buf: RID
var index_array: RID
var indirect_buf: RID
var frame_ubo: RID
var sampler: RID
var tex_rid: RID
var lm_sampler: RID
var shaders: Array = [RID(), RID(), RID()]
var pipelines: Dictionary = {}       # fb_format * 4 + mat -> RID
var _usets: Dictionary = {}          # mat * 4096 + page -> uniform set
var _cull_frame := -1
var _samples := RenderingDevice.TEXTURE_SAMPLES_1   # sample count of the current 3D buffers (pipelines are per format)
var _meta := PackedInt32Array()
var _runs := PackedInt32Array()      # translucent draw runs: (page, first command, count) in global far-to-near order
var world                            # WorldManager
var stats := {"cmds": 0, "cull_us": 0, "quads_resident": 0}
var debug_flags := 0                 # experiments: 4 hides groups below y 0, 8 below y 64 (--trhide=4|8)
var sky_rd: SkyRD                    # sky + clouds drawn inside this renderer's passes (WorldManager._install_compositor)
## One render pass for everything (opaque, cutout, sky, translucent, clouds) at POST_OPAQUE instead of two passes
## (POST_OPAQUE + POST_SKY): Godot draws nothing between them (BG_KEEP: no sky pass), so the image is the same and
## the 2880x1800 colour + depth buffers are loaded / stored once less per frame. --trmerge=0 restores two passes.
var merged := true


func _init(p_world) -> void:
	world = p_world
	rd = RenderingServer.get_rendering_device()
	h = int(Native.inst.tr_new()[0])
	frame_ubo = rd.uniform_buffer_create(FRAME_BYTES)
	indirect_buf = rd.storage_buffer_create(MAX_CMDS * 20, PackedByteArray(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	if p_world != null and p_world.autoplay.has("trhide"):
		debug_flags = int(p_world.autoplay["trhide"])
	if debug_flags & 1024:   # legacy: one 32-bit index buffer over a whole page (first_index = quad * 6)
		var idx: PackedByteArray = Native.inst.tr_quad_indices(PAGE_QUADS, 32)[0]
		index_buf = rd.index_buffer_create(PAGE_QUADS * 6, RenderingDevice.INDEX_BUFFER_FORMAT_UINT32, idx)
		index_array = rd.index_array_create(index_buf, 0, PAGE_QUADS * 6)
	else:
		# one shared 16-bit pattern for 16384 quads (192 KB, stays in the GPU caches); each indirect command reaches its
		# quads through its base vertex (vertex_offset). The 32-bit page-wide buffer streamed 24 bytes of indices per quad.
		var idx16: PackedByteArray = Native.inst.tr_quad_indices(16384, 16)[0]
		index_buf = rd.index_buffer_create(16384 * 6, RenderingDevice.INDEX_BUFFER_FORMAT_UINT16, idx16)
		index_array = rd.index_array_create(index_buf, 0, 16384 * 6)
	var ss := RDSamplerState.new()
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	ss.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler = rd.sampler_create(ss)
	tex_rid = RenderingServer.texture_get_rd_texture(Res.atlas.texture.get_rid())
	if p_world != null and p_world.autoplay.has("trplanar"):
		planar = str(p_world.autoplay["trplanar"]) == "1"
	for m in 3:
		shaders[m] = _compile(m)
	_preallocate()


## Vertex pages for the render distance, created and cleared while the world loads: a page created mid-flight (a
## 64 MB buffer committed and zeroed by the driver on first use) stalled the GPU for 8-22 ms over ~0.3 s (the worst
## stutter of the flight benchmark, every ~3-4 s while new terrain streamed in). ~5,500 quads per chunk measured at
## RD16 (5.2 M quads for ~1,000 chunks); capped at 10 pages (640 MB); page 0 is the translucent page; more pages are
## still added on demand.
func _preallocate() -> void:
	var rdist := int(Settings.get_v("render_distance")) if Settings.values.has("render_distance") else 12
	var chunks := (2 * rdist + 1) * (2 * rdist + 1)
	var need := clampi(ceili(float(chunks) * 5500.0 / float(PAGE_QUADS)) + 1, 2, 10)
	# (no buffer_clear: D3D12 clears need a storage / UAV buffer; on these vertex buffers it removed the device)
	for i in need:
		_new_page()
	trans_page = 0


## The two effects (WorldManager._install_compositor orders them with SkyRD's).
func opaque_effect() -> CompositorEffect:
	if merged:
		return Effect.new(self, [0, 1, 2], CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE)
	return Effect.new(self, [0, 1], CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE)


func translucent_effect() -> CompositorEffect:
	return Effect.new(self, [2], CompositorEffect.EFFECT_CALLBACK_TYPE_POST_SKY)


## Frees every GPU resource (world exit).
func destroy() -> void:
	free_all()
	Native.inst.tr_clear(h)
	for us in _usets.values():
		if rd.uniform_set_is_valid(us):
			rd.free_rid(us)
	_usets.clear()
	for p in pipelines.values():
		rd.free_rid(p)
	pipelines.clear()
	for s in shaders:
		if (s as RID).is_valid():
			rd.free_rid(s)
	for va in varrays:
		rd.free_rid(va)
	varrays.clear()
	for p in pages:
		rd.free_rid(p)
	for p in attr_bufs:
		rd.free_rid(p)
	attr_bufs.clear()
	for o in origins:
		rd.free_rid(o)
	pages.clear()
	origins.clear()
	rd.free_rid(index_array)
	rd.free_rid(index_buf)
	rd.free_rid(indirect_buf)
	rd.free_rid(frame_ubo)
	rd.free_rid(sampler)
	if lm_sampler.is_valid():
		rd.free_rid(lm_sampler)


# ---------------------------------------------------------------- geometry (main thread, ChunkManager)

## Replaces the chunk group's geometry (3 material classes) by the packed result of its mesh job.
func upload(cx: int, cz: int, g: int, res: Dictionary) -> void:
	var packed: Array = res.get("packed", [])
	# occlusion culling: the group's 4 section visibility masks (an empty / all-air group is fully connected)
	Native.inst.tr_vis(h, cx, cz, g, res.get("vis", PackedInt64Array()))
	var origin := Vector3i(cx * 16, Coords.MIN_Y + g * Mesher.GH, cz * 16)
	var base := Coords.chunk_key(cx, cz) * 8 + g
	var tu0 := Time.get_ticks_usec()
	for m in 3:
		var key := (base << 2) | m
		var tr0 := Time.get_ticks_usec()
		_release(key)
		var tr1 := Time.get_ticks_usec()
		if m < packed.size() and packed[m] != null and not (packed[m] as Array).is_empty():
			_put(key, m, origin, packed[m])
		if tr1 - tr0 > 3000 and world != null and world.cm != null and world.cm.tracing:
			world.frame_tparts["trd_release"] = tr1 - tr0
	if Time.get_ticks_usec() - tu0 > 3000 and world != null and world.cm != null and world.cm.tracing:
		world.frame_tparts["trd_upload_total"] = Time.get_ticks_usec() - tu0


func free_chunk(cx: int, cz: int) -> void:
	Native.inst.tr_vis_clear(h, cx, cz)
	var base := Coords.chunk_key(cx, cz) * 8
	for g in Coords.SECTIONS / Mesher.GROUP:
		for m in 3:
			_release(((base + g) << 2) | m)


func free_all() -> void:
	for k in allocs.keys():
		_release(k)


func _put(key: int, mat: int, origin: Vector3i, packed: Array) -> void:
	var raw: PackedByteArray = packed[0]
	var nq := raw.size() / (4 * VERT_BYTES)
	if nq == 0 or nq > PAGE_QUADS:
		return
	var tracing: bool = world != null and world.cm != null and world.cm.tracing
	var ca: int = Native.inst.thread_cycles()[0] if tracing else 0
	var ta := Time.get_ticks_usec()
	var at := _alloc(nq, mat == 2)
	if tracing and Time.get_ticks_usec() - ta > 3000:
		world.frame_tparts["trd_alloc"] = [Time.get_ticks_usec() - ta, "Mcyc", (Native.inst.thread_cycles()[0] - ca) / 1000000.0]
	var pg := at.x
	var slot := _slot_alloc(pg)
	if slot < 0:
		_free_range(pg, at.y, nq)
		return
	var t0 := Time.get_ticks_usec()
	var data: PackedByteArray
	if planar:
		var st: Array = Native.inst.tr_stamp2(raw, slot)
		data = st[0]
		var t1p := Time.get_ticks_usec()
		rd.buffer_update(pages[pg], at.y * 4 * 8, (st[0] as PackedByteArray).size(), st[0])
		rd.buffer_update(attr_bufs[pg], at.y * 4 * 12, (st[1] as PackedByteArray).size(), st[1])
	else:
		data = Native.inst.tr_stamp(raw, slot)[0]
		rd.buffer_update(pages[pg], at.y * 4 * VERT_BYTES, data.size(), data)
	var t1 := t0
	var t2 := Time.get_ticks_usec()
	rd.buffer_update(origins[pg], slot * 16, 16, PackedInt32Array([origin.x, origin.y, origin.z, 0]).to_byte_array())
	var t3 := Time.get_ticks_usec()
	Native.inst.tr_put(h, key, mat, origin.x, origin.y, origin.z, at.y, packed[1], packed[2], pg)
	if t3 - t0 > 3000 and world != null and world.cm != null and world.cm.tracing:
		world.frame_tparts["trd_put %d KB" % (data.size() / 1024)] = [t1 - t0, t2 - t1, t3 - t2]
	allocs[key] = [pg, at.y, nq, slot]
	stats["quads_resident"] += nq


func _new_page() -> void:
	var t0 := Time.get_ticks_usec()
	if planar:
		var pb := rd.vertex_buffer_create(PAGE_QUADS * 4 * 8)
		var ab := rd.vertex_buffer_create(PAGE_QUADS * 4 * 12)
		pages.append(pb)
		attr_bufs.append(ab)
		varrays.append(rd.vertex_array_create(PAGE_QUADS * 4, _vformat(), [pb, ab], PackedInt64Array([0, 0])))
	else:
		var vb := rd.vertex_buffer_create(PAGE_QUADS * 4 * VERT_BYTES)
		pages.append(vb)
		varrays.append(rd.vertex_array_create(PAGE_QUADS * 4, _vformat(), [vb, vb], PackedInt64Array([0, 0])))
	origins.append(rd.storage_buffer_create(MAX_SLOTS * 16))
	Native.inst.tr_page_add(h, PAGE_QUADS)
	slot_free.append([])
	slot_next.append(0)
	stats["pages"] = pages.size()
	stats["page_alloc_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	if world != null and world.autoplay.has("fpsbench"):
		page_log.append("[terrain_rd] page %d allocated in %.2f ms (%d quads resident) at %.2f s" % [pages.size(), (Time.get_ticks_usec() - t0) / 1000.0, int(stats["quads_resident"]), Time.get_ticks_msec() / 1000.0])


## Best fit (native allocator: O(log n) with merging); a new page when nothing fits. Translucent geometry lives in
## its own page (trans_page) so it can be drawn in one global far-to-near order (render: draw runs); it spills into
## other pages only when that page is full (still globally ordered, one draw per page switch). Translucent order used
## to be far-to-near per page only: a farther chunk's water in another page was blended over a nearer chunk's ice
## (dark see-through strips along chunk borders).
var trans_page := -1


func _alloc(nq: int, translucent := false) -> Vector2i:
	var r: Array
	if translucent:
		if trans_page < 0:
			_new_page()
			trans_page = pages.size() - 1
		r = Native.inst.tr_alloc(h, nq, 1, trans_page)
		if int(r[0]) < 0:
			r = Native.inst.tr_alloc(h, nq, 0, -1)
	else:
		r = Native.inst.tr_alloc(h, nq, 2, trans_page)
	if int(r[0]) >= 0:
		return Vector2i(int(r[0]), int(r[1]))
	_new_page()
	r = Native.inst.tr_alloc(h, nq, 1, pages.size() - 1)
	return Vector2i(int(r[0]), int(r[1]))

func _vformat() -> int:
	if vformat < 0:
		var a0 := RDVertexAttribute.new()
		a0.location = 0
		a0.format = RenderingDevice.DATA_FORMAT_R32G32_UINT if planar else RenderingDevice.DATA_FORMAT_R32G32B32A32_UINT
		a0.stride = 8 if planar else VERT_BYTES
		a0.offset = 0
		var a1 := RDVertexAttribute.new()
		a1.location = 1
		a1.format = RenderingDevice.DATA_FORMAT_R32G32B32_UINT if planar else RenderingDevice.DATA_FORMAT_R32_UINT
		a1.stride = 12 if planar else VERT_BYTES
		a1.offset = 0 if planar else 16
		vformat = rd.vertex_format_create([a0, a1])
	return vformat

func _slot_alloc(pg: int) -> int:
	var sf: Array = slot_free[pg]
	if not sf.is_empty():
		return sf.pop_back()
	if int(slot_next[pg]) >= MAX_SLOTS:
		return -1
	slot_next[pg] = int(slot_next[pg]) + 1
	return int(slot_next[pg]) - 1


func _release(key: int) -> void:
	var a = allocs.get(key)
	if a == null:
		return
	allocs.erase(key)
	Native.inst.tr_del(h, key)
	(slot_free[int(a[0])] as Array).append(int(a[3]))
	_free_range(int(a[0]), int(a[1]), int(a[2]))
	stats["quads_resident"] -= int(a[2])


func _free_range(pg: int, s: int, n: int) -> void:
	Native.inst.tr_free(h, pg, s, n)


# ---------------------------------------------------------------- rendering (render thread = main thread)

static func _put_proj(b: PackedByteArray, off: int, p: Projection) -> void:
	for c in 4:
		var col: Vector4 = p[c]
		b.encode_float(off + c * 16, col.x)
		b.encode_float(off + c * 16 + 4, col.y)
		b.encode_float(off + c * 16 + 8, col.z)
		b.encode_float(off + c * 16 + 12, col.w)


func _frame_ubo(cam: Camera3D, org: Vector3i) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(144)
	var gv: Dictionary = ShaderGlobals.values
	# Java fog (fog.glsl): sRGB colour + strength, environmental start / end, render-distance start / end
	var fc: Vector4 = gv["mc_fog_color"]
	var fd: Vector4 = gv["mc_fog_dist"]
	b.encode_float(0, fc.x)
	b.encode_float(4, fc.y)
	b.encode_float(8, fc.z)
	b.encode_float(12, fc.w)
	b.encode_float(16, fd.x)
	b.encode_float(20, fd.y)
	b.encode_float(24, fd.z)
	b.encode_float(28, fd.w)
	b.encode_float(32, float(gv["sky_light_factor"]))
	b.encode_float(36, float(gv["gamma_boost"]))
	b.encode_float(40, float(gv["night_vision"]))
	b.encode_float(44, float(gv["ambient_light"]))
	b.encode_s32(48, org.x)
	b.encode_s32(52, org.y)
	b.encode_s32(56, org.z)
	_put_proj(b, 64, Projection.create_depth_correction(true) * cam.get_camera_projection() * Projection(cam.global_transform.affine_inverse()))
	var cp := cam.global_position
	b.encode_float(128, cp.x)
	b.encode_float(132, cp.y)
	b.encode_float(136, cp.z)
	# Java lightmap texels (x = block level, y = sky level), read per vertex by level: no vertex texture fetch
	var li: Image = world.lightmap_img
	var ld := li.get_data() if li != null else PackedByteArray()
	if ld.size() != 1024:
		ld.resize(1024)
	b.append_array(ld)
	b.append_array(overlay_layers().to_byte_array())
	return b


## Culling + uploads once per frame (first effect callback of the frame).
func _prepare() -> void:
	var cam: Camera3D = world.camera
	var org: Vector3i = world.cm.origin
	var pl := PackedFloat32Array()
	for p in cam.get_frustum():
		var pp: Plane = p
		pl.append_array([pp.normal.x, pp.normal.y, pp.normal.z, pp.d])
	var cp := cam.global_position
	var t0 := Time.get_ticks_usec()
	# cam[3]: render radius in chunks (occlusion graph extent)
	var r: Array = Native.inst.tr_cull_all(h, pl, PackedFloat32Array([cp.x, cp.y, cp.z, float(world.cm.radius)]), PackedInt32Array([org.x, org.y, org.z]), pages.size(), debug_flags)
	stats["cull_us"] = Time.get_ticks_usec() - t0
	var cmds: PackedByteArray = r[0]
	_meta = r[1]
	_runs = r[2] if r.size() > 2 else PackedInt32Array()
	var n := mini(cmds.size(), MAX_CMDS * 20)
	stats["cmds"] = n / 20
	if _meta.size() >= 2:   # stats: quads drawn / visible groups per frame (benchmark averages)
		stats["q_sum"] = int(stats.get("q_sum", 0)) + _meta[_meta.size() - 2]
		stats["g_sum"] = int(stats.get("g_sum", 0)) + _meta[_meta.size() - 1]
		stats["c_sum"] = int(stats.get("c_sum", 0)) + n / 20
		stats["q_n"] = int(stats.get("q_n", 0)) + 1
	if n > 0:
		rd.buffer_update(indirect_buf, 0, n, cmds)
	rd.buffer_update(frame_ubo, 0, FRAME_BYTES, _frame_ubo(cam, org))


func render(render_data: RenderData, mats: Array) -> void:
	var rsb: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	if rsb == null:
		return
	var terrain := not pages.is_empty() and world.lightmap_img != null
	if terrain:
		var frame := Engine.get_frames_drawn()
		if frame != _cull_frame:
			_cull_frame = frame
			_prepare()
	# with MSAA the scene is still in the multisampled buffers here (Godot resolves after the transparent pass)
	var msaa := rsb.get_msaa_3d()
	var ms := msaa != RenderingServer.VIEWPORT_MSAA_DISABLED
	var fb := FramebufferCacheRD.get_cache_multipass([rsb.get_color_layer(0, ms), rsb.get_depth_layer(0, ms)], [], 1)
	var fmt := rd.framebuffer_get_format(fb)
	_samples = [RenderingDevice.TEXTURE_SAMPLES_1, RenderingDevice.TEXTURE_SAMPLES_2, RenderingDevice.TEXTURE_SAMPLES_4, RenderingDevice.TEXTURE_SAMPLES_8][clampi(msaa, 0, 3)]
	var np := pages.size() if terrain and not (debug_flags & 32) else 0   # 32: experiment, no terrain draws (pass only)
	var dl := -1
	for m in mats:
		# SkyRD in the same render pass: the sky behind the opaque terrain (after mats 0 / 1, before the translucent one)
		if m == 2 and sky_rd != null and mats.has(0):
			if dl < 0:
				dl = rd.draw_list_begin(fb, RenderingDevice.DRAW_DEFAULT_ALL)
			sky_rd.draw_sky(dl, fmt, _samples, rsb.get_internal_size())
		if m == 2:
			# translucent: global far-to-near order across pages, one indirect draw per run of same-page commands
			if np > 0:
				for ri in range(0, _runs.size(), 3):
					var rpg: int = _runs[ri]
					var rfirst: int = _runs[ri + 1]
					var rcnt: int = _runs[ri + 2]
					if rpg < 0 or rpg >= np or rcnt <= 0 or rfirst + rcnt > MAX_CMDS:
						continue
					if dl < 0:
						dl = rd.draw_list_begin(fb, RenderingDevice.DRAW_DEFAULT_ALL)
					rd.draw_list_bind_render_pipeline(dl, _pipeline(fmt, m))
					rd.draw_list_bind_uniform_set(dl, _uset(m, rpg), 0)
					rd.draw_list_bind_vertex_array(dl, varrays[rpg])
					rd.draw_list_bind_index_array(dl, index_array)
					rd.draw_list_draw_indirect(dl, true, indirect_buf, rfirst * 20, rcnt, 20)
			continue
		for pg in np:
			var mi: int = (m * np + pg) * 2
			if mi + 1 >= _meta.size():
				continue
			var cnt: int = _meta[mi + 1]
			if cnt == 0:
				continue
			var first: int = _meta[mi]
			if first + cnt > MAX_CMDS:
				continue
			if dl < 0:
				dl = rd.draw_list_begin(fb, RenderingDevice.DRAW_DEFAULT_ALL)
			rd.draw_list_bind_render_pipeline(dl, _pipeline(fmt, m))
			rd.draw_list_bind_uniform_set(dl, _uset(m, pg), 0)
			rd.draw_list_bind_vertex_array(dl, varrays[pg])
			rd.draw_list_bind_index_array(dl, index_array)
			rd.draw_list_draw_indirect(dl, true, indirect_buf, first * 20, cnt, 20)
	# SkyRD in the same render pass: the sky behind the opaque terrain, the clouds after the translucent terrain
	if sky_rd != null:
		if mats.has(0) and not mats.has(2):
			if dl < 0:
				dl = rd.draw_list_begin(fb, RenderingDevice.DRAW_DEFAULT_ALL)
			sky_rd.draw_sky(dl, fmt, _samples, rsb.get_internal_size())
		if mats.has(2) and sky_rd.has_clouds():
			if dl < 0:
				dl = rd.draw_list_begin(fb, RenderingDevice.DRAW_DEFAULT_ALL)
			sky_rd.draw_clouds(dl, fmt, _samples)
	if dl >= 0:
		rd.draw_list_end()


func _uset(m: int, pg: int) -> RID:
	var k := m * 4096 + pg
	var us: RID = _usets.get(k, RID())
	if us.is_valid() and rd.uniform_set_is_valid(us):
		return us
	us = rd.uniform_set_create([_u_storage(1, origins[pg]), _u_ubo(2, frame_ubo), _u_tex(4)], shaders[m], 0)
	_usets[k] = us
	return us


func _compile(mat: int) -> RID:
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_vertex = VERT.replace("//VDEFINES", ("#define PLANAR\n" if planar else "") + ("#define CHEAPVS\n" if debug_flags & 256 else "") + ("#define DEGEN\n" if debug_flags & 512 else ""))
	var defs := "#define CUTOUT\n" if mat == 1 else ("#define TRANSLUCENT\n" if mat == 2 else "")
	if debug_flags & 16:
		defs += "#define FLAT\n"   # experiment: constant colour (fragment cost)
	src.source_fragment = FRAG.replace("//DEFINES", defs)
	var spirv := rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_vertex != "" or spirv.compile_error_fragment != "":
		push_error("TerrainRD shader: %s %s" % [spirv.compile_error_vertex, spirv.compile_error_fragment])
		return RID()
	return rd.shader_create_from_spirv(spirv)


func _pipeline(fb_format: int, mat: int) -> RID:
	var k := fb_format * 4 + mat
	if pipelines.has(k):
		return pipelines[k]
	var rs := RDPipelineRasterizationState.new()
	rs.cull_mode = RenderingDevice.POLYGON_CULL_BACK
	rs.front_face = RenderingDevice.POLYGON_FRONT_FACE_CLOCKWISE   # verified visually with Godot's depth correction
	var ms := RDPipelineMultisampleState.new()
	ms.sample_count = _samples
	var ds := RDPipelineDepthStencilState.new()
	ds.enable_depth_test = true
	ds.enable_depth_write = mat != 2
	ds.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER_OR_EQUAL   # reverse Z
	var bs := RDPipelineColorBlendState.new()
	var att := RDPipelineColorBlendStateAttachment.new()
	if mat == 2:
		att.set_as_mix()
	bs.attachments = [att]
	var p := rd.render_pipeline_create(shaders[mat], fb_format, _vformat(), RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, rs, ms, ds, bs)
	pipelines[k] = p
	return p


func _u_storage(b: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = b
	u.add_id(rid)
	return u


func _u_ubo(b: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u.binding = b
	u.add_id(rid)
	return u


## Java lightmap texture (WorldManager.lightmap_tex, 16x16, updated in place: same RID), linear, clamped.
func _u_lightmap(b: int) -> RDUniform:
	if not lm_sampler.is_valid():
		var ss := RDSamplerState.new()
		ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		lm_sampler = rd.sampler_create(ss)
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = b
	u.add_id(lm_sampler)
	u.add_id(RenderingServer.texture_get_rd_texture(world.lightmap_tex.get_rid()))
	return u


func _u_tex(b: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = b
	u.add_id(sampler)
	u.add_id(tex_rid)
	return u


## Overlay texture layers (grass side overlay etc.) as a palette: vertices carry a 6-bit index (63 = none) so the light can
## use 6 bits per channel (quarter levels). Built once from every state's cube-face data (models / fluids have none).
static var _ovl_layers := PackedInt32Array()
static var _ovl_map := PackedByteArray()


static func overlay_layers() -> PackedInt32Array:
	if _ovl_layers.is_empty():
		_build_overlays()
	return _ovl_layers


## Layer -> palette index (4096 entries, 63 = none), the third argument of RecraftNative.tr_pack.
static func overlay_map() -> PackedByteArray:
	if _ovl_map.is_empty():
		_build_overlays()
	return _ovl_map


static func _build_overlays() -> void:
	var seen := {}
	var faces: PackedInt32Array = Res.blocks.st_faces
	for v in faces:
		var ov := ((v >> 12) & 0xFFF) - 1
		if ov >= 0:
			seen[ov] = true
	var lst: Array = seen.keys()
	lst.sort()
	if lst.size() > 63:
		push_error("TerrainRD: %d overlay layers, palette holds 63" % lst.size())
		lst = lst.slice(0, 63)
	var layers := PackedInt32Array()
	layers.resize(64)
	layers.fill(-1)
	var m := PackedByteArray()
	m.resize(4096)
	m.fill(63)
	for i in lst.size():
		layers[i] = int(lst[i])
		m[int(lst[i])] = i
	_ovl_layers = layers
	_ovl_map = m


class Effect:
	extends CompositorEffect
	var tr: TerrainRD
	var mats: Array

	func _init(p_tr: TerrainRD, p_mats: Array, p_type: int) -> void:
		tr = p_tr
		mats = p_mats
		effect_callback_type = p_type
		needs_motion_vectors = false

	func _render_callback(_type: int, render_data: RenderData) -> void:
		tr.render(render_data, mats)


const VERT := """
#version 450
//VDEFINES
#ifdef PLANAR
layout(location = 0) in uvec2 a_p;
layout(location = 1) in uvec3 a_a;
#else
layout(location = 0) in uvec4 a_w;
layout(location = 1) in uint a_w4;
#endif
layout(set = 0, binding = 1, std430) restrict readonly buffer Origins { ivec4 org[]; };
layout(set = 0, binding = 2, std140) uniform Frame { vec4 fog_color; vec4 fog; vec4 globals; ivec4 origin; mat4 viewproj; vec4 cam; uvec4 lm[64]; ivec4 ovl[16]; } fr;
layout(location = 0) out vec2 v_uv;
layout(location = 1) flat out vec2 v_layers;
layout(location = 2) out vec3 v_lm;   // lightmap colour (Java terrain.vsh: sample_lightmap per vertex)
layout(location = 3) out vec4 v_color;
layout(location = 4) out vec2 v_fogd;   // spherical, cylindrical distance (Java terrain.vsh)
void main() {
#ifdef PLANAR
	uint w0 = a_p.x;
	uint w1 = a_p.y;
	uint w2 = a_a.x;
	uint w3 = a_a.y;
	uint w4 = a_a.z;
#else
	uint w0 = a_w.x;
	uint w1 = a_w.y;
	uint w2 = a_w.z;
	uint w3 = a_w.w;
	uint w4 = a_w4;
#endif
	vec3 base = vec3(org[w1 >> 17u].xyz - fr.origin.xyz);
	vec3 p = vec3(float(w0 & 0xFFFFu) / 2048.0 - 8.0, float(w1 & 0xFFFFu) / 512.0 - 8.0, float(w0 >> 16u) / 2048.0 - 8.0);
	vec3 rel = base + p;
	gl_Position = fr.viewproj * vec4(rel, 1.0);
#ifdef CHEAPVS
	v_fogd = vec2(0.0);   // experiment (--trhide=256): vertex shader cost without fog / lightmap
	v_uv = vec2(float(w2 & 0xFFFFu), float(w2 >> 16u)) / 2048.0 - 8.0;
	v_color = unpackUnorm4x8(w3);
	v_layers = vec2(float(w4 & 0xFFFu), -1.0);
	v_lm = vec3(1.0);
	return;
#endif
	vec3 cr = rel - fr.cam.xyz;
	v_fogd = vec2(length(cr), max(length(cr.xz), abs(cr.y)));
	v_uv = vec2(float(w2 & 0xFFFFu), float(w2 >> 16u)) / 2048.0 - 8.0;
	v_color = unpackUnorm4x8(w3);
	uint oi = (w4 >> 12u) & 63u;
	v_layers = vec2(float(w4 & 0xFFFu), oi == 63u ? -1.0 : float(fr.ovl[oi >> 2u][oi & 3u]));
	// Java sample_lightmap: texture(lightMap, clamp(uv / 256 + 0.5 / 16, ...)) on the linear-filtered 16 x 16 lightmap,
	// uv = light * 16 in quarter levels -> bilinear between the levels around (block, sky)
	float fb = float((w4 >> 24u) & 63u) * 0.25;
	float fs = float((w4 >> 18u) & 63u) * 0.25;
	uint b0 = min(uint(fb), 15u);
	uint s0 = min(uint(fs), 15u);
	uint b1 = min(b0 + 1u, 15u);
	uint s1 = min(s0 + 1u, 15u);
	float tb = fb - float(b0);
	float ts = fs - float(s0);
	uint i00 = s0 * 16u + b0;
	uint i10 = s0 * 16u + b1;
	uint i01 = s1 * 16u + b0;
	uint i11 = s1 * 16u + b1;
	vec3 c00 = unpackUnorm4x8(fr.lm[i00 >> 2u][i00 & 3u]).rgb;
	vec3 c10 = unpackUnorm4x8(fr.lm[i10 >> 2u][i10 & 3u]).rgb;
	vec3 c01 = unpackUnorm4x8(fr.lm[i01 >> 2u][i01 & 3u]).rgb;
	vec3 c11 = unpackUnorm4x8(fr.lm[i11 >> 2u][i11 & 3u]).rgb;
	v_lm = mix(mix(c00, c10, tb), mix(c01, c11, tb), ts);
#ifdef DEGEN
	gl_Position = vec4(v_lm.x * 0.0 + 2.0, 2.0, 2.0, 1.0);   // experiment (--trhide=512): all work, no rasterization
#endif
}
"""

const FRAG := """
#version 450
//DEFINES
layout(set = 0, binding = 2, std140) uniform Frame { vec4 fog_color; vec4 fog; vec4 globals; ivec4 origin; mat4 viewproj; vec4 cam; uvec4 lm[64]; ivec4 ovl[16]; } fr;
layout(set = 0, binding = 4) uniform sampler2DArray block_tex;
layout(location = 0) in vec2 v_uv;
layout(location = 1) flat in vec2 v_layers;
layout(location = 2) in vec3 v_lm;
layout(location = 3) in vec4 v_color;
layout(location = 4) in vec2 v_fogd;
layout(location = 0) out vec4 frag;
float lin_fog(float d, float s, float e) {
	if (d <= s) return 0.0;
	if (d >= e) return 1.0;
	return (d - s) / (e - s);
}
vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}
void main() {
#ifdef FLAT
	frag = vec4(v_color.rgb * v_lm, 1.0);
	return;
#endif
	vec4 base = texture(block_tex, vec3(v_uv, v_layers.x));
#ifdef CUTOUT
	if (base.a < 0.5) discard;
#endif
	vec3 col = base.rgb;
	if (v_layers.y >= 0.0) {
		vec4 ov = texture(block_tex, vec3(v_uv, v_layers.y));
		col = mix(col, ov.rgb * v_color.rgb, ov.a);
	} else {
		col *= v_color.rgb;
	}
	col *= v_lm * v_color.a;
	col = clamp(col, 0.0, 1.0);
	// Java fog: max(environmental over the spherical, render distance over the cylindrical distance), mixed in sRGB
	float fv = max(lin_fog(v_fogd.x, fr.fog.x, fr.fog.y), lin_fog(v_fogd.y, fr.fog.z, fr.fog.w));
	col = mix(col, fr.fog_color.rgb, fv * fr.fog_color.a);
	vec3 lin = to_linear(col);
#ifdef TRANSLUCENT
	// Java blends translucent terrain in sRGB; our target is linear, where a light background shows through far more
	// (sand under water turned lavender). 1 - (1 - a)^1.5 restores the vanilla balance for typical backgrounds.
	frag = vec4(lin, 1.0 - pow(1.0 - base.a, 1.5));
#else
	frag = vec4(lin, 1.0);
#endif
}
"""
