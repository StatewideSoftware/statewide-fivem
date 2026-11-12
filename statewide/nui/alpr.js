import { isGameMessage } from "./frame.js";

const SOUNDS = new Set(["alpr-stolen", "alpr-warrant", "alpr-bolo", "alpr-registration", "alpr-insurance"]);

window.addEventListener("message", (e) => {
  if (!isGameMessage(e.data, e.source, e.origin, window)) return;
  if (e.data.type !== "alpr:tone" || !SOUNDS.has(e.data.sound)) return;
  const audio = new Audio(`../client/sounds/${e.data.sound}.mp3`);
  audio.volume = 0.6;
  audio.play().catch(() => {});
});
