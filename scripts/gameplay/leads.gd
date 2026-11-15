## Leads — Java Leashable: use a lead on a leashable mob (the wiki's list below) to tie it to the player;
## right-click a fence while holding mobs to tie them to a knot there; right-click the fence again (or the mob) to
## untie (the lead drops). Physics (Java Leashable.tickLeash / legacyElasticRangeLeashBehaviour): beyond 6 blocks the
## mob is pulled toward the holder, beyond 12 the lead snaps (16 for a happy ghast; wiki: Lead); mobs within range walk
## toward the holder.
## Rendering: Java LeashKnot/EntityRenderer.renderLeash - 24 segments, alternating brown shades, sagging curve.
## The tie is saved in the mob's data ("leash": "player" or [x, y, z] fence).
## Boats take leads too (wiki Boat: "Leads can be attached to boats"; a lead does nothing while a player rides it).
class_name Leads
extends RefCounted

# wiki: Lead - the mobs a lead can be used on (wolves / nautiluses / zombie nautiluses only while not hostile)
const LEASHABLE := ["allay", "armadillo", "axolotl", "bee", "camel", "camel_husk", "cat", "chicken", "copper_golem", "cow",
	"dolphin", "donkey", "fox", "frog", "glow_squid", "goat", "happy_ghast", "hoglin", "horse", "iron_golem", "llama",
	"mooshroom", "mule", "nautilus", "ocelot", "parrot", "pig", "polar_bear", "rabbit", "sheep", "skeleton_horse", "sniffer",
	"snow_golem", "squid", "strider", "sulfur_cube", "trader_llama", "wolf", "zoglin", "zombie_horse", "zombie_nautilus"]

static var _mesh: MeshInstance3D = null


static func leashable(e) -> bool:
	if e.kind == "boat" and not e.dead:
		return true
	if e.kind != "mob" or e.dead or not (e.id in LEASHABLE):
		return false
	return not (e.id in ["wolf", "nautilus", "zombie_nautilus"] and e.angry)


static func holder_pos(em, e) -> Variant:
	var l = e.data.get("leash")
	if l == null:
		return null
	if str(l) == "player":
		var p: Player = em.world.player
		var yr := deg_to_rad(p.yaw)
		return p.pos + Vector3(-cos(yr) * 0.36, p.eye_height() - 0.55, -sin(yr) * 0.36) + p.look_dir() * 0.3
	if l is Array and (l as Array).size() == 3:
		return Vector3(l[0], l[1], l[2]) + Vector3(0.5, 0.5, 0.5)
	return null


static func _drop(em, e) -> void:
	e.data.erase("leash")
	em.spawn_item(e.pos + Vector3(0, e.h * 0.5, 0), ItemStack.named("lead", 1))


## Right-click on a mob. True when handled.
static func interact(em, e, p: Player, held: ItemStack) -> bool:
	if e.data.has("leash"):
		if str(e.data["leash"]) == "player":
			_drop(em, e)
			Audio.play("item.lead.untied", e.pos, "Neutral")
			return true
		return false
	if not held.is_empty() and held.name() == "lead" and leashable(e):
		e.data["leash"] = "player"
		e.persistent = true
		if not p.is_creative():
			p.inventory.consume_held()
		Audio.play("item.lead.tied", e.pos, "Neutral")
		em.world.inv_changed()
		return true
	return false


## Right-click on a fence: tie the player's mobs to it, or untie the mobs tied there.
static func use_on_fence(world, pos: Vector3i) -> bool:
	var em = world.entities
	var p: Player = world.player
	var tied := false
	for e in em.ents:
		if (e.kind == "mob" or e.kind == "boat") and not e.dead and str(e.data.get("leash", "")) == "player" and e.pos.distance_to(p.pos) < 7.0:
			e.data["leash"] = [pos.x, pos.y, pos.z]
			tied = true
	if tied:
		Audio.play("entity.leash_knot.place", Vector3(pos), "Neutral")
		return true
	var freed := false
	for e in em.ents:
		var l = e.data.get("leash")
		if l is Array and Vector3i(l[0], l[1], l[2]) == pos:
			_drop(em, e)
			freed = true
	if freed:
		Audio.play("entity.leash_knot.break", Vector3(pos), "Neutral")
	return freed


