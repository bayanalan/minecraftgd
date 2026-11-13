## EditWorld — Java EditWorldScreen (`world.edit`): one vertical LinearLayout (spacing 5) centred in the screen:
## title, ["World Name" (0xA0A0A0) + 200 x 20 EditBox, spacing 2], then 200-px buttons:
## Reset Icon (only with an icon), Open World Folder, Make Backup, Open Backups Folder, Optimize World (no older
## chunk format exists in Recraft saves: disabled with the reason), Export World Generation Settings (writes
## worldgen_settings_export.json into the world folder), then Save | Cancel (98 each). Name changes apply on Save.
extends Control

var app
var world: Dictionary
var _title: Label
var _lab: Label
var name_edit: LineEdit
var _btns: Array = []
var _save: Button
var _cancel: Button
var _status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	var folder := str(world.get("folder", ""))
	var dir := SaveManager.ROOT.path_join(folder)
	_title = McW.text(Res.tr_key("selectWorld.edit.title", "Edit World"), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	_lab = McW.text(Res.tr_key("selectWorld.enterName", "World Name"), McW.GRAY)
	add_child(_lab)
	name_edit = McW.edit(str(world.get("name", folder)), "", 32)
	name_edit.text_changed.connect(func(t): _save.disabled = t.strip_edges() == "")
	add_child(name_edit)
	var icon_p := dir.path_join("icon.png")
	var reset := UiKit.button(Res.tr_key("selectWorld.edit.resetIcon", "Reset Icon"), func():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(icon_p))
		_btns[0].disabled = true)
	reset.disabled = not FileAccess.file_exists(icon_p)
	_btns.append(reset)
	_btns.append(UiKit.button(Res.tr_key("selectWorld.edit.openFolder", "Open World Folder"), func(): OS.shell_open(ProjectSettings.globalize_path(dir))))
	_btns.append(UiKit.button(Res.tr_key("selectWorld.edit.backup", "Make Backup"), func():
		var bp := SaveManager.backup_world(folder)
		_status.text = Res.tr_key("selectWorld.edit.backupCreated", "Backed up: %s").replace("%s", bp.get_file())))
	_btns.append(UiKit.button(Res.tr_key("selectWorld.edit.backupFolder", "Open Backups Folder"), func():
		DirAccess.make_dir_recursive_absolute("user://backups")
		OS.shell_open(ProjectSettings.globalize_path("user://backups"))))
	var opt := UiKit.button(Res.tr_key("selectWorld.edit.optimize", "Optimize World"), func(): pass)
	opt.disabled = true
	opt.tooltip_text = "Recraft saves have a single chunk format; there is nothing to upgrade"
	_btns.append(opt)
	_btns.append(UiKit.button(Res.tr_key("selectWorld.edit.export_worldgen_settings", "Export World Generation Settings"), func():
		var out := {"seed": world.get("seed", 0), "generator_id": world.get("generator_id", ""), "generator_settings": world.get("generator_settings", {})}
		var f := FileAccess.open(dir.path_join("worldgen_settings_export.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(out, "  "))
			f.close()
			_status.text = Res.tr_key("selectWorld.edit.export_worldgen_settings.success", "Exported")
		else:
			_status.text = Res.tr_key("selectWorld.edit.export_worldgen_settings.failure", "Export failed")))
	for b in _btns:
		add_child(b)
	_save = UiKit.button(Res.tr_key("selectWorld.edit.save", "Save"), func():
		SaveManager.rename_world(folder, name_edit.text.strip_edges())
		app.show_world_list(), 98)
	_cancel = UiKit.button(Res.tr_key("gui.cancel", "Cancel"), func(): app.show_world_list(), 98)
	add_child(_save)
	add_child(_cancel)
	_status = McW.text("", McW.GRAY, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_status)
	_layout()
	resized.connect(_layout)
	name_edit.grab_focus()


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	var total := 9.0 + 5.0 + 31.0 + 5.0 + 25.0 * _btns.size() + 20.0
	var y := floorf((gh - total) / 2.0)
	McW.place(_title, 0, y - 1, gw, 9)
	y += 14.0
	McW.place(_lab, c - 100, y - 1, 200, 9)
	McW.place(name_edit, c - 100, y + 11, 200, 20)
	y += 36.0
	for i in _btns.size():
		McW.place(_btns[i], c - 100, y, 200, 20)
		y += 25.0
	McW.place(_save, c - 100, y, 98, 20)
	McW.place(_cancel, c + 2, y, 98, 20)
	McW.place(_status, 0, y + 26, gw, 9)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		app.show_world_list()
