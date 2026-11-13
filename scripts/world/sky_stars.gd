class_name SkyStars
extends MeshInstance3D
## Java SkyRenderer star field: RandomSource.create(10842) (legacy LCG), 1500 candidates, kept when
## 0.01 < |v|^2 < 1, each a square of half size 0.15 + rand * 0.1 facing the centre at distance 100, rotated by a
## random angle (Matrix3f.rotateTowards(-dir, +Y).rotateZ(-angle)). Rotated with the star angle (YP(-90), XP(angle)),
## centred on the camera, drawn additively with colour (b, b, b, b) only where nothing else was drawn.

var mat: ShaderMaterial


## The star quads (4 vertices each, around the origin at distance 100); shared with SkyRD.
static func star_quads() -> PackedVector3Array:
	var rnd := RandomSources.LegacyRandom.new(10842)
	var verts := PackedVector3Array()
	for i in 1500:
		var f := rnd.next_float() * 2.0 - 1.0
		var g := rnd.next_float() * 2.0 - 1.0
		var h := rnd.next_float() * 2.0 - 1.0
		var j := 0.15 + rnd.next_float() * 0.1
		var k := f * f + g * g + h * h
		if k <= 0.010000001 or k >= 1.0:
			continue
		var c := Vector3(f, g, h).normalized() * 100.0
		var l := rnd.next_double() * PI * 2.0
		# JOML rotateTowards(dir, up): columns X = normalize(up x Z), Y = Z x X, Z = normalize(dir); then rotateZ(-l)
		var z := (-c).normalized()
		var x := Vector3.UP.cross(z).normalized()
		var y := z.cross(x)
		var rot := Basis(x, y, z) * Basis(Vector3.BACK, -l)
		for p in [Vector3(j, -j, 0), Vector3(j, j, 0), Vector3(-j, j, 0), Vector3(-j, -j, 0)]:
			verts.append(rot * p + c)
	return verts


func _ready() -> void:
	var verts := star_quads()
	var idx := PackedInt32Array()
	for b0 in range(0, verts.size(), 4):
		idx.append_array([b0, b0 + 1, b0 + 2, b0, b0 + 2, b0 + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh = m
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/stars.gdshader")
	mat.render_priority = -100   # first of the transparent objects (behind everything)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	top_level = true


## Per frame: brightness (timeline star brightness * (1 - rain)) and orientation around the camera.
func update(cam_pos: Vector3, star_angle: float, brightness: float) -> void:
	visible = brightness > 0.0
	if not visible:
		return
	mat.set_shader_parameter("brightness", brightness)
	global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)) * Basis(Vector3.RIGHT, star_angle), cam_pos)
