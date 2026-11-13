## ContainerUI — base for slot screens using Java container background textures (gui/container/*.png) and
## standard click semantics: left = pick/place/swap/merge, right = split half / place one, shift-click =
## quick-move between sections, number keys 1-9 = hotbar swap, double-click = collect matching, Q = drop.
## Subclasses add slot defs via add_slot(pos, getter, setter, section, output, filter). No item duplication:
## every transfer moves counts between exactly two stacks (verified by tests).
class_name ContainerUI
extends Control

var world
var slots: Array = []      # {pos, get, set, section, output, filter}
var bg_tex: Texture2D
var bg_size := Vector2(176, 166)
var bg_region := Rect2()
var hover := -1
var title := ""
var title_pos := Vector2(8, 6)   # Java titleLabelX / titleLabelY
var inv_label := true            # Java playerInventoryTitle at (8, imageHeight - 94) when the screen shows the player inventory
var _has_player_inv := false
var _last_click := 0
var _last_slot := -1
var extra_draw: Callable
var slot_toggle: Callable   # called with the slot index for a plain click on an empty "toggle" slot (crafter)
# recipe book (RecipeBook): grid size, grid accessors (i) -> ItemStack / (i, ItemStack), toggle button position
var rb_gw := 0
var rb_gh := 0
var rb_get: Callable
var rb_set: Callable
var rb_btn := Vector2.ZERO
var rb_open := false
var rb_list: Array = []        # [recipe, cells, craftable]
var rb_page := 0
var rb_tab := 0                 # RecipeBook.TABS index
var rb_filter := false          # Java "Showing Craftable" toggle (default: all)
var _rb_search: LineEdit
var _rb_tip: Array = []
static var advanced_tooltips := false   # Java F3+H


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	build()


func build() -> void:
	pass


func closes_on_inventory_key() -> bool:
	return true


func origin() -> Vector2:
	var s := UiKit.scale()
	return (size / s - bg_size) / 2.0 + (Vector2(77, 0) if rb_open else Vector2.ZERO)   # Java shifts the GUI right


func _rb_refresh() -> void:
	var g: Array = []
	for i in rb_gw * rb_gh:
		g.append(rb_get.call(i))
	var cat: String = RecipeBook.TABS[rb_tab][0]
	rb_list = RecipeBook.listing(world.player.inventory, g, rb_gw, rb_gh, cat, rb_filter, _rb_search.text if _rb_search != null else "")
	rb_page = clampi(rb_page, 0, maxi(0, (rb_list.size() - 1) / 20))


## Java RecipeBookComponent geometry: book (147 x 166) left of the shifted container, recipe buttons 5 x 4 at
## (11, 31) pitch 25, tabs 35 x 27 at (-30, 3 + 27 i) (selected drawn 2 px further left), craftable filter
## 26 x 16 at (110, 12), search box 81 x 14 at (25, 13), page arrows 12 x 17 at (38 / 93, 137), page text at x 73.
func _rb_x(o: Vector2) -> Vector2:
	return o + Vector2(-149, 0)


func _rb_entry_rect(o: Vector2, k: int) -> Rect2:
	return Rect2(_rb_x(o) + Vector2(11 + (k % 5) * 25, 31 + (k / 5) * 25), Vector2(25, 25))


func _rb_tab_rect(o: Vector2, i: int) -> Rect2:
	return Rect2(_rb_x(o) + Vector2(-30 - (2 if i == rb_tab else 0), 3 + 27 * i), Vector2(35, 27))


func _rb_pages() -> int:
	return maxi(1, (rb_list.size() + 19) / 20)


func _rb_place_search() -> void:
	if _rb_search == null:
		return
	_rb_search.visible = rb_open
	var s := float(UiKit.scale())
	_rb_search.position = (_rb_x(origin()) + Vector2(25, 13)) * s
	_rb_search.size = Vector2(81, 14) * s


func _rb_make_search() -> void:
	if _rb_search != null:
		return
	_rb_search = LineEdit.new()
	_rb_search.max_length = 50
	_rb_search.placeholder_text = Res.tr_key("gui.recipebook.search_hint", "Search...")
	_rb_search.add_theme_color_override("font_color", Color(1, 1, 1))
	_rb_search.add_theme_color_override("font_placeholder_color", Color8(170, 170, 170))
	_rb_search.add_theme_color_override("caret_color", Color(1, 1, 1))
	for st in ["normal", "focus", "read_only"]:
		_rb_search.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_rb_search.text_changed.connect(func(_t):
		rb_tab = 0   # Java: typing searches every category
		rb_page = 0
		_rb_refresh()
		queue_redraw())
	add_child(_rb_search)
	resized.connect(_rb_place_search)


