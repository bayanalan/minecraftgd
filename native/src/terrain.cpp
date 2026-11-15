// Native terrain stages after density, bit-exact ports of the GDScript reference:
//   noise fill + aquifer  (VanillaGenerator.generate fill loop, scripts/world/aquifer.gd)
//   cave / canyon carvers (scripts/world/carvers.gd)
// API (RecraftNative):
//   tg_config(graph, desc: Array) -> [cfg]
//   tg_begin(cfg, cx, cz) -> [job, col: PackedInt32Array(98304), skip_above]
//   tg_carve(job, col, src_biomes: PackedInt32Array(289)) -> [col]
//   tg_end(job) -> []
//   tg_surface_grid(cfg, gx, gz) -> [float]   (preliminary surface at grid point, shared cache)
#include "density_core.h"
#include "rng.h"
#include <cstdio>
#include <cstdlib>
#ifdef _WIN32
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#undef CONST   // windef.h macro; clashes with the density node kind
#endif

using namespace gdx;
using namespace rn;

namespace {

static const void *arr_of(const void *v) { return internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)v); }
static int64_t int_of(const void *v) { int64_t r = 0; to_type(GDEXTENSION_VARIANT_TYPE_INT)(&r, (GDExtensionVariantPtr)v); return r; }
static void read_i32(const void *v, std::vector<int> &out) {
	const void *a = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)v);
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, a);
	const int32_t *d = i32(a);
	out.assign(d, d + n);
}
static void read_f64(const void *v, std::vector<double> &out) {
	const void *a = internal(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY)((GDExtensionVariantPtr)v);
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, a);
	const double *d = f64(a);
	out.assign(d, d + n);
}
static void read_u8(const void *v, std::vector<uint8_t> &out) {
	const void *a = internal(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)((GDExtensionVariantPtr)v);
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, a);
	const uint8_t *d = bytes(a);
	out.assign(d, d + n);
}

static inline int64_t floordiv(int64_t a, int64_t b) { int64_t q = a / b; if ((a % b != 0) && ((a < 0) != (b < 0))) q--; return q; }
// Godot Math::remap = lerp(ostart, ostop, inverse_lerp(istart, istop, v))
static inline double remap(double v, double i0, double i1, double o0, double o1) { return o0 + (o1 - o0) * ((v - i0) / (i1 - i0)); }
static inline double clampd(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }

const double PI = 3.141592653589793;
const double TAU = 6.283185307179586;

// float / int providers (Carvers.fsample / isample)
struct FProv { int k; double a, b, c; };   // 0 const a, 1 uniform [a,b), 2 trapezoid (min a, max b, plateau c)
struct IProv { int k; int64_t a, b; };      // 0 const a, 1 uniform anchors (checked), 2 uniform ints, 3 very_biased, 4 biased

static double fsample(LegacyRandom &r, const FProv &p) {
	switch (p.k) {
		case 1: return p.a + r.next_float() * (p.b - p.a);
		case 2: {
			double f = p.b - p.a, g = (f - p.c) / 2.0, h = f - g;
			double n1 = r.next_float();
			double v = p.a + n1 * h;
			double n2 = r.next_float();
			return v + n2 * g;
		}
		default: return p.a;
	}
}
static int64_t mth_next(LegacyRandom &r, int64_t a, int64_t b) { int64_t bound = b - a + 1; if (bound < 1) bound = 1; return r.next_int_bound(bound) + a; }
static int64_t isample(LegacyRandom &r, const IProv &p) {
	switch (p.k) {
		case 1: return p.b >= p.a ? p.a + r.next_int_bound(p.b - p.a + 1) : p.a;
		case 2: return p.a + r.next_int_bound(p.b - p.a + 1);
		case 3: { int64_t k = mth_next(r, p.a + 1, p.b); int64_t l = mth_next(r, p.a, k - 1); return mth_next(r, p.a, l); }
		case 4: { int64_t inner = r.next_int_bound(p.b - p.a + 1); return p.a + r.next_int_bound(inner + 1); }
		default: return p.a;
	}
}

struct Carver {
	int type = 0;            // 0 none/other, 1 cave, 2 canyon
	bool empty = true;
	double probability = 0.0;
	IProv count{0, 14, 0}, y{0, 64, 0};
	FProv hrm{0, 1, 0, 0}, vrm{0, 1, 0, 0}, floor_level{0, -0.7, 0, 0}, room_vrm{0, 0.5, 0, 0}, thickness{0, 2, 0, 0};
	bool weird = false;
	double start_vrm = 1.0;
	// canyon
	FProv vrot{0, 0, 0, 0}, y_scale{0, 3, 0, 0}, c_thick{0, 2, 0, 0}, dist{0, 1, 0, 0}, hrf{0, 1, 0, 0};
	int smooth = 3;
	double vrdf = 1.0, vrcf = 0.0;
};

// SurfaceRules (scripts/world/surface_rules.gd) flattened by SurfaceRules.export_native()
enum SR { R_SEQ, R_COND, R_BLOCK, R_BANDS, R_VEIN, R_NONE };
enum SC { C_BIOME, C_NOISE, C_VGRAD, C_YABOVE, C_WATER, C_DEPTH, C_NOT, C_STEEP, C_HOLE, C_ABOVE_PRELIM, C_TEMP, C_TRUE };
struct SurfCfg {
	bool ok = false;
	int root = 0, n_surface = 0, n_secondary = 0, n_band = 0, p_ore = 0, p_root = 0, nb = 0, sea = 63;
	std::vector<int> rints, kids, cints, vints, bands;
	std::vector<double> cfl, vfl, temps;
	std::vector<uint8_t> bsets;
	std::vector<Normal> noises;
	std::vector<Positional> poss;
};

// Climate (scripts/world/climate.gd): column() + pick() with identical tie-breaking.
struct ClimateCfg {
	bool ok = false;           // multi-noise biomes for the chunk (not single-biome / End)
	bool src_ok = false;       // carver source biomes
	int single = -1;           // single-biome world: carver source biome
	int n = 0, ng = 0;
	std::vector<int64_t> pmin[6], pmax[6], offs, glo, ghi;
	std::vector<int> pgroup, pbiome;
	int plains = 0;
	int nodes[6] = {-1, -1, -1, -1, -1, -1};   // temperature, vegetation, continents, erosion, depth, ridges
	mutable std::mutex m;
	mutable std::unordered_map<int64_t, int> src_cache;
};
static inline int64_t cq(double f) { return (int64_t)(f * 10000.0); }
static inline int64_t cdist(int64_t lo, int64_t hi, int64_t v) { int64_t a = v - hi, b = lo - v; if (a > 0) return a; if (b > 0) return b; return 0; }
static void climate_column(const ClimateCfg &C, double t, double h, double c, double e, double w, int64_t *best, int *bi) {
	int64_t tv[5] = {cq(t), cq(h), cq(c), cq(e), cq(w)};
	static const int PK[5] = {0, 1, 2, 3, 5};
	for (int g = 0; g < C.ng; g++) { best[g] = INT64_MAX; bi[g] = -1; }
	for (int i = 0; i < C.n; i++) {
		int64_t s = 0;
		for (int k = 0; k < 5; k++) { int64_t d = cdist(C.pmin[PK[k]][i], C.pmax[PK[k]][i], tv[k]); s += d * d; }
		s += C.offs[i] * C.offs[i];
		int g = C.pgroup[i];
		if (s < best[g]) { best[g] = s; bi[g] = i; }
	}
}
static int climate_pick(const ClimateCfg &C, const int64_t *best, const int *bi, double depth) {
	int64_t dv = cq(depth);
	int64_t bm = INT64_MAX;
	int res = 0;
	for (int g = 0; g < C.ng; g++) {
		if (best[g] == INT64_MAX) continue;
		int64_t dk = cdist(C.glo[g], C.ghi[g], dv);
		int64_t s = best[g] + dk * dk;
		if (s < bm) { bm = s; res = bi[g] >= 0 ? C.pbiome[bi[g]] : C.plains; }
	}
	return res;
}

// An INTERP node i such that "all 8 corners of i's cell < 0" implies value(n) < 0 for every block of the cell: the
// interpolated value is a convex combination of the corners; squeeze, mul by a positive constant, min (either side)
// and pass keep a negative input negative. Overworld final_density = min(squeeze(interpolated(...)), noodle) (+ the
// beardifier, added separately). -1 when the graph has no such shape (the fill then evaluates every block).
static int air_interp(const Graph &g, int n, int depth = 0) {
	if (n < 0 || n >= (int)g.nodes.size() || depth > 8) return -1;
	const Node &d = g.nodes[n];
	switch (d.k) {
		case INTERP: return (d.cxz == 4 && d.cy == 8) ? n : -1;
		case SQUEEZE: case PASS: return air_interp(g, d.a, depth + 1);
		case MUL: {
			if (d.a >= 0 && g.nodes[d.a].k == CONST && g.nodes[d.a].v0 > 0.0) return air_interp(g, d.b, depth + 1);
			if (d.b >= 0 && g.nodes[d.b].k == CONST && g.nodes[d.b].v0 > 0.0) return air_interp(g, d.a, depth + 1);
			return -1;
		}
		case MIN: {
			int r = air_interp(g, d.a, depth + 1);
			return r >= 0 ? r : air_interp(g, d.b, depth + 1);
		}
		case ADD: {
			// adding a constant <= 0 (the beardifier placeholder is ZERO here; the real beard is added in fill) keeps a
			// negative value negative
			auto nonpos = [&](int m) { return m >= 0 && (g.nodes[m].k == ZERO || (g.nodes[m].k == CONST && g.nodes[m].v0 <= 0.0)); };
			if (nonpos(d.b)) return air_interp(g, d.a, depth + 1);
			if (nonpos(d.a)) return air_interp(g, d.b, depth + 1);
			return -1;
		}
		default: return -1;
	}
}

