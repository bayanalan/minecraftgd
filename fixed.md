# Recraft 2 — fixed bugs and completed work

Moved out of PROGRESS.md (2026-11-12). Open work lives in PROGRESS.md (OPEN BUGS). Newest first.

## Fixed 2026-11-12 (from the user bug lists; screenshots: c:\Users\Gerbilicious_Dude\Pictures\Screenshots\Screenshot 2026-11-12 <time>.png)
- [x] (Rendering) Rain cost ~35-75 % FPS [180829]: the 441 column quads shaded ~78 M fragments per frame at 2880x1800
      and discarded 97.5 % of them (rain.png is 2.5 % opaque, snow.png 0.8 %). Each column is now drawn as one small
      quad per vertical run of visible texels (WeatherFX._streak_mesh, 7 texture repeats, u wraps for snow), placed in
      the shader exactly over the texels the whole quad sampled, light / fog interpolated from the whole quad's
      corners. Frozen-weather A/B in one process (--raincheck): rain 2.75 -> 0.73 ms GPU per frame, snow 2.7 -> 1.0
      ms; images equal except ~0.01 % of pixels on texel edges (float rounding of the old large texture coordinates)
- [x] (Performance) Flight stutter from chunk streaming: chunk workers on the second Prime core cluster dragged the main
      thread's clock down (main thread running 10-20x slower in bursts). Workers now run on the 6 Performance cores (lower
      efficiency class) and use the second Prime cluster only during the loading screen, the first fill of the render
      distance, or when 3+ rings behind. Flight bench (ARM64, 2880x1800, RD 16, same 65 chunks / s): avg 240 -> 390-430,
      1 % low 70 -> 133-166, 0.1 % low 42 -> 81-95, worst frame 38 -> 14-17 ms; static views 465 / 1 % low 198. Also:
      jigsaw assembly 3-10x faster (trial chambers 420 -> 40-60 ms, identical pieces), decorate 2.9 -> 1.5 ms / chunk.
      Test / benchmark runs no longer draw their own FPS text (only with --benchoverlay)
- [x] (Worldgen) Woodland mansions never generated: now Java's WoodlandMansionStructure + WoodlandMansionPieces
      (MansionGrid: entrance block, recursive corridors, edge cleanup, 1x1 / 1x2 / 2x2 rooms with door / origin / stairs
      flags, the third floor grown from a staircase room; MansionPiecePlacer: outer walls traced per floor (wall_flat /
      wall_window, corners, inner turns), roofs + small walls + roof corners, corridor floors and carpets, indoor walls and
      doors, one room template per room from the floor's collection with Java's rotations and mirrors). Templates get
      both Mirror modes (FRONT_BACK and LEFT_RIGHT, door hinges swap), structure blocks are ignored and template air
      hollows the interior; data markers place facing chests (chests/woodland_mansion), evokers, vindicators and
      1-3 allays; the cobblestone foundation fills down to the ground (afterPlace); stub: lowest corner of the rotated
      5 x 5 box >= 60, biome at chunk block 7, 7. /place structure now places a whole structure chunk by chunk without
      the biome test (Java PlaceCommand). Verified by render (walls / corners / roofs meet) and grid invariant tests
- [x] (Worldgen) Dappled forest poplars looked nothing like vanilla [174713] (diamond / spindle crowns): rebuilt from the vanilla
      reference screenshots (2026-11-13 125709..125818) with the 26.3 parameters - dense rounded dome crowns (circular
      layers, ellipse profile centred 60 % down, radius 5-8, 5-6 layers), 1-4 diagonal branches each under a small
      crown lobe, rim-only side holes. The placer code itself is not public: shape matched visually, not block-for-block
- [x] (Build) Two game instances could open (and both write) the same world: Java's session.lock - the world holds the owner's
      process id; another running instance gets "Failed to access world" and cannot delete it, stale locks (crash) are
      taken over, released on leaving / quitting
- [x] (Rendering) Crafter did nothing and its screen threw errors (generic chest layout over 9 slots): now Java's crafter - 3 x 3
      grid with clickable disabled slots, result preview, redstone indicator; crafts on a redstone rising edge after 4
      ticks into the container in front or out of its face (remainders too), fail sound without a recipe, hoppers fill
      the smallest stacks, comparators read filled + disabled slots, Java placement orientation (front / top)
- [x] (Rendering) Pistons, dispensers, droppers placed while looking straight down faced down (Java: up, towards the player);
      observers the reverse - vertical facing was inverted
- [x] (Rendering) Headless autoplay probes never quit (awaited RenderingServer.frame_post_draw, which the dummy renderer never
      emits); a UI smoke test of 28 screens now runs in minutes - all open without script errors
- [x] (Rendering) Map markers: using a filled map on a banner toggles its marker (dye-coloured banner icon, its name under it in
      the vanilla font on a 50 % black background, removed when the banner breaks / changes), a map in an item frame
      shows the green frame marker, framed maps draw banner markers and turn in 90 deg steps (Java ItemFrameRenderer);
      the held map's player marker no longer errors after the hand-shader swap (off-map / off-limits sprites work)
- [x] (Worldgen) Cave water pools generate cut off [180044]: dripstone pools (water only where 4 sides + below are stone / water)
      were opened by another chunk's carving feature decided on pristine terrain; decoration now skips an origin's air
      writes on or beside a liquid another origin placed (Java: the lake sees the water and aborts, or the pool sees the
      air), native + GDScript identical (nativecheck decorate 0 differing). Recheck in game
- [x] (Worldgen) Parse Error: Could not resolve class "CreativeScreen": scripts/ui/container_ui.gd line 313 had a stray "o"
      typed before draw_background (file saved 10:33 from the editor); removed. If the editor still shows it, don't save
- [x] (Worldgen) /seed had no way to copy the seed: Java's copyOnClickText - green [seed], click copies to the clipboard, hover
      shows "Click to Copy to Clipboard" (/locate coordinates now show "Click to teleport" on hover)
- [x] (Rendering) Nether / any dimension fog stayed the default light blue after a teleport or portal trip while the player
      stood still (biome blend taken before the chunks existed, only redone on camera block changes): now redone each
      tick until the chunks around the camera are loaded
- [x] (Worldgen) Maps: Java MapItem.update ported (reveal radius 128 >> scale - was 64 px, 1/16 of the columns per tick plus
      changed neighbours, 2^scale blocks per pixel with the most common colour, height shading / (2^scale + 4), edge
      checkerboard); the holder's arrow (22.5 deg steps, Nether spin) / off-map / off-limits dots like MapRenderer;
      cartography table (zoom out with paper up to scale 4, lock with a glass pane, copy with an empty map, Java
      screen with the scaled / duplicated / locked previews and error icon)
- [x] (Worldgen) Structure data markers (TemplateStructurePiece.handleDataMarker) were ignored: shipwreck map / supply / treasure,
      igloo and ocean ruin chests had no loot, ocean ruins no drowned, end cities no loot / shulkers / elytra. Now
      handled per structure; end cities run Java's EndCityPieces (tower / bridge / house / fat tower generators, one
      ship, batch collision rule, the y 60 corner check - also in /locate); buried treasure runs BuriedTreasurePieces
- [x] (Worldgen) Deep dark had no sculk (the one vanilla feature type left unimplemented: sculk_patch): Java SculkPatchFeature +
      the world-gen SculkSpreader ported natively (featx kind 32: charge cursors, sculk / sculk-vein behaviours,
      MultifaceSpreader vein spreading, sensor / shrieker growths, decay penalties) - 2,356 sculk + 2,131 veins around
      the seed 12345 ancient city; the GDScript placement loop for it (2.2 s per load test) is gone
- [x] (Build) native/bin/recraft_native.x86_64.dll rebuilt (no longer locked); builds/windows-arm64 and builds/windows-x86_64 re-exported with every change of this round (2026-11-13 01:08)
- [x] (Gameplay / UI) Elytra + firework: the boost is Java's (updateFallFlyingMovement + FireworkRocketEntity attached boost, life
      10 x (flight + 1) + r6 + r7); using a rocket while gliding now spawns the attached rocket entity: rendered as the
      item's camera-facing ground sprite (also free-flying rockets, were grey boxes), riding at the hand, a spark every
      tick (gaussian 0.05, against the vertical motion), launch sound volume 3, at the end the star burst or Java's
      2-4 POOF particles (new ExplodeParticle kind, also used for mob death poofs)
- [x] (Gameplay / UI) Advancement toast text colours (challenge / goal); advancements screen like vanilla: AdvancementToast header
      per frame (challenges pink 0xFF88FF, tasks / goals yellow), ToastManager 600 ms quadratic slide in / out with
      ui.toast.in / out (+ challenge_complete), chat per frame type (made the advancement / reached the goal /
      completed the challenge); the screen (tabs, window, tree layout, frames, visibility) renders like Java;
      /advancement gained from / until / through and single criteria with Java's messages
- [x] (Gameplay / UI) Waterlogging for every waterloggable block: placement into water, buckets (fill / empty) and flows already
      handled; flows no longer waterlog (Java: a waterloggable block takes only a water source - canHoldSpecificFluid),
      doors hold water back (canHoldAnyFluid), holes test the flowing fluid. Kelp / seagrass ocean renders show no air
      pockets. Tests: fence passed by, two sources waterlog a stair
- [x] (Gameplay / UI) Fire spread: Java FireBlock ported - scheduled tick 30..39, survive check (sturdy floor or burnable side), rain
      burn-out, age, infiniburn floor per dimension type, checkBurnOut on the 6 sides (fire or gone, TNT primed), spread
      into the 3 x 6 x 3 box by ignite odds / age / difficulty / humid biomes, the bootStrap odds table, side-attached
      and soul fire states; LavaFluid.randomTick lights fires; fire from flint and steel / crystals uses the same state.
      Probe: planks + leaves burn down over ~1200 ticks
- [x] (Gameplay / UI) End crystal item (EndCrystalItem: obsidian / bedrock, empty above, no entity in the box, no base plate) and the
      dragon respawn (tryRespawn: 4 crystals beside the exit portal; DragonRespawnAnimation START / PREPARING / pillars
      rebuilt one per 40 ticks with invulnerable crystals beaming at (0, 128, 0) / SUMMONING / new dragon, crystal
      beams, abort when a respawn crystal is destroyed); exit podium clears Java's 3.5 sphere (the egg stays).
      --respawntest: 604 ticks, dragon back
- [x] (End) End crystals too small [181845]; sometimes no fire / off [181912]; no healing beam: EndCrystalModel / Renderer
      ported (scale 2, base plate around the bedrock, outer / inner glass and cube nested at 0.875, Ry(age * 3) * 60 deg
      tumble, getY bob, random start time), EndCrystal.tick keeps a fire in its block in the End, EnderDragon
      checkCrystals (tracked nearest crystal within the box + 32, re-picked 1 tick in 10, heals 1 / 10 ticks) with the
      renderCrystalBeams beam (8 quads, scrolling end_crystal_beam texture, black at the dragon); destroying the
      tracked crystal hits the head for 10, a holding dragon starts strafing
- [x] (End) Dragon tail always straight; AI stiff (no curving / waving, drifts): Java EnderDragonModel rebuilt (head with
      nostrils / scales + jaw, 5 neck + 12 tail segments with spine scales, body scales, wings + tips (mirrored left),
      legs with tips and feet) and posed from a 64-tick flight history like Java: body yaw 7 ticks back + climb pitch,
      neck / head / tail curving behind turns and waving with the flap phase, torso roll, legs tucked, root bob. AI is
      the Java phase machine on the node graph (holding circle radius 60 like vanilla). --dragonshots=N renders it
