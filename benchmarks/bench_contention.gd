## BenchContention — `-- --bench-contention`: measures multi-thread scaling of GDScript patterns
## (local arithmetic, static call via global class, member method call on thread-local object,
## shared packed-array member reads) to locate shared-refcount contention.
extends Node

var shared_arr := PackedInt32Array()
var mutex := Mutex.new()
var counter := 0
const LOCAL_C := -64


func _step(x: int) -> int:
	return (x * 31 + 5) & 0xFFFF


class Local:
	var v := 0

	func step(x: int) -> int:
		return (x * 31 + v) & 0xFFFF


func _ready() -> void:
	shared_arr.resize(1024)
	for mode in ["local", "self_method", "other_member", "other_member_hoisted", "dict_int_key", "method", "new_object"]:
		for n in [1, 8]:
			var t0 := Time.get_ticks_msec()
			var ids: Array = []
			for j in n:
				ids.append(WorkerThreadPool.add_task(_work.bind(mode), true))
			for id in ids:
				WorkerThreadPool.wait_for_task_completion(id)
			var ms := Time.get_ticks_msec() - t0
			print("BENCH-C %s threads %d: %d ms (per-thread work constant)" % [mode, n, ms])
	get_tree().quit()


func _work(mode: String) -> void:
	var acc := 0
	match mode:
		"local":
			for i in 2000000:
				acc = (acc * 31 + i) & 0xFFFF
		"const_global":
			for i in 2000000:
				acc = (acc + Coords.MIN_Y + i) & 0xFFFF
		"const_local":
			for i in 2000000:
				acc = (acc + LOCAL_C + i) & 0xFFFF
		"dict_local":
			var d := {"t": 3}
			for i in 1000000:
				acc = (acc + int(d["t"]) + i) & 0xFFFF
		"builtin_fn":
			for i in 1000000:
				acc = (acc + mini(i, 7) + absi(i)) & 0xFFFF
		"static":
			for i in 500000:
				acc = RandomSources.urshift(acc + i, 3)
		"method":
			var l := Local.new()
			for i in 500000:
				acc = l.step(acc + i)
		"self_method":
			for i in 500000:
				acc = _step(acc + i)
		"other_member":
			var l2 := Local.new()
			for i in 1000000:
				acc = (acc + l2.v + i) & 0xFFFF
		"other_member_hoisted":
			var l3 := Local.new()
			var vv := l3.v
			for i in 1000000:
				acc = (acc + vv + i) & 0xFFFF
		"dict_int_key":
			var d2 := {7: 3}
			for i in 1000000:
				acc = (acc + int(d2[7]) + i) & 0xFFFF
		"new_object":
			for i in 100000:
				var o := Local.new()
				acc += o.v
		"shared_array":
			var a := shared_arr
			for i in 2000000:
				acc += a[i & 1023]
		"xoroshiro":
			var r := RandomSources.Xoroshiro.from_seed(1)
			for i in 200000:
				acc += r.next_int_bound(100)
	mutex.lock()
	counter += acc & 1
	mutex.unlock()
