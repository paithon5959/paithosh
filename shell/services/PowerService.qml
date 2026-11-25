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
    readonly property int chargeWatts: (hasBattery && typeof bat.energyRate === "number") ? Math.round(Math.abs(bat.energyRate)) : 0
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

    signal chargerChanged(bool charging, int pct, int watts)
    signal sessionActionRequested(string action)

    onChargingChanged: {
        if (!initialized) {
            lastCharging = charging;
            initialized = true;
            return;
        }
        if (charging !== lastCharging) {
            lastCharging = charging;
            chargerChanged(charging, batteryPct, chargeWatts);
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
        chargerChanged(fallbackCharging, batteryPct, chargeWatts);
    }

    function setPowerProfile(name) {
        if (typeof PowerProfiles === "undefined" || !PowerProfiles) return;
        if (name === "Power Saver") PowerProfiles.profile = PowerProfile.PowerSaver;
        else if (name === "Performance" && PowerProfiles.hasPerformanceProfile) PowerProfiles.profile = PowerProfile.Performance;
        else PowerProfiles.profile = PowerProfile.Balanced;
    }

    function executeAction(action) {
        if (action === "Lock") {
            LockService.lock();
        } else if (action === "Logout" || action === "Reboot" || action === "Shutdown") {
            sessionActionRequested(action);
        }
    }

    function runSessionCommand(action) {
        const key = String(action || "").toLowerCase();
        if (key === "logout") {
            Quickshell.execDetached(["sh", "-c", "command -v hyprctl >/dev/null && hyprctl dispatch exit || loginctl terminate-user \"$USER\""]);
        } else if (key === "reboot" || key === "restart") {
            Quickshell.execDetached(["systemctl", "reboot"]);
        } else if (key === "shutdown" || key === "poweroff") {
            Quickshell.execDetached(["systemctl", "poweroff"]);
        }
    }
}
