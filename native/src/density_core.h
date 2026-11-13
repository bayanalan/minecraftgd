// Shared density-function engine (graph, noises, evaluator) used by density.cpp and terrain.cpp.
#pragma once
#include "native.h"
#include <vector>
#include <cmath>
#include <mutex>
#include <unordered_map>
#include <algorithm>
#include <cstdint>

namespace rn {
using namespace gdx;


enum K { CONST, ADD, MUL, SUB, DIV, MIN, MAX, ABS, SQUARE, CUBE, HALF_NEG, QUARTER_NEG, SQUEEZE, NEGATE, CLAMP,
	RANGE, LERP, GRADIENT, NOISE, SHIFT_A, SHIFT_B, SHIFT, BLENDED, INTERP, PASS, ONE, ZERO, SPLINE, INTERVAL,
	TOP_SURFACE, END_ISLANDS, DIST };

const int MIN_Y = -64, HEIGHT = 384;
const double WRAP = 33554432.0;
const double GX[16] = {1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0};
const double GY[16] = {1.0, 1.0, -1.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0};
const double GZ[16] = {0.0, 0.0, 0.0, 0.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, -1.0, 0.0, 1.0, 0.0, -1.0};

struct Improved {
	int32_t p[256];
	double xo, yo, zo;
	double noise(double x, double y, double z, double y_scale, double y_max) const {
		double d = x + xo, e = y + yo, f = z + zo;
		double fi = std::floor(d), fj = std::floor(e), fk = std::floor(f);
		int64_t a = (int64_t)fi, b = (int64_t)fj, c = (int64_t)fk;
		double dx = d - fi, dys = e - fj, dz = f - fk;
		double dy = dys;
		if (y_scale != 0.0) {
			double m = dys;
			if (y_max >= 0.0 && y_max < dys) m = y_max;
			dy = dys - std::floor(m / y_scale + 1.0e-7) * y_scale;
		}
		int64_t hh = p[a & 255], ii = p[(a + 1) & 255];
		int64_t jj = p[(hh + b) & 255], kk = p[(hh + b + 1) & 255];
		int64_t ll = p[(ii + b) & 255], mm = p[(ii + b + 1) & 255];
		double dx1 = dx - 1.0, dy1 = dy - 1.0, dz1 = dz - 1.0;
		int g = p[(jj + c) & 255] & 15; double n = GX[g] * dx + GY[g] * dy + GZ[g] * dz;
		g = p[(ll + c) & 255] & 15; double o = GX[g] * dx1 + GY[g] * dy + GZ[g] * dz;
		g = p[(kk + c) & 255] & 15; double q = GX[g] * dx + GY[g] * dy1 + GZ[g] * dz;
		g = p[(mm + c) & 255] & 15; double r = GX[g] * dx1 + GY[g] * dy1 + GZ[g] * dz;
		g = p[(jj + c + 1) & 255] & 15; double s = GX[g] * dx + GY[g] * dy + GZ[g] * dz1;
		g = p[(ll + c + 1) & 255] & 15; double t = GX[g] * dx1 + GY[g] * dy + GZ[g] * dz1;
		g = p[(kk + c + 1) & 255] & 15; double u = GX[g] * dx + GY[g] * dy1 + GZ[g] * dz1;
		g = p[(mm + c + 1) & 255] & 15; double v = GX[g] * dx1 + GY[g] * dy1 + GZ[g] * dz1;
		double sx = dx * dx * dx * (dx * (dx * 6.0 - 15.0) + 10.0);
		double sy = dys * dys * dys * (dys * (dys * 6.0 - 15.0) + 10.0);
		double sz = dz * dz * dz * (dz * (dz * 6.0 - 15.0) + 10.0);
		double a1 = n + sx * (o - n), a2 = q + sx * (r - q), b1 = s + sx * (t - s), b2 = u + sx * (v - u);
		double c1 = a1 + sy * (a2 - a1), c2 = b1 + sy * (b2 - b1);
		return c1 + sz * (c2 - c1);
	}
};

// MCNoise.Normal flattened octaves (sampler a then b)
struct Normal {
	std::vector<Improved> oct;
	std::vector<double> in, amp;
	double value(double x, double y, double z) const {
		double total = 0.0;
		size_t n = oct.size();
		for (size_t k = 0; k < n; k++) {
			double e = in[k];
			double ax = x * e, ay = y * e, az = z * e;
			ax -= std::floor(ax / WRAP + 0.5) * WRAP;
			ay -= std::floor(ay / WRAP + 0.5) * WRAP;
			az -= std::floor(az / WRAP + 0.5) * WRAP;
			total += amp[k] * oct[k].noise(ax, ay, az, 0.0, 0.0);
		}
		return total;
	}
};

struct Blended {
	Improved main_oct[8], min_oct[16], max_oct[16];
	bool main_p[8], min_p[16], max_p[16];
	double xz_mul, y_mul, xz_factor, y_factor, smear;
	double value(double x, double y, double z) const {
		double d = x * xz_mul, e = y * y_mul, f = z * xz_mul;
		double g = d / xz_factor, h = e / y_factor, i = f / xz_factor;
		double j = y_mul * smear;
		double k = j / y_factor;
		double l = 0.0, m = 0.0, n = 0.0, o = 1.0;
		for (int p = 0; p < 8; p++) {
			if (main_p[p]) {
				double ax = g * o, ay = h * o, az = i * o;
				n += main_oct[p].noise(ax - std::floor(ax / WRAP + 0.5) * WRAP, ay - std::floor(ay / WRAP + 0.5) * WRAP, az - std::floor(az / WRAP + 0.5) * WRAP, k * o, h * o) / o;
			}
			o /= 2.0;
		}
		double q = (n / 10.0 + 1.0) / 2.0;
		bool hi = q >= 1.0, lo = q <= 0.0;
		o = 1.0;
		for (int r = 0; r < 16; r++) {
			double sd = d * o, td = e * o, ud = f * o;
			double s = sd - std::floor(sd / WRAP + 0.5) * WRAP;
			double t = td - std::floor(td / WRAP + 0.5) * WRAP;
			double u = ud - std::floor(ud / WRAP + 0.5) * WRAP;
			double v = j * o;
			if (!hi && min_p[r]) l += min_oct[r].noise(s, t, u, v, td) / o;
			if (!lo && max_p[r]) m += max_oct[r].noise(s, t, u, v, td) / o;
			o /= 2.0;
		}
		double a = l / 512.0, b = m / 512.0;
		double res;
		if (q < 0.0) res = a; else if (q > 1.0) res = b; else res = a + q * (b - a);
		return res / 128.0;
	}
};

struct Simplex {
	int32_t p[256];
	double value2(double d, double e) const {
		const double F2 = 0.3660254037844386, G2 = 0.21132486540518713;
		double h = (d + e) * F2;
		int64_t i = (int64_t)std::floor(d + h), j = (int64_t)std::floor(e + h);
		double k = (double)(i + j) * G2;
		double n = d - ((double)i - k), o = e - ((double)j - k);
		int pp = n > o ? 1 : 0, qq = n > o ? 0 : 1;
		double r = n - pp + G2, s = o - qq + G2;
		double t = n - 1.0 + 2.0 * G2, u = o - 1.0 + 2.0 * G2;
		int64_t v = i & 255, w = j & 255;
		int gi0 = p[(v + p[w & 255]) & 255] % 12;
		int gi1 = p[(v + pp + p[(w + qq) & 255]) & 255] % 12;
		int gi2 = p[(v + 1 + p[(w + 1) & 255]) & 255] % 12;
		double tot = 0.0;
		double c0 = 0.5 - n * n - o * o;
		if (c0 >= 0.0) { c0 *= c0; tot += c0 * c0 * (GX[gi0] * n + GY[gi0] * o); }
		double c1 = 0.5 - r * r - s * s;
		if (c1 >= 0.0) { c1 *= c1; tot += c1 * c1 * (GX[gi1] * r + GY[gi1] * s); }
		double c2 = 0.5 - t * t - u * u;
		if (c2 >= 0.0) { c2 *= c2; tot += c2 * c2 * (GX[gi2] * t + GY[gi2] * u); }
		return 70.0 * tot;
	}
};

static inline double f32(double v) { return (double)(float)v; }

// MCNoise.end_height (float32 emulation)
inline double end_height(const Simplex &sn, int64_t i, int64_t j) {
	int64_t k = i / 2, l = j / 2, m = i % 2, n = j % 2;
	double f = f32(100.0 - f32(f32(std::sqrt(f32((double)(i * i + j * j)))) * 8.0));
	f = std::min(80.0, std::max(-100.0, f));
	for (int64_t o = -12; o <= 12; o++) {
		int64_t q = k + o;
		for (int64_t pz = -12; pz <= 12; pz++) {
			int64_t r = l + pz;
			if (q * q + r * r > 4096 && sn.value2((double)q, (double)r) < -0.8999999761581421) {
				double g = f32(std::fmod(f32(f32(std::fabs((double)q) * 3439.0) + f32(std::fabs((double)r) * 147.0)), 13.0) + 9.0);
				double h = (double)(m - o * 2), s = (double)(n - pz * 2);
				double t = f32(100.0 - f32(f32(std::sqrt(h * h + s * s)) * g));
				t = std::min(80.0, std::max(-100.0, t));
				f = std::max(f, t);
			}
		}
	}
	return f;
}

struct Spline {
	int coord;
	std::vector<double> locs, ders, vals;
	std::vector<int> val_spline;   // -1 = constant vals[i], else nested spline index
};

struct Node {
	int k, a, b, c, axis, cxz, cy, is2d, lower, noise, blended, spline, funcs_off, funcs_n, end;
	double v0, v1, v2, v3, lo, hi;
};

struct Graph {
	std::vector<Node> nodes;
	std::vector<int> funcs;
	std::vector<double> thresholds;
	std::vector<Normal> noises;
	std::vector<Blended> blended;
	std::vector<Spline> splines;
	std::vector<Simplex> ends;
};

extern std::mutex g_mutex;
extern std::vector<Graph *> g_graphs;
const Graph *graph_of(int64_t h);

// ---------------------------------------------------------------- evaluation context (one per call, per thread)
struct Eval {
	const Graph &g;
	int x0, z0;
	bool has_chunk;
	int mode;   // 0 point (x,y,z interpolation order), 1 block (y,z,x)
	// per-point memo
	std::vector<double> memo;
	std::vector<uint32_t> stamp;
	uint32_t cur = 1;
	int px = 0, py = 0, pz = 0;
	// interpolation corner grids per INTERP node
	std::vector<std::vector<double>> corners;
	// 2D column cache: in-chunk columns x0..x0+16, z0..z0+16 (17x17), map elsewhere
	std::vector<double> c2;
	std::vector<uint8_t> c2ok;
	std::unordered_map<uint64_t, double> c2map;

