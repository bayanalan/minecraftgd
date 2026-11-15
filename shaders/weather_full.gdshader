// Java WeatherEffectRenderer columns as whole camera-facing quads (1 block wide, bottom..top): the --raincheck
// reference for shaders/weather.gdshader (same instance data, see weather_common). Fill-rate bound; not used in play.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

#include "res://shaders/weather_common.gdshaderinc"

void vertex() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 org;
	float hgt;
	vec2 side;
	float uo;
	float c;
	float alpha;
	weather_column(MODEL_MATRIX, cam, org, hgt, side, uo, c, alpha);
	vec3 wp = org + vec3(side.x * VERTEX.x, VERTEX.y * hgt, side.y * VERTEX.x);
	vec3 lc = weather_light(MODEL_MATRIX);
	v_col = vec4(to_lin(mc_apply_fog(lc, wp - cam)), alpha);
	// Java: the top vertices take v = bottomY / 4, the bottom ones topY / 4 (v runs downwards), plus the scroll
	v_uv = vec2(VERTEX.x + 0.5 + uo, (org.y + (1.0 - VERTEX.y) * hgt) * 0.25 + c);
	POSITION = hgt > 0.0 ? PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0) : vec4(0.0, 0.0, 2.0, 1.0);
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
