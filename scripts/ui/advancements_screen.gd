## AdvancementsScreen — Java AdvancementsScreen (`game.advancements`): window gui/advancements/window.png (252 x 140)
## centred, title "Advancements" (0x404040) at (8, 6); tabs above the window (advancements/tab_above_left / middle /
## right [_selected], 28 x 32 every 32 px, icon at +6, +9; unselected behind the window, selected in front); inside
## area (9, 18) 234 x 113: the tab root's background texture tiled 16 x 16 with the scroll offset, connector lines
## (black 3-px shadow then white 1-px), advancement frames (task / goal / challenge _frame_(un)obtained, 26 x 26 at
## widget x + 3) with the item icon at +8 / +5. Widget positions: Java TreeNodePosition (Walker / Buchheim tree
## layout) x * 28, y * 27. Visibility: Java AdvancementVisibilityEvaluator (done, ancestors of done nodes, and nodes
## within two levels below a done one unless hidden). Drag to pan (only along axes wider than the area); hover shows
## the title + description tooltip (vanilla draws its title_box widget there). Esc returns to the parent screen.
extends Control

var world
var on_close: Callable
var _tabs: Array = []       # [{root, title, icon, bg, nodes: {id: {x, y, parent, frame, icon, done, title, desc}}, minx.., scroll}]
var _sel := 0
var _drag := false
var _last := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	for ch in get_children():
		(ch as CanvasItem).show_behind_parent = true   # this screen draws in _draw(): keep blur / tiles under it
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(queue_redraw)


# ---------------------------------------------------------------- data + layout

func _build() -> void:
	var adv = world.advancements
	if adv == null:
		return
	var defs: Dictionary = adv.defs
	var children := {}
	for id in defs:
		var par := str(defs[id]["parent"])
		if par != "":
			if not children.has(par):
				children[par] = []
			children[par].append(id)
	for k in children:
		(children[k] as Array).sort()
	# visibility (Java AdvancementVisibilityEvaluator): rule per node SHOW (done) / HIDE (hidden or no display, not
	# done) / NO_CHANGE; an unfinished node is visible when the nearest decisive rule among itself, its parent and
	# grandparent is SHOW; any node with a done descendant is visible
	var visible := {}
	var rule := func(id: String) -> int:
		var d: Dictionary = defs[id]
		if not bool(d.get("display", true)):
			return -1
		if adv.done.has(id):
			return 1
		return -1 if bool(d["hidden"]) else 0
	var eval := func(f: Callable, id: String, stack: Array) -> bool:
		var done: bool = adv.done.has(id)
		stack.append(rule.call(id))
		var sub := done
		for c in children.get(id, []):
			sub = f.call(f, c, stack) or sub
		stack.pop_back()
		var vis := sub
		if not vis:
			# own rule, then parent (stack top after the pop) and grandparent
			for k in 3:
				var r: int = rule.call(id) if k == 0 else (stack[stack.size() - k] if stack.size() - k >= 0 else 0)
				if r == 1:
					vis = true
					break
				if r == -1:
					break
		if vis and bool(defs[id].get("display", true)):
			visible[id] = true
		return sub
	var roots: Array = []
	for id in defs:
		if str(defs[id]["parent"]) == "" and bool(defs[id].get("display", true)):
			roots.append(id)
	# Java tab order: story, nether, end, adventure, husbandry (registration order)
	var order := ["story", "nether", "end", "adventure", "husbandry"]
	roots.sort_custom(func(a, b): return order.find(str(a).split("/")[0]) < order.find(str(b).split("/")[0]))
	for r in roots:
		eval.call(eval, r, [0, 0, 0])
		if not visible.has(r):
			continue
		var pos := {}
		var tn := TreeNode.new(r, null, null, 1, 0, defs, children, visible)
		tn.first_walk()
		var mn := tn.second_walk(0.0, 0, tn.y)
		if mn < 0.0:
			tn.third_walk(-mn)
		tn.collect(pos)
		var nodes := {}
		var minx := INF
		var maxx := -INF
		var miny := INF
		var maxy := -INF
		for id in pos:
			var d: Dictionary = defs[id]
			var x := floorf(pos[id].x * 28.0)
			var y := floorf(pos[id].y * 27.0)
			nodes[id] = {"x": x, "y": y, "parent": str(d["parent"]) if pos.has(str(d["parent"])) else "", "frame": str(d["frame"]),
				"icon": str(d["icon"]).trim_prefix("minecraft:"), "done": adv.done.has(id), "title": str(d["title"]), "desc": str(d["desc"])}
			minx = minf(minx, x)
			maxx = maxf(maxx, x + 28.0)
			miny = minf(miny, y)
			maxy = maxf(maxy, y + 27.0)
		var bg := str(defs[r].get("background", ""))
		_tabs.append({"root": r, "title": str(defs[r]["title"]), "icon": str(defs[r]["icon"]).trim_prefix("minecraft:"),
			"bg": bg.trim_suffix(".png").trim_prefix("textures/"), "nodes": nodes, "minx": minx, "maxx": maxx, "miny": miny, "maxy": maxy,
			"sx": floorf(117.0 - (maxx + minx) / 2.0), "sy": floorf(56.0 - (maxy + miny) / 2.0)})


