# STATUS (compact; resume from here + PROGRESS.md)

Godot 4.7.2 stable (Steam x64 build, runs under emulation on the ARM64 reference machine) · typed GDScript only ·
assets: user's local Java 26.3 jar (private cache, never redistributed).

## tested (automated, 2026-11-10)
- `--check`: 95 scripts compile, 0 errors.
- `--test` (placeholder content): 91/91 pass — previous suite plus legacy positional random, template rotation,
  BlockPos.withinManhattan order, float32 emulation, NBT parsing, portal coordinate scaling, mob-definition
  coverage of all 90 ids, End spike layout.
- `--test` 103/103 (adds command tests); `--test --vanilla`: 150/150 pass (adds Nether/End terrain, structure templates, redstone, enchanting, brewing,
  trading, advancements).
- LAN: two-process test (host + client on 127.0.0.1, java_26_3 seed 777) passes: modified chunk sync, block sync
  both ways, remote players, entity puppets, forwarded attacks.
- `--autoplay`: Overworld spawn 6.6 s; Nether arrival 4.6 s (warped forest, huge fungi, lava sea); End arrival 6 s
  (platform, 10 spikes with cages/fires, podium, crystals, dragon); savanna village at seed 777 (-297, -810).

## working
Asset import · block model baker · texture array · palette chunks · threaded streaming (4 workers, thread-local
generators) gen -> features -> decorate -> light -> mesh · data-driven 26.3 terrain for all three dimensions
(density functions, splines, aquifers, material rules, ore veins, carvers, legacy random sources, End islands) ·
data-driven features incl. the new 26.x composite types · structures (jigsaw villages/outposts/bastions/ancient
cities/trail ruins/trial chambers, template igloos/shipwrecks/ruined portals/fossils/ocean ruins/end cities,
approximate strongholds/fortresses/mineshafts/temples/huts/monuments/buried treasure) with loot chests and
template entities · nether/end portals, end gateways, eye of ender · Ender Dragon fight · Wither summoning ·
golem summoning · 90 mob ids with archetype AI (flyers, swimmers, hoppers, ranged, fireballs, bullets, lasers,
teleporters, neutral/group anger) · Java physics · all game modes · inventory/crafting/furnace/chests · loot ·
fluids · crops · redstone (repeaters, comparators, observers, pistons, dispensers, hoppers) · enchanting/anvil/
grindstone/smithing/stonecutter · brewing/potions · villager trading · advancements + statistics · third-person
player model · first-person hand/items · armor rendering · signs · books/lecterns · maps · particles · raids · trial spawners/vaults · sculk/Warden ·
beacons · composters · villager levels · taming/riding · boats/minecarts · cave features (dripstone, sulfur spikes, roots, fossils) ·
LAN multiplayer · commands (selectors, /execute, scoreboard, bossbars, titles, functions, command blocks) (incl. /locate structure) · saves (per-dimension regions) · menus ·
music/sounds.

## incomplete (high impact first)
1. Villager job sites, loom/cartography table/lectern (banners, maps, written books), conduit, armor trims;
   resource/data packs.
2. LAN gaps: client container contents not synced, clients cannot use portals (everyone follows the host),
   commands host-only; redstone update order not Java-exact.
3. Feature types: speleothem/speleothem_cluster, large_dripstone, root_system, sculk_patch, fossil/template
   (desert well), bonus_chest. Woodland mansion. Beardifier terrain adaptation around jigsaw structures.
4. Mob polish: approximate rigs (horses, camel, sniffer, armadillo, breeze, creaking, warden, nautilus...),
   taming/riding, villager professions; dragon uses simplified phases (no path-node graph).
5. Performance: generation ~0.4–0.9 s + features ~0.35–0.55 s per chunk single-thread; a village start costs ~8 s
   once (ground-height probes).

## blocked
- 1.18.2 exact parity: needs user-supplied official 1.18.2 server jar + Java 17 (not installed).
- 26.3 bit-exact parity: needs reference world output; 26.3 `base_amplitude` noise normalisation unknown.
- 26.x generalised feature types (overlay, spike, block_blob, random_neighbor_spread, stepped_column_cluster...)
  are reconstructed from their JSON fields (no reference implementation available).

## next command
`powershell -ExecutionPolicy Bypass -File tools/check.ps1` then `tools/gd.ps1 -A "--headless --path . -- --test"`;
continue with villager levels/job sites, beacon/conduit, loom/cartography/lectern, then mob polish.
