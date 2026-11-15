## BlockRegistry â€” compact runtime block-state registry: stable string IDs on disk, small ints in RAM.
## Why: hot paths (worldgen, meshing, light, collision) need packed per-state flag/shape/texture tables.
## Contract: state_of(name, props) / with_prop / get_prop / state_string / parse_state; packed arrays st_*.
## Invariants: state id = block_first[b] + mixed-radix(prop value indices, last property fastest);
## state 0 is always minecraft:air. Built once on the main thread, read-only afterwards (thread-safe reads).
class_name BlockRegistry
extends RefCounted

const F_AIR := 1
const F_OPAQUE := 2        # full opaque cube (culls neighbours, blocks light 15)
const F_COLLIDE := 4
const F_LIQUID := 8
const F_REPLACEABLE := 16
const F_CUTOUT := 32
const F_TRANSLUCENT := 64
const F_GRAVITY := 128
const F_WATERLOGGED := 256
const ALWAYS_WATER := ["seagrass", "tall_seagrass", "kelp", "kelp_plant", "bubble_column"]
const F_CLIMB := 512
const F_CUBE := 1024       # render via cube fast path
const F_MODEL := 2048      # render via baked quads
const F_FLUID := 4096      # render as fluid
const F_TINT_GRASS := 8192
const F_TINT_FOLIAGE := 16384
const F_TINT_WATER := 32768
const F_LAVA := 65536
const F_FLAMMABLE := 131072
const F_FULL_SHAPE := 262144  # collision shape is a full unit cube
const F_SELF_CULL := 524288   # same-state faces cull each other (glass, ice; not leaves: Java draws every leaf face)
const F_LEAVES := 1048576
const F_TINT_CONST := 2097152
const F_TINT_DRY := 4194304     # Java BlockColors: BiomeColors.getAverageDryFoliageColor (leaf litter)
const F_NO_AO := 8388608        # flat lighting (Java: model "ambientocclusion": false, or the block emits light)
const F_SOLID := 16777216       # Java BlockState.isSolid (legacy): collision bounds' mean size >= 0.7291666 or height >= 1
const F_TREE_REPL := 33554432   # Java TreeFeature.validTreePos: air or #replaceable_by_trees (Features.setup sets it from the tag)

var names := PackedStringArray()
var block_index: Dictionary = {}
var block_props: Array = []         # per block: Array of [String name, PackedStringArray values]
var block_first := PackedInt32Array()
var block_count := PackedInt32Array()
var block_default := PackedInt32Array()
var block_info: Array = []          # BlockProperties dicts
var hardness := PackedFloat32Array()

var st_block := PackedInt32Array()
var st_flags := PackedInt32Array()
var st_emit := PackedByteArray()
var st_opacity := PackedByteArray()
var st_cull := PackedByteArray()     # 6-bit mask of full opaque faces
var st_faces := PackedInt32Array()   # 6 per state: layer | (overlay+1)<<12 | rotflip<<24 | overlay_present<<27
var st_model := PackedInt32Array()
var st_shape := PackedInt32Array()   # collision shape index
var st_outline := PackedInt32Array() # outline shape index
var st_tint_color := PackedInt32Array()  # constant tint RGB for F_TINT_CONST
var st_level := PackedByteArray()        # fluid level (0 source .. 15), 0 for non-fluids
var st_particle := PackedInt32Array()    # texture layer of the model's #particle texture (breaking particles), -1 none
var st_ctm := PackedInt32Array()         # connected-texture variant base layer (glass), -1 none
var water_layer := 0
var lava_layer := 0
var water_flow_layer := 0
var lava_flow_layer := 0
var water_overlay_layer := 0
var models: Array = []               # Array[PackedFloat32Array]
var shapes: Array = []               # Array[PackedFloat32Array] boxes (minx,miny,minz,maxx,maxy,maxz)*n
var shape_keys: Dictionary = {}
var total_states := 0
var missing_models: Array = []

var AIR := 0
var STONE := 0
var WATER := 0
var LAVA := 0
var BEDROCK := 0


