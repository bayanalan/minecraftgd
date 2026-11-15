// Native port of scripts/world/mesher.gd (Mesher.build): same padding, culling, smooth light/AO, greedy merge,
// model quads and fluids, same vertex/index order and float rounding.
// mesh(snaps: Array[9], light: Array[24], group: int, tints: PackedColorArray(768), flags: PackedInt32Array,
//      cull: PackedByteArray, faces: PackedInt32Array, model_of: PackedInt32Array, models: Array[PackedFloat32Array],
//      tint_const: PackedInt32Array, level: PackedByteArray, water_layer: int, lava_layer: int)
//   -> [] when the group is empty, else [opaque_arrays, cutout_arrays, translucent_arrays, y_base]
//      (each *_arrays is [] or a Mesh.ARRAY_MAX Array with VERTEX, COLOR, TEX_UV, CUSTOM0, INDEX).
#include "native.h"
#include <vector>
#include <cstdlib>
#include <cmath>
#include <algorithm>

using namespace gdx;

// Godot Math::make_half_float (truncating, denormals -> 0): byte-identical to PackedByteArray.encode_half.
static inline uint16_t godot_half(float f) {
	uint32_t x;
	memcpy(&x, &f, 4);
	uint32_t sign = x >> 31;
	uint32_t mantissa = x & ((1u << 23) - 1);
	uint32_t exponent = x & (0xFFu << 23);
	if (exponent >= 0x47800000u) {
		mantissa = (mantissa && exponent == (0xFFu << 23)) ? ((1u << 23) - 1) : 0;
		return (uint16_t)((sign << 15) | (0x1Fu << 10) | (mantissa >> 13));
	}
	if (exponent <= 0x38000000u) return 0;
	return (uint16_t)((sign << 15) | ((exponent - 0x38000000u) >> 13) | (mantissa >> 13));
}

namespace {

const int GROUP = 4, GH = 64, PX = 18, PL = PX * PX, MIN_Y = -64, MAX_Y = 320;
const int F_AIR = 1, F_OPAQUE = 2, F_CUTOUT = 32, F_TRANSLUCENT = 64, F_WATERLOGGED = 256, F_CUBE = 1024, F_MODEL = 2048, F_FLUID = 4096,
	F_TINT_GRASS = 8192, F_TINT_FOLIAGE = 16384, F_TINT_WATER = 32768, F_LAVA = 65536, F_FULL_SHAPE = 262144, F_SELF_CULL = 524288,
	F_TINT_CONST = 2097152, F_LEAVES = 1048576, F_TINT_DRY = 4194304, F_NO_AO = 8388608;
const int OPP[6] = {1, 0, 3, 2, 5, 4};
const double SHADE[6] = {0.5, 1.0, 0.8, 0.8, 0.6, 0.6};
const double AO_CURVE[4] = {0.4, 0.6, 0.8, 1.0};   // Java: 1 - 0.2 per occluding side / corner sample (centre separate)
const int QUAD_FLOATS = 25;

struct V3 { float x, y, z; };
struct V2 { float x, y; };
struct C4 { float r, g, b, a; };

struct Surf {
	std::vector<float> v, uv, col, cu;
	std::vector<int32_t> idx;
	void quad(const V3 *p, const V2 *uvs, const C4 *c, float layer, float overlay, const float *sky, const float *blk, bool flip) {
		int32_t b = (int32_t)(v.size() / 3);
		for (int k = 0; k < 4; k++) {
			v.push_back(p[k].x); v.push_back(p[k].y); v.push_back(p[k].z);
			uv.push_back(uvs[k].x); uv.push_back(uvs[k].y);
			col.push_back(c[k].r); col.push_back(c[k].g); col.push_back(c[k].b); col.push_back(c[k].a);
			cu.push_back(layer); cu.push_back(overlay); cu.push_back(sky[k]); cu.push_back(blk[k]);
		}
		if (flip) { int32_t t[6] = {b + 1, b, b + 3, b + 1, b + 3, b + 2}; idx.insert(idx.end(), t, t + 6); }
		else { int32_t t[6] = {b, b + 3, b + 2, b, b + 2, b + 1}; idx.insert(idx.end(), t, t + 6); }
	}
};

struct Sec { const int32_t *pal = nullptr; int64_t npal = 0; const uint8_t *idx = nullptr; const int32_t *wide = nullptr; int64_t nwide = 0; };

struct Ctx {
	Sec sec[9][24];
	bool present[9] = {};
	const int32_t *flags; int64_t nflags;
	const uint8_t *cull;
	const int32_t *faces;
	const int32_t *model_of;
	const void *models;
	const int32_t *tint_const;
	const uint8_t *level;
	int opts = 0;   // Advanced video: bit 0 = no smart leaf culling, bit 1 = no face merging
	const uint8_t *emit = nullptr;   // st_emit (optional): flat-lit emitters raise their face light to their emission
	int64_t nemit = 0;
	const float *tints;   // 1024 colours * 4: grass, foliage, water, dry foliage (768 accepted: no dry layer)
	int64_t ntints = 0;
	int water_layer, lava_layer;
	int water_flow = 0, lava_flow = 0, water_overlay = 0;
	const int32_t *ctm = nullptr;
	int64_t nctm = 0;
	std::vector<int32_t> pad;
	std::vector<uint8_t> plight;

