# AUTONOMOUS BUILD SPEC — GODOT 4.7.2 / GDSCRIPT VOXEL SURVIVAL GAME

> **EXPANDED V2 · November 9, 2026 · One-file implementation contract.** Sections **18–36** are REQUIRED, not optional appendices, and supersede conflicting narrow/optional scopes in Sections 0–17. They cover complete audio/music, player and entity animations, biome profiles, all play styles and world creation options, multiplayer, commands, every asset/registry-driven mechanic, modern 26.3 additions, benchmarks, and a restartable autonomous Claude Code loop. **Truth constraint:** a prompt cannot guarantee literal 1:1 behavior, higher FPS, or unlimited Claude execution; the agent must compare with locally owned Java reference output, mark unverified gaps, and keep building after every verified milestone.
## Minecraft Java 1.18.2 terrain fidelity + Java 26.3 feature target, high performance, local vanilla-asset import

> **Paste this entire document into Claude Code, or tell Claude Code to read this exact file and execute it.** This is an implementation order, acceptance specification, architecture brief, and autonomous decision policy. **Build actual working software**, not a proposal, scaffolding-only repository, illustrative snippets, or endless planning. Continue making and verifying progress without asking me clarifying questions. The goal is the strongest feasible playable result, not a dishonest claim that a complete commercial-scale game has been reproduced in one run.

## 0. Executive operating instructions — READ FIRST

You are the **lead engine programmer, graphics engineer, gameplay programmer, tooling engineer, tester, and technical artist**. Operate autonomously in the current project folder. Create a complete Godot project, source, editor resources, startup scene, importers, tests, benchmarks, and startup instructions. The **game/runtime must be Godot 4.7.2 stable with typed GDScript 4.x**; do not use C#, Rust, C++, GDExtension, Unity, Unreal, or Minecraft's executable code. Portable **Python 3 standard-library utilities are allowed solely for offline asset/config inspection and test fixtures**, never required to play the game; if possible, write importers in GDScript too. If a newer **stable** Godot 4 version is already installed, check API compatibility and use that stable version; **never choose a beta merely for recency**. Do not rely on nonexistent engine APIs.

**The primary product:** A runnable, native-feeling, high-performance, single-player voxel survival sandbox with world creation/loading, block interaction, exploration, biome-driven 3D terrain, caves, lighting, water, entities, crafting, survival, creative mode, and a faithful-feeling GUI. Target as much feature coverage of **Minecraft Java Edition 26.3 (Wilderness Bound, September 15, 2026)** as feasible while offering a **separate, explicitly versioned Java 1.18.2 world-generation mode**. Favor deterministic correctness and smooth gameplay over flashy incomplete systems.

### Immutable decisions: do not ask me

- Platform first: Windows 11 desktop (keyboard/mouse), with portable GDScript paths for Linux/macOS. Support Vulkan Forward+ with compatibility/mobile fallbacks where feasible. Windowed 1280×720 default; desktop-resizable; target 1080p.
- Unit convention: 1 voxel = 1 meter; X/Z horizontal, Y vertical, center of block at integer cell center *only if all collision/interaction/worldgen coordinates consistently use that convention*; use Minecraft-compatible integer block coordinates for persistence and world generation. State the chosen visual transform unambiguously.
- Starter defaults: render distance 12 chunks, simulation distance 6 chunks, near collision radius 3 chunks, FOV 70°, GUI scale auto, vsync on, frame cap 120, sensitivity 0.5, normal difficulty, survival, world seed random signed 64-bit integer, autosave 120 s; expose settings and persist them.
- Main simulation: **20 logical ticks per second (50 ms each)**, decoupled from rendering/physics; interpolation allowed. Day-night cycle **24,000 logical ticks**; random tick speed default **3** when matching vanilla mechanics.
- Core survival: health 20 points/10 hearts; hunger 20 points/10 drumsticks; item stack maximum 64 unless a specific item says 16/1; player inventory **36 main/hotbar slots** (27 + 9), equipment, offhand, 2×2 personal crafting, 3×3 crafting table. **Creative**: flight, instant break, unlimited block placement, creative inventory/search. **All play styles are mandatory end-state:** Survival, Creative, Adventure, Spectator, and Hardcore world mode (Hardcore is a world flag rather than a fifth numeric gamemode); implement in verified phases.
- No vendor lock-in: no paid APIs, telemetry, external hosted services, or networking required to play. No fabricated third-party dependencies. Prefer engine-native APIs, small cohesive scripts, and data-driven registries.
- Source of truth for 26.3: installed official **Java 26.3** client data/asset metadata and verified official notes. For **exact** Java 1.18.2 seed/world parity, use **1.18.2** data-generator reports plus **reference world output**. NEVER assume 26.3 JSON and 1.18.2 world generation have identical schema or rules.
- **Legal/privacy boundary:** Never embed, commit, ship, upload, or redistribute Mojang/Microsoft code, textures, sounds, fonts, models, or extracted proprietary content. Never bypass launcher ownership/account checks, pirate files, or contact external services for assets without permission. **Import only from assets already installed on the end user's computer**, to a private local cache on that computer, with a clear notice about usage rights. Do not advertise this as an official Minecraft product. A local-import scheme alone does **not** establish permission to distribute a substantially similar game; respect Mojang's EULA/Usage Guidelines. Code and generated placeholders must be original.
- Treat any statements such as “exactly identical” or “faster than Minecraft” as **hypotheses to validate with measurements**, not declarations. Record what has and has not been verified.

### Do work, avoid wasting tokens

1. Inspect repo with **one bounded directory listing and one targeted code search**; don't repeatedly dump huge files. If empty, create project immediately. Check `godot --version` or known executable candidates once; create a fallback test path if missing.
2. Write only a small `docs/STATUS.md` and `docs/DECISIONS.md`; keep an updated concise task checklist, parity gaps, latest test outputs, and the next action. Resume from these files after compaction. Prefer editing actual source over narrating.
3. **Don't announce each step**, restate the spec, ask rhetorical questions, reread unchanged code, or repeatedly make plans. Use short progress checkpoints only when a phase is verified or blocked.
4. Avoid large dependency installations, unbounded web search, outputting whole generated JSON/asset catalogs, giant shell logs, and excessive code duplication. Use concise commands with filtered output; inspect only relevant failures.
5. After each feature slice: implement → headless import/parse/run test → resolve warnings/errors → benchmark if relevant → commit locally if git exists and permitted → update `STATUS.md` → continue.
6. Build the **vertical playable slice first** before breadth. No fake demos, unimplemented menu buttons, empty methods presented as done, silent errors, speculative API usage, or TODO placeholders counted as features.
7. Operate until completed against the full backlog or genuinely stopped by an environmental/tool limit. If cut short, leave project runnable, persist the precise state and next executable action, and truthfully list missing functionality. **Never claim full Java 26.3 parity unless tested.**
8. Resolve missing decisions yourself using these priorities: correctness > stability > measured performance > fidelity > feature quantity > code elegance. For irreversible/destructive actions beyond this project folder, ask permission; otherwise proceed autonomously.

## 1. Definition of done and feature priority

**P0: true playable build (must pass before expansion).** The Godot project opens without script parse errors; launches a functioning main menu; finds/imports owned local Java assets on first start or runs in a clearly marked original placeholder mode; creates a named seeded world; spawns safely; generates persistent, seamless, 3D chunk terrain with real caves and varied biomes; displays chunk-meshed textured blocks, water, basic lighting/sky/fog; moves with accurate-enough physics and mouse controls; reliably breaks/places targeted blocks; works in creative and survival; has inventory/hotbar, tools, item drops, pause/options/save/quit; streams terrain while moving without severe main-thread stalls; reopens the same saved edits; and passes automated smoke tests.

**P1: depth and vanilla feel.** Accurate 1.18.2-compatible generator, underground ore/surface rules, large cave networks, 3D aquifers, multiple structures and terrain features, richer blocks/rotations/stairs/slabs/plants, block light, fluid propagation, transparent and animated textures, weather, hunger/armor/damage, recipes/furnaces, core passive/hostile mobs, item handling, sound effects, HUD/screens, spawn and light rules, biome tints, configurable graphics, and acceptable frame pacing.

**P2: breadth.** All 26.3 biomes/blocks/items/recipes/loot/structures insofar as installed metadata supports them; ALL mobs listed in §9, varied AI, breeding/taming/trading, Nether/End and bosses, redstone, hoppers, villagers, farming, enchantments, brewing, potions, particles, advancements, world maps, commands, accessibility, and day/night survival loops.

**P3: later implementation phase; its items are mandatory end-state unless explicitly designated optional in Section 18-36.** Verified cross-version same-seed parity, complete automation/redstone behavior, raids, deeper mob behaviors, portal travel, exploration structures and loot, minecarts/boats/rideable mobs, datapack-like customization, LAN/authoritative multiplayer, resource pack overrides, world import/export, language localization, polished animations and visual comparisons to vanilla 26.3. Do not claim features without passing functional tests.

**Important:** The three aims—exact 1.18.2 terrain generation, 26.3 added content, and maximal performance—sometimes conflict. Deliver **versioned world generation modes**, not a falsely 'exact' hybrid. Keep save formats tied to `generator_id`, `generator_version`, and content registry version so future upgrades don't silently alter old terrain.

## 2. Required repository shape (adapt only with a documented reason)

```text
project.godot
main.tscn
scenes/{boot,menus,world,player,ui,entities}/
scripts/
  app/{bootstrap,settings,save_manager,diagnostics}.gd
  assets/{minecraft_locator,jar_asset_reader,asset_index_reader,resource_registry,model_resolver,atlas_builder,animation_loader}.gd
  core/{coordinates,random_sources,registries,clock,events,voxel_raycast}.gd
  world/{world_manager,chunk_manager,chunk,section,chunk_job_scheduler,worldgen_1182,worldgen_263,biome_sampler,density_functions,caves,aquifer,features,structures,lighting,mesher,mesh_upload,collision,fluid,block_updates}.gd
  gameplay/{player_controller,inventory,item_stack,interaction,damage,crafting,recipe_registry,block_entities,redstone,game_rules}.gd
  entities/{entity_base,mob_base,mob_registry,spawn_manager,ai_sensing,ai_goals,navigation,combat,entity_renderer}.gd
  ui/{title_menu,create_world,world_list,loading_screen,hud,inventory_screen,crafting_screen,pause_menu,options_menu,video_settings,controls_settings,statistics,debug_overlay}.gd
  util/{binary_io,compression,crc,profiler,math_utils}.gd
shaders/{voxel_opaque,voxel_cutout,voxel_water,voxel_translucent,sky,clouds}.gdshader
resources/           # ONLY original code-authored metadata/material templates or user-generated cache manifests
local_data/          # gitignored generated local assets; prefer user:// for real runtime assets
scripts_tools/       # optional stdlib-only offline extractors/tests, no copied game data
fixtures/            # small independently derived numeric test expectations, no proprietary files
benchmarks/{worldgen,meshing,streaming,save_load,frame_timing}.gd
scenes/tests/         # headless runnable test scene(s)
docs/{STATUS,DECISIONS,PARITY_MATRIX,BENCHMARKS,USER_GUIDE}.md
.gitignore
```

Only add extra files where they improve actual modularity. Every significant source file: 2–5-line header **what / why / public contract / invariants**, typed exported APIs and brief JSDoc-equivalent GDScript comments (`##`) for complicated logic. Avoid 100-line comments or overengineering. Maintain a registry-to-implementation mapping so expanding block/mob coverage doesn't create scattered giant `match` blocks.

## 3. Boot and local asset import: mandatory user experience

**On the very first launch**: show a polished “Import Java Edition Resources” screen, automatically scan local Minecraft launcher installs, select the highest available *installed release* up to 26.3 (prefer exact 26.3), display detected version/path, and import compatible assets into `user://minecraft_asset_cache/<version>/`. If multiple profiles/locations exist, offer a selection UI; if nothing is found, explain how to install Java Edition via the official Launcher and offer **Browse for Minecraft Folder**, **Retry**, **Use Original Placeholder Mode**, **Exit**. Do not require a developer terminal or manual texture copying. The generated project must run through this screen even on a clean computer.

Scan, without assuming any file exists:

| OS | Initial search roots (augment with launcher profile `gameDir` if present) |
|---|---|
| Windows | `%APPDATA%\\.minecraft`, `%USERPROFILE%\\AppData\\Roaming\\.minecraft`, user-selected folder |
| macOS | `~/Library/Application Support/minecraft` |
| Linux | `~/.minecraft`, XDG-compatible/custom launcher locations |

Read the versions folder and launcher profile metadata where available; allow custom instance folders (Prism/other launchers) via UI. Validate version manifests and selected `.jar` path, rather than assuming a directory name is trustworthy. The standard Java client JAR is typically `.minecraft/versions/<version>/<version>.jar`; it is a ZIP archive. **Textures, blockstates, item models, language/font metadata, shaders, particles, sounds manifest, and other packaged assets** live under `assets/minecraft/...` inside the client JAR. **Many sound/audio payloads are *not* in the JAR**: use `.minecraft/assets/indexes/<asset-index>.json` to map virtual asset paths to SHA-1 object files at `.minecraft/assets/objects/<first-two-hex>/<hash>`. Use matching selected-version asset index; validate expected hashes and existence; do not fetch missing objects covertly.

**Asset import pipeline**:

1. Read JAR central directory safely. Enforce ZIP entry size limits, file type allowlist, safe extraction paths (no `../`, symlinks, or absolute-path escapes), SHA-1/size verification when metadata is available, bounded memory and progress feedback.
2. Build versioned `manifest.json` with source version, original path, source file fingerprints, timestamp, asset registry schema, missing assets, and cache revision. Rebuild only changed assets or when `Reimport Assets` is selected. Handle interrupted imports atomically and idempotently.
3. Import block and item **textures**, animation `.png.mcmeta` timing/frame order/interpolation, `assets/minecraft/blockstates/*.json`, block/item `models/*.json` with recursive parents, UV rectangles, 90° rotations, multi-part and weighted variants, faces, cullface, element rotation, overlays, tint indices, emissive materials where indicated, display transforms. Fail gracefully with visible asset diagnostics if a model is unsupported; do not silently replace it.
4. Import `assets/minecraft/items/` definitions if present; **26.3 item model definitions are not identical to older model layouts**. Implement a versioned resolver; don't assume one static JSON schema for all releases. Support custom resource-pack override resolution later.
5. Read fonts (`font/*.json` and glyph sheets), GUI sprites and layout textures, particles, block-breaking stages, environment textures, mob skins, entity/equipment textures, panorama, sun/moon/cloud textures, sounds metadata, and ALL locally installed gameplay and background music, with complete music playback requirements in Section 20. Respect animation and color/tint behavior; preserve pixel art under native nearest filtering, configurable mipmaps/anisotropy for distance.
6. Import and build optimized **texture arrays when supported**, otherwise padded atlases with explicit per-tile UV lookup and mip-bleed protection. Don't duplicate texture memory by material/per-chunk; support normal animated textures without rebuilding every chunk mesh.
7. **Java entity geometry and animation are mostly implemented in game code, not provided as simple block-model JSON**. Texture extraction is not entity-model extraction. Build **original GDScript mesh/rig definitions** (dimensions and animation structures researched/validated against references); use imported local entity texture sheets. Never assert that Java client `.jar` automatically yields ready-to-render mob meshes.
8. Keep proprietary imported bytes **outside git and exported packages**; use `user://` caches and clear cache/reimport options. Original test-mode procedural checkerboards or neutral materials are permitted only as user-visible fallbacks when a local install is missing—**do not silently substitute handmade textures for available vanilla textures**.
9. At runtime show import progress per category, failures, disk usage, and source attribution. **No account authentication bypass, downloading official Minecraft resources from unofficial mirrors, or game asset redistribution**.

**Acceptance:** With installed 26.3 Java resources, create world and render correct grass/dirt/stone/tree/water/tool/HUD textures on first boot; animated water/lava/fire and representative entity skins are validated; assets missing from the selected install are reported. Without Minecraft installed, clean fallback starts and prompts rather than crashing.

## 4. World coordinate, storage, and infinite-streaming contract

- **One chunk = 16×16 X/Z blocks**; section = **16×16×16 = 4,096 blocks**; Overworld **24 vertical sections**, 384 blocks tall and **98,304 voxels per chunk** before compression. Use int64 world block/chunk coordinates. For negatives: `chunk_x = floor_div(block_x, 16)` and `local_x = floor_mod(block_x, 16)`; same for Z and Y sections. Test -1, -16, -17 boundaries.
- Keep world data in **integer global coordinates** and visual transforms near camera using a **floating origin**: periodically shift scene visual origin at a chunk-aligned threshold (e.g. 512–1,024 blocks), never changing global chunk keys, biome sampling, entity identities, or disk coordinates. Avoid float precision glitches at large world distances.
- Vanilla-like configurable default border: X/Z **±29,999,984** with further physical limits near ±30 million. Provide `unbounded_world = true` for a conceptual unbounded extension; never promise literally infinite memory/storage/coordinate range. Support negative coordinates, non-origin seeds, remote teleports, unloaded-chunk reentry.
- Use palette-compressed block-state IDs per 16³ section, a shared static registry mapping `namespace:block[property=...]` ↔ small integer ID, with `air` fast path. An all-air or single-state section should store little beyond its header. Bit-pack multistate palettes and reserve direct/global palette path when necessary. Optional compact local lights: packed 4-bit sky and blocklight 0..15; lazy allocate on demand. Biome palette per coarse quart grid for interpolation and rendering tint, rather than per-voxel strings.
- Chunk state machine: `ABSENT → QUEUED → GENERATING → DATA_READY → MESH_QUEUED → READY → VISIBLE → SLEEPING → EVICTED`; out-of-order results guarded by generation tokens. Worldgen must not depend on load order. Chunk job includes dimension, seed, generator version, position, priority, cancellation epoch, and neighbor-edge requirements.
- Prioritize chunks around the **player in front of the camera** and essential immediate collision envelope before distant render chunks; reserve request bandwidth for player falling/teleporting; async work must have strict queue/memory/time budgets. Smooth spiral/ring progression, opportunistic frustum priority, predictive prefetch from velocity; cancel outdated tasks instead of generating abandoned routes.
- **Do not create one Node per block.** Sections store raw data and a few per-section mesh/collision handles; one `MeshInstance3D`/RenderingServer instance per compact opaque/cutout/translucent section group where profitable. Entities are separate only when behavior requires them.
- Keep generated pristine terrain as deterministic seed+generator where possible; save **only edits and persistent state** for untouched chunks. Save region-based chunk snapshots if modifications become dense. Include version, seed, dimension, checksums, compression, entity/loot/spawn state, settings and timestamp. Journal writes atomically (write temp, fsync where supported, rename) and periodically checkpoint; corruption recovery, backups, and hot-reload world list. No destructive migration on old saves.
- Configure three independent radii: **render distance** (near/full mesh + far LOD), **simulation distance** (active ticks/spawns), and **collision distance** (near-player shapes). Never keep all 384 Y voxels active as scene objects or allocate every possible chunk.
- Full-world generation uses global voxel coordinates, with a 1–2-block halo for greedy mesh neighbor visibility and lighting; exact chunk-border consistency across generation, mesh edits, fluids, structures, and cave cuts. No arbitrary per-chunk reseeding that produces discontinuities.

## 5. Java 1.18.2 world-generation fidelity: exact specifications

**Absolute rule:** In this project, **1.18.2-compatible** means *same seed + same coordinates + same version = same biome/density/height/feature placements within explicitly declared/validated coverage*. 'Looks similar' is not exact. An independent `26.3` profile may use its own registries and innovations. Do not use Godot `FastNoiseLite` as a drop-in for Mojang seed parity: its algorithm, octave/permutation seeding and coordinate domain differ. It is allowed only for optional fog/cloud/LODs or temporary **visibly labeled approximate** development fallback.

### 5A. Known, fixed 1.18-world invariants

| Parameter | Exact target / contract |
|---|---|
| Reference | **Minecraft Java Edition 1.18.2**, not early 1.18 snapshots, Bedrock, 1.19 or modern defaults |
| Overworld generated Y | **-64 through +319 inclusive**, build ceiling Y=320 exclusive |
| Overworld generation height | **384** blocks, `min_y=-64` |
| Sea level | **Y=63** |
| Chunk column | **16×16** blocks; 24 sections of 16³ |
| Bedrock | bottommost **Y=-64**; randomized transition up to **Y=-60**, with exact block placement controlled by version-specific surface rule and random source |
| Deepslate | version-specific surface gradient in the **Y=0..8** transition, becoming dominant below zero; use actual 1.18.2 rule rather than merely thresholding |
| Base blocks/fluid | stone / water in Overworld except biome/material replacements and lava aquifers |
| Climate samples | temperature T, humidity H, continentalness C, erosion E, weirdness W, depth D; biome assignment is nearest **6D parameter interval** match, not a simplistic threshold per biome |
| Terrain shaping | 3D density field from version-specific **noise router + terrain-shaper splines**; positives generally solid, nonpositives air/fluid after aquifer logic |
| Caves | cheese, spaghetti, noodle and entrances; terrain density plus carving; connected large caverns, aquifers and lava below ground |
| RNG | Java-compatible 64-bit signed world seeds, exact version-appropriate positional RNG/Xoroshiro/legacy random where specified; preserve overflow and sign handling |
| Order | noise → biome/density → aquifer/materials → surface → carved/placed features & structures → lighting; match exact native stage order as researched, and test neighbor dependencies |

