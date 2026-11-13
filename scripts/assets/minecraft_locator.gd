## MinecraftLocator — finds locally installed Java Edition releases (never downloads anything).
## Why: assets are imported only from the user's own install (spec §3/§31).
## Contract: scan() -> Array[Dictionary] {version, jar, json, game_dir, asset_index, assets_dir, release, stable}
## Invariants: snapshots are listed but never auto-selected for the 26.3 profile.
class_name MinecraftLocator

const TARGET_VERSION := "26.3"


static func candidate_roots(extra: Array = []) -> Array:
	var roots: Array = []
	var appdata := OS.get_environment("APPDATA")
	var home := OS.get_environment("USERPROFILE")
	if home.is_empty():
		home = OS.get_environment("HOME")
	match OS.get_name():
		"Windows":
			if not appdata.is_empty():
				roots.append(appdata.path_join(".minecraft"))
			if not home.is_empty():
				roots.append(home.path_join("AppData/Roaming/.minecraft"))
		"macOS":
			roots.append(home.path_join("Library/Application Support/minecraft"))
		_:
			roots.append(home.path_join(".minecraft"))
			var xdg := OS.get_environment("XDG_DATA_HOME")
			if not xdg.is_empty():
				roots.append(xdg.path_join("minecraft"))
	for e in extra:
		roots.append(str(e))
	# launcher profiles may define custom gameDir
	var out: Array = []
	for r in roots:
		var rr := str(r).replace("\\", "/")
		if not out.has(rr):
			out.append(rr)
		var prof := rr.path_join("launcher_profiles.json")
		if FileAccess.file_exists(prof):
			var j = JSON.parse_string(FileAccess.get_file_as_string(prof))
			if j is Dictionary and j.get("profiles") is Dictionary:
				for p in j["profiles"].values():
					if p is Dictionary and p.has("gameDir"):
						var gd := str(p["gameDir"]).replace("\\", "/")
						if not out.has(gd):
							out.append(gd)
	return out


static func scan(extra: Array = []) -> Array:
	var found: Array = []
	for root in candidate_roots(extra):
		var vdir := str(root).path_join("versions")
		if not DirAccess.dir_exists_absolute(vdir):
			continue
		for v in DirAccess.get_directories_at(vdir):
			var jar := vdir.path_join(v).path_join(v + ".jar")
			var js := vdir.path_join(v).path_join(v + ".json")
			if not FileAccess.file_exists(jar) or not FileAccess.file_exists(js):
				continue
			var meta = JSON.parse_string(FileAccess.get_file_as_string(js))
			if not (meta is Dictionary):
				continue
			var ai: Dictionary = meta.get("assetIndex", {}) if meta.get("assetIndex") is Dictionary else {}
			var kind := str(meta.get("type", ""))
			found.append({
				"version": str(meta.get("id", v)),
				"jar": jar,
				"json": js,
				"game_dir": str(root),
				"assets_dir": str(root).path_join("assets"),
				"asset_index": str(ai.get("id", "")),
				"asset_index_sha1": str(ai.get("sha1", "")),
				"release": kind == "release",
				"type": kind,
			})
	found.sort_custom(func(a, b): return compare_versions(str(a["version"]), str(b["version"])) > 0)
	return found


## Picks exact 26.3 if present, else highest release <= 26.3.
static func pick_best(found: Array) -> Dictionary:
	for f in found:
		if f["version"] == TARGET_VERSION:
			return f
	for f in found:
		if f["release"] and compare_versions(str(f["version"]), TARGET_VERSION) <= 0:
			return f
	return {}


static func compare_versions(a: String, b: String) -> int:
	var pa := a.split("-")[0].split(".")
	var pb := b.split("-")[0].split(".")
	for i in max(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	var sa := a.contains("-")
	var sb := b.contains("-")
	if sa != sb:
		return -1 if sa else 1
	return 0
