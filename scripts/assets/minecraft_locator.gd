## MinecraftLocator — finds locally installed Java Edition releases (never downloads anything).
## Why: assets are imported only from the user's own install (spec §3/§31).
## Contract: scan() -> Array[Dictionary] {version, jar, json, game_dir, asset_index, assets_dir, release, stable};
## diagnose() -> human-readable lines saying what was checked and what is missing (import screen).
## Layouts: the official launcher's game directory (versions/<v>/<v>.jar + <v>.json; also CurseForge's Install
## folder, the Modrinth App's meta folder, TLauncher) and the Prism / MultiMC library layout
## (libraries/com/mojang/minecraft/<v>/minecraft-<v>-client.jar, metadata in meta/net.minecraft/<v>.json).
## Invariants: snapshots are listed but never auto-selected for the 26.3 profile.
class_name MinecraftLocator

const TARGET_VERSION := "26.3"


## A folder the user picked may be .minecraft itself, its versions folder or a version folder inside it: the game
## directory is the nearest of them that holds a versions folder.
static func _normalize(d: String) -> String:
	var p := d.replace("\\", "/").trim_suffix("/")
	for i in 3:
		if DirAccess.dir_exists_absolute(p.path_join("versions")) or DirAccess.dir_exists_absolute(p.path_join("libraries/com/mojang/minecraft")):
			return p
		if p.get_base_dir() == p or p.get_base_dir() == "":
			break
		p = p.get_base_dir()
	return d.replace("\\", "/").trim_suffix("/")


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
				roots.append(appdata.path_join("com.modrinth.theseus/meta"))   # Modrinth App
				roots.append(appdata.path_join("ModrinthApp/meta"))
				roots.append(appdata.path_join("PrismLauncher"))
				roots.append(appdata.path_join("PolyMC"))
			if not home.is_empty():
				roots.append(home.path_join("AppData/Roaming/.minecraft"))
				roots.append(home.path_join("curseforge/minecraft/Install"))   # CurseForge
		"macOS":
			roots.append(home.path_join("Library/Application Support/minecraft"))
			roots.append(home.path_join("Library/Application Support/PrismLauncher"))
		_:
			roots.append(home.path_join(".minecraft"))
			roots.append(home.path_join(".local/share/PrismLauncher"))
			var xdg := OS.get_environment("XDG_DATA_HOME")
			if not xdg.is_empty():
				roots.append(xdg.path_join("minecraft"))
	for e in extra:
		if str(e) != "":
			roots.append(_normalize(str(e)))
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


static func _entry(version: String, jar: String, js: String, root: String) -> Dictionary:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(js)) if js != "" and FileAccess.file_exists(js) else null
	if not (meta is Dictionary):
		meta = {}
	var ai: Dictionary = meta.get("assetIndex", {}) if meta.get("assetIndex") is Dictionary else {}
	var kind := str(meta.get("type", "release" if not version.contains("-") and not version.contains("w") else "snapshot"))
	return {
		"version": str(meta.get("id", meta.get("version", version))),
		"jar": jar,
		"json": js,
		"game_dir": root,
		"assets_dir": root.path_join("assets"),
		"asset_index": str(ai.get("id", "")),
		"asset_index_sha1": str(ai.get("sha1", "")),
		"release": kind == "release",
		"type": kind,
	}


static func scan(extra: Array = []) -> Array:
	var found: Array = []
	var seen := {}
	for root in candidate_roots(extra):
		var vdir := str(root).path_join("versions")
		if DirAccess.dir_exists_absolute(vdir):
			for v in DirAccess.get_directories_at(vdir):
				var jar := vdir.path_join(v).path_join(v + ".jar")
				var js := vdir.path_join(v).path_join(v + ".json")
				if not FileAccess.file_exists(jar) or not FileAccess.file_exists(js) or seen.has(jar):
					continue
				seen[jar] = true
				found.append(_entry(v, jar, js, str(root)))
		# Prism Launcher / MultiMC: client jars in the shared library folder, version metadata under meta/
		var ldir := str(root).path_join("libraries/com/mojang/minecraft")
		if DirAccess.dir_exists_absolute(ldir):
			for v in DirAccess.get_directories_at(ldir):
				var jar2 := ldir.path_join(v).path_join("minecraft-%s-client.jar" % v)
				if not FileAccess.file_exists(jar2) or seen.has(jar2):
					continue
				seen[jar2] = true
				found.append(_entry(v, jar2, str(root).path_join("meta/net.minecraft/%s.json" % v), str(root)))
	found.sort_custom(func(a, b): return compare_versions(str(a["version"]), str(b["version"])) > 0)
	return found


## What was checked and what is missing, for the import screen when no usable 26.3 copy was found.
static func diagnose(extra: Array = []) -> PackedStringArray:
	var lines := PackedStringArray()
	var any_target := false
	var versions_seen: Array = []
	for root in candidate_roots(extra):
		var r := str(root)
		var std := r.ends_with("/.minecraft") or extra.has(r) or r == (_normalize(str(extra[0])) if not extra.is_empty() else "")
		if not DirAccess.dir_exists_absolute(r):
			if std:
				lines.append("%s - folder not found" % r)
			continue
		var vdir := r.path_join("versions")
		var ldir := r.path_join("libraries/com/mojang/minecraft")
		if not DirAccess.dir_exists_absolute(vdir) and not DirAccess.dir_exists_absolute(ldir):
			if std:
				lines.append("%s - no versions folder (the game was never launched from here)" % r)
			continue
		var parts: Array = []
		if DirAccess.dir_exists_absolute(vdir):
			for v in DirAccess.get_directories_at(vdir):
				var jar := FileAccess.file_exists(vdir.path_join(v).path_join(v + ".jar"))
				var js := FileAccess.file_exists(vdir.path_join(v).path_join(v + ".json"))
				parts.append(v + ("" if jar and js else (" (no .jar - not downloaded yet)" if js else " (no .json)")))
				versions_seen.append(v)
				if v == TARGET_VERSION and jar and js:
					any_target = true
		if DirAccess.dir_exists_absolute(ldir):
			for v2 in DirAccess.get_directories_at(ldir):
				var ok2 := FileAccess.file_exists(ldir.path_join(v2).path_join("minecraft-%s-client.jar" % v2))
				parts.append(v2 + ("" if ok2 else " (no client jar)"))
				versions_seen.append(v2)
				if v2 == TARGET_VERSION and ok2:
					any_target = true
		lines.append("%s - versions: %s" % [r, ", ".join(parts) if not parts.is_empty() else "none"])
	if not any_target:
		var newer := versions_seen.filter(func(v): return compare_versions(str(v), TARGET_VERSION) > 0)
		lines.append("Minecraft %s is not installed%s. In the Minecraft Launcher open Installations > New installation, pick release %s, press Play once (this downloads the files), close the game and press Retry." % [TARGET_VERSION, (" (only newer versions: %s)" % ", ".join(newer)) if not newer.is_empty() else "", TARGET_VERSION])
	return lines


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
