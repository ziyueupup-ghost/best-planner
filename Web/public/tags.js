// Tag chips drawn like the Mac app (Shared/Tags.swift): 19 shapes, 8 styles, custom
// text / fill / border colors. The label is HTML; the shape is an SVG drawn behind it
// once the chip's size is known (drawTagShapes).

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

function rgb(hex) {
  const h = String(hex || "#888888").replace("#", "");
  const n = parseInt(h.length === 3 ? h.replace(/./g, "$&$&") : h.slice(0, 6), 16);
  return Number.isNaN(n) ? [136, 136, 136] : [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
export const rgba = (hex, a) => `rgba(${rgb(hex).join(",")},${a})`;
const mix = (hex, other, f) => { const c = rgb(hex), o = rgb(other); return `rgb(${c.map((v, i) => Math.round(v + (o[i] - v) * f)).join(",")})`; };
/** Black or white text on this color (Color.contrastingText). */
export function contrasting(hex) {
  const [r, g, b] = rgb(hex).map((v) => v / 255);
  return 0.299 * r + 0.587 * g + 0.114 * b > 0.65 ? "#000" : "#fff";
}

const LINE_ONLY = new Set(["underline", "dot", "bracket"]);
const STRONG = new Set(["solid", "gradient", "shadow"]);

/** HTML for a tag chip; `small` is the size used on cards. */
export function tagChipHTML(tag, { small = false, off = false, extra = "" } = {}) {
  const shape = tag.shape || "capsule", style = tag.style || "soft", color = tag.colorHex || "#888888";
  const lineOnly = LINE_ONLY.has(shape);
  const text = tag.textHex || (STRONG.has(style) && !lineOnly ? contrasting(color) : color);
  let fill = tag.fillHex || null;
  if (!fill && !lineOnly) fill = { soft: rgba(color, 0.18), duotone: rgba(color, 0.12), neon: rgba(color, 0.08), solid: color, shadow: color, gradient: "gradient" }[style] || null;
  let border = tag.border || "auto";
  if (border === "auto") border = style === "outline" || style === "duotone" || style === "neon" || shape === "underline" || shape === "bracket" ? "solid" : "none";
  const width = shape === "underline" || shape === "bracket" ? Math.max(tag.borderWidth ?? 1, 1.5) : (tag.borderWidth ?? 1);
  const weight = STRONG.has(style) || style === "plain" ? 600 : 400;
  const filter = style === "neon" ? `drop-shadow(0 0 2.5px ${rgba(color, 0.9)}) drop-shadow(0 0 6px ${rgba(color, 0.5)})`
    : style === "shadow" ? "drop-shadow(0 1.5px 2px rgba(0,0,0,.3))" : "";
  const pad = padding(shape, small);
  const label = `${tag.icon ? `<span>${esc(tag.icon)}</span>` : ""}<span>${esc(tag.name)}</span>`;
  const dot = shape === "dot" ? `<i class="tg-dot" style="width:${small ? 6 : 8}px;height:${small ? 6 : 8}px;background:${style === "outline" ? "transparent" : color};${border !== "none" ? `box-shadow:inset 0 0 0 ${width}px ${tag.borderHex || color}` : ""}"></i>` : "";
  return `<span class="tg ${small ? "small" : ""} ${off ? "off" : ""} ${extra}" data-shape="${shape}"
    data-fill="${fill === "gradient" ? "" : esc(fill || "")}" data-grad="${fill === "gradient" ? esc(color) : ""}"
    data-stroke="${border === "none" ? "" : esc(tag.borderHex || color)}" data-pattern="${border}" data-width="${width}"
    style="color:${esc(text)};font-weight:${weight};padding:${pad};${filter ? `filter:${filter};` : ""}">${dot}${label}</span>`;
}

function padding(shape, small) {
  if (shape === "dot") return "0";
  if (shape === "underline") return "0 2px 3px";
  const u = small ? 3 : 4, h = small ? 5 : 7, v = small ? 1 : 2;
  const e = { flag: [0, u + 1, 0, 0], arrow: [0, 0, 0, u + 2], chevron: [0, u + 1, 0, u + 2], ribbon: [0, 0, 0, u + 1],
    slant: [0, u, 0, u], hexagon: [0, u, 0, u], ticket: [0, u - 1, 0, u - 1], leaf: [0, u - 1, 0, u - 1], bracket: [0, u - 1, 0, u - 1],
    cutCorner: [0, 1, 0, 1], folded: [0, 0, 0, u], bubble: [0, 0, 3, 0], scallop: [1, 2, 1, 2] }[shape] || [0, 0, 0, 0];
  // [top, leading, bottom, trailing]
  return `${v + e[0]}px ${h + e[3]}px ${v + e[2]}px ${h + e[1]}px`;
}

// MARK: Shapes (ports of the SwiftUI Shape paths, in pixels)

function rounded(w, h, tl, tr, br, bl) {
  const m = Math.min(w, h) / 2;
  [tl, tr, br, bl] = [tl, tr, br, bl].map((r) => Math.min(r, m));
  return `M${tl},0 H${w - tr} A${tr},${tr} 0 0 1 ${w},${tr} V${h - br} A${br},${br} 0 0 1 ${w - br},${h} H${bl} A${bl},${bl} 0 0 1 0,${h - bl} V${tl} A${tl},${tl} 0 0 1 ${tl},0 Z`;
}

const poly = (pts) => `M${pts.map((p) => p.join(",")).join(" L")} Z`;

function shapePath(shape, w, h) {
  const my = h / 2;
  switch (shape) {
    case "capsule": case "dot": return rounded(w, h, h / 2, h / 2, h / 2, h / 2);
    case "rounded": return rounded(w, h, 5, 5, 5, 5);
    case "tab": return rounded(w, h, 6, 6, 0, 0);
    case "leaf": return rounded(w, h, 9, 2, 9, 2);
    case "flag": {
      const n = Math.min(my, 7), r = Math.min(4, h / 4);
      return `M0,${my} L${n},0 H${w - r} Q${w},0 ${w},${r} V${h - r} Q${w},${h} ${w - r},${h} H${n} Z`;
    }
    case "arrow": { const n = Math.min(my, 7); return poly([[0, 0], [w - n, 0], [w, my], [w - n, h], [0, h]]); }
    case "chevron": { const n = Math.min(my, 7); return poly([[0, 0], [w - n, 0], [w, my], [w - n, h], [0, h], [n, my]]); }
    case "ribbon": { const n = Math.min(my, 6); return poly([[0, 0], [w, 0], [w - n, my], [w, h], [0, h]]); }
    case "slant": { const s = Math.min(h * 0.35, 6); return poly([[s, 0], [w, 0], [w - s, h], [0, h]]); }
    case "hexagon": { const n = Math.min(my, 6); return poly([[0, my], [n, 0], [w - n, 0], [w, my], [w - n, h], [n, h]]); }
    case "cutCorner": { const c = Math.min(h * 0.3, 4.5); return poly([[c, 0], [w - c, 0], [w, c], [w, h - c], [w - c, h], [c, h], [0, h - c], [0, c]]); }
    case "ticket": {
      const n = Math.min(h * 0.28, 4);
      return `M0,0 H${w} V${my - n} Q${w - n * 1.8},${my} ${w},${my + n} V${h} H0 V${my + n} Q${n * 1.8},${my} 0,${my - n} Z`;
    }
    case "folded": { const c = Math.min(h * 0.4, 6); return `${poly([[0, 0], [w - c, 0], [w, c], [w, h], [0, h]])} M${w - c},0 V${c} H${w}`; }
    case "bubble": {
      const bh = h - 3, r = Math.min(5, bh / 2);
      return `${rounded(w, bh, r, r, r, r)} M5,${bh - 0.5} L4,${h} L11,${bh - 0.5} Z`;
    }
    case "scallop": {
      const bump = Math.min(1.8, h * 0.12), count = Math.max(2, Math.floor(w / 6)), step = w / count;
      let d = `M0,${bump}`;
      for (let i = 0; i < count; i++) d += ` Q${step * i + step / 2},${-bump} ${step * (i + 1)},${bump}`;
      d += ` L${w},${h - bump}`;
      for (let i = 0; i < count; i++) d += ` Q${w - step * i - step / 2},${h + bump} ${w - step * (i + 1)},${h - bump}`;
      return `${d} Z`;
    }
    case "bracket": { const a = Math.min(4, w / 4); return `M${a},0 H0 V${h} H${a} M${w - a},0 H${w} V${h} H${w - a}`; }
    case "underline": return `M0,${h} H${w}`;
    default: return `M0,0 H${w} V${h} H0 Z`;   // square
  }
}

function dash(pattern, w) {
  switch (pattern) {
    case "dashed": return `stroke-dasharray="${Math.max(3, w * 3)} ${Math.max(2, w * 2)}"`;
    case "dotted": return `stroke-dasharray="0.01 ${Math.max(2.5, w * 2.5)}" stroke-linecap="round"`;
    case "dashDot": return `stroke-dasharray="${Math.max(4, w * 4)} ${Math.max(2, w * 2)} 0.01 ${Math.max(2, w * 2)}" stroke-linecap="round"`;
    default: return "";
  }
}

let gradientID = 0;

/** Draw the shapes of the chips under `root` (call after they're in the page). */
export function drawTagShapes(root) {
  const chips = [...root.querySelectorAll(".tg:not([data-drawn])")];
  const sizes = chips.map((el) => [el.offsetWidth, el.offsetHeight]);   // measure all first: one layout pass
  chips.forEach((el, i) => {
    const [w, h] = sizes[i];
    if (!w || !h) return;
    el.dataset.drawn = "1";
    const shape = el.dataset.shape;
    if (shape === "dot") return;
    const { fill, grad, stroke, pattern } = el.dataset;
    const sw = Number(el.dataset.width) || 1;
    let defs = "", fillAttr = fill;
    if (grad) {
      const id = `tg-grad-${++gradientID}`;
      defs = `<defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${mix(grad, "#fff", 0.35)}"/><stop offset=".5" stop-color="${grad}"/><stop offset="1" stop-color="${mix(grad, "#000", 0.18)}"/></linearGradient></defs>`;
      fillAttr = `url(#${id})`;
    }
    const fillShape = shape === "bracket" || shape === "underline" ? "square" : shape;
    let svg = defs;
    if (fillAttr) svg += `<path d="${shapePath(fillShape, w, h)}" fill="${fillAttr}"/>`;
    if (stroke) {
      svg += `<path d="${shapePath(shape, w, h)}" fill="none" stroke="${stroke}" stroke-width="${sw}" ${dash(pattern, sw)}/>`;
      if (pattern === "double") {
        if (shape === "underline") svg += `<path d="M0,${h - sw - 2} H${w}" stroke="${stroke}" stroke-width="${sw}"/>`;
        else {
          const inset = sw + 1.5;
          svg += `<path transform="translate(${inset},${inset})" d="${shapePath(shape, w - inset * 2, h - inset * 2)}" fill="none" stroke="${stroke}" stroke-width="${sw}"/>`;
        }
      }
    }
    el.insertAdjacentHTML("afterbegin", `<svg class="tg-bg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true">${svg}</svg>`);
  });
}
