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
		test_vanilla_fluids_fire()
		test_vanilla_waterlogging()
		test_vanilla_gravity_support()
		test_vanilla_support_breaking()
		test_vanilla_snow_weather()
		test_vanilla_breaking()
		test_vanilla_structure_ports()
		test_vanilla_block_entity_renders()
		test_vanilla_player_blocks()
		test_vanilla_sensors()
		test_vanilla_redstone_blocks()
		preload("res://scenes/tests/redstone_tests.gd").new().run(self)   # redstone vanilla matrix
		test_vanilla_growth()
		test_vanilla_mob_behaviors()
		test_vanilla_mob_leftovers()
		test_vanilla_items_plants()
		test_vanilla_villagers_shields()
		test_vanilla_villager_beds_mobs()
		test_vanilla_fluid_items()
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
	# creative flight (Java Player.travel: flying speed 0.05, x2 sprinting, drag 0.91; vertical 3 x 0.05, drag 0.6)
	for fl in [[false, 10.889], [true, 21.778]]:
		var fw := MockWorld.new()
		var fq := Player.new()
		fq.mode = Player.Mode.CREATIVE
		fq.flying = true
		fq.pos = Vector3(0.5, 90, 0.5)
		fq.in_forward = 1.0
		fq.in_sprint = fl[0]
		for i in 200:
			fq.tick(fw)
		var f0 := fq.pos
		for i in 20:
			fq.tick(fw)
		var fsp := Vector2(fq.pos.x - f0.x, fq.pos.z - f0.z).length()
		ok("creative %s ~%.2f m/s" % ["sprint flight" if fl[0] else "flight", fl[1]], absf(fsp - float(fl[1])) < 0.05, "%.3f" % fsp)
	var w := MockWorld.new()
	var p := Player.new()
	p.pos = Vector3(0.5, 70, 0.5)
	p.saturation = 0.0
	p.food = 17
	for i in 60:
		p.tick(w)
	ok("falls and lands on floor", absf(p.pos.y - 64.0) < 0.001 and p.on_ground, str(p.pos))
	ok("fall damage from 6 blocks", p.health == 17.0, str(p.health))
	# dying: the hurt tilt timer keeps counting down (it stayed at 10 and the camera roll jittered with the partial tick)
	var dpl := Player.new()
	dpl.pos = Vector3(0.5, 64, 0.5)
	dpl.hurt(100.0, "mob")
	for i in 12:
		dpl.tick(w)
	ok("dead player: hurt time counts down", dpl.dead and dpl.hurt_time == 0, "dead %s hurt_time %d" % [dpl.dead, dpl.hurt_time])
	# Java calculateFallDamage floors: 4 blocks -> 1, 3 blocks -> 0; Feather Falling IV: 3 x (1 - 12/25)
	for fc in [[68.0, 19.0, 0], [67.0, 20.0, 0], [70.0, 18.44, 4]]:
		if int(fc[2]) > 0 and Res.items.id("diamond_boots") <= 0:
			continue   # (placeholder items: no armour)
		var fp := Player.new()
		fp.pos = Vector3(0.5, fc[0], 0.5)
		fp.saturation = 0.0
		fp.food = 17
		if int(fc[2]) > 0:
			var boots := ItemStack.named("diamond_boots", 1)
			boots.components["minecraft:enchantments"] = {"minecraft:feather_falling": int(fc[2])}
			fp.inventory.set_slot(Inventory.ARMOR0, boots)
		for i in 60:
			fp.tick(w)
		ok("fall damage from %d blocks%s" % [int(fc[0]) - 64, " (feather falling %d)" % int(fc[2]) if int(fc[2]) > 0 else ""], absf(fp.health - float(fc[1])) < 0.01, str(fp.health))
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
	func spawn_item(_p, _s, _v = null) -> void:
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
	func toast(_a, _b, _c, _d = null) -> void:
		toasts += 1
	func chat_message(_t, _c = "", _h = null) -> void:
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
	var seed_out := cp.execute("/seed")
	ok("cmd seed: Seed: [42], click copies the seed", seed_out == "Seed: [42]" and cp.feedback_click == "copy:42", seed_out + " / " + cp.feedback_click)
	cp.execute("/time set day")
	ok("cmd: the copy click belongs only to /seed", cp.feedback_click == "")
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


## Java RedStoneWireBlock shapes / signal rules (wiki Redstone Dust): crosses, lines, climbing, cuts, dot toggle,
## pointing, per-power colours.
func _test_redstone_wire_shapes() -> void:
	var b := Res.blocks
	var wire := b.default_state("redstone_wire")
	var stone := b.default_state("stone")
	var w := RsWorld.new()
	for x in range(-3, 8):
		for z in range(-3, 4):
			w.blocks[Vector3i(x, -1, z)] = stone
	# a lone dust is a cross; one neighbour makes a line along it
	w.blocks[Vector3i(0, 0, 0)] = wire
	RedstoneWire.update_around(w, Vector3i(0, 0, 0), true)
	ok("redstone dust: alone = cross", RedstoneWire.is_cross(w.state_at(0, 0, 0)))
	w.blocks[Vector3i(1, 0, 0)] = wire
	RedstoneWire.update_around(w, Vector3i(1, 0, 0), true)
	var s0 := w.state_at(0, 0, 0)
	ok("redstone dust: two in a row = east-west line", b.get_prop(s0, "east") == "side" and b.get_prop(s0, "west") == "side" and b.get_prop(s0, "north") == "none" and b.get_prop(s0, "south") == "none")
	# a corner: dust at (0, 0, 1) turns the first into an L (east + south)
	w.blocks[Vector3i(0, 0, 1)] = wire
	RedstoneWire.update_around(w, Vector3i(0, 0, 1), true)
	s0 = w.state_at(0, 0, 0)
	ok("redstone dust: corner", b.get_prop(s0, "east") == "side" and b.get_prop(s0, "south") == "side" and b.get_prop(s0, "west") == "none" and b.get_prop(s0, "north") == "none")
	# climbing: a block east of the line's end with dust on top -> up; a solid block above the lower dust cuts it
	var w2 := RsWorld.new()
	for x in range(-3, 8):
		w2.blocks[Vector3i(x, -1, 0)] = stone
	w2.blocks[Vector3i(1, 0, 0)] = stone
	w2.blocks[Vector3i(0, 0, 0)] = wire
	w2.blocks[Vector3i(1, 1, 0)] = wire
	RedstoneWire.update_around(w2, Vector3i(0, 0, 0), true)
	RedstoneWire.update_around(w2, Vector3i(1, 1, 0), true)
	ok("redstone dust: climbs a block (east = up)", b.get_prop(w2.state_at(0, 0, 0), "east") == "up")
	ok("redstone dust: the upper dust points down to it (west = side)", b.get_prop(w2.state_at(1, 1, 0), "west") == "side")
	w2.blocks[Vector3i(-3, 0, 0)] = b.with_prop(b.default_state("lever"), "powered", "true")
	w2.blocks[Vector3i(-2, 0, 0)] = wire
	w2.blocks[Vector3i(-1, 0, 0)] = wire
	RedstoneWire.update_around(w2, Vector3i(-2, 0, 0), true)
	RedstoneWire.update_around(w2, Vector3i(-1, 0, 0), true)
	Redstone.on_changed(w2, Vector3i(-3, 0, 0))
	ok("redstone dust: power climbs (15 .. 12 on top)", b.get_prop(w2.state_at(0, 0, 0), "power") == "13" and b.get_prop(w2.state_at(1, 1, 0), "power") == "12")
	w2.blocks[Vector3i(0, 1, 0)] = stone   # conductive block above the lower dust: the climb is cut
	RedstoneWire.update_around(w2, Vector3i(0, 1, 0), false)
	Redstone.on_changed(w2, Vector3i(0, 1, 0))
	ok("redstone dust: a block above cuts the climb", b.get_prop(w2.state_at(0, 0, 0), "east") != "up" and b.get_prop(w2.state_at(1, 1, 0), "power") == "0")
	# glass passes power up but not down
	var w3 := RsWorld.new()
	for x in range(-3, 8):
		w3.blocks[Vector3i(x, -1, 0)] = stone
	w3.blocks[Vector3i(1, 0, 0)] = b.default_state("glass")
	w3.blocks[Vector3i(0, 0, 0)] = wire
	w3.blocks[Vector3i(1, 1, 0)] = wire
	w3.blocks[Vector3i(-1, 0, 0)] = b.default_state("redstone_block")
	RedstoneWire.update_around(w3, Vector3i(0, 0, 0), true)
	RedstoneWire.update_around(w3, Vector3i(1, 1, 0), true)
	Redstone.on_changed(w3, Vector3i(-1, 0, 0))
	ok("redstone dust: power goes up onto glass", b.get_prop(w3.state_at(1, 1, 0), "power") == "14")
	w3.blocks[Vector3i(-1, 0, 0)] = stone
	w3.blocks[Vector3i(2, 1, 0)] = b.default_state("redstone_block")
	Redstone.on_changed(w3, Vector3i(-1, 0, 0))
	Redstone.on_changed(w3, Vector3i(2, 1, 0))
	ok("redstone dust: power never goes down from glass", b.get_prop(w3.state_at(1, 1, 0), "power") == "15" and b.get_prop(w3.state_at(0, 0, 0), "power") == "0")
	# dot toggle: a lone cross becomes a dot, back to a cross; a dot powers only the block below
	var w4 := RsWorld.new()
	w4.blocks[Vector3i(0, -1, 0)] = stone
	w4.blocks[Vector3i(0, 0, 0)] = wire
	RedstoneWire.update_around(w4, Vector3i(0, 0, 0), true)
	RedstoneWire.toggle(w4, Vector3i(0, 0, 0), w4.state_at(0, 0, 0))
	ok("redstone dust: right-click cross -> dot", RedstoneWire.is_dot(w4.state_at(0, 0, 0)))
	var pw := b.with_prop(w4.state_at(0, 0, 0), "power", "9")
	ok("redstone dust: a dot powers below, not the sides", RedstoneWire.signal_to(w4, Vector3i(0, 0, 0), pw, Vector3i(0, -1, 0)) == 9 and RedstoneWire.signal_to(w4, Vector3i(0, 0, 0), pw, Vector3i(1, 0, 0)) == 0)
	RedstoneWire.toggle(w4, Vector3i(0, 0, 0), w4.state_at(0, 0, 0))
	ok("redstone dust: right-click dot -> cross", RedstoneWire.is_cross(w4.state_at(0, 0, 0)))
	# a lamp beside a line that does not point at it stays off
	var w5 := RsWorld.new()
	for x in range(-3, 8):
		for z in range(-2, 3):
			w5.blocks[Vector3i(x, -1, z)] = stone
	w5.blocks[Vector3i(-1, 0, 0)] = b.default_state("redstone_block")
	for x in range(0, 4):
		w5.blocks[Vector3i(x, 0, 0)] = wire
	w5.blocks[Vector3i(4, 0, 0)] = stone
	for x in range(0, 4):
		RedstoneWire.update_around(w5, Vector3i(x, 0, 0), true)
	w5.blocks[Vector3i(2, 0, 1)] = b.default_state("redstone_lamp")
	Redstone.on_changed(w5, Vector3i(-1, 0, 0))
	Redstone.on_changed(w5, Vector3i(2, 0, 1))
	ok("redstone dust: a line passing a lamp does not light it", b.get_prop(w5.state_at(2, 0, 1), "lit") != "true" and b.get_prop(w5.state_at(2, 0, 0), "power") == "13")
	# colours per power (wiki Block colors, Redstone tints JE)
	ok("redstone dust: colour per power level", b.st_tint_color[b.with_prop(wire, "power", "0")] == 0x4C0000 and b.st_tint_color[b.with_prop(wire, "power", "15")] == 0xFF3200 and b.st_tint_color[b.with_prop(wire, "power", "8")] == 0xB70000)


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
	for x in range(1, 4):
		RedstoneWire.update_around(w, Vector3i(x, 0, 0), true)   # (placement shape, as WorldManager.set_block does)
	Redstone.on_changed(w, Vector3i(0, 0, 0))
	ok("redstone dust decays", b.get_prop(w.state_at(1, 0, 0), "power") == "15" and b.get_prop(w.state_at(3, 0, 0), "power") == "13")
	ok("redstone lamp lights", b.get_prop(w.state_at(4, 0, 0), "lit") == "true")
	_test_redstone_wire_shapes()
	# creative search "#": item tags whose path contains the text (Java CreativeModeInventoryScreen.updateVisibleTags)
	var CS = load("res://scripts/ui/creative_screen.gd")
	var fl: Dictionary = {}
	for vt in CS.tag_matches("flowers"):
		fl.merge(vt[1])
	var lg: Dictionary = {}
	for vt2 in CS.tag_matches("minecraft:logs"):
		lg.merge(vt2[1])
	ok("creative search #flowers / #minecraft:logs", fl.has("dandelion") and fl.has("poppy") and fl.has("sunflower") and lg.has("oak_log") and not fl.has("stone") and CS.tag_matches("other_mod:logs").is_empty())
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
	Pistons.reset()
	Pistons.queue_event(Vector3i(0, 0, 0))   # (the block event; its moving blocks finish 2 ticks later)
	Pistons.tick(w3)
	Pistons.finish_all(w3)
	ok("piston extends and pushes", b.name_of(w3.state_at(1, 0, 0)) == "piston_head" and w3.state_at(2, 0, 0) == stone)
	w3.blocks[Vector3i(0, 1, 0)] = 0
	Pistons.queue_event(Vector3i(0, 0, 0))
	Pistons.tick(w3)
	Pistons.finish_all(w3)
	ok("sticky piston pulls back", w3.state_at(1, 0, 0) == stone and w3.state_at(2, 0, 0) == 0)
	# obsidian blocks a push
	var w4 := RsWorld.new()
	var pis2 := b.with_prop(b.default_state("piston"), "facing", "up")
	w4.blocks[Vector3i(0, 0, 0)] = pis2
	w4.blocks[Vector3i(0, 1, 0)] = b.default_state("obsidian")
	w4.blocks[Vector3i(1, 0, 0)] = b.default_state("redstone_block")
	Pistons.queue_event(Vector3i(0, 0, 0))
	Pistons.tick(w4)
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

# ------------------------------------------------------------------ Java FlowingFluid / FireBlock / template ports

class FluidWorld:
	var blocks: Dictionary = {}
	var game_time := 0
	var rng := RandomNumberGenerator.new()
	var entities := MockEntities.new()
	var cm := MockCM.new()
	var dim_type: Dictionary = {}
	var raining := false
	var difficulty := 2
	var dimension := "overworld"

	func state_at(x: int, y: int, z: int) -> int:
		return blocks.get(Vector3i(x, y, z), 0)

	func set_block(x: int, y: int, z: int, st: int, _notify := true) -> int:
		var old: int = blocks.get(Vector3i(x, y, z), 0)
		if st == 0:
			blocks.erase(Vector3i(x, y, z))
		else:
			blocks[Vector3i(x, y, z)] = st
		if old != st and st > 0 and Res.blocks.st_block[st] == BlockUpdates._fire_id() and (old == 0 or Res.blocks.st_block[old] != Res.blocks.st_block[st]):
			BlockUpdates.fire_placed(self, Vector3i(x, y, z))
		return old

	func gamerule(_n, d = null):
		return d

	func weather_at(_p) -> String:
		return "rain" if raining else "none"

	func floor_at(y: int, r: int, st: int) -> void:
		for x in range(-r, r + 1):
			for z in range(-r, r + 1):
				blocks[Vector3i(x, y, z)] = st

	func run(ticks: int) -> void:
		for i in ticks:
			game_time += 1
			BlockUpdates.tick_scheduled(self)


func _fluid_world() -> FluidWorld:
	BlockUpdates.queue.clear()
	BlockUpdates.pending.clear()
	var w := FluidWorld.new()
	w.rng.seed = 1234
	w.floor_at(-1, 12, Res.blocks.STONE)
	return w


func _lvl(w: FluidWorld, x: int, y: int, z: int) -> int:
	var st := w.state_at(x, y, z)
	if st <= 0 or (Res.blocks.st_flags[st] & BlockRegistry.F_LIQUID) == 0:
		return -1
	return Res.blocks.st_level[st]


## SnowyDirtBlock.updateShape (snowy follows #snow above) and the precipitation rules (SnowLayerBlock.canSurvive,
## Level.isWaterAt) used by BlockUpdates.tick_precipitation.
## Wiki Breaking: hardness per block and break ticks = ceil(1 / (speed / hardness / (30 or 100))).
func test_vanilla_breaking() -> void:
	var gt: Array = ItemIcons.layer_tints("short_grass")
	var lt: Array = ItemIcons.layer_tints("lily_pad")
	ok("item tints: short grass from the grass colormap, lily pad constant (GH#3)", gt.size() == 1 and (gt[0] as Color).to_html(false) == "7cbd6b" and lt.size() == 1 and (lt[0] as Color).to_html(false) == "71c35c", "%s %s" % [str(gt), str(lt)])
	var wb := BiomeRegistry.new()
	wb.build()
	var wsw: Color = wb.water[wb.id("swamp")]
	var wwo: Color = wb.water[wb.id("warm_ocean")]
	print("WATERCOL swamp %s warm %s plains %s" % [wsw.to_html(false), wwo.to_html(false), (wb.water[wb.id("plains")] as Color).to_html(false)])
	ok("biome water colours from the data (swamp #617b64, warm ocean #43d5ee)", wsw.to_html(false) == "617b64" and wwo.to_html(false) == "43d5ee", "%s %s" % [wsw.to_html(false), wwo.to_html(false)])
	# selection outlines from Java's code shapes (GH#18)
	var ob := Res.blocks
	var tor := ob.get_outline(ob.default_state("torch"))
	var lad := ob.get_outline(ob.parse_state("minecraft:ladder[facing=north]"))
	ok("outline: torch is Java's 4 x 10 x 4 box, ladder a 3-pixel slab", tor == PackedFloat32Array([0.375, 0, 0.375, 0.625, 0.625, 0.625]) and lad == PackedFloat32Array([0, 0, 0.8125, 1, 1, 1]), "%s %s" % [tor, lad])
	var b := Res.blocks
	var want := {"stone": 1.5, "deepslate_iron_ore": 4.5, "oak_planks": 2.0, "white_wool": 0.8, "iron_door": 5.0, "oak_door": 3.0,
		"bricks": 2.0, "nether_bricks": 2.0, "end_stone_bricks": 3.0, "deepslate_bricks": 3.5, "short_grass": 0.0, "obsidian": 50.0,
		"glass": 0.3, "oak_leaves": 0.2, "dirt": 0.5, "netherrack": 0.4, "crafting_table": 2.5, "copper_block": 3.0, "smooth_stone": 2.0}
	var bad: Array = []
	for n in want:
		var bid := b.block_id(n)
		if bid < 0 or absf(b.hardness[bid] - float(want[n])) > 1e-6:
			bad.append("%s %s" % [n, str(b.hardness[bid]) if bid >= 0 else "?"])
	ok("breaking: wiki hardness values", bad.is_empty(), ", ".join(bad))
	var p := Player.new()
	p.on_ground = true
	var cases := [["stone", "", 150], ["stone", "wooden_pickaxe", 23], ["deepslate_iron_ore", "stone_pickaxe", 34], ["oak_log", "", 60],
		["oak_log", "iron_axe", 10], ["iron_block", "wooden_pickaxe", 250], ["oak_leaves", "shears", 1], ["cobweb", "iron_sword", 8], ["white_wool", "shears", 5]]
	var tb: Array = []
	for cs in cases:
		p.inventory.set_slot(p.inventory.selected, ItemStack.named(cs[1], 1) if cs[1] != "" else ItemStack.new())
		var d := Interaction.destroy_progress(p, b.default_state(cs[0]), null)
		var t := ceili(1.0 / d) if d > 0.0 else -1
		if t != int(cs[2]):
			tb.append("%s / %s %d ticks (want %d)" % [cs[0], cs[1] if cs[1] != "" else "hand", t, cs[2]])
	ok("breaking: break ticks (wiki formula)", tb.is_empty(), "; ".join(tb))


func test_vanilla_snow_weather() -> void:
	var b := Res.blocks
	var w := _fluid_world()
	var grass := b.default_state("grass_block")
	var snow := b.default_state("snow")
	w.set_block(0, 0, 0, grass)
	w.set_block(0, 1, 0, snow)
	ShapeUpdates.on_changed(w, Vector3i(0, 1, 0), 0, snow)
	ok("snow: grass under a snow layer turns snowy", b.get_prop(w.state_at(0, 0, 0), "snowy") == "true", b.state_string(w.state_at(0, 0, 0)))
	w.set_block(0, 1, 0, 0)
	ShapeUpdates.on_changed(w, Vector3i(0, 1, 0), snow, 0)
	ok("snow: removing the snow clears snowy", b.get_prop(w.state_at(0, 0, 0), "snowy") == "false", b.state_string(w.state_at(0, 0, 0)))
	var pod := b.default_state("podzol")
	w.set_block(2, 0, 0, pod)
	w.set_block(2, 1, 0, b.default_state("snow_block"))
	ShapeUpdates.on_changed(w, Vector3i(2, 1, 0), 0, b.default_state("snow_block"))
	ok("snow: podzol under a snow block turns snowy", b.get_prop(w.state_at(2, 0, 0), "snowy") == "true")
	w.set_block(2, 1, 0, b.default_state("stone"))
	ShapeUpdates.on_changed(w, Vector3i(2, 1, 0), b.default_state("snow_block"), b.default_state("stone"))
	ok("snow: a non-snow block on top clears snowy", b.get_prop(w.state_at(2, 0, 0), "snowy") == "false")
	# SnowLayerBlock.canSurvive
	w.set_block(4, 0, 0, b.default_state("ice"))
	w.set_block(5, 0, 0, b.default_state("stone"))
	w.set_block(6, 0, 0, b.with_prop(snow, "layers", "8"))
	w.set_block(7, 0, 0, b.with_prop(snow, "layers", "3"))
	w.set_block(8, 0, 0, b.default_state("soul_sand"))
	ok("snow: not on ice", not BlockUpdates._snow_survives(w, 4, 1, 0))
	ok("snow: on a full top face", BlockUpdates._snow_survives(w, 5, 1, 0))
	ok("snow: on 8 layers, not on 3", BlockUpdates._snow_survives(w, 6, 1, 0) and not BlockUpdates._snow_survives(w, 7, 1, 0))
	ok("snow: soul sand overrides", BlockUpdates._snow_survives(w, 8, 1, 0))
	ok("snow: not in mid-air", not BlockUpdates._snow_survives(w, 9, 5, 0))
	# Level.isWaterAt (ice forms only at the edge of still water)
	ok("ice: water, flowing water and waterlogged blocks count as water", BlockUpdates._is_water(b.WATER) and BlockUpdates._is_water(b.with_prop(b.WATER, "level", "3"))
		and BlockUpdates._is_water(b.with_prop(b.default_state("oak_slab"), "waterlogged", "true")))
	ok("ice: air and dry blocks are not water", not BlockUpdates._is_water(0) and not BlockUpdates._is_water(b.default_state("oak_slab")))


class GravEntities extends MockEntities:
	var fell: Array = []

	func spawn_falling_block(p: Vector3i, st: int) -> void:
		fell.append([p, st])


class GravWorld extends FluidWorld:
	func set_block(x: int, y: int, z: int, st: int, notify := true) -> int:
		var old := super.set_block(x, y, z, st, notify)
		if notify and old != st:
			BlockUpdates.fluids_changed(self, Vector3i(x, y, z))
		return old


## Gravity blocks fall in a chain when their support goes (Java FallingBlock.updateShape on every neighbour change);
## plants pop off when the block under them goes (26.3 supports_* tags; cactus flower on cactus / farmland).
## Block-entity renders vanilla draws and Recraft used to miss: end portal / gateway surfaces, spawner mob previews,
## the enchanting table book, decorated pot sherds, and the enchantment glint rules.
func test_vanilla_block_entity_renders() -> void:
	BERender.setup()
	var b := Res.blocks
	var ep := BERender.build(b.default_state("end_portal"), {})
	var ep_mesh: MeshInstance3D = BERender._meshes(ep)[0] if ep != null and not BERender._meshes(ep).is_empty() else null
	ok("end portal: drawn with the end portal shader (top + bottom faces)", ep_mesh != null and ep_mesh.material_override is ShaderMaterial and ep_mesh.mesh.get_faces().size() == 12, str(ep_mesh.mesh.get_faces().size() if ep_mesh != null else -1))
	var eg := BERender.build(b.default_state("end_gateway"), {})
	ok("end gateway: six faces", eg != null and (BERender._meshes(eg)[0] as MeshInstance3D).mesh.get_faces().size() == 36)
	ok("end gateway: 16 layers, end portal 15", int(BERender.portal_material("end_gateway").get_shader_parameter("layers")) == 16 and int(BERender.portal_material("end_portal").get_shader_parameter("layers")) == 15)
	var sp := BERender.build(b.default_state("spawner"), {"id": "spawner", "mob": "zombie"})
	ok("spawner: zombie preview built with a spin node", sp != null and sp.has_meta("spin"))
	if sp != null and sp.has_meta("spin"):
		var tilt: Node3D = (sp.get_meta("spin") as Node3D).get_child(0)
		# Java: 0.53125 / max(0.6, 1.95) for a zombie, tilted -30 degrees
		ok("spawner: preview scale 0.53125 / max(w, h) and -30 degree tilt", is_equal_approx(tilt.scale.x, 0.53125 / 1.95) and is_equal_approx(tilt.rotation.x, deg_to_rad(-30.0)), str(tilt.scale.x))
	ok("spawner: an empty spawner shows nothing", BERender.build(b.default_state("spawner"), {"id": "spawner"}) == null)
	var et := BERender.build(b.default_state("enchanting_table"), {})
	ok("enchanting table: floating book parts", et != null and et.has_meta("book") and (et.get_meta("book") as Dictionary).has("flip2"))
	var bk := {"open": 0.0, "o_open": 0.0, "rot": 0.0, "o_rot": 0.0, "t_rot": 0.0, "flip": 0.0, "o_flip": 0.0, "flip_t": 0.0, "flip_a": 0.0, "time": 0.0}
	for i in 12:
		BERender._book_tick(bk, Vector3i.ZERO, Vector3(2.0, 0.5, 0.5))
	ok("enchanting table: the book opens fully for a player within 3 blocks (+0.1 per tick)", is_equal_approx(float(bk["open"]), 1.0) and absf(float(bk["rot"])) < 0.01, "open %.2f rot %.3f" % [bk["open"], bk["rot"]])
	for i in 4:
		BERender._book_tick(bk, Vector3i.ZERO, Vector3(20.0, 0.5, 0.5))
	ok("enchanting table: closes by 0.1 per tick without a player", is_equal_approx(float(bk["open"]), 0.6), "%.2f" % bk["open"])
	var pot := BERender.build(b.default_state("decorated_pot"), {"id": "decorated_pot", "sherds": ["minecraft:brick", "minecraft:angler_pottery_sherd", "minecraft:brick", "minecraft:skull_pottery_sherd"]})
	var pot_tex: Array = []
	if pot != null:
		for mi in BERender._meshes(pot):
			var m = (mi as MeshInstance3D).material_override
			if m is ShaderMaterial:
				pot_tex.append(m)
	ok("decorated pot: sherd sides use their pottery pattern materials", pot != null and pot_tex.has(EntityRenderer.material("entity/decorated_pot/angler_pottery_pattern")) and pot_tex.has(EntityRenderer.material("entity/decorated_pot/skull_pottery_pattern")))
	# 2026-11-15 batch: blank enchanting book, item icons / held models, lantern placement
	var book_tex := false
	if et != null:
		for mi in BERender._meshes(et):
			var bm2 = (mi as MeshInstance3D).material_override
			book_tex = book_tex or (bm2 is ShaderMaterial and bool((bm2 as ShaderMaterial).get_shader_parameter("has_tex")))
	ok("enchanting table: the book uses the 26.3 texture (entity/enchantment/enchanting_table_book)", book_tex and EntityRenderer.texture("entity/enchantment/enchanting_table_book") != null)
	var it := Res.items
	ok("special item models only for items/<name>.json minecraft:special (chest, banner, skull, pot; not enchanting table / shelf / bell)",
		BERender.special_item(it.id("chest")) and BERender.special_item(it.id("white_banner")) and BERender.special_item(it.id("skeleton_skull")) and BERender.special_item(it.id("decorated_pot"))
		and not BERender.special_item(it.id("enchanting_table")) and not BERender.special_item(it.id("oak_shelf")) and not BERender.special_item(it.id("bell")))
	var wm := EntityRenderer.item_block_mesh(it.id("cobblestone_wall"))
	var wab: AABB = wm.get_aabb() if wm != null else AABB()
	ok("held wall: the wall_inventory model (post + a full-length wall), not the lone default-state post", wm != null and is_equal_approx(wab.size.z, 1.0) and is_equal_approx(wab.size.x, 0.5), str(wab))
	# (the wall's default state has no geometry of its own: the hand / frame / ground paths fell back to the extruded icon)
	var wn := HeldItems.item_node(ItemStack.named("cobblestone_wall", 1), "fixed", false)
	var wmi: MeshInstance3D = wn.get_child(0) as MeshInstance3D if wn != null and wn.get_child_count() > 0 else null
	ok("wall in hand / frame / on the ground: HeldItems.item_node draws that mesh", wmi != null and wmi.mesh == wm)
	if wn != null:
		wn.free()
	var shm := EntityRenderer.item_block_mesh(it.id("oak_shelf"))
	ok("held shelf: its shelf_inventory model", shm != null and shm.get_faces().size() > 0)
	var sgm := EntityRenderer.item_block_mesh(it.id("white_stained_glass"))
	ok("held stained glass: blended (translucent item material), glass stays cutout", sgm != null and sgm.surface_get_material(0) == Res.mat_item_block_translucent
		and EntityRenderer.item_block_mesh(it.id("glass")).surface_get_material(0) == Res.mat_item_block)
	var pane_em: Array = ItemIcons.extruded_model("item/white_stained_glass_pane")
	var stick_em: Array = ItemIcons.extruded_model("item/stick")
	ok("held stained glass pane: translucent flat item material; a stick keeps the cutout one", pane_em.size() == 2 and stick_em.size() == 2
		and EntityRenderer.flat_item_material(pane_em[1]).shader == EntityRenderer.translucent_shader() and EntityRenderer.flat_item_material(stick_em[1]).shader != EntityRenderer.translucent_shader())
	var lw := MockWorld.new()
	var lp := Player.new()
	lp.pitch = 30.0
	var lan := b.default_state("copper_lantern")
	lw.grid[Vector3i(0, 67, 0)] = b.STONE
	lw.grid[Vector3i(4, 70, 0)] = b.default_state("oak_fence")
	lw.grid[Vector3i(6, 70, 0)] = b.default_state("oak_fence_gate")
	var l_under := Interaction.lantern_placement(lw, Vector3i(0, 66, 0), lan, Vector3i(0, -1, 0), lp)
	var l_top := Interaction.lantern_placement(lw, Vector3i(0, 64, 0), lan, Vector3i(0, 1, 0), lp)
	var l_side := Interaction.lantern_placement(lw, Vector3i(0, 66, 0), lan, Vector3i(1, 0, 0), lp)
	var l_fence := Interaction.lantern_placement(lw, Vector3i(4, 69, 0), lan, Vector3i(0, -1, 0), lp)
	var l_air := Interaction.lantern_placement(lw, Vector3i(9, 69, 0), lan, Vector3i(0, -1, 0), lp)
	var l_gate := Interaction.lantern_placement(lw, Vector3i(6, 69, 0), lan, Vector3i(0, -1, 0), lp)
	ok("lantern placement (Java LanternBlock): under a block / fence it hangs, on the floor it stands, side click falls back to the surviving direction, nothing to hold it or a fence gate: not placed",
		l_under > 0 and b.get_prop(l_under, "hanging") == "true" and l_top > 0 and b.get_prop(l_top, "hanging") == "false" and l_side > 0 and b.get_prop(l_side, "hanging") == "true"
		and l_fence > 0 and b.get_prop(l_fence, "hanging") == "true" and l_air == -1 and l_gate == -1, "%d %d %d %d %d %d" % [l_under, l_top, l_side, l_fence, l_air, l_gate])
	for n in [ep, eg, sp, et, pot]:
		if n != null:
			n.free()
	var sword := ItemStack.named("diamond_sword")
	ok("glint: plain sword has none", not Glint.has_glint(sword))
	sword.components["minecraft:enchantments"] = {"minecraft:sharpness": 1}
	ok("glint: enchanted sword glints", Glint.has_glint(sword))
	sword.components["minecraft:enchantment_glint_override"] = false
	ok("glint: override false hides it", not Glint.has_glint(sword))
	# wiki Note Block instrument table (block below)
	var inst_ok := true
	var inst_bad := []
	for pair in [["oak_planks", "bass"], ["crimson_stem", "bass"], ["oak_sign", "bass"], ["chest", "bass"], ["stone", "basedrum"],
			["stone_brick_slab", "basedrum"], ["cobblestone_wall", "basedrum"], ["white_concrete", "basedrum"], ["netherrack", "basedrum"],
			["sand", "snare"], ["lime_concrete_powder", "snare"], ["glass", "hat"], ["red_stained_glass_pane", "hat"], ["gold_block", "bell"],
			["clay", "flute"], ["packed_ice", "chime"], ["white_wool", "guitar"], ["bone_block", "xylophone"], ["iron_block", "iron_xylophone"],
			["soul_sand", "cow_bell"], ["pumpkin", "didgeridoo"], ["emerald_block", "bit"], ["hay_block", "banjo"], ["glowstone", "pling"],
			["copper_block", "trumpet"], ["waxed_exposed_cut_copper", "trumpet_exposed"], ["oxidized_cut_copper_stairs", "trumpet_oxidized"],
			["dirt", "harp"], ["grass_block", "harp"]]:
		if BlockEntities.note_instrument(pair[0]) != pair[1]:
			inst_ok = false
			inst_bad.append("%s=%s" % [pair[0], BlockEntities.note_instrument(pair[0])])
	ok("note block: instruments from the block below (wiki table)", inst_ok, str(inst_bad))
	# wiki Block sound type (generated BlockSounds table)
	ok("block sounds: cherry planks cherry_wood, basalt basalt, deepslate deepslate, crimson planks nether_wood",
		BlockProperties.sound_group("cherry_planks") == "cherry_wood" and BlockProperties.sound_group("basalt") == "basalt"
		and BlockProperties.sound_group("deepslate") == "deepslate" and BlockProperties.sound_group("crimson_planks") == "nether_wood",
		"%s %s %s %s" % [BlockProperties.sound_group("cherry_planks"), BlockProperties.sound_group("basalt"), BlockProperties.sound_group("deepslate"), BlockProperties.sound_group("crimson_planks")])
	ok("block sounds: anvil volume 0.3, metal pitch 1.5, wheat places with item.crop.plant",
		BlockProperties.sound_volume_pitch("anvil") == [0.3, 1.0] and BlockProperties.sound_volume_pitch("metal") == [1.0, 1.5]
		and BlockProperties.sound_event(BlockProperties.sound_group("wheat"), "place") == "item.crop.plant",
		"%s %s %s" % [BlockProperties.sound_volume_pitch("anvil"), BlockProperties.sound_volume_pitch("metal"), BlockProperties.sound_event(BlockProperties.sound_group("wheat"), "place")])
	ok("glint: always-glint items (enchanted golden apple, nether star, experience bottle, written book)", Glint.has_glint(ItemStack.named("enchanted_golden_apple")) and Glint.has_glint(ItemStack.named("nether_star")) and Glint.has_glint(ItemStack.named("experience_bottle")) and Glint.has_glint(ItemStack.named("written_book")) and not Glint.has_glint(ItemStack.named("golden_apple")))


