## StatsScreen — Java StatsScreen (`game.statistics`), 1.20 layout: title "Statistics" at y 20, McList y 32..h-64;
## buttons General | Items | Mobs (80 px at h-52: C-120 / C-40 / C+40) and Done (200 at h-28).
##  General: 10-px rows, name at +2 (white / 0x909090 alternating), value right-aligned at +215; Java StatFormatter
##   TIME / DISTANCE for play time and walked distance.
##  Items: 20-px rows (280 wide), header sprites statistics/header + block_mined / item_broken / item_crafted /
##   item_used / item_picked_up / item_dropped at column x = 75 + 40 i, item icon in a container/slot sprite, counts
##   right-aligned at each column (alternating colours). Recraft records mined / crafted / used ("-" otherwise).
##  Mobs: 36-px rows: name, "You killed N <mob>" / "You have never killed <mob>" (0x909090).
extends Control

var world
var on_close: Callable
var list: McList
var _mode := 0
var _rows: Array = []
var _title: Label
var _btns: Array = []
var _done: Button

const ICONS := ["block_mined", "item_broken", "item_crafted", "item_used", "item_picked_up", "item_dropped"]
const PREFIX := ["mined.", "", "crafted.", "used.", "", ""]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	_title = McW.text(Res.tr_key("gui.stats", "Statistics"), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	list = McList.new()
	list.draw_row = _draw_row
	list.draw.connect(_draw_header)
	add_child(list)
	for i in 3:
		var b := UiKit.button(Res.tr_key(["stat.generalButton", "stat.itemsButton", "stat.mobsButton"][i], ["General", "Items", "Mobs"][i]), func(): _show(i), 80)
		add_child(b)
		_btns.append(b)
	_done = UiKit.button(Res.tr_key("gui.done", "Done"), close, 200)
	add_child(_done)
	_layout()
	resized.connect(_layout)
	_show(0)


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(_title, 0, 20 - 1, gw, 9)
	McW.place(list, 0, 32, gw, maxf(0.0, gh - 64 - 32))
	for i in 3:
		McW.place(_btns[i], c - 120 + 80 * i, gh - 52, 80, 20)
	McW.place(_done, c - 100, gh - 28, 200, 20)


## Java StatFormatter.TIME (ticks).
static func fmt_time(ticks: int) -> String:
	var d := ticks / 20.0
	var e := d / 60.0
	var f := e / 60.0
	var g := f / 24.0
	var h := g / 365.0
	if h > 0.5:
		return "%.2f y" % h
	if g > 0.5:
		return "%.2f d" % g
	if f > 0.5:
		return "%.2f h" % f
	if e > 0.5:
		return "%.2f min" % e
	return "%.2f s" % d


## Java StatFormatter.DISTANCE (centimetres).
static func fmt_dist(cm: int) -> String:
	var m := cm / 100.0
	var km := m / 1000.0
	if km > 0.5:
		return "%.2f km" % km
	if m > 0.5:
		return "%.2f m" % m
	return "%d cm" % cm


func _show(i: int) -> void:
	_mode = i
	for k in 3:
		_btns[k].disabled = k == i
	var p = world.player
	var st: Dictionary = p.stats
	_rows = []
	match i:
		0:
			list.item_height = 10
			list.row_width = 220
			list.header_px = 0
			_rows.append([Res.tr_key("stat.minecraft.play_time", "Time Played"), fmt_time(int(st.get("play_time", 0)))])
			_rows.append([Res.tr_key("stat.minecraft.walk_one_cm", "Distance Walked"), fmt_dist(int(float(p.walk_dist) * 100.0))])
			var keys: Array = st.keys()
			keys.sort()
			for k in keys:
				var ks := str(k)
				if ks == "play_time" or ks.contains("."):
					continue
				_rows.append([Res.tr_key("stat.minecraft." + ks, ks.replace("_", " ").capitalize()), str(st[k])])
		1:
			list.item_height = 20
			list.row_width = 280
			list.header_px = 20
			var items := {}
			for k in st:
				var ks := str(k)
				for pre in ["mined.", "crafted.", "used."]:
					if ks.begins_with(pre):
						items[ks.substr(pre.length())] = true
			var names: Array = items.keys()
			names.sort()
			for n in names:
				_rows.append([n])
		2:
			list.item_height = 36
			list.row_width = 220
			list.header_px = 0
			var mobs: Array = []
			for k in st:
				if str(k).begins_with("killed."):
					mobs.append(str(k).substr(7))
			mobs.sort()
			for m in mobs:
				_rows.append([m, int(st["killed." + m])])
	list.set_count(_rows.size())
	list.sel = -1
	list.scroll = 0.0
	list._redraw()


func _draw_header() -> void:
	if _mode != 1:
		return
	var s := list.gs()
	var left := list.row_left()
	var y := 4.0 - list.scroll
	if y + 19.0 < 0.0:
		return
	var hs := UiKit.sprite("gui/sprites/statistics/header")
	for i in ICONS.size():
		var x := left + 75 + 40 * i - 18
		if hs != null:
			list.draw_texture_rect(hs, Rect2(Vector2(x, y + 1) * s, Vector2(18, 18) * s), false)
		var ic := UiKit.sprite("gui/sprites/statistics/" + ICONS[i])
		if ic != null:
			list.draw_texture_rect(ic, Rect2(Vector2(x, y + 1) * s, Vector2(18, 18) * s), false)


func _draw_row(l: McList, i: int, r: Rect2, _h: bool, _s: bool) -> void:
	var s := l.gs()
	var row: Array = _rows[i]
	var col := Color(1, 1, 1) if i % 2 == 0 else Color8(0x90, 0x90, 0x90)
	match _mode:
		0:
			l.text(r.position + Vector2(2, 1) * s, str(row[0]), col)
			var v := str(row[1])
			l.text(Vector2(r.position.x + (2 + 213 - McList.text_w(v)) * s, r.position.y + 1 * s), v, col)
		1:
			var name: String = row[0]
			var slot := UiKit.sprite("gui/sprites/container/slot")
			if slot != null:
				l.body.draw_texture_rect(slot, Rect2(r.position + Vector2(1, 1) * s, Vector2(18, 18) * s), false)
			var it := Res.items.id(name) if Res.items != null else -1
			if it >= 0:
				var ic := ItemIcons.icon(it)
				if ic != null:
					l.body.draw_texture_rect(ic, Rect2(r.position + Vector2(2, 2) * s, Vector2(16, 16) * s), false)
			var st: Dictionary = world.player.stats
			for c in ICONS.size():
				var pre: String = PREFIX[c]
				var v := "-"
				if pre != "" and st.has(pre + name):
					v = str(st[pre + name])
				var cc := Color(1, 1, 1) if c % 2 == 0 else Color8(0x90, 0x90, 0x90)
				l.text(Vector2(r.position.x + (75 + 40 * c - McList.text_w(v)) * s, r.position.y + 5 * s), v, cc)
		2:
			var mob: String = row[0]
			var n: int = row[1]
			var mn := Res.tr_key("entity.minecraft." + mob, mob.capitalize())
			l.text(r.position + Vector2(2, 1) * s, mn, Color(1, 1, 1))
			var t1 := Res.tr_fmt("stat_type.minecraft.killed", [n, mn], "You killed %s %s") if n > 0 else Res.tr_fmt("stat_type.minecraft.killed.none", [mn], "You have never killed %s")
			l.text(r.position + Vector2(12, 10) * s, t1, Color8(0x90, 0x90, 0x90))
			l.text(r.position + Vector2(12, 19) * s, Res.tr_fmt("stat_type.minecraft.killed_by.none", [mn], "You have never been killed by %s"), Color8(0x90, 0x90, 0x90))


func close() -> void:
	queue_free()
	if on_close.is_valid():
		on_close.call()


func on_escape() -> void:
	close()
