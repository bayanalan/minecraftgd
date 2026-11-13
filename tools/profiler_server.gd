extends SceneTree
## Minimal Godot remote-debugger endpoint used as a script profiler (no editor needed).
## 1. godot --headless --script res://tools/profiler_server.gd -- --port=6007 --out=<file.json> [--raw=<file.txt>]
## 2. game:  godot --path . --remote-debug tcp://127.0.0.1:6007 -- --autoplay ... --fpsbench=A
## The game marks the measured window with EngineDebugger.send_message("recraft:bench", ["begin"|"end"]); per-function
## call counts / self / total time (GDScript profiler, all threads) are summed over the frames inside the window.

var srv := TCPServer.new()
var peer: StreamPeerTCP
var buf := PackedByteArray()
var sigs := {}        # sig id -> function signature
var acc := {}         # sig id -> [calls, self_s, total_s]
var recording := false
var frames := 0
var out_path := "user://profile.json"
var raw_path := ""
var raw_n := 0
var main_tid := 1
var cmds := {}
var frame_sums := {"frame_time": 0.0, "process_time": 0.0, "physics_time": 0.0, "physics_frame_time": 0.0, "script_time": 0.0}
var server_fns := {}  # "server/function" -> total seconds
var idle_t := 0.0
var done := false


func _initialize() -> void:
	var port := 6007
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--raw="):
			raw_path = a.substr(6)
	var e := srv.listen(port, "127.0.0.1")
	print("[prof] listening on %d: %s" % [port, error_string(e)])


func _send(cmd: String, data: Array) -> void:
	var b := var_to_bytes([cmd, main_tid, data])
	var hdr := PackedByteArray()
	hdr.resize(4)
	hdr.encode_u32(0, b.size())
	peer.put_data(hdr + b)


func _process(delta: float) -> bool:
	if peer == null:
		if srv.is_connection_available():
			peer = srv.take_connection()
			peer.set_no_delay(true)
			print("[prof] game connected")
			_send("profiler:servers", [true, [512, false]])
		return false
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		print("[prof] game disconnected")
		_write()
		return true
	var avail := peer.get_available_bytes()
	if avail > 0:
		var r := peer.get_data(avail)
		if r[0] == OK:
			buf.append_array(r[1])
	while buf.size() >= 4:
		var sz := buf.decode_u32(0)
		if buf.size() < 4 + sz:
			break
		var v = bytes_to_var(buf.slice(4, 4 + sz))
		buf = buf.slice(4 + sz)
		if v is Array and v.size() >= 3:
			_handle(str(v[0]), int(v[1]), v[2] if v[2] is Array else [])
	return done


func _raw(s: String) -> void:
	if raw_path == "" or raw_n > 40:
		return
	raw_n += 1
	var f := FileAccess.open(raw_path, FileAccess.READ_WRITE if FileAccess.file_exists(raw_path) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(s.substr(0, 4000))
	f.close()


func _handle(cmd: String, tid: int, data: Array) -> void:
	if not cmds.has(cmd):
		cmds[cmd] = 0
		_raw("CMD %s tid %d data %s" % [cmd, tid, str(data).substr(0, 1500)])
	cmds[cmd] += 1
	match cmd:
		"servers:function_signature":
			sigs[int(data[1])] = str(data[0])
		"servers:profile_frame":
			if recording:
				_frame(data)
		"recraft:bench":
			if str(data[0]) == "begin":
				recording = true
				acc.clear()
				frames = 0
				print("[prof] begin")
			elif str(data[0]) == "end":
				recording = false
				print("[prof] end (%d frames)" % frames)
				_write()
		"debug_enter":
			_send("continue", [])


## ServersProfilerFrame.serialize(): frame_number, frame_time, process_time, physics_time, physics_frame_time, script_time,
## server count, per server: name, 2*function count, (name, time)*; then 4*function count?, (sig, calls, self, total)*.
func _frame(a: Array) -> void:
	frames += 1
	var keys := ["frame_time", "process_time", "physics_time", "physics_frame_time", "script_time"]
	for k in 5:
		frame_sums[keys[k]] += float(a[1 + k])
	var i := 6
	var ns := int(a[i])
	i += 1
	for s in ns:
		var sname := str(a[i])
		var nf := int(a[i + 1])
		i += 2
		for j in range(0, nf, 2):
			var fk := sname + "/" + str(a[i + j])
			server_fns[fk] = float(server_fns.get(fk, 0.0)) + float(a[i + j + 1])
		i += nf
	var nfun := int(a[i])
	i += 1
	var rest := a.size() - i
	if frames == 1:
		_raw("FRAME layout: total %d, script header %d, rest %d" % [a.size(), nfun, rest])
	var stride := 5   # Godot 4.7: sig, calls, self, total, internal
	var end := mini(a.size(), i + nfun)
	while i + stride <= end:
		var sid := int(a[i])
		var e: Array = acc.get(sid, [0, 0.0, 0.0])
		e[0] += int(a[i + 1])
		e[1] += float(a[i + 2])
		e[2] += float(a[i + 3])
		acc[sid] = e
		i += stride


func _write() -> void:
	var rows: Array = []
	for sid in acc:
		var e: Array = acc[sid]
		rows.append({"fn": sigs.get(sid, "#%d" % sid), "calls_per_frame": snappedf(e[0] / maxf(1.0, frames), 0.01),
			"self_ms_per_frame": snappedf(e[1] * 1000.0 / maxf(1.0, frames), 0.0001), "total_ms_per_frame": snappedf(e[2] * 1000.0 / maxf(1.0, frames), 0.0001)})
	rows.sort_custom(func(x, y): return x["self_ms_per_frame"] > y["self_ms_per_frame"])
	var fs := {}
	for k in frame_sums:
		fs[k] = snappedf(frame_sums[k] * 1000.0 / maxf(1.0, frames), 0.001)
	var sv := {}
	for k in server_fns:
		sv[k] = snappedf(server_fns[k] * 1000.0 / maxf(1.0, frames), 0.001)
	var res := {"frames": frames, "frame_ms_avg": fs, "servers_ms_per_frame": sv, "functions_by_self": rows, "commands": cmds}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()
	print("[prof] wrote %s (%d functions, %d frames)" % [out_path, rows.size(), frames])
