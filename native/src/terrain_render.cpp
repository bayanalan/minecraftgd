// terrain_render — data side of the RenderingDevice terrain renderer (scripts/world/terrain_rd.gd).
//
// tr_pack(arrays, flags) -> [PackedByteArray verts, PackedInt32Array counts(7), PackedFloat32Array bounds(6)]
//   Converts one chunk-group surface (Mesh arrays from the mesher: VERTEX, TEX_UV, COLOR, CUSTOM0 RGBA half, INDEX;
//   quads = 4 consecutive vertices + 6 indices, normal pattern (0,3,2)(0,2,1), flipped (1,0,3)(1,3,2)) into
//   20-byte vertices (5 x u32) with quads sorted into 7 direction buckets (+X -X +Y -Y +Z -Z other); flipped quads
//   are stored rotated by one vertex so a single index pattern (0,3,2)(0,2,1) draws every quad:
//     w0 = x16 | z16 << 16   (x,z: (p + 8) * 2048)
//     w1 = y16 | slot << 17  (y: (p + 8) * 512; slot: group origin index, written by tr_stamp)
//     w2 = u16 | v16 << 16   (uv: (t + 8) * 2048)
//     w3 = RGBA8 colour (tint rgb, ao*shade in alpha)
//     w4 = layer 12 | overlay palette index 6 (63 = none) << 12 | sky 6 << 18 | block 6 << 24 (light in quarter levels
//          0..60: Java's smooth-lighting blend keeps .25 steps and samples the lightmap bilinearly between levels)
//
// Culler (handle-based, main thread): groups in dense arrays (structure of arrays for the frustum test).
//   tr_new() -> [h]; tr_clear(h) -> [1]
//   tr_put(h, key, mat, ox, oy, oz, quad_off, counts(7), bounds(6), page) -> [1]   (ox.. absolute world block coords;
//     quad_off is relative to the page's storage buffer)
//   tr_del(h, key) -> [1]
//   tr_cull_all(...): see below.
#include "native.h"
#include <vector>
#include <cstring>
#include <cmath>
#include <climits>
#include <map>
#include <array>
#include <chrono>
#include <algorithm>
#include <unordered_map>

using namespace gdx;

namespace {

struct Group {
	int mat = 0;
	int page = 0;
	int64_t ox = 0, oy = 0, oz = 0;
	uint32_t quad_off = 0;
	int nb = 7;                         // buckets: 7 directions, or 7 directions x 4 sections (direction-major)
	uint32_t cnt[28] = {};
	uint32_t start[28] = {};
	float b[6] = {0, 0, 0, 0, 0, 0};   // local min xyz, max xyz
	float sb[4][6] = {};                // sectioned groups: bounds of each section's quads (local)
};

struct TR {
	std::vector<Group> g;                       // dense
	std::vector<int64_t> keys;                  // parallel to g
	std::unordered_map<int64_t, int> idx;       // key -> index in g
	// structure of arrays for the frustum test, relative to `org` (render space): centre and half extents
	std::vector<float> cx, cy, cz, ex, ey, ez;
	int64_t org[3] = {0, 0, 0};
	// occlusion culling (Java SectionOcclusionGraph): per chunk column the 24 section visibility masks (VisGraph,
	// bit a * 6 + b: faces a and b connected); columns / sections without data count as fully connected
	std::unordered_map<int64_t, std::array<uint64_t, 24>> vism;
	bool vis_dirty = true;
	int bfs_frames = 1000;
	std::chrono::steady_clock::time_point bfs_at{};
	int64_t bfs_cam[3] = {INT64_MIN, 0, 0};
	int bfs_r = 0;
	int64_t bfs_cx0 = 0, bfs_cz0 = 0;
	std::vector<uint8_t> reach;   // per BFS grid section: reachable
	bool bfs_valid = false;
	// page allocator: free quad ranges per page by start (merging) and all free ranges by size (best fit)
	std::vector<std::map<uint32_t, uint32_t>> free_by_start;
	std::multimap<uint32_t, std::pair<int, uint32_t>> free_by_size;

