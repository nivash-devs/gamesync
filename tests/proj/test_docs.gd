extends SceneTree
## Live script editing: math fuzz + 3 friends typing in the same script at once.

const SyncCore := preload("res://addons/gamesync/sync_core.gd")
const OT := preload("res://addons/gamesync/ot.gd")
const URL := "ws://127.0.0.1:8799"

var passed := 0
var failed := 0
var rng := RandomNumberGenerator.new()
var friends: Array = []   # [{core, text}]


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("ok   ", label)
	else:
		failed += 1
		print("FAIL ", label)


func word() -> String:
	var a := ["a", "b", "x", "\n", " ", "é", "🙂", "\t"]
	var s := ""
	for i in rng.randi_range(1, 4):
		s += a[rng.randi() % a.size()]
	return s


func random_op(length: int) -> Array:
	var op: Array = []
	var cur := length
	for k in rng.randi_range(1, 3):
		if cur > 0 and rng.randi() % 2 == 0:
			var d := rng.randi() % cur
			var n := rng.randi_range(1, mini(5, cur - d))
			op.append({"d": d, "n": n})
			cur -= n
		else:
			var s := word()
			op.append({"i": rng.randi_range(0, cur), "s": s})
			cur += s.length()
	return op


func fuzz_math() -> void:
	var ok := 0
	for t in 3000:
		var base := word() + word() + word() + word()
		var A := random_op(base.length())
		var B := random_op(base.length())
		var a_first := rng.randi() % 2 == 0
		var r := OT.transform(A, B, a_first)
		var x = OT.apply(base, A)
		x = OT.apply(x, r[1]) if x != null else null
		var y = OT.apply(base, B)
		y = OT.apply(y, r[0]) if y != null else null
		if x != null and x == y:
			ok += 1
	check(ok == 3000, "GDScript math: %d/3000 random edit pairs end up identical" % ok)
	check(OT.diff("hello world", "hello brave world") == [{"i": 6, "s": "brave "}], "diff finds a simple insert")
	var diff_ok := 0
	var small := 0
	for t in 2000:
		var x := word() + word() + word() + word() + word()
		var y = OT.apply(x, random_op(x.length()))
		if y == null:
			y = x
		var op := OT.diff(x, y)
		if OT.apply(x, op) == y:
			diff_ok += 1
	check(diff_ok == 2000, "diff: %d/2000 random edits rebuilt exactly" % diff_ok)
	var two := OT.diff("aaaa_MIDDLE_bbbb", "aXaaa_MIDDLE_bbbYb")
	check(two.size() == 2 and two[0].has("s") and two[1].has("s"), "two far-apart typed letters become two small inserts, not one big replace")
	check(OT.map_offset(10, [{"i": 2, "s": "abc"}]) == 13, "cursor after an insert moves right")
	check(OT.map_offset(10, [{"d": 8, "n": 5}]) == 8, "cursor inside a delete lands at its start")


func make_friend(who: String) -> Dictionary:
	var f := {"core": SyncCore.new(), "text": ""}
	var c = f.core
	c.share_files = false
	c.doc.get_text = func(): return f.text
	c.doc.set_text = func(t, _op): f.text = t
	c.connect_to(URL, "doc-room", who)
	friends.append(f)
	return f


func pump(frames: int = 1) -> void:
	for i in frames:
		for f in friends:
			f.core.poll()
		await process_frame
		OS.delay_msec(5)