func _draw_recipe_book(o: Vector2, font: Font) -> void:
	var mp := get_local_mouse_position() / UiKit.scale()
	var btn := UiKit.sprite("gui/sprites/recipe_book/button_highlighted" if Rect2(o + rb_btn, Vector2(20, 18)).has_point(mp) else "gui/sprites/recipe_book/button")
	if btn != null:
		draw_texture_rect(btn, Rect2(o + rb_btn, Vector2(20, 18)), false)
	else:
		draw_rect(Rect2(o + rb_btn, Vector2(20, 18)), Color(0.3, 0.6, 0.25))
	_rb_tip = []
	if not rb_open:
		return
	if _rb_search == null or not _rb_search.visible:
		call_deferred("_rb_make_search")
		call_deferred("_rb_place_search")
	var bx := _rb_x(o)
	# tabs (behind the book)
	for i in RecipeBook.TABS.size():
		var tr := _rb_tab_rect(o, i)
		var ts := UiKit.sprite("gui/sprites/recipe_book/tab_selected" if i == rb_tab else "gui/sprites/recipe_book/tab")
		if ts != null:
			draw_texture_rect(ts, tr, false)
		# Java RecipeBookTabButton.renderIcon: x + 9 (one icon) or x + 3 / x + 14, both shifted with the selected tab
		var icons: Array = RecipeBook.TABS[i][1]
		if icons.size() == 1:
			_draw_icon(str(icons[0]), tr.position + Vector2(9, 5))
		else:
			_draw_icon(str(icons[0]), tr.position + Vector2(3, 5))
			_draw_icon(str(icons[1]), tr.position + Vector2(14, 5))
	var panel := UiKit.sprite("gui/recipe_book")
	if panel != null:
		draw_texture_rect_region(panel, Rect2(bx, Vector2(147, 166)), Rect2(1, 1, 147, 166))
	else:
		draw_rect(Rect2(bx, Vector2(147, 166)), Color(0.78, 0.78, 0.78))
	# craftable filter toggle
	var fr := Rect2(bx + Vector2(110, 12), Vector2(26, 16))
	var fs := UiKit.sprite("gui/sprites/recipe_book/filter_" + ("enabled" if rb_filter else "disabled") + ("_highlighted" if fr.has_point(mp) else ""))
	if fs != null:
		draw_texture_rect(fs, fr, false)
	var tip: Array = []
	if fr.has_point(mp):
		tip = [[Res.tr_key("gui.recipebook.toggleRecipes.craftable" if rb_filter else "gui.recipebook.toggleRecipes.all", "Showing Craftable" if rb_filter else "Showing All"), Color(1, 1, 1)]]
	for k in 20:
		var idx := rb_page * 20 + k
		if idx >= rb_list.size():
			break
		var r: Rect2 = _rb_entry_rect(o, k)
		var rec: Dictionary = rb_list[idx][0]
		var ok: bool = rb_list[idx][2]
		var ss := UiKit.sprite("gui/sprites/recipe_book/slot_craftable" if ok else "gui/sprites/recipe_book/slot_uncraftable")
		if ss != null:
			draw_texture_rect(ss, r, false)
		else:
			draw_rect(r.grow(-1), Color(0.42, 0.42, 0.42) if ok else Color(0.6, 0.25, 0.25))
		_draw_stack(ItemStack.named(str(rec["result"]), int(rec["count"])), r.position + Vector2(4, 4), font)
		if r.has_point(mp):
			tip = [[Res.items.display_name(Res.items.id(str(rec["result"]))), Color(1, 1, 1)]]
	var pages := _rb_pages()
	if pages > 1:
		for fwd in [false, true]:
			var pr := Rect2(bx + Vector2(93 if fwd else 38, 137), Vector2(12, 17))
			var show: bool = rb_page < pages - 1 if fwd else rb_page > 0
			if show:
				var ps := UiKit.sprite("gui/sprites/recipe_book/page_" + ("forward" if fwd else "backward") + ("_highlighted" if pr.has_point(mp) else ""))
				if ps != null:
					draw_texture_rect(ps, pr, false)
		var pt := "%d/%d" % [rb_page + 1, pages]
		var pw := font.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(font, bx + Vector2(73 - floorf(pw / 2.0), 141 + 7), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1))
	_rb_tip = tip


func _draw_icon(item: String, p: Vector2) -> void:
	var id := Res.items.id(item) if Res.items != null else -1
	if id < 0:
		return
	var ic := ItemIcons.icon(id)
	if ic != null:
		draw_texture_rect(ic, Rect2(p, Vector2(16, 16)), false)


