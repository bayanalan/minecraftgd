## MobBuckets — Bucket of Aquatic Mob (wiki): a water bucket used on a cod, salmon, tropical fish, pufferfish, axolotl
## or tadpole scoops it up (Java Bucketable.bucketMobPickup: the mob is removed, the filled bucket replaces one water
## bucket - creative keeps the water bucket and adds the filled one if missing); using the bucket places water like a
## water bucket (none where water evaporates) and releases the mob there (MobBucketItem.checkExtraContent), never
## despawning, with what the bucket kept (minecraft:bucket_entity_data: Health, Age for axolotls / tadpoles, the
## mob's variant data, its custom name); dispensers empty them the same way. Sounds from the wiki table.
class_name MobBuckets

const MOBS := {"cod": "cod_bucket", "salmon": "salmon_bucket", "tropical_fish": "tropical_fish_bucket", "pufferfish": "pufferfish_bucket",
	"axolotl": "axolotl_bucket", "tadpole": "tadpole_bucket"}
const ITEMS := {"cod_bucket": "cod", "salmon_bucket": "salmon", "tropical_fish_bucket": "tropical_fish", "pufferfish_bucket": "pufferfish",
	"axolotl_bucket": "axolotl", "tadpole_bucket": "tadpole"}
# wiki Bucket of Aquatic Mob sounds: [event, volume, pitch]
const FILL := {"axolotl": ["item.bucket.fill_axolotl", 1.0, 1.0], "tadpole": ["item.bucket.fill_tadpole", 0.5, 1.5]}
const FILL_FISH := ["item.bucket.fill_fish", 1.0, 1.0]
const EMPTY := {"axolotl": ["item.bucket.empty_axolotl", 1.0, 1.0], "tadpole": ["item.bucket.empty_tadpole", 0.5, 1.5]}
const EMPTY_FISH := ["item.bucket.empty_fish", 1.0, 1.0]


static func is_bucket(item_name: String) -> bool:
	return ITEMS.has(item_name)


## The empty sound of a mob bucket ([] for other items).
static func empty_sound(item_name: String) -> Array:
	if not ITEMS.has(item_name):
		return []
	return EMPTY.get(ITEMS[item_name], EMPTY_FISH)


## Bucketable.bucketMobPickup. True when the mob went into the bucket.
static func pickup(em, e, p, held: ItemStack) -> bool:
	if held.is_empty() or held.name() != "water_bucket" or e.dead or not MOBS.has(e.id):
		return false
	var snd: Array = FILL.get(e.id, FILL_FISH)
	Audio.play(snd[0], e.pos, "Neutral", snd[1], snd[2])
	var out := ItemStack.named(MOBS[e.id], 1)
	out.components["minecraft:bucket_entity_data"] = _save(e)
	if e.data.has("CustomName"):
		out.components["minecraft:custom_name"] = str(e.data["CustomName"])
	# ItemUtils.createFilledResult(stack, player, filled, false)
	var inv: Inventory = p.inventory
	if p.is_creative():
		if inv.count_item(out.item) == 0:
			inv.add(out)
	elif held.count == 1:
		inv.set_slot(inv.selected, out)
	else:
		held.count -= 1
		if inv.add(out) > 0:
			em.spawn_item(p.pos + Vector3(0, 1.3, 0), out)
		inv.changed.emit()
	if em.world.advancements != null:
		em.world.advancements.trigger("filled_bucket", {"item": MOBS[e.id]})
	em._remove(e)
	em.world.swing_hand()
	em.world.inv_changed()
	return true


## Bucketable.saveToBucketTag: health, age (axolotls / tadpoles) and the mob's plain data values (variants).
static func _save(e) -> Dictionary:
	var d := {"Health": e.hp}
	if e.id == "axolotl" or e.id == "tadpole":
		d["Age"] = e.baby_age
	var ed := {}
	for k in e.data:
		var v = e.data[k]
		if (v is int or v is float or v is String or v is bool) and str(k) != "CustomName":
			ed[str(k)] = v
	if not ed.is_empty():
		d["data"] = ed
	return d


## MobBucketItem.checkExtraContent: the mob at the bottom centre of the block the water went to, from the bucket's
## data, marked persistent (fromBucket: never despawns).
static func release(world, s: ItemStack, pos: Vector3i):
	var id: String = ITEMS.get(s.name(), "")
	if id == "" or world.get("entities") == null:
		return null
	var bd = s.components.get("minecraft:bucket_entity_data", {})
	var age := 0
	if bd is Dictionary and (id == "axolotl" or id == "tadpole"):
		age = int((bd as Dictionary).get("Age", 0))
	var e = world.entities.spawn_mob(id, Vector3(pos) + Vector3(0.5, 0.0, 0.5), id == "axolotl" and age < 0)
	if e == null:
		return null
	e.persistent = true
	e.data["from_bucket"] = true
	if bd is Dictionary:
		var bdd: Dictionary = bd
		if bdd.has("Health"):
			e.hp = clampf(float(bdd["Health"]), 0.5, float(e.def.get("hp", e.hp)))
		if id == "axolotl" or id == "tadpole":
			e.baby_age = age
		var ed = bdd.get("data", {})
		if ed is Dictionary:
			for k in ed:
				e.data[k] = ed[k]
	if s.components.has("minecraft:custom_name"):
		e.data["CustomName"] = str(s.components["minecraft:custom_name"])
	return e
