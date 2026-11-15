## Ambience — the 26.3 data-driven ambient sounds and background music (environment attributes
## minecraft:audio/ambient_sounds and minecraft:audio/background_music: the player's biome, else the dimension type):
## - mood (wiki Ambience): every tick one random block within 17 x 17 x 17 of the eyes (block_search_extent 8); sky light
##   there lowers the mood by sky / 1000, else block light b changes it by -(b - 1) / tick_delay (6000: complete darkness
##   reaches 100 % in 5 minutes); at 100 % the mood sound (overworld / End: ambient.cave; Nether biomes their own) plays
##   `offset` (2) blocks beyond that block as seen from the player and the mood restarts at 0
## - biome loop (Nether biomes) fading in / out over 40 ticks when it changes, additions at their tick_chance per tick
## - underwater (wiki Ambience: while the head is under water, any dimension): ambient.underwater.enter / exit, the
##   ambient.underwater.loop (fading over 40 ticks), loop additions / rare / ultra rare in a 90 : 9 : 1 ratio (1 % of the
##   ticks: Java's rate, the wiki gives only the ratio)
## - background music: the biome's (else the dimension's) background_music entry - "underwater" while the head is under
##   water, "creative" in Creative when present, else "default"; replace_current_music (the End) cuts a different track
## Cheap per tick: one light lookup + a random roll; the biome / attribute lookup runs every 20 ticks.
## Contract: tick(world) once per game tick (main thread); reset() when a world closes.
class_name Ambience

const FADE := 40   # loop fade ticks (Java ambient loop instances; not on the wiki)

static var mood := 0.0
static var _t := 0
static var _amb = null             # current ambient_sounds settings (Dictionary or null)
static var _cache: Dictionary = {} # biome index -> [ambient_sounds, background_music]
static var _loop: AudioStreamPlayer
static var _loop_ev := ""
static var _loop_want := ""
static var _loop_fade := 0
static var _loop_vol := 1.0
static var _uw: AudioStreamPlayer
static var _uw_fade := 0
static var _uw_vol := 0.65
static var _was_uw := false
static var _rng := RandomNumberGenerator.new()


static func reset() -> void:
	mood = 0.0
	_t = 0
	_amb = null
	_cache.clear()
	_loop_want = ""
	_loop_fade = 0
	_uw_fade = 0
	_was_uw = false
	for pl in [_loop, _uw]:
		if pl != null and is_instance_valid(pl):
			pl.stop()


static func tick(world) -> void:
	if Res.mode != "vanilla" or world.player == null:
		return
	var p: Player = world.player
	_t += 1
	if _t % 20 == 1:
		_refresh(world, p)
	_underwater(p)
	_biome_loop()
	var amb = _amb
	if amb is Dictionary:
		var add = (amb as Dictionary).get("additions")
		if add is Dictionary and _rng.randf() < float((add as Dictionary).get("tick_chance", 0.0)):
			Audio.play(_ev(add.get("sound", "")), Audio.listener_pos, "Ambient")
		var md = (amb as Dictionary).get("mood")
		if md is Dictionary:
			_mood(world, p, md)


static func _ev(s) -> String:
	return str(s).trim_prefix("minecraft:") if s is String else ""


## Biome attribute (else the dimension type's) for the player's position; refreshes the loop / music choice.
static func _refresh(world, p: Player) -> void:
	var bio: int = world._player_biome()
	var ent = _cache.get(bio)
	if ent == null:
		var amb = null
		var mus = null
		var reg = world.biomes
		if reg != null and bio >= 0 and bio < reg.data.size() and reg.data[bio] is Dictionary:
			var at = (reg.data[bio] as Dictionary).get("attributes")
			if at is Dictionary:
				amb = (at as Dictionary).get("minecraft:audio/ambient_sounds")
				mus = (at as Dictionary).get("minecraft:audio/background_music")
		var dt = world.dim_type.get("attributes") if world.dim_type is Dictionary else null
		if dt is Dictionary:
			if not (amb is Dictionary):
				amb = (dt as Dictionary).get("minecraft:audio/ambient_sounds")
			if not (mus is Dictionary):
				mus = (dt as Dictionary).get("minecraft:audio/background_music")
		ent = [amb if amb is Dictionary else null, mus if mus is Dictionary else null]
		_cache[bio] = ent
	_amb = ent[0]
	_loop_want = _ev((_amb as Dictionary).get("loop", "")) if _amb is Dictionary else ""
	var mus2 = ent[1]
	if mus2 is Dictionary:
		var m: Dictionary = mus2
		var key := "default"
		if p.eyes_in_water and m.has("underwater"):
			key = "underwater"
		elif p.is_creative() and m.has("creative"):
			key = "creative"
		var e = m.get(key, m.get("default"))
		if e is Dictionary:
			var ev := _ev((e as Dictionary).get("sound", ""))
			if ev != "":
				Audio.set_music_context(ev if ev.begins_with("music.") else "music." + ev)
				var cur := Audio.now_playing()
				if bool((e as Dictionary).get("replace_current_music", false)) and cur != "" and cur != Audio.music_context:
					Audio.stop_music()


