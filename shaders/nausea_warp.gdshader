// Nausea / nether portal screen warp (Java GameRenderer: the world projection gets rotate(t, axis) * scale(1 / f2, 1, 1)
// * rotate(-t, axis), axis (0, sqrt(2)/2, sqrt(2)/2) in view space). A linear map of view space maps view rays to view
// rays, so the warp is exact as a screen-space lookup: each output ray d shows the scene along M^-1 d.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float f2 = 1.0;          // Java f2 = (5 / (f1^2 + 5) - 0.04 f1)^2
uniform float ang = 0.0;         // rotation angle (radians)
uniform vec2 tan_half = vec2(1.0, 1.0);   // tan(fov / 2) horizontally / vertically

vec3 rot(vec3 v, vec3 k, float t) {
	float c = cos(t);
	float s = sin(t);
	return v * c + cross(k, v) * s + k * dot(k, v) * (1.0 - c);
}

void fragment() {
	vec2 ndc = vec2(SCREEN_UV.x * 2.0 - 1.0, 1.0 - SCREEN_UV.y * 2.0);
	vec3 d = vec3(ndc.x * tan_half.x, ndc.y * tan_half.y, -1.0);
	vec3 k = vec3(0.0, 0.70710678, 0.70710678);
	vec3 s = rot(d, k, -ang);
	s.x *= f2;
	s = rot(s, k, ang);
	float z = max(1e-4, -s.z);
	vec2 src = vec2(s.x / z / tan_half.x, s.y / z / tan_half.y);
	COLOR = vec4(texture(screen_tex, vec2(src.x * 0.5 + 0.5, 0.5 - src.y * 0.5)).rgb, 1.0);
}
