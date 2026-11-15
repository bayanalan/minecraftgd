## Trading — villager and wandering trader offers from the installed version's data-driven trades (26.3):
## data/minecraft/trade_set/<profession>/level_<n>.json {amount, trades: #villager_trade tag} picks distinct
## data/minecraft/villager_trade/*.json {wants, additional_wants, gives, given_item_modifier, max_uses (default 4),
## xp (default 1), reputation_discount (price multiplier, default 0), merchant_predicate, double_trade_price_enchantments}
## (wiki: Villager trade definition, Trade set, Trading). Level 1 trades on assignment, the next level's set on each
## level-up (villager XP 10 / 70 / 150 / 250); the wandering trader takes buying (2), uncommon (2), common (5) and
## never restocks. Prices: the first cost = wants count + the modifiers' additional cost (doubled for
## double_trade_price_enchantments), capped at the item's stack size; demand raises it by floor(p * m * max(0, d)).
## Prices on the trade screen include the gossip reputation and Hero of the Village discounts (update_special_prices).
## Villagers start unemployed ("none") and take their profession by claiming a job site block (Villagers); explorer
## maps (exploration_map) are searched asynchronously (ExplorerMaps) and dropped when no structure is found.
## Offer: {a: [item, count], b: [item, count] or [], out: [item, count], uses, max, xp, id, base, mult, demand,
## acomp / bcomp (components the costs must carry), comp (components of the result)}.
## Contract: assign(e, rng) fills e.data {prof, offers}; can_pay/pay(inventory, offer); on_trade(e, offer); restock(e).
class_name Trading
extends RefCounted

const PROFESSIONS := ["farmer", "fisherman", "shepherd", "fletcher", "librarian", "cartographer", "cleric", "armorer",
	"weaponsmith", "toolsmith", "butcher", "leatherworker", "mason", "nitwit"]
## Java VillagerData levels (wiki: Trading): novice -> apprentice (10 xp) -> journeyman (70) -> expert (150) -> master (250).
const LEVEL_XP := [0, 10, 70, 150, 250]
const LEVEL_NAMES := ["Novice", "Apprentice", "Journeyman", "Expert", "Master"]
## wiki: Trade set — the wandering trader's three sets, in offer order.
const WANDERING_SETS := ["wandering_trader/buying", "wandering_trader/uncommon", "wandering_trader/common"]
const DYES := ["white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray", "light_gray", "cyan", "purple",
	"blue", "brown", "green", "red", "black"]

static var TABLE: Dictionary = {}     # profession -> every trade id of its five levels (data-driven; debug / tests)
static var _trades: Dictionary = {}   # trade id -> parsed villager_trade json (or null)
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	for prof in PROFESSIONS:
		var all: Array = []
		for lv in range(1, 6):
			for tid in _set_trades(_set_json("%s/level_%d" % [prof, lv])):
				if not all.has(tid):
					all.append(tid)
		TABLE[prof] = all
	var wt: Array = []
	for s in WANDERING_SETS:
		wt.append_array(_set_trades(_set_json(s)))
	TABLE["wandering_trader"] = wt


static func _set_json(set_name: String) -> Dictionary:
	var j = Res.read_json("data/minecraft/trade_set/%s.json" % set_name)
	return j if j is Dictionary else {}


## Trade ids of a trade set's "trades": a trade id, a #villager_trade tag or an array of ids.
static func _set_trades(sj: Dictionary) -> Array:
	var out: Array = []
	var t = sj.get("trades", [])
	var lst: Array = t if t is Array else [t]
	for v in lst:
		var s := str(v)
		if s.begins_with("#"):
			for k in Tags.resolve("villager_trade", s):
				out.append(str(k))
		elif s != "":
			out.append(s.trim_prefix("minecraft:"))
	return out


static func _trade_json(tid: String):
	if not _trades.has(tid):
		_trades[tid] = Res.read_json("data/minecraft/villager_trade/%s.json" % tid)
	return _trades[tid]


static func assign(e, rng: RandomNumberGenerator) -> void:
	load_all()
	# wiki Villager: new villagers are unemployed (minecraft:none) until they claim a job site block (Villagers.tick);
	# structure villagers bring their template's profession (nitwit / none: EntityManager._deser)
	var prof: String = "wandering_trader" if e.id == "wandering_trader" else "none"
	e.data["prof"] = prof
	e.data["offers"] = []
	if prof == "wandering_trader":
		for s in WANDERING_SETS:
			_add_set(e, s, rng)


