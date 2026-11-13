## Net (autoload) — LAN multiplayer over Godot high-level multiplayer (ENet). Host-authoritative: the host world
## simulates blocks, entities, time and weather and keeps chunks loaded around every connected player. Clients run
## the same deterministic generator from the host's seed/settings and fetch only chunks the host has modified.
## Synced: modified chunk data, block changes (both ways), players (state 20 Hz, drawn with the player model and a
## name tag), entities (host -> client snapshots 20 Hz; client attacks/interactions/drops/spawns/projectiles are
## forwarded to the host), damage/items/XP/effects to clients, chat, time/weather, dimension (everyone follows the
## host), client player data (saved in the host's level.json "net_players").
## LAN discovery: UDP broadcast "[MOTD]<world>[/MOTD][AD]<port>[/AD]" to port 4445 every 1.5 s.
## APPROXIMATE vs Java: own protocol (not the Minecraft protocol, so vanilla clients cannot join); clients cannot
## use portals; containers (chests, furnaces) opened by a client use the client's copy; commands are host-only.
extends Node

const DISCOVERY_PORT := 4445
const DEFAULT_PORT := 25565
const PROTOCOL := 1
const CLIENT_FOLDER := ".lan_client"
const VIEW := 80.0          # entity snapshot range (blocks)


## Host-side stand-in for a remote player: mobs target it, hits/items/XP/effects are forwarded to its client.
class Proxy extends Player:
	var peer_id := 0
	var net

	func hurt(amount: float, source: String, bypass_armor: bool = false, _from: Vector3 = Vector3.INF, _attacker = null) -> bool:
		if dead or mode == Mode.CREATIVE or mode == Mode.SPECTATOR or invuln > 0:
			return false
		invuln = 10
		hurt_time = 10
		net.rpc_id(peer_id, "_hurt", amount, source, bypass_armor)
		return true

	func add_xp(points: int) -> void:
		net.rpc_id(peer_id, "_give_xp", points)

	func add_effect(id: String, amp: int, ticks: int) -> void:
		net.rpc_id(peer_id, "_effect", id, amp, ticks)


class ProxyInventory extends Inventory:
	var peer_id := 0
	var net

	func add(s: ItemStack) -> int:
		if s == null or s.is_empty():
			return 0
		net.rpc_id(peer_id, "_give", s.to_dict())
		return 0


var role := ""                 # "" | "host" | "client"
var world                      # WorldManager
var app
var my_name := "Player"
var port := DEFAULT_PORT
var players: Dictionary = {}   # peer id -> {name, pos, prev, t, yaw, pitch, sneak, mode, dead, dim, node, proxy, limb}
var applying := false          # applying remote state: no forwarding / re-broadcast
var status := ""
var autoplay_opts: Dictionary = {}
var discovered: Dictionary = {}   # "ip:port" -> {name, ip, port, t}
var test_log: Array = []

var _block_out := PackedInt32Array()
var _block_send := PackedInt32Array()
var _block_in: Array = []
var _req_mx := Mutex.new()
var _reqs: Dictionary = {}       # request id -> {sem, data, cx, cz, sent}
var _rid := 0
var _uid := 1
var puppets: Dictionary = {}     # client: uid -> EntityManager.Ent
var _bcast: PacketPeerUDP
var _bcast_t := 0.0
var _listen: PacketPeerUDP
var _send_t := 0.0
var _slow_t := 0.0
var _pdata_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)


func is_host() -> bool:
	return role == "host"


func is_client() -> bool:
	return role == "client"


func active() -> bool:
	return role != ""


func my_id() -> int:
	return multiplayer.get_unique_id() if active() else 1


# ------------------------------------------------------------------ session control

## Open the current world to LAN. bind_ip "*" = all interfaces (+ discovery broadcast); tests use 127.0.0.1.
func host(w, p_port: int = DEFAULT_PORT, bind_ip: String = "*") -> String:
	if role != "":
		return "Already " + ("hosting" if is_host() else "connected")
	var used := -1
	var peer: ENetMultiplayerPeer
	for i in 10:
		peer = ENetMultiplayerPeer.new()
		peer.set_bind_ip(bind_ip)
		if peer.create_server(p_port + i, 8) == OK:
			used = p_port + i
			break
	if used < 0:
		return "Could not open a network port"
	multiplayer.multiplayer_peer = peer
	role = "host"
	world = w
	port = used
	my_name = str(Settings.get_v("player_name"))
	if bind_ip == "*":
		_bcast = PacketPeerUDP.new()
		_bcast.set_broadcast_enabled(true)
		_bcast.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	return "Local game hosted on port %d" % used