## Recipe book clicks; returns true when handled.
func _rb_click(pos: Vector2) -> bool:
	if rb_gw == 0:
		return false
	var o := origin()
	if Rect2(o + rb_btn, Vector2(20, 18)).has_point(pos):
		rb_open = not rb_open
		_rb_make_search()
		if rb_open:
			_rb_refresh()
		_rb_place_search()
		Audio.play_ui("ui.button.click")
		return true
	if not rb_open:
		return false
	var bx := _rb_x(o)
	for i in RecipeBook.TABS.size():
		if _rb_tab_rect(o, i).has_point(pos):
			if i != rb_tab:
				rb_tab = i
				rb_page = 0
				_rb_refresh()
				Audio.play_ui("ui.button.click")
			return true
	if Rect2(bx + Vector2(110, 12), Vector2(26, 16)).has_point(pos):
		rb_filter = not rb_filter
		rb_page = 0
		_rb_refresh()
		Audio.play_ui("ui.button.click")
		return true
	if _rb_pages() > 1:
		if rb_page > 0 and Rect2(bx + Vector2(38, 137), Vector2(12, 17)).has_point(pos):
			rb_page -= 1
			Audio.play_ui("ui.button.click")
			return true
		if rb_page < _rb_pages() - 1 and Rect2(bx + Vector2(93, 137), Vector2(12, 17)).has_point(pos):
			rb_page += 1
			Audio.play_ui("ui.button.click")
			return true
	for k in 20:
		var idx := rb_page * 20 + k
		if idx < rb_list.size() and _rb_entry_rect(o, k).has_point(pos):
			if rb_list[idx][2]:
				RecipeBook.fill(world, rb_list[idx], rb_gw * rb_gh, rb_get, rb_set)
				on_changed()
				_rb_refresh()
			return true
	return Rect2(bx, Vector2(147, 166)).has_point(pos)

func add_slot(pos: Vector2, getter: Callable, setter: Callable, section: int, output := false, filter := Callable(), empty_icon := "") -> void:
	slots.append({"pos": pos, "get": getter, "set": setter, "section": section, "output": output, "filter": filter, "empty": empty_icon})


func add_player_inventory(x: float, y: float) -> void:
	_has_player_inv = true
	var inv: Inventory = world.player.inventory
	for r in 3:
		for c in 9:
			var i := 9 + r * 9 + c
			add_slot(Vector2(x + c * 18, y + r * 18), inv.get_slot.bind(i), inv.setter(i), 1)
	for c in 9:
		add_slot(Vector2(x + c * 18, y + 58), inv.get_slot.bind(c), inv.setter(c), 2)


func _process(_d: float) -> void:
	queue_redraw()
	if _over != null:
		_over.queue_redraw()


# The carried stack and tooltips draw on a top overlay (z above the player preview SubViewport and other children).
var _over: Control
var _ci: CanvasItem = self
var _over_cursor: ItemStack = null
var _over_tip: Array = []
var _over_mp := Vector2.ZERO


func _ensure_overlay() -> void:
	if _over != null:
		return
	_over = Control.new()
	_over.name = "overlay"
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.z_index = 50
	add_child(_over)
	_over.draw.connect(_draw_overlay)


func overlay_cursor(st: ItemStack, mp: Vector2) -> void:
	_over_cursor = st
	_over_mp = mp


func overlay_tip(tip: Array, mp: Vector2) -> void:
	_over_tip = tip
	_over_mp = mp


func _draw_overlay() -> void:
	var s := UiKit.scale()
	_over.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	_ci = _over
	if _over_cursor != null and not _over_cursor.is_empty():
		_draw_stack(_over_cursor, _over_mp - Vector2(8, 8), UiKit.font())
	elif not _over_tip.is_empty():
		UiKit.draw_tooltip(_over, _over_mp, _over_tip, size / float(s))
	_ci = self


func _draw() -> void:
	var s := UiKit.scale()
	_ensure_overlay()
	_over_cursor = null
	_over_tip = []
	draw_dim()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var o := origin()
	draw_background(o)
	var font := UiKit.font()
	if title != "":
		draw_string(font, o + title_pos + Vector2(0, 7), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, LABEL_COLOR)
	if inv_label and _has_player_inv:
		draw_string(font, o + Vector2(8, bg_size.y - 94 + 7), Res.tr_key("container.inventory", "Inventory"), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, LABEL_COLOR)
	if extra_draw.is_valid():
		extra_draw.call(o)
	if rb_gw > 0:
		_draw_recipe_book(o, font)
	var mp := get_local_mouse_position() / s
	# Java 1.21.2+ AbstractContainerScreen: slot_highlight_back (24 x 24 at slot - 4) behind the hovered slot's item,
	# slot_highlight_front over it; empty slots with a background icon (armour / offhand silhouettes) show it
	hover = -1
	for i in slots.size():
		if Rect2(o + (slots[i]["pos"] as Vector2), Vector2(16, 16)).has_point(mp):
			hover = i
	if hover >= 0:
		var hb := UiKit.sprite("gui/sprites/container/slot_highlight_back")
		if hb != null:
			draw_texture_rect(hb, Rect2(o + (slots[hover]["pos"] as Vector2) - Vector2(4, 4), Vector2(24, 24)), false)
	var drag_each := _drag_each() if _drag and _drag_slots.size() > 1 else 0
	var drag_left: int = world.player.inventory.cursor.count
	for i in slots.size():
		var sl: Dictionary = slots[i]
		var p: Vector2 = o + sl["pos"]
		var st: ItemStack = sl["get"].call()
		if drag_each > 0 and _drag_slots.has(i):
			# Java renderSlot quick-craft preview: the slot shows what it will hold, highlighted
			var cur2: ItemStack = world.player.inventory.cursor
			var pv := cur2.copy()
			var have := st.count if not st.is_empty() else 0
			var add := mini(mini(drag_each, cur2.max_stack() - have), drag_left)
			drag_left -= add
			pv.count = have + add
			draw_rect(Rect2(p, Vector2(16, 16)), Color(1, 1, 1, 0.5))
			_draw_stack(pv, p, font)
			continue
		if st.is_empty() and str(sl.get("empty", "")) != "":
			var ei := UiKit.sprite("gui/sprites/container/slot/" + str(sl["empty"]))
			if ei != null:
				draw_texture_rect(ei, Rect2(p, Vector2(16, 16)), false)
		_draw_stack(st, p, font)
	if hover >= 0:
		var hf := UiKit.sprite("gui/sprites/container/slot_highlight_front")
		if hf != null:
			draw_texture_rect(hf, Rect2(o + (slots[hover]["pos"] as Vector2) - Vector2(4, 4), Vector2(24, 24)), false)
		else:
			draw_rect(Rect2(o + (slots[hover]["pos"] as Vector2), Vector2(16, 16)), Color(1, 1, 1, 0.5))
	var cur: ItemStack = world.player.inventory.cursor
	if not cur.is_empty():
		if drag_each > 0:
			# Java: the carried stack shows what is left after the spread (yellow count)
			var rest := cur.copy()
			rest.count = drag_left
			if rest.count > 0:
				overlay_cursor(rest, mp)
		else:
			overlay_cursor(cur, mp)
	elif hover >= 0:
		var hs: ItemStack = slots[hover]["get"].call()
		if not hs.is_empty():
			overlay_tip(item_tooltip(hs), mp)
	elif not _rb_tip.is_empty():
		overlay_tip(_rb_tip, mp)


