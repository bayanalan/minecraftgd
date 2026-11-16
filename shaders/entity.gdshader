// Entity shading: texture * vertex colour * Java entity diffuse lighting * lightmap texel of the per-instance light.
// lit_normals (box-UV model meshes): Java minecraft_mix_light - min(1, (max(0, L0.n) + max(0, L1.n)) * 0.6 + 0.4) with
// the LEVEL lights (0.2, 1, -0.7) / (-0.2, 1, 0.7) normalised in world space (Nether: second light (-0.2, -1, 0.7)),
// in view space for the first-person hand (Java renders it with an identity view: its lighting never turns), and the
// ITEMS_3D lights for GUI icons (gui_items; their SubViewport camera is unrotated). Other meshes bake a shade in COLOR.
// ENTITY_TRANSLUCENT (variant built by EntityRenderer.translucent_shader): flat items whose sprite has translucent pixels
// (stained glass panes, bottles) blend like Java's translucent item sheet (item_entity_translucent_cull).
shader_type spatial;
#ifdef ENTITY_TRANSLUCENT
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque;
#else
render_mode unshaded, cull_disabled, depth_draw_opaque;
#endif

uniform sampler2D tex : filter_nearest;
uniform bool has_tex = false;
global uniform float sky_light_factor;
global uniform float ambient_light;
instance uniform vec2 light = vec2(1.0, 0.0);
instance uniform float hurt = 0.0;
instance uniform float gui_items = 0.0;
uniform bool lit_normals = false;
global uniform float mc_nether_light;
varying vec3 v_n;
#include "res://shaders/viewmodel.gdshaderinc"
#include "res://shaders/mc_fog.gdshaderinc"
varying vec3 v_rel;
global uniform sampler2D mc_lightmap;

void vertex() {
	v_rel = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD;
	v_n = MODEL_NORMAL_MATRIX * NORMAL;
#ifdef VIEWMODEL
	v_n = mat3(VIEW_MATRIX) * v_n;
#endif
	VM_POSITION
}

float mc_curve(float x) {
	float g = x / (4.0 - 3.0 * x);
	return g + ambient_light * (1.0 - g);
}

void fragment() {
	vec4 c = has_tex ? texture(tex, UV) : vec4(0.8, 0.6, 0.5, 1.0);
	if (c.a < 0.1) {
		discard;
	}
	// Java: vertex colour * lightmap texel of the entity's (block, sky) light
	vec3 l = texture(mc_lightmap, (vec2(light.y, light.x) * 15.0 + 0.5) / 16.0).rgb;
	vec3 col = c.rgb * COLOR.rgb * l;
	if (lit_normals) {
		vec3 n = normalize(v_n);
		vec3 l0 = vec3(0.2, 1.0, -0.7) * 0.808452;
		vec3 l1 = vec3(-0.2, mc_nether_light > 0.5 ? -1.0 : 1.0, 0.7) * 0.808452;
		if (gui_items > 0.5) {
			l0 = vec3(-0.933439, 0.262695, -0.2443);
			l1 = vec3(-0.103571, 0.976607, 0.188446);
		}
		col *= min(1.0, (max(0.0, dot(l0, n)) + max(0.0, dot(l1, n))) * 0.6 + 0.4);
	}
	col = mix(col, vec3(1.0, 0.2, 0.2), hurt * 0.5);
	col = mc_apply_fog(clamp(col, 0.0, 1.0), v_rel);
	ALBEDO = mix(pow((col + 0.055) / 1.055, vec3(2.4)), col / 12.92, lessThan(col, vec3(0.04045)));
#ifdef ENTITY_TRANSLUCENT
	ALPHA = 1.0 - pow(1.0 - c.a, 1.5);   // sRGB-like blending in a linear target (as voxel_translucent)
#endif
}
