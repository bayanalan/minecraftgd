## PanoramaBg — Java PanoramaRenderer + CubeMap: the six gui/title/background/panorama_N images on a cube around a
## camera (FOV 85, pitch 10 deg, yaw 2 deg/s x Panorama Scroll Speed) under panorama_overlay. One instance lives
## behind every out-of-game screen (vanilla's single TitleScreen panorama keeps turning across screens); other
## screens blur it through UiKit.background. Placeholder mode: a dark vertical gradient.
class_name PanoramaBg
extends Control

var _cam: Camera3D
var _root3d: Node3D
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root3d = Node3D.new()
	add_child(_root3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type sky;\nuniform samplerCube pano : source_color, filter_linear;\nuniform bool has_pano = false;\nvoid sky() { COLOR = has_pano ? texture(pano, EYEDIR).rgb : mix(vec3(0.05,0.07,0.12), vec3(0.2,0.3,0.5), EYEDIR.y * 0.5 + 0.5); }"
	mat.shader = sh
	var imgs: Array[Image] = []
	if Res.mode == "vanilla":
		# Java panorama order 0 front, 1 right, 2 back, 3 left, 4 up, 5 down -> Godot cube order +X,-X,+Y,-Y,+Z,-Z
		for i in [1, 3, 4, 5, 2, 0]:
			var im := Res.load_image("gui/title/background/panorama_%d" % i)
			if im == null:
				imgs.clear()
				break
			im.convert(Image.FORMAT_RGBA8)
			# the images are what the viewer sees in each direction; cubemap faces use the GL convention
			# (mirrored from inside): sides + top flipped horizontally, bottom vertically
			if i == 5:
				im.flip_y()
			else:
				im.flip_x()
			imgs.append(im)
	if imgs.size() == 6:
		var cm := Cubemap.new()
		cm.create_from_images(imgs)
		mat.set_shader_parameter("pano", cm)
		mat.set_shader_parameter("has_pano", true)
	sky.sky_material = mat
	env.sky = sky
	var we := WorldEnvironment.new()
	we.environment = env
	_root3d.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 85
	_cam.near = 0.05
	_cam.far = 10.0
	_root3d.add_child(_cam)
	_cam.make_current()
	var ov: Texture2D = UiKit.sprite("gui/title/background/panorama_overlay") if Res.mode == "vanilla" else null
	if ov != null:
		var tr := TextureRect.new()
		tr.texture = ov
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)


func _process(delta: float) -> void:
	_t += delta
	if _cam:
		_cam.rotation = Vector3(deg_to_rad(-10.0), -deg_to_rad(fmod(_t * 2.0 * float(Settings.get_v("panorama_speed")), 360.0)), 0)
