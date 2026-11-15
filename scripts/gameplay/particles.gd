## Particles — textured billboard particles from the installed textures/particle/*.png (packed into one atlas at
## world start), simulated at 20 TPS and interpolated per frame, drawn by one MultiMesh (shaders/particle.gdshader).
## Types follow Java particle classes (lifetime, gravity, friction, size, sprite animation over age):
## flame/soul_fire_flame (TorchFlameParticle), smoke/large_smoke (SmokeParticle, generic_7..0), campfire smoke
## (big_smoke), explosion (HugeExplosion sprites), crit/enchanted_hit, heart, angry/happy villager, note, portal,
## bubble, splash/rain, drip (hang/fall), dust (redstone), effect swirls, cherry leaves, end_rod.
## Emitters: Java ClientLevel.animateTick (random block samples around the player each tick:
## 667 within 16 + 667 within 32 blocks, like Java) and gameplay events via Particles.emit(kind, pos, ...).
## Cap 600 live particles (GDScript buffer update cost on the reference machine).
class_name Particles
extends Node3D

const CAP := 600
const SPRITES := ["flame", "soul_fire_flame", "generic_0", "generic_1", "generic_2", "generic_3", "generic_4", "generic_5", "generic_6", "generic_7",
	"big_smoke_0", "big_smoke_1", "big_smoke_2", "big_smoke_3", "big_smoke_4", "big_smoke_5", "big_smoke_6", "big_smoke_7", "big_smoke_8",
	"big_smoke_9", "big_smoke_10", "big_smoke_11", "explosion_0", "explosion_1", "explosion_2", "explosion_3", "explosion_4", "explosion_5",
	"explosion_6", "explosion_7", "explosion_8", "explosion_9", "explosion_10", "explosion_11", "explosion_12", "explosion_13", "explosion_14",
	"explosion_15", "critical_hit", "enchanted_hit", "heart", "angry", "glint", "note", "bubble", "splash_0", "splash_1", "splash_2", "splash_3",
	"drip_hang", "drip_fall", "drip_land", "effect_0", "effect_1", "effect_2", "effect_3", "effect_4", "effect_5", "effect_6", "effect_7",
	"cherry_0", "cherry_1", "cherry_2", "cherry_3", "cherry_4", "cherry_5", "cherry_6", "cherry_7", "cherry_8", "cherry_9", "cherry_10",
	"cherry_11", "leaf_0", "leaf_1", "leaf_2", "leaf_3", "leaf_4", "leaf_5", "leaf_6", "leaf_7", "leaf_8", "leaf_9", "leaf_10", "leaf_11",
	"pale_oak_0", "pale_oak_1", "pale_oak_2", "pale_oak_3", "pale_oak_4", "pale_oak_5", "pale_oak_6", "pale_oak_7", "pale_oak_8",
	"pale_oak_9", "pale_oak_10", "pale_oak_11", "orange_poplar_1", "orange_poplar_2", "orange_poplar_3", "orange_poplar_4",
	"red_poplar_1", "red_poplar_2", "red_poplar_3", "red_poplar_4", "yellow_poplar_1", "yellow_poplar_2", "yellow_poplar_3",
	"yellow_poplar_4", "lava", "spark_0", "glow", "damage", "flash", "bubble_pop_0",
	"sweep_0", "sweep_1", "sweep_2", "sweep_3", "sweep_4", "sweep_5", "sweep_6", "sweep_7",
	"spark_1", "spark_2", "spark_3", "spark_4", "spark_5", "spark_6", "spark_7",
	"glitter_0", "glitter_1", "glitter_2", "glitter_3", "glitter_4", "glitter_5", "glitter_6", "glitter_7",
	"soul_0", "soul_1", "soul_2", "soul_3", "soul_4", "soul_5", "soul_6", "soul_7", "soul_8", "soul_9", "soul_10"]

static var instance: Particles

var world
var mm: MultiMesh
var mmi: MultiMeshInstance3D
var uv: Dictionary = {}          # sprite -> Rect2 (atlas UV)
var parts: Array = []            # [kind, pos, prev, vel, age, life, size, color, sprite, grav, fric, bright, leaf state or null]
var rng := RandomNumberGenerator.new()
var _emit_ids: Dictionary = {}   # block id -> true for blocks with an animateTick emitter
# breaking-block particles (Java TerrainParticle): [pos, prev, vel, age, life, size, color, layer, u, v], own MultiMesh
const TCAP := 768
var tparts: Array = []   # terrain + item fragments: [pos, prev, vel, age, life, size, tint, layer, u, v]; layer <= -2: item atlas cell -2 - layer
var imm: MultiMesh       # item fragments (item sprite atlas)
var _iatlas: Image
var _iatlas_tex: ImageTexture
var _icells: Dictionary = {}   # item id -> atlas cell (-1: no flat sprite)
var _icount := 0
var tmm: MultiMesh
var _emit_st := PackedByteArray() # per state: 1 when its block has an emitter (built lazily)
const RCAP := 2048       # rain splash ring (100 spawns / tick at most, a splash lives <= 41 ticks, mostly < 15)
var rmm: MultiMesh
var _rbuf := PackedFloat32Array()
var _rhead := 0
var _rlive_until := -1   # game tick after which no splash in the ring can be alive
var _rdirty := false
var _rain_left := 0      # tickRainParticles tries left for the coming tick (spread over the frames before it)
var _rain_last := Vector3i(0, -99999, 0)
var _built_origin := Vector3i(-999999, 0, 0)