	Eval(const Graph &gr, int cx, int cz, bool hc) : g(gr), x0(cx * 16), z0(cz * 16), has_chunk(hc), mode(0) {
		size_t n = g.nodes.size();
		memo.assign(n, 0.0);
		stamp.assign(n, 0);
		corners.resize(n);
		c2.assign(n * 289, 0.0);
		c2ok.assign(n * 289, 0);
	}

	double at(int n, int x, int y, int z) {
		// evaluate node n at a point different from the current memo point
		int sx = px, sy = py, sz = pz;
		uint32_t sc = cur;
		px = x; py = y; pz = z;
		cur = next_stamp();
		double v = ev(n, x, y, z);
		px = sx; py = sy; pz = sz;
		cur = sc;
		return v;
	}

	uint32_t stamp_ctr = 1;
	uint32_t next_stamp() { return ++stamp_ctr; }

	double ev(int n, int x, int y, int z) {
		const Node &d = g.nodes[n];
		if (d.k == CONST) return d.v0;
		if (d.is2d) {
			int lx = x - x0, lz = z - z0;
			if (lx >= 0 && lx <= 16 && lz >= 0 && lz <= 16) {
				size_t ci = (size_t)n * 289 + lz * 17 + lx;
				if (c2ok[ci]) return c2[ci];
				double v = compute(n, d, x, y, z);
				c2[ci] = v;
				c2ok[ci] = 1;
				return v;
			}
			uint64_t key = ((uint64_t)(uint32_t)n << 42) ^ ((uint64_t)(uint32_t)(x & 0x1FFFFF) << 21) ^ (uint64_t)(uint32_t)(z & 0x1FFFFF);
			auto it = c2map.find(key);
			if (it != c2map.end()) return it->second;
			double v = compute(n, d, x, y, z);
			c2map[key] = v;
			return v;
		}
		if (x == px && y == py && z == pz) {
			if (stamp[n] == cur) return memo[n];
			double v = compute(n, d, x, y, z);
			stamp[n] = cur;
			memo[n] = v;
			return v;
		}
		return compute(n, d, x, y, z);
	}

