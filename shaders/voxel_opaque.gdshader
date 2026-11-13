shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
#include "res://shaders/voxel_common.gdshaderinc"

void fragment() {
	vec4 c = voxel_color(UV);
	ALBEDO = c.rgb;
}
