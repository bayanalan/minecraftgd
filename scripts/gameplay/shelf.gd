## Shelf — the 26.x wooden shelves (minecraft.wiki "Shelf"): three item slots shown on the front, right-click swaps the
## held item with the slot under the cursor; powered shelves join up to three in a row facing the same way
## (side_chain left / center / right) and swap all their slots with the hotbar at once - one shelf the 3 rightmost
## hotbar slots, two the 6, three all 9; comparator: left 1 + middle 2 + right 4 (read from the back).
## Contract: static functions; shelf block entities are {"id": <block>, "items": [3 item dicts]}.
class_name Shelf

const FRONT := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0)}


static func is_shelf(name: String) -> bool:
	return name.ends_with("_shelf")


## Right as seen by someone in front of the shelf (looking at its front face).
static func right_dir(facing: String) -> Vector3i:
	var f: Vector3i = FRONT.get(facing, Vector3i(0, 0, -1))
	var look := -f
	return Vector3i(-look.z, 0, look.x)   # (look x up)


## Slot 0 (left) .. 2 (right) under the hit point.
static func slot_at(st: int, pos: Vector3i, point: Vector3) -> int:
	var r := right_dir(Res.blocks.get_prop(st, "facing"))
	var c := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	var t := (point - c).dot(Vector3(r)) + 0.5
	return clampi(int(floor(t * 3.0)), 0, 2)


static func _items(world, p: Vector3i) -> Array:
	var d := BlockEntities.get_data(world, p)
	var items: Array = d.get("items", [])
	if items.size() != 3:
		items = [{}, {}, {}]
	return items


static func _store(world, p: Vector3i, items: Array) -> void:
	var d := BlockEntities.get_data(world, p)
	if d.is_empty():
		d = {"id": Res.blocks.name_of(world.state_at(p.x, p.y, p.z))}
	d["items"] = items
	BlockEntities.set_data(world, p, d)
	BERender.refresh(p)


static func use(world, pos: Vector3i, st: int, hit: Dictionary, p: Player) -> bool:
	var b := Res.blocks
	if b.get_prop(st, "powered") == "true":
		return _swap_hotbar(world, pos, st, p)
	var slot := slot_at(st, pos, Vector3(hit.get("point", Vector3(pos) + Vector3(0.5, 0.5, 0.5))))
	var items := _items(world, pos)
	var on_shelf := ItemStack.from_dict(items[slot])
	var held := p.inventory.held()
	if on_shelf.is_empty() and held.is_empty():
		return false
	items[slot] = held.to_dict() if not held.is_empty() else {}
	p.inventory.set_slot(p.inventory.selected, on_shelf)
	_store(world, pos, items)
	var snd := "block.shelf.single_swap"
	if held.is_empty():
		snd = "block.shelf.take_item"
	elif on_shelf.is_empty():
		snd = "block.shelf.place_item"
	Audio.play(snd, Vector3(pos) + Vector3(0.5, 0.5, 0.5), "Blocks")
	return true


## The powered chain this shelf belongs to, left to right (positions).
static func chain(world, pos: Vector3i, st: int) -> Array:
	var b := Res.blocks
	var f := b.get_prop(st, "facing")
	var r := right_dir(f)
	var same := func(q: Vector3i) -> bool:
		var s2: int = world.state_at(q.x, q.y, q.z)
		return s2 > 0 and is_shelf(b.name_of(s2)) and b.get_prop(s2, "facing") == f and b.get_prop(s2, "powered") == "true"
	var left := pos
	while left - pos != -r * 2 and same.call(left - r):
		left -= r
	var out: Array = []
	var q := left
	while out.size() < 3 and (q == pos or same.call(q)):
		out.append(q)
		q += r
	if not out.has(pos):
		out = [pos]
	return out


static func _swap_hotbar(world, pos: Vector3i, st: int, p: Player) -> bool:
	var shelves := chain(world, pos, st)
	var first_hb := 9 - 3 * shelves.size()
	var k := first_hb
	for sp in shelves:
		var items := _items(world, sp)
		for i in 3:
			var hb := p.inventory.get_slot(k)
			var sh := ItemStack.from_dict(items[i])
			p.inventory.set_slot(k, sh)
			items[i] = hb.to_dict() if not hb.is_empty() else {}
			k += 1
		_store(world, sp, items)
	Audio.play("block.shelf.multi_swap", Vector3(pos) + Vector3(0.5, 0.5, 0.5), "Blocks")
	return true


## Redstone: powered follows the input; side_chain re-evaluated for this shelf and its row.
static func on_power(world, pos: Vector3i, st: int, powered: bool) -> void:
	var b := Res.blocks
	if (b.get_prop(st, "powered") == "true") == powered:
		return
	world.set_block(pos.x, pos.y, pos.z, b.with_prop(st, "powered", "true" if powered else "false"), false)
	Audio.play("block.shelf.activate" if powered else "block.shelf.deactivate", Vector3(pos) + Vector3(0.5, 0.5, 0.5), "Blocks")
	var r := right_dir(b.get_prop(st, "facing"))
	for d in range(-2, 3):
		_update_chain_state(world, pos + r * d)


static func _update_chain_state(world, q: Vector3i) -> void:
	var b := Res.blocks
	var s: int = world.state_at(q.x, q.y, q.z)
	if s <= 0 or not is_shelf(b.name_of(s)) or not b.has_prop(s, "side_chain"):
		return
	var want := "unconnected"
	if b.get_prop(s, "powered") == "true":
		var ch := chain(world, q, s)
		if ch.size() > 1:
			var i := ch.find(q)
			want = "left" if i == 0 else ("right" if i == ch.size() - 1 else "center")
	if b.get_prop(s, "side_chain") != want:
		world.set_block(q.x, q.y, q.z, b.with_prop(s, "side_chain", want), false)


## Comparator reading (back side): left 1, middle 2, right 4.
static func comparator(world, pos: Vector3i) -> int:
	var items := _items(world, pos)
	var v := 0
	for i in 3:
		if not ItemStack.from_dict(items[i]).is_empty():
			v += [1, 2, 4][i]
	return v


## Display node children (BERender): the three items on the bottom ledge (block coordinates, shelf facing north,
## open side -z), each with its model's on_shelf display, a quarter size, turned to face out of the shelf.
static func build_items(model: Node3D, be: Dictionary) -> void:
	var items: Array = be.get("items", [])
	for i in mini(3, items.size()):
		var s := ItemStack.from_dict(items[i])
		if s.is_empty():
			continue
		var n := HeldItems.item_node(s, "on_shelf", false)
		if n == null:
			continue
		var holder := Node3D.new()
		# slot centres 16 / 3 px apart from the left as seen from the front (+x is the viewer's left on a north shelf)
		holder.position = Vector3((16.0 - (i + 0.5) * 16.0 / 3.0) / 16.0, 8.0 / 16.0, 12.0 / 16.0)
		holder.basis = Basis(Vector3.UP, PI) * Basis.from_scale(Vector3.ONE * 0.25)
		holder.add_child(n)
		model.add_child(holder)