	void fs_erase(uint32_t len, int pg, uint32_t start) {
		auto r = free_by_size.equal_range(len);
		for (auto it = r.first; it != r.second; ++it)
			if (it->second.first == pg && it->second.second == start) { free_by_size.erase(it); return; }
	}
	void free_range(int pg, uint32_t start, uint32_t len) {
		if (pg < 0 || pg >= (int)free_by_start.size() || len == 0) return;
		auto &m = free_by_start[pg];
		auto nx = m.lower_bound(start);
		if (nx != m.end() && start + len == nx->first) {   // merge with the next range
			fs_erase(nx->second, pg, nx->first);
			len += nx->second;
			nx = m.erase(nx);
		}
		if (nx != m.begin()) {                               // merge with the previous range
			auto pv = std::prev(nx);
			if (pv->first + pv->second == start) {
				fs_erase(pv->second, pg, pv->first);
				start = pv->first;
				len += pv->second;
				m.erase(pv);
			}
		}
		m[start] = len;
		free_by_size.insert({len, {pg, start}});
	}
	// mode 0: any page; 1: only page only (best fit inside it); 2: any page except only
	bool alloc(uint32_t n, int &pg, uint32_t &start, int mode = 0, int only = -1) {
		auto it = free_by_size.lower_bound(n);
		if (mode == 1) {
			if (only < 0 || only >= (int)free_by_start.size()) return false;
			uint32_t best = UINT32_MAX, bs = 0;
			for (auto &kv : free_by_start[only])
				if (kv.second >= n && kv.second < best) { best = kv.second; bs = kv.first; }
			if (best == UINT32_MAX) return false;
			auto r = free_by_size.equal_range(best);
			it = free_by_size.end();
			for (auto jt = r.first; jt != r.second; ++jt)
				if (jt->second.first == only && jt->second.second == bs) { it = jt; break; }
			if (it == free_by_size.end()) return false;
		} else if (mode == 2) {
			while (it != free_by_size.end() && it->second.first == only) ++it;
		}
		if (it == free_by_size.end()) return false;
		uint32_t len = it->first;
		pg = it->second.first;
		start = it->second.second;
		free_by_size.erase(it);
		free_by_start[pg].erase(start);
		if (len > n) {
			free_by_start[pg][start + n] = len - n;
			free_by_size.insert({len - n, {pg, start + n}});
		}
		return true;
	}
	void soa(int i) {
		const Group &q = g[i];
		cx[i] = (float)(q.ox - org[0]) + (q.b[0] + q.b[3]) * 0.5f;
		cy[i] = (float)(q.oy - org[1]) + (q.b[1] + q.b[4]) * 0.5f;
		cz[i] = (float)(q.oz - org[2]) + (q.b[2] + q.b[5]) * 0.5f;
		ex[i] = (q.b[3] - q.b[0]) * 0.5f;
		ey[i] = (q.b[4] - q.b[1]) * 0.5f;
		ez[i] = (q.b[5] - q.b[2]) * 0.5f;
	}
	void put(int64_t key, const Group &q) {
		auto it = idx.find(key);
		int i;
		if (it != idx.end()) {
			i = it->second;
			g[i] = q;
		} else {
			i = (int)g.size();
			g.push_back(q);
			keys.push_back(key);
			cx.push_back(0); cy.push_back(0); cz.push_back(0); ex.push_back(0); ey.push_back(0); ez.push_back(0);
			idx[key] = i;
		}
		soa(i);
	}
	void del(int64_t key) {
		auto it = idx.find(key);
		if (it == idx.end()) return;
		int i = it->second, last = (int)g.size() - 1;
		idx.erase(it);
		if (i != last) {
			g[i] = g[last]; keys[i] = keys[last];
			cx[i] = cx[last]; cy[i] = cy[last]; cz[i] = cz[last]; ex[i] = ex[last]; ey[i] = ey[last]; ez[i] = ez[last];
			idx[keys[i]] = i;
		}
		g.pop_back(); keys.pop_back();
		cx.pop_back(); cy.pop_back(); cz.pop_back(); ex.pop_back(); ey.pop_back(); ez.pop_back();
	}
	void clear() {
		vism.clear(); bfs_valid = false; vis_dirty = true;
		free_by_start.clear(); free_by_size.clear();
		g.clear(); keys.clear(); idx.clear();
		cx.clear(); cy.clear(); cz.clear(); ex.clear(); ey.clear(); ez.clear();
	}
	void set_org(int64_t x, int64_t y, int64_t z) {
		if (x == org[0] && y == org[1] && z == org[2]) return;
		org[0] = x; org[1] = y; org[2] = z;
		for (int i = 0; i < (int)g.size(); i++) soa(i);
	}
};

std::vector<TR *> g_tr;

inline uint16_t q16(double v, double off, double scale) {
	double t = (v + off) * scale;
	if (t < 0) t = 0;
	if (t > 65535) t = 65535;
	return (uint16_t)std::lround(t);
}

inline float half_to_float(uint16_t h) {
	uint32_t s = (h >> 15) & 1, e = (h >> 10) & 0x1F, m = h & 0x3FF;
	uint32_t f;
	if (e == 0) f = s << 31;   // Godot flushes denormals to zero
	else if (e == 31) f = (s << 31) | 0x7F800000u | (m << 13);
	else f = (s << 31) | ((e - 15 + 127) << 23) | (m << 13);
	float r;
	memcpy(&r, &f, 4);
	return r;
}

const void *pk(const void *arr, int64_t k, GDExtensionVariantType t) {
	const void *e = array_get(arr, k);
	if (!e || variant_get_type((GDExtensionConstVariantPtr)e) != t) return nullptr;
	return internal(t)((GDExtensionVariantPtr)e);
}

bool fn_tr_pack(const Args &a, void *ret) {
	const void *arrs = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	if (!arrs) return false;
	const void *vv = pk(arrs, 0, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY);
	const void *cv = pk(arrs, 3, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	const void *uvv = pk(arrs, 4, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY);
	const void *cuv = pk(arrs, 6, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	const void *iv = pk(arrs, 12, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	if (!vv || !cv || !uvv || !cuv || !iv) return false;
	int64_t nv = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, vv);
	int64_t ni = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, iv);
	int64_t nq = nv / 4;
	if (nq * 4 != nv || ni != nq * 6) return false;
	const float *P = vec3(vv);
	const float *C = color(cv);
	const float *U = vec2_w(const_cast<void *>(uvv));
	const uint8_t *CU = bytes(cuv);
	const int32_t *I = i32(iv);
	// flags & 1: buckets per (direction, 16-block section of the group), direction-major, so the culler can drop hidden
	// sections while a visible direction stays one contiguous range (opaque / cutout: order-independent). Stable: quads
	// keep their relative order inside a bucket (same-block coplanar faces stay in order).
	const bool sectioned = (a.i(1) & 1) != 0;
	// overlay layer -> palette index (TerrainRD.overlay_palette; 63 = none / not in the palette)
	const void *omv = a.obj(2, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	const uint8_t *omap = omv ? bytes(omv) : nullptr;
	const int64_t nomap = omv ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, omv) : 0;
	const int NBK = sectioned ? 28 : 7;
	std::vector<uint32_t> buckets[28];
	float smn[4][3], smx[4][3];
	for (int k = 0; k < 4; k++) for (int c = 0; c < 3; c++) { smn[k][c] = 1e9f; smx[k][c] = -1e9f; }
	float mn[3] = {1e9f, 1e9f, 1e9f}, mx[3] = {-1e9f, -1e9f, -1e9f};
	for (int64_t q = 0; q < nq; q++) {
		int64_t b0 = q * 4;
		bool flip = I[q * 6] == (int32_t)(b0 + 1);
		// face normal from the first triangle (indices as emitted)
		const float *A = P + I[q * 6] * 3, *B = P + I[q * 6 + 1] * 3, *Cc = P + I[q * 6 + 2] * 3;
		double ux = B[0] - A[0], uy = B[1] - A[1], uz = B[2] - A[2], vx = Cc[0] - A[0], vy = Cc[1] - A[1], vz = Cc[2] - A[2];
		double nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
		double len = std::sqrt(nx * nx + ny * ny + nz * nz);
		int dir = 6;
		if (len > 1e-12) {
			nx /= len; ny /= len; nz /= len;
			// mesher winding (clockwise front faces): the outward face normal is -(B-A)x(C-A) (verified visually)
			nx = -nx; ny = -ny; nz = -nz;
			if (nx > 0.999) dir = 0; else if (nx < -0.999) dir = 1;
			else if (ny > 0.999) dir = 2; else if (ny < -0.999) dir = 3;
			else if (nz > 0.999) dir = 4; else if (nz < -0.999) dir = 5;
		}
		int bk = dir;
		int sec = 0;
		if (sectioned) {
			// owning block's section: up faces belong to the block below their plane, down faces to the block above
			double cy = 0;
			for (int kk = 0; kk < 4; kk++) cy += P[(b0 + kk) * 3 + 1];
			cy *= 0.25;
			if (dir == 2) cy -= 0.5; else if (dir == 3) cy += 0.5;
			sec = (int)std::floor(cy / 16.0);
			sec = sec < 0 ? 0 : (sec > 3 ? 3 : sec);
			bk = dir * 4 + sec;
		}
		for (int kk = 0; kk < 4; kk++) {
			// flipped quads are stored rotated by one vertex so every quad uses the same index pattern (0,3,2)(0,2,1)
			int k = flip ? ((kk + 1) & 3) : kk;
			int64_t vi = b0 + k;
			const float *p = P + vi * 3;
			for (int c = 0; c < 3; c++) {
				mn[c] = std::min(mn[c], p[c]); mx[c] = std::max(mx[c], p[c]);
				smn[sec][c] = std::min(smn[sec][c], p[c]); smx[sec][c] = std::max(smx[sec][c], p[c]);
			}
			const float *uv = U + vi * 2;
			const float *col = C + vi * 4;
			const uint8_t *h = CU + vi * 8;
			float layer = half_to_float((uint16_t)(h[0] | (h[1] << 8)));
			float overlay = half_to_float((uint16_t)(h[2] | (h[3] << 8)));
			float sky = half_to_float((uint16_t)(h[4] | (h[5] << 8)));
			float blk = half_to_float((uint16_t)(h[6] | (h[7] << 8)));
			uint32_t lay = (uint32_t)std::max(0L, std::lround(layer)) & 0xFFF;
			long ol = overlay < 0 ? -1 : std::lround(overlay);
			uint32_t ovl = (ol < 0 || ol >= nomap) ? 63u : (uint32_t)(omap[ol] & 63);
			uint32_t sk = (uint32_t)std::min(60L, std::max(0L, std::lround(sky * 60.0)));
			uint32_t bl = (uint32_t)std::min(60L, std::max(0L, std::lround(blk * 60.0)));
			auto c8 = [](float f) -> uint32_t { long v = std::lround(f * 255.0); return (uint32_t)std::min(255L, std::max(0L, v)); };
			uint32_t w0 = q16(p[0], 8.0, 2048.0) | ((uint32_t)q16(p[2], 8.0, 2048.0) << 16);
			uint32_t w1 = q16(p[1], 8.0, 512.0);   // bits 17..31: group slot (tr_stamp)
			uint32_t w2 = q16(uv[0], 8.0, 2048.0) | ((uint32_t)q16(uv[1], 8.0, 2048.0) << 16);
			uint32_t w3 = c8(col[0]) | (c8(col[1]) << 8) | (c8(col[2]) << 16) | (c8(col[3]) << 24);
			uint32_t w4 = lay | (ovl << 12) | (sk << 18) | (bl << 24);
			std::vector<uint32_t> &bv = buckets[bk];
			bv.push_back(w0); bv.push_back(w1); bv.push_back(w2); bv.push_back(w3); bv.push_back(w4);
		}
	}
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr(), nq * 80);
	Owned cnt(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, cnt.ptr(), NBK);
	Owned bnd(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, bnd.ptr(), sectioned ? 30 : 6);
	uint8_t *o = nq ? bytes_w(out.ptr()) : nullptr;
	int32_t *co = i32_w(cnt.ptr());
	size_t off = 0;
	for (int d = 0; d < NBK; d++) {
		co[d] = (int32_t)(buckets[d].size() / 20);
		if (!buckets[d].empty()) {
			memcpy(o + off, buckets[d].data(), buckets[d].size() * 4);
			off += buckets[d].size() * 4;
		}
	}
	float *bo = f32_w(bnd.ptr());
	for (int c = 0; c < 3; c++) { bo[c] = nq ? mn[c] : 0; bo[3 + c] = nq ? mx[c] : 0; }
	if (sectioned)
		for (int k = 0; k < 4; k++)
			for (int c = 0; c < 3; c++) {
				bool e = smn[k][c] > smx[k][c];
				bo[6 + k * 6 + c] = e ? 0 : smn[k][c];
				bo[6 + k * 6 + 3 + c] = e ? 0 : smx[k][c];
			}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 3);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr());
	array_set_native(ret, 1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, cnt.ptr());
	array_set_native(ret, 2, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, bnd.ptr());
	return true;
}

