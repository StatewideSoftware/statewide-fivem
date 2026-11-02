import { isGameMessage } from "./frame.js";

const resource = typeof window !== "undefined" && typeof window.GetParentResourceName === "function" ? window.GetParentResourceName() : "statewide";

export const SIGNATURE_MAX = 200;

export function money(n) {
  const v = Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : 0;
  return `$${v.toLocaleString("en-US")}`;
}

export function jailText(seconds) {
  const s = Number.isFinite(seconds) ? Math.max(0, Math.trunc(seconds)) : 0;
  if (s === 0) return "";
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return [h ? `${h}h` : "", m ? `${m}m` : ""].filter(Boolean).join(" ") || `${s}s`;
}

const str = (v, max) => (typeof v === "string" ? v.slice(0, max) : "");

export function citationView(data) {
  const c = data && typeof data.citation === "object" && data.citation !== null ? data.citation : null;
  if (!c || typeof c.id !== "string") return null;
  const l = data.labels && typeof data.labels === "object" ? data.labels : {};
  const label = (k, fallback) => str(l[k], 80) || fallback;
  return {
    id: c.id,
    number: str(c.number, 30),
    name: str(c.name, 80),
    date: str(c.occurredAt, 30).slice(0, 10),
    officer: [str(c.officer, 60), str(c.department, 20)].filter(Boolean).join(", "),
    location: str(c.location, 120),
    charges: (Array.isArray(c.charges) ? c.charges : []).slice(0, 20).map((ch) => ({
      code: str(ch?.code, 20),
      title: str(ch?.title, 80),
      counts: Number.isFinite(ch?.counts) ? ch.counts : 1,
      fine: money(ch?.fine),
    })),
    fine: money(c.fine),
    points: Number.isFinite(c.points) ? String(Math.trunc(c.points)) : "0",
    jail: jailText(c.jailSeconds),
    more: Number.isFinite(data.total) && data.total > 1 ? `1 / ${Math.trunc(data.total)}` : "",
    canSign: data.canSign === true,
    labels: {
      title: label("title", "Uniform Traffic Citation"),
      sign: label("sign", "Sign"),
      keep: label("keep", "Keep"),
      close: label("close", "Close"),
      name: label("name", "Type your full name to sign"),
      note: label("note", ""),
      fine: label("fine", "Fine"),
      points: label("points", "Points"),
      jail: label("jail", "Jail"),
      officer: label("officer", "Officer"),
      location: label("location", "Location"),
      person: label("person", "Name"),
      date: label("date", "Date"),
    },
  };
}

function el(tag, cls, text) {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  return node;
}

function cell(label, value) {
  const box = el("div", "cell");
  box.append(el("span", "value", value || " "), el("span", "label", label));
  return box;
}

function post(name, body) {
  return fetch(`https://${resource}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(body ?? {}),
  }).catch(() => {});
}

const root = typeof document !== "undefined" ? document.getElementById("citation") : null;
let shown = null;

function setBusy(on) {
  if (!root) return;
  for (const b of root.querySelectorAll("button, input")) b.disabled = on;
}

function act(action, extra = {}) {
  if (!shown) return;
  setBusy(true);
  post("citation", { action, id: shown.id, ...extra });
}

function draw(v) {
  root.replaceChildren();
  const sheet = el("div", "sheet");
  const head = el("header", "head");
  head.append(el("h1", "title", v.labels.title), el("span", "number", v.number));
  if (v.more) head.append(el("span", "more", v.more));
  const grid = el("div", "grid");
  grid.append(cell(v.labels.person, v.name), cell(v.labels.date, v.date), cell(v.labels.officer, v.officer), cell(v.labels.location, v.location));
  const table = el("table", "charges");
  for (const ch of v.charges) {
    const tr = el("tr");
    tr.append(el("td", "code", ch.code), el("td", "", ch.title), el("td", "num", `x${ch.counts}`), el("td", "num", ch.fine));
    table.append(tr);
  }
  const totals = el("div", "totals");
  totals.append(cell(v.labels.fine, v.fine), cell(v.labels.points, v.points));
  if (v.jail) totals.append(cell(v.labels.jail, v.jail));
  const form = el("form", "sign");
  const field = el("label", "field");
  const input = el("input");
  input.type = "text";
  input.maxLength = SIGNATURE_MAX;
  input.autocomplete = "off";
  input.spellcheck = false;
  field.append(input, el("span", "label", v.labels.name));
  if (v.labels.note) form.append(el("p", "note", v.labels.note));
  const actions = el("div", "actions");
  const close = el("button", "", v.labels.close);
  close.type = "button";
  close.addEventListener("click", () => act("close"));
  const keep = el("button", "", v.labels.keep);
  keep.type = "button";
  keep.addEventListener("click", () => act("keep"));
  actions.append(close, keep);
  if (v.canSign) {
    form.prepend(field);
    const sign = el("button", "primary", v.labels.sign);
    sign.type = "submit";
    actions.append(sign);
  }
  form.append(actions);
  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const typed = input.value.trim();
    if (v.canSign && typed) act("sign", { signature: typed });
  });
  sheet.append(head, grid, table, totals, form);
  root.append(sheet);
  root.hidden = false;
  (v.canSign ? input : keep).focus();
}

const handlers = {
  "citation:show": (data) => {
    const v = citationView(data);
    if (!v) return;
    shown = v;
    draw(v);
  },
  "citation:idle": () => setBusy(false),
  "citation:hide": () => {
    shown = null;
    root.hidden = true;
    root.replaceChildren();
  },
};

if (root) {
  window.addEventListener("message", (e) => {
    if (!isGameMessage(e.data, e.source, e.origin, window)) return;
    if (Object.hasOwn(handlers, e.data.type)) handlers[e.data.type](e.data);
  });
  window.addEventListener("keydown", (e) => {
    if (shown && e.key === "Escape") act("close");
  });
}
