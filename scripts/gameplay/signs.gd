## Signs (Java SignBlockEntity): front/back text (4 lines), dye color, glowing text (glow ink sac), waxing
## (honeycomb). Placing a sign opens the editor; right-clicking an unwaxed sign edits the side facing the player.
## Text is drawn with Label3D nodes using the GUI font (Java SignRenderer: 1/96-block text scale, 10-unit line
## height), tinted by the light at the sign unless glowing. Standing (rotation 0-15), wall (facing), hanging and
## wall-hanging signs are supported. APPROXIMATE: board offsets measured from the Java models by eye.
class_name Signs
extends RefCounted

const DYES := {"white": Color(1, 1, 1), "orange": Color(1.0, 0.5, 0.1), "magenta": Color(0.8, 0.3, 0.8), "light_blue": Color(0.4, 0.7, 1.0),
	"yellow": Color(1.0, 1.0, 0.2), "lime": Color(0.5, 0.9, 0.2), "pink": Color(1.0, 0.6, 0.75), "gray": Color(0.3, 0.3, 0.3),
	"light_gray": Color(0.6, 0.6, 0.6), "cyan": Color(0.1, 0.6, 0.6), "purple": Color(0.5, 0.2, 0.7), "blue": Color(0.2, 0.3, 0.9),
	"brown": Color(0.5, 0.3, 0.15), "green": Color(0.35, 0.5, 0.1), "red": Color(0.75, 0.15, 0.15), "black": Color(0, 0, 0)}

static var _labels: Dictionary = {}   # Vector3i -> Node3D (main thread)
static var _dirty := true


static func is_sign(nm: String) -> bool:
	return nm.ends_with("_sign")


static func new_data() -> Dictionary:
	return {"id": "sign", "front": ["", "", "", ""], "back": ["", "", "", ""], "front_color": "black", "back_color": "black",
		"front_glow": false, "back_glow": false, "waxed": false}


static func data(world, p: Vector3i) -> Dictionary:
	var d := BlockEntities.get_data(world, p)
	if d.is_empty() or str(d.get("id", "")) != "sign":
		d = new_data()
		BlockEntities.set_data(world, p, d)
	return d


static func on_placed(world, p: Vector3i) -> void:
	data(world, p)
	if world.player != null and not world.autoplay.has("nettest"):
		open_editor(world, p, true)


## The side of the sign the player is looking at (Java SignBlockEntity.isFacingFrontText).
static func facing_front(world, p: Vector3i) -> bool:
	var yaw := sign_yaw(Res.blocks, world.state_at(p.x, p.y, p.z))
	var fwd := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
	var to_player: Vector3 = world.player.pos - (Vector3(p) + Vector3(0.5, 0.5, 0.5))
	return fwd.dot(Vector3(to_player.x, 0, to_player.z)) >= 0.0


static func open_editor(world, p: Vector3i, front: bool) -> void:
	var s = load("res://scripts/ui/sign_screen.gd").new()
	s.world = world
	s.pos = p
	s.front = front
	world.open_screen(s)


## Right-click: dyes / glow ink / ink sac / honeycomb apply to the facing side; otherwise edit (unless waxed).
static func use(world, p: Vector3i, pl: Player) -> bool:
	var d := data(world, p)
	var side := "front" if facing_front(world, p) else "back"
	var held := pl.inventory.held()
	var nm := "" if held.is_empty() else held.name()
	if bool(d.get("waxed", false)):
		Audio.play("block.sign.waxed_interact_fail", Vector3(p), "Blocks")
		return true
	var changed := false
	if nm.ends_with("_dye") and DYES.has(nm.trim_suffix("_dye")):
		d[side + "_color"] = nm.trim_suffix("_dye")
		changed = true
	elif nm == "glow_ink_sac":
		d[side + "_glow"] = true
		changed = true
	elif nm == "ink_sac":
		d[side + "_glow"] = false
		changed = true
	elif nm == "honeycomb":
		d["waxed"] = true
		Audio.play("item.honeycomb.wax_on", Vector3(p), "Blocks")
		changed = true
	if changed:
		if not pl.is_creative():
			pl.inventory.consume_held()
		BlockEntities.set_data(world, p, d)
		_dirty = true
		return true
	open_editor(world, p, side == "front")
	return true


## Java yaw (degrees, 0 = text faces south/+z) of a sign state.
static func sign_yaw(b: BlockRegistry, st: int) -> float:
	if st <= 0:
		return 0.0
	if b.has_prop(st, "rotation"):
		return float(int(b.get_prop(st, "rotation"))) * 22.5
	if b.has_prop(st, "facing"):
		return {"south": 0.0, "west": 90.0, "north": 180.0, "east": 270.0}.get(str(b.get_prop(st, "facing")), 0.0)
	return 0.0


