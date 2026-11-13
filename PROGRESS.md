# Recraft 2 — PROGRESS (resume from here)

Spec: `minecraft_godot_master_prompt.md`. Engine: Godot 4.7.2. Machine: ASUS Zenbook A16, Snapdragon X2 Elite Extreme
(ARM64, 18 threads), Adreno X2-90, display 2880x1800.
- Native ARM64 editor (official, signed): `%LOCALAPPDATA%\Recraft2Tools\godot-4.7.2-arm64\Godot_v4.7.2-stable_windows_arm64_console.exe`
  — verified ARM64 process + ARM64 GDExtension (`[native] RecraftNative v1 (arm64) loaded`, `--nativecheck` all equal).
- x64 Steam editor (runs under emulation): `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`.
- Export templates 4.7.2 (official) installed in `%APPDATA%\Godot\export_templates\4.7.2.stable\` (Windows only).
- `tools/gd.ps1` uses `$env:GODOT` (default: Steam x64 editor). Set `$env:GODOT` to the ARM64 editor for native runs.
Assets: local MC 26.3 jar (read through the indexed JarAssetReader; private cache `user://minecraft_asset_cache/26.3/`).

## Commands
- Compile check: `powershell -ExecutionPolicy Bypass -File tools/check.ps1`
- Tests: `tools/gd.ps1 -A "--headless --path . -- --test"` (add `--vanilla` for real-asset tests)
- **Release builds**: export presets `Windows ARM64` / `Windows x86_64` (export_presets.cfg) →
  `builds/windows-arm64/Recraft2.exe`, `builds/windows-x86_64/Recraft2.exe`
  (`<editor> --headless --path . --export-release "Windows ARM64" builds/windows-arm64/Recraft2.exe`).
- **FPS benchmark (main perf test)**: `powershell -File tools/bench.ps1 [-Scen F|A] [-NoExport] [-Pre "--rendering-method mobile"] [-Extra "--fsecs=40"]`
  exports the ARM64 release build and runs it. `--fpsbench=F` (default) = fresh world seed 12345, RD16/SD12, V-Sync +
  FPS caps off, **borderless fullscreen at native resolution**; after the world loads, 60 s creative **sprint-flight**
  with real controls (forward + sprint held, jump to climb) ≥ y 120 / 32 blocks above the terrain ahead, pitch 6°
  down, through fresh terrain. On-screen: FPS + 1% / 0.1% lows. Summary `user://perf/fps_<stamp>/summary.json`:
  FPS avg/median/1%/0.1% lows, frames >16.7/33/50 ms, render GPU/CPU time, draw calls, primitives, average frame
  phases (process / world_manager / chunk_manager / ticks / other nodes / draw), slow-frame attribution (>25 ms),
  holes in rings 2/4/8, chunk waits, gen/s, pipeline compilations. `--fpsbench=A` = stationary, 4 fixed views, fully
  loaded world. Options: `--res=WxH` (windowed), `--workers=N`, `--hidegroup=N` (experiment: hide mesh group N).
