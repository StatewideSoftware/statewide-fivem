import { holdProgress, isTrusted, money, phoneOrigin, pushOf, resourceOf, toneOf, words } from "./phone.js";

const RESOURCE = resourceOf(location.hostname) ?? "statewide";
const CIV_TABS = [
  ["characters", "Characters"],
  ["vehicles", "Vehicles"],
  ["licenses", "Licenses"],
  ["tickets", "Tickets"],
  ["my911", "911"],
];
const DUTY_TABS = [
  ["call", "My call"],
  ["status", "Status"],
  ["panic", "Panic"],
  ["run", "Run"],
];
const KIND_WORDS = { error: "Error", success: "Done", alert: "Alert", info: "Note" };
const SPACING_MS = 550;
const URGENT = new Set(["panic"]);
const REFETCH_MS = 250;

const main = document.getElementById("main");
const tabs = document.getElementById("tabs");
const mode = document.getElementById("mode");
const live = document.getElementById("live");
const title = document.getElementById("title");

const state = { mode: "civ", tab: "characters", me: null, profile: null, profileSsn: null, codes: null, render: 0 };
let lbOrigin = null;
const early = [];

function h(tag, attrs, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs ?? {})) {
    if (value === null || value === undefined || value === false) continue;
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value === true ? "" : String(value));
  }
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return node;
}

function failure(text) {
  return { ok: false, messages: [{ text: text ?? "No answer from the server. Try again in a moment.", kind: "error" }] };
}

