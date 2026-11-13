## SpecialRecipes — 26.x data-driven custom crafting recipes (Java CustomRecipe subclasses), parameters read from
## data/minecraft/recipe/*.json:
## - crafting_transmute (bundle / shulker box recolouring: input + material -> result keeping components)
## - crafting_dye (leather armour: DyedItemColor.applyDyes averaging with the existing colour)
## - crafting_imbue (tipped arrows: 8 arrows around a lingering potion)
## - crafting_special_firework_rocket / _firework_star / _firework_star_fade (FireworkRocketRecipe etc.)
## - crafting_special_bannerduplicate, _bookcloning (the source stays in the grid), _repairitem, _shielddecoration
## - crafting_decorated_pot (back / left / right / front in the 3x3 plus shape)
## APPROXIMATE: map extending (no map scales yet) is not supported.
class_name SpecialRecipes
extends RefCounted

## Java DyeColor.textureDiffuseColor and fireworkColor.
const DYE_RGB := {"white": 0xF9FFFE, "orange": 0xF9801D, "magenta": 0xC74EBD, "light_blue": 0x3AB3DA, "yellow": 0xFED83D,
	"lime": 0x80C71F, "pink": 0xF38BAA, "gray": 0x474F52, "light_gray": 0x9D9D97, "cyan": 0x169C9C, "purple": 0x8932B8,
	"blue": 0x3C44AA, "brown": 0x835432, "green": 0x5E7C16, "red": 0xB02E26, "black": 0x1D1D21}
const FIREWORK_RGB := {"white": 0xF0F0F0, "orange": 0xEB8844, "magenta": 0xC354CD, "light_blue": 0x6689D3, "yellow": 0xDECF2A,
	"lime": 0x41CD34, "pink": 0xD88198, "gray": 0x434343, "light_gray": 0xABABAB, "cyan": 0x287697, "purple": 0x7B2FBE,
	"blue": 0x253192, "brown": 0x51301A, "green": 0x3B511A, "red": 0xB3312C, "black": 0x1E1B1B}

static var recipes: Array = []


static func _ing(v) -> Dictionary:
	return Crafting._ingredient(v) if v != null else {}


static func _items(grid: Array) -> Array:
	var out: Array = []
	for i in grid.size():
		var s = grid[i]
		if s != null and not (s as ItemStack).is_empty():
			out.append(i)
	return out


static func _result_id(j: Dictionary, fallback: String = "") -> String:
	var r = j.get("result", {})
	if r is Dictionary:
		return str(r.get("id", fallback)).trim_prefix("minecraft:")
	return fallback


## Returns {result: ItemStack, keep: Array[int]} or {}.
static func match(grid: Array, gw: int, gh: int) -> Dictionary:
	var idx := _items(grid)
	if idx.is_empty():
		return {}
	for j in recipes:
		var tp := str(j.get("type", "")).trim_prefix("minecraft:")
		var r := {}
		match tp:
			"crafting_transmute":
				r = _transmute(j, grid, idx)
			"crafting_dye":
				r = _dye(j, grid, idx)
			"crafting_imbue":
				r = _imbue(j, grid, gw, gh)
			"crafting_special_firework_rocket":
				r = _rocket(j, grid, idx)
			"crafting_special_firework_star":
				r = _star(j, grid, idx)
			"crafting_special_firework_star_fade":
				r = _star_fade(j, grid, idx)
			"crafting_special_bannerduplicate":
				r = _banner_dup(j, grid, idx)
			"crafting_special_bookcloning":
				r = _book_clone(j, grid, idx)
			"crafting_special_repairitem":
				r = _repair(grid, idx)
			"crafting_special_shielddecoration":
				r = _shield(j, grid, idx)
			"crafting_decorated_pot":
				r = _pot(j, grid, gw, gh)
		if not r.is_empty():
			return r
	return {}


