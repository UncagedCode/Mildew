// Mildew LAN integration test: launches the real headless Godot host (HTTP + WebSocket on
// real sockets) and drives genuine WebSocket phone clients through complete broadcasts.
//   node tests/integration/lan_integration.mjs            (needs `godot` on PATH)
// Writes tests/output/integration_results.json. Exit code 0 = all scenarios passed.
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import http from "node:http";

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const SCALE = Number(process.env.MILDEW_IT_SCALE || 8);
const results = [];
let basePort = 18080;

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function startHost(tag) {
  const port = basePort, wsPort = basePort + 1;
  basePort += 10;
  const args = ["--headless", "--path", ROOT, "--", "--mildew-host", "--port", String(port), "--ws-port", String(wsPort),
    "--timescale", String(SCALE), "--save-dir", `user://it_${tag}_${Date.now()}`, "--seed", "4242", "--force-games", "hole"];
  const proc = spawn("godot", args, { stdio: ["ignore", "pipe", "pipe"] });
  const events = [];
  let ready = null, buf = "";
  proc.stdout.on("data", (d) => {
    buf += d.toString();
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i); buf = buf.slice(i + 1);
      if (line.startsWith("MILDEW_HOST_READY ")) ready = JSON.parse(line.slice(18));
      else if (line.startsWith("EVT ")) { try { events.push(JSON.parse(line.slice(4))); } catch { /* partial */ } }
    }
  });
  proc.stderr.on("data", (d) => { const s = d.toString(); if (s.includes("SCRIPT ERROR")) events.push({ e: "__script_error", text: s }); });
  for (let t = 0; t < 200 && !ready; t++) await sleep(100);
  if (!ready) { proc.kill("SIGKILL"); throw new Error("host did not start"); }
  return { proc, ready, events, port, wsPort, stop: () => proc.kill("SIGKILL") };
}

function httpGet(port, p, method = "GET") {
  return new Promise((resolve) => {
    const req = http.request({ host: "127.0.0.1", port, path: p, method }, (res) => {
      let body = ""; res.on("data", (c) => (body += c)); res.on("end", () => resolve({ status: res.statusCode, body, type: res.headers["content-type"] }));
    });
    req.on("error", (e) => resolve({ status: 0, body: String(e) }));
    req.end();
  });
}

class Phone {
  constructor(host, name, opts = {}) {
    this.host = host; this.name = name; this.opts = opts;
    this.msgs = []; this.errors = []; this.screens = []; this.status = { paused: false };
    this.player = null; this.resume = ""; this.results = []; this.holeResults = []; this.lastHole = null; this.points = 0; this.answered = new Set();
  }
  connect() {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(`ws://127.0.0.1:${this.host.wsPort}/`);
      this.ws = ws;
      ws.onopen = () => {
        const hello = { t: "hello", v: 1 };
        if (this.opts.useRoomCode) hello.room = this.host.ready.room.toLowerCase(); else hello.key = this.host.ready.key;
        if (this.resume) hello.resume = this.resume;
        ws.send(JSON.stringify(hello));
        this.ping = setInterval(() => ws.readyState === 1 && ws.send(JSON.stringify({ t: "ping", id: 1, rtt: 3 })), 1500);
        resolve();
      };
      ws.onerror = (e) => reject(e);
      ws.onclose = () => clearInterval(this.ping);
      ws.onmessage = (ev) => this.onMsg(JSON.parse(ev.data));
    });
  }
  send(m) { if (this.ws.readyState === 1) this.ws.send(JSON.stringify(m)); }
  close() { clearInterval(this.ping); this.ws.close(); }
  onMsg(m) {
    this.msgs.push(m);
    if (m.t === "welcome" && !this.player && !this.opts.noAutoJoin) {
      this.send({ t: "create_profile", name: this.name, speech: this.name, avatar: { hair: 2, outfit: 7, glasses: 1 } });
    } else if (m.t === "joined") { this.player = m.player_id; this.resume = m.resume; }
    else if (m.t === "error") this.errors.push(m.code);
    else if (m.t === "status") this.status = m;
    else if (m.t === "screen") {
      this.screens.push(m.screen); this.last = m;
      if (m.screen === "question" && !this.answered.has(m.data.qid) && !this.opts.silent) {
        this.answered.add(m.data.qid);
        const c = Math.floor(Math.random() * m.data.options.length);
        setTimeout(() => this.send({ t: "answer", q: m.data.qid, c }), 50 + Math.random() * 300);
      }
      if (m.screen === "hole_pick" && !this.opts.silent) {
        const d = m.data, key = d.qid + ":" + d.stage;
        if (!this.answered.has(key)) {
          this.answered.add(key);
          // gamble on a glimpse sometimes, otherwise ask for a better look; always commit at the end
          const lock = !d.can_pass || Math.random() < 0.35;
          setTimeout(() => this.send(lock ? { t: "lock", q: d.qid, s: d.stage, c: Math.floor(Math.random() * d.options.length) }
                                          : { t: "pass", q: d.qid, s: d.stage }), 50 + Math.random() * 300);
          if (lock) this.locks = (this.locks || 0) + 1;
        }
      }
      if (m.screen === "result") this.results.push(m.data);
      if (m.screen === "hole_result") {
        if (!this.lastHole || this.lastHole !== m.data.answer) { this.holeResults.push(m.data); this.lastHole = m.data.answer; }
      }
      if (m.screen === "lobby" && m.data.captain && this.opts.startAt && m.data.count >= this.opts.startAt && !this.started) {
        this.started = true; setTimeout(() => this.send({ t: "start_show" }), 200);
      }
    }
  }
  async waitFor(pred, ms = 30000) {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) { if (pred(this)) return true; await sleep(50); }
    return false;
  }
}

