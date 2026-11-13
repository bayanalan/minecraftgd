// Thread diagnostics and scheduling.
// thread_cycles() -> [cycles]: CPU cycles of the calling thread (QueryThreadCycleTime). Compared with wall time it
//   tells a thread that was descheduled or blocked (wall >> cycles) from one doing real work.
// set_thread_priority(p) -> [ok]: OS priority of the calling thread, -2..2 (lowest .. highest).
// cpu_sets() -> [PackedInt32Array]: per CPU set 5 ints (id, logical processor, core, last-level cache, efficiency class).
// set_thread_cpu_sets(ids: PackedInt32Array) -> [ok]: soft CPU-set preference of the calling thread (empty = any).
#include "native.h"
#include <vector>
#include <atomic>
#include <thread>
#include <mutex>
#include <map>
#include <string>
#include <algorithm>
#include <cstring>
#include <cstdio>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <psapi.h>
#pragma comment(lib, "user32.lib")
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
// no_power_throttling(main_thread: int) -> [ok]: opts the process (and, with 1, the calling thread) out of Windows
// power throttling (EcoQoS): a window without focus - the game running while another window is active - otherwise
// gets its threads parked on efficiency cores at low clocks in bursts (a fixed GDScript loop ran 10-17x slower).
bool fn_no_power_throttling(const Args &a, void *ret) {
	int ok = 0;
#ifdef _WIN32
	PROCESS_POWER_THROTTLING_STATE ps = {};
	ps.Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION;
	ps.ControlMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED | PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION;
	ps.StateMask = 0;
	ok = SetProcessInformation(GetCurrentProcess(), ProcessPowerThrottling, &ps, sizeof(ps)) ? 1 : 0;
	if (a.i(0) != 0) {
		THREAD_POWER_THROTTLING_STATE ts = {};
		ts.Version = THREAD_POWER_THROTTLING_CURRENT_VERSION;
		ts.ControlMask = THREAD_POWER_THROTTLING_EXECUTION_SPEED;
		ts.StateMask = 0;
		ok |= SetThreadInformation(GetCurrentThread(), ThreadPowerThrottling, &ts, sizeof(ts)) ? 2 : 0;
	}
#else
	(void)a;
#endif
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, ok);
	return true;
}
// thread_eco(on) -> [ok]: EcoQoS for the calling thread (on: power-efficient scheduling - efficiency cores, lower clocks;
// off: explicitly high QoS). Chunk workers in eco mode keep their load off the main thread's cluster / power budget.
bool fn_thread_eco(const Args &a, void *ret) {
	int ok = 0;
#ifdef _WIN32
	THREAD_POWER_THROTTLING_STATE ts = {};
	ts.Version = THREAD_POWER_THROTTLING_CURRENT_VERSION;
	ts.ControlMask = THREAD_POWER_THROTTLING_EXECUTION_SPEED;
	ts.StateMask = a.i(0) != 0 ? THREAD_POWER_THROTTLING_EXECUTION_SPEED : 0;
	ok = SetThreadInformation(GetCurrentThread(), ThreadPowerThrottling, &ts, sizeof(ts)) ? 1 : 0;
#else
	(void)a;
#endif
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, ok);
	return true;
}
// proc_stats() -> [page faults (process), kernel time, user time (calling thread, 100 ns units), private commit bytes].
// Per-frame deltas tell kernel work in the main thread (page faults, interrupts) from user-mode work.
bool fn_proc_stats(const Args &a, void *ret) {
	(void)a;
	int64_t pf = 0, kt = 0, ut = 0, pc = 0;
#ifdef _WIN32
	PROCESS_MEMORY_COUNTERS_EX pm = {};
	pm.cb = sizeof(pm);
	if (K32GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS *)&pm, sizeof(pm))) {
		pf = (int64_t)pm.PageFaultCount;
		pc = (int64_t)pm.PrivateUsage;
	}
	FILETIME c0, e0, k0, u0;
	if (GetThreadTimes(GetCurrentThread(), &c0, &e0, &k0, &u0)) {
		kt = ((int64_t)k0.dwHighDateTime << 32) | k0.dwLowDateTime;
		ut = ((int64_t)u0.dwHighDateTime << 32) | u0.dwLowDateTime;
	}
