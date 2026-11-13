// Native port of scripts/world/lighting.gd (Lighting.compute): identical seeds, BFS order and output layout.
// light(snaps: Array[9] of Array[24] of [pal: PackedInt32Array, idx: PackedByteArray, wide: PackedInt32Array] or null,
//       hms: Array[9] of PackedInt32Array(256) or null, opacity: PackedByteArray, emit: PackedByteArray)
//   -> Array[24]: int (uniform section light) or PackedByteArray(18*18*16) of sky<<4|block.
#include "native.h"
#include <vector>
#include <algorithm>

using namespace gdx;

namespace {

const int W = 48, LAYER = W * W, HEIGHT = 384, MIN_Y = -64, MAX_Y = 320, SECTIONS = 24, HALO = 18, HSEC = HALO * HALO * 16;

struct Sec {
	const int32_t *pal = nullptr;
	int64_t npal = 0;
	const uint8_t *idx = nullptr;
	int64_t nidx = 0;
	const int32_t *wide = nullptr;
	int64_t nwide = 0;
};

struct Region {
	Sec sec[9][SECTIONS];
	bool present[9] = {};
	const uint8_t *opac = nullptr;
	int64_t nopac = 0;
	const uint8_t *emit = nullptr;
	int64_t nemit = 0;

	inline int32_t sec_state(const Sec &e, int k) const {
		if (e.npal == 1) return e.pal[0];
		if (e.nwide > 0) return e.pal[e.wide[k]];
		return e.pal[e.idx[k]];
	}
	inline int32_t state(int x, int y, int z) const {
		if (y < MIN_Y || y >= MAX_Y) return 0;
		int ci = (z >> 4) * 3 + (x >> 4);
		if (!present[ci]) return -1;
		const Sec &e = sec[ci][(y - MIN_Y) >> 4];
		int k = ((y & 15) << 8) | ((z & 15) << 4) | (x & 15);
		return sec_state(e, k);
	}
	inline int op(int32_t st) const {
		// GDScript packed arrays accept index -1 (last element); states here are never -1 for present chunks
		if (st < 0) return opac[nopac - 1];
		return st < nopac ? opac[st] : 15;
	}
	inline int em(int32_t st) const { return (st >= 0 && st < nemit) ? emit[st] : 0; }
};

// per-section opacity cache for the BFS (uniform value or 4096 bytes)
struct OpacCache {
	int uni[9 * SECTIONS];
	bool built[9 * SECTIONS];
	std::vector<uint8_t> data[9 * SECTIONS];
	OpacCache() { std::fill(built, built + 9 * SECTIONS, false); }
	inline int get(const Region &r, int ci, int s, int k) {
		int key = ci * SECTIONS + s;
		if (!built[key]) {
			built[key] = true;
			uni[key] = -1;
			if (!r.present[ci]) {
				uni[key] = 15;
			} else {
				const Sec &e = r.sec[ci][s];
				if (e.npal == 1) {
					uni[key] = r.op(e.pal[0]);
				} else {
					bool same = true;
					int first = r.op(e.pal[0]);
					for (int64_t i = 1; i < e.npal; i++) if (r.op(e.pal[i]) != first) { same = false; break; }
					if (same) {
						uni[key] = first;
					} else {
						std::vector<uint8_t> po(e.npal);
						for (int64_t i = 0; i < e.npal; i++) po[i] = (uint8_t)r.op(e.pal[i]);
						data[key].resize(4096);
						uint8_t *o = data[key].data();
						if (e.nwide > 0) for (int i = 0; i < 4096; i++) o[i] = po[e.wide[i]];
						else for (int i = 0; i < 4096; i++) o[i] = po[e.idx[i]];
					}
				}
			}
		}
		if (uni[key] >= 0) return uni[key];
		return data[key][k];
	}
};

void bfs(std::vector<int32_t> &q, uint8_t *lt, const int32_t *hm, const Region &r, OpacCache &oc, bool is_sky, uint8_t *touched) {
	static const int dxs[6] = {0, 0, 0, 0, -1, 1};
	static const int dys[6] = {-1, 1, 0, 0, 0, 0};
	static const int dzs[6] = {0, 0, -1, 1, 0, 0};
	size_t head = 0;
	while (head < q.size()) {
		int i = q[head++];
		int v = lt[i];
		if (v <= 1) continue;
		int x = i % W;
		int z = (i / W) % W;
		int yy = i / LAYER;
		touched[yy >> 4] = 1;
		for (int d = 0; d < 6; d++) {
			int nx = x + dxs[d], ny = yy + dys[d], nz = z + dzs[d];
			if (nx < 0 || nx >= W || nz < 0 || nz >= W || ny < 0 || ny >= HEIGHT) continue;
			if (is_sky && ny + MIN_Y >= hm[nz * W + nx]) continue;
			int ni = (ny * W + nz) * W + nx;
			if (lt[ni] >= v - 1) continue;
			int o = oc.get(r, (nz >> 4) * 3 + (nx >> 4), ny >> 4, ((ny & 15) << 8) | ((nz & 15) << 4) | (nx & 15));
			if (o >= 15) continue;
			int nv = v - std::max(1, o);
			if (nv > lt[ni]) {
				lt[ni] = (uint8_t)nv;
				q.push_back(ni);
			}
		}
	}
}

bool fn_light(const Args &a, void *ret) {
	const void *snaps = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *hms = a.obj(1, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *opac = a.obj(2, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	const void *emit = a.obj(3, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!snaps || !hms || !opac || !emit) return false;
	Region *rp = new Region();
	Region &r = *rp;
	r.opac = bytes(opac);
	r.nopac = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, opac);
	r.emit = bytes(emit);
	r.nemit = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, emit);
	std::vector<int32_t> hm(LAYER);
	for (int ci = 0; ci < 9; ci++) {
		const void *sv = array_get(snaps, ci);
		if (variant_get_type(sv) == GDEXTENSION_VARIANT_TYPE_ARRAY) {
			const void *sarr = internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)sv);
			r.present[ci] = true;
			for (int s = 0; s < SECTIONS; s++) {
				const void *ev = array_get(sarr, s);
				const void *earr = internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)ev);
				const void *pal = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)array_get(earr, 0));
				const void *idx = internal(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)((GDExtensionVariantPtr)array_get(earr, 1));
				const void *wide = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)array_get(earr, 2));
				Sec &e = r.sec[ci][s];
				e.npal = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pal);
				e.pal = i32(pal);
				e.nidx = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, idx);
				e.idx = bytes(idx);
				e.nwide = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wide);
				e.wide = i32(wide);
			}
		}
		const void *hv = array_get(hms, ci);
		const int32_t *h = nullptr;
		if (variant_get_type(hv) == GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)
			h = i32(internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)hv));
		int cx = ci % 3, cz = ci / 3;
		for (int z = 0; z < 16; z++)
			for (int x = 0; x < 16; x++)
				hm[(cz * 16 + z) * W + cx * 16 + x] = h ? h[x + z * 16] : MAX_Y;
	}
	std::vector<uint8_t> sky(LAYER * HEIGHT, 0), blk(LAYER * HEIGHT, 0);
	uint8_t touched[SECTIONS] = {};
	std::vector<int32_t> q;
	q.reserve(65536);
	// sky seeds
	for (int z = 0; z < W; z++) {
		for (int x = 0; x < W; x++) {
			int h0 = hm[z * W + x];
			if (h0 >= MAX_Y) continue;
			if (h0 > MIN_Y) {
				int o0 = r.op(r.state(x, h0 - 1, z));
				if (o0 < 15) {
					int v0 = 15 - std::max(o0, 1);
					int i0 = ((h0 - 1 - MIN_Y) * W + z) * W + x;
					if (v0 > sky[i0]) { sky[i0] = (uint8_t)v0; q.push_back(i0); }
				}
			}
			int mn = h0;
			if (x > 0) mn = std::min(mn, hm[z * W + x - 1]);
			if (x < W - 1) mn = std::min(mn, hm[z * W + x + 1]);
			if (z > 0) mn = std::min(mn, hm[(z - 1) * W + x]);
			if (z < W - 1) mn = std::min(mn, hm[(z + 1) * W + x]);
			for (int y = std::max(mn, MIN_Y); y < h0 - 1; y++) {
				int o = r.op(r.state(x, y, z));
				if (o >= 15) continue;
				int i = ((y - MIN_Y) * W + z) * W + x;
				int v = 15 - std::max(o, 1);
				if (v > sky[i]) { sky[i] = (uint8_t)v; q.push_back(i); }
			}
		}
	}
	OpacCache *oc = new OpacCache();
	bfs(q, sky.data(), hm.data(), r, *oc, true, touched);
	// block light seeds
	q.clear();
	for (int ci = 0; ci < 9; ci++) {
		if (!r.present[ci]) continue;
		int ox = (ci % 3) * 16, oz = (ci / 3) * 16;
		for (int s = 0; s < SECTIONS; s++) {
			const Sec &e = r.sec[ci][s];
			bool has = false;
			for (int64_t p = 0; p < e.npal; p++) if (r.em(e.pal[p]) > 0) { has = true; break; }
			if (!has) continue;
			for (int k = 0; k < 4096; k++) {
				int emv = r.em(r.sec_state(e, k));
				if (emv > 0) {
					int y2 = MIN_Y + s * 16 + (k >> 8);
					int i2 = ((y2 - MIN_Y) * W + oz + ((k >> 4) & 15)) * W + ox + (k & 15);
					if (emv > blk[i2]) { blk[i2] = (uint8_t)emv; q.push_back(i2); touched[s] = 1; }
				}
			}
		}
	}
	bfs(q, blk.data(), hm.data(), r, *oc, false, touched);
	delete oc;
	// output halo sections
	int minh = MAX_Y, maxh = MIN_Y;
	for (int z = 15; z < 33; z++)
		for (int x = 15; x < 33; x++) {
			int hh = hm[z * W + x];
			minh = std::min(minh, hh);
			maxh = std::max(maxh, hh);
		}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, SECTIONS);
	for (int s = 0; s < SECTIONS; s++) {
		int y0 = MIN_Y + s * 16;
		if (touched[s] == 0 && (s == 0 || touched[s - 1] == 0) && (s == SECTIONS - 1 || touched[s + 1] == 0)) {
			if (y0 >= maxh) { array_set_int(ret, s, 0xF0); continue; }
			if (y0 + 16 <= minh - 16) { array_set_int(ret, s, 0); continue; }
		}
		Owned arr(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
		resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, arr.ptr(), HSEC);
		uint8_t *o = bytes_w(arr.ptr());
		int n = 0;
		for (int ly = 0; ly < 16; ly++) {
			int y = y0 + ly;
			int base = (y - MIN_Y) * LAYER;
			for (int z = 15; z < 33; z++) {
				int row = base + z * W;
				int hrow = z * W;
				for (int x = 15; x < 33; x++) {
					int sv = y >= hm[hrow + x] ? 15 : sky[row + x];
					o[n++] = (uint8_t)((sv << 4) | blk[row + x]);
				}
			}
		}
		array_set_native(ret, s, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, arr.ptr());
	}
	delete rp;
	return true;
}

} // namespace

void register_light(const char *cls) {
	register_method(cls, "light", fn_light, 4);
}
