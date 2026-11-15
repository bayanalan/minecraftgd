// Item fragment particles (Java BreakingItemParticle / ItemParticleOption: eating, items breaking, thrown eggs):
// camera-facing quads from one MultiMesh showing a 4x4-texel window of the item's sprite in a 16 x 16-cell atlas of
// 16 px item sprites. INSTANCE_CUSTOM = (window u, window v, cell u0, cell v0); COLOR = light (sRGB, linearised here).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2D items_tex : filter_nearest, source_color;
global uniform float mc_partial;
#include "res://shaders/mc_fog.gdshaderinc"
varying vec3 v_rel;

void vertex() {
	// per-tick instance data (Particles._build_terrain): [3] = position, [2] = previous - position, [0].x = size
	vec3 center = MODEL_MATRIX[3].xyz + MODEL_MATRIX[2].xyz * (1.0 - mc_partial);
	float s = MODEL_MATRIX[0].x;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 w = center + (right * VERTEX.x + up * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
	v_rel = w - CAMERA_POSITION_WORLD;
	// Java: u0 = getU((uo + 1) / 4), u1 = getU(uo / 4) (mirrored), v0 = getV(vo / 4), v1 = getV((vo + 1) / 4)
	vec2 inner = clamp(INSTANCE_CUSTOM.xy + vec2(1.0 - UV.x, UV.y) * 0.25, vec2(0.002), vec2(0.998));
	UV = INSTANCE_CUSTOM.zw + inner / 16.0;
}

void fragment() {
	vec4 t = texture(items_tex, UV);
	if (t.a < 0.1) {
		discard;
	}
	vec3 c = t.rgb * pow(COLOR.rgb, vec3(2.2));
	vec3 fc = pow(mc_fog_color.rgb, vec3(2.2));
	ALBEDO = mix(c, fc, mc_fog_value(v_rel) * mc_fog_color.a);
}
