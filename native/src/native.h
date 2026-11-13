// Shared declarations for RecraftNative modules.
#pragma once
#include "gdx.h"

#define RN_VERSION 1

// each module registers its methods here (light.cpp, mesher.cpp, density.cpp ...)
void register_native_methods(const char *cls);
