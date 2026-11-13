## ContainerScreen — chest/barrel/shulker (27), hopper (5), dispenser/dropper (9) and furnace family
## (input/fuel/output with burn + cook progress) backed by BlockEntities data (persisted with the chunk).
extends ContainerUI

var pos := Vector3i.ZERO
var kind := "chest"
var items: Array = []    # Array[ItemStack] working copy
var data: Dictionary = {}
var entity = null         # optional: container entity (chest/hopper minecart, chest boat); its data holds the items
## Large chest (Java CompoundContainer): the RIGHT half holds the top 27 slots.
var pos2 := Vector3i(0, -9999, 0)
var data2: Dictionary = {}
var self_first := true
var rows := 3


func build() -> void:
	if entity != null:
		data = entity.data
		pos = Vector3i(entity.pos.floor())
	else:
		data = BlockEntities.ensure_loot(world, pos)
	Sculk.vibrate(world, Vector3(pos) + Vector3(0.5, 0.5, 0.5), true)
	if data.is_empty() and entity == null:
		BlockEntities.on_placed(world, pos, world.state_at(pos.x, pos.y, pos.z))
		data = BlockEntities.get_data(world, pos)
	var n := BlockEntities.container_size(kind)
	var raw: Array = data.get("items", [])
	items.clear()
	for i in n:
		items.append(ItemStack.from_dict(raw[i] if i < raw.size() else {}))
	title = Res.block_display_name(kind)
	if data.has("CustomName"):
		title = str(data["CustomName"])
	if entity == null and Interaction.is_pair_chest(kind):
		var st0: int = world.state_at(pos.x, pos.y, pos.z)
		var q := Interaction.chest_partner(st0, pos)
		var ps: int = world.state_at(q.x, q.y, q.z) if q.y != -9999 else 0
		if ps > 0 and Res.blocks.st_block[ps] == Res.blocks.st_block[st0]:
			pos2 = q
			data2 = BlockEntities.ensure_loot(world, q)
			if data2.is_empty():
				BlockEntities.on_placed(world, q, ps)
				data2 = BlockEntities.get_data(world, q)
			self_first = Res.blocks.get_prop(st0, "type") == "right"
			var raw2: Array = data2.get("items", [])
			var other: Array = []
			for i in 27:
				other.append(ItemStack.from_dict(raw2[i] if i < raw2.size() else {}))
			items = (items + other) if self_first else (other + items)
			rows = 6
			title = Res.tr_key("container.chestDouble", "Large Chest")
	if kind == "brewing_stand":
		bg_tex = UiKit.sprite("gui/container/brewing_stand")
		bg_size = Vector2(176, 166)
		var bottle := func(st): return Potions.is_bottle(st) or st.name() == "glass_bottle"
		add_slot(Vector2(56, 51), _g.bind(0), _s.bind(0), 0, false, bottle, "potion")
		add_slot(Vector2(79, 58), _g.bind(1), _s.bind(1), 0, false, bottle, "potion")
		add_slot(Vector2(102, 51), _g.bind(2), _s.bind(2), 0, false, bottle, "potion")
		add_slot(Vector2(79, 17), _g.bind(3), _s.bind(3), 0)
		add_slot(Vector2(17, 17), _g.bind(4), _s.bind(4), 0, false, func(st): return st.name() == "blaze_powder", "brewing_fuel")
		add_player_inventory(8, 84)
		extra_draw = func(o: Vector2):
			var d2 := BlockEntities.get_data(world, pos)
			var bt := int(d2.get("brew", 0))
			if bt > 0:
				draw_rect(Rect2(o + Vector2(97, 16), Vector2(9, 28.0 * (1.0 - bt / 400.0))), Color(1, 1, 1, 0.6))
			draw_rect(Rect2(o + Vector2(60, 44), Vector2(18.0 * int(d2.get("fuel", 0)) / 20.0, 4)), Color(0.85, 0.55, 0.1))
	elif kind in ["furnace", "blast_furnace", "smoker"]:
		bg_tex = UiKit.sprite("gui/container/" + kind)
		bg_size = Vector2(176, 166)
		add_slot(Vector2(56, 17), _g.bind(0), _s.bind(0), 0)
		add_slot(Vector2(56, 53), _g.bind(1), _s.bind(1), 0, false, func(st): return Crafting.fuel_time(st.item) > 0)
		add_slot(Vector2(116, 35), _g.bind(2), _s.bind(2), 0, false, func(_st): return false)
		add_player_inventory(8, 84)
		extra_draw = _draw_furnace
	elif kind == "hopper":
		bg_tex = UiKit.sprite("gui/container/hopper")
		bg_size = Vector2(176, 133)
		for i in 5:
			add_slot(Vector2(44 + i * 18, 20), _g.bind(i), _s.bind(i), 0)
		add_player_inventory(8, 51)
	elif kind in ["dispenser", "dropper"]:
		bg_tex = UiKit.sprite("gui/container/dispenser")
		bg_size = Vector2(176, 166)
		for r in 3:
			for c in 3:
				add_slot(Vector2(62 + c * 18, 17 + r * 18), _g.bind(r * 3 + c), _s.bind(r * 3 + c), 0)
		add_player_inventory(8, 84)
	else:
		bg_tex = UiKit.sprite("gui/container/shulker_box" if kind.ends_with("shulker_box") else "gui/container/generic_54")
		bg_size = Vector2(176, 114 + rows * 18)
		if not kind.ends_with("shulker_box"):
			bg_region = Rect2()
		for r in rows:
			for c in 9:
				add_slot(Vector2(8 + c * 18, 18 + r * 18), _g.bind(r * 9 + c), _s.bind(r * 9 + c), 0, false, (func(st): return not st.name().ends_with("shulker_box")) if kind.ends_with("shulker_box") else Callable())
		add_player_inventory(8, 103 + (rows - 4) * 18)
	Audio.play("block.chest.open" if kind.contains("chest") else ("block.barrel.open" if kind == "barrel" else "block.chest.open"), Vector3(pos), "Blocks", 0.5)


