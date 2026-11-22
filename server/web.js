// Web pages: the join page friends open from an invite link, and the
// ready-to-open Godot project it hands out (GameSync already turned on,
// room code already filled in).

const fs = require("fs");
const path = require("path");
const { makeZip } = require("./zip");

// The plugin's files. In the repo they live in godot/addons/gamesync;
// server/plugin is a copy so the server also works when deployed on its own.
function pluginDir() {
  const inRepo = path.join(__dirname, "..", "godot", "addons", "gamesync");
  return fs.existsSync(path.join(inRepo, "plugin.cfg")) ? inRepo : path.join(__dirname, "plugin");
}

function pluginFiles() {
  const dir = pluginDir();
  return fs.readdirSync(dir)
    .filter((f) => f.endsWith(".gd") || f === "plugin.cfg" || f === "LICENSE" || f === "README.md")
    .sort()
    .map((f) => ({ name: "addons/gamesync/" + f, data: fs.readFileSync(path.join(dir, f)) }));
}

const CODE_RE = /^[A-Z0-9]{4,12}$/;

function projectGodot(code) {
  return [
    "config_version=5",
    "",
    "[application]",
    "",
    `config/name="GameSync room ${code}"`,
    "",
    "[editor_plugins]",
    "",
    'enabled=PackedStringArray("res://addons/gamesync/plugin.cfg")',
    "",
    "[gamesync]",
    "",
    `room="${code}"`,
    "",
  ].join("\n");
}

function projectZip(code) {
  return makeZip([{ name: "project.godot", data: Buffer.from(projectGodot(code), "utf8") }, ...pluginFiles()]);
}

function pluginZip() {
  return makeZip(pluginFiles());
}

