// First-person held map layers (ViewModel): unshaded nearest-filtered texture, re-projected like the hand.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#define VIEWMODEL
#include "res://shaders/viewmodel.gdshaderinc"

uniform sampler2D tex : source_color, filter_nearest;

void vertex() {
	VM_POSITION
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.1) {
		discard;
	}
	ALBEDO = c.rgb;
}