## A villager takes a profession (claimed job site): level 1, no experience, the novice trade set.
static func set_profession(e, prof: String, rng: RandomNumberGenerator) -> void:
	load_all()
	e.data["prof"] = prof
	e.data["offers"] = []
	e.data["level"] = 1
	e.data["vxp"] = 0
	if prof != "none" and prof != "nitwit":
		_add_set(e, prof + "/level_1", rng)


## Adds `amount` distinct offers of a trade set (trades that are filtered out / discarded are skipped).
static func _add_set(e, set_name: String, rng: RandomNumberGenerator) -> void:
	var sj := _set_json(set_name)
	if sj.is_empty():
		return
	var offers: Array = e.data.get("offers", [])
	e.data["offers"] = offers
	var have := {}
	for of in offers:
		have[str(of.get("id", ""))] = true
	var pool: Array = []
	for tid in _set_trades(sj):
		if not have.has(tid):
			pool.append(tid)
	var amount := _int(sj.get("amount", 1), rng)
	var dup := bool(sj.get("allow_duplicates", false))
	var added := 0
	while added < amount and not pool.is_empty():
		var i := rng.randi_range(0, pool.size() - 1)
		var pick_id: String = pool[i]
		var o := _make_offer(pick_id, e, rng)
		if not dup or o.is_empty():
			pool.remove_at(i)
		if o.is_empty():
			continue
		offers.append(o)
		added += 1


static func _make_offer(tid: String, e, rng: RandomNumberGenerator) -> Dictionary:
	var j = _trade_json(tid)
	if not (j is Dictionary):
		return {}
	if j.has("merchant_predicate") and not _merchant_ok(j["merchant_predicate"], e):
		return {}
	var gives: Dictionary = j.get("gives", {}) if j.get("gives") is Dictionary else {}
	var wants: Dictionary = j.get("wants", {}) if j.get("wants") is Dictionary else {}
	var out_name := str(gives.get("id", "")).trim_prefix("minecraft:")
	var a_name := str(wants.get("id", "")).trim_prefix("minecraft:")
	if Res.items.id(out_name) <= 0 or Res.items.id(a_name) <= 0:
		return {}
	var out := ItemStack.named(out_name, maxi(_int(gives.get("count", 1), rng), 1))
	if gives.get("components") is Dictionary:
		out.components = (gives["components"] as Dictionary).duplicate(true)
	var extra := 0
	var mods = j.get("given_item_modifier", [])
	for m in (mods if mods is Array else [mods]):
		if not (m is Dictionary):
			continue
		var c := _modify(m, out, rng, e)
		if c < 0:
			return {}
		extra += c
	if extra > 0 and j.has("double_trade_price_enchantments") and _has_double_price(out, j["double_trade_price_enchantments"]):
		extra *= 2
	# wiki: Villager trade definition — costs below 1 remove the trade, costs above the max stack size are capped
	var base := mini(_int(wants.get("count", 1), rng) + extra, Res.items.max_stack[Res.items.id(a_name)])
	if base < 1:
		return {}
	var b: Array = []
	var bw = j.get("additional_wants")
	if bw is Dictionary:
		var b_name := str(bw.get("id", "")).trim_prefix("minecraft:")
		if Res.items.id(b_name) <= 0:
			return {}
		b = [b_name, maxi(_int(bw.get("count", 1), rng), 1)]
	var mx := maxi(_int(j.get("max_uses", 4), rng), 1)
	var o := {"a": [a_name, base], "b": b, "out": [out_name, out.count], "uses": 0, "max": mx,
		"xp": maxi(_int(j.get("xp", 1), rng), 0), "id": tid, "base": base,
		"mult": maxf(float(j.get("reputation_discount", 0.0)), 0.0),
		"demand": -2 * mx}   # wiki: Trading — "initially minus two times the number of times the villager has the trade in stock"
	if not out.components.is_empty():
		o["comp"] = out.components
	if wants.get("components") is Dictionary:
		o["acomp"] = (wants["components"] as Dictionary).duplicate(true)
	if bw is Dictionary and bw.get("components") is Dictionary:
		o["bcomp"] = (bw["components"] as Dictionary).duplicate(true)
	return o


## villager/variant entity predicate against the villager's biome type (e.data.vtype, set at spawn).
static func _merchant_ok(pred, e) -> bool:
	for p in (pred if pred is Array else [pred]):
		if not (p is Dictionary):
			continue
		var pp = p.get("predicate", {})
		var comps = pp.get("minecraft:predicates", {}) if pp is Dictionary else {}
		if comps is Dictionary and comps.has("minecraft:villager/variant"):
			var want = comps["minecraft:villager/variant"]
			var vt := "minecraft:" + str(e.data.get("vtype", "plains"))
			if not ((want is Array and (want as Array).has(vt)) or (want is String and want == vt)):
				return false
	return true