func wait_for(cond: Callable, label: String, max_frames: int = 600) -> void:
	for i in max_frames:
		if cond.call():
			check(true, label)
			return
		await pump()
	check(false, label + " (timed out)")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	rng.seed = 42
	fuzz_math()

	var a := make_friend("Nivash")
	var b := make_friend("Arjun")
	await wait_for(func(): return a.core.is_live() and b.core.is_live(), "both join")

	a.text = "extends Node2D\n\nfunc _ready():\n\tpass\n"
	a.core.open_doc("player.gd")
	await wait_for(func(): return a.core.doc.is_open(), "A opens player.gd")
	b.text = "something old"
	b.core.open_doc("player.gd")
	await wait_for(func(): return b.core.doc.is_open() and b.text == a.text, "B opens it and gets A's text")

	# Simple typing.
	a.text = a.text.replace("pass", "print(\"hi\")")
	await wait_for(func(): return b.text.contains("print(\"hi\")"), "A types, B sees it")
	b.text = "# by Arjun\n" + b.text
	await wait_for(func(): return a.text.begins_with("# by Arjun\n"), "B types at the top, A sees it")

	# Same moment, same line.
	a.text = a.text.replace("_ready", "_ready_A")
	b.text = b.text.replace("Node2D", "Node2D_B")
	await pump(40)
	check(a.text == b.text and a.text.contains("_ready_A") and a.text.contains("Node2D_B"), "two edits at the same moment both survive")

	# Chaos: 3 people typing random edits for a while, all at once.
	var c := make_friend("Riya")
	await wait_for(func(): return c.core.is_live(), "C joins")
	c.core.open_doc("player.gd")
	await wait_for(func(): return c.core.doc.is_open() and c.text == a.text, "C opens the script mid-session and catches up")
	for round in 300:
		for f in [a, b, c]:
			if rng.randi() % 3 == 0:
				var r = OT.apply(f.text, random_op(f.text.length()))
				if r != null:
					f.text = r
		await pump(1)
	await pump(120)
	var same: bool = a.text == b.text and b.text == c.text
	check(same, "after 300 rounds of 3 people typing at once, all 3 texts match")
	check(a.text.length() < 3000, "no runaway copying (final text is %d characters)" % a.text.length())
	if not same:
		print("A: ", JSON.stringify(a.text))
		print("B: ", JSON.stringify(b.text))

	# Someone closes it and opens another script.
	b.core.open_doc("enemy.gd")
	await pump(20)
	a.text += "\n# still here"
	await pump(30)
	check(not b.text.ends_with("# still here") and c.text.ends_with("# still here"), "B moved to another script and stops getting player.gd edits")

	# ---------------- undo only undoes YOUR edits
	var u1 := make_friend("U1")
	var u2 := make_friend("U2")
	await wait_for(func(): return u1.core.is_live() and u2.core.is_live(), "undo test: two more friends join")
	u1.text = "func a():\n\tpass\n"
	u1.core.open_doc("undo.gd")
	await wait_for(func(): return u1.core.doc.is_open(), "U1 opens undo.gd")
	u2.core.open_doc("undo.gd")
	await wait_for(func(): return u2.core.doc.is_open() and u2.text == u1.text, "U2 opens it too")
	u1.core.doc._last_typed_ms = -100000
	u1.text += "# mine\n"
	await pump(20)
	u2.text = "# theirs\n" + u2.text
	await wait_for(func(): return u1.text.begins_with("# theirs") and u2.text.ends_with("# mine\n"), "both see both edits")
	u1.core.doc.undo()
	await wait_for(func(): return u2.text == "# theirs\nfunc a():\n\tpass\n", "U1 presses undo: only U1's line goes, for both people")
	check(u1.text == u2.text, "texts match after undo")
	u1.core.doc.redo()
	await wait_for(func(): return u2.text == "# theirs\nfunc a():\n\tpass\n# mine\n", "U1 presses redo: the line comes back")
	u2.core.doc.undo()
	await wait_for(func(): return u1.text == "func a():\n\tpass\n# mine\n", "U2 presses undo: only U2's line goes")
	var before_empty: String = u2.text
	check(u2.core.doc.undo() == false and u2.text == before_empty, "U2 has nothing left to undo: pressing it again does nothing (doesn't undo U1)")

	# Undo still lands right after a friend types above it.
	u1.core.doc._last_typed_ms = -100000
	u1.text = u1.text.replace("pass", "jump()")
	await pump(20)
	u2.text = "# a\n# b\n# c\n" + u2.text
	await wait_for(func(): return u1.text.begins_with("# a"), "friend adds 3 lines above")
	u1.core.doc.undo()
	await wait_for(func(): return u2.text.contains("\tpass") and not u2.text.contains("jump()") and u2.text.begins_with("# a\n# b\n# c\n"), "U1's undo still hits the right spot after lines were added above")

	# A typing burst undoes as one step.
	u1.core.doc._last_typed_ms = -100000
	var base: String = u1.text
	for ch in "hello":
		u1.text += ch
		await pump(1)
	await pump(10)
	u1.core.doc.undo()
	await wait_for(func(): return u2.text == base, "typing a word quickly undoes in one step")

	# ---------------- cursors
	u1.core.doc.my_cursor = 4
	await wait_for(func(): return u2.core.doc.cursors.has(u1.core.my_id) and u2.core.doc.cursors[u1.core.my_id].off == 4, "U2 sees U1's cursor")
	check(u2.core.doc.cursors[u1.core.my_id].name == "U1", "cursor carries U1's name")
	u2.text = "XYZ" + u2.text
	await pump(5)
	check(u2.core.doc.cursors[u1.core.my_id].off == 7, "U1's cursor shifts right when U2 types before it")
	u1.core.open_doc("")
	await wait_for(func(): return not u2.core.doc.cursors.has(u1.core.my_id), "U1 closes the script: their cursor disappears for U2")

	print("passed %d | failed %d" % [passed, failed])
	quit(1 if failed > 0 else 0)
