// Native density-function engine: evaluates the DFCompiler DAG exported by DensityFunctions.export_native()
// with the same per-node formulas as DensityFunctions.DF._point (scripts/world/density_functions.gd) and the
// same noise algorithms as scripts/world/noise.gd (MCNoise Normal / Blended / Simplex / end island height).
// Interpolated nodes use the chunk corner grid; block mode interpolates y, z, x (the GDScript cell path), point
// mode x, y, z (DF._interp_at). 2D nodes are cached per column, shared subgraphs per point (memo stamps).
//   df_graph(desc: Array) -> [handle]
//   df_chunk(handle, node, cx, cz) -> [PackedFloat64Array(98304)]     index ((y+64)<<8)|(z<<4)|x
//   df_points(handle, node, xs, ys, zs: PackedInt32Array, cx, cz, has_chunk) -> [PackedFloat64Array]
#include "density_core.h"
#include <vector>
#include <cmath>
#include <mutex>
#include <unordered_map>
#include <algorithm>

using namespace gdx;

namespace {
using namespace rn;

// ---------------------------------------------------------------- descriptor import
template <typename T>
static void read_packed_i32(const void *v, std::vector<T> &out) {
	const void *a = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)v);
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, a);
	const int32_t *d = i32(a);
	out.assign(d, d + n);
}
static void read_packed_f64(const void *v, std::vector<double> &out) {
	const void *a = internal(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY)((GDExtensionVariantPtr)v);
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, a);
	const double *d = f64(a);
	out.assign(d, d + n);
}
static const void *arr_of(const void *v) { return internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)v); }
static int64_t int_of(const void *v) { int64_t r = 0; to_type(GDEXTENSION_VARIANT_TYPE_INT)(&r, (GDExtensionVariantPtr)v); return r; }

static void read_improved(const std::vector<int> &perm, size_t po, const std::vector<double> &off, size_t oo, Improved &imp) {
	for (int i = 0; i < 256; i++) imp.p[i] = perm[po + i];
	imp.xo = off[oo]; imp.yo = off[oo + 1]; imp.zo = off[oo + 2];
}

bool fn_df_graph(const Args &a, void *ret) {
	const void *desc = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	if (!desc) return false;
	Graph *gr = new Graph();
	std::vector<int> ni;
	std::vector<double> nf;
	read_packed_i32(array_get(desc, 0), ni);
	read_packed_f64(array_get(desc, 1), nf);
	read_packed_i32(array_get(desc, 2), gr->funcs);
	read_packed_f64(array_get(desc, 3), gr->thresholds);
	const int NI = 15, NF = 6;
	size_t nn = ni.size() / NI;
	gr->nodes.resize(nn);
	for (size_t i = 0; i < nn; i++) {
		Node &d = gr->nodes[i];
		const int *p = &ni[i * NI];
		d.k = p[0]; d.a = p[1]; d.b = p[2]; d.c = p[3]; d.axis = p[4]; d.cxz = p[5]; d.cy = p[6]; d.is2d = p[7];
		d.lower = p[8]; d.noise = p[9]; d.blended = p[10]; d.spline = p[11]; d.funcs_off = p[12]; d.funcs_n = p[13]; d.end = p[14];
		d.v0 = nf[i * NF]; d.v1 = nf[i * NF + 1]; d.v2 = nf[i * NF + 2]; d.v3 = nf[i * NF + 3]; d.lo = nf[i * NF + 4]; d.hi = nf[i * NF + 5];
	}
	// noises: [perm (256/oct), off (3/oct), in, amp]
	const void *noises = arr_of(array_get(desc, 4));
	int64_t nnz = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, noises);
	gr->noises.resize(nnz);
	for (int64_t k = 0; k < nnz; k++) {
		const void *e = arr_of(array_get(noises, k));
		std::vector<int> perm;
		std::vector<double> off;
		read_packed_i32(array_get(e, 0), perm);
		read_packed_f64(array_get(e, 1), off);
		Normal &nz = gr->noises[k];
		read_packed_f64(array_get(e, 2), nz.in);
		read_packed_f64(array_get(e, 3), nz.amp);
		nz.oct.resize(nz.in.size());
		for (size_t o = 0; o < nz.in.size(); o++) read_improved(perm, o * 256, off, o * 3, nz.oct[o]);
	}
	// blended: [perm (40*256), off (40*3), present (40 ints), scalars (5)]
	const void *bl = arr_of(array_get(desc, 5));
	int64_t nbl = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, bl);
	gr->blended.resize(nbl);
	for (int64_t k = 0; k < nbl; k++) {
		const void *e = arr_of(array_get(bl, k));
		std::vector<int> perm, present;
		std::vector<double> off, sc;
		read_packed_i32(array_get(e, 0), perm);
		read_packed_f64(array_get(e, 1), off);
		read_packed_i32(array_get(e, 2), present);
		read_packed_f64(array_get(e, 3), sc);
		Blended &b = gr->blended[k];
		for (int o = 0; o < 40; o++) {
			Improved *imp = o < 8 ? &b.main_oct[o] : (o < 24 ? &b.min_oct[o - 8] : &b.max_oct[o - 24]);
			bool *pr = o < 8 ? &b.main_p[o] : (o < 24 ? &b.min_p[o - 8] : &b.max_p[o - 24]);
			*pr = present[o] != 0;
			if (*pr) read_improved(perm, o * 256, off, o * 3, *imp);
		}
		b.xz_mul = sc[0]; b.y_mul = sc[1]; b.xz_factor = sc[2]; b.y_factor = sc[3]; b.smear = sc[4];
	}
	// splines: [coord, locs, ders, vals, val_spline]
	const void *sps = arr_of(array_get(desc, 6));
	int64_t nsp = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, sps);
	gr->splines.resize(nsp);
	for (int64_t k = 0; k < nsp; k++) {
		const void *e = arr_of(array_get(sps, k));
		Spline &s = gr->splines[k];
		s.coord = (int)int_of(array_get(e, 0));
		read_packed_f64(array_get(e, 1), s.locs);
		read_packed_f64(array_get(e, 2), s.ders);
		read_packed_f64(array_get(e, 3), s.vals);
		read_packed_i32(array_get(e, 4), s.val_spline);
	}
	// end simplex permutations
	const void *ends = arr_of(array_get(desc, 7));
	int64_t ne = size_of(GDEXTENSION_VARIANT_TYPE_ARRAY, ends);
	gr->ends.resize(ne);
	for (int64_t k = 0; k < ne; k++) {
		std::vector<int> perm;
		read_packed_i32(array_get(ends, k), perm);
		for (int i = 0; i < 256; i++) gr->ends[k].p[i] = perm[i];
	}
	int64_t handle;
	{
		std::lock_guard<std::mutex> lk(g_mutex);
		g_graphs.push_back(gr);
		handle = (int64_t)g_graphs.size() - 1;
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, handle);
	return true;
}

} // namespace

