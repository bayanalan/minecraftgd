## Interaction — mining speed/tool rules, block placement with state orientation, block use (doors,
## trapdoors, levers, buttons, containers, crafting table, furnace, beds...), item use (food, buckets,
## bone meal, flint and steel, hoes/shovels/axes transforms, spawn eggs) and Adventure checks.
## Contract: static functions called by WorldManager on the main thread.
class_name Interaction


static func correct_tool(tool: ItemStack, st: int) -> bool:
	var blocks := Res.blocks
	var name := blocks.name_of(st)
	var kind := "" if tool == null or tool.is_empty() else Res.items.tool_kind[tool.item]
	var tier := 0 if tool == null or tool.is_empty() else Res.items.tool_tier[tool.item]
	var mine_tag := ""
	if Res.mode == "vanilla":
		for k in ["pickaxe", "axe", "shovel", "hoe"]:
			if Tags.has_block("mineable/" + k, name):
				mine_tag = k
				break
	else:
		mine_tag = str(blocks.block_info[blocks.st_block[st]]["tool"])
	if name == "cobweb":
		return kind == "sword" or kind == "shears"
	if mine_tag == "" or kind != mine_tag:
		return false
	var need := 0
	if Res.mode == "vanilla":
		if Tags.has_block("needs_diamond_tool", name):
			need = 4
		elif Tags.has_block("needs_iron_tool", name):
			need = 3
		elif Tags.has_block("needs_stone_tool", name):
			need = 2
	return tier >= need


static func destroy_progress(p: Player, st: int, world) -> float:
	var blocks := Res.blocks
	var h := blocks.hardness[blocks.st_block[st]]
	if h < 0.0:
		return 0.0
	if h == 0.0:
		return 1.0
	var tool := p.inventory.held()
	var speed := 1.0
	var correct := correct_tool(tool, st)
	var kind := "" if tool.is_empty() else Res.items.tool_kind[tool.item]
	if not tool.is_empty() and kind != "":
		var name := blocks.name_of(st)
		var mine_tag := ""
		for k in ["pickaxe", "axe", "shovel", "hoe"]:
			if (Res.mode == "vanilla" and Tags.has_block("mineable/" + k, name)) or (Res.mode != "vanilla" and blocks.block_info[blocks.st_block[st]]["tool"] == k):
				mine_tag = k
		var vanilla := Res.mode == "vanilla"
		if kind == mine_tag:
			speed = Res.items.tool_speed[tool.item]
		elif kind == "sword":
			# Java sword tool component: cobweb 15, #sword_instantly_mines (bamboo) instant, #sword_efficient 1.5
			if name == "cobweb":
				speed = 15.0
			elif vanilla and Tags.has_block("sword_instantly_mines", name):
				speed = 1.0e9
			elif (vanilla and Tags.has_block("sword_efficient", name)) or (not vanilla and name.ends_with("_leaves")):
				speed = 1.5
		elif kind == "shears":
			# Java shears tool component: cobweb / #leaves 15, #wool 5, vine / glow lichen 2
			if name == "cobweb" or (Tags.has_block("leaves", name) if vanilla else name.ends_with("_leaves")):
				speed = 15.0
			elif (Tags.has_block("wool", name) if vanilla else name.ends_with("_wool")):
				speed = 5.0
			elif name == "vine" or name == "glow_lichen":
				speed = 2.0
		# Java Player.getDestroySpeed: the mining_efficiency attribute (Efficiency: level^2 + 1) only for a tool that is
		# faster than the hand on this block
		if speed > 1.0:
			var eff := Loot._ench(tool, "efficiency")
			if eff > 0:
				speed += eff * eff + 1
	var haste := maxi(p._effect_amp("haste"), p._effect_amp("conduit_power"))
	if haste > 0:
		speed *= 1.0 + 0.2 * haste
	var fatigue := p._effect_amp("mining_fatigue")
	if fatigue > 0:
		speed *= [0.3, 0.09, 0.0027, 0.00081][mini(fatigue - 1, 3)]
	# submerged_mining_speed 0.2 (an Aqua Affinity helmet: 1.0)
	if p.eyes_in_water and Loot._ench(p.inventory.get_slot(Inventory.ARMOR0 + 3), "aqua_affinity") <= 0:
		speed /= 5.0
	if not p.on_ground and not p.flying:
		speed /= 5.0
	var harvest := correct or not bool(blocks.block_info[blocks.st_block[st]]["requires_tool"])
	return speed / h / (30.0 if harvest else 100.0)


static func damage_tool(p: Player, amount: int) -> void:
	if p.is_creative():
		return
	var t := p.inventory.held()
	if t.is_empty():
		return
	var md: int = Res.items.max_damage[t.item]
	if md <= 0:
		return
	var unb := Loot._ench(t, "unbreaking")
	if unb > 0 and randf() > 1.0 / (unb + 1):
		return
	t.damage += amount
	if t.damage >= md:
		UseItem.spawn_item_particles(p, t.item, 5)   # Java LivingEntity.breakItem
		t.clear()
		Audio.play("entity.item.break", p.pos, "Players")
	p.inventory.changed.emit()


static func adventure_can_break(tool: ItemStack, st: int) -> bool:
	if tool.is_empty():
		return false
	var cb = tool.components.get("minecraft:can_break")
	if not (cb is Dictionary):
		return false
	var blocks_pred = cb.get("blocks", [])
	var name := "minecraft:" + Res.blocks.name_of(st)
	if blocks_pred is String:
		return blocks_pred == name or (blocks_pred.begins_with("#") and Tags.has_block(blocks_pred, Res.blocks.name_of(st)))
	if blocks_pred is Array:
		return blocks_pred.has(name)
	return false


static func adventure_can_place(tool: ItemStack, against: int) -> bool:
	var cp = tool.components.get("minecraft:can_place_on")
	if not (cp is Dictionary):
		return false
	var bp = cp.get("blocks", [])
	var name := "minecraft:" + Res.blocks.name_of(against)
	return bp == name or (bp is Array and bp.has(name))


const CW := {"north": "east", "east": "south", "south": "west", "west": "north"}
const CCW := {"north": "west", "west": "south", "south": "east", "east": "north"}
const DIR_OFF := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0)}


static func is_pair_chest(name: String) -> bool:
	return name == "chest" or name == "trapped_chest" or name.ends_with("copper_chest")


## Java ChestBlock.getConnectedDirection: the other half of a double chest, or y = -9999.
static func chest_partner(st: int, pos: Vector3i) -> Vector3i:
	var b := Res.blocks
	if st <= 0 or not b.has_prop(st, "type") or not b.has_prop(st, "facing"):
		return Vector3i(0, -9999, 0)
	var t := b.get_prop(st, "type")
	if t == "single":
		return Vector3i(0, -9999, 0)
	var f := b.get_prop(st, "facing")
	return pos + DIR_OFF[CW.get(f, "north") if t == "left" else CCW.get(f, "north")]


## Java ChestBlock.updateShape: when one half goes away the other becomes single.
static func chest_unlink(world, pos: Vector3i, old: int, new_st: int) -> void:
	var b := Res.blocks
	if old <= 0 or not is_pair_chest(b.name_of(old)) or (new_st > 0 and b.st_block[new_st] == b.st_block[old]):
		return
	var q := chest_partner(old, pos)
	if q.y == -9999:
		return
	var ns: int = world.state_at(q.x, q.y, q.z)
	if ns > 0 and b.st_block[ns] == b.st_block[old] and b.get_prop(ns, "type") != "single":
		world.set_block(q.x, q.y, q.z, b.with_prop(ns, "type", "single"), false)


static func horizontal_facing(yaw: float) -> String:
	var i := int(floor(fposmod(yaw, 360.0) / 90.0 + 0.5)) & 3
	return ["south", "west", "north", "east"][i]


static func opposite(f: String) -> String:
	return {"north": "south", "south": "north", "east": "west", "west": "east", "up": "down", "down": "up"}.get(f, f)


static func face_name(n: Vector3i) -> String:
	if n.y > 0: return "up"
	if n.y < 0: return "down"
	if n.z < 0: return "north"
	if n.z > 0: return "south"
	if n.x < 0: return "west"
	return "east"


