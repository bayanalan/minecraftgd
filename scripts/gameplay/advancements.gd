## Advancements — data-driven from the installed data/minecraft/advancement/**.json (recipe unlock trees skipped).
## Supported triggers (source D semantics): inventory_changed (item predicates: id/tag/list, min count),
## changed_dimension (from/to), player_killed_entity (entity_type), bred_animals, consume_item (item),
## enter_block / placed_block (block id), location (dimension/biome/structure when given simply), tick, impossible.
## Progress persists in level.json ("advancements": {id: {criterion: true}}); completion shows a toast and a chat line.
## Contract: Advancements.new(world); trigger(kind, ctx); on_inventory(inv); list_by_tab() for the screen.
class_name Advancements
extends RefCounted

var world
var defs: Dictionary = {}       # id -> {criteria: {name: {trigger, conditions}}, requirements: [[...]], title, desc, icon, tab, parent, hidden}
var progress: Dictionary = {}   # id -> {criterion: true}
var done: Dictionary = {}


func _init(w) -> void:
	world = w
	progress = w.level.get("advancements", {})
	w.level["advancements"] = progress
	for f in Res.list_files("data/minecraft/advancement/", ".json"):
		var rel := f.trim_prefix("data/minecraft/advancement/").trim_suffix(".json")
		if rel.begins_with("recipes/"):
			continue
		var j = Res.read_json(f)
		if not (j is Dictionary):
			continue
		var disp: Dictionary = j.get("display", {}) if j.get("display") is Dictionary else {}
		var reqs: Array = j.get("requirements", [])
		if reqs.is_empty():
			for c in j.get("criteria", {}):
				reqs.append([c])
		defs[rel] = {"criteria": j.get("criteria", {}), "requirements": reqs, "tab": rel.split("/")[0],
			"title": _text(disp.get("title", rel)), "desc": _text(disp.get("description", "")),
			"icon": str((disp.get("icon", {}) as Dictionary).get("id", "minecraft:paper")) if disp.get("icon") is Dictionary else "minecraft:paper",
			"parent": str(j.get("parent", "")).trim_prefix("minecraft:"), "toast": bool(disp.get("show_toast", true)) and not disp.is_empty(),
			"hidden": bool(disp.get("hidden", false)), "frame": str(disp.get("frame", "task")),
			"display": not disp.is_empty(), "background": str(disp.get("background", "")).trim_prefix("minecraft:")}
	for id in defs:
		if _complete(id):
			done[id] = true


static func _text(v) -> String:
	if v is Dictionary:
		if v.has("translate"):
			return Res.tr_key(str(v["translate"]), str(v.get("fallback", v["translate"])))
		return str(v.get("text", ""))
	return str(v)


func _complete(id: String) -> bool:
	var d: Dictionary = defs[id]
	var p: Dictionary = progress.get(id, {})
	for group in d["requirements"]:
		var any := false
		for c in group:
			if p.has(c):
				any = true
				break
		if not any:
			return false
	return true


func trigger(kind: String, ctx: Dictionary = {}) -> void:
	for id in defs:
		if done.has(id):
			continue
		var d: Dictionary = defs[id]
		var crit: Dictionary = d["criteria"]
		var changed := false
		for cname in crit:
			var c = crit[cname]
			if not (c is Dictionary) or str(c.get("trigger", "")).trim_prefix("minecraft:") != kind:
				continue
			if (progress.get(id, {}) as Dictionary).has(cname):
				continue
			if _matches(kind, c.get("conditions", {}), ctx):
				if not progress.has(id):
					progress[id] = {}
				progress[id][cname] = true
				changed = true
		if changed and _complete(id):
			done[id] = true
			_award(id)


func _award(id: String) -> void:
	var d: Dictionary = defs[id]
	if d["toast"]:
		var head := {"goal": "Goal Reached!", "challenge": "Challenge Complete!"}.get(d["frame"], "Advancement Made!")
		world.hud.toast(head, d["title"], d["icon"])
		world.hud.chat_message("Player has made the advancement [%s]" % d["title"])
		Audio.play("ui.toast.challenge_complete" if d["frame"] == "challenge" else "entity.player.levelup", world.player.pos, "Players", 0.6)