- [x] (Worldgen) Ruined nether portals generate inside terrain [180647]: ported RuinedPortalStructure / RuinedPortalPiece - setup
      choice, air pocket (underground portals were placed without their air: sealed in stone), giant 5 %, rotation +
      mirror about the template centre, findSuitableY (3 of 4 corner columns, from Java getBaseColumn: new native
      tg_column = interpolated density + aquifer), biome test on the stub, cold check, processors (gold 30 % gone, lava
      rules, netherrack -> magma, Java BlockAgeProcessor, protected blocks, lava-submerged, blackstone), netherrack /
      magma spread + drip columns, vines and leaves (jungle / swamp). --rpcheck lists starts; renders checked
- [x] (Worldgen) Check: 8 overworld blocks = 1 Nether block: scaled_target = coordinate scale ratio (1/8, 8), floored like
      BlockPos.containing, clamped to the border; link search 16 (Nether) / 128 (Overworld) - matches Java
- [x] (Worldgen) Ice spikes cut off naturally [180259]: the spike layer loop iterated [k, -k] by value, so the k = 0 layer was
      skipped with its (non-existent) mirror: every spike missed its base slice (--icegap: sandwiched air cells per y
      342 -> 13, the rest are Java's random edge notches / trunk-corner gaps)
- [x] (Rendering) Gap glitch at the edge of ice [175817]; seams seen from under water [175857]: translucent cube faces (ice, glass,
      slime, honey) are no longer merged by the greedy mesher (T-junction hairline cracks showed through translucent
      layers; Java never merges), both meshers, --nativecheck mesh 0 diffs. Also: the camera-close bubble every 10
      ticks under water is gone (Java: 8 bubbles around the body only when drowning damage hits)
- [x] (Worldgen) Crimson roots floating; water in the Nether [181222] [181333]: roots / sprouts / fungi survival = Java mayPlaceOn
      (#nylium, soul soil, #dirt, farmland) in both feature engines and block updates (they had no rule: placed anywhere);
      water from buckets / dispensers evaporates where the dimension has minecraft:gameplay/water_evaporates (hiss + 8
      large smoke), the Nether's fast_lava gives lava tick delay 10 / drop-off 1 / slope distance 4
- [x] (Rendering) Water flow not identical [180119]; placed water low resolution [181222]; flow visible only every ~10 s: fluid
      ticks ported from Java FlowingFluid (getNewLiquid, spread down first / sides, getSpread slope search 4 (lava 2/4),
      holes, canBeReplacedWith, waterlogging spreadTo, lava spread delay x4); neighbour updates gave fluids a 1-tick
      tick (flows raced); bucket first tick 5 / 30; animated textures (water_flow / lava_flow 32 px) kept at native
      resolution; chunk relight / remesh after block changes now ahead of generation work (was behind it: seconds while
      streaming) and batched 150 ms instead of 600 ms. --flowtest: ring per 5 ticks, radius 7 = 113 blocks at t31
- [x] (Performance) Nether / End chunk generation very slow: 26.3 Nether feature types (netherrack_replace_blobs, delta_feature,
      stepped_column_cluster, single_block_pillar, projected_random_patchy_square, random_neighbor_spread, huge_fungus)
      and the count_on_every_layer modifier ported to the native feature engine (basalt delta chunk 215 -> ~3 ms of
      feature work; --nativecheck in the Nether 0 differing write lists); the End is all-native (biome erosion sample
      by native point evaluation instead of a GDScript density context per chunk: 8.1 -> 3.1 ms). Remaining GDScript
      features: overlay (basalt_pillar), root_system, iceberg, fossil, bamboo, poplar / cherry trunks, spike, sculk,
      large_dripstone, geode, end_spike / island / gateway, coral, chorus, blue_ice, block_blob
- [x] (Performance) Keep the other dimension partially loaded: the decorated chunks within 10 of the player stay in memory per
      dimension (ChunkManager.dim_cache) and are adopted on the way back instead of read / generated (--dimtrip: 126
      chunks from memory on return)
Rendering:
- [x] Grass block sides darken the landscape from a distance [175238]: vanilla mip chains (cutout plants nearest-only like Java's unmipped cutout; transparent texels take neighbour colours before averaging)
- [x] Bed item models wrong in the inventory [175344]: 26.x composite item models (head + foot translated (0, 0, 1))
- [x] Water too blue / old tint [175454]: translucent alpha compensated for blending in a linear target (Java blends in sRGB; light sand showed through lavender)
- [x] Arrow (entity) texture wrong [180326]: Java ArrowModel / TridentModel with their textures (spectral / tipped); box_arrays UVs fixed to Java ModelPart.Cube (every entity face was mirrored)
- [x] Items lack proper lighting in the inventory [180433]: Java ITEMS_3D two-light GUI lighting (top 1.0, left 0.65, right 0.4); entities / block entities lit by normals with Java's LEVEL (Nether: cardinal_light) lights, first-person hand in view space
- [x] Falling particles jitter (particles ticked a frame after the tick start: drawn one step back); Java FallingLeavesParticle (fixed sprite of 12, spin, flow / swirl drift, removal on contact), tinted / pale oak leaf particles, Java 667 x 2 animateTick samples
- [x] 2D breaking particles ignore Fullbright
- [x] First-person death animation flashes (void damage hit the dead player every tick)
- [x] Tooltips drawn behind the player model in the inventory [183216] (overlay control on top)
- [x] Hearts: Java Gui.renderPlayerHealth blinking (white blinking hearts, display health lag, regen blink)
UI / gameplay:
- [x] Command suggestions shown when commands are disabled
- [x] Clicking a command suggestion does not fill it in
- [x] While suggestions show, Up / Down should still reach the chat history
- [x] Creative worlds must allow commands by default
- [x] Game menu (pause) not vertically centred [175558]
- [x] Bed messages ("You can sleep only at night" ...) use the action bar
- [x] Straw beds: no respawn point, break with particles / sound when left or on death (26.3 straw_bed_rule)
- [x] /build command: architecture, emulation guess, Godot version, native library, renderer, CPU / GPU
- [x] Right-click armour equips it (Equippable.swapWithEquipmentSlot, swing, equip sounds)
- [x] Respawn at the nearest safe location, never inside blocks
Movement / mobs:
- [x] Sprint / crouch / swim / glide transitions smooth (Java Camera.tick eye height + GameRenderer.tickFov, interpolated)
- [x] Death animation (red, tips over 20 ticks, poof); creaking tear-down (45 ticks twitch, crumble); creaking model (CreakingModel)
- [x] Ender dragon (verified by --dragonsim: circles the node ring, strafes, lands on the podium twice in 1600 ticks;
      model checked): Java node graph (24 nodes, adjacency masks), phases (holding, strafe + fireballs, landing approach / landing, sitting scan / roar / breath, takeoff, charge, 200-tick death), Java flight physics, wing hierarchy + flap formula
- [x] Entity models: every mob audited with --rigcheck (Java box-UV face coverage + unused opaque texels per texture) and
      lineup renders. MobRigs (Java layer definitions) replaced borrowed / approximate rigs: zombie villager, illagers
      (robe, folded arms by arm pose, illusioner hat), witch (4-tier hat, mole), warden, breeze (+ wind layer), sniffer,
      armadillo, camel, frog, bat, allay, vex, guardians (12 spikes, eye), goat, parrot, cod, salmon, pufferfish, tropical
      fish, turtle, ravager, wither, polar bear, llama, enderman jaw, phantom tips, axolotl gills, humanoid hat layer,
      drowned arms; 26.3 layouts read from the textures: rabbit (64x64), magma cube (64x64), copper golem, sulfur cube
      (18^3 + inner 16^3), parched wraps, nautilus (APPROXIMATE). Block layers: mooshroom mushrooms, snow golem pumpkin.
      Rig builder: Java ZYX rotation order, corrected z sign (piglin ears flopped inward), part nesting, texture layers.
UI / items:
- [x] Tooltips: vanilla tooltip sprites (gui/sprites/tooltip background + frame) and full item stats (attribute
      modifiers "When in Main Hand:" attack damage / speed, armor, toughness ..., colours, spacing)
- [x] Creative tabs in Java CreativeModeTabs order (CreativeTabs, incl. 26.3 items); Search = tabs in order; spears in Combat
- [x] Shift-click quick-move (Java quickMoveStack targets: armor equip, shield offhand, main<->hotbar, container reverse)
- [x] Armor / offhand empty-slot icons (creative inventory tab drew no empty icons)
- [x] Player model backwards (shared preview never turned in Creative; Java follow-mouse pose)
- [x] Held items: context models (spear in-hand model) + each model's display transform with Java's exact numbers
- [x] Block icons use the item model + display.gui (stairs / fences / walls right), native rasteriser at 64 px; back faces
      culled like Java's GUI item render types + shade_direction_override (small dripleaf's coplanar leaf undersides won)
- [x] Dropped items: extruded ground model, Java sizes / copies / bob / spin
- [x] Nautilus armor (and wolf armor) stack to 1
- [x] Chat command suggestions (CommandSuggest: per-command argument kinds, ids / selectors / coordinates, yellow selection,
      ghost text, Tab / Up / Down, usage line); clickable chat components (suggest-command)
- [x] /locate runs on a worker thread; green clickable coordinates fill /tp @s x ~ z
- [x] QoL settings (Advanced Video): Connected Glass (16 frame variants per glass texture, both meshers, parity 0),
      Fullbright, Zoom key (C), Show Coordinates
- [x] Third-person / mob held items (HeldItems: Java ItemInHandLayer chain + thirdperson display, left mirrored);
      mob equipment (populateDefaultEquipmentSlots: zombie 1%/5% sword or shovel, drowned trident / rod / shell,
      skeleton bows, wither skeleton stone sword, piglin crossbow or gold sword, brute gold axe, vindicator axe while
      aggressive, pillager crossbow, vex sword), weapon damage for random weapons, 8.5% drops; player F5 rig now uses
      HumanoidModel.setupAnim (ITEM pose, arm bob, crouch, attack swing)
- [x] Cushions: 26.3 seat entity (16x4x16 box on entity/cushion/<colour>_cushion.png, placed from the item, right-click
      sits in the riding pose, sneak gets up, a hit breaks + drops it, gravity, saved; place/sit/get_up/break sounds)
Blocks / gameplay:
- [x] Fences / walls / panes / gates / stairs connect (ShapeUpdates). ROOT CAUSE of the wrong walls: the registry took
      property domains from the blockstate JSON, and multipart files never name the off value (wall sides had only
      low / tall, fence / vine / lichen / fire sides only true, redstone sides no none) - with_prop silently failed, so
      every wall kept a post and side arms, fences could not disconnect, and template / feature states with
      north=false etc. failed to parse (village fences, vines, fire drew every side). Domains are now completed to
      Java's (BooleanProperty, WallSide, RedstoneSide): 33006 states, parity 0, tests 200/200.
- [x] Dirt path / farmland under a solid block -> dirt
- [x] Water bucket waterlogs the clicked block; empty bucket takes the water back
- [x] Eggs (incl. blue / brown) thrown with item sprites, chick chances; splash potions now apply (elif bug)
- [x] Cushions work (were treated as blocks; 26.3 has no cushion blocks)
- [x] Beds: Java rules (night / thunder, reach, monsters 8x5x8, explode outside overworld), lie in bed (camera along the bed), Leave Bed screen, 100-tick darken, skip night + clear weather, stand up beside, fade out; damage wakes
- [x] Java getShape outlines (crops by age, plants, stems, vines ...)
- [x] Petals / wildflowers / leaf litter stack to 4
- [x] Pale hanging moss no collision (+ campfire / cauldron / shroomlight / chorus flower / pots / azalea collide again);
      length measured = Java PaleMossDecorator (runs 1:381 2:149 3:99 4:42 5:11 6:9 7:3 over 48 chunks, geometric 1/2)
- [x] Fluids: Java LiquidBlockRenderer (corner averaging, flow texture by flow vector, sides / bottom / overlay), GDScript + native, parity 0
- [x] Huge mushrooms: Java caps (red top full 3x3, brown radius), height, ground / space checks (no more on trees); native parity 0 diffs
- [x] Sugar cane shading (verified: even, shade_direction_override up)
- [x] Arm swing repeats while mining (creative hold-break and unbreakable blocks too)
- [x] Rotated cube faces: UV orientation matched by vertex position (sideways logs / pillars)
- [x] Rain falls down (Java v mapping)
- [x] Creative search keeps focus (Java setCanLoseFocus(false)), white caret / blue selection
- [x] TNT: no float, white flash, f^4 swell; Java ray explosion (1352 rays), entities hurt before drops, survives_explosion / decay 1/radius, urgent remesh
- [x] F3+F4 game mode switcher (Java GameModeSwitcherScreen), F3+N
- [x] Inventory: Java press / release clicks, double-click collect, drag spread (left even, right one each, middle creative) with preview
- [x] Item / XP pickup animation (Java ItemPickupParticle)
- [x] Breaking cracks: Java crumbling blend (2 x src x dst, alpha discard) on the block's own faces
- [x] Hurt tilt: Java bobHurt (partial ticks, sin(f^4), hurt direction) + dying tilt
Worldgen:
- [x] Structure ground height (Structures.first_free_height) evaluated the density WITHOUT Java's 4x8x4 cell
      interpolation (native df_points without a chunk): pieces landed 1-3 blocks off the real terrain and the beard dug
      pits / buried them (lamp posts in holes, houses sunk, terrain over floors). Now df_points runs in the column's chunk
      with lazy corner grids, block interpolation order: 99% of columns exact (rest = carvers / beards). The tent floor
      grass is in the 26.3 abandoned_camp templates themselves (legacy elements keep terrain where the template has air).
- [x] Structure void: 390 templates use structure_void as a jigsaw final_state; Java JigsawReplacementProcessor places
      nothing there, we placed the block. Fixed in both placement paths.
- [x] Sulfur springs / desert wells: 26.x 	emplate feature type was missing (sequence stopped after the tuff, wells
      never generated). FeaturesExt._template (weighted template, random rotation about the centre, explicit air);
      /place feature | template command; rule processor append_loot block entities; capped processor (two-pass,
      Java finalizeProcessing) -> trail ruins suspicious gravel.
- [x] Archaeology: brush (BrushItem 200 ticks, stroke every 10, BrushableBlockEntity 10 strokes / dusted 0-3 / decay /
      loot on the brushed face / sand or gravel / durability), Java applyBrushTransform first-person sweep. --brushtest.
- [x] Jungle trees: canopies are not clipped at chunk seams (leaf continuity 0.74 seam vs 0.73 interior); branches were
      wrong (4 x-axis logs from the corner) -> Java MegaJungleTrunkPlacer (5 upright logs from the trunk centre, Mth table,
      float32), both engines, parity 0. Trees into other trees' leaves = vanilla (foliage only needs air / leaves).
      Huge mushrooms fixed earlier.
- [x] x86_64 DLL rebuilt (icon raster, fluids, mushrooms, lazy density corners, jungle branches); tests 200/200 + 105/105


## User bug round (2026-11-12 morning)
- Ice "gaps" at chunk borders (see-through dark strips, visible from some angles): translucent groups were ordered
  far-to-near by the distance to their 64-block bounding-box centre (and only within each vertex page), so a farther
  chunk's water was blended over a nearer chunk's ice. Now translucent geometry has its own vertex page, is ordered
  globally across pages (draw runs per page switch) and sorted like Java's reverse BFS section order (section steps
  from the camera section, centre distance as tie-break). Screenshot-checked at the frozen river near (741, 326).
  Found on the way: decoration ran in place on the live chunk on a worker while the main thread could snapshot it for a
  neighbour job (stale cached snapshot) -> decoration now works on a private copy (Chunk.decor_shell / adopt_decoration
  on the main thread); chunks meshed while a neighbour was still undecorated are re-meshed when it decorates
  (Chunk.mesh_undecor, ChunkManager._remesh_built_against).
- World loading screen (Java LevelLoadingScreen): the world appears only once every chunk within 3 of the player is
  generated, lit and meshed (max 15 s) - new worlds, saved players, dimension arrivals; progress % + chunk status map in
  Java's ChunkStatus colours. While it shows, chunk work uses up to 10 workers and larger main-thread budgets
  (ChunkManager.set_loading). New world via the UI: visible after ~3.0 s with the 7x7 area drawn.
- Title logo off centre / too big: the 4x logo texture set a 1024-px minimum size (TextureRect keep-size) -> ignore size.
- Empty tooltip box on every button: Godot 4.7 asks for a custom tooltip even with empty text -> McButton / McSlider
  return no tooltip for empty text.
- Blank screen after closing Video Settings: Options restores its own controls robustly now (records them once, restores
  on any way the sub-screen goes away; a second sub-screen no longer overwrites the saved state).
- Giant spruce / pine crowns (see Perf round 4 entry).
- Smooth lighting "weak / pre-1.12" (user): three causes, all fixed in GDScript + native meshers (nativecheck 0 diffs):
  1. grass_block was not a full collision cube (its model has two 0..16 elements - base + tinted side overlay - and the
     full-shape test accepted exactly one box), so grass never occluded in AO: terrain steps, paths, slabs, plants
     next to grass had no corner darkening. Any covering box now counts (BlockRegistry F_FULL_SHAPE).
  2. Light blend kept in quarter levels like Java blend() (was rounded to whole levels).
  3. Model quads (slabs, stairs, paths, farmland, snow layers, ...) were flat-lit: now Java's model AO -
     calculateShape (boundary quads sample the neighbour layer, inset quads their own; centre light / shade rules) and
     per-vertex bilinear interpolation of the 4 corner values at the vertex position. Flat lighting kept, as in Java,
     for models with "ambientocclusion": false and light-emitting blocks (new F_NO_AO; emitters raise block light to
     their emission, LevelRenderer.getLightColor). Screenshot-checked: path / farmland / slabs on a flat world, terraced
     grass hillside (seed 12345 near 60, -85).
- Greedy meshing keeps vanilla shading with AO gradients (cost of fix 1 above: hilly grass terrain lost merging, play
  bench 431 -> 364 FPS): face keys are per-job descriptor indices (texture, tint, centre, all 4 corner sky / block /
  AO values in quarter levels) with merge modes - uniform faces merge both ways (now also on quarter levels), faces
  constant along one face axis merge along that axis only (identical vertex values, identical linear interpolation).
  Screenshot A/B (`RC_NOMERGE=1` env = no gradient merging): land pixel-identical, only animated water differs, as
  between two identical runs. Native + GDScript in lockstep (nativecheck mesh 0 diffs).
- Air pockets in the sea (user): every generated kelp column ended in air - 26.3 names the tip provider
  "minecraft:randomized_int" (was matched only as randomized_int_state_provider -> stateless provider = air). 1,904
  suspicious cells in a 121x121 ocean area -> 0. Kelp random tick now Java GrowingPlantHeadBlock (age < 25, 14 %,
  into source water, old tip -> kelp_plant; was sugar-cane logic needing air). Legacy structures: air never replaces
  liquid; legacy mineshaft pieces (room / corridors) are skipped per chunk when their box touches liquid (Java
  StructurePiece.isInInvalidLocation) - a mineshaft cut open the sea floor.
- Lava lake on the ocean (user screenshot): Java LakeFeature edge rule was half-ported (below the fluid line only air
  rejected; Java rejects anything non-solid that is not the lake's fluid -> water). Also added the 26.3 lake
  predicates (can_replace_with_air_or_fluid / can_replace_with_barrier) and the barrier shell (stone around lava
  lakes, random above the fluid line). GDScript + native featx; nativecheck decorate 0 diffs.
- Reloaded worlds: chunks loaded from a save had their features (and their neighbours') recomputed on decorated
  terrain without pristine heightmaps, so regenerated neighbours could differ from first generation. Loaded chunks
  now regenerate their pristine terrain on demand (Chunk.raw, only while a 3x3 neighbour still has to decorate) and
  feature computation uses it; loaded chunks no longer block light/mesh on a feature pass they do not need.
- Tree spacing / gaps (user: "tree generation not identical to vanilla"): feature placement read pristine heightmaps
  for every type. Java ProtoChunks keep the POST_FEATURES heightmaps (WORLD_SURFACE, OCEAN_FLOOR, MOTION_BLOCKING,
  MOTION_BLOCKING_NO_LEAVES) live while features place blocks; only *_WG stay pristine. Trees use OCEAN_FLOOR, so a
  tree whose spot is under an earlier tree's canopy lands on the leaves and fails would_survive; flowers
  (MOTION_BLOCKING) likewise skip canopies. Now live in both engines (FCtx.hl, Java Heightmap.update incl. the
  scan-down on removal; native fx_run writes the same array in place). Seed 12345, 9x9 chunks at spawn: 6,048 -> 4,210
  log blocks (overlapping / under-canopy trees gone). Still differs from Java: per-chunk feature passes do not see
  earlier neighbours' features (Java's order-dependent cross-chunk view); TreeFeature details not yet ported
  (getMaxFreeTreeHeight volume from minimum_size, clipped heights, foliage offset sampled per attachment after the
  trunk, setDirtAt keeps podzol).
- Chunk generation across cores (user: 15 % CPU on 18 threads): headless load test, 5 vs 16 workers: full RD16
  visible 21.7 -> 16.5 s, teleport ring 8 6.2 -> 4.6 s, but per-job time 2-3x (features 23 -> 63 ms, terrain 18 ->
  37 ms) and main-thread worst frames 23-29 -> 137-162 ms: the remaining GDScript world-gen work (structure placement
  steps 3 / 7, ancient city, trial chambers, sculk patches) contends across threads. Workers stay at 5 in game / 10
  while loading until that work is native or contention-free.
- Blank GUI after leaving Options (user, again): the return callbacks were GDScript lambdas created inside the screen
  being replaced (title: Options / Language / Accessibility; pause menu: Options / Statistics / Advancements). A
  lambda is bound to its creator; once that screen is freed the Callable is invalid, Done skipped it and freed itself
  -> nothing on screen. Now bound to persistent objects (Callable(app, "show_title"), World.open_pause_menu), and
  Options / top-level settings screens fall back to the title (Game Menu in a world) if a callback is ever invalid
  (UiKit.return_fallback). Verified with real clicks: title -> Options / Language / Accessibility -> Done -> title;
  in-world Pause -> Options -> Done -> Game Menu.
- GUI scale like vanilla (user: "only makes text larger, glitchy, needs a restart"): widgets drew text / sprites at
  the live setting while every screen's sizes were baked at creation. Now UiKit.scale() is a committed value and
  UiKit.apply_scale (Java resizeDisplay -> Screen.resize) runs when the setting changes (on slider release) or the
  window resizes (Auto / clamped scales): new theme, sizes baked at the old scale converted from a snapshot (min sizes,
  font / constant overrides, absolutely placed controls), then each screen's _layout re-run - menus and in-world
  screens, no restart. McW.place sets the minimum before the size (a smaller size was clamped by the old minimum).
  Screenshot-checked Video Settings 4 -> 5 / 4 -> 2 and the title at 6. Title notice wraps to two right-aligned lines
  when it would run off the screen.
- Plants darker than the grass under them (user screenshots vs vanilla): 26.3 cross models (tinted_cross, cross,
  flower pots) use the element property "shade_direction_override": "up" instead of "shade": false; the baker ignored
  it, so plant faces got the 0.8 / 0.6 side shade. Quad shade field now 0 none / 1 face direction / 2 + d direction d
  (ModelBaker.shade_of; native mesher, GDScript mesher, entity renderer).
- Stutters (play / flight, all CPUs): (1) the main thread was moved to the slow core cluster while workers ran (a
  fixed GDScript probe 10x slower): pinned to the fastest cluster by default (soft CPU-set preference), 105 -> 39
  frames over 8 ms; (2) mesh / light / load / save jobs used the main thread's registry tables (refcount contention)
  -> per-thread copies; (3) the block outline was a new ImmediateMesh every frame (RID churn under the RenderingServer
  lock) -> rebuilt only when the target state changes; (4) SkyState's timeline / biome blend part runs per tick, the
  look-dependent fog per frame; (5) random-tick handler budget 10 % of the frame time (was a fixed 1.5 ms), deadline
  checked per handler, sampling spread over the frames of the tick; (6) creaking-heart scan one chunk row per tick.
  Finding: while workers run, every refcounted GDScript operation on the main thread slows (a main-thread-only array
  probe slowed exactly like the shared one) - remaining spikes are GDScript main-thread work under that slowdown.
  Emulated x86_64 release build (play): avg 327 -> ~397 (run-to-run spread +-20 % with background apps).
- Breaking particles (user request): Java TerrainParticle billboards (ParticleEngine.destroy grid, velocities,
  lifetime, half quad size, 0.6 x block tint, random 4x4-texel window of the particle texture, mirrored U) in one
  MultiMesh sampling the block texture array (shaders/terrain_particle.gdshader); was a CPUParticles3D node of 3D
  cubes per broken block. New BlockRegistry.st_particle (model #particle layer).
- 2x2 trees standing on air (user): 26.x placeBelowTrunkBlock under every trunk column (below_trunk_provider,
  rule-based soil_beneath_tree: dirt unless dirt / mud / moss / podzol) - was only on existing grass-like blocks.
- Fancy oaks far too tall (user): real Java FancyTrunkPlacer (trunk floor((h+2) * 0.618), limbs with treeShape,
  free-space checks, 0.381 slope to the trunk, branch trimming below 20 %) in GDScript + native (float32 maths as
  Java); was a full-height straight trunk with 1-3 random branches.
- Structures buried in terrain (user): Java Beardifier (beard_thin / beard_box / bury / encapsulate kernels) added to
  final_density per block in both engines from the rigid pool pieces of structures referencing the chunk (starts now
  computed before the noise, Java STRUCTURE_STARTS). Jigsaw junctions are not recorded yet (their 0.4-weighted
  beards are missing). nativecheck density / decorate 0 diffs.
- Straw bed texture garbled (user): block textures larger than 16 px were shrunk to 16 px (nearest), so the 64-px
  straw_bed with quarter-pixel UVs sampled every 4th texel (also 32-px shelves, dried ghast tentacles, shelf mushroom).
  The GPU texture array now uses the largest native size (64) and enlarges 16-px textures by exact pixel copies (mip
  2 of an enlarged layer = the original: 16-px blocks render identically); CPU copies stay 16 px, item icons sample
  the native-resolution image (AtlasBuilder.hires / layer_px). Screenshot-checked both bed orientations.
- Plants re-checked in a generated savanna (seed 12345 near -800, 128, -224): grass / flowers blend with the ground
  like the user's vanilla reference (flat light from their own cell, no AO, no directional shade).
- Advanced video settings (Video Settings > Advanced...): chunk builder threads (Auto / 1-16), fast-core pinning,
  smart leaf culling, face merging, occlusion culling, face-direction culling - all switchable at runtime (mesh options
  rebuild loaded chunks).
- Title logo: the project's own logo (res://logo.png, "Minecraft GDScript Edition") replaces logo + edition strip,
  300 GUI px wide (word about the vanilla logo's size), splash anchored to its right edge.
Dev probes added: --cmds="setblock+x+y+z+block;fill+..." (commands before the screenshot, '+' = space),
--blockmesh=x,y,z (quads inside a block with per-vertex brightness + neighbour flags), --waterscan=x0,z0,x1,z1
(air pockets / plants under air / lava touching water, waits for chunk work), --regionhash=cx0,cz0,cx1,cz1 (per-chunk
block hashes + log counts + surface lava: generation / reload determinism). Data probes run with --headless (no
fullscreen window competing with the user's own testing). --dumpcol=x,z0,z1,y0,y1 (blocks + stored / recomputed biome), --meshprobe=cx,cz,g (border faces, top
face coverage, translucent buffer order), --remesh=1, --auditat=x,z, --uiclicks="x,y;..." (real clicks),
--uiclose (close an options sub-screen), --uihover prints the hovered control's tooltip.## Perf round 4 (2026-11-12, user: "as close to 800 as possible, lows 100-200")
Measured first (release ARM64, 2880x1800 borderless, Firefox/Discord in the background):
- Engine floor (`--emptybench --emptykeep`, our BG_KEEP setup): median 1,200-1,400 FPS, GPU 0.53 ms; 3D disabled
  (`--empty2d`): GPU 0.17 ms but frame time no better (~0.7 ms present/engine floor). Vulkan (`--rendering-driver
  vulkan`): no better than D3D12 (flight 348 vs 359).
- Flight GPU split (`--gpu-profile`, averaged by scratch script): TerrainRD pass (terrain + sky + water + clouds)
  1.79 ms, tonemap 0.40, prepass 0.08, Godot opaque 0.04, canvas 0.06 (+ unprofiled blit / present ~0.3).
  Experiments: cheaper terrain vertex shader -0.01 ms, flat fragment shader -0.14, all terrain vertices degenerate
  (no raster) 1.43 (so ~0.86 ms is the vertex stage = vertex / index data, ~0.36 raster + shading), no terrain draws
  0.58. Clouds: off -0.26 ms, without colour writes -0.01, all cloud vertices off-screen -0.24 -> cloud cost is
  rasterising ~37k faces (slivers near the horizon), inherent to drawing vanilla's clouds identically.
Applied (pixel-identical; screenshot A/B: land identical, only moving entities differ, same as run-to-run):
1. 16-bit indices: one shared 16384-quad index pattern (192 KB, cache-resident) + base vertex per indirect command
   (was a 77 MB page-wide 32-bit index buffer streamed per draw): terrain pass -0.056 ms (`--trhide=1024` = old).
2. Per-section culling for opaque / cutout: tr_pack buckets quads per (direction, 16-block section), direction-major
   (a visible direction stays one range); the culler drops sections outside the frustum or not reached by the
   occlusion graph (was per 64-block group). Quads drawn 485k -> 445k, commands 2,036 -> 2,148 (`--trsec=0` = old).
   Translucent keeps its per-group buckets (blend order unchanged).
3. One render pass for terrain + sky + water + clouds (POST_OPAQUE; Godot draws nothing between): measured neutral,
   kept (`--trmerge=0` = two passes).
4. Random-tick list rebuild time-budgeted (8 % of the frame time, 0.25-1.5 ms) and no longer restarted by every newly
   ready chunk while flying (a never-finishing rebuild ended in a synchronous one: up to 5.3 ms in one frame).
Result: flight F avg 385 -> 452, median 402 -> 480 (1 % low 120-134, 0.1 % low 68-90 = run noise range);
play P avg 392 -> 437, median 407 -> 446, 1 % low 160-165.
Measured, not applied: core-cluster pinning (main thread / workers on separate L2 clusters, `--pin=1|2|3`): workers
pinned off the main cluster made lows much worse (1 % low 126 -> 81); main-only neutral.
Spike attribution tools: `--trace=1 --slowms=N` spike lines now carry main-thread CPU time (thread cycles) and a fixed
GDScript speed probe per frame: slow frames are real work (CPU time = wall time, probe normal), e.g. random-tick
handler bursts (rare grass ticks ~290 us), trial spawner / creaking scans (2-6 ms), player tick (1-2.7 ms), commits.
Bug fix (user report): giant spruce / pine crowns were a 2x2 column (radius formula wrong for radius 0) -> Java
MegaPineFoliagePlacer (floor(depth / crown height * 3.5) float32 growth, +1 on even rows, x+z>=7 / circle skip) in
Trees and native featx. Screenshot-checked in an old growth spruce taiga (seed 12345 near 288, 160).
## Perf follow-up (2026-11-12 night): spikes, collision, vertex streams
- Spike attribution (`--trace=1 --slowms=N` now also lowers the per-frame [spike] log threshold; entity tick logs
  the slowest entity, `_tick()` logs leftover-phase finish time and phase-0 parts): entity step 9-12 ms in one frame
  (villagers ~1 ms each, pigs ~0.7-1.5) because the pass was cut into 3 equal slices.
- Entity pass is now time-budgeted (ENT_BUDGET_US 1 ms per frame across the frames until the next tick; the next tick
  finishes any rest, same semantics). Entity spikes in the traced run: 10-12 ms -> within budget.
- Collision: `Collision.gather` reads chunk sections directly when the getter is the world's state_at (one chunk
  lookup per column instead of 3 calls per voxel), caches boxes per entity / player keyed by integer region +
  `ChunkManager.block_epoch` (bumped by set_block, every chunk commit and eviction), and the clip / step-up solver
  is native (`RecraftNative.coll_move`, float32 vector storage like Godot). Test: 3000 random scenes native ==
  GDScript (195/195 tests).
- Planar vertex streams for TerrainRD (8-byte positions + 12-byte attributes, `--trplanar=1`): measured neutral on
  Adreno X2 D3D12 (GPU 2.15 vs 2.11-2.20 ms) -> kept off. Terrain stays geometry-bound (~1.4 M triangles).
- Bench now (Firefox in background): F avg 410 / median 454 / 1 % low 101 / 0.1 % low 68 / max 21.8 ms;
  P avg 372 / 1 % low 157 / 0.1 % low 96. Remaining >8 ms frames are mostly whole-system slowdowns (sky 0.15 ->
  1 ms, draw 5-7 ms in the same frame), random-tick handlers (capped 1.5 ms/frame), trial spawner scans.
## UI round (2026-11-12): Minecraft_UI_Final_Stage_26_3.md, Gates 0-1 (+ parts of 2-3)
Tracking files: `docs/UI_SCREEN_MANIFEST.csv` (every route family, tagged, honest status), `docs/UI_PARITY.md`,
`docs/UI_REFERENCE_GAPS.md`, `docs/UI_LAYOUT_DECISIONS.md`, `docs/UI_SCREENSHOTS.md`; smoke test
`tests/ui/ui_all_routes.ps1` (20/20 routes open without script errors and screenshot). `--test --vanilla` 194/194.
Foundation (scripts/ui/widgets/): `McButton` (Java button text + renderScrollingString), `McW` (cycle / on-off /
EditBox / TabButton / place()), `McSlider`, `McList` (AbstractSelectionList: list bg, separators, outline, scroller,
row widgets, clipping), `UiKit.nine()` (nine-slice from each sprite's .mcmeta, pre-scaled per GUI scale: borders were
1 screen px instead of 1 GUI px everywhere), `UiKit.background()` (blurred panorama / world + menu_background or
inworld_menu_background at 32 px), `PanoramaBg` (one panorama for all out-of-game screens; images from the launcher
asset index - the 26.3 jar holds 1x1 placeholders), `McConfirm`, `OptionsSub` (OptionsList shell + Settings bindings).
Screens rebuilt on vanilla geometry and screenshot-checked: title (logo/edition/splash/rows/icons), Select World,
Edit World, delete confirm, Create World (Game / World / More tabs, one model), Superflat + Presets (installed preset
data), Single Biome, Game Rules (create + runtime), Game Menu (26.3 grid), World Options (General / Multiplayer, LAN
via Net.host/stop), Options root, Video (26.x sections), Music & Sounds, Controls, Mouse, Key Binds (categories,
per-row Reset), Accessibility, Skin, Chat, Online, Language (all installed languages, live `Res.set_language`),
Resource Packs (two transferable lists). Unimplemented vanilla options are disabled with the reason in a tooltip.
Later the same night: vanilla tooltips everywhere (tooltip/background + frame sprites, Java positioning, 170 px wrap,
F3+H advanced tooltips), recipe book rebuilt (tabs by recipe category, craftable filter, search, slot / page sprites,
all recipes with red uncraftable slots), container slot highlight sprites + empty-slot silhouettes, Death screen
(death.* messages with the killer, score, 1 s button delay, chat death message), Multiplayer (saved servers, LAN
section, Edit Server / Direct Connection / delete confirm, connecting overlay), HUD checked in a survival probe
(--screen=hud). Probes: --screen=hud|death|world_options, --hover=gx,gy, --ui=multiplayer, --uihover=gx,gy.
Then: Statistics (General / Items / Mobs, Java time / distance formatters), Advancements (window + tab sprites, Java
TreeNodePosition layout, visibility evaluator, connectors, backgrounds, drag panning), world icon auto-capture
(icon.png 64 x 64 from the world without GUI, 2D disabled for that one frame).
Next: chat / sign / book editors audit, chat settings, skin layer toggles, ghost recipes, attribute tooltip lines, HUD
overlays audit (chat, titles, boss bar, toasts, effects).
## Night round (2026-11-11/12): stutters, sky / clouds, leaves, user bug list
User asks (in order): perf first (target ~800 FPS base, no stutters, no visual change), then bugs (waterlogging,
leaf blobs, igloo biome + basement, menu V-Sync cap, ice gap strip, door hitbox, snowy grass, leaf litter placement /
z-fight / colour, smooth lighting, inventory crash), then execute `Minecraft_UI_Final_Stage_26_3.md` fully.
Done:
- Stutters: every 20-40 ms "stall" in the flight bench was a `print` (stdout redirected to a file blocks 1-40 ms on
  this machine; proven with thread cycle counters: the main thread was not running). Bench logs are buffered and
  printed after the run; unimplemented-mob messages are `print_verbose` once (they were a chat message + print per
  spawn); chunk entities are created a few per frame (`EntityManager._drain_deser`); rig part meshes are cached.
- First-use hitches: screen scripts compile on a background thread at world start (inventory 41 ms -> 0), the
  inventory player preview is one pre-rendered SubViewport (`InventoryPreview`), item icons are built in the
  background after spawn (0.8 ms/frame). Play scenario P (walk + edits + inventory + autosave): max 68 -> 11 ms.
- Autosave: level / map files are written on the saver thread; `SaveManager.flush` holds its mutex only for a
  snapshot (chunk loads on workers no longer wait for region writes).
- Thread priorities: main thread above normal, chunk workers / saver below normal (`--noprio` to compare).
- Native TerrainRD page allocator (best fit, merging; was GDScript first-fit lists).
- Sky: `SkyRD` draws Java's sky (per-pixel port of the verified sky shader, stars, dark disc last) inside TerrainRD's
  render pass behind the terrain; Godot's sky pass is gone and the environment uses BG_KEEP (no colour clear: the
  sky writes every uncovered pixel). GPU: Godot opaque pass 0.41 -> 0.04 ms, sky pass 0.29 -> ~0.02 ms.
- Clouds (were missing): Java 26.3 CloudRenderer port - clouds.png cells 12x4x12, native near-to-far face list
  (`cloud_faces`), vertex pulling with clouds.vsh face shades, alpha fade to the cloud distance, cloud height 192.33 /
  colour from the dimension attributes + timeline + rain / thunder (ClientLevel.getCloudColor). Options: Clouds
  (default fancy), Cloud Distance (2-128 chunks, default 128). Faces are CCW-outward -> pipeline front face CCW.
- Leaves: same-state self-culling removed (generated leaves share one state, so every leaf-leaf face vanished:
  see-through, patchy canopies). Now vanilla cutout leaves except faces that are only visible through two leaf
  layers in line (neighbour leaf backed by leaf / occluder), kept at the padded range edge. ~25 % more terrain quads
  than the old (wrong) culling.
- Inventory click crash: `inv.set_slot.bind(i)` called set_slot(stack, i) -> `Inventory.setter(i)`.
- Benchmarks: scenario `P` (play), `--fy=` fixed flight altitude, `--fpitch=`, `[trd]`/`[sky]` end-of-run lines,
  `--skydbg`, `--trhide=32` (no terrain draws), `--bgkeep=0`, `--skyrd=0`.
Bug list (same night):
- Waterlogging: seagrass, tall seagrass, kelp(_plant), bubble columns count as waterlogged (Java: fluid state is
  always a water source) -> drawn inside water (no air gap), swimmable, flowing, leave water when broken.
- Leaf litter: tree `place_on_ground` decorator now Java PlaceOnGroundDecorator (air / vine above, solid-render
  ground, MOTION_BLOCKING_NO_LEAVES <= y + 1) in GDScript + native (was: any full-collision block incl. leaves);
  patch_leaf_litter already required grass. Colour: Java dry foliage tint (26.x colormap/dry_foliage.png + biome
  dry_foliage_color) through a 4th tint layer (native `tints` 9 args -> 1024 colours, mesher F_TINT_DRY); it was
  using the grass tint. No z-fight seen (model plane 0.25 px above the ground like Java).
- Igloos: biome checked at the exact WORLD_SURFACE_WG stub height (igloo, desert pyramid, jungle temple, swamp hut:
  Java onTopOfChunkCenter) instead of the interpolated surface estimate; igloo pieces and end city "overwrite"
  pieces place template air (Java STRUCTURE_BLOCK ignore only) so the basement is carved out of the terrain.
- Menus: 60 FPS cap + V-Sync while no world is loaded (Java getFramerateLimit); worlds use the player's settings.
- Smooth lighting: Java AmbientOcclusionFace for full-block faces - shade 0.2 per full-collision sample (sides,
  corner, block in front) averaged over 4 (AO 1.0/0.8/0.6/0.4, was 1.0/0.85/0.7/0.55 without the front sample),
  corner takes side A when both sides block view, Java blend() light (zero samples take the front light), fixed
  0-1-2/2-3-0 triangulation (no AO flip). Native == GDScript (`--nativecheck` 0 mismatches).
- Trees: Java CherryTrunkPlacer + CherryFoliagePlacer (branches, hole chances, hanging leaves) and a columnar
  poplar (26.x placer not public: APPROXIMATION from the JSON parameters, leaf lobes on branches); both run in
  Trees (GDScript; marked non-native in FeaturesNative).
- Doors: tests added - collision boxes equal Java DoorBlock shapes for all facings / hinges / open, and a player walks
  through an open door in a 1-wide doorway (both pass; no bug reproduced).
- Ice strip: fresh-world audit (`--audit=1`) finds 0 unfrozen surface water in freezing biomes (572 frozen columns);
  not reproduced (older chunks / runtime cause still open).
- Snowy grass: audit finds 0 snowy grass without snow and 0 grass under snow without snowy=true.
Open: random block model variants (grass / stone / dirt rotations; plan: chosen in the shader so greedy merging
stays), AO for non-cube models, occlusion culling (hiding y < 64 saves 0.43 ms of the 1.2 ms terrain pass),
full-frame RD renderer, UI document.
Measured GPU per frame now (2880x1800, Firefox using ~7 % of the GPU in the background): prepass 0.08, Godot opaque
0.04, TerrainRD opaque + sky ~1.3, translucent + clouds 0.27-0.3, tonemap 0.42, canvas 0.06. Terrain draws alone
~1.0 ms (vertex bound: flat fragment shading saves only 0.2). Flight F median ~385, P 1 % low 157.
800 FPS (1.25 ms) is below Godot Forward+'s own fixed cost (~0.6 ms of passes we cannot remove) plus the terrain;
reaching it needs a full-frame RD renderer (terrain, sky, entities, particles, hand into one RGBA8 target shown by
the canvas) - noted as the next large perf step.
## Visual parity round (2026-11-11 evening) — from the vanilla 26.3 shaders / data in the user's jar
Source of truth: the jar's assets/minecraft/shaders (fog.glsl, terrain.vsh/fsh, sky.fsh, stars, lightmap.fsh,
texture_sampling.glsl) and data (timeline/day.json, moon.json, dimension / biome visual attributes), dumped for local
reference with `-- --dumptext=<path>` / `--listraw=<dir>` (never copied into the project).
Done:
- Fog = fog.glsl exactly: max(linear spherical env fog, linear cylindrical render-distance fog), mixed in sRGB,
  per-vertex distances (TerrainRD) / shaders/mc_fog.gdshaderinc (voxel, entity, particle); Godot fog disabled. The old
  smoothstep spherical fog hid in-range chunks when flying high ("cuts off very soon").
- Sky = SkyRenderer geometry evaluated per direction (shaders/sky.gdshader): sky disc fan y16 r512 with sky.fsh fog,
  dark disc below the horizon, fog colour clear, sunrise fan (exact 16-triangle geometry), sun / moon quads (30 / 20
  at 100) with the 26.3 textures (environment/celestial/sun, celestial/moon/<phase> — the old paths no longer exist:
  the game drew flat white discs), stars = SkyStars mesh (LegacyRandom 10842, 1500 quads, additive, far depth).
- Day cycle = Timeline (scripts/world/timeline.gd) + SkyState (scripts/world/sky_state.gd): keyframed sky / fog /
  cloud colour multipliers, sky light colour / factor, star brightness, sunrise colour, eased sun / moon / star
  angles, moon phase; gaussian biome colour blend (CubicSampler); FogRenderer colour (sunrise tint, sky blend,
  weather, void).
- Lightmap = lightmap.fsh exactly (native `lightmap`, 16x16 texture, sampled per vertex like terrain.vsh); inputs from
  timeline / attributes. ESTIMATED code constants: BLOCK_LIGHT_TINT (1, 0.76, 0.47), NIGHT_VISION_COLOR white.
- Held / dropped block items tinted (grass / foliage / constant); in-game Options from the pause menu fixed (was a 0x0
  child of the pause menu); Esc in Options = Done.
Open parity items: texture sampling (sampleNearest / RGSS edge AA), chunk fade-in (ChunkVisibility), smooth light at
quarter levels (mesher rounds to whole levels; Java keeps .25 steps), clouds (not rendered at all), entity directional
light (light.glsl), join stutter, worldgen feel / tree spacing, generation speed.
Benchmark note: the user ran horizon-client from ~19:58; GPU numbers after that are contaminated (empty scene 632 -> 311
FPS). Re-measure with nothing else running.

## Performance round 3 (2026-11-11, absolute target) — current status
Flight benchmark F (`tools/bench.ps1 -Scen F -Extra "--fsecs=40"`), ARM64 release, RD16/SD12, V-Sync off, Forward+:

| configuration | FPS avg / median | 1% / 0.1% low | GPU (viewport) |
|---|---|---|---|
| start of round 3, native 2880x1800 borderless | 144–164 / 152–176 | 60–66 / 40–46 | 3.7–4.2 ms |
| **now, native 2880x1800 borderless** | **358–363 / 380–385** | 105–107 / 63–71 | 2.40 ms |
| **now, 1440x900 window** (`--res=1440x900`, non-native) | **634 / 718** | 131 / 76 | 1.39 ms |
| **now, native borderless + Render Scale 50 %** (`--rscale=50`, in-game Video setting) | **508 / 581** | 107 / 56 | 1.51 ms |
Static A (native): 335 / 350 FPS (was 146–166). Streaming unchanged: ~65 chunks/s, no holes, 0 s frozen.
Tests after all changes: vanilla 191/191, placeholder 103/103, `--nativecheck` all equal (incl. new rt_leaf_filter).

What changed (round 3):
1. **TerrainRD** (`scripts/world/terrain_rd.gd` + `native/src/terrain_render.cpp`), Video setting "Terrain Renderer"
   (default RenderingDevice; "Godot meshes" fallback, automatic with MSAA or without the native library): chunk
   groups packed on the mesh worker (tr_pack: 20-byte vertices, 7 face-direction buckets), uploaded into 64 MB vertex
   buffer pages (first-fit free lists, group slot per vertex -> origin buffer), one native cull per frame (SoA
   frustum test, 16-bit radix sort, Sodium-style direction culling) writing indexed indirect commands; one indirect
   draw per material per page via CompositorEffects (opaque/cutout POST_OPAQUE, translucent POST_SKY). ~9 draws total.
2. **First-person hand in the main view** (ViewModel): was a full-screen SubViewport = a second complete Forward+
   render every frame (~1.1 ms GPU, invisible to the viewport GPU timer). Now VIEWMODEL shader variants
   (shaders/viewmodel.gdshaderinc: fixed 70° FOV, depth packed in front of the world).
3. Main thread: block-entity index (BlockEntities.chunks_with) instead of per-tick scans of every chunk's block entities
   (furnaces, spawners, signs, command blocks, beacons); one tick phase per frame at high FPS, block updates split
   (scheduled / random sampling); cached random-tick chunk list (in-place refresh); native leaf-support filter
   (rt_leaf_filter, ~115k GDScript leaf searches/30 s -> ~200); leaf-support cache (Chunk.leaf_ok); chunk snapshot
   cache (Chunk._snap); dispatch batching (≤1 pass / 4 ms while workers are saturated), wake only expired timers and
   as many update waiters as free slots; adaptive mesh-upload budget (20 % of frame time); doAnimateTick block sampling
   native (anim_sample).
4. `rendering/rendering_device/vsync/frame_queue_size=3` (project.godot): CPU may run 2 frames ahead of the GPU.
   1440x900: 557 -> 607 avg, 1% low 121 -> 137, max frame 31 -> 15 ms; native (GPU-bound) unchanged. Cost: one more
   frame of latency when GPU-bound (~1.6 ms at 600 FPS; ~16 ms with V-Sync at 60 Hz).
5. Vertex-buffer fetch for TerrainRD (attributes instead of storage-buffer pulling): static terrain pass 1.93 -> 1.62 ms.
6. TerrainRD with MSAA (draws into the multisampled buffers; pipelines per sample count) — no Godot-mesh fallback needed.
7. Parity fix found on the way: held / dropped block items now carry Java's item tint (grass 0x91BD59, foliage 0x48B518,
   constant leaf tints) — they were grey (block_item_mesh ignored tints).
