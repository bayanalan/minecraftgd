// Enchantment glint on 3D items and armour (next pass over the item's own geometry) - the game's core/glint shader:
// colour = glint texture * GlintAlpha (Glint Strength, default 0.75), blended SRC_COLOR / ONE (dst += c * c), only
// where the item itself drew (Java: EQUAL depth test; here the item texture's alpha >= 0.1), texture coordinates =
// TextureMat * UV, TextureMat = translate(-f, g) * rotateZ(10 deg) * scale(s): f = (t % 110000) / 110000,
// g = (t % 30000) / 30000, t = ms * Glint Speed (default 0.5) * 8. s = 8 on item-atlas UVs (held / dropped items),
// 0.16 on armour texture UVs (worn armour, enchanted_glint_armor).
// sprite: xy = UV origin in the (stand-in) items atlas, z = UV size; armour passes (0, 0, 1).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
#include "res://shaders/viewmodel.gdshaderinc"

uniform sampler2D item_tex : filter_nearest, source_color;
uniform sampler2D glint_tex : repeat_enable, filter_linear;   // raw (sRGB) values like Java
uniform float glint_alpha = 0.75;
uniform float glint_speed = 0.5;
uniform float glint_scale = 8.0;
uniform vec3 sprite = vec3(0.0, 0.0, 1.0);
uniform bool use_mask = true;
instance uniform vec2 light = vec2(1.0);   // (set on entity meshes; the glint is unlit)

void vertex() {
	VM_POSITION
}

void fragment() {
	if (use_mask && texture(item_tex, UV).a < 0.1) {
		discard;
	}
	float t = TIME * 1000.0 * glint_speed * 8.0;
	float f = mod(t, 110000.0) / 110000.0;
	float g = mod(t, 30000.0) / 30000.0;
	vec2 uv = (sprite.xy + UV * sprite.z) * glint_scale;
	const float A = 0.17453292;
	uv = vec2(cos(A) * uv.x - sin(A) * uv.y - f, sin(A) * uv.x + cos(A) * uv.y + g);
	vec3 c = texture(glint_tex, uv).rgb * glint_alpha;
	vec3 add = c * c;   // what Java adds to the sRGB framebuffer
	ALBEDO = mix(add / 12.92, pow((add + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), add));
}
