shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque;
#include "res://shaders/voxel_common.gdshaderinc"

void fragment() {
	vec4 c = voxel_color(UV);
	ALBEDO = c.rgb;
	ALPHA = 1.0 - pow(1.0 - c.a, 1.5);   // sRGB-like blending in a linear target (see TerrainRD)
}
