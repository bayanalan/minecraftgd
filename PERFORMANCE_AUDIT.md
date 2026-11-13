# Performance audit (round 2: frame rate and stutter)

Hardware: ASUS Zenbook A16, Snapdragon X2 Elite Extreme (18 threads), Adreno X2-90, display 2880x1800, AC power,
Windows "Balanced" plan. Settings for every run: fresh world seed 12345 (java_26_3 generator), render distance 16,
simulation distance 12, default graphics, V-Sync off, no FPS cap.

## Benchmarks

| Name | Command | Measures |
|---|---|---|
| F (flight, default) | `minecraftgd.exe -- --autoplay --gen=java_26_3 --fresh --seed=12345 --fpsbench=F` | after the world loads: 60 s creative sprint-flight (21.6 blocks/s, real controls) >= y 120 / 32 blocks above the terrain ahead, pitch 6 degrees down, through fresh terrain; FPS avg/median/1%/0.1% lows, frames > 16.7/33/50 ms, holes within rings 2/4/8, chunk waits, distance, frozen time; slow-frame attribution (main-thread parts, frame phases, uploads, mesh frees, pipeline compilations) |
| A (static) | `--fpsbench=A` | fully loaded world, stationary, 4 fixed views: steady-state rendering cost |
| E (loading) | `--loadtest=1` (load_test.gd) | world entry per ring, walking, flying, teleport, gen/s |
| Function profile | `tools/profile.ps1 -A "--autoplay ... --fpsbench=F --fsecs=40"` | GDScript self/total time per function (debug build only; via the remote-debugger protocol, tools/profiler_server.gd) |

Benchmarks run borderless fullscreen at native resolution unless `--res=WxH` is given. An on-screen readout shows
FPS with the run's 1% and 0.1% lows. Results go to `user://perf/fps_<stamp>/summary.json`.

Builds: release export `builds/windows-arm64/minecraftgd.exe` (export preset "Windows ARM64"; official 4.7.2 templates),
`builds/windows-x86_64/` (preset "Windows x86_64"). The editor binaries are debug builds; they are not used for the
numbers below unless marked.

## Results (F flight unless noted)

| Step | FPS avg | median | 1% low | 0.1% low | frames > 33 ms | max ms | notes |
|---|---|---|---|---|---|---|---|
| Baseline (ARM64 editor/debug, 1920x1080 windowed) | 124 | 187 | 18.6 | 11.6 | 127 | 149 | |
| + grass opacity fix, event dispatch, BERender rewrite | 124 | 187 | 20.1 | 11.8 | 117 | 166 | |
| + copy-on-write section snapshots, dispatch idle set | 142 | 196 | 21.2 | 11.5 | 91 | | |
| + spread random ticks, cached wanted order, sliced dispatch, queued unloads | 136 | 185 | 20.2 | 11.8 | 95 | 162 | run-to-run noise ~10 % |
| + deferred mesh RID frees | 159 | 206 | 20.7 | 11.5 | 112 | 161 | max = benchmark screenshots |
| Release export (ARM64), same settings | 152 | 185 | 30.1 | 14.1 | 22 | 161 | |
| + phased game tick, cached block-entity list; borderless 2880x1800; no mid-run screenshots | **164** | **176** | **66.0** | **40.3** | **0** | **27.7** | GPU 3.85 ms at 2880x1800, 63 chunks/s, no holes |

Static scene A (debug, 1920x1080): 135 -> 188 FPS avg; 1% low 51 -> 70.

## Root causes found (measured)

1. **Debug build.** The editor binary runs the game as a debug build: GDScript validates objects through a global
   lock and checks every access, so worker GDScript (features, structures) slowed the main thread's GDScript 2-5x in
   the same frames. Release export: tick cost in slow frames 28 -> 13 ms, frames > 33 ms 112 -> 22.
2. **Game tick in one frame.** All tick systems (random ticks, entities, particles, furnaces, redstone...) ran inside
   one frame every 50 ms: 15-30 ms spikes. Now phase 0 (player) runs when due, phases 1-5 on the following frames
   within 1.5 ms each, completing before the next tick (every system still ticks once per tick, same order).
3. **grass_block not opaque.** The side-overlay quad made the registry class grass blocks as cutout: they passed
   skylight, did not cull neighbour faces and let grass "spread" into the dirt under them (12,000 bogus block changes
   per minute, each a relight + remesh). Cube transparency now comes from the base faces only.
4. **Dispatch rescans.** ChunkManager walked all 1,369 wanted chunks every frame (1.5-2.3 ms). Now: work set from
   events, idle set for chunks waiting on neighbours, cached priority order, 1 ms slices.
5. **Snapshots copied every array** (96 per chunk per light/mesh job). Now copy-on-write per section.
6. **Mesh buffer destruction** (D3D12) on the main thread: queued, a few per frame (godot_voxel reports the same issue).
7. **Random ticks:** per-cell sampling native (`rt_sample`), handlers spread over the frames of a tick with a 1.5 ms cap,
   grass/leaves fast paths. Block-entity renderer rescanned 121 chunks continuously: now event-driven.

## Renderer experiment (not applied yet)