	inline int32_t sec_state(const Sec &e, int k) const {
		if (e.npal == 1) return e.pal[0];
		if (e.nwide > 0) return e.pal[e.wide[k]];
		return e.pal[e.idx[k]];
	}
	inline int32_t nstate(int x, int y, int z) const {
		int ci = ((z + 16) >> 4) * 3 + ((x + 16) >> 4);
		if (!present[ci]) return 0;
		const Sec &e = sec[ci][(y - MIN_Y) >> 4];
		return sec_state(e, ((y & 15) << 8) | ((z & 15) << 4) | (x & 15));
	}
	inline int32_t fl(int32_t st) const { return flags[st]; }
};

static inline int r8(float v) { float f = v * 255.0f; f = std::round(f); return (int)std::min(255.0f, std::max(0.0f, f)); }

int tint_for(const Ctx &c, int fl, int st, int ci) {
	const float *col;
	if (fl & F_TINT_GRASS) col = c.tints + ci * 4;
	else if (fl & F_TINT_FOLIAGE) col = c.tints + (256 + ci) * 4;
	else if (fl & F_TINT_WATER) col = c.tints + (512 + ci) * 4;
	else if (fl & F_TINT_DRY) col = c.tints + ((c.ntints >= 1024 ? 768 : 256) + ci) * 4;
	else if (fl & F_TINT_CONST) return c.tint_const[st];
	else return 0xFFFFFF;
	return (r8(col[0]) << 16) | (r8(col[1]) << 8) | r8(col[2]);
}

static inline C4 color8(int t) { return C4{((t >> 16) & 255) / 255.0f, ((t >> 8) & 255) / 255.0f, (t & 255) / 255.0f, 1.0f}; }

struct FaceLight { bool uniform; int sky[4]; int blk[4]; int ao[4]; int center; };

// Java ModelBlockRenderer.AmbientOcclusionFace.calculate for a full-block face (see Mesher._face_light): samples in
// the layer in front of the face - sides A / B, the corner (side A's values when both sides block view), the block
// in front. Shade 0.2 per full-collision sample averaged over 4; light: Java blend() (zero samples take the front
// block's light), stored to the nearest level. ao = 3 - occluding sides / corner; centre separate.
// face_light_at: the same for an arbitrary sample layer f (Java AmbientOcclusionFace with blockpos = f), centre light lf
// and centre shade (1 = full-collision block) given by the caller (model quads inside their block sample their own layer).
void face_light_at(const Ctx &c, int f, int d, int lf, int center, FaceLight &out);
void face_light(const Ctx &c, int i, int d, FaceLight &out) {
	int f = i + (d == 1 ? PL : (d == 0 ? -PL : (d == 3 ? PX : (d == 2 ? -PX : (d == 5 ? 1 : -1)))));
	face_light_at(c, f, d, c.plight[f], (c.fl(c.pad[f]) & F_FULL_SHAPE) ? 1 : 0, out);
}
void face_light_at(const Ctx &c, int f, int d, int lf, int center, FaceLight &out) {
	int sa, sb;
	if (d <= 1) { sa = 1; sb = PX; } else if (d <= 3) { sa = 1; sb = PL; } else { sa = PX; sb = PL; }
	const int32_t *pad = c.pad.data();
	const uint8_t *pl = c.plight.data();
	out.center = center;
	bool oa_n = (c.fl(pad[f - sa]) & F_FULL_SHAPE) != 0;
	bool oa_p = (c.fl(pad[f + sa]) & F_FULL_SHAPE) != 0;
	bool ob_n = (c.fl(pad[f - sb]) & F_FULL_SHAPE) != 0;
	bool ob_p = (c.fl(pad[f + sb]) & F_FULL_SHAPE) != 0;
	bool va_n = (c.fl(pad[f - sa]) & F_OPAQUE) != 0;
	bool va_p = (c.fl(pad[f + sa]) & F_OPAQUE) != 0;
	bool vb_n = (c.fl(pad[f - sb]) & F_OPAQUE) != 0;
	bool vb_p = (c.fl(pad[f + sb]) & F_OPAQUE) != 0;
	int la_n = pl[f - sa], la_p = pl[f + sa], lb_n = pl[f - sb], lb_p = pl[f + sb];
	static const int corners[4][2] = {{-1, -1}, {1, -1}, {1, 1}, {-1, 1}};
	out.uniform = true;
	for (int k = 0; k < 4; k++) {
		int ca = corners[k][0], cb = corners[k][1];
		bool s1 = ca < 0 ? oa_n : oa_p;
		bool s2 = cb < 0 ? ob_n : ob_p;
		int l1 = ca < 0 ? la_n : la_p;
		int l2 = cb < 0 ? lb_n : lb_p;
		int cidx = f + ca * sa + cb * sb;
		bool cc;
		int l3;
		if ((ca < 0 ? va_n : va_p) && (cb < 0 ? vb_n : vb_p)) { cc = s1; l3 = l1; }
		else { cc = (c.fl(pad[cidx]) & F_FULL_SHAPE) != 0; l3 = pl[cidx]; }
		int ao = 3 - ((int)s1 + (int)s2 + (int)cc);
		int a1 = l1 == 0 ? lf : l1, a2 = l2 == 0 ? lf : l2, a3 = l3 == 0 ? lf : l3;
		// Java blend(): kept in quarter levels (sum of the 4 samples, 0..60), not rounded to a whole level
		out.sky[k] = (lf >> 4) + (a1 >> 4) + (a2 >> 4) + (a3 >> 4);
		out.blk[k] = (lf & 15) + (a1 & 15) + (a2 & 15) + (a3 & 15);
		out.ao[k] = ao;
		if (k > 0 && (out.sky[k] != out.sky[0] || out.blk[k] != out.blk[0] || out.ao[k] != out.ao[0])) out.uniform = false;
	}
}
void face_corners(int dir, V3 a, V3 b, V3 *o) {
	switch (dir) {
		case 0: o[0] = {a.x, a.y, b.z}; o[1] = {a.x, a.y, a.z}; o[2] = {b.x, a.y, a.z}; o[3] = {b.x, a.y, b.z}; break;
		case 1: o[0] = {a.x, b.y, a.z}; o[1] = {a.x, b.y, b.z}; o[2] = {b.x, b.y, b.z}; o[3] = {b.x, b.y, a.z}; break;
		case 2: o[0] = {b.x, b.y, a.z}; o[1] = {b.x, a.y, a.z}; o[2] = {a.x, a.y, a.z}; o[3] = {a.x, b.y, a.z}; break;
		case 3: o[0] = {a.x, b.y, b.z}; o[1] = {a.x, a.y, b.z}; o[2] = {b.x, a.y, b.z}; o[3] = {b.x, b.y, b.z}; break;
		case 4: o[0] = {a.x, b.y, a.z}; o[1] = {a.x, a.y, a.z}; o[2] = {a.x, a.y, b.z}; o[3] = {a.x, b.y, b.z}; break;
		default: o[0] = {b.x, b.y, b.z}; o[1] = {b.x, a.y, b.z}; o[2] = {b.x, a.y, a.z}; o[3] = {b.x, b.y, a.z}; break;
	}
}

static inline V2 canon_uv(int k, int rf) {
	int i = (k + (rf & 3)) % 4;
	float u = (i == 0 || i == 1) ? 0.0f : 1.0f;
	float v = (i == 0 || i == 3) ? 0.0f : 1.0f;
	if (rf & 4) u = 1.0f - u;
	return V2{u, v};
}

const int CORNER_SIGNS[6][4][2] = {
	{{-1, 1}, {-1, -1}, {1, -1}, {1, 1}},
	{{-1, -1}, {-1, 1}, {1, 1}, {1, -1}},
	{{1, 1}, {1, -1}, {-1, -1}, {-1, 1}},
	{{-1, 1}, {-1, -1}, {1, -1}, {1, 1}},
	{{-1, 1}, {-1, -1}, {1, -1}, {1, 1}},
	{{1, 1}, {1, -1}, {-1, -1}, {-1, 1}}};

static inline int sign_to_k(int sa, int sb) {
	if (sa < 0 && sb < 0) return 0;
	if (sa > 0 && sb < 0) return 1;
	if (sa > 0 && sb > 0) return 2;
	return 3;
}

// res: uniform -> sky[0], blk[0] (low 4 bits), ao[0]
void emit_cube_face(Surf &surf, int x, int y, int z, int d, int w, int h, int fdata, int tint, const FaceLight &res) {
	V3 a{(float)x, (float)y, (float)z};
	V3 b;
	if (d <= 1) b = {(float)(x + w), (float)(y + 1), (float)(z + h)};
	else if (d <= 3) b = {(float)(x + w), (float)(y + h), (float)(z + 1)};
	else b = {(float)(x + 1), (float)(y + h), (float)(z + w)};
	V3 pts[4];
	face_corners(d, a, b, pts);
	int rf = (fdata >> 24) & 7;
	float layer = (float)(fdata & 0xFFF);
	float ovl = (float)(((fdata >> 12) & 0xFFF) - 1);
	bool ua_is_a = (rf & 1) == 0;
	double ext_a = w, ext_b = h;
	V2 uvs[4];
	C4 cols[4];
	float skies[4], blks[4];
	double shade = SHADE[d];
	C4 tc = color8(tint);
	for (int k = 0; k < 4; k++) {
		V2 cuv = canon_uv(k, rf);
		uvs[k] = V2{(float)(cuv.x * (ua_is_a ? ext_a : ext_b)), (float)(cuv.y * (ua_is_a ? ext_b : ext_a))};
		int sk, bl, ao;
		if (res.uniform) { sk = res.sky[0]; bl = res.blk[0]; ao = res.ao[0]; }
		else {
			int kk = sign_to_k(CORNER_SIGNS[d][k][0], CORNER_SIGNS[d][k][1]);
			sk = res.sky[kk]; bl = res.blk[kk]; ao = res.ao[kk];
		}
		C4 cc = tc;
		cc.a = (float)(shade * (AO_CURVE[ao] - 0.2 * res.center));
		cols[k] = cc;
		skies[k] = (float)(sk / 60.0);   // quarter levels
		blks[k] = (float)(bl / 60.0);
	}
	surf.quad(pts, uvs, cols, layer, ovl, skies, blks, false);   // Java: fixed 0-1-2 / 2-3-0 triangulation, no AO flip
}

// Greedy face descriptors: texture / tint / centre / merge mode (u0) and the 4 corner sky, block (quarter levels) and AO
// values (u1). Merge modes: 1 uniform (both axes), 2 constant along the face's a axis (= greedy width: merge in width
// only), 3 constant along b (= greedy height). Merging along an axis the values do not change on keeps every vertex value
// and the linear interpolation between them, so the merged quad shades exactly like the separate faces.
struct FaceDescs {
	std::vector<uint64_t> u0, u1;
	std::vector<int32_t> slot;   // open addressing: descriptor index + 1, 0 = empty
	void reset() { u0.clear(); u1.clear(); slot.assign(4096, 0); }
	int get(uint64_t a, uint64_t b) {
		if ((u0.size() + 1) * 2 > slot.size()) {
			slot.assign(slot.size() * 2, 0);
			for (size_t i = 0; i < u0.size(); i++) put_slot(u0[i], u1[i], (int32_t)i);
		}
		size_t m = slot.size() - 1;
		size_t hsh = (size_t)((a * 0x9E3779B97F4A7C15ull) ^ (b * 0xC2B2AE3D27D4EB4Full) ^ (b >> 29)) & m;
		while (slot[hsh] != 0) {
			int32_t i = slot[hsh] - 1;
			if (u0[i] == a && u1[i] == b) return i;
			hsh = (hsh + 1) & m;
		}
		slot[hsh] = (int32_t)u0.size() + 1;
		u0.push_back(a); u1.push_back(b);
		return (int)u0.size() - 1;
	}
	void put_slot(uint64_t a, uint64_t b, int32_t i) {
		size_t m = slot.size() - 1;
		size_t hsh = (size_t)((a * 0x9E3779B97F4A7C15ull) ^ (b * 0xC2B2AE3D27D4EB4Full) ^ (b >> 29)) & m;
		while (slot[hsh] != 0) hsh = (hsh + 1) & m;
		slot[hsh] = i + 1;
	}
	// debug A/B (env RC_NOMERGE=1): gradient faces (modes 2 / 3) are not merged (mode 4 = single face)
	inline int mode(int i) const {
		static const bool nomerge = std::getenv("RC_NOMERGE") != nullptr;
		int m = (int)((u0[i] >> 53) & 3);
		return (nomerge && m != 1) ? 4 : m;
	}
};

// merge mode of a lit face: 1 uniform, 2 constant along a (corners 0 = 1, 3 = 2), 3 constant along b (0 = 3, 1 = 2), 0 none
static inline int face_mode(const FaceLight &r) {
	auto eq = [&](int i, int j) { return r.sky[i] == r.sky[j] && r.blk[i] == r.blk[j] && r.ao[i] == r.ao[j]; };
	bool ca = eq(0, 1) && eq(3, 2), cb = eq(0, 3) && eq(1, 2);
	return (ca && cb) ? 1 : (ca ? 2 : (cb ? 3 : 0));
}

void emit_key(Surf *surfs, int cl, int x, int y, int z, int d, int w, int h, const FaceDescs &fd, int di) {
	uint64_t a = fd.u0[di], b = fd.u1[di];
	int fdata = (int)(a & 0x0FFFFFFF);
	int tint = (int)((a >> 28) & 0xFFFFFF);
	FaceLight res;
	res.center = (int)((a >> 52) & 1);
	res.uniform = ((a >> 53) & 3) == 1;
	for (int k = 0; k < 4; k++) {
		res.sky[k] = (int)((b >> (k * 6)) & 63);
		res.blk[k] = (int)((b >> (24 + k * 6)) & 63);
		res.ao[k] = (int)((b >> (48 + k * 2)) & 3);
	}
	emit_cube_face(surfs[cl], x, y, z, d, w, h, fdata, tint, res);
}

void greedy(std::vector<int64_t> &mask, const std::vector<uint8_t> &cls, int d, Surf *surfs, const FaceDescs &fd) {
	int cbase = d * 16 * 16 * GH;
	if (d <= 1) {
		for (int ly = 0; ly < GH; ly++) {
			int o = ly * 256;
			for (int z = 0; z < 16; z++) {
				int x = 0;
				while (x < 16) {
					int mi = o + z * 16 + x;
					int64_t key = mask[mi];
					if (key == 0) { x++; continue; }
					int md = fd.mode((int)key - 1);
					int w = 1;
					while (md != 3 && md != 4 && x + w < 16 && mask[mi + w] == key) w++;
					int h = 1;
					bool done = md == 2 || md == 4;
					while (z + h < 16 && !done) {
						for (int k = 0; k < w; k++) if (mask[o + (z + h) * 16 + x + k] != key) { done = true; break; }
						if (!done) h++;
					}
					for (int hh = 0; hh < h; hh++) for (int k = 0; k < w; k++) mask[o + (z + hh) * 16 + x + k] = 0;
					emit_key(surfs, cls[cbase + mi], x, ly, z, d, w, h, fd, (int)key - 1);
					x += w;
				}
			}
		}
	} else if (d <= 3) {
		for (int z = 0; z < 16; z++) {
			for (int ly = 0; ly < GH; ly++) {
				int x2 = 0;
				while (x2 < 16) {
					int mi2 = (ly * 16 + z) * 16 + x2;
					int64_t key2 = mask[mi2];
					if (key2 == 0) { x2++; continue; }
					int md2 = fd.mode((int)key2 - 1);
					int w2 = 1;
					while (md2 != 3 && md2 != 4 && x2 + w2 < 16 && mask[mi2 + w2] == key2) w2++;
					int h2 = 1;
					bool done2 = md2 == 2 || md2 == 4;
					while (ly + h2 < GH && !done2) {
						for (int k = 0; k < w2; k++) if (mask[((ly + h2) * 16 + z) * 16 + x2 + k] != key2) { done2 = true; break; }
						if (!done2) h2++;
					}
					for (int hh = 0; hh < h2; hh++) for (int k = 0; k < w2; k++) mask[((ly + hh) * 16 + z) * 16 + x2 + k] = 0;
					emit_key(surfs, cls[cbase + mi2], x2, ly, z, d, w2, h2, fd, (int)key2 - 1);
					x2 += w2;
				}
			}
		}
	} else {
		for (int x = 0; x < 16; x++) {
			for (int ly = 0; ly < GH; ly++) {
				int z2 = 0;
				while (z2 < 16) {
					int mi3 = (ly * 16 + z2) * 16 + x;
					int64_t key3 = mask[mi3];
					if (key3 == 0) { z2++; continue; }
					int md3 = fd.mode((int)key3 - 1);
					int w3 = 1;
					while (md3 != 3 && md3 != 4 && z2 + w3 < 16 && mask[mi3 + w3 * 16] == key3) w3++;
					int h3 = 1;
					bool done3 = md3 == 2 || md3 == 4;
					while (ly + h3 < GH && !done3) {
						for (int k = 0; k < w3; k++) if (mask[((ly + h3) * 16 + z2 + k) * 16 + x] != key3) { done3 = true; break; }
						if (!done3) h3++;
					}
					for (int hh = 0; hh < h3; hh++) for (int k = 0; k < w3; k++) mask[((ly + hh) * 16 + z2 + k) * 16 + x] = 0;
					emit_key(surfs, cls[cbase + mi3], x, ly, z2, d, w3, h3, fd, (int)key3 - 1);
					z2 += w3;
				}
			}
		}
	}
}

void emit_model(Surf &surf, const Ctx &c, int i, int x, int y, int z, int st, int fl, int ci) {
	int mid = c.model_of[st];
	const void *mv = array_get(c.models, mid);
	if (variant_get_type(mv) != GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY) return;
	const void *qa = internal(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY)((GDExtensionVariantPtr)mv);
	int64_t qn = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, qa);
	const float *q = f32(qa);
	int n = (int)(qn / QUAD_FLOATS);
	static const int steps[6] = {-PL, PL, -PX, PX, -1, 1};
	int tint_c = tint_for(c, fl, st, ci);
	C4 tcol = color8(tint_c);
	int own = c.plight[i];
	const bool no_ao = (fl & F_NO_AO) != 0;
	const bool full = (fl & F_FULL_SHAPE) != 0;
	const int em = (c.emit && st < c.nemit) ? c.emit[st] : 0;
	for (int qi = 0; qi < n; qi++) {
		int o = qi * QUAD_FLOATS;
		int cf = (int)q[o + 22];
		if (cf >= 0) {
			int nb = c.pad[i + steps[cf]];
			if ((c.cull[nb] >> OPP[cf]) & 1) continue;
			if (nb == st && (fl & F_SELF_CULL)) continue;
		}
		int dirn = (int)q[o + 23];
		// shade field: 0 none, 1 by face direction, 2 + d by direction d (26.x shade_direction_override: plants = up)
		double shade = q[o + 24] > 1.5 ? SHADE[std::min(5, std::max(0, (int)q[o + 24] - 2))] : (q[o + 24] > 0.5 ? SHADE[dirn] : 1.0);
		C4 cc = q[o + 21] >= 0.0f ? tcol : C4{1, 1, 1, 1};
		V3 pts[4];
		V2 uvs[4];
		float mn[3] = {32.0f, 32.0f, 32.0f}, mx[3] = {-32.0f, -32.0f, -32.0f};
		for (int k = 0; k < 4; k++) {
			pts[k] = V3{(float)(x + (double)q[o + k * 5]), (float)(y + (double)q[o + k * 5 + 1]), (float)(z + (double)q[o + k * 5 + 2])};
			uvs[k] = V2{q[o + k * 5 + 3], q[o + k * 5 + 4]};
			for (int a2 = 0; a2 < 3; a2++) { mn[a2] = std::min(mn[a2], q[o + k * 5 + a2]); mx[a2] = std::max(mx[a2], q[o + k * 5 + a2]); }
		}
		// Java calculateShape flag 0: the quad lies on the block boundary in its direction (or the block is a full cube)
		bool on_face;
		switch (dirn) {
			case 0: on_face = mn[1] == mx[1] && (mn[1] < 1.0e-4f || full); break;
			case 1: on_face = mn[1] == mx[1] && (mx[1] > 0.9999f || full); break;
			case 2: on_face = mn[2] == mx[2] && (mn[2] < 1.0e-4f || full); break;
			case 3: on_face = mn[2] == mx[2] && (mx[2] > 0.9999f || full); break;
			case 4: on_face = mn[0] == mx[0] && (mn[0] < 1.0e-4f || full); break;
			default: on_face = mn[0] == mx[0] && (mx[0] > 0.9999f || full); break;
		}
		C4 cs[4];
		float sks[4], bls[4];
		if (no_ao) {
			// Java tesselateWithoutAO / renderModelFaceFlat: cull-face quads take the neighbour's light, the others the
			// neighbour's when on the boundary, else their own; emitters raise block light to their emission
			int lt = cf >= 0 ? c.plight[i + steps[cf]] : (on_face ? c.plight[i + steps[dirn]] : own);
			float sk = (float)((lt >> 4) / 15.0), bl = (float)(std::max(lt & 15, em) / 15.0);
			cc.a = (float)shade;
			for (int k = 0; k < 4; k++) { cs[k] = cc; sks[k] = sk; bls[k] = bl; }
		} else {
			// Java AmbientOcclusionFace for model quads: samples in the neighbour layer for boundary quads, in the block's
			// own layer otherwise (centre light: the neighbour's unless it is solid-render, centre shade of that block);
			// each vertex interpolates the 4 corner values at its position on the face (Java's non-cubic weights)
			int fi = i + steps[dirn];
			int base = on_face ? fi : i;
			int lf = (on_face || !(c.fl(c.pad[fi]) & F_OPAQUE)) ? c.plight[fi] : own;
			int ctr = on_face ? ((c.fl(c.pad[fi]) & F_FULL_SHAPE) ? 1 : 0) : (full ? 1 : 0);
			FaceLight fl2;
			face_light_at(c, base, dirn, lf, ctr, fl2);
			double br[4];
			for (int k = 0; k < 4; k++) br[k] = AO_CURVE[fl2.ao[k]] - 0.2 * fl2.center;
			int ia = dirn <= 3 ? 0 : 2, ib = dirn <= 1 ? 2 : 1;   // face axes (a, b) as in face_light: Y faces x/z, Z faces x/y, X faces z/y
			for (int k = 0; k < 4; k++) {
				double pa = std::min(1.0, std::max(0.0, (double)q[o + k * 5 + ia]));
				double pb = std::min(1.0, std::max(0.0, (double)q[o + k * 5 + ib]));
				double w0 = (1.0 - pa) * (1.0 - pb), w1 = pa * (1.0 - pb), w2 = pa * pb, w3 = (1.0 - pa) * pb;
				double b = w0 * br[0] + w1 * br[1] + w2 * br[2] + w3 * br[3];
				double sv = w0 * fl2.sky[0] + w1 * fl2.sky[1] + w2 * fl2.sky[2] + w3 * fl2.sky[3];
				double bv = w0 * fl2.blk[0] + w1 * fl2.blk[1] + w2 * fl2.blk[2] + w3 * fl2.blk[3];
				cs[k] = cc;
				cs[k].a = (float)(shade * b);
				sks[k] = (float)(sv / 60.0);
				bls[k] = (float)(bv / 60.0);
			}
		}
		surf.quad(pts, uvs, cs, q[o + 20], -1.0f, sks, bls, false);
	}
}