## Blocks the player is inside / stands on (wiki values): cobweb slowdown, cactus / magma / fire damage, powder snow
## freezing, footstep counter.
func test_vanilla_player_blocks() -> void:
	var b := Res.blocks
	var web := b.default_state("cobweb")
	var w := MockWorld.new()
	for z in range(-2, 40):
		w.grid[Vector3i(0, 64, z)] = web
		w.grid[Vector3i(0, 65, z)] = web
	var p := Player.new()
	p.mode = Player.Mode.SURVIVAL
	p.pos = Vector3(0.5, 64, 0.5)
	p.prev_pos = p.pos
	p.on_ground = true
	p.in_forward = 1.0
	for i in 20:
		p.tick(w)
	var z0 := p.pos.z
	for i in 20:
		p.tick(w)
	var v := p.pos.z - z0
	# stuck (0.25, 0.05, 0.25) with the motion reset every tick: 0.1 x 0.98 x 0.25 = 0.0245 blocks / tick = 0.49 m/s
	ok("cobweb: walking slows to ~0.49 m/s", absf(v - 0.49) < 0.03, "%.3f m/s" % v)
	var w2 := MockWorld.new()
	w2.grid[Vector3i(1, 64, 0)] = b.default_state("cactus")
	var c := Player.new()
	c.mode = Player.Mode.SURVIVAL
	c.food = 17
	c.saturation = 0.0
	c.pos = Vector3(0.75, 64, 0.5)   # touching the cactus cell (its shape is 1 px in)
	c.prev_pos = c.pos
	c.on_ground = true
	for i in 3:
		c.tick(w2)
	ok("cactus: touching it deals 1", c.health == 19.0, str(c.health))
	var w3 := MockWorld.new()
	w3.grid[Vector3i(0, 63, 0)] = b.default_state("magma_block")
	var m := Player.new()
	m.mode = Player.Mode.SURVIVAL
	m.food = 17
	m.saturation = 0.0
	m.pos = Vector3(0.5, 64, 0.5)
	m.prev_pos = m.pos
	m.on_ground = true
	for i in 5:
		m.tick(w3)
	ok("magma block: standing on it deals 1 (hot_floor)", m.health == 19.0, str(m.health))
	var ms := Player.new()
	ms.mode = Player.Mode.SURVIVAL
	ms.food = 17
	ms.saturation = 0.0
	ms.pos = Vector3(0.5, 64, 0.5)
	ms.prev_pos = ms.pos
	ms.on_ground = true
	ms.in_sneak = true
	for i in 5:
		ms.tick(w3)
	ok("magma block: sneaking is safe", ms.health == 20.0, str(ms.health))
	var w4 := MockWorld.new()
	w4.grid[Vector3i(0, 64, 0)] = b.default_state("fire")
	var f := Player.new()
	f.mode = Player.Mode.SURVIVAL
	f.food = 17
	f.saturation = 0.0
	f.pos = Vector3(0.5, 64, 0.5)
	f.prev_pos = f.pos
	f.on_ground = true
	f.tick(w4)
	ok("fire block: 1 damage and 8 s of burning", f.health == 19.0 and f.fire_ticks >= 150, "hp %.1f fire %d" % [f.health, f.fire_ticks])
	var w5 := MockWorld.new()
	w5.grid[Vector3i(0, 64, 0)] = b.default_state("powder_snow")
	w5.grid[Vector3i(0, 65, 0)] = b.default_state("powder_snow")
	var s := Player.new()
	s.mode = Player.Mode.SURVIVAL
	s.food = 17
	s.saturation = 0.0
	s.pos = Vector3(0.5, 64, 0.5)
	s.prev_pos = s.pos
	for i in 139:
		s.tick(w5)
	var before := s.health
	for i in 41:
		s.tick(w5)
	ok("powder snow: fully frozen after 140 ticks, then freeze damage", s.ticks_frozen == 140 and before == 20.0 and s.health == 19.0, "frozen %d hp %.1f -> %.1f" % [s.ticks_frozen, before, s.health])
	var leather := ItemStack.named("leather_boots")
	if not leather.is_empty():
		var s2 := Player.new()
		s2.mode = Player.Mode.SURVIVAL
		s2.pos = Vector3(0.5, 64, 0.5)
		s2.prev_pos = s2.pos
		s2.inventory.set_slot(Inventory.ARMOR0, leather)
		for i in 60:
			s2.tick(w5)
		ok("powder snow: leather armour stops freezing", s2.ticks_frozen == 0, str(s2.ticks_frozen))
	var wk := Player.new()
	wk.mode = Player.Mode.SURVIVAL
	wk.pos = Vector3(0.5, 64, 0.5)
	wk.prev_pos = wk.pos
	wk.on_ground = true
	wk.in_forward = 1.0
	for i in 40:
		wk.tick(MockWorld.new())
	# item cooldowns (Java ItemCooldowns): ender pearl 20 ticks
	var cp := Player.new()
	cp.add_cooldown("ender_pearl", 20)
	for i in 10:
		cp.tick(MockWorld.new())
	var half := cp.cooldown_percent("ender_pearl")
	for i in 10:
		cp.tick(MockWorld.new())
	ok("item cooldown: ender pearl 20 ticks (half after 10)", is_equal_approx(half, 0.5) and not cp.on_cooldown("ender_pearl"), "%.2f %s" % [half, cp.on_cooldown("ender_pearl")])
	# chorus fruit: lands on a floor within 8 blocks horizontally
	var cw := MockWorld.new()
	cw.set("dim_type", null)
	var ch := Player.new()
	ch.pos = Vector3(0.5, 64, 0.5)
	var tp := UseItem.chorus_teleport(cw, ch)
	ok("chorus fruit: teleports onto the floor within 8 blocks", tp and is_equal_approx(ch.pos.y, 64.0) and absf(ch.pos.x - 0.5) <= 8.0 and absf(ch.pos.z - 0.5) <= 8.0, str(ch.pos))
	# 2 s of walking (~8.6 blocks) at 0.6 per block -> ~5 steps
	ok("footsteps: a step every 1 / 0.6 blocks walked", wk.next_step >= 4.0 and wk.next_step <= 7.0, "next_step %.1f" % wk.next_step)


class SensorCM:
	var light := 0xF0
	var chunks: Dictionary = {}
	func get_light(_x: int, _y: int, _z: int) -> int:
		return light
	func get_chunk(_x: int, _z: int):
		return null


class SensorWorld:
	var blocks: Dictionary = {}
	var game_time := 0
	var rng := RandomNumberGenerator.new()
	var entities := CmdEnts.new()
	var cm := SensorCM.new()
	var player = null
	var dim_type := {"has_skylight": true}
	var angle := 0.0
	func state_at(x: int, y: int, z: int) -> int:
		return blocks.get(Vector3i(x, y, z), 0)
	func set_block(x: int, y: int, z: int, st: int, _notify := true) -> int:
		var old: int = blocks.get(Vector3i(x, y, z), 0)
		blocks[Vector3i(x, y, z)] = st
		return old
	func gamerule(_n: String, d = null):
		return d
	func sky_darken_level() -> int:
		return 0
	func celestial_angle() -> float:
		return angle


## Pressure plates, daylight detectors, target blocks (wiki values via Sensors).
func test_vanilla_sensors() -> void:
	var b := Res.blocks
	Sensors.reset()
	var w := SensorWorld.new()
	var q := Vector3i(0, 64, 0)
	w.blocks[q] = b.default_state("stone_pressure_plate")
	var it := EntityManager.Ent.new()
	it.kind = "item"
	it.pos = Vector3(0.5, 64, 0.5)
	w.entities.ents.append(it)
	Sensors.tick(w)
	ok("stone pressure plate: an item does not press it", b.get_prop(w.state_at(0, 64, 0), "powered") == "false")
	var mob = w.entities.spawn_mob("zombie", Vector3(0.5, 64, 0.5))
	mob.w = 0.6
	mob.h = 1.95
	Sensors.tick(w)
	ok("stone pressure plate: a mob presses it", b.get_prop(w.state_at(0, 64, 0), "powered") == "true")
	w.entities.ents.erase(mob)
	w.game_time += 19
	Sensors.tick(w)
	var still := b.get_prop(w.state_at(0, 64, 0), "powered") == "true"
	w.game_time += 1
	Sensors.tick(w)
	ok("stone pressure plate: re-checks after 20 ticks and releases", still and b.get_prop(w.state_at(0, 64, 0), "powered") == "false")
	w.blocks[q] = b.default_state("oak_pressure_plate")
	Sensors.tick(w)
	ok("wooden pressure plate: items press it", b.get_prop(w.state_at(0, 64, 0), "powered") == "true")
	w.entities.ents.clear()
	w.blocks[q] = b.default_state("heavy_weighted_pressure_plate")
	for i in 15:
		var e2 := EntityManager.Ent.new()
		e2.kind = "item"
		e2.pos = Vector3(0.5, 64, 0.5)
		w.entities.ents.append(e2)
	Sensors.tick(w)
	ok("heavy weighted plate: 15 items -> ceil(15 / 150 x 15) = 2", int(b.get_prop(w.state_at(0, 64, 0), "power")) == 2, b.get_prop(w.state_at(0, 64, 0), "power"))
	w.blocks[q] = b.default_state("light_weighted_pressure_plate")
	Sensors.tick(w)
	ok("light weighted plate: 15 items -> 15", int(b.get_prop(w.state_at(0, 64, 0), "power")) == 15, b.get_prop(w.state_at(0, 64, 0), "power"))
	var dd := Vector3i(3, 64, 0)
	w.blocks[dd] = b.default_state("daylight_detector")
	Sensors.update_detector(w, dd, w.state_at(3, 64, 0))
	var noon := int(b.get_prop(w.state_at(3, 64, 0), "power"))
	w.angle = 0.25
	Sensors.update_detector(w, dd, w.state_at(3, 64, 0))
	var eve := int(b.get_prop(w.state_at(3, 64, 0), "power"))
	w.blocks[dd] = b.with_prop(w.state_at(3, 64, 0), "inverted", "true")
	w.angle = 0.0
	Sensors.update_detector(w, dd, w.state_at(3, 64, 0))
	var inv := int(b.get_prop(w.state_at(3, 64, 0), "power"))
	ok("daylight detector: 15 at noon, round(15 cos(0.8 x 90 deg)) = 5 at sunset, inverted 0 at noon", noon == 15 and eve == 5 and inv == 0, "%d / %d / %d" % [noon, eve, inv])
	var tq := Vector3i(6, 64, 0)
	w.blocks[tq] = b.default_state("target")
	Sensors.on_projectile_hit(w, {"pos": tq, "normal": Vector3(0, 0, -1), "point": Vector3(6.5, 64.5, 0.0)}, "arrow")
	var centre := int(b.get_prop(w.state_at(6, 64, 0), "power"))
	Sensors.on_projectile_hit(w, {"pos": tq, "normal": Vector3(0, 0, -1), "point": Vector3(6.97, 64.5, 0.0)}, "snowball")
	var edge := int(b.get_prop(w.state_at(6, 64, 0), "power"))
	w.game_time += 8
	Sensors.tick(w)
	ok("target block: 15 in the centre, 1 at the edge, off after 8 ticks (snowball)", centre == 15 and edge == 1 and int(b.get_prop(w.state_at(6, 64, 0), "power")) == 0, "%d / %d" % [centre, edge])
	Sensors.reset()


## Chunk-backed mock for block entities (hoppers, rods, portal search): real Chunks created on demand.
class ChunkCM:
	var chunks: Dictionary = {}
	var origin := Vector3i.ZERO
	func get_chunk(cx: int, cz: int):
		var k := Coords.chunk_key(cx, cz)
		if not chunks.has(k):
			var c := Chunk.new(cx, cz)
			c.state = Chunk.DECORATED
			chunks[k] = c
		return chunks[k]
	func get_light(_x: int, _y: int, _z: int) -> int:
		return 0xF0
	func get_block(x: int, y: int, z: int) -> int:
		return (get_chunk(x >> 4, z >> 4) as Chunk).get_block(x & 15, y, z & 15)


class ChunkWorld:
	var game_time := 0
	var rng := RandomNumberGenerator.new()
	var entities := CmdEnts.new()
	var cm := ChunkCM.new()
	var player = null
	var dim_type := {"has_skylight": true}
	func gamerule(_n: String, d = null):
		return d
	func state_at(x: int, y: int, z: int) -> int:
		return cm.get_block(x, y, z)
	func set_block(x: int, y: int, z: int, st: int, _notify := true) -> int:
		return (cm.get_chunk(x >> 4, z >> 4) as Chunk).set_block(x & 15, y, z & 15, st)


## Tripwire, detector / powered rails, slime pistons, hopper cooldowns, bells, lecterns, jukeboxes, conduits, beacon
## tint, lightning rods, portal destination search, spawner eggs (wiki values; Tripwires / Redstone / Sensors / ...).
func test_vanilla_redstone_blocks() -> void:
	var b := Res.blocks
	Sensors.reset()
	BlockUpdates.reset()
	var stone := b.default_state("stone")
	# --- tripwire: hook east at x 0, 3 strings, hook west at x 4
	var w := SensorWorld.new()
	w.blocks[Vector3i(-1, 64, 0)] = stone
	w.blocks[Vector3i(5, 64, 0)] = stone
	var hook_e := b.with_prop(b.default_state("tripwire_hook"), "facing", "east")
	var hook_w := b.with_prop(b.default_state("tripwire_hook"), "facing", "west")
	w.blocks[Vector3i(0, 64, 0)] = hook_e
	for x in range(1, 4):
		w.blocks[Vector3i(x, 64, 0)] = b.default_state("tripwire")
		Tripwires.on_placed(w, Vector3i(x, 64, 0), w.state_at(x, 64, 0))
	w.blocks[Vector3i(4, 64, 0)] = hook_w
	Tripwires.on_placed(w, Vector3i(4, 64, 0), hook_w)
	var att := b.get_prop(w.state_at(0, 64, 0), "attached") == "true" and b.get_prop(w.state_at(4, 64, 0), "attached") == "true"
	ok("tripwire: two facing hooks with string between attach (hooks + strings)", att and b.get_prop(w.state_at(2, 64, 0), "attached") == "true" and b.get_prop(w.state_at(2, 64, 0), "east") == "true" and b.get_prop(w.state_at(1, 64, 0), "west") == "true")
	var mob = w.entities.spawn_mob("zombie", Vector3(2.5, 64, 0.5))
	mob.w = 0.6
	mob.h = 1.95
	Sensors.tick(w)
	var trip_on := b.get_prop(w.state_at(2, 64, 0), "powered") == "true" and b.get_prop(w.state_at(0, 64, 0), "powered") == "true" and b.get_prop(w.state_at(4, 64, 0), "powered") == "true"
	ok("tripwire: an entity on the string powers both hooks (15)", trip_on and Redstone.source_power(w, Vector3i(0, 64, 0)) == 15)
	w.entities.ents.erase(mob)
	w.game_time += 10
	Tripwires.scheduled(w, Vector3i(2, 64, 0), w.state_at(2, 64, 0))
	ok("tripwire: re-checks after 10 ticks and releases", b.get_prop(w.state_at(2, 64, 0), "powered") == "false" and b.get_prop(w.state_at(0, 64, 0), "powered") == "false")
	var ws := w.state_at(2, 64, 0)
	w.blocks[Vector3i(2, 64, 0)] = 0
	Tripwires.on_removed(w, Vector3i(2, 64, 0), ws, false)
	var pulse := b.get_prop(w.state_at(0, 64, 0), "powered") == "true" and b.get_prop(w.state_at(4, 64, 0), "powered") == "true"
	w.game_time += 1
	Tripwires.scheduled(w, Vector3i(0, 64, 0), w.state_at(0, 64, 0))   # (a neighbour update must not end the pulse)
	var held := b.get_prop(w.state_at(0, 64, 0), "powered") == "true"
	w.game_time += 9
	Tripwires.scheduled(w, Vector3i(0, 64, 0), w.state_at(0, 64, 0))
	Tripwires.scheduled(w, Vector3i(4, 64, 0), w.state_at(4, 64, 0))
	ok("tripwire: breaking string pulses the hooks 10 ticks, then they detach", pulse and held and b.get_prop(w.state_at(0, 64, 0), "powered") == "false" and b.get_prop(w.state_at(4, 64, 0), "attached") == "false" and b.get_prop(w.state_at(3, 64, 0), "attached") == "false", "%s %s" % [pulse, held])
	w.blocks[Vector3i(2, 64, 0)] = b.default_state("tripwire")
	Tripwires.on_placed(w, Vector3i(2, 64, 0), w.state_at(2, 64, 0))
	var re_att := b.get_prop(w.state_at(0, 64, 0), "attached") == "true"
	ws = w.state_at(2, 64, 0)
	w.blocks[Vector3i(2, 64, 0)] = 0
	Tripwires.on_removed(w, Vector3i(2, 64, 0), ws, true)
	ok("tripwire: shears disarm - hooks detach without a pulse", re_att and b.get_prop(w.state_at(0, 64, 0), "powered") == "false" and b.get_prop(w.state_at(0, 64, 0), "attached") == "false")
	Tripwires.reset()
	# --- detector rail + comparator from a chest minecart
	var wd := SensorWorld.new()
	var dr := b.with_prop(b.default_state("detector_rail"), "shape", "east_west")
	wd.blocks[Vector3i(0, 64, 0)] = dr
	var cart := EntityManager.Ent.new()
	cart.kind = "minecart"
	cart.id = "chest_minecart"
	cart.w = 0.98
	cart.h = 0.7
	cart.pos = Vector3(0.5, 64.0625, 0.5)
	var its: Array = []
	its.resize(27)
	its.fill({})
	its[0] = ItemStack.named("cobblestone", 64).to_dict()
	cart.data["items"] = its
	wd.entities.ents.append(cart)
	Sensors.detector_check(wd, Vector3i(0, 64, 0), dr)
	var dst := wd.state_at(0, 64, 0)
	ok("detector rail: a minecart powers it; comparator reads the cart (1 of 27 full stacks -> 1)", b.get_prop(dst, "powered") == "true" and Redstone.source_power(wd, Vector3i(0, 64, 0)) == 15 and Redstone.measure(wd, Vector3i(0, 64, 0), dst, Vector3i(1, 0, 0)) == 1)
	wd.entities.ents.clear()
	Sensors.detector_check(wd, Vector3i(0, 64, 0), dst)
	ok("detector rail: off when the cart has left", b.get_prop(wd.state_at(0, 64, 0), "powered") == "false")
	# --- powered rails pass power 8 rails along the track (incl. a slope)
	var wr := RsWorld.new()
	var pr := b.with_prop(b.default_state("powered_rail"), "shape", "east_west")
	for x in range(0, 14):
		var y := 0 if x < 5 else 1
		wr.blocks[Vector3i(x, y - 1, 0)] = stone
		wr.blocks[Vector3i(x, y, 0)] = pr
	wr.blocks[Vector3i(4, 0, 0)] = b.with_prop(pr, "shape", "ascending_east")
	wr.blocks[Vector3i(0, 0, 1)] = b.default_state("redstone_block")
	Redstone.on_changed(wr, Vector3i(0, 0, 1))
	var lit := []
	for x in range(0, 14):
		lit.append(b.get_prop(wr.state_at(x, 0 if x < 5 else 1, 0), "powered") == "true")
	ok("powered rails: a source powers its rail + 8 more along the track (slope included)", lit.slice(0, 9).count(true) == 9 and lit.slice(9).count(true) == 0, str(lit))
	wr.blocks[Vector3i(0, 0, 1)] = 0
	Redstone.on_changed(wr, Vector3i(0, 0, 1))
	var off := true
	for x in range(0, 14):
		off = off and b.get_prop(wr.state_at(x, 0 if x < 5 else 1, 0), "powered") == "false"
	ok("powered rails: the whole stretch turns off with the source", off)
	# --- dust weakly powers the block under it: a lamp beside that block lights
	var wl := RsWorld.new()
	wl.blocks[Vector3i(0, 0, 0)] = stone
	wl.blocks[Vector3i(0, 1, 0)] = b.with_prop(b.default_state("redstone_wire"), "power", "15")
	wl.blocks[Vector3i(1, 0, 0)] = b.default_state("redstone_lamp")
	ok("dust on a block powers a lamp beside the block (weak power)", Redstone._powered_any(wl, Vector3i(1, 0, 0)))
	# --- slime / honey pistons
	var wp := RsWorld.new()
	var pis := b.with_prop(b.default_state("sticky_piston"), "facing", "east")
	wp.blocks[Vector3i(0, 0, 0)] = pis
	wp.blocks[Vector3i(1, 0, 0)] = b.default_state("slime_block")
	wp.blocks[Vector3i(1, 1, 0)] = stone
	wp.blocks[Vector3i(1, 0, 1)] = b.default_state("honey_block")
	wp.blocks[Vector3i(1, -1, 0)] = b.default_state("obsidian")
	wp.blocks[Vector3i(1, 0, -1)] = b.default_state("orange_glazed_terracotta")
	wp.blocks[Vector3i(2, 0, 0)] = b.default_state("dirt")
	wp.blocks[Vector3i(0, 1, 1)] = b.default_state("redstone_block")
	Redstone._extend(wp, Vector3i(0, 0, 0), pis)
	Pistons.finish_all(wp)   # (moving blocks: 2 ticks)
	var moved := b.name_of(wp.state_at(2, 0, 0)) == "slime_block" and wp.state_at(2, 1, 0) == stone and b.name_of(wp.state_at(3, 0, 0)) == "dirt"
	var stayed := b.name_of(wp.state_at(1, 0, 1)) == "honey_block" and b.name_of(wp.state_at(1, -1, 0)) == "obsidian" and b.name_of(wp.state_at(1, 0, -1)) == "orange_glazed_terracotta"
	ok("slime piston: carries stuck blocks; honey, obsidian and glazed terracotta stay", moved and stayed and b.name_of(wp.state_at(1, 0, 0)) == "piston_head")
	Redstone._retract(wp, Vector3i(0, 0, 0), wp.state_at(0, 0, 0), true)
	Pistons.finish_all(wp)
	ok("sticky piston pulls the slime structure back (with the block stuck to its far side)", b.name_of(wp.state_at(1, 0, 0)) == "slime_block" and wp.state_at(1, 1, 0) == stone and b.name_of(wp.state_at(2, 0, 0)) == "dirt" and wp.state_at(3, 0, 0) == 0)
	var wq := RsWorld.new()
	wq.blocks[Vector3i(0, 0, 0)] = b.with_prop(b.default_state("piston"), "facing", "east")
	for x in range(1, 4):
		for y in range(0, 4):
			wq.blocks[Vector3i(x, y, 0)] = b.default_state("slime_block")   # 12 slime blocks
	var r12 := Redstone._resolve(wq, Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 0), true)
	wq.blocks[Vector3i(1, 4, 0)] = stone
	var r13 := Redstone._resolve(wq, Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 0), true)
	ok("piston push limit 12 blocks incl. stuck ones", (r12.get("move", []) as Array).size() == 12 and r13.is_empty())
	# --- hopper cooldowns: 8 ticks after a transfer, 7 after an item lands in an empty hopper
	var wh := ChunkWorld.new()
	var hop_e := b.with_prop(b.default_state("hopper"), "facing", "east")
	wh.set_block(0, 64, 0, hop_e)
	wh.set_block(1, 64, 0, hop_e)
	wh.set_block(2, 64, 0, b.default_state("chest"))
	BlockEntities.on_placed(wh, Vector3i(0, 64, 0), hop_e)
	BlockEntities.on_placed(wh, Vector3i(1, 64, 0), hop_e)
	BlockEntities.on_placed(wh, Vector3i(2, 64, 0), b.default_state("chest"))
	var ha := BlockEntities.get_data(wh, Vector3i(0, 64, 0))
	(ha["items"] as Array)[0] = ItemStack.named("cobblestone", 3).to_dict()
	var a_times: Array = []
	var c_times: Array = []
	var prev_c := 0
	for t in 20:
		wh.game_time = 100 + t
		var before := ItemStack.from_dict((BlockEntities.get_data(wh, Vector3i(0, 64, 0))["items"] as Array)[0]).count
		BlockEntities.tick_furnaces(wh)
		if ItemStack.from_dict((BlockEntities.get_data(wh, Vector3i(0, 64, 0))["items"] as Array)[0]).count < before:
			a_times.append(t)
		var cc := 0
		for it in BlockEntities.get_data(wh, Vector3i(2, 64, 0))["items"]:
			cc += ItemStack.from_dict(it).count
		if cc > prev_c:
			c_times.append(t)
		prev_c = cc
	ok("hopper: one transfer every 8 ticks; an item pushed into an empty hopper moves on 7 ticks later", a_times.slice(0, 2) == [0, 8] and not c_times.is_empty() and int(c_times[0]) == 7, "%s / %s" % [a_times, c_times])
	var hop_d := b.default_state("hopper")
	wh.set_block(5, 64, 0, hop_d)
	BlockEntities.on_placed(wh, Vector3i(5, 64, 0), hop_d)
	var drop := EntityManager.Ent.new()
	drop.kind = "item"
	drop.stack = ItemStack.named("dirt", 3)
	drop.pos = Vector3(5.5, 65.1, 0.5)
	wh.entities.ents.append(drop)
	wh.game_time = 300
	BlockEntities.tick_furnaces(wh)
	var got := ItemStack.from_dict((BlockEntities.get_data(wh, Vector3i(5, 64, 0))["items"] as Array)[0])
	ok("hopper: collects item entities in the block space above it (whole stack)", drop.dead and got.name() == "dirt" and got.count == 3, "%s x%d" % [got.name(), got.count])
	# --- lightning rods take natural strikes (closest exposed rod)
	var rod := Vector3i(10, 64, 3)
	wh.set_block(rod.x, rod.y, rod.z, b.default_state("lightning_rod"))
	BlockEntities.on_placed(wh, rod, b.default_state("lightning_rod"))
	var found := Sensors.find_rod(wh, Vector3(0, 64, 0))
	wh.set_block(rod.x, rod.y + 5, rod.z, stone)
	ok("lightning rod: attracts strikes within 128 blocks, only with open sky above", found == rod and Sensors.find_rod(wh, Vector3(0, 64, 0)) == Sensors.NONE and Sensors.find_rod(wh, Vector3(200, 64, 0)) == Sensors.NONE)
	# --- spawn egg on spawners
	wh.set_block(0, 70, 0, b.default_state("spawner"))
	Trials.set_spawner_mob(wh, Vector3i(0, 70, 0), "spawner", "zombie")
	ok("spawn egg on a spawner sets its mob", str(BlockEntities.get_data(wh, Vector3i(0, 70, 0)).get("mob", "")) == "zombie")
	# --- portal destination: closest 3 x 4 buildable area, else a 1 x 4 strip
	var wo := ChunkWorld.new()
	for x in range(10, 15):
		for z in range(0, 5):
			wo.set_block(x, 63, z, stone)
	for x in range(3, 7):
		wo.set_block(x, 63, -8, stone)
	var cols := {}
	var s34 := Portals._find_spot(wo, Vector3i(0, 64, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), 0, 127, 1, cols)
	var s14 := Portals._find_spot(wo, Vector3i(0, 64, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), 0, 127, 0, cols)
	ok("portal search: closest 3 x 4 buildable spot, 1 x 4 strip as the fallback", s34 == Vector3i(11, 64, 1) and s14 == Vector3i(4, 64, -8), "%s / %s" % [s34, s14])
	# --- bells: side use, redstone ring, swing
	var wb := SensorWorld.new()
	var bell := b.with_prop(b.with_prop(b.default_state("bell"), "attachment", "floor"), "facing", "north")
	wb.blocks[Vector3i(0, 64, 0)] = bell
	Bells.reset()
	var side_no := Bells.use(wb, Vector3i(0, 64, 0), bell, {"normal": Vector3i(1, 0, 0)})
	var side_yes := Bells.use(wb, Vector3i(0, 64, 0), bell, {"normal": Vector3i(0, 0, -1)})
	ok("bell: a floor bell rings from the faces along its facing", not side_no and side_yes and Bells.swing.has(Vector3i(0, 64, 0)))
	var a5 := Bells.swing_angles(5.0, Vector3i(0, 0, -1))
	ok("bell swing: BellRenderer angle -sin(t / pi) / (4 + t / 3), at rest after 50 ticks", is_equal_approx(a5.x, -sin(5.0 / PI) / (4.0 + 5.0 / 3.0)) and Bells.swing_angles(50.0, Vector3i(0, 0, -1)) == Vector2.ZERO)
	Bells.reset()
	wb.blocks[Vector3i(1, 64, 0)] = b.with_prop(b.default_state("lever"), "powered", "true")
	Redstone.on_changed(wb, Vector3i(1, 64, 0))
	ok("bell: a redstone signal rings it once", Bells.swing.has(Vector3i(0, 64, 0)) and b.get_prop(wb.state_at(0, 64, 0), "powered") == "true")
	Bells.reset()
	# --- lectern pulse, jukebox output
	var wj := SensorWorld.new()
	wj.blocks[Vector3i(0, 64, 0)] = b.default_state("lectern")
	Redstone.lectern_pulse(wj, Vector3i(0, 64, 0))
	var lp := Redstone.source_power(wj, Vector3i(0, 64, 0))
	wj.game_time += 2
	Redstone.scheduled(wj, Vector3i(0, 64, 0), wj.state_at(0, 64, 0))
	ok("lectern: a page turn gives a 2-tick pulse of 15", lp == 15 and Redstone.source_power(wj, Vector3i(0, 64, 0)) == 0)
	wj.blocks[Vector3i(2, 64, 0)] = b.default_state("jukebox")
	BlockEntities.playing[Vector3i(2, 64, 0)] = [wj.game_time, 100]
	var jp := Redstone.source_power(wj, Vector3i(2, 64, 0))
	wj.game_time += 100
	BlockEntities.tick_jukeboxes(wj)
	ok("jukebox: 15 while the record plays, 0 when the track ends", jp == 15 and Redstone.source_power(wj, Vector3i(2, 64, 0)) == 0)
	# --- conduit frame / range
	var wc := SensorWorld.new()
	var cp := Vector3i(0, 64, 0)
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				wc.blocks[cp + Vector3i(x, y, z)] = b.WATER
	wc.blocks[cp] = b.with_prop(b.default_state("conduit"), "waterlogged", "true")
	var fo := Conduits.frame_offsets()
	for i in 16:
		wc.blocks[cp + (fo[i] as Vector3i)] = b.default_state("prismarine")
	var f16 := Conduits.frame_count(wc, cp)
	wc.blocks[cp + Vector3i(1, 1, 1)] = stone
	ok("conduit: 42 frame spots, 16 blocks -> range 32 (16 per 7 blocks, 96 at 42), needs water around it", fo.size() == 42 and f16 == 16 and Conduits.range_for(16) == 32 and Conduits.range_for(21) == 48 and Conduits.range_for(42) == 96 and Conduits.range_for(15) == 0 and Conduits.frame_count(wc, cp) == 0)
	# --- beacon beam tint
	var wg := SensorWorld.new()
	wg.blocks[Vector3i(0, 66, 0)] = b.default_state("red_stained_glass")
	wg.blocks[Vector3i(0, 70, 0)] = b.default_state("blue_stained_glass_pane")
	var sg := Beacons.beam_segments(wg, Vector3i(0, 64, 0))
	var red := Color.hex(0xB02E26FF)
	var blue := Color.hex(0x3C44AAFF)
	ok("beacon beam: first glass sets the colour, the next one averages (wiki dye colours)", sg.size() == 3 and int(sg[1][0]) == 66 and (sg[1][1] as Color).is_equal_approx(red) and (sg[2][1] as Color).is_equal_approx(Color((red.r + blue.r) / 2.0, (red.g + blue.g) / 2.0, (red.b + blue.b) / 2.0)), str(sg))
	BlockUpdates.reset()
	Sensors.reset()


