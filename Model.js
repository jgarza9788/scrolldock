// Pure helpers for the Scroll Dock overlay. Imported as `import "Model.js" as
// Model`, and ES5-only so the same file runs under `node tests/model.test.js`.
//
// This is the same geometry/label math as jgarza.scrollmap's Model.js (same
// author) — a dock tile and a mini-map cell are the same shape problem, just
// drawn in a different surface.

// Hyprland/Quickshell report client addresses inconsistently: sometimes a bare
// hex string, sometimes already 0x-prefixed. Normalize to a lowercase 0x form,
// or "" when the value is not a hex address.
function normalizeAddress(value) {
  var raw = String(value || "").trim().toLowerCase()
  if (raw.indexOf("0x") === 0) raw = raw.slice(2)
  return /^[0-9a-f]+$/.test(raw) && raw.length > 0 ? "0x" + raw : ""
}

function ipcOf(toplevel) {
  var ipc = toplevel && toplevel.lastIpcObject
  return ipc && typeof ipc === "object" ? ipc : {}
}

function workspaceIdOf(ipc) {
  var ws = ipc && ipc.workspace
  if (!ws) return NaN
  var id = Number(ws.id)
  return isFinite(id) ? id : NaN
}

// Reduce the full toplevel list to the tiled, mapped windows that live on the
// given workspace, each described by the geometry the dock needs. Floating
// windows are excluded unless `includeFloating` is set.
function eligibleClients(toplevels, workspaceId, includeFloating) {
  var list = toplevels || []
  var target = Number(workspaceId)
  var withFloating = includeFloating === true
  var out = []

  for (var i = 0; i < list.length; i++) {
    var top = list[i]
    if (!top) continue
    var ipc = ipcOf(top)

    if (ipc.mapped === false) continue
    if (ipc.floating === true && !withFloating) continue
    if (ipc.hidden === true) continue
    if (isFinite(target) && workspaceIdOf(ipc) !== target) continue

    var at = ipc.at || []
    var size = ipc.size || []
    var x = Number(at[0])
    var y = Number(at[1])
    var w = Number(size[0])
    var h = Number(size[1])
    if (!isFinite(x) || !isFinite(y) || !(w > 0) || !(h > 0)) continue

    out.push({
      address: normalizeAddress(top.address || ipc.address),
      appClass: String(ipc.class || ipc.initialClass || ""),
      title: String(top.title || ipc.title || ipc.class || ""),
      floating: ipc.floating === true,
      // `urgent` lives on the live toplevel wrapper itself, not in the raw
      // ipc JSON dump on every Hyprland version — read it off `top` directly.
      urgent: top.urgent === true,
      // The live toplevel object, kept around (not just its plain data) so a
      // "thumbnail" tile can screencopy `toplevelRef.wayland` directly.
      toplevelRef: top,
      x: x,
      y: y,
      w: w,
      h: h
    })
  }

  return out
}

// Left-to-right for a horizontal dock, top-to-bottom for a vertical one. The
// off-axis coordinate is the tiebreaker so stacked splits keep a stable order.
function orderByPosition(clients, vertical) {
  var copy = (clients || []).slice()
  copy.sort(function (a, b) {
    var primary = vertical ? a.y - b.y : a.x - b.x
    if (primary !== 0) return primary
    var secondary = vertical ? a.x - b.x : a.y - b.y
    if (secondary !== 0) return secondary
    return String(a.address).localeCompare(String(b.address))
  })
  return copy
}

// How much of [start, end] falls inside [lo, hi], as a fraction of (end - start).
function overlapFraction(start, end, lo, hi) {
  var span = end - start
  if (!(span > 0)) return 0
  var a = Math.max(start, Math.min(lo, hi))
  var b = Math.min(end, Math.max(lo, hi))
  return b > a ? (b - a) / span : 0
}

// Turn ordered clients into positioned cells, each sized along the dock's
// length from its own aspect ratio against the dock's fixed cross-axis size
// (`crossSize` — the dock's thickness, e.g. a horizontal dock's height) —
// never the other way around: the dock's thickness never changes, only a
// tile's length does. A square window's tile comes out roughly as long as
// the dock is thick; a wide window's tile is longer, a tall window's
// shorter — down to `minCell` so an extreme aspect ratio stays clickable.
//
// If every tile's natural length together would exceed `maxAlong`, every
// tile is shrunk by the same factor so the dock still fits on screen — this
// keeps tiles' lengths proportional to each other even when squeezed, it
// just can no longer promise each one matches its window's ratio exactly.
//
// `viewport` (optional) is { start, end } in the same compositor coordinates as
// the clients' positions, along the active axis. Each cell then reports how much
// of its window is currently inside the monitor's visible region. The dock does
// not draw this (that's scrollmap's job) but the math stays so the two models
// can share tests/behaviour.
function computeStrip(clients, crossSize, gap, minCell, maxAlong, vertical, viewport) {
  var ordered = orderByPosition(clients, vertical)
  var n = ordered.length
  if (n === 0) return []

  var view = viewport && isFinite(viewport.start) && isFinite(viewport.end)
    && viewport.end > viewport.start ? viewport : null

  var cross = Math.max(1, Number(crossSize) || 1)
  var g = Math.max(0, Number(gap) || 0)
  var floor = Math.max(1, Number(minCell) || 1)
  var cap = Math.max(1, Number(maxAlong) || Infinity)

  var rawSizes = ordered.map(function (c) {
    var w = c.w > 0 ? c.w : 1
    var h = c.h > 0 ? c.h : 1
    var alongRatio = vertical ? (h / w) : (w / h)
    return Math.max(floor, cross * alongRatio)
  })

  var totalGaps = g * Math.max(0, n - 1)
  var totalRaw = rawSizes.reduce(function (sum, s) { return sum + s }, 0)
  var scale = (totalRaw + totalGaps) > cap && totalRaw > 0
    ? Math.max(0, cap - totalGaps) / totalRaw
    : 1
  var sizes = rawSizes.map(function (s) { return s * scale })

  var offset = 0
  return ordered.map(function (client, i) {
    var winStart = vertical ? client.y : client.x
    var winEnd = winStart + (vertical ? client.h : client.w)
    var visibleFraction = view
      ? overlapFraction(winStart, winEnd, view.start, view.end)
      : 1

    var cell = {
      address: client.address,
      appClass: client.appClass,
      title: client.title,
      floating: client.floating === true,
      urgent: client.urgent === true,
      toplevelRef: client.toplevelRef,
      size: sizes[i],
      offset: offset,
      visibleFraction: visibleFraction,
      onScreen: visibleFraction > 0.02
    }
    offset += sizes[i] + g
    return cell
  })
}

