// Map decoration name (Java MapRenderer: white text on a 50 % black background), alpha blended; the ViewModel variant
// (VIEWMODEL defined) re-projects it with the hand when the map is held.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
#include "res://shaders/viewmodel.gdshaderinc"

uniform sampler2D tex : source_color, filter_nearest;

void vertex() {
	VM_POSITION
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
