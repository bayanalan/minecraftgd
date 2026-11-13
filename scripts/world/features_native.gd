## FeaturesNative — flattens compiled Features dictionaries into int/float arrays for the native feature engine
## (RecraftNative.fx_*, native/src/featx.cpp). A top-level placed feature is exported only if its whole tree
## (modifiers, configured features, block state providers, block predicates, int/height providers) is supported;
## everything else keeps running in GDScript. Every node mirrors the GDScript semantics in features.gd exactly
## (verified write-for-write by --nativecheck). The export is built once and shared by all worker generators.
## Contract: FeaturesNative.shared(features) -> {"handle": int, "ids": {placed name: [pf offset, biome set offset]}}.
class_name FeaturesNative
extends RefCounted

const IP_CONST := 0
const IP_UNIFORM := 1
const IP_BIASED := 2
const IP_CLAMPED := 3
const IP_CLAMPED_NORMAL := 4
const IP_WEIGHTED := 5
const IP_TRAPEZOID := 6

static var _shared: Dictionary = {}   # key -> {"handle", "ids"}
static var _sm := Mutex.new()
static var _building: Dictionary = {}   # key -> true while one thread builds the export

var f: Features
var b: BlockRegistry
var I := PackedInt32Array()
var F := PackedFloat64Array()
var M := PackedByteArray()          # per-state masks (vegetation patch replace tags)
var BS := PackedByteArray()         # per top-level feature biome sets
var ok := true
var why := ""
var why_hist := {}     # reason -> [count, example feature]
var nb := 0
var _mask_off := {}


static func shared(fe: Features) -> Dictionary:
	if not Native.ok:
		return {}
	var key := "%d|%s|%s" % [fe.gen.seed, fe.gen.dimension, str(fe.gen.settings.get("world_type", ""))]
	_sm.lock()
	if _shared.has(key):
		var v: Dictionary = _shared[key]
		_sm.unlock()
		return v
	if _building.has(key):
		_sm.unlock()
		var tw := Time.get_ticks_msec()
		while Time.get_ticks_msec() - tw < 15000:
			OS.delay_msec(2)
			_sm.lock()
			if _shared.has(key):
				var v2: Dictionary = _shared[key]
				_sm.unlock()
				return v2
			_sm.unlock()
		return {}   # builder failed or too slow: this compute runs in GDScript
	_building[key] = true
	_sm.unlock()
	# built outside the lock (a failure can never leave other threads blocked); first published result wins
	var ex := FeaturesNative.new()
	var res := ex.build(fe)
	if res.is_empty() or not res.has("ids"):
		return {}
	_sm.lock()
	if _shared.has(key):
		res = _shared[key]
	else:
		_shared[key] = res
	_sm.unlock()
	return res


func build(fe: Features) -> Dictionary:
	f = fe
	b = fe.blocks
	nb = fe.gen.biomes.names.size()
	var ids := {}
	var names: Array = fe.placed.keys()
	names.sort()
	for nm in names:
		if not fe.feature_biomes.has(nm):
			continue
		ok = true
		why = ""
		var mark := I.size()
		var fmark := F.size()
		var pf := emit_pf(fe.placed[nm])
		if not ok or pf < 0:
			var e: Array = why_hist.get(why, [0, nm])
			e[0] += 1
			why_hist[why] = e
			I.resize(mark)
			F.resize(fmark)
			continue
		var bso := BS.size()
		var bs := PackedByteArray()
		bs.resize(nb)
		for bid in fe.feature_biomes[nm]:
			if int(bid) >= 0 and int(bid) < nb:
				bs[int(bid)] = 1
		BS.append_array(bs)
		ids[nm] = [pf, bso]
	if F.is_empty():
		F.append(0.0)
	var tables := _state_tables()
	var h: int = int(Native.inst.fx_config([I, F, M, BS, b.st_flags, b.st_block, tables[0], tables[1], tables[2], tables[3],
		PackedInt32Array([BlockRegistry.F_LIQUID, BlockRegistry.F_WATERLOGGED, BlockRegistry.F_COLLIDE, BlockRegistry.F_REPLACEABLE,
		BlockRegistry.F_FULL_SHAPE, BlockRegistry.F_OPAQUE, BlockRegistry.F_LAVA, fe.gen.gen_min_y, fe.gen.gen_depth, BlockRegistry.F_LEAVES]), fe.simplex_info.p, tables[4], tables[5]])[0])
	return {"handle": h, "ids": ids, "count": ids.size(), "of": fe.feature_biomes.size(), "why": why_hist}


func _node(v: Array) -> int:
	var o := I.size()
	for x in v:
		I.append(int(x))
	return o


func _fl(x: float) -> int:
	F.append(x)
	return F.size() - 1


# ------------------------------------------------------------------ int / height providers (Features.sample_int / sample_height)

