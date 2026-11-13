// Java WeatherEffectRenderer columns: one camera-facing quad per column (1 block wide, bottom..top), rain.png / snow.png
// scrolling, alpha by distance, lit by the column's light through the lightmap. MultiMesh instance:
//   transform: origin = column bottom centre, basis y scale = column height, basis x.x = v scroll per tick
//   custom: x = u offset, y = v offset at the tick, z = alpha, w = (block * 16 + sky) / 255
// Fill-rate bound (up to ~20 blended layers over every pixel near the camera): the light colour and fog are per
// column / vertex, the texture is decoded to linear by the sampler, and empty texels are discarded before anything else.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform float partial = 0.0;   // partial tick
global uniform sampler2D mc_lightmap;
#include "res://shaders/mc_fog.gdshaderinc"

varying vec4 v_col;    // linear light colour (fogged), alpha
varying vec2 v_uv;

vec3 to_lin(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	float hgt = length(MODEL_MATRIX[1].xyz);
	float spd = MODEL_MATRIX[0].x;
	vec2 d = org.xz - CAMERA_POSITION_WORLD.xz;
	float l = max(length(d), 0.0001);
	vec2 side = vec2(-d.y, d.x) / l;
	vec3 wp = org + vec3(side.x * VERTEX.x, VERTEX.y * hgt, side.y * VERTEX.x);
	float li = floor(INSTANCE_CUSTOM.w * 255.0 + 0.5);
	float bl = floor(li / 16.0);
	float sk = li - bl * 16.0;
	vec3 lc = textureLod(mc_lightmap, (vec2(bl, sk) + 0.5) / 16.0, 0.0).rgb;
	// fog of the light colour (the texture is grey-white): per vertex, the columns are within 10 blocks
	v_col = vec4(to_lin(mc_apply_fog(clamp(lc, 0.0, 1.0), wp - CAMERA_POSITION_WORLD)), INSTANCE_CUSTOM.z);
	// Java: the top vertices take v = bottomY / 4, the bottom ones topY / 4 (v runs downwards), plus the scroll
	v_uv = vec2(VERTEX.x + 0.5 + INSTANCE_CUSTOM.x, (org.y + (1.0 - VERTEX.y) * hgt) * 0.25 + INSTANCE_CUSTOM.y + spd * partial);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

void fragment() {
	vec4 c = texture(tex, v_uv);
	float a = c.a * v_col.a;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = c.rgb * v_col.rgb;
	ALPHA = a;
}