async function nui(name, body) {
  const res = await fetch(`https://${RESOURCE}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(body ?? {}),
  });
  return res.json();
}

let queue = Promise.resolve();
let lastAt = -Infinity;

async function send(action, args) {
  try {
    const result = await nui("phone", args ? { action, args } : { action });
    return result && typeof result === "object" ? result : failure();
  } catch {
    return failure();
  }
}

function ask(action, args) {
  if (URGENT.has(action)) return send(action, args);
  const run = async () => {
    const wait = lastAt + SPACING_MS - performance.now();
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
    lastAt = performance.now();
    return send(action, args);
  };
  const next = queue.then(run, run);
  queue = next.catch(() => {});
  return next;
}

function alerts(messages) {
  return (messages ?? []).map((m) => h("p", { class: `alert ${m.kind === "alert" ? "alert-kind" : m.kind ?? "info"}`, role: m.kind === "error" ? "alert" : null }, h("b", null, KIND_WORDS[m.kind] ?? "Note"), " ", m.text));
}

function badge(state, label) {
  return h("span", { class: `badge ${toneOf(state)}` }, label ?? words(state));
}

function facts(pairs) {
  const rows = pairs.filter(([, value]) => value !== null && value !== undefined && value !== "");
  if (rows.length === 0) return null;
  return h("dl", { class: "facts" }, rows.map(([label, value]) => [h("dt", null, label), h("dd", null, value)]));
}

function empty(text, action) {
  return h("div", { class: "empty" }, h("p", null, text), action ?? null);
}

function setTab(tab) {
  state.tab = tab;
  render();
}

function loading(what) {
  main.replaceChildren(h("div", { class: "skeleton" }), h("div", { class: "skeleton" }), h("p", { class: "sr", role: "status" }, `Loading ${what}`));
  main.setAttribute("aria-busy", "true");
}

function show(...nodes) {
  main.removeAttribute("aria-busy");
  main.replaceChildren(...nodes.flat(Infinity).filter(Boolean));
}

function errorState(result, retry) {
  show(alerts(result.messages), h("button", { type: "button", class: "btn", onclick: retry }, "Retry"));
}

let flight = null;

function load(what, action, args, draw, fresh = false) {
  const key = JSON.stringify([action, args ?? null]);
  const ticket = state.render;
  if (flight && flight.key === key) {
    Object.assign(flight, { ticket, what, draw });
    if (fresh) flight.again = true;
    else loading(what);
    return flight.done;
  }
  if (!fresh) loading(what);
  const f = { key, ticket, what, draw, again: false };
  flight = f;
  f.done = ask(action, args).then((result) => {
    if (flight === f) flight = null;
    if (f.ticket !== state.render) return;
    if (!result.ok) return errorState(result, () => load(f.what, action, args, f.draw));
    show(f.draw(result.data, result));
    if (f.again) return load(f.what, action, args, f.draw, true);
  });
  return f.done;
}

const soon = { at: 0, tab: null, timer: false };

function due() {
  const wait = soon.at - performance.now();
  if (wait > 0) {
    setTimeout(due, wait);
    return;
  }
  soon.timer = false;
  const view = soon.tab === state.tab ? REFETCH[state.tab] : null;
  soon.tab = null;
  if (view) view();
}

function refetch() {
  soon.at = performance.now() + REFETCH_MS;
  soon.tab = state.tab;
  if (soon.timer) return;
  soon.timer = true;
  setTimeout(due, REFETCH_MS);
}

function activeSsn() {
  return state.me?.character?.ssn ?? null;
}

function noCharacter() {
  return empty("No active character.", h("button", { type: "button", class: "btn primary", onclick: () => setTab("characters") }, "Choose character"));
}

async function refreshMe() {
  const result = await ask("me");
  if (result.ok && result.data) state.me = result.data;
  syncMode();
}

async function setActive(ssn) {
  const ticket = ++state.render;
  loading("your characters");
  const result = await ask("setActive", { ssn });
  state.profile = null;
  state.profileSsn = null;
  await refreshMe();
  if (ticket !== state.render) return;
  await drawCharacters(result.messages);
}

async function drawCharacters(notice) {
  await load("your characters", "characters", null, (list) => {
    const cards = (list ?? []).map((c) =>
      h(
        "article",
        { class: "card" },
        h("div", { class: "row" }, h("h2", { class: "name" }, c.name), c.active ? badge("active", "Active") : null),
        facts([
          ["Born", c.dob],
          ["SSN", c.ssn],
        ]),
        c.active ? null : h("button", { type: "button", class: "btn", onclick: () => setActive(c.ssn) }, "Set active"),
      ),
    );
    return [alerts(notice), cards.length ? cards : empty("No characters yet. Create one on the community website.")];
  });
}

async function withProfile(what, draw) {
  const ssn = activeSsn();
  if (!ssn) return show(noCharacter());
  if (state.profile && state.profileSsn === ssn) return show(draw(state.profile));
  await load(what, "profile", { ssn }, (profile) => {
    state.profile = profile;
    state.profileSsn = ssn;
    return draw(profile);
  });
}

function drawVehicles(profile) {
  const cards = (profile.vehicles ?? []).map((v) =>
    h(
      "article",
      { class: "card" },
      h("div", { class: "row" }, h("h2", { class: "name" }, [v.color, v.make, v.model].filter(Boolean).join(" ") || "Vehicle"), h("span", { class: "id" }, v.plate)),
      h("div", { class: "badges" }, v.registration ? badge(v.registration, `Registration ${words(v.registration).toLowerCase()}`) : null, v.insurance ? badge(v.insurance, words(v.insurance)) : null, v.stolen ? badge("stolen", "Stolen") : null),
    ),
  );
  return cards.length ? cards : empty(`No vehicles registered to ${profile.character.name}.`);
}

function drawLicenses(profile) {
  const cards = (profile.licenses ?? []).map((l) =>
    h(
      "article",
      { class: "card" },
      h("div", { class: "row" }, h("h2", { class: "name" }, l.name), l.status ? badge(l.status) : null),
      facts([
        ["Number", l.number],
        ["Expires", l.expiresOn],
        ["Points", String(l.points ?? 0)],
      ]),
    ),
  );
  return cards.length ? cards : empty(`${profile.character.name} holds no licenses.`);
}

function drawTickets(profile) {
  const cards = (profile.citations ?? []).map((t) =>
    h(
      "article",
      { class: "card" },
      h("div", { class: "row" }, h("h2", { class: "name" }, money(t.fine)), h("span", { class: "id" }, t.number)),
      t.caseStatus ? h("div", { class: "badges" }, badge(t.caseStatus, `Case ${words(t.caseStatus).toLowerCase()}`)) : null,
      facts([
        ["Issued", t.date],
        ["Points", String(t.points ?? 0)],
        ["Court date", t.courtDate],
        ["Court", t.courtLocation],
        ["Plea", t.plea ? words(t.plea) : null],
      ]),
    ),
  );
  return cards.length ? cards : empty(`No tickets for ${profile.character.name}.`);
}

function drawMy911(fresh = false) {
  return load("your 911 calls", "my911", null, (calls) => {
    const cards = (calls ?? []).map((c) =>
      h(
        "article",
        { class: "card" },
        h("div", { class: "row" }, h("h2", { class: "name id" }, c.number), badge(c.status === "pending" ? "pending" : c.status, c.status === "pending" ? "Waiting" : words(c.status))),
        h("p", { class: "sub" }, c.units === 1 ? "1 unit responding" : `${c.units} units responding`),
      ),
    );
    return cards.length ? cards : empty("No open 911 calls.");
  }, fresh);
}

function callView(call) {
  if (!call) return empty("No call attached.", h("button", { type: "button", class: "btn", onclick: () => setTab("status") }, "Set status"));
  return h(
    "article",
    { class: "card" },
    h("div", { class: "row" }, h("h2", { class: "name" }, call.nature || "Call"), h("span", { class: "id" }, call.number)),
    facts([
      ["Location", call.location],
      ["Postal", call.postal],
      ["Priority", call.priority ? String(call.priority) : null],
    ]),
    call.notes?.length
      ? h("ul", { class: "notes", "aria-label": "Notes" }, call.notes.map((n) => h("li", null, h("span", { class: "sub" }, [n.author, n.at ? n.at.slice(11, 16) : null].filter(Boolean).join(" · ")), n.body)))
      : null,
  );
}

function drawCall(fresh = false) {
  return load("your call", "call", null, callView, fresh);
}

function statusView(codes, notice) {
  const current = state.me?.unit?.status;
  const buttons = (codes ?? []).map((c) =>
    h("button", { type: "button", class: "btn", "aria-pressed": c.code === current ? "true" : "false", onclick: () => setStatus(c.code) }, `${c.code} ${c.label !== c.code ? c.label : ""}`.trim()),
  );
  return [alerts(notice), buttons.length ? h("div", { class: "grid", role: "group", "aria-label": "Status" }, buttons) : empty("No status codes for your department.")];
}

function drawStatus(notice) {
  if (state.codes) return show(statusView(state.codes, notice));
  return load("status codes", "statusCodes", null, (codes) => {
    state.codes = codes ?? [];
    return statusView(state.codes, notice);
  });
}

async function setStatus(code) {
  const result = await ask("status", { code });
  if (result.ok && state.me?.unit) state.me.unit.status = code;
  if (state.tab === "status") drawStatus(result.messages);
}

function drawPanic() {
  const fill = h("span", { class: "fill", "aria-hidden": "true" });
  const label = h("span", { class: "label" }, "Hold for panic");
  const button = h("button", { type: "button", class: "panic" }, fill, label);
  const out = h("div", { class: "form" });
  let started = null;
  let frame = 0;
  const stop = () => {
    started = null;
    cancelAnimationFrame(frame);
    button.classList.remove("holding");
    button.style.setProperty("--hold", "0");
  };
  const tick = () => {
    if (started === null) return;
    const p = holdProgress(started, performance.now());
    button.style.setProperty("--hold", String(p));
    if (p < 1) {
      frame = requestAnimationFrame(tick);
      return;
    }
    stop();
    label.textContent = "Sending panic";
    ask("panic").then((result) => {
      label.textContent = "Hold for panic";
      out.replaceChildren(...alerts(result.messages));
      live.textContent = result.messages?.[0]?.text ?? "";
    });
  };
  const start = (event) => {
    if (started !== null) return;
    if (event.type === "keydown" && event.key !== " " && event.key !== "Enter") return;
    event.preventDefault();
    started = performance.now();
    button.classList.add("holding");
    frame = requestAnimationFrame(tick);
  };
  button.addEventListener("pointerdown", start);
  button.addEventListener("keydown", start);
  for (const type of ["pointerup", "pointerleave", "pointercancel", "keyup", "blur"]) button.addEventListener(type, stop);
  show(button, out);
}

function drawRun() {
  const plateOut = h("div", { class: "form" });
  const nameOut = h("div", { class: "form" });
  const plate = h("input", { id: "run-plate", name: "plate", maxlength: "8", autocomplete: "off", autocapitalize: "characters", spellcheck: "false" });
  const first = h("input", { id: "run-first", name: "first", maxlength: "40", autocomplete: "off" });
  const last = h("input", { id: "run-last", name: "last", maxlength: "40", autocomplete: "off" });
  const submit = (form, action, args, out) => async (event) => {
    event.preventDefault();
    const button = form.querySelector("button");
    if (button.getAttribute("aria-disabled") === "true") return;
    button.setAttribute("aria-disabled", "true");
    const result = await ask(action, args());
    button.removeAttribute("aria-disabled");
    out.replaceChildren(...alerts(result.messages));
  };
  const plateForm = h("form", { class: "form card", "aria-labelledby": "run-plate-title" }, h("h2", { id: "run-plate-title", class: "section" }, "Plate"), h("label", { class: "field", for: "run-plate" }, "Plate", plate), h("button", { type: "submit", class: "btn primary" }, "Run plate"), plateOut);
  plateForm.addEventListener("submit", submit(plateForm, "plate", () => ({ plate: plate.value.trim() }), plateOut));
  const nameForm = h(
    "form",
    { class: "form card", "aria-labelledby": "run-name-title" },
    h("h2", { id: "run-name-title", class: "section" }, "Name"),
    h("div", { class: "pair" }, h("label", { class: "field", for: "run-first" }, "First name", first), h("label", { class: "field", for: "run-last" }, "Last name", last)),
    h("button", { type: "submit", class: "btn primary" }, "Run name"),
    nameOut,
  );
  nameForm.addEventListener("submit", submit(nameForm, "name", () => ({ first: first.value.trim(), last: last.value.trim() }), nameOut));
  show(plateForm, nameForm);
}

const REFETCH = {
  call: () => drawCall(true),
  my911: () => drawMy911(true),
  status: () => drawStatus(),
};

const VIEWS = {
  characters: () => drawCharacters(),
  vehicles: () => withProfile("your vehicles", drawVehicles),
  licenses: () => withProfile("your licenses", drawLicenses),
  tickets: () => withProfile("your tickets", drawTickets),
  my911: drawMy911,
  call: drawCall,
  status: () => drawStatus(),
  panic: drawPanic,
  run: drawRun,
};

function drawTabs() {
  const list = state.mode === "duty" ? DUTY_TABS : CIV_TABS;
  tabs.setAttribute("role", "tablist");
  tabs.replaceChildren(
    ...list.map(([key, label]) => h("button", { type: "button", role: "tab", "aria-selected": key === state.tab ? "true" : "false", "aria-controls": "main", onclick: () => setTab(key) }, label)),
  );
  const current = list.find(([key]) => key === state.tab);
  title.textContent = current ? current[1] : "Statewide";
}

function render() {
  state.render++;
  drawTabs();
  main.setAttribute("role", "tabpanel");
  VIEWS[state.tab]?.();
}

function syncMode() {
  const onDuty = state.me?.onDuty === true;
  mode.hidden = !onDuty;
  if (!onDuty && state.mode === "duty") {
    state.mode = "civ";
    state.tab = "characters";
    render();
  }
  for (const b of mode.querySelectorAll("button")) b.setAttribute("aria-selected", b.dataset.mode === state.mode ? "true" : "false");
}

mode.addEventListener("click", (event) => {
  const target = event.target.closest("button[data-mode]");
  if (!target || target.dataset.mode === state.mode) return;
  state.mode = target.dataset.mode === "duty" && state.me?.onDuty ? "duty" : "civ";
  state.tab = state.mode === "duty" ? "call" : "characters";
  syncMode();
  render();
});

function setTheme(theme) {
  if (theme === "light" || theme === "dark") document.documentElement.dataset.theme = theme;
}

function onComponents() {
  const settings = globalThis.getSettings;
  if (typeof settings === "function") Promise.resolve(settings()).then((s) => setTheme(s?.display?.theme)).catch(() => {});
  const change = globalThis.onSettingsChange;
  if (typeof change === "function") change((s) => setTheme(s?.display?.theme));
}

function onPush(push) {
  if (push.type === "unit") {
    const before = state.me?.unit ?? null;
    if (push.onDuty !== true || push.unit?.department !== before?.department) state.codes = null;
    state.me = { ...(state.me ?? {}), unit: push.unit ?? null, onDuty: push.onDuty === true };
    syncMode();
    if (state.tab === "call" && (push.unit?.callNumber ?? null) !== (before?.callNumber ?? null)) refetch();
    if (state.tab === "status" && (state.codes === null || push.unit?.status !== before?.status)) refetch();
    return;
  }
  if (push.type === "character") {
    state.profile = null;
    state.profileSsn = null;
    refreshMe().then(() => {
      if (state.mode === "civ") render();
    });
    return;
  }
  if (push.type === state.tab) refetch();
}

function handle(event) {
  if (!isTrusted(event, window, lbOrigin)) return;
  if (event.data === "componentsLoaded") return onComponents();
  const push = pushOf(event.data);
  if (push) onPush(push);
}

window.addEventListener("message", (event) => {
  if (lbOrigin === null && !(event.source === window && event.origin === location.origin)) {
    if (early.length < 20) early.push(event);
    return;
  }
  handle(event);
});

new MutationObserver(() => setTheme(document.body.dataset.theme)).observe(document.body, { attributes: true, attributeFilter: ["data-theme"] });
setTheme(document.body.dataset.theme);

async function boot() {
  render();
  try {
    const answer = await nui("phoneBoot");
    lbOrigin = phoneOrigin(answer?.lb);
  } catch {
    lbOrigin = null;
  }
  for (const event of early.splice(0)) handle(event);
  await refreshMe();
  render();
}

boot();
