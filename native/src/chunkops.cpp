// Native chunk column operations (exact ports of scripts/world/chunk.gd / worldgen_263.gd / features.gd loops):
//   chunk_finish(col, flags, opacity, f_liquid)
//     -> [sections: Array[24] of [pal, idx, wide], heightmap, gen_surface, gen_top, gen_floor]
//        (VanillaGenerator.generate tail: WORLD_SURFACE_WG scan, pristine surface/floor, Chunk.fill_from_column,
//         Chunk.recompute_heightmap)
//   chunk_decorate(secs, writes: Array[PackedInt32Array] (sorted origins), x0, z0, flags, opacity, consts, biomes, temps, st_block, leaf_info, ore_mask)
//     -> [sections, heightmap]   (Features.apply write modes + Features._freeze)
//     consts: [F_REPLACEABLE, F_LEAVES, F_FULL_SHAPE, WATER, ICE, SNOW, ice block id, packed_ice block id, sea level]
//   st_block passed for the ice name test.
#include "native.h"
#include <vector>
#include <unordered_map>
#include <cstring>
#include <cmath>
#include "rng.h"

using namespace gdx;

namespace {

const int MIN_Y = -64, HEIGHT = 384;

// Chunk.Section.fill_raw: palette in first-occurrence order; byte indices, wide indices from the 257th state on.
static void pack_section(const int32_t *raw, void *out_arr, int64_t slot) {
	Owned pal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	Owned idx(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	Owned wide(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	int32_t first = raw[0];
	bool uniform = true;
	for (int k = 0; k < 4096; k++) if (raw[k] != first) { uniform = false; break; }
	if (uniform) {
		resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pal.ptr(), 1);
		i32_w(pal.ptr())[0] = first;
	} else {
		std::vector<int32_t> pv;
		pv.reserve(16);
		std::vector<int32_t> ix(4096);
		int32_t last_v = -1, last_p = 0;
		for (int k = 0; k < 4096; k++) {
			int32_t v = raw[k];
			int32_t p;
			if (v == last_v) p = last_p;
			else {
				p = -1;
				for (size_t q = 0; q < pv.size(); q++) if (pv[q] == v) { p = (int32_t)q; break; }
				if (p < 0) { p = (int32_t)pv.size(); pv.push_back(v); }
				last_v = v;
				last_p = p;
			}
			ix[k] = p;
		}
		resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pal.ptr(), (int64_t)pv.size());
		memcpy(i32_w(pal.ptr()), pv.data(), pv.size() * sizeof(int32_t));
		if (pv.size() > 256) {
			resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wide.ptr(), 4096);
			memcpy(i32_w(wide.ptr()), ix.data(), 4096 * sizeof(int32_t));
		} else {
			resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, idx.ptr(), 4096);
			uint8_t *o = bytes_w(idx.ptr());
			for (int k = 0; k < 4096; k++) o[k] = (uint8_t)ix[k];
		}
	}
	Owned e(GDEXTENSION_VARIANT_TYPE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, e.ptr(), 3);
	array_set_native(e.ptr(), 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pal.ptr());
	array_set_native(e.ptr(), 1, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, idx.ptr());
	array_set_native(e.ptr(), 2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wide.ptr());
	array_set_native(out_arr, slot, GDEXTENSION_VARIANT_TYPE_ARRAY, e.ptr());
}

static void pack_all(const int32_t *col, void *ret, int64_t slot) {
	Owned secs(GDEXTENSION_VARIANT_TYPE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, secs.ptr(), 24);
	for (int s = 0; s < 24; s++) pack_section(col + s * 4096, secs.ptr(), s);
	array_set_native(ret, slot, GDEXTENSION_VARIANT_TYPE_ARRAY, secs.ptr());
}

// Chunk.recompute_heightmap: first state with opacity > 0 from the top, +1 (MIN_Y when none)
static void heightmap(const int32_t *col, const uint8_t *opac, int64_t nop, int32_t *hm) {
	for (int c = 0; c < 256; c++) {
		int top = MIN_Y;
		for (int ly = HEIGHT - 1; ly >= 0; ly--) {
			int st = col[(ly << 8) | c];
			if (st >= 0 && st < nop && opac[st] > 0) { top = MIN_Y + ly + 1; break; }
		}
		hm[c] = top;
	}
}

static void put_i32(void *ret, int64_t slot, const int32_t *d, int64_t n) {
	Owned a(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, a.ptr(), n);
	memcpy(i32_w(a.ptr()), d, n * sizeof(int32_t));
	array_set_native(ret, slot, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, a.ptr());
}

bool fn_chunk_finish(const Args &a, void *ret) {
	const void *colv = a.obj(0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *flv = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *opv = a.obj(2, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!colv || !flv || !opv || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, colv) != 98304) return false;
	int f_liquid = (int)a.i(3);
	const int32_t *col = i32(colv);
	const int32_t *fl = i32(flv);
	int64_t nfl = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, flv);
	const uint8_t *op = bytes(opv);
	int64_t nop = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, opv);
	int32_t hm[256], gsurf[256], gtop[256], gfloor[256], hmap[256];
	for (int c = 0; c < 256; c++) {
		int top2 = MIN_Y;
		for (int ly = HEIGHT - 1; ly >= 0; ly--) if (col[(ly << 8) | c] != 0) { top2 = MIN_Y + ly + 1; break; }
		hm[c] = top2;
	}
	for (int c = 0; c < 256; c++) {
		int fy = hm[c] - 1;
		while (fy >= MIN_Y) {
			int fs = col[((fy - MIN_Y) << 8) | c];
			if (fs != 0 && !((fs >= 0 && fs < nfl ? fl[fs] : 0) & f_liquid)) break;
			fy--;
		}
		gfloor[c] = fy + 1;
		int y2 = hm[c] - 1;
		gsurf[c] = y2;
		gtop[c] = y2 >= MIN_Y ? col[((y2 - MIN_Y) << 8) | c] : 0;
	}
	heightmap(col, op, nop, hmap);
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 5);
	pack_all(col, ret, 0);
	put_i32(ret, 1, hmap, 256);
	put_i32(ret, 2, gsurf, 256);
	put_i32(ret, 3, gtop, 256);
	put_i32(ret, 4, gfloor, 256);
	return true;
}

static void expand(const void *secs, int32_t *col) {
	memset(col, 0, sizeof(int32_t) * 98304);
	int64_t ns = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, secs);
	for (int64_t s = 0; s < ns && s < 24; s++) {
		const void *earr = internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)array_get(secs, s));
		const void *pal = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)array_get(earr, 0));
		const void *idx = internal(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)((GDExtensionVariantPtr)array_get(earr, 1));
		const void *wide = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)array_get(earr, 2));
		int64_t np = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pal);
		if (np == 0) continue;
		const int32_t *p = i32(pal);
		int32_t *dst = col + s * 4096;
		if (np == 1) { for (int k = 0; k < 4096; k++) dst[k] = p[0]; continue; }
		if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wide) >= 4096) {
			const int32_t *w = i32(wide);
			for (int k = 0; k < 4096; k++) dst[k] = p[w[k]];
		} else {
			const uint8_t *ix = bytes(idx);
			for (int k = 0; k < 4096; k++) dst[k] = p[ix[k]];
		}
	}
}

