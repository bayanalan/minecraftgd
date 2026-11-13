// Java 26.3 fog (assets/minecraft/shaders/include/fog.glsl): the larger of a linear environmental fog over the
// spherical distance and a linear render-distance fog over the cylindrical distance (max of horizontal distance and
// height difference), mixed towards the fog colour in sRGB space like Java's gamma-space pipeline. Godot's own depth
// fog is disabled; WorldManager sets these globals every frame.
global uniform vec4 mc_fog_color;   // sRGB fog colour; a = strength (0 disables)
global uniform vec4 mc_fog_dist;    // environmental start, environmental end, render-distance start, render-distance end

float mc_linear_fog(float d, float s, float e) {
	if (d <= s) {
		return 0.0;
	}
	if (d >= e) {
		return 1.0;
	}
	return (d - s) / (e - s);
}

// rel: position relative to the camera, world axes
float mc_fog_value(vec3 rel) {
	float sph = length(rel);
	float cyl = max(length(rel.xz), abs(rel.y));
	return max(mc_linear_fog(sph, mc_fog_dist.x, mc_fog_dist.y), mc_linear_fog(cyl, mc_fog_dist.z, mc_fog_dist.w));
}

vec3 mc_apply_fog(vec3 srgb, vec3 rel) {
	return mix(srgb, mc_fog_color.rgb, mc_fog_value(rel) * mc_fog_color.a);
}
