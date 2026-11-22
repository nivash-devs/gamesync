// Relay server for live scene sync.
// Friends join a room with a code. The server keeps the latest copy of each
// shared scene so late joiners get the current state, and forwards every
// change to the other people in the same scene.

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = Number(process.env.PORT) || 8787;
const MAX_MSG = 16 * 1024 * 1024;
const MAX_FILE_B64 = 12 * 1024 * 1024;   // ~8 MB file
const MAX_ROOM_BYTES = 300 * 1024 * 1024;
const COLORS = ["#ff5c5c", "#4da3ff", "#3ddc84", "#ffb020", "#c77dff", "#ff7ac6", "#2ee6d6", "#f5f56a"];

const rooms = new Map(); // code -> { peers: Map<id, peer>, scenes: Map<sceneKey, Map<path, node>> }
let nextId = 1;

function getRoom(code) {
  let r = rooms.get(code);
  if (!r) {
    r = { peers: new Map(), scenes: new Map(), files: new Map(), bytes: 0 };
    rooms.set(code, r);
  }
  return r;
}

const isStr = (v, max = 512) => typeof v === "string" && v.length > 0 && v.length <= max;
const isObj = (v) => v && typeof v === "object" && !Array.isArray(v);
// Project-relative file paths only: "player.gd", "art/hero.png".
const isRel = (p) => isStr(p, 300) && !p.includes("..") && !p.includes(":") && !p.includes("\\") && !p.startsWith("/");

function send(ws, msg) {
  if (ws.readyState === 1) ws.send(JSON.stringify(msg));
}

function presence(room) {
  const peers = [...room.peers.values()].map((p) => ({
    id: p.id, name: p.name, color: p.color, scene: p.scene, selected: p.selected,
  }));
  for (const p of room.peers.values()) send(p.ws, { t: "presence", peers });
}

function toOthers(room, from, scene, msg) {
  for (const p of room.peers.values()) {
    if (p.id !== from.id && p.scene === scene) send(p.ws, msg);
  }
}

function removeTree(nodes, path) {
  for (const k of [...nodes.keys()]) {
    if (k === path || k.startsWith(path + "/")) nodes.delete(k);
  }
}

function handle(peer, msg) {
  if (!isObj(msg) || typeof msg.t !== "string") return;

  if (msg.t === "join") {
    if (peer.room || !isStr(msg.room, 64) || !isStr(msg.name, 40)) return;
    peer.roomCode = msg.room;
    peer.room = getRoom(msg.room);
    peer.name = msg.name;
    peer.color = COLORS[peer.room.peers.size % COLORS.length];
    peer.room.peers.set(peer.id, peer);
    send(peer.ws, { t: "welcome", id: peer.id, color: peer.color });
    presence(peer.room);
    return;
  }

  const room = peer.room;
  if (!room) return;

  switch (msg.t) {
    case "hello": {
      // Peer opened a scene. Reply with what the room has for it (or null).
      if (!isStr(msg.scene)) return;
      peer.scene = msg.scene;
      peer.selected = [];
      const nodes = room.scenes.get(msg.scene);
      send(peer.ws, {
        t: "state", scene: msg.scene,
        nodes: nodes ? Object.fromEntries(nodes) : null,
      });
      presence(room);
      break;
    }
    case "seed": {
      // First person in a scene uploads it.
      if (!isStr(msg.scene) || !isObj(msg.nodes) || room.scenes.has(msg.scene)) return;
      room.scenes.set(msg.scene, new Map(Object.entries(msg.nodes)));
      break;
    }
    case "set": {
      if (!isStr(msg.scene) || !isStr(msg.path) || !isObj(msg.props)) return;
      const nodes = room.scenes.get(msg.scene);
      const node = nodes && nodes.get(msg.path);
      if (!node) return;
      Object.assign(node.props, msg.props);
      toOthers(room, peer, msg.scene, { t: "set", scene: msg.scene, path: msg.path, props: msg.props, from: peer.id });
      break;
    }
    case "add": {
      if (!isStr(msg.scene) || !isStr(msg.path) || !isStr(msg.cls, 128) || !isObj(msg.props)) return;
      const nodes = room.scenes.get(msg.scene);
      if (!nodes) return;
      const inst = typeof msg.inst === "string" ? msg.inst : "";
      nodes.set(msg.path, { cls: msg.cls, inst, props: msg.props });
      toOthers(room, peer, msg.scene, { t: "add", scene: msg.scene, path: msg.path, cls: msg.cls, inst, props: msg.props, from: peer.id });
      break;
    }
    case "remove": {
      if (!isStr(msg.scene) || !isStr(msg.path) || msg.path === ".") return;
      const nodes = room.scenes.get(msg.scene);
      if (!nodes) return;
      removeTree(nodes, msg.path);
      toOthers(room, peer, msg.scene, { t: "remove", scene: msg.scene, path: msg.path, from: peer.id });
      break;
    }
    case "fhello": {
      const files = {};
      for (const [p, f] of room.files) files[p] = f.md5;
      send(peer.ws, { t: "fstate", files });
      break;
    }
    case "fget": {
      if (!isRel(msg.path)) return;
      const f = room.files.get(msg.path);
      if (f) send(peer.ws, { t: "file", path: msg.path, md5: f.md5, data: f.data });
      else send(peer.ws, { t: "file", path: msg.path, md5: "", data: "", missing: true });
      break;
    }
    case "fput": {
      if (!isRel(msg.path) || typeof msg.data !== "string" || msg.data.length > MAX_FILE_B64 || !isStr(msg.md5, 64)) return;
      const old = room.files.get(msg.path);
      const delta = msg.data.length - (old ? old.data.length : 0);
      if (room.bytes + delta > MAX_ROOM_BYTES) return;
      room.bytes += delta;
      room.files.set(msg.path, { md5: msg.md5, data: msg.data });
      for (const p of room.peers.values()) {
        if (p.id !== peer.id) send(p.ws, { t: "file", path: msg.path, md5: msg.md5, data: msg.data, from: peer.id });
      }
      break;
    }
    case "fdel": {
      if (!isRel(msg.path)) return;
      const old = room.files.get(msg.path);
      if (!old) return;
      room.bytes -= old.data.length;
      room.files.delete(msg.path);
      for (const p of room.peers.values()) {
        if (p.id !== peer.id) send(p.ws, { t: "fdel", path: msg.path, from: peer.id });
      }
      break;
    }
    case "select": {
      if (!Array.isArray(msg.paths)) return;
      peer.selected = msg.paths.filter((p) => isStr(p)).slice(0, 50);
      presence(room);
      break;
    }
  }
}

const server = http.createServer((req, res) => {
  const out = [...rooms.entries()].map(([code, r]) => ({ room: code, people: r.peers.size }));
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({ ok: true, rooms: out.length }));
});

const wss = new WebSocketServer({ server, maxPayload: MAX_MSG });

wss.on("connection", (ws) => {
  const peer = { id: nextId++, ws, room: null, roomCode: "", name: "", color: "", scene: "", selected: [] };
  ws.on("message", (data) => {
    let msg;
    try { msg = JSON.parse(data.toString()); } catch { return; }
    handle(peer, msg);
  });
  ws.on("close", () => {
    const room = peer.room;
    if (!room) return;
    room.peers.delete(peer.id);
    if (room.peers.size === 0) rooms.delete(peer.roomCode);
    else presence(room);
  });
});

if (require.main === module) {
  server.listen(PORT, () => console.log(`gamesync server on :${PORT}`));
}

module.exports = { server, rooms };