bool fn_chunk_decorate(const Args &a, void *ret) {
	const void *secs = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *wl = a.obj(1, GDEXTENSION_VARIANT_TYPE_ARRAY);
	int x0 = (int)a.i(2), z0 = (int)a.i(3);
	const void *flv = a.obj(4, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *opv = a.obj(5, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	const void *cv = a.obj(6, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *biov = a.obj(7, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	const void *tv = a.obj(8, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY);
	const void *sbv = a.obj(9, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	if (!secs || !wl || !flv || !opv || !cv || !biov || !tv || !sbv) return false;
	if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, cv) < 9 || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, biov) < 1536) return false;
	const int32_t *fl = i32(flv);
	int64_t nfl = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, flv);
	const uint8_t *op = bytes(opv);
	int64_t nop = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, opv);
	const int32_t *k = i32(cv);
	int F_REPL = k[0], F_LEAVES = k[1], F_FULL = k[2], WATER = k[3], ICE = k[4], SNOW = k[5], ICE_B = k[6], PICE_B = k[7], SEA = k[8];
	const uint8_t *bio = bytes(biov);
	const double *temps = f64(tv);
	int64_t ntemps = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, tv);
	const int32_t *stb = i32(sbv);
	int64_t nstb = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, sbv);
	static thread_local std::vector<int32_t> tl_col;
	TLBuf<int32_t> col_buf(tl_col, 98304, 0);
	std::vector<int32_t> &col = col_buf.v;
	expand(secs, col.data());
	auto FL = [&](int st) { return (st >= 0 && st < nfl) ? fl[st] : 0; };
	// Features.apply: write lists of the 3x3 origins in (cz, cx) order; modes 0 force, 1 replaceable, 2 air
	// (3 = ore: W_ORE | rule << 2, tested against arg 11, the per-state ore rule bits of Features.ore_mask)
	const void *omv = a.count > 11 ? a.obj(11, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY) : nullptr;
	int64_t nom = omv ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, omv) : 0;
	const int32_t *om = nom > 0 ? i32(omv) : nullptr;
	int64_t nw = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, wl);
	// cross-origin carving next to another origin's liquid is skipped (consts[9] = F_LIQUID, [10] = cave air): every
	// origin's features ran on pristine terrain, so a lake carving air beside a neighbour's pool (Java: the lake sees the
	// water and aborts, or the pool sees the air and is not placed) would leave the pool open on one side
	int F_LIQ = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, cv) >= 11 ? k[9] : 0;
	int CAVE_AIR = F_LIQ ? k[10] : -1;
	// consts[11] = n, then n (snowy=false, snowy=true) state pairs: SnowAndFreezeFeature sets SNOWY on the block under new snow
	int64_t nkc = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, cv);
	int NSNOWY = nkc >= 12 ? k[11] : 0;
	if (12 + 2 * (int64_t)NSNOWY > nkc) NSNOWY = 0;
	const int32_t *snowy_pairs = k + 12;
	// liquid writes over the chunk + 1-block border: 18 x 18 x HEIGHT cells, value = origin list index + 1 (255 = several;
	// 0 = none). A thread-local flat array (a hash map here tripled the decorate time)
	static thread_local std::vector<uint8_t> tl_liq;
	static const int LW = 18, LA = 18 * 18;
	bool any_liq = false;
	auto lidx = [&](int x, int y, int z) -> int {
		int lx = x - (x0 - 1), lz = z - (z0 - 1), ly = y - MIN_Y;
		if (lx < 0 || lx >= LW || lz < 0 || lz >= LW || ly < 0 || ly >= HEIGHT) return -1;
		return ly * LA + lz * LW + lx;
	};
	if (F_LIQ) {
		for (int64_t li = 0; li < nw; li++) {
			const void *wa = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)array_get(wl, li));
			int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wa);
			const int32_t *w = n ? i32(wa) : nullptr;
			for (int64_t q = 0; q + 4 < n; q += 5) {
				int x = w[q], z = w[q + 2];
				if (x < x0 - 1 || x > x0 + 16 || z < z0 - 1 || z > z0 + 16) continue;
				if (!(FL(w[q + 3]) & F_LIQ)) continue;
				int ci = lidx(x, w[q + 1], z);
				if (ci < 0) continue;
				if (!any_liq) {
					any_liq = true;
					if (tl_liq.size() != (size_t)LA * HEIGHT) tl_liq.assign((size_t)LA * HEIGHT, 0);
					else std::memset(tl_liq.data(), 0, tl_liq.size());
				}
				uint8_t v = tl_liq[ci];
				uint8_t me = (uint8_t)(li + 1);
				if (v == 0) tl_liq[ci] = me;
				else if (v != me) tl_liq[ci] = 255;
			}
		}
	}
	auto other_liquid = [&](int x, int y, int z, int li) {
		static const int D[7][3] = {{0, 0, 0}, {1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
		uint8_t me = (uint8_t)(li + 1);
		for (int d = 0; d < 7; d++) {
			int ci = lidx(x + D[d][0], y + D[d][1], z + D[d][2]);
			if (ci < 0) continue;
			uint8_t v = tl_liq[ci];
			if (v != 0 && v != me) return true;
		}
		return false;
	};
	for (int64_t li = 0; li < nw; li++) {
		const void *wa = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)array_get(wl, li));
		int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wa);
		if (n == 0) continue;
		const int32_t *w = i32(wa);
		for (int64_t q = 0; q + 4 < n; q += 5) {
			int x = w[q], y = w[q + 1], z = w[q + 2], st = w[q + 3], mode = w[q + 4];
			if (x < x0 || x >= x0 + 16 || z < z0 || z >= z0 + 16) continue;
			if (y < MIN_Y || y >= MIN_Y + HEIGHT) continue;
			if (any_liq && (st == 0 || st == CAVE_AIR) && other_liquid(x, y, z, (int)li)) continue;
			int i = ((y - MIN_Y) << 8) | ((z & 15) << 4) | (x & 15);
			if (mode != 0) {
				int cur = col[i];
				if ((mode & 3) == 3) {
					// ore write (Features.W_ORE | rule << 2): only while the cell still passes the ore's target rule test
					if (nom > 0 && (cur <= 0 || cur >= nom || !((om[cur] >> (mode >> 2)) & 1))) continue;
					col[i] = st;
					continue;
				}
				if (mode == 2 && cur != 0 && !(FL(cur) & F_REPL)) continue;
				if (mode == 1 && cur != 0 && !(FL(cur) & (F_REPL | F_LEAVES))) continue;
			}
			col[i] = st;
		}
	}
	// Java TreeFeature.updateLeaves: leaf distances by a breadth-first walk from logs through leaves (6 steps at most;
	// unreached leaves keep their state). Arg 10 (optional): per state 0 other, -1 log (#logs), leaves (stride << 4 |
	// current distance 1..7). The walk covers the chunk plus a 6-block margin; outside the chunk the logs / leaves come
	// from the 3x3 origins' write lists (trees reaching in from neighbours).
	const void *lfv = a.count > 10 ? a.obj(10, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY) : nullptr;
	int64_t nlf = lfv ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, lfv) : 0;
	if (nlf > 0) {
		const int32_t *lf = i32(lfv);
		auto LF = [&](int st) -> int32_t { return (st > 0 && st < nlf) ? lf[st] : 0; };
		static const int M = 6, GW = 16 + 2 * M, GA = GW * GW;
		static thread_local std::vector<uint8_t> tl_cls, tl_dist;
		static thread_local std::vector<int32_t> tl_q;
		bool any_leaf = false;
		for (int i = 0; i < 98304 && !any_leaf; i++) if (LF(col[i]) > 0) any_leaf = true;
		if (any_leaf) {
			if (tl_cls.size() != (size_t)GA * HEIGHT) { tl_cls.assign((size_t)GA * HEIGHT, 0); tl_dist.assign((size_t)GA * HEIGHT, 7); }
			else { std::memset(tl_cls.data(), 0, tl_cls.size()); std::memset(tl_dist.data(), 7, tl_dist.size()); }
			uint8_t *cls = tl_cls.data();
			uint8_t *dist = tl_dist.data();
			auto gi = [&](int x, int y, int z) -> int {
				int gx = x - (x0 - M), gz = z - (z0 - M), gy = y - MIN_Y;
				if (gx < 0 || gx >= GW || gz < 0 || gz >= GW || gy < 0 || gy >= HEIGHT) return -1;
				return gy * GA + gz * GW + gx;
			};
			// margin from the write lists (in application order), then the finished chunk itself
			for (int64_t li = 0; li < nw; li++) {
				const void *wa = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)array_get(wl, li));
				int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wa);
				const int32_t *w = n ? i32(wa) : nullptr;
				for (int64_t q = 0; q + 4 < n; q += 5) {
					int x = w[q], z = w[q + 2];
					if (x >= x0 && x < x0 + 16 && z >= z0 && z < z0 + 16) continue;
					int ci = gi(x, w[q + 1], z);
					if (ci < 0) continue;
					int32_t c = LF(w[q + 3]);
					cls[ci] = c < 0 ? 1 : (c > 0 ? 2 : 0);
				}
			}
			for (int y = 0; y < HEIGHT; y++)
				for (int lz = 0; lz < 16; lz++)
					for (int lx = 0; lx < 16; lx++) {
						int32_t c = LF(col[(y << 8) | (lz << 4) | lx]);
						cls[y * GA + (lz + M) * GW + lx + M] = c < 0 ? 1 : (c > 0 ? 2 : 0);
					}
			tl_q.clear();
			for (int i = 0; i < GA * HEIGHT; i++)
				if (cls[i] == 1) { dist[i] = 0; tl_q.push_back(i); }
			for (size_t h = 0; h < tl_q.size(); h++) {
				int c = tl_q[h];
				int d = dist[c] + 1;
				if (d >= 7) continue;
				int gy = c / GA, rem = c % GA, gz = rem / GW, gx = rem % GW;
				const int nb[6] = {gx > 0 ? c - 1 : -1, gx < GW - 1 ? c + 1 : -1, gz > 0 ? c - GW : -1, gz < GW - 1 ? c + GW : -1,
					gy > 0 ? c - GA : -1, gy < HEIGHT - 1 ? c + GA : -1};
				for (int k2 = 0; k2 < 6; k2++) {
					int n2 = nb[k2];
					if (n2 < 0 || cls[n2] != 2 || dist[n2] <= d) continue;
					dist[n2] = (uint8_t)d;
					tl_q.push_back(n2);
				}
			}
			for (int y = 0; y < HEIGHT; y++)
				for (int lz = 0; lz < 16; lz++)
					for (int lx = 0; lx < 16; lx++) {
						int i = (y << 8) | (lz << 4) | lx;
						int32_t c = LF(col[i]);
						if (c <= 0) continue;
						int d = dist[y * GA + (lz + M) * GW + lx + M];
						if (d >= 7) continue;
						int cur = c & 15, stride = c >> 4;
						col[i] += (d - cur) * stride;
					}
		}
	}
	// Features._freeze on the chunk-local heightmap
	int32_t hm[256];
	heightmap(col.data(), op, nop, hm);
	for (int lz = 0; lz < 16; lz++)
		for (int lx = 0; lx < 16; lx++) {
			int y = hm[lx + lz * 16];
			int top = (y - 1 >= MIN_Y && y - 1 < MIN_Y + HEIGHT) ? col[((y - 1 - MIN_Y) << 8) | (lz << 4) | lx] : 0;
			int yc = y < MIN_Y ? MIN_Y : (y > MIN_Y + HEIGHT - 1 ? MIN_Y + HEIGHT - 1 : y);
			int qy = (yc - MIN_Y) >> 2;
			qy = qy < 0 ? 0 : (qy > 95 ? 95 : qy);
			int b = bio[(lx >> 2) + (lz >> 2) * 4 + qy * 16];
			double t = b < ntemps ? temps[b] : 1.0;
			int lim = SEA + 17;
			if (y > lim) t -= (double)(y - lim) * 0.05 / 40.0;
			if (t >= 0.15) continue;
			if (top == WATER) {
				if (y - 1 >= MIN_Y && y - 1 < MIN_Y + HEIGHT) col[((y - 1 - MIN_Y) << 8) | (lz << 4) | lx] = ICE;
			} else if (top > 0) {
				int above = (y >= MIN_Y && y < MIN_Y + HEIGHT) ? col[((y - MIN_Y) << 8) | (lz << 4) | lx] : 0;
				if (above == 0 && (FL(top) & (F_FULL | F_LEAVES))) {
					int tb = top < nstb ? stb[top] : -1;
					if (tb != ICE_B && tb != PICE_B && y >= MIN_Y && y < MIN_Y + HEIGHT) {
						col[((y - MIN_Y) << 8) | (lz << 4) | lx] = SNOW;
						for (int q = 0; q < NSNOWY; q++)
							if (snowy_pairs[q * 2] == top) { col[((y - 1 - MIN_Y) << 8) | (lz << 4) | lx] = snowy_pairs[q * 2 + 1]; break; }
					}
				}
			}
		}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 2);
	pack_all(col.data(), ret, 0);
	int32_t hm2[256];
	heightmap(col.data(), op, nop, hm2);
	put_i32(ret, 1, hm2, 256);
	return true;
}