## Thread-private deep copy for worker generators. Reading members/strings of an object shared by several threads
## serializes on refcount cache lines (benchmarks/contention_probe.gd: x12-x21 at 8 threads), so every container and
## string gets its own buffer. Models/shapes stay shared (only passed whole to native code).
func clone() -> BlockRegistry:
	var b := BlockRegistry.new()
	var nm := PackedStringArray()
	nm.resize(names.size())
	for i in names.size():
		nm[i] = _fresh(names[i])
	b.names = nm
	for k in block_index:
		b.block_index[_fresh(str(k))] = block_index[k]
	for props in block_props:
		var lst: Array = []
		for pr in props:
			var vals := PackedStringArray()
			for v in pr[1]:
				vals.append(_fresh(v))
			lst.append([_fresh(str(pr[0])), vals])
		b.block_props.append(lst)
	b.block_first = block_first.duplicate()
	b.block_count = block_count.duplicate()
	b.block_default = block_default.duplicate()
	b.block_info = block_info.duplicate(true)
	b.hardness = hardness.duplicate()
	b.st_block = st_block.duplicate()
	b.st_flags = st_flags.duplicate()
	b.st_emit = st_emit.duplicate()
	b.st_opacity = st_opacity.duplicate()
	b.st_cull = st_cull.duplicate()
	b.st_faces = st_faces.duplicate()
	b.st_model = st_model.duplicate()
	b.st_shape = st_shape.duplicate()
	b.st_outline = st_outline.duplicate()
	b.st_tint_color = st_tint_color.duplicate()
	b.st_level = st_level.duplicate()
	b.st_particle = st_particle.duplicate()
	b.st_ctm = st_ctm.duplicate()
	b.water_layer = water_layer
	b.lava_layer = lava_layer
	b.water_flow_layer = water_flow_layer
	b.lava_flow_layer = lava_flow_layer
	b.water_overlay_layer = water_overlay_layer
	b.models = models
	b.shapes = shapes
	b.shape_keys = shape_keys
	b.total_states = total_states
	b.AIR = AIR
	b.STONE = STONE
	b.WATER = WATER
	b.LAVA = LAVA
	b.BEDROCK = BEDROCK
	return b


static func _fresh(s: String) -> String:
	return s.to_utf8_buffer().get_string_from_utf8()


func block_id(name: String) -> int:
	return int(block_index.get(name.trim_prefix("minecraft:"), -1))


func name_of(state: int) -> String:
	return names[st_block[state]]


func default_state(name: String) -> int:
	var b := block_id(name)
	return block_default[b] if b >= 0 else 0


func _strides(b: int) -> PackedInt32Array:
	var props: Array = block_props[b]
	var s := PackedInt32Array()
	s.resize(props.size())
	var m := 1
	for i in range(props.size() - 1, -1, -1):
		s[i] = m
		m *= (props[i][1] as PackedStringArray).size()
	return s


func get_prop(state: int, prop: String) -> String:
	var b := st_block[state]
	var props: Array = block_props[b]
	var local := state - block_first[b]
	var st := _strides(b)
	for i in props.size():
		var vals: PackedStringArray = props[i][1]
		if props[i][0] == prop:
			return vals[(local / st[i]) % vals.size()]
	return ""


func has_prop(state: int, prop: String) -> bool:
	for p in block_props[st_block[state]]:
		if p[0] == prop:
			return true
	return false


func with_prop(state: int, prop: String, value: String) -> int:
	var b := st_block[state]
	var props: Array = block_props[b]
	var local := state - block_first[b]
	var st := _strides(b)
	for i in props.size():
		if props[i][0] == prop:
			var vals: PackedStringArray = props[i][1]
			var cur := (local / st[i]) % vals.size()
			var nv := vals.find(value)
			if nv < 0:
				return state
			return state + (nv - cur) * st[i]
	return state


func props_of(state: int) -> Dictionary:
	var b := st_block[state]
	var out := {}
	var props: Array = block_props[b]
	var local := state - block_first[b]
	var st := _strides(b)
	for i in props.size():
		var vals: PackedStringArray = props[i][1]
		out[props[i][0]] = vals[(local / st[i]) % vals.size()]
	return out


func state_of(name: String, props: Dictionary = {}) -> int:
	var b := block_id(name)
	if b < 0:
		return -1
	var s := block_default[b]
	for k in props:
		s = with_prop(s, str(k), str(props[k]))
	return s


func state_string(state: int) -> String:
	var p := props_of(state)
	if p.is_empty():
		return "minecraft:" + name_of(state)
	var parts: PackedStringArray = []
	for k in p:
		parts.append("%s=%s" % [k, p[k]])
	return "minecraft:%s[%s]" % [name_of(state), ",".join(parts)]


## Parses "minecraft:name[a=b,c=d]"; returns -1 for unknown block names.
func parse_state(s: String) -> int:
	var name := s
	var props := {}
	var br := s.find("[")
	if br >= 0:
		name = s.substr(0, br)
		var inner := s.substr(br + 1, s.length() - br - 2)
		for kv in inner.split(",", false):
			var e := kv.split("=")
			if e.size() == 2:
				props[e[0].strip_edges()] = e[1].strip_edges()
	return state_of(name.strip_edges(), props)


func is_air(state: int) -> bool:
	return (st_flags[state] & F_AIR) != 0


## Connected glass: variant layers for every glass cube (glass, tinted glass, stained glass); before the atlas build.
func build_ctm(atlas: AtlasBuilder) -> void:
	st_ctm = PackedInt32Array()
	st_ctm.resize(total_states)
	st_ctm.fill(-1)
	var by_layer := {}
	for st in total_states:
		var n := name_of(st)
		if not (n == "glass" or n == "tinted_glass" or n.ends_with("_stained_glass")) or (st_flags[st] & F_CUBE) == 0:
			continue
		var layer := st_faces[st * 6] & 0xFFF
		if not by_layer.has(layer):
			by_layer[layer] = atlas.ctm_variants(layer)
		st_ctm[st] = by_layer[layer]


