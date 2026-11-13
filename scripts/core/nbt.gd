## NBT — reader for Java Named Binary Tag data (big-endian, optionally gzip-compressed), used for structure
## templates (data/minecraft/structure/*.nbt) read from the user's installed jar.
## Contract: NBT.parse(bytes) -> Dictionary (root compound; {} on error). Lists -> Array, byte/int/long arrays ->
## PackedByteArray / PackedInt32Array / PackedInt64Array, numbers -> int/float, strings -> String.
class_name NBT
extends RefCounted

var b: PackedByteArray
var o := 0


static func parse(data: PackedByteArray) -> Dictionary:
	var raw := data
	if data.size() >= 2 and data[0] == 0x1f and data[1] == 0x8b:
		raw = data.decompress_dynamic(64 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
	if raw.size() < 3 or raw[0] != 10:
		return {}
	var r := NBT.new()
	r.b = raw
	r.o = 1
	r._str()   # root name
	var v = r._payload(10)
	return v if v is Dictionary else {}


func _u8() -> int:
	var v := b[o]
	o += 1
	return v


func _i16() -> int:
	var v := (b[o] << 8) | b[o + 1]
	o += 2
	return v - 0x10000 if v >= 0x8000 else v


func _i32() -> int:
	var v := (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]
	o += 4
	return v - 0x100000000 if v >= 0x80000000 else v


func _i64() -> int:
	var v := 0
	for i in 8:
		v = (v << 8) | b[o + i]
	o += 8
	return v


func _f32() -> float:
	var t := PackedByteArray([b[o + 3], b[o + 2], b[o + 1], b[o]])
	o += 4
	return t.decode_float(0)


func _f64() -> float:
	var t := PackedByteArray([b[o + 7], b[o + 6], b[o + 5], b[o + 4], b[o + 3], b[o + 2], b[o + 1], b[o]])
	o += 8
	return t.decode_double(0)


func _str() -> String:
	var n := (b[o] << 8) | b[o + 1]
	o += 2
	var s := b.slice(o, o + n).get_string_from_utf8()
	o += n
	return s


func _payload(t: int):
	match t:
		1:
			var v := _u8()
			return v - 256 if v >= 128 else v
		2:
			return _i16()
		3:
			return _i32()
		4:
			return _i64()
		5:
			return _f32()
		6:
			return _f64()
		7:
			var n := _i32()
			var a := b.slice(o, o + n)
			o += n
			return a
		8:
			return _str()
		9:
			var et := _u8()
			var n2 := _i32()
			var arr: Array = []
			for i in n2:
				arr.append(_payload(et))
			return arr
		10:
			var d := {}
			while o < b.size():
				var tt := _u8()
				if tt == 0:
					break
				var name := _str()
				d[name] = _payload(tt)
			return d
		11:
			var n3 := _i32()
			var ia := PackedInt32Array()
			ia.resize(n3)
			for i in n3:
				ia[i] = _i32()
			return ia
		12:
			var n4 := _i32()
			var la := PackedInt64Array()
			la.resize(n4)
			for i in n4:
				la[i] = _i64()
			return la
	return null
