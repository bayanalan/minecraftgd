class_name FpsCounter
extends CanvasLayer
## On-screen frame-rate readout (Video settings "FPS Counter"): "fps" shows FPS averaged over 0.25 s; "fps_lows" adds
## the 1% and 0.1% lows over the last 5 seconds (ring buffer of frame times, sorted 4x per second: constant cost).

const WINDOW_US := 5000000
var label: Label
var mode := "off"
var _times := PackedFloat32Array()   # frame times (ms), ring buffer
var _stamps := PackedInt64Array()    # frame end times (usec)
var _head := 0
var _count := 0
var _acc_n := 0
var _acc_ms := 0.0
var _last_upd := 0
var _last := 0


func _ready() -> void:
	layer = 120
	label = Label.new()
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	_times.resize(8192)
	_stamps.resize(8192)
	set_mode(mode)


func set_mode(m: String) -> void:
	mode = m
	visible = m != "off"
	set_process(m != "off")
	_count = 0
	_head = 0
	_last = 0
	if label != null:
		label.text = "FPS --"


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last == 0:
		_last = now
		return
	var ms := (now - _last) / 1000.0
	_last = now
	_times[_head] = ms
	_stamps[_head] = now
	_head = (_head + 1) & 8191
	_count = mini(_count + 1, 8192)
	_acc_n += 1
	_acc_ms += ms
	if now - _last_upd < 250000:
		return
	_last_upd = now
	var fps := roundi(1000.0 * _acc_n / maxf(_acc_ms, 0.001))
	_acc_n = 0
	_acc_ms = 0.0
	if mode != "fps_lows":
		label.text = "FPS %d" % fps
		return
	var win := PackedFloat32Array()
	for i in _count:
		var k := (_head - 1 - i) & 8191
		if now - _stamps[k] > WINDOW_US:
			break
		win.append(_times[k])
	win.sort()
	var n := win.size()
	label.text = "FPS %d     1%% low %d     0.1%% low %d" % [fps, roundi(_low(win, maxi(1, n / 100))), roundi(_low(win, maxi(1, n / 1000)))]


static func _low(sorted: PackedFloat32Array, k: int) -> float:
	var n := sorted.size()
	if n == 0:
		return 0.0
	var tot := 0.0
	for i in mini(k, n):
		tot += sorted[n - 1 - i]
	return 1000.0 * mini(k, n) / maxf(tot, 0.001)