TR *get_tr(int64_t h) { return (h >= 0 && h < (int64_t)g_tr.size()) ? g_tr[h] : nullptr; }

bool fn_tr_new(const Args &a, void *ret) {
	g_tr.push_back(new TR());
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, (int64_t)g_tr.size() - 1);
	return true;
}

bool fn_tr_put(const Args &a, void *ret) {
	TR *t = get_tr(a.i(0));
	const void *cv = a.obj(7, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *bv = a.obj(8, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
	if (!t || !cv || !bv || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, cv) < 7 || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, bv) < 6) return false;
	const bool sectioned = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, cv) >= 28 && size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, bv) >= 30;
	Group g;
	g.mat = (int)a.i(2);
	g.ox = a.i(3); g.oy = a.i(4); g.oz = a.i(5);
	g.quad_off = (uint32_t)a.i(6);
	g.page = (int)a.i(9);
	const int32_t *c = i32(cv);
	const float *b = f32(bv);
	uint32_t s = 0;
	g.nb = sectioned ? 28 : 7;
	for (int d = 0; d < g.nb; d++) { g.cnt[d] = (uint32_t)c[d]; g.start[d] = s; s += (uint32_t)c[d]; }
	for (int k = 0; k < 6; k++) g.b[k] = b[k];
	if (sectioned)
		for (int k = 0; k < 4; k++)
			for (int j = 0; j < 6; j++) g.sb[k][j] = b[6 + k * 6 + j];
	t->put(a.i(1), g);
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, 1);
	return true;
}