	double gradient(const Node &d, int t) const {
		if (d.v0 == d.v1) return d.v2;
		double f = ((double)t - d.v0) / (d.v1 - d.v0);
		f = std::min(1.0, std::max(0.0, f));
		return d.v2 + f * (d.v3 - d.v2);
	}

	// Corner values are computed on first use (a single column - Structures.first_free_height - needs only its own
	// 2 x 2 corner columns over a few cells; a whole chunk ends up computing all of them as before).
	std::vector<std::vector<uint8_t>> corner_ok;
	double corner(int n, const Node &d, int ix, int iy, int iz) {
		std::vector<double> &cv = corners[n];
		int nx = 16 / d.cxz + 1;
		if (cv.empty()) {
			int ny = HEIGHT / d.cy + 1;
			cv.assign((size_t)nx * ny * nx, 0.0);
			if (corner_ok.size() < corners.size()) corner_ok.resize(corners.size());
			corner_ok[n].assign(cv.size(), 0);
		}
		size_t i = ((size_t)iy * nx + iz) * nx + ix;
		if (corner_ok[n][i]) return cv[i];
		int saved_mode = mode;
		mode = 2;   // corner mode: nested interpolated nodes of the same cell size evaluate their input directly
		double v = at(d.a, x0 + ix * d.cxz, MIN_Y + iy * d.cy, z0 + iz * d.cxz);
		mode = saved_mode;
		cv[i] = v;
		corner_ok[n][i] = 1;
		return v;
	}

