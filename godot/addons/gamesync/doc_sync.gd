@tool
extends RefCounted
## Live-edits one text document (the script you have open) with the room.
## The server puts everyone's edits in one order. We keep at most one batch
## of edits in flight; anything typed meanwhile waits in `buffer`.

const OT := preload("res://addons/gamesync/ot.gd")

var send: Callable           # func(msg: Dictionary)
var get_text: Callable       # func() -> String, what's in the editor now
var set_text: Callable       # func(new_text: String, op: Array), apply a friend's edit

var path := ""               # project-relative, e.g. "player.gd"
var rev := -1                # server version we're in sync with, -1 = waiting
var pending: Array = []      # sent, not yet confirmed
var buffer: Array = []       # typed, not yet sent
var last_text := ""


func open(rel_path: String) -> void:
	close()
	path = rel_path
	rev = -1
	pending = []
	buffer = []
	last_text = get_text.call()
	send.call({"t": "dopen", "path": path, "text": last_text})


func close() -> void:
	if path != "":
		send.call({"t": "dclose", "path": path})
	path = ""
	rev = -1


func is_open() -> bool:
	return path != "" and rev >= 0


## Call every frame: picks up typing and sends it.
func poll() -> void:
	if not is_open():
		return
	var now: String = get_text.call()
	if now != last_text:
		buffer += OT.diff(last_text, now)
		last_text = now
	_flush()


func _flush() -> void:
	if pending.is_empty() and not buffer.is_empty():
		pending = buffer
		buffer = []
		send.call({"t": "dop", "path": path, "rev": rev, "op": pending})


func on_msg(m: Dictionary) -> void:
	if str(m.get("path", "")) != path or path == "":
		return
	match m.get("t", ""):
		"dstate":
			# Room's copy wins. Replace what's in the editor if it differs.
			rev = int(m.rev)
			pending = []
			buffer = []
			var text := str(m.text)
			var current: String = get_text.call()
			if text != current:
				set_text.call(text, OT.diff(current, text))
			last_text = text
		"dack":
			rev = int(m.rev)
			pending = []
			_flush()
		"dop":
			# Catch up with anything typed since the last poll first.
			poll_local_only()
			var op: Array = OT.norm(m.op)
			var r1: Array = OT.transform(op, pending, true)
			pending = r1[1]
			var r2: Array = OT.transform(r1[0], buffer, true)
			buffer = r2[1]
			var theirs: Array = r2[0]
			var current: String = get_text.call()
			var result = OT.apply(current, theirs)
			if result == null:
				open(path)   # out of step somehow: start over from the room's copy
				return
			set_text.call(result, theirs)
			last_text = result
			rev = int(m.rev)


func poll_local_only() -> void:
	var now: String = get_text.call()
	if now != last_text:
		buffer += OT.diff(last_text, now)
		last_text = now
