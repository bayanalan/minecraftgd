// Mob ground pathfinding: native port of scripts/entities/mob_path.gd (Java PathFinder + WalkNodeEvaluator,
// simplified). Same node rules, costs and neighbour order as the GDScript version, which remains the fallback when
// the native library is missing (equal-cost ties may resolve differently; stroll targets use their own random source).
//
// path_find(grid, gw, gh, cx0, cz0, cls, p) -> [PackedInt32Array nodes (x,y,z)..., reached 0/1, visited, gx, gy, gz]
//   grid: Array[gw*gh] (index cj*gw + ci for chunk (cx0+ci, cz0+cj)) of Chunk.sec_refs() arrays
//         [pal0, idx0, wide0, ... x24] or null (not loaded = blocked)
//   cls: PackedInt32Array per block state: top height in 16ths (0..24) | C_* flags (MobPath.class_table())
//   p: PackedInt32Array [sx, sy, sz, start_fy*1000, gx, gy, gz, reach, max_nodes, max_dist, h*1000, land, mode,
//      seed]; mode 0 = path to (gx, gy, gz), 1 = stroll (random target 10 / 7), 2 = panic (5 / 4)
#include "native.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <queue>
#include <unordered_map>
#include <vector>

using namespace gdx;

namespace {
const int C_WATER = 32, C_BLOCK = 64, C_FIRE = 128, C_STICKY = 256, C_GRASS = 1024;
const int MAX_FALL = 3;
const int DXS[8] = {0, 0, 1, -1, 1, 1, -1, -1};
const int DZS[8] = {1, -1, 0, 0, 1, -1, 1, -1};

inline int64_t key(int64_t x, int64_t y, int64_t z) {
	return ((x + 33554432) << 36) | ((z + 33554432) << 10) | (y + 256);
}
inline void unkey(int64_t k, int &x, int &y, int &z) {
	x = (int)((k >> 36) - 33554432);
	y = (int)((k & 1023) - 256);
	z = (int)(((k >> 10) & 67108863) - 33554432);
}

struct NodeV { double mal; double fy; };   // mal -1 blocked, -2 open with no floor

struct Search {
	struct Sec { bool init = false; const int32_t *pal = nullptr; int64_t np = 0; const uint8_t *idx = nullptr; const int32_t *wide = nullptr; };
	std::vector<const void *> carr;
	std::vector<Sec> secs;
	int gw = 0, gh = 0;
	int64_t cx0 = 0, cz0 = 0;
	const int32_t *cls = nullptr;
	int64_t ncls = 0;
	double h = 1.8;
	bool land = true;
	int hc = 2;
	std::unordered_map<int64_t, int> cells;
	std::unordered_map<int64_t, NodeV> nodes;
	uint64_t rng = 1;

	static const void *get_packed(const void *arr, int64_t k, GDExtensionVariantType t) {
		const void *e = array_get(arr, k);
		if (!e || variant_get_type((GDExtensionConstVariantPtr)e) != t) return nullptr;
		return internal(t)((GDExtensionVariantPtr)e);
	}

	int64_t state(int64_t x, int64_t y, int64_t z) {
		int64_t ci = (x >> 4) - cx0, cj = (z >> 4) - cz0;
		if (ci < 0 || ci >= gw || cj < 0 || cj >= gh) return -1;
		int k = (int)(cj * gw + ci);
		if (!carr[k]) return -1;
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
		if (!sc.pal) return -1;
		if (sc.np == 1) return sc.pal[0];
		int i = (int)(((y & 15) << 8) | ((z & 15) << 4) | (x & 15));
		int64_t pi = sc.wide ? sc.wide[i] : (sc.idx ? sc.idx[i] : 0);
		if (pi < 0 || pi >= sc.np) return -1;
		return sc.pal[pi];
	}

	int cell(int x, int y, int z) {
		int64_t k = key(x, y, z);
		auto it = cells.find(k);
		if (it != cells.end()) return it->second;
		int c = C_BLOCK;
		if (y >= 320) c = 0;
		else if (y >= -64) {
			int64_t st = state(x, y, z);
			c = st < 0 ? C_BLOCK : (st == 0 ? 0 : (st < ncls ? cls[st] : C_BLOCK));
		}
		cells[k] = c;
		return c;
	}

