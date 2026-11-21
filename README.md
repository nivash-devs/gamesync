# GameSync (working name)

Edit the same Godot scene with friends, live.

## Try it on one PC

1. Start the server:
   ```
   cd server
   npm install
   node server.js
   ```
2. Copy `godot/addons/gamesync` into your Godot project's `addons` folder.
3. In Godot: Project > Project Settings > Plugins, turn on GameSync.
4. Open a saved scene. In the GameSync dock, type a room code and your name, then press Join.
5. Open the same project in a second Godot window, join the same room, and move something.

To play with a friend on another PC, the server has to be reachable by both of you
(same Wi-Fi with your PC's local IP, or hosted online). You both need the same project files.

## Tests

- Server: `cd server && node test_server.js`
- Sync logic in Godot: run `server.js` with `PORT=8799`, then
  `godot --headless --path tests/proj --script res://test_sync.gd`