struct Cfg {
	ClimateCfg clim;
	SurfCfg surf;
	const Graph *g = nullptr;
	int water = 0, lava = 0, sea = 63;
	int n_barrier = -1, n_flood = -1, n_spread = -1, n_lava = -1, n_excl = -1, n_prelim = -1, n_final = -1;
	int n_air_interp = -1;   // INTERP node whose 8 negative corners prove final density < 0 (see air_interp)
	int gen_min_y = -64, gen_depth = 384;
	bool aquifers = true;
	int s_fluid = 0, s_default = 1, s_grass = 0;
	int grass_b = -1, myc_b = -1, dirt_b = -1;
	int f_liquid = 0;
	Positional aq_rand;
	int64_t seed = 0;
	std::vector<int> st_block, st_flags;
	std::vector<uint8_t> replaceable;   // by block id
	std::vector<Carver> carvers;
	std::vector<std::vector<int>> biome_carvers;
	// preliminary surface cache (grid point -> value)
	mutable std::mutex sc_mutex;
	mutable std::unordered_map<int64_t, double> sc;
};

std::mutex c_mutex;
std::vector<Cfg *> g_cfgs;

static const Cfg *cfg_of(int64_t h) {
	std::lock_guard<std::mutex> lk(c_mutex);
	return (h >= 0 && h < (int64_t)g_cfgs.size()) ? g_cfgs[h] : nullptr;
}

// ---------------------------------------------------------------- terrain job (per chunk)
static const int OFFS[13][2] = {{0, 0}, {-2, -1}, {-1, -1}, {0, -1}, {1, -1}, {-3, 0}, {-2, 0}, {-1, 0}, {1, 0}, {-2, 1}, {-1, 1}, {0, 1}, {1, 1}};
const int WAY_BELOW = -2032;

struct Job {
	const Cfg &c;
	int cx, cz;
	Eval ev;               // chunk context (has_chunk = true)
	Eval *ev_free = nullptr;   // has_chunk = false (preliminary surface)
	// aquifer grid
	int min_gx, min_gy, min_gz, sx, sy, sz;
	std::vector<int> loc_x, loc_y, loc_z, st_level, st_fluid;
	std::vector<uint8_t> st_set;
	bool bar_set = false;
	double bar = 0.0;
	// Java Beardifier pieces of this chunk (Structures.beard_pieces): [min x, y, z, max x, y, z, adaptation, delta]*
	std::vector<int32_t> beard;
	Job(const Cfg &cf, int x, int z) : c(cf), cx(x), cz(z), ev(*cf.g, x, z, true) {}

	static const float *beard_kernel() {
		static float k24[24 * 24 * 24];
		static bool done = false;
		static std::mutex m;
		std::lock_guard<std::mutex> lk(m);
		if (!done) {
			for (int k = 0; k < 24; k++)
				for (int i = 0; i < 24; i++)
					for (int j = 0; j < 24; j++) {
						double fx = i - 12, fy = (j - 12) + 0.5, fz = k - 12;
						k24[k * 576 + i * 24 + j] = (float)std::exp(-(fx * fx + fy * fy + fz * fz) / 16.0);
					}
			done = true;
		}
		return k24;
	}
	static double bury(double a, double b, double cc) {
		double l = std::sqrt(a * a + b * b + cc * cc) / 6.0;
		return 1.0 - std::min(1.0, std::max(0.0, l));
	}
	static double beard_c(const float *K, int x, int y, int z, int y_to_ground) {
		int i = x + 12, j = y + 12, k = z + 12;
		if (i < 0 || i >= 24 || j < 0 || j >= 24 || k < 0 || k >= 24) return 0.0;
		double d0 = (double)y_to_ground + 0.5;
		double d1 = (double)(x * x) + d0 * d0 + (double)(z * z);
		double d2 = -d0 / std::sqrt(d1 / 2.0) / 2.0;
		return d2 * (double)K[k * 576 + i * 24 + j];
	}
	// Java Beardifier.compute (Structures.beard_at is the GDScript reference)
	double beard_at(int x, int y, int z) const {
		const float *K = beard_kernel();
		double d = 0.0;
		for (size_t o = 0; o + 8 <= beard.size(); o += 8) {
			const int32_t *pc = &beard[o];
			int dx = std::max(0, std::max(pc[0] - x, x - pc[3]));
			int dz = std::max(0, std::max(pc[2] - z, z - pc[5]));
			int yb = pc[1] + pc[7];
			int dyb = y - yb;
			switch (pc[6]) {
				case 1: d += beard_c(K, dx, dyb, dz, dyb) * 0.8; break;
				case 2: d += beard_c(K, dx, std::max(0, std::max(yb - y, y - pc[4])), dz, dyb) * 0.8; break;
				case 3: d += bury((double)dx, (double)dyb / 2.0, (double)dz); break;
				case 4: d += bury((double)dx / 2.0, (double)std::max(0, std::max(pc[1] - y, y - pc[4])) / 2.0, (double)dz / 2.0) * 0.8; break;
				case 5: {   // JigsawJunction [x, ground y, z]: signed offsets, weight 0.4
					int jy = y - pc[1];
					d += beard_c(K, x - pc[0], jy, z - pc[2], jy) * 0.4;
					break;
				}
				default: break;
			}
		}
		return d;
	}
	~Job() { delete ev_free; }

	double grid_surface(int64_t gx, int64_t gz) {
		int64_t key = (gx << 32) ^ (gz & 0xFFFFFFFFLL);
		{
			std::lock_guard<std::mutex> lk(c.sc_mutex);
			auto it = c.sc.find(key);
			if (it != c.sc.end()) return it->second;
		}
		if (!ev_free) { ev_free = new Eval(*c.g, 0, 0, false); ev_free->mode = 0; }
		double r = ev_free->at(c.n_prelim, (int)(gx * 16), 0, (int)(gz * 16));
		std::lock_guard<std::mutex> lk(c.sc_mutex);
		if (c.sc.size() > 200000) c.sc.clear();
		c.sc[key] = r;
		return r;
	}
	int64_t chunk_surface(int64_t x, int64_t z) {
		int64_t gx = (int64_t)std::floor(x / 16.0), gz = (int64_t)std::floor(z / 16.0);
		double fx = (x - gx * 16) / 16.0, fz = (z - gz * 16) / 16.0;
		double a = grid_surface(gx, gz), b = grid_surface(gx + 1, gz), cc = grid_surface(gx, gz + 1), d = grid_surface(gx + 1, gz + 1);
		double top = a + fx * (b - a);
		double bot = cc + fx * (d - cc);
		return (int64_t)std::floor(top + fz * (bot - top));
	}
	int aquifer_ceiling() {
		int64_t m = c.sea;
		for (int64_t gz = cz - 4; gz < cz + 6; gz++)
			for (int64_t gx = cx - 4; gx < cx + 6; gx++)
				m = std::max(m, (int64_t)std::ceil(grid_surface(gx, gz)) + 8);
		return (int)(m + 6);
	}

