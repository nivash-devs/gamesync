extends SceneTree
## Manual check, not part of the suite: a real Openverse search from Godot.
## godot --headless --path tests/proj --script res://live_openverse.gd

const AssetsWindow := preload("res://addons/gamesync/assets_window.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var win = AssetsWindow.new()
	get_root().add_child(win)
	for kind in [0, 1]:
		win.tabs.current_tab = kind
		win.query.text = "coin" if kind == 0 else "chiptune"
		win.search(true)
		for i in 1500:
			if not win.results.is_empty() or win.status.text.begins_with("No") or win.status.text.begins_with("Too") or win.status.text.begins_with("Search is down"):
				break
			await process_frame
			OS.delay_msec(10)
		print(win.kind, ": ", win.status.text)
		for r in win.results.slice(0, 3):
			print("   ", r.title, " | ", r.creator, " | ", r.license, " | ", r.ext)
	quit()
