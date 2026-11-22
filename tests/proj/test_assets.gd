extends SceneTree
## Free assets: search URLs, license filtering, safe file names, credits,
## the window's add flow, and packs loaded from the server (needs it on 8799).

const Assets := preload("res://addons/gamesync/assets.gd")
const AssetsWindow := preload("res://addons/gamesync/assets_window.gd")
const BASE := "user://gs_assets_test"

var passed := 0
var failed := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("ok   ", label)
	else:
		failed += 1
		print("FAIL ", label)


func wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		wipe(dir.path_join(sub))
		d.remove(sub)


func read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<missing>"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	wipe(BASE)
	DirAccess.make_dir_recursive_absolute(BASE)

	# Search URLs
	var u := Assets.search_url("sounds", "  coin pickup ")
	check(u.begins_with("https://api.openverse.org/v1/audio/?q=coin%20pickup&license=cc0,by"), "sound search is encoded and only asks for free licenses")
	check(u.contains("source=freesound") and not u.contains("category=music"), "sounds come from Freesound")
	check(Assets.search_url("music", "boss", 3).contains("category=music") and Assets.search_url("music", "boss", 3).contains("page=3"), "music search asks for music, with paging")

	# Results: only licenses that are free for games, only real https audio
	var fixture := JSON.stringify({"page_count": 2, "results": [
		{"id": "8f3a2c1d-aaaa", "title": "Coin GET!", "creator": "plasterbrain", "license": "cc0", "license_version": "1.0", "url": "https://cdn.freesound.org/a.mp3", "filetype": "mp3", "duration": 300, "foreign_landing_url": "https://freesound.org/s/1"},
		{"id": "2", "title": "Video Game Coin", "creator": "harriet", "license": "by", "license_version": "4.0", "url": "https://cdn.freesound.org/b.mp3", "filetype": "mp3", "duration": 700, "foreign_landing_url": "https://freesound.org/s/2"},
		{"id": "3", "title": "No commercial", "creator": "x", "license": "by-nc", "url": "https://cdn.freesound.org/c.mp3", "filetype": "mp3"},
		{"id": "4", "title": "No edits", "creator": "x", "license": "by-nd", "url": "https://cdn.freesound.org/d.mp3", "filetype": "mp3"},
		{"id": "5", "title": "Plain http", "creator": "x", "license": "cc0", "url": "http://example.com/e.mp3", "filetype": "mp3"},
		{"id": "6", "title": "Weird format", "creator": "x", "license": "cc0", "url": "https://example.com/f.aiff", "filetype": "aiff"},
		{"id": "7", "title": "Jamendo track", "creator": "y", "license": "by", "license_version": "3.0", "url": "https://prod-1.storage.jamendo.com/?trackid=1&format=mp32", "filetype": "mp32", "duration": 125000},
	]})
	var items := Assets.parse_results(fixture)
	check(items.size() == 3, "NonCommercial, NoDerivatives, http and odd formats are dropped (kept %d)" % items.size())
	check(items[2].ext == "mp3", "Jamendo's mp32 counts as mp3")
	check(Assets.parse_results("not json").is_empty() and Assets.parse_results("{}").is_empty(), "junk responses give no results")

	# File names
	check(Assets.file_name(items[0]) == "coin-get_8f3a2c1d.mp3", "readable file name with a short id (%s)" % Assets.file_name(items[0]))
	var evil := {"id": "../../x", "title": "../../etc/passwd\\..", "ext": "mp3"}
	var fname := Assets.file_name(evil)
	check(not fname.contains("/") and not fname.contains("\\") and not fname.contains(".."), "file names can't escape the folder (%s)" % fname)
	check(Assets.file_name({"title": "Splash, Jumping, C.wav", "id": "", "ext": "mp3"}) == "splash-jumping-c.mp3", "old extensions in titles are dropped")

	# Credits
	var cc0_line := Assets.credit_line("assets/sfx/a.mp3", items[0])
	var by_line := Assets.credit_line("assets/sfx/b.mp3", items[1])
	check(cc0_line.contains("CC0") and cc0_line.contains("no credit needed"), "CC0 lines say no credit is needed")
	check(by_line.contains("Video Game Coin") and by_line.contains("harriet") and by_line.contains("CC BY 4.0") and by_line.contains("https://freesound.org/s/2"), "CC BY lines name the title, creator, license and source")

	# Saving
	var err := [""]
	var rel := Assets.save(BASE, "sounds", items[1], PackedByteArray([1, 2, 3, 4]), err)
	check(rel == "assets/sfx/video-game-coin_2.mp3" and FileAccess.file_exists(BASE.path_join(rel)), "sound saved under assets/sfx")
	Assets.save(BASE, "sounds", items[1], PackedByteArray([1, 2, 3, 4]), err)
	var credits := read(BASE.path_join("CREDITS.md"))
	check(credits.begins_with("# Credits") and credits.count("video-game-coin_2.mp3") == 1, "CREDITS.md gets one line per file, no duplicates")
	var big := PackedByteArray()
	big.resize(Assets.MAX_FILE + 1)
	check(Assets.save(BASE, "sounds", items[0], big, err) == "" and err[0].contains("8 MB"), "files over 8 MB are refused, so the room can share everything")
	check(Assets.save(BASE, "sounds", items[0], PackedByteArray(), err) == "", "empty downloads are refused")
	check(Assets.preview_stream("mp3", PackedByteArray([0])) is AudioStreamMP3 and Assets.preview_stream("wav", PackedByteArray([0])) == null, "mp3 previews, wav adds without preview")

	# Packs
	var packs_json := JSON.stringify({"categories": [{"name": "Pixel art", "items": [
		{"name": "Tiny Dungeon", "url": "https://kenney.nl/assets/tiny-dungeon", "license": "CC0", "desc": "tiles"},
		{"name": "Sneaky", "url": "javascript:alert(1)", "license": "CC0"},
		{"name": "Plain", "url": "http://example.com", "license": "CC0"}]}]})
	var packs := Assets.parse_packs(packs_json)
	check(packs.size() == 1 and packs[0].category == "Pixel art", "pack links must be https")

	# The window: add flow without the network
	var win = AssetsWindow.new()
	win.base = BASE
	get_root().add_child(win)
	win.show_results(items)
	check(win.list.item_count == 3 and win.list.get_item_text(0).contains("CC0"), "window lists results with their license")
	win.list.select(0)
	win._on_select(0)
	check(win.info.text.contains("no credit needed"), "picking a CC0 sound says no credit is needed")
	var added_calls := [0]
	win.on_added = func(): added_calls[0] += 1
	var r2: String = win._finish(items[0], "add", PackedByteArray([9, 9, 9]))
	check(r2 == "assets/sfx/coin-get_8f3a2c1d.mp3" and FileAccess.file_exists(BASE.path_join(r2)), "Add to project saves the file")
	check(added_calls[0] == 1 and win.status.text.contains("Your room gets it too"), "after adding, the editor rescans and the status says the room gets it")

	# Packs from the real server
	win.web = "http://127.0.0.1:8799"
	win.tabs.current_tab = 2
	for i in 400:
		if not win.results.is_empty():
			break
		await process_frame
		OS.delay_msec(10)
	check(win.results.size() >= 20, "Packs tab loads the curated list from the server (%d)" % win.results.size())
	check(not win.play_btn.visible and win.open_btn.visible, "packs open their page instead of downloading")
	win.query.text = "pixel"
	win.search(true)
	check(win.results.size() >= 1 and win.results.size() < 20, "packs can be filtered (%d)" % win.results.size())

	# A real download through the window (from the local server, so no outside traffic)
	win.tabs.current_tab = 0
	var local := {"id": "abc123", "title": "Local test", "creator": "me", "license": "cc0", "license_version": "1.0",
		"url": "http://127.0.0.1:8799/api/packs", "ext": "mp3", "seconds": 1.0, "landing": ""}
	win.show_results([local])
	win.list.select(0)
	win._on_select(0)
	win._on_add()
	for i in 400:
		if win.status.text.begins_with("Added"):
			break
		await process_frame
		OS.delay_msec(10)
	check(FileAccess.file_exists(BASE.path_join("assets/sfx/local-test_abc123.mp3")), "Add to project downloads and saves for real")

	win.queue_free()
	wipe(BASE)
	print("passed %d | failed %d" % [passed, failed])
	quit(1 if failed > 0 else 0)
