pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Right-click the dock to open this. One shared instance for the whole
// plugin (not one per monitor) — it shows on whichever screen you right
// clicked from (`dockRoot.settingsScreen`). Every control here writes
// straight through `dockRoot`'s setters, which both update the running dock
// immediately and persist the change into shell.json.
//
// Deliberately built from plain Rectangle/Text/MouseArea plus qs.Ui's
// `Button` (for chips), `ToggleSwitch` (for on/off rows), and `PanelSlider`
// (for Opacity) rather than `qs.Ui.PopupCard` — PopupCard is designed to
// anchor off a bar button and needs a real `bar` object, which this overlay
// doesn't have. `ButtonGroup` and the labeled `Toggle` composite are skipped
// too (this author's own jgarza.loadout plugin found them unreliable outside
// a bar context); plain `Button` with `selected:` and a bare `ToggleSwitch`
// are the same controls without that dependency. `PanelSlider`'s `bar`
// property is optional and every color already falls back to `Color`/plain
// values on its own, so it needs no such substitute.
PanelWindow {
  id: panel

  required property var dockRoot

  screen: dockRoot.settingsScreen
  visible: dockRoot.settingsOpen && dockRoot.settingsScreen !== null
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }

  WlrLayershell.namespace: "omarchy-scrolldock-settings"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: panel.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  readonly property var sizeOptions: [
    { value: "small", label: "Small" },
    { value: "medium", label: "Medium" },
    { value: "large", label: "Large" }
  ]
  readonly property var edgeOptions: [
    { value: "top", label: "Top" },
    { value: "bottom", label: "Bottom" },
    { value: "left", label: "Left" },
    { value: "right", label: "Right" }
  ]
  readonly property var hoverOptions: [
    { value: "magnify", label: "Magnify" },
    { value: "lift", label: "Lift" },
    { value: "none", label: "None" }
  ]
  readonly property var iconOptions: [
    { value: "icons", label: "Icons" },
    { value: "nerdfont", label: "Nerd Font" },
    { value: "thumbnail", label: "Thumbnail" },
    { value: "none", label: "None" }
  ]
  readonly property var transitionOptions: [
    { value: "fade", label: "Fade" },
    { value: "blur", label: "Blur" },
    { value: "zoom", label: "Zoom" },
    { value: "slide", label: "Slide" },
    { value: "glitch", label: "Glitch" },
    { value: "none", label: "None" }
  ]
  readonly property var monitorOptions: {
    var out = [{ value: "all", label: "All" }]
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++)
      if (screens[i] && screens[i].name)
        out.push({ value: String(screens[i].name), label: String(screens[i].name) })
    return out
  }

  // Backdrop: click anywhere outside the card to dismiss.
  Rectangle {
    id: scrim
    anchors.fill: parent
    color: Color.menu.scrim

    TapHandler {
      onTapped: panel.dockRoot.closeSettings()
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: panel.visible

    Keys.onPressed: function (event) {
      if (event.key === Qt.Key_Escape) {
        panel.dockRoot.closeSettings()
        event.accepted = true
      }
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(420), parent.width - Style.space(40))
      height: content.implicitHeight + Style.space(18) * 2
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(10)
      color: Color.popups.background
      border.width: 1
      border.color: Color.popups.border
      antialiasing: true

      // Swallow taps so they don't fall through to the scrim behind the card.
      TapHandler {}

      Column {
        id: content
        anchors.fill: parent
        anchors.margins: Style.space(18)
        spacing: Style.space(16)

        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, closeButton.implicitHeight)

          Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "SCROLL DOCK"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Button {
            id: closeButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "✕"
            foreground: Color.popups.text
            accent: Color.accent
            fontSize: Style.font.bodySmall
            onClicked: panel.dockRoot.closeSettings()
          }
        }

        SettingSection {
          label: "Size"
          options: panel.sizeOptions
          current: panel.dockRoot.size
          onChosen: function (value) { panel.dockRoot.commitSize(value) }
        }

        SettingSlider {
          label: "Opacity"
          suffix: "%"
          minimum: 10
          maximum: 100
          step: 5
          currentValue: Math.round(panel.dockRoot.bgOpacity * 100)
          onPreviewed: function (value) { panel.dockRoot.previewBgOpacity(value) }
          onCommitted: function (value) { panel.dockRoot.setBgOpacity(value) }
        }

        SettingSection {
          label: "Edge"
          options: panel.edgeOptions
          current: panel.dockRoot.edge
          onChosen: function (value) { panel.dockRoot.setEdge(value) }
        }

        SettingSection {
          label: "Monitor"
          options: panel.monitorOptions
          current: panel.dockRoot.monitorFilter
          onChosen: function (value) { panel.dockRoot.setMonitor(value) }
        }

        SettingSection {
          label: "Hover effect"
          options: panel.hoverOptions
          current: panel.dockRoot.hoverEffect
          onChosen: function (value) { panel.dockRoot.setHoverEffect(value) }
        }

        SettingSection {
          label: "Tile label"
          options: panel.iconOptions
          current: panel.dockRoot.iconMode
          onChosen: function (value) { panel.dockRoot.setIconMode(value) }
        }

        SettingSection {
          label: "Workspace-switch transition"
          options: panel.transitionOptions
          current: panel.dockRoot.transitionEffect
          onChosen: function (value) { panel.dockRoot.setTransitionEffect(value) }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
        }

        SettingToggle {
          label: "Auto-hide (reveal on edge hover)"
          checked: panel.dockRoot.autoHide
          onToggled: panel.dockRoot.setAutoHide(!panel.dockRoot.autoHide)
        }

        SettingToggle {
          label: "Show floating windows"
          checked: panel.dockRoot.showFloating
          onToggled: panel.dockRoot.setShowFloating(!panel.dockRoot.showFloating)
        }

        SettingToggle {
          label: "Dim unfocused windows"
          checked: panel.dockRoot.dimInactive
          onToggled: panel.dockRoot.setDimInactive(!panel.dockRoot.dimInactive)
        }

        SettingToggle {
          label: "Animate changes"
          checked: panel.dockRoot.animate
          onToggled: panel.dockRoot.setAnimate(!panel.dockRoot.animate)
        }

        SettingToggle {
          label: "Middle-click closes window"
          checked: panel.dockRoot.middleClickClose
          onToggled: panel.dockRoot.setMiddleClickClose(!panel.dockRoot.middleClickClose)
        }

        Text {
          width: parent.width
          text: "More knobs (gaps, magnify strength, auto-hide timing, …) live in"
            + " this plugin's shell.json entry — see the README."
          wrapMode: Text.WordWrap
          color: Color.popups.text
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // A labeled row of chips — one Button per option, the current value's chip
  // shown selected. Used for every choice-of-several setting above.
  component SettingSection: Column {
    id: section
    required property string label
    required property var options
    required property string current
    signal chosen(string value)

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(6)

    Text {
      text: section.label
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: section.options
        delegate: Button {
          required property var modelData
          text: modelData.label
          selected: modelData.value === section.current
          bordered: true
          foreground: Color.popups.text
          accent: Color.accent
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(10)
          verticalPadding: Style.space(5)
          onClicked: section.chosen(modelData.value)
        }
      }
    }
  }

  // A labeled slider with a live value readout. `qs.Ui.PanelSlider` works
  // without a `bar` (every color falls back to `qs.Commons.Color` on its
  // own), unlike `PopupCard`.
  component SettingSlider: Column {
    id: sliderRow
    required property string label
    required property real minimum
    required property real maximum
    required property real step
    required property real currentValue
    property string suffix: ""

    signal previewed(real value)
    signal committed(real value)

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(5)

    Item {
      width: parent.width
      implicitHeight: Math.max(sliderLabel.implicitHeight, sliderValue.implicitHeight)

      Text {
        id: sliderLabel
        anchors.left: parent.left
        text: sliderRow.label
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        id: sliderValue
        anchors.right: parent.right
        text: Math.round(slider.dragging ? slider.liveValue : sliderRow.currentValue) + sliderRow.suffix
        color: Color.popups.text
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      minimum: sliderRow.minimum
      maximum: sliderRow.maximum
      step: sliderRow.step
      integer: true
      value: sliderRow.currentValue
      fillColor: Color.accent
      knobColor: Color.popups.text
      onMoved: function (value) { sliderRow.previewed(value) }
      onReleased: function (value) { sliderRow.committed(value) }
    }
  }

  // A label + bare on/off switch, right-aligned.
  component SettingToggle: Item {
    id: toggleRow
    required property string label
    required property bool checked
    signal toggled()

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(toggleLabel.implicitHeight, toggleSwitch.implicitHeight)

    Text {
      id: toggleLabel
      anchors.left: parent.left
      anchors.right: toggleSwitch.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: toggleRow.label
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    ToggleSwitch {
      id: toggleSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: toggleRow.checked
      foreground: Color.popups.text
      accent: Color.accent
      onToggled: toggleRow.toggled()
    }
  }
}
