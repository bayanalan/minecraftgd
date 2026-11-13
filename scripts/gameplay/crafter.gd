## Crafter (Java CrafterBlock / CrafterBlockEntity / CrafterMenu): nine slots that can be disabled, crafting on a
## redstone rising edge 4 ticks later - the result (and remainders) go into the container in front or pop out of the
## front face, one of each ingredient is used; no recipe: the fail sound. Hoppers fill the smallest stacks first,
## comparators read the number of slots that hold an item or are disabled.
class_name Crafter
extends RefCounted


static func disabled(d: Dictionary, i: int) -> bool:
	return (d.get("disabled_slots", []) as Array).has(i)


static func set_disabled(d: Dictionary, i: int, on: bool) -> void:
	var a: Array = (d.get("disabled_slots", []) as Array).duplicate()
	if on and not a.has(i):
		a.append(i)
		a.sort()
	elif not on:
		a.erase(i)
	d["disabled_slots"] = a


static func _grid(d: Dictionary) -> Array:
	var raw: Array = d.get("items", [])
	var g: Array = []
	for i in 9:
		g.append(ItemStack.from_dict(raw[i] if i < raw.size() else {}))
	return g


## The recipe result for the grid (CrafterBlock.getPotentialResults), empty when nothing matches.
static func result(grid: Array) -> ItemStack:
	var any := false
	for s in grid:
		if not (s as ItemStack).is_empty():
			any = true
			break
	if not any:
		return ItemStack.new()
	var m := Crafting.match_grid(grid, 3, 3)
	return (m["result"] as ItemStack).copy() if not m.is_empty() else ItemStack.new()


## CrafterBlock.dispenseFrom (the scheduled tick after a rising edge).
static func craft(world, p: Vector3i, st: int) -> void:
	var d := BlockEntities.get_data(world, p)
	if d.is_empty():
		return
	var grid := _grid(d)
	var res := result(grid)
	if res.is_empty():
		Audio.play("block.crafter.fail", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks")
		return
	var b := Res.blocks
	world.set_block(p.x, p.y, p.z, b.with_prop(st, "crafting", "true"), false)
	d["crafting_until"] = int(world.game_time) + 6
	BlockUpdates.schedule(world, p, 6)
	# remainders (buckets, bottles) before the grid shrinks: Crafting.consume turns an emptied slot into its remainder
	var before: Array = []
	for s in grid:
		before.append((s as ItemStack).copy())
	Crafting.match_grid(grid, 3, 3)
	Crafting.consume(grid)
	var rems: Array = []
	for i in 9:
		var g: ItemStack = grid[i]
		var was: ItemStack = before[i]
		if not was.is_empty() and not g.is_empty() and g.item != was.item:
			rems.append(g.copy())   # the slot emptied and became its remainder: Java ejects remainders, the slot empties
			grid[i] = ItemStack.new()
	var raw: Array = []
	for s2 in grid:
		raw.append((s2 as ItemStack).to_dict())
	d["items"] = raw
	BlockEntities.set_data(world, p, d)
	var front := _front(st)
	_out(world, p, front, res)
	for r in rems:
		_out(world, p, front, r)
	Redstone.request(world, p)


## Direction the crafter faces (orientation "north_up" etc.: the first word).
static func _front(st: int) -> Vector3i:
	var o := Res.blocks.get_prop(st, "orientation")
	var f := o.get_slice("_", 0)
	return {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0),
		"up": Vector3i(0, 1, 0), "down": Vector3i(0, -1, 0)}.get(f, Vector3i(0, 0, -1))


## CrafterBlock.dispenseItem: into the container in front (one at a time for crafters / over-sized stacks), the rest
## pops out of the front face (DefaultDispenseItemBehavior.spawnItem speed 6), with the craft sound and particles.
static func _out(world, p: Vector3i, f: Vector3i, s: ItemStack) -> void:
	var t := p + f
	var td := BlockEntities.get_data(world, t)
	var left := s.copy()
	if not td.is_empty() and td.has("items"):
		var tid := str(td.get("id", Res.blocks.name_of(maxi(0, world.state_at(t.x, t.y, t.z)))))
		while not left.is_empty():
			var one := left.copy()
			one.count = 1
			if not BlockEntities._insert(td, one, tid, -f):
				break
			left.count -= 1
		BlockEntities.set_data(world, t, td)
	if not left.is_empty():
		var out := Vector3(p) + Vector3(0.5, 0.5, 0.5) + Vector3(f) * 0.7
		world.entities.spawn_item(out, left, true)
		Audio.play("block.crafter.craft", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks")


## CrafterBlockEntity.getRedstoneSignal: slots holding an item or disabled (0..9).
static func signal_strength(d: Dictionary) -> int:
	var raw: Array = d.get("items", [])
	var n := 0
	for i in 9:
		if disabled(d, i) or (i < raw.size() and not ItemStack.from_dict(raw[i]).is_empty()):
			n += 1
	return n


## CrafterBlockEntity.canPlaceItem for hoppers: never a disabled slot; a non-empty slot only when no later enabled
## slot is empty or holds fewer of the same item (fills the grid evenly).
static func insert_one(d: Dictionary, s: ItemStack) -> bool:
	var items: Array = d.get("items", [])
	while items.size() < 9:
		items.append({})
	for i in 9:
		if disabled(d, i):
			continue
		var cur := ItemStack.from_dict(items[i])
		if cur.is_empty():
			items[i] = s.to_dict()
			d["items"] = items
			return true
		if cur.count >= cur.max_stack() or not cur.can_merge(s):
			continue
		var smaller := false
		for j in range(i + 1, 9):
			if disabled(d, j):
				continue
			var o := ItemStack.from_dict(items[j])
			if o.is_empty() or (o.count < cur.count and o.can_merge(cur)):
				smaller = true
				break
		if smaller:
			continue
		cur.count += 1
		items[i] = cur.to_dict()
		d["items"] = items
		return true
	return false