func emit_ip(v) -> int:
	if v is int or v is float:
		return _node([IP_CONST, int(v)])
	if not (v is Dictionary):
		return _node([IP_CONST, 0])
	var t := str(v.get("type", "constant")).trim_prefix("minecraft:")
	match t:
		"constant":
			return _node([IP_CONST, int(v.get("value", 0))])
		"uniform":
			var lo := int(v.get("min_inclusive", v.get("value", {}).get("min_inclusive", 0) if v.get("value") is Dictionary else 0))
			var hi := int(v.get("max_inclusive", v.get("value", {}).get("max_inclusive", 0) if v.get("value") is Dictionary else 0))
			return _node([IP_UNIFORM, lo, hi])
		"biased_to_bottom":
			return _node([IP_BIASED, int(v.get("min_inclusive", 0)), int(v.get("max_inclusive", 0))])
		"clamped":
			var src := emit_ip(v.get("source", 0))
			return _node([IP_CLAMPED, src, int(v.get("min_inclusive", -2147483648)), int(v.get("max_inclusive", 2147483647))])
		"clamped_normal":
			var fm := _fl(float(v.get("mean", 0.0)))
			var fd := _fl(float(v.get("deviation", 1.0)))
			return _node([IP_CLAMPED_NORMAL, fm, fd, int(v.get("min_inclusive", -2147483648)), int(v.get("max_inclusive", 2147483647))])
		"weighted_list":
			var ents: Array = []
			for e in v.get("distribution", []):
				ents.append([int(e.get("weight", 1)), emit_ip(e.get("data", 0))])
			var nd := [IP_WEIGHTED, ents.size()]
			for e in ents:
				nd.append_array(e)
			return _node(nd)
		"trapezoid":
			return _node([IP_TRAPEZOID, int(v.get("min", v.get("min_inclusive", 0))), int(v.get("max", v.get("max_inclusive", 0))), int(v.get("plateau", 0))])
	return _node([IP_CONST, 0])


## FeaturesCave._fs float providers: [kind, F a, F b, F c, F d] (0 const, 1 uniform, 2 clamped_normal, 3 trapezoid).
func emit_fp(v) -> int:
	if v is int or v is float:
		return _node([0, _fl(float(v)), 0, 0, 0])
	if not (v is Dictionary):
		return _node([0, _fl(0.0), 0, 0, 0])
	match str(v.get("type", "constant")).trim_prefix("minecraft:"):
		"constant":
			return _node([0, _fl(float(v.get("value", 0.0))), 0, 0, 0])
		"uniform":
			return _node([1, _fl(float(v.get("min_inclusive", 0.0))), _fl(float(v.get("max_exclusive", 1.0))), 0, 0])
		"clamped_normal":
			return _node([2, _fl(float(v.get("mean", 0.0))), _fl(float(v.get("deviation", 1.0))), _fl(float(v.get("min", -1e9))), _fl(float(v.get("max", 1e9)))])
		"trapezoid":
			return _node([3, _fl(float(v.get("min", 0.0))), _fl(float(v.get("max", 0.0))), _fl(float(v.get("plateau", 0.0))), 0])
	return _node([0, _fl(0.0), 0, 0, 0])


func emit_hp(v) -> int:
	if not (v is Dictionary):
		return _node([0, 0])
	var t := str(v.get("type", "constant")).trim_prefix("minecraft:")
	if t == "constant" or v.has("absolute") or v.has("above_bottom") or v.has("below_top"):
		return _node([0, f._anchor(v.get("value", v))])
	var i := f._anchor(v.get("min_inclusive", {}))
	var j := f._anchor(v.get("max_inclusive", {}))
	match t:
		"uniform":
			return _node([1, i, j, 0])
		"trapezoid":
			return _node([2, i, j, int(v.get("plateau", 0))])
		"biased_to_bottom":
			return _node([3, i, j, int(v.get("inner", 1))])
		"very_biased_to_bottom":
			return _node([4, i, j, int(v.get("inner", 1))])
	return _node([0, i])


# ------------------------------------------------------------------ predicates (Features.test) and rule tests (rule_test)

## Heightmap kind codes of the native engine (featx Fx::height): pristine *_WG 0 / 1, live 2..5 (Features.height).
static func _hm_code(nm: String) -> int:
	match nm:
		"WORLD_SURFACE_WG":
			return 0
		"OCEAN_FLOOR_WG":
			return 1
		"WORLD_SURFACE":
			return 2
		"OCEAN_FLOOR":
			return 3
		"MOTION_BLOCKING":
			return 4
		"MOTION_BLOCKING_NO_LEAVES":
			return 5
	return 1 if nm.begins_with("OCEAN_FLOOR") else 0


func emit_pr(pd: Dictionary) -> int:
	var off: Vector3i = pd.get("off", Vector3i.ZERO)
	var base := [0, off.x, off.y, off.z]
	match str(pd["t"]):
		"true":
			base[0] = 0
		"blocks":
			base[0] = 1
			var ids: Dictionary = pd["ids"]
			base.append(ids.size())
			for k in ids:
				base.append(int(k))
		"fluids":
			base[0] = 2
			base.append_array([1 if pd["lava"] else 0, 1 if pd["water"] else 0])
		"solid":
			base[0] = 3
		"replaceable":
			base[0] = 4
		"survive":
			base[0] = 5
			base.append(int(pd["s"]))
		"sturdy":
			base[0] = 6
		"bounds":
			base[0] = 7
		"hrange":
			base[0] = 8
			base.append_array([int(pd["lo"]), int(pd["hi"])])
		"all_of", "any_of":
			var kids: Array = []
			for sp in pd["ps"]:
				kids.append(emit_pr(sp))
			base = [9 if str(pd["t"]) == "all_of" else 10, 0, 0, 0, kids.size()]
			base.append_array(kids)
		"not":
			var kid := emit_pr(pd["p"])
			base = [11, 0, 0, 0, kid]
		_:
			base[0] = 0
	return _node(base)


