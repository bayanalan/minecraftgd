## CommandParser — Java-like commands with an execution context (source, position, rotation): relative (~) and
## local (^) coordinates, selectors @p @a @e @s @r @n with arguments (type, distance, limit, sort, name, tag,
## gamemode, level, x/y/z/dx/dy/dz, scores), /execute (as, at, positioned, rotated, facing, anchored, align, in,
## if/unless block|entity|score, store result|success score, run), scoreboard/team/tag/bossbar/title state in
## level.json, data-pack functions (world/datapacks/<pack>/data/<ns>/function/*.mcfunction, #minecraft:load / tick
## tags). Never executes OS commands or touches files outside the world folder.
## Unsupported grammar is reported explicitly ("not supported"), never silently ignored.
## Contract: execute(line) -> feedback String; run(line, ctx) -> int result (store/conditions); tick() per game tick.
class_name CommandParser
extends RefCounted

class Ctx:
	var source = null          # Player, EntityManager.Ent or null (server / command block / function)
	var pos := Vector3.ZERO
	var yaw := 0.0
	var pitch := 0.0
	var eyes := false
	var silent := false

	func copy() -> Ctx:
		var c := Ctx.new()
		c.source = source
		c.pos = pos
		c.yaw = yaw
		c.pitch = pitch
		c.eyes = eyes
		c.silent = silent
		return c


var world
var feedback: Array = []         # messages produced by the current top-level command
var feedback_click := ""       # click event of the feedback line ("copy:<text>" = COPY_TO_CLIPBOARD, else SUGGEST_COMMAND)
var last_result := 0
var _depth := 0
var _functions: Dictionary = {}  # "ns:path" -> PackedStringArray (cached)
var _fn_loaded := false
var _tick_fns: Array = []

const IMPLEMENTED := ["help", "gamemode", "defaultgamemode", "difficulty", "gamerule", "time", "weather", "seed", "tp", "teleport",
	"give", "clear", "setblock", "fill", "clone", "summon", "kill", "effect", "enchant", "experience", "xp", "spawnpoint",
	"setworldspawn", "locate", "say", "me", "tell", "msg", "w", "tellraw", "title", "list", "save-all", "save-off", "save-on",
	"tick", "execute", "function", "scoreboard", "team", "tag", "bossbar", "worldborder", "damage", "ride", "particle",
	"playsound", "stopsound", "advancement", "loot", "item", "spreadplayers", "data", "fillbiome", "spectate", "publish", "reload", "place", "build"]
const NO_PERMISSION := ["help", "seed", "list", "me", "say", "tell", "msg", "w", "build"]


# ------------------------------------------------------------------ entry points

func player_ctx() -> Ctx:
	var c := Ctx.new()
	var p: Player = world.player
	c.source = p
	c.pos = p.pos
	c.yaw = p.yaw
	c.pitch = p.pitch
	return c


## Chat entry point (player). Returns the feedback text.
func execute(line: String) -> String:
	feedback = []
	feedback_click = ""
	var s := line.strip_edges().trim_prefix("/")
	if s.is_empty():
		return ""
	var cmd := s.get_slice(" ", 0).to_lower()
	if not bool(world.level.get("allow_commands", false)) and not cmd in NO_PERMISSION:
		return "You do not have permission to use this command (enable Allow Commands)."
	last_result = run(s, player_ctx())
	return "\n".join(feedback)


func _say(ctx: Ctx, msg: String) -> void:
	if ctx == null or not ctx.silent:
		feedback.append(msg)


## Runs one command (no leading slash) in a context. Returns the Java command result (0 = failure).
func run(s: String, ctx: Ctx) -> int:
	_depth += 1
	if _depth > 64:
		_depth -= 1
		_say(ctx, "Command recursion limit reached")
		return 0
	var parts := _split(s.strip_edges().trim_prefix("/"))
	var r := 0
	if not parts.is_empty():
		var cmd := parts[0].to_lower().trim_prefix("minecraft:")
		if not IMPLEMENTED.has(cmd):
			_say(ctx, "Unknown or not supported command: " + cmd)
		else:
			r = _dispatch(cmd, parts.slice(1), ctx)
	_depth -= 1
	return r


# ------------------------------------------------------------------ dispatcher