8. Spike work spread over frames: random-tick list rebuilt incrementally (6 rows/frame, old list used meanwhile),
   one tick's sampling in 220-chunk slices (rt_sample_range: same stream/order), entity phase in ~3 slices
   (EntityManager.tick_begin / tick_slice, per-entity interpolation time `Ent.tick_us`), dispatch work set and walk
   share an adaptive budget (15 % of frame time). Native slow frames > 8 ms: dispatch 1.36 -> 0.62 ms, random ticks
   1.9 -> 0.13 ms, entities 1.47 -> 0.6 ms. Load test: ring 16 visible at 12.0 s (was 16.1 s).
Not reachable: 500 FPS at native 2880x1800 — GPU-bound (busy-wait test), Godot's fixed passes ~1.2 ms + terrain ~1.0 ms
(vertex-bound: flat fragment shader saves only 0.15 ms; hiding everything below y 64 saves 0.25 ms, so cave culling
would gain < 0.25 ms in this flight) + present.
Measured but rejected: exclusive fullscreen (no gain), separate render thread (worse + stutter), depth prepass off
(-0.06 ms), frame queue 3 (no gain).
Native GPU floor: Godot's own passes cost ~2.2 ms at 2880x1800 in-game (opaque clear/store 0.6–0.7, tonemap 0.7–0.8,
canvas 0.2, sky 0.3) — 500 FPS at native resolution is not reachable with Forward+ on this GPU (see PERFORMANCE_AUDIT).
Next: section visibility graph (cave culling), random-tick sampler without per-section GDExtension calls, Java leaf
`distance` state (leaves would then not random-tick at all), dispatch key-evaluation cost, x64 export + test.

