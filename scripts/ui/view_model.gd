## ViewModel — first-person hand and held item (Java ItemInHandRenderer), drawn in the main view: the rig is a child
## of the world camera and every material is swapped for a VIEWMODEL variant of its shader (shaders/viewmodel.gdshaderinc)
## that re-projects it with Java's fixed 70 deg hand FOV and packs its depth in front of the world, so it never clips
## into terrain (Java clears depth before the hand pass). No second 3D render. Empty hand: renderPlayerArm pose chain
## (translate 0.64/-0.6/-0.72, Y 45, swing Y/Z, translate (-1, 3.6, 3.5), Z 120, X 200, Y -135, translate 5.6) applied
## to the player model's right arm (pivot -5, 2, 0).
## Items: swing translate (-0.4 sin(sqrt s pi), 0.2 sin(sqrt s 2pi), -0.2 sin(s pi)), applyItemArmTransform
## (0.56, -0.52, -0.72), applyItemArmAttackTransform, then the model's firstperson_righthand display transform
## (generated items: rot (0, -90, 25), trans (1.13, 3.2, 1.13)/16, scale 0.68; blocks: rot (0, 45, 0), scale 0.4)
## and the -0.5 model offset. Items are extruded from their icon like Java ItemModelGenerator (1/16 thick).
## Lit by the entity shader with the light level at the player's eyes.
class_name ViewModel
extends CanvasLayer

var world
var rig: Node3D             # child of the world camera; holds the arm and item roots (camera space)
var arm: Node3D
var item_root: Node3D
var off_root: Node3D        # offhand item (Java left arm, i = -1)
var _item_key := -2
var _off_key := -2
var _meshes: Array = []
var _vm_pending := 3        # frames left to convert newly built hand meshes to VIEWMODEL materials
var _fov_scale := -1.0
var _vm_mats: Dictionary = {}           # source material instance id -> VIEWMODEL material
# Java ItemInHandRenderer.tick: the shown stacks and their heights (the shown item lowers 0.4 / tick when the held one
# changes and is swapped below 0.1, the new one rises; the main hand also follows the attack strength cubed)
var _main_h := 0.0
var _main_h_old := 0.0
var _off_h := 0.0
var _off_h_old := 0.0
var _shown_main: ItemStack = null
var _shown_slot := -1
var _shown_off: ItemStack = null
static var _vm_shaders: Dictionary = {} # source shader instance id -> VIEWMODEL variant shader


func _ready() -> void:
	layer = 1
	rig = Node3D.new()
	rig.name = "ViewModelRig"
	# right arm of the player model (Java PlayerModel.rightArm box, wide skin)
	arm = Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	EntityRenderer.box_arrays(Vector3(-3, -2, -2), Vector3(4, 12, 4), Vector2(40, 16), Vector2(64, 64), st)
	var ami := MeshInstance3D.new()
	ami.mesh = st.commit()
	ami.material_override = EntityRenderer.material("entity/player/wide/steve")
	arm.add_child(ami)
	_meshes.append(ami)
	rig.add_child(arm)
	item_root = Node3D.new()
	rig.add_child(item_root)
	off_root = Node3D.new()
	rig.add_child(off_root)
	rig.visible = false
	if world != null and world.camera != null:
		world.camera.add_child(rig)


