// Native feature engine: runs a whole top-level placed feature (placement modifiers + configured feature tree) with
// the exact semantics of scripts/world/features.gd, over the job-private flat region (Features._load_region).
// Node arrays come from scripts/world/features_native.gd. Writes go straight into the flat region buffer (job-private,
// so no copy-on-write is involved) and are also returned as the (x, y, z, state, mode) list for FCtx.writes.
//   fx_config(desc: Array) -> [handle]
//   fx_run(handle, pf, bset, flat, info, gs, gf, bio, rng: [lo, hi], origin: PackedInt32Array[3]) -> [lo, hi, writes]
#include "native.h"
#include "rng.h"
#include <vector>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <mutex>
#include <unordered_set>

using namespace gdx;
using namespace rn;

namespace {

const double PI = 3.141592653589793;
const int MIN_Y = -64, MAX_Y = 320;
const int W_FORCE = 0, W_REPLACEABLE = 1, W_AIR = 2;

static void rd_i32(const void *v, std::vector<int32_t> &out) {
	const void *a = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)v);
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, a);
	const int32_t *d = i32(a);
	out.assign(d, d + n);
}
static void rd_f64(const void *v, std::vector<double> &out) {
	const void *a = internal(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY)((GDExtensionVariantPtr)v);
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, a);
	const double *d = f64(a);
	out.assign(d, d + n);
}
static void rd_u8(const void *v, std::vector<uint8_t> &out) {
	const void *a = internal(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)((GDExtensionVariantPtr)v);
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, a);
	const uint8_t *d = bytes(a);
	out.assign(d, d + n);
}

struct FxCfg {
	std::vector<int32_t> I, flags, stblock, half_up, wl, consts, simplex;
	std::vector<uint8_t> airn, logn;
	int F_LEAVES = 1048576;
	std::vector<double> F;
	std::vector<uint8_t> M, BS, cat, below;
	int F_LIQUID = 8, F_WATERLOGGED = 256, F_COLLIDE = 4, F_REPLACEABLE = 16, F_FULL_SHAPE = 262144, F_OPAQUE = 2, F_LAVA = 65536;
	int gen_min_y = -64, gen_depth = 384;
};

std::mutex g_m;
std::vector<FxCfg *> g_cfgs;

struct Fx {
	const FxCfg &c;
	const int32_t *I;
	const double *F;
	int32_t *flat = nullptr;
	int fx0 = 0, fz0 = 0;
	uint8_t has[9] = {0}, hst[9] = {0};
	const int32_t *gs = nullptr, *gf = nullptr;
	int32_t *hl = nullptr;   // live heightmaps (Features.FCtx.hl), written in place; null = pristine only
	const uint8_t *bio = nullptr;
	const uint8_t *bset = nullptr;
	int nbio = 0;
	Xoroshiro r;
	std::vector<int32_t> writes;
	std::vector<int64_t> bes;   // block entity requests: kind, x, y, z, value

	// Features.SimplexNoise.value (same algorithm as MCNoise.Simplex.value2)
	double simplex(double d, double e) const {
		static const double GX[16] = {1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0};
		static const double GY[16] = {1.0, 1.0, -1.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0};
		const int32_t *p = c.simplex.data();
		const double F2 = 0.3660254037844386, G2 = 0.21132486540518713;
		double h = (d + e) * F2;
		int64_t i = (int64_t)std::floor(d + h), j = (int64_t)std::floor(e + h);
		double k = (double)(i + j) * G2;
		double n = d - ((double)i - k), o = e - ((double)j - k);
		int pp = n > o ? 1 : 0, qq = n > o ? 0 : 1;
		double rr = n - pp + G2, s = o - qq + G2;
		double t = n - 1.0 + 2.0 * G2, u = o - 1.0 + 2.0 * G2;
		int64_t v = i & 255, w = j & 255;
		int gx = p[(v + p[w & 255]) & 255] % 12;
		int gy = p[(v + pp + p[(w + qq) & 255]) & 255] % 12;
		int gz = p[(v + 1 + p[(w + 1) & 255]) & 255] % 12;
		auto corner = [&](int g, double x, double y) -> double { double hh = 0.5 - x * x - y * y; if (hh < 0.0) return 0.0; hh *= hh; return hh * hh * (GX[g] * x + GY[g] * y); };
		double a = corner(gx, n, o);
		double b = corner(gy, rr, s);
		double cc = corner(gz, t, u);
		return 70.0 * (a + b + cc);
	}

	explicit Fx(const FxCfg &cf) : c(cf), I(cf.I.data()), F(cf.F.data()) {}

	// ---------------------------------------------------------------- region access (Features.get_block / set_block)
	int get(int x, int y, int z) const {
		int lx = x - fx0, lz = z - fz0;
		if (lx < 0 || lx >= 48 || lz < 0 || lz >= 48 || y < -64 || y >= 320) return 0;
		int ci = (lz >> 4) * 3 + (lx >> 4);
		if (!has[ci]) return 0;
		return flat[(size_t)ci * 98304 + ((y + 64) << 8) + ((lz & 15) << 4) + (lx & 15)];
	}
	bool in_region(int x, int z) const {
		int lx = x - fx0, lz = z - fz0;
		return lx >= 0 && lx < 48 && lz >= 0 && lz < 48 && has[(lz >> 4) * 3 + (lx >> 4)];
	}
	void set(int x, int y, int z, int st, int mode) {
		if (y < MIN_Y || y >= MAX_Y || st < 0) return;
		int lx = x - fx0, lz = z - fz0;
		if (lx < 0 || lx >= 48 || lz < 0 || lz >= 48) return;
		int ci = (lz >> 4) * 3 + (lx >> 4);
		if (!has[ci]) return;
		flat[(size_t)ci * 98304 + ((y + 64) << 8) + ((lz & 15) << 4) + (lx & 15)] = st;
		writes.push_back(x); writes.push_back(y); writes.push_back(z); writes.push_back(st); writes.push_back(mode);
		if (hl && hst[ci] == 2) hl_update(lx, y, lz, ci, st);
	}
	int flags(int st) const { return (st >= 0 && st < (int)c.flags.size()) ? c.flags[st] : 0; }
	// Features._hl_ok: 0 WORLD_SURFACE, 1 OCEAN_FLOOR, 2 MOTION_BLOCKING, 3 MOTION_BLOCKING_NO_LEAVES
	bool hl_ok(int k, int st) const {
		if (st <= 0) return false;
		int fl = flags(st);
		if (fl & 1) return false;   // F_AIR
		switch (k) {
			case 0: return true;
			case 1: return (fl & c.F_COLLIDE) != 0;
			case 2: return (fl & (c.F_COLLIDE | c.F_LIQUID | c.F_WATERLOGGED)) != 0;
			default: return (fl & (c.F_COLLIDE | c.F_LIQUID | c.F_WATERLOGGED)) != 0 && (fl & c.F_LEAVES) == 0;
		}
	}
	// Features._hl_update (Java Heightmap.update)
	void hl_update(int lx, int y, int lz, int ci, int st) {
		int col = lz * 48 + lx;
		for (int k = 0; k < 4; k++) {
			int32_t &h = hl[k * 2304 + col];
			if (y <= h - 2) continue;
			if (hl_ok(k, st)) { if (y >= h) h = y + 1; }
			else if (h - 1 == y) {
				size_t base = (size_t)ci * 98304 + ((lz & 15) << 4) + (lx & 15);
				int nh = MIN_Y;
				for (int j = y - 1; j >= MIN_Y; j--)
					if (hl_ok(k, flat[base + ((size_t)(j + 64) << 8)])) { nh = j + 1; break; }
				h = nh;
			}
		}
	}
	// Features.height: kind 0 WORLD_SURFACE_WG, 1 OCEAN_FLOOR_WG (pristine), 2 WORLD_SURFACE, 3 OCEAN_FLOOR,
	// 4 MOTION_BLOCKING, 5 MOTION_BLOCKING_NO_LEAVES (live) (hstate 1 regions never reach the engine)
	int height(int kind, int x, int z) const {
		int lx = x - fx0, lz = z - fz0;
		if (lx < 0 || lx >= 48 || lz < 0 || lz >= 48) return MIN_Y;
		int ci = (lz >> 4) * 3 + (lx >> 4);
		int hs = hst[ci];
		if (hs == 0) return MIN_Y;
		if (hs == 2 && hl && kind >= 2) return hl[(kind - 2) * 2304 + lz * 48 + lx];
		int hi = ci * 256 + (lx & 15) + (lz & 15) * 16;
		if (kind == 1 || kind == 3) return gf[hi];
		return gs[hi] + 1;
	}
	int biome(int x, int y, int z) const {
		int lx = x - fx0, lz = z - fz0;
		if (lx < 0 || lx >= 48 || lz < 0 || lz >= 48) return -1;
		int ci = (lz >> 4) * 3 + (lx >> 4);
		if (!has[ci]) return -1;
		int yy = y < MIN_Y ? MIN_Y : (y > MAX_Y - 1 ? MAX_Y - 1 : y);
		int qy = (yy - MIN_Y) >> 2;
		qy = qy < 0 ? 0 : (qy > 95 ? 95 : qy);
		return bio[ci * 1536 + ((lx & 15) >> 2) + ((lz & 15) >> 2) * 4 + qy * 16];
	}

	// ---------------------------------------------------------------- providers of numbers
	double gauss() {
		while (true) {
			double d = 2.0 * r.next_double() - 1.0;
			double e = 2.0 * r.next_double() - 1.0;
			double f = d * d + e * e;
			if (f < 1.0 && f != 0.0) return d * std::sqrt(-2.0 * std::log(f) / f);
		}
	}
	int64_t ip(int o) {
		const int32_t *n = I + o;
		switch (n[0]) {
			case 0: return n[1];
			case 1: { int64_t lo = n[1], hi = n[2]; return hi >= lo ? lo + r.next_int_bound(hi - lo + 1) : lo; }
			case 2: { int64_t lo = n[1], hi = n[2]; int64_t inner = r.next_int_bound(hi - lo + 1); return lo + r.next_int_bound(inner + 1); }
			case 3: { int64_t v = ip(n[1]); return v < n[2] ? n[2] : (v > n[3] ? n[3] : v); }
			case 4: {
				double g = F[n[1]] + gauss() * F[n[2]];
				int64_t v = (int64_t)std::floor(g);
				return v < n[3] ? n[3] : (v > n[4] ? n[4] : v);
			}
			case 5: {
				int cnt = n[1];
				int64_t tot = 0;
				for (int k = 0; k < cnt; k++) tot += n[2 + k * 2];
				if (tot <= 0) return 0;
				int64_t k2 = r.next_int_bound(tot);
				for (int k = 0; k < cnt; k++) {
					k2 -= n[2 + k * 2];
					if (k2 < 0) return ip(n[3 + k * 2]);
				}
				return 0;
			}
			case 6: {
				int64_t lo = n[1], hi = n[2], plateau = n[3];
				int64_t span = hi - lo;
				int64_t j = (span - plateau) / 2;
				int64_t kk = span - j;
				int64_t a = r.next_int_bound(kk + 1);
				int64_t b = r.next_int_bound(j + 1);
				return lo + a + b;
			}
		}
		return 0;
	}
	int64_t mth(int64_t a, int64_t b) { return a >= b ? a : r.next_int_bound(b - a + 1) + a; }
	int64_t hp(int o) {
		const int32_t *n = I + o;
		if (n[0] == 0) return n[1];
		int64_t i = n[1], j = n[2];
		if (i > j) return i;
		switch (n[0]) {
			case 1: return i + r.next_int_bound(j - i + 1);
			case 2: {
				int64_t plateau = n[3], k = j - i;
				if (plateau >= k) return i + r.next_int_bound(j - i + 1);
				int64_t l = (k - plateau) / 2, m = k - l;
				int64_t a = r.next_int_bound(m + 1);
				int64_t b = r.next_int_bound(l + 1);
				return i + a + b;
			}
			case 3: { int64_t inner = n[3]; int64_t l2 = r.next_int_bound(j - i - inner + 1); return r.next_int_bound(l2 + inner) + i; }
			case 4: {
				int64_t inner = n[3];
				int64_t k2 = mth(i + inner, j);
				int64_t l3 = mth(i, k2 - 1);
				return mth(i, l3 - 1 + inner);
			}
		}
		return i;
	}

