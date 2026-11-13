## MultiplayerScreen — Java JoinMultiplayerScreen (`network.multiplayer`): title "Play Multiplayer" at y 20, McList
## y 32..h-64 (36-px rows, 305 wide): saved servers (user://servers.json: icon misc/unknown_server, name, status line,
## hover server_list/join(_highlighted) - clicking the icon joins), then the LAN section ("Scanning for games on your
## local network" + loading dots, LAN World entries from the discovery broadcast). Buttons: Join Server | Direct
## Connection | Add Server (100 px at h-52), Edit | Delete | Refresh | Back (74 px at h-28). Sub-screens: Edit
## Server Info (`network.add_server` / `network.edit_server`), Direct Connection (`network.direct_connect`), delete
## confirm, and a connecting overlay with Cancel. Recraft has no server status ping: saved servers show their status
## only when the address matches a LAN broadcast, otherwise "status unknown" (never a fake ping).
extends Control

const SERVERS := "user://servers.json"

var app
var list: McList
var servers: Array = []     # [{name, ip}]
var _rows: Array = []       # ["server", i] | ["lanhead"] | ["lan", key]
var _title: Label
var _btn := {}
var _t := 0.0
var _shown := ""
var _connect: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	_load()
	_title = McW.text(Res.tr_key("multiplayer.title", "Play Multiplayer"), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	list = McList.new()
	list.item_height = 36
	list.row_width = 305
	list.draw_row = _draw_row
	list.selected.connect(func(_i): _update_buttons())
	list.activated.connect(func(_i): _join_selected())
	list.gui_input.connect(_list_click)
	add_child(list)
	for spec in [["join", "selectServer.select", "Join Server", _join_selected, 100], ["direct", "selectServer.direct", "Direct Connection", _direct, 100],
			["add", "selectServer.add", "Add Server", func(): _edit(-1), 100], ["edit", "selectServer.edit", "Edit", func(): _edit(_sel_server()), 74],
			["delete", "selectServer.delete", "Delete", _delete, 74], ["refresh", "selectServer.refresh", "Refresh", func(): app._set_screen(_fresh()), 74],
			["back", "gui.back", "Back", _back, 74]]:
		var b := UiKit.button(Res.tr_key(spec[1], spec[2]), spec[3], spec[4])
		add_child(b)
		_btn[spec[0]] = b
	Net.start_discovery()
	_rebuild()
	_layout()
	resized.connect(_layout)


func _fresh() -> Control:
	var m = load("res://scripts/ui/multiplayer_screen.gd").new()
	m.app = app
	return m


func _load() -> void:
	servers = []
	if FileAccess.file_exists(SERVERS):
		var j = JSON.parse_string(FileAccess.get_file_as_string(SERVERS))
		if j is Array:
			for e in j:
				if e is Dictionary and e.has("ip"):
					servers.append({"name": str(e.get("name", "")), "ip": str(e["ip"])})


func _save() -> void:
	var f := FileAccess.open(SERVERS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(servers, "  "))
		f.close()


func _rebuild() -> void:
	var keep := list.sel
	_rows = []
	for i in servers.size():
		_rows.append(["server", i])
	_rows.append(["lanhead"])
	var keys: Array = Net.discovered.keys()
	keys.sort()
	for k in keys:
		_rows.append(["lan", k])
	_shown = str(keys)
	list.set_count(_rows.size())
	list.sel = keep if keep < _rows.size() and keep >= 0 and _rows[keep][0] != "lanhead" else -1
	_update_buttons()


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(_title, 0, 20 - 1, gw, 9)
	McW.place(list, 0, 32, gw, maxf(0.0, gh - 64 - 32))
	McW.place(_btn["join"], c - 154, gh - 52, 100, 20)
	McW.place(_btn["direct"], c - 50, gh - 52, 100, 20)
	McW.place(_btn["add"], c + 54, gh - 52, 100, 20)
	McW.place(_btn["edit"], c - 154, gh - 28, 74, 20)
	McW.place(_btn["delete"], c - 76, gh - 28, 74, 20)
	McW.place(_btn["refresh"], c + 4, gh - 28, 74, 20)
	McW.place(_btn["back"], c + 82, gh - 28, 74, 20)


func _update_buttons() -> void:
	var r: Array = _rows[list.sel] if list.sel >= 0 and list.sel < _rows.size() else []
	_btn["join"].disabled = r.is_empty() or r[0] == "lanhead"
	_btn["edit"].disabled = r.is_empty() or r[0] != "server"
	_btn["delete"].disabled = r.is_empty() or r[0] != "server"


func _sel_server() -> int:
	if list.sel >= 0 and list.sel < _rows.size() and _rows[list.sel][0] == "server":
		return int(_rows[list.sel][1])
	return -1


## address "host[:port]" -> [host, port]
static func _parse(addr: String) -> Array:
	var a := addr.strip_edges()
	var p := Net.DEFAULT_PORT
	if a.contains(":"):
		p = int(a.get_slice(":", 1))
		a = a.get_slice(":", 0)
	return [a, p]


## The LAN broadcast matching a saved address, or {}.
func _lan_for(addr: String) -> Dictionary:
	var hp := _parse(addr)
	for k in Net.discovered:
		var d: Dictionary = Net.discovered[k]
		if str(d["ip"]) == str(hp[0]) and int(d["port"]) == int(hp[1]):
			return d
	return {}


func _draw_row(l: McList, i: int, r: Rect2, hovered: bool, _sel: bool) -> void:
	var s := l.gs()
	var row: Array = _rows[i]
	var x := r.position.x
	var y := r.position.y
	match row[0]:
		"server":
			var sv: Dictionary = servers[int(row[1])]
			var ic := UiKit.sprite("misc/unknown_server")
			if ic != null:
				l.body.draw_texture_rect(ic, Rect2(x, y, 32 * s, 32 * s), false)
			var nm := str(sv["name"]) if str(sv["name"]) != "" else Res.tr_key("selectServer.defaultName", "Minecraft Server")
			l.text(Vector2(x + 35 * s, y + 1 * s), nm, Color(1, 1, 1), false)
			var lan := _lan_for(str(sv["ip"]))
			if not lan.is_empty():
				l.text(Vector2(x + 35 * s, y + 12 * s), str(lan.get("name", "")), McW.DGRAY, false)
				var ping := UiKit.sprite("gui/sprites/server_list/ping_5")
				if ping != null:
					l.body.draw_texture_rect(ping, Rect2(x + (r.size.x / s - 15) * s, y, 10 * s, 8 * s), false)
			else:
				l.text(Vector2(x + 35 * s, y + 12 * s), "Status unknown (no status ping)", McW.DGRAY, false)
			if hovered:
				l.body.draw_rect(Rect2(x, y, 32 * s, 32 * s), Color8(0x90, 0x90, 0x90, 0xA0))
				var over := l.mouse_gui().x * s - x < 32 * s
				var js := UiKit.sprite("gui/sprites/server_list/join_highlighted" if over else "gui/sprites/server_list/join")
				if js != null:
					l.body.draw_texture_rect(js, Rect2(x, y, 32 * s, 32 * s), false)
		"lanhead":
			var t := Res.tr_key("lanServer.scanning", "Scanning for games on your local network")
			var cx := x + (r.size.x / s / 2.0) * s
			l.text(Vector2(cx - floorf(McList.text_w(t) / 2.0) * s, y + 9 * s), t, Color(1, 1, 1))
			# Java LoadingDotsText: "O o o" with the big dot moving every 300 ms
			var ph := int(Time.get_ticks_msec() / 300) % 4
			var dots: String = ["O o o", "o O o", "o o O", "o O o"][ph]
			l.text(Vector2(cx - floorf(McList.text_w(dots) / 2.0) * s, y + 18 * s), dots, McW.DGRAY)
		"lan":
			var d: Dictionary = Net.discovered.get(row[1], {})
			l.text(Vector2(x + 35 * s, y + 1 * s), Res.tr_key("lanServer.title", "LAN World"), Color(1, 1, 1), false)
			l.text(Vector2(x + 35 * s, y + 12 * s), str(d.get("name", "")), McW.DGRAY, false)
			l.text(Vector2(x + 35 * s, y + 23 * s), "%s:%d" % [str(d.get("ip", "")), int(d.get("port", 0))], Color8(48, 48, 48), false)


func _list_click(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := list.row_at(e.position)
		if i >= 0 and _rows[i][0] == "server":
			var r := list.row_rect(i)
			if e.position.x / list.gs() - r.position.x < 32:
				list.select(i, false)
				_join_selected()


func _join_selected() -> void:
	if list.sel < 0 or list.sel >= _rows.size():
		return
	var row: Array = _rows[list.sel]
	match row[0]:
		"server":
			var hp := _parse(str(servers[int(row[1])]["ip"]))
			_join(hp[0], hp[1])
		"lan":
			var d: Dictionary = Net.discovered.get(row[1], {})
			if not d.is_empty():
				_join(str(d["ip"]), int(d["port"]))


func _join(ip: String, p: int) -> void:
	Net.stop_discovery()
	var nm := str(Settings.get_v("player_name")).strip_edges()
	var err := Net.join(app, ip, p, nm if nm != "" else "Player")
	_show_connect(err)


## Java ConnectScreen: "Connecting to the server..." + live status, Cancel returns to this list.
func _show_connect(err: String) -> void:
	_connect = Control.new()
	_connect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for ch in get_children():
		ch.set_meta("was_visible", ch.visible)
		ch.visible = false
	add_child(_connect)
	UiKit.background(_connect)
	var t := McW.text(Res.tr_key("connect.connecting", "Connecting to the server..."), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	t.name = "title"
	_connect.add_child(t)
	var st := McW.text(err if err != "" else Net.status, McW.GRAY, HORIZONTAL_ALIGNMENT_CENTER)
	st.name = "status"
	_connect.add_child(st)
	var cancel := UiKit.button(Res.tr_key("gui.cancel", "Cancel"), func():
		if Net.is_client() and Net.world == null:
			Net.stop()
		app._set_screen(_fresh()), 200)
	cancel.name = "cancel"
	_connect.add_child(cancel)
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	McW.place(t, 0, gh / 2.0 - 50 - 1, gw, 9)
	McW.place(st, 0, gh / 2.0 - 30 - 1, gw, 9)
	McW.place(cancel, floorf(gw / 2.0) - 100, gh / 4.0 + 120 + 12, 200, 20)


func _direct() -> void:
	var d := _sub(Res.tr_key("selectServer.direct", "Direct Connection"))
	var lab := McW.text(Res.tr_key("addServer.enterIp", "Server Address"), McW.GRAY)
	var ed := McW.edit("", "", 128)
	var go := UiKit.button(Res.tr_key("selectServer.select", "Join Server"), func():
		var a := ed.text.strip_edges()
		if a == "":
			return
		var hp := _parse(a)
		d.queue_free()
		_join(hp[0], hp[1]), 200)
	var cancel := UiKit.button(Res.tr_key("gui.cancel", "Cancel"), func(): _close_sub(d), 200)
	for c in [lab, ed, go, cancel]:
		d.add_child(c)
	ed.text_changed.connect(func(t): go.disabled = t.strip_edges() == "")
	go.disabled = ed.text.strip_edges() == ""
	ed.text_submitted.connect(func(_t): go.pressed.emit())
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(lab, c - 100, 100 - 1, 200, 9)
	McW.place(ed, c - 100, 116, 200, 20)
	McW.place(go, c - 100, floorf(gh / 4.0) + 96 + 12, 200, 20)
	McW.place(cancel, c - 100, floorf(gh / 4.0) + 120 + 12, 200, 20)
	ed.grab_focus()


## Java EditServerScreen ("Edit Server Info"): Server Name (C-100, 66), Server Address (C-100, 106), Done / Cancel.
func _edit(idx: int) -> void:
	var d := _sub(Res.tr_key("addServer.title", "Edit Server Info"))
	var sv: Dictionary = servers[idx] if idx >= 0 else {"name": Res.tr_key("selectServer.defaultName", "Minecraft Server"), "ip": ""}
	var l1 := McW.text(Res.tr_key("addServer.enterName", "Server Name"), McW.GRAY)
	var e1 := McW.edit(str(sv["name"]), "", 128)
	var l2 := McW.text(Res.tr_key("addServer.enterIp", "Server Address"), McW.GRAY)
	var e2 := McW.edit(str(sv["ip"]), "", 128)
	var done := UiKit.button(Res.tr_key("gui.done", "Done"), func():
		var ns := {"name": e1.text.strip_edges(), "ip": e2.text.strip_edges()}
		if idx >= 0:
			servers[idx] = ns
		else:
			servers.append(ns)
		_save()
		_close_sub(d)
		_rebuild(), 200)
	var cancel := UiKit.button(Res.tr_key("gui.cancel", "Cancel"), func(): _close_sub(d), 200)
	for c in [l1, e1, l2, e2, done, cancel]:
		d.add_child(c)
	e2.text_changed.connect(func(t): done.disabled = t.strip_edges() == "")
	done.disabled = e2.text.strip_edges() == ""
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	McW.place(l1, c - 100, 53 - 1, 200, 9)
	McW.place(e1, c - 100, 66, 200, 20)
	McW.place(l2, c - 100, 94 - 1, 200, 9)
	McW.place(e2, c - 100, 106, 200, 20)
	McW.place(done, c - 100, floorf(gh / 4.0) + 96 + 18, 200, 20)
	McW.place(cancel, c - 100, floorf(gh / 4.0) + 120 + 18, 200, 20)
	e1.grab_focus()


func _delete() -> void:
	var i := _sel_server()
	if i < 0:
		return
	var nm := str(servers[i]["name"])
	McConfirm.open(self, Res.tr_key("selectServer.deleteQuestion", "Are you sure you want to remove this server?"),
		Res.tr_key("selectServer.deleteWarning", "'%s' will be lost forever! (A long time!)").replace("%s", nm),
		Res.tr_key("selectServer.deleteButton", "Delete"), Res.tr_key("gui.cancel", "Cancel"),
		func():
			servers.remove_at(i)
			_save()
			_rebuild())


## Sub-screen over this one (title at y 20, background), this screen's widgets hidden meanwhile.
func _sub(title: String) -> Control:
	var d := Control.new()
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for ch in get_children():
		ch.set_meta("was_visible", ch.visible)
		ch.visible = false
	add_child(d)
	UiKit.background(d)
	var t := McW.text(title, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	d.add_child(t)
	McW.place(t, 0, 20 - 1, size.x / float(UiKit.scale()), 9)
	return d


func _close_sub(d: Control) -> void:
	d.queue_free()
	for ch in get_children():
		if ch != d and ch.has_meta("was_visible"):
			ch.visible = ch.get_meta("was_visible")


func _back() -> void:
	Net.stop_discovery()
	if Net.is_client() and Net.world == null:
		Net.stop()
	app.show_title()


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_back()


func _process(delta: float) -> void:
	_t += delta
	if _connect != null and is_instance_valid(_connect):
		var st := _connect.get_node_or_null("status")
		if st != null:
			(st as Label).text = Net.status
		return
	list._redraw()   # LAN header loading dots
	if _t > 0.5:
		_t = 0.0
		var keys: Array = Net.discovered.keys()
		keys.sort()
		if str(keys) != _shown:
			_rebuild()
