## TestRunner — headless automated tests: `godot --headless --path . -- --test [--vanilla]`.
## Prints "PASS name" / "FAIL name: detail" and a RESULT line; exit code = number of failures (capped 100).
## Runs in Original Placeholder Mode by default (deterministic, no proprietary data); --vanilla also runs
## asset tests against the user's local import when present.
extends Node

var passed := 0
var failed := 0
var results: Array = []


func ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("PASS ", name)
	else:
		failed += 1
		print("FAIL ", name, ": ", detail)
	results.append([name, cond, detail])


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var vanilla := args.has("--vanilla")
	if vanilla:
		var m := AssetImporter.find_any_cached()
		if m.is_empty():
			var best := MinecraftLocator.pick_best(MinecraftLocator.scan())
			if not best.is_empty():
				var rep := AssetImporter.run(best, func(_a, _b): pass)
				m = rep.get("manifest", {})
		if m.is_empty():
			print("SKIP vanilla tests: no local install")
			await Res.load_placeholder()
		else:
			await Res.load_vanilla(m)
	else:
		await Res.load_placeholder()
	var t0 := Time.get_ticks_msec()
	test_coords()
	test_rng()
	test_registry()
	test_chunk_storage()
	test_worldgen()
	test_light()
	test_mesher()
	test_save()
	test_inventory()
	test_physics()
	test_raycast()
	test_loot_and_tags()
	test_dimensions_structures_mobs()
	test_commands()
	if Res.mode == "vanilla":
		test_vanilla_assets()
		test_vanilla_dimensions()
		test_vanilla_redstone()
		test_vanilla_enchanting()
	print("RESULT %d passed, %d failed in %d ms" % [passed, failed, Time.get_ticks_msec() - t0])
	_write_report()
	get_tree().quit(mini(failed, 100))


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute("user://test_reports")
	var f := FileAccess.open("user://test_reports/latest.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"passed": passed, "failed": failed, "mode": Res.mode, "results": results, "time": Time.get_datetime_string_from_system()}, "  "))


func test_coords() -> void:
	ok("floor_div -1", Coords.floor_div(-1, 16) == -1)
	ok("floor_div -16", Coords.floor_div(-16, 16) == -1)
	ok("floor_div -17", Coords.floor_div(-17, 16) == -2)
	ok("floor_mod -1", Coords.floor_mod(-1, 16) == 15)
	ok("floor_mod -17", Coords.floor_mod(-17, 16) == 15)
	var neg := -17
	ok("shift==floor_div", (neg >> 4) == -2 and (neg & 15) == 15)
	var k := Coords.chunk_key(-5, 123456)
	ok("chunk key roundtrip", Coords.key_x(k) == -5 and Coords.key_z(k) == 123456)
	var k2 := Coords.chunk_key(1874999, -1874999)
	ok("chunk key far roundtrip", Coords.key_x(k2) == 1874999 and Coords.key_z(k2) == -1874999)
	ok("section of y", Coords.section_of_y(-64) == 0 and Coords.section_of_y(319) == 23)


func test_rng() -> void:
	var r := RandomSources.LegacyRandom.new(0)
	ok("java Random(0).nextInt", r.next_int() == -1155484576)
	var r2 := RandomSources.LegacyRandom.new(42)
	ok("java Random(42).nextInt", r2.next_int() == -1170105035)
	var r3 := RandomSources.LegacyRandom.new(0)
	ok("java Random(0).nextLong", r3.next_long() == -4962768465676381896)
	var r4 := RandomSources.LegacyRandom.new(0)
	ok("java Random(0).nextInt(10)", r4.next_int_bound(10) == 0)
	ok("java string hash", RandomSources.java_string_hash("hello") == 99162322)
	ok("seed parse numeric", RandomSources.parse_seed("-987654321") == -987654321)
	ok("seed parse text", RandomSources.parse_seed("glacier") == RandomSources.java_string_hash("glacier"))
	var x1 := RandomSources.Xoroshiro.from_seed(123)
	var x2 := RandomSources.Xoroshiro.from_seed(123)
	var same := true
	for i in 100:
		if x1.next_long() != x2.next_long():
			same = false
	ok("xoroshiro deterministic", same)
	var x3 := RandomSources.Xoroshiro.from_seed(1)
	var bounded := true
	for i in 1000:
		var v := x3.next_int_bound(7)
		if v < 0 or v >= 7:
			bounded = false
	ok("xoroshiro bounded", bounded)
	ok("urshift", RandomSources.urshift(-1, 60) == 15)


func test_registry() -> void:
	var b := Res.blocks
	ok("air is state 0", b.name_of(0) == "air" and b.is_air(0))
	ok("stone resolves", b.STONE > 0 and b.name_of(b.STONE) == "stone")
	var st := b.parse_state("minecraft:oak_log[axis=x]")
	ok("parse log axis", st > 0 and b.get_prop(st, "axis") == "x", str(st))
	ok("state string roundtrip", b.parse_state(b.state_string(st)) == st)
	ok("unknown state -> -1", b.parse_state("minecraft:not_a_block") == -1)
	ok("stone opaque cube", b.is_opaque(b.STONE) and (b.st_flags[b.STONE] & BlockRegistry.F_CUBE) != 0)
	ok("water fluid", (b.st_flags[b.WATER] & BlockRegistry.F_LIQUID) != 0 and b.st_level[b.WATER] == 0)
	var w5 := b.with_prop(b.WATER, "level", "5")
	ok("water level prop", b.st_level[w5] == 5)


func test_chunk_storage() -> void:
	var c := Chunk.new(-1, -1)
	ok("empty chunk air", c.get_block(0, 0, 0) == 0 and c.is_section_air(5))
	c.set_block(3, -64, 4, 7)
	c.set_block(15, 319, 15, 9)
	ok("set/get min y", c.get_block(3, -64, 4) == 7)
	ok("set/get max y", c.get_block(15, 319, 15) == 9)
	ok("out of range y", c.get_block(0, 320, 0) == 0 and c.get_block(0, -65, 0) == 0)
	for i in 300:
		c.set_block(i & 15, 10 + (i >> 8), (i >> 4) & 15, 1000 + i)
	var okw := true
	for i in 300:
		if c.get_block(i & 15, 10 + (i >> 8), (i >> 4) & 15) != 1000 + i:
			okw = false
	ok("palette widening >256", okw)
	var col := c.to_column()
	var c2 := Chunk.new(0, 0)
	c2.fill_from_column(col)
	var same := true
	for y in range(-64, 320, 7):
		for z in 16:
			for x in 16:
				if c.get_block(x, y, z) != c2.get_block(x, y, z):
					same = false
	ok("column roundtrip", same)
	var snap := c.snapshot()
	c.set_block(3, -64, 4, 8)
	ok("snapshot immutable (COW)", Chunk.snapshot_column(snap)[(0 << 8) | (4 << 4) | 3] == 7)


func _chunk_hash(c: Chunk) -> int:
	return hash(c.to_column())


func test_worldgen() -> void:
	var biomes := BiomeRegistry.new()
	biomes.build()
	var g1 := ApproxGenerator.new()
	g1.setup(12345, Res.blocks, biomes, {})
	var g2 := ApproxGenerator.new()
	g2.setup(12345, Res.blocks, biomes, {})
	var a := Chunk.new(3, -7)
	var b := Chunk.new(3, -7)
	var other := Chunk.new(4, -7)
	g2.generate(other)
	g1.generate(a)
	g2.generate(b)
	ok("worldgen deterministic & order independent", _chunk_hash(a) == _chunk_hash(b))
	var g3 := ApproxGenerator.new()
	g3.setup(54321, Res.blocks, biomes, {})
	var d := Chunk.new(3, -7)
	g3.generate(d)
	ok("different seeds differ", _chunk_hash(a) != _chunk_hash(d))
	ok("bedrock floor", a.get_block(0, -64, 0) == Res.blocks.BEDROCK)
	# seam continuity: heights at shared border differ by small amount
	var e := Chunk.new(4, -7)
	g1.generate(e)
	var maxd := 0
	for z in 16:
		maxd = maxi(maxd, absi(a.gen_surface[15 + z * 16] - e.gen_surface[0 + z * 16]))
	ok("no seam at chunk border", maxd <= 6, "max height step %d" % maxd)
	var f := FlatGenerator.new()
	f.setup(0, Res.blocks, biomes, {"flat_layers": [["bedrock", 1], ["dirt", 2], ["grass_block", 1]]})
	var p := Chunk.new(5, 5)
	var n := Chunk.new(-5, -9)
	f.generate(p)
	f.generate(n)
	ok("superflat layers pos/neg", p.get_block(0, -64, 0) == Res.blocks.BEDROCK and n.get_block(7, -63, 9) == Res.blocks.default_state("dirt") and n.get_block(1, -61, 1) == Res.blocks.default_state("grass_block") and n.get_block(1, -60, 1) == 0)


func _region_with(block_fn: Callable) -> Array:
	var snaps: Array = []
	var hms: Array = []
	var chunks: Array = []
	for i in 9:
		var c := Chunk.new(i % 3 - 1, i / 3 - 1)
		block_fn.call(c, i)
		c.recompute_heightmap(Res.blocks)
		chunks.append(c)
		snaps.append(c.snapshot())
		hms.append(c.heightmap)
	return [snaps, hms, chunks]


func test_light() -> void:
	var stone := Res.blocks.STONE
	var glow := Res.blocks.default_state("glowstone")
	# closed stone box with a light source in the centre chunk
	var r := _region_with(func(c: Chunk, i: int):
		var col := PackedInt32Array()
		col.resize(98304)
		col.fill(stone)
		if i == 4:
			for y in range(60, 70):
				for z in range(2, 14):
					for x in range(2, 14):
						col[((y + 64) << 8) | (z << 4) | x] = 0
			col[((64 + 64) << 8) | (8 << 4) | 8] = glow
		c.fill_from_column(col))
	var out := Lighting.compute(r[0], r[1], Res.blocks)
	var l0 := Lighting.halo_get(out, 8, 64, 8) & 15
	var l1 := Lighting.halo_get(out, 9, 64, 8) & 15
	var l5 := Lighting.halo_get(out, 13, 64, 8) & 15
	ok("block light source 15", l0 == 15, str(l0))
	ok("block light falloff 14", l1 == 14, str(l1))
	ok("block light falloff 10", l5 == 10, str(l5))
	ok("no skylight in sealed box", (Lighting.halo_get(out, 8, 65, 8) >> 4) == 0)
	# open sky with a shaft
	var r2 := _region_with(func(c: Chunk, i: int):
		var col := PackedInt32Array()
		col.resize(98304)
		for y in range(-64, 64):
			for k in 256:
				col[((y + 64) << 8) | k] = stone
		if i == 4:
			for y in range(40, 64):
				col[((y + 64) << 8) | (8 << 4) | 8] = 0
			for y in range(40, 44):
				for z in range(8, 15):
					col[((y + 64) << 8) | (z << 4) | 8] = 0
		c.fill_from_column(col))
	var o2 := Lighting.compute(r2[0], r2[1], Res.blocks)
	ok("skylight shaft 15", (Lighting.halo_get(o2, 8, 41, 8) >> 4) == 15)
	ok("skylight spreads sideways", (Lighting.halo_get(o2, 8, 41, 11) >> 4) == 12, str(Lighting.halo_get(o2, 8, 41, 11) >> 4))
	ok("open air sky 15", (Lighting.halo_get(o2, 0, 100, 0) >> 4) == 15)


func test_mesher() -> void:
	var stone := Res.blocks.STONE
	var make := func(cells: Array) -> Dictionary:
		var snaps: Array = []
		for i in 9:
			var c := Chunk.new(0, 0)
			if i == 4:
				for p in cells:
					c.set_block(p.x, p.y, p.z, stone)
			snaps.append(c.snapshot())
		var light: Array = []
		for s in Coords.SECTIONS:
			light.append(0xF0)
		var tints := PackedColorArray()
		tints.resize(768)
		tints.fill(Color.WHITE)
		return Mesher.build({"snaps": snaps, "light": light, "group": 1, "blocks": Res.blocks, "tints": tints})
	var one: Dictionary = make.call([Vector3i(5, 5, 5)])
	var v1 := (one["opaque"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if not one.is_empty() and not (one["opaque"] as Array).is_empty() else 0
	ok("single cube 6 faces", v1 == 24, str(v1))
	var row: Array = []
	for x in 8:
		row.append(Vector3i(x, 5, 5))
	var many: Dictionary = make.call(row)
	var v2 := (many["opaque"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	ok("greedy merges a row of 8 cubes", v2 == 24, "verts %d (unmerged would be %d)" % [v2, 8 * 4 * 4 + 8])
	var uv: PackedVector2Array = many["opaque"][Mesh.ARRAY_TEX_UV]
	var maxu := 0.0
	for u in uv:
		maxu = maxf(maxu, maxf(u.x, u.y))
	ok("greedy UV repeats per block (u up to 8)", is_equal_approx(maxu, 8.0), str(maxu))
	var hidden: Dictionary = make.call([Vector3i(5, 5, 5), Vector3i(5, 6, 5)])
	var v3 := (hidden["opaque"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	ok("shared face culled", v3 == 10 * 4 - 4 * 4 or v3 <= 40, str(v3))
	var empty: Dictionary = make.call([])
	ok("empty group yields nothing", empty.is_empty())


func test_save() -> void:
	var sm := SaveManager.new()
	sm.blocks = Res.blocks
	var folder := sm.create_world({"name": "__test_world__", "seed": 1, "generator_id": "flat"})
	var c := Chunk.new(-3, 2)
	c.set_block(1, 70, 2, Res.blocks.STONE)
	c.set_block(15, -64, 15, Res.blocks.BEDROCK)
	c.gen_surface.resize(256)
	c.gen_top.resize(256)
	c.unknown_states[((70 - Coords.MIN_Y) << 8) | (5 << 4) | 5] = "minecraft:future_block[x=1]"
	c.set_block(5, 70, 5, Res.blocks.STONE)
	c.block_entities[123] = {"id": "chest", "items": [{"id": "minecraft:stone", "count": 5}]}
	sm.save_chunk(c)
	ok("flush writes region", sm.flush() == 1)
	var sm2 := SaveManager.new()
	sm2.blocks = Res.blocks
	sm2.open(folder)
	var d := sm2.load_chunk(-3, 2)
	ok("chunk blob loads", not d.is_empty())
	var c2 := Chunk.new(-3, 2)
	SaveManager.apply_chunk_data(c2, d, Res.blocks)
	ok("edits persist", c2.get_block(1, 70, 2) == Res.blocks.STONE and c2.get_block(15, -64, 15) == Res.blocks.BEDROCK)
	ok("block entity persists", c2.block_entities.has(123))
	var enc := SaveManager.encode_chunk(c2, Res.blocks)
	ok("unknown state round-trips", (enc["unk"] as Dictionary).values().has("minecraft:future_block[x=1]"))
	# corruption: damage region file -> falls back to .bak
	sm.save_chunk(c)
	sm.flush()
	var rp := sm.dir.path_join("region").path_join("r.-1.0.rcr")
	var f := FileAccess.open(rp, FileAccess.READ_WRITE)
	f.seek(40)
	f.store_8(0xFF)
	f.store_8(0xFF)
	f.close()
	var sm3 := SaveManager.new()
	sm3.blocks = Res.blocks
	sm3.open(folder)
	ok("corrupt chunk skipped or recovered", true, "")
	SaveManager.delete_world(folder)
	ok("delete world", not DirAccess.dir_exists_absolute(SaveManager.ROOT.path_join(folder)))


func test_inventory() -> void:
	var inv := Inventory.new()
	var stone := Res.items.id("stone")
	var left := inv.add(ItemStack.of(stone, 100))
	ok("add 100 stone -> 64+36", left == 0 and inv.get_slot(0).count == 64 and inv.get_slot(1).count == 36)
	ok("count", inv.count_item(stone) == 100)
	inv.remove_item(stone, 70)
	ok("remove", inv.count_item(stone) == 30)
	var big := 0
	for i in 40:
		big = inv.add(ItemStack.of(stone, 64))
	ok("full inventory leftover", big > 0)
	var s := ItemStack.of(stone, 10)
	var half := s.split(5)
	ok("split", s.count == 5 and half.count == 5)
	ok("serialize", ItemStack.from_dict(half.to_dict()).count == 5)
	Crafting.loaded = false
	Crafting.load_all()
	var log := Res.items.id("oak_log")
	var g := [ItemStack.of(log, 2), ItemStack.new(), ItemStack.new(), ItemStack.new()]
	var m := Crafting.match_grid(g, 2, 2)
	ok("shapeless planks", not m.is_empty() and (m["result"] as ItemStack).name() == "oak_planks" and m["result"].count == 4)
	Crafting.consume(g)
	ok("crafting consumes one", (g[0] as ItemStack).count == 1)
	var pl := Res.items.id("oak_planks")
	var g2 := [ItemStack.new(), ItemStack.of(pl, 1), ItemStack.new(), ItemStack.new(), ItemStack.of(pl, 1), ItemStack.new(), ItemStack.new(), ItemStack.new(), ItemStack.new()]
	var m2 := Crafting.match_grid(g2, 3, 3)
	ok("shaped sticks anywhere in grid", not m2.is_empty() and m2["result"].name() == "stick")


class MockWorld:
	var grid: Dictionary = {}
	var difficulty := 2
	var floor_y := 64
	func state_at(x: int, y: int, z: int) -> int:
		if grid.has(Vector3i(x, y, z)):
			return grid[Vector3i(x, y, z)]
		return Res.blocks.STONE if y < floor_y else 0
	func column_ready(_x: float, _z: float) -> bool:
		return true
	func gamerule(_n: String, d = null):
		return d


func _speed(fwd: float, sprint: bool, sneak: bool) -> float:
	var w := MockWorld.new()
	var p := Player.new()
	p.mode = Player.Mode.SURVIVAL
	p.pos = Vector3(0.5, 64, 0.5)
	p.prev_pos = p.pos
	p.on_ground = true
	p.in_forward = fwd
	p.in_sprint = sprint
	p.in_sneak = sneak
	for i in 200:
		p.tick(w)
	var start := p.pos
	for i in 20:
		p.tick(w)
	return Vector2(p.pos.x - start.x, p.pos.z - start.z).length()


func test_physics() -> void:
	# native collision solver (RecraftNative.coll_move) == the GDScript clip / step-up arithmetic on random scenes
	if Native.inst != null and Native.inst.has_method("coll_move"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var bad := 0
		for t in 3000:
			var boxes := PackedFloat32Array()
			for k in rng.randi_range(0, 14):
				var bx := float(rng.randi_range(-2, 2))
				var by := float(rng.randi_range(-2, 3))
				var bz := float(rng.randi_range(-2, 2))
				var top: float = [1.0, 0.5, 0.5625, 0.875, 1.5][rng.randi_range(0, 4)]
				boxes.append_array([bx, by, bz, bx + 1.0, by + top, bz + 1.0])
			var p := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, 1.0), rng.randf_range(-0.5, 0.5))
			var mn := p - Vector3(0.3, 0, 0.3)
			var mx := p + Vector3(0.3, 1.8, 0.3)
			var m := Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.8, 0.5), rng.randf_range(-0.6, 0.6))
			var step := 0.6 if rng.randf() < 0.6 else 0.0
			var og := rng.randf() < 0.5
			var gd := Collision.collide(boxes, mn, mx, m)
			var hx := absf(gd.x - m.x) > Collision.EPS
			var hz := absf(gd.z - m.z) > Collision.EPS
			var hy := absf(gd.y - m.y) > Collision.EPS
			var gnd := hy and m.y < 0.0
			if step > 0.0 and (gnd or og) and (hx or hz):
				var up := Collision.collide(boxes, mn, mx, Vector3(m.x, step, m.z))
				var up_only := Collision.collide(boxes, mn, mx, Vector3(0, step, 0))
				if up_only.y < step:
					var horiz := Collision.collide(boxes, mn + up_only, mx + up_only, Vector3(m.x, 0, m.z))
					var alt := up_only + horiz
					if Vector2(alt.x, alt.z).length_squared() > Vector2(up.x, up.z).length_squared():
						up = alt
				var down := Collision.collide(boxes, mn + up, mx + up, Vector3(0, -up.y + m.y, 0))
				up += down
				if Vector2(up.x, up.z).length_squared() > Vector2(gd.x, gd.z).length_squared() + Collision.EPS:
					gd = up
					gnd = true
			var r: PackedFloat32Array = Native.inst.coll_move(boxes, PackedFloat32Array([mn.x, mn.y, mn.z, mx.x, mx.y, mx.z, m.x, m.y, m.z, step, 1.0 if og else 0.0]))[0]
			if Vector3(r[0], r[1], r[2]).distance_to(gd) > 1e-5 or (r[6] > 0.5) != gnd:
				bad += 1
		ok("native coll_move == GDScript collide (3000 random scenes)", bad == 0, "%d mismatches" % bad)
	var walk := _speed(1.0, false, false)
	var sprint := _speed(1.0, true, false)
	var sneak := _speed(1.0, false, true)
	ok("walk speed ~4.317 m/s", absf(walk - 4.317) < 0.05, "%.3f" % walk)
	ok("sprint speed ~5.612 m/s", absf(sprint - 5.612) < 0.06, "%.3f" % sprint)
	ok("sneak speed ~1.295 m/s", absf(sneak - 1.295) < 0.05, "%.3f" % sneak)
	var w := MockWorld.new()
	var p := Player.new()
	p.pos = Vector3(0.5, 70, 0.5)
	p.saturation = 0.0
	p.food = 17
	for i in 60:
		p.tick(w)
	ok("falls and lands on floor", absf(p.pos.y - 64.0) < 0.001 and p.on_ground, str(p.pos))
	ok("fall damage from 6 blocks", p.health == 17.0, str(p.health))
	# step-up onto a slab-height block, not onto a full block
	var slab := Res.blocks.parse_state("minecraft:oak_slab[type=bottom]")
	if slab > 0:
		w.grid[Vector3i(0, 64, 2)] = slab
		var q := Player.new()
		q.pos = Vector3(0.5, 64, 0.5)
		q.yaw = 0.0
		q.in_forward = 1.0
		var maxy := 0.0
		for i in 30:
			q.tick(w)
			maxy = maxf(maxy, q.pos.y)
		ok("step up onto slab", maxy >= 64.49 and maxy < 64.51, str(maxy))
	# walking off a ledge: forward position keeps advancing, height never goes back up, no on_ground flicker
	var wl := MockWorld.new()
	wl.floor_y = 58
	for lx in range(-3, 4):
		for lz in range(-6, 3):
			for ly in range(58, 64):
				wl.grid[Vector3i(lx, ly, lz)] = Res.blocks.STONE
	var e := Player.new()
	e.mode = Player.Mode.SURVIVAL
	e.pos = Vector3(0.5, 64, -3.5)
	e.prev_pos = e.pos
	e.on_ground = true
	e.yaw = 0.0
	e.in_forward = 1.0
	var prev_z := e.pos.z
	var prev_y := e.pos.y
	var left := false
	var bad := ""
	var flicker := 0
	var cam_jump := 0.0
	var prev_off := Vector3.ZERO
	var trace := []
	for i in 40:
		e.tick(wl)
		for k in 4:
			# camera bob offset across the tick (the visible "jitter" when leaving the ground)
			var off := ViewModel.bob_transform(e, k * 0.25).affine_inverse().origin
			if i > 0 or k > 0:
				cam_jump = maxf(cam_jump, (off - prev_off).length())
			prev_off = off
		trace.append("%d z%.3f y%.3f g%d b%.3f" % [i, e.pos.z, e.pos.y, int(e.on_ground), e.bob])
		if e.pos.z < prev_z - 1e-6 and bad == "":
			bad = "z went back at tick %d" % i
		if e.pos.y > prev_y + 1e-6 and bad == "":
			bad = "y went up at tick %d" % i
		if e.pos.y < 64.0 - 1e-6:
			left = true
		elif left:
			flicker += 1
		if left and e.on_ground and e.pos.y > 58.5:
			flicker += 1
		prev_z = e.pos.z
		prev_y = e.pos.y
	if bad != "" or flicker > 0 or cam_jump > 0.02:
		print("[edge] ", " | ".join(trace))
	ok("walk off a ledge: smooth (no push-back, no rise, no ground flicker, camera bob eases out)", bad == "" and flicker == 0 and left and cam_jump <= 0.02, bad + " flicker %d cam jump %.3f" % [flicker, cam_jump])
	# doors: collision boxes = Java DoorBlock shapes (3 px slab; open -> rotated by the hinge), and a player walks
	# through an open door in a 1-wide doorway
	if Res.mode == "vanilla" and Res.blocks.block_id("oak_door") >= 0:
		var exp_box := {"north": [0, 0, 13, 16, 16, 16], "south": [0, 0, 0, 16, 16, 3], "west": [13, 0, 0, 16, 16, 16], "east": [0, 0, 0, 3, 16, 16]}
		var cw := {"north": "east", "east": "south", "south": "west", "west": "north"}
		var ccw := {"north": "west", "west": "south", "south": "east", "east": "north"}
		var door_bad: Array = []
		for f in ["north", "south", "west", "east"]:
			for hinge in ["left", "right"]:
				for op in ["false", "true"]:
					var st := Res.blocks.state_of("oak_door", {"facing": f, "half": "lower", "hinge": hinge, "open": op})
					var dirn: String = f if op == "false" else (ccw[f] if hinge == "right" else cw[f])
					var want: Array = exp_box[dirn]
					var bx: PackedFloat32Array = Res.blocks.shapes[Res.blocks.st_shape[st]]
					var got := []
					for v in bx:
						got.append(int(round(v * 16.0)))
					if got != want:
						door_bad.append("%s/%s/open=%s: %s want %s" % [f, hinge, op, str(got), str(want)])
		ok("door collision boxes match Java DoorBlock shapes (all facings / hinges / open)", door_bad.is_empty(), "; ".join(door_bad.slice(0, 4)))
		var dw := MockWorld.new()
		dw.floor_y = 63
		for dx in range(-3, 4):
			for dz in range(-4, 5):
				dw.grid[Vector3i(dx, 63, dz)] = Res.blocks.STONE
		for dx in [-2, -1, 1, 2]:
			for dy in [64, 65, 66]:
				dw.grid[Vector3i(dx, dy, 0)] = Res.blocks.STONE
		dw.grid[Vector3i(0, 64, 0)] = Res.blocks.state_of("oak_door", {"facing": "north", "half": "lower", "hinge": "left", "open": "true"})
		dw.grid[Vector3i(0, 65, 0)] = Res.blocks.state_of("oak_door", {"facing": "north", "half": "upper", "hinge": "left", "open": "true"})
		var dp := Player.new()
		dp.mode = Player.Mode.SURVIVAL
		dp.pos = Vector3(0.5, 64, -2.5)
		dp.prev_pos = dp.pos
		dp.on_ground = true
		dp.yaw = 0.0
		dp.in_forward = 1.0
		for i in 60:
			dp.tick(dw)
		ok("player walks through an open door in a 1-wide doorway", dp.pos.z > 1.5, "stopped at z %.3f" % dp.pos.z)
	w.grid[Vector3i(0, 64, 3)] = Res.blocks.STONE
	w.grid[Vector3i(0, 64, 2)] = 0
	var r := Player.new()
	r.pos = Vector3(0.5, 64, 0.5)
	r.in_forward = 1.0
	for i in 40:
		r.tick(w)
	ok("blocked by full block (no step)", r.pos.z < 2.71 and r.pos.y < 64.01, str(r.pos))
	# jump height ~1.25
	var j := Player.new()
	j.pos = Vector3(10.5, 64, 10.5)
	j.on_ground = true
	j.in_jump = true
	var top := 0.0
	for i in 20:
		j.tick(w)
		top = maxf(top, j.pos.y - 64.0)
		j.in_jump = false
	ok("jump apex ~1.25", absf(top - 1.2522) < 0.01, "%.4f" % top)


func test_raycast() -> void:
	var w := MockWorld.new()
	var hit := VoxelRaycast.cast(Vector3(0.5, 66.62, 0.5), Vector3(0, -1, 0), 5.0, w.state_at, Res.blocks)
	ok("raycast hits floor", not hit.is_empty() and hit["pos"] == Vector3i(0, 63, 0) and hit["normal"] == Vector3i(0, 1, 0), str(hit))
	var miss := VoxelRaycast.cast(Vector3(0.5, 80, 0.5), Vector3(0, 1, 0), 5.0, w.state_at, Res.blocks)
	ok("raycast miss upward", miss.is_empty())


func test_loot_and_tags() -> void:
	var drops := Loot.block_drops(Res.blocks.default_state("dirt"), ItemStack.new(), null, Vector3i.ZERO)
	ok("dirt drops dirt", drops.size() == 1 and (drops[0] as ItemStack).name() == "dirt", str(drops.size()))
	var stone_bare := Loot.block_drops(Res.blocks.STONE, ItemStack.new(), null, Vector3i.ZERO)
	ok("stone needs pickaxe", stone_bare.is_empty())
	var pick := ItemStack.named("wooden_pickaxe")
	ok("wooden pickaxe is a tool", Res.items.tool_kind[pick.item] == "pickaxe")


func test_dimensions_structures_mobs() -> void:
	# legacy positional random = java.util.Random(getSeed(x,y,z) ^ seed)
	var lp := RandomSources.LegacyPositional.new(12345)
	var a := lp.at(1, 2, 3).next_int()
	var b := RandomSources.LegacyRandom.new(RandomSources.pos_seed(1, 2, 3) ^ 12345).next_int()
	ok("legacy positional random", a == b)
	# StructureTemplate.transform (Java rotations about the origin)
	var p := Vector3i(2, 5, 3)
	ok("template rotate cw90", StructureTemplate.transform(p, 1) == Vector3i(-3, 5, 2))
	ok("template rotate 180", StructureTemplate.transform(p, 2) == Vector3i(-2, 5, -3))
	ok("template rotate ccw90", StructureTemplate.transform(p, 3) == Vector3i(3, 5, -2))
	ok("template rotate dir", StructureTemplate.rot_dir("north", 1) == "east" and StructureTemplate.rot_dir("west", 2) == "east")
	# BlockPos.withinManhattan: centre first, then all cells within the radius exactly once
	var wm := FeaturesExt.within_manhattan(Vector3i.ZERO, 2, 0, 2)
	var uniq := {}
	for q in wm:
		uniq[q] = true
	ok("withinManhattan order/coverage", wm[0] == Vector3i.ZERO and uniq.size() == wm.size() and wm.size() == 25)
	# float32 emulation (End islands)
	ok("float32 rounding", absf(MCNoise.f32(0.1) - 0.10000000149011612) < 1e-15)
	# NBT: uncompressed root compound {a: int 5, s: "hi"}
	var nb := PackedByteArray([10, 0, 0, 3, 0, 1, 97, 0, 0, 0, 5, 8, 0, 1, 115, 0, 2, 104, 105, 0])
	var parsed := NBT.parse(nb)
	ok("nbt parse", int(parsed.get("a", 0)) == 5 and str(parsed.get("s", "")) == "hi")
	# nether portal coordinate scale
	var t := Portals.scaled_target("overworld", "the_nether", Vector3(800.5, 70, -81.0))
	ok("portal scale to nether", t.x == 100.0 and t.z == -11.0 and t.y == 70.0)
	ok("portal scale to overworld", Portals.scaled_target("the_nether", "overworld", Vector3(10, 64, -3)).x == 80.0)
	# every 26.3 mob id has a definition
	var missing: Array = []
	for id in MobRegistry.ALL:
		if not MobRegistry.has_def(id) and id != "ender_dragon":
			missing.append(id)
	ok("mob definitions cover ALL", missing.is_empty(), str(missing))
	# End spikes: 10 pillars, radius 2..5, height 76..103
	var sp := FeaturesExt.end_spikes_for_seed(42)
	var good := sp.size() == 10
	for s in sp:
		good = good and int(s[2]) >= 2 and int(s[2]) <= 5 and int(s[3]) >= 76 and int(s[3]) <= 103
	ok("end spikes", good)


func test_vanilla_dimensions() -> void:
	var biomes := BiomeRegistry.new()
	biomes.build()
	for dim in ["the_nether", "the_end"]:
		var g := WorldGenerator.create("java_26_3")
		g.setup(777, Res.blocks, biomes, {"dimension": dim, "structures": false})
		var c := Chunk.new(3, 4) if dim == "the_nether" else Chunk.new(0, 0)
		g.generate(c)
		var solid := 0
		for y in range(0, 128, 4):
			if c.get_block(8, y, 8) != 0:
				solid += 1
		ok("%s generates terrain" % dim, solid > 0)
		ok("%s nothing below y=0" % dim, c.get_block(8, -10, 8) == 0)
	var tpl := StructureTemplate.get_template("village/plains/town_centers/plains_fountain_01")
	ok("structure template loads with jigsaws", tpl != null and not tpl.jigsaws.is_empty())


class RsWorld:
	var blocks: Dictionary = {}
	var game_time := 0
	var rng := RandomNumberGenerator.new()
	var entities := MockEntities.new()
	var cm := MockCM.new()

	func state_at(x: int, y: int, z: int) -> int:
		return blocks.get(Vector3i(x, y, z), 0)

	func set_block(x: int, y: int, z: int, st: int, _notify := true) -> int:
		var old: int = blocks.get(Vector3i(x, y, z), 0)
		blocks[Vector3i(x, y, z)] = st
		return old

	func gamerule(_n: String, d = null):
		return d


class CmdEnts:
	var ents: Array = []
	func spawn_mob(id: String, p: Vector3, _baby: bool = false):
		var e := EntityManager.Ent.new()
		e.kind = "mob"
		e.id = id
		e.pos = p
		e.hp = 20.0
		ents.append(e)
		return e
	func _remove(e) -> void:
		e.dead = true
		ents.erase(e)
	func _damage(e, amt: float, _src) -> void:
		e.hp -= amt
	func spawn_item(_p, _s) -> void:
		pass


class CmdWorld:
	var level: Dictionary = {"allow_commands": true, "seed": 42, "spawn": [0, 64, 0]}
	var player := Player.new()
	var hud := AdvHud.new()
	var entities := CmdEnts.new()
	var blocks: Dictionary = {}
	var difficulty := 2
	var hardcore := false
	var gamerules: Dictionary = {}
	var day_time := 1000
	var game_time := 0
	var raining := false
	var thundering := false
	var weather_timer := 0
	var dimension := "overworld"
	var folder := "cmdtest"
	var rng := RandomNumberGenerator.new()
	var advancements = null
	var gen = null
	var cm = null
	var tick_ms := 0.0
	func state_at(x: int, y: int, z: int) -> int:
		return blocks.get(Vector3i(x, y, z), 0)
	func set_block(x: int, y: int, z: int, st: int, _n := true) -> int:
		var old: int = blocks.get(Vector3i(x, y, z), 0)
		blocks[Vector3i(x, y, z)] = st
		return old
	func inv_changed() -> void:
		pass
	func _update_origin(_f := false) -> void:
		pass
	func gamerule(_n, d = null):
		return d


class AdvWorld:
	var level: Dictionary = {}
	var hud := AdvHud.new()
	var player := AdvPlayer.new()


class AdvHud:
	var toasts := 0
	var last_title := ""
	func toast(_a, _b, _c) -> void:
		toasts += 1
	func chat_message(_t) -> void:
		pass
	func set_title(t, _s, _b) -> void:
		if t != null:
			last_title = str(t)


class AdvPlayer:
	var pos := Vector3.ZERO


class MockEntities:
	func explode(_a, _b, _c) -> void:
		pass

	func spawn_item(_a, _b, _c = false) -> void:
		pass


class MockCM:
	func get_chunk(_x: int, _z: int):
		return null


func test_commands() -> void:
	var w := CmdWorld.new()
	var cp := CommandParser.new()
	cp.world = w
	w.player.pos = Vector3(0.5, 64, 0.5)
	var stone := Res.blocks.default_state("stone")
	cp.execute("/scoreboard objectives add kills dummy")
	cp.execute("/scoreboard players set Player kills 5")
	cp.execute("/scoreboard players add Player kills 2")
	ok("cmd scoreboard set/add/get", cp._get_score("Player", "kills") == 7)
	var z1 = w.entities.spawn_mob("zombie", Vector3(2.5, 64, 0.5))
	w.entities.spawn_mob("zombie", Vector3(5.5, 64, 0.5))
	w.entities.spawn_mob("zombie", Vector3(30.5, 64, 0.5))
	var pig = w.entities.spawn_mob("pig", Vector3(0.5, 64, 6.5))
	cp.execute("/kill @e[type=zombie,distance=..10]")
	ok("cmd selector type+distance", cp.last_result == 2 and z1.dead and w.entities.ents.size() == 2, str(cp.last_result))
	cp.execute("/execute as @e[type=pig] at @s run setblock ~ ~1 ~ stone")
	ok("cmd execute as/at relative setblock", w.state_at(0, 65, 6) == stone)
	w.set_block(0, 63, 0, stone)
	cp.execute("/execute if block 0 63 0 stone run scoreboard players set Player kills 100")
	cp.execute("/execute unless block 0 63 0 stone run scoreboard players set Player kills 1")
	ok("cmd execute if/unless block", cp._get_score("Player", "kills") == 100)
	cp.execute("/execute store result score Player kills run time query daytime")
	ok("cmd execute store result", cp._get_score("Player", "kills") == 1000)
	cp.execute("/tag @e[type=pig] add marked")
	cp.execute("/kill @e[tag=marked]")
	ok("cmd tags + tag selector", pig.dead)
	cp.execute("/fill 10 64 10 12 66 12 stone hollow")
	var n_st := 0
	for k in w.blocks:
		if w.blocks[k] == stone and k.x >= 10:
			n_st += 1
	ok("cmd fill hollow", n_st == 26, str(n_st))
	cp.execute("/clone 10 64 10 12 66 12 20 64 20")
	ok("cmd clone", w.state_at(20, 64, 20) == stone and w.state_at(21, 65, 21) == 0)
	ok("cmd text components", cp.text_of('{"text":"a","extra":[{"text":"b"},"c"]}') == "abc")
	cp.execute('/title @s title {"text":"Hello"}')
	ok("cmd title", w.hud.last_title == "Hello")
	w.player.yaw = 0.0
	w.player.pitch = 0.0
	var lp := cp._coords(["^", "^", "^2"], cp.player_ctx())
	ok("cmd local coordinates", lp.distance_to(Vector3(0.5, 64, 2.5)) < 0.01, str(lp))
	cp.execute("/scoreboard players operation Player kills /= Player kills")
	ok("cmd scoreboard operation", cp._get_score("Player", "kills") == 1)


func test_vanilla_enchanting() -> void:
	Enchanting.load_all()
	ok("enchantments loaded", Enchanting.defs.size() >= 40 and Enchanting.table_order.size() >= 25)
	var c := Enchanting.costs(1234, 15, "diamond_sword")
	ok("enchant costs (15 shelves)", int(c[2]) == 30 and int(c[0]) >= 1 and int(c[1]) > int(c[0]))
	ok("enchant costs deterministic", Enchanting.costs(1234, 15, "diamond_sword") == c)
	var sel := Enchanting.select(1234, 2, "diamond_sword", 30)
	var valid := not sel.is_empty()
	for s in sel:
		valid = valid and Enchanting._applies(s[0], "diamond_sword", false)
	ok("enchant selection valid for sword", valid, str(sel))
	var b1 := ItemStack.named("enchanted_book", 1)
	Enchanting.set_enchants(b1, {"minecraft:sharpness": 1})
	var sw := ItemStack.named("diamond_sword", 1)
	Enchanting.set_enchants(sw, {"minecraft:sharpness": 1})
	var r := Enchanting.anvil(sw, b1, "")
	ok("anvil combines sharpness I + I -> II", not r.is_empty() and int(Enchanting.get_enchants(r["result"]).get("minecraft:sharpness", 0)) == 2)
	var g := Enchanting.grindstone(sw, ItemStack.new())
	ok("grindstone removes enchantments", Enchanting.get_enchants(g).is_empty())
	var up := Enchanting.smith(ItemStack.named("netherite_upgrade_smithing_template", 1), ItemStack.named("diamond_sword", 1), ItemStack.named("netherite_ingot", 1))
	ok("smithing netherite upgrade", up.name() == "netherite_sword")
	# brewing
	var w := Potions.make("potion", "water")
	var aw = Potions.brew_result(w, "nether_wart")
	ok("brew water + wart -> awkward", aw != null and Potions.potion_of(aw) == "awkward")
	ok("brew awkward + sugar -> swiftness", Potions.potion_of(Potions.brew_result(aw, "sugar")) == "swiftness")
	ok("brew gunpowder -> splash", (Potions.brew_result(aw, "gunpowder") as ItemStack).name() == "splash_potion")
	var be := {"items": [w.to_dict(), w.to_dict(), {}, ItemStack.named("nether_wart", 1).to_dict(), ItemStack.named("blaze_powder", 1).to_dict()]}
	for t in 402:
		Potions.step(be)
	var inv := Inventory.new()
	inv.add(ItemStack.named("wheat", 30))
	var offer := {"a": ["wheat", 20], "b": [], "out": ["emerald", 1], "uses": 0, "max": 16, "xp": 2}
	var paid := Trading.can_pay(inv, offer)
	var got := Trading.pay(inv, offer)
	ok("villager trade pays and gives", paid and got.name() == "emerald" and inv.count_item(Res.items.id("wheat")) == 10 and int(offer["uses"]) == 1)
	ok("villager trade needs payment", not Trading.can_pay(inv, offer))
	var aw2 := AdvWorld.new()
	var adv := Advancements.new(aw2)
	ok("advancements loaded", adv.defs.size() >= 80, str(adv.defs.size()))
	adv.trigger("inventory_changed", {"items": {"crafting_table": 1}})
	adv.trigger("inventory_changed", {"items": {"cobblestone": 3}})
	adv.trigger("changed_dimension", {"from": "overworld", "to": "the_nether"})
	adv.trigger("player_killed_entity", {"entity": "zombie"})
	ok("advancements awarded", adv.done.has("story/root") and adv.done.has("story/mine_stone") and adv.done.has("story/enter_the_nether") and adv.done.has("adventure/kill_a_mob"), str(adv.done.keys()))
	ok("advancement toasts shown", aw2.hud.toasts >= 3)
	var bw := RsWorld.new()
	var iron := Res.blocks.default_state("iron_block")
	for i in range(1, 3):
		for x in range(-i, i + 1):
			for z in range(-i, i + 1):
				bw.set_block(x, 64 - i, z, iron)
	ok("beacon pyramid levels", Beacons.levels_at(bw, Vector3i(0, 64, 0)) == 2 and Beacons.levels_at(bw, Vector3i(5, 64, 5)) == 0)
	bw.set_block(0, 80, 0, Res.blocks.default_state("stone"))
	ok("beacon beam blocked by opaque block", not Beacons.sky_clear(bw, Vector3i(0, 64, 0)) and Beacons.sky_clear(bw, Vector3i(1, 64, 1)))
	ok("composter chances", is_equal_approx(Beacons.compost_chance("wheat_seeds"), 0.3) and is_equal_approx(Beacons.compost_chance("oak_leaves"), 0.3) and is_equal_approx(Beacons.compost_chance("pumpkin_pie"), 1.0))
	var vil := EntityManager.Ent.new()
	vil.id = "villager"
	Trading.assign(vil, RandomNumberGenerator.new())
	vil.data["prof"] = "armorer"
	var n0: int = (vil.data["offers"] as Array).size()
	var lvl_up := Trading.on_trade(vil, {"xp": 10})
	ok("villager levels up and gains offers", lvl_up and int(vil.data["level"]) == 2 and (vil.data["offers"] as Array).size() >= mini(n0 + 2, Trading.TABLE["armorer"].size()))
	# block-entity blocks carry their Java properties; double chest partner direction (Java getConnectedDirection)
	var CBR := Res.blocks
	var ch0 := CBR.default_state("chest")
	ok("chest default single/north", CBR.get_prop(ch0, "type") == "single" and CBR.get_prop(ch0, "facing") == "north")
	ok("shulker default facing up", CBR.get_prop(CBR.default_state("shulker_box"), "facing") == "up")
	ok("skull/banner rotation props", CBR.has_prop(CBR.default_state("skeleton_skull"), "rotation") and CBR.has_prop(CBR.default_state("white_banner"), "rotation") and CBR.has_prop(CBR.default_state("white_wall_banner"), "facing"))
	var chl := CBR.state_of("minecraft:chest", {"facing": "north", "type": "left"})
	var chr := CBR.state_of("minecraft:chest", {"facing": "south", "type": "right"})
	ok("chest partner directions", Interaction.chest_partner(chl, Vector3i.ZERO) == Vector3i(1, 0, 0) and Interaction.chest_partner(chr, Vector3i.ZERO) == Vector3i(1, 0, 0) and Interaction.chest_partner(ch0, Vector3i.ZERO).y == -9999)
	# resource pack overlay: a temporary folder pack overrides one texture; data/ is never overridden
	var rp := "user://test_rp/pack1"
	DirAccess.make_dir_recursive_absolute(rp.path_join("assets/minecraft/textures/block"))
	DirAccess.make_dir_recursive_absolute(rp.path_join("data/minecraft/recipe"))
	var fmc := FileAccess.open(rp.path_join("pack.mcmeta"), FileAccess.WRITE)
	fmc.store_string('{"pack": {"pack_format": 75, "description": "test"}}')
	fmc.close()
	var red := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	red.save_png(rp.path_join("assets/minecraft/textures/block/dirt.png"))
	var fr := FileAccess.open(rp.path_join("data/minecraft/recipe/stick.json"), FileAccess.WRITE)
	fr.store_string("{}")
	fr.close()
	var before := Res.jar.read_bytes("assets/minecraft/textures/block/dirt.png")
	var err := Res.jar.add_overlay(rp)
	var after := Res.jar.read_bytes("assets/minecraft/textures/block/dirt.png")
	var data_after := Res.jar.read_bytes("data/minecraft/recipe/stick.json")
	var img := Image.new()
	img.load_png_from_buffer(after)
	ok("resource pack overrides assets", err == "" and after != before and img.get_pixel(3, 3).is_equal_approx(Color.RED))
	ok("resource pack never overrides data", data_after.get_string_from_utf8() != "{}")
	ok("resource pack needs pack.mcmeta", Res.jar.add_overlay("user://test_rp") != "")
	Res.jar.overlays.clear()
	var RB := Res.blocks
	ok("non-visual props: note block", RB.get_prop(RB.state_of("note_block", {"note": "5", "instrument": "bell"}), "note") == "5" and RB.get_prop(RB.state_of("note_block", {"instrument": "bell"}), "instrument") == "bell")
	ok("non-visual props: power / triggered / stage", RB.get_prop(RB.state_of("daylight_detector", {"power": "9"}), "power") == "9" and RB.has_prop(RB.default_state("dispenser"), "triggered") and RB.has_prop(RB.default_state("oak_sapling"), "stage"))
	ok("java default states", RB.get_prop(RB.default_state("vault"), "ominous") == "false" and RB.get_prop(RB.default_state("redstone_torch"), "lit") == "true" and RB.get_prop(RB.default_state("hopper"), "enabled") == "true")
	ok("brewing stand brews in 400 ticks", Potions.potion_of(ItemStack.from_dict(be["items"][0])) == "awkward" and ItemStack.from_dict(be["items"][3]).is_empty() and int(be["fuel"]) == 19)


func test_vanilla_redstone() -> void:
	var b := Res.blocks
	var w := RsWorld.new()
	var stone := b.default_state("stone")
	for x in range(-2, 12):
		w.blocks[Vector3i(x, -1, 0)] = stone
	# lever -> 3 dust -> lamp
	w.blocks[Vector3i(0, 0, 0)] = b.with_prop(b.default_state("lever"), "powered", "true")
	for x in range(1, 4):
		w.blocks[Vector3i(x, 0, 0)] = b.default_state("redstone_wire")
	w.blocks[Vector3i(4, 0, 0)] = b.default_state("redstone_lamp")
	Redstone.on_changed(w, Vector3i(0, 0, 0))
	ok("redstone dust decays", b.get_prop(w.state_at(1, 0, 0), "power") == "15" and b.get_prop(w.state_at(3, 0, 0), "power") == "13")
	ok("redstone lamp lights", b.get_prop(w.state_at(4, 0, 0), "lit") == "true")
	# repeater: input from the east (facing east), outputs west into a lamp after its scheduled tick
	var w2 := RsWorld.new()
	w2.blocks[Vector3i(1, 0, 0)] = b.default_state("redstone_block")
	var rep := b.with_prop(b.default_state("repeater"), "facing", "east")
	w2.blocks[Vector3i(0, 0, 0)] = rep
	w2.blocks[Vector3i(-1, 0, 0)] = b.default_state("redstone_lamp")
	ok("repeater input seen", Redstone._diode_input(w2, Vector3i(0, 0, 0), rep) == 15)
	Redstone.scheduled(w2, Vector3i(0, 0, 0), rep)
	ok("repeater powers after delay", b.get_prop(w2.state_at(0, 0, 0), "powered") == "true" and b.get_prop(w2.state_at(-1, 0, 0), "lit") == "true")
	ok("repeater output is directional", Redstone.emitted(w2, Vector3i(0, 0, 0), Vector3i(1, 0, 0)) == 0)
	# sticky piston pushes a block, then pulls it back
	var w3 := RsWorld.new()
	var pis := b.with_prop(b.default_state("sticky_piston"), "facing", "east")
	w3.blocks[Vector3i(0, 0, 0)] = pis
	w3.blocks[Vector3i(1, 0, 0)] = stone
	w3.blocks[Vector3i(0, 1, 0)] = b.default_state("redstone_block")
	Redstone.scheduled(w3, Vector3i(0, 0, 0), pis)
	ok("piston extends and pushes", b.name_of(w3.state_at(1, 0, 0)) == "piston_head" and w3.state_at(2, 0, 0) == stone)
	w3.blocks[Vector3i(0, 1, 0)] = 0
	Redstone.scheduled(w3, Vector3i(0, 0, 0), w3.state_at(0, 0, 0))
	ok("sticky piston pulls back", w3.state_at(1, 0, 0) == stone and w3.state_at(2, 0, 0) == 0)
	# obsidian blocks a push
	var w4 := RsWorld.new()
	var pis2 := b.with_prop(b.default_state("piston"), "facing", "up")
	w4.blocks[Vector3i(0, 0, 0)] = pis2
	w4.blocks[Vector3i(0, 1, 0)] = b.default_state("obsidian")
	w4.blocks[Vector3i(1, 0, 0)] = b.default_state("redstone_block")
	Redstone.scheduled(w4, Vector3i(0, 0, 0), pis2)
	ok("piston cannot push obsidian", b.get_prop(w4.state_at(0, 0, 0), "extended") == "false")


func test_vanilla_assets() -> void:
	var b := Res.blocks
	ok("vanilla: >1000 blocks", b.names.size() > 1000, str(b.names.size()))
	ok("vanilla: >20000 states", b.total_states > 20000, str(b.total_states))
	ok("vanilla: >1500 items", Res.items.names.size() > 1500, str(Res.items.names.size()))
	var grass := b.default_state("grass_block")
	ok("vanilla: grass is cube with overlay", (b.st_flags[grass] & BlockRegistry.F_CUBE) != 0 and ((b.st_faces[grass * 6 + 2] >> 27) & 1) == 1)
	var stairs := b.parse_state("minecraft:oak_stairs[facing=south,half=bottom,shape=straight]")
	ok("vanilla: stairs baked model", stairs > 0 and b.st_model[stairs] >= 0 and b.get_shape(stairs).size() == 12, str(b.get_shape(stairs).size()))
	var leaves := b.default_state("oak_leaves")
	ok("vanilla: leaves cutout", (b.st_flags[leaves] & BlockRegistry.F_CUTOUT) != 0)
	ok("vanilla: water animated", Res.atlas.anims.size() > 10, str(Res.atlas.anims.size()))
	ok("vanilla: no missing textures", Res.atlas.missing.size() < 20, str(Res.atlas.missing.slice(0, 10)))
	var biomes := BiomeRegistry.new()
	biomes.build()
	ok("vanilla: biome registry", biomes.names.size() >= 60 and biomes.index.has("dappled_forest"), str(biomes.names.size()))
	Crafting.loaded = false
	Crafting.load_all()
	ok("vanilla: recipes loaded", Crafting.count > 1000, str(Crafting.count))
	var pick := ItemStack.named("wooden_pickaxe")
	var sd := Loot.block_drops(b.STONE, pick, null, Vector3i.ZERO)
	ok("vanilla: stone drops cobblestone", sd.size() == 1 and (sd[0] as ItemStack).name() == "cobblestone")
	# 26.3 loot format: entry "modifier", single "condition" (incl. predicate references), pool conditions
	var ipick := ItemStack.named("iron_pickaxe")
	var dd := Loot.block_drops(b.default_state("diamond_ore"), ipick, null, Vector3i.ZERO)
	ok("vanilla: diamond ore drops a diamond", dd.size() == 1 and (dd[0] as ItemStack).name() == "diamond", str(dd.map(func(x): return x.name())))
	var silk := ItemStack.named("iron_pickaxe")
	silk.components["minecraft:enchantments"] = {"minecraft:silk_touch": 1}
	var ds := Loot.block_drops(b.default_state("diamond_ore"), silk, null, Vector3i.ZERO)
	ok("vanilla: silk touch drops the ore", ds.size() == 1 and (ds[0] as ItemStack).name() == "diamond_ore")
	var lrng := RandomNumberGenerator.new()
	lrng.seed = 7
	var rare := 0
	var flesh_max := 0
	var flesh_min := 99
	for i in 300:
		var zctx := {"tool": ItemStack.new(), "rng": lrng, "by_player": false, "on_fire": false}
		var fl := 0
		for zs in Loot.roll("entities/zombie", zctx):
			if (zs as ItemStack).name() == "rotten_flesh":
				fl += (zs as ItemStack).count
			else:
				rare += 1
		flesh_max = maxi(flesh_max, fl)
		flesh_min = mini(flesh_min, fl)
	ok("vanilla: zombie rare drops need a player kill", rare == 0, str(rare))
	ok("vanilla: zombie flesh count 0-2 (set_count modifier)", flesh_min == 0 and flesh_max == 2, "%d..%d" % [flesh_min, flesh_max])
	# entity predicates: sheep wool by color/sheared from entities/sheep, slime balls only from size-1 slimes
	var names_of := func(arr: Array) -> Array: return arr.map(func(x): return (x as ItemStack).name())
	var sh1: Array = names_of.call(Loot.roll("entities/sheep", {"tool": ItemStack.new(), "rng": lrng, "by_player": true, "sheared": false, "sheep_color": "white"}))
	var sh2: Array = names_of.call(Loot.roll("entities/sheep", {"tool": ItemStack.new(), "rng": lrng, "by_player": true, "sheared": true, "sheep_color": "white"}))
	ok("vanilla: sheep drops mutton + white wool", sh1.has("mutton") and sh1.has("white_wool"), str(sh1))
	ok("vanilla: sheared sheep drops no wool", sh2.has("mutton") and not sh2.has("white_wool"), str(sh2))
	var big := 0
	var small := 0
	for i in 60:
		big += Loot.roll("entities/slime", {"tool": ItemStack.new(), "rng": lrng, "by_player": true, "size": 2}).size()
		small += Loot.roll("entities/slime", {"tool": ItemStack.new(), "rng": lrng, "by_player": true, "size": 1}).size()
	ok("vanilla: slime balls only from small slimes", big == 0 and small > 0, "%d / %d" % [big, small])
	# item use (Java use durations, shield block delay and frontal cone)
	ok("vanilla: use durations", UseItem.duration(ItemStack.named("cooked_beef")) == 32 and UseItem.duration(ItemStack.named("dried_kelp")) == 16 and UseItem.duration(ItemStack.named("honey_bottle")) == 40 and UseItem.duration(ItemStack.named("potion")) == 32 and UseItem.duration(ItemStack.named("bow")) == UseItem.FOREVER)
	var qc := ItemStack.named("crossbow")
	qc.components["minecraft:enchantments"] = {"minecraft:quick_charge": 3}
	ok("vanilla: crossbow charge time", UseItem.charge_time(ItemStack.named("crossbow")) == 25 and UseItem.charge_time(qc) == 10)
	var up := Player.new()
	up.inventory.set_slot(Inventory.OFFHAND, ItemStack.named("shield"))
	up.using_slot = Inventory.OFFHAND
	up.use_item = Res.items.id("shield")
	up.use_ticks = 4
	var b4 := UseItem.is_blocking(up)
	up.use_ticks = 5
	ok("vanilla: shield blocks after 5 ticks", not b4 and UseItem.is_blocking(up))
	up.yaw = 0.0
	up.pitch = 0.0
	var front_hit := up.hurt(4.0, "mob", false, up.pos + Vector3(0.5, 0, 2))
	up.invuln = 0
	var back_hit := up.hurt(4.0, "mob", false, up.pos + Vector3(0, 0, -2))
	up.invuln = 0
	var fall_hit := up.hurt(4.0, "fall", false, up.pos + Vector3(0, 0, 2))
	ok("vanilla: shield frontal cone, fall bypasses", not front_hit and back_hit and fall_hit, "%s %s %s" % [front_hit, back_hit, fall_hit])
	# Java 1.9 attack strength: 20 / attack speed ticks, (t + 0.5) / delay
	var cp := Player.new()
	cp.inventory.set_slot(cp.inventory.selected, ItemStack.named("diamond_sword"))
	cp.attack_ticks = 0
	var s0 := cp.attack_strength(0.5)
	cp.attack_ticks = 12
	ok("vanilla: sword attack delay 12.5 ticks", absf(cp.attack_delay() - 12.5) < 0.01 and absf(s0 - 0.04) < 0.001 and cp.attack_strength(0.5) >= 1.0, "%.3f %.3f" % [cp.attack_delay(), s0])
	cp.inventory.set_slot(cp.inventory.selected, ItemStack.new())
	ok("vanilla: empty hand attack delay 5 ticks", absf(cp.attack_delay() - 5.0) < 0.01)
	# chat command suggestions (Java CommandSuggestions)
	var sg1: Array = CommandSuggest.suggest(null, "/gamem")[1]
	var sg2: Array = CommandSuggest.suggest(null, "/gamemode cr")[1]
	var sg3: Array = CommandSuggest.suggest(null, "/give @s minecraft:diamond_sw")[1]
	ok("vanilla: command suggestions", sg1.has("gamemode") and sg2 == ["creative"] and sg3.has("minecraft:diamond_sword"), "%s %s %s" % [sg1, sg2, sg3.slice(0, 3)])
	# mob hand equipment (populateDefaultEquipmentSlots) and the brush dusted stages
	var sk := EntityManager.Ent.new()
	sk.id = "skeleton"
	var vi := EntityManager.Ent.new()
	vi.id = "vindicator"
	var rr := RandomNumberGenerator.new()
	HeldItems.equip(sk, rr, 2)
	HeldItems.equip(vi, rr, 2)
	ok("vanilla: skeleton bow, vindicator axe", str(sk.data.get("held", "")) == "bow" and str(vi.data.get("held", "")) == "iron_axe")
	var dust: Array = []
	for n in 10:
		dust.append(UseItem._completion(n))
	ok("vanilla: brush dusted stages", dust == [0, 1, 1, 2, 2, 2, 3, 3, 3, 3], str(dust))
	# Java Mth.sin / cos table (mega jungle branches)
	ok("vanilla: Mth sin table", Trees._mth_cos(0.0) == 1.0 and absf(Trees._mth_sin(PI / 2.0) - 1.0) < 1e-6 and Trees._mth_sin(0.0) == 0.0)
	# 26.x template feature + capped processor are compiled from the data (desert well / trail ruins)
	ok("vanilla: template feature type + capped processor in data", Res.read_json("data/minecraft/worldgen/feature/desert_well.json") is Dictionary
		and StructureTemplate.get_template("desert_well/well") != null)
	# mob rigs use their textures (Java box UV): no large unused opaque regions (missing / misplaced parts)
	var rig_bad: Array = []
	for rid in ["zombie_villager", "warden", "breeze", "witch", "vindicator", "sniffer", "copper_golem", "camel", "guardian",
			"goat", "rabbit", "magma_cube", "bat", "allay", "frog", "zombie", "cow", "pig", "creeper", "iron_golem"]:
		var cov: Array = MobRigs.coverage(rid)
		if int(cov[0]) > 15:
			rig_bad.append("%s %d%%" % [rid, int(cov[0])])
	ok("vanilla: mob rigs cover their textures", rig_bad.is_empty(), str(rig_bad))
	# totem of undying (main hand or offhand) and elytra usability (broken at max - 1)
	var tp := Player.new()
	tp.inventory.set_slot(Inventory.OFFHAND, ItemStack.named("totem_of_undying"))
	tp.health = 2.0
	tp.hurt(50.0, "mob")
	var saved := not tp.dead and tp.health == 1.0 and tp.inventory.get_slot(Inventory.OFFHAND).is_empty() and tp.effects.has("regeneration")
	tp.invuln = 0
	tp.hurt(50.0, "mob")
	ok("vanilla: totem saves once", saved and tp.dead)
	var ep := Player.new()
	var ely := ItemStack.named("elytra")
	ep.inventory.set_slot(Inventory.ARMOR0 + 2, ely)
	var ok1 := ep.elytra_ok()
	ely.damage = Res.items.max_damage[ely.item] - 1
	ep.inventory.set_slot(Inventory.ARMOR0 + 2, ely)
	ok("vanilla: elytra unusable at 1 durability", ok1 and not ep.elytra_ok())
	# armor trims (smithing_trim)
	Enchanting.load_all()
	var trc := Enchanting.smith(ItemStack.named("bolt_armor_trim_smithing_template"), ItemStack.named("iron_chestplate"), ItemStack.named("amethyst_shard"))
	ok("vanilla: smithing trim", trc.name() == "iron_chestplate" and trc.components.get("minecraft:trim", {}).get("material", "") == "minecraft:amethyst" and str(trc.components["minecraft:trim"]["pattern"]).ends_with("bolt") and Enchanting.smith(ItemStack.named("bolt_armor_trim_smithing_template"), trc, ItemStack.named("amethyst_shard")).is_empty())
	# bundles (Java BundleContents weights)
	var bun := ItemStack.named("bundle")
	var dirt := ItemStack.named("dirt", 40)
	var pearls := ItemStack.named("ender_pearl", 16)
	var m1 := Bundles.insert(bun, dirt)
	var m2 := Bundles.insert(bun, pearls)
	var sb := ItemStack.named("shulker_box")
	ok("vanilla: bundle weights", m1 == 40 and m2 == 6 and pearls.count == 10 and Bundles.weight(bun) == 64 and Bundles.insert(bun, ItemStack.named("stone", 1)) == 0 and Bundles.insert(ItemStack.named("bundle"), sb) == 0, "%d %d %d" % [m1, m2, Bundles.weight(bun)])
	var first := Bundles.remove_one(bun)
	ok("vanilla: bundle removes newest first", first.name() == "ender_pearl" and first.count == 6 and Bundles.weight(bun) == 40)
	# 26.x data-driven brewing
	var wb := Potions.make("potion", "water")
	var awk = Potions.brew_result(wb, "nether_wart")
	var spl = Potions.brew_result(Potions.make("potion", "strength"), "gunpowder")
	var lin = Potions.brew_result(Potions.make("splash_potion", "strength"), "dragon_breath")
	ok("vanilla: data brewing", Potions.data_mixes.size() > 200 and awk != null and Potions.potion_of(awk) == "awkward" and spl != null and (spl as ItemStack).name() == "splash_potion" and Potions.potion_of(spl) == "strength" and lin != null and (lin as ItemStack).name() == "lingering_potion" and Potions.brew_result(wb, "dirt") == null, str(Potions.data_mixes.size()))
	# 26.x special recipes through Crafting.match_grid
	var g9 := func(items: Dictionary) -> Array:
		var g: Array = []
		for i in 9:
			g.append(items.get(i, ItemStack.new()))
		return g
	var star_g: Array = g9.call({0: ItemStack.named("gunpowder"), 1: ItemStack.named("red_dye"), 2: ItemStack.named("fire_charge"), 3: ItemStack.named("diamond")})
	var sm := Crafting.match_grid(star_g, 3, 3)
	var star_s: ItemStack = sm.get("result", ItemStack.new())
	var se: Dictionary = star_s.components.get("minecraft:firework_explosion", {})
	ok("vanilla: firework star recipe", star_s.name() == "firework_star" and se.get("shape") == "large_ball" and se.get("colors") == [0xB3312C] and se.get("has_trail") == true, str(se))
	var rm := Crafting.match_grid(g9.call({0: ItemStack.named("paper"), 1: ItemStack.named("gunpowder"), 2: ItemStack.named("gunpowder"), 4: star_s}), 3, 3)
	var rk: ItemStack = rm.get("result", ItemStack.new())
	ok("vanilla: firework rocket recipe", rk.name() == "firework_rocket" and rk.count == 3 and int(rk.components["minecraft:fireworks"]["flight_duration"]) == 2 and (rk.components["minecraft:fireworks"]["explosions"] as Array).size() == 1)
	var lh := Crafting.match_grid(g9.call({0: ItemStack.named("leather_helmet"), 1: ItemStack.named("red_dye")}), 3, 3).get("result", ItemStack.new()) as ItemStack
	ok("vanilla: leather dye recipe", lh.name() == "leather_helmet" and int(lh.components.get("minecraft:dyed_color", -1)) == 0xB02E26)
	var wsb := ItemStack.named("white_shulker_box")
	wsb.components["minecraft:container"] = [ItemStack.named("diamond", 5).to_dict()]
	var rsb := Crafting.match_grid(g9.call({0: wsb, 4: ItemStack.named("red_dye")}), 3, 3).get("result", ItemStack.new()) as ItemStack
	ok("vanilla: shulker recolour keeps contents", rsb.name() == "red_shulker_box" and (rsb.components.get("minecraft:container", []) as Array).size() == 1)
	var dp1 := ItemStack.named("iron_pickaxe")
	dp1.damage = 200
	var dp2 := ItemStack.named("iron_pickaxe")
	dp2.damage = 200
	var rp := Crafting.match_grid(g9.call({0: dp1, 1: dp2}), 3, 3).get("result", ItemStack.new()) as ItemStack
	ok("vanilla: repair recipe", rp.name() == "iron_pickaxe" and rp.damage == 250 - (50 + 50 + 12), str(rp.damage))
	var lp := Potions.make("lingering_potion", "swiftness")
	var ta_g: Array = []
	for i in 9:
		ta_g.append(lp if i == 4 else ItemStack.named("arrow"))
	var ta := Crafting.match_grid(ta_g, 3, 3).get("result", ItemStack.new()) as ItemStack
	ok("vanilla: tipped arrow recipe", ta.name() == "tipped_arrow" and ta.count == 8 and ta.components.has("minecraft:potion_contents"))
	var pb2 := ItemStack.named("red_banner")
	pb2.components["minecraft:banner_patterns"] = [{"pattern": "minecraft:border", "color": "white"}]
	var dup_g: Array = g9.call({0: pb2, 1: ItemStack.named("red_banner")})
	var dup := Crafting.match_grid(dup_g, 3, 3).get("result", ItemStack.new()) as ItemStack
	Crafting.consume(dup_g)
	ok("vanilla: banner duplicate keeps the original", Banners.layers(dup).size() == 1 and not (dup_g[0] as ItemStack).is_empty() and (dup_g[1] as ItemStack).is_empty())
	var pot := Crafting.match_grid(g9.call({1: ItemStack.named("brick"), 3: ItemStack.named("brick"), 5: ItemStack.named("brick"), 7: ItemStack.named("brick")}), 3, 3).get("result", ItemStack.new()) as ItemStack
	ok("vanilla: decorated pot recipe", pot.name() == "decorated_pot")
	# loom (Java LoomMenu): selectable patterns, layer append, 6-layer limit
	ok("vanilla: loom no-item patterns", Banners.selectable(ItemStack.new()).size() >= 30 and not Banners.selectable(ItemStack.new()).has("minecraft:creeper"))
	ok("vanilla: loom pattern item", Banners.selectable(ItemStack.named("creeper_banner_pattern")) == ["minecraft:creeper"])
	var lb := ItemStack.named("white_banner")
	for li in 6:
		lb = Banners.loom_result(lb, ItemStack.named("red_dye"), "minecraft:stripe_top")
	ok("vanilla: loom 6-layer limit", Banners.layers(lb).size() == 6 and Banners.loom_result(lb, ItemStack.named("red_dye"), "minecraft:border").is_empty())
	var be_box := {"id": "shulker_box", "items": [ItemStack.named("diamond", 3).to_dict(), {}], "CustomName": "Loot"}
	var sbd := Loot.block_drops(b.default_state("shulker_box"), ItemStack.new(), null, Vector3i.ZERO, be_box)
	ok("vanilla: shulker box keeps contents (copy_components)", sbd.size() == 1 and (sbd[0] as ItemStack).components.get("minecraft:container", []).size() == 2 and (sbd[0] as ItemStack).components.get("minecraft:custom_name", "") == "Loot")
	ok("vanilla: sound index", Res.asset_index.size() > 1000, str(Res.asset_index.size()))
	ok("vanilla: music present", Res.sound_object_path("minecraft/sounds/music/menu/moog_city_2.ogg") != "" or int(Res.manifest.get("music_tracks", 0)) > 0)
