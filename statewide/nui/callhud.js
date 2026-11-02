import { isGameMessage } from "./frame.js";

const root = typeof document === "undefined" ? null : document.getElementById("callhud");
const CALL_NUMBER = /^\d{2}-\d{6}$/;

const text = (v, max) => (typeof v === "string" ? v.slice(0, max) : "");
const priorityOf = (v) => (Number.isInteger(v) && v >= 1 && v <= 9 ? v : null);

export function callOf(c) {
  if (c === null || typeof c !== "object" || typeof c.number !== "string" || !CALL_NUMBER.test(c.number)) return null;
  return {
    number: c.number,
    priority: priorityOf(c.priority),
    nature: text(c.nature, 40),
    location: text(c.location, 60),
    postal: text(c.postal, 10),
    description: text(c.description, 240),
    units: Array.isArray(c.units) ? c.units.filter((u) => typeof u === "string").slice(0, 8).map((u) => u.slice(0, 16)) : [],
    attached: c.attached === true,
  };
}

export function viewOf(data) {
  const v = data && typeof data === "object" ? data.view : null;
  if (!v || typeof v !== "object") return null;
  const current = callOf(v.current);
  if (!current) return null;
  const index = Number.isInteger(v.index) ? v.index : 1;
  const total = Number.isInteger(v.total) ? v.total : 1;
  return { index, total, current, prev: callOf(v.prev), next: callOf(v.next) };
}

function el(tag, className, content) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (content !== undefined) node.textContent = content;
  return node;
}

function key(label) {
  return el("kbd", "", text(label, 12));
}

function priority(c) {
  const node = el("span", "ch-pri", c.priority ? `P${c.priority}` : "");
  if (c.priority) node.dataset.pri = String(c.priority);
  else node.hidden = true;
  return node;
}

function near(c, label) {
  const row = el("div", "ch-near");
  if (c.priority) row.dataset.pri = String(c.priority);
  row.append(key(label), el("span", "mono", c.number), priority(c), el("span", "ch-nature", c.nature));
  return row;
}

function place(c) {
  if (!c.location) return c.postal;
  return c.postal ? `${c.location} (${c.postal})` : c.location;
}

function current(c, keys, labels, showDetails) {
  const box = el("div", "ch-current");
  if (c.priority) box.dataset.pri = String(c.priority);
  const line = el("div", "ch-line");
  line.append(el("span", "mono ch-number", c.number), priority(c));
  if (c.attached) line.append(el("span", "ch-state", labels.attached));
  box.append(line);
  if (c.nature) box.append(el("div", "ch-nature", c.nature));
  const where = place(c);
  if (where) box.append(el("div", "ch-location", where));
  if (showDetails) {
    const more = el("div", "ch-details");
    if (c.description) more.append(el("p", "ch-desc", c.description));
    if (c.units.length > 0) {
      const units = el("div", "ch-units");
      units.append(el("span", "", labels.units));
      for (const u of c.units) units.append(el("span", "mono", u));
      more.append(units);
    }
    if (more.childElementCount > 0) box.append(more);
  }
  const actions = el("div", "ch-keys");
  if (!c.attached) {
    const a = el("span");
    a.append(key(keys.attach), labels.attach);
    actions.append(a);
  }
  const d = el("span");
  d.append(key(keys.details), labels.details);
  actions.append(d);
  box.append(actions);
  return box;
}

export function render(target, data) {
  const view = viewOf(data);
  if (!view) {
    target.hidden = true;
    target.replaceChildren();
    return false;
  }
  const keys = data.keys && typeof data.keys === "object" ? data.keys : {};
  const raw = data.labels && typeof data.labels === "object" ? data.labels : {};
  const labels = {
    title: text(raw.title, 24) || "Calls",
    attach: text(raw.attach, 24) || "Attach",
    attached: text(raw.attached, 24) || "Attached",
    details: text(raw.details, 24) || "Details",
    units: text(raw.units, 24) || "Units",
  };
  const bar = el("header", "ch-bar");
  bar.append(el("span", "", labels.title), el("span", "mono", `${view.index}/${view.total}`));
  const parts = [bar];
  if (view.prev) parts.push(near(view.prev, keys.prev));
  parts.push(current(view.current, keys, labels, data.details === true));
  if (view.next) parts.push(near(view.next, keys.next));
  target.replaceChildren(...parts);
  target.hidden = false;
  return true;
}

if (root) {
  window.addEventListener("message", (e) => {
    if (!isGameMessage(e.data, e.source, e.origin, window)) return;
    if (e.data.type === "callhud:show") render(root, e.data);
    else if (e.data.type === "callhud:hide") render(root, null);
  });
}
