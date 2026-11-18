pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: bat !== null && bat.isPresent
    property int fallbackPct: 84
    property bool fallbackCharging: false
    property bool initialized: false
    property bool lastCharging: false

    readonly property int batteryPct: hasBattery ? Math.round(bat.percentage * 100) : fallbackPct
    readonly property bool charging: hasBattery ? !UPower.onBattery : fallbackCharging
    readonly property int healthPct: (hasBattery && bat.healthSupported) ? Math.round(bat.healthPercentage) : 96
    readonly property bool lowBatteryAlert: hasBattery && !charging && batteryPct <= 15

    readonly property string timeRemaining: {
        if (!hasBattery) return "3h 42m remaining";
        const secs = charging ? bat.timeToFull : bat.timeToEmpty;
        if (!secs || secs <= 0) return charging ? "Charging (AC)" : "On Battery";
        const h = Math.floor(secs / 3600);
        const m = Math.floor((secs % 3600) / 60);
        return h + "h " + m + "m " + (charging ? "to full" : "remaining");
    }

    readonly property string powerProfile: {
        if (typeof PowerProfiles !== "undefined" && PowerProfiles) {
            if (PowerProfiles.profile === PowerProfile.PowerSaver) return "Power Saver";
            if (PowerProfiles.profile === PowerProfile.Performance) return "Performance";
        }
        return "Balanced";
    }

    signal chargerChanged(bool charging, int pct)

    onChargingChanged: {
        if (!initialized) {
            lastCharging = charging;
            initialized = true;
            return;
        }
        if (charging !== lastCharging) {
            lastCharging = charging;
            chargerChanged(charging, batteryPct);
        }
    }

    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: {
            root.lastCharging = root.charging;
            root.initialized = true;
        }
    }

    function triggerPreviewCharger() {
        fallbackCharging = !fallbackCharging;
        chargerChanged(fallbackCharging, batteryPct);
    }

    function setPowerProfile(name) {
        if (typeof PowerProfiles === "undefined" || !PowerProfiles) return;
        if (name === "Power Saver") PowerProfiles.profile = PowerProfile.PowerSaver;
        else if (name === "Performance" && PowerProfiles.hasPerformanceProfile) PowerProfiles.profile = PowerProfile.Performance;
        else PowerProfiles.profile = PowerProfile.Balanced;
    }

    function executeAction(action) {
        if (action === "Lock") {
            Quickshell.execDetached(["sh", "-c", "command -v hyprlock >/dev/null && hyprlock || loginctl lock-session"]);
        } else if (action === "Suspend") {
            Quickshell.execDetached(["systemctl", "suspend"]);
        } else if (action === "Reboot") {
            Quickshell.execDetached(["systemctl", "reboot"]);
        } else if (action === "Shutdown") {
            Quickshell.execDetached(["systemctl", "poweroff"]);
        }
    }
}
