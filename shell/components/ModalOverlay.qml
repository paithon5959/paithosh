import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "../services"
import "common"

PanelWindow {
    id: root

    required property var shellState

    readonly property bool isOpen: shellState.modalKind !== ""
    readonly property string kind: shellState.modalKind

    property string monitorMode: CompositorService.previewMonitorMode
    property string portalTab: "display" // "display" | "portal"
    property int selectedPortalIdx: 0
    property bool shareAudio: true
    property int progressVal: 0
    property var portalSources: []
    property bool portalSubmitted: false

    screen: shellState.activeScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    visible: isOpen || backdrop.opacity > 0.01

    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "paithosh-modal"
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    Item {
        id: fullMask
        anchors.fill: parent
    }

    mask: Region {
        item: root.isOpen ? fullMask : emptyMask
    }

    onKindChanged: {
        if (kind === "progress") {
            progressVal = 0;
            progTimer.restart();
        } else {
            progTimer.stop();
        }
        if (kind === "monitor") {
            portalTab = root.shellState.portalInitialTab || "display";
            monitorMode = CompositorService.previewMonitorMode;
            selectedPortalIdx = 0;
            portalSubmitted = false;
            refreshPortalSources();
        }
        if (kind === "" && root.shellState.portalResultPath !== "" && !portalSubmitted) {
            writePortalResult("CANCEL");
        }
        if (kind !== "") {
            modalFocus.forceActiveFocus();
        }
    }

    function buildMonitorSources() {
        const list = [];
        const mons = CompositorService.monitorsList() || [];
        for (let i = 0; i < mons.length; i++) {
            const m = mons[i];
            list.push({
                kind: "screen",
                id: m.name,
                name: "Screen: " + m.name,
                sub: (m.primary ? "Primary • " : "") + (m.refreshRate || 60) + "Hz",
                thumb: (m.width || 1920) + " × " + (m.height || 1080)
            });
        }
        return list;
    }

    function parseXdphWindows(raw) {
        const wins = [];
        if (!raw || !raw.trim()) return wins;
        const entries = raw.split("[HE>]");
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i].trim();
            if (!entry) continue;
            const hcIdx = entry.indexOf("[HC>]");
            const htIdx = entry.indexOf("[HT>]");
            if (hcIdx === -1 || htIdx === -1) continue;
            let id = entry.slice(0, hcIdx);
            const haIdx = id.lastIndexOf("[HA>]");
            if (haIdx !== -1) {
                id = id.slice(haIdx + 5);
            }
            const cls = entry.slice(hcIdx + 5, htIdx);
            const title = entry.slice(htIdx + 5);
            wins.push({
                kind: "window",
                id: id,
                cls: cls,
                title: title,
                name: title || cls || "Window",
                sub: (cls || "Wayland") + " • Window",
                thumb: "Window"
            });
        }
        return wins;
    }

    function resolveCaptureSource(src) {
        if (!src) return null;
        if (src.kind === "screen") {
            for (let i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i].name === src.id) return Quickshell.screens[i];
            }
            return null;
        }
        if (src.kind === "window") {
            if (Hyprland.toplevels && Hyprland.toplevels.values) {
                const vals = Hyprland.toplevels.values;
                for (let i = 0; i < vals.length; i++) {
                    const tl = vals[i];
                    if (!tl || !tl.wayland) continue;
                    const ipc = tl.lastIpcObject;
                    if (src.title && tl.title === src.title && (!src.cls || (ipc && ipc.class === src.cls))) {
                        return tl.wayland;
                    }
                }
                for (let i = 0; i < vals.length; i++) {
                    const tl = vals[i];
                    if (tl && tl.wayland && src.title && tl.title === src.title) {
                        return tl.wayland;
                    }
                }
            }
            if (ToplevelManager.toplevels && ToplevelManager.toplevels.values) {
                const tvals = ToplevelManager.toplevels.values;
                for (let i = 0; i < tvals.length; i++) {
                    const tl = tvals[i];
                    if (tl && src.title && tl.title === src.title) return tl;
                }
            }
        }
        return null;
    }

    function refreshPortalSources() {
        portalSources = buildMonitorSources().concat([
            { kind: "region", id: "region", name: "Select Region", sub: "Drag area with slurp", thumb: "Region" }
        ]);
        if (root.shellState.portalWindowsPath !== "") {
            xdphWinProc.command = ["cat", root.shellState.portalWindowsPath];
            xdphWinProc.running = true;
        } else if (CompositorService.isHyprland) {
            hyprWinProc.running = true;
        }
    }

    function writePortalResult(value) {
        const path = root.shellState.portalResultPath;
        if (!path) return;
        portalSubmitted = true;
        root.shellState.portalResultPath = "";
        root.shellState.portalWindowsPath = "";
        portalWriteProc.command = ["sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"", "_", value, path];
        portalWriteProc.running = true;
    }

    function submitPortalSelection() {
        if (selectedPortalIdx < 0 || selectedPortalIdx >= portalSources.length) {
            writePortalResult("CANCEL");
            root.shellState.closeModal();
            return;
        }
        const src = portalSources[selectedPortalIdx];
        if (src.kind === "region") {
            slurpProc.running = true;
            return;
        }
        const prefix = src.kind === "window" ? "/window:" : "/screen:";
        writePortalResult("[SELECTION]" + prefix + src.id);
        root.shellState.closeModal();
    }

    Process {
        id: xdphWinProc
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                const mons = root.buildMonitorSources();
                const wins = root.parseXdphWindows(data);
                root.portalSources = mons.concat(wins).concat([
                    { kind: "region", id: "region", name: "Select Region", sub: "Drag area with slurp", thumb: "Region" }
                ]);
            }
        }
    }

    Process {
        id: hyprWinProc
        command: ["hyprctl", "clients", "-j"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                try {
                    const clients = JSON.parse(data);
                    const wins = [];
                    for (let i = 0; i < Math.min(clients.length, 8); i++) {
                        const c = clients[i];
                        if (!c.mapped) continue;
                        wins.push({
                            kind: "window",
                            id: c.address || String(i),
                            cls: c.class || "",
                            title: c.title || "",
                            name: c.title || c.class || "Window",
                            sub: (c.class || "Wayland") + " • Window",
                            thumb: "Window"
                        });
                    }
                    root.portalSources = root.buildMonitorSources().concat(wins).concat([
                        { kind: "region", id: "region", name: "Select Region", sub: "Drag area with slurp", thumb: "Region" }
                    ]);
                } catch (e) {}
            }
        }
    }

    Process {
        id: portalWriteProc
    }

    Process {
        id: slurpProc
        command: ["slurp", "-f", "%o@%x,%y,%w,%h"]
        property string capturedRegion: ""
        stdout: SplitParser {
            onRead: data => {
                if (data.trim()) slurpProc.capturedRegion = data.trim();
            }
        }
        onExited: (code, status) => {
            if (code === 0 && slurpProc.capturedRegion !== "") {
                root.writePortalResult("[SELECTION]/region:" + slurpProc.capturedRegion);
            } else {
                root.writePortalResult("CANCEL");
            }
            slurpProc.capturedRegion = "";
            root.shellState.closeModal();
        }
    }

    Timer {
        id: progTimer
        interval: 240
        repeat: true
        onTriggered: {
            root.progressVal = Math.min(100, root.progressVal + 12);
            if (root.progressVal >= 100) progTimer.stop();
        }
    }

    Item {
        id: modalFocus
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.shellState.closeModal()
    }

    Rectangle {
        id: backdrop
        readonly property bool isBottom: root.shellState.barPosition === "bottom"
        anchors.fill: parent
        anchors.topMargin: (root.kind === "monitor" && !isBottom) ? (Theme.topOffsetHover + Theme.islandHeight) : 0
        anchors.bottomMargin: (root.kind === "monitor" && isBottom) ? (Theme.topOffsetHover + Theme.islandHeight) : 0
        color: (root.kind === "monitor" && root.portalTab === "portal") ? Qt.rgba(0, 0, 0, 0.72) : Qt.rgba(0, 0, 0, 0.52)
        opacity: root.isOpen ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.isOpen
            onClicked: root.shellState.closeModal()
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.kind === "monitor"
                ? (backdrop.isBottom
                    ? (parent.height - height + (root.isOpen ? 0 : 12))
                    : (root.isOpen ? 0 : -12))
                : (parent.height - height) / 2
            transformOrigin: root.kind === "monitor" ? (backdrop.isBottom ? Item.Bottom : Item.Top) : Item.Center
            width: Math.min(parent.width - 32, root.kind === "monitor" ? 640 : 380)
            height: cardCol.implicitHeight + 40
            radius: 20
            color: Theme.surfaceBg
            border.width: 1
            border.color: Theme.borderSubtle
            clip: true
            scale: root.isOpen ? 1.0 : 0.92
            anchors.verticalCenterOffset: root.isOpen ? 0 : 10

            Behavior on width { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: 1.25 } }
            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack } }

            ThemeGradientFill {
                anchors.fill: parent
                anchors.margins: 1
                enabled: Theme.surfaceGradientEnabled
                color1: Theme.surfaceBg
                colorMid: Theme.surfaceBgMid
                color2: Theme.surfaceBg2
                cornerRadius: 19
            }

            MouseArea {
                anchors.fill: parent
                onClicked: function(mouse) { mouse.accepted = true; }
            }

            ColumnLayout {
                id: cardCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 20
                spacing: 14

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (root.kind === "confirm") return "Reload Hyprland Config?";
                        if (root.kind === "multi") return "Select Output Profile";
                        if (root.kind === "monitor") return "Display & XDG Portal";
                        if (root.kind === "progress") return "Updating System Packages";
                        return "";
                    }
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (root.kind === "confirm") return "Unsaved decoration tweaks will be applied immediately across all windows.";
                        if (root.kind === "multi") return "Choose a display & power preset for your current session:";
                        if (root.kind === "monitor") return "Configure connected monitors or pick a source to share (Discord / OBS):";
                        if (root.kind === "progress") return "Installing hyprland 0.45.2-1 (18.4 MB)...";
                        return "";
                    }
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                // Multi-Option Body
                ColumnLayout {
                    visible: root.kind === "multi"
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { title: "Presentation (Mirror)", sub: "1920×1080", mode: "mirror" },
                            { title: "Extend Workspace", sub: "2560×1600", mode: "extend-right" },
                            { title: "External Monitor Only", sub: "165Hz", mode: "ext-only" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            height: 42
                            radius: 12
                            color: optMouse.containsMouse ? Theme.cardHover : Qt.rgba(1, 1, 1, 0.07)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            scale: optMouse.pressed ? 0.97 : 1.0

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    color: Theme.text
                                    font.family: Theme.fontSans
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: modelData.sub
                                    color: Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                }
                            }

                            MouseArea {
                                id: optMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    CompositorService.applyMonitorLayout(modelData.mode);
                                    root.shellState.closeModal();
                                }
                            }
                        }
                    }
                }

                // Monitor + XDG Portal Body
                ColumnLayout {
                    visible: root.kind === "monitor"
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.06)

                        GridLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            columns: 2
                            columnSpacing: 4

                            Repeater {
                                model: [
                                    { key: "display", label: "Monitor Arrangement" },
                                    { key: "portal", label: "XDG Portal (Screen Share)" }
                                ]
                                delegate: PillButton {
                                    required property var modelData
                                    text: modelData.label
                                    active: root.portalTab === modelData.key
                                    fillWidth: true
                                    fontSize: 11
                                    radius: 9
                                    onClicked: root.portalTab = modelData.key
                                }
                            }
                        }
                    }

                    // Display Arrangement Subtab
                    ColumnLayout {
                        visible: root.portalTab === "display"
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            height: 110
                            radius: 14
                            color: "#060607"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            clip: true

                            readonly property var mons: CompositorService.monitorsList()
                            readonly property string nameA: mons.length > 0 ? mons[0].name : "eDP-1"
                            readonly property string resA: mons.length > 0 ? (mons[0].width + "×" + mons[0].height) : "2560×1600"
                            readonly property string nameB: mons.length > 1 ? mons[1].name : "HDMI-A-1"
                            readonly property string resB: mons.length > 1 ? (mons[1].width + "×" + mons[1].height) : "1920×1080"

                            Rectangle {
                                id: primaryMonBox
                                width: 108
                                height: 64
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1.5
                                border.color: Qt.rgba(1, 1, 1, 0.45)
                                anchors.verticalCenter: parent.verticalCenter
                                x: {
                                    if (root.monitorMode === "extend-left") return 260;
                                    if (root.monitorMode === "mirror") return 174;
                                    if (root.monitorMode === "ext-only") return 96;
                                    return 112;
                                }
                                scale: root.monitorMode === "mirror" ? 0.95 : (root.monitorMode === "ext-only" ? 0.85 : 1.0)
                                opacity: root.monitorMode === "mirror" ? 0.45 : (root.monitorMode === "ext-only" ? 0.20 : 1.0)

                                Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }
                                Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }
                                Behavior on opacity { NumberAnimation { duration: 260 } }

                                Column {
                                    anchors.centerIn: parent
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: primaryMonBox.parent.nameA; color: Theme.text; font.pixelSize: 11; font.weight: Font.Bold }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: primaryMonBox.parent.resA; color: Theme.textSub; font.pixelSize: 9 }
                                }
                            }

                            Rectangle {
                                id: extMonBox
                                width: 118
                                height: 68
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.18)
                                border.width: 1.5
                                border.color: Theme.text
                                anchors.verticalCenter: parent.verticalCenter
                                x: {
                                    if (root.monitorMode === "extend-left") return 124;
                                    if (root.monitorMode === "mirror") return 184;
                                    if (root.monitorMode === "ext-only") return 181;
                                    return 234;
                                }
                                scale: root.monitorMode === "ext-only" ? 1.06 : 1.0

                                Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }
                                Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }

                                Column {
                                    anchors.centerIn: parent
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: extMonBox.parent.nameB; color: Theme.text; font.pixelSize: 11; font.weight: Font.Bold }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: extMonBox.parent.resB; color: Theme.textSub; font.pixelSize: 9 }
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 8
                            rowSpacing: 8

                            Repeater {
                                model: [
                                    { key: "extend-right", label: "Extend Right", sub: "eDP → HDMI" },
                                    { key: "extend-left", label: "Extend Left", sub: "HDMI → eDP" },
                                    { key: "mirror", label: "Mirror", sub: "1 = 2" },
                                    { key: "ext-only", label: "External Only", sub: "HDMI-A-1" }
                                ]
                                delegate: PillButton {
                                    required property var modelData
                                    text: modelData.label + " (" + modelData.sub + ")"
                                    active: root.monitorMode === modelData.key
                                    fillWidth: true
                                    fontSize: 11
                                    radius: 12
                                    verticalPadding: 8
                                    onClicked: root.monitorMode = modelData.key
                                }
                            }
                        }
                    }

                    // XDG Portal Subtab
                    ColumnLayout {
                        visible: root.portalTab === "portal"
                        Layout.fillWidth: true
                        spacing: 8

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 8
                            rowSpacing: 8

                            Repeater {
                                model: root.portalSources
                                delegate: Rectangle {
                                    required property int index
                                    required property var modelData
                                    readonly property bool sel: root.selectedPortalIdx === index
                                    Layout.fillWidth: true
                                    height: 140
                                    radius: 12
                                    color: sel ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                                    border.width: 1.5
                                    border.color: sel ? Theme.text : Qt.rgba(1, 1, 1, 0.10)
                                    clip: true

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 6

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 76
                                            radius: 8
                                            color: "#060607"
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.12)
                                            clip: true

                                            ScreencopyView {
                                                id: previewView
                                                anchors.fill: parent
                                                anchors.margins: 1
                                                captureSource: root.isOpen && root.portalTab === "portal" ? root.resolveCaptureSource(modelData) : null
                                                live: true
                                                visible: captureSource !== null && hasContent
                                            }

                                            Rectangle {
                                                visible: !previewView.visible
                                                width: 30
                                                height: 5
                                                radius: 2.5
                                                color: Qt.rgba(1, 1, 1, 0.35)
                                                anchors.top: parent.top
                                                anchors.topMargin: 6
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }
                                            Text {
                                                visible: !previewView.visible
                                                anchors.centerIn: parent
                                                text: modelData.thumb
                                                color: Theme.textSub
                                                font.pixelSize: 11
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            color: Theme.text
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.sub
                                            color: Theme.textSub
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedPortalIdx = index
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            radius: 10
                            color: Qt.rgba(1, 1, 1, 0.06)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 4
                                    color: root.shareAudio ? Theme.accent : "transparent"
                                    border.width: 1.5
                                    border.color: root.shareAudio ? Theme.accent : Qt.rgba(1, 1, 1, 0.4)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✓"
                                        color: Theme.accentFg
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        visible: root.shareAudio
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Share system audio via PipeWire"
                                    color: Qt.rgba(1, 1, 1, 0.85)
                                    font.pixelSize: 12
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.shareAudio = !root.shareAudio
                            }
                        }
                    }
                }

                // Progress Body
                ColumnLayout {
                    visible: root.kind === "progress"
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.14)
                        clip: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: 3
                            color: Theme.text
                            width: parent.width * (root.progressVal / 100.0)
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: {
                                if (root.progressVal >= 100) return "Done ✓";
                                if (root.progressVal >= 60) return "Installing hyprland...";
                                if (root.progressVal >= 30) return "Verifying PGP...";
                                return "Downloading...";
                            }
                            color: Theme.textSub
                            font.pixelSize: 11
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.progressVal + "%"
                            color: Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                }

                // Footer Actions
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    PillButton {
                        visible: root.kind !== "progress" || root.progressVal < 100
                        text: "Cancel"
                        horizontalPadding: 16
                        verticalPadding: 8
                        onClicked: root.shellState.closeModal()
                    }

                    PillButton {
                        visible: root.kind === "confirm" || root.kind === "monitor" || (root.kind === "progress" && root.progressVal >= 100)
                        text: {
                            if (root.kind === "monitor") return root.portalTab === "portal" ? "Share Stream" : "Apply";
                            if (root.kind === "progress") return "Done";
                            return "Confirm";
                        }
                        active: true
                        horizontalPadding: 16
                        verticalPadding: 8
                        onClicked: {
                            if (root.kind === "confirm" && CompositorService.isHyprland) {
                                Quickshell.execDetached(["hyprctl", "reload"]);
                            } else if (root.kind === "monitor" && root.portalTab === "display") {
                                CompositorService.applyMonitorLayout(root.monitorMode);
                            } else if (root.kind === "monitor" && root.portalTab === "portal") {
                                root.submitPortalSelection();
                                return;
                            }
                            root.shellState.closeModal();
                        }
                    }
                }
            }
        }
    }
}