func _ready() -> void:
	instance = self
	rng.randomize()
	for bn in ["torch", "soul_torch", "wall_torch", "soul_wall_torch", "campfire", "soul_campfire", "furnace", "smoker", "blast_furnace", "nether_portal", "end_rod", "redstone_torch", "redstone_wall_torch", "redstone_wire", "lava", "cherry_leaves", "fire", "soul_fire", "wet_sponge"]:
		var bid := Res.blocks.block_id(bn)
		if bid >= 0:
			_emit_ids[bid] = true
	for bi in Res.blocks.names.size():
		if Res.blocks.names[bi].ends_with("candle"):
			_emit_ids[bi] = true
	var cell := 16
	var cols := 16
	var rows := int(ceil(float(SPRITES.size()) / cols))
	var atlas := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	for i in SPRITES.size():
		var t := UiKit.sprite("particle/" + SPRITES[i])
		if t == null:
			continue
		var img := t.get_image()
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != cell:
			img.resize(cell, cell, Image.INTERPOLATE_NEAREST)
		var x := (i % cols) * cell
		var y := (i / cols) * cell
		atlas.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i(x, y))
		uv[SPRITES[i]] = Rect2(float(x) / atlas.get_width(), float(y) / atlas.get_height(), float(cell) / atlas.get_width(), float(cell) / atlas.get_height())
	if OS.get_cmdline_user_args().has("--particles=1"):
		var big := atlas.duplicate()
		big.resize(atlas.get_width() * 4, atlas.get_height() * 4, Image.INTERPOLATE_NEAREST)
		big.save_png("user://autoplay/particle_atlas.png")
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	mm.mesh = qm
	mm.instance_count = CAP
	mm.visible_instance_count = 0
	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/particle.gdshader")
	mat.set_shader_parameter("atlas", ImageTexture.create_from_image(atlas))
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	mm.custom_aabb = mmi.custom_aabb   # (no per-upload AABB recomputation over the instances)
	add_child(mmi)
	# rain splashes (Java WaterDropParticle from tickRainParticles): one ring of spawn records; the GPU evaluates each
	# drop's flight in closed form (shaders/rain_splash.gdshader), the CPU never touches a live splash
	rmm = MultiMesh.new()
	rmm.transform_format = MultiMesh.TRANSFORM_3D
	rmm.use_colors = true
	rmm.use_custom_data = true
	var rq := QuadMesh.new()
	rq.size = Vector2.ONE
	rmm.mesh = rq
	rmm.instance_count = RCAP
	rmm.visible_instance_count = 0
	rmm.custom_aabb = mmi.custom_aabb
	_rbuf.resize(RCAP * 20)
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = rmm
	var rmat := ShaderMaterial.new()
	rmat.shader = load("res://shaders/rain_splash.gdshader")
	rmat.set_shader_parameter("atlas", mat.get_shader_parameter("atlas"))
	rmi.material_override = rmat
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rmi.custom_aabb = mmi.custom_aabb
	add_child(rmi)
	tmm = MultiMesh.new()
	tmm.transform_format = MultiMesh.TRANSFORM_3D
	tmm.use_colors = true
	tmm.use_custom_data = true
	var tq := QuadMesh.new()
	tq.size = Vector2.ONE
	tmm.mesh = tq
	tmm.instance_count = TCAP
	tmm.visible_instance_count = 0
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = tmm
	var tmat := ShaderMaterial.new()
	tmat.shader = load("res://shaders/terrain_particle.gdshader")
	if Res.atlas != null and Res.atlas.texture != null:
		tmat.set_shader_parameter("blocks_tex", Res.atlas.texture)
	tmi.material_override = tmat
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tmi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	tmm.custom_aabb = tmi.custom_aabb
	add_child(tmi)
	_iatlas = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	_iatlas_tex = ImageTexture.create_from_image(_iatlas)
	imm = MultiMesh.new()
	imm.transform_format = MultiMesh.TRANSFORM_3D
	imm.use_colors = true
	imm.use_custom_data = true
	var iq := QuadMesh.new()
	iq.size = Vector2.ONE
	imm.mesh = iq
	imm.instance_count = TCAP
	imm.visible_instance_count = 0
	var imi := MultiMeshInstance3D.new()
	imi.multimesh = imm
	var imat := ShaderMaterial.new()
	imat.shader = load("res://shaders/item_particle.gdshader")
	imat.set_shader_parameter("items_tex", _iatlas_tex)
	imi.material_override = imat
	imi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	imi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	imm.custom_aabb = imi.custom_aabb
	add_child(imi)


## Java ParticleEngine.destroy: every box of the block's shape split into max(2, ceil(extent / 0.25)) cells per axis
## (4 x 4 x 4 = 64 for a full block), one TerrainParticle per cell moving out from the centre.
static func terrain(p: Vector3i, st: int) -> void:
	if instance == null or st <= 0 or str(Settings.get_v("particles")) == "minimal":
		return
	instance._terrain(p, st)


func _terrain(p: Vector3i, st: int) -> void:
	var b := Res.blocks
	var layer: int = b.st_particle[st] if st < b.st_particle.size() else -1
	if layer < 0:
		return
	# Java TerrainParticle: colour 0.6 x the block colour (biome tint at the position); grass blocks stay untinted
	var tint := Color(0.6, 0.6, 0.6)
	if b.name_of(st) != "grass_block":
		tint = tint * _tint_at(st, p)
	var boxes := b.get_outline(st)
	if boxes.is_empty():
		boxes = PackedFloat32Array([0, 0, 0, 1, 1, 1])
	var every := 2 if str(Settings.get_v("particles")) == "decreased" else 1
	var n := 0
	for bi in range(0, boxes.size(), 6):
		var x0 := boxes[bi]
		var y0 := boxes[bi + 1]
		var z0 := boxes[bi + 2]
		var ex := minf(1.0, boxes[bi + 3] - x0)
		var ey := minf(1.0, boxes[bi + 4] - y0)
		var ez := minf(1.0, boxes[bi + 5] - z0)
		var ni := maxi(2, ceili(ex / 0.25))
		var nj := maxi(2, ceili(ey / 0.25))
		var nk := maxi(2, ceili(ez / 0.25))
		for i in ni:
			for j in nj:
				for k in nk:
					n += 1
					if n % every != 0:
						continue
					var fx := (i + 0.5) / ni
					var fy := (j + 0.5) / nj
					var fz := (k + 0.5) / nk
					var pos := Vector3(p) + Vector3(fx * ex + x0, fy * ey + y0, fz * ez + z0)
					_add_terrain(pos, Vector3(fx - 0.5, fy - 0.5, fz - 0.5), tint, layer)


## Java ParticleEngine.crack (each tick a block is being hit / mined): one TerrainParticle at a random point of the
## hit face of the block's outline (0.1 in from the edges, 0.1 out from the face), power 0.2 (velocity x 0.2, vertical
## (v - 0.1) x 0.2 + 0.1), scale 0.6.
static func crack(p: Vector3i, st: int, n: Vector3i) -> void:
	if instance == null or st <= 0 or str(Settings.get_v("particles")) == "minimal":
		return
	instance._crack(p, st, n)


func _crack(p: Vector3i, st: int, n: Vector3i) -> void:
	var b := Res.blocks
	var layer: int = b.st_particle[st] if st < b.st_particle.size() else -1
	if layer < 0:
		return
	var tint := Color(0.6, 0.6, 0.6)
	if b.name_of(st) != "grass_block":
		tint = tint * _tint_at(st, p)
	var boxes := b.get_outline(st)
	var mn := Vector3.ZERO
	var mx := Vector3.ONE
	if boxes.size() >= 6:
		mn = Vector3(boxes[0], boxes[1], boxes[2])
		mx = Vector3(boxes[3], boxes[4], boxes[5])
		for bi in range(6, boxes.size(), 6):
			mn = mn.min(Vector3(boxes[bi], boxes[bi + 1], boxes[bi + 2]))
			mx = mx.max(Vector3(boxes[bi + 3], boxes[bi + 4], boxes[bi + 5]))
	var pos := Vector3(p) + Vector3(rng.randf() * (mx.x - mn.x - 0.2) + 0.1 + mn.x, rng.randf() * (mx.y - mn.y - 0.2) + 0.1 + mn.y, rng.randf() * (mx.z - mn.z - 0.2) + 0.1 + mn.z)
	if n.y < 0:
		pos.y = p.y + mn.y - 0.1
	elif n.y > 0:
		pos.y = p.y + mx.y + 0.1
	elif n.z < 0:
		pos.z = p.z + mn.z - 0.1
	elif n.z > 0:
		pos.z = p.z + mx.z + 0.1
	elif n.x < 0:
		pos.x = p.x + mn.x - 0.1
	elif n.x > 0:
		pos.x = p.x + mx.x + 0.1
	_add_terrain(pos, Vector3.ZERO, tint, layer)
	var tp: Array = tparts[tparts.size() - 1]
	var v: Vector3 = tp[2]
	tp[2] = Vector3(v.x * 0.2, (v.y - 0.1) * 0.2 + 0.1, v.z * 0.2)
	tp[5] = float(tp[5]) * 0.6


## Java Particle(level, x, y, z, xa, ya, za) + TerrainParticle: velocity randomised and rescaled, lifetime
## 4 / (r * 0.9 + 0.1), half the default quad size, gravity 1 (0.04 / tick), friction 0.98, random 4x4 texel window.
func _add_terrain(pos: Vector3, a: Vector3, tint: Color, layer: int) -> void:
	if tparts.size() >= TCAP:
		tparts.pop_front()
	var v := a + Vector3(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0, randf() * 2.0 - 1.0) * 0.4
	var d0 := (randf() + randf() + 1.0) * 0.15
	var d1 := maxf(v.length(), 1e-6)
	v = Vector3(v.x / d1 * d0 * 0.4, v.y / d1 * d0 * 0.4 + 0.1, v.z / d1 * d0 * 0.4)
	var life := int(4.0 / (rng.randf() * 0.9 + 0.1))
	var size := 0.1 * (rng.randf() * 0.5 + 0.5)
	tparts.append([pos, pos, v, 0, life, size, tint, layer, rng.randf() * 3.0 / 4.0, rng.randf() * 3.0 / 4.0])


