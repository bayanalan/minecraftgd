// Particles: camera-facing quads from one MultiMesh, rebuilt once per game tick (Particles._build) and interpolated
// here with the global partial tick like Java's render-time lerp of (xo, yo, zo) -> (x, y, z). Instance data:
// MODEL_MATRIX[3] = position, [2] = previous position - position, [0] = (quad width, age, lifetime),
// [1] = (previous roll, roll, size curve: 0 constant, 1 SingleQuadParticle grow-in over 1/32 of the life, 2 flame
// shrink 1 - t² / 2, 3 leaf roll); INSTANCE_CUSTOM = atlas UV rect (u, v, w, h), COLOR = tint * light (alpha = fade).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2D atlas : filter_nearest, source_color;
global uniform float mc_partial;
#include "res://shaders/mc_fog.gdshaderinc"
varying vec3 v_rel;

void vertex() {
	float pt = mc_partial;
	vec3 center = MODEL_MATRIX[3].xyz + MODEL_MATRIX[2].xyz * (1.0 - pt);
	float s = MODEL_MATRIX[0].x;
	float tl = (MODEL_MATRIX[0].y + pt) / max(MODEL_MATRIX[0].z, 1.0);
	float curve = MODEL_MATRIX[1].z;
	float roll = 0.0;
	if (curve > 2.5) {
		roll = mix(MODEL_MATRIX[1].x, MODEL_MATRIX[1].y, pt);
	} else if (curve > 1.5) {
		s *= 1.0 - tl * tl * 0.5;
	} else if (curve > 0.5) {
		s *= clamp(tl * 32.0, 0.0, 1.0);
	}
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec2 rc = vec2(cos(roll), sin(roll));   // Java SingleQuadParticle roll
	vec2 q = vec2(VERTEX.x * rc.x - VERTEX.y * rc.y, VERTEX.x * rc.y + VERTEX.y * rc.x);
	vec3 w = center + (right * q.x + up * q.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
	v_rel = w - CAMERA_POSITION_WORLD;
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}

void fragment() {
	vec4 c = texture(atlas, UV) * COLOR;
	if (c.a < 0.1) {
		discard;
	}
	// particle colours are linear here (source_color): fog mixed with the linearised fog colour
	vec3 fc = pow(mc_fog_color.rgb, vec3(2.2));
	ALBEDO = mix(c.rgb, fc, mc_fog_value(v_rel) * mc_fog_color.a);
}