bool fn_tr_del(const Args &a, void *ret) {
	TR *t = get_tr(a.i(0));
	if (!t) return false;
	t->del(a.i(1));
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, 1);
	return true;
}

// tr_quad_indices(nquads, bits) -> [PackedByteArray indices: quad q -> q*4 + (0,3,2,0,2,1)], bits 32 or 16 (n <= 16384)
bool fn_tr_quad_indices(const Args &a, void *ret) {
	int64_t n = a.i(0);
	bool b16 = a.i(1) == 16;
	if (n < 0 || (b16 && n > 16384)) return false;
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr(), n * (b16 ? 12 : 24));
	if (n > 0) {
		static const uint32_t P[6] = {0, 3, 2, 0, 2, 1};
		if (b16) {
			uint16_t *o = (uint16_t *)bytes_w(out.ptr());
			for (int64_t q = 0; q < n; q++)
				for (int k = 0; k < 6; k++) o[q * 6 + k] = (uint16_t)((uint32_t)(q * 4) + P[k]);
		} else {
			uint32_t *o = (uint32_t *)bytes_w(out.ptr());
			for (int64_t q = 0; q < n; q++)
				for (int k = 0; k < 6; k++) o[q * 6 + k] = (uint32_t)(q * 4) + P[k];
		}
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr());
	return true;
}

// tr_stamp(verts, slot) -> [PackedByteArray copy with the group slot in bits 17..31 of every vertex's w1]
bool fn_tr_stamp(const Args &a, void *ret) {
	const void *dv = a.obj(0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!dv) return false;
	uint32_t slot = (uint32_t)a.i(1) & 0x7FFFu;
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, dv);
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr(), n);
	if (n > 0) {
		uint8_t *o = bytes_w(out.ptr());
		memcpy(o, bytes(dv), (size_t)n);
		for (int64_t v = 0; v + 20 <= n; v += 20) {
			uint32_t w1;
			memcpy(&w1, o + v + 4, 4);
			w1 = (w1 & 0xFFFFu) | (slot << 17);
			memcpy(o + v + 4, &w1, 4);
		}
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr());
	return true;
}

// tr_stamp2(verts, slot) -> [positions, attributes]: the stamped 20-byte vertices split into two planar streams,
// 8 bytes (w0, w1: position + slot) and 12 bytes (w2, w3, w4: uv, colour, layers / light). Tiled GPUs (Adreno) run a
// position-only binning pass; a separate compact position stream keeps it from fetching the other 12 bytes.
bool fn_tr_stamp2(const Args &a, void *ret) {
	const void *dv = a.obj(0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!dv) return false;
	uint32_t slot = (uint32_t)a.i(1) & 0x7FFFu;
	int64_t n = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, dv);
	int64_t nv = n / 20;
	Owned po(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	Owned ao(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, po.ptr(), nv * 8);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, ao.ptr(), nv * 12);
	if (nv > 0) {
		const uint8_t *src = bytes(dv);
		uint8_t *p = bytes_w(po.ptr());
		uint8_t *q = bytes_w(ao.ptr());
		for (int64_t v = 0; v < nv; v++) {
			const uint8_t *s = src + v * 20;
			uint32_t w[5];
			memcpy(w, s, 20);
			w[1] = (w[1] & 0xFFFFu) | (slot << 17);
			memcpy(p + v * 8, w, 8);
			memcpy(q + v * 12, w + 2, 12);
		}
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 2);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, po.ptr());
	array_set_native(ret, 1, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, ao.ptr());
	return true;
}

// lightmap(params) -> [PackedByteArray 16x16 RGBA8]: Java 26.3 core/lightmap.fsh evaluated on the CPU (the texture Java
// renders every frame; x = block light level, y = sky light level). params (18 floats): SkyFactor, BlockFactor,
// NightVisionFactor, DarknessScale, BossOverlayWorldDarkeningFactor, BrightnessFactor, BlockLightTint rgb,
// SkyLightColor rgb, AmbientColor rgb, NightVisionColor rgb.
bool fn_lightmap(const Args &a, void *ret) {
	const void *pv = a.obj(0, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
	if (!pv || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, pv) < 18) return false;
	const float *P = f32(pv);
	const float sky_f = P[0], blk_f = P[1], nv_f = P[2], dark = P[3], boss = P[4], bright = P[5];
	const float *tint = P + 6, *skyc = P + 9, *amb = P + 12, *nvc = P + 15;
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr(), 16 * 16 * 4);
	uint8_t *o = bytes_w(out.ptr());
	auto brightness = [](float l) { return l / (4.0f - 3.0f * l); };
	for (int y = 0; y < 16; y++) {
		for (int x = 0; x < 16; x++) {
			float bl = (float)x / 15.0f, sl = (float)y / 15.0f;
			float bb = brightness(bl) * blk_f, sb = brightness(sl) * sky_f;
			float c[3];
			float pm = (2.0f * bl - 1.0f) * (2.0f * bl - 1.0f) * 0.9f;
			for (int k = 0; k < 3; k++) {
				c[k] = std::max(amb[k], nvc[k] * nv_f);
				c[k] += skyc[k] * sb;
				c[k] += (tint[k] + (1.0f - tint[k]) * pm) * bb;
			}
			const float bossm[3] = {0.7f, 0.6f, 0.6f};
			for (int k = 0; k < 3; k++) {
				c[k] = c[k] + (c[k] * bossm[k] - c[k]) * boss;
				c[k] -= dark;
				c[k] = std::min(1.0f, std::max(0.0f, c[k]));
			}
			float mx = std::max(c[0], std::max(c[1], c[2]));
			if (mx > 0.0f) {
				float inv = 1.0f - mx;
				float sc = (1.0f - inv * inv * inv * inv) / mx;
				for (int k = 0; k < 3; k++) c[k] = c[k] + (c[k] * sc - c[k]) * bright;
			}
			uint8_t *t = o + (y * 16 + x) * 4;
			for (int k = 0; k < 3; k++) t[k] = (uint8_t)std::lround(std::min(1.0f, std::max(0.0f, c[k])) * 255.0f);
			t[3] = 255;
		}
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr());
	return true;
}
// Page allocator (TerrainRD): tr_page_add(h, quads) -> [page index]; tr_alloc(h, quads) -> [page, start] or [-1, 0]
// (best fit over every page's free ranges); tr_free(h, page, start, quads) -> [1] (merges neighbours).
bool fn_tr_page_add(const Args &a, void *ret) {
	TR *t = get_tr(a.i(0));
	if (!t) return false;
	int pg = (int)t->free_by_start.size();
	t->free_by_start.emplace_back();
	t->free_range(pg, 0, (uint32_t)a.i(1));
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, pg);
	return true;
}

