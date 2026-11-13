## Trading — villager professions and offers (Java VillagerTrades novice/apprentice tiers recalled, source D;
## APPROXIMATE: professions are assigned at spawn instead of by claiming job sites, no level-ups or price
## demand/reputation adjustments) and wandering trader offers. Offer: {a: [item, count], b: [item, count] or [],
## out: [item, count], uses, max, xp}.
## Contract: assign(e, rng) fills e.data {prof, offers}; can_pay/pay(inventory, offer); restock(e).
class_name Trading
extends RefCounted

const PROFESSIONS := ["farmer", "fisherman", "shepherd", "fletcher", "librarian", "cartographer", "cleric", "armorer",
	"weaponsmith", "toolsmith", "butcher", "leatherworker", "mason", "nitwit"]

# profession -> list of [a, b, out, max_uses, xp]; a/b/out = [item, count]
const TABLE := {
	"farmer": [[["wheat", 20], [], ["emerald", 1], 16, 2], [["potato", 26], [], ["emerald", 1], 16, 2], [["carrot", 22], [], ["emerald", 1], 16, 2],
		[["beetroot", 15], [], ["emerald", 1], 16, 2], [["emerald", 1], [], ["bread", 6], 16, 1], [["pumpkin", 6], [], ["emerald", 1], 12, 10],
		[["emerald", 1], [], ["pumpkin_pie", 4], 12, 5], [["emerald", 1], [], ["apple", 4], 16, 5]],
	"fisherman": [[["string", 20], [], ["emerald", 1], 16, 2], [["coal", 10], [], ["emerald", 1], 16, 2], [["cod", 6], ["emerald", 1], ["cooked_cod", 6], 16, 1],
		[["emerald", 3], [], ["cod_bucket", 1], 16, 1], [["cod", 15], [], ["emerald", 1], 16, 10], [["emerald", 1], ["salmon", 6], ["cooked_salmon", 6], 16, 5]],
	"shepherd": [[["white_wool", 18], [], ["emerald", 1], 16, 2], [["brown_wool", 18], [], ["emerald", 1], 16, 2], [["black_wool", 18], [], ["emerald", 1], 16, 2],
		[["emerald", 2], [], ["shears", 1], 12, 1], [["white_dye", 12], [], ["emerald", 1], 16, 10], [["emerald", 1], [], ["white_wool", 1], 16, 5]],
	"fletcher": [[["stick", 32], [], ["emerald", 1], 16, 2], [["emerald", 1], [], ["arrow", 16], 12, 1], [["gravel", 10], ["emerald", 1], ["flint", 10], 12, 1],
		[["flint", 26], [], ["emerald", 1], 12, 10], [["emerald", 2], [], ["bow", 1], 12, 5]],
	"librarian": [[["paper", 24], [], ["emerald", 1], 16, 2], [["emerald", 9], [], ["bookshelf", 1], 12, 1], [["emerald", 5], ["book", 1], ["enchanted_book", 1], 12, 1],
		[["book", 4], [], ["emerald", 1], 12, 10], [["emerald", 1], [], ["lantern", 1], 12, 5]],
	"cartographer": [[["paper", 24], [], ["emerald", 1], 16, 2], [["emerald", 7], [], ["map", 1], 12, 1], [["glass_pane", 11], [], ["emerald", 1], 16, 10]],
	"cleric": [[["rotten_flesh", 32], [], ["emerald", 1], 16, 2], [["emerald", 1], [], ["redstone", 2], 12, 1], [["gold_ingot", 3], [], ["emerald", 1], 12, 10],
		[["emerald", 1], [], ["lapis_lazuli", 1], 12, 5]],
	"armorer": [[["coal", 15], [], ["emerald", 1], 16, 2], [["emerald", 7], [], ["iron_leggings", 1], 12, 1], [["emerald", 4], [], ["iron_boots", 1], 12, 1],
		[["emerald", 5], [], ["iron_helmet", 1], 12, 1], [["emerald", 9], [], ["iron_chestplate", 1], 12, 1], [["iron_ingot", 4], [], ["emerald", 1], 12, 10]],
	"weaponsmith": [[["coal", 15], [], ["emerald", 1], 16, 2], [["emerald", 3], [], ["iron_axe", 1], 12, 1], [["emerald", 2], [], ["iron_sword", 1], 3, 1],
		[["iron_ingot", 4], [], ["emerald", 1], 12, 10]],
	"toolsmith": [[["coal", 15], [], ["emerald", 1], 16, 2], [["emerald", 1], [], ["stone_axe", 1], 12, 1], [["emerald", 1], [], ["stone_shovel", 1], 12, 1],
		[["emerald", 1], [], ["stone_pickaxe", 1], 12, 1], [["emerald", 1], [], ["stone_hoe", 1], 12, 1], [["iron_ingot", 4], [], ["emerald", 1], 12, 10]],
	"butcher": [[["chicken", 14], [], ["emerald", 1], 16, 2], [["porkchop", 7], [], ["emerald", 1], 16, 2], [["rabbit", 4], [], ["emerald", 1], 16, 2],
		[["emerald", 1], [], ["rabbit_stew", 1], 12, 1], [["coal", 15], [], ["emerald", 1], 16, 10], [["emerald", 1], [], ["cooked_porkchop", 5], 16, 5]],
	"leatherworker": [[["leather", 6], [], ["emerald", 1], 16, 2], [["emerald", 3], [], ["leather_leggings", 1], 12, 1], [["emerald", 7], [], ["leather_chestplate", 1], 12, 1],
		[["flint", 26], [], ["emerald", 1], 12, 10], [["emerald", 5], [], ["leather_helmet", 1], 12, 5]],
	"mason": [[["clay_ball", 10], [], ["emerald", 1], 16, 2], [["emerald", 1], [], ["bricks", 10], 16, 1], [["stone", 20], [], ["emerald", 1], 16, 10],
		[["emerald", 1], [], ["chiseled_stone_bricks", 4], 16, 5]],
	"nitwit": [],
	"wandering_trader": [[["emerald", 1], [], ["oak_sapling", 1], 8, 1], [["emerald", 1], [], ["fern", 1], 12, 1], [["emerald", 1], [], ["sugar_cane", 1], 8, 1],
		[["emerald", 1], [], ["pumpkin", 1], 4, 1], [["emerald", 3], [], ["glowstone", 1], 5, 1], [["emerald", 5], [], ["blue_ice", 1], 6, 1],
		[["emerald", 3], [], ["sea_pickle", 1], 5, 1], [["emerald", 1], [], ["slime_ball", 1], 5, 1], [["emerald", 1], [], ["cactus", 1], 8, 1],
		[["emerald", 1], [], ["red_dye", 3], 12, 1], [["emerald", 5], [], ["nautilus_shell", 1], 5, 1], [["emerald", 1], [], ["kelp", 1], 12, 1]],
}


