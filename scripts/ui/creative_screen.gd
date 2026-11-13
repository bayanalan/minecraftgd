## CreativeScreen — Java CreativeModeInventoryScreen with the user's 26.3 GUI assets:
## - 195 x 136 panel: gui/container/creative_inventory/tab_items (tab_item_search for Search, tab_inventory for the
##   Survival Inventory tab); category tabs (26 x 32 sprites tab_{top,bottom}_{selected,unselected}_<column + 1>) at
##   x = 27 * column (right-aligned tabs: 195 - 27 * (7 - column) + 1), top tabs 28 above the panel, bottom tabs
##   overlapping its bottom edge by 4; unselected tabs behind the panel, the selected one in front; tab icon at +5, +8 +-1.
## - 9 x 5 item grid at (9, 18), scroller (12 x 15) in the 112-high track at x 175, own hotbar row at y 112.
## - Search tab: edit box at (82, 6, 80, 9), live filter over every item. Saved Hotbars tab: 9 rows (C + 1..9 saves,
##   X + 1..9 loads; user://hotbars.json). Survival Inventory tab: Java's slot remap (armor 54/108 x 6/33, offhand
##   35,20, main 9+18c / 54+18r, hotbar y 112), player preview box (73,6)-(105,49), destroy-item slot (173, 112).
## Clicks: grid item left = a full stack, right = one, shift = a full stack into the inventory, clicking the grid with
## a carried stack deletes it; destroy slot deletes the carried stack (shift: clears the whole inventory).
## Tab contents: Java's per-tab lists are code, not data - categories here are a HEURISTIC over the item registry
## (registry order), recorded in docs/UI_REFERENCE_GAPS.md.
class_name CreativeScreen
extends ContainerUI

const W := 195
const H := 136
# [id, lang key, fallback title, row (0 top, 1 bottom), column, aligned right, icon item, background, kind]
# kind: 0 items, 1 saved hotbars, 2 search, 3 survival inventory
const TABS := [
	["building_blocks", "itemGroup.buildingBlocks", "Building Blocks", 0, 0, false, "bricks", "tab_items", 0],
	["colored_blocks", "itemGroup.coloredBlocks", "Colored Blocks", 0, 1, false, "cyan_wool", "tab_items", 0],
	["natural_blocks", "itemGroup.natural", "Natural Blocks", 0, 2, false, "grass_block", "tab_items", 0],
	["functional_blocks", "itemGroup.functional", "Functional Blocks", 0, 3, false, "oak_sign", "tab_items", 0],
	["redstone_blocks", "itemGroup.redstone", "Redstone Blocks", 0, 4, false, "redstone", "tab_items", 0],
	["hotbar", "itemGroup.hotbar", "Saved Hotbars", 0, 5, true, "bookshelf", "tab_items", 1],
	["search", "itemGroup.search", "Search Items", 0, 6, true, "compass", "tab_item_search", 2],
	["tools_and_utilities", "itemGroup.tools", "Tools & Utilities", 1, 0, false, "diamond_pickaxe", "tab_items", 0],
	["combat", "itemGroup.combat", "Combat", 1, 1, false, "netherite_sword", "tab_items", 0],
	["food_and_drinks", "itemGroup.foodAndDrink", "Food & Drinks", 1, 2, false, "golden_apple", "tab_items", 0],
	["ingredients", "itemGroup.ingredients", "Ingredients", 1, 3, false, "iron_ingot", "tab_items", 0],
	["spawn_eggs", "itemGroup.spawnEggs", "Spawn Eggs", 1, 4, false, "pig_spawn_egg", "tab_items", 0],
	["inventory", "itemGroup.inventory", "Survival Inventory", 1, 6, true, "chest", "tab_inventory", 3],
]
const HOTBARS_FILE := "user://hotbars.json"

static var selected := 0          # Java keeps the selected tab between openings
static var _tab_items: Dictionary = {}
static var _all_items: PackedInt32Array = PackedInt32Array()

var items: PackedInt32Array = PackedInt32Array()   # current tab / search result
var scroll := 0                                     # first visible row
var search: LineEdit
var _drag_scroll := false
var _bg: Dictionary = {}


