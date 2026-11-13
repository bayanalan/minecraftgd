// Breaking-block particles (Java TerrainParticle): camera-facing quads from one MultiMesh showing a 4x4-texel window of
// the block's particle texture (block texture array layer). Instance transform = position + uniform size;
// INSTANCE_CUSTOM = (window u, window v, layer, -); COLOR = 0.6 x block tint x light (sRGB, linearised here).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

uniform sampler2DArray blocks_tex : filter_nearest, source_color;
#include "res://shaders/mc_fog.gdshaderinc"
varying vec3 v_rel;
varying flat float v_layer;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 w = center + (right * VERTEX.x + up * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
	v_rel = w - CAMERA_POSITION_WORLD;
	// Java: u0 = getU((uo + 1) / 4), u1 = getU(uo / 4) (mirrored), v0 = getV(vo / 4), v1 = getV((vo + 1) / 4)
	UV = INSTANCE_CUSTOM.xy + vec2(1.0 - UV.x, UV.y) * 0.25;
	v_layer = INSTANCE_CUSTOM.z;
}

void fragment() {
	vec4 t = texture(blocks_tex, vec3(UV, v_layer));
	if (t.a < 0.1) {
		discard;
	}
	vec3 c = t.rgb * pow(COLOR.rgb, vec3(2.2));
	vec3 fc = pow(mc_fog_color.rgb, vec3(2.2));
	ALBEDO = mix(c, fc, mc_fog_value(v_rel) * mc_fog_color.a);
}