Same release build, flight F, `--rendering-method mobile`: GPU 4.17 -> 2.42 ms, render CPU 0.81 -> 1.0 ms, draws
847 -> 514, avg 144 -> 170 FPS, median 152 -> 188 (1% low 60 -> 50, within run noise). Static A: GPU 6.1 -> 3.05 ms,
draws 1,759 -> 798 (Forward+ renders a depth prepass). The world uses only sky background, linear tonemap and depth
fog, all supported by Mobile. Not used: the project stays on Forward+ (desktop-only app, user decision). Screenshots were identical. `--hidegroup=0` (all mesh groups below y 64 hidden):
triangles 2.30 -> 1.95 M only, no GPU gain from the surface — cave culling alone will not fix GPU time there.

## Measured ceiling (release ARM64, Forward+, borderless 2880x1800, V-Sync off)

| Scene | FPS avg / median | GPU | main-thread process phase |
|---|---|---|---|
| Empty scene: game sky shader + environment + one label (`-- --emptybench`) | 698 / 727 | 1.21 ms | ~0 |
| Flight F with every terrain mesh hidden (`--hidegroup=99`; simulation + generation running) | 295 / 341 | 1.38 ms | 1.97 ms (chunk manager 1.12, ticks 0.63) |
| Flight F, normal | 137-164 / 152-176 | 3.6-4.2 ms | 2.6-2.9 ms (+ render CPU 0.9-1.4 ms) |

Forward+ itself (sky pass, 3D buffer + tonemap pass, 2D, present at 5.2 MP) costs ~1.2 ms GPU per frame, so 800 FPS
(1.25 ms) at native resolution is not reachable with Forward+ on this GPU even with nothing drawn. Budget above that
floor: terrain GPU ~2.5 ms, terrain render CPU ~1 ms, game CPU ~2-2.8 ms per frame.

## Round 3 (2026-11-11): RenderingDevice terrain + main-thread work

Flight F, release ARM64, RD16/SD12, V-Sync off (each row adds to the previous; ±5–10 % run noise):

| step | native 2880x1800 avg / med | 1440x900 avg / med | evidence |
|---|---|---|---|
| start (Godot mesh instances, 1,100–1,400 draws) | 151 / 159 | — | GPU 4.7 ms, render CPU 0.96 |
| TerrainRD, storage-buffer vertex pulling, table + range search | 178 / 189 | — | GPU 3.76, render CPU 1.46 |
| indexed indirect draws (static quad index buffer, vertex reuse) | 222 / 242 | 393 / 454 | GPU 2.80, render CPU 0.54; A 184 -> 238 |
| hand drawn in the main view (no SubViewport) | 285 / 326 | 454 / 534 | hidden 2nd Forward+ render ~1.1 ms GPU |
| block-entity index, tick phase pacing, leaf filter, list/snapshot caches, dispatch batching, SoA culler | — | 475–491 / 550 | process 0.84 -> 0.52 ms/frame; cull 190 -> 101 µs |
| single view-projection matrix in the terrain VS | — | 443–480 / 514–553 | terrain pass 1.00 -> 0.93 ms (1440) |
| vertex-buffer fetch (attributes) instead of SSBO pulling | **336 / 372** | **551 / 661** | A terrain pass 1.93 -> 1.62 ms; A 313 -> 335 |
| native doAnimateTick sampling + `frame_queue_size=3` | **353 / 384** | **607 / 688** | 1440: 1% low 121 -> 137, max 31 -> 15 ms; native GPU-bound (unchanged by queue) |
| native + Render Scale 50 % (in-game setting) | 508 / 581 | — | GPU 1.51 ms |

How the hidden GPU work was found: a fixed 1 ms CPU busy-wait per frame (`--busy=1000`) changed the native frame time
by ~0 (GPU-bound) although the viewport GPU timer reported only 3.0 of the 4.3 ms frame; the empty scene has no such
gap, the in-game difference was the hand's full-screen SubViewport (`--nohand=1`: 222 -> 280 FPS).

Godot fixed passes in game (2880x1800, `--gpu-profile`): opaque pass 0.6–0.74 ms, tonemap 0.7–0.8, sky 0.28, canvas
0.22, prepass 0.15 — about twice the empty-scene cost of the same passes (0.31 / 0.37 / 0.32 / 0.21 / 0.05): textured
content compresses worse than an empty sky (bandwidth-bound passes). Isolated with `--emptybench --emptycomp/--emptynear`:
no setting or compositor effect causes it. At 1440x900 the same passes cost ~0.4 ms in total and the terrain pass
dominates (0.9 ms, vertex-bound: 1.2 ms at 4x the pixels).

Not applied (measured): exclusive fullscreen (no change), `rendering/driver/threads/thread_model=2` (Godot meshes:
151 -> 131 avg, 1% low 63 -> 24), depth prepass off (-0.06 ms GPU, opaque pass grows), frame queue 3 (no change).

## Remaining bottlenecks (next tasks)

- (Round 3 status above supersedes the numbers below.)
- GPU 3.85 ms/frame at 2880x1800 (1.4 M triangles, 1,100 draw calls): Sodium-style culling (per-section visibility /
  cave culling, per-direction face groups), compact vertex format, depth-prepass cost.
- Main thread per frame (median frame 5.7 ms): chunk commit/upload, remaining tick phases, other nodes' _process.
- Leaves: generated leaves lack the vanilla `distance` property, so decay uses a BFS per random tick (29 us each in
  large canopies); porting TreeFeature.updateLeaves + distance updates would make it O(1) (changes generated states).
- Remaining GDScript features/structures on workers (contention, 6+ workers do not help).