func draw_background(o: Vector2) -> void:
	if not kind in ["furnace", "blast_furnace", "smoker", "hopper", "dispenser", "dropper", "brewing_stand"] and not kind.ends_with("shulker_box") and bg_tex != null:
		# generic_54: top part (3 rows) + bottom player-inventory part
		draw_texture_rect_region(bg_tex, Rect2(o, Vector2(176, rows * 18 + 17)), Rect2(0, 0, 176, rows * 18 + 17))
		draw_texture_rect_region(bg_tex, Rect2(o + Vector2(0, rows * 18 + 17), Vector2(176, 96)), Rect2(0, 126, 176, 96))
		return
	super.draw_background(o)


func _g(i: int) -> ItemStack:
	return items[i]


func _s(st: ItemStack, i: int) -> void:
	items[i] = st


func _draw_furnace(o: Vector2) -> void:
	data = BlockEntities.get_data(world, pos)
	var raw: Array = data.get("items", [])
	for i in mini(raw.size(), items.size()):
		var fresh := ItemStack.from_dict(raw[i])
		if fresh.to_dict() != (items[i] as ItemStack).to_dict():
			items[i] = fresh
	var burn := float(data.get("burn", 0))
	var bmax := maxf(1.0, float(data.get("burn_max", 1)))
	var cook := float(data.get("cook", 0))
	var lit := UiKit.sprite("gui/sprites/container/furnace/lit_progress")
	var arrow := UiKit.sprite("gui/sprites/container/furnace/burn_progress")
	if burn > 0 and lit != null:
		var h := int(ceil(14.0 * burn / bmax))
		draw_texture_rect_region(lit, Rect2(o + Vector2(56, 36 + 14 - h), Vector2(14, h)), Rect2(0, 14 - h, 14, h))
	if cook > 0 and arrow != null:
		var w := int(24.0 * cook / 200.0)
		draw_texture_rect_region(arrow, Rect2(o + Vector2(79, 34), Vector2(w, 16)), Rect2(0, 0, w, 16))


func on_changed() -> void:
	_commit()


func _commit() -> void:
	var raw: Array = []
	for it in items:
		raw.append((it as ItemStack).to_dict())
	if pos2.y != -9999:
		var top := raw.slice(0, 27)
		var bottom := raw.slice(27, 54)
		data["items"] = top if self_first else bottom
		data2["items"] = bottom if self_first else top
		BlockEntities.set_data(world, pos, data)
		BlockEntities.set_data(world, pos2, data2)
		return
	data["items"] = raw
	if entity == null:
		BlockEntities.set_data(world, pos, data)


func on_close() -> void:
	_commit()
	Audio.play("block.chest.close", Vector3(pos), "Blocks", 0.5)
	super.on_close()
