// Run: node tests/model.test.js
const M = require("../Model.js");

let failed = 0;
function ok(name, cond) {
  console.log((cond ? "PASS " : "FAIL ") + name);
  if (!cond) failed++;
}
function near(a, b, eps) { return Math.abs(a - b) <= (eps || 0.001); }

// normalizeAddress
ok("normalizeAddress adds 0x", M.normalizeAddress("55d1aa") === "0x55d1aa");
ok("normalizeAddress keeps 0x", M.normalizeAddress("0x55D1AA") === "0x55d1aa");
ok("normalizeAddress rejects junk", M.normalizeAddress("nope!") === "");
ok("normalizeAddress rejects empty", M.normalizeAddress("") === "");

// eligibleClients
const tops = [
  { address: "aa1", urgent: true, lastIpcObject: { class: "kitty", title: "shell", at: [0, 0], size: [800, 1000], workspace: { id: 1 } } },
  { address: "bb2", lastIpcObject: { class: "firefox", title: "web", at: [800, 0], size: [1200, 1000], workspace: { id: 1 } } },
  { address: "cc3", lastIpcObject: { class: "other", title: "elsewhere", at: [0, 0], size: [400, 400], workspace: { id: 2 } } },
  { address: "dd4", lastIpcObject: { class: "float", title: "f", at: [50, 50], size: [300, 200], workspace: { id: 1 }, floating: true } },
  { address: "ee5", lastIpcObject: { class: "unmapped", title: "u", at: [0, 0], size: [10, 10], workspace: { id: 1 }, mapped: false } },
];
const elig = M.eligibleClients(tops, 1);
ok("eligibleClients keeps only tiled mapped on workspace", elig.length === 2);
ok("eligibleClients captured classes", elig.map(c => c.appClass).sort().join(",") === "firefox,kitty");
ok("eligibleClients normalized address", elig[0].address === "0xaa1");
ok("eligibleClients excludes floating by default", elig.every(c => c.floating === false));
ok("eligibleClients reads urgent off the live toplevel, not the ipc dump",
  elig.find(c => c.appClass === "kitty").urgent === true
  && elig.find(c => c.appClass === "firefox").urgent === false);
ok("eligibleClients keeps a reference to the live toplevel",
  elig.find(c => c.appClass === "kitty").toplevelRef === tops[0]);

const eligFloat = M.eligibleClients(tops, 1, true);
ok("eligibleClients includes floating when asked", eligFloat.length === 3);
ok("eligibleClients still excludes unmapped with floating on",
  eligFloat.map(c => c.appClass).indexOf("unmapped") === -1);
ok("eligibleClients flags the floating window",
  eligFloat.filter(c => c.floating).map(c => c.appClass).join(",") === "float");

// orderByPosition
const shuffled = [
  { address: "0xb", x: 800, y: 0, w: 100, h: 100 },
  { address: "0xa", x: 0, y: 0, w: 100, h: 100 },
  { address: "0xc", x: 1600, y: 0, w: 100, h: 100 },
];
ok("orderByPosition sorts left to right",
  M.orderByPosition(shuffled, false).map(c => c.address).join("") === "0xa0xb0xc");
ok("orderByPosition vertical sorts top to bottom",
  M.orderByPosition([{ address: "0xlow", x: 0, y: 500, w: 1, h: 1 }, { address: "0xhi", x: 0, y: 0, w: 1, h: 1 }], true)
    .map(c => c.address).join("") === "0xhi0xlow");

// computeStrip: along-axis size comes from the window's own aspect ratio
// against the dock's fixed cross-axis size (`crossSize`) — never the other
// way around. Signature: (clients, crossSize, gap, minCell, maxAlong, vertical, viewport)
const strip = M.computeStrip(
  [{ address: "0xa", x: 0, y: 0, w: 100, h: 100 }, { address: "0xb", x: 100, y: 0, w: 300, h: 100 }],
  100, 3, 10, 10000, false);