	double interp(int n, const Node &d, int x, int y, int z) {
		if (mode == 2) return ev(d.a, x, y, z);
		if (!has_chunk) return ev(d.a, x, y, z);
		int lx = x - x0, lz = z - z0, ly = y - MIN_Y;
		if (lx < 0 || lx > 15 || lz < 0 || lz > 15 || ly < 0 || ly >= HEIGHT) return ev(d.a, x, y, z);
		int ix = lx / d.cxz, iz = lz / d.cxz, iy = ly / d.cy;
		double c000 = corner(n, d, ix, iy, iz), c100 = corner(n, d, ix + 1, iy, iz);
		double c001 = corner(n, d, ix, iy, iz + 1), c101 = corner(n, d, ix + 1, iy, iz + 1);
		double c010 = corner(n, d, ix, iy + 1, iz), c110 = corner(n, d, ix + 1, iy + 1, iz);
		double c011 = corner(n, d, ix, iy + 1, iz + 1), c111 = corner(n, d, ix + 1, iy + 1, iz + 1);
		if (mode == 1 && d.cxz == 4 && d.cy == 8) {
			// GDScript cell path (_interp_cells): y, then z, then x
			double ty = (ly & 7) * 0.125;
			double y00 = c000 + ty * (c010 - c000);
			double y10 = c100 + ty * (c110 - c100);
			double y01 = c001 + ty * (c011 - c001);
			double y11 = c101 + ty * (c111 - c101);
			double tz = (lz & 3) * 0.25;
			double z0v = y00 + tz * (y01 - y00);
			double z1v = y10 + tz * (y11 - y10);
			double dz = z1v - z0v;
			int sx = lx & 3;
			if (sx == 0) return z0v;
			return z0v + (sx == 1 ? 0.25 : (sx == 2 ? 0.5 : 0.75)) * dz;
		}
		// DF._interp_at: x, then y, then z
		double tx = (double)(lx % d.cxz) / d.cxz, tz = (double)(lz % d.cxz) / d.cxz, ty = (double)(ly % d.cy) / d.cy;
		double x00 = c000 + tx * (c100 - c000);
		double x10 = c010 + tx * (c110 - c010);
		double x01 = c001 + tx * (c101 - c001);
		double x11 = c011 + tx * (c111 - c011);
		double y0 = x00 + ty * (x10 - x00);
		double y1 = x01 + ty * (x11 - x01);
		return y0 + tz * (y1 - y0);
	}

