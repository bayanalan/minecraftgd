// Thread diagnostics and scheduling.
// thread_cycles() -> [cycles]: CPU cycles of the calling thread (QueryThreadCycleTime). Compared with wall time it
//   tells a thread that was descheduled or blocked (wall >> cycles) from one doing real work.
// set_thread_priority(p) -> [ok]: OS priority of the calling thread, -2..2 (lowest .. highest).
// cpu_sets() -> [PackedInt32Array]: per CPU set 5 ints (id, logical processor, core, last-level cache, efficiency class).
// set_thread_cpu_sets(ids: PackedInt32Array) -> [ok]: soft CPU-set preference of the calling thread (empty = any).
#include "native.h"
#include <vector>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif

using namespace gdx;

namespace {
bool fn_thread_cycles(const Args &a, void *ret) {
	(void)a;
	unsigned long long c = 0;
#ifdef _WIN32
	QueryThreadCycleTime(GetCurrentThread(), &c);
#endif
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, (int64_t)c);
	return true;
}

bool fn_set_thread_priority(const Args &a, void *ret) {
	int ok = 0;
#ifdef _WIN32
	static const int map[5] = {THREAD_PRIORITY_LOWEST, THREAD_PRIORITY_BELOW_NORMAL, THREAD_PRIORITY_NORMAL,
			THREAD_PRIORITY_ABOVE_NORMAL, THREAD_PRIORITY_HIGHEST};
	int p = (int)a.i(0);
	p = p < -2 ? -2 : (p > 2 ? 2 : p);
	ok = SetThreadPriority(GetCurrentThread(), map[p + 2]) ? 1 : 0;
#else
	(void)a;
#endif
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, ok);
	return true;
}
bool fn_cpu_sets(const Args &a, void *ret) {
	(void)a;
	std::vector<int32_t> out;
#ifdef _WIN32
	ULONG len = 0;
	GetSystemCpuSetInformation(nullptr, 0, &len, GetCurrentProcess(), 0);
	std::vector<uint8_t> buf(len);
	if (len && GetSystemCpuSetInformation((PSYSTEM_CPU_SET_INFORMATION)buf.data(), len, &len, GetCurrentProcess(), 0)) {
		for (ULONG off = 0; off < len;) {
			auto *e = (PSYSTEM_CPU_SET_INFORMATION)(buf.data() + off);
			if (e->Type == CpuSetInformation) {
				out.push_back((int32_t)e->CpuSet.Id);
				out.push_back((int32_t)e->CpuSet.LogicalProcessorIndex);
				out.push_back((int32_t)e->CpuSet.CoreIndex);
				out.push_back((int32_t)e->CpuSet.LastLevelCacheIndex);
				out.push_back((int32_t)e->CpuSet.EfficiencyClass);
			}
			off += e->Size;
		}
	}
#endif
	Owned o(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, o.ptr(), (int64_t)out.size());
	if (!out.empty()) {
		int32_t *w = i32_w(o.ptr());
		for (size_t i = 0; i < out.size(); i++) w[i] = out[i];
	}
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, o.ptr());
	return true;
}

bool fn_set_thread_cpu_sets(const Args &a, void *ret) {
	int ok = 0;
#ifdef _WIN32
	const void *v = a.obj(0, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
	int64_t n = v ? size_of(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, v) : 0;
	std::vector<ULONG> ids;
	if (n > 0) {
		const int32_t *r = i32(v);
		for (int64_t i = 0; i < n; i++) ids.push_back((ULONG)r[i]);
	}
	ok = SetThreadSelectedCpuSets(GetCurrentThread(), ids.empty() ? nullptr : ids.data(), (ULONG)ids.size()) ? 1 : 0;
#else
	(void)a;
#endif
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, ok);
	return true;
}
} // namespace
void register_diag(const char *cls) {
	register_method(cls, "thread_cycles", fn_thread_cycles, 0);
	register_method(cls, "set_thread_priority", fn_set_thread_priority, 1);
	register_method(cls, "cpu_sets", fn_cpu_sets, 0);
	register_method(cls, "set_thread_cpu_sets", fn_set_thread_cpu_sets, 1);
}