## Java TreeNodePosition: Walker's algorithm with Buchheim's linear-time improvements (x = depth, y = sibling axis).
class TreeNode:
	var id: String
	var parent: TreeNode
	var prev: TreeNode
	var child_index: int
	var children: Array = []
	var ancestor: TreeNode
	var thread: TreeNode
	var x := 0
	var y := -1.0
	var mod := 0.0
	var change := 0.0
	var shift := 0.0

	func _init(p_id: String, p_parent: TreeNode, p_prev: TreeNode, p_index: int, p_x: int, defs: Dictionary, kids: Dictionary, vis: Dictionary) -> void:
		id = p_id
		parent = p_parent
		prev = p_prev
		child_index = p_index
		x = p_x
		ancestor = self
		var last: TreeNode = null
		for c in kids.get(id, []):
			last = _add_child(c, last, defs, kids, vis)

	func _add_child(cid: String, last: TreeNode, defs: Dictionary, kids: Dictionary, vis: Dictionary) -> TreeNode:
		if vis.has(cid):
			last = TreeNode.new(cid, self, last, children.size() + 1, x + 1, defs, kids, vis)
			children.append(last)
		else:
			for c in kids.get(cid, []):
				last = _add_child(c, last, defs, kids, vis)
		return last

	func first_walk() -> void:
		if children.is_empty():
			y = prev.y + 1.0 if prev != null else 0.0
			return
		var def_anc: TreeNode = null
		for c in children:
			c.first_walk()
			def_anc = c.apportion(c if def_anc == null else def_anc)
		execute_shifts()
		var f: float = (children[0].y + children[children.size() - 1].y) / 2.0
		if prev != null:
			y = prev.y + 1.0
			mod = y - f
		else:
			y = f

	func second_walk(f: float, i: int, g: float) -> float:
		y += f
		x = i
		if y < g:
			g = y
		for c in children:
			g = c.second_walk(f + mod, i + 1, g)
		return g

	func third_walk(f: float) -> void:
		y += f
		for c in children:
			c.third_walk(f)

	func execute_shifts() -> void:
		var f := 0.0
		var g := 0.0
		for i in range(children.size() - 1, -1, -1):
			var c: TreeNode = children[i]
			c.y += f
			c.mod += f
			g += c.change
			f += c.shift + g

	func prev_or_thread() -> TreeNode:
		if thread != null:
			return thread
		return children[0] if not children.is_empty() else null

	func next_or_thread() -> TreeNode:
		if thread != null:
			return thread
		return children[children.size() - 1] if not children.is_empty() else null

	func apportion(def_anc: TreeNode) -> TreeNode:
		if prev == null:
			return def_anc
		var vir: TreeNode = self
		var vor: TreeNode = self
		var vil: TreeNode = prev
		var vol: TreeNode = parent.children[0]
		var sir := mod
		var sor := mod
		var sil := vil.mod
		var sol := vol.mod
		while vil.next_or_thread() != null and vir.prev_or_thread() != null:
			vil = vil.next_or_thread()
			vir = vir.prev_or_thread()
			vol = vol.prev_or_thread()
			vor = vor.next_or_thread()
			vor.ancestor = self
			var sh := vil.y + sil - (vir.y + sir) + 1.0
			if sh > 0.0:
				vil.get_ancestor(self, def_anc).move_subtree(self, sh)
				sir += sh
				sor += sh
			sil += vil.mod
			sir += vir.mod
			sol += vol.mod
			sor += vor.mod
		if vil.next_or_thread() != null and vor.next_or_thread() == null:
			vor.thread = vil.next_or_thread()
			vor.mod += sil - sor
		else:
			if vir.prev_or_thread() != null and vol.prev_or_thread() == null:
				vol.thread = vir.prev_or_thread()
				vol.mod += sir - sol
			def_anc = self
		return def_anc

	func move_subtree(other: TreeNode, f: float) -> void:
		var g := float(other.child_index - child_index)
		if g != 0.0:
			other.change -= f / g
			change += f / g
		other.shift += f
		other.y += f
		other.mod += f

	func get_ancestor(other: TreeNode, def_anc: TreeNode) -> TreeNode:
		return ancestor if ancestor != null and other.parent.children.has(ancestor) else def_anc

	func collect(out: Dictionary) -> void:
		out[id] = Vector2(x, y)
		for c in children:
			c.collect(out)


