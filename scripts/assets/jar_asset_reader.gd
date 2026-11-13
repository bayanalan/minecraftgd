## JarAssetReader — safe read-only access to a client JAR (ZIP): the central directory is parsed ONCE into a
## name -> entry index (Godot's ZIPReader does a linear scan per file, too slow for 34k entries). Deflated
## entries are inflated by wrapping the raw deflate stream as gzip using the ZIP's stored CRC32 + size.
## Contract: open(path) -> Error; has(path); read_bytes/read_text/read_json; list(prefix, ext).
## Invariants: names validated (no traversal/absolute paths); per-entry size cap; extension allow-list;
## the archive bytes are immutable after open, so reads are safe from any thread.
class_name JarAssetReader
extends RefCounted

const MAX_ENTRY_BYTES := 64 * 1024 * 1024
const ALLOWED_EXT := ["png", "json", "mcmeta", "txt", "nbt", "fsh", "vsh", "glsl", "bin", "properties"]

var data := PackedByteArray()
var entries: Dictionary = {}   # name -> PackedInt64Array [method, crc, csize, usize, local_off]
var files: Dictionary:
	get:
		return entries
var path: String = ""
## Resource pack overlays, highest priority first: {name, reader (JarAssetReader for zips) or dir, files}.
## Only assets/ paths are overridden (resource packs never replace game data).
var overlays: Array = []


func open(p: String) -> Error:
	if not FileAccess.file_exists(p):
		return ERR_FILE_NOT_FOUND
	data = FileAccess.get_file_as_bytes(p)
	if data.size() < 22:
		return ERR_FILE_CORRUPT
	path = p
	entries.clear()
	# locate End Of Central Directory (signature 0x06054b50) within the last 64 KiB + 22
	var eocd := -1
	var lo := maxi(0, data.size() - 65557)
	for i in range(data.size() - 22, lo - 1, -1):
		if data[i] == 0x50 and data[i + 1] == 0x4b and data[i + 2] == 0x05 and data[i + 3] == 0x06:
			eocd = i
			break
	if eocd < 0:
		return ERR_FILE_CORRUPT
	var count := data.decode_u16(eocd + 10)
	var cd := data.decode_u32(eocd + 16)
	var o := cd
	for n in count:
		if o + 46 > data.size() or data.decode_u32(o) != 0x02014b50:
			return ERR_FILE_CORRUPT
		var method := data.decode_u16(o + 10)
		var crc := data.decode_u32(o + 16)
		var csize := data.decode_u32(o + 20)
		var usize := data.decode_u32(o + 24)
		var nlen := data.decode_u16(o + 28)
		var elen := data.decode_u16(o + 30)
		var clen := data.decode_u16(o + 32)
		var loff := data.decode_u32(o + 42)
		var name := data.slice(o + 46, o + 46 + nlen).get_string_from_utf8()
		o += 46 + nlen + elen + clen
		if name.ends_with("/") or not is_safe_name(name):
			continue
		entries[name] = PackedInt64Array([method, crc, csize, usize, loff])
	return OK


func close() -> void:
	data = PackedByteArray()
	entries.clear()


static func is_safe_name(n: String) -> bool:
	if n.begins_with("/") or n.begins_with("\\") or n.contains("..") or n.contains(":") or n.contains("\\"):
		return false
	return true


## Adds a resource pack (folder or .zip with pack.mcmeta). Returns an error message or "".
func add_overlay(pack_path: String) -> String:
	var ov := {"name": pack_path.get_file(), "reader": null, "dir": "", "files": {}}
	if DirAccess.dir_exists_absolute(pack_path):
		if not FileAccess.file_exists(pack_path.path_join("pack.mcmeta")):
			return "missing pack.mcmeta"
		ov["dir"] = pack_path
		_walk(pack_path, "assets", ov["files"])
	elif pack_path.to_lower().ends_with(".zip"):
		var r := JarAssetReader.new()
		if r.open(pack_path) != OK:
			return "cannot open zip"
		if not r.entries.has("pack.mcmeta"):
			return "missing pack.mcmeta"
		ov["reader"] = r
		for f in r.entries:
			if str(f).begins_with("assets/"):
				ov["files"][f] = true
	else:
		return "not a folder or .zip"
	overlays.append(ov)
	return ""


