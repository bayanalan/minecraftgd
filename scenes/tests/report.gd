## Report — `godot --headless --path . -- --report`: enumerates the installed version's registries and writes
## docs/COVERAGE.json, docs/PARITY_MATRIX.md and docs/MOB_PARITY.md (IDs + statuses only, no game content).
## Statuses: missing | parsed | visible | interactive | mechanically_tested | java26_3_parity_tested.
extends Node


func _ready() -> void:
	var cov := {"version": Res.version, "mode": Res.mode, "generated": Time.get_datetime_string_from_system(), "categories": {}}
	var b := Res.blocks
	# blocks
	var bl := {}
	var visible := 0
	for i in b.names.size():
		var st := b.block_default[i]
		var fl := b.st_flags[st]
		var status := "parsed"
		if fl & (BlockRegistry.F_CUBE | BlockRegistry.F_MODEL | BlockRegistry.F_FLUID):
			status = "visible"
			visible += 1
		var nm := b.names[i]
		if nm in ["air", "stone", "dirt", "grass_block", "oak_log", "oak_planks", "crafting_table", "furnace", "chest", "water", "lava", "sand", "gravel", "oak_slab", "oak_stairs", "torch", "glowstone", "wheat", "farmland", "oak_door", "lever", "redstone_lamp", "tnt"]:
			status = "interactive"
		bl[nm] = {"render": status, "states": b.block_count[i], "hardness": b.hardness[i]}
	cov["categories"]["block"] = {"total": b.names.size(), "visible": visible, "states": b.total_states, "ids": bl}
	# items
	var it := {}
	var usable := 0
	for i in range(1, Res.items.names.size()):
		var n: String = Res.items.names[i]
		var st2 := "parsed"
		if Res.items.place_block[i] > 0 or Res.items.tool_kind[i] != "" or Res.items.food_nutrition[i] > 0 or Res.items.armor_slot[i] >= 0:
			st2 = "interactive"
			usable += 1
		it[n] = st2
	cov["categories"]["item"] = {"total": Res.items.names.size() - 1, "interactive": usable, "ids": it}
	# biomes
	var biomes := BiomeRegistry.new()
	biomes.build()
	var placed := {}
	if Res.mode == "vanilla":
		var g := VanillaGenerator.new()
		g.setup(1, Res.blocks, biomes, {})
		var clim := g.climate
		for n in clim.names:
			placed[n] = true
		cov["categories"]["feature_types_unsupported"] = g.features.unsupported
		var ft := {}
		for k in g.features.configured:
			ft[str(g.features.configured[k].get("t", "none"))] = true
		cov["categories"]["feature_types_seen"] = ft.keys()
	var bi := {}
	for n in biomes.names:
		bi[n] = "generated" if placed.has(n) else ("parsed" if not n in ["the_void"] else "special")
	cov["categories"]["biome"] = {"total": biomes.names.size(), "generated_overworld": placed.size(), "ids": bi}
	# recipes / loot
	Crafting.loaded = false
	Crafting.load_all()
	cov["categories"]["recipe"] = {"shaped": Crafting.shaped.size(), "shapeless": Crafting.shapeless.size(), "smelting": Crafting.smelting.size(), "blasting": Crafting.blasting.size(), "smoking": Crafting.smoking.size(), "stonecutting": Crafting.stonecutting.size(), "status": "crafting table + 2x2 + furnaces interactive; stonecutter/smithing UI missing"}
	cov["categories"]["loot_table"] = {"total": Res.list_files("data/minecraft/loot_table/", ".json").size(), "status": "block, entity and structure chest tables evaluated (chests unpack on open/break)"}
	# structures
	var structs := {}
	var approx := ["stronghold", "fortress", "mineshaft", "desert_pyramid", "jungle_temple", "swamp_hut", "buried_treasure", "ocean_monument", "end_city"]
	for f in Res.list_files("data/minecraft/worldgen/structure/", ".json"):
		var j = Res.read_json(f)
		var t := str(j.get("type", "?")).trim_prefix("minecraft:") if j is Dictionary else "?"
		var nm2 := f.get_file().get_basename()
		var stt := "generated (data-driven jigsaw)"
		if t == "woodland_mansion":
			stt = "missing"
		elif t in approx:
			stt = "generated (APPROXIMATE builder)"
		elif t != "jigsaw":
			stt = "generated (installed templates)"
		structs[nm2] = {"type": t, "status": stt}
	cov["categories"]["structure"] = {"total": structs.size(), "ids": structs}
	# mobs
	var mobs := {}
	var impl := MobRegistry.implemented()
	var approx_rig := ["horse", "donkey", "mule", "skeleton_horse", "zombie_horse", "camel", "camel_husk", "sniffer", "armadillo", "breeze", "creaking", "warden", "copper_golem", "nautilus", "zombie_nautilus", "sulfur_cube", "magma_cube", "goat", "turtle", "frog", "fox", "llama", "trader_llama", "giant", "ender_dragon"]
	for m in MobRegistry.ALL:
		mobs[m] = ("functional (approx rig)" if approx_rig.has(m) else "functional") if impl.has(m) else "absent"
	var n_func := 0
	for m2 in MobRegistry.ALL:
		if impl.has(m2):
			n_func += 1
	cov["categories"]["mob"] = {"total": MobRegistry.ALL.size(), "functional": n_func, "ids": mobs}
	var sys := {
		"modes": "survival/creative/adventure(can_break components)/spectator/hardcore: interactive",
		"worldgen_26_3": "data-driven terrain, biomes, aquifers, material rules, ore veins, cave/canyon carvers, features (all 26.3 feature types used by the data except speleothem*, large_dripstone, root_system, sculk_patch, fossil/template, bonus_chest), structures; no beardifier; parity unverified",
		"worldgen_1_18_2": "blocked (no 1.18.2 reference data) - approximate profile",
		"lighting": "sky+block BFS, smooth light, AO", "fluids": "flow/sources/lava-water interactions (simplified slope search)",
		"redstone": "dust, levers, buttons, plates, torches, lamps, doors, TNT, note blocks, repeaters (delay/lock), comparators (compare/subtract, containers), observers, pistons/sticky pistons (12-block push), dispensers/droppers, hoppers; update order/quasi-connectivity not Java-exact",
		"music": "menu/game/creative/underwater contexts from installed sounds.json", "multiplayer": "LAN over ENet (scripts/net/net.gd): host-authoritative, discovery broadcast, modified-chunk sync + local deterministic generation, block/player/entity/chat/time sync, forwarded client actions; own protocol (not Minecraft's), clients share the host dimension",
		"dimensions": "overworld, nether, end (legacy random sources, per-dimension saves, sky/fog/ambient)", "portals": "nether portal frames/linking/creation, end portal frames + eyes, end platform, end gateways",
		"bosses": "ender dragon fight (crystals, podium, egg, gateways; simplified phases), wither (summon pattern, charge, skulls)",
		"advancements": "data-driven from installed advancement JSON (triggers: inventory_changed, changed_dimension, player_killed_entity, bred_animals, consume_item, enter/placed_block, simple location); toasts; recipe trees skipped; other triggers never fire", "workstations": "enchanting table (data-driven enchantments, Java cost/selection algorithm), anvil (repair/combine/rename/too expensive), grindstone, smithing (transform recipes), stonecutter, brewing stand (Java mix table, fuel, 400-tick brew), potions (drink/splash/lingering)",
		"armor_rendering": "humanoid armor layer on player/armor stands/mobs (installed equipment textures, Java inflation), mob armor spawn tiers and drops; no trims, glint or leather overlay",
		"sculk_warden": "vibrations from player actions/explosions/projectiles (wool occlusion), sensors (distance power), shriekers (warning levels, darkness, warden summoning), warden anger/sonic boom/dig; no frequencies, no catalyst spreading",
		"trials_spawners": "mob spawners (Java BaseSpawner), trial spawners (installed configs, rewards, cooldown), vaults (keys, per-player rewards), breeze/player wind charges; no ominous trial variants, no line of sight",
		"raids": "patrols + captains, ominous bottle/Bad Omen/Raid Omen, waves (Java composition), raid bar, victory/defeat, raiders vs villagers, evoker vexes/fangs, witch potions; no banners, no ravager riders, no villager panic/bell ringing",
		"particles": "textured billboard particles (installed sprites, one MultiMesh, cap 600), Java animateTick block emitters, rain splashes, event particles; no particle data-driven definitions, no block-crack particles via sprites (simple cubes)",
		"maps": "explorer maps (scale 0), Java grid centering, MapColor bases for common blocks + shading, held two-handed view, item frames; no zoom/cartography table, markers or locking",
		"books": "book and quill editing, signing, written book reading, lecterns (no comparator output, no book copying recipe handling)",
		"creaking": "heart states, protector spawn/despawn, invulnerability, resin, watched freeze; no heart comparator output, no emitter particle trail toward the heart",
		"tree_decorators": "all 10 26.3 decorator types; shelf_mushroom placement approximated (no source), beehives without bees",
		"armor_trims": "smithing + rendering with material palettes; no trim tooltip line, no trims on item icons",
		"bundles": "weights, click actions, bar, empty on use; no contents tooltip grid, no scroll selection (newest item is taken)",
		"leads": "tie/untie, fence knots, pull/snap distances, rope render; no knot entity model, rope sag approximated",
		"special_recipes": "transmute, dye, imbue, fireworks, banner/book copy, repair, shield decoration, decorated pot; dyed leather shows on icons and worn armour (with overlay); no map extending; decorated shields render base colour + patterns (not on cached icons)",
		"elytra_fireworks_totem": "Java glide physics, rocket boost, ground rockets with star explosions, totem, name tags; no elytra on the player model, no crafted firework stars/patterns UI (crafting recipes are special), no CustomNameVisible toggle",
		"combat_19": "attack cooldown, crits, sweeps, sprint knockback, enchantment damage, attack indicator; no shield-disabling player axes vs mobs, no mob attack cooldown changes",
		"item_use": "Java use durations/poses for food, drinks, bow, crossbow, trident, shield, spyglass; no firework crossbow ammo, tridents drop as items instead of sticking, no spyglass overlay texture, no third-person use poses",
		"loot_263_format": "modifier/condition keys, integer number providers, enchanted chance/count, entity_properties subset, copy_components; damage_source_properties evaluates false, location/weather/time checks true",
		"loom": "patterns from data + tags, pattern items, 6-layer limit, preview; item icons do not show patterns",
		"special_item_models": "icons/held/dropped items via block-entity models + item display transforms; bed items render one half",
		"block_entity_render": "chests (double, lid), shulker boxes, skulls/heads, banners, bell, decorated pot, conduit drawn from installed entity textures; banner patterns, pot sherds and active conduit not rendered",
		"large_chests": "Java placement pairing, unlink on break, 54-slot Large Chest screen; hoppers/comparators treat halves separately",
		"resource_packs": "folder/zip packs with pack.mcmeta overlay assets (textures, models, sounds, lang) in priority order; restart to apply; no pack_format version check, no hot reload",
		"recipe_book": "craftable-recipe list on inventory/crafting table, click fills the grid; no search box, no recipe unlocking, no furnace recipe book",
		"signs": "front/back text editing (Java width limits), dye colors, glowing text, waxing; text rendered on standing/wall/hanging signs",
		"first_person": "hand (player skin arm) and held items (extruded sprites / block meshes) with Java arm/item/swing/display transforms, bobbing; no offhand rendering, no equip animation, no map/shield/bow/crossbow special poses",
		"misc_entities": "primed TNT (Java fuse/physics, chain priming), fishing hook (cast vector, lure/bite timing, fishing loot table, XP), item frames + glow frames (8 rotations), paintings (installed variants, largest fit), armor stands (stores armor, not drawn), lightning bolts",
		"vehicles": "boats/rafts + chest boats (Java Boat float/control physics, 8 m/s on water), minecarts + chest/hopper/TNT/furnace variants (rail exits projection, slopes, powered rails, friction, fuel, fuse, hopper pickup); hopper carts do not pull from containers",
		"taming_riding": "wolves/cats (1/3 taming, sit, follow/teleport, wolves assist the owner), horses/donkeys/mules/llamas (temper taming, saddles, rider control, jump), saddled pigs/striders with steering sticks, camels, happy ghast harness; horse inventory (saddle/armor/chest), horse armor + saddle rendering and damage reduction; no sitting pose, no llama caravans/spit",
		"trading": "villager professions (assigned at spawn - approx), trade tables, levels (xp 10/70/150/250, +2 offers per level), wandering trader, merchant screen, restock; no demand pricing/reputation",
		"beacons": "pyramid levels, sky check, effects every 80 ticks, payment, beam (untinted); composter, bell",
		"commands": "%d commands (%s); selectors @p/@a/@e/@s/@r/@n with type/distance/limit/sort/name/tag/gamemode/level/volume/scores; /execute as/at/positioned/rotated/facing/anchored/align/in/if/unless (block, entity, score)/store score/run; scoreboard, teams (basic), bossbars, titles, tags; command blocks (impulse/chain/repeating, conditional, redstone); data-pack functions + #load/#tick. Not supported: /data modify, /place, /function macros, /item block slots, NBT predicates" % [CommandParser.IMPLEMENTED.size(), ", ".join(CommandParser.IMPLEMENTED)], "saves": "atomic region files + backups",
	}
	cov["systems"] = sys
	var dir := ProjectSettings.globalize_path("res://docs")
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("COVERAGE.json"), JSON.stringify(cov, "  "))
	# PARITY_MATRIX.md
	var md := "# PARITY MATRIX (generated by `--report`, %s)\n\nSource codes: A data, B notes, C reference, D docs/recalled, E approximation. Nothing below is claimed `java26_3_parity_tested`.\n\n| Category | Total | Status counts | Source |\n|---|---|---|---|\n" % cov["generated"]
	md += "| Blocks | %d (%d states) | visible %d, interactive (tested families) ~%d | A (models/textures), D (behaviour) |\n" % [b.names.size(), b.total_states, visible, 23]
	md += "| Items | %d | interactive %d | A + D |\n" % [Res.items.names.size() - 1, usable]
	md += "| Biomes | %d | generated in overworld %d | A (data) + D/E (placement) |\n" % [biomes.names.size(), placed.size()]
	md += "| Recipes | %d crafting + %d smelting | crafting/smelting interactive | A |\n" % [Crafting.shaped.size() + Crafting.shapeless.size(), Crafting.smelting.size()]
	md += "| Mobs | %d | functional %d (approx rigs marked), absent %d | D |\n" % [MobRegistry.ALL.size(), n_func, MobRegistry.ALL.size() - n_func]
	for k in sys:
		md += "| %s | - | %s | - |\n" % [k, sys[k]]
	md += "\n## Structures\n\n| Structure | Type | Status |\n|---|---|---|\n"
	var sk: Array = structs.keys()
	sk.sort()
	for k2 in sk:
		md += "| %s | %s | %s |\n" % [k2, structs[k2]["type"], structs[k2]["status"]]
	_write(dir.path_join("PARITY_MATRIX.md"), md)
	# MOB_PARITY.md
	var mm := "# MOB PARITY (generated by `--report`)\n\nStatus: absent / visible / functional / vanilla-validated. Functional = spawns, AI goals, drops via installed loot tables, save/load. No mob is vanilla-validated yet.\n\n| Mob | Registry ID | Status | Notes |\n|---|---|---|---|\n"
	for m in MobRegistry.ALL:
		var d := MobRegistry.get_def(m)
		var notes := ""
		if not d.is_empty():
			var ai := "walker"
			for flag in ["dragon", "boss", "flies", "swims", "hops", "stationary", "ranged", "explodes", "neutral", "teleports"]:
				if d.get(flag, false):
					ai = flag
					break
			notes = "%s, hp %d, AI %s, rig %s" % [d.get("kind", ""), int(d.get("hp", 0)), ai, str(d.get("rig", d.get("rig_of", "own")))]
		mm += "| %s | minecraft:%s | %s | %s |\n" % [m.capitalize(), m, mobs[m], notes]
	_write(dir.path_join("MOB_PARITY.md"), mm)
	print("REPORT written to ", dir)
	get_tree().quit()


func _write(p: String, t: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(t)
		f.close()
