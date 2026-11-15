// Shared column math of shaders/weather.gdshader (visible-texel runs) and weather_full.gdshader (whole column quads,
// --raincheck reference). Per instance (WeatherFX, constant per column, rebuilt only when the column changes):
//   MODEL_MATRIX[3] = (column centre x, motion-blocking height, column centre z), scene coordinates
//   MODEL_MATRIX[0] = (a, b, c), MODEL_MATRIX[1] = (d, j, light): the column's random values (Java seeds a RandomSource
//   with the column hash: rain speed 3 + a; snow drift a, b, c, d), the rain scroll hash j (& 0xFF) and
//   (sky << 4 | block) light at max(camera y, height).
// Everything Java's WeatherEffectRenderer evaluates per frame is evaluated here per frame: the column's span
// max(camera y -/+ r, height), alpha ((1 - (d² / r²)²) * 0.5 + 0.5) * rain level from the camera position, the scroll
// at tick + partial tick.
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform float texel_w = 0.015625;   // 1 / texture width
uniform bool snow = false;
uniform float level = 1.0;          // rain level
uniform float radius = 10.0;        // 10 blocks (5 with Fast graphics)
uniform float fixed_time = -1.0;    // --raincheck: frozen (ticks & 131071) + partial tick
global uniform float mc_partial;
global uniform float mc_ticks;      // game time & 131071
global uniform sampler2D mc_lightmap;
#include "res://shaders/mc_fog.gdshaderinc"

varying vec4 v_col;    // linear light colour (fogged), alpha
varying vec2 v_uv;

vec3 to_lin(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

// org: column bottom centre (y = max(camera y - r, height)), hgt: column height (0 = not drawn), side: unit vector
// across the camera-facing quad, uo / c: u / v texture offsets (Java ColumnInstance uOffset / vOffset), alpha.
void weather_column(mat4 m, vec3 cam, out vec3 org, out float hgt, out vec2 side, out float uo, out float c, out float alpha) {
	vec3 o = m[3].xyz;
	float cy = floor(cam.y);
	float l1 = max(cy - radius, o.y);
	float i2 = max(cy + radius, o.y);
	org = vec3(o.x, l1, o.z);
	hgt = i2 - l1;
	vec2 d = o.xz - cam.xz;
	float l = max(length(d), 0.0001);
	side = vec2(-d.y, d.x) / l;
	float f3 = dot(d, d) / (radius * radius);
	alpha = clamp(((1.0 - f3 * f3) * 0.5 + 0.5) * level, 0.0, 1.0);
	float tt = fixed_time >= 0.0 ? fixed_time : mc_ticks + mc_partial;
	if (snow) {
		// Java createSnowColumnInstance: t = (ticks & 511) + partial; u = a + t 0.01 b; v = c + t d 0.001 - t / 512
		float t = mod(tt, 512.0);
		uo = m[0].x + t * 0.01 * m[0].y;
		c = m[0].z + t * m[1].x * 0.001 - t / 512.0;
	} else {
		// Java createRainColumnInstance: v = (-((ticks & 131071) + j + partial) / 32 x (3 + a)) % 32
		uo = 0.0;
		c = mod(-(tt + m[1].y) / 32.0 * (3.0 + m[0].x), 32.0);
	}
}

// The column's light through the lightmap (snow raises it: (l x 3 + 15) / 4 for block and sky), sRGB.
vec3 weather_light(mat4 m) {
	float li = floor(m[1].z + 0.5);
	float sk = floor(li / 16.0);
	float bl = li - sk * 16.0;
	if (snow) {
		sk = floor((sk * 3.0 + 15.0) / 4.0);
		bl = floor((bl * 3.0 + 15.0) / 4.0);
	}
	return clamp(textureLod(mc_lightmap, (vec2(bl, sk) + 0.5) / 16.0, 0.0).rgb, 0.0, 1.0);
}

