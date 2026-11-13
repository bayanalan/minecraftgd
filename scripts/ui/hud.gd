## HUD — in-game overlay drawn with the user's imported HUD sprites (fallback shapes in placeholder mode):
## crosshair, hotbar + selection + item icons/counts/durability, hearts (hardcore/absorption/poison),
## food, armor, air bubbles, XP bar/level, offhand slot, chat log, subtitles, F3 debug overlay.
## Screens (inventory, pause...) are added as children of this CanvasLayer by WorldManager.open_screen.
extends CanvasLayer

var world
var canvas: Control
var chat: Array = []        # [text, time_ms]
var death_shown := false
var _dbg_timer := 0.0
var _dbg_text := ""
var toasts: Array = []      # [heading, title, icon id, start_ms]
var title_text := ""
var subtitle_text := ""
var actionbar_text := ""
var _last_health := 20
var _display_health := 20
var _last_health_ms := 0
var _blink_until := 0
var title_start := 0
var actionbar_start := 0
var title_times := [10, 70, 20]   # fade in, stay, fade out (ticks)


func _ready() -> void:
	layer = 5
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_hud)
	add_child(canvas)
	world.player.inventory.changed.connect(canvas.queue_redraw)


## /title: null leaves a field unchanged; title text restarts the fade timer.
func set_title(t, sub, bar) -> void:
	if t != null:
		title_text = str(t)
		title_start = Time.get_ticks_msec()
	if sub != null:
		subtitle_text = str(sub)
	if bar != null:
		actionbar_text = str(bar)
		actionbar_start = Time.get_ticks_msec()
	if t == "" and sub == "" and bar == "":
		title_text = ""
		subtitle_text = ""
		actionbar_text = ""


func _draw_titles(font: Font, size: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if title_text != "" or subtitle_text != "":
		var age := float(now - title_start) / 50.0
		var total := float(title_times[0] + title_times[1] + title_times[2])
		if age > total:
			title_text = ""
			subtitle_text = ""
		else:
			var al := clampf(minf(age / maxf(1.0, title_times[0]), (total - age) / maxf(1.0, title_times[2])), 0.0, 1.0)
			# Java Gui.renderTitle: title at 4x (top h/2 - 40), subtitle at 2x (top h/2 + 10), shadowed
			_shadow_text(font, Vector2(0, size.y / 2 - 40 + 28), title_text, size.x, 32, Color(1, 1, 1, al), 4.0)
			_shadow_text(font, Vector2(0, size.y / 2 + 10 + 14), subtitle_text, size.x, 16, Color(1, 1, 1, al), 2.0)
	# Java overlay message: 60 ticks, centred at h - 68 (text top h - 72), fading over the last 20 ticks
	if actionbar_text != "" and now - actionbar_start < 3000:
		var left := 3000.0 - float(now - actionbar_start)
		_shadow_text(font, Vector2(0, size.y - 72 + 7), actionbar_text, size.x, 8, Color(1, 1, 1, clampf(left / 1000.0, 0.0, 1.0)), 1.0)
	# boss bars (/bossbar)
	var by := 12.0
	var bars = world.level.get("bossbars", {})   # first bar at y 12, then every 19 px
	if bars is Dictionary:
		for id in bars:
			var b: Dictionary = bars[id]
			if not bool(b.get("visible", true)):
				continue
			var frac := clampf(float(b.get("value", 0)) / maxf(1.0, float(b.get("max", 100))), 0.0, 1.0)
			# Java BossHealthOverlay: boss_bar/<colour>_background + _progress (182 x 5) at y, name centred at y - 9
			var cname := str(b.get("color", "white"))
			var bx := floorf(size.x / 2 - 91)
			var bgs := UiKit.sprite("gui/sprites/boss_bar/%s_background" % cname)
			var pgs := UiKit.sprite("gui/sprites/boss_bar/%s_progress" % cname)
			if bgs != null:
				canvas.draw_texture_rect(bgs, Rect2(bx, by, 182, 5), false)
			if pgs != null and frac > 0.0:
				var pw := floorf(frac * 183.0)
				canvas.draw_texture_rect_region(pgs, Rect2(bx, by, minf(pw, 182), 5), Rect2(0, 0, minf(pw, 182) * pgs.get_width() / 182.0, pgs.get_height()))
			_shadow_text(font, Vector2(0, by - 9 + 7), str(b.get("name", id)), size.x, 8, Color.WHITE, 1.0)
			by += 19.0
	# scoreboard sidebar
	var sb = world.level.get("scoreboard", {})
	if sb is Dictionary and (sb.get("display", {}) as Dictionary).has("sidebar"):
		var obj := str(sb["display"]["sidebar"])
		var rows: Array = []
		for h in sb.get("scores", {}):
			if (sb["scores"][h] as Dictionary).has(obj):
				rows.append([str(h), int(sb["scores"][h][obj])])
		rows.sort_custom(func(x, y): return x[1] > y[1])
		rows = rows.slice(0, 15)
		var x0 := size.x - 100
		var y0 := size.y / 2 - rows.size() * 4.5
		var head := str((sb.get("objectives", {}) as Dictionary).get(obj, {}).get("display", obj))
		canvas.draw_rect(Rect2(x0 - 2, y0 - 10, 100, 10 + rows.size() * 9), Color(0, 0, 0, 0.35))
		canvas.draw_string(font, Vector2(x0, y0 - 2), head, HORIZONTAL_ALIGNMENT_CENTER, 96, 8, Color.WHITE)
		for i in rows.size():
			canvas.draw_string(font, Vector2(x0, y0 + 8 + i * 9), str(rows[i][0]), HORIZONTAL_ALIGNMENT_LEFT, 80, 8, Color(0.85, 0.85, 0.85))
			canvas.draw_string(font, Vector2(x0, y0 + 8 + i * 9), str(rows[i][1]), HORIZONTAL_ALIGNMENT_RIGHT, 96, 8, Color(1, 0.33, 0.33))


## Centred text with Java's drop shadow (offset 1 GUI px at scale k, colour * 0.25).
func _shadow_text(font: Font, base: Vector2, t: String, w: float, fs: int, col: Color, k: float) -> void:
	if t == "":
		return
	if Settings.get_v("text_shadow"):
		canvas.draw_string(font, base + Vector2(k, k), t, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, col.a))
	canvas.draw_string(font, base, t, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)


