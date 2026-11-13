// Module registration hub.
#include "native.h"

void register_light(const char *cls);
void register_mesher(const char *cls);
void register_density(const char *cls);
void register_terrain(const char *cls);
void register_region(const char *cls);
void register_feat(const char *cls);
void register_featx(const char *cls);
void register_chunkops(const char *cls);
void register_terrain_render(const char *cls);
void register_diag(const char *cls);
void register_clouds(const char *cls);
void register_collision(const char *cls);
void register_pathfind(const char *cls);
void register_icons(const char *cls);

void register_native_methods(const char *cls) {
	register_light(cls);
	register_mesher(cls);
	register_density(cls);
	register_terrain(cls);
	register_region(cls);
	register_feat(cls);
	register_featx(cls);
	register_chunkops(cls);
	register_terrain_render(cls);
	register_diag(cls);
	register_clouds(cls);
	register_collision(cls);
	register_pathfind(cls);
	register_icons(cls);
}
