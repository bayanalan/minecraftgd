// GUI item icon rasteriser: native port of ItemIcons._raster (same triangles, barycentric test, z rule and texel
// lookup), so block item icons can be drawn at screen resolution (64 px) without a GDScript pixel loop.
//
// icon_raster(quads, texs, sizes, size) -> [PackedByteArray rgba (size * size * 4)]
//   quads: PackedFloat32Array, 24 floats per quad: 4 x (screen x, screen y, depth, u, v), texture index, r, g, b
//          (texture index + 0.5: translucent quad - texels blend over the pixel like Java's translucent item sheet,
//          straight-alpha "over"; otherwise written opaque; alpha < 26 is discarded either way)
//   texs: Array of PackedByteArray (RGBA8 texture data), sizes: PackedInt32Array (w, h per texture)
#include "native.h"
#include <algorithm>
#include <cmath>
#include <vector>

using namespace gdx;

namespace {
bool fn_icon_raster(const Args &a, void *ret) {
	const void *qv = a.obj(0, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
	const void *tv = a.obj(1, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *sv = a.obj(2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	int size = (int)a.i(3);
	if (!qv || !tv || !sv || size < 1 || size > 512) return false;
	int64_t nq = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, qv) / 24;
	const float *q = nq ? f32(qv) : nullptr;
	int64_t nt = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, tv);
	const int32_t *sz = i32(sv);
	if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, sv) < nt * 2) return false;
	std::vector<const uint8_t *> tex((size_t)nt, nullptr);
	for (int64_t k = 0; k < nt; k++) {
		const void *e = array_get(tv, k);
		if (e && variant_get_type((GDExtensionConstVariantPtr)e) == GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY) {
			const void *pb = internal(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)((GDExtensionVariantPtr)e);
			if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, pb) >= (int64_t)sz[k * 2] * sz[k * 2 + 1] * 4) tex[(size_t)k] = bytes(pb);
		}
	}
	std::vector<float> zb((size_t)size * size, -INFINITY);
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr(), (int64_t)size * size * 4);
	uint8_t *o = bytes_w(out.ptr());
	std::fill(o, o + (size_t)size * size * 4, 0);
	static const int TRI[2][3] = {{0, 1, 2}, {0, 2, 3}};
	for (int64_t qi = 0; qi < nq; qi++) {
		const float *Q = q + qi * 24;
		int ti = (int)Q[20];
		bool tl = Q[20] - (float)ti > 0.25f;
		if (ti < 0 || ti >= nt || !tex[(size_t)ti]) continue;
		const uint8_t *T = tex[(size_t)ti];
		int tw = sz[ti * 2], th = sz[ti * 2 + 1];
		float mr = Q[21], mg = Q[22], mb = Q[23];
		for (int t = 0; t < 2; t++) {
			const float *A = Q + TRI[t][0] * 5, *B = Q + TRI[t][1] * 5, *C = Q + TRI[t][2] * 5;
			double ax = A[0], ay = A[1], bx = B[0], by = B[1], cx = C[0], cy = C[1];
			int minx = std::clamp((int)std::floor(std::min(ax, std::min(bx, cx))), 0, size - 1);
			int maxx = std::clamp((int)std::ceil(std::max(ax, std::max(bx, cx))), 0, size - 1);
			int miny = std::clamp((int)std::floor(std::min(ay, std::min(by, cy))), 0, size - 1);
			int maxy = std::clamp((int)std::ceil(std::max(ay, std::max(by, cy))), 0, size - 1);
			double area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
			if (std::fabs(area) < 1e-6) continue;
			for (int y = miny; y <= maxy; y++)
				for (int x = minx; x <= maxx; x++) {
					double px = x + 0.5, py = y + 0.5;
					double w0 = ((bx - px) * (cy - py) - (by - py) * (cx - px)) / area;
					double w1 = ((cx - px) * (ay - py) - (cy - py) * (ax - px)) / area;
					double w2 = 1.0 - w0 - w1;
					if (w0 < -0.001 || w1 < -0.001 || w2 < -0.001) continue;
					float z = (float)(A[2] * w0 + B[2] * w1 + C[2] * w2);
					float &zr = zb[(size_t)y * size + x];
					if (z < zr) continue;
					double u = A[3] * w0 + B[3] * w1 + C[3] * w2;
					double v = A[4] * w0 + B[4] * w1 + C[4] * w2;
					double fu = std::fmod(u, 1.0001); if (fu < 0) fu += 1.0001;
					double fv = std::fmod(v, 1.0001); if (fv < 0) fv += 1.0001;
					int tx = std::clamp((int)(fu * tw), 0, tw - 1), ty = std::clamp((int)(fv * th), 0, th - 1);
					const uint8_t *px4 = T + ((size_t)ty * tw + tx) * 4;
					if (px4[3] < 26) continue;
					zr = z;
					uint8_t *d = o + ((size_t)y * size + x) * 4;
					int sr = std::clamp((int)std::lround(px4[0] * mr), 0, 255);
					int sg = std::clamp((int)std::lround(px4[1] * mg), 0, 255);
					int sb = std::clamp((int)std::lround(px4[2] * mb), 0, 255);
					if (tl && px4[3] < 255) {
						double sa = px4[3] / 255.0, da = d[3] / 255.0;
						double oa = sa + da * (1.0 - sa);
						double k = da * (1.0 - sa);
						d[0] = (uint8_t)std::clamp((int)std::lround((sr * sa + d[0] * k) / oa), 0, 255);
						d[1] = (uint8_t)std::clamp((int)std::lround((sg * sa + d[1] * k) / oa), 0, 255);
						d[2] = (uint8_t)std::clamp((int)std::lround((sb * sa + d[2] * k) / oa), 0, 255);
						d[3] = (uint8_t)std::clamp((int)std::lround(oa * 255.0), 0, 255);
					} else {
						d[0] = (uint8_t)sr;
						d[1] = (uint8_t)sg;
						d[2] = (uint8_t)sb;
						d[3] = 255;
					}
				}
		}
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr());
	return true;
}
}  // namespace

void register_icons(const char *cls) {
	register_method(cls, "icon_raster", fn_icon_raster, 4);
}