**Major source-of-truth caveat:** Java **1.18.2** has a `noise.terrain_shaper` spline-based schema and a `noise_router`, with sampling/top-and-bottom slide parameters. **1.19+ moved these concepts into a different density-function layout; 26.3 also renamed `surface_rule` to `material_rule`.** Implement separate deserializers and evaluation paths. Do not put later `spawn_target`/`material_rule` fields into 1.18.2 data or use 26.3 density configs and call the result 1.18.

**Obtain exact 1.18.2 numeric parameters instead of guessing:**

1. Locate an **official, locally installed 1.18.2 server JAR** if available. The original server data generator supports `--reports` and emits the full vanilla worldgen reference; with Java 17, in a bounded temporary folder, execute (adjust executable path):
   ```text
   java -DbundlerMainClass=net.minecraft.data.Main -jar minecraft_server.1.18.2.jar --reports --output ./vanilla-1182-reports
   ```
   Check whether that specific JAR supports the command and inspect exit status. If only a local **client** JAR exists, check legitimately available version-appropriate reports or instruct the end-user to provide the official JAR manually—**do not pirate or invent a report**. 26.3 modern worldgen JSON is available in the selected client's own `data/minecraft/worldgen/` directory.
2. Parse/retain in the user's **local generated reference cache** every `worldgen/noise_settings`, `noise`, `density_function`, `biome`, `configured_feature`, `placed_feature`, `configured_carver`, `structure`, `structure_set`, `template_pool`, `processor_list`, and structure NBT needed by each version. Normalize schema into typed runtime definitions; avoid copying proprietary files into the shared repository/export.
3. **Treat the authoritative source as executable configuration:** every octave, salt, frequency, scale, interpolation size, sliding target/size/offset, spline knot/derivative, ore height/count/rarity, vegetation spacing, cave-carver setting, temperature modifier, surface rule, structures spacing/separation/salt, and feature order must be read from **exact 1.18.2 output**. Do not fill gaps with arbitrary nice-looking values and mark them exact.
4. **Reference parity:** generate a vanilla 1.18.2 sample world locally if possible and compare matching seeds `(0, 1, -1, 123456789, -987654321)` and chunk coordinates `(0,0), (-1,0), (0,-1), (1,1), (17,-23), (1024,-1024)`. Compare biome grid, heightmaps, block sections, Y-slices, selected ores and structure origins by canonical hashes. Track **terrain surface parity**, **cave density parity**, **biome parity**, and **feature parity** separately. Only mark a subsystem exact if hashes or sampled coordinate comparisons pass. Store numeric expectations, not copied client files.
5. Optional `APPROX_118_LOOK` mode allowed **only as an honest bootstrap fallback** when the 1.18.2 reference is absent. It must be labeled approximate in UI/save metadata and replaced by exact implementation when source data is available.

### 5B. Climate thresholds: guideposts to validate in version-specific parameter list

The following are known general post-1.18 climate intervals; **the authoritative 1.18.2 biome parameter map controls boundaries and exceptions**, not this shorthand table:

```text
T (temperature): [-1,-.45),[-.45,-.15),[-.15,.2),[.2,.55),[.55,1]
H (humidity):    [-1,-.35),[-.35,-.1),[-.1,.1),[.1,.3),[.3,1]
C (continental): mushroom roughly [-1.2,-1.05); deep-ocean [-1.05,-.455);
                 ocean [-.455,-.19); coast [-.19,-.11); near-inland [-.11,.03);
                 mid-inland [.03,.3); far-inland [.3,1]
E (erosion):     [-1,-.78),[-.78,-.375),[-.375,-.2225),[-.2225,.05),
                 [.05,.45),[.45,.55),[.55,1]
PV (peaks/valleys from weirdness W): PV = 1 - abs(3*abs(W) - 2)
PV categories: valley [-1,-.85); low [-.85,-.2); mid [-.2,.2);
               high [.2,.7); peaks [.7,1]
Depth D:        varies vertically; approx +1/128 per block descending,
               but true biome-depth selection comes from the reference sampler.
```

Implement shifted noise for T/H, C/E/W terrain climate noises, accurate 2D/3D coordinates, true nearest-parameter-space interval distance for biome selection, versioned cave-biome sampling, spline-controlled offset/factor/jaggedness, blending and smoothing. Cache coarse climate/density samples with *unchanged outputs*; aggressive memoization cannot alter deterministic bitwise results. Add detailed biome diagnostic overlay T/H/C/E/D/W/PV and exact seed/chunk/XYZ.

### 5C. Landform and cave fidelity

- **Terrain:** oceans, deep oceans, beaches, coastlines, islands, mushroom fields, flat plains, plateaus, rolling forests, deserts, jungles, badlands, swamps, rivers, meadows, groves, dramatic jagged/frozen/stony peaks, snowy slopes and windswept highlands; large smooth transitions, realistic mountain shape, overhangs, giant cliff faces and valley carving.
- **Noise math:** faithfully implement versioned `normal_noise`, improved Perlin/octave sampling, shift functions, clamp, abs, square, cube, squeeze, spline, mul/add/min/max, interpolated and cache-once/2D/in-cell nodes, range choice, slide and blend, with exact sample order and integer RNG. Where version lacks a node, don't substitute newer semantics silently. Use 3D density (not a 2D heightmap plus ad hoc caves).
- **Caves:** all relevant 1.18.2 cheese caves, spaghetti 2D/3D corridors, noodle tunnels, cave entrances, ravines/canyons as applicable, underground lakes, underwater caves, lava aquifers, local water levels/barrier noise, caves that traverse multiple chunks. Carving should be reproducible independent of chunk load direction.
- **Surface and geology:** surface thickness, grass/dirt/stone mixes, underwater gravel/clay/sand, snow layers, powdered snow where applicable, badlands terracotta strata, calcite and dripstone, deepslate transition, cave biome flooring, coarse dirt/podzol/nylium/mycelium where appropriate. Biome-specific sky, water, foliage and grass colors from data.
- **Ores:** coal, iron, copper, gold, redstone, lapis, diamond, emerald, ancient debris (Nether), nether quartz/gold; exact 1.18.2 Y-range triangular/uniform/distribution shapes, vein size, attempts per chunk, exposure attenuation, iron/copper large veins, tuff/granite hosts, emerald mountain distribution. **Extract exact placement JSON and parameters** rather than relying on an approximate memorized ore chart.
- **Structures/feature order:** mineshafts, dungeons, geodes, fossils, ruined portals, villages, desert/jungle temples, witch huts, pillager outposts, woodland mansions, ocean monuments/ruins, shipwrecks, buried treasures, strongholds, igloos, trail and lush/dripstone cave features as present in target version, lava pools, springs, trees/flowers/vegetation, icebergs, coral, huge mushrooms, ruined portals, and cross-chunk placements. Data-driven piece selection, block rotation/mirroring, loot tables and seeds; only mark implemented when visible and functional.
- **Separate version behavior:** A `WORLDGEN_1182` save does not spontaneously gain 26.3-specific terrain/structures in already-generated chunks. If the user wants 26.3 blocks/mobs in the 1.18 landmass, use separate `WORLDGEN_1182_WITH_263_CONTENT` profile, clearly labeled **hybrid / not exact vanilla seed parity**. An independent `WORLDGEN_263` profile implements 26.3 climate/density/biomes/structures.

### 5D. 26.3 Wilderness Bound worldgen/content obligations

Add to **26.3 content registry** and, where correct, 26.3 worldgen: **Dappled Forest** (near cold biomes), poplar trees and fallen poplar trunks, red/orange/yellow poplar leaf variants, poplar full wood set, red shrubs, shelf mushrooms, **abandoned camps** and explorer maps, cushions, straw beds, 16-color wool stair/slab sets, and 16-color concrete stair/slab sets. Respect their actual crafting recipes, block geometry/collision, rotations, drops, spawn lists, sounds, sleeping rules, loot and world placement; see official 26.3 notes. Include preceding features through 26.2 (e.g., sulfur caves/cubes, if present in 26.3 registry), plus modern copper content and newer mounts, without inventing unreleased 26.4-only additions. `WORLDGEN_1182` retains 1.18-style terrain unless hybrid mode explicitly applies these additions.

## 6. Rendering, block models, lighting, and visual fidelity

### 6A. Fast voxel geometry pipeline

Use **one reusable registry of block-state render definitions**, derived from each installed vanilla blockstate/model JSON and a small number of original special renderers. For every 16³ section, assemble **separate opaque, alpha-tested/cutout, transparent, animated-water/lava, and special geometry batches** as needed. No individual block nodes, per-face materials, or per-voxel draw calls. An opaque cube emits a face only if neighbor occlusion rules require it, including across section and chunk boundaries. Hollow caves and interiors are visible; enclosed solid areas are never drawn.

Implement **greedy meshing** for neighboring coplanar faces only when **texture/material/state, face orientation, tint, lighting, ambient occlusion, UV repeat rule, transparency class and animation parameters** are compatible. Don't greedily merge arbitrary different stone/grass faces, or stretch a single 16×16 pixel tile over a 32-block wall. If using a texture atlas, represent tiled per-block UVs in shader/local metadata with padded clamping; test against texture bleeding. Explicit six-face neighbor lookup, zero-cost all-air/all-solid section paths, negative position handling, and correct partial-block occlusion. For stairs, slabs, fences, walls, doors, rails, beds, crops, plants, levers, buttons, redstone dust, waterlogged blocks, signs, copper/transparent variants and multiblock forms, use voxel model JSON elements/connection states or specialized meshed primitives batched per section. Use instancing for repeated complex decorations only when benchmarks show a win.

Render in this order/conceptual set: sky/atmosphere → opaque chunks → cutout foliage → entities → translucent water/glass → particles → first-person hand/item → HUD. Handle depth writes and transparency sorting deliberately. Water must have separate material/underwater fog/refraction-lite effects with **low** and **high** cost choices. Block-breaking damage overlay uses stages 0–9, accurate block selection outline and mining progress. Support swaying grasses/animated leaves only if vanilla-like and not expensive; don't introduce gratuitous non-vanilla PBR style by default.

- **Chunk frustum culling:** per-section bounds, not one giant full-column AABB where many sections are invisible.
- **Occlusion-aware rendering:** optional conservative chunk occlusion/hierarchical visibility when measured beneficial; never incorrectly hide caves through transparent blocks.
- **Mesh LOD:** full voxel geometry for active close chunks; progressively simplified/coarse or heightfield **visual-only** far chunks with properly blended boundaries/skirts and atmospheric fog. Never substitute LOD data for collision, block picks, edits or terrain generation parity. Settings may disable distant LOD for vanilla-faithful silhouettes. Defer distant caves/underground faces behind occlusion.
- **Batch upload:** CPU generation and mesh array construction off main thread where safe; queue **bounded**, ordered, main-thread/RenderingServer commits. Do not concurrently mutate SceneTree or shared Image/Texture resources. Respect Godot documented thread-safety; avoid the known risks of forcing the renderer's Separate thread mode. Never call `wait_for_group_task_completion()` on every render frame in a way that blocks the camera.
- **Materials:** maximize shared material/shader instances. Vertex colors or custom attributes carry light/AO/tint. Deduplicate texture layers and texture atlas space, avoid giant unbounded atlas. Keep cutout pixels crisp and add selectable MIP/texture filtering.
- **Lighting:** voxel skylight (0..15) and emission blocklight (0..15), attenuation and occlusion, skylight recomputation for edits, incremental BFS/bucket queues for neighbors, light crossing chunks, AO and smooth lighting interpolation; support Fast vs Smooth vs Maximum light quality. Prioritize near-player updates; don't remesh an entire vertical column after one torch placement. Sun/moon movement influences sky color and *visible* overall illumination while block skylight propagation stays valid.
- **Clouds/sky:** vanilla-like rotating sun/moon, stars, horizon, per-biome fog/water tint, sunrise/sunset gradients, rain/snow/thunder effects, sky/cloud height behavior as performance allows. Cull weather particle volumes and don't spawn particle nodes per raindrop.
- **Models:** parse vanilla JSON accurately, but identify custom renderers such as chests, banners, shulker boxes, signs, beds, pistons, conduits, item frames, and entity-rendered block entities. Source JSON does not supply every Java hard-coded behavior; implement original code and test representative shapes.

### 6B. Technical renderer test matrix

Create automated/visual test scene with a line of every key shape: normal cube; grass cube with top/side/bottom and tint; logs all axes; cutout leaves; glass panes with connecting glass; stairs and slab orientation; flowing water/lava; trapdoor/door open/closed; fences/walls/gates; torch/light; two neighboring different blocks; flowers/crops; redstone dust; a mine shaft with complex light; a water-filled cave; snow/ice; a row of animated tiles. Verify **UV repeat on greedy faces**, no alpha halos or atlas bleed, correct culling at chunk boundaries, no z-fighting, shadows consistent with options, and stable frame timing during chunk updates.

## 7. Player motion, input, combat, survival and interaction

Implement a responsive first-person controller with Java-compatible AABB and voxel collision, not a generic slippery FPS capsule: standing hitbox **0.6 wide × 1.8 high**, crouching **0.6 × 1.5**, swimming/gliding **0.6 × 0.6** where implemented. Normal eye height about **1.62**. Collision vs stairs, slabs, fences, leaves, fluids, ladders, vines, powder snow, doors and trapdoors must correspond to their shape registry. Add step-up (including slabs), gravity, landing, edge sneak, friction per block (ice/slime/honey/soul sand), swimming/buoyancy, sprint-jump momentum, fall damage, head collision, ladders, crawling, elytra later. Preserve camera motion and target selection through floating-origin rebases.

**Movement sanity benchmarks** on flat normal terrain: walking about **4.317 blocks/s**, sprinting about **5.612 blocks/s**, sneaking about **1.295 blocks/s**; match vanilla acceleration/friction and cross-check rather than setting only a constant target speed. Support toggle/hold sneak and sprint, double-tap sprint if appropriate, configurable key bindings, sensitivity, invert Y, raw-ish capture with escape to release, and scroll/number hotbar selection. Physics and game logic must not vary with FPS.

**Interaction:** voxel DDA raycast, hit face normal, block outlines, targeted entity selection, reach **4.5 blocks survival / 5 creative** for block interactions by default (entity attack reach handled separately). Left-click break with correct hardness/tool tags, tier and enchantment rules; right-click place/use/interact; offhand precedence; shift-use; continuous mining, progressive break animation; normal block placement orientation and face-adjacent placement; 3rd-person and hand bob options. Validate pickup collision, dropped item entity stack merge, death drops, and inventory capacity.

**Health/survival:** health, absorption, food/exhaustion/saturation, regeneration, starvation by difficulty, underwater oxygen/drowning, armor/toughness, durability, environmental damage (fire/lava/fall/suffocation/freezing/lightning), status effects, poison, fall damage, knockback, critical hits, shield, ranged combat, cooldowns, XP and respawn. Game modes: full Survival, Creative, Adventure, Spectator and Hardcore world rules (see expanded Section 19). Difficulty Peaceful/Easy/Normal/Hard updates spawning/damage. Beds set spawn and advance time, with Nether/End behavior in proper profile. Weather and day/night influence hostile spawns and burn in daylight where appropriate.

**Interaction systems:** crafting recipes, crafting table, furnace/smoker/blast furnace/brewing stand, crafting book, stonecutter, anvil, grindstone, enchantment table, loom, smithing table, cartography, composter, chests/barrels/shulkers/hoppers, item frames, painting, banners, signs, books, maps, fishing, shields/bows/crossbows/tridents/spears/maces where version demands. Prefer generic block-entity state and `Container` API with per-entity adapters. Implement actual recipes/loot from versioned reference data; a texture/registry entry alone is *not* feature completion.

**Blocks and updates:** stateful blocks with neighbor events, scheduled and random ticks, falling gravity blocks, crop/tree growth, bone meal, waterlogging, freezing/melting, fire spread, explosions/TNT, fluid level/flow and interactions, copper oxidation/waxing, sculk and sensors, nether portals, piston moves, boats/minecarts. Prioritize fast incremental dirty queues, no full-world scans. Limit per-tick work safely while preserving determinism in active areas.

### 7A. Redstone and automation coverage

Build a discrete 20 TPS block-update scheduler, separate from rendering. Data-driven power propagation with scheduled delay queues, neighbor notifications and directional states. Include dust, repeaters, comparators, torches, levers, buttons, plates, observers, daylight sensors, target blocks, rails/detectors/activators, pistons/sticky pistons, hoppers, droppers, dispensers, note blocks, tripwire, sculk sensors, copper bulbs, lamps and the crafter. **Java-specific quasi-connectivity and update-order behavior** require explicit version tests before claiming parity. Detect oscillation/performance abuse and impose bounded processing with clear diagnostics rather than freezing. All circuits persist when chunks sleep/save/reload; avoid stepping unloaded chunks unsafely.

## 8. World ecosystem, item/block registry, dimensions, biomes and structures

At first boot, enumerate **installed 26.3 registries** for blockstates, model references, item models and available data-driven recipes/loot/tags/worldgen; create a compact manifest of supported/unsupported behaviors. The goal is to load **all available texture/ID assets automatically**; implementation of behavior is separate and has explicit status. Do not claim a `block` works because its art loads. Maintain **stable string IDs on disk** and compact numeric IDs in RAM; unknown IDs must round-trip safely through save/load.

**Block categories / mechanics to support:** stone variants, soil and ores; logs/planks/leaves/wood sets (including poplar); wool/concrete 16 colors and 26.3 stairs/slabs; glass/panes and tinted materials; storage and machines; farms/crops; flowers/plants/vines; multi-part doors/beds/tall plants; rails; redstone; water/lava/powder snow/ice; TNT/fire/explosives; decorative blocks/shelves/cushions; dripstone/sculk/copper weathering, waterlogged states; orientations of stairs/slabs/fences/walls/trapdoors; full survival tools/weapons/armor/food and utility items. Machine GUIs work, not just display.

**Biomes:** Build data-driven biome registry from exact selected-version entries with terrain, vegetation, weather, colors, ambient sound, foliage, creatures, cave features, surface composition and structures. Include all applicable plains/forest/birch/dark forest/flower forest, jungle/bamboo jungle, taiga/old growth, snowy tundra/grove, rivers/frozen rivers, swamps/mangrove, desert, savanna, badlands, stony shores, mountains/meadows/slopes/peaks, warm/cold/frozen oceans and deep oceans, mushroom fields, lush/dripstone/deep dark caves, cherry grove, pale garden, sulfur caves if present, **Dappled Forest** and all other 26.3 installed biomes. **Do not include unreleased snapshot biomes in a 26.3 world** unless under a separate experimental switch.

**Structures & exploration:** village variants and jobs, outposts, ancient cities, trial chambers and ominous vaults, woodland mansions, strongholds, ruined portals, bastions, nether fortresses, end cities/ships, monuments, temples, witch huts, shipwrecks, underwater ruins, buried treasure, desert wells, geodes, trail ruins, jungle pyramids, igloos, mineshafts, dungeons, fossils, ruined camps and **26.3 abandoned camps**. Use versioned structure-set salt, spacing, separation and placement JSON where available; implement Jigsaw/template pool assembly with rotated structure templates, markers, palette replacements, and loot/container entities. Structure placements crossing chunk edges must be deterministic and order-independent. Mark unsupported NBT/template behavior honestly.

**Dimensions:** Overworld (mandatory), Nether (different climate/material, lava sea, Nether caves and biomes; portals with 8:1 horizontal coordinate relation, scaled safely), End (central island/outer islands/gateways, strongholds/end portals, End cities and the Ender Dragon encounter). Dimension-specific sky/weather, fluids, mob lists, build limits, seed mixing, saving, respawn and travel. Worldgen exactness per dimension requires separate vanilla reference comparison; do not reuse Overworld noise for everything.

**Game progression:** mining → wood/tools → food/shelter → iron/diamond → enchanting/potions/trading → Nether → blaze rods/ender pearls → stronghold/End → dragon/elytra; implement achievements/advancements and recipes in approximately vanilla progression order. Add commands `/gamemode`, `/time`, `/weather`, `/tp`, `/give`, `/fill`, `/setblock`, `/locate`, `/seed`, `/difficulty`, `/gamerule` when core supports them, plus debug diagnostics. Local single-player command parser has permission distinction and never executes OS commands.

## 9. COMPLETE MOB TARGET LIST — Java Edition 26.3 (not 26.4 snapshots)