static func _has_double_price(out: ItemStack, spec) -> bool:
	var ids := {}
	for v in (spec if spec is Array else [spec]):
		var s := str(v)
		if s.begins_with("#"):
			ids.merge(Tags.resolve("enchantment", s))
		else:
			ids[s.trim_prefix("minecraft:")] = true
	var st = out.components.get("minecraft:stored_enchantments", {})
	if st is Dictionary:
		for k in st:
			if ids.has(str(k).trim_prefix("minecraft:")):
				return true
	return false


## Applies one given_item_modifier entry to `out`; returns its additional cost (>= 0) or -1 when the trade is discarded.
static func _modify(m: Dictionary, out: ItemStack, rng: RandomNumberGenerator, merchant = null) -> int:
	var tp := str(m.get("type", "")).trim_prefix("minecraft:")
	var add_cost := bool(m.get("include_additional_cost_component", false))
	match tp:
		"discard":
			return -1
		"filtered":
			if not _filter_ok(m.get("item_filter", {}), out):
				var f = m.get("on_fail")
				if f is Dictionary:
					return _modify(f, out, rng, merchant)
			elif m.get("modifier") is Dictionary:
				return _modify(m["modifier"], out, rng, merchant)
			return 0
		"enchant_with_levels":
			var lv := _int(m.get("levels", 1), rng)
			var opts: Array = []
			for k in Tags.resolve("enchantment", str(m.get("options", "#minecraft:in_enchanting_table"))):
				opts.append("minecraft:" + str(k))
			var r := RandomSources.LegacyRandom.new(rng.randi())
			var sel := Enchanting.select_from(r, out.name(), lv, opts)
			if not sel.is_empty():
				var e := Enchanting.get_enchants(out)
				for s in sel:
					e[s[0]] = s[1]
				Enchanting.set_enchants(out, e)
			return lv if add_cost else 0
		"enchant_randomly":
			Enchanting.load_all()
			var cands: Array = []
			for k2 in Tags.resolve("enchantment", str(m.get("options", "#minecraft:tradeable"))):
				var id := "minecraft:" + str(k2)
				if Enchanting.defs.has(id) and (out.name() == "enchanted_book" or out.name() == "book" or not bool(m.get("only_compatible", true)) or Enchanting._applies(id, out.name(), false)):
					cands.append(id)
			if cands.is_empty():
				return 0
			var pick: String = cands[rng.randi_range(0, cands.size() - 1)]
			var lvl := rng.randi_range(1, int(Enchanting.defs[pick]["max"]))
			var e2 := Enchanting.get_enchants(out)
			e2[pick] = lvl
			Enchanting.set_enchants(out, e2)
			# wiki: Trading — enchanted book price range 2 + 3 x level .. 6 + 13 x level (doubled for treasure later)
			return 2 + 3 * lvl + rng.randi_range(0, 4 + 10 * lvl) if add_cost else 0
		"set_random_dyes":
			var n := _int(m.get("number_of_dyes", 1), rng)
			if n > 0:
				var dyes: Array = []
				for i in n:
					dyes.append(DYES[rng.randi_range(0, DYES.size() - 1)])
				out.components["minecraft:dyed_color"] = SpecialRecipes.mix_dyes(int(out.components.get("minecraft:dyed_color", -1)), dyes)
			return 0
		"set_stew_effect":
			var effs: Array = m.get("effects", [])
			if not effs.is_empty():
				var ef: Dictionary = effs[rng.randi_range(0, effs.size() - 1)]
				# duration kept in the data's units (no consumer of the component yet)
				out.components["minecraft:suspicious_stew_effects"] = [{"id": str(ef.get("type", "")), "duration": _int(ef.get("duration", 1), rng)}]
			return 0
		"set_potion":
			out.components["minecraft:potion_contents"] = {"potion": str(m.get("id", "minecraft:water"))}
			return 0
		"set_random_potion":
			var pots: Array = Tags.resolve("potion", str(m.get("options", "#minecraft:tradeable"))).keys()
			if not pots.is_empty():
				out.components["minecraft:potion_contents"] = {"potion": "minecraft:" + str(pots[rng.randi_range(0, pots.size() - 1)])}
			return 0
		"exploration_map":
			# the map id at once, its target searched on a worker (ExplorerMaps); no world (tests): no map, and the
			# following filtered map_id / discard drops the trade as when nothing is found
			var mid := ExplorerMaps.begin(m, merchant)
			if mid >= 0:
				out.components["minecraft:map_id"] = mid
			return 0
	# other modifiers are not generated (a following filtered / discard drops the trade)
	return 0