func build() -> void:
	bg_size = Vector2(W, H)
	_ensure_lists()
	for k in ["tab_items", "tab_item_search", "tab_inventory"]:
		_bg[k] = UiKit.sprite("gui/container/creative_inventory/" + k)
	search = LineEdit.new()
	search.flat = true
	search.max_length = 50
	search.context_menu_enabled = false
	search.add_theme_color_override("font_color", Color.WHITE)
	search.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	search.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	search.add_theme_font_override("font", UiKit.font())
	# Java EditBox (no border on the tab texture): white text, white caret, inverted-blue selection
	search.add_theme_color_override("caret_color", Color.WHITE)
	search.add_theme_color_override("selection_color", Color(0.0, 0.0, 1.0, 0.75))
	search.add_theme_color_override("font_selected_color", Color.WHITE)
	search.focus_mode = Control.FOCUS_ALL
	search.text_changed.connect(func(_t): _refresh_items())
	add_child(search)
	_select(selected)


func _exit_tree() -> void:
	if InventoryPreview.cont != null and InventoryPreview.cont.get_parent() == self:
		InventoryPreview.detach()


func closes_on_inventory_key() -> bool:
	return not (search != null and search.visible and search.has_focus())


func _tab(i: int) -> Array:
	return TABS[i]


func _select(i: int) -> void:
	selected = clampi(i, 0, TABS.size() - 1)
	scroll = 0
	slots.clear()
	var kind: int = _tab(selected)[8]
	title = Res.tr_key(_tab(selected)[1], _tab(selected)[2]) if kind != 3 else ""
	search.visible = kind == 2
	if kind == 2:
		search.grab_focus()
	else:
		search.release_focus()
	var inv: Inventory = world.player.inventory
	if kind == 3:
		InventoryPreview.attach(self)
		for k in 4:
			# Java: armor slots 5..8 (helmet first) at 54 + (k / 2) * 54, 6 + (k % 2) * 27
			var ai := Inventory.ARMOR0 + 3 - k
			add_slot(Vector2(54 + (k / 2) * 54, 6 + (k % 2) * 27), inv.get_slot.bind(ai), inv.setter(ai), 3, false, _armor_filter.bind(3 - k), ["helmet", "chestplate", "leggings", "boots"][k])
		add_slot(Vector2(35, 20), inv.get_slot.bind(Inventory.OFFHAND), inv.setter(Inventory.OFFHAND), 3, false, Callable(), "shield")
		for r in 3:
			for c in 9:
				var mi := 9 + r * 9 + c
				add_slot(Vector2(9 + c * 18, 54 + r * 18), inv.get_slot.bind(mi), inv.setter(mi), 1)
	else:
		InventoryPreview.detach()
		for r in 5:
			for c in 9:
				add_slot(Vector2(9 + c * 18, 18 + r * 18), _grid_get.bind(r * 9 + c), func(_s): pass, 4, true)
	for c in 9:
		add_slot(Vector2(9 + c * 18, 112), inv.get_slot.bind(c), inv.setter(c), 2)
	_refresh_items()


func _refresh_items() -> void:
	var kind: int = _tab(selected)[8]
	match kind:
		0:
			items = _tab_items.get(_tab(selected)[0], PackedInt32Array())
		2:
			var q := search.text.strip_edges().to_lower() if search != null else ""
			if q == "":
				items = _all_items
			else:
				var out := PackedInt32Array()
				for i in _all_items:
					if Res.items.names[i].contains(q) or Res.items.display_name(i).to_lower().contains(q):
						out.append(i)
				items = out
		_:
			items = PackedInt32Array()
	scroll = clampi(scroll, 0, _max_scroll())


func _rows() -> int:
	if _tab(selected)[8] == 1:
		return 9
	return int(ceil(items.size() / 9.0))


func _max_scroll() -> int:
	return maxi(0, _rows() - 5)


