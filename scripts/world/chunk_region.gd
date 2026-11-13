## ChunkRegion — 3x3 chunk neighbourhood accessor used by feature decoration and lighting jobs.
## Why: features (trees, ores) may cross chunk borders; writes are confined to the centre chunk to keep
## decoration order-independent (Java's WorldGenRegion idea, simplified: centre-write, 3x3 read).
## Contract: get_block(x,y,z) world coords; set_block writes only inside the centre chunk (returns false otherwise).
class_name ChunkRegion
extends RefCounted

var chunks: Array = []  # 9 entries, index (dz+1)*3 + (dx+1)
var cx: int
var cz: int
var writes_outside := 0


func _init(center_x: int, center_z: int, nine: Array) -> void:
	cx = center_x
	cz = center_z
	chunks = nine


func chunk_at(x: int, z: int) -> Chunk:
	var dx := (x >> 4) - cx
	var dz := (z >> 4) - cz
	if dx < -1 or dx > 1 or dz < -1 or dz > 1:
		return null
	return chunks[(dz + 1) * 3 + (dx + 1)]


func get_block(x: int, y: int, z: int) -> int:
	var c := chunk_at(x, z)
	if c == null:
		return 0
	return c.get_block(x & 15, y, z & 15)


func set_block(x: int, y: int, z: int, st: int) -> bool:
	if (x >> 4) != cx or (z >> 4) != cz:
		writes_outside += 1
		return false
	var c: Chunk = chunks[4]
	c.set_block(x & 15, y, z & 15, st)
	return true


func height(x: int, z: int) -> int:
	var c := chunk_at(x, z)
	if c == null:
		return Coords.MIN_Y
	return c.heightmap[(x & 15) + (z & 15) * 16]
