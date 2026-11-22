// Relay server for live scene sync.
// Friends join a room with a code. The server keeps the latest copy of each
// shared scene so late joiners get the current state, and forwards every
// change to the other people in the same scene.

const http = require("http");
const { WebSocketServer } = require("ws");
const crypto = require("crypto");
const OT = require("./ot");
const { handleWeb } = require("./web");

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
    r = { peers: new Map(), scenes: new Map(), files: new Map(), bytes: 0, docs: new Map() };
    rooms.set(code, r);
  }
  return r;
}

const isStr = (v, max = 512) => typeof v === "string" && v.length > 0 && v.length <= max;
const isObj = (v) => v && typeof v === "object" && !Array.isArray(v);
// Project-relative file paths only: "player.gd", "art/hero.png".
const TEXT_EXTS = ["gd", "gdshader", "txt", "md", "json", "cfg", "csv", "tres", "tscn"];
const isTextDoc = (p) => TEXT_EXTS.includes(p.split(".").pop().toLowerCase());
const MAX_DOC = 1024 * 1024;
const MAX_LOG = 2000;
const md5 = (str) => crypto.createHash("md5").update(str, "utf8").digest("hex");
const docText = (doc) => doc.chars.join("");
const isRel = (p) => isStr(p, 300) && !p.includes("..") && !p.includes(":") && !p.includes("\\") && !p.startsWith("/");

function send(ws, msg) {
  if (ws.readyState === 1) ws.send(JSON.stringify(msg));
}