# ---------------------------------------------------------------- drawing

func _win() -> Vector2:
	var s := float(UiKit.scale())
	return Vector2(floorf((size.x / s - 252.0) / 2.0), floorf((size.y / s - 140.0) / 2.0))


func _tab_rect(i: int) -> Rect2:
	var w := _win()
	return Rect2(w + Vector2(32 * i, -28), Vector2(28, 32))


func _draw() -> void:
	var s := float(UiKit.scale())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var w := _win()
	var mp := get_local_mouse_position() / s
	for i in _tabs.size():
		if i != _sel:
			_draw_tab(i, false)
	var inside := Rect2(w + Vector2(9, 18), Vector2(234, 113))
	var tip: Array = []
	if _tabs.is_empty():
		draw_rect(inside, Color(0, 0, 0))
		var t := Res.tr_key("advancements.empty", "There doesn't seem to be anything here...")
		_text(inside.position + Vector2(floorf((234 - McList.text_w(t)) / 2.0), 56 - 4), t, Color(1, 1, 1))
	else:
		var tab: Dictionary = _tabs[_sel]
		var sx: float = tab["sx"]
		var sy: float = tab["sy"]
		# background (16 x 16 tiles), clipped to the inside area via the tile loop
		var bg := UiKit.sprite(str(tab["bg"])) if str(tab["bg"]) != "" else null
		var ox := fposmod(sx, 16.0)
		var oy := fposmod(sy, 16.0)
		for ty in range(-1, 9):
			for tx in range(-1, 16):
				var r := Rect2(inside.position + Vector2(ox + tx * 16, oy + ty * 16), Vector2(16, 16))
				var c := r.intersection(inside)
				if c.size.x <= 0 or c.size.y <= 0:
					continue
				if bg != null:
					draw_texture_rect_region(bg, c, Rect2((c.position - r.position) * (bg.get_width() / 16.0), c.size * (bg.get_width() / 16.0)))
				else:
					draw_rect(c, Color(0.2, 0.2, 0.2))
		var nodes: Dictionary = tab["nodes"]
		var org := inside.position + Vector2(sx, sy)
		for shadow in [true, false]:
			for id in nodes:
				_draw_link(nodes, id, org, shadow, inside)
		for id in nodes:
			var n: Dictionary = nodes[id]
			var p := org + Vector2(n["x"], n["y"])
			if not inside.grow(26).has_point(p):
				continue
			var fr := UiKit.sprite("gui/sprites/advancements/%s_frame_%s" % [n["frame"], "obtained" if n["done"] else "unobtained"])
			if fr != null and inside.encloses(Rect2(p + Vector2(3, 0), Vector2(26, 26))):
				draw_texture_rect(fr, Rect2(p + Vector2(3, 0), Vector2(26, 26)), false)
				var it := Res.items.id(str(n["icon"])) if Res.items != null else -1
				if it >= 0:
					var ic := ItemIcons.icon(it)
					if ic != null:
						draw_texture_rect(ic, Rect2(p + Vector2(8, 5), Vector2(16, 16)), false)
			if Rect2(p + Vector2(3, 0), Vector2(26, 26)).has_point(mp) and inside.has_point(mp):
				tip = [[str(n["title"]), Color(1, 1, 1)], [str(n["desc"]), Color8(85, 255, 85) if n["frame"] != "challenge" else Color8(255, 85, 255)]]
	var win := UiKit.sprite("gui/advancements/window")
	if win != null:
		draw_texture_rect_region(win, Rect2(w, Vector2(252, 140)), Rect2(0, 0, 252, 140))
	if not _tabs.is_empty():
		_draw_tab(_sel, true)
	_text(w + Vector2(8, 6), Res.tr_key("gui.advancements", "Advancements"), Color8(64, 64, 64), false)
	for i in _tabs.size():
		if _tab_rect(i).has_point(mp):
			tip = [[str(_tabs[i]["title"]), Color(1, 1, 1)]]
	if not tip.is_empty():
		UiKit.draw_tooltip(self, mp, tip, size / s)


