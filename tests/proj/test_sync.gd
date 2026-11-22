extends SceneTree
## Three fake "friends" in one process, each with their own copy of the scene.

const SyncCore := preload("res://addons/gamesync/sync_core.gd")
const URL := "ws://127.0.0.1:8799"
const KEY := "res://main.tscn"

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


func make_friend(who: String, scene: Node) -> Object:
	get_root().add_child(scene)
	var c = SyncCore.new()
	c.share_files = false
	c.set_root(scene, KEY)
	c.connect_to(URL, "room1", who)
	cores.append(c)
	return c


func pump(frames: int = 20) -> void:
	for i in frames:
		for c in cores:
			c.poll()
		await process_frame
		OS.delay_msec(5)


func wait_for(cond: Callable, label: String, max_frames: int = 400) -> void:
	for i in max_frames:
		if cond.call():
			check(true, label)
			return
		await pump(1)
	check(false, label + " (timed out)")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# A has the real scene. B starts from an empty Node2D.
	var a_root: Node = load(KEY).instantiate()
	var a = make_friend("Nivash", a_root)
	await wait_for(func(): return a.synced, "A joins and seeds the scene")

	var b_root := Node2D.new()
	b_root.name = "Main"
	var b = make_friend("Arjun", b_root)
	await wait_for(func(): return b.synced, "B joins")
	check(b_root.get_node_or_null("Player") is Sprite2D, "B gets Player as a Sprite2D")
	check(b_root.get_node("Player").position == Vector2(200, 150), "B gets Player's position")

	# Move on A, see it on B.
	a_root.get_node("Player").position = Vector2(100, 50)
	await wait_for(func(): return b_root.get_node("Player").position == Vector2(100, 50), "A moves Player, B sees it")

	# Several props at once, including color and rotation.
	var ap: Sprite2D = a_root.get_node("Player")
	ap.rotation = 1.25
	ap.modulate = Color(1, 0, 0, 1)
	ap.flip_h = true
	await wait_for(func():
		var bp = b_root.get_node("Player")
		return is_equal_approx(bp.rotation, 1.25) and bp.modulate == Color(1, 0, 0, 1) and bp.flip_h,
		"rotation, color and flip sync")

	# B adds a node with a child.
	var enemy := Node2D.new()
	enemy.name = "Enemy"
	b_root.add_child(enemy)
	enemy.owner = b_root
	enemy.position = Vector2(-30, 7)
	var label := Label.new()
	label.name = "Tag"
	enemy.add_child(label)
	label.owner = b_root
	label.text = "boss"
	await wait_for(func(): return a_root.get_node_or_null("Enemy/Tag") is Label, "B adds Enemy/Tag, A gets both")
	check(a_root.get_node("Enemy").position == Vector2(-30, 7), "A gets Enemy position")
	check(a_root.get_node("Enemy/Tag").text == "boss", "A gets label text")

	# Texture resource by path.
	ap.texture = load("res://icon.svg")
	await wait_for(func(): return b_root.get_node("Player").texture != null and b_root.get_node("Player").texture.resource_path == "res://icon.svg", "texture syncs by file path")

	# Presence / selection.
	b.set_selection(["Enemy"])
	await wait_for(func():
		for p in a.peers:
			if p.name == "Arjun" and p.selected == ["Enemy"]:
				return true
		return false, "A sees what B selected")
	check(a.peers.size() == 2, "A sees 2 people in the room")

	# A deletes Player.
	a_root.get_node("Player").free()
	await wait_for(func(): return b_root.get_node_or_null("Player") == null, "A deletes Player, B loses it")

	# Late joiner C starts with stale stuff and gets the current room state.
	var c_root: Node = load(KEY).instantiate()  # still has Player in the file
	var c = make_friend("Riya", c_root)
	await wait_for(func(): return c.synced, "C joins late")
	check(c_root.get_node_or_null("Player") == null, "C's stale Player is removed")
	check(c_root.get_node_or_null("Enemy/Tag") is Label, "C gets Enemy/Tag")
	check(c_root.get_node("Enemy").position == Vector2(-30, 7), "C gets Enemy position")

	# No echo: after everything settles, nobody keeps sending.
	await pump(30)
	var before := [a.snap.duplicate(true), b.snap.duplicate(true)]
	await pump(30)
	check(JSON.stringify(a.snap) == JSON.stringify(before[0]) and JSON.stringify(b.snap) == JSON.stringify(before[1]), "things settle, no echo loop")

	# Bad values are ignored, not crashing.
	var ok := [true]
	SyncCore._dec(["r", "res://test_sync.gd"], ok)
	check(ok[0] == false, "refuses to load a non-texture resource")
	ok = [true]
	SyncCore._dec("junk", ok)
	check(ok[0] == false, "ignores junk values")

	# Someone leaves.
	c.disconnect_from()
	await wait_for(func(): return a.peers.size() == 2, "C leaves, A sees 2 people")

	print("passed %d | failed %d" % [passed, failed])
	quit(1 if failed > 0 else 0)