The following is the **explicit 26.3 mob scope** (categorized approximately as in the Minecraft Wiki; some mobs are neutral only under certain conditions). Generate `docs/MOB_PARITY.md` **from this list**, include Java registry IDs and observed installed local textures, and give each mob a status **absent / visible / functional / vanilla-validated**. **All these are targets, not a declaration that the resulting game already implements them.** Include boss and summon-only exceptions. If registry or version proves a list discrepancy, honor the **26.3 installed data**, explain correction, and do not import future 26.4-only mobs from a live wiki page.

### Passive/non-aggressive or utility mobs

**Allay, Armadillo, Axolotl, Bat, Camel, Camel Husk, Cat, Chicken, Cod, Copper Golem, Cow, Donkey, Frog, Glow Squid, Happy Ghast, Horse, Mooshroom, Mule, Ocelot, Parrot, Pig, Rabbit, Salmon, Sheep, Skeleton Horse, Sniffer, Snow Golem, Squid, Strider, Sulfur Cube, Tadpole, Tropical Fish, Turtle, Villager, Wandering Trader, Zombie Horse.**

### Neutral/conditionally hostile mobs

**Bee, Cave Spider, Dolphin, Drowned, Enderman, Fox, Goat, Iron Golem, Llama, Nautilus, Panda, Piglin, Polar Bear, Pufferfish, Spider, Trader Llama, Wolf, Zombie Nautilus, Zombified Piglin.**

### Hostile regular mobs

**Blaze, Bogged, Breeze, Creaking, Creeper, Elder Guardian, Endermite, Evoker, Ghast, Guardian, Hoglin, Husk, Magma Cube, Parched, Phantom, Piglin Brute, Pillager, Ravager, Shulker, Silverfish, Skeleton, Slime, Stray, Vex, Vindicator, Warden, Witch, Wither Skeleton, Zoglin, Zombie, Zombie Villager.**

### Bosses and other exceptions

**Ender Dragon, Wither.** Cover **Giant** and **Illusioner** as Java summon-only/unused special cases if still present in the 26.3 entity registry. Do not confuse any nonliving entity type (projectiles, boats, minecarts, item frames, armor stands, TNT, area-effect clouds, displays) with a standard mob; still implement those as gameplay entities when needed. Exclude **Blub/Frostbite** or other announced/future mobs unless confirmed in the actual 26.3 stable registry. Support **adult/baby forms, breed/variant states, biome coloration, equipment, ridden mobs and special texture variants** where the respective mob supports them.

### 9A. Mob implementation contract

**For every mob ID:** implement a GDScript data record with spawn rules, dimension/biome restrictions, group size/weight/cap, hitbox (including baby state), render rig, UV/texture, idle/walk/attack/hurt/death animations, sound events, AI goal stack/state machine, senses, health/armor/attack/speed, targeting/avoidance rules, loot/XP, and persistence. Special behaviors must be real. Examples:

| Class / mob | Required distinctive behavior, beyond walking texture |
|---|---|
| Cow, pig, sheep, chicken | wander, eat/graze where applicable, breed, follow food, drops; sheep wool and regrowth; chickens eggs |
| Horse, donkey, mule, camel, camel husk | ride, tame/bond where appropriate, mount controls, inventory/armor, jump/dash, dismount, special rider/variant behavior |
| Cat, wolf, fox, ocelot, parrot | tame/avoid/follow/sit/panic, breeding, prey and attack; variants and player interactions |
| Bee, frog, axolotl, turtle, sniffer, armadillo | pollinate/hives, frog eating/jump, aquatic air, egg nesting/hatching, sniff/dig, roll/scute, correct specialty drops |
| Fish, dolphin, squid, glow squid, nautilus | fluid-only path/oxygen, schools/animations, aquatic movement, variant interactions and drops |
| Villager, trader, iron/copper golem | village AI, schedule, jobs/trade/restock, profession/biome variants, golem utility/guard/block sorting as applicable |
| Zombie, husk, drowned, parched, skeleton/stray/bogged | day/light behavior, target pursuit, weapon/projectile variants, conversion, drops, water/biome adaptation |
| Creeper | pursue → audible fuse → blast and terrain damage; lightning charged variant, cat avoidance |
| Spider/cave spider | light-dependent hostility, climb walls, web/poison behavior |
| Enderman | gaze/aggro, teleport, block carry/place, water avoidance |
| Slime/magma cube/sulfur cube | size-dependent split/bounce, distinctive material/absorbed-block behavior, versioned special states |
| Piglin, brute, zombified piglin, hoglin, zoglin | barter/gold armor rules, anger, group behavior, combat, zombification/environment rules |
| Ghast, happy ghast, blaze, shulker | flight/hover, ranged attacks and projectiles, shell/teleport, ridable/friendly ghast behavior where correct |
| Witch, evoker, vex, vindicator, pillager, ravager | potion casting, summons/fangs, weapons, raids, group targeting |
| Warden, creaking, breeze | vibration/scent/darkness and sonic boom, gaze/creaking-heart mechanics, wind charge/jumps/trial behavior |
| Ender Dragon, Wither | multi-phase boss logic, boss health bar, block destruction where appropriate, abilities, loot/portals, win condition |

Use **goal-based, interruptible AI** with sensing/pathfinding priority; separation/flocking where relevant; sleeping or deterministic low-frequency tick when remote; no A* rebuild every frame. **Near-field navigation** voxel grid with obstacles, jump heights, door decisions and line-of-sight. Fluids/flying entities get separate cost maps. Recalculate only for changed regions; cache paths and limit work per tick. Spawn via eligible biome/dimension/light/time/block/fluid conditions and vanilla-like caps; 26.3 natural spawning can be data-driven through its **Environment Attribute** `minecraft:gameplay/natural_mob_spawns` and related settings. Do not assume the old biome `spawners` JSON schema is unmodified in 26.3.

**Progression order:** chicken/cow/sheep/pig → zombie/skeleton/creeper/spider → horse/wolf/villager → aquatic/flier/Nether → special abilities/raids → Warden/bosses → all remaining mobs. The game should never contain a flat static statue and declare that mob functional. If only a few can be fully built in current context, implement those correctly, record the rest as absent, and continue automatically when resources permit.

## 10. Desktop UI, HUD, input, graphics and accessibility menus

Aim to **closely reproduce the feel and workflow** of the Java 26.3 menu system using the user's privately imported vanilla GUI/font/icon textures: pixel-scale text/UI, hover/disabled/focus states, nine-slice controls, subtle button sounds, correct icons and spacing, texture-backed panorama where available. Avoid official logos/trademarks in distributed build; use an original product name/branding. Preserve screen readability at 720p, 1080p, 1440p and 4K. Avoid fragile fixed-pixel layouts; adapt with `Control` containers and UI scaling; **do not use screenshot as entire interface**—buttons must really work.

**Screens (required):** initial import/verification and progress; title screen (Singleplayer, functional Multiplayer/LAN end-state, Options, Quit); world list/Create World (name, seed, normal/creative, difficulty, worldgen 1.18.2 / 26.3 / hybrid, structures, cheats, bonuses); loading screen and generated world preview when feasible; in-game HUD (crosshair, 9-slot hotbar, selection, hunger, hearts, armor, air, XP, bossbar, effects, chat); inventory/crafting/recipe book; pause (Resume, Advancements, Stats, Options, Save & Quit); Options root with Video, Controls, Accessibility, Language, Sound; world settings/game rules; diagnostics/F3 overlay; death/respawn. Map, villager trading, machine GUIs, containers and creative search should be integrated rather than stand-alone fake demos.

**Video Settings: everything must actually control quality or resource load.** Include with exact persisted type/range and sane preset defaults:

| Setting | Values/default | Implementation action |
|---|---|---|
| Preset | Low / Fast / Balanced (default) / Fancy / Ultra / Custom | Map to concrete settings without resetting manually set `Custom` |
| Display mode | Windowed / Borderless / Exclusive fullscreen where platform supports | Godot window mode + monitor selector |
| Resolution | Desktop list + auto; default 1280×720 windowed | Resize backing window, UI still usable |
| Frame rate cap | 30 / 60 / 90 / 120 / 144 / 240 / Unlimited (default 120) | Engine frame pacing; avoid busy loop |
| VSync | Off / On / Adaptive if supported | Real `DisplayServer` control, not fake menu |
| Render distance | 2–32 chunks, default 12 | Near terrain chunks/mesh radius and associated memory budget |
| Simulation distance | 2–16 chunks, default 6 | Mob/redstone/random-tick active radius |
| LOD distance / far terrain | Off, 16–64 chunks (default auto, subject to hardware) | Visual-only, with fade/fog; must not affect saves/edits |
| Dynamic resolution | Off/On (default off); render scale 50–100% | Adjust 3D pixel fill while native-resolution GUI remains crisp |
| FOV | 30–110°, default 70° | Camera projection; apply immediately |
| Graphics | Fast / Fancy / Fabulous-ish if implementable | Transparency/cloud/lighting feature suite, not just relabel |
| Smooth lighting / AO | Off / Low / High (default High) | Light interpolation/AO shader/data |
| Shadow quality | Off / Low / Medium / High | Real shadow resolution/cascades and lights |
| Cloud quality | Off / Fast / Fancy; default Fast | Real clouds and distance behavior |
| Particles | Minimal / Decreased / All | Pool sizes/spawn rate |
| Entity distance | 50–500%, default 100 | Entity render/AI visual culling, not despawn state |
| Biome blend | 0–7 blocks, default 3 | Color blending radius |
| Texture filtering | Nearest / Bilinear / Trilinear; default nearest | Accurate atlas/array sampler choice |
| Anisotropic filtering | Off / 2× / 4× / 8× / 16×, default 4× | Real texture sampler at distance |
| Antialiasing | Off / FXAA / TAA or other supported implementation / MSAA choices | Show only backend-supported options; avoid mutually incompatible fake toggles |
| Mipmaps | Off / On (default On) | Import/texture rebuild if necessary; near-texel art remains crisp |
| Fog | Off / Vanilla / Enhanced | Sky/terrain/water fog settings |
| View bobbing | Off/On, default On | First-person camera transform only |
| Vignette / distortion | Off/On; configurable | Actual fullscreen effect |
| Weather visuals | Off / Reduced / Full | Render settings only, simulation/weather unaffected |
| Chunk upload budget | Auto / Low / Normal / High | Per-frame mesh upload and rebuild budgets |
| Background FPS | 15 / 30 / 60 | Lower frame rate when unfocused, if supported |
| GUI scale | Auto / 1× / 2× / 3× / 4× | Responsiveness and pixel scaling |
| Debug metrics | Off/On | FPS, frame time, TPS, draw calls, chunks, queues, RAM/VRAM estimates |

Persist per-user to `user://settings.cfg` with validation, backward-compatible schema migrations, Reset/Apply/Cancel, accessibility contrast, text shadows and correct keyboard navigation. Use supported Godot 4.7.2 APIs; if Vulkan/MSAA/TAA or fullscreen mode is unsupported on a platform, disable it with truthful tooltip rather than no-op.

**Controls:** Minecraft-style bindings (WASD, space jump, Shift sneak, Ctrl sprint by default, E inventory, F offhand, Q drop, 1–9 hotbar, F3 debug, F5 camera if supported, Esc pause, mouse L/R break/place, wheel select, double-tap W optionally sprint). Rebind UI with conflict detection, hold/toggle options, sensitivity, invert Y, subtitles. Don't globally trap inputs when menus/dialogs are open. Support controller later with remappable actions, but mouse/keyboard gets priority.

## 11. Sound and music architecture

Use the local version's `sounds.json` sound-event lookup plus hashed object files. Decode supported OGG files at first-use or cache, stream long music where appropriate. Sound buses: Master, Music, Weather, Blocks, Hostile, Neutral, Players, Ambient, UI, Voice, Jukebox. Spatialize footsteps by block, digging, placing, tool hits, fire/water/lava, ambient cave/biome/weather, mobs, UI transitions, potion effects, music discs, menu music. Pool AudioStreamPlayer nodes to avoid per-step allocation, cap simultaneous emitters, apply distance attenuation, randomize source variants as metadata requires, and implement pause/audio settings/subtitles. Imported audio stays local to user's machine; no shipping audio data or unlicensed fallback tracks.

## 12. MAXIMUM PRACTICAL OPTIMIZATION — REQUIRED, NOT OPTIONAL

The instruction “all physically possible optimizations” is not mathematically finite. Implement **every applicable optimization below that produces a measured net benefit**, not every mutually incompatible trick at once. Profile first and after; retain the fastest **correct** implementation for real target hardware. Never sacrifice worldgen seed determinism, collision, asset fidelity, texture consistency, or save reliability to improve one synthetic benchmark. A 200 FPS empty world is irrelevant if rendering drops to 15 FPS while exploring.

### 12A. CPU/worldgen

1. Use typed GDScript variables, packed arrays and value-type math in hot paths; avoid per-block `Dictionary`/`Variant`/`String` allocations and per-voxel `Object` instances.
2. Compile canonical block states into small integer runtime IDs; use compact bitfields for properties/opaque/collision/light/material flags. Precompute state neighbor-occlusion masks and render templates.
3. Generate terrain only for requested chunks/sections; skip or compress all-air and all-solid sections; use vertical height estimates / conservative density bounds to avoid expensive samples that can't affect outcome, **without changing outputs**.
4. Memoize expensive climate and 3D noise subexpressions at the same sampling-grid resolution as the reference; implement exact interpolation with cache-friendly iteration order. Reuse columns/biome values across vertical sections.
5. Use **seeded region-/coordinate-based random streams** so task scheduling order cannot change tree placements or structure origins. Keep seed parity tests at each refactor.
6. Support prioritized async workers (`WorkerThreadPool` or carefully managed background `Thread`s), bounded number of inflight jobs, lightweight cancellation, immutable input snapshots, and marshaled main-thread commits.
7. Avoid launching a worker for microscopic jobs; batch neighboring sections or features when CPU overhead dominates, benchmark different job sizes.
8. Keep permanent biome/heightmap caches only within memory budgets; use cheap LRU/clock eviction; reuse transient buffers via pools to avoid allocator spikes.
9. Avoid recomputing terrain, biome, collision or noise on every render frame; ensure stable scroll/zoom and player movement do not trigger unrelated recomputation.
10. Use section-level dirty flags and queues: `geometry_dirty`, `light_dirty`, `collision_dirty`, `simulation_dirty`, `save_dirty`; coalesce edits per tick/frame and only rebuild affected neighbor sections.
11. Biome and feature samplers must be pure in global coordinates, enabling deterministic multi-threading and reproducible replay; no mutable shared worldgen RNG.
12. For 26.3 data-driven density expressions, compile the JSON tree once into a compact typed op stream/DAG with constant folding and shared subexpression IDs when safe; do not recursively traverse dictionaries for every voxel.

### 12B. GPU geometry and scene cost

13. **Culled faces** are default; **greedy meshing** for compatible faces, sparse mesh for non-cubes, opaque/cutout/translucent separation.
14. Use one shared texture atlas/array per material family and a small fixed count of shaders/materials, avoiding state changes between chunks; never bind a different texture for every block.
15. Mesh only visible section surfaces. Avoid generating entire 16×384×16 column meshes for one grass edit; handle local edge neighbors correctly.
16. Aggressively frustum-cull chunks/sections. Optionally cache conservative occlusion (benchmark benefit; avoid invisible holes) and keep water visibility rules separate.
17. Use transparent geometry sparingly; batch/sort water/alpha objects by chunk or transparent region. Opaque geometry first. Don't enable costly transparency features everywhere.
18. Apply configurable far-LOD/fog, but use a deterministic full-detail representation near player and no missing physics; prioritize near chunks on camera rotation and teleport.
19. Reuse GPU buffers/`ArrayMesh` surface allocations and mesh instances where supported; bounded mesh uploads per frame to avoid GPU stalls. All array write/texture upload ownership must respect Godot's thread-safety rules.
20. Shader work: vertex light/AO/color tint; minimize expensive branch/per-fragment noise and full-screen passes; platform-appropriate alternatives for shadows, SSR/refraction, fog, DOF, SSAO/SSIL as available. Don't turn on every effect under “Ultra” if it hurts performance disproportionately.
21. Avoid deep SceneTree hierarchies, per-face nodes, hundreds of unique materials, duplicated resources, redundant lights, and excessive per-object signals; use registries and centralized scheduling.
22. Prefer lightweight GPU/CPU-side pooled particles, batched rain/snow, distance-cull particles and entities; avoid spawning thousands of short-lived nodes.
23. Avoid texture-array assumptions that fail on Godot compatibility/mobile backend; implement robust padded-atlas fallback. Check max texture dimension and VRAM; avoid huge wasteful power-of-two atlases.
24. Expose chunk mesh triangle/vertex count, draw calls, texture memory and render time in F3 overlay, allowing before/after comparisons.

### 12C. Memory, I/O, world persistence

25. Palette-pack 4,096 block states per section with bit-packing; use all-air and single-value fast paths; compare compression speed vs runtime decode costs. `PackedByteArray`/`PackedInt32Array`/`PackedInt64Array` where appropriate.
26. Avoid permanent duplication of decoded data and compressed data. Keep raw section arrays only while edited/meshing; cache packed forms and usage counts. Use shared immutable block/material tables.
27. Keep per-chunk save data sparse (seed + only deltas for pristine terrain); persist snapshots only when size/decoding threshold favors them. Include integrity checks, versioning and transactional save.
28. Build background disk I/O queues and coalesce writes. Never perform 500 file open/write calls on the render thread while traversing chunks.
29. Cache generated mesh/heightmap *optionally*, keyed by seed, worldgen version, content version, texture atlas revision and relevant world-edits hash; invalidate deterministically. Do not cache stale meshes after a block edit.
30. Apply LRU eviction for far terrain, meshes, cached audio, worldgen output and textures; memory cap is part of settings. Do not evict unsaved dirty chunks.
31. Use compact binary region indexing, seekable chunk blobs and partial reads, checksums/CRCs and corruption recovery; avoid monstrous per-chunk JSON saves and duplicate texture copies.
32. Avoid unbounded queues during flight/teleport and main menu transitions; cancel old work and release disposed resources only when no worker references them.

### 12D. Physics, AI, simulation

33. Fixed **20 TPS** for game logic independent of variable FPS; interpolate remote entities/first person presentation. Keep physics substep where Godot demands it, but do not run full AI at 60/120 Hz.
34. Collision broadphase: query only nearby solid block AABBs and collision shapes, not per-voxel rigidbodies or world-sized static triangle collision. Merge adjacent full-cube collision where advantageous; precise near-player block geometry for stairs/slabs/fences.
35. Entity spatial hash/grid, distance/visibility culling, local nearest targets, sleeping/staggered AI schedules and hard caps on pathfinding jobs. Reactivate with consistent elapsed-game behavior; never despawn important persistent named/tamed mobs incorrectly.
36. Cache dynamic pathfinding regions and incrementally invalidate around block edits; use hierarchical chunk/section routes for long paths and fine voxel search only when near.
37. Schedule block updates, fluids, redstone, random ticks and light via bounded event queues; no full active-world scans for every block type.
38. Pool dropped items, projectiles, hit particles and sound emitters; batch transforms/draws. Keep pickup and item-merge semantics correct.
39. Prioritize active player space over background mob wandering; degrade far-AI fidelity, far render detail and cosmetic particles under load before dropping core collision/near gameplay or TPS.
40. Strict pause/unfocus behavior: save work, sleep threads safely, lower background FPS, and don't keep generating chunks in a paused menu without need.

### 12E. Adaptive quality and rigorous optimization decisions

41. In **Auto Performance** mode adjust far LOD, shadow distance, particle budget and temporary render scale by a smoothed 95th-percentile frame-time signal; **never silently reduce simulation distance, worldgen accuracy or save integrity**. Tell the user which quality knobs are auto-managed.
42. Separate **CPU frame time, GPU frame time, worst spikes, chunk generation latency, mesh latency, mesh upload latency, garbage/allocation spikes, TPS**; benchmark each independently.
43. Avoid unstable experimental Godot engine settings without A/B tests; specifically obey documented thread-safe API rules, and don't enable renderer Separate-thread mode just because it sounds faster.
44. A change must pass unit/integration tests and achieve a measurable benefit in a representative scenario before calling it an optimization. Revert regressions—even if the code looks clever.
45. Preserve readability: micro-optimized unmaintainable code often creates hidden correctness/performance bugs. Typed tight loops + clean data boundaries + profiled caches beat repeated premature rewrites.

### 12F. Performance budgets (engineering targets, not guarantees)

