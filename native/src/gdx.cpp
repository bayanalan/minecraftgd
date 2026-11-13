#include "gdx.h"
#include <new>

namespace gdx {

GDExtensionInterfaceGetProcAddress gpa = nullptr;
GDExtensionClassLibraryPtr library = nullptr;
GDExtensionInterfaceVariantGetType variant_get_type = nullptr;
GDExtensionInterfaceVariantDestroy variant_destroy = nullptr;
GDExtensionInterfaceVariantNewNil variant_new_nil = nullptr;
GDExtensionInterfaceVariantNewCopy variant_new_copy = nullptr;
GDExtensionInterfaceArrayOperatorIndex array_index = nullptr;
GDExtensionInterfaceArrayOperatorIndexConst array_index_const = nullptr;
GDExtensionInterfacePrintError print_error = nullptr;
GDExtensionInterfacePrintWarning print_warning = nullptr;

static GDExtensionInterfaceGetVariantFromTypeConstructor p_get_from_type = nullptr;
static GDExtensionInterfaceGetVariantToTypeConstructor p_get_to_type = nullptr;
static GDExtensionInterfaceGetVariantGetInternalPtrFunc p_get_internal = nullptr;
static GDExtensionInterfaceVariantGetPtrConstructor p_get_ctor = nullptr;
static GDExtensionInterfaceVariantGetPtrDestructor p_get_dtor = nullptr;
static GDExtensionInterfaceVariantGetPtrBuiltinMethod p_get_builtin = nullptr;
static GDExtensionInterfaceStringNameNewWithLatin1Chars p_sn_new = nullptr;
static GDExtensionInterfaceStringNewWithLatin1Chars p_str_new = nullptr;
static GDExtensionInterfacePackedByteArrayOperatorIndex p_pba = nullptr;
static GDExtensionInterfacePackedByteArrayOperatorIndexConst p_pba_c = nullptr;
static GDExtensionInterfacePackedInt32ArrayOperatorIndex p_pi32 = nullptr;
static GDExtensionInterfacePackedInt32ArrayOperatorIndexConst p_pi32_c = nullptr;
static GDExtensionInterfacePackedFloat32ArrayOperatorIndex p_pf32 = nullptr;
static GDExtensionInterfacePackedFloat32ArrayOperatorIndexConst p_pf32_c = nullptr;
static GDExtensionInterfacePackedFloat64ArrayOperatorIndex p_pf64 = nullptr;
static GDExtensionInterfacePackedInt64ArrayOperatorIndex p_pi64 = nullptr;
static GDExtensionInterfacePackedInt64ArrayOperatorIndexConst p_pi64_c = nullptr;
static GDExtensionInterfacePackedFloat64ArrayOperatorIndexConst p_pf64_c = nullptr;
static GDExtensionInterfacePackedVector3ArrayOperatorIndex p_pv3 = nullptr;
static GDExtensionInterfacePackedVector2ArrayOperatorIndex p_pv2 = nullptr;
static GDExtensionInterfacePackedColorArrayOperatorIndex p_pcol = nullptr;
static GDExtensionInterfacePackedColorArrayOperatorIndexConst p_pcol_c = nullptr;
static GDExtensionInterfacePackedVector3ArrayOperatorIndexConst p_pv3_c = nullptr;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 p_reg_class = nullptr;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod p_reg_method = nullptr;
static GDExtensionInterfaceClassdbConstructObject2 p_construct = nullptr;
static GDExtensionInterfaceObjectSetInstance p_set_instance = nullptr;

static GDExtensionPtrBuiltInMethod m_size[64];
static GDExtensionPtrBuiltInMethod m_resize[64];
static GDExtensionVariantFromTypeConstructorFunc c_from[64];
static GDExtensionTypeFromVariantConstructorFunc c_to[64];
static GDExtensionVariantGetInternalPtrFunc c_int[64];
static GDExtensionPtrConstructor c_ctor[64];
static GDExtensionPtrDestructor c_dtor[64];

// StringNames that must outlive registration (8 bytes each)
struct SN { alignas(8) uint8_t b[8]; };
static std::vector<SN *> g_names;

static void *sn(const char *s) {
	SN *n = new SN();
	p_sn_new(n->b, s, 1);
	g_names.push_back(n);
	return n->b;
}

#define LOAD(var, type, name) var = (type)gpa(name); if (!var) return false;

bool load(GDExtensionInterfaceGetProcAddress p_gpa, GDExtensionClassLibraryPtr p_lib) {
	gpa = p_gpa;
	library = p_lib;
	LOAD(variant_get_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
	LOAD(variant_destroy, GDExtensionInterfaceVariantDestroy, "variant_destroy");
	LOAD(variant_new_nil, GDExtensionInterfaceVariantNewNil, "variant_new_nil");
	LOAD(variant_new_copy, GDExtensionInterfaceVariantNewCopy, "variant_new_copy");
	LOAD(array_index, GDExtensionInterfaceArrayOperatorIndex, "array_operator_index");
	LOAD(array_index_const, GDExtensionInterfaceArrayOperatorIndexConst, "array_operator_index_const");
	LOAD(print_error, GDExtensionInterfacePrintError, "print_error");
	LOAD(print_warning, GDExtensionInterfacePrintWarning, "print_warning");
	LOAD(p_get_from_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
	LOAD(p_get_to_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");
	LOAD(p_get_internal, GDExtensionInterfaceGetVariantGetInternalPtrFunc, "variant_get_ptr_internal_getter");
	LOAD(p_get_ctor, GDExtensionInterfaceVariantGetPtrConstructor, "variant_get_ptr_constructor");
	LOAD(p_get_dtor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
	LOAD(p_get_builtin, GDExtensionInterfaceVariantGetPtrBuiltinMethod, "variant_get_ptr_builtin_method");
	LOAD(p_sn_new, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
	LOAD(p_str_new, GDExtensionInterfaceStringNewWithLatin1Chars, "string_new_with_latin1_chars");
	LOAD(p_pba, GDExtensionInterfacePackedByteArrayOperatorIndex, "packed_byte_array_operator_index");
	LOAD(p_pba_c, GDExtensionInterfacePackedByteArrayOperatorIndexConst, "packed_byte_array_operator_index_const");
	LOAD(p_pi32, GDExtensionInterfacePackedInt32ArrayOperatorIndex, "packed_int32_array_operator_index");
	LOAD(p_pi32_c, GDExtensionInterfacePackedInt32ArrayOperatorIndexConst, "packed_int32_array_operator_index_const");
	LOAD(p_pf32, GDExtensionInterfacePackedFloat32ArrayOperatorIndex, "packed_float32_array_operator_index");
	LOAD(p_pf32_c, GDExtensionInterfacePackedFloat32ArrayOperatorIndexConst, "packed_float32_array_operator_index_const");
	LOAD(p_pf64, GDExtensionInterfacePackedFloat64ArrayOperatorIndex, "packed_float64_array_operator_index");
	LOAD(p_pi64, GDExtensionInterfacePackedInt64ArrayOperatorIndex, "packed_int64_array_operator_index");
	LOAD(p_pi64_c, GDExtensionInterfacePackedInt64ArrayOperatorIndexConst, "packed_int64_array_operator_index_const");
	LOAD(p_pf64_c, GDExtensionInterfacePackedFloat64ArrayOperatorIndexConst, "packed_float64_array_operator_index_const");
	LOAD(p_pv3, GDExtensionInterfacePackedVector3ArrayOperatorIndex, "packed_vector3_array_operator_index");
	LOAD(p_pv2, GDExtensionInterfacePackedVector2ArrayOperatorIndex, "packed_vector2_array_operator_index");
	LOAD(p_pcol, GDExtensionInterfacePackedColorArrayOperatorIndex, "packed_color_array_operator_index");
	LOAD(p_pcol_c, GDExtensionInterfacePackedColorArrayOperatorIndexConst, "packed_color_array_operator_index_const");
	LOAD(p_pv3_c, GDExtensionInterfacePackedVector3ArrayOperatorIndexConst, "packed_vector3_array_operator_index_const");
	LOAD(p_reg_class, GDExtensionInterfaceClassdbRegisterExtensionClass6, "classdb_register_extension_class6");
	LOAD(p_reg_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
	LOAD(p_construct, GDExtensionInterfaceClassdbConstructObject2, "classdb_construct_object2");
	LOAD(p_set_instance, GDExtensionInterfaceObjectSetInstance, "object_set_instance");
	void *size_name = sn("size");
	void *resize_name = sn("resize");
	GDExtensionVariantType arr_types[] = {GDEXTENSION_VARIANT_TYPE_ARRAY, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY,
		GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,
		GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY,
		GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY};
	for (GDExtensionVariantType t : arr_types) {
		m_size[t] = p_get_builtin(t, size_name, 3173160232u);
		m_resize[t] = p_get_builtin(t, resize_name, 848867239u);
		if (!m_size[t] || !m_resize[t]) return false;
	}
	for (int t = 1; t < GDEXTENSION_VARIANT_TYPE_VARIANT_MAX; t++) {
		c_from[t] = p_get_from_type((GDExtensionVariantType)t);
		c_to[t] = p_get_to_type((GDExtensionVariantType)t);
		c_int[t] = p_get_internal((GDExtensionVariantType)t);
		c_ctor[t] = p_get_ctor((GDExtensionVariantType)t, 0);
		c_dtor[t] = p_get_dtor((GDExtensionVariantType)t);
	}
	return true;
}

GDExtensionVariantFromTypeConstructorFunc from_type(GDExtensionVariantType t) { return c_from[t]; }
GDExtensionTypeFromVariantConstructorFunc to_type(GDExtensionVariantType t) { return c_to[t]; }
GDExtensionVariantGetInternalPtrFunc internal(GDExtensionVariantType t) { return c_int[t]; }
GDExtensionPtrConstructor ctor(GDExtensionVariantType t) { return c_ctor[t]; }
GDExtensionPtrDestructor dtor(GDExtensionVariantType t) { return c_dtor[t]; }

int64_t size_of(GDExtensionVariantType t, const void *native) {
	int64_t r = 0;
	m_size[t]((GDExtensionTypePtr)native, nullptr, &r, 0);
	return r;
}

void resize(GDExtensionVariantType t, void *native, int64_t n) {
	int64_t r = 0;
	const void *args[1] = {&n};
	m_resize[t](native, (const GDExtensionConstTypePtr *)args, &r, 1);
}

const uint8_t *bytes(const void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, p) ? p_pba_c(p, 0) : nullptr; }
uint8_t *bytes_w(void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, p) ? p_pba(p, 0) : nullptr; }
const int32_t *i32(const void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, p) ? p_pi32_c(p, 0) : nullptr; }
int32_t *i32_w(void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, p) ? p_pi32(p, 0) : nullptr; }
const float *f32(const void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, p) ? p_pf32_c(p, 0) : nullptr; }
float *f32_w(void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, p) ? p_pf32(p, 0) : nullptr; }
const double *f64(const void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, p) ? p_pf64_c(p, 0) : nullptr; }
double *f64_w(void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, p) ? p_pf64(p, 0) : nullptr; }
const int64_t *i64(const void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, p) ? p_pi64_c(p, 0) : nullptr; }
int64_t *i64_w(void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, p) ? p_pi64(p, 0) : nullptr; }
float *vec3_w(void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, p) ? (float *)p_pv3(p, 0) : nullptr; }
float *vec2_w(void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY, p) ? (float *)p_pv2(p, 0) : nullptr; }
float *color_w(void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, p) ? (float *)p_pcol(p, 0) : nullptr; }
const float *color(const void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY, p) ? (const float *)p_pcol_c(p, 0) : nullptr; }
const float *vec3(const void *p) { return size_of(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, p) ? (const float *)p_pv3_c(p, 0) : nullptr; }

