import QtQuick
import Quickshell
import qs

// One module on the bar: text with padding either side, hidden while empty.
// Tells its bar window when it's hovered, which shows `tooltip`.
Rectangle {
    id: module

    property string text: ""
    property color textColor: Theme.textColor
    property string tooltip: ""
    property int leftPadding: Theme.barModulePadding
    property int rightPadding: Theme.barModulePadding
    property alias label: label
    // Wider for modules that draw their own content
    property real contentWidth: label.implicitWidth
    readonly property bool pressed: mouse.pressed
    readonly property bool hovered: mouse.containsMouse

    // Qt.LeftButton, Qt.RightButton or Qt.MiddleButton
    signal clicked(int button)
    // Whole wheel notches, up positive
    signal scrolled(int steps)

    visible: text !== ""
    implicitWidth: contentWidth + leftPadding + rightPadding
    implicitHeight: Theme.barHeight
    color: "transparent"

    onHoveredChanged: {
        const window = QsWindow.window;
        if (!window)
            return;
        if (hovered)
            window.hovered = module;
        else if (window.hovered === module)
            window.hovered = null;
    }

    // Runs of thin spaces are gaps of a sixth of an em each, as waybar drew
    // them: the font has none, and Qt's fallback's are a whole character wide.
    // Sized by advance, like waybar: Nerd Font icons hang over their cell
    Row {
        id: label

        readonly property list<string> parts: module.text.split(/(\u2009+)/).filter(part => part !== "")

        x: module.leftPadding
        anchors.verticalCenter: parent.verticalCenter

        // By count, so new text updates the pieces instead of making new ones
        Repeater {
            model: label.parts.length

            Text {
                required property int index
                readonly property string part: label.parts[index] ?? ""
                readonly property bool gap: part[0] === "\u2009"

                width: gap ? part.length * fontInfo.pixelSize / 6 : advance.width
                text: gap ? "" : part
                textFormat: Text.PlainText
                color: module.textColor
                font.family: Theme.barFontFamily
                font.pointSize: Theme.barFontSize
                font.weight: Theme.fontWeight
            }
        }
    }

    MouseArea {
        id: mouse

        // Touchpads scroll in fractions of a notch
        property real wheel: 0

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => module.clicked(event.button)
        onWheel: event => {
            wheel += event.angleDelta.y / 120;
            const steps = wheel > 0 ? Math.floor(wheel) : Math.ceil(wheel);
            if (steps === 0)
                return;
            wheel -= steps;
            module.scrolled(steps);
        }
    }
}