func _grid_get(idx: int) -> ItemStack:
	var kind: int = _tab(selected)[8]
	var r := scroll + idx / 9
	var c := idx % 9
	if kind == 1:
		var rows := _load_hotbars()
		if r < 9:
			var row: Array = rows[r]
			if row.is_empty():
				return ItemStack.named("paper", 1) if c == r else ItemStack.new()
			if c < row.size() and row[c] is Dictionary:
				return ItemStack.from_dict(row[c])
		return ItemStack.new()
	var j := r * 9 + c
	return ItemStack.of(items[j], 1) if j < items.size() else ItemStack.new()


# ---------------------------------------------------------------- clicks

func click(i: int, right: bool) -> void:
	var sl: Dictionary = slots[i]
	if sl["section"] == 4:
		var inv: Inventory = world.player.inventory
		if not inv.cursor.is_empty():
			inv.cursor = ItemStack.new()   # Java: dropping a carried stack on the creative grid deletes it
			return
		var st: ItemStack = sl["get"].call()
		if st.is_empty():
			return
		var cp := st.copy()
		cp.count = 1 if right else cp.max_stack()
		inv.cursor = cp
		return
	super.click(i, right)


func _armor_filter(st: ItemStack, slot: int) -> bool:
	var n := st.name()
	return Res.items.armor_slot[st.item] == slot or (slot == 3 and (n == "carved_pumpkin" or n.ends_with("_head") or n.ends_with("_skull")))


func quick_move(i: int) -> void:
	if slots[i]["section"] == 2 and _tab(selected)[8] != 3:
		slots[i]["set"].call(ItemStack.new())   # Java ItemPickerMenu.quickMoveStack: shift-click clears a hotbar slot
		return
	if slots[i]["section"] == 4:
		var st: ItemStack = slots[i]["get"].call()
		if not st.is_empty():
			var cp := st.copy()
			cp.count = cp.max_stack()
			world.player.inventory.add(cp)
		return
	super.quick_move(i)


func take_output(i: int, _all: bool) -> void:
	click(i, false)


func _destroy_rect(o: Vector2) -> Rect2:
	return Rect2(o + Vector2(173, 112), Vector2(16, 16))


func _tab_pos(i: int) -> Vector2:
	var t := _tab(i)
	var col: int = t[4]
	var x := 27 * col
	if t[5]:
		x = W - 27 * (7 - col) + 1
	return Vector2(x, -28 if t[3] == 0 else H - 4)


func _tab_hit(i: int, p: Vector2) -> bool:
	# Java checkTabClicked: 26 x 32 from y -32 (top) / imageHeight (bottom)
	var t := _tab(i)
	var tp := _tab_pos(i)
	var y0 := -32.0 if t[3] == 0 else float(H)
	return p.x >= tp.x and p.x <= tp.x + 26 and p.y >= y0 and p.y <= y0 + 32


func _gui_input(event: InputEvent) -> void:
	var s := UiKit.scale()
	var o := origin()
	var mp: Vector2 = get_local_mouse_position() / s - o
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll = clampi(scroll + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, _max_scroll())
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			for i in TABS.size():
				if _tab_hit(i, mp):
					if i != selected:
						_select(i)
						Audio.play("ui.button.click", world.player.pos, "Master", 0.25)
					accept_event()
					return
			if _tab(selected)[8] != 3 and Rect2(Vector2(175, 18), Vector2(12, 112)).has_point(mp):
				_drag_scroll = true
				_scroll_to(mp.y)
				accept_event()
				return
			if _tab(selected)[8] == 3 and _destroy_rect(Vector2.ZERO).has_point(mp):
				var inv: Inventory = world.player.inventory
				if Input.is_key_pressed(KEY_SHIFT):
					for k in Inventory.SIZE:
						inv.set_slot(k, ItemStack.new())
				inv.cursor = ItemStack.new()
				accept_event()
				return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drag_scroll = false
	if event is InputEventMouseMotion and _drag_scroll:
		_scroll_to(mp.y)
		accept_event()
		return
	if event is InputEventKey and event.pressed and _tab(selected)[8] == 2 and search.has_focus():
		return   # typing goes to the search box
	super._gui_input(event)
	if _tab(selected)[8] == 2 and search != null and search.visible and not search.has_focus():
		search.grab_focus()   # Java: the search box cannot lose focus on the Search tab (setCanLoseFocus(false))


