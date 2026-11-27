import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "../services"
import "common"

Item {
    id: root

    required property var shellState

    property var portalSources: []
    property int selectedIdx: 0
    property bool shareAudio: true
    property bool submitted: false

    Component.onCompleted: refreshSources()

    Component.onDestruction: {
        if (!submitted && shellState.portalResultPath !== "") {
            writeResult("CANCEL");
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
                cls: "",
                title: "",
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

    function refreshSources() {
        selectedIdx = 0;
        submitted = false;
        portalSources = buildMonitorSources().concat([
            { kind: "region", id: "region", cls: "", title: "", name: "Select Region", sub: "Drag area with slurp", thumb: "Region" }
        ]);
        if (shellState.portalWindowsPath !== "") {
            xdphWinProc.command = ["cat", shellState.portalWindowsPath];
            xdphWinProc.running = true;
        } else if (CompositorService.isHyprland) {
            hyprWinProc.running = true;
        }
    }

    function writeResult(value) {
        const path = shellState.portalResultPath;
        if (!path) return;
        submitted = true;
        shellState.portalResultPath = "";
        shellState.portalWindowsPath = "";
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"", "_", value, path]);
    }

    function submitSelection() {
        if (selectedIdx < 0 || selectedIdx >= portalSources.length) {
            writeResult("CANCEL");
            shellState.collapseIslandApp();
            return;
        }
        const src = portalSources[selectedIdx];
        if (src.kind === "region") {
            slurpProc.running = true;
            return;
        }
        const prefix = src.kind === "window" ? "/window:" : "/screen:";
        writeResult("[SELECTION]" + prefix + src.id);
        shellState.collapseIslandApp();
    }

    Process {
        id: xdphWinProc
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                const mons = root.buildMonitorSources();
                const wins = root.parseXdphWindows(data);
                root.portalSources = mons.concat(wins).concat([
                    { kind: "region", id: "region", cls: "", title: "", name: "Select Region", sub: "Drag area with slurp", thumb: "Region" }
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
                    for (let i = 0; i < Math.min(clients.length, 12); i++) {
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
                        { kind: "region", id: "region", cls: "", title: "", name: "Select Region", sub: "Drag area with slurp", thumb: "Region" }
                    ]);
                } catch (e) {}
            }
        }
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
                root.writeResult("[SELECTION]/region:" + slurpProc.capturedRegion);
            } else {
                root.writeResult("CANCEL");
            }
            slurpProc.capturedRegion = "";
            root.shellState.collapseIslandApp();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                spacing: 2
                Text {
                    text: "XDG Desktop Portal • Screen Share"
                    color: Theme.text
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }
                Text {
                    text: "Select a display, application window, or custom region to stream"
                    color: Theme.textSub
                    font.pixelSize: 11
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.portalSources.length + " sources"
                color: Theme.textMuted
                font.pixelSize: 11
                font.family: Theme.fontMono
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: grid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            GridLayout {
                id: grid
                width: parent.width
                columns: 3
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: root.portalSources
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        readonly property bool sel: root.selectedIdx === index
                        Layout.fillWidth: true
                        height: 156
                        radius: 12
                        color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1.5
                        border.color: sel ? Theme.accent : Theme.borderSubtle
                        clip: true

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 7

                            Rectangle {
                                Layout.fillWidth: true
                                height: 90
                                radius: 8
                                color: "#060607"
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.12)
                                clip: true

                                ScreencopyView {
                                    id: previewView
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    captureSource: root.resolveCaptureSource(modelData)
                                    live: !Theme.reduceMotion
                                    visible: captureSource !== null && hasContent
                                }

                                Rectangle {
                                    visible: !previewView.visible
                                    width: 30
                                    height: 5
                                    radius: 2.5
                                    color: Qt.rgba(1, 1, 1, 0.35)
                                    anchors.top: parent.top
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    visible: !previewView.visible
                                    anchors.centerIn: parent
                                    text: modelData.thumb
                                    color: Theme.textSub
                                    font.pixelSize: 12
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
                            onClicked: root.selectedIdx = index
                            onDoubleClicked: {
                                root.selectedIdx = index;
                                root.submitSelection();
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

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
                            visible: root.shareAudio
                            text: "✓"
                            color: "#000000"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        text: "Share system audio via PipeWire"
                        color: Theme.text
                        font.pixelSize: 12
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.shareAudio = !root.shareAudio
                }
            }

            PillButton {
                text: "Cancel"
                horizontalPadding: 18
                verticalPadding: 8
                onClicked: {
                    root.writeResult("CANCEL");
                    root.shellState.collapseIslandApp();
                }
            }

            PillButton {
                text: "Share Stream"
                active: true
                horizontalPadding: 18
                verticalPadding: 8
                onClicked: root.submitSelection()
            }
        }
    }
}