bool fn_tr_alloc(const Args &a, void *ret) {
	TR *t = get_tr(a.i(0));
	if (!t) return false;
	int pg = -1;
	uint32_t start = 0;
	if (!t->alloc((uint32_t)a.i(1), pg, start, (int)a.i(2), (int)a.i(3))) { pg = -1; start = 0; }
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 2);
	array_set_int(ret, 0, pg);
	array_set_int(ret, 1, (int64_t)start);
	return true;
}

bool fn_tr_free(const Args &a, void *ret) {
	TR *t = get_tr(a.i(0));
	if (!t) return false;
	t->free_range((int)a.i(1), (uint32_t)a.i(2), (uint32_t)a.i(3));
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, 1);
	return true;
}
// tr_clear(h) -> [1]: drops every group (world exit).
bool fn_tr_clear(const Args &a, void *ret) {
	TR *t = get_tr(a.i(0));
	if (!t) return false;
	t->clear();
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, 1);
	return true;
}

static const uint64_t VIS_ALL = (1ull << 36) - 1;

static inline int64_t fdiv16(int64_t v) { return v >= 0 ? v / 16 : -((-v + 15) / 16); }

// Java SectionOcclusionGraph BFS from the camera section over a (2R+1)^2 x 24 grid: a section may continue in direction f
// unless the path already moved the opposite way, and (except at the start) only when one of the faces it was entered
// through can see face f (VisGraph). No frustum here: computed when the camera changes section / new masks arrive.
static void occlusion_bfs(TR *t, int64_t wx, int64_t wy, int64_t wz, int R) {
	int64_t ccx = fdiv16(wx), ccz = fdiv16(wz);
	int csy = (int)std::max<int64_t>(0, std::min<int64_t>(23, fdiv16(wy + 64)));
	const int W = 2 * R + 1;
	const size_t N = (size_t)W * W * 24;
	t->reach.assign(N, 0);
	static thread_local std::vector<uint8_t> srcd, dirs;
	static thread_local std::vector<const uint64_t *> col;
	static thread_local std::vector<int> q;
	srcd.assign(N, 0);
	dirs.assign(N, 0);
	col.assign((size_t)W * W, nullptr);
	q.clear();
	for (int lz = 0; lz < W; lz++)
		for (int lx = 0; lx < W; lx++) {
			int64_t key = ((ccx - R + lx) << 32) | ((ccz - R + lz) & 0xFFFFFFFFll);
			auto it = t->vism.find(key);
			if (it != t->vism.end()) col[(size_t)lz * W + lx] = it->second.data();
		}
	static const int DX[6] = {0, 0, 0, 0, -1, 1}, DY[6] = {-1, 1, 0, 0, 0, 0}, DZ[6] = {0, 0, -1, 1, 0, 0}, OPP[6] = {1, 0, 3, 2, 5, 4};
	int s0 = (int)(((size_t)R * W + R) * 24 + csy);
	t->reach[s0] = 1;
	q.push_back(s0);
	for (size_t h = 0; h < q.size(); h++) {
		int i = q[h];
		int sy = i % 24, cl = i / 24, lx = cl % W, lz = cl / W;
		const uint64_t *cp = col[cl];
		uint64_t m = cp ? cp[sy] : VIS_ALL;
		uint8_t sd = srcd[i], dr = dirs[i];
		for (int f = 0; f < 6; f++) {
			if (dr & (1 << OPP[f])) continue;
			if (sd) {
				bool ok = false;
				for (int e = 0; e < 6 && !ok; e++)
					if (((sd >> e) & 1) && ((m >> (OPP[e] * 6 + f)) & 1)) ok = true;
				if (!ok) continue;
			}
			int nx = lx + DX[f], ny = sy + DY[f], nz = lz + DZ[f];
			if (nx < 0 || nx >= W || nz < 0 || nz >= W || ny < 0 || ny >= 24) continue;
			int j = (int)(((size_t)nz * W + nx) * 24 + ny);
			if (t->reach[j]) { srcd[j] |= (uint8_t)(1 << f); continue; }
			t->reach[j] = 1;
			srcd[j] = (uint8_t)(1 << f);
			dirs[j] = (uint8_t)(dr | (1 << f));
			q.push_back(j);
		}
	}
	t->bfs_cx0 = ccx - R;
	t->bfs_cz0 = ccz - R;
	t->bfs_r = R;
	t->bfs_valid = true;
}

static inline bool group_reachable(const TR *t, int64_t key) {
	if (!t->bfs_valid) return true;
	int64_t gk = key >> 2;
	int g = (int)(gk & 7);
	int64_t ck = gk >> 3;
	int64_t gcx = ck >> 32, gcz = (int64_t)(int32_t)(ck & 0xFFFFFFFFll);
	int64_t lx = gcx - t->bfs_cx0, lz = gcz - t->bfs_cz0;
	const int W = 2 * t->bfs_r + 1;
	if (lx < 0 || lx >= W || lz < 0 || lz >= W || g > 5) return true;
	const uint8_t *r = t->reach.data() + ((size_t)lz * W + lx) * 24 + g * 4;
	return (r[0] | r[1] | r[2] | r[3]) != 0;
}