func _draw_tab(i: int, sel: bool) -> void:
	var r := _tab_rect(i)
	var part := "left" if i == 0 else ("right" if i == 7 else "middle")
	var t := UiKit.sprite("gui/sprites/advancements/tab_above_%s%s" % [part, "_selected" if sel else ""])
	if t != null:
		draw_texture_rect(t, r, false)
	var it := Res.items.id(str(_tabs[i]["icon"])) if Res.items != null else -1
	if it >= 0:
		var ic := ItemIcons.icon(it)
		if ic != null:
			draw_texture_rect(ic, Rect2(r.position + Vector2(6, 9), Vector2(16, 16)), false)


## Java AdvancementWidget.drawConnectivity: parent (x + 13 .. x + 30) -> elbow -> child (x + 13), shadow pass first.
func _draw_link(nodes: Dictionary, id: String, org: Vector2, shadow: bool, clip: Rect2) -> void:
	var n: Dictionary = nodes[id]
	var par := str(n["parent"])
	if par == "" or not nodes.has(par):
		return
	var pn: Dictionary = nodes[par]
	var i := org.x + float(pn["x"]) + 13.0
	var j := org.x + float(pn["x"]) + 26.0 + 4.0
	var k := org.y + float(pn["y"]) + 13.0
	var l := org.x + float(n["x"]) + 13.0
	var m := org.y + float(n["y"]) + 13.0
	var c := Color(0, 0, 0) if shadow else Color(1, 1, 1)
	if shadow:
		_hline(j, i, k - 1, c, clip)
		_hline(j + 1, i, k, c, clip)
		_hline(j, i, k + 1, c, clip)
		_hline(l, j - 1, m - 1, c, clip)
		_hline(l, j - 1, m, c, clip)
		_hline(l, j - 1, m + 1, c, clip)
		_vline(j - 1, m, k, c, clip)
		_vline(j + 1, m, k, c, clip)
	else:
		_hline(j, i, k, c, clip)
		_hline(l, j, m, c, clip)
		_vline(j, m, k, c, clip)


func _hline(x1: float, x2: float, y: float, c: Color, clip: Rect2) -> void:
	var r := Rect2(minf(x1, x2), y, absf(x2 - x1) + 1, 1).intersection(clip)
	if r.size.x > 0 and r.size.y > 0:
		draw_rect(r, c)


func _vline(x: float, y1: float, y2: float, c: Color, clip: Rect2) -> void:
	var r := Rect2(x, minf(y1, y2) + 1, 1, absf(y2 - y1) - 1).intersection(clip)
	if r.size.x > 0 and r.size.y > 0:
		draw_rect(r, c)


func _text(p: Vector2, t: String, c: Color, shadow := true) -> void:
	var f := UiKit.font()
	if shadow and Settings.get_v("text_shadow"):
		draw_string(f, p + Vector2(1, 8), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(c.r * 0.25, c.g * 0.25, c.b * 0.25))
	draw_string(f, p + Vector2(0, 7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)


# ---------------------------------------------------------------- input

func _gui_input(e: InputEvent) -> void:
	var s := float(UiKit.scale())
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var mp: Vector2 = e.position / s
			for i in _tabs.size():
				if _tab_rect(i).has_point(mp):
					_sel = i
					Audio.play_ui("ui.button.click")
					queue_redraw()
					return
			_drag = Rect2(_win() + Vector2(9, 18), Vector2(234, 113)).has_point(mp)
			_last = mp
		else:
			_drag = false
	elif e is InputEventMouseMotion:
		var mp2: Vector2 = e.position / s
		if _drag and not _tabs.is_empty():
			var t: Dictionary = _tabs[_sel]
			var d := mp2 - _last
			# Java AdvancementTab.scroll: only along axes wider than the inside area, clamped to the content
			if float(t["maxx"]) - float(t["minx"]) > 234.0:
				t["sx"] = clampf(float(t["sx"]) + d.x, -(float(t["maxx"]) - 234.0), -float(t["minx"]))
			if float(t["maxy"]) - float(t["miny"]) > 113.0:
				t["sy"] = clampf(float(t["sy"]) + d.y, -(float(t["maxy"]) - 113.0), -float(t["miny"]))
		_last = mp2
		queue_redraw()


func close() -> void:
	queue_free()
	if on_close.is_valid():
		on_close.call()


func on_escape() -> void:
	close()