Owned::Owned(GDExtensionVariantType t) : type(t) {
	memset(buf, 0, sizeof(buf));
	c_ctor[t](buf, nullptr);
}
Owned::~Owned() { c_dtor[type](buf); }

int64_t Args::i(int k) const {
	if (k >= count) return 0;
	if (is_ptr) return *(const int64_t *)p[k];
	GDExtensionVariantType t = variant_get_type(p[k]);
	if (t == GDEXTENSION_VARIANT_TYPE_INT) { int64_t v = 0; c_to[t](&v, (GDExtensionVariantPtr)p[k]); return v; }
	if (t == GDEXTENSION_VARIANT_TYPE_FLOAT) { double v = 0; c_to[t](&v, (GDExtensionVariantPtr)p[k]); return (int64_t)v; }
	if (t == GDEXTENSION_VARIANT_TYPE_BOOL) { uint8_t v = 0; c_to[t](&v, (GDExtensionVariantPtr)p[k]); return v; }
	return 0;
}

double Args::f(int k) const {
	if (k >= count) return 0.0;
	if (is_ptr) return *(const double *)p[k];
	GDExtensionVariantType t = variant_get_type(p[k]);
	if (t == GDEXTENSION_VARIANT_TYPE_FLOAT) { double v = 0; c_to[t](&v, (GDExtensionVariantPtr)p[k]); return v; }
	if (t == GDEXTENSION_VARIANT_TYPE_INT) { int64_t v = 0; c_to[t](&v, (GDExtensionVariantPtr)p[k]); return (double)v; }
	return 0.0;
}