## Performance round 2 (2026-11-11) — FPS and stutter (details + per-step table: PERFORMANCE_AUDIT.md)
Flight benchmark F, ARM64 **release** build, borderless 2880x1800, RD16/SD12, V-Sync off:

| | start of round 2 (editor/debug, 1920x1080 window) | now (release, Forward+) | now + Mobile renderer (tested, NOT default) |
|---|---|---|---|
| FPS avg / median | 124 / 187 | 144–164 / 152–176 | 170 / 188 |
| 1% / 0.1% low | 18.6 / 11.6 | 60–66 / 40–46 | 50 / 40 |
| frames > 33 ms / max frame | 127 / 149 ms | 0 / 28–30 ms | 0 / 26 ms |
| GPU / render CPU per frame | 3.0 / 0.9 ms (1080p) | 3.7–4.2 / 0.8–1.2 ms | 2.4 / 1.0 ms |
| streaming during flight | no holes, 61 chunks/s | no holes, 55–63 chunks/s, 0 s frozen | no holes, 60 chunks/s |
Static A (fully loaded, release, 2880x1800): Forward+ GPU 5.4–6.1 ms (2.3 M triangles, 1,759 draws); Mobile GPU 3.05 ms
(798 draws: Forward+ draws everything twice for its depth prepass). Run-to-run noise on this laptop is ±10–15 %
(heat after back-to-back runs): compare A/B pairs, not single runs.

