pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
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
    property var monitorDetails: []

    // Hyprland Visual, Layout, Animations & Blur config state (synced with ~/.config/hypr/config/)
    property string activeThemePreset: "oled"
    property bool animationsEnabled: true
    property int springStiffness: 260
    property int springDamping: 23
    property bool blurEnabled: true
    property int blurSize: 6
    property int blurPasses: 2
    property real blurVibrancy: 0.12
    property int gapsIn: 6
    property int gapsOut: 12
    property int borderSize: 1
    property int cornerRounding: 18
    property bool shadowEnabled: true
    property real inactiveOpacity: 0.96
    property string layoutName: "dwindle"
    property bool reduceMotionActive: false

    Process {
        id: hyprMonitorsProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text);
                    if (Array.isArray(parsed)) root.monitorDetails = parsed;
                } catch (e) {}
            }
        }
    }

    Timer {
        id: refreshDelayTimer
        interval: 400
        repeat: false
        onTriggered: root.refreshMonitorDetails()
    }

    function refreshMonitorDetails() {
        if (!isHyprland) return;
        hyprMonitorsProc.running = true;
    }

    function refreshOverviewData() {
        if (!isHyprland) return;
        if (Hyprland.refreshToplevels) Hyprland.refreshToplevels();
        if (Hyprland.refreshWorkspaces) Hyprland.refreshWorkspaces();
        if (Hyprland.refreshMonitors) Hyprland.refreshMonitors();
    }

    Component.onCompleted: {
        hyprVisualCfgReadProc.running = true;
        if (isHyprland) {
            refreshMonitorDetails();
            refreshOverviewData();
        }
    }

    function focusedScreen() {
        if (isHyprland && Hyprland.focusedMonitor) {
            const monName = Hyprland.focusedMonitor.name;
            for (let i = 0; i < Quickshell.screens.length; ++i) {
                if (Quickshell.screens[i].name === monName) return Quickshell.screens[i];
            }
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

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

    property var _islandDragSuppressors: ({})
    property bool _islandDragSuppressed: false

    function setIslandDragSuppressedFor(screenKey, suppressed) {
        if (!isHyprland) return;
        const key = String(screenKey || "default");
        const next = Object.assign({}, _islandDragSuppressors);
        if (suppressed) {
            next[key] = true;
        } else {
            delete next[key];
        }
        _islandDragSuppressors = next;
        const shouldSuppress = Object.keys(next).length > 0;
        if (shouldSuppress === _islandDragSuppressed) return;
        _islandDragSuppressed = shouldSuppress;
        if (shouldSuppress) {
            Quickshell.execDetached(["hyprctl", "eval", "hl.unbind(\"SUPER + mouse:272\"); hl.unbind(\"SUPER + mouse:273\")"]);
        } else {
            Quickshell.execDetached(["hyprctl", "eval", "hl.bind(\"SUPER + mouse:272\", hl.dsp.window.drag(), { mouse = true }); hl.bind(\"SUPER + mouse:273\", hl.dsp.window.resize(), { mouse = true })"]);
        }
    }

    Component.onDestruction: {
        if (_islandDragSuppressed && isHyprland) {
            _islandDragSuppressed = false;
            _islandDragSuppressors = ({});
            Quickshell.execDetached(["hyprctl", "eval", "hl.bind(\"SUPER + mouse:272\", hl.dsp.window.drag(), { mouse = true }); hl.bind(\"SUPER + mouse:273\", hl.dsp.window.resize(), { mouse = true })"]);
        }
    }

    function monitorBoundsFor(screen) {
        if (isHyprland && screen) {
            const mon = Hyprland.monitorFor(screen);
            if (mon) {
                return {
                    x: mon.x || 0,
                    y: mon.y || 0,
                    width: mon.width || screen.width || 1920,
                    height: mon.height || screen.height || 1080
                };
            }
        }
        return {
            x: 0,
            y: 0,
            width: screen ? (screen.width || 1920) : 1920,
            height: screen ? (screen.height || 1080) : 1080
        };
    }

    function isOverlappedFor(screen, barPosition) {
        if (isHyprland && screen) {
            const mon = Hyprland.monitorFor(screen);
            if (!mon || !mon.activeWorkspace) return false;
            const wsId = mon.activeWorkspace.id;
            const isBottom = barPosition === "bottom";
            if (Hyprland.toplevels && Hyprland.toplevels.values) {
                const vals = Hyprland.toplevels.values;
                const monY = mon.y || 0;
                const monH = mon.height || screen.height || 1080;
                for (let i = 0; i < vals.length; ++i) {
                    const tl = vals[i];
                    if (!tl || !tl.workspace || tl.workspace.id !== wsId) continue;
                    const ipc = tl.lastIpcObject;
                    if (ipc && ipc.at && ipc.size) {
                        const relY = ipc.at[1] - monY;
                        if (ipc.size[1] > 0) {
                            if (isBottom) {
                                if (relY + ipc.size[1] > monH - 56) return true;
                            } else {
                                if (relY < 56) return true;
                            }
                        }
                    } else {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    function formatWindowName(rawName, fallbackTitle) {
        let name = String(rawName || "").trim();
        if (name === "") return String(fallbackTitle || "");
        if (name.indexOf(".") !== -1) {
            const parts = name.split(".");
            name = parts[parts.length - 1] || name;
        }
        if (name.length > 0 && name === name.toLowerCase()) {
            name = name.charAt(0).toUpperCase() + name.slice(1);
        }
        return name;
    }

    function activeTitleFor(screen) {
        if (previewTitle !== "") return previewTitle;
        if (isHyprland) {
            const ht = Hyprland.activeToplevel;
            const mon = screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor;
            // Blank when focused window isn't on this monitor's visible workspace (e.g. empty workspace)
            if (ht && ht.title && mon && mon.activeWorkspace && ht.workspace
                && ht.workspace.id === mon.activeWorkspace.id
                && (!screen || !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === screen.name)) {
                const rawClass = (ht.lastIpcObject && ht.lastIpcObject.class)
                    || (ht.wayland && ht.wayland.appId)
                    || "";
                return formatWindowName(rawClass, ht.title);
            }
            return "";
        }
        const tl = ToplevelManager.activeToplevel;
        if (tl && (tl.appId || tl.title)) return formatWindowName(tl.appId, tl.title);
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
        const ws = Math.max(1, Math.min(10, id));
        previewWs = ws;
        if (isHyprland) {
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + ws + " })");
        }
    }

    function focusWindow(address) {
        if (!isHyprland || !address || address === "") return;
        const safeAddr = String(address).replace(/[^0-9a-fA-Fx]/g, "");
        if (safeAddr === "") return;
        const normAddr = safeAddr.indexOf("0x") === 0 ? safeAddr : ("0x" + safeAddr);
        Hyprland.dispatch("hl.dsp.focus({ window = 'address:" + normAddr + "' })");
    }

    function focusWindowByApp(appName, desktopEntry, summary) {
        if (!isHyprland || !Hyprland.toplevels || !Hyprland.toplevels.values) return false;
        const appLower = String(appName || "").trim().toLowerCase();
        const deskLower = String(desktopEntry || "").trim().toLowerCase();
        const sumLower = String(summary || "").trim().toLowerCase();
        if (appLower === "" && deskLower === "") return false;

        const tls = Hyprland.toplevels.values;
        let bestAddr = "";
        let bestScore = 0;

        for (let i = 0; i < tls.length; ++i) {
            const tl = tls[i];
            if (!tl) continue;
            const ipc = tl.lastIpcObject || {};
            const addr = tl.address ? String(tl.address) : (ipc.address ? String(ipc.address) : "");
            if (addr === "") continue;

            const rawClass = String(ipc.class || (tl.wayland && tl.wayland.appId) || "").toLowerCase();
            const fmtName = formatWindowName(rawClass, tl.title || "").toLowerCase();
            const title = String(tl.title || "").toLowerCase();

            let score = 0;
            if (deskLower !== "" && (rawClass === deskLower || fmtName === deskLower)) {
                score = 100;
            } else if (appLower !== "" && (rawClass === appLower || fmtName === appLower)) {
                score = 90;
            } else if (deskLower !== "" && (rawClass.indexOf(deskLower) !== -1 || deskLower.indexOf(rawClass) !== -1)) {
                score = 70;
            } else if (appLower !== "" && rawClass !== "" && (rawClass.indexOf(appLower) !== -1 || appLower.indexOf(rawClass) !== -1)) {
                score = 60;
            } else if (appLower !== "" && title.indexOf(appLower) !== -1) {
                score = 40;
            } else if (sumLower !== "" && title.indexOf(sumLower) !== -1) {
                score = 20;
            }

            if (score > bestScore) {
                bestScore = score;
                bestAddr = addr;
            }
        }

        if (bestAddr !== "") {
            focusWindow(bestAddr);
            return true;
        }
        return false;
    }

    function closeWindow(address) {
        if (!isHyprland || !address || address === "") return;
        const safeAddr = String(address).replace(/[^0-9a-fA-Fx]/g, "");
        if (safeAddr === "") return;
        const normAddr = safeAddr.indexOf("0x") === 0 ? safeAddr : ("0x" + safeAddr);
        Hyprland.dispatch("hl.dsp.window.close({ window = 'address:" + normAddr + "' })");
    }

    function workspaceOverviewModel() {
        const count = 10;
        const slots = [];
        for (let i = 1; i <= count; ++i) {
            slots.push({
                id: i,
                name: String(i),
                isFocused: false,
                hasFullscreen: false,
                monitorName: "",
                windows: []
            });
        }

        if (!isHyprland) {
            // Deterministic preview fallback when running outside Hyprland
            slots[0].isFocused = (previewWs === 1);
            slots[0].windows = [
                { address: "0x1", title: "kitty — ~/Projects/paithosh", appClass: "kitty", focused: true, floating: false, relX: 0.02, relY: 0.04, relW: 0.47, relH: 0.92 },
                { address: "0x2", title: "Chromium", appClass: "chromium", focused: false, floating: false, relX: 0.51, relY: 0.04, relW: 0.47, relH: 0.92 }
            ];
            slots[1].isFocused = (previewWs === 2);
            slots[1].windows = [
                { address: "0x3", title: "Code — shell.qml", appClass: "code", focused: false, floating: false, relX: 0.02, relY: 0.04, relW: 0.96, relH: 0.92 }
            ];
            slots[2].isFocused = (previewWs === 3);
            slots[2].windows = [
                { address: "0x4", title: "Spotify", appClass: "spotify", focused: false, floating: false, relX: 0.02, relY: 0.04, relW: 0.96, relH: 0.56 },
                { address: "0x5", title: "btop", appClass: "kitty", focused: false, floating: false, relX: 0.02, relY: 0.62, relW: 0.96, relH: 0.34 }
            ];
            return slots;
        }

        const monByName = {};
        if (Hyprland.monitors && Hyprland.monitors.values) {
            const mons = Hyprland.monitors.values;
            for (let i = 0; i < mons.length; ++i) {
                const m = mons[i];
                if (!m) continue;
                const sc = (m.scale && m.scale > 0) ? m.scale : 1.0;
                monByName[m.name] = {
                    x: m.x || 0,
                    y: m.y || 0,
                    w: Math.max(1, (m.width || 1920) / sc),
                    h: Math.max(1, (m.height || 1080) / sc)
                };
            }
        }

        const focusedWsId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
        const activeAddr = (Hyprland.activeToplevel && Hyprland.activeToplevel.address)
            ? String(Hyprland.activeToplevel.address)
            : "";

        if (Hyprland.workspaces && Hyprland.workspaces.values) {
            const wss = Hyprland.workspaces.values;
            for (let i = 0; i < wss.length; ++i) {
                const ws = wss[i];
                if (!ws || ws.id < 1 || ws.id > count) continue;
                const slot = slots[ws.id - 1];
                slot.name = ws.name ? String(ws.name) : String(ws.id);
                slot.isFocused = (ws.id === focusedWsId) || Boolean(ws.focused);
                slot.hasFullscreen = Boolean(ws.hasFullscreen);
                slot.monitorName = ws.monitor ? String(ws.monitor.name || "") : "";
            }
        }
        if (focusedWsId >= 1 && focusedWsId <= count) {
            slots[focusedWsId - 1].isFocused = true;
        }

        if (Hyprland.toplevels && Hyprland.toplevels.values) {
            const tls = Hyprland.toplevels.values;
            for (let i = 0; i < tls.length; ++i) {
                const tl = tls[i];
                if (!tl || !tl.workspace) continue;
                const wsId = tl.workspace.id;
                if (wsId < 1 || wsId > count) continue;

                const ipc = tl.lastIpcObject || {};
                const rawClass = ipc.class || (tl.wayland && tl.wayland.appId) || "";
                const appName = formatWindowName(rawClass, tl.title || "Window");
                const addr = tl.address ? String(tl.address) : (ipc.address ? String(ipc.address) : "");
                const monName = (tl.monitor && tl.monitor.name) ? tl.monitor.name : slots[wsId - 1].monitorName;
                const monRect = monByName[monName] || { x: 0, y: 0, w: 1920, h: 1080 };

                let relX = 0.02;
                let relY = 0.04;
                let relW = 0.96;
                let relH = 0.92;
                let hasGeom = false;
                if (ipc.at && ipc.size && ipc.size[0] > 0 && ipc.size[1] > 0) {
                    relX = Math.max(0.01, Math.min(0.92, (ipc.at[0] - monRect.x) / monRect.w));
                    relY = Math.max(0.02, Math.min(0.88, (ipc.at[1] - monRect.y) / monRect.h));
                    relW = Math.max(0.14, Math.min(1.0 - relX - 0.01, ipc.size[0] / monRect.w));
                    relH = Math.max(0.18, Math.min(1.0 - relY - 0.02, ipc.size[1] / monRect.h));
                    hasGeom = true;
                }

                slots[wsId - 1].windows.push({
                    address: addr,
                    title: tl.title ? String(tl.title) : appName,
                    appClass: appName,
                    focused: (activeAddr !== "" && addr === activeAddr) || Boolean(tl.activated),
                    floating: Boolean(ipc.floating),
                    wayland: tl.wayland || null,
                    hasGeom: hasGeom,
                    relX: relX,
                    relY: relY,
                    relW: relW,
                    relH: relH
                });
            }
        }

        // Auto-tile any windows missing IPC geometry so they never stack on top of each other
        for (let i = 0; i < slots.length; ++i) {
            const wins = slots[i].windows;
            const noGeom = [];
            for (let j = 0; j < wins.length; ++j) {
                if (!wins[j].hasGeom) noGeom.push(wins[j]);
            }
            if (noGeom.length > 1) {
                const gap = 0.02;
                const cellW = (1.0 - gap * (noGeom.length + 1)) / noGeom.length;
                for (let k = 0; k < noGeom.length; ++k) {
                    noGeom[k].relX = gap + k * (cellW + gap);
                    noGeom[k].relW = Math.max(0.14, cellW);
                }
            }
        }

        return slots;
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

    function applyDisplaySettings(output, mode, scale, transform) {
        if (!isHyprland || !output) return;
        let pos = "auto";
        for (let i = 0; i < monitorDetails.length; ++i) {
            if (monitorDetails[i].name === output) {
                const m = monitorDetails[i];
                if (typeof m.x === "number" && typeof m.y === "number") {
                    pos = m.x + "x" + m.y;
                }
                break;
            }
        }
        const monitorRule = output + "," + mode + "," + pos + "," + scale + ",transform," + transform;
        Quickshell.execDetached(["hyprctl", "keyword", "monitor", monitorRule]);

        const pyScript = `
import os, re, sys
out, mode, pos, scale, tr = sys.argv[1:6]
cfg_path = os.path.expanduser("~/.config/hypr/config/monitors.lua")
if not os.path.exists(cfg_path):
    sys.exit(0)
with open(cfg_path, "r", encoding="utf-8") as f:
    text = f.read()

pattern = re.compile(r'(hl\\.monitor\\(\\{[^}]*?output\\s*=\\s*"' + re.escape(out) + r'"[^}]*?\\}\\))', re.DOTALL)
new_block = (
    'hl.monitor({\\n'
    f'    output    = "{out}",\\n'
    f'    mode      = "{mode}",\\n'
    f'    position  = "{pos}",\\n'
    f'    scale     = {scale},\\n'
    f'    transform = {tr},\\n'
    '})'
)
if pattern.search(text):
    text = pattern.sub(new_block, text, count=1)
else:
    text = text.rstrip() + "\\n\\n" + new_block + "\\n"
with open(cfg_path, "w", encoding="utf-8") as f:
    f.write(text)
`;
        Quickshell.execDetached(["python3", "-c", pyScript, output, mode, pos, String(scale), String(transform)]);
        refreshDelayTimer.restart();
    }

    function setPreviewState(title, ws, fullscreen) {
        previewTitle = title;
        if (ws > 0) previewWs = ws;
        previewFullscreen = fullscreen;
    }

    Process {
        id: hyprVisualCfgReadProc
        command: ["python3", "-c", `
import os, re, json
res = {}
anim_path = os.path.expanduser("~/.config/hypr/config/animations.lua")
if os.path.exists(anim_path):
    txt = open(anim_path, encoding="utf-8").read()
    m = re.search(r"animations\\s*=\\s*\\{[^}]*?enabled\\s*=\\s*(true|false)", txt, re.DOTALL)
    if m: res["animationsEnabled"] = (m.group(1) == "true")
    ms = re.search(r'hl\\.curve\\("paithoshSpring"[^)]*?stiffness\\s*=\\s*(\\d+)[^)]*?damping\\s*=\\s*(\\d+)', txt, re.DOTALL)
    if ms:
        res["springStiffness"] = int(ms.group(1))
        res["springDamping"] = int(ms.group(2))
app_path = os.path.expanduser("~/.config/hypr/config/appearance.lua")
if os.path.exists(app_path):
    txt = open(app_path, encoding="utf-8").read()
    for key, pat, cast in [
        ("gapsIn", r"gaps_in\s*=\s*(\d+)", int),
        ("gapsOut", r"gaps_out\s*=\s*(\d+)", int),
        ("borderSize", r"border_size\s*=\s*(\d+)", int),
        ("cornerRounding", r"rounding\s*=\s*(\d+)", int),
        ("inactiveOpacity", r"inactive_opacity\s*=\s*([0-9.]+)", float),
    ]:
        m = re.search(pat, txt)
        if m: res[key] = cast(m.group(1))
    ml = re.search(r'layout\s*=\s*"([^"]+)"', txt)
    if ml: res["layoutName"] = ml.group(1)
    msh = re.search(r"shadow\s*=\s*\{[^}]*?enabled\s*=\s*(true|false)", txt, re.DOTALL)
    if msh: res["shadowEnabled"] = (msh.group(1) == "true")
    mb = re.search(r"blur\s*=\s*\{([^}]*)\}", txt, re.DOTALL)
    if mb:
        blk = mb.group(1)
        me = re.search(r"enabled\s*=\s*(true|false)", blk)
        msz = re.search(r"size\s*=\s*(\d+)", blk)
        mp = re.search(r"passes\s*=\s*(\d+)", blk)
        mv = re.search(r"vibrancy\s*=\s*([0-9.]+)", blk)
        if me: res["blurEnabled"] = (me.group(1) == "true")
        if msz: res["blurSize"] = int(msz.group(1))
        if mp: res["blurPasses"] = int(mp.group(1))
        if mv: res["blurVibrancy"] = float(mv.group(1))
print(json.dumps(res))
`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const cfg = JSON.parse(this.text);
                    if (typeof cfg.animationsEnabled === "boolean") root.animationsEnabled = cfg.animationsEnabled;
                    if (typeof cfg.springStiffness === "number") root.springStiffness = cfg.springStiffness;
                    if (typeof cfg.springDamping === "number") root.springDamping = cfg.springDamping;
                    if (typeof cfg.blurEnabled === "boolean") root.blurEnabled = cfg.blurEnabled;
                    if (typeof cfg.blurSize === "number") root.blurSize = cfg.blurSize;
                    if (typeof cfg.blurPasses === "number") root.blurPasses = cfg.blurPasses;
                    if (typeof cfg.blurVibrancy === "number") root.blurVibrancy = cfg.blurVibrancy;
                    if (typeof cfg.gapsIn === "number") root.gapsIn = cfg.gapsIn;
                    if (typeof cfg.gapsOut === "number") root.gapsOut = cfg.gapsOut;
                    if (typeof cfg.borderSize === "number") root.borderSize = cfg.borderSize;
                    if (typeof cfg.cornerRounding === "number") root.cornerRounding = cfg.cornerRounding;
                    if (typeof cfg.shadowEnabled === "boolean") root.shadowEnabled = cfg.shadowEnabled;
                    if (typeof cfg.inactiveOpacity === "number") root.inactiveOpacity = cfg.inactiveOpacity;
                    if (typeof cfg.layoutName === "string") root.layoutName = cfg.layoutName;
                } catch (e) {}
            }
        }
    }

    property bool _dirtyAppearance: false
    property bool _dirtyAnimations: false
    property bool _dirtyColors: false
    property bool _pendingReload: false
    property bool _flushAgain: false
    property bool _writerNeedsReload: false
    property var _pendingThemeColors: null

    Timer {
        id: hyprColorEvalTimer
        interval: 50
        repeat: false
        onTriggered: {
            const c = root._pendingThemeColors;
            if (!c) return;
            root._hyprEval(
                'hl.config({ general = { col = { active_border = { colors = { "' + c.border_active_a + '", "' + c.border_active_b + '" }, angle = ' + c.activeBorderAngle + ' }, inactive_border = "' + c.border_inactive + '" } }, misc = { background_color = "' + c.pill_bg + '" } })'
            );
        }
    }

    Timer {
        id: hyprConfigFlushTimer
        interval: 180
        repeat: false
        onTriggered: root._flushHyprConfig()
    }

    readonly property string _hyprWriterPy: `
import fcntl, json, os, re, sys

cfg = json.loads(sys.argv[1])
lock_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
lock_path = os.path.join(lock_dir, f"paithosh-hypr-cfg-{os.getuid()}.lock")
with open(lock_path, "w") as lf:
    fcntl.flock(lf, fcntl.LOCK_EX)

    staged = []

    def stage_update(path, updater):
        if not os.path.exists(path):
            return
        with open(path, "r", encoding="utf-8") as f:
            txt = f.read()
        if not txt.strip():
            return
        new_txt = updater(txt)
        if not new_txt or not new_txt.strip() or new_txt == txt:
            return
        tmp = f"{path}.tmp.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(new_txt)
            f.flush()
            os.fsync(f.fileno())
        staged.append((tmp, path))

    if cfg.get("animations"):
        def update_animations(txt):
            an_en = "true" if cfg["animationsEnabled"] else "false"
            txt = re.sub(r"(animations\\s*=\\s*\\{[^}]*?enabled\\s*=\\s*)(true|false)", r"\\g<1>" + an_en, txt, count=1, flags=re.DOTALL)
            new_line = f'hl.curve("paithoshSpring", {{ type = "spring", mass = 1, stiffness = {cfg["springStiffness"]}, damping = {cfg["springDamping"]} }})'
            txt = re.sub(r'hl\\.curve\\("paithoshSpring",\\s*\\{[^}]*\\}\\)', new_line, txt, count=1)
            return txt

        stage_update(os.path.expanduser("~/.config/hypr/config/animations.lua"), update_animations)

    if cfg.get("colors") and cfg.get("themeColors"):
        tc = cfg["themeColors"]
        def update_colors(txt):
            for key in ("pill_bg", "surface_bg", "surface_raised", "text", "text_sub", "text_muted", "border_active_a", "border_active_b", "border_inactive"):
                val = tc.get(key)
                if val:
                    txt = re.sub(
                        rf'(\\b{key}\\s*=\\s*)"[^"]*"',
                        lambda m, v=val: m.group(1) + f'"{v}"',
                        txt,
                        count=1,
                    )
            return txt

        stage_update(os.path.expanduser("~/.config/hypr/theme/colors.lua"), update_colors)

    if cfg.get("appearance"):
        def update_appearance(txt):
            txt = re.sub(r"(gaps_in\\s*=\\s*)\\d+", r"\\g<1>" + str(cfg["gapsIn"]), txt, count=1)
            txt = re.sub(r"(gaps_out\\s*=\\s*)\\d+", r"\\g<1>" + str(cfg["gapsOut"]), txt, count=1)
            txt = re.sub(r"(border_size\\s*=\\s*)\\d+", r"\\g<1>" + str(cfg["borderSize"]), txt, count=1)
            txt = re.sub(r'(layout\\s*=\\s*)"[^"]+"', r'\\g<1>"' + str(cfg["layoutName"]) + '"', txt, count=1)
            txt = re.sub(r"(rounding\\s*=\\s*)\\d+", r"\\g<1>" + str(cfg["cornerRounding"]), txt, count=1)
            txt = re.sub(r"(inactive_opacity\\s*=\\s*)[0-9.]+", r"\\g<1>" + f'{cfg["inactiveOpacity"]:.2f}', txt, count=1)
            sh_en = "true" if cfg["shadowEnabled"] else "false"
            txt = re.sub(r"(shadow\\s*=\\s*\\{[^}]*?enabled\\s*=\\s*)(true|false)", r"\\g<1>" + sh_en, txt, count=1, flags=re.DOTALL)
            bl_en = "true" if cfg["blurEnabled"] else "false"
            new_blk = (
                "blur = {\\n"
                f"            enabled  = {bl_en},\\n"
                f"            size     = {cfg['blurSize']},\\n"
                f"            passes   = {cfg['blurPasses']},\\n"
                f"            vibrancy = {cfg['blurVibrancy']:.2f},\\n"
                "        }"
            )
            txt = re.sub(r"blur\\s*=\\s*\\{[^}]*\\}", new_blk, txt, count=1, flags=re.DOTALL)
            tc = cfg.get("themeColors")
            if tc and "activeBorderAngle" in tc:
                txt = re.sub(r"(active_border\\s*=\\s*\\{(?:[^{}]|\\{[^{}]*\\})*?\\bangle\\s*=\\s*)\\d+", r"\\g<1>" + str(int(tc["activeBorderAngle"])), txt, count=1)
            return txt

        stage_update(os.path.expanduser("~/.config/hypr/config/appearance.lua"), update_appearance)

    # Commit all staged files back-to-back after fsync so Hyprland autoreload
    # never observes a half-updated config pair.
    for tmp, path in staged:
        os.replace(tmp, path)
`

    Process {
        id: hyprConfigWriter
        onExited: (code) => {
            if (code === 0 && root._writerNeedsReload && root.isHyprland) {
                Quickshell.execDetached(["hyprctl", "reload"]);
                if (root.reduceMotionActive) reduceMotionReapplyTimer.restart();
            }
            root._writerNeedsReload = false;
            if (root._flushAgain) {
                root._flushAgain = false;
                hyprConfigFlushTimer.restart();
            }
        }
    }

    Timer {
        id: reduceMotionReapplyTimer
        interval: 120
        repeat: false
        onTriggered: if (root.reduceMotionActive) root._applyReduceMotionLive()
    }

    function _scheduleHyprWrite(appearanceDirty, animationsDirty, needsReload) {
        if (appearanceDirty) _dirtyAppearance = true;
        if (animationsDirty) _dirtyAnimations = true;
        if (needsReload) _pendingReload = true;
        hyprConfigFlushTimer.restart();
    }

    function _flushHyprConfig() {
        if (!_dirtyAppearance && !_dirtyAnimations && !_dirtyColors) return;
        if (hyprConfigWriter.running) {
            _flushAgain = true;
            return;
        }
        const payloadJson = JSON.stringify({
            appearance: _dirtyAppearance,
            animations: _dirtyAnimations,
            colors: _dirtyColors,
            themeColors: _pendingThemeColors,
            gapsIn: gapsIn,
            gapsOut: gapsOut,
            borderSize: borderSize,
            layoutName: layoutName,
            cornerRounding: cornerRounding,
            shadowEnabled: shadowEnabled,
            inactiveOpacity: inactiveOpacity,
            blurEnabled: blurEnabled,
            blurSize: blurSize,
            blurPasses: blurPasses,
            blurVibrancy: blurVibrancy,
            animationsEnabled: animationsEnabled,
            springStiffness: springStiffness,
            springDamping: springDamping
        });
        _writerNeedsReload = _pendingReload;
        _dirtyAppearance = false;
        _dirtyAnimations = false;
        _dirtyColors = false;
        _pendingReload = false;
        hyprConfigWriter.command = ["python3", "-c", root._hyprWriterPy, payloadJson];
        hyprConfigWriter.running = true;
    }

    function _stripHex(hex) {
        const m = String(hex || "").trim().match(/^#?([0-9a-fA-F]{6})$/);
        return m ? m[1].toLowerCase() : "000000";
    }

    function _byteHex(val) {
        const clamped = Math.max(0, Math.min(255, Math.round(val)));
        const s = clamped.toString(16);
        return s.length < 2 ? "0" + s : s;
    }

    function syncThemeColors(cfg) {
        if (!cfg) return;
        const pill = _stripHex(cfg.pillBg);
        const surf = _stripHex(cfg.surfaceBg);
        const raised = _stripHex(cfg.surfaceRaised);
        const txt = _stripHex(cfg.text);
        const acc = _stripHex(cfg.accent);
        const acc2 = _stripHex(cfg.accent2);
        const bdr = _stripHex(cfg.borderColor || cfg.text);
        const bAlpha = Math.max(0.08, Math.min(0.60, Number(cfg.borderAlpha) || 0.14));
        const bAlphaHex = _byteHex(bAlpha * 255);
        const activeHi = cfg.activeBorderHighlight !== false;
        const gradAcc = Boolean(cfg.accentGradientEnabled);
        const angle = Math.max(0, Math.min(360, Math.round(Number(cfg.gradientAngle) || 45)));

        _pendingThemeColors = {
            pill_bg: "rgb(" + pill + ")",
            surface_bg: "rgb(" + surf + ")",
            surface_raised: "rgb(" + raised + ")",
            text: "rgb(" + txt + ")",
            text_sub: "rgba(" + txt + "99)",
            text_muted: "rgba(" + txt + "73)",
            border_inactive: "rgba(" + bdr + bAlphaHex + ")",
            border_active_a: activeHi ? ("rgba(" + acc + "ee)") : ("rgba(" + bdr + "44)"),
            border_active_b: activeHi ? (gradAcc ? ("rgba(" + acc2 + "cc)") : ("rgba(" + acc + "55)")) : ("rgba(" + bdr + "24)"),
            activeBorderAngle: angle
        };
        hyprColorEvalTimer.restart();
        _dirtyColors = true;
        _scheduleHyprWrite(true, false, false);
    }

    property var _evalQueue: []
    function _hyprEval(luaCode) {
        if (!isHyprland) return;
        _evalQueue.push(luaCode);
        Qt.callLater(_flushHyprEval);
    }

    function _flushHyprEval() {
        if (_evalQueue.length === 0) return;
        const batch = _evalQueue.join("; ");
        _evalQueue = [];
        Quickshell.execDetached(["hyprctl", "eval", batch]);
    }

    function _applyReduceMotionLive() {
        if (!isHyprland) return;
        _hyprEval(
            'hl.config({ ' +
                'decoration = { rounding = 10, inactive_opacity = 1.0, shadow = { enabled = false }, blur = { enabled = false } }, ' +
                'animations = { enabled = true } ' +
            '}); ' +
            'hl.animation({ leaf = "border", enabled = false }); ' +
            'hl.animation({ leaf = "shadowangle", enabled = false }); ' +
            'hl.animation({ leaf = "windows", enabled = true, speed = 2.0, bezier = "easeOutQuint", style = "slide" }); ' +
            'hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.0, bezier = "easeOutQuint", style = "slide" }); ' +
            'hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.6, bezier = "quick", style = "slide" }); ' +
            'hl.animation({ leaf = "workspaces", enabled = true, speed = 2.0, bezier = "easeOutQuint", style = "slide" }); ' +
            'hl.animation({ leaf = "workspacesIn", enabled = true, speed = 2.0, bezier = "easeOutQuint", style = "slide" }); ' +
            'hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.8, bezier = "easeOutQuint", style = "slide" }); ' +
            'hl.animation({ leaf = "layers", enabled = true, speed = 2.0, bezier = "quick", style = "fade" }); ' +
            'hl.animation({ leaf = "layersIn", enabled = true, speed = 2.0, bezier = "quick", style = "fade" }); ' +
            'hl.animation({ leaf = "layersOut", enabled = true, speed = 1.6, bezier = "quick", style = "fade" }); ' +
            'hl.animation({ leaf = "fade", enabled = true, speed = 2.0, bezier = "quick" }); ' +
            'hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.8, bezier = "quick" }); ' +
            'hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.5, bezier = "quick" })'
        );
    }

    function applyReduceMotion(enabled) {
        const next = Boolean(enabled);
        const prev = reduceMotionActive;
        reduceMotionActive = next;
        if (!isHyprland) return;
        if (next) {
            _applyReduceMotionLive();
        } else if (prev) {
            reduceMotionReapplyTimer.stop();
            Quickshell.execDetached(["hyprctl", "reload", "config-only"]);
        }
    }

    function setAnimationsEnabled(enabled) {
        animationsEnabled = Boolean(enabled);
        if (!reduceMotionActive) {
            _hyprEval("hl.config({ animations = { enabled = " + (animationsEnabled ? "true" : "false") + " } })");
        }
        _scheduleHyprWrite(false, true, false);
    }

    function setSpringCurve(stiffness, damping) {
        springStiffness = Math.max(80, Math.min(600, Math.round(stiffness)));
        springDamping = Math.max(5, Math.min(60, Math.round(damping)));
        if (!reduceMotionActive) {
            _hyprEval('hl.curve("paithoshSpring", { type = "spring", mass = 1, stiffness = ' + springStiffness + ', damping = ' + springDamping + ' })');
        }
        _scheduleHyprWrite(false, true, false);
    }

    function setBlurConfig(enabled, size, passes, vibrancy) {
        blurEnabled = Boolean(enabled);
        blurSize = Math.max(1, Math.min(24, Math.round(size)));
        blurPasses = Math.max(1, Math.min(6, Math.round(passes)));
        blurVibrancy = Math.max(0.0, Math.min(1.0, Math.round(vibrancy * 100) / 100));

        if (!reduceMotionActive) {
            _hyprEval("hl.config({ decoration = { blur = { enabled = " + (blurEnabled ? "true" : "false") + ", size = " + blurSize + ", passes = " + blurPasses + ", vibrancy = " + blurVibrancy.toFixed(2) + " } } })");
        }
        _scheduleHyprWrite(true, false, false);
    }

    function setGapsAndBorder(gIn, gOut, bSize) {
        gapsIn = Math.max(0, Math.min(32, Math.round(gIn)));
        gapsOut = Math.max(0, Math.min(48, Math.round(gOut)));
        borderSize = Math.max(0, Math.min(6, Math.round(bSize)));
        _hyprEval("hl.config({ general = { gaps_in = " + gapsIn + ", gaps_out = " + gapsOut + ", border_size = " + borderSize + " } })");
        _scheduleHyprWrite(true, false, false);
    }

    function setDecoration(rounding, shadows, inactOp) {
        cornerRounding = Math.max(0, Math.min(32, Math.round(rounding)));
        shadowEnabled = Boolean(shadows);
        inactiveOpacity = Math.max(0.5, Math.min(1.0, Math.round(inactOp * 100) / 100));
        if (!reduceMotionActive) {
            _hyprEval("hl.config({ decoration = { rounding = " + cornerRounding + ", inactive_opacity = " + inactiveOpacity.toFixed(2) + ", shadow = { enabled = " + (shadowEnabled ? "true" : "false") + " } } })");
        }
        _scheduleHyprWrite(true, false, false);
    }

    function setLayout(name) {
        layoutName = (name === "master") ? "master" : "dwindle";
        _hyprEval('hl.config({ general = { layout = "' + layoutName + '" } })');
        _scheduleHyprWrite(true, false, false);
    }

    function setActiveThemePresetName(key) {
        activeThemePreset = key;
    }

    function applyThemePreset(key) {
        activeThemePreset = key;
        if (key === "oled") {
            setGapsAndBorder(6, 12, 1);
            setDecoration(18, true, 0.96);
            setBlurConfig(true, 6, 2, 0.12);
            setAnimationsEnabled(true);
            setSpringCurve(260, 23);
        } else if (key === "mica") {
            setGapsAndBorder(8, 16, 1);
            setDecoration(14, true, 0.92);
            setBlurConfig(true, 12, 3, 0.22);
            setAnimationsEnabled(true);
            setSpringCurve(240, 24);
        } else if (key === "minimal") {
            setGapsAndBorder(4, 8, 1);
            setDecoration(6, false, 1.0);
            setBlurConfig(false, 4, 1, 0.0);
            setAnimationsEnabled(true);
            setSpringCurve(420, 30);
        } else if (key === "ocean") {
            setGapsAndBorder(6, 12, 2);
            setDecoration(16, true, 0.94);
            setBlurConfig(true, 9, 2, 0.18);
            setAnimationsEnabled(true);
            setSpringCurve(280, 22);
        } else if (key === "adaptive") {
            setGapsAndBorder(6, 12, 1);
            setDecoration(16, true, 0.95);
            setBlurConfig(true, 8, 2, 0.16);
            setAnimationsEnabled(true);
            setSpringCurve(270, 23);
        }
    }
}