## Java ItemParticleOption / BreakingItemParticle (eating, an item breaking, thrown eggs and snowballs): a camera-facing
## quad showing a random 4x4-texel window of the item's own sprite (block items: the block's particle texture),
## untinted, half the default size, gravity 1, friction 0.98, lifetime 4 / (r * 0.9 + 0.1); velocity: the randomised
## spawn velocity x 0.1 plus the given one.
static func item_fragment(pos: Vector3, vel: Vector3, item: int) -> void:
	if instance == null or str(Settings.get_v("particles")) == "minimal":
		return
	instance._item_fragment(pos, vel, item)


func _item_fragment(pos: Vector3, vel: Vector3, item: int) -> void:
	var layer := -1
	var cell := _item_cell(item)
	if cell >= 0:
		layer = -2 - cell
	elif item >= 0 and item < Res.items.names.size():
		var st := Res.blocks.default_state(Res.items.names[item])
		if st > 0 and st < Res.blocks.st_particle.size():
			layer = Res.blocks.st_particle[st]
	if layer == -1:
		_add("item", pos, vel, Color(1, 1, 1))
		return
	if tparts.size() >= TCAP:
		tparts.pop_front()
	var v := Vector3(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0, randf() * 2.0 - 1.0) * 0.4
	var d0 := (randf() + randf() + 1.0) * 0.15
	var d1 := maxf(v.length(), 1e-6)
	v = Vector3(v.x / d1 * d0 * 0.4, v.y / d1 * d0 * 0.4 + 0.1, v.z / d1 * d0 * 0.4) * 0.1 + vel
	var life := int(4.0 / (rng.randf() * 0.9 + 0.1))
	var size := 0.1 * (rng.randf() * 0.5 + 0.5)
	tparts.append([pos, pos, v, 0, life, size, Color(1, 1, 1), layer, rng.randf() * 3.0 / 4.0, rng.randf() * 3.0 / 4.0])


func _item_cell(item: int) -> int:
	if _icells.has(item):
		return _icells[item]
	var cell := -1
	var img: Image = null
	if item >= 0 and item < Res.items.model_ref.size():
		img = ItemIcons.flat_image(Res.items.model_ref[item])
	if img != null and _icount < 256:
		var im: Image = img.duplicate()
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		if im.get_width() != 16 or im.get_height() != 16:
			im.resize(16, 16, Image.INTERPOLATE_NEAREST)
		cell = _icount
		_icount += 1
		_iatlas.blit_rect(im, Rect2i(0, 0, 16, 16), Vector2i((cell % 16) * 16, (cell / 16) * 16))
		_iatlas_tex.update(_iatlas)
	_icells[item] = cell
	return cell


## Biome tint for a tinted state at a block position (the chunk's cached colour columns), white otherwise.
func _tint_at(st: int, p: Vector3i) -> Color:
	var fl: int = Res.blocks.st_flags[st]
	if fl & BlockRegistry.F_TINT_CONST:
		var tv: int = Res.blocks.st_tint_color[st]
		return Color8((tv >> 16) & 255, (tv >> 8) & 255, tv & 255)
	var base := -1
	if fl & BlockRegistry.F_TINT_GRASS:
		base = 0
	elif fl & BlockRegistry.F_TINT_FOLIAGE:
		base = 256
	elif fl & BlockRegistry.F_TINT_WATER:
		base = 512
	elif fl & BlockRegistry.F_TINT_DRY:
		base = 768
	if base < 0 or world == null or world.cm == null:
		return Color(1, 1, 1)
	var c: Chunk = world.cm.get_chunk(p.x >> 4, p.z >> 4)
	if c == null:
		return ItemIcons.block_tint(st)
	var tints: PackedColorArray = world.cm._tints(c)
	var i := base + (p.z & 15) * 16 + (p.x & 15)
	return tints[i] if i < tints.size() else ItemIcons.block_tint(st)


## Spawn one particle. kind decides physics/sprites; color tints (white default).
static func emit(kind: String, pos: Vector3, vel: Vector3 = Vector3.ZERO, color: Color = Color.WHITE, n: int = 1) -> void:
	if instance == null or Settings.get_v("particles") == "minimal" and kind != "explosion":
		return
	for i in n:
		instance._add(kind, pos, vel, color)


