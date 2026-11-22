@tool
extends Window
## The "Free assets" window: search sounds and music, preview them, add them to
## the project with one click, or browse the curated packs.

const Assets := preload("res://addons/gamesync/assets.gd")
const TABS := ["sounds", "music", "packs"]

var base := "res://"                                   # tests point this elsewhere
var web := "https://gamesync-yggk.onrender.com"        # where /api/packs lives
var on_added: Callable                                 # e.g. rescan the FileSystem dock

var kind := "sounds"
var page := 1
var results: Array = []
var packs: Array = []
var _busy_item := {}
var _busy_action := ""
var _cache := {}            # url -> bytes, so preview then add downloads once
var _playing_url := ""

var tabs: TabBar
var query: LineEdit
var list: ItemList
var info: Label
var status: Label
var play_btn: Button
var add_btn: Button
var open_btn: Button
var more_btn: Button
var http_search: HTTPRequest
var http_file: HTTPRequest
var player: AudioStreamPlayer


func _init() -> void:
	title = "GameSync: free assets"
	size = Vector2i(760, 540)
	min_size = Vector2i(520, 380)
	transient = true
	exclusive = false
	visible = false
	close_requested.connect(_close)
	_build()


func _build() -> void:
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	m.add_child(col)

	tabs = TabBar.new()
	tabs.add_tab("Sounds")
	tabs.add_tab("Music")
	tabs.add_tab("Packs")
	tabs.tab_changed.connect(_on_tab)
	col.add_child(tabs)

	var row := HBoxContainer.new()
	col.add_child(row)
	query = LineEdit.new()
	query.placeholder_text = "footsteps, laser, coin, rain..."
	query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	query.text_submitted.connect(func(_t): search(true))
	row.add_child(query)
	var go := Button.new()
	go.text = "Search"
	go.pressed.connect(func(): search(true))
	row.add_child(go)

	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(_on_select)
	list.item_activated.connect(func(_i): _on_play())
	col.add_child(list)

	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(0, 40)
	col.add_child(info)

	var btns := HBoxContainer.new()
	col.add_child(btns)
	play_btn = Button.new()
	play_btn.text = "Play"
	play_btn.pressed.connect(_on_play)
	btns.add_child(play_btn)
	add_btn = Button.new()
	add_btn.text = "Add to project"
	add_btn.pressed.connect(_on_add)
	btns.add_child(add_btn)
	open_btn = Button.new()
	open_btn.text = "Open page"
	open_btn.pressed.connect(_on_open)
	btns.add_child(open_btn)
	more_btn = Button.new()
	more_btn.text = "More results"
	more_btn.pressed.connect(func(): page += 1; search(false))
	btns.add_child(more_btn)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.clip_text = true
	btns.add_child(status)

	http_search = HTTPRequest.new()
	http_search.timeout = 20
	http_search.request_completed.connect(_on_search_done)
	add_child(http_search)
	http_file = HTTPRequest.new()
	http_file.timeout = 60
	http_file.body_size_limit = Assets.MAX_FILE + 1
	http_file.request_completed.connect(_on_file_done)
	add_child(http_file)
	player = AudioStreamPlayer.new()
	player.finished.connect(func(): _playing_url = ""; _refresh_buttons())
	add_child(player)
	_refresh_buttons()


func _close() -> void:
	player.stop()
	_playing_url = ""
	hide()


func _on_tab(i: int) -> void:
	kind = TABS[clampi(i, 0, TABS.size() - 1)]
	player.stop()
	_playing_url = ""
	query.placeholder_text = {"sounds": "footsteps, laser, coin, rain...", "music": "chiptune, calm, boss fight, adventure...", "packs": "filter: pixel, tileset, ui, 3d..."}[kind]
	results = []
	list.clear()
	info.text = ""
	if kind == "packs":
		search(true)
	elif query.text.strip_edges() != "":
		search(true)
	else:
		status.text = ""
	_refresh_buttons()


func search(fresh: bool) -> void:
	if fresh:
		page = 1
	if kind == "packs":
		if packs.is_empty():
			_request(http_search, web.trim_suffix("/") + "/api/packs", "Loading packs...")
		else:
			_show_packs()
		return
	var q := query.text.strip_edges()
	if q == "":
		status.text = "Type what you need first"
		return
	_request(http_search, Assets.search_url(kind, q, page), "Searching...")


func _request(h: HTTPRequest, url: String, msg: String) -> void:
	if h.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		h.cancel_request()
	var err := h.request(url, PackedStringArray(["User-Agent: " + Assets.USER_AGENT]))
	status.text = msg if err == OK else "Couldn't start the request"