	void aq_init() {
		min_gx = (int)std::floor((cx * 16) / 16.0) - 1;
		int max_gx = (int)std::floor((cx * 16 + 15) / 16.0) + 1;
		min_gz = (int)std::floor((cz * 16) / 16.0) - 1;
		int max_gz = (int)std::floor((cz * 16 + 15) / 16.0) + 1;
		min_gy = (int)std::floor(MIN_Y / 12.0) - 1;
		int max_gy = (int)std::floor((MIN_Y + HEIGHT) / 12.0) + 1;
		sx = max_gx - min_gx + 1; sy = max_gy - min_gy + 1; sz = max_gz - min_gz + 1;
		size_t n = (size_t)sx * sy * sz;
		loc_x.resize(n); loc_y.resize(n); loc_z.resize(n);
		st_level.assign(n, 0); st_fluid.assign(n, 0); st_set.assign(n, 0);
		for (int gy = min_gy; gy < min_gy + sy; gy++)
			for (int gz = min_gz; gz < min_gz + sz; gz++)
				for (int gx = min_gx; gx < min_gx + sx; gx++) {
					size_t i = ((size_t)(gy - min_gy) * sz + (gz - min_gz)) * sx + (gx - min_gx);
					AnyRandom r = c.aq_rand.at(gx, gy, gz);
					loc_x[i] = gx * 16 + (int)r.next_int_bound(10);
					loc_y[i] = gy * 12 + (int)r.next_int_bound(9);
					loc_z[i] = gz * 16 + (int)r.next_int_bound(10);
				}
	}
	// global fluid picker: (level, state)
	void global(int y, int &lvl, int &fl) const {
		if (y < std::min(-54, c.sea)) { lvl = -54; fl = c.lava; } else { lvl = c.sea; fl = c.water; }
	}
	void compute_fluid(int x, int y, int z, int &out_lvl, int &out_fl) {
		int glvl, gfl;
		global(y, glvl, gfl);
		int64_t min_surface = 2147483647;
		int hi = y + 12, lo = y - 12;
		bool flooded = false;
		for (int k = 0; k < 13; k++) {
			int ox = x + OFFS[k][0] * 16, oz = z + OFFS[k][1] * 16;
			int64_t q = chunk_surface(ox, oz);
			int64_t r = q + 8;
			bool center = OFFS[k][0] == 0 && OFFS[k][1] == 0;
			if (center && lo > r) { out_lvl = glvl; out_fl = gfl; return; }
			bool above = hi > r;
			if (above || center) {
				int l2, f2;
				global((int)r, l2, f2);
				if ((r < l2 ? f2 : 0) != 0) {
					if (center) flooded = true;
					if (above) { out_lvl = l2; out_fl = f2; return; }
				}
			}
			min_surface = std::min(min_surface, q);
		}
		int lvl = surface_level(x, y, z, glvl, (int)min_surface, flooded);
		out_lvl = lvl;
		out_fl = fluid_type(x, y, z, gfl, lvl);
	}
	int surface_level(int x, int y, int z, int glvl, int min_surface, bool flooded) {
		double d, e;
		if (ev.at(c.n_excl, x, y, z) > 0.0) {
			d = -1.0; e = -1.0;
		} else {
			int m = min_surface + 8 - y;
			double f = flooded ? clampd(remap((double)m, 0.0, 64.0, 1.0, 0.0), 0.0, 1.0) : 0.0;
			double g = clampd(ev.at(c.n_flood, x, y, z), -1.0, 1.0);
			double h = remap(f, 1.0, 0.0, -0.3, 0.8);
			double o = remap(f, 1.0, 0.0, -0.8, 0.4);
			d = g - o;
			e = g - h;
		}
		if (e > 0.0) return glvl;
		if (d > 0.0) {
			int px = (int)std::floor(x / 16.0), py = (int)std::floor(y / 40.0), pz = (int)std::floor(z / 16.0);
			int r = py * 40 + 20;
			double dd = ev.at(c.n_spread, px, py, pz) * 10.0;
			int t = (int)std::floor(dd / 3.0) * 3;
			return std::min(min_surface, r + t);
		}
		return WAY_BELOW;
	}
	int fluid_type(int x, int y, int z, int gfl, int lvl) {
		if (lvl <= -10 && lvl != WAY_BELOW && gfl != c.lava) {
			double d = ev.at(c.n_lava, (int)std::floor(x / 64.0), (int)std::floor(y / 40.0), (int)std::floor(z / 64.0));
			if (std::fabs(d) > 0.3) return c.lava;
		}
		return gfl;
	}
	void fill_status(size_t i) {
		int l, f;
		compute_fluid(loc_x[i], loc_y[i], loc_z[i], l, f);
		st_set[i] = 1; st_level[i] = l; st_fluid[i] = f;
	}
	double press(int y, int la, int fa, int lb, int fb, int x, int z) {
		int sa = y < la ? fa : 0, sb = y < lb ? fb : 0;
		if ((sa == c.lava && sb == c.water) || (sa == c.water && sb == c.lava)) return 2.0;
		int j = std::abs(la - lb);
		if (j == 0) return 0.0;
		double k = 0.5 * (la + lb);
		double l = y + 0.5 - k;
		double t = j / 2.0 - std::fabs(l);
		double v;
		if (l > 0.0) v = t > 0.0 ? t / 1.5 : t / 2.5;
		else { double u = 3.0 + t; v = u > 0.0 ? u / 3.0 : u / 10.0; }
		double xb = 0.0;
		if (v >= -2.0 && v <= 2.0) {
			if (!bar_set) { bar = ev.at(c.n_barrier, x, y, z); bar_set = true; }
			xb = bar;
		}
		return 2.0 * (xb + v);
	}
	int substance(int x, int y, int z, double density) {
		if (density > 0.0) return -1;
		int lava_y = std::min(-54, c.sea);
		if (y < lava_y) return c.lava;
		int l = (x - 5) >> 4;
		int m = (int)floordiv(y + 1, 12);
		int n = (z - 5) >> 4;
		int64_t d0 = 2147483647, d1 = 2147483647, d2 = 2147483647;
		size_t i0 = 0, i1 = 0, i2 = 0;
		for (int w = 0; w < 2; w++)
			for (int xx = -1; xx < 2; xx++)
				for (int yy = 0; yy < 2; yy++) {
					size_t gi = ((size_t)(m + xx - min_gy) * sz + (n + yy - min_gz)) * sx + (l + w - min_gx);
					int64_t dx = loc_x[gi] - x, dy = loc_y[gi] - y, dz = loc_z[gi] - z;
					int64_t dist = dx * dx + dy * dy + dz * dz;
					if (d0 >= dist) { i2 = i1; d2 = d1; i1 = i0; d1 = d0; i0 = gi; d0 = dist; }
					else if (d1 >= dist) { i2 = i1; d2 = d1; i1 = gi; d1 = dist; }
					else if (d2 >= dist) { i2 = gi; d2 = dist; }
				}
		if (!st_set[i0]) fill_status(i0);
		int lv0 = st_level[i0], fl0 = st_fluid[i0];
		int st = y < lv0 ? fl0 : 0;
		double sim01 = 1.0 - std::llabs(d1 - d0) / 25.0;
		if (sim01 <= 0.0) return st;
		if (st == c.water && y - 1 < lava_y) return st;
		bar_set = false;
		if (!st_set[i1]) fill_status(i1);
		int lv1 = st_level[i1], fl1 = st_fluid[i1];
		double e = sim01 * press(y, lv0, fl0, lv1, fl1, x, z);
		if (density + e > 0.0) return -1;
		if (!st_set[i2]) fill_status(i2);
		int lv2 = st_level[i2], fl2 = st_fluid[i2];
		double f = 1.0 - std::llabs(d2 - d0) / 25.0;
		if (f > 0.0) {
			double g = sim01 * f * press(y, lv0, fl0, lv2, fl2, x, z);
			if (density + g > 0.0) return -1;
		}
		double h = 1.0 - std::llabs(d2 - d1) / 25.0;
		if (h > 0.0) {
			double g2 = sim01 * h * press(y, lv1, fl1, lv2, fl2, x, z);
			if (density + g2 > 0.0) return -1;
		}
		return st;
	}

	// Java NoiseBasedChunkGenerator.getBaseColumn / iterateNoiseColumn: one column's noise-stage block classes from the
	// cell-interpolated final density (no beard) and the aquifer: 0 air, 1 solid, 2 water (other fluid), 3 lava
	void column(int x, int z, uint8_t *out) {
		int nlo = c.gen_min_y, nhi = c.gen_min_y + c.gen_depth;
		if (c.aquifers) aq_init();
		int lava_y = std::min(-54, c.sea);
		ev.mode = 1;
		for (int y = nlo; y < nhi; y++) {
			ev.px = x; ev.py = y; ev.pz = z;
			ev.cur = ev.next_stamp();
			double d = ev.ev(c.n_final, x, y, z);
			int st;
			if (d > 0.0) st = c.s_default;
			else if (!c.aquifers) st = y < lava_y ? c.lava : (y < c.sea ? c.s_fluid : 0);
			else if (y < lava_y) st = c.lava;
			else { int s = substance(x, y, z, d); st = s < 0 ? c.s_default : s; }
			out[y - nlo] = (uint8_t)(st == 0 ? 0 : (st == c.lava ? 3 : (st == c.s_default ? 1 : 2)));
		}
		ev.mode = 0;
	}