func join(a, ip: String, p_port: int, name: String, opts: Dictionary = {}) -> String:
	stop()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, p_port) != OK:
		status = "Cannot connect to %s:%d" % [ip, p_port]
		return status
	multiplayer.multiplayer_peer = peer
	role = "client"
	app = a
	my_name = name
	autoplay_opts = opts
	status = "Connecting to %s:%d..." % [ip, p_port]
	return ""


func stop() -> void:
	stop_discovery()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for id in players.keys():
		_free_player(id)
	players.clear()
	puppets.clear()
	_block_in.clear()
	_block_out = PackedInt32Array()
	_block_send = PackedInt32Array()
	_req_mx.lock()
	for r in _reqs.values():
		(r["sem"] as Semaphore).post()
	_req_mx.unlock()
	_bcast = null
	role = ""


## World closed (save and quit / connection lost).
func on_world_closed(w) -> void:
	if world == w:
		if is_client():
			client_save()
		stop()
		world = null


func _on_connected() -> void:
	status = "Logging in..."
	rpc_id(1, "_hello", my_name, PROTOCOL, Res.mode, Res.version)


func _on_failed() -> void:
	status = "Connection failed"
	stop()
	_test_exit()


func _on_server_lost() -> void:
	status = "Connection lost: the host closed the game"
	var w = world
	var test := autoplay_opts.has("nettest")
	stop()
	world = null
	if test:
		get_tree().quit()
	elif w != null and is_instance_valid(w) and app != null:
		app.leave_world()


func _test_exit() -> void:
	if autoplay_opts.has("nettest"):
		print("NET-CLIENT ", status)
		get_tree().quit()


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	var nm: String = players[id]["name"]
	_free_player(id)
	players.erase(id)
	if is_host():
		_chat_all("%s left the game" % nm)


func _free_player(id: int) -> void:
	var pl: Dictionary = players.get(id, {})
	if pl.get("node") != null and is_instance_valid(pl["node"]):
		(pl["node"] as Node).queue_free()


# ------------------------------------------------------------------ login

@rpc("any_peer", "call_remote", "reliable")
func _hello(name: String, proto: int, mode: String, version: String) -> void:
	if not is_host() or world == null:
		return
	var id := multiplayer.get_remote_sender_id()
	if proto != PROTOCOL or mode != Res.mode or version != Res.version:
		rpc_id(id, "_reject", "Incompatible game: the host runs %s assets %s (protocol %d)" % [Res.mode, Res.version, PROTOCOL])
		return
	var nm := name.strip_edges().substr(0, 16)
	if nm == "":
		nm = "Player"
	var taken := [my_name]
	for o in players.values():
		taken.append(o["name"])
	while nm in taken:
		nm += str(id % 10)
	var saved: Dictionary = {}
	var np = world.level.get("net_players", {})
	if np is Dictionary and np.get(nm) is Dictionary:
		saved = np[nm]
	var px := Proxy.new()
	px.peer_id = id
	px.net = self
	var inv := ProxyInventory.new()
	inv.peer_id = id
	inv.net = self
	px.inventory = inv
	var sp: Array = world.level.get("spawn", [0, 80, 0])
	px.pos = Vector3(sp[0], sp[1], sp[2])
	players[id] = {"name": nm, "pos": px.pos, "prev": px.pos, "t": 0, "yaw": 0.0, "pitch": 0.0, "sneak": false, "mode": 0,
		"dead": false, "dim": world.dimension, "node": null, "proxy": px, "limb": 0.0}
	var lv: Dictionary = world.level
	var meta := {"name": lv.get("name", "LAN World"), "seed": lv.get("seed", 0), "generator_id": lv.get("generator_id", "approx_original"),
		"generator_settings": lv.get("generator_settings", {}), "generator_version": lv.get("generator_version", 1),
		"content_version": Res.version, "dimension": world.dimension, "day_time": world.day_time, "game_time": world.game_time,
		"raining": world.raining, "thundering": world.thundering, "difficulty": world.difficulty, "hardcore": world.hardcore,
		"gamerules": world.gamerules, "spawn": sp, "game_mode": lv.get("game_mode", 0), "allow_commands": false,
		"net_client": true, "net_name": nm, "net_host": my_name}
	if not saved.is_empty():
		meta["player"] = saved
	rpc_id(id, "_welcome", meta)
	_chat_all("%s joined the game" % nm)


