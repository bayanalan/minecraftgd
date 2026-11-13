// Shared declarations for RecraftNative modules.
#pragma once
#include "gdx.h"
#include <vector>

// Scratch vector borrowed from a thread-local home for the duration of a call (large per-call buffers were allocated,
// paged in and freed for every chunk job). Nested borrows on one thread fall back to a fresh vector.
template <class T> struct TLBuf {
	std::vector<T> v;
	std::vector<T> *home;
	TLBuf(std::vector<T> &h, size_t n, T fill) : home(&h) { v.swap(h); v.assign(n, fill); }
	~TLBuf() { if (home->capacity() < v.capacity()) home->swap(v); }
};

#define RN_VERSION 1

// each module registers its methods here (light.cpp, mesher.cpp, density.cpp ...)
void register_native_methods(const char *cls);
