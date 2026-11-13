class_name ShaderGlobals
extends RefCounted
## Global shader parameters set by the game, mirrored here so code that needs their values (the RenderingDevice terrain
## renderer) does not call RenderingServer.global_shader_parameter_get (editor-only, slow).

static var values := {"sky_light_factor": 1.0, "gamma_boost": 0.5, "night_vision": 0.0, "ambient_light": 0.0,
	"mc_fog_color": Vector4(0.75, 0.85, 1.0, 1.0), "mc_fog_dist": Vector4(1e6, 1e6, 230.0, 256.0)}


static func put(name: StringName, v: float) -> void:
	if values.get(name) == v:
		return   # unchanged: global_shader_parameter_set re-uploads the globals buffer
	values[name] = v
	RenderingServer.global_shader_parameter_set(name, v)


## Non-float globals (vec4 fog colour / distances); skipped when unchanged.
static func put_v(name: StringName, v) -> void:
	if values.get(name) == v:
		return
	values[name] = v
	RenderingServer.global_shader_parameter_set(name, v)
