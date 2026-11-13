# Recraft 2 — User Guide

Recraft 2 is a voxel sandbox written in Godot 4.7.2 (typed GDScript). It does not ship any Mojang or Microsoft
content. If you own Minecraft Java Edition 26.3, Recraft 2 reads the game data from **your own local
installation** at runtime, caches it privately and never redistributes it. Without an installation it runs in
**Original Placeholder Mode** with its own simple procedural textures and blocks (clearly labelled in the UI).

## Running

1. Install Godot 4.7.2 (standard build).
2. Open the project folder in Godot and press Play, or run
   `godot --path <project folder>`.
3. On first start the game scans the default Minecraft launcher folder (`%APPDATA%\.minecraft` on Windows).
   If it finds version 26.3 it asks before importing; the import is verified and stored in Godot's user data
   folder (`minecraft_asset_cache/26.3/`). A custom Minecraft folder can be set in Options.
4. Without a Minecraft installation choose **Placeholder Mode**.

## Worlds

- **Singleplayer → Create New World**: name, seed (numbers are used as-is, text is hashed like Java), game mode,
  difficulty, world type (default, large biomes, amplified, single biome, superflat), structures on/off, bonus
  chest, commands on/off.
- Generator profiles: `java_26_3` (data-driven from your installed 26.3 data — the default with assets),
  `approx_original` (original placeholder terrain), `java_1_18_2_exact` / `hybrid` (**labelled APPROXIMATE**:
  no 1.18.2 reference data is installed, so they run the 26.3 pipeline).
- Saves live in `user://saves/<world>/` (`level.json`, `region/`, `DIM-1/region/` for the Nether,
  `DIM1/region/` for the End). Writes are atomic with backups.

## Controls (rebindable in Options → Controls)

| Action | Key |
|---|---|
| Move | W A S D |
| Jump / swim up | Space |
| Sneak | Shift |
| Sprint | Ctrl (or double-tap W) |
| Attack / break | Left mouse |
| Use / place | Right mouse |
| Pick block | Middle mouse |
| Hotbar | 1–9, mouse wheel |
| Inventory | E |
| Drop item (Ctrl = stack) | Q |
| Swap off-hand | F |
| Chat / command | T / `/` |
| Hide HUD / screenshot / debug | F1 / F2 / F3 |
| Camera perspective | F5 |
| Pause | Esc |

In inventories: left click picks up / places, right click splits / places one, Shift-click moves between
sections, double-click collects, number keys swap with the hotbar.

## Gameplay overview

- **Game modes**: Survival, Creative (flight with double-tap Space, creative inventory), Adventure, Spectator,
  Hardcore.
- **Bundles**: left-click items with a bundle (or a bundle with items) to fill it; right-click to take the newest
  item out; use it in the world to empty it.
- **Leads**: use a lead on an animal to lead it; right-click a fence to tie it there, right-click again to untie.
- **Elytra**: wear it, jump off something high and press jump again in mid-air to glide; use firework rockets while
  gliding to boost. A totem of undying in either hand saves you from death once.
- **Using items**: hold right-click to eat, drink, draw a bow (release to shoot), charge a crossbow (release to
  load, click again to fire), throw a trident or raise a shield (offhand shields work while holding a weapon).
- **Loom**: put a banner and a dye in the loom, pick a pattern (or add a banner pattern item for special ones) and
  take the result; banners keep up to 6 layers and show them when placed.
- **Shulker boxes** keep their contents when broken.
- **Chests**: placing a chest next to another with the same facing makes a large chest (sneak to keep them
  separate), as in Java.
- **Crafting**: 2×2 in the inventory, 3×3 on a crafting table; all recipes come from the installed data. The green
  recipe book button lists everything you can craft right now; click a recipe to fill the grid.
- **Workstations**: furnace/blast furnace/smoker, enchanting table (bookshelves boost levels), anvil (repair,
  combine, rename; "Too Expensive!" at 40 levels), grindstone, smithing table (netherite upgrades),
  stonecutter, brewing stand (blaze powder fuel; water bottles from water with a glass bottle).
