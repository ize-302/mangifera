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
    property int slideDistance: 16
    property int slideDuration: Theme.appearDuration
    // True while disappear() runs; keep the panel visible until it ends
    readonly property bool hiding: hideAnimation.running

    color: Theme.glassPanelColor
    radius: floating ? cornerRadius : 0
    // The one corner touching neither the screen edge nor the bar
    topRightRadius: fullWidth ? radius : cornerRadius

    // Waits out the first frame: filling a menu can take longer than the whole
    // animation, which then ends before it's drawn
    function appear() {
        hideAnimation.stop();
        animation.stop();
        slide.x = fromRight ? slideDistance : 0;
        slide.y = fromRight ? 0 : slideDistance;
        opacity = 0;
        startDelay.frames = 0;
        startDelay.restart();
    }

    // Sinks back the way appear() came in
    function disappear() {
        startDelay.stop();
        animation.stop();
        hideAnimation.restart();
    }

    FrameAnimation {
        id: startDelay

        property int frames: 0

        onTriggered: {
            if (++frames < 2)
                return;
            stop();
            animation.restart();
        }
    }

    transform: Translate {
        id: slide
    }

    ParallelAnimation {
        id: animation

        NumberAnimation {
            target: slide
            property: glass.fromRight ? "x" : "y"
            from: glass.slideDistance
            to: 0
            duration: glass.slideDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: glass
            property: "opacity"
            from: 0
            to: 1
            duration: glass.slideDuration
        }
    }

    ParallelAnimation {
        id: hideAnimation

        NumberAnimation {
            target: slide
            property: glass.fromRight ? "x" : "y"
            to: glass.slideDistance
            duration: glass.slideDuration
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: glass
            property: "opacity"
            to: 0
            duration: glass.slideDuration
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
