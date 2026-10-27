import QtQuick
import Quickshell
import qs

// A bar module's tooltip, centred above it. Bar.qml picks the module.
PopupWindow {
    id: tip

    // A BarModule, or null for none
    property Item target: null
    readonly property string text: target?.tooltip ?? ""
    readonly property int gap: 6

    visible: target !== null && text !== ""
    color: "transparent"
    implicitWidth: box.width
    implicitHeight: box.height

    anchor.rect.x: target ? target.mapToItem(null, 0, 0).x : 0
    anchor.rect.y: -gap
    anchor.rect.width: target?.width ?? 0
    anchor.rect.height: 1
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top

    // Plain dark box, no outline
    Rectangle {
        id: box

        width: label.implicitWidth + 12
        height: label.implicitHeight + 6
        color: Theme.barTooltipColor
        radius: Theme.barTooltipRadius

        Text {
            id: label

            anchors.centerIn: parent
            text: tip.text
            textFormat: Text.PlainText
            color: Theme.barTooltipTextColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.barTooltipFontSize
            font.weight: Theme.fontWeight
        }
    }
}
