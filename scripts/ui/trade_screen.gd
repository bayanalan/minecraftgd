## TradeScreen — merchant UI on the user's gui/container/villager.png (276x166): offer list on the left; clicking
## an offer the player can pay for performs the trade into the cursor (shift-click: into the inventory).
extends ContainerUI

var villager   # EntityManager.Ent


func build() -> void:
	bg_tex = UiKit.sprite("gui/container/villager")
	bg_size = Vector2(276, 166)
	var prof := str(villager.data.get("prof", "villager"))
	title = (prof.capitalize() + " - " + Trading.LEVEL_NAMES[clampi(int(villager.data.get("level", 1)) - 1, 0, 4)]) if prof != "wandering_trader" else "Wandering Trader"
	add_player_inventory(108, 84)
	extra_draw = _draw_offers


func _offer_rect(i: int) -> Rect2:
	return Rect2(Vector2(5, 18 + i * 20), Vector2(88, 20))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := get_local_mouse_position() / UiKit.scale() - origin()
		var offers: Array = villager.data.get("offers", [])
		for i in mini(offers.size(), 7):
			if _offer_rect(i).has_point(mp):
				_trade(offers[i], Input.is_key_pressed(KEY_SHIFT))
				accept_event()
				return
	super._gui_input(event)


func _trade(o: Dictionary, to_inv: bool) -> void:
	var inv: Inventory = world.player.inventory
	if not Trading.can_pay(inv, o):
		Audio.play("entity.villager.no", villager.pos, "Neutral")
		return
	if not to_inv and not inv.cursor.is_empty():
		return
	var out := Trading.pay(inv, o)
	if villager.remote:
		Net.forward("trade", [villager.uid, (villager.data.get("offers", []) as Array).find(o)])
	elif Trading.on_trade(villager, o):
		Audio.play("entity.villager.celebrate", villager.pos, "Neutral")
		for i in 6:
			Particles.emit("happy_villager", villager.pos + Vector3(randf_range(-0.5, 0.5), 1.8 + randf(), randf_range(-0.5, 0.5)))
	if to_inv:
		if inv.add(out) > 0:
			world.entities.spawn_item(world.player.eye_pos(), out)
	else:
		inv.cursor = out
	world.player.add_xp(int(o.get("xp", 1)))
	Audio.play("entity.villager.yes", villager.pos, "Neutral")
	inv.changed.emit()


func _draw_offers(o: Vector2) -> void:
	var font := UiKit.font()
	var inv: Inventory = world.player.inventory
	var offers: Array = villager.data.get("offers", [])
	for i in mini(offers.size(), 7):
		var r := _offer_rect(i)
		var of: Dictionary = offers[i]
		var ok := Trading.can_pay(inv, of)
		draw_rect(Rect2(o + r.position, r.size), Color(0.62, 0.62, 0.62) if ok else Color(0.45, 0.4, 0.4))
		draw_rect(Rect2(o + r.position, r.size), Color(0.25, 0.25, 0.25), false, 1.0)
		var x := 2.0
		for c in [of["a"], of["b"]]:
			if c.is_empty():
				continue
			_draw_stack(ItemStack.named(c[0], int(c[1])), o + r.position + Vector2(x, 2), font)
			x += 18.0
		draw_string(font, o + r.position + Vector2(42, 13), ">" if int(of["uses"]) < int(of["max"]) else "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE if ok else Color(1, 0.4, 0.4))
		_draw_stack(ItemStack.named(of["out"][0], int(of["out"][1])), o + r.position + Vector2(62, 2), font)
