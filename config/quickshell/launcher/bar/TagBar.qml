import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs
import qs.services

// The bar's tags, scratchpad count and key mode, drawn over the left end of
// waybar on each screen: waybar's custom modules can only show text, and these
// show each window's real app icon. Clicking a tag views it there; clicking
// the scratchpad's icons opens the scratchpad menu.
Scope {
    id: root

    required property var scratchpadMenu

    readonly property int parked: Compositor.parked.length
    // Apps with windows in the scratchpad, once each, the last parked on top
    // of the stack
    readonly property var parkedApps: Compositor.parked.map(client => client.appid ?? "").filter((appid, index, all) => all.lastIndexOf(appid) === index)
    readonly property string mode: Compositor.focusedMonitor?.keymode ?? "default"

    function iconFor(appId) {
        const entry = DesktopEntries.heuristicLookup(appId);
        return Quickshell.iconPath(entry?.icon || appId, "application-x-executable");
    }

    // Shown tags (active, or with windows) on a monitor: { index, focused,
    // visible, urgent, apps: [{ appid, count }] }, one entry per app in the
    // order their first window opened. Global windows (picture-in-picture)
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
                apps: windows.reduce((apps, client) => {
                    const appid = client.appid ?? "";
                    const app = apps.find(app => app.appid === appid);
                    if (app)
                        app.count++;
                    else
                        apps.push({
                            appid: appid,
                            count: 1
                        });
                    return apps;
                }, [])
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

                                // One icon per app, with a dot under it per
                                // window when it has more than one
                                IconImage {
                                    id: app

                                    required property var modelData

                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitSize: Theme.tagIconSize
                                    source: root.iconFor(modelData.appid)

                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.bottom
                                        anchors.topMargin: Theme.tagDotGap
                                        spacing: Theme.tagDotSpacing
                                        visible: app.modelData.count > 1

                                        Repeater {
                                            model: Math.min(app.modelData.count, Theme.tagDotMax)

                                            Rectangle {
                                                width: Theme.tagDotSize
                                                height: Theme.tagDotSize
                                                radius: width / 2
                                                color: tag.modelData.urgent ? Theme.tagUrgentTextColor : Theme.textColor
                                            }
                                        }
                                    }
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

                // Icons of the apps parked in the scratchpad, stacked like
                // cards, each a little to the right of the one behind it. In
                // a pill set apart from the tags, bordered like waybar's
                // tooltips, rather than a full-height block like a tag
                Item {
                    visible: root.parked > 0
                    width: pill.width + Theme.scratchpadGap * 2
                    height: row.height

                    Rectangle {
                        id: pill

                        anchors.centerIn: parent
                        width: stack.width + Theme.scratchpadPadding * 2
                        height: Theme.scratchpadPillHeight
                        radius: Theme.scratchpadPillRadius
                        color: Theme.tagColor
                        border.width: 1
                        border.color: Theme.scratchpadPillBorderColor

                        // Hovered, the stack spreads into a row like a tag's
                        // icons, and closes back up after
                        readonly property bool spread: hover.containsMouse
                        property real offset: spread ? Theme.tagIconSize + Theme.tagIconSpacing : Theme.scratchpadStackOffset
                        property real backBrightness: spread ? 0 : Theme.scratchpadStackBackBrightness

                        Behavior on offset {
                            NumberAnimation {
                                duration: Theme.scratchpadSpreadDuration
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on backBrightness {
                            NumberAnimation {
                                duration: Theme.scratchpadSpreadDuration
                            }
                        }

                        Item {
                            id: stack

                            anchors.centerIn: parent
                            width: Theme.tagIconSize + Math.max(0, root.parkedApps.length - 1) * pill.offset
                            height: Theme.tagIconSize

                            Repeater {
                                model: root.parkedApps

                                Item {
                                    id: card

                                    required property string modelData
                                    required property int index
                                    readonly property bool front: index === root.parkedApps.length - 1

                                    x: index * pill.offset
                                    z: index
                                    width: Theme.tagIconSize
                                    height: Theme.tagIconSize

                                    // The ones behind are darkened, and have the
                                    // one in front, plus a ring, cut out of them,
                                    // so each edge stays clear of the next
                                    IconImage {
                                        anchors.fill: parent
                                        source: root.iconFor(card.modelData)
                                        layer.enabled: !card.front
                                        layer.effect: MultiEffect {
                                            brightness: pill.backBrightness
                                            maskEnabled: true
                                            maskInverted: true
                                            maskSource: cutout
                                            maskThresholdMin: 0.5
                                            maskSpreadAtMin: 1
                                        }
                                    }

                                    // The mask: where the next icon and its ring
                                    // sit over this one
                                    Item {
                                        id: cutout

                                        width: parent.width
                                        height: parent.height
                                        visible: false
                                        layer.enabled: !card.front

                                        Rectangle {
                                            x: pill.offset - Theme.scratchpadStackRing
                                            y: -Theme.scratchpadStackRing
                                            width: parent.width + Theme.scratchpadStackRing * 2
                                            height: parent.height + Theme.scratchpadStackRing * 2
                                            radius: Theme.scratchpadStackRadius
                                            color: "black"
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: hover

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.scratchpadMenu.open = !root.scratchpadMenu.open
                        }
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
