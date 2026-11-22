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
:root { color-scheme: dark; }
* { box-sizing: border-box; }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #121417; color: #e8e8e8;
  font: 16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; padding: 24px 16px; }
main { width: 100%; max-width: 440px; }
h1 { font-size: 28px; margin: 0 0 6px; }
.code { font: 700 40px/1.1 ui-monospace, "Cascadia Mono", Consolas, monospace; letter-spacing: 4px; color: #6fb6ff; margin: 8px 0 20px; }
.btn { display: block; text-align: center; background: #478cbf; color: #fff; text-decoration: none; font-weight: 600;
  padding: 14px 18px; border-radius: 10px; margin: 0 0 22px; }
.btn:hover { background: #5a9fd1; }
ol { padding-left: 20px; margin: 0 0 18px; }
li { margin-bottom: 8px; }
.muted { color: #9aa0a6; font-size: 14px; }
a { color: #6fb6ff; }
`;

function page(title, body) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title><style>${STYLE}</style></head><body><main>${body}</main></body></html>`;
}

function joinPage(code) {
  return page(`Join ${code} · GameSync`, `
<h1>Join your friend's game</h1>
<div class="code">${code}</div>
<a class="btn" href="/join/${code}/GameSync-${code}.zip" download>Download project</a>
<ol>
  <li>Open Godot and click <b>Import</b>.</li>
  <li>Pick the file you just downloaded, then <b>Import &amp; Edit</b>.</li>
  <li>That's it. You join automatically and their project downloads.</li>
</ol>
<p class="muted">Needs Godot 4.2 or newer. No Godot? <a href="https://godotengine.org/download">Get it free</a>.</p>`);
}

function homePage() {
  return page("GameSync", `
<h1>GameSync</h1>
<p>Build Godot games with friends, live. Move a node, they see it. Type in a script, they see that too.</p>
<a class="btn" href="/plugin/GameSync-plugin.zip" download>Download the plugin</a>
<p class="muted">Got an invite link? Just open it.</p>`);
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