static func tick(em) -> void:
	var b := Res.blocks
	for e in em.ents:
		if (e.kind != "mob" and e.kind != "boat") or not e.data.has("leash"):
			continue
		if e.dead:
			_drop(em, e)
			continue
		var l = e.data["leash"]
		if l is Array:
			var fs: int = em.world.state_at(int(l[0]), int(l[1]), int(l[2]))
			if fs <= 0 or not b.name_of(fs).ends_with("_fence"):
				_drop(em, e)
				Audio.play("entity.leash_knot.break", e.pos, "Neutral")
				continue
		var hp = holder_pos(em, e)
		if hp == null:
			continue
		var to: Vector3 = (hp as Vector3) - (e.pos + Vector3(0, e.h * 0.5, 0))
		var d := to.length()
		# wiki: Lead - a lead stretches at most 12 blocks (16 for a happy ghast) before it snaps
		if d > (16.0 if e.id == "happy_ghast" else 12.0):
			_drop(em, e)
			Audio.play("entity.leash_knot.break", e.pos, "Neutral")
			continue
		if e.kind == "boat" and em.world.player.vehicle == e:
			continue   # (wiki Boat: the lead does nothing while a player rides)
		var free := 10.0 if e.id == "happy_ghast" else 6.0   # wiki: Lead - happy ghasts roam freely within 10 blocks
		if d > free:
			var n := to / d
			e.vel += Vector3(n.x * absf(n.x), n.y * absf(n.y), n.z * absf(n.z)) * 0.4 * ((d - free) / 4.0 + 0.25)
		elif d > 2.0 and str(l) == "player":
			e.target_pos = hp
			e.has_target = true


## Per frame: one ribbon mesh for all leads.
static func render(em) -> void:
	var any := false
	for e in em.ents:
		if (e.kind == "mob" or e.kind == "boat") and e.data.has("leash") and not e.dead:
			any = true
			break
	if not any:
		if _mesh != null and is_instance_valid(_mesh):
			_mesh.visible = false
		return
	if _mesh == null or not is_instance_valid(_mesh):
		_mesh = MeshInstance3D.new()
		_mesh.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh.material_override = m
		em.add_child(_mesh)
	_mesh.visible = true
	var im: ImmediateMesh = _mesh.mesh
	im.clear_surfaces()
	var drawn := 0
	for e0 in em.ents:
		if (e0.kind == "mob" or e0.kind == "boat") and e0.data.has("leash") and not e0.dead and holder_pos(em, e0) != null:
			drawn += 1
	if drawn == 0:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in em.ents:
		if (e.kind != "mob" and e.kind != "boat") or not e.data.has("leash") or e.dead:
			continue
		var hp = holder_pos(em, e)
		if hp == null:
			continue
		var a: Vector3 = em.world.vis(e.pos + Vector3(0, e.h * 0.7, 0))
		var bpos: Vector3 = em.world.vis(hp)
		var dv := bpos - a
		var side := dv.cross(Vector3.UP).normalized() * 0.025
		if side.length() < 0.001:
			side = Vector3(0.025, 0, 0)
		var prev := a
		for i in range(1, 25):
			var t := i / 24.0
			var q := a.lerp(bpos, t)
			# Java renderLeash: y follows t*t (hanging from the higher end) - approximated as a parabola sag
			q.y -= sin(t * PI) * 0.15 * dv.length() / 6.0 + 0.0
			var c := Color(0.5, 0.4, 0.3) if i % 2 == 0 else Color(0.35, 0.28, 0.21)
			for v in [prev - side, prev + side, q + side, prev - side, q + side, q - side,
					prev - Vector3(0, 0.025, 0), prev + Vector3(0, 0.025, 0), q + Vector3(0, 0.025, 0), prev - Vector3(0, 0.025, 0), q + Vector3(0, 0.025, 0), q - Vector3(0, 0.025, 0)]:
				im.surface_set_color(c)
				im.surface_add_vertex(v)
			prev = q
	im.surface_end()
