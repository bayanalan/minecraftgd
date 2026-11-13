// RecraftNative — native hot loops for Recraft 2 (lighting, meshing, density). Entry point + registration.
// Every method returns an Array; GDScript calls it dynamically (ClassDB.instantiate("RecraftNative")) so scripts
// still parse when the library is absent and fall back to the GDScript implementations.
#include "gdx.h"
#include "native.h"

using namespace gdx;

static bool fn_version(const Args &, void *ret) {
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 2);
	array_set_int(ret, 0, RN_VERSION);
#if defined(_M_ARM64)
	array_set_int(ret, 1, 64);   // arm64
#else
	array_set_int(ret, 1, 86);   // x86-64
#endif
	return true;
}

// test: [sum of PackedInt32Array, PackedByteArray(n) filled with v]
static bool fn_selftest(const Args &a, void *ret) {
	const void *arr = a.obj(0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	int64_t n = a.i(1);
	int64_t v = a.i(2);
	int64_t sum = 0;
	if (arr) {
		int64_t sz = size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, arr);
		const int32_t *d = i32(arr);
		for (int64_t k = 0; k < sz; k++) sum += d[k];
	}
	Owned b(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, b.ptr(), n);
	uint8_t *w = bytes_w(b.ptr());
	for (int64_t k = 0; k < n; k++) w[k] = (uint8_t)v;
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 2);
	array_set_int(ret, 0, sum);
	array_set_native(ret, 1, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, b.ptr());
	return true;
}

static void initialize(void *, GDExtensionInitializationLevel level) {
	if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
	// Object, not RefCounted: every Native.inst.x() call from any thread copied a Ref (two atomic operations on one shared
	// counter): measurable cache-line contention between the chunk workers and the main thread. One instance lives for
	// the whole run (scripts/core/native.gd).
	register_class("RecraftNative", "Object");
	register_method("RecraftNative", "version", fn_version, 0);
	register_method("RecraftNative", "selftest", fn_selftest, 3);
	register_native_methods("RecraftNative");
}

static void deinitialize(void *, GDExtensionInitializationLevel) {}

extern "C" __declspec(dllexport) GDExtensionBool recraft_native_init(GDExtensionInterfaceGetProcAddress p_gpa, GDExtensionClassLibraryPtr p_lib, GDExtensionInitialization *r_init) {
	if (!load(p_gpa, p_lib)) return 0;
	r_init->initialize = initialize;
	r_init->deinitialize = deinitialize;
	r_init->userdata = nullptr;
	r_init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	return 1;
}
