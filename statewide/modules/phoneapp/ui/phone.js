export const NUI_PREFIX = "https://cfx-nui-";
export const RESOURCE_NAME = /^[A-Za-z0-9_.-]{1,64}$/;

export function resourceOf(hostname) {
  if (typeof hostname !== "string" || !hostname.startsWith("cfx-nui-")) return null;
  const name = hostname.slice("cfx-nui-".length);
  return RESOURCE_NAME.test(name) ? name : null;
}

export function phoneOrigin(lb) {
  return typeof lb === "string" && RESOURCE_NAME.test(lb) ? NUI_PREFIX + lb.toLowerCase() : null;
}

export function isTrusted(event, self, lbOrigin) {
  if (!event || event.data === null || event.data === undefined) return false;
  if (event.source === self && event.origin === self.location.origin) return true;
  return lbOrigin !== null && event.source === self.parent && event.origin === lbOrigin;
}

export const PUSH_TYPES = ["unit", "call", "my911", "character"];

export function pushOf(data) {
  if (!data || typeof data !== "object" || !PUSH_TYPES.includes(data.type)) return null;
  return data;
}

const OK = ["valid", "active", "insured", "alive", "open", "scheduled", "available"];
const BAD = ["suspended", "revoked", "expired", "stolen", "uninsured", "deceased", "closed", "panic"];

export function toneOf(state) {
  const s = String(state ?? "").toLowerCase();
  if (OK.includes(s)) return "ok";
  if (BAD.includes(s)) return "red";
  if (s === "pending" || s === "pending_renewal") return "amber";
  return "gray";
}

export function words(value) {
  const s = String(value ?? "").replace(/_/g, " ").trim();
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : "";
}

export function money(n) {
  const v = Number.isFinite(n) ? Math.trunc(n) : 0;
  return "$" + v.toLocaleString("en-US");
}

export const HOLD_MS = 1500;

export function holdProgress(startedAt, now, holdMs = HOLD_MS) {
  if (!Number.isFinite(startedAt) || !Number.isFinite(now)) return 0;
  return Math.max(0, Math.min(1, (now - startedAt) / holdMs));
}
