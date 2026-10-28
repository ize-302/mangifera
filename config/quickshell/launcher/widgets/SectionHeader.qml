import QtQuick
import qs

// Group header: dimmed name and a thin line. One that opens a page ends in a
// summary key cap and chevron, and emits `clicked`. A `back` one is a page
// title with a back chevron and an optional `action` key cap emitting
// `actionClicked`.
Item {
    id: header

    property string text: ""
    property string summary: ""
    property bool opensPage: false
    property bool line: true
    property bool back: false
    // Off for a page that closes instead of going back
    property bool arrow: true
    property int inset: Theme.rowPadding
    property int titleSize: Theme.searchFontSize
    // Lit and spinning while running
    property string action: ""
    property bool actionActive: false

    signal clicked
    signal actionClicked

    // Pulled up into the panel's padding, so the space above matches the space
    // below
    height: back ? label.y + label.height + Theme.searchPadding + 1 + Theme.searchPadding / 2 : Theme.sectionHeight

    Text {
        id: backIcon
        x: header.inset
        anchors.verticalCenter: label.verticalCenter
        visible: header.back && header.arrow
        text: Theme.backIcon
        color: mouse.containsMouse ? Theme.textColor : Theme.dimColor
        font.family: Theme.fontFamily
        font.pixelSize: header.titleSize
    }

    Text {
        id: label
        x: header.back && header.arrow ? backIcon.x + backIcon.width + Theme.iconSpacing : header.inset
        y: header.back ? Theme.searchPadding - Theme.panelPadding : header.height - height - Theme.rowSpacing
        text: header.back ? header.text : header.text.toUpperCase()
        color: header.back ? Theme.textColor : Theme.dimColor
        font.family: Theme.fontFamily
        font.pixelSize: header.back ? header.titleSize : Theme.sectionFontSize
        font.weight: Theme.fontWeight
        font.letterSpacing: header.back ? 0 : 1
    }

    Rectangle {
        visible: header.line && !header.back
        anchors.left: label.right
        anchors.leftMargin: Theme.iconSpacing
        anchors.right: summary.visible ? summary.left : more.visible ? more.left : parent.right
        anchors.rightMargin: summary.visible || more.visible ? Theme.iconSpacing : header.inset
        anchors.verticalCenter: label.verticalCenter
        height: 1
        color: Theme.dividerColor
    }

    Rectangle {
        visible: header.back
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.searchPadding / 2
        width: parent.width
        height: 1
        color: Theme.dividerColor
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: header.opensPage || header.back
        enabled: header.opensPage || header.back
        cursorShape: Qt.PointingHandCursor
        onClicked: header.clicked()
    }

    KeyCap {
        id: summary
        anchors.right: more.visible ? more.left : parent.right
        anchors.rightMargin: more.visible ? Theme.keySpacing : header.inset
        anchors.verticalCenter: label.verticalCenter
        visible: header.summary !== "" && !header.back
        text: header.summary
        lit: mouse.containsMouse
    }

    Text {
        id: more
        anchors.right: parent.right
        anchors.rightMargin: header.inset
        anchors.verticalCenter: label.verticalCenter
        visible: header.opensPage && !header.back
        text: Theme.pageIcon
        color: mouse.containsMouse ? Theme.textColor : Theme.keyTextColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.sectionFontSize
    }

    KeyCap {
        anchors.right: parent.right
        anchors.rightMargin: header.inset
        anchors.verticalCenter: label.verticalCenter
        visible: header.back && header.action !== ""
        text: header.action
        fontSize: Math.min(Theme.keyFontSize, header.titleSize - 2)
        lit: header.actionActive || actionMouse.containsMouse
        busy: header.actionActive

        MouseArea {
            id: actionMouse

            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: header.actionClicked()
        }
    }
}