static func _filter_ok(f, s: ItemStack) -> bool:
	if not (f is Dictionary):
		return true
	var items = f.get("items")
	if items != null:
		var names := {}
		for v in (items if items is Array else [items]):
			var sv := str(v)
			if sv.begins_with("#"):
				names.merge(Tags.items(sv))
			else:
				names[sv.trim_prefix("minecraft:")] = true
		if not names.has(s.name()):
			return false
	var preds = f.get("predicates", {})
	if preds is Dictionary:
		for k in preds:
			var key := str(k)
			if key == "minecraft:enchantments" or key == "minecraft:stored_enchantments":
				var en = s.components.get(key, {})
				if not (en is Dictionary) or (en as Dictionary).is_empty():
					return false
			elif not s.components.has(key):
				return false
	return true


## Number / int provider: constant, uniform {min, max}, binomial {n, p}, add {inputs}.
static func _int(v, rng: RandomNumberGenerator) -> int:
	if v is int or v is float:
		return int(v)
	if v is Dictionary:
		match str(v.get("type", "minecraft:constant")).trim_prefix("minecraft:"):
			"constant":
				return int(v.get("value", 0))
			"uniform":
				return rng.randi_range(_int(v.get("min", 0), rng), _int(v.get("max", 0), rng))
			"binomial":
				var k := 0
				var p := float(v.get("p", 0.5))
				for i in _int(v.get("n", 0), rng):
					if rng.randf() < p:
						k += 1
				return k
			"add":
				var sum := 0
				for x in v.get("inputs", []):
					sum += _int(x, rng)
				return sum
	return 0


static func _matches(st: ItemStack, item: int, comps) -> bool:
	if st.item != item:
		return false
	if comps is Dictionary:
		for k in comps:
			if str(st.components.get(k)) != str(comps[k]):
				return false
	return true


static func _count(inv: Inventory, name: String, comps) -> int:
	var id := Res.items.id(name)
	var n := 0
	for i in 36:
		var t: ItemStack = inv.slots[i]
		if _matches(t, id, comps):
			n += t.count
	return n


static func _take(inv: Inventory, name: String, n: int, comps) -> void:
	var id := Res.items.id(name)
	var left := n
	for i in 36:
		var t: ItemStack = inv.slots[i]
		if left > 0 and _matches(t, id, comps):
			var k := mini(t.count, left)
			t.count -= k
			left -= k
			if t.count <= 0:
				t.clear()
	inv.changed.emit()


# ------------------------------------------------------------------ reputation (wiki Villager: Gossiping)

## gossip type -> [gain, decay per 20 minutes, max, reputation multiplier] (wiki Villager gossip table)
const GOSSIP := {"trading": [4, 2, 25, 1], "major_positive": [20, 0, 20, 5], "minor_positive": [25, 1, 25, 1],
	"minor_negative": [25, 20, 200, -1], "major_negative": [25, 10, 100, -5]}


## A gossip event about the (single-player) player: trading (each trade), minor_negative (attacked), major_negative
## (a villager killed nearby), major / minor_positive (cured).
static func gossip(e, kind: String) -> void:
	if not GOSSIP.has(kind) or e == null or e.id != "villager":
		return
	var g: Dictionary = e.data.get("gossip", {})
	var spec: Array = GOSSIP[kind]
	g[kind] = mini(int(spec[2]), int(g.get(kind, 0)) + int(spec[0]))
	e.data["gossip"] = g


## wiki Villager: gossip decays every 20 minutes (24000 ticks) by the type's decay amount.
static func gossip_decay(e) -> void:
	var g = e.data.get("gossip")
	if not (g is Dictionary):
		return
	for k in (g as Dictionary).keys():
		var v := int(g[k]) - int(GOSSIP.get(k, [0, 0, 0, 0])[1])
		if v <= 0:
			(g as Dictionary).erase(k)
		else:
			g[k] = v


## Reputation = sum of each gossip value x its multiplier (wiki Villager).
static func reputation(e) -> int:
	var r := 0
	var g = e.data.get("gossip")
	if g is Dictionary:
		for k in g:
			r += int(g[k]) * int(GOSSIP.get(k, [0, 0, 0, 0])[3])
	return r


