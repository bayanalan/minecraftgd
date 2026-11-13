## WorkstationScreen — enchanting table, anvil, grindstone, smithing table, stonecutter and loom using the user's
## gui/container/*.png backgrounds and Java slot coordinates. Inputs are returned to the player on close.
## Logic: Enchanting (data-driven enchantments), Crafting.stonecutting.
extends ContainerUI

var kind := "enchanting_table"
var pos := Vector3i.ZERO
var inp: Array = []            # input stacks
var result: ItemStack = ItemStack.new()
var cost := 0
var use_right := 0
var ench_costs := [0, 0, 0]
var ench_hint: Array = ["", "", ""]
var stone_choices: Array = []  # [result name, count]
var stone_sel := -1
var name_edit: LineEdit
var loom_list: Array = []       # selectable pattern ids (Java LoomMenu.selectablePatterns)
var loom_sel := -1
var loom_row := 0                # first visible row of the 4x4 pattern grid
var carto_mode := ""             # cartography table result: scale / lock / copy


func build() -> void:
	Enchanting.load_all()
	inp.clear()
	for i in 3:
		inp.append(ItemStack.new())
	bg_size = Vector2(176, 166)
	match kind:
		"enchanting_table":
			bg_tex = UiKit.sprite("gui/container/enchanting_table")
			title = "Enchant"
			add_slot(Vector2(15, 47), _g.bind(0), _s.bind(0), 0)
			add_slot(Vector2(35, 47), _g.bind(1), _s.bind(1), 0, false, func(st): return st.name() == "lapis_lazuli", "lapis_lazuli")
			extra_draw = _draw_enchant
		"anvil":
			bg_tex = UiKit.sprite("gui/container/anvil")
			title = Res.tr_key("container.repair", "Repair & Name")
			title_pos = Vector2(60, 6)   # Java AnvilScreen titleLabelX
			add_slot(Vector2(27, 47), _g.bind(0), _s.bind(0), 0)
			add_slot(Vector2(76, 47), _g.bind(1), _s.bind(1), 0)
			add_slot(Vector2(134, 47), func(): return result, func(_s): pass, 0, true)
			name_edit = LineEdit.new()
			name_edit.max_length = 50
			name_edit.flat = true
			# Java AnvilScreen EditBox: unbordered, white text (the field look is the text_field sprite drawn in renderBg)
			for st in ["normal", "focus", "read_only"]:
				name_edit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			name_edit.add_theme_color_override("font_color", Color(1, 1, 1))
			name_edit.add_theme_color_override("font_uneditable_color", Color(1, 1, 1))
			name_edit.add_theme_color_override("caret_color", Color(1, 1, 1))
			name_edit.text_changed.connect(func(_t): on_changed())
			add_child(name_edit)
			extra_draw = _draw_anvil
		"grindstone":
			bg_tex = UiKit.sprite("gui/container/grindstone")
			title = Res.tr_key("container.grindstone_title", "Repair & Disenchant")
			add_slot(Vector2(49, 19), _g.bind(0), _s.bind(0), 0)
			add_slot(Vector2(49, 40), _g.bind(1), _s.bind(1), 0)
			add_slot(Vector2(129, 34), func(): return result, func(_s): pass, 0, true)
		"smithing_table":
			bg_tex = UiKit.sprite("gui/container/smithing")
			title = Res.tr_key("container.upgrade", "Upgrade Gear")
			title_pos = Vector2(44, 15)   # Java SmithingScreen titleLabelX / Y
			add_slot(Vector2(8, 48), _g.bind(0), _s.bind(0), 0)
			add_slot(Vector2(26, 48), _g.bind(1), _s.bind(1), 0)
			add_slot(Vector2(44, 48), _g.bind(2), _s.bind(2), 0)
			add_slot(Vector2(98, 48), func(): return result, func(_s): pass, 0, true)
		"loom":
			bg_tex = UiKit.sprite("gui/container/loom")
			title = Res.tr_key("container.loom", "Loom")
			add_slot(Vector2(13, 26), _g.bind(0), _s.bind(0), 0, false, func(st): return st.name().ends_with("_banner"), "banner")
			add_slot(Vector2(33, 26), _g.bind(1), _s.bind(1), 0, false, func(st): return st.name().ends_with("_dye"), "dye")
			add_slot(Vector2(23, 45), _g.bind(2), _s.bind(2), 0, false, func(st): return st.name().ends_with("_banner_pattern"), "banner_pattern")
			add_slot(Vector2(143, 57), func(): return result, func(_s): pass, 0, true)
			extra_draw = _draw_loom
		"cartography_table":
			# Java CartographyTableMenu / Screen: map (15, 15), paper / map / glass pane (15, 52), result (145, 39)
			bg_tex = UiKit.sprite("gui/container/cartography_table")
			title = Res.tr_key("container.cartography_table", "Cartography Table")
			add_slot(Vector2(15, 15), _g.bind(0), _s.bind(0), 0, false, func(st): return st.name() == "filled_map")
			add_slot(Vector2(15, 52), _g.bind(1), _s.bind(1), 0, false, func(st): return st.name() in ["paper", "map", "glass_pane"])
			add_slot(Vector2(145, 39), func(): return result, func(_s): pass, 0, true)
			extra_draw = _draw_cartography
		"stonecutter":
			bg_tex = UiKit.sprite("gui/container/stonecutter")
			title = "Stonecutter"
			add_slot(Vector2(20, 33), _g.bind(0), _s.bind(0), 0)
			add_slot(Vector2(143, 33), func(): return result, func(_s): pass, 0, true)
			extra_draw = _draw_stonecutter
	add_player_inventory(8, 84)
	on_changed()


