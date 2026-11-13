# BENCHMARKS

Hardware: Snapdragon X2 (18 threads), Qualcomm Adreno X2-90, Windows 11 (machine appeared power/thermal
throttled ~1.8x during the later runs). Godot 4.7.2 stable Steam build, Forward+ D3D12. Assets: Java 26.3.
Command: `godot --headless --path . -- --bench --n=3` (single-threaded per stage); JSON in `user://bench/`.

| Stage (per chunk, single thread) | 2026-11-09 first | 2026-11-10 optimised (throttled) |
|---|---|---|
| terrain density | 400 ms | 251–270 ms |
| biomes | 20 ms | 32–35 ms |
| fill + aquifer | 162 ms | 163 ms |
| material rules | 153 ms | 215–235 ms |
| total generate | 951 ms | 913–942 ms (was 1555 before opts in same throttled state) |
| features (compute) | 413 ms | 343–368 ms |
| light (3×3) | 181 ms | 138 ms (was 326 throttled) |
| mesh (one column, 6 groups) | 91 ms | 150 ms |

Optimisations kept (each measured): indexed ZIP reader (registry build 600 s → 4.4 s), inlined Perlin,
memo inheritance across sub-batches (blended noise 3× → 1×), Java min/max short-circuits, cell interval
classification + cell-major interpolation (block stage 330 → 45 ms), palette compaction fast path,
inlined aquifer search (307 → 163 ms), per-section opacity cache in light BFS (326 → 138 ms).

In-game probe (`--autoplay --gen=java_26_3`, RD 12, 16 workers): spawn 35.9 s (before spawn-first radius),
frame median 33 ms / p95 81 ms while streaming, 424 mesh groups, 419 draw calls.

Targets not yet met: 60 FPS at 1080p while streaming; time-to-spawn < 5 s.