func _walk(root: String, rel: String, out: Dictionary) -> void:
	var d := root.path_join(rel)
	for f in DirAccess.get_files_at(d):
		if is_safe_name(f):
			out[rel + "/" + f] = true
	for sub in DirAccess.get_directories_at(d):
		if is_safe_name(sub):
			_walk(root, rel + "/" + sub, out)


func _overlay_for(p: String) -> Dictionary:
	if overlays.is_empty() or not p.begins_with("assets/"):
		return {}
	for ov in overlays:
		if (ov["files"] as Dictionary).has(p):
			return ov
	return {}


func has(p: String) -> bool:
	return entries.has(p) or not _overlay_for(p).is_empty()


func read_bytes(p: String) -> PackedByteArray:
	var ov := _overlay_for(p)
	if not ov.is_empty():
		if not ALLOWED_EXT.has(p.get_extension().to_lower()) or not is_safe_name(p):
			return PackedByteArray()
		if ov["reader"] != null:
			return (ov["reader"] as JarAssetReader).read_bytes(p)
		var fp := str(ov["dir"]).path_join(p)
		if FileAccess.file_exists(fp):
			var b := FileAccess.get_file_as_bytes(fp)
			if b.size() <= MAX_ENTRY_BYTES:
				return b
	var e = entries.get(p)
	if e == null:
		return PackedByteArray()
	if not ALLOWED_EXT.has(p.get_extension().to_lower()):
		push_warning("JarAssetReader: blocked extension " + p)
		return PackedByteArray()
	var en: PackedInt64Array = e
	var usize := int(en[3])
	if usize > MAX_ENTRY_BYTES:
		push_warning("JarAssetReader: entry too large " + p)
		return PackedByteArray()
	var loff := int(en[4])
	if data.decode_u32(loff) != 0x04034b50:
		return PackedByteArray()
	var start := loff + 30 + data.decode_u16(loff + 26) + data.decode_u16(loff + 28)
	var raw := data.slice(start, start + int(en[2]))
	if en[0] == 0:
		return raw
	if en[0] != 8:
		push_warning("JarAssetReader: unsupported compression %d in %s" % [en[0], p])
		return PackedByteArray()
	# wrap raw deflate as a gzip member: header + data + CRC32 + ISIZE (little endian)
	var gz := PackedByteArray([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff])
	gz.append_array(raw)
	var tail := PackedByteArray()
	tail.resize(8)
	tail.encode_u32(0, int(en[1]))
	tail.encode_u32(4, usize & 0xFFFFFFFF)
	gz.append_array(tail)
	var out := gz.decompress(usize, FileAccess.COMPRESSION_GZIP)
	if out.size() != usize:
		push_warning("JarAssetReader: inflate failed for " + p)
		return PackedByteArray()
	return out


func read_text(p: String) -> String:
	var b := read_bytes(p)
	return b.get_string_from_utf8() if b.size() > 0 else ""


func read_json(p: String) -> Variant:
	var t := read_text(p)
	if t.is_empty():
		return null
	var j := JSON.new()
	if j.parse(t) != OK:
		push_warning("JSON parse error in %s line %d: %s" % [p, j.get_error_line(), j.get_error_message()])
		return null
	return j.data


func list(prefix: String, ext: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for f in entries:
		var s: String = f
		if s.begins_with(prefix) and (ext.is_empty() or s.ends_with(ext)):
			out.append(s)
			seen[s] = true
	for ov in overlays:
		for f2 in ov["files"]:
			var s2: String = f2
			if not seen.has(s2) and s2.begins_with(prefix) and (ext.is_empty() or s2.ends_with(ext)):
				out.append(s2)
				seen[s2] = true
	out.sort()
	return out
