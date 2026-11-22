# GameSync

Build the same Godot game with friends, live.

## Use it

1. Turn it on: Project > Project Settings > Plugins > GameSync.
2. Open the **GameSync** tab (next to the Inspector).
3. Type your name and press **Create room**.
4. Press **Copy invite link** and send it to friends. They open the link,
   download a ready-made project, and import it in Godot. They join automatically.
   Or they install GameSync themselves and type the 6-letter room code.

## What syncs

- The scene you have open: moving, rotating, scaling, colors, text, textures,
  adding and deleting nodes.
- Project files: scripts, scenes, images, sounds, fonts. Not shared: `.godot/`,
  `addons/`, `project.godot`.
- Scripts live: type in the same script at the same time. Friends' cursors show
  in their color. Ctrl+Z only undoes your own edits.

When you join a room, the room's files replace yours. Yours are backed up to
`user://gamesync_backup` first.

## Network and privacy

GameSync only connects when you press Create room or Join, or when you open a
project made from an invite link (those join their room automatically). While you're in a room
it sends your scene changes, project files, script edits, cursor position, the
name you typed and the room code to the GameSync server, which passes them to
the other people in the same room. Nothing is sent when you're not in a room.
There are no analytics or tracking.

The default server is `gamesync-yggk.onrender.com`. Rooms live in memory and are
deleted when everyone leaves. The hosting provider may keep standard
connection logs. To use your own server instead, run the server from
the GitHub repo and turn on "Use my own server" in the GameSync tab.

Only share room codes with people you trust: people in your room can change
your project's files.

Source and server: https://github.com/nivash-devs/gamesync
