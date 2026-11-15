## Features — data-driven decoration from the installed 26.3 worldgen/placed_feature + worldgen/feature JSON.
## Per biome feature steps, Java decoration/feature seeding (setDecorationSeed/setFeatureSeed with Xoroshiro),
## depth-first placement-modifier chains (count, in_square, rarity_filter, height_range, heightmap, biome,
## offset, block_predicate_filter, surface_water_depth_filter, noise(_threshold|_based)_count, environment_scan,
## random_offset, count_on_every_layer, surface_relative_threshold_filter, fixed_placement), int/height/state
## providers, block predicates, and feature types: ore, scattered_ore, tree (trunk/foliage placers, partly
## approximated), simple_block, *selectors, sequence, block_column, disk, spring_feature, lake, block_pile,
## vegetation_patch, monster_room, fallen_tree, huge mushrooms, multiface_growth, geode (approx), bamboo.
## Determinism: features of an ORIGIN chunk read only pristine (undecorated) terrain of its 3x3 and produce a
## write list; every centre chunk applies the writes of its 3x3 origins in a fixed global order -> seamless,
## load-order independent. Unknown feature types are skipped and counted in `unsupported`.
## Contract: setup() on main thread; compute(origin, region) -> PackedInt32Array; apply(centre, nine).
class_name Features
extends RefCounted

const STEPS := 11
const W_FORCE := 0
const W_REPLACEABLE := 1
const W_AIR := 2
# Ore writes: W_ORE | (rule << 2). Java's OreFeature runs its target rule test against the block present when the
# feature runs; here every origin decides on pristine terrain, so the decorate merge re-tests the cell against the
# rule (another origin's moss / plant / structure block in that cell keeps it; a neighbour's stone-type blob still
# takes the ore when the rule accepts it, as in Java). ore_mask: per state, bit r = passes interned ore rule r.
const W_ORE := 3
static var ore_rule_index := {}
static var ore_mask := PackedInt32Array()
static var _ore_m := Mutex.new()

var gen: VanillaGenerator
var blocks: BlockRegistry
var placed: Dictionary = {}          # name -> compiled placed feature
var configured: Dictionary = {}      # name -> compiled configured feature
var providers: Dictionary = {}
var biome_steps: Array = []          # per biome: Array[11] of Array of names
var step_index: Array = []           # per step: Dictionary name -> index
var feature_biomes: Dictionary = {}  # placed name -> Dictionary(biome id -> true)
var unsupported: Dictionary = {}
var simplex_info: SimplexNoise
var tag_cache: Dictionary = {}
var profile: Dictionary = {}   # placed feature -> usec (when enabled)
var profiling := false
var legacy_region := false   # verification: original overlay/region access path
var native_engine := true    # run supported placed features in RecraftNative.fx_run (features_native.gd)
var bounds: Array = []       # verification: [name, writes size before it] per placed feature of the last compute
var _temps := PackedFloat64Array()   # biome temperatures (native decorate)
var trace_names := false     # diagnostics: print each placed feature / structure step before running it
# neighbours' surface structures are visible to this origin's later features (Structures.place_neighbour_view);
# RC_NO_NSTRUCT=1 turns it off for A/B checks
var neighbour_structures := not OS.has_environment("RC_NO_NSTRUCT")
var _m := Mutex.new()
# diagnostics (--structcheck): every structure write of every origin [x, y, z, state]*, checked against the finished world
static var struct_record := false
static var struct_writes := PackedInt32Array()
static var _srm := Mutex.new()


class SimplexNoise:
	var p := PackedInt32Array()
	const F2 := 0.3660254037844386
	const G2 := 0.21132486540518713

	func _init(r) -> void:
		r.next_double()
		r.next_double()
		r.next_double()
		p.resize(256)
		for i in 256:
			p[i] = i
		for i in 256:
			var j: int = r.next_int_bound(256 - i)
			var k := p[i]
			p[i] = p[j + i]
			p[j + i] = k

	func _corner(g: int, x: float, y: float) -> float:
		var h := 0.5 - x * x - y * y
		if h < 0.0:
			return 0.0
		h *= h
		return h * h * (MCNoise.GX[g] * x + MCNoise.GY[g] * y)

	func value(d: float, e: float) -> float:
		var h := (d + e) * F2
		var i := floori(d + h)
		var j := floori(e + h)
		var k := (i + j) * G2
		var n := d - (i - k)
		var o := e - (j - k)
		var pp := 1 if n > o else 0
		var qq := 0 if n > o else 1
		var r := n - pp + G2
		var s := o - qq + G2
		var t := n - 1.0 + 2.0 * G2
		var u := o - 1.0 + 2.0 * G2
		var v := i & 255
		var w := j & 255
		var x := p[(v + p[w & 255]) & 255] % 12
		var y := p[(v + pp + p[(w + qq) & 255]) & 255] % 12
		var z := p[(v + 1 + p[(w + 1) & 255]) & 255] % 12
		return 70.0 * (_corner(x, n, o) + _corner(y, r, s) + _corner(z, t, u))


func _init(g: VanillaGenerator) -> void:
	gen = g
	blocks = g.blocks


## Sets BlockRegistry.F_TREE_REPL on air and #replaceable_by_trees states (water included: swamp / mangrove trees grow
## in it; snow layers are not in it, so a snow pile blocks a tree). Without the tag (placeholder mode): replaceable or
## leaves, no liquid (the earlier rule).
func _mark_tree_replaceable() -> void:
	var tag := Tags.blocks("#minecraft:replaceable_by_trees") if Res.mode == "vanilla" else {}
	var fl := blocks.st_flags
	for st in fl.size():
		var v := fl[st] & ~BlockRegistry.F_TREE_REPL
		var ok := false
		if tag.is_empty():
			ok = (v & (BlockRegistry.F_REPLACEABLE | BlockRegistry.F_LEAVES)) != 0 and (v & BlockRegistry.F_LIQUID) == 0
		else:
			var nm := blocks.name_of(st) if st > 0 else "air"
			ok = nm == "air" or nm == "cave_air" or nm == "void_air" or tag.has(nm)
		fl[st] = v | (BlockRegistry.F_TREE_REPL if ok else 0)
	blocks.st_flags = fl


func _json(kind: String, name: String):
	return gen.source.call("data/minecraft/worldgen/%s/%s.json" % [kind, name.trim_prefix("minecraft:")])


func setup() -> void:
	if OS.get_environment("RC_GD_FEATURES") != "":
		native_engine = false   # (dev: GDScript feature path only)
	_mark_tree_replaceable()
	simplex_info = SimplexNoise.new(RandomSources.LegacyRandom.new(2345))
	for s in STEPS:
		step_index.append({})
	for bi in gen.biomes.names.size():
		var d = gen.biomes.data[bi]
		var steps: Array = []
		var fl = d.get("features", []) if d is Dictionary else []
		for s in STEPS:
			var lst: Array = []
			if fl is Array and s < fl.size() and fl[s] is Array:
				for f in fl[s]:
					var nm := str(f)
					lst.append(nm)
					if not (step_index[s] as Dictionary).has(nm):
						step_index[s][nm] = (step_index[s] as Dictionary).size()
					if not feature_biomes.has(nm):
						feature_biomes[nm] = {}
					feature_biomes[nm][bi] = true
					_placed(nm)
			steps.append(lst)
		biome_steps.append(steps)
	_sort_features(_possible_biomes())


## Biomes in the dimension's BiomeSource.possibleBiomes() order (the feature sorter's input order): multi-noise ->
## first appearance in the parameter list (Climate, Java OverworldBiomeBuilder / nether preset), the End ->
## TheEndBiomeSource's five, a single biome -> itself; else registry order.
func _possible_biomes() -> Array:
	var out: Array = []
	var seen := {}
	var src: PackedStringArray = PackedStringArray()
	if gen.get("single_biome") != null and int(gen.get("single_biome")) >= 0:
		src = PackedStringArray([gen.biomes.names[int(gen.single_biome)]])
	elif bool(gen.get("end_biomes")):
		src = PackedStringArray(["the_end", "end_highlands", "end_midlands", "small_end_islands", "end_barrens"])
	elif gen.get("climate") != null:
		src = (gen.climate as Climate).names
	for nm in src:
		var bi: int = gen.biomes.id(nm)
		if bi >= 0 and not seen.has(bi):
			seen[bi] = true
			out.append(bi)
	if out.is_empty():
		for bi in gen.biomes.names.size():
			out.append(bi)
	return out


## Java FeatureSorter.buildFeaturesPerStep: every biome's feature list (all steps flattened) adds an edge from each
## feature to the next; features are numbered by first appearance (biomes in possibleBiomes order); a depth-first
## search over the nodes in (step, number) order, successors in the same order, gives the reversed post-order. Its
## per-step positions are the feature indices (setFeatureSeed(decoration seed, index, step)) and the placing order.
func _sort_features(order: Array) -> void:
	var num := {}   # feature name -> first-appearance number (shared by all steps)
	var edges := {}   # node key (step << 20 | number) -> {successor key: true}
	var names_of := {}   # node key -> feature name
	for bi in order:
		if bi >= biome_steps.size():
			continue
		var flat: Array = []
		for s in STEPS:
			for nm in biome_steps[bi][s]:
				if not num.has(nm):
					num[nm] = num.size()
				var k: int = (s << 20) | int(num[nm])
				names_of[k] = nm
				flat.append(k)
		for i in flat.size():
			if not edges.has(flat[i]):
				edges[flat[i]] = {}
			if i < flat.size() - 1:
				edges[flat[i]][flat[i + 1]] = true
	var keys: Array = edges.keys()
	keys.sort()
	var visited := {}
	var post: Array = []
	for start in keys:
		if visited.has(start):
			continue
		# iterative DFS: stack of [node, sorted successors, next successor index]
		var in_progress := {start: true}
		var succ0: Array = (edges[start] as Dictionary).keys()
		succ0.sort()
		var stack: Array = [[start, succ0, 0]]
		while not stack.is_empty():
			var top: Array = stack[stack.size() - 1]
			var lst: Array = top[1]
			if int(top[2]) < lst.size():
				var nx = lst[int(top[2])]
				top[2] = int(top[2]) + 1
				if visited.has(nx) or in_progress.has(nx):
					continue   # (a cycle: vanilla data has none)
				in_progress[nx] = true
				var sn: Array = (edges.get(nx, {}) as Dictionary).keys()
				sn.sort()
				stack.append([nx, sn, 0])
			else:
				stack.pop_back()
				in_progress.erase(top[0])
				visited[top[0]] = true
				post.append(top[0])
	post.reverse()
	var idx: Array = []
	for s in STEPS:
		idx.append({})
	for k in post:
		var s2: int = int(k) >> 20
		if s2 < STEPS:
			idx[s2][names_of[k]] = (idx[s2] as Dictionary).size()
	# features of biomes outside the biome source (unreachable) keep a number after the sorted ones
	for s in STEPS:
		for nm in step_index[s]:
			if not (idx[s] as Dictionary).has(nm):
				idx[s][nm] = (idx[s] as Dictionary).size()
	step_index = idx


# ------------------------------------------------------------------ compilation

func _placed(v) -> Dictionary:
	if v is String:
		if placed.has(v):
			return placed[v]
		var j = _json("placed_feature", v)
		var r := _placed(j) if j != null else {"cf": {"t": "none"}, "mods": []}
		r["name"] = v
		placed[v] = r
		return r
	if v is Dictionary:
		var mods: Array = []
		for m in v.get("placement", []):
			mods.append(_mod(m))
		return {"cf": _cf(v.get("feature", {})), "mods": mods, "name": ""}
	return {"cf": {"t": "none"}, "mods": []}


