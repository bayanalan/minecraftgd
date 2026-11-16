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
- **Native equality check**: `-- --autoplay --gen=java_26_3 --fresh --seed=12345 --nativecheck=1 [--dchunks=N --fchunks=N --decchunks=N --fonly=x,z --flatcmp=1 --fall=1]`
  (`--flatcmp=1`: features compared against the GDScript flat path with live heightmaps - the default legacy overlay
  path reads pristine heightmaps, so trees placed beside earlier trees (jungle, fancy oak, mangroves) always differ
  there; `--fall=1`: every placed feature compared, first differing writes printed)
- Native library: `powershell -ExecutionPolicy Bypass -File tools/build_native.ps1 -Arch x86_64|arm64|all` (MSVC 14.44; raw GDExtension C API) → `native/bin/recraft_native.<arch>.dll`
- GDScript thread-contention probe: `-- --contention --threads=8`; worldgen thread scaling `-- --bench --mt=4|8 [--clone]`

## OPEN BUGS - remaining (fixed bugs and completed work: fixed.md)
Screenshots: c:\Users\Gerbilicious_Dude\Pictures\Screenshots\Screenshot 2026-11-12 <time>.png
BUG BATCH 2026-11-15 (user list of 26; fix all before stopping - see memory project-bug-batch-2026-11-15):
- [x] Default distances: render 16 / simulation 12 (settings schema 4 moves saved settings once)
- [x] Chat input text 2 GUI px too low (drawn at h - 10; Java EditBox unbordered draws at h - 12; selection / caret / ghost
      text moved with it)
- [x] Creative search "#text": item tags whose path contains the text ("#ns:path" too), their items in creative order,
      matching tags listed under the item name in dark purple (Java CreativeModeInventoryScreen.updateVisibleTags)
- [x] Rain / snow fell through glass, panes, fences, iron bars...: the weather used the light heightmap (opacity > 0);
      now Java MOTION_BLOCKING (legacy-solid except cobweb / bamboo sapling, or fluid) via Chunk.motion_top (lazy per
      column, reset by block changes) for columns, splashes, the rain-above sound and isRainingAt
- [x] Campfire smoke: Java CampfireBlockEntity.particleTick every tick (11 % chance of 2-3 cosy / signal smoke, y 0..2
      above, quad x3, 80-129 / 280-329 ticks, fade over the last 60, random fixed sprite); animateTick only adds lava
      (1 in 5); every campfire gets its block entity (structures, commands)
- [x] F11 fullscreen on every screen: handled from Window.window_input (before any node: menus / chat / options
      with their own _input used to swallow it), toggles windowed <-> the chosen full-screen mode; automated runs never
      save it (--keytest=1 probe: in game, chat, options all toggle)
- [~] Alt-tab back: "fullscreen" is now Godot's non-exclusive full screen (exclusive D3D12 windows sometimes never
      reactivated; no FPS difference measured), a minimised window is restored and the mouse recaptured on focus in -
      needs an in-game check
- [x] Water in ice glitch (dark water patches / see-through walls on frozen lakes): Java draws water under / beside ice
      (ice is noOcclusion) but sorts translucent quads back to front; TerrainRD drew a group's translucent direction
      buckets in fixed order, so sloped water tops under the ice (bucket "other") and a hole's +-Z water sides came after
      the ice tops, in front of them. Translucent buckets now draw in a camera-side order (above the group: sloped,
      vertical, +Y, -Y; below: +Y, vertical, sloped, -Y). Render-checked (ice sheet over water with holes, 4 views)
- [x] Stained glass / ice / slime / honey icons were opaque bricks of colour: block icons blend translucent block items
      (native icon_raster: texture index + 0.5 = translucent, straight-alpha "over"; GDScript fallback the same)
- [x] Panes "bricks of colour" in hand: flat items with translucent pixels use a blended entity shader variant
      (EntityRenderer.flat_item_material; Java translucent item sheet) in hand / third person / on the ground / in
      frames; translucent block items in hand / dropped / falling use voxel_item_translucent
- [x] Shelves had no icon, the enchanting table icon was its floating book: BERender.item_node only for items whose
      items/<name>.json is minecraft:special (they went through the block-entity renderer: empty shelf, lone book)
- [x] Walls broken in hand: a wall's default state has no geometry, so hand / ground / frame paths fell back to the
      extruded GUI icon turned 45 deg (an edge-on striped sliver). Block items now draw the item's own model
      (EntityRenderer.item_block_mesh: *_inventory models of walls, fences, buttons, shelves; else the default state)
      whenever the item model is a block model. Render-checked (wall in hand, in a frame, dropped)
