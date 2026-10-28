pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services

// Webcam bubble for screen recordings, shown by ~/.local/bin/record-toggle
// while recording when the record menu's Camera is on, or toggled by
// ~/.local/bin/cam-toggle. An overlay layer, so it stays above every window.
// Drag it to move, drag its edge to resize, scroll to zoom, double-click to
// reset the zoom, right-click to switch circle / landscape / portrait. Shape,
// size, place and camera are kept for next time. Uses the camera picked in
// the record menu, else an external one when plugged in, else the built-in one.
Scope {
    id: root

    property bool open: false
    readonly property list<string> shapes: ["circle", "landscape", "portrait"]
    property string shape: "circle"
    // The circle's diameter, and the short side of the others
    property int size: Theme.cameraSize
    property real zoom: 1
    // Top left corner on the screen; -1 until placed
    property real posX: -1
    property real posY: -1
    property var screen: null
    // The picked camera's description; empty for the default
    property string device: ""
    // Cameras to pick from: only those with a 720p mode, which leaves out IR
    // and metadata nodes
    readonly property list<var> devices: mediaDevices.videoInputs.filter(input => input.videoFormats.some(format => format.resolution.height === 720))
    readonly property string currentDevice: camera.cameraDevice.description

    readonly property int shapeWidth: shape === "landscape" ? Math.round(size * 16 / 9) : size
    readonly property int shapeHeight: shape === "portrait" ? Math.round(size * 16 / 9) : size

    function clamp(value, low, high) {
        return Math.max(low, Math.min(high, value));
    }

    // Keeps the bubble on its screen, above the bar
    function place(x, y) {
        if (!screen)
            return;
        posX = Math.round(clamp(x, 0, screen.width - shapeWidth));
        posY = Math.round(clamp(y, 0, screen.height - Theme.barHeight - shapeHeight));
    }

    // Changes the size or shape around the same centre
    function reshape(change) {
        const centreX = posX + shapeWidth / 2;
        const centreY = posY + shapeHeight / 2;
        change();
        place(centreX - shapeWidth / 2, centreY - shapeHeight / 2);
    }

    function rotate() {
        setShape(shapes[(shapes.indexOf(shape) + 1) % shapes.length]);
    }

    function setShape(newShape) {
        reshape(() => shape = newShape);
        save();
    }

    // Saved when the drag ends
    function resize(newSize) {
        reshape(() => size = Math.round(clamp(newSize, Theme.cameraMinSize, Theme.cameraMaxSize)));
    }

    function zoomBy(steps) {
        zoom = clamp(zoom + steps * Theme.cameraZoomStep, 1, Theme.cameraMaxZoom);
    }

    function setDevice(description) {
        device = description;
        save();
    }

    function save() {
        stateFile.setText(JSON.stringify({
            device: device,
            shape: shape,
            size: size,
            x: posX,
            y: posY
        }));
    }

    onOpenChanged: {
        if (!open)
            return;
        screen = Compositor.focusedScreen() ?? Quickshell.screens[0];
        // Bottom right, above the bar, the first time
        if (posX < 0)
            place(screen.width - shapeWidth - Theme.cameraMargin, screen.height - Theme.barHeight - shapeHeight - Theme.cameraMargin);
        else
            place(posX, posY);
    }

    FileView {
        id: stateFile

        path: Quickshell.statePath("camera.json")
        blockLoading: true
        printErrors: false

        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (root.shapes.includes(saved.shape))
                    root.shape = saved.shape;
                root.size = root.clamp(saved.size ?? root.size, Theme.cameraMinSize, Theme.cameraMaxSize);
                root.posX = saved.x ?? -1;
                root.posY = saved.y ?? -1;
                root.device = saved.device ?? "";
            } catch (error) {}
        }
    }

    property alias ipc: ipcHandler

    IpcHandler {
        id: ipcHandler
        target: "camera"

        function toggle(): void {
            root.open = !root.open;
        }

        function show(): void {
            root.open = true;
        }

        function hide(): void {
            root.open = false;
        }

        function rotate(): void {
            if (root.open)
                root.rotate();
        }

        function zoomIn(): void {
            root.zoomBy(1);
        }

        function zoomOut(): void {
            root.zoomBy(-1);
        }

        function zoomReset(): void {
            root.zoom = 1;
        }
    }

    MediaDevices {
        id: mediaDevices
    }

    CaptureSession {
        camera: Camera {
            id: camera

            // Only while shown, so the camera's light goes off with it
            active: root.open
            // The picked one while it's plugged in, else an external camera
            // over the built-in one
            cameraDevice: root.devices.find(input => input.description === root.device) ?? root.devices.find(input => !input.description.startsWith("Integrated")) ?? root.devices[0] ?? mediaDevices.defaultVideoInput
            // The smallest 16:9 mode at least 480 high (848x480 is near
            // enough), at 30 frames a second, raw YUYV (17; VideoFrameFormat
            // isn't in QML) if it has one. Motion-JPEG is decoded on the CPU,
            // in the render thread: 540p took ~22% of a core, raw 480p ~7%
            cameraFormat: {
                const formats = cameraDevice.videoFormats.filter(format => format.resolution.height >= 480 && Math.abs(format.resolution.width / format.resolution.height - 16 / 9) < 0.02);
                const score = format => (format.maxFrameRate >= 30 ? 0 : 2) + (format.pixelFormat === 17 ? 0 : 1);
                formats.sort((a, b) => score(a) - score(b) || a.resolution.height - b.resolution.height);
                return formats[0] ?? cameraDevice.videoFormats[0];
            }
        }
        videoOutput: video
    }

    // Covers the screen, see-through and click-through outside the bubble,
    // which moves inside it. Moving the window itself instead jumped about:
    // pointer events still came relative to where it had been.
    PanelWindow { // qmllint disable uncreatable-type
        visible: root.open
        screen: root.screen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {
            item: bubble
            shape: root.shape === "circle" ? RegionShape.Ellipse : RegionShape.Rect
        }

        WlrLayershell.namespace: "camera"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Item {
            id: bubble

            readonly property real radius: root.shape === "circle" ? width / 2 : Theme.cameraCornerRadius

            x: root.posX
            y: root.posY
            width: root.shapeWidth
            height: root.shapeHeight

            // Zoomed and mirrored inside, then cut to shape. A layer effect,
            // as a hidden VideoOutput never draws its frames
            Item {
                anchors.fill: parent
                clip: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: shapeMask
                    // Soft edge instead of jaggies
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.panelColor
                }

                VideoOutput {
                    id: video

                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
                    scale: root.zoom
                    // Like a mirror
                    transform: Scale {
                        origin.x: video.width / 2
                        xScale: -1
                    }
                }

                // Faint veil while the pointer is over it
                Rectangle {
                    anchors.fill: parent
                    color: Theme.hoverColor
                    opacity: mouse.containsMouse || mouse.pressed ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.animationDuration
                        }
                    }
                }
            }

            Rectangle {
                id: shapeMask

                anchors.fill: parent
                radius: bubble.radius
                layer.enabled: true
                visible: false
            }

            // Thin outline, like the other panels
            Rectangle {
                anchors.fill: parent
                radius: bubble.radius
                color: "transparent"
                border.width: 1
                border.color: Theme.edgeColor
                antialiasing: true
            }

            MouseArea {
                id: mouse

                // Pointer on the screen (the window's coordinates)
                property real pressX: 0
                property real pressY: 0
                property real startX: 0
                property real startY: 0
                property bool resizing: false
                property real startSize: 0
                property real startDistance: 1
                property bool nearEdge: false

                // How far the point is from the centre, and whether it's on
                // the grip band along the edge
                function distance(x, y) {
                    return Math.hypot(x - width / 2, y - height / 2);
                }
                function onEdge(x, y) {
                    if (root.shape === "circle")
                        return distance(x, y) > width / 2 - Theme.cameraGrip;
                    return x < Theme.cameraGrip || y < Theme.cameraGrip || x > width - Theme.cameraGrip || y > height - Theme.cameraGrip;
                }

                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: resizing || nearEdge ? Qt.SizeFDiagCursor : pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                onPressed: event => {
                    pressX = bubble.x + event.x;
                    pressY = bubble.y + event.y;
                    startX = root.posX;
                    startY = root.posY;
                    resizing = event.button === Qt.LeftButton && onEdge(event.x, event.y);
                    startSize = root.size;
                    startDistance = Math.max(1, distance(event.x, event.y));
                }
                onPositionChanged: event => {
                    if (!(event.buttons & Qt.LeftButton)) {
                        nearEdge = onEdge(event.x, event.y);
                        return;
                    }
                    if (resizing) {
                        // Scales with the pointer's distance from the centre,
                        // which stays put
                        root.resize(startSize * distance(event.x, event.y) / startDistance);
                    } else {
                        root.place(startX + bubble.x + event.x - pressX, startY + bubble.y + event.y - pressY);
                    }
                }
                onReleased: event => {
                    if (event.button === Qt.LeftButton) {
                        resizing = false;
                        root.save();
                    }
                }
                onExited: nearEdge = false
                onClicked: event => {
                    if (event.button === Qt.RightButton)
                        root.rotate();
                }
                onDoubleClicked: root.zoom = 1
                onWheel: event => root.zoomBy(event.angleDelta.y / 120)
            }
        }
    }
}
