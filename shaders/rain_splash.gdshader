// Rain splashes (Java WaterDropParticle spawned by WeatherEffectRenderer.tickRainParticles), evaluated entirely here:
// Particles writes one spawn record per drop into a ring (MODEL_MATRIX[3] = start position on the block top /
// fluid surface, [0] = start velocity, [1] = (spawn tick & 131071, lifetime, -), [2] = (ground ticks survived, quad
// width, -), COLOR = light, INSTANCE_CUSTOM = splash sprite UV rect). Java's tick: yd -= 0.06; move; velocity x 0.98;
// stops (stoppedByCollision) on landing back on its surface, then 50 % removal per tick; removed after its lifetime.
// Closed form per tick n in the air: v_n = 0.98^n (v0 - C) + C with C = -0.98 x 0.06 / 0.02, so
// y_n = y0 + (v0 - C)(1 - 0.98^n) / 0.02 + n (C - 0.06); x_n = x0 + xd0 (1 - 0.98^n) / 0.02. Rendered at
// lerp(pos(age - 1), pos(age), partial tick) like any particle.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2D atlas : filter_nearest, source_color;
global uniform float mc_partial;
global uniform float mc_ticks;
#include "res://shaders/mc_fog.gdshaderinc"
varying vec3 v_rel;

const float F = 0.98;
const float G = 0.06;

vec3 drop_pos(vec3 p0, vec3 v0, float n, float land) {
	float k = min(n, land);
	float fk = pow(F, k);
	float c = -F * G / (1.0 - F);
	float y = k >= land ? 0.0 : (v0.y - c) * (1.0 - fk) / (1.0 - F) + k * (c - G);
	vec2 xz = v0.xz * (1.0 - fk) / (1.0 - F);
	return p0 + vec3(xz.x, y, xz.y);
}

void vertex() {
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 v0 = MODEL_MATRIX[0].xyz;
	float age = mod(mc_ticks - MODEL_MATRIX[1].x + 65536.0, 131072.0) - 65536.0;
	float life = MODEL_MATRIX[1].y;
	// landing tick: the first tick whose move ends at or below the surface it started on
	float c = -F * G / (1.0 - F);
	float land = 64.0;
	for (int n = 1; n < 64; n++) {
		float fn = float(n);
		if ((v0.y - c) * (1.0 - pow(F, fn)) / (1.0 - F) + fn * (c - G) <= 0.0) {
			land = fn;
			break;
		}
	}
	float die = min(life + 1.0, land + MODEL_MATRIX[2].x);
	if (age < 0.0 || age >= die || life <= 0.0) {
		POSITION = vec4(0.0, 0.0, 2.0, 1.0);
		UV = vec2(0.0);
		v_rel = vec3(0.0);
	} else {
		vec3 cur = drop_pos(p0, v0, age, land);
		vec3 prev = age >= 1.0 ? drop_pos(p0, v0, age - 1.0, land) : cur;
		vec3 center = mix(prev, cur, mc_partial);
		float s = MODEL_MATRIX[2].y;
		vec3 w = center + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
		v_rel = w - CAMERA_POSITION_WORLD;
		UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
	}
}

void fragment() {
	vec4 c = texture(atlas, UV) * COLOR;
	if (c.a < 0.1) {
		discard;
	}
	vec3 fc = pow(mc_fog_color.rgb, vec3(2.2));
	ALBEDO = mix(c.rgb, fc, mc_fog_value(v_rel) * mc_fog_color.a);
}
