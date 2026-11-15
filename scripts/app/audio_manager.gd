## Audio (autoload) — sound events from the installed sounds.json resolved through the launcher's hashed
## objects store (never redistributed), bounded voice pools, per-category buses, subtitles, and a
## MusicScheduler (menu/game/creative/underwater/dimension contexts with randomized gaps, no overlap).
## Contract: play(event, pos, category, vol, pitch), play_ui(event), set_music_context(ctx), subtitles[].
## Invariants: a missing OGG never crashes (silently counted in `missing`); long tracks streamed from disk.
extends Node

const BUSES := ["Music", "Jukebox", "Weather", "Blocks", "Hostile", "Neutral", "Players", "Ambient", "Voice", "UI"]
const POOL_3D := 32
const POOL_2D := 8

var _cache: Dictionary = {}       # file path -> AudioStream
var _cache_order: Array = []
var _pool3: Array = []
var _pool2: Array = []
var _music: AudioStreamPlayer
var music_context := "menu"
var _music_timer := 2.0
var _music_event := ""
var missing := 0
var played := 0
var subtitles: Array = []         # [{text, pos, time}]
var listener_pos := Vector3.ZERO   # world coordinates (the camera)
var origin := Vector3.ZERO         # world -> scene offset (ChunkManager origin rebasing; the camera lives in scene space)
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 16.0
		p.unit_size = 4.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_pool2.append(p2)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_music.finished.connect(func(): _music_timer = _gap_for(music_context))
	Settings.changed.connect(_on_setting)
	apply_volumes()


func _on_setting(key: String) -> void:
	if key.begins_with("vol_"):
		apply_volumes()


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(Settings.get_v("vol_master")))))
	for b in BUSES:
		var key: String = "vol_" + str(b).to_lower()
		var v := float(Settings.get_v(key)) if Settings.SPEC.has(key) else 1.0
		if b == "Neutral":
			v = float(Settings.get_v("vol_neutral"))
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(b), linear_to_db(maxf(0.0001, v)))
		AudioServer.set_bus_mute(AudioServer.get_bus_index(b), v <= 0.001)


func _resolve(event: String) -> Dictionary:
	var e = Res.sounds_json.get(event.trim_prefix("minecraft:"))
	if not (e is Dictionary):
		return {}
	var list: Array = e.get("sounds", [])
	if list.is_empty():
		return {}
	var total := 0.0
	for s in list:
		total += float(s.get("weight", 1)) if s is Dictionary else 1.0
	var r := rng.randf() * total
	var pick = list[0]
	for s in list:
		r -= float(s.get("weight", 1)) if s is Dictionary else 1.0
		if r <= 0.0:
			pick = s
			break
	var d := {"name": "", "volume": 1.0, "pitch": 1.0, "stream": false, "subtitle": str(e.get("subtitle", "")), "dist": 16.0}
	if pick is String:
		d["name"] = pick
	else:
		if str(pick.get("type", "file")) == "event":
			return _resolve(str(pick.get("name", "")))
		d["name"] = str(pick.get("name", ""))
		d["volume"] = float(pick.get("volume", 1.0))
		d["pitch"] = float(pick.get("pitch", 1.0))
		d["stream"] = bool(pick.get("stream", false))
		d["dist"] = float(pick.get("attenuation_distance", 16))
	return d


func _stream_for(name: String) -> AudioStream:
	var vpath := "minecraft/sounds/" + name.trim_prefix("minecraft:") + ".ogg"
	if _cache.has(vpath):
		return _cache[vpath]
	var p := Res.sound_object_path(vpath)
	if p.is_empty():
		missing += 1
		return null
	var st := AudioStreamOggVorbis.load_from_file(p)
	if st == null:
		missing += 1
		return null
	_cache[vpath] = st
	_cache_order.append(vpath)
	if _cache_order.size() > 256:
		_cache.erase(_cache_order.pop_front())
	return st


