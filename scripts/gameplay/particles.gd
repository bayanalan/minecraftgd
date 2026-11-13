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
	"glitter_0", "glitter_1", "glitter_2", "glitter_3", "glitter_4", "glitter_5", "glitter_6", "glitter_7"]

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
var tparts: Array = []
var tmm: MultiMesh
var _emit_st := PackedByteArray() # per state: 1 when its block has an emitter (built lazily)


func _ready() -> void:
	instance = self
	rng.randomize()
	for bn in ["torch", "soul_torch", "wall_torch", "soul_wall_torch", "campfire", "soul_campfire", "furnace", "smoker", "blast_furnace", "nether_portal", "end_rod", "redstone_torch", "redstone_wall_torch", "redstone_wire", "lava", "cherry_leaves", "fire", "soul_fire"]:
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
	add_child(mmi)
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
	add_child(tmi)


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


func _draw_terrain(alpha: float) -> void:
	var n := tparts.size()
	tmm.visible_instance_count = n
	if n == 0:
		return
	var buf := PackedFloat32Array()
	buf.resize(TCAP * 20)
	var day := clampf(world.sky_darken(), 0.2, 1.0)
	var fullbright: bool = Settings.get_v("adv_fullbright")
	var k := 0
	for q in tparts:
		var pos: Vector3 = world.vis((q[1] as Vector3).lerp(q[0], alpha))
		var s: float = q[5] * 2.0   # Java quads span +-quadSize
		var wp: Vector3 = q[0]
		var l: int = world.cm.get_light(int(floor(wp.x)), int(floor(wp.y)), int(floor(wp.z)))
		var lv := 1.0 if fullbright else maxf(float(l >> 4) / 15.0 * day, float(l & 15) / 15.0)
		var m := 0.2 + 0.8 * lv
		var col: Color = q[6]
		buf[k] = s
		buf[k + 3] = pos.x
		buf[k + 5] = s
		buf[k + 7] = pos.y
		buf[k + 10] = s
		buf[k + 11] = pos.z
		buf[k + 12] = col.r * m
		buf[k + 13] = col.g * m
		buf[k + 14] = col.b * m
		buf[k + 15] = 1.0
		buf[k + 16] = q[8]
		buf[k + 17] = q[9]
		buf[k + 18] = float(q[7])
		k += 20
	tmm.buffer = buf


## 20 TPS simulation.
func tick() -> void:
	var b := Res.blocks
	var flags := b.st_flags
	var chunks: Dictionary = world.cm.chunks
	var keep: Array = []
	for p in parts:
		p[4] = int(p[4]) + 1
		if int(p[4]) >= int(p[5]):
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
			if lf != null:
				continue   # Java: removed on landing or when a horizontal collision zeroes xd / zd
			v = Vector3(v.x * 0.7, 0.0, v.z * 0.7)
			np = p[1]
		if p[0] == "bubble" and (st <= 0 or (flags[st] & BlockRegistry.F_LIQUID) == 0):
			continue
		p[1] = np
		p[3] = v * float(p[10])
		if lf == null:
			p[8] = _sprite(p[0], p[4], p[5])
		keep.append(p)
	parts = keep
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
	# rain splashes around the player (Java LevelRenderer.tickRain)
	if world.rain > 0.2 and world.dimension == "overworld":
		for i in int(world.rain * 6.0):
			var rx := int(floor(c.x)) + rng.randi_range(-10, 10)
			var rz := int(floor(c.z)) + rng.randi_range(-10, 10)
			var ch: Chunk = world.cm.get_chunk(rx >> 4, rz >> 4)
			if ch == null or ch.heightmap.is_empty():
				continue
			var hy: int = ch.heightmap[(rx & 15) + (rz & 15) * 16]
			if absf(hy - c.y) < 16.0:
				_add("rain", Vector3(rx + rng.randf(), hy + 0.05, rz + rng.randf()), Vector3(0, 0.1, 0), Color(0.5, 0.6, 1.0))


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
func _process(_d: float) -> void:
	if world == null or world.cm == null:
		return
	var alpha := clampf(world.tick_accum / 0.05, 0.0, 1.0)
	_draw_terrain(alpha)
	var n := parts.size()
	mm.visible_instance_count = n
	if n == 0:
		return
	var buf := PackedFloat32Array()
	buf.resize(n * 20)
	var day := clampf(world.sky_darken(), 0.2, 1.0)
	var fullbright: bool = Settings.get_v("adv_fullbright")
	var k := 0
	for p in parts:
		var pos: Vector3 = world.vis((p[2] as Vector3).lerp(p[1], alpha))
		var s: float = p[6] * 2.0   # Java quads span +-quadSize
		var rc := 1.0
		var rs := 0.0
		if p[12] != null:
			var roll := lerpf(float(p[12][1]), float(p[12][0]), alpha)
			rc = cos(roll)
			rs = sin(roll)
		elif p[0] == "flame" or p[0] == "soul_fire_flame":
			var t := (float(p[4]) + alpha) / float(p[5])
			s *= 1.0 - t * t * 0.5
		elif p[0] == "explosion" or p[0] == "campfire_smoke":
			s *= 1.0
		else:
			s *= clampf((float(p[4]) + alpha) / float(p[5]) * 32.0, 0.0, 1.0)
		var col: Color = p[7]
		if not p[11]:
			var wp: Vector3 = p[1]
			var l: int = world.cm.get_light(int(floor(wp.x)), int(floor(wp.y)), int(floor(wp.z)))
			var lv := 1.0 if fullbright else maxf(float(l >> 4) / 15.0 * day, float(l & 15) / 15.0)
			var m := 0.2 + 0.8 * lv
			col = Color(col.r * m, col.g * m, col.b * m, col.a)
		var r: Rect2 = uv.get(p[8], uv.get("generic_0", Rect2(0, 0, 0.0625, 0.0625)))
		# basis x = (s cos roll, s sin roll, 0): the shader takes the size from its length and the roll from its angle
		buf[k] = s * rc
		buf[k + 1] = 0.0
		buf[k + 2] = 0.0
		buf[k + 3] = pos.x
		buf[k + 4] = s * rs
		buf[k + 5] = s
		buf[k + 6] = 0.0
		buf[k + 7] = pos.y
		buf[k + 8] = 0.0
		buf[k + 9] = 0.0
		buf[k + 10] = s
		buf[k + 11] = pos.z
		buf[k + 12] = col.r
		buf[k + 13] = col.g
		buf[k + 14] = col.b
		buf[k + 15] = col.a
		buf[k + 16] = r.position.x
		buf[k + 17] = r.position.y
		buf[k + 18] = r.size.x
		buf[k + 19] = r.size.y
		k += 20
	# rows beyond n are hidden by visible_instance_count; the buffer must cover the whole multimesh
	if n < CAP:
		buf.resize(CAP * 20)
	mm.buffer = buf