func _cf(v) -> Dictionary:
	if v is String:
		if configured.has(v):
			return configured[v]
		configured[v] = {"t": "none"}
		var j = _json("feature", v)
		if j == null:
			j = _json("configured_feature", v)
		var r := _cf(j) if j != null else {"t": "none"}
		configured[v] = r
		return r
	if not (v is Dictionary):
		return {"t": "none"}
	var c: Dictionary = v.get("config", v)
	var t := str(v.get("type", "")).trim_prefix("minecraft:")
	var out := {"t": t, "raw": c}
	match t:
		"ore", "scattered_ore":
			var targets: Array = []
			for tg in c.get("targets", []):
				var rt0 := _rule_test(tg.get("target", {}))
				targets.append([rt0, _state(tg.get("state", "minecraft:stone")), _ore_mode(rt0)])
			out["targets"] = targets
			out["size"] = int(c.get("size", 8))
			out["discard"] = float(c.get("discard_chance_on_air_exposure", 0.0))
		"simple_block":
			out["prov"] = _prov(c.get("to_place", {}))
			out["schedule"] = bool(c.get("schedule_tick", false))
		"random_selector":
			var fs: Array = []
			for e in c.get("features", []):
				fs.append([float(e.get("chance", 0.0)), _placed(e.get("feature", {}))])
			out["fs"] = fs
			out["default"] = _placed(c.get("default", {}))
		"weighted_random_selector":
			var ws: Array = []
			for e in c.get("features", []):
				ws.append([int(e.get("weight", 1)), _placed(e.get("data", {}))])
			out["ws"] = ws
		"simple_random_selector":
			var ss: Array = []
			var feats = c.get("features", [])
			if feats is Array:
				for e in feats:
					ss.append(_placed(e))
			out["ss"] = ss
		"random_boolean_selector":
			out["a"] = _placed(c.get("feature_true", {}))
			out["b"] = _placed(c.get("feature_false", {}))
		"sequence":
			var sq: Array = []
			for e in c.get("features", []):
				sq.append(_placed(e))
			out["seq"] = sq
		"block_column":
			var layers: Array = []
			for l in c.get("layers", []):
				layers.append([l.get("height", 1), _prov(l.get("provider", {}))])
			out["layers"] = layers
			out["dir"] = str(c.get("direction", "up"))
			out["allowed"] = _pred(c.get("allowed_placement", {"type": "minecraft:true"}))
			out["tip"] = bool(c.get("prioritize_tip", false))
		"disk":
			out["prov"] = _prov(c.get("state_provider", {}))
			out["target"] = _pred(c.get("target", {}))
			out["radius"] = c.get("radius", 2)
			out["half"] = int(c.get("half_height", 1))
		"spring_feature":
			out["state"] = _state(c.get("state", "minecraft:water"))
			var vb := {}
			var vbl = c.get("valid_blocks", [])
			if vbl is String:
				vbl = [vbl]
			for b in vbl:
				var bid := blocks.block_id(str(b))
				if bid >= 0:
					vb[bid] = true
			out["valid"] = vb
			out["rock"] = int(c.get("rock_count", 4))
			out["hole"] = int(c.get("hole_count", 1))
			out["below"] = bool(c.get("requires_block_below", true))
		"lake":
			out["fluid"] = _prov(c.get("fluid", {}))
			out["barrier"] = _prov(c.get("barrier", {}))
			# 26.x predicates (Java LakeFeature.Configuration)
			out["repl_af"] = _pred(c.get("can_replace_with_air_or_fluid", {"type": "minecraft:true"}))
			out["repl_bar"] = _pred(c.get("can_replace_with_barrier", {"type": "minecraft:true"}))
		"tree":
			out["trunk"] = _prov(c.get("trunk_provider", {}))
			out["foliage"] = _prov(c.get("foliage_provider", {}))
			out["soil"] = _prov(c.get("below_trunk_provider", c.get("dirt_provider", {"id": "minecraft:dirt"})))
			out["tp"] = c.get("trunk_placer", {})
			out["fp"] = c.get("foliage_placer", {})
			out["ms"] = c.get("minimum_size", {})
			out["iv"] = bool(c.get("ignore_vines", false))
			# UpwardsBranchingTrunkPlacer.validTreePos: also through its can_grow_through blocks
			var cgt = (out["tp"] as Dictionary).get("can_grow_through", null)
			if cgt != null:
				out["tgrow"] = _block_set(cgt)
			# MangroveRootPlacer (the only root placer type in 26.3)
			var rpl = c.get("root_placer", null)
			if rpl is Dictionary and str(rpl.get("type", "")).trim_prefix("minecraft:") == "mangrove_root_placer":
				var mrp: Dictionary = rpl.get("mangrove_root_placement", {})
				var rp := {"off": rpl.get("trunk_offset_y", 0), "prov": _prov(rpl.get("root_provider", {})),
					"grow": _block_set(mrp.get("can_grow_through", [])), "muddy_in": _block_set(mrp.get("muddy_roots_in", [])),
					"muddy": _prov(mrp.get("muddy_roots_provider", {})), "len": int(mrp.get("max_root_length", 15)),
					"width": int(mrp.get("max_root_width", 8)), "skew": float(mrp.get("random_skew_chance", 0.2)), "above_p": -1.0}
				var arp = rpl.get("above_root_placement", null)
				if arp is Dictionary:
					rp["above_p"] = float(arp.get("above_root_placement_chance", 0.0))
					rp["above"] = _prov(arp.get("above_root_provider", {}))
				out["rp"] = rp
			# decorators: providers / nested features resolved now (worker threads only read them later)
			var decs: Array = []
			for d in c.get("decorators", []):
				if not (d is Dictionary):
					continue
				var dd: Dictionary = (d as Dictionary).duplicate()
				for pk in ["provider", "block_provider", "block_state_provider"]:
					if dd.has(pk):
						dd["_prov"] = _prov(dd[pk])
				if str(dd.get("type", "")).ends_with("pale_moss"):
					dd["_patch"] = _cf("minecraft:pale_moss_patch")
				decs.append(dd)
			out["decorators"] = decs
		"fallen_tree":
			out["trunk"] = _prov(c.get("trunk_provider", {}))
			out["len"] = c.get("log_length", 4)
			for dk in ["stump_decorators", "log_decorators"]:
				var fdecs: Array = []
				for d2 in c.get(dk, []):
					if not (d2 is Dictionary):
						continue
					var dd2: Dictionary = (d2 as Dictionary).duplicate()
					for pk2 in ["provider", "block_provider", "block_state_provider"]:
						if dd2.has(pk2):
							dd2["_prov"] = _prov(dd2[pk2])
					fdecs.append(dd2)
				out[dk] = fdecs
		"block_pile":
			out["prov"] = _prov(c.get("state_provider", {}))
		"vegetation_patch", "waterlogged_vegetation_patch":
			out["ground"] = _prov(c.get("ground_state", {}))
			out["veg"] = _placed(c.get("vegetation_feature", {}))
			out["replace_tag"] = str(c.get("replaceable", "#minecraft:moss_replaceable"))
			out["radius"] = c.get("xz_radius", 3)
			out["chance"] = float(c.get("vegetation_chance", 0.1))
			out["depth"] = c.get("depth", 1)
		"huge_brown_mushroom", "huge_red_mushroom":
			out["cap"] = _prov(c.get("cap_provider", {}))
			out["stem"] = _prov(c.get("stem_provider", {}))
			out["radius"] = int(c.get("foliage_radius", 2))
		"multiface_growth":
			out["block"] = _state(c.get("block", "minecraft:glow_lichen"))
		"geode":
			var bs: Dictionary = c.get("blocks", {})
			out["filling"] = _prov(bs.get("filling_provider", {"id": "minecraft:air"}))
			out["inner"] = _prov(bs.get("inner_layer_provider", {"id": "minecraft:amethyst_block"}))
			out["middle"] = _prov(bs.get("middle_layer_provider", {"id": "minecraft:calcite"}))
			out["outer"] = _prov(bs.get("outer_layer_provider", {"id": "minecraft:smooth_basalt"}))
		"monster_room", "freeze_top_layer", "bamboo":
			pass
		_:
			if not FeaturesCave.compile(self, t, c, out):
				FeaturesExt.compile(self, t, c, out)
	return out


func _state(v) -> int:
	if v is String:
		var s := blocks.parse_state(v)
		return s if s >= 0 else 0
	if v is Dictionary:
		var nm := str(v.get("id", v.get("Name", "minecraft:air")))
		var s2 := blocks.state_of(nm, v.get("properties", v.get("Properties", {})))
		return s2 if s2 >= 0 else 0
	return 0


## Block state providers.
func _prov(v) -> Dictionary:
	if v is String:
		if providers.has(v):
			return providers[v]
		var j = _json("block_state_provider", v)
		var r: Dictionary
		if j != null:
			r = _prov(j)
		else:
			r = {"t": "simple", "s": _state(v)}
		providers[v] = r
		return r
	if not (v is Dictionary):
		return {"t": "simple", "s": 0}
	if not v.has("type") and (v.has("id") or v.has("Name")):
		return {"t": "simple", "s": _state(v)}
	var t := str(v.get("type", "")).trim_prefix("minecraft:")
	match t:
		"simple_state_provider":
			return {"t": "simple", "s": _state(v.get("state", {}))}
		"weighted_state_provider", "weighted":
			var ents: Array = []
			for e in v.get("entries", []):
				ents.append([int(e.get("weight", 1)), _prov(e.get("data", {}))])
			return {"t": "weighted", "e": ents}
		"rule_based", "rule_based_state_provider":
			var rules: Array = []
			for r in v.get("rules", []):
				rules.append([_pred(r.get("if_true", {})), _prov(r.get("then", {}))])
			return {"t": "rule", "rules": rules, "fallback": _prov(v.get("fallback", {})) if v.has("fallback") else {}}
		"noise_threshold_provider", "noise_provider", "dual_noise_provider", "noise_threshold":
			var states: Array = []
			for s in v.get("states", []):
				states.append(_state(s))
			var dflt := _state(v.get("default_state", {})) if v.has("default_state") else -1
			var low: Array = []
			for s in v.get("low_states", []):
				low.append(_state(s))
			var high: Array = []
			for s in v.get("high_states", []):
				high.append(_state(s))
			var seed := int(v.get("seed", 0))
			var np: Dictionary = v.get("noise", {"firstOctave": 0, "amplitudes": [1.0]})
			var lr := RandomSources.LegacyRandom.new(seed)
			return {"t": t.replace("_state_provider", ""), "states": states, "default": dflt, "low": low, "high": high,
				"noise": MCNoise.Normal.from_params(_legacy_pf(lr), np), "scale": float(v.get("scale", 1.0)),
				"threshold": float(v.get("threshold", 0.0)), "high_chance": float(v.get("high_chance", 0.5))}
		"randomized_int_state_provider", "randomized_int":
			# 26.x id "minecraft:randomized_int" (kelp tips: kelp[age=20..23]); unmatched it fell through to a stateless
			# simple provider = air, which left an air pocket on top of every generated kelp column
			return {"t": "rint", "src": _prov(v.get("source", {})), "prop": str(v.get("property", "")), "vals": v.get("values", 0)}
		"rotated_block_provider", "rotated":
			return {"t": "simple", "s": _state(v.get("state", {}))}
	return {"t": "simple", "s": _state(v.get("state", v))}


## Legacy positional factory wrapper so MCNoise.Normal.create can fork octaves from a java.util.Random seed.
class LegacyPF:
	var seed := 0

	func _init(s: int) -> void:
		seed = s

	func fork_positional():
		return self

	func from_hash(name: String) -> RandomSources.LegacyRandom:
		return RandomSources.LegacyRandom.new(RandomSources.java_string_hash(name) ^ seed)


class LegacyRoot:
	var r: RandomSources.LegacyRandom

	func _init(x: RandomSources.LegacyRandom) -> void:
		r = x

	func fork_positional():
		return Features.LegacyPF.new(r.next_long())


func _legacy_pf(lr: RandomSources.LegacyRandom):
	return LegacyRoot.new(lr)


## Block predicates.
func _pred(v) -> Dictionary:
	if not (v is Dictionary):
		return {"t": "true"}
	var t := str(v.get("type", "true")).trim_prefix("minecraft:")
	var off := Vector3i.ZERO
	if v.get("offset") is Array:
		var o: Array = v["offset"]
		off = Vector3i(int(o[0]), int(o[1]), int(o[2]))
	match t:
		"matching_blocks":
			var ids := {}
			var bl = v.get("blocks", [])
			if bl is String:
				if bl.begins_with("#"):
					for n in _tag_blocks(bl):
						ids[blocks.block_id(n)] = true
				else:
					bl = [bl]
			if bl is Array:
				for b in bl:
					ids[blocks.block_id(str(b))] = true
			return {"t": "blocks", "ids": ids, "off": off}
		"matching_block_tag":
			var ids2 := {}
			for n in _tag_blocks(str(v.get("tag", ""))):
				ids2[blocks.block_id(n)] = true
			return {"t": "blocks", "ids": ids2, "off": off}
		"matching_fluids":
			var fl = v.get("fluids", [])
			if fl is String:
				fl = [fl]
			var lava := false
			var water := false
			for f in fl:
				if str(f).contains("lava"):
					lava = true
				if str(f).contains("water"):
					water = true
			return {"t": "fluids", "lava": lava, "water": water, "off": off}
		"solid":
			return {"t": "solid", "off": off}
		"replaceable":
			return {"t": "replaceable", "off": off}
		"would_survive":
			return {"t": "survive", "s": _state(v.get("state", "minecraft:oak_sapling")), "off": off}
		"has_sturdy_face":
			return {"t": "sturdy", "dir": str(v.get("direction", "up")), "off": off}
		"inside_world_bounds":
			return {"t": "bounds", "off": off}
		"height_range":
			return {"t": "hrange", "lo": _anchor(v.get("min_inclusive", {"above_bottom": 0})), "hi": _anchor(v.get("max_inclusive", {"below_top": 0})), "off": off}
		"all_of", "any_of":
			var ps: Array = []
			for p in v.get("predicates", []):
				ps.append(_pred(p))
			return {"t": t, "ps": ps}
		"not":
			return {"t": "not", "p": _pred(v.get("predicate", {}))}
		"true":
			return {"t": "true"}
	return {"t": "true"}


func _tag_blocks(tag: String) -> Dictionary:
	var t := tag.trim_prefix("#")
	if tag_cache.has(t):
		return tag_cache[t]
	var r := Tags.blocks(t)
	if t.trim_prefix("minecraft:") == "air" and r.is_empty():
		r = {"air": true, "cave_air": true, "void_air": true}
	tag_cache[t] = r
	return r


