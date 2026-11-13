## Loot — data-driven loot table evaluator for the installed version's data/minecraft/loot_table/*.json
## (pools, rolls, entries item/alternatives/group/sequence/loot_table/empty/tag, weights, conditions
## survives_explosion/match_tool(silk touch, items)/random_chance/table_bonus/block_state_property/
## inverted/any_of/all_of, functions set_count/apply_bonus/explosion_decay/limit_count/set_damage).
## Contract: block_drops(state, tool, world, pos) -> Array[ItemStack]; roll(table_id, ctx) -> Array[ItemStack].
## Placeholder mode or missing tables fall back to "drops itself".
class_name Loot

static var _cache: Dictionary = {}


static func table(id: String):
	if _cache.has(id):
		return _cache[id]
	var j = Res.read_json("data/minecraft/loot_table/" + id.trim_prefix("minecraft:") + ".json")
	_cache[id] = j
	return j


## be: block entity data captured before removal (copy_components source); looked up from the world when empty.
static func block_drops(st: int, tool: ItemStack, world, pos: Vector3i, be: Dictionary = {}) -> Array:
	var blocks := Res.blocks
	var name := blocks.name_of(st)
	var info: Dictionary = blocks.block_info[blocks.st_block[st]]
	if be.is_empty() and world != null and world.get("cm") != null:
		be = BlockEntities.get_data(world, pos)
	var ctx := {"tool": tool, "state": st, "rng": world.rng if world != null else RandomNumberGenerator.new(), "explosion": false, "pos": pos, "block_entity": be}
	if bool(info["requires_tool"]) and not Interaction.correct_tool(tool, st):
		return []
	var t = table("blocks/" + name)
	if t is Dictionary:
		return roll_table(t, ctx)
	if Res.mode == "vanilla":
		return []
	if not bool(info["drops_self"]):
		return []
	var it := Res.items.id(name)
	return [ItemStack.of(it, 1)] if it > 0 else []


static func roll(id: String, ctx: Dictionary) -> Array:
	var t = table(id)
	return roll_table(t, ctx) if t is Dictionary else []


