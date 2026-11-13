class_name FrameProbe
extends Node
## Frame-phase timestamps for the FPS benchmark: two probes (process_priority -1e6 / +1e6) bracket the process phase
## of all nodes; RenderingServer frame_pre_draw / frame_post_draw bracket the draw. Shared Dictionary `t`:
## proc_start, proc_end, pre_draw, post_draw (usec, last frame).

var t: Dictionary
var is_first := true
static var busy_us := 0   # experiment (--busy=US): fixed CPU busy-wait per frame
var _private := PackedInt32Array()   # probe3: main-thread-only array
static var speed_probe := false   # --trace: time a fixed GDScript workload at the start of every frame (CPU speed)


static func install(parent: Node) -> Dictionary:
	var t := {"proc_start": 0, "proc_end": 0, "pre_draw": 0, "post_draw": 0, "phys0": 0, "phys_end": 0}
	for first in [true, false]:
		var p := FrameProbe.new()
		p.t = t
		p.is_first = first
		p.process_priority = -1000000 if first else 1000000
		p.process_physics_priority = -1000000 if first else 1000000
		p.name = "FrameProbeFirst" if first else "FrameProbeLast"
		parent.add_child(p)
	RenderingServer.frame_pre_draw.connect(func(): t["pre_draw"] = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): t["post_draw"] = Time.get_ticks_usec())
	# first physics step after the last draw (splits the after-draw gap: OS events / audio, physics, until process)
	parent.get_tree().physics_frame.connect(func():
		if int(t["phys0"]) <= int(t["post_draw"]):
			t["phys0"] = Time.get_ticks_usec())
	return t


func _physics_process(_delta: float) -> void:
	if not is_first:
		t["phys_end"] = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	if busy_us > 0 and not is_first:
		var b0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - b0 < busy_us:
			pass
	if speed_probe and is_first:
		var c0: int = Native.inst.thread_cycles()[0] if Native.inst != null else 0
		var s0 := Time.get_ticks_usec()
		var acc := 0
		for i in 3000:
			acc = (acc * 31 + i) & 0xFFFFFF
		t["probe_us"] = Time.get_ticks_usec() - s0 + (acc & 0)
		# cycles the thread actually ran during the loop: ~probe_us x clock (MHz) when it ran throughout; far fewer when it
		# was descheduled (waiting for a core) - tells preemption from a slow / throttled core
		t["probe_cyc"] = (Native.inst.thread_cycles()[0] - c0) if Native.inst != null else 0
		# same loop reading a block table shared with the chunk workers (Res.blocks.st_flags: refcount on every access)
		var s1 := Time.get_ticks_usec()
		var blocks := Res.blocks
		for i in 3000:
			acc = (acc * 31 + blocks.st_flags[i & 255]) & 0xFFFFFF
		t["probe2_us"] = Time.get_ticks_usec() - s1 + (acc & 0)
		# the same refcounted access pattern on an array only this thread ever sees (sharing vs. system-wide slowness)
		if _private.is_empty():
			_private.resize(256)
		var s2 := Time.get_ticks_usec()
		var holder := self
		for i in 3000:
			acc = (acc * 31 + holder._private[i & 255]) & 0xFFFFFF
		t["probe3_us"] = Time.get_ticks_usec() - s2 + (acc & 0)
	t["proc_start" if is_first else "proc_end"] = Time.get_ticks_usec()