func emit_rt(rt: Dictionary) -> int:
	match str(rt["t"]):
		"true":
			return _node([0])
		"ids", "rand":
			var ids: Dictionary = rt["ids"]
			var nd := [1 if str(rt["t"]) == "ids" else 3, ids.size()]
			for k in ids:
				nd.append(int(k))
			if str(rt["t"]) == "rand":
				nd.append(_fl(float(rt["p"])))
			return _node(nd)
		"state":
			return _node([2, int(rt["s"])])
		"height":
			return _node([4, int(rt["lo"]), int(rt["hi"])])
		"any_of", "all_of":
			var kids: Array = []
			for sub in rt["rs"]:
				kids.append(emit_rt(sub))
			var nd2 := [5 if str(rt["t"]) == "any_of" else 6, kids.size()]
			nd2.append_array(kids)
			return _node(nd2)
		"not":
			return _node([7, emit_rt(rt["r"])])
	return _node([0])


# ------------------------------------------------------------------ block state providers (Features.provide)

func emit_pv(pv: Dictionary) -> int:
	match str(pv.get("t", "simple")):
		"simple":
			return _node([0, int(pv["s"])])
		"weighted":
			var ents: Array = []
			for e in pv["e"]:
				ents.append([int(e[0]), emit_pv(e[1])])
			var nd := [1, ents.size()]
			for e in ents:
				nd.append_array(e)
			return _node(nd)
		"rule":
			var rules: Array = []
			for rr in pv["rules"]:
				rules.append([emit_pr(rr[0]), emit_pv(rr[1])])
			var fb := -1
			if not (pv["fallback"] as Dictionary).is_empty():
				fb = emit_pv(pv["fallback"])
			var nd2 := [2, rules.size()]
			for r in rules:
				nd2.append_array(r)
			nd2.append(fb)
			return _node(nd2)
		"rint":
			# with_prop(s, prop, str(v)) precomputed for every state the source can produce and every value v
			var src: Dictionary = pv["src"]
			var states := {}
			if not _pv_states(src, states):
				ok = false
				return _node([0, 0])
			var vr := _ip_range(pv["vals"])
			if vr.is_empty():
				ok = false
				return _node([0, 0])
			var srcn := emit_pv(src)
			var vals := emit_ip(pv["vals"])
			var prop := str(pv["prop"])
			var nd3 := [3, srcn, vals, vr[0], vr[1], states.size()]
			for s in states:
				var st := int(s)
				var has := st > 0 and b.has_prop(st, prop)
				nd3.append_array([st, 1 if has else 0])
				for v in range(vr[0], vr[1] + 1):
					nd3.append(b.with_prop(st, prop, str(v)) if has else st)
			return _node(nd3)
	ok = false   # noise providers: not ported yet
	if why == "":
		why = "provider " + str(pv.get("t", "?"))
	return _node([0, 0])


func _pv_states(pv: Dictionary, out: Dictionary) -> bool:
	match str(pv.get("t", "simple")):
		"simple":
			out[int(pv["s"])] = true
			return true
		"weighted":
			for e in pv["e"]:
				if not _pv_states(e[1], out):
					return false
			return true
	return false


func _ip_range(v) -> Array:
	if v is int or v is float:
		return [int(v), int(v)]
	if not (v is Dictionary):
		return [0, 0]
	var t := str(v.get("type", "constant")).trim_prefix("minecraft:")
	if t == "constant":
		return [int(v.get("value", 0)), int(v.get("value", 0))]
	if t == "uniform":
		var lo := int(v.get("min_inclusive", v.get("value", {}).get("min_inclusive", 0) if v.get("value") is Dictionary else 0))
		var hi := int(v.get("max_inclusive", v.get("value", {}).get("max_inclusive", 0) if v.get("value") is Dictionary else 0))
		return [mini(lo, hi), maxi(lo, hi)]
	return []


# ------------------------------------------------------------------ placed features, modifiers, configured features

func emit_pf(pf: Dictionary) -> int:
	if pf.is_empty():
		return -1
	var mods: Array = []
	for m in pf.get("mods", []):
		mods.append(emit_mod(m))
	var cf := emit_cf(pf.get("cf", {"t": "none"}))
	var nd := [mods.size()]
	nd.append_array(mods)
	nd.append(cf)
	return _node(nd)