func _add(kind: String, pos: Vector3, vel: Vector3, color: Color) -> void:
	if parts.size() >= CAP:
		parts.pop_front()
	var life := 20
	var size := 0.1
	var grav := 0.0
	var fric := 0.96
	var bright := false
	match kind:
		"flame", "soul_fire_flame":
			life = int(8.0 / (rng.randf() * 0.8 + 0.2)) + 4
			size = 0.1 * (rng.randf() * 0.5 + 0.5)
			bright = true
		"soul":
			# Java SoulParticle (RisingParticle like the flame: friction 0.96), size x 1.5, its 11-frame sprite set
			life = int(8.0 / (rng.randf() * 0.8 + 0.2)) + 4
			size = 0.15 * (rng.randf() * 0.5 + 0.5)
		"smoke", "large_smoke":
			life = int(8.0 / (rng.randf() * 0.8 + 0.2))
			size = 0.1 * (2.5 if kind == "large_smoke" else 1.0) * (rng.randf() * 0.5 + 0.5)
			var g := rng.randf() * 0.3
			color = Color(g, g, g) if color == Color.WHITE else color
			vel += Vector3(0, 0.004, 0)
		"poof":
			# Java ExplodeParticle (POOF): rises (gravity -0.1), friction 0.9, grey 0.7..1, size 0.1 x (1 + 6 r r)
			life = int(16.0 / (rng.randf() * 0.8 + 0.2)) + 2
			size = 0.1 * (rng.randf() * rng.randf() * 6.0 + 1.0)
			var pg := rng.randf() * 0.3 + 0.7
			color = Color(pg, pg, pg)
			vel += Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 0.05
			grav = -0.004
			fric = 0.9
		"campfire_smoke":
			life = rng.randi_range(80, 140)
			size = 0.3 * (rng.randf() * 0.5 + 0.5)
			vel = Vector3(rng.randf_range(-0.005, 0.005), 0.07, rng.randf_range(-0.005, 0.005))
			fric = 0.99
		"explosion":
			life = 6 + rng.randi_range(0, 4)
			size = 2.0 * (1.0 - rng.randf() * 0.5)
			bright = true
			var gc := rng.randf() * 0.6 + 0.4
			color = Color(gc, gc, gc)
		"firework":
			# Java FireworkParticles.SparkParticle: lifetime 48 + r(12), friction 0.91, quad 0.75x, sprite by age
			life = 48 + rng.randi_range(0, 11)
			size = 0.1 * 0.75
			fric = 0.91
			grav = 0.004
			bright = true
		"totem_of_undying":
			# Java TotemParticle: lifetime 60 + r(12), gravity 1.25, friction 0.6, quad 0.75x
			life = 60 + rng.randi_range(0, 11)
			size = 0.1 * 0.75
			fric = 0.6
			grav = 0.05
			bright = true
		"sweep_attack":
			# Java AttackSweepParticle: lifetime 4, quad 1 - r*0.5, grey 0.6-0.9, full bright
			life = 4
			size = 1.0 - rng.randf() * 0.5
			var sg := rng.randf() * 0.3 + 0.6
			color = Color(sg, sg, sg)
			bright = true
			fric = 0.0
		"item":
			# Java BreakingItemParticle: lifetime 4/(r*0.9+0.1), gravity 1 (0.04/tick), half quad size
			life = int(4.0 / (rng.randf() * 0.9 + 0.1))
			size = 0.1 * (rng.randf() * 0.5 + 0.5) * 0.5
			grav = 0.04
			fric = 0.98
		"crit", "enchanted_hit":
			life = int(6.0 / (rng.randf() * 0.8 + 0.6))
			size = 0.1 * 0.75
			grav = 0.04
			fric = 0.7
			if kind == "crit":
				color = Color(rng.randf() * 0.3 + 0.6, rng.randf() * 0.3 + 0.6, rng.randf() * 0.3 + 0.6)
			else:
				color = Color(0.48, 0.38, 0.95)
		"heart", "angry_villager", "happy_villager":
			life = 16
			size = 0.15
			vel = Vector3(0, 0.1, 0) if kind != "happy_villager" else vel
			fric = 0.86
		"note":
			life = 6
			size = 0.15
			vel = Vector3(0, 0.2, 0)
			fric = 0.66
		"portal":
			life = rng.randi_range(40, 49)
			size = 0.1 * (rng.randf() * 0.2 + 0.5)
			var f := rng.randf() * 0.6 + 0.4
			color = Color(f * 0.9, f * 0.3, f)
			bright = true
			fric = 1.0
		"bubble":
			life = int(8.0 / (rng.randf() * 0.8 + 0.2))
			size = 0.1 * (rng.randf() * 0.6 + 0.2)
			vel += Vector3(0, 0.002, 0)
			fric = 0.85
		"splash", "rain":
			life = int(8.0 / (rng.randf() * 0.8 + 0.2))
			size = 0.1
			grav = 0.06
			fric = 0.98
		"drip":
			life = 40
			size = 0.08
			grav = 0.0
		"dripping_water":
			# Java DripParticle.DripHangParticle (water, colour 0.2 / 0.3 / 1.0): hangs 40 ticks (gravity 0.06 x 0.02, motion x 0.02
			# a tick), then becomes a falling drop (tick)
			life = 40
			size = 0.2 * (rng.randf() * 0.5 + 0.5)
			grav = 0.06 * 0.02
			fric = 0.02 * 0.98
			color = Color(0.2, 0.3, 1.0)
		"falling_water":
			# Java DripParticle.FallAndLandParticle: gravity 0.06, friction 0.98, lifetime 64 / (r * 0.8 + 0.2); a splash where it lands
			life = int(64.0 / (rng.randf() * 0.8 + 0.2))
			size = 0.2 * (rng.randf() * 0.5 + 0.5)
			grav = 0.06
			fric = 0.98
			color = Color(0.2, 0.3, 1.0)
		"cloud":
			# Java PlayerCloudParticle: lifetime int(8 / (r * 0.8 + 0.3)) x 2.5, quad size x 1.875, grey 1 - r * 0.3, friction 0.96
			life = maxi(int(int(8.0 / (rng.randf() * 0.8 + 0.3)) * 2.5), 1)
			size = 0.2 * (rng.randf() * 0.5 + 0.5) * 1.875
			var cg := 1.0 - rng.randf() * 0.3
			color = Color(cg, cg, cg)
			vel += Vector3(0, 0.01, 0)
		"dust":
			life = int(8.0 / (rng.randf() * 0.8 + 0.2))
			size = 0.1 * 0.75
			fric = 0.96
		"effect":
			life = int(8.0 / (rng.randf() * 0.8 + 0.2))
			size = 0.1
			vel += Vector3(0, 0.03, 0)
			fric = 0.96
		"cherry_leaves", "tinted_leaves", "pale_oak_leaves", "falling_leaf", "orange_poplar_leaves", "red_poplar_leaves", "yellow_poplar_leaves":
			# Java FallingLeavesParticle(fallAcceleration, sideAcceleration, swirl, flowAway, scale, startVelocity):
			# cherry (0.25, 2, false, true, 1, 0), tinted / pale oak (0.07, 10, true, false, 2, 0.021); one random sprite
			var cherry := kind == "cherry_leaves"
			var side := 2.0 if cherry else 10.0
			life = 300
			grav = (0.25 if cherry else 0.07) * 1.2 * 0.0025
			fric = 1.0
			vel = Vector3(0, 0.0 if cherry else -0.021, 0)
			var rot_speed := deg_to_rad(-30.0 if rng.randi() & 1 else 30.0)
			var pr := rng.randf()
			var spin := deg_to_rad(-5.0 if rng.randi() & 1 else 5.0)
			size = (1.0 if cherry else 2.0) * (0.05 if rng.randi() & 1 else 0.075)
			var a60 := deg_to_rad(pr * 60.0)
			var spr: String
			if kind.ends_with("_poplar_leaves"):
				spr = kind.trim_suffix("_leaves") + "_%d" % rng.randi_range(1, 4)   # particles/<colour>_poplar_leaves.json: 4 sprites
			else:
				spr = ("cherry_%d" if cherry else ("pale_oak_%d" if kind == "pale_oak_leaves" else "leaf_%d")) % rng.randi_range(0, 11)
			# [roll, previous roll, spin speed, spin acceleration, flow x, flow z, side acceleration, swirl, flow away,
			#  swirl period, sprite]
			var lf := [0.0, 0.0, rot_speed, spin, cos(a60) * side, sin(a60) * side, side, not cherry, cherry, deg_to_rad(1000.0 + pr * 3000.0), spr]
			parts.append([kind, pos, pos, vel, 0, life, size, color, spr, grav, fric, bright, lf])
			return
		"end_rod":
			life = 60 + rng.randi_range(0, 12)
			size = 0.1
			bright = true
			fric = 0.91
		"lava":
			life = int(16.0 / (rng.randf() * 0.8 + 0.2))
			size = 0.1 * (rng.randf() * 2.0 + 0.2)
			vel = Vector3(rng.randf_range(-0.02, 0.02), rng.randf() * 0.4 + 0.05, rng.randf_range(-0.02, 0.02))
			grav = 0.75 * 0.04
			fric = 0.999
			bright = true
	parts.append([kind, pos, pos, vel, 0, life, size, color, _sprite(kind, 0, life), grav, fric, bright, null])


func _sprite(kind: String, age: int, life: int) -> String:
	var t := clampf(float(age) / maxf(1.0, float(life)), 0.0, 0.999)
	match kind:
		"flame", "soul_fire_flame":
			return kind
		"dripping_water":
			return "drip_hang"
		"falling_water":
			return "drip_fall"
		"cloud":
			return "generic_%d" % (7 - int(t * 8.0))
		"smoke", "large_smoke", "dust", "portal":
			return "generic_%d" % (7 - int(t * 8.0))
		"poof":
			return "generic_%d" % mini(7, int(t * 8.0))
		"campfire_smoke":
			return "big_smoke_%d" % int(t * 12.0)
		"explosion":
			return "explosion_%d" % int(t * 16.0)
		"sweep_attack":
			return "sweep_%d" % mini(7, int(t * 8.0))
		"firework":
			return "spark_%d" % mini(7, int(t * 8.0))
		"totem_of_undying":
			return "glitter_%d" % (7 - mini(7, int(t * 8.0)))
		"soul":
			return "soul_%d" % mini(10, int(t * 11.0))
		"crit":
			return "critical_hit"
		"enchanted_hit":
			return "enchanted_hit"
		"heart":
			return "heart"
		"angry_villager":
			return "angry"
		"happy_villager":
			return "glint"
		"note":
			return "note"
		"bubble":
			return "bubble"
		"splash", "rain":
			return "splash_%d" % int(t * 4.0)
		"drip":
			return "drip_hang"
		"effect":
			return "effect_%d" % (7 - int(t * 8.0))
		"end_rod":
			return "glint"
		"lava":
			return "lava"
	return "generic_0"


