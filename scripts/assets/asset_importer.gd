## AssetImporter — imports a user-owned Java client into user://minecraft_asset_cache/<version>/.
## Why: spec §3 — private local cache, versioned manifest, hash validation, idempotent atomic import.
## Contract: run(found, progress_cb) -> Dictionary {ok, error, manifest}; is_cache_valid(version) -> bool.
## Invariants: copies the jar atomically (tmp + rename); sound/music objects stay in the launcher's
## objects store and are only referenced by hash (never redistributed, never downloaded).
class_name AssetImporter

const CACHE_ROOT := "user://minecraft_asset_cache"
const CACHE_REVISION := 3


static func cache_dir(version: String) -> String:
	return CACHE_ROOT.path_join(version)


static func manifest_path(version: String) -> String:
	return cache_dir(version).path_join("manifest.json")


static func load_manifest(version: String) -> Dictionary:
	var p := manifest_path(version)
	if not FileAccess.file_exists(p):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(p))
	return j if j is Dictionary else {}


static func find_any_cached() -> Dictionary:
	if not DirAccess.dir_exists_absolute(CACHE_ROOT):
		return {}
	var best := {}
	for d in DirAccess.get_directories_at(CACHE_ROOT):
		var m := load_manifest(d)
		if m.get("complete", false) and int(m.get("cache_revision", 0)) == CACHE_REVISION:
			if best.is_empty() or MinecraftLocator.compare_versions(str(m["version"]), str(best["version"])) > 0:
				best = m
	return best


static func file_sha1(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(1 << 20))
	return ctx.finish().hex_encode()


## Returns true if the cached manifest still matches the source jar (size+mtime) — rebuild otherwise.
static func is_cache_valid(found: Dictionary) -> bool:
	var m := load_manifest(str(found.get("version", "")))
	if m.is_empty() or not m.get("complete", false) or int(m.get("cache_revision", 0)) != CACHE_REVISION:
		return false
	var jar := str(found["jar"])
	if not FileAccess.file_exists(jar):
		return FileAccess.file_exists(str(m.get("cached_jar", "")))
	return int(m.get("source_jar_size", -1)) == FileAccess.get_size(jar) and int(m.get("source_jar_mtime", -1)) == FileAccess.get_modified_time(jar)


static func run(found: Dictionary, progress: Callable) -> Dictionary:
	var version := str(found["version"])
	var dir := cache_dir(version)
	DirAccess.make_dir_recursive_absolute(dir)
	var report := {"ok": false, "error": "", "manifest": {}}
	var jar_src := str(found["jar"])
	print("[Import] start ", jar_src)
	progress.call("Validating client archive", 0.05)
	var reader := JarAssetReader.new()
	if reader.open(jar_src) != OK:
		report["error"] = "Cannot open client jar (not a valid ZIP): " + jar_src
		return report
	var vjson = reader.read_json("version.json")
	reader.close()
	if not (vjson is Dictionary) or str(vjson.get("id", "")) != version:
		report["error"] = "version.json inside jar does not match " + version
		return report
	progress.call("Hashing client jar", 0.15)
	var jar_sha := file_sha1(jar_src)
	progress.call("Copying jar to private cache", 0.3)
	var cached_jar := dir.path_join("client.jar")
	var tmp := cached_jar + ".tmp"
	var err := DirAccess.copy_absolute(jar_src, tmp)
	if err != OK:
		report["error"] = "Copy failed (%d)" % err
		return report
	if file_sha1(tmp) != jar_sha:
		DirAccess.remove_absolute(tmp)
		report["error"] = "Copied jar hash mismatch"
		return report
	if FileAccess.file_exists(cached_jar):
		DirAccess.remove_absolute(cached_jar)
	DirAccess.rename_absolute(tmp, cached_jar)
	progress.call("Indexing sounds and music", 0.55)
	var sound_info := index_sounds(found)
	progress.call("Cataloguing packaged assets", 0.75)
	reader = JarAssetReader.new()
	reader.open(cached_jar)
	var counts := {}
	for f in reader.files:
		var parts: PackedStringArray = str(f).split("/")
		if parts.size() >= 3:
			var k := parts[0] + "/" + parts[2]
			counts[k] = int(counts.get(k, 0)) + 1
	var missing: Array = []
	for must in ["assets/minecraft/textures/block/stone.png", "assets/minecraft/blockstates/grass_block.json", "assets/minecraft/textures/block/water_still.png", "assets/minecraft/textures/gui/sprites/hud/heart/full.png", "data/minecraft/worldgen/noise_settings/overworld.json"]:
		if not reader.has(must):
			missing.append(must)
	reader.close()
	var manifest := {
		"version": version,
		"cache_revision": CACHE_REVISION,
		"source_jar": jar_src,
		"source_jar_size": FileAccess.get_size(jar_src),
		"source_jar_mtime": FileAccess.get_modified_time(jar_src),
		"source_jar_sha1": jar_sha,
		"cached_jar": cached_jar,
		"assets_dir": str(found.get("assets_dir", "")),
		"asset_index": str(found.get("asset_index", "")),
		"asset_index_valid": sound_info["valid"],
		"sound_objects": sound_info["count"],
		"sound_objects_missing": sound_info["missing"],
		"music_tracks": sound_info["music"],
		"categories": counts,
		"missing_required": missing,
		"timestamp": Time.get_datetime_string_from_system(true),
		"complete": true,
		"notice": "Imported privately from the user's own Minecraft install for local use only. Not redistributed.",
	}
	var mtmp := manifest_path(version) + ".tmp"
	var f := FileAccess.open(mtmp, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	if FileAccess.file_exists(manifest_path(version)):
		DirAccess.remove_absolute(manifest_path(version))
	DirAccess.rename_absolute(mtmp, manifest_path(version))
	print("[Import] done")
	progress.call("Done", 1.0)
	report["ok"] = true
	report["manifest"] = manifest
	return report


## Validates the asset index hash and counts how many sound objects actually exist locally.
static func index_sounds(found: Dictionary) -> Dictionary:
	var out := {"valid": false, "count": 0, "missing": 0, "music": 0}
	var idx_path := str(found.get("assets_dir", "")).path_join("indexes").path_join(str(found.get("asset_index", "")) + ".json")
	if not FileAccess.file_exists(idx_path):
		return out
	var want := str(found.get("asset_index_sha1", ""))
	out["valid"] = want.is_empty() or file_sha1(idx_path) == want
	var j = JSON.parse_string(FileAccess.get_file_as_string(idx_path))
	if not (j is Dictionary) or not (j.get("objects") is Dictionary):
		return out
	var objdir := str(found.get("assets_dir", "")).path_join("objects")
	for k in j["objects"]:
		var key: String = k
		if not key.begins_with("minecraft/sounds/"):
			continue
		var h := str(j["objects"][k].get("hash", ""))
		if h.length() < 2:
			continue
		if FileAccess.file_exists(objdir.path_join(h.substr(0, 2)).path_join(h)):
			out["count"] += 1
			if key.begins_with("minecraft/sounds/music/"):
				out["music"] += 1
		else:
			out["missing"] += 1
	return out