- [x] Enchanting table book blank: 26.3 moved the texture to entity/enchantment/enchanting_table_book.png
- [x] Lanterns "don't connect": every lantern was placed standing (floating under ceilings). Java LanternBlock
      placement: the vertical nearest looking directions (clicked face's opposite first), hanging=true when the block
      above supports its centre (Block.canSupportCenter; fence gates never), else standing on a centre support, else
      not placed (Interaction.lantern_placement). Breaking the support is Support.can_survive's (support.gd)
- [x] Item frames: a stretched leather box -> Java ItemFrameRenderer: block/(glow_)item_frame(_map) model rotated per
      facing (all 6), the item at 0.4375 turned 45 deg per rotation, half size with its FIXED display (blocks 3D),
      maps 128 px over the whole face; glow frames light their item fully. /summon item_frame <pos> {Facing,Item,
      ItemRotation} added. Render-checked (wall / floor / ceiling / side frames, sword, block, rotated pane, bow)
- [x] Floating top half of a door after breaking the block under it / torches staying when the block behind them goes /
      "every supported block must break": scripts/world/support.gd (Java canSurvive + updateShape). Every notified
      set_block hands its 6 neighbours with a rule (byte per block id, no scans) to Support; the rule re-checks only the
      side Java reads (torches / signs / plates / candles below, wall torches / ladders / hooks / wall signs / banners /
      coral fans / amethyst behind, buttons / levers / lanterns / bells their attachment, cocoa its log; dust, diodes,
      rails, plants, carpets, snow any side) and a failed block goes like Level.destroyBlock: loot without tool / entity,
      break particles + sound, its water stays. Doors / tall plants / beds: the half left alone is destroyed with drops
      (one item from the loot tables; creative breaks drop nothing - preventDropFromBottomPart). Vines / glow lichen lose
      faces first; sugar cane, cactus, bamboo, chorus, kelp / weeping / twisting / cave vines, pale hanging moss,
      dripstone (stalactites fall) and scaffolding (distance 0-7, falls / breaks at 7) use 1-2 tick scheduled ticks like
      Java. Face support = Java isFaceSturdy FULL / CENTER / RIGID rasterised from collision shapes (leaves give none,
      soul sand / mud full, snow by layers). Placement uses the same rules (StandingAndWallBlockItem wall / standing
      fallback along the nearest looking directions, buttons / levers every face, ladders / hooks / cocoa / vines /
      lichen / bells / dripstone / wall hanging signs, doors + tall plants need a replaceable block above, crops light 8).
      Loot fixes found on the way: 26.3 "match_block" condition was never evaluated (both door halves rolled a door, crops
      at age 0 dropped wheat, snow always 1 snowball), location_check (tall grass halves), wall torches / signs / banners
      / heads / coral wall fans have no 26.3 table (dropsLike: standing form - they dropped nothing), requiresCorrectTool
      only for players (a lantern losing its ceiling drops). 20 tests + render check (door / torches / lantern / ladders
      popped with their items, no floating halves)
- [x] Door / trapdoor / lever click spam and fast Escape: every right-click press now acts at once (Java handleKeybinds:
      clicks ignore rightClickDelay; the 4-tick cooldown dropped clicks), holding repeats every 4 ticks (new: blocks /
      doors repeated nothing before); Escape closes a screen whose LineEdit / TextEdit has focus on the first press
      (WorldManager._input, Java Screen.keyPressed - the LineEdit ate the first Escape) and a sign keeps its text on
      Escape (Java onClose -> onDone)
- [x] Closing a door into the player forced a crawl: Java Player.updatePlayerPose keeps the pose while even the 0.6-tall
      swimming box is blocked (door collision itself = Java DoorBlock 3 px shapes, already tested); test added
- [x] Snow layers stack like Java (SnowLayerBlock.canBeReplaced): a snow item on a layer's top face, or on a face in
      front of a layer, adds a layer up to 8 (then a new layer above); other blocks replace only a single layer
      (wiki Snow), entity / player obstruction checked
- [x] Water on snow layers: vanilla drops NOTHING (wiki Snow: "breaks and drops nothing if water or lava flows into its
      space"; 26.3 loot snow.json needs an entity) - water now washes layers away dropless; a shovel still gives one
      snowball per layer; explosions drop (own context)
- [x] Redstone dust placed on dust "breaks instantly": placement is refused where dust cannot survive (Support K_WIRE ->
      RedstoneWire.can_survive_on: a sturdy top or a hopper; not dust, leaves, bottom slabs, fences, bottom trapdoors,
      air). RedstoneWire's sturdy-face checks (survival, placement, the UP connection) now read Support's per-state
      isFaceSturdy table (leaves give no support, as Java), so dust and Support agree; dust on a block a piston pushes
      away pops (Support on the moved cells). Tested (stone / glass / glowstone / soul sand / top slab / upside-down
      stairs / hopper ok) + render-checked (dust on leaves pops, climbing dust lights a lamp)
- [x] Levers didn't open doors: 26.3 door / trapdoor / fence gate blockstates carry no "powered" (no model reads it), so
      redstone never saw them. The registry now adds Java's POWERED; doors read both halves' neighbours and switch
      both halves (Java DoorBlock), trapdoors / gates open + close with power, a hand-closed powered door stays closed,
      placement next to power comes open (getStateForPlacement), sounds per set (wooden / cherry / bamboo / nether wood /
      iron / copper doors, trapdoors, gates; volume 1, pitch 0.9-1.0 - hand toggles too)
- [x] Redstone like vanilla (Redstone rewrite, wiki Redstone mechanics + component pages): Java weak / strong power per
      component (levers / buttons strong into their block, plates / detector rails / lecterns / trapped chests / sculk
      sensors down, torches up and never into their own block, rods / hooks behind, diodes / observers their output,
      redstone blocks / daylight detectors / targets / jukeboxes weak only) and conductors per wiki Conductivity (glass,
      glowstone, sea lanterns, leaves, ice, honey, TNT, redstone blocks, observers, pistons, beacons, spawners, copper
      bulbs / grates don't conduct; soul sand / mud do); dust ignores dust while computing (weakly powered blocks power
      lamps, not dust); a lever on a block now powers dust 2 blocks away (updates reach 2); repeaters extend short pulses
      to their delay, lock only from diodes; comparators keep their output for 2 ticks, take any source as side input;
      torches read only their own block (a torch on a redstone block is off); quasi-connectivity for pistons / dispensers
      / droppers; copper bulbs toggle per pulse (were inert); trapped chests output their viewers; shelves react;
      BlockUpdates support ticks no longer run components early (a neighbour change released buttons / cut repeater
      delays: Redstone.schedule_tick remembers each component's own tick); more blocks break when pushed (pumpkins,
      melons, leaves, cactus, cake, carpets, repeaters, ladders, heads ...). 80+ tests (scenes/tests/redstone_tests.gd: every source, strong / weak
      matrix, dust, repeater delays 1-4 / extension / lock, comparator compare / subtract / container / through-block,
      observer pulse, torch inversion + burnout, buttons 20 / 30, doors / trapdoors / gates, QC, hoppers, note blocks,
      TNT, bulbs, rails, pistons); render-checked (lever + dust lamp, torch not powering its block, doors opened by levers)
- [x] Piston pushing not smooth: Pistons (Java PistonMovingBlockEntity): block events after the tick's scheduled ticks,
      moved blocks sit in moving_piston cells for 2 ticks (progress 0.5 / tick, solid at the start of the 3rd), drawn by
      one node each at the partial-tick position (head SHORT for the first / last half, retracting base shows the head
      sliding in), kept until the terrain mesh shows the result; entities in the way are pushed (slime launches 1 / tick),
      a pulse ending mid-push makes a sticky piston drop its block, moving cells survive save / reload (block entity +
      scheduled tick; saves finish moves first). Nothing runs while nothing moves. Render-checked mid-move
      (--pistonhold=0.5 probe: push east, sticky push up) and after
- [x] Extended piston = two blocks: breaking the head breaks the piston (drops it; creative: no drop), breaking the base
      removes the head, a head without its piston can't stay, the head never drops (Java PistonHeadBlock)
MERGED LIST 2026-11-14 (PROGRESS + own findings + every open GitHub issue; work top to bottom, don't stop until empty):
- [x] Redstone dust like Java (user 2026-11-15: "needs to connect and have an on/off state proper"): dust shapes were never
      computed (default state had every side "up") -> RedstoneWire (Java RedStoneWireBlock): side / up / none per side on
      placement and every neighbour change (incl. dust one above / below), lone dust = cross, one neighbour = line,
      right-click cross <-> dot, connects to sources / repeaters along their axis / observer backs; power follows Java
      (a conductive block above cuts the climb, non-conductive blocks pass power up but never down); dust powers the
      block below and only the blocks it points into (a passing line no longer lights lamps beside it); one colour per
      power level (wiki Block colors, Redstone tints JE: #4C0000 .. #FF3200; all levels had shared one tint). 14 tests;
      render-checked (lever line with a bend climbing a block into a lit lamp, dark unpowered line, dark lone cross).
- [~] PERF + RAIN + CHUNK GEN (user 2026-11-14: x86 400-500 / 1 % 100-150, arm64 800 / 1 % 200-300 at RD16 / SD12, no
      cost for rain / snow, instant chunk gen). Done so far (2026-11-15):
      - Rain / snow: particles rebuilt once per tick and interpolated on the GPU (global mc_partial / mc_ticks; Java
        also adds particles at the next tick) instead of a 600-particle GDScript loop every frame; rain splashes are
        spawn records evaluated in closed form on the GPU (shaders/rain_splash.gdshader: Java WaterDropParticle flight,
        landing, 50 % ground removal) - zero CPU per live splash, tries spread over the frames before their tick, spawned
        on the block's collision top / fluid surface (Java) with Java's quad size and random sprite; weather columns in
        world-aligned 4 x 4 tiles (Godot culls tiles off screen), only the texture repeats the tile's tallest column
        crosses, per-frame values (span, alpha, scroll, partial tick) in the shader, column data rebuilt only on change
        (enter / camera level / set_block / 1 s round robin). Static views: rain 262 -> 335 fps vs clear 359 (was 404 ->
        262), rain 1 % low 144.
      - Block change listeners: Interest (per-section palette bits) skips observer / redstone / coral scans when none of
        those blocks are within 2 (every water flow step did ~60 lookups); Redstone.request gated the same way (block
        entity writes of loading structures queued 256 full scans per tick: 29 ms frames on x86).
      - Items: Java ItemEntity movement (still items move every 4th tick, item friction x 0.98, water / lava rise 5e-4),
        merge candidates from a per-tick cell grid (was a scan of every entity per moving item); collision caches keyed
        by per-chunk block versions (a global epoch made every cache miss while flying); faster gather.
      - Mobs: light / hurt instance uniforms only on change (the rig was walked every frame), armour key by hash.
      - Chunk gen: boosted workers (10) + 40 % main-thread dispatch / upload share until the render distance is shown
        once (and when 3+ rings behind); it used to drop to 5 workers after the loading screen. Ring 16 visible 14.0 ->
        7.9 s (load test, RD16, 1369 chunks); more workers or budget measured no faster (native noise 13.6 ms/chunk +
        structures now dominate). Update-slot waiters (relights) wake nearest-first.
      - Later the same day: Redstone requests skip air / water / lava changes (inert: no power or wire change; a water
        step next to an ancient-city wire network re-solved the whole network, 20 ms), Interest bits shared with the
        villager agent (a bit collision made water count as lightning rods: hundreds of fake rod entries per chunk -
        fixed, and stale rod entries are dropped on load), precipitation column search on the palettes, chunk collision
        versions only bump for colliding blocks (water flow no longer invalidates item / mob collision caches),
        dispatch walk keeps its frontier across 1-chunk moves (no 1400-entry walk per chunk crossing) and idle entries
        remember their centre (no 750 erases per crossing), random-tick list rebuild resumable mid-row, adaptive entity
        and random-tick-handler budgets (sized from the measured cost and the frames left; whole passes landed in one
        frame on x86), first sampling slice sized by frame time, entity raycast distance prefilter.
      - Bench now (quiet machine, RD16 / SD12, 2880x1800): arm64 flight F 451 / 1 % 143 / 0.1 % 73 (GPU 1.85 ms);
        x86_64 static A 364 / 172 / 121 (was 248 / 43), A rain 328 / 130 / 93, play P 279-307 / 95-103 / 46-54,
        flight F 334-371 / 66-80 / 21-42. Chunk gen: ring 16 visible 14.0 -> 7.9 s.
      - FINAL 2026-11-15 (all agents done, quiet machine, RD16 / SD12, 2880x1800): arm64 F 444 / 1 % 155 / 0.1 % 85
        (GPU 1.94 ms), A 377 / 191 / 127, A rain 339 / 162 / 104, snowy plains A 453 / 186 vs snowing 364 / 142, P 320 /
        112 / 52; x86_64 F 314 / 73 / 34, A 341 / 148 / 101, A rain 320 / 118 / 55, P 265 / 82 / 41 (P worlds hold ~370
        dropped items: leaf litter / moss carpets washed away by worldgen springs - Java behaviour, see Fluid items).
        Load test ring 16 visible at 7.7 s (was 14.0). --nativecheck all equal except first_free_height (pre-existing).
      Open / limits: arm64 is GPU-bound at native 2880x1800 (terrain + sky + water + clouds 1.3-1.6 ms, Godot Forward+
      tonemap 0.38 + canvas 0.19 + prepass 0.08 + opaque 0.05): 800 fps (1.25 ms) is below the terrain pass alone;
      ~450-500 is the ceiling without fewer pixels or a full-frame RD renderer replacing Godot's 3D pipeline. x86_64:
      48 of 53 slow frames in a traced flight are memory stalls (thousands of page faults in a frame, heap decommit /
      recommit while workers churn chunk buffers; probes 50-150x slower), not game logic; the rest are tick work.
      Ideas not done: GPU Hi-Z occlusion culling for TerrainRD (<= ~0.2-0.4 ms), reusable worker buffers to cut page
      faults, native item physics.
- [x] Waterlogging + flow stutter (2026-11-15): a water bucket on a waterloggable block now waterlogs it (it went
      through block placement: water beside it, bucket eaten); BucketItem.use rules (clicked container first, sneak =
      beside per MC-173730, already-waterlogged blocks take it (22w45a), double slabs / lava never, creative keeps the
      bucket), empty bucket picks water out of waterlogged blocks (also aimed at open water), dispensers waterlog / pick
      up, lit campfires / candles go out. The registry lacked `waterlogged` on campfires, amethyst, sculk, light, barrier,
      mangrove roots / propagules, coral wall fans, copper bars / golem statues, resin clumps, dried ghasts (and gave it
      wrongly to fence gates, candle cakes, jack o'lanterns, sea lanterns); mangrove roots had no collision. Flow cadence:
      a tick's sliced updates schedule from their own tick (the front frayed over consecutive ticks), a step's chunks
      remesh together after its last slice, relight -> remesh without a second throttle, flows skip edit batches, near
      updates before far backlogs; fluid ticks ~4x cheaper (per-state tables, SpreadContext grid, slope distances in one
      pass checked against Java's DFS). Probe `--autoplay --cam=8,120,8 --camwait=1 --fluidtest=1`: every step on screen
      +20..34 ms after its tick, 250 ms apart (was +55..321 ms, 234..401 ms). Open: occasional ~100 ms remesh wait
      from the 2 update-job slots shared by the 9 relights of each flow step
  - [x] Fluid items (2026-11-15, tests in test_vanilla_fluid_items): sponges (Sponges, wiki Sponge: on placement and
        any neighbour change via BlockUpdates.fluids_changed, water up to 6 blocks taxicab, at most 118 - the wiki's
        current numbers, not the old 7 / 65 - through water only, nearest first; waterlogged blocks dried, bubble columns
        removed, kelp / seagrass broken with drops; -> wet sponge + block.sponge.absorb; a wet sponge placed where water
        evaporates dries with block.wet_sponge.dries + cloud puff; furnace-dried wet sponge fills a bucket in the fuel
        slot); wet sponge drip particles (Java WetSpongeBlock.animateTick: random side / bottom, no rate on the wiki) and
        leaf drips in rain (LeavesBlock: 1 in 15 per animate hit, not on the wiki) with Java's hanging -> falling ->
        splash water drip (Particles dripping_water / falling_water). Bucket of aquatic mob (MobBuckets, wiki): a water
        bucket scoops cod / salmon / tropical fish / pufferfish / axolotl / tadpole (Health, Age, plain data / variant,
        custom name kept; wiki fill / empty sounds; filled_bucket advancements), using it or a dispenser places water
        (none in the Nether) and releases the mob, persistent. Flowing water / lava now replace every non-solid block
        (Java canHoldAnyFluid = not blocksMotion = !isSolid: carpets incl. moss carpets, heads, flower pots, repeaters,
        snow layers, end rods, cocoa, turtle eggs ...); banners and pressure plates hold fluids back (wiki Banner /
        Pressure Plate); heads got their Java skull collision (they used the default 14/16 box). Grass / mycelium decay
        and spread use Java canBeGrass (dies under full opaque blocks, bottom slabs / stairs / snow layers >= 2 /
        farmland ..., a full fluid; one snow layer keeps it) (RandomTickable.grass_ok). Worldgen mangroves: Java
        MangroveRootPlacer (trunk 1-3 up, root paths per side, muddy roots in mud, waterlogged roots in water, moss
        carpets above) + UpwardsBranchingTrunkPlacer (was the forking approximation, no roots at all) + Java
        RandomSpreadFoliagePlacer offsets (nextInt(r) - nextInt(r); also azaleas), GDScript Trees + native featx.
        Load census (seed 12345, 60 s): snowy_plains 45 item entities (sticks / poplar saplings from leaf decay, 5 sugar
        cane, 2 gravel - none from these changes); default spawn 370 = 253 before this change (leaf litter 1180 items
        from one spring at ~114,98,-243, glow berries) + 117 moss carpets washed by lush-cave aquifer water - Java
        behaviour (wiki Water: carpets wash away). Our worldgen ticks (fluid_exposed: water with air beside / below)
        are a subset of Java's (Aquifer.shouldScheduleFluidUpdate marks every fluid cell near an aquifer boundary,
        similarity >= -0.76, which in Java also spreads into carpets beside water with no air): not over-eager
- [~] GH#14 Sky / clouds checked against 26.3: fancy clouds are 12 x 4 x 12 boxes from clouds.png with Java's face
      shades (0.7 / 1.0 / 0.8 / 0.9) and colour #ccffffff at y 192.33, sky colours / sunrise from the timeline data
      (render probe looks vanilla). The Fast cloud setting (some presets) draws flat clouds like Java. Need the
      specific view that looks wrong
Older open items (below) stay part of the list.
WIKI VALUE AUDIT (user 2026-11-14: "go through the entire game and make sure all values match the wiki"). Every
hardcoded number checked against minecraft.wiki (Java 26.3); baseline snapshot of the code before the audit in the
session scratchpad (baseline_audit). Slices (status):
- [x] Items (done 2026-11-14): chainmail helmet 2, spear damage / speed per tier, on-a-stick durability + stack 1,
      wolf armor 64, banner patterns stack 1, turtle / sniffer eggs 64, netherite knockback resistance, fuel table from
      the wiki (nether wood no longer burns, boats 1200 ...), strict enchantability (shears / shield / elytra not
      enchantable at the table), anvil fixes (prior work 2 x max + 1, incompatibility cost), villager trades loaded from
      the 26.3 trade_set / villager_trade data (2 per level, demand repricing). Follow-ups:
  - [x] Trading drops a 3-6 XP orb at the villager (+5 on a level up) instead of giving the offer's villager XP
  - [x] Player knockback = Java LivingEntity.knockback (0.4, armour knockback resistance, halves motion, rise <= 0.4;
        mob attack_knockback; projectiles push along their flight)
  - [x] Trading.assign after vtype (villager/variant merchant predicates see the biome type); "+1 Knockback
        Resistance" tooltip line (was already there for netherite)
  - [x] Gossip / Hero of the Village discounts: wiki gossip table (trading +4 / 25, minor_negative on attack, major_negative
        for villagers within 16 of a killed one, decay every 20 min), price = cost - floor(m x reputation) - Hero
        max(1, floor(p (0.3 + 0.0625 (h - 1)))) applied while the trade screen is open (Trading.update_special_prices) (test)
  - [x] Cartographer explorer maps, job sites, restock, gossip sharing, curing (2026-11-15, tests): ExplorerMaps -
        exploration_map allocates the map at once and searches the destination tag (Structures.locate on a worker,
        skips starts earlier maps found) - offer out of stock while searching, removed when nothing is found; /locate
        and the maps now search 201 x 201 units of the set's spacing (wiki /locate; was 100 chunks: mansions / monuments
        were often "not found"), nearest-first by a native key sort (10-20 ms per search in the probe);
        map centred on the target at zoom 2 with the land / water preview (#water_on_map_outlines, orange stripes:
        visual match) and the type's decoration; the 26.x *_map items count as maps (Maps.map_id); 2026-11-15: chest loot
        explorer maps (shipwreck / ocean ruin buried treasure maps, abandoned camp maps: exploration_map + the filtered /
        discard modifiers) search async from the chest, a map that found nothing is taken back from the chest / player /
        ground, held pending maps restart their search after a reload (test). Villagers - start
        unemployed (village templates bring nitwit / none), claim the nearest free job site within 48 (provisional
        claim, 60 s, full claim within 2 blocks, green particles), lose an untraded profession with the site / after
        failing to reach it, work 2000-9000 next to the site (work sounds, restock up to twice a day), gather at the
        nearest bell 9000-11000 and share gossip minus the wiki sharing costs; unemployed / nitwit / baby villagers say
        no + head shake. Curing: golden apple + Weakness, 3600-6000 ticks, Strength I, shudder, iron bars / beds speed-up
        (1 % / 9x9x9 / 30 % / max 14), keeps trades / xp / gossip, Nausea 10 s, major 20 + minor 25 positive gossip,
        drops held items, Zombie Doctor trigger. Not on the wiki (marked in code): search / work / gossip intervals,
        meeting-point range, goal speed modifiers. 2026-11-15 (Villagers, tests): beds - every villager claims the nearest
        free #beds bed head within 48 (green particles, POI index now holds bed heads), at rest time (12000 .. 10) walks
        home and sleeps (0.2 hitbox on the pillow, Java sleep pose, bed occupied), wakes at 10 / when hurt / for a bell /
        bed broken / a player using the bed (kicked out), back to bed after 100 ticks; raids (96-block area): no job
        claiming or work, the first villager at the meeting bell rings it before wave 1, then hide at their bed within 32
        (else the nearest bed) and stay, sleepers get up, cheers after a victory; iron golem summoning per the wiki (5
        gossiping / 3 panicking every 5 s, slept within 20 min, no golem seen within 16 for 30 s - scanned every 10 s, 10
        tries in 17 x 13 x 17, the group counts it as seen); sleeping pose / sleep state synced to LAN clients. Open: no
        villager breeding (beds as a requirement), bed claims are not reachability-checked (an unreachable bed is dropped
        after 3 failed paths)
- [x] Player + combat (done 2026-11-14): damage cooldown (bigger hit deals the difference), jar #bypasses_armor /
      #is_fire / protection tags, damage exhaustion only for armor-protected types, sprint-swim 0.02 (3.92 m/s), Depth
      Strider, Dolphin's Grace, Soul Speed, Swift Sneak, sprint rules (blindness, ground-only exhaustion, swim 0.01 / m),
      Haste / Fatigue attack speed, effect stacking (hidden weaker effects), instant effects, Absorption / Health Boost /
      Saturation, void at min_y - 64, Respiration, turtle shell, Fire Protection lava burn time, rain extinguishes,
      golden apple / pufferfish / raw chicken effects, Strength / Weakness damage, sweep damage per target, enchantment
      targets from jar tags. Follow-ups:
  - [x] Contact damage (fire / soul fire + 8 s burning, cactus, magma unless sneaking, lit campfires, berry bush, wither
        rose; Frost Walker immune to #burn_from_stepping), stuck multipliers (cobweb 0.25 / Weaving 0.5, berry bush 0.8,
        powder snow 0.9 / 1.5), powder snow freezing (140 ticks, 1 per 40, leather) + frozen speed -0.05 x fraction,
        frozen hearts, powder snow outline (tests). Mobs in cobwebs / berry bushes still open; Frost Walker frosted ice
  - [x] Crawling pose in 1-block gaps; Soul Speed particles / sounds (done: crawling when neither the 1.8 nor the 1.5 box
        fits - 0.6 tall, eyes 0.4, sneaking speed; Soul Speed soul particle every 5th tick + 35 % particle.soul_escape
        from the 26.3 enchantment data, "soul" particle sprites. 2026-11-15: third-person crawl / swim model pose -
        Java setupRotations (rotX -90, in water -90 - pitch, translate (0, -1, 0.3)), swimAmount 0.09 / tick, swim-stroke
        arms over limbSwing % 26, kicking legs, head -45 degrees (world_manager._update_player_model))
  - [x] Shield bypass list = 26.3 #bypasses_shield
  - [x] Husk Hunger 7 x regional difficulty seconds (entity_manager uses 140 ticks); lava vertical drag 0.8 vs 0.5 (check)
        (done: MobAI.regional_difficulty / clamped_regional from the wiki formula - chunk inhabited time is not tracked
        yet, counts 0; unarmed husks only; mobs in lava 0.5 horizontal / 0.8 vertical, fall distance halved per tick)
- [x] Mob stat tables (done 2026-11-14): attack (zombified piglin 8, brute 13), speeds (fish 0.7, phantom 0.7, vex 0.7,
      zombie nautilus 1.1), follow ranges, knockback resistance, breeding foods from the jar tags, camel husk / sulfur
      cube / happy ghast data, fire immunity, burn flags. Follow-ups (code outside the tables):
  - [x] Easy damage: min(d, d / 2 + 1), not d x 0.5 (entity_manager _tick_mob, mob_ai, raids)
  - [x] Wire new def fields: armor_points (+ horse armor toughness) into _damage, attack_knockback, step_height,
        baby_w / baby_h / baby_speed, fly_speed, follow_range for player targeting (hardcoded 16 / +19) (done: step_height
        in mob physics + MoveControl jumps, baby hitboxes from the defs, baby_speed for every zombie variant, follow
        range picks and drops targets (was 16 / 40); fly_speed goes with the flyer port below)
  - [x] XP: babies 0 (baby zombies x 2.5 = 12, baby hoglin / piglin 5), +1-3 per equipment piece, slime / magma = size
  - [x] Mob armour: natural armor_points, worn pieces, horse armour (+ toughness) reduce attack damage (magma 3 x size)
  - [x] Magma cube damage by size (size + 2), magma armor 3 x size; set_size 0.5202 x 0.52 per size; sulfur cubes
        spawn large (HP 4 x size, 0.49 x size), split into exactly 2, small ones drop no XP and grow up after 20 min
        (2026-11-15: hop speed = the Sulfur Cube infobox speeds 0.4 large / 0.3 small; hop cadence / height are not
        on the wiki - slime's)
  - [x] Piglins: golden sword +damage (RANDOM_WEAPON_MOBS), crossbow piglins shoot (every 2 s, back off; range 8 / 6
        borrowed from the pillager - not on the wiki); 20 % babies (passive, no weapons, never grow up)
  - [x] Villager 0.5 / trader 0.7 speed attributes need per-goal speed modifiers; done: zombie horse speed roll
        0.2135-0.2846, jump strength rolls (horse / skeleton horse / mule 0.4-1.0, zombie horse 0.5-0.7, llama / donkey
        0.5) used by the ridden jump. 2026-11-15: defs speed 0.5 / 0.7 (wiki) + per-goal modifiers stroll_speed /
        panic_speed / hide_speed (the wiki has none: Java's villager walk 0.5, panic / flee 0.75, bell hide 0.625; trader
        stroll 0.35, panic / avoid 0.5) - strolls stay 0.25 / 0.245; villagers flee and traders avoid zombies / illagers /
        vexes / ravagers / zoglins within the wiki Villager panic radii (8-15), threat re-checked every 10 ticks
  - [x] Breeding only between tamed wolves / cats / horses / donkeys / mules / llamas (Java canMate); parrot taming 1/10
  - [x] Heal / tempt-only foods (camel husk rabbit's foot, zombie horse red mushroom, happy ghast snowball, strider
        warped fungus on a stick, nautilus pufferfish taming); neutral-animal AI (nautilus). Done: def "tempt" lists
        (camel husk rabbit's foot, zombie horse red mushroom, strider warped fungus on a stick), red mushroom heals a
        zombie horse 3 (+3 temper untamed, tamed ones refuse horse food), snowballs cut ghastling growth 10 %, nautiluses
        / wolves / llamas fight back. 2026-11-15: happy ghasts follow players holding a snowball (or a harness while
        unharnessed) within 10 blocks, stopping at 5; nautilus: pufferfish / pufferfish bucket tames 1/3, any fish heals 2x
        its nutrition (wiki table), babies grow 10 % per fish, buckets come back as water buckets, tempted by fish within
        10 blocks, swimmers breed (partner within 8) (Taming._nautilus_feed, MobAI._swimmer) (test). 2026-11-15 (Taming,
        test): nautilus / zombie nautilus riding - tamed adults take a saddle and nautilus armor (armour points = the wiki
        table, drawn as shell layers from equipment/nautilus_body / nautilus_saddle; shears take armour then saddle;
        sneak = inventory on the 26.3 nautilus GUI), forward follows the rider's look up to 6.5 m/s (zombie 7.15) in water,
        0.88 / 0.97 on land, jump charges a dash (~12 / 13 blocks, every 2 s, dash bar in place of the XP bar), rider gets
        Breath of the Nautilus (air paused underwater); zombie nautiluses tame with pufferfish and armour stops their
        burning; camels heal 2 from cactus, camel husks from a rabbit's foot (amount not on the wiki: the camel's 2).
        Open: camel husk riding / dash, Free Diver advancement, the riding sound
  - [x] _swimmer / _small_flyer speeds are hand-tuned: port Java fish / vex / phantom movement on the attribute speeds
        (done for vexes: pass through blocks, idle in the 15 x 11 x 15 box around their summon spot, give up beyond 128
        blocks). 2026-11-15 (MobAI): fish = FishMoveControl on movement_speed 0.7 (speed eased 0.125 / tick, 90 degree
        turns, moveRelative 0.01, drag 0.9: 0.07 blocks / tick; panic 1.25, avoid players within 8 at 1.6 / 1.4, random
        swim 1 / 40 per tick); bees / parrots = FlyingAnimal on fly_speed 0.6 / 0.4 (0.02 air factor, drag 0.91: 0.133 /
        0.089 blocks / tick; bee attack x1.4, panic 1.25, parrots drop / land without a target); vex = VexMoveControl
        (0.05 x modifier toward the point, charge 1.0 / wander 0.25, hits when boxes touch - the attribute is unused in
        Java); phantom = PhantomMoveControl (4 degrees / tick, speeds up while lined up) capped at the wiki's 20 blocks
        per second, circle points 15 degrees apart; allay reads fly_speed (tests). The wiki gives none of these
        formulas: Java's, noted in the code
- [x] Mob AI + spawning (done 2026-11-14): difficulty damage min(D, D/2+1) / 1.5 D, per-category mob caps (70 / 10 /
      15 / 5 / 5 / 5 / 20), despawn rules (inactivity counter, fish 64), pack spread +-5, spider light rule, skeleton /
      bogged / pillager ranges + intervals, charged creepers (power 6, lightning), magma / slime damage by size, shulker /
      guardian / phantom / ghast / enderman / wither timings, anger timeouts, zombified piglin group box, teleports,
      baby zombies, horse foods / foal growth, wolf healing, raids (omen 600, patrols, bonus wave, hero), trial spawner
      LOS + no despawn, spawner box 9 x 9 x 9, shrieker / warden / sonic boom timings, golem pattern. Follow-ups:
  - [x] Projectile damage from mobs scaled by difficulty (explosions already)
  - [x] Phantom attack 6 vs wiki 2 / 3 (Hard); vex attack double-count check; ravager speed 0.4 vs 0.3 (verify) (done:
        phantom 2 per its infobox; vex 9 already includes the sword - attack_bonus skips vexes, no double count; ravager
        0.3 per the Attribute table, the Ravager infobox 0.4 conflicts)
  - [x] Iron golem AI: targets hostile mobs (not creepers) within 16, melee 7.5-21.5 every 20 ticks, throws up 0.4, arm
        swing, attack sound; iron ingot repairs 25 (test)
  - [x] Polar bear defend, goat ram, llama spit, bee sting (done in MobBehaviors: polar bears turn on attackers, cubs
        anger adults in 41 x 21 x 41, adults near cubs provoke 21 x 21 x 21 and attack players near cubs; llama spit 1 /
        Hard 1.5, every 2 s, gravity 0.06 drag 0.99; bees: anger 20-39 s spread to nearby bees, sting = Poison 10 s /
        18 s, stinger lost, death ~1 min). 2026-11-15 goat ram (wiki Goat): cooldown 30 s - 5 min (screaming 5-15 s),
        nearest still target in sight 4-16 blocks (players outside Creative / Peaceful, armor stands, mobs but ghasts /
        goats), locks its position, prepare_ram sound, a target leaving its block cancels; charge hits on box contact: 2 /
        Hard 3 (babies 1 / 1.5), knockback for the wiki's 9 / 4.5 blocks (strength 1.13 / 0.565), ram_impact; misses stop
        past the spot; #snaps_goat_horn blocks break off a horn (left / right, 10 % adults spawn with one, variant from
        the regular / screaming horn tags, horn_break, model horns hidden); 2 % screaming goats; wheat stops a preparing
        goat. Not on the wiki (Java): 20-tick head lowering, charge modifier 3.0. Llamas spit at untamed wolves every 2 s
        within 16 (tests). 2026-11-15 (MobBehaviors / MobAI / EntityManager, tests): llama strength 1-5 (wiki odds 32.8 %
        x 3 / 0.8 % x 2, foals 1 .. the stronger parent +1 at 3 %, chest columns = strength); wild wolves flee llamas
        within 24 at 1.5x (strength s: Java's (s + 1) / 5 per check - always for 4 / 5); goat long jumps (spots within 5
        laterally / 5 up or down, Java's 65-80 degree ballistic launch without drag, 40-tick preparation, 30-60 s
        cooldown, long_jump sounds, not from honey); fish schools (cod 9 / salmon 7 / tropical 7, Java follow-the-leader);
        phantoms call off a swoop with a cat within 16 (cats hiss; ocelots are Bedrock-only); charging vexes use the red
        vex_charging texture and raise / swing their arms (Java VexModel)
  - [x] Drowned trident throwing (1.5 s, 20 blocks, 8) + daytime land neutrality; enderman arrow dodge, rain damage,
        teleport toward far targets, block pick-up / place; warden projectile vibrations +10 (done: MobBehaviors /
        MobAI.wants_target; enderman freezes while stared at within 16, teleports from a starer within 4, carried-block
        layer + arm pose, drops the block on death; rain hurts every water_hurts mob; warden anger: +35 vibration / +10
        projectile (35 for two in 5 s, none from 30+ blocks), 2 s cooldown, touch +35, direct hit +100, roar +20 at 80)
  - [x] Zombie reinforcements / door breaking / villager targeting; piglin babies; witch drinking + 85 % magic resistance;
        evoker flee + warm-up; ravager stun / roar; creepers flee cats; skeleton inaccuracy + bow draw (done: Hard
        reinforcements 0-10 % + leaders, door breakers (10 % x clamped regional) break wooden / copper doors in 10 s on
        Hard; zombies / vindicators / ravagers hunt villagers, traders, iron golems, villagers infected 50 % / 100 %;
        witches walk into 10 blocks and drink water breathing / fire resistance / healing / swiftness (1.6 s), mob potion
        effects + splash potions on mobs; evoker flees within 10, 2 s vex warm-up with raised arms (fang warm-up has no
        Java value on the wiki); ravager 50 % 2 s stun on a shield block then a 6-damage roar (radius not on the wiki:
        4); creepers flee cats / ocelots within 6; mob arrows +-0.0172275 x (14 - 4 x difficulty), 20-tick bow draw)
  - [x] Parrot taming + shoulder; stray cats + morning gifts; armor (shulker 20 closed, magma 3 x size, wither < half);
        ominous trial spawners; raid bonus raiders / captain banners / POI centre; creature spawning every 400 ticks.
        Done: parrots perch on the left then right shoulder (saved with the player, drawn in third person), hop off on
        falls / damage / water / flying / gliding / sleep, cookies kill them; stray cats every 1200 ticks near 5+ beds
        (no bed claiming) with < 5 cats around; 70 % morning gifts (cat_morning_gift) from tamed cats within 10 blocks of
        the bed; shulker 20 armor closed; wither armor below half health (immune to arrows / tridents / wind charges,
        flies at the target's height); raid bonus raiders (25 % / 50 % / 0-2, witches, bonus-wave ravagers) and a captain
        per wave, captains / patrol leaders wear the ominous banner (CustomHeadLayer); ominous trials (Bad Omen -> Trial
        Omen 15 min x level, spawners within 15 blocks in sight turn ominous: mobs despawn, active at once, ominous config
        loot / keys, back to normal after the cooldown). 2026-11-15: ominous mobs wear their config's equipment table
        (trial_chamber_melee / _ranged: trimmed Protection IV armour, Sharpness / Knockback swords, Power / Punch bows -
        mob Sharpness / Knockback / Power / Punch / Protection now count; never dropped); ominous item spawners every 8 s
        above a player in range or one of the spawner's mobs (raycast 2-5 up), shown 3-6 s, then arrows / fire charges /
        wind charges / lingering potions shot down (Trials, kind "ominous_item"); Loot now applies set_potion /
        set_enchantments / set_components (trial consumables were plain water bottles); raid centre = average POI position
        (beds, job sites, bells) within 64 blocks, village = POI in the 3 x 3 x 3 sub-chunks (patrols: 5 x 5 x 5), the centre
        moves within 5 x 5 x 5 sub-chunks, defeat when none is left (Raids.is_village / village_center; no POI claiming:
        a villager within 64 blocks stands in); passive mobs spawn every 400 ticks (one pack try per chunk within 128 /
        simulation distance, 16 per tick, no extra 1 / 10 roll); cat variants from the 26.3 cat_variant data (all_black in
        swamp huts and at a full moon 1 / 11, textures), cats also spawn in swamp huts (none within 16 x 8 x 16) (tests).
        2026-11-15: ominous item spawners are saved with their chunk (item, age, delay) and sent to LAN clients (tests).
        Open: Raids.is_village still lets a villager within 64 blocks stand in for POI claiming (villagers now claim beds
        and job sites: Villagers could feed it)
- [x] Entities + item use (done 2026-11-14): item HP 5, XP orb sizes (2477 ... 1) + pickup 1 per 2 ticks + 7.25 range,
      MENDING (was missing), netherite floats on lava, item merge rules / pickup box, falling blocks (drop after 600 ticks,
      concrete powder in water, anvil damage 2 / block cap 40 + degrading), projectile gravities (potions 0.05, XP bottle
      0.07, trident 0.05), fireballs accelerate (0.1 / 0.95), trident Impaling / bounce / stick, splash distance to the
      hitbox, explosion exposure + float damage + difficulty + entity damage (items, frames, stands, vehicles), TNT no drop
      decay, fishing rain / sky timing, armor stand 20 HP, boat / minecart damage model, boat land speed 2.0 m/s, leads
      snap at 12 + allow list, bundle drops newest stack, shields don't knock back (Java 18w43a). Follow-ups:
  - [x] Item cooldowns (Java ItemCooldowns + white hotbar / slot overlay): ender pearl 20, wind charge 10, chorus fruit 20,
        shield 100 after an axe, goat horn 140; goat horns play their instrument (range / 16); chorus fruit teleports (was
        missing: 16 tries, +-8, floor search) (tests)
  - [x] Lingering potions make area effect clouds (MiscEntities.spawn_cloud: radius 3 -> 0 over 600 ticks, 20 wait,
        -0.5 / -100 per use, timed effects 1/4, instant 1/2, potion-coloured particles, wiki Effect colors); splash
        potions affect mobs (MobBehaviors.apply_potion); thrown at 0.5 with -20 degrees pitch offset (test)
  - [x] Ghast / blaze fireballs start at the 0.1 acceleration (wiki gives no start speed: Java assignDirectionalMovement)
        and speed up to 1.9; explosion knockback x (1 - 0.15 x Blast Protection levels of all pieces)
  - [x] Concrete powder solidifies when placed / landing / updated next to water (not water below alone; waterlogged
        blocks only through an open side) (test); items burn in fire (1 / soul fire 2 per tick + burning), on cacti and in
        lava (burn sound); projectiles break paintings / item frames (frames drop their item first)
  - [x] TNT minecart: falling > 3 blocks onto non-rail ground explodes it (bonus from fall / 10), broken while moving
        primes a 0-1.95 s fuse; boats carry 2 (mobs get in when no player drives, not aquatic / ambient / too wide,
        no despawn aboard, seats 0.2 / -0.6), boats take leads; armor stands break on a second hit within 5 ticks
        (wobble, hit sound; Creative one hit)
  - [x] Crossbow Piercing (passes level entities, never the same twice), firework rockets from the offhand (straight
        1.6 / tick, explode on contact, 3 durability per shot), Channeling (lightning on a hit entity / frame / lightning
        rod in thunderstorms under open sky), dragon fireball cloud grows 3 -> 7 (Harming II), perch breath cloud.
        Glass bottles collect dragon's breath from the dragon's clouds (radius -0.5)
  - [x] Shields block projectiles (2026-11-15, tests): UseItem.block_projectile from the projectile's position (half
        cylinder in front, pitch ignored; any shooter - mobs, players, dispensers): arrows bounce back x -0.1 and fly on
        (wiki Arrow), tridents bounce off (Loyalty returns), fireballs / wither skulls still explode, the rest break;
        no burning / tipped / Levitation / Wither effects reach the blocker; Piercing arrows pass (no durability);
        1 + floor(damage) durability from 3 damage, item.shield.block, "Not Today, Thank You" (entity_hurt_player
        blocked #is_projectile). Projectile hits now credit the shooter (death message) and set the hurt direction
- [x] Blocks over time (done 2026-11-14): crop growth formula 1 / (floor(25 / speed) + 1) with farmland / neighbour
      rules, beetroot 1/3 skip, stems attach to their fruit, nether wart 10 %, cocoa 20 %, sweet berries 20 %, kelp into
      flowing water, farmland (rain, #maintains_farmland), leaf decay tag, grass / mycelium spread rules, sky light
      = sky - darkening (rain 12 / storm 10 / night 4), lava ignition + fire tables, bone meal amounts, sugar cane /
      cactus support, light levels (amethyst buds, copper torches / lanterns, lava cauldron, firefly bush, calibrated
      sculk sensor). Fluids, fire mechanics, precipitation, melting verified. Follow-ups:
  - [x] Missing random-tick / timed mechanics added (Growth, wiki values, tests): budding amethyst, pointed dripstone
        growth + cauldron filling + mud -> clay, vines, cave / twisting / weeping vines, chorus flowers, mushroom spread,
        nylium decay, frosted ice, lit redstone ore off, bamboo + shoots (stage property), cactus flowers, turtle / sniffer
        eggs, frogspawn, dried ghasts, coral death (60-99 ticks), eyeblossoms (timeline 12600 / 23401), nether portal
        zombified piglins, mangrove propagules (were never growing)
  - [x] Redstone ore lights up when hit / used / stepped on (dust particles, light 9, off on the next random tick)
  - [x] Saplings / propagules / azaleas grow the 26.3 configured tree features through the worldgen tree placer
        (TreeGrower: fancy oak 1/10, *_bees_005 with a flower within 2, 2x2 mega spruce / pine, mega jungle, dark oak,
        pale oak, mangrove / tall mangrove, poplar colours, azalea tree; sapling restored when it does not fit; --growtest
        probe grows all 13 kinds). Leaf drip particles done (fluid items entry)
  - [x] Pitcher crop upper half (two blocks from age 3, as the 26.3 top-stage models) (test). Grass / mycelium under water / slabs:
        Java canBeGrass (fluid items entry)
  - [x] State-dependent light: lit copper bulbs 15 / 12 / 8 / 4, respawn anchor 0 / 3 / 7 / 11 / 15, vault 12 / 6,
        trial spawner 8 / 4 (block_registry)
  - [x] Bone meal targets (Bonemeal): saplings / azalea / propagule 45 %, hanging propagule age, mangrove leaves,
        mushrooms / fungi 40 % (huge features), nylium / moss / pale moss patches, netherrack, grass (128 walks, biome
        flowers), short grass / fern / seagrass -> tall, tall flowers drop, petals / wildflowers, big / small dripleaf,
        glow lichen spread, cave vines, rooted dirt, kelp, sea pickles, pale hanging moss; happy villager particles +
        item.bone_meal.use; full-grown crops no longer use it; vines are not a Java target (wiki) (tests)
  - [x] Sweet berry light rechecked: wiki "block above in light level 10 or greater", 20 % - as implemented
- [x] Redstone + block entities (done 2026-11-14): comparators read cake / composter / cauldrons / end portal frame /
      anchor / hives / jukebox / lectern / command block / copper bulb (+ through a block), container changes update
      comparators, lamp off-delay 4 ticks, torch 2-tick delay + burnout (8 in 60 ticks), piston immovable / breakable
      lists (shulker boxes drop with contents), dispenser sounds, hopper -> furnace fuel only + empty bucket pull,
      composter chances, beacon vertical range, portal height cap, game rule ranges, glow-ink sign colours, anvil rename
      cap 39, grindstone XP, candle cake, bell volume. Follow-ups:
  - [x] Note blocks: instrument from the block below / mob head above (wiki table incl. copper trumpets), head
        sounds, air-above rule (tests)
  - [x] Pressure plates (entity detection, wood / stone sensitivity, weighted formulas, 20 / 10-tick re-check, set-type
        click sounds), daylight detectors (20 ticks, sun-angle formula, invert on use), target blocks (accuracy signal,
        20 / 8 ticks), lightning rods (8 ticks, power 15), per-type button sounds; lightning thunder 10000 / impact 2.0
        (Sensors, tests)
  - [x] Tripwire + hooks (Tripwires: 1-40 strings between facing hooks attach, entity box 0.0625-0.15625 / detached
        0-0.5 powers the line, 10-tick re-check, broken string = 10-tick pulse then detach, shears disarm, string
        connections, attach / click / detach sounds 0.4 at the wiki pitches, hook support); detector rail (15 while a
        cart touches it, 20-tick re-check, comparator = chest / hopper cart fullness); activator rails eject riders and
        lock hopper carts (tests)
  - [x] Powered / activator rails pass power 8 rails along connected track of their kind incl. slopes (17 per source,
        instant); dust now weakly powers the block under / pointed at (lamps, rails, repeaters beside it) (tests)
  - [x] Game rules use the 26.x ids (58 rules: keep_inventory, advance_time, raids ...; wiki table), old names and old
        saves migrate (inverted disable* rules flip), /gamerule + suggestions + screen labels (tests)
  - [x] Respawn anchors: glowstone charging (4), Nether spawn point, explosion elsewhere (5, fire), respawn travels to
        the Nether and uses a charge (deplete sound; missing / empty anchor -> world spawn + message)
  - [x] Campfire cooking (4 slots, recipe time 600 while lit, -2 per tick unlit, items drawn per CampfireRenderer);
        campfire_cooking recipes had been loaded into the smoker table (smoker foods took 600 ticks)
  - [x] Smoker / blast furnace cook at 2 per tick (26.3 recipes list 200; wiki: 5 s) - they took 10 s
  - [x] Bed sleep rule = 26.3 bed_rule "when_dark" (sky darkening >= 4: clear 12523-23477, rain 12002-23998, thunder);
        bed explosions set fire
  - [x] Anvil prior work penalty max(left, right) x 2 + 1 (enchanting.gd uses left + right)
  - [x] Conduit (Conduits: waterlogged + 26 water around, 42-spot frame of prismarine / bricks / dark / sea lantern,
        16+ blocks, range 16 x floor(n / 7), Conduit Power 13 s every second to players in water / rain, full frame
        attacks one wet hostile within 8 blocks 4 HP / 2 s, activate / deactivate / ambient_short / attack sounds) (tests)
  - [x] Jukebox 15 while playing (ends with the track); lectern 2-tick page pulse + page sound (Blocks 2.0); bell rung
        by redstone (rising edge), projectiles and its swinging sides, raider within 32 -> raiders within 48 glow 3 s
        (+ resonate), villagers within 32 run to the nearest bed within 32; swing animation (BellRenderer) (Bells, tests).
  - [x] Glowing outline (2026-11-15): GlowOutline draws Java's entity_outline chain - glowing meshes on visual layer 20
        rendered by a sub-frustum camera into a buffer covering only their screen rectangle (no world depth: visible
        through walls), then one canvas pass = entity_sobel + 2 x box blur radius 2, white (no team colours), blended
        under the HUD. Zero cost while nothing glows (node not processing, no viewport render). Spectral arrows (mobs +
        player), bell-rung raiders and /effect (now also on mobs) give the real Glowing effect; the player model
        glows in third person. Needs an in-game look (headless probes ran it without errors)
  - [x] Slime / honey sticking (PistonStructureResolver rules: stuck lines + blocks behind a sticky block, 12 limit,
        slime / honey don't stick to each other, glazed terracotta push-only, immovable / breakable neighbours stay;
        sticky pistons pull whole structures); pushed blocks keep block-entity data; bells / campfires / lanterns /
        doors / beds break when pushed; per-hopper cooldown 8 (7 after a push into an empty hopper) and hoppers now
        collect item entities (block space above, bowl; #does_not_block_hoppers); portal destination: closest 3 x 4
        buildable spot with 4 air above within 16 blocks, then 1 x 4, then forced (tests)
  - [x] Decorated pot: placing a crafted pot keeps its sherds (BlockEntities.apply_item pot_decorations -> "sherds");
        spawn egg on a spawner / trial spawner sets its mob (Trials.set_spawner_mob)
- [x] World / camera / HUD / audio (done 2026-11-14): separate rain / thunder timers (wiki Weather), FOV Effects slider
      (was the Distortion slider), lava / powder snow / blindness / darkness fog, water fog ramp (25 % -> 100 % over 30 s),
      bottom-of-world fog, lightmap tint #FFD88C + night vision #999999 (26.3 environment attribute defaults), break delay
      6 ticks, break sound pitch 0.8, block fall sound only with fall damage, air bubble pop sounds, absorption hearts,
      music gaps 12000-24000 ticks (End 6000-24000, menu), loud sounds carry 16 x volume. Follow-ups:
  - [x] Player footsteps (Entity.moveDist / nextStep, combination / inside step blocks, muffled in water), swim, hurt
        (per damage type), death, small / big fall sounds; block place / break / hit / fall at the sound type's volume /
        pitch (Java multipliers). Block -> sound type for 1284 / 1286 blocks generated from the wiki Block sound type
        templates (tools/gen_block_sounds.js -> BlockSounds; was name guessing: cherry / bamboo / nether wood, basalt,
        amethyst, sculk ... all used wrong sounds); copper golem statues use their own 26.3 events
  - [x] Mob sounds: Java ambient timer (-80, chance t / 1000 per tick), pitch 1 +- 0.2 (babies 1.5), volume (ghast /
        dragon 5, slimes 0.4 x size), Hostile channel for monsters
  - [x] Lightning: thunder 10000 / 0.8-1.0, impact 2.0 / 0.5-0.7; natural lightning in thunderstorms (1 / 100000 per
        ticking chunk per tick, living entities under the sky within 3 blocks attract it, rain biomes only); sky flash
        (2 ticks full sky light, Hide Sky Flashes); lightning rods take natural strikes (closest rod within 128 with only
        air above; placed rods are indexed like Java's POI; rods placed earlier / by structures get their entry when
        their chunk loads - only sections whose palette has a rod are scanned, with native finds). Open: skeleton
        trap horses, the jagged bolt model (LightningBoltRenderer), sky colour flash
  - [x] Tripwires / plates see every block of the entity box (was feet + 1 only: tall mobs and jumping players missed
        strings higher up); boxes whose sections hold no plate / string (Interest.SENSOR palette bit) are skipped
        without block lookups, so the per-tick sensor pass is cheaper than before (test)
  - [x] Rain: Java tickRainParticles (100 f^2 tries, rain-only columns, smoke on lava / magma / campfires) and the rain
        sounds weather.rain 0.2 / 1.0 and weather.rain.above 0.1 / 0.5 (rain was silent)
  - [x] /weather default durations and thunder timer; bed rule in rain (sleep 12010-23992), sleeping resets weather only
        when raining
  - [x] Game logic uses Java raw brightness (sky - darkening): monster spawning (raw sky <= rand 32, thunder darkening
        10), spider neutrality, despawn brightness, spawner light; daylight burning = timeline monsters_burn window +
        Java isSunBurnTick chance (was a fixed 20-tick check)
  - [x] Water fog colour = the biome's minecraft:visual/water_fog_color (default #050533), bottom-of-world darkening
  - [x] Ambience (data-driven 26.3 audio attributes): mood (wiki algorithm, ambient.cave / Nether moods), Nether biome
        loops + additions, underwater enter / exit / loop / additions 90:9:1, background music per biome / dimension
        (underwater / creative / default entries, the End replaces the current track)
  - [x] Moon phase from a running day counter: day_time keeps counting like Java dayTime (sleep jumps to the next day,
        /time set / add / query daytime / day as Java); weather timers flip at 0 and redraw when reset (Java)
  - [x] HUD: selected item name (40 ticks, fade over 10, rarity colour), vignette (brightness-eased, multiplied), spyglass
        scope, pumpkin blur, powder snow outline, nether portal overlay + portal.trigger sound, frozen hearts, hotbar glint
  - [x] HUD: hotbar pickup pop (popTime 5, Gui.renderSlot squash), Inventory.add order (selected slot, offhand, then
        others), heart layout as Java (max health rows incl. Health Boost, absorption after them, row height, armour row
        above all rows)
  - [x] HUD: block hit particles while mining (ParticleEngine.crack every tick), nausea / portal world warp
        (screen-space GameRenderer warp, NauseaWarp) + nausea overlay below 100 % Distortion Effects
- [x] Options vs the wiki Options page: simulation distance 5-32, FOV Effects / Darkness Pulsing / Glint Speed 50 % /
      Glint Strength 75 % / Text Background Opacity are real settings now (were "not available")
- [x] Enchantment glint (was missing everywhere): GUI slots + hotbar (core/glint math, enchanted_glint_item, SRC_COLOR
      blend), held items (hand projection), dropped items, worn armour (enchanted_glint_armor at 0.16); Glint Speed /
      Strength options. Always-glint items per the wiki
- [x] D3D12 sampler descriptor heap was full (one material per run failed to draw: "not enough room in the SAMPLERS
      descriptors heap"): rendering/rendering_device/d3d12/max_sampler_descriptors = 2048 (the D3D12 maximum)
- [x] Window icon really applies now (hashed asset files have no extension: the PNG is decoded from bytes)
- [x] Perf after the audit (2026-11-14): the vignette as a custom canvas shader cost 0.39 ms GPU -> black + alpha bands,
      skipped below half an 8-bit step (static views 404 fps, GPU 2.23 ms); vine / mushroom area scans by block id, held
      item name rebuilt only on stack changes, overlay layers redraw only when needed. Flight bench vs the pre-audit
      build (same machine, back-to-back): 379 / 1 % 89 / 0.1 % 52 vs 383 / 94 / 54 (noise level); main thread per frame
      1.30 vs 1.39 ms. Sounds out of range (16 x volume) are culled before loading (Java); positional sounds now
      follow the world-origin rebase (they were offset by the origin after 512+ blocks of travel - inaudible)
- [x] Lush caves / mushrooms break on their own while chunks load: big dripleaf stems fell through to the crop-stem
      rule ("_stem" needs farmland) and collapsed on any neighbour update (all dripleaves dropped) - now the 26.3
      #supports_big_dripleaf / #supports_small_dripleaf rules; worldgen fluid ticks of a chunk wait for its 3 x 3 to be
      decorated (Java post-processing when FULL). Remaining (flight probe): plants standing on ore blocks (azalea /
      grass / dripleaf on diorite, tuff, copper ore): another origin's ore write, decided on pristine stone, overwrites
      the moss under the plant in the decorate merge (native chunk_decorate W_FORCE; the Java ore target test would
      fail on moss). Fixed 2026-11-15: ore writes carry their target rule (Features.W_ORE | rule << 2,
      rules interned with a per-state table Features.ore_mask) and the decorate merge (chunk_decorate / Features.apply /
      /place / tree growth) applies them only while the cell still passes the rule (moss, plants, structure blocks
      keep their block; a neighbour's stone-type blob still takes the ore, as in Java); native check equal. Glow berries
      broken by spring / aquifer water flowing on load look vanilla-like
Visual parity gaps found during the audit (vanilla draws these, Recraft doesn't yet):
- [~] End portal / end gateway surface: were invisible (particle-only block models); now the game's end_portal shader
      math (15 / 16 layers, screen-projected end_sky + end_portal) on the portal top/bottom and gateway faces. Render check
- [~] Monster spawner mob preview (SpawnerRenderer: 0.53125 scale, -30 deg tilt, spin 1000 / (delay + 200) x 10 deg per
      tick within 16 blocks); trial spawners show the mob they spawn next while waiting / active (spin uses the time to
      the next spawn as the delay - the wiki gives no trial spawner spin); spawn eggs used on either spawner set its mob
      (Trials.set_spawner_mob, egg used up in Survival). Render check
- [~] Enchanting table floating book (BookModel + EnchantTableRenderer + bookAnimationTick: opens / turns toward a
      player within 3 blocks, random page flips). Render check
- [~] Bell swing when rung (BellRenderer: lip swings with the body, 50 ticks); beacon beam tinted by stained glass /
      panes (sections: first glass sets the colour, each further one averages; wiki dye colour codes); active conduit
      (ConduitRenderer: turning / bobbing cage, two wind shells with the 22-frame animated textures and the 66-tick
      orientation cycle, camera-facing eye open while it hunts) (pot sherds: done). Render check in game
Reported 2026-11-13 (afternoon; rule: every value / feature / mob UI must match the Minecraft wiki):
- [~] Mining a block shows see-through holes (much more than Java's threaded rebuilds): edit batches now swap all
      mesh groups of one edit in the same frame (needs an in-game check)
- [~] Day cycle and sunset: day time advances 20 / s (24000 = 20 min, measured), sky / sunset colours / sun angle come
      from the game's timeline/day.json keyframes (ARGB, bezier ease) - renders at 11800 / 12400 / 13000 look vanilla.
      Need the exact moment that looks different
- [~] Mob values vs the wiki (Attribute + Hitbox pages): health and hitboxes match except fixed ones - zombie horse 25 HP,
      horse family / hoglin / zoglin width 1.3965, elder guardian 1.9975, zoglin speed 0.3; horses, donkeys, mules,
      llamas roll 15-30 HP (Java generateMaxHealth), horses their speed. 2026-11-14: bats fly like Java Bat (random
      targets, velocity eased to 0.5 / 0.7 per axis - they crawled at a fifth of that), mob fall damage per the wiki
      (floor, horses safe 6 at half damage, foxes 5, goats -10, frogs -5). Squids swim like Java (random
      vector x 0.2, tentacle strokes). Villager (0.5 x stroll 0.5) and wandering trader (0.7 x 0.35) stroll speeds
      already match. Fish, bee, parrot, vex and phantom movement ported 2026-11-15 (see the flyer entry). Open: ghast
      movement is an AI approximation
- [~] Some plants z-fight ("z-clipping"): repeated coplanar model faces (open eyeblossom glow layer, flower bed stems) are
      drawn 1/1024 block out along their facing, like Java's later-element-wins depth test (needs an in-game check)
- [~] Alt-tab back into the game sometimes does not work: V-Sync was switched on every focus change and menu (a swap
      chain rebuild); it now changes only when the setting changes (needs an in-game check)
Worldgen:
- [~] Grass looks denser than vanilla: placement matches the 26.3 data (noise_threshold_count 5 / 10 x 32 tries, trapezoid
      offsets, air filter, survival check); the dense look was likely mipmapped cutout plants (vanilla mips now). Recheck in game
- [~] Village house placement wonky (earlier): seed 12345 plains village (-144, -832) rendered - houses on beard terraces,
      planks streets over water, farms at water level; matches Java's behaviour as far as visible. Needs the case you saw
Rendering:
End:
Performance:
- [~] FPS goals: 500 x86_64 (emulated), 800 ARM64 native with 1 % lows 300-350 (ARM) / 100-150 (x64); stutters gone.
      Current numbers and limits: see the PERF + RAIN + CHUNK GEN entry at the top (2026-11-15).
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
      2026-11-14: the exact (sRGB) translucent pass for water costs ~0.16 ms GPU: static views avg 403 -> 380 fps,
      1 % low 188 -> 177 (--trsrgb=0 switches it off for A/B)
- [~] Chunk generation "instant" (2026-11-15: 14.0 s -> 7.9 s with the boosted fill, see the top entry): RD16 fully visible 14.5 s -> 8.9 s (spawn 1.3 s, ring 8 3.9 s); per chunk gen
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
3. Villager job sites, loom/cartography/lectern (banners, maps, books), armor trims.
4. Resource/data packs; LAN: container sync for clients, client portals/per-player dimensions.
5. Keep docs/STATUS.md, PARITY_MATRIX.md, BENCHMARKS.md, USER_GUIDE.md current.
7. Perf: see Performance round 2 → Next plan (fixed.md) and PERFORMANCE_AUDIT.md.