func _scroll_to(y: float) -> void:
	var f := clampf((y - 18.0 - 7.5) / (112.0 - 15.0), 0.0, 1.0)
	scroll = int(roundf(f * _max_scroll()))


# ---------------------------------------------------------------- drawing

func _process(d: float) -> void:
	super._process(d)
	var s := UiKit.scale()
	var o := origin()
	if search != null and search.visible:
		search.position = (o + Vector2(82, 5)) * s
		search.size = Vector2(80, 11) * s
		search.add_theme_font_size_override("font_size", 8 * s)
	if _tab(selected)[8] == 3 and InventoryPreview.cont != null and InventoryPreview.cont.get_parent() == self:
		InventoryPreview.cont.position = (o + Vector2(73, 6)) * s
		InventoryPreview.cont.size = Vector2(32, 43) * s
		InventoryPreview.follow_mouse(get_local_mouse_position() / s, o + Vector2(89, 27.5))


func _draw() -> void:
	var s := UiKit.scale()
	_ensure_overlay()
	_over_cursor = null
	_over_tip = []
	draw_dim()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var o := origin()
	var font := UiKit.font()
	# unselected tabs behind the panel
	for i in TABS.size():
		if i != selected:
			_draw_tab(i, o, false)
	var bg: Texture2D = _bg.get(_tab(selected)[7])
	if bg != null:
		draw_texture_rect_region(bg, Rect2(o, Vector2(W, H)), Rect2(Vector2.ZERO, Vector2(W, H)))
	else:
		draw_rect(Rect2(o, Vector2(W, H)), Color(0.78, 0.78, 0.78))
	_draw_tab(selected, o, true)
	if title != "":
		draw_string(font, o + Vector2(8, 6 + 7), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(0x40, 0x40, 0x40))
	# scroller
	if _tab(selected)[8] != 3:
		var can := _max_scroll() > 0
		var sc := UiKit.sprite("gui/sprites/container/creative_inventory/scroller" + ("" if can else "_disabled"))
		var y := 18.0 + (112.0 - 17.0) * (float(scroll) / _max_scroll() if can else 0.0)
		if sc != null:
			draw_texture_rect(sc, Rect2(o + Vector2(175, y), Vector2(12, 15)), false)
	var mp := get_local_mouse_position() / s
	hover = -1
	for i in slots.size():
		var sl: Dictionary = slots[i]
		var p: Vector2 = o + sl["pos"]
		var sst: ItemStack = sl["get"].call()
		if sst.is_empty() and str(sl.get("empty", "")) != "":
			var ei := UiKit.sprite("gui/sprites/container/slot/" + str(sl["empty"]))
			if ei != null:
				draw_texture_rect(ei, Rect2(p, Vector2(16, 16)), false)
		_draw_stack(sst, p, font)
		if Rect2(p, Vector2(16, 16)).has_point(mp):
			hover = i
			draw_rect(Rect2(p, Vector2(16, 16)), Color(1, 1, 1, 0.5))
	if _tab(selected)[8] == 3 and _destroy_rect(o).has_point(mp):
		draw_rect(_destroy_rect(o), Color(1, 1, 1, 0.5))
	var inv: Inventory = world.player.inventory
	if not inv.cursor.is_empty():
		overlay_cursor(inv.cursor, mp)
		return
	# Java tooltips (sprite background / frame, item lines like the survival screens)
	var tip: Array = []
	for i in TABS.size():
		if _tab_hit(i, mp - o):
			tip = [[Res.tr_key(_tab(i)[1], _tab(i)[2]), Color.WHITE]]
	if tip.is_empty() and _tab(selected)[8] == 3 and _destroy_rect(o).has_point(mp):
		tip = [[Res.tr_key("inventory.binSlot", "Destroy Item"), Color.WHITE]]
	if tip.is_empty() and hover >= 0:
		var hs: ItemStack = slots[hover]["get"].call()
		if not hs.is_empty():
			tip = item_tooltip(hs)
			if _tab(selected)[8] == 1 and hs.name() == "paper" and slots[hover]["section"] == 4:
				tip = [[Res.tr_key("inventory.hotbarInfo", "Save hotbar with %s+%s") % ["C", str(scroll + hover / 9 + 1)], Color.WHITE]]
	if not tip.is_empty():
		overlay_tip(tip, mp)