function check(sc, cond, msg) { sc.checks.push({ ok: !!cond, msg }); if (!cond) console.log("   FAIL:", msg); }

async function scenario(name, fn) {
  const sc = { name, checks: [], started: Date.now() };
  console.log("SCENARIO", name);
  let host;
  try {
    host = await startHost(name);
    await fn(host, sc);
    check(sc, !host.events.some((e) => e.e === "__script_error"), "no GDScript errors on the host");
  } catch (e) { check(sc, false, "exception: " + (e && e.stack || e)); }
  finally { if (host) host.stop(); }
  sc.ms = Date.now() - sc.started;
  sc.pass = sc.checks.every((c) => c.ok);
  console.log(sc.pass ? "  PASS" : "  FAIL", `(${sc.checks.length} checks, ${sc.ms} ms)`);
  results.push(sc);
}

await scenario("http_static_and_security", async (h, sc) => {
  const idx = await httpGet(h.port, "/");
  check(sc, idx.status === 200 && idx.body.includes("HOME RESPONSE UNIT"), "GET / serves the controller");
  check(sc, (idx.type || "").startsWith("text/html"), "html content type");
  const cfg = await httpGet(h.port, "/config.js");
  check(sc, cfg.status === 200 && cfg.body.includes(`"wsPort":${h.wsPort}`), "config.js advertises ws port");
  for (const p of ["/app.js", "/style.css", "/assets/fonts/DejaVuSansMono-Bold.ttf", "/api/avatar", "/api/info"]) {
    const r = await httpGet(h.port, p); check(sc, r.status === 200, `GET ${p} = 200 (got ${r.status})`);
  }
  check(sc, (await httpGet(h.port, "/?k=" + h.ready.key)).status === 200, "QR URL with key query serves index");
  check(sc, (await httpGet(h.port, "/../project.godot")).status === 400, "path traversal rejected");
  check(sc, (await httpGet(h.port, "/nope.js")).status === 404, "missing file 404");
  check(sc, (await httpGet(h.port, "/", "POST")).status === 405, "POST rejected");
  check(sc, h.ready.join_url.includes("?k=" + h.ready.key), "join URL carries the session key (no code re-entry)");
});

await scenario("two_players_full_show", async (h, sc) => {
  const a = new Phone(h, "Aaron", { startAt: 2 });
  const b = new Phone(h, "Sarah", { useRoomCode: true });
  await a.connect(); await b.connect();
  check(sc, await a.waitFor((p) => p.player) && await b.waitFor((p) => p.player), "both phones joined (QR key + room code)");
  check(sc, await a.waitFor((p) => p.last && p.last.screen === "ended", 300000), "show reached END OF TRANSMISSION");
  const ended = h.events.find((e) => e.e === "show_ended");
  check(sc, !!ended, "host emitted show_ended");
  const qs = h.events.filter((e) => e.e === "question_show" && e.game_id === "studio_rehearsal").length;
  check(sc, qs === 2, `two studio-rehearsal questions on a new installation (got ${qs})`);
  const games = new Set(h.events.filter((e) => e.e === "sting").map((e) => e.game_id || e.title));
  check(sc, games.size >= 3, `rehearsal + at least two games in the programme (${[...games]})`);
  const reveals = h.events.filter((e) => e.e === "reveal").length;
  const rounds = h.events.filter((e) => e.e === "hole_reveal").length;
  check(sc, rounds === 6, `six Hole rounds (got ${rounds})`);
  check(sc, h.events.some((e) => e.e === "hole_lock"), "phones locked Hole answers over the network");
  for (const ph of [a, b]) {
    const sum = ph.results.reduce((s, r) => s + r.points, 0) + ph.holeResults.reduce((s, r) => s + r.points, 0);
    const st = ended.standings.find((s) => s.pid === ph.player);
    check(sc, st && st.score === sum, `${ph.name}: server score ${st && st.score} equals sum of result screens ${sum}`);
    check(sc, ph.results.length === reveals, `${ph.name} saw a result for every question (${ph.results.length}/${reveals})`);
    check(sc, ph.holeResults.length === 6, `${ph.name} saw 6 Hole results (got ${ph.holeResults.length})`);
  }
  check(sc, a.errors.length === 0 && b.errors.length === 0, `no protocol errors (${a.errors} / ${b.errors})`);
  a.close(); b.close();
});

