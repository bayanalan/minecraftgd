// Enchantment glint over GUI item icons - the game's own core/glint shader and GLINT pipeline:
// colour = glint texture * GlintAlpha (Glint Strength option, default 0.75), blended SRC_COLOR / ONE (dst += c * c),
// only where the item drew pixels (Java's EQUAL depth test; here the icon's alpha >= 0.1), texture coordinates =
// TextureMat * item UV with TextureMat = translate(-f, g) * rotateZ(10 deg) * scale(8): f = (t % 110000) / 110000,
// g = (t % 30000) / 30000, t = milliseconds * Glint Speed (default 0.5) * 8.
// Per-icon input (vertex colour): rg = the icon's atlas UV origin, b = its atlas UV size (vanilla items atlas).
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform sampler2D glint_tex : repeat_enable, filter_linear;
uniform float glint_alpha = 0.75;
uniform float glint_speed = 0.5;
uniform float glint_scale = 8.0;

varying vec3 v_sprite;

void vertex() {
	v_sprite = COLOR.rgb;
}

void fragment() {
	vec4 ic = texture(TEXTURE, UV);
	if (ic.a < 0.1) {
		discard;
	}
	float t = TIME * 1000.0 * glint_speed * 8.0;
	float f = mod(t, 110000.0) / 110000.0;
	float g = mod(t, 30000.0) / 30000.0;
	vec2 uv = (v_sprite.xy + UV * v_sprite.z) * glint_scale;
	const float A = 0.17453292;
	uv = vec2(cos(A) * uv.x - sin(A) * uv.y - f, sin(A) * uv.x + cos(A) * uv.y + g);
	vec3 c = texture(glint_tex, uv).rgb * glint_alpha;
	COLOR = vec4(c * c, 1.0);
}
