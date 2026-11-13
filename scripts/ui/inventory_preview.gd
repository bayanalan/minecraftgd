class_name InventoryPreview
extends RefCounted
## The inventory's player preview (Java InventoryScreen.renderEntityInInventoryFollowsMouse) as ONE SubViewport for the
## whole session: built and rendered once while the world loads (warm()), then attached to each inventory screen and
## detached when it closes. A new SubViewport per opening cost ~25 ms on the first open (a Forward+ render target and its
## pipelines) and allocated buffers on every later one.

static var cont: SubViewportContainer
static var vp: SubViewport
static var rig: Node3D


static func _build() -> void:
	cont = SubViewportContainer.new()
	cont.stretch = true
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	cont.add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 72.0 / 30.0          # Java renders the entity at 30 GUI px per block in the 51x72 box
	cam.position = Vector3(0, 1.0, 5)
	vp.add_child(cam)
	rig = EntityRenderer.build_rig({"tex": "entity/player/wide/steve", "tex_size": [64, 64], "parts": MobRegistry.PLAYER})
	EntityRenderer.apply_skin_parts(rig)
	vp.add_child(rig)


static func ensure() -> void:
	if cont == null or not is_instance_valid(cont):
		_build()


## World loading: render the preview once off screen (compiles its pipelines, allocates its buffers), then detach.
static func warm(host: Node) -> void:
	ensure()
	detach()
	cont.position = Vector2(-4096, -4096)
	cont.size = Vector2(51, 72)
	host.add_child(cont)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if is_instance_valid(cont) and cont.get_parent() == host:
		detach()


static func attach(parent: Node) -> void:
	ensure()
	detach()
	parent.add_child(cont)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


static func detach() -> void:
	if cont != null and is_instance_valid(cont):
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var p := cont.get_parent()
		if p != null:
			p.remove_child(cont)


## Java InventoryScreen.renderEntityInInventoryFollowsMouse: f = atan((centre - mouse) / 40) per axis; the body turns
## f.x * 20 degrees, the head another f.x * 20 (yHeadRot = 180 + f.x * 40) and pitches f.y * 20 toward the mouse.
## Positions in GUI pixels. Facing the camera = rotation.y PI (the rig front is -z).
static func follow_mouse(mouse: Vector2, centre: Vector2) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var fx := atan((mouse.x - centre.x) / 40.0)
	var fy := atan((mouse.y - centre.y) / 40.0)
	rig.rotation = Vector3(0.0, PI + deg_to_rad(fx * 20.0), 0.0)
	var model: Node = rig.get_node_or_null("model")
	if model == null:
		return
	for c in model.get_children():
		if c.name == "head" or c.name == "hat":
			c.rotation = Vector3(-deg_to_rad(fy * 20.0), deg_to_rad(fx * 20.0), 0.0)


## World exit.
static func free_shared() -> void:
	if cont != null and is_instance_valid(cont):
		detach()
		cont.free()
	cont = null
	vp = null
	rig = null