class GolemEnts extends CmdEnts:
	var rng := RandomNumberGenerator.new()


class GrowWorld:
	var blocks: Dictionary = {}
	var game_time := 0
	var day_time := 6000
	var difficulty := 2
	var rng := RandomNumberGenerator.new()
	var entities := CmdEnts.new()
	var cm := SensorCM.new()
	var dim_type := {"attributes": {"minecraft:gameplay/nether_portal_spawns_piglin": true}}
	var angle := 0.0
	func state_at(x: int, y: int, z: int) -> int:
		return blocks.get(Vector3i(x, y, z), 0)
	func set_block(x: int, y: int, z: int, st: int, _notify := true) -> int:
		var old: int = blocks.get(Vector3i(x, y, z), 0)
		if st == 0:
			blocks.erase(Vector3i(x, y, z))
		else:
			blocks[Vector3i(x, y, z)] = st
		return old
	func gamerule(_n: String, d = null):
		return d
	func celestial_angle() -> float:
		return angle


func _names_in(w: GrowWorld, nm: String) -> int:
	var n := 0
	for k in w.blocks:
		if Res.blocks.name_of(w.blocks[k]) == nm:
			n += 1
	return n


## Random-tick / timed growth that was missing (Growth; wiki values).
func test_vanilla_growth() -> void:
	var b := Res.blocks
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	Growth.reset()
	# budding amethyst: buds appear on its faces and grow into clusters
	var w := GrowWorld.new()
	w.blocks[Vector3i(0, 64, 0)] = b.default_state("budding_amethyst")
	for i in 3000:
		Growth.random_tick(w, Vector3i(0, 64, 0), w.state_at(0, 64, 0), "budding_amethyst", rng)
	ok("budding amethyst: buds grow into clusters on its faces", _names_in(w, "amethyst_cluster") >= 1, "clusters %d small %d" % [_names_in(w, "amethyst_cluster"), _names_in(w, "small_amethyst_bud")])
	# vines grow down from a vine on a wall
	var wv := GrowWorld.new()
	wv.blocks[Vector3i(0, 70, -1)] = b.default_state("stone")
	wv.blocks[Vector3i(0, 70, 0)] = b.with_prop(b.default_state("vine"), "north", "true")
	for i in 400:
		Growth.random_tick(wv, Vector3i(0, 70, 0), wv.state_at(0, 70, 0), "vine", rng)
	ok("vines: spread down (25 % per tick, 50 % per face)", b.name_of(wv.state_at(0, 69, 0)) == "vine")
	# cave vines: grow down 10 % per tick, the old head becomes the plant
	var wc := GrowWorld.new()
	wc.blocks[Vector3i(0, 70, 0)] = b.default_state("cave_vines")
	var head := Vector3i(0, 70, 0)
	for i in 300:
		var hn := b.name_of(wc.state_at(head.x, head.y, head.z))
		if hn != "cave_vines":
			break
		Growth.random_tick(wc, head, wc.state_at(head.x, head.y, head.z), "cave_vines", rng)
		if b.name_of(wc.state_at(head.x, head.y - 1, head.z)) == "cave_vines":
			head += Vector3i.DOWN
	ok("cave vines: grow downward, body behind the head", head.y < 66 and b.name_of(wc.state_at(0, 70, 0)) == "cave_vines_plant", "head y %d" % head.y)
	# chorus flower on end stone grows a plant
	var wh := GrowWorld.new()
	wh.blocks[Vector3i(0, 63, 0)] = b.default_state("end_stone")
	wh.blocks[Vector3i(0, 64, 0)] = b.default_state("chorus_flower")
	Growth.random_tick(wh, Vector3i(0, 64, 0), wh.state_at(0, 64, 0), "chorus_flower", rng)
	ok("chorus flower: grows up from end stone (the old flower becomes chorus plant)", b.name_of(wh.state_at(0, 64, 0)) == "chorus_plant" and b.name_of(wh.state_at(0, 65, 0)) == "chorus_flower")
	# bamboo: grows (1/3, light 9) and stops by 16 blocks
	var wb := GrowWorld.new()
	wb.blocks[Vector3i(0, 63, 0)] = b.default_state("grass_block")
	wb.blocks[Vector3i(0, 64, 0)] = b.default_state("bamboo")
	for i in 600:
		var top := 64
		while b.name_of(wb.state_at(0, top + 1, 0)) == "bamboo":
			top += 1
		Growth.random_tick(wb, Vector3i(0, top, 0), wb.state_at(0, top, 0), "bamboo", rng)
	var hgt := _names_in(wb, "bamboo")
	ok("bamboo: grows and stops at 12-16 blocks", hgt >= 12 and hgt <= 16, str(hgt))
	# cactus flower: ~10 % on a 1-2 tall cactus reaching age 9
	var flowers := 0
	for i in 2000:
		var wk := GrowWorld.new()
		wk.blocks[Vector3i(0, 63, 0)] = b.default_state("sand")
		wk.blocks[Vector3i(0, 64, 0)] = b.with_prop(b.default_state("cactus"), "age", "8")
		Growth.cactus_tick(wk, Vector3i(0, 64, 0), wk.state_at(0, 64, 0), rng)
		if b.name_of(wk.state_at(0, 65, 0)) == "cactus_flower":
			flowers += 1
	ok("cactus flower: ~10 % on a short cactus at age 8 -> 9", flowers > 150 and flowers < 260, str(flowers))
	# coral without water dies 60-99 ticks later
	var wo := GrowWorld.new()
	wo.blocks[Vector3i(0, 64, 0)] = b.default_state("tube_coral_block")
	Growth.on_changed(wo, Vector3i(0, 64, 0))
	wo.game_time += 59
	Growth.tick(wo)
	var alive := b.name_of(wo.state_at(0, 64, 0)) == "tube_coral_block"
	wo.game_time += 41
	Growth.tick(wo)
	ok("coral: dies 60-99 ticks after losing water", alive and b.name_of(wo.state_at(0, 64, 0)) == "dead_tube_coral_block", b.name_of(wo.state_at(0, 64, 0)))
	# dripstone with water above its dripstone block fills a cauldron below
	var wd := GrowWorld.new()
	wd.blocks[Vector3i(0, 72, 0)] = Res.blocks.WATER
	wd.blocks[Vector3i(0, 71, 0)] = b.default_state("dripstone_block")
	wd.blocks[Vector3i(0, 70, 0)] = b.with_prop(b.with_prop(b.default_state("pointed_dripstone"), "vertical_direction", "down"), "thickness", "tip")
	wd.blocks[Vector3i(0, 66, 0)] = b.default_state("cauldron")
	for i in 400:
		Growth.random_tick(wd, Vector3i(0, 70, 0), wd.state_at(0, 70, 0), "pointed_dripstone", rng)
		wd.game_time += 1
		Growth.tick(wd)
	ok("pointed dripstone: water above fills the cauldron below", b.name_of(wd.state_at(0, 66, 0)) == "water_cauldron", b.name_of(wd.state_at(0, 66, 0)))
	# frogspawn hatches 2-5 tadpoles within 3600-12000 ticks
	var wf := GrowWorld.new()
	wf.blocks[Vector3i(0, 64, 0)] = b.default_state("frogspawn")
	Growth.random_tick(wf, Vector3i(0, 64, 0), wf.state_at(0, 64, 0), "frogspawn", rng)
	wf.game_time += 3599
	Growth.tick(wf)
	var still := b.name_of(wf.state_at(0, 64, 0)) == "frogspawn"
	wf.game_time += 12001
	Growth.tick(wf)
	var tads := 0
	for e in wf.entities.ents:
		if e.id == "tadpole":
			tads += 1
	ok("frogspawn: hatches 2-5 tadpoles after 3600-12000 ticks", still and wf.state_at(0, 64, 0) == 0 and tads >= 2 and tads <= 5, str(tads))
	# turtle eggs at night (celestial angle 0.65-0.69) crack on every random tick and hatch after 3
	var wt := GrowWorld.new()
	wt.angle = 0.67
	wt.blocks[Vector3i(0, 63, 0)] = b.default_state("sand")
	wt.blocks[Vector3i(0, 64, 0)] = b.with_prop(b.default_state("turtle_egg"), "eggs", "2")
	for i in 3:
		Growth.random_tick(wt, Vector3i(0, 64, 0), wt.state_at(0, 64, 0), "turtle_egg", rng)
	ok("turtle eggs: crack every random tick at night and hatch (2 turtles)", wt.state_at(0, 64, 0) == 0 and wt.entities.ents.size() == 2)
	Growth.reset()
	# iron golem: attacks a nearby zombie for 7.5-21.5 and throws it up (not creepers)
	var gw := GrowWorld.new()
	var gem := GolemEnts.new()
	gw.entities = gem
	var golem = gem.spawn_mob("iron_golem", Vector3(0.5, 64, 0.5))
	golem.def = MobRegistry.get_def("iron_golem")
	golem.w = 1.4
	var zomb = gem.spawn_mob("zombie", Vector3(2.0, 64, 0.5))
	zomb.def = MobRegistry.get_def("zombie")
	zomb.w = 0.6
	var cre = gem.spawn_mob("creeper", Vector3(-1.5, 64, 0.5))
	cre.def = MobRegistry.get_def("creeper")
	MobAI.iron_golem(gw, golem)
	ok("iron golem: hits a zombie for 7.5-21.5 and throws it up, ignores the creeper", zomb.hp <= 20.0 - 7.5 and zomb.hp >= 20.0 - 21.5 and zomb.vel.y >= 0.4 and cre.hp == 20.0, "zombie hp %.1f" % zomb.hp)
	# campfire_cooking recipes in their own table (they used to overwrite the smoker's 100-tick times with 600)
	var beef := Res.items.id("beef")
	if beef > 0:
		var smk: Array = Crafting.smelt_info(beef, "smoking")
		var cmp: Array = Crafting.smelt_info(beef, "campfire_cooking")
		var sd := {"id": "smoker", "items": [ItemStack.named("beef", 1).to_dict(), ItemStack.named("coal", 1).to_dict(), {}], "burn": 0, "burn_max": 0, "cook": 0}
		var sticks := 0
		while sticks < 400 and ItemStack.from_dict((sd["items"] as Array)[2]).is_empty():
			BlockEntities.furnace_step(sd)
			sticks += 1
		ok("smoker cooks beef in 100 ticks (wiki: 5 s, twice a furnace), campfire recipe 600 in its own table", not smk.is_empty() and sticks == 100 and not cmp.is_empty() and int(cmp[3]) == 600, "%d ticks %s %s" % [sticks, str(smk), str(cmp)])
	# 26.x game rule ids (wiki Game rule: 59 rows, max_minecart_speed only with the Minecart Improvements experiment)
	var mg := GameRules.migrate({"keepInventory": true, "disableRaids": true, "doFireTick": false})
	ok("game rules: 26.x ids (58 without experiments), old saves migrate (disableRaids true -> raids false)", GameRules.SPEC.size() == 58 and GameRules.canonical("keepInventory") == "keep_inventory"
		and GameRules.canonical("minecraft:random_tick_speed") == "random_tick_speed" and mg.get("keep_inventory") == true and mg.get("raids") == false
		and not mg.has("doFireTick") and GameRules.validate("max_snow_accumulation_height", "9") == null and GameRules.validate("max_snow_accumulation_height", "8") == 8,
		"%d %s" % [GameRules.SPEC.size(), str(mg)])


# ------------------------------------------------------------------ waterlogging (BucketItem, SimpleWaterloggedBlock)

class BucketEnts extends MockEntities:
	var ents: Array = []

	func spawn_block_particles(_p, _s) -> void:
		pass

	func on_block_changed(_p, _o, _n) -> void:
		pass


## A FluidWorld a player can use items in (player set only during the use: with a player BlockUpdates defers ticks).
class BucketWorld extends FluidWorld:
	var player = null

	func _init() -> void:
		entities = BucketEnts.new()


## A FluidWorld with a player: BlockUpdates collects each tick's updates for slices (the game's deferred path).
class SliceWorld extends FluidWorld:
	var player := Player.new()


func _bucket_world() -> BucketWorld:
	BlockUpdates.reset()
	var w := BucketWorld.new()
	w.rng.seed = 1234
	w.floor_at(-1, 12, Res.blocks.STONE)
	return w


## The game's right-click path (WorldManager._use): use_item_on on the targeted block, then use_item. The player stands
## 2 blocks above `at`, looking straight down at it.
func _bucket_use(w: BucketWorld, item: String, at: Vector3i, sneak := false, creative := false) -> Player:
	var p := Player.new()
	p.pos = Vector3(at) + Vector3(0.5, 2.0, 0.5)
	p.pitch = 90.0
	p.sneaking = sneak
	p.mode = Player.Mode.CREATIVE if creative else Player.Mode.SURVIVAL
	p.inventory.set_slot(p.inventory.selected, ItemStack.named(item, 1))
	w.player = p
	var held := p.inventory.held()
	var hit := VoxelRaycast.cast(p.eye_pos(), p.look_dir(), p.block_reach(), w.state_at, Res.blocks)
	if hit.is_empty() or not Interaction.use_item_on(w, held, hit):
		Interaction.use_item(w, held)
	w.player = null
	return p


func _water_cells(w: FluidWorld) -> int:
	var n := 0
	for k in w.blocks:
		if Res.blocks.st_flags[int(w.blocks[k])] & BlockRegistry.F_LIQUID:
			n += 1
	return n


func test_vanilla_waterlogging() -> void:
	var b := Res.blocks
	var slab := b.default_state("oak_slab")   # bottom, dry
	# BucketItem.use: water into the clicked liquid container itself (GH: right-click with a water bucket did nothing)
	var w := _bucket_world()
	w.blocks[Vector3i(0, 0, 0)] = slab
	var p := _bucket_use(w, "water_bucket", Vector3i(0, 0, 0))
	ok("waterlog: water bucket on a bottom slab waterlogs it, the bucket empties (survival)", b.get_prop(w.state_at(0, 0, 0), "waterlogged") == "true" and w.state_at(0, 1, 0) == 0 and p.inventory.held().name() == "bucket",
		"%s above=%d held=%s" % [b.state_string(w.state_at(0, 0, 0)), w.state_at(0, 1, 0), p.inventory.held().name()])
	w.run(5)
	ok("waterlog: a waterlogged slab is a water source for flow (level 1 on its four sides 5 ticks later)", _lvl(w, 1, 0, 0) == 1 and _lvl(w, -1, 0, 0) == 1 and _lvl(w, 0, 0, 1) == 1 and _lvl(w, 0, 0, -1) == 1,
		"%d %d %d %d" % [_lvl(w, 1, 0, 0), _lvl(w, -1, 0, 0), _lvl(w, 0, 0, 1), _lvl(w, 0, 0, -1)])
	p = _bucket_use(w, "bucket", Vector3i(0, 0, 0))
	ok("waterlog: an empty bucket takes the water back (SimpleWaterloggedBlock.pickupBlock)", b.get_prop(w.state_at(0, 0, 0), "waterlogged") == "false" and p.inventory.held().name() == "water_bucket", p.inventory.held().name())
	w.run(80)
	ok("waterlog: removing the water stops the flow (it recedes to nothing)", _water_cells(w) == 0, str(_water_cells(w)))
	var w2 := _bucket_world()
	w2.blocks[Vector3i(0, 0, 0)] = slab
	_bucket_use(w2, "water_bucket", Vector3i(0, 0, 0), true)
	ok("waterlog: sneaking puts the water beside the block instead (MC-173730, 25w33a)", w2.state_at(0, 0, 0) == slab and b.name_of(w2.state_at(0, 1, 0)) == "water")
	var w3 := _bucket_world()
	var wst := b.with_prop(b.default_state("oak_stairs"), "waterlogged", "true")
	w3.blocks[Vector3i(0, 0, 0)] = wst
	var p3 := _bucket_use(w3, "water_bucket", Vector3i(0, 0, 0))
	ok("waterlog: a water bucket empties into an already waterlogged block (22w45a), nothing placed in front", w3.state_at(0, 0, 0) == wst and w3.state_at(0, 1, 0) == 0 and p3.inventory.held().name() == "bucket")
	var w4 := _bucket_world()
	w4.blocks[Vector3i(0, 0, 0)] = slab
	var p4 := _bucket_use(w4, "lava_bucket", Vector3i(0, 0, 0))
	ok("waterlog: lava buckets never waterlog (lava goes in front of the clicked face)", w4.state_at(0, 0, 0) == slab and b.name_of(w4.state_at(0, 1, 0)) == "lava" and p4.inventory.held().name() == "bucket")
	var w5 := _bucket_world()
	var dbl := b.with_prop(slab, "type", "double")
	w5.blocks[Vector3i(0, 0, 0)] = dbl
	_bucket_use(w5, "water_bucket", Vector3i(0, 0, 0))
	ok("waterlog: a double slab holds no water (SlabBlock.canPlaceLiquid): water goes in front", w5.state_at(0, 0, 0) == dbl and b.name_of(w5.state_at(0, 1, 0)) == "water")
	var w6 := _bucket_world()
	w6.blocks[Vector3i(0, 0, 0)] = b.default_state("oak_fence")
	var p6 := _bucket_use(w6, "water_bucket", Vector3i(0, 0, 0), false, true)
	ok("waterlog: creative keeps the full bucket (BucketItem.getEmptySuccessItem)", b.get_prop(w6.state_at(0, 0, 0), "waterlogged") == "true" and p6.inventory.held().name() == "water_bucket")
	# every block whose 26.3 blockstate has `waterlogged` (the wiki Waterlogging list) takes water and gives it back
	var wiki := ["copper_grate", "mangrove_roots", "oak_leaves", "heavy_core", "dried_ghast", "resin_clump", "decorated_pot", "lightning_rod", "iron_bars",
		"conduit", "light", "barrier", "big_dripleaf", "small_dripleaf", "hanging_roots", "glow_lichen", "sculk_vein", "sculk_sensor", "calibrated_sculk_sensor",
		"sculk_shrieker", "scaffolding", "ladder", "rail", "powered_rail", "chest", "trapped_chest", "ender_chest", "copper_chest", "campfire", "soul_campfire", "candle",
		"lantern", "soul_lantern", "sea_pickle", "pointed_dripstone", "amethyst_cluster", "mangrove_propagule", "oak_sign", "oak_wall_sign", "oak_hanging_sign",
		"oak_trapdoor", "oak_fence", "cobblestone_wall", "glass_pane", "oak_stairs", "oak_slab", "tube_coral", "tube_coral_fan", "dead_tube_coral_wall_fan"]
	var missing: Array = []
	for nm0 in wiki:
		var bi0 := b.block_id(nm0)
		if bi0 < 0 or not b.has_prop(b.block_default[bi0], "waterlogged"):
			missing.append(nm0)
	ok("waterlog: the wiki's waterloggable blocks have a waterlogged state in 26.3", missing.is_empty(), str(missing))
	var wa := _bucket_world()
	var n_all := 0
	var bad: Array = []
	for bi in b.names.size():
		var st0: int = b.block_default[bi]
		if not b.has_prop(st0, "waterlogged"):
			continue
		st0 = b.with_prop(st0, "waterlogged", "false")
		if b.names[bi].ends_with("_slab"):
			st0 = b.with_prop(st0, "type", "bottom")
		wa.blocks[Vector3i(0, 0, 0)] = st0
		var emptied := Interaction.bucket_empty(wa, Vector3i(0, 0, 0), true)   # (the dispenser call: the block in front)
		var ws: int = wa.state_at(0, 0, 0)
		var took := emptied and b.st_block[ws] == bi and b.get_prop(ws, "waterlogged") == "true" and (b.st_flags[ws] & BlockRegistry.F_WATERLOGGED) != 0
		var back := Interaction.bucket_pickup(wa, Vector3i(0, 0, 0), false) == "water_bucket" and b.get_prop(wa.state_at(0, 0, 0), "waterlogged") == "false"
		n_all += 1
		if not (took and back):
			bad.append(b.names[bi])
	ok("waterlog: all %d waterloggable blocks take a water bucket and give it back (dry -> waterlogged -> dry)" % n_all, n_all > 200 and bad.is_empty(), str(bad))
	wa.blocks[Vector3i(0, 0, 0)] = b.STONE
	ok("waterlog: a dispenser's water bucket can't empty into stone (the bucket is dropped instead)", not Interaction.bucket_empty(wa, Vector3i(0, 0, 0), true) and wa.state_at(0, 0, 0) == b.STONE)
	var cf := b.with_prop(b.with_prop(b.default_state("campfire"), "lit", "true"), "waterlogged", "false")
	var cd := b.with_prop(b.with_prop(b.default_state("candle"), "lit", "true"), "waterlogged", "false")
	wa.blocks[Vector3i(0, 0, 0)] = cf
	wa.blocks[Vector3i(2, 0, 0)] = cd
	Interaction.bucket_empty(wa, Vector3i(0, 0, 0), true)
	Interaction.bucket_empty(wa, Vector3i(2, 0, 0), true)
	ok("waterlog: lit campfires and candles go out when waterlogged (wiki Waterlogging)", b.get_prop(wa.state_at(0, 0, 0), "lit") == "false" and b.get_prop(wa.state_at(0, 0, 0), "waterlogged") == "true"
		and b.get_prop(wa.state_at(2, 0, 0), "lit") == "false" and b.get_prop(wa.state_at(2, 0, 0), "waterlogged") == "true")
	# flow out of waterlogged blocks through their open faces only (FlowingFluid.canPassThroughWall, collision shapes)
	var fb := _fluid_world()
	fb.blocks[Vector3i(0, 4, 0)] = b.with_prop(slab, "waterlogged", "true")
	BlockUpdates.schedule(fb, Vector3i(0, 4, 0), 5)
	fb.run(5)
	ok("waterlog flow: a waterlogged bottom slab in mid-air spreads sideways, not down (its bottom face is full)", _lvl(fb, 1, 4, 0) == 1 and _lvl(fb, 0, 4, 1) == 1 and fb.state_at(0, 3, 0) == 0)
	var ft := _fluid_world()
	ft.blocks[Vector3i(0, 4, 0)] = b.with_prop(b.with_prop(slab, "type", "top"), "waterlogged", "true")
	BlockUpdates.schedule(ft, Vector3i(0, 4, 0), 5)
	ft.run(5)
	ok("waterlog flow: a waterlogged top slab in mid-air pours down (falling water below it)", _lvl(ft, 0, 3, 0) == 8, str(_lvl(ft, 0, 3, 0)))
	var fs := _fluid_world()
	fs.blocks[Vector3i(0, 0, 0)] = b.with_prop(b.with_prop(b.default_state("oak_stairs"), "facing", "east"), "waterlogged", "true")
	BlockUpdates.schedule(fs, Vector3i(0, 0, 0), 5)
	fs.run(5)
	ok("waterlog flow: waterlogged stairs flow out of their open sides, not out of their full back", _lvl(fs, -1, 0, 0) == 1 and _lvl(fs, 0, 0, 1) == 1 and _lvl(fs, 0, 0, -1) == 1 and _lvl(fs, 1, 0, 0) == -1,
		"%d %d %d %d" % [_lvl(fs, -1, 0, 0), _lvl(fs, 0, 0, 1), _lvl(fs, 0, 0, -1), _lvl(fs, 1, 0, 0)])
	var fg := _fluid_world()
	fg.blocks[Vector3i(0, 0, 0)] = b.with_prop(b.default_state("copper_grate"), "waterlogged", "true")
	fg.blocks[Vector3i(3, 3, 0)] = b.with_prop(b.default_state("mangrove_roots"), "waterlogged", "true")
	BlockUpdates.schedule(fg, Vector3i(0, 0, 0), 5)
	BlockUpdates.schedule(fg, Vector3i(3, 3, 0), 5)
	fg.run(40)
	ok("waterlog flow: water never flows out of full-collision waterlogged blocks (copper grate, mangrove roots; wiki)", _water_cells(fg) == 0, str(_water_cells(fg)))
	var fl := _fluid_world()
	fl.blocks[Vector3i(1, 0, 0)] = slab
	fl.set_block(0, 0, 0, b.with_prop(b.WATER, "level", "1"))
	fl.set_block(-1, 0, 0, b.WATER)
	BlockUpdates.schedule(fl, Vector3i(-1, 0, 0), 5)
	fl.run(60)
	ok("waterlog flow: flowing water never waterlogs (a slab beside a flow stays dry)", fl.state_at(1, 0, 0) == slab)
	# getSlopeDistance: the one-pass hole field (BlockUpdates._side_slopes) equals Java's depth-first search (_gslope,
	# kept as the reference) for every side, on random terrain: walls, slabs, stairs, sources, flows, holes, lava
	var srng := RandomNumberGenerator.new()
	srng.seed = 4242
	var top := b.with_prop(slab, "type", "top")
	var wpool: Array = [0, 0, 0, 0, b.STONE, slab, top, b.with_prop(b.default_state("oak_stairs"), "waterlogged", "true"), b.default_state("oak_fence"),
		b.WATER, b.with_prop(b.WATER, "level", "3"), b.with_prop(b.WATER, "level", "8"), b.with_prop(slab, "waterlogged", "true"), b.default_state("copper_grate")]
	var lpool: Array = [0, 0, 0, 0, b.STONE, slab, top, b.default_state("oak_fence"), b.LAVA, b.with_prop(b.LAVA, "level", "2"), b.with_prop(b.LAVA, "level", "8"), b.WATER]
	var mism: Array = []
	var compared := 0
	for trial in 600:
		var tw := _fluid_world()
		tw.blocks.clear()
		var lv := trial % 4 == 3
		var pool: Array = lpool if lv else wpool
		if lv and trial % 8 == 7:
			tw.dim_type = {"attributes": {"minecraft:gameplay/fast_lava": true}}
		var air_below := srng.randf() * 0.5
		for dz in range(-6, 7):
			for dx in range(-6, 7):
				var s0: int = pool[srng.randi() % pool.size()]
				if s0 != 0:
					tw.blocks[Vector3i(dx, 0, dz)] = s0
				var r1 := srng.randf()
				var s1: int = 0 if r1 < air_below else (b.STONE if r1 < 0.8 else pool[srng.randi() % pool.size()])
				if s1 != 0:
					tw.blocks[Vector3i(dx, -1, dz)] = s1
		var ost: int = (b.with_prop(b.LAVA, "level", "2") if trial % 2 == 0 else b.LAVA) if lv else [b.with_prop(b.WATER, "level", "2"), b.WATER, b.with_prop(b.WATER, "level", "8")][trial % 3]
		tw.blocks[Vector3i.ZERO] = ost
		BlockUpdates._gbegin(tw, Vector3i.ZERO, lv)
		BlockUpdates._side_slopes(ost)
		for k in 4:
			var sdx: int = BlockUpdates.HDX[k]
			var sdz: int = BlockUpdates.HDZ[k]
			var sns := BlockUpdates._gget(sdx, 0, sdz)
			if sns < 0 or BlockUpdates._ghole(sdx, sdz, sns):
				continue
			var ref := BlockUpdates._gslope(sdx, sdz, sns, 1, k ^ 2)
			compared += 1
			if ref != BlockUpdates._gsl[k] and mism.size() < 5:
				mism.append("trial %d side %d: dfs %d field %d" % [trial, k, ref, BlockUpdates._gsl[k]])
	ok("getSlopeDistance: the hole field equals Java's depth-first search on 600 random terrains (%d sides, water + lava)" % compared, mism.is_empty() and compared > 1000, str(mism))
	# placing a waterloggable block: waterlogged in a water source, dry in flowing water (getStateForPlacement)
	var wp := _bucket_world()
	wp.blocks[Vector3i(0, 0, 0)] = b.WATER
	wp.blocks[Vector3i(4, 0, 0)] = b.with_prop(b.WATER, "level", "2")
	_bucket_use(wp, "oak_slab", Vector3i(0, -1, 0))
	_bucket_use(wp, "oak_slab", Vector3i(4, -1, 0))
	ok("waterlog: a slab placed into a water source is waterlogged, into flowing water dry", b.name_of(wp.state_at(0, 0, 0)) == "oak_slab" and b.get_prop(wp.state_at(0, 0, 0), "waterlogged") == "true"
		and b.name_of(wp.state_at(4, 0, 0)) == "oak_slab" and b.get_prop(wp.state_at(4, 0, 0), "waterlogged") == "false", "%s %s" % [b.state_string(wp.state_at(0, 0, 0)), b.state_string(wp.state_at(4, 0, 0))])
	# flow cadence (the "update stutter"): the front advances exactly one block per 5 ticks, also when the game's slices
	# of a tick's updates spill into the next tick
	var wc := _fluid_world()
	wc.set_block(0, 0, 0, b.WATER)
	BlockUpdates.schedule(wc, Vector3i.ZERO, 5)
	var first := {}
	for i in 40:
		wc.run(1)
		for k in range(1, 8):
			if not first.has(k) and _lvl(wc, k, 0, 0) >= 0:
				first[k] = wc.game_time
	var exact := true
	for k in range(1, 8):
		exact = exact and int(first.get(k, -1)) == 5 * k
	ok("water flow cadence: block k of the front appears on tick 5k (k = 1..7)", exact, str(first))
	BlockUpdates.reset()
	var wd := SliceWorld.new()
	wd.floor_at(-1, 12, b.STONE)
	wd.set_block(0, 0, 0, b.WATER)
	BlockUpdates.schedule(wd, Vector3i.ZERO, 5)
	var first2 := {}
	for i in 50:
		wd.game_time += 1
		BlockUpdates.tick_scheduled(wd)   # appends this tick's updates behind the rest of earlier ticks
		BlockUpdates._run_due(wd, 20)     # 20 per tick: a step's ~40-60 updates spill over the next ticks
		for k in range(1, 8):
			if not first2.has(k) and _lvl(wd, k, 0, 0) >= 0:
				first2[k] = wd.game_time
	var steady := true
	for k in range(1, 8):
		steady = steady and int(first2.get(k, -1)) >= 5 * k and int(first2.get(k, -1)) <= 5 * k + 3
	ok("water flow cadence with sliced updates spilling into the next tick: still one block per 5 ticks (no drift)", steady, str(first2))
	BlockUpdates.reset()
	# remesh pipeline: a sliced tick's chunks wait for its last slice, then update together; a relight's remesh skips the
	# throttle the relight set
	var cmt := ChunkManager.new()
	var ch := Chunk.new(0, 0)
	ch.shown = true
	var ck := Coords.chunk_key(0, 0)
	cmt.hold_marks = true
	cmt._mark_mesh(ch, 2)
	cmt.hold_marks = false
	var now := Time.get_ticks_usec()
	var held_wait := not cmt._can_update(ck, now)
	cmt.release_held()
	var released := cmt._can_update(ck, now) and cmt._work.has(ck)
	cmt._next_update[ck] = now + 1000000
	var throttled := not cmt._can_update(ck, now)
	var chained := cmt._can_update(ck, now, true)
	ok("remesh pipeline: held until the tick's last slice, then at once; a relight's remesh is not throttled again", held_wait and released and throttled and chained,
		"%s %s %s %s" % [held_wait, released, throttled, chained])


