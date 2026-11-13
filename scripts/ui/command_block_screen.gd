## CommandBlockScreen — Java CommandBlockEditScreen: command text field, previous output, mode (Impulse / Chain /
## Repeat — swaps the block type, keeping facing), Conditional / Unconditional, Needs Redstone / Always Active,
## Done / Cancel. Switching an impulse block to Always Active runs it once (Java).
extends Control

var world
var pos := Vector3i.ZERO
var edit: LineEdit
var mode_btn: Button
var cond_btn: Button
var auto_btn: Button
var kind := "command_block"
var cond := false
var auto := false


func closes_on_inventory_key() -> bool:
	return false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var b := Res.blocks
	var st: int = world.state_at(pos.x, pos.y, pos.z)
	kind = b.name_of(st)
	cond = b.has_prop(st, "conditional") and b.get_prop(st, "conditional") == "true"
	var d := CommandBlocks.data(world, pos)
	auto = bool(d.get("auto", false))
	var v := UiKit.column(self, 4)
	v.add_child(UiKit.label("Set Console Command for Block"))
	edit = LineEdit.new()
	edit.text = str(d.get("Command", ""))
	edit.max_length = 32500
	edit.custom_minimum_size = Vector2(300, 20) * UiKit.scale()
	v.add_child(edit)
	v.add_child(UiKit.label("Previous Output: " + str(d.get("LastOutput", "")).substr(0, 120), HORIZONTAL_ALIGNMENT_LEFT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4 * UiKit.scale())
	mode_btn = UiKit.button("", _cycle_mode, 100)
	cond_btn = UiKit.button("", func(): cond = not cond; _labels(), 100)
	auto_btn = UiKit.button("", func(): auto = not auto; _labels(), 100)
	row.add_child(mode_btn)
	row.add_child(cond_btn)
	row.add_child(auto_btn)
	v.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4 * UiKit.scale())
	row2.add_child(UiKit.button("Done", _done, 150))
	row2.add_child(UiKit.button("Cancel", func(): world.close_screen(), 150))
	v.add_child(row2)
	_labels()
	edit.grab_focus()


func _labels() -> void:
	mode_btn.text = {"command_block": "Impulse", "chain_command_block": "Chain", "repeating_command_block": "Repeat"}.get(kind, "Impulse")
	cond_btn.text = "Conditional" if cond else "Unconditional"
	auto_btn.text = "Always Active" if auto else "Needs Redstone"


func _cycle_mode() -> void:
	var i := CommandBlocks.KINDS.find(kind)
	kind = CommandBlocks.KINDS[(i + 1) % 3]
	_labels()


func _done() -> void:
	var b := Res.blocks
	var st: int = world.state_at(pos.x, pos.y, pos.z)
	var d := CommandBlocks.data(world, pos)
	var was_auto := bool(d.get("auto", false))
	var ns := b.state_of("minecraft:" + kind, {"facing": b.get_prop(st, "facing") if b.has_prop(st, "facing") else "north", "conditional": "true" if cond else "false"})
	if ns > 0 and ns != st:
		world.set_block(pos.x, pos.y, pos.z, ns, false)
	d["Command"] = edit.text
	d["auto"] = auto
	BlockEntities.set_data(world, pos, d)
	if auto and not was_auto and kind == "command_block":
		CommandBlocks.queue(pos)
	world.close_screen()
