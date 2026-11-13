// In-world menu background blur (Java GameRenderer.processBlurEffect with Menu Background Blurriness): gaussian over
// the rendered world, radius scaled with the window height. Applied by UiKit.inworld_background.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float radius = 5.0;   // option value 0..10

void fragment() {
	if (radius <= 0.0) {
		COLOR = texture(screen_tex, SCREEN_UV);
	} else {
		vec2 step = SCREEN_PIXEL_SIZE * radius * (1.0 / SCREEN_PIXEL_SIZE.y / 1080.0) * 1.6;
		vec4 c = vec4(0.0);
		float ws = 0.0;
		for (int x = -3; x <= 3; x++) {
			for (int y = -3; y <= 3; y++) {
				float w = exp(-float(x * x + y * y) / 6.0);
				c += textureLod(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * step, 2.0) * w;
				ws += w;
			}
		}
		COLOR = vec4(c.rgb / ws, 1.0);
	}
}