## Terrain / item fragments, once per tick: MODEL_MATRIX[3] = position, [2] = previous - position (the shaders
## interpolate with the global partial tick), [0].x = quad size.
func _build_terrain() -> void:
	var n := tparts.size()
	if n == 0:
		tmm.visible_instance_count = 0
		imm.visible_instance_count = 0
		return
	var buf := PackedFloat32Array()
	buf.resize(TCAP * 20)
	var ibuf := PackedFloat32Array()
	var ik := 0
	var day := clampf(world.sky_darken(), 0.2, 1.0)
	var fullbright: bool = Settings.get_v("adv_fullbright")
	var orgv := Vector3(world.cm.origin)
	var k := 0
	for q in tparts:
		var pos: Vector3 = (q[0] as Vector3) - orgv
		var dp: Vector3 = (q[1] as Vector3) - (q[0] as Vector3)
		var s: float = q[5] * 2.0   # Java quads span +-quadSize
		var wp: Vector3 = q[0]
		var l: int = world.cm.get_light(int(floor(wp.x)), int(floor(wp.y)), int(floor(wp.z)))
		var lv := 1.0 if fullbright else maxf(float(l >> 4) / 15.0 * day, float(l & 15) / 15.0)
		var m := 0.2 + 0.8 * lv
		var col: Color = q[6]
		if int(q[7]) <= -2:
			if ibuf.is_empty():
				ibuf.resize(TCAP * 20)
			var cl := -2 - int(q[7])
			ibuf[ik] = s
			ibuf[ik + 2] = dp.x
			ibuf[ik + 3] = pos.x
			ibuf[ik + 6] = dp.y
			ibuf[ik + 7] = pos.y
			ibuf[ik + 10] = dp.z
			ibuf[ik + 11] = pos.z
			ibuf[ik + 12] = col.r * m
			ibuf[ik + 13] = col.g * m
			ibuf[ik + 14] = col.b * m
			ibuf[ik + 15] = 1.0
			ibuf[ik + 16] = q[8]
			ibuf[ik + 17] = q[9]
			ibuf[ik + 18] = float(cl % 16) / 16.0
			ibuf[ik + 19] = float(cl / 16) / 16.0
			ik += 20
			continue
		buf[k] = s
		buf[k + 2] = dp.x
		buf[k + 3] = pos.x
		buf[k + 6] = dp.y
		buf[k + 7] = pos.y
		buf[k + 10] = dp.z
		buf[k + 11] = pos.z
		buf[k + 12] = col.r * m
		buf[k + 13] = col.g * m
		buf[k + 14] = col.b * m
		buf[k + 15] = 1.0
		buf[k + 16] = q[8]
		buf[k + 17] = q[9]
		buf[k + 18] = float(q[7])
		k += 20
	tmm.visible_instance_count = k / 20
	tmm.buffer = buf
	imm.visible_instance_count = ik / 20
	if ik > 0:
		imm.buffer = ibuf


## 20 TPS simulation.
func tick() -> void:
	var b := Res.blocks
	var flags := b.st_flags
	var chunks: Dictionary = world.cm.chunks
	var spawn_after: Array = []   # [kind, pos]: drops that fall after hanging, splashes where they land
	var keep: Array = []
	for p in parts:
		p[4] = int(p[4]) + 1
		if int(p[4]) >= int(p[5]):
			if p[0] == "dripping_water":
				spawn_after.append(["falling_water", p[1]])
			continue
		p[2] = p[1]
		var v: Vector3 = p[3]
		var lf = p[12]
		if lf != null:
			# Java FallingLeavesParticle.tick: flow-away / swirl side acceleration, spin
			var rel := minf(float(p[4]) / 300.0, 1.0)
			var xa := 0.0
			var za := 0.0
			if lf[8]:
				var pw := pow(rel, 1.25)
				xa += float(lf[4]) * pw
				za += float(lf[5]) * pw
			if lf[7]:
				xa += rel * cos(rel * float(lf[9])) * float(lf[6])
				za += rel * sin(rel * float(lf[9])) * float(lf[6])
			v.x += xa * 0.0025
			v.z += za * 0.0025
			lf[2] = float(lf[2]) + float(lf[3]) / 20.0
			lf[1] = lf[0]
			lf[0] = float(lf[0]) + float(lf[2]) / 20.0
		v.y -= float(p[9])
		var np: Vector3 = p[1] + v
		var st := -1
		var px := int(floor(np.x))
		var py := int(floor(np.y))
		var pz := int(floor(np.z))
		if py >= -64 and py < 320:
			var ck: Chunk = chunks.get(((px >> 4) << 32) | ((pz >> 4) & 0xFFFFFFFF))
			if ck != null and ck.state >= Chunk.DATA_READY:
				st = ck.get_block(px & 15, py, pz & 15)
		elif chunks.has(((px >> 4) << 32) | ((pz >> 4) & 0xFFFFFFFF)):
			st = 0
		if st > 0 and (flags[st] & BlockRegistry.F_COLLIDE) != 0 and float(p[9]) > 0.0:
			if p[0] == "falling_water":
				spawn_after.append(["splash", p[1]])
				continue
			if lf != null:
				continue   # Java: removed on landing or when a horizontal collision zeroes xd / zd
			v = Vector3(v.x * 0.7, 0.0, v.z * 0.7)
			np = p[1]
		if p[0] == "bubble" and (st <= 0 or (flags[st] & BlockRegistry.F_LIQUID) == 0):
			continue
		if p[0] == "falling_water" and st > 0 and (flags[st] & (BlockRegistry.F_LIQUID | BlockRegistry.F_LAVA)) == BlockRegistry.F_LIQUID:
			continue   # (DripParticle: gone inside water of its own kind)
		p[1] = np
		p[3] = v * float(p[10])
		if lf == null:
			p[8] = _sprite(p[0], p[4], p[5])
		keep.append(p)
	parts = keep
	for sa in spawn_after:
		_add(sa[0], sa[1], Vector3.ZERO, Color(0.2, 0.3, 1.0) if sa[0] != "splash" else Color.WHITE)
	var tkeep: Array = []
	for q in tparts:
		q[3] = int(q[3]) + 1
		if int(q[3]) >= int(q[4]):
			continue
		q[1] = q[0]
		var tv: Vector3 = q[2]
		tv.y -= 0.04
		var tp: Vector3 = q[0] + tv
		var tx := int(floor(tp.x))
		var ty := int(floor(tp.y))
		var tz := int(floor(tp.z))
		var tst := -1
		if ty >= -64 and ty < 320:
			var tck: Chunk = chunks.get(((tx >> 4) << 32) | ((tz >> 4) & 0xFFFFFFFF))
			if tck != null and tck.state >= Chunk.DATA_READY:
				tst = tck.get_block(tx & 15, ty, tz & 15)
		if tst > 0 and (flags[tst] & BlockRegistry.F_COLLIDE) != 0:
			tv = Vector3(tv.x * 0.7, 0.0, tv.z * 0.7)
			tp = q[0]
		q[0] = tp
		q[2] = tv * 0.98
		tkeep.append(q)
	tparts = tkeep
	_animate_blocks()
	_rain_finish()
	_build()


var _rain_sound_time := 0