## Computes the placed state for a block item given the click context.
static func placement_state(base: int, hit: Dictionary, p: Player) -> int:
	var blocks := Res.blocks
	var st := base
	var name := blocks.name_of(base)
	var n: Vector3i = hit["normal"]
	var point: Vector3 = hit["point"]
	var fy: float = point.y - floorf(point.y)
	if n.y != 0:
		fy = 0.0 if n.y > 0 else 1.0
	var face := face_name(n)
	var look := horizontal_facing(p.yaw)
	if blocks.has_prop(st, "axis"):
		st = blocks.with_prop(st, "axis", "y" if n.y != 0 else ("x" if n.x != 0 else "z"))
	if blocks.has_prop(st, "facing"):
		var vals := ""
		for pr in blocks.block_props[blocks.st_block[st]]:
			if pr[0] == "facing":
				vals = ",".join(pr[1])
		var six := vals.contains("up")
		if name.ends_with("_stairs") or name.ends_with("_door") or name.ends_with("_fence_gate") or name.contains("bed") or name == "lectern" or name.contains("repeater") or name.contains("comparator") or name.ends_with("anvil"):
			st = blocks.with_prop(st, "facing", look)
		elif name.ends_with("_trapdoor"):
			st = blocks.with_prop(st, "facing", opposite(look) if n.y != 0 else face)
		elif name == "piston" or name == "sticky_piston" or name == "dispenser" or name == "dropper" or name == "observer":
			# Java getNearestLookingDirection().getOpposite(): looking down (pitch > 45) faces up, towards the player;
			# observers take the looking direction itself (their face looks away)
			var pitch_dir := "up" if p.pitch > 45 else ("down" if p.pitch < -45 else opposite(look))
			if name == "observer":
				pitch_dir = opposite(pitch_dir) if pitch_dir in ["up", "down"] else look
			st = blocks.with_prop(st, "facing", pitch_dir)
		elif name.contains("wall_") or name.ends_with("_wall_torch") or name.ends_with("ladder") or name.ends_with("_button") or name == "lever" or name == "tripwire_hook":
			st = blocks.with_prop(st, "facing", face if n.y == 0 else opposite(look))
		elif six:
			st = blocks.with_prop(st, "facing", face)
		else:
			st = blocks.with_prop(st, "facing", opposite(look))
	if name == "crafter":
		# Java CrafterBlock.getStateForPlacement: front = nearest looking direction reversed; top = up, or for a vertical
		# front the horizontal facing (front up) / its opposite (front down); triggered when placed powered
		var front := "up" if p.pitch > 45 else ("down" if p.pitch < -45 else opposite(look))
		var topd := "up"
		if front == "down":
			topd = opposite(look)
		elif front == "up":
			topd = look
		st = blocks.with_prop(st, "orientation", front + "_" + topd)
	if blocks.has_prop(st, "half"):
		var top: bool = (n.y < 0) or (n.y == 0 and fy > 0.5)
		var hv := blocks.get_prop(st, "half")
		if hv == "bottom" or hv == "top":
			st = blocks.with_prop(st, "half", "top" if top else "bottom")
	if blocks.has_prop(st, "type") and name.ends_with("_slab"):
		var top2: bool = (n.y < 0) or (n.y == 0 and fy > 0.5)
		st = blocks.with_prop(st, "type", "top" if top2 else "bottom")
	if blocks.has_prop(st, "face") and (name.ends_with("_button") or name == "lever"):
		st = blocks.with_prop(st, "face", "floor" if n.y > 0 else ("ceiling" if n.y < 0 else "wall"))
	if blocks.has_prop(st, "rotation"):
		# Java: signs/banners face the player (yaw + 180); SkullBlock uses the raw yaw
		var skull := name.ends_with("_skull") or name.ends_with("_head")
		st = blocks.with_prop(st, "rotation", str(int(floor(fposmod(p.yaw + (0.0 if skull else 180.0), 360.0) * 16.0 / 360.0 + 0.5)) & 15))
	if blocks.has_prop(st, "hinge"):
		st = blocks.with_prop(st, "hinge", "left")
	return st


## Java LanternBlock.getStateForPlacement: of the nearest looking directions (BlockPlaceContext: the clicked face's
## opposite first, then Direction.orderedByNearest - UP before DOWN while looking up) the vertical ones in order, the
## first whose attachment survives (canSurvive: Block.canSupportCenter of the block above for hanging=true, below for a
## standing lantern). Clicking a block's underside hangs the lantern from it. -1 when neither survives (not placed).
static func lantern_placement(world, dest: Vector3i, st: int, n: Vector3i, p: Player) -> int:
	var b := Res.blocks
	var dirs: Array = [1, -1] if p.pitch < 0.0 else [-1, 1]   # Java: xRot < 0 (looking up) -> UP nearest
	if n.y != 0:
		dirs = [-n.y, n.y]
	for dy in dirs:
		var q: Vector3i = dest + Vector3i(0, dy, 0)
		if can_support_center(world.state_at(q.x, q.y, q.z), dy > 0):
			return b.with_prop(st, "hanging", "true" if dy > 0 else "false")
	return -1


## Java Block.canSupportCenter(level, pos, face): the block's support (collision) shape covers the 2 x 2 px centre
## (Block.box(7, 0, 7, 9, 10, 9)) on that face - full blocks, slabs, fences, walls, chains, ... Fence gates
## (#unstable_bottom_center) never hold anything under them. bottom_face: the block's DOWN face (something hangs below).
static func can_support_center(st: int, bottom_face: bool) -> bool:
	var b := Res.blocks
	if st <= 0 or (b.st_flags[st] & BlockRegistry.F_COLLIDE) == 0:
		return false
	if bottom_face and Tags.has_block("unstable_bottom_center", b.name_of(st)):
		return false
	var sh := b.get_shape(st)
	for i in range(0, sh.size(), 6):
		var on_face: bool = sh[i + 1] <= 0.001 if bottom_face else sh[i + 4] >= 0.999
		if on_face and sh[i] <= 7.001 / 16.0 and sh[i + 2] <= 7.001 / 16.0 and sh[i + 3] >= 8.999 / 16.0 and sh[i + 5] >= 8.999 / 16.0:
			return true
	return false


## Wall variants: torch -> wall_torch etc. when clicking a side face.
static func wall_variant(item_name: String, n: Vector3i) -> String:
	if n.y != 0:
		return ""
	var cands := {"torch": "wall_torch", "soul_torch": "soul_wall_torch", "redstone_torch": "redstone_wall_torch", "copper_torch": "copper_wall_torch"}
	if cands.has(item_name):
		return cands[item_name]
	if item_name.ends_with("_sign") and not item_name.ends_with("hanging_sign"):
		return item_name.trim_suffix("_sign") + "_wall_sign"
	if item_name.ends_with("_banner"):
		return item_name.trim_suffix("_banner") + "_wall_banner"
	if item_name.ends_with("_head") or item_name.ends_with("_skull"):
		return item_name.replace("_head", "_wall_head").replace("_skull", "_wall_skull")
	if item_name.ends_with("_coral_fan"):
		return item_name.trim_suffix("_coral_fan") + "_coral_wall_fan"
	return ""


## BlockBehaviour.canBeReplaced for placing `place`: #replaceable blocks, except SnowLayerBlock - only a single layer
## (wiki Snow: "two layers and thicker does not get replaced"), never by snow itself.
static func snow_replaceable(st: int, place: int) -> bool:
	var b := Res.blocks
	if st <= 0:
		return st == 0
	if (b.st_flags[st] & BlockRegistry.F_REPLACEABLE) == 0:
		return false
	if b.has_prop(st, "layers") and b.name_of(st) == "snow":
		return b.get_prop(st, "layers") == "1" and (place <= 0 or b.st_block[place] != b.st_block[st])
	return true