static func roll_table(t: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	for pool in t.get("pools", []):
		if not _conds(_entry_conds(pool), ctx):
			continue
		var rolls := _int(pool.get("rolls", 1), ctx) + int(floor(_num(pool.get("bonus_rolls", 0.0), ctx) * _ench(ctx.get("tool"), "luck_of_the_sea")))
		for r in rolls:
			var before := out.size()
			_pick_entries(pool.get("entries", []), ctx, out)
			for k in range(before, out.size()):
				for pfn in _mods(pool):
					if out[k] != null:
						out[k] = _apply_fn(pfn, out[k], ctx)
	var res: Array = []
	for s in out:
		if s == null:
			continue
		for fn in _mods(t):
			s = _apply_fn(fn, s, ctx)
		if s != null and not s.is_empty():
			res.append(s)
	return res


static func _pick_entries(entries: Array, ctx: Dictionary, out: Array) -> void:
	var cands: Array = []
	var total := 0
	for e in entries:
		_expand(e, ctx, cands)
	for c in cands:
		total += int(c.get("weight", 1))
	if total <= 0:
		return
	var rng: RandomNumberGenerator = ctx["rng"]
	var r := rng.randi_range(0, total - 1)
	for c in cands:
		r -= int(c.get("weight", 1))
		if r < 0:
			_emit(c, ctx, out)
			return


## Expand composite entries (alternatives/group/sequence) into a list of leaf entries.
static func _expand(e: Dictionary, ctx: Dictionary, cands: Array) -> void:
	if not _conds(_entry_conds(e), ctx):
		return
	var tp := str(e.get("type", "minecraft:item")).trim_prefix("minecraft:")
	match tp:
		"alternatives":
			for ch in e.get("children", []):
				if _conds(_entry_conds(ch), ctx):
					_expand(ch, ctx, cands)
					return
		"group":
			for ch in e.get("children", []):
				_expand(ch, ctx, cands)
		"sequence":
			for ch in e.get("children", []):
				if not _conds(_entry_conds(ch), ctx):
					return
				_expand(ch, ctx, cands)
		_:
			cands.append(e)


static func _emit(e: Dictionary, ctx: Dictionary, out: Array) -> void:
	var tp := str(e.get("type", "minecraft:item")).trim_prefix("minecraft:")
	var stacks: Array = []
	match tp:
		"item":
			var it := Res.items.id(str(e.get("name", "")))
			if it > 0:
				stacks.append(ItemStack.of(it, 1))
		"loot_table":
			var v = e.get("value", e.get("name", ""))
			if v is String:
				stacks.append_array(roll(v, ctx))
			elif v is Dictionary:
				stacks.append_array(roll_table(v, ctx))
		"tag":
			for n in Tags.items(str(e.get("name", ""))):
				var it2 := Res.items.id(n)
				if it2 > 0:
					stacks.append(ItemStack.of(it2, 1))
					if not bool(e.get("expand", false)):
						break
		_:
			pass
	for s in stacks:
		var cur = s
		for fn in _mods(e):
			if cur == null:
				break
			cur = _apply_fn(fn, cur, ctx)
		if cur != null and not cur.is_empty():
			out.append(cur)


## Java NumberProvider.getInt: uniform -> inclusive integer range, others rounded.
static func _int(v, ctx: Dictionary) -> int:
	if v is Dictionary and str(v.get("type", "minecraft:uniform")).trim_prefix("minecraft:") == "uniform":
		var rng: RandomNumberGenerator = ctx["rng"]
		return rng.randi_range(int(floor(_num(v.get("min", 0), ctx))), int(floor(_num(v.get("max", 1), ctx))))
	return int(round(_num(v, ctx)))


static func _num(v, ctx: Dictionary) -> float:
	if v is float or v is int:
		return float(v)
	if v is Dictionary:
		var rng: RandomNumberGenerator = ctx["rng"]
		var tp := str(v.get("type", "minecraft:uniform")).trim_prefix("minecraft:")
		match tp:
			"uniform":
				return rng.randf_range(_num(v.get("min", 0), ctx), _num(v.get("max", 1), ctx))
			"constant":
				return _num(v.get("value", 0), ctx)
			"binomial":
				var n := int(_num(v.get("n", 1), ctx))
				var p := _num(v.get("p", 0.5), ctx)
				var k := 0
				for i in n:
					if rng.randf() < p:
						k += 1
				return k
	return 0.0


static func _ench(tool: ItemStack, id: String) -> int:
	if tool == null or tool.is_empty():
		return 0
	var e = tool.components.get("minecraft:enchantments", {})
	if e is Dictionary:
		return int(e.get("minecraft:" + id, e.get(id, 0)))
	return 0


## Conditions of a pool / entry / function object. 26.x uses a single "condition" (string predicate reference or
## object); older versions a "conditions" list. (On these objects "condition" is never the old condition-type key.)
static func _entry_conds(e: Dictionary) -> Array:
	var out: Array = e.get("conditions", []).duplicate() if e.get("conditions") is Array else []
	if e.has("condition") and (e["condition"] is String or e["condition"] is Dictionary):
		out.append(e["condition"])
	return out


## Item modifiers of a table / pool / entry: 26.x "modifier" (object or list), older "functions" list.
static func _mods(o: Dictionary) -> Array:
	var out: Array = []
	if o.get("functions") is Array:
		out.append_array(o["functions"])
	var m = o.get("modifier", o.get("modifiers", null))
	if m is Array:
		out.append_array(m)
	elif m is Dictionary:
		out.append(m)
	elif m is String:
		var mj = Res.read_json("data/minecraft/item_modifier/" + str(m).trim_prefix("minecraft:") + ".json")
		if mj is Array:
			out.append_array(mj)
		elif mj is Dictionary:
			out.append(mj)
	return out


## Java LevelBasedValue.
static func _level_value(v, lvl: int) -> float:
	if v is float or v is int:
		return float(v)
	if not (v is Dictionary):
		return 0.0
	match str(v.get("type", "")).trim_prefix("minecraft:"):
		"linear":
			return float(v.get("base", 0.0)) + float(v.get("per_level_above_first", 0.0)) * (lvl - 1)
		"constant":
			return float(v.get("value", 0.0))
		"clamped":
			return clampf(_level_value(v.get("value", 0.0), lvl), float(v.get("min", 0.0)), float(v.get("max", 1.0)))
		"fraction":
			var den := _level_value(v.get("denominator", 1.0), lvl)
			return 0.0 if den == 0.0 else _level_value(v.get("numerator", 0.0), lvl) / den
		"levels_squared":
			return float(lvl * lvl) + float(v.get("added", 0.0))
		"lookup":
			var vals: Array = v.get("values", [])
			return float(vals[lvl - 1]) if lvl - 1 < vals.size() else _level_value(v.get("fallback", 0.0), lvl)
	return 0.0


## Java EntityPredicate subset for the dying entity (ctx: on_fire, baby, entity_id, vehicle_id) and its killer's weapon.
static func _entity_pred(pred, ctx: Dictionary, who: String) -> bool:
	if not (pred is Dictionary):
		return true
	for k in pred:
		var key := str(k).trim_prefix("minecraft:")
		var v = pred[k]
		match key:
			"flags":
				for fk in v:
					var want := bool(v[fk])
					var have := false
					match str(fk):
						"is_on_fire":
							have = bool(ctx.get("on_fire", false))
						"is_baby":
							have = bool(ctx.get("baby", false))
						_:
							have = false
					if have != want:
						return false
			"entity_type", "type":
				var ids: String = str(v)
				var mine := "minecraft:" + str(ctx.get("entity_id" if who == "this" else "killer_id", ""))
				if ids.begins_with("#"):
					return false
				if ids != mine:
					return false
			"type_specific/fishing_hook":
				if v.has("in_open_water") and bool(ctx.get("open_water", true)) != bool(v["in_open_water"]):
					return false
			"type_specific/cube_mob":
				var sz = v.get("size", null)
				var have_sz := int(ctx.get("size", 1))
				if (sz is float or sz is int) and have_sz != int(sz):
					return false
				if sz is Dictionary and (have_sz < int(sz.get("min", -999)) or have_sz > int(sz.get("max", 999))):
					return false
			"type_specific/raider":
				if v.has("is_captain") and bool(ctx.get("captain", false)) != bool(v["is_captain"]):
					return false
			"type_specific/sheep":
				if v.has("sheared") and bool(ctx.get("sheared", false)) != bool(v["sheared"]):
					return false
			"components":
				for ck in v:
					if str(ck).trim_prefix("minecraft:") == "sheep/color":
						if str(ctx.get("sheep_color", "white")) != str(v[ck]):
							return false
					else:
						return false
			"vehicle":
				if not ctx.has("vehicle_id"):
					return false
				var sub := {}
				sub["entity_id"] = ctx["vehicle_id"]
				if not _entity_pred(v, sub, "this"):
					return false
			"equipment":
				var mh = v.get("mainhand", null)
				if mh is Dictionary:
					var en = mh.get("predicates", {}).get("minecraft:enchantments", null)
					if en is Array:
						for e2 in en:
							var ref := str((e2 as Dictionary).get("enchantments", ""))
							if ref == "#minecraft:smelts_loot":
								if _ench(ctx.get("tool"), "fire_aspect") <= 0:
									return false
							elif _ench(ctx.get("tool"), ref.trim_prefix("minecraft:")) <= 0:
								return false
			_:
				return false   # unknown predicate parts: treat as not matching (rare drops stay rare)
	return true


static func _conds(conds: Array, ctx: Dictionary) -> bool:
	for c in conds:
		if not _cond(c, ctx):
			return false
	return true


static func _cond(c, ctx: Dictionary) -> bool:
	if c is String:
		# 26.x shorthand predicate reference, e.g. "minecraft:tool/can_silk_touch"
		var cs := str(c).trim_prefix("minecraft:")
		if cs.contains("silk_touch"):
			return _ench(ctx["tool"], "silk_touch") > 0
		if cs.contains("shears") or cs.contains("shear"):
			var t: ItemStack = ctx["tool"]
			return t != null and not t.is_empty() and t.name() == "shears"
		var pj = Res.read_json("data/minecraft/predicate/" + cs + ".json")
		return _cond(pj, ctx) if pj is Dictionary else false
	if not (c is Dictionary):
		return true
	var tp := str(c.get("condition", c.get("type", ""))).trim_prefix("minecraft:")
	var rng: RandomNumberGenerator = ctx["rng"]
	match tp:
		"survives_explosion":
			# Java ExplosionCondition: survives with probability 1 / explosion radius
			return not ctx.get("explosion", false) or rng.randf() <= 1.0 / maxf(float(ctx.get("explosion_radius", 4.0)), 1.0)
		"random_chance":
			return rng.randf() < _num(c.get("chance", 1.0), ctx)
		"inverted":
			return not _cond(c.get("term", {}), ctx)
		"any_of", "alternative":
			for t in c.get("terms", []):
				if _cond(t, ctx):
					return true
			return false
		"all_of":
			for t in c.get("terms", []):
				if not _cond(t, ctx):
					return false
			return true
		"match_tool":
			var pred = c.get("predicate", {})
			var tool: ItemStack = ctx["tool"]
			if pred is Dictionary:
				if pred.has("items"):
					if tool == null or tool.is_empty():
						return false
					var items = pred["items"]
					var nm := "minecraft:" + tool.name()
					if items is String:
						if items.begins_with("#"):
							return Tags.items(items.substr(1)).has(tool.name())
						return items == nm
					if items is Array:
						return items.has(nm)
				var ench = pred.get("predicates", {}).get("minecraft:enchantments", pred.get("enchantments", null))
				if ench is Array:
					for en in ench:
						var eid := str(en.get("enchantments", "")).trim_prefix("minecraft:")
						if _ench(tool, eid) <= 0:
							return false
			return true
		"table_bonus":
			var lvl := _ench(ctx["tool"], str(c.get("enchantment", "")).trim_prefix("minecraft:"))
			var ch: Array = c.get("chances", [0.0])
			return rng.randf() < float(ch[mini(lvl, ch.size() - 1)])
		"block_state_property":
			var props: Dictionary = c.get("properties", {})
			var st: int = ctx.get("state", 0)
			for k in props:
				var want = props[k]
				var have := Res.blocks.get_prop(st, k)
				if want is String and have != want:
					return false
				if want is Dictionary:
					var hv := int(have)
					if want.has("min") and hv < int(want["min"]):
						return false
					if want.has("max") and hv > int(want["max"]):
						return false
			return true
		"killed_by_player":
			return ctx.get("by_player", false)
		"random_chance_with_enchanted_bonus":
			var lvl2 := _ench(ctx.get("tool"), str(c.get("enchantment", "minecraft:looting")).trim_prefix("minecraft:"))
			var chance := float(c.get("unenchanted_chance", 0.0)) if lvl2 <= 0 else _level_value(c.get("enchanted_chance", 0.0), lvl2)
			return rng.randf() < chance
		"random_chance_with_looting":
			var lvl3 := _ench(ctx.get("tool"), "looting")
			return rng.randf() < float(c.get("chance", 0.0)) + lvl3 * float(c.get("looting_multiplier", 0.0))
		"entity_properties":
			return _entity_pred(c.get("predicate", {}), ctx, str(c.get("entity", "this")))
		"damage_source_properties":
			return false
		"location_check", "weather_check", "time_check":
			return true
	return true


static func _apply_fn(fn: Dictionary, s: ItemStack, ctx: Dictionary) -> ItemStack:
	if not _conds(_entry_conds(fn), ctx):
		return s
	var tp := str(fn.get("function", fn.get("type", ""))).trim_prefix("minecraft:")
	var rng: RandomNumberGenerator = ctx["rng"]
	match tp:
		"set_count":
			var n := _int(fn.get("count", 1), ctx)
			if fn.get("add", false):
				s.count += n
			else:
				s.count = n
		"apply_bonus":
			var lvl := _ench(ctx["tool"], str(fn.get("enchantment", "")).trim_prefix("minecraft:"))
			var formula := str(fn.get("formula", "")).trim_prefix("minecraft:")
			var p: Dictionary = fn.get("parameters", {})
			if lvl > 0:
				match formula:
					"ore_drops":
						var k := rng.randi_range(0, lvl + 1) - 1
						s.count *= maxi(0, k) + 1
					"uniform_bonus_count":
						s.count += rng.randi_range(0, int(p.get("bonusMultiplier", 1)) * lvl)
					"binomial_with_bonus_count":
						for i in lvl + int(p.get("extra", 0)):
							if rng.randf() < float(p.get("probability", 0.5)):
								s.count += 1
		"explosion_decay":
			if ctx.get("explosion", false):
				# Java ApplyExplosionDecay: each item survives with probability 1 / explosion radius
				var keep := 0
				var pr := 1.0 / maxf(float(ctx.get("explosion_radius", 4.0)), 1.0)
				for i in s.count:
					if rng.randf() <= pr:
						keep += 1
				s.count = keep
		"limit_count":
			var lim = fn.get("limit", {})
			if lim is Dictionary:
				if lim.has("min"):
					s.count = maxi(s.count, int(_num(lim["min"], ctx)))
				if lim.has("max"):
					s.count = mini(s.count, int(_num(lim["max"], ctx)))
		"set_damage":
			var md: int = Res.items.max_damage[s.item]
			if md > 0:
				s.damage = int(md * (1.0 - _num(fn.get("damage", 1.0), ctx)))
		"enchanted_count_increase", "looting_enchant":
			var lvl4 := _ench(ctx.get("tool"), str(fn.get("enchantment", "minecraft:looting")).trim_prefix("minecraft:"))
			if lvl4 > 0 and ctx.get("by_player", true):
				s.count += int(round(lvl4 * _num(fn.get("count", 0), ctx)))
				var lim2 := int(fn.get("limit", 0))
				if lim2 > 0:
					s.count = mini(s.count, lim2)
		"copy_components":
			var be: Dictionary = ctx.get("block_entity", {})
			if str(fn.get("source", "")).trim_prefix("minecraft:") == "block_entity" and not be.is_empty():
				for comp in fn.get("include", []):
					var v = BlockEntities.component_of(be, str(comp))
					if v != null:
						s.components[str(comp)] = v
		"set_ominous_bottle_amplifier":
			s.components["minecraft:ominous_bottle_amplifier"] = _int(fn.get("amplifier", 0), ctx)
		"enchant_randomly", "enchant_with_levels", "set_components", "set_name", "set_lore", "copy_state", "set_stew_effect", "set_potion", "exploration_map", "set_instrument", "furnace_smelt":
			if tp == "furnace_smelt" and ctx.get("on_fire", false):
				var r := Crafting.smelt_result(s.item)
				if r != null:
					r.count = s.count
					return r
	if s.count <= 0:
		s.clear()
	return s