// Java LiquidBlockRenderer (port of Mesher._emit_fluid: same operations and order)
const int F_COLLIDE_ = 4, F_SOLID_ = 16777216;
inline bool same_fluid(int fl, bool lava) { return (fl & (F_FLUID | F_WATERLOGGED)) && (((fl & F_LAVA) != 0) == lava); }
double own_h(const Ctx &c, int st) {
	if (!(c.fl(st) & F_FLUID)) return 8.0 / 9.0;
	int lv = c.level[st];
	return (lv == 0 || lv >= 8) ? 8.0 / 9.0 : (8.0 - lv) / 9.0;
}
double cell_h(const Ctx &c, int j, bool lava) {
	int st = c.pad[j];
	int fl = c.fl(st);
	if (same_fluid(fl, lava)) return same_fluid(c.fl(c.pad[j + PL]), lava) ? 1.0 : own_h(c, st);
	return (fl & F_SOLID_) ? -1.0 : 0.0;
}
inline void add_w(double v, double &s, double &w) {
	if (v >= 0.8) { s += v * 10.0; w += 10.0; }
	else if (v >= 0.0) { s += v; w += 1.0; }
}
double avg_h(const Ctx &c, double cur, double h1, double h2, int diag, bool lava) {
	if (h2 >= 1.0 || h1 >= 1.0) return 1.0;
	double s = 0.0, w = 0.0;
	if (h2 > 0.0 || h1 > 0.0) {
		double f = cell_h(c, diag, lava);
		if (f >= 1.0) return 1.0;
		add_w(f, s, w);
	}
	add_w(cur, s, w);
	add_w(h2, s, w);
	add_w(h1, s, w);
	return s / w;
}
void flow_vec(const Ctx &c, int i, int st, bool lava, double &d0, double &d1) {
	double own = own_h(c, st);
	d0 = 0.0; d1 = 0.0;
	static const int stp[4] = {-PX, 1, PX, -1}, sx[4] = {0, 1, 0, -1}, sz[4] = {-1, 0, 1, 0};
	for (int k = 0; k < 4; k++) {
		int nb = c.pad[i + stp[k]];
		int nf = c.fl(nb);
		bool nfl = (nf & (F_FLUID | F_WATERLOGGED)) != 0;
		if (nfl && !same_fluid(nf, lava)) continue;
		double f = nfl ? own_h(c, nb) : 0.0;
		double f1 = 0.0;
		if (f == 0.0) {
			if (!(nf & F_COLLIDE_)) {
				int b2 = c.pad[i + stp[k] - PL];
				int bf = c.fl(b2);
				bool bfl = (bf & (F_FLUID | F_WATERLOGGED)) != 0;
				if (!bfl || same_fluid(bf, lava)) {
					f = bfl ? own_h(c, b2) : 0.0;
					if (f > 0.0) f1 = own - (f - 0.8888889);
				}
			}
		} else if (f > 0.0) {
			f1 = own - f;
		}
		if (f1 != 0.0) { d0 += sx[k] * f1; d1 += sz[k] * f1; }
	}
}
inline int max_light(int a, int b) { return std::max(a & 0xF0, b & 0xF0) | std::max(a & 15, b & 15); }