static func use_item_on(world, held: ItemStack, hit: Dictionary) -> bool:
	if held.name() == "firework_rocket":
		# Java FireworkRocketItem.useOn: launch from the clicked face
		var fp: Vector3 = Vector3(hit["point"]) + Vector3(hit["normal"]) * 0.15
		world.entities.spawn_projectile("firework_rocket", fp, Vector3(randfn(0, 0.001), 0.05, randfn(0, 0.001)), world.player)
		var fe = world.entities.ents[world.entities.ents.size() - 1]
		fe.stack = held.copy()
		var fw = held.components.get("minecraft:fireworks", {})
		fe.data["life"] = 10 * (int((fw as Dictionary).get("flight_duration", 1)) + 1 if fw is Dictionary else 2) + randi_range(0, 5) + randi_range(0, 6)
		Audio.play("entity.firework_rocket.launch", fp, "Ambient")
		if not world.player.is_creative():
			world.player.inventory.consume_held()
		world.inv_changed()
		return true
	if held.name() == "filled_map" and Res.blocks.name_of(int(hit["state"])).ends_with("_banner"):
		# Java MapItem.useOn a banner: toggle its map marker
		Maps.toggle_banner(world, held, hit["pos"])
		return true
	var blocks := Res.blocks
	var p: Player = world.player
	var pos: Vector3i = hit["pos"]
	var n: Vector3i = hit["normal"]
	var target_st: int = hit["state"]
	var iname := held.name()
	if Vehicles.is_boat_item(iname) or Vehicles.is_cart_item(iname):
		return Vehicles.use_item(world, held, hit)
	# tool transforms
	var tname := blocks.name_of(target_st)
	if (iname == "flint_and_steel" or iname == "fire_charge") and tname == "tnt":
		world.set_block(pos.x, pos.y, pos.z, 0)
		MiscEntities.spawn_tnt(world.entities, Vector3(pos) + Vector3(0.5, 0.0, 0.5), 80)
		if iname == "flint_and_steel":
			damage_tool(p, 1)
		elif not p.is_creative():
			p.inventory.consume_held()
		return true
	if MiscEntities.is_placeable(iname):
		return MiscEntities.use_item(world, held, hit)
	if iname == "fishing_rod":
		return false
	if iname.ends_with("_hoe") and n.y >= 0 and tname in ["grass_block", "dirt", "dirt_path", "coarse_dirt", "rooted_dirt"] and world.state_at(pos.x, pos.y + 1, pos.z) == 0:
		var fl := blocks.default_state("farmland") if tname != "coarse_dirt" else blocks.default_state("dirt")
		world.set_block(pos.x, pos.y, pos.z, fl)
		Audio.play("item.hoe.till", Vector3(pos), "Blocks")
		damage_tool(p, 1)
		return true
	if iname.ends_with("_shovel") and tname in ["grass_block", "dirt", "coarse_dirt", "mycelium", "podzol", "rooted_dirt"] and n.y >= 0 and world.state_at(pos.x, pos.y + 1, pos.z) == 0:
		world.set_block(pos.x, pos.y, pos.z, blocks.default_state("dirt_path"))
		Audio.play("item.shovel.flatten", Vector3(pos), "Blocks")
		damage_tool(p, 1)
		return true
	if (iname.ends_with("_axe") or iname == "honeycomb") and Copper.use_item(world, pos, target_st, held, p):
		return true
	if iname.ends_with("_axe") and tname == "copper_golem_statue" and CopperGolem.reanimate(world, pos, target_st):
		damage_tool(p, 1)
		return true
	if iname.ends_with("_axe") and (tname.ends_with("_log") or tname.ends_with("_wood") or tname.ends_with("_stem") or tname.ends_with("_hyphae")) and not tname.begins_with("stripped_"):
		var stripped := blocks.state_of("stripped_" + tname, {"axis": blocks.get_prop(target_st, "axis")})
		if stripped >= 0:
			world.set_block(pos.x, pos.y, pos.z, stripped)
			Audio.play("item.axe.strip", Vector3(pos), "Blocks")
			damage_tool(p, 1)
			return true
	if iname == "flint_and_steel" or iname == "fire_charge":
		var fp: Vector3i = pos + n
		if world.state_at(fp.x, fp.y, fp.z) == 0:
			# fire inside an obsidian frame opens a nether portal (Java BaseFireBlock.onPlace -> PortalShape)
			if not Portals.try_light(world, fp):
				world.set_block(fp.x, fp.y, fp.z, BlockUpdates.fire_state(world, fp))
			Audio.play("item.flintandsteel.use" if iname == "flint_and_steel" else "item.firecharge.use", Vector3(fp), "Blocks")
			if iname == "flint_and_steel":
				damage_tool(p, 1)
			elif not p.is_creative():
				p.inventory.consume_held()
			return true
	if iname == "ender_eye" and tname == "end_portal_frame" and blocks.get_prop(target_st, "eye") == "false":
		world.set_block(pos.x, pos.y, pos.z, blocks.with_prop(target_st, "eye", "true"))
		Audio.play("block.end_portal_frame.fill", Vector3(pos), "Blocks")
		if not p.is_creative():
			p.inventory.consume_held()
		Portals.try_open_end_portal(world, pos)
		return true
	if iname == "bone_meal":
		if BlockUpdates.bonemeal(world, pos, target_st):
			if not p.is_creative():
				p.inventory.consume_held()
			return true
	if iname == "bucket" or iname == "water_bucket" or iname == "lava_bucket" or MobBuckets.is_bucket(iname):
		return false   # Java BucketItem has no useOn: buckets act through BucketItem.use (use_item, its own raycast)
	if iname == "end_crystal":
		# Java EndCrystalItem.useOn: on obsidian / bedrock with an empty block above and no entity in the 1 x 2 x 1 box
		# there; no base plate; in the End it may start the dragon respawn
		if tname != "obsidian" and tname != "bedrock":
			return false
		var ab := pos + Vector3i(0, 1, 0)
		if world.state_at(ab.x, ab.y, ab.z) != 0:
			return false
		for oe in world.entities.ents:
			if oe.dead:
				continue
			if oe.pos.x + oe.w / 2.0 > ab.x and oe.pos.x - oe.w / 2.0 < ab.x + 1 and oe.pos.z + oe.w / 2.0 > ab.z and oe.pos.z - oe.w / 2.0 < ab.z + 1 and oe.pos.y + oe.h > ab.y and oe.pos.y < ab.y + 2:
				return false
		var ce = world.entities.spawn_mob("end_crystal", Vector3(ab) + Vector3(0.5, 0, 0.5))
		if ce != null:
			ce.data["ShowBottom"] = false
			ce.persistent = true
		if not p.is_creative():
			p.inventory.consume_held()
		if world.dimension == "the_end" and world.dragon_fight != null:
			world.dragon_fight.try_respawn()
		return true
	if (iname.ends_with("_spawn_egg")) and (tname == "spawner" or tname == "trial_spawner"):
		# wiki Spawn Egg / Monster Spawner / Trial Spawner: an egg used on a spawner sets the mob it spawns (and shows);
		# spawn eggs are used up in Survival like any other use
		Trials.set_spawner_mob(world, pos, tname, iname.trim_suffix("_spawn_egg"))
		if not p.is_creative():
			p.inventory.consume_held()
		return true
	if iname.begins_with("spawn_egg") or iname.ends_with("_spawn_egg"):
		var mob := iname.trim_suffix("_spawn_egg")
		world.entities.spawn_mob(mob, Vector3(pos + n) + Vector3(0.5, 0, 0.5))
		if not p.is_creative():
			p.inventory.consume_held()
		return true
	# block placement
	var place: int = Res.items.place_block[held.item]
	if place < 0:
		return false
	if p.mode == Player.Mode.ADVENTURE and not adventure_can_place(held, target_st):
		return false
	# Java PinkPetalsBlock / LeafLitterBlock (SegmentableBlock.canBeReplaced): the same item adds a flower / segment
	# to the clicked block, up to 4
	if blocks.st_block[target_st] == blocks.st_block[place]:
		for ap in ["flower_amount", "segment_amount"]:
			if blocks.has_prop(target_st, ap) and int(blocks.get_prop(target_st, ap)) < 4:
				world.set_block(pos.x, pos.y, pos.z, blocks.with_prop(target_st, ap, str(int(blocks.get_prop(target_st, ap)) + 1)))
				_after_place(world, p, target_st, pos)
				return true
	# Java SnowLayerBlock.canBeReplaced / getStateForPlacement (wiki Snow: 1 - 8 layers): a snow item used on a snow
	# layer's top face, or on a face in front of a snow layer, adds a layer to it (8 layers: no more)
	if blocks.st_block[place] == blocks.block_id("snow") and blocks.has_prop(place, "layers"):
		var sp0: Vector3i = pos if (blocks.st_block[target_st] == blocks.st_block[place] and n.y > 0) else pos + n
		var ss0: int = world.state_at(sp0.x, sp0.y, sp0.z)
		if ss0 > 0 and blocks.st_block[ss0] == blocks.st_block[place] and int(blocks.get_prop(ss0, "layers")) < 8:
			var sl := blocks.with_prop(ss0, "layers", str(int(blocks.get_prop(ss0, "layers")) + 1))
			if blocks.st_flags[sl] & BlockRegistry.F_COLLIDE:
				# Level.isUnobstructed: the taller layer must not reach into the player or a mob
				var ssh := blocks.get_shape(sl)
				for sb in range(0, ssh.size(), 6):
					var smin := Vector3(sp0) + Vector3(ssh[sb], ssh[sb + 1], ssh[sb + 2])
					var smax := Vector3(sp0) + Vector3(ssh[sb + 3], ssh[sb + 4], ssh[sb + 5])
					var spm := p.aabb_min()
					var spx := p.aabb_max()
					if (not p.is_spectator() and spm.x < smax.x and spx.x > smin.x and spm.y < smax.y and spx.y > smin.y and spm.z < smax.z and spx.z > smin.z) or _entity_obstructs(world, smin, smax):
						return false
			world.set_block(sp0.x, sp0.y, sp0.z, sl)
			_after_place(world, p, sl, sp0)
			return true
	var dest := pos
	if not snow_replaceable(target_st, place) or blocks.name_of(target_st) == blocks.name_of(place):
		dest = pos + n
		# slab merging
		if blocks.name_of(target_st).ends_with("_slab") and blocks.name_of(target_st) == blocks.name_of(place) and blocks.get_prop(target_st, "type") != "double":
			var t := blocks.get_prop(target_st, "type")
			if (t == "bottom" and n.y > 0) or (t == "top" and n.y < 0):
				world.set_block(pos.x, pos.y, pos.z, blocks.with_prop(blocks.with_prop(target_st, "type", "double"), "waterlogged", "false"))   # (SlabBlock: a double slab holds no water)
				_after_place(world, p, place, pos)
				return true
	var cur: int = world.state_at(dest.x, dest.y, dest.z)
	if cur < 0 or not snow_replaceable(cur, place):
		if cur >= 0 and blocks.name_of(cur).ends_with("_slab") and blocks.name_of(cur) == blocks.name_of(place) and blocks.get_prop(cur, "type") != "double":
			world.set_block(dest.x, dest.y, dest.z, blocks.with_prop(blocks.with_prop(cur, "type", "double"), "waterlogged", "false"))
			_after_place(world, p, place, dest)
			return true
		return false
	if dest.y < Coords.MIN_Y or dest.y >= Coords.MAX_Y:
		return false
	var wv := wall_variant(iname, n)
	var st := place
	if wv != "" and blocks.block_id(wv) >= 0:
		st = blocks.default_state(wv)
	elif n.y == 0 and iname.ends_with("torch") and wv == "":
		pass
	st = placement_state(st, hit, p)
	# support checks for plants/torches
	var bname := blocks.name_of(st)
	if blocks.has_prop(st, "hanging") and (bname == "lantern" or bname == "soul_lantern" or bname.ends_with("copper_lantern")):
		st = lantern_placement(world, dest, st, n, p)
		if st < 0:
			return false
	# Java getStateForPlacement + canPlace for every block with a support rule (Support.placement): torches / signs /
	# banners / coral fans try the wall and the standing form along the nearest looking directions, buttons / levers
	# every face, ladders / tripwire hooks / cocoa the horizontal ones, vines / lichen the first holding face; doors and
	# tall plants need a replaceable block above, beds at the head; plants their 26.3 #supports_* soil, crops light 8
	if Support.kind_of(st) != Support.K_NONE:
		st = Support.placement(world, st, dest, n, p, dest == pos)
		if st < 0:
			return false
		bname = blocks.name_of(st)
	st = Redstone.placed_state(world, dest, st)   # (doors / trapdoors / fence gates placed with power come open)
	# getStateForPlacement: waterlogged = the fluid there is a water SOURCE (Fluids.WATER: a water source block, or
	# seagrass / bubble columns being replaced); flowing water leaves the block dry (wiki Waterlogging)
	if cur > 0 and can_place_water(st) and ((blocks.st_flags[cur] & (BlockRegistry.F_LIQUID | BlockRegistry.F_LAVA)) == BlockRegistry.F_LIQUID and blocks.st_level[cur] == 0 or (blocks.st_flags[cur] & BlockRegistry.F_WATERLOGGED) != 0):
		st = blocks.with_prop(st, "waterlogged", "true")
	# entity collision check
	if blocks.st_flags[st] & BlockRegistry.F_COLLIDE:
		var sh := blocks.get_shape(st)
		for b in range(0, sh.size(), 6):
			var bmin := Vector3(dest) + Vector3(sh[b], sh[b + 1], sh[b + 2])
			var bmax := Vector3(dest) + Vector3(sh[b + 3], sh[b + 4], sh[b + 5])
			var pm := p.aabb_min()
			var px := p.aabb_max()
			if not p.is_spectator() and pm.x < bmax.x and px.x > bmin.x and pm.y < bmax.y and px.y > bmin.y and pm.z < bmax.z and px.z > bmin.z:
				return false
			if _entity_obstructs(world, bmin, bmax):
				return false
	# Java ChestBlock.getStateForPlacement: join a single chest with the same facing to the left/right
	var pair_q := Vector3i(0, -9999, 0)
	var pair_st := 0
	if is_pair_chest(bname) and blocks.has_prop(st, "type") and not p.sneaking:
		var f0 := blocks.get_prop(st, "facing")
		for side in [["left", CW.get(f0, "north")], ["right", CCW.get(f0, "north")]]:
			var q: Vector3i = dest + DIR_OFF[side[1]]
			var ns: int = world.state_at(q.x, q.y, q.z)
			if ns > 0 and blocks.st_block[ns] == blocks.st_block[st] and blocks.get_prop(ns, "type") == "single" and blocks.get_prop(ns, "facing") == f0:
				st = blocks.with_prop(st, "type", side[0])
				pair_q = q
				pair_st = blocks.with_prop(ns, "type", "right" if side[0] == "left" else "left")
				break
	world.set_block(dest.x, dest.y, dest.z, st)
	if pair_q.y != -9999:
		world.set_block(pair_q.x, pair_q.y, pair_q.z, pair_st)
	# two-block structures
	if blocks.has_prop(st, "half") and blocks.get_prop(st, "half") == "lower" and bname != "pitcher_crop":
		# DoorBlock / DoublePlantBlock.setPlacedBy: the upper half replaces what is above (checked replaceable; a
		# planted pitcher pod is a single block until age 3 - PitcherCropBlock)
		var ua: int = world.state_at(dest.x, dest.y + 1, dest.z)
		if ua == 0 or (ua > 0 and (blocks.st_flags[ua] & BlockRegistry.F_REPLACEABLE) != 0):
			world.set_block(dest.x, dest.y + 1, dest.z, blocks.with_prop(st, "half", "upper"))
	if bname.ends_with("_bed") and blocks.has_prop(st, "part"):
		var f := blocks.get_prop(st, "facing")
		var off := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0)}.get(f, Vector3i.ZERO)
		var hp: Vector3i = dest + off
		var hs0: int = world.state_at(hp.x, hp.y, hp.z)
		if hs0 == 0 or (hs0 > 0 and (blocks.st_flags[hs0] & BlockRegistry.F_REPLACEABLE) != 0):
			world.set_block(hp.x, hp.y, hp.z, blocks.with_prop(st, "part", "head"))
	_after_place(world, p, st, dest)
	return true