// Structures._candidates (random_spread): start chunks of a structure set that may reach chunk (cx, cz).
// rs_candidates(seed, spacing, separation, salt, triangular, frequency, legacy_type_3, cx, cz, search) -> [PackedInt32Array]
bool fn_rs_candidates(const Args &a, void *ret) {
	int64_t seed = a.i(0);
	int64_t spacing = a.i(1), sep = a.i(2), salt = a.i(3);
	bool tri = a.i(4) != 0;
	double freq = a.f(5);
	bool legacy3 = a.i(6) != 0;
	int64_t cx = a.i(7), cz = a.i(8), search = a.i(9);
	if (spacing < 1) spacing = 1;
	auto fdiv = [](int64_t v, int64_t d) { return (int64_t)std::floor((double)v / (double)d); };
	std::vector<int32_t> out;
	for (int64_t rz = fdiv(cz - search, spacing); rz < fdiv(cz + search, spacing) + 1; rz++) {
		for (int64_t rx = fdiv(cx - search, spacing); rx < fdiv(cx + search, spacing) + 1; rx++) {
			rn::LegacyRandom r(rn::wadd(rn::wadd(rn::wadd(rn::wmul(rx, 341873128712LL), rn::wmul(rz, 132897987541LL)), seed), salt));
			int64_t k = spacing - sep;
			if (k < 1) k = 1;
			int64_t ox, oz;
			if (tri) { int64_t a1 = r.next_int_bound(k); int64_t a2 = r.next_int_bound(k); ox = (a1 + a2) / 2; }
			else ox = r.next_int_bound(k);
			if (tri) { int64_t b1 = r.next_int_bound(k); int64_t b2 = r.next_int_bound(k); oz = (b1 + b2) / 2; }
			else oz = r.next_int_bound(k);
			int64_t sx = rx * spacing + ox, sz = rz * spacing + oz;
			if (std::llabs(sx - cx) > search || std::llabs(sz - cz) > search) continue;
			if (freq < 1.0) {
				if (legacy3) {
					rn::LegacyRandom fr(seed);
					int64_t la = fr.next_long();
					int64_t lb = fr.next_long();
					fr.set_seed(rn::wmul(sx, la) ^ rn::wmul(sz, lb) ^ seed);
					if (fr.next_double() >= freq) continue;
				} else {
					rn::LegacyRandom fr(rn::wadd(rn::wadd(rn::wadd(rn::wmul(salt, 341873128712LL), rn::wmul(sx, 132897987541LL)), seed), sz));
					if (fr.next_float() >= freq) continue;
				}
			}
			out.push_back((int32_t)sx);
			out.push_back((int32_t)sz);
		}
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	Owned o(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, o.ptr(), (int64_t)out.size());
	if (!out.empty()) memcpy(i32_w(o.ptr()), out.data(), out.size() * sizeof(int32_t));
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, o.ptr());
	return true;
}

// Structures._fits hole test: true when box (x0..x1) overlaps any hole (6 ints per hole) -> [0/1]
bool fn_boxes_hit(const Args &a, void *ret) {
	const void *hp = a.obj(0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	if (!hp) return false;
	int64_t x0 = a.i(1), y0 = a.i(2), z0 = a.i(3), x1 = a.i(4), y1 = a.i(5), z1 = a.i(6);
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, hp);
	const int32_t *h = n ? i32(hp) : nullptr;
	int hit = 0;
	for (int64_t i = 0; i + 5 < n; i += 6) {
		if (x0 <= h[i + 3] && x1 >= h[i] && y0 <= h[i + 4] && y1 >= h[i + 1] && z0 <= h[i + 5] && z1 >= h[i + 2]) { hit = 1; break; }
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, hit);
	return true;
}

