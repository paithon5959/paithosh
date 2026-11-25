pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var binds: []
    property int totalComboCount: 0
    property var categoryCounts: ({ all: 0, island: 0, screenshot: 0, apps: 0, window: 0, command: 0 })
    property string mainMod: "SUPER"
    property string statusText: ""
    property bool statusOk: true
    property bool busy: false

    property var _undoSnapshot: null
    readonly property bool canUndo: _undoSnapshot !== null

    property string _queuedPayload: ""
    property string _queuedStatus: ""
    property bool _hasQueuedWrite: false
    property bool _queuedReset: false

    readonly property var categoryOrder: ["island", "screenshot", "apps", "window", "command"]
    readonly property var categoryMeta: ({
        island:     { label: "Dynamic Island",     shortLabel: "Island",  iconName: "bolt",     desc: "Paithosh shell, launcher, search & OSD" },
        screenshot: { label: "Capture & Record",   shortLabel: "Capture", iconName: "image",    desc: "Screenshots & screen recording" },
        apps:       { label: "Applications",       shortLabel: "Apps",    iconName: "grid",     desc: "Launch apps & default programs" },
        window:     { label: "Window & Workspace", shortLabel: "Window",  iconName: "list",     desc: "Focus, tiling, close & workspaces" },
        command:    { label: "Commands & Media",   shortLabel: "Custom",  iconName: "terminal", desc: "Custom shell commands & media keys" }
    })

    readonly property string shellDir: Quickshell.shellDir
    readonly property string projectRoot: Quickshell.shellDir.replace(/\/shell\/?$/, "")

    readonly property var islandActions: [
        { id: "toggleLauncher",    label: "Toggle Launcher",            desc: "Open or close Paithosh app launcher",     lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleLauncher")',          opts: "" },
        { id: "toggleSearch",      label: "Toggle Search",              desc: "Open universal search in Dynamic Island", lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleSearch")',            opts: "" },
        { id: "toggleOverview",    label: "Workspace Overview",         desc: "Show all workspaces & window overview",   lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleOverview")',          opts: "" },
        { id: "toggleClipboard",   label: "Clipboard History",          desc: "Open clipboard history manager",          lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleClipboard")',         opts: "" },
        { id: "openFiles",         label: "Open Files Drawer",          desc: "Open quick file browser in Island",       lua: 'hl.dsp.exec_cmd(qsIpc .. "openFiles")',               opts: "" },
        { id: "openSettings",      label: "Open Settings",              desc: "Open Paithosh Settings panel",            lua: 'hl.dsp.exec_cmd(qsIpc .. "openSettings home")',       opts: "" },
        { id: "dashMission",       label: "Dashboard: Mission Control", desc: "Open Mission Control tab in Island",      lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleDashboard mission")', opts: "" },
        { id: "dashTasks",         label: "Dashboard: Task Manager",    desc: "Open Task Manager tab in Island",         lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleDashboard tasks")',   opts: "" },
        { id: "dashKde",           label: "Dashboard: KDE Connect",     desc: "Open KDE Connect tab in Island",          lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleDashboard kde")',     opts: "" },
        { id: "dashPower",         label: "Dashboard: Power Station",   desc: "Open Power Station tab in Island",        lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleDashboard power")',   opts: "" },
        { id: "lockScreen",        label: "Lock Screen",                desc: "Lock session with Paithosh Statusbar Lock", lua: 'hl.dsp.exec_cmd(qsIpc .. "lock")',                    opts: "" },
        { id: "toggleHideBar",     label: "Toggle Hide Bar",            desc: "Show or hide the Dynamic Island bar",     lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleHideBar")',           opts: "" },
        { id: "toggleBarPosition", label: "Swap Bar Position",          desc: "Toggle Dynamic Island top / bottom",      lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleBarPosition")',       opts: "" },
        { id: "nextWallpaper",     label: "Next Wallpaper",             desc: "Cycle to the next desktop wallpaper",     lua: 'hl.dsp.exec_cmd(qsIpc .. "nextWallpaper")',           opts: "" },
        { id: "volUp",             label: "Volume Up (+5%)",            desc: "Increase volume with Dynamic Island OSD", lua: 'hl.dsp.exec_cmd(qsIpc .. "adjustVolume 5")',          opts: "{ locked = true, repeating = true }" },
        { id: "volDown",           label: "Volume Down (-5%)",          desc: "Decrease volume with Dynamic Island OSD", lua: 'hl.dsp.exec_cmd(qsIpc .. "adjustVolume -5")',         opts: "{ locked = true, repeating = true }" },
        { id: "volMute",           label: "Toggle Mute",                desc: "Mute or unmute audio with Island OSD",    lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleMute")',              opts: "{ locked = true }" },
        { id: "brightUp",          label: "Brightness Up (+5%)",        desc: "Increase screen brightness with OSD",     lua: 'hl.dsp.exec_cmd(qsIpc .. "adjustBrightness 5")',      opts: "{ locked = true, repeating = true }" },
        { id: "brightDown",        label: "Brightness Down (-5%)",      desc: "Decrease screen brightness with OSD",     lua: 'hl.dsp.exec_cmd(qsIpc .. "adjustBrightness -5")',     opts: "{ locked = true, repeating = true }" },
        { id: "cycleAlert",        label: "Cycle Island Alert",         desc: "Cycle active Dynamic Island alert pill",  lua: 'hl.dsp.exec_cmd(qsIpc .. "cycleAlert")',              opts: "" }
    ]

    readonly property var screenshotActions: [
        { id: "shotFullClip",   label: "Fullscreen → Clipboard",    desc: "grim",               lua: 'hl.dsp.exec_cmd("grim - | wl-copy && " .. qsIpc .. "notifyStatus \\"Screenshot copied\\"")', opts: "" },
        { id: "shotRegionClip", label: "Region Select → Clipboard", desc: "grim + slurp",       lua: 'hl.dsp.exec_cmd("grim -g \\"$(slurp)\\" - | wl-copy && " .. qsIpc .. "notifyStatus \\"Region copied\\"")', opts: "" },
        { id: "screenRecord",   label: "Screen Recording",          desc: "wf-recorder toggle", lua: 'hl.dsp.exec_cmd(qsIpc .. "toggleScreenRecord")', opts: "" },
        { id: "shotFullSave",   label: "Fullscreen → Save PNG",     desc: "~/Pictures/Screenshots", lua: 'hl.dsp.exec_cmd("mkdir -p ~/Pictures/Screenshots && grim ~/Pictures/Screenshots/shot_$(date +%Y%m%d_%H%M%S).png && " .. qsIpc .. "notifyStatus \\"Screenshot saved\\"")', opts: "" },
        { id: "shotRegionSave", label: "Region Select → Save PNG",  desc: "~/Pictures/Screenshots", lua: 'hl.dsp.exec_cmd("mkdir -p ~/Pictures/Screenshots && grim -g \\"$(slurp)\\" ~/Pictures/Screenshots/region_$(date +%Y%m%d_%H%M%S).png && " .. qsIpc .. "notifyStatus \\"Region saved\\"")', opts: "" },
        { id: "shotWindowClip", label: "Active Window → Clipboard", desc: "grim + hyprctl",     lua: 'hl.dsp.exec_cmd("hyprctl activewindow -j | python3 -c \'import sys,json;w=json.load(sys.stdin);a,s=w[\\"at\\"],w[\\"size\\"];print(f\\"{a[0]},{a[1]} {s[0]}x{s[1]}\\")\' | xargs -I{} grim -g \\"{}\\" - | wl-copy && " .. qsIpc .. "notifyStatus \\"Window copied\\"")', opts: "" }
    ]

    readonly property var defaultAppActions: [
        { id: "defaultTerminal",    label: "Default Terminal",     desc: "programs.terminal",    lua: "hl.dsp.exec_cmd(programs.terminal)",    opts: "" },
        { id: "defaultFileManager", label: "Default File Manager", desc: "programs.fileManager", lua: "hl.dsp.exec_cmd(programs.fileManager)", opts: "" },
        { id: "defaultMenu",        label: "Default App Menu",     desc: "programs.menu",        lua: "hl.dsp.exec_cmd(programs.menu)",        opts: "" }
    ]

    readonly property var windowActions: [
        { id: "winClose",      label: "Close Active Window", desc: "", lua: "hl.dsp.window.close()" },
        { id: "winKill",       label: "Force Kill Window",   desc: "", lua: "hl.dsp.window.kill()" },
        { id: "winFullscreen", label: "Toggle Fullscreen",   desc: "", lua: "hl.dsp.window.fullscreen()" },
        { id: "winFloat",      label: "Toggle Floating",     desc: "", lua: 'hl.dsp.window.float({ action = "toggle" })' },
        { id: "winPseudo",     label: "Toggle Pseudo-Tile",  desc: "", lua: "hl.dsp.window.pseudo()" },
        { id: "winSplit",      label: "Toggle Split",        desc: "", lua: 'hl.dsp.layout("togglesplit")' },
        { id: "focusLeft",     label: "Focus Left",          desc: "", lua: 'hl.dsp.focus({ direction = "left" })' },
        { id: "focusRight",    label: "Focus Right",         desc: "", lua: 'hl.dsp.focus({ direction = "right" })' },
        { id: "focusUp",       label: "Focus Up",            desc: "", lua: 'hl.dsp.focus({ direction = "up" })' },
        { id: "focusDown",     label: "Focus Down",          desc: "", lua: 'hl.dsp.focus({ direction = "down" })' },
        { id: "moveLeft",      label: "Move Window Left",    desc: "", lua: 'hl.dsp.window.move({ direction = "left" })' },
        { id: "moveRight",     label: "Move Window Right",   desc: "", lua: 'hl.dsp.window.move({ direction = "right" })' },
        { id: "moveUp",        label: "Move Window Up",      desc: "", lua: 'hl.dsp.window.move({ direction = "up" })' },
        { id: "moveDown",      label: "Move Window Down",    desc: "", lua: 'hl.dsp.window.move({ direction = "down" })' },
        { id: "wsNext",        label: "Next Workspace",      desc: "", lua: 'hl.dsp.focus({ workspace = "e+1" })' },
        { id: "wsPrev",        label: "Previous Workspace",  desc: "", lua: 'hl.dsp.focus({ workspace = "e-1" })' },
        { id: "exitHypr",      label: "Exit Hyprland",       desc: "hyprshutdown / exit", lua: 'hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit")' }
    ]

    Component.onCompleted: refresh()

    function escapeLuaString(s) {
        return String(s || "")
            .replace(/\\/g, "\\\\")
            .replace(/"/g, '\\"')
            .replace(/\r/g, "\\r")
            .replace(/\n/g, "\\n");
    }

    function buildExecCmdLua(cmd) {
        return 'hl.dsp.exec_cmd("' + escapeLuaString(cmd) + '")';
    }

    function shellQuoteArg(s) {
        const str = String(s || "");
        if (/^[A-Za-z0-9._@+\-]+$/.test(str)) return str;
        return "'" + str.replace(/'/g, "'\\''") + "'";
    }

    function buildGtkLaunchLua(appId) {
        const cmd = "gtk-launch " + shellQuoteArg(appId);
        return { cmd: cmd, lua: buildExecCmdLua(cmd) };
    }

    function buildOptsLua(existingOpts, locked, repeating) {
        const raw = String(existingOpts || "").trim();
        const extra = [];
        if (raw.startsWith("{") && raw.endsWith("}")) {
            const inner = raw.slice(1, -1).split(",");
            for (let i = 0; i < inner.length; ++i) {
                const tok = inner[i].trim();
                if (!tok) continue;
                if (/^(locked|repeating)\s*=/.test(tok)) continue;
                extra.push(tok);
            }
        }
        if (locked) extra.unshift("locked = true");
        if (repeating) {
            const insertAt = locked ? 1 : 0;
            extra.splice(insertAt, 0, "repeating = true");
        }
        return extra.length > 0 ? ("{ " + extra.join(", ") + " }") : "";
    }

    function normalizeComboKey(combo) {
        if (!combo) return "";
        const parts = String(combo).split("+").map(s => s.trim()).filter(s => s !== "");
        const mods = [];
        let key = "";
        for (let i = 0; i < parts.length; ++i) {
            let up = parts[i].toUpperCase();
            if (up === "CONTROL") up = "CTRL";
            if (up === "SUPER" || up === "CTRL" || up === "ALT" || up === "SHIFT") {
                if (mods.indexOf(up) === -1) mods.push(up);
            } else {
                key = parts[i].toLowerCase();
            }
        }
        const order = ["SUPER", "CTRL", "ALT", "SHIFT"];
        mods.sort((a, b) => order.indexOf(a) - order.indexOf(b));
        return mods.concat(key ? [key] : []).join("+");
    }

    function splitComboParts(combo) {
        if (!combo) return [];
        return String(combo).split("+").map(s => s.trim()).filter(s => s !== "");
    }

    function isModPart(part) {
        const up = String(part || "").toUpperCase();
        return up === "SUPER" || up === "CTRL" || up === "CONTROL" || up === "ALT" || up === "SHIFT";
    }

    function prettyKeyLabel(part) {
        const p = String(part || "").trim();
        const low = p.toLowerCase();
        if (low === "super") return "SUPER";
        if (low === "ctrl" || low === "control") return "CTRL";
        if (low === "alt") return "ALT";
        if (low === "shift") return "SHIFT";
        if (low === "space") return "SPACE";
        if (low === "return") return "ENTER";
        if (low === "escape") return "ESC";
        if (low === "backspace") return "BKSP";
        if (low === "delete") return "DEL";
        if (low === "insert") return "INS";
        if (low === "prior") return "PGUP";
        if (low === "next") return "PGDN";
        if (low === "print") return "PRTSC";
        if (low === "grave") return "`";
        if (low === "minus") return "-";
        if (low === "equal") return "=";
        if (low === "bracketleft") return "[";
        if (low === "bracketright") return "]";
        if (low === "backslash") return "\\";
        if (low === "semicolon") return ";";
        if (low === "apostrophe") return "'";
        if (low === "comma") return ",";
        if (low === "period") return ".";
        if (low === "slash") return "/";
        if (low === "left" || low === "right" || low === "up" || low === "down") return low.toUpperCase();
        if (p === "XF86AudioRaiseVolume") return "VOL +";
        if (p === "XF86AudioLowerVolume") return "VOL -";
        if (p === "XF86AudioMute") return "MUTE";
        if (p === "XF86AudioMicMute") return "MIC MUTE";
        if (p === "XF86MonBrightnessUp") return "BRI +";
        if (p === "XF86MonBrightnessDown") return "BRI -";
        if (p === "XF86AudioNext") return "NEXT";
        if (p === "XF86AudioPrev") return "PREV";
        if (p === "XF86AudioPlay") return "PLAY";
        if (p === "XF86AudioPause") return "PAUSE";
        if (p === "XF86AudioStop") return "STOP";
        if (p === "Super_L") return "SUPER (Tap)";
        return p.toUpperCase();
    }

    function findConflict(comboStr, ignoreBindId, ignoreComboIdx, isRelease) {
        const norm = normalizeComboKey(comboStr);
        if (!norm) return null;
        const targetRel = Boolean(isRelease);

        for (let i = 0; i < binds.length; ++i) {
            const b = binds[i];
            if (!b) continue;
            if (b.id === "builtin_ws_loop") {
                if (!targetRel) {
                    const mod = (root.mainMod || "SUPER").toUpperCase();
                    for (let d = 0; d <= 9; ++d) {
                        const k1 = normalizeComboKey(mod + " + " + d);
                        const k2 = normalizeComboKey(mod + " + SHIFT + " + d);
                        if (norm === k1 || norm === k2) {
                            return { bindId: b.id, title: b.title, category: b.category };
                        }
                    }
                }
                continue;
            }
            if (b.id === "builtin_super_tap") {
                if (!targetRel && norm === "super_l") {
                    return { bindId: b.id, title: b.title, category: b.category };
                }
                continue;
            }
            if (b.readOnly) continue;

            const combos = b.combos || [];
            for (let j = 0; j < combos.length; ++j) {
                if (b.id === ignoreBindId && (ignoreComboIdx < 0 || j === ignoreComboIdx)) continue;
                if (Boolean(combos[j].release) !== targetRel) continue;
                if (normalizeComboKey(combos[j].combo) === norm) {
                    return { bindId: b.id, title: b.title, category: b.category };
                }
            }
        }
        return null;
    }

    function recomputeCounts(list) {
        const counts = { all: 0, island: 0, screenshot: 0, apps: 0, window: 0, command: 0 };
        let totalCombos = 0;
        for (let i = 0; i < list.length; ++i) {
            const b = list[i];
            const c = b.category || "command";
            counts.all += 1;
            if (counts[c] !== undefined) counts[c] += 1;
            totalCombos += (b.combos ? b.combos.length : 0);
        }
        root.categoryCounts = counts;
        root.totalComboCount = totalCombos;
    }

    function setTransientStatus(msg, ok) {
        root.statusText = msg;
        root.statusOk = ok;
        if (msg !== "") statusClearTimer.restart();
    }

    Timer {
        id: statusClearTimer
        interval: 4200
        onTriggered: root.statusText = ""
    }

    function refresh() {
        if (readProc.running) return;
        root.busy = true;
        readProc.outBuf = "";
        readProc.errBuf = "";
        readProc._stdoutDone = false;
        readProc._stderrDone = false;
        readProc._exited = false;
        readProc._exitCode = -1;
        readProc.running = true;
    }

    function reloadHyprland() {
        if (reloadProc.running) return;
        reloadProc.outBuf = "";
        reloadProc.errBuf = "";
        reloadProc._stdoutDone = false;
        reloadProc._stderrDone = false;
        reloadProc._exited = false;
        reloadProc._exitCode = -1;
        reloadProc.running = true;
    }

    function _dispatchWrite(payloadJson, statusMsg) {
        writeProc.payloadJson = payloadJson;
        writeProc.pendingStatus = statusMsg || "Saved";
        writeProc.outBuf = "";
        writeProc.errBuf = "";
        writeProc._stdoutDone = false;
        writeProc._stderrDone = false;
        writeProc._exited = false;
        writeProc._exitCode = -1;
        writeProc.running = true;
    }

    function saveBinds(newList, statusMsg, recordUndo) {
        if (recordUndo !== false && root.binds && root.binds.length > 0) {
            root._undoSnapshot = JSON.parse(JSON.stringify(root.binds));
        }
        root.binds = newList;
        recomputeCounts(newList);
        const payload = JSON.stringify(newList);
        if (writeProc.running || resetProc.running) {
            root._queuedPayload = payload;
            root._queuedStatus = statusMsg || "Saved";
            root._hasQueuedWrite = true;
            return;
        }
        _dispatchWrite(payload, statusMsg);
    }

    function undoLastChange() {
        if (!root._undoSnapshot) return;
        const snap = root._undoSnapshot;
        root._undoSnapshot = null;
        saveBinds(snap, "Restored previous shortcut", false);
    }

    function resetToDefaults() {
        if (root.binds && root.binds.length > 0) {
            root._undoSnapshot = JSON.parse(JSON.stringify(root.binds));
        }
        if (writeProc.running) {
            root._queuedReset = true;
            return;
        }
        if (resetProc.running) return;
        resetProc.outBuf = "";
        resetProc.errBuf = "";
        resetProc._stdoutDone = false;
        resetProc._stderrDone = false;
        resetProc._exited = false;
        resetProc._exitCode = -1;
        resetProc.running = true;
    }

    function _computeTier(category, combosList) {
        if (!combosList || combosList.length === 0) return "core";
        for (let i = 0; i < combosList.length; ++i) {
            const parts = splitComboParts(combosList[i].combo);
            const last = parts.length > 0 ? parts[parts.length - 1].toUpperCase() : "";
            if (last.indexOf("XF86") !== 0) return "core";
        }
        return "system";
    }

    function addOrMergeBind(category, title, subtitle, actionLua, command, appId, combosList) {
        if (!combosList || combosList.length === 0) return;
        const copy = binds.slice();
        let existingIdx = -1;
        for (let i = 0; i < copy.length; ++i) {
            if (!copy[i].readOnly && copy[i].actionLua === actionLua) {
                existingIdx = i;
                break;
            }
        }
        if (existingIdx !== -1) {
            const item = Object.assign({}, copy[existingIdx]);
            const curCombos = (item.combos || []).slice();
            for (let k = 0; k < combosList.length; ++k) {
                const normNew = normalizeComboKey(combosList[k].combo);
                const relNew = Boolean(combosList[k].release);
                const dup = curCombos.some(c => normalizeComboKey(c.combo) === normNew && Boolean(c.release) === relNew);
                if (!dup) curCombos.push(combosList[k]);
            }
            item.combos = curCombos;
            item.groupTier = _computeTier(item.category, curCombos);
            copy[existingIdx] = item;
        } else {
            copy.push({
                id: "bind_" + Date.now() + "_" + Math.floor(Math.random() * 1000),
                category: category,
                title: title,
                subtitle: subtitle,
                actionType: category,
                actionLua: actionLua,
                command: command || "",
                appId: appId || "",
                groupTier: _computeTier(category, combosList),
                combos: combosList,
                readOnly: false,
                mainMod: root.mainMod
            });
        }
        saveBinds(copy, "Shortcut added", true);
    }

    function updateBind(bindId, category, title, subtitle, actionLua, command, appId, combosList) {
        const copy = [];
        for (let i = 0; i < binds.length; ++i) {
            if (binds[i].id === bindId) {
                if (!combosList || combosList.length === 0) continue;
                copy.push({
                    id: bindId,
                    category: category,
                    title: title,
                    subtitle: subtitle,
                    actionType: category,
                    actionLua: actionLua,
                    command: command || "",
                    appId: appId || "",
                    groupTier: _computeTier(category, combosList),
                    combos: combosList,
                    readOnly: false,
                    mainMod: root.mainMod
                });
            } else {
                copy.push(binds[i]);
            }
        }
        saveBinds(copy, "Shortcut updated", true);
    }

    function deleteBind(bindId) {
        const copy = binds.filter(b => b.id !== bindId);
        saveBinds(copy, "Shortcut deleted", true);
    }

    Process {
        id: reloadProc
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false
        property int _exitCode: -1

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;
            const out = (outBuf + " " + errBuf).trim();
            if (_exitCode !== 0 || out.toLowerCase().indexOf("err") !== -1) {
                root.setTransientStatus("Reload error: " + (out || "hyprctl failed"), false);
            } else if (root.statusText === "") {
                root.setTransientStatus("Hyprland Reloaded ✓", true);
            }
        }

        command: ["hyprctl", "reload"]
        stdout: StdioCollector {
            onStreamFinished: {
                reloadProc.outBuf = text || "";
                reloadProc._stdoutDone = true;
                reloadProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                reloadProc.errBuf = text || "";
                reloadProc._stderrDone = true;
                reloadProc.tryFinish();
            }
        }
        onExited: function(exitCode) {
            reloadProc._exitCode = exitCode;
            reloadProc._exited = true;
            reloadProc.tryFinish();
        }
    }

    Process {
        id: readProc
        command: ["python3", "-c", `
import os, re, json, shlex, sys

shell_dir = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else os.path.expanduser("~/.config/paithosh/shell")
qs_ipc = f"qs -p {shlex.quote(shell_dir)} ipc call paithosh "
cfg_home = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
binds_path = os.path.join(cfg_home, "hypr", "config", "binds.lua")
progs_path = os.path.join(cfg_home, "hypr", "config", "programs.lua")

programs = {"terminal": "kitty", "fileManager": "dolphin", "menu": "hyprlauncher"}
if os.path.exists(progs_path):
    ptxt = open(progs_path, encoding="utf-8").read()
    for k in ("terminal", "fileManager", "menu"):
        m = re.search(rf'{k}\\s*=\\s*(["\\'])([^"\\']+)\\1', ptxt)
        if m:
            programs[k] = m.group(2)

if not os.path.exists(binds_path):
    print("[]")
    raise SystemExit(0)

txt = open(binds_path, encoding="utf-8").read()
mm = re.search(r'local\\s+mainMod\\s*=\\s*(["\\'])([^"\\']+)\\1', txt)
main_mod = mm.group(2) if mm else "SUPER"

def strip_lua_strings_and_comments(line):
    out = []
    in_q = None
    esc = False
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if esc:
            esc = False
            i += 1
            continue
        if ch == "\\\\" and in_q:
            esc = True
            i += 1
            continue
        if in_q:
            if ch == in_q:
                in_q = None
            i += 1
            continue
        if ch in ('"', "'"):
            in_q = ch
            out.append(" ")
            i += 1
            continue
        if ch == "-" and i + 1 < n and line[i + 1] == "-":
            break
        out.append(ch)
        i += 1
    return "".join(out)

def count_block_delta(line):
    clean = strip_lua_strings_and_comments(line)
    opens = len(re.findall(r'(?<![.:])\\b(?:if|do|function|repeat)\\b', clean))
    closes = len(re.findall(r'(?<![.:])\\b(?:end|until)\\b', clean))
    return opens - closes, clean

def split_lua_args(s):
    args = []
    cur = []
    depth = 0
    in_q = None
    esc = False
    for ch in s:
        if esc:
            cur.append(ch)
            esc = False
            continue
        if ch == "\\\\" and in_q:
            cur.append(ch)
            esc = True
            continue
        if in_q:
            cur.append(ch)
            if ch == in_q:
                in_q = None
            continue
        if ch in ('"', "'"):
            in_q = ch
            cur.append(ch)
            continue
        if ch in "({[":
            depth += 1
            cur.append(ch)
        elif ch in ")}]":
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    tail = "".join(cur).strip()
    if tail:
        args.append(tail)
    return args

def unquote(s):
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        inner = s[1:-1]
        def _repl(m):
            c = m.group(1)
            if c == "n": return "\\n"
            if c == "r": return "\\r"
            if c == "t": return "\\t"
            return c
        return re.sub(r'\\\\(.)', _repl, inner)
    return s

def resolve_key(expr):
    expr = expr.strip()
    m = re.match(r'^mainMod\\s*\\.\\.\\s*(["\\'])(.*)\\1$', expr)
    if m:
        return main_mod + unquote(m.group(1) + m.group(2) + m.group(1))
    return unquote(expr)

def split_lua_concat(s):
    parts = []
    cur = []
    depth = 0
    in_q = None
    esc = False
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if esc:
            cur.append(ch)
            esc = False
            i += 1
            continue
        if ch == "\\\\" and in_q:
            cur.append(ch)
            esc = True
            i += 1
            continue
        if in_q:
            cur.append(ch)
            if ch == in_q:
                in_q = None
            i += 1
            continue
        if ch in ('"', "'"):
            in_q = ch
            cur.append(ch)
            i += 1
            continue
        if ch in "({[":
            depth += 1
            cur.append(ch)
            i += 1
            continue
        if ch in ")}]":
            depth -= 1
            cur.append(ch)
            i += 1
            continue
        if depth == 0 and s[i:i+2] == "..":
            tok = "".join(cur).strip()
            if tok:
                parts.append(tok)
            cur = []
            i += 2
            continue
        cur.append(ch)
        i += 1
    tail = "".join(cur).strip()
    if tail:
        parts.append(tail)
    return parts

def eval_lua_str_expr(expr):
    out = []
    for tok in split_lua_concat(expr):
        if tok == "qsIpc":
            out.append(qs_ipc)
        elif tok == "shellDir":
            out.append(shell_dir)
        elif tok.startswith("programs."):
            k = tok.split(".", 1)[1].strip()
            out.append(programs.get(k, k))
        else:
            out.append(unquote(tok))
    return "".join(out)

def extract_exec_cmd(action_lua):
    s = action_lua.strip()
    if not s.startswith("hl.dsp.exec_cmd(") or not s.endswith(")"):
        return None
    inner = s[len("hl.dsp.exec_cmd("):-1].strip()
    return eval_lua_str_expr(inner)

def classify(action_lua, cmd):
    al = action_lua.strip()
    c = cmd or ""
    if "grim" in c or "slurp" in c or "hyprshot" in c:
        if "activewindow" in c: return ("screenshot", "Active Window → Clipboard", "grim + hyprctl")
        if "slurp" in c and "wl-copy" in c: return ("screenshot", "Region Select → Clipboard", "grim + slurp")
        if "slurp" in c: return ("screenshot", "Region Select → Save PNG", "~/Pictures/Screenshots")
        if "wl-copy" in c: return ("screenshot", "Fullscreen → Clipboard", "grim")
        return ("screenshot", "Fullscreen → Save PNG", "~/Pictures/Screenshots")
    if "toggleScreenRecord" in c:
        return ("screenshot", "Screen Recording", "wf-recorder toggle")
    if "ipc call paithosh" in c or ("qs -p" in c and "paithosh" in c):
        if "superPressed" in c: return ("island", "Launcher (Super Press)", "")
        if "superReleased" in c: return ("island", "Launcher (Super Release)", "")
        if "toggleLauncher" in c: return ("island", "Toggle Launcher", "")
        if "toggleSearch" in c: return ("island", "Toggle Search", "")
        if "toggleOverview" in c: return ("island", "Workspace Overview", "")
        if "toggleClipboard" in c: return ("island", "Clipboard History", "")
        if "toggleDashboard mission" in c: return ("island", "Dashboard: Mission Control", "")
        if "toggleDashboard tasks" in c: return ("island", "Dashboard: Task Manager", "")
        if "toggleDashboard kde" in c: return ("island", "Dashboard: KDE Connect", "")
        if "toggleDashboard power" in c: return ("island", "Dashboard: Power Station", "")
        if "toggleHideBar" in c: return ("island", "Toggle Hide Bar", "")
        if "toggleBarPosition" in c: return ("island", "Swap Bar Position", "")
        if "setBarPosition" in c: return ("island", "Set Bar Position", "")
        if "openSettings" in c: return ("island", "Open Settings", "")
        if "openFiles" in c: return ("island", "Open Files Drawer", "")
        if "nextWallpaper" in c: return ("island", "Next Wallpaper", "")
        m_vol = re.search(r'adjustVolume\\s+(-?\\d+)', c)
        if m_vol:
            n = int(m_vol.group(1))
            return ("island", f"Volume {'Up' if n >= 0 else 'Down'} ({'+' if n >= 0 else ''}{n}%)", "")
        if "toggleMute" in c: return ("island", "Toggle Mute", "")
        m_bri = re.search(r'adjustBrightness\\s+(-?\\d+)', c)
        if m_bri:
            n = int(m_bri.group(1))
            return ("island", f"Brightness {'Up' if n >= 0 else 'Down'} ({'+' if n >= 0 else ''}{n}%)", "")
        if "cycleAlert" in c: return ("island", "Cycle Island Alert", "")
        if re.search(r'\\block\\b', c): return ("island", "Lock Screen", "")
        short_c = c.split("ipc call paithosh", 1)[-1].strip() if "ipc call paithosh" in c else c
        return ("island", "Island: " + short_c, "")
    if "programs.terminal" in al: return ("apps", "Terminal", programs["terminal"])
    if "programs.fileManager" in al: return ("apps", "File Manager", programs["fileManager"])
    if "programs.menu" in al: return ("apps", "App Menu", programs["menu"])
    if c.startswith("gtk-launch "):
        rest = c[len("gtk-launch "):].strip()
        try:
            toks = shlex.split(rest)
            app_id = toks[0] if toks else rest.strip('"').strip("'")
        except Exception:
            app_id = rest.strip('"').strip("'")
        nice = app_id.replace(".desktop", "").split(".")[-1].replace("-", " ").title()
        return ("apps", "Launch " + nice, app_id)
    if al.startswith("hl.dsp.window.") or al.startswith("hl.dsp.focus") or al.startswith("hl.dsp.layout") or "hyprshutdown" in c:
        if "window.close" in al: return ("window", "Close Active Window", "")
        if "window.kill" in al: return ("window", "Force Kill Window", "")
        if "window.fullscreen" in al: return ("window", "Toggle Fullscreen", "")
        if "window.float" in al: return ("window", "Toggle Floating", "")
        if "window.pseudo" in al: return ("window", "Toggle Pseudo-Tile", "")
        if "togglesplit" in al: return ("window", "Toggle Split", "")
        if "window.move" in al:
            if 'direction = "left"' in al or "direction = 'left'" in al: return ("window", "Move Window Left", "")
            if 'direction = "right"' in al or "direction = 'right'" in al: return ("window", "Move Window Right", "")
            if 'direction = "up"' in al or "direction = 'up'" in al: return ("window", "Move Window Up", "")
            if 'direction = "down"' in al or "direction = 'down'" in al: return ("window", "Move Window Down", "")
        if 'direction = "left"' in al or "direction = 'left'" in al: return ("window", "Focus Left", "")
        if 'direction = "right"' in al or "direction = 'right'" in al: return ("window", "Focus Right", "")
        if 'direction = "up"' in al or "direction = 'up'" in al: return ("window", "Focus Up", "")
        if 'direction = "down"' in al or "direction = 'down'" in al: return ("window", "Focus Down", "")
        if 'workspace = "e+1"' in al or "workspace = 'e+1'" in al: return ("window", "Next Workspace", "")
        if 'workspace = "e-1"' in al or "workspace = 'e-1'" in al: return ("window", "Previous Workspace", "")
        if "hyprshutdown" in c: return ("window", "Exit Hyprland", "hyprshutdown / exit")
        return ("window", "Window Action", al)
    if "wpctl" in c or "playerctl" in c:
        if "DEFAULT_AUDIO_SINK" in c: return ("command", "Mute Audio Output", "wpctl")
        if "DEFAULT_AUDIO_SOURCE" in c: return ("command", "Mute Microphone", "wpctl")
        if "playerctl next" in c: return ("command", "Media: Next Track", "playerctl")
        if "playerctl previous" in c: return ("command", "Media: Previous Track", "playerctl")
        if "playerctl play-pause" in c: return ("command", "Media: Play / Pause", "playerctl")
    return ("command", c if c else al, "")

groups = {}
order = []
block_depth = 0
in_long_comment = False
in_ws_loop = False
has_ws_loop = False
has_mouse_drag = False

for raw_line in txt.splitlines():
    stripped = raw_line.strip()
    if in_long_comment:
        if "]]" in stripped:
            in_long_comment = False
        continue
    if stripped.startswith("--[["):
        if "]]" not in stripped[4:]:
            in_long_comment = True
        continue
    if not stripped or stripped.startswith("--"):
        continue

    delta, clean = count_block_delta(raw_line)
    if block_depth == 0:
        if re.match(r'^for\\s+i\\s*=\\s*1\\s*,\\s*10\\b.*\\bdo\\b', clean):
            in_ws_loop = True
            has_ws_loop = True
        if delta > 0:
            block_depth += delta
            continue
    else:
        block_depth = max(0, block_depth + delta)
        if block_depth == 0:
            in_ws_loop = False
        continue

    if not stripped.startswith("hl.bind("):
        continue

    start = stripped.find("(")
    depth = 0
    in_q = None
    esc = False
    end = -1
    for idx in range(start, len(stripped)):
        ch = stripped[idx]
        if esc:
            esc = False; continue
        if ch == "\\\\" and in_q:
            esc = True; continue
        if in_q:
            if ch == in_q: in_q = None
            continue
        if ch in ('"', "'"):
            in_q = ch; continue
        if ch == "(": depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                end = idx
                break
    if end == -1:
        continue

    # Ignore lines with Lua trailing comments? Allow trailing comment after ')'
    trailing = stripped[end+1:].strip()
    if trailing and not trailing.startswith("--"):
        continue

    args = split_lua_args(stripped[start+1:end])
    if len(args) < 2:
        continue
    combo_str = resolve_key(args[0])
    action_lua = args[1].strip()
    if "mouse:272" in combo_str or "mouse:273" in combo_str:
        has_mouse_drag = True
        continue
    if "mouse:" in combo_str or "mouse_" in combo_str:
        continue
    if re.search(r'\\bfunction\\s*\\(', strip_lua_strings_and_comments(action_lua)):
        continue

    opts_lua = args[2].strip() if len(args) >= 3 else ""
    cmd = extract_exec_cmd(action_lua)
    cat, title, subtitle = classify(action_lua, cmd)
    app_id = ""
    if cmd and cmd.startswith("gtk-launch "):
        rest = cmd[len("gtk-launch "):].strip()
        try:
            toks = shlex.split(rest)
            app_id = toks[0] if toks else rest.strip('"').strip("'")
        except Exception:
            app_id = rest.strip('"').strip("'")
    combo_obj = {
        "combo": combo_str,
        "opts": opts_lua,
        "release": bool(re.search(r'\\brelease\\s*=\\s*true\\b', opts_lua)),
        "locked": bool(re.search(r'\\blocked\\s*=\\s*true\\b', opts_lua)),
        "repeating": bool(re.search(r'\\brepeating\\s*=\\s*true\\b', opts_lua))
    }
    if action_lua not in groups:
        groups[action_lua] = {
            "id": f"bind_{len(order)}",
            "category": cat,
            "title": title,
            "subtitle": subtitle,
            "actionType": cat,
            "actionLua": action_lua,
            "command": cmd or "",
            "appId": app_id,
            "groupTier": "core",
            "combos": [combo_obj],
            "readOnly": False,
            "mainMod": main_mod
        }
        order.append(action_lua)
    else:
        groups[action_lua]["combos"].append(combo_obj)

super_press_k = 'hl.dsp.exec_cmd(qsIpc .. "superPressed")'
super_rel_k = 'hl.dsp.exec_cmd(qsIpc .. "superReleased")'
has_super_pair = (super_press_k in groups and super_rel_k in groups)

res = []
for k in order:
    if has_super_pair and k in (super_press_k, super_rel_k):
        continue
    item = groups[k]
    all_xf86 = all(c["combo"].split("+")[-1].strip().upper().startswith("XF86") for c in item["combos"])
    item["groupTier"] = "system" if all_xf86 else "core"
    res.append(item)

if has_super_pair:
    res.append({
        "id": "builtin_super_tap",
        "category": "island",
        "title": "Launcher & Bar Peek (Super Tap)",
        "subtitle": "Tap Super for Launcher • Hold to peek hidden bar",
        "actionType": "island",
        "actionLua": "__BUILTIN_SUPER_TAP__",
        "command": "",
        "appId": "",
        "groupTier": "system",
        "combos": [{"combo": "Super_L", "opts": "", "release": False, "locked": False, "repeating": False}],
        "readOnly": True,
        "mainMod": main_mod
    })

if has_ws_loop:
    res.append({
        "id": "builtin_ws_loop",
        "category": "window",
        "title": "Workspaces 1–10 (Focus & Move)",
        "subtitle": "Built-in Lua loop",
        "actionType": "window",
        "actionLua": "",
        "command": "",
        "appId": "",
        "groupTier": "system",
        "combos": [{"combo": f"{main_mod} + 1..0", "opts": ""}, {"combo": f"{main_mod} + SHIFT + 1..0", "opts": ""}],
        "readOnly": True,
        "mainMod": main_mod
    })

if has_mouse_drag:
    res.append({
        "id": "builtin_mouse_drag",
        "category": "window",
        "title": "Mouse Drag & Resize",
        "subtitle": "Move or resize windows",
        "actionType": "window",
        "actionLua": "",
        "command": "",
        "appId": "",
        "groupTier": "system",
        "combos": [{"combo": f"{main_mod} + LMB", "opts": ""}, {"combo": f"{main_mod} + RMB", "opts": ""}],
        "readOnly": True,
        "mainMod": main_mod
    })

print(json.dumps(res))
`, root.shellDir]
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false
        property int _exitCode: -1

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;
            root.busy = false;
            if (_exitCode !== 0) {
                root.setTransientStatus("Failed to read binds.lua", false);
                return;
            }
            try {
                const parsed = JSON.parse(outBuf);
                if (Array.isArray(parsed)) {
                    root.binds = parsed;
                    root.recomputeCounts(parsed);
                    if (parsed.length > 0 && parsed[0].mainMod) {
                        root.mainMod = parsed[0].mainMod;
                    }
                }
            } catch (e) {
                root.setTransientStatus("Failed to parse binds.lua", false);
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                readProc.outBuf = text || "";
                readProc._stdoutDone = true;
                readProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                readProc.errBuf = text || "";
                readProc._stderrDone = true;
                readProc.tryFinish();
            }
        }
        onExited: function(exitCode) {
            readProc._exitCode = exitCode;
            readProc._exited = true;
            readProc.tryFinish();
        }
    }

    Process {
        id: writeProc
        property string payloadJson: "[]"
        property string pendingStatus: "Saved"
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false
        property int _exitCode: -1

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;

            if (root._queuedReset) {
                root._queuedReset = false;
                root._hasQueuedWrite = false;
                root.resetToDefaults();
                return;
            }
            if (root._hasQueuedWrite) {
                const nextPayload = root._queuedPayload;
                const nextStatus = root._queuedStatus;
                root._hasQueuedWrite = false;
                root._dispatchWrite(nextPayload, nextStatus);
                return;
            }

            if (_exitCode === 0 && outBuf.trim() === "ok") {
                root.reloadHyprland();
                if (pendingStatus) {
                    root.setTransientStatus(pendingStatus + " ✓", true);
                }
            } else {
                const errLine = (errBuf || outBuf || "").trim().split("\n")[0] || "Lua validation error";
                root.setTransientStatus("Save failed: " + errLine, false);
                root.refresh();
            }
        }

        command: ["python3", "-c", `
import os, re, sys, json, shutil, subprocess

binds = json.loads(sys.argv[1])
cfg_home = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
binds_path = os.path.join(cfg_home, "hypr", "config", "binds.lua")

known_headers = {
    "-- Keybindings",
    "-- Keybindings (managed by Paithosh Settings)",
    "-- Core applications & window management",
    "-- Paithosh shell IPC",
    "-- Paithosh Dynamic Island & Shell IPC",
    "-- Focus movement",
    "-- Workspaces 1-10",
    "-- Screenshot (grim + slurp -> clipboard + status bar notification)",
    "-- Screenshot & Capture",
    "-- Capture & Record",
    "-- Screen Recording (wf-recorder toggle -> <=20MB clipboard, >20MB ~/Videos)",
    "-- Cycle workspaces",
    "-- Applications",
    "-- Window & Workspace Management",
    "-- Mouse drag & resize",
    "-- Media & brightness",
    "-- Playerctl",
    "-- Custom Commands & Media",
    "-- Custom Lua (preserved)",
}

def strip_lua_strings_and_comments(line):
    out = []
    in_q = None
    esc = False
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if esc:
            esc = False; i += 1; continue
        if ch == "\\\\" and in_q:
            esc = True; i += 1; continue
        if in_q:
            if ch == in_q: in_q = None
            i += 1; continue
        if ch in ('"', "'"):
            in_q = ch; out.append(" "); i += 1; continue
        if ch == "-" and i + 1 < n and line[i + 1] == "-":
            break
        out.append(ch); i += 1
    return "".join(out)

def count_block_delta(line):
    clean = strip_lua_strings_and_comments(line)
    opens = len(re.findall(r'(?<![.:])\\b(?:if|do|function|repeat)\\b', clean))
    closes = len(re.findall(r'(?<![.:])\\b(?:end|until)\\b', clean))
    return opens - closes, clean

def split_lua_args(s):
    args = []; cur = []; depth = 0; in_q = None; esc = False
    for ch in s:
        if esc: cur.append(ch); esc = False; continue
        if ch == "\\\\" and in_q: cur.append(ch); esc = True; continue
        if in_q:
            cur.append(ch)
            if ch == in_q: in_q = None
            continue
        if ch in ('"', "'"): in_q = ch; cur.append(ch); continue
        if ch in "({[": depth += 1; cur.append(ch)
        elif ch in ")}]": depth -= 1; cur.append(ch)
        elif ch == "," and depth == 0: args.append("".join(cur).strip()); cur = []
        else: cur.append(ch)
    tail = "".join(cur).strip()
    if tail: args.append(tail)
    return args

def is_managed_bind_line(stripped):
    if not stripped.startswith("hl.bind("):
        return False, "", ""
    start = stripped.find("(")
    depth = 0; in_q = None; esc = False; end = -1
    for idx in range(start, len(stripped)):
        ch = stripped[idx]
        if esc: esc = False; continue
        if ch == "\\\\" and in_q: esc = True; continue
        if in_q:
            if ch == in_q: in_q = None
            continue
        if ch in ('"', "'"): in_q = ch; continue
        if ch == "(": depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                end = idx; break
    if end == -1:
        return False, "", ""
    trailing = stripped[end+1:].strip()
    if trailing and not trailing.startswith("--"):
        return False, "", ""
    args = split_lua_args(stripped[start+1:end])
    if len(args) < 2:
        return False, "", ""
    k_expr = args[0].strip()
    a_expr = args[1].strip()
    if "mouse:272" in k_expr or "mouse:273" in k_expr:
        return True, k_expr, a_expr
    if "mouse:" in k_expr or "mouse_" in k_expr:
        return False, k_expr, a_expr
    if re.search(r'\\bfunction\\s*\\(', strip_lua_strings_and_comments(a_expr)):
        return False, k_expr, a_expr
    return True, k_expr, a_expr

main_mod = "SUPER"
has_ws_loop = not os.path.exists(binds_path)
has_mouse_272 = not os.path.exists(binds_path)
has_mouse_273 = not os.path.exists(binds_path)
preserved_custom = []

if os.path.exists(binds_path):
    old_txt = open(binds_path, encoding="utf-8").read()
    mm = re.search(r'local\\s+mainMod\\s*=\\s*(["\\'])([^"\\']+)\\1', old_txt)
    if mm:
        main_mod = mm.group(2)

    old_lines = old_txt.splitlines()
    i = 0
    n_lines = len(old_lines)
    in_long_comment = False
    while i < n_lines:
        raw = old_lines[i]
        stripped = raw.strip()
        if in_long_comment:
            preserved_custom.append(raw)
            if "]]" in stripped:
                in_long_comment = False
            i += 1
            continue
        if stripped.startswith("--[["):
            preserved_custom.append(raw)
            if "]]" not in stripped[4:]:
                in_long_comment = True
            i += 1
            continue
        if not stripped:
            i += 1
            continue
        if stripped in known_headers:
            i += 1
            continue
        if (re.match(r'^local\\s+programs\\s*=\\s*require\\(', stripped) or
            re.match(r'^local\\s+(?:ok_p\\s*,\\s*)?paithosh\\s*=', stripped) or
            re.match(r'^local\\s+shellDir\\s*=', stripped) or
            re.match(r'^local\\s+qsIpc\\s*=', stripped) or
            re.match(r'^local\\s+mainMod\\s*=', stripped)):
            i += 1
            continue

        delta, clean = count_block_delta(raw)
        if delta > 0:
            block = [raw]
            depth = delta
            is_shell_quote = bool(re.match(r'^local\\s+function\\s+shellQuote\\b', clean))
            is_ws_for = bool(re.match(r'^for\\s+i\\s*=\\s*1\\s*,\\s*10\\b.*\\bdo\\b', clean))
            i += 1
            while i < n_lines and depth > 0:
                b_raw = old_lines[i]
                block.append(b_raw)
                b_delta, _ = count_block_delta(b_raw)
                depth = max(0, depth + b_delta)
                i += 1
            if is_shell_quote:
                continue
            if is_ws_for:
                has_ws_loop = True
                continue
            preserved_custom.extend(block)
            continue

        managed, k_expr, _ = is_managed_bind_line(stripped)
        if managed:
            if "mouse:272" in k_expr:
                has_mouse_272 = True
            elif "mouse:273" in k_expr:
                has_mouse_273 = True
            i += 1
            continue

        preserved_custom.append(raw)
        i += 1

def fmt_key(combo):
    c = combo.strip()
    prefix = main_mod + " + "
    if main_mod and c.startswith(prefix):
        rest = c[len(prefix):].replace("\\\\", "\\\\\\\\").replace('"', '\\\\"')
        return f'mainMod .. " + {rest}"'
    escaped = c.replace("\\\\", "\\\\\\\\").replace('"', '\\\\"')
    return f'"{escaped}"'

cat_titles = [
    ("island", "Paithosh Dynamic Island & Shell IPC"),
    ("screenshot", "Capture & Record"),
    ("apps", "Applications"),
    ("window", "Window & Workspace Management"),
    ("command", "Custom Commands & Media")
]

fallback_shell = (sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else os.path.expanduser("~/.config/paithosh/shell")).replace("\\\\", "\\\\\\\\").replace('"', '\\\\"')
main_mod_esc = main_mod.replace("\\\\", "\\\\\\\\").replace('"', '\\\\"')

lines = [
    "-- Keybindings (managed by Paithosh Settings)",
    "",
    "local function shellQuote(s)",
    r'''    return "'" .. tostring(s):gsub("'", "'\\\\''") .. "'"''',
    "end",
    "",
    'local programs = require("config.programs")',
    'local ok_p, paithosh = pcall(require, "config.paithosh")',
    f'local shellDir = (ok_p and type(paithosh) == "table" and paithosh.root) and (paithosh.root .. "/shell") or "{fallback_shell}"',
    'local qsIpc    = "qs -p " .. shellQuote(shellDir) .. " ipc call paithosh "',
    f'local mainMod  = "{main_mod_esc}"',
    ""
]

has_super_tap = any(b.get("id") == "builtin_super_tap" for b in binds)
has_ws_payload = any(b.get("id") == "builtin_ws_loop" for b in binds)
has_mouse_payload = any(b.get("id") == "builtin_mouse_drag" for b in binds)
if has_ws_payload:
    has_ws_loop = True
if has_mouse_payload and not (has_mouse_272 or has_mouse_273):
    has_mouse_272 = True
    has_mouse_273 = True

for cat_key, cat_header in cat_titles:
    cat_items = [b for b in binds if not b.get("readOnly") and b.get("category") == cat_key]
    emit_super_here = (cat_key == "island" and has_super_tap)
    if not cat_items and not emit_super_here:
        continue
    lines.append(f"-- {cat_header}")
    if emit_super_here:
        lines.append('hl.bind("Super_L", hl.dsp.exec_cmd(qsIpc .. "superPressed"))')
        lines.append('hl.bind("SUPER + Super_L", hl.dsp.exec_cmd(qsIpc .. "superReleased"), { release = true })')
    for b in cat_items:
        action_lua = b.get("actionLua", "").strip()
        if not action_lua or action_lua == "__BUILTIN_SUPER_TAP__":
            continue
        for c in b.get("combos", []):
            k_expr = fmt_key(c.get("combo", ""))
            opts = c.get("opts", "").strip()
            if opts:
                lines.append(f"hl.bind({k_expr}, {action_lua}, {opts})")
            else:
                lines.append(f"hl.bind({k_expr}, {action_lua})")
    lines.append("")

if has_ws_loop:
    lines.extend([
        "-- Workspaces 1-10",
        "for i = 1, 10 do",
        "    local key = tostring(i % 10)",
        '    hl.bind(mainMod .. " + " .. key,          hl.dsp.focus({ workspace = i }))',
        '    hl.bind(mainMod .. " + SHIFT + " .. key,  hl.dsp.window.move({ workspace = i }))',
        "end",
        ""
    ])

if has_mouse_272 or has_mouse_273:
    lines.append("-- Mouse drag & resize")
    if has_mouse_272:
        lines.append('hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })')
    if has_mouse_273:
        lines.append('hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })')
    lines.append("")

if preserved_custom:
    lines.append("-- Custom Lua (preserved)")
    lines.extend(preserved_custom)
    lines.append("")

os.makedirs(os.path.dirname(binds_path), exist_ok=True)
tmp_path = f"{binds_path}.tmp.{os.getpid()}"
with open(tmp_path, "w", encoding="utf-8") as f:
    f.write("\\n".join(lines))
    f.flush()
    os.fsync(f.fileno())

def validate_lua_file(path):
    if shutil.which("luajit"):
        r = subprocess.run(["luajit", "-bl", path, "/dev/null"], capture_output=True, text=True)
        return r.returncode == 0, r.stderr or r.stdout
    if shutil.which("luac"):
        r = subprocess.run(["luac", "-p", path], capture_output=True, text=True)
        return r.returncode == 0, r.stderr or r.stdout
    if shutil.which("lua"):
        r = subprocess.run(["lua", "-e", "assert(loadfile(arg[1]))", path], capture_output=True, text=True)
        return r.returncode == 0, r.stderr or r.stdout
    return True, ""

ok_lua, lua_err = validate_lua_file(tmp_path)
if not ok_lua:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    sys.stderr.write((lua_err or "Invalid Lua syntax").strip() + "\\n")
    raise SystemExit(1)

if os.path.exists(binds_path):
    shutil.copy2(binds_path, binds_path + ".bak")
os.replace(tmp_path, binds_path)
print("ok")
`, writeProc.payloadJson, root.shellDir]
        stdout: StdioCollector {
            onStreamFinished: {
                writeProc.outBuf = text || "";
                writeProc._stdoutDone = true;
                writeProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                writeProc.errBuf = text || "";
                writeProc._stderrDone = true;
                writeProc.tryFinish();
            }
        }
        onExited: function(exitCode) {
            writeProc._exitCode = exitCode;
            writeProc._exited = true;
            writeProc.tryFinish();
        }
    }

    Process {
        id: resetProc
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false
        property int _exitCode: -1

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;
            if (_exitCode === 0 && outBuf.trim() === "ok") {
                root.refresh();
                root.reloadHyprland();
                root.setTransientStatus("Reset to Defaults ✓", true);
            } else {
                const errLine = (errBuf || outBuf || "").trim().split("\n")[0] || "Failed to reset";
                root.setTransientStatus("Reset failed: " + errLine, false);
            }
            if (root._hasQueuedWrite) {
                const nextPayload = root._queuedPayload;
                const nextStatus = root._queuedStatus;
                root._hasQueuedWrite = false;
                root._dispatchWrite(nextPayload, nextStatus);
            }
        }

        command: ["python3", "-c", `
import os, sys, shutil, subprocess

repo_root = sys.argv[1] if len(sys.argv) > 1 else ""
src_path = os.path.join(repo_root, "defaults", "hypr", "config", "binds.lua")
cfg_home = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
binds_path = os.path.join(cfg_home, "hypr", "config", "binds.lua")

if not os.path.isfile(src_path):
    sys.stderr.write("Default binds.lua not found\\n")
    raise SystemExit(1)

os.makedirs(os.path.dirname(binds_path), exist_ok=True)
tmp_path = f"{binds_path}.tmp.{os.getpid()}"
shutil.copy2(src_path, tmp_path)

if shutil.which("luajit"):
    r = subprocess.run(["luajit", "-bl", tmp_path, "/dev/null"], capture_output=True, text=True)
    if r.returncode != 0:
        os.unlink(tmp_path)
        sys.stderr.write((r.stderr or r.stdout or "Invalid default Lua").strip() + "\\n")
        raise SystemExit(1)

if os.path.exists(binds_path):
    shutil.copy2(binds_path, binds_path + ".bak")
os.replace(tmp_path, binds_path)
print("ok")
`, root.projectRoot]
        stdout: StdioCollector {
            onStreamFinished: {
                resetProc.outBuf = text || "";
                resetProc._stdoutDone = true;
                resetProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                resetProc.errBuf = text || "";
                resetProc._stderrDone = true;
                resetProc.tryFinish();
            }
        }
        onExited: function(exitCode) {
            resetProc._exitCode = exitCode;
            resetProc._exited = true;
            resetProc.tryFinish();
        }
    }
}
