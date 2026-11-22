extends SceneTree
## Two friends, each with their own project folder. Checks that files flow
## between them: join, save, add, delete, backups, and that junk is ignored.

const SyncCore := preload("res://addons/gamesync/sync_core.gd")
const URL := "ws://127.0.0.1:8799"

var passed := 0
var failed := 0
var cores: Array = []


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("ok   ", label)
	else:
		failed += 1
		print("FAIL ", label)


func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<missing>"


func wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		wipe(dir.path_join(sub))
		d.remove(sub)


func friend(who: String, base: String) -> Object:
	var c = SyncCore.new()
	c.files.base = base
	c.files.backup_dir = base.path_join("../" + who + "_backup").simplify_path()
	c.connect_to(URL, "files-room", who)
	cores.append(c)
	return c


func pump(frames: int = 1) -> void:
	for i in frames:
		for c in cores:
			c.poll()
		await process_frame
		OS.delay_msec(10)


func wait_for(cond: Callable, label: String, max_frames: int = 500) -> void:
	for i in max_frames:
		if cond.call():
			check(true, label)
			return
		await pump()
	check(false, label + " (timed out)")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var A := "user://gs_test/a"
	var B := "user://gs_test/b"
	wipe("user://gs_test")
	# A has a small project. B has an older copy of one script and nothing else.
	write(A + "/player.gd", "extends Sprite2D\nvar speed = 200\n")
	write(A + "/art/hero.svg", "<svg xmlns='http://www.w3.org/2000/svg'/>")
	write(A + "/levels/level1.tscn", "[gd_scene format=3]\n")
	write(A + "/.godot/cache.bin", "machine-specific")
	write(A + "/addons/evil/plugin.gd", "should never be shared")
	write(B + "/player.gd", "extends Sprite2D\nvar speed = 50\n")
	write(B + "/notes.txt", "B's own notes")

	var a = friend("Nivash", A)
	await wait_for(func(): return a.files.ready, "A joins and shares its files")
	var b = friend("Arjun", B)
	await wait_for(func(): return b.files.ready and b.files._pending == 0, "B joins and downloads")
	await pump(20)

	check(read(B + "/art/hero.svg").contains("svg"), "B gets A's image in a subfolder")
	check(read(B + "/levels/level1.tscn").begins_with("[gd_scene"), "B gets A's scene file")
	check(read(B + "/player.gd").contains("200"), "room's version of player.gd wins on join")
	var backups := []
	_find(B.path_join("../Arjun_backup").simplify_path(), backups)
	check(backups.any(func(p): return p.ends_with("player.gd") and read(p).contains("50")), "B's old player.gd was backed up first")
	await wait_for(func(): return read(A + "/notes.txt") == "B's own notes", "B's own file goes to A")
	check(read(B + "/.godot/cache.bin") == "<missing>", ".godot folder is never shared")
	check(read(B + "/addons/evil/plugin.gd") == "<missing>", "addons are never shared")

	# Live edits.
	write(A + "/player.gd", "extends Sprite2D\nvar speed = 999\n")
	await wait_for(func(): return read(B + "/player.gd").contains("999"), "A saves a script, B gets the new version")
	write(B + "/enemy.gd", "extends Node2D\n")
	await wait_for(func(): return read(A + "/enemy.gd") == "extends Node2D\n", "B creates a new script, A gets it")
	DirAccess.remove_absolute(A + "/notes.txt")
	await wait_for(func(): return read(B + "/notes.txt") == "<missing>", "A deletes a file, B's copy goes too")

	# Gzip: big text files travel packed and arrive exactly the same.
	var FileSync := preload("res://addons/gamesync/file_sync.gd")
	var big := "extends Node\n" + "func f():\n\tprint(\"gamesync\")\n".repeat(300)
	var packed: Dictionary = FileSync.pack(big.to_utf8_buffer(), "gd")
	check(packed.get("z", 0) == 1 and packed.data.length() < big.length() / 5, "big script gets gzipped and much smaller")
	check(not FileSync.pack(big.to_utf8_buffer(), "png").has("z") and not FileSync.pack("tiny".to_utf8_buffer(), "gd").has("z"), "images and tiny files are sent as they are")
	write(A + "/big.gd", big)
	await wait_for(func(): return read(B + "/big.gd") == big, "A saves a big script, B gets it exactly")
	b.files.on_msg({"t": "file", "path": "junk.gd", "md5": "x", "z": 1, "data": Marshalls.utf8_to_base64("not gzip")})
	check(read(B + "/junk.gd") == "<missing>", "broken gzip data is ignored")

	# No ping-pong: things settle.
	await pump(150)
	var sent_before: int = _count_files(A) + _count_files(B)
	await pump(150)
	check(_count_files(A) + _count_files(B) == sent_before and read(A + "/player.gd") == read(B + "/player.gd"), "files settle, both sides match")

	# Junk paths from the room are ignored.
	b.files.on_msg({"t": "file", "path": "../escape.gd", "md5": "x", "data": Marshalls.utf8_to_base64("bad")})
	b.files.on_msg({"t": "file", "path": "res://abs.gd", "md5": "x", "data": Marshalls.utf8_to_base64("bad")})
	b.files.on_msg({"t": "file", "path": "addons/x/plugin.gd", "md5": "x", "data": Marshalls.utf8_to_base64("bad")})
	check(read("user://gs_test/escape.gd") == "<missing>" and read(B + "/addons/x/plugin.gd") == "<missing>", "refuses paths outside the project and into addons")

	# Invite codes.
	var d := "ws://localhost:8787"
	check(SyncCore.parse_invite("abc-def.trycloudflare.com/4821", d) == ["wss://abc-def.trycloudflare.com", "4821"], "invite code -> secure address + room")
	check(SyncCore.parse_invite("  4821 ", d) == [d, "4821"], "plain room code uses default server")
	check(SyncCore.parse_invite("ws://192.168.1.5:8787/demo", d) == ["ws://192.168.1.5:8787", "demo"], "local network address works")
	check(SyncCore.parse_invite("https://abc.trycloudflare.com/x1", d) == ["wss://abc.trycloudflare.com", "x1"], "pasted https link works")
	check(SyncCore.parse_invite("", d)[1] == "", "empty code is rejected")

	print("passed %d | failed %d" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _find(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		out.append(dir.path_join(f))
	for s in d.get_directories():
		_find(dir.path_join(s), out)


func _count_files(dir: String) -> int:
	var out := []
	_find(dir, out)
	return out.size()