	// ------------------------------------------------------------ fill
	int skip_above = 0;
	void fill(int32_t *col) {
		// density (block mode = GDScript cell path)
		static thread_local std::vector<double> tl_dens;
		TLBuf<double> dens_buf(tl_dens, 98304, 0.0);
		std::vector<double> &dens = dens_buf.v;
		int nlo = c.gen_min_y, nhi = c.gen_min_y + c.gen_depth;
		static int prof = getenv("RC_DFPROF") ? 1 : 0;
		LARGE_INTEGER pf0, pf1, pf2, pf3, pfq;
		if (prof) {
			// profiling (RC_DFPROF=1): every interpolation corner first, then the per-block pass alone
			QueryPerformanceFrequency(&pfq);
			QueryPerformanceCounter(&pf0);
			ev.mode = 1;
			for (size_t n = 0; n < c.g->nodes.size(); n++) {
				const Node &d = c.g->nodes[n];
				if (d.k != INTERP || d.cxz <= 0 || d.cy <= 0) continue;
				int nx = 16 / d.cxz + 1, ny = HEIGHT / d.cy + 1;
				for (int iy = 0; iy < ny; iy++) for (int iz = 0; iz < nx; iz++) for (int ix = 0; ix < nx; ix++) ev.corner((int)n, d, ix, iy, iz);
			}
			QueryPerformanceCounter(&pf1);
		}
		uint64_t kc[40] = {0};
		if (prof) ev.kcount = kc;
		ev.mode = 1;
		int x0 = cx * 16, z0 = cz * 16;
		// Proven-air cells are not evaluated per block: the block is air whatever the exact negative value when the cell
		// lies wholly above the aquifer ceiling (above it the fill only tests the sign; without aquifers: above the sea
		// and the lava level), no structure beard can add density in this chunk, and every corner of the n_air_interp
		// cell is negative. Generated blocks are identical; ~half of a chunk's cells are open air.
		skip_above = c.aquifers ? aquifer_ceiling() : c.gen_min_y + c.gen_depth;
		int air_from = c.aquifers ? skip_above + 1 : std::max(c.sea, std::min(-54, c.sea));
		const bool can_skip = c.n_air_interp >= 0 && beard.empty() && !getenv("RC_NOAIRSKIP");
		const Node *ai = can_skip ? &c.g->nodes[c.n_air_interp] : nullptr;
		int air_cells = 0;
		const bool use_batch = !getenv("RC_NOBATCH") && ev.batch_ok(c.n_final);
		// cell order (4 x 8 x 4, Java NoiseChunk's): every block of a cell reuses the interpolation nodes' cached corners
		// (Eval::interp); each block is still evaluated on its own, so the values are the same in any order
		for (int cy0 = 0; cy0 < HEIGHT; cy0 += 8)
			for (int cz0 = 0; cz0 < 16; cz0 += 4)
				for (int cx0 = 0; cx0 < 16; cx0 += 4) {
					if (ai && MIN_Y + cy0 >= air_from && MIN_Y + cy0 >= nlo && MIN_Y + cy0 + 8 <= nhi) {
						int ix = cx0 >> 2, iz = cz0 >> 2, iy = cy0 >> 3;
						bool air = true;
						for (int k = 0; k < 8 && air; k++)
							air = ev.corner(c.n_air_interp, *ai, ix + (k & 1), iy + ((k >> 2) & 1), iz + ((k >> 1) & 1)) < 0.0;
						if (air) {
							air_cells++;
							for (int ly = cy0; ly < cy0 + 8; ly++)
								for (int lz = cz0; lz < cz0 + 4; lz++)
									for (int lx = cx0; lx < cx0 + 4; lx++) dens[(ly << 8) | (lz << 4) | lx] = -1.0;
							continue;
						}
					}
					if (use_batch && MIN_Y + cy0 >= nlo && MIN_Y + cy0 + 8 <= nhi) {
						// whole cell as array operations (Eval::eval_cell, bit-identical to the per-block path)
						double lane[128];
						ev.eval_cell(c.n_final, cx0, cy0, cz0, lane);
						for (int i = 0; i < 128; i++) {
							int ly = cy0 + (i >> 4), lz = cz0 + ((i >> 2) & 3), lx = cx0 + (i & 3);
							int idx = (ly << 8) | (lz << 4) | lx;
							dens[idx] = lane[i];
							if (!beard.empty()) dens[idx] += beard_at(x0 + lx, MIN_Y + ly, z0 + lz);
						}
						continue;
					}
					for (int ly = cy0; ly < cy0 + 8; ly++) {
						int y = MIN_Y + ly;
						for (int lz = cz0; lz < cz0 + 4; lz++)
							for (int lx = cx0; lx < cx0 + 4; lx++) {
								int idx = (ly << 8) | (lz << 4) | lx;
								if (y < nlo || y >= nhi) { dens[idx] = -1.0; continue; }
								int x = x0 + lx, z = z0 + lz;
								ev.px = x; ev.py = y; ev.pz = z;
								ev.cur = ev.next_stamp();
								dens[idx] = ev.ev(c.n_final, x, y, z);
								if (!beard.empty()) dens[idx] += beard_at(x, y, z);   // final_density = add(..., beardifier)
							}
					}
				}
		ev.mode = 0;
		ev.kcount = nullptr;
		(void)0;
		if (prof) {
			QueryPerformanceCounter(&pf2);
			static const char *KN[] = {"CONST", "ADD", "MUL", "SUB", "DIV", "MIN", "MAX", "ABS", "SQUARE", "CUBE", "HALF_NEG", "QUARTER_NEG", "SQUEEZE", "NEGATE", "CLAMP", "RANGE", "LERP", "GRADIENT", "NOISE", "SHIFT_A", "SHIFT_B", "SHIFT", "BLENDED", "INTERP", "PASS", "ONE", "ZERO", "SPLINE", "INTERVAL", "TOP_SURFACE", "END_ISLANDS", "DIST"};
			printf("[dfprof] per-block computes / block:");
			for (int k = 0; k < 32; k++) if (kc[k]) printf(" %s %.2f", KN[k], (double)kc[k] / 98304.0);
			printf("\n");
		}
		if (c.aquifers) aq_init();
		int gtop = c.gen_min_y + c.gen_depth;
		int lava_y = std::min(-54, c.sea);
		for (int i = 0; i < 98304; i++) {
			double d = dens[i];
			if (d > 0.0) { col[i] = c.s_default; continue; }
			int y = -64 + (i >> 8);
			col[i] = 0;
			if (!c.aquifers) {
				if (y < c.gen_min_y || y >= gtop) continue;
				col[i] = y < lava_y ? c.lava : (y < c.sea ? c.s_fluid : 0);
				continue;
			}
			if (y > skip_above) continue;
			if (y < lava_y) { col[i] = c.lava; continue; }
			int s = substance(x0 + (i & 15), y, z0 + ((i >> 4) & 15), d);
			col[i] = s < 0 ? c.s_default : s;
		}
		if (prof) {
			QueryPerformanceCounter(&pf3);
			double ms = 1000.0 / (double)pfq.QuadPart;
			int ninterp = 0;
			for (auto &nd : c.g->nodes) ninterp += nd.k == INTERP ? 1 : 0;
			printf("[dfprof] corners %.2f ms (%d interp nodes) | per-block %.2f ms | aquifer+fill %.2f ms | nodes %d | air cells %d / 768 (air interp %d)\n", (pf1.QuadPart - pf0.QuadPart) * ms, ninterp, (pf2.QuadPart - pf1.QuadPart) * ms, (pf3.QuadPart - pf2.QuadPart) * ms, (int)c.g->nodes.size(), air_cells, c.n_air_interp);
			fflush(stdout);
		}
	}

	// ------------------------------------------------------------ surface rules (SurfaceRules.apply_chunk)
	struct Cand { int i, above, below, water; };
	int sdepth[256];
	std::vector<std::vector<double>> planes;   // per surface noise index (empty = not computed)
	int64_t min_surf[256];
	uint8_t steep_c[256];
	const uint8_t *sbio = nullptr;
	const int32_t *shm = nullptr;
	static const int MINI = (-2147483647 - 1);