func emit_mod(m: Dictionary) -> int:
	var raw: Dictionary = m.get("raw", {})
	match str(m["t"]):
		"count":
			return _node([1, emit_ip(raw.get("count", 1))])
		"in_square":
			return _node([2])
		"rarity_filter":
			return _node([3, _fl(1.0 / float(raw.get("chance", 1)))])
		"height_range":
			return _node([4, emit_hp(raw.get("height", {}))])
		"heightmap":
			return _node([5, _hm_code(str(raw.get("heightmap", "WORLD_SURFACE_WG")))])
		"biome":
			return _node([6])
		"surface_water_depth_filter":
			return _node([7, int(raw.get("max_water_depth", 0))])
		"block_predicate_filter":
			return _node([8, emit_pr(m["pred"])])
		"offset":
			var ox := emit_ip(raw.get("x", 0))
			var oy := emit_ip(raw.get("y", 0))
			var oz := emit_ip(raw.get("z", 0))
			return _node([9, ox, oy, oz])
		"random_offset":
			var rxz := emit_ip(raw.get("xz_spread", 0))
			var ry := emit_ip(raw.get("y_spread", 0))
			return _node([10, rxz, ry])
		"environment_scan":
			var dirs := {"up": 1, "down": -1}
			var dy: int = dirs.get(str(raw.get("direction_of_search", "down")), -1)
			var tg := emit_pr(m["target"])
			var al := emit_pr(m["allowed"])
			return _node([11, dy, int(raw.get("max_steps", 12)), tg, al])
		"surface_relative_threshold_filter":
			var oc := _hm_code(str(raw.get("heightmap", "OCEAN_FLOOR_WG")))
			return _node([12, oc, 1 if raw.has("min_inclusive") else 0, int(raw.get("min_inclusive", -2147483648)) if raw.has("min_inclusive") else 0,
				1 if raw.has("max_inclusive") else 0, int(raw.get("max_inclusive", 2147483647)) if raw.has("max_inclusive") else 0])
		"random_chance":
			return _node([13, _fl(float(raw.get("chance", 1.0)))])
		"noise_threshold_count":
			return _node([14, _fl(float(raw.get("noise_level", 0.0))), int(raw.get("below_noise", 0)), int(raw.get("above_noise", 0))])
		"noise_based_count":
			return _node([15, _fl(float(raw.get("noise_factor", 1.0))), _fl(float(raw.get("noise_offset", 0.0))), int(raw.get("noise_to_count_ratio", 1))])
		"count_on_every_layer":
			return _node([16, emit_ip(raw.get("count", 1)), _hm_code("MOTION_BLOCKING"), b.block_id("bedrock")])
		"randomly_selected", "cuboid", "fixed_placement":
			ok = false
			if why == "":
				why = "modifier " + str(m["t"])
			return _node([0])
	return _node([0])


