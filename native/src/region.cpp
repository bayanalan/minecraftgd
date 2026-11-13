// Feature-region helpers: expand the 3x3 chunk sections around a feature origin into one flat, job-private block
// array so feature placement reads/writes plain memory (no shared chunk objects across worker threads).
//   region_flat(secs: Array[9] of (Array[24] of [pal: PackedInt32Array, idx: PackedByteArray, wide: PackedInt32Array]) or null)
//     -> [PackedInt32Array(9 * 98304)]   index ci * 98304 + ((y + 64) << 8 | lz << 4 | lx), ci = dz * 3 + dx (0..8)
#include "native.h"
#include <cstring>

using namespace gdx;

namespace {

bool fn_region_flat(const Args &a, void *ret) {
	const void *secs = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	if (!secs || size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, secs) != 9) return false;
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, out.ptr(), 9 * 98304);
	int32_t *o = i32_w(out.ptr());
	memset(o, 0, sizeof(int32_t) * 9 * 98304);
	for (int ci = 0; ci < 9; ci++) {
		const void *cv = array_get(secs, ci);
		if (variant_get_type((GDExtensionConstVariantPtr)cv) != GDEXTENSION_VARIANT_TYPE_ARRAY) continue;
		const void *carr = internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)cv);
		int64_t ns = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, carr);
		for (int64_t s = 0; s < ns && s < 24; s++) {
			const void *earr = internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)array_get(carr, s));
			const void *pal = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)array_get(earr, 0));
			const void *idx = internal(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)((GDExtensionVariantPtr)array_get(earr, 1));
			const void *wide = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)array_get(earr, 2));
			int64_t npal = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pal);
			if (npal == 0) continue;
			const int32_t *p = i32(pal);
			int32_t *dst = o + (size_t)ci * 98304 + (size_t)s * 4096;
			if (npal == 1) {
				if (p[0] != 0) for (int k = 0; k < 4096; k++) dst[k] = p[0];
				continue;
			}
			int64_t nw = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wide);
			if (nw >= 4096) {
				const int32_t *w = i32(wide);
				for (int k = 0; k < 4096; k++) dst[k] = p[w[k]];
			} else if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, idx) >= 4096) {
				const uint8_t *ix = bytes(idx);
				for (int k = 0; k < 4096; k++) dst[k] = p[ix[k]];
			}
		}
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, out.ptr());
	return true;
}

} // namespace

void register_region(const char *cls) {
	register_method(cls, "region_flat", fn_region_flat, 1);
}
