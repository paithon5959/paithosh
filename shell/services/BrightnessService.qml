pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int brightnessPct: 85
    property string backlightDir: ""
    property int maxBrightness: 100
    property bool hasBrightnessctl: false

    signal osdTriggered(string kind, int value)

    Process {
        id: probeProc
        command: ["sh", "-c", "ls -d /sys/class/backlight/* 2>/dev/null | head -n1; command -v brightnessctl || true"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length >= 1 && lines[0].startsWith("/sys/class/backlight/")) {
                    root.backlightDir = lines[0];
                    readProc.running = true;
                }
                if (lines.length >= 2 && lines[1].indexOf("brightnessctl") !== -1) {
                    root.hasBrightnessctl = true;
                }
            }
        }
    }

    Process {
        id: readProc
        command: ["sh", "-c", "cat \"$1/brightness\" \"$1/max_brightness\" 2>/dev/null", "sh", root.backlightDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                if (parts.length >= 2) {
                    const cur = parseInt(parts[0], 10);
                    const max = parseInt(parts[1], 10);
                    if (max > 0 && !isNaN(cur)) {
                        root.maxBrightness = max;
                        root.brightnessPct = Math.max(10, Math.min(100, Math.round((cur / max) * 100)));
                    }
                }
            }
        }
    }

    Process {
        id: kdeWriteProc
        property int targetVal: 8500
        command: [
            "gdbus", "call", "--session",
            "--dest", "org.kde.Solid.PowerManagement",
            "--object-path", "/org/kde/Solid/PowerManagement/Actions/BrightnessControl",
            "--method", "org.kde.Solid.PowerManagement.Actions.BrightnessControl.setBrightness",
            String(kdeWriteProc.targetVal)
        ]
    }

    function setBrightness(pct, emitOsd) {
        const clamped = Math.max(10, Math.min(100, Math.round(pct)));
        brightnessPct = clamped;
        if (hasBrightnessctl) {
            Quickshell.execDetached(["brightnessctl", "set", clamped + "%"]);
        } else if (backlightDir !== "") {
            kdeWriteProc.targetVal = Math.round((clamped / 100.0) * maxBrightness);
            kdeWriteProc.running = true;
        }
        if (emitOsd !== false) osdTriggered("bri", clamped);
    }

    function adjustBrightness(delta) {
        setBrightness(brightnessPct + delta, true);
    }
}
