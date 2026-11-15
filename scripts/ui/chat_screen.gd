## ChatScreen — text input for chat and /commands: history with Up/Down, Java CommandSuggestions (a list of up to 10
## completions above the input at the argument's x - selected one yellow, others grey on 0xD0000000 - with the
## selected completion's rest as dark grey ghost text; Tab applies / cycles, Up / Down move the selection; a usage line
## when nothing matches), and clicks on chat components with a suggest-command (/locate's green coordinates).
extends Control

var world
var prefill := ""
var edit: LineEdit
var hist_i := -1
static var history: Array = []
var _sug: Array = [0, [], ""]   # [token start, candidates, usage]
var _sel := 0
var _scroll := 0
var _hidden := false
var _overlay: Control
var _applying := false
var _cycling := false       # Tab pressed: Up / Down move through the suggestions instead of the history
var _sug_box := Rect2()     # suggestion list rect (GUI units) for mouse clicks
var _open_frame := 0
var _focus_ms := 0
var _disp := 0              # Java EditBox.displayPos: first character drawn


func is_chat() -> bool:
	return true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	edit = LineEdit.new()
	edit.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	edit.offset_top = -14 * UiKit.scale()
	edit.offset_bottom = -2 * UiKit.scale()
	edit.offset_left = 2 * UiKit.scale()
	edit.offset_right = -2 * UiKit.scale()
	# Java ChatScreen: plain input bar fill(2, h - 14, w - 2, h - 2, 0x80000000), text 0xE0E0E0 at x 4, no border
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(0, 0, 0, 0.5)
	bar.content_margin_left = 2 * UiKit.scale()
	bar.content_margin_right = 2 * UiKit.scale()
	for st in ["normal", "focus", "read_only"]:
		edit.add_theme_stylebox_override(st, bar)
	# the LineEdit only edits: Java EditBox's look (shadowed 0xE0E0E0 text, "_" / 1-px caret blinking every 300 ms,
	# inverted selection, displayPos scrolling) is drawn by _draw_input
	for cn in ["font_color", "font_selected_color", "selection_color", "caret_color", "font_uneditable_color", "font_placeholder_color", "font_outline_color"]:
		edit.add_theme_color_override(cn, Color(0, 0, 0, 0))
	_focus_ms = Time.get_ticks_msec()
	edit.text = prefill
	_open_frame = Engine.get_process_frames()
	edit.max_length = 256
	edit.text_submitted.connect(_submit)
	edit.text_changed.connect(func(_t): _refresh())
	add_child(edit)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_suggestions)
	add_child(_overlay)
	edit.grab_focus()
	edit.caret_column = edit.text.length()
	_refresh()


func _refresh() -> void:
	if _applying:
		return
	_hidden = false
	_cycling = false
	_sel = 0
	_scroll = 0
	var before := edit.text.substr(0, edit.caret_column)
	_sug = CommandSuggest.suggest(world, before) if before.begins_with("/") else [0, [], ""]


func _process(_d: float) -> void:
	_overlay.queue_redraw()


func _apply(i: int) -> void:
	var c: Array = _sug[1]
	if c.is_empty():
		return
	var cand := str(c[i % c.size()])
	var st: int = _sug[0]
	_applying = true
	edit.text = edit.text.substr(0, st) + cand + edit.text.substr(edit.caret_column)
	edit.caret_column = st + cand.length()
	_applying = false


func _submit(t: String) -> void:
	_send(t)
	world.close_screen()


## Java ChatScreen.handleChatInput: a command runs, anything else is a chat message.
func _send(t: String) -> void:
	t = t.strip_edges()
	if t != "":
		history.append(t)
		if t.begins_with("/"):
			if Net.is_client() and not (t.get_slice(" ", 0) in ["/help", "/seed", "/list", "/locate", "/me"]):
				world.hud.chat_message("Only the host can run that command in a LAN game")
			else:
				var out: String = world.commands.execute(t)
				world.hud.chat_message(out, world.commands.feedback_click)
		elif Net.active():
			Net.chat(t)
		else:
			world.hud.chat_message("<Player> " + t)


func _input(event: InputEvent) -> void:
	# the "/" that opened the command chat must not be typed a second time (a character event that follows the key)
	if event is InputEventKey and event.pressed and event.unicode == 47 and prefill == "/" and edit.text == "/" and Engine.get_process_frames() - _open_frame <= 2:
		get_viewport().set_input_as_handled()
		return
	var cands: Array = _sug[1]
	var showing := not _hidden and not cands.is_empty()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and showing:
		# Java SuggestionsList.mouseClicked: a click on a line uses that suggestion
		var gp: Vector2 = event.position / float(UiKit.scale())
		if _sug_box.has_point(gp):
			_sel = clampi(_scroll + int((gp.y - _sug_box.position.y) / 12.0), 0, cands.size() - 1)
			_apply(_sel)
			_refresh()
			edit.grab_focus()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and world != null:
		var cmd: String = world.hud.chat_click_at(event.position)
		if cmd.begins_with("copy:"):
			# Java ClickEvent COPY_TO_CLIPBOARD (the chat stays open)
			DisplayServer.clipboard_set(cmd.substr(5))
			get_viewport().set_input_as_handled()
			return
		if cmd != "":
			# Java ClickEvent SUGGEST_COMMAND
			edit.text = cmd
			edit.caret_column = cmd.length()
			edit.grab_focus()
			_refresh()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_TAB and showing:
		_apply(_sel)
		_sel = (_sel + (-1 if event.shift_pressed else 1) + cands.size()) % cands.size()
		_cycling = true
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_UP and showing and _cycling:
		_sel = (_sel - 1 + cands.size()) % cands.size()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DOWN and showing and _cycling:
		_sel = (_sel + 1) % cands.size()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DOWN and history.size() > 0 and hist_i >= 0:
		hist_i += 1
		edit.text = history[hist_i] if hist_i < history.size() else ""
		if hist_i >= history.size():
			hist_i = -1
		edit.caret_column = edit.text.length()
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and showing:
		_hidden = true
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_UP and history.size() > 0:
		hist_i = clampi(hist_i - 1 if hist_i >= 0 else history.size() - 1, 0, history.size() - 1)
		edit.text = history[hist_i]
		edit.caret_column = edit.text.length()
		_refresh()
		get_viewport().set_input_as_handled()


