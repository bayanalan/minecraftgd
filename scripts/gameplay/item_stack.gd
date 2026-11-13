## ItemStack — item index + count + damage + data components (custom name, enchantments...).
## Contract: is_empty(), max_stack(), can_merge(other), copy(), to_dict()/from_dict() using stable string IDs.
## Invariants: count <= max_stack; empty stacks have item 0 and count 0.
class_name ItemStack
extends RefCounted

var item := 0
var count := 0
var damage := 0
var components: Dictionary = {}


static func of(item_id: int, n: int = 1) -> ItemStack:
	var s := ItemStack.new()
	if item_id > 0 and n > 0:
		s.item = item_id
		s.count = n
	return s


static func named(name: String, n: int = 1) -> ItemStack:
	return of(maxi(0, Res.items.id(name)), n)


func is_empty() -> bool:
	return item <= 0 or count <= 0


func max_stack() -> int:
	return Res.items.max_stack[item] if item > 0 else 64


func name() -> String:
	return Res.items.names[item] if item > 0 else "air"


func can_merge(o: ItemStack) -> bool:
	return o != null and not o.is_empty() and not is_empty() and o.item == item and o.damage == damage and o.components == components


func copy() -> ItemStack:
	var s := ItemStack.new()
	s.item = item
	s.count = count
	s.damage = damage
	s.components = components.duplicate(true)
	return s


func split(n: int) -> ItemStack:
	var k := mini(n, count)
	var s := copy()
	s.count = k
	count -= k
	if count <= 0:
		clear()
	return s


func clear() -> void:
	item = 0
	count = 0
	damage = 0
	components = {}


func to_dict() -> Dictionary:
	if is_empty():
		return {}
	var d := {"id": "minecraft:" + name(), "count": count}
	if damage > 0:
		d["damage"] = damage
	if not components.is_empty():
		d["components"] = components
	return d


static func from_dict(d) -> ItemStack:
	var s := ItemStack.new()
	if not (d is Dictionary) or d.is_empty():
		return s
	var i := Res.items.id(str(d.get("id", "")))
	if i <= 0:
		# unknown item: keep it as a component-tagged placeholder so data round-trips
		i = Res.items.id("barrier") if Res.items.id("barrier") > 0 else 0
		if i <= 0:
			return s
		s.components = {"recraft:unknown_id": str(d.get("id", ""))}
	s.item = i
	s.count = clampi(int(d.get("count", 1)), 1, 99)
	s.damage = int(d.get("damage", 0))
	if d.get("components") is Dictionary:
		s.components.merge(d["components"])
	return s
