# GameSync

Build the same Godot game with friends, live. Move a node and it moves on their
screen. Save a script or add a sprite and they get it. Join with an empty project
and the whole thing downloads.

## Play with a friend over the internet (Windows)

**Host (one person):**
1. Install Node.js (LTS) from nodejs.org.
2. Double-click `HOST.bat`. The first time it installs Cloudflare's free tunnel tool.
3. It copies an invite code like `blue-cat-river.trycloudflare.com/k3x9p2`. Send it to your friends.

**Everyone (host too):**
1. Copy `godot/addons/gamesync` into your project's `addons` folder.
   A friend can use a brand new empty project.
2. Project > Project Settings > Plugins, turn on GameSync.
3. In the GameSync panel, paste the invite code, type your name, press Join.

The host's window has to stay open. The invite code changes every time you host.
Only share codes with people you trust: they can change your project's files.

## What syncs

- Nodes in the scene you have open: position, rotation, scale, color, visibility,
  text, textures, adding and deleting.
- Project files: scripts, scenes, images, sounds, fonts, `.tres`, `.import`, `.uid`.
  Not shared: `.godot/`, `addons/`, `project.godot`.
- When you join, the room's files replace yours. Yours are backed up to
  `user://gamesync_backup` first.
- Who's online and what each person has selected (outlined in their color).

## Tests

```
cd server && node test_server.js
PORT=8799 node server.js     # in another window
godot --headless --path tests/proj --script res://test_sync.gd
godot --headless --path tests/proj --script res://test_files.gd
```