ok("computeStrip count", strip.length === 2);
ok("computeStrip first offset is 0", strip[0].offset === 0);
ok("computeStrip square window -> size matches crossSize", near(strip[0].size, 100, 0.01));
ok("computeStrip wide window (3:1) -> size is 3x crossSize", near(strip[1].size, 300, 0.01));
ok("computeStrip gap respected", near(strip[1].offset, strip[0].size + 3, 0.01));
ok("computeStrip carries the floating flag through",
  M.computeStrip([{ address: "0xa", x: 0, w: 100, h: 100, floating: true }], 100, 0, 10, 10000, false)[0].floating === true);
ok("computeStrip carries urgent and the toplevel reference through", (function () {
  var ref = { fake: "toplevel" };
  var out = M.computeStrip([{ address: "0xa", x: 0, w: 100, h: 100, urgent: true, toplevelRef: ref }], 100, 0, 10, 10000, false);
  return out[0].urgent === true && out[0].toplevelRef === ref;
})());

// computeStrip: a tall window narrows on a horizontal dock (cross-axis —
// height — never changes; only the along-axis — width — does)...
const tallHoriz = M.computeStrip([{ address: "0xa", x: 0, w: 100, h: 300 }], 100, 0, 10, 10000, false);
ok("computeStrip tall window on a horizontal dock -> narrower than crossSize",
  near(tallHoriz[0].size, 100 / 3, 0.01));
// ...and the same real shape narrows the opposite way on a vertical dock,
// where the along axis is height and the cross axis (width) is fixed.
const wideVert = M.computeStrip([{ address: "0xa", y: 0, w: 300, h: 100 }], 100, 0, 10, 10000, true);
ok("computeStrip wide window on a vertical dock -> shorter than crossSize",
  near(wideVert[0].size, 100 / 3, 0.01));

// computeStrip: minimum cell honored when a window's derived size is tiny
const tiny = M.computeStrip(
  [{ address: "0xa", x: 0, y: 0, w: 10, h: 1000 }], 50, 0, 20, 10000, false);
ok("computeStrip honors minCell for an extreme aspect ratio", near(tiny[0].size, 20, 0.001));

ok("computeStrip empty -> []", M.computeStrip([], 100, 3, 10, 10000, false).length === 0);

// computeStrip: maxAlong squeezes every tile by the same factor rather than
// letting the dock grow without bound, preserving their relative proportions.
const squeezed = M.computeStrip([
  { address: "0xa", x: 0, w: 1000, h: 100 },  // raw size 1000 (crossSize 100 * ratio 10)
  { address: "0xb", x: 1, w: 500, h: 100 }    // raw size 500  (crossSize 100 * ratio 5)
], 100, 0, 10, 300, false);
ok("computeStrip squeeze fits the cap", near(squeezed[1].offset + squeezed[1].size, 300, 0.01));
ok("computeStrip squeeze preserves relative proportions",
  near(squeezed[0].size / squeezed[1].size, 2, 0.01));

// computeStrip: without a viewport every cell is fully visible
const noView = M.computeStrip(
  [{ address: "0xa", x: 0, y: 0, w: 100, h: 100 }, { address: "0xb", x: 5000, y: 0, w: 100, h: 100 }],
  100, 0, 10, 10000, false);
ok("computeStrip no viewport -> visibleFraction 1", noView.every(c => c.visibleFraction === 1 && c.onScreen));

// computeStrip: viewport marks which windows are on screen and by how much
const view = { start: 0, end: 1920 };
const vp = M.computeStrip([
  { address: "0xoff", x: -2000, y: 0, w: 900, h: 100 },   // fully scrolled off left
  { address: "0xhalf", x: -450, y: 0, w: 900, h: 100 },   // half in view
  { address: "0xin", x: 500, y: 0, w: 900, h: 100 },       // fully in view
  { address: "0xright", x: 4000, y: 0, w: 900, h: 100 },   // off right
], 100, 0, 10, 10000, false, view);
ok("computeStrip viewport: off-left not on screen",
  vp[0].onScreen === false && vp[0].visibleFraction === 0);
