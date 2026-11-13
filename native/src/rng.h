// Java-compatible random sources, bit-exact with scripts/core/random_sources.gd (LegacyRandom LCG, Xoroshiro128++,
// positional factories). All arithmetic is wrapping 64-bit like GDScript ints.
#pragma once
#include <cstdint>

namespace rn {

static inline int64_t wmul(int64_t a, int64_t b) { return (int64_t)((uint64_t)a * (uint64_t)b); }
static inline int64_t wadd(int64_t a, int64_t b) { return (int64_t)((uint64_t)a + (uint64_t)b); }
static inline int64_t to_i32(int64_t v) { v &= 0xFFFFFFFFLL; return v >= 0x80000000LL ? v - 0x100000000LL : v; }

// Mth.getSeed(x, y, z) >> 16 (RandomSources.pos_seed)
static inline int64_t pos_seed(int64_t x, int64_t y, int64_t z) {
	int64_t l = to_i32(wmul(x, 3129871)) ^ wmul(z, 116129781) ^ y;
	l = wadd(wmul(wmul(l, l), 42317861), wmul(l, 11));
	return l >> 16;
}

struct LegacyRandom {
	int64_t seed = 0;
	LegacyRandom() {}
	explicit LegacyRandom(int64_t s) { set_seed(s); }
	void set_seed(int64_t s) { seed = (s ^ 0x5DEECE66DLL) & 0xFFFFFFFFFFFFLL; }
	int64_t next(int bits) {
		seed = wadd(wmul(seed, 0x5DEECE66DLL), 0xB) & 0xFFFFFFFFFFFFLL;
		int64_t v = (seed >> (48 - bits)) & 0xFFFFFFFFLL;
		return v >= 0x80000000LL ? v - 0x100000000LL : v;
	}
	int64_t next_int() { return next(32); }
	int64_t next_int_bound(int64_t bound) {
		if ((bound & -bound) == bound) {
			int64_t pv = (wmul(bound, next(31)) >> 31) & 0xFFFFFFFFLL;
			return pv >= 0x80000000LL ? pv - 0x100000000LL : pv;
		}
		int64_t bits, val;
		while (true) {
			bits = next(31);
			val = bits % bound;
			if (bits - val + (bound - 1) < 0x80000000LL) break;
		}
		return val;
	}
	int64_t next_long() { int64_t a = next(32); int64_t b = next(32); return wadd((int64_t)((uint64_t)a << 32), b); }
	double next_double() { int64_t a = next(26); int64_t b = next(27); return (double)wadd(a << 27, b) * 1.1102230246251565e-16; }
	double next_float() { return (double)next(24) / (double)(1 << 24); }
	bool next_bool() { return next(1) != 0; }
};

struct Xoroshiro {
	int64_t lo, hi;
	Xoroshiro(int64_t a = 0, int64_t b = 0) : lo(a), hi(b) {
		if (lo == 0 && hi == 0) { lo = -7046029254386353131LL; hi = 7640891576956012809LL; }
	}
	int64_t next_long() {
		uint64_t l = (uint64_t)lo, m = (uint64_t)hi;
		uint64_t s = l + m;
		uint64_t n = ((s << 17) | (s >> 47)) + l;
		m ^= l;
		lo = (int64_t)(((l << 49) | (l >> 15)) ^ m ^ (m << 21));
		hi = (int64_t)((m << 28) | (m >> 36));
		return (int64_t)n;
	}
	int64_t next_int() { int64_t v = next_long() & 0xFFFFFFFFLL; return v >= 0x80000000LL ? v - 0x100000000LL : v; }
	int64_t next_bits(int bits) { return (int64_t)(((uint64_t)next_long()) >> (64 - bits)); }
	int64_t next_int_bound(int64_t bound) {
		int64_t l = next_long() & 0xFFFFFFFFLL;
		int64_t m = wmul(l, bound);
		int64_t n = m & 0xFFFFFFFFLL;
		if (n < bound) {
			int64_t i = ((~bound + 1) & 0xFFFFFFFFLL) % bound;
			while (n < i) {
				l = next_long() & 0xFFFFFFFFLL;
				m = wmul(l, bound);
				n = m & 0xFFFFFFFFLL;
			}
		}
		return m >> 32;
	}
	double next_double() { return (double)next_bits(53) * 1.1102230246251565e-16; }
	double next_float() { return (double)next_bits(24) * 5.9604645e-8; }
	bool next_bool() { return (next_long() & 1) != 0; }
};

// Positional factory: Xoroshiro (lo, hi) or legacy (seed). at() returns a generator of either kind.
struct AnyRandom {
	bool legacy = false;
	LegacyRandom l;
	Xoroshiro x;
	int64_t next_int_bound(int64_t b) { return legacy ? l.next_int_bound(b) : x.next_int_bound(b); }
	double next_float() { return legacy ? l.next_float() : x.next_float(); }
	double next_double() { return legacy ? l.next_double() : x.next_double(); }
	int64_t next_long() { return legacy ? l.next_long() : x.next_long(); }
	bool next_bool() { return legacy ? l.next_bool() : x.next_bool(); }
};

struct Positional {
	bool legacy = false;
	int64_t lo = 0, hi = 0;   // legacy: lo = seed
	AnyRandom at(int64_t px, int64_t py, int64_t pz) const {
		AnyRandom r;
		r.legacy = legacy;
		if (legacy) {
			r.l = LegacyRandom(pos_seed(px, py, pz) ^ lo);
		} else {
			int64_t t = to_i32(wmul(px, 3129871));
			int64_t l = t ^ wmul(pz, 116129781) ^ py;
			l = wadd(wmul(wmul(l, l), 42317861), wmul(l, 11));
			r.x = Xoroshiro((l >> 16) ^ lo, hi);
		}
		return r;
	}
};

} // namespace rn