## Java WeatherEffectRenderer.tickRainParticles: int(100 f^2) tries (f = rain level, halved on Fast graphics; halved
## again on Decreased particles, none on Minimal) at random columns +-10 around the camera whose top lies within 10
## blocks of it and where it rains (not snows): a rain splash (WaterDropParticle) on the top of the block's collision
## shape / fluid surface there, smoke on lava / magma / lit campfires. The last such column sounds weather.rain (0.2,
## 1.0), or weather.rain.above (0.1, 0.5) when it is more than a block above a camera under a roof, whenever
## nextInt(3) < rainSoundTime++ (wiki Rain: the same volumes / pitches).
## Java adds the particles of a tick at the next particle tick, so the tries are spread over the frames before the
## tick they belong to (_rain_step) and the splashes become visible together at that tick (spawn time = that tick).
func _rain_tries() -> int:
	if world.player == null or world.dimension != "overworld":
		return 0
	var rf: float = float(world.rain) / (2.0 if str(Settings.get_v("graphics")) == "fast" else 1.0)
	if rf <= 0.0:
		return 0
	return int(100.0 * rf * rf) / (2 if str(Settings.get_v("particles")) == "decreased" else 1)


## A share of the coming tick's tries, evenly over the frames left until it.
func _rain_step(delta: float) -> void:
	if _rain_left <= 0:
		return
	var frames_left := maxi(1, int((0.05 - float(world.tick_accum)) / maxf(delta, 0.0005)))
	var n := mini(_rain_left, maxi(1, ceili(float(_rain_left) / frames_left)))
	_rain_left -= n
	_rain_run(n)


