pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Singleton {
    id: root

    readonly property bool isHyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") !== ""

    // Preview/fallback properties used when running on KDE Wayland before Hyprland switch
    property int previewWs: 1
    property string previewTitle: ""
    property bool previewFullscreen: false
    property string previewMonitorMode: "extend-right"

    function workspaceIdFor(screen) {
        if (isHyprland && screen) {
            const mon = Hyprland.monitorFor(screen);
            if (mon && mon.activeWorkspace) return mon.activeWorkspace.id;
        }
        return previewWs;
    }

    function isFullscreenFor(screen) {
        if (previewFullscreen) return true;
        if (isHyprland && screen) {
            const mon = Hyprland.monitorFor(screen);
            if (mon && mon.activeWorkspace && mon.activeWorkspace.hasFullscreen) return true;
        }
        const tl = ToplevelManager.activeToplevel;
        if (tl && tl.fullscreen) {
            if (!screen || !tl.screens) return true;
            for (let i = 0; i < tl.screens.length; ++i) {
                if (tl.screens[i] === screen) return true;
            }
        }
        return false;
    }

    function activeTitleFor(screen) {
        if (previewTitle !== "") return previewTitle;
        if (isHyprland) {
            const ht = Hyprland.activeToplevel;
            if (ht && ht.title) {
                if (!screen || !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === screen.name) {
                    return ht.title;
                }
            }
        }
        const tl = ToplevelManager.activeToplevel;
        if (tl && tl.title) return tl.title;
        return "";
    }

    function monitorsList() {
        if (isHyprland && Hyprland.monitors && Hyprland.monitors.values && Hyprland.monitors.values.length > 0) {
            const out = [];
            const vals = Hyprland.monitors.values;
            for (let i = 0; i < vals.length; ++i) {
                const m = vals[i];
                out.push({
                    name: m.name || ("Monitor " + (i + 1)),
                    width: m.width || 1920,
                    height: m.height || 1080,
                    refreshRate: Math.round(m.refreshRate || 60),
                    primary: i === 0
                });
            }
            return out;
        }
        return [
            { name: "eDP-1", width: 2560, height: 1600, refreshRate: 165, primary: true },
            { name: "HDMI-A-1", width: 1920, height: 1080, refreshRate: 144, primary: false }
        ];
    }

    function switchWorkspace(id) {
        const ws = Math.max(1, Math.min(9, id));
        previewWs = ws;
        if (isHyprland) {
            Hyprland.dispatch("workspace " + ws);
        }
    }

    function applyMonitorLayout(mode) {
        previewMonitorMode = mode;
        if (!isHyprland) return;
        const mons = monitorsList();
        if (mons.length < 2) return;
        const primary = mons[0].name;
        const ext = mons[1].name;
        if (mode === "extend-right") {
            Quickshell.execDetached(["hyprctl", "keyword", "monitor", primary + ",preferred,0x0,1"]);
            Quickshell.execDetached(["hyprctl", "keyword", "monitor", ext + ",preferred,auto-right,1"]);
        } else if (mode === "extend-left") {
            Quickshell.execDetached(["hyprctl", "keyword", "monitor", ext + ",preferred,0x0,1"]);
            Quickshell.execDetached(["hyprctl", "keyword", "monitor", primary + ",preferred,auto-right,1"]);
        } else if (mode === "mirror") {
            Quickshell.execDetached(["hyprctl", "keyword", "monitor", ext + ",preferred,auto,1,mirror," + primary]);
        } else if (mode === "ext-only") {
            Quickshell.execDetached(["hyprctl", "keyword", "monitor", primary + ",disable"]);
            Quickshell.execDetached(["hyprctl", "keyword", "monitor", ext + ",preferred,0x0,1"]);
        }
    }

    function setPreviewState(title, ws, fullscreen) {
        previewTitle = title;
        if (ws > 0) previewWs = ws;
        previewFullscreen = fullscreen;
    }
}
