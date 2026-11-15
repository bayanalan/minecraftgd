## GameRulesScreen — Java EditGameRulesScreen (`world.gamerules_create`, `world.gamerules_runtime`): title at
## y 20, McList y 43..h-32 with 24-px rows (row width 220): category headers (bold yellow, centred, sorted in the
## Java Category order), then the category's rules sorted by id — label (gamerule.<id>, split at 175 px, 1 or 2
## lines) and on the right (row x + 175) a 44 x 20 value-only ON/OFF switch or an integer EditBox (red text and
## Done disabled while invalid). Hover tooltip: gamerule.<id>.description + "Default: v". Done | Cancel at h-29.
extends Control

var rules: Dictionary = {}          # overrides only (name -> value), returned through on_done
var on_done: Callable
var runtime := false                # opened from World Options (applies to the running world)
var _work := {}
var _rows: Array = []               # ["cat", key] | ["rule", name]
var _invalid := {}
var list: McList
var _title: Label
var _done: Button
var _cancel: Button

const CATS := ["player", "mobs", "spawning", "drops", "updates", "chat", "misc"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	_work = GameRules.defaults()
	_work.merge(rules, true)
	_title = McW.text(Res.tr_key("editGamerule.title", "Edit Game Rules"), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	list = McList.new()
	list.item_height = 24
	list.row_width = 220
	list.draw_row = _draw_row
	add_child(list)
	_done = UiKit.button(Res.tr_key("gui.done", "Done"), _finish, 150)
	_cancel = UiKit.button(Res.tr_key("gui.cancel", "Cancel"), func(): queue_free(), 150)
	add_child(_done)
	add_child(_cancel)
	_layout()
	resized.connect(_layout)
	_build_rows()


func _build_rows() -> void:
	_rows.clear()
	for cat in CATS:
		var names: Array = []
		for k in GameRules.SPEC:
			if str(GameRules.SPEC[k][1]) == cat:
				names.append(k)
		if names.is_empty():
			continue
		names.sort()
		_rows.append(["cat", cat])
		for n in names:
			_rows.append(["rule", n])
	list.set_count(_rows.size())
	list.sel = -1
	for i in _rows.size():
		if _rows[i][0] != "rule":
			continue
		var n: String = _rows[i][1]
		var def = GameRules.SPEC[n][0]
		var tip := Res.tr_key(GameRules.lang_key(n) + ".description", "")
		tip = (tip + "\n" if tip != "" else "") + Res.tr_key("editGamerule.default", "Default: %s").replace("%s", str(def))
		var w: Control
		if def is bool:
			w = McW.on_off("", bool(_work[n]), func(v): _work[n] = v, 44, true)
		else:
			var le := McW.edit(str(_work[n]), "", 12)
			le.text_changed.connect(func(t):
				var ok: bool = t.is_valid_int()
				if ok:
					_work[n] = int(t)
					_invalid.erase(n)
				else:
					_invalid[n] = true
				le.add_theme_color_override("font_color", McW.EDIT_TEXT if ok else McW.RED)
				_done.disabled = not _invalid.is_empty())
			w = le
		w.tooltip_text = tip
		w.size = Vector2(44, 20) * float(UiKit.scale())
		w.custom_minimum_size = w.size
		list.add_row_widget(i, w, Vector2(175, 0))


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(_title, 0, 20 - 1, gw, 9)
	McW.place(list, 0, 43, gw, maxf(0.0, gh - 32 - 43))
	McW.place(_done, c - 155, gh - 29, 150, 20)
	McW.place(_cancel, c + 5, gh - 29, 150, 20)
	list._redraw()


func _draw_row(l: McList, i: int, r: Rect2, _hovered: bool, _sel: bool) -> void:
	var s := l.gs()
	var row: Array = _rows[i]
	if row[0] == "cat":
		var t := Res.tr_key("gamerule.category." + str(row[1]), str(row[1]).capitalize())
		var tw := McList.text_w_bold(t)
		var x := r.position.x + floorf((220.0 - tw) / 2.0) * s
		l.text_bold(Vector2(x, r.position.y + 5 * s), t, Color8(255, 255, 85))
		return
	var n: String = row[1]
	var lines := _split(Res.tr_key(GameRules.lang_key(n), n), 175.0)
	if lines.size() == 1:
		l.text(Vector2(r.position.x, r.position.y + 5 * s), lines[0], Color(1, 1, 1), false)
	else:
		l.text(Vector2(r.position.x, r.position.y), lines[0], Color(1, 1, 1), false)
		l.text(Vector2(r.position.x, r.position.y + 10 * s), lines[1], Color(1, 1, 1), false)


## Word wrap at `w` GUI px (Java Font.split).
static func _split(t: String, w: float) -> Array:
	var out: Array = []
	var cur := ""
	for word in t.split(" "):
		var cand := word if cur == "" else cur + " " + word
		if McList.text_w(cand) > w and cur != "":
			out.append(cur)
			cur = word
		else:
			cur = cand
	if cur != "":
		out.append(cur)
	return out


func _finish() -> void:
	if not _invalid.is_empty():
		return
	var over := {}
	for k in _work:
		if _work[k] != GameRules.SPEC[k][0]:
			over[k] = _work[k]
	if on_done.is_valid():
		on_done.call(over if not runtime else _work)
	queue_free()


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
