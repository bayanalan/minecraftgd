// Java core/stars (colour (b, b, b, b), additive SRC_ALPHA / ONE: adds b * b in sRGB). Placed at the far end of the
// reverse-Z depth range so it only shows where nothing else was drawn (behind terrain, like the Java sky pass).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform float brightness = 0.0;

void vertex() {
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z = POSITION.w * 1e-7;
}

void fragment() {
	float b = brightness * brightness;
	ALBEDO = vec3(b <= 0.04045 ? b / 12.92 : pow((b + 0.055) / 1.055, 2.4));
	ALPHA = 1.0;
}