static func _transmute(j: Dictionary, grid: Array, idx: Array) -> Dictionary:
	if idx.size() != 2:
		return {}
	var inp := _ing(j.get("input"))
	var mat := _ing(j.get("material"))
	var a: ItemStack = grid[idx[0]]
	var b: ItemStack = grid[idx[1]]
	if not inp.has(a.name()):
		var t := a
		a = b
		b = t
	if not inp.has(a.name()) or not mat.has(b.name()):
		return {}
	var rid := _result_id(j)
	if rid == "" or rid == a.name():
		return {}
	var out := ItemStack.named(rid, 1)
	out.components = a.components.duplicate(true)
	out.damage = a.damage
	return {"result": out, "keep": []}


static func _dye_name(s: ItemStack) -> String:
	return s.name().trim_suffix("_dye") if s.name().ends_with("_dye") else ""


## Java DyedItemColor.applyDyes.
static func mix_dyes(existing: int, dyes: Array) -> int:
	var tr := 0
	var tg := 0
	var tb := 0
	var maxsum := 0
	var n := 0
	if existing >= 0:
		var er := (existing >> 16) & 255
		var eg := (existing >> 8) & 255
		var eb := existing & 255
		maxsum += maxi(er, maxi(eg, eb))
		tr += er
		tg += eg
		tb += eb
		n += 1
	for d in dyes:
		var c: int = DYE_RGB.get(d, 0xFFFFFF)
		var r := (c >> 16) & 255
		var g := (c >> 8) & 255
		var b := c & 255
		maxsum += maxi(r, maxi(g, b))
		tr += r
		tg += g
		tb += b
		n += 1
	if n == 0:
		return existing
	var ar := tr / n
	var ag := tg / n
	var ab := tb / n
	var avgmax := float(maxsum) / n
	var mx := float(maxi(ar, maxi(ag, ab)))
	if mx <= 0.0:
		return 0
	ar = int(ar * avgmax / mx)
	ag = int(ag * avgmax / mx)
	ab = int(ab * avgmax / mx)
	return (ar << 16) | (ag << 8) | ab


static func _dye(j: Dictionary, grid: Array, idx: Array) -> Dictionary:
	var target := _ing(j.get("target"))
	var dye := _ing(j.get("dye"))
	var tgt: ItemStack = null
	var dyes: Array = []
	for i in idx:
		var s: ItemStack = grid[i]
		if target.has(s.name()) and tgt == null:
			tgt = s
		elif dye.has(s.name()) and _dye_name(s) != "":
			dyes.append(_dye_name(s))
		else:
			return {}
	if tgt == null or dyes.is_empty():
		return {}
	var out := tgt.copy()
	out.count = 1
	out.components["minecraft:dyed_color"] = mix_dyes(int(tgt.components.get("minecraft:dyed_color", -1)), dyes)
	return {"result": out, "keep": []}


static func _imbue(j: Dictionary, grid: Array, gw: int, gh: int) -> Dictionary:
	if gw != 3 or gh != 3:
		return {}
	var mat := _ing(j.get("material"))
	var src := _ing(j.get("source"))
	for i in 9:
		var s = grid[i]
		if s == null or (s as ItemStack).is_empty():
			return {}
		if i == 4:
			if not src.has((s as ItemStack).name()):
				return {}
		elif not mat.has((s as ItemStack).name()):
			return {}
	var r = j.get("result", {})
	var out := ItemStack.named(_result_id(j, "tipped_arrow"), int((r as Dictionary).get("count", 8)) if r is Dictionary else 8)
	var pc = (grid[4] as ItemStack).components.get("minecraft:potion_contents")
	if pc != null:
		out.components["minecraft:potion_contents"] = pc
	return {"result": out, "keep": []}