const STYLE = `
:root { color-scheme: dark; --bg:#07080b; --panel:#0e1117; --line:#1d2330; --fg:#eef1f6; --muted:#8a93a3;
  --blue:#ffffff; --blue2:#ffffff; --orange:#9a9a9a; }
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.6 Inter, system-ui, -apple-system, "Segoe UI", sans-serif;
  -webkit-font-smoothing: antialiased; overflow-x: hidden; }
body::before { content: ""; position: fixed; inset: 0; z-index: -1; pointer-events: none;
  background:
    radial-gradient(600px 400px at 15% 0%, rgba(255,255,255,.06), transparent 70%),
    radial-gradient(500px 380px at 90% 10%, rgba(255,255,255,.035), transparent 70%),
    linear-gradient(rgba(255,255,255,.035) 1px, transparent 1px) 0 0 / 40px 40px,
    linear-gradient(90deg, rgba(255,255,255,.035) 1px, transparent 1px) 0 0 / 40px 40px;
  -webkit-mask-image: linear-gradient(#000 0%, #000 50%, transparent 100%); mask-image: linear-gradient(#000 0%, #000 50%, transparent 100%); }
a { color: var(--blue2); text-decoration: none; }
a:hover { text-decoration: underline; }
.wrap { max-width: 1040px; margin: 0 auto; padding: 0 20px; }
nav { display: flex; align-items: center; justify-content: space-between; height: 68px; }
.logo { font-weight: 700; font-size: 20px; letter-spacing: -.5px; color: var(--fg); display: flex; align-items: center; gap: 9px; }
.logo:hover { text-decoration: none; }
.dot { width: 12px; height: 12px; border-radius: 3px; background: #fff; }
nav .links a { color: var(--muted); margin-left: 22px; font-size: 15px; }
nav .links a:hover { color: var(--fg); text-decoration: none; }
.hero { display: grid; grid-template-columns: minmax(0,1.15fr) minmax(0,1fr); gap: 48px; align-items: center; padding: 56px 20px 72px; }
h1 { font-size: clamp(34px, 5vw, 48px); line-height: 1.05; letter-spacing: -2px; margin: 0 0 18px; font-weight: 800; }
h1 .b { color: #fff; } h1 .o { color: #9a9a9a; }
.lead { color: var(--muted); font-size: 18px; margin: 0 0 30px; max-width: 30em; }
.btns { display: flex; gap: 12px; flex-wrap: wrap; }
.btn { display: inline-flex; align-items: center; gap: 8px; padding: 13px 22px; border-radius: 10px; font-weight: 600; font-size: 15px;
  background: var(--blue); color: #000; box-shadow: 0 6px 24px rgba(255,255,255,.10); transition: transform .15s, background .15s; }
.btn:hover { background: #e4e4e4; text-decoration: none; transform: translateY(-1px); }
.btn.ghost { background: transparent; color: var(--fg); border: 1px solid var(--line); box-shadow: none; }
.btn.ghost:hover { border-color: #39414f; }
.meta { margin-top: 18px; color: var(--muted); font-size: 13px; }
.editor { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; overflow: hidden;
  box-shadow: 0 30px 80px rgba(0,0,0,.55); }
.bar { display: flex; align-items: center; gap: 7px; padding: 11px 14px; border-bottom: 1px solid var(--line); font-size: 12px; color: var(--muted); }
.bar i { width: 10px; height: 10px; border-radius: 50%; background: #262c38; }
.bar .tab { margin-left: 10px; } .bar .room { margin-left: auto; font-family: "JetBrains Mono", Consolas, monospace; color: var(--blue2); }
.editor svg { display: block; width: 100%; height: auto; }
.mv { animation: mv 6s ease-in-out infinite; }
@keyframes mv { 0%,100% { transform: translate(0,0); } 45%,55% { transform: translate(90px,-38px); } }
.blink { animation: bl 1.1s steps(1) infinite; } @keyframes bl { 50% { opacity: 0; } }
@media (prefers-reduced-motion: reduce) { .mv, .blink { animation: none; } }
section { padding: 64px 0; border-top: 1px solid var(--line); }
h2 { font-size: 30px; letter-spacing: -1px; margin: 0 0 8px; }
.kicker { color: var(--muted); margin: 0 0 32px; }
.cols { display: grid; grid-template-columns: minmax(0,1fr) minmax(0,1fr); gap: 20px; }
.card { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; padding: 26px; }
.card h3 { margin: 0 0 18px; font-size: 18px; display: flex; align-items: center; gap: 10px; }
.tag { font-size: 11px; font-weight: 700; letter-spacing: .5px; text-transform: uppercase; padding: 3px 8px; border-radius: 20px; }
.tag.b { background: #fff; color: #000; } .tag.o { background: rgba(255,255,255,.1); color: #fff; }
.steps { list-style: none; padding: 0; margin: 0; counter-reset: s; }
.steps li { counter-increment: s; position: relative; padding: 2px 0 16px 42px; color: #c9cfda; }
.steps li::before { content: counter(s); position: absolute; left: 0; top: 0; width: 28px; height: 28px; border-radius: 8px;
  display: grid; place-items: center; font-size: 13px; font-weight: 700; background: #161b24; border: 1px solid var(--line); color: var(--fg); }
.steps li:last-child { padding-bottom: 0; }
.steps b, .feat b, .faq b { color: var(--fg); font-weight: 600; }
.or { display: flex; align-items: center; gap: 12px; color: var(--muted); font-size: 13px; margin: 20px 0 16px; }
.or::before, .or::after { content: ""; flex: 1; height: 1px; background: var(--line); }
kbd, code { overflow-wrap: anywhere; font-family: "JetBrains Mono", Consolas, monospace; font-size: 13px; background: #161b24; border: 1px solid var(--line);
  border-radius: 5px; padding: 1px 6px; color: var(--fg); }
.feats { display: grid; grid-template-columns: repeat(3, minmax(0,1fr)); gap: 16px; }
.feat { background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 20px; color: var(--muted); font-size: 15px; }
.feat svg { display: block; margin-bottom: 12px; }
.faq details { background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 16px 20px; margin-bottom: 10px; }
.faq summary { cursor: pointer; font-weight: 600; list-style: none; display: flex; justify-content: space-between; gap: 12px; }
.faq summary::after { content: "+"; color: var(--muted); font-size: 20px; line-height: 1; }
.faq details[open] summary::after { content: "\\2212"; }
.faq summary::-webkit-details-marker { display: none; }
.faq p { color: var(--muted); margin: 10px 0 0; }
footer { border-top: 1px solid var(--line); padding-top: 28px; padding-bottom: 40px; color: var(--muted); font-size: 14px; display: flex; justify-content: space-between; flex-wrap: wrap; gap: 10px; }
.join { min-height: calc(100vh - 68px); display: grid; place-items: center; padding-top: 20px; padding-bottom: 60px; }
.join .card { width: 100%; max-width: 460px; padding: 34px; text-align: center; }
.join h1 { font-size: 30px; letter-spacing: -1px; margin-bottom: 6px; }
.code { font: 700 46px/1 "JetBrains Mono", Consolas, monospace; letter-spacing: 6px; color: var(--blue2); margin: 14px 0 26px; }
.join .btn { width: 100%; justify-content: center; }
.join .steps { text-align: left; margin-top: 28px; }
@media (max-width: 820px) {
  .hero, .cols { grid-template-columns: minmax(0,1fr); } .hero { padding-top: 28px; padding-bottom: 56px; gap: 36px; }
  .feats { grid-template-columns: repeat(2, minmax(0,1fr)); }
}
@media (max-width: 520px) { .feats { grid-template-columns: minmax(0,1fr); } nav .links a.hide { display: none; } .code { font-size: 36px; letter-spacing: 4px; } .join .card { padding: 26px 20px; } }
`;