func _g(i: int) -> ItemStack:
	return inp[i]


func _s(s: ItemStack, i: int) -> void:
	inp[i] = s
	on_changed()


func _process(d: float) -> void:
	super._process(d)
	if name_edit != null:
		var s := UiKit.scale()
		name_edit.position = (origin() + Vector2(62, 24)) * s
		name_edit.size = Vector2(103, 12) * s
		name_edit.add_theme_font_size_override("font_size", int(8 * s))


func on_changed() -> void:
	var p: Player = world.player
	result = ItemStack.new()
	cost = 0
	if name_edit != null:
		name_edit.editable = inp.size() > 0 and inp[0] != null and not (inp[0] as ItemStack).is_empty()
	match kind:
		"enchanting_table":
			var it: ItemStack = inp[0]
			ench_costs = [0, 0, 0]
			ench_hint = ["", "", ""]
			if not it.is_empty() and Enchanting.get_enchants(it).is_empty() and it.count == 1:
				var shelves := Enchanting.bookshelves(world, pos)
				ench_costs = Enchanting.costs(p.enchant_seed, shelves, it.name())
				for i in 3:
					if ench_costs[i] > 0:
						var sel := Enchanting.select(p.enchant_seed, i, it.name(), ench_costs[i])
						if not sel.is_empty():
							ench_hint[i] = "%s %s . . . ?" % [Enchanting.name_of(sel[0][0]), Enchanting.roman(sel[0][1])]
						else:
							ench_costs[i] = 0
		"anvil":
			var r := Enchanting.anvil(inp[0], inp[1], name_edit.text if name_edit != null else "")
			if not r.is_empty():
				result = r["result"]
				cost = r["cost"]
				use_right = r["use_right"]
				if cost >= 40 and not p.is_creative():
					result = ItemStack.new()
		"grindstone":
			result = Enchanting.grindstone(inp[0], inp[1])
		"smithing_table":
			result = Enchanting.smith(inp[0], inp[1], inp[2])
		"loom":
			var have: bool = not (inp[0] as ItemStack).is_empty() and not (inp[1] as ItemStack).is_empty()
			var nl: Array = Banners.selectable(inp[2]) if have else []
			if nl != loom_list:
				loom_list = nl
				loom_sel = 0 if nl.size() == 1 else -1
				loom_row = 0
			if loom_sel >= loom_list.size():
				loom_sel = -1
			if loom_sel >= 0:
				result = Banners.loom_result(inp[0], inp[1], str(loom_list[loom_sel]))
		"cartography_table":
			# CartographyTableMenu.setupResultSlot: paper zooms out (unlocked, scale < 4), a glass pane locks (unlocked),
			# an empty map copies
			var mp: ItemStack = inp[0]
			var ad: ItemStack = inp[1]
			if not mp.is_empty() and not ad.is_empty():
				var mi := Maps.info(world, mp)
				if not mi.is_empty():
					var locked := bool(mi.get("locked", false))
					if ad.name() == "paper" and not locked and int(mi.get("scale", 0)) < 4:
						result = mp.copy()
						result.count = 1
						carto_mode = "scale"
					elif ad.name() == "glass_pane" and not locked:
						result = mp.copy()
						result.count = 1
						carto_mode = "lock"
					elif ad.name() == "map":
						result = mp.copy()
						result.count = 2
						carto_mode = "copy"
		"stonecutter":
			var src: ItemStack = inp[0]
			stone_choices = Crafting.stonecutting.get(src.name(), []) if not src.is_empty() else []
			if stone_sel >= stone_choices.size():
				stone_sel = -1
			if stone_sel >= 0:
				result = ItemStack.named(stone_choices[stone_sel][0], int(stone_choices[stone_sel][1]))