## Java Villager.updateSpecialPrices when the trade screen opens (wiki Trading price formula): - floor(m x reputation),
## and with Hero of the Village level h: - max(1, floor(p x (0.3 + 0.0625 x (h - 1)))) (p = the initial price, without
## the multiplier); reset_special_prices when it closes.
static func update_special_prices(e, p: Player) -> void:
	var rep := reputation(e)
	var h := 0
	if p != null and p.effects.has("hero_of_the_village"):
		h = int((p.effects["hero_of_the_village"] as Dictionary).get("amp", 0)) + 1
	for o in e.data.get("offers", []):
		var sp := -floori(float(o.get("mult", 0.0)) * rep)
		if h > 0:
			sp -= maxi(1, floori(float(o.get("base", o["a"][1])) * (0.3 + 0.0625 * (h - 1))))
		if sp != 0:
			o["special"] = sp
		else:
			o.erase("special")


static func reset_special_prices(e) -> void:
	for o in e.data.get("offers", []):
		o.erase("special")


## The first cost with the special price difference: min(max(cost + special, 1), stack size).
static func cost_a(o: Dictionary) -> int:
	if o["a"].is_empty():
		return 0
	var c := int(o["a"][1]) + int(o.get("special", 0))
	var it := Res.items.id(str(o["a"][0]))
	return clampi(c, 1, Res.items.max_stack[it] if it > 0 else 64)


static func can_pay(inv: Inventory, o: Dictionary) -> bool:
	if int(o["uses"]) >= int(o["max"]):
		return false
	if o.get("comp") is Dictionary and (o["comp"] as Dictionary).has("minecraft:map_id"):
		var mid := int(o["comp"]["minecraft:map_id"])
		if ExplorerMaps.pending(mid):
			ExplorerMaps.ensure(mid)   # (still searching for its structure: not for sale yet)
			return false
	if not o["a"].is_empty() and _count(inv, o["a"][0], o.get("acomp")) < cost_a(o):
		return false
	if not o["b"].is_empty() and _count(inv, o["b"][0], o.get("bcomp")) < int(o["b"][1]):
		return false
	return true


static func pay(inv: Inventory, o: Dictionary) -> ItemStack:
	if not o["a"].is_empty():
		_take(inv, o["a"][0], cost_a(o), o.get("acomp"))
	if not o["b"].is_empty():
		_take(inv, o["b"][0], int(o["b"][1]), o.get("bcomp"))
	o["uses"] = int(o["uses"]) + 1
	var out := ItemStack.named(o["out"][0], int(o["out"][1]))
	if o.get("comp") is Dictionary:
		out.components = (o["comp"] as Dictionary).duplicate(true)
	elif out.name() == "enchanted_book":
		# offers saved before trades were data-driven carry no components: roll a tradeable enchantment once
		Enchanting.load_all()
		var ids: Array = []
		for k in Tags.resolve("enchantment", "#minecraft:tradeable"):
			if Enchanting.defs.has("minecraft:" + str(k)):
				ids.append("minecraft:" + str(k))
		if not ids.is_empty():
			var id: String = ids[randi() % ids.size()]
			Enchanting.set_enchants(out, {id: 1 + randi() % int(Enchanting.defs[id]["max"])})
			o["comp"] = out.components.duplicate(true)
	return out


## Villager XP from a trade; levels up once the next threshold is reached and unlocks that level's trade set.
static func on_trade(e, o: Dictionary, rng: RandomNumberGenerator = null) -> bool:
	if str(e.data.get("prof", "")) == "wandering_trader":
		return false
	gossip(e, "trading")   # wiki Villager: each trade +4 trading gossip (max 25)
	var xp := int(e.data.get("vxp", 0)) + int(o.get("xp", 1))
	e.data["vxp"] = xp
	var lv := int(e.data.get("level", 1))
	if lv >= 5 or xp < int(LEVEL_XP[lv]):
		return false
	e.data["level"] = lv + 1
	load_all()
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	_add_set(e, "%s/level_%d" % [str(e.data.get("prof", "")), lv + 1], r)
	return true


## Restock (twice a day at work): demand += 2 x uses - max uses, then uses reset and the first cost is repriced
## min(max(floor(p * (m * max(0, demand) + 1)), 1), stack size) (wiki: Trading). Wandering traders never restock.
static func restock(e) -> void:
	if str(e.data.get("prof", "")) == "wandering_trader":
		return
	for o in e.data.get("offers", []):
		if o.has("base"):
			o["demand"] = int(o.get("demand", 0)) + 2 * int(o["uses"]) - int(o["max"])
			var p := int(o["base"])
			var price := floori(p * (float(o.get("mult", 0.0)) * maxf(0.0, float(o["demand"])) + 1.0))
			var it := Res.items.id(str(o["a"][0]))
			o["a"][1] = clampi(price, 1, Res.items.max_stack[it] if it > 0 else 64)
		o["uses"] = 0