const FONTS = `<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&family=JetBrains+Mono:wght@500;700&display=swap" rel="stylesheet">`;

const NAV = `<nav class="wrap"><a class="logo" href="/"><span class="dot"></span>gamesync</a>
<div class="links"><a href="/assets">Assets</a><a class="hide" href="/#how">How it works</a><a href="https://github.com/nivash-devs/gamesync">GitHub</a></div></nav>`;

function page(title, body) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>${FONTS}<style>${STYLE}</style></head><body>${NAV}${body}</body></html>`;
}

function joinPage(code) {
  return page(`Join ${code} · GameSync`, `
<main class="wrap join"><div class="card">
<h1>Join your friend's game</h1>
<p class="kicker" style="margin:0">Room code</p>
<div class="code">${code}</div>
<a class="btn" href="/join/${code}/GameSync-${code}.zip" download>Download project</a>
<ol class="steps">
  <li>Open Godot and click <b>Import</b>.</li>
  <li>Pick the zip, then <b>Import &amp; Edit</b>.</li>
  <li>You join by yourself and their project downloads.</li>
</ol>
<p class="meta">Godot 4.2 or newer. No Godot? <a href="https://godotengine.org/download">Get it free</a></p>
</div></main>`);
}

const EDITOR = `<div class="editor" aria-hidden="true">
<div class="bar"><i></i><i></i><i></i><span class="tab">level1.tscn</span><span class="room">ROOM K3X9P2</span></div>
<svg viewBox="0 0 520 330">
  <defs><pattern id="g" width="26" height="26" patternUnits="userSpaceOnUse"><path d="M26 0H0V26" fill="none" stroke="#1a202b"/></pattern></defs>
  <rect width="520" height="330" fill="url(#g)"/>
  <rect x="0" y="250" width="520" height="80" fill="#121722"/>
  <rect x="0" y="250" width="520" height="3" fill="#2a3242"/>
  <rect x="290" y="226" width="140" height="14" rx="3" fill="#2a3242"/>
  <rect x="72" y="200" width="34" height="50" rx="6" fill="#ffffff"/>
  <rect x="66" y="194" width="46" height="62" fill="none" stroke="#ffffff" stroke-width="1.5" stroke-dasharray="5 4"/>
  <path d="M120 222 l0 18 l5-5 l4 9 l3-1 l-4-9 l7 0z" fill="#fff" stroke="#ffffff" stroke-width="1.5"/>
  <rect x="136" y="244" width="34" height="18" rx="4" fill="#ffffff"/><text x="153" y="257" text-anchor="middle" font-size="11" font-weight="700" fill="#000" font-family="Inter,sans-serif">you</text>
  <g class="mv">
    <rect x="300" y="150" width="30" height="30" rx="5" fill="#9a9a9a"/>
    <rect x="294" y="144" width="42" height="42" fill="none" stroke="#9a9a9a" stroke-width="1.5" stroke-dasharray="5 4"/>
    <path d="M342 168 l0 18 l5-5 l4 9 l3-1 l-4-9 l7 0z" fill="#fff" stroke="#9a9a9a" stroke-width="1.5"/>
    <rect x="358" y="190" width="44" height="18" rx="4" fill="#9a9a9a"/><text x="380" y="203" text-anchor="middle" font-size="11" font-weight="700" fill="#111" font-family="Inter,sans-serif">friend</text>
  </g>
  <g font-family="JetBrains Mono,Consolas,monospace" font-size="12">
    <rect x="18" y="18" width="200" height="84" rx="8" fill="#0b0e14" stroke="#1d2330"/>
    <text x="32" y="42" fill="#c678dd">func</text><text x="68" y="42" fill="#ffffff">_ready</text><text x="116" y="42" fill="#8a93a3">():</text>
    <text x="44" y="62" fill="#8a93a3">speed = </text><text x="108" y="62" fill="#9a9a9a">300</text>
    <rect x="132" y="51" width="2" height="15" fill="#9a9a9a" class="blink"/>
    <text x="44" y="82" fill="#8a93a3">jump()</text>
  </g>
