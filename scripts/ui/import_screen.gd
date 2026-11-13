## ImportScreen — first-launch "Import Java Edition Resources": shows detected installs (version/path),
## lets the user pick one, browse for a custom folder, retry, use Original Placeholder Mode, or exit.
## Emits finished({manifest} | {placeholder: true}). Never downloads; reads only the user's own install.
extends Control

signal finished(result: Dictionary)

var found: Array = []
var best: Dictionary = {}
var list: ItemList
var status: Label
var bar: ProgressBar
var busy := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 40
	v.offset_right = -40
	v.offset_top = 30
	v.offset_bottom = -30
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var t := Label.new()
	t.text = "Import Java Edition Resources"
	t.add_theme_font_size_override("font_size", 28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.text = "Recraft can use textures, sounds and music from a Minecraft: Java Edition copy that is already installed on this computer. Files are copied only into a private cache on this machine (user://minecraft_asset_cache) and are never uploaded or redistributed. You must own the game to use its assets."
	v.add_child(info)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(list)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(status)
	bar = ProgressBar.new()
	bar.max_value = 1.0
	v.add_child(bar)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	for pair in [["Import Selected", _import], ["Browse for Minecraft Folder", _browse], ["Retry", _rescan], ["Use Original Placeholder Mode", _placeholder], ["Exit", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		h.add_child(b)
	_fill()


func _fill() -> void:
	list.clear()
	var sel := -1
	for i in found.size():
		var f: Dictionary = found[i]
		var tag := " (release)" if f["release"] else " (%s - not used for the 26.3 profile)" % f["type"]
		list.add_item("%s%s  —  %s" % [f["version"], tag, f["jar"]])
		if not best.is_empty() and f["jar"] == best["jar"]:
			sel = i
	var extra: Array = [Settings.get_v("custom_mc_dir")] if Settings.get_v("custom_mc_dir") != "" else []
	if found.is_empty():
		status.text = "No Minecraft: Java Edition %s installation was found. Checked:\n%s\nOr browse to the folder of another launcher, or continue in Original Placeholder Mode." % [MinecraftLocator.TARGET_VERSION, "\n".join(MinecraftLocator.diagnose(extra))]
	elif sel >= 0:
		list.select(sel)
		if best["version"] == MinecraftLocator.TARGET_VERSION:
			status.text = "Detected %s. Press Import Selected." % best["version"]
		else:
			var d := MinecraftLocator.diagnose(extra)
			status.text = "Only %s was found - this game is built for %s and needs its files (world generation data, models). %s" % [best["version"], MinecraftLocator.TARGET_VERSION, d[d.size() - 1] if not d.is_empty() else ""]
	else:
		status.text = "No usable version was found. Checked:\n%s" % "\n".join(MinecraftLocator.diagnose(extra))


func _rescan() -> void:
	found = MinecraftLocator.scan([Settings.get_v("custom_mc_dir")] if Settings.get_v("custom_mc_dir") != "" else [])
	best = MinecraftLocator.pick_best(found)
	_fill()


func _browse() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.title = "Select your .minecraft (game directory) folder"
	fd.show_hidden_files = true   # .minecraft starts with a dot: hidden by default in Godot dialogs
	var appdata := OS.get_environment("APPDATA")
	if appdata != "":
		fd.current_dir = appdata
	fd.dir_selected.connect(func(d):
		Settings.set_v("custom_mc_dir", d)
		Settings.save()
		_rescan())
	add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


func _placeholder() -> void:
	finished.emit({"placeholder": true})


func _import() -> void:
	if busy:
		return
	var s := list.get_selected_items()
	if s.is_empty():
		status.text = "Select an installation first."
		return
	busy = true
	var f: Dictionary = found[s[0]]
	var rep := AssetImporter.run(f, func(m, p):
		status.text = m
		bar.value = p)
	busy = false
	if rep["ok"]:
		finished.emit({"manifest": rep["manifest"]})
	else:
		status.text = "Import failed: " + str(rep["error"])