func emit_cf(cf: Dictionary) -> int:
	var t := str(cf.get("t", "none"))
	match t:
		"none":
			return _node([0])
		"ore", "scattered_ore":
			var tg: Array = []
			for x in cf["targets"]:
				tg.append([emit_rt(x[0]), int(x[1])])
			var nd := [1 if t == "ore" else 2, int(cf["size"]), _fl(float(cf["discard"])), tg.size()]
			for x in tg:
				nd.append_array(x)
			return _node(nd)
		"simple_block":
			return _node([3, emit_pv(cf["prov"])])
		"random_selector":
			var es: Array = []
			for e in cf["fs"]:
				es.append([_fl(float(e[0])), emit_pf(e[1])])
			var dflt := emit_pf(cf["default"])
			var nd2 := [4, es.size()]
			for e in es:
				nd2.append_array(e)
			nd2.append(dflt)
			return _node(nd2)
		"weighted_random_selector":
			var ws: Array = []
			for e in cf["ws"]:
				ws.append([int(e[0]), emit_pf(e[1])])
			var nd3 := [5, ws.size()]
			for e in ws:
				nd3.append_array(e)
			return _node(nd3)
		"simple_random_selector":
			var ss: Array = []
			for e in cf["ss"]:
				ss.append(emit_pf(e))
			var nd4 := [6, ss.size()]
			nd4.append_array(ss)
			return _node(nd4)
		"random_boolean_selector":
			var pa := emit_pf(cf["a"])
			var pb := emit_pf(cf["b"])
			return _node([7, pa, pb])
		"sequence":
			var sq: Array = []
			for e in cf["seq"]:
				sq.append(emit_pf(e))
			var nd5 := [8, sq.size()]
			nd5.append_array(sq)
			return _node(nd5)
		"block_column":
			var al := emit_pr(cf["allowed"])
			var ls: Array = []
			for l in cf["layers"]:
				ls.append([emit_ip(l[0]), emit_pv(l[1])])
			var nd6 := [9, 1 if cf["dir"] == "up" else -1, al, ls.size()]
			for l in ls:
				nd6.append_array(l)
			return _node(nd6)
		"disk":
			var pv := emit_pv(cf["prov"])
			var tp := emit_pr(cf["target"])
			var rad := emit_ip(cf["radius"])
			return _node([10, pv, tp, rad, int(cf["half"])])
		"vegetation_patch", "waterlogged_vegetation_patch":
			var gpv := emit_pv(cf["ground"])
			var veg := emit_pf(cf["veg"])
			var rad2 := emit_ip(cf["radius"])
			return _node([11, gpv, veg, _mask(str(cf["replace_tag"])), rad2, _fl(float(cf["chance"]))])
		"multiface_growth":
			var bst: int = cf["block"]
			var nd7 := [12]
			for dn in ["down", "up", "north", "south", "west", "east"]:
				nd7.append(b.with_prop(bst, dn, "true") if bst > 0 and b.has_prop(bst, dn) else -1)
			return _node(nd7)
		"block_pile":
			return _node([13, emit_pv(cf["prov"])])
		"underwater_magma":
			return _node([14, int(cf["range"]), int(cf["radius"]), _fl(float(cf["prob"])), b.block_id("water"), b.default_state("magma_block")])
		"vines":
			var vine := b.default_state("vine")
			var nd8 := [15]
			for dn2 in ["north", "east", "south", "west", "up"]:
				nd8.append(b.with_prop(vine, dn2, "true"))
			return _node(nd8)
		"spring_feature":
			var vb: Dictionary = cf["valid"]
			var st0: int = cf["state"]
			var nd9 := [16, 1 if cf["below"] else 0, int(cf["rock"]), int(cf["hole"]), b.default_state(b.name_of(st0)), vb.size()]
			for k in vb:
				nd9.append(int(k))
			return _node(nd9)
		"monster_room":
			return _node([17, b.default_state("cobblestone"), b.default_state("mossy_cobblestone"), b.default_state("spawner"), b.default_state("chest")])
		"freeze_top_layer":
			return _node([18])
		"lake":
			return _node([20, emit_pv(cf["fluid"]), emit_pv(cf["barrier"]), emit_pr(cf["repl_af"]), emit_pr(cf["repl_bar"])])
		"speleothem_cluster":
			var ccfg: Dictionary = cf["cfg"]
			var ndc := [24, int(cf["base"]), int(cf["base_b"]), int(cf["w"]), int(cf["ca"]), int(cf["va"]), 0, 0, 0, 0]
			var cps: Dictionary = cf["ps"]
			for up in [true, false]:
				for th in FeaturesCave.THICK:
					for wv in [false, true]:
						ndc.append(int(cps[FeaturesCave._pk(up, th, wv)]))
			var crp: Dictionary = cf["repl"]
			ndc.append(crp.size())
			for k in crp:
				ndc.append(int(k))
			var thick_v = ccfg.get("speleothem_block_layer_thickness", ccfg.get("dripstone_block_layer_thickness", 3))
			ndc.append_array([int(cf["l"]), int(cf["pointed_b"]), b.default_state("water"), emit_ip(ccfg.get("height", 6)),
				emit_fp(ccfg.get("wetness", 0.0)), emit_fp(ccfg.get("density", 0.5)), emit_ip(ccfg.get("radius", 4)),
				_fl(float(ccfg.get("max_distance_from_edge_affecting_chance_of_speleothem", ccfg.get("max_distance_from_edge_affecting_chance_of_dripstone_column", 3)))),
				_fl(float(ccfg.get("chance_of_speleothem_at_max_distance_from_center", ccfg.get("chance_of_dripstone_column_at_max_distance_from_center", 0.1)))),
				int(ccfg.get("floor_to_ceiling_search_range", 12)), emit_ip(thick_v), int(ccfg.get("max_stalagmite_stalactite_height_diff", 1)),
				_fl(float(ccfg.get("max_distance_from_center_affecting_height_bias", 8))), _fl(float(ccfg.get("height_deviation", 3)))])
			var stn: Dictionary = cf["stone"]
			ndc.append(stn.size())
			for k in stn:
				ndc.append(int(k))
			return _node(ndc)
		"tree":
			return emit_tree(cf)
		"fallen_tree":
			var ax := _axis_table(cf["trunk"])
			if ax.is_empty():
				ok = false
				return _node([0])
			var nd11 := [23, emit_pv(cf["trunk"]), emit_ip(cf["len"]), ax.size() / 4]
			nd11.append_array(ax)
			return _node(nd11)
		"huge_brown_mushroom", "huge_red_mushroom":
			# + #dirt / #mushroom_grow_block masks and the cap state per face bitmask (up 1, north 2, south 4, east 8, west 16)
			# for a simple cap provider (else -1: the provider's state as is)
			var capt := PackedInt32Array()
			capt.resize(32)
			capt.fill(-1)
			var cpv: Dictionary = cf["cap"]
			if str(cpv.get("t", "")) == "simple" and b.has_prop(int(cpv["s"]), "west"):
				for fb in 32:
					var cs := int(cpv["s"])
					var ks := ["up", "north", "south", "east", "west"]
					for ki in 5:
						if ki == 0 and t != "huge_red_mushroom":
							continue   # brown: up / down stay as the provider has them
						cs = b.with_prop(cs, ks[ki], "true" if fb & (1 << ki) else "false")
					capt[fb] = cs
			var nd := [22, 1 if t == "huge_red_mushroom" else 0, emit_pv(cf["stem"]), emit_pv(cf["cap"]), int(cf["radius"]), _mask("dirt"), _mask("mushroom_grow_block")]
			nd.append_array(capt)
			return _node(nd)
		"speleothem":
			var cfg: Dictionary = cf["cfg"]
			var nd10 := [19, int(cf["base"]), int(cf["base_b"]), int(cf["w"]), int(cf["ca"]), int(cf["va"]),
				_fl(float(cfg.get("chance_of_directional_spread", 0.7))), _fl(float(cfg.get("chance_of_spread_radius2", 0.5))),
				_fl(float(cfg.get("chance_of_spread_radius3", 0.5))), _fl(float(cfg.get("chance_of_taller_dripstone", 0.2)))]
			var ps: Dictionary = cf["ps"]
			for up in [true, false]:
				for th in FeaturesCave.THICK:
					for wv in [false, true]:
						nd10.append(int(ps[FeaturesCave._pk(up, th, wv)]))
			var rp: Dictionary = cf["repl"]
			nd10.append(rp.size())
			for k in rp:
				nd10.append(int(k))
			return _node(nd10)
		# 26.3 Nether types (FeaturesExt; node layouts in featx.cpp)
		"netherrack_replace_blobs":
			return _node([25, int(cf["target"]), int(cf["state"]), emit_ip(cf["radius"])])
		"delta_feature":
			var bad: Array = []
			for bn in ["bedrock", "nether_bricks", "nether_brick_fence", "nether_brick_stairs", "nether_wart", "chest", "spawner"]:
				var bid := b.block_id(bn)
				if bid >= 0:
					bad.append(bid)
			var ndd := [26, int(cf["contents"]), int(cf["rim"]), emit_ip(cf["size"]), emit_ip(cf["rim_size"]), b.st_block[maxi(int(cf["contents"]), 0)], bad.size()]
			ndd.append_array(bad)
			return _node(ndd)
		"stepped_column_cluster":
			var cannot: Dictionary = cf["cannot_on"]
			var ndc2 := [27, emit_pv(cf["block"]), emit_pr(cf["can_replace"]), emit_pr(cf["continue"]), int(cf["cluster_reach"]),
				int(cf["column_count"]), emit_ip(cf["column_reach"]), emit_ip(cf["height"]), cannot.size()]
			for k2 in cannot:
				ndc2.append(int(k2))
			return _node(ndc2)
		"single_block_pillar":
			var cap: Dictionary = cf["cap"]
			var cap_n := -1
			if not cap.is_empty():
				cap_n = emit_pf(cap)
			return _node([28, emit_pv(cf["block"]), emit_pr(cf["can_replace"]), (cf["dir"] as Vector3i).y, _fl(float(cf["chance"])), cap_n])
		"projected_random_patchy_square":
			return _node([29, emit_pv(cf["block"]), int(cf["size"]), int(cf["proj"]), emit_pr(cf["through"])])
		"random_neighbor_spread":
			var accd: Dictionary = cf["accepted"]
			var nds := [30, emit_pv(cf["block"]), emit_pr(cf["can_replace"]), int(cf["attempts"]), emit_ip(cf["xz"]), emit_ip(cf["y"]), accd.size()]
			for k3 in accd:
				nds.append(int(k3))
			return _node(nds)
		"sculk_patch":
			# SculkPatchFeature (featx kind 32): config, growth / water states, block ids, the 128 sculk vein states
			# (local index -> face mask | waterlogged << 6 and back), #sculk_replaceable_world_gen ids (sorted)
			var raw: Dictionary = cf.get("raw", {})
			var vein_b := b.block_id("sculk_vein")
			if vein_b < 0:
				ok = false
				why = "sculk_vein missing"
				return _node([0])
			var first: int = b.block_first[vein_b]
			var local := PackedInt32Array()
			local.resize(128)
			var bycode := PackedInt32Array()
			bycode.resize(128)
			var dn := ["down", "up", "north", "south", "west", "east"]
			for k in 128:
				var vs := first + k
				var m := 0
				for d in 6:
					if b.get_prop(vs, dn[d]) == "true":
						m |= 1 << d
				if b.get_prop(vs, "waterlogged") == "true":
					m |= 64
				local[k] = m
				bycode[m] = vs
			var sensor := b.default_state("sculk_sensor")
			var shriek := b.with_prop(b.default_state("sculk_shrieker"), "can_summon", "true")
			var nsk := [32, int(raw.get("charge_count", 10)), int(raw.get("amount_per_charge", 32)), int(raw.get("spread_attempts", 64)),
				int(raw.get("growth_rounds", 0)), int(raw.get("spread_rounds", 1)), emit_ip(raw["extra_rare_growths"]) if raw.has("extra_rare_growths") else -1,
				b.default_state("sculk"), b.with_prop(sensor, "waterlogged", "false"), b.with_prop(sensor, "waterlogged", "true"),
				b.with_prop(shriek, "waterlogged", "false"), b.with_prop(shriek, "waterlogged", "true"), b.WATER,
				b.block_id("sculk"), vein_b, b.block_id("sculk_catalyst"), b.block_id("moving_piston"), b.block_id("water"),
				b.block_id("sculk_sensor"), b.block_id("sculk_shrieker"), b.block_id("fire"), b.block_id("soul_fire"), first]
			nsk.append_array(local)
			nsk.append_array(bycode)
			var rep: Array = []
			for nm in Tags.blocks("#minecraft:sculk_replaceable_world_gen"):
				var rb := b.block_id(nm)
				if rb >= 0:
					rep.append(rb)
			rep.sort()
			nsk.append(rep.size())
			nsk.append_array(rep)
			return _node(nsk)
		"huge_fungus":
			var tip := b.default_state("weeping_vines")
			var ndf := [31, int(cf["stem"]), int(cf["hat"]), int(cf["decor"]), int(cf["base"]), emit_pr(cf["replace"]), 1 if cf["planted"] else 0,
				1 if b.name_of(int(cf["hat"])) == "nether_wart_block" else 0, b.default_state("weeping_vines_plant")]
			for age in [23, 24, 25]:
				ndf.append(b.with_prop(tip, "age", str(age)))
			return _node(ndf)
	ok = false
	if why == "":
		why = "feature " + t
	return _node([0])