</svg></div>`;

const ic = (d, c) => `<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;

function homePage() {
  return page("GameSync", `
<main>
<div class="wrap hero">
  <div>
    <h1>Build Godot games with <span class="b">friends</span>, <span class="o">live</span>.</h1>
    <p class="lead">Move a node, they see it. Type in a script, they see that too. A plugin for the Godot editor.</p>
    <div class="btns">
      <a class="btn" href="/plugin/GameSync-plugin.zip" download>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v13M6 11l6 6 6-6M4 21h16"/></svg>
        Download plugin</a>
      <a class="btn ghost" href="#how">How it works</a>
    </div>
    <p class="meta">Free · Open source · Godot 4.2+</p>
  </div>
  ${EDITOR}
</div>

<section id="how"><div class="wrap">
  <h2>Get going</h2>
  <p class="kicker">One person starts a room. Everyone else joins.</p>
  <div class="cols">
    <div class="card">
      <h3><span class="tag b">Host</span> Start a room</h3>
      <ol class="steps">
        <li><a href="/plugin/GameSync-plugin.zip" download>Download the plugin</a> and unzip it.</li>
        <li>Put the <b>addons</b> folder in your project. Already have one? Put <b>gamesync</b> inside it.</li>
        <li><b>Project › Project Settings › Plugins</b>, turn on GameSync.</li>
        <li>In the GameSync tab on the right, type your name and click <b>Create room</b>.</li>
        <li>Click <b>Copy invite link</b> and send it.</li>
      </ol>
    </div>
    <div class="card">
      <h3><span class="tag o">Friend</span> Join a room</h3>
      <ol class="steps">
        <li>Open the invite link, click <b>Download project</b>.</li>
        <li>In Godot, click <b>Import</b> and pick the zip.</li>
        <li>Click <b>Import &amp; Edit</b>. You're in.</li>
      </ol>
      <div class="or">or with a code</div>
      <ol class="steps">
        <li>Install the plugin (host steps 1 to 3).</li>
        <li>Type your name and the code, click <b>Join</b>.</li>
      </ol>
    </div>
  </div>
</div></section>

<section><div class="wrap">
  <h2>In a room</h2>
  <p class="kicker">Nothing to set up.</p>
  <div class="feats">
    <div class="feat">${ic('<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18M3 9h18"/>', "#ffffff")}<b>Scenes sync live.</b> Moves, adds and deletes show up for everyone.</div>
    <div class="feat">${ic('<path d="M16 18l6-6-6-6M8 6l-6 6 6 6"/>', "#9a9a9a")}<b>Scripts too.</b> Type together and see each other's cursors.</div>
    <div class="feat">${ic('<path d="M4 4h10l6 6v10H4z"/><path d="M14 4v6h6"/>', "#ffffff")}<b>Files follow.</b> Images, sounds and new scripts land in everyone's project.</div>
    <div class="feat">${ic('<path d="M3 7v6h6"/><path d="M21 17a9 9 0 0 0-15-6.7L3 13"/>', "#9a9a9a")}<b><kbd>Ctrl+Z</kbd> is yours.</b> It only undoes your own edits.</div>
    <div class="feat">${ic('<path d="M12 3l8 4v5c0 5-3.5 8-8 9-4.5-1-8-4-8-9V7z"/>', "#ffffff")}<b>Backed up.</b> Your old files go to <code>user://gamesync_backup</code> on join.</div>
    <div class="feat">${ic('<path d="M21 12a9 9 0 1 1-3-6.7L21 8"/><path d="M21 3v5h-5"/>', "#9a9a9a")}<b>Reconnects.</b> Drop off and you're put back in the same room.</div>
  </div>
</div></section>

<section class="faq"><div class="wrap">
  <h2>Questions</h2>
  <p class="kicker"></p>
  <details><summary>It says "Waking up the server"</summary><p>The free server sleeps when nobody's using it. The first connect can take about a minute.</p></details>
  <details><summary>What isn't shared?</summary><p><code>.godot</code>, <code>addons</code>, <code>project.godot</code> and files over 8 MB.</p></details>
  <details><summary>A friend can't see my scene</summary><p>Save it first so it has a file name.</p></details>
  <details><summary>The room is gone</summary><p>Rooms close when everyone leaves. Your project stays on your computer. Create a new room.</p></details>
  <details><summary>Do we need the same Godot version?</summary><p>It's safest. GameSync runs on 4.2 to 4.7.</p></details>
</div></section>
</main>
<footer class="wrap"><span>gamesync · MIT</span><a href="https://github.com/nivash-devs/gamesync">GitHub</a></footer>`);
}


