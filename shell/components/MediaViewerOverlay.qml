import QtQuick
import QtQuick.Layouts
import ".."
import "common"
import "../services"

FocusScope {
    id: root

    property bool open: false
    property var item: null
    property int currentIndex: -1
    property int totalCount: 0
    property int stepDir: 0
    property int topRadius: 0
    property int bottomRadius: 0

    // Deferred entrance flag so first-load via Loader always animates instead of snapping on frame 0
    property bool _entered: false

    readonly property bool isImage: Boolean(item && item.type === "image")
    readonly property bool isVideo: Boolean(item && item.type === "video")
    readonly property string mediaPath: item ? String(item.path || "") : ""
    readonly property string mediaUrl: mediaPath !== "" ? FileService.fileUrl(mediaPath) : ""

    // Image zoom & pan state
    readonly property real minZoom: 0.5
    readonly property real maxZoom: 6.0
    property real zoom: 1.0
    property real panX: 0
    property real panY: 0
    property bool smoothTransform: false
    property int transformDuration: 180

    signal closeRequested()
    signal stepRequested(int delta)
    signal openExternalRequested(string path)

    opacity: _entered ? 1.0 : 0.0
    visible: open || opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: root._entered ? 220 : 180; easing.type: Easing.OutCubic } }

    Component.onCompleted: {
        if (open) {
            Qt.callLater(() => {
                if (root && root.open) root._entered = true;
            });
        }
    }

    function resetView(animate) {
        transformDuration = 190;
        smoothTransform = Boolean(animate);
        zoom = 1.0;
        panX = 0;
        panY = 0;
    }

    function clampPan(nextX, nextY, targetZoom) {
        const z = targetZoom !== undefined ? targetZoom : zoom;
        if (z <= 1.01) return { x: 0, y: 0 };
        const baseW = viewerImg.paintedWidth > 0 ? viewerImg.paintedWidth : imageStage.width;
        const baseH = viewerImg.paintedHeight > 0 ? viewerImg.paintedHeight : imageStage.height;
        const maxX = Math.max(0, (baseW * z - imageStage.width) / 2);
        const maxY = Math.max(0, (baseH * z - imageStage.height) / 2);
        return {
            x: Math.max(-maxX, Math.min(maxX, nextX)),
            y: Math.max(-maxY, Math.min(maxY, nextY))
        };
    }

    function applyZoom(targetZoom, anchorX, anchorY, animate, durationMs) {
        const clamped = Math.max(minZoom, Math.min(maxZoom, targetZoom));
        const prev = zoom;
        if (Math.abs(clamped - prev) < 0.001) return;

        transformDuration = durationMs !== undefined ? durationMs : 180;
        smoothTransform = Boolean(animate);
        let nextX = panX;
        let nextY = panY;
        if (anchorX !== undefined && anchorY !== undefined && imageStage.width > 0 && imageStage.height > 0) {
            const cx = anchorX - imageStage.width / 2;
            const cy = anchorY - imageStage.height / 2;
            const ratio = clamped / prev;
            nextX = cx - (cx - panX) * ratio;
            nextY = cy - (cy - panY) * ratio;
        }
        const bounded = clampPan(nextX, nextY, clamped);
        zoom = clamped;
        panX = bounded.x;
        panY = bounded.y;
    }

    function zoomBy(factor, anchorX, anchorY, animate, durationMs) {
        applyZoom(zoom * factor, anchorX, anchorY, animate, durationMs);
    }

    onItemChanged: {
        resetView(false);
        if (_entered && stepDir !== 0) {
            stageSwitchAnim.restart();
        }
    }

    onOpenChanged: {
        if (open) {
            resetView(false);
            root.forceActiveFocus();
            Qt.callLater(() => {
                if (root && root.open) root._entered = true;
            });
        } else {
            _entered = false;
            if (videoLoader.item && videoLoader.item.stopMedia) {
                videoLoader.item.stopMedia();
            }
        }
    }

    Keys.onPressed: (event) => {
        if (!root.open) return;

        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
            return;
        }

        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

        if (root.isImage) {
            if (event.key === Qt.Key_Left) {
                if (root.totalCount > 1) root.stepRequested(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right) {
                if (root.totalCount > 1) root.stepRequested(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                root.zoomBy(1.25, undefined, undefined, true);
                event.accepted = true;
            } else if (event.key === Qt.Key_Minus || event.key === Qt.Key_Underscore) {
                root.zoomBy(1 / 1.25, undefined, undefined, true);
                event.accepted = true;
            } else if (event.key === Qt.Key_0 || event.key === Qt.Key_Space) {
                root.resetView(true);
                event.accepted = true;
            }
            return;
        }

        if (root.isVideo && videoLoader.item) {
            if (event.key === Qt.Key_Space) {
                videoLoader.item.togglePlay();
                event.accepted = true;
            } else if (event.key === Qt.Key_Left) {
                if (shift && root.totalCount > 1) root.stepRequested(-1);
                else videoLoader.item.seekRelative(-5000);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right) {
                if (shift && root.totalCount > 1) root.stepRequested(1);
                else videoLoader.item.seekRelative(5000);
                event.accepted = true;
            } else if (event.key === Qt.Key_M) {
                videoLoader.item.toggleMute();
                event.accepted = true;
            } else if (event.key === Qt.Key_BracketLeft) {
                videoLoader.item.cycleSpeed(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_BracketRight) {
                videoLoader.item.cycleSpeed(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Backspace) {
                videoLoader.item.resetSpeed();
                event.accepted = true;
            }
        }
    }

    // Root Backdrop
    Rectangle {
        id: backdrop
        anchors.fill: parent
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
        color: Theme.surfaceBg
        clip: true

        ThemeGradientFill {
            anchors.fill: parent
            enabled: Theme.effectiveSurfaceGradient
            color1: Theme.surfaceBg
            colorMid: Theme.surfaceBgMid
            color2: Theme.surfaceBg2
            cornerRadius: Math.max(root.topRadius, root.bottomRadius)
        }

        // Block pointer pass-through to FilesView beneath
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onClicked: (m) => { m.accepted = true; }
            onWheel: (w) => { w.accepted = true; }
        }

        ColumnLayout {
            id: shellCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Minimal Top Header Bar (slides gently down on entrance)
            Rectangle {
                id: topBar
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                radius: 12
                color: Theme.pillBg
                border.width: 1; border.color: Theme.borderSubtle
                clip: true
                opacity: root._entered ? 1.0 : 0.0
                transform: Translate {
                    y: root._entered ? 0 : -10
                    Behavior on y { NumberAnimation { duration: root._entered ? 260 : 160; easing.type: Easing.OutCubic } }
                }
                Behavior on opacity { NumberAnimation { duration: root._entered ? 220 : 150; easing.type: Easing.OutCubic } }

                ThemeGradientFill {
                    anchors.fill: parent
                    anchors.margins: 1
                    enabled: Theme.effectiveShellGradient
                    color1: Theme.pillBg
                    colorMid: Theme.pillBgMid
                    color2: Theme.pillBg2
                    cornerRadius: 11
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 8
                    spacing: 8

                    SvgIcon {
                        sourceName: root.isVideo ? "video" : "image"
                        iconSize: 16
                        color: Theme.textSub
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.item ? String(root.item.name || "") : ""
                        color: Theme.text
                        font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        readonly property string dimStr: (root.isImage && viewerImg.status === Image.Ready && viewerImg.implicitWidth > 0)
                            ? (viewerImg.implicitWidth + "×" + viewerImg.implicitHeight)
                            : ""
                        readonly property string sizeStr: root.item ? FileService.formatSize(root.item.size) : ""
                        readonly property string posStr: (root.totalCount > 1 && root.currentIndex >= 0)
                            ? ((root.currentIndex + 1) + "/" + root.totalCount)
                            : ""
                        text: [dimStr, sizeStr, posStr].filter(Boolean).join(" • ")
                        visible: text !== ""
                        color: Theme.textMuted
                        font.family: Theme.fontMono; font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    PillButton {
                        visible: root.totalCount > 1
                        iconName: "arrow-left"; iconSize: 13
                        fixedWidth: 28; fixedHeight: 28; radius: 8; subtle: true
                        onClicked: root.stepRequested(-1)
                    }

                    PillButton {
                        visible: root.totalCount > 1
                        iconName: "arrow-right"; iconSize: 13
                        fixedWidth: 28; fixedHeight: 28; radius: 8; subtle: true
                        onClicked: root.stepRequested(1)
                    }

                    PillButton {
                        iconName: "external-link"; iconSize: 13
                        fixedWidth: 28; fixedHeight: 28; radius: 8; subtle: true
                        onClicked: {
                            if (root.mediaPath !== "") root.openExternalRequested(root.mediaPath);
                        }
                    }

                    PillButton {
                        iconName: "close"; iconSize: 13
                        fixedWidth: 28; fixedHeight: 28; radius: 8; subtle: true
                        onClicked: root.closeRequested()
                    }
                }
            }

            // Main Media Stage
            Item {
                id: mediaStageHost
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                transform: Translate { id: stageSlide }

                ParallelAnimation {
                    id: stageSwitchAnim
                    NumberAnimation {
                        target: stageSlide
                        property: "x"
                        from: root.stepDir * 22
                        to: 0
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: mediaStageHost
                        property: "opacity"
                        from: 0.25
                        to: 1.0
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                // 1. IMAGE VIEWER MODE
                Item {
                    id: imageStage
                    anchors.fill: parent
                    visible: root.isImage
                    clip: true

                    onWidthChanged: {
                        const b = root.clampPan(root.panX, root.panY);
                        root.panX = b.x; root.panY = b.y;
                    }
                    onHeightChanged: {
                        const b = root.clampPan(root.panX, root.panY);
                        root.panX = b.x; root.panY = b.y;
                    }

                    Item {
                        id: imageEntranceWrap
                        anchors.fill: parent
                        scale: root._entered ? 1.0 : 0.94
                        opacity: root._entered ? 1.0 : 0.0
                        Behavior on scale { NumberAnimation { duration: root._entered ? 320 : 170; easing.type: root._entered ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 0.8 } }
                        Behavior on opacity { NumberAnimation { duration: root._entered ? 220 : 150; easing.type: Easing.OutCubic } }

                        Image {
                            id: viewerImg
                            anchors.centerIn: parent
                            width: imageStage.width
                            height: imageStage.height
                            source: (root.open && root.isImage) ? root.mediaUrl : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            opacity: status === Image.Ready ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            transform: [
                                Scale {
                                    origin.x: viewerImg.width / 2
                                    origin.y: viewerImg.height / 2
                                    xScale: root.zoom
                                    yScale: root.zoom
                                    Behavior on xScale { enabled: root.smoothTransform; NumberAnimation { duration: root.transformDuration; easing.type: Easing.OutCubic } }
                                    Behavior on yScale { enabled: root.smoothTransform; NumberAnimation { duration: root.transformDuration; easing.type: Easing.OutCubic } }
                                },
                                Translate {
                                    x: root.panX
                                    y: root.panY
                                    Behavior on x { enabled: root.smoothTransform; NumberAnimation { duration: root.transformDuration; easing.type: Easing.OutCubic } }
                                    Behavior on y { enabled: root.smoothTransform; NumberAnimation { duration: root.transformDuration; easing.type: Easing.OutCubic } }
                                }
                            ]
                        }
                    }

                    // Error / loading fallback for Image
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        opacity: viewerImg.status === Image.Error ? 1.0 : 0.0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        SvgIcon {
                            Layout.alignment: Qt.AlignHCenter
                            sourceName: "image"; iconSize: 28; color: Theme.warn
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Unable to display this image"
                            color: Theme.textSub
                            font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.Medium
                        }
                    }

                    // Wheel Zoom + Drag Pan + Double-Click Zoom
                    MouseArea {
                        id: imageMouse
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        hoverEnabled: true
                        cursorShape: root.zoom > 1.01
                            ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                            : Qt.ArrowCursor

                        property real dragStartX: 0
                        property real dragStartY: 0
                        property real panStartX: 0
                        property real panStartY: 0

                        onPressed: (mouse) => {
                            root.forceActiveFocus();
                            dragStartX = mouse.x;
                            dragStartY = mouse.y;
                            panStartX = root.panX;
                            panStartY = root.panY;
                        }

                        onPositionChanged: (mouse) => {
                            if (!pressed || root.zoom <= 1.01) return;
                            root.smoothTransform = false;
                            const bounded = root.clampPan(
                                panStartX + (mouse.x - dragStartX),
                                panStartY + (mouse.y - dragStartY)
                            );
                            root.panX = bounded.x;
                            root.panY = bounded.y;
                        }

                        onDoubleClicked: (mouse) => {
                            if (root.zoom > 1.05) {
                                root.resetView(true);
                            } else {
                                root.applyZoom(2.5, mouse.x, mouse.y, true);
                            }
                        }

                        onWheel: (wheel) => {
                            const dy = wheel.angleDelta.y;
                            if (dy === 0) return;
                            const factor = dy > 0 ? 1.18 : (1 / 1.18);
                            root.zoomBy(factor, wheel.x, wheel.y, true, 95);
                            wheel.accepted = true;
                        }
                    }

                    // Minimal Floating Zoom Pill (slides up with spring on entrance)
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        height: 36
                        width: zoomRow.implicitWidth + 12
                        radius: 12
                        color: Theme.pillBg
                        border.width: 1; border.color: Theme.borderSubtle
                        clip: true
                        opacity: root._entered ? 1.0 : 0.0
                        scale: root._entered ? 1.0 : 0.95
                        transform: Translate {
                            y: root._entered ? 0 : 14
                            Behavior on y { NumberAnimation { duration: root._entered ? 300 : 160; easing.type: root._entered ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 0.8 } }
                        }
                        Behavior on opacity { NumberAnimation { duration: root._entered ? 220 : 150; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: root._entered ? 300 : 160; easing.type: root._entered ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 0.8 } }

                        ThemeGradientFill {
                            anchors.fill: parent
                            anchors.margins: 1
                            enabled: Theme.effectiveShellGradient
                            color1: Theme.pillBg
                            colorMid: Theme.pillBgMid
                            color2: Theme.pillBg2
                            cornerRadius: 11
                        }

                        RowLayout {
                            id: zoomRow
                            anchors.centerIn: parent
                            spacing: 4

                            PillButton {
                                iconName: "minus"; iconSize: 13
                                fixedWidth: 28; fixedHeight: 28; radius: 8; subtle: true
                                enabled: root.zoom > root.minZoom + 0.01
                                onClicked: root.zoomBy(1 / 1.25, undefined, undefined, true)
                            }

                            PillButton {
                                text: Math.round(root.zoom * 100) + "%"
                                fontFamily: Theme.fontMono
                                fontSize: 11
                                fixedWidth: 54; fixedHeight: 28; radius: 8
                                subtle: Math.abs(root.zoom - 1.0) <= 0.02
                                active: Math.abs(root.zoom - 1.0) > 0.02
                                onClicked: root.resetView(true)
                            }

                            PillButton {
                                iconName: "plus"; iconSize: 13
                                fixedWidth: 28; fixedHeight: 28; radius: 8; subtle: true
                                enabled: root.zoom < root.maxZoom - 0.01
                                onClicked: root.zoomBy(1.25, undefined, undefined, true)
                            }
                        }
                    }
                }

                // 2. VIDEO WATCHER MODE (lazy-loaded so QtMultimedia only imports on demand)
                Loader {
                    id: videoLoader
                    anchors.fill: parent
                    active: root.open && root.isVideo
                    visible: root.isVideo
                    source: "MediaVideoPane.qml"
                    onLoaded: {
                        if (item) {
                            item.active = Qt.binding(() => root.open && root.isVideo);
                            item.entered = Qt.binding(() => root._entered && root.isVideo);
                            item.source = Qt.binding(() => (root.open && root.isVideo) ? root.mediaUrl : "");
                            item.openExternalRequested.connect(() => {
                                if (root.mediaPath !== "") root.openExternalRequested(root.mediaPath);
                            });
                        }
                    }
                }

                // Graceful fallback if QtMultimedia plugin is missing
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    visible: root.isVideo && videoLoader.status === Loader.Error
                    width: Math.min(320, parent.width - 32)

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 44; height: 44; radius: 12
                        color: Theme.surfaceRaised
                        border.width: 1; border.color: Theme.borderSubtle
                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: "video"; iconSize: 20; color: Theme.warn
                        }
                    }

                    Text {
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        horizontalAlignment: Text.AlignHCenter
                        text: "Video playback unavailable"
                        color: Theme.text
                        font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        horizontalAlignment: Text.AlignHCenter
                        text: "Re-run the Paithosh installer to enable built-in video playback."
                        color: Theme.textSub
                        font.family: Theme.fontSans; font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    PillButton {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Open Externally"
                        iconName: "external-link"
                        onClicked: {
                            if (root.mediaPath !== "") root.openExternalRequested(root.mediaPath);
                        }
                    }
                }
            }
        }
    }
}