func is_opaque(state: int) -> bool:
	return (st_flags[state] & F_OPAQUE) != 0


func collides(state: int) -> bool:
	return (st_flags[state] & F_COLLIDE) != 0


func get_shape(state: int) -> PackedFloat32Array:
	return shapes[st_shape[state]]


func get_outline(state: int) -> PackedFloat32Array:
	return shapes[st_outline[state]]


func _shape_index(boxes: PackedFloat32Array) -> int:
	var key := str(boxes)
	if shape_keys.has(key):
		return shape_keys[key]
	shapes.append(boxes)
	shape_keys[key] = shapes.size() - 1
	return shapes.size() - 1


# ---------------------------------------------------------------- building

## Default value heuristics for properties (Java defaults are code-defined; documented approximation).
static func pick_default(prop: String, vals: PackedStringArray, block: String) -> String:
	var prefs := {
		"axis": "y", "facing": "north", "half": "bottom", "shape": "straight", "type": "bottom",
		"hinge": "left", "attachment": "floor", "face": "wall", "part": "foot", "distance": "7",
		"waterlogged": "false", "powered": "false", "open": "false", "lit": "false", "snowy": "false",
		"persistent": "false", "in_wall": "false", "occupied": "false", "triggered": "false",
		"north": "none", "south": "none", "east": "none", "west": "none", "up": "false", "down": "false",
		"level": "0", "age": "0", "power": "0", "rotation": "0", "layers": "1", "moisture": "0",
		"stage": "0", "delay": "1", "mode": "compare", "instrument": "harp", "note": "0", "bites": "0",
		"candles": "1", "pickles": "1", "eggs": "1", "hatch": "0", "honey_level": "0", "charges": "0",
		"tilt": "none", "thickness": "tip", "vertical_direction": "up", "orientation": "north_up",
		"sculk_sensor_phase": "inactive", "bottom": "false", "has_book": "false", "drag": "true",
		"inverted": "false", "enabled": "true", "extended": "false", "short": "false", "conditional": "false",
		"unstable": "false", "disarmed": "false", "attached": "false", "berries": "false", "bloom": "false",
		"can_summon": "false", "shrieking": "false", "cracked": "false", "crafting": "false", "flower_amount": "1",
		"dusted": "0", "segment_amount": "1", "hanging": "false", "signal_fire": "false", "has_bottle_0": "false",
		"ominous": "false", "vault_state": "inactive", "trial_spawner_state": "inactive", "has_record": "false", "eye": "false",
	}
	# Java registers lit=true as the default for campfires and redstone torches
	if prop == "lit" and (block.ends_with("campfire") or block == "redstone_torch" or block == "redstone_wall_torch") and vals.has("true"):
		return "true"
	if prop == "type" and vals.has("single"):
		return "single"
	if prop == "facing" and block.ends_with("shulker_box") and vals.has("up"):
		return "up"
	# Java HugeMushroomBlock registers every face true
	if (block.ends_with("mushroom_block") or block == "mushroom_stem") and vals.has("true"):
		return "true"
	if block.ends_with("_leaves") and prop == "distance":
		return "7" if vals.has("7") else vals[0]
	if prefs.has(prop):
		var want: String = prefs[prop]
		if vals.has(want):
			return want
		# fence-like connection props use booleans
		if want == "none" and vals.has("false"):
			return "false"
	# Java convention: boolean properties default to false unless the block registers otherwise
	if vals.size() == 2 and vals.has("false") and vals.has("true"):
		return "false"
	return vals[0]


static func sort_values(vals: Array) -> PackedStringArray:
	var all_int := true
	for v in vals:
		if not str(v).is_valid_int():
			all_int = false
			break
	var out: Array = vals.duplicate()
	if all_int:
		out.sort_custom(func(a, b): return int(a) < int(b))
	elif out.size() == 2 and out.has("true") and out.has("false"):
		out = ["true", "false"]
	return PackedStringArray(out)


## Collect property names/values from a blockstate JSON (variants keys + multipart "when").
static func collect_props(bs: Dictionary) -> Dictionary:
	var props := {}
	if bs.get("variants") is Dictionary:
		for key in bs["variants"]:
			for kv in str(key).split(",", false):
				var e := kv.split("=")
				if e.size() == 2:
					if not props.has(e[0]):
						props[e[0]] = []
					if not props[e[0]].has(e[1]):
						props[e[0]].append(e[1])
	if bs.get("multipart") is Array:
		for part in bs["multipart"]:
			if part is Dictionary and part.has("when"):
				_collect_when(part["when"], props)
		_complete_domains(props)
	return props


