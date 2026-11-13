extends Node3D
## Engine floor benchmark (--emptybench): the game's sky shader + environment (linear tonemap, depth fog), a camera and
## one label, borderless fullscreen at native resolution, V-Sync off, no FPS cap. No world, no scripts per frame
## beyond this one. Prints "[empty] RESULT {...}" after 8 s and quits. Measures what Forward+ costs per frame at this
## resolution before any game content is drawn.

var _ft: Array = []
var _t0 := 0
var _last := 0
var _vp: RID


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 80, 0)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	cam.far = 16 * 16 + 32
	add_child(cam)
	cam.make_current()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 200.0
	env.fog_depth_end = 256.0
	we.environment = env
	add_child(we)
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "empty scene"
	label.add_theme_font_size_override("font_size", 30)
	layer.add_child(label)
	add_child(layer)
	var args := OS.get_cmdline_user_args()
	if args.has("--emptyapply"):
		Settings.apply_all()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	if args.has("--emptycomp"):
		var comp := Compositor.new()
		var e := CompositorEffect.new()
		e.effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE
		comp.compositor_effects = [e]
		cam.compositor = comp
	if args.has("--emptynear"):
		cam.near = 0.05
		cam.far = 2000.0
	if args.has("--emptykeep"):   # game setup now: no Godot sky pass, the frame is fully covered by our own draws
		env.background_mode = Environment.BG_KEEP
	_vp = get_viewport().get_viewport_rid()
	if args.has("--empty2d"):   # 3D disabled on the main viewport: canvas only (floor of a full-frame RD renderer)
		RenderingServer.viewport_set_disable_3d(_vp, true)
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_t0 = Time.get_ticks_usec()
	_last = _t0


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if now - _t0 > 2000000:   # 2 s warm-up
		_ft.append((now - _last) / 1000.0)
	_last = now
	if now - _t0 > 10000000:
		_ft.sort()
		var tot := 0.0
		for f in _ft:
			tot += f
		print("[empty] RESULT %s" % JSON.stringify({"window": DisplayServer.window_get_size(), "frames": _ft.size(),
			"fps_avg": snappedf(1000.0 * _ft.size() / tot, 0.1), "fps_median": snappedf(1000.0 / _ft[_ft.size() / 2], 0.1),
			"ms_p99": snappedf(_ft[int(_ft.size() * 0.99)], 0.001), "gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(_vp), 0.001),
			"render_cpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(_vp), 0.001)}))
		get_tree().quit()