@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	status = reason
	stop()
	_test_exit()


@rpc("authority", "call_remote", "reliable")
func _welcome(meta: Dictionary) -> void:
	if not is_client():
		return
	my_name = str(meta.get("net_name", my_name))
	if DirAccess.dir_exists_absolute(SaveManager.ROOT.path_join(CLIENT_FOLDER)):
		SaveManager.delete_world(CLIENT_FOLDER)
	var dir := SaveManager.ROOT.path_join(CLIENT_FOLDER)
	DirAccess.make_dir_recursive_absolute(dir.path_join("region"))
	SaveManager.atomic_write(dir.path_join("level.json"), JSON.stringify(meta).to_utf8_buffer())
	status = "Joined " + str(meta.get("name", ""))
	app.start_world(CLIENT_FOLDER, autoplay_opts)


## Called by WorldManager._ready for a world started by this session.
func attach(w) -> void:
	if is_client() or is_host():
		world = w


# ------------------------------------------------------------------ chunks (client worker threads)

## ChunkManager.load_chunk_fn on clients: blocks the worker until the host answers (modified data or {} = generate).
func client_load_chunk(cx: int, cz: int) -> Dictionary:
	if not is_client():
		return {}
	var r := {"sem": Semaphore.new(), "data": {}, "cx": cx, "cz": cz, "sent": false}
	_req_mx.lock()
	_rid += 1
	var rid := _rid
	_reqs[rid] = r
	_req_mx.unlock()
	var t0 := Time.get_ticks_msec()
	var sem: Semaphore = r["sem"]
	while not sem.try_wait():
		if not is_client() or Time.get_ticks_msec() - t0 > 10000:
			break
		OS.delay_msec(3)
	_req_mx.lock()
	_reqs.erase(rid)
	_req_mx.unlock()
	return r["data"]


