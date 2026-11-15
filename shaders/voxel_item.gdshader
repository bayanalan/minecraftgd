// Block models drawn as entities (dropped block items, falling blocks, primed TNT, held blocks): the voxel cutout
// shading with the light taken from the instance's "light" parameter (the light at the entity) instead of the
// vertices (built at full sky light).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#define ITEM_LIGHT
#include "res://shaders/voxel_common.gdshaderinc"

void fragment() {
	vec4 c = voxel_color(UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
}