const ASSETS = require("./assets-data");
const esc = (t) => String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

const ASSETS_STYLE = `
[hidden] { display: none !important; }
.ahero { padding: 40px 0 30px; }
.ahero h1 { margin-bottom: 14px; }
.jump { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 22px; }
.jump a { color: var(--fg); border: 1px solid var(--line); border-radius: 20px; padding: 6px 14px; font-size: 14px; }
.jump a:hover { border-color: #555; text-decoration: none; }
.agrid { display: grid; grid-template-columns: repeat(3, minmax(0,1fr)); gap: 14px; }
.acard { display: block; background: var(--panel); border: 1px solid var(--line); border-radius: 14px; padding: 18px; color: var(--fg); }
.acard:hover { border-color: #4a4a4a; text-decoration: none; }
.atop { display: flex; justify-content: space-between; align-items: flex-start; gap: 10px; }
.atop b { font-size: 16px; }
.lic { flex: none; font-size: 11px; font-weight: 700; letter-spacing: .3px; padding: 3px 8px; border-radius: 20px; border: 1px solid #444; color: #cfcfcf; white-space: nowrap; }
.lic.cc0 { background: #fff; color: #000; border-color: #fff; }
.acard p { color: var(--muted); font-size: 14px; margin: 8px 0 0; }
.acard .anote { color: #b8b8b8; font-size: 13px; }
.sbar { display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 18px; }
.seg { display: inline-flex; border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }
.seg button { background: none; border: 0; color: var(--muted); font: 600 15px Inter, sans-serif; padding: 0 16px; cursor: pointer; }
.seg button.on { background: #fff; color: #000; }
#q { flex: 1; min-width: 200px; background: var(--panel); border: 1px solid var(--line); border-radius: 10px; color: var(--fg); font: 16px Inter, sans-serif; padding: 12px 14px; }
#q:focus { outline: none; border-color: #666; }
.row { display: flex; align-items: center; gap: 14px; background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 12px 14px; margin-bottom: 8px; }
.play { flex: none; width: 38px; height: 38px; border-radius: 50%; border: 0; background: #fff; color: #000; font-size: 14px; cursor: pointer; }
.rinfo { flex: 1; min-width: 0; }
.rinfo b { display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.rinfo span { color: var(--muted); font-size: 13px; }
.racts { display: flex; gap: 8px; flex: none; }
.racts a, .racts button { font: 600 13px Inter, sans-serif; color: var(--fg); background: none; border: 1px solid var(--line); border-radius: 8px; padding: 7px 10px; cursor: pointer; }
.racts a:hover, .racts button:hover { border-color: #666; text-decoration: none; }
#msg { color: var(--muted); margin: 6px 0 14px; }
.godot { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; padding: 20px 22px; margin-top: 22px; color: var(--muted); }
.godot b { color: var(--fg); }
@media (max-width: 820px) { .agrid { grid-template-columns: repeat(2, minmax(0,1fr)); } }
@media (max-width: 520px) { .agrid { grid-template-columns: minmax(0,1fr); } .racts a { display: none; } }
`;

