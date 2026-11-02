export const LOAD_TIMEOUT_MS = 10000;
export const RESUME_TIMEOUT_MS = 5000;
export const READY = "statewide:ready";
export const EXPIRED = "statewide:expired";
export const RESUME = "statewide:resume";
export const HIDDEN = "statewide:hidden";
export const TOKEN = "statewide:token";
export const MAX_KEEP_MINUTES = 240;
export const MIN_SCALE = 0.8;
export const MAX_SCALE = 2;
export const SCALE_STEP = 0.1;

export function isFrameMessage(data, origin, expectedOrigin, type) {
  return expectedOrigin !== null && origin === expectedOrigin && data !== null && typeof data === "object" && data.type === type;
}

export const GAME_ORIGIN = "nui://game";

export function isGameMessage(data, source, origin, self) {
  if (source === null || source === undefined || data === null || typeof data !== "object" || typeof data.type !== "string") return false;
  if (source === self.parent && origin === GAME_ORIGIN) return true;
  return source === self && origin === self.location.origin;
}

export function isReadyMessage(data, origin, expectedOrigin) {
  return isFrameMessage(data, origin, expectedOrigin, READY);
}

export function isCloseKey(key, configured) {
  return key === "Escape" || (typeof configured === "string" && configured !== "" && typeof key === "string" && key.toUpperCase() === configured.toUpperCase());
}

const tenth = (v) => Math.round(v * 10) / 10;
const finite = (v) => typeof v === "number" && Number.isFinite(v);

export function clampScale(v) {
  return finite(v) ? Math.min(MAX_SCALE, Math.max(MIN_SCALE, tenth(v))) : 1;
}

export function autoScale(height) {
  return finite(height) ? Math.min(1.6, Math.max(1, tenth(height / 1080))) : 1;
}

export function startScale(configured, saved, height) {
  if (finite(saved)) return clampScale(saved);
  if (configured === "auto") return autoScale(height);
  return clampScale(configured);
}

export function stepScale(current, direction) {
  return clampScale(current + direction * SCALE_STEP);
}

const LOOPBACK = new Set(["localhost", "127.0.0.1"]);

export function isSignInUrl(value) {
  try {
    const u = new URL(value);
    const secure = u.protocol === "https:" || (u.protocol === "http:" && LOOPBACK.has(u.hostname));
    if (!secure) return false;
    if (u.pathname === "/auth/game/open") return u.search === "" && u.hash === "";
    return u.pathname === "/auth/game" && /^\?code=[\w-]+$/.test(u.search);
  } catch {
    return false;
  }
}

const TOKEN_SHAPE = /^[A-Za-z0-9_-]{43}$/;

export function isTabletToken(value) {
  return typeof value === "string" && TOKEN_SHAPE.test(value);
}

export function tokenMessage(token, link) {
  if (!isTabletToken(token)) return null;
  return isTabletToken(link) ? { type: TOKEN, token, link } : { type: TOKEN, token };
}

export function keepMs(minutes) {
  if (typeof minutes !== "number" || !Number.isFinite(minutes) || minutes <= 0) return 0;
  return Math.round(Math.min(minutes, MAX_KEEP_MINUTES) * 60000);
}