	NodeV node_calc(int x, int y, int z) {
		int c0 = cell(x, y, z);
		if (c0 & C_BLOCK) return {-1, 0};
		int t0 = c0 & 31;
		double mal = 0.0, fy = y;
		if (c0 & C_FIRE) mal = 16.0;
		if (t0 > 8) return {-1, 0};
		if (t0 > 0) {
			fy = y + t0 / 16.0;
		} else if (c0 & C_WATER) {
			if (cell(x, y + 1, z) & C_WATER) return {-1, 0};
			if (land) mal = std::max(mal, 8.0);
		} else {
			int c1 = cell(x, y - 1, z);
			int t1 = c1 & 31;
			if ((c1 & C_BLOCK) && t1 == 0) return {-1, 0};
			if (t1 < 8) return {-2, 0};
			if (t1 > 16 || (c1 & C_BLOCK)) return {-1, 0};
			fy = y - 1 + t1 / 16.0;
			if (c1 & C_FIRE) mal = std::max(mal, 16.0);
			if (c1 & C_STICKY) mal = std::max(mal, 8.0);
		}
		int top = (int)std::ceil(fy + h - 0.001);
		for (int cy = y + 1; cy < top; cy++) {
			int c = cell(x, cy, z);
			if (c & (C_BLOCK | 31)) return {-1, 0};
		}
		return {mal, fy};
	}

	NodeV node(int x, int y, int z) {
		int64_t k = key(x, y, z);
		auto it = nodes.find(k);
		if (it != nodes.end()) return it->second;
		NodeV r = node_calc(x, y, z);
		nodes[k] = r;
		return r;
	}

	static const int NONE = -99999;

	int accept(int cx, int cy, int cz, double cfy, int nx, int nz) {
		NodeV v = node(nx, cy, nz);
		if (v.mal >= 0.0) return v.fy - cfy <= 1.125 ? cy : NONE;
		if (v.mal == -1.0) {
			if (cell(cx, cy + hc, cz) & (C_BLOCK | 31)) return NONE;
			NodeV u = node(nx, cy + 1, nz);
			if (u.mal >= 0.0 && u.fy - cfy <= 1.25) return cy + 1;
			return NONE;
		}
		for (int d = 1; d < MAX_FALL + 2; d++) {
			NodeV w = node(nx, cy - d, nz);
			if (w.mal >= 0.0) return cy - d;
			if (w.mal == -1.0) return NONE;
		}
		return NONE;
	}

	// Godot RandomNumberGenerator is not reproducible here; any uniform source works (targets are random anyway)
	uint32_t next() {
		rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17;
		return (uint32_t)(rng >> 16);
	}
	int range(int lo, int hi) { return lo + (int)(next() % (uint32_t)(hi - lo + 1)); }