const SEARCH_JS = `
(function () {
  var kind = "sounds", page = 1, q = "";
  var res = document.getElementById("res"), msg = document.getElementById("msg"), more = document.getElementById("more");
  var player = new Audio(), playing = null;
  document.querySelectorAll(".seg button").forEach(function (b) {
    b.onclick = function () {
      document.querySelectorAll(".seg button").forEach(function (x) { x.classList.remove("on"); });
      b.classList.add("on"); kind = b.dataset.k;
      document.getElementById("q").placeholder = kind === "music" ? "chiptune, calm, boss fight, adventure..." : "footsteps, laser, coin, rain, door...";
      if (q) search(true);
    };
  });
  document.getElementById("go").onclick = function () { search(true); };
  document.getElementById("q").onkeydown = function (e) { if (e.key === "Enter") search(true); };
  more.onclick = function () { page++; search(false); };
  function url() {
    var u = "https://api.openverse.org/v1/audio/?q=" + encodeURIComponent(q) + "&license=cc0,by&page_size=20&page=" + page;
    return u + (kind === "music" ? "&category=music" : "&source=freesound,wikimedia_audio");
  }
  function lic(r) { return r.license === "cc0" ? "CC0" : "CC BY " + (r.license_version || ""); }
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function search(fresh) {
    q = document.getElementById("q").value.trim();
    if (!q) return;
    if (fresh) { page = 1; res.innerHTML = ""; }
    msg.textContent = "Searching...";
    more.hidden = true;
    fetch(url()).then(function (r) {
      if (r.status === 429) throw new Error("Too many searches for a minute. Try again shortly.");
      if (!r.ok) throw new Error("Search is down right now. Try again later.");
      return r.json();
    }).then(function (j) {
      var list = (j.results || []).filter(function (r) { return (r.license === "cc0" || r.license === "by") && String(r.url || "").indexOf("https://") === 0; });
      msg.textContent = list.length || !fresh ? "" : "Nothing found. Try a simpler word.";
      list.forEach(function (r) {
        var row = el("div", "row");
        var play = el("button", "play", "▶");
        play.onclick = function () {
          if (playing === play) { player.pause(); play.textContent = "▶"; playing = null; return; }
          if (playing) playing.textContent = "▶";
          player.src = r.url; player.play(); play.textContent = "■"; playing = play;
        };
        var info = el("div", "rinfo");
        info.appendChild(el("b", null, r.title || "untitled"));
        var secs = r.duration ? (r.duration / 1000) : 0;
        var len = secs >= 60 ? Math.floor(secs / 60) + ":" + String(Math.round(secs % 60)).padStart(2, "0") : secs.toFixed(1) + "s";
        info.appendChild(el("span", null, (r.creator || "unknown") + " · " + len + " · " + lic(r)));
        var acts = el("div", "racts");
        var get = el("a", null, "File"); get.href = r.url; get.target = "_blank"; get.rel = "noopener";
        var src = el("a", null, "Source"); src.href = r.foreign_landing_url || r.url; src.target = "_blank"; src.rel = "noopener";
        var cred = el("button", null, r.license === "cc0" ? "No credit needed" : "Copy credit");
        if (r.license !== "cc0") cred.onclick = function () {
          navigator.clipboard.writeText(r.attribution || ((r.title || "") + " by " + (r.creator || "") + ", " + lic(r)));
          cred.textContent = "Copied";
        };
        acts.appendChild(get); acts.appendChild(src); acts.appendChild(cred);
        row.appendChild(play); row.appendChild(info); row.appendChild(acts);
        res.appendChild(row);
      });
      more.hidden = !(j.page_count > page);
    }).catch(function (e) { msg.textContent = e.message; });
  }
  player.onended = function () { if (playing) playing.textContent = "▶"; playing = null; };
})();
`;

