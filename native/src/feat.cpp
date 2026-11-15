// Native feature kernels (bit-exact ports of scripts/world/features.gd) operating on the job-private flat region
// (Features._load_region). They never write the region: writes come back in order and GDScript applies them through
// Features.set_block, so the write list / overlay semantics stay in one place. RNG = Xoroshiro state in/out.
//   feat_ore(kind, flat, info, gf, rng, origin, params, rule_ints, rule_ids, rule_f, targets, st_block)
//     kind 0 = ore, 1 = scattered_ore
//     info: PackedInt32Array [fx0, fz0, has0..8, hstate0..8]; gf: PackedInt32Array(2304) OCEAN_FLOOR_WG per column
//     rng: PackedInt64-in-Array [lo, hi]; origin: PackedInt32Array [x, y, z]; params: PackedFloat64Array [size, discard]
//     rule_ints: 4 per node [type, a, b, c]; rule_ids: block ids; rule_f: probabilities; targets: [node, state]*
//   -> [status (0 ok, 1 fallback needed), placed (0/1), lo, hi, writes: PackedInt32Array (x, y, z, state)*]
#include "native.h"
#include "rng.h"
#include <vector>
#include <cmath>
#include <unordered_map>
#include <unordered_set>

using namespace gdx;
using namespace rn;

namespace {

const double PI = 3.141592653589793;
enum RT { RT_TRUE, RT_IDS, RT_STATE, RT_RAND, RT_HEIGHT, RT_ANY, RT_ALL, RT_NOT };

struct Region {
	const int32_t *flat = nullptr;
	int fx0 = 0, fz0 = 0;
	uint8_t has[9] = {0}, hst[9] = {0};
	const int32_t *gf = nullptr;
	std::unordered_map<int64_t, int32_t> own;   // writes made by this kernel call
	static int64_t key(int x, int y, int z) { return ((int64_t)(x & 0x3FFFFFF) << 38) | ((int64_t)(z & 0x3FFFFFF) << 12) | (int64_t)((y + 2048) & 0xFFF); }
	bool in_region(int x, int z) const {
		int lx = x - fx0, lz = z - fz0;
		return lx >= 0 && lx < 48 && lz >= 0 && lz < 48 && has[(lz >> 4) * 3 + (lx >> 4)];
	}
	int32_t get(int x, int y, int z) const {
		int lx = x - fx0, lz = z - fz0;
		if (lx < 0 || lx >= 48 || lz < 0 || lz >= 48 || y < -64 || y >= 320) return 0;
		int ci = (lz >> 4) * 3 + (lx >> 4);
		if (!has[ci]) return 0;
		if (!own.empty()) {
			auto it = own.find(key(x, y, z));
			if (it != own.end()) return it->second;
		}
		return flat[(size_t)ci * 98304 + ((y + 64) << 8) + ((lz & 15) << 4) + (lx & 15)];
	}
	// Features.height(c, "OCEAN_FLOOR_WG", x, z); returns false when the slow legacy path would be needed
	bool floor_height(int x, int z, int &out) const {
		int lx = x - fx0, lz = z - fz0;
		if (lx < 0 || lx >= 48 || lz < 0 || lz >= 48) { out = -64; return true; }
		int ci = (lz >> 4) * 3 + (lx >> 4);
		if (hst[ci] == 0) { out = -64; return true; }
		if (hst[ci] == 1) return false;
		out = gf[ci * 256 + (lx & 15) + (lz & 15) * 16];
		return true;
	}
};

struct Rules {
	const int32_t *ri = nullptr;
	const int32_t *ids = nullptr;
	const double *pf = nullptr;
	const int32_t *st_block = nullptr;
	int64_t n_states = 0;
	bool test(int node, int st, int py, WorldgenXoro &r) const {
		const int32_t *q = ri + node * 4;
		switch (q[0]) {
			case RT_TRUE: return true;
			case RT_IDS: {
				if (st < 0 || st >= n_states) return false;
				int b = st_block[st];
				for (int k = 0; k < q[2]; k++) if (ids[q[1] + k] == b) return true;
				return false;
			}
			case RT_STATE: return st == q[1];
			case RT_RAND: {
				if (st < 0 || st >= n_states) return false;
				int b = st_block[st];
				bool hit = false;
				for (int k = 0; k < q[2]; k++) if (ids[q[1] + k] == b) { hit = true; break; }
				if (!hit) return false;
				return r.next_float() < pf[q[3]];
			}
			case RT_HEIGHT: return py >= q[1] && py <= q[2];
			case RT_ANY:
				for (int k = 0; k < q[2]; k++) if (test(ids[q[1] + k], st, py, r)) return true;
				return false;
			case RT_ALL:
				for (int k = 0; k < q[2]; k++) if (!test(ids[q[1] + k], st, py, r)) return false;
				return true;
			case RT_NOT: return !test(q[1], st, py, r);
		}
		return true;
	}
};

struct Kernel {
	Region rg;
	Rules ru;
	WorldgenXoro r;   // Java WorldgenRandom(XoroshiroRandomSource)
	const int32_t *targets = nullptr;
	int ntargets = 0;
	double discard = 0.0;
	std::vector<int32_t> writes;