@rpc("any_peer", "call_remote", "reliable")
func _req_chunk(rid: int, dim: String, cx: int, cz: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	var size := 0
	var data := PackedByteArray()
	if is_host() and world != null and dim == world.dimension:
		var d := _host_chunk(cx, cz)
		if not d.is_empty():
			var raw := var_to_bytes(d)
			size = raw.size()
			data = raw.compress(FileAccess.COMPRESSION_ZSTD)
	rpc_id(id, "_chunk", rid, size, data)


func _host_chunk(cx: int, cz: int) -> Dictionary:
	var c: Chunk = world.cm.get_chunk(cx, cz)
	var d: Dictionary = {}
	if c != null and c.state >= Chunk.DECORATED and c.modified:
		d = SaveManager.encode_chunk(c, Res.blocks)
	else:
		var s = world.save.load_chunk(cx, cz)
		if s is Dictionary:
			d = (s as Dictionary).duplicate()
	if not d.is_empty():
		d["ent"] = []
	return d


@rpc("authority", "call_remote", "reliable")
func _chunk(rid: int, size: int, data: PackedByteArray) -> void:
	var d: Dictionary = {}
	if size > 0:
		var v = bytes_to_var(data.decompress(size, FileAccess.COMPRESSION_ZSTD))
		if v is Dictionary:
			d = v
	_req_mx.lock()
	var r = _reqs.get(rid)
	_req_mx.unlock()
	if r != null:
		r["data"] = d
		(r["sem"] as Semaphore).post()


# ------------------------------------------------------------------ blocks

## Hook from WorldManager.set_block.
func on_local_block(x: int, y: int, z: int, st: int) -> void:
	if applying:
		return
	if is_host() and not players.is_empty():
		_block_out.append_array([x, y, z, st])
	elif is_client():
		_block_send.append_array([x, y, z, st])


@rpc("authority", "call_remote", "reliable")
func _blocks(dim: String, arr: PackedInt32Array) -> void:
	if world == null or world.cm == null or dim != world.dimension:
		return
	applying = true
	for i in range(0, arr.size(), 4):
		if world.set_block(arr[i], arr[i + 1], arr[i + 2], arr[i + 3]) < 0:
			_block_in.append([arr[i], arr[i + 1], arr[i + 2], arr[i + 3]])
	applying = false


@rpc("any_peer", "call_remote", "reliable")
func _set_blocks(dim: String, arr: PackedInt32Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or world == null or not players.has(id) or dim != world.dimension:
		return
	var at: Vector3 = players[id]["pos"]
	for i in range(0, arr.size(), 4):
		if Vector3(arr[i], arr[i + 1], arr[i + 2]).distance_to(at) > 16.0:
			continue
		world.set_block(arr[i], arr[i + 1], arr[i + 2], arr[i + 3])
		test_log.append("client_block %d %d %d %s" % [arr[i], arr[i + 1], arr[i + 2], Res.blocks.name_of(arr[i + 3])])


func _retry_blocks() -> void:
	if _block_in.is_empty():
		return
	var keep: Array = []
	applying = true
	for b in _block_in:
		var c: Chunk = world.cm.get_chunk(int(b[0]) >> 4, int(b[2]) >> 4)
		if c == null:
			continue       # not loading: a later load fetches the host's copy
		if c.state >= Chunk.DECORATED:
			world.set_block(b[0], b[1], b[2], b[3])
		else:
			keep.append(b)
	applying = false
	_block_in = keep


# ------------------------------------------------------------------ players

func _state_of_local() -> Array:
	var p: Player = world.player
	return [my_name, p.pos.x, p.pos.y, p.pos.z, p.yaw, p.pitch, p.sneaking, int(p.mode), p.dead, world.dimension]


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _pstate(st: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or not players.has(id):
		return
	_apply_state(id, st)
	var px: Proxy = players[id]["proxy"]
	px.prev_pos = px.pos
	px.pos = players[id]["pos"]
	px.yaw = float(st[4])
	px.pitch = float(st[5])
	px.sneaking = bool(st[6])
	px.mode = int(st[7]) as Player.Mode
	if px.dead and not bool(st[8]):
		px.health = 20.0
	px.dead = bool(st[8])


@rpc("authority", "call_remote", "unreliable_ordered")
func _pstates(all: Dictionary) -> void:
	if not is_client():
		return
	var me := my_id()
	for id in all:
		if int(id) == me:
			continue
		if not players.has(id):
			players[id] = {"name": str(all[id][0]), "pos": Vector3.ZERO, "prev": Vector3.ZERO, "t": 0, "node": null, "limb": 0.0}
		_apply_state(id, all[id])
	for id in players.keys():
		if not all.has(id):
			_free_player(id)
			players.erase(id)


func _apply_state(id: int, st: Array) -> void:
	var pl: Dictionary = players[id]
	var np := Vector3(float(st[1]), float(st[2]), float(st[3]))
	pl["prev"] = pl["pos"] if int(pl.get("t", 0)) > 0 else np
	pl["limb"] = float(pl.get("limb", 0.0)) + Vector2(np.x - (pl["pos"] as Vector3).x, np.z - (pl["pos"] as Vector3).z).length() * 4.0
	pl["spd"] = Vector2(np.x - (pl["pos"] as Vector3).x, np.z - (pl["pos"] as Vector3).z).length()
	pl["pos"] = np
	pl["t"] = Time.get_ticks_msec()
	pl["yaw"] = float(st[4])
	pl["pitch"] = float(st[5])
	pl["sneak"] = bool(st[6])
	pl["mode"] = int(st[7])
	pl["dead"] = bool(st[8])
	pl["dim"] = str(st[9])


## Host: proxies of players in the host's dimension (mob targets, item pickup, chunk loading centres).
func proxies() -> Array:
	var out: Array = []
	if not is_host() or world == null:
		return out
	for pl in players.values():
		if str(pl.get("dim", "")) == world.dimension:
			out.append(pl["proxy"])
	return out


func player_names() -> Array:
	var out: Array = [my_name]
	for pl in players.values():
		out.append(pl["name"])
	return out


func _render_players() -> void:
	if world == null or world.cm == null:
		return
	var now := Time.get_ticks_msec()
	for id in players:
		var pl: Dictionary = players[id]
		var vis_ok: bool = str(pl.get("dim", world.dimension)) == world.dimension and int(pl.get("mode", 0)) != 3 and not bool(pl.get("dead", false))
		var node: Node3D = pl.get("node")
		if node == null or not is_instance_valid(node):
			node = EntityRenderer.build_rig({"tex": "entity/player/wide/steve", "tex_size": [64, 64], "parts": MobRegistry.PLAYER})
			var tag := Label3D.new()
			tag.text = str(pl["name"])
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.position = Vector3(0, 2.15, 0)
			tag.pixel_size = 0.01
			tag.font_size = 24
			tag.outline_size = 6
			tag.no_depth_test = true
			node.add_child(tag)
			world.add_child(node)
			pl["node"] = node
		node.visible = vis_ok
		if not vis_ok:
			continue
		var a := clampf(float(now - int(pl.get("t", now))) / 50.0, 0.0, 1.0)
		var ip: Vector3 = (pl["prev"] as Vector3).lerp(pl["pos"], a)
		node.position = world.vis(ip)
		node.rotation.y = deg_to_rad(180.0 - float(pl["yaw"]))
		var sw := cos(float(pl["limb"]) * 0.6662) * 1.4 * clampf(float(pl.get("spd", 0.0)) * 4.0, 0.0, 1.0)
		var model: Node = node.get_node_or_null("model")
		if model == null:
			continue
		var l: int = world.cm.get_light(int(floor(ip.x)), int(floor(ip.y + 1.0)), int(floor(ip.z)))
		for c in model.get_children():
			var nm: String = c.name
			if nm == "head" or nm == "hat":
				c.rotation.x = deg_to_rad(-float(pl["pitch"]))
			elif nm.begins_with("leg"):
				c.rotation.x = sw * (1.0 if nm == "leg0" else -1.0)
			elif nm.begins_with("arm"):
				c.rotation.x = -sw * (1.0 if nm == "arm0" else -1.0) * 0.8
			for mi in world.entities._meshes(c):
				mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))
				mi.set_instance_shader_parameter("hurt", 0.0)


# ------------------------------------------------------------------ entities

## Host: snapshot of entities near each client.
func _send_entities() -> void:
	var ents: Array = world.entities.ents
	for id in players:
		var pl: Dictionary = players[id]
		if str(pl.get("dim", "")) != world.dimension:
			continue
		var at: Vector3 = pl["pos"]
		var out: Array = []
		for e in ents:
			if e.dead or e.node == null or e.pos.distance_squared_to(at) > VIEW * VIEW:
				continue
			if e.uid == 0:
				e.uid = _uid
				_uid += 1
			var flags := (1 if e.hurt_time > 0 else 0) | (2 if e.baby_age < 0 else 0) | (4 if e.sheared else 0) | (8 if e.target_player else 0) | (16 if e.fire > 0 else 0)
			var extra = null
			match e.kind:
				"item":
					extra = e.stack.to_dict()
				"falling":
					extra = e.state
				"projectile":
					extra = [e.vel.x, e.vel.y, e.vel.z]
				"mob":
					extra = e.size
				"xp":
					extra = e.xp
			out.append([e.uid, e.kind, e.id, e.pos.x, e.pos.y, e.pos.z, e.body_yaw, e.head_pitch, flags, extra, e.head_yaw])
		rpc_id(id, "_ents", out)


@rpc("authority", "call_remote", "unreliable_ordered")
func _ents(list: Array) -> void:
	if not is_client() or world == null or world.entities == null:
		return
	var em = world.entities
	var seen := {}
	applying = true
	for en in list:
		var uid: int = en[0]
		seen[uid] = true
		var p := Vector3(en[3], en[4], en[5])
		var e = puppets.get(uid)
		if e == null or e.dead:
			e = em.spawn_puppet(en)
			if e == null:
				continue
			puppets[uid] = e
		else:
			var mv := Vector2(p.x - e.pos.x, p.z - e.pos.z).length()
			e.limb_amt_o = e.limb_amt
			e.limb_amt = lerpf(e.limb_amt, clampf(mv * 4.0, 0.0, 1.0), 0.4)
			e.limb += e.limb_amt
			e.prev = e.pos
			e.pos = p
			e.tick_us = Time.get_ticks_usec()
			if e.kind == "item" and en[9] is Dictionary:
				e.stack.count = int((en[9] as Dictionary).get("count", e.stack.count))
		e.body_yaw_o = e.body_yaw
		e.head_yaw_o = e.head_yaw
		e.head_pitch_o = e.head_pitch
		var fl: int = en[8]
		e.body_yaw = float(en[6])
		e.yaw = e.body_yaw
		e.head_pitch = float(en[7])
		e.head_yaw = float(en[10]) if en.size() > 10 else e.body_yaw
		e.hurt_time = 10 if fl & 1 else 0
		e.sheared = (fl & 4) != 0
		e.target_player = (fl & 8) != 0
		e.fire = 1 if fl & 16 else 0
	applying = false
	for uid in puppets.keys():
		if not seen.has(uid):
			var e = puppets[uid]
			if e != null and not e.dead:
				em._remove(e)
			puppets.erase(uid)


func _ent_by_uid(uid: int):
	for e in world.entities.ents:
		if e.uid == uid and not e.dead:
			return e
	return null


## Client -> host forwarded action (spawns, drops, attacks, interactions, trades, player data).
func forward(kind: String, a: Array) -> void:
	if is_client():
		rpc_id(1, "_fwd", kind, a)


@rpc("any_peer", "call_remote", "reliable")
func _fwd(kind: String, a: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not is_host() or world == null or not players.has(id):
		return
	var pl: Dictionary = players[id]
	var em = world.entities
	match kind:
		"item":
			var e = em.spawn_item(Vector3(a[0], a[1], a[2]), ItemStack.from_dict(a[3]))
			if e != null and a.size() >= 8:
				e.vel = Vector3(a[4], a[5], a[6])
				e.pickup_delay = int(a[7])
		"xp":
			em.spawn_xp(Vector3(a[0], a[1], a[2]), int(a[3]))
		"mob":
			em.spawn_mob(str(a[3]), Vector3(a[0], a[1], a[2]), bool(a[4]))
		"projectile":
			em.spawn_projectile(str(a[3]), Vector3(a[0], a[1], a[2]), Vector3(a[4], a[5], a[6]), pl["proxy"])
		"eye":
			em.throw_eye(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]))
		"attack":
			var t = _ent_by_uid(int(a[0]))
			if t != null:
				em._damage(t, float(a[1]), pl["proxy"])
				t.vel += Vector3(a[2], a[3], a[4])
				test_log.append("client_attack %s" % t.id)
		"interact":
			_remote_interact(id, int(a[0]), ItemStack.from_dict(a[1]))
		"trade":
			var v = _ent_by_uid(int(a[0]))
			if v != null:
				var offers: Array = v.data.get("offers", [])
				if int(a[1]) >= 0 and int(a[1]) < offers.size():
					offers[int(a[1])]["uses"] = int(offers[int(a[1])]["uses"]) + 1
					Trading.on_trade(v, offers[int(a[1])])
		"pdata":
			if not (world.level.get("net_players") is Dictionary):
				world.level["net_players"] = {}
			world.level["net_players"][pl["name"]] = a[0]
		"chat":
			_chat_all("<%s> %s" % [pl["name"], str(a[0]).substr(0, 256)])