// Total along-axis extent of a computeStrip() result (its last cell's far
// edge) — the dock's natural length, before any centering/anchoring.
function stripLength(cells) {
  if (!cells || cells.length === 0)
    return 0
  var last = cells[cells.length - 1]
  return last.offset + last.size
}

// ---- Dock thickness presets -----------------------------------------------
// Three sizes, named rather than an arbitrary pixel value — easy to pick from
// the settings panel.
var SIZES = ["small", "medium", "large"]
var SIZE_PX = { small: 28, medium: 40, large: 56 }

function isSize(value) {
  return SIZES.indexOf(value) !== -1
}

// Pixel thickness for a named size, falling back to "medium" for anything
// unrecognized (a stale/typo'd config value, for instance).
function sizePx(name) {
  return SIZE_PX[name] || SIZE_PX.medium
}

// The named size whose pixel thickness is closest to `px`.
function nearestSize(px) {
  var value = Number(px)
  var best = "medium"
  var bestDist = Infinity
  for (var i = 0; i < SIZES.length; i++) {
    var name = SIZES[i]
    var dist = Math.abs(SIZE_PX[name] - value)
    if (dist < bestDist) {
      bestDist = dist
      best = name
    }
  }
  return best
}

// ---- Cell labels ---------------------------------------------------------
// `iconMode === "nerdfont"` draws one glyph per cell, looked up from the
// window class. The shell's default font already resolves to a Nerd Font, so
// these are just the private-use codepoints. Anything not in the table gets a
// plain window glyph — a starter set, easy to extend.
var NERD_FALLBACK = "" // window-maximize

var NERD_GLYPHS = {
  "firefox": "",
  "firefox-developer-edition": "",
  "chromium": "",
  "chrome": "",
  "google-chrome": "",
  "brave-browser": "",
  "brave": "",
  "code": "",
  "codium": "",
  "vscodium": "",
  "kitty": "",
  "alacritty": "",
  "foot": "",
  "ghostty": "",
  "wezterm": "",
  "discord": "",
  "slack": "",
  "spotify": "",
  "telegram": "",
  "thunderbird": "",
  "nautilus": "",
  "thunar": "",
  "pcmanfm": "",
  "nemo": "",
  "dolphin": "",
  "gimp": "",
  "blender": "",
  "steam": "",
  "mpv": "",
  "vlc": "",
  "obsidian": "",
  "zoom": ""
}

// Resolve a window class to a Nerd Font glyph. Tries the class as given,
// then its last dotted segment (org.gnome.Nautilus -> nautilus), then the
// class with trailing "-suffix" parts peeled off one at a time
// (google-chrome-stable -> google-chrome -> google).
function nerdGlyph(cls) {
  var key = String(cls || "").trim().toLowerCase().replace(/\.desktop$/, "")
  if (!key) return NERD_FALLBACK
  if (NERD_GLYPHS[key]) return NERD_GLYPHS[key]
  var dot = key.lastIndexOf(".")
  if (dot !== -1 && NERD_GLYPHS[key.slice(dot + 1)]) return NERD_GLYPHS[key.slice(dot + 1)]
  var stem = key
  var dash = stem.lastIndexOf("-")
  while (dash > 0) {
    stem = stem.slice(0, dash)
    if (NERD_GLYPHS[stem]) return NERD_GLYPHS[stem]
    dash = stem.lastIndexOf("-")
  }
  return NERD_FALLBACK
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeAddress: normalizeAddress,
    overlapFraction: overlapFraction,
    eligibleClients: eligibleClients,
    orderByPosition: orderByPosition,
    computeStrip: computeStrip,
    stripLength: stripLength,
    SIZES: SIZES,
    SIZE_PX: SIZE_PX,
    isSize: isSize,
    sizePx: sizePx,
    nearestSize: nearestSize,
    nerdGlyph: nerdGlyph,
    NERD_FALLBACK: NERD_FALLBACK
  }
}
