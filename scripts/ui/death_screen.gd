## DeathScreen — Java DeathScreen (`game.death`, `game.hardcore_death`): gradient 0x60500000 -> 0xA0803030 over the
## world, title at 2x scale (y 30 in the scaled space), the death message (death.* translations) at y 85 and
## "Score: <yellow n>" at y 100, centred in white; Respawn (Spectate World in Hardcore) at (C-100, h/4 + 72) and Title
## Screen at (C-100, h/4 + 96), both inactive for the first 20 ticks like Java.
extends Control

var world
var _title: Label
var _cause: Label
var _score: RichTextLabel
var _b1: Button
var _b2: Button
var _t0 := 0

## Recraft damage source -> Java death message key (%1$s player, %2$s killer).
const MESSAGES := {
	"fall": "death.fell.accident.generic", "lava": "death.attack.lava", "drown": "death.attack.drown",
	"starve": "death.attack.starve", "on_fire": "death.attack.onFire", "in_fire": "death.attack.inFire",
	"out_of_world": "death.attack.outOfWorld", "magic": "death.attack.magic", "wither": "death.attack.wither",
	"explosion": "death.attack.explosion", "lightning_bolt": "death.attack.lightningBolt", "in_wall": "death.attack.inWall",
	"fly_into_wall": "death.attack.flyIntoWall", "fireworks": "death.attack.fireworks", "cactus": "death.attack.cactus",
	"freeze": "death.attack.freeze", "sonic_boom": "death.attack.sonic_boom", "mob": "death.attack.mob",
	"attack": "death.attack.mob", "arrow": "death.attack.arrow", "fireball": "death.attack.fireball",
}


## Java CombatTracker.getDeathMessage equivalent for the recorded source / attacker.
static func death_message(player_name: String, source: String, attacker_id: String) -> String:
	var key: String = MESSAGES.get(source, "death.attack.generic")
	var killer := Res.tr_key("entity.minecraft." + attacker_id, attacker_id.capitalize()) if attacker_id != "" else ""
	if killer != "" and source in ["explosion", "magic", "on_fire", "in_fire", "lava", "drown", "fall"]:
		var k2 := key + ".player"
		if Res.lang.has(k2):
			key = k2
	if killer == "" and source in ["mob", "attack", "arrow", "fireball", "sonic_boom"]:
		key = "death.attack.generic"
	return Res.tr_fmt(key, [player_name, killer], "%1$s died")


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	var p = world.player
	_title = McW.text(Res.tr_key("deathScreen.title.hardcore" if world.hardcore else "deathScreen.title", "Game Over!" if world.hardcore else "You Died!"), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_font_size_override("font_size", 16 * UiKit.scale())
	add_child(_title)
	_cause = McW.text(death_message(str(Settings.get_v("player_name")), str(p.last_damage_source), str(p.last_attacker_id)), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_cause)
	# "Score: %s" with the number in yellow (ChatFormatting.YELLOW)
	var sc := Res.tr_key("deathScreen.score.value", "Score: %s")
	var parts := sc.split("%s")
	_score = RichTextLabel.new()
	_score.bbcode_enabled = true
	_score.fit_content = true
	_score.scroll_active = false
	_score.autowrap_mode = TextServer.AUTOWRAP_OFF
	_score.add_theme_font_override("normal_font", UiKit.font())
	_score.add_theme_font_size_override("normal_font_size", 8 * UiKit.scale())
	_score.add_theme_color_override("font_shadow_color", Color(0.25, 0.25, 0.25) if Settings.get_v("text_shadow") else Color(0, 0, 0, 0))
	_score.add_theme_constant_override("shadow_offset_x", UiKit.scale())
	_score.add_theme_constant_override("shadow_offset_y", UiKit.scale())
	_score.text = "[center]%s[color=#FFFF55]%d[/color]%s[/center]" % [parts[0], int(p.xp_total), parts[1] if parts.size() > 1 else ""]
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_score)
	_b1 = UiKit.button(Res.tr_key("deathScreen.spectate" if world.hardcore else "deathScreen.respawn", "Spectate World" if world.hardcore else "Respawn"), func():
		_b1.disabled = true
		world.respawn()
		world.close_screen(), 200)
	_b2 = UiKit.button(Res.tr_key("deathScreen.titleScreen", "Title Screen"), func(): world.app.leave_world(), 200)
	add_child(_b1)
	add_child(_b2)
	_b1.disabled = true
	_b2.disabled = true
	_t0 = Time.get_ticks_msec()
	_layout()
	resized.connect(_layout)
	world.paused = false


func _process(_d: float) -> void:
	# Java: buttons become active after 20 ticks (1 s)
	if _b1.disabled and _b2.disabled and Time.get_ticks_msec() - _t0 >= 1000:
		_b1.disabled = false
		_b2.disabled = false
		set_process(false)


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(_title, 0, 60 - 2, gw, 18)
	McW.place(_cause, 0, 85 - 1, gw, 9)
	_score.position = Vector2(0, 100 - 1) * s
	_score.size = Vector2(gw, 12) * s
	McW.place(_b1, c - 100, floorf(gh / 4.0) + 72, 200, 20)
	McW.place(_b2, c - 100, floorf(gh / 4.0) + 96, 200, 20)
	queue_redraw()


func _draw() -> void:
	# Java DeathScreen.renderDeathBackground: fillGradient(0x60500000 -> 0xA0803030)
	var top := Color8(0x50, 0x00, 0x00, 0x60)
	var bot := Color8(0x80, 0x30, 0x30, 0xA0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]), PackedColorArray([top, top, bot, bot]))


func closes_on_inventory_key() -> bool:
	return false