func _rain_run(n: int) -> void:
	var wfx = world.get("weather_fx")
	if wfx == null or world.player == null:
		return
	var cols: Dictionary = wfx._cols
	var cam: Vector3 = world.player.pos + Vector3(0, world.player.eye_height(), 0)
	var cb := Vector3i(cam.floor())
	var b := Res.blocks
	var minimal := str(Settings.get_v("particles")) == "minimal"
	var spawn_t := float((int(world.game_time) + 1) & 131071)
	for i in n:
		var rx := cb.x + rng.randi_range(0, 20) - 10
		var rz := cb.z + rng.randi_range(0, 20) - 10
		var col = cols.get((rx << 32) ^ (rz & 0xFFFFFFFF))
		if col == null:
			continue
		var hy: int = col.k1
		if hy <= Coords.MIN_Y or hy > cb.y + 10 or hy < cb.y - 10 or col.kind != 1:
			continue
		var bs: int = col.top
		# Java: the top of the collision shape at a random point of the block, or the fluid surface (higher of both)
		var fx := rng.randf()
		var fz := rng.randf()
		var top := 0.0
		if bs > 0:
			var fl: int = b.st_flags[bs]
			if (fl & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0:
				top = float(BlockUpdates._amount(bs)) / 9.0
			if (fl & BlockRegistry.F_COLLIDE) != 0:
				var boxes := b.get_shape(bs)
				for bi in range(0, boxes.size(), 6):
					if fx >= boxes[bi] and fx <= boxes[bi + 3] and fz >= boxes[bi + 2] and fz <= boxes[bi + 5]:
						top = maxf(top, boxes[bi + 4])
		if top <= 0.0:
			continue
		_rain_last = Vector3i(rx, hy - 1, rz)
		if minimal:
			break
		var at := Vector3(rx + fx, hy - 1 + top, rz + fz)
		var bn := b.name_of(bs) if bs > 0 else ""
		if (bs > 0 and (b.st_flags[bs] & BlockRegistry.F_LAVA) != 0) or bn == "magma_block" or ((bn == "campfire" or bn == "soul_campfire") and b.get_prop(bs, "lit") == "true"):
			_add("smoke", at, Vector3.ZERO, Color.WHITE)
			continue
		_splash(at, spawn_t)
	_rlive_until = int(world.game_time) + 45


## One WaterDropParticle spawn record: Java Particle(x, y, z, 0, 0, 0) velocity (random direction, rescaled), then
## xd / zd x 0.3, yd = 0.1 + 0.2 r, lifetime 8 / (0.2 + 0.8 r), ground removal 50 % per tick (the number of ground ticks
## survived is drawn here), quad size 0.1 x (0.5 + 0.5 r) x 2, a random splash sprite, lit at its block.
func _splash(at: Vector3, spawn_t: float) -> void:
	var vx := (randf() * 2.0 - 1.0) * 0.4
	var vy := (randf() * 2.0 - 1.0) * 0.4
	var vz := (randf() * 2.0 - 1.0) * 0.4
	var d0 := (randf() + randf() + 1.0) * 0.15
	var d1 := maxf(sqrt(vx * vx + vy * vy + vz * vz), 1e-6)
	vx = vx / d1 * d0 * 0.4 * 0.3
	vz = vz / d1 * d0 * 0.4 * 0.3
	vy = randf() * 0.2 + 0.1
	var life := int(8.0 / (randf() * 0.8 + 0.2))
	var gr := 0
	while gr < 40 and randf() >= 0.5:
		gr += 1
	var size := 0.1 * (rng.randf() * 0.5 + 0.5) * 2.0
	var l: int = world.cm.get_light(floori(at.x), floori(at.y), floori(at.z))
	var lv := 1.0 if Settings.get_v("adv_fullbright") else maxf(float(l >> 4) / 15.0 * clampf(world.sky_darken(), 0.2, 1.0), float(l & 15) / 15.0)
	var m := 0.2 + 0.8 * lv
	var r: Rect2 = uv.get("splash_%d" % rng.randi_range(0, 3), uv.get("generic_0", Rect2(0, 0, 0.0625, 0.0625)))
	var pos := at - Vector3(world.cm.origin)
	var o := _rhead * 20
	_rhead = (_rhead + 1) % RCAP
	# MODEL_MATRIX[0] = start velocity, [1] = (spawn tick, lifetime, -), [2] = (ground ticks survived, quad size, -),
	# [3] = start position
	_rbuf[o] = vx
	_rbuf[o + 1] = spawn_t
	_rbuf[o + 2] = float(gr)
	_rbuf[o + 3] = pos.x
	_rbuf[o + 4] = vy
	_rbuf[o + 5] = float(life)
	_rbuf[o + 6] = size
	_rbuf[o + 7] = pos.y
	_rbuf[o + 8] = vz
	_rbuf[o + 9] = 0.0
	_rbuf[o + 10] = 0.0
	_rbuf[o + 11] = pos.z
	_rbuf[o + 12] = m
	_rbuf[o + 13] = m
	_rbuf[o + 14] = m
	_rbuf[o + 15] = 1.0
	_rbuf[o + 16] = r.position.x
	_rbuf[o + 17] = r.position.y
	_rbuf[o + 18] = r.size.x
	_rbuf[o + 19] = r.size.y
	_rdirty = true


## At the tick: the remaining tries, the rain sound, one upload of the splash ring; next tick's tries.
func _rain_finish() -> void:
	if _rain_left > 0:
		_rain_run(_rain_left)
		_rain_left = 0
	if _rdirty:
		_rdirty = false
		rmm.buffer = _rbuf
		rmm.visible_instance_count = RCAP
	elif rmm.visible_instance_count > 0 and int(world.game_time) > _rlive_until:
		rmm.visible_instance_count = 0
	var last := _rain_last
	_rain_last = Vector3i(0, -99999, 0)
	_rain_left = _rain_tries()
	if last.y == -99999 or world.player == null:
		return
	var cam: Vector3 = world.player.pos + Vector3(0, world.player.eye_height(), 0)
	var cb := Vector3i(cam.floor())
	var play := rng.randi_range(0, 2) < _rain_sound_time
	_rain_sound_time += 1
	if play:
		_rain_sound_time = 0
		var cch: Chunk = world.cm.get_chunk(cb.x >> 4, cb.z >> 4)
		var roof := cch != null and not cch.heightmap.is_empty() and int(cch.heightmap[(cb.x & 15) + (cb.z & 15) * 16]) > cb.y
		if last.y > cb.y + 1 and roof:
			Audio.play("weather.rain.above", Vector3(last) + Vector3(0.5, 0.5, 0.5), "Weather", 0.1, 0.5)
		else:
			Audio.play("weather.rain", Vector3(last) + Vector3(0.5, 0.5, 0.5), "Weather", 0.2, 1.0)


## Java ClientLevel.doAnimateTick sampling.
func _animate_blocks() -> void:
	if world.player == null or Settings.get_v("particles") == "minimal":
		return
	var b := Res.blocks
	var c: Vector3 = world.player.pos
	if _emit_st.size() != b.total_states:
		_emit_st.resize(b.total_states)
		for s0 in b.total_states:
			_emit_st[s0] = 1 if _emit_ids.has(b.st_block[s0]) or (b.st_flags[s0] & BlockRegistry.F_LEAVES) != 0 else 0
	var est := _emit_st
	var chunks: Dictionary = world.cm.chunks
	var bx := int(floor(c.x))
	var by := int(floor(c.y))
	var bz := int(floor(c.z))
	if _anim_native():
		# native sampling (RecraftNative.anim_sample: Java's 667 x 2 positions per tick, within 16 and 32 blocks,
		# own xorshift stream); only the emitting-block hits come back
		var gx0 := (bx - 32) >> 4
		var gz0 := (bz - 32) >> 4
		var grid: Array = []
		grid.resize(36)
		for gz in 6:
			for gx in 6:
				var gc: Chunk = chunks.get(((gx0 + gx) << 32) | ((gz0 + gz) & 0xFFFFFFFF))
				if gc != null and gc.state >= Chunk.DATA_READY:
					grid[gz * 6 + gx] = gc.sec_refs()
		var ar: Array = Native.inst.anim_sample(grid, gx0, gz0, 6, est, bx, by, bz, _anim_seed)
		_anim_seed = int(ar[1])
		var hits: PackedInt32Array = ar[0]
		for hi in range(0, hits.size(), 4):
			_anim_emit(b, hits[hi], hits[hi + 1], hits[hi + 2], hits[hi + 3])
	else:
		for i in 1334:
			var r := 16 if (i & 1) == 0 else 32
			var x := bx + rng.randi_range(-r, r)
			var y := by + rng.randi_range(-r, r)
			var z := bz + rng.randi_range(-r, r)
			# inlined ChunkManager.get_block (667 samples per tick; GDScript call chains dominated this loop)
			if y < -64 or y >= 320:
				continue
			var ck: Chunk = chunks.get(((x >> 4) << 32) | ((z >> 4) & 0xFFFFFFFF))
			if ck == null or ck.state < Chunk.DATA_READY:
				continue
			var sec: Chunk.Section = ck.sections[(y + 64) >> 4]
			var spal := sec.pal
			var st: int
			if spal.size() == 1:
				st = spal[0]
			else:
				var li := ((y & 15) << 8) | ((z & 15) << 4) | (x & 15)
				st = spal[sec.wide[li]] if sec.wide.size() > 0 else spal[sec.idx[li]]
			if st <= 0 or est[st] == 0:
				continue
			_anim_emit(b, x, y, z, st)


## One doAnimateTick hit: the block's ambient particles (torches, campfires, furnaces, portals, ...).
func _anim_emit(b: BlockRegistry, x: int, y: int, z: int, st: int) -> void:
	if (b.st_flags[st] & BlockRegistry.F_LEAVES) != 0:
		_leaf_emit(b, x, y, z, st)   # most hits are leaves: roll their chance before any name work
		return
	var nm := b.name_of(st)
	var q := Vector3(x + 0.5, y, z + 0.5)
	if nm == "torch" or nm == "soul_torch":
		_add("smoke", q + Vector3(0, 0.7, 0), Vector3.ZERO, Color.WHITE)
		_add("flame" if nm == "torch" else "soul_fire_flame", q + Vector3(0, 0.7, 0), Vector3.ZERO, Color.WHITE)
	elif nm == "wall_torch" or nm == "soul_wall_torch":
		var f := str(b.get_prop(st, "facing"))
		var off: Vector3 = {"north": Vector3(0, 0, 0.27), "south": Vector3(0, 0, -0.27), "west": Vector3(0.27, 0, 0), "east": Vector3(-0.27, 0, 0)}.get(f, Vector3.ZERO)
		_add("smoke", q + Vector3(0, 0.92, 0) + off, Vector3.ZERO, Color.WHITE)
		_add("flame" if nm == "wall_torch" else "soul_fire_flame", q + Vector3(0, 0.92, 0) + off, Vector3.ZERO, Color.WHITE)
	elif nm.ends_with("campfire") and b.get_prop(st, "lit") == "true":
		if rng.randf() < 0.4:
			_add("campfire_smoke", q + Vector3(rng.randf_range(-0.3, 0.3), 0.5, rng.randf_range(-0.3, 0.3)), Vector3.ZERO, Color(0.85, 0.85, 0.85, 0.9))
	elif nm in ["furnace", "smoker", "blast_furnace"] and b.get_prop(st, "lit") == "true":
		if rng.randf() < 0.1:
			var fd := str(b.get_prop(st, "facing"))
			var fo: Vector3 = {"north": Vector3(0, 0, -0.52), "south": Vector3(0, 0, 0.52), "west": Vector3(-0.52, 0, 0), "east": Vector3(0.52, 0, 0)}.get(fd, Vector3.ZERO)
			_add("smoke", q + Vector3(0, 0.3, 0) + fo, Vector3.ZERO, Color.WHITE)
			_add("flame", q + Vector3(0, 0.3, 0) + fo, Vector3.ZERO, Color.WHITE)
	elif nm == "nether_portal":
		_add("portal", Vector3(x + rng.randf(), y + rng.randf(), z + rng.randf()), Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)) * 0.05, Color.WHITE)
	elif nm == "end_rod" and rng.randf() < 0.2:
		_add("end_rod", q + Vector3(0, 0.6, 0), Vector3(0, 0.005, 0), Color.WHITE)
	elif (nm == "redstone_torch" or nm == "redstone_wall_torch") and b.get_prop(st, "lit") == "true":
		_add("dust", q + Vector3(rng.randf_range(-0.1, 0.1), 0.75, rng.randf_range(-0.1, 0.1)), Vector3.ZERO, Color(1.0, 0.1, 0.1))
	elif nm == "redstone_wire" and int(b.get_prop(st, "power")) > 0 and rng.randf() < 0.2:
		_add("dust", Vector3(x + rng.randf(), y + 0.06, z + rng.randf()), Vector3.ZERO, Color(0.3 + int(b.get_prop(st, "power")) / 15.0 * 0.7, 0, 0))
	elif nm == "lava" and world.state_at(x, y + 1, z) == 0 and rng.randf() < 0.01:
		_add("lava", Vector3(x + rng.randf(), y + 1.0, z + rng.randf()), Vector3.ZERO, Color.WHITE)
	elif (nm == "fire" or nm == "soul_fire") and rng.randf() < 0.3:
		_add("large_smoke", Vector3(x + rng.randf(), y + rng.randf() * 0.5 + 0.5, z + rng.randf()), Vector3.ZERO, Color.WHITE)
	elif nm.ends_with("candle") and b.get_prop(st, "lit") == "true" and rng.randf() < 0.3:
		_add("flame", q + Vector3(0, 0.55, 0), Vector3.ZERO, Color.WHITE)
	elif nm == "wet_sponge":
		_wet_sponge_drip(b, x, y, z)


