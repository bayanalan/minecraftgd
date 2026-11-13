// Java 26.3 CloudRenderer face list (buildMesh / addCellGeometryToBuffer / addCellFaces), rebuilt when the camera
// enters another 12-block cloud cell or changes its position relative to the cloud layer.
//
// cloud_faces(cells, w, h, cell_x, cell_z, rel, fancy, radius) -> [PackedByteArray faces, face count]
//   cells: w * h bytes from clouds.png: bit0 cloud, bit1 north (z-1) empty, bit2 east (x+1) empty,
//          bit3 south (z+1) empty, bit4 west (x-1) empty (neighbours wrap around the texture).
//   rel: 0 above the clouds, 1 below, 2 inside (Java RelativeCameraPos).
//   Output: 8 bytes per face, near to far (Java's ring order, so depth writes keep only the nearest surface):
//     uint32 (dx & 0xFFFF) | (dz << 16), uint32 direction (Java 3D data value) | flags
//     (16 inside face: reversed winding, 32 use the top colour).
#include "native.h"
#include <vector>
#include <cstdlib>

using namespace gdx;

namespace {
enum { DOWN = 0, UP = 1, NORTH = 2, SOUTH = 3, WEST = 4, EAST = 5 };
const uint32_t INSIDE = 16, TOPCOL = 32;

inline void face(std::vector<uint32_t> &o, int dx, int dz, uint32_t d) {
	o.push_back((uint32_t)(dx & 0xFFFF) | ((uint32_t)(dz & 0xFFFF) << 16));
	o.push_back(d);
}

bool fn_cloud_faces(const Args &a, void *ret) {
	const void *cv = a.obj(0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!cv) return false;
	const uint8_t *cells = bytes(cv);
	int w = (int)a.i(1), h = (int)a.i(2);
	int cx = (int)a.i(3), cz = (int)a.i(4);
	int rel = (int)a.i(5);
	bool fancy = a.i(6) != 0;
	int k = (int)a.i(7);
	if (!cells || w <= 0 || h <= 0 || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, cv) < (int64_t)w * h) return false;
	std::vector<uint32_t> o;
	o.reserve(65536);
	auto cell = [&](int dx, int dz) {
		int x = ((cx + dx) % w + w) % w;
		int z = ((cz + dz) % h + h) % h;
		uint8_t c = cells[x + z * w];
		if (!(c & 1)) return;
		if (!fancy) {
			face(o, dx, dz, DOWN | TOPCOL);
			return;
		}
		if (rel != 1) face(o, dx, dz, UP);
		if (rel != 0) face(o, dx, dz, DOWN);
		if ((c & 2) && dz > 0) face(o, dx, dz, NORTH);
		if ((c & 8) && dz < 0) face(o, dx, dz, SOUTH);
		if ((c & 16) && dx > 0) face(o, dx, dz, WEST);
		if ((c & 4) && dx < 0) face(o, dx, dz, EAST);
		if (std::abs(dx) <= 1 && std::abs(dz) <= 1)
			for (uint32_t d = 0; d < 6; d++) face(o, dx, dz, d | INSIDE);
	};
	for (int n = 0; n <= 2 * k; ++n) {
		for (int x = -n; x <= n; ++x) {
			int z = n - std::abs(x);
			if (z >= 0 && z <= k && x * x + z * z <= k * k) {
				if (z != 0) cell(x, -z);
				cell(x, z);
			}
		}
	}
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr(), (int64_t)o.size() * 4);
	if (!o.empty()) {
		uint8_t *dst = bytes_w(out.ptr());
		const uint8_t *src = reinterpret_cast<const uint8_t *>(o.data());
		for (size_t i = 0; i < o.size() * 4; i++) dst[i] = src[i];
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 2);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr());
	array_set_int(ret, 1, (int64_t)(o.size() / 2));
	return true;
}
} // namespace

void register_clouds(const char *cls) {
	register_method(cls, "cloud_faces", fn_cloud_faces, 8);
}
