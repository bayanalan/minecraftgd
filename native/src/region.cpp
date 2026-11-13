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

// region_meta(surf: Array[9], floor: Array[9], bio: Array[9]) -> [gs, gf, bio, hl, hstate]  (Features._load_region's
//   per-chunk pristine data; entries are PackedInt32Array(256) / PackedByteArray(1536) or anything else for none)
//   gs, gf: PackedInt32Array(2304) ci * 256 + lx + lz * 16; bio: PackedByteArray(9 * 1536); hstate: PackedByteArray(9)
//   0 none, 1 surface, 2 surface + floor; hl: PackedInt32Array(4 * 2304) live heightmaps primed from the pristine ones
//   (48 x 48 columns lz * 48 + lx: WORLD_SURFACE_WG, OCEAN_FLOOR_WG, WORLD_SURFACE, MOTION_BLOCKING; -64 without data)
bool fn_region_meta(const Args &a, void *ret) {
	const void *sv = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *fv = a.obj(1, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *bv = a.obj(2, GDEXTENSION_VARIANT_TYPE_ARRAY);
	if (!sv || !fv || !bv || size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, sv) != 9 || size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, fv) != 9 || size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, bv) != 9) return false;
	auto packed = [](const void *arr, int k, GDExtensionVariantType t, int64_t need) -> const void * {
		const void *e = array_get(arr, k);
		if (!e || variant_get_type((GDExtensionConstVariantPtr)e) != t) return nullptr;
		const void *p = internal(t)((GDExtensionVariantPtr)e);
		return size_of(t, p) >= need ? p : nullptr;
	};
	Owned gs(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY), gf(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY), hl(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	Owned bio(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY), hs(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, gs.ptr(), 2304);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, gf.ptr(), 2304);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, hl.ptr(), 4 * 2304);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, bio.ptr(), 9 * 1536);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, hs.ptr(), 9);
	int32_t *G = i32_w(gs.ptr()), *F = i32_w(gf.ptr()), *H = i32_w(hl.ptr());
	uint8_t *B = bytes_w(bio.ptr()), *S = bytes_w(hs.ptr());
	memset(G, 0, 2304 * 4); memset(F, 0, 2304 * 4); memset(B, 0, 9 * 1536); memset(S, 0, 9);
	for (int k = 0; k < 4 * 2304; k++) H[k] = -64;
	for (int ci = 0; ci < 9; ci++) {
		if (const void *s = packed(sv, ci, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, 256)) {
			if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, s) == 256) {
				memcpy(G + ci * 256, i32(s), 256 * 4);
				S[ci] = 1;
				const void *f = packed(fv, ci, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, 256);
				if (f && size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, f) == 256) {
					memcpy(F + ci * 256, i32(f), 256 * 4);
					S[ci] = 2;
				}
			}
		}
		const void *e = array_get(bv, ci);
		if (e && variant_get_type((GDExtensionConstVariantPtr)e) == GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY) {
			const void *bp = internal(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)((GDExtensionVariantPtr)e);
			int64_t nb = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, bp);
			if (nb > 0) memcpy(B + ci * 1536, bytes(bp), (size_t)(nb < 1536 ? nb : 1536));
		}
	}
	for (int lz = 0; lz < 48; lz++)
		for (int lx = 0; lx < 48; lx++) {
			int hci = (lz >> 4) * 3 + (lx >> 4);
			if (S[hci] != 2) continue;
			int hhi = hci * 256 + (lx & 15) + (lz & 15) * 16;
			int col = lz * 48 + lx;
			int top = G[hhi] + 1;
			H[col] = top; H[2304 + col] = F[hhi]; H[4608 + col] = top; H[6912 + col] = top;
		}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 5);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, gs.ptr());
	array_set_native(ret, 1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, gf.ptr());
	array_set_native(ret, 2, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, bio.ptr());
	array_set_native(ret, 3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, hl.ptr());
	array_set_native(ret, 4, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, hs.ptr());
	return true;
}

} // namespace

void register_region(const char *cls) {
	register_method(cls, "region_flat", fn_region_flat, 1);
	register_method(cls, "region_meta", fn_region_meta, 3);
}
