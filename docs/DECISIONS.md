# DECISIONS (assumptions, approximations, provenance)

Source-of-truth codes: A = installed game data, B = official notes, C = controlled reference observation,
D = third-party/recalled algorithm, E = approximation.

| Topic | Decision | Source |
|---|---|---|
| Engine | Godot 4.7.2 stable (Steam), Forward+ (D3D12 default on Windows, Vulkan selectable) | env |
| Coordinates | block (x,y,z) occupies [x,x+1); visual = world − floating origin (chunk aligned, rebase > 512 blocks) | spec |
| Storage | per-section palette + byte indices (wide int32 > 256 entries) in RAM; zstd + MD5 region files on disk | E (speed in GDScript) |
| Packed arrays | Godot 4 packed arrays are shared by reference; worker snapshots `duplicate()` sections | measured |
| Noise | Java ImprovedNoise/Perlin/Normal/Blended algorithms; 26.3 `base_amplitude` field recorded but Java 1.18–1.21 normalisation (0.1666/expectedDeviation) used | D (26.3 normalisation unknown) |
| Density functions | 26.3 JSON compiled to DAG; batch evaluation; exact Java minValue/maxValue short-circuits; cell interval classification (exact) | A + D |
| Biomes | OverworldBiomeBuilder re-implemented (1.21.4 layout incl. pale_garden). dappled_forest = cool forest variant; sulfur_caves = hot+dry underground | D + E |
| Aquifer | NoiseBasedAquifer re-implemented; surface sampling via 16-block interpolated preliminary surface (chunk_surface_level semantics) | D + E |
| Material rules | 26.3 material_rule/material_condition interpreted; ore_vein rule semantics inferred from 26.3 DF structure (density threshold 0.7 / richness / gap<0) | A + E |
| Features | 26.3 placed_feature/feature JSON; Java decoration/feature seeds; features read pristine 3×3 terrain and emit write lists applied in fixed order (load-order independent) | A + D + E |
| Trees | foliage row formulas (blob/bush/spruce/pine/acacia/fancy/jungle) from Java; branching trunk placers approximated | D + E |
| Biome lookup | quart resolution, no Java fuzzy zoom | E |
| Lighting | per-chunk recompute over 3×3 region (sources ≤15 away), BFS decrement max(1, opacity); slabs/stairs treated as transparent | E |
| Colour | voxel/entity colour math in sRGB (like Java), converted to linear once in shader | D |
| Hardness etc. | original table in block_properties.gd (Java values from documentation) | D |
| Tool tiers | wood/gold 1, stone/copper 2, iron 3, diamond 4, netherite 5 vs needs_*_tool tags | A + D |
| Physics | Java travel(): accel = speed·0.216/slip³, drag slip·0.91, gravity 0.08, drag 0.98, jump 0.42 | D (tests confirm speeds) |
| 1.18.2 profile | uses the 26.3 data pipeline and is labelled APPROXIMATE (no 1.18.2 reference data) | blocked |
| Multiplayer button | disabled with explanation until LAN works | spec §28 |

## D-PERF-THREADS (2026-11-10): worker cap and contention-free hot loops
- Measured (`-- --bench-contention`, 8 vs 1 threads, constant per-thread work): local arithmetic 1.1x, packed-array reads 1.1x, builtins 1.1x, int-key Dictionary 1.05x — but any GDScript function call 8.5x, member read on another object 25x, String-key Dictionary 10x, `Object.new()` 5.5x slower. The Godot binary is x64 under ARM64 emulation, where shared atomic refcounts/locks are very expensive.
- `-- --bench-mt` chunk throughput: 1 thread 1.33/s, 2: 2.46/s, 4: 3.55/s, 8: 2.30/s. => `ChunkManager.max_jobs = clamp(cores/4, 2, 4)`.
- Rule for hot loops: hoist members of other objects into locals, inline tiny helpers (RNG steps, Aquifer status/pressure, positional random), avoid per-element String-key dict lookups, prefer batch evaluation.
- A native ARM64 Godot build would likely scale further; not used because only the Steam x64 editor is installed.

## D-LIGHT-DEPS (2026-11-10): relaxed lighting dependency
- Light/mesh of a chunk need its 3x3 neighbours generated (not decorated). Chunks lit with undecorated neighbours are flagged `light_partial` and relit (which remeshes) when a neighbour decorates. Generation halo shrinks from R+3 to R+2; spawn area (radius 1) is ready in ~6.6 s instead of ~32 s. Trade-off: border light may briefly miss neighbour trees until the relight.

