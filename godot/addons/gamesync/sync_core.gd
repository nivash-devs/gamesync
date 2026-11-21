@tool
extends RefCounted
## Keeps one scene in sync with a room on the gamesync server.
## Works on any root Node, so it runs inside the editor plugin and in tests.

signal status_changed(text: String)
signal peers_changed

const PROPS := [
	"position", "rotation", "scale", "skew", "visible", "modulate", "self_modulate",
	"z_index", "texture", "flip_h", "flip_v", "frame", "centered", "offset",
	"text", "size", "color",
]

var ws := WebSocketPeer.new()
var root: Node = null
var scene_key := ""
var room := ""
var my_name := ""
var my_id := -1
var my_color := Color.WHITE
var peers: Array = []          # [{id, name, color, scene, selected}]
var snap := {}                 # path -> {cls, inst, props}
var synced := false            # true once we have the room's copy of this scene
var _joined := false
var _last_state := -1
var _last_selected: Array = []


func connect_to(url: String, room_code: String, display_name: String) -> void:
	room = room_code
	my_name = display_name
	_joined = false
	synced = false
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	var err := ws.connect_to_url(url)
	status_changed.emit("Connecting..." if err == OK else "Bad server address")


func disconnect_from() -> void:
	ws.close()
	_joined = false
	synced = false
	peers = []
	peers_changed.emit()
	status_changed.emit("Not connected")


func is_live() -> bool:
	return _joined and ws.get_ready_state() == WebSocketPeer.STATE_OPEN


## Call when the open scene changes. key is the scene file path.
func set_root(node: Node, key: String) -> void:
	root = node
	scene_key = key
	synced = false
	snap = {}
	if is_live():
		_hello()


func set_selection(paths: Array) -> void:
	if paths == _last_selected:
		return
	_last_selected = paths.duplicate()
	if is_live():
		_send({"t": "select", "paths": paths})


## Call often (every frame is fine).
func poll() -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st != _last_state:
		_last_state = st
		if st == WebSocketPeer.STATE_OPEN:
			_send({"t": "join", "room": room, "name": my_name})
		elif st == WebSocketPeer.STATE_CLOSED:
			if _joined or synced:
				status_changed.emit("Disconnected")
			_joined = false
			synced = false
			peers = []
			peers_changed.emit()
	while ws.get_available_packet_count() > 0:
		var parsed = JSON.parse_string(ws.get_packet().get_string_from_utf8())
		if parsed is Dictionary:
			_on_msg(parsed)
	if synced and is_instance_valid(root):
		_push_local_changes()


