pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool online: false
    property string deviceId: ""
    property string deviceName: "No paired device"
    property int batteryPct: 84

    signal dropStatusChanged(bool active, string message, bool done)

    Process {
        id: probeProc
        command: ["kdeconnect-cli", "--list-available", "--id-name-only"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim().split("\n")[0] || "";
                if (line !== "" && line.indexOf("0 devices") === -1) {
                    const parts = line.split(/\s+/);
                    root.deviceId = parts[0] || "";
                    root.deviceName = parts.slice(1).join(" ") || "KDE Connect Device";
                    root.online = root.deviceId !== "";
                } else {
                    root.online = false;
                    root.deviceId = "";
                    root.deviceName = "Pixel 8 Pro (Preview)";
                }
            }
        }
    }

    function refresh() {
        probeProc.running = true;
    }

    function ping() {
        if (online && deviceId !== "") Quickshell.execDetached(["kdeconnect-cli", "-d", deviceId, "--ping"]);
    }

    function sendClipboard() {
        if (online && deviceId !== "") {
            Quickshell.execDetached(["sh", "-c", "kdeconnect-cli -d \"$1\" --share-text \"$(wl-paste 2>/dev/null || echo Paithosh)\"", "sh", deviceId]);
        }
    }

    function ring() {
        if (online && deviceId !== "") Quickshell.execDetached(["kdeconnect-cli", "-d", deviceId, "--ring"]);
    }

    function browseFiles() {
        if (online && deviceId !== "") Quickshell.execDetached(["xdg-open", "kdeconnect://" + deviceId]);
    }

    function sendFile(pathOrName) {
        const clean = String(pathOrName || "file").replace(/^file:\/\//, "");
        const base = clean.split("/").pop() || clean;
        dropStatusChanged(true, "Sending " + base + " → KDE Connect...", false);
        if (online && deviceId !== "" && clean.startsWith("/")) {
            Quickshell.execDetached(["kdeconnect-cli", "-d", deviceId, "--share", clean]);
        }
        dropDoneTimer.lastBase = base;
        dropDoneTimer.restart();
    }

    Timer {
        id: dropDoneTimer
        property string lastBase: "file"
        interval: 650
        repeat: false
        onTriggered: {
            root.dropStatusChanged(true, "Sent " + lastBase + " via KDE Connect ✓", true);
            dropHideTimer.restart();
        }
    }

    Timer {
        id: dropHideTimer
        interval: 2200
        repeat: false
        onTriggered: root.dropStatusChanged(false, "", false)
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
