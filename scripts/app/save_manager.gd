## SaveManager — world folders under user://saves/<folder>/: level.json + region/r.X.Z.rcr (32x32 chunks).
## Why: persist only edited chunks (pristine terrain regenerates from seed + generator snapshot), atomic
## writes (tmp + rename, previous file kept as .bak), MD5 integrity per chunk blob, stable string block IDs.
## Contract: create_world(meta) / open(folder) / load_chunk(cx,cz) (thread-safe) / save_chunk(c) /
## flush() / save_level(dict) / list_worlds() / delete_world / backup_world / duplicate_world.
## Invariants: unknown block-state strings round-trip (kept per position); never touches files outside user://saves.
class_name SaveManager
extends RefCounted

const ROOT := "user://saves"
const FORMAT := 1
const MAGIC := "RCRG"

var folder := ""
var dir := ""
var level: Dictionary = {}
var _mutex := Mutex.new()
var _regions: Dictionary = {}     # "rx,rz" -> Dictionary(chunk_key -> PackedByteArray blob)
var region_dir := "region"        # per dimension: region | DIM-1/region | DIM1/region (Java layout)
var _dirty_regions: Dictionary = {}
var blocks: BlockRegistry


static func sanitize(name: String) -> String:
	var s := ""
	for ch in name.strip_edges():
		s += ch if (ch.is_valid_identifier() or ch in " -_()0123456789") else "_"
	s = s.strip_edges()
	if s.is_empty():
		s = "World"
	return s


static func unique_folder(name: String) -> String:
	var base := sanitize(name)
	var f := base
	var n := 1
	while DirAccess.dir_exists_absolute(ROOT.path_join(f)):
		f = "%s (%d)" % [base, n]
		n += 1
	return f


static func list_worlds() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(ROOT):
		return out
	# no per-world directory walk here (Java lists from level summaries only); size: world_size()
	for d in DirAccess.get_directories_at(ROOT):
		if d.begins_with("."):
			continue   # internal (LAN client cache)
		var p := ROOT.path_join(d).path_join("level.json")
		var meta := _read_json_safe(p)
		if meta.is_empty():
			meta = _read_json_safe(p + ".bak")
			if meta.is_empty():
				out.append({"folder": d, "name": d, "corrupt": true})
				continue
			meta["recovered"] = true
		meta["folder"] = d
		out.append(meta)
	out.sort_custom(func(a, b): return int(a.get("last_played", 0)) > int(b.get("last_played", 0)))
	return out


static func world_size(f: String) -> int:
	return _dir_size(ROOT.path_join(f))


static func _dir_size(p: String) -> int:
	var total := 0
	for f in DirAccess.get_files_at(p):
		total += FileAccess.get_size(p.path_join(f)) if FileAccess.file_exists(p.path_join(f)) else 0
	for d in DirAccess.get_directories_at(p):
		total += _dir_size(p.path_join(d))
	return total


static func _read_json_safe(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(p))
	return j if j is Dictionary else {}


static func atomic_write(p: String, data: PackedByteArray) -> bool:
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Save failed (cannot open %s): %s" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_buffer(data)
	f.flush()
	var ok := f.get_error() == OK
	f.close()
	if not ok:
		return false
	if FileAccess.file_exists(p):
		if FileAccess.file_exists(p + ".bak"):
			DirAccess.remove_absolute(p + ".bak")
		DirAccess.rename_absolute(p, p + ".bak")
	return DirAccess.rename_absolute(tmp, p) == OK


static func delete_world(f: String) -> bool:
	var p := ROOT.path_join(f)
	if not DirAccess.dir_exists_absolute(p) or f.contains("..") or f.is_empty():
		return false
	return _rm_rf(p)


static func _rm_rf(p: String) -> bool:
	for f in DirAccess.get_files_at(p):
		DirAccess.remove_absolute(p.path_join(f))
	for d in DirAccess.get_directories_at(p):
		_rm_rf(p.path_join(d))
	return DirAccess.remove_absolute(p) == OK