func take_output(_i: int, all: bool) -> void:
	var p: Player = world.player
	var inv: Inventory = p.inventory
	if result.is_empty():
		return
	if kind == "anvil" and not p.is_creative() and p.xp_level < cost:
		return
	var out := result.copy()
	if kind == "cartography_table":
		# MapItem.onCraftedPostProcess: the taken map is the zoomed-out / locked one
		if carto_mode == "scale":
			out = Maps.scaled_copy(world, inp[0])
		elif carto_mode == "lock":
			out = Maps.locked_copy(world, inp[0])
		if out.is_empty():
			return
	if all:
		if inv.add(out) > 0:
			return
	else:
		if not inv.cursor.is_empty():
			return
		inv.cursor = out
	match kind:
		"anvil":
			if not p.is_creative():
				p.xp_level -= cost
			inp[0] = ItemStack.new()
			var r: ItemStack = inp[1]
			r.count -= use_right
			inp[1] = r if r.count > 0 else ItemStack.new()
			Audio.play("block.anvil.use", Vector3(pos), "Blocks")
			if not p.is_creative() and world.rng.randf() < 0.12:
				_damage_anvil()
			if name_edit != null:
				name_edit.text = ""
		"grindstone":
			inp[0] = ItemStack.new()
			inp[1] = ItemStack.new()
			Audio.play("block.grindstone.use", Vector3(pos), "Blocks")
		"smithing_table":
			for i in 3:
				var s: ItemStack = inp[i]
				s.count -= 1
				inp[i] = s if s.count > 0 else ItemStack.new()
			Audio.play("block.smithing_table.use", Vector3(pos), "Blocks")
		"loom":
			for k in 2:
				var lk: ItemStack = inp[k]
				lk.count -= 1
				inp[k] = lk if lk.count > 0 else ItemStack.new()
			Audio.play("ui.loom.take_result", Vector3(pos), "Blocks")
		"stonecutter":
			var s2: ItemStack = inp[0]
			s2.count -= 1
			inp[0] = s2 if s2.count > 0 else ItemStack.new()
			Audio.play("ui.stonecutter.take_result", Vector3(pos), "Blocks")
		"cartography_table":
			for k2 in 2:
				var ck: ItemStack = inp[k2]
				ck.count -= 1
				inp[k2] = ck if ck.count > 0 else ItemStack.new()
			Audio.play("ui.cartography_table.take_result", Vector3(pos), "Blocks")
	on_changed()


func _damage_anvil() -> void:
	var st: int = world.state_at(pos.x, pos.y, pos.z)
	var n := Res.blocks.name_of(st)
	var next := {"anvil": "chipped_anvil", "chipped_anvil": "damaged_anvil"}.get(n, "")
	if next == "":
		world.set_block(pos.x, pos.y, pos.z, 0)
		Audio.play("block.anvil.destroy", Vector3(pos), "Blocks")
		world.close_screen()
	else:
		var ns := Res.blocks.state_of(next, {"facing": Res.blocks.get_prop(st, "facing")})
		world.set_block(pos.x, pos.y, pos.z, ns if ns >= 0 else Res.blocks.default_state(next))


func _gui_input(event: InputEvent) -> void:
	if _unhandled_loom_wheel(event):
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := get_local_mouse_position() / UiKit.scale() - origin()
		if kind == "enchanting_table":
			for i in 3:
				if Rect2(Vector2(60, 14 + 19 * i), Vector2(108, 19)).has_point(mp):
					_enchant(i)
					accept_event()
					return
		elif kind == "loom":
			for k in 16:
				var idx := loom_row * 4 + k
				if idx < loom_list.size() and Rect2(Vector2(60 + (k % 4) * 14, 13 + (k / 4) * 14), Vector2(14, 14)).has_point(mp):
					loom_sel = idx
					Audio.play("ui.loom.select_pattern", Vector3(pos), "Blocks")
					on_changed()
					accept_event()
					return
		elif kind == "stonecutter":
			for i in stone_choices.size():
				if Rect2(_stone_rect(i).position, Vector2(16, 18)).has_point(mp):
					stone_sel = i
					on_changed()
					accept_event()
					return
	super._gui_input(event)