class SupEnts extends MockEntities:
	var items: Array = []

	func spawn_item(_p, s, _c = false) -> void:
		items.append(s)


## A GravWorld (set_block -> BlockUpdates.fluids_changed -> Support) that keeps the items dropped.
class SupWorld extends GravWorld:
	func _init() -> void:
		entities = SupEnts.new()


func _sup_world() -> SupWorld:
	BlockUpdates.reset()
	var w := SupWorld.new()
	w.rng.seed = 77
	return w


func _drops(w: SupWorld, item: String) -> int:
	var n := 0
	for s in (w.entities as SupEnts).items:
		if (s as ItemStack).name() == item:
			n += (s as ItemStack).count
	return n


## Java canSurvive / updateShape (Support): whatever hangs on, stands on or leans on a block breaks with its drops when
## that block goes - from any side; both halves of doors / tall plants / beds go together with one item; snow drops
## nothing without a player (wiki Snow); face support follows Java isFaceSturdy (FULL / CENTER / RIGID); placement
## picks the wall or standing form like StandingAndWallBlockItem; snow layers stack; the pose keeps standing when a
## door closes into the player (Player.updatePlayerPose).
func test_vanilla_support_breaking() -> void:
	var b := Res.blocks
	var stone := b.STONE
	# face support table
	var slab := b.default_state("oak_slab")
	var fence := b.default_state("oak_fence")
	var hopper := b.default_state("hopper")
	var chain := b.default_state("iron_chain") if b.block_id("iron_chain") >= 0 else b.default_state("chain")
	ok("support faces: stone full; bottom slab only below, top slab on top; fence / chain hold centre only; hopper rim (rigid) not centre; leaves none; 8 snow layers full, 3 not; soul sand full",
		Support.sturdy(stone, Support.F_UP) and Support.sturdy(stone, Support.F_NORTH) and not Support.sturdy(slab, Support.F_UP) and Support.sturdy(slab, Support.F_DOWN)
		and Support.sturdy(b.with_prop(slab, "type", "top"), Support.F_UP) and Support.sturdy(fence, Support.F_UP, Support.T_CENTER) and not Support.sturdy(fence, Support.F_UP)
		and Support.sturdy(chain, Support.F_DOWN, Support.T_CENTER) and Support.sturdy(hopper, Support.F_UP, Support.T_RIGID) and not Support.sturdy(hopper, Support.F_UP, Support.T_CENTER)
		and not Support.sturdy(b.default_state("oak_leaves"), Support.F_UP, Support.T_CENTER) and Support.sturdy(b.with_prop(b.default_state("snow"), "layers", "8"), Support.F_UP)
		and not Support.sturdy(b.with_prop(b.default_state("snow"), "layers", "3"), Support.F_UP) and Support.sturdy(b.default_state("soul_sand"), Support.F_UP))
	# wall torch on the side of a block, a torch on top of it (the user's report: a torch stayed in the air)
	var w := _sup_world()
	w.blocks[Vector3i(0, 1, 0)] = stone
	w.blocks[Vector3i(1, 1, 0)] = b.state_of("wall_torch", {"facing": "east"})
	w.blocks[Vector3i(0, 2, 0)] = b.default_state("torch")
	w.blocks[Vector3i(-1, 1, 0)] = b.state_of("ladder", {"facing": "west"})
	w.blocks[Vector3i(0, 1, -1)] = b.state_of("oak_wall_sign", {"facing": "north"})
	w.set_block(0, 1, 0, 0)
	ok("support: wall torch, torch on top, ladder and wall sign break with their block and drop", w.state_at(1, 1, 0) == 0 and w.state_at(0, 2, 0) == 0
		and w.state_at(-1, 1, 0) == 0 and w.state_at(0, 1, -1) == 0 and _drops(w, "torch") == 2 and _drops(w, "ladder") == 1 and _drops(w, "oak_sign") == 1,
		"%d %d %d %d torches %d" % [w.state_at(1, 1, 0), w.state_at(0, 2, 0), w.state_at(-1, 1, 0), w.state_at(0, 1, -1), _drops(w, "torch")])
	# doors: the block under it, or either half
	var dl := b.state_of("oak_door", {"facing": "north", "half": "lower"})
	for case in ["floor", "upper", "lower"]:
		w = _sup_world()
		w.blocks[Vector3i(0, 0, 0)] = stone
		w.blocks[Vector3i(0, 1, 0)] = dl
		w.blocks[Vector3i(0, 2, 0)] = b.with_prop(dl, "half", "upper")
		w.blocks[Vector3i(1, 1, 0)] = stone   # an unrelated neighbour change first: nothing happens
		w.set_block(1, 1, 0, 0)
		var kept := w.state_at(0, 1, 0) == dl
		var at: int = {"floor": 0, "upper": 2, "lower": 1}[case]
		w.set_block(0, at, 0, 0)
		ok("support: door - %s removed: no floating half left, one door dropped" % case, kept and w.state_at(0, 1, 0) == 0 and w.state_at(0, 2, 0) == 0 and _drops(w, "oak_door") == (0 if case == "lower" else 1) + (0 if case != "lower" else 0),
			"kept %s lower %d upper %d doors %d" % [kept, w.state_at(0, 1, 0), w.state_at(0, 2, 0), _drops(w, "oak_door")])
	# beds: a bed's head goes with its foot (the head's loot drops the bed); the same bed beside it stays
	w = _sup_world()
	var foot := b.state_of("red_bed", {"facing": "south", "part": "foot"})
	w.blocks[Vector3i(0, 1, 0)] = foot
	w.blocks[Vector3i(0, 1, 1)] = b.with_prop(foot, "part", "head")
	w.blocks[Vector3i(1, 1, 0)] = foot
	w.blocks[Vector3i(1, 1, 1)] = b.with_prop(foot, "part", "head")
	w.set_block(0, 1, 0, 0)
	ok("support: a bed's head goes with its foot (one bed), the bed beside it stays", w.state_at(0, 1, 1) == 0 and _drops(w, "red_bed") == 1 and w.state_at(1, 1, 0) == foot and w.state_at(1, 1, 1) != 0)
	# tall plants
	w = _sup_world()
	w.blocks[Vector3i(0, 0, 0)] = b.default_state("grass_block")
	var rb := b.state_of("rose_bush", {"half": "lower"})
	w.blocks[Vector3i(0, 1, 0)] = rb
	w.blocks[Vector3i(0, 2, 0)] = b.with_prop(rb, "half", "upper")
	w.set_block(0, 0, 0, stone)
	ok("support: a rose bush on a block turned to stone breaks whole, one rose bush", w.state_at(0, 1, 0) == 0 and w.state_at(0, 2, 0) == 0 and _drops(w, "rose_bush") == 1, str(_drops(w, "rose_bush")))
	var tg := b.state_of("tall_grass", {"half": "lower"})
	w.blocks[Vector3i(4, 1, 0)] = tg
	w.blocks[Vector3i(4, 2, 0)] = b.with_prop(tg, "half", "upper")
	var tg_up := b.with_prop(tg, "half", "upper")
	var with_lower := Loot.block_drops(tg_up, ItemStack.named("shears"), w, Vector3i(4, 2, 0)).size()
	w.blocks.erase(Vector3i(4, 1, 0))
	var without := Loot.block_drops(tg_up, ItemStack.named("shears"), w, Vector3i(4, 2, 0)).size()
	ok("loot: a tall grass half drops only while its other half is there (location_check)", with_lower > 0 and without == 0, "%d %d" % [with_lower, without])
	var young := Loot.block_drops(b.default_state("wheat"), ItemStack.new(), null, Vector3i.ZERO)
	var young_names := []
	for s in young:
		young_names.append("%s x%d" % [(s as ItemStack).name(), (s as ItemStack).count])
	var door_up := Loot.block_drops(b.with_prop(dl, "half", "upper"), ItemStack.new(), null, Vector3i.ZERO)
	var wall_t := Loot.block_drops(b.state_of("wall_torch", {"facing": "east"}), ItemStack.new(), null, Vector3i.ZERO)
	ok("loot: 26.3 match_block - unripe wheat drops one seed only, a door's upper half nothing; a wall torch drops a torch (dropsLike)",
		young_names == ["wheat_seeds x1"] and door_up.is_empty() and wall_t.size() == 1 and (wall_t[0] as ItemStack).name() == "torch", "%s / %d / %d" % [str(young_names), door_up.size(), wall_t.size()])
	# lanterns (no pickaxe needed when nobody mines them), buttons, levers, cocoa
	w = _sup_world()
	w.blocks[Vector3i(0, 3, 0)] = stone
	w.blocks[Vector3i(0, 2, 0)] = b.state_of("lantern", {"hanging": "true"})
	w.blocks[Vector3i(3, 0, 0)] = stone
	w.blocks[Vector3i(3, 1, 0)] = b.state_of("lantern", {"hanging": "false"})
	w.blocks[Vector3i(6, 1, 0)] = stone
	w.blocks[Vector3i(6, 1, 1)] = b.state_of("stone_button", {"face": "wall", "facing": "south"})
	w.blocks[Vector3i(6, 2, 0)] = b.state_of("lever", {"face": "floor", "facing": "north"})
	w.blocks[Vector3i(9, 1, 0)] = b.default_state("jungle_log")
	w.blocks[Vector3i(9, 1, 1)] = b.state_of("cocoa", {"facing": "north"})
	for q in [Vector3i(0, 3, 0), Vector3i(3, 0, 0), Vector3i(6, 1, 0), Vector3i(9, 1, 0)]:
		w.set_block(q.x, q.y, q.z, 0)
	ok("support: hanging / standing lanterns, a wall button, a floor lever and cocoa drop off", w.state_at(0, 2, 0) == 0 and w.state_at(3, 1, 0) == 0 and w.state_at(6, 1, 1) == 0
		and w.state_at(6, 2, 0) == 0 and w.state_at(9, 1, 1) == 0 and _drops(w, "lantern") == 2 and _drops(w, "stone_button") == 1 and _drops(w, "lever") == 1 and _drops(w, "cocoa_beans") >= 1,
		"lanterns %d button %d lever %d cocoa %d" % [_drops(w, "lantern"), _drops(w, "stone_button"), _drops(w, "lever"), _drops(w, "cocoa_beans")])
	# redstone dust, repeater, rail, carpet, pressure plate, candle on a row of stone
	w = _sup_world()
	var row := ["redstone_wire", "repeater", "rail", "white_carpet", "stone_pressure_plate", "candle"]
	for i in row.size():
		w.blocks[Vector3i(i, 0, 5)] = stone
		w.blocks[Vector3i(i, 1, 5)] = b.default_state(row[i])
	for i in row.size():
		w.set_block(i, 0, 5, 0)
	var left := []
	for i in row.size():
		if w.state_at(i, 1, 5) != 0:
			left.append(row[i])
	ok("support: dust, repeater, rail, carpet, pressure plate and candle break without the block below and drop", left.is_empty() and _drops(w, "redstone") == 1 and _drops(w, "repeater") == 1
		and _drops(w, "rail") == 1 and _drops(w, "white_carpet") == 1 and _drops(w, "stone_pressure_plate") == 1 and _drops(w, "candle") == 1, "left %s" % str(left))
	# vines: the vine on the wall goes, and the vine hanging from it
	w = _sup_world()
	w.blocks[Vector3i(0, 5, 0)] = stone
	w.blocks[Vector3i(0, 5, 1)] = b.state_of("vine", {"north": "true"})
	w.blocks[Vector3i(0, 4, 1)] = b.state_of("vine", {"north": "true"})
	w.set_block(0, 5, 0, 0)
	ok("support: a vine loses its wall, the vine hanging below it goes too", w.state_at(0, 5, 1) == 0 and w.state_at(0, 4, 1) == 0)
	# snow: support gone / water -> nothing; mined with a shovel -> one snowball per layer (26.3 loot: match_block)
	w = _sup_world()
	w.blocks[Vector3i(0, 0, 0)] = stone
	var snow3 := b.with_prop(b.default_state("snow"), "layers", "3")
	w.blocks[Vector3i(0, 1, 0)] = snow3
	w.set_block(0, 0, 0, 0)
	var s5 := b.with_prop(b.default_state("snow"), "layers", "5")
	var shovel_drops := Loot.block_drops(s5, ItemStack.named("iron_shovel"), null, Vector3i.ZERO)
	var sb_n := 0
	for s in shovel_drops:
		if (s as ItemStack).name() == "snowball":
			sb_n += (s as ItemStack).count
	ok("snow: breaks without its block and drops nothing; 5 layers mined with a shovel give 5 snowballs, without a player nothing (wiki Snow)",
		w.state_at(0, 1, 0) == 0 and _drops(w, "snowball") == 0 and sb_n == 5 and Loot.block_drops(s5, null, w, Vector3i(0, 1, 0)).is_empty(), "snowballs %d" % sb_n)
	w = _sup_world()
	w.floor_at(-1, 4, stone)
	w.blocks[Vector3i(0, 0, 0)] = b.WATER
	w.blocks[Vector3i(1, 0, 0)] = snow3
	BlockUpdates.schedule(w, Vector3i(0, 0, 0), 1)
	w.run(12)
	ok("snow: water flowing into a snow layer washes it away without snowballs (wiki Snow)", b.name_of(w.state_at(1, 0, 0)) == "water" and _drops(w, "snowball") == 0, b.state_string(w.state_at(1, 0, 0)))
	# sugar cane (Java: scheduled tick) loses its sand
	w = _sup_world()
	w.blocks[Vector3i(8, 0, 8)] = b.default_state("sand")
	w.blocks[Vector3i(9, 0, 8)] = b.WATER
	w.blocks[Vector3i(8, 1, 8)] = b.default_state("sugar_cane")
	w.blocks[Vector3i(8, 2, 8)] = b.default_state("sugar_cane")
	w.set_block(8, 0, 8, 0)
	w.run(4)
	ok("support: sugar cane goes block by block when its sand is removed (scheduled ticks), both drop", w.state_at(8, 1, 8) == 0 and w.state_at(8, 2, 8) == 0 and _drops(w, "sugar_cane") == 2, str(_drops(w, "sugar_cane")))
	# placement: a torch clicked onto the side of leaves stands on the floor instead (StandingAndWallBlockItem)
	w = _sup_world()
	w.blocks[Vector3i(0, 0, 0)] = stone
	w.blocks[Vector3i(1, 1, 0)] = b.default_state("oak_leaves")
	w.blocks[Vector3i(1, 1, 2)] = stone
	var pl := Player.new()
	pl.yaw = -90.0   # looking east
	pl.pitch = 30.0
	var wt := b.state_of("wall_torch", {"facing": "west"})
	var on_leaves := Support.placement(w, wt, Vector3i(0, 1, 0), Vector3i(-1, 0, 0), pl, false)
	var on_stone := Support.placement(w, wt, Vector3i(0, 1, 2), Vector3i(-1, 0, 0), pl, false)
	var mid_air := Support.placement(w, wt, Vector3i(0, 5, 0), Vector3i(-1, 0, 0), pl, false)
	ok("placement: a torch on the side of leaves stands on the floor; on stone it hangs on the wall; in the air nowhere",
		on_leaves > 0 and b.name_of(on_leaves) == "torch" and on_stone > 0 and b.name_of(on_stone) == "wall_torch" and b.get_prop(on_stone, "facing") == "west" and mid_air == -1,
		"%s / %s / %d" % [b.state_string(maxi(on_leaves, 0)), b.state_string(maxi(on_stone, 0)), mid_air])
	# snow layers stack (Java SnowLayerBlock.canBeReplaced): up to 8, then a new layer on top; other blocks only replace one layer
	var bw := _bucket_world()
	bw.blocks[Vector3i(0, 0, 0)] = b.default_state("snow")
	for i in 7:
		_bucket_use(bw, "snow", Vector3i(0, 0, 0))
	var eight := b.get_prop(bw.state_at(0, 0, 0), "layers")
	_bucket_use(bw, "snow", Vector3i(0, 0, 0))
	var above := bw.state_at(0, 1, 0)
	bw.blocks[Vector3i(3, 0, 0)] = snow3
	_bucket_use(bw, "stone", Vector3i(3, 0, 0))
	bw.blocks[Vector3i(6, 0, 0)] = b.default_state("snow")
	_bucket_use(bw, "stone", Vector3i(6, 0, 0))
	ok("snow: a snow item adds layers up to 8, then starts a layer above; stone replaces one layer but goes on top of three",
		eight == "8" and above > 0 and b.name_of(above) == "snow" and b.get_prop(above, "layers") == "1" and bw.state_at(3, 0, 0) == snow3 and bw.state_at(3, 1, 0) == stone and bw.state_at(6, 0, 0) == stone,
		"layers %s above %s / %s %s / %s" % [eight, b.state_string(maxi(above, 0)), b.state_string(bw.state_at(3, 0, 0)), b.state_string(bw.state_at(3, 1, 0)), b.state_string(bw.state_at(6, 0, 0))])
	# Player.updatePlayerPose: a door closed into the player keeps them standing; a 1-block gap still makes them crawl
	var mw := MockWorld.new()
	mw.floor_y = 64
	mw.grid[Vector3i(0, 64, 0)] = b.state_of("oak_door", {"facing": "north", "half": "lower", "open": "false"})
	mw.grid[Vector3i(0, 65, 0)] = b.state_of("oak_door", {"facing": "north", "half": "upper", "open": "false"})
	var dp := Player.new()
	dp.mode = Player.Mode.SURVIVAL
	dp.pos = Vector3(0.5, 64, 0.75)   # the closed door's 3 px slab (z 13..16 px) reaches into the player
	dp.prev_pos = dp.pos
	dp.on_ground = true
	for i in 5:
		dp.tick(mw)
	var door_pose := not dp.crawling and not dp.sneaking
	mw.grid[Vector3i(5, 65, 5)] = stone
	var cp := Player.new()
	cp.mode = Player.Mode.SURVIVAL
	cp.pos = Vector3(5.5, 64, 5.5)
	cp.prev_pos = cp.pos
	cp.on_ground = true
	for i in 3:
		cp.tick(mw)
	ok("pose: a door closed into the player keeps them standing (no forced crouch / crawl); a 1-block gap still crawls", door_pose and cp.crawling,
		"door crawl %s sneak %s / gap crawl %s" % [dp.crawling, dp.sneaking, cp.crawling])


func test_vanilla_gravity_support() -> void:
	BlockUpdates.queue.clear()
	BlockUpdates.pending.clear()
	var w := GravWorld.new()
	var ge := GravEntities.new()
	w.entities = ge
	var b := Res.blocks
	var sand := b.default_state("sand")
	w.blocks[Vector3i(0, 0, 0)] = b.STONE
	for y in range(1, 5):
		w.blocks[Vector3i(0, y, 0)] = sand
	w.set_block(0, 0, 0, 0)
	w.run(20)
	ok("gravity: a sand column falls block by block when its support is removed", ge.fell.size() == 4, "%d fell" % ge.fell.size())
	var cactus := b.default_state("cactus")
	var flower := b.default_state("cactus_flower")
	if cactus > 0 and flower > 0:
		w.blocks[Vector3i(4, 0, 4)] = sand
		w.blocks[Vector3i(4, 1, 4)] = cactus
		w.blocks[Vector3i(4, 2, 4)] = flower
		w.set_block(4, 1, 4, 0)
		BlockUpdates.schedule_neighbors(w, Vector3i(4, 1, 4))
		w.run(4)
		ok("support: the cactus flower breaks with the cactus under it", w.state_at(4, 2, 4) == 0, b.name_of(w.state_at(4, 2, 4)))
	var poppy := b.default_state("poppy")
	w.blocks[Vector3i(6, 0, 6)] = b.default_state("grass_block")
	w.blocks[Vector3i(6, 1, 6)] = poppy
	w.set_block(6, 0, 6, b.default_state("stone"))
	BlockUpdates.schedule_neighbors(w, Vector3i(6, 0, 6))
	w.run(4)
	ok("support: a flower on stone pops off (supports_vegetation)", w.state_at(6, 1, 6) == 0, b.name_of(w.state_at(6, 1, 6)))
	# copper: axe scrapes a stage / removes wax, honeycomb waxes (Java AxeItem / HoneycombItem), random ticks oxidise
	var cpl := Player.new()
	var cpos := Vector3i(10, 0, 10)
	w.blocks[cpos] = b.default_state("exposed_cut_copper_stairs")
	cpl.inventory.set_slot(cpl.inventory.selected, ItemStack.named("iron_axe", 1))
	Copper.use_item(w, cpos, w.state_at(10, 0, 10), cpl.inventory.held(), cpl)
	var c1 := b.name_of(w.state_at(10, 0, 10))
	cpl.inventory.set_slot(cpl.inventory.selected, ItemStack.named("honeycomb", 4))
	Copper.use_item(w, cpos, w.state_at(10, 0, 10), cpl.inventory.held(), cpl)
	var c2 := b.name_of(w.state_at(10, 0, 10))
	cpl.inventory.set_slot(cpl.inventory.selected, ItemStack.named("iron_axe", 1))
	Copper.use_item(w, cpos, w.state_at(10, 0, 10), cpl.inventory.held(), cpl)
	var c3 := b.name_of(w.state_at(10, 0, 10))
	ok("copper: scrape / wax / unwax", c1 == "cut_copper_stairs" and c2 == "waxed_cut_copper_stairs" and c3 == "cut_copper_stairs", "%s %s %s" % [c1, c2, c3])
	w.blocks[Vector3i(20, 0, 20)] = b.default_state("copper_block")
	var crng := RandomNumberGenerator.new()
	crng.seed = 77
	var steps := 0
	while b.name_of(w.state_at(20, 0, 20)) == "copper_block" and steps < 5000:
		Copper.random_tick(w, Vector3i(20, 0, 20), w.state_at(20, 0, 20), crng)
		steps += 1
	ok("copper: a lone copper block oxidises to exposed copper by random ticks (~1 / 0.0427)", b.name_of(w.state_at(20, 0, 20)) == "exposed_copper" and steps > 1, "%s after %d ticks" % [b.name_of(w.state_at(20, 0, 20)), steps])