Applied this round (all in the code now):
1. Release export path (official templates) — the editor binary is a debug build whose per-access object validation
   (global ObjectDB lock) made worker GDScript stall the main thread: tick cost in slow frames 28 → 13 ms.
2. **Phased game tick** (`WorldManager._tick` / `_tick_step` / `_tick_continue`): phase 0 (time, weather, input,
   player, portals, mining, item use) when due; phases 1–5 (particles, entities, block updates, redstone +
   block entities + beacons/commands/raids, trials/sculk/creaking/commands + origin) on the following frames, ≤1.5 ms
   per frame, always finished before the next tick. Entity render interpolation uses the entity phase's own time
   (`EntityManager.last_tick_us`).
3. **grass_block opacity fix** (block_registry: full-cube transparency from base faces only; overlays are blended in
   the shader). Grass blocks were "cutout": passed skylight, didn't cull neighbours, grass spread under grass
   (12,000 bogus block changes/min). Changes F_OPAQUE for grass_block → may change feature output vs older builds.
4. ChunkManager dispatch: event work set + idle set (+ band un-idle on centre move), cached priority order per
   (radius, 32 look directions), 1 ms time slices with cursor, queued unloads (6/frame), inlined neighbour checks.
5. Copy-on-write section snapshots (`Chunk.Section.shared/_unshare`; snapshot / frozen_copy hand out references).
6. Mesh RID destruction queued (4+/frame; D3D12 buffer frees are slow on the main thread); meshes freed at shutdown.
7. Random ticks: native per-cell sampler `RecraftNative.rt_sample` (same xorshift stream/order), hits handled spread
   over the frames of the tick (≤1.5 ms/frame), kind-table fast paths for grass/mycelium and leaves.
