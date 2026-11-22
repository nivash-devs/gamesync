// Tests the relay server with fake clients.
const WebSocket = require("ws");
const { server, rooms } = require("./server");

let passed = 0, failed = 0;
const check = (c, label) => { c ? passed++ : failed++; console.log((c ? "ok   " : "FAIL ") + label); };

function client(name, room = "r1", extra = {}) {
  const ws = new WebSocket(`ws://127.0.0.1:${server.address().port}`);
  const inbox = [];
  ws.on("message", (d) => inbox.push(JSON.parse(d.toString())));
  const c = {
    ws, inbox,
    send: (m) => ws.send(JSON.stringify(m)),
    raw: (s) => ws.send(s),
    async next(t, ms = 1000) {
      const start = Date.now();
      while (Date.now() - start < ms) {
        const i = inbox.findIndex((m) => m.t === t);
        if (i >= 0) return inbox.splice(i, 1)[0];
        await new Promise((r) => setTimeout(r, 10));
      }
      return null;
    },
    async none(t, ms = 200) { await new Promise((r) => setTimeout(r, ms)); return !inbox.some((m) => m.t === t); },
  };
  return new Promise((res) => ws.on("open", () => { c.send({ t: "join", room, name, ...extra }); res(c); }));
}

const S = "res://main.tscn";