static func copy_dir(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	for f in DirAccess.get_files_at(src):
		DirAccess.copy_absolute(src.path_join(f), dst.path_join(f))
	for d in DirAccess.get_directories_at(src):
		copy_dir(src.path_join(d), dst.path_join(d))


static func backup_world(f: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var dst := "user://backups".path_join(f + "_" + stamp)
	copy_dir(ROOT.path_join(f), dst)
	return dst


static func duplicate_world(f: String) -> String:
	var meta := _read_json_safe(ROOT.path_join(f).path_join("level.json"))
	var nf := unique_folder(str(meta.get("name", f)) + " copy")
	copy_dir(ROOT.path_join(f), ROOT.path_join(nf))
	meta["name"] = str(meta.get("name", f)) + " copy"
	atomic_write(ROOT.path_join(nf).path_join("level.json"), JSON.stringify(meta, "  ").to_utf8_buffer())
	return nf


static func rename_world(f: String, new_name: String) -> void:
	var p := ROOT.path_join(f).path_join("level.json")
	var meta := _read_json_safe(p)
	meta["name"] = new_name
	atomic_write(p, JSON.stringify(meta, "  ").to_utf8_buffer())


func create_world(meta: Dictionary) -> String:
	folder = unique_folder(str(meta.get("name", "New World")))
	dir = ROOT.path_join(folder)
	DirAccess.make_dir_recursive_absolute(dir.path_join("region"))
	level = meta.duplicate(true)
	level["format"] = FORMAT
	level["created"] = int(Time.get_unix_time_from_system())
	level["last_played"] = level["created"]
	save_level(level)
	return folder


func open(f: String) -> bool:
	folder = f
	dir = ROOT.path_join(f)
	level = _read_json_safe(dir.path_join("level.json"))
	if level.is_empty():
		level = _read_json_safe(dir.path_join("level.json.bak"))
		if level.is_empty():
			return false
		push_warning("level.json corrupt; recovered from backup")
	DirAccess.make_dir_recursive_absolute(dir.path_join("region"))
	var lock := dir.path_join("session.lock")
	var f2 := FileAccess.open(lock, FileAccess.WRITE)
	if f2:
		f2.store_string(str(OS.get_process_id()))
		f2.close()
	return true


## Switch chunk storage to another dimension (flushes pending regions of the current one first).
func set_dimension(dim: String) -> void:
	flush()
	_mutex.lock()
	_regions.clear()
	_dirty_regions.clear()
	region_dir = {"the_nether": "DIM-1/region", "the_end": "DIM1/region"}.get(dim, "region")
	_mutex.unlock()
	DirAccess.make_dir_recursive_absolute(dir.path_join(region_dir))


func close() -> void:
	if not dir.is_empty() and FileAccess.file_exists(dir.path_join("session.lock")):
		DirAccess.remove_absolute(dir.path_join("session.lock"))


func save_level(meta: Dictionary) -> bool:
	return atomic_write(dir.path_join("level.json"), level_bytes(meta))


## level.json contents for meta (also remembered as the current level data); written by the caller.
func level_bytes(meta: Dictionary) -> PackedByteArray:
	level = meta
	level["last_played"] = int(Time.get_unix_time_from_system())
	return JSON.stringify(level, "  ").to_utf8_buffer()


static func _region_name(rx: int, rz: int) -> String:
	return "r.%d.%d.rcr" % [rx, rz]


func _region(rx: int, rz: int) -> Dictionary:
	var k := "%d,%d" % [rx, rz]
	if _regions.has(k):
		return _regions[k]
	var reg := {}
	var p := dir.path_join(region_dir).path_join(_region_name(rx, rz))
	for cand in [p, p + ".bak"]:
		if not FileAccess.file_exists(cand):
			continue
		var b := FileAccess.get_file_as_bytes(cand)
		reg = _parse_region(b)
		if reg.has("__corrupt"):
			push_warning("Region %s corrupt, trying backup" % cand)
			reg = {}
			continue
		break
	_regions[k] = reg
	return reg


static func _parse_region(b: PackedByteArray) -> Dictionary:
	var reg := {}
	if b.size() < 8 or b.slice(0, 4).get_string_from_ascii() != MAGIC:
		return {"__corrupt": true} if b.size() > 0 else {}
	var count := b.decode_u32(4)
	var o := 8
	for i in count:
		if o + 32 > b.size():
			return {"__corrupt": true}
		var key := b.decode_s64(o)
		var length := b.decode_u32(o + 8)
		var md5 := b.slice(o + 12, o + 28)
		o += 28
		var blob := b.slice(o, o + length)
		o += length
		if blob.size() != length:
			return {"__corrupt": true}
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update(blob)
		if ctx.finish() != md5:
			push_warning("Chunk blob checksum mismatch; skipping chunk (regenerates)")
			continue
		reg[key] = blob
	return reg


## Thread-safe: returns decoded chunk dictionary or {}.
func load_chunk(cx: int, cz: int) -> Dictionary:
	_mutex.lock()
	var reg := _region(cx >> 5, cz >> 5)
	var blob = reg.get(Coords.chunk_key(cx, cz))
	_mutex.unlock()
	if blob == null:
		return {}
	var bb: PackedByteArray = blob
	if bb.size() < 4:
		return {}
	var raw: PackedByteArray = bb.slice(4).decompress(bb.decode_u32(0), FileAccess.COMPRESSION_ZSTD)
	var d = bytes_to_var(raw)
	return d if d is Dictionary else {}


func save_chunk(c: Chunk) -> void:
	var d := encode_chunk(c, blocks)
	var raw := var_to_bytes(d)
	var blob := PackedByteArray()
	blob.resize(4)
	blob.encode_u32(0, raw.size())
	blob.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	_mutex.lock()
	var reg := _region(c.cx >> 5, c.cz >> 5)
	reg[Coords.chunk_key(c.cx, c.cz)] = blob
	_dirty_regions["%d,%d" % [c.cx >> 5, c.cz >> 5]] = true
	_mutex.unlock()


## Writes every dirty region file. Only the snapshot of the dirty regions holds the mutex: building and writing
## the files (MD5 per chunk, disk I/O) runs unlocked, so chunk loads on the workers never wait for an autosave.
func flush() -> int:
	_mutex.lock()
	var snap := {}
	for k in _dirty_regions:
		snap[k] = (_regions[k] as Dictionary).duplicate()   # shallow: the blobs are copy-on-write
	_dirty_regions.clear()
	_mutex.unlock()
	var n := 0
	for k in snap:
		var parts: PackedStringArray = k.split(",")
		var reg: Dictionary = snap[k]
		var out := PackedByteArray()
		out.append_array(MAGIC.to_ascii_buffer())
		var hdr := PackedByteArray()
		hdr.resize(4)
		hdr.encode_u32(0, reg.size())
		out.append_array(hdr)
		for key in reg:
			var blob: PackedByteArray = reg[key]
			var e := PackedByteArray()
			e.resize(12)
			e.encode_s64(0, key)
			e.encode_u32(8, blob.size())
			out.append_array(e)
			var ctx := HashingContext.new()
			ctx.start(HashingContext.HASH_MD5)
			ctx.update(blob)
			out.append_array(ctx.finish())
			out.append_array(blob)
		if atomic_write(dir.path_join(region_dir).path_join(_region_name(int(parts[0]), int(parts[1]))), out):
			n += 1
	return n


static func encode_chunk(c: Chunk, blocks: BlockRegistry) -> Dictionary:
	var secs: Array = []
	for s in Coords.SECTIONS:
		var sec: Chunk.Section = c.sections[s]
		var names := PackedStringArray()
		for st in sec.pal:
			names.append(blocks.state_string(st))
		var idx = sec.wide if sec.wide.size() > 0 else sec.idx
		secs.append([names, idx])
	var tops := PackedStringArray()
	for st in c.gen_top:
		tops.append(blocks.state_string(st))
	var unknown := {}
	for k in c.unknown_states:
		var lx: int = k & 15
		var lz: int = (k >> 4) & 15
		var y: int = (k >> 8) + Coords.MIN_Y
		if c.get_block(lx, y, lz) == blocks.STONE:
			unknown[k] = c.unknown_states[k]
	return {"v": FORMAT, "cx": c.cx, "cz": c.cz, "secs": secs, "bio": c.biomes, "gs": c.gen_surface, "gt": tops,
		"be": c.block_entities, "ent": c.saved_entities, "unk": unknown, "sched": c.scheduled, "fw": c.feature_writes}


## Worker-safe decode into a fresh Chunk.
static func apply_chunk_data(c: Chunk, d: Dictionary, blocks: BlockRegistry) -> void:
	var secs: Array = d.get("secs", [])
	var lut := {}
	for s in mini(secs.size(), Coords.SECTIONS):
		var e: Array = secs[s]
		var names: PackedStringArray = e[0]
		var pal := PackedInt32Array()
		var unknown_local := {}
		for pi in names.size():
			var n: String = names[pi]
			var st: int
			if lut.has(n):
				st = lut[n]
			else:
				st = blocks.parse_state(n)
				lut[n] = st
			if st < 0:
				unknown_local[pi] = n
				st = blocks.STONE
			pal.append(st)
		var sec: Chunk.Section = c.sections[s]
		sec.pal = pal
		sec.wide = PackedInt32Array()
		sec.idx = PackedByteArray()
		if pal.size() > 1:
			if e[1] is PackedInt32Array:
				sec.wide = e[1]
			else:
				sec.idx = e[1]
		if not unknown_local.is_empty():
			for k in 4096:
				var p: int = sec.wide[k] if sec.wide.size() > 0 else (sec.idx[k] if pal.size() > 1 else 0)
				if unknown_local.has(p):
					var y := Coords.MIN_Y + s * 16 + (k >> 8)
					c.unknown_states[((y - Coords.MIN_Y) << 8) | (k & 255)] = unknown_local[p]
	var unk: Dictionary = d.get("unk", {})
	for k in unk:
		c.unknown_states[k] = unk[k]
	c.biomes = d.get("bio", c.biomes)
	c.gen_surface = d.get("gs", PackedInt32Array())
	var tops: PackedStringArray = d.get("gt", PackedStringArray())
	c.gen_top.resize(tops.size())
	for i in tops.size():
		var t: String = tops[i]
		if not lut.has(t):
			lut[t] = maxi(0, blocks.parse_state(t))
		c.gen_top[i] = lut[t]
	c.block_entities = d.get("be", {})
	c.saved_entities = d.get("ent", [])
	c.scheduled = d.get("sched", [])
	c.feature_writes = d.get("fw", PackedInt32Array())
	c.features_ready = true
	c.modified = true
	c.recompute_heightmap(blocks)
