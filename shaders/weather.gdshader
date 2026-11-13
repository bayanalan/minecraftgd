// Java WeatherEffectRenderer columns: one camera-facing quad per column (1 block wide, bottom..top), rain.png / snow.png
// scrolling, alpha by distance, lit by the column's light through the lightmap. MultiMesh instance:
//   transform: origin = column bottom centre, basis y scale = column height, basis x.x = v scroll per tick
//   custom: x = u offset, y = v offset at the tick, z = alpha, w = (block * 16 + sky) / 255
// The column quad is not drawn whole: 97.5 % of rain.png (99 % of snow.png) is transparent, and the full quad shaded
// ~78 M fragments per frame at 2880x1800 only to discard them. The mesh is one small quad per vertical run of visible
// texels instead (WeatherFX._streak_mesh: texel column, run rows, wrap index k (and u wrap for snow)); each is placed
// here exactly over the texels the full quad would sample there (same plane, same texture coordinates, clipped to the
// column), so every pixel gets the same texel, colour and blend as before. The light / fog colour is interpolated
// from the full quad's four corners the way its two triangles did.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform float partial = 0.0;   // partial tick
uniform float texel_w = 0.015625;   // 1 / texture width
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
	// v along the full quad: (org.y + (1 - t) * hgt) / 4 + c, t = 0 at the bottom, 1 at the top
	float c = INSTANCE_CUSTOM.y + spd * partial;
	float vt = org.y * 0.25 + c;
	float vb = (org.y + hgt) * 0.25 + c;
	float k = mod(UV2.y, 16.0);
	float w = floor(UV2.y / 16.0);
	float n = floor(vt) - 1.0 + k;   // which repeat of the texture this copy of the run is
	float va = max(UV.y + n, vt);
	float vz = min(UV2.x + n, vb);
	float uo = INSTANCE_CUSTOM.x;
	float m = floor(uo) + w;          // u wrap (snow scrolls sideways)
	float ua = max(UV.x + m, uo);
	float uz = min(UV.x + texel_w + m, uo + 1.0);
	float s;
	float t;
	float vv;
	float uu;
	if (va >= vz || ua >= uz || hgt <= 0.0) {
		// this copy lies outside the column: all four corners on one point (no area, no fragments)
		uu = uo;
		vv = vt;
		s = 0.0;
		t = 1.0;
	} else {
		vv = mix(va, vz, VERTEX.y);
		uu = mix(ua, uz, VERTEX.x);
		s = uu - uo;
		t = 1.0 - ((vv - c) * 4.0 - org.y) / hgt;
	}
	vec3 wp = org + vec3(side.x * (s - 0.5), t * hgt, side.y * (s - 0.5));
	float li = floor(INSTANCE_CUSTOM.w * 255.0 + 0.5);
	float bl = floor(li / 16.0);
	float sk = li - bl * 16.0;
	vec3 lc = clamp(textureLod(mc_lightmap, (vec2(bl, sk) + 0.5) / 16.0, 0.0).rgb, 0.0, 1.0);
	// fog: the full quad's corners (0: bottom left, 1: bottom right, 2: top right, 3: top left), interpolated over its
	// two triangles (0 1 2: t <= s, 0 2 3: t >= s); no fog anywhere on the column (the usual case) skips it
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 p0 = org + vec3(-0.5 * side.x, 0.0, -0.5 * side.y) - cam;
	vec3 p1 = org + vec3(0.5 * side.x, 0.0, 0.5 * side.y) - cam;
	vec3 p2 = p1 + vec3(0.0, hgt, 0.0);
	vec3 p3 = p0 + vec3(0.0, hgt, 0.0);
	float fmax = max(max(mc_fog_value(p0), mc_fog_value(p1)), max(mc_fog_value(p2), mc_fog_value(p3)));
	vec3 col;
	if (fmax * mc_fog_color.a <= 0.0) {
		col = to_lin(lc);
	} else {
		vec3 c0 = to_lin(mc_apply_fog(lc, p0));
		vec3 c1 = to_lin(mc_apply_fog(lc, p1));
		vec3 c2 = to_lin(mc_apply_fog(lc, p2));
		vec3 c3 = to_lin(mc_apply_fog(lc, p3));
		col = t <= s ? c0 + s * (c1 - c0) + t * (c2 - c1) : c0 + t * (c3 - c0) + s * (c2 - c3);
	}
	v_col = vec4(col, INSTANCE_CUSTOM.z);
	v_uv = vec2(uu, vv);
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
