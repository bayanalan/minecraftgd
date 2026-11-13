## InventoryScreen — survival inventory (armor, offhand, 2x2 crafting with live recipe matching) or, in
## Creative, a searchable catalogue of every registered item (click = take a full stack, plus own hotbar).
extends ContainerUI

var grid: Array = []       # 4 ItemStacks (2x2), owned by player inventory slots 41..44
var result: ItemStack = ItemStack.new()
var search: LineEdit
var catalogue: Array = []
var scroll := 0
var creative := false
var _pv_cont: SubViewportContainer   # player preview (Java InventoryScreen.renderEntityInInventoryFollowsMouse)
var _pv_rig: Node3D


func build() -> void:
	var inv: Inventory = world.player.inventory
	creative = world.player.is_creative()
	if creative:
		_build_creative()
		return
	bg_tex = UiKit.sprite("gui/container/inventory")
	bg_size = Vector2(176, 166)
	# Java InventoryScreen.renderLabels: only the "Crafting" title at (97, 8); no player-inventory label
	title = Res.tr_key("container.crafting", "Crafting")
	title_pos = Vector2(97, 8)
	inv_label = false
	for i in 4:
		add_slot(Vector2(8, 8 + i * 18), inv.get_slot.bind(Inventory.ARMOR0 + 3 - i), inv.setter(Inventory.ARMOR0 + 3 - i), 3, false, _armor_filter.bind(3 - i), ["helmet", "chestplate", "leggings", "boots"][i])
	add_slot(Vector2(77, 62), inv.get_slot.bind(Inventory.OFFHAND), inv.setter(Inventory.OFFHAND), 3, false, Callable(), "shield")
	for r in 2:
		for c in 2:
			var i := Inventory.CRAFT0 + r * 2 + c
			add_slot(Vector2(98 + c * 18, 18 + r * 18), inv.get_slot.bind(i), inv.setter(i), 0)
	add_slot(Vector2(154, 28), func(): return result, func(_s): pass, 0, true)
	add_player_inventory(8, 84)
	rb_gw = 2
	rb_gh = 2
	rb_get = func(i: int) -> ItemStack: return inv.get_slot(Inventory.CRAFT0 + i)
	rb_set = func(i: int, s: ItemStack) -> void: inv.set_slot(Inventory.CRAFT0 + i, s)
	rb_btn = Vector2(104, 61)
	on_changed()
	_build_preview()


func _build_preview() -> void:
	InventoryPreview.attach(self)   # shared, pre-warmed SubViewport (InventoryPreview)
	_pv_cont = InventoryPreview.cont
	_pv_rig = InventoryPreview.rig
	ArmorRender.apply(_pv_rig, ArmorRender.slots_of_inventory(world.player.inventory))


func _exit_tree() -> void:
	if _pv_cont != null and _pv_cont.get_parent() == self:
		InventoryPreview.detach()   # kept for the next opening (not freed with this screen)


func _update_preview() -> void:
	if _pv_cont == null:
		return
	var s := UiKit.scale()
	_pv_cont.position = (origin() + Vector2(26, 8)) * s
	_pv_cont.size = Vector2(51, 72) * s
	ArmorRender.apply(_pv_rig, ArmorRender.slots_of_inventory(world.player.inventory))
	# Java renderEntityInInventoryFollowsMouse over the 26,8 - 75,78 box
	InventoryPreview.follow_mouse(get_local_mouse_position() / s, origin() + Vector2(51.5, 43))
	var model: Node = _pv_rig.get_node_or_null("model")
	if model == null:
		return
	for c in model.get_children():
		for mi in world.entities._meshes(c):
			mi.set_instance_shader_parameter("light", Vector2(1, 1))


## Java InventoryMenu.quickMoveStack: the crafting grid is never a shift-click target from the inventory.
func quick_order(i: int, st: ItemStack) -> Array:
	if creative:
		return super.quick_order(i, st)
	var src: int = slots[i]["section"]
	if src == 0 or src == 3:
		return _sec(1) + _sec(2)
	var eq := _equip_target(st)
	if eq >= 0:
		return [eq]
	return _sec(2) if src == 1 else _sec(1)


