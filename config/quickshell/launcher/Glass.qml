import QtQuick
import qs

// Menu panel background: translucent, with a lit top and right edge. Floating
// panels get every corner rounded and every edge lit; full-width ones only the
// top edge.
Rectangle {
    id: glass

    property bool floating: false
    property int cornerRadius: Theme.panelRadius
    property bool fullWidth: false
    // Red for a critical notification
    property color edgeColor: Theme.edgeColor
    // Slides in from the right instead of rising out of the bar
    property bool fromRight: false

    color: Theme.glassPanelColor
    radius: floating ? cornerRadius : 0
    // The one corner touching neither the screen edge nor the bar
    topRightRadius: fullWidth ? radius : cornerRadius

    function appear() {
        animation.restart();
    }

    transform: Translate {
        id: slide
    }

    ParallelAnimation {
        id: animation

        NumberAnimation {
            target: slide
            property: glass.fromRight ? "x" : "y"
            from: 16
            to: 0
            duration: Theme.animationDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: glass
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.animationDuration
        }
    }

    // The outline's sides on the screen edge and bar hang outside and are
    // clipped (unless floating)
    Item {
        anchors.fill: parent
        clip: true

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: glass.floating ? 0 : -border.width
            anchors.bottomMargin: glass.floating ? 0 : -border.width
            anchors.rightMargin: glass.fullWidth ? -border.width : 0
            color: "transparent"
            radius: glass.radius
            topLeftRadius: glass.topLeftRadius
            topRightRadius: glass.topRightRadius
            border.width: 1
            border.color: glass.edgeColor
        }
    }
}