static func mark_dirty() -> void:
	_dirty = true


## Per frame (main thread): create/update/remove the Label3D pairs for signs in loaded chunks.
static func render(world) -> void:
	if world.game_time % 20 == 0:
		_dirty = true
	var b := Res.blocks
	if _dirty:
		_dirty = false
		var seen := {}
		for c in BlockEntities.chunks_with(world, ["sign"]):
			var ch: Chunk = c
			for k in ch.block_entities:
				var d: Dictionary = ch.block_entities[k]
				if str(d.get("id", "")) != "sign":
					continue
				var p := Vector3i(ch.cx * 16 + (k & 15), (k >> 8) + Coords.MIN_Y, ch.cz * 16 + ((k >> 4) & 15))
				var st: int = world.state_at(p.x, p.y, p.z)
				if st <= 0 or not is_sign(b.name_of(st)):
					continue
				seen[p] = true
				var node: Node3D = _labels.get(p)
				if node == null or not is_instance_valid(node):
					node = _make(world, b, st)
					_labels[p] = node
				_fill(node, d)
		for p in _labels.keys():
			if not seen.has(p):
				if is_instance_valid(_labels[p]):
					(_labels[p] as Node).queue_free()
				_labels.erase(p)
	for p in _labels:
		var node2: Node3D = _labels[p]
		if not is_instance_valid(node2):
			continue
		node2.position = world.vis(Vector3(p) + Vector3(0.5, 0.0, 0.5))
		var l: int = world.cm.get_light(p.x, p.y, p.z)
		var sky := float(l >> 4) / 15.0 * clampf(world.sky_darken(), 0.2, 1.0)
		var v := maxf(sky, float(l & 15) / 15.0)
		node2.set_meta("light", 0.15 + 0.85 * v * v)
		for side in ["front", "back"]:
			var lab: Label3D = node2.get_node_or_null(side)
			if lab != null:
				var base: Color = lab.get_meta("base", Color.BLACK)
				var lit: float = 1.0 if lab.get_meta("glow", false) else float(node2.get_meta("light", 1.0))
				lab.modulate = Color(base.r * lit, base.g * lit, base.b * lit, 1.0)


static func _make(world, b: BlockRegistry, st: int) -> Node3D:
	var nm := b.name_of(st)
	var node := Node3D.new()
	node.rotation.y = deg_to_rad(sign_yaw(b, st))
	var hanging := nm.ends_with("hanging_sign")
	var wall := nm.contains("_wall_")
	var y := 0.0
	var z := 0.0
	if hanging:
		y = 0.32
		z = 1.0 / 16.0 + 0.002 if not wall else 1.0 / 16.0 + 0.002
	elif wall:
		y = 0.53
		z = -0.5 + 2.0 / 16.0 + 0.002
	else:
		y = 0.83
		z = 1.0 / 24.0 + 0.002
	for side in ["front", "back"]:
		var lab := Label3D.new()
		lab.name = side
		lab.font = UiKit.font()
		lab.font_size = 8
		lab.outline_size = 0
		lab.pixel_size = 1.0 / 96.0 * (0.9 if hanging else 1.0)
		lab.line_spacing = 2.0
		lab.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		lab.double_sided = false
		lab.position = Vector3(0, y, z if side == "front" else -z if not wall else z - 0.004)
		if side == "back":
			lab.rotation.y = PI
			if wall and not hanging:
				lab.visible = false
		node.add_child(lab)
	world.add_child(node)
	return node


static func _fill(node: Node3D, d: Dictionary) -> void:
	for side in ["front", "back"]:
		var lab: Label3D = node.get_node_or_null(side)
		if lab == null:
			continue
		var lines: Array = d.get(side, ["", "", "", ""])
		var txt := ""
		for i in 4:
			txt += (str(lines[i]) if i < lines.size() else "") + ("\n" if i < 3 else "")
		lab.text = txt
		var col: Color = DYES.get(str(d.get(side + "_color", "black")), Color.BLACK)
		var glow: bool = d.get(side + "_glow", false)
		lab.set_meta("base", col if not (glow and str(d.get(side + "_color", "black")) == "black") else Color(0.94, 0.94, 0.86))
		lab.set_meta("glow", glow)
		lab.outline_size = 2 if glow else 0
		lab.outline_modulate = col.darkened(0.6) if glow else Color(0, 0, 0, 0)


static func clear() -> void:
	for p in _labels:
		if is_instance_valid(_labels[p]):
			(_labels[p] as Node).queue_free()
	_labels.clear()
	_dirty = true
