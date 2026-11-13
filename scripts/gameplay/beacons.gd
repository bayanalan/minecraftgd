## Beacons (Java BeaconBlockEntity): every 80 ticks the pyramid under the beacon is measured (levels 1-4, every
## block of each square layer in #beacon_base_blocks), the beam needs a clear column (blocks with light dampening 15
## stop it, bedrock does not), and the selected effects are given to players within levels*10+10 blocks
## horizontally (whole world height) for (9 + 2*levels) s; level 4 adds the secondary (regeneration, or the primary
## at amplifier II). Payment: one item of #beacon_payment_items. Beam: rotating emissive column textured with the
## installed entity/beacon_beam.png. APPROXIMATE: beam is not tinted by stained glass.
## Composter (Java ComposterBlock): compost chances per item, level 0-7, ready (8) after 20 ticks, bone meal out.
class_name Beacons
extends RefCounted

const TIERS := [["speed", "haste"], ["resistance", "jump_boost"], ["strength"], ["regeneration"]]
const COMPOST := {"dried_kelp_block": 0.5, "tall_grass": 0.5, "flowering_azalea_leaves": 0.5, "cactus": 0.5, "sugar_cane": 0.5,
	"vine": 0.5, "nether_sprouts": 0.5, "weeping_vines": 0.5, "twisting_vines": 0.5, "melon_slice": 0.5, "glow_lichen": 0.5,
	"apple": 0.65, "beetroot": 0.65, "carrot": 0.65, "cocoa_beans": 0.65, "potato": 0.65, "wheat": 0.65, "lily_pad": 0.65,
	"melon": 0.65, "pumpkin": 0.65, "carved_pumpkin": 0.65, "brown_mushroom": 0.65, "red_mushroom": 0.65, "nether_wart": 0.65,
	"sea_pickle": 0.65, "shroomlight": 0.65, "spore_blossom": 0.65, "big_dripleaf": 0.65, "moss_block": 0.65, "fern": 0.65,
	"large_fern": 0.65, "crimson_fungus": 0.65, "warped_fungus": 0.65, "crimson_roots": 0.65, "warped_roots": 0.65,
	"baked_potato": 0.85, "bread": 0.85, "cookie": 0.85, "hay_block": 0.85, "red_mushroom_block": 0.85,
	"brown_mushroom_block": 0.85, "mushroom_stem": 0.85, "nether_wart_block": 0.85, "warped_wart_block": 0.85,
	"flowering_azalea": 0.85, "torchflower": 0.85, "pitcher_plant": 0.85, "cake": 1.0, "pumpkin_pie": 1.0,
	"beetroot_seeds": 0.3, "dried_kelp": 0.3, "short_grass": 0.3, "kelp": 0.3, "melon_seeds": 0.3, "pumpkin_seeds": 0.3,
	"wheat_seeds": 0.3, "sweet_berries": 0.3, "glow_berries": 0.3, "seagrass": 0.3, "small_dripleaf": 0.3,
	"hanging_roots": 0.3, "mangrove_roots": 0.3, "moss_carpet": 0.3, "pitcher_pod": 0.3, "torchflower_seeds": 0.3,
	"pink_petals": 0.3, "azalea": 0.65}

static var active: Dictionary = {}     # Vector3i -> levels (main thread)
static var _beams: Dictionary = {}     # Vector3i -> MeshInstance3D


static func compost_chance(nm: String) -> float:
	if COMPOST.has(nm):
		return COMPOST[nm]
	if nm.ends_with("_leaves") or nm.ends_with("_sapling") or nm.ends_with("_propagule"):
		return 0.3
	if Tags.has_block("flowers", nm) or Tags.has_block("small_flowers", nm):
		return 0.65
	return 0.0


## Right-click on a composter. Returns true when handled.
static func use_composter(world, p: Vector3i, st: int, pl: Player) -> bool:
	var b := Res.blocks
	var lvl := int(b.get_prop(st, "level"))
	if lvl >= 8:
		world.set_block(p.x, p.y, p.z, b.with_prop(st, "level", "0"))
		world.entities.spawn_item(Vector3(p) + Vector3(0.5, 1.1, 0.5), ItemStack.named("bone_meal", 1))
		Audio.play("block.composter.empty", Vector3(p), "Blocks")
		return true
	var held := pl.inventory.held()
	if held.is_empty() or lvl >= 7:
		return false
	var ch := compost_chance(held.name())
	if ch <= 0.0:
		return false
	if not pl.is_creative():
		pl.inventory.consume_held()
	if (lvl == 0 and ch > 0.0) or randf() < ch:
		lvl += 1
		world.set_block(p.x, p.y, p.z, b.with_prop(st, "level", str(lvl)))
		Audio.play("block.composter.fill_success", Vector3(p), "Blocks")
		if lvl == 7:
			BlockUpdates.schedule(world, p, 20)
	else:
		Audio.play("block.composter.fill", Vector3(p), "Blocks")
	return true