const void *Args::obj(int k, GDExtensionVariantType t) const {
	if (k >= count) return nullptr;
	if (is_ptr) return p[k];
	if (variant_get_type(p[k]) != t) return nullptr;
	return c_int[t]((GDExtensionVariantPtr)p[k]);
}

const void *array_get(const void *arr, int64_t k) { return array_index_const(arr, k); }

void array_set_native(void *arr, int64_t k, GDExtensionVariantType t, void *native) {
	void *v = array_index(arr, k);
	variant_destroy(v);
	c_from[t](v, native);
}

void array_set_int(void *arr, int64_t k, int64_t val) {
	void *v = array_index(arr, k);
	variant_destroy(v);
	c_from[GDEXTENSION_VARIANT_TYPE_INT](v, &val);
}

void array_set_float(void *arr, int64_t k, double val) {
	void *v = array_index(arr, k);
	variant_destroy(v);
	c_from[GDEXTENSION_VARIANT_TYPE_FLOAT](v, &val);
}

// ---------------------------------------------------------------- class + method registration
struct MethodData { NativeFn fn; int argc; };

static void call_func(void *ud, GDExtensionClassInstancePtr, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr r_ret, GDExtensionCallError *err) {
	MethodData *md = (MethodData *)ud;
	err->error = GDEXTENSION_CALL_OK;
	if (argc < md->argc) {
		err->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		err->expected = md->argc;
		return;
	}
	Args a{false, (const void *const *)args, argc};
	Owned out(GDEXTENSION_VARIANT_TYPE_ARRAY);
	md->fn(a, out.ptr());
	variant_destroy(r_ret);
	c_from[GDEXTENSION_VARIANT_TYPE_ARRAY](r_ret, out.ptr());
}