void emit_fluid(Surf &surf, const Ctx &c, int i, int x, int y, int z, int st, int fl, int ci) {
	bool lava = (fl & F_LAVA) != 0;
	float still = (float)(lava ? c.lava_layer : c.water_layer);
	float flowl = (float)(lava ? c.lava_flow : c.water_flow);
	C4 col = lava ? C4{1, 1, 1, 1} : C4{c.tints[(512 + ci) * 4], c.tints[(512 + ci) * 4 + 1], c.tints[(512 + ci) * 4 + 2], c.tints[(512 + ci) * 4 + 3]};
	bool up_same = same_fluid(c.fl(c.pad[i + PL]), lava);
	int dn = c.pad[i - PL];
	// Java shouldRenderFace: not where the cell's own block (a waterlogged slab / stairs) covers that face
	bool draw_down = !same_fluid(c.fl(dn), lava) && !((c.cull[dn] >> 1) & 1) && !(c.cull[st] & 1);
	double h = cell_h(c, i, lava);
	double cnw = 1.0, cne = 1.0, csw = 1.0, cse = 1.0;
	if (h < 1.0) {
		double hn = cell_h(c, i - PX, lava), hs = cell_h(c, i + PX, lava), he = cell_h(c, i + 1, lava), hw = cell_h(c, i - 1, lava);
		cne = avg_h(c, h, hn, he, i - PX + 1, lava);
		cnw = avg_h(c, h, hn, hw, i - PX - 1, lava);
		cse = avg_h(c, h, hs, he, i + PX + 1, lava);
		csw = avg_h(c, h, hs, hw, i + PX - 1, lava);
	}
	int lt = max_light(c.plight[i], c.plight[i + PL]);
	float sk = (float)((lt >> 4) / 15.0), bl = (float)((lt & 15) / 15.0);
	float sks[4] = {sk, sk, sk, sk}, bls[4] = {bl, bl, bl, bl};
	double x0 = x, z0 = z, y0 = y;
	double bottom = draw_down ? 0.001 : 0.0;
	if (!up_same && !(std::min(std::min(cnw, csw), std::min(cse, cne)) >= 1.0 && (c.cull[c.pad[i + PL]] & 1))) {
		cnw -= 0.001; csw -= 0.001; cse -= 0.001; cne -= 0.001;
		double fx, fz;
		flow_vec(c, i, st, lava, fx, fz);
		V2 uvc[4];
		float layer = still;
		if (fx == 0.0 && fz == 0.0) {
			uvc[0] = {0, 0}; uvc[1] = {0, 1}; uvc[2] = {1, 1}; uvc[3] = {1, 0};
		} else {
			layer = flowl;
			double ang = std::atan2(fz, fx) - 3.141592653589793 / 2.0;
			double s = std::sin(ang) * 0.25, co = std::cos(ang) * 0.25;
			uvc[0] = {(float)(0.5 + (-co - s)), (float)(0.5 + (-co + s))};
			uvc[1] = {(float)(0.5 + (-co + s)), (float)(0.5 + (co + s))};
			uvc[2] = {(float)(0.5 + (co + s)), (float)(0.5 + (co - s))};
			uvc[3] = {(float)(0.5 + (co - s)), (float)(0.5 + (-co - s))};
		}
		V3 pts[4] = {{(float)x0, (float)(y0 + cnw), (float)z0}, {(float)x0, (float)(y0 + csw), (float)(z0 + 1.0)},
			{(float)(x0 + 1.0), (float)(y0 + cse), (float)(z0 + 1.0)}, {(float)(x0 + 1.0), (float)(y0 + cne), (float)z0}};
		C4 cc = col;
		cc.a = (float)SHADE[1];
		C4 cs[4] = {cc, cc, cc, cc};
		surf.quad(pts, uvc, cs, layer, -1.0f, sks, bls, false);
		// FluidState.shouldRenderBackwardUpFace: the underside only when one of the 9 cells above holds neither water
		// nor a solid-render block (open water). Under a submerged block the surface (8/9 high) is not seen from below:
		// drawn always, it showed a thin layer of "air" under every block in water.
		bool back = false;
		if (!lava)
			for (int oz = -1; oz <= 1 && !back; oz++)
				for (int ox = -1; ox <= 1 && !back; ox++) {
					int f2 = c.fl(c.pad[i + PL + oz * PX + ox]);
					if (!same_fluid(f2, false) && !(f2 & F_OPAQUE)) back = true;
				}
		if (back) {
			V3 rp[4] = {pts[3], pts[2], pts[1], pts[0]};
			V2 ru[4] = {uvc[3], uvc[2], uvc[1], uvc[0]};
			surf.quad(rp, ru, cs, layer, -1.0f, sks, bls, false);
		}
	}
	if (draw_down) {
		int lt2 = max_light(c.plight[i - PL], c.plight[i]);
		float sk2 = (float)((lt2 >> 4) / 15.0), bl2 = (float)((lt2 & 15) / 15.0);
		C4 cd = col;
		cd.a = (float)SHADE[0];
		float yb = (float)(y0 + bottom);
		V3 bp[4] = {{(float)x0, yb, (float)(z0 + 1.0)}, {(float)x0, yb, (float)z0}, {(float)(x0 + 1.0), yb, (float)z0}, {(float)(x0 + 1.0), yb, (float)(z0 + 1.0)}};
		V2 bu[4] = {{0, 1}, {0, 0}, {1, 0}, {1, 1}};
		C4 bc[4] = {cd, cd, cd, cd};
		float sk2a[4] = {sk2, sk2, sk2, sk2}, bl2a[4] = {bl2, bl2, bl2, bl2};
		surf.quad(bp, bu, bc, still, -1.0f, sk2a, bl2a, false);
	}
	static const int sd[4] = {2, 3, 4, 5};
	static const int sstep[4] = {-PX, PX, -1, 1};
	for (int k = 0; k < 4; k++) {
		int d = sd[k];
		int nb = c.pad[i + sstep[k]];
		int nf = c.fl(nb);
		if (same_fluid(nf, lava)) continue;
		if ((c.cull[nb] >> OPP[d]) & 1) continue;
		if ((c.cull[st] >> d) & 1) continue;
		double h1, h2, p1x, p1z, p2x, p2z;
		switch (k) {
			case 0: h1 = cnw; h2 = cne; p1x = x0; p1z = z0 + 0.001; p2x = x0 + 1.0; p2z = z0 + 0.001; break;
			case 1: h1 = cse; h2 = csw; p1x = x0 + 1.0; p1z = z0 + 1.0 - 0.001; p2x = x0; p2z = z0 + 1.0 - 0.001; break;
			case 2: h1 = csw; h2 = cnw; p1x = x0 + 0.001; p1z = z0 + 1.0; p2x = x0 + 0.001; p2z = z0; break;
			default: h1 = cne; h2 = cse; p1x = x0 + 1.0 - 0.001; p1z = z0; p2x = x0 + 1.0 - 0.001; p2z = z0 + 1.0; break;
		}
		bool overlay = !lava && (nf & F_SELF_CULL) && !(nf & (F_FLUID | F_WATERLOGGED));
		float sl = overlay ? (float)c.water_overlay : flowl;
		C4 sc = col;
		sc.a = (float)SHADE[d];
		V3 sv[4] = {{(float)p1x, (float)(y0 + h1), (float)p1z}, {(float)p2x, (float)(y0 + h2), (float)p2z},
			{(float)p2x, (float)(y0 + bottom), (float)p2z}, {(float)p1x, (float)(y0 + bottom), (float)p1z}};
		V2 su[4] = {{0.0f, (float)((1.0 - h1) * 0.5)}, {0.5f, (float)((1.0 - h2) * 0.5)}, {0.5f, 0.5f}, {0.0f, 0.5f}};
		C4 scs[4] = {sc, sc, sc, sc};
		surf.quad(sv, su, scs, sl, -1.0f, sks, bls, false);
		if (!overlay) {
			V3 rv[4] = {sv[3], sv[2], sv[1], sv[0]};
			V2 ru2[4] = {su[3], su[2], su[1], su[0]};
			surf.quad(rv, ru2, scs, sl, -1.0f, sks, bls, false);
		}
	}
}
// Java VisGraph for the 4 sections of the group (occlusion culling): flood fill through blocks that are not
// solid-render (F_OPAQUE); every pair of section faces touched by one connected region can see each other.
// Fewer than 256 opaque blocks -> all faces connected; all opaque -> none (Java VisGraph.resolve shortcuts).
// Mask bit a * 6 + b (symmetric); faces 0 down, 1 up, 2 north (-z), 3 south (+z), 4 west (-x), 5 east (+x).
static uint64_t section_vis(const Ctx &c, int s) {
	static thread_local std::vector<uint8_t> open;
	static thread_local std::vector<int> stack;
	open.assign(4096, 0);
	int nopen = 0;
	for (int y = 0; y < 16; y++)
		for (int z = 0; z < 16; z++)
			for (int x = 0; x < 16; x++) {
				int st = c.pad[(s * 16 + y + 1) * PL + (z + 1) * PX + (x + 1)];
				if (!(c.fl(st) & F_OPAQUE)) { open[(y << 8) | (z << 4) | x] = 1; nopen++; }
			}
	const uint64_t ALL = (1ull << 36) - 1;
	if (4096 - nopen < 256) return ALL;
	if (nopen == 0) return 0;
	uint64_t mask = 0;
	for (int i0 = 0; i0 < 4096; i0++) {
		if (open[i0] != 1) continue;
		int faces = 0;
		stack.clear();
		stack.push_back(i0);
		open[i0] = 2;
		while (!stack.empty()) {
			int i = stack.back();
			stack.pop_back();
			int x = i & 15, z = (i >> 4) & 15, y = i >> 8;
			if (y == 0) faces |= 1; if (y == 15) faces |= 2;
			if (z == 0) faces |= 4; if (z == 15) faces |= 8;
			if (x == 0) faces |= 16; if (x == 15) faces |= 32;
			if (x > 0 && open[i - 1] == 1) { open[i - 1] = 2; stack.push_back(i - 1); }
			if (x < 15 && open[i + 1] == 1) { open[i + 1] = 2; stack.push_back(i + 1); }
			if (z > 0 && open[i - 16] == 1) { open[i - 16] = 2; stack.push_back(i - 16); }
			if (z < 15 && open[i + 16] == 1) { open[i + 16] = 2; stack.push_back(i + 16); }
			if (y > 0 && open[i - 256] == 1) { open[i - 256] = 2; stack.push_back(i - 256); }
			if (y < 15 && open[i + 256] == 1) { open[i + 256] = 2; stack.push_back(i + 256); }
		}
		for (int a = 0; a < 6; a++)
			if (faces & (1 << a))
				for (int b = 0; b < 6; b++)
					if (faces & (1 << b)) mask |= 1ull << (a * 6 + b);
		if (mask == ALL) break;
	}
	return mask;
}
void put_surface(void *arr, int64_t slot, Surf &s) {
	Owned out(GDEXTENSION_VARIANT_TYPE_ARRAY);
	if (!s.v.empty()) {
		resize(GDEXTENSION_VARIANT_TYPE_ARRAY, out.ptr(), 13);
		int64_t nv = (int64_t)(s.v.size() / 3);
		Owned v3(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY);
		resize(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, v3.ptr(), nv);
		memcpy(vec3_w(v3.ptr()), s.v.data(), s.v.size() * sizeof(float));
		Owned uv(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY);
		resize(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, uv.ptr(), nv);
		memcpy(vec2_w(uv.ptr()), s.uv.data(), s.uv.size() * sizeof(float));
		Owned col(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
		resize(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, col.ptr(), nv);
		memcpy(color_w(col.ptr()), s.col.data(), s.col.size() * sizeof(float));
		// CUSTOM0 as RGBA half floats (PackedByteArray, Mesh ARRAY_CUSTOM_RGBA_HALF): Godot's make_half_float rounding
		Owned cu(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
		resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, cu.ptr(), (int64_t)s.cu.size() * 2);
		if (!s.cu.empty()) {
			uint8_t *hb = bytes_w(cu.ptr());
			for (size_t q = 0; q < s.cu.size(); q++) {
				uint16_t h = godot_half(s.cu[q]);
				hb[q * 2] = (uint8_t)(h & 0xFF);
				hb[q * 2 + 1] = (uint8_t)(h >> 8);
			}
		}
		Owned ix(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
		resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, ix.ptr(), (int64_t)s.idx.size());
		memcpy(i32_w(ix.ptr()), s.idx.data(), s.idx.size() * sizeof(int32_t));
		array_set_native(out.ptr(), 0, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, v3.ptr());
		array_set_native(out.ptr(), 3, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, col.ptr());
		array_set_native(out.ptr(), 4, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, uv.ptr());
		array_set_native(out.ptr(), 6, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, cu.ptr());
		array_set_native(out.ptr(), 12, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, ix.ptr());
	}
	array_set_native(arr, slot, GDEXTENSION_VARIANT_TYPE_ARRAY, out.ptr());
}

bool fn_mesh(const Args &a, void *ret) {
	const void *snaps = a.obj(0, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *light = a.obj(1, GDEXTENSION_VARIANT_TYPE_ARRAY);
	int g = (int)a.i(2);
	const void *tints = a.obj(3, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY);
	const void *flags = a.obj(4, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *cull = a.obj(5, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	const void *faces = a.obj(6, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *model_of = a.obj(7, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *models = a.obj(8, GDEXTENSION_VARIANT_TYPE_ARRAY);
	const void *tint_const = a.obj(9, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	const void *level = a.obj(10, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	if (!snaps || !light || !tints || !flags || !cull || !faces || !model_of || !models || !tint_const || !level) return false;
	Ctx *cp = new Ctx();
	Ctx &c = *cp;
	c.flags = i32(flags);
	c.nflags = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, flags);
	c.cull = bytes(cull);
	c.faces = i32(faces);
	c.model_of = i32(model_of);
	c.models = models;
	c.tint_const = i32(tint_const);
	c.level = bytes(level);
	// PackedColorArray data pointer: read through a const index of element 0
	c.tints = color(tints);
	if (!c.tints || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, tints) < 768) { delete cp; return false; }
	c.ntints = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, tints);
	c.water_layer = (int)a.i(11);
	c.lava_layer = (int)a.i(12);
	if (const void *ev = a.obj(13, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)) { c.emit = bytes(ev); c.nemit = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, ev); }
	if (a.count > 14) c.opts = (int)a.i(14);
	c.water_flow = a.count > 15 ? (int)a.i(15) : c.water_layer;
	c.lava_flow = a.count > 16 ? (int)a.i(16) : c.lava_layer;
	c.water_overlay = a.count > 17 ? (int)a.i(17) : c.water_layer;
	if (a.count > 18) {
		if (const void *cv = a.obj(18, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)) {
			c.nctm = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, cv);
			c.ctm = c.nctm ? i32(cv) : nullptr;
		}
	}
	for (int ci = 0; ci < 9; ci++) {
		const void *sv = array_get(snaps, ci);
		if (variant_get_type(sv) != GDEXTENSION_VARIANT_TYPE_ARRAY) continue;
		const void *sarr = internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)sv);
		c.present[ci] = true;
		for (int s = 0; s < 24; s++) {
			const void *earr = internal(GDEXTENSION_VARIANT_TYPE_ARRAY)((GDExtensionVariantPtr)array_get(sarr, s));
			const void *pal = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)array_get(earr, 0));
			const void *idx = internal(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)((GDExtensionVariantPtr)array_get(earr, 1));
			const void *wide = internal(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY)((GDExtensionVariantPtr)array_get(earr, 2));
			Sec &e = c.sec[ci][s];
			e.npal = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, pal);
			e.pal = i32(pal);
			e.idx = bytes(idx);
			e.nwide = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, wide);
			e.wide = i32(wide);
		}
	}
	// empty group?
	bool any = false;
	if (c.present[4]) {
		for (int s2 = g * GROUP; s2 < g * GROUP + GROUP; s2++) {
			const Sec &e2 = c.sec[4][s2];
			if (!(e2.npal == 1 && e2.pal[0] == 0)) { any = true; break; }
		}
	}
	if (!any) { delete cp; return true; }  // empty Array
	int y_base = MIN_Y + g * GH;
	int H = GH + 2;
	c.pad.assign(PL * H, 0);
	c.plight.assign(PL * H, 0);
	// light sections
	for (int ly = 0; ly < H; ly++) {
		int y = y_base + ly - 1;
		int o = ly * PL;
		if (y < MIN_Y || y >= MAX_Y) {
			uint8_t v = y >= MAX_Y ? 0xF0 : 0;
			for (int k = 0; k < PL; k++) c.plight[o + k] = v;
			continue;
		}
		int s = (y - MIN_Y) >> 4;
		const void *lv = array_get(light, s);
		if (variant_get_type(lv) == GDEXTENSION_VARIANT_TYPE_INT) {
			int64_t u = 0;
			to_type(GDEXTENSION_VARIANT_TYPE_INT)(&u, (GDExtensionVariantPtr)lv);
			for (int k = 0; k < PL; k++) c.plight[o + k] = (uint8_t)u;
		} else {
			const uint8_t *lsb = bytes(internal(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY)((GDExtensionVariantPtr)lv));
			int lo = (y & 15) * PL;
			for (int k = 0; k < PL; k++) c.plight[o + k] = lsb[lo + k];
		}
		const Sec &e = c.sec[4][s];
		int base_k = (y & 15) << 8;
		if (e.npal == 1) {
			int32_t vv = e.pal[0];
			if (vv != 0)
				for (int z = 0; z < 16; z++) { int ro = o + (z + 1) * PX + 1; for (int x = 0; x < 16; x++) c.pad[ro + x] = vv; }
		} else {
			for (int z = 0; z < 16; z++) {
				int ro2 = o + (z + 1) * PX + 1;
				int ko = base_k | (z << 4);
				for (int x = 0; x < 16; x++) c.pad[ro2 + x] = e.nwide > 0 ? e.pal[e.wide[ko | x]] : e.pal[e.idx[ko | x]];
			}
		}
		for (int z = -1; z < 17; z++) {
			c.pad[o + (z + 1) * PX + 0] = c.nstate(-1, y, z);
			c.pad[o + (z + 1) * PX + 17] = c.nstate(16, y, z);
		}
		for (int x = 0; x < 16; x++) {
			c.pad[o + x + 1] = c.nstate(x, y, -1);
			c.pad[o + 17 * PX + x + 1] = c.nstate(x, y, 16);
		}
	}
	Surf surfs[3];
	static const int dir_step[6] = {-PL, PL, -PX, PX, -1, 1};
	std::vector<int64_t> masks[6];
	for (int d = 0; d < 6; d++) masks[d].assign(16 * 16 * GH, 0);
	static thread_local std::vector<uint8_t> tl_mask;
	TLBuf<uint8_t> mask_buf(tl_mask, 6 * 16 * 16 * GH, 0);
	std::vector<uint8_t> &mask_cls = mask_buf.v;
	static thread_local FaceDescs fdesc;
	fdesc.reset();
	FaceLight res;
	for (int ly = 1; ly <= GH; ly++) {
		for (int z = 0; z < 16; z++) {
			int row = ly * PL + (z + 1) * PX + 1;
			for (int x = 0; x < 16; x++) {
				int i = row + x;
				int st = c.pad[i];
				if (st == 0) continue;
				int fl = c.fl(st);
				if (fl & F_AIR) continue;
				int ci = z * 16 + x;
				if (fl & F_CUBE) {
					int surf_cls = (fl & (F_CUTOUT | F_TRANSLUCENT)) == 0 ? 0 : ((fl & F_CUTOUT) ? 1 : 2);
					for (int d = 0; d < 6; d++) {
						int n = c.pad[i + dir_step[d]];
						if ((c.cull[n] >> OPP[d]) & 1) continue;
						if ((fl & F_LEAVES) && !(c.opts & 1)) {
							// Cutout leaves: Java draws every face between leaves. A leaf face is skipped only when the
							// neighbour is a leaf AND the block behind it is a leaf or an occluding face: seeing it would
							// need a line of sight through two leaf textures' holes (the outer two layers of a canopy
							// stay exactly vanilla). Out of the padded range (section / chunk borders) the face is kept.
							if (c.fl(n) & F_LEAVES) {
								int ax = x + 1 + (d == 4 ? -2 : (d == 5 ? 2 : 0));
								int az = z + 1 + (d == 2 ? -2 : (d == 3 ? 2 : 0));
								int ay = ly + (d == 0 ? -2 : (d == 1 ? 2 : 0));
								if (ax >= 0 && ax < PX && az >= 0 && az < PX && ay >= 0 && ay <= GH + 1) {
									int n2 = c.pad[ay * PL + az * PX + ax];
									if ((c.fl(n2) & F_LEAVES) || ((c.cull[n2] >> OPP[d]) & 1)) continue;
								}
							}
						} else if (n == st && (fl & F_SELF_CULL)) continue;
						int fdata = c.faces[st * 6 + d];
						if ((c.opts & 4) && c.ctm && st < c.nctm && c.ctm[st] >= 0) {
							// connected textures (Mesher._build: CTM_DU / CTM_DV)
							static const int CDU[6] = {1, 1, -1, 1, PX, -PX};
							static const int CDV[6] = {-PX, PX, -PL, -PL, -PL, -PL};
							int cu = CDU[d], cv2 = CDV[d];
							int cm = (c.pad[i - cv2] == st ? 1 : 0) | (c.pad[i + cu] == st ? 2 : 0) | (c.pad[i + cv2] == st ? 4 : 0) | (c.pad[i - cu] == st ? 8 : 0);
							fdata = (fdata & ~0xFFF) | (c.ctm[st] + cm);
						}
						int tint = ((fdata >> 28) & 1) ? tint_for(c, fl, st, ci) : 0xFFFFFF;
						if (fl & F_NO_AO) {
							// Java tesselateWithoutAO: the neighbour's light (an emitter raises block light to its own
							// emission, LevelRenderer.getLightColor), face shade only
							int lt = c.plight[i + (d == 1 ? PL : (d == 0 ? -PL : (d == 3 ? PX : (d == 2 ? -PX : (d == 5 ? 1 : -1)))))];
							int em = (c.emit && st < c.nemit) ? c.emit[st] : 0;
							res.uniform = true; res.center = 0;
							for (int k = 0; k < 4; k++) { res.sky[k] = (lt >> 4) * 4; res.blk[k] = std::max(lt & 15, em) * 4; res.ao[k] = 3; }
						} else {
							face_light(c, i, d, res);
						}
						// translucent cubes never merged (T-junction cracks show through translucent layers; see mesher.gd)
						static const bool tr_merge = std::getenv("RC_TRMERGE") != nullptr;   // A/B: old merged translucent faces
						int md = ((c.opts & 2) || (surf_cls == 2 && !tr_merge)) ? 0 : face_mode(res);
						if (md != 0) {
							uint64_t u0 = ((uint64_t)fdata & 0x0FFFFFFF) | (((uint64_t)tint & 0xFFFFFF) << 28) | ((uint64_t)res.center << 52) | ((uint64_t)md << 53);
							uint64_t u1 = 0;
							for (int k = 0; k < 4; k++)
								u1 |= ((uint64_t)res.sky[k] << (k * 6)) | ((uint64_t)res.blk[k] << (24 + k * 6)) | ((uint64_t)res.ao[k] << (48 + k * 2));
							int mi = ((ly - 1) * 16 + z) * 16 + x;
							masks[d][mi] = fdesc.get(u0, u1) + 1;
							mask_cls[d * 16 * 16 * GH + mi] = (uint8_t)surf_cls;
						} else {
							emit_cube_face(surfs[surf_cls], x, ly - 1, z, d, 1, 1, fdata, tint, res);
						}
					}
				} else if (fl & F_MODEL) {
					int sc = (fl & F_CUTOUT) ? 1 : ((fl & F_TRANSLUCENT) ? 2 : 0);
					emit_model(surfs[sc], c, i, x, ly - 1, z, st, fl, ci);
				}
				if (fl & (F_FLUID | F_WATERLOGGED)) {
					emit_fluid((fl & F_LAVA) == 0 ? surfs[2] : surfs[0], c, i, x, ly - 1, z, st, fl, ci);
				}
			}
		}
	}
	for (int d = 0; d < 6; d++) greedy(masks[d], mask_cls, d, surfs, fdesc);
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 5);
	put_surface(ret, 0, surfs[0]);
	put_surface(ret, 1, surfs[1]);
	put_surface(ret, 2, surfs[2]);
	array_set_int(ret, 3, y_base);
	{
		// section visibility for occlusion culling (TerrainRD tr_vis)
		Owned vis(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY);
		resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, vis.ptr(), 4);
		int64_t *vp = i64_w(vis.ptr());
		for (int sct = 0; sct < 4; sct++) vp[sct] = (int64_t)section_vis(c, sct);
		array_set_native(ret, 4, GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, vis.ptr());
	}
	delete cp;
	return true;
}

} // namespace

void register_mesher(const char *cls) {
	register_method(cls, "mesh", fn_mesh, 13);
}