function presence(room) {
  const peers = [...room.peers.values()].map((p) => ({
    id: p.id, name: p.name, color: p.color, scene: p.scene, selected: p.selected,
    docs: [...p.docs],
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

function docSubscribers(room, path) {
  return [...room.peers.values()].filter((p) => p.docs.has(path));
}

// Nobody has this script open any more: its text becomes a normal file again.
function retireDoc(room, path) {
  const doc = room.docs.get(path);
  if (!doc) return;
  room.docs.delete(path);
  const text = docText(doc);
  const data = Buffer.from(text, "utf8").toString("base64");
  const old = room.files.get(path);
  room.bytes += data.length - (old ? old.data.length : 0);
  room.files.set(path, { md5: md5(text), data });
}

function leaveDoc(room, peer, path) {
  if (!peer.docs.delete(path)) return;
  for (const p of docSubscribers(room, path)) send(p.ws, { t: "dcur", path, id: peer.id, off: -1 });
  if (docSubscribers(room, path).length === 0) retireDoc(room, path);
}

function handle(peer, msg) {
  if (!isObj(msg) || typeof msg.t !== "string") return;

  if (msg.t === "join") {
    if (peer.room || !isStr(msg.room, 64) || !isStr(msg.name, 40)) return;
    // "Create room" picks a random code; if it's somehow taken, the client picks another.
    if (msg.create === true && rooms.has(msg.room) && rooms.get(msg.room).peers.size > 0) {
      send(peer.ws, { t: "error", code: "room_taken" });
      return;
    }
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
    case "ping":
      // Keeps free hosting awake while someone is connected.
      send(peer.ws, { t: "pong" });
      break;
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
      if (!isStr(msg.scene) || !isObj(msg.nodes)) return;
      // Two people uploaded at the same moment: the second one gets the room's copy.
      if (room.scenes.has(msg.scene)) {
        send(peer.ws, { t: "state", scene: msg.scene, nodes: Object.fromEntries(room.scenes.get(msg.scene)) });
        return;
      }
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
      for (const [p, d] of room.docs) files[p] = md5(docText(d));
      send(peer.ws, { t: "fstate", files });
      break;
    }
    case "fget": {
      if (!isRel(msg.path)) return;
      const doc = room.docs.get(msg.path);
      const f = room.files.get(msg.path);
      if (doc) {
        const text = docText(doc);
        send(peer.ws, { t: "file", path: msg.path, md5: md5(text), data: Buffer.from(text, "utf8").toString("base64") });
      } else if (f) send(peer.ws, { t: "file", path: msg.path, md5: f.md5, data: f.data });
      else send(peer.ws, { t: "file", path: msg.path, md5: "", data: "", missing: true });
      break;
    }
    case "fput": {
      if (!isRel(msg.path) || typeof msg.data !== "string" || msg.data.length > MAX_FILE_B64 || !isStr(msg.md5, 64)) return;
      // Someone is live-editing this script: their edits win over a saved file.
      if (room.docs.has(msg.path)) {
        if (docSubscribers(room, msg.path).length > 0) return;
        room.docs.delete(msg.path);
      }
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
    case "dopen": {
      if (!isRel(msg.path) || !isTextDoc(msg.path) || typeof msg.text !== "string" || msg.text.length > MAX_DOC) return;
      let doc = room.docs.get(msg.path);
      if (!doc) {
        // Start from the room's saved file if there is one, else from this person's text.
        const f = room.files.get(msg.path);
        const start = f ? Buffer.from(f.data, "base64").toString("utf8") : msg.text;
        doc = { chars: Array.from(start), rev: 0, base: 0, log: [] };
        room.docs.set(msg.path, doc);
      }
      peer.docs.add(msg.path);
      send(peer.ws, { t: "dstate", path: msg.path, text: docText(doc), rev: doc.rev });
      presence(room);
      break;
    }
    case "dclose": {
      if (!isStr(msg.path)) return;
      leaveDoc(room, peer, msg.path);
      presence(room);
      break;
    }
    case "dop": {
      const doc = isStr(msg.path) && room.docs.get(msg.path);
      if (!doc || !peer.docs.has(msg.path)) return;
      const resync = () => { send(peer.ws, { t: "dstate", path: msg.path, text: docText(doc), rev: doc.rev }); };
      if (!Number.isInteger(msg.rev) || msg.rev < doc.base || msg.rev > doc.rev || !OT.validShape(msg.op)) return resync();
      // Shift this edit past everything the sender hadn't seen yet.
      let op = msg.op;
      for (let k = msg.rev - doc.base; k < doc.log.length; k++) op = OT.transform(op, doc.log[k], false)[0];
      const next = doc.chars.slice();
      if (!OT.apply(next, op) || next.length > MAX_DOC) return resync();
      doc.chars = next;
      doc.log.push(op);
      doc.rev++;
      if (doc.log.length > MAX_LOG) { doc.log.shift(); doc.base++; }
      send(peer.ws, { t: "dack", path: msg.path, rev: doc.rev });
      for (const p of docSubscribers(room, msg.path)) {
        if (p.id !== peer.id) send(p.ws, { t: "dop", path: msg.path, rev: doc.rev, op, from: peer.id });
      }
      break;
    }
    case "dcur": {
      if (!isStr(msg.path) || !peer.docs.has(msg.path) || !Number.isInteger(msg.off)) return;
      for (const p of docSubscribers(room, msg.path)) {
        if (p.id !== peer.id) send(p.ws, { t: "dcur", path: msg.path, off: msg.off, id: peer.id, name: peer.name, color: peer.color });
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
  try {
    if (handleWeb(req, res, { rooms: rooms.size })) return;
  } catch (e) {
    console.error("web error", e.message);
    res.writeHead(500);
    return res.end("Something went wrong.");
  }
  res.writeHead(404, { "content-type": "text/plain" });
  res.end("Not found");
});

const wss = new WebSocketServer({ server, maxPayload: MAX_MSG });

wss.on("connection", (ws) => {
  const peer = { id: nextId++, ws, room: null, roomCode: "", name: "", color: "", scene: "", selected: [], docs: new Set() };
  ws.on("message", (data) => {
    let msg;
    try { msg = JSON.parse(data.toString()); } catch { return; }
    try { handle(peer, msg); } catch (e) { console.error("bad message from", peer.name, e.message); }
  });
  ws.on("close", () => {
    const room = peer.room;
    if (!room) return;
    for (const path of [...peer.docs]) leaveDoc(room, peer, path);
    room.peers.delete(peer.id);
    if (room.peers.size === 0) rooms.delete(peer.roomCode);
    else presence(room);
  });
});

if (require.main === module) {
  server.listen(PORT, () => console.log(`gamesync server on :${PORT}`));
}

module.exports = { server, rooms };