func toast(head: String, title: String, icon: String, head_color: Color = Color8(255, 255, 0)) -> void:
	toasts.append([head, title, icon, Time.get_ticks_msec(), head_color, false])
	Audio.play_ui("ui.toast.in")   # Toast.Visibility.SHOW


func _draw_toasts(font: Font, size: Vector2) -> void:
	var now := Time.get_ticks_msec()
	var y := 0.0
	for t in toasts.duplicate():
		# Java ToastManager: shown 5000 ms, then hidden; each change slides over 600 ms (f = t / 600, f * f)
		var age: int = now - int(t[3])
		if age > 5600:
			toasts.erase(t)
			continue
		var slide := 0.0
		if age < 5000:
			slide = clampf(age / 600.0, 0.0, 1.0)
			slide *= slide
		else:
			if not bool(t[5]):
				t[5] = true
				Audio.play_ui("ui.toast.out")
			var hf := clampf((age - 5000) / 600.0, 0.0, 1.0)
			slide = 1.0 - hf * hf
		var pos := Vector2(size.x - 160.0 * slide, y)
		var bg := UiKit.sprite("gui/sprites/toast/advancement")
		if bg != null:
			canvas.draw_texture_rect(bg, Rect2(pos, Vector2(160, 32)), false)
		else:
			canvas.draw_rect(Rect2(pos, Vector2(160, 32)), Color(0.13, 0.1, 0.15))
		var ic := ItemIcons.icon(Res.items.id(str(t[2]).trim_prefix("minecraft:")))
		if ic != null:
			canvas.draw_texture_rect(ic, Rect2(pos + Vector2(8, 8), Vector2(16, 16)), false)
		# Java AdvancementToast: header at (30, 7) 0xFFFF00 (challenges 0xFF88FF), title at (30, 18) white, no shadow
		canvas.draw_string(font, pos + Vector2(30, 7 + 7), str(t[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, t[4] if t.size() > 4 else Color8(255, 255, 0))
		canvas.draw_string(font, pos + Vector2(30, 18 + 7), str(t[1]), HORIZONTAL_ALIGNMENT_LEFT, 126, 8, Color.WHITE)
		y += 32.0


## click: a command a click on the message puts in the chat box (Java ClickEvent SUGGEST_COMMAND, e.g. /locate's
## green [x, ~, z] teleport coordinates).
func chat_message(t: String, click: String = "") -> void:
	# Java ChatComponent.addMessage: wrapped to the chat width (320) into separate lines at add time
	var now := Time.get_ticks_msec()
	for line in wrap_chat(t, chat_width()):
		chat.append([line, now, click])
	while chat.size() > 100:
		chat.pop_front()
	print("[chat] ", t)


static func wrap_chat(t: String, w: float) -> Array:
	var f := UiKit.font()
	var out: Array = []
	for para in t.split("\n"):
		var cur := ""
		for word in para.split(" "):
			var cand := word if cur == "" else cur + " " + word
			if cur != "" and f.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > w:
				out.append(cur)
				cur = word
			else:
				cur = cand
			# a single word wider than the chat breaks by characters
			while f.get_string_size(cur, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > w and cur.length() > 1:
				var k := cur.length() - 1
				while k > 1 and f.get_string_size(cur.substr(0, k), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > w:
					k -= 1
				out.append(cur.substr(0, k))
				cur = cur.substr(k)
		out.append(cur)
	return out


func _process(delta: float) -> void:
	canvas.queue_redraw()
	_dbg_timer -= delta
	if _dbg_timer <= 0.0 and world.show_debug:
		_dbg_timer = 0.25
		_dbg_text = _debug_text()


func _spr(path: String) -> Texture2D:
	return UiKit.sprite("gui/sprites/hud/" + path)


func _draw_hud() -> void:
	if world == null or world.player == null:
		return
	var s := UiKit.scale()
	var size := canvas.size / s
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var p: Player = world.player
	var font := UiKit.font()
	if not world.spawn_ready:
		_draw_loading(font, size)
		return
	if p.sleep_counter > 0:
		# Java Gui.renderSleepOverlay: 0x101020 fading in over 100 ticks (up to 220 alpha), out over 10 after waking
		var sf := float(p.sleep_counter) / 100.0
		if sf > 1.0:
			sf = 1.0 - float(p.sleep_counter - 100) / 10.0
		canvas.draw_rect(Rect2(Vector2.ZERO, size), Color8(16, 16, 32, int(220.0 * clampf(sf, 0.0, 1.0))))
	if world.hud_hidden:
		return
	if p.effects.has("darkness"):
		# Java Darkness: pulsing dimming of the view
		var pulse := 0.45 + 0.25 * sin(float(Time.get_ticks_msec()) / 700.0)
		canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, pulse))
	_draw_toasts(font, size)
	_draw_titles(font, size)
	if Settings.get_v("adv_coords") and not world.show_debug:
		# QoL coordinates (Bedrock-style position line)
		var fac: String = ["south", "west", "north", "east"][int(floor(fposmod(p.yaw, 360.0) / 90.0 + 0.5)) & 3]
		var ct := "XYZ: %d / %d / %d  (%s)" % [floori(p.pos.x), floori(p.pos.y), floori(p.pos.z), fac]
		var cw := font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		canvas.draw_rect(Rect2(1, 1, cw + 4, 10), Color(0, 0, 0, 0.35))
		canvas.draw_string(font, Vector2(3, 9), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	var cx := size.x / 2.0
	var by := size.y
	# crosshair
	if world.screen == null and world.third_person == 0:
		var ch := _spr("crosshair")
		if ch != null:
			canvas.draw_texture(ch, Vector2(cx - 7.5, size.y / 2 - 7.5))
		# Java Gui.renderCrosshair attack indicator (crosshair mode)
		if str(Settings.get_v("attack_indicator")) == "crosshair" and not p.is_spectator() and world.target != null:
			var af := p.attack_strength(0.0)
			var ay := floorf(size.y / 2.0) - 7.0 + 16.0
			var ax := floorf(cx) - 8.0
			var full := false
			if af >= 1.0 and world.target.has("entity") and world.target["entity"] != null and world.target["entity"].kind == "mob" and not world.target["entity"].dead:
				full = p.attack_delay() > 5.0
			if full:
				var fs := _spr("crosshair_attack_indicator_full")
				if fs != null:
					canvas.draw_texture(fs, Vector2(ax, ay))
			elif af < 1.0:
				var bgs := _spr("crosshair_attack_indicator_background")
				var pgs := _spr("crosshair_attack_indicator_progress")
				if bgs != null:
					canvas.draw_texture(bgs, Vector2(ax, ay))
				if pgs != null:
					var pw := int(af * 17.0)
					canvas.draw_texture_rect_region(pgs, Rect2(ax, ay, pw, 4), Rect2(0, 0, pw, 4))
		else:
			canvas.draw_rect(Rect2(cx - 0.5, size.y / 2 - 5, 1, 10), Color.WHITE)
			canvas.draw_rect(Rect2(cx - 5, size.y / 2 - 0.5, 10, 1), Color.WHITE)
	# Java GameRenderer.renderItemActivationAnimation (totem of undying): grow, spin, shrink over 40 ticks
	if p.totem_anim > 0:
		var tt := ItemIcons.icon(Res.items.id("totem_of_undying"))
		if tt != null:
			var fa := clampf((40.0 - float(p.totem_anim) + float(world.tick_accum) / 0.05) / 40.0, 0.0, 1.0)
			var g2 := fa * fa
			var h3 := fa * g2
			var jv := 10.25 * h3 * g2 - 24.95 * g2 * g2 + 25.5 * h3 - 13.8 * g2 + 4.0 * fa
			var kv := jv * PI
			var nsz := 50.0 + 175.0 * sin(kv)
			var sx := maxf(0.05, absf(cos(deg_to_rad(900.0 * absf(sin(kv))))))
			var tsz := Vector2(nsz * sx, nsz)
			canvas.draw_texture_rect(tt, Rect2(Vector2(cx, size.y / 2.0) - tsz / 2.0, tsz), false)
	# Java Gui.renderItemHotbar attack indicator (hotbar mode, right of the hotbar for a right-handed player)
	if str(Settings.get_v("attack_indicator")) == "hotbar" and not p.is_spectator() and world.screen == null:
		var hf := p.attack_strength(0.0)
		if hf < 1.0:
			var hx := floorf(cx) + 91.0 + 6.0
			var hy := size.y - 20.0
			var hb := _spr("hotbar_attack_indicator_background")
			var hp := _spr("hotbar_attack_indicator_progress")
			if hb != null:
				canvas.draw_texture(hb, Vector2(hx, hy))
			if hp != null:
				var ph := int(hf * 19.0)
				canvas.draw_texture_rect_region(hp, Rect2(hx, hy + 18 - ph, 18, ph), Rect2(0, 18 - ph, 18, ph))
	if p.is_spectator():
		_draw_chat(font, size)
		_draw_debug(font, size)
		return
	# hotbar
	var hb := _spr("hotbar")
	if hb != null:
		canvas.draw_texture(hb, Vector2(cx - 91, by - 22))
	else:
		canvas.draw_rect(Rect2(cx - 91, by - 22, 182, 22), Color(0, 0, 0, 0.5))
	var sel := _spr("hotbar_selection")
	var sx := cx - 91 - 1 + p.inventory.selected * 20
	if sel != null:
		canvas.draw_texture(sel, Vector2(sx, by - 23))
	else:
		canvas.draw_rect(Rect2(sx, by - 23, 24, 24), Color.WHITE, false, 1.0)
	for i in 9:
		_draw_stack(p.inventory.get_slot(i), Vector2(cx - 88 + i * 20, by - 19), font)
	var off := p.inventory.get_slot(Inventory.OFFHAND)
	if not off.is_empty():
		var ot := _spr("hotbar_offhand_left")
		if ot != null:
			canvas.draw_texture(ot, Vector2(cx - 91 - 29, by - 23))
		_draw_stack(off, Vector2(cx - 91 - 26, by - 19), font)
	if p.mode == Player.Mode.SURVIVAL or p.mode == Player.Mode.ADVENTURE:
		_draw_stats(p, cx, by, font)
	_draw_chat(font, size)
	_draw_subtitles(font, size)
	_draw_debug(font, size)


func _draw_stack(st: ItemStack, pos: Vector2, font: Font) -> void:
	if st == null or st.is_empty():
		return
	var ic := ItemIcons.icon_for(st)
	if ic != null:
		canvas.draw_texture_rect(ic, Rect2(pos, Vector2(16, 16)), false)
	if st.count > 1:
		var t := str(st.count)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		canvas.draw_string(font, pos + Vector2(17 - w + 1, 17 + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.25, 0.25, 0.25))
		canvas.draw_string(font, pos + Vector2(17 - w, 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	var md: int = Res.items.max_damage[st.item]
	if md > 0 and st.damage > 0:
		var f := 1.0 - float(st.damage) / md
		canvas.draw_rect(Rect2(pos + Vector2(2, 13), Vector2(13, 2)), Color.BLACK)
		canvas.draw_rect(Rect2(pos + Vector2(2, 13), Vector2(roundf(13 * f), 1)), Color.from_hsv(f / 3.0, 1, 1))


func _draw_stats(p: Player, cx: float, by: float, font: Font) -> void:
	var hc: bool = world.hardcore
	var pre := "hardcore_" if hc else ""
	var poison := p.effects.has("poison")
	var wither := p.effects.has("wither")
	var kind := "poisoned_" if poison else ("withered_" if wither else "")
	# Java Gui.renderPlayerHealth: health down -> blink 20 ticks, up -> 10 ticks (switching every 3); the hearts lost
	# since the display health (which lags 1 s) show white while blinking, under the current red ones
	var hp := int(ceil(p.health))
	var tick: int = world.game_time
	var now_ms := Time.get_ticks_msec()
	if hp < _last_health:
		_last_health_ms = now_ms
		_blink_until = tick + 20
	elif hp > _last_health:
		_last_health_ms = now_ms
		_blink_until = tick + 10
	if now_ms - _last_health_ms > 1000:
		_display_health = hp
		_last_health_ms = now_ms
	_last_health = hp
	var blink := _blink_until > tick and ((_blink_until - tick) / 3) % 2 == 1
	var cont := _spr(("heart/container_hardcore" if hc else "heart/container") + ("_blinking" if blink else ""))
	if cont == null:
		cont = _spr("heart/container_hardcore" if hc else "heart/container")
	var shake := p.health + p.absorption <= 4.0
	var shake_rng := RandomNumberGenerator.new()
	shake_rng.seed = tick * 312871
	var regen_heart := -1
	if p.effects.has("regeneration"):
		regen_heart = tick % int(ceil(20.0 + 5.0))
	for i in 10:
		var x := cx - 91 + i * 8
		var y := by - 39
		if shake:
			y += shake_rng.randi_range(0, 1)
		if i == regen_heart:
			y -= 2
		if cont != null:
			canvas.draw_texture(cont, Vector2(x, y))
		var u := i * 2
		if blink and u < _display_health:
			var half_b := u + 1 == _display_health
			_icon("heart/%s%s%s_blinking" % [kind, pre, "half" if half_b else "full"], Vector2(x, y), Color(1, 1, 1), 0.5 if half_b else 1.0)
		if u < hp:
			var half_n := u + 1 == hp
			_icon("heart/%s%s%s" % [kind, pre, "half" if half_n else "full"], Vector2(x, y), Color(0.9, 0.1, 0.1), 0.5 if half_n else 1.0)
	if p.absorption > 0:
		var ab := int(ceil(p.absorption))
		for i in ceili(ab / 2.0):
			var x2 := cx - 91 + (i % 10) * 8
			var y2 := by - 49 - (i / 10) * 10
			_icon("heart/absorbing_full" if ab - i * 2 >= 2 else "heart/absorbing_half", Vector2(x2, y2), Color(1, 0.85, 0.1))
	# armor
	var ar := p.inventory.armor_points()
	if ar > 0:
		for i in 10:
			var x3 := cx - 91 + i * 8
			var v3 := ar - i * 2
			_icon("armor_full" if v3 >= 2 else ("armor_half" if v3 == 1 else "armor_empty"), Vector2(x3, by - 49), Color(0.8, 0.8, 0.8), 1.0 if v3 >= 2 else (0.5 if v3 == 1 else 0.15))
	# food
	var hunger := p.effects.has("hunger")
	for i in 10:
		var x4 := cx + 91 - 9 - i * 8
		var y4 := by - 39
		if p.saturation <= 0.0 and world.game_time % (p.food * 3 + 1) == 0:
			y4 += randi_range(-1, 1)
		_icon("food_empty" + ("_hunger" if hunger else ""), Vector2(x4, y4), Color(0.3, 0.2, 0.1))
		var v4 := p.food - i * 2
		if v4 >= 2:
			_icon("food_full" + ("_hunger" if hunger else ""), Vector2(x4, y4), Color(0.75, 0.45, 0.2))
		elif v4 == 1:
			_icon("food_half" + ("_hunger" if hunger else ""), Vector2(x4, y4), Color(0.75, 0.45, 0.2), 0.5)
	# air
	if p.eyes_in_water or p.air < 300:
		var bubbles := int(ceil(float(maxi(p.air, 0) - 2) * 10.0 / 300.0))
		var pops := int(ceil(float(maxi(p.air, 0)) * 10.0 / 300.0)) - bubbles
		for i in bubbles + pops:
			_icon("air" if i < bubbles else "air_bursting", Vector2(cx + 91 - 9 - i * 8, by - 49), Color(0.6, 0.8, 1.0))
	# xp
	var bg := _spr("experience_bar_background")
	var pr := _spr("experience_bar_progress")
	if bg != null:
		canvas.draw_texture(bg, Vector2(cx - 91, by - 29))
		if pr != null:
			canvas.draw_texture_rect_region(pr, Rect2(cx - 91, by - 29, int(182 * p.xp_progress), 5), Rect2(0, 0, int(182 * p.xp_progress), 5))
	else:
		canvas.draw_rect(Rect2(cx - 91, by - 29, 182, 5), Color(0, 0, 0, 0.6))
		canvas.draw_rect(Rect2(cx - 91, by - 29, 182 * p.xp_progress, 5), Color(0.5, 1.0, 0.2))
	if p.xp_level > 0:
		var t := str(p.xp_level)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		for o in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			canvas.draw_string(font, Vector2(cx - w / 2, by - 31) + o, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.BLACK)
		canvas.draw_string(font, Vector2(cx - w / 2, by - 31), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 1.0, 0.13))


func _icon(path: String, pos: Vector2, fallback: Color, frac: float = 1.0) -> void:
	var t := _spr(path)
	if t != null:
		canvas.draw_texture(t, pos)
	else:
		canvas.draw_rect(Rect2(pos + Vector2(1, 1), Vector2(7 * frac, 7)), fallback)


## Java ChatComponent (default chat settings): width 320, lines 9 px stacked up from y = h - 40, background
## x 0 .. width + 8 at 50 % opacity, text at x 4 with shadow; unfocused lines live 200 ticks and fade with
## clamp((1 - age / 200) * 10, 0, 1)^2, at most 10 lines (90 px); focused (chat open): all lines, 20 (180 px).
## Chat settings (Java ChatComponent): width floor(w * 280 + 40), height floor(h * 160 + 20) (focused / unfocused),
## line height 9 * (spacing + 1), text alpha fade * (opacity * 0.9 + 0.1), background alpha fade * bg opacity,
## text size scales the whole chat; visibility Shown / Commands Only (system lines) / Hidden.
static func chat_width() -> float:
	return floorf(float(Settings.get_v("chat_width")) * 280.0 + 40.0)


var _chat_hits: Array = []   # [rect (chat px), click command, chat scale] of clickable lines drawn this frame


## Java ChatScreen.mouseClicked on a component with a SUGGEST_COMMAND click event: its command, or "".
func chat_click_at(screen_pos: Vector2) -> String:
	for h in _chat_hits:
		var r: Rect2 = h[0]
		var sc: float = float(h[2]) * float(UiKit.scale())
		if r.has_point(screen_pos / sc):
			return str(h[1])
	return ""


func _draw_chat(font: Font, size: Vector2) -> void:
	_chat_hits.clear()
	var vis := str(Settings.get_v("chat_visibility"))
	if vis == "hidden":
		return
	var now := Time.get_ticks_msec()
	var open: bool = world.screen != null and world.screen.has_method("is_chat")
	var k := float(Settings.get_v("chat_scale"))
	if k <= 0.0:
		return
	var w := chat_width()
	var lh := 9.0 * (float(Settings.get_v("chat_line_spacing")) + 1.0)
	var hpx := floorf(float(Settings.get_v("chat_height_focused" if open else "chat_height_unfocused")) * 160.0 + 20.0)
	var max_lines := maxi(1, int(hpx / lh))
	var t_op := float(Settings.get_v("chat_opacity")) * 0.9 + 0.1
	var b_op := float(Settings.get_v("text_bg_opacity"))
	var bottom := (size.y - 40.0) / k
	var n := 0
	var shadow: bool = Settings.get_v("text_shadow")
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k) * float(UiKit.scale()))
	for i in range(chat.size() - 1, -1, -1):
		var line := str(chat[i][0])
		if vis == "system" and line.begins_with("<"):
			continue   # Commands Only: player chat hidden
		var age_t := float(now - int(chat[i][1])) / 50.0
		if not open and age_t >= 200.0:
			break
		var a := 1.0
		if not open:
			a = clampf((1.0 - age_t / 200.0) * 10.0, 0.0, 1.0)
			a *= a
		var top := bottom - lh * (n + 1)
		canvas.draw_rect(Rect2(0, top, w + 8, lh), Color(0, 0, 0, b_op * a))
		var ty := top + (lh - 9.0) / 2.0 + 1.0 + 7.0
		var click := str(chat[i][2]) if (chat[i] as Array).size() > 2 else ""
		if click != "" and line.contains("[") and line.contains("]"):
			# the bracketed part is the green clickable component
			var i0 := line.find("[")
			var i1 := line.find("]", i0) + 1
			var parts := [[line.substr(0, i0), Color(1, 1, 1)], [line.substr(i0, i1 - i0), Color8(0x55, 0xFF, 0x55)], [line.substr(i1), Color(1, 1, 1)]]
			var x := 4.0
			for pt in parts:
				var col: Color = pt[1]
				if shadow:
					canvas.draw_string(font, Vector2(x + 1, ty + 1), str(pt[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, a * t_op))
				canvas.draw_string(font, Vector2(x, ty), str(pt[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(col.r, col.g, col.b, a * t_op))
				x += font.get_string_size(str(pt[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			if open:
				_chat_hits.append([Rect2(0, top, w + 8, lh), click, k])
		else:
			if shadow:
				canvas.draw_string(font, Vector2(5, ty + 1), line, HORIZONTAL_ALIGNMENT_LEFT, w, 8, Color(0.25, 0.25, 0.25, a * t_op))
			canvas.draw_string(font, Vector2(4, ty), line, HORIZONTAL_ALIGNMENT_LEFT, w, 8, Color(1, 1, 1, a * t_op))
		n += 1
		if n >= max_lines:
			break
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * float(UiKit.scale()))


func _draw_subtitles(font: Font, size: Vector2) -> void:
	if not Settings.get_v("subtitles"):
		return
	var y := size.y - 40
	var p: Player = world.player
	for sub in Audio.subtitles:
		var d: Vector3 = sub["pos"] - p.eye_pos()
		var right := Vector3(cos(deg_to_rad(p.yaw)), 0, sin(deg_to_rad(p.yaw)))
		var side := d.normalized().dot(right)
		var t: String = ("< " if side > 0.3 else "  ") + str(sub["text"]) + (" >" if side < -0.3 else "  ")
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		canvas.draw_rect(Rect2(size.x - w - 6, y - 8, w + 4, 10), Color(0, 0, 0, 0.6))
		canvas.draw_string(font, Vector2(size.x - w - 4, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
		y -= 10


func _draw_debug(font: Font, _size: Vector2) -> void:
	if not world.show_debug and not Settings.get_v("debug_metrics"):
		return
	if _dbg_text == "":
		_dbg_text = _debug_text()
	var y := 10.0
	for line in _dbg_text.split("\n"):
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		canvas.draw_rect(Rect2(1, y - 8, w + 2, 9), Color(0.31, 0.31, 0.31, 0.56))
		canvas.draw_string(font, Vector2(2, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.88, 0.88, 0.88))
		y += 9


func _debug_text() -> String:
	var p: Player = world.player
	var cm: ChunkManager = world.cm
	var bx := int(floor(p.pos.x))
	var by := int(floor(p.pos.y))
	var bz := int(floor(p.pos.z))
	var c := cm.get_chunk(bx >> 4, bz >> 4)
	var bio := "?"
	if c != null:
		bio = "minecraft:" + world.biomes.names[c.biome_at(bx & 15, by, bz & 15)]
	var lt := cm.get_light(bx, by, bz)
	var fps := Engine.get_frames_per_second()
	var ft: PackedFloat32Array = world.fps_samples.duplicate()
	ft.sort()
	var p95: float = ft[int(ft.size() * 0.95)] * 1000.0 if ft.size() > 10 else 0.0
	var lines := PackedStringArray()
	lines.append("Recraft (assets %s %s)  Godot %s" % [Res.mode, Res.version, Engine.get_version_info()["string"]])
	lines.append("%d fps (p95 %.1f ms)  T: %s  vsync %s" % [fps, p95, str(Settings.get_v("max_fps")), Settings.get_v("vsync")])
	lines.append("Tick %.2f ms  game time %d  day %d  %s" % [world.tick_ms, world.game_time, world.day_time, "raining" if world.raining else "clear"])
	lines.append("C: %d loaded, %d jobs, gen %.1f ms, light %.1f ms, mesh %.1f ms" % [cm.chunks.size(), cm.pending_jobs(), cm.stats["gen_ms"], cm.stats["light_ms"], cm.stats["mesh_ms"]])
	lines.append("Meshes: %d groups, %d uploads, %d verts total" % [cm.visible_groups(), cm.stats["uploaded"], cm.stats["verts"]])
	lines.append("Draw calls: %d  Objects: %d  Prims: %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	lines.append("Mem: %.0f MB static, VRAM %.0f MB" % [OS.get_static_memory_usage() / 1048576.0, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
	lines.append("E: %d entities" % world.entities.ents.size())
	lines.append("")
	lines.append("XYZ: %.3f / %.5f / %.3f" % [p.pos.x, p.pos.y, p.pos.z])
	lines.append("Block: %d %d %d  Chunk: %d %d %d in %d %d %d" % [bx, by, bz, bx & 15, by & 15, bz & 15, bx >> 4, by >> 4, bz >> 4])
	lines.append("Facing: %s (yaw %.1f / pitch %.1f)" % [Interaction.horizontal_facing(p.yaw), p.yaw, p.pitch])
	lines.append("Light: %d (%d sky, %d block)  sky factor %.2f" % [maxi(lt >> 4, lt & 15), lt >> 4, lt & 15, world.sky_darken()])
	lines.append("Biome: %s" % bio)
	lines.append("Generator: %s (seed %d)" % [world.gen.generator_id, world.gen.seed])
	lines.append("Mode: %s%s  speed %.3f b/t" % [["Survival", "Creative", "Adventure", "Spectator"][p.mode], " HARDCORE" if world.hardcore else "", Vector2(p.pos.x - p.prev_pos.x, p.pos.z - p.prev_pos.z).length()])
	lines.append("Music: %s  sounds played %d missing %d" % [Audio.now_playing(), Audio.played, Audio.missing])
	if not world.target.is_empty() and world.target.has("state"):
		var tp: Vector3i = world.target["pos"]
		lines.append("Targeted Block: %d, %d, %d  %s" % [tp.x, tp.y, tp.z, Res.blocks.state_string(int(world.target["state"]))])
	return "\n".join(lines)


## Java LevelLoadingScreen while the area around the player loads (WorldManager preload): menu background, progress
## percentage at (C, H/2 - 4 - 30), chunk status map below (2 GUI px per chunk) in Java's ChunkStatus colours
## (EMPTY 0x545454, SURFACE 0x726809, FEATURES 0x21C600, INITIALIZE_LIGHT 0xCCCCCC, LIGHT 0xFFE0A0, FULL white).
const LOAD_R := 5
func _draw_loading(font: Font, size: Vector2) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color8(16, 16, 16))
	var bg := UiKit.sprite("gui/menu_background")
	if bg != null:
		canvas.draw_texture_rect(bg, Rect2(Vector2.ZERO, size), true, Color(1, 1, 1, 1))
	var cm = world.cm
	var p: Player = world.player
	var pcx := int(floor(p.pos.x)) >> 4
	var pcz := int(floor(p.pos.z)) >> 4
	var pr := mini(int(world.PRELOAD_R), int(Settings.get_v("render_distance")))
	var done := 0.0
	var cnt := 0
	var d := 2 * LOAD_R + 1
	var x0 := floorf(size.x / 2.0) - float(d)   # 2 px per chunk, map centred at (C, H/2 + 30)
	var y0 := floorf(size.y / 2.0) + 30.0 - float(d)
	for dz in range(-LOAD_R, LOAD_R + 1):
		for dx in range(-LOAD_R, LOAD_R + 1):
			var c: Chunk = cm.get_chunk(pcx + dx, pcz + dz) if cm != null else null
			var col := Color8(0x54, 0x54, 0x54)
			var f := 0.0
			if c != null:
				if cm.is_visible_chunk(c):
					col = Color8(255, 255, 255)
					f = 1.0
				elif c.light_valid:
					col = Color8(0xFF, 0xE0, 0xA0)
					f = 0.85
				elif c.state >= Chunk.DECORATED:
					col = Color8(0xCC, 0xCC, 0xCC)
					f = 0.7
				elif c.features_ready:
					col = Color8(0x21, 0xC6, 0x00)
					f = 0.55
				elif c.state >= Chunk.DATA_READY:
					col = Color8(0x72, 0x68, 0x09)
					f = 0.4
			canvas.draw_rect(Rect2(x0 + (dx + LOAD_R) * 2, y0 + (dz + LOAD_R) * 2, 2, 2), col)
			if absi(dx) <= pr and absi(dz) <= pr:
				done += f
				cnt += 1
	var pct := clampi(int(floor(done / maxf(1.0, float(cnt)) * 100.0)), 0, 100)
	var t := Res.tr_fmt("loading.progress", [pct], "%s%%")
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var ty := floorf(size.y / 2.0) - 4.0 - 30.0
	if Settings.get_v("text_shadow"):
		canvas.draw_string(font, Vector2(floorf(size.x / 2.0 - tw / 2.0) + 1, ty + 7 + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(63, 63, 63))
	canvas.draw_string(font, Vector2(floorf(size.x / 2.0 - tw / 2.0), ty + 7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1))
	canvas.queue_redraw()