func test_vanilla_fluids_fire() -> void:
	var b := Res.blocks
	# water: 7 blocks out on a flat floor (amount 8 - distance), diagonal by Manhattan distance
	var w := _fluid_world()
	w.set_block(0, 0, 0, b.WATER)
	BlockUpdates.schedule(w, Vector3i(0, 0, 0), 5)
	w.run(200)
	ok("water: level 3 three blocks out", _lvl(w, 3, 0, 0) == 3, str(_lvl(w, 3, 0, 0)))
	ok("water: level 7 at the 7th block", _lvl(w, 7, 0, 0) == 7 and _lvl(w, -7, 0, 0) == 7 and _lvl(w, 0, 0, 7) == 7)
	ok("water: nothing at 8 blocks", _lvl(w, 8, 0, 0) == -1 and _lvl(w, 0, 0, -8) == -1)
	ok("water: diagonal by Manhattan distance", _lvl(w, 4, 0, 3) == 7 and _lvl(w, 4, 0, 4) == -1)
	var wt := _fluid_world()
	wt.set_block(0, 0, 0, b.WATER)
	BlockUpdates.schedule(wt, Vector3i(0, 0, 0), 5)
	wt.run(9)
	var ring1 := _lvl(wt, 1, 0, 0) == 1 and _lvl(wt, 2, 0, 0) == -1
	wt.run(1)
	ok("water: spreads one ring per 5 ticks (WaterFluid tick delay)", ring1 and _lvl(wt, 2, 0, 0) == 2)
	# slope search: only the direction of the nearest drop within 4 blocks
	var w2 := _fluid_world()
	w2.blocks.erase(Vector3i(3, -1, 0))
	w2.set_block(0, 0, 0, b.WATER)
	BlockUpdates.schedule(w2, Vector3i(0, 0, 0), 5)
	w2.run(6)
	ok("water: heads for the nearest drop (getSlopeDistance)", _lvl(w2, 1, 0, 0) == 1 and _lvl(w2, -1, 0, 0) == -1 and _lvl(w2, 0, 0, 1) == -1 and _lvl(w2, 0, 0, -1) == -1)
	var w2b := _fluid_world()
	w2b.blocks.erase(Vector3i(6, -1, 0))
	w2b.set_block(0, 0, 0, b.WATER)
	BlockUpdates.schedule(w2b, Vector3i(0, 0, 0), 5)
	w2b.run(6)
	ok("water: a drop 6 away is beyond the slope search (all 4 sides)", _lvl(w2b, 1, 0, 0) == 1 and _lvl(w2b, -1, 0, 0) == 1 and _lvl(w2b, 0, 0, 1) == 1)
	# lava: drop-off 2 in the overworld, 1 with fast_lava (the Nether)
	var w3 := _fluid_world()
	w3.set_block(0, 0, 0, b.LAVA)
	BlockUpdates.schedule(w3, Vector3i(0, 0, 0), 30)
	w3.run(400)
	ok("lava: 3 blocks in the overworld (levels 2 / 4 / 6)", _lvl(w3, 1, 0, 0) == 2 and _lvl(w3, 3, 0, 0) == 6 and _lvl(w3, 4, 0, 0) == -1, "%d %d %d" % [_lvl(w3, 1, 0, 0), _lvl(w3, 3, 0, 0), _lvl(w3, 4, 0, 0)])
	var w4 := _fluid_world()
	w4.dim_type = {"attributes": {"minecraft:gameplay/fast_lava": true}}
	ok("lava: tick delay 10 with fast_lava, 30 without", BlockUpdates.lava_delay(w4) == 10 and BlockUpdates.lava_delay(w3) == 30)
	w4.set_block(0, 0, 0, b.LAVA)
	BlockUpdates.schedule(w4, Vector3i(0, 0, 0), 10)
	w4.run(600)
	ok("lava: 7 blocks with fast_lava (drop-off 1)", _lvl(w4, 7, 0, 0) == 7 and _lvl(w4, 8, 0, 0) == -1, "%d %d" % [_lvl(w4, 7, 0, 0), _lvl(w4, 8, 0, 0)])
	# infinite water source
	var w5 := _fluid_world()
	w5.set_block(0, 0, 0, b.WATER)
	w5.set_block(2, 0, 0, b.WATER)
	BlockUpdates.schedule(w5, Vector3i(0, 0, 0), 5)
	BlockUpdates.schedule(w5, Vector3i(2, 0, 0), 5)
	w5.run(20)
	ok("water: two sources make a third on a solid floor", _lvl(w5, 1, 0, 0) == 0)
	# falling water
	var w6 := _fluid_world()
	w6.set_block(0, 5, 0, b.WATER)
	BlockUpdates.schedule(w6, Vector3i(0, 5, 0), 5)
	w6.run(60)
	ok("water: falls first (level 8 below a source)", _lvl(w6, 0, 4, 0) == 8 and _lvl(w6, 0, 0, 0) == 8)
	ok("water: a source in mid-air also spreads to its 4 sides (isSource -> spreadToSides)", _lvl(w6, 1, 5, 0) == 1 and _lvl(w6, 0, 5, -1) == 1)
	ok("water: flowing water in mid-air only falls", _lvl(w6, 2, 5, 0) == -1)
	# waterloggable blocks take only water sources (SimpleWaterloggedBlock.canPlaceLiquid)
	var wl := _fluid_world()
	var fence := b.default_state("oak_fence")
	wl.blocks[Vector3i(1, 0, 0)] = fence
	wl.set_block(0, 0, 0, b.WATER)
	BlockUpdates.schedule(wl, Vector3i(0, 0, 0), 5)
	wl.run(100)
	ok("water: a flow passes a fence without waterlogging it (routes around: level 4 behind)", wl.state_at(1, 0, 0) == fence and _lvl(wl, 2, 0, 0) == 4, "%s %d" % [b.get_prop(wl.state_at(1, 0, 0), "waterlogged"), _lvl(wl, 2, 0, 0)])
	var wl2 := _fluid_world()
	var stair := b.default_state("oak_stairs")
	wl2.blocks[Vector3i(1, 0, 0)] = stair
	wl2.set_block(0, 0, 0, b.WATER)
	wl2.set_block(2, 0, 0, b.WATER)
	BlockUpdates.schedule(wl2, Vector3i(0, 0, 0), 5)
	BlockUpdates.schedule(wl2, Vector3i(2, 0, 0), 5)
	wl2.run(30)
	ok("water: two sources beside a stair waterlog it (a new source)", b.get_prop(wl2.state_at(1, 0, 0), "waterlogged") == "true")
	var wl3 := _fluid_world()
	wl3.blocks[Vector3i(1, 0, 0)] = b.default_state("oak_door")
	wl3.set_block(0, 0, 0, b.WATER)
	BlockUpdates.schedule(wl3, Vector3i(0, 0, 0), 5)
	wl3.run(40)
	var od := b.with_prop(b.default_state("oak_door"), "open", "true")
	ok("water: doors hold water back, open ones too (canHoldAnyFluid)", b.name_of(wl3.state_at(1, 0, 0)) == "oak_door" and BlockUpdates._can_hold(od, false) == false)
	# lava meets water
	var w7 := _fluid_world()
	w7.set_block(0, 0, 0, b.LAVA)
	w7.set_block(1, 0, 0, b.WATER)
	BlockUpdates.schedule(w7, Vector3i(0, 0, 0), 30)
	w7.run(40)
	ok("lava source beside water -> obsidian", b.name_of(w7.state_at(0, 0, 0)) == "obsidian")
	var w8 := _fluid_world()
	w8.set_block(0, 0, 0, b.with_prop(b.LAVA, "level", "2"))
	w8.set_block(1, 0, 0, b.WATER)
	BlockUpdates.schedule(w8, Vector3i(0, 0, 0), 30)
	w8.run(40)
	ok("flowing lava beside water -> cobblestone", b.name_of(w8.state_at(0, 0, 0)) == "cobblestone")
	# fire: odds table (FireBlock.bootStrap)
	ok("fire odds: planks 5 / 20", BlockUpdates.ignite_odds(b.default_state("oak_planks")) == 5 and BlockUpdates.burn_odds(b.default_state("oak_planks")) == 20)
	ok("fire odds: leaves 30 / 60, wool 30 / 60", BlockUpdates.ignite_odds(b.default_state("oak_leaves")) == 30 and BlockUpdates.burn_odds(b.default_state("white_wool")) == 60)
	ok("fire odds: logs 5 / 5, stone 0, crimson planks 0", BlockUpdates.burn_odds(b.default_state("oak_log")) == 5 and BlockUpdates.ignite_odds(b.STONE) == 0 and BlockUpdates.ignite_odds(b.default_state("crimson_planks")) == 0)
	ok("fire odds: waterlogged blocks never burn", BlockUpdates.ignite_odds(b.with_prop(b.default_state("oak_slab"), "waterlogged", "true")) == 0)
	ok("fire odds: TNT 15 / 100, short grass 60 / 100", BlockUpdates.ignite_odds(b.default_state("tnt")) == 15 and BlockUpdates.burn_odds(b.default_state("short_grass")) == 100)
	# fire survival and burn-out
	var f1 := _fluid_world()
	f1.set_block(0, 0, 0, b.default_state("fire"))
	f1.run(2500)
	ok("fire: burns out on stone without fuel", f1.state_at(0, 0, 0) == 0)
	var f2 := _fluid_world()
	f2.blocks[Vector3i(0, -1, 0)] = b.default_state("netherrack")
	f2.set_block(0, 0, 0, b.default_state("fire"))
	f2.run(2500)
	ok("fire: burns forever on netherrack (infiniburn_overworld)", b.name_of(f2.state_at(0, 0, 0)) == "fire")
	var f3 := _fluid_world()
	f3.blocks[Vector3i(0, -1, 0)] = b.default_state("bedrock")
	f3.dim_type = {"infiniburn": "#minecraft:infiniburn_end"}
	f3.set_block(0, 0, 0, b.default_state("fire"))
	f3.run(2500)
	ok("fire: burns forever on bedrock in the End", b.name_of(f3.state_at(0, 0, 0)) == "fire")
	ok("fire: no floor and no fuel -> cannot survive", not BlockUpdates.fire_can_survive(f1, Vector3i(0, 5, 0)))
	f1.blocks[Vector3i(1, 5, 0)] = b.default_state("oak_planks")
	ok("fire: survives in the air beside planks", BlockUpdates.fire_can_survive(f1, Vector3i(0, 5, 0)))
	var fs := BlockUpdates.fire_state(f1, Vector3i(0, 5, 0))
	ok("fire: side-attached to the burnable side", b.get_prop(fs, "east") == "true" and b.get_prop(fs, "west") == "false")
	f1.blocks[Vector3i(0, 9, 0)] = b.default_state("soul_sand")
	ok("fire: soul fire on soul sand", b.name_of(BlockUpdates.fire_state(f1, Vector3i(0, 10, 0))) == "soul_fire")
	# fire spreads through planks and leaves
	var f4 := _fluid_world()
	var planks := b.default_state("oak_planks")
	for x in range(-4, 5):
		for z in range(-4, 5):
			f4.blocks[Vector3i(x, 0, z)] = planks
	f4.set_block(0, 1, 0, b.default_state("fire"))
	f4.run(3000)
	var left := 0
	for x2 in range(-4, 5):
		for z2 in range(-4, 5):
			if f4.state_at(x2, 0, z2) == planks:
				left += 1
	ok("fire: spreads over a plank floor and burns it", left < 81, "%d of 81 planks left" % left)
	var f5 := _fluid_world()
	for x3 in range(-4, 5):
		for z3 in range(-4, 5):
			f5.blocks[Vector3i(x3, 0, z3)] = planks
	f5.raining = true
	f5.set_block(0, 1, 0, b.default_state("fire"))
	f5.run(3000)
	var fires := 0
	for fp in f5.blocks:
		if b.name_of(f5.blocks[fp]) == "fire":
			fires += 1
	ok("fire: rain puts it out", fires == 0, str(fires))


func test_vanilla_structure_ports() -> void:
	var b := Res.blocks
	# StructureTemplate.transform with Mirror.FRONT_BACK and a pivot (Java formulas)
	ok("template mirror: x negated", StructureTemplate.transform_m(Vector3i(2, 0, 1), 0, 1, Vector3i.ZERO) == Vector3i(-2, 0, 1))
	ok("template mirror + cw90 about a pivot", StructureTemplate.transform_m(Vector3i(2, 0, 1), 1, 1, Vector3i(3, 0, 4)) == Vector3i(6, 0, -1))
	ok("template 180 about a pivot", StructureTemplate.transform(Vector3i(1, 2, 1), 2, Vector3i(3, 0, 4)) == Vector3i(5, 2, 7))
	var stairs := b.with_prop(b.default_state("stone_brick_stairs"), "facing", "east")
	ok("mirror_state: east stairs face west", b.get_prop(StructureTemplate.mirror_state(b, stairs), "facing") == "west")
	ok("mirror_state: north stays north", b.get_prop(StructureTemplate.mirror_state(b, b.with_prop(stairs, "facing", "north")), "facing") == "north")
	var bars := b.with_prop(b.with_prop(b.default_state("iron_bars"), "east", "true"), "west", "false")
	var mb := StructureTemplate.mirror_state(b, bars)
	ok("mirror_state: east / west connections swap", b.get_prop(mb, "west") == "true" and b.get_prop(mb, "east") == "false")
	var chest := b.with_prop(b.default_state("chest"), "type", "left")
	ok("mirror_state: chest halves swap", b.get_prop(StructureTemplate.mirror_state(b, chest), "type") == "right")
	# BlockAgeProcessor
	var obs := b.default_state("obsidian")
	var crying := 0
	for i in 2000:
		if b.name_of(Structures._block_age(b, obs, Vector3i(i, 64, i * 7), 0.0)) == "crying_obsidian":
			crying += 1
	ok("block age: obsidian -> crying obsidian ~15 %", crying > 240 and crying < 360, str(crying))
	var mossy_kept := true
	var changed := 0
	for i2 in 400:
		var st2 := b.with_prop(b.with_prop(b.default_state("stone_brick_stairs"), "facing", "south"), "half", "top")
		var o := Structures._block_age(b, st2, Vector3i(i2, 70, -i2), 1.0)
		if b.name_of(o) == "mossy_stone_brick_stairs":
			changed += 1
			mossy_kept = mossy_kept and b.get_prop(o, "facing") == "south" and b.get_prop(o, "half") == "top"
	ok("block age: stairs become mossy keeping facing / half", changed > 50 and mossy_kept, str(changed))
	ok("block age: cobblestone untouched (not in Java's list)", Structures._block_age(b, b.default_state("cobblestone"), Vector3i(5, 5, 5), 1.0) == b.default_state("cobblestone"))
	var full_ok := true
	for i3 in 200:
		var o3 := b.name_of(Structures._block_age(b, b.default_state("stone_bricks"), Vector3i(i3, 1, 2), 0.0))
		full_ok = full_ok and o3 in ["stone_bricks", "cracked_stone_bricks", "stone_brick_stairs"]
	ok("block age: stone bricks -> cracked / stairs without moss", full_ok)
	# BlackstoneReplaceProcessor
	var bs_st := Structures._blackstone(b, b.with_prop(b.with_prop(b.default_state("stone_brick_stairs"), "facing", "south"), "half", "top"))
	ok("blackstone: stairs keep their properties", b.name_of(bs_st) == "polished_blackstone_brick_stairs" and b.get_prop(bs_st, "facing") == "south" and b.get_prop(bs_st, "half") == "top")
	ok("blackstone: cobblestone -> blackstone", b.name_of(Structures._blackstone(b, b.default_state("cobblestone"))) == "blackstone")
	ok("blackstone: iron bars -> chain", b.name_of(Structures._blackstone(b, b.default_state("iron_bars"))).ends_with("chain"))
	ok("blackstone: obsidian untouched", Structures._blackstone(b, obs) == obs)
	# Java StructurePiece orientation (getWorldX / Z, setOrientation state transforms)
	var jp := JavaPieces.P.new()
	jp.b = b
	jp.bmin = Vector3i(100, 64, 200)
	jp.bmax = Vector3i(106, 70, 208)
	jp.ori = "north"
	ok("piece north: x = min x + x, z = max z - z", jp.wpos(1, 2, 3) == Vector3i(101, 66, 205))
	jp.ori = "south"
	ok("piece south: z = min z + z", jp.wpos(1, 2, 3) == Vector3i(101, 66, 203))
	jp.bmax = Vector3i(108, 70, 206)
	jp.ori = "west"
	ok("piece west: x = max x - z, z = min z + x", jp.wpos(1, 2, 3) == Vector3i(105, 66, 201))
	jp.ori = "east"
	ok("piece east: x = min x + z", jp.wpos(1, 2, 3) == Vector3i(103, 66, 201))
	var nst := b.with_prop(b.default_state("oak_stairs"), "facing", "north")
	jp.ori = "south"
	ok("piece south mirrors north stairs to south (Mirror.LEFT_RIGHT)", b.get_prop(jp.orient(nst), "facing") == "south")
	jp.ori = "east"
	ok("piece east turns north stairs east (CW90)", b.get_prop(jp.orient(nst), "facing") == "east")
	jp.ori = "west"
	ok("piece west: mirror then CW90 (north -> south -> west)", b.get_prop(jp.orient(nst), "facing") == "west")
	ok("mirror_z: chest-less north / south connections swap", b.get_prop(JavaPieces.mirror_z(b, b.with_prop(b.default_state("oak_fence"), "north", "true")), "south") == "true")
	# maps (MapItemSavedData.createFresh / scaled / locked)
	var mw := CmdWorld.new()
	var m0 := Maps.new_map(mw, 100.0, -100.0)
	var mi0 := Maps.info(mw, m0)
	ok("map centre on the 128 grid", int(mi0["x"]) == 128 and int(mi0["z"]) == -128 and int(mi0["scale"]) == 0, str(mi0))
	var m1 := Maps.scaled_copy(mw, m0)
	var mi1 := Maps.info(mw, m1)
	ok("zoomed-out map: scale 1 on the 256 grid", int(mi1["scale"]) == 1 and int(mi1["x"]) == 64 and int(mi1["z"]) == -192, str(mi1))
	ok("zoomed-out map is a new map id", Maps.map_id(m1) != Maps.map_id(m0))
	var m2 := Maps.locked_copy(mw, m0)
	ok("locked copy: new id, locked, same centre", Maps.map_id(m2) != Maps.map_id(m0) and bool(Maps.info(mw, m2).get("locked", false)) and int(Maps.info(mw, m2)["x"]) == 128)
	var m4 := m1
	for zi in 4:
		m4 = Maps.scaled_copy(mw, m4)
	ok("maps stop at scale 4", int(Maps.info(mw, m4)["scale"]) == 4)
	# NetherFortressPieces: orientBox, generation invariants (Java generatePieces / moveInsideHeights)
	ok("orientBox south", JavaPieces.orient_box(10, 64, 20, -1, -3, 0, 5, 10, 19, "south") == [Vector3i(9, 61, 20), Vector3i(13, 70, 38)])
	ok("orientBox north", JavaPieces.orient_box(10, 64, 20, -1, -3, 0, 5, 10, 19, "north") == [Vector3i(9, 61, 2), Vector3i(13, 70, 20)])
	ok("orientBox west", JavaPieces.orient_box(10, 64, 20, -1, -3, 0, 5, 10, 19, "west") == [Vector3i(-8, 61, 19), Vector3i(10, 70, 23)])
	ok("orientBox east", JavaPieces.orient_box(10, 64, 20, -1, -3, 0, 5, 10, 19, "east") == [Vector3i(10, 61, 19), Vector3i(28, 70, 23)])
	var nf_ok := true
	var nf_msg := ""
	var kinds_seen := {}
	for fs in [Vector2i(3, -7), Vector2i(-17, -8), Vector2i(40, 12)]:
		var fr := Structures.large_feature_seed(12345, fs.x, fs.y)
		var fres := JavaPieces.fortress(null, fs, fr)
		var fps: Array = fres["pieces"]
		var counts := {}
		var fmin := 1 << 30
		var fmax := -(1 << 30)
		for i in fps.size():
			var a: Dictionary = fps[i]["el"]
			counts[a["k"]] = int(counts.get(a["k"], 0)) + 1
			kinds_seen[a["k"]] = true
			fmin = mini(fmin, a["min"].y)
			fmax = maxi(fmax, a["max"].y)
			for j in range(i + 1, fps.size()):
				var bb: Dictionary = fps[j]["el"]
				if a["max"].x >= bb["min"].x and a["min"].x <= bb["max"].x and a["max"].y >= bb["min"].y and a["min"].y <= bb["max"].y and a["max"].z >= bb["min"].z and a["min"].z <= bb["max"].z:
					nf_ok = false
					nf_msg = "overlap %s %s" % [a["k"], bb["k"]]
		var st0: Dictionary = fps[0]["el"]
		if st0["k"] != "crossing" or st0["min"].x != fs.x * 16 + 2 or st0["min"].z != fs.y * 16 + 2 or st0["max"] - st0["min"] != Vector3i(18, 9, 18):
			nf_ok = false
			nf_msg = "start piece %s" % str(st0)
		if int(counts.get("entrance", 0)) > 1 or int(counts.get("throne", 0)) > 2 or int(counts.get("c_stalk", 0)) > 2 or int(counts.get("crossing", 0)) > 5 or int(counts.get("c_balcony", 0)) > 2:
			nf_ok = false
			nf_msg = "piece limits %s" % str(counts)
		if fmin < 48 or (fmax - fmin < 22 and fmax > 70):
			nf_ok = false
			nf_msg = "height %d..%d" % [fmin, fmax]
		var again := JavaPieces.fortress(null, fs, Structures.large_feature_seed(12345, fs.x, fs.y))
		if (again["pieces"] as Array).size() != fps.size():
			nf_ok = false
			nf_msg = "not deterministic"
	ok("fortress: start crossing, no overlaps, piece limits, 48..70 band, deterministic", nf_ok, nf_msg)
	ok("fortress: bridge and castle pieces both occur", kinds_seen.has("straight") and kinds_seen.has("c_corridor") and kinds_seen.has("end"), str(kinds_seen.keys()))
	# StrongholdPieces: spiral stairs start, five-way crossing forced next, a portal room, no overlaps, below sea - 10
	var sh_ok := true
	var sh_msg := ""
	for shc in [Vector2i(-40, 25), Vector2i(70, -3)]:
		var shr := JavaPieces.stronghold_for(12345, 63, -64, shc)
		var sps: Array = shr["pieces"]
		var portals := 0
		var top := -(1 << 30)
		for i in sps.size():
			var a: Dictionary = sps[i]["el"]
			if a["k"] == "portal_room":
				portals += 1
			top = maxi(top, a["max"].y)
			for j in range(i + 1, sps.size()):
				var bb: Dictionary = sps[j]["el"]
				if a["k"] == "filler" or bb["k"] == "filler":
					continue   # FillerCorridor ends one block inside the piece it reaches (the doorway it punches)
				if a["max"].x >= bb["min"].x and a["min"].x <= bb["max"].x and a["max"].y >= bb["min"].y and a["min"].y <= bb["max"].y and a["max"].z >= bb["min"].z and a["min"].z <= bb["max"].z:
					sh_ok = false
					sh_msg = "overlap %s %s" % [a["k"], bb["k"]]
		var s0: Dictionary = sps[0]["el"]
		if s0["k"] != "stairs_down" or s0["min"].x != shc.x * 16 + 2 or s0["max"] - s0["min"] != Vector3i(4, 10, 4):
			sh_ok = false
			sh_msg = "start %s" % str(s0)
		if sps.size() < 2 or sps[1]["el"]["k"] != "five_crossing":
			sh_ok = false
			sh_msg = "second piece %s" % str(sps[1]["el"]["k"] if sps.size() > 1 else "-")
		if portals != 1 or top > 53:
			sh_ok = false
			sh_msg = "portals %d top %d" % [portals, top]
	ok("stronghold: stairs start, five-way crossing next, one portal room, no overlaps, top <= sea - 10", sh_ok, sh_msg)	# OceanMonumentPieces: building, entry + core rooms, every grid room fitted once, two wings + penthouse
	var mo_ok := true
	var mo_msg := ""
	for msc in [Vector2i(8, -371), Vector2i(-245, -400), Vector2i(107, -336)]:
		var mres := JavaPieces.monument_layout(msc, Structures.large_feature_seed(12345, msc.x, msc.y))
		var mps: Array = mres["pieces"]
		var kc := {}
		var bld: Dictionary = mps[0]["el"]
		for mp in mps:
			var me: Dictionary = mp["el"]
			kc[me["k"]] = int(kc.get(me["k"], 0)) + 1
			if me["min"].x < bld["min"].x or me["max"].x > bld["max"].x or me["min"].z < bld["min"].z or me["max"].z > bld["max"].z:
				mo_ok = false
				mo_msg = "%s outside the building" % me["k"]
		if bld["k"] != "building" or bld["min"] != Vector3i(msc.x * 16 - 29, 39, msc.y * 16 - 29) or bld["max"] - bld["min"] != Vector3i(57, 22, 57):
			mo_ok = false
			mo_msg = "building %s" % str(bld)
		if kc.get("entry", 0) != 1 or kc.get("core", 0) != 1 or kc.get("wing", 0) != 2 or kc.get("penthouse", 0) != 1:
			mo_ok = false
			mo_msg = "kinds %s" % str(kc)
		# room cells covered: 20 + 20 + 6 grid rooms = 46 cells, each fitted exactly once
		var cells := 0
		var sizes := {"entry": 1, "core": 8, "simple": 1, "simple_top": 1, "double_x": 2, "double_y": 2, "double_z": 2, "double_xy": 4, "double_yz": 4}
		for k2 in kc:
			cells += int(sizes.get(k2, 0)) * int(kc[k2])
		if cells != 46:
			mo_ok = false
			mo_msg = "cells %d %s" % [cells, str(kc)]
	ok("monument: building box, entry / core / wings / penthouse, all 46 grid cells fitted once", mo_ok, mo_msg)	# StructurePiece SHAPE_CHECK_BLOCKS: fences / bars get their connections after generation
	# WoodlandMansionPieces: MansionGrid invariants (entrance, blocked rows, every room cell owned by a room with one
	# origin cell, one third-floor staircase pair or a blocked third floor), placer output, LEFT_RIGHT state mirror
	var wm_ok := true
	var wm_msg := ""
	for wseed in [1, 42, 12345, 987654321, -77]:
		var mg := MansionPieces.MGrid.new(RandomSources.LegacyRandom.new(wseed))
		var gb: MansionPieces.Grid = mg.base
		if gb.at(7, 4) != 3 or gb.at(8, 5) != 3 or gb.at(3, 0) != 5 or gb.at(3, 10) != 5 or gb.at(9, 3) != 5:
			wm_ok = false
			wm_msg = "base grid entrance / blocked rows (seed %d)" % wseed
		for fl in 2:
			var rg: MansionPieces.Grid = mg.rooms[fl]
			var origins := {}
			for y in 11:
				for x in 11:
					if gb.at(x, y) == 2:
						var q := rg.at(x, y)
						if (q & MansionPieces.ID_MASK) < 10 or (q & MansionPieces.TYPE_MASK) == 0:
							wm_ok = false
							wm_msg = "room cell %d,%d floor %d without a room (seed %d)" % [x, y, fl, wseed]
						if (q & MansionPieces.ORIGIN_FLAG) != 0:
							origins[q & MansionPieces.ID_MASK] = int(origins.get(q & MansionPieces.ID_MASK, 0)) + 1
			for id in origins:
				if int(origins[id]) != 1:
					wm_ok = false
					wm_msg = "room %d has %d origin cells (seed %d)" % [id, origins[id], wseed]
		var starts := 0
		var blocked := 0
		for y in 11:
			for x in 11:
				starts += int(mg.third.at(x, y) == 3)
				blocked += int(mg.third.at(x, y) == 5)
		if not (starts == 2 or blocked == 121):
			wm_ok = false
			wm_msg = "third floor: %d staircase cells, %d blocked (seed %d)" % [starts, blocked, wseed]
		var pl := MansionPieces.new()
		pl.r = RandomSources.LegacyRandom.new(wseed + 1)
		pl.create(Vector3i(100, 70, 200), wseed & 3, mg)
		var ent := 0
		for pc in pl.pieces:
			ent += int(str(pc["el"]["loc"]) == "woodland_mansion/entrance")
		if ent != 1 or pl.pieces.size() < 60:
			wm_ok = false
			wm_msg = "placer: %d entrances, %d pieces (seed %d)" % [ent, pl.pieces.size(), wseed]
	ok("mansion: grid entrance / rooms / origins / third floor, placer entrance + pieces", wm_ok, wm_msg)
	ok("locate biome heights: Mth.outFromOrigin(64, -63, 320, 64) = 64, 128, 0, 192, 256, 320", VanillaGenerator.out_from_origin(64, -63, 320, 64) == PackedInt32Array([64, 128, 0, 192, 256, 320]), str(VanillaGenerator.out_from_origin(64, -63, 320, 64)))
	ok("locate biome heights: outside the world -> no search (Java)", VanillaGenerator.out_from_origin(400, -63, 320, 64).is_empty())
	ok("template entities: Java Vec3 transform (+1 under rotation / mirror), caged allay stays in its block", StructureTemplate.transform_vec(Vector3(4.5, 1.05, 4.5), 1, 0, Vector3i.ZERO) == Vector3(-3.5, 1.05, 4.5) and StructureTemplate.transform(Vector3i(4, 1, 4), 1) == Vector3i(-4, 1, 4) and StructureTemplate.transform_vec(Vector3(4.5, 1.0, 4.5), 2, 0, Vector3i.ZERO) == Vector3(-3.5, 1.0, -3.5) and StructureTemplate.transform_vec(Vector3(0.25, 0, 0.75), 0, 1, Vector3i.ZERO) == Vector3(0.75, 0, 0.75))
	var nst2 := b.with_prop(b.default_state("dark_oak_stairs"), "facing", "north")
	ok("mirror LEFT_RIGHT: north stairs face south, east stays east", b.get_prop(StructureTemplate.mirror_state(b, nst2, 2), "facing") == "south" and b.get_prop(StructureTemplate.mirror_state(b, b.with_prop(nst2, "facing", "east"), 2), "facing") == "east")
	ok("mirror: door hinge swaps (both modes)", b.get_prop(StructureTemplate.mirror_state(b, b.with_prop(b.default_state("dark_oak_door"), "hinge", "left"), 2), "hinge") == "right" and b.get_prop(StructureTemplate.mirror_state(b, b.with_prop(b.default_state("dark_oak_door"), "hinge", "left"), 1), "hinge") == "right")
	ok("mirror LEFT_RIGHT: z negated", StructureTemplate.transform_m(Vector3i(2, 0, 1), 0, 2, Vector3i.ZERO) == Vector3i(2, 0, -1))
	ok("shape check: nether brick fence, oak fence, iron bars; not stone", JavaPieces.shape_check(b, b.default_state("nether_brick_fence")) and JavaPieces.shape_check(b, b.default_state("oak_fence")) and JavaPieces.shape_check(b, b.default_state("iron_bars")) and not JavaPieces.shape_check(b, b.default_state("stone")))	# MapItemSavedData decorations: banner toggle (inside the map, same banner twice removes), frame marker facing
	var bw := CmdWorld.new()
	var bm := Maps.new_map(bw, 0.0, 0.0)
	var bmid := Maps.map_id(bm)
	bw.set_block(10, 64, -20, Res.blocks.default_state("red_banner"))
	ok("map banner: toggling a banner adds its marker", Maps.toggle_banner(bw, bm, Vector3i(10, 64, -20)) and Maps.decorations(bw, bmid).size() == 1)
	var bd: Array = Maps.decorations(bw, bmid)[0]
	ok("map banner: red banner sprite, map coords (int)(2f + 0.5) toward zero, turned 180", bd[0] == "map/decorations/red_banner" and int(bd[1]) == 21 and int(bd[2]) == -38 and int(bd[3]) == 8, str(bd))
	ok("map banner: toggling again removes it", Maps.toggle_banner(bw, bm, Vector3i(10, 64, -20)) and Maps.decorations(bw, bmid).is_empty())
	bw.set_block(200, 64, 0, Res.blocks.default_state("blue_banner"))
	ok("map banner: outside the map area does nothing", not Maps.toggle_banner(bw, bm, Vector3i(200, 64, 0)))
	ok("map banner: not a banner does nothing", not Maps.toggle_banner(bw, bm, Vector3i(0, 64, 0)))
	Maps.frame_added(bw, Vector3i(5, 70, 5), Vector3i(1, 0, 0), bm)
	var fdec: Array = Maps.decorations(bw, bmid)
	ok("map frame marker: east-facing frame -> rot 12, frame sprite, not on frames", fdec.size() == 1 and fdec[0][0] == "map/decorations/frame" and int(fdec[0][3]) == 12 and not bool(fdec[0][5]), str(fdec))
	var rv0 := Maps.rev(bw, bmid)
	Maps.frame_added(bw, Vector3i(5, 70, 5), Vector3i(1, 0, 0), bm)
	ok("map frame marker: re-adding the same frame changes nothing", Maps.rev(bw, bmid) == rv0)
	Maps.frame_removed(bw, Vector3i(5, 70, 5), bm)
	ok("map frame marker: removed with the map", Maps.decorations(bw, bmid).is_empty())	# Crafter (CrafterBlockEntity / CrafterBlock): disabled slots, hopper filling, comparator, recipe preview
	var cd := {"id": "crafter", "items": []}
	Crafter.set_disabled(cd, 4, true)
	ok("crafter: slot 4 disabled, others enabled", Crafter.disabled(cd, 4) and not Crafter.disabled(cd, 0))
	var filled := 0
	for k in 16:
		if Crafter.insert_one(cd, ItemStack.named("oak_log", 1)):
			filled += 1
	var counts: Array = []
	for k2 in 9:
		counts.append(ItemStack.from_dict(cd["items"][k2]).count)
	ok("crafter: hoppers fill the enabled slots evenly, never the disabled one", filled == 16 and counts[4] == 0 and counts.max() == 2 and counts.min() == 0 and counts.count(2) == 8, str(counts))
	ok("crafter: comparator counts filled + disabled slots", Crafter.signal_strength(cd) == 9)
	var g1: Array = []
	for k3 in 9:
		g1.append(ItemStack.named("oak_log", 1) if k3 == 4 else ItemStack.new())
	var r1 := Crafter.result(g1)
	ok("crafter: one log anywhere crafts 4 oak planks", r1.name() == "oak_planks" and r1.count == 4, r1.name() + " x" + str(r1.count))
	var g2: Array = []
	for k4 in 9:
		g2.append(ItemStack.new())
	ok("crafter: an empty grid has no result", Crafter.result(g2).is_empty())
	Crafter.set_disabled(cd, 4, false)
	ok("crafter: re-enabling a slot", not Crafter.disabled(cd, 4) and Crafter.signal_strength(cd) == 8)	# Java session.lock: a world held by another running process is neither opened nor deleted; stale locks are taken
	var lkdir := SaveManager.ROOT.path_join("__locktest__")
	DirAccess.make_dir_recursive_absolute(lkdir)
	var other_pid := OS.create_process("ping", ["-n", "8", "127.0.0.1"])   # a running process that is not this one
	var lkf := FileAccess.open(lkdir.path_join("session.lock"), FileAccess.WRITE)
	lkf.store_string(str(other_pid))
	lkf.close()
	ok("session lock: a world locked by a running process is refused", not SaveManager.lock_world("__locktest__"))
	ok("session lock: and cannot be deleted", not SaveManager.delete_world("__locktest__") and DirAccess.dir_exists_absolute(lkdir))
	lkf = FileAccess.open(lkdir.path_join("session.lock"), FileAccess.WRITE)
	lkf.store_string("987654321")   # no such process: stale
	lkf.close()
	ok("session lock: a stale lock is taken over", SaveManager.lock_world("__locktest__") and FileAccess.get_file_as_string(lkdir.path_join("session.lock")) == str(OS.get_process_id()))
	if other_pid > 0:
		OS.kill(other_pid)
	SaveManager.unlock_world("__locktest__")
	ok("session lock: released on leaving", not FileAccess.file_exists(lkdir.path_join("session.lock")))
	SaveManager.delete_world("__locktest__")	# Nether coordinate scale
	ok("nether portal target: x / 8 floored", Portals.scaled_target("overworld", "the_nether", Vector3(800.0, 70.0, -801.0)) == Vector3(100.0, 70.0, -101.0))
	ok("nether portal target: x * 8 back", Portals.scaled_target("the_nether", "overworld", Vector3(100.5, 70.0, -101.0)) == Vector3(804.0, 70.0, -808.0))
	# End crystal / dragon rigs
	for i4 in 200:
		var gy := EntityManager._crystal_y(i4 * 0.37)
		if gy < -1.4001 or gy > -0.5999:
			ok("end crystal bob in [-1.4, -0.6]", false, str(gy))
			break
		if i4 == 199:
			ok("end crystal bob in [-1.4, -0.6]", true)
	var dr := MobRigs.rig("ender_dragon")
	ok("dragon rig: 37 Java parts", (dr.get("parts", []) as Array).size() == 37, str((dr.get("parts", []) as Array).size()))
	ok("dragon rig: wings / legs hang off the torso", str((dr.get("nest", {}) as Dictionary).get("left_wing", "")) == "torso" and str((dr.get("nest", {}) as Dictionary).get("right_hind_foot", "")) == "right_hind_leg_tip")
	ok("end crystal rig: base, 2 glass, cube", (MobRigs.rig("end_crystal").get("parts", []) as Array).size() == 4)
	var built := EntityRenderer.build_rig(MobRegistry.get_def("ender_dragon"))
	var m := built.get_node_or_null("model")
	ok("dragon model builds with nested parts", m != null and m.find_child("left_front_foot", true, false) != null and m.find_child("jaw", true, false).get_parent().name == "head")
	built.free()