// Structures._el_jig_idx: Util.shuffle of jigsaw indices with java.util.Random state `seed` (already scrambled,
// i.e. LegacyRandom.seed), then a stable bucket by selection priority (order = distinct priorities, descending).
// jig_shuffle(seed, sels, order) -> [new_seed, PackedInt32Array idx]
bool fn_jig_shuffle(const Args &a, void *ret) {
	int64_t seed = a.i(0);
	const void *sv = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *ov = a.obj(2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	if (!sv || !ov) return false;
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, sv);
	int64_t no = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, ov);
	const int32_t *sels = n ? i32(sv) : nullptr;
	const int32_t *order = no ? i32(ov) : nullptr;
	rn::LegacyRandom r;
	r.seed = seed;
	std::vector<int32_t> idx(n);
	for (int64_t k = 0; k < n; k++) idx[k] = (int32_t)k;
	for (int64_t i = n; i > 1; i--) {
		int64_t j = r.next_int_bound(i);
		std::swap(idx[i - 1], idx[j]);
	}
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, out.ptr(), n);
	int32_t *o = n ? i32_w(out.ptr()) : nullptr;
	if (no <= 1) {
		for (int64_t k = 0; k < n; k++) o[k] = idx[k];
	} else {
		int64_t w = 0;
		for (int64_t q = 0; q < no; q++)
			for (int64_t k = 0; k < n; k++)
				if (sels[idx[k]] == order[q]) o[w++] = idx[k];
		resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, out.ptr(), w);
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 2);
	array_set_int(ret, 0, r.seed);
	array_set_native(ret, 1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, out.ptr());
	return true;
}

// SkyState._biome_blend (Java CubicSampler.gaussianSampleVec3 over the 6x6x6 biome quarts around the camera) of the
// biome sky and fog colours. sky_blend(biomes9: Array[9] (chunks ccx-1..ccx+1 x ccz-1..ccz+1), ccx, ccz, x, y, z,
// sky, fog, default_sky, default_fog) -> [PackedColorArray(2): sky, fog]
bool fn_sky_blend(const Args &a, void *ret) {
	const void *bv = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	int64_t ccx = a.i(1), ccz = a.i(2);
	double px = a.f(3), py = a.f(4), pz = a.f(5);
	const void *sv = a.obj(6, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	const void *fv = a.obj(7, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	const void *dv = a.obj(8, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	if (!bv || !sv || !fv || !dv || size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, bv) != 9 || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, dv) < 2) return false;
	const uint8_t *bio[9];
	for (int k = 0; k < 9; k++) {
		const void *e = array_get(bv, k);
		bio[k] = nullptr;
		if (variant_get_type((GDExtensionConstVariantPtr)e) == GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY) {
			const void *pa = internal(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)((GDExtensionVariantPtr)e);
			if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, pa) >= 1536) bio[k] = bytes(pa);
		}
	}
	const float *S = color(sv), *F = color(fv), *D = color(dv);
	int64_t ns = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, sv), nf = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, fv);
	static const double G[7] = {0.0, 1.0, 4.0, 6.0, 4.0, 1.0, 0.0};
	double qx = (px - 2.0) * 0.25, qy = (py - 2.0) * 0.25, qz = (pz - 2.0) * 0.25;
	int64_t bxq = (int64_t)std::floor(qx), byq = (int64_t)std::floor(qy), bzq = (int64_t)std::floor(qz);
	double dx = qx - bxq, dy = qy - byq, dz = qz - bzq;
	double wx[6], wy[6], wz[6];
	for (int i = 0; i < 6; i++) {
		wx[i] = G[i + 1] + (G[i] - G[i + 1]) * dx;
		wy[i] = G[i + 1] + (G[i] - G[i + 1]) * dy;
		wz[i] = G[i + 1] + (G[i] - G[i + 1]) * dz;
	}
	double sum = 0, sk[3] = {0, 0, 0}, fg[3] = {0, 0, 0};
	double first_s[3] = {D[0], D[1], D[2]}, first_f[3] = {D[4], D[5], D[6]};
	bool first = true;
	for (int l = 0; l < 6; l++)
		for (int n = 0; n < 6; n++)
			for (int s = 0; s < 6; s++) {
				int64_t bx = (bxq - 2 + l) * 4, by = (byq - 2 + n) * 4, bz = (bzq - 2 + s) * 4;
				int64_t ox = (bx >> 4) - ccx, oz = (bz >> 4) - ccz;
				const float *cs = D, *cf = D + 4;
				if (ox >= -1 && ox <= 1 && oz >= -1 && oz <= 1 && bio[(oz + 1) * 3 + (ox + 1)]) {
					int64_t yy = by < -64 ? -64 : (by > 319 ? 319 : by);
					int qy2 = (int)((yy + 64) >> 2);
					int b = bio[(oz + 1) * 3 + (ox + 1)][((bx & 15) >> 2) + ((bz & 15) >> 2) * 4 + qy2 * 16];
					if (b < ns) cs = S + b * 4;
					if (b < nf) cf = F + b * 4;
				}
				if (first) { for (int c = 0; c < 3; c++) { first_s[c] = cs[c]; first_f[c] = cf[c]; } first = false; }
				double w = wx[l] * wy[n] * wz[s];
				sum += w;
				for (int c = 0; c < 3; c++) { sk[c] += cs[c] * w; fg[c] += cf[c] * w; }
			}
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, out.ptr(), 2);
	float *o = color_w(out.ptr());
	for (int c = 0; c < 3; c++) {
		o[c] = (float)(sum > 0 ? sk[c] / sum : first_s[c]);
		o[4 + c] = (float)(sum > 0 ? fg[c] / sum : first_f[c]);
	}
	o[3] = 1.0f;
	o[7] = 1.0f;
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, out.ptr());
	return true;
}
// ChunkManager._tints_compute: biome-blended grass / foliage / water colours per column (float32, same order).
// tints(biomes9: Array[9] of PackedByteArray or null, heightmap, cx, cz, radius, grass, foliage, water, dry_foliage)
//   -> [PackedColorArray(1024)]: grass, foliage, water, dry foliage (leaf litter) per column
bool fn_tints(const Args &a, void *ret) {
	const void *bv = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *hv = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	int64_t cx = a.i(2), cz = a.i(3);
	int r = (int)a.i(4);
	const void *gv = a.obj(5, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	const void *fv = a.obj(6, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	const void *wv = a.obj(7, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	const void *dv = a.obj(8, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	if (!bv || !hv || !gv || !fv || !wv || !dv || size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, bv) != 9 || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, hv) < 256) return false;
	const uint8_t *bio[9];
	for (int k = 0; k < 9; k++) {
		const void *e = array_get(bv, k);
		bio[k] = nullptr;
		if (variant_get_type((GDExtensionConstVariantPtr)e) == GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY) {
			const void *pa = internal(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)((GDExtensionVariantPtr)e);
			if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, pa) >= 1536) bio[k] = bytes(pa);
		}
	}
	const int32_t *hm = i32(hv);
	const float *G = color(gv), *Fo = color(fv), *W = color(wv), *D = color(dv);
	int64_t nd = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, dv);
	int64_t ng = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, gv);
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, out.ptr(), 1024);
	float *o = color_w(out.ptr());
	for (int z = 0; z < 16; z++)
		for (int x = 0; x < 16; x++) {
			int hy = hm[x + z * 16];
			float g[4] = {0, 0, 0, 1}, f[4] = {0, 0, 0, 1}, w[4] = {0, 0, 0, 1}, dr[4] = {0, 0, 0, 1};
			int n = 0;
			for (int dz = -r; dz <= r; dz++)
				for (int dx = -r; dx <= r; dx++) {
					int64_t wx = cx * 16 + x + dx * 2, wz = cz * 16 + z + dz * 2;
					int64_t ox = (wx >> 4) - cx, oz = (wz >> 4) - cz;
					if (ox < -1 || ox > 1 || oz < -1 || oz > 1) continue;
					const uint8_t *bb = bio[(oz + 1) * 3 + (ox + 1)];
					if (!bb) continue;
					int qy = (hy - (-64)) >> 2;
					qy = qy < 0 ? 0 : (qy > 95 ? 95 : qy);
					int b = bb[((wx & 15) >> 2) + ((wz & 15) >> 2) * 4 + qy * 16];
					if (b >= ng) continue;
					for (int q = 0; q < 4; q++) { g[q] += G[b * 4 + q]; f[q] += Fo[b * 4 + q]; w[q] += W[b * 4 + q]; dr[q] += b < nd ? D[b * 4 + q] : 0.0f; }
					n++;
				}
			if (n == 0) {
				n = 1;
				g[0] = 0.5f; g[1] = 0.75f; g[2] = 0.35f; g[3] = 1.0f;
				for (int q = 0; q < 4; q++) f[q] = g[q];
				w[0] = 0.25f; w[1] = 0.46f; w[2] = 0.89f; w[3] = 1.0f;
				dr[0] = 0x5C / 255.0f; dr[1] = 0x3C / 255.0f; dr[2] = 0x32 / 255.0f; dr[3] = 1.0f;
			}
			float fn = (float)n;
			int i = x + z * 16;
			for (int q = 0; q < 3; q++) { o[i * 4 + q] = g[q] / fn; o[(256 + i) * 4 + q] = f[q] / fn; o[(512 + i) * 4 + q] = w[q] / fn; o[(768 + i) * 4 + q] = dr[q] / fn; }
			o[i * 4 + 3] = 1.0f; o[(256 + i) * 4 + 3] = 1.0f; o[(512 + i) * 4 + 3] = 1.0f; o[(768 + i) * 4 + 3] = 1.0f;
		}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, out.ptr());
	return true;
}