	// ---------------------------------------------------------------- can_survive / predicates / rule tests / providers
	bool can_survive(int st, int x, int y, int z) {
		if (st <= 0) return true;
		int cat = st < (int)c.cat.size() ? c.cat[st] : 0;
		if (cat == 0) return true;
		int below = get(x, y - 1, z);
		int bb = c.below[below < 0 ? 0 : below];
		bool dirt = (bb & 1) != 0;
		switch (cat) {
			case 1: return dirt;
			case 2: return dirt || (bb & 8);
			case 3: return dirt || (bb & 2) || (bb & 4);
			case 4: return below > 0 && (flags(below) & c.F_OPAQUE);
			case 5: {
				if (!(bb & 16)) return false;
				static const int D[4][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
				for (int k = 0; k < 4; k++) {
					int s = get(x + D[k][0], y, z + D[k][1]);
					if (s > 0 && (flags(s) & c.F_COLLIDE)) return false;
				}
				return true;
			}
			case 6: {
				if (bb & 32) return true;
				if (!(dirt || (bb & 2))) return false;
				static const int D2[4][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
				for (int k = 0; k < 4; k++) {
					int s2 = get(x + D2[k][0], y - 1, z + D2[k][1]);
					if (s2 > 0 && (flags(s2) & (c.F_LIQUID | c.F_WATERLOGGED))) return true;
				}
				return false;
			}
			case 7: return below > 0 && (flags(below) & c.F_FULL_SHAPE);
			case 8: return below > 0 && (flags(below) & c.F_LIQUID);
			case 9: return below > 0 && (flags(below) & c.F_FULL_SHAPE) && !(bb & 64);
			case 10: return (bb & 128) != 0;   // nether roots / sprouts / fungi: #nylium, soul soil, #dirt, farmland
		}
		return true;
	}
	bool test(int o, int px, int py, int pz) {
		const int32_t *n = I + o;
		int x = px + n[1], y = py + n[2], z = pz + n[3];
		switch (n[0]) {
			case 0: return true;
			case 1: {
				int st = get(x, y, z);
				if (st < 0) return false;
				int bid = c.stblock[st];
				for (int k = 0; k < n[4]; k++) if (n[5 + k] == bid) return true;
				return false;
			}
			case 2: {
				int st = get(x, y, z);
				if (st <= 0) return false;
				int fl = flags(st);
				if (fl & c.F_LAVA) return n[4] != 0;
				if (fl & (c.F_LIQUID | c.F_WATERLOGGED)) return n[5] != 0;
				return false;
			}
			case 3: { int st = get(x, y, z); return st > 0 && (flags(st) & c.F_COLLIDE); }
			case 4: { int st = get(x, y, z); return st == 0 || (st > 0 && (flags(st) & c.F_REPLACEABLE)); }
			case 5: return can_survive(n[4], x, y, z);
			case 6: { int st = get(x, y, z); return st > 0 && (flags(st) & c.F_FULL_SHAPE); }
			case 7: return y >= c.gen_min_y && y < c.gen_min_y + c.gen_depth;
			case 8: return y >= n[4] && y <= n[5];
			case 9: for (int k = 0; k < n[4]; k++) if (!test(n[5 + k], px, py, pz)) return false; return true;
			case 10: for (int k = 0; k < n[4]; k++) if (test(n[5 + k], px, py, pz)) return true; return false;
			case 11: return !test(n[4], px, py, pz);
		}
		return true;
	}
	bool rule(int o, int st, int py) {
		const int32_t *n = I + o;
		switch (n[0]) {
			case 0: return true;
			case 1: case 3: {
				if (st < 0) return false;
				int bid = c.stblock[st];
				bool hit = false;
				for (int k = 0; k < n[1]; k++) if (n[2 + k] == bid) { hit = true; break; }
				if (!hit) return false;
				if (n[0] == 1) return true;
				return r.next_float() < F[n[2 + n[1]]];
			}
			case 2: return st == n[1];
			case 4: return py >= n[1] && py <= n[2];
			case 5: for (int k = 0; k < n[1]; k++) if (rule(n[2 + k], st, py)) return true; return false;
			case 6: for (int k = 0; k < n[1]; k++) if (!rule(n[2 + k], st, py)) return false; return true;
			case 7: return !rule(n[1], st, py);
		}
		return true;
	}
	int provide(int o, int x, int y, int z) {
		const int32_t *n = I + o;
		switch (n[0]) {
			case 0: return n[1];
			case 1: {
				int cnt = n[1];
				int64_t tot = 0;
				for (int k = 0; k < cnt; k++) tot += n[2 + k * 2];
				if (tot <= 0) return 0;
				int64_t k2 = r.next_int_bound(tot);
				for (int k = 0; k < cnt; k++) {
					k2 -= n[2 + k * 2];
					if (k2 < 0) return provide(n[3 + k * 2], x, y, z);
				}
				return 0;
			}
			case 2: {
				int cnt = n[1];
				for (int k = 0; k < cnt; k++) if (test(n[2 + k * 2], x, y, z)) return provide(n[3 + k * 2], x, y, z);
				int fb = n[2 + cnt * 2];
				return fb >= 0 ? provide(fb, x, y, z) : -1;
			}
			case 3: {
				int s = provide(n[1], x, y, z);
				int vmin = n[3], vmax = n[4], ns = n[5];
				int width = vmax - vmin + 1;
				const int32_t *t = n + 6;
				for (int k = 0; k < ns; k++, t += 2 + width) {
					if (t[0] != s) continue;
					if (!(s > 0 && t[1])) return s;
					int64_t v = ip(n[2]);
					if (v < vmin || v > vmax) return s;
					return t[2 + (v - vmin)];
				}
				return s;
			}
		}
		return 0;
	}

	// ---------------------------------------------------------------- placement chain (Features._chain / _sub)
	bool sub(int pf, int x, int y, int z) {
		if (pf < 0) return false;
		int nm = I[pf];
		if (nm == 0) return place(I[pf + 1], x, y, z);
		chain(pf, 0, x, y, z);
		return true;
	}
	void chain(int pf, int i, int x, int y, int z) {
		int nm = I[pf];
		if (i >= nm) { place(I[pf + 1 + nm], x, y, z); return; }
		const int32_t *m = I + I[pf + 1 + i];
		switch (m[0]) {
			case 1: { int64_t n = ip(m[1]); for (int64_t k = 0; k < n; k++) chain(pf, i + 1, x, y, z); return; }
			case 2: { int nx = x + (int)r.next_int_bound(16); int nz = z + (int)r.next_int_bound(16); chain(pf, i + 1, nx, y, nz); return; }
			case 3: if (r.next_float() < F[m[1]]) chain(pf, i + 1, x, y, z); return;
			case 4: { int ny = (int)hp(m[1]); chain(pf, i + 1, x, ny, z); return; }
			case 5: { int h = height(m[1], x, z); if (h > MIN_Y) chain(pf, i + 1, x, h, z); return; }
			case 6: { int b = biome(x, y, z); if (b >= 0 && b < nbio && bset[b]) chain(pf, i + 1, x, y, z); return; }
			case 7: { int fl = height(3, x, z); int ws = height(2, x, z); if (ws - fl <= m[1]) chain(pf, i + 1, x, y, z); return; }
			case 8: if (test(m[1], x, y, z)) chain(pf, i + 1, x, y, z); return;
			case 9: { int ox = (int)ip(m[1]); int oy = (int)ip(m[2]); int oz = (int)ip(m[3]); chain(pf, i + 1, x + ox, y + oy, z + oz); return; }
			case 10: { int rx = (int)ip(m[1]); int ry = (int)ip(m[2]); int rz = (int)ip(m[1]); chain(pf, i + 1, x + rx, y + ry, z + rz); return; }
			case 11: {
				int dy = m[1], steps = m[2];
				int qy = y;
				if (test(m[3], x, qy, z)) { chain(pf, i + 1, x, qy, z); return; }
				for (int s = 0; s < steps; s++) {
					qy += dy;
					if (qy < MIN_Y || qy >= MAX_Y || !test(m[4], x, qy, z)) return;
					if (test(m[3], x, qy, z)) { chain(pf, i + 1, x, qy, z); return; }
				}
				return;
			}
			case 12: {
				int h2 = height(m[1], x, z);
				int64_t lo = m[2] ? (int64_t)h2 + m[3] : (int64_t)-2147483648LL;
				int64_t hi = m[4] ? (int64_t)h2 + m[5] : (int64_t)2147483647LL;
				if (y >= lo && y <= hi) chain(pf, i + 1, x, y, z);
				return;
			}
			case 13: if (r.next_float() < F[m[1]]) chain(pf, i + 1, x, y, z); return;
			case 14: {
				double d = simplex(x / 200.0, z / 200.0);
				int n2 = d < F[m[1]] ? m[2] : m[3];
				for (int k = 0; k < n2; k++) chain(pf, i + 1, x, y, z);
				return;
			}
			case 15: {
				double fac = F[m[1]];
				double d2 = simplex(x / fac, z / fac);
				int n3 = (int)std::ceil((d2 + F[m[2]]) * (double)m[3]);
				for (int k = 0; k < (n3 > 0 ? n3 : 0); k++) chain(pf, i + 1, x, y, z);
				return;
			}
			case 16: {
				// count_on_every_layer (Features._chain / _layer_y): the count provider is sampled on every loop check
				std::vector<int> found;
				int layer = 0;
				bool more = true;
				while (more) {
					more = false;
					int64_t jn = 0;
					while (jn < ip(m[1])) {
						int x2 = x + (int)r.next_int_bound(16);
						int z2 = z + (int)r.next_int_bound(16);
						int top = height(m[2], x2, z2);
						int y2 = layer_y(x2, top, z2, layer, m[3]);
						if (y2 != INT32_MAX) { found.push_back(x2); found.push_back(y2); found.push_back(z2); more = true; }
						jn++;
					}
					layer++;
				}
				for (size_t q = 0; q + 2 < found.size(); q += 3) chain(pf, i + 1, found[q], found[q + 1], found[q + 2]);
				return;
			}
			default: chain(pf, i + 1, x, y, z); return;
		}
	}
	int layer_y(int x, int y, int z, int target, int bed) {
		int nn = 0;
		int prev = get(x, y, z);
		for (int j = y; j >= c.gen_min_y + 1; j--) {
			int cur = get(x, j - 1, z);
			bool ce = cur <= 0 || (flags(cur) & c.F_LIQUID);
			bool pe = prev <= 0 || (flags(prev) & c.F_LIQUID);
			if (!ce && pe && c.stblock[cur] != bed) {
				if (nn == target) return j;
				nn++;
			}
			prev = cur;
		}
		return INT32_MAX;
	}

	// ---------------------------------------------------------------- configured features (Features.place_feature)
	bool place(int o, int x, int y, int z) {
		const int32_t *n = I + o;
		switch (n[0]) {
			case 0: return false;
			case 1: return ore(n, x, y, z);
			case 2: return scattered(n, x, y, z);
			case 3: {
				int st = provide(n[1], x, y, z);
				if (st < 0 || !can_survive(st, x, y, z)) return false;
				int hu = st < (int)c.half_up.size() ? c.half_up[st] : -1;
				if (hu >= 0) {
					if (get(x, y + 1, z) != 0) return false;
					set(x, y, z, st, W_AIR);
					set(x, y + 1, z, hu, W_AIR);
					return true;
				}
				int cur = get(x, y, z);
				if (cur > 0 && (flags(cur) & c.F_LIQUID) && st < (int)c.wl.size() && c.wl[st] >= 0) st = c.wl[st];
				set(x, y, z, st, W_REPLACEABLE);
				return true;
			}
			case 4: {
				int cnt = n[1];
				for (int k = 0; k < cnt; k++) if (r.next_float() < F[n[2 + k * 2]]) return sub(n[3 + k * 2], x, y, z);
				return sub(n[2 + cnt * 2], x, y, z);
			}
			case 5: {
				int cnt = n[1];
				int64_t tot = 0;
				for (int k = 0; k < cnt; k++) tot += n[2 + k * 2];
				if (tot <= 0) return false;
				int64_t k2 = r.next_int_bound(tot);
				for (int k = 0; k < cnt; k++) {
					k2 -= n[2 + k * 2];
					if (k2 < 0) return sub(n[3 + k * 2], x, y, z);
				}
				return false;
			}
			case 6: {
				int cnt = n[1];
				if (cnt == 0) return false;
				return sub(n[2 + r.next_int_bound(cnt)], x, y, z);
			}
			case 7: { bool bl = r.next_bool(); return sub(bl ? n[1] : n[2], x, y, z); }
			case 8: {
				for (int k = 0; k < n[1]; k++) if (!sub(n[2 + k], x, y, z)) return false;
				return true;
			}
			case 9: return column(n, x, y, z);
			case 10: return disk(n, x, y, z);
			case 11: return veg_patch(n, x, y, z);
			case 12: {
				if (get(x, y, z) != 0) return false;
				static const int D[6][3] = {{0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1}, {-1, 0, 0}, {1, 0, 0}};
				for (int k = 0; k < 6; k++) {
					int s = get(x + D[k][0], y + D[k][1], z + D[k][2]);
					if (s > 0 && (flags(s) & c.F_FULL_SHAPE) && n[1 + k] >= 0) {
						set(x, y, z, n[1 + k], W_AIR);
						return true;
					}
				}
				return false;
			}
			case 14: return underwater_magma(n, x, y, z);
			case 15: {
				int s0 = get(x, y, z);
				bool airish = s0 == 0 || (s0 > 0 && s0 < (int)c.airn.size() && c.airn[s0]);
				if (!airish) return false;
				static const int DV[5][3] = {{0, 0, -1}, {1, 0, 0}, {0, 0, 1}, {-1, 0, 0}, {0, 1, 0}};
				for (int k = 0; k < 5; k++) {
					int s = get(x + DV[k][0], y + DV[k][1], z + DV[k][2]);
					if (s > 0 && (flags(s) & c.F_FULL_SHAPE)) { set(x, y, z, n[1 + k], W_FORCE); return true; }
				}
				return false;
			}
			case 16: return spring(n, x, y, z);
			case 17: return dungeon(n, x, y, z);
			case 18: return true;
			case 19: return speleothem(n, x, y, z);
			case 20: return lake(n, x, y, z);
			case 21: return tree(n, x, y, z);
			case 22: return mushroom(n, x, y, z);
			case 23: return fallen(n, x, y, z);
			case 24: return cluster(n, x, y, z);
			case 25: return replace_blobs(n, x, y, z);
			case 26: return delta(n, x, y, z);
			case 27: return columns(n, x, y, z);
			case 28: return pillar(n, x, y, z);
			case 29: return patchy(n, x, y, z);
			case 30: return neighbor_spread(n, x, y, z);
			case 31: return fungus(n, x, y, z);
			case 32: return sculk_patch(n, x, y, z);
			case 13: {
				for (int k2 = 0; k2 < 12; k2++) {
					int qx = x + (int)r.next_int_bound(5) - 2;
					int qy = y + (int)r.next_int_bound(2);
					int qz = z + (int)r.next_int_bound(5) - 2;
					if (get(qx, qy, qz) == 0 && get(qx, qy - 1, qz) > 0) {
						int st = provide(n[1], qx, qy, qz);
						set(qx, qy, qz, st, W_AIR);
					}
				}
				return true;
			}
		}
		return false;
	}
	bool valid_id(const int32_t *ids, int nids, int st) const {
		if (st <= 0) return false;
		int b = c.stblock[st];
		for (int k = 0; k < nids; k++) if (ids[k] == b) return true;
		return false;
	}
	bool spring(const int32_t *n, int x, int y, int z) {
		int below = n[1], rock_need = n[2], hole_need = n[3], out = n[4], nv = n[5];
		const int32_t *ids = n + 6;
		int up = get(x, y + 1, z);
		if (!valid_id(ids, nv, up)) return false;
		int dn = get(x, y - 1, z);
		if (below && !valid_id(ids, nv, dn)) return false;
		int cur = get(x, y, z);
		if (cur != 0 && !valid_id(ids, nv, cur)) return false;
		int rock = 0, hole = 0;
		static const int D[5][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}, {0, -1, 0}};
		for (int k = 0; k < 5; k++) {
			int s = get(x + D[k][0], y + D[k][1], z + D[k][2]);
			if (valid_id(ids, nv, s)) rock++;
			else if (s == 0) hole++;
		}
		if (rock == rock_need && hole == hole_need) { set(x, y, z, out, W_FORCE); return true; }
		return false;
	}
	bool underwater_magma(const int32_t *n, int x, int y, int z) {
		int range = n[1], rad = n[2];
		double prob = F[n[3]];
		int water = n[4], magma = n[5];
		int py = y;
		bool found = false;
		for (int i = 0; i < range; i++) {
			int s = get(x, py, z);
			if (s > 0 && c.stblock[s] != water && (flags(s) & c.F_COLLIDE)) { found = true; break; }
			py--;
		}
		if (!found) return false;
		static const int H[4][2] = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}};
		bool any = false;
		for (int dx = -rad; dx <= rad; dx++)
			for (int dy = -rad; dy <= rad; dy++)
				for (int dz = -rad; dz <= rad; dz++) {
					int qx = x + dx, qy = py + dy, qz = z + dz;
					int s2 = get(qx, qy, qz);
					if (s2 <= 0 || !(flags(s2) & c.F_COLLIDE)) continue;
					int above = get(qx, qy + 1, qz);
					if (above <= 0 || c.stblock[above] != water) continue;
					bool walled = true;
					for (int k = 0; k < 4; k++) {
						int nb = get(qx + H[k][0], qy, qz + H[k][1]);
						if (nb <= 0 || !(flags(nb) & c.F_COLLIDE)) { walled = false; break; }
					}
					if (walled && r.next_float() < prob) { set(qx, qy, qz, magma, W_FORCE); any = true; }
				}
		return any;
	}
	bool dungeon(const int32_t *n, int px, int py, int pz) {
		int cobble = n[1], mossy = n[2], spawner = n[3], chest = n[4];
		int rx = (int)r.next_int_bound(2) + 2;
		int rz = (int)r.next_int_bound(2) + 2;
		int openings = 0;
		for (int x = -rx - 1; x < rx + 2; x++)
			for (int y = -1; y < 5; y++)
				for (int z = -rz - 1; z < rz + 2; z++) {
					int st = get(px + x, py + y, pz + z);
					bool solid = st > 0 && (flags(st) & c.F_COLLIDE);
					if ((y == -1 || y == 4) && !solid) return false;
					if ((std::abs(x) == rx + 1 || std::abs(z) == rz + 1) && y == 0 && st == 0 && get(px + x, py + 1, pz + z) == 0) openings++;
				}
		if (openings < 1 || openings > 5) return false;
		for (int x = -rx - 1; x < rx + 2; x++)
			for (int y = 3; y > -2; y--)
				for (int z = -rz - 1; z < rz + 2; z++) {
					int qx = px + x, qy = py + y, qz = pz + z;
					bool wall = std::abs(x) == rx + 1 || y == -1 || std::abs(z) == rz + 1;
					if (!wall) set(qx, qy, qz, 0, W_FORCE);
					else if (y >= 0 && get(qx, qy - 1, qz) <= 0) set(qx, qy, qz, 0, W_FORCE);
					else if (get(qx, qy, qz) > 0) {
						int st = cobble;
						if (y == -1 && r.next_int_bound(4) != 0) st = mossy;
						set(qx, qy, qz, st, W_FORCE);
					}
				}
		set(px, py, pz, spawner, W_FORCE);
		for (int k = 0; k < 2; k++) {
			int ox = (int)r.next_int_bound(rx * 2 + 1) - rx;
			int oz = (int)r.next_int_bound(rz * 2 + 1) - rz;
			int qx = px + ox, qz = pz + oz;
			if (get(qx, py, qz) == 0) {
				set(qx, py, qz, chest, W_AIR);
				int64_t seed = r.next_long();
				bes.push_back(0); bes.push_back(qx); bes.push_back(py); bes.push_back(qz); bes.push_back(seed);
			}
		}
		int64_t mob = r.next_int_bound(4);
		bes.push_back(1); bes.push_back(px); bes.push_back(py); bes.push_back(pz); bes.push_back(mob);
		return true;
	}
	// FeaturesCave._speleothem (PointedDripstoneFeature); node: [19, base, base_b, water_b, cave_air_b, void_air_b,
	// F dir_spread, F r2, F r3, F taller, ps x20 (up/down x tip_merge,tip,frustum,middle,base x dry/wet), n_repl, ids]
	int bid(int st) const { return st > 0 ? c.stblock[st] : 0; }
	bool sp_repl(const int32_t *n, int b) const {
		int nr = n[30];
		for (int k = 0; k < nr; k++) if (n[31 + k] == b) return true;
		return false;
	}
	bool sp_ew(const int32_t *n, int st) const { int b = bid(st); return b == 0 || b == n[4] || b == n[5] || b == n[3]; }
	bool sp_base(const int32_t *n, int st) const { int b = bid(st); return b != 0 && (b == n[2] || sp_repl(n, b)); }
	void sp_place_base(const int32_t *n, int x, int y, int z) { if (sp_repl(n, bid(get(x, y, z)))) set(x, y, z, n[1], W_FORCE); }
	bool speleothem(const int32_t *n, int x, int y, int z) {
		bool can_up = sp_base(n, get(x, y + 1, z));
		bool can_down = sp_base(n, get(x, y - 1, z));
		int dir;
		if (can_up && can_down) dir = r.next_bool() ? -1 : 1;
		else if (can_up) dir = -1;
		else if (can_down) dir = 1;
		else return false;
		int rx = x, ry = y - dir, rz = z;
		sp_place_base(n, rx, ry, rz);
		static const int H[4][3] = {{0, 0, -1}, {1, 0, 0}, {0, 0, 1}, {-1, 0, 0}};
		static const int D6[6][3] = {{0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1}, {-1, 0, 0}, {1, 0, 0}};
		for (int k = 0; k < 4; k++) {
			if (r.next_float() > F[n[6]]) continue;
			int x2 = rx + H[k][0], y2 = ry + H[k][1], z2 = rz + H[k][2];
			sp_place_base(n, x2, y2, z2);
			if (r.next_float() > F[n[7]]) continue;
			int d1 = (int)r.next_int_bound(6);
			int x3 = x2 + D6[d1][0], y3 = y2 + D6[d1][1], z3 = z2 + D6[d1][2];
			sp_place_base(n, x3, y3, z3);
			if (r.next_float() > F[n[8]]) continue;
			int d2 = (int)r.next_int_bound(6);
			sp_place_base(n, x3 + D6[d2][0], y3 + D6[d2][1], z3 + D6[d2][2]);
		}
		int h = 1;
		if (r.next_float() < F[n[9]] && sp_ew(n, get(x, y + dir, z))) h = 2;
		// DripstoneUtils.growPointedDripstone (merge = false)
		if (h <= 0 || !sp_base(n, get(x, y - dir, z))) return true;
		int seq[4];
		int ns = 0;
		if (h >= 3) seq[ns++] = 4;
		if (h >= 2) seq[ns++] = 2;
		seq[ns++] = 1;
		int qy = y;
		for (int k = 0; k < ns; k++) {
			bool wet = bid(get(x, qy, z)) == n[3];
			int st = n[10 + (dir > 0 ? 0 : 10) + seq[k] * 2 + (wet ? 1 : 0)];
			set(x, qy, z, st, W_FORCE);
			qy += dir;
		}
		return true;
	}
	// ---------------------------------------------------------------- speleothem_cluster (FeaturesCave._cluster)
	double fp(int o) {
		const int32_t *q = I + o;
		switch (q[0]) {
			case 1: { double lo = F[q[1]]; double n1 = r.next_float(); return lo + n1 * (F[q[2]] - lo); }
			case 2: {
				double g = F[q[1]] + gauss() * F[q[2]];
				double mn = F[q[3]], mx = F[q[4]];
				return g < mn ? mn : (g > mx ? mx : g);
			}
			case 3: {
				double mn = F[q[1]];
				double rg = F[q[2]] - mn;
				double slope = (rg - F[q[3]]) / 2.0;
				double a = r.next_float();
				double v = mn + a * (rg - slope);
				double b = r.next_float();
				return v + b * slope;
			}
		}
		return F[q[1]];
	}
	static double clamped_map(double v, double a, double b, double lo, double hi) {
		double tt;
		if (b != a) { tt = (v - a) / (b - a); tt = tt < 0.0 ? 0.0 : (tt > 1.0 ? 1.0 : tt); }
		else tt = 1.0;
		return lo + tt * (hi - lo);
	}
	bool sp_stone(const int32_t *n, int e, int b) const {
		int ns = n[e + 14];
		for (int k = 0; k < ns; k++) if (n[e + 15 + k] == b) return true;
		return false;
	}
	bool sp_adj_water_ok(const int32_t *n, int e, int st) const { int b = bid(st); return sp_stone(n, e, b) || b == n[3]; }
	bool sp_can_pool(const int32_t *n, int e, int x, int y, int z) {
		int b = bid(get(x, y, z));
		if (b == n[3] || b == n[2] || b == n[e + 1]) return false;
		if (bid(get(x, y + 1, z)) == n[3]) return false;
		static const int H[4][2] = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}};
		for (int k = 0; k < 4; k++) if (!sp_adj_water_ok(n, e, get(x + H[k][0], y, z + H[k][1]))) return false;
		return sp_adj_water_ok(n, e, get(x, y - 1, z));
	}
	// DripstoneUtils.growPointedDripstone (merge variant used by clusters)
	void sp_grow(const int32_t *n, int x, int y, int z, int dir, int h, bool merge) {
		if (h <= 0 || !sp_base(n, get(x, y - dir, z))) return;
		std::vector<int> seq;
		if (h >= 3) { seq.push_back(4); for (int i = 0; i < h - 3; i++) seq.push_back(3); }
		if (h >= 2) seq.push_back(2);
		seq.push_back(merge ? 0 : 1);
		int qy = y;
		for (int th : seq) {
			bool wet = bid(get(x, qy, z)) == n[3];
			set(x, qy, z, n[10 + (dir > 0 ? 0 : 10) + th * 2 + (wet ? 1 : 0)], W_FORCE);
			qy += dir;
		}
	}
	int sp_drip_height(const int32_t *n, int e, int dx, int dz, double dens, int max_h) {
		if (r.next_float() > dens) return 0;
		double mean = clamped_map((double)(std::abs(dx) + std::abs(dz)), 0.0, F[n[e + 12]], max_h / 2.0, 0.0);
		double v = mean + gauss() * F[n[e + 13]];
		v = v < 0.0 ? 0.0 : (v > (double)max_h ? (double)max_h : v);
		return (int)v;
	}
	bool cluster(const int32_t *n, int px, int py, int pz) {
		int e = 31 + n[30];   // extras: lava_b, pointed_b, water_state, height_ip, wet_fp, dens_fp, radius_ip, F edge, F far,
		                      // scan, thick_ip, dev, F hbias, F hdev, n_stone, stone...
		if (!sp_ew(n, get(px, py, pz))) return false;
		int height = (int)ip(n[e + 3]);
		double wet = fp(n[e + 4]);
		double dens = fp(n[e + 5]);
		int rx = (int)ip(n[e + 6]);
		int rz = (int)ip(n[e + 6]);
		double edge_max = F[n[e + 7]], chance_far = F[n[e + 8]];
		for (int dx = -rx; dx < rx + 1; dx++)
			for (int dz = -rz; dz < rz + 1; dz++) {
				int k = std::min(rx - std::abs(dx), rz - std::abs(dz));
				double chv = clamped_map((double)k, 0.0, edge_max, chance_far, 1.0);
				cluster_column(n, e, px + dx, py, pz + dz, dx, dz, wet, chv, height, dens);
			}
		return true;
	}
	void cluster_column(const int32_t *n, int e, int qx, int qy, int qz, int dx, int dz, double wet, double chance, int height, double dens) {
		if (!sp_ew(n, get(qx, qy, qz))) return;
		int rng = n[e + 9];
		int fy_s = qy, cy_s = qy;
		bool has_floor = false, has_ceil = false;
		for (int pass = 0; pass < 2; pass++) {
			int dir = pass == 0 ? -1 : 1;
			int y = qy, i = 1;
			while (i < rng) { y += dir; if (!sp_ew(n, get(qx, y, qz))) break; i++; }
			int st = get(qx, y, qz);
			bool edge = !sp_ew(n, st);
			if (pass == 0) { has_floor = edge && y != qy; fy_s = y; }
			else { has_ceil = edge && y != qy; cy_s = y; }
		}
		int floor_y = fy_s, ceil_y = cy_s;
		if (!has_ceil && !has_floor) return;
		int col_h = (has_ceil && has_floor) ? ceil_y - floor_y - 1 : -1;
		bool pool = r.next_float() < wet;
		bool f_has = has_floor;
		int f_y = floor_y;
		if (pool && has_floor && sp_can_pool(n, e, qx, floor_y, qz)) { set(qx, floor_y, qz, n[e + 2], W_FORCE); f_y = floor_y - 1; }
		int lava = n[e + 0];
		int ch = 0;
		if (has_ceil && r.next_double() < chance && bid(get(qx, ceil_y, qz)) != lava) {
			int th = (int)ip(n[e + 10]);
			int my = ceil_y;
			for (int i = 0; i < th; i++) {
				if (!sp_repl(n, bid(get(qx, my, qz)))) break;
				set(qx, my, qz, n[1], W_FORCE);
				my += 1;
			}
			int mh = f_has ? std::min(height, ceil_y - f_y) : height;
			ch = sp_drip_height(n, e, dx, dz, dens, mh);
		}
		int fh = 0;
		if (f_has && r.next_double() < chance && bid(get(qx, f_y, qz)) != lava) {
			int th2 = (int)ip(n[e + 10]);
			int my = f_y;
			for (int i = 0; i < th2; i++) {
				if (!sp_repl(n, bid(get(qx, my, qz)))) break;
				set(qx, my, qz, n[1], W_FORCE);
				my -= 1;
			}
			if (has_ceil) {
				int dev = n[e + 11];
				fh = std::max(0, ch + (int)mth(-dev, dev));
			} else fh = sp_drip_height(n, e, dx, dz, dens, height);
		}
		int ch2 = ch, fh2 = fh;
		if (has_ceil && f_has && ceil_y - ch <= f_y + fh) {
			int lo = std::max(ceil_y - ch, f_y + 1);
			int hi = std::min(f_y + fh, ceil_y - 1);
			int mid = (int)mth(lo, hi + 1);
			ch2 = ceil_y - mid;
			fh2 = mid - 1 - f_y;
		}
		bool merge = r.next_bool() && ch2 > 0 && fh2 > 0 && col_h >= 0 && ch2 + fh2 == col_h;
		if (has_ceil) sp_grow(n, qx, ceil_y - 1, qz, -1, ch2, merge);
		if (f_has) sp_grow(n, qx, f_y + 1, qz, 1, fh2, merge);
	}

	// ---------------------------------------------------------------- trees (scripts/world/trees.gd)
	struct V3 { int x, y, z; };
	std::vector<V3> logs, leaves;
	// Godot SortArray (core/templates/sort_array.h) with comparator a.y < b.y: the order GDScript's
	// Array.sort_custom gives equal-height logs/leaves (introsort, threshold 16, heap fallback, insertion sort).
	struct GSort {
		static bool cmp(const V3 &a, const V3 &b) { return a.y < b.y; }
		static const V3 &median3(const V3 &a, const V3 &b, const V3 &c) {
			if (cmp(a, b)) { if (cmp(b, c)) return b; else if (cmp(a, c)) return c; else return a; }
			else if (cmp(a, c)) return a;
			else if (cmp(b, c)) return c;
			else return b;
		}
		static int64_t bitlog(int64_t n) { int64_t k; for (k = 0; n != 1; n >>= 1) ++k; return k; }
		static void push_heap(int64_t first, int64_t hole, int64_t top, V3 value, V3 *a) {
			int64_t parent = (hole - 1) / 2;
			while (hole > top && cmp(a[first + parent], value)) { a[first + hole] = a[first + parent]; hole = parent; parent = (hole - 1) / 2; }
			a[first + hole] = value;
		}
		static void adjust_heap(int64_t first, int64_t hole, int64_t len, V3 value, V3 *a) {
			int64_t top = hole;
			int64_t second = 2 * hole + 2;
			while (second < len) {
				if (cmp(a[first + second], a[first + (second - 1)])) second--;
				a[first + hole] = a[first + second];
				hole = second;
				second = 2 * (second + 1);
			}
			if (second == len) { a[first + hole] = a[first + (second - 1)]; hole = second - 1; }
			push_heap(first, hole, top, value, a);
		}
		static void pop_heap(int64_t first, int64_t last, int64_t result, V3 value, V3 *a) { a[result] = a[first]; adjust_heap(first, 0, last - first, value, a); }
		static void pop_heap(int64_t first, int64_t last, V3 *a) { pop_heap(first, last - 1, last - 1, a[last - 1], a); }
		static void make_heap(int64_t first, int64_t last, V3 *a) {
			if (last - first < 2) return;
			int64_t len = last - first;
			int64_t parent = (len - 2) / 2;
			while (true) { adjust_heap(first, parent, len, a[first + parent], a); if (parent == 0) return; parent--; }
		}
		static void sort_heap(int64_t first, int64_t last, V3 *a) { while (last - first > 1) pop_heap(first, last--, a); }
		static void partial_sort(int64_t first, int64_t last, int64_t middle, V3 *a) {
			make_heap(first, middle, a);
			for (int64_t i = middle; i < last; i++) if (cmp(a[i], a[first])) pop_heap(first, middle, i, a[i], a);
			sort_heap(first, middle, a);
		}
		static int64_t partitioner(int64_t first, int64_t last, V3 pivot, V3 *a) {
			while (true) {
				while (cmp(a[first], pivot)) first++;
				last--;
				while (cmp(pivot, a[last])) last--;
				if (!(first < last)) return first;
				std::swap(a[first], a[last]);
				first++;
			}
		}
		static void introsort(int64_t first, int64_t last, V3 *a, int64_t depth) {
			while (last - first > 16) {
				if (depth == 0) { partial_sort(first, last, last, a); return; }
				depth--;
				int64_t cut = partitioner(first, last, median3(a[first], a[first + (last - first) / 2], a[last - 1]), a);
				introsort(cut, last, a, depth);
				last = cut;
			}
		}
		static void unguarded_linear_insert(int64_t last, V3 value, V3 *a) {
			int64_t next = last - 1;
			while (cmp(value, a[next])) { a[last] = a[next]; last = next; next--; }
			a[last] = value;
		}
		static void linear_insert(int64_t first, int64_t last, V3 *a) {
			V3 val = a[last];
			if (cmp(val, a[first])) { for (int64_t i = last; i > first; i--) a[i] = a[i - 1]; a[first] = val; }
			else unguarded_linear_insert(last, val, a);
		}
		static void insertion_sort(int64_t first, int64_t last, V3 *a) {
			if (first == last) return;
			for (int64_t i = first + 1; i != last; i++) linear_insert(first, i, a);
		}
		static void unguarded_insertion_sort(int64_t first, int64_t last, V3 *a) { for (int64_t i = first; i != last; i++) unguarded_linear_insert(i, a[i], a); }
		static void sort(std::vector<V3> &v) {
			int64_t n = (int64_t)v.size();
			if (n == 0) return;
			V3 *a = v.data();
			introsort(0, n, a, bitlog(n) * 2);
			if (n > 16) { insertion_sort(0, 16, a); unguarded_insertion_sort(16, n, a); }
			else insertion_sort(0, n, a);
		}
	};
	int leaves_n = 0, leaves_min_y = 0;
	bool tvalid(int x, int y, int z) const {
		int st = get(x, y, z);
		if (st == 0) return true;
		if (st < 0) return false;
		int fl = flags(st);
		return (fl & (c.F_REPLACEABLE | c.F_LEAVES)) && !(fl & c.F_LIQUID);
	}
	// Trees._log; axis 0 y, 1 x, 2 z
	void tlog(const int32_t *n, int pv, const int32_t *axt, int na, int x, int y, int z, int axis) {
		if (!tvalid(x, y, z)) {
			int st = get(x, y, z);
			if (st > 0 && !(st < (int)c.logn.size() && c.logn[st])) return;
		}
		int s = provide(pv, x, y, z);
		if (s > 0) {
			for (int k = 0; k < na; k++) if (axt[k * 4] == s) { s = axt[k * 4 + 1 + axis]; break; }
		}
		set(x, y, z, s, W_FORCE);
		logs.push_back(V3{x, y, z});
	}
	void tleaf(int fpv, int x, int y, int z) {
		if (tvalid(x, y, z)) {
			set(x, y, z, provide(fpv, x, y, z), W_REPLACEABLE);
			if (leaves_n == 0 || y < leaves_min_y) leaves_min_y = y;
			leaves_n++;
			leaves.push_back(V3{x, y, z});
		}
	}
	// Trees._skip; kind: foliage type id
	bool tskip(int kind, int x, int y, int z, int rng) {
		switch (kind) {
			case 0: case 1: case 2: return x == rng && z == rng && (r.next_int_bound(2) == 0 || y == 0);
			case 3: case 4: return x == rng && z == rng && rng > 0;
			case 5: return x + z >= 7 || x * x + z * z > rng * rng;   // Java MegaPineFoliagePlacer.shouldSkipLocation
			case 6: if (y == 0) return (x > 1 || z > 1) && x != 0 && z != 0; return x == rng && z == rng && rng > 0;
			case 7: return (x + 0.5) * (x + 0.5) + (z + 0.5) * (z + 0.5) > (double)rng * rng;
			case 8: return x + z >= 7 || x * x + z * z > rng * rng;
			case 9: return y == 0 && x == rng && z == rng;
		}
		return false;
	}
	void trow(int fpv, int cx, int cy, int cz, int rng, int ly, bool dbl, int kind) {
		int i = dbl ? 1 : 0;
		for (int j = -rng; j < rng + 1 + i; j++)
			for (int k = -rng; k < rng + 1 + i; k++) {
				int ax = std::abs(j), az = std::abs(k);
				if (dbl) { ax = std::min(std::abs(j), std::abs(j - 1)); az = std::min(std::abs(k), std::abs(k - 1)); }
				if (kind == 9 && ly == 0 && dbl && (j == -rng || j >= rng) && (k == -rng || k >= rng)) continue;
				if (kind == 9) {
					if ((ly == -1 && !dbl && ax == rng && az == rng) || (ly == 1 && ax + az > rng * 2 - 2)) continue;
					tleaf(fpv, cx + j, cy + ly, cz + k);
					continue;
				}
				if (tskip(kind, ax, ly, az, rng)) continue;
				tleaf(fpv, cx + j, cy + ly, cz + k);
			}
	}
	void tfoliage(const int32_t *n, int fk, int ax, int ay, int az, int ro, bool dbl, int fh, int radius, int offset) {
		int fpv = n[12];
		switch (fk) {
			case 0: case 1:
				for (int l = offset; l > offset - fh - 1; l--) trow(fpv, ax, ay, az, std::max(radius + ro - 1 - (int)(l / 2.0), 0), l, dbl, fk);
				break;
			case 2:
				for (int l = offset; l > offset - fh - 1; l--) trow(fpv, ax, ay, az, std::max(radius + ro - 1 - l, 0), l, dbl, 2);
				break;
			case 3: {
				int i = (int)r.next_int_bound(2), j = 1, k = 0;
				for (int l = offset; l > -fh - 1; l--) {
					trow(fpv, ax, ay, az, i, l, dbl, 3);
					if (i >= j) { i = k; k = 1; j = std::min(j + 1, radius + ro); }
					else i++;
				}
				break;
			}
			case 4: {
				int i2 = 0;
				for (int l = offset; l > offset - fh - 1; l--) {
					trow(fpv, ax, ay, az, i2, l, dbl, 4);
					if (i2 >= 1 && l == offset - fh + 1) i2--;
					else if (i2 < radius + ro) i2++;
				}
				break;
			}
			case 5: {
				// Java MegaPineFoliagePlacer.createFoliage (float32 radius growth, +1 on even rows when it repeats)
				int y = ay, prev = 0;
				for (int l = y - fh + offset; l < y + offset + 1; l++) {
					int k = y - l;
					volatile float q = (float)k / (float)fh;
					volatile float g = q * 3.5f;
					int sm = radius + ro + (int)std::floor(g);
					int rr = (k > 0 && sm == prev && (l & 1) == 0) ? sm + 1 : sm;
					trow(fpv, ax, l, az, rr, 0, dbl, 5);
					prev = sm;
				}
				break;
			}
			case 6: {
				int by = ay + offset;
				trow(fpv, ax, by, az, radius + ro, -1 - fh, dbl, 6);
				trow(fpv, ax, by, az, radius - 1, -fh, dbl, 6);
				trow(fpv, ax, by, az, radius + ro - 1, 0, dbl, 6);
				break;
			}
			case 7:
				for (int l = offset; l > offset - fh - 1; l--) trow(fpv, ax, ay, az, radius + ((l != offset && l != offset - fh) ? 1 : 0), l, dbl, 7);
				break;
			case 8: {
				int cnt = dbl ? fh : 1 + (int)r.next_int_bound(2);
				for (int l = offset; l > offset - cnt - 1; l--) trow(fpv, ax, ay, az, radius + ro + 1 - l, l, dbl, 8);
				break;
			}
			case 9: {
				int by = ay + offset;
				if (dbl) {
					trow(fpv, ax, by, az, radius + 2, -1, true, 9);
					trow(fpv, ax, by, az, radius + 3, 0, true, 9);
					trow(fpv, ax, by, az, radius + 2, 1, true, 9);
					if (r.next_bool()) trow(fpv, ax, by, az, radius, 2, true, 9);
				} else {
					trow(fpv, ax, by, az, radius + 2, -1, false, 9);
					trow(fpv, ax, by, az, radius + 1, 0, false, 9);
				}
				break;
			}
			case 10: {
				int cnt2 = n[14];
				for (int q = 0; q < cnt2; q++) {
					int qx = ax + (int)r.next_int_bound(radius * 2 + 1) - radius;
					int qy = ay + (int)r.next_int_bound(fh + 1) - fh / 2;
					int qz = az + (int)r.next_int_bound(radius * 2 + 1) - radius;
					tleaf(fpv, qx, qy, qz);
				}
				break;
			}
			default:
				for (int l = offset; l > offset - 3; l--) trow(fpv, ax, ay, az, std::max(radius - (int)(l / 2.0), 0), l, dbl, 0);
		}
	}
	bool tair(int x, int y, int z) const { return get(x, y, z) == 0; }
	void tdecorators(const int32_t *n, int nd_off) {
		int nd = n[nd_off];
		GSort::sort(logs);
		GSort::sort(leaves);
		static const int HD[4][3] = {{-1, 0, 0}, {1, 0, 0}, {0, 0, -1}, {0, 0, 1}};
		for (int di = 0; di < nd; di++) {
			const int32_t *d = I + n[nd_off + 1 + di];
			double prob = F[d[1]];
			switch (d[0]) {
				case 1:
					for (const V3 &q : logs)
						for (int k = 0; k < 4; k++) {
							if (r.next_int_bound(3) > 0) continue;
							int nx = q.x + HD[k][0], ny = q.y, nz = q.z + HD[k][2];
							if (tair(nx, ny, nz) && d[2 + k] >= 0) set(nx, ny, nz, d[2 + k], W_AIR);
						}
					break;
				case 2: {
					if (r.next_float() >= prob || logs.empty()) break;
					int y0 = logs[0].y;
					for (const V3 &q : logs) {
						if (q.y - y0 > 2) continue;
						for (int k = 0; k < 4; k++) {
							if (r.next_float() <= 0.25) {
								int nx = q.x + HD[k][0], ny = q.y, nz = q.z + HD[k][2];
								if (d[2] > 0 && tair(nx, ny, nz)) {
									int age = (int)r.next_int_bound(3);
									set(nx, ny, nz, d[2 + age * 4 + k], W_AIR);
								}
							}
						}
					}
					break;
				}
				case 3: {
					if (r.next_float() >= prob || logs.empty()) break;
					int hy;
					if (leaves_n > 0) hy = std::max(leaves_min_y - 1, logs[0].y + 1);
					else { int a = logs[0].y + 1 + (int)r.next_int_bound(3); hy = std::min(a, logs.back().y); }
					std::vector<V3> cands;
					static const int B3[3][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 0, 1}};
					for (const V3 &q : logs) if (q.y == hy) for (int k = 0; k < 3; k++) cands.push_back(V3{q.x + B3[k][0], q.y, q.z + B3[k][2]});
					for (int i = (int)cands.size() - 1; i > 0; i--) { int j = (int)r.next_int_bound(i + 1); std::swap(cands[i], cands[j]); }
					for (const V3 &q2 : cands) {
						if (d[2] > 0 && tair(q2.x, q2.y, q2.z) && tair(q2.x, q2.y, q2.z + 1)) { set(q2.x, q2.y, q2.z, d[2], W_AIR); break; }
					}
					break;
				}
				case 4: {
					if (logs.empty() || !d[2]) break;
					int ly = logs[0].y;
					static const int OF[4][2] = {{-1, -1}, {2, -1}, {-1, 2}, {2, 2}};
					for (const V3 &q : logs) {
						if (q.y != ly) continue;
						for (int k = 0; k < 4; k++) alter_circle(d[3], q.x + OF[k][0], q.y, q.z + OF[k][1]);
						for (int k = 0; k < 5; k++) {
							int rr = (int)r.next_int_bound(64);
							int lx = rr % 8, lz = rr / 8;
							if (lx == 0 || lx == 7 || lz == 0 || lz == 7) alter_circle(d[3], q.x - 3 + lx, q.y, q.z - 3 + lz);
						}
					}
					break;
				}
				case 5: {
					if (logs.empty() || !d[2]) break;
					int oy = logs[0].y;
					int mnx = logs[0].x, mnz = logs[0].z, mxx = mnx, mxz = mnz;
					for (const V3 &q : logs) if (q.y == oy) { mnx = std::min(mnx, q.x); mnz = std::min(mnz, q.z); mxx = std::max(mxx, q.x); mxz = std::max(mxz, q.z); }
					int rad = d[4], hgt = d[5], tries = d[6], vine_b = d[7];
					for (int k = 0; k < tries; k++) {
						int qx = (int)r.next_int_bound(mxx - mnx + 2 * rad + 1) + mnx - rad;
						int qy = (int)r.next_int_bound(2 * hgt + 1) + oy - hgt;
						int qz = (int)r.next_int_bound(mxz - mnz + 2 * rad + 1) + mnz - rad;
						int as_ = get(qx, qy + 1, qz);
						int bs = get(qx, qy, qz);
						// Java PlaceOnGroundDecorator.attemptToPlaceBlockAbove: air / vine above, a solid-render block
						// (full opaque cube: not leaves, glass or ice) and MOTION_BLOCKING_NO_LEAVES at the column <= y + 1
						// (no collidable / fluid non-leaf block higher up; scanned 64 blocks)
						if ((as_ == 0 || (as_ > 0 && c.stblock[as_] == vine_b)) && bs > 0 && (flags(bs) & c.F_OPAQUE) && (flags(bs) & c.F_FULL_SHAPE)) {
							bool covered = false;
							for (int yy = qy + 2; yy <= qy + 64 && yy < MIN_Y + 384; yy++) {
								int s2 = get(qx, yy, qz);
								if (s2 > 0 && !(flags(s2) & c.F_LEAVES) && (flags(s2) & (c.F_COLLIDE | c.F_LIQUID | c.F_WATERLOGGED))) { covered = true; break; }
							}
							if (!covered) set(qx, qy + 1, qz, provide(d[3], qx, qy + 1, qz), W_AIR);
						}
					}
					break;
				}
				case 7: {
					// leave_vine: hanging vines below leaves, extended down up to 4 blocks
					for (const V3 &q : leaves)
						for (int k = 0; k < 4; k++) {
							if (r.next_float() < prob) {
								int nx = q.x + HD[k][0], ny = q.y, nz = q.z + HD[k][2];
								if (tair(nx, ny, nz) && d[2 + k] >= 0) {
									set(nx, ny, nz, d[2 + k], W_AIR);
									int kk = 4, dy = ny - 1;
									while (kk > 0 && tair(nx, dy, nz)) { set(nx, dy, nz, d[2 + k], W_AIR); dy--; kk--; }
								}
							}
						}
					break;
				}
				case 8: {
					// attached_to_leaves: [8, prob, has_prov, pv, need, exz, exy, ndirs, dirs...(0 down,1 up,2 n,3 s,4 w,5 e)]
					if (!d[2]) break;
					static const int DV[6][3] = {{0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1}, {-1, 0, 0}, {1, 0, 0}};
					int need = d[4], exz = d[5], exy = d[6], ndir = d[7];
					std::vector<V3> sh = leaves;
					for (int i = (int)sh.size() - 1; i > 0; i--) { int j = (int)r.next_int_bound(i + 1); std::swap(sh[i], sh[j]); }
					std::unordered_set<int64_t> excluded;
					auto key = [](int x, int y, int z) { return ((int64_t)(x & 0x3FFFFFF) << 38) | ((int64_t)(z & 0x3FFFFFF) << 12) | (int64_t)((y + 2048) & 0xFFF); };
					for (const V3 &q : sh) {
						int dsel = d[8 + (int)r.next_int_bound(ndir)];
						int dx = DV[dsel][0], dy = DV[dsel][1], dz = DV[dsel][2];
						int tx = q.x + dx, ty = q.y + dy, tz = q.z + dz;
						if (excluded.count(key(tx, ty, tz)) || r.next_float() >= prob) continue;
						bool okk = true;
						for (int k2 = 1; k2 < need + 1; k2++) if (!tair(q.x + dx * k2, q.y + dy * k2, q.z + dz * k2)) { okk = false; break; }
						if (!okk) continue;
						for (int ex = -exz; ex < exz + 1; ex++)
							for (int ey = -exy; ey < exy + 1; ey++)
								for (int ez = -exz; ez < exz + 1; ez++) excluded.insert(key(tx + ex, ty + ey, tz + ez));
						set(tx, ty, tz, provide(d[3], tx, ty, tz), W_AIR);
					}
					break;
				}
				case 9: {
					// pale_moss: [9, prob(unused), F ground, F trunk, F leaves, patch cf (-1), moss tip=false, moss tip=true (-1 none)]
					if (logs.empty()) break;
					if (r.next_float() < F[d[2]] && d[5] >= 0) place(d[5], logs[0].x, logs[0].y + 1, logs[0].z);
					double tp = F[d[3]], lp = F[d[4]];
					for (const V3 &q : logs) if (r.next_float() < tp && tair(q.x, q.y - 1, q.z)) moss_hanger(d, q.x, q.y - 1, q.z);
					for (const V3 &q : leaves) if (r.next_float() < lp && tair(q.x, q.y - 1, q.z)) moss_hanger(d, q.x, q.y - 1, q.z);
					break;
				}
				case 10: {
					// creaking_heart: [10, prob, heart state (-1 none)]
					if (r.next_float() >= prob || logs.empty()) break;
					if (d[2] < 0) break;
					std::vector<V3> sh2 = logs;
					for (int i = (int)sh2.size() - 1; i > 0; i--) { int j = (int)r.next_int_bound(i + 1); std::swap(sh2[i], sh2[j]); }
					static const int N6[6][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
					for (const V3 &q : sh2) {
						bool all_logs = true;
						for (int k = 0; k < 6; k++) {
							int ns = get(q.x + N6[k][0], q.y + N6[k][1], q.z + N6[k][2]);
							if (ns <= 0 || !(ns < (int)c.logn.size() && c.logn[ns])) { all_logs = false; break; }
						}
						if (all_logs) { set(q.x, q.y, q.z, d[2], W_FORCE); break; }
					}
					break;
				}
				case 6: {
					if (d[2] < 0 || logs.size() < 3 || r.next_float() >= prob) break;
					int cnt = 1 + (int)r.next_int_bound(3);
					for (int k = 0; k < cnt; k++) {
						const V3 &q4 = logs[1 + (int)r.next_int_bound((int)logs.size() - 1)];
						int dv = (int)r.next_int_bound(4);
						int nx = q4.x + HD[dv][0], ny = q4.y, nz = q4.z + HD[dv][2];
						if (tair(nx, ny, nz)) set(nx, ny, nz, d[3 + dv], W_AIR);
					}
					break;
				}
			}
		}
	}
	void moss_hanger(const int32_t *d, int x, int y, int z) {
		if (d[6] < 0) return;
		int py = y;
		while (tair(x, py - 1, z) && !(r.next_float() < 0.5)) { set(x, py, z, d[6], W_AIR); py--; }
		set(x, py, z, d[7], W_AIR);
	}
	void alter_circle(int pv, int qx, int qy, int qz) {
		for (int dx = -2; dx < 3; dx++)
			for (int dz = -2; dz < 3; dz++) {
				if (std::abs(dx) == 2 && std::abs(dz) == 2) continue;
				int bx = qx + dx, bz = qz + dz;
				for (int dy = 2; dy > -4; dy--) {
					int st = get(bx, qy + dy, bz);
					if (st > 0 && (c.below[st] & 1)) { set(bx, qy + dy, bz, provide(pv, bx, qy, bz), W_AIR); break; }
					if (st != 0 && dy < 0) break;
				}
			}
	}
	struct Att { int x, y, z, ro; bool dbl; };
	static float fancy_shape(int height, int y) {
		volatile float lim = (float)height * 0.3f;
		if ((float)y < lim) return -1.0f;
		float hf = (float)height / 2.0f;
		float f1 = hf - (float)y;
		if (f1 == 0.0f) return hf * 0.5f;
		if (std::fabs(f1) >= hf) return 0.0f;
		volatile float a = hf * hf, b = f1 * f1;   // separate float roundings (no fused multiply-add)
		volatile float dd = a - b;
		float f2 = (float)std::sqrt((double)dd);
		return f2 * 0.5f;
	}
	bool tfree(int x, int y, int z) const {
		if (tvalid(x, y, z)) return true;
		int st = get(x, y, z);
		return st > 0 && st < (int)c.logn.size() && c.logn[st];
	}
	bool fancy_limb(const int32_t *n, int pv, const int32_t *axt, int na, int ax, int ay, int az, int bx, int by, int bz, bool place) {
		if (!place && ax == bx && ay == by && az == bz) return true;
		int dx = bx - ax, dy = by - ay, dz = bz - az;
		int steps = std::max(std::abs(dx), std::max(std::abs(dy), std::abs(dz)));
		if (steps == 0) { tlog(n, pv, axt, na, ax, ay, az, 0); return true; }
		float fx = (float)dx / (float)steps, fy = (float)dy / (float)steps, fz = (float)dz / (float)steps;
		for (int j = 0; j <= steps; j++) {
			volatile float ux = 0.5f + (float)j * fx, uy = 0.5f + (float)j * fy, uz = 0.5f + (float)j * fz;
			int qx = ax + (int)std::floor(ux), qy = ay + (int)std::floor(uy), qz = az + (int)std::floor(uz);
			if (place) {
				int ix = std::abs(qx - ax), iz = std::abs(qz - az), km = std::max(ix, iz);
				tlog(n, pv, axt, na, qx, qy, qz, km == 0 ? 0 : (ix == km ? 1 : 2));
			} else if (!tfree(qx, qy, qz)) return false;
		}
		return true;
	}
	void fancy_trunk(const int32_t *n, int pv, const int32_t *axt, int na, int px, int py, int pz, int h, std::vector<Att> &atts) {
		int jh = h + 2;
		int tk = (int)std::floor(jh * 0.618);
		int i1 = py + tk;
		int j1 = jh - 5;
		struct FC { int x, y, z, base; };
		std::vector<FC> coords;
		coords.push_back(FC{px, py + j1, pz, i1});
		for (; j1 >= 0; j1--) {
			float fs = fancy_shape(jh, j1);
			if (fs < 0.0f) continue;
			double d2 = (double)fs * ((double)r.next_float() + 0.328);
			volatile float a2 = (float)r.next_float() * 2.0f;
			double d3 = (double)a2 * 3.141592653589793;
			int bx = px + (int)std::floor(d2 * std::sin(d3) + 0.5), by = py + j1 - 1, bz = pz + (int)std::floor(d2 * std::cos(d3) + 0.5);
			if (fancy_limb(n, pv, axt, na, bx, by, bz, bx, by + 5, bz, false)) {
				int l1 = px - bx, i2 = pz - bz;
				double d6 = (double)by - std::sqrt((double)(l1 * l1 + i2 * i2)) * 0.381;
				int j2 = d6 > (double)i1 ? i1 : (int)d6;
				if (fancy_limb(n, pv, axt, na, px, j2, pz, bx, by, bz, false)) coords.push_back(FC{bx, by, bz, j2});
			}
		}
		fancy_limb(n, pv, axt, na, px, py, pz, px, py + tk, pz, true);
		for (const FC &fc : coords)
			if (!(fc.x == px && fc.y == fc.base && fc.z == pz) && (double)(fc.base - py) >= (double)jh * 0.2)
				fancy_limb(n, pv, axt, na, px, fc.base, pz, fc.x, fc.y, fc.z, true);
		for (const FC &fc : coords)
			if ((double)(fc.base - py) >= (double)jh * 0.2) atts.push_back(Att{fc.x, fc.y, fc.z, 0, false});
	}
	bool tree(const int32_t *n, int px, int py, int pz) {
		int tk = n[1];
		bool bending = n[2] != 0;
		int fk = n[3];
		int a1 = (int)r.next_int_bound(n[5] + 1);
		int a2 = (int)r.next_int_bound(n[6] + 1);
		int h = n[4] + a1 + a2;
		int fh;
		if (n[7] == 0) fh = n[8];
		else if (n[7] == 1) fh = std::max(4, h - (int)ip(n[8]));
		else fh = (int)ip(n[8]);
		int radius = (int)ip(n[9]);
		int offset = (int)ip(n[10]);
		bool dbl = tk == 1 || tk == 2 || tk == 3;
		int na = n[15];
		const int32_t *axt = n + 16;
		int nd_off = 16 + na * 4;
		logs.clear();
		leaves.clear();
		leaves_n = 0;
		if (py < MIN_Y + 1 || py + h + 1 >= MAX_Y) return false;
		int w = dbl ? 2 : 1;
		for (int y = 0; y < h; y++)
			for (int dx = 0; dx < w; dx++)
				for (int dz = 0; dz < w; dz++)
					if (!tvalid(px + dx, py + y, pz + dz)) return false;
		for (int dx = 0; dx < w; dx++)
			for (int dz = 0; dz < w; dz++) {
				int bx = px + dx, by = py - 1, bz = pz + dz;
				// Java 26.x placeBelowTrunkBlock (see Trees.place): the provider decides (rule-based soil_beneath_tree)
				int soil = provide(n[13], bx, by, bz);
				if (soil > 0) set(bx, by, bz, soil, W_FORCE);
			}
		std::vector<Att> atts;
		int tpv = n[11];
		switch (tk) {
			case 1: {
				static const int D4[4][2] = {{0, -1}, {0, 1}, {-1, 0}, {1, 0}};
				int di = (int)r.next_int_bound(4);
				int si = h - (int)r.next_int_bound(4);
				int sj = 2 - (int)r.next_int_bound(3);
				int nx = px, nz = pz, top = py + h - 1;
				for (int q = 0; q < h; q++) {
					if (q >= si && sj > 0) { nx += D4[di][0]; nz += D4[di][1]; sj--; }
					int bx = nx, by = py + q, bz = nz;
					if (tvalid(bx, by, bz)) {
						tlog(n, tpv, axt, na, bx, by, bz, 0);
						tlog(n, tpv, axt, na, bx + 1, by, bz, 0);
						tlog(n, tpv, axt, na, bx, by, bz + 1, 0);
						tlog(n, tpv, axt, na, bx + 1, by, bz + 1, 0);
					}
				}
				atts.push_back(Att{nx, top, nz, 0, true});
				for (int q = -1; q < 3; q++)
					for (int rr = -1; rr < 3; rr++) {
						if ((q < 0 || q > 1 || rr < 0 || rr > 1) && r.next_int_bound(3) <= 0) {
							int s2 = (int)r.next_int_bound(3) + 2;
							for (int t2 = 0; t2 < s2; t2++) tlog(n, tpv, axt, na, px + q, top - t2 - 1, pz + rr, 0);
							atts.push_back(Att{px + q, top, pz + rr, 0, false});
						}
					}
				break;
			}
			case 2: case 3: {
				for (int y = 0; y < h; y++)
					for (int dx = 0; dx < 2; dx++)
						for (int dz = 0; dz < 2; dz++) tlog(n, tpv, axt, na, px + dx, py + y, pz + dz, 0);
				atts.push_back(Att{px, py + h, pz, 0, true});
				if (tk == 3) {
					int y2 = h - 2 - (int)r.next_int_bound(4);
					while (y2 > h / 2) {
						// Java MegaJungleTrunkPlacer (Trees.gd): 5 upright logs at (int)(1.5F + Mth.cos(f) * l)
						float a = (float)r.next_float() * (float)6.283185307179586;
						auto msin = [](double v) { return (float)std::sin((double)((int64_t)(v * 10430.378350470453) & 65535) * 6.283185307179586 / 65536.0); };
						auto mcos = [](double v) { return (float)std::sin((double)((int64_t)(v * 10430.378350470453 + 16384.0) & 65535) * 6.283185307179586 / 65536.0); };
						int bx = 0, bz = 0;
						for (int k = 0; k < 5; k++) {
							bx = (int)(1.5f + mcos(a) * (float)k);
							bz = (int)(1.5f + msin(a) * (float)k);
							tlog(n, tpv, axt, na, px + bx, py + y2 - 3 + k / 2, pz + bz, 0);
						}
						atts.push_back(Att{px + bx, py + y2, pz + bz, -2, false});
						y2 -= 2 + (int)r.next_int_bound(4);
					}
				}
				break;
			}
			case 4: {
				static const int D4b[4][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
				int di = (int)r.next_int_bound(4);
				int bend = h - (int)r.next_int_bound(4) - 1;
				int bl = 3 - (int)r.next_int_bound(3);
				int qx = px, qz = pz;
				for (int y = 0; y < h; y++) {
					if (y >= bend && bl > 0) { qx += D4b[di][0]; qz += D4b[di][1]; bl--; }
					tlog(n, tpv, axt, na, qx, py + y, qz, 0);
				}
				atts.push_back(Att{qx, py + h, qz, 0, false});
				if (!bending && r.next_bool()) {
					int d2 = (int)r.next_int_bound(4);
					if (d2 != di) {
						int s = bend - (int)r.next_int_bound(2) - 1;
						int x2 = px, y2 = py + s, z2 = pz;
						int cnt = 1 + (int)r.next_int_bound(3);
						for (int k = 0; k < cnt; k++) { x2 += D4b[d2][0]; y2 += 1; z2 += D4b[d2][1]; tlog(n, tpv, axt, na, x2, y2, z2, 0); }
						atts.push_back(Att{x2, y2 + 1, z2, 0, false});
					}
				}
				break;
			}
			case 5: {
				// Java FancyTrunkPlacer (Trees._fancy_trunk)
				fancy_trunk(n, tpv, axt, na, px, py, pz, h, atts);
				break;
			}
			case 105: {   // (old approximation, unused)
				int nb = 1 + (int)r.next_int_bound(3);
				for (int b = 0; b < nb; b++) {
					int by = (int)(h * (0.4 + 0.5 * r.next_float()));
					double ang = r.next_float() * 6.283185307179586;
					double ln = 2.0 + r.next_float() * 2.0;
					int ex = px + (int)std::round(std::cos(ang) * ln), ey = py + by + 1, ez = pz + (int)std::round(std::sin(ang) * ln);
					int steps = (int)std::ceil(ln);
					int axis = std::fabs(std::cos(ang)) > std::fabs(std::sin(ang)) ? 1 : 2;
					// Vector3 (single precision) lerp from the trunk point to the branch end, rounded per component
					float ox = (float)px, oy = (float)py + (float)by, oz = (float)pz;
					float vx = ((float)ex - (float)px) - 0.0f, vy = ((float)ey - (float)py) - (float)by, vz = ((float)ez - (float)pz) - 0.0f;
					for (int k = 1; k < steps + 1; k++) {
						float t = (float)((double)k / steps);
						float qx = ox + vx * t, qy = oy + vy * t, qz = oz + vz * t;
						tlog(n, tpv, axt, na, (int)std::round(qx), (int)std::round(qy), (int)std::round(qz), axis);
					}
					atts.push_back(Att{ex, ey, ez, 0, false});
				}
				break;
			}
			default:
				for (int y = 0; y < h; y++) tlog(n, tpv, axt, na, px, py + y, pz, 0);
				atts.push_back(Att{px, py + h, pz, 0, false});
		}
		for (const Att &at : atts) tfoliage(n, fk, at.x, at.y, at.z, at.ro, at.dbl, fh, radius, offset);
		tdecorators(n, nd_off);
		return true;
	}
	// Trees.mushroom: Java HugeRed/BrownMushroomFeature (height, isValidPosition, stem, caps with face states).
	// n: [22, red, stem pv, cap pv, radius, dirt mask, mushroom_grow_block mask, cap state by face bits x32]
	bool solid_render(int x, int y, int z) const {
		int st = get(x, y, z);
		return st < 0 || (st > 0 && (flags(st) & c.F_OPAQUE));
	}
	bool mushroom(const int32_t *n, int px, int py, int pz) {
		bool red = n[1] != 0;
		int h = 4 + (int)r.next_int_bound(3);
		if (r.next_int_bound(12) == 0) h *= 2;
		int rad = n[4];
		if (py < MIN_Y + 1 || py + h + 1 >= MAX_Y) return false;
		int below = get(px, py - 1, pz);
		if (below <= 0) return false;
		const uint8_t *dm = c.M.data() + n[5];
		const uint8_t *gm = c.M.data() + n[6];
		if (!dm[below] && !gm[below]) return false;
		for (int j = 0; j <= h; j++) {
			int k = red ? 0 : (j <= 3 ? 0 : rad);
			for (int l = -k; l <= k; l++)
				for (int i1 = -k; i1 <= k; i1++) {
					int st = get(px + l, py + j, pz + i1);
					if (st != 0 && (st < 0 || !(flags(st) & c.F_LEAVES))) return false;
				}
		}
		for (int y = 0; y < h; y++)
			if (!solid_render(px, py + y, pz)) set(px, py + y, pz, provide(n[2], px, py, pz), W_FORCE);
		const int32_t *capt = n + 7;
		if (red) {
			int kk = rad - 2;
			for (int y = h - 3; y <= h; y++) {
				int j2 = y < h ? rad : rad - 1;
				for (int l = -j2; l <= j2; l++)
					for (int i1 = -j2; i1 <= j2; i1++) {
						bool e4 = l == -j2 || l == j2, e5 = i1 == -j2 || i1 == j2;
						if (!(y >= h || e4 != e5)) continue;
						int qx = px + l, qy = py + y, qz = pz + i1;
						if (solid_render(qx, qy, qz)) continue;
						int cs = provide(n[3], px, py, pz);
						int fb = (y >= h - 1 ? 1 : 0) | (i1 < -kk ? 2 : 0) | (i1 > kk ? 4 : 0) | (l > kk ? 8 : 0) | (l < -kk ? 16 : 0);
						if (capt[fb] >= 0) cs = capt[fb];
						set(qx, qy, qz, cs, W_FORCE);
					}
			}
		} else {
			for (int l = -rad; l <= rad; l++)
				for (int i1 = -rad; i1 <= rad; i1++) {
					bool f0 = l == -rad, f1 = l == rad, f2 = i1 == -rad, f3 = i1 == rad;
					bool f4 = f0 || f1, f5 = f2 || f3;
					if (f4 && f5) continue;
					int qx = px + l, qy = py + h, qz = pz + i1;
					if (solid_render(qx, qy, qz)) continue;
					int cs = provide(n[3], px, py, pz);
					bool w = f0 || (f5 && l == 1 - rad), e = f1 || (f5 && l == rad - 1);
					bool no = f2 || (f4 && i1 == 1 - rad), so = f3 || (f4 && i1 == rad - 1);
					int fb = (no ? 2 : 0) | (so ? 4 : 0) | (e ? 8 : 0) | (w ? 16 : 0);
					if (capt[fb] >= 0) cs = capt[fb];
					set(qx, qy, qz, cs, W_FORCE);
				}
		}
		return true;
	}	bool fallen(const int32_t *n, int px, int py, int pz) {
		int below = get(px, py - 1, pz);
		if (below <= 0 || !(flags(below) & c.F_FULL_SHAPE) || get(px, py, pz) != 0) return false;
		int na = n[3];
		const int32_t *axt = n + 4;
		logs.clear();
		tlog(n, n[1], axt, na, px, py, pz, 0);
		int64_t length = ip(n[2]);
		static const int D4c[4][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
		int di = (int)r.next_int_bound(4);
		int sk = 2 + (int)r.next_int_bound(2);
		int sx = px + D4c[di][0] * sk, sz = pz + D4c[di][1] * sk;
		for (int64_t k = 0; k < length; k++) {
			int qx = sx + D4c[di][0] * (int)k, qz = sz + D4c[di][1] * (int)k;
			int bl = get(qx, py - 1, qz);
			if (get(qx, py, qz) != 0 || bl <= 0 || !(flags(bl) & c.F_COLLIDE)) break;
			tlog(n, n[1], axt, na, qx, py, qz, D4c[di][0] != 0 ? 1 : 2);
		}
		return true;
	}

	// Features._lake
	bool lake(const int32_t *n, int x0, int y0, int z0) {
		if (y0 <= MIN_Y + 4) return false;
		int px = x0 - 8, py = y0 - 4, pz = z0 - 8;
		uint8_t grid[2048];
		memset(grid, 0, sizeof(grid));
		int cnt = (int)r.next_int_bound(4) + 4;
		for (int k = 0; k < cnt; k++) {
			double d = r.next_double() * 6.0 + 3.0;
			double e = r.next_double() * 4.0 + 2.0;
			double f = r.next_double() * 6.0 + 3.0;
			double g = r.next_double() * (16.0 - d - 2.0) + 1.0 + d / 2.0;
			double h = r.next_double() * (8.0 - e - 4.0) + 2.0 + e / 2.0;
			double ii = r.next_double() * (16.0 - f - 2.0) + 1.0 + f / 2.0;
			for (int x = 1; x < 15; x++)
				for (int z = 1; z < 15; z++)
					for (int y = 1; y < 7; y++) {
						double o = (x - g) / (d / 2.0);
						double q = (y - h) / (e / 2.0);
						double rr = (z - ii) / (f / 2.0);
						if (o * o + q * q + rr * rr < 1.0) grid[(x * 16 + z) * 8 + y] = 1;
					}
		}
		int fluid = provide(n[1], px, py, pz);
		if (fluid <= 0) return false;
		auto edge = [&](int x, int y, int z) {
			if (grid[(x * 16 + z) * 8 + y]) return false;
			return (x < 15 && grid[((x + 1) * 16 + z) * 8 + y]) || (x > 0 && grid[((x - 1) * 16 + z) * 8 + y]) ||
				(z < 15 && grid[(x * 16 + z + 1) * 8 + y]) || (z > 0 && grid[(x * 16 + z - 1) * 8 + y]) ||
				(y < 7 && grid[(x * 16 + z) * 8 + y + 1]) || (y > 0 && grid[(x * 16 + z) * 8 + y - 1]);
		};
		// Java LakeFeature (see Features._lake): no liquid around above the fluid line, below it solid or own fluid
		for (int x = 0; x < 16; x++)
			for (int z = 0; z < 16; z++)
				for (int y = 0; y < 8; y++) {
					if (!edge(x, y, z)) continue;
					int st = get(px + x, py + y, pz + z);
					if (y >= 4 && st > 0 && (flags(st) & c.F_LIQUID)) return false;
					if (y < 4 && !(st > 0 && (flags(st) & c.F_COLLIDE)) && st != fluid) return false;
				}
		for (int x = 0; x < 16; x++)
			for (int z = 0; z < 16; z++)
				for (int y = 0; y < 8; y++)
					if (grid[(x * 16 + z) * 8 + y] && test(n[3], px + x, py + y, pz + z))
						set(px + x, py + y, pz + z, y >= 4 ? 0 : fluid, W_FORCE);
		int bar = provide(n[2], px, py, pz);
		if (bar > 0) {
			for (int x = 0; x < 16; x++)
				for (int z = 0; z < 16; z++)
					for (int y = 0; y < 8; y++)
						if (edge(x, y, z) && (y < 4 || r.next_int_bound(2) != 0)) {
							int st = get(px + x, py + y, pz + z);
							if (st > 0 && (flags(st) & c.F_COLLIDE) && test(n[4], px + x, py + y, pz + z))
								set(px + x, py + y, pz + z, bar, W_FORCE);
						}
		}
		return true;
	}
	bool column(const int32_t *n, int x, int y, int z) {
		int dir = n[1], allowed = n[2], nl = n[3];
		std::vector<int64_t> heights(nl);
		int64_t total = 0;
		for (int l = 0; l < nl; l++) { heights[l] = ip(n[4 + l * 2]); total += heights[l]; }
		if (total == 0) return false;
		int qy = y;
		int placed = 0;
		for (int li = 0; li < nl; li++) {
			for (int64_t k = 0; k < heights[li]; k++) {
				if (!test(allowed, x, qy, z)) return placed > 0;
				int st = provide(n[5 + li * 2], x, qy, z);
				if (placed == 0 && !can_survive(st, x, qy, z)) return false;
				set(x, qy, z, st, W_AIR);
				placed++;
				qy += dir;
			}
		}
		return true;
	}
	// ---------------------------------------------------------------- Nether (FeaturesExt, same RNG order)
	// 26.3 Nether feature types; in GDScript they cost ~200 ms per basalt-delta chunk (seconds per chunk while loading).
	bool is_air(int st) const { return st == 0 || (st > 0 && (flags(st) & 1)); }
	bool is_blk(int st, int bid) const { return st >= 0 && c.stblock[st] == bid; }
	static constexpr int D6[6][3] = {{0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1}, {-1, 0, 0}, {1, 0, 0}};
	// netherrack_replace_blobs: [25, target block, state, radius ip]
	bool replace_blobs(const int32_t *n, int x, int y, int z) {
		int lo = c.gen_min_y + 1, hi = c.gen_min_y + c.gen_depth - 1;
		int py = y < lo ? lo : (y > hi ? hi : y);
		bool found = false;
		while (py > c.gen_min_y + 1) {
			if (is_blk(get(x, py, z), n[1])) { found = true; break; }
			py--;
		}
		if (!found) return false;
		int64_t i = ip(n[3]), j = ip(n[3]), k = ip(n[3]);
		int64_t l = std::max(i, std::max(j, k));
		bool any = false;
		for (int64_t dx = -i; dx <= i; dx++)
			for (int64_t dy = -j; dy <= j; dy++)
				for (int64_t dz = -k; dz <= k; dz++) {
					if (std::llabs(dx) + std::llabs(dy) + std::llabs(dz) > l) continue;
					int qx = x + (int)dx, qy = py + (int)dy, qz = z + (int)dz;
					if (is_blk(get(qx, qy, qz), n[1])) { set(qx, qy, qz, n[2], W_FORCE); any = true; }
				}
		return any;
	}
	// delta_feature: [26, contents, rim, size ip, rim_size ip, contents block, n bad, bad block ids...]
	bool delta_clear(const int32_t *n, int x, int y, int z) {
		int s = get(x, y, z);
		if (s < 0) return false;
		int b = c.stblock[s];
		if (b == n[5]) return false;
		for (int k = 0; k < n[6]; k++) if (n[7 + k] == b) return false;
		for (int d = 0; d < 6; d++) {
			bool air = is_air(get(x + D6[d][0], y + D6[d][1], z + D6[d][2]));
			if ((air && d != 1) || (!air && d == 1)) return false;
		}
		return true;
	}
	bool delta(const int32_t *n, int x, int y, int z) {
		bool any = false;
		bool big = r.next_double() < 0.9;
		int64_t i = big ? ip(n[4]) : 0;
		int64_t j = big ? ip(n[4]) : 0;
		bool rim = big && i != 0 && j != 0;
		int64_t k = ip(n[3]), l = ip(n[3]);
		int64_t m = std::max(k, l);
		// BlockPos.withinManhattan(o, k, 0, l) in Features_ext.within_manhattan order; stops beyond distance m
		for (int64_t depth = 0; depth <= k + l && depth <= m; depth++) {
			int64_t mx = std::min(k, depth);
			for (int64_t ax = -mx; ax <= mx; ax++) {
				int64_t mm = depth - std::llabs(ax);
				if (mm > l) continue;
				for (int sg = 0; sg < (mm != 0 ? 2 : 1); sg++) {
					int px = x + (int)ax, py = y, pz = z + (int)(sg == 0 ? mm : -mm);
					if (delta_clear(n, px, py, pz)) {
						if (rim) { any = true; set(px, py, pz, n[2], W_FORCE); }
						int qx = px + (int)i, qz = pz + (int)j;
						if (delta_clear(n, qx, py, qz)) { any = true; set(qx, py, qz, n[1], W_FORCE); }
					}
				}
			}
		}
		return any;
	}
	// stepped_column_cluster: [27, block pv, can_replace pr, continue pr, cluster_reach, column_count, column_reach ip,
	//   height ip, n cannot, cannot block ids...]
	bool col_cannot(const int32_t *n, int st) const {
		if (st < 0) return false;
		int b = c.stblock[st];
		for (int k = 0; k < n[8]; k++) if (n[9 + k] == b) return true;
		return false;
	}
	bool col_can_place(const int32_t *n, int x, int y, int z) {
		if (!test(n[2], x, y, z)) return false;
		int below = get(x, y - 1, z);
		return below > 0 && !is_air(below) && !col_cannot(n, below);
	}
	bool col_place(const int32_t *n, int px, int py, int pz, int64_t distance, int64_t reach) {
		bool any = false;
		for (int64_t dz = -reach; dz <= reach; dz++)
			for (int64_t dx = -reach; dx <= reach; dx++) {
				int x = px + (int)dx, z = pz + (int)dz;
				int64_t i = std::llabs(dx) + std::llabs(dz);
				bool have = false;
				int qy = 0;
				if (test(n[2], x, py, z)) {
					int sy = py;
					int64_t nn = i;
					while (sy > c.gen_min_y + 1 && nn > 0) {
						nn--;
						if (col_can_place(n, x, sy, z)) { have = true; qy = sy; break; }
						sy--;
					}
				} else {
					int sy = py;
					int64_t nn = i;
					while (sy < c.gen_min_y + c.gen_depth && nn > 0) {
						nn--;
						int st = get(x, sy, z);
						if (col_cannot(n, st)) break;
						if (is_air(st)) { have = true; qy = sy; break; }
						sy++;
					}
				}
				if (!have) continue;
				int64_t hgt = distance - i / 2;
				int my = qy;
				while (hgt >= 0) {
					if (test(n[2], x, my, z)) {
						int st = provide(n[1], x, my, z);
						if (st >= 0) set(x, my, z, st, W_FORCE);
						my++;
						any = true;
					} else if (test(n[3], x, my, z)) {
						my++;
					} else break;
					hgt--;
				}
			}
		return any;
	}
	bool columns(const int32_t *n, int x, int y, int z) {
		if (!col_can_place(n, x, y, z)) return false;
		int64_t j = ip(n[7]);
		int64_t k = std::min(j, (int64_t)n[4]);
		bool any = false;
		for (int cnt = 0; cnt < n[5]; cnt++) {
			int64_t px = x - k + r.next_int_bound(2 * k + 1);
			r.next_int_bound(1);
			int64_t pz = z - k + r.next_int_bound(2 * k + 1);
			int64_t m = j - (std::llabs(px - x) + std::llabs(pz - z));
			if (m >= 0 && col_place(n, (int)px, y, (int)pz, m, ip(n[6]))) any = true;
		}
		return any;
	}
	// single_block_pillar: [28, block pv, can_replace pr, dir -1 / 1, chance (F), cap pf or -1]
	bool pillar(const int32_t *n, int x, int y, int z) {
		double chance = F[n[4]];
		int py = y, last = y;
		bool placed = false;
		while (py >= c.gen_min_y && py < c.gen_min_y + c.gen_depth && test(n[2], x, py, z)) {
			int st = provide(n[1], x, py, z);
			if (st >= 0) set(x, py, z, st, W_FORCE);
			placed = true;
			last = py;
			py += n[3];
			if (chance < 1.0 && r.next_float() >= chance) break;
		}
		if (placed && n[5] >= 0) sub(n[5], x, last, z);
		return placed;
	}
	// projected_random_patchy_square: [29, block pv, size, max projection, through pr]
	bool patchy(const int32_t *n, int x, int y, int z) {
		int sz = n[2];
		bool any = false;
		for (int i = -sz; i <= sz; i++)
			for (int j = -sz; j <= sz; j++) {
				int k = std::abs(i) * std::abs(j);
				if (r.next_int_bound(10) >= 10 - k) continue;
				int qx = x + i, qy = y, qz = z + j, h = 0;
				while (h < n[3] && test(n[4], qx, qy - 1, qz)) { qy--; h++; }
				if (!test(n[4], qx, qy, qz)) continue;
				int st = provide(n[1], qx, qy, qz);
				if (st > 0) { set(qx, qy, qz, st, W_FORCE); any = true; }
			}
		return any;
	}
	// random_neighbor_spread: [30, block pv, can_replace pr, attempts, xz ip, y ip, n accepted, accepted block ids...]
	bool neighbor_spread(const int32_t *n, int x, int y, int z) {
		if (!test(n[2], x, y, z)) return false;
		int st = provide(n[1], x, y, z);
		if (st >= 0) set(x, y, z, st, W_FORCE);
		for (int a = 0; a < n[3]; a++) {
			int px = x + (int)ip(n[4]);
			int py = y + (int)ip(n[5]);
			int pz = z + (int)ip(n[4]);
			if (!test(n[2], px, py, pz)) continue;
			int cnt = 0;
			for (int d = 0; d < 6; d++) {
				int s = get(px + D6[d][0], py + D6[d][1], pz + D6[d][2]);
				if (s > 0) {
					int b = c.stblock[s];
					bool acc = false;
					for (int q = 0; q < n[6]; q++) if (n[7 + q] == b) { acc = true; break; }
					if (acc && ++cnt > 1) break;
				}
			}
			if (cnt == 1) {
				int s2 = provide(n[1], px, py, pz);
				if (s2 >= 0) set(px, py, pz, s2, W_FORCE);
			}
		}
		return true;
	}
	// huge_fungus: [31, stem, hat, decor, base block, replace pr, planted, hat is wart, vine plant, vine tip age 23, 24, 25]
	bool fung_repl(const int32_t *n, int x, int y, int z, bool check) {
		int s = get(x, y, z);
		if (s == 0 || (s > 0 && (flags(s) & c.F_REPLACEABLE))) return true;
		return check && test(n[5], x, y, z);
	}
	void weeping(const int32_t *n, int x, int y, int z) {
		int my = y - 1;
		if (!is_air(get(x, my, z))) return;
		int64_t nn = mth(1, 5);
		if (r.next_int_bound(7) == 0) nn *= 2;
		for (int64_t i = 0; i <= nn; i++) {
			if (is_air(get(x, my, z))) {
				if (i == nn || !is_air(get(x, my - 1, z))) {
					int64_t age = mth(23, 25);
					set(x, my, z, n[9 + (int)(age - 23)], W_FORCE);
					break;
				}
				set(x, my, z, n[8], W_FORCE);
			}
			my--;
		}
	}
	void hat_block(const int32_t *n, int x, int y, int z, double decor, double hat, double vine) {
		if (r.next_float() < decor) set(x, y, z, n[3], W_FORCE);
		else if (r.next_float() < hat) {
			set(x, y, z, n[2], W_FORCE);
			if (r.next_float() < vine) weeping(n, x, y, z);
		}
	}
	bool fungus(const int32_t *n, int x, int y, int z) {
		if (!is_blk(get(x, y - 1, z), n[4])) return false;
		int64_t h = mth(4, 13);
		if (r.next_int_bound(12) == 0) h *= 2;
		bool planted = n[6] != 0;
		if (!planted && y + h + 1 >= c.gen_depth) return false;
		bool huge = !planted && r.next_float() < 0.06;
		set(x, y, z, 0, W_FORCE);
		int si = huge ? 1 : 0;
		for (int j = -si; j <= si; j++)
			for (int k = -si; k <= si; k++) {
				bool corner = huge && std::abs(j) == si && std::abs(k) == si;
				for (int64_t l = 0; l < h; l++) {
					int my = y + (int)l;
					if (fung_repl(n, x + j, my, z + k, true)) {
						if (corner) { if (r.next_float() < 0.1) set(x + j, my, z + k, n[1], W_FORCE); }
						else set(x + j, my, z + k, n[1], W_FORCE);
					}
				}
			}
		bool wart = n[7] != 0;
		int64_t i = std::min((int64_t)r.next_int_bound(1 + h / 3) + 5, h);
		int64_t j0 = h - i;
		int hat_b = c.stblock[n[2]];
		for (int64_t k2 = j0; k2 <= h; k2++) {
			int64_t lr = k2 < h - r.next_int_bound(3) ? 2 : 1;
			if (i > 8 && k2 < j0 + 4) lr = 3;
			if (huge) lr++;
			for (int64_t nn = -lr; nn <= lr; nn++)
				for (int64_t o2 = -lr; o2 <= lr; o2++) {
					bool e1 = nn == -lr || nn == lr, e2 = o2 == -lr || o2 == lr;
					bool inner = !e1 && !e2 && k2 != h;
					bool corner2 = e1 && e2;
					bool low = k2 < j0 + 3;
					int mx = x + (int)nn, my = y + (int)k2, mz = z + (int)o2;
					if (!fung_repl(n, mx, my, mz, false)) continue;
					if (low) {
						if (!inner) {
							int bs = get(mx, my - 1, mz);
							if (bs > 0 && c.stblock[bs] == hat_b) set(mx, my, mz, n[2], W_FORCE);
							else if (r.next_float() < 0.15) {
								set(mx, my, mz, n[2], W_FORCE);
								if (wart && r.next_int_bound(11) == 0) weeping(n, mx, my, mz);
							}
						}
					} else if (inner) hat_block(n, mx, my, mz, 0.1, 0.2, wart ? 0.1 : 0.0);
					else if (corner2) hat_block(n, mx, my, mz, 0.01, 0.7, wart ? 0.083 : 0.0);
					else hat_block(n, mx, my, mz, 0.0005, 0.98, wart ? 0.07 : 0.0);
				}
		}
		return true;
	}

	// ---------------------------------------------------------------- sculk_patch (Java SculkPatchFeature with the
	// world-gen SculkSpreader: replaceable #sculk_replaceable_world_gen, growth cost 50, no-growth radius 1, charge
	// decay 1 in 5, additional decay 1 in 10; cursors merge never, die 15 blocks out; sculk / sculk vein behaviours,
	// MultifaceSpreader for veins). Directions: 0 down, 1 up, 2 north, 3 south, 4 west, 5 east (Direction.values()).
	enum { SK_CC = 1, SK_AMT, SK_ATT, SK_GROW, SK_SPREAD, SK_RARE, SK_S_SCULK, SK_S_SENSOR, SK_S_SENSOR_WL, SK_S_SHRIEK,
		SK_S_SHRIEK_WL, SK_S_WATER, SK_B_SCULK, SK_B_VEIN, SK_B_CATALYST, SK_B_PISTON, SK_B_WATER, SK_B_SENSOR, SK_B_SHRIEK,
		SK_B_FIRE, SK_B_SOUL_FIRE, SK_VEIN_FIRST, SK_LOCAL, SK_STATE = SK_LOCAL + 128, SK_NREPL = SK_STATE + 128, SK_REPL };
	struct SkC { int x, y, z, charge, upd, decay, faces; };   // faces -1 = none known (Java null)
	const int32_t *sk = nullptr;
	int skd(int d, int a) const {
		static const int D[6][3] = {{0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1}, {-1, 0, 0}, {1, 0, 0}};
		return D[d][a];
	}
	int sk_at(int x, int y, int z, int d) const { return get(x + skd(d, 0), y + skd(d, 1), z + skd(d, 2)); }
	bool sk_sturdy(int st) const { int f = flags(st); return st > 0 && (f & c.F_FULL_SHAPE) && (f & c.F_COLLIDE); }
	bool sk_is_vein(int st) const { return st > 0 && bid(st) == sk[SK_B_VEIN]; }
	int sk_code(int st) const { return sk_is_vein(st) ? sk[SK_LOCAL + (st - sk[SK_VEIN_FIRST])] : 0; }
	bool sk_has(int st, int d) const { return (sk_code(st) >> d) & 1; }
	int sk_beh(int st) const {   // 0 default, 1 sculk, 2 sculk vein
		if (st <= 0) return 0;
		int b = bid(st);
		return b == sk[SK_B_SCULK] ? 1 : (b == sk[SK_B_VEIN] ? 2 : 0);
	}
	bool sk_repl(int st) const {
		if (st <= 0) return false;
		int b = bid(st);
		return std::binary_search(sk + SK_REPL, sk + SK_REPL + sk[SK_NREPL], b);
	}
	bool sk_fluid(int st) const { return st > 0 && (flags(st) & (c.F_LIQUID | c.F_WATERLOGGED)); }
	// MultifaceBlock.isValidStateForPlacement: no such face yet, and the block behind that face can hold it
	bool sk_valid(int st, int x, int y, int z, int d) const { return (!sk_is_vein(st) || !sk_has(st, d)) && sk_sturdy(sk_at(x, y, z, d)); }
	// SculkVeinSpreaderConfig.stateCanBeReplaced
	bool sk_can_replace(int px, int py, int pz, int sx, int sy, int sz, int d, int st) const {
		int b2 = bid(sk_at(sx, sy, sz, d));
		if (b2 == sk[SK_B_SCULK] || b2 == sk[SK_B_CATALYST] || b2 == sk[SK_B_PISTON]) return false;
		if (std::abs(px - sx) + std::abs(py - sy) + std::abs(pz - sz) == 2 && sk_sturdy(sk_at(px, py, pz, d ^ 1))) return false;
		if (st > 0 && (flags(st) & c.F_LIQUID) && bid(st) != sk[SK_B_WATER]) return false;
		int b = bid(st);
		if (st > 0 && (b == sk[SK_B_FIRE] || b == sk[SK_B_SOUL_FIRE])) return false;
		return st == 0 || (flags(st) & c.F_REPLACEABLE) || sk_is_vein(st) || st == sk[SK_S_WATER];
	}
	// MultifaceSpreader.spreadFromFaceTowardDirection; types: 0 same position, 1 same plane, 2 wrap around
	bool sk_spread_one(int st, int x, int y, int z, int sd, int face, int ntypes, const int *types) {
		if ((face >> 1) == (sd >> 1)) return false;
		if (!(!sk_is_vein(st) || (sk_has(st, sd) && !sk_has(st, face)))) return false;
		for (int t = 0; t < ntypes; t++) {
			int qx = x, qy = y, qz = z, qd = face;
			if (types[t] == 1) { qx += skd(face, 0); qy += skd(face, 1); qz += skd(face, 2); qd = sd; }
			else if (types[t] == 2) {
				qx += skd(face, 0) + skd(sd, 0); qy += skd(face, 1) + skd(sd, 1); qz += skd(face, 2) + skd(sd, 2);
				qd = face ^ 1;
			}
			int cur = get(qx, qy, qz);
			if (sk_can_replace(x, y, z, qx, qy, qz, qd, cur) && sk_valid(cur, qx, qy, qz, qd)) {
				int base = sk_is_vein(cur) ? sk_code(cur) : (cur == sk[SK_S_WATER] ? 64 : 0);
				set(qx, qy, qz, sk[SK_STATE + (base | (1 << qd))], W_FORCE);
				return true;
			}
		}
		return false;
	}
	int sk_spread_all(int st, int x, int y, int z, bool same_only) {
		static const int ALL[3] = {0, 1, 2}, SAME[1] = {0};
		int n = 0;
		bool other = !sk_is_vein(st);
		for (int sd = 0; sd < 6; sd++) {
			if (!(other || sk_has(st, sd))) continue;
			for (int face = 0; face < 6; face++)
				if (sk_spread_one(st, x, y, z, sd, face, same_only ? 1 : 3, same_only ? SAME : ALL)) n++;
		}
		return n;
	}
	// SculkVeinBlock.regrow
	bool sk_regrow(int x, int y, int z, int st, int faces) {
		int code = 0;
		for (int d = 0; d < 6; d++)
			if (((faces >> d) & 1) && sk_sturdy(sk_at(x, y, z, d))) code |= 1 << d;
		if (code == 0) return false;
		if (sk_fluid(st)) code |= 64;
		set(x, y, z, sk[SK_STATE + code], W_FORCE);
		return true;
	}
	bool sk_spread_vein(int beh, int x, int y, int z, int st, int faces) {
		if (beh == 0) {
			if (faces < 0) return sk_spread_all(get(x, y, z), x, y, z, true) > 0;
			if (faces != 0) return (st == 0 || sk_fluid(st)) && sk_regrow(x, y, z, st, faces);
		}
		return sk_spread_all(st, x, y, z, false) > 0;
	}
	// SculkVeinBlock.onDischarged: faces against sculk drop off; no face left -> air / water
	void sk_discharged(int beh, int st, int x, int y, int z) {
		if (beh != 2 || !sk_is_vein(st)) return;
		int code = sk_code(st);
		for (int d = 0; d < 6; d++)
			if (((code >> d) & 1) && bid(sk_at(x, y, z, d)) == sk[SK_B_SCULK]) code &= ~(1 << d);
		set(x, y, z, (code & 63) == 0 ? ((code & 64) ? sk[SK_S_WATER] : 0) : sk[SK_STATE + code], W_FORCE);
	}
	bool sk_place_sculk(int x, int y, int z) {
		int st = get(x, y, z);
		int ord[6] = {0, 1, 2, 3, 4, 5};
		for (int k = 6; k > 1; k--) { int j = (int)r.next_int_bound(k); std::swap(ord[k - 1], ord[j]); }
		for (int k = 0; k < 6; k++) {
			int d = ord[k];
			if (!sk_has(st, d)) continue;
			int bx = x + skd(d, 0), by = y + skd(d, 1), bz = z + skd(d, 2);
			if (!sk_repl(get(bx, by, bz))) continue;
			set(bx, by, bz, sk[SK_S_SCULK], W_FORCE);
			sk_spread_all(sk[SK_S_SCULK], bx, by, bz, false);
			for (int d2 = 0; d2 < 6; d2++) {
				if (d2 == (d ^ 1)) continue;
				int qx = bx + skd(d2, 0), qy = by + skd(d2, 1), qz = bz + skd(d2, 2);
				int s2 = get(qx, qy, qz);
				if (sk_is_vein(s2)) sk_discharged(2, s2, qx, qy, qz);
			}
			return true;
		}
		return false;
	}
	bool sk_can_growth(int x, int y, int z) const {
		int a = get(x, y + 1, z);
		if (!(a == 0 || (a > 0 && bid(a) == sk[SK_B_WATER]))) return false;
		int n = 0;
		for (int qy = y; qy <= y + 2; qy++)
			for (int qz = z - 4; qz <= z + 4; qz++)
				for (int qx = x - 4; qx <= x + 4; qx++) {
					int b = bid(get(qx, qy, qz));
					if (b == sk[SK_B_SENSOR] || b == sk[SK_B_SHRIEK]) n++;
					if (n > 2) return false;
				}
		return true;
	}
	int sk_use_charge(int beh, SkC &cu, int ox, int oy, int oz, bool convert) {
		int i = cu.charge;
		if (beh == 0) return cu.decay > 0 ? i : 0;
		if (beh == 2) {
			if (convert && sk_place_sculk(cu.x, cu.y, cu.z)) return i - 1;
			return r.next_int_bound(5) == 0 ? (int)std::floor(i * 0.5f) : i;
		}
		if (i == 0 || r.next_int_bound(5) != 0) return i;
		bool near = cu.x == ox && cu.y == oy && cu.z == oz;
		if (!near && sk_can_growth(cu.x, cu.y, cu.z)) {
			if ((int)r.next_int_bound(50) < i) {
				int above = get(cu.x, cu.y + 1, cu.z);
				bool wet = sk_fluid(above);
				int g = r.next_int_bound(11) == 0 ? (wet ? sk[SK_S_SHRIEK_WL] : sk[SK_S_SHRIEK]) : (wet ? sk[SK_S_SENSOR_WL] : sk[SK_S_SENSOR]);
				set(cu.x, cu.y + 1, cu.z, g, W_FORCE);
			}
			return std::max(0, i - 50);
		}
		if (r.next_int_bound(10) != 0) return i;
		if (near) return i - 1;
		double dx = cu.x - ox, dy = cu.y - oy, dz = cu.z - oz;
		float f = (float)std::sqrt(dx * dx + dy * dy + dz * dz) - 1.0f;
		f = f * f;
		float f1 = std::min(1.0f, f / (float)(23 * 23));
		return i - std::max(1, (int)(i * f1 * 0.5f));
	}
	bool sk_clear(int x, int y, int z, int d) const { return !sk_sturdy(sk_at(x, y, z, d)); }
	bool sk_unobstructed(int x, int y, int z, int qx, int qy, int qz) const {
		int dx = qx - x, dy = qy - y, dz = qz - z;
		if (std::abs(dx) + std::abs(dy) + std::abs(dz) == 1) return true;
		int ddx = dx < 0 ? 4 : 5, ddy = dy < 0 ? 0 : 1, ddz = dz < 0 ? 2 : 3;
		if (dx == 0) return sk_clear(x, y, z, ddy) || sk_clear(x, y, z, ddz);
		if (dy == 0) return sk_clear(x, y, z, ddx) || sk_clear(x, y, z, ddz);
		return sk_clear(x, y, z, ddx) || sk_clear(x, y, z, ddy);
	}
	bool sk_substrate(int st, int x, int y, int z) const {
		if (!sk_is_vein(st)) return false;
		for (int d = 0; d < 6; d++) if (sk_has(st, d) && sk_repl(sk_at(x, y, z, d))) return true;
		return false;
	}
	// ChargeCursor.getValidMovementPos: the 18 non-corner neighbours shuffled; a sculk / vein block reachable, the first
	// with substrate access wins, else the last one seen
	bool sk_move(int x, int y, int z, int &ox, int &oy, int &oz) {
		static int NC[18][3];
		static bool init = false;
		if (!init) {
			int k = 0;
			for (int cz = -1; cz <= 1; cz++)
				for (int cy = -1; cy <= 1; cy++)
					for (int cx = -1; cx <= 1; cx++)
						if ((cx == 0 || cy == 0 || cz == 0) && !(cx == 0 && cy == 0 && cz == 0)) { NC[k][0] = cx; NC[k][1] = cy; NC[k][2] = cz; k++; }
			init = true;
		}
		int idx[18];
		for (int k = 0; k < 18; k++) idx[k] = k;
		for (int k = 18; k > 1; k--) { int j = (int)r.next_int_bound(k); std::swap(idx[k - 1], idx[j]); }
		bool found = false;
		for (int k = 0; k < 18; k++) {
			int qx = x + NC[idx[k]][0], qy = y + NC[idx[k]][1], qz = z + NC[idx[k]][2];
			int qs = get(qx, qy, qz);
			if (sk_beh(qs) != 0 && sk_unobstructed(x, y, z, qx, qy, qz)) {
				ox = qx; oy = qy; oz = qz;
				found = true;
				if (sk_substrate(qs, qx, qy, qz)) break;
			}
		}
		return found;
	}
	void sk_update(SkC &cu, int ox, int oy, int oz, bool convert) {
		if (cu.charge <= 0) return;
		if (cu.upd > 0) { cu.upd--; return; }
		int st = get(cu.x, cu.y, cu.z);
		int beh = sk_beh(st);
		if (convert && sk_spread_vein(beh, cu.x, cu.y, cu.z, st, cu.faces) && beh != 1) {
			st = get(cu.x, cu.y, cu.z);
			beh = sk_beh(st);
		}
		cu.charge = sk_use_charge(beh, cu, ox, oy, oz, convert);
		if (cu.charge <= 0) { sk_discharged(beh, st, cu.x, cu.y, cu.z); return; }
		int nx, ny, nz;
		if (sk_move(cu.x, cu.y, cu.z, nx, ny, nz)) {
			sk_discharged(beh, st, cu.x, cu.y, cu.z);
			cu.x = nx; cu.y = ny; cu.z = nz;
			double dx = cu.x - ox, dz = cu.z - oz;
			if (!(dx * dx + dz * dz < 225.0)) { cu.charge = 0; return; }
			st = get(nx, ny, nz);
		}
		int nb = sk_beh(st);
		if (nb != 0) cu.faces = nb == 2 ? (sk_code(st) & 63) : 0;
		cu.decay = beh == 0 ? std::max(cu.decay - 1, 0) : 1;
		cu.upd = 1;
	}
	bool sculk_patch(const int32_t *n, int x, int y, int z) {
		sk = n;
		int s0 = get(x, y, z);
		if (sk_beh(s0) == 0) {
			if (!(s0 == 0 || s0 == n[SK_S_WATER])) return false;
			bool any = false;
			for (int d = 0; d < 6 && !any; d++) {
				int s = sk_at(x, y, z, d);
				any = s > 0 && (flags(s) & c.F_FULL_SHAPE) && (flags(s) & c.F_COLLIDE);
			}
			if (!any) return false;
		}
		std::vector<SkC> cur, nxt;
		int rounds = n[SK_SPREAD] + n[SK_GROW];
		for (int j = 0; j < rounds; j++) {
			for (int k = 0; k < n[SK_CC]; k++) {
				int ch = n[SK_AMT];
				while (ch > 0) {
					int i = std::min(ch, 1000);
					if (cur.size() < 32) cur.push_back(SkC{x, y, z, i, 1, 0, -1});
					ch -= i;
				}
			}
			bool convert = j < n[SK_SPREAD];
			for (int l = 0; l < n[SK_ATT] && !cur.empty(); l++) {
				nxt.clear();
				for (auto &cu : cur) {
					if (std::abs(cu.x - x) + std::abs(cu.y - y) + std::abs(cu.z - z) > 1024) continue;
					sk_update(cu, x, y, z, convert);
					if (cu.charge > 0) nxt.push_back(cu);
				}
				cur.swap(nxt);
			}
			cur.clear();
		}
		int rare = n[SK_RARE] >= 0 ? (int)ip(n[SK_RARE]) : 0;
		for (int k = 0; k < rare; k++) {
			int qx = x + (int)r.next_int_bound(5) - 2, qz = z + (int)r.next_int_bound(5) - 2;
			if (get(qx, y, qz) == 0 && sk_sturdy(get(qx, y - 1, qz))) set(qx, y, qz, n[SK_S_SHRIEK], W_FORCE);
		}
		return true;
	}

	bool disk(const int32_t *n, int x, int y, int z) {
		int64_t rad = ip(n[3]);
		int half = n[4];
		bool any = false;
		for (int64_t dx = -rad; dx <= rad; dx++)
			for (int64_t dz = -rad; dz <= rad; dz++) {
				if (dx * dx + dz * dz > rad * rad) continue;
				for (int dy = half; dy > -half - 1; dy--) {
					int qx = x + (int)dx, qy = y + dy, qz = z + (int)dz;
					if (test(n[2], qx, qy, qz)) {
						int st = provide(n[1], qx, qy, qz);
						if (st >= 0) { set(qx, qy, qz, st, W_FORCE); any = true; }
					}
				}
			}
		return any;
	}
	bool veg_patch(const int32_t *n, int x, int y, int z) {
		int64_t rad = ip(n[4]) + 1;
		const uint8_t *mask = c.M.data() + n[3];
		size_t mlen = c.M.size() - (size_t)n[3];
		double chance = F[n[5]];
		bool any = false;
		for (int64_t dx = -rad; dx <= rad; dx++)
			for (int64_t dz = -rad; dz <= rad; dz++) {
				if (std::llabs(dx) == rad && std::llabs(dz) == rad && r.next_bool()) continue;
				int qx = x + (int)dx, qy = y - 1, qz = z + (int)dz;
				int st = get(qx, qy, qz);
				if (st <= 0 || (size_t)st >= mlen || !mask[st] || get(qx, qy + 1, qz) != 0) continue;
				int gst = provide(n[1], qx, qy, qz);
				set(qx, qy, qz, gst, W_FORCE);
				any = true;
				if (r.next_float() < chance) sub(n[2], qx, qy + 1, qz);
			}
		return any;
	}

	// ---------------------------------------------------------------- ore / scattered ore (Features._ore / _scattered_ore)
	bool can_place_ore(int tnode, int st, int x, int y, int z, double discard) {
		if (!rule(tnode, st, y)) return false;
		if (discard <= 0.0) return true;
		if (discard < 1.0 && r.next_float() >= discard) return true;
		static const int D[6][3] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
		for (int k = 0; k < 6; k++) if (get(x + D[k][0], y + D[k][1], z + D[k][2]) == 0) return false;
		return true;
	}
	bool ore(const int32_t *n, int ox, int oy, int oz) {
		int size = n[1];
		double discard = F[n[2]];
		int nt = n[3];
		const int32_t *tg = n + 4;
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
		int nn = ox - cg - i;
		int oo = oy - 2 - i;
		int pz = oz - cg - i;
		int q = 2 * (cg + i);
		bool ok = false;
		for (int s = nn; s <= nn + q && !ok; s++)
			for (int t = pz; t <= pz + q; t++)
				if (oo <= height(1, s, t)) { ok = true; break; }
		if (!ok) return false;
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
			int x0 = std::max((int)std::floor(cx - rad), nn);
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
						if (aj * aj + al * al + an * an >= 1.0 || yy < MIN_Y || yy >= MAX_Y) continue;
						int64_t key = ((int64_t)(xx & 0x3FFFFFF) << 38) | ((int64_t)(zz & 0x3FFFFFF) << 12) | (int64_t)((yy + 2048) & 0xFFF);
						if (!seen.insert(key).second) continue;
						if (!in_region(xx, zz)) continue;
						int st = get(xx, yy, zz);
						for (int t = 0; t < nt; t++) {
							if (can_place_ore(tg[t * 2], st, xx, yy, zz, discard)) {
								set(xx, yy, zz, tg[t * 2 + 1], W_FORCE);
								placed = true;
								break;
							}
						}
					}
				}
			}
		}
		return placed;
	}
	int spread(int s) { double a = r.next_float(); double b = r.next_float(); return (int)std::round((a - b) * s); }
	bool scattered(const int32_t *n, int ox, int oy, int oz) {
		int size = n[1];
		double discard = F[n[2]];
		int nt = n[3];
		const int32_t *tg = n + 4;
		int64_t cnt = r.next_int_bound(size + 1);
		for (int64_t k = 0; k < cnt; k++) {
			int sp = (int)std::min<int64_t>(k, 7);
			int dx = spread(sp);
			int dy = spread(sp);
			int dz = spread(sp);
			int x = ox + dx, y = oy + dy, z = oz + dz;
			int st = get(x, y, z);
			for (int t = 0; t < nt; t++) {
				if (can_place_ore(tg[t * 2], st, x, y, z, discard)) {
					set(x, y, z, tg[t * 2 + 1], W_FORCE);
					break;
				}
			}
		}
		return true;
	}
};