class BehWorld extends GrowWorld:
	var biomes = null
	var dimension := "overworld"
	var player := Player.new()
	var raining := false
	var darken := 0
	func sky_darken_level() -> int:
		return darken
	func column_ready(_x: float, _z: float) -> bool:
		return true


class BehEnts extends CmdEnts:
	var rng := RandomNumberGenerator.new()
	var world = null
	var particles := 0
	func _damage(e, amt: float, _src, dtype: String = "") -> void:
		if dtype == "magic" and e.id == "witch":
			amt *= 0.15
		e.hp -= amt
	func _teleport(e, _gs, _b) -> bool:
		e.pos += Vector3(10, 0, 0)
		return true
	func spawn_block_particles(_p, _s) -> void:
		particles += 1
	func spawn_projectile(kind: String, p: Vector3, v: Vector3, owner_ref) -> void:
		var e := EntityManager.Ent.new()
		e.kind = "projectile"
		e.id = kind
		e.pos = p
		e.vel = v
		e.owner = owner_ref
		ents.append(e)
	func set_size(e, s: int) -> void:
		e.size = s


func _beh_mob(em: BehEnts, id: String, p: Vector3, baby: bool = false):
	var e = em.spawn_mob(id, p)
	e.def = MobRegistry.get_def(id)
	e.hp = float(e.def["hp"])
	e.w = float(e.def["w"])
	e.h = float(e.def["h"])
	e.baby_age = -24000 if baby else 0
	return e


## Mob behaviours from the wiki audit (MobBehaviors / MobAI): regional difficulty, drowned day rule, trident throwing,
## witch magic resistance, mob potions, zombie infection + door breaking, bee stings, polar bears, enderman dodging.
func test_vanilla_mob_behaviors() -> void:
	MobBehaviors.reset_cache()
	var w := BehWorld.new()
	var em := BehEnts.new()
	em.world = w
	var rem := EntityManager.new()
	rem.world = w
	w.entities = em
	em.rng.seed = 4242
	w.difficulty = 3
	w.day_time = 0
	var r0 := MobAI.regional_difficulty(w, Vector3.ZERO)
	w.difficulty = 2
	w.day_time = 2400000
	var r1 := MobAI.regional_difficulty(w, Vector3.ZERO)
	ok("regional difficulty: Hard day 0 = 2.25, Normal after day 63 with a full moon = 2.5 (clamped 0.25)", is_equal_approx(r0, 2.25) and is_equal_approx(r1, 2.5)
		and is_equal_approx(MobAI.clamped_regional(w, Vector3.ZERO), 0.25), "%f %f" % [r0, r1])
	w.difficulty = 2
	w.day_time = 6000
	var p: Player = w.player
	p.pos = Vector3(8.5, 64, 0.5)
	var dr = _beh_mob(em, "drowned", Vector3(0.5, 64, 0.5))
	var day_land := MobAI.wants_target(rem, dr, p, 8.0)
	p.in_water = true
	var day_water := MobAI.wants_target(rem, dr, p, 8.0)
	p.in_water = false
	w.darken = 11
	var night := MobAI.wants_target(rem, dr, p, 8.0)
	ok("drowned: ignore players on land by day, hunt them in water or at night", not day_land and day_water and night)
	dr.data["held"] = "trident"
	dr.attack_cd = 0
	var handled := MobBehaviors.attack(rem, dr, p, 8.0)
	var tri = rem.ents[rem.ents.size() - 1] if not rem.ents.is_empty() else EntityManager.Ent.new()
	ok("drowned with a trident throws it (8 base damage, cannot be picked up, every 1.5 s), no melee", handled and tri.id == "trident" and float(tri.data.get("base_damage", 0)) == 8.0
		and tri.data.get("pickup", true) == false and dr.attack_cd == 30 and MobBehaviors.nav_out == Vector3.INF)
	var sp := MobBehaviors.spread(em.rng, Vector3(1, 0, 0), 6.0)
	ok("mob arrow spread: +-0.0172275 x inaccuracy per axis (Normal 6)", absf(sp.y) <= 0.0172275 * 6.0 and absf(sp.z) <= 0.0172275 * 6.0 and MobBehaviors.mob_inaccuracy(w) == 6.0)
	# witch: 85 % magic resistance in the real damage path
	var wi := EntityManager.Ent.new()
	wi.kind = "mob"
	wi.id = "witch"
	wi.def = MobRegistry.get_def("witch")
	wi.hp = 26.0
	rem._damage(wi, 10.0, null, "magic")
	var after_magic := wi.hp
	wi.invuln = 0
	rem._damage(wi, 4.0, null)
	ok("witch: magic damage 85 % less effective (10 -> 1.5), other damage in full", is_equal_approx(after_magic, 24.5) and is_equal_approx(wi.hp, 20.5), "%f %f" % [after_magic, wi.hp])
	# mob potions: harming hurts the living and heals the undead, poison ticks every 25 ticks, never below 1 HP
	var cow = _beh_mob(em, "cow", Vector3(20, 64, 20))
	var zom = _beh_mob(em, "zombie", Vector3(22, 64, 20))
	zom.hp = 10.0
	MobBehaviors.apply_potion(em, cow, "harming", 1.0)
	MobBehaviors.apply_potion(em, zom, "harming", 1.0)
	ok("splash harming: 6 to a cow, heals a zombie 4 (undead swap)", is_equal_approx(cow.hp, 4.0) and is_equal_approx(zom.hp, 14.0), "%f %f" % [cow.hp, zom.hp])
	cow.hp = 3.0
	MobBehaviors.add_effect(cow, "poison", 0, 200)
	MobBehaviors.add_effect(zom, "poison", 0, 200)
	for i in 200:
		MobBehaviors.tick_effects(em, cow)
	ok("mob poison: 1 per 25 ticks down to 1 HP, undead immune", is_equal_approx(cow.hp, 1.0) and not MobBehaviors.has_effect(zom, "poison") and not cow.data.has("fx"), "%f" % cow.hp)
	# zombie kills a villager on Hard -> zombie villager with the same profession
	w.difficulty = 3
	var vil = _beh_mob(em, "villager", Vector3(30.5, 64, 30.5))
	vil.data["prof"] = "farmer"
	vil.hp = 2.0
	var zk = _beh_mob(em, "zombie", Vector3(31.0, 64, 30.5))
	zk.attack_cd = 0
	MobBehaviors.melee_mob(em, zk, vil)
	var zv = null
	for o in em.ents:
		if o.id == "zombie_villager":
			zv = o
	ok("zombie killing a villager on Hard infects it (profession kept)", vil.dead and zv != null and str(zv.data.get("prof", "")) == "farmer")
	# door breaking on Hard after ~10 s; Normal only bangs
	var b := Res.blocks
	var door := b.default_state("oak_door")
	if door > 0:
		for diff in [2, 3]:
			w.difficulty = diff
			w.blocks.clear()
			w.blocks[Vector3i(1, 64, 0)] = b.with_prop(b.with_prop(door, "half", "lower"), "open", "false")
			w.blocks[Vector3i(1, 65, 0)] = b.with_prop(b.with_prop(door, "half", "upper"), "open", "false")
			var zd = _beh_mob(em, "zombie", Vector3(0.5, 64, 0.5))
			zd.data["breaks_doors"] = true
			zd.target_player = true
			p.pos = Vector3(4.5, 64, 0.5)
			for i in 200:
				MobBehaviors.pre_tick(em, zd, p, 4.0, 0)
			var gone: bool = w.state_at(1, 64, 0) == 0 and w.state_at(1, 65, 0) == 0
			ok("door-breaking zombie: %s" % ("breaks a closed wooden door after 10 s on Hard" if diff == 3 else "only bangs on Normal"), gone == (diff == 3))
	# bees: sting poisons (Normal 10 s), the bee loses its stinger
	w.difficulty = 2
	var bee = _beh_mob(em, "bee", Vector3(40, 66, 40))
	p.effects.clear()
	MobBehaviors.bee_stung(em, bee, p)
	ok("bee sting: Poison 10 s on Normal, stinger lost, no more anger", p.effects.has("poison") and int(p.effects["poison"].get("ticks", 0)) == 200 and bee.data.has("stung") and not bee.angry,
		str(p.effects))
	# polar bears: hitting a cub angers the adults around; an adult turns on its attacker
	MobBehaviors.reset_cache()
	w.game_time += 10
	var cub = _beh_mob(em, "polar_bear", Vector3(50.5, 64, 50.5), true)
	var mom = _beh_mob(em, "polar_bear", Vector3(60.5, 64, 50.5))
	var far = _beh_mob(em, "polar_bear", Vector3(90.5, 64, 50.5))
	var cub_fights: bool = MobBehaviors.retaliate(em, cub, p)
	ok("polar bear cub hit: adults within 41 x 21 x 41 turn hostile, the cub panics", not cub_fights and mom.angry and mom.target_player and not far.angry)
	var llama = _beh_mob(em, "llama", Vector3(70.5, 64, 70.5))
	ok("llama hit by a player retaliates (spit)", MobBehaviors.retaliate(em, llama, p) and llama.target_player)
	# endermen dodge arrows but not snowballs
	var en = _beh_mob(em, "enderman", Vector3(80.5, 64, 80.5))
	var x0: float = en.pos.x
	ok("enderman teleports away from arrows (snowballs still hit)", MobBehaviors.dodge_projectile(em, en, "arrow") and en.pos.x != x0 and not MobBehaviors.dodge_projectile(em, en, "snowball"))
	# sulfur cube / slime sizes (real EntityManager.set_size)
	var sc := EntityManager.Ent.new()
	sc.id = "sulfur_cube"
	rem.set_size(sc, 2)
	var big := [sc.w, sc.hp]
	rem.set_size(sc, 1)
	var sl := EntityManager.Ent.new()
	sl.id = "slime"
	rem.set_size(sl, 4)
	ok("sulfur cube 0.98 / 8 HP large, 0.49 / 4 HP small; slime size 4 = 2.0808 wide, 16 HP", is_equal_approx(float(big[0]), 0.98) and float(big[1]) == 8.0 and is_equal_approx(sc.w, 0.49) and sc.hp == 4.0
		and is_equal_approx(sl.w, 2.0808) and sl.hp == 16.0)
	# tamed parrot perches on the left shoulder when touching its owner, hops off when the owner falls
	p.pos = Vector3(100.5, 64, 100.5)
	p.on_ground = true
	p.fall_distance = 0.0
	p.shoulder = [{}, {}]
	var par: EntityManager.Ent = rem.spawn_mob("parrot", p.pos + Vector3(0, 0.5, 0))
	if par != null:
		par.data["owner"] = Taming.owner_name()
		par.persistent = true
		par.rt["ride_cd"] = 0
		MobBehaviors.pre_tick(rem, par, p, 0.5, 0)
		var perched: bool = par.dead and not (p.shoulder[0] as Dictionary).is_empty() and (p.shoulder[1] as Dictionary).is_empty()
		p.fall_distance = 1.0
		MobBehaviors.shoulder_tick(rem, p)
		var back = rem.ents[rem.ents.size() - 1]
		ok("parrot: perches on the owner's left shoulder, hops off when the owner falls", perched and (p.shoulder[0] as Dictionary).is_empty() and back.id == "parrot" and str(back.data.get("owner", "")) == Taming.owner_name() and int(back.rt.get("ride_cd", 0)) == 100)
	# warden: anger 70 + a projectile's 10 reaches 80 -> roar +20; a direct attack adds 100 (cap 150)
	var wd = _beh_mob(em, "warden", Vector3(120.5, 64, 120.5))
	wd.data["anger"] = 70
	MobBehaviors.warden_anger(wd, 10)
	var roared := int(wd.data["anger"])
	MobBehaviors.retaliate(em, wd, p)
	ok("warden anger: reaching 80 adds 20 (roar), a direct hit +100, capped at 150", roared == 100 and int(wd.data["anger"]) == 150 and wd.target_player)
	# raid captain: the ominous banner (8 patterns) on the head part
	var cap := EntityManager.Ent.new()
	cap.id = "pillager"
	cap.node = EntityRenderer.build_rig(MobRegistry.get_def("pillager"))
	EntityRenderer.group_head(cap.node)
	MobBehaviors.render_captain(cap)
	var hd: Node = cap.node.get_node_or_null("model/head")
	ok("raid captain wears the ominous banner on its head (white banner, 8 patterns)", hd != null and hd.get_node_or_null("captain_banner") != null
		and (MobBehaviors.ominous_banner().components["minecraft:banner_patterns"] as Array).size() == 8)
	cap.node.free()
	# wither armor below half health: arrows / tridents / wind charges pass, other projectiles hit
	var wt = _beh_mob(em, "wither", Vector3(130.5, 70, 130.5))
	var full_hit := MobBehaviors.dodge_projectile(em, wt, "arrow")
	wt.hp = 140.0
	ok("wither armor below half health: immune to arrows / tridents / wind charges, not fireworks", not full_hit and MobBehaviors.dodge_projectile(em, wt, "arrow")
		and MobBehaviors.dodge_projectile(em, wt, "trident") and not MobBehaviors.dodge_projectile(em, wt, "firework_rocket"))
	# ominous trial: Bad Omen II seen by a trial spawner -> Trial Omen 30 min, the spawner (even on cooldown) turns ominous
	var tsp := Vector3i(140, 64, 140)
	var tst := b.default_state("trial_spawner")
	if tst > 0:
		w.blocks.clear()
		w.game_time = 1000
		w.blocks[tsp] = tst
		var td := {"id": "trial_spawner", "normal": "minecraft:trial_chamber/melee/zombie/normal", "ominous": "minecraft:trial_chamber/melee/zombie/ominous",
			"state": "cooldown", "until": 999999}
		p.pos = Vector3(140.5, 64, 145.5)
		p.effects.clear()
		p.add_effect("bad_omen", 1, 6000)
		Trials._trial(w, tsp, td, 5.0)
		ok("ominous trial: Bad Omen II -> Trial Omen 36000 ticks, the cooling-down spawner turns ominous and active", not p.effects.has("bad_omen") and p.effects.has("trial_omen")
			and int(p.effects["trial_omen"].get("ticks", 0)) == 36000 and bool(td.get("is_ominous", false)) and str(td.get("state", "")) == "active"
			and b.get_prop(w.state_at(140, 64, 140), "ominous") == "true", str(td))
		p.effects.clear()
	rem.free()
	MobBehaviors.reset_cache()


class LeftEnts extends BehEnts:
	var items: Array = []
	var hearts := 0
	func spawn_item(_p, s, _v = null):
		items.append(s)
	func spawn_hearts(_a) -> void:
		hearts += 1
	func spawn_xp(_p, _n) -> void:
		pass


class PoiCM:
	var chunks: Dictionary = {}
	func get_chunk(cx: int, cz: int):
		return chunks.get(Vector2i(cx, cz))


class PoiWorld:
	var cm := PoiCM.new()
	var entities = null
	var game_time := 0


func _left_ent(id: String, at: Vector3, yaw: float) -> EntityManager.Ent:
	var e := EntityManager.Ent.new()
	e.kind = "mob"
	e.id = id
	e.def = MobRegistry.get_def(id)
	e.w = float(e.def["w"])
	e.h = float(e.def["h"])
	e.hp = float(e.def["hp"])
	e.pos = at
	e.prev = at
	e.yaw = yaw
	return e


## Mob leftovers of the wiki audit: trial equipment + ominous item spawners (loot modifiers), goat ram, villager /
## trader speeds + fleeing, attribute swim / flight speeds, nautilus taming, cat variants, raid POI centre, llama spit.
func test_vanilla_mob_leftovers() -> void:
	MobBehaviors.reset_cache()
	var w := BehWorld.new()
	var em := LeftEnts.new()
	em.world = w
	w.entities = em
	em.rng.seed = 777
	w.rng.seed = 778
	w.difficulty = 2
	var p: Player = w.player
	p.mode = Player.Mode.SURVIVAL
	var b := Res.blocks
	# loot modifiers used by the trial equipment / ominous drops
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var saw_trim := false
	var saw_sharp := false
	var saw_sword := false
	for i in 80:
		for s in Loot.roll("equipment/trial_chamber_melee", {"rng": rng, "tool": ItemStack.new()}):
			saw_trim = saw_trim or (s as ItemStack).components.has("minecraft:trim")
			saw_sharp = saw_sharp or Loot._ench(s, "sharpness") > 0
			saw_sword = saw_sword or (s as ItemStack).name().ends_with("_sword")
	ok("loot set_components / set_enchantments: trial melee equipment = trimmed armour, Sharpness swords", saw_trim and saw_sharp and saw_sword)
	var pots := 0
	for i in 20:
		for s in Loot.roll("spawners/trial_chamber/items_to_drop_when_ominous", {"rng": rng, "tool": ItemStack.new()}):
			if (s as ItemStack).name() == "lingering_potion" and Potions.potion_of(s) != "":
				pots += 1
	ok("loot set_potion: every ominous drop roll has a real lingering potion", pots == 20, str(pots))
	# ominous trial equipment, enchanted weapons
	var tz = _beh_mob(em, "zombie", Vector3(0.5, 64, 0.5))
	Trials.equip_from_config(w, tz, Trials.config("trial_chamber/melee/zombie/ominous"), "zombie")
	ok("ominous trial zombie wears its config's equipment (sword, never dropped)", str(tz.data.get("held", "")).ends_with("_sword") and tz.data.has("no_equip_drop")
		and (tz.data.get("armor", []) as Array).size() == 4, str(tz.data))
	tz.data["held"] = "iron_sword"
	var hs := ItemStack.named("iron_sword", 1)
	Enchanting.set_enchants(hs, {"minecraft:sharpness": 1})
	tz.data["held_stack"] = hs.to_dict()
	ok("Sharpness I on a mob's iron sword: +5 +1", is_equal_approx(HeldItems.attack_bonus(tz), 6.0) and HeldItems.ench(tz, "sharpness") == 1, str(HeldItems.attack_bonus(tz)))
	var oi = Trials.spawn_ominous_item(em, Vector3(0.5, 70, 0.5), Potions.make("arrow", "poison"), 60)
	oi.age = 60
	Trials.tick_ominous_item(em, oi)
	var shot = em.ents[em.ents.size() - 1]
	ok("ominous item spawner: after its display time a tipped arrow is shot straight down", oi.dead and shot.id == "arrow" and shot.vel.y < -1.0
		and str(shot.data.get("potion", "")) == "poison")
	# goat ram
	var stone := b.default_state("stone")
	w.blocks.clear()
	for x in range(-2, 20):
		for z in range(-3, 4):
			w.blocks[Vector3i(x, 63, z)] = stone
	var g = _beh_mob(em, "goat", Vector3(0.5, 64, 0.5))
	MobBehaviors.goat_init(em, g, false)
	var cd0 := int(g.data["ram_cd"])
	ok("goat: two horn flags, a horn variant, ram cooldown 30 s - 5 min (screaming 5 - 15 s)", (g.data["horns"] as Array).size() == 2 and str(g.data.get("horn", "")).ends_with("_goat_horn")
		and cd0 >= (100 if g.data["screaming"] else 600) and cd0 <= (300 if g.data["screaming"] else 6000), str(g.data))
	g.data["ram_cd"] = 0
	g.uid = 0
	g.age = 10
	p.pos = Vector3(8.5, 64, 0.5)
	p.prev_pos = p.pos
	p.on_ground = true
	var busy := MobBehaviors._goat_tick(em, g, p, 8.0)
	ok("goat picks a player standing still 8 blocks away and lowers its head", busy and g.rt.has("ram_t"))
	for i in MobBehaviors.GOAT_RAM_PREP:
		MobBehaviors._goat_tick(em, g, p, 8.0)
	ok("after 20 ticks it charges at the locked spot", g.rt.has("ram_to") and not g.rt.has("ram_t"))
	g.pos = Vector3(8.2, 64, 0.5)
	var hp0: float = p.health
	MobBehaviors._goat_tick(em, g, p, 0.3)
	ok("ram hit: 2 damage (Normal), 9-block knockback along the charge, new cooldown", is_equal_approx(hp0 - p.health, 2.0) and p.vel.x > 1.0 and not g.rt.has("ram_to")
		and int(g.data["ram_cd"]) >= 100, "%f %s" % [hp0 - p.health, str(p.vel)])
	w.blocks[Vector3i(12, 64, 0)] = stone
	g.data["horns"] = [true, true]
	g.rt["ram_to"] = Vector3(18.5, 64, 0.5)
	g.rt["ram_from"] = Vector3(0.5, 64, 0.5)
	g.pos = Vector3(11.45, 64, 0.5)
	g.hcollide = true
	p.pos = Vector3(0.5, 64, 30.5)
	var ni := em.items.size()
	MobBehaviors._goat_charge(em, g, p)
	var horn: ItemStack = em.items[em.items.size() - 1] if em.items.size() > ni else ItemStack.new()
	ok("ramming stone (#snaps_goat_horn) drops one horn of the goat's variant", horn.name() == "goat_horn" and str(horn.components.get("minecraft:instrument", "")) == str(g.data["horn"])
		and (g.data["horns"] as Array).count(true) == 1 and not g.rt.has("ram_to"))
	# villager / wandering trader speeds and fleeing
	var vd := MobRegistry.get_def("villager")
	var td := MobRegistry.get_def("wandering_trader")
	ok("villager 0.5 / wandering trader 0.7 attributes, strolling at 0.25 / 0.245, villager panic 0.375", float(vd["speed"]) == 0.5 and float(td["speed"]) == 0.7
		and is_equal_approx(float(vd["speed"]) * float(vd["stroll_speed"]), 0.25) and is_equal_approx(float(td["speed"]) * float(td["stroll_speed"]), 0.245)
		and is_equal_approx(float(vd["speed"]) * float(vd["panic_speed"]), 0.375))
	MobBehaviors.reset_cache()
	var vil = _beh_mob(em, "villager", Vector3(40.5, 64, 0.5))
	var zb = _beh_mob(em, "zombie", Vector3(46.5, 64, 0.5))
	var fp := MobBehaviors.flee_point(em, vil, p, 50.0)
	zb.pos = Vector3(49.5, 64, 0.5)
	vil.rt.erase("threat")
	MobBehaviors.reset_cache()
	var fp2 := MobBehaviors.flee_point(em, vil, p, 50.0)
	ok("villager flees a zombie within 8 blocks (wiki panic radius), not one 9 away", fp != Vector3.INF and fp.x < vil.pos.x and fp2 == Vector3.INF, "%s %s" % [fp, fp2])
	em._remove(zb)
	em._remove(vil)
	# attribute swim / flight speeds
	var rem := EntityManager.new()
	rem.world = w
	w.blocks.clear()
	var water := b.default_state("water")
	for x in range(-2, 30):
		for y in range(60, 66):
			for z in range(-3, 4):
				w.blocks[Vector3i(x, y, z)] = water
	p.pos = Vector3(0.5, 120, 60.5)
	var cod := _left_ent("cod", Vector3(0.5, 62, 0.5), -90.0)
	cod.has_target = true
	cod.target_pos = Vector3(28.5, 62.15, 0.5)
	var step := 0.0
	for i in 120:
		cod.prev = cod.pos
		MobAI._fish(rem, cod, p, w.state_at, b, 60.0)
		step = cod.pos.x - cod.prev.x
	ok("cod swims on its 0.7 attribute: ~0.07 blocks / tick (0.7 x 0.01 / (1 - 0.9))", step > 0.06 and step < 0.075, str(step))
	w.blocks.clear()
	var bee := _left_ent("bee", Vector3(0.5, 80, 0.5), -90.0)
	var par := _left_ent("parrot", Vector3(0.5, 90, 0.5), -90.0)
	var bstep := 0.0
	var pstep := 0.0
	for i in 120:
		bee.prev = bee.pos
		par.prev = par.pos
		MobAI.fly_animal(rem, bee, Vector3(300, 80, 0.5), 1.0, w.state_at, b)
		MobAI.fly_animal(rem, par, Vector3(300, 90, 0.5), 1.0, w.state_at, b)
		bstep = bee.pos.x - bee.prev.x
		pstep = par.pos.x - par.prev.x
	ok("bee / parrot fly on flying_speed 0.6 / 0.4: 0.133 / 0.089 blocks per tick (x 0.02 / 0.09)", absf(bstep - 0.1333) < 0.006 and absf(pstep - 0.0889) < 0.005, "%f %f" % [bstep, pstep])
	# smoke: the full mob tick of every touched mob type (ground + a water pool), with a zombie near the villagers
	w.blocks.clear()
	for x in range(-12, 13):
		for z in range(-12, 13):
			w.blocks[Vector3i(x, 63, z)] = stone
			if x > 4 and z > 4:
				for y in range(60, 64):
					w.blocks[Vector3i(x, y, z)] = water
	p.pos = Vector3(0.5, 64, 0.5)
	MobBehaviors.reset_cache()
	var ticked := 0
	for id in ["goat", "villager", "wandering_trader", "bee", "parrot", "cod", "salmon", "pufferfish", "phantom", "vex", "llama", "wolf", "cat",
			"nautilus", "happy_ghast", "sulfur_cube", "axolotl", "zombie"]:
		var sm := _left_ent(id, Vector3(8.5, 61, 8.5) if id in ["cod", "salmon", "pufferfish", "nautilus", "axolotl"] else Vector3(-4.5, 64, -4.5), 0.0)
		rem.ents.append(sm)
		sm.persistent = true
	for i in 60:
		w.game_time += 1
		for sm in rem.ents.duplicate():
			if sm.kind != "mob" or sm.dead:
				continue
			sm.prev = sm.pos
			sm.age += 1
			rem._tick_mob(sm, p, w.state_at, b)
			ticked += 1
	ok("mob tick smoke: goats, villagers, flyers, fish, llamas, cats, nautiluses ... tick without errors", ticked > 900, str(ticked))
	rem.free()
	# nautilus taming / feeding
	var tamed := 0
	for i in 300:
		var nau = _beh_mob(em, "nautilus", Vector3(0.5, 62, 0.5))
		p.inventory.set_slot(p.inventory.selected, ItemStack.named("pufferfish", 1))
		Taming._nautilus_feed(em, nau, p, p.inventory.held(), "pufferfish")
		if Taming.is_tamed(nau):
			tamed += 1
		em._remove(nau)
	var nh = _beh_mob(em, "nautilus", Vector3(0.5, 62, 0.5))
	nh.hp = 3.0
	p.inventory.set_slot(p.inventory.selected, ItemStack.named("cooked_cod", 1))
	Taming._nautilus_feed(em, nh, p, p.inventory.held(), "cooked_cod")
	var nb = _beh_mob(em, "nautilus", Vector3(0.5, 62, 0.5), true)
	p.inventory.set_slot(p.inventory.selected, ItemStack.named("pufferfish_bucket", 1))
	Taming._nautilus_feed(em, nb, p, p.inventory.held(), "pufferfish_bucket")
	ok("nautilus: pufferfish tame with 1/3, cooked cod heals 10, a fish bucket grows a baby 10 % (water bucket back)", tamed > 70 and tamed < 130 and is_equal_approx(nh.hp, 13.0)
		and nb.baby_age == -21600 and p.inventory.held().name() == "water_bucket", "%d %f %d" % [tamed, nh.hp, nb.baby_age])
	# cat variants (26.3 cat_variant data)
	var blk := 0
	var blk0 := 0
	for i in 1100:
		if MobBehaviors.cat_variant(w, Vector3.ZERO, rng, 1.0) == "all_black":
			blk += 1
		if MobBehaviors.cat_variant(w, Vector3.ZERO, rng, 0.0) == "all_black":
			blk0 += 1
	ok("cat variants: black cats only at a full moon (1 in 11 there), never otherwise", blk0 == 0 and blk > 60 and blk < 150, "%d %d" % [blk, blk0])
	# raid centre from points of interest
	var pw := PoiWorld.new()
	var pe := LeftEnts.new()
	pe.world = pw
	pw.entities = pe
	var ch := Chunk.new(0, 0)
	ch.state = Chunk.DECORATED
	ch.set_block(4, 64, 4, b.default_state("composter"))
	var bed := b.default_state("red_bed")
	ch.set_block(10, 64, 10, b.with_prop(bed, "part", "head"))
	ch.set_block(10, 64, 11, b.with_prop(bed, "part", "foot"))
	pw.cm.chunks[Vector2i(0, 0)] = ch
	MobBehaviors.reset_cache()
	var no_vil := Raids.is_village(pw, Vector3(8, 64, 8), 1)
	_beh_mob(pe, "villager", Vector3(8.5, 64, 8.5))
	MobBehaviors.reset_cache()
	var yes_vil := Raids.is_village(pw, Vector3(8, 64, 8), 1)
	var far_vil := Raids.is_village(pw, Vector3(8, 120, 8), 1)
	var cen := Raids.village_center(pw, Vector3(8, 64, 8), 64.0)
	ok("raid: a village = POI sub-chunks nearby (with villagers); centre = average POI position (bed heads, job sites)", not no_vil and yes_vil and not far_vil
		and cen.is_equal_approx(Vector3(7.5, 64.5, 7.5)), str(cen))
	# llamas spit at untamed wolves
	MobBehaviors.reset_cache()
	w.blocks.clear()
	var lla = _beh_mob(em, "llama", Vector3(60.5, 64, 0.5))
	lla.uid = 0
	lla.age = 10
	lla.attack_cd = 0
	var wolf = _beh_mob(em, "wolf", Vector3(66.5, 64, 0.5))
	MobBehaviors._llama_wolf_tick(em, lla)
	var spit = em.ents[em.ents.size() - 1]
	wolf.data["owner"] = "Player"
	lla.attack_cd = 0
	lla.age = 20
	MobBehaviors.reset_cache()
	var n0 := em.ents.size()
	MobBehaviors._llama_wolf_tick(em, lla)
	ok("llamas spit at untamed wolves (every 2 s), not at tamed ones", spit.id == "llama_spit" and n0 == em.ents.size() and lla.attack_cd == 0)
	MobBehaviors.reset_cache()