// BlockUpdates random ticks: rt_sample(list, tab, speed, seed) -> [new_seed, PackedInt32Array hits]
// list: Array of per-chunk Arrays [PackedInt32Array secs, pal0, idx0, wide0, pal1, idx1, wide1, ...] (random-tickable
// sections only, references to the live Section arrays). For every listed section `speed` cells are drawn from the
// xorshift32 stream (same generator and order as the former GDScript loop); hits (tab[state] == 1) are returned as
// 4 ints each: list index, section, cell index (y<<8 | z<<4 | x), state.
static bool rt_sample_impl(const Args &a, void *ret, int64_t c0, int64_t c1);

bool fn_rt_sample(const Args &a, void *ret) { return rt_sample_impl(a, ret, 0, -1); }

// rt_sample_range(list, tab, speed, seed, start, end): the same sampling for list entries [start, end) only, hit chunk
// indices absolute — one tick's pass split over several calls with the seed carried over gives identical hits.
bool fn_rt_sample_range(const Args &a, void *ret) { return rt_sample_impl(a, ret, a.i(4), a.i(5)); }

static bool rt_sample_impl(const Args &a, void *ret, int64_t c0, int64_t c1) {
	const void *lv = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *tv = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!lv || !tv) return false;
	int speed = (int)a.i(2);
	uint32_t xs = (uint32_t)a.i(3);
	int64_t ntab = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, tv);
	const uint8_t *tab = ntab ? bytes(tv) : nullptr;
	int64_t nc = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, lv);
	std::vector<int32_t> hits;
	auto get_packed = [](const void *arr, int64_t k, GDExtensionVariantType t) -> const void * {
		const void *e = array_get(arr, k);
		if (!e || variant_get_type((GDExtensionConstVariantPtr)e) != t) return nullptr;
		return internal(t)((GDExtensionVariantPtr)e);
	};
	if (c1 < 0 || c1 > nc) c1 = nc;
	if (c0 < 0) c0 = 0;
	for (int64_t ci = c0; ci < c1; ci++) {
		const void *ev = array_get(lv, ci);
		if (!ev || variant_get_type((GDExtensionConstVariantPtr)ev) != GDEXTENSION_VARIANT_TYPE_ARRAY) continue;
		const void *ca = internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)ev);
		int64_t ne = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, ca);
		const void *sv = ne > 0 ? get_packed(ca, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY) : nullptr;
		if (!sv) continue;
		int64_t ns = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, sv);
		const int32_t *secs = ns ? i32(sv) : nullptr;
		for (int64_t si = 0; si < ns && 1 + si * 3 + 2 < ne; si++) {
			const void *pv = get_packed(ca, 1 + si * 3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
			const void *iv = get_packed(ca, 2 + si * 3, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
			const void *wv = get_packed(ca, 3 + si * 3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
			int64_t np = pv ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pv) : 0;
			int64_t ni = iv ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, iv) : 0;
			int64_t nw = wv ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wv) : 0;
			const int32_t *pal = np ? i32(pv) : nullptr;
			const uint8_t *idx = ni >= 4096 ? bytes(iv) : nullptr;
			const int32_t *wide = nw >= 4096 ? i32(wv) : nullptr;
			for (int i = 0; i < speed; i++) {
				xs ^= xs << 13;
				xs ^= xs >> 17;
				xs ^= xs << 5;
				int k = (int)(xs & 4095u);
				if (np == 0) continue;
				int64_t pi;
				if (np == 1) pi = 0;
				else if (wide) pi = wide[k];
				else if (idx) pi = idx[k];
				else continue;
				if (pi < 0 || pi >= np) continue;
				int32_t st = pal[pi];
				if (st <= 0 || st >= ntab || tab[st] != 1) continue;
				hits.push_back((int32_t)ci);
				hits.push_back(secs[si]);
				hits.push_back(k);
				hits.push_back(st);
			}
		}
	}
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, out.ptr(), (int64_t)hits.size());
	if (!hits.empty()) memcpy(i32_w(out.ptr()), hits.data(), hits.size() * sizeof(int32_t));
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 2);
	array_set_int(ret, 0, (int64_t)xs);
	array_set_native(ret, 1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, out.ptr());
	return true;
}

// RandomTickable._log_nearby: breadth-first search through leaves (tab 2) from (x, y, z) for a log/wood/stem (tab 1)
// within r steps; unloaded chunks count as found. nine: Array[9] (dz*3+dx around the start chunk) of per-chunk Arrays
// [pal0, idx0, wide0, ... x24] or null. Same visit order and rules as the GDScript version. -> [found 0/1]
bool fn_leaf_search(const Args &a, void *ret) {
	const void *nv = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *tv = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!nv || !tv || size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, nv) != 9) return false;
	int64_t px = a.i(2), py = a.i(3), pz = a.i(4);
	int r = (int)a.i(5);
	if (r < 1 || r > 15) return false;
	int64_t ntab = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, tv);
	const uint8_t *tab = ntab ? bytes(tv) : nullptr;
	struct Sec { bool init = false; const int32_t *pal = nullptr; int64_t np = 0; const uint8_t *idx = nullptr; const int32_t *wide = nullptr; };
	Sec secs[9][24];
	const void *carr[9];
	for (int k = 0; k < 9; k++) {
		const void *e = array_get(nv, k);
		carr[k] = (e && variant_get_type((GDExtensionConstVariantPtr)e) == GDEXTENSION_VARIANT_TYPE_ARRAY) ? internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)e) : nullptr;
		if (carr[k] && size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, carr[k]) < 72) carr[k] = nullptr;
	}
	int64_t cx0 = (px >> 4) - 1, cz0 = (pz >> 4) - 1;
	auto get_packed = [](const void *arr, int64_t k, GDExtensionVariantType t) -> const void * {
		const void *e = array_get(arr, k);
		if (!e || variant_get_type((GDExtensionConstVariantPtr)e) != t) return nullptr;
		return internal(t)((GDExtensionVariantPtr)e);
	};
	auto state_at = [&](int64_t x, int64_t y, int64_t z) -> int64_t {
		int64_t ci = (x >> 4) - cx0, cj = (z >> 4) - cz0;
		if (ci < 0 || ci > 2 || cj < 0 || cj > 2) return -1;
		int k = (int)(cj * 3 + ci);
		if (!carr[k]) return -1;
		if (y < -64 || y >= 320) return 0;
		int s = (int)((y + 64) >> 4);
		Sec &sc = secs[k][s];
		if (!sc.init) {
			sc.init = true;
			const void *pv = get_packed(carr[k], s * 3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
			const void *iv = get_packed(carr[k], s * 3 + 1, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
			const void *wv = get_packed(carr[k], s * 3 + 2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
			sc.np = pv ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pv) : 0;
			sc.pal = sc.np ? i32(pv) : nullptr;
			sc.idx = (iv && size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, iv) >= 4096) ? bytes(iv) : nullptr;
			sc.wide = (wv && size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wv) >= 4096) ? i32(wv) : nullptr;
		}
		if (sc.np == 0) return 0;
		if (sc.np == 1) return sc.pal[0];
		int li = (int)(((y & 15) << 8) | ((z & 15) << 4) | (x & 15));
		int64_t pi = sc.wide ? sc.wide[li] : (sc.idx ? sc.idx[li] : 0);
		return (pi >= 0 && pi < sc.np) ? sc.pal[pi] : 0;
	};
	const int W = 2 * r + 1;
	std::vector<uint8_t> seen((size_t)W * W * W, 0);
	auto sidx = [&](int64_t x, int64_t y, int64_t z) -> int64_t {
		int64_t dx = x - px + r, dy = y - py + r, dz = z - pz + r;
		if (dx < 0 || dy < 0 || dz < 0 || dx >= W || dy >= W || dz >= W) return -1;
		return (dz * W + dy) * W + dx;
	};
	struct Q { int64_t x, y, z; int d; };
	std::vector<Q> q;
	q.push_back({px, py, pz, 0});
	seen[sidx(px, py, pz)] = 1;
	static const int O[6][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
	int found = 0;
	for (size_t qi = 0; qi < q.size() && !found; qi++) {
		Q c = q[qi];
		for (int o = 0; o < 6; o++) {
			int64_t nx = c.x + O[o][0], ny = c.y + O[o][1], nz = c.z + O[o][2];
			int64_t si = sidx(nx, ny, nz);
			if (si >= 0 && seen[si]) continue;
			int64_t st = state_at(nx, ny, nz);
			if (st < 0) { found = 1; break; }
			int t = (st < ntab) ? tab[st] : 0;
			if (t == 1) { found = 1; break; }
			if (c.d + 1 < r && t == 2 && si >= 0) {
				seen[si] = 1;
				q.push_back({nx, ny, nz, c.d + 1});
			}
		}
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, found);
	return true;
}

