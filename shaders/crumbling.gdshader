// Java rendertype_crumbling: destroy_stage texels with alpha < 0.1 discarded, blended DST_COLOR / SRC_COLOR
// (result = 2 * src * dst in sRGB: mid grey leaves the block unchanged, darker cracks darken, lighter ones lighten).
// The framebuffer is linear: a factor of 2 * s in sRGB is (2 * s)^2.2 in linear light.
shader_type spatial;
render_mode unshaded, blend_mul, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D tex : filter_nearest, repeat_enable;

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.1) {
		discard;
	}
	ALBEDO = pow(clamp(2.0 * c.rgb, vec3(0.0), vec3(2.0)), vec3(2.2));
}
