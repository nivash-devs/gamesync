extends SceneTree
## Two friends in a room, the server restarts (like a Render redeploy),
## both get back in by themselves and keep syncing.
## Starts its own server on port 8798, so nothing else needs to run.

const SyncCore := preload("res://addons/gamesync/sync_core.gd")
const PORT := "8798"
const URL := "ws://127.0.0.1:8798"
const KEY := "res://main.tscn"

var passed := 0
var failed := 0
var cores: Array = []
var server_pid := -1


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("ok   ", label)
	else:
		failed += 1
		print("FAIL ", label)


func start_server() -> void:
	OS.set_environment("PORT", PORT)
	var js := ProjectSettings.globalize_path("res://").path_join("../../server/server.js").simplify_path()
	server_pid = OS.create_process("node", [js])
	OS.delay_msec(1500)


func stop_server() -> void:
	if server_pid > 0:
		OS.kill(server_pid)
		server_pid = -1


func make_friend(who: String, scene: Node) -> Object:
	get_root().add_child(scene)
	var c = SyncCore.new()
	c.share_files = false
	c.set_root(scene, KEY)
	c.connect_to(URL, "ROOM42", who)
	cores.append(c)
	return c


func pump(frames: int = 20) -> void:
	for i in frames:
		for c in cores:
			c.poll()
		await process_frame
		OS.delay_msec(5)


func wait_for(cond: Callable, label: String, max_frames: int = 1500) -> void:
	for i in max_frames:
		if cond.call():
			check(true, label)
			return
		await pump(1)
	check(false, label + " (timed out)")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	start_server()
	var a_root: Node = load(KEY).instantiate()
	var a = make_friend("Nivash", a_root)
	await wait_for(func(): return a.synced, "A joins")
	var b_root := Node2D.new()
	b_root.name = "Main"
	var b = make_friend("Arjun", b_root)
	await wait_for(func(): return b.synced, "B joins")

	# The server goes away.
	stop_server()
	await wait_for(func(): return not a.is_live() and not b.is_live(), "both notice the server is gone")
	check(a.room == "ROOM42" and b.room == "ROOM42", "both keep the room code")

	# A edits while offline.
	a_root.get_node("Player").position = Vector2(321, 123)

	# Server comes back (empty, like after a redeploy).
	await pump(40)
	start_server()
	await wait_for(func(): return a.synced and b.synced, "both get back in by themselves")
	await wait_for(func(): return a.peers.size() == 2 and b.peers.size() == 2, "both see each other again")
	await wait_for(func():
		return a_root.get_node("Player").position == b_root.get_node("Player").position,
		"scene matches again after reconnect")

	# Syncing still works.
	b_root.get_node("Player").position = Vector2(7, 8)
	await wait_for(func(): return a_root.get_node("Player").position == Vector2(7, 8), "B moves Player, A sees it")

	# Leave stops the retries.
	a.disconnect_from()
	stop_server()
	await pump(300)
	check(not a.is_live() and a._retry_at == 0, "after Leave, no reconnecting")

	stop_server()
	print("passed %d | failed %d" % [passed, failed])
	quit(1 if failed > 0 else 0)
