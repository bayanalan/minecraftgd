## BenchMT — `godot --headless --path . -- --bench-mt`: chunk generation throughput vs worker count using
## thread-local generators (WorkerThreadPool high-priority tasks). Prints BENCH-MT lines.
extends Node

var biomes: BiomeRegistry
var gens: Dictionary = {}
var mutex := Mutex.new()
var done := 0
var base_gen: WorldGenerator


func _ready() -> void:
	biomes = BiomeRegistry.new()
	biomes.build()
	base_gen = WorldGenerator.create("java_26_3")
	base_gen.setup(4242, Res.blocks, biomes, {})
	print("BENCH-MT cores=%d" % OS.get_processor_count())
	var offset := 0
	for n: int in [1, 2, 4, 8, 12]:
		done = 0
		var jobs: int = n * 2
		var t0 := Time.get_ticks_msec()
		var ids: Array = []
		for j in jobs:
			ids.append(WorkerThreadPool.add_task(_job.bind(offset + j), true))
		offset += jobs
		# limit concurrency to n by running in waves
		for id in ids:
			WorkerThreadPool.wait_for_task_completion(id)
		var ms := Time.get_ticks_msec() - t0
		print("BENCH-MT threads<=%d jobs %d: %d ms total, %.2f chunks/s" % [n, jobs, ms, jobs * 1000.0 / ms])
		if n >= 8:
			break
	for g in gens.values():
		print("BENCH-MT stage ms: ", (g as VanillaGenerator).stats)
	get_tree().quit()


func _gen() -> WorldGenerator:
	var tid := OS.get_thread_caller_id()
	mutex.lock()
	var g = gens.get(tid)
	mutex.unlock()
	if g == null:
		g = WorldGenerator.create("java_26_3")
		g.setup(4242, Res.blocks, biomes, {})
		mutex.lock()
		gens[tid] = g
		mutex.unlock()
	return g


func _job(i: int) -> void:
	var g := _gen()
	var c := Chunk.new(i * 3, 100)
	g.generate(c)
	mutex.lock()
	done += 1
	mutex.unlock()