func _draw_tab(i: int, o: Vector2, sel: bool) -> void:
	var t := _tab(i)
	var top: bool = t[3] == 0
	var tp := o + _tab_pos(i)
	var name := "tab_%s_%s_%d" % ["top" if top else "bottom", "selected" if sel else "unselected", clampi(int(t[4]), 0, 6) + 1]
	var spr := UiKit.sprite("gui/sprites/container/creative_inventory/" + name)
	if spr != null:
		draw_texture_rect(spr, Rect2(tp, Vector2(26, 32)), false)
	var icon := ItemIcons.icon(Res.items.id(t[6]))
	if icon != null:
		draw_texture_rect(icon, Rect2(tp + Vector2(5, 8 + (1 if top else -1)), Vector2(16, 16)), false)


# ---------------------------------------------------------------- saved hotbars (Java hotbar.nbt)

static func _load_hotbars() -> Array:
	var rows: Array = []
	if FileAccess.file_exists(HOTBARS_FILE):
		var j = JSON.parse_string(FileAccess.get_file_as_string(HOTBARS_FILE))
		if j is Array:
			rows = j
	while rows.size() < 9:
		rows.append([])
	return rows


## C + n: save the player's hotbar into row n; X + n: load row n (creative).
static func save_hotbar(inv: Inventory, row: int) -> void:
	var rows := _load_hotbars()
	var out: Array = []
	for c in 9:
		out.append(inv.get_slot(c).to_dict())
	rows[row] = out
	var f := FileAccess.open(HOTBARS_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(rows))


static func load_hotbar(inv: Inventory, row: int) -> void:
	var r: Array = _load_hotbars()[row]
	for c in 9:
		inv.set_slot(c, ItemStack.from_dict(r[c]) if c < r.size() and r[c] is Dictionary else ItemStack.new())


# ---------------------------------------------------------------- tab contents (heuristic categories)

## Java CreativeModeTabs order (CreativeTabs lists); registry items those lists do not name follow in their best-guess
## tab; spawn eggs after the spawner / trial spawner; Search = all tabs in order, each item once.
static func _ensure_lists() -> void:
	if not _tab_items.is_empty():
		return
	var lists := {}
	for t in TABS:
		lists[t[0]] = PackedInt32Array()
	var placed := {}
	var named := CreativeTabs.lists()
	for tab in named:
		var arr: PackedInt32Array = lists[tab]
		var seen := {}
		for nm in named[tab]:
			var id := Res.items.id(nm)
			if id > 0 and not seen.has(id) and not (nm in OP_ITEMS):
				seen[id] = true
				arr.append(id)
				placed[id] = true
		lists[tab] = arr
	var extra := {}
	for t in TABS:
		extra[t[0]] = PackedInt32Array()
	for i in range(1, Res.items.names.size()):
		var n: String = Res.items.names[i]
		if n == "air" or n in OP_ITEMS or placed.has(i) or n in CreativeTabs.EXCLUDED or n == "spawner" or n == "trial_spawner":
			continue
		if n.ends_with("_spawn_egg") and not (MobRegistry.DEFS.has(n.trim_suffix("_spawn_egg")) or MobRegistry.get_def(n.trim_suffix("_spawn_egg")).size() > 0):
			continue
		var cat := category(i)
		if extra.has(cat):
			var ea: PackedInt32Array = extra[cat]   # packed arrays are values: write the appended copy back
			ea.append(i)
			extra[cat] = ea
	for k in lists:
		var base: PackedInt32Array = lists[k]
		if k == "spawn_eggs":
			for sp in ["spawner", "trial_spawner"]:
				if Res.items.id(sp) > 0 and not placed.has(Res.items.id(sp)):
					base.append(Res.items.id(sp))
			base.append_array(extra[k])   # registry (alphabetical) order
		else:
			base.append_array(_sorted(extra[k]))
		lists[k] = base
	var all := PackedInt32Array()
	var in_all := {}
	for t in TABS:
		if int(t[8]) != 0:
			continue
		for id2 in lists[t[0]]:
			if not in_all.has(id2):
				in_all[id2] = true
				all.append(id2)
	_all_items = all
	_tab_items = lists


