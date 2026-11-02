const ESC = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ESC[c]);
const HEX = /^#[0-9a-f]{6}$/i;
const KINDS = ["id", "driver", "cdl", "permit", "generic"];
const kindOf = (kind) => (KINDS.includes(kind) ? kind : "generic");
export function cardImageUrl(v) {
    if (typeof v !== "string" || v.length > 2048)
        return null;
    return /^https?:\/\/[^\s"'<>\\]+$/i.test(v) || /^\/[^/\\\s"'<>][^\s"'<>\\]*$/.test(v) ? v : null;
}
export function cardWordmark(stateName) {
    const m = /^(state|commonwealth|territory) of\s+(.+)$/i.exec(stateName.trim());
    return m ? { lead: `${m[1].toUpperCase()} OF`, name: m[2].toUpperCase() } : { lead: null, name: stateName.trim().toUpperCase() };
}
function seeded(seed) {
    let s = 0x811c9dc5;
    for (let i = 0; i < seed.length; i++)
        s = Math.imul(s ^ seed.charCodeAt(i), 0x01000193) >>> 0;
    s &= 0x7fffffff;
    return () => {
        s = (Math.imul(s, 1103515245) + 12345) & 0x7fffffff;
        return s / 0x7fffffff;
    };
}
const svg = (body, viewBox, extra = "") => `data:image/svg+xml,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}"${extra}>${body}</svg>`)}`;
function barcodes(seed) {
    const rnd = seeded(seed);
    let pd = '<g fill="#10131a">';
    for (let row = 0; row < 20; row++) {
        const y = row * 5;
        pd += `<rect x="0" y="${y}" width="8" height="5"/><rect x="10" y="${y}" width="1" height="5"/><rect x="12" y="${y}" width="1" height="5"/><rect x="15" y="${y}" width="2" height="5"/>`;
        let x = 20;
        while (x < 114) {
            const w = 1 + Math.floor(rnd() * 3);
            if (rnd() > 0.48)
                pd += `<rect x="${x}" y="${y}" width="${w}" height="5"/>`;
            x += w;
        }
        pd += `<rect x="118" y="${y}" width="7" height="5"/><rect x="127" y="${y}" width="1" height="5"/><rect x="130" y="${y}" width="2" height="5"/><rect x="134" y="${y}" width="2" height="5"/>`;
    }
    let b1 = '<g fill="#10131a">';
    let bx = 0;
    while (bx < 396) {
        const w = 1 + Math.floor(rnd() * 4);
        if (rnd() > 0.4)
            b1 += `<rect x="${bx}" width="${w}" height="20"/>`;
        bx += w + 1 + Math.floor(rnd() * 2);
    }
    return { pdf: svg(`${pd}</g>`, "0 0 136 100", ' preserveAspectRatio="none"'), bar: svg(`${b1}</g>`, "0 0 400 20", ' preserveAspectRatio="none"') };
}
function defaultSeal(state) {
    const text = `${state} ~ MOTOR VEHICLES ~`;
    const size = Math.max(6, Math.min(9.4, 230 / Math.max(text.length, 1)));
    return svg(`<path id="r" d="M50 50m-37 0a37 37 0 1 1 74 0a37 37 0 1 1-74 0" fill="none"/><circle cx="50" cy="50" r="48" fill="none" stroke="#1d3f6e" stroke-width="2.4"/><circle cx="50" cy="50" r="30" fill="none" stroke="#1d3f6e" stroke-width="1.6"/><text font-family="Arial Narrow,sans-serif" font-weight="700" font-size="${size.toFixed(1)}" letter-spacing="1.2" fill="#1d3f6e"><textPath href="#r">${esc(state)} &#9733; MOTOR VEHICLES &#9733;</textPath></text><circle cx="61" cy="43" r="7" fill="none" stroke="#1d3f6e" stroke-width="1.6"/><path d="M21 62l12-15 7 7 10-14 11 14 6-6 12 14" fill="none" stroke="#1d3f6e" stroke-width="1.8" stroke-linejoin="round"/><path d="M23 67q7-4 14 0t13 0 13 0 13 0M25 72q6-3 12 0t12 0 12 0 12 0" stroke="#1d3f6e" stroke-width="1.4" fill="none"/>`, "0 0 100 100");
}
const SIL = '<svg class="sil" viewBox="0 0 120 160" aria-hidden="true"><path d="M60 30c-14 0-23 11-23 27 0 11 4 21 10 27 2 2 3 5 3 8v7c0 3-2 5-5 6-17 5-33 11-39 22-3 6-5 21-5 33h118c0-12-2-27-5-33-6-11-22-17-39-22-3-1-5-3-5-6v-7c0-3 1-6 3-8 6-6 10-16 10-27 0-16-9-27-23-27z" fill="#8c929a"/></svg>';
const HEART = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 17.5S2 12.6 2 7.2A4.2 4.2 0 0 1 10 5a4.2 4.2 0 0 1 8 2.2c0 5.4-8 10.3-8 10.3z" fill="#b3122b"/></svg>';
const ICON_PATHS = {
    boat: '<path d="M12 5v10M12 6l5 8h-5M11 8l-4 6h4M6 16.5h12l-2 2.5H8z"/>',
    hunt: '<path d="M9 18v-4l-3-3V7M6 9l-2-1M9 14l-2-4M15 18v-4l3-3V7M18 9l2-1M15 14l2-4M9 14h6"/>',
    fresh: '<path d="M5 11c3-4 8-4 11 0-3 4-8 4-11 0zM16 11l3-2.5v5zM5 16.5q2-1.5 4 0t4 0 4 0"/><circle cx="8" cy="10.5" r=".6" fill="currentColor"/>',
    salt: '<path d="M6 10c3-3.5 7-3.5 10 0-3 3.5-7 3.5-10 0zM16 10l2.5-2v4zM5 15q1.75-1.3 3.5 0t3.5 0 3.5 0 3.5 0M5 18q1.75-1.3 3.5 0t3.5 0 3.5 0 3.5 0"/>',
    sport: '<path d="M12 5l1.9 4.2 4.6.4-3.5 3 1 4.5-4-2.4-4 2.4 1-4.5-3.5-3 4.6-.4z"/>',
};
const icon = (key) => `<svg viewBox="0 0 24 24" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="11"/>${ICON_PATHS[key] ?? ""}</g></svg>`;
const f = (label, value, cls = "") => `<span class="f ${cls}"><em>${esc(label)}</em><b class="e">${esc(value)}</b></span>`;
const ln = (top, html, cls = "") => `<div class="ln ${cls}" style="top:calc(${Math.round(top * 10) / 10}*var(--cq))">${html}</div>`;
const row = (html) => `<div class="row">${html}</div>`;
const fx = (label, value, cls = "") => (value ? f(label, value, cls) : "");
function photo(url, cls) {
    const img = url ? `<img src="${esc(url)}" alt="" referrerpolicy="no-referrer">` : "";
    return `<div class="${cls}">${img}${cls === "photo" && !url ? SIL : ""}${cls === "bphoto" && !url ? SIL : ""}</div>`;
}
const micro = (state, community, title) => esc(Array(14).join(`${state} · ${community.toUpperCase()} · ${title} · `));
function palette(m, t) {
    const d = m.design;
    if (d)
        return HEX.test(d.colors.header) && HEX.test(d.colors.accent) ? ` style="--stripe-a:${d.colors.header};--stripe-b:${d.colors.accent};--title:${d.colors.header};--lab:${d.colors.header}"` : "";
    if (m.kind !== "driver")
        return "";
    const c = t.colors;
    if (!HEX.test(c.band) || !HEX.test(c.accent) || !HEX.test(c.ink))
        return "";
    return ` style="--stripe-a:${c.band};--stripe-b:${c.accent};--title:${c.band};--lab:${c.ink}"`;
}
const shows = (m, key) => !m.design || !Array.isArray(m.design.hidden) || !m.design.hidden.includes(key);
const stateOf = (m, t) => (m.design && typeof m.design.stateName === "string" && m.design.stateName.trim() ? m.design.stateName : t.stateName);
function wordmark(m, wm) {
    const img = cardImageUrl(m.design?.wordmarkUrl);
    if (img)
        return `<div class="wm"><img class="wmimg" src="${esc(img)}" alt=""></div>`;
    return `<div class="wm"><div class="st${wm.name.length > 11 ? " long" : ""}">${wm.lead ? `<small>${esc(wm.lead)}</small>` : ""}${esc(wm.name)}</div><span class="usa">USA</span></div>`;
}
export const cardDefaultSeal = (stateName) => defaultSeal(cardWordmark(stateName).name);
function front(m, t) {
    const wm = cardWordmark(stateOf(m, t));
    const seal = cardImageUrl(m.design?.sealUrl) ?? cardImageUrl(t.sealUrl) ?? defaultSeal(wm.name);
    const pic = cardImageUrl(m.photoUrl);
    const on = (key) => shows(m, key);
    const cells = (...parts) => parts.map(([k, html]) => (k === null || on(k) ? html : "")).join("");
    let h = ln(13.4, f(m.numberLabel, m.number), "dl") + (m.expires ? ln(19.6, f("EXP", m.expires), "exp") : "") + ln(24.4, f("LN", m.lastName), "nm") + ln(28.2, f("FN", m.firstName), "nm");
    if (on("address")) {
        if (m.addressLine)
            h += ln(32.4, f("", m.addressLine), "ad");
        if (m.cityLine)
            h += ln(35.2, f("", m.cityLine), "ad");
    }
    let y = on("address") ? 39.2 : 32.4;
    if (m.kind === "generic") {
        h += ln(y, f("DOB", m.dob), "dob");
        const r = cells(["issued", f("ISS", m.issued)], ["sex", f("SEX", m.sex)]);
        if (r)
            h += ln(y + 4.4, row(r));
    }
    else {
        h += ln(y, row(f("DOB", m.dob, "dob") + (m.restrictions !== null && on("restrictions") ? f("RSTR", m.restrictions) : "")));
        y += 4;
        const end = on("endorsements") && m.endorsements && m.endorsements !== "NONE" ? ` · ${m.endorsements}` : "";
        const r2 = m.class === null ? "" : m.kind === "cdl" ? (on("class") ? f("", `CLASS ${m.class}${end}`) : on("endorsements") ? f("END", m.endorsements ?? "NONE") : "") : cells(["class", f("CLASS", m.class)], ["endorsements", f("END", m.endorsements ?? "NONE")]);
        if (r2) {
            h += ln(y, row(r2));
            y += 3;
        }
        const r3 = cells(["sex", f("SEX", m.sex)], ["height", fx("HGT", m.height)], ["weight", fx("WGT", m.weight)]);
        if (r3) {
            h += ln(y, row(r3));
            y += 3;
        }
        const r4 = cells(["hair", fx("HAIR", m.hair)], ["eyes", fx("EYES", m.eyes)], ["issued", f("ISS", m.issued)]);
        if (r4) {
            h += ln(y, row(r4));
            y += 3;
        }
        if (m.issuedBy && on("issuedBy"))
            h += ln(y, f("ISSUED BY", m.issuedBy));
    }
    const d = m.designations;
    const vet = d?.veteran && on("veteran");
    const don = d?.donor && on("donor");
    const safe = d?.safeDriverSince && on("safeDriver") ? d.safeDriverSince : null;
    const desig = vet || don || safe
        ? `<div class="desig">${vet ? '<span class="vet">VETERAN</span>' : ""}${don ? `<span class="don">${HEART}<span class="e">DONOR</span></span>` : ""}${safe ? `<span class="safe"><em>SAFE DRIVER</em><b class="e">${esc(safe)}</b></span>` : ""}</div>`
        : "";
    return (`<div class="lic t-${m.kind} ${m.status === "expired" ? "expired" : ""}"${palette(m, t)} role="img" aria-label="${esc(`${wm.name} ${m.title} for ${m.holderName}, status ${m.statusWord}`.toLowerCase())}"><div class="face">` +
        `<div class="land"></div><img class="wseal" src="${esc(seal)}" alt=""><div class="stripe"></div>` +
        `<div class="microv">${micro(wm.name, t.communityName, m.title)}</div>` +
        wordmark(m, wm) +
        `<div class="title"><span class="e">${esc(m.title)}</span>${m.note ? `<small>${esc(m.note)}</small>` : ""}</div>` +
        `<div class="star"></div>` +
        `<div class="status${m.bad ? " bad" : ""}"><em>STATUS</em><b class="e">${esc(m.statusWord)}</b></div>` +
        photo(pic, "photo") +
        (pic && on("ghost") ? photo(pic, "ghost") : "") +
        h +
        desig +
        (on("signature") ? `<div class="sig">${esc(m.signature)}</div>` : "") +
        (on("dd") ? `<div class="dd">${f("DD", m.dd)}</div>` : "") +
        `<div class="micro">${micro(wm.name, t.communityName, m.title)}</div>` +
        `<div class="holo"></div><div class="gloss"></div>` +
        `</div>${m.overprint ? `<div class="over">${esc(m.overprint)}</div>` : ""}</div>`);
}
const NOTICE = "Replacement license required within 30 days of an address or name change.";
function back(m, t) {
    const b = m.back;
    const state = stateOf(m, t);
    const wm = cardWordmark(state);
    const codes = barcodes(b.barcodeSeed);
    const on = (key) => shows(m, key);
    const notice = m.design ? (typeof m.design.notice === "string" ? m.design.notice.trim() : "") : NOTICE;
    const wmImg = cardImageUrl(m.design?.wordmarkUrl);
    const legend = (b.classText && on("backClass") ? `<p>${legendLine(b.classText)}</p>` : "") +
        (on("backRestrictions") ? `<p><b>REST:</b>${esc(b.restrictions)}</p>` : "") +
        (on("backEndorsements") ? `<p><b>END:</b>${esc(b.endorsements.join(" · "))}</p>` : "") +
        (notice && on("backNotice") ? `<p>${esc(notice)}</p>` : "") +
        (t.siteHost && on("backSite") ? `<p class="url">${esc(t.siteHost)}</p>` : "");
    return (`<div class="lic t-${m.kind} back"${palette(m, t)} role="img" aria-label="${esc(`back of the ${wm.name} ${m.title}`.toLowerCase())}"><div class="face">` +
        `<div class="land" style="opacity:.3"></div>` +
        `<div class="bar1" style="--bar1:url('${codes.bar}')"></div><div class="bpdf" style="--pdf:url('${codes.pdf}')"></div>` +
        (wmImg ? `<img class="bwm" src="${esc(wmImg)}" alt="">` : `<div class="bwm">${esc(wm.name)}</div>`) +
        `<div class="bnum">${esc(m.number)}</div>` +
        photo(cardImageUrl(m.photoUrl), "bphoto") +
        (on("backIcons") ? `<div class="picto">${b.icons.map((i) => `<span${i.on ? ' class="on"' : ""}>${icon(i.key)}${esc(i.label)}</span>`).join("")}</div>` : "") +
        `<div class="legend">${legend}</div>` +
        `<div class="office"><span>ISSUED BY ${esc(state.toUpperCase())} · DEPARTMENT OF MOTOR VEHICLES</span><span>DD ${esc(m.dd)}</span></div>` +
        `<div class="micro">${micro(wm.name, t.communityName, m.title)}</div><div class="holo"></div><div class="gloss"></div>` +
        "</div></div>");
}
function legendLine(s) {
    const i = s.indexOf(":");
    return i > 0 ? `<b>${esc(s.slice(0, i + 1))}</b>${esc(s.slice(i + 1).trim())}` : esc(s);
}
function vertical(m, t) {
    const wm = cardWordmark(stateOf(m, t));
    return (`<div class="vlic" role="img" aria-label="${esc(`${wm.name} under 21 ${m.title} for ${m.holderName}, status ${m.statusWord}`.toLowerCase())}"><div class="face">` +
        `<div class="land" style="background-size:300% 100%;background-position:80% 50%;opacity:.4"></div><div class="vtop"></div>` +
        `<div class="vwm">${wm.lead ? `<small>${esc(wm.lead)}</small>` : ""}${esc(wm.name)}</div><div class="vstar"></div>` +
        `<div class="vtitle e">${esc(m.title)}</div>` +
        `<div class="u21">UNDER 21 UNTIL ${esc(m.under21Until)}</div><div class="u18">UNDER 18 UNTIL ${esc(m.under18Until)}</div>` +
        photo(cardImageUrl(m.photoUrl), "photo") +
        `<div class="vf"><div class="dl">${f(m.numberLabel, m.number)}</div><div class="nm">${f("LN", m.lastName)}</div><div class="nm">${f("FN", m.firstName)}</div>` +
        `<div class="row">${f("DOB", m.dob, "dob")}${f("EXP", m.expires, "exp")}</div><div class="row">${f("CLASS", m.class ?? "NONE")}${f("SEX", m.sex)}${f("RSTR", m.restrictions ?? "NONE")}</div>` +
        "</div>" +
        `<div class="vsig">${esc(m.signature)}</div>` +
        `<div class="micro">${micro(wm.name, t.communityName, m.title)}</div><div class="holo"></div><div class="gloss"></div>` +
        `</div>${m.overprint ? `<div class="over">${esc(m.overprint)}</div>` : ""}</div>`);
}
export const isVerticalCard = (m, t) => t.verticalUnder21 && m.kind === "driver" && m.under21Until !== null;
export function renderLicenseCard(card, t, side = "front") {
    const m = { ...card, kind: kindOf(card.kind) };
    const body = isVerticalCard(m, t) ? vertical(m, t) : side === "back" && m.back ? back(m, t) : front(m, t);
    return `<div class="lcard">${body}</div>`;
}