const LABEL_COLOR := Color(0.2509804, 0.2509804, 0.2509804)   # Java 4210752 (0x404040), no shadow


# Java ChatFormatting colours
const C_WHITE := Color8(255, 255, 255)
const C_GRAY := Color8(170, 170, 170)
const C_DARK_GRAY := Color8(85, 85, 85)
const C_DARK_GREEN := Color8(0, 170, 0)
const C_BLUE := Color8(85, 85, 255)
const C_RED := Color8(255, 85, 85)
const C_YELLOW := Color8(255, 255, 85)
const C_AQUA := Color8(85, 255, 255)
const C_LIGHT_PURPLE := Color8(255, 85, 255)
const C_DARK_PURPLE := Color8(170, 0, 170)

# Java Rarity (item default components): 1 uncommon (yellow), 2 rare (aqua), 3 epic (light purple)
const RARITY := {"enchanted_golden_apple": 3, "command_block": 3, "chain_command_block": 3, "repeating_command_block": 3,
	"command_block_minecart": 3, "structure_block": 3, "jigsaw": 3, "barrier": 3, "light": 3, "debug_stick": 3, "dragon_egg": 3,
	"elytra": 3, "mace": 3, "heavy_core": 3, "dragon_head": 3, "knowledge_book": 3, "test_block": 3, "test_instance_block": 3,
	"beacon": 2, "conduit": 2, "end_crystal": 2, "golden_apple": 2, "heart_of_the_sea": 2, "nether_star": 2, "trident": 2,
	"totem_of_undying": 1, "experience_bottle": 1, "dragon_breath": 1, "enchanted_book": 1, "skeleton_skull": 1,
	"wither_skeleton_skull": 1, "player_head": 1, "zombie_head": 1, "creeper_head": 1, "piglin_head": 1, "ominous_bottle": 1,
	"trial_key": 1, "ominous_trial_key": 1, "netherite_upgrade_smithing_template": 1, "sniffer_egg": 1, "recovery_compass": 1,
	"echo_shard": 1, "disc_fragment_5": 1}


static func rarity(hs: ItemStack) -> int:
	var n := hs.name()
	var r := int(RARITY.get(n, 0))
	if r == 0 and (n.begins_with("music_disc_") or n.ends_with("_armor_trim_smithing_template")):
		r = 2 if n.begins_with("music_disc_") else 1
	if r == 0 and n.ends_with("_banner_pattern"):
		r = 1
	# Java ItemStack.getRarity: enchantments raise common / uncommon to rare, rare to epic
	if not Enchanting.get_enchants(hs).is_empty() and n != "enchanted_book":
		r = 2 if r < 2 else 3
	return r


static func _fmt(v: float) -> String:
	# Java ItemAttributeModifiers.ATTRIBUTE_MODIFIER_FORMAT (#.##)
	var s := str(snappedf(v, 0.01))
	return s.trim_suffix(".0")