const OP_ITEMS := ["command_block", "chain_command_block", "repeating_command_block", "command_block_minecart", "structure_block",
	"structure_void", "jigsaw", "barrier", "light", "debug_stick", "test_block", "test_instance_block", "knowledge_book"]
const COLORS := ["white", "light_gray", "gray", "black", "brown", "red", "orange", "yellow", "lime", "green", "cyan", "light_blue", "blue",
	"purple", "magenta", "pink"]
const REDSTONE := ["redstone", "redstone_torch", "redstone_block", "repeater", "comparator", "target", "lever", "lightning_rod",
	"daylight_detector", "sculk_sensor", "calibrated_sculk_sensor", "tripwire_hook", "trapped_chest", "tnt", "redstone_lamp", "note_block",
	"observer", "piston", "sticky_piston", "slime_block", "honey_block", "dispenser", "dropper", "crafter", "hopper", "rail", "powered_rail",
	"detector_rail", "activator_rail", "minecart", "hopper_minecart", "chest_minecart", "furnace_minecart", "tnt_minecart"]
const FUNCTIONAL := ["crafting_table", "furnace", "smoker", "blast_furnace", "campfire", "soul_campfire", "anvil", "chipped_anvil",
	"damaged_anvil", "grindstone", "smithing_table", "stonecutter", "loom", "cartography_table", "fletching_table", "composter", "barrel",
	"chest", "ender_chest", "enchanting_table", "brewing_stand", "cauldron", "bell", "beacon", "conduit", "lodestone", "respawn_anchor",
	"jukebox", "lectern", "bookshelf", "chiseled_bookshelf", "ladder", "scaffolding", "flower_pot", "decorated_pot", "armor_stand",
	"item_frame", "glow_item_frame", "painting", "end_crystal", "end_portal_frame", "dragon_egg", "spawner", "trial_spawner", "vault",
	"torch", "soul_torch", "lantern", "soul_lantern", "chain", "iron_bars", "beehive", "bee_nest", "suspicious_sand", "suspicious_gravel",
	"sponge", "wet_sponge", "glowstone", "sea_lantern", "shroomlight", "end_rod", "copper_torch", "copper_lantern", "heavy_core",
	"creaking_heart", "infested_stone", "infested_cobblestone", "infested_stone_bricks", "infested_deepslate", "pale_moss_carpet", "copper_chain"]
const NATURAL_HINTS := ["grass_block", "dirt", "coarse_dirt", "rooted_dirt", "podzol", "mycelium", "mud", "clay", "gravel", "sand", "red_sand",
	"ice", "packed_ice", "blue_ice", "snow", "snow_block", "powder_snow_bucket", "moss_block", "moss_carpet", "pale_moss_block", "cactus",
	"pumpkin", "carved_pumpkin", "jack_o_lantern", "melon", "hay_block", "bone_block", "dripstone_block", "pointed_dripstone", "calcite",
	"tuff", "amethyst_block", "budding_amethyst", "obsidian", "crying_obsidian", "magma_block", "netherrack", "soul_sand", "soul_soil",
	"basalt", "blackstone", "end_stone", "glowstone", "sculk", "sculk_vein", "sculk_catalyst", "sculk_shrieker", "sniffer_egg", "frogspawn",
	"turtle_egg", "lily_pad", "seagrass", "kelp", "sugar_cane", "bamboo", "vine", "glow_lichen", "hanging_roots", "spore_blossom",
	"big_dripleaf", "small_dripleaf", "azalea", "flowering_azalea", "chorus_plant", "chorus_flower", "cobweb", "bedrock", "stone",
	"deepslate", "granite", "diorite", "andesite", "leaf_litter", "firefly_bush", "bush", "short_dry_grass", "tall_dry_grass", "cactus_flower",
	"wildflowers", "pink_petals", "resin_clump", "pale_hanging_moss", "open_eyeblossom", "closed_eyeblossom", "dried_ghast", "pitcher_plant",
	"torchflower", "sweet_berries", "glow_berries", "nether_wart", "warped_wart_block", "nether_wart_block", "crimson_nylium", "warped_nylium"]