static func levels_at(world, p: Vector3i) -> int:
	var lv := 0
	for i in range(1, 5):
		var y := p.y - i
		if y < Coords.MIN_Y:
			break
		for x in range(p.x - i, p.x + i + 1):
			for z in range(p.z - i, p.z + i + 1):
				var st: int = world.state_at(x, y, z)
				if st <= 0 or not Tags.has_block("beacon_base_blocks", Res.blocks.name_of(st)):
					return lv
		lv = i
	return lv


static func sky_clear(world, p: Vector3i) -> bool:
	var b := Res.blocks
	for y in range(p.y + 1, Coords.MAX_Y):
		var st: int = world.state_at(p.x, y, p.z)
		if st > 0 and b.st_opacity[st] >= 15 and b.name_of(st) != "bedrock":
			return false
	return true


## Java BeaconBlockEntity.tick (every 80 game ticks).
static func tick(world) -> void:
	if world.game_time % 80 != 0:
		return
	var now: Dictionary = {}
	for c in BlockEntities.chunks_with(world, ["beacon"]):
		var ch: Chunk = c
		for k in ch.block_entities:
			var d: Dictionary = ch.block_entities[k]
			if str(d.get("id", "")) != "beacon":
				continue
			var p := Vector3i(ch.cx * 16 + (k & 15), (k >> 8) + Coords.MIN_Y, ch.cz * 16 + ((k >> 4) & 15))
			var lv := levels_at(world, p) if sky_clear(world, p) else 0
			var was := int(d.get("levels", 0))
			d["levels"] = lv
			if lv > 0 and was == 0:
				Audio.play("block.beacon.activate", Vector3(p), "Blocks")
			elif lv == 0 and was > 0:
				Audio.play("block.beacon.deactivate", Vector3(p), "Blocks")
			if lv > 0:
				now[p] = lv
				Audio.play("block.beacon.ambient", Vector3(p), "Blocks", 0.5)
				_apply(world, p, d, lv)
	active = now


static func _apply(world, p: Vector3i, d: Dictionary, lv: int) -> void:
	var prim := str(d.get("primary", ""))
	if prim == "":
		return
	var sec := str(d.get("secondary", ""))
	var rng := float(lv * 10 + 10)
	var amp := 1 if lv >= 4 and prim == sec else 0
	var dur := (9 + lv * 2) * 20
	var players: Array = [world.player]
	players.append_array(Net.proxies())
	for pl in players:
		if pl.dead or absf(pl.pos.x - (p.x + 0.5)) > rng + 0.5 or absf(pl.pos.z - (p.z + 0.5)) > rng + 0.5:
			continue
		pl.add_effect(prim, amp, dur)
		if lv >= 4 and sec != "" and sec != prim:
			pl.add_effect(sec, 0, dur)


## Per frame (main thread): beam nodes for active beacons, kept in sync with the floating origin.
static func render(world) -> void:
	for p in _beams.keys():
		if not active.has(p) or world.cm.get_chunk(p.x >> 4, p.z >> 4) == null:
			(_beams[p] as Node).queue_free()
			_beams.erase(p)
	for p in active:
		var mi: MeshInstance3D = _beams.get(p)
		var h := float(Coords.MAX_Y - p.y - 1)
		if mi == null:
			mi = MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.4, h, 0.4)
			mi.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.albedo_texture = UiKit.sprite("entity/beacon_beam")
			mat.albedo_color = Color(1, 1, 1, 0.8)
			mat.uv1_scale = Vector3(1, h, 1)
			mat.texture_repeat = true
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			world.add_child(mi)
			_beams[p] = mi
		mi.position = world.vis(Vector3(p) + Vector3(0.5, 1.0 + h / 2.0, 0.5))
		mi.rotation.y = float(world.game_time % 400) / 400.0 * TAU
		var mat2: StandardMaterial3D = mi.material_override
		mat2.uv1_offset = Vector3(0, -float(world.game_time % 40) / 40.0, 0)


static func clear() -> void:
	for p in _beams:
		if is_instance_valid(_beams[p]):
			(_beams[p] as Node).queue_free()
	_beams.clear()
	active.clear()
