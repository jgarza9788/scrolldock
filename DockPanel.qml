pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

// One monitor's dock surface: a PanelWindow anchored to a single screen edge,
// sized to its content along the long axis (centered on that edge, the usual
// layer-shell behaviour when only one edge is anchored) and to `cellSize`
// along the short axis. By default floats over windows
// (`ExclusionMode.Ignore`), so resizing / auto-hiding never reflows other
// windows; `dockRoot.reserveSpace` flips it to `ExclusionMode.Auto`, which
// reserves the panel's current on-screen thickness as a layer-shell exclusive
// zone (recomputed live, so combining this with auto-hide still reflows other
// windows as the dock collapses/reveals).
PanelWindow {
  id: panel

  required property var modelData
  required property var dockRoot
  screen: modelData

  visible: dockRoot.opened
  color: "transparent"

  WlrLayershell.namespace: "omarchy-scrolldock"
  WlrLayershell.layer: WlrLayer.Top
  // Exclusive only while this specific panel is actively driving keyboard
  // nav, and dropped back to None the instant an activation is queued (see
  // the focus-restore note by `activating` below) — a dock must never hold
  // keyboard focus outside of that explicit, momentary case.
  WlrLayershell.keyboardFocus: panel.navActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  exclusionMode: dockRoot.reserveSpace ? ExclusionMode.Auto : ExclusionMode.Ignore

  // Resolved per-screen, so `perMonitor` overrides (shell.json-only) can give
  // one monitor a different edge/size than the rest.
  readonly property string screenName: panel.screen ? panel.screen.name : ""
  readonly property bool vertical: dockRoot.effectiveVertical(panel.screenName)
  readonly property string edge: dockRoot.effectiveEdge(panel.screenName)
  readonly property int cellSize: dockRoot.effectiveCellSize(panel.screenName)
  onCellSizeChanged: panel.rebuild()

  // ── Keyboard navigation ──────────────────────────────────────────────────
  // Only the monitor Hyprland currently has focused enters nav mode — with
  // one dock per monitor, grabbing keyboard on all of them at once would be
  // both pointless and confusing about which one is listening.
  readonly property bool navActive: dockRoot.navMode && !panel.activating
    && panel.screenName !== "" && panel.screenName === panel.focusedMonitorName
  readonly property string focusedMonitorName: {
    var _dep = dockRoot.tick
    return Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : ""
  }
  property int navIndex: -1
  property bool activating: false

  onNavActiveChanged: {
    if (panel.navActive) {
      var i = -1
      for (var k = 0; k < panel.cells.length; k++)
        if (panel.cells[k].address === panel.activeAddr) { i = k; break }
      panel.navIndex = i >= 0 ? i : (panel.cells.length > 0 ? 0 : -1)
      panel.revealed = true
      panel.cancelHide()
      Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    } else {
      panel.navIndex = -1
    }
  }

  function navStep(delta) {
    if (panel.cells.length === 0)
      return
    var next = panel.navIndex < 0 ? 0 : panel.navIndex + delta
    panel.navIndex = Math.max(0, Math.min(panel.cells.length - 1, next))
  }

  // Focusing the selected window has to wait until this panel has released
  // its exclusive keyboard grab, or the compositor restores focus to
  // whatever was focused before *after* the activate call, clobbering it
  // (see jgarza.scroll-overview's identical fix for the same race).
  property string pendingActivateAddr: ""
  Timer {
    id: activateTimer
    interval: 70
    onTriggered: {
      panel.activating = false
      if (panel.pendingActivateAddr) {
        dockRoot.focusClient(panel.pendingActivateAddr)
        panel.pendingActivateAddr = ""
      }
    }
  }
  function activateNav() {
    if (panel.navIndex < 0 || panel.navIndex >= panel.cells.length)
      return
    panel.pendingActivateAddr = panel.cells[panel.navIndex].address
    panel.activating = true
    dockRoot.closeNav()
    activateTimer.restart()
  }

  // Only the anchored edge is ever pinned — collapsed or revealed, the dock
  // stays the same width (or height, on a side dock), centered on that edge.
  // Collapsing only changes its thickness, never its length.
  anchors {
    top: panel.edge === "top"
    bottom: panel.edge === "bottom"
    left: panel.edge === "left"
    right: panel.edge === "right"
  }
  // Only the revealed dock gets `edgeMargin`'s breathing room off the screen
  // edge. Collapsed, the sliver sits flush against the true edge (0 margin) —
  // a gap there would be dead space the pointer has to cross before the
  // hover-reveal even notices it.
  readonly property int revealedEdgeMargin: panel.revealed ? dockRoot.edgeMargin : 0
  margins {
    top: panel.edge === "top" ? panel.revealedEdgeMargin : 0
    bottom: panel.edge === "bottom" ? panel.revealedEdgeMargin : 0
    left: panel.edge === "left" ? panel.revealedEdgeMargin : 0
    right: panel.edge === "right" ? panel.revealedEdgeMargin : 0
  }

  // ── This screen's monitor / workspace / clients ──────────────────────────
  function monitorByName(name) {
    var ms = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < ms.length; i++)
      if (ms[i] && String(ms[i].name) === name)
        return ms[i]
    return null
  }

  readonly property var monitor: {
    var _dep = dockRoot.tick
    return panel.monitorByName(String(panel.screen ? panel.screen.name : "")) || null
  }

  readonly property int workspaceId: {
    var m = panel.monitor
    if (m && m.activeWorkspace && isFinite(Number(m.activeWorkspace.id)))
      return Number(m.activeWorkspace.id)
    if (m && m.lastIpcObject && m.lastIpcObject.activeWorkspace
        && isFinite(Number(m.lastIpcObject.activeWorkspace.id)))
      return Number(m.lastIpcObject.activeWorkspace.id)
    return -1
  }

  // Plays `dockRoot.transitionEffect` whenever this monitor's *active
  // workspace* changes (not on every window open/close/move, which also
  // touches `clients` but isn't a workspace switch).
  property int lastWorkspaceId: -1
  onWorkspaceIdChanged: {
    var prev = panel.lastWorkspaceId
    panel.lastWorkspaceId = panel.workspaceId
    if (prev !== -1 && panel.workspaceId !== prev && dockRoot.animate)
      panel.playTransition(panel.workspaceId > prev ? 1 : -1)
  }

  readonly property var clients: {
    var _dep = dockRoot.tick
    if (!dockRoot.scrolling || panel.workspaceId < 0)
      return []
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    return Model.eligibleClients(tops, panel.workspaceId, dockRoot.showFloating)
  }

  readonly property string activeAddr: Model.normalizeAddress(
    Hyprland.activeToplevel ? Hyprland.activeToplevel.address : "")

  // Stable delegate model: replaced only when order, size or focus change.
  property string sig: ""
  property var cells: []
  onCellsChanged: if (panel.navActive)
    panel.navIndex = Math.max(-1, Math.min(panel.cells.length - 1, panel.navIndex))

  // The dock's natural length is whatever computeStrip's aspect-derived
  // tiles add up to (never below one thickness, so it reads as a shape even
  // with zero or one window).
  readonly property real dockLength: Math.max(panel.cellSize, Model.stripLength(panel.cells))

  function rebuild() {
    var next = Model.computeStrip(panel.clients, panel.cellSize, dockRoot.cellGap,
      dockRoot.minCell, dockRoot.maxLength, panel.vertical)
    var s = panel.activeAddr + "|" + next.map(function (c) {
      return c.address + ":" + Math.round(c.offset) + ":" + Math.round(c.size) + (c.floating ? "f" : "")
    }).join(",")
    if (s !== panel.sig) {
      panel.sig = s
      panel.cells = next
    }
  }

  onClientsChanged: panel.rebuild()
  onActiveAddrChanged: panel.rebuild()
  onVerticalChanged: panel.rebuild()

  // ── Auto-hide reveal state ───────────────────────────────────────────────
  // `revealed` is always true when autoHide is off; otherwise it tracks
  // pointer hover over the dock (or the thin hot-zone sliver it collapses to)
  // with a short grace period before hiding again.
  property bool revealed: !dockRoot.autoHide

  readonly property real fullThickness: panel.cellSize + dockRoot.padding * 2
  readonly property real thickness: panel.revealed ? panel.fullThickness : dockRoot.hotZoneSize

  implicitWidth: panel.vertical ? panel.thickness : Math.ceil(panel.dockLength + dockRoot.padding * 2)
  implicitHeight: panel.vertical ? Math.ceil(panel.dockLength + dockRoot.padding * 2) : panel.thickness

  Behavior on implicitWidth {
    enabled: dockRoot.animate
    NumberAnimation { duration: dockRoot.revealMs; easing.type: Easing.OutCubic }
  }
  Behavior on implicitHeight {
    enabled: dockRoot.animate
    NumberAnimation { duration: dockRoot.revealMs; easing.type: Easing.OutCubic }
  }

  function scheduleHide() {
    if (!dockRoot.autoHide)
      return
    hideTimer.restart()
  }
  function cancelHide() { hideTimer.stop() }

  Timer {
    id: hideTimer
    interval: dockRoot.autoHideDelayMs
    onTriggered: if (dockRoot.autoHide) panel.revealed = false
  }

  // Flipping `autoHide` from the settings panel doesn't touch `revealed` on
  // its own — `revealed` only ever changes via imperative assignment (here,
  // the hover handler, the hide timer), so its initializer binding above is
  // long gone by the time a setting changes. React explicitly: turning
  // auto-hide off should reveal the dock and keep it revealed; turning it on
  // should start collapsing unless the pointer is already sitting on it.
  Connections {
    target: dockRoot
    function onAutoHideChanged() {
      if (dockRoot.autoHide) {
        if (!revealHover.hovered)
          panel.scheduleHide()
      } else {
        panel.cancelHide()
        panel.revealed = true
      }
    }
  }

  onVisibleChanged: if (panel.visible) {
    panel.revealed = !dockRoot.autoHide
    dockRoot.bump()
  }

  // Pointer position along the dock's long axis, in dock-content coordinates;
  // -1 when the pointer is not over the dock. Drives the "magnify" hover
  // effect in DockCell.
  property real pointerAxis: -1

  // ── Tile tooltip (window title on hover) ─────────────────────────────────
  function showTooltip(cellItem, text) { tooltip.showFor(cellItem, text) }
  function hideTooltip() { tooltip.hide() }

  TooltipWindow {
    id: tooltip
    panel: panel
  }

  // ── Workspace-change transition ──────────────────────────────────────────
  // The tile swap itself is instant (a plain property/binding update); these
  // just play a short visual effect over it so the change reads as a
  // transition instead of a jump-cut. `dir` is +1/-1 (new workspace id
  // higher/lower than the old one) — only "slide" uses it, to arrive from
  // the side that matches the direction you switched.
  readonly property real slideDistance: Math.max(24, panel.cellSize)
  property real transitionBlur: 0
  property real transitionSlide: 0
  // "glitch": a red ghost and a blue ghost of the tiles, each offset to one
  // side, converge back onto the sharp (unmodified) strip underneath — the
  // classic RGB-channel-split look, minus an actual per-channel split (see
  // the glitchRed/glitchBlue MultiEffects below for why that's not needed).
  property real glitchOffset: 0
  property real glitchGhostOpacity: 0

  function playTransition(dir) {
    fadeAnim.stop()
    blurAnim.stop()
    zoomAnim.stop()
    slideAnim.stop()
    glitchAnim.stop()
    switch (dockRoot.transitionEffect) {
      case "fade":
        stripHolder.opacity = 0
        fadeAnim.restart()
        break
      case "blur":
        panel.transitionBlur = 1
        blurAnim.restart()
        break
      case "zoom":
        stripHolder.opacity = 0
        stripHolder.scale = 0.66
        zoomAnim.restart()
        break
      case "slide":
        stripHolder.opacity = 0
        panel.transitionSlide = dir * panel.slideDistance
        slideAnim.restart()
        break
      case "glitch":
        panel.glitchOffset = panel.slideDistance * 0.8 
        panel.glitchGhostOpacity = 0.85 
        glitchAnim.restart()
        break
      default:
        break // "none"
    }
  }

  NumberAnimation {
    id: fadeAnim
    target: stripHolder
    property: "opacity"
    to: 1
    duration: dockRoot.transitionMs
    easing.type: Easing.OutCubic
  }

  NumberAnimation {
    id: blurAnim
    target: panel
    property: "transitionBlur"
    to: 0
    duration: dockRoot.transitionMs
    easing.type: Easing.InOutSine
  }

  ParallelAnimation {
    id: zoomAnim
    NumberAnimation { target: stripHolder; property: "opacity"; to: 1; duration: dockRoot.transitionMs; easing.type: Easing.OutCubic }
    NumberAnimation { target: stripHolder; property: "scale"; to: 1; duration: dockRoot.transitionMs; easing.type: Easing.OutBack }
  }

  ParallelAnimation {
    id: slideAnim
    NumberAnimation { target: stripHolder; property: "opacity"; to: 1; duration: dockRoot.transitionMs; easing.type: Easing.OutCubic }
    NumberAnimation { target: panel; property: "transitionSlide"; to: 0; duration: dockRoot.transitionMs; easing.type: Easing.OutCubic }
  }

  ParallelAnimation {
    id: glitchAnim
    NumberAnimation { target: panel; property: "glitchOffset"; to: 0; duration: dockRoot.transitionMs; easing.type: Easing.OutBack }
    NumberAnimation { target: panel; property: "glitchGhostOpacity"; to: 0; duration: dockRoot.transitionMs; easing.type: Easing.OutCubic }
  }

  // ── Surface ───────────────────────────────────────────────────────────────
  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: panel.navActive

    Keys.onPressed: function (event) {
      if (!panel.navActive)
        return
      var back = panel.vertical
        ? (event.key === Qt.Key_Up || event.key === Qt.Key_K)
        : (event.key === Qt.Key_Left || event.key === Qt.Key_H)
      var fwd = panel.vertical
        ? (event.key === Qt.Key_Down || event.key === Qt.Key_J)
        : (event.key === Qt.Key_Right || event.key === Qt.Key_L)
      if (event.key === Qt.Key_Escape) {
        dockRoot.closeNav()
        event.accepted = true
      } else if (back) {
        panel.navStep(-1)
        event.accepted = true
      } else if (fwd) {
        panel.navStep(1)
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        panel.activateNav()
        event.accepted = true
      }
    }

    Item {
    id: content
    anchors.fill: parent

    HoverHandler {
      id: revealHover
      enabled: dockRoot.autoHide
      onHoveredChanged: {
        if (hovered) {
          panel.cancelHide()
          panel.revealed = true
        } else {
          panel.scheduleHide()
        }
      }
    }

    HoverHandler {
      id: magnifyHover
      enabled: dockRoot.hoverEffect === "magnify" && panel.revealed
      onPointChanged: {
        panel.pointerAxis = panel.vertical ? point.position.y : point.position.x
      }
      onHoveredChanged: if (!hovered) panel.pointerAxis = -1
    }

    Rectangle {
      id: surface
      anchors.fill: parent
      radius: Math.min(14, dockRoot.padding + 6)
      color: Util.alpha(Color.background, dockRoot.bgOpacity)
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.10)
      antialiasing: true
      clip: true

      Text {
        anchors.centerIn: parent
        visible: !dockRoot.scrolling
        text: "only for scrollable layout"
        color: Color.foreground
        opacity: 0.65
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Item {
        id: stripHolder
        anchors.centerIn: parent
        visible: dockRoot.scrolling && panel.cells.length > 0
        width: strip.width
        height: strip.height

        transform: Translate {
          x: panel.vertical ? 0 : panel.transitionSlide
          y: panel.vertical ? panel.transitionSlide : 0
        }

        Item {
          id: strip
          // Hidden while an active blur transition shows the MultiEffect
          // copy instead — MultiEffect can still sample a hidden source.
          visible: !(dockRoot.transitionEffect === "blur" && panel.transitionBlur > 0.01)
          width: panel.vertical ? panel.cellSize : panel.dockLength
          height: panel.vertical ? panel.dockLength : panel.cellSize

          Repeater {
            model: panel.cells
            delegate: DockCell {
              required property var modelData
              dockRoot: panel.dockRoot
              panel: panel
              cellData: modelData
            }
          }

          // Keyboard-nav selection ring — only visible while this panel is
          // actively driving nav mode (see `navActive` above).
          Rectangle {
            id: navRing
            readonly property var navCell: (panel.navActive && panel.navIndex >= 0
              && panel.navIndex < panel.cells.length) ? panel.cells[panel.navIndex] : null
            visible: navRing.navCell !== null
            z: 50
            x: panel.vertical ? 0 : (navRing.navCell ? navRing.navCell.offset : 0)
            y: panel.vertical ? (navRing.navCell ? navRing.navCell.offset : 0) : 0
            width: panel.vertical ? parent.width : (navRing.navCell ? navRing.navCell.size : 0)
            height: panel.vertical ? (navRing.navCell ? navRing.navCell.size : 0) : parent.height
            radius: Math.min(8, Math.min(width, height) / 3)
            color: "transparent"
            border.width: 2
            border.color: Color.accent
            antialiasing: true
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          }
        }

        MultiEffect {
          anchors.fill: strip
          source: strip
          visible: dockRoot.transitionEffect === "blur" && panel.transitionBlur > 0.01
          blurEnabled: true
          blur: panel.transitionBlur
          blurMax: 64
        }

        // "glitch": red and blue ghosts of the tiles, colorized via
        // MultiEffect (`colorization: 1` replaces each pixel's color with
        // colorizationColor while keeping the source's alpha shape, so each
        // ghost reads as a colored silhouette of the real tiles) and offset
        // to opposite sides. The sharp, un-tinted `strip` stays visible
        // underneath the whole time and supplies the "green" — there's no
        // real per-channel split, but two offset colored echoes converging
        // back onto a sharp center is the same illusion CSS glitch effects
        // use, without needing to isolate actual RGB planes.
        MultiEffect {
          id: glitchRed
          anchors.fill: strip
          source: strip
          visible: dockRoot.transitionEffect === "glitch" && panel.glitchGhostOpacity > 0.01
          opacity: panel.glitchGhostOpacity
          colorizationColor: "#ff2a3d"
          colorization: 1
          transform: Translate {
            x: panel.vertical ? 0 : panel.glitchOffset
            y: panel.vertical ? panel.glitchOffset : 0
          }
        }
        MultiEffect {
          id: glitchBlue
          anchors.fill: strip
          source: strip
          visible: dockRoot.transitionEffect === "glitch" && panel.glitchGhostOpacity > 0.01
          opacity: panel.glitchGhostOpacity
          colorizationColor: "#2a8cff"
          colorization: 1
          transform: Translate {
            x: panel.vertical ? 0 : -panel.glitchOffset
            y: panel.vertical ? -panel.glitchOffset : 0
          }
        }
      }

      // Right-click the dock background (not a window tile) to open settings
      // — sizing is a settings-panel choice (Small/Medium/Large), not a drag.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: dockRoot.toggleSettings(panel.screen)
      }
    }
  }
  }
}
