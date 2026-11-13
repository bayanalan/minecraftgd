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
- [~] Grass looks denser than vanilla: placement matches the 26.3 data (noise_threshold_count 5 / 10 x 32 tries, trapezoid
      offsets, air filter, survival check); the dense look was likely mipmapped cutout plants (vanilla mips now). Recheck in game
- [~] Village house placement wonky (earlier): seed 12345 plains village (-144, -832) rendered - houses on beard terraces,
      planks streets over water, farms at water level; matches Java's behaviour as far as visible. Needs the case you saw
- [~] Hand-coded structures: swamp hut, jungle temple and desert pyramid now run Java's StructurePiece code (new JavaPieces: orientation transforms + state mirror / rotation, generateBox / selectors, fillColumnDown, reoriented
      chests, trap dispensers, witch + cat), mineshafts run MineshaftPieces (room with dirt floor + entrances + dome,
      corridors with supports / torches / cobwebs / rails / chests / cave-spider spawners and log pillars or chains,
      crossings, stairs, recursive layout, moveBelowSeaLevel / mesa lift, liquid and deep-dark checks);
      SinglePieceStructure sea-level corner check (also in /locate); /place
      structure. Nether fortress now runs NetherFortressPieces (all 14 piece types, weighted picks with limits,
      112-block reach, depth 30, moveInsideHeights 48..70, blaze spawner thrones, wart rooms, chests); structure
      fences / bars get their connections after generation (Java SHAPE_CHECK_BLOCKS post-processing, also mineshafts);
      natural spawning uses structure spawn_overrides (fortress enemies incl. wither skeletons, witches / cats in huts,
      guardians, pillagers, nothing in trial chambers / ancient cities). Desert pyramid 1.20 cellar + suspicious sand
      not reproduced. Stronghold now runs StrongholdPieces (11 weighted pieces + filler corridors, small doors -
      openings / oak / iron with buttons / grates, forced five-way crossing, library min depth 4 / portal room 5,
      retries until a portal room exists, moveBelowSeaLevel, bury terrain adaptation, libraries with chandeliers,
      prison cells, chests, the silverfish spawner and 10 % eyes per frame). Neighbour chunks' features (ore blobs)
      no longer overwrite structure blocks: a chunk's own writes are applied last at decoration. Ocean monument now
      runs OceanMonumentPieces (building shell, wings, entrance, roof, pillars to the sea floor, the 5 x 5 x 3 room
      graph with Java's pruning, 7 room fitters, sponge rooms, gold core, 3 elder guardians, the 29-block ocean
      surroundings check via native getBiomesWithin). Woodland mansion now generated (see fixed.md)