- **Pets and mounts**: tame wolves with bones and cats with raw cod/salmon (right-click to make them sit or stand);
  ride horses, donkeys and mules until they accept you, then saddle them (W/A/S/D steer, Space jumps, Shift
  dismounts). Press E while riding (or sneak + right-click a tamed horse) for its inventory: saddle, horse armor,
  and a chest for donkeys/mules/llamas (right-click them with a chest). Saddled pigs and striders follow a carrot /
  warped fungus on a stick.
- **Maps**: use an empty map to start a map of the 128x128 area around you; it fills in while you hold it.
- **Books**: right-click with a book and quill to write (up to 100 pages), Sign to turn it into a written book;
  place books on lecterns to share them.
- **Signs**: placing a sign opens the editor; right-click to edit the side you face, use dyes / glow ink sacs to
  color the text and honeycomb to lock it.
- **Decoration and tools**: item frames (right-click to insert/rotate, hit to remove), paintings (the largest design
  that fits the wall), armor stands (right-click with armor to store it), fishing rods (cast, wait for the bobber to
  dip, reel in), TNT (flint and steel, redstone or another explosion primes it; 4 s fuse).
- **Boats and minecarts**: place a boat on water or a minecart on rails and right-click to board; A/D turn a boat,
  W paddles. Powered rails boost minecarts; unpowered ones brake. Hit a vehicle a few times to pick it up.
- **Raids**: pillager patrols appear after day 5; killing a captain drops an ominous bottle. Drinking it and then
  entering a village (within 48 blocks of a bell) starts a raid: survive all waves to earn Hero of the Village.
- **Villagers**: right-click to trade (professions are assigned when they spawn); wandering traders sell items.
- **Redstone**: dust, levers, buttons, pressure plates, torches, repeaters (right-click to change delay),
  comparators (right-click toggles subtract), observers, pistons and sticky pistons, dispensers, droppers,
  hoppers, lamps, doors, TNT, note blocks, powered rails.
- **Structures**: villages, pillager outposts, desert pyramids, jungle temples, swamp huts, igloos,
  shipwrecks, ocean ruins, ruined portals, buried treasure, mineshafts, strongholds, trail ruins, trial
  chambers, ancient cities, ocean monuments; Nether fortresses, bastions and fossils; End cities.
  Some (strongholds, fortresses, mineshafts, monuments, temples) are original approximations; woodland mansions
  are not generated yet. Chests contain loot from your installed loot tables.

## The Nether and the End

- **Nether portal**: build an obsidian frame (inside 2–21 wide, 3–21 tall) and light it with flint and steel or
  a fire charge. Stand inside for 4 seconds (instant in Creative). Coordinates are scaled 1:8 and portals link to
  the nearest existing portal (16 blocks in the Nether, 128 in the Overworld) or build a new one.
- **Finding a stronghold**: throw an Eye of Ender (right-click); it flies toward the nearest stronghold.
  Fill all 12 End Portal Frames with eyes to open the portal.
- **The End**: you arrive on an obsidian platform. Destroy the End Crystals on the obsidian pillars (they heal the
  dragon), then defeat the Ender Dragon. Its death opens the exit portal, leaves the dragon egg (first kill) and
  creates an End Gateway to the outer islands. Enter the exit portal to return to your spawn point.
- **Bosses**: summon the Wither with 4 soul sand (T shape) and 3 wither skeleton skulls; build iron golems
  (iron block T + pumpkin) and snow golems (2 snow blocks + pumpkin).

## Multiplayer (LAN)

- **Host**: in a world, press Esc → **Open to LAN**. The game keeps running while menus are open and other players
  on your network see it under Multiplayer. The port is shown in the pause menu (25565 by default). Windows may ask
  to allow Godot through the firewall.
- **Join**: title screen → **Multiplayer**, enter your name, pick a world from the list or type the host's address
  (`192.168.1.20` or `192.168.1.20:25565`) and press **Direct Connect**. Both computers need the same asset
  mode and Minecraft version.
