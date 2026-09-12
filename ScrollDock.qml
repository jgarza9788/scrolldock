pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Model.js" as Model

// A resizable, edge-anchored dock for the Hyprland scrolling layout: every
// window on a monitor's active workspace is drawn as a tile whose size tracks
// the window's real on-screen extent, in the same order the layout shows
// them. One DockPanel (a PanelWindow) per connected screen, each showing that
// screen's own workspace — the same per-monitor scope as jgarza.scrollmap,
// just as its own floating element instead of a bar widget.
//
// Config is read from this plugin's entry in `~/.config/omarchy/shell.json`
// (the `plugins` array) — see README.md for the full key list. Manual
// show/hide is wired to the shell's summon/hide/toggle verbs (`opened`
// defaults to true, so the dock is present as soon as the shell starts).
// Edge-hover auto-hide is a separate, independent setting (`autoHide`).
Item {
  id: root

  // Injected by the Omarchy shell loader.
  property var shell: null
  property var manifest: null
  readonly property string pluginId: String((manifest && manifest.id) || "jgarza.scrolldock")

  // ── Config (this plugin's object entry in shell.json's `plugins` array) ──
  readonly property var pluginEntry: {
    var cfg = shell && shell.shellConfig ? shell.shellConfig : null
    var plugins = cfg && Array.isArray(cfg.plugins) ? cfg.plugins : []
    for (var i = 0; i < plugins.length; i++)
      if (plugins[i] && String(plugins[i].id || "") === root.pluginId)
        return plugins[i]
    return null
  }
  function opt(key, fallback) {
    var v = root.pluginEntry ? root.pluginEntry[key] : undefined
    return (v === undefined || v === null) ? fallback : v
  }

  // Most settings below are plain (non-readonly) properties, each seeded from
  // config as its initial value: the settings panel (SettingsPanel.qml) and
  // the resize grip change them live at runtime and persist the change back
  // into shell.json via `persistSetting`.
  property string edge: {
    var e = String(root.opt("edge", "bottom")).toLowerCase()
    return (e === "top" || e === "left" || e === "right") ? e : "bottom"
  }
  readonly property bool vertical: root.edge === "left" || root.edge === "right"
  property string monitorFilter: String(root.opt("monitor", "all"))

  // The dock's thickness preset — one of Model.SIZES ("small"/"medium"/
  // "large"). `cellSize` is the derived pixel value everything else uses.
  property string size: {
    var s = String(root.opt("size", "medium"))
    return Model.isSize(s) ? s : "medium"
  }
  readonly property int cellSize: Model.sizePx(root.size)

  // Low by default (matches scrollmap's own minCell) — a narrow sliver of a
  // window should draw as a narrow sliver of a tile, not get padded out to a
  // "stays clickable" width. Raise it in shell.json if you'd rather trade
  // shape accuracy for an easier click target.
  readonly property int minCell: Math.max(4, Math.round(Number(root.opt("minCell", 6))))
  readonly property int maxLength: Math.max(200, Math.round(Number(root.opt("maxLength", 900))))
  readonly property int cellGap: Math.max(0, Math.round(Number(root.opt("gap", 8))))
  readonly property int edgeMargin: Math.max(0, Math.round(Number(root.opt("margin", 8))))
  readonly property int padding: Math.max(0, Math.round(Number(root.opt("padding", 6))))

  // Backdrop alpha, stored 0-1 (`Item.opacity` is already taken, hence the
  // "bg" prefix). The settings-panel slider works in whole percent.
  property real bgOpacity: Math.max(0.1, Math.min(1, Number(root.opt("opacity", 0.55))))

  property string iconMode: {
    var m = String(root.opt("iconMode", "icons"))
    return (m === "none" || m === "icons" || m === "nerdfont" || m === "thumbnail") ? m : "icons"
  }
  // Unlike scrollmap (tiling-only mini-map), the dock defaults floating
  // windows ON — a dock is meant to represent everything on the desktop.
  property bool showFloating: root.opt("showFloating", true) === true
  property bool dimInactive: root.opt("dimInactive", true) === true
  property bool animate: root.opt("animate", true) === true
  property bool middleClickClose: root.opt("middleClickClose", true) === true

  property string hoverEffect: {
    var h = String(root.opt("hoverEffect", "magnify"))
    return (h === "magnify" || h === "lift" || h === "none") ? h : "magnify"
  }
  readonly property real magnifyScale: Math.max(1, Math.min(2.2, Number(root.opt("magnifyScale", 1.35))))
  readonly property int magnifyRadius: Math.max(20, Math.round(Number(root.opt("magnifyRadius", 80))))

  property bool autoHide: root.opt("autoHide", false) === true
  readonly property int autoHideDelayMs: Math.max(0, Math.round(Number(root.opt("autoHideDelayMs", 400))))
  readonly property int revealMs: Math.max(0, Math.round(Number(root.opt("revealMs", 160))))
  readonly property int hotZoneSize: Math.max(1, Math.min(16, Math.round(Number(root.opt("hotZoneSize", 4)))))

  // Played once per monitor whenever that monitor's active workspace changes
  // (not on every window open/close — see DockPanel's onWorkspaceIdChanged).
  property string transitionEffect: {
    var t = String(root.opt("transitionEffect", "fade"))
    return (t === "none" || t === "fade" || t === "blur" || t === "slide"
      || t === "zoom" || t === "glitch") ? t : "fade"
  }
  readonly property int transitionMs: Math.max(0, Math.round(Number(root.opt("transitionMs", 260))))

  // ── Manual show/hide (shell summon/hide/toggle verbs) ────────────────────
  // Defaults to visible — a dock is an always-on element until you hide it.
  property bool opened: true
  function open(payloadJson) {
    root.opened = true
    try {
      var p = payloadJson ? (typeof payloadJson === "string" ? JSON.parse(payloadJson) : payloadJson) : null
      if (p && p.navigate === true)
        root.navMode = true
    } catch (e) {
    }
  }
  function close() {
    root.opened = false
    root.navMode = false
  }
  function toggle() { root.opened ? root.close() : root.open("{}") }
  // Aliases, in case the loader calls these names instead.
  function summon(payloadJson) { root.open(payloadJson) }
  function hide() { root.close() }

  // ── Keyboard navigation ──────────────────────────────────────────────────
  // Off by default — a dock that permanently grabbed keyboard focus would
  // steal every keystroke from whatever you're actually doing. Only the
  // monitor currently focused enters nav mode (see DockPanel.navActive), and
  // only when explicitly requested:
  //   omarchy-shell shell summon jgarza.scrolldock '{"navigate": true}'
  // Arrow keys move the selection, Enter focuses it, Esc exits.
  property bool navMode: false
  function closeNav() { root.navMode = false }

  // ── Settings panel (right-click the dock to open it) ────────────────────
  property bool settingsOpen: false
  property var settingsScreen: null
  function openSettings(screen) {
    root.settingsScreen = screen
    root.settingsOpen = true
  }
  function closeSettings() { root.settingsOpen = false }
  function toggleSettings(screen) {
    if (root.settingsOpen && root.settingsScreen === screen)
      root.closeSettings()
    else
      root.openSettings(screen)
  }

  // Write one key back into this plugin's shell.json entry. The in-memory
  // property is the source of truth for the running shell; this just makes
  // the change survive a restart.
  function persistSetting(key, value) {
    if (root.shell && typeof root.shell.updateEntryInline === "function") {
      var cur = Object.assign({ id: root.pluginId }, root.pluginEntry || {})
      cur[key] = value
      root.shell.updateEntryInline(root.pluginId, cur)
    }
  }

  function commitSize(name) {
    root.size = Model.isSize(name) ? name : "medium"
    root.persistSetting("size", root.size)
  }

  // The opacity slider previews live while dragging (no disk write per
  // pixel of motion) and persists once on release, same split as size used
  // to use for the resize grip.
  function previewBgOpacity(percent) {
    root.bgOpacity = Math.max(0.1, Math.min(1, Number(percent) / 100))
  }
  function setBgOpacity(percent) {
    root.previewBgOpacity(percent)
    root.persistSetting("opacity", root.bgOpacity)
  }

  function setEdge(value) {
    var v = String(value || "bottom")
    root.edge = (v === "top" || v === "left" || v === "right" || v === "bottom") ? v : "bottom"
    root.persistSetting("edge", root.edge)
  }
  function setMonitor(name) {
    root.monitorFilter = String(name || "all")
    root.persistSetting("monitor", root.monitorFilter)
  }
  function setIconMode(value) {
    var v = String(value || "icons")
    root.iconMode = (v === "none" || v === "icons" || v === "nerdfont" || v === "thumbnail") ? v : "icons"
    root.persistSetting("iconMode", root.iconMode)
  }
  function setHoverEffect(value) {
    var v = String(value || "magnify")
    root.hoverEffect = (v === "magnify" || v === "lift" || v === "none") ? v : "magnify"
    root.persistSetting("hoverEffect", root.hoverEffect)
  }
  function setTransitionEffect(value) {
    var v = String(value || "fade")
    root.transitionEffect = (v === "none" || v === "fade" || v === "blur" || v === "slide"
      || v === "zoom" || v === "glitch") ? v : "fade"
    root.persistSetting("transitionEffect", root.transitionEffect)
  }
  function setAutoHide(value) {
    root.autoHide = value === true
    root.persistSetting("autoHide", root.autoHide)
  }
  function setShowFloating(value) {
    root.showFloating = value === true
    root.persistSetting("showFloating", root.showFloating)
  }
  function setDimInactive(value) {
    root.dimInactive = value === true
    root.persistSetting("dimInactive", root.dimInactive)
  }
  function setAnimate(value) {
    root.animate = value === true
    root.persistSetting("animate", root.animate)
  }
  function setMiddleClickClose(value) {
    root.middleClickClose = value === true
    root.persistSetting("middleClickClose", root.middleClickClose)
  }

  // ── Scrolling-layout probe, shared by every monitor's dock ───────────────
  property string layoutName: ""
  readonly property bool scrolling: root.layoutName === "scrolling"

  function probeLayout() {
    if (!layoutProbe.running)
      layoutProbe.running = true
  }

  Process {
    id: layoutProbe
    command: ["hyprctl", "getoption", "general:layout", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          root.layoutName = String(parsed.str || "").trim()
        } catch (e) {
        }
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.probeLayout()
  }

  // ── Live-update tick, shared by every monitor's dock ──────────────────────
  property int tick: 0

  function bump() {
    Hyprland.refreshToplevels()
    if (Hyprland.refreshMonitors)
      Hyprland.refreshMonitors()
    root.tick = (root.tick + 1) & 0x3fffffff
  }

  function burst() {
    root.bump()
    burstTimer.count = 0
    burstTimer.restart()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name)
        return
      var n = String(event.name)
      if (n === "configreloaded") {
        root.probeLayout()
        root.burst()
        return
      }
      if (n.indexOf("window") !== -1 || n.indexOf("workspace") !== -1
          || n.indexOf("monitor") !== -1 || n === "changefloatingmode"
          || n === "fullscreen" || n === "activelayout" || n === "urgent")
        root.burst()
    }
  }

  // Fast poll that runs for ~2s after an event, then stops.
  Timer {
    id: burstTimer
    interval: 180
    repeat: true
    property int count: 0
    onTriggered: {
      root.bump()
      if (++count >= 11)
        stop()
    }
  }

  // Safety net for viewport shifts that raise no event (plain scroll binds).
  Timer {
    interval: 2500
    running: root.opened && root.scrolling
    repeat: true
    onTriggered: root.bump()
  }

  // Resolve an application icon from its window class. The shell's app
  // library does proper desktop-entry matching; fall back to a raw
  // icon-theme lookup.
  function resolveIcon(cls) {
    var value = String(cls || "")
    if (!value)
      return ""
    if (root.shell && root.shell.appLibrary)
      return root.shell.appLibrary.iconSource(value)
    var direct = Quickshell.iconPath(value, true)
    return direct ? direct : Quickshell.iconPath(value.toLowerCase(), true)
  }

  function focusClient(address) {
    var a = Model.normalizeAddress(address)
    if (!a)
      return
    if (Hyprland.usingLua)
      Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + a + "\" })")
    else
      Hyprland.dispatch("focuswindow address:" + a)
  }

  // Middle-click a tile to close that window, same address-targeting as
  // focusClient.
  function closeClient(address) {
    var a = Model.normalizeAddress(address)
    if (!a)
      return
    if (Hyprland.usingLua)
      Hyprland.dispatch("hl.dsp.window.close({ window = \"address:" + a + "\" })")
    else
      Hyprland.dispatch("closewindow address:" + a)
  }

  // ── Per-monitor overrides (shell.json-only: `perMonitor.<screen name>`) ──
  // A monitor not listed here — or every monitor, if the key is absent —
  // just gets the global `edge`/`size` above. There's no settings-panel UI
  // for this (it would need a "which monitor am I editing" concept the panel
  // doesn't have), so it's read once from config, not a live setter.
  readonly property var perMonitor: {
    var v = root.opt("perMonitor", null)
    return (v && typeof v === "object" && !Array.isArray(v)) ? v : {}
  }
  function effectiveEdge(screenName) {
    var o = root.perMonitor[screenName]
    var e = o && o.edge !== undefined ? String(o.edge).toLowerCase() : ""
    return (e === "top" || e === "left" || e === "right" || e === "bottom") ? e : root.edge
  }
  function effectiveVertical(screenName) {
    var e = root.effectiveEdge(screenName)
    return e === "left" || e === "right"
  }
  function effectiveSize(screenName) {
    var o = root.perMonitor[screenName]
    var s = o && o.size !== undefined ? String(o.size) : ""
    return Model.isSize(s) ? s : root.size
  }
  function effectiveCellSize(screenName) {
    return Model.sizePx(root.effectiveSize(screenName))
  }

  // Screens this dock should appear on: every connected screen by default,
  // or a single named monitor when `monitor` is set to something other than
  // "all".
  readonly property var activeScreens: {
    var _dep = root.monitorFilter
    var all = Quickshell.screens || []
    if (root.monitorFilter === "all")
      return all
    var out = []
    for (var i = 0; i < all.length; i++)
      if (all[i] && String(all[i].name) === root.monitorFilter)
        out.push(all[i])
    return out
  }

  Component.onCompleted: {
    root.probeLayout()
  }

  // ── One dock per matching screen ─────────────────────────────────────────
  Variants {
    model: root.activeScreens
    delegate: Component {
      DockPanel {
        dockRoot: root
      }
    }
  }

  // ── One shared settings panel, shown on whichever screen it was opened from ──
  SettingsPanel {
    dockRoot: root
  }
}
