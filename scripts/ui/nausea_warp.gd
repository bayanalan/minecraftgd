## NauseaWarp — the world wobble of Nausea and nether portals (Java LocalPlayer.spinningEffectIntensity, kept in
## WorldManager.portal_spin): GameRenderer's projection warp as a screen-space pass (shaders/nausea_warp.gdshader)
## with intensity f1 = spin x distortion^2, f2 = (5 / (f1^2 + 5) - 0.04 f1)^2 and a rotation of 7 degrees per tick
## (Nausea) / 20 (portal); with Distortion Effects below 100 % and Nausea, Gui.renderConfusionOverlay draws
## misc/nausea.png additively in (0.2, 0.4, 0.2) x i, scaled 2 -> 1 about the centre, i = spin x (1 - distortion).
## Only drawn while the spin is above 0 (the screen copy costs nothing otherwise). Under the HUD (layer 4).
class_name NauseaWarp
extends CanvasLayer

var world
var _rect: ColorRect
var _mat: ShaderMaterial
var _ovl: Control
var _ovl_i := 0.0
var spin := 0.0       # Java spinningEffectIntensity from Nausea: + 1/150 per tick while it does not end within 60 ticks,
var spin_old := 0.0   # - 0.05 per tick otherwise (the portal's own intensity is WorldManager.portal_spin)
var _tick := -1


func _init(w) -> void:
	world = w
	layer = 4


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/nausea_warp.gdshader")
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	_ovl = Control.new()
	_ovl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ovl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ovl.material = cm
	_ovl.visible = false
	_ovl.draw.connect(_draw_overlay)
	add_child(_ovl)


func _process(_delta: float) -> void:
	if world == null or world.player == null or world.camera == null:
		return
	var gt: int = world.game_time
	var nausea: bool = world.player.effects.has("nausea")
	if gt != _tick:
		var steps := clampi(gt - _tick, 1, 40) if _tick >= 0 else 1
		_tick = gt
		var on := nausea and int((world.player.effects["nausea"] as Dictionary).get("ticks", 0)) > 60
		for i in steps:
			spin_old = spin
			spin = minf(1.0, spin + 1.0 / 150.0) if on else maxf(0.0, spin - 0.05)
	var a := clampf(float(world.tick_accum) / 0.05, 0.0, 1.0)
	var ns := lerpf(spin_old, spin, a)
	var ps := lerpf(float(world.portal_spin_old), float(world.portal_spin), a)
	var s := maxf(ns, ps)
	var dist := float(Settings.get_v("distortion"))
	var f1 := s * dist * dist
	_rect.visible = f1 > 0.0
	if f1 > 0.0:
		var f2 := 5.0 / (f1 * f1 + 5.0) - f1 * 0.04
		f2 *= f2
		var cam: Camera3D = world.camera
		var vp := get_viewport().get_visible_rect().size
		var ty := tan(deg_to_rad(cam.fov) * 0.5)
		_mat.set_shader_parameter("f2", f2)
		_mat.set_shader_parameter("ang", (float(gt) + a) * (7.0 if nausea else 20.0) * PI / 180.0)
		_mat.set_shader_parameter("tan_half", Vector2(ty * vp.x / maxf(1.0, vp.y), ty))
	var oi := ns * (1.0 - dist) if nausea and dist < 1.0 else 0.0
	if oi > 0.0 or _ovl.visible:
		_ovl_i = oi
		_ovl.visible = oi > 0.0
		_ovl.queue_redraw()


func _draw_overlay() -> void:
	if _ovl_i <= 0.0:
		return
	var tex := UiKit.sprite("misc/nausea")
	if tex == null:
		return
	var sz := _ovl.size
	var f := lerpf(2.0, 1.0, _ovl_i)
	var rsz := sz * f
	_ovl.draw_texture_rect(tex, Rect2((sz - rsz) * 0.5, rsz), false, Color(0.2 * _ovl_i, 0.4 * _ovl_i, 0.2 * _ovl_i, 1.0))