await scenario("eight_players_and_ninth_rejected", async (h, sc) => {
  const names = ["Aaron", "Sarah", "Claire", "Steve", "Daniel", "Sam", "Stacy", "Neil"];
  const phones = names.map((n, i) => new Phone(h, n, i === 0 ? { startAt: 8 } : {}));
  for (const p of phones) { await p.connect(); await p.waitFor((x) => x.player, 5000); }
  check(sc, phones.every((p) => p.player), "eight phones joined");
  const ninth = new Phone(h, "Carol");
  await ninth.connect();
  check(sc, await ninth.waitFor((p) => p.errors.includes("room_full"), 5000), "ninth phone told room_full");
  check(sc, await phones[0].waitFor((p) => p.last && p.last.screen === "ended", 360000), "8-player show completed");
  const ended = h.events.find((e) => e.e === "show_ended");
  check(sc, ended && ended.standings.length === 8, "eight in final standings");
  phones.forEach((p) => p.close()); ninth.close();
});

await scenario("reconnect_within_window", async (h, sc) => {
  const a = new Phone(h, "Aaron", { startAt: 2 });
  const b = new Phone(h, "Sarah");
  await a.connect(); await b.connect();
  check(sc, await b.waitFor((p) => p.last && p.last.screen === "question", 60000), "reached a question");
  const pid = b.player;
  b.close();
  check(sc, await a.waitFor((p) => p.status.paused && p.status.reason === "reconnect", 5000), "other phone sees honest reconnect hold");
  const lost = a.status.detail && a.status.detail.lost && a.status.detail.lost[0];
  check(sc, lost && lost.name === "Sarah", "hold names the missing player");
  await sleep(800);
  await b.connect();
  check(sc, await b.waitFor((p) => p.msgs.some((m) => m.t === "joined" && m.resumed), 5000), "resume token restores the player");
  check(sc, b.player === pid, "same player id after reconnect");
  check(sc, await a.waitFor((p) => !p.status.paused, 5000), "hold released immediately on return");
  check(sc, await a.waitFor((p) => p.last && p.last.screen === "ended", 300000), "show completed after reconnect");
  check(sc, h.events.some((e) => e.e === "player_back"), "host emitted player_back");
  a.close(); b.close();
});

await scenario("drop_after_timeout_and_continue", async (h, sc) => {
  const a = new Phone(h, "Aaron", { startAt: 3 });
  const b = new Phone(h, "Sarah");
  const c = new Phone(h, "Claire");
  for (const p of [a, b, c]) await p.connect();
  check(sc, await c.waitFor((p) => p.last && p.last.screen === "question", 60000), "reached a question");
  c.close();
  check(sc, await a.waitFor((p) => p.status.paused, 5000), "held for reconnect");
  check(sc, await a.waitFor((p) => !p.status.paused, 30000 / SCALE + 8000), "hold released after the 30 s window");
  check(sc, h.events.some((e) => e.e === "player_dropped"), "player dropped");
  check(sc, h.events.some((e) => e.e === "say" && e.category === "reconnect_failed"), "Graham comments on the failure to return");
  check(sc, await a.waitFor((p) => p.last && p.last.screen === "ended", 300000), "show continues to the end with two");
  a.close(); b.close();
});