	const double *plane(int nz) {
		if (planes.size() < c.surf.noises.size()) planes.resize(c.surf.noises.size());
		std::vector<double> &pv = planes[nz];
		if (!pv.empty()) return pv.data();
		pv.resize(256);
		double *a = pv.data();
		const Normal &n = c.surf.noises[nz];
		int x0 = cx * 16, z0 = cz * 16;
		for (int k = 0; k < 256; k++) a[k] = n.value((double)(x0 + (k & 15)), 0.0, (double)(z0 + (k >> 4)));
		return a;
	}
	bool stest(int cd, const Cand &k) {
		const SurfCfg &S = c.surf;
		const int *ci = &S.cints[cd * 5];
		int i = k.i;
		int col_i = i & 255;
		int y = -64 + (i >> 8);
		switch (ci[0]) {
			case C_TRUE: return true;
			case C_BIOME: {
				int b = sbio[((i & 15) >> 2) + (((i >> 4) & 15) >> 2) * 4 + ((i >> 8) >> 2) * 16];
				return b < S.nb && S.bsets[ci[1] + b] != 0;
			}
			case C_NOISE: {
				double v;
				if (ci[2]) v = S.noises[ci[1]].value((double)(cx * 16 + (i & 15)), (double)y, (double)(cz * 16 + ((i >> 4) & 15)));
				else v = plane(ci[1])[col_i];
				return v >= S.cfl[cd * 2] && v <= S.cfl[cd * 2 + 1];
			}
			case C_VGRAD: {
				int lo = ci[2], hi = ci[3];
				if (y <= lo) return true;
				if (y >= hi) return false;
				double span = (double)(hi - lo);
				double prob = 1.0 - (double)(y - lo) / span;
				AnyRandom r = S.poss[ci[1]].at(cx * 16 + (i & 15), y, cz * 16 + ((i >> 4) & 15));
				return r.next_float() < prob;
			}
			case C_YABOVE: return y + (ci[3] ? k.above : 0) >= ci[1] + sdepth[col_i] * ci[2];
			case C_WATER:
				if (k.water == MINI) return true;
				return y + (ci[3] ? k.above : 0) >= k.water + ci[1] + sdepth[col_i] * ci[2];
			case C_DEPTH: {
				int dv = ci[4] ? k.below : k.above;
				int rng = ci[3];
				int sec = 0;
				if (rng != 0) sec = (int)((plane(S.n_secondary)[col_i] + 1.0) * 0.5 * (double)rng);
				return dv <= 1 + ci[1] + (ci[2] ? sdepth[col_i] : 0) + sec;
			}
			case C_NOT: return !stest(ci[1], k);
			case C_STEEP: {
				if (steep_c[col_i] == 0) {
					int lx = col_i & 15, lz = col_i >> 4;
					bool st = false;
					if (shm[lx + std::min(lz + 1, 15) * 16] >= shm[lx + std::max(lz - 1, 0) * 16] + 4) st = true;
					else if (shm[std::max(lx - 1, 0) + lz * 16] >= shm[std::min(lx + 1, 15) + lz * 16] + 4) st = true;
					steep_c[col_i] = st ? 2 : 1;
				}
				return steep_c[col_i] == 2;
			}
			case C_HOLE: return sdepth[col_i] <= 0;
			case C_ABOVE_PRELIM: {
				if (min_surf[col_i] == MINI) min_surf[col_i] = chunk_surface(cx * 16 + (col_i & 15), cz * 16 + (col_i >> 4)) + sdepth[col_i] - 8;
				return y >= min_surf[col_i];
			}
			case C_TEMP: {
				int b = sbio[((i & 15) >> 2) + (((i >> 4) & 15) >> 2) * 4 + ((i >> 8) >> 2) * 16];
				double tv = S.temps[b];
				int lim = S.sea + 17;
				if (y > lim) tv -= (double)(y - lim) * 0.05 / 40.0;
				return tv < 0.15;
			}
		}
		return true;
	}
	int sapply(int r, const Cand &k) {
		const SurfCfg &S = c.surf;
		const int *ri = &S.rints[r * 4];
		switch (ri[0]) {
			case R_BLOCK: return ri[1];
			case R_SEQ:
				for (int q = 0; q < ri[2]; q++) {
					int v = sapply(S.kids[ri[1] + q], k);
					if (v >= 0) return v;
				}
				return -1;
			case R_COND: return stest(ri[1], k) ? sapply(ri[2], k) : -1;
			case R_BANDS: {
				int y = -64 + (k.i >> 8);
				double nv = plane(S.n_band)[k.i & 255];
				int64_t l = (int64_t)std::round(nv * 4.0);
				int64_t a = (y + l + 192) % 192;
				if (a < 0) a += 192;
				return S.bands[(size_t)a];
			}
			case R_VEIN: {
				const int *vi = &S.vints[ri[1] * 6];
				int i = k.i;
				int x = cx * 16 + (i & 15), y = -64 + (i >> 8), z = cz * 16 + ((i >> 4) & 15);
				double d = ev.at(vi[0], x, y, z);
				if (d < 0.0) return -1;
				AnyRandom rs = S.poss[S.p_ore].at(x, y, z);
				if (rs.next_float() > d) return -1;
				double rich = ev.at(vi[1], x, y, z);
				if (rs.next_float() < rich && ev.at(vi[2], x, y, z) < 0.0)
					return rs.next_float() < S.vfl[ri[1]] ? vi[4] : vi[3];
				return vi[5];
			}
		}
		return -1;
	}
	void surface(int32_t *col, const uint8_t *biomes, const int32_t *hm) {
		const SurfCfg &S = c.surf;
		sbio = biomes;
		shm = hm;
		ev.mode = 0;
		planes.clear();
		for (int k = 0; k < 256; k++) { min_surf[k] = MINI; steep_c[k] = 0; }
		std::vector<Cand> cand;
		cand.reserve(4096);
		int x0 = cx * 16, z0 = cz * 16;
		int stone = c.s_default;
		const int MAX_Y = MIN_Y + HEIGHT;
		for (int cc = 0; cc < 256; cc++) {
			int x = x0 + (cc & 15), z = z0 + (cc >> 4);
			{
				double d = S.noises[S.n_surface].value((double)x, 0.0, (double)z);
				AnyRandom r = S.poss[S.p_root].at(x, 0, z);
				double nd = r.next_double();
				sdepth[cc] = (int)(d * 2.75 + 3.0 + nd * 0.25);
			}
			int q = 0, rr = MINI, s = 2147483647;
			int top = hm[cc];
			for (int y = std::min(top, MAX_Y - 1); y > MIN_Y - 1; y--) {
				int i = ((y - MIN_Y) << 8) | cc;
				int st = col[i];
				if (st == 0) { q = 0; rr = MINI; continue; }
				if (c.st_flags[st] & c.f_liquid) { if (rr == MINI) rr = y + 1; continue; }
				if (s >= y) {
					s = -2032;
					for (int v = y - 1; v > MIN_Y - 2; v--) {
						if (v < MIN_Y) { s = v + 1; break; }
						int sv = col[((v - MIN_Y) << 8) | cc];
						if (sv == 0 || (c.st_flags[sv] & c.f_liquid)) { s = v + 1; break; }
					}
				}
				q++;
				if (st != stone) continue;
				cand.push_back(Cand{i, q, y - s + 1, rr});
			}
		}
		for (const Cand &k : cand) {
			int v = sapply(S.root, k);
			if (v >= 0) col[k.i] = v;
		}
	}

	// ------------------------------------------------------------ carvers
	std::vector<uint8_t> mask;
	int32_t *col = nullptr;