namespace rn {
std::mutex g_mutex;
std::vector<Graph *> g_graphs;
const Graph *graph_of(int64_t h) {
	std::lock_guard<std::mutex> lk(g_mutex);
	if (h < 0 || h >= (int64_t)g_graphs.size()) return nullptr;
	return g_graphs[h];
}
} // namespace rn

namespace {
using namespace rn;

bool fn_df_chunk(const Args &a, void *ret) {
	const Graph *gr = graph_of(a.i(0));
	int node = (int)a.i(1);
	int cx = (int)a.i(2), cz = (int)a.i(3);
	int nlo = (int)a.i(4), nhi = (int)a.i(5);   // noise range: rows outside are -1 (no terrain)
	if (!gr || node < 0 || node >= (int)gr->nodes.size()) return false;
	Eval *ev = new Eval(*gr, cx, cz, true);
	ev->mode = 1;
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, out.ptr(), 98304);
	double *o = f64_w(out.ptr());
	int x0 = cx * 16, z0 = cz * 16;
	for (int ly = 0; ly < HEIGHT; ly++) {
		for (int lz = 0; lz < 16; lz++) {
			for (int lx = 0; lx < 16; lx++) {
				int x = x0 + lx, y = MIN_Y + ly, z = z0 + lz;
				if (y < nlo || y >= nhi) { o[(ly << 8) | (lz << 4) | lx] = -1.0; continue; }
				ev->px = x; ev->py = y; ev->pz = z;
				ev->cur = ev->next_stamp();
				o[(ly << 8) | (lz << 4) | lx] = ev->ev(node, x, y, z);
			}
		}
	}
	delete ev;
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, out.ptr());
	return true;
}

// several nodes at the same points: df_points(handle, nodes: PackedInt32Array, xs, ys, zs, cx, cz, has_chunk)
//   -> [PackedFloat64Array(nodes * n)] (node-major)
bool fn_df_points(const Args &a, void *ret) {
	const Graph *gr = graph_of(a.i(0));
	const void *nodes = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *xs = a.obj(2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *ys = a.obj(3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *zs = a.obj(4, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	if (!gr || !nodes || !xs || !ys || !zs) return false;
	int cx = (int)a.i(5), cz = (int)a.i(6);
	bool hc = a.i(7) != 0;
	int64_t nn = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, nodes);
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, xs);
	const int32_t *nd = i32(nodes), *px = i32(xs), *py = i32(ys), *pz = i32(zs);
	Eval *ev = new Eval(*gr, cx, cz, hc);
	ev->mode = a.i(7) == 2 ? 1 : 0;   // has_chunk 2: block mode (the terrain fill's y, z, x interpolation order)
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, out.ptr(), nn * n);
	double *o = nn * n > 0 ? f64_w(out.ptr()) : nullptr;
	for (int64_t k = 0; k < nn; k++) {
		for (int64_t i = 0; i < n; i++) {
			ev->px = px[i]; ev->py = py[i]; ev->pz = pz[i];
			ev->cur = ev->next_stamp();
			o[k * n + i] = ev->ev(nd[k], px[i], py[i], pz[i]);
		}
	}
	delete ev;
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, out.ptr());
	return true;
}

} // namespace

void register_density(const char *cls) {
	register_method(cls, "df_graph", fn_df_graph, 1);
	register_method(cls, "df_chunk", fn_df_chunk, 6);
	register_method(cls, "df_points", fn_df_points, 8);
}