func _remote_interact(id: int, uid: int, held: ItemStack) -> void:
	var e = _ent_by_uid(uid)
	if e == null or e.kind != "mob":
		return
	if e.def.get("trader", false) and e.baby_age >= 0 and str(e.data.get("prof", "")) != "nitwit":
		rpc_id(id, "_open_trade", uid, e.data)
		return
	if held.is_empty():
		return
	var food: Array = e.def.get("food", [])
	if food.has(held.name()) and e.baby_age >= 0 and e.breed_cd <= 0 and e.love <= 0:
		e.love = 600
		rpc_id(id, "_held", "consume")
	elif held.name() == "shears" and e.id == "sheep" and not e.sheared:
		e.sheared = true
		world.entities.spawn_item(e.pos + Vector3(0, 1, 0), ItemStack.named("white_wool", randi_range(1, 3)))
		Audio.play("entity.sheep.shear", e.pos, "Players")
		rpc_id(id, "_held", "damage")
	elif held.name() == "bucket" and e.id == "cow":
		rpc_id(id, "_held", "milk_bucket")


@rpc("authority", "call_remote", "reliable")
func _open_trade(uid: int, data: Dictionary) -> void:
	var e = puppets.get(uid)
	if e == null or world == null:
		return
	e.data = data
	var ts = load("res://scripts/ui/trade_screen.gd").new()
	ts.villager = e
	world.open_screen(ts)
	Audio.play("entity.villager.trade", e.pos, "Neutral")


