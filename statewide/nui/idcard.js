import { cardModel, cardTheme } from "./card.js";
import { isGameMessage } from "./frame.js";
import { isVerticalCard, renderLicenseCard } from "./licence-card.js";

const root = document.getElementById("idcard");
let shown = null;

function draw() {
  root.innerHTML = renderLicenseCard(shown.card, shown.theme, shown.side);
  root.toggleAttribute("data-vertical", isVerticalCard(shown.card, shown.theme));
  root.toggleAttribute("data-handed", shown.handed);
  for (const img of root.querySelectorAll("img")) img.addEventListener("error", () => img.remove(), { once: true });
}

const handlers = {
  "idcard:show": (data) => {
    const card = cardModel(data.card, data.hosts, data.devHttp === true);
    if (!card) return;
    shown = { card, theme: cardTheme(data.theme, data.hosts, data.devHttp === true), side: "front", handed: data.handed === true };
    draw();
    root.hidden = false;
  },
  "idcard:flip": () => {
    if (!shown || !shown.card.back) return;
    shown.side = shown.side === "front" ? "back" : "front";
    draw();
  },
  "idcard:hide": () => {
    shown = null;
    root.hidden = true;
    root.replaceChildren();
  },
};

window.addEventListener("message", (e) => {
  if (!isGameMessage(e.data, e.source, e.origin, window)) return;
  if (Object.hasOwn(handlers, e.data.type)) handlers[e.data.type](e.data);
});
