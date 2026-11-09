import QtQuick

// One entry on a ring: an icon (Nerd Font glyph or app/window image) with a label.
Item {
  id: slot

  property var entry: ({})
  property real size: 40
  property real labelWidth: 80
  property real labelHeight: 26
  property real labelOffsetX: (width - labelWidth) / 2
  property real labelOffsetY: size + 2
  property bool selected: false
  property bool dim: false
  property color textColor: "#f5efff"
  property color accent: "#b784ff"
  property color selectedTextColor: "#ffffff"
  property string iconFont: "JetBrainsMono Nerd Font"
  property string imageSource: ""

  width: size
  height: size + 28
  opacity: dim ? 0.35 : (selected ? 1 : 0.9)
  Behavior on opacity { NumberAnimation { duration: 120 } }

  Item {
    id: iconBox
    anchors.horizontalCenter: parent.horizontalCenter
    width: slot.size * (slot.selected ? 1.12 : 0.94)
    height: width
    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    Image {
      anchors.fill: parent
      visible: slot.imageSource.length > 0
      source: slot.imageSource
      sourceSize.width: 96
      sourceSize.height: 96
      fillMode: Image.PreserveAspectFit
      smooth: true
    }
    Text {
      anchors.centerIn: parent
      visible: slot.imageSource.length === 0
      text: slot.entry && slot.entry.icon ? slot.entry.icon : "\u2022"
      font.family: slot.iconFont
      font.pixelSize: Math.round(iconBox.width * 0.74)
      color: slot.selected ? slot.selectedTextColor : slot.textColor
    }
  }

  Text {
    x: slot.labelOffsetX
    y: slot.labelOffsetY
    width: slot.labelWidth
    height: slot.labelHeight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignTop
    text: slot.entry && slot.entry.label ? slot.entry.label : ""
    color: slot.selected ? slot.selectedTextColor : slot.textColor
    font.pixelSize: slot.selected ? 10 : 9
    font.bold: slot.selected
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    maximumLineCount: 2
    elide: Text.ElideRight
    clip: true
  }
}