## Java WetSpongeBlock.animateTick (wiki: wet sponges drip water from their sides and bottom; it gives no rate): a
## random direction per hit, none upward, none where that neighbour's face is full; a hanging water drip on that face.
const _DIR6 := [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
func _wet_sponge_drip(b: BlockRegistry, x: int, y: int, z: int) -> void:
	var di := rng.randi_range(0, 5)
	if di == 1:
		return
	var dv: Vector3i = _DIR6[di]
	var ns: int = world.state_at(x + dv.x, y + dv.y, z + dv.z)
	if ns > 0 and (b.st_flags[ns] & BlockRegistry.F_FULL_SHAPE) != 0:
		return
	var px := float(x)
	var py := float(y)
	var pz := float(z)
	if di == 0:
		py -= 0.05
		px += rng.randf()
		pz += rng.randf()
	else:
		py += rng.randf() * 0.8
		if dv.x != 0:
			pz += rng.randf()
			px += 1.1 if dv.x > 0 else -0.1
		else:
			px += rng.randf()
			pz += 1.1 if dv.z > 0 else -0.1
	_add("dripping_water", Vector3(px, py, pz), Vector3.ZERO, Color.WHITE)


## Java LeavesBlock.spawnFallingLeavesParticle: leafParticleChance (cherry 0.1, pale oak 0.02, tinted 0.01), only
## above a block whose collision top face is not full; tinted leaves take the block colour at the position.
## _leaf_kind per state: 0 no particles (azalea), 1 tinted, 2 cherry, 3 pale oak, 4-6 orange / red / yellow poplar
## (26.3 poplar leaves: chance and motion not in the data, ESTIMATED as pale oak).
var _leaf_kind := PackedByteArray()
const LEAF_CHANCE := [0.0, 0.01, 0.1, 0.02, 0.02, 0.02, 0.02]
const LEAF_KINDS := ["", "tinted_leaves", "cherry_leaves", "pale_oak_leaves", "orange_poplar_leaves", "red_poplar_leaves", "yellow_poplar_leaves"]
func _leaf_emit(b: BlockRegistry, x: int, y: int, z: int, st: int) -> void:
	if _leaf_kind.size() != b.total_states:
		_leaf_kind.resize(b.total_states)
		for s0 in b.total_states:
			if (b.st_flags[s0] & BlockRegistry.F_LEAVES) == 0:
				continue
			var n0 := b.name_of(s0)
			var lk := LEAF_KINDS.find(n0)
			_leaf_kind[s0] = 0 if n0.contains("azalea") else (lk if lk >= 2 else 1)
	var k := _leaf_kind[st]
	# LeavesBlock.makeDrippingWaterParticles (wiki Leaves: "water now slowly drips through leaves during rain"; the 1 in 15
	# per hit is Java's, not on the wiki): raining at the block above, the block below without a full top face
	if world.raining and rng.randi_range(0, 14) == 1 and world.weather_at(Vector3(x, y + 1, z)) == "rain":
		var bl: int = world.state_at(x, y - 1, z)
		if bl <= 0 or (b.st_flags[bl] & BlockRegistry.F_FULL_SHAPE) == 0:
			_add("dripping_water", Vector3(x + rng.randf(), y - 0.05, z + rng.randf()), Vector3.ZERO, Color.WHITE)
	if k == 0 or rng.randf() >= LEAF_CHANCE[k]:
		return
	var below: int = world.state_at(x, y - 1, z)
	if below > 0 and (b.st_flags[below] & BlockRegistry.F_FULL_SHAPE) != 0:
		return
	var lp := Vector3(x + rng.randf(), y - 0.05, z + rng.randf())
	if k >= 2:
		_add(LEAF_KINDS[k], lp, Vector3.ZERO, Color.WHITE)
	else:
		_add("tinted_leaves", lp, Vector3.ZERO, _tint_at(st, Vector3i(x, y, z)))


var _anim_seed := 0x2545F491
var _anim_nat := -1


func _anim_native() -> bool:
	if _anim_nat < 0:
		_anim_nat = 1 if (Native.ok and Native.chunkops_ok and Native.inst != null and Native.inst.has_method("anim_sample")) else 0
	return _anim_nat == 1


## Per frame: interpolate and upload the instance buffer.
## Once per tick (Java renders particles between ticks by interpolating their previous / current positions): the
## instance buffer holds MODEL_MATRIX[3] = position, [2] = previous - position, [0] = (quad size, age, lifetime),
## [1] = (previous roll, roll, size curve); shaders/particle.gdshader interpolates with the global partial tick, so
## no frame touches a particle.
func _build() -> void:
	_built_origin = world.cm.origin
	_build_terrain()
	var n := parts.size()
	mm.visible_instance_count = n
	if n == 0:
		return
	var buf := PackedFloat32Array()
	buf.resize(CAP * 20)
	var day := clampf(world.sky_darken(), 0.2, 1.0)
	var fullbright: bool = Settings.get_v("adv_fullbright")
	var orgv := Vector3(world.cm.origin)
	var k := 0
	for p in parts:
		var cur: Vector3 = (p[1] as Vector3) - orgv
		var dp: Vector3 = (p[2] as Vector3) - (p[1] as Vector3)
		var s: float = p[6] * 2.0   # Java quads span +-quadSize
		var r0 := 0.0
		var r1 := 0.0
		var curve := 1.0   # 0 constant, 1 grows in over the first 1/32 of the life, 2 flame shrink, 3 leaf roll
		var kind: String = p[0]
		if p[12] != null:
			r0 = float(p[12][1])
			r1 = float(p[12][0])
			curve = 3.0
		elif kind == "flame" or kind == "soul_fire_flame":
			curve = 2.0
		elif kind == "explosion" or kind == "campfire_smoke":
			curve = 0.0
		var col: Color = p[7]
		if not p[11]:
			var wp: Vector3 = p[1]
			var l: int = world.cm.get_light(int(floor(wp.x)), int(floor(wp.y)), int(floor(wp.z)))
			var lv := 1.0 if fullbright else maxf(float(l >> 4) / 15.0 * day, float(l & 15) / 15.0)
			var m := 0.2 + 0.8 * lv
			col = Color(col.r * m, col.g * m, col.b * m, col.a)
		var r: Rect2 = uv.get(p[8], uv.get("generic_0", Rect2(0, 0, 0.0625, 0.0625)))
		buf[k] = s
		buf[k + 1] = r0
		buf[k + 2] = dp.x
		buf[k + 3] = cur.x
		buf[k + 4] = float(p[4])
		buf[k + 5] = r1
		buf[k + 6] = dp.y
		buf[k + 7] = cur.y
		buf[k + 8] = float(p[5])
		buf[k + 9] = curve
		buf[k + 10] = dp.z
		buf[k + 11] = cur.z
		buf[k + 12] = col.r
		buf[k + 13] = col.g
		buf[k + 14] = col.b
		buf[k + 15] = col.a
		buf[k + 16] = r.position.x
		buf[k + 17] = r.position.y
		buf[k + 18] = r.size.x
		buf[k + 19] = r.size.y
		k += 20
	mm.buffer = buf


func _process(delta: float) -> void:
	if world == null or world.cm == null:
		return
	if world.cm.origin != _built_origin:
		# positions are stored relative to the world origin: rebuild now, splashes in flight are dropped
		_build()
		rmm.visible_instance_count = 0
		_rbuf.fill(0.0)
	_rain_step(delta)