## Multipart blockstates only name the values some model part depends on, so the "off" value of a property is often
## missing (fence / vine / lichen sides only say true, wall sides low / tall, redstone wire side / up): without
## it a fence could never disconnect and a wall side never be none. Complete them to Java's full property domains
## (BooleanProperty, WallSide NONE / LOW / TALL, RedstoneSide UP / SIDE / NONE).
static func _complete_domains(props: Dictionary) -> void:
	for k in props:
		var vals: Array = props[k]
		var is_bool := true
		var is_wall := true
		var is_wire := true
		for v in vals:
			is_bool = is_bool and (v == "true" or v == "false")
			is_wall = is_wall and (v == "none" or v == "low" or v == "tall")
			is_wire = is_wire and (v == "none" or v == "side" or v == "up")
		if is_bool:
			props[k] = ["true", "false"]
		elif is_wall and (vals.has("low") or vals.has("tall")):
			props[k] = ["none", "low", "tall"]
		elif is_wire and (vals.has("side") or vals.has("up")):
			props[k] = ["up", "side", "none"]


static func _collect_when(w, props: Dictionary) -> void:
	if not (w is Dictionary):
		return
	for k in w:
		if k == "OR" or k == "AND":
			for sub in w[k]:
				_collect_when(sub, props)
			continue
		if not props.has(k):
			props[k] = []
		for v in str(w[k]).trim_prefix("!").split("|"):
			if not props[k].has(v):
				props[k].append(v)


static func extra_props(name: String, info: Dictionary, props: Dictionary) -> void:
	if info.get("waterloggable", false) and not props.has("waterlogged"):
		props["waterlogged"] = ["false", "true"]
	if name.ends_with("_leaves"):
		if not props.has("distance"):
			props["distance"] = ["1", "2", "3", "4", "5", "6", "7"]
		if not props.has("persistent"):
			props["persistent"] = ["true", "false"]
	if (name == "water" or name == "lava") and not props.has("level"):
		var lv: Array = []
		for i in 16:
			lv.append(str(i))
		props["level"] = lv
	if name == "redstone_wire" and not props.has("power"):
		var pw: Array = []
		for i in 16:
			pw.append(str(i))
		props["power"] = pw
	# Java properties that no model depends on (absent from blockstate JSON) but gameplay reads/writes
	var extra := {}
	match name:
		"note_block":
			extra = {"instrument": ["harp", "basedrum", "snare", "hat", "bass", "flute", "bell", "guitar", "chime", "xylophone", "iron_xylophone",
				"cow_bell", "didgeridoo", "bit", "banjo", "pling", "trumpet", "trumpet_exposed", "trumpet_weathered", "trumpet_oxidized", "zombie",
				"skeleton", "creeper", "dragon", "wither_skeleton", "piglin", "custom_head"], "note": _range(25), "powered": ["false", "true"]}
		"daylight_detector", "target", "sculk_sensor", "calibrated_sculk_sensor":
			extra = {"power": _range(16)}
		"jukebox":
			extra = {"has_record": ["false", "true"]}
		"dispenser", "dropper":
			extra = {"triggered": ["false", "true"]}
		"hopper":
			extra = {"enabled": ["true", "false"]}
		"lectern", "bell":
			extra = {"powered": ["false", "true"]}
		"tripwire":
			extra = {"powered": ["false", "true"], "disarmed": ["false", "true"]}   # (Java TripWireBlock; no model uses them)
		"tnt":
			extra = {"unstable": ["false", "true"]}
		"scaffolding":
			extra = {"distance": _range(8)}
		"cactus", "sugar_cane", "fire":
			extra = {"age": _range(16)}
		"kelp", "twisting_vines", "weeping_vines", "cave_vines":
			extra = {"age": _range(26)}
	if name.ends_with("_sapling") or name == "mangrove_propagule" or name == "bamboo":
		extra["stage"] = ["0", "1"]   # (bamboo: 1 = stopped growing)
	# block-entity-rendered blocks: their blockstate JSON is a single particle-only variant
	var four := ["north", "south", "west", "east"]
	if name == "chest" or name == "trapped_chest" or name.ends_with("copper_chest"):
		extra["facing"] = four
		extra["type"] = ["single", "left", "right"]
	elif name == "ender_chest" or name == "decorated_pot":
		extra["facing"] = four
	elif name.ends_with("shulker_box"):
		extra["facing"] = ["up", "down", "north", "south", "west", "east"]
	elif name.ends_with("_wall_banner") or name.ends_with("_wall_skull") or name.ends_with("_wall_head") and not name.begins_with("piston"):
		extra["facing"] = four
	elif name.ends_with("_banner") or name.ends_with("_skull") or (name.ends_with("_head") and not name.begins_with("piston")):
		extra["rotation"] = _range(16)
	for k in extra:
		if not props.has(k):
			props[k] = extra[k]
	# make sure fence/pane/wall connection props are complete (both values)
	for k in props.keys():
		var arr: Array = props[k]
		if arr.size() == 1 and (arr[0] == "true" or arr[0] == "false"):
			props[k] = ["true", "false"]