func _send(msg: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


func _hello() -> void:
	if root and scene_key != "":
		_send({"t": "hello", "scene": scene_key})
		status_changed.emit("Syncing " + scene_key.get_file() + "...")


# ---------------------------------------------------------------- incoming

func _on_msg(m: Dictionary) -> void:
	match m.get("t", ""):
		"welcome":
			_joined = true
			my_id = int(m.id)
			my_color = Color.html(str(m.color))
			status_changed.emit("Connected to room " + room)
			if not _last_selected.is_empty():
				_send({"t": "select", "paths": _last_selected})
			_hello()
		"presence":
			peers = m.peers
			peers_changed.emit()
		"state":
			if m.scene != scene_key or root == null:
				return
			if m.nodes == null:
				snap = _collect()
				_send({"t": "seed", "scene": scene_key, "nodes": snap})
			else:
				_apply_state(m.nodes)
				snap = _collect()
			synced = true
			status_changed.emit("Live: " + scene_key.get_file())
		"set":
			if synced and m.scene == scene_key:
				_apply_set(str(m.path), m.props)
		"add":
			if synced and m.scene == scene_key:
				_apply_add(str(m.path), str(m.cls), str(m.get("inst", "")), m.props)
		"remove":
			if synced and m.scene == scene_key:
				_apply_remove(str(m.path))


func _apply_state(nodes: Dictionary) -> void:
	# Remove local nodes the room doesn't have (deepest first is not needed,
	# removing a parent removes its children).
	var local := _collect()
	for p in local.keys():
		if p != "." and not nodes.has(p) and is_instance_valid(root.get_node_or_null(p)):
			_apply_remove(p)
	var paths: Array = nodes.keys()
	paths.sort_custom(func(a, b): return _depth(a) < _depth(b))
	for p in paths:
		var n: Dictionary = nodes[p]
		_apply_add(p, str(n.cls), str(n.get("inst", "")), n.props)


func _apply_set(path: String, props: Dictionary) -> void:
	var node := root.get_node_or_null(path) if path != "." else root
	if node == null:
		return
	for k in props.keys():
		if k in PROPS and k in node:
			var ok := [true]
			var v = _dec(props[k], ok)
			if ok[0]:
				node.set(k, v)
	if snap.has(path):
		snap[path].props = _props(node)
	_touched()


func _apply_add(path: String, cls: String, inst: String, props: Dictionary) -> void:
	var existing := root if path == "." else root.get_node_or_null(path)
	if existing == null:
		var cut := path.rfind("/")
		var parent_path := "." if cut == -1 else path.substr(0, cut)
		var child_name := path if cut == -1 else path.substr(cut + 1)
		var parent := root if parent_path == "." else root.get_node_or_null(parent_path)
		if parent == null:
			return
		var node := _make(cls, inst)
		if node == null:
			return
		node.name = child_name
		parent.add_child(node)
		node.owner = root
		existing = node
	_apply_set(path, props)
	snap[path] = _entry(existing)


func _apply_remove(path: String) -> void:
	if path == ".":
		return
	var node := root.get_node_or_null(path)
	if node:
		node.get_parent().remove_child(node)
		node.queue_free()
	for k in snap.keys():
		if k == path or k.begins_with(path + "/"):
			snap.erase(k)
	_touched()


func _make(cls: String, inst: String) -> Node:
	if inst.begins_with("res://") and (inst.ends_with(".tscn") or inst.ends_with(".scn")) and ResourceLoader.exists(inst):
		var ps = load(inst)
		if ps is PackedScene:
			return ps.instantiate()
	if ClassDB.class_exists(cls) and ClassDB.can_instantiate(cls) and ClassDB.is_parent_class(cls, "Node"):
		return ClassDB.instantiate(cls)
	return null


## Lets the editor know the scene changed so it can be saved.
func _touched() -> void:
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		var ei = Engine.get_singleton("EditorInterface")
		if ei and ei.has_method("mark_scene_as_unsaved"):
			ei.mark_scene_as_unsaved()


# ---------------------------------------------------------------- outgoing

func _push_local_changes() -> void:
	var now := _collect()
	# Removed nodes: only send the top one, the server drops its children.
	for p in snap.keys():
		if not now.has(p):
			var cut: int = str(p).rfind("/")
			var parent_p: String = "." if cut == -1 else str(p).substr(0, cut)
			if parent_p == "." or now.has(parent_p):
				_send({"t": "remove", "scene": scene_key, "path": p})
	# Added nodes (or class swapped), parents first.
	var added: Array = []
	for p in now.keys():
		if not snap.has(p) or snap[p].cls != now[p].cls or snap[p].inst != now[p].inst:
			added.append(p)
	added.sort_custom(func(a, b): return _depth(a) < _depth(b))
	for p in added:
		if snap.has(p):
			_send({"t": "remove", "scene": scene_key, "path": p})
		_send({"t": "add", "scene": scene_key, "path": p, "cls": now[p].cls, "inst": now[p].inst, "props": now[p].props})
	# Changed properties.
	for p in now.keys():
		if added.has(p) or not snap.has(p):
			continue
		var before: Dictionary = snap[p].props
		var after: Dictionary = now[p].props
		var diff := {}
		for k in after.keys():
			if not before.has(k) or JSON.stringify(before[k]) != JSON.stringify(after[k]):
				diff[k] = after[k]
		if not diff.is_empty():
			_send({"t": "set", "scene": scene_key, "path": p, "props": diff})
	snap = now


func _collect() -> Dictionary:
	var out := {}
	if is_instance_valid(root):
		_walk(root, out)
	return out


func _walk(n: Node, out: Dictionary) -> void:
	out[str(root.get_path_to(n))] = _entry(n)
	for c in n.get_children():
		if c.owner == root:
			_walk(c, out)


func _entry(n: Node) -> Dictionary:
	return {"cls": n.get_class(), "inst": n.scene_file_path if n != root else "", "props": _props(n)}


func _props(n: Node) -> Dictionary:
	var out := {}
	for k in PROPS:
		if k in n:
			var e = _enc(n.get(k))
			if e != null:
				out[k] = e
	return out


static func _depth(p: String) -> int:
	return 0 if p == "." else p.count("/") + 1


# ---------------------------------------------------------------- values
# Values go over the wire as small tagged arrays so types survive JSON.

static func _enc(v):
	match typeof(v):
		TYPE_BOOL: return ["b", v]
		TYPE_INT: return ["i", v]
		TYPE_FLOAT: return ["f", v]
		TYPE_STRING: return ["s", v]
		TYPE_VECTOR2: return ["v2", v.x, v.y]
		TYPE_VECTOR2I: return ["v2i", v.x, v.y]
		TYPE_VECTOR3: return ["v3", v.x, v.y, v.z]
		TYPE_COLOR: return ["c", v.r, v.g, v.b, v.a]
		TYPE_NIL: return ["n"]
		TYPE_OBJECT:
			if v is Resource and v.resource_path.begins_with("res://") and not v.resource_path.contains("::"):
				return ["r", v.resource_path]
	return null


static func _dec(e, ok: Array):
	if not (e is Array) or e.is_empty():
		ok[0] = false
		return null
	match str(e[0]):
		"b": return bool(e[1])
		"i": return int(e[1])
		"f": return float(e[1])
		"s": return str(e[1])
		"v2": return Vector2(e[1], e[2])
		"v2i": return Vector2i(int(e[1]), int(e[2]))
		"v3": return Vector3(e[1], e[2], e[3])
		"c": return Color(e[1], e[2], e[3], e[4])
		"n": return null
		"r":
			var path := str(e[1])
			if path.begins_with("res://") and ResourceLoader.exists(path):
				var res = load(path)
				if res is Texture2D:
					return res
	ok[0] = false
	return null