	double spline(int si, int x, int y, int z) {
		const Spline &sp = g.splines[si];
		double f = ev(sp.coord, x, y, z);
		const std::vector<double> &locs = sp.locs;
		const std::vector<double> &ders = sp.ders;
		int last = (int)locs.size() - 1;
		int lo = 0, hi = (int)locs.size();
		while (lo < hi) {
			int mid = (lo + hi) >> 1;
			if (f < locs[mid]) hi = mid; else lo = mid + 1;
		}
		int i = lo - 1;
		auto val = [&](int vi) -> double { return sp.val_spline[vi] >= 0 ? spline(sp.val_spline[vi], x, y, z) : sp.vals[vi]; };
		if (i < 0) {
			double v0s = val(0);
			return ders[0] == 0.0 ? v0s : v0s + ders[0] * (f - locs[0]);
		}
		if (i == last) {
			double vl = val(last);
			return ders[last] == 0.0 ? vl : vl + ders[last] * (f - locs[last]);
		}
		double gg = locs[i], hh = locs[i + 1];
		double kk = (f - gg) / (hh - gg);
		double m = val(i), nn = val(i + 1);
		double o = ders[i], p = ders[i + 1];
		double q = o * (hh - gg) - (nn - m);
		double r = -p * (hh - gg) + (nn - m);
		return (m + kk * (nn - m)) + kk * (1.0 - kk) * (q + kk * (r - q));
	}