## Java Level.isUnobstructed: entities with blocksBuilding (living mobs, falling blocks, primed TNT, boats, minecarts,
## armour stands) inside the new block's collision box stop the placement (items, XP, arrows and paintings do not).
static func _entity_obstructs(world, bmin: Vector3, bmax: Vector3) -> bool:
	if world.get("entities") == null or world.entities == null:
		return false
	for e in world.entities.ents:
		if e.dead or not (e.kind in ["mob", "falling", "tnt", "boat", "minecart", "armor_stand", "anvil"]):
			continue
		if e.kind == "mob" and e.death_time > 0:
			continue
		var hw: float = e.w * 0.5
		if e.pos.x - hw < bmax.x and e.pos.x + hw > bmin.x and e.pos.y < bmax.y and e.pos.y + e.h > bmin.y and e.pos.z - hw < bmax.z and e.pos.z + hw > bmin.z:
			return true
	return false


static func _after_place(world, p: Player, st: int, pos: Vector3i) -> void:
	var blocks := Res.blocks
	BlockProperties.play_block_sound(st, "place", Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	var placed_from := p.inventory.held().copy()
	if not p.is_creative():
		p.inventory.consume_held()
	if Growth.concrete_check(world, pos, st):   # wiki Concrete Powder: placed into / next to water
		st = world.state_at(pos.x, pos.y, pos.z)
	BlockUpdates.schedule_neighbors(world, pos)
	BlockEntities.on_placed(world, pos, st)
	BlockEntities.apply_item(world, pos, placed_from)
	Sculk.vibrate(world, Vector3(pos) + Vector3(0.5, 0.5, 0.5), true)
	if Signs.is_sign(blocks.name_of(st)):
		Signs.on_placed(world, pos)
	Tripwires.on_placed(world, pos, st)
	Summons.try(world, pos, st)


static func _replace_held(p: Player, name: String) -> void:
	var inv := p.inventory
	var h := inv.held()
	var ns := ItemStack.named(name, 1)
	if p.is_creative():
		if inv.count_item(ns.item) == 0:
			inv.add(ns)
		return
	if h.count == 1:
		inv.set_slot(inv.selected, ns)
	else:
		h.count -= 1
		if inv.add(ns) > 0:
			p.inventory.changed.emit()


## Items whose right-click (Interaction.use_item) does something; otherwise the offhand gets a turn.
## Equipment slot (Inventory.ARMOR0 + 0 feet .. 3 head) an item equips into with right-click, -1 none (Java equippable).
static func armor_slot_of(n: String) -> int:
	if n.ends_with("_boots"):
		return Inventory.ARMOR0
	if n.ends_with("_leggings"):
		return Inventory.ARMOR0 + 1
	if n.ends_with("_chestplate") or n == "elytra":
		return Inventory.ARMOR0 + 2
	if n.ends_with("_helmet"):
		return Inventory.ARMOR0 + 3
	return -1


## Java Equippable.swapWithEquipmentSlot: right-click puts the piece on, the worn one goes to the hand (Curse of
## Binding blocks it outside creative), equip sound, the hand swings.
static func equip_from_hand(world, held: ItemStack) -> bool:
	var p: Player = world.player
	var slot := armor_slot_of(held.name())
	if slot < 0:
		return false
	var worn := p.inventory.get_slot(slot)
	if not worn.is_empty() and Loot._ench(worn, "binding_curse") > 0 and not p.is_creative():
		return false
	var one := held.copy()
	one.count = 1
	p.inventory.set_slot(slot, one)
	if held.count > 1 and not p.is_creative():
		var rest := held.copy()
		rest.count -= 1
		p.inventory.set_slot(p.inventory.selected, rest)
		if not worn.is_empty():
			p.inventory.add(worn)
	elif not p.is_creative():
		p.inventory.set_slot(p.inventory.selected, worn)
	var n := held.name()
	var snd := "item.armor.equip_generic"
	for t in ["leather", "chain", "iron", "gold", "diamond", "netherite", "turtle", "elytra", "copper"]:
		if n.begins_with(t) or (t == "gold" and n.begins_with("golden")) or (t == "chain" and n.begins_with("chainmail")):
			snd = "item.armor.equip_%s" % t
			break
	Audio.play(snd, p.pos, "Players")
	world.inv_changed()
	return true


static func has_use(s: ItemStack) -> bool:
	if Bundles.is_bundle(s):
		return true
	if armor_slot_of(s.name()) >= 0:
		return true
	var n := s.name()
	return n in ["goat_horn", "firework_rocket", "name_tag", "wind_charge", "map", "writable_book", "written_book", "fishing_rod", "water_bucket", "lava_bucket", "bucket", "cod_bucket", "salmon_bucket", "tropical_fish_bucket", "pufferfish_bucket", "axolotl_bucket", "tadpole_bucket",
		"splash_potion", "experience_bottle", "lingering_potion", "glass_bottle", "ender_eye", "ender_pearl", "snowball", "egg", "blue_egg", "brown_egg"]


static func use_item(world, held: ItemStack) -> void:
	var p: Player = world.player
	var iname := held.name()
	if Bundles.is_bundle(held):
		Bundles.drop_all(world, held)
		return
	if armor_slot_of(iname) >= 0:
		equip_from_hand(world, held)
		return
	if iname == "firework_rocket":
		# Java FireworkRocketItem.use: boosts only while gliding (the rocket attaches to the player)
		if p.fall_flying:
			var fl := int((held.components.get("minecraft:fireworks", {}) as Dictionary).get("flight_duration", 1)) if held.components.get("minecraft:fireworks") is Dictionary else 1
			p.rocket_ticks = 10 * (fl + 1) + randi_range(0, 5) + randi_range(0, 6)
			# the rocket entity riding at the hand (sprite, sparks, launch sound, the end-of-life burst)
			world.entities.spawn_projectile("firework_rocket", p.pos, Vector3.ZERO, p)
			var rk = world.entities.ents.back() if not world.entities.ents.is_empty() else null
			if rk != null and rk.id == "firework_rocket":
				rk.data["attached"] = true
				rk.data["life"] = p.rocket_ticks
				rk.stack = held.copy()
			if not p.is_creative():
				p.inventory.consume_held()
			world.inv_changed()
		return
	if iname == "wind_charge":
		world.entities.spawn_projectile("wind_charge", p.eye_pos(), p.look_dir() * 1.5, p)
		Audio.play("entity.wind_charge.throw", p.pos, "Players")
		p.add_cooldown("wind_charge", 10)   # wiki Wind Charge: 0.5 s cooldown
		if not p.is_creative():
			p.inventory.consume_held()
		return
	if iname == "goat_horn":
		# wiki Goat Horn: plays its instrument (data/minecraft/instrument: range 256 -> volume range / 16, RECORDS) and
		# cools down for use_duration (7 s)
		var ins := str(held.components.get("minecraft:instrument", "minecraft:ponder_goat_horn")).trim_prefix("minecraft:")
		var idef = Res.read_json("data/minecraft/instrument/%s.json" % ins)
		if idef is Dictionary:
			Audio.play(str(idef.get("sound_event", "minecraft:item.goat_horn.sound.0")).trim_prefix("minecraft:"), p.pos, "Jukebox", float(idef.get("range", 256.0)) / 16.0, 1.0)
			p.add_cooldown("goat_horn", int(floor(float(idef.get("use_duration", 7.0)) * 20.0)))
		return
	if iname == "ominous_bottle":
		var amp := int(held.components.get("minecraft:ominous_bottle_amplifier", 0))
		p.add_effect("bad_omen", clampi(amp, 0, 4), 120000)
		Audio.play("item.ominous_bottle.dispose", p.pos, "Players")
		if not p.is_creative():
			p.inventory.consume_held()
		world.inv_changed()
		return
	if iname == "map":
		var fm := Maps.new_map(world, p.pos.x, p.pos.z)
		if held.count <= 1:
			p.inventory.set_slot(p.inventory.selected, fm)
		else:
			p.inventory.consume_held()
			if p.inventory.add(fm) > 0:
				world.entities.spawn_item(p.eye_pos(), fm)
		Audio.play("ui.cartography_table.take_result", p.pos, "Players", 0.6)
		world.inv_changed()
		return
	if iname == "writable_book" or iname == "written_book":
		var bs = load("res://scripts/ui/book_screen.gd").new()
		bs.world = world
		bs.stack = held
		world.open_screen(bs)
		return
	if iname == "fishing_rod":
		if world.entities.hook != null:
			var cost := MiscEntities.reel(world.entities, p)
			if cost > 0 and not p.is_creative():
				damage_tool(p, cost)
		else:
			MiscEntities.cast(world.entities, p)
		return
	if Res.items.food_nutrition[held.item] > 0:
		if p.eat(held.item):
			if world.advancements != null:
				world.advancements.trigger("consume_item", {"item": iname})
			Audio.play("entity.generic.eat", p.pos, "Players")
			if not p.is_creative():
				var rem := "bowl" if iname.ends_with("_stew") or iname == "beetroot_soup" else ("glass_bottle" if iname == "honey_bottle" else "")
				p.inventory.consume_held()
				if rem != "":
					p.inventory.add(ItemStack.named(rem))
		return
	if iname == "water_bucket" or iname == "lava_bucket" or MobBuckets.is_bucket(iname):
		# Java BucketItem.use (ClipContext.Fluid.NONE: the ray passes through fluids)
		var hit := VoxelRaycast.cast(p.eye_pos(), p.look_dir(), p.block_reach(), world.state_at, Res.blocks)
		if hit.is_empty():
			return
		var t: Vector3i = hit["pos"]
		var front: Vector3i = t + hit["normal"]
		var water := iname != "lava_bucket"
		# water goes into a clicked liquid container (any waterloggable block) itself - sneaking puts it beside the block
		# instead (MC-173730, fixed in 25w33a) - else into the block in front of the clicked face; emptyContents falls
		# back to that block when the first one can't take it
		var first: Vector3i = t if water and liquid_container(int(hit["state"])) and not p.sneaking else front
		if bucket_empty(world, first, water, front, MobBuckets.empty_sound(iname)):
			Sculk.vibrate(world, Vector3(first) + Vector3(0.5, 0.5, 0.5), true)
			MobBuckets.release(world, held, last_empty)   # (fish / axolotl / tadpole buckets)
			if not p.is_creative():
				_replace_held(p, "bucket")   # (creative: BucketItem.getEmptySuccessItem keeps the full bucket)
		return
	if iname == "bucket":
		bucket_fill(world, p)
		return
	if iname == "milk_bucket":
		p.effects.clear()
		_replace_held(p, "bucket")
		return
	if iname == "potion":
		if world.advancements != null:
			world.advancements.trigger("consume_item", {"item": iname})
		var pid := Potions.potion_of(held)
		Potions.apply(p, pid)
		Audio.play("entity.generic.drink", p.pos, "Players")
		if not p.is_creative():
			_replace_held(p, "glass_bottle")
		return
	if iname == "splash_potion" or iname == "lingering_potion":
		# wiki Splash / Lingering Potion: thrown at 0.5 blocks per tick with a -20 degree pitch offset (aimed 20 degrees
		# higher than the look), inaccuracy 1 (Java Projectile.shoot spread)
		var pyr := deg_to_rad(p.yaw)
		var ppr := deg_to_rad(p.pitch - 20.0)
		var pdir := Vector3(-sin(pyr) * cos(ppr), -sin(ppr), cos(pyr) * cos(ppr)).normalized()
		pdir = (pdir + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * 0.0075).normalized()
		world.entities.spawn_projectile(iname, p.eye_pos() - Vector3(0, 0.1, 0), pdir * 0.5, p)
		var pe = world.entities.ents[world.entities.ents.size() - 1]
		pe.stack = held.copy()
		Audio.play("entity.%s.throw" % iname, p.pos, "Neutral", 0.5, 0.4 / (randf() * 0.4 + 0.8))
		if not p.is_creative():
			p.inventory.consume_held()
		return
	if iname == "glass_bottle":
		# wiki Dragon's Breath: a glass bottle used in the dragon's purple cloud collects it (the cloud shrinks by 0.5;
		# Java BottleItem: clouds within the player's box grown by 2)
		var bmn := p.aabb_min() - Vector3(2, 2, 2)
		var bmx := p.aabb_max() + Vector3(2, 2, 2)
		for ce in world.entities.ents:
			if ce.kind == "cloud" and not ce.dead and ce.id != "potion" and ce.pos.x >= bmn.x and ce.pos.x <= bmx.x and ce.pos.y >= bmn.y and ce.pos.y <= bmx.y and ce.pos.z >= bmn.z and ce.pos.z <= bmx.z:
				ce.data["r"] = float(ce.data.get("r", 3.0)) - 0.5
				Audio.play("item.bottle.fill_dragonbreath", p.pos, "Neutral")
				if p.is_creative():
					p.inventory.add(ItemStack.named("dragon_breath", 1))
				else:
					var hb := p.inventory.held()
					hb.count -= 1
					if hb.count <= 0:
						p.inventory.set_slot(p.inventory.selected, ItemStack.named("dragon_breath", 1))
					elif p.inventory.add(ItemStack.named("dragon_breath", 1)) > 0:
						world.entities.spawn_item(p.pos, ItemStack.named("dragon_breath", 1))
				world.inv_changed()
				return
		var wh := VoxelRaycast.cast(p.eye_pos(), p.look_dir(), p.block_reach(), world.state_at, Res.blocks, true)
		if not wh.is_empty() and (Res.blocks.st_flags[int(wh["state"])] & BlockRegistry.F_LIQUID) != 0 and (Res.blocks.st_flags[int(wh["state"])] & BlockRegistry.F_LAVA) == 0:
			var wb := Potions.make("potion", "water")
			if p.is_creative():
				p.inventory.add(wb)
			else:
				var h := p.inventory.held()
				h.count -= 1
				if h.count <= 0:
					p.inventory.set_slot(p.inventory.selected, wb)
				elif p.inventory.add(wb) > 0:
					world.entities.spawn_item(p.pos, wb)
			Audio.play("item.bottle.fill", p.pos, "Players")
		return
	if iname == "ender_eye":
		# Java EnderEyeItem.use: locate the nearest stronghold and throw an eye toward it (overworld only)
		if world.dimension == "overworld" and world.gen is VanillaGenerator and (world.gen as VanillaGenerator).structures != null:
			var sc: Vector2i = (world.gen as VanillaGenerator).structures.nearest_stronghold(int(floor(p.pos.x)) >> 4, int(floor(p.pos.z)) >> 4)
			if sc.x < (1 << 28):
				world.entities.throw_eye(p.eye_pos() + p.look_dir() * 0.5, Vector3(sc.x * 16 + 8, 32, sc.y * 16 + 8))
				Audio.play("entity.ender_eye.launch", p.pos, "Neutral")
				if not p.is_creative():
					p.inventory.consume_held()
		return
	if iname == "experience_bottle":
		# Java ExperienceBottleItem: thrown 20 degrees up at 0.7
		var yr2 := deg_to_rad(p.yaw)
		var pr2 := deg_to_rad(p.pitch - 20.0)
		var d := Vector3(-sin(yr2) * cos(pr2), -sin(pr2), cos(yr2) * cos(pr2))
		world.entities.spawn_projectile("experience_bottle", p.eye_pos(), d.normalized() * 0.7, p)
		Audio.play("entity.experience_bottle.throw", p.pos, "Neutral", 0.5, 0.4 / (randf() * 0.4 + 0.8))
		if not p.is_creative():
			p.inventory.consume_held()
		return
	if iname in ["ender_pearl", "snowball", "egg", "blue_egg", "brown_egg"]:
		# Java ThrowableItem: velocity 1.5 along the look, sound, 4 tick cooldown (ender pearl 20)
		world.entities.spawn_projectile(iname, p.eye_pos() - Vector3(0, 0.1, 0), p.look_dir() * 1.5, p)
		Audio.play("entity.%s.throw" % ("egg" if iname.ends_with("egg") else iname), p.pos, "Neutral", 0.5, 0.4 / (randf() * 0.4 + 0.8))
		if iname == "ender_pearl":
			p.add_cooldown("ender_pearl", 20)   # wiki Ender Pearl: 1 s cooldown (also in Creative)
		if not p.is_creative():
			p.inventory.consume_held()


## Java RedStoneOreBlock.interact (attack, use, stepped on without sneaking): red dust on the free faces and the lit
## state (light 9) until the next random tick.
static func redstone_ore_interact(world, pos: Vector3i, st: int) -> void:
	var b := Res.blocks
	if not b.name_of(st).ends_with("redstone_ore"):
		return
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var q: Vector3i = pos + d
		var qs: int = world.state_at(q.x, q.y, q.z)
		if qs > 0 and (b.st_flags[qs] & BlockRegistry.F_OPAQUE) != 0:
			continue
		var c := Vector3(pos) + Vector3(0.5, 0.5, 0.5) + Vector3(d) * 0.5625
		var r := Vector3(randf() if d.x == 0 else 0.0, randf() if d.y == 0 else 0.0, randf() if d.z == 0 else 0.0) - Vector3(0.5 if d.x == 0 else 0.0, 0.5 if d.y == 0 else 0.0, 0.5 if d.z == 0 else 0.0)
		Particles.emit("dust", c + r, Vector3.ZERO, Color(1.0, 0.0, 0.0))
	if b.get_prop(st, "lit") != "true":
		world.set_block(pos.x, pos.y, pos.z, b.with_prop(st, "lit", "true"))


## wiki Respawn Anchor: glowstone adds a charge (max 4); with charges, using it sets the respawn point where anchors
## work (26.3 dimension attribute gameplay/respawn_anchor_works: the Nether) and explodes elsewhere (power 5, fire).
static func respawn_anchor_use(world, pos: Vector3i, st: int, p: Player) -> bool:
	var b := Res.blocks
	var ch := int(b.get_prop(st, "charges"))
	var held := p.inventory.held()
	var at := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	if not held.is_empty() and held.name() == "glowstone" and ch < 4:
		world.set_block(pos.x, pos.y, pos.z, b.with_prop(st, "charges", str(ch + 1)))
		Audio.play("block.respawn_anchor.charge", at, "Blocks")
		if not p.is_creative():
			p.inventory.consume_held()
		return true
	if ch == 0:
		return false
	var works := bool((world.dim_type.get("attributes", {}) as Dictionary).get("minecraft:gameplay/respawn_anchor_works", false)) if world.get("dim_type") is Dictionary else false
	if not works:
		world.set_block(pos.x, pos.y, pos.z, 0)
		world.entities.explode(at, 5.0, true, true)   # (bad_respawn_point explosion)
		return true
	if not (p.has_spawn and p.spawn_point == pos and p.spawn_dim == str(world.dimension)):
		p.spawn_point = pos
		p.spawn_dim = str(world.dimension)
		p.has_spawn = true
		Audio.play("block.respawn_anchor.set_spawn", at, "Blocks")
		world.hud.chat_message(Res.tr_key("block.minecraft.set_spawn", "Respawn point set"))
	return true


static func use_block(world, hit: Dictionary) -> bool:
	var blocks := Res.blocks
	var pos: Vector3i = hit["pos"]
	var st: int = hit["state"]
	var name := blocks.name_of(st)
	var p: Player = world.player
	if p.mode == Player.Mode.SPECTATOR:
		return false
	if name.ends_with("_fence") and Leads.use_on_fence(world, pos):
		return true
	if name.ends_with("copper_golem_statue") and not p.inventory.held().name().ends_with("_axe") and CopperGolem.cycle_pose(world, pos, st):
		return true
	if Shelf.is_shelf(name):
		return Shelf.use(world, pos, st, hit, p)
	if (name.ends_with("_door") and name != "iron_door") or (name.ends_with("_trapdoor") and name != "iron_trapdoor") or name.ends_with("_fence_gate"):
		var open := blocks.get_prop(st, "open") == "true"
		var ns := blocks.with_prop(st, "open", "false" if open else "true")
		if name.ends_with("_fence_gate") and not open:
			ns = blocks.with_prop(ns, "facing", horizontal_facing(p.yaw))
		world.set_block(pos.x, pos.y, pos.z, ns)
		if name.ends_with("_door"):
			var other := pos + (Vector3i(0, 1, 0) if blocks.get_prop(st, "half") == "lower" else Vector3i(0, -1, 0))
			var os: int = world.state_at(other.x, other.y, other.z)
			if os > 0 and blocks.name_of(os) == name:
				world.set_block(other.x, other.y, other.z, blocks.with_prop(os, "open", "false" if open else "true"))
		Redstone.play_door_sound(pos, name, not open)   # (per wood / metal set: cherry, bamboo, nether, copper ...)
		return true
	if name == "redstone_wire" and p.mode != Player.Mode.ADVENTURE:
		return RedstoneWire.toggle(world, pos, st)   # Java Edition: an isolated cross <-> dot
	if name == "lever":
		var pw := blocks.get_prop(st, "powered") == "true"
		world.set_block(pos.x, pos.y, pos.z, blocks.with_prop(st, "powered", "false" if pw else "true"))
		Audio.play("block.lever.click", Vector3(pos), "Blocks", 0.3, 0.5 if pw else 0.6)
		Redstone.on_changed(world, pos)
		return true
	if name.ends_with("_button"):
		if blocks.get_prop(st, "powered") != "true":
			world.set_block(pos.x, pos.y, pos.z, blocks.with_prop(st, "powered", "true"))
			Redstone.schedule_tick(world, pos, 30 if name.contains("wood") or Tags.has_block("wooden_buttons", name) else 20)
			Redstone.on_changed(world, pos)
			Audio.play("block.%s_button.click_on" % Sensors.set_type(name), Vector3(pos) + Vector3(0.5, 0.5, 0.5), "Blocks")   # (BlockSetType sounds)
		return true
	if name.ends_with("_bed"):
		return world.entities.try_sleep(pos, st)
	if name in ["enchanting_table", "anvil", "chipped_anvil", "damaged_anvil", "grindstone", "smithing_table", "stonecutter", "loom", "cartography_table"]:
		var ws = load("res://scripts/ui/workstation_screen.gd").new()
		ws.kind = "anvil" if name.ends_with("anvil") else name
		ws.pos = pos
		world.open_screen(ws)
		return true
	if name == "crafting_table":
		var cs = load("res://scripts/ui/crafting_screen.gd").new()
		cs.grid_size = 3
		world.open_screen(cs)
		return true
	if name in ["furnace", "blast_furnace", "smoker", "chest", "trapped_chest", "barrel", "hopper", "dispenser", "dropper", "crafter", "ender_chest", "brewing_stand"] or name.ends_with("shulker_box") or name.ends_with("copper_chest"):
		var cont = load("res://scripts/ui/container_screen.gd").new()
		cont.pos = pos
		cont.kind = name
		world.open_screen(cont)
		return true
	if name == "daylight_detector":
		Sensors.use_detector(world, pos, st)   # wiki Daylight Detector: use inverts it
		return true
	if name == "respawn_anchor":
		return respawn_anchor_use(world, pos, st, p)
	if (name == "campfire" or name == "soul_campfire") and BlockEntities.campfire_place(world, pos, p.inventory.held(), p):
		return true
	if name.ends_with("redstone_ore"):
		redstone_ore_interact(world, pos, st)
		# Java: PASS when the held block item can be placed (placement continues), else consumed
		return Res.items.place_block[p.inventory.held().item] < 0 if not p.inventory.held().is_empty() else true
	if name == "note_block":
		var note := (int(blocks.get_prop(st, "note")) + 1) % 25
		world.set_block(pos.x, pos.y, pos.z, blocks.with_prop(st, "note", str(note)))
		BlockEntities.play_note(world, pos)
		return true
	if name == "cake" or name.ends_with("candle_cake"):
		if p.food < 20 or p.is_creative():
			p.food = mini(20, p.food + 2)
			p.saturation = minf(float(p.food), p.saturation + 0.4)
			var bites := int(blocks.get_prop(st, "bites")) + 1 if name == "cake" else 1
			if name != "cake":
				# wiki: Cake - eating a candle cake breaks the candle off (it drops); the cake loses one of its 7 slices
				world.entities.spawn_item(Vector3(pos) + Vector3(0.5, 0.5, 0.5), ItemStack.named(name.trim_suffix("_cake"), 1))
				world.set_block(pos.x, pos.y, pos.z, blocks.with_prop(blocks.default_state("cake"), "bites", str(bites)))
			elif bites >= 7:
				world.set_block(pos.x, pos.y, pos.z, 0)
			else:
				world.set_block(pos.x, pos.y, pos.z, blocks.with_prop(st, "bites", str(bites)))
			return true
	if name == "jukebox":
		return BlockEntities.use_jukebox(world, pos, p)
	if Signs.is_sign(name):
		return Signs.use(world, pos, p)
	if name == "vault":
		return Trials.use_vault(world, pos, p)
	if name == "lectern":
		var ld := BlockEntities.get_data(world, pos)
		var held := p.inventory.held()
		if not ld.has("book"):
			if held.is_empty() or not (held.name() in ["writable_book", "written_book"]):
				return false
			var one := held.copy()
			one.count = 1
			BlockEntities.set_data(world, pos, {"id": "lectern", "book": one.to_dict(), "page": 0})
			if not p.is_creative():
				p.inventory.consume_held()
			world.set_block(pos.x, pos.y, pos.z, blocks.with_prop(st, "has_book", "true"))
			Audio.play("item.book.put", Vector3(pos), "Blocks")
			world.inv_changed()
			return true
		var lb = load("res://scripts/ui/book_screen.gd").new()
		lb.world = world
		lb.stack = ItemStack.from_dict(ld["book"])
		lb.lectern = pos
		world.open_screen(lb)
		return true
	if CommandBlocks.is_command_block(name):
		if not p.is_creative() or not bool(world.level.get("allow_commands", false)):
			return false
		var cbs = load("res://scripts/ui/command_block_screen.gd").new()
		cbs.world = world
		cbs.pos = pos
		world.open_screen(cbs)
		return true
	if name == "composter":
		return Beacons.use_composter(world, pos, st, p)
	if name == "beacon":
		if BlockEntities.get_data(world, pos).is_empty():
			BlockEntities.set_data(world, pos, {"id": "beacon", "levels": 0, "primary": "", "secondary": ""})
		var bsc = load("res://scripts/ui/beacon_screen.gd").new()
		bsc.pos = pos
		world.open_screen(bsc)
		return true
	if name == "bell":
		return Bells.use(world, pos, st, hit)
	if name == "repeater":
		var d := int(blocks.get_prop(st, "delay")) % 4 + 1
		world.set_block(pos.x, pos.y, pos.z, blocks.with_prop(st, "delay", str(d)))
		return true
	if name == "comparator":
		world.set_block(pos.x, pos.y, pos.z, blocks.with_prop(st, "mode", "subtract" if blocks.get_prop(st, "mode") == "compare" else "compare"))
		return true
	if name.ends_with("_cushion"):
		return world.entities.sit_on(pos)
	return false


static func on_block_broken(world, pos: Vector3i, st: int) -> void:
	var blocks := Res.blocks
	var name := blocks.name_of(st)
	# (the other half of a door / tall plant / bed went with the set_block that removed this one: Support, Java
	# updateShape -> destroyBlock, with its drops - the loot tables give one item between the two halves)
	# wiki Piston Head: an extended piston and its head are one block - breaking the head breaks the piston (dropping it,
	# none in creative), breaking the piston removes the head (Java PistonHeadBlock.onRemove / playerWillDestroy)
	if name == "piston_head":
		Pistons.head_broken(world, pos, st)
	elif (name == "piston" or name == "sticky_piston") and blocks.get_prop(st, "extended") == "true":
		Pistons.base_broken(world, pos, st)
	BlockEntities.on_removed(world, pos, st)
	# wiki String: cutting tripwire with shears disarms it (no pulse); any other break pulses its hooks
	Tripwires.on_removed(world, pos, st, world.player != null and world.player.inventory.held().name() == "shears")
	BlockUpdates.schedule_neighbors(world, pos)
	Redstone.on_changed(world, pos)


## Dimension attribute minecraft:gameplay/water_evaporates (26.3 dimension_type data; the Nether): placed water vanishes.
static func water_evaporates(world) -> bool:
	var at = world.dim_type.get("attributes", {})
	return at is Dictionary and bool((at as Dictionary).get("minecraft:gameplay/water_evaporates", false))


## Java BucketItem.emptyContents with WATER_EVAPORATES: fire extinguish sound (0.5, 2.6 + (r - r) * 0.8), 8 large smoke
## particles at random points of the block.
static func evaporate(world, pos: Vector3i) -> void:
	Audio.play("block.fire.extinguish", Vector3(pos) + Vector3(0.5, 0.5, 0.5), "Blocks", 0.5, 2.6 + (randf() - randf()) * 0.8)
	for i in 8:
		Particles.emit("large_smoke", Vector3(pos) + Vector3(randf(), randf(), randf()))


# ---------------------------------------------------------------- buckets / waterlogging

const NO_POS := Vector3i(0, -100000, 0)


## Java LiquidBlockContainer: every block with a `waterlogged` property (SimpleWaterloggedBlock: slabs, stairs, fences,
## walls, panes, bars, chains, trapdoors, signs, rails, ladders, lanterns, candles, campfires, chests, corals, leaves,
## grates, mangrove roots, dripleaves, sculk, ... - the wiki Waterlogging list) and kelp / seagrass (never take more).
static func liquid_container(st: int) -> bool:
	if st <= 0:
		return false
	return Res.blocks.has_prop(st, "waterlogged") or Res.blocks.name_of(st) in BlockRegistry.ALWAYS_WATER


## SimpleWaterloggedBlock.canPlaceLiquid: water only (fluid == Fluids.WATER; since 22w45a also into a block that is
## already waterlogged - the bucket empties into it); SlabBlock: not a double slab.
static func can_place_water(st: int) -> bool:
	var b := Res.blocks
	if st <= 0 or not b.has_prop(st, "waterlogged"):
		return false
	return not (b.name_of(st).ends_with("_slab") and b.get_prop(st, "type") == "double")


## SimpleWaterloggedBlock.placeLiquid: an unwaterlogged block takes a water source - waterlogged, the water's tick
## scheduled (WaterFluid tick delay 5). CampfireBlock.placeLiquid: a lit campfire goes out (entity.generic.
## extinguish_fire 1.0 / 1.0, wiki Campfire sounds); CandleBlock.placeLiquid: lit candles go out (block.candle.
## extinguish; wiki Waterlogging: "Candles unlight upon becoming waterlogged"). False when nothing changed.
static func waterlog(world, pos: Vector3i, st: int) -> bool:
	var b := Res.blocks
	if not can_place_water(st) or b.get_prop(st, "waterlogged") == "true":
		return false
	var ns := b.with_prop(st, "waterlogged", "true")
	if b.has_prop(ns, "lit") and b.get_prop(ns, "lit") == "true":
		var nm := b.name_of(ns)
		if nm.ends_with("campfire"):
			ns = b.with_prop(ns, "lit", "false")
			Audio.play("entity.generic.extinguish_fire", Vector3(pos) + Vector3(0.5, 0.5, 0.5), "Blocks", 1.0, 1.0)
		elif nm.ends_with("candle"):
			ns = b.with_prop(ns, "lit", "false")
			Audio.play("block.candle.extinguish", Vector3(pos) + Vector3(0.5, 0.5, 0.5), "Blocks", 1.0, 1.0)
	world.set_block(pos.x, pos.y, pos.z, ns)
	BlockUpdates.schedule(world, pos, 5)
	return true


## Java BucketItem.emptyContents: water / lava into pos when it is air, a block the fluid replaces
## (BlockBehaviour.canBeReplaced(fluid): replaceable or not solid - destroyed with its drops) or, for water, a liquid
## container that takes it (waterlogged); otherwise into `alt` (the block in front of the clicked face; NO_POS:
## none, as for dispensers). Where water evaporates (the Nether) it vanishes with smoke. Sound item.bucket.empty(_lava)
## (Blocks, 1.0 / 1.0, wiki Bucket sounds). True when the bucket emptied.
## `sound`: [event, volume, pitch] played instead (MobBucketItem.playEmptySound, Neutral); last_empty = where it emptied.
static var last_empty := Vector3i(0, -100000, 0)
static func bucket_empty(world, pos: Vector3i, water: bool, alt: Vector3i = NO_POS, sound: Array = []) -> bool:
	var b := Res.blocks
	var cur: int = world.state_at(pos.x, pos.y, pos.z) if pos.y >= Coords.MIN_Y and pos.y < Coords.MAX_Y else -1
	var replace := cur > 0 and ((b.st_flags[cur] & BlockRegistry.F_REPLACEABLE) != 0 or (b.st_flags[cur] & BlockRegistry.F_SOLID) == 0)
	if cur < 0 or not (cur == 0 or replace or (water and can_place_water(cur))):
		return alt != NO_POS and alt != pos and bucket_empty(world, alt, water, NO_POS, sound)
	if water and water_evaporates(world):
		evaporate(world, pos)
		last_empty = pos
		return true
	var snd := "item.bucket.empty" if water else "item.bucket.empty_lava"
	var sv := 1.0
	var sp := 1.0
	var scat := "Blocks"
	if sound.size() == 3:
		snd = str(sound[0])
		sv = float(sound[1])
		sp = float(sound[2])
		scat = "Neutral"
	last_empty = pos
	if water and liquid_container(cur):
		waterlog(world, pos, cur)   # (already waterlogged, kelp, seagrass: the bucket still empties, nothing changes)
		Audio.play(snd, Vector3(pos) + Vector3(0.5, 0.5, 0.5), scat, sv, sp)
		return true
	var fluid := b.WATER if water else b.LAVA
	if replace and (b.st_flags[cur] & BlockRegistry.F_LIQUID) == 0:
		# Level.destroyBlock: drops, and a waterlogged block leaves its water (lava then replaces it)
		if world.gamerule("doTileDrops", true) and world.get("entities") != null:
			for s in Loot.block_drops(cur, null, world, pos):
				world.entities.spawn_item(Vector3(pos) + Vector3(0.5, 0.5, 0.5), s)
		BlockProperties.play_block_sound(cur, "break", Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		if world.get("entities") != null and world.entities.has_method("spawn_block_particles"):
			world.entities.spawn_block_particles(pos, cur)
	if cur == fluid:
		# setBlock changed nothing, but the block there is already a source of it: the bucket still empties
		Audio.play(snd, Vector3(pos) + Vector3(0.5, 0.5, 0.5), scat, sv, sp)
		return true
	world.set_block(pos.x, pos.y, pos.z, fluid)
	# Java FlowingFluid.getTickDelay: water 5, lava 30 (10 where lava is fast: the Nether's fast_lava attribute)
	BlockUpdates.schedule(world, pos, 5 if water else BlockUpdates.lava_delay(world))
	Audio.play(snd, Vector3(pos) + Vector3(0.5, 0.5, 0.5), scat, sv, sp)
	return true


## Java BucketPickup.pickupBlock at pos: a fluid source (LiquidBlock: level 0) becomes air, a waterlogged block gives
## its water (SimpleWaterloggedBlock: waterlogged = false), powder snow becomes air. Returns the filled bucket's item
## name ("" when nothing was picked up) after playing its pickup sound (item.bucket.fill / fill_lava /
## fill_powder_snow, Players, wiki Bucket sounds; dispensers play only their own sound).
static func bucket_pickup(world, pos: Vector3i, sound := true) -> String:
	var b := Res.blocks
	var st: int = world.state_at(pos.x, pos.y, pos.z)
	if st <= 0:
		return ""
	var filled := ""
	var snd := ""
	if (b.st_flags[st] & BlockRegistry.F_LIQUID) != 0:
		if b.st_level[st] != 0:
			return ""
		var lava := (b.st_flags[st] & BlockRegistry.F_LAVA) != 0
		world.set_block(pos.x, pos.y, pos.z, 0)
		filled = "lava_bucket" if lava else "water_bucket"
		snd = "item.bucket.fill_lava" if lava else "item.bucket.fill"
	elif b.has_prop(st, "waterlogged") and b.get_prop(st, "waterlogged") == "true":
		world.set_block(pos.x, pos.y, pos.z, b.with_prop(st, "waterlogged", "false"))
		filled = "water_bucket"
		snd = "item.bucket.fill"
	elif b.name_of(st) == "powder_snow":
		world.set_block(pos.x, pos.y, pos.z, 0)
		filled = "powder_snow_bucket"
		snd = "item.bucket.fill_powder_snow"
	else:
		return ""
	if sound:
		Audio.play(snd, Vector3(pos) + Vector3(0.5, 0.5, 0.5), "Players", 1.0, 1.0)
	return filled


## Java BucketItem.use with an empty bucket: ray through flowing fluid to the first source / waterlogged block / block
## (ClipContext.Fluid.SOURCE_ONLY) and pick it up (ItemUtils.createFilledResult: creative keeps the empty bucket and
## gets the filled one only if it has none).
static func bucket_fill(world, p: Player) -> bool:
	var fh := VoxelRaycast.cast(p.eye_pos(), p.look_dir(), p.block_reach(), world.state_at, Res.blocks, true, true)
	if fh.is_empty():
		return false
	var pos: Vector3i = fh["pos"]
	var filled := bucket_pickup(world, pos)
	if filled == "":
		return false
	Sculk.vibrate(world, Vector3(pos) + Vector3(0.5, 0.5, 0.5), true)
	_replace_held(p, filled)
	return true