// Sections lo..hi of a group (group-local section indices, may reach into the neighbour groups) reached by the BFS.
static inline bool sections_reachable(const TR *t, int64_t key, int lo, int hi) {
	if (!t->bfs_valid) return true;
	int64_t gk = key >> 2;
	int g = (int)(gk & 7);
	int64_t ck = gk >> 3;
	int64_t gcx = ck >> 32, gcz = (int64_t)(int32_t)(ck & 0xFFFFFFFFll);
	int64_t lx = gcx - t->bfs_cx0, lz = gcz - t->bfs_cz0;
	const int W = 2 * t->bfs_r + 1;
	if (lx < 0 || lx >= W || lz < 0 || lz >= W || g > 5) return true;
	int a0 = std::max(0, g * 4 + lo), a1 = std::min(23, g * 4 + hi);
	if (a0 > a1) return true;
	const uint8_t *r = t->reach.data() + ((size_t)lz * W + lx) * 24;
	for (int k = a0; k <= a1; k++) if (r[k]) return true;
	return false;
}

// tr_vis(h, cx, cz, g, masks: PackedInt64Array(4) or empty = fully connected) -> [1]
bool fn_tr_vis(const Args &a, void *ret) {
	TR *t = get_tr(a.i(0));
	if (!t) return false;
	int64_t cx = a.i(1), cz = a.i(2);
	int g = (int)a.i(3);
	const void *mv = a.obj(4, GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY);
	int64_t key = (cx << 32) | (cz & 0xFFFFFFFFll);
	auto it = t->vism.find(key);
	if (it == t->vism.end()) {
		std::array<uint64_t, 24> full;
		full.fill(VIS_ALL);
		it = t->vism.emplace(key, full).first;
	}
	int64_t n = mv ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, mv) : 0;
	const int64_t *m = n > 0 ? i64(mv) : nullptr;
	for (int s = 0; s < 4; s++) {
		int sy = g * 4 + s;
		if (sy < 0 || sy >= 24) continue;
		it->second[sy] = (m && s < n) ? (uint64_t)m[s] : VIS_ALL;
	}
	t->vis_dirty = true;
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, 1);
	return true;
}

