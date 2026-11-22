@tool
extends RefCounted
## Free assets for your game: search sounds and music (Openverse, which covers
## Freesound and Jamendo), browse curated packs, and add them to the project.
## Everything added lands in res://assets/ and gets a line in res://CREDITS.md,
## and GameSync's file sync shares it with everyone in the room.

const API := "https://api.openverse.org/v1/audio/"
const MAX_FILE := 8 * 1024 * 1024      # same limit as file sync
const LICENSES := ["cc0", "by"]         # free for any use; "by" needs credit
const AUDIO_EXTS := ["mp3", "ogg", "wav"]
const USER_AGENT := "GameSync-Godot-Plugin"

## kind: "sounds" or "music"
static func search_url(kind: String, query: String, page: int = 1) -> String:
	var q := query.strip_edges().uri_encode()
	var url := API + "?q=" + q + "&license=" + ",".join(LICENSES) + "&page_size=20&page=" + str(maxi(page, 1))
	if kind == "music":
		url += "&category=music"
	else:
		url += "&source=freesound,wikimedia_audio"
	return url


## Turns an Openverse response into plain results we can trust.
static func parse_results(json_text: String) -> Array:
	var data = JSON.parse_string(json_text)
	var out: Array = []
	if not (data is Dictionary) or not (data.get("results") is Array):
		return out
	for r in data.results:
		if not (r is Dictionary):
			continue
		var lic := str(r.get("license", "")).to_lower()
		var url := str(r.get("url", ""))
		var ext := file_ext(str(r.get("filetype", "")), url)
		if not lic in LICENSES or not url.begins_with("https://") or ext == "":
			continue
		var dur = r.get("duration")
		out.append({
			"id": str(r.get("id", "")),
			"title": str(r.get("title", "untitled")).strip_edges(),
			"creator": str(r.get("creator", "unknown")).strip_edges(),
			"license": lic,
			"license_version": str(r.get("license_version", "")),
			"url": url,
			"ext": ext,
			"seconds": (float(dur) / 1000.0) if (dur is float or dur is int) else -1.0,
			"landing": str(r.get("foreign_landing_url", "")),
			"source": str(r.get("source", "")),
		})
	return out


## "mp32" (Jamendo) is mp3. Anything Godot can't import as audio is skipped.
static func file_ext(filetype: String, url: String) -> String:
	var t := filetype.to_lower()
	if t.begins_with("mp3"):
		return "mp3"
	if t in AUDIO_EXTS:
		return t
	var from_url := url.get_file().get_extension().to_lower()
	return from_url if from_url in AUDIO_EXTS else ""


## A safe, readable file name: "deep-whoosh-1_8f3a2c1d.mp3"
static func file_name(item: Dictionary) -> String:
	var base := ""
	for ch in str(item.get("title", "")).to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			base += ch
		elif not base.ends_with("-"):
			base += "-"
	base = base.trim_prefix("-").trim_suffix("-")
	for e in AUDIO_EXTS:
		base = base.trim_suffix("-" + e)
	if base.length() > 40:
		base = base.substr(0, 40).trim_suffix("-")
	if base == "":
		base = "sound"
	var id := ""
	for ch in str(item.get("id", "")).to_lower():
		if (ch >= "a" and ch <= "f") or (ch >= "0" and ch <= "9"):
			id += ch
	return base + ("_" + id.substr(0, 8) if id != "" else "") + "." + str(item.get("ext", "mp3"))


static func folder_for(kind: String) -> String:
	return "assets/music" if kind == "music" else "assets/sfx"


static func license_name(item: Dictionary) -> String:
	if item.get("license", "") == "cc0":
		return "CC0"
	return ("CC BY " + str(item.get("license_version", ""))).strip_edges()


static func needs_credit(item: Dictionary) -> bool:
	return item.get("license", "") != "cc0"


static func credit_line(rel_path: String, item: Dictionary) -> String:
	var line := "- `%s`: \"%s\" by %s, %s" % [rel_path, item.get("title", ""), item.get("creator", ""), license_name(item)]
	if not needs_credit(item):
		line += " (no credit needed)"
	var landing := str(item.get("landing", ""))
	if landing.begins_with("https://"):
		line += ", " + landing
	return line


## Adds the line to CREDITS.md once. base: "res://" (tests use a temp folder).
static func add_credit(base: String, rel_path: String, item: Dictionary) -> void:
	var path := base.path_join("CREDITS.md")
	var text := ""
	if FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
	if text.contains("`" + rel_path + "`"):
		return
	if text == "":
		text = "# Credits\n\nAssets used in this game. Lines marked CC BY need this credit wherever the game is shared.\n\n"
	if not text.ends_with("\n"):
		text += "\n"
	text += credit_line(rel_path, item) + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)


## Writes the downloaded file into the project. Returns the project-relative
## path, or "" with an error message in err[0].
static func save(base: String, kind: String, item: Dictionary, data: PackedByteArray, err: Array) -> String:
	if data.is_empty():
		err[0] = "The download was empty."
		return ""
	if data.size() > MAX_FILE:
		err[0] = "Too big to share with your room (over 8 MB)."
		return ""
	var rel := folder_for(kind).path_join(file_name(item))
	var path := base.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		err[0] = "Couldn't write " + rel
		return ""
	f.store_buffer(data)
	f.close()
	add_credit(base, rel, item)
	return rel


## Curated packs, as served by the GameSync server at /api/packs.
static func parse_packs(json_text: String) -> Array:
	var data = JSON.parse_string(json_text)
	var out: Array = []
	if not (data is Dictionary) or not (data.get("categories") is Array):
		return out
	for c in data.categories:
		if not (c is Dictionary) or not (c.get("items") is Array):
			continue
		for it in c.items:
			if not (it is Dictionary):
				continue
			var url := str(it.get("url", ""))
			if not url.begins_with("https://"):
				continue
			out.append({
				"category": str(c.get("name", "")),
				"name": str(it.get("name", "")),
				"url": url,
				"license": str(it.get("license", "")),
				"desc": str(it.get("desc", "")),
			})
	return out


## Turns audio bytes into something the editor can play for a preview.
static func preview_stream(ext: String, data: PackedByteArray) -> AudioStream:
	if ext == "mp3":
		var s := AudioStreamMP3.new()
		s.data = data
		return s
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_buffer(data)
	return null