func _dispatch(cmd: String, a: PackedStringArray, ctx: Ctx) -> int:
	var p: Player = world.player
	match cmd:
		"help":
			_say(ctx, "Commands: " + ", ".join(IMPLEMENTED))
			return 1
		"gamemode":
			if a.is_empty():
				_say(ctx, "Usage: /gamemode <mode> [targets]")
				return 0
			var m := _mode(a[0])
			if m < 0:
				_say(ctx, "Unknown game mode " + a[0])
				return 0
			var n := 0
			for t in _players(a[1] if a.size() > 1 else "@s", ctx):
				if world.hardcore and m != Player.Mode.SPECTATOR:
					continue
				t.mode = m as Player.Mode
				if m == Player.Mode.SURVIVAL or m == Player.Mode.ADVENTURE:
					t.flying = false
				n += 1
			if n > 0 and a.size() <= 1:
				Audio.set_music_context("creative" if m == Player.Mode.CREATIVE else "game")
			_say(ctx, "Set game mode to %s Mode" % ["Survival", "Creative", "Adventure", "Spectator"][m])
			return n
		"defaultgamemode":
			var m2 := _mode(a[0] if a.size() > 0 else "")
			if m2 < 0:
				_say(ctx, "Usage: /defaultgamemode <mode>")
				return 0
			world.level["game_mode"] = m2
			_say(ctx, "The default game mode is now " + ["Survival", "Creative", "Adventure", "Spectator"][m2])
			return 1
		"difficulty":
			if a.is_empty():
				_say(ctx, "The difficulty is " + ["Peaceful", "Easy", "Normal", "Hard"][world.difficulty])
				return world.difficulty
			var d := ["peaceful", "easy", "normal", "hard"].find(a[0].to_lower())
			if d < 0 or world.hardcore:
				_say(ctx, "Unknown difficulty" if d < 0 else "Difficulty is locked to Hard in Hardcore")
				return 0
			world.difficulty = d
			_say(ctx, "The difficulty has been set to " + a[0].capitalize())
			return 1
		"gamerule":
			if a.is_empty():
				_say(ctx, "Usage: /gamerule <rule> [value]")
				return 0
			if a.size() == 1:
				_say(ctx, "Gamerule %s is currently set to: %s" % [a[0], str(world.gamerules.get(a[0], "?"))])
				return int(world.gamerules.get(a[0], 0)) if str(world.gamerules.get(a[0], "")).is_valid_int() else 1
			var v = GameRules.validate(a[0], a[1])
			if v == null:
				_say(ctx, "Invalid gamerule or value")
				return 0
			world.gamerules[a[0]] = v
			_say(ctx, "Gamerule %s is now set to: %s" % [a[0], str(v)])
			return 1
		"time":
			if a.size() >= 2 and (a[0] == "set" or a[0] == "add"):
				var tv = {"day": 1000, "noon": 6000, "night": 13000, "midnight": 18000}.get(a[1], _ticks(a[1]))
				if a[0] == "set":
					world.day_time = int(tv) % 24000
				else:
					world.day_time = (world.day_time + int(tv)) % 24000
				_say(ctx, "Set the time to %d" % world.day_time)
				return world.day_time
			if a.size() >= 2 and a[0] == "query":
				var q: int = world.day_time if a[1] == "daytime" else (world.game_time if a[1] == "gametime" else world.game_time / 24000)
				_say(ctx, "The time is %d" % q)
				return q
			_say(ctx, "Usage: /time <set|add|query> <value>")
			return 0
		"weather":
			if a.is_empty():
				_say(ctx, "Usage: /weather <clear|rain|thunder> [duration]")
				return 0
			world.raining = a[0] != "clear"
			world.thundering = a[0] == "thunder"
			world.weather_timer = _ticks(a[1]) if a.size() > 1 else 6000
			_say(ctx, "Changed the weather")
			return 1
		"seed":
			# Java SeedCommand: ComponentUtils.copyOnClickText - green brackets, click copies, hover "Click to Copy to Clipboard"
			_say(ctx, "Seed: [%d]" % int(world.level.get("seed", 0)))
			feedback_click = "copy:%d" % int(world.level.get("seed", 0))
			return 1
		"build":
			# Recraft: which build is running (native library architecture, emulation, renderer)
			var arch := Engine.get_architecture_name()
			var cpu := OS.get_processor_name()
			var native_s := ("native library %s loaded" % arch) if Native.ok else "native library NOT loaded (GDScript fallback)"
			var emulated := arch == "x86_64" and (cpu.to_lower().contains("snapdragon") or cpu.to_lower().contains("qualcomm") or OS.has_environment("PROCESSOR_ARCHITEW6432"))
			_say(ctx, "Recraft build: %s%s, Godot %s, %s, renderer %s" % [arch, " (emulated on ARM64)" if emulated else "", Engine.get_version_info().get("string", "?"), native_s,
				RenderingServer.get_current_rendering_method()])
			_say(ctx, "CPU: %s (%d threads), GPU: %s" % [cpu, OS.get_processor_count(), RenderingServer.get_video_adapter_name()])
			return 1
		"tp", "teleport":
			return _tp(a, ctx)
		"give":
			if a.size() < 2:
				_say(ctx, "Usage: /give <targets> <item> [count]")
				return 0
			var it := Res.items.id(a[1].split("[")[0].trim_prefix("minecraft:"))
			if it <= 0:
				_say(ctx, "Unknown item " + a[1])
				return 0
			var cnt := int(a[2]) if a.size() > 2 else 1
			var n := 0
			for t in _players(a[0], ctx):
				var left: int = t.inventory.add(ItemStack.of(it, cnt))
				if left > 0:
					world.entities.spawn_item(t.pos + Vector3(0, 1, 0), ItemStack.of(it, left))
				n += 1
			world.inv_changed()
			_say(ctx, "Gave %d [%s] to %d player(s)" % [cnt, Res.items.display_name(it), n])
			return n
		"clear":
			var n := 0
			var total := 0
			var only := Res.items.id(a[1].trim_prefix("minecraft:")) if a.size() > 1 else -1
			var maxc := int(a[2]) if a.size() > 2 else -1
			for t in _players(a[0] if a.size() > 0 else "@s", ctx):
				if only > 0:
					total += t.inventory.remove_item(only, maxc if maxc >= 0 else 1 << 30)
				else:
					for i in Inventory.SIZE:
						total += t.inventory.get_slot(i).count
					t.inventory.clear_all()
				n += 1
			world.inv_changed()
			_say(ctx, "Removed %d item(s) from %d player(s)" % [total, n])
			return total
		"setblock":
			if a.size() < 4:
				_say(ctx, "Usage: /setblock <pos> <block> [destroy|keep|replace]")
				return 0
			var bp := Vector3i(_coords(a.slice(0, 3), ctx).floor())
			var st := Res.blocks.parse_state(a[3].trim_prefix("minecraft:"))
			if st < 0:
				_say(ctx, "Unknown block " + a[3])
				return 0
			var mode := a[4] if a.size() > 4 else "replace"
			if mode == "keep" and world.state_at(bp.x, bp.y, bp.z) != 0:
				_say(ctx, "Could not set the block")
				return 0
			if mode == "destroy":
				world._break_block(bp, true)
			if world.set_block(bp.x, bp.y, bp.z, st) < 0:
				_say(ctx, "That position is not loaded")
				return 0
			BlockEntities.on_placed(world, bp, st)
			BlockUpdates.schedule_neighbors(world, bp)   # Java onPlace / neighbour updates: fluids flow, sand falls
			_say(ctx, "Changed the block at %d, %d, %d" % [bp.x, bp.y, bp.z])
			return 1
		"fill":
			return _fill(a, ctx)
		"place":
			return _place(a, ctx)
		"clone":
			return _clone(a, ctx)
		"summon":
			if a.is_empty():
				_say(ctx, "Usage: /summon <entity> [pos]")
				return 0
			var at := ctx.pos
			if a.size() >= 4:
				at = _coords(a.slice(1, 4), ctx)
			var id := a[0].trim_prefix("minecraft:")
			var e = null
			if id.ends_with("_boat") or id.ends_with("_raft") or id == "minecart":
				e = Vehicles.spawn(world.entities, "minecart" if id == "minecart" else "boat", id, at, ctx.yaw)
			elif id == "lightning_bolt":
				world.entities.lightning(at)
				_say(ctx, "Summoned new Lightning Bolt")
				return 1
			elif id == "item":
				# Java: /summon item <pos> {Item:{id:"minecraft:stick",count:3}}
				var nb := a[4] if a.size() >= 5 else ""
				var rid := RegEx.create_from_string("id:\\s*\"?(?:minecraft:)?([a-z0-9_]+)")
				var rc := RegEx.create_from_string("count:\\s*(\\d+)")
				var mid := rid.search(nb)
				var it := Res.items.id(mid.get_string(1)) if mid != null else -1
				if it <= 0:
					_say(ctx, "Unable to summon entity item")
					return 0
				var mc := rc.search(nb)
				var ie = world.entities.spawn_item(at, ItemStack.of(it, int(mc.get_string(1)) if mc != null else 1))
				if ie != null:
					ie.vel = Vector3.ZERO
					ie.pickup_delay = 40
				_say(ctx, "Summoned new Item")
				return 1
			elif id == "experience_orb":
				world.entities.spawn_xp(at, 1)
				_say(ctx, "Summoned new Experience Orb")
				return 1
			elif id == "tnt":
				MiscEntities.spawn_tnt(world.entities, at, 80)
				_say(ctx, "Summoned new Primed TNT")
				return 1
			else:
				e = world.entities.spawn_mob(id, at)
			if e == null:
				_say(ctx, "Unable to summon entity " + id)
				return 0
			if a.size() >= 5:
				_apply_nbt(e, a[4])
			_say(ctx, "Summoned new " + id)
			return 1
		"kill":
			var n := 0
			for t in _targets(a[0] if a.size() > 0 else "@s", ctx):
				if t is Player:
					(t as Player).hurt(1.0e6, "out_of_world", true)
				else:
					world.entities._remove(t)
				n += 1
			_say(ctx, "Killed %d entities" % n)
			return n
		"effect":
			if a.size() >= 3 and a[0] == "give":
				var eid := a[2].trim_prefix("minecraft:")
				var secs := 30 if a.size() <= 3 else (1000000 if a[3] == "infinite" else int(a[3]))
				var amp := int(a[4]) if a.size() > 4 else 0
				var n := 0
				for t in _players(a[1], ctx):
					t.add_effect(eid, amp, secs * 20)
					n += 1
				_say(ctx, "Applied effect %s to %d target(s)" % [eid, n])
				return n
			if a.size() >= 1 and a[0] == "clear":
				var n2 := 0
				for t in _players(a[1] if a.size() > 1 else "@s", ctx):
					if a.size() > 2:
						t.effects.erase(a[2].trim_prefix("minecraft:"))
					else:
						t.effects.clear()
					n2 += 1
				_say(ctx, "Removed effects from %d target(s)" % n2)
				return n2
			_say(ctx, "Usage: /effect <give|clear> <targets> [effect] [seconds|infinite] [amplifier]")
			return 0
		"enchant":
			if a.size() < 2:
				_say(ctx, "Usage: /enchant <targets> <enchantment> [level]")
				return 0
			Enchanting.load_all()
			var en := a[1].trim_prefix("minecraft:")
			if not Enchanting.defs.has(en):
				_say(ctx, "Unknown enchantment " + en)
				return 0
			var n := 0
			for t in _players(a[0], ctx):
				var h: ItemStack = t.inventory.held()
				if h.is_empty():
					continue
				var cur := Enchanting.get_enchants(h)
				cur[en] = int(a[2]) if a.size() > 2 else 1
				Enchanting.set_enchants(h, cur)
				n += 1
			world.inv_changed()
			_say(ctx, "Applied enchantment %s to %d target(s)" % [en, n] if n > 0 else "No target was holding an item")
			return n
		"experience", "xp":
			if a.size() >= 3 and (a[0] == "add" or a[0] == "set"):
				var amt := int(a[2])
				var lv := a.size() > 3 and a[3] == "levels"
				var n := 0
				for t in _players(a[1], ctx):
					if a[0] == "set":
						if lv:
							t.xp_level = amt
						else:
							t.xp_progress = clampf(float(amt) / t.xp_to_next(), 0.0, 0.999)
					elif lv:
						t.xp_level = maxi(0, t.xp_level + amt)
					else:
						t.add_xp(amt)
					n += 1
				_say(ctx, "Changed experience of %d player(s)" % n)
				return n
			if a.size() >= 2 and a[0] == "query":
				var ps := _players(a[1], ctx)
				if ps.is_empty():
					return 0
				var q: int = ps[0].xp_level if a.size() > 2 and a[2] == "levels" else int(ps[0].xp_progress * ps[0].xp_to_next())
				_say(ctx, "%s has %d experience %s" % [_name(ps[0]), q, "levels" if a.size() > 2 and a[2] == "levels" else "points"])
				return q
			_say(ctx, "Usage: /xp <add|set|query> <targets> <amount> [points|levels]")
			return 0
		"spawnpoint":
			var at2 := Vector3i(_coords(a.slice(1, 4), ctx).floor()) if a.size() >= 4 else Vector3i(ctx.pos.floor())
			var n := 0
			for t in _players(a[0] if a.size() > 0 else "@s", ctx):
				t.spawn_point = at2
				t.has_spawn = true
				n += 1
			_say(ctx, "Set spawn point to %d, %d, %d" % [at2.x, at2.y, at2.z])
			return n
		"setworldspawn":
			var at3 := Vector3i(_coords(a.slice(0, 3), ctx).floor()) if a.size() >= 3 else Vector3i(ctx.pos.floor())
			world.level["spawn"] = [at3.x, at3.y, at3.z]
			_say(ctx, "Set the world spawn point to %d, %d, %d" % [at3.x, at3.y, at3.z])
			return 1
		"locate":
			return _locate(a, ctx)
		"say":
			_chat(ctx, "[%s] %s" % [_name(ctx.source), " ".join(a)])
			return 1
		"me":
			_chat(ctx, "* %s %s" % [_name(ctx.source), " ".join(a)])
			return 1
		"tell", "msg", "w":
			if a.size() < 2:
				return 0
			var n := 0
			for t in _players(a[0], ctx):
				if t == world.player:
					world.hud.chat_message("%s whispers to you: %s" % [_name(ctx.source), " ".join(a.slice(1))])
				n += 1
			_say(ctx, "You whisper to %d player(s): %s" % [n, " ".join(a.slice(1))])
			return n
		"tellraw":
			if a.size() < 2:
				return 0
			var txt := text_of(" ".join(a.slice(1)), ctx)
			var n := 0
			for t in _players(a[0], ctx):
				if t == world.player:
					world.hud.chat_message(txt)
				n += 1
			return n
		"title":
			return _title(a, ctx)
		"list":
			var names: Array = Net.player_names() if Net.active() else ["Player"]
			_say(ctx, "There are %d of a max of 8 players online: %s" % [names.size(), ", ".join(names)])
			return names.size()
		"save-all":
			world.save_all()
			_say(ctx, "Saved the game")
			return 1
		"save-off", "save-on":
			world.level["autosave"] = cmd == "save-on"
			_say(ctx, "Automatic saving is now " + ("enabled" if cmd == "save-on" else "disabled"))
			return 1
		"tick":
			_say(ctx, "Target tick rate: 20.0, current mspt: %.2f" % world.tick_ms)
			return 20
		"execute":
			return _execute(a, 0, ctx)
		"function":
			if a.is_empty():
				return 0
			return run_function(a[0], ctx)
		"reload":
			_functions.clear()
			_fn_loaded = false
			_load_tags()
			_say(ctx, "Reloading data packs (functions)")
			return 1
		"scoreboard":
			return _scoreboard(a, ctx)
		"team":
			return _team(a, ctx)
		"tag":
			if a.size() < 2:
				return 0
			var ts := _targets(a[0], ctx)
			if a[1] == "list":
				var tl := {}
				for t in ts:
					for tg in _tags_of(t):
						tl[tg] = true
				_say(ctx, "Tags: " + ", ".join(tl.keys()))
				return tl.size()
			if a.size() < 3:
				return 0
			var n := 0
			for t in ts:
				var tags := _tags_of(t)
				if a[1] == "add" and not tags.has(a[2]):
					tags.append(a[2])
					n += 1
				elif a[1] == "remove" and tags.has(a[2]):
					tags.erase(a[2])
					n += 1
				_set_tags(t, tags)
			_say(ctx, "%s tag '%s' on %d entities" % ["Added" if a[1] == "add" else "Removed", a[2], n])
			return n
		"bossbar":
			return _bossbar(a, ctx)
		"worldborder":
			var wb: Dictionary = world.level.get("worldborder", {"size": 59999968.0, "center": [0.0, 0.0]})
			if a.size() >= 2 and (a[0] == "set" or a[0] == "add"):
				wb["size"] = clampf(float(a[1]) + (float(wb["size"]) if a[0] == "add" else 0.0), 1.0, 59999968.0)
			elif a.size() >= 3 and a[0] == "center":
				var cp := _coords([a[1], "~", a[2]], ctx)
				wb["center"] = [cp.x, cp.z]
			elif a.size() >= 1 and a[0] == "get":
				_say(ctx, "The world border is currently %d block(s) wide" % int(wb["size"]))
				return int(wb["size"])
			else:
				_say(ctx, "Usage: /worldborder <set|add|center|get> ...")
				return 0
			world.level["worldborder"] = wb
			_say(ctx, "Set the world border to %d block(s) wide" % int(wb["size"]))
			return 1
		"damage":
			if a.size() < 2:
				return 0
			var n := 0
			for t in _targets(a[0], ctx):
				var src := a[2].trim_prefix("minecraft:") if a.size() > 2 else "generic"
				if t is Player:
					(t as Player).hurt(float(a[1]), src)
				else:
					world.entities._damage(t, float(a[1]), null)
				n += 1
			_say(ctx, "Applied %s damage to %d entities" % [a[1], n])
			return n
		"ride":
			if a.size() >= 3 and a[1] == "mount":
				var riders := _targets(a[0], ctx)
				var mounts := _targets(a[2], ctx)
				if riders.is_empty() or mounts.is_empty() or not (riders[0] is Player):
					_say(ctx, "Only players can ride (mobs riding mobs is not supported)")
					return 0
				Taming.mount(world.entities, mounts[0], riders[0])
				return 1
			if a.size() >= 2 and a[1] == "dismount":
				for t in _players(a[0], ctx):
					Taming.dismount(world.entities, t)
				return 1
			_say(ctx, "Usage: /ride <target> mount <vehicle> | dismount")
			return 0
		"particle":
			var at4 := _coords(a.slice(1, 4), ctx) if a.size() >= 4 else ctx.pos
			world.entities.spawn_hearts(at4) if a.size() > 0 and a[0].ends_with("heart") else world.entities.spawn_block_particles(Vector3i(at4.floor()), Res.blocks.default_state("stone"))
			return 1
		"playsound":
			if a.is_empty():
				return 0
			var at5 := _coords(a.slice(3, 6), ctx) if a.size() >= 6 else ctx.pos
			Audio.play(a[0].trim_prefix("minecraft:"), at5, (a[1] if a.size() > 1 else "master").capitalize(), float(a[6]) if a.size() > 6 else 1.0, float(a[7]) if a.size() > 7 else 1.0)
			return 1
		"stopsound":
			Audio.stop_all() if Audio.has_method("stop_all") else null
			return 1
		"advancement":
			return _advancement(a, ctx)
		"loot":
			if a.size() >= 4 and a[2] == "loot" and (a[0] == "give" or a[0] == "spawn"):
				var stacks := Loot.roll(a[3].trim_prefix("minecraft:"), {"rng": world.rng, "tool": ItemStack.new()})
				if a[0] == "give":
					for t in _players(a[1], ctx):
						for s2 in stacks:
							t.inventory.add((s2 as ItemStack).copy())
					world.inv_changed()
				else:
					var at6 := _coords(a.slice(1, 4), ctx) if false else ctx.pos
					for s3 in stacks:
						world.entities.spawn_item(at6, s3)
				_say(ctx, "Dropped %d stack(s)" % stacks.size())
				return stacks.size()
			_say(ctx, "Usage: /loot <give <players>|spawn> loot <table> (other sources not supported)")
			return 0
		"item":
			if a.size() >= 6 and a[0] == "replace" and a[1] == "entity" and a[4] == "with":
				var slot := _slot_index(a[3])
				var it2 := Res.items.id(a[5].split("[")[0].trim_prefix("minecraft:"))
				if slot < 0 or it2 <= 0:
					_say(ctx, "Unknown slot or item")
					return 0
				var n := 0
				for t in _players(a[2], ctx):
					t.inventory.set_slot(slot, ItemStack.of(it2, int(a[6]) if a.size() > 6 else 1))
					n += 1
				world.inv_changed()
				return n
			_say(ctx, "Usage: /item replace entity <targets> <slot> with <item> [count] (block slots not supported)")
			return 0
		"spreadplayers":
			if a.size() < 5:
				return 0
			var c := _coords([a[0], "~", a[1]], ctx)
			var rng2 := float(a[3])
			var n := 0
			for t in _targets(a[5] if a.size() > 5 else a[4], ctx):
				var q := Vector3(c.x + world.rng.randf_range(-rng2, rng2), 0, c.z + world.rng.randf_range(-rng2, rng2))
				if world.gen != null:
					q.y = world.gen.surface_height(int(q.x), int(q.z)) + 1
				_move_to(t, q)
				n += 1
			_say(ctx, "Spread %d entities" % n)
			return n
		"data":
			if a.size() >= 3 and a[0] == "get" and a[1] == "entity":
				var ts := _targets(a[2], ctx)
				if ts.is_empty():
					return 0
				var t0 = ts[0]
				var dd := {"Pos": [t0.pos.x, t0.pos.y, t0.pos.z]}
				if t0 is Player:
					dd["Health"] = t0.health
					dd["XpLevel"] = t0.xp_level
				else:
					dd["id"] = t0.id
					dd["Health"] = t0.hp
					dd["data"] = t0.data
				_say(ctx, "%s has the following entity data: %s" % [_name(t0), JSON.stringify(dd)])
				return 1
			if a.size() >= 5 and a[0] == "get" and a[1] == "block":
				var bp2 := Vector3i(_coords(a.slice(2, 5), ctx).floor())
				_say(ctx, "Block data: " + JSON.stringify(BlockEntities.get_data(world, bp2)))
				return 1
			_say(ctx, "Usage: /data get <entity <target>|block <pos>> (modify/merge not supported)")
			return 0
		"fillbiome":
			if a.size() < 7:
				return 0
			var b1 := _coords(a.slice(0, 3), ctx)
			var b2 := _coords(a.slice(3, 6), ctx)
			var bid: int = world.biomes.index.get(a[6].trim_prefix("minecraft:"), -1)
			if bid < 0:
				_say(ctx, "Unknown biome " + a[6])
				return 0
			var n := 0
			var mn := Vector3i(b1.min(b2).floor())
			var mx := Vector3i(b1.max(b2).floor())
			for cx in range(mn.x >> 4, (mx.x >> 4) + 1):
				for cz in range(mn.z >> 4, (mx.z >> 4) + 1):
					var ch: Chunk = world.cm.get_chunk(cx, cz)
					if ch == null:
						continue
					for i in ch.biomes.size():
						var qx := cx * 16 + (i & 3) * 4
						var qz := cz * 16 + ((i >> 2) & 3) * 4
						var qy := Coords.MIN_Y + (i >> 4) * 4
						if qx >= mn.x - 3 and qx <= mx.x and qz >= mn.z - 3 and qz <= mx.z and qy >= mn.y - 3 and qy <= mx.y:
							ch.biomes[i] = bid
							n += 1
					ch.modified = true
					ch.dirty_groups = 0x3F
					world.cm.kick()
			_say(ctx, "%d biome entries set" % n)
			return n
		"spectate":
			_say(ctx, "Spectating entities is not supported")
			return 0
		"publish":
			_say(ctx, Net.host(world))
			return 1 if Net.is_host() else 0
	return 0


