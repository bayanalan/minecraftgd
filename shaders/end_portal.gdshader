// End portal / end gateway surface - the game's core/rendertype_end_portal shader math (TheEndPortalRenderer):
// screen-projected texture coordinates; colour = end_sky * C[0] + sum over layers i = 1..N of
// end_portal(uv_i) * C[i - 1], uv_i = 0.5 * (k R(a) s + (17 / i, (2 + i / 1.5) * GameTime * 1.5)) + 0.25 with
// a = 2 * (4321 i^2 + 9 i) degrees, k = 2 * (4.5 - i / 4); N = 15 (portal) / 16 (gateway);
// GameTime = ((game time % 24000) + partial tick) / 24000. Java writes the sum straight into the sRGB framebuffer.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform sampler2D sky_tex : repeat_enable, filter_nearest;
uniform sampler2D portal_tex : repeat_enable, filter_nearest;
uniform int layers = 15;
uniform float game_time = 0.0;
instance uniform vec2 light = vec2(1.0);   // (set on every block-entity mesh; the portal is full bright)

const vec3 C[16] = vec3[16](
	vec3(0.022087, 0.098399, 0.110818), vec3(0.011892, 0.095924, 0.089485), vec3(0.027636, 0.101689, 0.100326),
	vec3(0.046564, 0.109883, 0.114838), vec3(0.064901, 0.117696, 0.097189), vec3(0.063761, 0.086895, 0.123646),
	vec3(0.084817, 0.111994, 0.166380), vec3(0.097489, 0.154120, 0.091064), vec3(0.106152, 0.131144, 0.195191),
	vec3(0.097721, 0.110188, 0.187229), vec3(0.133516, 0.138278, 0.148582), vec3(0.070006, 0.243332, 0.235792),
	vec3(0.196766, 0.142899, 0.214696), vec3(0.047281, 0.315338, 0.321970), vec3(0.204675, 0.390010, 0.302066),
	vec3(0.080955, 0.314821, 0.661491));

vec2 layer_uv(vec2 s, float i) {
	float a = radians((i * i * 4321.0 + i * 9.0) * 2.0);
	float k = (4.5 - i / 4.0) * 2.0;
	vec2 p = vec2(s.x * cos(a) - s.y * sin(a), s.x * sin(a) + s.y * cos(a)) * k;
	p += vec2(17.0 / i, (2.0 + i / 1.5) * (game_time * 1.5));
	return p * 0.5 + 0.25;
}

void fragment() {
	vec2 s = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y);   // GL window coordinates (origin bottom left)
	vec3 c = texture(sky_tex, s).rgb * C[0];
	for (int i = 0; i < layers; i++) {
		c += texture(portal_tex, layer_uv(s, float(i + 1))).rgb * C[i];
	}
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