## Java EditBox.renderWidget (unbordered, at (4, h - 12)): text from displayPos in 0xE0E0E0 with shadow, the caret
## blinking 300 ms on / off - "_" at the end of the text, else a 1-pixel 0xD0D0D0 bar - and the selection drawn by
## OR_REVERSE over 0xFF0000FF (light box, blue text).
func _draw_input(font: Font, w: float, h: float) -> void:
	var txt := edit.text
	var cc := clampi(edit.caret_column, 0, txt.length())
	var maxw := w - 8.0
	_disp = clampi(_disp, 0, txt.length())
	if cc < _disp:
		_disp = cc
	while _disp < cc and font.get_string_size(txt.substr(_disp, cc - _disp), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > maxw:
		_disp += 1
	var vis := txt.substr(_disp)
	while vis.length() > 0 and font.get_string_size(vis, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > maxw:
		vis = vis.substr(0, vis.length() - 1)
	var x := 4.0
	var base := h - 10.0 + 7.0
	var tc := Color8(0xE0, 0xE0, 0xE0)
	var sc := Color8(0x38, 0x38, 0x38)
	_overlay.draw_string(font, Vector2(x + 1, base + 1), vis, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, sc)
	_overlay.draw_string(font, Vector2(x, base), vis, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, tc)
	var cx := x + font.get_string_size(txt.substr(_disp, cc - _disp), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	if edit.has_selection():
		var a := clampi(edit.get_selection_from_column() - _disp, 0, vis.length())
		var b := clampi(edit.get_selection_to_column() - _disp, 0, vis.length())
		if b > a:
			var sx := x + font.get_string_size(vis.substr(0, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			var sw := font.get_string_size(vis.substr(a, b - a), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			_overlay.draw_rect(Rect2(sx, h - 11.0, sw, 11.0), Color8(0xDF, 0xDF, 0xFF))
			_overlay.draw_string(font, Vector2(sx, base), vis.substr(a, b - a), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(0x1F, 0x1F, 0xFF))
	if ((Time.get_ticks_msec() - _focus_ms) / 300) % 2 == 0 and edit.has_focus():
		if cc >= txt.length():
			_overlay.draw_string(font, Vector2(cx + 1, base + 1), "_", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, sc)
			_overlay.draw_string(font, Vector2(cx, base), "_", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, tc)
		else:
			_overlay.draw_rect(Rect2(cx, h - 11.0, 1.0, 11.0), Color8(0xD0, 0xD0, 0xD0))


func _draw_suggestions() -> void:
	var s := UiKit.scale()
	var font := UiKit.font()
	_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var h := size.y / s
	_draw_input(font, size.x / s, h)
	var cands: Array = _sug[1]
	var before := edit.text.substr(0, int(_sug[0]))
	var x0 := 4.0 + font.get_string_size(before.substr(mini(_disp, before.length())), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	if not _hidden and not cands.is_empty():
		_sel = clampi(_sel, 0, cands.size() - 1)
		if _sel < _scroll:
			_scroll = _sel
		elif _sel >= _scroll + 10:
			_scroll = _sel - 9
		var n := mini(10, cands.size())
		var w := 0.0
		for c in cands.slice(_scroll, _scroll + n):
			w = maxf(w, font.get_string_size(str(c), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
		var top := h - 14.0 - 1.0 - n * 12.0
		_sug_box = Rect2(x0 - 1, top, w + 2, n * 12.0)
		_overlay.draw_rect(_sug_box, Color(0, 0, 0, 0.8156863))
		for k in n:
			var idx := _scroll + k
			var col := Color8(0xFF, 0xFF, 0x55) if idx == _sel else Color8(0xAA, 0xAA, 0xAA)
			_overlay.draw_string(font, Vector2(x0, top + 2 + 12 * k + 7), str(cands[idx]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
		# ghost text: the rest of the selected completion after the typed token
		var typed := edit.text.substr(int(_sug[0]), edit.caret_column - int(_sug[0]))
		var sel_s := str(cands[_sel])
		if edit.caret_column == edit.text.length() and sel_s.to_lower().begins_with(typed.to_lower()) and sel_s.length() > typed.length():
			var gx := 4.0 + font.get_string_size(edit.text.substr(_disp), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			_overlay.draw_string(font, Vector2(gx, h - 10.0 + 7.0), sel_s.substr(typed.length()), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(0x80, 0x80, 0x80))
	elif not _hidden and str(_sug[2]) != "" and edit.text.begins_with("/"):
		var u := str(_sug[2])
		var uw := font.get_string_size(u, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var top2 := h - 14.0 - 1.0 - 12.0
		_overlay.draw_rect(Rect2(3, top2, uw + 2, 12), Color(0, 0, 0, 0.8156863))
		_overlay.draw_string(font, Vector2(4, top2 + 2 + 7), u, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(0xAA, 0xAA, 0xAA))