static func _player(vol_bus: String) -> AudioStreamPlayer:
	var pl := AudioStreamPlayer.new()
	pl.bus = vol_bus
	Audio.add_child(pl)
	return pl


static func _start(pl: AudioStreamPlayer, ev: String) -> float:
	var d: Dictionary = Audio._resolve(ev)
	if d.is_empty():
		return 0.0
	var st = Audio._stream_for(d["name"])
	if st == null:
		return 0.0
	if st is AudioStreamOggVorbis:
		st = (st as AudioStreamOggVorbis).duplicate()
		(st as AudioStreamOggVorbis).loop = true
	pl.stream = st
	pl.pitch_scale = clampf(float(d["pitch"]), 0.5, 2.0)
	pl.volume_db = -80.0
	pl.play()
	return float(d["volume"])


static func _underwater(p: Player) -> void:
	var uw := p.eyes_in_water
	if uw != _was_uw:
		_was_uw = uw
		Audio.play("ambient.underwater.enter" if uw else "ambient.underwater.exit", Audio.listener_pos, "Ambient")
	if uw:
		if _uw == null or not is_instance_valid(_uw):
			_uw = _player("Ambient")
		if not _uw.playing:
			_uw_vol = _start(_uw, "ambient.underwater.loop")
		_uw_fade = mini(FADE, _uw_fade + 1)
		var r := _rng.randf()
		if r < 0.0001:
			Audio.play("ambient.underwater.loop.additions.ultra_rare", Audio.listener_pos, "Ambient")
		elif r < 0.001:
			Audio.play("ambient.underwater.loop.additions.rare", Audio.listener_pos, "Ambient")
		elif r < 0.01:
			Audio.play("ambient.underwater.loop.additions", Audio.listener_pos, "Ambient")
	elif _uw_fade > 0:
		_uw_fade -= 1
	if _uw != null and is_instance_valid(_uw) and _uw.playing:
		if _uw_fade <= 0:
			_uw.stop()
		else:
			_uw.volume_db = linear_to_db(maxf(0.0001, _uw_vol * float(_uw_fade) / FADE))


static func _biome_loop() -> void:
	if _loop_ev != _loop_want:
		if _loop_fade > 0 and _loop != null and is_instance_valid(_loop) and _loop.playing:
			_loop_fade -= 1   # the old loop fades out first
		else:
			_loop_ev = _loop_want
			_loop_fade = 0
			if _loop != null and is_instance_valid(_loop):
				_loop.stop()
			if _loop_ev != "":
				if _loop == null or not is_instance_valid(_loop):
					_loop = _player("Ambient")
				_loop_vol = _start(_loop, _loop_ev)
	elif _loop_ev != "":
		_loop_fade = mini(FADE, _loop_fade + 1)
	if _loop != null and is_instance_valid(_loop) and _loop.playing:
		_loop.volume_db = linear_to_db(maxf(0.0001, _loop_vol * float(_loop_fade) / FADE))


static func _mood(world, p: Player, md: Dictionary) -> void:
	var ext := int(md.get("block_search_extent", 8))
	var delay := maxf(1.0, float(md.get("tick_delay", 6000)))
	var eye := p.eye_pos()
	var q := Vector3i(floori(eye.x) + _rng.randi_range(-ext, ext), floori(eye.y) + _rng.randi_range(-ext, ext), floori(eye.z) + _rng.randi_range(-ext, ext))
	if q.y < Coords.MIN_Y or q.y >= Coords.MAX_Y or not world.cm.is_ready(q.x, q.z):
		return
	var l: int = world.cm.get_light(q.x, q.y, q.z)
	var sky := l >> 4
	if sky > 0:
		mood -= float(sky) / 1000.0
	else:
		mood -= float((l & 15) - 1) / delay
	if mood >= 1.0:
		var c := Vector3(q) + Vector3(0.5, 0.5, 0.5)
		var dv := c - eye
		var dist := dv.length()
		var at := eye + (dv / dist * (dist + float(md.get("offset", 2.0))) if dist > 0.001 else Vector3.ZERO)
		Audio.play(_ev(md.get("sound", "")), at, "Ambient")
		mood = 0.0
	else:
		mood = maxf(mood, 0.0)