# ------------------------------------------------------------------ helpers: parsing

func _split(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var depth := 0
	var quote := false
	for ch in s:
		if ch == "\"" and depth == 0:
			quote = not quote
		if not quote:
			if ch == "[" or ch == "{":
				depth += 1
			elif ch == "]" or ch == "}":
				depth -= 1
		if ch == " " and depth == 0 and not quote:
			if cur != "":
				out.append(cur)
			cur = ""
		else:
			cur += ch
	if cur != "":
		out.append(cur)
	return out


func _mode(a: String) -> int:
	match a.to_lower():
		"survival", "s", "0": return 0
		"creative", "c", "1": return 1
		"adventure", "a", "2": return 2
		"spectator", "sp", "3": return 3
	return -1


func _ticks(v: String) -> int:
	if v.ends_with("d"):
		return int(float(v.trim_suffix("d")) * 24000)
	if v.ends_with("s"):
		return int(float(v.trim_suffix("s")) * 20)
	if v.ends_with("t"):
		return int(v.trim_suffix("t"))
	return int(v)


func _coords(a: Array, ctx: Ctx) -> Vector3:
	if a.size() < 3:
		return ctx.pos
	if str(a[0]).begins_with("^"):
		var l := [_num(str(a[0]).substr(1)), _num(str(a[1]).substr(1)), _num(str(a[2]).substr(1))]
		var yr := deg_to_rad(ctx.yaw)
		var pr := deg_to_rad(ctx.pitch)
		var fwd := Vector3(-sin(yr) * cos(pr), -sin(pr), cos(yr) * cos(pr))
		var left := Vector3(cos(yr), 0, sin(yr))
		var up := fwd.cross(left).normalized() * -1.0
		var base := ctx.pos + (Vector3(0, 1.62, 0) if ctx.eyes else Vector3.ZERO)
		return base + left * l[0] + up * l[1] + fwd * l[2]
	var out := Vector3.ZERO
	for i in 3:
		var t := str(a[i])
		if t.begins_with("~"):
			out[i] = ctx.pos[i] + _num(t.substr(1))
		else:
			out[i] = float(t) + (0.5 if i != 1 and t.is_valid_int() else 0.0)
	return out


func _num(s: String) -> float:
	return float(s) if s != "" else 0.0


func _in_range(v: float, r: String) -> bool:
	if r.contains(".."):
		var lo := r.get_slice("..", 0)
		var hi := r.get_slice("..", 1)
		return (lo == "" or v >= float(lo)) and (hi == "" or v <= float(hi))
	return is_equal_approx(v, float(r))


# ------------------------------------------------------------------ helpers: targets

func _all_players() -> Array:
	var out: Array = [world.player]
	out.append_array(Net.proxies())
	return out


func _players(sel: String, ctx: Ctx) -> Array:
	var out: Array = []
	for t in _targets(sel, ctx):
		if t is Player:
			out.append(t)
	return out


func _name(t) -> String:
	if t == null:
		return "Server"
	if t is Player and "peer_id" in t:
		return str(Net.players.get(t.peer_id, {}).get("name", "Player"))
	if t is Player:
		return Net.my_name if Net.active() else "Player"
	return str(t.data.get("CustomName", t.id.capitalize())) if t.data is Dictionary else str(t.id)


## Selector / name -> Array of Player and EntityManager.Ent targets (Java EntitySelector subset).
func _targets(sel: String, ctx: Ctx) -> Array:
	if not sel.begins_with("@"):
		var out0: Array = []
		for pl in _all_players():
			if _name(pl) == sel:
				out0.append(pl)
		return out0
	var kind := sel.substr(0, 2)
	var args := {}
	var b := sel.find("[")
	if b > 0:
		for kv in _split_args(sel.substr(b + 1, sel.length() - b - 2)):
			var k := kv.get_slice("=", 0).strip_edges()
			var v := kv.substr(kv.find("=") + 1).strip_edges()
			if not args.has(k):
				args[k] = []
			args[k].append(v)
	var pool: Array = []
	match kind:
		"@s":
			if ctx.source != null:
				pool = [ctx.source]
		"@a", "@p", "@r":
			pool = _all_players()
		"@e", "@n":
			pool = _all_players()
			for e in world.entities.ents:
				if not e.dead and e.kind != "falling":
					pool.append(e)
	var origin := ctx.pos
	if args.has("x") or args.has("y") or args.has("z"):
		origin = Vector3(float(args.get("x", [origin.x])[0]), float(args.get("y", [origin.y])[0]), float(args.get("z", [origin.z])[0]))
	var out: Array = []
	for t in pool:
		if _matches(t, args, origin):
			out.append(t)
	var sort := str(args.get("sort", ["arbitrary"])[0])
	if kind == "@p" or kind == "@n":
		sort = "nearest"
	elif kind == "@r":
		sort = "random"
	match sort:
		"nearest":
			out.sort_custom(func(x, y): return x.pos.distance_squared_to(origin) < y.pos.distance_squared_to(origin))
		"furthest":
			out.sort_custom(func(x, y): return x.pos.distance_squared_to(origin) > y.pos.distance_squared_to(origin))
		"random":
			out.shuffle()
	var lim := int(args.get("limit", ["1" if kind in ["@p", "@r", "@n", "@s"] else "2147483647"])[0])
	return out.slice(0, lim)


func _split_args(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var depth := 0
	for ch in s:
		if ch == "{" or ch == "[":
			depth += 1
		elif ch == "}" or ch == "]":
			depth -= 1
		if ch == "," and depth == 0:
			out.append(cur)
			cur = ""
		else:
			cur += ch
	if cur.strip_edges() != "":
		out.append(cur)
	return out


func _matches(t, args: Dictionary, origin: Vector3) -> bool:
	if t is Player and (t as Player).dead:
		return false
	for k in args:
		for v0 in args[k]:
			var v := str(v0)
			var neg := v.begins_with("!")
			if neg:
				v = v.substr(1)
			var ok := true
			match k:
				"type":
					var tid := "player" if t is Player else str(t.id if t.kind == "mob" else t.kind)
					if t is EntityManager.Ent and t.kind == "boat":
						tid = t.id
					if v.begins_with("#"):
						ok = Tags.resolve("entity_type", v).has(tid)
					else:
						ok = v.trim_prefix("minecraft:") == tid
				"distance":
					ok = _in_range(t.pos.distance_to(origin), v)
				"name":
					ok = _name(t) == v.trim_prefix("\"").trim_suffix("\"")
				"tag":
					ok = _tags_of(t).has(v) if v != "" else _tags_of(t).is_empty()
				"gamemode":
					ok = t is Player and int(t.mode) == _mode(v)
				"level":
					ok = t is Player and _in_range(float(t.xp_level), v)
				"dx", "dy", "dz":
					var lo: Vector3 = origin
					var size := Vector3(float(args.get("dx", ["0"])[0]), float(args.get("dy", ["0"])[0]), float(args.get("dz", ["0"])[0]))
					var bmin := lo.min(lo + size)
					var bmax := lo.max(lo + size) + Vector3.ONE
					ok = t.pos.x >= bmin.x and t.pos.x <= bmax.x and t.pos.y >= bmin.y and t.pos.y <= bmax.y and t.pos.z >= bmin.z and t.pos.z <= bmax.z
				"scores":
					for pair in _split_args(v.trim_prefix("{").trim_suffix("}")):
						var obj := pair.get_slice("=", 0).strip_edges()
						var sc = _get_score(_holder(t), obj)
						if sc == null or not _in_range(float(sc), pair.get_slice("=", 1).strip_edges()):
							ok = false
				"x", "y", "z", "limit", "sort":
					ok = true
			if ok == neg:
				return false
	return true


func _move_to(t, q: Vector3) -> void:
	if t is Player:
		var pl: Player = t
		if pl.vehicle != null:
			Taming.dismount(world.entities, pl)
		pl.pos = q
		pl.prev_pos = q
		pl.vel = Vector3.ZERO
		pl.fall_distance = 0.0
		if pl == world.player:
			world._update_origin(true)
	else:
		t.pos = q
		t.prev = q
		t.vel = Vector3.ZERO


func _tags_of(t) -> Array:
	if t is Player:
		var pt = world.level.get("player_tags", [])
		return pt if pt is Array else []
	return t.data.get("tags", []) if t.data is Dictionary else []


func _set_tags(t, tags: Array) -> void:
	if t is Player:
		world.level["player_tags"] = tags
	else:
		t.data["tags"] = tags


func _holder(t) -> String:
	if t is Player:
		return _name(t)
	if t is EntityManager.Ent:
		if t.uid == 0:
			t.uid = world.rng.randi_range(1, 1 << 30)
		return "#e" + str(t.uid)
	return str(t)


# ------------------------------------------------------------------ commands: tp, fill, clone, locate, title

func _tp(a: PackedStringArray, ctx: Ctx) -> int:
	# forms: <dest> | <x y z> [yaw pitch] | <targets> <dest> | <targets> <x y z> [yaw pitch]
	var targets: Array = [ctx.source] if ctx.source != null else []
	var rest := a
	if a.size() == 2 or a.size() == 4 or a.size() == 6:
		targets = _targets(a[0], ctx)
		rest = a.slice(1)
	if rest.size() == 1:
		var dest := _targets(rest[0], ctx)
		if dest.is_empty():
			_say(ctx, "No entity was found")
			return 0
		for t in targets:
			_move_to(t, dest[0].pos)
		_say(ctx, "Teleported %d entities to %s" % [targets.size(), _name(dest[0])])
		return targets.size()
	if rest.size() >= 3:
		var q := _coords(rest.slice(0, 3), ctx)
		for t in targets:
			_move_to(t, q)
			if rest.size() >= 5:
				t.yaw = float(rest[3].trim_prefix("~")) + (t.yaw if rest[3].begins_with("~") else 0.0)
				if t is Player:
					t.pitch = clampf(float(rest[4].trim_prefix("~")), -90, 90)
		_say(ctx, "Teleported %d entities to %.1f, %.1f, %.1f" % [targets.size(), q.x, q.y, q.z])
		return targets.size()
	_say(ctx, "Usage: /tp [targets] <pos|destination> [yaw pitch]")
	return 0


func _fill(a: PackedStringArray, ctx: Ctx) -> int:
	if a.size() < 7:
		_say(ctx, "Usage: /fill <from> <to> <block> [replace [filter]|destroy|keep|hollow|outline]")
		return 0
	var b1 := _coords(a.slice(0, 3), ctx)
	var b2 := _coords(a.slice(3, 6), ctx)
	var st := Res.blocks.parse_state(a[6].trim_prefix("minecraft:"))
	if st < 0:
		_say(ctx, "Unknown block " + a[6])
		return 0
	var mode := a[7] if a.size() > 7 else "replace"
	var filt := -1
	if mode == "replace" and a.size() > 8:
		filt = Res.blocks.block_id(a[8].trim_prefix("minecraft:"))
	var mn := Vector3i(b1.min(b2).floor())
	var mx := Vector3i(b1.max(b2).floor())
	var vol := (mx.x - mn.x + 1) * (mx.y - mn.y + 1) * (mx.z - mn.z + 1)
	if vol > 32768:
		_say(ctx, "Too many blocks in the specified area (maximum 32768, specified %d)" % vol)
		return 0
	var n := 0
	for x in range(mn.x, mx.x + 1):
		for y in range(mn.y, mx.y + 1):
			for z in range(mn.z, mx.z + 1):
				var edge := x == mn.x or x == mx.x or y == mn.y or y == mx.y or z == mn.z or z == mx.z
				var cur: int = world.state_at(x, y, z)
				var want := st
				match mode:
					"keep":
						if cur != 0:
							continue
					"hollow":
						if not edge:
							want = 0
					"outline":
						if not edge:
							continue
					"destroy":
						if cur > 0:
							world._break_block(Vector3i(x, y, z), true)
					"replace":
						if filt >= 0 and (cur <= 0 or Res.blocks.st_block[cur] != filt):
							continue
				if cur != want and world.set_block(x, y, z, want) >= 0:
					if Res.blocks.st_flags[want] & (BlockRegistry.F_LIQUID | BlockRegistry.F_GRAVITY):
						BlockUpdates.schedule(world, Vector3i(x, y, z), 5)
					n += 1
	_say(ctx, "Successfully filled %d block(s)" % n)
	return n


func _clone(a: PackedStringArray, ctx: Ctx) -> int:
	if a.size() < 9:
		_say(ctx, "Usage: /clone <begin> <end> <destination> [replace|masked] [normal|force|move]")
		return 0
	var b1 := Vector3i(_coords(a.slice(0, 3), ctx).floor())
	var b2 := Vector3i(_coords(a.slice(3, 6), ctx).floor())
	var dst := Vector3i(_coords(a.slice(6, 9), ctx).floor())
	var mn := Vector3i(mini(b1.x, b2.x), mini(b1.y, b2.y), mini(b1.z, b2.z))
	var mx := Vector3i(maxi(b1.x, b2.x), maxi(b1.y, b2.y), maxi(b1.z, b2.z))
	var vol := (mx.x - mn.x + 1) * (mx.y - mn.y + 1) * (mx.z - mn.z + 1)
	if vol > 32768:
		_say(ctx, "Too many blocks in the specified area (maximum 32768, specified %d)" % vol)
		return 0
	var masked := a.size() > 9 and a[9] == "masked"
	var move := a.size() > 10 and a[10] == "move"
	var buf: Array = []
	for x in range(mn.x, mx.x + 1):
		for y in range(mn.y, mx.y + 1):
			for z in range(mn.z, mx.z + 1):
				var q := Vector3i(x, y, z)
				buf.append([q - mn, world.state_at(x, y, z), BlockEntities.get_data(world, q).duplicate(true)])
	if move:
		for e in buf:
			var q2: Vector3i = mn + e[0]
			world.set_block(q2.x, q2.y, q2.z, 0, false)
	var n := 0
	for e in buf:
		if masked and int(e[1]) == 0:
			continue
		var q3: Vector3i = dst + e[0]
		if world.set_block(q3.x, q3.y, q3.z, maxi(int(e[1]), 0)) >= 0:
			n += 1
			if not (e[2] as Dictionary).is_empty():
				BlockEntities.set_data(world, q3, e[2])
	_say(ctx, "Successfully cloned %d block(s)" % n)
	return n


func _locate(a: PackedStringArray, ctx: Ctx) -> int:
	if a.size() >= 2 and a[0] == "biome":
		_say(ctx, _locate_biome(a[1].trim_prefix("minecraft:"), ctx))
		return 1
	if a.size() >= 2 and a[0] == "structure":
		var sname := a[1].trim_prefix("minecraft:")
		if not (world.gen is VanillaGenerator) or (world.gen as VanillaGenerator).structures == null:
			_say(ctx, "Structures are not available with this world generator")
			return 0
		# searched on a worker (the main thread kept stalling for seconds); the answer is posted to chat with Java's
		# green clickable [x, ~, z] (click: /tp @s x ~ z)
		var pp := ctx.pos
		var sts = (world.gen as VanillaGenerator).structures
		var hud = world.hud
		WorkerThreadPool.add_task(func():
			var res: Dictionary = sts.locate(sname, int(floor(pp.x)) >> 4, int(floor(pp.z)) >> 4)
			if res.is_empty():
				hud.call_deferred("chat_message", "Could not find a structure of type " + sname + " nearby")
				return
			var ch: Vector2i = res["chunk"]
			var bx := ch.x * 16 + 8
			var bz := ch.y * 16 + 8
			var dist := int(Vector2(bx - pp.x, bz - pp.z).length())
			hud.call_deferred("chat_message", "The nearest %s is at [%d, ~, %d] (%d blocks away)" % [sname, bx, bz, dist], "/tp @s %d ~ %d" % [bx, bz]))
		return 1
	_say(ctx, "Usage: /locate biome <biome> | /locate structure <structure> (poi not supported)")
	return 0


func _locate_biome(name: String, ctx: Ctx) -> String:
	var bid: int = world.biomes.index.get(name, -1)
	if bid < 0:
		return "There is no biome with type \"%s\"" % name
	if world.gen is VanillaGenerator:
		# biome-source search (Java findClosestBiome3d) runs on a worker; the answer is posted to chat
		var vg: VanillaGenerator = world.gen
		var hud = world.hud
		var px := int(floor(ctx.pos.x))
		var py := int(floor(ctx.pos.y))
		var pz := int(floor(ctx.pos.z))
		WorkerThreadPool.add_task(func():
			var at: Vector3i = vg.find_biome(bid, px, py, pz)
			var msg := "Could not find a biome of type \"%s\" within 2048 blocks" % name
			var tp_cmd := ""
			if at.y != -999999:
				msg = "The nearest %s is at [%d, %d, %d] (%d blocks away)" % [name, at.x, at.y, at.z, int(Vector2(at.x - px, at.z - pz).length())]
				tp_cmd = "/tp @s %d %d %d" % [at.x, at.y, at.z]
			hud.call_deferred("chat_message", msg, tp_cmd))
		return "Locating %s..." % name
	for r in range(0, 32):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var c: Chunk = world.cm.get_chunk((int(ctx.pos.x) >> 4) + dx, (int(ctx.pos.z) >> 4) + dz)
				if c == null:
					continue
				for i in 16:
					if c.biomes[i + 16 * 30] == bid:
						return "The nearest %s is at [%d, ~, %d]" % [name, c.cx * 16 + 8, c.cz * 16 + 8]
	return "Could not find a biome of type \"%s\" within loaded chunks" % name


func _title(a: PackedStringArray, ctx: Ctx) -> int:
	if a.size() < 2:
		return 0
	var ps := _players(a[0], ctx)
	var mine := ps.has(world.player)
	match a[1]:
		"clear", "reset":
			if mine:
				world.hud.set_title("", "", "")
		"title", "subtitle", "actionbar":
			if a.size() < 3:
				return 0
			if mine:
				var txt := text_of(" ".join(a.slice(2)), ctx)
				world.hud.set_title(txt if a[1] == "title" else null, txt if a[1] == "subtitle" else null, txt if a[1] == "actionbar" else null)
		"times":
			if mine and a.size() >= 5:
				world.hud.title_times = [_ticks(a[2]), _ticks(a[3]), _ticks(a[4])]
		_:
			return 0
	return ps.size()


## Java text component (JSON or plain string) -> plain text (translate keys resolved; selectors/scores substituted).
func text_of(raw: String, ctx: Ctx = null) -> String:
	var j = JSON.parse_string(raw)
	if j == null:
		return raw.trim_prefix("\"").trim_suffix("\"")
	return _component(j, ctx)


func _component(j, ctx: Ctx) -> String:
	if j is String:
		return j
	if j is float or j is int or j is bool:
		return str(j)
	if j is Array:
		var s := ""
		for e in j:
			s += _component(e, ctx)
		return s
	if j is Dictionary:
		var s2 := ""
		if j.has("text"):
			s2 = str(j["text"])
		elif j.has("translate"):
			var key := str(j["translate"])
			s2 = Res.tr_key(key, str(j.get("fallback", key)))
			for w in j.get("with", []):
				s2 = s2.replace("%s", _component(w, ctx)) if s2.contains("%s") else s2
		elif j.has("selector") and ctx != null:
			var names: Array = []
			for t in _targets(str(j["selector"]), ctx):
				names.append(_name(t))
			s2 = ", ".join(names)
		elif j.has("score") and j["score"] is Dictionary:
			var sc: Dictionary = j["score"]
			var holder := str(sc.get("name", ""))
			if holder.begins_with("@") and ctx != null:
				var ts := _targets(holder, ctx)
				holder = _holder(ts[0]) if not ts.is_empty() else holder
			s2 = str(_get_score(holder, str(sc.get("objective", ""))) if _get_score(holder, str(sc.get("objective", ""))) != null else "")
		for e2 in j.get("extra", []):
			s2 += _component(e2, ctx)
		return s2
	return ""


func _chat(_ctx: Ctx, msg: String) -> void:
	if Net.active():
		Net._chat_all(msg)
	else:
		world.hud.chat_message(msg)


# ------------------------------------------------------------------ /execute

func _execute(a: PackedStringArray, i: int, ctx: Ctx) -> int:
	if i >= a.size():
		return 1
	var sub := a[i]
	match sub:
		"run":
			return run(" ".join(a.slice(i + 1)), ctx)
		"as":
			var n := 0
			for t in _targets(a[i + 1], ctx):
				var c := ctx.copy()
				c.source = t
				n += _execute(a, i + 2, c)
			return n
		"at":
			var n2 := 0
			for t in _targets(a[i + 1], ctx):
				var c2 := ctx.copy()
				c2.pos = t.pos
				c2.yaw = t.yaw
				c2.pitch = t.pitch if t is Player else 0.0
				n2 += _execute(a, i + 2, c2)
			return n2
		"positioned":
			var c3 := ctx.copy()
			if a[i + 1] == "as":
				var n3 := 0
				for t in _targets(a[i + 2], ctx):
					var c4 := ctx.copy()
					c4.pos = t.pos
					n3 += _execute(a, i + 3, c4)
				return n3
			c3.pos = _coords(a.slice(i + 1, i + 4), ctx)
			return _execute(a, i + 4, c3)
		"rotated":
			if a[i + 1] == "as":
				var n4 := 0
				for t in _targets(a[i + 2], ctx):
					var c5 := ctx.copy()
					c5.yaw = t.yaw
					c5.pitch = t.pitch if t is Player else 0.0
					n4 += _execute(a, i + 3, c5)
				return n4
			var c6 := ctx.copy()
			c6.yaw = float(a[i + 1].trim_prefix("~")) + (ctx.yaw if a[i + 1].begins_with("~") else 0.0)
			c6.pitch = float(a[i + 2].trim_prefix("~")) + (ctx.pitch if a[i + 2].begins_with("~") else 0.0)
			return _execute(a, i + 3, c6)
		"facing":
			var tgt := Vector3.ZERO
			var skip := 4
			if a[i + 1] == "entity":
				var ts := _targets(a[i + 2], ctx)
				if ts.is_empty():
					return 0
				tgt = ts[0].pos + (Vector3(0, 1.62, 0) if a.size() > i + 3 and a[i + 3] == "eyes" else Vector3.ZERO)
			else:
				tgt = _coords(a.slice(i + 1, i + 4), ctx)
			var c7 := ctx.copy()
			var dv := tgt - ctx.pos
			c7.yaw = rad_to_deg(atan2(-dv.x, dv.z))
			c7.pitch = rad_to_deg(-atan2(dv.y, Vector2(dv.x, dv.z).length()))
			return _execute(a, i + skip, c7)
		"anchored":
			var c8 := ctx.copy()
			c8.eyes = a[i + 1] == "eyes"
			return _execute(a, i + 2, c8)
		"align":
			var c9 := ctx.copy()
			for ax in a[i + 1]:
				var k := "xyz".find(ax)
				if k >= 0:
					c9.pos[k] = floor(c9.pos[k])
			return _execute(a, i + 2, c9)
		"in":
			if a[i + 1].trim_prefix("minecraft:") != world.dimension:
				_say(ctx, "Running commands in another dimension is not supported")
				return 0
			return _execute(a, i + 2, ctx)
		"if", "unless":
			var want := sub == "if"
			var res := _condition(a, i + 1, ctx)
			if res[0] != want:
				return 0
			return _execute(a, int(res[1]), ctx)
		"store":
			# store <result|success> score <targets> <objective> ...
			if a.size() > i + 4 and a[i + 2] == "score":
				var success := a[i + 1] == "success"
				var holders := _targets(a[i + 3], ctx)
				var obj := a[i + 4]
				var r := _execute(a, i + 5, ctx)
				for t in holders:
					_set_score(_holder(t), obj, (1 if r > 0 else 0) if success else r)
				return r
			_say(ctx, "Only 'execute store result|success score' is supported")
			return 0
	_say(ctx, "Unknown execute subcommand: " + sub)
	return 0


## Returns [passed: bool, next index].
func _condition(a: PackedStringArray, i: int, ctx: Ctx) -> Array:
	match a[i]:
		"block":
			var q := Vector3i(_coords(a.slice(i + 1, i + 4), ctx).floor())
			var want := a[i + 4].trim_prefix("minecraft:")
			var st: int = world.state_at(q.x, q.y, q.z)
			var nm := Res.blocks.name_of(maxi(st, 0)) if st > 0 else "air"
			var ok := nm == want.split("[")[0] if not want.begins_with("#") else Tags.has_block(want.substr(1).trim_prefix("minecraft:"), nm)
			return [ok, i + 5]
		"entity":
			return [not _targets(a[i + 1], ctx).is_empty(), i + 2]
		"score":
			var ts := _targets(a[i + 1], ctx)
			var v = _get_score(_holder(ts[0]), a[i + 2]) if not ts.is_empty() else null
			if a[i + 3] == "matches":
				return [v != null and _in_range(float(v), a[i + 4]), i + 5]
			var src := _targets(a[i + 4], ctx)
			var w = _get_score(_holder(src[0]), a[i + 5]) if not src.is_empty() else null
			if v == null or w == null:
				return [false, i + 6]
			var ok2 := false
			match a[i + 3]:
				"<": ok2 = v < w
				"<=": ok2 = v <= w
				"=": ok2 = v == w
				">=": ok2 = v >= w
				">": ok2 = v > w
			return [ok2, i + 6]
	_say(ctx, "Unsupported execute condition: " + a[i])
	return [false, a.size()]


# ------------------------------------------------------------------ scoreboard / teams / bossbars / advancements

func _sb() -> Dictionary:
	if not (world.level.get("scoreboard") is Dictionary):
		world.level["scoreboard"] = {"objectives": {}, "scores": {}, "display": {}, "teams": {}}
	return world.level["scoreboard"]


func _get_score(holder: String, obj: String):
	var sc: Dictionary = _sb()["scores"]
	if sc.has(holder) and (sc[holder] as Dictionary).has(obj):
		return int(sc[holder][obj])
	return null


func _set_score(holder: String, obj: String, v: int) -> void:
	var sb := _sb()
	if not (sb["objectives"] as Dictionary).has(obj):
		return
	if not (sb["scores"] as Dictionary).has(holder):
		sb["scores"][holder] = {}
	sb["scores"][holder][obj] = v


func _score_holders(s: String, ctx: Ctx) -> Array:
	if s == "*":
		return (_sb()["scores"] as Dictionary).keys()
	if s.begins_with("@"):
		var out: Array = []
		for t in _targets(s, ctx):
			out.append(_holder(t))
		return out
	return [s]


func _scoreboard(a: PackedStringArray, ctx: Ctx) -> int:
	var sb := _sb()
	if a.size() >= 2 and a[0] == "objectives":
		match a[1]:
			"add":
				if a.size() < 4 or (sb["objectives"] as Dictionary).has(a[2]):
					_say(ctx, "An objective already exists by that name" if a.size() >= 4 else "Usage: /scoreboard objectives add <name> <criteria> [display]")
					return 0
				sb["objectives"][a[2]] = {"criteria": a[3], "display": text_of(" ".join(a.slice(4)), ctx) if a.size() > 4 else a[2]}
				_say(ctx, "Created new objective [%s]" % a[2])
				return 1
			"remove":
				sb["objectives"].erase(a[2])
				for h in sb["scores"]:
					(sb["scores"][h] as Dictionary).erase(a[2])
				for slot in (sb["display"] as Dictionary).keys():
					if sb["display"][slot] == a[2]:
						sb["display"].erase(slot)
				return 1
			"list":
				_say(ctx, "Objectives: " + ", ".join((sb["objectives"] as Dictionary).keys()))
				return (sb["objectives"] as Dictionary).size()
			"setdisplay":
				if a.size() >= 4:
					sb["display"][a[2]] = a[3]
				elif a.size() == 3:
					sb["display"].erase(a[2])
				return 1
	if a.size() >= 2 and a[0] == "players":
		match a[1]:
			"set", "add", "remove":
				if a.size() < 5 or not (sb["objectives"] as Dictionary).has(a[3]):
					_say(ctx, "Unknown scoreboard objective")
					return 0
				var n := 0
				for h in _score_holders(a[2], ctx):
					var cur = _get_score(h, a[3])
					var v := int(a[4])
					var nv: int = v if a[1] == "set" else (int(cur if cur != null else 0) + (v if a[1] == "add" else -v))
					_set_score(h, a[3], nv)
					n += 1
				return n
			"get":
				var v2 = _get_score(_score_holders(a[2], ctx)[0], a[3]) if a.size() >= 4 else null
				if v2 == null:
					_say(ctx, "No score for that holder")
					return 0
				_say(ctx, "%s has %d [%s]" % [a[2], v2, a[3]])
				return v2
			"reset":
				for h in _score_holders(a[2], ctx):
					if a.size() > 3:
						(sb["scores"].get(h, {}) as Dictionary).erase(a[3])
					else:
						sb["scores"].erase(h)
				return 1
			"list":
				_say(ctx, "Tracked: " + ", ".join((sb["scores"] as Dictionary).keys()))
				return (sb["scores"] as Dictionary).size()
			"operation":
				if a.size() < 7:
					return 0
				var srcs := _score_holders(a[5], ctx)
				var sv = _get_score(srcs[0], a[6]) if not srcs.is_empty() else null
				if sv == null:
					return 0
				var n2 := 0
				for h in _score_holders(a[2], ctx):
					var tv = _get_score(h, a[3])
					var t := int(tv if tv != null else 0)
					var s := int(sv)
					match a[4]:
						"+=": t += s
						"-=": t -= s
						"*=": t *= s
						"/=": t = floori(float(t) / float(s)) if s != 0 else t
						"%=": t = posmod(t, s) if s != 0 else t
						"=": t = s
						"<": t = mini(t, s)
						">": t = maxi(t, s)
					_set_score(h, a[3], t)
					n2 += 1
				return n2
	_say(ctx, "Usage: /scoreboard objectives|players ...")
	return 0


func _team(a: PackedStringArray, ctx: Ctx) -> int:
	var teams: Dictionary = _sb()["teams"]
	if a.size() >= 2 and a[0] == "add":
		teams[a[1]] = {"members": [], "display": a[1]}
		return 1
	if a.size() >= 2 and a[0] == "remove":
		teams.erase(a[1])
		return 1
	if a.size() >= 2 and a[0] == "join" and teams.has(a[1]):
		var n := 0
		for h in _score_holders(a[2] if a.size() > 2 else "@s", ctx):
			for tn in teams:
				(teams[tn]["members"] as Array).erase(h)
			(teams[a[1]]["members"] as Array).append(h)
			n += 1
		return n
	if a.size() >= 2 and a[0] == "leave":
		for h in _score_holders(a[1], ctx):
			for tn in teams:
				(teams[tn]["members"] as Array).erase(h)
		return 1
	if a.size() >= 1 and a[0] == "list":
		_say(ctx, "Teams: " + ", ".join(teams.keys()))
		return teams.size()
	_say(ctx, "Usage: /team add|remove|join|leave|list (modify not supported)")
	return 0


func _bossbar(a: PackedStringArray, ctx: Ctx) -> int:
	if not (world.level.get("bossbars") is Dictionary):
		world.level["bossbars"] = {}
	var bars: Dictionary = world.level["bossbars"]
	if a.size() >= 3 and a[0] == "add":
		bars[a[1]] = {"name": text_of(" ".join(a.slice(2)), ctx), "value": 0, "max": 100, "color": "white", "visible": true}
		return 1
	if a.size() >= 2 and a[0] == "remove":
		bars.erase(a[1])
		return 1
	if a.size() >= 4 and a[0] == "set" and bars.has(a[1]):
		var b: Dictionary = bars[a[1]]
		match a[2]:
			"value": b["value"] = int(a[3])
			"max": b["max"] = maxi(1, int(a[3]))
			"name": b["name"] = text_of(" ".join(a.slice(3)), ctx)
			"color": b["color"] = a[3]
			"visible": b["visible"] = a[3] == "true"
			"players": b["visible"] = true
		return 1
	if a.size() >= 3 and a[0] == "get" and bars.has(a[1]):
		var b2: Dictionary = bars[a[1]]
		var v: int = int(b2.get(a[2], 0)) if a[2] in ["value", "max"] else (1 if b2.get("visible", true) else 0)
		_say(ctx, "Bossbar %s %s is %d" % [a[1], a[2], v])
		return v
	if a.size() >= 1 and a[0] == "list":
		_say(ctx, "Bossbars: " + ", ".join(bars.keys()))
		return bars.size()
	_say(ctx, "Usage: /bossbar add|remove|set|get|list ...")
	return 0


## Java AdvancementCommands: grant / revoke <targets> everything | only <advancement> [<criterion>] | from | until |
## through <advancement> (from = it + descendants, until = ancestors + it, through = both). Granting awards like
## progress does (toast + chat announcement); messages per commands.advancement.<grant|revoke>.*.
func _advancement(a: PackedStringArray, ctx: Ctx) -> int:
	if world.advancements == null or a.size() < 3 or not (a[0] in ["grant", "revoke"]):
		_say(ctx, "Usage: /advancement (grant|revoke) <targets> (everything|only|from|until|through) ...")
		return 0
	var adv: Advancements = world.advancements
	var grant := a[0] == "grant"
	var mode := a[2]
	var ids: Array = []
	var target := a[3].trim_prefix("minecraft:") if a.size() > 3 else ""
	if mode != "everything" and not adv.defs.has(target):
		_say(ctx, "Unknown advancement: minecraft:%s" % target)
		return 0
	match mode:
		"everything":
			ids = adv.defs.keys()
		"only":
			if a.size() > 4:
				# a single criterion
				var cn := a[4]
				if not (adv.defs[target]["criteria"] as Dictionary).has(cn):
					_say(ctx, "Advancement %s does not contain the criterion '%s'" % [_adv_title(adv, target), cn])
					return 0
				var had: bool = (adv.progress.get(target, {}) as Dictionary).has(cn)
				if grant == had:
					_say(ctx, "Couldn't %s criterion '%s' of advancement %s %s Player as they %s" % ["grant" if grant else "revoke", cn, _adv_title(adv, target), "to" if grant else "from", "already have it" if grant else "don't have it"])
					return 0
				if grant:
					if not adv.progress.has(target):
						adv.progress[target] = {}
					adv.progress[target][cn] = true
					if not adv.done.has(target) and adv._complete(target):
						adv.done[target] = true
						adv._award(target)
				else:
					(adv.progress[target] as Dictionary).erase(cn)
					adv.done.erase(target)
				_say(ctx, "%s criterion '%s' of advancement %s %s Player" % ["Granted" if grant else "Revoked", cn, _adv_title(adv, target), "to" if grant else "from"])
				return 1
			ids = [target]
		"from", "until", "through":
			if mode != "from":
				var c := target
				while c != "" and adv.defs.has(c):
					ids.push_front(c)
					c = str(adv.defs[c]["parent"]).trim_prefix("minecraft:")
			else:
				ids.append(target)
			if mode != "until":
				var queue: Array = [target]
				while not queue.is_empty():
					var cur: String = queue.pop_front()
					for id2 in adv.defs:
						if str(adv.defs[id2]["parent"]).trim_prefix("minecraft:") == cur and not ids.has(id2):
							ids.append(id2)
							queue.append(id2)
		_:
			_say(ctx, "Usage: /advancement (grant|revoke) <targets> (everything|only|from|until|through) ...")
			return 0
	var n := 0
	for id in ids:
		if not adv.defs.has(id):
			continue
		if grant:
			if adv.done.has(id):
				continue
			var crit: Dictionary = {}
			for cn2 in adv.defs[id]["criteria"]:
				crit[cn2] = true
			adv.progress[id] = crit
			adv.done[id] = true
			adv._award(id)
			n += 1
		else:
			var was: bool = adv.done.has(id) or adv.progress.has(id)
			adv.progress.erase(id)
			adv.done.erase(id)
			if was:
				n += 1
	if n == 0:
		if ids.size() == 1:
			_say(ctx, "Couldn't %s advancement %s %s Player as they %s" % ["grant" if grant else "revoke", _adv_title(adv, ids[0]), "to" if grant else "from", "already have it" if grant else "don't have it"])
		else:
			_say(ctx, "Couldn't %s %d advancements %s Player as they %s" % ["grant" if grant else "revoke", ids.size(), "to" if grant else "from", "already have them" if grant else "don't have them"])
		return 0
	if ids.size() == 1:
		_say(ctx, "%s the advancement %s %s Player" % ["Granted" if grant else "Revoked", _adv_title(adv, ids[0]), "to" if grant else "from"])
	else:
		_say(ctx, "%s %d advancements %s Player" % ["Granted" if grant else "Revoked", n, "to" if grant else "from"])
	return n


func _adv_title(adv: Advancements, id: String) -> String:
	return "[%s]" % str(adv.defs[id].get("title", id))

func _slot_index(s: String) -> int:
	if s.begins_with("hotbar."):
		return int(s.substr(7))
	if s.begins_with("inventory."):
		return 9 + int(s.substr(10))
	match s:
		"weapon", "weapon.mainhand":
			return world.player.inventory.selected
		"weapon.offhand":
			return Inventory.OFFHAND
		"armor.feet":
			return Inventory.ARMOR0
		"armor.legs":
			return Inventory.ARMOR0 + 1
		"armor.chest":
			return Inventory.ARMOR0 + 2
		"armor.head":
			return Inventory.ARMOR0 + 3
	return -1


func _apply_nbt(e, raw: String) -> void:
	# summon NBT subset: NoAI, Invulnerable->persistent, CustomName, Tags, Age, Health
	var s := raw
	if s.contains("NoAI:1") or s.contains("NoAI:1b") or s.contains("NoAI:true"):
		e.noai = true
	if s.contains("PersistenceRequired:1"):
		e.persistent = true
	var cn := s.find("CustomName:")
	if cn >= 0:
		var q0 := s.find("\"", cn)
		var q1 := s.find("\"", q0 + 1)
		if q0 >= 0 and q1 > q0:
			e.data["CustomName"] = s.substr(q0 + 1, q1 - q0 - 1)
	var tg := s.find("Tags:[")
	if tg >= 0:
		var tags: Array = []
		for t in s.substr(tg + 6, s.find("]", tg) - tg - 6).split(","):
			tags.append(t.strip_edges().trim_prefix("\"").trim_suffix("\""))
		e.data["tags"] = tags
	if s.contains("Age:-"):
		e.baby_age = -24000


# ------------------------------------------------------------------ data-pack functions

func _pack_root() -> String:
	return SaveManager.ROOT.path_join(world.folder).path_join("datapacks")


func _function_lines(id: String) -> PackedStringArray:
	var key := id if id.contains(":") else "minecraft:" + id
	if _functions.has(key):
		return _functions[key]
	var ns := key.get_slice(":", 0)
	var path := key.get_slice(":", 1)
	var lines := PackedStringArray()
	var root := _pack_root()
	if DirAccess.dir_exists_absolute(root):
		for pack in DirAccess.get_directories_at(root):
			for sub in ["function", "functions"]:
				var f := root.path_join(pack).path_join("data").path_join(ns).path_join(sub).path_join(path + ".mcfunction")
				if FileAccess.file_exists(f):
					lines = FileAccess.get_file_as_string(f).split("\n")
	_functions[key] = lines
	return lines


func run_function(id: String, ctx: Ctx) -> int:
	if id.begins_with("#"):
		var n0 := 0
		for f in _function_tag(id.substr(1)):
			n0 += run_function(f, ctx)
		return n0
	var lines := _function_lines(id.trim_prefix("minecraft:") if not id.contains(":") else id)
	if lines.is_empty():
		_say(ctx, "Unknown function " + id)
		return 0
	var n := 0
	var c := ctx.copy()
	c.silent = true
	for l in lines:
		var t := l.strip_edges()
		if t == "" or t.begins_with("#"):
			continue
		run(t.trim_prefix("$"), c)
		n += 1
	return n


func _function_tag(tag: String) -> Array:
	var ns := tag.get_slice(":", 0) if tag.contains(":") else "minecraft"
	var path := tag.get_slice(":", 1) if tag.contains(":") else tag
	var out: Array = []
	var root := _pack_root()
	if not DirAccess.dir_exists_absolute(root):
		return out
	for pack in DirAccess.get_directories_at(root):
		for sub in ["tags/function", "tags/functions"]:
			var f := root.path_join(pack).path_join("data").path_join(ns).path_join(sub).path_join(path + ".json")
			if FileAccess.file_exists(f):
				var j = JSON.parse_string(FileAccess.get_file_as_string(f))
				if j is Dictionary:
					for v in j.get("values", []):
						out.append(str(v if v is String else (v as Dictionary).get("id", "")))
	return out


func _load_tags() -> void:
	_fn_loaded = true
	_tick_fns = _function_tag("minecraft:tick")
	var srv := Ctx.new()
	srv.pos = Vector3(world.level.get("spawn", [0, 64, 0])[0], world.level.get("spawn", [0, 64, 0])[1], world.level.get("spawn", [0, 64, 0])[2])
	for f in _function_tag("minecraft:load"):
		run_function(f, srv)


## Per game tick: #minecraft:tick functions (loads #minecraft:load once).
func tick() -> void:
	if not _fn_loaded:
		_load_tags()
	if _tick_fns.is_empty():
		return
	var srv := Ctx.new()
	var sp: Array = world.level.get("spawn", [0, 64, 0])
	srv.pos = Vector3(sp[0], sp[1], sp[2])
	srv.silent = true
	for f in _tick_fns:
		run_function(f, srv)


## Java PlaceCommand: /place feature <configured feature> [pos], /place template <template> [pos] [rotation]. Runs the
## generator's feature code on a private copy of the 3 x 3 loaded chunks around the position and applies its writes.
func _place(a: Array, ctx: Ctx) -> int:
	if a.size() < 2 or not (a[0] in ["feature", "template", "structure"]):
		_say(ctx, "Usage: /place feature <feature> [pos] | /place structure <structure> [pos] | /place template <template> [pos] [rotation]")
		return 0
	var fe = world.gen.get("features") if world.gen != null else null
	if fe == null:
		_say(ctx, "This world type has no data-driven features")
		return 0
	var bp := Vector3i(_coords(a.slice(2, 5), ctx).floor()) if a.size() >= 5 else Vector3i(ctx.pos.floor())
	var ccx := bp.x >> 4
	var ccz := bp.z >> 4
	var nine: Array = []
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			nine.append(world.cm.get_chunk(ccx + dx, ccz + dz))
	if nine[4] == null:
		_say(ctx, "That position is not loaded")
		return 0
	var region := ChunkRegion.new(ccx, ccz, nine)
	var c := Features.FCtx.new()
	c.region = region
	fe._load_region(c, nine[4], region)
	c.origin_chunk = nine[4]
	c.r = RandomSources.Xoroshiro.from_seed(randi())
	var id := str(a[1]).trim_prefix("minecraft:")
	var ok := false
	if a[0] == "structure":
		# Java PlaceCommand.placeStructure: the start generated at this chunk without the biome test, its pieces placed
		# here (this 3 x 3 chunk area)
		var sts = world.gen.get("structures")
		var cfg: Dictionary = sts.structures.get(id, {}) if sts != null else {}
		if cfg.is_empty():
			_say(ctx, "There is no structure with type \"%s\"" % id)
			return 0
		var t := str(cfg.get("type", "")).trim_prefix("minecraft:")
		var sc := Vector2i(ccx, ccz)
		var r := Structures.large_feature_seed(world.gen.seed, sc.x, sc.y)
		var res: Dictionary = {}
		if t == "jigsaw":
			var stub: Dictionary = sts._jigsaw_stub(cfg, sc, r)
			if not stub.is_empty():
				res = sts._jigsaw_finish(cfg, stub, r)
		elif t == "woodland_mansion":
			res = MansionPieces.generate(sts, cfg, sc, r, true)
		else:
			res = StructuresLegacy.generate(sts, t, cfg, sc, r)
		if res.is_empty():
			_say(ctx, "Failed to generate structure \"%s\"" % id)
			return 0
		print("[place] structure %s centre %s box %s" % [id, str(res.get("center")), str(res.get("box"))])
		# Java: StructureStart.placeInChunk for every chunk of the start's bounding box (loaded chunks)
		var sbox: Array = res.get("box", [bp, bp])
		for scz in range(sbox[0].z >> 4, (sbox[1].z >> 4) + 1):
			for scx in range(sbox[0].x >> 4, (sbox[1].x >> 4) + 1):
				var nine2: Array = []
				for dz2 in [-1, 0, 1]:
					for dx2 in [-1, 0, 1]:
						nine2.append(world.cm.get_chunk(scx + dx2, scz + dz2))
				if nine2[4] == null:
					continue
				var c2 := c if (scx == ccx and scz == ccz) else Features.FCtx.new()
				if c2 != c:
					var region2 := ChunkRegion.new(scx, scz, nine2)
					c2.region = region2
					fe._load_region(c2, nine2[4], region2)
					c2.origin_chunk = nine2[4]
					c2.r = RandomSources.Xoroshiro.from_seed(randi())
				sts._place_start(c2, res, Vector3i(scx * 16, world.gen.gen_min_y, scz * 16), Vector3i(scx * 16 + 15, world.gen.gen_min_y + world.gen.gen_depth - 1, scz * 16 + 15))
				if c2 != c:
					_apply_place_writes(c2)
		ok = true
	elif a[0] == "feature":
		var cf: Dictionary = fe._cf("minecraft:" + id)
		if cf.is_empty():
			_say(ctx, "There is no configured feature with type \"%s\"" % id)
			return 0
		ok = fe.place_feature(c, cf, bp)
	else:
		var tpl := StructureTemplate.get_template(id)
		if tpl == null:
			_say(ctx, "Template \"%s\" not found" % id)
			return 0
		var rot := {"none": 0, "clockwise_90": 1, "180": 2, "counterclockwise_90": 3}.get(str(a[5]) if a.size() > 5 else "none", 0)
		tpl.place(fe, c, bp, rot, [], false, false, Vector3i(ccx * 16 - 16, Coords.MIN_Y, ccz * 16 - 16), Vector3i(ccx * 16 + 31, Coords.MAX_Y - 1, ccz * 16 + 31))
		ok = true
	if not ok:
		_say(ctx, "Failed to place feature")
		return 0
	_apply_place_writes(c)
	if a[0] == "structure":
		_say(ctx, "Generated structure \"%s\" at %d, %d, %d" % [id, bp.x, bp.y, bp.z])
		return 1
	_say(ctx, "Placed feature \"%s\" at %d, %d, %d" % [id, bp.x, bp.y, bp.z] if a[0] == "feature" else "Structure template %s placed at %d, %d, %d" % [id, bp.x, bp.y, bp.z])
	return 1


## /place: a feature context's block writes (with their placement modes), block entities and structure mobs applied
## to the world.
func _apply_place_writes(c: Features.FCtx) -> void:
	var w: PackedInt32Array = c.writes
	for k in range(0, w.size(), 5):
		var st := w[k + 3]
		var mode := w[k + 4]
		if mode != Features.W_FORCE:
			var cur: int = world.state_at(w[k], w[k + 1], w[k + 2])
			var fl: int = Res.blocks.st_flags[cur] if cur > 0 else 0
			if mode == Features.W_AIR and cur != 0 and (fl & BlockRegistry.F_REPLACEABLE) == 0:
				continue
			if mode == Features.W_REPLACEABLE and cur != 0 and (fl & (BlockRegistry.F_REPLACEABLE | BlockRegistry.F_LEAVES)) == 0:
				continue
		world.set_block(w[k], w[k + 1], w[k + 2], st, false)
	for bpos in c.block_entities:
		BlockEntities.set_data(world, bpos, (c.block_entities[bpos] as Dictionary).duplicate(true))
	for en in c.entities:
		var ep: Array = en.get("p", [])
		if str(en.get("k", "")) == "mob" and ep.size() == 3:
			var m = world.entities.spawn_mob(str(en["id"]), Vector3(ep[0], ep[1], ep[2]))
			if m != null and en.get("pers", false):
				m.persistent = true