8. BERender (block-entity renderer): scan on load/change only, node sync on change, only lids/flags animate per frame.
9. `BlockEntities.tick_furnaces`: cached list of chunks with block entities (was a walk over all 1,369 chunks/tick).
10. Benchmarks/tools: fps_bench.gd (F/A), frame_probe.gd, tools/bench.ps1, tools/profile.ps1 + profiler_server.gd,
    export_presets.cfg; load test now forces V-Sync/caps off.

Tested but NOT applied (the switch was interrupted): **Mobile renderer** (`rendering/renderer/rendering_method="mobile"`,
features "Mobile") — flight GPU 4.17 → 2.42 ms, avg 144 → 170 FPS; the world only uses sky background, linear
tonemap and depth fog (all supported by Mobile); needs a visual A/B screenshot check before switching. Also not
applied: `_dispatch` early return when `_inflight >= max_jobs + queue_depth` (dispatch is still ~0.9 ms/frame during
flight because a capacity-limited pass walks complete chunks first).

Verification status: vanilla tests 191/191 after the phased tick (ARM64 editor). Placeholder tests (103) and
`--nativecheck` were last run BEFORE the grass-opacity / copy-on-write changes — rerun both. x64 release preset exists
but was not exported/tested this round.

Where a flight frame goes now (release, Forward+, averages): process phase ~3.0 ms (world_manager 2.6–3.0: ticks
1.2–1.4 spread, chunk_manager 1.3–1.4 = dispatch 0.9 + commit 0.3 + upload 0.25; other nodes 0.15–0.18) + draw
phase 2.7–3.4 ms (render CPU 0.8–1.2 + waiting on the GPU) — median frame 5.3–6.6 ms. Target 600+ FPS = 1.67 ms.

Next plan (largest measured costs first):
1. (Renderer stays Forward+ — desktop-only app, user decision 2026-11-11. Mobile was only a measurement.)
2. Dispatch early return when the queue is full; then dispatch only from the work set while loading.
3. Upload path: build Godot's packed surface buffers natively on workers and call `RenderingServer.mesh_add_surface`
   with ready byte arrays (main-thread `mesh_add_surface_from_arrays` packing ~0.25 ms/frame); compact vertex format
   (CUSTOM0 RGBA float 16 B → one packed 32-bit value: base layer 12 bit, overlay 12 bit, sky 4, block 4; positions /
   UVs 16-bit).
4. GPU (Sodium-style): per-direction face groups (draw only faces facing the camera), section visibility graph
   (cave culling, native flood fill per section in the mesh job + native BFS per camera-section change); hiding all
   underground groups only removed 15 % of triangles from the surface, so directional culling + vertex size +
   fragment cost (pow() sRGB conversion per pixel, leaves alpha-test overdraw) matter more there. Use
   `--gpu-profile` to split GPU passes.
5. Tick cost (~7 ms per tick total, now spread): leaf-decay BFS 29 µs/call (port TreeFeature.updateLeaves +
   LeavesBlock distance updates → O(1) decay check), AtlasBuilder.tick (animated textures, ~2.4 ms per tick in the
   debug profile), random-tick list building (625 chunks per tick), particle block sampling (667/tick, could be
   spread), entity ticks.
6. Remaining GDScript features/structures on workers (contention; 6+ workers don't help even on ARM64:
   5 workers 50.9 chunks/s, 8 workers 62.8 chunks/s but worse frames).
7. Fidelity notes found on the way: generated leaves carry distance=7 (vanilla sets 1–6 via updateLeaves), so poplar
   canopies decay heavily right after generation.