	bool can_reach(double d, double e, int i, int j, double f) const {
		double g = cx * 16 + 8.0, h = cz * 16 + 8.0;
		double k = d - g, l = e - h;
		double m = (double)(j - i);
		double n = f + 2.0 + 16.0;
		return k * k + l * l - m * m <= n * n;
	}
	void ellipsoid(double d, double e, double f, double g, double h, double floor_l, const std::vector<float> *widths) {
		double mx = cx * 16 + 8.0, mz = cz * 16 + 8.0;
		double k = 16.0 + g * 2.0;
		if (std::fabs(d - mx) > k || std::fabs(f - mz) > k) return;
		int l = cx * 16, m = cz * 16;
		int n = std::max((int)std::floor(d - g) - l - 1, 0);
		int o = std::min((int)std::floor(d + g) - l, 15);
		int p = std::max((int)std::floor(e - h) - 1, c.gen_min_y + 1);
		int r2 = std::min((int)std::floor(e + h) + 1, c.gen_min_y + c.gen_depth - 1 - 7);
		int lava_level = c.gen_min_y + 8;
		int lava_y = std::min(-54, c.sea);
		int s = std::max((int)std::floor(f - g) - m - 1, 0);
		int t = std::min((int)std::floor(f + g) - m, 15);
		for (int u = n; u <= o; u++) {
			double wx = (((double)(l + u)) + 0.5 - d) / g;
			for (int x = s; x <= t; x++) {
				double wz = (((double)(m + x)) + 0.5 - f) / g;
				if (wx * wx + wz * wz >= 1.0) continue;
				bool surface = false;
				for (int aa = r2; aa > p; aa--) {
					double ab = ((double)aa - 0.5 - e) / h;
					if (!widths) {
						if (ab <= floor_l || wx * wx + ab * ab + wz * wz >= 1.0) continue;
					} else {
						int wi = aa - c.gen_min_y - 1;
						int ws = (int)widths->size() - 1;
						wi = wi < 0 ? 0 : (wi > ws ? ws : wi);
						double wj = (double)(*widths)[wi];
						if ((wx * wx + wz * wz) * wj + ab * ab / 6.0 >= 1.0) continue;
					}
					int bi = ((aa - MIN_Y) << 8) | (x << 4) | u;
					if (mask[bi]) continue;
					mask[bi] = 1;
					int cur = col[bi];
					int cb = cur >= 0 ? c.st_block[cur] : -1;
					if (cb == c.grass_b || cb == c.myc_b) surface = true;
					if (cb < 0 || cb >= (int)c.replaceable.size() || !c.replaceable[cb]) continue;
					int ns;
					if (aa <= lava_level) ns = c.lava;
					else if (c.aquifers) {
						ns = substance(l + u, aa, m + x, 0.0);
						if (ns < 0) continue;
					} else ns = aa < lava_y ? c.lava : (aa < c.sea ? c.s_fluid : 0);
					col[bi] = ns;
					if (surface && aa - 1 >= MIN_Y) {
						int bi2 = ((aa - 1 - MIN_Y) << 8) | (x << 4) | u;
						if (c.st_block[col[bi2]] == c.dirt_b && (c.st_flags[ns] & c.f_liquid) == 0) col[bi2] = c.s_grass;
					}
				}
			}
		}
	}
	void tunnel(int64_t seed, double d, double e, double f, double g, double h, double thick, double yaw, double pitch, int start, int end, double yscale, double floor_l) {
		LegacyRandom r(seed);
		int64_t o = r.next_int_bound(end / 2) + end / 4;
		bool steep = r.next_int_bound(6) == 0;
		double p = 0.0, q = 0.0;
		for (int idx = start; idx < end; idx++) {
			double s = 1.5 + std::sin(PI * (double)idx / (double)end) * thick;
			double t = s * yscale;
			double u = std::cos(pitch);
			d += std::cos(yaw) * u;
			e += std::sin(pitch);
			f += std::sin(yaw) * u;
			pitch *= steep ? 0.92 : 0.7;
			pitch += q * 0.1;
			yaw += p * 0.1;
			q *= 0.9;
			p *= 0.75;
			{ double a1 = r.next_float(); double a2 = r.next_float(); double a3 = r.next_float(); q += (a1 - a2) * a3 * 2.0; }
			{ double a1 = r.next_float(); double a2 = r.next_float(); double a3 = r.next_float(); p += (a1 - a2) * a3 * 4.0; }
			if (idx == o && thick > 1.0) {
				int64_t s1 = r.next_long();
				double t1 = r.next_float() * 0.5 + 0.5;
				tunnel(s1, d, e, f, g, h, t1, yaw - PI / 2.0, pitch / 3.0, idx, end, 1.0, floor_l);
				int64_t s2 = r.next_long();
				double t2 = r.next_float() * 0.5 + 0.5;
				tunnel(s2, d, e, f, g, h, t2, yaw + PI / 2.0, pitch / 3.0, idx, end, 1.0, floor_l);
				return;
			}
			if (r.next_int_bound(4) == 0) continue;
			if (!can_reach(d, f, idx, end, thick)) return;
			ellipsoid(d, e, f, s * g, t * h, floor_l, nullptr);
		}
	}
	void cave(const Carver &cf, LegacyRandom &r, int sxc, int szc) {
		const int i = (4 * 2 - 1) * 16;
		int64_t n = isample(r, cf.count);
		for (int64_t k = 0; k < n; k++) {
			double d = (double)(sxc * 16 + r.next_int_bound(16));
			double e = (double)isample(r, cf.y);
			double f = (double)(szc * 16 + r.next_int_bound(16));
			double g = fsample(r, cf.hrm);
			double h = fsample(r, cf.vrm);
			double floor_l = fsample(r, cf.floor_level);
			int64_t m = 1;
			if (r.next_int_bound(4) == 0) {
				double ys = fsample(r, cf.room_vrm);
				double o = 1.0 + r.next_float() * 6.0;
				double rad = 1.5 + std::sin(PI / 2.0) * o;
				ellipsoid(d + 1.0, e, f, rad, rad * ys, floor_l, nullptr);
				m += r.next_int_bound(4);
			}
			for (int64_t pi = 0; pi < m; pi++) {
				double yaw = r.next_float() * TAU;
				double pitch = (r.next_float() - 0.5) / 4.0;
				double thick = fsample(r, cf.thickness);
				if (cf.weird && r.next_int_bound(10) == 0) {
					double a1 = r.next_float(); double a2 = r.next_float();
					thick *= a1 * a2 * 3.0 + 1.0;
				}
				int s = i - (int)r.next_int_bound(i / 4);
				int64_t sd = r.next_long();
				tunnel(sd, d, e, f, g, h, thick, yaw, pitch, 0, s, cf.start_vrm, floor_l);
			}
		}
	}
	void canyon_carve(const Carver &cf, int64_t seed, double d, double e, double f, double g, double yaw, double pitch, int start, int end, double yscale) {
		LegacyRandom r(seed);
		std::vector<float> widths(c.gen_depth);
		double w = 1.0;
		int smooth = std::max(1, cf.smooth);
		for (int jj = 0; jj < c.gen_depth; jj++) {
			if (jj == 0 || r.next_int_bound(smooth) == 0) { double a1 = r.next_float(); double a2 = r.next_float(); w = 1.0 + a1 * a2; }
			widths[jj] = (float)(w * w);
		}
		double m = 0.0, n = 0.0;
		for (int o = start; o < end; o++) {
			double p = 1.5 + std::sin((double)o * PI / (double)end) * g;
			double q = p * yscale;
			p *= fsample(r, cf.hrf);
			double hh = 1.0 - std::fabs(0.5 - (double)o / (double)end) * 2.0;
			double vf = cf.vrdf + cf.vrcf * hh;
			q = vf * q * (r.next_float() * 0.25 + 0.75);
			double rr = std::cos(pitch), ss = std::sin(pitch);
			d += std::cos(yaw) * rr;
			e += ss;
			f += std::sin(yaw) * rr;
			pitch *= 0.7;
			pitch += n * 0.05;
			yaw += m * 0.05;
			n *= 0.8;
			m *= 0.5;
			{ double a1 = r.next_float(); double a2 = r.next_float(); double a3 = r.next_float(); n += (a1 - a2) * a3 * 2.0; }
			{ double a1 = r.next_float(); double a2 = r.next_float(); double a3 = r.next_float(); m += (a1 - a2) * a3 * 4.0; }
			if (r.next_int_bound(4) == 0) continue;
			if (!can_reach(d, f, o, end, g)) return;
			ellipsoid(d, e, f, p, q, -INFINITY, &widths);
		}
	}
	void canyon(const Carver &cf, LegacyRandom &r, int sxc, int szc) {
		const int i = (4 * 2 - 1) * 16;
		double d = (double)(sxc * 16 + r.next_int_bound(16));
		int64_t j = isample(r, cf.y);
		double e = (double)(szc * 16 + r.next_int_bound(16));
		double f = r.next_float() * TAU;
		double g = fsample(r, cf.vrot);
		double h = fsample(r, cf.y_scale);
		double k = fsample(r, cf.c_thick);
		int l = (int)(i * fsample(r, cf.dist));
		int64_t sd = r.next_long();
		canyon_carve(cf, sd, d, (double)j, e, k, f, g, 0, l, h);
	}
	// carver source biome of chunk (sx, sz): climate at (sx*16, 0, sz*16), has_chunk = false (Carvers._source_biome)
	int source_biome(int sxc, int szc) {
		const ClimateCfg &C = c.clim;
		if (C.single >= 0) return C.single;
		int64_t key = ((int64_t)sxc << 32) ^ ((int64_t)szc & 0xFFFFFFFFLL);
		{
			std::lock_guard<std::mutex> lk(C.m);
			auto it = C.src_cache.find(key);
			if (it != C.src_cache.end()) return it->second;
		}
		if (!ev_free) { ev_free = new Eval(*c.g, 0, 0, false); ev_free->mode = 0; }
		int x = sxc * 16, z = szc * 16;
		double v[6];
		for (int k = 0; k < 6; k++) v[k] = ev_free->at(C.nodes[k], x, 0, z);
		std::vector<int64_t> best(C.ng);
		std::vector<int> bi(C.ng);
		climate_column(C, v[0], v[1], v[2], v[3], v[5], best.data(), bi.data());
		int id = climate_pick(C, best.data(), bi.data(), v[4]);
		std::lock_guard<std::mutex> lk(C.m);
		if (C.src_cache.size() > 100000) C.src_cache.clear();
		C.src_cache[key] = id;
		return id;
	}
	// chunk biomes (VanillaGenerator._biomes): quart points, column params from the qy = 0 layer
	void biomes(uint8_t *out) {
		const ClimateCfg &C = c.clim;
		ev.mode = 0;
		int x0 = cx * 16, z0 = cz * 16;
		std::vector<int64_t> best(16 * (size_t)C.ng);
		std::vector<int> bi(16 * (size_t)C.ng);
		for (int qc = 0; qc < 16; qc++) {
			int x = x0 + (qc & 3) * 4, z = z0 + (qc >> 2) * 4;
			double v[6];
			for (int k = 0; k < 6; k++) v[k] = ev.at(C.nodes[k], x, MIN_Y, z);
			climate_column(C, v[0], v[1], v[2], v[3], v[5], &best[qc * C.ng], &bi[qc * C.ng]);
		}
		for (int qy = 0; qy < 96; qy++)
			for (int qc = 0; qc < 16; qc++) {
				double d = ev.at(C.nodes[4], x0 + (qc & 3) * 4, MIN_Y + qy * 4, z0 + (qc >> 2) * 4);
				out[(qc & 3) + (qc >> 2) * 4 + qy * 16] = (uint8_t)climate_pick(C, &best[qc * C.ng], &bi[qc * C.ng], d);
			}
	}
	void carve(int32_t *cl, const int32_t *src_biomes) {
		col = cl;
		int32_t src_local[289];
		if (c.clim.src_ok) {
			int w2 = 0;
			for (int dz = -8; dz <= 8; dz++)
				for (int dx = -8; dx <= 8; dx++) src_local[w2++] = c.biome_carvers.empty() ? -1 : source_biome(cx + dx, cz + dz);
			src_biomes = src_local;
		}
		mask.assign(98304, 0);
		ev.mode = 0;
		LegacyRandom r(0);
		int w = 0;
		for (int dz = -8; dz <= 8; dz++) {
			for (int dx = -8; dx <= 8; dx++, w++) {
				int sxc = cx + dx, szc = cz + dz;
				int bio = src_biomes[w];
				if (bio < 0 || bio >= (int)c.biome_carvers.size()) continue;
				const std::vector<int> &lst = c.biome_carvers[bio];
				int64_t l = 0;
				for (int ci : lst) {
					const Carver &cf = c.carvers[ci];
					int64_t fs = wadd(c.seed, l);
					r.set_seed(fs);
					int64_t a = r.next_long();
					int64_t b = r.next_long();
					r.set_seed(wmul(sxc, a) ^ wmul(szc, b) ^ fs);
					l++;
					if (cf.empty || r.next_float() > cf.probability) continue;
					if (cf.type == 1) cave(cf, r, sxc, szc);
					else if (cf.type == 2) canyon(cf, r, sxc, szc);
				}
			}
		}
	}
};

std::mutex j_mutex;
std::vector<Job *> g_jobs;
std::vector<int64_t> g_free_jobs;

static Job *job_of(int64_t h) {
	std::lock_guard<std::mutex> lk(j_mutex);
	return (h >= 0 && h < (int64_t)g_jobs.size()) ? g_jobs[h] : nullptr;
}

static FProv fprov(const std::vector<double> &f, size_t o) { return FProv{(int)f[o], f[o + 1], f[o + 2], f[o + 3]}; }
static IProv iprov(const std::vector<double> &f, size_t o) { return IProv{(int)f[o], (int64_t)f[o + 1], (int64_t)f[o + 2]}; }

