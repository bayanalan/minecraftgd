// End crystal healing beam (Java RenderType.entitySmoothCutout of end_crystal_beam.png): texture (repeating, it
// scrolls along the beam) * vertex colour (black at the dragon, white at the crystal), alpha-tested, both sides.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D tex : filter_nearest, repeat_enable;
#include "res://shaders/mc_fog.gdshaderinc"
varying vec3 v_rel;

void vertex() {
	v_rel = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD;
}

void fragment() {
	vec4 t = texture(tex, UV);
	if (t.a < 0.1) {
		discard;
	}
	vec3 col = mc_apply_fog(clamp(t.rgb * COLOR.rgb, 0.0, 1.0), v_rel);
	ALBEDO = mix(pow((col + 0.055) / 1.055, vec3(2.4)), col / 12.92, lessThan(col, vec3(0.04045)));
}
