## Bundles — Java BundleItem / BundleContents (26.x): weight capacity 64 units (an item weighs 64 / max stack;
## a nested bundle 4 + its contents), newest stack first, shulker boxes refused. Inventory clicks:
## - bundle on cursor, left-click a filled slot: put that slot's items in (tryTransfer)
## - bundle on cursor, right-click an empty slot: take the newest item out into the slot
## - items on cursor, left-click a bundle: put the cursor items in
## - empty cursor, right-click a bundle: take the newest item out onto the cursor
## Using a bundle in the world empties it in front of the player. Slot bar: fullness (blue, red when full).
## Contents live in the item component minecraft:bundle_contents (Array of item dicts).
class_name Bundles
extends RefCounted

const CAPACITY := 64


static func is_bundle(s: ItemStack) -> bool:
	return s != null and not s.is_empty() and (s.name() == "bundle" or s.name().ends_with("_bundle"))


static func contents(s: ItemStack) -> Array:
	var c = s.components.get("minecraft:bundle_contents", [])
	return c if c is Array else []


static func unit(s: ItemStack) -> int:
	if is_bundle(s):
		return 4 + weight(s)
	return CAPACITY / maxi(1, s.max_stack())


static func weight(b: ItemStack) -> int:
	var w := 0
	for d in contents(b):
		var s := ItemStack.from_dict(d)
		w += unit(s) * s.count
	return w


static func can_hold(s: ItemStack) -> bool:
	return not s.is_empty() and not s.name().ends_with("shulker_box")


## Moves as much of `s` as fits into bundle `b`. Returns the number moved (s.count is reduced).
static func insert(b: ItemStack, s: ItemStack) -> int:
	if not can_hold(s) or s == b:
		return 0
	var room := CAPACITY - weight(b)
	var per := unit(s)
	var n := mini(s.count, room / per) if per > 0 else 0
	if n <= 0:
		return 0
	var items: Array = contents(b).duplicate(true)
	var merged := false
	for i in items.size():
		var e := ItemStack.from_dict(items[i])
		if e.can_merge(s):
			e.count += n
			items.remove_at(i)
			items.insert(0, e.to_dict())
			merged = true
			break
	if not merged:
		var add := s.copy()
		add.count = n
		items.insert(0, add.to_dict())
	s.count -= n
	b.components["minecraft:bundle_contents"] = items
	return n


static func remove_one(b: ItemStack) -> ItemStack:
	var items: Array = contents(b).duplicate(true)
	if items.is_empty():
		return ItemStack.new()
	var out := ItemStack.from_dict(items.pop_front())
	if items.is_empty():
		b.components.erase("minecraft:bundle_contents")
	else:
		b.components["minecraft:bundle_contents"] = items
	return out


## ContainerUI click hook. True when the bundle handled the click.
static func click(ui, sl: Dictionary, st: ItemStack, right: bool) -> bool:
	var inv: Inventory = ui.world.player.inventory
	var cur := inv.cursor
	var p: Vector3 = ui.world.player.pos
	if is_bundle(cur) and not right and not st.is_empty():
		if insert(cur, st) > 0:
			sl["set"].call(st if st.count > 0 else ItemStack.new())
			Audio.play("item.bundle.insert", p, "Players", 0.8, 0.8 + randf() * 0.4)
		else:
			Audio.play("item.bundle.insert_fail", p, "Players")
		return true
	if is_bundle(cur) and right and st.is_empty():
		var out := remove_one(cur)
		if not out.is_empty():
			sl["set"].call(out)
			Audio.play("item.bundle.remove_one", p, "Players", 0.8, 0.8 + randf() * 0.4)
		return true
	if is_bundle(st) and not right and not cur.is_empty():
		if insert(st, cur) > 0:
			if cur.count <= 0:
				inv.cursor = ItemStack.new()
			sl["set"].call(st)
			Audio.play("item.bundle.insert", p, "Players", 0.8, 0.8 + randf() * 0.4)
		else:
			Audio.play("item.bundle.insert_fail", p, "Players")
		return true
	if is_bundle(st) and right and cur.is_empty():
		var out2 := remove_one(st)
		if not out2.is_empty():
			inv.cursor = out2
			sl["set"].call(st)
			Audio.play("item.bundle.remove_one", p, "Players", 0.8, 0.8 + randf() * 0.4)
		return true
	return false


## Java BundleItem.dropContent (use in the world).
static func drop_all(world, b: ItemStack) -> bool:
	var items := contents(b)
	if items.is_empty():
		return false
	var p: Player = world.player
	for d in items:
		var e = world.entities.spawn_item(p.eye_pos() - Vector3(0, 0.3, 0), ItemStack.from_dict(d))
		if e != null:
			e.vel = p.look_dir() * 0.3 + Vector3(randf_range(-0.05, 0.05), 0.1, randf_range(-0.05, 0.05))
			e.pickup_delay = 40
	b.components.erase("minecraft:bundle_contents")
	Audio.play("item.bundle.drop_contents", p.pos, "Players")
	world.inv_changed()
	return true