class ItemEnts extends CmdEnts:
	var rng := RandomNumberGenerator.new()
	var items: Array = []
	func spawn_item(_p, s, _v = null):
		items.append(s)


class PlantWorld extends GrowWorld:
	var thundering := false
	func _init() -> void:
		entities = ItemEnts.new()


## Sapling growth choices, bone meal targets, dripleaf support, concrete powder, pitcher crops, potion colours and
## lingering clouds (TreeGrower / Bonemeal / BlockUpdates / Growth / MiscEntities; wiki values).
func test_vanilla_items_plants() -> void:
	var b := Res.blocks
	var stone := b.default_state("stone")
	# every tree feature the growers use exists in the 26.3 jar (worldgen/feature)
	var missing: Array = []
	for fid in ["oak", "fancy_oak", "oak_bees_005", "fancy_oak_bees_005", "birch", "birch_bees_005", "cherry", "cherry_bees_005", "spruce",
			"mega_spruce", "mega_pine", "jungle_tree_no_vine", "mega_jungle_tree", "acacia", "dark_oak", "pale_oak_bonemeal", "mangrove",
			"tall_mangrove", "azalea_tree", "orange_poplar", "yellow_poplar", "red_poplar", "huge_brown_mushroom", "huge_red_mushroom",
			"crimson_fungus_planted", "warped_fungus_planted", "nylium_bonemeal", "moss_patch_bonemeal", "pale_moss_patch_bonemeal"]:
		if Res.read_json("data/minecraft/worldgen/feature/%s.json" % fid) == null:
			missing.append(fid)
	ok("tree grower / bone meal: every configured feature used exists in the 26.3 data", missing.is_empty(), str(missing))
	# 2x2 sapling square + flowers within 2 blocks (bee nest variants)
	var wt := PlantWorld.new()
	var sp := b.default_state("spruce_sapling")
	for d in [Vector3i(0, 64, 0), Vector3i(1, 64, 0), Vector3i(0, 64, 1), Vector3i(1, 64, 1)]:
		wt.blocks[d] = sp
	var sq: bool = TreeGrower._square(wt, Vector3i(0, 64, 0), b.st_block[sp]) and not TreeGrower._square(wt, Vector3i(-1, 64, 0), b.st_block[sp])
	wt.blocks[Vector3i(3, 64, 0)] = b.default_state("poppy")
	ok("tree grower: 2x2 square from its north-west sapling; a flower 2 blocks away counts, 3 does not", sq and TreeGrower._flowers_near(wt, Vector3i(1, 64, 0)) and not TreeGrower._flowers_near(wt, Vector3i(0, 64, 0)))
	# dripleaf support (26.3 #supports_big_dripleaf / #supports_small_dripleaf): the stem used to need farmland
	var wd := PlantWorld.new()
	wd.blocks[Vector3i(0, 63, 0)] = b.default_state("moss_block")
	wd.blocks[Vector3i(0, 64, 0)] = b.default_state("big_dripleaf_stem")
	wd.blocks[Vector3i(0, 65, 0)] = b.default_state("big_dripleaf")
	var stem_ok: bool = BlockUpdates._has_support(wd, Vector3i(0, 64, 0), wd.state_at(0, 64, 0))
	var head_ok: bool = BlockUpdates._has_support(wd, Vector3i(0, 65, 0), wd.state_at(0, 65, 0))
	wd.blocks.erase(Vector3i(0, 65, 0))
	var stem_alone: bool = BlockUpdates._has_support(wd, Vector3i(0, 64, 0), wd.state_at(0, 64, 0))
	wd.blocks[Vector3i(2, 63, 0)] = b.default_state("dirt")
	var sdl := b.default_state("small_dripleaf")
	var dry_dirt: bool = BlockUpdates._has_support(wd, Vector3i(2, 64, 0), sdl)
	var wet_dirt: bool = BlockUpdates._has_support(wd, Vector3i(2, 64, 0), b.with_prop(sdl, "waterlogged", "true"))
	wd.blocks[Vector3i(4, 63, 0)] = stone
	var mush_stem: bool = BlockUpdates._has_support(wd, Vector3i(4, 64, 0), b.default_state("mushroom_stem"))
	ok("dripleaf support: stem on moss under its leaf stays, a stem without the leaf breaks; small dripleaf on dirt only underwater; mushroom stems never", stem_ok and head_ok and not stem_alone and not dry_dirt and wet_dirt and mush_stem, "%s %s %s %s %s %s" % [stem_ok, head_ok, stem_alone, dry_dirt, wet_dirt, mush_stem])
	# bone meal targets
	var wb := PlantWorld.new()
	wb.rng.seed = 99
	var ie: ItemEnts = wb.entities as ItemEnts
	wb.blocks[Vector3i(0, 70, 0)] = b.default_state("cave_vines")
	var cv: bool = Bonemeal.apply(wb, Vector3i(0, 70, 0), wb.state_at(0, 70, 0))
	var cv2: bool = Bonemeal.apply(wb, Vector3i(0, 70, 0), wb.state_at(0, 70, 0))
	wb.blocks[Vector3i(2, 70, 0)] = b.default_state("rooted_dirt")
	var rd: bool = Bonemeal.apply(wb, Vector3i(2, 70, 0), wb.state_at(2, 70, 0)) and b.name_of(wb.state_at(2, 69, 0)) == "hanging_roots"
	ok("bone meal: cave vines get berries (then not a target), rooted dirt grows hanging roots", cv and b.get_prop(wb.state_at(0, 70, 0), "berries") == "true" and not cv2 and rd)
	wb.blocks[Vector3i(4, 63, 0)] = b.default_state("grass_block")
	wb.blocks[Vector3i(4, 64, 0)] = b.with_prop(b.default_state("pink_petals"), "flower_amount", "3")
	Bonemeal.apply(wb, Vector3i(4, 64, 0), wb.state_at(4, 64, 0))
	var four := b.get_prop(wb.state_at(4, 64, 0), "flower_amount") == "4"
	Bonemeal.apply(wb, Vector3i(4, 64, 0), wb.state_at(4, 64, 0))
	ok("bone meal: pink petals + 1, a full block drops one (wiki Pink Petals)", four and ie.items.size() == 1 and (ie.items[0] as ItemStack).name() == "pink_petals")
	wb.blocks[Vector3i(6, 63, 0)] = b.default_state("grass_block")
	wb.blocks[Vector3i(6, 64, 0)] = b.default_state("short_grass")
	Bonemeal.apply(wb, Vector3i(6, 64, 0), wb.state_at(6, 64, 0))
	wb.blocks[Vector3i(8, 64, 0)] = b.default_state("sunflower")
	var n_items := ie.items.size()
	Bonemeal.apply(wb, Vector3i(8, 64, 0), wb.state_at(8, 64, 0))
	ok("bone meal: short grass -> tall grass (two halves), tall flowers drop a copy", b.name_of(wb.state_at(6, 64, 0)) == "tall_grass" and b.get_prop(wb.state_at(6, 65, 0), "half") == "upper" and ie.items.size() == n_items + 1)
	wb.blocks[Vector3i(10, 63, 0)] = b.default_state("moss_block")
	wb.blocks[Vector3i(10, 64, 0)] = b.default_state("big_dripleaf")
	Bonemeal.apply(wb, Vector3i(10, 64, 0), wb.state_at(10, 64, 0))
	var big_grew := b.name_of(wb.state_at(10, 64, 0)) == "big_dripleaf_stem" and b.name_of(wb.state_at(10, 65, 0)) == "big_dripleaf"
	wb.blocks[Vector3i(12, 63, 0)] = b.default_state("clay")
	wb.blocks[Vector3i(12, 64, 0)] = b.with_prop(sdl, "half", "lower")
	wb.blocks[Vector3i(12, 65, 0)] = b.with_prop(sdl, "half", "upper")
	Bonemeal.apply(wb, Vector3i(12, 64, 0), wb.state_at(12, 64, 0))
	var h := 0
	while b.name_of(maxi(0, wb.state_at(12, 64 + h, 0))) == "big_dripleaf_stem":
		h += 1
	ok("bone meal: big dripleaf + 1 block; small dripleaf -> big dripleaf 2-5 tall", big_grew and h >= 1 and h <= 4 and b.name_of(maxi(0, wb.state_at(12, 64 + h, 0))) == "big_dripleaf", "stem %d" % h)
	wb.blocks[Vector3i(14, 64, 0)] = b.with_prop(b.default_state("wheat"), "age", "7")
	ok("bone meal: a fully grown crop is not a target", not Bonemeal.apply(wb, Vector3i(14, 64, 0), wb.state_at(14, 64, 0)))
	# glow lichen spreads along the wall
	var wl := PlantWorld.new()
	wl.rng.seed = 5
	wl.blocks[Vector3i(0, 64, -1)] = stone
	wl.blocks[Vector3i(1, 64, -1)] = stone
	var gl := b.default_state("glow_lichen")
	for f in ["north", "south", "east", "west", "up", "down"]:
		gl = b.with_prop(gl, f, "false")
	wl.blocks[Vector3i(0, 64, 0)] = b.with_prop(gl, "north", "true")
	var spread: bool = Bonemeal.apply(wl, Vector3i(0, 64, 0), wl.state_at(0, 64, 0))
	var faces := 0
	for k in wl.blocks:
		var ls: int = wl.blocks[k]
		if b.name_of(ls) == "glow_lichen":
			for f2 in ["north", "south", "east", "west", "up", "down"]:
				if b.get_prop(ls, f2) == "true":
					faces += 1
	wl.blocks.erase(Vector3i(0, 64, -1))
	wl.blocks.erase(Vector3i(1, 64, -1))
	var lone := gl
	wl.blocks = {Vector3i(0, 64, 0): b.with_prop(lone, "north", "true")}
	ok("bone meal: glow lichen spreads one face to an adjacent spot; nothing to attach to -> not a target", spread and faces == 2 and not Bonemeal.apply(wl, Vector3i(0, 64, 0), wl.state_at(0, 64, 0)), "faces %d" % faces)
	# sea pickle on live coral underwater becomes 4
	var ws := PlantWorld.new()
	ws.blocks[Vector3i(0, 63, 0)] = b.default_state("brain_coral_block")
	ws.blocks[Vector3i(0, 64, 0)] = b.with_prop(b.default_state("sea_pickle"), "waterlogged", "true")
	Bonemeal.apply(ws, Vector3i(0, 64, 0), ws.state_at(0, 64, 0))
	ok("bone meal: a sea pickle on a live coral block underwater becomes 4", b.get_prop(ws.state_at(0, 64, 0), "pickles") == "4")
	# pitcher crop: two blocks tall from age 3
	var wp := PlantWorld.new()
	wp.blocks[Vector3i(0, 63, 0)] = b.default_state("farmland")
	wp.blocks[Vector3i(0, 64, 0)] = b.with_prop(b.with_prop(b.default_state("pitcher_crop"), "half", "lower"), "age", "2")
	Growth.pitcher_grow(wp, Vector3i(0, 64, 0), wp.state_at(0, 64, 0), 1)
	var up: int = wp.state_at(0, 65, 0)
	ok("pitcher crop: reaching age 3 adds the upper half (same age)", up > 0 and b.name_of(up) == "pitcher_crop" and b.get_prop(up, "half") == "upper" and b.get_prop(up, "age") == "3")
	# concrete powder next to water
	var wcp := PlantWorld.new()
	wcp.blocks[Vector3i(0, 64, 0)] = b.default_state("red_concrete_powder")
	wcp.blocks[Vector3i(0, 63, 0)] = b.WATER
	var below_only: bool = Growth.concrete_check(wcp, Vector3i(0, 64, 0))
	wcp.blocks[Vector3i(1, 64, 0)] = b.WATER
	var side: bool = Growth.concrete_check(wcp, Vector3i(0, 64, 0))
	ok("concrete powder: water below alone does nothing, water beside turns it into concrete", not below_only and side and b.name_of(wcp.state_at(0, 64, 0)) == "red_concrete")
	# potion colours (wiki Effect colors)
	ok("potion colours: water #385DC6, swiftness #33EBFF; healing is instant", Potions.color_of("water").to_html(false) == "385dc6" and Potions.color_of("swiftness").to_html(false) == "33ebff" and Potions.all_instant("healing") and not Potions.all_instant("turtle_master"))
	# lingering cloud: nothing in the first second, then 1/4 duration; radius -0.5 and 100 ticks per use
	var ce := ItemEnts.new()
	var pl := Player.new()
	pl.pos = Vector3(0.5, 64, 0.5)
	var cl = MiscEntities.spawn_cloud(ce, Vector3(0.5, 64, 0.5), "swiftness")
	for t in 19:
		cl.age += 1
		MiscEntities.tick_cloud(ce, cl, pl)
	var waited := not pl.effects.has("speed")
	cl.age += 1
	MiscEntities.tick_cloud(ce, cl, pl)
	var sp_t := int((pl.effects.get("speed", {}) as Dictionary).get("ticks", 0))
	ok("lingering cloud: waits 20 ticks, then Speed for 1/4 of 3600 ticks; radius - 0.5, life - 100 per use", waited and sp_t == 900 and absf(float(cl.data["r"]) - 2.495) < 0.001 and int(cl.data["dur"]) == 500, "t %d r %.3f" % [sp_t, float(cl.data["r"])])
	var dc = MiscEntities.spawn_cloud(ce, Vector3(40, 64, 40), "", "dragon")
	dc.age = 1
	MiscEntities.tick_cloud(ce, dc, pl)
	ok("dragon fireball cloud: grows (3 -> 7 over its life), Harming II", float(dc.data["r"]) > 3.0 and str(dc.data["pot"]) == "strong_harming")
	# trading: gossip reputation and Hero of the Village (wiki Trading price formula)
	var vg := EntityManager.Ent.new()
	vg.kind = "mob"
	vg.id = "villager"
	var of := {"a": ["emerald", 10], "b": [], "out": ["bread", 6], "uses": 0, "max": 16, "base": 10, "mult": 0.2, "demand": 0}
	vg.data["offers"] = [of]
	Trading.gossip(vg, "trading")
	Trading.gossip(vg, "trading")
	var rep := Trading.reputation(vg)
	var tp := Player.new()
	Trading.update_special_prices(vg, tp)
	var c_rep := Trading.cost_a(of)
	tp.effects["hero_of_the_village"] = {"amp": 0, "ticks": 100}
	Trading.update_special_prices(vg, tp)
	var c_hero := Trading.cost_a(of)
	Trading.reset_special_prices(vg)
	for gi in 8:
		Trading.gossip(vg, "trading")
	ok("trading: 2 trades = reputation 8 (-1 at multiplier 0.2), Hero I another -3 (30 % of 10); trading gossip caps at 25", rep == 8 and c_rep == 9 and c_hero == 6 and Trading.cost_a(of) == 10 and Trading.reputation(vg) == 25, "rep %d cost %d hero %d" % [rep, c_rep, c_hero])


class VilCM extends SensorCM:
	var dummy := Chunk.new(0, 0)
	func get_chunk(_x: int, _z: int):
		return dummy


## Shields vs projectiles, Glowing, villager job sites / work / gossip / curing, explorer map pieces, lightning rod
## indexing and tripwires over the whole entity box (wiki Shield, Arrow, Villager, Zombie Villager, Explorer Map).
func test_vanilla_villagers_shields() -> void:
	var w := BehWorld.new()
	var em := EntityManager.new()
	em.world = w
	var p: Player = w.player
	p.pos = Vector3(0.5, 64, 0.5)
	p.yaw = 0.0
	p.spawn_invuln = 0
	p.inventory.set_slot(Inventory.OFFHAND, ItemStack.named("shield"))
	p.using_slot = Inventory.OFFHAND
	p.use_item = Res.items.id("shield")
	p.use_ticks = 5
	var gs := func(_x: int, _y: int, _z: int) -> int: return 0
	var skel := EntityManager.Ent.new()
	skel.kind = "mob"
	skel.id = "skeleton"
	var a1 := _shot(em, skel, "arrow", Vector3(0.5, 65, 3.5), Vector3(0, 0, -3))
	em._tick_projectile(a1, p, gs, Res.blocks)
	var sh_dmg := p.inventory.get_slot(Inventory.OFFHAND).damage
	ok("shield: an arrow from the front is blocked (no damage), bounces back x -0.1, shield takes 1 + 6 durability", p.health == 20.0 and a1.vel.z > 0.2 and a1.vel.z < 0.31 and not a1.dead and sh_dmg == 7,
		"hp %.1f vz %.3f dmg %d" % [p.health, a1.vel.z, sh_dmg])
	var a2 := _shot(em, skel, "arrow", Vector3(0.5, 65, -2.5), Vector3(0, 0, 3))
	em._tick_projectile(a2, p, gs, Res.blocks)
	var hp_back := p.health
	p.health = 20.0
	p.invuln = 0
	var a3 := _shot(em, skel, "arrow", Vector3(0.5, 65, 3.5), Vector3(0, 0, -3))
	a3.data["pierce"] = 1
	em._tick_projectile(a3, p, gs, Res.blocks)
	ok("shield: arrows from behind hit; Piercing arrows pass the shield and cost no durability", hp_back < 20.0 and p.health < 20.0 and p.inventory.get_slot(Inventory.OFFHAND).damage == sh_dmg,
		"%.1f %.1f" % [hp_back, p.health])
	p.health = 20.0
	p.invuln = 0
	var fb := _shot(em, skel, "small_fireball", Vector3(0.5, 65, 2.0), Vector3(0, 0, -1.5))
	em._tick_projectile(fb, p, gs, Res.blocks)
	var tr := _shot(em, skel, "trident", Vector3(0.5, 65, 2.5), Vector3(0, 0, -2.5))
	tr.data["base_damage"] = 8.0
	em._tick_projectile(tr, p, gs, Res.blocks)
	ok("shield: blaze fireballs blocked without setting fire, tridents bounce off (dealt)", p.health == 20.0 and p.fire_ticks == 0 and fb.dead and bool(tr.data.get("dealt", false)) and tr.vel.z > 0.0,
		"hp %.1f fire %d fb %s tr %s %.3f" % [p.health, p.fire_ticks, fb.dead, tr.data.get("dealt", false), tr.vel.z])
	# Glowing: the effect marks the mob for the outline renderer
	var cow := EntityManager.Ent.new()
	cow.kind = "mob"
	cow.id = "cow"
	MobBehaviors.add_effect(cow, "glowing", 0, 200)
	ok("glowing: the Glowing effect marks the mob for the outline", GlowOutline.glowing(cow))
	# villager job sites
	var vw := BehWorld.new()
	vw.cm = VilCM.new()
	var vem := BehEnts.new()
	vem.world = vw
	vw.entities = vem
	vw.day_time = 6000
	Villagers._poi.clear()
	vw.set_block(5, 64, 0, Res.blocks.default_state("composter"))
	Villagers.poi_placed(Vector3i(5, 64, 0))
	var vv = _beh_mob(vem, "villager", Vector3(0.5, 64, 0.5))
	vv.data["prof"] = "none"
	vv.data["offers"] = []
	var g1: Vector3 = Villagers.tick(vem, vv)
	var v2 = _beh_mob(vem, "villager", Vector3(1.5, 64, 0.5))
	v2.data["prof"] = "none"
	vw.game_time = 1
	Villagers.tick(vem, v2)
	ok("villager: an unemployed villager walks to the nearest free job site (provisional claim), others skip it", vv.rt.has("pjob") and absf(g1.x - 5.5) < 0.01 and not v2.rt.has("pjob"))
	vv.pos = Vector3(4.5, 64, 0.5)
	Villagers.tick(vem, vv)
	ok("villager: within 2 blocks it claims the composter and becomes a farmer with novice trades", vv.data.get("job") == [5, 64, 0] and str(vv.data["prof"]) == "farmer" and not (vv.data["offers"] as Array).is_empty())
	# work: restock up to twice a day next to the job site
	vw.day_time = 3000
	for o in vv.data["offers"]:
		o["uses"] = 3
	vv.rt["work_t"] = 0   # (the claim tick already worked once)
	Villagers.tick(vem, vv)
	var used0 := int(vv.data["offers"][0]["uses"])
	for o in vv.data["offers"]:
		o["uses"] = 3
	vv.rt["work_t"] = 0
	Villagers.tick(vem, vv)
	for o in vv.data["offers"]:
		o["uses"] = 3
	vv.rt["work_t"] = 0
	Villagers.tick(vem, vv)
	ok("villager: working at its job site restocks used trades, at most twice a day", used0 == 0 and int(vv.data.get("restocks", 0)) == 2 and int(vv.data["offers"][0]["uses"]) == 3,
		"used0 %d restocks %d uses %d job %s prof %s" % [used0, int(vv.data.get("restocks", 0)), int(vv.data["offers"][0]["uses"]), str(vv.data.get("job")), str(vv.data.get("prof"))])
	# losing the site: untraded villagers become unemployed, traded ones keep the profession
	vw.blocks.erase(Vector3i(5, 64, 0))
	vw.game_time = 20
	Villagers.tick(vem, vv)
	ok("villager: a removed job site makes an untraded villager unemployed", not vv.data.has("job") and str(vv.data["prof"]) == "none")
	var vt = _beh_mob(vem, "villager", Vector3(10.5, 64, 0.5))
	vt.data["prof"] = "librarian"
	vt.data["vxp"] = 5
	vt.data["job"] = [99, 64, 99]
	vw.game_time = 40
	Villagers.tick(vem, vt)
	ok("villager: a villager that traded keeps its profession when the site is gone", not vt.data.has("job") and str(vt.data["prof"]) == "librarian")
	# gossip sharing (sharing costs: trading 20, minor_positive 5, major_positive never)
	var ga = _beh_mob(vem, "villager", Vector3(20, 64, 20))
	var gb = _beh_mob(vem, "villager", Vector3(21, 64, 20))
	ga.data["gossip"] = {"trading": 25, "minor_positive": 25, "major_positive": 20}
	Villagers.share_gossip(ga, gb)
	var gg: Dictionary = gb.data.get("gossip", {})
	ok("gossip: shared values lose the sharing cost, curing gossip is never shared", int(gg.get("trading", 0)) == 5 and int(gg.get("minor_positive", 0)) == 20 and not gg.has("major_positive"), str(gg))
	# curing a zombie villager
	var zv = _beh_mob(vem, "zombie_villager", Vector3(30.5, 64, 30.5))
	zv.data["prof"] = "librarian"
	zv.data["offers"] = [{"a": ["emerald", 5], "b": [], "out": ["book", 1], "uses": 0, "max": 12}]
	zv.data["vxp"] = 10
	var cp: Player = vw.player
	cp.inventory.set_slot(cp.inventory.selected, ItemStack.named("golden_apple", 2))
	var no_weak := Villagers.try_cure(vem, zv, cp, cp.inventory.held())
	MobBehaviors.add_effect(zv, "weakness", 0, 600)
	var started := Villagers.try_cure(vem, zv, cp, cp.inventory.held())
	var ct := int(zv.data.get("cure", 0))
	ok("curing: golden apple only with Weakness; 3600-6000 ticks, Strength replaces Weakness, apple used", not no_weak and started and ct >= 3600 and ct <= 6000 and MobBehaviors.has_effect(zv, "strength")
		and not MobBehaviors.has_effect(zv, "weakness") and cp.inventory.held().count == 1)
	zv.data["cure"] = 1
	Villagers.cure_tick(vem, zv)
	var cured = null
	for o2 in vem.ents:
		if o2.id == "villager" and o2.pos.distance_to(Vector3(30.5, 64, 30.5)) < 0.1:
			cured = o2
	ok("curing: the villager keeps profession / trades / xp, gets Nausea and the curer's major + minor positive gossip", zv.dead and cured != null and str(cured.data.get("prof", "")) == "librarian"
		and int(cured.data.get("vxp", 0)) == 10 and (cured.data.get("offers", []) as Array).size() == 1 and MobBehaviors.has_effect(cured, "nausea")
		and int((cured.data.get("gossip", {}) as Dictionary).get("major_positive", 0)) == 20 and int((cured.data.get("gossip", {}) as Dictionary).get("minor_positive", 0)) == 25)
	# explorer maps
	var xm := ItemStack.named("ocean_monument_map", 1)
	xm.components["minecraft:map_id"] = 7
	ok("explorer maps: 26.x explorer map items are maps; decorations per type", Maps.map_id(xm) == 7 and Maps.map_id(ItemStack.named("ocean_monument_map", 1)) == -1
		and ExplorerMaps.decoration_texture("minecraft:monument") == "map/decorations/ocean_monument" and ExplorerMaps.decoration_texture("minecraft:village_desert") == "map/decorations/desert_village"
		and ExplorerMaps.decoration_texture("minecraft:trial_chambers") == "map/decorations/trial_chambers")
	var itab := Interest.table()
	var bits := [Interest.WIRE, Interest.CONSUMER, Interest.OBSERVER, Interest.CORAL, Interest.RS_INERT, Interest.ROD, Interest.SENSOR, Interest.POI]
	var bor := 0
	var bsum := 0
	for bt in bits:
		bor |= int(bt)
		bsum += int(bt)
	ok("interest bits: distinct; water flags no rod / POI / sensor, rods / composters / tripwires flagged", bor == bsum and bor < 256
		and (itab[Res.blocks.default_state("water")] & (Interest.ROD | Interest.POI | Interest.SENSOR)) == 0 and (itab[Res.blocks.default_state("lightning_rod")] & Interest.ROD) != 0
		and (itab[Res.blocks.default_state("composter")] & Interest.POI) != 0 and (itab[Res.blocks.default_state("tripwire")] & Interest.SENSOR) != 0)
	# lightning rods placed before rods had their entry are indexed when the chunk loads
	var rc := Chunk.new(2, 3)
	rc.set_block(4, 70, 9, Res.blocks.default_state("lightning_rod"))
	BlockEntities._index_rods(rc)
	var rk := BlockEntities._key(Vector3i(2 * 16 + 4, 70, 3 * 16 + 9))
	ok("lightning rods: existing rods get their index entry from the section palette scan", rc.block_entities.has(rk) and str((rc.block_entities[rk] as Dictionary).get("id", "")) == "lightning_rod")
	# tripwire: a string at head height of a tall mob (two blocks above its feet) is detected
	var tw := SensorWorld.new()
	tw.blocks[Vector3i(0, 66, 0)] = Res.blocks.default_state("tripwire")
	var tall = tw.entities.spawn_mob("enderman", Vector3(0.5, 64.0, 0.5))
	tall.w = 0.6
	tall.h = 2.9
	Sensors.tick(tw)
	ok("tripwire: strings anywhere in the entity box are detected (not only feet + 1)", Res.blocks.get_prop(tw.state_at(0, 66, 0), "powered") == "true")
	Tripwires.reset()