## Swaps the materials of hand meshes not yet converted for their VIEWMODEL variants (recursively).
func _convert(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and not c.has_meta("vm"):
			var mi := c as MeshInstance3D
			mi.set_meta("vm", true)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 16.0   # culled with the world camera; the hand projection differs
			if mi.material_override != null:
				mi.material_override = _vm_material(mi.material_override)
			elif mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					var sm := mi.get_surface_override_material(i)
					if sm == null:
						sm = mi.mesh.surface_get_material(i)
					if sm != null:
						mi.set_surface_override_material(i, _vm_material(sm))
		_convert(c)


func _vm_material(m: Material) -> Material:
	var k := m.get_instance_id()
	if _vm_mats.has(k):
		return _vm_mats[k]
	if _vm_mats.size() > 256:
		_vm_mats.clear()
	var out: Material = m
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		var sm := m as ShaderMaterial
		var v := ShaderMaterial.new()
		v.shader = _vm_shader(sm.shader)
		for u in sm.shader.get_shader_uniform_list():
			v.set_shader_parameter(u["name"], sm.get_shader_parameter(u["name"]))
		out = v
	elif m is BaseMaterial3D:
		var v2 := ShaderMaterial.new()
		v2.shader = load("res://shaders/viewmodel_unshaded.gdshader")
		v2.set_shader_parameter("tex", (m as BaseMaterial3D).albedo_texture)
		out = v2
	_vm_mats[k] = out
	return out


static func _vm_shader(s: Shader) -> Shader:
	var k := s.get_instance_id()
	if _vm_shaders.has(k):
		return _vm_shaders[k]
	var out := s
	var code := s.code
	if code.contains("VM_POSITION") or code.contains("voxel_common"):
		var v := Shader.new()
		v.code = code.replace("shader_type spatial;", "shader_type spatial;\n#define VIEWMODEL")
		out = v
	else:
		push_warning("ViewModel: shader without the VM_POSITION hook, drawn with the world projection: " + s.resource_path)
	_vm_shaders[k] = out
	return out

## Java GameRenderer.bobView: walk phase h = -(walkDist + (walkDist - walkDistO) * partial), amplitude i = lerp(oBob, bob);
## translate (sin(h pi) i / 2, -|cos(h pi) i|, 0), roll sin(h pi) i * 3 deg, pitch |cos(h pi - 0.2) i| * 5 deg.
static func bob_transform(p: Player, partial: float) -> Transform3D:
	var h := -(p.walk_phase + (p.walk_phase - p.prev_walk_phase) * partial)
	var i := lerpf(p.prev_bob, p.bob, partial)
	var t := Transform3D(Basis.IDENTITY, Vector3(sin(h * PI) * i * 0.5, -absf(cos(h * PI) * i), 0.0))
	t = _rot(t, Vector3.BACK, sin(h * PI) * i * 3.0)
	t = _rot(t, Vector3.RIGHT, absf(cos(h * PI - 0.2) * i) * 5.0)
	return t


## Java PoseStack helpers (post-multiplied, degrees).
static func _rot(t: Transform3D, axis: Vector3, deg: float) -> Transform3D:
	t.basis = t.basis * Basis(axis, deg_to_rad(deg))
	return t


static func _tr(t: Transform3D, v: Vector3) -> Transform3D:
	return t * Transform3D(Basis.IDENTITY, v)


## Same stack for the hand animation: Java keeps the shown stack when the held one is the same object (counts change in
## place) or ItemStack.matches it (same item, count and components - e.g. two identical stacks).
static func _same_stack(a: ItemStack, b: ItemStack, same_slot: bool) -> bool:
	if a == null:
		return false
	if a.item != b.item:
		return false
	return same_slot or (a.count == b.count and a.components == b.components)


func game_tick() -> void:
	if world == null or world.player == null:
		return
	var p: Player = world.player
	_main_h_old = _main_h
	_off_h_old = _off_h
	var cur := p.inventory.held()
	var cur_off := p.inventory.get_slot(Inventory.OFFHAND)
	var same_main := _same_stack(_shown_main, cur, p.inventory.selected == _shown_slot)
	if same_main:
		_shown_main = cur
		_shown_slot = p.inventory.selected
	var same_off := _same_stack(_shown_off, cur_off, true)
	if same_off:
		_shown_off = cur_off
	var f: float = p.attack_strength(1.0)
	_main_h += clampf((f * f * f if same_main else 0.0) - _main_h, -0.4, 0.4)
	_off_h += clampf((1.0 if same_off else 0.0) - _off_h, -0.4, 0.4)
	if _main_h < 0.1:
		_shown_main = cur
		_shown_slot = p.inventory.selected
	if _off_h < 0.1:
		_shown_off = cur_off


func _process(_d: float) -> void:
	if world == null or world.player == null or world.cm == null:
		return
	var p: Player = world.player
	var show: bool = world.third_person == 0 and not world.hud_hidden and not p.is_spectator() and world.spawn_ready and not p.dead
	rig.visible = show
	if _vm_pending > 0:
		_vm_pending -= 1
		_convert(rig)
	var fs := tan(deg_to_rad(world.camera.fov) * 0.5) / tan(deg_to_rad(35.0))   # Java hand FOV 70
	if absf(fs - _fov_scale) > 0.00001:
		_fov_scale = fs
		RenderingServer.global_shader_parameter_set("vm_fov_scale", fs)
	arm.visible = false
	item_root.visible = false
	off_root.visible = false
	if not show:
		return
	var held: ItemStack = _shown_main if _shown_main != null else p.inventory.held()
	var swing := 0.0
	var ptk := clampf(world.tick_accum / 0.05, 0.0, 1.0)
	if world.hand_swing > 0:
		swing = clampf((float(world.hand_swing_dur - world.hand_swing) + ptk) / float(world.hand_swing_dur), 0.0, 1.0)
	# equipped progress (Java 1 - lerp(oMainHandHeight, mainHandHeight)): -0.6 x it down (maps -1.2)
	var equip := 1.0 - lerpf(_main_h_old, _main_h, ptk)
	# view bobbing (Java bobView: translate(sin(b*pi)*bob*0.5, -|cos(b*pi)*bob|, 0), z/x rotations)
	var bob_t := Transform3D.IDENTITY
	if Settings.get_v("view_bobbing"):
		bob_t = bob_transform(p, clampf(world.tick_accum / 0.05, 0.0, 1.0))
	var light: int = world.cm.get_light(int(floor(p.pos.x)), int(floor(p.eye_pos().y)), int(floor(p.pos.z)))
	var lv := Vector2((light >> 4) / 15.0, (light & 15) / 15.0)
	_update_offhand(p, bob_t, lv)
	_update_map_marker(p)
	if held.is_empty():
		var g := sqrt(swing)
		var t := bob_t
		t = _tr(t, Vector3(-0.3 * sin(g * PI) + 0.64, 0.4 * sin(g * TAU) - 0.6 + equip * -0.6, -0.4 * sin(swing * PI) - 0.72))
		t = _rot(t, Vector3.UP, 45.0)
		t = _rot(t, Vector3.UP, sin(g * PI) * 70.0)
		t = _rot(t, Vector3.BACK, sin(swing * swing * PI) * -20.0)
		t = _tr(t, Vector3(-1.0, 3.6, 3.5))
		t = _rot(t, Vector3.BACK, 120.0)
		t = _rot(t, Vector3.RIGHT, 200.0)
		t = _rot(t, Vector3.UP, -135.0)
		t = _tr(t, Vector3(5.6, 0.0, 0.0))
		t = _tr(t, Vector3(-5, 2, 0) / 16.0)
		t = t * Transform3D(Basis.from_scale(Vector3(-1, -1, 1)), Vector3.ZERO)   # undo the rig builder's model flip
		arm.transform = t
		arm.visible = true
		for mi in _meshes:
			mi.set_instance_shader_parameter("light", lv)
		return
	_ensure_item(held)
	if Maps.map_id(held) >= 0:
		# Java renderTwoHandedMap: tilt from pitch, translate (0, 0.04 - tilt/2, -0.72), X -85 * tilt, scale 2 * 0.38
		var f := clampf(1.0 - p.pitch / 45.0 + 0.1, 0.0, 1.0)
		var tilt := -cos(f * PI) * 0.5 + 0.5
		var tm := bob_t
		tm = _tr(tm, Vector3(0, 0.04 + equip * -1.2 - tilt * 0.5, -0.72 - 0.4 * sin(sqrt(swing) * PI)))
		tm = _rot(tm, Vector3.RIGHT, tilt * -85.0 + sin(sqrt(swing) * PI) * 20.0)
		tm = tm * Transform3D(Basis.from_scale(Vector3.ONE * 0.76), Vector3.ZERO)
		item_root.transform = tm
		item_root.visible = true
		return
	var g2 := sqrt(swing)
	var ti := bob_t
	var ua := UseItem.anim(held) if p.using_slot == p.inventory.selected else ""
	if ua == "spyglass":
		return   # Java hides the hand while scoping
	if ua != "":
		# Java ItemInHandRenderer.renderArmWithItem while using an item (right arm, i = 1)
		var used: float = float(p.use_ticks) + float(world.tick_accum) / 0.05
		if ua == "eat" or ua == "drink":
			var dur := float(UseItem.duration(held))
			var rem: float = dur - used + 1.0
			var gq := clampf(rem / dur, 0.0, 1.0)
			if gq < 0.8:
				ti = _tr(ti, Vector3(0, absf(cos(rem / 4.0 * PI) * 0.1), 0))
			var hq := 1.0 - pow(gq, 27.0)
			ti = _tr(ti, Vector3(hq * 0.6, hq * -0.5, 0))
			ti = _rot(ti, Vector3.UP, hq * 90.0)
			ti = _rot(ti, Vector3.RIGHT, hq * 10.0)
			ti = _rot(ti, Vector3.BACK, hq * 30.0)
		ti = _tr(ti, Vector3(0.56, -0.52 + equip * -0.6, -0.72))
		if ua == "brush":
			# Java applyBrushTransform (right arm): a 10-tick sweep, X rotation -15 + 75 cos(h 2 pi)
			var rem_i: int = UseItem.duration(held) - p.use_ticks
			var gb := float(posmod(rem_i, 10)) - float(world.tick_accum) / 0.05 + 1.0
			var hb := 1.0 - gb / 10.0
			ti = _tr(ti, Vector3(-0.25, 0.22, 0.35))
			ti = _rot(ti, Vector3.RIGHT, -80.0)
			ti = _rot(ti, Vector3.UP, 90.0)
			ti = _rot(ti, Vector3.RIGHT, -15.0 + 75.0 * cos(hb * TAU))
		if ua == "bow" or ua == "crossbow" or ua == "spear":
			var fb := 0.0
			if ua == "bow":
				ti = _tr(ti, Vector3(-0.2785682, 0.18344387, 0.15731531))
				ti = _rot(ti, Vector3.RIGHT, -13.935)
				ti = _rot(ti, Vector3.UP, 35.3)
				ti = _rot(ti, Vector3.BACK, -9.785)
				fb = used / 20.0
				fb = minf(1.0, (fb * fb + fb * 2.0) / 3.0)
			elif ua == "crossbow":
				ti = _tr(ti, Vector3(-0.4785682, -0.094387, 0.05731531))
				ti = _rot(ti, Vector3.RIGHT, -11.935)
				ti = _rot(ti, Vector3.UP, 65.3)
				ti = _rot(ti, Vector3.BACK, -9.785)
				fb = minf(1.0, used / maxf(1.0, float(UseItem.charge_time(held))))
			else:
				ti = _tr(ti, Vector3(-0.5, 0.7, 0.1))
				ti = _rot(ti, Vector3.RIGHT, -55.0)
				ti = _rot(ti, Vector3.UP, 35.3)
				ti = _rot(ti, Vector3.BACK, -9.785)
				fb = minf(1.0, used / 10.0)
			if fb > 0.1:
				ti = _tr(ti, Vector3(0, sin((used - 0.1) * 1.3) * (fb - 0.1) * 0.004, 0))
			ti = _tr(ti, Vector3(0, 0, fb * (0.2 if ua == "spear" else 0.04)))
			ti = ti * Transform3D(Basis.from_scale(Vector3(1, 1, 1.0 + fb * 0.2)), Vector3.ZERO)
			ti = _rot(ti, Vector3.UP, -45.0)
	else:
		ti = _tr(ti, Vector3(-0.4 * sin(g2 * PI), 0.2 * sin(g2 * TAU), -0.2 * sin(swing * PI)))
		ti = _tr(ti, Vector3(0.56, -0.52 + equip * -0.6, -0.72))
		var s2 := sin(swing * swing * PI)
		ti = _rot(ti, Vector3.UP, 45.0 + s2 * -20.0)
		var h2 := sin(g2 * PI)
		ti = _rot(ti, Vector3.BACK, h2 * -20.0)
		ti = _rot(ti, Vector3.RIGHT, h2 * -80.0)
		ti = _rot(ti, Vector3.UP, -45.0)
	if not item_root.get_meta("special", false):
		# Java ItemTransform.apply: the context model's display.firstperson_righthand (translation / 16, rotationXYZ,
		# scale) - generated items (0, -90, 25), blocks (0, 45, 0) x 0.4, spears their in-hand model (-20, 90, -35) ...
		# Our extruded mesh is Java's ItemModelGenerator geometry (front = south face, u along +x), so the numbers are
		# used as they are.
		var d: Dictionary = item_root.get_meta("disp", {})
		var dt: Array = d.get("translation", [0, 0, 0])
		var dr: Array = d.get("rotation", [0, 0, 0])
		var ds: Array = d.get("scale", [1, 1, 1])
		ti = _tr(ti, Vector3(float(dt[0]), float(dt[1]), float(dt[2])) / 16.0)
		ti = _rot(ti, Vector3.RIGHT, float(dr[0]))
		ti = _rot(ti, Vector3.UP, float(dr[1]))
		ti = _rot(ti, Vector3.BACK, float(dr[2]))
		ti = ti * Transform3D(Basis.from_scale(Vector3(float(ds[0]), float(ds[1]), float(ds[2]))), Vector3.ZERO)
	item_root.transform = ti
	item_root.visible = true
	if item_root.get_meta("special", false):
		BERender.set_light(item_root, lv)
	for c in item_root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial:
			(c as MeshInstance3D).set_instance_shader_parameter("light", lv)


## Offhand item: Java renderArmWithItem for the off arm: applyItemArmTransform(-0.56, -0.52, -0.72) and the model's
## firstperson_lefthand display (shield: item/shield or item/shield_blocking while blocking).
## Java MapItemSavedData player decoration: position (world - centre) / 2^scale map pixels (inside +-63: the arrow, rotated
## by (yRot +- 8) * 16 / 360; outside within 320: the off-map dot at the edge; farther: the small off-limits dot;
## the Nether spins the arrow), drawn by MapRenderer at x / 2 + 64 on the 128 px map.
func _update_map_marker(p: Player) -> void:
	var dq := item_root.get_node_or_null("map_player") as MeshInstance3D
	if dq == null:
		return
	_update_map_decos(int(dq.get_meta("map_id", -1)))
	var md: Dictionary = (world.level.get("maps", {}) as Dictionary).get(str(dq.get_meta("map_id", -1)), {})
	if md.is_empty() or str(md.get("dim", "overworld")) != world.dimension:
		dq.visible = false
		return
	var sc := 1 << int(md.get("scale", 0))
	var fx := (p.pos.x - float(md["x"])) / sc
	var fz := (p.pos.z - float(md["z"])) / sc
	var spr := "map/decorations/player"
	var rot := 0
	if fx >= -63.0 and fz >= -63.0 and fx <= 63.0 and fz <= 63.0:
		if world.dimension == "the_nether":
			var i := int(world.day_time / 10)
			rot = ((i * i * 34187121 + i * 121) >> 15) & 15
		else:
			var yr: float = p.yaw
			var d0 := yr - 8.0 if yr < 0.0 else yr + 8.0
			rot = int(d0 * 16.0 / 360.0)
	elif absf(fx) < 320.0 and absf(fz) < 320.0:
		spr = "map/decorations/player_off_map"
	else:
		spr = "map/decorations/player_off_limits"
	var bx := clampi(int(fx * 2.0 + 0.5), -128, 127)
	var bz := clampi(int(fz * 2.0 + 0.5), -128, 127)
	if str(dq.get_meta("spr", "")) != spr:
		dq.set_meta("spr", spr)
		# the hand pass replaced the quad's material by its viewmodel shader (tex) - set whichever it has
		var dmat := dq.material_override
		if dmat is StandardMaterial3D:
			(dmat as StandardMaterial3D).albedo_texture = UiKit.sprite(spr)
		elif dmat is ShaderMaterial:
			(dmat as ShaderMaterial).set_shader_parameter("tex", UiKit.sprite(spr))
	dq.visible = true
	# map quad: 1 unit = 128 px, +x right, +y up on screen = map north (-z)
	dq.position = Vector3((bx / 2.0) / 128.0, -(bz / 2.0) / 128.0, 0.003)
	# MapRenderer draws the sprite's top towards +y of the map (south) and turns it by rot * 22.5 deg in that y-down
	# space: here (y = north) the quad is flipped on y and turned by the negated angle
	dq.rotation = Vector3(0.0, 0.0, -float(rot) * TAU / 16.0)
	dq.scale = Vector3(1.0, -1.0, 1.0)


## Banner / frame markers of the held map (Java MapRenderer: 8 x 8 map-pixel sprites at x / 2 + 64, rotated in 22.5 deg
## steps, later decorations nearer; a banner's name under it, scaled to fit 25 px, at most 6 px tall, on a 25 %
## black background).
func _update_map_decos(mid: int) -> void:
	var dn := item_root.get_node_or_null("map_decos") as Node3D
	if dn == null or mid < 0:
		return
	var rv := Maps.rev(world, mid)
	if int(dn.get_meta("rev", -1)) == rv:
		return
	dn.set_meta("rev", rv)
	for ch in dn.get_children():
		ch.queue_free()
	var k := 0
	for d in Maps.decorations(world, mid):
		k += 1
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE * (8.0 / 128.0)
		q.mesh = qm
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mm.cull_mode = BaseMaterial3D.CULL_DISABLED
		mm.albedo_texture = UiKit.sprite(str(d[0]))
		q.material_override = mm
		q.position = Vector3((float(d[1]) / 2.0) / 128.0, -(float(d[2]) / 2.0) / 128.0, 0.0015 + 0.0001 * k)
		q.rotation = Vector3(0.0, 0.0, -float(d[3]) * TAU / 16.0)
		q.scale = Vector3(1.0, -1.0, 1.0)
		dn.add_child(q)
		var nm := str(d[4])
		if nm != "":
			# the name under the marker: scaled to 25 px wide at most, 6 px tall at most (Java f7)
			var lt := Maps.label_texture(nm)
			var tw := float(lt.get_width() - 1)
			var f7 := clampf(25.0 / maxf(tw, 1.0), 0.0, 6.0 / 9.0)
			var lq := MeshInstance3D.new()
			var lm := QuadMesh.new()
			lm.size = Vector2(float(lt.get_width()), float(lt.get_height())) * f7 / 128.0
			lq.mesh = lm
			var lmat := ShaderMaterial.new()
			lmat.shader = load("res://shaders/map_label.gdshader")
			lmat.set_shader_parameter("tex", lt)
			lq.material_override = lmat
			lq.position = Vector3((float(d[1]) / 2.0) / 128.0, -(float(d[2]) / 2.0 + 4.0 + float(lt.get_height()) * f7 / 2.0) / 128.0, 0.0025 + 0.0001 * k)
			dn.add_child(lq)
	_vm_pending = maxi(_vm_pending, 2)   # the new quads take the hand projection on the next conversion pass


func _update_offhand(p: Player, bob_t: Transform3D, lv: Vector2) -> void:
	var off: ItemStack = _shown_off if _shown_off != null else p.inventory.get_slot(Inventory.OFFHAND)
	if off.is_empty():
		return
	var using := p.using_slot == Inventory.OFFHAND
	var key := off.item * 10 + (1 if using else 0) + (hash(str(off.components)) % 997) * 100000
	if key != _off_key:
		_off_key = key
		_vm_pending = 3
		for c in off_root.get_children():
			c.queue_free()
		off_root.set_meta("mode", "")
		var spec := BERender.item_node(off.item, "firstperson_lefthand", {"patterns": Banners.layers(off), "base_color": off.components.get("minecraft:base_color")}, using)
		var pb: int = Res.items.place_block[off.item]
		var bm: ArrayMesh = EntityRenderer.item_block_mesh(off.item) if spec == null and pb > 0 and not Res.items.model_ref[off.item].begins_with("item/") else null
		if spec != null:
			off_root.add_child(spec)
			off_root.set_meta("mode", "special")
		elif bm != null:
			var bmi := MeshInstance3D.new()
			bmi.mesh = bm
			bmi.position = Vector3(0, -0.5, 0)
			off_root.add_child(bmi)
			off_root.set_meta("mode", "block")
		else:
			var tex := ItemIcons.icon(off.item)
			if tex != null:
				var emi := MeshInstance3D.new()
				emi.mesh = extruded(tex)
				emi.material_override = EntityRenderer.flat_item_material(tex)
				off_root.add_child(emi)
				off_root.set_meta("mode", "item")
				if Glint.has_glint(off):
					var og := MeshInstance3D.new()
					og.mesh = emi.mesh
					og.material_override = Glint.material_3d(tex, off)
					off_root.add_child(og)
	var mode := str(off_root.get_meta("mode", ""))
	if mode == "":
		return
	var off_equip := 1.0 - lerpf(_off_h_old, _off_h, clampf(world.tick_accum / 0.05, 0.0, 1.0))
	var t := _tr(bob_t, Vector3(-0.56, -0.52 + off_equip * -0.6, -0.72))
	if mode == "block":
		t = _rot(t, Vector3.UP, -225.0)   # block/block firstperson_lefthand Y 225, mirrored for the left hand
		t = t * Transform3D(Basis.from_scale(Vector3.ONE * 0.4), Vector3.ZERO)
	elif mode == "item":
		# generated firstperson_lefthand (0, 90, -25) / (1.13, 3.2, 1.13), mirrored for the left hand -> (0, -90, 25) at x -1.13;
		# Y +90 instead of -90: the same extrusion mirror as the main hand
		t = _tr(t, Vector3(-1.13, 3.2, 1.13) / 16.0)
		t = _rot(t, Vector3.UP, 90.0)
		t = _rot(t, Vector3.BACK, 25.0)
		t = t * Transform3D(Basis.from_scale(Vector3.ONE * 0.68), Vector3.ZERO)
	off_root.transform = t
	off_root.visible = true
	BERender.set_light(off_root, lv)


## Java items/bow.json / crossbow.json: pulling sprites by use time, loaded crossbow sprite.
func _pull_sprite(s: ItemStack) -> String:
	var p: Player = world.player
	var n := s.name()
	if n == "crossbow" and (s.components.get("minecraft:charged_projectiles", []) as Array).size() > 0:
		return "item/crossbow_arrow"
	if p.using_slot != p.inventory.selected or (n != "bow" and n != "crossbow"):
		return ""
	if n == "bow":
		var sec := p.use_ticks * 0.05
		return "item/bow_pulling_%d" % (0 if sec < 0.65 else (1 if sec < 0.9 else 2))
	var pull := float(p.use_ticks) / maxf(1.0, float(UseItem.charge_time(s)))
	return "item/crossbow_pulling_%d" % (0 if pull < 0.58 else (1 if pull < 1.0 else 2))


var _pull_tex: Dictionary = {}


func _ensure_item(s: ItemStack) -> void:
	var pull := _pull_sprite(s)
	var using_main: bool = world.player.using_slot == world.player.inventory.selected
	var key := s.item * 100000 + maxi(Maps.map_id(s), 0) + (hash(pull) % 1000 if pull != "" else 0) * 7 + (50000 if using_main and s.name() == "shield" else 0) + (hash(str(s.components)) % 997) * 3
	if pull != "" and not _pull_tex.has(pull):
		var pim := Res.load_image(pull)
		_pull_tex[pull] = ImageTexture.create_from_image(pim) if pim != null else null
	if key == _item_key:
		return
	_item_key = key
	_vm_pending = 3
	for c in item_root.get_children():
		c.queue_free()
	var pb: int = Res.items.place_block[s.item]
	if pb > 0 and not Res.items.model_ref[s.item].begins_with("item/"):
		# the item's model (wall / fence / shelf inventory models; a wall's default state has no geometry of its own, so
		# walls fell through to the extruded GUI icon - an edge-on striped sliver in the hand)
		var mesh := EntityRenderer.item_block_mesh(s.item)
		if mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = Vector3(0, -0.5, 0)
			item_root.add_child(mi)
			item_root.set_meta("block", true)
			item_root.set_meta("special", false)
			item_root.set_meta("disp", ItemIcons.item_display(s.item, "firstperson_righthand"))
			return
	item_root.set_meta("block", false)
	item_root.set_meta("special", false)
	item_root.set_meta("disp", ItemIcons.item_display(s.item, "firstperson_righthand"))
	var spec := BERender.item_node(s.item, "firstperson_righthand", {"patterns": Banners.layers(s), "base_color": s.components.get("minecraft:base_color")}, using_main)
	if spec != null:
		item_root.add_child(spec)
		item_root.set_meta("special", true)
		return
	var mid := Maps.map_id(s)
	if mid >= 0:
		for layer in [["map/map_background", 142.0 / 128.0, -0.002], ["", 1.0, 0.0]]:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2.ONE * float(layer[1])
			q.mesh = qm
			q.position.z = float(layer[2])
			var mm := StandardMaterial3D.new()
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mm.albedo_texture = UiKit.sprite(str(layer[0])) if str(layer[0]) != "" else Maps.texture(world, mid)
			q.material_override = mm
			item_root.add_child(q)
		# the holder's decoration (MapRenderer: an 8 x 8 map-pixel sprite quad over the map, rotated in 22.5 deg steps)
		var dq := MeshInstance3D.new()
		dq.name = "map_player"
		var dqm := QuadMesh.new()
		dqm.size = Vector2.ONE * (8.0 / 128.0)
		dq.mesh = dqm
		var dmm := StandardMaterial3D.new()
		dmm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		dmm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		dmm.cull_mode = BaseMaterial3D.CULL_DISABLED
		dmm.albedo_texture = UiKit.sprite("map/decorations/player")
		dq.material_override = dmm
		dq.set_meta("map_id", mid)
		item_root.add_child(dq)
		var dn := Node3D.new()
		dn.name = "map_decos"
		dn.set_meta("rev", -1)
		item_root.add_child(dn)
		return
	# the model for this context (spears: item/<tier>_spear_in_hand; a drawn bow: item/bow_pulling_N)
	var ref := pull if pull != "" else ItemRegistry.ctx_model(s.name(), "firstperson_righthand")
	if ref == "":
		ref = Res.items.model_ref[s.item]
	item_root.set_meta("disp", ItemIcons.model_display(ref, "firstperson_righthand"))
	var em: Array = ItemIcons.extruded_model(ref)
	var tex: Texture2D = em[1] if em.size() == 2 else ItemIcons.icon(s.item)
	if tex == null:
		return
	var mi2 := MeshInstance3D.new()
	mi2.mesh = em[0] if em.size() == 2 else extruded(tex)
	mi2.material_override = EntityRenderer.flat_item_material(tex)   # (translucent sprites blend: stained glass panes)
	item_root.add_child(mi2)
	if Glint.has_glint(s):
		var g2 := MeshInstance3D.new()   # enchantment glint over the item's own geometry
		g2.mesh = mi2.mesh
		g2.material_override = Glint.material_3d(tex, s)
		item_root.add_child(g2)


## Java ItemModelGenerator: front/back quads + one side quad per exposed pixel edge, 1/16 thick, centred.
static func extruded(tex: Texture2D) -> ArrayMesh:
	var img := tex.get_image()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := -0.5 / 16.0
	var z1 := 0.5 / 16.0
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, shade: float):
		var pts := [a, b, c, d]
		var uvs := [ua, ub, uc, ud]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(shade, shade, shade))
			st.set_uv(uvs[idx])
			st.add_vertex(pts[idx])
	quad.call(Vector3(-0.5, 0.5, z1), Vector3(0.5, 0.5, z1), Vector3(0.5, -0.5, z1), Vector3(-0.5, -0.5, z1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), 1.0)
	quad.call(Vector3(0.5, 0.5, z0), Vector3(-0.5, 0.5, z0), Vector3(-0.5, -0.5, z0), Vector3(0.5, -0.5, z0), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), 0.8)
	if img != null:
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var solid := func(x: int, y: int) -> bool:
			return x >= 0 and y >= 0 and x < w and y < h and img.get_pixel(x, y).a > 0.1
		for y in h:
			for x in w:
				if not solid.call(x, y):
					continue
				var x0 := -0.5 + float(x) / w
				var x1 := -0.5 + float(x + 1) / w
				var y0 := 0.5 - float(y) / h
				var y1 := 0.5 - float(y + 1) / h
				var uv := Vector2((x + 0.5) / w, (y + 0.5) / h)
				if not solid.call(x, y - 1):
					quad.call(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), uv, uv, uv, uv, 1.0)
				if not solid.call(x, y + 1):
					quad.call(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), uv, uv, uv, uv, 0.5)
				if not solid.call(x - 1, y):
					quad.call(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), uv, uv, uv, uv, 0.6)
				if not solid.call(x + 1, y):
					quad.call(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), uv, uv, uv, uv, 0.6)
	return st.commit()
