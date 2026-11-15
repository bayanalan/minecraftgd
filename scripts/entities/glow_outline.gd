## Glowing outline (Java EntityOutline rendering + post_effect/entity_outline): entities with the Glowing effect are drawn
## a second time into an outline buffer as flat silhouettes in their team colour (white without a team - /team has no
## colour option here), with no depth test against the world, so the outline shows through walls; entity_sobel keeps
## the silhouette edges (4-neighbour alpha differences, colour = 0.2 x the summed neighbour colours), two box blurs
## (radius 2: horizontal, then vertical) soften them, and the buffer is alpha-blended over the frame.
## Costs nothing while nothing glows: this node only processes and the outline SubViewport only renders while a tracked
## entity glows, and the buffer covers only the screen rectangle around the glowing entities (a sub-frustum of the main
## camera), so even then the extra pass is a few hundred pixels wide.
## Contract: GlowOutline.track(ent) when an entity gains Glowing (MobBehaviors.add_effect), GlowOutline.wake() when the
## player does (Player.add_effect); untracking happens here once the effect ends / the entity is gone.
class_name GlowOutline
extends Node

const LAYER_BIT := 1 << 19   # visual layer 20: the outline camera sees only the meshes of glowing entities
const MARGIN := 4            # px kept around the silhouettes (sobel 1 + blur 2, +1)
const STEP := 64             # outline buffer size granularity (px): resized only when the needed area changes a lot

static var inst: GlowOutline = null

var world
var _ents: Array = []        # glowing EntityManager.Ent
var _player_lit := false     # the third-person player model carries the outline bit
var _vp: SubViewport
var _cam: Camera3D
var _layer: CanvasLayer
var _rect: ColorRect
var _shrink_t := 0


static func track(e) -> void:
	if inst == null or inst._ents.has(e):
		return
	inst._ents.append(e)
	inst.set_process(true)


static func wake() -> void:
	if inst != null:
		inst.set_process(true)


func _ready() -> void:
	inst = self
	process_priority = 1000   # after the camera (WorldManager) and the entity nodes (EntityManager) moved this frame
	set_process(false)


func _exit_tree() -> void:
	if inst == self:
		inst = null


static func glowing(e) -> bool:
	var fx = e.data.get("fx")
	return fx is Dictionary and (fx as Dictionary).has("glowing")


func _process(_delta: float) -> void:
	var cam: Camera3D = world.camera if world != null else null
	var rmin := Vector2(INF, INF)
	var rmax := Vector2(-INF, -INF)
	var i := _ents.size() - 1
	while i >= 0:
		var e = _ents[i]
		var n = e.node   # (untyped: a freed node must not fail the assignment)
		if e.dead or n == null or not is_instance_valid(n) or not (n as Node3D).is_inside_tree() or not glowing(e):
			if is_instance_valid(n):
				_set_bits(n, false)
			_ents.remove_at(i)
		elif (n as Node3D).visible:
			var ab := _set_bits(n, true)
			if ab.size != Vector3.ZERO and cam != null:
				var r := _screen_rect(cam, ab)
				rmin = rmin.min(r.position)
				rmax = rmax.max(r.end)
		i -= 1
	# the player (third person: Java draws the local player's outline too when it glows and is visible)
	var p = world.player if world != null else null
	var pm = world.get("player_model") if world != null else null
	var pg: bool = p != null and pm != null and is_instance_valid(pm) and (p.effects as Dictionary).has("glowing") and not p.dead
	if pg != _player_lit and pm != null and is_instance_valid(pm):
		_set_bits(pm, pg)
		_player_lit = pg
	if pg and (pm as Node3D).visible and cam != null:
		var pab := _set_bits(pm, true)
		if pab.size != Vector3.ZERO:
			var pr := _screen_rect(cam, pab)
			rmin = rmin.min(pr.position)
			rmax = rmax.max(pr.end)
	if _ents.is_empty() and not pg:
		set_process(false)
	if cam == null or rmax.x <= rmin.x or rmax.y <= rmin.y:
		_hide()
		return
	_draw_region(cam, rmin, rmax)


## Sets / clears the outline layer bit on every visual of the rig (parts added later - armour, held items - get it on
## the next frame) and returns their merged world AABB.
func _set_bits(n: Node, on: bool) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is VisualInstance3D:
			var vi := c as VisualInstance3D
			var has := (vi.layers & LAYER_BIT) != 0
			if on != has:
				vi.layers = (vi.layers | LAYER_BIT) if on else (vi.layers & ~LAYER_BIT)
			if on and vi.is_visible_in_tree():
				var wb: AABB = vi.global_transform * vi.get_aabb()
				out = wb if first else out.merge(wb)
				first = false
		for ch in c.get_children():
			stack.append(ch)
	return out


