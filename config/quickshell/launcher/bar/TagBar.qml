import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs
import qs.services

// The bar's tags, scratchpad count and key mode, drawn over the left end of
// waybar on each screen: waybar's custom modules can only show text, and these
// show each window's real app icon. Clicking a tag views it there; clicking
// the scratchpad count opens the scratchpad menu.
Scope {
    id: root

    required property var scratchpadMenu

    readonly property int parked: Compositor.parked.length
    readonly property string mode: Compositor.focusedMonitor?.keymode ?? "default"

    function iconFor(appId) {
        const entry = DesktopEntries.heuristicLookup(appId);
        return Quickshell.iconPath(entry?.icon || appId, "application-x-executable");
    }

    // Shown tags (active, or with windows) on a monitor: { index, focused,
    // visible, urgent, apps: [appid] }. Global windows (picture-in-picture)
    // follow onto every tag, so they don't count
    function tagsOf(monitor) {
        const tags = [];
        for (const tag of monitor?.tags ?? []) {
            const windows = Compositor.clients.filter(client => client.monitor === monitor.name && !client.is_minimized && !client.is_global && client.tags.includes(tag.index)).sort((a, b) => a.id - b.id);
            if (!tag.is_active && windows.length === 0)
                continue;
            tags.push({
                index: tag.index,
                focused: tag.is_active && monitor.active,
                visible: tag.is_active,
                urgent: tag.is_urgent,
                apps: windows.map(client => client.appid ?? "")
            });
        }
        return tags;
    }

    Variants {
        model: Quickshell.screens

        PanelWindow { // qmllint disable uncreatable-type
            id: strip

            required property var modelData
            readonly property var monitor: Compositor.monitors.find(monitor => monitor.name === modelData.name) ?? null
            // Waybar hides under fullscreen windows; this sits above it on the
            // overlay layer, so it hides itself
            readonly property bool fullscreen: Compositor.clients.some(client => client.monitor === modelData.name && client.is_fullscreen && client.is_visible)
            // Only replaced when something shown changes, so icons don't reload
            property var tags: []
            readonly property string tagsKey: JSON.stringify(root.tagsOf(monitor))

            onTagsKeyChanged: tags = JSON.parse(tagsKey)

            // The tag just switched to on this monitor, whose number briefly
            // shows in place of its icons, as a tag with windows has no number
            // otherwise. 0 when none
            property int flashTag: 0
            readonly property int activeTag: monitor?.tags?.find(tag => tag.is_active)?.index ?? 0
            // The first tag seen, at startup or when mango restarts, isn't a
            // switch
            property int lastTag: 0

            onActiveTagChanged: {
                if (!activeTag)
                    return;
                if (lastTag) {
                    flashTag = activeTag;
                    flash.restart();
                }
                lastTag = activeTag;
            }

            Timer {
                id: flash
                interval: Theme.tagFlashTimeout
                onTriggered: strip.flashTag = 0
            }

            screen: modelData
            visible: !Compositor.remapping && !fullscreen
            color: "transparent"
            implicitWidth: Math.max(1, row.implicitWidth)
            implicitHeight: Theme.tagBarHeight
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "tags"
            // Above waybar, whose surface is on the top layer
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                bottom: true
                left: true
            }

            // Under waybar's top border
            Row {
                id: row

                y: Theme.tagBorder
                height: parent.height - Theme.tagBorder

                Repeater {
                    model: strip.tags

                    Rectangle {
                        id: tag

                        required property var modelData
                        readonly property bool empty: modelData.apps.length === 0
                        readonly property bool flashing: !empty && modelData.index === strip.flashTag

                        width: (empty ? number.implicitWidth : content.implicitWidth) + Theme.tagPadding + (empty ? Theme.tagPadding : Theme.tagEndPadding)
                        height: row.height
                        color: modelData.urgent ? Theme.closeColor : modelData.focused ? Theme.tagFocusedColor : Theme.tagColor

                        // Hidden rather than gone while the number shows, so
                        // the tag keeps its width
                        Row {
                            id: content

                            x: Theme.tagPadding
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.tagIconSpacing
                            opacity: tag.flashing ? 0 : 1

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.animationDuration
                                }
                            }

                            Repeater {
                                model: tag.modelData.apps

                                IconImage {
                                    required property string modelData

                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitSize: Theme.tagIconSize
                                    source: root.iconFor(modelData)
                                }
                            }
                        }

                        // The number: always on an empty tag, and over the
                        // icons just after switching to one with windows
                        Text {
                            id: number

                            x: Theme.tagPadding + (tag.empty ? 0 : (content.implicitWidth - width) / 2)
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: tag.empty || tag.flashing ? 1 : 0
                            text: tag.modelData.index
                            color: tag.modelData.urgent ? Theme.tagUrgentTextColor : Theme.textColor
                            font.family: Theme.barFontFamily
                            font.pointSize: Theme.barFontSize
                            font.weight: Theme.fontWeight

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Theme.animationDuration
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Quickshell.execDetached(["mmsg", "dispatch", `viewcrossmon,${tag.modelData.index},${strip.modelData.name}`])
                        }
                    }
                }

                // Dots for windows parked in the scratchpad
                Rectangle {
                    visible: root.parked > 0
                    width: dots.implicitWidth + Theme.scratchpadPadding * 2
                    height: row.height
                    color: Theme.tagColor

                    Text {
                        id: dots

                        anchors.centerIn: parent
                        text: ["•", "••", "•••", "••••", "••••+"][Math.min(root.parked, 5) - 1] ?? ""
                        color: Theme.textColor
                        font.family: Theme.barFontFamily
                        font.pointSize: Theme.barFontSize
                        font.weight: Theme.fontWeight
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.scratchpadMenu.open = !root.scratchpadMenu.open
                    }
                }

                // mango's key mode, when not the default
                Rectangle {
                    visible: root.mode !== "default"
                    width: modeText.implicitWidth + Theme.modePadding * 2
                    height: row.height
                    color: Theme.modeColor

                    Text {
                        id: modeText

                        anchors.centerIn: parent
                        text: root.mode
                        color: Theme.tagUrgentTextColor
                        font.family: Theme.barFontFamily
                        font.pointSize: Theme.barFontSize
                        font.weight: Theme.fontWeight
                    }
                }
            }
        }
    }
}
