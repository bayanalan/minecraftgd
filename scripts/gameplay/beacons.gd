## Beacons (Java BeaconBlockEntity): every 80 ticks the pyramid under the beacon is measured (levels 1-4, every
## block of each square layer in #beacon_base_blocks), the beam needs a clear column (blocks with light dampening 15
## stop it, bedrock does not), and the selected effects are given to players within levels*10+10 blocks
## horizontally (from that far below the beacon up past the build height) for (9 + 2*levels) s; level 4 adds the secondary (regeneration, or the primary
## at amplifier II). Payment: one item of #beacon_payment_items. Beam: rotating emissive column textured with the
## installed entity/beacon_beam.png, split into coloured segments by stained glass / panes (wiki Beacon: the lowest
## glass sets the colour, every further glass averages its colour with the current one; dye colour codes from the
## wiki Dye page).
## Composter (Java ComposterBlock): compost chances per item, level 0-7, ready (8) after 20 ticks, bone meal out.
class_name Beacons
extends RefCounted

const TIERS := [["speed", "haste"], ["resistance", "jump_boost"], ["strength"], ["regeneration"]]
# wiki: Composter (Java compostable items; leaves / saplings / propagules and flowers by name / tag below)
const COMPOST := {"dried_kelp_block": 0.5, "tall_grass": 0.5, "flowering_azalea_leaves": 0.5, "cactus": 0.5, "sugar_cane": 0.5,
	"vine": 0.5, "nether_sprouts": 0.5, "weeping_vines": 0.5, "twisting_vines": 0.5, "melon_slice": 0.5, "glow_lichen": 0.5,
	"apple": 0.65, "beetroot": 0.65, "carrot": 0.65, "cocoa_beans": 0.65, "potato": 0.65, "wheat": 0.65, "lily_pad": 0.65,
	"melon": 0.65, "pumpkin": 0.65, "carved_pumpkin": 0.65, "brown_mushroom": 0.65, "red_mushroom": 0.65, "nether_wart": 0.65,
	"sea_pickle": 0.65, "shroomlight": 0.65, "spore_blossom": 0.65, "big_dripleaf": 0.65, "moss_block": 0.65, "fern": 0.65,
	"large_fern": 0.65, "crimson_fungus": 0.65, "warped_fungus": 0.65, "crimson_roots": 0.65, "warped_roots": 0.65,
	"mushroom_stem": 0.65, "pale_moss_block": 0.65, "shelf_mushroom": 0.65, "straw_bed": 0.65, "wither_rose": 0.65,
	"baked_potato": 0.85, "bread": 0.85, "cookie": 0.85, "hay_block": 0.85, "red_mushroom_block": 0.85,
	"brown_mushroom_block": 0.85, "nether_wart_block": 0.85, "warped_wart_block": 0.85,
	"flowering_azalea": 0.85, "torchflower": 0.85, "pitcher_plant": 0.85, "cake": 1.0, "pumpkin_pie": 1.0,
	"beetroot_seeds": 0.3, "dried_kelp": 0.3, "short_grass": 0.3, "kelp": 0.3, "melon_seeds": 0.3, "pumpkin_seeds": 0.3,
	"wheat_seeds": 0.3, "sweet_berries": 0.3, "glow_berries": 0.3, "seagrass": 0.3, "small_dripleaf": 0.3,
	"hanging_roots": 0.3, "mangrove_roots": 0.3, "moss_carpet": 0.3, "pitcher_pod": 0.3, "torchflower_seeds": 0.3,
	"pink_petals": 0.3, "bush": 0.3, "cactus_flower": 0.3, "firefly_bush": 0.3, "leaf_litter": 0.3, "pale_hanging_moss": 0.3,
	"pale_moss_carpet": 0.3, "red_shrub": 0.3, "short_dry_grass": 0.3, "tall_dry_grass": 0.3, "wildflowers": 0.3,
	"azalea": 0.65}
const TALL_FLOWERS := ["sunflower", "lilac", "peony", "rose_bush"]   # the 26.3 #flowers tag's tall flowers

static var active: Dictionary = {}     # Vector3i -> levels (main thread)
static var segments: Dictionary = {}   # Vector3i -> Array of [first y, Color] (beam sections, bottom up)
static var _beams: Dictionary = {}     # Vector3i -> Node3D (one box per section)

# wiki Dye (Color values, "Color code" column - used for beacon beams; white is the Java value)
const DYE_COLOR := {"white": 0xF9FFFE, "orange": 0xF9801D, "magenta": 0xC74EBD, "light_blue": 0x3AB3DA, "yellow": 0xFED83D,
	"lime": 0x80C71F, "pink": 0xF38BAA, "gray": 0x474F52, "light_gray": 0x9D9D97, "cyan": 0x169C9C, "purple": 0x8932B8,
	"blue": 0x3C44AA, "brown": 0x835432, "green": 0x5E7C16, "red": 0xB02E26, "black": 0x1D1D21}


## Dye name of a stained glass block / pane ("" for anything else).
static func glass_dye(name: String) -> String:
	var c := ""
	if name.ends_with("_stained_glass"):
		c = name.trim_suffix("_stained_glass")
	elif name.ends_with("_stained_glass_pane"):
		c = name.trim_suffix("_stained_glass_pane")
	return c if DYE_COLOR.has(c) else ""