static void ptrcall_func(void *ud, GDExtensionClassInstancePtr, const GDExtensionConstTypePtr *args, GDExtensionTypePtr r_ret) {
	MethodData *md = (MethodData *)ud;
	// arguments are declared as Variant, so ptrcall also passes Variant pointers
	Args a{false, (const void *const *)args, md->argc};
	md->fn(a, r_ret);
}

static const char *g_class_name = nullptr;
static void *g_class_sn = nullptr;
static void *g_parent_sn = nullptr;
static int g_dummy_instance = 1;

static GDExtensionObjectPtr create_instance(void *, GDExtensionBool) {
	GDExtensionObjectPtr o = p_construct(g_parent_sn);
	p_set_instance(o, g_class_sn, &g_dummy_instance);
	return o;
}

static void free_instance(void *, GDExtensionClassInstancePtr) {}

void register_class(const char *name, const char *parent) {
	g_class_name = name;
	g_class_sn = sn(name);
	g_parent_sn = sn(parent);
	GDExtensionClassCreationInfo6 info;
	memset(&info, 0, sizeof(info));
	info.is_exposed = 1;
	info.create_instance_func = create_instance;
	info.free_instance_func = free_instance;
	p_reg_class(library, g_class_sn, g_parent_sn, &info);
}

void register_method(const char *cls, const char *name, NativeFn fn, int argc) {
	MethodData *md = new MethodData{fn, argc};
	// arguments are untyped Variants (callers use dynamic calls); return type Array
	static GDExtensionPropertyInfo ret;
	static void *empty_sn = nullptr;
	static uint8_t empty_str[8];
	if (!empty_sn) {
		empty_sn = sn("");
		p_str_new(empty_str, "");
	}
	ret.type = GDEXTENSION_VARIANT_TYPE_ARRAY;
	ret.name = empty_sn;
	ret.class_name = empty_sn;
	ret.hint = 0;
	ret.hint_string = empty_str;
	ret.usage = 6;
	std::vector<GDExtensionPropertyInfo> ai(argc);
	std::vector<GDExtensionClassMethodArgumentMetadata> am(argc);
	for (int i = 0; i < argc; i++) {
		char buf[16];
		snprintf(buf, sizeof(buf), "a%d", i);
		ai[i].type = GDEXTENSION_VARIANT_TYPE_NIL;
		ai[i].name = sn(buf);
		ai[i].class_name = empty_sn;
		ai[i].hint = 0;
		ai[i].hint_string = empty_str;
		ai[i].usage = 6 | 131072;  // PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT
		am[i] = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	}
	GDExtensionClassMethodInfo mi;
	memset(&mi, 0, sizeof(mi));
	mi.name = sn(name);
	mi.method_userdata = md;
	mi.call_func = call_func;
	mi.ptrcall_func = ptrcall_func;
	mi.method_flags = GDEXTENSION_METHOD_FLAGS_DEFAULT;
	mi.has_return_value = 1;
	mi.return_value_info = &ret;
	mi.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
	mi.argument_count = argc;
	mi.arguments_info = argc ? ai.data() : nullptr;
	mi.arguments_metadata = argc ? am.data() : nullptr;
	p_reg_method(library, sn(cls), &mi);
}

} // namespace gdx
