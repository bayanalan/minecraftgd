## Native — gateway to the RecraftNative GDExtension (native/recraft_native.gdextension: lighting, meshing,
## density loops in C++). Calls are dynamic so scripts parse without the library; every caller keeps its GDScript
## implementation as the fallback (and for output comparison, see --nativecheck).
## init() runs once on the main thread at startup; `ok` is read-only afterwards (thread-safe for workers).
class_name Native
extends RefCounted

static var ok := false
static var inst = null
static var version := 0
static var arch := ""
static var light_ok := true
static var mesh_ok := true
static var density_ok := true
static var surface_ok := true
static var climate_ok := true
static var features_ok := true
static var chunkops_ok := true


static func init(disabled := false) -> void:
	ok = false
	inst = null
	if disabled or not ClassDB.class_exists("RecraftNative"):
		return
	inst = ClassDB.instantiate("RecraftNative")
	if inst == null:
		return
	var v: Array = inst.version()
	version = int(v[0])
	arch = "arm64" if int(v[1]) == 64 else "x86_64"
	ok = true
	print("[native] RecraftNative v%d (%s) loaded" % [version, arch])