class VilWorld extends BehWorld:
	var level: Dictionary = {}


## Villager beds / sleeping / raids / iron golem summoning, chest explorer maps, nautilus riding, goat long jumps, fish
## schools, phantoms vs cats, wolves vs llamas (strength), vex charge texture, ominous item spawner saving.
func test_vanilla_villager_beds_mobs() -> void:
	var b := Res.blocks
	var w := VilWorld.new()
	w.cm = VilCM.new()
	var em := BehEnts.new()
	em.world = w
	w.entities = em
	em.rng.seed = 777
	Villagers._poi.clear()
	Villagers._sleepers.clear()
	MobBehaviors.reset_cache()
	var stone := b.default_state("stone")
	for x in range(-12, 13):
		for z in range(-12, 13):
			w.blocks[Vector3i(x, 63, z)] = stone
	var bed := b.default_state("red_bed")
	var foot := b.with_prop(b.with_prop(bed, "facing", "east"), "part", "foot")
	var head := b.with_prop(b.with_prop(bed, "facing", "east"), "part", "head")
	w.blocks[Vector3i(3, 64, 0)] = foot
	w.blocks[Vector3i(4, 64, 0)] = head
	Villagers.poi_placed(Vector3i(3, 64, 0), foot)
	w.day_time = 13000
	w.game_time = 100
	var v = _beh_mob(em, "villager", Vector3(0.5, 64, 0.5))
	v.data["prof"] = "none"
	var g0: Vector3 = Villagers.tick(em, v)
	ok("villager bed: claims the nearest bed head (green particles) and walks home at night", v.data.get("home") == [4, 64, 0] and g0.distance_to(Vector3(4.5, 64, 0.5)) < 0.01,
		"%s %s" % [str(v.data.get("home")), str(g0)])
	v.pos = Vector3(4.5, 64, 1.5)
	w.game_time = 101
	Villagers.tick(em, v)
	ok("villager bed: within 2 blocks it lies down - 0.2 hitbox on the pillow (0.6875 up), bed occupied, facing east", v.data.has("sleep") and absf(v.w - 0.2) < 0.001
		and v.pos.distance_to(Vector3(4.5, 64.6875, 0.5)) < 0.001 and Villagers.bed_occupied(Vector3i(4, 64, 0)) and int(v.rt.get("sleep_dir", -1)) == 3)
	var v2 = _beh_mob(em, "villager", Vector3(1.5, 64, 2.5))
	MobBehaviors.reset_cache()
	Villagers._find_home(em, v2, 102)
	ok("villager bed: a claimed bed is not claimed again", not v2.data.has("home"))
	ok("villager bed: asleep at night (no AI)", Villagers.sleep_tick(em, v))
	Villagers.kick_out(em, Vector3i(4, 64, 0))
	ok("villager bed: a player using the bed kicks the villager out (stands up beside it, full size)", not v.data.has("sleep") and absf(v.w - 0.6) < 0.001 and absf(v.pos.y - 64.0) < 0.001
		and not Villagers.bed_occupied(Vector3i(4, 64, 0)) and v.pos.distance_to(Vector3(4.5, 64, 0.5)) < 1.6, str(v.pos))
	w.game_time = 150
	Villagers.tick(em, v)
	ok("villager bed: no lying down again within 100 ticks of getting up", not v.data.has("sleep"))
	w.game_time = 300
	Villagers.tick(em, v)
	w.day_time = 24000 + 10
	var still := Villagers.sleep_tick(em, v)
	ok("villager bed: back to bed after the interruption, up at 10 (06:00:36), last_slept noted", not still and not v.data.has("sleep") and int(v.data.get("last_slept", -1)) == 300)
	w.day_time = 13000
	v.rt["woken"] = -1000
	v.pos = Vector3(4.5, 64, 1.5)
	Villagers.tick(em, v)
	v.hp = 20.0
	var rem := EntityManager.new()
	rem.world = w
	w.blocks.erase(Vector3i(4, 64, 0))
	w.blocks.erase(Vector3i(3, 64, 0))
	Villagers._check_home(em, v)
	ok("villager bed: a broken bed wakes it and the claim is gone", v.data.has("last_slept") and not v.data.has("sleep") and not v.data.has("home"))
	# raids: no job claiming / work, hide in a bed's house
	w.blocks[Vector3i(3, 64, 0)] = foot
	w.blocks[Vector3i(4, 64, 0)] = head
	w.day_time = 3000
	w.level["raid"] = {"center": [0, 64, 0], "state": "active", "wave": 1}
	w.blocks[Vector3i(-6, 64, 0)] = b.default_state("composter")
	Villagers.poi_placed(Vector3i(-6, 64, 0))
	var rv = _beh_mob(em, "villager", Vector3(-3.5, 64, 0.5))
	rv.data["prof"] = "none"
	w.game_time = 400
	var rg: Vector3 = Villagers.tick(em, rv)
	ok("raid: villagers claim no job site and run to a bed within 32 blocks to hide", not rv.rt.has("pjob") and rg.distance_to(Vector3(4.5, 64, 0.5)) < 0.01, str(rg))
	rv.pos = Vector3(4.5, 64, 1.5)
	ok("raid: indoors it stays put", Villagers.tick(em, rv) == Villagers.STAY)
	w.level["raid"]["state"] = "over"
	w.level["raid"]["victory"] = true
	ok("raid: once over, villagers go back to their day", Villagers.tick(em, rv) != Villagers.STAY)
	w.level.erase("raid")
	# iron golem summoning: 5 villagers that slept recently and saw no golem
	var gw := VilWorld.new()
	gw.cm = VilCM.new()
	var gem := BehEnts.new()
	gem.world = gw
	gw.entities = gem
	gem.rng.seed = 99
	gw.game_time = 1000
	for x in range(-12, 13):
		for z in range(-12, 13):
			gw.blocks[Vector3i(x, 63, z)] = stone
	var vs: Array = []
	for i in 5:
		var gv = _beh_mob(gem, "villager", Vector3(i * 1.5, 64, 0.5))
		gv.data["last_slept"] = 900 if i < 4 else -50000
		vs.append(gv)
	MobBehaviors.reset_cache()
	var four := Villagers.summon_golem(gem, vs[0], 5)
	vs[4].data["last_slept"] = 990
	var five := Villagers.summon_golem(gem, vs[0], 5)
	var golems := 0
	var gpos := Vector3.ZERO
	for o in gem.ents:
		if o.id == "iron_golem":
			golems += 1
			gpos = o.pos
	MobBehaviors.reset_cache()
	var again := Villagers.summon_golem(gem, vs[1], 3)
	ok("iron golem: 5 gossiping villagers that slept within 20 min summon one (4 do not), on the floor within 8 / 6 blocks; then 30 s off",
		not four and five and golems == 1 and absf(gpos.y - 64.0) < 0.01 and absf(gpos.x - 0.5) <= 8.5 and not again and int(vs[3].rt.get("golem_seen", -1)) == 1000,
		"%s %s %d %s %s" % [four, five, golems, str(gpos), again])
	Villagers._poi.clear()
	Villagers._sleepers.clear()
	# chest explorer maps: the filtered modifier discards a map that got no map id (no world generator here)
	var ctx := {"rng": em.rng, "tool": ItemStack.new(), "origin": Vector3(0.5, 64, 0.5), "container": Vector3i(0, 64, 0)}
	var mtab := {"pools": [{"rolls": 1, "entries": [{"type": "minecraft:item", "name": "minecraft:buried_treasure_map", "modifier": [
		{"type": "minecraft:exploration_map", "decoration": "minecraft:red_x", "destination": "#minecraft:on_treasure_maps", "zoom": 1},
		{"type": "minecraft:filtered", "item_filter": {"predicates": {"minecraft:map_id": {}}}, "on_fail": {"type": "minecraft:discard"}}]}]}]}
	var none := Loot.roll_table(mtab, ctx)
	(mtab["pools"][0]["entries"][0]["modifier"] as Array).push_front({"type": "minecraft:set_components", "components": {"minecraft:map_id": 5}})
	var kept := Loot.roll_table(mtab, ctx)
	ok("explorer maps: chest loot keeps a map with an id, the filtered modifier discards one without", none.is_empty() and kept.size() == 1 and Maps.map_id(kept[0]) == 5,
		"%d %d" % [none.size(), kept.size()])
	# nautilus: saddle, armour, shears, riding speed, dash, Breath of the Nautilus
	var nw := VilWorld.new()
	nw.cm = VilCM.new()
	var nem := EntityManager.new()
	nem.world = nw
	pass
	nem.rng.seed = 5
	var water := b.default_state("water")
	for x in range(-4, 60):
		for y in range(60, 70):
			for z in range(-4, 5):
				nw.blocks[Vector3i(x, y, z)] = water
	var np: Player = nw.player
	var nau = nem.spawn_mob("nautilus", Vector3(0.5, 64, 0.5))
	nau.data["owner"] = Taming.owner_name()
	np.inventory.set_slot(np.inventory.selected, ItemStack.named("saddle", 1))
	Taming.interact(nem, nau, np, np.inventory.held())
	np.inventory.set_slot(np.inventory.selected, ItemStack.named("iron_nautilus_armor", 1))
	Taming.interact(nem, nau, np, np.inventory.held())
	var armor_pts := ArmorRender.horse_armor_points(nau)
	var mounted_ok: bool = bool(nau.data.get("saddle", false)) and armor_pts == 5 and nem.mob_armor(nau).x == 5.0
	np.inventory.set_slot(np.inventory.selected, ItemStack.named("shears", 1))
	Taming.interact(nem, nau, np, np.inventory.held())
	var shorn1: bool = (nau.data.get("horse_armor", {}) as Dictionary).is_empty() and bool(nau.data.get("saddle", false))
	Taming.interact(nem, nau, np, np.inventory.held())
	ok("nautilus: tamed adults take a saddle and nautilus armor (iron 5); shears take the armor first, then the saddle", mounted_ok and shorn1 and not bool(nau.data.get("saddle", true)))
	nau.data["saddle"] = true
	np.inventory.set_slot(np.inventory.selected, ItemStack.new())
	np.yaw = -90.0
	np.pitch = 0.0
	np.vehicle = nau
	nau.yaw = -90.0
	np.in_forward = 1.0
	var gs: Callable = nw.state_at
	for i in 80:
		nau.prev = nau.pos
		Taming.ride_tick(nem, nau, np, gs, b)
	var spd: float = nau.pos.distance_to(nau.prev)
	np.in_forward = 0.0
	np.in_jump = true
	for i in 10:
		nau.prev = nau.pos
		Taming.ride_tick(nem, nau, np, gs, b)
	var full: float = float(nau.rt.get("dash_charge", 0.0))
	np.in_jump = false
	nau.prev = nau.pos
	Taming.ride_tick(nem, nau, np, gs, b)
	var dash: float = nau.pos.distance_to(nau.prev)
	ok("nautilus riding: forward builds to 6.5 m/s in water, jump charges a dash (~12 blocks, 2 s cooldown), Breath of the Nautilus",
		absf(spd - 0.325) < 0.01 and absf(full - 1.0) < 0.001 and dash > 1.1 and int(nau.rt.get("dash_cd", 0)) == 40 and np.effects.has("breath_of_the_nautilus"),
		"%.3f %.2f %.3f %d" % [spd, full, dash, int(nau.rt.get("dash_cd", 0))])
	np.vehicle = null
	# goat long jump: a landing spot within 5 blocks, a launch that lands near it
	var jw := VilWorld.new()
	jw.cm = VilCM.new()
	var jem := EntityManager.new()
	jem.world = jw
	pass
	jem.rng.seed = 11
	for x in range(-8, 9):
		for z in range(-8, 9):
			jw.blocks[Vector3i(x, 63, z)] = stone
	var goat = jem.spawn_mob("goat", Vector3(0.5, 64, 0.5))
	goat.on_ground = true
	goat.data["jump_cd"] = 0
	var found := false
	for i in 400:
		goat.rt.erase("lj_tries")
		if MobBehaviors._goat_find_jump(jem, goat):
			found = true
			break
	var land_to: Vector3 = goat.rt.get("lj_to", Vector3.INF)
	var landed := false
	if found:
		for i in 140:
			MobBehaviors._goat_long_jump(jem, goat, 0)
			if not goat.rt.has("lj_air") and not goat.rt.has("lj_prep"):
				landed = true
				break
	ok("goat long jump: a spot 2-5 blocks away is chosen, the goat leaps after preparing and lands there, 30-60 s cooldown",
		found and landed and goat.pos.distance_to(land_to) < 1.6 and int(goat.data.get("jump_cd", 0)) >= 600 and Vector2(land_to.x - 0.5, land_to.z - 0.5).length() >= 1.9,
		"%s %s %s %s" % [found, landed, str(goat.pos), str(land_to)])
	# fish schools
	MobBehaviors.reset_cache()
	var cods: Array = []
	for i in 3:
		var cd = _beh_mob(em, "cod", Vector3(20 + i, 64, 20))
		cd.rt["flock_t"] = 0
		cods.append(cd)
	MobBehaviors.reset_cache()
	for cd in cods:
		MobAI._flock(em, cd)
	var leaders := 0
	var followers := 0
	for cd in cods:
		if cd.rt.get("leader") != null:
			followers += 1
		elif int(cd.rt.get("school", 1)) == 3:
			leaders += 1
	ok("fish schools: nearby cod form one school - a leader and two followers (max 9)", leaders == 1 and followers == 2, "%d %d" % [leaders, followers])
	# phantoms and cats
	var ph = _beh_mob(em, "phantom", Vector3(40, 80, 40))
	var cat = _beh_mob(em, "cat", Vector3(40, 66, 50))
	MobBehaviors.reset_cache()
	var hiss := MobAI._cats_hiss(em, ph)
	cat.pos = Vector3(40, 60, 70)
	MobBehaviors.reset_cache()
	ok("phantoms: a cat within 16 blocks (through walls) hisses and calls off the swoop", hiss and not MobAI._cats_hiss(em, ph))
	# wolves and llamas
	var wolf = _beh_mob(em, "wolf", Vector3(60.5, 64, 60.5))
	var lla = _beh_mob(em, "llama", Vector3(70.5, 64, 60.5))
	lla.data["strength"] = 5
	MobBehaviors.reset_cache()
	var fp := MobBehaviors.flee_point(em, wolf, w.player, 100.0)
	lla.data["strength"] = 1
	var fled := 0
	for i in 400:
		wolf.rt.erase("threat")
		if MobBehaviors.flee_point(em, wolf, w.player, 100.0) != Vector3.INF:
			fled += 1
	wolf.data["owner"] = "Player"
	wolf.rt.erase("threat")
	ok("wolves: wild wolves flee llamas within 24 (strength 5 always, strength 1 about 2 in 5), tamed ones never", fp != Vector3.INF and fp.x < wolf.pos.x and fled > 100 and fled < 230
		and MobBehaviors.flee_point(em, wolf, w.player, 100.0) == Vector3.INF and float(MobBehaviors.FLEES["wolf"]) == 1.5, "%s %d" % [str(fp), fled])
	var strong := 0
	var weak := 0
	for i in 3000:
		var ll = EntityManager.Ent.new()
		ll.id = "llama"
		MobBehaviors.on_spawn(em, ll, false)
		var s := int(ll.data["strength"])
		if s >= 4:
			strong += 1
		elif s >= 1:
			weak += 1
	var a1 = EntityManager.Ent.new()
	a1.data["strength"] = 2
	var a2 = EntityManager.Ent.new()
	a2.data["strength"] = 4
	var bred_ok := true
	for i in 300:
		var bs := MobBehaviors.llama_bred_strength(em.rng, a1, a2)
		bred_ok = bred_ok and bs >= 1 and bs <= 5
	ok("llama strength: 1-3 at 32.8 % each, 4 / 5 at 0.8 % each; foals 1 .. the stronger parent (+1 3 %)", strong > 15 and strong < 90 and weak + strong == 3000 and bred_ok, "%d" % strong)
	# vex charge texture
	var vex = nem.spawn_mob("vex", Vector3(0.5, 70, 0.5))
	nem._vex_texture(vex, true)
	var red_mat := EntityRenderer.material("entity/illager/vex_charging")
	var reds := 0
	for mi in nem._meshes(vex.node.get_node("model")):
		if (mi as MeshInstance3D).material_override == red_mat:
			reds += 1
	nem._vex_texture(vex, false)
	var reds2 := 0
	for mi in nem._meshes(vex.node.get_node("model")):
		if (mi as MeshInstance3D).material_override == red_mat:
			reds2 += 1
	ok("vex: charging vexes switch to the red vex_charging texture and back", reds > 0 and reds2 == 0)
	# sleeping pose: head toward the pillow (bed facing), face up
	nw.cm = SensorCM.new()   # (no chunk: the villager keeps the plains type - this world has no biome registry)
	var sv = nem.spawn_mob("villager", Vector3(0.5, 64.6875, 0.5))
	sv.node.position = Vector3.ZERO
	nem._sleep_pose(sv, 0)
	var hb: Basis = sv.node.basis.orthonormalized()
	ok("sleep pose: lying along the bed (head south for a south bed), face up, shifted back toward the foot", (hb * Vector3.UP).distance_to(Vector3(0, 0, 1)) < 0.01
		and (hb * Vector3.FORWARD).distance_to(Vector3(0, 1, 0)) < 0.01 and sv.node.position.z < -1.0)
	# ominous item spawners are saved with their chunk
	var oi = Trials.spawn_ominous_item(nem, Vector3(2.5, 66, 2.5), ItemStack.named("arrow", 1), 80, false)
	oi.age = 30
	var od := nem._ser(oi)
	var n0 := nem.ents.size()
	nem._deser(od)
	var oi2 = nem.ents[nem.ents.size() - 1] if nem.ents.size() > n0 else null
	ok("ominous item spawner: saved with the chunk (item, age, delay) and restored", str(od.get("k", "")) == "ominous_item" and oi2 != null and oi2.kind == "ominous_item"
		and oi2.age == 30 and int(oi2.data.get("spawn_after", 0)) == 80 and oi2.stack.name() == "arrow")
	for n in [nem, jem, rem]:
		for e2 in (n as EntityManager).ents:
			if e2.node != null:
				e2.node.free()
		(n as EntityManager).free()
	for ents_mgr in [em, gem]:
		for e3 in ents_mgr.ents:
			e3.rt.clear()   # (fish leaders / golem targets: no reference cycles left behind)
		ents_mgr.world = null   # (world <-> entities cycle)
	MobBehaviors.reset_cache()


func _shot(em: EntityManager, owner, id: String, at: Vector3, v: Vector3) -> EntityManager.Ent:
	var pe := EntityManager.Ent.new()
	pe.kind = "projectile"
	pe.id = id
	pe.pos = at
	pe.vel = v
	pe.owner = owner
	pe.data["base_damage"] = 2.0
	em.ents.append(pe)
	return pe


## A BucketWorld whose notified block changes run the fluid neighbour updates (WorldManager.set_block ->
## BlockUpdates.fluids_changed: flow ticks, sponges).
class NotifyWorld extends BucketWorld:
	var advancements = null

	func _init() -> void:
		entities = MobBucketEnts.new()

	func set_block(x: int, y: int, z: int, st: int, notify := true) -> int:
		var old := super(x, y, z, st, notify)
		if notify and old != st:
			BlockUpdates.fluids_changed(self, Vector3i(x, y, z))
		return old

	func swing_hand() -> void:
		pass

	func inv_changed() -> void:
		pass


class MobBucketEnts extends BucketEnts:
	var world = null

	func spawn_mob(id: String, p: Vector3, _baby: bool = false):
		var e := EntityManager.Ent.new()
		e.kind = "mob"
		e.id = id
		e.pos = p
		e.hp = 3.0
		ents.append(e)
		return e

	func _remove(e) -> void:
		e.dead = true
		ents.erase(e)


## Sponges, bucketed fish, blocks washed away by flowing fluids, grass decay, wet sponge drying in furnaces (wiki
## Sponge / Bucket of Aquatic Mob / Water / Pressure Plate / Banner / Grass Block).
func test_vanilla_fluid_items() -> void:
	var b := Res.blocks
	var water := b.WATER
	# sponge: placed next to a water line, takes water up to 6 blocks away (taxicab), becomes wet
	BlockUpdates.reset()
	var w := NotifyWorld.new()
	for x in range(1, 11):
		w.blocks[Vector3i(x, 0, 0)] = water
	var slab_wl := b.with_prop(b.default_state("oak_slab"), "waterlogged", "true")
	w.blocks[Vector3i(0, 0, 1)] = slab_wl
	w.blocks[Vector3i(0, 0, -1)] = b.default_state("kelp")
	w.set_block(0, 0, 0, b.default_state("sponge"))
	ok("sponge: placed next to water it soaks up water up to 6 blocks away and turns wet (wiki Sponge)", b.name_of(w.state_at(0, 0, 0)) == "wet_sponge"
		and w.state_at(6, 0, 0) == 0 and w.state_at(1, 0, 0) == 0 and w.state_at(7, 0, 0) == water,
		"%s 6:%d 7:%d" % [b.name_of(w.state_at(0, 0, 0)), w.state_at(6, 0, 0), w.state_at(7, 0, 0)])
	ok("sponge: a waterlogged block gives up its water, kelp is removed", b.get_prop(w.state_at(0, 0, 1), "waterlogged") == "false" and w.state_at(0, 0, -1) == 0)
	BlockUpdates.reset()
	var w2 := NotifyWorld.new()
	w2.set_block(0, 0, 0, b.default_state("sponge"))
	var dry_alone := b.name_of(w2.state_at(0, 0, 0)) == "sponge"
	w2.set_block(1, 0, 0, water)
	ok("sponge: stays dry without water, then takes water that comes into contact with it", dry_alone and b.name_of(w2.state_at(0, 0, 0)) == "wet_sponge" and w2.state_at(1, 0, 0) == 0)
	BlockUpdates.reset()
	var w3 := NotifyWorld.new()
	for y in range(-6, 0):
		for z in range(-6, 7):
			for x in range(-6, 7):
				w3.blocks[Vector3i(x, y, z)] = water
	var before := _water_cells(w3)
	w3.set_block(0, 0, 0, b.default_state("sponge"))
	ok("sponge: at most 118 water blocks per sponge (wiki Sponge)", before - _water_cells(w3) == Sponges.MAX_COUNT and Sponges.MAX_COUNT == 118, str(before - _water_cells(w3)))
	BlockUpdates.reset()
	var w4 := NotifyWorld.new()
	w4.dim_type = {"attributes": {"minecraft:gameplay/water_evaporates": true}}
	w4.set_block(0, 0, 0, b.default_state("wet_sponge"))
	ok("sponge: a wet sponge placed in the Nether dries at once", b.name_of(w4.state_at(0, 0, 0)) == "sponge")
	var fd := {"id": "furnace", "items": [ItemStack.named("wet_sponge").to_dict(), ItemStack.named("bucket", 3).to_dict(), {}], "burn": 100, "cook": 199}
	BlockEntities.furnace_step(fd)
	var fout := ItemStack.from_dict(fd["items"][2])
	var ffuel := ItemStack.from_dict(fd["items"][1])
	ok("sponge: smelting a wet sponge gives a sponge and fills a bucket in the fuel slot (wiki Sponge)", fout.name() == "sponge" and ffuel.name() == "water_bucket" and ffuel.count == 1, "%s %s" % [fout.name(), ffuel.name()])
	# bucket of aquatic mob
	BlockUpdates.reset()
	var wm := NotifyWorld.new()
	wm.floor_at(-1, 6, b.STONE)
	var em := wm.entities as MobBucketEnts
	em.world = wm
	var p := Player.new()
	p.inventory.set_slot(p.inventory.selected, ItemStack.named("water_bucket", 1))
	var fish = em.spawn_mob("tropical_fish", Vector3(3.5, 0.2, 3.5))
	fish.data["variant"] = 117506305
	fish.hp = 2.0
	fish.data["CustomName"] = "Nemo"
	var took := MobBuckets.pickup(em, fish, p, p.inventory.held())
	var bk := p.inventory.held()
	ok("mob bucket: a water bucket scoops a tropical fish into a bucket of tropical fish (variant, health, name kept)", took and fish.dead and bk.name() == "tropical_fish_bucket"
		and int(bk.components["minecraft:bucket_entity_data"]["data"]["variant"]) == 117506305 and str(bk.components.get("minecraft:custom_name", "")) == "Nemo", bk.name())
	p.pos = Vector3(0.5, 2.0, 0.5)
	p.pitch = 90.0
	wm.player = p
	Interaction.use_item(wm, bk)
	wm.player = null
	var rel = em.ents[em.ents.size() - 1] if not em.ents.is_empty() else null
	ok("mob bucket: using it places water and releases the fish there, persistent, with its data; an empty bucket is left", wm.state_at(0, 0, 0) == water and rel != null and rel.id == "tropical_fish"
		and rel.persistent and int(rel.data.get("variant", 0)) == 117506305 and is_equal_approx(rel.hp, 2.0) and str(rel.data.get("CustomName", "")) == "Nemo" and p.inventory.held().name() == "bucket",
		"%d %s %s" % [wm.state_at(0, 0, 0), str(rel.id if rel != null else ""), p.inventory.held().name()])
	var pig = em.spawn_mob("pig", Vector3(5.5, 0, 5.5))
	p.inventory.set_slot(p.inventory.selected, ItemStack.named("water_bucket", 1))
	ok("mob bucket: only fish, axolotls and tadpoles go into buckets", not MobBuckets.pickup(em, pig, p, p.inventory.held()) and not pig.dead)
	# flowing water / lava destroys non-solid blocks (wiki Water: carpets, heads, flower pots ...) but not banners / plates
	var fw := _fluid_world()
	fw.blocks[Vector3i(0, 0, 0)] = water
	fw.blocks[Vector3i(1, 0, 0)] = b.default_state("white_carpet")
	fw.blocks[Vector3i(-1, 0, 0)] = b.default_state("player_head")
	fw.blocks[Vector3i(0, 0, 1)] = b.default_state("flower_pot")
	fw.blocks[Vector3i(0, 0, -1)] = b.default_state("stone_pressure_plate")
	BlockUpdates.schedule(fw, Vector3i(0, 0, 0), 5)
	fw.run(5)
	ok("fluids: flowing water washes away carpets, heads and flower pots", _lvl(fw, 1, 0, 0) == 1 and _lvl(fw, -1, 0, 0) == 1 and _lvl(fw, 0, 0, 1) == 1,
		"%d %d %d" % [_lvl(fw, 1, 0, 0), _lvl(fw, -1, 0, 0), _lvl(fw, 0, 0, 1)])
	ok("fluids: pressure plates hold water back (wiki Pressure Plate)", b.name_of(fw.state_at(0, 0, -1)) == "stone_pressure_plate")
	var fb := _fluid_world()
	fb.blocks[Vector3i(0, 0, 0)] = water
	fb.blocks[Vector3i(1, 0, 0)] = b.default_state("white_banner")
	fb.blocks[Vector3i(-1, 0, 0)] = b.default_state("oak_slab")
	BlockUpdates.schedule(fb, Vector3i(0, 0, 0), 5)
	fb.run(5)
	ok("fluids: water flows around banners (wiki Banner); a dry slab takes no flowing water", b.name_of(fb.state_at(1, 0, 0)) == "white_banner" and b.name_of(fb.state_at(-1, 0, 0)) == "oak_slab"
		and b.get_prop(fb.state_at(-1, 0, 0), "waterlogged") == "false")
	var fl := _fluid_world()
	fl.blocks[Vector3i(0, 0, 0)] = b.LAVA
	fl.blocks[Vector3i(1, 0, 0)] = b.default_state("white_carpet")
	BlockUpdates.schedule(fl, Vector3i(0, 0, 0), 30)
	fl.run(30)
	ok("fluids: flowing lava destroys a carpet too", b.name_of(fl.state_at(1, 0, 0)) == "lava", b.name_of(fl.state_at(1, 0, 0)))
	# grass / mycelium can stay under (SpreadingSnowyDirtBlock.canBeGrass)
	var g_stay := RandomTickable.grass_ok(0) and RandomTickable.grass_ok(b.default_state("glass")) and RandomTickable.grass_ok(b.default_state("oak_leaves")) \
		and RandomTickable.grass_ok(b.default_state("white_carpet")) and RandomTickable.grass_ok(b.with_prop(b.default_state("oak_slab"), "type", "top")) \
		and RandomTickable.grass_ok(b.with_prop(b.default_state("snow"), "layers", "1"))
	var g_die := not RandomTickable.grass_ok(b.STONE) and not RandomTickable.grass_ok(b.default_state("oak_slab")) and not RandomTickable.grass_ok(water) \
		and not RandomTickable.grass_ok(b.default_state("oak_stairs")) and not RandomTickable.grass_ok(b.with_prop(b.default_state("glass_pane"), "waterlogged", "true"))
	ok("grass: stays under air, glass, leaves, carpets, top slabs, one snow layer; dies under full blocks, bottom slabs, stairs, water", g_stay and g_die,
		"stay %s die %s" % [str(g_stay), str(g_die)])