// anim_sample(grid, gx0, gz0, gw, est, bx, by, bz, seed) -> [PackedInt32Array hits (x, y, z, state)..., seed]
//   Java ClientLevel.animateTick sampling for Particles._animate_blocks: 667 x 2 positions per tick around (bx, by, bz),
//   alternately within +-16 and +-32 blocks per axis (xorshift32 stream, state carried in `seed`); grid: Array gw*gw
//   (row-major, z then x) of Chunk.sec_refs arrays or null for chunks (gx0.., gz0..). Returns the positions whose
//   state has est[state] == 1 (blocks with ambient particles), in sampling order.
bool fn_anim_sample(const Args &a, void *ret) {
	const void *gv = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	int64_t gx0 = a.i(1), gz0 = a.i(2), gw = a.i(3);
	const void *ev = a.obj(4, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	int64_t bx = a.i(5), by = a.i(6), bz = a.i(7);
	uint32_t xs = (uint32_t)a.i(8);
	if (!gv || !ev || gw <= 0 || gw > 64 || size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, gv) != gw * gw) return false;
	if (xs == 0) xs = 0x2545F491u;
	int64_t ntab = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, ev);
	const uint8_t *est = ntab ? bytes(ev) : nullptr;
	struct Sec { bool init = false; const int32_t *pal = nullptr; int64_t np = 0; const uint8_t *idx = nullptr; const int32_t *wide = nullptr; };
	std::vector<Sec> secs((size_t)(gw * gw * 24));
	std::vector<const void *> carr((size_t)(gw * gw), nullptr);
	std::vector<uint8_t> cinit((size_t)(gw * gw), 0);
	auto get_packed = [](const void *arr, int64_t k, GDExtensionVariantType t) -> const void * {
		const void *e = array_get(arr, k);
		if (!e || variant_get_type((GDExtensionConstVariantPtr)e) != t) return nullptr;
		return internal(t)((GDExtensionVariantPtr)e);
	};
	auto next = [&]() -> uint32_t { xs ^= xs << 13; xs ^= xs >> 17; xs ^= xs << 5; return xs; };
	std::vector<int32_t> out;
	for (int i = 0; i < 1334; i++) {   // Java: 667 x (doAnimateTick within 16, doAnimateTick within 32)
		int r = (i & 1) == 0 ? 16 : 32;
		uint32_t span = (uint32_t)(2 * r + 1);
		int64_t x = bx + (int64_t)(next() % span) - r;
		int64_t y = by + (int64_t)(next() % span) - r;
		int64_t z = bz + (int64_t)(next() % span) - r;
		if (y < -64 || y >= 320) continue;
		int64_t gi = (x >> 4) - gx0, gj = (z >> 4) - gz0;
		if (gi < 0 || gj < 0 || gi >= gw || gj >= gw) continue;
		int64_t k = gj * gw + gi;
		if (!cinit[k]) {
			cinit[k] = 1;
			const void *e = array_get(gv, k);
			const void *ca = (e && variant_get_type((GDExtensionConstVariantPtr)e) == GDEXTENSION_VARIANT_TYPE_ARRAY) ? internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)e) : nullptr;
			if (ca && size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, ca) < 72) ca = nullptr;
			carr[k] = ca;
		}
		if (!carr[k]) continue;
		int s = (int)((y + 64) >> 4);
		Sec &sc = secs[(size_t)k * 24 + s];
		if (!sc.init) {
			sc.init = true;
			const void *pv = get_packed(carr[k], s * 3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
			const void *iv = get_packed(carr[k], s * 3 + 1, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
			const void *wv = get_packed(carr[k], s * 3 + 2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
			sc.np = pv ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pv) : 0;
			sc.pal = sc.np ? i32(pv) : nullptr;
			sc.idx = (iv && size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, iv) >= 4096) ? bytes(iv) : nullptr;
			sc.wide = (wv && size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wv) >= 4096) ? i32(wv) : nullptr;
		}
		if (sc.np == 0) continue;
		int64_t st;
		if (sc.np == 1) st = sc.pal[0];
		else {
			int li = (int)(((y & 15) << 8) | ((z & 15) << 4) | (x & 15));
			int64_t pi = sc.wide ? sc.wide[li] : (sc.idx ? sc.idx[li] : 0);
			st = (pi >= 0 && pi < sc.np) ? sc.pal[pi] : 0;
		}
		if (st <= 0 || st >= ntab || est[st] != 1) continue;
		out.push_back((int32_t)x); out.push_back((int32_t)y); out.push_back((int32_t)z); out.push_back((int32_t)st);
	}
	Owned o(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, o.ptr(), (int64_t)out.size());
	if (!out.empty()) memcpy(i32_w(o.ptr()), out.data(), out.size() * sizeof(int32_t));
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 2);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, o.ptr());
	array_set_int(ret, 1, (int64_t)xs);
	return true;
}
// rt_leaf_filter(hits, coords, grid, gx0, gz0, gw, ltab, r) -> [PackedInt32Array hits]
//   hits: rt_sample output (chunk index, section, local index, state) x n; coords: PackedInt32Array (cx, cz) per chunk
//   index; grid: Array gw*gw (row-major, z then x) of Chunk.sec_refs arrays [pal, idx, wide] x 24 or null, for chunks
//   (gx0 .. gx0+gw-1, gz0 .. gz0+gw-1); ltab: per state 1 log/wood/stem, 2 leaves. For every leaf hit the leaf search of
//   RandomTickable._log_nearby / leaf_search runs (BFS through leaves for a log within r steps, same visit order and
//   rules; chunks outside the grid or null count as found). Leaves with support are dropped (their random tick would
//   do nothing); every other hit is kept in order.
bool fn_rt_leaf_filter(const Args &a, void *ret) {
	const void *hv = a.obj(0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *cv = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *gv = a.obj(2, GDEXTENSION_VARIANT_TYPE_ARRAY);
	int64_t gx0 = a.i(3), gz0 = a.i(4), gw = a.i(5);
	const void *tv = a.obj(6, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	int r = (int)a.i(7);
	if (!hv || !cv || !gv || !tv || gw <= 0 || gw > 200 || r < 1 || r > 15) return false;
	if (size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, gv) != gw * gw) return false;
	int64_t nh = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, hv);
	int64_t ncrd = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, cv);
	const int32_t *H = nh ? i32(hv) : nullptr;
	const int32_t *CRD = ncrd ? i32(cv) : nullptr;
	int64_t ntab = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, tv);
	const uint8_t *tab = ntab ? bytes(tv) : nullptr;
	// buffers reused across calls (main thread only) and invalidated by a generation stamp: allocating and zeroing
	// ~(2 sim + 3)^2 x 24 section records (~700 KB at sim 12) on every per-frame call cost more than the searches
	struct Sec { uint32_t gen = 0; const int32_t *pal = nullptr; int64_t np = 0; const uint8_t *idx = nullptr; const int32_t *wide = nullptr; };
	const int64_t ng = gw * gw;
	static thread_local std::vector<Sec> secs;
	static thread_local std::vector<const void *> carr;
	static thread_local std::vector<uint32_t> cgen;
	static thread_local uint32_t gen = 0;
	if (++gen == 0) { gen = 1; for (auto &x : secs) x.gen = 0; std::fill(cgen.begin(), cgen.end(), 0u); }
	if (secs.size() < (size_t)ng * 24) secs.resize((size_t)ng * 24);
	if (carr.size() < (size_t)ng) { carr.resize((size_t)ng, nullptr); cgen.resize((size_t)ng, 0u); }
	auto get_packed = [](const void *arr, int64_t k, GDExtensionVariantType t) -> const void * {
		const void *e = array_get(arr, k);
		if (!e || variant_get_type((GDExtensionConstVariantPtr)e) != t) return nullptr;
		return internal(t)((GDExtensionVariantPtr)e);
	};
	auto chunk_index = [&](int64_t cx, int64_t cz) -> int64_t {
		int64_t gi = cx - gx0, gj = cz - gz0;
		if (gi < 0 || gj < 0 || gi >= gw || gj >= gw) return -1;
		int64_t k = gj * gw + gi;
		if (cgen[k] != gen) {
			cgen[k] = gen;
			const void *e = array_get(gv, k);
			const void *ca = (e && variant_get_type((GDExtensionConstVariantPtr)e) == GDEXTENSION_VARIANT_TYPE_ARRAY) ? internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)e) : nullptr;
			if (ca && size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, ca) < 72) ca = nullptr;
			carr[k] = ca;
		}
		return carr[k] ? k : -1;
	};
	auto state_at = [&](int64_t x, int64_t y, int64_t z) -> int64_t {
		int64_t k = chunk_index(x >> 4, z >> 4);
		if (k < 0) return -1;
		if (y < -64 || y >= 320) return 0;
		int s = (int)((y + 64) >> 4);
		Sec &sc = secs[(size_t)k * 24 + s];
		if (sc.gen != gen) {
			sc.gen = gen;
			const void *pv = get_packed(carr[k], s * 3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
			const void *iv = get_packed(carr[k], s * 3 + 1, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
			const void *wv = get_packed(carr[k], s * 3 + 2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
			sc.np = pv ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pv) : 0;
			sc.pal = sc.np ? i32(pv) : nullptr;
			sc.idx = (iv && size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, iv) >= 4096) ? bytes(iv) : nullptr;
			sc.wide = (wv && size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wv) >= 4096) ? i32(wv) : nullptr;
		}
		if (sc.np == 0) return 0;
		if (sc.np == 1) return sc.pal[0];
		int li = (int)(((y & 15) << 8) | ((z & 15) << 4) | (x & 15));
		int64_t pi = sc.wide ? sc.wide[li] : (sc.idx ? sc.idx[li] : 0);
		return (pi >= 0 && pi < sc.np) ? sc.pal[pi] : 0;
	};
	const int W = 2 * r + 1;
	std::vector<uint8_t> seen((size_t)W * W * W, 0);
	struct Q { int64_t x, y, z; int d; };
	std::vector<Q> q;
	static const int O[6][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
	std::vector<int32_t> out;
	out.reserve((size_t)nh);
	for (int64_t h = 0; h + 3 < nh; h += 4) {
		int32_t ci = H[h], sec = H[h + 1], li = H[h + 2], st = H[h + 3];
		bool keep = true;
		if (st > 0 && st < ntab && tab[st] == 2 && ci >= 0 && (int64_t)ci * 2 + 1 < ncrd) {
			int64_t px = (int64_t)CRD[ci * 2] * 16 + (li & 15), py = -64 + (int64_t)sec * 16 + (li >> 8), pz = (int64_t)CRD[ci * 2 + 1] * 16 + ((li >> 4) & 15);
			std::fill(seen.begin(), seen.end(), (uint8_t)0);
			auto sidx = [&](int64_t x, int64_t y, int64_t z) -> int64_t {
				int64_t dx = x - px + r, dy = y - py + r, dz = z - pz + r;
				if (dx < 0 || dy < 0 || dz < 0 || dx >= W || dy >= W || dz >= W) return -1;
				return (dz * W + dy) * W + dx;
			};
			q.clear();
			q.push_back({px, py, pz, 0});
			seen[sidx(px, py, pz)] = 1;
			int found = 0;
			for (size_t qi = 0; qi < q.size() && !found; qi++) {
				Q c = q[qi];
				for (int o = 0; o < 6; o++) {
					int64_t nx = c.x + O[o][0], ny = c.y + O[o][1], nz = c.z + O[o][2];
					int64_t si = sidx(nx, ny, nz);
					if (si >= 0 && seen[si]) continue;
					int64_t s2 = state_at(nx, ny, nz);
					if (s2 < 0) { found = 1; break; }
					int t = (s2 < ntab) ? tab[s2] : 0;
					if (t == 1) { found = 1; break; }
					if (c.d + 1 < r && t == 2 && si >= 0) {
						seen[si] = 1;
						q.push_back({nx, ny, nz, c.d + 1});
					}
				}
			}
			keep = !found;
		}
		if (keep) { out.push_back(ci); out.push_back(sec); out.push_back(li); out.push_back(st); }
	}
	Owned o(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, o.ptr(), (int64_t)out.size());
	if (!out.empty()) memcpy(i32_w(o.ptr()), out.data(), out.size() * sizeof(int32_t));
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, o.ptr());
	return true;
}
// Experiment helper (FpsBench --merged): concatenate mesh surface arrays into one surface. list: Array of
// [Array arrays (Mesh.ARRAY_MAX: VERTEX PackedVector3Array, TEX_UV PackedVector2Array, COLOR PackedColorArray,
// CUSTOM0 PackedByteArray (RGBA half), INDEX PackedInt32Array), Vector3-as-PackedFloat32Array(3) origin].
// -> [vertices PackedVector3Array, uv PackedVector2Array, colors PackedColorArray, custom PackedByteArray, index PackedInt32Array]
bool fn_merge_surfaces(const Args &a, void *ret) {
	const void *lv = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	if (!lv) return false;
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, lv);
	std::vector<float> V, UV, C;
	std::vector<uint8_t> CU;
	std::vector<int32_t> IX;
	auto pk = [](const void *arr, int64_t k, GDExtensionVariantType t) -> const void * {
		const void *e = array_get(arr, k);
		if (!e || variant_get_type((GDExtensionConstVariantPtr)e) != t) return nullptr;
		return internal(t)((GDExtensionVariantPtr)e);
	};
	for (int64_t i = 0; i < n; i++) {
		const void *pair = pk(lv, i, GDEXTENSION_VARIANT_TYPE_ARRAY);
		if (!pair) continue;
		const void *arrs = pk(pair, 0, GDEXTENSION_VARIANT_TYPE_ARRAY);
		const void *ov = pk(pair, 1, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
		if (!arrs || !ov) continue;
		const float *o = f32(ov);
		const void *vv = pk(arrs, 0, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY);
		const void *uvv = pk(arrs, 4, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY);
		const void *cv = pk(arrs, 3, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
		const void *cuv = pk(arrs, 6, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
		const void *iv = pk(arrs, 12, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
		if (!vv || !uvv || !cv || !cuv || !iv) continue;
		int64_t nv = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, vv);
		int64_t base = (int64_t)(V.size() / 3);
		const float *pv = vec3(vv);
		for (int64_t k = 0; k < nv; k++) { V.push_back(pv[k * 3] + o[0]); V.push_back(pv[k * 3 + 1] + o[1]); V.push_back(pv[k * 3 + 2] + o[2]); }
		int64_t nuv = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, uvv);
		const float *puv = vec2_w(const_cast<void *>(uvv));   // experiment only (copy-on-write access is fine here)
		UV.insert(UV.end(), puv, puv + nuv * 2);
		int64_t nc = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, cv);
		const float *pc = color(cv);
		C.insert(C.end(), pc, pc + nc * 4);
		int64_t ncu = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, cuv);
		const uint8_t *pcu = bytes(cuv);
		CU.insert(CU.end(), pcu, pcu + ncu);
		int64_t ni = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, iv);
		const int32_t *pi = i32(iv);
		for (int64_t k = 0; k < ni; k++) IX.push_back((int32_t)(pi[k] + base));
	}
	Owned ov3(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY), ouv(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY), oc(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY), ocu(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY), oix(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, ov3.ptr(), (int64_t)V.size() / 3);
	if (!V.empty()) memcpy(vec3_w(ov3.ptr()), V.data(), V.size() * 4);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, ouv.ptr(), (int64_t)UV.size() / 2);
	if (!UV.empty()) memcpy(vec2_w(ouv.ptr()), UV.data(), UV.size() * 4);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, oc.ptr(), (int64_t)C.size() / 4);
	if (!C.empty()) memcpy(color_w(oc.ptr()), C.data(), C.size() * 4);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, ocu.ptr(), (int64_t)CU.size());
	if (!CU.empty()) memcpy(bytes_w(ocu.ptr()), CU.data(), CU.size());
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, oix.ptr(), (int64_t)IX.size());
	if (!IX.empty()) memcpy(i32_w(oix.ptr()), IX.data(), IX.size() * 4);
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 5);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, ov3.ptr());
	array_set_native(ret, 1, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, ouv.ptr());
	array_set_native(ret, 2, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, oc.ptr());
	array_set_native(ret, 3, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, ocu.ptr());
	array_set_native(ret, 4, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, oix.ptr());
	return true;
}

