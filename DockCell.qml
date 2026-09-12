import QtQuick
import QtQuick.Shapes
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

// One window tile in the dock. Fills the dock's full thickness (never
// changes); its length (`cellData.size`/`.offset` from Model.computeStrip) is
// derived there from the real window's own aspect ratio against that fixed
// thickness, which is what gives a square window a square-ish tile, a wide
// window a longer one, a tall window a shorter one. Configurable hover
// effect: "magnify" grows tiles nearer the pointer (like a dock's zoom, but
// contained within the dock's own bounds rather than overflowing above it —
// that would need reserving headroom in the panel's surface, which is more
// machinery than this effect is worth), "lift" is a flat hover scale+
// brighten, "none" disables both.
Rectangle {
  id: cell

  required property var dockRoot
  required property var panel
  required property var cellData

  readonly property bool focused: panel.activeAddr !== "" && cellData.address === panel.activeAddr
  readonly property bool floating: cellData.floating === true
  readonly property bool urgent: cellData.urgent === true
  readonly property bool hovered: hoverArea.containsMouse

  // ---- Hover effect --------------------------------------------------------
  readonly property real axisCenter: cellData.offset + cellData.size / 2
  readonly property real magnifyFactor: {
    if (dockRoot.hoverEffect !== "magnify" || panel.pointerAxis < 0)
      return 1
    var dist = Math.abs(panel.pointerAxis - axisCenter)
    var t = Math.max(0, 1 - dist / dockRoot.magnifyRadius)
    return 1 + (dockRoot.magnifyScale - 1) * t * t
  }
  readonly property real liftFactor: (dockRoot.hoverEffect === "lift" && hovered) ? 1.08 : 1
  readonly property real hoverScale: dockRoot.hoverEffect === "magnify" ? magnifyFactor : liftFactor

  x: panel.vertical ? 0 : cellData.offset
  y: panel.vertical ? cellData.offset : 0
  width: panel.vertical ? parent.width : cellData.size
  height: panel.vertical ? cellData.size : parent.height
  z: Math.round((hoverScale - 1) * 1000)
  radius: Math.min(8, Math.min(width, height) / 3)
  antialiasing: true
  transformOrigin: Item.Center
  scale: hoverScale

  color: Util.alpha(Color.foreground,
    (focused ? 0.30 : (floating ? 0.08 : (dockRoot.dimInactive ? 0.13 : 0.19))) + (hovered ? 0.08 : 0))
  border.color: cell.urgent ? Color.urgent : (focused ? Color.accent : "transparent")
  border.width: (cell.urgent || focused) ? 1 : 0

  Behavior on scale { enabled: dockRoot.animate; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
  Behavior on color { enabled: dockRoot.animate; ColorAnimation { duration: 120 } }
  Behavior on x { enabled: dockRoot.animate; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
  Behavior on y { enabled: dockRoot.animate; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
  Behavior on width { enabled: dockRoot.animate; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
  Behavior on height { enabled: dockRoot.animate; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

  // Floating windows read as a dashed outline, distinct from tiled ones.
  Shape {
    anchors.fill: parent
    visible: cell.floating
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: cell.focused ? Color.accent : Util.alpha(Color.foreground, 0.5)
      strokeWidth: 1
      fillColor: "transparent"
      strokeStyle: ShapePath.DashLine
      dashPattern: [2, 2]
      startX: 0.5
      startY: 0.5
      PathLine { x: cell.width - 0.5; y: 0.5 }
      PathLine { x: cell.width - 0.5; y: cell.height - 0.5 }
      PathLine { x: 0.5; y: cell.height - 0.5 }
      PathLine { x: 0.5; y: 0.5 }
    }
  }

  // A pulsing accent ring for windows demanding attention (Hyprland's
  // `urgent` flag) — visible even at a glance, and even more so once
  // `dimInactive` has faded everything that isn't focused.
  Rectangle {
    anchors.fill: parent
    visible: cell.urgent
    radius: cell.radius
    color: "transparent"
    antialiasing: true
    border.width: 2
    border.color: Color.urgent
    opacity: 0.4
    SequentialAnimation on opacity {
      running: cell.urgent
      loops: Animation.Infinite
      NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.4; duration: 500; easing.type: Easing.InOutSine }
    }
  }

  readonly property real iconPx: Math.max(10, Math.min(panel.cellSize - 12, width - 6, height - 6))
  readonly property bool labelIsText: dockRoot.iconMode === "nerdfont"
  readonly property bool showThumbnail: dockRoot.iconMode === "thumbnail"

  // "thumbnail": a live screencopy of the real window instead of an app
  // icon. Static (a single freeze-frame) until this tile is hovered, then
  // live — a hover "peek" rather than every tile decoding video constantly.
  Item {
    id: thumbHolder
    anchors.fill: parent
    anchors.margins: Math.max(3, Math.round(cell.radius))
    visible: cell.showThumbnail && cell.width >= 20 && cell.height >= 16
    clip: true

    ScreencopyView {
      id: thumb
      anchors.fill: parent
      captureSource: (cell.cellData.toplevelRef && cell.cellData.toplevelRef.wayland)
        ? cell.cellData.toplevelRef.wayland : null
      live: cell.hovered
      constraintSize: Qt.size(width, height)
    }

    Text {
      anchors.centerIn: parent
      visible: !thumb.hasContent
      text: {
        var c = String(cell.cellData.appClass || "")
        return c ? c.charAt(0).toUpperCase() : "•"
      }
      color: Color.foreground
      opacity: cell.focused ? 1 : 0.72
      font.family: Style.font.family
      font.pixelSize: Math.max(8, Math.min(22, Math.min(parent.width, parent.height) * 0.5))
      font.bold: true
    }
  }

  Item {
    anchors.centerIn: parent
    width: cell.labelIsText ? Math.max(6, cell.width - 4) : cell.iconPx
    height: cell.labelIsText ? Math.max(cell.iconPx, Math.min(cell.height - 2, 26)) : cell.iconPx
    visible: dockRoot.iconMode !== "none" && !cell.showThumbnail
      && (cell.labelIsText ? (cell.width >= 12 && cell.height >= 12) : (cell.width >= 16 && cell.height >= 16))

    Image {
      id: iconImg
      anchors.centerIn: parent
      width: cell.iconPx
      height: cell.iconPx
      source: dockRoot.iconMode === "icons" ? dockRoot.resolveIcon(cell.cellData.appClass) : ""
      sourceSize.width: Math.round(cell.iconPx * Screen.devicePixelRatio)
      sourceSize.height: Math.round(cell.iconPx * Screen.devicePixelRatio)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      visible: dockRoot.iconMode === "icons" && status === Image.Ready
      opacity: cell.focused ? 1 : 0.85
    }

    // Nerd Font glyph, or — in icon mode — the first class letter when no
    // icon image resolves, so a wide tile is never blank.
    Text {
      anchors.fill: parent
      visible: dockRoot.iconMode === "nerdfont"
        || (dockRoot.iconMode === "icons" && iconImg.status !== Image.Ready)
      text: {
        if (dockRoot.iconMode === "nerdfont")
          return Model.nerdGlyph(cell.cellData.appClass)
        var c = String(cell.cellData.appClass || "")
        return c ? c.charAt(0).toUpperCase() : "•"
      }
      color: Color.foreground
      opacity: cell.focused ? 1 : (cell.labelIsText ? 0.88 : 0.72)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
      fontSizeMode: Text.Fit
      minimumPixelSize: 6
      font.family: Style.font.family
      font.pixelSize: cell.labelIsText ? Math.max(10, Math.min(22, cell.height - 4)) : Math.max(8, cell.iconPx)
      font.bold: true
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function (mouse) {
      if (mouse.button === Qt.MiddleButton) {
        if (dockRoot.middleClickClose)
          dockRoot.closeClient(cell.cellData.address)
      } else {
        dockRoot.focusClient(cell.cellData.address)
      }
    }
    onEntered: panel.showTooltip(cell, String(cell.cellData.title || cell.cellData.appClass))
    onExited: panel.hideTooltip()
  }
}
