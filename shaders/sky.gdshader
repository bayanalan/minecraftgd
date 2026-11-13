// Java 26.3 sky (SkyRenderer + core/sky.fsh), evaluated per view direction, colour math in sRGB like Java's
// gamma-space framebuffer, converted to linear at the end:
// - clear colour = fog colour;
// - sky disc: octagonal fan 16 blocks above the camera, radius 512, coloured with the sky colour and fogged per
//   vertex like sky.fsh (spherical distance 0 .. FogSkyEnd, cylindrical distance cut at FogSkyEnd), the distances
//   interpolated across the fan triangles exactly as the rasteriser does;
// - dark disc (camera below the horizon height): black fan drawn 4 blocks below the camera, same fog;
// - sunrise / sunset fan: 16-triangle fan (apex 100 blocks towards the sun's horizon, ring radius 120 raised
//   40 * alpha on the sun side), alpha blended, not fogged;
// - sun (half size 30) and moon (half size 20) textured quads 100 blocks away, additive (SRC_ALPHA, ONE);
// stars are a separate mesh (SkyStars). Nether: fog colour; End: end_sky texture box.
shader_type sky;

uniform vec3 sky_color = vec3(0.47, 0.65, 1.0);   // sRGB
uniform vec4 fog_color = vec4(0.75, 0.85, 1.0, 1.0);   // sRGB, a = fog strength
uniform float sky_end = 256.0;                     // FogSkyEnd (render distance in blocks)
uniform bool dark_disc = false;
uniform vec4 sunrise = vec4(0.0);                  // sRGB colour, alpha
uniform float sunrise_side = 1.0;                  // -1: fan towards +X (sunrise), 1: towards -X (sunset)
uniform float sun_angle = 0.0;                     // radians, 0 = overhead
uniform float moon_angle = 3.14159265;
uniform float celestial_alpha = 1.0;               // 1 - rain
uniform sampler2D sun_tex : filter_nearest;        // raw sRGB values (no source_color: blended in sRGB)
uniform sampler2D moon_tex : filter_nearest;
uniform bool has_textures = false;
uniform int mode = 0;                              // 0 overworld, 1 flat fog colour (Nether), 2 End sky texture
uniform sampler2D end_tex : filter_nearest, repeat_enable;
uniform bool has_end_tex = false;

float lin_fog(float d, float s, float e) {
	if (d <= s) return 0.0;
	if (d >= e) return 1.0;
	return (d - s) / (e - s);
}

// one disc: hit of the plane at `plane_y` (geometry radius 512, fog distances of the untranslated +-16 geometry)
vec4 sky_disc(vec3 d, float plane_y, vec3 col) {
	float t = plane_y / d.y;
	if (t <= 0.0) return vec4(0.0);
	vec2 p = d.xz * t;
	float r = length(p);
	const float SEG = 0.785398163;   // 45 deg sectors, vertices at -180..180 step 45
	float phi = atan(p.y, p.x);
	float k = floor((phi + 3.14159265) / SEG);
	float mid = (k + 0.5) * SEG - 3.14159265;
	float rc = 512.0 * cos(SEG * 0.5) / cos(phi - mid);
	if (r > rc) return vec4(0.0);
	float u = r / rc;
	float sph = mix(16.0, 512.249939, u);
	float cyl = mix(16.0, 512.0, u);
	float f = max(lin_fog(sph, 0.0, sky_end), lin_fog(cyl, sky_end, sky_end));
	return vec4(mix(col, fog_color.rgb, f * fog_color.a), 1.0);
}

// Moller-Trumbore from the origin; returns (t, u, v) or t < 0
vec3 ray_tri(vec3 d, vec3 a, vec3 b, vec3 c) {
	vec3 e1 = b - a;
	vec3 e2 = c - a;
	vec3 pv = cross(d, e2);
	float det = dot(e1, pv);
	if (abs(det) < 1e-6) return vec3(-1.0);
	float inv = 1.0 / det;
	vec3 tv = -a;
	float u = dot(tv, pv) * inv;
	if (u < 0.0 || u > 1.0) return vec3(-1.0);
	vec3 qv = cross(tv, e1);
	float v = dot(d, qv) * inv;
	if (v < 0.0 || u + v > 1.0) return vec3(-1.0);
	float t = dot(e2, qv) * inv;
	return vec3(t, u, v);
}

