## Inventory — player container: 36 main slots (0-8 hotbar, 9-35 main), 4 armor (36 feet .. 39 head),
## 1 offhand (40), 2x2 crafting grid (41-44) + result (45), plus the cursor stack while a screen is open.
## Contract: add(stack) -> leftover count, remove_item(id, n), get/set slot, selected hotbar, to/from array.
## Invariants: no duplication — every transfer moves counts, never copies without subtracting.
class_name Inventory
extends RefCounted

signal changed

const SIZE := 46
const ARMOR0 := 36
const OFFHAND := 40
const CRAFT0 := 41
const RESULT := 45

var slots: Array = []
var selected := 0
var cursor: ItemStack = ItemStack.new()


func _init() -> void:
	slots.resize(SIZE)
	for i in SIZE:
		slots[i] = ItemStack.new()


func get_slot(i: int) -> ItemStack:
	return slots[i]


func set_slot(i: int, s: ItemStack) -> void:
	slots[i] = s if s != null else ItemStack.new()
	changed.emit()


## Slot setter callable for UI slots: setter(i).call(stack) == set_slot(i, stack)
## (set_slot.bind(i) would append i AFTER the stack and call set_slot(stack, i)).
func setter(i: int) -> Callable:
	return func(st: ItemStack) -> void: set_slot(i, st)


func held() -> ItemStack:
	return slots[selected]


## Adds as much as possible (merge first, hotbar then main); returns leftover count.
## Java Inventory.add: stacks onto the selected slot first, then the offhand, then any slot with room, then the first
## free slot; every slot that receives items gets popTime 5 (the hotbar "pop" squash, Gui.renderSlot).
func add(s: ItemStack) -> int:
	if s.is_empty():
		return 0
	var left := s.count
	var maxs := s.max_stack()
	var order: Array = [selected, OFFHAND]
	for i in 36:
		if i != selected:
			order.append(i)
	for i in order:
		var t: ItemStack = slots[i]
		if t.can_merge(s) and t.count < maxs:
			var mv := mini(maxs - t.count, left)
			t.count += mv
			left -= mv
			pop[i] = 5
			if left == 0:
				changed.emit()
				return 0
	for i in 36:
		var t2: ItemStack = slots[i]
		if t2.is_empty():
			var n := s.copy()
			n.count = mini(maxs, left)
			slots[i] = n
			left -= n.count
			pop[i] = 5
			if left == 0:
				changed.emit()
				return 0
	changed.emit()
	return left


var pop: Dictionary = {}   # slot -> Java ItemStack.popTime (5 after a pickup, -1 per tick)


func tick_pop() -> void:
	if pop.is_empty():
		return
	for k in pop.keys():
		pop[k] = int(pop[k]) - 1
		if int(pop[k]) <= 0:
			pop.erase(k)


func count_item(item: int) -> int:
	var n := 0
	for i in 36:
		var t: ItemStack = slots[i]
		if t.item == item:
			n += t.count
	return n


func remove_item(item: int, n: int) -> int:
	var removed := 0
	for i in 36:
		var t: ItemStack = slots[i]
		if t.item == item and removed < n:
			var k := mini(t.count, n - removed)
			t.count -= k
			removed += k
			if t.count <= 0:
				t.clear()
	changed.emit()
	return removed


func consume_held(n: int = 1) -> void:
	var h: ItemStack = slots[selected]
	h.count -= n
	if h.count <= 0:
		h.clear()
	changed.emit()


func armor_points() -> int:
	var p := 0
	for i in range(ARMOR0, ARMOR0 + 4):
		var s: ItemStack = slots[i]
		if not s.is_empty():
			p += Res.items.armor_points[s.item]
	return p


func armor_toughness() -> float:
	var p := 0.0
	for i in range(ARMOR0, ARMOR0 + 4):
		var s: ItemStack = slots[i]
		if not s.is_empty():
			p += Res.items.armor_tough[s.item]
	return p


## Knockback resistance from worn armor (netherite 0.1 per piece, wiki: Armor materials), capped at 1.
func knockback_resistance() -> float:
	var k := 0.0
	for i in range(ARMOR0, ARMOR0 + 4):
		var s: ItemStack = slots[i]
		if not s.is_empty():
			k += Res.items.armor_kb[s.item]
	return minf(k, 1.0)


func clear_all() -> void:
	for i in SIZE:
		(slots[i] as ItemStack).clear()
	cursor.clear()
	changed.emit()


func to_array() -> Array:
	var a: Array = []
	for i in SIZE:
		a.append((slots[i] as ItemStack).to_dict())
	return a


func from_array(a: Array) -> void:
	for i in mini(a.size(), SIZE):
		slots[i] = ItemStack.from_dict(a[i])
	changed.emit()