@rpc("authority", "call_remote", "reliable")
func _held(action: String) -> void:
	if world == null:
		return
	var p: Player = world.player
	match action:
		"consume":
			if not p.is_creative():
				p.inventory.consume_held()
		"damage":
			Interaction.damage_tool(p, 1)
		_:
			Interaction._replace_held(p, action)
	world.inv_changed()


@rpc("authority", "call_remote", "reliable")
func _hurt(amount: float, source: String, bypass: bool) -> void:
	if world != null and world.player.hurt(amount, source, bypass):
		Audio.play("entity.player.hurt", world.player.pos, "Players")


@rpc("authority", "call_remote", "reliable")
func _give(d: Dictionary) -> void:
	if world == null:
		return
	var s := ItemStack.from_dict(d)
	var left: int = world.player.inventory.add(s)
	Audio.play("entity.item.pickup", world.player.pos, "Players", 0.2, randf_range(1.4, 2.0))
	if left > 0:
		s.count = left
		var p: Vector3 = world.player.pos
		forward("item", [p.x, p.y + 0.5, p.z, s.to_dict(), 0.0, 0.1, 0.0, 60])
	world.inv_changed()


@rpc("authority", "call_remote", "reliable")
func _give_xp(n: int) -> void:
	if world != null:
		world.player.add_xp(n)
		Audio.play("entity.experience_orb.pickup", world.player.pos, "Players", 0.1, randf_range(0.55, 1.45))


