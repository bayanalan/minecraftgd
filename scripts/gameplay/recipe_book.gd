## RecipeBook — Java RecipeBookComponent essentials for the crafting grids: lists the recipes the player can craft
## right now with the items in the inventory plus the grid (craftable filter, the Java default after unlocking),
## and clicking one moves the ingredients into the grid in pattern order (current grid contents go back to the
## inventory first). APPROXIMATE: all recipes count as unlocked; no ghost recipes for uncraftable entries; no
## shift-click "craft as many as possible".
class_name RecipeBook
extends RefCounted


static func _available(inv: Inventory, grid: Array) -> Dictionary:
	var counts := {}
	for i in 36:
		var s := inv.get_slot(i)
		if not s.is_empty():
			counts[s.name()] = int(counts.get(s.name(), 0)) + s.count
	for s in grid:
		if s != null and not (s as ItemStack).is_empty():
			counts[(s as ItemStack).name()] = int(counts.get((s as ItemStack).name(), 0)) + (s as ItemStack).count
	return counts


## Greedy ingredient assignment; returns Array of item names per cell ("" for empty cells) or [] when impossible.
static func assign(cells: Array, counts: Dictionary) -> Array:
	var left := counts.duplicate()
	var out: Array = []
	for cell in cells:
		var c: Dictionary = cell
		if c.is_empty():
			out.append("")
			continue
		var best := ""
		var bn := 0
		for n in left:
			if int(left[n]) > bn and c.has(n):
				best = n
				bn = int(left[n])
		if best == "":
			return []
		left[best] = int(left[best]) - 1
		out.append(best)
	return out


## Recipes craftable in a gw x gh grid: Array of [recipe, cells (gw*gh list of ingredient dicts)].
static func craftable(inv: Inventory, grid: Array, gw: int, gh: int) -> Array:
	Crafting.load_all()
	var counts := _available(inv, grid)
	var out: Array = []
	var seen := {}
	for r in Crafting.shaped:
		if int(r["w"]) > gw or int(r["h"]) > gh:
			continue
		var cells: Array = []
		for y in gh:
			for x in gw:
				cells.append((r["cells"] as Array)[y * int(r["w"]) + x] if x < int(r["w"]) and y < int(r["h"]) else {})
		if not assign(cells, counts).is_empty() and not seen.has(r["id"]):
			seen[r["id"]] = true
			out.append([r, cells])
	for r2 in Crafting.shapeless:
		var ings: Array = r2["ings"]
		if ings.size() > gw * gh:
			continue
		var cells2: Array = ings.duplicate()
		while cells2.size() < gw * gh:
			cells2.append({})
		if not assign(cells2, counts).is_empty() and not seen.has(r2["id"]):
			seen[r2["id"]] = true
			out.append([r2, cells2])
	out.sort_custom(func(a, b): return str(a[0]["result"]) < str(b[0]["result"]))
	return out


## Java crafting recipe book tabs (RecipeBookCategories for the crafting table / inventory): search (all), equipment,
## building, misc, redstone, with their tab icons.
const TABS := [["", ["compass"]], ["equipment", ["iron_axe", "golden_sword"]], ["building", ["bricks"]],
	["misc", ["lava_bucket", "apple"]], ["redstone", ["redstone"]]]


## Every recipe that fits the grid, as [recipe, cells, craftable], filtered by tab category ("" = all), the
## craftable toggle and a search string (display name, case-insensitive); sorted by result name.
static func listing(inv: Inventory, grid: Array, gw: int, gh: int, cat: String, only_craftable: bool, query: String) -> Array:
	Crafting.load_all()
	var counts := _available(inv, grid)
	var q := query.strip_edges().to_lower()
	var out: Array = []
	var seen := {}
	var add := func(r: Dictionary, cells: Array):
		if seen.has(r["id"]):
			return
		if cat != "" and str(r.get("category", "misc")) != cat:
			return
		if q != "":
			var it := Res.items.id(str(r["result"])) if Res.items != null else -1
			var nm := Res.items.display_name(it).to_lower() if it >= 0 else str(r["result"])
			if not nm.contains(q):
				return
		var ok := not assign(cells, counts).is_empty()
		if only_craftable and not ok:
			return
		seen[r["id"]] = true
		out.append([r, cells, ok])
	for r in Crafting.shaped:
		if int(r["w"]) > gw or int(r["h"]) > gh:
			continue
		var cells: Array = []
		for y in gh:
			for x in gw:
				cells.append((r["cells"] as Array)[y * int(r["w"]) + x] if x < int(r["w"]) and y < int(r["h"]) else {})
		add.call(r, cells)
	for r2 in Crafting.shapeless:
		var ings: Array = r2["ings"]
		if ings.size() > gw * gh:
			continue
		var cells2: Array = ings.duplicate()
		while cells2.size() < gw * gh:
			cells2.append({})
		add.call(r2, cells2)
	out.sort_custom(func(a, b): return str(a[0]["result"]) < str(b[0]["result"]))
	return out


## Move the ingredients of entry ([recipe, cells]) into the grid via the callables. Returns true when filled.
static func fill(world, entry: Array, n: int, grid_get: Callable, grid_set: Callable) -> bool:
	var inv: Inventory = world.player.inventory
	for i in n:
		var s: ItemStack = grid_get.call(i)
		if s != null and not s.is_empty():
			var left := inv.add(s)
			if left > 0:
				s.count = left
				world.entities.spawn_item(world.player.eye_pos(), s.copy())
			grid_set.call(i, ItemStack.new())
	var counts := _available(inv, [])
	var names := assign(entry[1], counts)
	if names.is_empty():
		return false
	for i in names.size():
		if names[i] == "":
			continue
		var id := Res.items.id(str(names[i]))
		if inv.remove_item(id, 1) <= 0:
			continue
		grid_set.call(i, ItemStack.of(id, 1))
	world.inv_changed()
	return true