func _armor_filter(st: ItemStack, slot: int) -> bool:
	var n := st.name()
	return Res.items.armor_slot[st.item] == slot or (slot == 3 and (n == "carved_pumpkin" or n.ends_with("_head") or n.ends_with("_skull")))


func _grid() -> Array:
	var inv: Inventory = world.player.inventory
	var g: Array = []
	for i in 4:
		g.append(inv.get_slot(Inventory.CRAFT0 + i))
	return g


func on_changed() -> void:
	if creative:
		return
	var m := Crafting.match_grid(_grid(), 2, 2)
	result = m["result"] if not m.is_empty() else ItemStack.new()


func take_output(i: int, all: bool) -> void:
	if creative:
		_take_creative(i)
		return
	var inv: Inventory = world.player.inventory
	var n := 64 if all else 1
	for k in n:
		on_changed()
		if result.is_empty():
			return
		if all:
			if inv.add(result.copy()) > 0:
				return
		else:
			if not inv.cursor.is_empty() and not inv.cursor.can_merge(result):
				return
			if not inv.cursor.is_empty() and inv.cursor.count + result.count > inv.cursor.max_stack():
				return
			if inv.cursor.is_empty():
				inv.cursor = result.copy()
			else:
				inv.cursor.count += result.count
		var g := _grid()
		Crafting.consume(g)
		for gi in 4:
			inv.set_slot(Inventory.CRAFT0 + gi, g[gi])
		world.player.stats["crafted." + result.name()] = int(world.player.stats.get("crafted." + result.name(), 0)) + result.count
	on_changed()


func on_close() -> void:
	var inv: Inventory = world.player.inventory
	if not creative:
		for i in 4:
			var s := inv.get_slot(Inventory.CRAFT0 + i)
			if not s.is_empty():
				var left := inv.add(s)
				if left > 0:
					s.count = left
					world.entities.spawn_item(world.player.eye_pos(), s.copy())
				inv.set_slot(Inventory.CRAFT0 + i, ItemStack.new())
	super.on_close()


# ---------------- creative
func _build_creative() -> void:
	bg_tex = null
	bg_size = Vector2(195, 136)
	title = "Search Items"
	search = LineEdit.new()
	search.placeholder_text = "Search..."
	search.text_changed.connect(func(_t): _filter())
	add_child(search)
	search.position = Vector2(0, 0)
	_filter()
	var inv: Inventory = world.player.inventory
	for c in 9:
		add_slot(Vector2(9 + c * 18, 112), inv.get_slot.bind(c), inv.setter(c), 2)
	for r in 5:
		for c in 9:
			var idx := r * 9 + c
			add_slot(Vector2(9 + c * 18, 18 + r * 18), _cat_get.bind(idx), func(_s): pass, 4, true)
	search.grab_focus()


func _filter() -> void:
	catalogue.clear()
	var q := search.text.to_lower() if search else ""
	for i in range(1, Res.items.names.size()):
		var n: String = Res.items.names[i]
		if n == "air" or n.ends_with("spawn_egg") and not MobRegistry.DEFS.has(n.trim_suffix("_spawn_egg")):
			continue
		if q == "" or n.contains(q) or Res.items.display_name(i).to_lower().contains(q):
			catalogue.append(i)
	scroll = 0


func _cat_get(idx: int) -> ItemStack:
	var j := scroll * 9 + idx
	if j < catalogue.size():
		return ItemStack.of(catalogue[j], 1)
	return ItemStack.new()


func _take_creative(i: int) -> void:
	var st: ItemStack = slots[i]["get"].call()
	var inv: Inventory = world.player.inventory
	if not inv.cursor.is_empty():
		inv.cursor = ItemStack.new()
		return
	if st.is_empty():
		return
	var cp := st.copy()
	cp.count = cp.max_stack() if Input.is_key_pressed(KEY_SHIFT) or true else 1
	inv.cursor = cp


func _process(d: float) -> void:
	super._process(d)
	_update_preview()
	if search:
		var s := UiKit.scale()
		search.position = (origin() + Vector2(80, 2)) * s
		search.size = Vector2(100, 12) * s


func _gui_input(event: InputEvent) -> void:
	if creative and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll = mini(scroll + 1, maxi(0, int(ceil(catalogue.size() / 9.0)) - 5))
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll = maxi(scroll - 1, 0)
			accept_event()
			return
	super._gui_input(event)