func _on_search_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		status.text = "No connection. Check your internet."
		return
	if code == 429:
		status.text = "Too many searches. Wait a minute."
		return
	if code != 200:
		status.text = "Search is down right now (%d)" % code
		return
	var text := body.get_string_from_utf8()
	if kind == "packs":
		packs = Assets.parse_packs(text)
		_show_packs()
		return
	show_results(Assets.parse_results(text), page > 1)
	var data = JSON.parse_string(text)
	more_btn.visible = data is Dictionary and int(data.get("page_count", 0)) > page


## Fills the list. Public so tests can feed it results without the network.
func show_results(items: Array, append := false) -> void:
	if not append:
		results = []
		list.clear()
	for it in items:
		results.append(it)
		var secs: float = it.seconds
		var dur := ("%d:%02d" % [int(secs) / 60, int(secs) % 60]) if secs >= 60 else ("%.1fs" % secs if secs >= 0 else "")
		var label := "%s  ·  %s  ·  %s  ·  %s" % [it.title, it.creator, dur, Assets.license_name(it)]
		list.add_item(label)
	status.text = "%d results" % results.size() if not results.is_empty() else "Nothing found. Try a simpler word."
	_refresh_buttons()


func _show_packs() -> void:
	results = []
	list.clear()
	var f := query.text.strip_edges().to_lower()
	for p in packs:
		var hay: String = (str(p.name) + " " + str(p.category) + " " + str(p.desc) + " " + str(p.license)).to_lower()
		if f != "" and not hay.contains(f):
			continue
		results.append(p)
		var i := list.add_item("%s  ·  %s  ·  %s" % [p.category, p.name, p.license])
		list.set_item_tooltip(i, p.desc)
	status.text = "%d packs" % results.size()
	more_btn.visible = false
	_refresh_buttons()


func _selected() -> Dictionary:
	var sel := list.get_selected_items()
	if sel.is_empty() or sel[0] >= results.size():
		return {}
	return results[sel[0]]


func _on_select(_i: int) -> void:
	var it := _selected()
	if it.is_empty():
		info.text = ""
	elif kind == "packs":
		info.text = it.desc + ("  License: " + it.license if it.license != "" else "")
	elif Assets.needs_credit(it):
		info.text = "%s, %s. Free to use, credit needed: it goes into CREDITS.md for you." % [it.title, Assets.license_name(it)]
	else:
		info.text = "%s, CC0. Free to use, no credit needed." % it.title
	_refresh_buttons()


func _refresh_buttons() -> void:
	var it := _selected()
	var media := kind != "packs" and not it.is_empty()
	play_btn.visible = kind != "packs"
	add_btn.visible = kind != "packs"
	play_btn.disabled = not media
	add_btn.disabled = not media
	play_btn.text = "Stop" if media and _playing_url == it.get("url", "") else "Play"
	open_btn.disabled = it.is_empty()
	if kind == "packs":
		more_btn.visible = false


func _on_play() -> void:
	var it := _selected()
	if it.is_empty() or kind == "packs":
		return
	if _playing_url == it.url:
		player.stop()
		_playing_url = ""
		_refresh_buttons()
		return
	_fetch(it, "preview")


func _on_add() -> void:
	var it := _selected()
	if not it.is_empty() and kind != "packs":
		_fetch(it, "add")


func _on_open() -> void:
	var it := _selected()
	var url := str(it.get("url" if kind == "packs" else "landing", ""))
	if url.begins_with("https://"):
		OS.shell_open(url)


func _fetch(it: Dictionary, action: String) -> void:
	if _cache.has(it.url):
		_finish(it, action, _cache[it.url])
		return
	_busy_item = it
	_busy_action = action
	_request(http_file, it.url, "Downloading...")


func _on_file_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var it := _busy_item
	_busy_item = {}
	if it.is_empty():
		return
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		status.text = "Too big to share with your room (over 8 MB)"
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.text = "Download failed. Try another one."
		return
	if _cache.size() > 20:
		_cache.clear()
	_cache[it.url] = body
	_finish(it, _busy_action, body)


## Preview or save downloaded bytes. Public so tests can skip the network.
func _finish(it: Dictionary, action: String, data: PackedByteArray) -> String:
	if action == "preview":
		var s := Assets.preview_stream(it.ext, data)
		if s == null:
			status.text = "No preview for .%s files, but you can still add it" % it.ext
			return ""
		player.stream = s
		player.play()
		_playing_url = it.url
		status.text = "Playing"
		_refresh_buttons()
		return ""
	var err := [""]
	var rel := Assets.save(base, kind, it, data, err)
	if rel == "":
		status.text = err[0]
		return ""
	status.text = "Added " + rel + ". Your room gets it too."
	if on_added.is_valid():
		on_added.call()
	return rel