ARM64 vs x64 (load test, debug editors): ARM64 native 50.9 chunks/s, full RD16 26.9 s; x64 emulated 37–40 chunks/s,
34–37 s. Debug-build GDScript contention exists on ARM64 too (features 22 → 41 ms/chunk at 8 workers).
## Performance round 1 (2026-11-11, overnight) — chunk generation, real game, RD16 / SD12
| | before (11-10) | now (11-11 05:30, 5 workers) |
|---|---|---|
| spawn ready | 9.2 s | 1.5 s |
| ring 1 / 2 / 4 / 8 visible | 19.3 / 33.9 / 80 s / – | 1.8–2.6 / 2.8–3.1 / 4.6 / 10.8 s |
| full RD16 visible | not within 240 s | 34.5–37 s |
| generation throughput | 2.9 chunks/s | 39.7 chunks/s |
| walk 5.6 m/s: chunk wait on entering ring 4 | median 11.5 s | 0 ms (all visible) |
| fly 22 m/s: ring-2 incomplete samples / p90 wait | 76 % / 3.7 s | 0 % / 0 ms (nothing missing) |
| teleport into unexplored terrain: ring 0 / 1 / 2 | 14.4 / 45.4 s / – | 0.7 / 1.1 / 1.5 s (ring 1: 0.9–1.6 s across 6 destinations) |
| frame avg / p50 / p95 (entry) | 71 / – / 182 ms | 12.3 / 8.5 / 27 ms |
| teleport / autosave stall | 771 ms / ~700 ms every 2 min | ~110 ms / none (background saver) |
| per chunk in game: generate / features / decorate | 556 / 312 / 28 ms | 22 / 28 / 1.6 ms |
| main thread script time per frame | ~65 ms | ~7 ms |
Root causes found (measured, not guessed): (1) GDScript stops scaling past ~4 threads under x86-64 emulation —
method calls, member reads and allocation contend globally (contention_probe: x5–x21 at 8 threads, even on
thread-local objects), native code scales x1.0; (2) `Redstone.flush` evaluated power for every neighbour of every
random-tick block change (43 ms/frame); (3) random ticks rescanned 15 000 section palettes per tick and treated copper
ore as tickable (46 ms/frame); (4) `Structures.first_free_height` looped forever when the surface sat at a search
window top — a worker hung permanently and its chunks never appeared; (5) structure sets were scanned once per
generation step (3x); (6) unload / autosave encoded ~1000 chunks synchronously (700 ms stalls); (7) workers waited a
frame for every job; (8) look-ahead bias delayed inner rings when standing still.
Native (bit-exact, verified by `--nativecheck` on seeds 12345 and 777): lighting, meshing, biome tints, density
functions + noises, fill/aquifer, surface rules, carvers, climate biomes, chunk packing/heightmaps, decorate, feature
region + 174/211 placed features (placement chain incl. noise counts + ore/scattered_ore, vegetation patches, block
columns, simple blocks, selectors, disks, multiface, piles, vines, underwater magma, springs, dungeons, lakes,
speleothems, trees with all trunk/foliage placers and decorators — Godot's SortArray ported for exact tie order —,
fallen trees, huge mushrooms, speleothem clusters), structure candidate scan, first-free-height columns, jigsaw shuffles and box tests. Other fixes:
inlined random-tick sampling, table-driven leaf decay search, inlined particle block sampling, per-pass snapshot reuse, structure-start
prefetch in generation jobs. Remaining GDScript in workers: trees, structure piece placement / jigsaw candidate loop,
noise providers, geodes, sculk, fossils, Nether/End features — the reason 6+ workers still do not help (GDScript
contention), so `max_jobs` is 5 (measured optimum; 6+ only raise frame times).
## Latest results (2026-11-10)
- 76 scripts compile; tests 79/79 placeholder.
- java_26_3 autoplay seed 777: **spawn 6.6 s** (was 32 s), 261 chunks in 90 s, frame median 8.3 ms / p95 33 ms, RD 12.
- Per chunk (single thread, machine speed varies ~2x with throttling): generate 430–870 ms (density 120–230, fill+aquifer 60–110, surface rules ~65–200, carvers 35–65), features ~330 ms, light 75–130 ms, mesh 40–150 ms.

## Done (2026-11-10, session 3)
- Dimensions: Nether + End fully generated from 26.3 data (legacy random sources, noise ranges 0..128, End islands
  with float32-exact height field, TheEndBiomeSource, nether_cave carver, disabled-aquifer fluid picker);
  per-dimension region storage (region / DIM-1 / DIM1), travel with unload/reload, sky/fog/ambient per dimension.
- Portals: nether portal frames (PortalShape), lighting (flint & steel / fire charge), breaking, linking via a
  portal index (POI equivalent, 16/128 search), creation + forced platform; End portal frames + eyes, End
  platform, End exit -> respawn point. Autoplay `--dim=the_nether|the_end` verified (arrival 4.6 s / 7.4 s).
- Features: 26.3 composite/new types (overlay, random_neighbor_spread, single_block_pillar,
  projected_random_patchy_square, stepped_column_cluster, netherrack_replace_blobs, delta_feature, huge_fungus,
  End island/spikes/chorus/gateway/platform/podium, coral, underwater_magma, blue_ice, iceberg, spike, block_blob,
  vines); placement: count_on_every_layer (exact), random_chance, randomly_selected, cuboid; height_range pred.
- Mobs: all 90 ids defined (stats, behaviour flags, box rigs); new AI archetypes in scripts/entities/mob_ai.gd
  (ghast, blaze, slime/magma split, shulker bullets, enderman stare/teleport, group anger, flyers, swimmers,
  guardian laser); fireballs; dimension-aware spawn rules (Java isDarkEnoughToSpawn, in_lava, in_water).
  Fixed: all mob models rendered rotated 180 degrees (Java rotY(180 - bodyYaw)).

- Structures (scripts/world/structures.gd, structure_template.gd, structures_legacy.gd, core/nbt.gd): NBT reader,
  templates from the jar (26.x {id, properties} palettes, Java block order, rotation, processors, entities, loot
  chests), random_spread + concentric_rings placement (lazy shared ring snapping), Java JigsawPlacement (stub +
  biome check before assembly, priority queue, free-space shapes, expansion hack) -> villages (107-112 pieces),
  outposts, bastions (85-90 pieces), ancient cities, trail ruins, trial chambers; templates: igloo, shipwreck,
  ruined portal, nether fossil, ocean ruin, end city (simplified); APPROX builders: stronghold (portal room),
  fortress, mineshaft, desert pyramid, jungle temple, swamp hut, buried treasure, ocean monument. Placed per step
  before features; loot tables unpacked on open/break; eye of ender flies to the nearest stronghold.
  Verified: savanna village at seed 777 (-297, -810) renders; spawn next to it 9.4 s.
- End fight (scripts/entities/dragon_fight.gd): podium, 10 crystals (heal, explode), dragon phases, damage
  reduction, death -> XP/exit portal/egg/gateway; gateways to outer islands (+ return links). Wither summoning
  (scripts/gameplay/summons.gd) with charge/skulls; iron/snow golem summoning. Entities in unmodified chunks now
  persist (save bug fixed).
- Redstone rewrite (directional emitters, repeaters, comparators, observers, pistons, dispensers/droppers,
  hoppers, rails) + update queue; workstations (scripts/ui/workstation_screen.gd, gameplay/enchanting.gd):
  enchanting/anvil/grindstone/smithing/stonecutter; brewing + potions (gameplay/potions.gd); villager trading
  (gameplay/trading.gd, ui/trade_screen.gd).
- Advancements (gameplay/advancements.gd, data-driven, toasts, pause-menu summary); statistics (mined/crafted/killed/
  play time); third-person player model (Java PlayerModel layout, installed default skin or custom skin file);
  /locate structure (placement + biome stub, like Java); docs/USER_GUIDE.md.
- LAN multiplayer (scripts/net/net.gd autoload, ui/multiplayer_screen.gd): Open to LAN from the pause menu,
  discovery broadcast, Direct Connect; host keeps chunks loaded around remote players (ChunkManager.extra_centers);
  verified by a two-process test: `--autoplay --gen=java_26_3 --fresh --seed=777 --nettest=host` then
  `--netjoin=127.0.0.1:25599 --nettest=client` (host block seen by client, client block/attack reach host,
  players and entity puppets mirrored).
- Cave features (scripts/world/features_cave.gd): speleothem + speleothem_cluster (dripstone and 26.x sulfur spikes),
  large_dripstone, root_system (azalea, sulfur springs), fossil (templates + processors). No unsupported feature
  types remain in 26.3 biomes. `/locate biome` searches the biome source (Java findClosestBiome3d) on a worker.
- Taming/riding (scripts/entities/taming.gd) and vehicles (scripts/entities/vehicles.gd): probes
  `--autoplay --gen=flat --ride=horse|pig` and `--vehicle=boat|minecart` (boat 8 m/s, horse ~9.5 m/s).
  Player hat layer now uses Java CubeDeformation (inflate) instead of a 9-px box (fixed a doubled head).
- Beacons (gameplay/beacons.gd, ui/beacon_screen.gd: pyramid levels, sky check, 80-tick effects, payment, beam;
  probe `--beacon=1`), composters (Java chances, bone meal), bells, villager levels (xp thresholds 10/70/150/250,
  two new offers per level).
