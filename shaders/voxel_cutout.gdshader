shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#include "res://shaders/voxel_common.gdshaderinc"

void fragment() {
	vec4 c = voxel_color(UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
}