## D-ORE-VEIN-CONJ (2026-11-10): exact reordering of ore-vein density
- 26.3 `ore_vein` density is nested `range_choice` whose out-of-range branches share one constant, i.e. a conjunction. Conditions are evaluated cheapest first (y, then interpolated toggle, then noise mask) with exact per-cell interval classification; results are identical to straight evaluation.
## D-NET-LAN (2026-11-10)
LAN multiplayer uses Godot's high-level multiplayer over ENet with our own messages, not the Minecraft protocol
(spec: own protocol acceptable, label it). Host-authoritative. Clients do NOT receive full chunk data: the
generator is deterministic, so a client generates pristine chunks itself and asks the host only for chunks it has
modified (host answers from memory if modified, else from its region files, else "generate"). This keeps LAN
traffic tiny (most chunks are a 20-byte reply) at the cost of client CPU. Chunk requests block a worker thread on a
semaphore (10 s timeout -> local generation). The host keeps chunks loaded around every remote player
(ChunkManager.extra_centers: generated, lit and simulated but not meshed). Remote players exist on the host as
Net.Proxy (a Player subclass) so the unchanged mob AI, item pickup and XP code target them; damage/items/XP/effects
are forwarded to the owning client. Clients do not simulate block updates, redstone, portals or spawning; their
entities are puppets from 20 Hz snapshots. Everyone shares the host's dimension (clients follow the host).

## D-PERF-JIGSAW (2026-11-10)
Measured (bench seed 777, 3 chunks at the origin, a trial chamber nearby): the feature stage was 2.45 s/chunk, of
which 2.29 s was underground structure placement. Profile: _el_jigsaws 6.2 s total, of which 4.9 s were first-time
template loads (GDScript NBT parsing + three sort_custom lambda sorts per template) and the rest a sort_custom per
call. Fixes, all order-preserving (village outputs unchanged: 112 / 107 pieces at the same centres; 150/150 tests):
selection-priority sort skipped when all priorities are equal (stable bucket pass otherwise), template blocks
ordered with native PackedInt64Array sorts of packed (y, x, z, index) keys, and parsed templates cached as native
binary in the private asset cache (<cache>/<version>/templates/, invalidated by block-state count). Result: 0.53
s/chunk features after the cache is warm (1.88 s on the first encounter).
Not done: village height probes (first_free_height) evaluate final density per block in a window (~18 ms each,
~800 per village start). Java interpolates cell corners; switching would be faster but changes piece heights, so it
needs a parity check first.

## D-NATIVE (2026-11-11): native GDExtension for world-gen, lighting and meshing hot loops
- Why: measured in the real game (RD16/SD12) chunks took 10–80 s to appear. GDScript under x86-64 emulation on the
  ARM64 Snapdragon does not scale past ~4 threads: method calls, member reads and allocations contend globally
  (benchmarks/contention_probe.gd: x5–x21 per op at 8 threads even on thread-local objects); native code scales x1.0.
- What: `native/` — RecraftNative (raw GDExtension C interface, no godot-cpp), x86_64 + arm64 DLLs built by
  tools/build_native.ps1. Every native stage is a bit-exact port of the GDScript reference (kept as fallback and as
  the oracle for `--nativecheck`), so world generation and saves are unchanged. Native: lighting, meshing, density
  functions + MCNoise, noise fill + aquifer, surface rules, carvers, climate biome lookup, section packing/heightmaps,
  decorate (write application + freeze), feature region, placed-feature engine (features_native.gd exports the
  compiled feature tree; unsupported trees run in GDScript per placed feature — each has its own RNG seed),
  structure random-spread candidates and first-free-height columns.
- Feature engine writes straight into the job-private flat region buffer (created per features job, never shared,
  so no copy-on-write is involved) and returns the write list for FCtx.writes.
- Not ported yet (GDScript): trees, structure piece placement / jigsaw assembly, springs, noise-count modifiers,
  dungeons, Nether/End feature types.

## D-SCHED (2026-11-11): chunk job scheduling
- Worker ready-queue (`ChunkManager._submit`): up to `max_jobs` worker-loop tasks drain a queue of
  `max_jobs + queue_depth` jobs, taking the lowest priority value (Chebyshev ring × 10 + stage: mesh < light <
  decorate < features < generate) — workers never wait a frame for the main thread and near chunks finish first.
- Look-ahead (forward) bias in the wanted order only while the player moves > 4 blocks/s.
- Unloaded / autosaved chunks are encoded by a background saver (evicted chunks or frozen copies); a chunk being
  re-created flushes its pending save first; explicit saves (quit, dimension change) drain the queue.
- Structure starts: one scan per chunk shared by all steps; a start being assembled by one worker is awaited by
  others instead of being assembled again.

## D-SORT-PARITY (2026-11-11): native tree decorators reproduce Godot's sort order
- Trees.gd sorts logs/leaves with Array.sort_custom (Godot SortArray: introsort, threshold 16, heap fallback, final
  insertion sort — unstable for >16 elements). Decorators iterate those lists while consuming random numbers, so the
  native engine ports SortArray exactly (featx.cpp GSort) instead of using std::sort; verified write-for-write.
- Workers: clamp(cpu/3, 2, 5) — 5 measured best in the real-game test once features went native (6+ only raised
  frame times; the remaining GDScript features still contend).
- Packed arrays are shared BY REFERENCE in Godot 4 (not copy-on-write between Variants): worker snapshots must stay
  explicit copies (test "snapshot immutable"); the feature region reads sections by reference only for chunks that
  nothing else can edit (not yet decorated), decorated neighbours are copied.