## A block HolderSet ("#tag", one id or a list of ids) -> {block id: true}.
func _block_set(v) -> Dictionary:
	var out := {}
	var names: Array = []
	if v is String:
		if (v as String).begins_with("#"):
			names = _tag_blocks(v).keys()
		else:
			names = [v]
	elif v is Array:
		names = v
	for n in names:
		var bi := blocks.block_id(str(n))
		if bi >= 0:
			out[bi] = true
	return out


func _rule_test(v) -> Dictionary:
	if not (v is Dictionary):
		return {"t": "true"}
	var t := str(v.get("predicate_type", "always_true")).trim_prefix("minecraft:")
	match t:
		"tag_match":
			var ids := {}
			for n in _tag_blocks(str(v.get("tag", ""))):
				ids[blocks.block_id(n)] = true
			return {"t": "ids", "ids": ids}
		"block_match":
			return {"t": "ids", "ids": {blocks.block_id(str(v.get("block", ""))): true}}
		"blockstate_match":
			return {"t": "state", "s": _state(v.get("block_state", {}))}
		"random_block_match":
			return {"t": "rand", "ids": {blocks.block_id(str(v.get("block", ""))): true}, "p": float(v.get("probability", 1.0))}
		"height_match":
			return {"t": "height", "lo": int(v.get("min_inclusive", -2032)), "hi": int(v.get("max_inclusive", 2031))}
		"any_of", "all_of":
			var rs: Array = []
			for r in v.get("rules", []):
				rs.append(_rule_test(r))
			return {"t": t, "rs": rs}
		"not":
			return {"t": "not", "r": _rule_test(v.get("rule", {}))}
	return {"t": "true"}


## Merge mode of an ore target (W_ORE | rule << 2, see W_ORE). Each distinct rule test is interned once (static, shared
## by every generator, so the indices in saved write lists stay valid) with its per-state table. The position / random
## parts can't be re-tested at merge time: height_match passes, random_block_match keeps its block test only (vanilla
## ores use neither). W_FORCE (the old rule) once 29 rules are taken.
func _ore_mode(rt: Dictionary) -> int:
	var key := var_to_str(rt)
	_ore_m.lock()
	var idx := int(ore_rule_index.get(key, -1))
	if idx < 0 and ore_rule_index.size() < 29:
		idx = ore_rule_index.size()
		var ok := _rule_states(rt)
		var m := ore_mask.duplicate()
		var n := ok.size()
		if m.size() < n:
			var old := m.size()
			m.resize(n)
			for st in range(old, n):
				m[st] = 0
		for st in n:
			if ok[st] != 0:
				m[st] |= 1 << idx
		ore_mask = m
		ore_rule_index[key] = idx
	_ore_m.unlock()
	return W_FORCE if idx < 0 else W_ORE | (idx << 2)


## Per-state result of a rule test (1 = passes) for the ore merge table.
func _rule_states(rt: Dictionary) -> PackedByteArray:
	var n := blocks.st_block.size()
	var out := PackedByteArray()
	out.resize(n)
	out.fill(0)
	match str(rt["t"]):
		"true", "height":
			out.fill(1)
		"ids", "rand":
			for b in rt["ids"]:
				var bi := int(b)
				if bi >= 0 and bi < blocks.block_first.size():
					for k in blocks.block_count[bi]:
						out[blocks.block_first[bi] + k] = 1
		"state":
			var s := int(rt["s"])
			if s >= 0 and s < n:
				out[s] = 1
		"any_of", "all_of":
			var all := str(rt["t"]) == "all_of"
			if all:
				out.fill(1)
			for r in rt["rs"]:
				var sub := _rule_states(r)
				for st in n:
					out[st] = (out[st] & sub[st]) if all else (out[st] | sub[st])
		"not":
			var sub2 := _rule_states(rt["r"])
			for st in n:
				out[st] = 1 - sub2[st]
	return out


## Snapshot of the ore merge table for one decorate merge.
static func ore_table() -> PackedInt32Array:
	_ore_m.lock()
	var m := ore_mask
	_ore_m.unlock()
	return m


## Whether a write of `mode` applies over the current state `cur` (Features.apply rules; also /place and tree growth
## on the live world).
static func write_ok(mode: int, cur: int, fl: PackedInt32Array, om: PackedInt32Array) -> bool:
	if mode == W_FORCE:
		return true
	if (mode & 3) == W_ORE:
		if om.is_empty():
			return true
		return cur > 0 and cur < om.size() and ((om[cur] >> (mode >> 2)) & 1) != 0
	if cur == 0:
		return true
	var f := fl[cur] if cur < fl.size() else 0
	if mode == W_AIR:
		return (f & BlockRegistry.F_REPLACEABLE) != 0
	if mode == W_REPLACEABLE:
		return (f & (BlockRegistry.F_REPLACEABLE | BlockRegistry.F_LEAVES)) != 0
	return true


func _mod(m) -> Dictionary:
	if not (m is Dictionary):
		return {"t": "none"}
	var t := str(m.get("type", "")).trim_prefix("minecraft:")
	var out := {"t": t, "raw": m}
	match t:
		"block_predicate_filter":
			out["pred"] = _pred(m.get("predicate", {}))
		"environment_scan":
			out["target"] = _pred(m.get("target_condition", {}))
			out["allowed"] = _pred(m.get("allowed_search_condition", {"type": "minecraft:true"}))
		"randomly_selected":
			var subs: Array = []
			for sm in m.get("placements", []):
				subs.append(_mod(sm))
			out["subs"] = subs
	return out


# ------------------------------------------------------------------ runtime context

class FCtx:
	var block_entities: Dictionary = {}   # Vector3i -> data (gateways etc.; applied with the writes)
	var postproc := PackedInt32Array()    # [x,y,z]* positions whose shape is recomputed once the chunk is complete
	var entities: Array = []              # serialized mobs from structure templates (inside the origin chunk)
	var region: ChunkRegion
	var r: RandomSources.Xoroshiro
	var writes := PackedInt32Array()
	# job-private copy of the 3x3 region (blocks as written so far by this pass, pristine surfaces, biomes)
	var overlay: Dictionary = {}     # legacy path only (flat empty)
	var flat := PackedInt32Array()   # ci * 98304 + ((y + 64) << 8 | lz << 4 | lx), ci = dz * 3 + dx
	var fx0 := 0
	var fz0 := 0
	var has := PackedByteArray()     # chunk present
	var hstate := PackedByteArray()  # 0 no surface data, 1 gen_surface, 2 gen_surface + gen_floor
	var gs := PackedInt32Array()
	var gf := PackedInt32Array()
	var bio := PackedByteArray()
	var info := PackedInt32Array()   # native kernels: [fx0, fz0, has x9, hstate x9]
	# live heightmaps (Java ProtoChunk POST_FEATURES types, updated by every write of this pass; the *_WG types stay
	# pristine): 4 x 48x48 [WORLD_SURFACE, OCEAN_FLOOR, MOTION_BLOCKING, MOTION_BLOCKING_NO_LEAVES], col = lz * 48 + lx
	var hl := PackedInt32Array()
	var struct_scan: Dictionary = {} # Structures._scan result for this origin (shared by all steps)
	var origin_chunk: Chunk
	var placed_name := ""
	var tree_logs: Array = []     # Java TreeDecorator.Context logs / leaves of the tree being placed
	var tree_leaves: Array = []
	var tree_leaf_set: Dictionary = {}   # FoliageSetter.isSet (cherry hanging leaves)
	var unsupported: Dictionary


func get_block(c: FCtx, p: Vector3i) -> int:
	if c.flat.is_empty():
		var o = c.overlay.get(p)
		if o != null:
			return o
		return c.region.get_block(p.x, p.y, p.z)
	var lx := p.x - c.fx0
	var lz := p.z - c.fz0
	if lx < 0 or lx >= 48 or lz < 0 or lz >= 48 or p.y < -64 or p.y >= 320:
		return 0
	var ci := (lz >> 4) * 3 + (lx >> 4)
	if c.has[ci] == 0:
		return 0
	return c.flat[ci * 98304 + ((p.y + 64) << 8) + ((lz & 15) << 4) + (lx & 15)]


## Chunk of the 3x3 region containing block column (x, z) is present.
func in_region(c: FCtx, x: int, z: int) -> bool:
	if c.flat.is_empty():
		return c.region.chunk_at(x, z) != null
	var lx := x - c.fx0
	var lz := z - c.fz0
	return lx >= 0 and lx < 48 and lz >= 0 and lz < 48 and c.has[(lz >> 4) * 3 + (lx >> 4)] != 0


func set_block(c: FCtx, p: Vector3i, st: int, mode: int = W_FORCE) -> void:
	if p.y < Coords.MIN_Y or p.y >= Coords.MAX_Y or st < 0:
		return
	if c.flat.is_empty():
		if c.region.chunk_at(p.x, p.z) == null:
			return
		c.overlay[p] = st
		c.writes.append_array([p.x, p.y, p.z, st, mode])
		return
	var lx := p.x - c.fx0
	var lz := p.z - c.fz0
	if lx < 0 or lx >= 48 or lz < 0 or lz >= 48:
		return
	var ci := (lz >> 4) * 3 + (lx >> 4)
	if c.has[ci] == 0:
		return
	c.flat[ci * 98304 + ((p.y + 64) << 8) + ((lz & 15) << 4) + (lx & 15)] = st
	c.writes.append_array([p.x, p.y, p.z, st, mode])
	if not c.hl.is_empty() and c.hstate[ci] == 2:
		_hl_update(c, lx, p.y, lz, ci, st)


