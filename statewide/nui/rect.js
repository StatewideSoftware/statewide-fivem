export const MIN_W = 800;
export const MIN_H = 500;

const fit = (v, min, max) => Math.min(Math.max(min, Math.round(v)), max);

export function defaultRect(vw, vh) {
  const w = fit(vw * 0.7, MIN_W, vw);
  const h = fit(vh * 0.75, MIN_H, vh);
  return { x: Math.round((vw - w) / 2), y: Math.round((vh - h) / 2), w, h };
}

export function clampRect(r, vw, vh) {
  if (!r || ![r.x, r.y, r.w, r.h].every((v) => typeof v === "number" && Number.isFinite(v))) return defaultRect(vw, vh);
  const w = fit(r.w, Math.min(MIN_W, vw), vw);
  const h = fit(r.h, Math.min(MIN_H, vh), vh);
  return { x: fit(r.x, 0, vw - w), y: fit(r.y, 0, vh - h), w, h };
}