## Java ItemStack.getTooltipLines: name (rarity colour), component lines (potion effects, enchantments, dye, lore,
## trim), the attribute block (blank line, "When in Main Hand:" / "When on Head:" ..., " 7 Attack Damage" dark green
## for base weapon stats, "+2 Armor" blue / "-x" red otherwise), Unbreakable; advanced tooltips (F3+H): durability,
## item id, component count. Lines: [[text, Color], ...] ("" = an empty spacer line).
static func item_tooltip(hs: ItemStack) -> Array:
	var name := Res.items.display_name(hs.item)
	var custom = hs.components.get("minecraft:custom_name")
	if custom is String and custom != "":
		name = custom
	if hs.components.has("recraft:unknown_id"):
		name += " (unsupported: %s)" % hs.components["recraft:unknown_id"]
	var lines: Array = [[name, [C_WHITE, C_YELLOW, C_AQUA, C_LIGHT_PURPLE][rarity(hs)]]]
	var n := hs.name()
	# potion contents (Java PotionContents.addPotionTooltip)
	if Potions.is_bottle(hs) or n == "tipped_arrow":
		var pid := Potions.potion_of(hs)
		var effs: Array = Potions.EFFECTS.get(pid, [])
		var scale := 0.125 if n == "tipped_arrow" else (0.25 if n == "lingering_potion" else 1.0)
		if effs.is_empty():
			lines.append([Res.tr_key("effect.none", "No Effects"), C_GRAY])
		for ef in effs:
			var en := Res.tr_key("effect.minecraft." + str(ef[0]), str(ef[0]).capitalize())
			if int(ef[1]) > 0:
				en += " " + Res.tr_key("potion.potency.%d" % int(ef[1]), Enchanting.roman(int(ef[1]) + 1))
			var dur := int(float(ef[2]) * scale)
			if dur > 20:
				en += " (%d:%02d)" % [dur / 1200, (dur / 20) % 60]
			var harmful := str(ef[0]) in ["slowness", "instant_damage", "poison", "weakness", "mining_fatigue", "nausea", "blindness", "hunger", "wither", "levitation", "unluck", "bad_omen", "darkness", "infested", "oozing", "weaving", "wind_charged"]
			lines.append([en, C_RED if harmful else C_BLUE])
	# enchantments (stored on books), curses red; the level is shown unless the enchantment has a single level
	var ench := Enchanting.get_enchants(hs)
	for eid in ench:
		var lvl := int(ench[eid])
		var key := str(eid) if str(eid).contains(":") else "minecraft:" + str(eid)
		var d: Dictionary = Enchanting.defs.get(key, Enchanting.defs.get(key.trim_prefix("minecraft:"), {}))
		var et := Enchanting.name_of(key)
		if lvl != 1 or int(d.get("max", 2)) != 1:
			et += " " + Res.tr_key("enchantment.level.%d" % lvl, Enchanting.roman(lvl))
		lines.append([et, C_RED if d.get("curse", false) else C_GRAY])
	if hs.components.has("minecraft:dyed_color"):
		if advanced_tooltips:
			lines.append(["Color: #%06X" % int(hs.components["minecraft:dyed_color"]), C_GRAY])
		else:
			lines.append([Res.tr_key("item.dyed", "Dyed"), C_GRAY])
	var lore = hs.components.get("minecraft:lore")
	if lore is Array:
		for ll in lore:
			lines.append([str(ll), C_DARK_PURPLE])
	# attribute modifiers by slot group (Java ItemStack.addAttributeTooltips)
	var aslot: int = Res.items.armor_slot[hs.item]
	var kind: String = Res.items.tool_kind[hs.item]
	if kind != "" or n in ["trident", "mace"]:
		lines.append(["", C_WHITE])
		lines.append([Res.tr_key("item.modifiers.mainhand", "When in Main Hand:"), C_GRAY])
		lines.append([" " + _fmt(Res.items.attack_damage[hs.item]) + " " + Res.tr_key("attribute.name.attack_damage", "Attack Damage"), C_DARK_GREEN])
		lines.append([" " + _fmt(Res.items.attack_speed[hs.item]) + " " + Res.tr_key("attribute.name.attack_speed", "Attack Speed"), C_DARK_GREEN])
	elif aslot >= 0:
		var slot_key: String = ["feet", "legs", "chest", "head"][aslot]
		var slot_txt: String = ["When on Feet:", "When on Legs:", "When on Body:", "When on Head:"][aslot]
		var pts: int = Res.items.armor_points[hs.item]
		var tough: float = Res.items.armor_tough[hs.item]
		if pts > 0 or tough > 0.0:
			lines.append(["", C_WHITE])
			lines.append([Res.tr_key("item.modifiers." + slot_key, slot_txt), C_GRAY])
			if pts > 0:
				lines.append(["+" + str(pts) + " " + Res.tr_key("attribute.name.armor", "Armor"), C_BLUE])
			if tough > 0.0:
				lines.append(["+" + _fmt(tough) + " " + Res.tr_key("attribute.name.armor_toughness", "Armor Toughness"), C_BLUE])
			if n.begins_with("netherite_"):
				lines.append(["+1 " + Res.tr_key("attribute.name.knockback_resistance", "Knockback Resistance"), C_BLUE])
	if hs.components.has("minecraft:unbreakable"):
		lines.append([Res.tr_key("item.unbreakable", "Unbreakable"), C_BLUE])
	if advanced_tooltips:
		var md: int = Res.items.max_damage[hs.item]
		if md > 0 and hs.damage > 0:
			var parts := Res.tr_key("item.durability", "Durability: %s / %s").split("%s")
			var dt := (parts[0] + str(md - hs.damage) + parts[1] + str(md) + parts[2]) if parts.size() == 3 else "Durability: %d / %d" % [md - hs.damage, md]
			lines.append([dt, Color(1, 1, 1)])
		lines.append(["minecraft:" + hs.name(), C_DARK_GRAY])
		if not hs.components.is_empty():
			lines.append([Res.tr_key("item.components", "%s component(s)").replace("%s", str(hs.components.size())), C_DARK_GRAY])
	return lines