static func _rocket(j: Dictionary, grid: Array, idx: Array) -> Dictionary:
	var shell := _ing(j.get("shell"))
	var fuel := _ing(j.get("fuel"))
	var star := _ing(j.get("star"))
	var n_shell := 0
	var n_fuel := 0
	var exps: Array = []
	for i in idx:
		var s: ItemStack = grid[i]
		if shell.has(s.name()):
			n_shell += 1
		elif fuel.has(s.name()):
			n_fuel += 1
		elif star.has(s.name()):
			var e = s.components.get("minecraft:firework_explosion")
			if e is Dictionary:
				exps.append(e)
		else:
			return {}
	if n_shell != 1 or n_fuel < 1 or n_fuel > 3:
		return {}
	var r = j.get("result", {})
	var out := ItemStack.named(_result_id(j, "firework_rocket"), int((r as Dictionary).get("count", 3)) if r is Dictionary else 3)
	out.components["minecraft:fireworks"] = {"flight_duration": n_fuel, "explosions": exps}
	return {"result": out, "keep": []}


static func _star(j: Dictionary, grid: Array, idx: Array) -> Dictionary:
	var fuel := _ing(j.get("fuel"))
	var dye := _ing(j.get("dye"))
	var trail := _ing(j.get("trail"))
	var twinkle := _ing(j.get("twinkle"))
	var shapes: Dictionary = j.get("shapes", {})
	var n_fuel := 0
	var colors: Array = []
	var shape := "small_ball"
	var has_shape := false
	var has_trail := false
	var has_twinkle := false
	for i in idx:
		var s: ItemStack = grid[i]
		var nm := s.name()
		if fuel.has(nm):
			n_fuel += 1
		elif dye.has(nm) and _dye_name(s) != "":
			colors.append(FIREWORK_RGB.get(_dye_name(s), 0xFFFFFF))
		elif trail.has(nm):
			if has_trail:
				return {}
			has_trail = true
		elif twinkle.has(nm):
			if has_twinkle:
				return {}
			has_twinkle = true
		else:
			var found := ""
			for sk in shapes:
				if _ing(shapes[sk]).has(nm):
					found = str(sk)
			if found == "" or has_shape:
				return {}
			has_shape = true
			shape = found
	if n_fuel != 1 or colors.is_empty():
		return {}
	var out := ItemStack.named(_result_id(j, "firework_star"), 1)
	out.components["minecraft:firework_explosion"] = {"shape": shape, "colors": colors, "fade_colors": [], "has_trail": has_trail, "has_twinkle": has_twinkle}
	return {"result": out, "keep": []}


static func _star_fade(j: Dictionary, grid: Array, idx: Array) -> Dictionary:
	var target := _ing(j.get("target"))
	var dye := _ing(j.get("dye"))
	var st: ItemStack = null
	var fades: Array = []
	for i in idx:
		var s: ItemStack = grid[i]
		if target.has(s.name()) and st == null:
			st = s
		elif dye.has(s.name()) and _dye_name(s) != "":
			fades.append(FIREWORK_RGB.get(_dye_name(s), 0xFFFFFF))
		else:
			return {}
	if st == null or fades.is_empty() or not (st.components.get("minecraft:firework_explosion") is Dictionary):
		return {}
	var out := st.copy()
	out.count = 1
	var e: Dictionary = (st.components["minecraft:firework_explosion"] as Dictionary).duplicate(true)
	e["fade_colors"] = fades
	out.components["minecraft:firework_explosion"] = e
	return {"result": out, "keep": []}


static func _banner_dup(j: Dictionary, grid: Array, idx: Array) -> Dictionary:
	if idx.size() != 2:
		return {}
	var ban := _ing(j.get("banner"))
	var a: ItemStack = grid[idx[0]]
	var b: ItemStack = grid[idx[1]]
	if not ban.has(a.name()) or a.name() != b.name():
		return {}
	var la := Banners.layers(a).size()
	var lb := Banners.layers(b).size()
	if (la == 0) == (lb == 0):
		return {}
	var src_i: int = idx[0] if la > 0 else idx[1]
	var out := (grid[src_i] as ItemStack).copy()
	out.count = 1
	return {"result": out, "keep": [src_i]}


