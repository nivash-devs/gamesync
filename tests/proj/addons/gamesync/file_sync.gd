@tool
extends RefCounted
## Shares project files (scripts, images, sounds, scenes...) with the room.
## On join: files the room has replace ours (ours are backed up first),
## files only we have get uploaded. After that, every save goes out live.

signal files_changed(paths: Array)   # files we wrote from the room
signal status(text: String)

const MAX_FILE := 8 * 1024 * 1024
const EXTS := [
	"gd", "gdshader", "tscn", "tres", "res", "uid", "import",
	"png", "jpg", "jpeg", "svg", "webp", "bmp",
	"wav", "ogg", "mp3", "ttf", "otf", "json", "txt", "md", "csv",
]
const SKIP_DIRS := ["res://.godot", "res://addons", "res://.git", "res://.import"]

var base := "res://"                  # tests point this somewhere else
var backup_dir := "user://gamesync_backup"
var send: Callable                    # func(msg: Dictionary)
var index := {}                       # path -> {mtime, md5}
var skip_paths: Array = []            # relative paths to leave alone, e.g. live scenes
var ready := false
var _pending := 0
var _received: Array = []


func reset() -> void:
	ready = false
	_pending = 0
	_received = []


## Called right after we join a room.
func start() -> void:
	index = _scan()
	var manifest := {}
	for p in index.keys():
		manifest[_rel(p)] = index[p].md5
	send.call({"t": "fhello", "files": manifest})


func on_msg(m: Dictionary) -> void:
	match m.get("t", ""):
		"fstate":
			_on_state(m)
		"file":
			_on_file(m)
		"fdel":
			_on_del(_abs(str(m.get("path", ""))))


func _on_state(m: Dictionary) -> void:
	var room_files: Dictionary = m.get("files", {})
	# Ask for anything the room has that we don't, or that differs.
	for r in room_files.keys():
		var p := _abs(str(r))
		if not _allowed(p):
			continue
		if not index.has(p) or (index[p].md5 != room_files[r] and not _skipped(p)):
			_pending += 1
			send.call({"t": "fget", "path": str(r)})
	# Upload files only we have (live scenes too, so new friends get them once).
	for p in index.keys():
		if not room_files.has(_rel(p)):
			_upload(p)
	ready = true
	_report()


func _on_file(m: Dictionary) -> void:
	var path := _abs(str(m.get("path", "")))
	if m.get("missing", false) or not _allowed(path):
		_done_one()
		return
	var data := Marshalls.base64_to_raw(str(m.get("data", "")))
	if data.size() > MAX_FILE:
		return
	if FileAccess.file_exists(path) and _skipped(path):
		_done_one()
		return
	if FileAccess.file_exists(path):
		if FileAccess.get_md5(path) == str(m.get("md5", "")):
			_mark(path)
			_done_one()
			return
		_backup(path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_done_one()
		return
	f.store_buffer(data)
	f.close()
	_mark(path)
	_received.append(path)
	_done_one()


func _on_del(path: String) -> void:
	if not _allowed(path) or _skipped(path) or not FileAccess.file_exists(path):
		return
	_backup(path)
	DirAccess.remove_absolute(path)
	index.erase(path)
	_received.append(path)
	_flush()


func _done_one() -> void:
	if _pending > 0:
		_pending -= 1
	_report()
	_flush()


func _flush() -> void:
	if _pending == 0 and not _received.is_empty():
		var got := _received.duplicate()
		_received = []
		files_changed.emit(got)


func _report() -> void:
	if _pending > 0:
		status.emit("Downloading %d file(s)..." % _pending)
	elif ready:
		status.emit("Files in sync")


## Call every second or so. Sends saved, new and deleted files.
func poll_changes() -> void:
	if not ready:
		return
	var now := _scan()
	for p in now.keys():
		if not index.has(p) or index[p].md5 != now[p].md5:
			var is_new := not index.has(p)
			index[p] = now[p]
			if is_new or not _skipped(p):
				_upload(p)
	for p in index.keys():
		if not now.has(p):
			index.erase(p)
			send.call({"t": "fdel", "path": _rel(p)})


func _upload(p: String) -> void:
	var data := FileAccess.get_file_as_bytes(p)
	if data.size() > MAX_FILE:
		return
	send.call({"t": "fput", "path": _rel(p), "md5": index[p].md5, "data": Marshalls.raw_to_base64(data)})


func _rel(p: String) -> String:
	return p.trim_prefix(base).trim_prefix("/")


func _abs(r: String) -> String:
	return base.path_join(r)


func _mark(path: String) -> void:
	index[path] = {"mtime": FileAccess.get_modified_time(path), "md5": FileAccess.get_md5(path)}


func _backup(path: String) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var dest := backup_dir.path_join(stamp).path_join(_rel(path))
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	DirAccess.copy_absolute(path, dest)


## Live-synced scenes are handled node by node, so we don't overwrite or upload them.
func _skipped(p: String) -> bool:
	return _rel(p) in skip_paths


func _allowed(p: String) -> bool:
	if not p.begins_with(base) or p.contains("..") or p.contains("\\"):
		return false
	if _rel(p).contains(":") or _rel(p).begins_with("/"):
		return false
	for d in SKIP_DIRS:
		var dd := base.path_join(d.trim_prefix("res://"))
		if p.begins_with(dd + "/") or p == dd:
			return false
	if p.get_file() == "project.godot":
		return false
	return p.get_extension().to_lower() in EXTS


func _scan() -> Dictionary:
	var out := {}
	_scan_dir(base, out)
	return out


func _scan_dir(dir: String, out: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		var p := dir.path_join(f)
		if not _allowed(p):
			continue
		var mt := FileAccess.get_modified_time(p)
		# Timestamps are in whole seconds, so re-check anything touched just now.
		var recent := mt >= int(Time.get_unix_time_from_system()) - 2
		if index.has(p) and index[p].mtime == mt and not recent:
			out[p] = index[p]
		else:
			out[p] = {"mtime": mt, "md5": FileAccess.get_md5(p)}
	for sub in d.get_directories():
		var sp := dir.path_join(sub)
		var blocked := false
		for s in SKIP_DIRS:
			if sp == base.path_join(s.trim_prefix("res://")):
				blocked = true
		if not blocked and not sub.begins_with("."):
			_scan_dir(sp, out)
