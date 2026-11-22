@tool
extends RefCounted
## Keeps one scene in sync with a room on the gamesync server.
## Works on any root Node, so it runs inside the editor plugin and in tests.

signal status_changed(text: String)
signal peers_changed
signal room_changed(code: String)

const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O or 1/I mix-ups
const WAKE_TIMEOUT_MS := 100000   # free hosting can take ~1 minute to wake up

const PROPS := [
	"position", "rotation", "scale", "skew", "visible", "modulate", "self_modulate",
	"z_index", "texture", "flip_h", "flip_v", "frame", "centered", "offset",
	"text", "size", "color",
]

const FileSync := preload("res://addons/gamesync/file_sync.gd")
const DocSync := preload("res://addons/gamesync/doc_sync.gd")

var ws := WebSocketPeer.new()
var files = FileSync.new()
var doc = DocSync.new()
var share_files := true
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
var _file_timer := 0.0
var _last_tick := 0
var _url := ""
var _create := false
var _first_try_ms := 0
var _retry_at := 0
var _last_ping := 0
var _last_doc_poll := 0
var _reconnecting := false
var msg_count := 0            # goes up with every message from the room, so the UI knows when to redraw


static func random_code() -> String:
	var out := ""
	for i in 6:
		out += CODE_CHARS[randi() % CODE_CHARS.length()]
	return out


## create = true: this is a brand new room (the server refuses taken codes).
func connect_to(url: String, room_code: String, display_name: String, create := false) -> void:
	room = room_code
	my_name = display_name
	_url = url
	_create = create
	_first_try_ms = Time.get_ticks_msec()
	_retry_at = 0
	_open_socket()


func _open_socket() -> void:
	_joined = false
	synced = false
	_last_state = -1
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 16 << 20
	ws.outbound_buffer_size = 16 << 20
	files.reset()
	files.send = _send
	doc.send = _send
	doc.path = ""
	doc.rev = -1
	var err := ws.connect_to_url(_url)
	if err != OK:
		_url = ""
		status_changed.emit("Bad server address")
	elif Time.get_ticks_msec() - _first_try_ms < 1000:
		status_changed.emit("Connecting...")


func disconnect_from() -> void:
	_url = ""
	_retry_at = 0
	_reconnecting = false
	ws.close()
	_joined = false
	synced = false
	peers = []
	peers_changed.emit()
	status_changed.emit("Not connected")


func is_live() -> bool:
	return _joined and ws.get_ready_state() == WebSocketPeer.STATE_OPEN


## Turns what someone pasted into [server url, room].
## "abc.trycloudflare.com/4821" -> ["wss://abc.trycloudflare.com", "4821"]
## "4821" -> [default_url, "4821"]
static func parse_invite(text: String, default_url: String) -> Array:
	var t := text.strip_edges()
	if t == "":
		return [default_url, ""]
	var scheme := ""
	for s in ["wss://", "ws://", "https://", "http://"]:
		if t.begins_with(s):
			scheme = s
			t = t.substr(s.length())
	var cut := t.rfind("/")
	if cut == -1:
		if scheme == "":
			return [default_url, t.to_upper()]
		return ["", ""]
	var host := t.substr(0, cut)
	var room := t.substr(cut + 1)
	if host == "" or room == "":
		return ["", ""]
	var ws_scheme := "ws://" if scheme in ["ws://", "http://"] or host.begins_with("localhost") or host.begins_with("127.") or host.begins_with("192.168.") else "wss://"
	return [ws_scheme + host, room]