## Best-effort Java tab for an item (the real lists are code in CreativeModeTabs; not data in the jar).
static func category(i: int) -> String:
	var n: String = Res.items.names[i]
	if n.ends_with("_spawn_egg"):
		return "spawn_eggs"
	if n in REDSTONE or n.ends_with("_button") or n.ends_with("_pressure_plate") or n.ends_with("copper_bulb") or n == "redstone_wire":
		return "redstone_blocks"
	var col := false
	for c in COLORS:
		if n.begins_with(c + "_"):
			col = true
			break
	if col and (n.ends_with("_wool") or n.ends_with("_carpet") or n.ends_with("_terracotta") or n.ends_with("_concrete") or n.ends_with("_concrete_powder")
			or n.ends_with("_stained_glass") or n.ends_with("_stained_glass_pane") or n.ends_with("_shulker_box") or n.ends_with("_bed")
			or n.ends_with("_candle") or n.ends_with("_banner") or n.ends_with("_glazed_terracotta") or n.ends_with("_harness") or n.ends_with("_bundle")):
		return "colored_blocks"
	if n in ["terracotta", "glass", "glass_pane", "tinted_glass", "candle", "shulker_box", "white_wool"]:
		return "colored_blocks"
	if n in FUNCTIONAL or n.ends_with("_sign") or n.ends_with("_hanging_sign") or n.ends_with("_head") or n.ends_with("_skull") or n.ends_with("_shelf"):
		return "functional_blocks"
	var it := Res.items
	if it.armor_slot[i] >= 0 or n.ends_with("_sword") or n in ["bow", "crossbow", "trident", "mace", "shield", "arrow", "spectral_arrow",
			"tipped_arrow", "totem_of_undying", "snowball", "egg", "blue_egg", "brown_egg", "wind_charge", "firework_rocket", "elytra"] or n.ends_with("_horse_armor") or n == "wolf_armor":
		return "combat"
	if it.tool_kind[i] != "" or n.ends_with("_bucket") or n == "bucket" or n.ends_with("_boat") or n.ends_with("_raft") or n.ends_with("_chest_boat") or n.ends_with("_chest_raft") \
			or n.begins_with("music_disc") or n in ["shears", "flint_and_steel", "fishing_rod", "carrot_on_a_stick", "warped_fungus_on_a_stick", "brush",
			"compass", "recovery_compass", "clock", "spyglass", "map", "filled_map", "lead", "name_tag", "saddle", "bundle", "writable_book", "written_book",
			"ender_pearl", "ender_eye", "goat_horn", "bone_meal"]:
		return "tools_and_utilities"
	if it.food_nutrition[i] > 0 or n in ["potion", "splash_potion", "lingering_potion", "milk_bucket", "honey_bottle", "cake", "ominous_bottle"]:
		return "food_and_drinks"
	if it.place_block[i] >= 0:
		if n in NATURAL_HINTS or n.ends_with("_ore") or n.begins_with("raw_") and n.ends_with("_block") or n.ends_with("_log") or n.ends_with("_stem") \
				or n.ends_with("_leaves") or n.ends_with("_sapling") or n.ends_with("_propagule") or n.ends_with("_mushroom") or n.ends_with("_fungus") \
				or n.ends_with("_roots") or n.ends_with("_coral") or n.ends_with("_coral_block") or n.ends_with("_coral_fan") or n.ends_with("_seeds") \
				or n.ends_with("_tulip") or n in ["dandelion", "poppy", "blue_orchid", "allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley",
				"wither_rose", "sunflower", "lilac", "rose_bush", "peony", "short_grass", "tall_grass", "fern", "large_fern", "dead_bush", "mangrove_roots",
				"muddy_mangrove_roots", "red_mushroom_block", "brown_mushroom_block", "mushroom_stem", "sea_pickle", "twisting_vines", "weeping_vines"]:
			return "natural_blocks"
		return "building_blocks"
	return "ingredients"