bool fn_fx_config(const Args &a, void *ret) {
	const void *d = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	if (!d) return false;
	FxCfg *c = new FxCfg();
	rd_i32(array_get(d, 0), c->I);
	rd_f64(array_get(d, 1), c->F);
	rd_u8(array_get(d, 2), c->M);
	rd_u8(array_get(d, 3), c->BS);
	rd_i32(array_get(d, 4), c->flags);
	rd_i32(array_get(d, 5), c->stblock);
	rd_u8(array_get(d, 6), c->cat);
	rd_u8(array_get(d, 7), c->below);
	rd_i32(array_get(d, 8), c->half_up);
	rd_i32(array_get(d, 9), c->wl);
	rd_i32(array_get(d, 10), c->consts);
	if (size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, d) > 12) {
		rd_i32(array_get(d, 11), c->simplex);
		rd_u8(array_get(d, 12), c->airn);
	}
	if (size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, d) > 13) rd_u8(array_get(d, 13), c->logn);
	if (c->consts.size() >= 10) c->F_LEAVES = c->consts[9];
	if (c->simplex.size() < 256) c->simplex.assign(256, 0);
	if (c->consts.size() >= 9) {
		c->F_LIQUID = c->consts[0]; c->F_WATERLOGGED = c->consts[1]; c->F_COLLIDE = c->consts[2]; c->F_REPLACEABLE = c->consts[3];
		c->F_FULL_SHAPE = c->consts[4]; c->F_OPAQUE = c->consts[5]; c->F_LAVA = c->consts[6]; c->gen_min_y = c->consts[7]; c->gen_depth = c->consts[8];
	}
	if (c->F.empty()) c->F.push_back(0.0);
	if (c->I.empty()) c->I.push_back(0);
	int64_t h;
	{
		std::lock_guard<std::mutex> lk(g_m);
		g_cfgs.push_back(c);
		h = (int64_t)g_cfgs.size() - 1;
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, h);
	return true;
}