static func _range(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(str(i))
	return out


func matches_when(w, state_props: Dictionary) -> bool:
	if not (w is Dictionary):
		return true
	if w.has("OR"):
		for sub in w["OR"]:
			if matches_when(sub, state_props):
				return true
		return false
	if w.has("AND"):
		for sub in w["AND"]:
			if not matches_when(sub, state_props):
				return false
		return true
	for k in w:
		var want := str(w[k])
		var neg := want.begins_with("!")
		var opts := want.trim_prefix("!").split("|")
		var has := opts.has(str(state_props.get(k, "")))
		if has == neg:
			return false
	return true


func variant_for(variants: Dictionary, sp: Dictionary) -> Variant:
	var best = null
	var best_n := -1
	for key in variants:
		var ok := true
		var n := 0
		for kv in str(key).split(",", false):
			var e := kv.split("=")
			if e.size() != 2 or str(sp.get(e[0], "")) != e[1]:
				ok = false
				break
			n += 1
		if ok and n > best_n:
			best = variants[key]
			best_n = n
	return best


## Builds all blocks. bs_source(name)->blockstate json; baker bakes models.
func build(block_names: PackedStringArray, bs_source: Callable, baker: ModelBaker, tex_info: Callable) -> void:
	names.clear()
	block_index.clear()
	var ordered := PackedStringArray(["air"])
	for n in block_names:
		if n != "air":
			ordered.append(n)
	var states_flags := PackedInt32Array()
	_shape_index(PackedFloat32Array())                    # 0 = empty
	_shape_index(PackedFloat32Array([0, 0, 0, 1, 1, 1]))  # 1 = full cube
	for name in ordered:
		var bs = bs_source.call(name)
		if not (bs is Dictionary):
			bs = {}
		var info := BlockProperties.get_props(name)
		var raw := collect_props(bs)
		extra_props(name, info, raw)
		var keys: Array = raw.keys()
		keys.sort()
		var plist: Array = []
		var count := 1
		for k in keys:
			var vals := sort_values(raw[k])
			plist.append([k, vals])
			count *= vals.size()
		if count > 4096:
			push_warning("Block %s has %d states; truncating props" % [name, count])
		var b := names.size()
		names.append(name)
		block_index[name] = b
		block_props.append(plist)
		block_info.append(info)
		hardness.append(float(info["hardness"]))
		block_first.append(total_states)
		block_count.append(count)
		# default state
		var def_local := 0
		var stride := 1
		for i in range(plist.size() - 1, -1, -1):
			var vals: PackedStringArray = plist[i][1]
			var dv := pick_default(plist[i][0], vals, name)
			def_local += vals.find(dv) * stride
			stride *= vals.size()
		block_default.append(total_states + def_local)
		for local in count:
			var sp := {}
			var rem := local
			for i in range(plist.size() - 1, -1, -1):
				var vals: PackedStringArray = plist[i][1]
				sp[plist[i][0]] = vals[rem % vals.size()]
				rem /= vals.size()
			_add_state(b, name, info, bs, sp, baker, tex_info)
		total_states += count
		if count > 2000:
			print("[Blocks] large state count: %s = %d" % [name, count])
	AIR = default_state("air")
	STONE = default_state("stone")
	WATER = default_state("water")
	LAVA = default_state("lava")
	BEDROCK = default_state("bedrock")


func _add_state(b: int, name: String, info: Dictionary, bs: Dictionary, sp: Dictionary, baker: ModelBaker, tex_info: Callable) -> void:
	var flags := 0
	var quads := PackedFloat32Array()
	var boxes: Array = []
	var applied: Array = []
	if bs.get("variants") is Dictionary:
		var v = variant_for(bs["variants"], sp)
		if v is Array and v.size() > 0:
			v = v[0]
		if v is Dictionary:
			applied.append(v)
	elif bs.get("multipart") is Array:
		for part in bs["multipart"]:
			if part is Dictionary and matches_when(part.get("when"), sp):
				var ap = part.get("apply")
				if ap is Array and ap.size() > 0:
					ap = ap[0]
				if ap is Dictionary:
					applied.append(ap)
	var ao := true
	var part_tex := ""
	for ap in applied:
		var baked := baker.bake(str(ap.get("model", "")), int(ap.get("x", 0)), int(ap.get("y", 0)), bool(ap.get("uvlock", false)))
		quads.append_array(baked["quads"])
		boxes.append_array(baked["boxes"])
		ao = ao and bool(baked["ao"])
		if part_tex == "":
			part_tex = str(baked.get("particle", ""))
	var liquid: String = info["liquid"]
	if name == "air" or name == "cave_air" or name == "void_air":
		flags |= F_AIR | F_REPLACEABLE
	if info["replaceable"]:
		flags |= F_REPLACEABLE
	if info["gravity"]:
		flags |= F_GRAVITY
	if info["climbable"]:
		flags |= F_CLIMB
	if info["flammable"]:
		flags |= F_FLAMMABLE
	if name.ends_with("_leaves"):
		flags |= F_LEAVES
	# waterlogged states, and the blocks whose fluid state is always a water source in Java (no waterlogged property:
	# seagrass, kelp, bubble columns): drawn inside water, swimmable, flowing, leave water when broken
	if sp.get("waterlogged", "false") == "true" or name in ALWAYS_WATER:
		flags |= F_WATERLOGGED
	if liquid != "":
		flags |= F_LIQUID | F_FLUID
		if liquid == "lava":
			flags |= F_LAVA
	# texture transparency class (cutout/translucent) from actual pixels
	var max_class := 0
	var nq := quads.size() / ModelBaker.QUAD_FLOATS
	for qi in nq:
		var c: int = tex_info.call(int(quads[qi * ModelBaker.QUAD_FLOATS + 20]))
		max_class = maxi(max_class, c)
	var faces := [0, 0, 0, 0, 0, 0]
	var cube := ModelBaker.analyze_cube(quads) if liquid == "" else {}
	var cull := 0
	if not cube.is_empty():
		# full cubes: only the base faces decide transparency; overlay quads (grass_block side overlay) are blended onto
		# the opaque base in the shader, so such a block is still a full opaque cube (Java: grass blocks light / culls)
		var base_class := 0
		for d0 in 6:
			base_class = maxi(base_class, int(tex_info.call(int(cube["faces"][d0][0]))))
		max_class = base_class
		flags |= F_CUBE
		for d in 6:
			var f: Array = cube["faces"][d]
			var ov = cube["overlays"][d]
			var v: int = (f[0] & 0xFFF) | ((f[2] & 7) << 24)
			if ov != null:
				v |= ((int(ov[0]) + 1) & 0xFFF) << 12
				v |= 1 << 27
				if ov[1]:
					flags |= _tint_flag(name)
					v |= 1 << 28
			elif f[1]:
				flags |= _tint_flag(name)
				v |= 1 << 28
			faces[d] = v
		if max_class == 0:
			flags |= F_OPAQUE
			cull = 63
		elif not name.ends_with("_leaves"):
			flags |= F_SELF_CULL   # (Java: glass / ice / grates hide faces against themselves; leaves draw every face)
	elif nq > 0 and liquid == "":
		flags |= F_MODEL
		for qi in nq:
			if quads[qi * ModelBaker.QUAD_FLOATS + 21] >= 0.0:
				flags |= _tint_flag(name)
				break
		# partial culling masks: a face is "full" if some quad covers it entirely (slabs/stairs bottoms)
		if max_class == 0:
			for qi in nq:
				var o := qi * ModelBaker.QUAD_FLOATS
				var cf := int(quads[o + 22])
				if cf >= 0 and _quad_full(quads, o, cf):
					cull |= 1 << cf
	if max_class == 1:
		flags |= F_CUTOUT
	elif max_class >= 2:
		flags |= F_TRANSLUCENT
	if liquid == "water":
		flags |= F_TRANSLUCENT | F_TINT_WATER
	if name.contains("glass") or name in ["ice", "slime_block", "honey_block"]:
		flags |= F_SELF_CULL
	# collision
	var shape_boxes := PackedFloat32Array()
	var outline_boxes := PackedFloat32Array()
	for bx in boxes:
		var a: AABB = bx
		outline_boxes.append_array([a.position.x, a.position.y, a.position.z, a.end.x, a.end.y, a.end.z])
	if outline_boxes.is_empty() and (flags & F_AIR) == 0 and liquid == "":
		outline_boxes = PackedFloat32Array([0.125, 0, 0.125, 0.875, 0.8125, 0.875]) if not (flags & F_CUBE) else PackedFloat32Array([0, 0, 0, 1, 1, 1])
	var outline_model := outline_boxes
	var jo := BlockProperties.java_outline(name, sp)
	if not jo.is_empty():
		outline_boxes = jo   # Java getShape defined in code (crops by age, plants, stems ...)
	if info["collide"] and liquid == "" and (flags & F_AIR) == 0:
		shape_boxes = outline_model
		if info["fence_like"] and name.ends_with("_fence") or name.ends_with("_wall") or (name.ends_with("_fence_gate") and sp.get("open", "false") == "false"):
			var tall := PackedFloat32Array()
			for i in range(0, shape_boxes.size(), 6):
				tall.append_array([shape_boxes[i], shape_boxes[i + 1], shape_boxes[i + 2], shape_boxes[i + 3], 1.5, shape_boxes[i + 5]])
			shape_boxes = tall
		elif name.ends_with("_fence_gate"):
			shape_boxes = PackedFloat32Array()
		if name == "soul_sand" or name == "mud":
			shape_boxes = PackedFloat32Array([0, 0, 0, 1, 0.875, 1])
		elif name == "mangrove_roots":
			shape_boxes = PackedFloat32Array([0, 0, 0, 1, 1, 1])   # (full collision; its model is crossed planes - wiki Waterlogging: no flow out of it)
		elif not jo.is_empty() and (name.ends_with("_skull") or (name.ends_with("_head") and name != "piston_head")):
			shape_boxes = jo   # (heads have no block model: Java SkullBlock / WallSkullBlock shapes, not the default box)
		elif name == "farmland" or name == "dirt_path":
			shape_boxes = PackedFloat32Array([0, 0, 0, 1, 0.9375, 1])
		elif name == "snow":
			var layers := int(sp.get("layers", "1"))
			shape_boxes = PackedFloat32Array([0, 0, 0, 1, (layers - 1) / 8.0, 1]) if layers > 1 else PackedFloat32Array()
		elif name.ends_with("_door") and sp.get("open", "false") == "true":
			pass
		if shape_boxes.size() > 0:
			flags |= F_COLLIDE
		# full collision cube (Java isCollisionShapeFullBlock): any box covering the unit cube - multi-element cube models
		# such as grass_block (base + tinted side overlay, two 0..16 boxes) are full too (AO occluders, suffocation, ...)
		for fb in range(0, shape_boxes.size(), 6):
			if is_zero_approx(shape_boxes[fb]) and is_zero_approx(shape_boxes[fb + 1]) and is_zero_approx(shape_boxes[fb + 2]) and is_equal_approx(shape_boxes[fb + 3], 1.0) and is_equal_approx(shape_boxes[fb + 4], 1.0) and is_equal_approx(shape_boxes[fb + 5], 1.0):
				flags |= F_FULL_SHAPE
				shape_boxes = PackedFloat32Array([0, 0, 0, 1, 1, 1])
				break
	if shape_boxes.size() >= 6:
		# Java BlockState.isSolid (legacy solid): collision bounds' mean size >= 0.7291666 or height >= 1
		var smn := Vector3(shape_boxes[0], shape_boxes[1], shape_boxes[2])
		var smx := Vector3(shape_boxes[3], shape_boxes[4], shape_boxes[5])
		for sb in range(6, shape_boxes.size(), 6):
			smn = smn.min(Vector3(shape_boxes[sb], shape_boxes[sb + 1], shape_boxes[sb + 2]))
			smx = smx.max(Vector3(shape_boxes[sb + 3], shape_boxes[sb + 4], shape_boxes[sb + 5]))
		var sd := smx - smn
		if (sd.x + sd.y + sd.z) / 3.0 >= 0.7291666 or sd.y >= 1.0:
			flags |= F_SOLID
	var opacity := 0
	if flags & F_OPAQUE:
		opacity = 15
	if int(info["opacity"]) >= 0:
		opacity = int(info["opacity"])
	if flags & F_WATERLOGGED:
		opacity = maxi(opacity, 1)
	var emit := int(info["light"])
	if sp.has("lit") and emit == 0 and (name.contains("furnace") or name == "smoker" or name == "redstone_ore" or name == "deepslate_redstone_ore" or name == "redstone_lamp" or name == "copper_bulb" or name.ends_with("_copper_bulb")):
		emit = 0
	if sp.get("lit", "") == "true":
		if name.contains("furnace") or name == "smoker":
			emit = 13
		elif name == "redstone_lamp":
			emit = 15
		elif name.ends_with("copper_bulb"):
			# wiki Light / Copper Bulb: 15 / 12 / 8 / 4 by oxidation (waxed the same)
			var bn := name.trim_prefix("waxed_")
			emit = 12 if bn.begins_with("exposed_") else (8 if bn.begins_with("weathered_") else (4 if bn.begins_with("oxidized_") else 15))
		elif name.contains("redstone_ore"):
			emit = 9
		elif name.contains("candle"):
			emit = 3 * int(sp.get("candles", "1"))
	elif sp.get("lit", "") == "false" and (name.contains("campfire") or name.contains("candle") or name.contains("redstone_torch")):
		emit = 0
	if name == "light":
		emit = int(sp.get("level", "15"))
	# wiki Light: respawn anchor floor(charges / 4 x 15) = 0 / 3 / 7 / 11 / 15; vault 12 while active / unlocking /
	# ejecting, 6 inactive; trial spawner 8 active / ejecting, 4 waiting for players, 0 inactive / cooldown
	if name == "respawn_anchor":
		emit = int(floor(int(sp.get("charges", "0")) / 4.0 * 15.0))
	if name == "vault":
		emit = 6 if sp.get("vault_state", "inactive") == "inactive" else 12
	if name == "trial_spawner":
		var ts := str(sp.get("trial_spawner_state", "inactive"))
		emit = 4 if ts == "waiting_for_players" else (8 if ts in ["active", "waiting_for_reward_ejection", "ejecting_reward"] else 0)
	if name == "sea_pickle":
		emit = 3 + 3 * int(sp.get("pickles", "1")) if sp.get("waterlogged", "false") == "true" else 0
	if name.ends_with("cave_vines") or name.ends_with("cave_vines_plant"):
		emit = 14 if sp.get("berries", "false") == "true" else 0
	if name == "lava" or name == "fire":
		emit = 15
	var mi := -1
	if flags & F_MODEL:
		models.append(quads)
		mi = models.size() - 1
	elif not (flags & (F_CUBE | F_AIR | F_FLUID)) and nq == 0 and liquid == "":
		missing_models.append(name)
	if not ao or emit > 0:
		flags |= F_NO_AO
	# Java TerrainParticle sprite: the model's particle texture (first applied model; first quad's texture as fallback)
	var pl := -1
	if part_tex != "" and not part_tex.begins_with("#"):
		pl = int(baker.texture_layer.call(part_tex))
	if pl < 0 and quads.size() >= ModelBaker.QUAD_FLOATS:
		pl = int(quads[20])
	if pl < 0 and (flags & F_CUBE):
		pl = faces[1] & 0xFFF
	st_particle.append(pl)
	st_block.append(b)
	st_flags.append(flags)
	st_emit.append(emit)
	st_opacity.append(opacity)
	st_cull.append(cull)
	st_faces.append_array(faces)
	st_model.append(mi)
	st_shape.append(_shape_index(shape_boxes))
	st_outline.append(_shape_index(outline_boxes))
	st_tint_color.append(_const_tint(name))
	st_level.append(int(sp.get("level", "0")) if liquid != "" else 0)


static func _quad_full(q: PackedFloat32Array, o: int, dir: int) -> bool:
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for k in 4:
		var p := Vector3(q[o + k * 5], q[o + k * 5 + 1], q[o + k * 5 + 2])
		mn = mn.min(p)
		mx = mx.max(p)
	var e := mx - mn
	match dir:
		0, 1: return is_equal_approx(e.x, 1.0) and is_equal_approx(e.z, 1.0)
		2, 3: return is_equal_approx(e.x, 1.0) and is_equal_approx(e.y, 1.0)
		_: return is_equal_approx(e.z, 1.0) and is_equal_approx(e.y, 1.0)


## Java BlockColors registrations (code, not data): only these blocks colour their tintindex faces; every other block
## renders tintindex faces untinted (cherry / azalea / pale oak / poplar leaves: their models have tintindex too).
const FOLIAGE_TINTED := ["oak_leaves", "jungle_leaves", "acacia_leaves", "dark_oak_leaves", "mangrove_leaves", "vine"]
const GRASS_TINTED := ["grass_block", "short_grass", "tall_grass", "fern", "large_fern", "potted_fern", "sugar_cane", "bush",
	"pink_petals", "wildflowers"]
const DRY_FOLIAGE_TINTED := ["leaf_litter"]


static func _tint_flag(name: String) -> int:
	if name in ["spruce_leaves", "birch_leaves", "lily_pad", "attached_melon_stem", "attached_pumpkin_stem", "melon_stem", "pumpkin_stem", "redstone_wire"]:
		return F_TINT_CONST
	if name in FOLIAGE_TINTED:
		return F_TINT_FOLIAGE
	if name.contains("water") or name == "bubble_column":
		return F_TINT_WATER
	if name in GRASS_TINTED:
		return F_TINT_GRASS
	if name in DRY_FOLIAGE_TINTED:
		return F_TINT_DRY
	return 0


static func _const_tint(name: String) -> int:
	match name:
		"spruce_leaves": return 0x619961
		"birch_leaves": return 0x80A755
		"lily_pad": return 0x208030
		"redstone_wire": return 0xB01010
		"melon_stem", "pumpkin_stem", "attached_melon_stem", "attached_pumpkin_stem": return 0xE0C71C
	return 0xFFFFFF


## Deep copy for one worker thread (ChunkManager._thread_gen): same content, private packed buffers and containers, so a
## worker's reads never touch the shared registry's reference counts. Every `blocks.st_flags[i]` copies the array (an
## atomic refcount increment + decrement); with the main thread and 5+ workers on the same counters this cache-line
## ping-pong made main-thread GDScript 2-100x slower in bursts (FrameProbe shared-table probe).
func thread_copy():
	var c = get_script().new()
	for p in get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p["name"]
		var v = get(n)
		if v is Array or v is Dictionary:
			c.set(n, v.duplicate(true))
		elif typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY:
			c.set(n, v.duplicate())
		else:
			c.set(n, v)
	return c