await scenario("invalid_actions_and_everyone_leaves", async (h, sc) => {
  const a = new Phone(h, "Aaron");
  const b = new Phone(h, "Sarah");
  await a.connect(); await b.connect();
  await a.waitFor((p) => p.player); await b.waitFor((p) => p.player);
  a.send({ t: "answer", q: "x", c: 0 });
  b.send({ t: "start_show" });
  a.send({ t: "award_points", points: 1e9 });
  a.ws.send("this is not json");
  check(sc, await a.waitFor((p) => p.errors.includes("invalid_state") && p.errors.includes("unknown_type") && p.errors.includes("bad_json"), 3000), `invalid actions rejected (${a.errors})`);
  check(sc, await b.waitFor((p) => p.errors.includes("not_captain"), 3000), "non-captain cannot start");
  const bad = new Phone(h, "Mallory", { noAutoJoin: true });
  bad.opts.useRoomCode = true; bad.host = { ...h, ready: { ...h.ready, room: "ZZZZ" } };
  await bad.connect();
  check(sc, await bad.waitFor((p) => p.errors.includes("bad_room"), 3000), "wrong room code rejected");
  a.send({ t: "start_show" });
  check(sc, await a.waitFor((p) => p.screens.includes("watch") || p.screens.includes("get_ready"), 10000), "show started");
  a.close(); b.close(); bad.close();
  const t0 = Date.now();
  while (Date.now() - t0 < 30000 / SCALE + 10000 && !h.events.some((e) => e.e === "session_closed")) await sleep(100);
  check(sc, h.events.some((e) => e.e === "all_gone"), "everyone gone detected");
  const closed = h.events.find((e) => e.e === "session_closed");
  check(sc, closed && closed.reason === "all_contestants_left", "transmission ended when nobody returned");
  check(sc, h.events.some((e) => e.e === "say" && e.category === "all_gone"), "Graham visibly annoyed");
});

fs.mkdirSync(path.join(ROOT, "tests/output"), { recursive: true });
await scenario("dev_panel_drives_bots_only_show", async (h, sc) => {
  const page = await httpGet(h.port, "/dev");
  check(sc, page.status === 200 && page.body.includes("MILDEW · DEV PANEL"), "GET /dev serves the panel in a debug build");
  check(sc, /^\d{4}$/.test(h.ready.dev_pin || ""), "host reports a 4-digit dev PIN");
  const dev = new WebSocket(`ws://127.0.0.1:${h.wsPort}`);
  const got = [];
  dev.onmessage = (ev) => got.push(JSON.parse(ev.data));
  await new Promise((r) => (dev.onopen = r));
  const wrong = h.ready.dev_pin === "0000" ? "1111" : "0000";
  dev.send(JSON.stringify({ t: "dev_hello", pin: wrong }));
  await sleep(300);
  check(sc, got.some((m) => m.t === "dev_denied") && !got.some((m) => m.t === "dev_welcome"), "wrong PIN refused");
  dev.send(JSON.stringify({ t: "dev_hello", pin: h.ready.dev_pin }));
  const until = async (pred, ms = 8000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (pred()) return true; await sleep(50); } return false; };
  check(sc, await until(() => got.some((m) => m.t === "dev_welcome")), "right PIN accepted");
  const welcome = got.find((m) => m.t === "dev_welcome");
  check(sc, welcome && welcome.catalogue.hole_items.length >= 20 && welcome.catalogue.incidents.length >= 10, "catalogue lists Hole items and incidents");
  const last = () => got.filter((m) => m.t === "dev_state").at(-1);
  const result = async (cmd, args) => { const n = got.length; dev.send(JSON.stringify({ t: "dev", cmd, args })); await until(() => got.slice(n).some((m) => m.t === "dev_result" && m.cmd === cmd)); return got.slice(n).find((m) => m.t === "dev_result" && m.cmd === cmd); };
  check(sc, !(await result("start_show", {})).ok, "start refused with nobody in the studio");
  check(sc, (await result("add_bot", { count: 3, personality: "risk_taker" })).ok, "add 3 bots");
  check(sc, await until(() => last() && last().players.length === 3 && last().players.every((p) => p.fake)), "state shows exactly the 3 bots (dev socket is never a player)");
  check(sc, (await result("force", { key: "hole_variant", value: "scale" })).ok, "force a SCALE round");
  check(sc, (await result("force", { key: "incident", value: "t0.mic_pop" })).ok, "force an incident");
  check(sc, !(await result("force", { key: "nonsense", value: "x" })).ok, "unknown force key refused");
  check(sc, (await result("timescale", { value: 8 })).ok, "set timescale");
  check(sc, (await result("start_show", {})).ok, "bots-only show started from the panel");
  check(sc, await until(() => last() && last().phase === "show"), "state reports the show");
  check(sc, await until(() => h.events.some((e) => e.e === "hole_round" && e.variant === "scale"), 60000), "forced SCALE variant used");
  check(sc, (await result("pause", { on: true })).ok && await until(() => last().manual_pause), "pause from the panel");
  check(sc, (await result("pause", { on: false })).ok && await until(() => !last().manual_pause), "resume from the panel");
  check(sc, await until(() => h.events.some((e) => e.e === "show_ended"), 360000), "bots-only show completes");
  check(sc, await until(() => last().events.length > 5 && last().decisions.length > 0), "live feed and Director decisions streamed");
  dev.close();
});

fs.writeFileSync(path.join(ROOT, "tests/output/integration_results.json"), JSON.stringify(results, null, 2));
const failed = results.filter((r) => !r.pass);
console.log(`\n${results.length} scenarios, ${failed.length} failed`);
process.exit(failed.length ? 1 : 0);