// Java worldgen fluid ticks (NoiseBasedChunkGenerator / carvers markPosForPostprocessing where the aquifer status
// changes, SpringFeature.scheduleTick): generated fluid that can flow on its first tick. fluid_exposed(nine: Array[9]
// (Chunk.sec_refs of the 3x3 chunks around, null = missing), kinds: PackedByteArray per state (1 air, 2 water /
// waterlogged, 3 lava), cx, cz) -> [PackedInt32Array local positions x | z << 4 | (y + 64) << 8 of the centre chunk's
// fluid cells with air below or beside, the other fluid below / beside, or (lava) water above].
bool fn_fluid_exposed(const Args &a, void *ret) {
	const void *nv = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *kv = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!nv || !kv || size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, nv) != 9) return false;
	int64_t nk = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, kv);
	const uint8_t *kinds = nk ? bytes(kv) : nullptr;
	int64_t ccx = a.i(2), ccz = a.i(3);
	struct Sec { bool init = false; const int32_t *pal = nullptr; int64_t np = 0; const uint8_t *idx = nullptr; const int32_t *wide = nullptr; };
	static thread_local Sec secs[9][24];
	const void *carr[9];
	for (int k = 0; k < 9; k++) {
		const void *e = array_get(nv, k);
		carr[k] = (e && variant_get_type((GDExtensionConstVariantPtr)e) == GDEXTENSION_VARIANT_TYPE_ARRAY) ? internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)e) : nullptr;
		if (carr[k] && size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, carr[k]) < 72) carr[k] = nullptr;
		for (int s = 0; s < 24; s++) secs[k][s].init = false;
	}
	auto get_packed = [](const void *arr, int64_t k, GDExtensionVariantType t) -> const void * {
		const void *e = array_get(arr, k);
		if (!e || variant_get_type((GDExtensionConstVariantPtr)e) != t) return nullptr;
		return internal(t)((GDExtensionVariantPtr)e);
	};
	auto sec = [&](int k, int s) -> Sec & {
		Sec &sc = secs[k][s];
		if (!sc.init) {
			sc.init = true;
			sc.np = 0;
			const void *pv = get_packed(carr[k], s * 3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
			const void *iv = get_packed(carr[k], s * 3 + 1, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
			const void *wv = get_packed(carr[k], s * 3 + 2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
			sc.np = pv ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pv) : 0;
			sc.pal = sc.np ? i32(pv) : nullptr;
			sc.idx = (iv && size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, iv) >= 4096) ? bytes(iv) : nullptr;
			sc.wide = (wv && size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wv) >= 4096) ? i32(wv) : nullptr;
		}
		return sc;
	};
	// kind of the block at chunk-relative (x, y, z), x / z in -1..16; 0 for missing chunks (never "exposed")
	auto kind_at = [&](int x, int y, int z) -> int {
		if (y < -64 || y >= 320) return y >= 320 ? 1 : 0;
		int ci = (x >> 4) + 1, cj = (z >> 4) + 1;
		int k = cj * 3 + ci;
		if (!carr[k]) return 0;
		Sec &sc = sec(k, (y + 64) >> 4);
		int64_t st;
		if (sc.np == 0) st = 0;
		else if (sc.np == 1) st = sc.pal[0];
		else {
			int li = ((y & 15) << 8) | ((z & 15) << 4) | (x & 15);
			int64_t pi = sc.wide ? sc.wide[li] : (sc.idx ? sc.idx[li] : 0);
			st = (pi >= 0 && pi < sc.np) ? sc.pal[pi] : 0;
		}
		return (st >= 0 && st < nk) ? kinds[st] : 0;
	};
	std::vector<int32_t> out;
	if (carr[4]) {
		for (int s = 0; s < 24; s++) {
			Sec &sc = sec(4, s);
			bool any = false;
			for (int64_t p = 0; p < sc.np && !any; p++) { int32_t st = sc.pal[p]; if (st >= 0 && st < nk && kinds[st] >= 2) any = true; }
			if (!any) continue;
			int y0 = -64 + s * 16;
			for (int ly = 0; ly < 16; ly++) {
				int y = y0 + ly;
				for (int z = 0; z < 16; z++)
					for (int x = 0; x < 16; x++) {
						int kd = kind_at(x, y, z);
						if (kd < 2) continue;
						int other = kd == 2 ? 3 : 2;
						bool ex = false;
						int nb[5] = {kind_at(x, y - 1, z), kind_at(x + 1, y, z), kind_at(x - 1, y, z), kind_at(x, y, z + 1), kind_at(x, y, z - 1)};
						for (int q = 0; q < 5 && !ex; q++) if (nb[q] == 1 || nb[q] == other) ex = true;
						if (!ex && kd == 3 && kind_at(x, y + 1, z) == 2) ex = true;
						if (ex) out.push_back(x | (z << 4) | ((y + 64) << 8));
					}
			}
		}
	}
	(void)ccx; (void)ccz;
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	Owned o(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, o.ptr(), (int64_t)out.size());
	if (!out.empty()) memcpy(i32_w(o.ptr()), out.data(), out.size() * sizeof(int32_t));
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, o.ptr());
	return true;
}

} // namespace

void register_chunkops(const char *cls) {
	register_method(cls, "fluid_exposed", fn_fluid_exposed, 4);
	register_method(cls, "merge_surfaces", fn_merge_surfaces, 1);
	register_method(cls, "leaf_search", fn_leaf_search, 6);
	register_method(cls, "rt_sample", fn_rt_sample, 4);
	register_method(cls, "rt_sample_range", fn_rt_sample_range, 6);
	register_method(cls, "rt_leaf_filter", fn_rt_leaf_filter, 8);
	register_method(cls, "anim_sample", fn_anim_sample, 9);
	register_method(cls, "tints", fn_tints, 9);
	register_method(cls, "sky_blend", fn_sky_blend, 9);
	register_method(cls, "jig_shuffle", fn_jig_shuffle, 3);
	register_method(cls, "boxes_hit", fn_boxes_hit, 7);
	register_method(cls, "rs_candidates", fn_rs_candidates, 10);
	register_method(cls, "chunk_finish", fn_chunk_finish, 4);
	register_method(cls, "chunk_decorate", fn_chunk_decorate, 12);
}
