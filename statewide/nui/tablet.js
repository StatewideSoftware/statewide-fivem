import { clampRect, defaultRect } from "./rect.js";
import { EXPIRED, HIDDEN, LOAD_TIMEOUT_MS, READY, RESUME, RESUME_TIMEOUT_MS, isCloseKey, isFrameMessage, isGameMessage, isSignInUrl, keepMs, startScale, stepScale, tokenMessage } from "./frame.js";

const resource = typeof window.GetParentResourceName === "function" ? window.GetParentResourceName() : "statewide";
const $ = (id) => document.getElementById(id);
const tablet = $("tablet");
const frame = $("frame");
let rect = null;
let scale = 1;
let configuredScale = "auto";
let expectedOrigin = null;
let live = false;
let timer = 0;
let idle = 0;
let keep = 0;
let closeKey = null;
let token = null;
let link = null;
let timeout = {
  code: "frame_timeout",
  title: "The MDT did not load",
  next: "Close the tablet and try again. If it keeps happening, tell a server admin.",
};

function post(name, body) {
  return fetch(`https://${resource}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(body ?? {}),
  }).catch(() => {});
}

function place(r) {
  rect = clampRect(r, window.innerWidth, window.innerHeight);
  Object.assign(tablet.style, { left: `${rect.x}px`, top: `${rect.y}px`, width: `${rect.w}px`, height: `${rect.h}px` });
}

function applyScale(s) {
  scale = s;
  Object.assign(frame.style, { width: `${100 / s}%`, height: `${100 / s}%`, transform: `scale(${s})` });
}

function showStatus(kind) {
  $("status").hidden = kind === "frame";
  $("loading").hidden = kind !== "loading";
  $("error").hidden = kind !== "error";
  frame.hidden = kind !== "frame";
}

function stopFrame() {
  clearTimeout(timer);
  clearTimeout(idle);
  expectedOrigin = null;
  live = false;
  token = null;
  link = null;
  frame.src = "about:blank";
}

function requestCode() {
  stopFrame();
  showStatus("loading");
  post("code");
}

function resume() {
  showStatus("frame");
  frame.contentWindow?.postMessage({ type: RESUME }, expectedOrigin);
  clearTimeout(timer);
  timer = setTimeout(requestCode, RESUME_TIMEOUT_MS);
}

function hide() {
  tablet.hidden = true;
  clearTimeout(timer);
  if (!live) {
    stopFrame();
    showStatus("loading");
    return;
  }
  frame.contentWindow?.postMessage({ type: HIDDEN }, expectedOrigin);
  clearTimeout(idle);
  if (keep > 0) idle = setTimeout(unload, keep);
}

function unload() {
  if (!tablet.hidden) return;
  stopFrame();
  showStatus("loading");
}

function close() {
  hide();
  post("close");
}

const handlers = {
  open(m) {
    const l = m.labels ?? {};
    if (typeof l.title === "string") $("tablet-title").textContent = l.title;
    if (typeof l.reset === "string") $("reset").textContent = l.reset;
    if (typeof l.close === "string") $("close").textContent = l.close;
    for (const id of ["smaller", "larger"]) {
      if (typeof l[id] === "string") {
        $(id).title = l[id];
        $(id).setAttribute("aria-label", l[id]);
      }
    }
    if (typeof l.loading === "string") $("loading").textContent = l.loading;
    if (typeof l.timeoutTitle === "string") timeout = { ...timeout, title: l.timeoutTitle };
    if (typeof l.timeoutNext === "string") timeout = { ...timeout, next: l.timeoutNext };
    closeKey = typeof m.key === "string" ? m.key : null;
    keep = keepMs(m.keepMinutes);
    clearTimeout(idle);
    configuredScale = m.scale;
    place(m.rect);
    applyScale(startScale(m.scale, m.savedScale, window.innerHeight));
    tablet.hidden = false;
    if (live) resume();
    else requestCode();
    $("close").focus();
  },
  url(m) {
    const valid = isSignInUrl(m.url);
    const opens = valid && new URL(m.url).pathname === "/auth/game/open";
    const tokenOk = m.token === undefined || m.token === null ? !opens : tokenMessage(m.token, null) !== null;
    const linkOk = !opens || "link" in (tokenMessage(m.token, m.link) ?? {});
    if (!valid || !tokenOk || !linkOk) return handlers.error({ code: "error", title: "The CAD sent an invalid sign-in link", next: "Tell a server admin." });
    stopFrame();
    token = m.token ?? null;
    link = opens ? m.link : null;
    expectedOrigin = new URL(m.url).origin;
    frame.src = m.url;
    timer = setTimeout(() => handlers.error(timeout), LOAD_TIMEOUT_MS);
  },
  error(m) {
    stopFrame();
    $("error-code").textContent = String(m.code ?? "error");
    $("error-title").textContent = String(m.title ?? "");
    $("error-next").textContent = String(m.next ?? "");
    showStatus("error");
    $("close").focus();
  },
  drop() {
    if (tablet.hidden) {
      stopFrame();
      showStatus("loading");
    } else requestCode();
  },
  close: hide,
};

window.addEventListener("message", (e) => {
  if (e.source === frame.contentWindow) {
    if (isFrameMessage(e.data, e.origin, expectedOrigin, READY)) {
      const handover = tokenMessage(token, link);
      if (handover) frame.contentWindow?.postMessage(handover, expectedOrigin);
      link = null;
      clearTimeout(timer);
      live = true;
      if (!tablet.hidden) {
        showStatus("frame");
        post("shown");
      }
    } else if (isFrameMessage(e.data, e.origin, expectedOrigin, EXPIRED)) {
      if (tablet.hidden) stopFrame();
      else requestCode();
    }
    return;
  }
  if (!isGameMessage(e.data, e.source, e.origin, window)) return;
  if (Object.hasOwn(handlers, e.data.type)) handlers[e.data.type](e.data);
});

window.addEventListener("keydown", (e) => {
  if (isCloseKey(e.key, closeKey) && !tablet.hidden) close();
});

$("close").addEventListener("click", close);
$("reset").addEventListener("click", () => {
  place(defaultRect(window.innerWidth, window.innerHeight));
  applyScale(startScale(configuredScale, null, window.innerHeight));
  post("rect", { reset: true });
});

for (const [id, direction] of [
  ["smaller", -1],
  ["larger", 1],
]) {
  $(id).addEventListener("click", () => {
    applyScale(stepScale(scale, direction));
    post("scale", { scale });
  });
}

function track(handle, onMove) {
  handle.addEventListener("pointerdown", (e) => {
    if (e.button !== 0 || e.target.closest("button")) return;
    e.preventDefault();
    const start = { px: e.clientX, py: e.clientY, ...rect };
    handle.setPointerCapture(e.pointerId);
    tablet.classList.add("moving");
    const move = (ev) => place(onMove(start, ev.clientX - start.px, ev.clientY - start.py));
    const up = () => {
      handle.removeEventListener("pointermove", move);
      handle.removeEventListener("pointerup", up);
      handle.removeEventListener("pointercancel", up);
      tablet.classList.remove("moving");
      post("rect", rect);
    };
    handle.addEventListener("pointermove", move);
    handle.addEventListener("pointerup", up);
    handle.addEventListener("pointercancel", up);
  });
}

track($("bar"), (s, dx, dy) => ({ x: s.x + dx, y: s.y + dy, w: s.w, h: s.h }));
track($("grip"), (s, dx, dy) => ({ x: s.x, y: s.y, w: s.w + dx, h: s.h + dy }));

window.addEventListener("resize", () => {
  if (rect) place(rect);
});
