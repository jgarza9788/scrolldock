import QtQuick
import Quickshell
import qs.Commons

// One per DockPanel, showing that monitor's tile-title tooltip. A real
// separate Wayland surface (Quickshell's `PopupWindow`) rather than a
// QtQuick Controls `ToolTip` — a ToolTip renders inside its own window's
// overlay, so it would be clipped to the dock's own tight little surface
// instead of floating past it. Same anchor idiom as `qs.Ui.PopupCard`
// (fixed `edges`/`gravity`, position by feeding it a 1x1 "anchor point" and
// letting the popup's own size do the rest) minus the `bar` dependency — a
// tooltip doesn't need per-position theming, just to land on the side of
// the dock that's away from the screen edge.
PopupWindow {
  id: root

  required property var panel
  property string text: ""
  property bool shown: false

  visible: root.shown && root.text !== ""
  color: "transparent"

  implicitWidth: Math.min(Style.space(320), label.implicitWidth + Style.space(16))
  implicitHeight: label.implicitHeight + Style.space(10)

  anchor {
    window: root.panel
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1
  }

  // Point the anchor at whichever side of `cellItem` faces away from the
  // dock's screen edge, so the tooltip reads as coming off the tile rather
  // than overlapping the screen edge the dock is pinned to.
  function showFor(cellItem, text) {
    if (!cellItem)
      return
    root.text = String(text || "")
    var margin = 6
    // `rect` is in the anchor window's own local coordinates, not global
    // screen coordinates — map into `panel.contentItem`, not a null target.
    var pos = cellItem.mapToItem(root.panel.contentItem, 0, 0)
    var cx = pos.x + cellItem.width / 2
    var cy = pos.y + cellItem.height / 2
    var edge = root.panel.edge
    if (edge === "bottom") {
      root.anchor.rect.x = cx - root.implicitWidth / 2
      root.anchor.rect.y = -root.implicitHeight - margin
    } else if (edge === "top") {
      root.anchor.rect.x = cx - root.implicitWidth / 2
      root.anchor.rect.y = root.panel.height + margin
    } else if (edge === "left") {
      root.anchor.rect.x = root.panel.width + margin
      root.anchor.rect.y = cy - root.implicitHeight / 2
    } else {
      root.anchor.rect.x = -root.implicitWidth - margin
      root.anchor.rect.y = cy - root.implicitHeight / 2
    }
    root.shown = true
  }

  function hide() { root.shown = false }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.tooltip.background
    border.width: 1
    border.color: Color.tooltip.border
    antialiasing: true
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: Color.tooltip.text
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
