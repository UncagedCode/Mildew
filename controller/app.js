/* MILDEW HOME RESPONSE UNIT — phone controller.
 * Served by the TV over local Wi-Fi. No frameworks, no internet, no installs.
 * The phone is an untrusted input device: it only sends intents (join, answer...);
 * the TV decides everything. Real connection status is always shown honestly.
 */
(() => {
  "use strict";
  const CFG = window.MILDEW_CONFIG || { wsPort: 8081, protocol: 1, pingMs: 2000, maxName: 16 };
  const params = new URLSearchParams(location.search);
  const $ = (id) => document.getElementById(id);
  const lcd = $("lcd-inner"), keys = $("keys");

  const S = {
    ws: null, key: params.get("k") || "", room: (params.get("room") || "").toUpperCase(),
    connected: false, helloOk: false, playerId: "", number: 0, seq: 0, screen: null,
    status: { paused: false, reason: "" }, avatarParts: null, profiles: [],
    retry: 0, retryTimer: null, pingTimer: null, pingId: 0, pingSent: {}, rtt: -1,
    wizard: null, kicked: false, ended: false, timerRAF: 0, lastError: "",
  };

  // ---------------- storage (resume token survives refresh / brief drops) ----------------
  const store = {
    get(k) { try { return localStorage.getItem("mildew." + k) || ""; } catch (e) { return ""; } },
    set(k, v) { try { localStorage.setItem("mildew." + k, v); } catch (e) { /* private mode */ } },
    del(k) { try { localStorage.removeItem("mildew." + k); } catch (e) { /* ignore */ } },
  };
  const tokenKey = () => "resume." + (S.key || S.room || "none");

  // ---------------- helpers ----------------
  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined && text !== null) e.textContent = text;
    return e;
  }
  function clear() { lcd.textContent = ""; keys.textContent = ""; cancelAnimationFrame(S.timerRAF); }
  function buzz(p) { try { if (navigator.vibrate) navigator.vibrate(p); } catch (e) { /* unsupported */ } }
  function key(label, cls, onTap, cap) {
    const b = el("button", "key " + (cls || ""));
    if (cap) { const c = el("span", "cap", cap); b.appendChild(c); }
    b.appendChild(document.createTextNode(label));
    b.addEventListener("click", (ev) => { ev.preventDefault(); if (b.disabled) return; buzz(15); onTap(b); });
    keys.appendChild(b);
    return b;
  }
  function send(msg) {
    if (S.ws && S.ws.readyState === 1) { S.ws.send(JSON.stringify(msg)); return true; }
    return false;
  }
  function pad4(n) { return String(n).padStart(4, "0"); }
  function ordinal(n) { const s = ["TH", "ST", "ND", "RD"], v = n % 100; return n + (s[(v - 20) % 10] || s[v] || s[0]); }

  // ---------------- link status (REAL network state only) ----------------
  function setLink(state, text) {
    $("link").dataset.state = state;
    $("link-text").textContent = text;
  }
  function sysbar(kind, title, detail) {
    const b = $("sysbar");
    if (!kind) { b.hidden = true; return; }
    b.hidden = false; b.dataset.kind = kind;
    $("sys-title").textContent = title; $("sys-detail").textContent = detail || "";
  }

  // ---------------- connection ----------------
  function connect() {
    clearTimeout(S.retryTimer);
    if (S.ws) { try { S.ws.onclose = null; S.ws.close(); } catch (e) { /* ignore */ } }
    setLink(S.retry ? "retry" : "retry", "LINKING");
    let ws;
    try { ws = new WebSocket("ws://" + location.hostname + ":" + CFG.wsPort + "/"); }
    catch (e) { scheduleRetry(); return; }
    S.ws = ws;
    ws.onopen = () => {
      S.connected = true; S.retry = 0;
      setLink("up", "LINK OK");
      sysbar(null);
      const hello = { t: "hello", v: CFG.protocol };
      if (S.key) hello.key = S.key; else hello.room = S.room;
      const tok = store.get(tokenKey());
      if (tok) hello.resume = tok;
      send(hello);
      clearInterval(S.pingTimer);
      S.pingTimer = setInterval(ping, CFG.pingMs || 2000);
    };
    ws.onmessage = (ev) => { let m; try { m = JSON.parse(ev.data); } catch (e) { return; } handle(m); };
    ws.onclose = () => {
      S.connected = false; S.helloOk = false;
      clearInterval(S.pingTimer);
      if (S.kicked || S.ended) { setLink("down", "NO LINK"); return; }
      setLink("retry", "RECONNECTING");
      // Honest real-status banner: this is a genuine connection problem, never fiction.
      sysbar("net", "CONNECTION TO THE TELEVISION LOST", "Reconnecting automatically… keep this page open and stay on the same Wi-Fi.");
      scheduleRetry();
    };
    ws.onerror = () => { /* onclose follows */ };
  }
  function scheduleRetry() {
    S.retry++;
    const delay = Math.min(3000, 400 * S.retry);
    S.retryTimer = setTimeout(connect, delay);
  }
  function ping() {
    S.pingId++;
    S.pingSent[S.pingId] = performance.now();
    send({ t: "ping", id: S.pingId, rtt: S.rtt >= 0 ? Math.round(S.rtt) : undefined });
  }
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden && (!S.ws || S.ws.readyState > 1) && !S.kicked) { S.retry = 0; connect(); }
  });

  // ---------------- message handling ----------------
  function handle(m) {
    switch (m.t) {
      case "pong": {
        const t0 = S.pingSent[m.id]; if (t0) { S.rtt = performance.now() - t0; delete S.pingSent[m.id]; }
        return;
      }
      case "welcome":
        S.helloOk = true; S.playerId = ""; S.profiles = m.profiles || [];
        store.del(tokenKey());
        if (!S.wizard) showIdentify();
        return;
      case "joined":
        S.helloOk = true; S.playerId = m.player_id; S.number = m.number || 0; S.wizard = null;
        store.set(tokenKey(), m.resume);
        $("unit-no").textContent = "UNIT No. " + pad4(S.number);
        return;
      case "screen":
        if (m.seq && m.seq < S.seq && m.screen !== "closed") return;
        S.seq = m.seq || S.seq; S.screen = m;
        renderScreen(m.screen, m.data || {});
        return;
      case "status":
        S.status = m; renderStatus();
        return;
      case "name_result":
        onNameResult(m); return;
      case "kicked":
        S.kicked = true; store.del(tokenKey()); showKicked(); return;
      case "error":
        onError(m); return;
      case "interfere":
        interfere(m); return;
    }
  }

  const ERRORS = {
    bad_room: "THAT CODE DOES NOT MATCH THE BROADCAST ON YOUR TELEVISION.",
    bad_version: "THIS UNIT IS OUT OF DATE. RELOAD THE PAGE.",
    self_vote: "YOU CAN'T VOTE FOR YOUR OWN ANSWER. WE CHECK.",
    name_taken: "THAT NAME IS ALREADY ON A PODIUM. TRY ANOTHER (E.G. ADD AN INITIAL).",
    name_invalid: "THE PRESENTER CANNOT PRONOUNCE THAT. LETTERS AND NUMBERS ONLY, PLEASE.",
    room_full: "ALL EIGHT PODIUMS ARE TAKEN. YOU MAY WATCH FROM THE SOFA.",
    profile_unavailable: "THAT CONTESTANT IS ALREADY HERE, OR NO LONGER EXISTS.",
    not_captain: "ONLY THE FLOOR CAPTAIN MAY DO THAT.",
    not_enough_players: "AT LEAST TWO CONTESTANTS ARE REQUIRED.",
    rate_limited: "PLEASE STOP PRESSING EVERYTHING.",
  };
  function onError(m) {
    S.lastError = m.code;
    if (m.code === "bad_room") { store.del(tokenKey()); S.key = ""; showCodeEntry(ERRORS.bad_room); return; }
    if (m.code === "bad_version") { showMessage("UNIT FAULT", ERRORS.bad_version); return; }
    const text = ERRORS[m.code];
    if (!text) return; // invalid-state style errors are expected races; stay quiet
    if (S.wizard && (m.code === "name_taken" || m.code === "name_invalid")) { wizardName(text); return; }
    if (m.code === "self_vote" && S.screen && S.screen.screen === "wv_vote") { scrWVVote(S.screen.data || {}); }
    toast(text);
  }
  // Private interference: brief, unrecoverable, never blocks input (pointer-events: none),
  // never imitates the phone's own call screen. Nothing is stored or listed anywhere.
  function interfere(m) {
    const ms = Math.max(200, Math.min(4000, Number(m.ms) || 1300));
    if (m.buzz) buzz(m.buzz);
    const text = String(m.text || "");
    if (m.style === "buzz" || !text) return;
    if (m.style === "unit") {
      const u = $("unit-no"); const keep = u.textContent;
      u.textContent = text; u.classList.add("intf-unit");
      setTimeout(() => { u.textContent = keep; u.classList.remove("intf-unit"); }, ms);
      return;
    }
    const ta = document.getElementById("wv-text");
    if (m.style === "field" && ta) {
      const keep = ta.value, ro = ta.readOnly;
      ta.readOnly = true; ta.value = text; ta.classList.add("intf-field");
      setTimeout(() => { ta.value = keep; ta.readOnly = ro; ta.classList.remove("intf-field"); }, ms);
      return;
    }
    const o = el("div", "intf", text);
    document.body.appendChild(o);
    let changed = false;
    const onTouch = () => { if (m.after && !changed) { changed = true; o.textContent = String(m.after); } };
    if (m.after) document.addEventListener("pointerdown", onTouch, { once: true, capture: true });
    setTimeout(() => { o.remove(); document.removeEventListener("pointerdown", onTouch, { capture: true }); }, ms);
  }
  function toast(text) {
    const t = el("div", "toast flash", text);
    lcd.appendChild(t);
    setTimeout(() => t.remove(), 4500);
  }

  // ---------------- screens: joining ----------------
  function showCodeEntry(note) {
    clear();
    lcd.appendChild(el("div", "title", "ENTER BROADCAST CODE"));
    lcd.appendChild(el("div", "sub", note || "TYPE THE FOUR LETTERS SHOWN ON YOUR TELEVISION."));
    const inp = el("input", "codebox");
    inp.type = "text"; inp.maxLength = 4; inp.autocapitalize = "characters"; inp.autocomplete = "off"; inp.spellcheck = false;
    inp.value = S.room;
    lcd.appendChild(inp);
    const go = key("CONNECT", "go plain", () => {
      const v = inp.value.trim().toUpperCase();
      if (v.length !== 4) { toast("FOUR LETTERS, PLEASE."); return; }
      S.room = v; S.key = ""; S.kicked = false; S.retry = 0; connect();
      showMessage("ESTABLISHING CONNECTION", "PLEASE HOLD.");
    });
    inp.addEventListener("keydown", (e) => { if (e.key === "Enter") go.click(); });
    setTimeout(() => inp.focus(), 50);
  }

  function showMessage(title, sub) {
    clear();
    lcd.appendChild(el("div", "title blinker", title));
    if (sub) lcd.appendChild(el("div", "sub", sub));
  }

  function showIdentify() {
    clear();
    lcd.appendChild(el("div", "sub", "CONNECTION ESTABLISHED"));
    lcd.appendChild(el("div", "big blinker", "IDENTIFY YOURSELF"));
    if (S.profiles.length) {
      lcd.appendChild(el("div", "sub", "RETURNING CONTESTANTS:"));
      const list = el("div", "profiles");
      for (const p of S.profiles) {
        const b = el("button", "profile");
        const cv = document.createElement("canvas"); cv.width = 88; cv.height = 88;
        drawAvatar(cv, p.avatar || {});
        const txt = el("div", "", p.name);
        txt.appendChild(el("small", "", p.games_played ? (p.games_played + " BROADCAST" + (p.games_played === 1 ? "" : "S")) : "NEW-ISH"));
        b.appendChild(cv); b.appendChild(txt);
        b.addEventListener("click", () => { buzz(15); send({ t: "select_profile", profile_id: p.id }); showMessage("CHECKING RECORDS", "ONE MOMENT."); });
        list.appendChild(b);
      }
      lcd.appendChild(list);
    } else {
      lcd.appendChild(el("div", "sub", "NO RECORDS ON FILE. YOU ARE A NEW CONTESTANT."));
    }
    key("NEW CONTESTANT", "go plain", () => startWizard());
  }

  // New-contestant wizard: name -> pronunciation -> avatar -> create.
  function startWizard() {
    S.wizard = { name: store.get("draft.name"), speech: "", avatar: randomAvatar(), claim: "", match: null };
    wizardName();
  }
  function wizardName(note) {
    clear();
    lcd.appendChild(el("div", "title", "STATE YOUR NAME"));
    lcd.appendChild(el("div", note ? "sub warn" : "sub", note || "AS YOU WISH TO BE ADDRESSED ON TELEVISION."));
    const inp = el("input");
    inp.type = "text"; inp.maxLength = CFG.maxName || 16; inp.autocomplete = "off"; inp.spellcheck = false; inp.autocapitalize = "words";
    inp.value = S.wizard.name || "";
    inp.addEventListener("input", () => store.set("draft.name", inp.value));
    lcd.appendChild(inp);
    const go = key("CONTINUE", "go plain", () => {
      const v = inp.value.trim();
      if (!v) { toast("A NAME IS REQUIRED."); return; }
      S.wizard.name = v;
      send({ t: "check_name", name: v });
      showMessage("CHECKING RECORDS", "ONE MOMENT.");
    });
    key("BACK", "grey plain small", () => { S.wizard = null; showIdentify(); });
    inp.addEventListener("keydown", (e) => { if (e.key === "Enter") go.click(); });
    setTimeout(() => inp.focus(), 50);
  }
  function onNameResult(m) {
    if (!S.wizard) return;
    if (m.ok) {
      S.wizard.name = m.name; S.wizard.speech = S.wizard.speech || m.name;
      wizardPronounce(true);
      return;
    }
    if (m.code === "match_profile" && m.match_profile) { wizardMatch(m.match_profile); return; }
    wizardName(ERRORS[m.code] || (m.code === "name_invalid" ? ERRORS.name_invalid : "PLEASE TRY ANOTHER NAME."));
  }
  function wizardMatch(prof) {
    S.wizard.match = prof;
    clear();
    lcd.appendChild(el("div", "title", "WE'VE HAD A " + prof.name.toUpperCase() + " BEFORE."));
    const wrap = el("div", "avatar-wrap");
    const cv = document.createElement("canvas"); cv.width = 264; cv.height = 264; drawAvatar(cv, prof.avatar || {});
    wrap.appendChild(cv); lcd.appendChild(wrap);
    lcd.appendChild(el("div", "big", "IS THIS YOU?"));
    key("YES, THAT'S ME", "ok plain", () => { send({ t: "create_profile", name: prof.name, claim: prof.id }); showMessage("RESTORING RECORDS", "WELCOME BACK."); });
    key("NO — DIFFERENT PERSON", "grey plain", () => { S.wizard.name = ""; wizardName("PLEASE USE A NAME WE CAN TELL APART (E.G. " + prof.name.toUpperCase() + " B)."); });
  }
  // D024: Graham only says names he has a recording of (name bank). Unknown names skip the check;
  // debug builds may still use the device voice as a flagged developer fallback.
  function graham_knows(name) {
    const n = String(name || "").trim().toLowerCase().replace(/[^\p{L}\p{N} '\-]/gu, "").trim();
    return ((window.MILDEW_CONFIG || {}).voiceNames || []).includes(n);
  }
  function wizardPronounce(first) {
    const cfgv = window.MILDEW_CONFIG || {};
    if (!graham_knows(S.wizard.speech) && !cfgv.devTts) {
      if (first && graham_knows(S.wizard.name)) { S.wizard.speech = S.wizard.name; }
      else { return wizardAvatar(); }   // nothing to check: Graham will read it from his cards
    }
    clear();
    lcd.appendChild(el("div", "sub", "PRONUNCIATION CHECK"));
    lcd.appendChild(el("div", "big", "LISTEN TO YOUR TELEVISION."));
    lcd.appendChild(el("div", "title", "IS THIS PRONUNCIATION CORRECT?"));
    lcd.appendChild(el("div", "sub", "PRESENTER WILL SAY: \"" + S.wizard.speech.toUpperCase() + "\""));
    if (first) send({ t: "say_name", speech: S.wizard.speech });
    key("YES", "ok plain", () => wizardAvatar());
    if (cfgv.devTts && !graham_knows(S.wizard.speech)) lcd.appendChild(el("div", "sub warn", "DEVELOPER BUILD: SYSTEM VOICE, NOT GRAHAM."));
    if (cfgv.devTts) key("NO — SPELL IT HOW IT SOUNDS", "grey plain", () => wizardSpell());
    // Rejecting Graham's recording: store a speech form that matches no recording ("-name"), so he
    // never says the wrong name for this contestant. The displayed name is unaffected.
    else key("NO — THAT'S NOT IT", "grey plain", () => { S.wizard.speech = "-" + S.wizard.name; wizardAvatar(); });
    key("SAY IT AGAIN", "grey plain small", () => send({ t: "say_name", speech: S.wizard.speech }));
  }
  function wizardSpell() {
    clear();
    lcd.appendChild(el("div", "title", "SPELL IT HOW IT SOUNDS"));
    lcd.appendChild(el("div", "sub", "E.G. \"SHIV-AWN\" FOR SIOBHAN. YOUR NAME WILL STILL BE DISPLAYED AS \"" + S.wizard.name.toUpperCase() + "\"."));
    const inp = el("input"); inp.type = "text"; inp.maxLength = 40; inp.autocomplete = "off"; inp.spellcheck = false;
    inp.value = S.wizard.speech;
    lcd.appendChild(inp);
    key("TRY IT", "go plain", () => {
      const v = inp.value.trim(); if (!v) return;
      S.wizard.speech = v; send({ t: "say_name", speech: v }); wizardPronounce(false);
    });
    setTimeout(() => inp.focus(), 50);
  }
  function wizardAvatar() {
    clear();
    lcd.appendChild(el("div", "title", "CONTESTANT LIKENESS"));
    const wrap = el("div", "avatar-wrap");
    const cv = document.createElement("canvas"); cv.width = 264; cv.height = 264;
    wrap.appendChild(cv); lcd.appendChild(wrap);
    const rows = el("div", "avatar-rows");
    const P = S.avatarParts || DEFAULT_PARTS;
    const fields = [["hair", "HAIR", P.hair.length], ["hair_colour", "COLOUR", P.hair_colour.length], ["skin", "TONE", P.skin.length],
      ["glasses", "GLASSES", P.glasses.length], ["outfit", "OUTFIT", P.outfit.length], ["accessory", "EXTRA", P.accessory.length]];
    const labelFor = (f, v) => {
      if (f === "skin") return "TONE " + (v + 1);
      const arr = P[f]; const it = arr[v]; return Array.isArray(it) ? it[0] : it;
    };
    const redraw = () => drawAvatar(cv, S.wizard.avatar);
    for (const [f, title, n] of fields) {
      const row = el("div", "avatar-row");
      const l = el("button", "arrow", "◀"); const r = el("button", "arrow", "▶");
      const lab = el("div", "lab"); const small = el("small", "", title); const val = el("span", "", labelFor(f, S.wizard.avatar[f]));
      lab.appendChild(small); lab.appendChild(val);
      const step = (d) => { buzz(8); S.wizard.avatar[f] = (S.wizard.avatar[f] + d + n) % n; val.textContent = labelFor(f, S.wizard.avatar[f]); redraw(); };
      l.addEventListener("click", () => step(-1)); r.addEventListener("click", () => step(1));
      row.appendChild(l); row.appendChild(lab); row.appendChild(r); rows.appendChild(row);
    }
    lcd.appendChild(rows);
    redraw();
    key("CONFIRM IDENTITY", "go plain", () => {
      send({ t: "create_profile", name: S.wizard.name, speech: S.wizard.speech, avatar: S.wizard.avatar });
      store.del("draft.name");
      showMessage("PROCESSING", "PLEASE STAND BY.");
    });
  }

  // ---------------- screens: in programme ----------------
  function renderScreen(name, d) {
    if (S.wizard && name !== "closed") return; // stay in the wizard until joined
    switch (name) {
      case "lobby": return scrLobby(d);
      case "watch": return scrWatch(d.caption || "PLEASE WATCH YOUR TELEVISION");
      case "get_ready": buzz(25); return scrWatch(d.caption || "QUESTION INCOMING", true, d.header);
      case "hole_pick": return scrHolePick(d);
      case "hole_locked": return scrHoleLocked(d);
      case "hole_waiting": return scrWatch(d.caption || "WAITING FOR A BETTER LOOK", false, d.header);
      case "hole_result": return scrHoleResult(d);
      case "question": return scrQuestion(d);
      case "wv_write": return scrWVWrite(d);
      case "wv_wait": return scrWVWait(d);
      case "wv_vote": return scrWVVote(d);
      case "wv_rate": return scrWVRate(d);
      case "wv_result": return scrWVResult(d);
      case "locked": return scrLocked(d);
      case "result": return scrResult(d);
      case "scores": return scrScores(d);
      case "spectator": return scrWatch(d.caption || "YOU WILL JOIN AT THE NEXT SEGMENT", false, "LATE ARRIVAL");
      case "ended": return scrEnded(d);
      case "closed": return scrClosed(d);
      default: return scrWatch("PLEASE WATCH YOUR TELEVISION");
    }
  }

  function scrLobby(d) {
    clear();
    lcd.appendChild(el("div", "sub", "IDENTITY CONFIRMED"));
    lcd.appendChild(el("div", "big", (d.name || "").toUpperCase()));
    lcd.appendChild(el("div", "title", "CONTESTANT No. " + (d.number || "?")));
    lcd.appendChild(el("div", "spacer"));
    lcd.appendChild(el("div", "sub", d.count + " CONTESTANT" + (d.count === 1 ? "" : "S") + " ON PODIUMS. MINIMUM " + d.min + "."));
    if (d.captain) {
      lcd.appendChild(el("div", "sub", "YOU ARE FLOOR CAPTAIN. PRESS THE BUTTON WHEN EVERYBODY IS IN."));
      const b = key(d.can_start ? "EVERYBODY'S IN — BEGIN" : "WAITING FOR CONTESTANTS", "go plain", () => send({ t: "start_show" }));
      b.disabled = !d.can_start;
    } else {
      lcd.appendChild(el("div", "sub blinker", "WAITING FOR THE FLOOR CAPTAIN TO BEGIN"));
    }
    key("LEAVE THE STUDIO", "grey plain small", () => { if (confirm("Leave the studio?")) send({ t: "leave" }); });
  }

  function scrWatch(caption, urgent, header) {
    clear();
    if (header) lcd.appendChild(el("div", "sub", header));
    lcd.appendChild(el("div", "spacer"));
    lcd.appendChild(el("div", urgent ? "big blinker" : "title", caption));
    lcd.appendChild(el("div", "spacer"));
    lcd.appendChild(el("div", "sub", "UNIT No. " + pad4(S.number) + " · STANDING BY"));
  }

  function scrQuestion(d) {
    clear();
    buzz([30, 40, 30]);
    if (d.header) lcd.appendChild(el("div", "sub", d.header));
    lcd.appendChild(el("div", "prompt", d.prompt));
    if (d.confidence) lcd.appendChild(el("div", "sub warn", "CONFIDENCE ROUND: PICK, THEN SAY HOW SURE YOU ARE."));
    const bar = el("div", "timer"); const fill = el("div"); bar.appendChild(fill); lcd.appendChild(bar);
    const secs = el("div", "sub"); lcd.appendChild(secs);
    const total = Math.max(1, d.total_ms || 20000);
    const end = performance.now() + (d.remaining_ms || 0);
    const tick = () => {
      const left = Math.max(0, end - performance.now());
      fill.style.transform = "scaleX(" + (left / total).toFixed(3) + ")";
      secs.textContent = Math.ceil(left / 1000) + " SECONDS";
      if (left > 0) S.timerRAF = requestAnimationFrame(tick);
    };
    tick();
    const caps = ["A", "B", "C", "D"], cls = ["a", "b", "c", "d"];
    const submit = (i, k) => send({ t: "answer", q: d.qid, c: i, k: k ? 1 : 0 });
    (d.options || []).forEach((opt, i) => {
      const b = key(opt, cls[i] + (d.long ? " long" : ""), (btn) => {
        if (S.status.paused) { toast("TRANSMISSION IS ON HOLD."); return; }
        if (d.confidence) return confirmConfidence(d, i, submit);
        for (const k of keys.querySelectorAll(".key")) k.disabled = true;
        btn.classList.add("pressed");
        submit(i, false);
      }, caps[i]);
    });
  }
  // Confidence wager (Real or Mildew?): NORMAL or I'M CERTAIN (double points if right).
  function confirmConfidence(d, i, submit) {
    clear();
    const caps = ["A", "B", "C", "D"];
    lcd.appendChild(el("div", "sub", d.header || "CONFIDENCE ROUND"));
    lcd.appendChild(el("div", "title", "YOU CHOSE " + caps[i]));
    lcd.appendChild(el("div", "sub", String(d.options[i] || "").toUpperCase()));
    lcd.appendChild(el("div", "big", "HOW SURE ARE YOU?"));
    lcd.appendChild(el("div", "sub", "CERTAIN AND RIGHT: DOUBLE POINTS. CERTAIN AND WRONG: GRAHAM WILL REMEMBER."));
    key("I'M CERTAIN", "go plain", (b) => { b.classList.add("pressed"); submit(i, true); });
    key("NORMAL", "ok plain", (b) => { b.classList.add("pressed"); submit(i, false); });
    key("CHANGE MY ANSWER", "grey plain small", () => scrQuestion(d));
  }

  // ---------------- SURVEY / MOUTHFEEL (write, then vote) ----------------
  // The draft is kept per question in local storage so a reconnect or reload doesn't lose it,
  // and the screen is not rebuilt while typing when the server re-sends the same write screen.
  function wvTimer(d) {
    const bar = el("div", "timer"); const fill = el("div"); bar.appendChild(fill); lcd.appendChild(bar);
    const secs = el("div", "sub"); lcd.appendChild(secs);
    const total = Math.max(1, d.total_ms || d.remaining_ms || 30000), end = performance.now() + (d.remaining_ms || 0);
    const tick = () => {
      const left = Math.max(0, end - performance.now());
      fill.style.transform = "scaleX(" + Math.min(1, left / total).toFixed(3) + ")";
      secs.textContent = Math.ceil(left / 1000) + " SECONDS";
      if (left > 0) S.timerRAF = requestAnimationFrame(tick);
    };
    tick();
  }
  function scrWVWrite(d) {
    const wkey = "draft.wv." + d.qid + "." + (d.chain ? String(d.prompt || "").length : 0);
    if (S.wvKey === wkey && document.getElementById("wv-text")) return; // same screen re-sent: keep typing
    clear();
    S.wvKey = wkey;
    buzz([30, 40, 30]);
    if (d.header) lcd.appendChild(el("div", "sub", d.header));
    if (d.category) lcd.appendChild(el("div", "sub warn", "VOTE CATEGORY: " + d.category));
    lcd.appendChild(el("div", "prompt", d.prompt));
    if (d.hint) lcd.appendChild(el("div", "sub", d.hint));
    wvTimer(d);
    const ta = el("textarea", "wv-text"); ta.id = "wv-text";
    ta.maxLength = d.max || 80; ta.rows = 3; ta.autocapitalize = "sentences"; ta.spellcheck = false;
    ta.placeholder = d.chain ? "...AND THEN" : "TYPE YOUR ANSWER";
    ta.value = store.get(wkey);
    const count = el("div", "sub count");
    const upd = () => { count.textContent = ta.value.length + " / " + ta.maxLength; store.set(wkey, ta.value); };
    ta.addEventListener("input", upd);
    upd();
    keys.appendChild(ta); keys.appendChild(count);
    const b = key(d.chain ? "MAKE IT WORSE" : "SUBMIT", "go plain", (btn) => {
      const v = ta.value.trim();
      if (!v) { toast("WRITE SOMETHING FIRST."); return; }
      if (S.status.paused) { toast("TRANSMISSION IS ON HOLD."); return; }
      if (send({ t: "submit", q: d.qid, text: v })) { btn.disabled = true; btn.classList.add("pressed"); store.del(wkey); }
      else toast("NOT CONNECTED. YOUR ANSWER IS SAVED; TRY AGAIN IN A MOMENT.");
    });
    b.id = "wv-submit";
    setTimeout(() => { try { ta.focus(); } catch (e) { /* ignore */ } }, 60);
  }
  function scrWVWait(d) {
    clear(); S.wvKey = "";
    if (d.header) lcd.appendChild(el("div", "sub", d.header));
    lcd.appendChild(el("div", "spacer"));
    if (d.mine) { lcd.appendChild(el("div", "sub", "YOU WROTE")); lcd.appendChild(el("div", "title", "\u201c" + d.mine + "\u201d")); }
    lcd.appendChild(el("div", "sub blinker", d.caption || "WAITING"));
  }
  function scrWVVote(d) {
    clear(); S.wvKey = "";
    buzz([30, 40, 30]);
    if (d.header) lcd.appendChild(el("div", "sub", d.header));
    lcd.appendChild(el("div", "title", d.ask || "VOTE"));
    wvTimer(d);
    (d.options || []).forEach((opt, i) => {
      const mine = i === d.own;
      const b = key(mine ? opt + "  (YOURS)" : opt, "plain long " + (mine ? "grey" : ["a", "b", "c", "d"][i % 4]), (btn) => {
        if (S.status.paused) { toast("TRANSMISSION IS ON HOLD."); return; }
        for (const k of keys.querySelectorAll(".key")) k.disabled = true;
        btn.classList.add("pressed");
        send({ t: "vote", q: d.qid, c: i });
      });
      if (mine) b.disabled = true;
    });
  }
  function scrWVRate(d) {
    clear(); S.wvKey = "";
    buzz([30, 40, 30]);
    if (d.header) lcd.appendChild(el("div", "sub", d.header));
    lcd.appendChild(el("div", "sub", "LOOK WHAT YOU'VE ALL MADE"));
    lcd.appendChild(el("div", "prompt", d.text));
    wvTimer(d);
    lcd.appendChild(el("div", "title", "RATE IT. 1 = SAD. 5 = UNSPEAKABLE."));
    const row = el("div", "keyrow"); keys.appendChild(row);
    for (let i = 1; i <= 5; i++) {
      const b = el("button", "key plain " + (i >= 4 ? "go" : "grey"), String(i));
      b.addEventListener("click", (ev) => {
        ev.preventDefault(); if (b.disabled) return; buzz(15);
        for (const k of keys.querySelectorAll(".key")) k.disabled = true;
        b.classList.add("pressed"); send({ t: "vote", q: d.qid, c: i });
      });
      row.appendChild(b);
    }
  }
  function scrWVResult(d) {
    clear(); S.wvKey = "";
    if (d.header) lcd.appendChild(el("div", "sub", d.header));
    if (d.points > 0) { buzz([20, 30, 60]); lcd.appendChild(el("div", "huge", "+" + fmt(d.points))); }
    else lcd.appendChild(el("div", "big", "NO POINTS"));
    if (d.mine) lcd.appendChild(el("div", "title", "\u201c" + d.mine + "\u201d"));
    if (d.votes !== undefined && d.mine) lcd.appendChild(el("div", "sub", d.votes + " VOTE" + (d.votes === 1 ? "" : "S")));
    lcd.appendChild(el("div", "spacer"));
    lcd.appendChild(el("div", "sub", "YOUR SCORE: " + fmt(d.score)));
  }

  // ---------------- HOLE ----------------
  const fmt = (n) => Number(n || 0).toLocaleString("en-GB");
  function holeTimer(d) {
    const bar = el("div", "timer"); const fill = el("div"); bar.appendChild(fill); lcd.appendChild(bar);
    const total = Math.max(1, d.total_ms || 8000), end = performance.now() + (d.remaining_ms || 0);
    const tick = () => {
      const left = Math.max(0, end - performance.now());
      fill.style.transform = "scaleX(" + (left / total).toFixed(3) + ")";
      if (left > 0) S.timerRAF = requestAnimationFrame(tick);
    };
    tick();
  }
  function scrHolePick(d) {
    clear();
    const look = d.safety_net ? "MULTIPLE CHOICE" : "LOOK " + d.stage + " OF " + (d.final_stage === 4 ? 3 : d.final_stage);
    lcd.appendChild(el("div", "sub", (d.header || "HOLE") + " · " + look));
    lcd.appendChild(el("div", "title", d.prompt || "WHAT IS THIS HOLE?"));
    lcd.appendChild(el("div", "big", "LOCK NOW: " + fmt(d.points) + " PTS"));
    holeTimer(d);
    if (d.can_pass) lcd.appendChild(el("div", "sub", "WAIT FOR A WIDER LOOK AND IT'S WORTH " + fmt(d.next_points) + ". ONCE LOCKED, IT'S LOCKED."));
    const lock = (i) => {
      if (S.status.paused) { toast("TRANSMISSION IS ON HOLD."); return; }
      for (const k of keys.querySelectorAll(".key")) k.disabled = true;
      send({ t: "lock", q: d.qid, s: d.stage, c: i });
      S.holeConfirm = null;
    };
    if (d.safety_net) {
      buzz([30, 40, 30]);
      const caps = ["A", "B", "C", "D"], cls = ["a", "b", "c", "d"];
      (d.options || []).forEach((opt, i) => key(opt, cls[i], (btn) => { btn.classList.add("pressed"); lock(i); }, caps[i]));
      return;
    }
    if (d.stage === 1) buzz([30, 40, 30]); else buzz(20);
    // Pending confirmation survives a reveal advancing underneath it (points update).
    const pend = S.holeConfirm;
    if (pend && pend.qid === d.qid && (d.options || []).indexOf(pend.label) >= 0) return holeConfirm(d, pend.label, lock);
    const grid = el("div", "keygrid"); keys.appendChild(grid);
    (d.options || []).forEach((opt) => {
      const b = el("button", "key small plain grey");
      b.textContent = opt;
      b.addEventListener("click", (ev) => { ev.preventDefault(); buzz(15); S.holeConfirm = { qid: d.qid, label: opt }; holeConfirm(d, opt, lock); });
      grid.appendChild(b);
    });
    if (d.can_pass) key("SHOW ME MORE", "plain", (b) => { b.disabled = true; send({ t: "pass", q: d.qid, s: d.stage }); }).classList.add("d");
  }
  function holeConfirm(d, label, lock) {
    clear();
    lcd.appendChild(el("div", "sub", (d.header || "HOLE") + " · LOOK " + d.stage));
    lcd.appendChild(el("div", "title", "LOCK IN"));
    lcd.appendChild(el("div", "big", label.toUpperCase()));
    lcd.appendChild(el("div", "title", "FOR " + fmt(d.points) + " PTS?"));
    holeTimer(d);
    lcd.appendChild(el("div", "sub warn", "NO TAKE-BACKS."));
    key("YES — LOCK IT IN", "go plain", (b) => { b.classList.add("pressed"); lock((d.options || []).indexOf(label)); });
    key("NO, GO BACK", "grey plain small", () => { S.holeConfirm = null; scrHolePick(d); });
  }
  function scrHoleLocked(d) {
    clear();
    S.holeConfirm = null;
    lcd.appendChild(el("div", "sub", (d.header || "HOLE") + " · LOCKED AT " + (d.stage >= 4 ? "MULTIPLE CHOICE" : "LOOK " + d.stage)));
    lcd.appendChild(el("div", "big", String(d.label || "").toUpperCase()));
    lcd.appendChild(el("div", "title", "WORTH " + fmt(d.points) + " IF YOU'RE RIGHT"));
    lcd.appendChild(el("div", "spacer"));
    lcd.appendChild(el("div", "sub blinker", "NO TAKE-BACKS. WATCH THE TELEVISION"));
  }
  function scrHoleResult(d) {
    clear();
    const where = d.stage ? (d.stage >= 4 ? "MULTIPLE CHOICE" : "LOOK " + d.stage) : "";
    if (d.correct) {
      buzz([20, 30, 60]);
      lcd.appendChild(el("div", "huge", "CORRECT"));
      lcd.appendChild(el("div", "big", "+" + fmt(d.points)));
      lcd.appendChild(el("div", "sub", "LOCKED AT " + where));
    } else if (d.partial) {
      buzz([20, 60]);
      lcd.appendChild(el("div", "big warn", "RIGHT SORT OF THING"));
      lcd.appendChild(el("div", "big", "+" + fmt(d.points)));
      lcd.appendChild(el("div", "title", "IT WAS: " + String(d.answer || "").toUpperCase()));
    } else {
      buzz(200);
      lcd.appendChild(el("div", "huge warn", d.label ? "WRONG" : "NOTHING"));
      lcd.appendChild(el("div", "title", "IT WAS: " + String(d.answer || "").toUpperCase()));
      if (d.label) lcd.appendChild(el("div", "sub", "YOU SAID: " + String(d.label).toUpperCase() + " (" + where + ")"));
    }
    lcd.appendChild(el("div", "spacer"));
    lcd.appendChild(el("div", "sub", "YOUR SCORE: " + fmt(d.score)));
  }

  function scrLocked(d) {
    clear();
    if (d.choice >= 0) {
      lcd.appendChild(el("div", "sub", (d.header ? d.header + " · " : "") + "ANSWER LOCKED"));
      lcd.appendChild(el("div", "huge", ["A", "B", "C", "D"][d.choice] || "?"));
      lcd.appendChild(el("div", d.text && d.text.length > 40 ? "sub" : "title", (d.text || "").toUpperCase()));
      if (d.certain) lcd.appendChild(el("div", "big warn", "YOU SAID: CERTAIN"));
    } else {
      lcd.appendChild(el("div", "sub", "ANSWERS CLOSED"));
      lcd.appendChild(el("div", "big warn", "NO ANSWER RECEIVED"));
    }
    lcd.appendChild(el("div", "spacer"));
    lcd.appendChild(el("div", "sub blinker", "AWAITING VERDICT"));
  }

  function scrResult(d) {
    clear();
    if (d.correct) {
      buzz([20, 30, 60]);
      lcd.appendChild(el("div", "huge", "CORRECT"));
      lcd.appendChild(el("div", "big", "+" + Number(d.points).toLocaleString("en-GB")));
      if (d.certain) lcd.appendChild(el("div", "title", "CERTAIN, AND RIGHT. DOUBLED."));
    } else {
      buzz(200);
      lcd.appendChild(el("div", "huge warn", d.answered ? "WRONG" : "NOTHING"));
      if (d.certain) lcd.appendChild(el("div", "title warn", "AND YOU WERE CERTAIN."));
      const at = String(d.answer_text || "");
      lcd.appendChild(el("div", at.length > 40 ? "sub" : "title", "IT WAS: " + at.toUpperCase()));
    }
    lcd.appendChild(el("div", "spacer"));
    lcd.appendChild(el("div", "sub", "YOUR SCORE: " + Number(d.score || 0).toLocaleString("en-GB")));
  }

  function scrScores(d) {
    clear();
    lcd.appendChild(el("div", "sub", "CURRENT STANDINGS"));
    lcd.appendChild(el("div", "huge", ordinal(d.rank)));
    lcd.appendChild(el("div", "title", "OF " + d.of + " CONTESTANTS"));
    lcd.appendChild(el("div", "big", Number(d.score || 0).toLocaleString("en-GB") + " PTS"));
  }

  function scrEnded(d) {
    clear();
    lcd.appendChild(el("div", "sub", "END OF TRANSMISSION"));
    lcd.appendChild(el("div", "big", "THANK YOU FOR WATCHING"));
    if (d.rank) lcd.appendChild(el("div", "title", "YOU FINISHED " + ordinal(d.rank) + " · " + Number(d.score || 0).toLocaleString("en-GB") + " PTS"));
    lcd.appendChild(el("div", "spacer"));
    if (d.captain) key("ANOTHER BROADCAST", "go plain", () => send({ t: "play_again" }));
    else lcd.appendChild(el("div", "sub blinker", "THE FLOOR CAPTAIN DECIDES WHAT HAPPENS NEXT"));
    key("LEAVE THE STUDIO", "grey plain small", () => send({ t: "leave" }));
  }

  function scrClosed() {
    S.ended = true; store.del(tokenKey());
    clear();
    lcd.appendChild(el("div", "big", "TRANSMISSION ENDED"));
    lcd.appendChild(el("div", "sub", "THE PROGRAMME HAS FINISHED ON YOUR TELEVISION. TO JOIN A NEW BROADCAST, SCAN THE NEW CODE."));
    key("ENTER A NEW CODE", "grey plain", () => { S.ended = false; S.key = ""; S.room = ""; showCodeEntry(); });
  }

  function showKicked() {
    clear();
    lcd.appendChild(el("div", "big warn", "THIS UNIT HAS BEEN SUPERSEDED"));
    lcd.appendChild(el("div", "sub", "YOUR CONTESTANT WAS OPENED ON ANOTHER DEVICE OR TAB."));
    key("USE THIS DEVICE INSTEAD", "grey plain", () => { S.kicked = false; S.retry = 0; connect(); });
  }

  function renderStatus() {
    const s = S.status;
    if (!S.connected) return; // the network banner has priority
    if (!s.paused) { sysbar(null); return; }
    if (s.reason === "manual") sysbar("hold", "TRANSMISSION PAUSED", "Paused on the television. Nothing is lost.");
    else if (s.reason === "reconnect") {
      const lost = (s.detail && s.detail.lost) || [];
      const names = lost.map((l) => l.name).join(", ") || "a contestant";
      const secs = lost.length ? Math.ceil(Math.max(...lost.map((l) => l.remaining))) : 30;
      sysbar("hold", "WAITING FOR " + names.toUpperCase() + " TO RECONNECT", "Up to " + secs + " seconds. The programme resumes automatically.");
      countdownStatus(secs, names);
    } else if (s.reason === "players") sysbar("hold", "WAITING FOR MORE CONTESTANTS", "At least two contestants are needed. New players can join now.");
  }
  let statusTimer = 0;
  function countdownStatus(secs, names) {
    clearInterval(statusTimer);
    let left = secs;
    statusTimer = setInterval(() => {
      left--;
      if (!S.status.paused || S.status.reason !== "reconnect" || left < 0) { clearInterval(statusTimer); return; }
      $("sys-detail").textContent = "Up to " + left + " seconds. The programme resumes automatically.";
    }, 1000);
  }

  // ---------------- avatar drawing (shared parts table with the TV) ----------------
  const DEFAULT_PARTS = {
    hair: ["SIDE PARTING", "CURTAINS", "MULLET", "BALDING", "PERM", "BOB"],
    hair_colour: [["MOUSE", "#7a5a3a"], ["JET", "#1e1b1b"], ["GINGER", "#b8572a"], ["PLATINUM", "#e6d79a"], ["GREY", "#9b9a95"], ["AUBERGINE", "#5c2442"]],
    skin: ["#f1c9a4", "#dfab7d", "#c48a5a", "#8c593a", "#5b3925"],
    glasses: ["NONE", "BIG GOLD FRAMES", "TINTED"],
    outfit: [["TEAL SHELL SUIT", "#1f8a8a", "#e0457b"], ["BURGUNDY BLAZER", "#6b1f2e", "#d9b24c"], ["MUSTARD KNIT", "#c79a2b", "#6a4a1a"], ["PURPLE BOMBER", "#4b2a7a", "#2ec4b6"],
      ["DOUBLE DENIM", "#3b5f8a", "#9fb8d8"], ["NICOTINE CARDIGAN", "#b9a77a", "#5e5340"], ["MILDEW GREEN", "#4d6b3a", "#c8d96f"], ["LOUD SHIRT", "#e04f2f", "#f4d03f"]],
    accessory: ["NOTHING", "BOW TIE", "EARRING", "MOUSTACHE", "MEDAL", "SCRUNCHIE"],
  };
  function randomAvatar() {
    const r = (n) => Math.floor(Math.random() * n);
    return { hair: r(6), hair_colour: r(6), skin: r(5), glasses: r(3), outfit: r(8), accessory: r(6) };
  }
  // Mirrors src/broadcast/avatar_painter.gd (normalised 0..1 coordinates).
  function drawAvatar(cv, a) {
    const P = S.avatarParts || DEFAULT_PARTS;
    const g = cv.getContext("2d"), W = cv.width, H = cv.height;
    const X = (v) => v * W, Y = (v) => v * H;
    const pick = (arr, i) => arr[Math.max(0, Math.min(arr.length - 1, i | 0))];
    const skin = pick(P.skin, a.skin), hairC = pick(P.hair_colour, a.hair_colour)[1];
    const out = pick(P.outfit, a.outfit);
    const bg = g.createLinearGradient(0, 0, 0, H); bg.addColorStop(0, "#23305e"); bg.addColorStop(1, "#0b1030");
    g.fillStyle = bg; g.fillRect(0, 0, W, H);
    g.fillStyle = "rgba(255,255,255,.05)"; for (let y = 0; y < H; y += 4) g.fillRect(0, y, W, 1);
    // shoulders
    g.fillStyle = out[1];
    g.beginPath(); g.moveTo(X(.08), Y(1)); g.lineTo(X(.16), Y(.78)); g.quadraticCurveTo(X(.5), Y(.66), X(.84), Y(.78)); g.lineTo(X(.92), Y(1)); g.fill();
    g.fillStyle = out[2];
    g.beginPath(); g.moveTo(X(.40), Y(.74)); g.lineTo(X(.5), Y(.90)); g.lineTo(X(.60), Y(.74)); g.fill();
    if (a.outfit === 7) { g.fillStyle = "rgba(0,0,0,.18)"; for (let i = 0; i < 6; i++) g.fillRect(X(.16 + i * .13), Y(.8), X(.05), Y(.2)); }
    // neck + head
    g.fillStyle = skin; g.fillRect(X(.44), Y(.6), X(.12), Y(.14));
    g.beginPath(); g.ellipse(X(.5), Y(.45), X(.17), Y(.21), 0, 0, Math.PI * 2); g.fill();
    g.beginPath(); g.ellipse(X(.33), Y(.47), X(.03), Y(.05), 0, 0, Math.PI * 2); g.ellipse(X(.67), Y(.47), X(.03), Y(.05), 0, 0, Math.PI * 2); g.fill();
    // hair
    g.fillStyle = hairC;
    const hair = a.hair | 0;
    g.beginPath();
    if (hair === 0) { g.ellipse(X(.5), Y(.30), X(.18), Y(.10), 0, Math.PI, 0); g.fill(); g.beginPath(); g.ellipse(X(.42), Y(.27), X(.12), Y(.06), -0.3, 0, Math.PI * 2); }
    else if (hair === 1) { g.ellipse(X(.38), Y(.33), X(.10), Y(.12), 0.5, 0, Math.PI * 2); g.ellipse(X(.62), Y(.33), X(.10), Y(.12), -0.5, 0, Math.PI * 2); }
    else if (hair === 2) { g.ellipse(X(.5), Y(.30), X(.18), Y(.10), 0, Math.PI, 0); g.rect(X(.31), Y(.30), X(.06), Y(.30)); g.rect(X(.63), Y(.30), X(.06), Y(.30)); }
    else if (hair === 3) { g.ellipse(X(.33), Y(.38), X(.04), Y(.07), 0, 0, Math.PI * 2); g.ellipse(X(.67), Y(.38), X(.04), Y(.07), 0, 0, Math.PI * 2); }
    else if (hair === 4) { for (let i = 0; i < 9; i++) { const ang = Math.PI + i * Math.PI / 8; g.moveTo(X(.5 + .17 * Math.cos(ang)), Y(.33 + .12 * Math.sin(ang))); g.arc(X(.5 + .17 * Math.cos(ang)), Y(.33 + .12 * Math.sin(ang)), X(.06), 0, Math.PI * 2); } }
    else { g.ellipse(X(.5), Y(.32), X(.20), Y(.13), 0, Math.PI, 0); g.rect(X(.30), Y(.32), X(.07), Y(.24)); g.rect(X(.63), Y(.32), X(.07), Y(.24)); }
    g.fill();
    // face
    g.fillStyle = "#1a1410";
    g.beginPath(); g.arc(X(.44), Y(.45), X(.016), 0, Math.PI * 2); g.arc(X(.56), Y(.45), X(.016), 0, Math.PI * 2); g.fill();
    g.strokeStyle = "#5a2a22"; g.lineWidth = Math.max(1, W * .012);
    g.beginPath(); g.arc(X(.5), Y(.52), X(.06), 0.15 * Math.PI, 0.85 * Math.PI); g.stroke();
    // glasses
    if (a.glasses === 1 || a.glasses === 2) {
      g.strokeStyle = a.glasses === 1 ? "#d8b44a" : "#222"; g.lineWidth = Math.max(1, W * .014);
      g.fillStyle = a.glasses === 2 ? "rgba(60,30,80,.55)" : "rgba(255,255,255,.08)";
      for (const cx of [.43, .57]) { g.beginPath(); g.rect(X(cx - .055), Y(.415), X(.11), Y(.075)); g.fill(); g.stroke(); }
      g.beginPath(); g.moveTo(X(.485), Y(.45)); g.lineTo(X(.515), Y(.45)); g.stroke();
    }
    // accessory
    const acc = a.accessory | 0;
    if (acc === 1) { g.fillStyle = "#c21f3a"; g.beginPath(); g.moveTo(X(.5), Y(.76)); g.lineTo(X(.42), Y(.72)); g.lineTo(X(.42), Y(.80)); g.closePath(); g.moveTo(X(.5), Y(.76)); g.lineTo(X(.58), Y(.72)); g.lineTo(X(.58), Y(.80)); g.closePath(); g.fill(); }
    if (acc === 2) { g.fillStyle = "#e8c547"; g.beginPath(); g.arc(X(.33), Y(.53), X(.018), 0, Math.PI * 2); g.fill(); }
    if (acc === 3) { g.fillStyle = hairC; g.beginPath(); g.ellipse(X(.5), Y(.505), X(.07), Y(.018), 0, 0, Math.PI * 2); g.fill(); }
    if (acc === 4) { g.fillStyle = "#2a5bd7"; g.fillRect(X(.62), Y(.80), X(.05), Y(.07)); g.fillStyle = "#e8c547"; g.beginPath(); g.arc(X(.645), Y(.90), X(.035), 0, Math.PI * 2); g.fill(); }
    if (acc === 5) { g.fillStyle = "#ff4fa3"; g.beginPath(); g.ellipse(X(.5), Y(.235), X(.06), Y(.025), 0, 0, Math.PI * 2); g.fill(); }
  }

  // ---------------- boot ----------------
  fetch("/api/avatar").then((r) => r.json()).then((j) => { S.avatarParts = j; }).catch(() => { /* defaults */ });
  if (S.key || S.room) { showMessage("ESTABLISHING CONNECTION", "PLEASE HOLD."); connect(); }
  else showCodeEntry();
})();
