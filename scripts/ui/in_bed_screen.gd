## InBedScreen — Java InBedChatScreen: while lying in a bed, a "Leave Bed" button (200 x 20 at width / 2 - 100,
## height - 40); it and Esc wake the player up without skipping the night. The world keeps running.
extends Control

var world
var _btn: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn = UiKit.button(Res.tr_key("multiplayer.stopSleeping", "Leave Bed"), Callable(self, "_leave"), 200)
	add_child(_btn)


func _process(_d: float) -> void:
	var s := UiKit.scale()
	McW.place(_btn, size.x / s / 2.0 - 100.0, size.y / s - 40.0, 200, 20)
	if world != null and not world.player.sleeping:
		world.close_screen()


func _leave() -> void:
	if world != null:
		world.entities.wake_up()


func on_escape() -> void:
	_leave()
