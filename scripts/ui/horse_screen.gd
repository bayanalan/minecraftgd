## HorseScreen — Java HorseInventoryScreen on the installed gui/container/horse.png (176x166): saddle slot (8, 18),
## body armor slot (8, 36; horse armor for horses, carpets for llamas), 5x3 chest slots at (80, 18) for chested
## donkeys/mules/llamas, player inventory at (8, 84). Backed by the mount entity's data (saved with the entity).
extends ContainerUI

var mount   # EntityManager.Ent


func build() -> void:
	bg_tex = UiKit.sprite("gui/container/horse")
	bg_size = Vector2(176, 166)
	title = str(mount.data.get("CustomName", mount.id.capitalize()))
	add_slot(Vector2(8, 18), _get_saddle, _set_saddle, 0, false, func(s: ItemStack): return s.name() == "saddle", "saddle")
	if not (mount.id in ["donkey", "mule"]):
		add_slot(Vector2(8, 36), _get_armor, _set_armor, 0, false, _armor_ok, "llama_armor" if str(mount.id) in ["llama", "trader_llama"] else "horse_armor")
	if bool(mount.data.get("chest", false)):
		var items: Array = mount.data.get("items", [])
		if items.size() < 15:
			items.resize(15)
			for i in 15:
				if items[i] == null:
					items[i] = {}
			mount.data["items"] = items
		for r in 3:
			for c in 5:
				var idx := r * 5 + c
				add_slot(Vector2(80 + c * 18, 18 + r * 18), _get_item.bind(idx), _set_item.bind(idx), 0)
	add_player_inventory(8, 84)


func _armor_ok(s: ItemStack) -> bool:
	if mount.id in ["llama", "trader_llama"]:
		return s.name().ends_with("_carpet")
	return s.name().ends_with("_horse_armor")


func _get_saddle() -> ItemStack:
	return ItemStack.named("saddle", 1) if bool(mount.data.get("saddle", false)) else ItemStack.new()


func _set_saddle(s: ItemStack) -> void:
	mount.data["saddle"] = not s.is_empty()


func _get_armor() -> ItemStack:
	return ItemStack.from_dict(mount.data.get("horse_armor", {}))


func _set_armor(s: ItemStack) -> void:
	mount.data["horse_armor"] = s.to_dict() if not s.is_empty() else {}


func _get_item(i: int) -> ItemStack:
	return ItemStack.from_dict((mount.data.get("items", []) as Array)[i])


func _set_item(s: ItemStack, i: int) -> void:
	(mount.data["items"] as Array)[i] = s.to_dict()
