pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool enabled: true
    property bool capsLockEnabled: true
    property bool fcitxEnabled: true

    readonly property bool shouldWatch: enabled && (capsLockEnabled || fcitxEnabled)
    readonly property bool suppressFcitxPopup: enabled && fcitxEnabled

    signal indicatorTriggered(string kind, string label, string badge, bool active)

    readonly property string _scriptPath: decodeURIComponent(
        Qt.resolvedUrl("../scripts/paithosh-input-indicator.py").toString().replace(/^file:\/\//, "")
    )

    onShouldWatchChanged: syncWatcher()
    onCapsLockEnabledChanged: if (shouldWatch) restartWatcher()
    onFcitxEnabledChanged: if (shouldWatch) restartWatcher()
    onSuppressFcitxPopupChanged: fcitxPopupSyncTimer.restart()

    Component.onCompleted: {
        syncWatcher();
        fcitxPopupSyncTimer.restart();
    }

    function syncWatcher() {
        if (shouldWatch) {
            if (!watchProc.running) {
                watchProc.command = [
                    "python3", _scriptPath, "watch",
                    "--caps", capsLockEnabled ? "1" : "0",
                    "--fcitx", fcitxEnabled ? "1" : "0"
                ];
                watchProc.running = true;
            }
        } else {
            if (watchProc.running) watchProc.running = false;
        }
    }

    function restartWatcher() {
        if (watchProc.running) watchProc.running = false;
        restartTimer.restart();
    }

    Timer {
        id: restartTimer
        interval: 80
        repeat: false
        onTriggered: root.syncWatcher()
    }

    Timer {
        id: fcitxPopupSyncTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (fcitxPopupProc.running) fcitxPopupProc.running = false;
            fcitxPopupProc.command = [
                "python3", root._scriptPath, "set-fcitx-popup",
                root.suppressFcitxPopup ? "false" : "true"
            ];
            fcitxPopupProc.running = true;
        }
    }

    Process {
        id: watchProc
        running: false
        stdout: SplitParser {
            onRead: (line) => {
                const s = (line || "").trim();
                if (!s) return;
                try {
                    const ev = JSON.parse(s);
                    if (ev && ev.kind) {
                        root.indicatorTriggered(
                            String(ev.kind),
                            String(ev.label || ""),
                            String(ev.badge || ""),
                            Boolean(ev.active)
                        );
                    }
                } catch (e) {
                    // ignore malformed line
                }
            }
        }
    }

    Process {
        id: fcitxPopupProc
        running: false
    }
}
