// voxel_item.gdshader for translucent block items (stained glass, ice, slime, honey, tinted glass): Java draws them
// with the translucent item sheet (item_entity_translucent_cull) - alpha blended, back faces culled - where the cutout
// variant turned stained glass into opaque bricks of colour in the hand and on the ground.
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque;
#define ITEM_LIGHT
#include "res://shaders/voxel_common.gdshaderinc"

void fragment() {
	vec4 c = voxel_color(UV);
	if (c.a < 0.1) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = 1.0 - pow(1.0 - c.a, 1.5);   // sRGB-like blending in a linear target (as voxel_translucent)
}