// desc: [ints: Array(int), st_block: PackedInt32Array, st_flags: PackedInt32Array, replaceable: PackedByteArray,
//        carvers: Array[[PackedInt32Array ints, PackedFloat64Array floats]], biome_carvers: Array[PackedInt32Array]]
bool fn_tg_config(const Args &a, void *ret) {
	const Graph *g = graph_of(a.i(0));
	const void *desc = a.obj(1, GDEXTENSION_VARIANT_TYPE_ARRAY);
	if (!g || !desc) return false;
	Cfg *c = new Cfg();
	c->g = g;
	const void *ints = arr_of(array_get(desc, 0));
	auto I = [&](int k) { return int_of(array_get(ints, k)); };
	c->water = (int)I(0); c->lava = (int)I(1); c->sea = (int)I(2);
	c->n_barrier = (int)I(3); c->n_flood = (int)I(4); c->n_spread = (int)I(5); c->n_lava = (int)I(6); c->n_excl = (int)I(7);
	c->n_prelim = (int)I(8); c->gen_min_y = (int)I(9); c->gen_depth = (int)I(10); c->aquifers = I(11) != 0;
	c->s_fluid = (int)I(12); c->s_default = (int)I(13); c->aq_rand.legacy = I(14) != 0; c->aq_rand.lo = I(15); c->aq_rand.hi = I(16);
	c->s_grass = (int)I(17); c->grass_b = (int)I(18); c->myc_b = (int)I(19); c->dirt_b = (int)I(20); c->f_liquid = (int)I(21);
	c->n_final = (int)I(22); c->seed = I(23);
	c->n_air_interp = air_interp(*g, c->n_final);
	read_i32(array_get(desc, 1), c->st_block);
	read_i32(array_get(desc, 2), c->st_flags);
	read_u8(array_get(desc, 3), c->replaceable);
	const void *cv = arr_of(array_get(desc, 4));
	int64_t nc = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, cv);
	c->carvers.resize(nc);
	for (int64_t k = 0; k < nc; k++) {
		const void *e = arr_of(array_get(cv, k));
		std::vector<int> ci;
		std::vector<double> cf;
		read_i32(array_get(e, 0), ci);
		read_f64(array_get(e, 1), cf);
		Carver &cr = c->carvers[k];
		cr.type = ci[0]; cr.empty = ci[1] != 0; cr.weird = ci[2] != 0; cr.smooth = ci[3];
		cr.probability = cf[0]; cr.start_vrm = cf[1]; cr.vrdf = cf[2]; cr.vrcf = cf[3];
		size_t o = 4;
		cr.count = iprov(cf, o); o += 4;
		cr.y = iprov(cf, o); o += 4;
		cr.hrm = fprov(cf, o); o += 4;
		cr.vrm = fprov(cf, o); o += 4;
		cr.floor_level = fprov(cf, o); o += 4;
		cr.room_vrm = fprov(cf, o); o += 4;
		cr.thickness = fprov(cf, o); o += 4;
		cr.vrot = fprov(cf, o); o += 4;
		cr.y_scale = fprov(cf, o); o += 4;
		cr.c_thick = fprov(cf, o); o += 4;
		cr.dist = fprov(cf, o); o += 4;
		cr.hrf = fprov(cf, o); o += 4;
	}
	const void *bc = arr_of(array_get(desc, 5));
	int64_t nb = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, bc);
	c->biome_carvers.resize(nb);
	for (int64_t k = 0; k < nb; k++) read_i32(array_get(bc, k), c->biome_carvers[k]);
	if (size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, desc) > 6) {
		const void *sd = arr_of(array_get(desc, 6));
		SurfCfg &S = c->surf;
		const void *misc = arr_of(array_get(sd, 0));
		auto M = [&](int k) { return (int)int_of(array_get(misc, k)); };
		S.root = M(0); S.n_surface = M(1); S.n_secondary = M(2); S.n_band = M(3); S.p_ore = M(4); S.p_root = M(5); S.nb = M(6); S.sea = M(7);
		read_i32(array_get(sd, 1), S.rints);
		read_i32(array_get(sd, 2), S.kids);
		read_i32(array_get(sd, 3), S.cints);
		read_f64(array_get(sd, 4), S.cfl);
		read_u8(array_get(sd, 5), S.bsets);
		read_i32(array_get(sd, 6), S.vints);
		read_f64(array_get(sd, 7), S.vfl);
		const void *nzs = arr_of(array_get(sd, 8));
		int64_t nn = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, nzs);
		S.noises.resize(nn);
		for (int64_t k = 0; k < nn; k++) {
			const void *e = arr_of(array_get(nzs, k));
			std::vector<int> perm;
			std::vector<double> off;
			read_i32(array_get(e, 0), perm);
			read_f64(array_get(e, 1), off);
			Normal &nz = S.noises[k];
			read_f64(array_get(e, 2), nz.in);
			read_f64(array_get(e, 3), nz.amp);
			nz.oct.resize(nz.in.size());
			for (size_t o = 0; o < nz.in.size(); o++) {
				for (int q = 0; q < 256; q++) nz.oct[o].p[q] = perm[o * 256 + q];
				nz.oct[o].xo = off[o * 3]; nz.oct[o].yo = off[o * 3 + 1]; nz.oct[o].zo = off[o * 3 + 2];
			}
		}
		const void *ps = arr_of(array_get(sd, 9));
		int64_t np = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, ps);
		S.poss.resize(np);
		for (int64_t k = 0; k < np; k++) {
			const void *e = arr_of(array_get(ps, k));
			S.poss[k].legacy = int_of(array_get(e, 0)) != 0;
			S.poss[k].lo = int_of(array_get(e, 1));
			S.poss[k].hi = int_of(array_get(e, 2));
		}
		read_i32(array_get(sd, 10), S.bands);
		read_f64(array_get(sd, 11), S.temps);
		S.ok = !S.rints.empty();
	}
	if (size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, desc) > 7) {
		// climate: [flags(ok, src_ok, single, plains, nodes x6), pmin(6n), pmax(6n), offs, pgroup, pbiome, glo, ghi] (floats hold ints)
		const void *cd = arr_of(array_get(desc, 7));
		ClimateCfg &C = c->clim;
		std::vector<int> fl, pg, pb;
		std::vector<double> mn, mx, of, gl, gh;
		read_i32(array_get(cd, 0), fl);
		read_f64(array_get(cd, 1), mn);
		read_f64(array_get(cd, 2), mx);
		read_f64(array_get(cd, 3), of);
		read_i32(array_get(cd, 4), pg);
		read_i32(array_get(cd, 5), pb);
		read_f64(array_get(cd, 6), gl);
		read_f64(array_get(cd, 7), gh);
		C.ok = fl[0] != 0; C.src_ok = fl[1] != 0; C.single = fl[2]; C.plains = fl[3];
		for (int k = 0; k < 6; k++) C.nodes[k] = fl[4 + k];
		C.n = (int)of.size();
		C.ng = (int)gl.size();
		for (int k = 0; k < 6; k++) {
			C.pmin[k].resize(C.n); C.pmax[k].resize(C.n);
			for (int i = 0; i < C.n; i++) { C.pmin[k][i] = (int64_t)mn[(size_t)k * C.n + i]; C.pmax[k][i] = (int64_t)mx[(size_t)k * C.n + i]; }
		}
		C.offs.resize(C.n);
		for (int i = 0; i < C.n; i++) C.offs[i] = (int64_t)of[i];
		C.pgroup = pg; C.pbiome = pb;
		C.glo.resize(C.ng); C.ghi.resize(C.ng);
		for (int g = 0; g < C.ng; g++) { C.glo[g] = (int64_t)gl[g]; C.ghi[g] = (int64_t)gh[g]; }
		for (int k = 0; k < 6; k++) if (C.nodes[k] < 0) { C.ok = false; C.src_ok = C.single >= 0; }
	}
	int64_t h;
	{
		std::lock_guard<std::mutex> lk(c_mutex);
		g_cfgs.push_back(c);
		h = (int64_t)g_cfgs.size() - 1;
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, h);
	return true;
}

bool fn_tg_begin(const Args &a, void *ret) {
	const Cfg *c = cfg_of(a.i(0));
	if (!c) return false;
	Job *j = new Job(*c, (int)a.i(1), (int)a.i(2));
	if (const void *bp = a.obj(3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)) {
		int64_t nb = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, bp);
		if (nb >= 8) j->beard.assign(i32(bp), i32(bp) + nb);
	}
	Owned col(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, col.ptr(), 98304);
	j->fill(i32_w(col.ptr()));
	Owned bio(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	bool has_bio = c->clim.ok;
	if (has_bio) {
		resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, bio.ptr(), 1536);
		static int bprof = getenv("RC_DFPROF") ? 1 : 0;
		LARGE_INTEGER b0, b1, bq;
		if (bprof) { QueryPerformanceFrequency(&bq); QueryPerformanceCounter(&b0); }
		j->biomes(bytes_w(bio.ptr()));
		if (bprof) { QueryPerformanceCounter(&b1); printf("[dfprof] biomes %.2f ms\n", (b1.QuadPart - b0.QuadPart) * 1000.0 / (double)bq.QuadPart); fflush(stdout); }
	}
	int64_t h;
	{
		std::lock_guard<std::mutex> lk(j_mutex);
		if (!g_free_jobs.empty()) { h = g_free_jobs.back(); g_free_jobs.pop_back(); g_jobs[h] = j; }
		else { g_jobs.push_back(j); h = (int64_t)g_jobs.size() - 1; }
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, has_bio ? 4 : 3);
	array_set_int(ret, 0, h);
	array_set_native(ret, 1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, col.ptr());
	array_set_int(ret, 2, j->skip_above);
	if (has_bio) array_set_native(ret, 3, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, bio.ptr());
	return true;
}

bool fn_tg_carve(const Args &a, void *ret) {
	Job *j = job_of(a.i(0));
	const void *col_in = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *src = a.obj(2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	if (!j || !col_in || !src || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, col_in) != 98304) return false;
	if (!j->c.clim.src_ok && size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, src) != 289) return false;
	Owned col(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, col.ptr(), 98304);
	int32_t *o = i32_w(col.ptr());
	memcpy(o, i32(col_in), 98304 * sizeof(int32_t));
	j->carve(o, i32(src));
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, col.ptr());
	return true;
}

