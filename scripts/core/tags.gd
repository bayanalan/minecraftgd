## Tags — resolves data/minecraft/tags/{block,item,...}/*.json (with nested "#tag" refs and optional
## {"id","required"} entries) into name sets. Cached; main-thread lazy, or prewarm() before worker use.
## Contract: blocks(tag) / items(tag) -> Dictionary(name -> true); has_block(tag, name).
class_name Tags

static var _cache: Dictionary = {}
static var _m := Mutex.new()   # recursive; worker-thread generators resolve tags too


static func resolve(kind: String, tag: String, depth: int = 0) -> Dictionary:
	var t := tag.trim_prefix("#").trim_prefix("minecraft:")
	var key := kind + ":" + t
	_m.lock()
	if _cache.has(key):
		var cached: Dictionary = _cache[key]
		_m.unlock()
		return cached
	var out := {}
	_cache[key] = out
	if depth > 16:
		_m.unlock()
		return out
	var j = Res.read_json("data/minecraft/tags/%s/%s.json" % [kind, t])
	if j is Dictionary:
		for v in j.get("values", []):
			var s := str(v.get("id", "")) if v is Dictionary else str(v)
			if s.begins_with("#"):
				out.merge(resolve(kind, s, depth + 1))
			else:
				out[s.trim_prefix("minecraft:")] = true
	_m.unlock()
	return out


static func blocks(tag: String) -> Dictionary:
	return resolve("block", tag)


static func items(tag: String) -> Dictionary:
	return resolve("item", tag)


static func has_block(tag: String, name: String) -> bool:
	return blocks(tag).has(name)