@rpc("authority", "call_remote", "reliable")
func _effect(id: String, amp: int, ticks: int) -> void:
	if world != null:
		world.player.add_effect(id, amp, ticks)


# ------------------------------------------------------------------ world state, chat, dimension

@rpc("authority", "call_remote", "reliable")
func _world_state(day: int, gt: int, rain: bool, thunder: bool, diff: int) -> void:
	if world == null:
		return
	world.day_time = day
	world.game_time = gt
	world.raining = rain
	world.thundering = thunder
	world.difficulty = diff


func chat(text: String) -> void:
	if is_client():
		forward("chat", [text])
	elif is_host():
		_chat_all("<%s> %s" % [my_name, text])


func _chat_all(msg: String) -> void:
	if world != null and world.hud != null:
		world.hud.chat_message(msg)
	if is_host():
		rpc("_chat", msg)


@rpc("authority", "call_remote", "reliable")
func _chat(msg: String) -> void:
	if world != null and world.hud != null:
		world.hud.chat_message(msg)


## Host finished arriving in a dimension: clients follow to the host's position.
func host_arrived() -> void:
	if is_host() and not players.is_empty():
		var p: Vector3 = world.player.pos
		rpc("_follow_dim", world.dimension, p.x, p.y, p.z)


@rpc("authority", "call_remote", "reliable")
func _follow_dim(dim: String, x: float, y: float, z: float) -> void:
	if world == null:
		return
	puppets.clear()
	if dim != world.dimension:
		world.change_dimension(dim, {"kind": "exact", "pos": Vector3(x + 1.0, y, z)})


func client_save() -> void:
	if is_client() and world != null and world.player != null:
		forward("pdata", [world.player.to_dict()])


# ------------------------------------------------------------------ discovery

func start_discovery() -> void:
	stop_discovery()
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISCOVERY_PORT) != OK:
		_listen = null


func stop_discovery() -> void:
	if _listen != null:
		_listen.close()
		_listen = null


