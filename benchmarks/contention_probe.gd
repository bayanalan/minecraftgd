## ContentionProbe — `godot --headless --path . -- --contention [--threads=8]`: which GDScript access patterns stop
## scaling across threads (x86-64 Godot under ARM64 emulation). Each pattern runs N iterations on 1 thread, then on
## T threads at once (same per-thread work); prints the per-thread slowdown factor.
extends Node

class Shared:
	extends RefCounted
	var arr := PackedInt32Array()
	var dict := {}
	var obj: RefCounted = null
	var s := "stone"

	func _init() -> void:
		arr.resize(4096)
		for i in 4096:
			arr[i] = i
			dict[i] = i
		obj = RefCounted.new()

	func get_v(i: int) -> int:
		return arr[i & 4095]


static var s_shared: Shared = null
static var s_int := 5

var shared := Shared.new()
var _vg = null
var _res: Array = []
const ITERS := 400000


func _ready() -> void:
	var t := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--threads="):
			t = int(a.substr(10))
	s_shared = shared
	if Native.ok:
		var bio := BiomeRegistry.new()
		bio.build()
		_vg = WorldGenerator.create("java_26_3")
		_vg.setup(12345, Res.blocks, bio, {"structures": true, "dimension": "overworld"})
	for pat in ["local_method_call", "local_member_packed", "local_static_func_other", "inner_func_call", "local_dict_rw", "arith", "member_packed_read", "local_packed_read", "dict_read", "method_call", "static_var", "static_func",
			"global_const", "string_name_of", "native_call", "native_static_inst", "vector3i_alloc", "array_alloc"]:
		var one := _run(pat, 1)
		var many := _run(pat, t)
		print("CONTENTION %-20s 1 thread %7.1f ms   %d threads %7.1f ms/thread   slowdown x%.2f" % [pat, one, t, many, many / maxf(one, 0.001)])
	get_tree().quit()


func _run(pat: String, n: int) -> float:
	_res.resize(n)
	var ths: Array = []
	for i in n:
		var th := Thread.new()
		th.start(_work.bind(pat, i))
		ths.append(th)
	for th in ths:
		th.wait_to_finish()
	var tot := 0.0
	for i in n:
		tot += _res[i]
	return tot / n


static func _sf(i: int) -> int:
	return i + 1


func _work(pat: String, idx: int) -> void:
	var t0 := Time.get_ticks_usec()
	var acc := 0
	match pat:
		"arith":
			for i in ITERS:
				acc += (i * 7) ^ (i >> 3)
		"member_packed_read":
			for i in ITERS:
				acc += shared.arr[i & 4095]
		"local_packed_read":
			var a := shared.arr.duplicate()
			for i in ITERS:
				acc += a[i & 4095]
		"dict_read":
			for i in ITERS:
				acc += int(shared.dict[i & 4095])
		"method_call":
			for i in ITERS:
				acc += shared.get_v(i)
		"static_var":
			for i in ITERS:
				acc += s_int
		"static_func":
			for i in ITERS:
				acc += _sf(i)
		"global_const":
			for i in ITERS:
				acc += Coords.MIN_Y + BlockRegistry.F_LIQUID
		"string_name_of":
			for i in ITERS:
				var s: String = shared.s
				acc += s.length()
		"native_call":
			if Native.ok:
				var inst = Native.inst
				for i in ITERS / 20:
					acc += int(inst.version()[0])
		"native_static_inst":
			if Native.ok:
				for i in ITERS / 20:
					acc += int(Native.inst.version()[0])
		"vector3i_alloc":
			for i in ITERS:
				var v := Vector3i(i, i + 1, i + 2)
				acc += v.x
		"local_method_call":
			var lo := Shared.new()
			for i in ITERS:
				acc += lo.get_v(i)
		"local_member_packed":
			var lo2 := Shared.new()
			for i in ITERS:
				acc += lo2.arr[i & 4095]
		"local_static_func_other":
			for i in ITERS:
				acc += Coords.chunk_key(i, 3)
		"inner_func_call":
			for i in ITERS:
				acc += _sf(i)
		"local_dict_rw":
			var d := {}
			for i in ITERS:
				d[i & 1023] = i
				acc += int(d[i & 1023])
		"native_df_chunk":
			for i in 6:
				acc += (Native.inst.df_chunk(_vg.native_graph, _vg.final_density.id, idx * 100 + i, 7, -64, 320)[0] as PackedFloat64Array).size()
		"native_df_points_small":
			var xs := PackedInt32Array([1, 2, 3])
			for i in 200:
				acc += (Native.inst.df_points(_vg.native_graph, PackedInt32Array([_vg.final_density.id]), xs, xs, xs, idx * 100 + i, 0, 1)[0] as PackedFloat64Array).size()
		"native_tg_begin":
			for i in 6:
				var tg: Array = Native.inst.tg_begin(_vg.native_tg, idx * 100 + i, 9)
				Native.inst.tg_end(tg[0])
				acc += 1
		"gd_alloc_big":
			for i in 400:
				var big := PackedInt32Array()
				big.resize(98304)
				acc += big.size()
		"gd_generate":
			for i in 4:
				var c := Chunk.new(idx * 100 + i, 33)
				_vg.generate(c)
				acc += 1
		"array_alloc":
			for i in ITERS / 10:
				var a2 := [i, i + 1]
				acc += a2.size()
	_res[idx] = (Time.get_ticks_usec() - t0) / 1000.0 + float(acc & 0)