## Java Heightmap predicates per live type: 0 WORLD_SURFACE (not air), 1 OCEAN_FLOOR (blocks motion), 2 MOTION_BLOCKING
## (blocks motion or holds fluid), 3 MOTION_BLOCKING_NO_LEAVES (the same, leaves excluded).
func _hl_ok(k: int, st: int) -> bool:
	if st <= 0:
		return false
	var fl := blocks.st_flags[st]
	if fl & BlockRegistry.F_AIR:
		return false
	match k:
		0:
			return true
		1:
			return (fl & BlockRegistry.F_COLLIDE) != 0
		2:
			return (fl & (BlockRegistry.F_COLLIDE | BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0
	return (fl & (BlockRegistry.F_COLLIDE | BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0 and (fl & BlockRegistry.F_LEAVES) == 0


## Java Heightmap.update for the live types after a write at (lx, y, lz) of the region.
func _hl_update(c: FCtx, lx: int, y: int, lz: int, ci: int, st: int) -> void:
	var col := lz * 48 + lx
	for k in 4:
		var idx := k * 2304 + col
		var h := c.hl[idx]
		if y <= h - 2:
			continue
		if _hl_ok(k, st):
			if y >= h:
				c.hl[idx] = y + 1
		elif h - 1 == y:
			var base := ci * 98304 + ((lz & 15) << 4) + (lx & 15)
			var nh := Coords.MIN_Y
			var j := y - 1
			while j >= Coords.MIN_Y:
				if _hl_ok(k, c.flat[base + ((j + 64) << 8)]):
					nh = j + 1
					break
				j -= 1
			c.hl[idx] = nh


## Heightmap value (first free y above the top block of the given type): *_WG types from pristine generation data,
## the others live (Java: features see the blocks earlier features of this pass placed, e.g. a tree under another
## tree's canopy lands on its leaves and fails would_survive - the natural spacing / gaps of vanilla forests).
func height(c: FCtx, kind: String, x: int, z: int) -> int:
	if c.flat.is_empty():
		return _height_legacy(c, kind, x, z)
	var lx := x - c.fx0
	var lz := z - c.fz0
	if lx < 0 or lx >= 48 or lz < 0 or lz >= 48:
		return Coords.MIN_Y
	var ci := (lz >> 4) * 3 + (lx >> 4)
	var hs := c.hstate[ci]
	if hs == 0:
		return Coords.MIN_Y
	if hs == 2 and not c.hl.is_empty():
		var lk := -1
		match kind:
			"WORLD_SURFACE":
				lk = 0
			"OCEAN_FLOOR":
				lk = 1
			"MOTION_BLOCKING":
				lk = 2
			"MOTION_BLOCKING_NO_LEAVES":
				lk = 3
		if lk >= 0:
			return c.hl[lk * 2304 + lz * 48 + lx]
	var hi := ci * 256 + (lx & 15) + (lz & 15) * 16
	if kind.begins_with("OCEAN_FLOOR"):
		if hs == 2:
			return c.gf[hi]
	else:
		return c.gs[hi] + 1
	return _height_legacy(c, kind, x, z)


func _height_legacy(c: FCtx, kind: String, x: int, z: int) -> int:
	var ch := c.region.chunk_at(x, z)
	if ch == null or ch.gen_surface.is_empty():
		return Coords.MIN_Y
	var i := (x & 15) + (z & 15) * 16
	var top := ch.gen_surface[i]
	if kind.begins_with("OCEAN_FLOOR"):
		if not ch.gen_floor.is_empty():
			return ch.gen_floor[i]
		var y := top
		while y > Coords.MIN_Y:
			var st := ch.get_block(x & 15, y, z & 15)
			if st != 0 and (blocks.st_flags[st] & (BlockRegistry.F_LIQUID)) == 0 and (blocks.st_flags[st] & BlockRegistry.F_COLLIDE) != 0:
				break
			y -= 1
		return y + 1
	return top + 1


## Java CountOnEveryLayerPlacement.findOnGroundYPosition (empty = air/water/lava; bedrock never counts as ground).
func _layer_y(c: FCtx, x: int, y: int, z: int, target: int) -> int:
	var n := 0
	var bed := blocks.block_id("bedrock")
	var prev := get_block(c, Vector3i(x, y, z))
	var j := y
	while j >= gen.gen_min_y + 1:
		var cur := get_block(c, Vector3i(x, j - 1, z))
		var cur_empty := cur <= 0 or (blocks.st_flags[cur] & BlockRegistry.F_LIQUID) != 0
		var prev_empty := prev <= 0 or (blocks.st_flags[prev] & BlockRegistry.F_LIQUID) != 0
		if not cur_empty and prev_empty and blocks.st_block[cur] != bed:
			if n == target:
				return j
			n += 1
		prev = cur
		j -= 1
	return 2147483647


func biome_at(c: FCtx, p: Vector3i) -> int:
	if c.flat.is_empty():
		var ch := c.region.chunk_at(p.x, p.z)
		return ch.biome_at(p.x & 15, clampi(p.y, Coords.MIN_Y, Coords.MAX_Y - 1), p.z & 15) if ch != null else -1
	var lx := p.x - c.fx0
	var lz := p.z - c.fz0
	if lx < 0 or lx >= 48 or lz < 0 or lz >= 48:
		return -1
	var ci := (lz >> 4) * 3 + (lx >> 4)
	if c.has[ci] == 0:
		return -1
	var qy := clampi((clampi(p.y, Coords.MIN_Y, Coords.MAX_Y - 1) - Coords.MIN_Y) >> 2, 0, 95)
	return c.bio[ci * 1536 + ((lx & 15) >> 2) + ((lz & 15) >> 2) * 4 + qy * 16]


# ------------------------------------------------------------------ providers / predicates / numbers

func sample_int(c: FCtx, v) -> int:
	if v is int or v is float:
		return int(v)
	if not (v is Dictionary):
		return 0
	var r := c.r
	# a bare {min_inclusive, max_inclusive} is a UniformInt (e.g. cherry branch_start_offset_from_top)
	var t := str(v.get("type", "uniform" if v.has("min_inclusive") else "constant")).trim_prefix("minecraft:")
	match t:
		"constant":
			return int(v.get("value", 0))
		"uniform":
			var lo := int(v.get("min_inclusive", v.get("value", {}).get("min_inclusive", 0) if v.get("value") is Dictionary else 0))
			var hi := int(v.get("max_inclusive", v.get("value", {}).get("max_inclusive", 0) if v.get("value") is Dictionary else 0))
			return lo + r.next_int_bound(hi - lo + 1) if hi >= lo else lo
		"biased_to_bottom":
			var lo2 := int(v.get("min_inclusive", 0))
			var hi2 := int(v.get("max_inclusive", 0))
			return lo2 + r.next_int_bound(r.next_int_bound(hi2 - lo2 + 1) + 1)
		"clamped":
			return clampi(sample_int(c, v.get("source", 0)), int(v.get("min_inclusive", -2147483648)), int(v.get("max_inclusive", 2147483647)))
		"clamped_normal":
			var g := float(v.get("mean", 0.0)) + _gauss(r) * float(v.get("deviation", 1.0))
			return clampi(int(floor(g)), int(v.get("min_inclusive", -2147483648)), int(v.get("max_inclusive", 2147483647)))
		"weighted_list":
			var dist: Array = v.get("distribution", [])
			var tot := 0
			for e in dist:
				tot += int(e.get("weight", 1))
			if tot <= 0:
				return 0
			var k := r.next_int_bound(tot)
			for e in dist:
				k -= int(e.get("weight", 1))
				if k < 0:
					return sample_int(c, e.get("data", 0))
			return 0
		"trapezoid":
			var lo3 := int(v.get("min", v.get("min_inclusive", 0)))
			var hi3 := int(v.get("max", v.get("max_inclusive", 0)))
			var plateau := int(v.get("plateau", 0))
			var span := hi3 - lo3
			var j := (span - plateau) / 2
			var kk := span - j
			return lo3 + r.next_int_bound(kk + 1) + r.next_int_bound(j + 1)
	return 0


func _gauss(r) -> float:
	while true:
		var d: float = 2.0 * r.next_double() - 1.0
		var e: float = 2.0 * r.next_double() - 1.0
		var f := d * d + e * e
		if f < 1.0 and f != 0.0:
			return d * sqrt(-2.0 * log(f) / f)
	return 0.0


func _anchor(a) -> int:
	if a is Dictionary:
		if a.has("absolute"):
			return int(a["absolute"])
		if a.has("above_bottom"):
			return gen.gen_min_y + int(a["above_bottom"])
		if a.has("below_top"):
			return gen.gen_min_y + gen.gen_depth - 1 - int(a["below_top"])
		if a.has("relative_to_sea_level"):
			return gen.sea_level + int(a["relative_to_sea_level"])
	return 0


func sample_height(c: FCtx, v) -> int:
	if not (v is Dictionary):
		return 0
	var r := c.r
	# a bare {min_inclusive, max_inclusive} is a UniformInt (e.g. cherry branch_start_offset_from_top)
	var t := str(v.get("type", "uniform" if v.has("min_inclusive") else "constant")).trim_prefix("minecraft:")
	if t == "constant" or v.has("absolute") or v.has("above_bottom") or v.has("below_top"):
		return _anchor(v.get("value", v))
	var i := _anchor(v.get("min_inclusive", {}))
	var j := _anchor(v.get("max_inclusive", {}))
	if i > j:
		return i
	match t:
		"uniform":
			return i + r.next_int_bound(j - i + 1)
		"trapezoid":
			var plateau := int(v.get("plateau", 0))
			var k := j - i
			if plateau >= k:
				return i + r.next_int_bound(j - i + 1)
			var l := (k - plateau) / 2
			var m := k - l
			return i + r.next_int_bound(m + 1) + r.next_int_bound(l + 1)
		"biased_to_bottom":
			var inner := int(v.get("inner", 1))
			var l2 := r.next_int_bound(j - i - inner + 1)
			return r.next_int_bound(l2 + inner) + i
		"very_biased_to_bottom":
			var inner2 := int(v.get("inner", 1))
			var k2 := _mth_next(r, i + inner2, j)
			var l3 := _mth_next(r, i, k2 - 1)
			return _mth_next(r, i, l3 - 1 + inner2)
	return i


static func _mth_next(r, a: int, b: int) -> int:
	return a if a >= b else r.next_int_bound(b - a + 1) + a


func provide(c: FCtx, pv: Dictionary, p: Vector3i) -> int:
	match str(pv.get("t", "simple")):
		"simple":
			return pv["s"]
		"weighted":
			var tot := 0
			for e in pv["e"]:
				tot += int(e[0])
			if tot <= 0:
				return 0
			var k := c.r.next_int_bound(tot)
			for e in pv["e"]:
				k -= int(e[0])
				if k < 0:
					return provide(c, e[1], p)
		"rule":
			for rr in pv["rules"]:
				if test(c, rr[0], p):
					return provide(c, rr[1], p)
			if not (pv["fallback"] as Dictionary).is_empty():
				return provide(c, pv["fallback"], p)
			return -1
		"noise_threshold":
			var nv := (pv["noise"] as MCNoise.Normal).value(p.x * float(pv["scale"]), p.y * float(pv["scale"]), p.z * float(pv["scale"]))
			if nv < float(pv["threshold"]):
				var low: Array = pv["low"]
				return low[c.r.next_int_bound(low.size())] if not low.is_empty() else pv["default"]
			var high: Array = pv["high"]
			if c.r.next_float() < float(pv["high_chance"]) and not high.is_empty():
				return high[c.r.next_int_bound(high.size())]
			return pv["default"] if int(pv["default"]) >= 0 else (high[0] if not high.is_empty() else 0)
		"noise", "dual_noise":
			var states: Array = pv["states"]
			if states.is_empty():
				return 0
			var nv2 := (pv["noise"] as MCNoise.Normal).value(p.x * float(pv["scale"]), p.y * float(pv["scale"]), p.z * float(pv["scale"]))
			var idx := clampi(int(floor((clampf(nv2, -1.0, 1.0) + 1.0) / 2.0 * states.size())), 0, states.size() - 1)
			return states[idx]
		"rint":
			var s := provide(c, pv["src"], p)
			var vals = pv["vals"]
			if s > 0 and blocks.has_prop(s, pv["prop"]):
				return blocks.with_prop(s, pv["prop"], str(sample_int(c, vals)))
			return s
	return 0


func test(c: FCtx, pd: Dictionary, p: Vector3i) -> bool:
	var q: Vector3i = p + pd.get("off", Vector3i.ZERO)
	match str(pd["t"]):
		"true":
			return true
		"blocks":
			var st := get_block(c, q)
			return st >= 0 and (pd["ids"] as Dictionary).has(blocks.st_block[st])
		"fluids":
			var st2 := get_block(c, q)
			if st2 <= 0:
				return false
			var fl := blocks.st_flags[st2]
			if (fl & BlockRegistry.F_LAVA) != 0:
				return pd["lava"]
			if (fl & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0:
				return pd["water"]
			return false
		"solid":
			var st3 := get_block(c, q)
			return st3 > 0 and (blocks.st_flags[st3] & BlockRegistry.F_COLLIDE) != 0
		"replaceable":
			var st4 := get_block(c, q)
			return st4 == 0 or (st4 > 0 and (blocks.st_flags[st4] & BlockRegistry.F_REPLACEABLE) != 0)
		"survive":
			return can_survive(c, pd["s"], q)
		"sturdy":
			var dv: Vector3i = {"up": Vector3i(0, 1, 0), "down": Vector3i(0, -1, 0)}.get(pd["dir"], Vector3i.ZERO)
			var st5 := get_block(c, q)
			return st5 > 0 and (blocks.st_flags[st5] & BlockRegistry.F_FULL_SHAPE) != 0 and dv != null
		"bounds":
			return q.y >= gen.gen_min_y and q.y < gen.gen_min_y + gen.gen_depth
		"hrange":
			return q.y >= int(pd["lo"]) and q.y <= int(pd["hi"])
		"all_of":
			for sp in pd["ps"]:
				if not test(c, sp, p):
					return false
			return true
		"any_of":
			for sp in pd["ps"]:
				if test(c, sp, p):
					return true
			return false
		"not":
			return not test(c, pd["p"], p)
	return true


func rule_test(c: FCtx, rt: Dictionary, st: int, p: Vector3i) -> bool:
	match str(rt["t"]):
		"true":
			return true
		"ids":
			return st >= 0 and (rt["ids"] as Dictionary).has(blocks.st_block[st])
		"state":
			return st == rt["s"]
		"rand":
			return st >= 0 and (rt["ids"] as Dictionary).has(blocks.st_block[st]) and c.r.next_float() < float(rt["p"])
		"height":
			return p.y >= int(rt["lo"]) and p.y <= int(rt["hi"])
		"any_of":
			for r in rt["rs"]:
				if rule_test(c, r, st, p):
					return true
			return false
		"all_of":
			for r in rt["rs"]:
				if not rule_test(c, r, st, p):
					return false
			return true
		"not":
			return not rule_test(c, rt["r"], st, p)
	return true


func _is_dirt(st: int) -> bool:
	if st <= 0:
		return false
	var n := blocks.name_of(st)
	return n in ["grass_block", "dirt", "podzol", "coarse_dirt", "mycelium", "rooted_dirt", "moss_block", "mud", "muddy_mangrove_roots", "farmland", "pale_moss_block"]


func can_survive(c: FCtx, st: int, p: Vector3i) -> bool:
	if st <= 0:
		return true
	var n := blocks.name_of(st)
	var below := get_block(c, p + Vector3i(0, -1, 0))
	var bn := blocks.name_of(maxi(below, 0))
	if n.ends_with("_sapling") or n.ends_with("_propagule") or n in ["short_grass", "fern", "tall_grass", "large_fern", "bush", "firefly_bush", "sweet_berry_bush", "pink_petals", "wildflowers", "leaf_litter", "red_shrub"] or n.ends_with("_tulip") or n in ["dandelion", "poppy", "blue_orchid", "allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley", "sunflower", "lilac", "rose_bush", "peony", "torchflower", "closed_eyeblossom", "open_eyeblossom", "pale_moss_carpet"]:
		if n == "mangrove_propagule":
			return _is_dirt(below) or bn == "clay"
		return _is_dirt(below)
	if n == "dead_bush" or n.ends_with("dry_grass"):
		return _is_dirt(below) or bn.contains("sand") or bn.contains("terracotta")
	if n in ["crimson_fungus", "warped_fungus", "crimson_roots", "warped_roots", "nether_sprouts"]:
		# Java RootsBlock / NetherSproutsBlock / FungusBlock.mayPlaceOn: #nylium, soul soil, #dirt (mycelium), farmland
		return _is_dirt(below) or bn in ["crimson_nylium", "warped_nylium", "soul_soil"]
	if n.ends_with("_mushroom"):
		return below > 0 and (blocks.st_flags[below] & BlockRegistry.F_OPAQUE) != 0
	if n == "cactus":
		if not (bn == "sand" or bn == "red_sand" or bn == "cactus"):
			return false
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var s := get_block(c, p + d)
			if s > 0 and (blocks.st_flags[s] & BlockRegistry.F_COLLIDE) != 0:
				return false
		return true
	if n == "sugar_cane":
		if bn == "sugar_cane":
			return true
		if not (_is_dirt(below) or bn.contains("sand")):
			return false
		for d in [Vector3i(1, -1, 0), Vector3i(-1, -1, 0), Vector3i(0, -1, 1), Vector3i(0, -1, -1)]:
			var s2 := get_block(c, p + d)
			if s2 > 0 and (blocks.st_flags[s2] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0:
				return true
		return false
	if n in ["seagrass", "tall_seagrass", "kelp", "kelp_plant", "sea_pickle"] or n.ends_with("_coral") or n.ends_with("_coral_fan"):
		return below > 0 and (blocks.st_flags[below] & BlockRegistry.F_FULL_SHAPE) != 0
	if n == "lily_pad":
		return below > 0 and (blocks.st_flags[below] & BlockRegistry.F_LIQUID) != 0
	if n == "snow":
		return below > 0 and (blocks.st_flags[below] & BlockRegistry.F_FULL_SHAPE) != 0 and bn != "ice" and bn != "packed_ice"
	return true


# ------------------------------------------------------------------ placement chain

func place_placed(c: FCtx, pf: Dictionary, origin: Vector3i) -> void:
	_chain(c, pf, pf["mods"], 0, origin)


func _chain(c: FCtx, pf: Dictionary, mods: Array, i: int, p: Vector3i) -> void:
	if i >= mods.size():
		place_feature(c, pf["cf"], p)
		return
	var m: Dictionary = mods[i]
	var raw: Dictionary = m["raw"]
	match str(m["t"]):
		"count":
			var n := sample_int(c, raw.get("count", 1))
			for k in n:
				_chain(c, pf, mods, i + 1, p)
		"in_square":
			var x := p.x + c.r.next_int_bound(16)
			var z := p.z + c.r.next_int_bound(16)
			_chain(c, pf, mods, i + 1, Vector3i(x, p.y, z))
		"rarity_filter":
			if c.r.next_float() < 1.0 / float(raw.get("chance", 1)):
				_chain(c, pf, mods, i + 1, p)
		"height_range":
			_chain(c, pf, mods, i + 1, Vector3i(p.x, sample_height(c, raw.get("height", {})), p.z))
		"heightmap":
			var h := height(c, str(raw.get("heightmap", "WORLD_SURFACE_WG")), p.x, p.z)
			if h > Coords.MIN_Y:
				_chain(c, pf, mods, i + 1, Vector3i(p.x, h, p.z))
		"biome":
			var b := biome_at(c, p)
			if b >= 0 and (feature_biomes.get(c.placed_name, {}) as Dictionary).has(b):
				_chain(c, pf, mods, i + 1, p)
		"surface_water_depth_filter":
			var fl := height(c, "OCEAN_FLOOR", p.x, p.z)
			var ws := height(c, "WORLD_SURFACE", p.x, p.z)
			if ws - fl <= int(raw.get("max_water_depth", 0)):
				_chain(c, pf, mods, i + 1, p)
		"block_predicate_filter":
			if test(c, m["pred"], p):
				_chain(c, pf, mods, i + 1, p)
		"offset":
			var ox := sample_int(c, raw.get("x", 0))
			var oy := sample_int(c, raw.get("y", 0))
			var oz := sample_int(c, raw.get("z", 0))
			_chain(c, pf, mods, i + 1, p + Vector3i(ox, oy, oz))
		"random_offset":
			var rx := sample_int(c, raw.get("xz_spread", 0))
			var ry := sample_int(c, raw.get("y_spread", 0))
			var rz := sample_int(c, raw.get("xz_spread", 0))
			_chain(c, pf, mods, i + 1, p + Vector3i(rx, ry, rz))
		"noise_threshold_count":
			var d := simplex_info.value(p.x / 200.0, p.z / 200.0)
			var n2 := int(raw.get("below_noise", 0)) if d < float(raw.get("noise_level", 0.0)) else int(raw.get("above_noise", 0))
			for k in n2:
				_chain(c, pf, mods, i + 1, p)
		"noise_based_count":
			var d2 := simplex_info.value(p.x / float(raw.get("noise_factor", 1.0)), p.z / float(raw.get("noise_factor", 1.0)))
			var n3 := int(ceil((d2 + float(raw.get("noise_offset", 0.0))) * int(raw.get("noise_to_count_ratio", 1))))
			for k in maxi(n3, 0):
				_chain(c, pf, mods, i + 1, p)
		"environment_scan":
			var dirs := {"up": 1, "down": -1}
			var dy: int = dirs.get(str(raw.get("direction_of_search", "down")), -1)
			var steps := int(raw.get("max_steps", 12))
			var q := p
			if test(c, m["target"], q):
				_chain(c, pf, mods, i + 1, q)
				return
			for s in steps:
				q.y += dy
				if q.y < Coords.MIN_Y or q.y >= Coords.MAX_Y or not test(c, m["allowed"], q):
					return
				if test(c, m["target"], q):
					_chain(c, pf, mods, i + 1, q)
					return
		"surface_relative_threshold_filter":
			var h2 := height(c, str(raw.get("heightmap", "OCEAN_FLOOR_WG")), p.x, p.z)
			var lo := h2 + int(raw.get("min_inclusive", -2147483648)) if raw.has("min_inclusive") else -2147483648
			var hi := h2 + int(raw.get("max_inclusive", 2147483647)) if raw.has("max_inclusive") else 2147483647
			if p.y >= lo and p.y <= hi:
				_chain(c, pf, mods, i + 1, p)
		"count_on_every_layer":
			# Java CountOnEveryLayerPlacement: N positions on the layer-th air-above-ground surface, per layer
			var found: Array = []
			var layer := 0
			var more := true
			while more:
				more = false
				var jn := 0
				while jn < sample_int(c, raw.get("count", 1)):
					var x2 := p.x + c.r.next_int_bound(16)
					var z2 := p.z + c.r.next_int_bound(16)
					var top := height(c, "MOTION_BLOCKING", x2, z2)
					var y2 := _layer_y(c, x2, top, z2, layer)
					if y2 != 2147483647:
						found.append(Vector3i(x2, y2, z2))
						more = true
					jn += 1
				layer += 1
			for q3 in found:
				_chain(c, pf, mods, i + 1, q3)
		"random_chance":
			if c.r.next_float() < float(raw.get("chance", 1.0)):
				_chain(c, pf, mods, i + 1, p)
		"randomly_selected":
			var subs: Array = m["subs"]
			if not subs.is_empty():
				var sel: Dictionary = subs[c.r.next_int_bound(subs.size())]
				var rest: Array = [sel]
				rest.append_array(mods.slice(i + 1))
				_chain(c, pf, rest, 0, p)
		"cuboid":
			var sx := sample_int(c, raw.get("xz_size", 1))
			var sy := sample_int(c, raw.get("y_size", 1))
			var sz := sample_int(c, raw.get("xz_size", 1))
			var edges := bool(raw.get("include_edges", true))
			var interior := bool(raw.get("include_interior", true))
			for cx2 in sx + 1:
				for cy2 in sy + 1:
					for cz2 in sz + 1:
						var nb := int(cx2 == 0 or cx2 == sx) + int(cy2 == 0 or cy2 == sy) + int(cz2 == 0 or cz2 == sz)
						if (nb >= 2 and not edges) or (nb == 0 and not interior):
							continue
						_chain(c, pf, mods, i + 1, p + Vector3i(cx2, cy2, cz2))
		"fixed_placement":
			for pos in raw.get("positions", []):
				if pos is Array and pos.size() == 3:
					_chain(c, pf, mods, i + 1, Vector3i(int(pos[0]), int(pos[1]), int(pos[2])))
		_:
			_chain(c, pf, mods, i + 1, p)


# ------------------------------------------------------------------ features

func place_feature(c: FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var t := str(cf.get("t", "none"))
	match t:
		"none":
			return false
		"ore", "scattered_ore":
			if Native.ok and Native.features_ok and not c.flat.is_empty():
				var nr := _ore_native(c, cf, p, 0 if t == "ore" else 1)
				if nr >= 0:
					return nr == 1
			return _ore(c, cf, p) if t == "ore" else _scattered_ore(c, cf, p)
		"simple_block":
			var st := provide(c, cf["prov"], p)
			if st < 0 or not can_survive(c, st, p):
				return false
			if blocks.has_prop(st, "half") and blocks.get_prop(st, "half") == "lower":
				var up := get_block(c, p + Vector3i(0, 1, 0))
				if up != 0:
					return false
				set_block(c, p, st, W_AIR)
				set_block(c, p + Vector3i(0, 1, 0), blocks.with_prop(st, "half", "upper"), W_AIR)
				return true
			var cur := get_block(c, p)
			if cur > 0 and (blocks.st_flags[cur] & BlockRegistry.F_LIQUID) and blocks.has_prop(st, "waterlogged"):
				st = blocks.with_prop(st, "waterlogged", "true")
			set_block(c, p, st, W_REPLACEABLE)
			return true
		"random_selector":
			for e in cf["fs"]:
				if c.r.next_float() < float(e[0]):
					return _sub(c, e[1], p)
			return _sub(c, cf["default"], p)
		"weighted_random_selector":
			var tot := 0
			for e in cf["ws"]:
				tot += int(e[0])
			if tot <= 0:
				return false
			var k := c.r.next_int_bound(tot)
			for e in cf["ws"]:
				k -= int(e[0])
				if k < 0:
					return _sub(c, e[1], p)
			return false
		"simple_random_selector":
			var ss: Array = cf["ss"]
			if ss.is_empty():
				return false
			return _sub(c, ss[c.r.next_int_bound(ss.size())], p)
		"random_boolean_selector":
			return _sub(c, cf["a"] if c.r.next_bool() else cf["b"], p)
		"sequence":
			for f in cf["seq"]:
				if not _sub(c, f, p):
					return false
			return true
		"block_column":
			return _column(c, cf, p)
		"disk":
			return _disk(c, cf, p)
		"spring_feature":
			return _spring(c, cf, p)
		"lake":
			return _lake(c, cf, p)
		"tree":
			return Trees.place(self, c, cf, p)
		"fallen_tree":
			return Trees.fallen(self, c, cf, p)
		"huge_brown_mushroom", "huge_red_mushroom":
			return Trees.mushroom(self, c, cf, p, t == "huge_red_mushroom")
		"block_pile":
			# Java BlockPileFeature (native twin: featx.cpp case 13)
			if p.y < gen.gen_min_y + 5:
				return false
			var pi := 2 + c.r.next_int_bound(2)
			var pj := 2 + c.r.next_int_bound(2)
			var path := blocks.block_id("dirt_path")
			for qz in range(p.z - pj, p.z + pj + 1):
				for qy in range(p.y, p.y + 2):
					for qx in range(p.x - pi, p.x + pi + 1):
						var k := p.x - qx
						var l := p.z - qz
						var fa := c.r.next_float() * 10.0
						var fb := c.r.next_float() * 6.0
						var put := float(k * k + l * l) <= MCNoise.f32(MCNoise.f32(fa) - MCNoise.f32(fb))
						if not put:
							put = c.r.next_float() < 0.031
						var q := Vector3i(qx, qy, qz)
						var cur := get_block(c, q)
						if not put or (cur != 0 and (blocks.st_flags[cur] & BlockRegistry.F_AIR) == 0):
							continue
						var below := get_block(c, q + Vector3i(0, -1, 0))
						var ok := false
						if below > 0 and blocks.st_block[below] == path:
							ok = c.r.next_bool()
						else:
							ok = below > 0 and (blocks.st_flags[below] & BlockRegistry.F_COLLIDE) != 0 and (blocks.st_flags[below] & BlockRegistry.F_FULL_SHAPE) != 0
						if ok:
							set_block(c, q, provide(c, cf["prov"], q), W_FORCE)
			return true
		"vegetation_patch", "waterlogged_vegetation_patch":
			return _veg_patch(c, cf, p)
		"multiface_growth":
			return _lichen(c, cf, p)
		"geode":
			return _geode(c, cf, p)
		"monster_room":
			return _dungeon(c, p)
		"bamboo":
			if get_block(c, p) != 0 or not _is_dirt(get_block(c, p + Vector3i(0, -1, 0))):
				return false
			var hh := 5 + c.r.next_int_bound(12)
			var bam := blocks.default_state("bamboo")
			for yy in hh:
				if get_block(c, p + Vector3i(0, yy, 0)) != 0:
					break
				set_block(c, p + Vector3i(0, yy, 0), bam, W_AIR)
			return true
		"freeze_top_layer":
			return true  # applied in apply() on live data (chunk-local)
	var cav = FeaturesCave.place(self, c, cf, p, t)
	if cav != null:
		return cav
	var ext = FeaturesExt.place(self, c, cf, p, t)
	if ext != null:
		return ext
	_m.lock()
	unsupported[t] = int(unsupported.get(t, 0)) + 1
	_m.unlock()
	return false


func _sub(c: FCtx, pf: Dictionary, p: Vector3i) -> bool:
	if pf.is_empty():
		return false
	var mods: Array = pf.get("mods", [])
	if mods.is_empty():
		return place_feature(c, pf["cf"], p)
	_chain(c, pf, mods, 0, p)
	return true


func _ore(c: FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var r := c.r
	var size: int = cf["size"]
	var f := r.next_float() * PI
	var g := size / 8.0
	var i := int(ceil((size / 16.0 * 2.0 + 1.0) / 2.0))
	var d := o.x + sin(f) * g
	var e := o.x - sin(f) * g
	var h := o.z + cos(f) * g
	var j := o.z - cos(f) * g
	var l := float(o.y + r.next_int_bound(3) - 2)
	var m := float(o.y + r.next_int_bound(3) - 2)
	var n := o.x - int(ceil(g)) - i
	var oo := o.y - 2 - i
	var pz := o.z - int(ceil(g)) - i
	var q := 2 * (int(ceil(g)) + i)
	var ok := false
	for s in range(n, n + q + 1):
		for t in range(pz, pz + q + 1):
			if oo <= height(c, "OCEAN_FLOOR_WG", s, t):
				ok = true
				break
		if ok:
			break
	if not ok:
		return false
	var ds := PackedFloat64Array()
	ds.resize(size * 4)
	for u in size:
		var v := float(u) / size
		ds[u * 4] = lerpf(d, e, v)
		ds[u * 4 + 1] = lerpf(l, m, v)
		ds[u * 4 + 2] = lerpf(h, j, v)
		var z := r.next_double() * size / 16.0
		ds[u * 4 + 3] = ((sin(PI * v) + 1.0) * z + 1.0) / 2.0
	for u in size - 1:
		if ds[u * 4 + 3] <= 0.0:
			continue
		for ab in range(u + 1, size):
			if ds[ab * 4 + 3] <= 0.0:
				continue
			var w2 := ds[u * 4] - ds[ab * 4]
			var x2 := ds[u * 4 + 1] - ds[ab * 4 + 1]
			var y2 := ds[u * 4 + 2] - ds[ab * 4 + 2]
			var z2 := ds[u * 4 + 3] - ds[ab * 4 + 3]
			if z2 * z2 > w2 * w2 + x2 * x2 + y2 * y2:
				if z2 > 0.0:
					ds[ab * 4 + 3] = -1.0
				else:
					ds[u * 4 + 3] = -1.0
	var seen := {}
	var placed_any := false
	var targets: Array = cf["targets"]
	var discard: float = cf["discard"]
	for ab in size:
		var rad := ds[ab * 4 + 3]
		if rad < 0.0:
			continue
		var cx := ds[ab * 4]
		var cy := ds[ab * 4 + 1]
		var cz := ds[ab * 4 + 2]
		var x0 := maxi(int(floor(cx - rad)), n)
		var y0 := maxi(int(floor(cy - rad)), oo)
		var z0 := maxi(int(floor(cz - rad)), pz)
		var x1 := maxi(int(floor(cx + rad)), x0)
		var y1 := maxi(int(floor(cy + rad)), y0)
		var z1 := maxi(int(floor(cz + rad)), z0)
		for xx in range(x0, x1 + 1):
			var aj := (xx + 0.5 - cx) / rad
			if aj * aj >= 1.0:
				continue
			for yy in range(y0, y1 + 1):
				var al := (yy + 0.5 - cy) / rad
				if aj * aj + al * al >= 1.0:
					continue
				for zz in range(z0, z1 + 1):
					var an := (zz + 0.5 - cz) / rad
					if aj * aj + al * al + an * an >= 1.0 or yy < Coords.MIN_Y or yy >= Coords.MAX_Y:
						continue
					var key := Vector3i(xx, yy, zz)
					if seen.has(key):
						continue
					seen[key] = true
					if not in_region(c, xx, zz):
						continue
					var st := get_block(c, key)
					for tg in targets:
						if _can_place_ore(c, tg, st, key, discard):
							set_block(c, key, tg[1], tg[2])
							placed_any = true
							break
	return placed_any


## Native ore / scattered_ore (RecraftNative.feat_ore, bit-exact): writes applied here in order through set_block.
## Returns 1 placed, 0 not placed, -1 = legacy height data needed (nothing consumed; caller runs the GDScript path).
func _ore_native(c: FCtx, cf: Dictionary, p: Vector3i, kind: int) -> int:
	var nat = cf.get("_nat")
	if nat == null:
		nat = _ore_native_desc(cf)
		cf["_nat"] = nat
	var res: Array = Native.inst.feat_ore(kind, c.flat, c.info, c.gf, [c.r.lo, c.r.hi], PackedInt32Array([p.x, p.y, p.z]),
		nat[0], nat[1], nat[2], nat[3], nat[4], blocks.st_block)
	if int(res[0]) != 0:
		return -1
	c.r.lo = res[2]
	c.r.hi = res[3]
	var w: PackedInt32Array = res[4]
	var tgs: Array = cf["targets"]
	for k in range(0, w.size(), 4):
		var wm := W_FORCE
		for tg in tgs:
			if int(tg[1]) == w[k + 3]:
				wm = int(tg[2])
				break
		set_block(c, Vector3i(w[k], w[k + 1], w[k + 2]), w[k + 3], wm)
	return int(res[1])


class RuleFlat:
	var ri := PackedInt32Array()
	var ids := PackedInt32Array()
	var fl := PackedFloat64Array()

	func add(rt: Dictionary) -> int:
		var node := ri.size() / 4
		ri.append_array([0, 0, 0, 0])
		var t := str(rt["t"])
		var v := [0, 0, 0, 0]
		match t:
			"ids", "rand":
				v[0] = 1 if t == "ids" else 3
				v[1] = ids.size()
				v[2] = (rt["ids"] as Dictionary).size()
				for b in rt["ids"]:
					ids.append(int(b))
				if t == "rand":
					v[3] = fl.size()
					fl.append(float(rt["p"]))
			"state":
				v = [2, int(rt["s"]), 0, 0]
			"height":
				v = [4, int(rt["lo"]), int(rt["hi"]), 0]
			"any_of", "all_of":
				var kids: Array = []
				for sub in rt["rs"]:
					kids.append(add(sub))
				v = [5 if t == "any_of" else 6, ids.size(), kids.size(), 0]
				for k in kids:
					ids.append(int(k))
			"not":
				v = [7, add(rt["r"]), 0, 0]
		for k in 4:
			ri[node * 4 + k] = v[k]
		return node


func _ore_native_desc(cf: Dictionary) -> Array:
	var rf := RuleFlat.new()
	var tg := PackedInt32Array()
	for t in cf["targets"]:
		var node := rf.add(t[0])
		tg.append_array([node, int(t[1])])
	if rf.fl.is_empty():
		rf.fl.append(0.0)
	if rf.ids.is_empty():
		rf.ids.append(-1)
	return [PackedFloat64Array([float(cf["size"]), float(cf["discard"])]), rf.ri, rf.ids, rf.fl, tg]


func _can_place_ore(c: FCtx, tg: Array, st: int, p: Vector3i, discard: float) -> bool:
	if not rule_test(c, tg[0], st, p):
		return false
	if discard <= 0.0:
		return true
	if discard < 1.0 and c.r.next_float() >= discard:
		return true
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if get_block(c, p + d) == 0:
			return false
	return true


func _scattered_ore(c: FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var n := c.r.next_int_bound(int(cf["size"]) + 1)
	for k in n:
		var spread := mini(k, 7)
		var q := o + Vector3i(_spread(c, spread), _spread(c, spread), _spread(c, spread))
		var st := get_block(c, q)
		for tg in cf["targets"]:
			if _can_place_ore(c, tg, st, q, float(cf["discard"])):
				set_block(c, q, tg[1], tg[2])
				break
	return true


func _spread(c: FCtx, s: int) -> int:
	return int(round((c.r.next_float() - c.r.next_float()) * s))


func _column(c: FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var dir := 1 if cf["dir"] == "up" else -1
	var total := 0
	var heights: Array = []
	for l in cf["layers"]:
		var hh := sample_int(c, l[0])
		heights.append(hh)
		total += hh
	if total == 0:
		return false
	var q := p
	var placed := 0
	for li in heights.size():
		for k in heights[li]:
			if not test(c, cf["allowed"], q):
				return placed > 0
			var st := provide(c, cf["layers"][li][1], q)
			if placed == 0 and not can_survive(c, st, q):
				return false
			set_block(c, q, st, W_AIR)
			placed += 1
			q.y += dir
	return true


func _disk(c: FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var r := sample_int(c, cf["radius"])
	var half: int = cf["half"]
	var any := false
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if dx * dx + dz * dz > r * r:
				continue
			for dy in range(half, -half - 1, -1):
				var q := p + Vector3i(dx, dy, dz)
				if test(c, cf["target"], q):
					var st := provide(c, cf["prov"], q)
					if st >= 0:
						set_block(c, q, st, W_FORCE)
						any = true
	return any


func _spring(c: FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var valid: Dictionary = cf["valid"]
	var up := get_block(c, p + Vector3i(0, 1, 0))
	if up <= 0 or not valid.has(blocks.st_block[up]):
		return false
	var dn := get_block(c, p + Vector3i(0, -1, 0))
	if cf["below"] and (dn <= 0 or not valid.has(blocks.st_block[dn])):
		return false
	var cur := get_block(c, p)
	if cur != 0 and (cur <= 0 or not valid.has(blocks.st_block[cur])):
		return false
	var rock := 0
	var hole := 0
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, -1, 0)]:
		var s := get_block(c, p + d)
		if s > 0 and valid.has(blocks.st_block[s]):
			rock += 1
		elif s == 0:
			hole += 1
	if rock == int(cf["rock"]) and hole == int(cf["hole"]):
		var st: int = cf["state"]
		var fl_name := blocks.name_of(st)
		set_block(c, p, blocks.default_state(fl_name), W_FORCE)
		return true
	return false


func _lake(c: FCtx, cf: Dictionary, p0: Vector3i) -> bool:
	if p0.y <= Coords.MIN_Y + 4:
		return false
	var p := p0 - Vector3i(8, 4, 8)
	var grid := PackedByteArray()
	grid.resize(2048)
	var n := c.r.next_int_bound(4) + 4
	for k in n:
		var d := c.r.next_double() * 6.0 + 3.0
		var e := c.r.next_double() * 4.0 + 2.0
		var f := c.r.next_double() * 6.0 + 3.0
		var g := c.r.next_double() * (16.0 - d - 2.0) + 1.0 + d / 2.0
		var h := c.r.next_double() * (8.0 - e - 4.0) + 2.0 + e / 2.0
		var ii := c.r.next_double() * (16.0 - f - 2.0) + 1.0 + f / 2.0
		for x in range(1, 15):
			for z in range(1, 15):
				for y in range(1, 7):
					var o := (x - g) / (d / 2.0)
					var q := (y - h) / (e / 2.0)
					var r := (z - ii) / (f / 2.0)
					if o * o + q * q + r * r < 1.0:
						grid[(x * 16 + z) * 8 + y] = 1
	var fluid := provide(c, cf["fluid"], p)
	if fluid <= 0:
		return false
	# Java LakeFeature: around the lake no liquid above the fluid line, below it only solid blocks or the lake's own
	# fluid (a lava lake on the sea surface / against water is rejected)
	for x in 16:
		for z in 16:
			for y in 8:
				if not _lake_edge(grid, x, y, z):
					continue
				var st := get_block(c, p + Vector3i(x, y, z))
				if y >= 4 and st > 0 and (blocks.st_flags[st] & BlockRegistry.F_LIQUID):
					return false
				if y < 4 and not (st > 0 and (blocks.st_flags[st] & BlockRegistry.F_COLLIDE) != 0) and st != fluid:
					return false
	for x in 16:
		for z in 16:
			for y in 8:
				if grid[(x * 16 + z) * 8 + y] == 1:
					var q2 := p + Vector3i(x, y, z)
					if test(c, cf["repl_af"], q2):
						set_block(c, q2, 0 if y >= 4 else fluid, W_FORCE)
	# barrier (lava lakes: stone) on the solid shell, above the fluid line on every other block at random
	var barrier := provide(c, cf["barrier"], p)
	if barrier > 0:
		for x in 16:
			for z in 16:
				for y in 8:
					if _lake_edge(grid, x, y, z) and (y < 4 or c.r.next_int_bound(2) != 0):
						var q3 := p + Vector3i(x, y, z)
						var st3 := get_block(c, q3)
						if st3 > 0 and (blocks.st_flags[st3] & BlockRegistry.F_COLLIDE) != 0 and test(c, cf["repl_bar"], q3):
							set_block(c, q3, barrier, W_FORCE)
	return true


static func _lake_edge(grid: PackedByteArray, x: int, y: int, z: int) -> bool:
	if grid[(x * 16 + z) * 8 + y] == 1:
		return false
	return (x < 15 and grid[((x + 1) * 16 + z) * 8 + y] == 1) or (x > 0 and grid[((x - 1) * 16 + z) * 8 + y] == 1) or (z < 15 and grid[(x * 16 + z + 1) * 8 + y] == 1) or (z > 0 and grid[(x * 16 + z - 1) * 8 + y] == 1) or (y < 7 and grid[(x * 16 + z) * 8 + y + 1] == 1) or (y > 0 and grid[(x * 16 + z) * 8 + y - 1] == 1)


func _veg_patch(c: FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var r := sample_int(c, cf["radius"]) + 1
	var tag := _tag_blocks(str(cf["replace_tag"]))
	var any := false
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if absi(dx) == r and absi(dz) == r and c.r.next_bool():
				continue
			var q := p + Vector3i(dx, -1, dz)
			var st := get_block(c, q)
			if st <= 0 or not tag.has(blocks.name_of(st)) or get_block(c, q + Vector3i(0, 1, 0)) != 0:
				continue
			set_block(c, q, provide(c, cf["ground"], q), W_FORCE)
			any = true
			if c.r.next_float() < float(cf["chance"]):
				_sub(c, cf["veg"], q + Vector3i(0, 1, 0))
	return any


func _lichen(c: FCtx, cf: Dictionary, p: Vector3i) -> bool:
	if get_block(c, p) != 0:
		return false
	var b: int = cf["block"]
	for d in [["down", Vector3i(0, -1, 0)], ["up", Vector3i(0, 1, 0)], ["north", Vector3i(0, 0, -1)], ["south", Vector3i(0, 0, 1)], ["west", Vector3i(-1, 0, 0)], ["east", Vector3i(1, 0, 0)]]:
		var s := get_block(c, p + d[1])
		if s > 0 and (blocks.st_flags[s] & BlockRegistry.F_FULL_SHAPE) != 0 and blocks.has_prop(b, d[0]):
			set_block(c, p, blocks.with_prop(b, d[0], "true"), W_AIR)
			return true
	return false


func _geode(c: FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var r := 3.0 + c.r.next_double() * 2.0
	var outer := r + 2.0
	var ir := int(ceil(outer))
	for dx in range(-ir, ir + 1):
		for dy in range(-ir, ir + 1):
			for dz in range(-ir, ir + 1):
				var dist := Vector3(dx, dy, dz).length()
				if dist > outer:
					continue
				var q := p + Vector3i(dx, dy, dz)
				var st := get_block(c, q)
				if st == 0 or (st > 0 and blocks.st_flags[st] & BlockRegistry.F_LIQUID):
					continue
				var prov: Dictionary
				if dist < r - 1.0:
					prov = cf["filling"]
				elif dist < r:
					prov = cf["inner"]
				elif dist < r + 1.0:
					prov = cf["middle"]
				else:
					prov = cf["outer"]
				set_block(c, q, provide(c, prov, q), W_FORCE)
	return true


func _dungeon(c: FCtx, p: Vector3i) -> bool:
	var rx := c.r.next_int_bound(2) + 2
	var rz := c.r.next_int_bound(2) + 2
	var openings := 0
	for x in range(-rx - 1, rx + 2):
		for y in range(-1, 5):
			for z in range(-rz - 1, rz + 2):
				var st := get_block(c, p + Vector3i(x, y, z))
				var solid := st > 0 and (blocks.st_flags[st] & BlockRegistry.F_COLLIDE) != 0
				if (y == -1 or y == 4) and not solid:
					return false
				if (absi(x) == rx + 1 or absi(z) == rz + 1) and y == 0 and st == 0 and get_block(c, p + Vector3i(x, 1, z)) == 0:
					openings += 1
	if openings < 1 or openings > 5:
		return false
	var cobble := blocks.default_state("cobblestone")
	var mossy := blocks.default_state("mossy_cobblestone")
	for x in range(-rx - 1, rx + 2):
		for y in range(3, -2, -1):
			for z in range(-rz - 1, rz + 2):
				var q := p + Vector3i(x, y, z)
				var wall := absi(x) == rx + 1 or y == -1 or absi(z) == rz + 1
				if not wall:
					set_block(c, q, 0, W_FORCE)
				elif y >= 0 and get_block(c, q + Vector3i(0, -1, 0)) <= 0:
					set_block(c, q, 0, W_FORCE)
				elif get_block(c, q) > 0:
					set_block(c, q, mossy if (y == -1 and c.r.next_int_bound(4) != 0) else cobble, W_FORCE)
	var sp := blocks.default_state("spawner")
	set_block(c, p, sp, W_FORCE)
	var chest := blocks.default_state("chest")
	for k in 2:
		var q2 := p + Vector3i(c.r.next_int_bound(rx * 2 + 1) - rx, 0, c.r.next_int_bound(rz * 2 + 1) - rz)
		if get_block(c, q2) == 0:
			set_block(c, q2, chest, W_AIR)
			c.block_entities[q2] = {"id": "chest", "loot_table": "chests/simple_dungeon", "loot_seed": c.r.next_long()}
	# Java MonsterRoomFeature: the spawner's mob is chosen after the chests' loot seeds
	c.block_entities[p] = {"id": "spawner", "mob": Trials.DUNGEON_MOBS[c.r.next_int_bound(4)]}
	return true


# ------------------------------------------------------------------ orchestration

static func decoration_seed(world_seed: int, x0: int, z0: int) -> int:
	var r := RandomSources.WorldgenXoro.seeded(world_seed)
	var l := r.next_long() | 1
	var m := r.next_long() | 1
	return (x0 * l + z0 * m) ^ world_seed


## Compute all feature writes originating in `origin` (reads only pristine 3x3 terrain).
func compute(origin: Chunk, region: ChunkRegion) -> PackedInt32Array:
	var c := FCtx.new()
	c.region = region
	bounds = []
	var tl0 := Time.get_ticks_usec() if profiling else 0
	if not legacy_region:
		_load_region(c, origin, region)
	if profiling:
		profile["<load region>"] = int(profile.get("<load region>", 0)) + Time.get_ticks_usec() - tl0
	c.origin_chunk = origin
	# Java applyBiomeDecoration: the features of every biome in the 3x3 chunks around the origin (each placement still
	# checks the biome at its own position)
	var present := {}
	for nc in (region.chunks if region != null and region.chunks.size() == 9 else [origin]):
		if nc == null:
			continue
		var nb: PackedByteArray = (nc as Chunk).biomes
		for b0 in biome_steps.size():
			if not present.has(b0) and nb.has(b0):   # (native scans: no per-byte script loop)
				present[b0] = true
	var deco := decoration_seed(gen.seed, origin.cx * 16, origin.cz * 16)
	var o := Vector3i(origin.cx * 16, Coords.MIN_Y, origin.cz * 16)
	# native feature engine for fully supported placed features (regions with legacy height data stay in GDScript)
	var nat := {}
	if Native.ok and Native.features_ok and not c.flat.is_empty() and native_engine:
		var legacy_h := false
		for ci in 9:
			if c.hstate[ci] == 1:
				legacy_h = true
		if not legacy_h:
			nat = FeaturesNative.shared(self)
	var nat_ids: Dictionary = nat.get("ids", {})
	var org := PackedInt32Array([o.x, o.y, o.z])
	for s in STEPS:
		if gen.aborted:
			return c.writes
		var names: Array = []
		var seen := {}
		for b in present:
			if b >= biome_steps.size():
				continue
			for nm in biome_steps[b][s]:
				if not seen.has(nm):
					seen[nm] = true
					names.append(nm)
		names.sort_custom(func(a, b): return int(step_index[s][a]) < int(step_index[s][b]))
		# Java ChunkGenerator.applyBiomeDecoration: a step's structures are placed before its features
		if gen.structures != null:
			if trace_names:
				printerr("[feat] structures step %d" % s)
			var tst := Time.get_ticks_usec() if profiling else 0
			if neighbour_structures:
				gen.structures.place_neighbour_view(c, origin, s)
			var nw0 := c.writes.size()
			gen.structures.place_step(c, origin, s, deco)
			if struct_record and c.writes.size() > nw0:
				_srm.lock()
				for k in range(nw0, c.writes.size(), 5):
					struct_writes.append_array([c.writes[k], c.writes[k + 1], c.writes[k + 2], c.writes[k + 3], c.writes[k + 4]])
				_srm.unlock()
			if profiling:
				profile["<structures step %d>" % s] = int(profile.get("<structures step %d>" % s, 0)) + Time.get_ticks_usec() - tst
		for nm in names:
			var pf: Dictionary = placed.get(nm, {})
			if pf.is_empty():
				continue
			c.r = RandomSources.WorldgenXoro.seeded(deco + int(step_index[s][nm]) + 10000 * s)
			c.placed_name = nm
			if trace_names:
				printerr("[feat] %s" % nm)
			var tp := Time.get_ticks_usec() if profiling else 0
			bounds.append([nm, c.writes.size()])
			var ni = nat_ids.get(nm)
			if profiling:
				var pk := "<native features>" if ni != null else "<gdscript features>"
				profile[pk + " n"] = int(profile.get(pk + " n", 0)) + 1
			if ni != null:
				var res: Array = Native.inst.fx_run(nat["handle"], ni[0], ni[1], c.flat, c.info, c.gs, c.gf, c.bio, [c.r.lo, c.r.hi], org, c.hl)
				c.r.lo = res[0]
				c.r.hi = res[1]
				c.writes.append_array(res[2])
				var bes: Array = res[3]
				for bk in range(0, bes.size(), 5):
					var bpos := Vector3i(bes[bk + 1], bes[bk + 2], bes[bk + 3])
					if int(bes[bk]) == 0:
						c.block_entities[bpos] = {"id": "chest", "loot_table": "chests/simple_dungeon", "loot_seed": int(bes[bk + 4])}
					else:
						c.block_entities[bpos] = {"id": "spawner", "mob": Trials.DUNGEON_MOBS[int(bes[bk + 4])]}
			else:
				place_placed(c, pf, o)
			if profiling:
				var dtp := Time.get_ticks_usec() - tp
				profile[nm] = int(profile.get(nm, 0)) + dtp
				var pk2 := "<native features>" if ni != null else "<gdscript features>"
				profile[pk2] = int(profile.get(pk2, 0)) + dtp
	origin.feature_bes = c.block_entities
	origin.feature_postproc = c.postproc
	origin.saved_entities.append_array(c.entities)
	return c.writes


## Job-private flat copy of the 3x3 region + pristine surfaces + biomes (FCtx); native expansion when available.
func _load_region(c: FCtx, origin: Chunk, region: ChunkRegion) -> void:
	c.fx0 = (origin.cx - 1) * 16
	c.fz0 = (origin.cz - 1) * 16
	c.has.resize(9)
	c.hstate.resize(9)
	c.gs.resize(2304)
	c.gf.resize(2304)
	c.bio.resize(9 * 1536)
	var secs: Array = []
	secs.resize(9)
	if Native.ok and Native.inst.has_method("region_meta") and not OS.has_environment("RC_NOMETA"):
		# surfaces / floors / biomes / primed heightmaps in one native call (the GDScript copy loops here were ~9 ms of
		# the ~16 ms feature job, contended across the workers)
		var sl: Array = []
		var fl: Array = []
		var bl: Array = []
		sl.resize(9)
		fl.resize(9)
		bl.resize(9)
		for ci in 9:
			var ch0: Chunk = region.chunks[ci]
			if ch0 == null:
				continue
			c.has[ci] = 1
			secs[ci] = ch0.raw_sections() if ch0.state < Chunk.DECORATED else ch0.snapshot()
			sl[ci] = ch0.gen_surface
			fl[ci] = ch0.gen_floor
			bl[ci] = ch0.biomes
		var rm: Array = Native.inst.region_meta(sl, fl, bl)
		c.gs = rm[0]
		c.gf = rm[1]
		c.bio = rm[2]
		c.hl = rm[3]
		c.hstate = rm[4]
		c.info = PackedInt32Array([c.fx0, c.fz0])
		for ci2 in 9:
			c.info.append(c.has[ci2])
		for ci3 in 9:
			c.info.append(c.hstate[ci3])
		c.flat = Native.inst.region_flat(secs)[0]
		return
	for ci in 9:
		var ch: Chunk = region.chunks[ci]
		if ch == null:
			continue
		c.has[ci] = 1
		# by reference only while nothing else can edit the chunk (packed arrays are shared by reference in Godot 4);
		# decorated neighbours (e.g. loaded from a save) can be edited on the main thread -> copy
		secs[ci] = ch.raw_sections() if ch.state < Chunk.DECORATED else ch.snapshot()   # snapshot: copy-on-write refs
		if ch.gen_surface.size() == 256:
			c.hstate[ci] = 2 if ch.gen_floor.size() == 256 else 1
			for k in 256:
				c.gs[ci * 256 + k] = ch.gen_surface[k]
			if ch.gen_floor.size() == 256:
				for k in 256:
					c.gf[ci * 256 + k] = ch.gen_floor[k]
		var bb := ch.biomes
		for k in mini(1536, bb.size()):
			c.bio[ci * 1536 + k] = bb[k]
	# live heightmaps primed from the pristine ones (the region holds pristine terrain: Chunk.raw for loaded chunks)
	c.hl.resize(4 * 2304)
	c.hl.fill(Coords.MIN_Y)
	for lz in 48:
		for lx in 48:
			var hci := (lz >> 4) * 3 + (lx >> 4)
			if c.hstate[hci] != 2:
				continue
			var hhi := hci * 256 + (lx & 15) + (lz & 15) * 16
			var col := lz * 48 + lx
			var top := c.gs[hhi] + 1
			c.hl[col] = top
			c.hl[2304 + col] = c.gf[hhi]
			c.hl[4608 + col] = top
			c.hl[6912 + col] = top
	c.info = PackedInt32Array([c.fx0, c.fz0])
	for ci in 9:
		c.info.append(c.has[ci])
	for ci in 9:
		c.info.append(c.hstate[ci])
	if Native.ok:
		c.flat = Native.inst.region_flat(secs)[0]
		return
	c.flat.resize(9 * 98304)
	for ci in 9:
		var ch2: Chunk = region.chunks[ci]
		if ch2 != null:
			var colv := Chunk.snapshot_column(ch2.snapshot())
			for k in 98304:
				c.flat[ci * 98304 + k] = colv[k]


## Apply the write lists of the 3x3 origins to the centre chunk (fixed order), then chunk-local freeze layer.
## Returns true when the native path ran (sections and final heightmap already installed).
func apply(center: Chunk, nine: Array) -> bool:
	var order: Array = []
	for ch in nine:
		if ch != null:
			order.append(ch)
	order.sort_custom(func(a, b): return a.cz < b.cz or (a.cz == b.cz and a.cx < b.cx))
	# this chunk's own writes last: its structure pieces must win over neighbours' features decided on pristine
	# terrain (Java: a neighbour's ore / tree placed first is overwritten by the piece, one placed later fails its
	# target test against the piece's blocks - either way the piece stays intact)
	for oi in order.size():
		if order[oi].cx == center.cx and order[oi].cz == center.cz:
			order.append(order.pop_at(oi))
			break
	var x0 := center.cx * 16
	var z0 := center.cz * 16
	# cross-origin carving beside another origin's liquid is skipped (same rule as the native chunk_decorate)
	var liq := {}
	var cave_air := blocks.default_state("cave_air")
	if not (Native.ok and Native.chunkops_ok):
		for oi2 in order.size():
			var wl2: PackedInt32Array = order[oi2].feature_writes
			for k2 in range(0, wl2.size(), 5):
				var lx2 := wl2[k2]
				var lz2 := wl2[k2 + 2]
				if lx2 < x0 - 1 or lx2 > x0 + 16 or lz2 < z0 - 1 or lz2 > z0 + 16:
					continue
				var ls2 := wl2[k2 + 3]
				if ls2 <= 0 or (blocks.st_flags[ls2] & BlockRegistry.F_LIQUID) == 0:
					continue
				var lk := Vector3i(lx2, wl2[k2 + 1], lz2)
				liq[lk] = oi2 if not liq.has(lk) or liq[lk] == oi2 else -2
	var om := ore_table()
	var oidx := -1
	for ch in order:
		oidx += 1
		var w: PackedInt32Array = ch.feature_writes
		for bp in ch.feature_bes:
			var bv: Vector3i = bp
			if bv.x >= x0 and bv.x < x0 + 16 and bv.z >= z0 and bv.z < z0 + 16:
				center.block_entities[BlockEntities._key(bv)] = (ch.feature_bes[bp] as Dictionary).duplicate()
		if Native.ok and Native.chunkops_ok:
			continue
		for k in range(0, w.size(), 5):
			var x := w[k]
			var z := w[k + 2]
			if x < x0 or x >= x0 + 16 or z < z0 or z >= z0 + 16:
				continue
			var y := w[k + 1]
			var st := w[k + 3]
			var mode := w[k + 4]
			if not liq.is_empty() and (st == 0 or st == cave_air) and _other_liquid(liq, x, y, z, oidx):
				continue
			if mode != W_FORCE:
				var cur := center.get_block(x & 15, y, z & 15)
				if not write_ok(mode, cur, blocks.st_flags, om):
					continue
			center.set_block(x & 15, y, z & 15, st)
	if Native.ok and Native.chunkops_ok:
		var wls: Array = []
		for ch2 in order:
			wls.append(ch2.feature_writes)
		if _temps.is_empty():
			for tv in gen.biomes.temperature:
				_temps.append(tv)
		var kc := PackedInt32Array([BlockRegistry.F_REPLACEABLE, BlockRegistry.F_LEAVES, BlockRegistry.F_FULL_SHAPE, blocks.WATER,
			blocks.default_state("ice"), blocks.default_state("snow"), blocks.block_id("ice"), blocks.block_id("packed_ice"), gen.sea_level,
			BlockRegistry.F_LIQUID, blocks.default_state("cave_air")] + _snowy_pairs() if not _no_poolfix else [])
		var res: Array = Native.inst.chunk_decorate(center.raw_sections(), wls, center.cx * 16, center.cz * 16, blocks.st_flags, blocks.st_opacity, kc,
			center.biomes, _temps, blocks.st_block, _leaf_info(), om)
		center.set_sections(res[0])
		center.heightmap = res[1]
		_post_process(center, nine)
		return true
	_leaf_distances(center, order)
	_freeze(center)
	_post_process(center, nine)
	return false


## GDScript twin of the native leaf distance pass (chunkops.cpp, TreeFeature.updateLeaves): breadth-first from logs
## through leaves, 6 steps, over the chunk and a 6-block margin taken from the origins' write lists.
func _leaf_distances(center: Chunk, order: Array) -> void:
	var lf := _leaf_info()
	var x0 := center.cx * 16
	var z0 := center.cz * 16
	var cls := {}   # Vector3i -> 1 log / 2 leaves
	for ch in order:
		var w: PackedInt32Array = ch.feature_writes
		for k in range(0, w.size(), 5):
			var x := w[k]
			var z := w[k + 2]
			if (x >= x0 and x < x0 + 16 and z >= z0 and z < z0 + 16) or x < x0 - 6 or x >= x0 + 22 or z < z0 - 6 or z >= z0 + 22:
				continue
			var c := lf[w[k + 3]] if w[k + 3] > 0 and w[k + 3] < lf.size() else 0
			var q := Vector3i(x, w[k + 1], z)
			if c == 0:
				cls.erase(q)
			else:
				cls[q] = 1 if c < 0 else 2
	var any := false
	for y in range(Coords.MIN_Y, Coords.MAX_Y):
		for lz in 16:
			for lx in 16:
				var st := center.get_block(lx, y, lz)
				if st <= 0 or st >= lf.size() or lf[st] == 0:
					continue
				cls[Vector3i(x0 + lx, y, z0 + lz)] = 1 if lf[st] < 0 else 2
				if lf[st] > 0:
					any = true
	if not any:
		return
	var dist := {}
	var queue: Array = []
	for q in cls:
		if cls[q] == 1:
			dist[q] = 0
			queue.append(q)
	var h := 0
	while h < queue.size():
		var c: Vector3i = queue[h]
		h += 1
		var d: int = int(dist[c]) + 1
		if d >= 7:
			continue
		for o in [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(0, -1, 0), Vector3i(0, 1, 0)]:
			var n: Vector3i = c + o
			if n.x < x0 - 6 or n.x >= x0 + 22 or n.z < z0 - 6 or n.z >= z0 + 22:
				continue
			if int(cls.get(n, 0)) != 2 or int(dist.get(n, 7)) <= d:
				continue
			dist[n] = d
			queue.append(n)
	for q in dist:
		var qv: Vector3i = q
		if qv.x < x0 or qv.x >= x0 + 16 or qv.z < z0 or qv.z >= z0 + 16 or int(dist[q]) == 0:
			continue
		var st2 := center.get_block(qv.x & 15, qv.y, qv.z & 15)
		var c2 := lf[st2]
		if c2 > 0:
			center.set_block(qv.x & 15, qv.y, qv.z & 15, st2 + (int(dist[q]) - (c2 & 15)) * (c2 >> 4))


## Per state for the native leaf distance pass (TreeFeature.updateLeaves): -1 for #logs, (distance stride << 4 | current
## distance) for leaves with a distance property, 0 otherwise. Built once.
static var _linfo := PackedInt32Array()
static var _linfo_m := Mutex.new()


func _leaf_info() -> PackedInt32Array:
	if _linfo.size() == blocks.total_states:
		return _linfo
	_linfo_m.lock()
	if _linfo.size() != blocks.total_states:
		var out := PackedInt32Array()
		out.resize(blocks.total_states)
		var logs := {}
		if Res.mode == "vanilla":
			for n in Tags.resolve("block", "#minecraft:logs"):
				logs[str(n).trim_prefix("minecraft:")] = true
		for st in blocks.total_states:
			var n2 := blocks.name_of(st)
			if logs.has(n2) or (logs.is_empty() and (n2.ends_with("_log") or n2.ends_with("_wood"))):
				out[st] = -1
			elif blocks.has_prop(st, "distance") and n2.ends_with("_leaves"):
				var cur := int(blocks.get_prop(st, "distance"))
				var stride := blocks.with_prop(st, "distance", "2") - blocks.with_prop(st, "distance", "1")
				out[st] = (stride << 4) | cur
		_linfo = out
	_linfo_m.unlock()
	return _linfo


## Java LevelChunk.postProcessGeneration: blocks a structure piece marked (fences, iron bars: StructurePiece
## SHAPE_CHECK_BLOCKS) take their shape from the finished neighbourhood (Block.updateFromNeighbourShapes). Runs at
## decoration, when every neighbour's features exist; a neighbour not decorated yet is read as its terrain plus its
## own feature writes.
func _post_process(center: Chunk, nine: Array) -> void:
	var src: Chunk = nine[4] if nine.size() > 4 and nine[4] != null else center
	var pp := src.feature_postproc
	if pp.is_empty():
		return
	var rd := _PPReader.new()
	rd.center = center
	rd.nine = nine
	for k in range(0, pp.size(), 3):
		var x := pp[k]
		var y := pp[k + 1]
		var z := pp[k + 2]
		var st := center.get_block(x & 15, y, z & 15)
		if st <= 0:
			continue
		var ns := ShapeUpdates.computed(rd, Vector3i(x, y, z), st)
		if ns != st:
			center.set_block(x & 15, y, z & 15, ns)


class _PPReader:
	var center: Chunk
	var nine: Array
	var _over: Dictionary = {}   # neighbour index -> {Vector3i: state} from its own feature writes

	func state_at(x: int, y: int, z: int) -> int:
		if y < Coords.MIN_Y or y >= Coords.MAX_Y:
			return 0
		var dx := (x >> 4) - center.cx
		var dz := (z >> 4) - center.cz
		if dx == 0 and dz == 0:
			return center.get_block(x & 15, y, z & 15)
		if absi(dx) > 1 or absi(dz) > 1:
			return 0
		var i := (dz + 1) * 3 + dx + 1
		var n: Chunk = nine[i]
		if n == null:
			return 0
		if n.decorated:
			return n.get_block(x & 15, y, z & 15)
		if not _over.has(i):
			var d := {}
			var w := n.feature_writes
			var x0 := n.cx * 16
			var z0 := n.cz * 16
			for k in range(0, w.size(), 5):
				if w[k] >= x0 and w[k] < x0 + 16 and w[k + 2] >= z0 and w[k + 2] < z0 + 16:
					d[Vector3i(w[k], w[k + 1], w[k + 2])] = w[k + 3]
			_over[i] = d
		var o = _over[i].get(Vector3i(x, y, z))
		return int(o) if o != null else n.get_block(x & 15, y, z & 15)


static var _no_poolfix := OS.get_environment("RC_NOPOOLFIX") != ""


static func _other_liquid(liq: Dictionary, x: int, y: int, z: int, li: int) -> bool:
	for d in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var o = liq.get(Vector3i(x, y, z) + d)
		if o != null and int(o) != li:
			return true
	return false


## SnowAndFreezeFeature: blocks with a SNOWY property (grass block, podzol, mycelium) under new snow -> [n, false, true]*.
func _snowy_pairs() -> Array:
	var out: Array = [0]
	for nm in ["grass_block", "podzol", "mycelium"]:
		var s0 := blocks.default_state(nm)
		if s0 > 0 and blocks.has_prop(s0, "snowy"):
			out.append_array([blocks.with_prop(s0, "snowy", "false"), blocks.with_prop(s0, "snowy", "true")])
			out[0] += 1
	return out


func _freeze(ch: Chunk) -> void:
	var snow := blocks.default_state("snow")
	var ice := blocks.default_state("ice")
	ch.recompute_heightmap(blocks)
	for lz in 16:
		for lx in 16:
			var y := ch.heightmap[lx + lz * 16]
			var top := ch.get_block(lx, y - 1, lz)
			var b := ch.biome_at(lx, y, lz)
			if gen.biome_temperature_at(b, 0, y, 0) >= 0.15:
				continue
			if top == blocks.WATER:
				ch.set_block(lx, y - 1, lz, ice)
			elif top > 0 and ch.get_block(lx, y, lz) == 0 and (blocks.st_flags[top] & (BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_LEAVES)) != 0:
				var tn := blocks.name_of(top)
				if tn != "ice" and tn != "packed_ice":
					ch.set_block(lx, y, lz, snow)
					if blocks.has_prop(top, "snowy"):
						ch.set_block(lx, y - 1, lz, blocks.with_prop(top, "snowy", "true"))


## Compatibility entry for the old single-pass decorate (used if the chunk manager has no features stage).
func decorate(ch: Chunk, region: ChunkRegion) -> void:
	apply(ch, region.chunks)
