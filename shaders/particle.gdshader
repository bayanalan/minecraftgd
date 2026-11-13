// Particles: camera-facing quads from one MultiMesh. Instance transform = position + uniform size,
// INSTANCE_CUSTOM = atlas UV rect (u, v, w, h), COLOR = tint * light (alpha = fade).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2D atlas : filter_nearest, source_color;
#include "res://shaders/mc_fog.gdshaderinc"
varying vec3 v_rel;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec2 rc = MODEL_MATRIX[0].xy / max(s, 1e-6);   // (cos, sin) of the particle roll (Java SingleQuadParticle roll)
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