ok("computeStrip viewport: half-in reports ~0.5",
  near(vp[1].visibleFraction, 0.5, 0.01) && vp[1].onScreen);
ok("computeStrip viewport: fully-in reports 1", near(vp[2].visibleFraction, 1, 0.001));
ok("computeStrip viewport: off-right not on screen", vp[3].onScreen === false);
ok("computeStrip viewport: order preserved by position",
  vp.map(c => c.address).join(",") === "0xoff,0xhalf,0xin,0xright");

// computeStrip: vertical viewport uses Y
const vView = M.computeStrip(
  [{ address: "0xa", x: 0, y: -50, w: 100, h: 100 }, { address: "0xb", x: 0, y: 200, w: 100, h: 100 }],
  100, 0, 10, 10000, true, { start: 0, end: 180 });
ok("computeStrip vertical viewport: partial top window on screen",
  near(vView[0].visibleFraction, 0.5, 0.01) && vView[0].onScreen);
ok("computeStrip vertical viewport: window past bottom is off",
  vView[1].onScreen === false);

// stripLength
ok("stripLength empty -> 0", M.stripLength([]) === 0);
ok("stripLength single cell -> its far edge", M.stripLength([{ offset: 0, size: 40 }]) === 40);
ok("stripLength multiple cells -> the last cell's far edge",
  M.stripLength([{ offset: 0, size: 40 }, { offset: 48, size: 60 }]) === 108);

// overlapFraction
ok("overlapFraction full", M.overlapFraction(0, 100, -10, 200) === 1);
ok("overlapFraction none", M.overlapFraction(0, 100, 200, 300) === 0);
ok("overlapFraction partial", near(M.overlapFraction(0, 100, 50, 999), 0.5, 0.001));
ok("overlapFraction zero-width span -> 0", M.overlapFraction(50, 50, 0, 100) === 0);
ok("overlapFraction tolerates reversed bounds", near(M.overlapFraction(0, 100, 999, 50), 0.5, 0.001));

// size presets
ok("isSize accepts the three presets", M.isSize("small") && M.isSize("medium") && M.isSize("large"));
ok("isSize rejects junk", M.isSize("huge") === false);
ok("sizePx returns the preset value", M.sizePx("small") === M.SIZE_PX.small);
ok("sizePx falls back to medium for unknown names", M.sizePx("nope") === M.SIZE_PX.medium);
ok("nearestSize exact match", M.nearestSize(M.SIZE_PX.large) === "large");
ok("nearestSize snaps down near the low end", M.nearestSize(20) === "small");
ok("nearestSize snaps up near the high end", M.nearestSize(200) === "large");
ok("nearestSize picks the midpoint's nearer neighbor",
  M.nearestSize((M.SIZE_PX.small + M.SIZE_PX.medium) / 2 - 1) === "small");

// nerdGlyph
ok("nerdGlyph maps a known class", M.nerdGlyph("firefox") === "");
ok("nerdGlyph resolves reverse-DNS via last segment",
  M.nerdGlyph("org.gnome.Nautilus") === M.nerdGlyph("nautilus"));
ok("nerdGlyph resolves prefix before dash", M.nerdGlyph("google-chrome-stable") === M.nerdGlyph("google-chrome"));
ok("nerdGlyph unknown class -> fallback", M.nerdGlyph("some-random-app") === M.NERD_FALLBACK);
ok("nerdGlyph empty -> fallback", M.nerdGlyph("") === M.NERD_FALLBACK);

console.log(failed === 0 ? "\nALL PASS" : `\n${failed} FAILED`);
process.exit(failed === 0 ? 0 : 1);
