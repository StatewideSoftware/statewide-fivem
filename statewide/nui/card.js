const LOOPBACK = new Set(["localhost", "127.0.0.1"]);

export function isPhotoUrl(value, hosts, devHttp = false) {
  if (typeof value !== "string" || value.length > 2048) return false;
  try {
    const u = new URL(value);
    if (u.username || u.password || !Array.isArray(hosts)) return false;
    if (u.protocol !== "https:" && !(devHttp === true && u.protocol === "http:" && LOOPBACK.has(u.hostname))) return false;
    return hosts.some((h) => {
      if (typeof h !== "string" || h === "") return false;
      const host = h.toLowerCase();
      return u.hostname === host || (host.startsWith(".") && u.hostname.length > host.length && u.hostname.endsWith(host));
    });
  } catch {
    return false;
  }
}

export const DEFAULT_THEME = {
  stateName: "State of San Andreas",
  sealUrl: null,
  colors: { band: "#1d4f8f", accent: "#5b9bd5", ink: "#244e93" },
  verticalUnder21: false,
  communityName: "",
  siteHost: null,
};

const text = (v, fallback) => (typeof v === "string" && v.trim() !== "" ? v : fallback);

export function cardTheme(theme, hosts, devHttp = false) {
  const t = theme && typeof theme === "object" ? theme : {};
  const c = t.colors && typeof t.colors === "object" ? t.colors : {};
  const d = DEFAULT_THEME;
  return {
    stateName: text(t.stateName, d.stateName),
    sealUrl: isPhotoUrl(t.sealUrl, hosts, devHttp) ? t.sealUrl : null,
    colors: { band: text(c.band, d.colors.band), accent: text(c.accent, d.colors.accent), ink: text(c.ink, d.colors.ink) },
    verticalUnder21: t.verticalUnder21 === true,
    communityName: text(t.communityName, d.communityName),
    siteHost: text(t.siteHost, null),
  };
}

const KINDS = new Set(["id", "driver", "cdl", "permit", "generic"]);

const HEX = /^#[0-9a-f]{6}$/i;
const words = (v) => (v && typeof v === "object" ? Object.fromEntries(Object.entries(v).filter(([, w]) => typeof w === "string")) : {});

export function cardDesign(design, hosts, devHttp = false) {
  if (!design || typeof design !== "object") return undefined;
  const c = design.colors && typeof design.colors === "object" ? design.colors : {};
  if (!HEX.test(c.header) || !HEX.test(c.accent)) return undefined;
  return {
    version: Number.isInteger(design.version) ? design.version : 0,
    stateName: text(design.stateName, ""),
    wordmarkUrl: isPhotoUrl(design.wordmarkUrl, hosts, devHttp) ? design.wordmarkUrl : null,
    sealUrl: isPhotoUrl(design.sealUrl, hosts, devHttp) ? design.sealUrl : null,
    colors: { header: c.header, accent: c.accent },
    hidden: Array.isArray(design.hidden) ? design.hidden.filter((k) => typeof k === "string") : [],
    notice: typeof design.notice === "string" ? design.notice : "",
    classText: words(design.classText),
    endorsements: words(design.endorsements),
  };
}

export function cardModel(card, hosts, devHttp = false) {
  if (!card || typeof card !== "object" || typeof card.number !== "string" || typeof card.kind !== "string") return null;
  const out = { ...card, kind: KINDS.has(card.kind) ? card.kind : "generic", photoUrl: isPhotoUrl(card.photoUrl, hosts, devHttp) ? card.photoUrl : null };
  const design = cardDesign(card.design, hosts, devHttp);
  if (design) out.design = design;
  else delete out.design;
  return out;
}