#endif
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 4);
	array_set_int(ret, 0, pf);
	array_set_int(ret, 1, kt);
	array_set_int(ret, 2, ut);
	array_set_int(ret, 3, pc);
	return true;
}
// wndproc_probe(hwnd) -> [ok]: wraps the game window's procedure and records every message whose handling takes
//   over 1 ms; wndproc_slow() -> [PackedInt64Array (message, usec, ms since install) triples, messages handled].
//   Diagnostic for the once-a-second main-thread stall between the draw and the next frame.
#ifdef _WIN32
static WNDPROC g_orig_proc = nullptr;
static std::vector<int64_t> g_slow_msgs;
static int64_t g_msg_count = 0;
static std::map<uint32_t, int64_t> g_msg_hist;
static LARGE_INTEGER g_qpf, g_qp0;
static LRESULT CALLBACK probe_wndproc(HWND h, UINT m, WPARAM w, LPARAM l) {
	LARGE_INTEGER a, b;
	QueryPerformanceCounter(&a);
	LRESULT r = CallWindowProcW(g_orig_proc, h, m, w, l);
	QueryPerformanceCounter(&b);
	g_msg_count++;
	g_msg_hist[m]++;
	int64_t us = (b.QuadPart - a.QuadPart) * 1000000 / g_qpf.QuadPart;
	if ((us > 1000 || m == 0x7f || m >= 0xc000) && g_slow_msgs.size() < 3000) {
		g_slow_msgs.push_back((int64_t)m);
		g_slow_msgs.push_back(us);
		g_slow_msgs.push_back((a.QuadPart - g_qp0.QuadPart) * 1000 / g_qpf.QuadPart);
	}
	return r;
}
#endif
bool fn_wndproc_probe(const Args &a, void *ret) {
	int ok = 0;
#ifdef _WIN32
	HWND h = (HWND)(intptr_t)a.i(0);
	if (h && !g_orig_proc) {
		QueryPerformanceFrequency(&g_qpf);
		QueryPerformanceCounter(&g_qp0);
		g_orig_proc = (WNDPROC)SetWindowLongPtrW(h, GWLP_WNDPROC, (LONG_PTR)probe_wndproc);
		ok = g_orig_proc != nullptr ? 1 : 0;
	}
#else
	(void)a;
#endif
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, ok);
	return true;
}
bool fn_wndproc_slow(const Args &a, void *ret) {
	(void)a;
	Owned arr(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY);
#ifdef _WIN32
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, arr.ptr(), (int64_t)g_slow_msgs.size());
	int64_t *w = i64_w(arr.ptr());
	for (size_t k = 0; k < g_slow_msgs.size(); k++) w[k] = g_slow_msgs[k];
	g_slow_msgs.clear();
#endif
	Owned hist(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY);
#ifdef _WIN32
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, hist.ptr(), (int64_t)g_msg_hist.size() * 2);
	int64_t *hw = i64_w(hist.ptr());
	int64_t hk = 0;
	for (auto &kv : g_msg_hist) {
		hw[hk++] = kv.first;
		hw[hk++] = kv.second;
	}
#endif
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 3);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, arr.ptr());
	array_set_native(ret, 2, GDEXTENSION_VARIANT_TYPE_PACKED_INT64_ARRAY, hist.ptr());
#ifdef _WIN32
	array_set_int(ret, 1, g_msg_count);
#else
	array_set_int(ret, 1, 0);
#endif
	return true;
}
// stall_sampler(on) -> [ok]: diagnostic. A sampler thread watches the frame mark (frame_mark() each frame from the main
//   thread); while a frame runs past 2.5 ms it suspends the main thread every ~150 us and records its call stack (16
//   frames, RtlVirtualUnwind). stall_report() -> [PackedByteArray: UTF-8 lines "count: module+offset caller ..." by count].
#ifdef _WIN32
static std::atomic<int64_t> g_mark{0};
static std::atomic<bool> g_samp_run{false};
static HANDLE g_main_thread = nullptr;
static std::thread g_samp_thread;
static std::mutex g_samp_mx;
static std::map<std::vector<uint64_t>, int> g_stacks;