vec3 sunrise_fan(vec3 d, vec3 col) {
	float a = sunrise.a;
	float s = sunrise_side;
	vec3 apex = vec3(-100.0 * s, 0.0, 0.0);
	for (int k = 0; k < 16; k++) {
		float g0 = float(k) * 6.28318531 / 16.0;
		float g1 = float(k + 1) * 6.28318531 / 16.0;
		vec3 r0 = vec3(-120.0 * s * cos(g0), 40.0 * a * cos(g0), 120.0 * s * sin(g0));
		vec3 r1 = vec3(-120.0 * s * cos(g1), 40.0 * a * cos(g1), 120.0 * s * sin(g1));
		vec3 h = ray_tri(d, apex, r0, r1);
		if (h.x > 0.0) {
			float w_apex = 1.0 - h.y - h.z;
			col = mix(col, sunrise.rgb, a * w_apex);
		}
	}
	return col;
}

// textured quad 100 blocks away along the rotated +Y axis (Java: YP(-90) then XP(angle)); half size hs
vec4 celestial(vec3 d, float ang, float hs, bool flip_uv, sampler2D tex) {
	vec3 dirv = vec3(-sin(ang), cos(ang), 0.0);
	float dd = dot(d, dirv);
	if (dd <= 0.0) return vec4(0.0);
	vec3 p = d * (100.0 / dd);
	vec3 ax_u = vec3(0.0, 0.0, 1.0);
	vec3 ax_v = vec3(-cos(ang), -sin(ang), 0.0);
	float lx = dot(p, ax_u) / hs;
	float lz = dot(p, ax_v) / hs;
	if (abs(lx) > 1.0 || abs(lz) > 1.0) return vec4(0.0);
	vec2 uv = vec2(lx, lz) * 0.5 + 0.5;
	if (flip_uv) uv = vec2(1.0) - uv;
	if (!has_textures) return vec4(1.0, 1.0, 0.9, 1.0);
	return texture(tex, uv);
}

vec3 end_sky(vec3 dir) {
	// Java EndSkyRenderer: end_sky texture on the 6 faces of a box, 16 repeats per face, tinted 40/255
	vec3 a = abs(dir);
	vec2 uv;
	if (a.x >= a.y && a.x >= a.z) uv = dir.zy / a.x;
	else if (a.y >= a.z) uv = dir.xz / a.y;
	else uv = dir.xy / a.z;
	vec3 t = has_end_tex ? texture(end_tex, uv * 8.0).rgb : vec3(0.5, 0.45, 0.55);
	return t * (40.0 / 255.0);
}

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = fog_color.rgb;
	if (mode == 2) {
		col = end_sky(d);
	} else if (mode == 0) {
		if (d.y > 0.0) {
			vec4 top = sky_disc(d, 16.0, sky_color);
			if (top.a > 0.0) col = top.rgb;
		} else if (dark_disc && d.y < 0.0) {
			vec4 bot = sky_disc(d, -4.0, vec3(0.0));
			if (bot.a > 0.0) col = bot.rgb;
		}
		if (sunrise.a > 0.0) {
			col = sunrise_fan(d, col);
		}
		if (celestial_alpha > 0.0) {
			vec4 sun = celestial(d, sun_angle, 30.0, false, sun_tex);
			col += sun.rgb * sun.a * celestial_alpha;
			vec4 moon = celestial(d, moon_angle, 20.0, true, moon_tex);
			col += moon.rgb * moon.a * celestial_alpha;
		}
	}
	COLOR = to_linear(clamp(col, 0.0, 1.0));
}