	// Java RandomPos / LandRandomPos: 10 tries; animals prefer grass, otherwise the first standable spot wins ties
	bool pick_random(int sx, int sy, int sz, int hr, int vr, bool monster, int &gx, int &gy, int &gz) {
		bool found = false;
		double best_v = -1e30;
		for (int i = 0; i < 10; i++) {
			int x = sx + range(-hr, hr), y = sy + range(-vr, vr), z = sz + range(-hr, hr);
			bool ok = false;
			for (int d = 0; d < 2 * vr + 1; d++) {
				NodeV v = node(x, y, z);
				if (v.mal >= 0.0) { ok = true; break; }
				y += v.mal == -1.0 ? 1 : -1;
			}
			if (!ok) continue;
			if (land && (cell(x, y, z) & C_WATER)) continue;
			double val = monster ? 0.0 : ((cell(x, y - 1, z) & C_GRASS) ? 10.0 : 0.0);
			if (val > best_v) { best_v = val; gx = x; gy = y; gz = z; found = true; }
		}
		return found;
	}
};

bool fn_path_find(const Args &a, void *ret) {
	const void *gv = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *cv = a.obj(5, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *pv = a.obj(6, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	if (!gv || !cv || !pv || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pv) < 14) return false;
	Search s;
	s.gw = (int)a.i(1);
	s.gh = (int)a.i(2);
	s.cx0 = a.i(3);
	s.cz0 = a.i(4);
	if (s.gw < 1 || s.gh < 1 || s.gw * s.gh > 400 || size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, gv) < s.gw * s.gh) return false;
	s.ncls = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, cv);
	s.cls = s.ncls ? i32(cv) : nullptr;
	s.carr.resize((size_t)s.gw * s.gh);
	s.secs.resize((size_t)s.gw * s.gh * 24);
	for (int k = 0; k < s.gw * s.gh; k++) {
		const void *e = array_get(gv, k);
		const void *c = (e && variant_get_type((GDExtensionConstVariantPtr)e) == GDEXTENSION_VARIANT_TYPE_ARRAY) ? internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)e) : nullptr;
		if (c && size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, c) < 72) c = nullptr;
		s.carr[k] = c;
	}
	const int32_t *p = i32(pv);
	int sx = p[0], sy = p[1], sz = p[2];
	double start_fy = p[3] / 1000.0;
	int gx = p[4], gy = p[5], gz = p[6];
	int reach = p[7], max_nodes = p[8];
	double max_dist = p[9];
	s.h = p[10] / 1000.0;
	s.land = p[11] != 0;
	int mode = p[12] & 3;
	bool monster = (p[12] & 4) != 0;
	s.rng = (uint64_t)(uint32_t)p[13] * 2654435761ull + 0x9E3779B97F4A7C15ull;
	if (s.rng == 0) s.rng = 1;
	s.hc = std::max(1, (int)std::ceil(s.h));

	bool reached = false;
	int visited = 0;
	std::vector<int32_t> out;
	bool have_goal = true;
	if (mode != 0) have_goal = mode == 1 ? s.pick_random(sx, sy, sz, 10, 7, monster, gx, gy, gz) : s.pick_random(sx, sy, sz, 5, 4, monster, gx, gy, gz);
	if (have_goal) {
		auto hdist = [&](int x, int y, int z) { double dx = x - gx, dy = y - gy, dz = z - gz; return std::sqrt(dx * dx + dy * dy + dz * dz); };
		struct QE { double f; int64_t seq; int64_t k; };
		struct Cmp { bool operator()(const QE &x, const QE &y) const { return x.f > y.f || (x.f == y.f && x.seq > y.seq); } };
		std::priority_queue<QE, std::vector<QE>, Cmp> open;
		std::unordered_map<int64_t, double> g;
		std::unordered_map<int64_t, int64_t> from;
		std::unordered_map<int64_t, bool> closed;
		int64_t seq = 0;
		int64_t sk = key(sx, sy, sz);
		g[sk] = 0.0;
		int64_t best = sk;
		double best_h = hdist(sx, sy, sz);
		open.push({best_h, seq++, sk});
		while (!open.empty()) {
			QE q = open.top();
			open.pop();
			if (closed.count(q.k)) continue;
			closed[q.k] = true;
			int cx, cy, cz;
			unkey(q.k, cx, cy, cz);
			double hd = hdist(cx, cy, cz);
			if (std::abs(cx - gx) + std::abs(cy - gy) + std::abs(cz - gz) <= reach) { best = q.k; reached = true; break; }
			if (hd < best_h) { best_h = hd; best = q.k; }
			visited++;
			if (visited >= max_nodes) break;
			double gc = g[q.k];
			double cfy = q.k == sk ? start_fy : s.node(cx, cy, cz).fy;
			int ok_dirs = 0;
			for (int d = 0; d < 8; d++) {
				int dx = DXS[d], dz = DZS[d];
				int ny = Search::NONE;
				if (d < 4) {
					ny = s.accept(cx, cy, cz, cfy, cx + dx, cz + dz);
					if (ny == cy) ok_dirs |= 1 << d;
				} else {
					int sa = dx > 0 ? 4 : 8, sb = dz > 0 ? 1 : 2;
					if ((ok_dirs & sa) && (ok_dirs & sb)) {
						NodeV v = s.node(cx + dx, cy, cz + dz);
						if (v.mal >= 0.0 && v.fy - cfy <= 0.6) ny = cy;
					}
				}
				if (ny == Search::NONE) continue;
				int nx = cx + dx, nz = cz + dz;
				int64_t nk = key(nx, ny, nz);
				if (closed.count(nk)) continue;
				double ex = nx - sx, ey = ny - sy, ez = nz - sz;
				if (std::sqrt(ex * ex + ey * ey + ez * ez) > max_dist) continue;
				NodeV nv = s.node(nx, ny, nz);
				double ng = gc + std::sqrt((double)(dx * dx + (ny - cy) * (ny - cy) + dz * dz)) + std::max(nv.mal, 0.0);
				auto it = g.find(nk);
				if (it != g.end() && it->second <= ng) continue;
				g[nk] = ng;
				from[nk] = q.k;
				open.push({ng + hdist(nx, ny, nz), seq++, nk});
			}
		}
		std::vector<int64_t> rev;
		int64_t cur = best;
		while (cur != sk) {
			auto it = from.find(cur);
			if (it == from.end()) break;
			rev.push_back(cur);
			cur = it->second;
		}
		for (auto r = rev.rbegin(); r != rev.rend(); ++r) {
			int x, y, z;
			unkey(*r, x, y, z);
			out.push_back(x); out.push_back(y); out.push_back(z);
		}
	}
	Owned arr(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, arr.ptr(), (int64_t)out.size());
	if (!out.empty()) memcpy(i32_w(arr.ptr()), out.data(), out.size() * sizeof(int32_t));
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 6);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, arr.ptr());
	array_set_int(ret, 1, reached ? 1 : 0);
	array_set_int(ret, 2, visited);
	array_set_int(ret, 3, have_goal ? gx : 0);
	array_set_int(ret, 4, have_goal ? gy : -9999);
	array_set_int(ret, 5, have_goal ? gz : 0);
	return true;
}
}  // namespace

void register_pathfind(const char *cls) {
	register_method(cls, "path_find", fn_path_find, 7);
}