func _enchant(i: int) -> void:
	var p: Player = world.player
	var it: ItemStack = inp[0]
	var lapis: ItemStack = inp[1]
	var c: int = ench_costs[i]
	if it.is_empty() or c <= 0:
		return
	if not p.is_creative() and (p.xp_level < c or lapis.count < i + 1):
		return
	var sel := Enchanting.select(p.enchant_seed, i, it.name(), c)
	if sel.is_empty():
		return
	var out := it
	if it.name() == "book":
		out = ItemStack.named("enchanted_book", 1)
	var e := Enchanting.get_enchants(out)
	for s in sel:
		e[s[0]] = s[1]
	Enchanting.set_enchants(out, e)
	inp[0] = out
	if not p.is_creative():
		p.xp_level -= i + 1
		lapis.count -= i + 1
		inp[1] = lapis if lapis.count > 0 else ItemStack.new()
	p.enchant_seed = world.rng.randi()
	Audio.play("block.enchantment_table.use", Vector3(pos), "Blocks")
	on_changed()


func _draw_enchant(o: Vector2) -> void:
	var font := UiKit.font()
	var p: Player = world.player
	for i in 3:
		var r := Rect2(o + Vector2(60, 14 + 19 * i), Vector2(108, 19))
		var can: bool = ench_costs[i] > 0 and (p.is_creative() or (p.xp_level >= ench_costs[i] and (inp[1] as ItemStack).count >= i + 1))
		draw_rect(r, Color(0.55, 0.45, 0.35) if can else Color(0.32, 0.28, 0.25))
		draw_rect(r, Color(0.2, 0.15, 0.1), false, 1.0)
		if ench_costs[i] > 0:
			draw_string(font, r.position + Vector2(4, 12), str(ench_hint[i]).substr(0, 18), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.85, 0.8, 0.6) if can else Color(0.5, 0.45, 0.4))
			draw_string(font, r.position + Vector2(108 - 4 - font.get_string_size(str(ench_costs[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, 16), str(ench_costs[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 1.0, 0.2) if can else Color(0.3, 0.5, 0.2))


func _draw_anvil(o: Vector2) -> void:
	# Java AnvilScreen.renderBg: container/anvil/text_field (or _disabled without an input item) at (59, 20), 110 x 16
	var has_in := not (inp[0] as ItemStack).is_empty() if inp.size() > 0 and inp[0] != null else false
	var tf := UiKit.sprite("gui/sprites/container/anvil/text_field" if has_in else "gui/sprites/container/anvil/text_field_disabled")
	if tf != null:
		draw_texture_rect(tf, Rect2(o + Vector2(59, 20), Vector2(110, 16)), false)
	if cost > 0:
		var too: bool = cost >= 40 and not world.player.is_creative()
		var t := "Too Expensive!" if too else "Enchantment Cost: %d" % cost
		var col := Color(1.0, 0.4, 0.4) if too or world.player.xp_level < cost else Color(0.5, 1.0, 0.3)
		draw_string(UiKit.font(), o + Vector2(60, 72), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)


func _loom_rows() -> int:
	return maxi(0, int(ceil(loom_list.size() / 4.0)) - 4)


func _unhandled_loom_wheel(event: InputEvent) -> bool:
	if kind == "loom" and event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		loom_row = clampi(loom_row + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, _loom_rows())
		queue_redraw()
		return true
	return false


## Java LoomScreen.renderBg: 4x4 pattern buttons with small flags (gray base, white pattern), scroller, result preview.
func _draw_loom(o: Vector2) -> void:
	var mp := get_local_mouse_position() / UiKit.scale() - o
	for k in 16:
		var idx := loom_row * 4 + k
		if idx >= loom_list.size():
			break
		var bp := o + Vector2(60 + (k % 4) * 14, 13 + (k / 4) * 14)
		var spr := "pattern_selected" if idx == loom_sel else ("pattern_highlighted" if Rect2(bp - o, Vector2(14, 14)).has_point(mp) else "pattern")
		var t := UiKit.sprite("gui/sprites/container/loom/" + spr)
		if t != null:
			draw_texture_rect(t, Rect2(bp, Vector2(14, 14)), false)
		_draw_flag(Rect2(bp + Vector2(4.5, 2), Vector2(5, 10)), "gray", [{"pattern": loom_list[idx], "color": "white"}])
	var sc := UiKit.sprite("gui/sprites/container/loom/" + ("scroller" if _loom_rows() > 0 else "scroller_disabled"))
	if sc != null:
		var off := 0.0 if _loom_rows() == 0 else 41.0 * loom_row / _loom_rows()
		draw_texture_rect(sc, Rect2(o + Vector2(119, 13 + off), Vector2(12, 15)), false)
	var ban: ItemStack = inp[0]
	if not ban.is_empty() and Banners.layers(ban).size() >= Banners.MAX_LAYERS:
		var er := UiKit.sprite("gui/sprites/container/loom/error")
		if er != null:
			draw_texture_rect(er, Rect2(o + Vector2(139, 50) + Vector2(1, 1), Vector2(26, 26)), false)
	var show: ItemStack = result if not result.is_empty() else ban
	if not show.is_empty():
		_draw_flag(Rect2(o + Vector2(141, 8), Vector2(20, 40)), show.name().trim_suffix("_banner"), Banners.layers(show))


## Flag front (texture region 1,1 20x40 of each 64x64 layer) tinted with the dye colors.
func _draw_flag(r: Rect2, base_color: String, layers: Array) -> void:
	draw_rect(r, BERender.DYE.get(base_color, Color.WHITE))
	for l in layers:
		var tex = EntityRenderer.texture(Banners.texture(str(l.get("pattern", ""))))
		if tex != null:
			draw_texture_rect_region(tex, r, Rect2(1, 1, 20, 40), BERender.DYE.get(str(l.get("color", "white")), Color.WHITE))


## CartographyTableScreen.renderBg / renderResultingMap: error icon (locked + paper / pane, or paper at scale 4), the
## preview: zoomed (scaled_map frame, map at 0.226), two copies (duplicated_map frames, 0.34), locked (map + lock icon),
## else the map at 0.45.
func _draw_cartography(o: Vector2) -> void:
	var mp: ItemStack = inp[0]
	var ad: ItemStack = inp[1]
	var copy := ad.name() == "map"
	var paper := ad.name() == "paper"
	var pane := ad.name() == "glass_pane"
	var mi := Maps.info(world, mp) if not mp.is_empty() else {}
	var bad := false
	if not mi.is_empty():
		if bool(mi.get("locked", false)):
			bad = true
			if paper or pane:
				_spr("container/cartography_table/error", Rect2(o + Vector2(35, 31), Vector2(28, 21)))
		if paper and int(mi.get("scale", 0)) >= 4:
			bad = true
			_spr("container/cartography_table/error", Rect2(o + Vector2(35, 31), Vector2(28, 21)))
	var tex: Texture2D = Maps.texture(world, Maps.map_id(mp)) if not mi.is_empty() else null
	var mapq := func(at: Vector2, scale: float) -> void:
		if tex != null:
			draw_texture_rect(tex, Rect2(at + Vector2(1, 1), Vector2(128, 128) * scale), false)
	if paper and not bad:
		_spr("container/cartography_table/scaled_map", Rect2(o + Vector2(67, 13), Vector2(66, 66)))
		mapq.call(o + Vector2(85, 31), 0.226)
	elif copy:
		_spr("container/cartography_table/duplicated_map", Rect2(o + Vector2(83, 13), Vector2(50, 66)))
		mapq.call(o + Vector2(86, 16), 0.34)
		_spr("container/cartography_table/duplicated_map", Rect2(o + Vector2(67, 29), Vector2(50, 66)))
		mapq.call(o + Vector2(70, 32), 0.34)
	elif pane:
		_spr("container/cartography_table/map", Rect2(o + Vector2(67, 13), Vector2(66, 66)))
		mapq.call(o + Vector2(71, 17), 0.45)
		_spr("container/cartography_table/locked", Rect2(o + Vector2(118, 60), Vector2(10, 14)))
	else:
		_spr("container/cartography_table/map", Rect2(o + Vector2(67, 13), Vector2(66, 66)))
		mapq.call(o + Vector2(71, 17), 0.45)


func _spr(path: String, r: Rect2) -> void:
	var t := UiKit.sprite("gui/sprites/" + path)
	if t != null:
		draw_texture_rect(t, r, false)


func _stone_rect(i: int) -> Rect2:
	return Rect2(Vector2(52 + (i % 4) * 16, 15 + (i / 4) * 18), Vector2(16, 18))


func _draw_stonecutter(o: Vector2) -> void:
	for i in mini(stone_choices.size(), 12):
		var r := _stone_rect(i)
		draw_rect(Rect2(o + r.position, r.size), Color(0.75, 0.75, 0.75) if i != stone_sel else Color(0.45, 0.8, 0.45))
		var ic := ItemIcons.icon(Res.items.id(stone_choices[i][0]))
		if ic != null:
			draw_texture_rect(ic, Rect2(o + r.position + Vector2(0, 1), Vector2(16, 16)), false)


func on_close() -> void:
	var inv: Inventory = world.player.inventory
	for i in inp.size():
		var s: ItemStack = inp[i]
		if not s.is_empty():
			var left := inv.add(s)
			if left > 0:
				s.count = left
				world.entities.spawn_item(world.player.eye_pos(), s.copy())
		inp[i] = ItemStack.new()
	super.on_close()