func _poll_discovery() -> void:
	if _listen == null:
		return
	while _listen.get_available_packet_count() > 0:
		var msg := _listen.get_packet().get_string_from_utf8()
		var ip := _listen.get_packet_ip()
		var a := msg.find("[MOTD]")
		var b := msg.find("[/MOTD]")
		var c := msg.find("[AD]")
		var d := msg.find("[/AD]")
		if a < 0 or b < a or c < 0 or d < c:
			continue
		var p := int(msg.substr(c + 4, d - c - 4))
		discovered["%s:%d" % [ip, p]] = {"name": msg.substr(a + 6, b - a - 6), "ip": ip, "port": p, "t": Time.get_ticks_msec()}
	for k in discovered.keys():
		if Time.get_ticks_msec() - int(discovered[k]["t"]) > 5000:
			discovered.erase(k)


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_poll_discovery()
	if role == "" or world == null or not is_instance_valid(world) or world.cm == null:
		return
	if is_client():
		var send: Array = []
		_req_mx.lock()
		for rid in _reqs:
			var r: Dictionary = _reqs[rid]
			if not r["sent"]:
				r["sent"] = true
				send.append([rid, r["cx"], r["cz"]])
		_req_mx.unlock()
		for q in send:
			rpc_id(1, "_req_chunk", q[0], world.dimension, q[1], q[2])
		if _block_send.size() > 0:
			rpc_id(1, "_set_blocks", world.dimension, _block_send)
			_block_send = PackedInt32Array()
		_retry_blocks()
	elif _block_out.size() > 0:
		rpc("_blocks", world.dimension, _block_out)
		_block_out = PackedInt32Array()
	_send_t += delta
	if _send_t >= 0.05:
		_send_t = 0.0
		if world.player != null and world.spawn_ready:
			if is_client():
				rpc_id(1, "_pstate", _state_of_local())
			elif not players.is_empty():
				var all := {1: _state_of_local()}
				for id in players:
					var pl: Dictionary = players[id]
					var pp: Vector3 = pl["pos"]
					all[id] = [pl["name"], pp.x, pp.y, pp.z, pl["yaw"], pl["pitch"], pl["sneak"], pl["mode"], pl["dead"], pl["dim"]]
				rpc("_pstates", all)
				_send_entities()
	_slow_t += delta
	if _slow_t >= 1.0:
		_slow_t = 0.0
		if is_host():
			if not players.is_empty():
				rpc("_world_state", world.day_time, world.game_time, world.raining, world.thundering, world.difficulty)
			var centers: Array = []
			for px in proxies():
				centers.append(Vector2i(int(floor(px.pos.x)) >> 4, int(floor(px.pos.z)) >> 4))
			world.cm.extra_centers = centers
		world.cm.kick()
		_bcast_t += 1.0
		if _bcast != null and _bcast_t >= 1.5:
			_bcast_t = 0.0
			_bcast.put_packet(("[MOTD]%s - %s[/MOTD][AD]%d[/AD]" % [my_name, str(world.level.get("name", "World")), port]).to_utf8_buffer())
	if is_client():
		_pdata_t += delta
		if _pdata_t > 30.0:
			_pdata_t = 0.0
			client_save()
	_render_players()


# ------------------------------------------------------------------ integration test (two processes)

## --autoplay ... --nettest=host|client: host marks a block and waits for the client's block; client verifies the
## host's block (from modified chunk data), places its own, checks remote player + entity snapshots.
func run_test(w, which: String) -> void:
	var tree: SceneTree = w.get_tree()
	var t0 := Time.get_ticks_msec()
	while not w.spawn_ready and Time.get_ticks_msec() - t0 < 60000:
		await tree.process_frame
	var sp: Array = w.level.get("spawn", [0, 64, 0])
	var mark := Vector3i(int(sp[0]) + 2, int(sp[1]), int(sp[2]))
	if which == "host":
		print("NET-HOST ", host(w, 25599, "127.0.0.1"))
		w.set_block(mark.x, mark.y, mark.z, Res.blocks.state_of("gold_block", {}))
		w.entities.spawn_mob("pig", Vector3(mark) + Vector3(0.5, 1, 3.5))
		while Time.get_ticks_msec() - t0 < 90000:
			await tree.process_frame
			if test_log.size() >= 2:
				break
		print("NET-HOST players=%s log=%s" % [str(player_names()), str(test_log)])
	else:
		while Time.get_ticks_msec() - t0 < 60000 and (not w.cm.is_ready(mark.x, mark.z) or players.is_empty()):
			await tree.process_frame
		for i in 40:
			await tree.process_frame
		print("NET-CLIENT host block at mark: %s" % Res.blocks.name_of(maxi(w.state_at(mark.x, mark.y, mark.z), 0)))
		print("NET-CLIENT remote players: %s, puppets: %d" % [str(player_names()), puppets.size()])
		w.set_block(mark.x, mark.y + 1, mark.z, Res.blocks.state_of("diamond_block", {}))
		for e in puppets.values():
			if e.kind == "mob":
				w.entities.player_attack(e)
				break
		for i in 60:
			await tree.process_frame
	tree.quit()
