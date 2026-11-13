## Coords — integer world/chunk/section coordinate math.
## Why: Minecraft-compatible floor-div/floor-mod for negative coordinates and compact int64 chunk keys.
## Contract: block (x,y,z) is the cell [x,x+1)x[y,y+1)x[z,z+1); visual position == block min corner minus floating origin.
## Invariants: chunk = 16x16 XZ, section = 16^3, overworld Y in [-64, 320).
class_name Coords

const CHUNK := 16
const MIN_Y := -64
const HEIGHT := 384
const MAX_Y := MIN_Y + HEIGHT  # exclusive
const SECTIONS := 24
const SEA_LEVEL := 63
const BORDER := 29999984


static func floor_div(a: int, b: int) -> int:
	var q := a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


static func floor_mod(a: int, b: int) -> int:
	var m := a % b
	if m != 0 and ((m < 0) != (b < 0)):
		m += b
	return m


static func chunk_key(cx: int, cz: int) -> int:
	return (cx << 32) | (cz & 0xFFFFFFFF)


static func key_x(key: int) -> int:
	return key >> 32


static func key_z(key: int) -> int:
	return (key << 32) >> 32


## Index inside a 16x16x16 section: x fastest, then z, then y (YZX order like Minecraft).
static func sidx(lx: int, ly: int, lz: int) -> int:
	return (ly << 8) | (lz << 4) | lx


static func section_of_y(y: int) -> int:
	return (y - MIN_Y) >> 4


static func ufloor(v: float) -> int:
	return int(floor(v))
