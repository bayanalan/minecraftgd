## InBedScreen — Java InBedChatScreen (a ChatScreen): while lying in a bed the chat input is open (Enter sends and
## keeps the screen: the player stays in bed) with a "Leave Bed" button (200 x 20 at width / 2 - 100, height - 40);
## the button and Esc wake the player up without skipping the night. The world keeps running.
extends "res://scripts/ui/chat_screen.gd"

var _btn: Control


func _ready() -> void:
	super._ready()
	_btn = UiKit.button(Res.tr_key("multiplayer.stopSleeping", "Leave Bed"), Callable(self, "_leave"), 200)
	add_child(_btn)


func _process(d: float) -> void:
	super._process(d)
	var s := UiKit.scale()
	McW.place(_btn, size.x / s / 2.0 - 100.0, size.y / s - 40.0, 200, 20)
	if world != null and not world.player.sleeping:
		world.close_screen()


## InBedChatScreen.keyPressed (Enter): the message is sent, the input cleared, the screen stays.
func _submit(t: String) -> void:
	_send(t)
	edit.text = ""
	hist_i = -1
	_refresh()
	edit.grab_focus()


func _leave() -> void:
	if world != null:
		world.entities.wake_up()


func on_escape() -> void:
	_leave()
