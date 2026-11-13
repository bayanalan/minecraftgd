// gdx — minimal helper layer over the raw GDExtension C interface (no godot-cpp): variant/packed/array access,
// owned temporaries and method registration. Godot 4.7, single precision build ("float_64" sizes).
#pragma once
#include <cstdint>
#include <cstring>
#include <vector>
#include "gdextension_interface.h"

namespace gdx {

// ---- interface function pointers (filled by load())
extern GDExtensionInterfaceGetProcAddress gpa;
extern GDExtensionClassLibraryPtr library;
extern GDExtensionInterfaceVariantGetType variant_get_type;
extern GDExtensionInterfaceVariantDestroy variant_destroy;
extern GDExtensionInterfaceVariantNewNil variant_new_nil;
extern GDExtensionInterfaceVariantNewCopy variant_new_copy;
extern GDExtensionInterfaceArrayOperatorIndex array_index;
extern GDExtensionInterfaceArrayOperatorIndexConst array_index_const;
extern GDExtensionInterfacePrintError print_error;
extern GDExtensionInterfacePrintWarning print_warning;

bool load(GDExtensionInterfaceGetProcAddress p_gpa, GDExtensionClassLibraryPtr p_lib);

// ---- type helpers
GDExtensionVariantFromTypeConstructorFunc from_type(GDExtensionVariantType t);
GDExtensionTypeFromVariantConstructorFunc to_type(GDExtensionVariantType t);
GDExtensionVariantGetInternalPtrFunc internal(GDExtensionVariantType t);
GDExtensionPtrConstructor ctor(GDExtensionVariantType t);
GDExtensionPtrDestructor dtor(GDExtensionVariantType t);

int64_t size_of(GDExtensionVariantType t, const void *native);          // Array / Packed*Array
void resize(GDExtensionVariantType t, void *native, int64_t n);

// Packed data pointers (nullptr when empty)
const uint8_t *bytes(const void *packed);
uint8_t *bytes_w(void *packed);
const int32_t *i32(const void *packed);
int32_t *i32_w(void *packed);
const float *f32(const void *packed);
float *f32_w(void *packed);
const double *f64(const void *packed);
double *f64_w(void *packed);
const int64_t *i64(const void *packed);
int64_t *i64_w(void *packed);
float *vec3_w(void *packed);   // x,y,z float triples
float *vec2_w(void *packed);
float *color_w(void *packed);  // r,g,b,a
const float *color(const void *packed);
const float *vec3(const void *packed);

// ---- owned native value (constructed / destroyed through the interface)
struct Owned {
	alignas(16) uint8_t buf[32];
	GDExtensionVariantType type;
	explicit Owned(GDExtensionVariantType t);
	~Owned();
	void *ptr() { return buf; }
	Owned(const Owned &) = delete;
	Owned &operator=(const Owned &) = delete;
};

// ---- method call arguments: same accessors for ptrcall (native pointers) and call (Variants)
struct Args {
	bool is_ptr;
	const void *const *p;
	int64_t count;
	int64_t i(int k) const;
	double f(int k) const;
	// pointer to the native packed/array object for argument k (nullptr if the variant has another type)
	const void *obj(int k, GDExtensionVariantType t) const;
};

// Native method signature: fills `ret` (an Array native object) and returns false on bad arguments.
typedef bool (*NativeFn)(const Args &a, void *ret_array);

// Array building helpers: set element k (Array must already be resized) from a native value or int.
void array_set_native(void *arr, int64_t k, GDExtensionVariantType t, void *native);
void array_set_int(void *arr, int64_t k, int64_t v);
void array_set_float(void *arr, int64_t k, double v);
const void *array_get(const void *arr, int64_t k);           // Variant*

void register_class(const char *name, const char *parent);
void register_method(const char *cls, const char *name, NativeFn fn, int argc);

} // namespace gdx