- Commands rewritten (scripts/gameplay/command_parser.gd): execution contexts, full selector arguments, /execute,
  56 commands incl. scoreboard/team/tag/bossbar/title/tellraw/clone/fillbiome/advancement/loot/item/damage/ride;
  HUD titles, boss bars, scoreboard sidebar; data-pack functions (#minecraft:load / #minecraft:tick) from
  <world>/datapacks; command blocks (gameplay/command_blocks.gd, ui/command_block_screen.gd), probe `--cmdblock=1`.
- Non-living entities (scripts/entities/misc_entities.gd): primed TNT (flint/redstone/explosion chains), fishing,
  item frames, paintings, armor stands, lightning; probe `--misc=1`. Hanging entities use unshaded materials tinted
  by the block/sky light (lit StandardMaterial3D renders black: the scene has no lights by design).
- First-person hand + held item (scripts/ui/view_model.gd): separate SubViewport/World3D at Java's 70-degree hand
  FOV, Java renderPlayerArm / applyItemArmTransform / attack-swing / display transforms, extruded item meshes,
  view bobbing, swing on attack/use/mining. Probe `--hold=<item|none>`. Calibration: our extruded quad needs
  Y +90 instead of Java's -90 (u axis runs the other way), verified visually.
- Signs (gameplay/signs.gd, ui/sign_screen.gd): editor on placement / right-click (side facing the player),
  width-limited lines, dyes, glow ink, honeycomb wax; Label3D text on standing/wall/hanging signs, light-tinted.
  Probe `--signs=1`.
- Armor rendering (entities/armor_render.gd, Java HumanoidArmorLayer inflate 1.0/0.5 on installed equipment
  textures) on the player model, armor stands and mobs; mob armor equipment (Java populateDefaultEquipmentSlots),
  8.5% drops, helmets stop daylight burning. Probe `--armor=1 --third=1`.
- Books (ui/book_screen.gd): book-and-quill editing (100 pages x 1024 chars), signing into written books (title,
  author), reading screen on the installed gui/book.png, lecterns (place/read/turn pages/take, drop on break).
  Probe `--book=read|edit`.
- Maps (gameplay/maps.gd): empty map -> filled_map on Java's 128-grid, incremental column scans while held, Java
  MapColor bases + height/water-depth shading, per-map files <world>/data/map_<id>.bin, two-handed map view in
  first person, maps in item frames. Probe `--maptest=1`.
- Particles (gameplay/particles.gd, shaders/particle.gdshader): MultiMesh billboard particles from installed
  particle textures, Java animateTick emitters (torches, campfires, furnaces, portals, fire, redstone, lava,
  cherry leaves, candles), rain splashes, explosion/crit/heart/note/villager/bubble events. Probe `--particles=1`.
- Raids (gameplay/raids.gd): patrols with captains, ominous bottles -> Bad Omen -> Raid Omen at a village bell,
  Java wave tables by difficulty, raid bar, victory (Hero of the Village) / defeat, raiders attack villagers;
  evoker vexes + fangs, witch splash potions. Probe `--raid=1` (wave 1: 4 pillagers + captain).
- Spawners / trial spawners / vaults / wind charges (gameplay/trials.gd): dungeon spawners now have block entities
  (Java MonsterRoomFeature mobs + simple_dungeon chests), template trial spawner/vault/spawner NBT is captured,
  trial spawner state machine with installed configs, reward ejection and cooldown, vault keys (one reward per
  player), breeze wind charges and player-thrown wind charges. Probe `--trial=1`.
  Known: BlockRegistry.default_state picks the first permutation (vault default = ominous), not Java's default.
- MENU FIX (user-reported 2026-11-10): screens under the bootstrap CanvasLayer were 0x0 (full-rect anchors did not
  resolve), so Create New World had no visible button and the world list was empty. Screens now live in a
  viewport-sized host Control (bootstrap._set_screen). Dev flag `--ui=title|world_list|create_world|create_world_go`
  screenshots menus; create_world_go creates a world through the screen end to end (verified). In-game screens
  (open_screen) are sized explicitly too; probe `--screen=pause|inventory|options|chest`. Inventory now shows a
  live player preview (armor, mouse-follow) in the black box.
- Menu crawler (`--crawl`, spec 28): every menu screen and tab page must fill the window, every button must be on
  screen (scrollable areas: horizontally), non-zero and connected. First run found 55 problems (Create World
  World-tab dropdowns and Options Resources buttons off screen); now 126 controls, 0 failures.
- Creaking (gameplay/creaking.gd): heart states (uprooted / dormant / awake by Java isNight), protector spawning
  (5 attempts in 16/8, needs a survival player within 32), crumbles at day / beyond 34 / heart broken, invulnerable
  while bound, hits grow 2-3 resin clumps via Java's breadth-first log walk, freezes while watched. Probe `--creaking`.
- Tree decorators (world/trees.gd, Java TreeDecorator with the tree's log/leaf lists): trunk_vine, leave_vine
  (hanging vines), cocoa, beehive (Java height/side rules), alter_ground (podzol circles), attached_to_leaves
  (mangrove propagules with exclusion radius), creaking_heart (log enclosed by logs), pale_moss (hanging moss +
  pale_moss_patch), place_on_ground (leaf litter), shelf_mushroom (APPROXIMATE). Java DarkOakTrunkPlacer (shift +
  hanging ring logs) and DarkOakFoliagePlacer (pale/dark oak). Probe `--count=a+b` tallies blocks in loaded chunks.
- Armor trims: smithing_trim recipes from data (template + trimmable armour + trim material item), minecraft:trim
  component; rendered on players, mobs and armour stands with Java's paletted permutation (26.3 paths:
  palettes/trim_base key palette, palettes/<palette_id>, _darker variant on same-material armour). Tests 191/191.
- Bundles (gameplay/bundles.gd): Java weight rules (64 units, 64/max-stack per item, nested bundles 4 + contents,
  no shulker boxes), the four inventory click actions, newest-first removal, fullness bar, use to empty. Tests 190/190.
- Leads (gameplay/leads.gd): tie leashable mobs (not monsters/villagers/fish), fence knots, pull beyond 6 blocks,
  snap beyond 10, follow when near, 24-segment rope render, saved in mob data. Bottle o' enchanting: thrown at
  pitch-20 / 0.7, 3 + r(5) + r(5) XP on impact. Probe `--leadtest`.
- Brewing now uses the 26.3 data-driven minecraft:brewing recipes (280; item-aware input/reagent/output, container
  changes keep the potion); the hard-coded PotionBrewing table remains only for placeholder mode. Tests 188/188.
- 26.x special crafting recipes (gameplay/special_recipes.gd, parameters from the recipe JSON): transmute (bundle /
  shulker recolour keeping contents), leather dyeing (Java DyedItemColor.applyDyes), tipped arrows, firework stars
  (shapes, trail, twinkle, Java firework colours), fade stars, firework rockets (flight = gunpowder, explosions),
  banner duplicate and book cloning (source stays in the grid), tool repair (sum + 5%, curses kept), shield
  decoration, decorated pot. Tipped arrows apply their potion at 1/8 duration, spectral arrows mark targets.
  Tests 187/187. Map extending not supported (no map scales). Dyed leather: tinted icons (Java default #A06540 for
  undyed) and worn armour with the untinted overlay layer.
- Elytra (Player._travel_elytra, Java travelFallFlying): start with jump in mid-air, lift/dive physics, 0.99/0.98
  drag, FLY_INTO_WALL damage, durability 1 per 20 ticks, unusable at 1, 0.6-tall hitbox. Firework rockets: boost
  while gliding (Java attached rocket: look*0.1 + (look*1.5 - v)*0.5 for 10*(flight+1)+r(6)+r(7) ticks), ground
  launch (x1.15 / +0.04 acceleration, star explosions: spark balls, blast sounds, 5 + 2/star damage within 5).
  Totem of undying (either hand, Java effects, glitter particles, HUD item activation animation). Name tags
  (renamed tag names mobs, makes them persistent; nameplate when looked at). Probe `--elytra`. Tests 179/179.
- Java 1.9+ melee combat (EntityManager.player_attack): attack strength from ticks since swing / item change
  (20 / attack speed), damage x (0.2 + 0.8 f^2), enchantment bonus x f (Sharpness 0.5L+0.5, Smite / Bane /
  Impaling 2.5L by mob group), strong hits > 0.9 gate crits (falling, not sprinting), sprint knockback and sword
  sweeps (1 + Sweeping Edge ratio x dmg to mobs within 1 block of the target), Java LivingEntity.knockback, Fire
  Aspect, weak/strong/crit/sweep/nodamage sounds, sweep particle; crosshair / hotbar attack indicator (Video
  option). Probe `--combat`. Tests 177/177.
- Item use (gameplay/use_item.gd, Java LivingEntity using-item flow): eating/drinking take their Java durations with
  slowdown, particles and sounds (was instant); player bows (power curve, crit, Power/Punch/Flame/Infinity, ammo
  search, arrows stick and can be picked up), crossbows (charge, load on release, Multishot, Quick Charge), tridents
  (throw, Loyalty return, Riptide), shields (5-tick delay, 90-degree frontal cone, durability, axe disable, attacker
  knockback), spyglass zoom, bow FOV. Main hand first, offhand when the main hand has no use. First-person: Java
  eat/bow/crossbow/spear poses, bow/crossbow pulling sprites, offhand item rendering (left-hand display mirroring),
  3D shield model (icon, held, blocking pose). Probe `--usetest`. Tests 175/175.
- Loot 26.3 format fix (gameplay/loot.gd): 26.x tables use "modifier" (object/list, "type" key) and a single
  "condition" on pools/entries/functions; pool conditions and entry modifiers were previously ignored (zombies dropped
  rare items without a player kill, set_count/fortune/looting never applied). Now also: Java integer NumberProvider
  (uniform inclusive), random_chance_with_enchanted_bonus (LevelBasedValue), entity_properties (flags/type/vehicle/
  equipment), enchanted_count_increase, copy_components (container, banner patterns, custom name) with block-entity
  data captured before removal. Shulker boxes keep contents (creative too); placed items apply their components.
  Entity predicates: type_specific fishing_hook (Java calculateOpenWater 5x4x5 check: treasure only in open water),
  cube_mob size (slime balls only from small slimes), raider captain, sheep sheared/color components. Sheep now
  roll entities/sheep (previously forced to sheep/white: no mutton). Tests 171/171. Enchantment/advancement JSON
  formats audited against 26.3 (unchanged).
- Loom (ui/workstation_screen.gd + gameplay/banners.gd): data-driven patterns/tags, pattern items, 6-layer limit,
  Java layout (4x4 grid, scroller, preview); placed banners render their pattern layers.
- Special item models: icons (orthographic SubViewport with the base model's display.gui), held items
  (firstperson_righthand) and dropped items (ground) for chests, shulker boxes, heads, banners, pot, conduit;
  chest minecarts/boats show the chest model. Tests 168/168.
- Block-entity rendering (world/block_entity_renderer.gd): chests (single/double, normal/trapped/ender/copper, lid
  animation), shulker boxes (6 facings, lid), skulls/heads incl. piglin + dragon models, banners (standing/wall, sway),
  bell body, decorated pot, conduit shell. Registry now carries the Java props these blocks lack in blockstate JSON
  (chest facing/type, skull/banner rotation, wall facing, shulker facing). Double chests: Java placement pairing,
  unlink on break, Large Chest screen (54 slots, RIGHT half on top). Tests 160/160. Probes `--entblocks=<dist>`,
  `--screen=largechest`.
- Resource packs: folders/zips in user://resourcepacks with pack.mcmeta overlay assets/ (never data/) in priority
  order via JarAssetReader.overlays; Options > Resources lists and toggles packs (restart to apply). Tests 156/156.
- Recipe book (gameplay/recipe_book.gd + ContainerUI): toggle button at Java positions on the inventory and crafting
  table, craftable recipes (greedy ingredient assignment over inventory + grid), click fills the grid, paging,
  GUI shifts right like Java. Probe `--screen=crafting` (23 craftable, stone pickaxe filled).
- Horse inventory (ui/horse_screen.gd): saddle/armor/chest slots, E while riding or sneak-right-click; donkey/mule/
  llama chests; horse armor + saddle layers rendered from installed equipment textures; horse armor reduces damage.
  Probe `--ride=horse --harmor=diamond_horse_armor --hscreen=1`.
- Vehicle variants: chest/hopper/TNT/furnace minecarts and chest boats (contents, entity container screens, furnace
  fuel/push ~0.2 b/t, TNT priming by flint/activator rails/breaking, hopper item pickup). Probe
  `--vehicle=minecart --cart=furnace_minecart`.
- Sculk (gameplay/sculk.gd): vibrations (place/break/steps/drops/projectiles/explosions/containers, wool
  occlusion), sensors with distance-based power (lamp test), shriekers (warning 0-4, Darkness overlay, Warden
  summoning), Warden anger/sonic boom/digging. Probe `--sculk=1`.
- BlockRegistry: Java properties that no model uses (note block note/instrument/powered, daylight detector/target
  power, triggered, enabled, has_record, sapling stage, cactus/sugar cane/fire/kelp age, scaffolding distance)
  were missing entirely; added via extra_props. Tests 153/153 vanilla.
- BlockRegistry defaults now follow Java conventions (booleans false, ominous false, vault/trial spawner inactive,
  lit campfires/redstone torches).
- Perf: jigsaw/template fixes (DECISIONS D-PERF-JIGSAW): features 2.45 s -> 0.53 s/chunk near a trial chamber.
- Tests: 103/103 placeholder (12 command tests), 150/150 vanilla.
- Status estimate given to the user 2026-11-10: ~55-60% of the full spec (see docs/STATUS.md areas).

## Done earlier this session
Legacy carvers (cave/canyon from 26.3 carver JSON, `scripts/world/carvers.gd`), aquifer substance inlined, surface-rule batch hoisting, interval_all for GRADIENT + static bounds fallback, flattened NormalNoise, inlined RNG ops, relaxed light deps, worker cap, spawn radius 1 first.
