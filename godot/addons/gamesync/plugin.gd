@tool
extends EditorPlugin
## Editor side: a dock to join a room, live sync of the open scene,
## and friends' selections drawn in the 2D view in their color.

const SyncCore := preload("res://addons/gamesync/sync_core.gd")

var core
var dock: VBoxContainer
var url_edit: LineEdit
var room_edit: LineEdit
var name_edit: LineEdit
var connect_btn: Button
var status_label: Label
var file_label: Label
var peer_list: ItemList
var _resync_pending := false


func _enter_tree() -> void:
	core = SyncCore.new()
	core.status_changed.connect(_on_status)
	core.peers_changed.connect(_on_peers)
	core.files.files_changed.connect(_on_files_changed)
	core.files.status.connect(_on_file_status)
	get_editor_interface().get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	scene_changed.connect(_on_scene_changed)
	get_editor_interface().get_selection().selection_changed.connect(_on_selection)
	set_force_draw_over_forwarding_enabled()
	_auto_join.call_deferred()


## Optional: if the project sets gamesync/room and gamesync/name,
## open the main scene and join right away.
func _auto_join() -> void:
	var room := str(ProjectSettings.get_setting("gamesync/room", ""))
	var who := str(ProjectSettings.get_setting("gamesync/name", ""))
	if room == "" or who == "":
		return
	await get_tree().create_timer(1.5).timeout
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene != "" and get_editor_interface().get_edited_scene_root() == null:
		get_editor_interface().open_scene_from_path(main_scene)
		await get_tree().process_frame
	if get_editor_interface().get_edited_scene_root() is CanvasItem:
		get_editor_interface().set_main_screen_editor("2D")
	room_edit.text = room
	name_edit.text = who
	var url := str(ProjectSettings.get_setting("gamesync/server", ""))
	if url != "":
		url_edit.text = url
	_on_connect_pressed()


func _exit_tree() -> void:
	if core:
		core.disconnect_from()
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()


func _process(_delta: float) -> void:
	if core == null:
		return
	core.poll()
	if core.is_live():
		update_overlays()


func _build_dock() -> void:
	dock = VBoxContainer.new()
	dock.name = "GameSync"
	var title := Label.new()
	title.text = "GameSync"
	dock.add_child(title)
	url_edit = _field("Server", "ws://localhost:8787")
	room_edit = _field("Invite code", "")
	room_edit.placeholder_text = "paste the code your friend sent"
	name_edit = _field("Your name", "")
	connect_btn = Button.new()
	connect_btn.text = "Join"
	connect_btn.pressed.connect(_on_connect_pressed)
	dock.add_child(connect_btn)
	status_label = Label.new()
	status_label.text = "Not connected"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(status_label)
	file_label = Label.new()
	file_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(file_label)
	peer_list = ItemList.new()
	peer_list.custom_minimum_size = Vector2(0, 140)
	peer_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_child(peer_list)


func _field(label: String, value: String) -> LineEdit:
	var l := Label.new()
	l.text = label
	dock.add_child(l)
	var e := LineEdit.new()
	e.text = value
	dock.add_child(e)
	return e


func _on_connect_pressed() -> void:
	if core.is_live() or connect_btn.text == "Leave":
		core.disconnect_from()
		connect_btn.text = "Join"
		return
	var who := name_edit.text.strip_edges()
	var target: Array = SyncCore.parse_invite(room_edit.text, url_edit.text.strip_edges())
	if target[1] == "" or who == "":
		status_label.text = "Paste an invite code and type your name"
		return
	_on_scene_changed(get_editor_interface().get_edited_scene_root())
	core.connect_to(target[0], target[1], who)
	connect_btn.text = "Leave"


func _on_file_status(text: String) -> void:
	if file_label:
		file_label.text = text


## New or changed files came from the room: let Godot pick them up.
func _on_files_changed(_paths: Array) -> void:
	_resync_pending = true
	get_editor_interface().get_resource_filesystem().scan()


func _on_filesystem_changed() -> void:
	if not _resync_pending:
		return
	_resync_pending = false
	# Joined with an empty project? Open whatever a friend is editing.
	if get_editor_interface().get_edited_scene_root() == null:
		for p in core.peers:
			var s := str(p.get("scene", ""))
			if s != "" and FileAccess.file_exists(s):
				get_editor_interface().open_scene_from_path(s)
				get_editor_interface().set_main_screen_editor("2D")
				return
	core.resync_scene()


func _on_scene_changed(root: Node) -> void:
	var key := ""
	if root and root.scene_file_path != "":
		key = root.scene_file_path
	core.set_root(root if key != "" else null, key)
	if root and key == "" and core.is_live():
		status_label.text = "Save this scene first so friends can open it too"


func _on_selection() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	var paths: Array = []
	for n in get_editor_interface().get_selection().get_selected_nodes():
		if n == root or root.is_ancestor_of(n):
			paths.append(str(root.get_path_to(n)))
	core.set_selection(paths)


func _on_status(text: String) -> void:
	if status_label:
		status_label.text = text


func _on_peers() -> void:
	if peer_list == null:
		return
	peer_list.clear()
	for p in core.peers:
		var line := str(p.name)
		if int(p.id) == core.my_id:
			line += " (you)"
		if str(p.scene) != "":
			line += "  ·  " + str(p.scene).get_file()
		if p.selected is Array and not p.selected.is_empty():
			line += "  ·  " + str(p.selected[0]).get_file()
		var i := peer_list.add_item(line)
		peer_list.set_item_custom_fg_color(i, Color.html(str(p.color)))


## Outline what each friend has selected, in their color, with their name.
func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	if core == null or not core.is_live() or core.root == null:
		return
	var vp := get_editor_interface().get_editor_viewport_2d()
	var font := ThemeDB.fallback_font
	for p in core.peers:
		if int(p.id) == core.my_id or str(p.scene) != core.scene_key:
			continue
		if not (p.selected is Array):
			continue
		var col := Color.html(str(p.color))
		for path in p.selected:
			var node: Node = core.root.get_node_or_null(str(path))
			if not (node is CanvasItem):
				continue
			var rect: Rect2 = Rect2(-12, -12, 24, 24)
			if node is Control:
				rect = Rect2(Vector2.ZERO, (node as Control).size)
			elif node.has_method("get_rect"):
				rect = node.call("get_rect")
			var xf: Transform2D = vp.global_canvas_transform * (node as CanvasItem).get_global_transform_with_canvas()
			var pts := PackedVector2Array([
				xf * rect.position,
				xf * Vector2(rect.end.x, rect.position.y),
				xf * rect.end,
				xf * Vector2(rect.position.x, rect.end.y),
				xf * rect.position,
			])
			overlay.draw_polyline(pts, col, 2.0)
			overlay.draw_string(font, pts[0] + Vector2(0, -6), str(p.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