// tr_vis_clear(h, cx, cz) -> [1]: chunk unloaded (its sections count as fully connected again)
bool fn_tr_vis_clear(const Args &a, void *ret) {
	TR *t = get_tr(a.i(0));
	if (!t) return false;
	int64_t key = (a.i(1) << 32) | (a.i(2) & 0xFFFFFFFFll);
	t->vism.erase(key);
	t->vis_dirty = true;
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, 1);
	return true;
}
// tr_cull_all(h, planes, cam, origin, npages, flags) -> [PackedByteArray cmds, PackedInt32Array meta]
//   One call per frame. planes: 6 x (nx, ny, nz, d), Godot Plane semantics (normal points out of the frustum, a point
//   is inside when n.p - d <= 0), render space. A group is outside when its box is entirely in front of a plane
//   (n.c - d - |n|.e > 0), tested branch-free over the structure-of-arrays bounds. Visible groups are ordered by distance
//   (16-bit key, radix sort; opaque / cutout near-first, translucent far-first) and their face-direction buckets that
//   face away from the camera are dropped (Sodium-style), written as indexed indirect draw commands (5 u32:
//   index_count, instance_count 1, first_index, vertex_offset 0, first_instance 0) over the static quad index buffer,
//   grouped by (material, page): meta[(m * npages + pg) * 2] = first command, [+1] = command count.
//   flags & 2: keep every face direction (debug).
bool fn_tr_cull_all(const Args &a, void *ret) {
	TR *t = get_tr(a.i(0));
	const void *pv = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
	const void *cv = a.obj(2, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
	const void *ov = a.obj(3, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	int npages = (int)a.i(4);
	bool no_dir = (a.i(5) & 2) != 0;
	int64_t min_oy = (a.i(5) & 4) ? 0 : ((a.i(5) & 8) ? 64 : INT64_MIN);   // experiment: hide groups below y 0 / 64
	if (!t || !pv || !cv || !ov || npages < 0 || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, pv) < 24) return false;
	const float *pl = f32(pv);
	const float *cam = f32(cv);
	const int32_t *org = i32(ov);
	t->set_org(org[0], org[1], org[2]);
	const int n = (int)t->g.size();
	// occlusion graph (flags & 64: off): recomputed when the camera enters another section, the radius changes, or
	// (at most every 100 ms) when new section masks arrived
	const bool occl = (a.i(5) & 64) == 0;
	if (occl) {
		int64_t ncam = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, cv);
		int64_t wx = (int64_t)std::floor(cam[0]) + org[0], wy = (int64_t)std::floor(cam[1]) + org[1], wz = (int64_t)std::floor(cam[2]) + org[2];
		int64_t sx = fdiv16(wx), sy = fdiv16(wy), sz = fdiv16(wz);
		int R = ncam >= 4 ? std::max(2, std::min(40, (int)cam[3] + 1)) : 17;
		t->bfs_frames++;
		bool moved = sx != t->bfs_cam[0] || sy != t->bfs_cam[1] || sz != t->bfs_cam[2];
		auto now = std::chrono::steady_clock::now();
		bool stale = t->vis_dirty && std::chrono::duration_cast<std::chrono::milliseconds>(now - t->bfs_at).count() >= 100;
		if (!t->bfs_valid || moved || R != t->bfs_r || stale) {
			t->bfs_at = now;
			occlusion_bfs(t, wx, wy, wz, R);
			t->vis_dirty = false;
			t->bfs_frames = 0;
			t->bfs_cam[0] = sx; t->bfs_cam[1] = sy; t->bfs_cam[2] = sz;
		}
	} else {
		t->bfs_valid = false;
	}
	// frustum: branch-free over SoA (vectorizes)
	static thread_local std::vector<uint8_t> vis;
	vis.resize((size_t)n);
	float P[6][7];
	for (int p = 0; p < 6; p++) {
		P[p][0] = pl[p * 4]; P[p][1] = pl[p * 4 + 1]; P[p][2] = pl[p * 4 + 2]; P[p][3] = pl[p * 4 + 3];
		P[p][4] = std::fabs(P[p][0]); P[p][5] = std::fabs(P[p][1]); P[p][6] = std::fabs(P[p][2]);
	}
	{
		const float *X = t->cx.data(), *Y = t->cy.data(), *Z = t->cz.data(), *EX = t->ex.data(), *EY = t->ey.data(), *EZ = t->ez.data();
		uint8_t *V = vis.data();
		for (int i = 0; i < n; i++) {
			bool out = false;
			for (int p = 0; p < 6; p++) {
				float dist = P[p][0] * X[i] + P[p][1] * Y[i] + P[p][2] * Z[i] - P[p][3] - (P[p][4] * EX[i] + P[p][5] * EY[i] + P[p][6] * EZ[i]);
				out |= dist > 0.0f;
			}
			V[i] = out ? 0 : 1;
		}
	}
	const int nb = 3 * std::max(1, npages);
	static thread_local std::vector<std::vector<uint32_t>> bins;   // (key16 << 16... ) packed: index list per bin
	static thread_local std::vector<std::vector<uint16_t>> bkeys;
	if ((int)bins.size() < nb) { bins.resize((size_t)nb); bkeys.resize((size_t)nb); }
	for (int b = 0; b < nb; b++) { bins[b].clear(); bkeys[b].clear(); }
	for (int i = 0; i < n; i++) {
		if (!vis[i]) continue;
		const Group &q = t->g[i];
		if (q.oy < min_oy) continue;
		if (occl && !group_reachable(t, t->keys[i])) continue;
		if (q.page < 0 || q.page >= npages || q.mat < 0 || q.mat > 2) continue;
		float dx = t->cx[i] - cam[0], dy = t->cy[i] - cam[1], dz = t->cz[i] - cam[2];
		float dist = std::sqrt(dx * dx + dy * dy + dz * dz) * 64.0f;
		uint16_t k = (uint16_t)std::min(65535.0f, dist);
		if (q.mat == 2) {
			// translucent: far first in section steps from the camera section, like Java's reverse BFS section order
			// (|dx| + |dz| chunks + the vertical section gap to the group's own y range), centre distance as tie-break.
			// The plain centre distance of a 64-block group misordered neighbours with different depth ranges (a farther
			// chunk's water drawn over a nearer chunk's ice: see-through strips along chunk borders).
			int64_t ccx = fdiv16((int64_t)std::floor(cam[0]) + t->org[0]), ccz = fdiv16((int64_t)std::floor(cam[2]) + t->org[2]);
			int64_t csy = fdiv16((int64_t)std::floor(cam[1]) + t->org[1]);
			int64_t gsy0 = fdiv16(q.oy + (int64_t)std::floor(q.b[1])), gsy1 = fdiv16(q.oy + (int64_t)std::floor(q.b[4] - 0.001f));
			int64_t dsy = csy < gsy0 ? gsy0 - csy : (csy > gsy1 ? csy - gsy1 : 0);
			int64_t man = std::llabs(fdiv16(q.ox) - ccx) + std::llabs(fdiv16(q.oz) - ccz) + dsy;
			uint32_t fine = (uint32_t)std::min(1023.0f, dist / 64.0f * 2.0f);
			uint32_t key = (uint32_t)std::min<int64_t>(63, man) * 1024u + fine;
			k = (uint16_t)(65535u - key);
		}
		// translucent: one bin over every page (globally far-first; page switches become draw runs below)
		int b = q.mat == 2 ? 2 * npages : q.mat * npages + q.page;
		bins[b].push_back((uint32_t)i);
		bkeys[b].push_back(k);
	}
	std::vector<uint32_t> cmds;
	cmds.reserve((size_t)n * 5);
	std::vector<int32_t> meta((size_t)3 * npages * 2 + 2, 0);   // + quads drawn, visible groups (stats)
	uint64_t qdrawn = 0;
	const bool split = (a.i(5) & 128) != 0;
	// flags & 1024: legacy 32-bit page-wide index buffer (first_index = quad * 6); default: one shared 16-bit pattern of
	// 16384 quads, each command addresses its quads through vertex_offset (base vertex) and is split at 16384 quads
	const bool idx16 = (a.i(5) & 1024) == 0;
	static thread_local std::vector<uint32_t> tmp_i;
	static thread_local std::vector<uint16_t> tmp_k;
	// translucent draw runs (page, first command, command count) in global far-first order: a run ends where the page of
	// the next group differs (each run is one indirect draw with that page's vertex array)
	std::vector<int32_t> runs;
	int run_pg = -1;
	size_t run_first = 0;
	for (int m = 0; m < 3; m++) {
		for (int pg = 0; pg < npages; pg++) {
			int b = m * npages + pg;
			std::vector<uint32_t> &ids = bins[b];
			std::vector<uint16_t> &ks = bkeys[b];
			const size_t cnt_v = ids.size();
			// LSD radix sort on the 16-bit keys (two 8-bit passes, stable)
			tmp_i.resize(cnt_v);
			tmp_k.resize(cnt_v);
			for (int pass = 0; pass < 2; pass++) {
				int sh = pass * 8;
				uint32_t hist[257] = {0};
				for (size_t j = 0; j < cnt_v; j++) hist[((ks[j] >> sh) & 255) + 1]++;
				for (int h = 0; h < 256; h++) hist[h + 1] += hist[h];
				for (size_t j = 0; j < cnt_v; j++) {
					uint32_t d = hist[(ks[j] >> sh) & 255]++;
					tmp_i[d] = ids[j];
					tmp_k[d] = ks[j];
				}
				ids.swap(tmp_i);
				ks.swap(tmp_k);
			}
			size_t first_cmd = cmds.size() / 5;
			for (size_t j = 0; j < cnt_v; j++) {
				int i = (int)ids[j];
				const Group &q = t->g[i];
				if (m == 2 && q.page != run_pg) {
					if (run_pg >= 0 && cmds.size() / 5 > run_first) {
						runs.push_back(run_pg); runs.push_back((int32_t)run_first); runs.push_back((int32_t)(cmds.size() / 5 - run_first));
					}
					run_pg = q.page;
					run_first = cmds.size() / 5;
				}
				bool want[28];
				auto dir_want = [&](bool *w, float mn0, float mx0, float mn1, float mx1, float mn2, float mx2) {
					w[0] = no_dir || cam[0] > mn0 - 0.01f; w[1] = no_dir || cam[0] < mx0 + 0.01f;
					w[2] = no_dir || cam[1] > mn1 - 0.01f; w[3] = no_dir || cam[1] < mx1 + 0.01f;
					w[4] = no_dir || cam[2] > mn2 - 0.01f; w[5] = no_dir || cam[2] < mx2 + 0.01f; w[6] = true;
				};
				if (q.nb == 7) {
					dir_want(want, t->cx[i] - t->ex[i], t->cx[i] + t->ex[i], t->cy[i] - t->ey[i], t->cy[i] + t->ey[i], t->cz[i] - t->ez[i], t->cz[i] + t->ez[i]);
				} else {
					// per 16-block section: frustum and occlusion graph on that section's own bounds; face directions per group
					// (direction-major buckets: a visible direction stays one range unless a section of it is hidden)
					bool wg[7];
					dir_want(wg, t->cx[i] - t->ex[i], t->cx[i] + t->ex[i], t->cy[i] - t->ey[i], t->cy[i] + t->ey[i], t->cz[i] - t->ez[i], t->cz[i] + t->ez[i]);
					const float ox = (float)(q.ox - t->org[0]), oy = (float)(q.oy - t->org[1]), oz = (float)(q.oz - t->org[2]);
					for (int sc = 0; sc < 4; sc++) {
						uint32_t tot = 0;
						for (int dd = 0; dd < 7; dd++) tot += q.cnt[dd * 4 + sc];
						bool vs = tot > 0;
						const float *sb = q.sb[sc];
						if (vs) {
							float c0 = ox + (sb[0] + sb[3]) * 0.5f, c1 = oy + (sb[1] + sb[4]) * 0.5f, c2 = oz + (sb[2] + sb[5]) * 0.5f;
							float e0 = (sb[3] - sb[0]) * 0.5f, e1 = (sb[4] - sb[1]) * 0.5f, e2 = (sb[5] - sb[2]) * 0.5f;
							for (int pp = 0; pp < 6 && vs; pp++)
								if (P[pp][0] * c0 + P[pp][1] * c1 + P[pp][2] * c2 - P[pp][3] - (P[pp][4] * e0 + P[pp][5] * e1 + P[pp][6] * e2) > 0.0f) vs = false;
						}
						if (vs && occl) {
							int lo = (int)std::floor((sb[1] - 0.01f) / 16.0f), hi = (int)std::floor((sb[4] + 0.01f) / 16.0f);
							vs = sections_reachable(t, t->keys[i], lo, hi);
						}
						for (int dd = 0; dd < 7; dd++) want[dd * 4 + sc] = vs && wg[dd];
					}
				}
				const int NB = q.nb;
				int d = 0;
				while (d < NB) {
					if (!want[d] || q.cnt[d] == 0) { d++; continue; }
					uint32_t first = q.quad_off + q.start[d];
					uint32_t cnt = 0;
					while (d < NB && (want[d] || q.cnt[d] == 0)) { cnt += want[d] ? q.cnt[d] : 0; d++; }
					qdrawn += cnt;
					if (idx16) {
						while (cnt > 0) {
							uint32_t nq = cnt < 16384u ? cnt : 16384u;
							cmds.push_back(nq * 6u); cmds.push_back(1u); cmds.push_back(0u); cmds.push_back(first * 4u); cmds.push_back(0u);
							first += nq;
							cnt -= nq;
						}
						continue;
					}
					if (split && cnt > 1) {   // experiment (flags & 128): every command split in two (per-command GPU cost)
						uint32_t h1 = cnt / 2;
						cmds.push_back(h1 * 6u); cmds.push_back(1u); cmds.push_back(first * 6u); cmds.push_back(0u); cmds.push_back(0u);
						cmds.push_back((cnt - h1) * 6u); cmds.push_back(1u); cmds.push_back((first + h1) * 6u); cmds.push_back(0u); cmds.push_back(0u);
						continue;
					}
					cmds.push_back(cnt * 6u); cmds.push_back(1u); cmds.push_back(first * 6u); cmds.push_back(0u); cmds.push_back(0u);
				}
			}
			meta[(size_t)b * 2] = (int32_t)first_cmd;
			meta[(size_t)b * 2 + 1] = (int32_t)(cmds.size() / 5 - first_cmd);
		}
	}
	if (run_pg >= 0 && cmds.size() / 5 > run_first) {
		runs.push_back(run_pg); runs.push_back((int32_t)run_first); runs.push_back((int32_t)(cmds.size() / 5 - run_first));
	}
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr(), (int64_t)cmds.size() * 4);
	if (!cmds.empty()) memcpy(bytes_w(out.ptr()), cmds.data(), cmds.size() * 4);
	meta[meta.size() - 2] = (int32_t)std::min<uint64_t>(qdrawn, INT32_MAX);
	{
		int ng = 0;
		for (int b = 0; b < nb; b++) ng += (int)bins[b].size();
		meta[meta.size() - 1] = ng;
	}
	Owned mo(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, mo.ptr(), (int64_t)meta.size());
	if (!meta.empty()) memcpy(i32_w(mo.ptr()), meta.data(), meta.size() * 4);
	Owned ro(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, ro.ptr(), (int64_t)runs.size());
	if (!runs.empty()) memcpy(i32_w(ro.ptr()), runs.data(), runs.size() * 4);
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 3);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, out.ptr());
	array_set_native(ret, 1, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, mo.ptr());
	array_set_native(ret, 2, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, ro.ptr());
	return true;
}

} // namespace

void register_terrain_render(const char *cls) {
	register_method(cls, "tr_pack", fn_tr_pack, 3);
	register_method(cls, "tr_new", fn_tr_new, 0);
	register_method(cls, "tr_put", fn_tr_put, 10);
	register_method(cls, "tr_del", fn_tr_del, 2);
	register_method(cls, "tr_clear", fn_tr_clear, 1);
	register_method(cls, "tr_page_add", fn_tr_page_add, 2);
	register_method(cls, "tr_alloc", fn_tr_alloc, 4);
	register_method(cls, "tr_free", fn_tr_free, 4);
	register_method(cls, "tr_vis", fn_tr_vis, 5);
	register_method(cls, "tr_vis_clear", fn_tr_vis_clear, 3);
	register_method(cls, "lightmap", fn_lightmap, 1);
	register_method(cls, "tr_cull_all", fn_tr_cull_all, 6);
	register_method(cls, "tr_stamp", fn_tr_stamp, 2);
	register_method(cls, "tr_stamp2", fn_tr_stamp2, 2);
	register_method(cls, "tr_quad_indices", fn_tr_quad_indices, 2);
}
