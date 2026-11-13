## LanguageScreen — Java LanguageSelectScreen (`options.language`): header 33 with "Language", McList of the
## locally available languages (jar en_us + the launcher asset index's minecraft/lang/*.json), 18-px rows,
## "Name (Region)" centred in white; footer 53: gray accuracy warning, then Font Settings... | Done (150 each, 8
## apart). Names are scanned once from the language files on a worker thread and cached in user://. Done applies
## the selection (Res.set_language, live for menus and item names) and saves it.
extends Control

var on_close: Callable
var list: McList
var _langs: Array = []      # [code, display]
var _title: Label
var _warn: Label
var _font: Button
var _done: Button
var _task := -1
var _result: Array = []

const CACHE := "user://lang_names.json"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	_title = McW.text(Res.tr_key("options.language.title", "Language"), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	list = McList.new()
	list.item_height = 18
	list.row_width = 220
	list.draw_row = func(l: McList, i: int, r: Rect2, _h: bool, _s: bool):
		var t: String = _langs[i][1]
		var x := r.position.x + floorf((216.0 - McList.text_w(t)) / 2.0) * l.gs()
		l.text(Vector2(x, r.position.y + floorf((14.0 - 9.0) / 2.0 + 1.0) * l.gs()), t, Color(1, 1, 1))
	list.activated.connect(func(_i): _apply())
	add_child(list)
	_warn = McW.text(Res.tr_key("options.languageAccuracyWarning", "(Language translations may not be 100% accurate)").replace("%%", "%"), Color8(186, 186, 186), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_warn)
	_font = UiKit.button(Res.tr_key("options.font", "Font Settings..."), func(): pass, 150)
	_font.disabled = true
	_font.tooltip_text = "Force Unicode Font / Japanese Glyph Variants are not implemented yet"
	add_child(_font)
	_done = UiKit.button(Res.tr_key("gui.done", "Done"), _apply, 150)
	add_child(_done)
	_layout()
	resized.connect(_layout)
	_load_names()


func _load_names() -> void:
	var codes: Array = Res.language_codes()
	var cache := {}
	if FileAccess.file_exists(CACHE):
		var j = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
		if j is Dictionary:
			cache = j
	var missing := codes.filter(func(c): return not cache.has(c))
	if missing.is_empty():
		_fill(codes, cache)
		return
	# scan the language files off the main thread (each is a few hundred KB)
	var paths := {}
	for c in missing:
		paths[c] = Res.sound_object_path("minecraft/lang/%s.json" % c) if c != "en_us" or Res.sound_object_path("minecraft/lang/en_us.json") != "" else ""
	_result = []
	_task = WorkerThreadPool.add_task(func():
		var out := {}
		for c in paths:
			var p: String = paths[c]
			if p == "":
				out[c] = [str(Res.lang_en.get("language.name", c)), str(Res.lang_en.get("language.region", ""))]
				continue
			var txt := FileAccess.get_file_as_string(p)
			out[c] = [_field(txt, "language.name"), _field(txt, "language.region")]
		_result = [out])
	set_process(true)
	_fill(codes, cache)   # codes now, names when the scan finishes
	var pend := codes
	set_meta("codes", pend)
	set_meta("cache", cache)


static func _field(txt: String, key: String) -> String:
	var i := txt.find("\"" + key + "\"")
	if i < 0:
		return ""
	var a := txt.find("\"", txt.find(":", i) + 1)
	var b := a + 1
	while b < txt.length() and not (txt[b] == "\"" and txt[b - 1] != "\\"):
		b += 1
	return txt.substr(a + 1, b - a - 1).c_unescape() if a >= 0 else ""


func _process(_d: float) -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	set_process(false)
	var cache: Dictionary = get_meta("cache")
	if not _result.is_empty():
		cache.merge(_result[0], true)
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(cache))
		f.close()
	_fill(get_meta("codes"), cache)


func _fill(codes: Array, cache: Dictionary) -> void:
	_langs.clear()
	for c in codes:
		var nr = cache.get(c, [c, ""])
		var nm: String = str(nr[0]) if str(nr[0]) != "" else c
		_langs.append([c, nm + (" (" + str(nr[1]) + ")" if str(nr[1]) != "" else "")])
	_langs.sort_custom(func(a, b): return str(a[1]).to_lower() < str(b[1]).to_lower())
	list.set_count(_langs.size())
	var cur := str(Settings.get_v("language"))
	for i in _langs.size():
		if _langs[i][0] == cur:
			list.select(i)


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(_title, 0, 12 - 1, gw, 9)
	McW.place(list, 0, 33, gw, maxf(0.0, gh - 33 - 53))
	McW.place(_warn, 0, gh - 45 - 1, gw, 9)
	McW.place(_font, c - 154, gh - 28, 150, 20)
	McW.place(_done, c + 4, gh - 28, 150, 20)


func _apply() -> void:
	if list.sel >= 0 and list.sel < _langs.size():
		var code: String = _langs[list.sel][0]
		if code != str(Settings.get_v("language")) and Res.set_language(code):
			Settings.set_v("language", code)
	close()


func close() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
	Settings.save()
	UiKit.reset_theme()
	var top := get_parent() != null and not get_parent().has_method("_restore")   # a screen of its own (not inside Options)
	queue_free()
	if on_close.is_valid():
		on_close.call()
	elif top:
		UiKit.return_fallback(self)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