- The host's world is authoritative: block changes, mobs, items, time and weather come from the host; your
  inventory and position are saved in the host's world under your name.
- Limitations: everyone shares the host's dimension (clients follow the host through portals), chests and furnaces
  opened by a client are not synchronized, and only the host can run commands. Recraft 2 uses its own network
  protocol, so official Minecraft clients and servers cannot connect to it.

## Advancements and statistics

Advancements come from your installed game data and show a toast when completed. Esc → **Advancements** lists
progress per tab; **Statistics** shows play time, distance, blocks mined, items crafted and mobs killed.

## Commands (enable cheats when creating the world)

Type `/help` in game for the full list. Supported: gamemode, defaultgamemode, difficulty, gamerule, time, weather,
seed, tp/teleport, give, clear, setblock, fill, clone, summon, kill, effect, enchant, experience/xp, spawnpoint,
setworldspawn, locate (biome/structure), say, me, tell/msg/w, tellraw, title, list, save-all/off/on, tick, execute,
function, reload, scoreboard, team, tag, bossbar, worldborder, damage, ride, particle, playsound, stopsound,
advancement, loot, item, spreadplayers, data get, fillbiome, publish.

- Selectors: `@p @a @e @s @r @n` with `type= distance= limit= sort= name= tag= gamemode= level= x= y= z= dx= dy= dz=`,
  `scores={obj=1..5}`. Coordinates support `~` (relative) and `^` (local).
- `/execute`: as, at, positioned, rotated, facing, anchored, align, in (current dimension), if/unless block|entity|score,
  store result|success score, run.
- **Command blocks** (creative + commands enabled): right-click to edit; Impulse runs on a redstone pulse, Repeat
  every tick while active, Chain after the block pointing into it.
- **Data-pack functions**: put packs in `<world folder>/datapacks/<pack>/data/<namespace>/function/*.mcfunction`;
  functions listed in the `#minecraft:load` / `#minecraft:tick` function tags run on load / every tick.
  Other data-pack contents (recipes, loot tables, worldgen) are not loaded from packs yet.

## Options

Video (render distance, simulation distance, FOV, fog, biome blend, view bobbing, GUI scale, brightness, entity
distance, particles), audio volumes per category, controls, accessibility (damage tilt, distortion effects,
toggle sneak/sprint), language strings from your installed assets.

## Resource packs

Put resource packs (folders or .zip files containing pack.mcmeta) into the resourcepacks folder (Options →
Resources → Open Pack Folder), tick them in that list and restart. Packs replace textures, models, sounds and
language files from your installed assets; they cannot change game data.

## Performance notes

Generation runs on 4 worker threads (GDScript calls contend across more threads on the reference machine).
First spawn takes roughly 6–10 s; the first chunk that touches a village pays a one-time cost of a few seconds
while the village layout is assembled. Lower the render distance on slower machines. A native ARM64 build of
Godot is expected to scale better on ARM computers.

## Developer commands

| Purpose | Command |
|---|---|
| Compile check | `powershell -ExecutionPolicy Bypass -File tools/check.ps1` |
| Tests | `godot --headless --path . -- --test` (add `--vanilla` to test against your installed data) |
| Benchmarks | `godot --headless --path . -- --bench --n=2` (`--dim=the_nether`, `--locate=<structure>`) |
| Render probe | `godot --path . -- --autoplay --gen=java_26_3 --fresh --seed=777` (`--dim=`, `--at=x,z`, `--mobs=a,b`) |
| Coverage docs | `godot --headless --path . -- --report` (writes docs/COVERAGE.json, PARITY_MATRIX.md, MOB_PARITY.md) |

## Known limitations

See `docs/STATUS.md` and `docs/PARITY_MATRIX.md` — notably: LAN limitations above, advancements with uncommon
triggers never complete, simplified dragon AI, approximate rigs for some mobs, villagers do not level up, Java
redstone update order not matched, woodland mansions missing, 1.18.2 exact profile blocked.
