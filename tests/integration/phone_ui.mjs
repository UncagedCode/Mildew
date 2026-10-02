// Drives the real phone controller in Chromium (portrait phone viewport) against the real
// headless host: code entry, new-contestant wizard (name -> pronunciation -> likeness),
// returning-profile selection, lobby captain start, tapping answers, reconnect banner.
// Screenshots -> tests/output/phone/. Exit 0 = pass.
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

const port = 18300, wsPort = 18301;
const proc = spawn("godot", ["--headless", "--path", ROOT, "--", "--mildew-host", "--port", String(port), "--ws-port", String(wsPort),
  "--timescale", "3", "--save-dir", `user://phone_${Date.now()}`], { stdio: ["ignore", "pipe", "pipe"] });
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
  // --- Phone A: manual URL + room code entry, full new-contestant wizard ---------------
  await A.goto(`http://127.0.0.1:${port}/`);
  await A.waitForSelector(".codebox");
  await shot(A, "01_code_entry");
  await A.fill(".codebox", ready.room.toLowerCase());
  await A.click('button:has-text("CONNECT")');
  await A.waitForSelector("text=IDENTIFY YOURSELF", { timeout: 8000 });
  check((await A.locator("#link").getAttribute("data-state")) === "up", "real link LED shows connected");
  await shot(A, "02_identify");
  await A.click('button:has-text("NEW CONTESTANT")');
  await A.fill("input[type=text]", "Siobhan");
  await shot(A, "03_name");
  await A.click('button:has-text("CONTINUE")');
  await A.waitForSelector("text=IS THIS PRONUNCIATION CORRECT?");
  await sleep(300);
  check(events.some((e) => e.e === "say" && e.pronunciation_test), "TV speaks the name for the pronunciation check");
  await shot(A, "04_pronunciation");
  await A.click('button:has-text("NO — SPELL IT HOW IT SOUNDS")');
  await sleep(900);
  await A.fill("input[type=text]", "Shiv-awn");
  await A.click('button:has-text("TRY IT")');
  await sleep(1500);
  check(events.filter((e) => e.e === "say" && e.pronunciation_test).some((e) => e.speech.includes("Shiv-awn")), "phonetic spelling re-spoken on TV");
  await A.click('button:has-text("YES")');
  await A.waitForSelector("text=CONTESTANT LIKENESS");
  await A.click(".avatar-row:nth-child(1) .arrow >> nth=1");
  await A.click(".avatar-row:nth-child(5) .arrow >> nth=1");
  await shot(A, "05_likeness");
  await A.click('button:has-text("CONFIRM IDENTITY")');
  await A.waitForSelector("text=CONTESTANT No. 1", { timeout: 8000 });
  check((await lcdText(A)).includes("SIOBHAN"), "lobby shows identity");
  await shot(A, "06_lobby_captain_waiting");

  // --- Phone B: QR link (key in URL), duplicate name, then join -------------------------
  await B.goto(`http://127.0.0.1:${port}/?k=${ready.key}`);
  await B.waitForSelector("text=IDENTIFY YOURSELF", { timeout: 8000 });
  check(true, "QR link joins without typing a room code");
  await B.click('button:has-text("NEW CONTESTANT")');
  await B.fill("input[type=text]", "siobhan");
  await B.click('button:has-text("CONTINUE")');
  await B.waitForSelector("text=ALREADY ON A PODIUM", { timeout: 5000 });
  check(true, "duplicate active name rejected with on-brand copy");
  await shot(B, "07_duplicate_name");
  await B.fill("input[type=text]", "Neil");
  await B.click('button:has-text("CONTINUE")');
  await B.waitForSelector('button:has-text("YES")');
  await B.click('button:has-text("YES")');
  await B.click('button:has-text("CONFIRM IDENTITY")');
  await B.waitForSelector("text=WAITING FOR THE FLOOR CAPTAIN", { timeout: 8000 });

  // --- Start via captain, answer by tapping --------------------------------------------
  await A.waitForSelector('button:has-text("EVERYBODY\'S IN — BEGIN"):not([disabled])');
  await shot(A, "08_lobby_captain_ready");
  await A.click('button:has-text("BEGIN")');
  await A.waitForSelector(".key.a", { timeout: 60000 });
  await shot(A, "09_question");
  await A.click(".key.a");
  await A.waitForSelector("text=ANSWER LOCKED", { timeout: 5000 });
  await shot(A, "10_locked");
  await B.waitForSelector(".key.b", { timeout: 10000 });
  await B.click(".key.b");
  await A.waitForSelector("text=YOUR SCORE", { timeout: 20000 });
  await shot(A, "11_result");

  // --- Reconnect: B's page goes away and comes back (resume token in localStorage) -------
  await B.waitForSelector(".key.a", { timeout: 60000 });
  await B.goto("about:blank");
  await A.waitForSelector("#sysbar:not([hidden])", { timeout: 15000 });
  const bar = await A.locator("#sys-title").innerText();
  check(bar.includes("NEIL") && bar.includes("RECONNECT"), `honest reconnect banner on other phone: "${bar}"`);
  await shot(A, "12_waiting_for_reconnect");
  await B.goto(`http://127.0.0.1:${port}/?k=${ready.key}`);
  await B.waitForSelector(".key, text=ANSWER LOCKED, text=QUESTION INCOMING, text=PLEASE WATCH", { timeout: 10000 }).catch(() => {});
  check(!(await B.locator("text=IDENTIFY YOURSELF").count()), "returning tab resumes as the same contestant (no re-identify)");
  await A.waitForSelector("#sysbar[hidden]", { state: "attached", timeout: 10000 });
  check(true, "banner cleared after reconnect");
  // --- Hole: early lock on a glimpse, confirm step, locked screen, result ------------------
  await A.waitForSelector('button:has-text("SHOW ME MORE")', { timeout: 90000 });
  await shot(A, "13_hole_pick");
  check(await A.locator(".keygrid button").count() >= 4, "Hole look shows candidate tiles");
  await A.locator(".keygrid button").first().click();
  await A.waitForSelector('button:has-text("YES — LOCK IT IN")', { timeout: 5000 });
  await shot(A, "14_hole_confirm");
  await A.click('button:has-text("YES — LOCK IT IN")');
  await A.waitForSelector("text=NO TAKE-BACKS. WATCH THE TELEVISION", { timeout: 5000 });
  await shot(A, "15_hole_locked");
  const bm = B.locator('button:has-text("SHOW ME MORE")');
  if (await bm.count()) await bm.first().click().catch(() => {});
  await A.waitForSelector("text=YOUR SCORE", { timeout: 60000 });
  check(await A.locator("text=/CORRECT|WRONG|RIGHT SORT OF THING/").count(), "Hole result screen shown");
  await shot(A, "16_hole_result");
  // finish
  for (let i = 0; i < 900; i++) {
    for (const p of [A, B]) { const k = p.locator(".key.c"); if (await k.count()) await k.first().click().catch(() => {}); }
    if (await A.locator("text=END OF TRANSMISSION").count()) break;
    await sleep(300);
  }
  check(await A.locator("text=END OF TRANSMISSION").count(), "phone reaches END OF TRANSMISSION");
  await shot(A, "17_ended_captain");
  check(consoleErrors.length === 0, "no page JS errors: " + consoleErrors.join(" | "));
} catch (e) {
  check(false, "exception: " + e.message);
  await shot(A, "zz_fail_A").catch(() => {});
  await shot(B, "zz_fail_B").catch(() => {});
} finally {
  await browser.close();
  proc.kill("SIGKILL");
}
fs.writeFileSync(path.join(ROOT, "tests/output/phone_ui_results.json"), JSON.stringify(checks, null, 2));
const failed = checks.filter((c) => !c.ok).length;
console.log(`${checks.length} checks, ${failed} failed`);
process.exit(failed ? 1 : 0);