- **Function profiler** (debug builds only): `powershell -File tools/profile.ps1 -A "--autoplay --gen=java_26_3 --fresh --seed=12345 --fpsbench=F --fsecs=40"`
  → per-function self/total ms per frame (all threads) in `%TEMP%\rc_profile.json` (tools/profiler_server.gd speaks
  Godot's remote-debugger protocol; the benchmark marks its window with EngineDebugger messages).
- Render probe (windowed): `tools/gd.ps1 -A "--path . -- --autoplay --gen=java_26_3 --fresh --secs=90 --seed=777"`
- Dump vanilla JSON: `-- --dumpjson=data/minecraft/worldgen/<path>.json`; reports/docs: `-- --report`
- **Real-game load test** (RD16 / SD12, V-Sync/caps off, fresh 26.3 world): `tools/gd.ps1 -A "--path . -- --autoplay --gen=java_26_3 --fresh --seed=12345 --loadtest=1 [--ltquick=60] [--workers=N] [--ltd=N]"`
  → phases A entry / B walk / C fly / D teleport; per-chunk traces → `user://perf/<stamp>/`
- **Native equality check**: `-- --autoplay --gen=java_26_3 --fresh --seed=12345 --nativecheck=1 [--dchunks=N --fchunks=N --decchunks=N --fonly=x,z]`
- Native library: `powershell -ExecutionPolicy Bypass -File tools/build_native.ps1 -Arch x86_64|arm64|all` (MSVC 14.44; raw GDExtension C API) → `native/bin/recraft_native.<arch>.dll`
- GDScript thread-contention probe: `-- --contention --threads=8`; worldgen thread scaling `-- --bench --mt=4|8 [--clone]`

## OPEN BUGS - remaining (fixed bugs and completed work: fixed.md)
Screenshots: c:\Users\Gerbilicious_Dude\Pictures\Screenshots\Screenshot 2026-11-12 <time>.png
Worldgen:
- [~] Poplar trees not vanilla-shaped [174713]: the 26.3 poplar_trunk_placer / poplar_foliage_placer code is not public;
      now a spindle (rhombus) crown with diamond layers and the branches inside it. APPROXIMATE: needs a vanilla reference
- [~] Grass looks denser than vanilla: placement matches the 26.3 data (noise_threshold_count 5 / 10 x 32 tries, trapezoid
      offsets, air filter, survival check); the dense look was likely mipmapped cutout plants (vanilla mips now). Recheck in game
- [ ] Cave water pools generate cut off [180044]
- [ ] Ice spikes cut off naturally [180259] (reproduced: seed 12345 near 704, -768, a tall spike with missing layers)
- [ ] Ruined nether portals generate inside terrain [180647]
- [ ] Crimson roots floating; water generating in the Nether [181222] [181333]
- [ ] Check: 8 overworld blocks = 1 Nether block
- [ ] Village house placement wonky (earlier)
Rendering:
- [ ] Gap glitch at the edge of ice [175817]; chunk-border ice glitch seen from under water [175857]
- [ ] Water flow not identical to vanilla [180119]; placed water lower resolution [181222]; flow updates only every ~10 s
- [~] Rain costs ~75% FPS [180829]: weather shader made cheaper (per-column light / fog, early discard; the column count
      is already Java's 21 x 21). Measure in game
End:
- [ ] End crystals too small [181845]; sometimes no fire / off [181912]; no healing beam to the dragon
- [ ] Dragon tail always straight; AI stiff (no curving / waving, drifts), stays away from the main island
Performance:
- [ ] FPS goals: 500 x86_64 (emulated), 800 ARM64 native; ARM build has lower average than expected (fewer stutters)
- [ ] Nether / End chunk generation very slow (seconds per chunk)
- [ ] Keep the other dimension partially loaded when travelling between dimensions
- [ ] Loot generation, chunk loading, locating feel slow
Gameplay / UI:
- [ ] Waterlogging for every waterloggable block
- [ ] Advancement toast text colours (challenge / goal); advancements screen like vanilla
- [ ] Elytra + firework: boost feel, firework rocket rendered as a camera-facing sprite, vanilla particles, trail from
      the held item in first person
- [~] Mob animation smooth + modern AI (interpolation, look / body rotation controls, A* pathfinding, arm poses):
      verify in game; probe timing split (15 ms worst step)
Build:
- [ ] native/bin/recraft_native.x86_64.dll is stale (locked by the running x64 Godot): rebuild with tools/build_native.ps1 -Arch x86_64 once it is closed. builds/windows-x86_64 already has the fresh DLL (built with -OutDir)
Earlier, still open: vanilla template structures (shipwreck, ocean ruins, ruined portal, igloo, fossils, end city),
hand-coded structures (desert pyramid, jungle temple, swamp hut, stronghold, fortress, monument, mansion), map zoom /
cartography, banners, offhand, recipe book search; parched arm / leg wraps; nautilus exact model.

## Key performance findings (see DECISIONS.md)
- GDScript function calls, member access on other objects, String-keyed Dictionary lookups and object creation contend across threads (8 threads: 8–25x slower per op). Local math, packed arrays, builtins, int-key dicts scale. => hot loops hoist members to locals and inline helpers; hot worker loops moved to native (see Performance overhaul); workers = clamp(cpu/3, 2, 5) (`ChunkManager.max_jobs`).
- Thread-local WorldGenerator per worker (`ChunkManager._thread_gen`).
- Stage deps: gen ≤R+2, features ≤R+1, decorate ≤R, light/mesh need neighbours *generated*; chunks lit against undecorated neighbours are `light_partial` and relit when neighbours decorate.
- Ore veins: range_choice conjunction reordering + exact per-cell interval classification (`SurfaceRules.conj_of`).

## Older roadmap (2026-11-10; partly done since - verify before relying on it)
1. Remaining feature types: speleothem_cluster, speleothem, large_dripstone, root_system, sculk_patch,
   fossil/template (desert well), bonus_chest. Woodland mansion not generated. No beardifier terrain adaptation.
2. Mob polish: horse/camel/sniffer/armadillo/breeze/warden rigs approximate; taming/riding; dragon path nodes.
3. Villager job sites, loom/cartography/lectern (banners, maps, books), armor trims, conduit, stained-glass beam tint.
4. Resource/data packs; LAN: container sync for clients, client portals/per-player dimensions.
5. Keep docs/STATUS.md, PARITY_MATRIX.md, BENCHMARKS.md, USER_GUIDE.md current.
7. Perf: see Performance round 2 → Next plan (fixed.md) and PERFORMANCE_AUDIT.md.
