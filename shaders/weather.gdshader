// Java WeatherEffectRenderer columns, drawn as their visible texels only. The column quad is not drawn whole: 97.5 % of
// rain.png (99 % of snow.png) is transparent, and the full quad shaded ~78 M fragments per frame at 2880x1800 only to
// discard them. The mesh is one small quad per vertical run of visible texels instead (WeatherFX._streak_mesh: texel
// column, run rows, repeat k (and u wrap for snow)); each is placed here exactly over the texels the full quad would
// sample there (same plane, same texture coordinates, clipped to the column), so every pixel gets the same texel,
// colour and blend as the full quad (shaders/weather_full.gdshader, --raincheck compares both). The light / fog colour
// is interpolated from the full quad's four corners the way its two triangles did. Column data: weather_common.
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
	// v along the full quad: (org.y + (1 - t) * hgt) / 4 + c, t = 0 at the bottom, 1 at the top
	float vt = org.y * 0.25 + c;
	float vb = (org.y + hgt) * 0.25 + c;
	float k = mod(UV2.y, 16.0);
	float w = floor(UV2.y / 16.0);
	float n = floor(vt) + k;   // which repeat of the texture this copy of the run is (the tile mesh has enough copies)
	float va = max(UV.y + n, vt);
	float vz = min(UV2.x + n, vb);
	float m = floor(uo) + w;   // u wrap (snow scrolls sideways)
	float ua = max(UV.x + m, uo);
	float uz = min(UV.x + texel_w + m, uo + 1.0);
	if (va >= vz || ua >= uz || hgt <= 0.0) {
		// this copy lies outside the column: all four corners on one point (no area, no fragments)
		POSITION = vec4(0.0, 0.0, 2.0, 1.0);
		v_col = vec4(0.0);
		v_uv = vec2(0.0);
	} else {
		float vv = mix(va, vz, VERTEX.y);
		float uu = mix(ua, uz, VERTEX.x);
		float s = uu - uo;
		float t = 1.0 - ((vv - c) * 4.0 - org.y) / hgt;
		vec3 wp = org + vec3(side.x * (s - 0.5), t * hgt, side.y * (s - 0.5));
		vec3 lc = weather_light(MODEL_MATRIX);
		// fog: the full quad's corners (0: bottom left, 1: bottom right, 2: top right, 3: top left), interpolated over
		// its two triangles (0 1 2: t <= s, 0 2 3: t >= s); columns nearer than both fog starts (the usual case) skip it
		vec2 dxz = org.xz - cam.xz;
		float far = length(vec2(length(dxz) + 0.71, max(abs(org.y - cam.y), abs(org.y + hgt - cam.y))));
		vec3 col;
		if (mc_fog_color.a <= 0.0 || far <= min(mc_fog_dist.x, mc_fog_dist.z)) {
			col = to_lin(lc);
		} else {
			vec3 p0 = org + vec3(-0.5 * side.x, 0.0, -0.5 * side.y) - cam;
			vec3 p1 = org + vec3(0.5 * side.x, 0.0, 0.5 * side.y) - cam;
			vec3 p2 = p1 + vec3(0.0, hgt, 0.0);
			vec3 p3 = p0 + vec3(0.0, hgt, 0.0);
			vec3 c0 = to_lin(mc_apply_fog(lc, p0));
			vec3 c1 = to_lin(mc_apply_fog(lc, p1));
			vec3 c2 = to_lin(mc_apply_fog(lc, p2));
			vec3 c3 = to_lin(mc_apply_fog(lc, p3));
			col = t <= s ? c0 + s * (c1 - c0) + t * (c2 - c1) : c0 + t * (c3 - c0) + s * (c2 - c3);
		}
		v_col = vec4(col, alpha);
		v_uv = vec2(uu, vv);
		POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	}
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
