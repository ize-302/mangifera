import QtQuick
import qs

// Tinted cap around short text; brighter when lit.
Rectangle {
    id: cap

    property string text: ""
    property bool lit: false
    // So a changing number doesn't make it jump
    property int minWidth: 0
    property int fontSize: Theme.keyFontSize
    property color textColor: Theme.keyTextColor
    property color litTextColor: Theme.textColor
    // Outline, no tint
    property bool outlined: false
    property bool bold: false
    property int weight: Theme.fontWeight
    // Spinner in place of the text, keeping the width
    property bool busy: false

    width: Math.max(minWidth, label.implicitWidth + Theme.keyPadding * 2)
    height: Theme.keyHeight
    radius: Theme.cornerRadius
    color: lit ? Theme.hoverColor : outlined ? "transparent" : Theme.keyColor
    border.width: outlined ? 1 : 0
    border.color: Theme.dividerColor

    Text {
        id: label
        anchors.centerIn: parent
        text: cap.text
        textFormat: Text.PlainText
        color: cap.lit ? cap.litTextColor : cap.textColor
        font.family: Theme.fontFamily
        font.pixelSize: cap.fontSize
        font.weight: cap.bold ? Theme.selectedWeight : cap.weight
        opacity: cap.busy ? 0 : 1
    }

    Spinner {
        anchors.centerIn: parent
        visible: cap.busy
        width: cap.fontSize
        height: cap.fontSize
        color: label.color
    }
}