## Beam sections above the beacon at p (wiki Beacon colours), or [] when an opaque block (not bedrock) stops it.
static func beam_segments(world, p: Vector3i) -> Array:
	var b := Res.blocks
	var out: Array = [[p.y + 1, Color.WHITE]]
	var col := Color.WHITE
	var glass := false
	for y in range(p.y + 1, Coords.MAX_Y):
		var st: int = world.state_at(p.x, y, p.z)
		if st <= 0:
			continue
		var dye := glass_dye(b.name_of(st))
		if dye != "":
			var gc := Color.hex((int(DYE_COLOR[dye]) << 8) | 0xFF)
			col = Color((col.r + gc.r) * 0.5, (col.g + gc.g) * 0.5, (col.b + gc.b) * 0.5) if glass else gc
			glass = true
			if not (out[out.size() - 1][1] as Color).is_equal_approx(col):
				if int(out[out.size() - 1][0]) == y:
					out[out.size() - 1][1] = col   # (an empty white section right under the first glass)
				else:
					out.append([y, col])
			continue
		if b.st_opacity[st] >= 15 and b.name_of(st) != "bedrock":
			return []
	return out


static func compost_chance(nm: String) -> float:
	if COMPOST.has(nm):
		return COMPOST[nm]
	if nm.ends_with("_leaves") or nm.ends_with("_sapling") or nm.ends_with("_propagule"):
		return 0.3
	# "Flowers" 65 %: the small flowers and tall flowers (not every #flowers entry - chorus flowers do not compost)
	if Tags.items("small_flowers").has(nm) or nm in TALL_FLOWERS:
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
	var segs: Dictionary = {}
	for c in BlockEntities.chunks_with(world, ["beacon"]):
		var ch: Chunk = c
		for k in ch.block_entities:
			var d: Dictionary = ch.block_entities[k]
			if str(d.get("id", "")) != "beacon":
				continue
			var p := Vector3i(ch.cx * 16 + (k & 15), (k >> 8) + Coords.MIN_Y, ch.cz * 16 + ((k >> 4) & 15))
			var sg := beam_segments(world, p)
			var lv := levels_at(world, p) if not sg.is_empty() else 0
			if lv > 0:
				segs[p] = sg
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
	segments = segs
	var sigs: Dictionary = {}
	for p in segs:
		sigs[p] = str(segs[p])
	_sigs = sigs


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
		if pl.pos.y < float(p.y) - rng:
			continue   # wiki: Beacon - the area reaches the range below the beacon and up past the build height
		pl.add_effect(prim, amp, dur)
		if lv >= 4 and sec != "" and sec != prim:
			pl.add_effect(sec, 0, dur)


## Per frame (main thread): beam nodes for active beacons, kept in sync with the floating origin.
static func render(world) -> void:
	for p in _beams.keys():
		var nd: Node3D = _beams[p]
		if not active.has(p) or world.cm.get_chunk(p.x >> 4, p.z >> 4) == null or nd.get_meta("sig", "") != _sig(p):
			nd.queue_free()
			_beams.erase(p)
	for p in active:
		var root: Node3D = _beams.get(p)
		if root == null:
			root = _build_beam(world, p)
			_beams[p] = root
		root.position = world.vis(Vector3(p) + Vector3(0.5, 0.0, 0.5))
		var rot := float(world.game_time % 400) / 400.0 * TAU
		var off := Vector3(0, -float(world.game_time % 40) / 40.0, 0)
		for mi in root.get_children():
			(mi as MeshInstance3D).rotation.y = rot
			((mi as MeshInstance3D).material_override as StandardMaterial3D).uv1_offset = off


static var _sigs: Dictionary = {}   # Vector3i -> segments as text (rebuilt in tick, compared per frame)


static func _sig(p: Vector3i) -> String:
	return _sigs.get(p, "")


## One rotating box per beam section, tinted with its colour (sections run to the build limit).
static func _build_beam(world, p: Vector3i) -> Node3D:
	var root := Node3D.new()
	root.set_meta("sig", _sig(p))
	var sg: Array = segments.get(p, [[p.y + 1, Color.WHITE]])
	for i in sg.size():
		var y0 := int(sg[i][0])
		var y1 := int(sg[i + 1][0]) if i + 1 < sg.size() else Coords.MAX_Y
		var h := float(y1 - y0)
		if h <= 0.0:
			continue
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, h, 0.4)
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_texture = UiKit.sprite("entity/beacon_beam")
		var c: Color = sg[i][1]
		mat.albedo_color = Color(c.r, c.g, c.b, 0.8)
		mat.uv1_scale = Vector3(1, h, 1)
		mat.texture_repeat = true
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, float(y0 - p.y) + h / 2.0, 0)
		root.add_child(mi)
	world.add_child(root)
	return root


static func clear() -> void:
	for p in _beams:
		if is_instance_valid(_beams[p]):
			(_beams[p] as Node).queue_free()
	_beams.clear()
	active.clear()
	segments.clear()
	_sigs.clear()