func on_inventory(inv: Inventory) -> void:
	var counts := {}
	for i in Inventory.SIZE:
		var s := inv.get_slot(i)
		if not s.is_empty():
			counts[s.name()] = int(counts.get(s.name(), 0)) + s.count
	trigger("inventory_changed", {"items": counts})


static func _item_match(pred, name: String) -> bool:
	if pred is String:
		var t := str(pred)
		if t.begins_with("#"):
			return Tags.items(t.substr(1)).has(name)
		return t.trim_prefix("minecraft:") == name
	if pred is Array:
		for q in pred:
			if _item_match(q, name):
				return true
	return false


func _matches(kind: String, cond, ctx: Dictionary) -> bool:
	if not (cond is Dictionary):
		return true
	match kind:
		"inventory_changed":
			var items: Dictionary = ctx.get("items", {})
			for pred in cond.get("items", []):
				var ok := false
				var want := 1
				if pred is Dictionary and pred.get("count") is Dictionary:
					want = int(pred["count"].get("min", 1))
				elif pred is Dictionary and (pred.get("count") is int or pred.get("count") is float):
					want = int(pred["count"])
				for n in items:
					if (not (pred is Dictionary) or not pred.has("items") or _item_match(pred["items"], n)) and int(items[n]) >= want:
						ok = true
						break
				if not ok:
					return false
			return true
		"changed_dimension":
			if cond.has("to") and str(cond["to"]).trim_prefix("minecraft:") != str(ctx.get("to", "")):
				return false
			if cond.has("from") and str(cond["from"]).trim_prefix("minecraft:") != str(ctx.get("from", "")):
				return false
			return true
		"player_killed_entity":
			var ent = cond.get("entity", null)
			if ent is Dictionary:
				var pr: Dictionary = ent.get("predicate", ent)
				var et = pr.get("minecraft:entity_type", pr.get("type", null))
				if et is String:
					var ets := str(et)
					if ets.begins_with("#"):
						return Tags.resolve("entity_type", ets).has(str(ctx.get("entity", "")))
					return ets.trim_prefix("minecraft:") == str(ctx.get("entity", ""))
			elif ent is Array:
				for e in ent:
					if e is Dictionary:
						var pr2: Dictionary = e.get("predicate", {})
						var et2 = pr2.get("minecraft:entity_type", pr2.get("type", null))
						if et2 is String and str(et2).trim_prefix("minecraft:") != str(ctx.get("entity", "")):
							return false
			return true
		"consume_item":
			var it = cond.get("item", null)
			if it is Dictionary and it.has("items"):
				return _item_match(it["items"], str(ctx.get("item", "")))
			return true
		"enter_block", "placed_block":
			var blk = cond.get("block", null)
			if blk is String:
				return str(blk).trim_prefix("minecraft:") == str(ctx.get("block", ""))
			return true
		"location":
			# simple dimension / biome / structure predicates only
			var s := JSON.stringify(cond)
			if s.contains("\"dimension\"") and not s.contains(str(ctx.get("dimension", "~"))):
				return false
			if s.contains("\"biomes\"") and not s.contains(str(ctx.get("biome", "~"))):
				return false
			if s.contains("\"structures\"") and not s.contains(str(ctx.get("structure", "~"))):
				return false
			return s.contains("\"dimension\"") or s.contains("\"biomes\"") or s.contains("\"structures\"")
		"tick":
			return true
		"impossible":
			return false
	return true


## For the advancements screen: tab -> Array of [id, title, desc, done, icon].
func list_by_tab() -> Dictionary:
	var out := {}
	var ids: Array = defs.keys()
	ids.sort()
	for id in ids:
		var d: Dictionary = defs[id]
		if d["hidden"] and not done.has(id):
			continue
		if not out.has(d["tab"]):
			out[d["tab"]] = []
		(out[d["tab"]] as Array).append([id, d["title"], d["desc"], done.has(id), d["icon"]])
	return out
