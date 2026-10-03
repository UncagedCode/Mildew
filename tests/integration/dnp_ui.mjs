// DO NOT PRESS THAT on real phone pages (Chromium portrait) against the real headless host:
// two phones get different panels and instructions, a tap changes server state, the decoy jams
// and is reported on the TV. Screenshots -> tests/output/phone/dnp_*. Exit 0 = pass.
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "/home/claude/.npm-global/lib/node_modules/playwright");

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const OUT = path.join(ROOT, "tests/output/phone");
fs.mkdirSync(OUT, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const checks = [];
const check = (ok, msg) => { checks.push({ ok: !!ok, msg }); console.log(ok ? "  ok  " : "  FAIL", msg); };

const port = 18340, wsPort = 18341;
const proc = spawn("godot", ["--headless", "--path", ROOT, "--", "--mildew-host", "--port", String(port), "--ws-port", String(wsPort),
  "--timescale", "6", "--force-games", "do_not_press_that", "--save-dir", `user://dnpui_${Date.now()}`], { stdio: ["ignore", "pipe", "pipe"] });
let ready = null, buf = "";
const events = [];
proc.stdout.on("data", (d) => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1);
  if (l.startsWith("MILDEW_HOST_READY ")) ready = JSON.parse(l.slice(18)); else if (l.startsWith("EVT ")) { try { events.push(JSON.parse(l.slice(4))); } catch {} } } });
for (let t = 0; t < 200 && !ready; t++) await sleep(100);
if (!ready) { console.error("host failed"); process.exit(2); }

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined });
const phone = { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true };
const ctxA = await browser.newContext(phone);
const ctxB = await browser.newContext({ ...phone, viewport: { width: 360, height: 740 } });
const A = await ctxA.newPage();
const B = await ctxB.newPage();
const consoleErrors = [];
for (const p of [A, B]) p.on("pageerror", (e) => consoleErrors.push(String(e)));
const lcdText = (p) => p.locator("#lcd-inner").innerText();
const shot = (p, n) => p.screenshot({ path: path.join(OUT, n + ".png") });

try {
  const join = async (p, name) => {
    await p.goto(`http://127.0.0.1:${port}/?k=${ready.key}`);
    await p.waitForSelector("text=IDENTIFY YOURSELF", { timeout: 8000 });
    await p.click('button:has-text("NEW CONTESTANT")');
    await p.fill("input[type=text]", name);
    await p.click('button:has-text("CONTINUE")');
    await p.waitForSelector('button:has-text("YES")');
    await p.click('button:has-text("YES")');
    await p.click('button:has-text("CONFIRM IDENTITY")');
  };
  await join(A, "Aaron");
  await join(B, "Grace");
  await A.waitForSelector('button:has-text("EVERYBODY\'S IN — BEGIN"):not([disabled])', { timeout: 10000 });
  await A.click('button:has-text("BEGIN")');
  await A.waitForSelector("#dnp-panel .dnp-ctl", { timeout: 120000 });
  await B.waitForSelector("#dnp-panel .dnp-ctl", { timeout: 10000 });
  await A.waitForSelector(".timer", { timeout: 30000 });
  await shot(A, "dnp_01_panel_A");
  await shot(B, "dnp_02_panel_B");
  const insA = await A.locator(".dnp-line").allInnerTexts();
  const insB = await B.locator(".dnp-line").allInnerTexts();
  check(insA.length + insB.length >= 3, `instructions dealt (${insA.length} + ${insB.length})`);
  const labA = await A.locator(".dnp-ctl .dnp-label").allInnerTexts();
  const labB = await B.locator(".dnp-ctl .dnp-label").allInnerTexts();
  check(labA.length >= 1 && labB.length >= 1 && !labA.some((l) => labB.includes(l)), "each phone has its own controls");
  check(!insA.some((t) => labA.some((l) => t.startsWith("\u25B8 " + l + " ") || t.startsWith("\u25B8 Set " + l + " ") || t.startsWith("\u25B8 Press " + l + " "))), "nobody holds the instruction for their own control");
  const before = events.filter((e) => e.e === "dnp_state").length;
  const real = A.locator(".dnp-ctl:not(.decoy) button").first();
  await real.click();
  await sleep(1500);
  check(events.filter((e) => e.e === "dnp_state").length > before, "a tap changes authoritative state on the TV");
  const decoyOwner = (await A.locator(".dnp-ctl.decoy").count()) ? A : B;
  await decoyOwner.locator(".dnp-ctl.decoy button").first().click();
  const jammed = await decoyOwner.waitForSelector(".dnp-ctl.decoy.jammed", { timeout: 3000 }).then(() => true).catch(() => false);
  check(jammed, "the decoy jams on that phone (time-scaled jam)");
  await shot(decoyOwner, "dnp_03_jammed");
  await sleep(800);
  check(events.some((e) => e.e === "dnp_mistake" && e.kind === "decoy"), "pressing the thing you shouldn't is reported");
  await A.waitForSelector("text=/PERFECT|COMPLETED|FAILED SPECTACULARLY/", { timeout: 120000 });
  await shot(A, "dnp_04_result");
  check(true, "puzzle resolves with a success tier on the phone");
  check(consoleErrors.length === 0, "no page JS errors: " + consoleErrors.join(" | "));
} catch (e) {
  check(false, "exception: " + e.message);
  await shot(A, "dnp_zz_fail_A").catch(() => {});
  await shot(B, "dnp_zz_fail_B").catch(() => {});
} finally {
  await browser.close();
  proc.kill("SIGKILL");
}
const failed = checks.filter((c) => !c.ok).length;
console.log(`${checks.length} checks, ${failed} failed`);
process.exit(failed ? 1 : 0);