	bool can_place(int tnode, int st, int x, int y, int z) {
		if (!ru.test(tnode, st, y, r)) return false;
		if (discard <= 0.0) return true;
		if (discard < 1.0 && r.next_float() >= discard) return true;
		static const int D[6][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
		for (int k = 0; k < 6; k++) if (rg.get(x + D[k][0], y + D[k][1], z + D[k][2]) == 0) return false;
		return true;
	}
	void set(int x, int y, int z, int st) {
		if (y < -64 || y >= 320 || st < 0) return;
		if (!rg.in_region(x, z)) return;
		rg.own[Region::key(x, y, z)] = st;
		writes.push_back(x); writes.push_back(y); writes.push_back(z); writes.push_back(st);
	}
	// returns -1 when the legacy height path is needed (nothing consumed from the caller's point of view)
	int ore(int ox, int oy, int oz, int size) {
		double f = r.next_float() * PI;
		double g = size / 8.0;
		int i = (int)std::ceil((size / 16.0 * 2.0 + 1.0) / 2.0);
		double d = ox + std::sin(f) * g;
		double e = ox - std::sin(f) * g;
		double h = oz + std::cos(f) * g;
		double j = oz - std::cos(f) * g;
		double l = (double)(oy + r.next_int_bound(3) - 2);
		double m = (double)(oy + r.next_int_bound(3) - 2);
		int cg = (int)std::ceil(g);
		int n = ox - cg - i;
		int oo = oy - 2 - i;
		int pz = oz - cg - i;
		int q = 2 * (cg + i);
		bool ok = false;
		for (int s = n; s <= n + q && !ok; s++)
			for (int t = pz; t <= pz + q; t++) {
				int hv;
				if (!rg.floor_height(s, t, hv)) return -1;
				if (oo <= hv) { ok = true; break; }
			}
		if (!ok) return 0;
		std::vector<double> ds((size_t)size * 4);
		for (int u = 0; u < size; u++) {
			double v = (double)u / size;
			ds[u * 4] = d + (e - d) * v;
			ds[u * 4 + 1] = l + (m - l) * v;
			ds[u * 4 + 2] = h + (j - h) * v;
			double z = r.next_double() * size / 16.0;
			ds[u * 4 + 3] = ((std::sin(PI * v) + 1.0) * z + 1.0) / 2.0;
		}
		for (int u = 0; u < size - 1; u++) {
			if (ds[u * 4 + 3] <= 0.0) continue;
			for (int ab = u + 1; ab < size; ab++) {
				if (ds[ab * 4 + 3] <= 0.0) continue;
				double w2 = ds[u * 4] - ds[ab * 4];
				double x2 = ds[u * 4 + 1] - ds[ab * 4 + 1];
				double y2 = ds[u * 4 + 2] - ds[ab * 4 + 2];
				double z2 = ds[u * 4 + 3] - ds[ab * 4 + 3];
				if (z2 * z2 > w2 * w2 + x2 * x2 + y2 * y2) {
					if (z2 > 0.0) ds[ab * 4 + 3] = -1.0;
					else ds[u * 4 + 3] = -1.0;
				}
			}
		}
		std::unordered_set<int64_t> seen;
		bool placed = false;
		for (int ab = 0; ab < size; ab++) {
			double rad = ds[ab * 4 + 3];
			if (rad < 0.0) continue;
			double cx = ds[ab * 4], cy = ds[ab * 4 + 1], cz = ds[ab * 4 + 2];
			int x0 = std::max((int)std::floor(cx - rad), n);
			int y0 = std::max((int)std::floor(cy - rad), oo);
			int z0 = std::max((int)std::floor(cz - rad), pz);
			int x1 = std::max((int)std::floor(cx + rad), x0);
			int y1 = std::max((int)std::floor(cy + rad), y0);
			int z1 = std::max((int)std::floor(cz + rad), z0);
			for (int xx = x0; xx <= x1; xx++) {
				double aj = (xx + 0.5 - cx) / rad;
				if (aj * aj >= 1.0) continue;
				for (int yy = y0; yy <= y1; yy++) {
					double al = (yy + 0.5 - cy) / rad;
					if (aj * aj + al * al >= 1.0) continue;
					for (int zz = z0; zz <= z1; zz++) {
						double an = (zz + 0.5 - cz) / rad;
						if (aj * aj + al * al + an * an >= 1.0 || yy < -64 || yy >= 320) continue;
						int64_t k = Region::key(xx, yy, zz);
						if (!seen.insert(k).second) continue;
						if (!rg.in_region(xx, zz)) continue;
						int st = rg.get(xx, yy, zz);
						for (int t = 0; t < ntargets; t++) {
							if (can_place(targets[t * 2], st, xx, yy, zz)) {
								set(xx, yy, zz, targets[t * 2 + 1]);
								placed = true;
								break;
							}
						}
					}
				}
			}
		}
		return placed ? 1 : 0;
	}
	int spread(int s) {
		double a = r.next_float();
		double b = r.next_float();
		return (int)std::round((a - b) * s);
	}
	int scattered(int ox, int oy, int oz, int size) {
		int64_t n = r.next_int_bound(size + 1);
		for (int64_t k = 0; k < n; k++) {
			int sp = (int)std::min<int64_t>(k, 7);
			int dx = spread(sp);
			int dy = spread(sp);
			int dz = spread(sp);
			int x = ox + dx, y = oy + dy, z = oz + dz;
			int st = rg.get(x, y, z);
			for (int t = 0; t < ntargets; t++) {
				if (can_place(targets[t * 2], st, x, y, z)) {
					set(x, y, z, targets[t * 2 + 1]);
					break;
				}
			}
		}
		return 1;
	}
};

static const void *packed(const Args &a, int k, GDExtensionVariantType t) { return a.obj(k, t); }

bool fn_feat_ore(const Args &a, void *ret) {
	int kind = (int)a.i(0);
	const void *flat = packed(a, 1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *info = packed(a, 2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *gf = packed(a, 3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *rng = a.obj(4, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *org = packed(a, 5, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *prm = packed(a, 6, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY);
	const void *rint = packed(a, 7, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *rids = packed(a, 8, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *rf = packed(a, 9, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY);
	const void *tgs = packed(a, 10, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *stb = packed(a, 11, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	if (!flat || !info || !gf || !rng || !org || !prm || !rint || !rids || !rf || !tgs || !stb) return false;
	if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, flat) != 9 * 98304 || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, info) < 20) return false;
	Kernel kr;
	const int32_t *in = i32(info);
	kr.rg.flat = i32(flat);
	kr.rg.fx0 = in[0]; kr.rg.fz0 = in[1];
	for (int k = 0; k < 9; k++) { kr.rg.has[k] = (uint8_t)in[2 + k]; kr.rg.hst[k] = (uint8_t)in[11 + k]; }
	kr.rg.gf = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, gf) >= 2304 ? i32(gf) : nullptr;
	if (!kr.rg.gf) for (int k = 0; k < 9; k++) if (kr.rg.hst[k] == 2) kr.rg.hst[k] = 1;
	int64_t lo = 0, hi = 0;
	to_type(GDEXTENSION_VARIANT_TYPE_INT)(&lo, (GDExtensionVariantPtr)array_get(rng, 0));
	to_type(GDEXTENSION_VARIANT_TYPE_INT)(&hi, (GDExtensionVariantPtr)array_get(rng, 1));
	kr.r.lo = lo; kr.r.hi = hi;
	const int32_t *o = i32(org);
	const double *p = f64(prm);
	kr.discard = p[1];
	kr.ru.ri = i32(rint);
	kr.ru.ids = i32(rids);
	kr.ru.pf = f64(rf);
	kr.ru.st_block = i32(stb);
	kr.ru.n_states = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, stb);
	kr.targets = i32(tgs);
	kr.ntargets = (int)(size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, tgs) / 2);
	int res = kind == 0 ? kr.ore(o[0], o[1], o[2], (int)p[0]) : kr.scattered(o[0], o[1], o[2], (int)p[0]);
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 5);
	if (res < 0) {
		array_set_int(ret, 0, 1);
		array_set_int(ret, 1, 0);
		array_set_int(ret, 2, lo);
		array_set_int(ret, 3, hi);
		Owned empty(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
		array_set_native(ret, 4, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, empty.ptr());
		return true;
	}
	Owned w(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, w.ptr(), (int64_t)kr.writes.size());
	if (!kr.writes.empty()) memcpy(i32_w(w.ptr()), kr.writes.data(), kr.writes.size() * sizeof(int32_t));
	array_set_int(ret, 0, 0);
	array_set_int(ret, 1, res);
	array_set_int(ret, 2, kr.r.lo);
	array_set_int(ret, 3, kr.r.hi);
	array_set_native(ret, 4, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, w.ptr());
	return true;
}

} // namespace

void register_feat(const char *cls) {
	register_method(cls, "feat_ore", fn_feat_ore, 12);
}