func play(event: String, pos: Vector3, bus: String = "Blocks", volume: float = 1.0, pitch: float = 1.0) -> void:
	if Res.mode != "vanilla":
		return
	var d := _resolve(event)
	if d.is_empty():
		return
	# Java: a sound reaches a player only within its range (attenuation distance x max(volume, 1)) - culled here before
	# the file is loaded (distant mob ambience used to stall frames loading sounds nobody could hear)
	var rng_dist: float = float(d["dist"]) * maxf(1.0, volume)
	if listener_pos.distance_squared_to(pos) > rng_dist * rng_dist:
		return
	var st := _stream_for(d["name"])
	if st == null:
		return
	var best: AudioStreamPlayer3D = null
	for p in _pool3:
		if not p.playing:
			best = p
			break
	if best == null:
		best = _pool3[rng.randi() % _pool3.size()]
	best.stream = st
	best.bus = bus
	best.global_position = pos - origin
	# wiki: Sounds.json - range attenuation_distance (16) x max(volume, 1): a louder sound (thunder 10000, explosions 4)
	# carries proportionally farther instead of only being clamped to full volume
	best.max_distance = d["dist"] * maxf(1.0, volume)
	best.unit_size = 4.0 * maxf(1.0, volume)
	best.volume_db = linear_to_db(clampf(d["volume"] * volume, 0.0, 1.0))
	best.pitch_scale = clampf(d["pitch"] * pitch, 0.5, 2.0)
	best.play()
	played += 1
	if Settings.get_v("subtitles") and d["subtitle"] != "":
		var text := Res.tr_key(d["subtitle"])
		for s in subtitles:
			if s["text"] == text:
				subtitles.erase(s)
				break
		subtitles.append({"text": text, "pos": pos, "time": Time.get_ticks_msec()})
		if subtitles.size() > 8:
			subtitles.pop_front()


func play_ui(event: String, pitch: float = 1.0) -> void:
	if Res.mode != "vanilla":
		return
	var d := _resolve(event)
	if d.is_empty():
		return
	var st := _stream_for(d["name"])
	if st == null:
		return
	for p in _pool2:
		if not p.playing:
			p.stream = st
			p.bus = "UI"
			p.pitch_scale = d["pitch"] * pitch
			p.volume_db = linear_to_db(clampf(d["volume"], 0.0, 1.0))
			p.play()
			return


func set_music_context(ctx: String) -> void:
	if ctx == music_context:
		return
	var was_menu := music_context == "menu"
	music_context = ctx
	if was_menu != (ctx == "menu") and _music.playing:
		_music.stop()
		_music_timer = 3.0


## Gaps between tracks (seconds): menu 1..30 s (wiki: Music); in game the 26.3 minecraft:audio/background_music
## min_delay / max_delay of the dimension / biome: 12000..24000 ticks for game, creative, underwater, Nether and
## Overworld biome music (wiki: Music "10 to 20 minutes"), 6000..24000 ticks in the End.
func _gap_for(ctx: String) -> float:
	match ctx:
		"menu": return rng.randf_range(1.0, 30.0)
		"end", "music.end": return rng.randf_range(300.0, 1200.0)
	return rng.randf_range(600.0, 1200.0)


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	while not subtitles.is_empty() and now - int(subtitles[0]["time"]) > 3000:
		subtitles.pop_front()
	if Res.mode != "vanilla" or _music.playing:
		return
	_music_timer -= delta
	if _music_timer > 0.0:
		return
	var ev := "music.menu"
	match music_context:
		"game": ev = "music.game"
		"creative": ev = "music.creative"
		"underwater": ev = "music.under_water"
		"end": ev = "music.end"
		"nether": ev = "music.nether.nether_wastes"
	if music_context.begins_with("music."):
		ev = music_context
	var d := _resolve(ev)
	if d.is_empty():
		_music_timer = 30.0
		return
	var st := _stream_for(d["name"])
	if st == null:
		_music_timer = 30.0
		return
	_music_event = ev
	_music.stream = st
	_music.volume_db = linear_to_db(clampf(d["volume"], 0.0, 1.0))
	_music.play()


func now_playing() -> String:
	return _music_event if _music.playing else ""


func stop_music() -> void:
	_music.stop()
	_music_timer = _gap_for(music_context)


## Stops the positional sounds of a bus playing at a point (an ejected jukebox record).
func stop_at(pos: Vector3, bus: String) -> void:
	for p in _pool3:
		if p.playing and p.bus == bus and p.global_position.distance_to(pos) < 0.75:
			p.stop()