static func assign(e, rng: RandomNumberGenerator) -> void:
	var prof: String = "wandering_trader" if e.id == "wandering_trader" else PROFESSIONS[rng.randi_range(0, PROFESSIONS.size() - 1)]
	var lst: Array = TABLE.get(prof, [])
	var picks: Array = []
	var pool := lst.duplicate()
	var want := 6 if prof == "wandering_trader" else mini(4, pool.size())
	while picks.size() < want and not pool.is_empty():
		picks.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	var offers: Array = []
	for t in picks:
		offers.append({"a": t[0], "b": t[1], "out": t[2], "uses": 0, "max": t[3], "xp": t[4]})
	e.data["prof"] = prof
	e.data["offers"] = offers


static func can_pay(inv: Inventory, o: Dictionary) -> bool:
	for c in [o["a"], o["b"]]:
		if c.is_empty():
			continue
		if inv.count_item(Res.items.id(c[0])) < int(c[1]):
			return false
	return int(o["uses"]) < int(o["max"])


static func pay(inv: Inventory, o: Dictionary) -> ItemStack:
	for c in [o["a"], o["b"]]:
		if not c.is_empty():
			inv.remove_item(Res.items.id(c[0]), int(c[1]))
	o["uses"] = int(o["uses"]) + 1
	var out := ItemStack.named(o["out"][0], int(o["out"][1]))
	if out.name() == "enchanted_book":
		Enchanting.load_all()
		var ids: Array = Enchanting.defs.keys()
		if not ids.is_empty():
			var id: String = ids[randi() % ids.size()]
			Enchanting.set_enchants(out, {id: 1 + randi() % int(Enchanting.defs[id]["max"])})
	return out


## Java VillagerData levels: novice -> apprentice (10 xp) -> journeyman (70) -> expert (150) -> master (250); each
## level-up adds two offers not yet sold by this villager (APPROXIMATE: drawn from the same per-profession table).
const LEVEL_XP := [0, 10, 70, 150, 250]
const LEVEL_NAMES := ["Novice", "Apprentice", "Journeyman", "Expert", "Master"]


static func on_trade(e, o: Dictionary, rng: RandomNumberGenerator = null) -> bool:
	if str(e.data.get("prof", "")) == "wandering_trader":
		return false
	var xp := int(e.data.get("vxp", 0)) + int(o.get("xp", 1))
	e.data["vxp"] = xp
	var lv := int(e.data.get("level", 1))
	if lv >= 5 or xp < int(LEVEL_XP[lv]):
		return false
	e.data["level"] = lv + 1
	var have := {}
	for of in e.data.get("offers", []):
		have[str(of["out"]) + str(of["a"])] = true
	var pool: Array = []
	for t in TABLE.get(str(e.data.get("prof", "")), []):
		if not have.has(str(t[2]) + str(t[0])):
			pool.append(t)
	var r := rng if rng != null else RandomNumberGenerator.new()
	for i in 2:
		if pool.is_empty():
			break
		var t: Array = pool.pop_at(r.randi_range(0, pool.size() - 1))
		(e.data["offers"] as Array).append({"a": t[0], "b": t[1], "out": t[2], "uses": 0, "max": t[3], "xp": t[4]})
	return true


static func restock(e) -> void:
	for o in e.data.get("offers", []):
		o["uses"] = 0