| Scenario | Desired metric | Measurement requirement |
|---|---|---|
| Menu and cached-world load | usable almost immediately; clear progress during heavy import | time-to-menu and time-to-first-interactive-frame |
| 1080p gameplay, 12-chunk render / 6 sim | **60 FPS target** on a documented midrange PC; degrade gracefully | median FPS, p95/p99 frame time, GPU/CPU split |
| Camera spin while standing | no missing close terrain, no more than occasional short spikes | p99 frame time and draw calls |
| Run/sprint 1,000 blocks through new chunks | near-player collision ready, chunk streaming bounded, never freezes | queue depth, unloaded collision wait, CPU time, RAM |
| Dig 100 contiguous blocks and place 100 | no widespread full-column remesh; immediate visible edits | per-edit latency, total dirty mesh rebuilds |
| Fast teleport + turn 180 degrees | pending jobs canceled/prioritized; no crash | time to near collision and first stable view |
| Distant travel then save/reload | edit, entities and player position persist correctly | checksum and replay/canonical equality |
| Main menu after hours of travel | no runaway memory/worker threads | before/after RSS and live resource counts |
| Logic | **20 TPS** maintained under normal mob/redstone load | actual tick duration and max backlog |

Do not hard-code one low-spec computer's measurements as universal. Publish actual tested hardware, Godot version/renderer, graphics preset, scene, sample size, and CSV output in `docs/BENCHMARKS.md`. If target fails, identify bottleneck and optimize it before piling on more features. Offer Low/Fast preset that visibly improves performance on integrated graphics.

## 13. Automated test requirements and executable acceptance gates

Create a **test runner callable headlessly** without user input; if Godot executable is installed, use the exact version and commands that version supports. Typical syntax to validate, not blindly assume: `godot --headless --path . --editor --quit` for project/editor parse/import, and `godot --headless --path . --quit-after 300` for a bounded game smoke run. Use the correct executable name/platform, capture stderr and exit code. Ensure successful test has no new parser errors/warnings, invalid freed instances, missing classes/UIDs, or critical resource failures. A failure must be fixed or explicitly reported.

**Required runnable tests** (write tests as code, not a checklist without implementations):

| Group | Cases and pass criteria |
|---|---|
| Coordinate math | negative and positive floor-div/floor-mod, float origin rebase, block→chunk→block round trip, Y section bounds |
| Seed/RNG | same seed and coords across multiple runs/threads, different seeds visibly differ, Java overflow/golden vectors for compatible RNG |
| Worldgen | chunks order-independent, no seam at x/z +/-16, equal climate and density on shared border, y min/max, sea 63, deterministic cave cross-chunk |
| 1.18.2 parity | reference sampled columns and biomes hashed on seeds listed in §5; report exact mismatch counts per subsystem; no “verified” without fixture |
| Data compatibility | versioned 1.18.2 `surface_rule` versus 26.3 `material_rule`; missing data gives error/fallback without crash |
| Save | create → edit → save → quit → reload, identical edits/entities/inventory/seed; interrupted write recovery; unknown block-ID roundtrip |
| Assets | discovery defaults/custom path, missing JAR/index/sounds, ZIP traversal protections, import re-run unchanged, corrupt asset, `.mcmeta` animation |
| Mesh | hidden face counts, greedy merge rules, opaque/transparent edges, UV repeat, no chunk boundary holes, edit invalidation |
| Light | torch falloff, skylight vertical shafts, light crossing chunk edge, removing source restores shadows |
| Physics | collide with cubes/slabs/stairs, stand and sneak, step-up, no falling through new chunk, correct near-water behavior |
| Inventory | stack max, pickup/drop, crafting consumes ingredients, split/merge, save/load, durability, equipment |
| Blocks | place in six directions, door state, falling sand, liquids flow, simple clock/redstone circuit, crop random tick |
| Mob | spawn/despawn by rule, pathfind obstacles, chase and damage, passive flee/breed, loot drop and persist, no offscreen runaway simulation |
| UI | title buttons, create world, video options persist/apply, keybinding, pause/save/quit, HUD scales 720p/1080p/4K |
| Stress | 64 chunks churn, 100 edits, sprint over hills, 50 entities, teleport, 30-min seeded simulation, active chunk memory bounded |

**Automated integration probes:** `worldgen_probe(seed,x,z,y)` serializes biome/density/block, `render_probe(scene,settings)` logs frame stats and optionally captures screenshot, `save_probe` writes/reopens, `asset_probe` validates local import. Put deterministic inputs/expected results in original small fixtures; do not distribute original vanilla world files. Keep snapshots/render captures in temporary or ignored folders.

**Manual acceptance tour before calling P0 done:** boot on clean runtime → import installed local resources → main menu → new world → spawn on safe surface → daylight forest/hills/mountain/cave/water → move/sprint/jump/swim → break tree and stone → place blocks → open inventory → craft basic item → encounter 1 working mob → open video settings and change render distance/graphics → save quit → reload edits → walk into newly generated chunks. Fix any broken step before moving on.

## 14. Autonomous implementation stages — EXECUTE in this order

### Stage 0 — environment and minimum runnable game

Determine whether an existing compatible Godot project exists. If yes, preserve it and extend it; if empty, create new. Confirm Godot version or identify trustworthy install path. Write `project.godot`, main scene, boot process, valid InputMap, logger, class registration, original placeholder materials, and a visible title menu. **Run a real headless import/boot test immediately**. If Godot is not installed and cannot be installed safely in scope, still produce a valid project and source code, record `UNVERIFIED: Godot runtime unavailable`, and continue code-level deterministic tests; do not hallucinate a successful run.

### Stage 1 — local asset importer and block/model registry

Implement first-run detector, JAR reader, versioned texture/sound extraction, import progress and local cache. Build tiny test scene with block textures, item icon, GUI font. Add version/missing/corrupt tests. Keep no proprietary file in Git/export. Support 26.3 primarily; layer 1.18.2 resource lookup separately when present. **Gate:** physical installed assets render or the missing-install prompt/fallback runs correctly.

### Stage 2 — fast chunks, 3D terrain, rendering and persistence

Implement sections, palette storage, world coords, seed generation, near collision, streaming scheduler, mesh pipelines, fog/sky/water, persistent saves, and debug metrics. Use an **explicitly marked approximate density backend temporarily** if it gets a playable first build faster; do not conflate with 1.18 parity. Add caves and biomes, render near terrain, place/break blocks, save/reload, and neighbor seam tests. **Gate:** user can actually explore indefinitely in practical memory and revisit edited places.

### Stage 3 — exact 1.18.2 and modern 26.3 worldgen backends

Implement versioned RNG/noise/density/climate/spline/feature/evaluation using §5, the authoritative local data generators and canonical fixtures. Add independent 26.3 generator reading its installed data. Avoid dumping full reports into context; read targeted portions and build compact parser/registry, then test. Complete surface/caves/aquifers/ores/structures stepwise and report measured parity by subsystem. **Gate:** only label components exact after reference comparison.

### Stage 4 — polished game loop and Java-like physics

Implement input, accurate hitbox and movement, voxel raycast, modes, survival damage/hunger, hotbar, inventory, crafting, tools, item drops, day/night, HUD and pause/options. Add near player lighting and weather. **Gate:** playable and saveable survival/creative experience at 20 TPS.

### Stage 5 — implement all core block categories and graphics options

Expand imported block states/models, transparent shapes, texture tint, lighting, animations, block entities and video/settings UI. Add fluid and redstone primitives, furnaces/recipes, generated structures/loot. **Gate:** every implemented settings control changes actual engine behavior; no large frame stalls when moving or editing.

### Stage 6 — scalable entity framework and all mobs

Implement rendering/rigs, AI goals, spawn rules and pooling. Build the core animals/hostiles first, test, then implement each remaining mob by small functional family batches from §9. Every family has verified distinctive behavior, sounds, drops and realistic texture/rig. Add villager trading, tame/breed, mounts, raids, boss bars and bosses. **Gate:** `MOB_PARITY.md` automatically reports working coverage; inactive registry entries are not claimed implemented.

### Stage 7 — Nether/End, progression, extended vanilla parity

Add dimension generators and portals, structures/loot, progression blocks, enchantments, potions, automation/redstone, advancements, maps, commands. Prioritize the path to the Ender Dragon then complete parity breadth. Confirm 26.3 Dappled Forest, abandoned camps, poplar, cushion/straw beds, wool/concrete stairs/slabs and preceding version additions are genuinely playable. **Gate:** complete progression is possible without creative cheats.

### Stage 8 — optimize, stabilize, verify, package code-only build

Run §§12–13 stress tests/profiles; fix memory/resource leaks, visual seams, bad frametimes, background job cancellation and race bugs. Keep per-preset numbers and fresh screenshots where possible. Produce run instructions, clean startup experience on Windows; export **CODE-ONLY/no proprietary assets** if export templates exist, otherwise provide valid Godot project with instructions. **Gate:** all P0 tests and as many P1–P3 tests as feasible pass; remaining gaps are clearly documented.

### Stage-completion policy

Each gate is a condition to **keep the working build intact**, not permission to stop: move to the next stage and continue while resources allow. If a difficult optional feature blocks progress, isolate it behind a feature flag, record a concise blocker, and continue other features. Never overwrite complete working files with shorter stubs or remove tests to make a gate appear green. Use `git diff` and test after large refactors. **Prefer 10 fully working systems over 100 fictional systems.**

## 15. Coding policy optimized for Claude Code's token use

- **GDScript only** in gameplay and editor runtime. Use `class_name` carefully to avoid collisions, typed `const`/`var`/arguments/returns, `@onready`/`@export` as applicable, `Packed*Array` and explicit resource lifetimes. No deprecated Godot 3 APIs (`Pool*Array`, `Spatial`, old signal syntax, `KinematicBody`, `yield`, `OS.window_*`). Check 4.7 API docs when uncertain.
- Prefer composition over deep inheritance. One `WorldManager`, one `ChunkScheduler`, one `Registry`, one `SaveManager`, and small pure modules. Single source of truth per state. Avoid circular `class_name` dependencies and huge mega-scripts.
- Keep components with clear interfaces. Reference docs are cheap when they're short. Put 2–5-line file header and an accurate `docs/STATUS.md`; do **not** generate a 200-page architecture commentary before writing code.
- Discovery efficiency: inspect filenames/headers first, then only needed ranges and direct references; never recursively dump the entire codebase. Use `rg --files`, targeted `rg`, limited `sed`/file reads. If output truncates, narrow it, don't repeat the same giant command.
- When code doesn't work, reproduce a bounded error, inspect only relevant stack/file/line, fix, run test again. Don't repeatedly claim “I will now read lines ...” without performing tool calls.
- Keep build scripts deterministic and quiet except for actionable warnings, errors and one-line statistics. Read only changed/tested output; collect benchmark JSON/CSV rather than pasting giant logs.
- Prefer data loops over huge generated per-block/per-mob switch statements. Generic behavior classes with config-driven variations; still add specialized logic for unique behavior.
- Use realistic resource/time budgets. Do not open thousands of images manually or load whole 26.3 client JAR into prompt context. Extract indexes programmatically and inspect small representative examples.
- Document assumptions and unknown exact values in `DECISIONS.md`; never present invented constants as Mojang internals. Pin versions for reproducibility.
- Optimize on confirmed hotspots. Avoid unnecessary broad refactoring while a working vertical slice is unstable. Include small benchmark tests alongside complex optimizations.
- Maintain `docs/STATUS.md` in an ultra-compact format: `tested`, `working`, `incomplete`, `blocked`, `next command`. After any context compaction, read **only** that summary plus relevant source files and resume immediately.
- If the current request/project cannot be completed in one context window, do the maximum useful work **now**; leave the build runnable and a concrete continuation state. Do not pretend to work after the current session has ended or claim progress that did not occur.

## 16. User-facing completion report — only after performing the work

At each meaningful milestone, summarize in **no more than 8 short lines**: (1) implemented and demonstrated systems; (2) exact Godot version; (3) launch command/path; (4) tests passed/failed and how verified; (5) measured FPS/chunk generation performance, with hardware and scenario; (6) imported asset status; (7) true 1.18.2 parity status; (8) remaining high-impact work. When fully handing off, include the run instructions and locations of `docs/STATUS.md`, `docs/MOB_PARITY.md`, `docs/BENCHMARKS.md`. **Never say “finished” when major features are placeholders.**

## 17. Reference links and version locking (use sparingly, don't browse endlessly)

**Authoritative version-specific reference material.** Prefer the target user's installed local game assets/configuration and primary references; these URLs are for targeted verification, not an excuse to spend the whole run searching:

- Godot officially supported stable releases: https://godotengine.org/download/archive/ — **4.7.2 stable as of 2026-11-09; 4.8 is beta and not a stable upgrade**.
- Godot 4.7 documentation: https://docs.godotengine.org/en/4.7/ — use `/classes/` and thread-safety docs for precise APIs: https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html .
- Minecraft Java 26.3 official changelog (2026-09-15): https://www.minecraft.net/en-us/article/minecraft-java-edition-26-3 .
- Minecraft Java 1.18 original release/technical changes: https://feedback.minecraft.net/hc/en-us/articles/4415128577293-Minecraft-Java-Edition-1-18 .
- Minecraft Wiki world generation and climate: https://minecraft.wiki/w/World_generation .
- Minecraft Wiki noise configuration and version changes: https://minecraft.wiki/w/Noise_settings and https://minecraft.wiki/w/Custom_world_generation .
- Minecraft Wiki Java client JAR/assets explanation: https://minecraft.wiki/w/Client_software .
- Minecraft Wiki versioned mobs: https://minecraft.wiki/w/Mob — **filter against actual 26.3 stable; wiki can show future mobs**.
- Minecraft 1.18.2 worldgen file schema/exploration (secondary): https://misode.github.io/worldgen/noise-settings/?preset=overworld&version=1.18.2 ; generated values from the **version-specific original report** supersede any third-party tool.
- Minecraft official EULA/permission boundary: https://www.minecraft.net/en-us/eula .

**Final priority order:** (1) runnable and safe; (2) genuine seamless persistent terrain; (3) high FPS / responsive frame pacing; (4) accurate user-owned 26.3 visual assets and usable GUI; (5) exact, *verified* 1.18.2 worldgen mode; (6) feature breadth through 26.3, including all mobs; (7) ambitious multiplayer and full parity. **Do not stop at a plan. Make the project.**

---

# EXPANSION PACK V2: FULL JAVA 26.3 GAMEPLAY-PARITY SPECIFICATION

**Status and precedence.** The following sections are part of this SAME master prompt, not optional notes. They fill omissions in sections 0-17. If two instructions conflict, use the more specific, version-verified requirement in this expansion, except that safety, user ownership of assets, and keeping the build runnable always take precedence. Do not treat the former P2/P3 labels as permission to omit Adventure, Hardcore, music, player animation, world-type controls, commands, or multiplayer; those are **required end-state features**. P0/P1/P2/P3 remain an implementation ORDER only. "Complete" requires passing the expanded acceptance matrix, not merely running a game loop.

## 18. Zero-omission inventory, acceptance ledger, and authoritative version accounting

1. Target **Java Edition 26.3 stable released 2026-09-15** for game features, visuals, sound, menus, registries and default worldgen, and **Java Edition 1.18.2** for an independently selectable EXACT legacy terrain-generation pipeline. Godot **4.7.2 stable** and Godot 4.x typed GDScript are the implementation target as of 2026-11-09. No unverified future snapshot content in the 26.3 profile. Bedrock-only UI/physics/features must NOT be substituted for Java behavior.
2. On first access to the user's legitimately installed 26.3 client and locally available official data, create `docs/COVERAGE.json` and `docs/PARITY_MATRIX.md` **programmatically**, without uploading or copying assets into the repository. Enumerate every registered `block`, `block_state`, `item`, `entity_type` (living and nonliving), `biome`, `structure`, `structure_set`, `configured/placed feature`, `block_entity_type`, `recipe`, `loot_table`, `enchantment`, `mob_effect`, `particle_type`, `sound_event`, `instrument`, `jukebox_song`, `painting_variant`, `trim_pattern`, `trim_material`, `banner_pattern`, `damage_type`, `gamerule`, `advancement`, `statistic`, `villager_profession`, `poi_type`, `attribute`, `data_component`, `world_preset`, `dimension_type`, `chat_type`, and `command` that the selected version actually exposes. Where a registry is code-defined and not in static JSON, use officially generated reports or local controlled reference observations; don't hallucinate an enumeration. Store only IDs, version tags, local source hashes, test results and implementation links in the repository.
3. **Scale check only, not a hardcoded specification:** independent 26.3 catalogs report roughly **1,286 block IDs, 1,658 item IDs, 161 entity types (many NOT mobs), 67 biome IDs, 52 structures, 2,042 recipes, 1,447 loot tables and 43 enchantments**. An individual catalog may classify IDs differently; exact counts MUST be computed from the version-selected official registry and their meaning stated. If enumeration differs, investigate, don't change the game's behavior to match a website's count. Sound registry has very many events and 26.3 has approximately 126 vanilla advancements; infer the authoritative set from local data.
4. For each ID write `asset_status`, `data_status`, `render_status`, `logic_status`, `interaction_status`, `save_status`, `verified_status`, `reference_source`, `exact_version`, and `test_case`. Allowed states: `missing`, `parsed`, `visible`, `interactive`, `mechanically_tested`, `java26_3_parity_tested`. A generic texture, mesh, item icon or spawn egg is NOT sufficient for `interactive`. Include generated percentages per category and a known-gap list. Never hide IDs to inflate percentages.
5. Separately cover **non-registry systems**: title menus, controls, screen readers, music scheduling, animation, movement/physics, hunger/XP, world creation, dimension travel, gamerules, pause/save, statistics, multiplayer, packet protocol if offered, resource/data packs, debug, commands, skins/capes, particles, sound subtitles, render settings, performance, recovery and accessibility. These also need tests. Gameplay-percentage coverage is different from imported-asset-percentage coverage.
6. Implement contracts by *families* rather than one class per unique ID, but generate an ID-specific test manifest. A family implementation (e.g. log, slab, stairs, consumable, bucket, projectile, horse, flower, chest, recipe, wood set) can satisfy hundreds of variants only when correct special cases and state transitions pass. Use explicit exception tables, not a 1,000-case monolith.
7. Produce a CLI/in-game `Parity Dashboard` displaying `total`, `parsed`, `functional`, `vanilla-verified` for every registry and system and optionally launch deterministic self-tests. Final parity signoff requires **all in-scope entries** verified or a visible, accurately labeled exception; a feature is not "done" until state, visuals, sounds and persistence agree. Never silently substitute approximations.
8. Add a `Source Of Truth` column: **A** = verified local 26.3 or 1.18.2 game data, **B** = official Mojang release notes, **C** = controlled vanilla reference observation, **D** = third-party documentation, **E** = approximation. Only A/C validated with golden data can yield `exact`. Put links and provenance in compact docs. Note that Java has some behaviors implemented as code and not exposed via resource JSON, so an asset import is not enough.

## 19. ALL modes, world types, creation options and gamerules

### 19A. All playable modes (not simply survival and creative)

| Mode | Mandatory full behavior and proof |
|---|---|
| Survival (`gamemode=0`) | Gather/mining time, durability, correct tools/drops, damage/death, hunger/saturation/exhaustion, armor, XP, crafting, natural mobs, advancements, legitimate progression, respawning |
| Creative (`gamemode=1`) | Flight, instant break, unlimited resources and placement, invulnerability rules, creative search/tabs with all 26.3 items, hotbar presets, middle-click pick block, pick block with block-entity data when permitted, drop/delete behavior, command access, survival-like mobs still present |
| Adventure (`gamemode=2`) | Interactions permitted but block placement/breaking restricted by item `can_place_on`/`can_break` components and valid predicates, block-use exceptions, health/damage/loot, custom maps and command triggers, true item tooltips |
| Spectator (`gamemode=3`) | No block collision or physical damage, no direct world edits or ordinary interaction, free camera/flight, speed control by scrolling, optional mob-spectate cameras, transparent/invisible-entity rules, proper chunk generation gamerule, **26.3 spectator portal interaction**, no normal block-outline targeting |
| Hardcore (world flag, **not** gamemode=4) | Survival rules locked to Hard and single life, distinctive world selection and HUD, permanent death/respawn restrictions and spectator continuation, correct world-lock settings, confirmation before deleting; cannot silently revert to Survival |

World **difficulty** independent of player mode: Peaceful/Easy/Normal/Hard, monster despawn/disable and hunger consequences, damage scaling and villager conversions where appropriate; enforce Hardcore lock. Include `/defaultgamemode`, `/gamemode`, `/difficulty`, F3+F4 mode switch when commands permit, and separate *personal* and *world-default* mode in 26.3 World Options. Test transitions and persistence through reload. Include Demo/Debug World only if confirmed in 26.3 and clearly distinguish them from primary modes.

### 19B. World-creation screen, tabs and every relevant control

