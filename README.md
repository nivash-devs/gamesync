# GameSync

Build the same Godot game with friends, live. Move a node and it moves on their
screen. Save a script or add a sprite and they get it. Join with an empty project
and the whole thing downloads.

## Play with friends

1. Copy `godot/addons/gamesync` into your project's `addons` folder.
   A friend can use a brand new empty project.
2. Project > Project Settings > Plugins, turn on GameSync.
3. In the GameSync tab, type your name and press **Create room**.
4. Send the 6-letter code to your friends. They type it in and press **Join**.

The first join after a quiet period can take up to a minute while the server wakes up.
Only share codes with people you trust: they can change your project's files.

### Run your own server (optional)

Double-click `HOST.bat` (Windows). It starts a server on your PC, opens a free
Cloudflare tunnel and copies an invite code. Everyone turns on
"Use my own server" or just pastes the full invite code.

## What syncs

- Nodes in the scene you have open: position, rotation, scale, color, visibility,
  text, textures, adding and deleting.
- Project files: scripts, scenes, images, sounds, fonts, `.tres`, `.import`, `.uid`.
  Not shared: `.godot/`, `addons/`, `project.godot`.
- When you join, the room's files replace yours. Yours are backed up to
  `user://gamesync_backup` first.
- Scripts, live: open the same script and type at the same time, like Google Docs.
  Edits merge with operational transformation, so nobody's typing gets lost.
- Friends' cursors in the script, in their color with their name.
- Ctrl+Z / Ctrl+Y only undo and redo YOUR edits, never a friend's.
- Who's online, what each person has selected (outlined in their color),
  and which script they're editing.

## Tests

```
cd server && node test_ot.js && node test_server.js
PORT=8799 node server.js     # in another window
godot --headless --path tests/proj --script res://test_sync.gd
godot --headless --path tests/proj --script res://test_files.gd
godot --headless --path tests/proj --script res://test_docs.gd
```
