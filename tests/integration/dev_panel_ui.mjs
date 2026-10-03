// Drives the phone dev panel (/dev, debug builds) in Chromium at phone size against the real headless
// host: PIN login (wrong then right), add bots, force a variant, start a bots-only show, pause/resume,
// reconnect after a transmission restart. Screenshots -> tests/output/devpanel/. Exit 0 = pass.
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "/home/claude/.npm-global/lib/node_modules/playwright");

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const OUT = path.join(ROOT, "tests/output/devpanel");
fs.mkdirSync(OUT, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const checks = [];
const check = (ok, msg) => { checks.push({ ok: !!ok, msg }); console.log(ok ? "  ok  " : "  FAIL", msg); };

const port = 18400, wsPort = 18401;
const proc = spawn("godot", ["--headless", "--path", ROOT, "--", "--mildew-host", "--port", String(port), "--ws-port", String(wsPort),
  "--timescale", "6", "--dev-pin", "2468", "--save-dir", `user://devpanel_${Date.now()}`], { stdio: ["ignore", "pipe", "pipe"] });
let ready = null, buf = "";
const events = [];
proc.stdout.on("data", (d) => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1);
  if (l.startsWith("MILDEW_HOST_READY ")) ready = JSON.parse(l.slice(18)); else if (l.startsWith("EVT ")) { try { events.push(JSON.parse(l.slice(4))); } catch {} } } });
for (let t = 0; t < 200 && !ready; t++) await sleep(100);
if (!ready) { console.error("host failed"); process.exit(2); }

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const P = await ctx.newPage();
const errors = [];
P.on("pageerror", (e) => errors.push(String(e)));
const shot = (n, full = false) => P.screenshot({ path: path.join(OUT, n + ".png"), fullPage: full });
const toast = () => P.locator("#toast").innerText();

try {
  check(ready.dev_pin === "2468", "--dev-pin fixes the PIN for tests");
  await P.goto(`http://127.0.0.1:${port}/dev`);
  await P.fill("#pin", "1357");
  await P.click("#go");
  await P.waitForFunction(() => document.querySelector("#loginmsg").textContent.includes("Wrong PIN"), null, { timeout: 5000 });
  check(true, "wrong PIN shows a message and stays on the login screen");
  await shot("01_login_wrong_pin");
  await P.goto(`http://127.0.0.1:${port}/dev`);   // fresh socket (3 strikes would close it)
  await P.fill("#pin", "2468");
  await P.click("#go");
  await P.waitForSelector("#app:not([hidden])", { timeout: 5000 });
  check(true, "right PIN opens the panel");
  await P.selectOption("#persona", "risk_taker");
  await P.selectOption("#botcount", "4");
  await P.click("#addbots");
  await P.waitForFunction(() => document.querySelectorAll("#players tr").length === 4, null, { timeout: 5000 });
  check(true, "four bots listed");
  await P.click('#variants button[data-v="scale"]');
  await P.waitForFunction(() => document.querySelector("#forced").textContent.includes("hole_variant=scale"), null, { timeout: 5000 });
  check(true, "forced variant shown as waiting");
  await P.selectOption("#nextgame", "hole");
  await P.waitForFunction(() => document.querySelector("#forced").textContent.includes("game=hole"), null, { timeout: 5000 });
  check(true, "forced first game shown as waiting");
  await shot("02_lobby_with_bots", true);
  await P.click('#speeds button[data-v="8"]');
  await P.click('button[data-cmd="start_show"]');
  await P.waitForFunction(() => document.querySelector("#phase").textContent === "SHOW", null, { timeout: 8000 });
  check(true, "show started from the phone");
  await P.click("#pausebtn");
  await P.waitForFunction(() => document.querySelector("#pausebtn").textContent === "RESUME", null, { timeout: 5000 });
  check(true, "pause button reflects the paused show");
  await shot("03_show_paused");
  await P.click("#pausebtn");
  await P.waitForFunction(() => document.querySelector("#pausebtn").textContent === "PAUSE", null, { timeout: 5000 });
  for (let t = 0; t < 400 && !events.some((e) => e.e === "hole_round"); t++) await sleep(100);
  check(events.some((e) => e.e === "hole_round" && e.variant === "scale"), "forced SCALE round reached the TV");
  await sleep(1500);
  await shot("04_show_running_feed", true);
  // Restart: sockets close, the panel reconnects by itself with the stored PIN.
  P.on("dialog", (d) => d.accept());
  await P.click("#restart");
  await P.waitForFunction(() => document.querySelector("#phase").textContent === "LOBBY", null, { timeout: 15000 });
  check(true, "panel reconnected after RESTART TRANSMISSION and shows the fresh lobby");
  check(errors.length === 0, "no page JS errors: " + errors.join(" | "));
} catch (e) {
  check(false, "exception: " + e.message);
  await shot("zz_fail", true).catch(() => {});
} finally {
  await browser.close();
  proc.kill("SIGKILL");
}
const failed = checks.filter((c) => !c.ok).length;
console.log(`${checks.length} checks, ${failed} failed`);
process.exit(failed ? 1 : 0);