- **Game tab:** World Name (editable/save-folder collision policy), Game Mode (Survival/Creative/Hardcore), Difficulty (Peaceful/Easy/Normal/Hard; lock in Hardcore), Allow Commands (independent of world name), meaningful compatibility warning when switching incompatible rules.
- **World tab:** Java numeric or string seed (Java-compatible string hashing and signed 64-bit parsing), World Type: **Default, Superflat, Large Biomes, AMPLIFIED, Single Biome**, and Java **Debug Mode** as version-appropriate hidden/advanced choice; choose `generator_profile`: `java_26_3`, `java_1_18_2_exact`, or explicitly **`hybrid_1_18_2_terrain_26_3_content` (NOT vanilla-exact)**. `Customize` for Superflat layer order/thickness/block IDs/biome/structure presets and Single Biome chooser. Structure generation toggle, Bonus Chest toggle with legit loot and torches. Seed randomizer, safe world spawn logic, creative spawn override optional. Reflect correct 26.3 world-type naming if local reference disagrees.
- **More tab:** Data Packs (local loading and dependency/pack-format compatibility), Experiments (off by default and clearly **experimental**, never contaminate base 26.3 profile), Game Rules editor with search/filter/category, optional Import Settings JSON/datapack where version supports. Warn that changing generation after world creation can make chunk seams; store immutable generator snapshot.
- **World management:** list Worlds with name, gamemode, hardcore icon, last played, version, seed metadata, thumbnail/screenshot, size; play, create, recreate/duplicate with same settings/seed, rename, make backup, delete with confirmation, open saves directory, version-upgrade warning, detect corrupted saves/repair from backup, world lock, migration with backup. Never modify the user's original Minecraft save without permission.
- **World options in pause menu per 26.3:** `General`: Default Game Mode, Personal Game Mode, Allow Commands, Difficulty, Edit Game Rules, Restrictions. `Multiplayer`: LAN publish/unpublish, Port, Command Access, Force Game Mode. Do not retain obsolete 26.2-only UI placement. Clearly gate the controls for unimplemented networking rather than claiming they work.
- **World presets:** normal modern terrain; legacy 1.18.2 terrain; superflat and custom layers; 1-biome; large-biomes scaling; amplified terrain; Debug Mode block-state showcase (if selected); dimension-specific custom settings only via **versioned** data pack. `Large Biomes`, `Amplified`, etc. are distinct generator algorithms/parameter sets and require reference validation, not multiplying all positions by four without checking version.
- **Per-world gamerules:** load authoritative 26.3 list, defaults, valid data types and min/max ranges. Implement categories including `doDaylightCycle`, `doWeatherCycle`, `doMobSpawning`, `doMobLoot`, `doTileDrops`, `doFireTick`, `randomTickSpeed`, `keepInventory`, `mobGriefing`, `naturalRegeneration`, `doImmediateRespawn`, `showDeathMessages`, `announceAdvancements`, `commandBlockOutput`, `sendCommandFeedback`, `reducedDebugInfo`, `spectatorsGenerateChunks`, `playersSleepingPercentage`, `spawnRadius`, `maxEntityCramming`, `universalAnger`, `forgiveDeadPlayers`, `disableElytraMovementCheck` only if version supports it, `doInsomnia`, `doPatrolSpawning`, `doTraderSpawning`, `doWardenSpawning` and newer namespaced rules as applicable. The user's installed target controls canonical spellings/defaults; translate aliases carefully and DO NOT invent removed gamerules. Test rule toggles in behavior, not only UI.
- **World boundary/time:** configure default Java border and world-border center/size/damage/warning/transition, dimension bounds, DayTime/GameTime, tick-freeze and tick-step controls in debug where permitted. Persist every rule with the world.

### 19C. Hard-world acceptance cases

1. Hardcore world save/restart retains Hard lock, no respawn after death and appropriate spectator option. Normal Survival can respawn with bed/respawn anchor constraints.
2. Adventure cannot break regular stone with a random pickaxe, but an appropriately component-tagged item can break its permitted block; no blanket Creative behavior.
3. Spectator can fly through terrain, and in **26.3** interact with supported portals without taking collision damage; entity/tile menus use proper observer rules where implemented.
4. Superflat custom 3-layer world has exactly the configured layers on positive and negative chunk coordinates; Single Biome results in one biome classification throughout its covered dimension; Large Biomes/Amplified produce clearly distinct, deterministic output.
5. World list displays the right metadata; Backup/Cancel/Delete controls work and cannot silently destroy any saves.

## 20. FULL music, sound, jukebox, note-block, and subtitle implementation

**Music is not optional.** A parsed `sounds.json` with no scheduler is not music implementation. The first-run asset importer must find **actual OGG bytes** from the selected user's official launcher cache via `assets/indexes/<index>.json` hashes, not only PNG textures in the client JAR. Require a user-owned installed resource before any copyrighted music plays. Never redistribute tracks, cache in a shared repo, scrape official downloads from mirrors, or play unlicensed music as a fallback. If music data is missing, show asset diagnostics and use silence instead of a pretend soundtrack.

**Version-aware sound manifest:** parse all `sounds.json` events, `name`, event-specific `subtitle`, `replace` flags, sound entry weights, volume/pitch distribution, `stream`, attenuation distance and category as actually defined. Resolve sound `hash -> .minecraft/assets/objects/xx/hash` in `assets/indexes`, verify SHA-1 when applicable, and map to `user://` lazy cache or read original files in place. Use Godot 4.7 `AudioStreamOggVorbis.load_from_file` / `load_from_buffer`, `AudioStreamPlayer`, `AudioStreamPlayer3D`, persisted `AudioServer` buses. Keep long tracks streamed or lazy decoded (do not permanently preload hundreds of megabytes). Version differences must not break sound lookup. Fallbacks only with user-visible warnings.

| Audio class | 26.3 requirements and what to test |
|---|---|
| Title and menu music | Genuine private asset tracks, randomized version-correct timing, background/music slider, pause/mute/unfocus semantics, avoid overlaps and restarting a track whenever a menu opens |
| Overworld soundtrack | Select tracks by dimension, biome, time/weather and applicable event/environment attribute, with exact weighted/cooldown behavior when verified, quiet stretches, crossfade or cut rules matching actual version, no one generic endless loop |
| Nether/End | Dimension and biome-specific track selection, dimension transition, End boss/fight/cinematic/credits music as permitted, prevent overlapping world and menu tracks |
| Environmental ambience | Cave eerie sounds, biome ambience, underwater, wind, weather/rain/thunder, special blocks/biomes, pale garden/deep dark/caves, 26.2 sulfur caves, geisers, bubbles, appropriate muffling |
| Discs and jukebox | Every 26.3 disc item maps to its correct private audio track; insertion/ejection, pickup, one disc slot, playback timing, duration, 3D audible distance, comparator output, particles, stop when broken, persist playback position per version; 26.2 added **Bounce** by fingerspit. Do NOT implement future 26.4 jukebox chest-playlist behavior as if already in 26.3 |
| Note blocks | Instrument choice by supporting block including 26.1 **copper trumpet** with oxidation-specific sound, 25 semitone pitches, colored particles, player tuning/right click, redstone triggering, repeated pulses, correct audible range and efficient polyphony |
| Hit/interaction | Distinct step/fall/place/break/use sounds by block and surface, tool critical attacks, armor/shield, projectiles, item pickup/drop, opening chests/doors/traps, brewing/crafting/XP, all imported 26.3 event variations |
| Entity/animation | Correct idle/ambient/hurt/death/attack/movement/footsteps for all mobs, baby vs adult variants (especially 26.1), environment-based sound pitch, positional occlusion/attenuation as the version implements |
| UI | Buttons, inventory drag/swap, recipe discovery, advancements/toasts, death, achievement chime, pause, World Options, import warnings and title sounds where applicable |
| Sound categories | Master, Music, Jukebox/Note Blocks, Weather, Blocks, Hostile, Friendly/Neutral, Players, Ambient/Environment, Voice/Speech, UI; match vanilla categories rather than inventing mismatched sliders. Per-category volume independent and saved |
| Subtitles | Sound-event subtitle registry resolution, localizable text, 3D direction arrow/indicator and distance/lifetime rules, **26.3 subtitle points to most recent sound in range**, contrast/scaling, no fake subtitles for nonexistent audio |

**Sound scheduling algorithm:** `SoundDefinition` registry, `MusicContext` derived from dimension/biome/event, `MusicScheduler` with seeded but player-independent track selection and nonrepetition constraints, `SpatialAudioManager` with bounded source pool, `JukeboxManager` with one tracked event per active jukebox, `NoteBlockVoicePool` with short polyphony, `SoundMixer` with volume buses and limiter. Preserve gameplay state if audio device is unavailable or track fails. Never let a missing OGG crash a world. Respect display focus options: on lost focus, pause or continue based on explicit setting; on world pause, implement the matching single-player semantics. Cache offscreen audio cheaply, with priority to player/collocated/high-attention sounds.

**Explicit 26.2 soundtrack changes:** include `music_disc` Bounce and the five background tracks **Shores, Memories, Nightly, Home, Ebb** as locally discoverable assets and eligible only for their actual weighted/context rules; `music.overworld.sulfur_caves` when correct. Do not infer their raw filenames from English titles when `sounds.json` provides identifiers. Correctly handle songs from prior updates, recent composers, credits and boss tracks through the version manifest, not an incomplete handwritten title list.

**Music acceptance:** Verify playing a new world with locally installed sounds eventually triggers real music; changing to Nether/End changes appropriate selection; slider Music=0 mutes background but leaves Blocks audible; jukebox insertion plays the right local disc, stops when removed, syncs disc logic across save/reload and LAN; note blocks select the correct instrument and pitch, including trumpet/copper oxidation; sounds are spatial, attenuate and subtitle properly. Record asset hashes and event IDs, never distribute decoded audio.

## 21. Fully animated PLAYER, models, hands, skins, equipment and cameras

Implement an original voxel/box-joint rig reproducing Java geometry, body part proportions, 64x64 skin sheet mapping, legacy 64x32 handling, standard 4px vs slim 3px arms, inner/outer skin layers, hats/jackets/sleeves/pants, head yaw/pitch limits, body yaw smoothing, mirrored limbs and UV orientation. Import skins locally from user-selected files or permitted owned local caches; optional default **original** placeholder skin if a licensed/official one is absent. No silent cloud account/skin fetch. Handle multiplayer skin synchronization only with user consent and lawful asset paths. Apply armor/equipment/trim textures and dye tint from local assets, elytra wings, helmets/head items, held maps, spyglass, shields, tridents, bows, crossbows, mace, spears, fishing rods, and offhand as actual equipped objects with matching transforms.

**Player state machine (first-person AND third-person, visible to LAN peers):** idle breathing, head look, walk, sprint, walk backward, lateral strafe, diagonal walk, acceleration/deceleration, crouch idle/walk, jump takeoff/fall/land, swimming surface, underwater swim, sprint swim, crawling, ladder/vine climb, flight/hover, elytra glide/dive, riding horse/camel/nautilus/boat/minecart/Happy Ghast where applicable, attack/swing/hit-stop/cooldown, continuous block breaking, use item/eat/drink, charge/release bow/crossbow/trident/spear, shield blocking, spear jab/charge from Mounts of Mayhem, fishing cast/reel, place block/use door/chest, damage recoil/red tint, knockback, burning/frozen/poisoned, potion effect overlays, death/ragdoll NOT if Java animation is deterministic, sleep, wake, sit/cushion, spyglass zoom, map held with two hands, totem activation, eating particles, equipment swap, emotes ONLY if actual Java 26.3 feature (do not import Bedrock behavior).

**First-person arm rig:** exact-feeling item pose, left/right dominance, handedness preference, hand swing, arm sway/equip transition, mining animation and crack stage, block model vs sprite item display, attack strength indicator, crosshair interactions, shield raising/lowering, offhand rendering, fishing line, map, spyglass. Respect hide HUD/F1, F5 third-person rear/front switch, FOV change while sprinting/flying/using spyglass, camera bob toggle, damage tilt, nausea/portal distortion toggle, brightness/darkness and accessibility effects. Avoid excessive third-person animation overhead when first-person only.

**Hitbox separation:** animation skeleton is visual only; physics uses accurate state-specific AABB, eye height, step-up, collision face logic. Head pitch/body turn/hands and held items must update smoothly but not change hitbox. Use pose masks or typed animation controllers; do not bind gameplay position to frame-dependent keyframes. Transitions and travel direction survive framerate changes and network interpolation.

**Variant coverage:** 26.1 redesigned many baby models and baby sounds; create version-specific baby rig/texture variations for cow, mooshroom, sheep, pig, cat, ocelot, wolf, chicken, rabbit, horse, donkey, mule, zombie/skeleton horse, camel, llama, bee, fox, goat, armadillo, polar bear, panda, snifflet, dolphin, squid/glow squid, turtle, axolotl, strider, hoglin, zoglin, zombie/husk/drowned, piglin/zombified piglin, villagers/zombie villagers. **26.1 Golden Dandelion** stops/restarts eligible baby aging; correctly exclude undead babies and baby villagers where version specifies. Some mob variants have biome-based skins and sound variants (not new entity IDs). Test all using a private automated entity showcase world and compare to matching 26.3 reference screenshots/behavior.

**Animation acceptance:** 1st-person break/eat/shield/held-map/spyglass, 3rd-person sprint/sneak/swim/crawl/elytra/riding/sleep, slim and standard skins, armor trims, weapon use and 26.1 baby variants all transition without sliding, flicker, limbs detaching or breaking collision. Include animation test snapshots and side-by-side vanilla reference measurements where available; otherwise mark approximation.

## 22. FULL BIOME and modern + legacy world generation matrix

### 22A. Worldgen profiles MUST be separate

- `java_1_18_2_exact` uses its **own** Java 1.18.2 seed samplers, RNG, noise settings, 6D climate/biomes, terrain shaper splines, density router, carvers, aquifers, noise interpolation cells, surface system, ores, feature/structure generation, jigsaw/template NBT and 1.18.2 biomes, items, blocks, loot and entities as applicable. If newer 26.3 content is injected, label that *hybrid* instead of exact 1.18.2.
- `java_26_3` reads 26.3-specific data, registries, material rules, climate, biome environment attributes, placement/structure features and noise system. It is NOT numerically the same as 1.18.2. In 26.3, noise format and floating-point evaluation changed: `base_octave` / `octave_count` / `base_amplitude` / `amplitude_modifiers` / `normalize` replace older fields; **density/noise evaluation is single-precision**, so preserving older double-precision math produces incorrect 26.3 sampling. `worldgen/material_rule` and `material_condition` are separate registries; `worldgen/feature` replaces former configured-feature split. Mob spawn fields moved into environment attributes. Do not parse 26.3 as 1.18.2 JSON.
- `hybrid_1_18_2_terrain_26_3_content`: **EXPLICIT EXPERIMENTAL MIX** in which geological terrain/noise is fixed to 1.18.2, and compatible modern content overlays only by a documented, deterministic feature placement policy; newer biomes have no vanilla 1.18.2 placement parameters. Generate full metadata. Never claim same seed creates both exact old terrain and all new biome placements without differences.
- All profiles persist `generator_id`, seed, dimension, data pack/version fingerprint, algorithm revision, biome registry version and world type. If changed later, existing sections remain from their saved generator, or only user-confirmed copy-on-upgrade migration occurs. Cross-version terrain seams are flagged.

### 22B. Exact biome IDs to cover for Java 26.3 (67 IDs, including special Void)

Do NOT treat this as a weighting or worldgen placement list. Actual placements, temperature, erosion, humidity, surface palette, weather, spawning and generation weights are extracted from the chosen version's data. `the_void` is a special preset biome, not an ordinary overworld region. `Deep Dark`, `Sulfur Caves`, `Lush Caves` and `Dripstone Caves` are 3D cave biomes and MUST NOT be painted purely by surface climate sampling.

```
Overworld (56 ordinary + 1 special/preset):
badlands, bamboo_jungle, beach, birch_forest, cherry_grove,
cold_ocean, dappled_forest, dark_forest, deep_cold_ocean,
deep_dark, deep_frozen_ocean, deep_lukewarm_ocean, deep_ocean,
desert, dripstone_caves, eroded_badlands, flower_forest, forest,
frozen_ocean, frozen_peaks, frozen_river, grove, ice_spikes,
jagged_peaks, jungle, lukewarm_ocean, lush_caves, mangrove_swamp,
meadow, mushroom_fields, ocean, old_growth_birch_forest,
old_growth_pine_taiga, old_growth_spruce_taiga, pale_garden,
plains, river, savanna, savanna_plateau, snowy_beach,
snowy_plains, snowy_slopes, snowy_taiga, sparse_jungle,
stony_peaks, stony_shore, sulfur_caves, sunflower_plains,
swamp, taiga, the_void [special], warm_ocean, windswept_forest,
windswept_gravelly_hills, windswept_hills, windswept_savanna,
wooded_badlands

Nether (5): basalt_deltas, crimson_forest, nether_wastes,
soul_sand_valley, warped_forest

The End (5): end_barrens, end_highlands, end_midlands,
small_end_islands, the_end
```

**Generate all biome metadata**: namespace, source version, dimension/preset, temperature and modifier, precipitation and downfall, sky/water/fog/foliage/grass colors, ambient loops, particle types and rates, sound/music tags, terrain climate placement and 3D depth, cave overlap/surface feature dependencies, ground and underwater materials, flowers/crops/foliage/tree variants, tree/trunk/leaf shapes, hostile/passive/ambient/water spawning, structure tags and local features, exact per-stage order and randomization. Respect biome borders, blended foliage, ocean water tint, high-altitude snowfall, frozen river/beach edges and caves below forests. Do not confuse biome color with global grass texture.

### 22C. Required generation pipeline, in exact stage/source order

1. `seed_and_random`: Java 64-bit world seed parsing, generation-specific RandomSource (including legacy/Xoroshiro/PositionalRandom), dimension salts, Java signed overflow, coordinate mixing and version-distinct RNG stream ordering. **Do not** use Godot FastNoiseLite for exact parity or seed Java's functions with a simple hash.
2. `biome_climate`: Java quart/block coords, versioned multi-noise sampler with temperature/humidity/continentalness/erosion/weirdness/depth, 6D nearest box parameter logic, off-by-one inclusive boundary behavior, biome cave sources, climate-shift and region caching. Record intermediate sample values for golden tests.
3. `density_field`: version-selected noise router, octave/perlin/normal-noise, terrain splines, interpolation cells, slide/factor/jaggedness/offset nodes, blending/structure beardifier, erosion, islands, amplified variants, and valid Y boundaries; no heightmap-only approximation accepted as parity.
4. `aquifer_and_fluids`: local water levels, cave water/lava choices, barrier noise, waterlogged blocks, flooded caves, lava below sea where appropriate and proper density air replacement. Cross-chunk liquid boundaries must be continuous; avoid spontaneous water walls after load order changes.
5. `surface_material`: 1.18.2 surface rules vs 26.3 `material_rule` registry, thickness/noise depth, bedrock, deepslate/tuff, stone/gravel/clay/sand, topsoil, beaches, snow/ice, powders, badland terracotta, geothermal, sulfur/cinnabar, 26.3 cold Dappled Forest. Use exact versioned rule data.
6. `carvers_underground`: cheese/spaghetti/noodle/entrance caves, canyons and ravines if version calls for them; lava aquifers, sculk/deep dark, dripstone/lush/sulfur cave features, iron/copper veins and speleothems. Carving must be spatially stable with no visible seams or artificial horizontal chunk stripes.
7. `structure_start_and_jigsaw`: potential placement via structure sets, frequency reduction/spacing/separation/salt, biome tags, adapted terrain/piece intersections, jigsaw pools/connectors/weights/rotation/mirror, underground support, randomized loot/inventory/entity placements, cross-chunk buffers and idempotent continuation. Use canonical NBT where available locally and compatible with version; don't paste protected structures into repo.
8. `decorations_and_features`: ores and vein height curves, amethyst geodes, gravel/clay/sand patches, springs/lakes, obsidian, flowers/grass/mushrooms, every biome-specific tree type and branch/leaf variant, huge mushrooms, fallen trees, vines/bamboo/kelp/coral, icebergs, rare structures, poplar/shelf mushrooms/red shrubs, crops/fruit, sugar cane, pumpkins/melons, fungi, grasses and leaf litter; correct ordering and heightmap predicates.
9. `finalization`: heightmaps (`WORLD_SURFACE`, `OCEAN_FLOOR`, `MOTION_BLOCKING`, etc. as appropriate), sky/block light, fluids scheduling, mob spawning at generation according to version-specific source, structure references, biome palettes, save metadata; chunk-border propagation and async graph work.

**Exact numeric parameters rule:** Never invent frequency, octave, aquifer, spline, ore-vein, structure spacing or biome threshold parameters. Generate a machine-readable `docs/WORLDGEN_PARAMETERS_1_18_2.json` and `docs/WORLDGEN_PARAMETERS_26_3.json` from the authorized version-specific local data/report. These are compact **parameter/index summaries and hashes**, not copied proprietary textures/structures/code. Every value comes with `source_path`, JSON pointer, exact version, value and validation status. Build data-driven parsers that can consume the local full reference, with a no-license distribution path that generates correct results when the user's local reference exists. If source unavailable, mark the exact generator `unverified/unavailable` rather than inventing settings. Document whether data generation legitimately requires Java 17 for 1.18.2 or Java 25 for 26.3 and verify requirements on the installed jars before running commands.