static func _book_clone(j: Dictionary, grid: Array, idx: Array) -> Dictionary:
	var src := _ing(j.get("source"))
	var mat := _ing(j.get("material"))
	var book_i := -1
	var n := 0
	for i in idx:
		var s: ItemStack = grid[i]
		if src.has(s.name()) and book_i < 0:
			book_i = i
		elif mat.has(s.name()):
			n += 1
		else:
			return {}
	if book_i < 0 or n < 1:
		return {}
	var book: ItemStack = grid[book_i]
	var content = book.components.get("minecraft:written_book_content", {})
	var gen := int((content as Dictionary).get("generation", 0)) if content is Dictionary else 0
	if gen >= 2:
		return {}
	var out := book.copy()
	out.count = n
	var c2: Dictionary = (content as Dictionary).duplicate(true) if content is Dictionary else {}
	c2["generation"] = gen + 1
	out.components["minecraft:written_book_content"] = c2
	return {"result": out, "keep": [book_i]}


## Java RepairItemRecipe: two damaged copies of the same item -> summed durability + 5% of max; enchantments dropped
## (curses kept).
static func _repair(grid: Array, idx: Array) -> Dictionary:
	if idx.size() != 2:
		return {}
	var a: ItemStack = grid[idx[0]]
	var b: ItemStack = grid[idx[1]]
	var md: int = Res.items.max_damage[a.item]
	if a.item != b.item or md <= 0 or a.count != 1 or b.count != 1:
		return {}
	var left := (md - a.damage) + (md - b.damage) + int(md * 5 / 100)
	var out := ItemStack.of(a.item, 1)
	out.damage = maxi(0, md - left)
	var curses := {}
	for s in [a, b]:
		var en = (s as ItemStack).components.get("minecraft:enchantments", {})
		if en is Dictionary:
			for k in en:
				if str(k).contains("curse"):
					curses[k] = maxi(int(curses.get(k, 0)), int(en[k]))
	if not curses.is_empty():
		out.components["minecraft:enchantments"] = curses
	return {"result": out, "keep": []}


static func _shield(j: Dictionary, grid: Array, idx: Array) -> Dictionary:
	if idx.size() != 2:
		return {}
	var target := _ing(j.get("target"))
	var ban := _ing(j.get("banner"))
	var sh: ItemStack = null
	var bn: ItemStack = null
	for i in idx:
		var s: ItemStack = grid[i]
		if target.has(s.name()):
			sh = s
		elif ban.has(s.name()):
			bn = s
	if sh == null or bn == null or sh.components.has("minecraft:base_color"):
		return {}
	var out := sh.copy()
	out.count = 1
	out.components["minecraft:base_color"] = bn.name().trim_suffix("_banner")
	if not Banners.layers(bn).is_empty():
		out.components["minecraft:banner_patterns"] = Banners.layers(bn).duplicate(true)
	return {"result": out, "keep": []}


static func _pot(j: Dictionary, grid: Array, gw: int, gh: int) -> Dictionary:
	if gw != 3 or gh != 3:
		return {}
	var spots := {1: "back", 3: "left", 5: "right", 7: "front"}
	var deco: Array = []
	for i in 9:
		var s = grid[i]
		var empty: bool = s == null or (s as ItemStack).is_empty()
		if spots.has(i):
			if empty or not _ing(j.get(spots[i])).has((s as ItemStack).name()):
				return {}
		elif not empty:
			return {}
	for i in [1, 3, 5, 7]:
		deco.append((grid[i] as ItemStack).name())
	var out := ItemStack.named(_result_id(j, "decorated_pot"), 1)
	out.components["minecraft:pot_decorations"] = deco
	return {"result": out, "keep": []}
