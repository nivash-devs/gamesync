@tool
extends RefCounted
## Live-edits one text document (the script you have open) with the room.
## The server puts everyone's edits in one order. We keep at most one batch
## of edits in flight; anything typed meanwhile waits in `buffer`.
##
## Undo only touches YOUR edits. Each undo step is stored as "the op that
## reverses my edit", and gets shifted past every later edit (yours or a
## friend's) so it still points at the right characters.

const OT := preload("res://addons/gamesync/ot.gd")
const GROUP_MS := 800          # typing closer together than this undoes as one step

var send: Callable             # func(msg: Dictionary)
var get_text: Callable         # func() -> String, what's in the editor now
var set_text: Callable         # func(new_text: String, op: Array), apply a friend's edit
var set_text_own: Callable     # optional: same, for your own undo/redo (moves your cursor there)

var path := ""                 # project-relative, e.g. "player.gd"
var rev := -1                  # server version we're in sync with, -1 = waiting
var pending: Array = []        # sent, not yet confirmed
var buffer: Array = []         # typed, not yet sent
var last_text := ""

var undo_stack: Array = []     # ops that reverse my edits, newest last, valid on last_text
var redo_stack: Array = []
var _last_typed_ms := -100000

var cursors := {}              # friend id -> {off, name, color}
var my_cursor := -1            # where my cursor is (character offset)
var _sent_cursor := -2
var _cursor_ms := 0


func open(rel_path: String) -> void:
	close()
	path = rel_path
	rev = -1
	pending = []
	buffer = []
	undo_stack = []
	redo_stack = []
	cursors = {}
	_sent_cursor = -2
	last_text = get_text.call()
	send.call({"t": "dopen", "path": path, "text": last_text})


func close() -> void:
	if path != "":
		send.call({"t": "dclose", "path": path})
	path = ""
	rev = -1
	cursors = {}


func is_open() -> bool:
	return path != "" and rev >= 0


## Call every frame: picks up typing and sends it.
func poll() -> void:
	if not is_open():
		return
	poll_local_only()
	_flush()
	var now := Time.get_ticks_msec()
	if my_cursor != _sent_cursor and now - _cursor_ms > 50:
		_sent_cursor = my_cursor
		_cursor_ms = now
		send.call({"t": "dcur", "path": path, "off": my_cursor})


func poll_local_only() -> void:
	var now: String = get_text.call()
	if now != last_text:
		var op := OT.diff(last_text, now)
		_record_typing(op, last_text)
		buffer += op
		last_text = now


func _flush() -> void:
	if pending.is_empty() and not buffer.is_empty():
		pending = buffer
		buffer = []
		send.call({"t": "dop", "path": path, "rev": rev, "op": pending})


# ---------------------------------------------------------------- undo

func _record_typing(op: Array, before: String) -> void:
	var inv := OT.invert(op, before)
	var now := Time.get_ticks_msec()
	if not undo_stack.is_empty() and now - _last_typed_ms < GROUP_MS:
		# Part of the same burst: one undo step covers both.
		var top: Array = undo_stack.pop_back()
		_shift(undo_stack, op)
		undo_stack.append(inv + top)
	else:
		_shift(undo_stack, op)
		undo_stack.append(inv)
	redo_stack = []
	_last_typed_ms = now
	_shift_cursors(op)


## Undo my most recent edit. Friends' edits are left alone.
func undo() -> bool:
	return _step(undo_stack, redo_stack)


func redo() -> bool:
	return _step(redo_stack, undo_stack)


func _step(from: Array, to: Array) -> bool:
	if not is_open():
		return false
	poll_local_only()
	while not from.is_empty():
		var op: Array = from.pop_back()
		var after = OT.apply(last_text, op)
		if after == null:
			continue   # couldn't place it any more; skip to the next one
		var back := OT.invert(op, last_text)
		_shift(from, op)
		_shift(to, op)
		to.append(back)
		if set_text_own.is_valid():
			set_text_own.call(after, op)
		else:
			set_text.call(after, op)
		last_text = after
		buffer += op
		_shift_cursors(op)
		_last_typed_ms = -100000   # next typing starts a new undo step
		_flush()
		return true
	return false


static func _shift(stack: Array, op: Array) -> void:
	for i in stack.size():
		stack[i] = OT.transform(stack[i], op, false)[0]


func _shift_cursors(op: Array) -> void:
	for id in cursors.keys():
		cursors[id].off = OT.map_offset(cursors[id].off, op)


# ---------------------------------------------------------------- incoming

func on_msg(m: Dictionary) -> void:
	if str(m.get("path", "")) != path or path == "":
		return
	match m.get("t", ""):
		"dstate":
			# Room's copy wins. Replace what's in the editor if it differs.
			rev = int(m.rev)
			pending = []
			buffer = []
			undo_stack = []
			redo_stack = []
			var text := str(m.text)
			var current: String = get_text.call()
			if text != current:
				set_text.call(text, OT.diff(current, text))
			last_text = text
			_sent_cursor = -2
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
			var result = OT.apply(last_text, theirs)
			if result == null:
				open(path)   # out of step somehow: start over from the room's copy
				return
			set_text.call(result, theirs)
			last_text = result
			rev = int(m.rev)
			_shift(undo_stack, theirs)
			_shift(redo_stack, theirs)
			_shift_cursors(theirs)
		"dcur":
			var id := int(m.get("id", -1))
			var off := int(m.get("off", -1))
			if off < 0:
				cursors.erase(id)
			else:
				cursors[id] = {"off": off, "name": str(m.get("name", "?")), "color": str(m.get("color", "#ffffff"))}