Rendering:
End:
Performance:
- [~] FPS goals: 500 x86_64 (emulated), 800 ARM64 native with 1 % lows 300-350 (ARM) / 100-150 (x64); stutters gone.
      2026-11-13 (late): the flight stutter is chunk streaming, not rendering: flying in a circle over loaded terrain
      (--fcircle=40) gives 1 % low 142-162 vs 76-96 straight. Cause: the chunk workers ran on the second Prime cluster
      and dragged the main thread's cluster clock down (main thread running but 10-20x slower). Workers now use the 6
      Performance cores (lower efficiency class; the second Prime cluster only while loading / the initial fill / when
      falling 3+ rings behind): same 65 chunks / s in flight, flight avg 240 -> 390-430, 1 % low 70 -> 133-166, 0.1 %
      low 42 -> 81-95, max 38 -> 14-17 ms, slowed main-thread frames 195 -> 8; static views avg 465 / 1 % low 198 /
      0.1 % 121. Remaining: after ~25 s of uncapped load the laptop throttles (slowed frames cluster late in long
      runs, thermal / power state), GPU p99 ~5.6 ms at 2880x1800
      Once-a-second 3-9 ms hitch (every scene, also a bare Godot project and a plain Windows Forms window): the
      ASUS ATKHotkey service broadcasts "ACPI Notification through ATKHotkey from BIOS" (registered message) to every
      top-level window once a second; the game thread waits inside Windows' PeekMessage meanwhile (main-thread stack
      sampler: --emptybench --stallprobe / --msgprobe; arrival times match the slow frames exactly). Not game code:
      turning the ASUS hotkey service off removes it
      2026-11-13: native per-job scratch (density evaluator caches ~2 MB, density array, decorate / light / mesh
      buffers) now reused per thread instead of allocated, paged in and freed for every chunk: flight bench worst
      frame 35.0 -> 18.3 ms, 0.1 % low 63 -> 76, 1 % low 125 -> 130, mesh job 1.1 -> 0.7 ms. Per-chunk generation
      time still rises with more workers (12 -> 18 ms at 8 workers): all-core clock limit, not allocation
      Remaining spikes: the main thread's fixed GDScript probe loop runs 10-17x slower (descheduled / throttled core);
      the process now opts out of Windows power throttling (EcoQoS) at world start (--ecoqos keeps it for A/B)
      Root cause of the remaining slow frames (2026-11-13, per-frame GPU time + main-thread cycle counter): in static views
      (nothing streaming) CPU and GPU slow down together in bursts (main thread ~10x slower while running, GPU 2 -> 4-5
      ms): the SoC power limit when running uncapped. Static 1 % low ~85-100 uncapped vs 137-160 at a 240 cap (main
      thread pinned; unpinned 82-112). GPU per frame: p50 2.0, p95 4.6, p99 5.5 ms; Forward+ fixed passes at 5.2 MP
      leave no room for 800 avg without a lower render scale / another renderer (both excluded). Fewer chunk workers
      (--adapt: 2 when the near rings are complete) gave +20-30 % avg FPS but no better 1 % lows: opt-in only
      Flight bench F (ARM64 release, 2880x1800, RD16): start of this round avg 282 / 1 % 80 / 0.1 % 53 / max 24-65 ms;
      now avg 284-314 / 1 % 90-113 / 0.1 % 61-63 / max 17 ms. Done: TerrainRD vertex pages preallocated at load (new
      64 MB pages mid-flight stalled the GPU 8-22 ms), full fast-core pinning (main + workers, default), advancement
      criteria indexed by trigger (2 ms), wanted-chunk order sorted natively (12 ms), sky material params skipped when
      SkyRD draws, SkyState split by dependency, unchanged shader globals not re-uploaded, snow / ice random ticks fast
      path, leaf particle emission fast path, native leaf-filter buffers reused. Remaining slow frames are GPU time
      (draw 4-5.5 ms vs 2.7 avg): Godot's fixed Forward+ passes cost ~2.2 ms at 2880x1800 (see fixed.md, round 3)
- [~] Chunk generation "instant": RD16 fully visible 14.5 s -> 8.9 s (spawn 1.3 s, ring 8 3.9 s); per chunk gen
      25.5 -> 10.7 ms (density: per-node cell corner cache, cell-order fill, provably-air cells skipped, whole-cell
      batch evaluation of the final density - all bit-exact, --nativecheck 0 diffs), features 15 -> 6 ms (region
      metadata native). Next: surface rules (4-7 ms / chunk, per stone block), dispatch utilisation (63 %), beard
      chunks (per-block beard_at), more workers only while loading (8 workers: ring 16 7.3 s but -10 % FPS in flight)
      2026-11-13: ring 16 now 12.5-13.3 s on this machine after hours of continuous load (gen 12 ms, features 9-12 ms,
      utilisation 58-60 %). A/B tests rule out the new mineshafts, ruined portals, update priorities and translucent
      face merging (all within noise); 8 / 10 workers give 11.3 / 11.6 s with gen 16 / 23 ms per chunk (contention).
      Sculk patches moved native (the GDScript placement loop cost 2.2 s per run); mineshaft placement 2.8 -> 1.5 s
      2026-11-13 (late): jigsaw assembly without per-jigsaw dictionary copies, name-filtered attach candidates and
      replayed random calls for repeat candidates that already failed (trial chambers 420 -> 40-60 ms per start, 20
      starts identical piece for piece); template state rotation / mirror cached; decorate's liquid-origin map is a
      flat per-thread array instead of a hash map (decorate 2.9 -> 1.5 ms / chunk)
- [~] Loot generation, chunk loading, locating feel slow: /locate measured 1-233 ms for 14 structure types (seed 12345;
      stronghold / buried treasure slowest), now with Java's generation-point checks (temples, end cities) so it never
      points at a spot where nothing generates; chunk loading: see the chunk generation entry above
Gameplay / UI:
- [~] Mob animation smooth + modern AI (interpolation, look / body rotation controls, A* pathfinding, arm poses):
      verify in game; probe timing split (15 ms worst step)
Build:
- [ ] Copper Age content: copper golems exist as mobs but do not sort items (copper chest -> chests), no copper golem
      statue; shelves have no slot interaction / hotbar swapping. Exact 26.3 mechanics need a reference (not guessed)
Earlier, still open (re-checked 2026-11-13): parched arm / leg
wraps; nautilus exact model. (Recipe book search, loom banners and offhand use exist - see fixed.md.)

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
