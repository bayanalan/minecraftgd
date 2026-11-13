// Entity / player AABB movement against gathered block boxes (port of scripts/world/collision.gd move() after the
// gather step, identical arithmetic): Y first, then the larger horizontal axis, Java step-up (up, horizontal, down)
// when blocked horizontally on the ground.
//
// coll_move(boxes, p) -> [PackedFloat32Array r]
//   boxes: 6 floats per box (min xyz, max xyz).
//   p: 11 floats: mn xyz, mx xyz, motion xyz, step, on_ground_before (0/1).
//   r: 7 floats: motion xyz, hit_x, hit_y, hit_z, on_ground (0/1).
#include "native.h"
#include <cmath>

using namespace gdx;

namespace {
const double EPS = 1.0e-7;

// Godot Vector3 stores 32-bit floats while GDScript scalars are 64-bit: vectors here store floats, scalar maths in double
struct V3 { float v[3]; };

double clip(const float *b, int nb, const V3 &mn, const V3 &mx, int axis, double d) {
	if (std::fabs(d) < EPS) return 0.0;
	int a1 = (axis + 1) % 3, a2 = (axis + 2) % 3;
	for (int i = 0; i < nb; i++) {
		const float *q = b + i * 6;
		double bmn[3] = {q[0], q[1], q[2]}, bmx[3] = {q[3], q[4], q[5]};
		if (bmx[a1] <= mn.v[a1] + EPS || bmn[a1] >= mx.v[a1] - EPS) continue;
		if (bmx[a2] <= mn.v[a2] + EPS || bmn[a2] >= mx.v[a2] - EPS) continue;
		if (d > 0.0 && bmn[axis] >= mx.v[axis] - EPS) d = std::min(d, bmn[axis] - mx.v[axis]);
		else if (d < 0.0 && bmx[axis] <= mn.v[axis] + EPS) d = std::max(d, bmx[axis] - mn.v[axis]);
	}
	return d;
}

V3 collide(const float *b, int nb, V3 mn, V3 mx, const V3 &m) {
	V3 out = {{0, 0, 0}};
	double dy = clip(b, nb, mn, mx, 1, m.v[1]);
	mn.v[1] = (float)(mn.v[1] + dy); mx.v[1] = (float)(mx.v[1] + dy); out.v[1] = (float)dy;
	int order[2] = {0, 2};
	if (!(std::fabs(m.v[0]) >= std::fabs(m.v[2]))) { order[0] = 2; order[1] = 0; }
	for (int k = 0; k < 2; k++) {
		int a = order[k];
		double dd = clip(b, nb, mn, mx, a, m.v[a]);
		mn.v[a] = (float)(mn.v[a] + dd); mx.v[a] = (float)(mx.v[a] + dd); out.v[a] = (float)dd;
	}
	return out;
}

V3 add(const V3 &a, const V3 &b) { return {{a.v[0] + b.v[0], a.v[1] + b.v[1], a.v[2] + b.v[2]}}; }
float h2(const V3 &a) { return a.v[0] * a.v[0] + a.v[2] * a.v[2]; }   // Vector2.length_squared (float)

bool fn_coll_move(const Args &a, void *ret) {
	const void *bv = a.obj(0, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
	const void *pv = a.obj(1, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
	if (!bv || !pv || size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, pv) < 11) return false;
	const float *b = f32(bv);
	int nb = (int)(size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, bv) / 6);
	const float *p = f32(pv);
	V3 mn = {{p[0], p[1], p[2]}}, mx = {{p[3], p[4], p[5]}}, m = {{p[6], p[7], p[8]}};
	float step = p[9];
	bool og_before = p[10] > 0.5f;
	V3 res = collide(b, nb, mn, mx, m);
	bool hit_x = std::fabs(res.v[0] - m.v[0]) > EPS;
	bool hit_z = std::fabs(res.v[2] - m.v[2]) > EPS;
	bool hit_y = std::fabs(res.v[1] - m.v[1]) > EPS;
	bool on_ground = hit_y && m.v[1] < 0.0;
	if (step > 0.0 && (on_ground || og_before) && (hit_x || hit_z)) {
		V3 up = collide(b, nb, mn, mx, {{m.v[0], (float)step, m.v[2]}});
		V3 up_only = collide(b, nb, mn, mx, {{0.0f, (float)step, 0.0f}});
		if (up_only.v[1] < step) {
			V3 horiz = collide(b, nb, add(mn, up_only), add(mx, up_only), {{m.v[0], 0.0f, m.v[2]}});
			V3 alt = add(up_only, horiz);
			if (h2(alt) > h2(up)) up = alt;
		}
		V3 down = collide(b, nb, add(mn, up), add(mx, up), {{0.0f, -up.v[1] + m.v[1], 0.0f}});
		up = add(up, down);
		if (h2(up) > h2(res) + EPS) {
			res = up;
			hit_x = std::fabs(res.v[0] - m.v[0]) > EPS;
			hit_z = std::fabs(res.v[2] - m.v[2]) > EPS;
			hit_y = std::fabs(res.v[1] - m.v[1]) > EPS;
			on_ground = true;
		}
	}
	Owned out(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, out.ptr(), 7);
	float *o = f32_w(out.ptr());
	o[0] = res.v[0]; o[1] = res.v[1]; o[2] = res.v[2];
	o[3] = hit_x ? 1.f : 0.f; o[4] = hit_y ? 1.f : 0.f; o[5] = hit_z ? 1.f : 0.f; o[6] = on_ground ? 1.f : 0.f;
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, out.ptr());
	return true;
}
}  // namespace

void register_collision(const char *cls) {
	register_method(cls, "coll_move", fn_coll_move, 2);
}
