// Glowing outline composite (GlowOutline): the game's post_effect/entity_outline chain in one pass over the outline
// buffer region - entity_sobel (alpha = clamped sum of the 4-neighbour alpha differences, colour = 0.2 x the summed
// alpha-weighted colours of the 5 taps), then entity_outline_box_blur horizontally and vertically (radius 2: bilinear
// taps at -1.5, +0.5 and a half-weighted +2 = half of each of the 5 texels; colour / 2.5, alpha summed, RGBA8-clamped
// after every pass), blended with SRC_ALPHA / ONE_MINUS_SRC_ALPHA. The buffer holds flat silhouettes, so only its
// alpha is read (colour = the team colour).
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform sampler2D sil : filter_nearest;
uniform vec3 team = vec3(1.0);

void fragment() {
	ivec2 sz = textureSize(sil, 0);
	ivec2 c = ivec2(UV * vec2(sz));
	// 7 x 7 alpha window around the pixel (sobel at the 5 x 5 blur taps needs +-3)
	float a[49];
	for (int y = 0; y < 7; y++) {
		for (int x = 0; x < 7; x++) {
			ivec2 p = c + ivec2(x - 3, y - 3);
			bool inside = p.x >= 0 && p.y >= 0 && p.x < sz.x && p.y < sz.y;
			a[y * 7 + x] = inside ? texelFetch(sil, p, 0).a : 0.0;
		}
	}
	float out_c = 0.0;
	float out_a = 0.0;
	for (int j = -2; j <= 2; j++) {
		float row_c = 0.0;
		float row_a = 0.0;
		for (int i = -2; i <= 2; i++) {
			int k = (j + 3) * 7 + (i + 3);
			float ce = a[k];
			float le = a[k - 1];
			float ri = a[k + 1];
			float up = a[k - 7];
			float dn = a[k + 7];
			row_a += clamp(abs(ce - le) + abs(ce - ri) + abs(ce - up) + abs(ce - dn), 0.0, 1.0);
			row_c += 0.2 * (ce + le + ri + up + dn);
		}
		// horizontal blur result at row j
		out_c += row_c / 5.0;
		out_a += min(1.0, 0.5 * row_a);
	}
	// vertical blur
	float fa = min(1.0, 0.5 * out_a);
	COLOR = vec4(team * (out_c / 5.0), fa);
}