## Java Screen.renderTransparentBackground (container screens over the world): vertical gradient 0xC0101010 -> 0xD0101010.
func draw_dim() -> void:
	var top := Color8(16, 16, 16, 0xC0)
	var bot := Color8(16, 16, 16, 0xD0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]), PackedColorArray([top, top, bot, bot]))


func draw_background(o: Vector2) -> void:
	if bg_tex != null:
		draw_texture_rect_region(bg_tex, Rect2(o, bg_size), Rect2(Vector2.ZERO, bg_size))
	else:
		draw_rect(Rect2(o, bg_size), Color(0.78, 0.78, 0.78))
		draw_rect(Rect2(o, bg_size), Color(0.2, 0.2, 0.2), false, 1.0)
		for sl in slots:
			draw_rect(Rect2(o + sl["pos"] - Vector2(1, 1), Vector2(18, 18)), Color(0.55, 0.55, 0.55))


func _draw_stack(st: ItemStack, p: Vector2, font: Font) -> void:
	if st == null or st.is_empty():
		return
	var ic := ItemIcons.icon_for(st)
	if ic != null:
		_ci.draw_texture_rect(ic, Rect2(p, Vector2(16, 16)), false)
	if st.count > 1:
		var t := str(st.count)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		_ci.draw_string(font, p + Vector2(18 - w, 18), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.25, 0.25, 0.25))
		_ci.draw_string(font, p + Vector2(17 - w, 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	if Bundles.is_bundle(st) and not Bundles.contents(st).is_empty():
		# Java BundleItem bar: 1 + 12 * fullness px, blue (red when full)
		var bw := Bundles.weight(st)
		_ci.draw_rect(Rect2(p + Vector2(2, 13), Vector2(13, 2)), Color.BLACK)
		_ci.draw_rect(Rect2(p + Vector2(2, 13), Vector2(mini(13, 1 + 12 * bw / Bundles.CAPACITY), 1)), Color8(0xFF, 0x55, 0x55) if bw >= Bundles.CAPACITY else Color8(0x70, 0x86, 0xFF))
	var md: int = Res.items.max_damage[st.item]
	if md > 0 and st.damage > 0:
		var f := 1.0 - float(st.damage) / md
		_ci.draw_rect(Rect2(p + Vector2(2, 13), Vector2(13, 2)), Color.BLACK)
		_ci.draw_rect(Rect2(p + Vector2(2, 13), Vector2(roundf(13 * f), 1)), Color.from_hsv(f / 3.0, 1, 1))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _drag:
		_drag_add(hover)
	if event is InputEventMouseButton and not event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE):
		_release(event.button_index)
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and hover < 0:
		if _rb_click(get_local_mouse_position() / UiKit.scale()):
			accept_event()
			return
	if event is InputEventMouseButton and event.pressed:
		if hover < 0:
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
				var o := origin() * UiKit.scale()
				if not Rect2(o, bg_size * UiKit.scale()).has_point(event.position):
					_drop_cursor(event.button_index == MOUSE_BUTTON_RIGHT)
			return
		# Java AbstractContainerScreen.mouseClicked: with an empty cursor the click acts on press; carrying a stack
		# starts a quick-craft drag whose outcome is decided on release (one slot: a normal click; several: spread)
		var shift := Input.is_key_pressed(KEY_SHIFT)
		var now := Time.get_ticks_msec()
		var btn: int = event.button_index
		_dbl = _last_slot == hover and now - _last_click < 250 and _last_btn == btn
		_skip_release = false
		var cur0: ItemStack = world.player.inventory.cursor
		if btn == MOUSE_BUTTON_MIDDLE:
			if world.player.is_creative() and cur0.is_empty():
				var hs: ItemStack = slots[hover]["get"].call()
				if not hs.is_empty():
					var cp := hs.copy()
					cp.count = cp.max_stack()
					world.player.inventory.cursor = cp
			elif world.player.is_creative():
				_drag = true
				_drag_btn = btn
				_drag_slots = []
		elif cur0.is_empty() and not shift and slot_toggle.is_valid() and bool(slots[hover].get("toggle", false)) and (slots[hover]["get"].call() as ItemStack).is_empty():
			slot_toggle.call(hover)
			_skip_release = true
		elif cur0.is_empty():
			if shift and btn == MOUSE_BUTTON_LEFT:
				quick_move(hover)
			elif not _dbl:
				click(hover, btn == MOUSE_BUTTON_RIGHT)
			_skip_release = true
		elif shift and btn == MOUSE_BUTTON_LEFT:
			quick_move(hover)
			_skip_release = true
		else:
			_drag = true
			_drag_btn = btn
			_drag_slots = []
		_last_click = now
		_last_slot = hover
		_last_btn = btn
		on_changed()
		accept_event()
	elif event is InputEventKey and event.pressed and hover >= 0:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			_swap_hotbar(hover, k - KEY_1)
			on_changed()
			accept_event()
		elif k == KEY_Q:
			var hs2: ItemStack = slots[hover]["get"].call()
			if not hs2.is_empty():
				var out := hs2.split(hs2.count if Input.is_key_pressed(KEY_CTRL) else 1)
				slots[hover]["set"].call(hs2 if not hs2.is_empty() else ItemStack.new())
				world.entities.spawn_item(world.player.eye_pos(), out)
				on_changed()
			accept_event()


var _dbl := false
var _skip_release := false
var _last_btn := 0
var _drag := false
var _drag_btn := 0
var _drag_slots: Array = []


## Java mouseDragged (quick craft): slots the carried stack can still be spread over.
func _drag_add(i: int) -> void:
	if not _drag or i < 0 or _drag_slots.has(i):
		return
	var cur: ItemStack = world.player.inventory.cursor
	var sl: Dictionary = slots[i]
	if cur.is_empty() or sl["output"] or (sl["filter"].is_valid() and not sl["filter"].call(cur)):
		return
	var st: ItemStack = sl["get"].call()
	if not st.is_empty() and not st.can_merge(cur):
		return
	if _drag_btn != MOUSE_BUTTON_MIDDLE and cur.count <= _drag_slots.size():
		return
	_drag_slots.append(i)


## Java AbstractContainerMenu.getQuickCraftPlaceCount: left = even split, right = one each, middle = a full stack.
func _drag_each() -> int:
	var cur: ItemStack = world.player.inventory.cursor
	match _drag_btn:
		MOUSE_BUTTON_LEFT:
			return int(floor(float(cur.count) / maxi(1, _drag_slots.size())))
		MOUSE_BUTTON_RIGHT:
			return 1
	return cur.max_stack()


## Java mouseReleased: double-click collects (PICKUP_ALL), a drag over several slots spreads the carried stack, a
## drag that stayed on one slot is a normal click there.
func _release(btn: int) -> void:
	var cur: ItemStack = world.player.inventory.cursor
	if _dbl and btn == MOUSE_BUTTON_LEFT and hover >= 0:
		_collect(hover)
		_dbl = false
		_last_click = 0
		_drag = false
		_drag_slots = []
		on_changed()
		return
	if _drag and _drag_btn != btn:
		_drag = false
		_drag_slots = []
		return
	if _skip_release:
		_skip_release = false
		return
	if not _drag:
		return
	_drag = false
	if _drag_slots.size() > 1:
		var each := _drag_each()
		var creative_copy := _drag_btn == MOUSE_BUTTON_MIDDLE
		for i in _drag_slots:
			var sl: Dictionary = slots[i]
			var st: ItemStack = sl["get"].call()
			var room := (st.max_stack() if not st.is_empty() else cur.max_stack()) - (st.count if not st.is_empty() else 0)
			var n := mini(room, each) if creative_copy else mini(mini(room, each), cur.count)
			if n <= 0:
				continue
			if st.is_empty():
				var ns := cur.copy()
				ns.count = n
				sl["set"].call(ns)
			else:
				st.count += n
			if not creative_copy:
				cur.count -= n
		if cur.count <= 0:
			world.player.inventory.cursor = ItemStack.new()
	elif _drag_slots.size() == 1:
		click(_drag_slots[0], btn == MOUSE_BUTTON_RIGHT)
	elif hover >= 0:
		click(hover, btn == MOUSE_BUTTON_RIGHT)
	_drag_slots = []
	on_changed()


func _drop_cursor(one: bool) -> void:
	var inv: Inventory = world.player.inventory
	if inv.cursor.is_empty():
		return
	var out := inv.cursor.split(1 if one else inv.cursor.count)
	var e = world.entities.spawn_item(world.player.eye_pos() - Vector3(0, 0.3, 0), out)
	if e != null:
		e.vel = world.player.look_dir() * 0.3
		e.pickup_delay = 40


func click(i: int, right: bool) -> void:
	var inv: Inventory = world.player.inventory
	var sl: Dictionary = slots[i]
	var st: ItemStack = sl["get"].call()
	var cur := inv.cursor
	if sl["output"]:
		take_output(i, false)
		return
	if not (sl["filter"].is_valid() and st.is_empty()) and Bundles.click(self, sl, st, right):
		return
	if sl["filter"].is_valid() and not cur.is_empty() and not sl["filter"].call(cur):
		return
	if cur.is_empty():
		if st.is_empty():
			return
		if right:
			var half := int(ceil(st.count / 2.0))
			inv.cursor = st.split(half)
			sl["set"].call(st if not st.is_empty() else ItemStack.new())
		else:
			inv.cursor = st
			sl["set"].call(ItemStack.new())
	else:
		if st.is_empty():
			if right:
				sl["set"].call(cur.split(1))
			else:
				sl["set"].call(cur)
				inv.cursor = ItemStack.new()
		elif st.can_merge(cur):
			var room := st.max_stack() - st.count
			var mv := mini(room, 1 if right else cur.count)
			st.count += mv
			cur.count -= mv
			if cur.count <= 0:
				inv.cursor = ItemStack.new()
		elif not right:
			sl["set"].call(cur)
			inv.cursor = st


func _collect(i: int) -> void:
	var inv: Inventory = world.player.inventory
	var cur := inv.cursor
	if cur.is_empty():
		return
	for sl in slots:
		if sl["output"]:
			continue
		var st: ItemStack = sl["get"].call()
		if st.can_merge(cur) and cur.count < cur.max_stack():
			var mv := mini(cur.max_stack() - cur.count, st.count)
			cur.count += mv
			st.count -= mv
			if st.count <= 0:
				sl["set"].call(ItemStack.new())


func _swap_hotbar(i: int, hb: int) -> void:
	var inv: Inventory = world.player.inventory
	var sl: Dictionary = slots[i]
	if sl["output"]:
		return
	var a: ItemStack = sl["get"].call()
	var b: ItemStack = inv.get_slot(hb)
	sl["set"].call(b)
	inv.set_slot(hb, a)


## Shift-click (Java AbstractContainerMenu.quickMoveStack + moveItemStackTo): the stack goes to the slots of
## quick_order() - first merged into matching stacks in that order, then the remainder into the first empty slot that
## accepts it.
func quick_move(i: int) -> void:
	var sl: Dictionary = slots[i]
	if sl["output"]:
		take_output(i, true)
		return
	var st: ItemStack = sl["get"].call()
	if st.is_empty():
		return
	var order: Array = quick_order(i, st)
	for j in order:
		var tsl: Dictionary = slots[j]
		var ts: ItemStack = tsl["get"].call()
		if j != i and ts.can_merge(st) and ts.count < ts.max_stack():
			var mv := mini(ts.max_stack() - ts.count, st.count)
			ts.count += mv
			st.count -= mv
			if st.count <= 0:
				sl["set"].call(ItemStack.new())
				return
	for j in order:
		var tsl2: Dictionary = slots[j]
		if j != i and (tsl2["get"].call() as ItemStack).is_empty():
			var room := 1 if tsl2["section"] == 3 else st.max_stack()
			tsl2["set"].call(st.split(mini(room, st.count)))
			if st.count <= 0:
				sl["set"].call(ItemStack.new())
				return
			break
	sl["set"].call(st)


## Slot indices of one section, in slot order.
func _sec(section: int) -> Array:
	var out: Array = []
	for j in slots.size():
		if slots[j]["section"] == section and not slots[j]["output"]:
			out.append(j)
	return out


## An empty armor / offhand slot (section 3) that takes this item (Java: armor equips, a shield goes to the offhand).
func _equip_target(st: ItemStack) -> int:
	for j in _sec(3):
		var tsl: Dictionary = slots[j]
		var shield_slot := str(tsl.get("empty", "")) == "shield"
		if shield_slot and st.name() != "shield":
			continue
		if not shield_slot and not (tsl["filter"].is_valid() and tsl["filter"].call(st)):
			continue
		if (tsl["get"].call() as ItemStack).is_empty():
			return j
	return -1


## Java quickMoveStack target order: container -> player inventory from the last slot backwards (hotbar right to
## left first); armor / offhand -> main inventory then hotbar; player inventory -> the container slots that accept the
## item (furnace input / fuel ...), else equipment, else main <-> hotbar.
func quick_order(i: int, st: ItemStack) -> Array:
	var src: int = slots[i]["section"]
	if src == 0:
		var o := _sec(1) + _sec(2)
		o.reverse()
		return o
	if src == 3:
		return _sec(1) + _sec(2)
	var c: Array = []
	for j in _sec(0):
		if not slots[j]["filter"].is_valid() or slots[j]["filter"].call(st):
			c.append(j)
	if not c.is_empty():
		return c
	var eq := _equip_target(st)
	if eq >= 0:
		return [eq]
	return _sec(2) if src == 1 else _sec(1)


func has_section(s: int) -> bool:
	for sl in slots:
		if sl["section"] == s and not sl["output"]:
			return true
	return false


func take_output(_i: int, _all: bool) -> void:
	pass


func on_changed() -> void:
	pass


func on_close() -> void:
	var inv: Inventory = world.player.inventory
	if not inv.cursor.is_empty():
		var left := inv.add(inv.cursor)
		if left > 0:
			var d := inv.cursor.copy()
			d.count = left
			world.entities.spawn_item(world.player.eye_pos(), d)
		inv.cursor = ItemStack.new()
	inv.changed.emit()