(async () => {
  await new Promise((r) => server.listen(0, r));

  const a = await client("Nivash");
  const w = await a.next("welcome");
  check(w && w.id && w.color, "A gets an id and a color");

  a.send({ t: "hello", scene: S });
  const st = await a.next("state");
  check(st && st.nodes === null, "empty room: A is asked to seed");
  a.send({ t: "seed", scene: S, nodes: { ".": { cls: "Node2D", inst: "", props: {} }, Player: { cls: "Sprite2D", inst: "", props: { position: ["v2", 1, 2] } } } });

  const b = await client("Arjun");
  await b.next("welcome");
  b.send({ t: "hello", scene: S });
  const st2 = await b.next("state");
  check(st2 && st2.nodes && st2.nodes.Player.cls === "Sprite2D", "B gets A's scene");

  a.send({ t: "set", scene: S, path: "Player", props: { position: ["v2", 9, 9] } });
  const set = await b.next("set");
  check(set && set.props.position[1] === 9 && set.from === w.id, "A's change reaches B");
  check(await a.none("set"), "A doesn't get its own change back");

  a.send({ t: "add", scene: S, path: "Player/Gun", cls: "Node2D", props: {} });
  check(!!(await b.next("add")), "add reaches B");
  a.send({ t: "remove", scene: S, path: "Player" });
  check(!!(await b.next("remove")), "remove reaches B");
  const nodes = rooms.get("r1").scenes.get(S);
  check(!nodes.has("Player") && !nodes.has("Player/Gun"), "server drops Player and its child");
  a.send({ t: "remove", scene: S, path: "." });
  await new Promise((r) => setTimeout(r, 50));
  check(nodes.has("."), "nobody can delete the scene root");

  b.send({ t: "select", paths: ["Player", 5, ""] });
  let pres;
  for (let i = 0; i < 5; i++) { pres = await a.next("presence"); if (pres && pres.peers.some((p) => p.selected.length)) break; }
  check(pres && pres.peers.find((p) => p.name === "Arjun").selected.join() === "Player", "selection shows up, junk filtered");

  // Other scene and other room stay separate.
  const c = await client("Riya");
  await c.next("welcome");
  c.send({ t: "hello", scene: "res://other.tscn" });
  await c.next("state");
  a.send({ t: "set", scene: S, path: ".", props: { visible: ["b", false] } });
  check(await c.none("set"), "someone in another scene doesn't get the change");
  const d = await client("Stranger", "r2");
  await d.next("welcome");
  d.send({ t: "hello", scene: S });
  const st3 = await d.next("state");
  check(st3 && st3.nodes === null, "other room can't see room r1's scene");

  // Junk doesn't crash.
  a.raw("not json"); a.raw("[]"); a.send({ t: "set" }); a.send({ t: "join", room: "r9", name: "x" });
  a.send({ t: "set", scene: S, path: ".", props: { visible: ["b", true] } });
  check(!!(await b.next("set")), "server survives junk and keeps working");

  // Files.
  a.send({ t: "fhello", files: {} });
  const fs0 = await a.next("fstate");
  check(fs0 && Object.keys(fs0.files).length === 0, "new room has no files");
  a.send({ t: "fput", path: "art/hero.png", md5: "abc", data: "AAAA" });
  const got = await b.next("file");
  check(got && got.path === "art/hero.png" && got.data === "AAAA", "file upload reaches B");
  c.send({ t: "fget", path: "art/hero.png" });
  const got2 = await c.next("file");
  check(got2 && got2.md5 === "abc", "anyone in the room can download it (even in another scene)");
  b.send({ t: "fget", path: "nope.gd" });
  const miss = await b.next("file");
  check(miss && miss.missing === true, "asking for a missing file says so");
  for (const bad of ["../x.gd", "/etc/passwd", "C:/x.gd", "a\\b.gd"]) a.send({ t: "fput", path: bad, md5: "x", data: "AA" });
  await new Promise((r) => setTimeout(r, 50));
  check(rooms.get("r1").files.size === 1, "bad file paths are refused");
  a.send({ t: "fdel", path: "art/hero.png" });
  const del = await b.next("fdel");
  check(del && rooms.get("r1").files.size === 0 && rooms.get("r1").bytes === 0, "delete reaches B and frees space");

  // Gzip: new plugins send and get files packed, old plugins still get plain files.
  const zlib = require("zlib");
  const g = await client("Packer", "r1", { gz: true });
  await g.next("welcome");
  const text = "func _ready():\n\tprint('hi')\n".repeat(100);
  g.send({ t: "fput", path: "big.gd", md5: "m1", data: zlib.gzipSync(text).toString("base64"), z: 1 });
  const plainGot = await b.next("file");
  check(plainGot && !plainGot.z && Buffer.from(plainGot.data, "base64").toString() === text, "gzipped upload reaches an old plugin as a plain file");
  a.send({ t: "fput", path: "big2.gd", md5: "m2", data: Buffer.from(text).toString("base64") });
  const packed = await g.next("file");
  check(packed && packed.z === 1 && zlib.gunzipSync(Buffer.from(packed.data, "base64")).toString() === text && packed.data.length < text.length / 5, "plain upload reaches a new plugin gzipped and much smaller");
  g.send({ t: "fget", path: "big.gd" });
  const again = await g.next("file");
  check(again && again.z === 1 && zlib.gunzipSync(Buffer.from(again.data, "base64")).toString() === text, "downloading a file on join comes gzipped too");
  a.send({ t: "fput", path: "pic.png", md5: "m3", data: Buffer.alloc(2000, 7).toString("base64") });
  const pic = await g.next("file");
  check(pic && pic.path === "pic.png" && !pic.z, "images are sent as they are");
  g.send({ t: "fput", path: "bomb.gd", md5: "m4", data: zlib.gzipSync(Buffer.alloc(9 * 1024 * 1024)).toString("base64"), z: 1 });
  await new Promise((r) => setTimeout(r, 100));
  check(!rooms.get("r1").files.has("bomb.gd"), "a gzip that unpacks past 8 MB is refused");
  for (const p of ["big.gd", "big2.gd", "pic.png"]) a.send({ t: "fdel", path: p });
  g.ws.close();
  await new Promise((r) => setTimeout(r, 100));

  // Two seeds at once: the late one gets the room's copy back.
  b.send({ t: "seed", scene: S, nodes: { ".": { cls: "Node2D", inst: "", props: {} } } });
  const back = await b.next("state");
  check(back && back.nodes && back.nodes["."], "a late scene upload gets the room's copy back");

  // Create room: a taken code is refused, a free one works.
  const x = await client("Creator", "r1");   // r1 already has people, but plain join is fine
  check(!!(await x.next("welcome")), "joining an existing room by code works");
  const y = new WebSocket(`ws://127.0.0.1:${server.address().port}`);
  const yin = [];
  y.on("message", (dd) => yin.push(JSON.parse(dd.toString())));
  await new Promise((r) => y.on("open", r));
  y.send(JSON.stringify({ t: "join", room: "r1", name: "Y", create: true }));
  await new Promise((r) => setTimeout(r, 80));
  check(yin.some((m) => m.t === "error" && m.code === "room_taken"), "creating a room with a taken code is refused");
  y.send(JSON.stringify({ t: "join", room: "FRESH1", name: "Y", create: true }));
  await new Promise((r) => setTimeout(r, 80));
  check(yin.some((m) => m.t === "welcome"), "creating a room with a free code works");
  y.send(JSON.stringify({ t: "ping" }));
  await new Promise((r) => setTimeout(r, 50));
  check(yin.some((m) => m.t === "pong"), "ping gets a pong");
  y.close(); x.ws.close();

  // Leaving.
  b.ws.close();
  let p2;
  for (let i = 0; i < 20; i++) { p2 = await a.next("presence"); if (p2 && p2.peers.length === 2) break; }
  check(p2 && !p2.peers.some((p) => p.name === "Arjun"), "B leaves, others see it");
  a.ws.close(); c.ws.close();
  await new Promise((r) => setTimeout(r, 100));
  check(!rooms.has("r1"), "empty room is cleaned up");

  d.ws.close();

  // Web pages and the ready-made project.
  const http = require("http");
  const fs = require("fs");
  const path = require("path");
  const { execSync } = require("child_process");
  const get = (p) => new Promise((res) => http.get(`http://127.0.0.1:${server.address().port}${p}`, (r) => {
    const chunks = []; r.on("data", (c) => chunks.push(c)); r.on("end", () => res({ status: r.statusCode, headers: r.headers, body: Buffer.concat(chunks) }));
  }));
  const home = await get("/");
  check(home.status === 200 && home.body.toString().includes("GameSync"), "home page loads");
  const health = await get("/health");
  check(health.status === 200 && JSON.parse(health.body).ok === true, "health check answers");
  const lower = await get("/join/k3x9p2");
  check(lower.status === 302 && lower.headers.location === "/join/K3X9P2", "lowercase invite link redirects to the capital code");
  const join = await get("/join/K3X9P2");
  check(join.status === 200 && join.body.toString().includes("K3X9P2") && join.body.toString().includes("/join/K3X9P2/GameSync-K3X9P2.zip"), "join page shows the code and a download button");
  const bad = await get("/join/%3Cscript%3E");
  check(bad.status === 404, "junk room codes get a 404, not a page");
  const zip = await get("/join/K3X9P2/GameSync-K3X9P2.zip");
  const tmp = fs.mkdtempSync(path.join(require("os").tmpdir(), "gs-"));
  fs.writeFileSync(path.join(tmp, "p.zip"), zip.body);
  let listing = "";
  try { execSync(`unzip -q -t "${tmp}/p.zip"`); execSync(`unzip -q "${tmp}/p.zip" -d "${tmp}/out"`); listing = fs.readdirSync(path.join(tmp, "out")).join(","); } catch (e) { listing = "BROKEN " + e.message; }
  check(zip.status === 200 && listing.includes("project.godot") && listing.includes("addons"), "project zip is valid with project.godot at the top");
  let names = "";
  try { names = execSync(`unzip -Z1 "${tmp}/p.zip"`).toString(); } catch (e) {}
  check(names.split(/\r?\n/).includes("addons/") && names.split(/\r?\n/).includes("addons/gamesync/"), "project zip has folder entries (Godot Import needs them)");
  const pg = fs.existsSync(path.join(tmp, "out/project.godot")) ? fs.readFileSync(path.join(tmp, "out/project.godot"), "utf8") : "";
  check(pg.includes('room="K3X9P2"') && pg.includes("res://addons/gamesync/plugin.cfg"), "project has the room code and GameSync turned on");
  const repoDir = path.join(__dirname, "..", "godot", "addons", "gamesync");
  const same = fs.readdirSync(repoDir).filter((f) => f.endsWith(".gd") || f === "plugin.cfg").every((f) =>
    fs.existsSync(path.join(tmp, "out/addons/gamesync", f)) && fs.readFileSync(path.join(repoDir, f)).equals(fs.readFileSync(path.join(tmp, "out/addons/gamesync", f))));
  check(same, "zip has exactly the current plugin files");
  const copySame = fs.readdirSync(repoDir).filter((f) => f.endsWith(".gd") || f === "plugin.cfg").every((f) =>
    fs.existsSync(path.join(__dirname, "plugin", f)) && fs.readFileSync(path.join(repoDir, f)).equals(fs.readFileSync(path.join(__dirname, "plugin", f))));
  check(copySame, "server/plugin copy matches the real plugin (run: cp ../godot/addons/gamesync/* plugin/)");
  const plug = await get("/plugin/GameSync-plugin.zip");
  check(plug.status === 200 && plug.body.length > 1000, "plugin download works");

  console.log(`passed ${passed} | failed ${failed}`);
  server.close();
  process.exit(failed ? 1 : 0);
})();