**Parity fixtures:** create canonical Java 1.18.2 and Java 26.3 tiny reference-world datasets in a temp path (with user's installed official copies if available). At seeds `0`, `1`, `-1`, `123456789`, `-987654321`, hash sampled biomes/heights/ore sections/noise intermediate values/feature starts at origin, negative XZ and far corners. Include sea level Y=63, 1.18.2 Overworld -64..319, bedrock layers, undersea caves, tall mountains, deep cave floor, lava aquifer edges, waterfalls and waterlogging; test negative modulo and chunk boundaries. Publish per-component mismatch counts without copying client content into any distributed build. Simultaneously validate modern 26.3 dappled forest and sulfur cave generation without assuming those exist in 1.18.2.

## 23. Every BLOCK family and block-entity mechanic, not just visuals

The `block`/`blockstate` registry is exhaustive and data-driven, but each state must have correct occlusion, collision, outline, light, material, tool, drop, item, neighbor-update and ticking behavior. Build these reusable semantic families, with generated per-ID parity tests and version-aware exceptions:

| Family | Mandatory mechanics |
|---|---|
| Full cubes | Hardness, blast resistance, slipperiness, tool-mining rule, faces/tint, opacity/skylight, translucency, sound type, explosion drops, placement/rotate/mirror |
| Slabs, stairs, walls, fences/gates | Half/top/bottom, inner/outer corners, left/right handedness, shape recomputation, connected/fenced pathfinding, waterlogged states, occlusion and multi-AABB collisions, correct tool/drop behavior |
| Doors/trapdoors | Two-block state, power/open/facing/hinge, sound, collision, villagers and redstone, fluid content, double-door variant when version behavior requires it |
| Transparent and thin | Glass/stained glass, panes, ice, leaves, iron bars, chains, trapdoors, carpets, rails, banners, signs, ladders, vines, small plants, light propagation, no incorrect hidden faces |
| Logs and wood | Every tree set including poplar, axis, stripping, leaves distance/decay, sapling growth, tree variants, doors/buttons/plates/fences/gates, signs/hanging signs, boats/rafts/chest boats where applicable |
| Wool and concrete | All 16 dyes, wool/concrete powder, water conversion, hardening, **26.3 wool/concrete stairs+slabs**, wool vibration dampening and correct mining |
| Crops and growth | Seeds, farmland hydration/trampling, 0..N growth stages, random tick, bone meal, stems/attached fruits, berries, cactus, sugar cane, bamboo, kelp, vines, cocoa, nether wart, fungi, chorus, saplings, moss, azaleas, flowers and new shrubs |
| Fire/light | Torches/wall torches, soul torches, candles/cakes, campfires/soul campfires, lanterns, glowstone, shroomlights, froglights, sea pickles, redstone lamps, copper bulbs, sculk sensors, end rods, portal lights; correct orientation, light colors in renderer only if parity supports, propagation radius and opacity |
| Water/lava | Source/flow levels, viscosity/tick priority, renewability, lava + water results (obsidian/cobblestone/stone), bucket scoop/place, cauldrons, waterlogging, plants and entities, fishing, underwater physics, ice/freezing, water elevators and bubble columns |
| Terrain/environment | Sand/red sand/gravel/anvils/concrete powder falling entities, snow layers, powdered snow freezing/sinking/leather, honey/slime bounce, soul sand/soul soil drag, ice friction, magma damage, pointed dripstone damage/cauldron fill, mud/clay conversion, sculk spread |
| Decorative/stateful | Pots and sherds, glazed terracotta, beds, flower pots, hanging signs, lecterns, bookshelves/chiseled bookshelves, leaves/leaf litter, jukeboxes, note blocks, cakes/food, item frames and glowing frames, paintings, bells, chains, banners, carpets, armor stands, shelves, cushions |
| Storage | Chests/double chests/trapped chests, barrels, shulker boxes, ender chest per player, furnaces/blast furnaces/smokers, hoppers, droppers, dispensers, 26.3 copper chests, 26.3 copper-golem sorting state, comparator signal mapping, lock codes where supported |
| Technical/redstone | Piston/sticky piston/slime/honey movable assembly, redstone wire, repeaters, comparators, observers, daylight detectors, tripwire hooks, levers/buttons/plates, sculk and calibrated sensors, crafters, target blocks, all rails and minecart interactions |
| Nether/End blocks | Nether portal/obsidian/crying obsidian, respawn anchor, nether fungus/nylium, soul fire, basalt, blackstone, ancient debris, budding amethyst, end portal/frame/gateway, end stone, purpur, chorus, dragon egg, dragon heads, shulker box and attached variants |
| Structure and dungeon | Spawners, trial spawners, vaults/ominous vaults, suspicious sand/gravel archaeology brushes, decorated pots, reinforced deepslate, shriekers/catalysts/sensors, ancient-city blocks, rails/traps/tombs, structure block and command block (if permission enabled) |
| Special 26.2/26.3 | Sulfur, cinnabar, spikes, potent sulfur, geysers, toxic gas, sulfur-cube block absorption; dappled-forest poplar/colored falling leaves/shelf mushrooms/red shrubs; straw-bed one-time sleep without spawn, 16 cushion colors with sitting entity, abandoned camp containers |

**Block state test definition:** for each state group: item-to-block placement, orient toward hit face, rotate/mirror, geometry/faces/UV/collision/occlusion, fluid persistence, tool hardness/drops, sound, tick and neighbor update, piston motion if movable, inventory/machine UI if applicable, light value, redstone comparator value if applicable, persistence and multiplayer replication. Enforce correct property names, not a guessed `facing` property on all blocks.

**26.3 notable mechanics from the official notes**: Dappled Forest appears near cold biomes; poplar red/orange/yellow leaves and fallen poplar logs, shelf mushrooms on trunks and fallen trunks, shelf mushroom growth with bone meal and light bounce, red shrub spreading with bone meal; abandoned camps have biome variants, loot containers and explorer maps; **straw beds are one-use and do NOT set spawn**, are crafted 3 hay bales -> 4 and fail/destroy in Nether/End; cushions sit on horizontal flat support, 16 colors, break on support removal, have no normal collision, cannot be pushed by pistons; wool stairs/slabs damp vibrations; concrete stairs/slabs stonecutter recipes. Test each with actual interaction and save/reload.

**26.2 sulfur systems:** Sulfur Caves are a separate UNDERGROUND biome with sulfur/cinnabar bands and pools. Potent sulfur under water emits bubbles/toxic surface gas; magma/lava below creates periodic or continuous geyser behavior according to version conditions and water depth. Sulfur spikes merge/grow/fall/damage correctly. Sulfur Cube absorbs one block via interaction, changes its physical archetype and properties, can be ejected/sheared, is split/converted as version defines and uses new sounds and particles. Do not turn this into a generic slime with a texture.

**2025-2026 copper features:** Copper equipment tier, copper chest and golem, copper oxidation/wax/scrape, copper lamps/bulbs, copper-themed blocks and armor trim where applicable; correct sorting radius and carried stacks if verified. The 26.3 block transformer registry (`minecraft:block_transformer`) is versioned and should control tool stripping/scraping/path/tilling where possible. External model JSON is not enough to know functional piston/neighbor behavior.

**Block entities must be real:** each machine has a typed inventory/data payload, client screen, server-side authoritative behavior, hopper item insertion/extraction, command and persistence interface, active-tick budget and dirty notifications. Include signs/front-back text, command/structure blocks gated by permissions, skull/block entities, beacon pyramid/beam/effects, brewing stand, lectern page state, campfire cooking, decorated pot storage, banner patterns, trial spawner and vault data, beehives, crafter, jukebox playback state, sculk sensors, skull/hanging signs, map decorations, bed spawn and cushions as correct entity/block distinction. Build a separate `BLOCK_ENTITY_PARITY` report.

## 24. Every ITEM, COMPONENT, recipe, loot and progression system

**Not a texture catalog.** Generate the complete 26.3 item ID list locally; each item has classification, stack size, durability, tool tier, equipment slot, placement/use action, cooldown/charge time, animation, enchantability, damage, attack speed, food/saturation/status effect, sounds, description/tooltip, default data components and NBT-equivalent persistent state. Unknown items retain IDs safely and are displayed as unsupported, never magically become generic blocks.

- **Tools and equipment:** wood/stone/copper/iron/gold/diamond/netherite tools, swords, axes, pickaxes, shovels, hoes, armor including leather dye and armor trims, shields/banner patterns, bows/crossbows, tridents (throw/Riptide/loyalty/channeling), netherite upgrade smithing templates, fishing rod, shears, flint/steel, brush, spyglass, mace, spear with 1.21.11 velocity-scaled jab/charge and Lunge enchantment, elytra, saddle/mount armor and new nautilus armor. Attribute modifiers, combat cooldown, range and reach must vary correctly.
- **Consumables:** food, food exhaustion, suspicious stew variants, golden apples, enchanted golden apples, milk removes effects, potions/splash/lingering/tipped arrows, honey bottles, mushrooms/stews, dried kelp, raw vs cooked, specific poisonous/harmful foods, golden dandelion baby-aging use; container remainders and animation.
- **Throwables/projectiles:** snowballs, eggs, ender pearls including teleport damage/velocity resets, eyes of ender stronghold trajectory and portal frame, wind charges, fireworks/elytra propulsion, splash bottles, tridents, thrown spears if version permits, fishing bobber, arrows/spectral arrows, potion clouds, fire charges, ghast fireballs, dragon fireballs.
- **Tools for blocks:** buckets (empty/water/lava/milk/powder snow/fish/axolotl/tadpole), leads/leash knots, bone meal, bottles, boats/chest boats/rafts, armor stands, paintings, item frames/maps/compasses/clock, recovery compass, brush archaeology, shears honeycomb, dye patterns, signs and hanging signs, banners, fireworks stars/rockets, firework recipes.
- **Recipes:** 2x2 inventory and 3x3 table shaped/shapeless, crafting remainder, stonecutting, smithing transform/trim, furnace/blast/smoker cooking and fuel time, campfire, brewing, loom/banner, cartography map scaling/lock/clone, grindstone disenchant/repair, anvil repair/rename/combine/cost/Too Expensive, enchantment table bookshelf effects, composter and beacon mineral input. 26.3 makes **brewing recipes data-driven**, with world-data providers and configurable fuel rules; implement the *selected version* recipe/fuel registry rather than hardcoded old brewing logic. Use a recipe book with unlock notifications, filters, craftable flag, ghost recipe/auto-fill and shift-click craft-all.
- **Loot:** read every versioned loot table and predicate, seeded container content, silk touch/fortune, tool/biome/entity damage source, fishing treasure/junk/fish, archaeology brushes, structure chests, trial chambers/vaults, abandoned-camp loot, bastions, strongholds, piglin bartering, villager gifts/trades, mob equipment/drop modifiers, experience orbs, advancements/criteria, block loot conditions. Count drops per stack and maintain exact RNG sources where possible.
- **Villagers and trade economy:** full profession/job-site/biome appearance matrix, trade tiers, restocking, gossip/reputation, discount/demand, zombification/cure, hero of the village, wandering trader new trades, emerald prices, regional experiments only if enabled, GUI correct sell/buy behavior and XP. 26.3 trades can update while trade window remains open.
- **Enchantments:** discover every 26.3 registered ID (third-party catalog approx 43). Implement mutually exclusive groups, weights, level limits, treasure/curses, XP cost, tool compatibility, effects on break/combat/armor/projectiles/looting/fishing/mob events. Include Mending/Unbreaking, Protection family, Sharpness/Smite/Bane, Efficiency/Fortune/Silk Touch, Respiration/Aqua Affinity, Depth Strider/Frost Walker/Soul Speed/Swift Sneak, Power/Punch/Flame/Infinity, multishot/piercing/quick charge, trident group, mace group, Lunge for spear and any versioned additions. Don't falsely count an enchantment functional because its glint renders.
- **Potion/status effects:** enumerate all 26.3 effect IDs and potion variants. Distinguish instantaneous vs timed, amplifier, duration ticks, brewing transformations, harmful/beneficial/neutral, splash radius, lingering cloud, tipped arrows, beacon/conduit effect, totem, milk, resistance, fire resistance, water breathing, slow falling, saturation, hunger, nausea, blindness, darkness, trial omen/bad omen, glowing, levitation, wither, absorption, health boost, luck/unluck where present; version dictates details.
- **Durability and item components:** game data components should survive crafting/transforms, enchant, renaming, container operations, books, custom names/lore, banners, pot decorations, maps, fireworks, jukebox-playable and item-use animations. 26.3 changed some components such as sign text and map metadata; avoid unsupported NBT guesses.
- **Statistics and advancements:** advancement tree, trigger predicates, per-world persisted criteria, UI tabs/scroll/navigation, toast notifications, rewards/recipes/XP, command `/advancement`, stats screen for general/items/mobs and newer straw-bed sleeping statistic. Count and verify against 26.3 local data, including hidden/secret advancement criteria.

**Transactional tests:** shift-click across chest/furnace/crafter, drag stack split, pickup-and-drop, double-click collection, offhand swap, stack sizes 1/16/64, container sorting, recipe result/remainders, death inventory transfer, XP consumption, enchanting, trading and price/restock, hopper automation, multiplayer simultaneous access, interruption while brewing, save/reload mid-craft, nonduplication after crash recovery. Prioritize **no item dupes or silent loss** in persistent worlds.

## 25. Redstone: tick accuracy, circuit correctness and automation integration

- Separate game logical time at **20 TPS** from Godot render and physics; scheduled block updates with priority and sub-order where version rules require, unique event IDs, block state after neighbor notifications, correct random ticks versus scheduled ticks, active chunk ticket/persistence rules. Build deterministic circuit replay harness.
- Redstone dust connection/level 0..15, direct/indirect power, strong/weak powering, torch burnout, repeater ticks and locking, comparator subtract/compare and container fullness, tripwire, sculk sensors, calibrated sculk, observers, note blocks, target blocks, daylight sensors, levers/buttons/pressure plates, redstone lamps, copper bulbs, quasi-connectivity (Java-specific) and powered rails.
- Pistons/sticky pistons: push limit and movable/immovable block tables, slime and honey attached blocks, collision with entities, Java update ordering, push/pull behavior, block entities and fragile replacements, block retraction, ghost-piston prevention, crossing chunk boundaries. Test piston doors, 2x2 hidden doors, slime/honey contraptions, flying-machine circuits if parity target includes them.
- Hoppers, droppers, dispensers: correct item transfer direction/cooldown and filters, redstone disable, item ejection/projectile spawning, shears/buckets/armor equip/boat spawn behaviors, hopper minecarts and chests, auto-crafting 26.3 crafter slot disable/drop semantics, furnace/composter storage, comparator output and bulk item flow.
- Rail transport: powered/activator/detector rails, curves/slopes, minecart physics, boosters, hopper/chest/furnace/TNT minecarts (if in 26.3), block collision and entity carts. Boats/rafts with paddling, air/water/ice/soul-sand influence, collidable passengers, leash behavior, chest storage.
- Sculk/sensor events: implement vibrations, filters, wool dampening (including new wool slabs/stairs), calibrated sculk and Warden/shrieker reactions. Correct 26.2 geyser start/end events detectible by sculk sensors. Hoppers and entities should not starve block updates or cause full-world relights.
- **Fidelity test circuits:** 10-tick repeater timing; 15-block wire decay; observer clock; comparator chest output from mixed stacks; hopper filter and multi-chest; sticky piston quasi-connectivity; BUD switch; T-flip-flop; instant harvest farm; railway junction; 26.3 crafter and sulfur geyser vibration; trapdoor controls; unload/reload same tick without loss or duplicate transfer.
- Distinguish `mechanically working in normal gameplay` from precise redstone update-order parity; put deviations in `REDSTONE_PARITY.md`. No blanket claim of "100% redstone" without timing golden tests.

**26.3 animation component migration:** Interpret versioned item data components `minecraft:attack_animation` and `minecraft:interact_animation` as distinct attack versus use interaction animations; do not use removed `minecraft:swing_animation` as the 26.3 schema. Validate default attack/use duration and pose transitions against the 26.3 changelog and installed data, including the unusual item model transformations for shields, tridents, spears, maps and spyglasses. Store item-component IDs on save/load and apply exact schema migration rules.

## 26. All mobs, variants, movement, AI, spawning, villages, raids and bosses

Section 9 provides the living-mob candidate roster. Do not assume classifying sulfur cubes, nautili, camel husks or zombie horses as "passive" means their actual behavior is passive in every state; consult 26.3 and use entity-specific rules. **The registered `entity_type` set also contains nonliving gameplay entities**: boats/rafts/chest boats, all minecart varieties, item drops, arrows and other projectiles, thrown potions, area clouds, fireballs, falling blocks, TNT, armor stands, item frames/glow frames, paintings, item displays/block displays/text displays/interaction entities, end crystals, leashes, fishing bobbers, lightning, experience orbs, evoker fangs, dragon attacks, all applicable vehicles and decorative entities. For each type, create a real spawn/update/render/collision/serialization behavior; keep a distinct entity type matrix from the MOBS matrix.

**Common mob AI rules:** spawn categories/caps, despawn rules, per-biome spawn weights and conditions, light and block checks, difficulty, hostile weapon equipment, armor and loot, follow range, look/perception, line-of-sight, target memory, motion cost and pathfinding, breeding/cooldowns, mating and baby genetics, age/maturation/26.1 Golden Dandelion, sleep/rest, patrol/school/swarm/herd, anger memory/pack attack, block griefing, tame/command/follow, damage immunity, elemental/environment responses, interaction hand/tool items, drops/XP, status effects, persistence, dimension crossing, step height, boat/minecart/passenger mounting, variant textures/animations/sounds. Update tick only when near/eligible, preserve important simulation during unload through queued state, and don't affect deterministic random sources by render distance.

**Specific family requirements beyond section 9:**
- **Villagers:** births/careers/POI beds/job sites/bells, restock, schedule and workstation use, raids/defense, gossip/iron golem spawning, wandering trader timetable and llamas, biome/profession skin, trader UI. Trading in a 26.3 world updates new unlocked offers while GUI stays open.
- **Illagers and raids:** pillager captain banner, bad omen/ominous effects, raid waves, village defenses/bells, ravager riders, witch healing, evoker fangs/Vexes, Totem of Undying, patrols, vindicators; difficulty and omen control.
- **Trial Chambers:** trial spawners normal/ominous, keys/vaults, Breeze and wind charges, loot, cooldown/wave trigger, reward and persistence; all required blocks and sound/particle effects.
- **Ancient Cities:** sculk vibration propagation, wool suppression, shrieker warning counter and darkness, Warden emergence and retreat, heartbeat, sonic boom, sensing, loot, Deep Dark layout and 3D biomes.
- **Pale Garden:** pale oak, Creaking Heart daylight/night connection, creaking activation, gaze/eye mechanics, persistent heart/block/creaking relationship, moody sounds/colors and structure/vegetation.
- **Mounts of Mayhem (1.21.11):** nautilus, zombie nautilus, naturally spawning zombie horse, camel husk, Parched, spears and Lunge, mounted riding/attack/reins/armor, aquatic oxygen and passengers. No static mobs with no mount controls.
- **Tiny Takeover (26.1):** baby appearance/sounds and animation changes, new chicken/cow/pig/cat variants, craftable name tags, aging stop/start with Golden Dandelion, note-block copper trumpet. Implement correct variant NBT/data-component persistence.
- **Chaos Cubed (26.2):** sulfur cube absorb/eject material; block archetype impacts friction, gravity, bounciness and heat; poison clouds/geysers; ambient/sulfur biome soundtrack. Add distinct small/large cube behavior.
- **Wilderness Bound (26.3):** Dappled Forest farm animal cold variants, fox/rabbit; new camp structures and specific gameplay items; entity cushion sitting interaction and fall damage handling per version.
- **Water and flying:** dolphin air rescue, axolotl fighting and playing dead, turtle nest/beach homing, tadpole metamorphosis to frog variants, enderman teleport when rain/water, bees to hive and pollinate, Happy Ghast growth/riding, ghast projectile physics, dragon flying/phase/boss portal.
- **Bosses:** Ender Dragon multi-stage flight/neck/head/wing animation, perch, breath, crystal healing, towers, portal generation, gateways/dragon egg/respawn loop and End Poem/credits; Wither summoning, initial invulnerability, shield phase, block destruction, Nether Star drop and beacon progression.

**AI architecture:** archetype components + typed state machine behavior trees/priority selector + local steering; asynchronous voxel navigation using version-aware collision shapes, climb/swim/fly path map and delayed updates; group cap, spawning simulation distance, passive fallback, priority culling. No one Node per distant block, no per-mob full A* every frame. For distant mobs, sleep pose and animation but keep appropriate gameplay ticks and save data. Build deterministic replay of AI inputs to test route decisions across FPS differences.

**Complete mob test suite:** every registered living mob can be spawned via commands/egg where appropriate; has correct proportions/textures/animations, accurate health and damage, interaction/tame/breed rules, pathfinding and gravity/buoyancy, correct sounds and item drops, time/biome/spawn behavior, baby and equipment states, save/reload, no memory leaks with a large herd. Produce category counts and per-variant failure report. "Can be spawned" alone is not completion.

## 27. Rendering and lighting exactly where practical; more efficient than Java ONLY when measured

- **World art:** import own local block texture atlas/arrays with correct mip transparency, dynamic texture animation, connected blockstate and neighboring texture variants. Sky/sun/moon/star phases, shadows, weather, cave light, light-emission 0..15, skylight/blocked skylight, smooth light/AO, climate fog/water transparency, biome color blending, underwater/lava distortion. Real clouds fast/fancy, world border shader, portal animation, End sky/flash, beacons, item enchant glint, entity outlines and glowing effect, damage flashes, particles, falling leaves and shelf-mushroom/straw-bed effects. Exact version's brightness mapping matters: 26.1 rewrote brightness sampling and 26.3 uses order-independent transparency to address glass/water layers.
- **Entity and held items:** correct face culling and transparency, 3D display transforms, block/item icons with lighting, armor trim overlays, dyed leather, wolf armor and saddle rendering, mounts and passengers, nametags, scoreboards and text sprites. Never use cube block models for player/animal meshes; use distinct rig/item rigs.
- **Texture packs:** support ordered 26.3 resource pack overlay on the selected installed asset version, font/GUI/sound overrides and animated textures; validate 26.3 pack version. On reload use versioned caches/rebuild only affected atlases/mesh materials, preserve session state; dynamic high-res pack fallback if GPU memory too small.
- **Transparency:** allow Fast sorted, Fancy/refined and (when supported and profiled) a Godot-equivalent of Java 26.3 improved transparency/OIT. Note 26.3's new OIT is more costly than old sorted transparency; do not claim all pipelines simultaneously "faster". Profile glass-in-water, stained panes, particles, foliage and ice at all settings. If Godot renderer cannot implement exact Java algorithm through supported APIs, use nearest stable approximation with an explicit parity note; never rely on invalid shader features.
- **Render architecture:** 16x16x16 section meshes opaque/cutout/translucent, side culling, greedy face merges ONLY when UV/material/AO/light/state/tint/animation boundaries allow, meshed water surfaces, instance geometry for repeated vegetation when profitable, LOD rings, frustum and occlusion/portal tests where supported, predictive streaming. Render immediate collision/terrain before far chunks. No main-thread mesh work beyond per-frame measured budget.
- **Graphics settings as functions, not toggles:** in addition to section 10, include graphics API selection if an actual 4.7 backend choice can be exposed (restart if required); default Forward+ Vulkan with Compatibility fallback; VSync modes, refresh/resolution/fullscreen/borderless, render/sim distances, shadows, smooth lighting, entity shadows, particles, fog, biome blend, clouds, mipmapping, anisotropy/filter, texture array/pixel-art mode, transparency modes, MSAAs/TAA or actual supported alternatives, brightness/gamma, FOV effects and sprint-FOV control, distortion and damage tilt, view bob, GUI scale and separate debug-GUI scale, render scale/dynamic resolution, FPS limiter, idle/unfocused FPS, persistent presets and adaptive quality toggle.
- **26.3 UI/input changes:** no obsolete raw-input toggle (Java 26.3 removed it); relative mouse control while playing, physical-key rebindings independent of keyboard layout, borderless fullscreen default, exclusive option where supported, minimum readable window 320x240, `F3+X` improved transparency toggle if implemented, `F3+F6` separate debug scale options, current refresh rate and player speed per tick in debug overlay; include World Options General/Multiplayer menu replacing older Open to LAN placement. Optionally match macOS Control+click emulation and Quit Shortcuts where relevant; not Windows mandatory. Update map icon direction and Creative inventory tab ordering for the 26.3 target.

**Performance matrix:** capture at least two hardware tiers with a reference target machine if available, 720p/1080p/1440p, 8/12/16/24 render distance, 4/6/10 simulation distance, underground caves, plains, huge jungle, dense village, redstone farm, large chest storage, many livestock, Nether lava and End dragon, flying at high speed and teleports. Report 1% low, 99th percentile frame time, mean FPS, chunk generation latency, draw calls, triangles, RAM, estimated VRAM, TPS, light propagation cost, save latency and spikes. Compare default Java 26.3 on SAME machine/settings/world only where licensed reference can be run. Faster than Java is a goal, **never a blanket promise**.

## 28. Full functional UI, inventory UX, controls, chat and accessibility

**Screen inventory:** startup/asset import and repair, title (Singleplayer, Multiplayer, custom LAN, Options, Credits, Quit), world select/create/customize, settings category trees, language/resource packs, achievements/advancements/stats, loading/progress, world pause/options, survival inventory and armor/offhand grid, creative inventory all tabs/search/hotbar storage, recipe book, crafting table, all furnace variants, smoker/blast furnace/brewing, smithing/stonecutter/grindstone/loom/cartography/anvil, beacon, enchanting, villager trade, chest/barrel/double chest/trapped/ender chest/shulker, hopper/crafter/dispenser/dropper, lectern/book pages, sign editor front/back, banners/maps, horse/mount/nautilus inventories, command block if enabled, game rule search/filter, server/connection list, online restrictions/LAN settings, chat/command autocompletion, subtitles, toasts, death/respawn, Hardcore post-death spectate, End Poem/credits, F3+F6 debug controls, asset failures, crash-safe backup and migrate prompt.

**Shared UI toolkit:** version-appropriate imported GUI sprites (nine-patches, selected slots, sliders, toggles, icons) and fonts, pixel-scaling and nearest texture sampling, responsive keyboard/mouse navigation, gamepad optional, focus traversal and mouse hover, drag and drop stack types, Shift click/double-click/number-key slot swap, scrollbar/recipe search, editable text input with Unicode/IME support, Escape/back navigation and modal focus. Use the player's locally imported art only, not shipped copyrighted branding. Match vanilla proportions/behavior in controlled visual captures (720p, 1080p and 4K) when feasible; don't implement the whole GUI as flattened bitmap.

**HUD:** crosshair and variants, hotbar with active slot and item durability/count, main/offhand held objects, hearts/absorption/hardcore hearts, armor, hunger/saturation feedback, air bubbles, XP bar/level, status icons, mob boss health, raid bar, horse jump, mount health, creative hotbar, attack strength indicator, subtitles, actionbar, chat, scoreboard/team/sidebar, locator bar if present in 26.3, effect overlays, debug overlays, F1 HUD hide, inventory screens never allow world movement unless vanilla does.

**Controls:** actual physical scancode mapping for Java 26.3, WASD movement, Q drop (Ctrl+Q stack), E inventory, mouse left attack/break, right use/place, middle pick block and Ctrl+middle pick entity NBT when permissioned, F offhand, 1..9 slot, Scroll select, Left Shift sneak, Left Ctrl sprint, Space jump, double-tap forward sprint option, Esc pause, T chat, / command, Tab online player list, F3 debug combos, F5 perspective, F1 HUD, F2 screenshot, Ctrl+B narrator equivalent only if supported, toggle/hold sneak/sprint, smooth mouse sensitivity/invert Y and raw-input removed as Java 26.3. Rebind every key, detect conflicts and support keys on varied layouts.

**Accessibility:** individual captions/subtitles with directional indicators, GUI scale and independent debug GUI scale, reduced distortion/fog where option allows, nausea toggle, view bob/attack shake/damage tilt, high-contrast text and focus, text-to-speech via OS only when permission/OS available, simplified input and hold/toggle, language loading and translations from locally installed string tables, bidirectional scripts if font supports, color-blind-friendly indicators, reduced particle settings, no flashing-dependent gameplay cues, joystick/deadzones where implemented, mute and individual category sliders.

**Settings confirmation:** every slider/button must visibly change its appropriate world or renderer subsystem, persist and restore, never overwrite existing manual values when changing unrelated options, validate ranges, migration-safe load and Reset/Cancel/Apply behavior. Add an automated menu crawler that clicks EVERY navigable button in a clean world and asserts no dead buttons or infinite loops. Unavailable capabilities are disabled with explanatory text, not pretend working options.

## 29. Multiplayer, LAN, dedicated server, chat, remote entities and permissions

**Full Java-like multiplayer is an end-state requirement**, but implement the safest practical independent protocol first. Do NOT impersonate Mojang/Microsoft sign-in, claim official Realms connectivity, or assert compatibility with vanilla Java servers without real protocol/auth testing. Minecraft's 26.3 vanilla network protocol is not automatically provided by import of `assets`; treat 26.3 server compatibility as a **separate explicitly unverified milestone**, not a hidden promise.

1. **Local authority model:** an in-process single-player server and headless dedicated server share the same simulation code (20 TPS); clients send input/actions, authority validates positions, block reach, drops, inventory transactions, damage, attack cooldown, redstone and chunk edits. Prevent dupes, desync, terrain divergence and common grief/invalid-packet paths. Client prediction/reconciliation for local player and interpolation/extrapolation for remote entities/mobs/vehicles; never trust client-sent item counts or world state.
2. **LAN UX:** discovery on a permitted local subnet, LAN publish/unpublish, port selection and conflict reporting, join by local IP:port, automatic compatible-version and content-hash handshake, max players and whitelist, per-user game mode, world options `Command Access` and `Force Game Mode` per 26.3. Never open public firewall/UPnP ports without explicit approval. Graceful fallback if firewall blocks discovery.
3. **Core session:** players join/drop/reconnect; world/time/weather/chunk/block state sync, compressed chunk streaming, persistent player inventories/ender chest/stats/advancements, per-player respawn/bed, private player settings and names, remote skin/armor/animation rendering (assets imported/user-selected), remote projectiles/mount passenger attachments, chat messages/signs/book text, death and respawn, permission levels, server list and ping.
4. **Gameplay parity:** player-vs-player on/off, friendly fire/teams, shared or per-player rules where appropriate, all multiplayer container GUIs atomic, hoppers/redstone and block tick server-owned, entity collision and hit registration, shared boss fight/raid, sleeping percentage and day skip, nether/end portals, chunk tickets, game tick time correction and pause behavior (single player pauses where expected; multiplayer does not stop simulation).
5. **Chat and social:** chat log, command console, player tab list, motd/ping/status, local mute/block/ignore, username display and scoreboard teams, message history, text formatting from a safe parser, profanity controls optional and off by default. 26.2 introduced a first-party Friends List tied to official services; do not pretend our independent clone can use that service. Offer distinct local recent-servers/friends bookmarks without official account login.
6. **Security/privacy:** network parsing and length caps, rate-limit packets/commands, message bounds/UTF handling, no arbitrary filesystem access via network actions, robust malicious NBT/JSON depth limits, world backup before imports, predictable disconnection behavior, no auto-public server. Explicit permission for any cloud services. **No code that performs credential theft or bypasses vendor account ownership.**
7. **Vanilla Java protocol compatibility:** optional advanced milestone AFTER native multiplayer is stable; if attempted, version-lock 26.3 protocol/data version, packet states/handshake, encryption/compression, registry remapping, auth rules, entity metadata/components, chat/signature behavior, dimension travel and server login. This is a major standalone project. Do not label Java-compatible unless cross-tested against legal owned 26.3 clients/servers. An independent network protocol is still valuable but is NOT 1:1 Java networking parity.

**Multiplayer tests:** two clients on same LAN, two-way chunk edits, distant portals, double chest concurrent edits, flying Creative vs Survival, Adventure restrictions, Hardcore death, simultaneous redstone, thousands of item entities, chat and commands, player reconnect, server crash/restart/save, network loss/jitter 50..200 ms, bandwidth cap and join near complex structure. Report **latency, packets/s, bytes/s, server TPS, desync** and CPU memory under player load. A UI button labelled "Multiplayer" is not implemented unless at least LAN session works.

## 30. Commands, datapacks, world editing, scripts and diagnostic APIs

- Build a typed command parser with Java-like syntax, selectors `@p/@a/@e/@s`, dimension selectors, coordinate forms `~` and `^`, ranges and entity/data predicates, permissions, command completion and in-game feedback. No shell execution, no raw filesystem access through chat. Implement `/help`, `/gamemode`, `/defaultgamemode`, `/difficulty`, `/gamerule`, `/time`, `/weather`, `/seed`, `/tp`/`teleport`, `/summon`, `/give`, `/clear`, `/item`, `/enchant`, `/effect`, `/experience`, `/advancement`, `/locate`, `/fill`, `/fillbiome`, `/clone`, `/setblock`, `/place`, `/data`, `/loot`, `/execute`, `/function`, `/scoreboard`, `/team`, `/tag`, `/bossbar`, `/worldborder`, `/spreadplayers`, `/spawnpoint`, `/setworldspawn`, `/kill`, `/damage`, `/ride`, `/spectate`, `/particle`, `/playsound`, `/stopsound`, `/title`, `/tellraw`, `/say`, `/tell`, `/msg`, `/me`, `/list`, `/save-all`, `/save-off`, `/save-on`, `/publish`/`unpublish` (where version supported), `/tick` and other 26.3 command IDs from the authoritative local version's command tree. Mark unsupported grammar explicitly; do not claim full command parity if only a subset works.
- **Command blocks/structure blocks:** world-change commands in correct order/timing, chained/repeating/impulse modes, conditional execution and tracking, command access gated by gamerule/op status, structure save/load/mirror/rotate without proprietary template distribution, debug output. `/execute` modifiers and target selectors are essential for adventure maps; support more than one trivial command.
- **Data packs:** version-locked 26.3 pack format and `pack.mcmeta`, JSON registry/recipes/loot/advancements/tags/biome/feature/structures/dimension/attributes/functions/world presets where actually supported, layered overrides, namespace order, validation errors with paths/line info, reload safely only at data boundary. Warn if a pack requires unsupported custom code. No untrusted scripts with OS privileges.
- **Custom worlds:** externally supplied or hand-written JSON generator presets only when validated against selected target schema; allow custom biome tags, flat layers, placed features, drops, potion recipes and sound events where data driven. Invalid pack -> precise error and safe recovery.
- **Scoreboard/advancements/stats:** objective triggers, read-only counters, scoreboard display, trigger commands, function scheduler, advancement grants/revokes and criteria; per-player and world save. Required for command block maps.
- **Debug tooling:** F3 coordinates/dimension/biome/light/chunk/cache/seed/profile/TPS/FPS/1% lows/VRAM estimate/queues/palette bytes/visible sections/occlusion/triangles, seed parity overlay, climate 6D values, sampling noise and aquifers, entity collision shapes/path route, blockstate/target, sound event monitor, network packet graph, FPS profiler, content unsupported-ID browser, generator reference hashes, screenshot export, diagnostic log pack with no proprietary content.
- **Creative builder tools:** copy/paste bounded region in-project, schematic-like internal clipboard (clearly non-vanilla convenience), command functionality `/fill` `/clone` `/setblock`, block picker/search, flying camera bookmarks, debug mode registry showcase, versioned import/export of own worlds. Treat non-vanilla enhancements as opt-in so 1:1 baseline behavior remains unchanged.

## 31. Save format, migration, Minecraft world import (optional), offline first-run assets

- **Private local asset rule:** scan launcher install for exact selected Java 26.3 version; client `.jar` has block/item/entity textures, GUI, model JSON, particle/fonts, while downloaded `assets/indexes` + `assets/objects` provide sound/music files. Support launcher's custom instance `gameDir`, Windows `%APPDATA%/.minecraft`, Linux/macOS paths, local versions, asset hash/size validation and missing file diagnostics. Never assume a custom launcher keeps paths in `%APPDATA%`. Asset import cache must not be in exported game build or Git.
- **Registry/code reality:** most entity rig definitions and complex behavior are Java-coded, not asset JSON. The importer imports raw data/models/textures/sounds, while original GDScript implements rigs, animation, AI and rules. Do not claim complete native entity model import solely because entity textures exist.
- **World data:** per dimension/region/section palette-compressed block states + biome samples, authored overlays/modified chunks, block entities/containers, all entities and variants, map data, raids/trial/warden/dragon/boss states, advancements/stats/recipes, player pos/rotation/health/saturation/XP/effects/inventory/ender chest/bed, time/weather/moon, gamerules/world options, spectator/hardcore status, portal links, scheduled updates including redstone/fluid, light or reliable relight checksum, active chunk tickets, generator fingerprint and asset registry version.
- **Crash safety:** write-ahead journal or copy-on-write checkpoint, temp + atomic rename when supported, bounded write delay, auto backups, failed-write warnings, world-level lock, disk-full recovery, stale lock recovery after crash, migration on copy, restart exactly where player last saved without item dupes/rollback of critical actions; robust corruption detection and partial recovery options.
- **Infinite/unbounded world:** global signed 64-bit coordinates, floor-div/mod, streaming disk unload, floating visual origin, no global world array, deterministic regenerate untouched chunks, visible world border controls, explicit practical bounds of coordinate/storage capabilities. Never claim literally infinite world with finite RAM or 64-bit coordinate range.
- **Minecraft Anvil/NBT import/export** is optional only after native saves are stable, and must be explicit opt-in. Import legally possessed local `level.dat` + region files from a selected world folder in READ-ONLY mode, create an independent copy, version-check NBT compression/palettes/biome IDs/heightmaps/entities/poi/data components for 1.18.2 vs 26.3, warn on unsupported features, preserve original bytes untouched. Export Minecraft-readable worlds only after extensive tests; do not promise a Java-compatible native save without correct NBT/DataFixer migrations.
- **World upgradability:** 1.18.2 vs 26.3 world profiles and hybrid preserve their origin; changing content pack/biome registry later does not mutate old terrain randomly. Explicit migration/retrogen preview, backups and irreversible warning. Never save a hybrid world as unmodified vanilla 1.18.2.

## 32. Optimization beyond the original 45 rules: prioritize measured stability

**Non-negotiable engine architecture:** all gameplay in typed GDScript 4.7.2; no C#/GDExtension/C++/Rust in the runtime under current user constraint. If a proposed optimization requires those, document it as **not permitted** rather than silently adding an extension. Use Godot native `RenderingServer`/`PhysicsServer3D` and render APIs only when thread-safe and objectively faster than many Node instances; keep Node tree small. No assumptions that Vulkan compute or low-level GPU features are available on every target hardware.

### 32A. Worldgen and scheduling

- Per-frame adaptive work queue with priorities: immediate collision + player chunk > changed block geometry/light > near visible generation > neighbor mesh halo > far visible LOD > speculative prefetch > disk maintenance. Avoid starvation with priority aging and cancellation.
- Deterministic per-cell cache and vectorized PackedFloat32Array/PackedInt32Array noise buffers, domain-level climate cache, density sampling only where necessary, column-level solid/air rejection, near-surface conservative sampling, noise polynomial/SIMD opportunities only where GDScript/Godot actually supports, transparent version-specific float precision. Cache results with version/seed/world-coord keys and correct invalidation.
- Partition chunk tasks into lightweight stages with small immutable input/output buffers. CPU worker threads may generate pure arrays, decompress, parse JSON, compute mesh arrays; **must not** mutate live Nodes/SceneTree/materials/render textures unsafely. Main-thread bounded commit and collision-server synchronization. Batch too-small jobs to amortize scheduling overhead; cap workers based on hardware and UI-thread headroom.
- Structure regional planning to avoid jigsaw recursion/chunk circular waits. Snapshot references to neighboring sections; no blocking waits on adjacent chunk main loop. Debounce dirty section redraws and relights; ensure rapid block placement does not remesh identical section 20 times per tick.
- Fast travel with generation epoch cancellation, chunk memory soft/hard caps, visible fallback sky/fog/LOD, staged mesh upload and collision priming. Player never falls through missing collisions; if necessary briefly delay movement into ungenerated columns rather than teleport into void.

### 32B. Mesh/render memory

- Palette-bits block states, optional RLE, homogeneous air/solid section special cases, compressed disk chunks; reuse one material/texture pool, no per-face material creation. Do not make a separate Area3D/CollisionShape for each voxel; combine physical solids by section or local slab decomposition.
- Submesh classes opaque/cutout/translucent/fluid/animated; correct cache invalidation; greedy only merge same material/tint/vertex light/UV/state; separate overlay rendering for crack stages and enchant glint. Reserve memory/face bounds before building PackedArrays; reuse scratch arrays after workers complete. Avoid reallocating 16^3 arrays each frame.
- Frustum cull sections and grouped entities, software/engine occlusion if available and measured, LOD with consistent silhouette/no visible popping/neighbor skirts or seam stitching, fog hides far transitions, only near dynamic light recalculation. Lower render scale changes 3D only; keep UI full resolution.
- GPU performance options: batch instancing repeated vegetation, multi-mesh dense decor where dynamic updates compatible, shader feature flags per preset instead of many materials, shadow cascades distance/cost control, particle budgets, texture array vs atlas based on measured GPU and mip bleed, no forced expensive OIT on Low preset. Show VRAM budget and warn for high-res packs.

### 32C. AI, audio, physics, networking and frame pacing

- Hierarchical mob update: all important logic 20 TPS, expensive sensing/path decisions at lower cached rates where equivalent, animation interpolated independent of TPS, far mobs sleep. Spatial hash/grid for collision/interactions, broadphase near player, path mesh/incremental A* only for relevant route and reactive obstacles, cap navigation nodes per tick, re-use routes, pathfinding regression tests.
- **Audio budget:** loop environmental stems with bounded pools, lazy music decoding, short SFX cache with eviction, cap simultaneous 3D emitters based on priority/distance, offline-subtitle logic independent of playback, no per-frame `AudioStreamOggVorbis.load_from_file` calls, avoid re-reading hashes when looping.
- **Networking:** chunk snapshot delta + varint/palette compression, dirty section and entity transform diffs, interest management and distance culling, bounded packets, rate limit, adaptive interpolation, authoritative reconciling; ensure compression doesn't add extreme latency for tiny inventory events.
- **Profiling harness:** Python standard-lib for offline fixture parsing allowed; game rendering/simulation still GDScript. Repeat benchmark seeds/runs; compare each optimization before/after for FPS, p95/p99 frame time, TPS, RAM/VRAM, chunk throughput. Revert optimizations that corrupt parity or make worst-case stalls worse. Do not choose a theoretically "optimal" structure based on name alone.

**Target budgets are hypotheses**, measured per actual machine; e.g. stable 60+ FPS at 1080p Balanced on a defined mid-tier GPU with 12 render chunks, 20 TPS near the player, no >100ms recurring hitches while moving, no >500 MB unbounded growth after teleporting several thousand chunks, and failure tests on integrated graphics. Never claim stable FPS without benchmarking representative worlds. A full 26.3 feature set might run slower than an incomplete one; compare **equivalent workloads**.

## 33. Release-by-release 26.3 feature-delta checklist (includes pre-2026 core)

These update deltas are NOT an exhaustive substitute for the installed registries, but prevent important recent mechanics getting lost:

| Release | Mandatory systems to include |
|---|---|
| Minecraft through 1.18.2 | Overworld height -64..319, revised mountains/caves/climate, Nether/End, survival/combat/farming/transport/redstone/enchants/villagers/raids, structures and bosses, music/jukebox, gamemodes and world types available in that version |
| 1.19 (Wild Update) | Deep Dark/Ancient City/Warden/sculk, mangrove swamp, frogs/tadpoles, allay, boats with chest where relevant |
| 1.20 (Trails & Tales) | Cherry groves, sniffer, archaeology/trail ruins, armor trims, camel, hanging signs, bamboo/cherry wood, chiseled bookshelf |
| 1.21 (Tricky Trials) | Trial chambers, Breeze, bogged, crafter, mace/wind charges, ominous trial events/vaults and loot, new blocks and combat mechanics |
| Later 1.21 2024-2025 | Pale Garden/creaking, resin, armadillo/wolf armor, variant mobs, Happy Ghast, copper age content, equipment, shelves, world/music/UI changes from installed version records |
| 1.21.9 Copper Age | Copper Golem, copper chests, sorting, copper armor/tools/weapons, copper decor, ox/weathering, shelves, mannequin entity where present; sound preview UI |
| 1.21.11 Mounts of Mayhem | Nautilus and Zombie Nautilus, nautilus armor, Camel Husk, Parched, naturally spawned Zombie Horses, tiered spear/charge and Lunge, transport/AI and animations |
| **26.1 Tiny Takeover** | Baby mob models/animations/voices, adult farm sound variants, **Golden Dandelion** age control, craftable name tags, copper trumpet note block; Java lighting behavior update |
| **26.2 Chaos Cubed** | Sulfur Caves 3D biome, Sulfur Cube absorbed-block physics, sulfur/cinnabar sets, Potent Sulfur, sulfur spikes, geysers/gas, new music disc `Bounce`, background tracks `Shores`, `Memories`, `Nightly`, `Home`, `Ebb`, friends list UI distinction, modern graphics choices |
| **26.3 Wilderness Bound** | Dappled Forest, red/orange/yellow poplar leaf variants, fallen poplar trunks, red shrubs, shelf mushrooms, abandoned camps and biome variants, explorer map item family, cushions, disposable straw beds, wool/concrete stairs/slabs (all 16 dyes), new world options UI, spectator portal interaction, updated transparency, map compass icons, debug controls, revised runtime data/worldgen format |
| **26.4 and later** | **EXCLUDED** from 26.3 stable profile unless explicitly turned on as separate experimental or a later verified release. Examples: future ice caves/frostbite/Blub, jukebox chest playlist, and later entity additions are not 26.3 features |

Pay attention to the difference between **version-specific rendering/asset changes** and **data-driven behavior**. Validate any single claimed feature against exact release notes, original data or a controlled local game reference, not an undated community list that may combine Java, Bedrock and upcoming releases.

## 34. AUTONOMOUS Claude Code execution: run, test, resume, do not self-declare victory

**Definition of autonomy:** Start creating the actual Godot project immediately. Don't ask ordinary design or priority questions; this file resolves them. Build/test/repair in iterative slices, continue with the next unchecked requirement, and keep the project playable. It is NOT technically possible to guarantee that any Claude Code session runs forever: the tool can stop due to context, quotas, permissions, time, process crashes or billing. Implement **resume/checkpoint support** so work proceeds across sessions without relying on a single infinite context window or pretending work occurred while the tool was stopped.

**First run commands** (from an empty, dedicated project directory with this file present, PowerShell on Windows):

```powershell
claude --version
claude --permission-mode auto "Read Minecraft_26_3_Godot_4_7_Claude_Code_Master_Prompt.md completely and execute its build plan. Create the real Godot project immediately. Follow its version and legal boundaries. Never stop at a plan. Keep working down the parity matrix while tests pass; when interrupted, persist docs/STATUS.md with the next concrete action."
```

`--permission-mode auto` is documented in current Claude Code and still observes the platform's safety classifier; it is **not** a magical unlimited-execution switch. If `auto` is unavailable in the installed CLI, check `claude --help` and use a supported non-bypass mode, with project-scoped approvals as needed. **Never use `--dangerously-skip-permissions` by default**. Keep OS writes in the user's designated project/cache/owned data paths; avoid external network, destructive edits outside workspace and unauthorized downloads.

**Unattended continuation option:** After it has built and tested the baseline, create and document `tools/autobuild.ps1` in the project as an **optional** local orchestrator. It should invoke `claude -p` and `claude -p --continue` or the version-specific session resume API in controlled cycles, read `docs/STATUS.md` and machine-readable `docs/COVERAGE.json`, tell each session to implement the next tested incomplete slice, and keep concise stdout/stderr logs. Implement a stop marker `docs/BUILD_COMPLETE.json` ONLY when required coverage gates/benchmarks/boot smoke tests pass, **not** when the assistant says "done" in prose. The wrapper must have user-configurable per-run maximum cycles, wall-clock runtime, total/API budget, per-cycle turn budget and no-progress threshold (e.g. stop after 3 consecutive cycles with no verified changed file or test). Stop immediately on quota/auth/permissions errors, suspicious outside-project writes, missing game ownership/source, critical corruption or any test failure that threatens saved data; log exact reason and instructions. Never run an unbounded paid loop or secretly retry forever.

**Each iteration must execute, not narrate:**

```
RECONCILE: read docs/STATUS.md + docs/COVERAGE.json + relevant tests ONLY
SELECT:    highest priority incomplete functional item whose dependency is ready
BUILD:     edit actual .gd/.tscn/.tres/.godot or tests, no fake stubs
VERIFY:    parse/import/headless launch + deterministic unit/integration tests
BENCH:     benchmark when changes affect worldgen/render/AI/audio/network
REPORT:    update machine-readable parity ledger, tests and blockers with file paths
COMMIT:    local git commit ONLY if repository enabled and appropriate
CONTINUE:  next incomplete item; do not ask user routine questions
```

At startup, create a **canonical backlog** `docs/TASKS.json` automatically from the manifest and sections 0-36. Each item has: id, category, version, dependency IDs, acceptance test path, estimated cost, priority, state `queued|active|tested|blocked`, progress fingerprint, and last failure; update incrementally after tests. Do not copy the whole file to the model context; query a small batch of next actions from a script. Tag tasks that are genuinely impossible without external account/permission and continue work elsewhere, but never mark them completed. Record actual coverage percentages; a polished menu does not satisfy missing mobs, and a complete texture importer does not satisfy the Survival loop.

**Token budget discipline:** no long self-reflection/chain-of-thought dumps, file discovery with targeted `rg --files` and small `sed` slices, short status logs, one precise failing test at a time, no gigantic full-code output unless actually saving it to disk, reuse existing helpers, use source-of-truth registries instead of generating one file per block, keep stable codemap in 1-2 KB `docs/ARCHITECTURE.md`. After compaction/restart read 2 KB status plus specific source needed; do not reread the entire 20k+ word spec at every turn. Prompt instructions have precedence over an agent's urge to stop after a flashy prototype. Avoid broad unrequested refactors while a subsystem is incomplete.

**Implementation order with mandatory finish targets:**
1. Valid Godot 4.7.2 project boots, editable scenes and UI render; local asset discovery/import verifies hash, imports all classes including music.
2. Playable seed-based streaming 3D world with near collisions, block place/break, correct persistence, fly/survival and menu; no critical stalls.
3. True, separately versioned 1.18.2 terrain/world generation and 26.3 generator with reference sample parity and full 67 biome registry, plus modern structures.
4. Complete inventory, crafting, GUI, 5 play styles, world presets/gamerules, death/hardcore, animation and audio scheduling.
5. All blocks/items/recipes/loot/enchants/effects/redstone/machines/containers and three dimensions, all structures and progression.
6. All mobs/entity types/variants with appropriate AI/animations/sounds/loot and special release mechanics.
7. Commands, advancement/stats, resource/data packs, multiplayer LAN/dedicated, polished graphics/accessibility, opt-in source-compatible world import if feasible.
8. Full performance/safety/regression/seed parity evaluation; packaging without third-party assets; only emit `BUILD_COMPLETE.json` on verified test coverage, else leave resumable partial status.

**Never ask the user "what next?" or declare terminal completion** while backlog entries remain, except when external authorization/legal/licensing action is genuinely required or processing budget is exhausted. If a required capability cannot be implemented within the tools, record it honestly and keep other tasks progressing. Do not use the absence of a local Java client to invent copyrighted reference assets. Prefer verified real working features over speculative code volume.

## 35. Huge regression and parity test matrix: no pretend 1:1 claim

Implement tests as deterministic Godot GDScript test runner scripts + small Python stdlib parsing tools if necessary. No proprietary assets embedded in distributed fixtures. Focus on *observable gameplay*. A single `--headless --path <project>` parse success is insufficient for graphical/audio/worldgen parity; additionally implement in-game test scenes, manual visual checklists, reference comparison files and automated artifacts where possible.

| Category | Essential acceptance scenarios |
|---|---|
| Boot/import | Clean Windows no Minecraft -> informative fallback; installed 26.3 -> texture AND audio; missing asset index -> clear repair; safe ZIP path traversal rejection; corrupt hash -> warning; reimport idempotent; resource pack ordering; never export source assets |
| Create/load | Named random seed/numeric negative/string; default and legacy generator; Superflat custom layers; Single Biome; Large Biomes/Amplified; structure off; Bonus Chest; Hardcore/Creative; game rules; duplicate folder name; backup/recreate/delete confirmation; save/reload every option |
| Worldgen 1.18.2 | Y=-64..319, sea Y=63, biome 6D points and cave biomes, huge mountains, cheese/noodle/spaghetti caves, underwater caves/aquifers, ore heights, structures and piece rotation, bedrock/deepslate, positive and negative chunk positions, same-seed parity hash against vanilla reference |
| Worldgen 26.3 | Correct climate/surface/density single precision, 67 biome registry incl special Void, Dappled Forest and its trees, sulfur cave/springs/geysers, mineshaft/trial/abandoned camp, proper Nether/End, dimension-specific biomes and fog, versioned material rules; reference seed parity where verified |
| Streaming | Run/walk/fly/elytra/teleport thousands of chunks, change direction, chunk job cancellation, remove/reload edited chunk, neighbor fluid and mesh seams, floating origin far coordinates, no missing collision leading to void, memory bounds after eviction |
| Player physics | Correct walking/sprinting/sneak speed, jump/step slabs, ice/honey/slime friction, ladder/vines/swim/crawl, oxygen/drowning, fall/fire/lava/freeze damage, lava bucket and water flow, hit reach, combat cooldown and armor/status attributes independent of FPS |
| Player animation | Standard/slim skin, first-person hand and offhand, third-person idle/walk/sprint/strafe/sneak/swim/crawl/climb/fly/riding/gliding, mining break overlay, eat/drink, bow/spear/trident/shield/map/spyglass, arm armor trim and skin layers, hurt/death/sleep/sit, 26.1 baby rig variants |
| Modes | Survival honest resource economy, Creative unlimited+flight, Adventure component-gated break/place, Spectator fly through terrain and 26.3 portal interaction, Hardcore one-life world lock; difficulty changes produce correct mobs/damage and persist |
| Inventory/items | All catalog IDs enumerate, each family works, shift-click and drag stack, recipe book, material/armor/weapon tooltips, enchant durability, status effect and potion interaction, unique food effects, buckets/boats/maps, rare drops, crafting leftovers, no item dupe or lost chest contents |
| Crafting/trading | Exact 2x2/3x3 shaped/shapeless, blast/smoker/brewing/stonecutting/smithing/anvil/grindstone/loom/cartography, enchanting/bookshelf effect, villager restock/price, copper golem sorting, crafter, chest/trapped/hopper and automated transfer, GUI resume after save |
| Redstone | Dust decay, gates/power direction and timing, tick ordering, observer, comparator, hopper filter, pistons QC, crafting farms, note blocks, dispensers/rails, edge-of-chunk machines, sculk sensing and wool dampening, survival when saving mid pulse |
| Mobs | Complete living mob roster spawn and behavior, baby variants, AI pathing and despawn rules, tame/ride/breed, variant drops and sounds, villagers/golems/raids/trials, all aquatic/flying, Warden/Creaking/Sulfur Cube, Dragon/Wither boss stages, Nether/End mobs |
| Audio/music | All sound event paths resolve from locally owned cache, menu/world biome-dependent tracks with gaps, Nether/End selection, 26.2 disc `Bounce` and five music tracks, jukebox sound+comparator, copper note trumpet, 3D attenuation/muffle, sound-category sliders independent, 26.3 directional subtitles, pause/restart without audio leak |
| Visuals | Correct texture UV and animation, transparent face sorting/OIT fallback, glass/water/foliage/crops, biome tint/water fog, day/night moon/weather, block and entity AO/shadow, atlas mip bleed, held items, map/GUI sprites, light propagation, no z-fighting at section seams |
| Graphics settings | Every video toggle changes real rendering/resources, saves/restores, invalid combinations greyed out, minimum GUI 320x240, normal 720/1080/1440/4K, full/borderless/window, debug F3/F5, 26.3 F3+X/F3+F6, stable camera and frame pacing at varied distances |
| UI/accessibility | Every button navigable and functional, input focus/IME/keyboard rebind, translated strings, recipe search, map/book/signs, toast/subtitles and sound direction, reduced distortions, chat input/commands, spectator restrictions, no background movement while typing |
| Commands/datapacks | `/give`, `/tp`, `/fill`, `/locate`, `/effect`, `/execute`, selectors, game rules, 26.3 data-pack loading, worldgen custom tags, scoreboard/advancements, command blocks, invalid pack recovery, untrusted JSON bounds and no shell injection |
| Multiplayer | Host/join LAN, simultaneous players, chunk edits/containers and inventory atomic, PvP/damage/respawn, player skins+animations, remote mobs, network loss/rejoin, Chat and World Options, commands roles, server restart, dimension portals, TPS 20 under normal loads |
| Stability/safety | No parser errors, no missing script class, no infinite spin, no on-disk imported proprietary assets in repo/export, no authorization bypass, clean crash logging, autosave temp/atomic rollback, corrupt region recovery and world backup, no loss of owned files |

Add exhaustive **property-based testing** per block/item/biome/recipe ID: all model refs resolve; all tags refer to known IDs; valid state values; every loot output is registered; every recipe's inputs/outputs exist; biome structure tags resolve; all sound events have local objects or reported missing hashes; every clickable UI action has a callback to a genuine implementation. Run tests nightly/on checkpoint if user's environment permits, but do not rely on a future background job without an actual scheduler.

**Golden-test discipline:** maintain source version and seed for every fixture, capture a reproducible mismatch log with coordinates/type/expected/actual and code pointer. A version mismatch is NOT silently patched by hardcoding a handful of seeds: test random unseen seeds, negative coords and boundary regions. Build property tests to detect daylight, weather and random tick results changing when frame rate changes.

**Completion criterion:** software starts, can be legitimately played in all five modes, saves/reloads accurately, actually streams imported audio/graphics where user-owned installed references exist, generates modern and legacy terrain with explicit tested parity, has working content and mechanics for all 26.3 registry IDs and systems in scope, menus genuinely work, LAN/server functions as claimed, published code-only build includes no proprietary assets, benchmarks and visual/sound comparisons demonstrate true performance and correctness. If any category fails, record `NOT COMPLETE` and continue when feasible, rather than implying a 1:1 finished game.

## 36. Primary references, research notes and exact snapshot dates

* **Minecraft 26.3 official full changelog** (2026-09-15, Wilderness Bound): https://www.minecraft.net/en-us/article/minecraft-java-edition-26-3 . This is the canonical 26.3 feature/format/UI change log, including straw beds/cushions/world options/material rules.
* **Minecraft 26.2 official full changelog** (2026-06-16, Chaos Cubed, sulfur and music): https://www.minecraft.net/en-us/article/minecraft-java-edition-26-2 .
* **Minecraft 26.1 official full changelog** (2026-03-24, Tiny Takeover, babies and golden dandelion): https://www.minecraft.net/en-us/article/minecraft-java-edition-26-1 .
* **Minecraft 1.21.11 official full changelog** (2025-12-09, Mounts of Mayhem): https://www.minecraft.net/en-us/article/minecraft-java-edition-1-21-11 .
* **Minecraft Java 1.21.9 official Copper Age notes:** https://feedback.minecraft.net/hc/en-us/articles/39966147272589-Minecraft-Java-Edition-1-21-9-The-Copper-Age .
* **Minecraft Java 1.18 historical release:** https://feedback.minecraft.net/hc/en-us/articles/4415128577293-Minecraft-Java-Edition-1-18 .
* **Minecraft official game-mode distinctions:** https://help.minecraft.net/hc/en-us/articles/360058743992-Minecraft-Differences-Between-Creative-Survival .
* **Godot official stable version archive** (4.7.2 stable 2026-08-18; 4.8 beta as of 2026-11-09): https://godotengine.org/download/archive/ .
* **Godot 4.7 audio streams and runtime import:** https://docs.godotengine.org/en/4.7/classes/class_audiostreamoggvorbis.html and https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html .
* **Godot 4.7 thread-safety:** https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html .
* **Claude Code current CLI** (auto permission mode, `-p`, `--continue`, `--allowedTools`, structured output): https://code.claude.com/docs/en/cli-reference . Verify the *locally installed* version before constructing a PowerShell continuation wrapper; flags may change.
* **Minecraft Wiki technical guides** (SECONDARY, filter versions carefully): https://minecraft.wiki/w/Create_New_World , https://minecraft.wiki/w/Music , https://minecraft.wiki/w/World_generation , https://minecraft.wiki/w/Noise_settings , https://minecraft.wiki/w/Mob , https://minecraft.wiki/w/Commands , https://minecraft.wiki/w/Advancement . These can contain upcoming 26.4 rows; the selected 26.3 install supersedes them.
* **Versioned 26.3 ID lookup for cross-checking, not as final source:** https://mygames.wiki/minecraft and https://endgametools.com/en/minecraft/ids/biomes . Registry totals are not authoritative unless confirmed against selected 26.3 client/reports.
* **Minecraft EULA and use guidelines:** https://www.minecraft.net/en-us/eula and https://www.minecraft.net/en-us/usage-guidelines . The project must be independently implemented; importing assets locally does not grant a right to distribute those assets or represent an unofficial product as official.

**LAST AND MOST IMPORTANT COMMAND TO THE CODING AGENT:** Do not write a design essay. Write and repeatedly test a real Godot project until every testable requirement of this **entire document** is verified or an objectively documented constraint stops execution. Music, animations, biomes, ALL 5 modes, modern 26.3 content, world options, UI, high performance, full mechanics and autonomous resumption are **not** to be skipped. Never substitute "I implemented everything" for passing evidence. End each execution slice with a runnable game and the next concrete, unattended action saved on disk.
