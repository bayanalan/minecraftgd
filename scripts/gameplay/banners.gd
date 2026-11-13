## Banners — banner pattern registry from the installed data (data/minecraft/banner_pattern/*.json, tags
## banner_pattern/no_item_required and pattern_item/<name>), Java LoomMenu rules:
## - selectable patterns: the no_item_required tag with an empty pattern slot, else the pattern item's tag
##   (<name>_banner_pattern item -> #pattern_item/<name>, Java provides_banner_patterns component);
## - result = input banner + one layer {pattern, dye color}; at most 6 layers (Java BannerPatternLayers limit);
## - taking the result uses one banner and one dye; the pattern item stays.
## Layers live in the item component minecraft:banner_patterns and in the placed banner's block entity "patterns".
class_name Banners
extends RefCounted

const MAX_LAYERS := 6

static var patterns: Dictionary = {}   # "minecraft:border" -> {asset, key}
static var _tags: Dictionary = {}


static func load_all() -> void:
	if not patterns.is_empty():
		return
	for f in Res.list_files("data/minecraft/banner_pattern/", ".json"):
		var j = Res.read_json(f)
		if j is Dictionary:
			var id := "minecraft:" + str(f).get_file().get_basename()
			patterns[id] = {"asset": str(j.get("asset_id", id)).trim_prefix("minecraft:"), "key": str(j.get("translation_key", ""))}


static func tag(name: String) -> Array:
	if _tags.has(name):
		return _tags[name]
	var out: Array = []
	var j = Res.read_json("data/minecraft/tags/banner_pattern/%s.json" % name)
	if j is Dictionary:
		for v in j.get("values", []):
			var s := str(v if not (v is Dictionary) else v.get("id", ""))
			if s.begins_with("#"):
				out.append_array(tag(s.substr(1).trim_prefix("minecraft:")))
			elif not out.has(s):
				out.append(s)
	_tags[name] = out
	return out


static func selectable(pattern_item: ItemStack) -> Array:
	load_all()
	if pattern_item == null or pattern_item.is_empty():
		return tag("no_item_required")
	var nm := pattern_item.name()
	if nm.ends_with("_banner_pattern"):
		return tag("pattern_item/" + nm.trim_suffix("_banner_pattern"))
	return []


static func texture(id: String) -> String:
	load_all()
	var p: Dictionary = patterns.get(id, {})
	return "entity/banner/" + str(p.get("asset", id.trim_prefix("minecraft:")))


static func display_name(id: String, color: String) -> String:
	load_all()
	var key := str((patterns.get(id, {}) as Dictionary).get("key", ""))
	return Res.tr_key(key + "." + color, color.capitalize() + " " + id.trim_prefix("minecraft:").capitalize())


static func dye_color(item_name: String) -> String:
	return item_name.trim_suffix("_dye") if item_name.ends_with("_dye") else ""


static func layers(s: ItemStack) -> Array:
	var v = s.components.get("minecraft:banner_patterns", [])
	return v if v is Array else []


## Loom result for (banner, dye, pattern id) or an empty stack.
static func loom_result(banner: ItemStack, dye: ItemStack, pid: String) -> ItemStack:
	if banner.is_empty() or dye.is_empty() or pid == "" or not banner.name().ends_with("_banner"):
		return ItemStack.new()
	var color := dye_color(dye.name())
	if color == "" or layers(banner).size() >= MAX_LAYERS:
		return ItemStack.new()
	var out := banner.copy()
	out.count = 1
	var l: Array = layers(banner).duplicate(true)
	l.append({"pattern": pid, "color": color})
	out.components["minecraft:banner_patterns"] = l
	return out
