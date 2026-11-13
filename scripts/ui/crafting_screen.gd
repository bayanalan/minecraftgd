## CraftingScreen — 3x3 crafting table (gui/container/crafting_table.png) with shaped/shapeless matching.
extends ContainerUI

var grid_size := 3
var grid: Array = []
var result: ItemStack = ItemStack.new()


func build() -> void:
	bg_tex = UiKit.sprite("gui/container/crafting_table")
	bg_size = Vector2(176, 166)
	title = Res.tr_key("container.crafting", "Crafting")
	title_pos = Vector2(29, 6)   # Java CraftingScreen titleLabelX = 29
	grid.clear()
	for i in 9:
		grid.append(ItemStack.new())
	for r in 3:
		for c in 3:
			var i := r * 3 + c
			add_slot(Vector2(30 + c * 18, 17 + r * 18), func(): return grid[i], func(s): grid[i] = s, 0)
	add_slot(Vector2(124, 35), func(): return result, func(_s): pass, 0, true)
	add_player_inventory(8, 84)
	rb_gw = 3
	rb_gh = 3
	rb_get = func(i: int) -> ItemStack: return grid[i]
	rb_set = func(i: int, s: ItemStack) -> void: grid[i] = s
	rb_btn = Vector2(5, 34)


func on_changed() -> void:
	var m := Crafting.match_grid(grid, 3, 3)
	result = m["result"] if not m.is_empty() else ItemStack.new()


func take_output(_i: int, all: bool) -> void:
	var inv: Inventory = world.player.inventory
	for k in (64 if all else 1):
		on_changed()
		if result.is_empty():
			return
		if all:
			if inv.add(result.copy()) > 0:
				return
		else:
			if not inv.cursor.is_empty() and (not inv.cursor.can_merge(result) or inv.cursor.count + result.count > inv.cursor.max_stack()):
				return
			if inv.cursor.is_empty():
				inv.cursor = result.copy()
			else:
				inv.cursor.count += result.count
		Crafting.consume(grid)
	on_changed()


func on_close() -> void:
	var inv: Inventory = world.player.inventory
	for i in 9:
		var s: ItemStack = grid[i]
		if not s.is_empty():
			var left := inv.add(s)
			if left > 0:
				s.count = left
				world.entities.spawn_item(world.player.eye_pos(), s.copy())
		grid[i] = ItemStack.new()
	super.on_close()