## Screen-space bounds (main viewport pixels) of a world AABB; the whole screen when a corner is behind the camera.
func _screen_rect(cam: Camera3D, ab: AABB) -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for k in 8:
		var c := ab.get_endpoint(k)
		if cam.is_position_behind(c):
			return Rect2(Vector2.ZERO, vs)
		var s := cam.unproject_position(c)
		mn = mn.min(s)
		mx = mx.max(s)
	return Rect2(mn, mx - mn)


func _hide() -> void:
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_layer.visible = false


func _build() -> void:
	_vp = SubViewport.new()
	_vp.name = "GlowOutlineBuffer"
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.use_taa = false
	_vp.use_debanding = false
	_vp.use_occlusion_culling = false
	_vp.positional_shadow_atlas_size = 0
	_vp.gui_disable_input = true
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_vp.size = Vector2i(STEP, STEP)
	_cam = Camera3D.new()
	_cam.cull_mask = LAYER_BIT
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_cam.environment = env
	_vp.add_child(_cam)
	add_child(_vp)
	_cam.current = true
	_layer = CanvasLayer.new()
	_layer.layer = -1   # over the 3D frame, under the HUD / screens (Java blends the outline before the GUI)
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/glow_outline.gdshader")
	mat.set_shader_parameter("sil", _vp.get_texture())
	mat.set_shader_parameter("team", Color(1, 1, 1))
	_rect.material = mat
	_layer.add_child(_rect)


## Renders the outline buffer for the screen rectangle [rmin, rmax] (+ margin) and places the blend quad over it.
func _draw_region(cam: Camera3D, rmin: Vector2, rmax: Vector2) -> void:
	var vs := get_viewport().get_visible_rect().size
	var x0 := clampf(floorf(rmin.x) - MARGIN, 0.0, vs.x)
	var y0 := clampf(floorf(rmin.y) - MARGIN, 0.0, vs.y)
	var x1 := clampf(ceilf(rmax.x) + MARGIN, 0.0, vs.x)
	var y1 := clampf(ceilf(rmax.y) + MARGIN, 0.0, vs.y)
	if x1 - x0 < 1.0 or y1 - y0 < 1.0:
		_hide()
		return
	if _vp == null:
		_build()
	# buffer size: the needed area rounded up to STEP (capped at the screen); shrinks only after it stayed under half
	# for a second, so moving / turning does not reallocate the render target every frame
	var need := Vector2i(mini(int(ceilf((x1 - x0) / STEP)) * STEP, int(vs.x)), mini(int(ceilf((y1 - y0) / STEP)) * STEP, int(vs.y)))
	var cur := _vp.size
	if need.x > cur.x or need.y > cur.y:
		_vp.size = Vector2i(maxi(need.x, cur.x), maxi(need.y, cur.y))
		_shrink_t = 0
	elif need.x * 2 < cur.x or need.y * 2 < cur.y:
		_shrink_t += 1
		if _shrink_t > 60:
			_vp.size = need
			_shrink_t = 0
	else:
		_shrink_t = 0
	if _vp.size.x > int(vs.x) or _vp.size.y > int(vs.y):
		_vp.size = _vp.size.min(Vector2i(vs))   # (window made smaller)
	var sz := Vector2(_vp.size)
	var rx := minf(x0, vs.x - sz.x)
	var ry := minf(y0, vs.y - sz.y)
	# sub-frustum of the main camera covering exactly the pixels [rx, rx + w) x [ry, ry + h) (KEEP_HEIGHT: vertical fov)
	var nr := cam.near
	var top := nr * tan(deg_to_rad(cam.fov) * 0.5)
	var right := top * vs.x / vs.y
	var l := (rx / vs.x * 2.0 - 1.0) * right
	var r := ((rx + sz.x) / vs.x * 2.0 - 1.0) * right
	var t := (1.0 - ry / vs.y * 2.0) * top
	var b := (1.0 - (ry + sz.y) / vs.y * 2.0) * top
	_cam.set_frustum(t - b, Vector2((l + r) * 0.5, (t + b) * 0.5), nr, cam.far)
	_cam.global_transform = cam.global_transform
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_rect.position = Vector2(rx, ry)
	_rect.size = sz
	_layer.visible = true