# ---------------------------------------------------------------- tab order (approximating Java's hand-written lists)
const WOODS := ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "pale_oak", "bamboo", "crimson", "warped", "poplar"]
const WOOD_PARTS := ["_log", "_stem", "_block", "_wood", "_hyphae", "stripped_", "_planks", "_mosaic", "_stairs", "_slab", "_fence", "_fence_gate",
	"_door", "_trapdoor", "_pressure_plate", "_button", "_sign", "_hanging_sign", "_boat", "_raft", "_leaves", "_sapling"]
const STONES := ["stone", "cobblestone", "mossy_cobblestone", "smooth_stone", "stone_brick", "cracked_stone", "chiseled_stone", "mossy_stone",
	"granite", "polished_granite", "diorite", "polished_diorite", "andesite", "polished_andesite", "deepslate", "cobbled_deepslate", "chiseled_deepslate",
	"polished_deepslate", "deepslate_brick", "cracked_deepslate_brick", "deepslate_tile", "cracked_deepslate_tile", "reinforced_deepslate", "tuff",
	"polished_tuff", "chiseled_tuff", "tuff_brick", "brick", "packed_mud", "mud_brick", "resin_brick", "chiseled_resin", "sandstone", "chiseled_sandstone",
	"cut_sandstone", "smooth_sandstone", "red_sandstone", "chiseled_red_sandstone", "cut_red_sandstone", "smooth_red_sandstone", "sea_lantern",
	"prismarine", "dark_prismarine", "netherrack", "nether_brick", "cracked_nether_brick", "chiseled_nether_brick", "red_nether_brick", "basalt",
	"smooth_basalt", "polished_basalt", "blackstone", "gilded_blackstone", "polished_blackstone", "chiseled_polished_blackstone", "cracked_polished_blackstone",
	"end_stone", "purpur", "quartz", "chiseled_quartz", "smooth_quartz", "coal_block", "iron", "gold", "redstone_block", "emerald_block", "lapis",
	"diamond_block", "netherite_block", "amethyst", "copper", "exposed_copper", "weathered_copper", "oxidized_copper", "cut_copper", "waxed"]
const COLOR_PARTS := ["_wool", "_carpet", "terracotta", "_concrete", "_concrete_powder", "_glazed_terracotta", "glass", "_glass_pane", "shulker_box",
	"_bed", "candle", "_banner", "_harness", "_bundle", "_dye"]


static func _sort_key(n: String) -> String:
	for wi in WOODS.size():
		var w: String = WOODS[wi]
		if n.begins_with(w + "_") or n.begins_with("stripped_" + w + "_"):
			var part := WOOD_PARTS.size()
			for pi in WOOD_PARTS.size():
				if n.contains(WOOD_PARTS[pi]):
					part = pi
					if WOOD_PARTS[pi] == "stripped_":
						part = 5 + (1 if n.ends_with("_wood") or n.ends_with("_hyphae") else 0)
					break
			return "0_%02d_%02d_%s" % [wi, part, n]
	for ci in COLORS.size():
		var c: String = COLORS[ci]
		if n.begins_with(c + "_"):
			var tp := COLOR_PARTS.size()
			for pi in COLOR_PARTS.size():
				if n.ends_with(COLOR_PARTS[pi]) or n.contains(COLOR_PARTS[pi] + "_"):
					tp = pi
			return "1_%02d_%02d_%s" % [tp, ci, n]
	for si in range(STONES.size() - 1, -1, -1):
		if n.begins_with(STONES[si]):
			return "2_%03d_%s" % [si, n]
	return "3_" + n


static func _sorted(arr: PackedInt32Array) -> PackedInt32Array:
	var ids: Array = Array(arr)
	var keys := {}
	for i in ids:
		keys[i] = _sort_key(Res.items.names[i])
	ids.sort_custom(func(a, b): return keys[a] < keys[b])
	return PackedInt32Array(ids)