## Trunk provider states -> [state, axis=y, axis=x, axis=z] (Trees._log: with_prop(s, "axis", axis) when it has one).
func _axis_table(pv: Dictionary) -> PackedInt32Array:
	var states := {}
	if not _pv_states(pv, states):
		return PackedInt32Array()
	var out := PackedInt32Array()
	for s in states:
		var st := int(s)
		var has := st > 0 and b.has_prop(st, "axis")
		out.append_array([st, b.with_prop(st, "axis", "y") if has else st, b.with_prop(st, "axis", "x") if has else st, b.with_prop(st, "axis", "z") if has else st])
	return out


const TRUNKS := {"straight_trunk_placer": 0, "dark_oak_trunk_placer": 1, "giant_trunk_placer": 2, "mega_jungle_trunk_placer": 3,
	"forking_trunk_placer": 4, "bending_trunk_placer": 4, "upwards_branching_trunk_placer": 4, "cherry_trunk_placer": 4, "fancy_trunk_placer": 5}
const FOLIAGES := {"blob": 0, "cherry": 1, "bush": 2, "spruce": 3, "pine": 4, "mega_pine": 5, "acacia": 6, "fancy": 7, "jungle": 8, "dark_oak": 9, "random_spread": 10}


## Trees.place: trunk/foliage placers + decorators whose result does not depend on the order GDScript's (unstable)
## sort gives equal-height logs/leaves (per-log decorators only with straight trunks, leaf-iterating ones not ported).
func emit_tree(cf: Dictionary) -> int:
	var tp: Dictionary = cf["tp"]
	var fp: Dictionary = cf["fp"]
	var ttype := str(tp.get("type", "minecraft:straight_trunk_placer")).trim_prefix("minecraft:")
	var ftype := str(fp.get("type", "minecraft:blob_foliage_placer")).trim_prefix("minecraft:").trim_suffix("_foliage_placer")
	var tk: int = TRUNKS.get(ttype, 0)
	var fk: int = FOLIAGES.get(ftype, 11)
	if ttype in ["cherry_trunk_placer", "poplar_trunk_placer"] or ftype in ["cherry", "poplar"]:
		# Java cherry / 26.x poplar placers (hole chances, hanging leaves, branches) only in Trees (GDScript)
		ok = false
		if why == "":
			why = "tree placer " + ttype
		return _node([0])
	var fh_kind := 2
	var fh_node := 0
	match ftype:
		"spruce":
			fh_kind = 1
			fh_node = emit_ip(fp.get("trunk_height", 1))
		"pine":
			fh_node = emit_ip(fp.get("height", 4))
		"mega_pine":
			fh_node = emit_ip(fp.get("crown_height", 13))
		"jungle", "blob", "bush", "fancy", "cherry":
			fh_node = emit_ip(fp.get("height", 3))
		"acacia", "dark_oak":
			fh_kind = 0
			fh_node = 0 if ftype == "acacia" else 4
		"random_spread":
			fh_node = emit_ip(fp.get("foliage_height", 2))
		_:
			fh_kind = 0
			fh_node = 3
	var rad := emit_ip(fp.get("radius", 2))
	var off := emit_ip(fp.get("offset", 0))
	var tpv := emit_pv(cf["trunk"])
	var fpv := emit_pv(cf["foliage"])
	var spv := emit_pv(cf["soil"])
	var ax := _axis_table(cf["trunk"])
	if ax.is_empty():
		ok = false
		if why == "":
			why = "tree trunk provider"
		return _node([0])
	var decs: Array = []
	var hd_faces := ["east", "west", "south", "north"]
	for d in cf["decorators"]:
		if not (d is Dictionary):
			continue
		var dt := str(d.get("type", "")).trim_prefix("minecraft:")
		var prob := _fl(float(d.get("probability", 1.0)))
		match dt:
			"trunk_vine":
				var vine := b.default_state("vine")
				var nd := [1, prob]
				for fc in hd_faces:
					nd.append(b.with_prop(vine, fc, "true") if vine >= 0 else -1)
				decs.append(_node(nd))
			"cocoa":
				var cocoa := b.default_state("cocoa")
				var nd2 := [2, prob]
				for a in 3:
					for fc in hd_faces:
						nd2.append(b.with_prop(b.with_prop(cocoa, "age", str(a)), "facing", fc) if cocoa > 0 else -1)
				decs.append(_node(nd2))
			"beehive":
				var nest := b.default_state("bee_nest")
				decs.append(_node([3, prob, b.with_prop(nest, "facing", "south") if nest > 0 else -1]))
			"alter_ground":
				decs.append(_node([4, prob, 1 if d.has("_prov") else 0, emit_pv(d["_prov"]) if d.has("_prov") else 0]))
			"place_on_ground":
				decs.append(_node([5, prob, 1 if d.has("_prov") else 0, emit_pv(d["_prov"]) if d.has("_prov") else 0,
					int(d.get("radius", 2)), int(d.get("height", 1)), int(d.get("tries", 128)), b.block_id("vine")]))
			"leave_vine":
				var vine2 := b.default_state("vine")
				var nd5 := [7, prob]
				for fc in hd_faces:
					nd5.append(b.with_prop(vine2, fc, "true") if vine2 >= 0 else -1)
				decs.append(_node(nd5))
			"attached_to_leaves":
				var dmap := {"down": 0, "up": 1, "north": 2, "south": 3, "west": 4, "east": 5}
				var dl: Array = d.get("directions", ["down"])
				var nd6 := [8, prob, 1 if d.has("_prov") else 0, emit_pv(d["_prov"]) if d.has("_prov") else 0, int(d.get("required_empty_blocks", 1)),
					int(d.get("exclusion_radius_xz", 0)), int(d.get("exclusion_radius_y", 0)), dl.size()]
				for dn3 in dl:
					nd6.append(int(dmap.get(str(dn3).trim_prefix("minecraft:"), 0)))
				decs.append(_node(nd6))
			"pale_moss":
				var moss := b.default_state("pale_hanging_moss")
				var has_tip := moss >= 0 and b.has_prop(moss, "tip")
				var patch := emit_cf(d["_patch"]) if d.has("_patch") else -1
				decs.append(_node([9, prob, _fl(float(d.get("ground_probability", 0.0))), _fl(float(d.get("trunk_probability", 0.0))),
					_fl(float(d.get("leaves_probability", 0.0))), patch, (b.with_prop(moss, "tip", "false") if has_tip else moss) if moss >= 0 else -1,
					(b.with_prop(moss, "tip", "true") if has_tip else moss) if moss >= 0 else -1]))
			"creaking_heart":
				var heart := b.default_state("creaking_heart")
				if heart >= 0:
					if b.has_prop(heart, "creaking_heart_state"):
						heart = b.with_prop(heart, "creaking_heart_state", "dormant")
					if b.has_prop(heart, "natural"):
						heart = b.with_prop(heart, "natural", "true")
				decs.append(_node([10, prob, heart]))
			"shelf_mushroom":
				var shelf := b.default_state("shelf_mushroom")
				var nd3 := [6, prob, shelf]
				for fc2 in ["west", "east", "north", "south"]:
					nd3.append(b.with_prop(shelf, "facing", fc2) if shelf >= 0 and b.has_prop(shelf, "facing") else shelf)
				decs.append(_node(nd3))
			_:
				ok = false
				if why == "":
					why = "tree decorator " + dt
				return _node([0])
	var nd4 := [21, tk, 1 if ttype == "bending_trunk_placer" else 0, fk, int(tp.get("base_height", 4)), int(tp.get("height_rand_a", 2)),
		int(tp.get("height_rand_b", 0)), fh_kind, fh_node, rad, off, tpv, fpv, spv, int(fp.get("leaf_placement_attempts", 50)), ax.size() / 4]
	nd4.append_array(ax)
	nd4.append(decs.size())
	nd4.append_array(decs)
	return _node(nd4)