static void sampler_loop() {
	LARGE_INTEGER f;
	QueryPerformanceFrequency(&f);
	const int64_t thr = f.QuadPart * 25 / 10000;
	const int64_t gap = f.QuadPart * 15 / 100000;
	int64_t next = 0;
	while (g_samp_run.load()) {
		LARGE_INTEGER n;
		QueryPerformanceCounter(&n);
		int64_t m = g_mark.load();
		if (m == 0 || n.QuadPart - m <= thr || n.QuadPart < next) {
			YieldProcessor();
			continue;
		}
		next = n.QuadPart + gap;
		uint64_t pcs[16];
		int np = 0;
		if (SuspendThread(g_main_thread) == (DWORD)-1) continue;
		CONTEXT ctx;
		memset(&ctx, 0, sizeof(ctx));
		ctx.ContextFlags = CONTEXT_FULL;
		if (GetThreadContext(g_main_thread, &ctx)) {
			for (int k = 0; k < 16; k++) {
#if defined(_M_ARM64)
				DWORD64 pc = ctx.Pc;
#else
				DWORD64 pc = ctx.Rip;
#endif
				if (pc == 0) break;
				pcs[np++] = pc;
				DWORD64 img = 0;
				PRUNTIME_FUNCTION fe = RtlLookupFunctionEntry(pc, &img, nullptr);
				if (!fe) {
#if defined(_M_ARM64)
					if (ctx.Lr == pc) break;
					ctx.Pc = ctx.Lr;
#else
					ctx.Rip = *(DWORD64 *)ctx.Rsp;
					ctx.Rsp += 8;
#endif
					continue;
				}
				PVOID hd = nullptr;
				DWORD64 ef = 0;
				RtlVirtualUnwind(0, img, pc, fe, &ctx, &hd, &ef, nullptr);
			}
		}
		ResumeThread(g_main_thread);
		std::vector<uint64_t> key(pcs, pcs + np);
		std::lock_guard<std::mutex> lk(g_samp_mx);
		g_stacks[key]++;
	}
}
#endif
bool fn_frame_mark(const Args &a, void *ret) {
	(void)a;
#ifdef _WIN32
	LARGE_INTEGER n;
	QueryPerformanceCounter(&n);
	g_mark.store(n.QuadPart);
#endif
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 0);
	return true;
}
bool fn_stall_sampler(const Args &a, void *ret) {
	int ok = 0;
#ifdef _WIN32
	if (a.i(0) != 0 && !g_samp_run.load()) {
		g_main_thread = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, GetCurrentThreadId());
		if (g_main_thread) {
			g_samp_run.store(true);
			g_samp_thread = std::thread(sampler_loop);
			ok = 1;
		}
	} else if (a.i(0) == 0 && g_samp_run.load()) {
		g_samp_run.store(false);
		g_samp_thread.join();
		ok = 1;
	}
#else
	(void)a;
#endif
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_int(ret, 0, ok);
	return true;
}
bool fn_stall_report(const Args &a, void *ret) {
	(void)a;
	std::vector<std::string> lines;
#ifdef _WIN32
	std::vector<std::pair<int, std::vector<uint64_t>>> v;
	{
		std::lock_guard<std::mutex> lk(g_samp_mx);
		for (auto &kv : g_stacks) v.push_back({kv.second, kv.first});
	}
	std::sort(v.begin(), v.end(), [](const auto &x, const auto &y) { return x.first > y.first; });
	for (size_t i = 0; i < v.size() && i < 25; i++) {
		std::string s = std::to_string(v[i].first) + ":";
		for (uint64_t pc : v[i].second) {
			HMODULE h = nullptr;
			char nm[MAX_PATH] = "?";
			if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)pc, &h) && h) {
				GetModuleFileNameA(h, nm, MAX_PATH);
			}
			const char *base = strrchr(nm, 92);
			char buf[MAX_PATH + 32];
			snprintf(buf, sizeof(buf), " %s+0x%llx", base ? base + 1 : nm, (unsigned long long)(pc - (uint64_t)h));
			s += buf;
		}
		lines.push_back(s);
	}
#endif
	std::string all;
	for (auto &l : lines) {
		all += l;
		all += (char)10;
	}
	Owned arr(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY);
	resize(GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, arr.ptr(), (int64_t)all.size());
	if (!all.empty()) memcpy(bytes_w(arr.ptr()), all.data(), all.size());
	resize(GDEXTENSION_VARIANT_TYPE_ARRAY, ret, 1);
	array_set_native(ret, 0, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, arr.ptr());
	return true;
}
} // namespace
void register_diag(const char *cls) {
	register_method(cls, "no_power_throttling", fn_no_power_throttling, 1);
	register_method(cls, "thread_eco", fn_thread_eco, 1);
	register_method(cls, "thread_cycles", fn_thread_cycles, 0);
	register_method(cls, "proc_stats", fn_proc_stats, 0);
	register_method(cls, "wndproc_probe", fn_wndproc_probe, 1);
	register_method(cls, "wndproc_slow", fn_wndproc_slow, 0);
	register_method(cls, "frame_mark", fn_frame_mark, 0);
	register_method(cls, "stall_sampler", fn_stall_sampler, 1);
	register_method(cls, "stall_report", fn_stall_report, 0);
	register_method(cls, "set_thread_priority", fn_set_thread_priority, 1);
	register_method(cls, "cpu_sets", fn_cpu_sets, 0);
	register_method(cls, "set_thread_cpu_sets", fn_set_thread_cpu_sets, 1);
}