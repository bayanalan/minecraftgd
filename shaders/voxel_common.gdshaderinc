// Shared voxel terrain shading: texture-array sampling, overlay+tint, Minecraft-like lightmap curve.
// CUSTOM0 = (base layer, overlay layer or -1, sky light 0..1, block light 0..1); COLOR = (tint rgb, ao*shade).
// Sampled WITHOUT source_color: all Minecraft-style colour math (tint, lightmap, face shade, AO) happens in
// sRGB space like Java, then the result is converted to linear once for the Forward+ pipeline.
uniform sampler2DArray block_tex : filter_nearest_mipmap, repeat_enable;
global uniform float sky_light_factor;
global uniform float gamma_boost;
global uniform float night_vision;
global uniform float ambient_light;   // dimension ambient_light (Nether 0.1, End 0.25)

varying vec4 v_light;
varying vec4 v_color;
varying vec3 v_rel;   // position relative to the camera (world axes) for the vanilla fog
varying vec3 v_lm;    // lightmap colour of the vertex (Java terrain.vsh: Color * sample_lightmap(UV2))
global uniform sampler2D mc_lightmap;   // Java 26.3 lightmap texture (WorldManager._update_lightmap)

#include "res://shaders/viewmodel.gdshaderinc"
#include "res://shaders/mc_fog.gdshaderinc"

void vertex() {
	v_light = CUSTOM0;
	v_color = COLOR;
	v_rel = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD;
	v_lm = textureLod(mc_lightmap, (vec2(CUSTOM0.w, CUSTOM0.z) * 15.0 + 0.5) / 16.0, 0.0).rgb;
	VM_POSITION
}

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

float mc_curve(float x) {
	float g = x / (4.0 - 3.0 * x);
	return g + ambient_light * (1.0 - g);   // Java getBrightness: lerp(ambientLight, g, 1)
}

vec3 lightmap(float sky, float blk) {
	float s = mc_curve(sky) * sky_light_factor;
	float b = mc_curve(blk);
	vec3 l = vec3(s) + vec3(b, b * 0.92, b * 0.80) * (1.0 - s * 0.35);
	l = clamp(l, 0.0, 1.0);
	vec3 inv = vec3(1.0) - l;
	vec3 bright = vec3(1.0) - inv * inv * inv * inv;
	l = mix(l, bright, gamma_boost);
	l = max(l, vec3(night_vision));
	return l * 0.955 + 0.045;
}

vec4 voxel_color(vec2 uv) {
	vec4 base = texture(block_tex, vec3(uv, v_light.x));
	vec3 col = base.rgb;
	if (v_light.y >= 0.0) {
		vec4 ov = texture(block_tex, vec3(uv, v_light.y));
		col = mix(col, ov.rgb * v_color.rgb, ov.a);
	} else {
		col *= v_color.rgb;
	}
	col *= v_lm * v_color.a;
	col = mc_apply_fog(clamp(col, 0.0, 1.0), v_rel);
	return vec4(to_linear(col), base.a);
}
