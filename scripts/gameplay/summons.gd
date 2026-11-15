## Summons — Java block patterns that create mobs when the last block is placed (source D):
## Wither (3 wither skeleton skulls on a T of #wither_summon_base_blocks, lower corners empty, X or Z plane),
## Iron Golem (carved pumpkin / jack o'lantern on a T of iron blocks), Snow Golem (pumpkin on 2 snow blocks).
## Contract: try(world, pos, state) after a block is placed; consumes the pattern and spawns the mob.
class_name Summons
extends RefCounted


static func _n(world, p: Vector3i) -> String:
	var st: int = world.state_at(p.x, p.y, p.z)
	return Res.blocks.name_of(st) if st > 0 else "air"


static func try(world, pos: Vector3i, st: int) -> void:
	var n := Res.blocks.name_of(st)
	if n == "wither_skeleton_skull" or n == "wither_skeleton_wall_skull":
		_wither(world, pos)
	elif n == "carved_pumpkin" or n == "jack_o_lantern":
		if not _snow_golem(world, pos) and not _iron_golem(world, pos):
			CopperGolem.try_build(world, pos, st)


static func _is_base(n: String) -> bool:
	return n == "soul_sand" or n == "soul_soil"


static func _wither(world, pos: Vector3i) -> void:
	if world.difficulty == 0:
		return
	for axis in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
		for k in range(-1, 2):
			var c: Vector3i = pos - axis * k   # top-centre skull
			var ok := true
			for i in range(-1, 2):
				var top := _n(world, c + axis * i)
				if top != "wither_skeleton_skull" and top != "wither_skeleton_wall_skull":
					ok = false
				if not _is_base(_n(world, c + axis * i + Vector3i(0, -1, 0))):
					ok = false
			if not ok or not _is_base(_n(world, c + Vector3i(0, -2, 0))):
				continue
			if _n(world, c + axis + Vector3i(0, -2, 0)) != "air" or _n(world, c - axis + Vector3i(0, -2, 0)) != "air":
				continue
			for i in range(-1, 2):
				world.set_block(c.x + axis.x * i, c.y, c.z + axis.z * i, 0)
				world.set_block(c.x + axis.x * i, c.y - 1, c.z + axis.z * i, 0)
			world.set_block(c.x, c.y - 2, c.z, 0)
			var w = world.entities.spawn_mob("wither", Vector3(c) + Vector3(0.5, -2.0, 0.5))
			if w != null:
				w.persistent = true
				w.hp = 100.0   # Java: spawns at 1/3 health and heals to full while invulnerable (220 ticks)
				w.charge = -220
			Audio.play("entity.wither.spawn", Vector3(c), "Hostile")
			return


static func _snow_golem(world, pos: Vector3i) -> bool:
	if _n(world, pos + Vector3i(0, -1, 0)) == "snow_block" and _n(world, pos + Vector3i(0, -2, 0)) == "snow_block":
		for i in 3:
			world.set_block(pos.x, pos.y - i, pos.z, 0)
		world.entities.spawn_mob("snow_golem", Vector3(pos) + Vector3(0.5, -2.0, 0.5))
		return true
	return false


static func _iron_golem(world, pos: Vector3i) -> bool:
	for axis in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
		var b := pos + Vector3i(0, -1, 0)
		if _n(world, b) != "iron_block" or _n(world, b + axis) != "iron_block" or _n(world, b - axis) != "iron_block":
			continue
		if _n(world, b + Vector3i(0, -1, 0)) != "iron_block":
			continue
		# wiki Iron Golem: the spaces above and below each arm must be air
		if _n(world, b + axis + Vector3i(0, -1, 0)) != "air" or _n(world, b - axis + Vector3i(0, -1, 0)) != "air":
			continue
		if _n(world, pos + axis) != "air" or _n(world, pos - axis) != "air":
			continue
		world.set_block(pos.x, pos.y, pos.z, 0)
		for q in [b, b + axis, b - axis, b + Vector3i(0, -1, 0)]:
			world.set_block(q.x, q.y, q.z, 0)
		world.entities.spawn_mob("iron_golem", Vector3(b) + Vector3(0.5, -1.0, 0.5))
		return true
	return false