## Per-state mask: tag.has(name_of(st)) (Features._veg_patch replace test).
func _mask(tag: String) -> int:
	if _mask_off.has(tag):
		return _mask_off[tag]
	var names := f._tag_blocks(tag)
	var n := b.total_states
	var o := M.size()
	var mk := PackedByteArray()
	mk.resize(n)
	for st in range(1, n):
		if names.has(b.name_of(st)):
			mk[st] = 1
	M.append_array(mk)
	_mask_off[tag] = o
	return o


# ------------------------------------------------------------------ per-state tables (can_survive, simple_block)

## [survive category, below-block bits, half=upper state (-1), waterlogged=true state (-1)] per state.
func _state_tables() -> Array:
	var n := b.total_states
	var cat := PackedByteArray()
	var below := PackedByteArray()
	var half_up := PackedInt32Array()
	var wl := PackedInt32Array()
	var airn := PackedByteArray()
	airn.resize(n)
	var logn := PackedByteArray()
	logn.resize(n)
	cat.resize(n)
	below.resize(n)
	half_up.resize(n)
	wl.resize(n)
	var dirt := ["grass_block", "dirt", "podzol", "coarse_dirt", "mycelium", "rooted_dirt", "moss_block", "mud", "muddy_mangrove_roots", "farmland", "pale_moss_block"]
	var plants := ["short_grass", "fern", "tall_grass", "large_fern", "bush", "firefly_bush", "sweet_berry_bush", "pink_petals", "wildflowers", "leaf_litter", "red_shrub"]
	var flowers := ["dandelion", "poppy", "blue_orchid", "allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley", "sunflower", "lilac", "rose_bush", "peony", "torchflower", "closed_eyeblossom", "open_eyeblossom", "pale_moss_carpet"]
	var sea := ["seagrass", "tall_seagrass", "kelp", "kelp_plant", "sea_pickle"]
	for st in n:
		half_up[st] = -1
		wl[st] = -1
		var nm := b.name_of(st)
		if st > 0 and nm.ends_with("air"):
			airn[st] = 1
		if st > 0 and nm.ends_with("_log"):
			logn[st] = 1
		var bits := 0
		if st > 0 and nm in dirt:
			bits |= 1
		if nm.contains("sand"):
			bits |= 2
		if nm.contains("terracotta"):
			bits |= 4
		if nm == "clay":
			bits |= 8
		if nm == "sand" or nm == "red_sand" or nm == "cactus":
			bits |= 16
		if nm == "sugar_cane":
			bits |= 32
		if nm == "ice" or nm == "packed_ice":
			bits |= 64
		# Java RootsBlock / NetherSproutsBlock / FungusBlock.mayPlaceOn: #nylium, soul soil, #dirt (mycelium), farmland
		if (st > 0 and nm in dirt) or nm in ["crimson_nylium", "warped_nylium", "soul_soil"]:
			bits |= 128
		below[st] = bits
		if st <= 0:
			continue
		var c := 0
		if nm.ends_with("_sapling") or nm.ends_with("_propagule") or nm in plants or nm.ends_with("_tulip") or nm in flowers:
			c = 2 if nm == "mangrove_propagule" else 1
		elif nm == "dead_bush" or nm.ends_with("dry_grass"):
			c = 3
		elif nm in ["crimson_fungus", "warped_fungus", "crimson_roots", "warped_roots", "nether_sprouts"]:
			c = 10
		elif nm.ends_with("_mushroom"):
			c = 4
		elif nm == "cactus":
			c = 5
		elif nm == "sugar_cane":
			c = 6
		elif nm in sea or nm.ends_with("_coral") or nm.ends_with("_coral_fan"):
			c = 7
		elif nm == "lily_pad":
			c = 8
		elif nm == "snow":
			c = 9
		cat[st] = c
		if b.has_prop(st, "half") and b.get_prop(st, "half") == "lower":
			half_up[st] = b.with_prop(st, "half", "upper")
		if b.has_prop(st, "waterlogged"):
			wl[st] = b.with_prop(st, "waterlogged", "true")
	return [cat, below, half_up, wl, airn, logn]
