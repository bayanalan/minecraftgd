## BeaconScreen — Java BeaconScreen layout on the installed gui/container/beacon.png (230x219): primary effect
## buttons per pyramid tier (rows at y 22/47/72, centred on x 76), secondary at level 4 (regeneration or "upgrade"
## the primary to II, centred on x 167), payment slot (136, 110), confirm (164, 107) / cancel (190, 107).
## Confirm needs a payment item (#beacon_payment_items) and a primary effect; it consumes the payment.
extends ContainerUI

var pos := Vector3i.ZERO
var pay: ItemStack = ItemStack.new()
var primary := ""
var secondary := ""


func build() -> void:
	bg_tex = UiKit.sprite("gui/container/beacon")
	bg_size = Vector2(230, 219)
	title = ""
	var d := BlockEntities.get_data(world, pos)
	primary = str(d.get("primary", ""))
	secondary = str(d.get("secondary", ""))
	add_slot(Vector2(136, 110), func(): return pay, func(s): pay = s, 0, false,
		func(s: ItemStack): return Tags.items("beacon_payment_items").has(s.name()))
	add_player_inventory(36, 137)
	extra_draw = _draw_beacon


func _levels() -> int:
	return int(BlockEntities.get_data(world, pos).get("levels", 0))


func _buttons() -> Array:
	# [rect, effect, kind] kind: "p" primary, "s" secondary, "ok", "cancel"
	var out: Array = []
	var lv := _levels()
	for tier in 3:
		var effs: Array = Beacons.TIERS[tier]
		var w := effs.size() * 22 + (effs.size() - 1) * 2
		for j in effs.size():
			out.append([Rect2(76 + j * 24 - w / 2, 22 + tier * 25, 22, 22), effs[j], "p", lv > tier])
	var sec_opts := ["regeneration"]
	if primary != "":
		sec_opts.append(primary)
	var w2 := sec_opts.size() * 22 + (sec_opts.size() - 1) * 2
	for j in sec_opts.size():
		out.append([Rect2(167 + j * 24 - w2 / 2, 47, 22, 22), sec_opts[j], "s", lv >= 4 and primary != ""])
	out.append([Rect2(164, 107, 22, 22), "", "ok", true])
	out.append([Rect2(190, 107, 22, 22), "", "cancel", true])
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := get_local_mouse_position() / UiKit.scale() - origin()
		for b in _buttons():
			if (b[0] as Rect2).has_point(mp) and b[3]:
				match str(b[2]):
					"p":
						primary = b[1]
						if secondary != "regeneration":
							secondary = ""
					"s":
						secondary = b[1]
					"ok":
						_confirm()
					"cancel":
						world.close_screen()
				Audio.play("ui.button.click", world.player.pos, "Master", 0.25)
				accept_event()
				return
	super._gui_input(event)


func _confirm() -> void:
	if pay.is_empty() or primary == "" or _levels() <= 0:
		return
	var d := BlockEntities.get_data(world, pos)
	d["primary"] = primary
	d["secondary"] = secondary if _levels() >= 4 else ""
	BlockEntities.set_data(world, pos, d)
	pay.count -= 1
	if pay.count <= 0:
		pay = ItemStack.new()
	world.close_screen()


func on_close() -> void:
	if not pay.is_empty():
		if world.player.inventory.add(pay) > 0:
			world.entities.spawn_item(world.player.eye_pos(), pay)
		pay = ItemStack.new()


func _draw_beacon(o: Vector2) -> void:
	var font := UiKit.font()
	for b in _buttons():
		var r: Rect2 = b[0]
		var sel: bool = (b[2] == "p" and b[1] == primary) or (b[2] == "s" and b[1] == secondary)
		var spr := "button_selected" if sel else ("button" if b[3] else "button_disabled")
		var t := UiKit.sprite("gui/sprites/container/beacon/" + spr)
		if t != null:
			draw_texture_rect(t, Rect2(o + r.position, r.size), false)
		else:
			draw_rect(Rect2(o + r.position, r.size), Color(0.3, 0.6, 0.3) if sel else Color(0.25, 0.25, 0.3))
		var icon: Texture2D = null
		match str(b[2]):
			"p", "s":
				icon = UiKit.sprite("mob_effect/" + str(b[1]))
			"ok":
				icon = UiKit.sprite("gui/sprites/container/beacon/confirm")
			"cancel":
				icon = UiKit.sprite("gui/sprites/container/beacon/cancel")
		if icon != null:
			draw_texture_rect(icon, Rect2(o + r.position + Vector2(2, 2), Vector2(18, 18)), false, Color(1, 1, 1, 1.0 if b[3] else 0.4))
		elif b[2] == "ok" or b[2] == "cancel":
			draw_string(font, o + r.position + Vector2(6, 15), "OK" if b[2] == "ok" else "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
	draw_string(font, o + Vector2(10, 14), "Primary Power", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.88, 0.88, 0.88))
	draw_string(font, o + Vector2(140, 14), "Secondary Power", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.88, 0.88, 0.88))
	draw_string(font, o + Vector2(10, 100), "Pyramid level %d" % _levels(), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.88, 0.88, 0.88))