function assetsPage() {
  const card = (it) => {
    const cc0 = it.license === "CC0";
    return '<a class="acard" href="' + esc(it.url) + '" target="_blank" rel="noopener"><div class="atop"><b>' + esc(it.name) + '</b><span class="lic' + (cc0 ? " cc0" : "") + '">' + esc(it.license) + '</span></div><p>' + esc(it.desc) + '</p>' + (it.note ? '<p class="anote">' + esc(it.note) + '</p>' : "") + '</a>';
  };
  const cats = ASSETS.categories.map((c) =>
    '<section id="' + c.id + '"><div class="wrap"><h2>' + esc(c.name) + '</h2><p class="kicker"></p><div class="agrid">' + c.items.map(card).join("") + '</div></div></section>').join("\n");
  return page("Free game assets · GameSync", '<style>' + ASSETS_STYLE + '</style>' +
'<main><div class="wrap ahero"><h1>Free stuff for<br>your game.</h1>' +
'<p class="lead">Sound effects, music, VFX, art, pixel art, tilesets and tools. Picked by hand, with the license spelled out.</p>' +
'<div class="jump"><a href="#search">Search sounds</a>' + ASSETS.categories.map((c) => '<a href="#' + c.id + '">' + esc(c.name) + '</a>').join("") + '</div></div>' +
'<section id="search"><div class="wrap"><h2>Search sounds and music</h2>' +
'<p class="kicker">From Freesound and Jamendo, only licenses you can use in a game. CC0 needs no credit. CC BY needs the credit line.</p>' +
'<div class="sbar"><div class="seg"><button data-k="sounds" class="on">Sounds</button><button data-k="music">Music</button></div>' +
'<input id="q" placeholder="footsteps, laser, coin, rain, door..." autocomplete="off"><button id="go" class="btn">Search</button></div>' +
'<div id="msg"></div><div id="res"></div><button id="more" class="btn ghost" hidden>More</button>' +
'<div class="godot"><b>In Godot:</b> the GameSync tab has an <b>Assets</b> button. Search, preview and add sounds straight into your project. Everyone in your room gets them too, and the credits file fills itself in.</div>' +
'</div></section>\n' + cats + '</main>' +
'<footer class="wrap"><span>Licenses checked ' + ASSETS.checked + '. Always check the source page before you ship.</span><a href="/">gamesync</a></footer>' +
'<script>' + SEARCH_JS + '</script>');
}

// Returns true if it handled the request.
function handleWeb(req, res, stats) {
  const url = new URL(req.url, "http://x");
  const p = url.pathname;
  const send = (code, type, body, extra = {}) => {
    res.writeHead(code, { "content-type": type, "cache-control": "no-store", ...extra });
    res.end(body);
  };
  if (p === "/health") return send(200, "application/json", JSON.stringify({ ok: true, rooms: stats.rooms })), true;
  if (p === "/assets" || p === "/assets/") return send(200, "text/html; charset=utf-8", assetsPage()), true;
  if (p === "/api/packs") return send(200, "application/json", JSON.stringify(ASSETS), { "cache-control": "public, max-age=3600", "access-control-allow-origin": "*" }), true;
  if (p === "/" ) return send(200, "text/html; charset=utf-8", homePage()), true;
  if (p === "/plugin/GameSync-plugin.zip") {
    return send(200, "application/zip", pluginZip(), { "content-disposition": 'attachment; filename="GameSync-plugin.zip"' }), true;
  }
  let m = p.match(/^\/join\/([A-Za-z0-9]{1,20})\/?$/);
  if (m) {
    const code = m[1].toUpperCase();
    if (!CODE_RE.test(code)) return send(404, "text/plain", "That room code doesn't look right."), true;
    if (code !== m[1]) return send(302, "text/plain", "", { location: `/join/${code}` }), true;
    return send(200, "text/html; charset=utf-8", joinPage(code)), true;
  }
  m = p.match(/^\/join\/([A-Za-z0-9]{1,20})\/GameSync-[A-Za-z0-9]{1,20}\.zip$/);
  if (m) {
    const code = m[1].toUpperCase();
    if (!CODE_RE.test(code)) return send(404, "text/plain", "That room code doesn't look right."), true;
    return send(200, "application/zip", projectZip(code), { "content-disposition": `attachment; filename="GameSync-${code}.zip"` }), true;
  }
  return false;
}

module.exports = { handleWeb, projectZip, pluginZip, projectGodot, pluginFiles };