// fx_run(handle, pf, bset_offset, flat, info, gs, gf, bio, rng, origin)
bool fn_fx_run(const Args &a, void *ret) {
	const FxCfg *c;
	{
		std::lock_guard<std::mutex> lk(g_m);
		int64_t h = a.i(0);
		if (h < 0 || h >= (int64_t)g_cfgs.size()) return false;
		c = g_cfgs[h];
	}
	int pf = (int)a.i(1);
	int bso = (int)a.i(2);
	const void *flat = a.obj(3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *info = a.obj(4, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *gs = a.obj(5, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *gf = a.obj(6, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *bio = a.obj(7, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	const void *rng = a.obj(8, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *org = a.obj(9, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	if (!flat || !info || !gs || !gf || !bio || !rng || !org) return false;
	if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, flat) != 9 * 98304 || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, info) < 20) return false;
	if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, gs) < 2304 || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, gf) < 2304 || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, bio) < 9 * 1536) return false;
	if (pf < 0 || pf >= (int)c->I.size() || bso < 0 || bso > (int)c->BS.size()) return false;
	Fx fx(*c);
	// job-private region buffer (see header): written in place, never shared with another array
	fx.flat = const_cast<int32_t *>(i32(flat));
	const int32_t *in = i32(info);
	fx.fx0 = in[0]; fx.fz0 = in[1];
	for (int k = 0; k < 9; k++) { fx.has[k] = (uint8_t)in[2 + k]; fx.hst[k] = (uint8_t)in[11 + k]; }
	fx.gs = i32(gs); fx.gf = i32(gf); fx.bio = bytes(bio);
	if (const void *hlv = a.obj(10, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)) {
		if (size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, hlv) >= 4 * 2304) fx.hl = const_cast<int32_t *>(i32(hlv));   // job-private, in place
	}
	fx.bset = c->BS.data() + bso;
	fx.nbio = (int)(c->BS.size() - bso);
	int64_t lo = 0, hi = 0;
	to_type(GDEXTENSION_VARIANT_TYPE_INT)(&lo, (GDExtensionVariantPtr)array_get(rng, 0));
	to_type(GDEXTENSION_VARIANT_TYPE_INT)(&hi, (GDExtensionVariantPtr)array_get(rng, 1));
	fx.r.lo = lo; fx.r.hi = hi;
	const int32_t *o = i32(org);
	fx.writes.reserve(4096);
	fx.chain(pf, 0, o[0], o[1], o[2]);
	Owned w(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, w.ptr(), (int64_t)fx.writes.size());
	if (!fx.writes.empty()) memcpy(i32_w(w.ptr()), fx.writes.data(), fx.writes.size() * sizeof(int32_t));
	Owned be(GDEXTENSION_VARIANT_TYPE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, be.ptr(), (int64_t)fx.bes.size());
	for (size_t k = 0; k < fx.bes.size(); k++) array_set_int(be.ptr(), (int64_t)k, fx.bes[k]);
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 4);
	array_set_int(ret, 0, fx.r.lo);
	array_set_int(ret, 1, fx.r.hi);
	array_set_native(ret, 2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, w.ptr());
	array_set_native(ret, 3, GDEXTENSION_VARIANT_TYPE_ARRAY, be.ptr());
	return true;
}

} // namespace

void register_featx(const char *cls) {
	register_method(cls, "fx_config", fn_fx_config, 1);
	register_method(cls, "fx_run", fn_fx_run, 10);
}