// tg_surface(job, col, biomes: PackedByteArray(1536)) -> [col]   (heightmap computed here, WORLD_SURFACE_WG)
bool fn_tg_surface(const Args &a, void *ret) {
	Job *j = job_of(a.i(0));
	const void *col_in = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *bio = a.obj(2, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!j || !col_in || !bio || !j->c.surf.ok || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, col_in) != 98304 || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, bio) < 1536) return false;
	Owned col(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, col.ptr(), 98304);
	int32_t *o = i32_w(col.ptr());
	memcpy(o, i32(col_in), 98304 * sizeof(int32_t));
	int32_t hm[256];
	for (int cc = 0; cc < 256; cc++) {
		int top = MIN_Y;
		for (int ly = HEIGHT - 1; ly >= 0; ly--) {
			if (o[(ly << 8) | cc] != 0) { top = MIN_Y + ly + 1; break; }
		}
		hm[cc] = top;
	}
	j->surface(o, bytes(bio), hm);
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, col.ptr());
	return true;
}

bool fn_tg_end(const Args &a, void *ret) {
	int64_t h = a.i(0);
	Job *j = nullptr;
	{
		std::lock_guard<std::mutex> lk(j_mutex);
		if (h >= 0 && h < (int64_t)g_jobs.size() && g_jobs[h]) { j = g_jobs[h]; g_jobs[h] = nullptr; g_free_jobs.push_back(h); }
	}
	delete j;
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 0);
	return true;
}

// tg_column(cfg, x, z) -> [PackedByteArray(gen_depth)]: Job::column (getBaseColumn) of block column (x, z)
bool fn_tg_column(const Args &a, void *ret) {
	const Cfg *c = cfg_of(a.i(0));
	if (!c) return false;
	int x = (int)a.i(1), z = (int)a.i(2);
	Job j(*c, x >> 4, z >> 4);
	Owned col(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, col.ptr(), c->gen_depth);
	j.column(x, z, bytes_w(col.ptr()));
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, col.ptr());
	return true;
}

bool fn_tg_surface_grid(const Args &a, void *ret) {
	const Cfg *c = cfg_of(a.i(0));
	if (!c) return false;
	Job j(*c, 0, 0);
	double v = j.grid_surface(a.i(1), a.i(2));
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_float(ret, 0, v);
	return true;
}

// Java BiomeSource.getBiomesWithin(x, y, z, radius): the distinct biomes over the quart cube around the point
// (OceanMonumentStructure's surrounding check). tg_biomes_within(cfg, x, y, z, radius) -> [PackedInt32Array ids]
bool fn_tg_biomes_within(const Args &a, void *ret) {
	const Cfg *c = cfg_of(a.i(0));
	if (!c) return false;
	int x = (int)a.i(1), y = (int)a.i(2), z = (int)a.i(3), r = (int)a.i(4);
	const ClimateCfg &C = c->clim;
	std::vector<int> ids;
	if (C.single >= 0) {
		ids.push_back(C.single);
	} else {
		Eval ev(*c->g, 0, 0, false);
		ev.mode = 0;
		int i0 = (x - r) >> 2, j0 = (y - r) >> 2, k0 = (z - r) >> 2;
		int i1 = (x + r) >> 2, j1 = (y + r) >> 2, k1 = (z + r) >> 2;
		std::vector<int64_t> best(C.ng);
		std::vector<int> bi(C.ng);
		std::vector<char> seen(4096, 0);
		for (int qz = k0; qz <= k1; qz++)
			for (int qx = i0; qx <= i1; qx++) {
				double v[6];
				for (int k = 0; k < 6; k++) v[k] = k == 4 ? 0.0 : ev.at(C.nodes[k], qx * 4, 0, qz * 4);
				climate_column(C, v[0], v[1], v[2], v[3], v[5], best.data(), bi.data());
				for (int qy = j0; qy <= j1; qy++) {
					double d = ev.at(C.nodes[4], qx * 4, qy * 4, qz * 4);
					int id = climate_pick(C, best.data(), bi.data(), d);
					if (id >= 0 && id < 4096 && !seen[id]) { seen[id] = 1; ids.push_back(id); }
				}
			}
	}
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, out.ptr(), (int64_t)ids.size());
	int32_t *w = i32_w(out.ptr());
	for (size_t i = 0; i < ids.size(); i++) w[i] = ids[i];
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, out.ptr());
	return true;
}

// tg_biome_at(cfg, x, y, z) -> [biome id, -1 without multi-noise biomes]: Java getNoiseBiome at the block's quart
// position (the horizontal climate values from the column, depth at the quart y - as the chunk biomes).
bool fn_tg_biome_at(const Args &a, void *ret) {
	const Cfg *c = cfg_of(a.i(0));
	if (!c) return false;
	int x = (int)a.i(1), y = (int)a.i(2), z = (int)a.i(3);
	const ClimateCfg &C = c->clim;
	int id = -1;
	if (C.single >= 0) {
		id = C.single;
	} else if (C.ok) {
		Eval ev(*c->g, 0, 0, false);
		ev.mode = 0;
		int qx = x >> 2, qy = y >> 2, qz = z >> 2;
		std::vector<int64_t> best(C.ng);
		std::vector<int> bi(C.ng);
		double v[6];
		for (int k = 0; k < 6; k++) v[k] = k == 4 ? 0.0 : ev.at(C.nodes[k], qx * 4, 0, qz * 4);
		climate_column(C, v[0], v[1], v[2], v[3], v[5], best.data(), bi.data());
		id = climate_pick(C, best.data(), bi.data(), ev.at(C.nodes[4], qx * 4, qy * 4, qz * 4));
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, id);
	return true;
}

// tg_find_biome(cfg, want: PackedByteArray (1 per accepted biome id), x, z, ys: PackedInt32Array, size, step)
//   -> [found 0/1, x, y, z, biome id]. Java BiomeSource.findClosestBiome3d: columns in BlockPos.spiralAround order
//   (east, south, west, north legs of 1, 1, 2, 2, 3, ... steps; (2 size + 1)^2 columns) step blocks apart, at each the
//   heights ys (Mth.outFromOrigin order), the first quart biome accepted wins. -1 found: no multi-noise biomes.
bool fn_tg_find_biome(const Args &a, void *ret) {
	const Cfg *c = cfg_of(a.i(0));
	if (!c) return false;
	const void *wantp = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	const void *ysp = a.obj(4, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	if (!wantp || !ysp) return false;
	int nw = (int)size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, wantp);
	const uint8_t *want = bytes(wantp);
	int ny = (int)size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, ysp);
	const int32_t *ys = i32(ysp);
	int x0 = (int)a.i(2), z0 = (int)a.i(3);
	int size = (int)a.i(5), step = (int)a.i(6);
	const ClimateCfg &C = c->clim;
	int found = 0, fx = 0, fy = 0, fz = 0, fid = -1;
	auto accept = [&](int id) { return id >= 0 && id < nw && want[id] != 0; };
	if (C.single >= 0) {
		if (accept(C.single) && ny > 0) { found = 1; fx = x0; fy = ys[0]; fz = z0; fid = C.single; }
	} else if (!C.ok) {
		found = -1;
	} else if (ny > 0) {
		Eval ev(*c->g, 0, 0, false);
		ev.mode = 0;
		std::vector<int64_t> best(C.ng);
		std::vector<int> bi(C.ng);
		static const int DX[4] = {1, 0, -1, 0};   // east, south, west, north
		static const int DZ[4] = {0, 1, 0, -1};
		int64_t total = (int64_t)(2 * size + 1) * (2 * size + 1);
		int64_t emitted = 0;
		int cx = 0, cz = 0, leg = 0, li = 0;
		while (emitted < total && !found) {
			if (emitted > 0) {
				int len = leg / 2 + 1;
				cx += DX[leg & 3];
				cz += DZ[leg & 3];
				if (++li >= len) { li = 0; leg++; }
			}
			emitted++;
			int bx = x0 + cx * step, bz = z0 + cz * step;
			int qx = bx >> 2, qz = bz >> 2;
			double v[6];
			for (int k = 0; k < 6; k++) v[k] = k == 4 ? 0.0 : ev.at(C.nodes[k], qx * 4, 0, qz * 4);
			climate_column(C, v[0], v[1], v[2], v[3], v[5], best.data(), bi.data());
			for (int yi = 0; yi < ny; yi++) {
				int id = climate_pick(C, best.data(), bi.data(), ev.at(C.nodes[4], qx * 4, (ys[yi] >> 2) * 4, qz * 4));
				if (accept(id)) { found = 1; fx = bx; fy = ys[yi]; fz = bz; fid = id; break; }
			}
		}
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 5);
	array_set_int(ret, 0, found);
	array_set_int(ret, 1, fx);
	array_set_int(ret, 2, fy);
	array_set_int(ret, 3, fz);
	array_set_int(ret, 4, fid);
	return true;
}

} // namespace

void register_terrain(const char *cls) {
	register_method(cls, "tg_biome_at", fn_tg_biome_at, 4);
	register_method(cls, "tg_find_biome", fn_tg_find_biome, 7);
	register_method(cls, "tg_biomes_within", fn_tg_biomes_within, 5);
	register_method(cls, "tg_config", fn_tg_config, 2);
	register_method(cls, "tg_begin", fn_tg_begin, 3);
	register_method(cls, "tg_carve", fn_tg_carve, 3);
	register_method(cls, "tg_end", fn_tg_end, 1);
	register_method(cls, "tg_surface", fn_tg_surface, 3);
	register_method(cls, "tg_surface_grid", fn_tg_surface_grid, 3);
	register_method(cls, "tg_column", fn_tg_column, 3);
}