	double compute(int n, const Node &d, int x, int y, int z) {
		switch (d.k) {
			case CONST: return d.v0;
			case ADD: return ev(d.a, x, y, z) + ev(d.b, x, y, z);
			case MUL: { double l = ev(d.a, x, y, z); return l == 0.0 ? 0.0 : l * ev(d.b, x, y, z); }
			case SUB: return ev(d.a, x, y, z) - ev(d.b, x, y, z);
			case DIV: { double dd = ev(d.b, x, y, z); return dd != 0.0 ? ev(d.a, x, y, z) / dd : 0.0; }
			case MIN: { double m1 = ev(d.a, x, y, z); if (m1 < g.nodes[d.b].lo) return m1; double m2 = ev(d.b, x, y, z); return m1 < m2 ? m1 : m2; }
			case MAX: { double m1 = ev(d.a, x, y, z); if (m1 > g.nodes[d.b].hi) return m1; double m2 = ev(d.b, x, y, z); return m1 > m2 ? m1 : m2; }
			case ABS: return std::fabs(ev(d.a, x, y, z));
			case SQUARE: { double s = ev(d.a, x, y, z); return s * s; }
			case CUBE: { double s = ev(d.a, x, y, z); return s * s * s; }
			case HALF_NEG: { double h = ev(d.a, x, y, z); return h > 0.0 ? h : h * 0.5; }
			case QUARTER_NEG: { double q = ev(d.a, x, y, z); return q > 0.0 ? q : q * 0.25; }
			case SQUEEZE: { double e = std::min(1.0, std::max(-1.0, ev(d.a, x, y, z))); return e / 2.0 - e * e * e / 24.0; }
			case NEGATE: return -ev(d.a, x, y, z);
			case CLAMP: { double v = ev(d.a, x, y, z); return std::min(d.v1, std::max(d.v0, v)); }
			case PASS: return ev(d.a, x, y, z);
			case ONE: return 1.0;
			case ZERO: return 0.0;
			case GRADIENT: return gradient(d, d.axis == 1 ? y : (d.axis == 0 ? x : z));
			case LERP: {
				double al = ev(d.a, x, y, z);
				if (al == 0.0) return ev(d.b, x, y, z);
				if (al == 1.0) return ev(d.c, x, y, z);
				double f1 = ev(d.b, x, y, z);
				return f1 + al * (ev(d.c, x, y, z) - f1);
			}
			case RANGE: {
				double iv = ev(d.a, x, y, z);
				return (iv >= d.v0 && iv < d.v1) ? ev(d.b, x, y, z) : ev(d.c, x, y, z);
			}
			case INTERVAL: {
				double iv2 = ev(d.a, x, y, z);
				int gi = 0;
				int tn = d.funcs_n - 1;
				while (gi < tn && iv2 >= g.thresholds[d.funcs_off - 0 + gi]) gi++;
				return ev(g.funcs[d.funcs_off + gi], x, y, z);
			}
			case NOISE: {
				double ppx = x * d.v0, ppy = y * d.v1, ppz = z * d.v0;
				if (d.a >= 0) {
					ppx += ev(d.a, x, y, z);
					if (d.b >= 0) ppy += ev(d.b, x, y, z);
					if (d.c >= 0) ppz += ev(d.c, x, y, z);
				}
				return g.noises[d.noise].value(ppx, ppy, ppz);
			}
			case SHIFT_A: return g.noises[d.noise].value(x * 0.25, 0.0, z * 0.25) * 4.0;
			case SHIFT_B: return g.noises[d.noise].value(z * 0.25, x * 0.25, 0.0) * 4.0;
			case SHIFT: return g.noises[d.noise].value(x * 0.25, y * 0.25, z * 0.25) * 4.0;
			case BLENDED: return g.blended[d.blended].value((double)x, (double)y, (double)z);
			case INTERP: return interp(n, d, x, y, z);
			case SPLINE: return spline(d.spline, x, y, z);
			case TOP_SURFACE: {
				int saved = mode;
				mode = 0;   // GDScript evaluates find_top_surface through DF.point
				int64_t top = (int64_t)std::floor(at(d.c, x, 0, z));
				int cell = (int)d.v0;
				int64_t yy = (int64_t)std::floor((double)top / d.v0) * cell;
				double res = (double)d.lower;
				while (yy >= d.lower) {
					if (at(d.a, x, (int)yy, z) > 0.0) { res = (double)yy; break; }
					yy -= cell;
				}
				mode = saved;
				return res;
			}
			case END_ISLANDS: {
				int64_t kx = x / 8, kz = z / 8;
				return (end_height(g.ends[d.end], kx, kz) - 8.0) / 128.0;
			}
			case DIST: {
				float fx = (float)(x - d.v0), fy = (float)(y - d.v1), fz = (float)(z - d.v2);
				return (double)std::sqrt(fx * fx + fy * fy + fz * fz);
			}
		}
		return 0.0;
	}
};


} // namespace rn
