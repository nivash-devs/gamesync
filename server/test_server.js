// Tests the relay server with fake clients.
const WebSocket = require("ws");
const { server, rooms } = require("./server");

let passed = 0, failed = 0;
const check = (c, label) => { c ? passed++ : failed++; console.log((c ? "ok   " : "FAIL ") + label); };

function client(name, room = "r1") {
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
  return new Promise((res) => ws.on("open", () => { c.send({ t: "join", room, name }); res(c); }));
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

  // Leaving.
  b.ws.close();
  let p2;
  for (let i = 0; i < 5; i++) { p2 = await a.next("presence"); if (p2 && p2.peers.length === 2) break; }
  check(p2 && !p2.peers.some((p) => p.name === "Arjun"), "B leaves, others see it");
  a.ws.close(); c.ws.close();
  await new Promise((r) => setTimeout(r, 100));
  check(!rooms.has("r1"), "empty room is cleaned up");

  d.ws.close();
  console.log(`passed ${passed} | failed ${failed}`);
  server.close();
  process.exit(failed ? 1 : 0);
})();