## Call when the open scene changes. key is the scene file path.
func set_root(node: Node, key: String) -> void:
	root = node
	scene_key = key
	_update_live_scenes()
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
			_send({"t": "join", "room": room, "name": my_name, "create": _create})
		elif st == WebSocketPeer.STATE_CLOSED:
			var never_joined := not _joined
			var now_ms := Time.get_ticks_msec()
			if _joined and _url != "":
				# We were in the room and lost it (server restart, Wi-Fi blip).
				# Rejoin the same room; whoever gets back first re-seeds it.
				_reconnecting = true
				_create = false
				_first_try_ms = now_ms
				_retry_at = now_ms + 1000
				status_changed.emit("Connection lost, reconnecting...")
			elif never_joined and _url != "" and now_ms - _first_try_ms < WAKE_TIMEOUT_MS:
				# Couldn't reach the server yet: it may be waking up or restarting.
				_retry_at = now_ms + 3000
				if _reconnecting:
					status_changed.emit("Connection lost, reconnecting...")
				else:
					status_changed.emit("Waking up the server, this can take a minute...")
			elif never_joined and _url != "":
				_url = ""
				_reconnecting = false
				status_changed.emit("Couldn't reach the server. Check your internet and try again.")
			elif _joined or synced:
				status_changed.emit("Disconnected")
			_joined = false
			synced = false
			peers = []
			peers_changed.emit()
	while ws.get_available_packet_count() > 0:
		var parsed = JSON.parse_string(ws.get_packet().get_string_from_utf8())
		if parsed is Dictionary:
			_on_msg(parsed)
	if _retry_at > 0 and Time.get_ticks_msec() >= _retry_at:
		_retry_at = 0
		if _url != "":
			_open_socket()
	if synced and is_instance_valid(root):
		_push_local_changes()
	if is_live():
		# Reading the whole script costs time, so ~30 times a second is plenty.
		if Time.get_ticks_msec() - _last_doc_poll >= 33:
			_last_doc_poll = Time.get_ticks_msec()
			doc.poll()
		if Time.get_ticks_msec() - _last_ping > 20000:
			_last_ping = Time.get_ticks_msec()
			_send({"t": "ping"})
	var now_ms := Time.get_ticks_msec()
	if share_files and is_live() and now_ms - _last_tick > 1000:
		_last_tick = now_ms
		files.poll_changes()


## Scenes someone has open are synced node by node, not as files.
func _update_live_scenes() -> void:
	var live: Array = []
	if scene_key != "":
		live.append(scene_key.trim_prefix("res://"))
	for p in peers:
		var s := str(p.get("scene", ""))
		if s != "":
			live.append(s.trim_prefix("res://"))
		var d = p.get("docs", [])
		if d is Array:
			live.append_array(d)
	if doc.path != "":
		live.append(doc.path)
	files.skip_paths = live


## Start live-editing a script. rel_path is project-relative ("player.gd").
func open_doc(rel_path: String) -> void:
	if rel_path == doc.path:
		return
	if rel_path == "":
		doc.close()
	elif is_live():
		doc.open(rel_path)
	_update_live_scenes()


## Re-ask the room for the open scene, e.g. after new files arrived.
func resync_scene() -> void:
	if is_live() and root and scene_key != "":
		synced = false
		_hello()


func _send(msg: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


func _hello() -> void:
	if root and scene_key != "":
		_send({"t": "hello", "scene": scene_key})
		status_changed.emit("Syncing " + scene_key.get_file() + "...")


# ---------------------------------------------------------------- incoming

func _on_msg(m: Dictionary) -> void:
	msg_count += 1
	match m.get("t", ""):
		"error":
			if m.get("code", "") == "room_taken" and _create:
				room = random_code()
				room_changed.emit(room)
				_send({"t": "join", "room": room, "name": my_name, "create": true})
		"welcome":
			_joined = true
			_create = false
			_reconnecting = false
			my_id = int(m.id)
			my_color = Color.html(str(m.color))
			status_changed.emit("Connected to room " + room)
			if not _last_selected.is_empty():
				_send({"t": "select", "paths": _last_selected})
			_hello()
			if share_files:
				files.start()
		"presence":
			peers = m.peers
			_update_live_scenes()
			peers_changed.emit()
		"fstate", "file", "fdel":
			if share_files:
				files.on_msg(m)
		"dstate", "dack", "dop", "dcur":
			doc.on_msg(m)
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
	paths.sort_custom(_by_depth)
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
	added.sort_custom(_by_depth)
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


# A plain method (not a lambda) so sorting also works in Godot 4.2.
func _by_depth(a, b) -> bool:
	return _depth(a) < _depth(b)


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
