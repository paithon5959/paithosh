pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var binds: []
    property int totalComboCount: 0
    property var categoryCounts: ({ all: 0, island: 0, screenshot: 0, apps: 0, window: 0, command: 0 })
    property string statusText: ""
    property bool statusOk: true
    property bool busy: false

    readonly property var categoryOrder: ["island", "screenshot", "apps", "window", "command"]
    readonly property var categoryMeta: ({
        island:     { label: "Dynamic Island",        icon: "◈", desc: "Paithosh shell, launcher, search & OSD" },
        screenshot: { label: "Screenshot & Capture",  icon: "⬓", desc: "Grim & Slurp screen capture shortcuts" },
        apps:       { label: "Applications",          icon: "⊞", desc: "Launch .desktop apps & default programs" },
        window:     { label: "Window & Workspace",    icon: "◫", desc: "Focus, tiling, close & workspace navigation" },
        command:    { label: "Commands & Media",      icon: "⌘", desc: "Custom shell commands & media keys" }
    })

    readonly property string shellDir: Quickshell.shellDir

    readonly property var islandActions: [
        { id: "toggleLauncher", label: "Toggle Launcher",           desc: "Open or close Paithosh app launcher",       cmd: "qs -p " + shellDir + " ipc call paithosh toggleLauncher", opts: "" },
        { id: "toggleSearch",   label: "Toggle Search",             desc: "Open universal search in Dynamic Island",   cmd: "qs -p " + shellDir + " ipc call paithosh toggleSearch", opts: "" },
        { id: "toggleOverview", label: "Workspace Overview",        desc: "Show all workspaces & window overview",     cmd: "qs -p " + shellDir + " ipc call paithosh toggleOverview", opts: "" },
        { id: "dashMission",    label: "Dashboard: Mission Control",desc: "Open Mission Control tab in Island",        cmd: "qs -p " + shellDir + " ipc call paithosh toggleDashboard mission", opts: "" },
        { id: "dashTasks",      label: "Dashboard: Task Manager",   desc: "Open Task Manager tab in Island",           cmd: "qs -p " + shellDir + " ipc call paithosh toggleDashboard tasks", opts: "" },
        { id: "dashKde",        label: "Dashboard: KDE Connect",    desc: "Open KDE Connect tab in Island",            cmd: "qs -p " + shellDir + " ipc call paithosh toggleDashboard kde", opts: "" },
        { id: "dashPower",      label: "Dashboard: Power Station",  desc: "Open Power Station tab in Island",          cmd: "qs -p " + shellDir + " ipc call paithosh toggleDashboard power", opts: "" },
        { id: "toggleHideBar",  label: "Toggle Hide Bar",           desc: "Show or hide the Dynamic Island bar",       cmd: "qs -p " + shellDir + " ipc call paithosh toggleHideBar", opts: "" },
        { id: "openSettings",   label: "Open Settings",             desc: "Open Paithosh Settings panel",              cmd: "qs -p " + shellDir + " ipc call paithosh openSettings home", opts: "" },
        { id: "openFiles",      label: "Open Files Drawer",         desc: "Open quick file browser in Island",         cmd: "qs -p " + shellDir + " ipc call paithosh openFiles", opts: "" },
        { id: "nextWallpaper",  label: "Next Wallpaper",            desc: "Cycle to the next desktop wallpaper",       cmd: "qs -p " + shellDir + " ipc call paithosh nextWallpaper", opts: "" },
        { id: "volUp",          label: "Volume Up (+5%)",           desc: "Increase volume with Dynamic Island OSD",   cmd: "qs -p " + shellDir + " ipc call paithosh adjustVolume 5", opts: "{ locked = true, repeating = true }" },
        { id: "volDown",        label: "Volume Down (-5%)",         desc: "Decrease volume with Dynamic Island OSD",   cmd: "qs -p " + shellDir + " ipc call paithosh adjustVolume -5", opts: "{ locked = true, repeating = true }" },
        { id: "volMute",        label: "Toggle Mute",               desc: "Mute or unmute audio with Island OSD",      cmd: "qs -p " + shellDir + " ipc call paithosh toggleMute", opts: "{ locked = true }" },
        { id: "brightUp",       label: "Brightness Up (+5%)",       desc: "Increase screen brightness with OSD",       cmd: "qs -p " + shellDir + " ipc call paithosh adjustBrightness 5", opts: "{ locked = true, repeating = true }" },
        { id: "brightDown",     label: "Brightness Down (-5%)",     desc: "Decrease screen brightness with OSD",       cmd: "qs -p " + shellDir + " ipc call paithosh adjustBrightness -5", opts: "{ locked = true, repeating = true }" },
        { id: "cycleAlert",     label: "Cycle Island Alert",        desc: "Cycle active Dynamic Island alert pill",    cmd: "qs -p " + shellDir + " ipc call paithosh cycleAlert", opts: "" }
    ]

    readonly property var screenshotActions: [
        { id: "shotFullClip",   label: "Fullscreen → Clipboard",    desc: "Capture full screen & copy to clipboard",   cmd: "grim - | wl-copy && qs -p " + shellDir + " ipc call paithosh notifyStatus \"Screenshot copied\"", opts: "" },
        { id: "shotRegionClip", label: "Region Select → Clipboard", desc: "Select area with slurp & copy to clipboard",cmd: "grim -g \"$(slurp)\" - | wl-copy && qs -p " + shellDir + " ipc call paithosh notifyStatus \"Region copied\"", opts: "" },
        { id: "shotFullSave",   label: "Fullscreen → Save PNG",     desc: "Save full screen to ~/Pictures/Screenshots",cmd: "mkdir -p ~/Pictures/Screenshots && grim ~/Pictures/Screenshots/shot_$(date +%Y%m%d_%H%M%S).png && qs -p " + shellDir + " ipc call paithosh notifyStatus \"Screenshot saved\"", opts: "" },
        { id: "shotRegionSave", label: "Region Select → Save PNG",  desc: "Save selected area to ~/Pictures/Screenshots",cmd: "mkdir -p ~/Pictures/Screenshots && grim -g \"$(slurp)\" ~/Pictures/Screenshots/region_$(date +%Y%m%d_%H%M%S).png && qs -p " + shellDir + " ipc call paithosh notifyStatus \"Region saved\"", opts: "" },
        { id: "shotWindowClip", label: "Active Window → Clipboard", desc: "Capture focused window & copy to clipboard",cmd: "hyprctl activewindow -j | python3 -c \"import sys,json;w=json.load(sys.stdin);print(f'{w[\\\"at\\\"][0]},{w[\\\"at\\\"][1]} {w[\\\"size\\\"][0]}x{w[\\\"size\\\"][1]}')\" | xargs -I{} grim -g \"{}\" - | wl-copy && qs -p " + shellDir + " ipc call paithosh notifyStatus \"Window copied\"", opts: "" }
    ]

    readonly property var windowActions: [
        { id: "winClose",  label: "Close Active Window",  desc: "Gracefully close focused window",         lua: "hl.dsp.window.close()" },
        { id: "winKill",   label: "Force Kill Window",    desc: "Kill unresponsive focused window",        lua: "hl.dsp.window.kill()" },
        { id: "winFloat",  label: "Toggle Floating",      desc: "Switch between tiled and floating",       lua: "hl.dsp.window.float({ action = \"toggle\" })" },
        { id: "winPseudo", label: "Toggle Pseudo-Tile",   desc: "Preserve window size in dwindle layout",  lua: "hl.dsp.window.pseudo()" },
        { id: "winSplit",  label: "Toggle Split",         desc: "Flip horizontal/vertical split",          lua: "hl.dsp.layout(\"togglesplit\")" },
        { id: "wsNext",    label: "Next Workspace",       desc: "Switch to next workspace (e+1)",          lua: "hl.dsp.focus({ workspace = \"e+1\" })" },
        { id: "wsPrev",    label: "Previous Workspace",   desc: "Switch to previous workspace (e-1)",      lua: "hl.dsp.focus({ workspace = \"e-1\" })" }
    ]

    Component.onCompleted: refresh()

    function normalizeComboKey(combo) {
        if (!combo) return "";
        const parts = String(combo).split("+").map(s => s.trim()).filter(s => s !== "");
        const mods = [];
        let key = "";
        for (let i = 0; i < parts.length; ++i) {
            const up = parts[i].toUpperCase();
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

    function findConflict(comboStr, ignoreBindId, ignoreComboIdx) {
        const norm = normalizeComboKey(comboStr);
        if (!norm) return null;
        for (let i = 0; i < binds.length; ++i) {
            const b = binds[i];
            if (!b || b.readOnly) continue;
            const combos = b.combos || [];
            for (let j = 0; j < combos.length; ++j) {
                if (b.id === ignoreBindId && j === ignoreComboIdx) continue;
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
        statusClearTimer.restart();
    }

    Timer {
        id: statusClearTimer
        interval: 3500
        onTriggered: root.statusText = ""
    }

    function refresh() {
        if (readProc.running) return;
        root.busy = true;
        readProc.running = true;
    }

    function reloadHyprland() {
        if (reloadProc.running) return;
        reloadProc.running = true;
    }

    function saveBinds(newList, statusMsg) {
        root.binds = newList;
        recomputeCounts(newList);
        writeProc.payloadJson = JSON.stringify(newList);
        writeProc.pendingStatus = statusMsg || "Saved & Reloaded";
        if (writeProc.running) writeProc.running = false;
        writeProc.running = true;
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
                const dup = curCombos.some(c => normalizeComboKey(c.combo) === normNew);
                if (!dup) curCombos.push(combosList[k]);
            }
            item.combos = curCombos;
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
                combos: combosList,
                readOnly: false
            });
        }
        saveBinds(copy, "Added & Reloaded");
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
                    combos: combosList,
                    readOnly: false
                });
            } else {
                copy.push(binds[i]);
            }
        }
        saveBinds(copy, "Updated & Reloaded");
    }

    function addComboToBind(bindId, comboObj) {
        const copy = binds.slice();
        for (let i = 0; i < copy.length; ++i) {
            if (copy[i].id === bindId) {
                const item = Object.assign({}, copy[i]);
                const cur = (item.combos || []).slice();
                const norm = normalizeComboKey(comboObj.combo);
                if (!cur.some(c => normalizeComboKey(c.combo) === norm)) {
                    cur.push(comboObj);
                }
                item.combos = cur;
                copy[i] = item;
                break;
            }
        }
        saveBinds(copy, "Shortcut Added");
    }

    function removeComboFromBind(bindId, comboIndex) {
        const copy = [];
        for (let i = 0; i < binds.length; ++i) {
            if (binds[i].id === bindId) {
                const item = Object.assign({}, binds[i]);
                const cur = (item.combos || []).slice();
                cur.splice(comboIndex, 1);
                if (cur.length > 0) {
                    item.combos = cur;
                    copy.push(item);
                }
            } else {
                copy.push(binds[i]);
            }
        }
        saveBinds(copy, "Shortcut Removed");
    }

    function deleteBind(bindId) {
        const copy = binds.filter(b => b.id !== bindId);
        saveBinds(copy, "Keybind Deleted");
    }

    Process {
        id: reloadProc
        command: ["hyprctl", "reload"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text.trim();
                if (out.toLowerCase().indexOf("err") !== -1) {
                    root.setTransientStatus("Reload error: " + out, false);
                } else {
                    root.setTransientStatus("Hyprland Reloaded ✓", true);
                }
            }
        }
    }

    Process {
        id: readProc
        command: ["python3", "-c", `
import os, re, json, shlex, sys

shell_dir = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else os.path.expanduser("~/.config/paithosh/shell")
qs_ipc = f"qs -p {shlex.quote(shell_dir)} ipc call paithosh "
binds_path = os.path.expanduser("~/.config/hypr/config/binds.lua")
progs_path = os.path.expanduser("~/.config/hypr/config/programs.lua")

programs = {"terminal": "kitty", "fileManager": "dolphin", "menu": "hyprlauncher"}
if os.path.exists(progs_path):
    ptxt = open(progs_path, encoding="utf-8").read()
    for k in ("terminal", "fileManager", "menu"):
        m = re.search(rf'{k}\\s*=\\s*"([^"]+)"', ptxt)
        if m:
            programs[k] = m.group(1)

if not os.path.exists(binds_path):
    print("[]")
    raise SystemExit(0)

txt = open(binds_path, encoding="utf-8").read()
mm = re.search(r'local\\s+mainMod\\s*=\\s*"([^"]+)"', txt)
main_mod = mm.group(1) if mm else "SUPER"

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
        inner = inner.replace('\\\\"', '"').replace("\\\\'", "'").replace("\\\\\\\\", "\\\\")
        return inner
    return s

def resolve_key(expr):
    expr = expr.strip()
    m = re.match(r'^mainMod\\s*\\.\\.\\s*"(.*)"$', expr)
    if m:
        return main_mod + m.group(1)
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
        if "activewindow" in c: return ("screenshot", "Active Window → Clipboard", "Capture focused window")
        if "slurp" in c and "wl-copy" in c: return ("screenshot", "Region Select → Clipboard", "Select area & copy to clipboard")
        if "slurp" in c: return ("screenshot", "Region Select → Save PNG", "Save selected area to Pictures")
        if "wl-copy" in c: return ("screenshot", "Fullscreen → Clipboard", "Capture full screen & copy")
        return ("screenshot", "Fullscreen → Save PNG", "Save full screen to Pictures")
    if "ipc call paithosh" in c or ("qs -p" in c and "paithosh" in c):
        if "superPressed" in c: return ("island", "Launcher (Super Press)", "Press Super to open launcher")
        if "superReleased" in c: return ("island", "Launcher (Super Release)", "Release Super to toggle launcher")
        if "toggleLauncher" in c: return ("island", "Toggle Launcher", "Open or close Paithosh launcher")
        if "toggleSearch" in c: return ("island", "Toggle Search", "Open universal search in Dynamic Island")
        if "toggleOverview" in c: return ("island", "Workspace Overview", "Toggle Dynamic Island workspace overview")
        if "toggleDashboard mission" in c: return ("island", "Dashboard: Mission Control", "Open Mission Control tab")
        if "toggleDashboard tasks" in c: return ("island", "Dashboard: Task Manager", "Open Task Manager tab")
        if "toggleDashboard kde" in c: return ("island", "Dashboard: KDE Connect", "Open KDE Connect tab")
        if "toggleDashboard power" in c: return ("island", "Dashboard: Power Station", "Open Power Station tab")
        if "toggleHideBar" in c: return ("island", "Toggle Hide Bar", "Show or hide Dynamic Island")
        if "openSettings" in c: return ("island", "Open Settings", "Open Paithosh Settings")
        if "openFiles" in c: return ("island", "Open Files Drawer", "Open Island file browser")
        if "nextWallpaper" in c: return ("island", "Next Wallpaper", "Cycle desktop wallpaper")
        if "adjustVolume 5" in c: return ("island", "Volume Up (+5%)", "Dynamic Island volume OSD")
        if "adjustVolume -5" in c: return ("island", "Volume Down (-5%)", "Dynamic Island volume OSD")
        if "toggleMute" in c: return ("island", "Toggle Mute", "Mute or unmute audio")
        if "adjustBrightness 5" in c: return ("island", "Brightness Up (+5%)", "Dynamic Island brightness OSD")
        if "adjustBrightness -5" in c: return ("island", "Brightness Down (-5%)", "Dynamic Island brightness OSD")
        if "cycleAlert" in c: return ("island", "Cycle Island Alert", "Cycle active Island alert")
        return ("island", "Dynamic Island Action", c)
    if "programs.terminal" in al: return ("apps", "Terminal (" + programs["terminal"] + ")", "Default terminal emulator")
    if "programs.fileManager" in al: return ("apps", "File Manager (" + programs["fileManager"] + ")", "Default file manager")
    if "programs.menu" in al: return ("apps", "App Menu (" + programs["menu"] + ")", "Default launcher menu")
    if c.startswith("gtk-launch "):
        app_id = c[len("gtk-launch "):].strip().strip('"').strip("'")
        nice = app_id.replace(".desktop", "").split(".")[-1].replace("-", " ").title()
        return ("apps", "Launch " + nice, c)
    if al.startswith("hl.dsp.window.") or al.startswith("hl.dsp.focus") or al.startswith("hl.dsp.layout") or "hyprshutdown" in c:
        if "window.close" in al: return ("window", "Close Active Window", "Gracefully close focused window")
        if "window.kill" in al: return ("window", "Force Kill Window", "Kill unresponsive window")
        if "window.float" in al: return ("window", "Toggle Floating", "Switch tiled / floating mode")
        if "window.pseudo" in al: return ("window", "Toggle Pseudo-Tile", "Preserve window size in dwindle")
        if "togglesplit" in al: return ("window", "Toggle Split", "Flip split direction")
        if 'direction = "left"' in al: return ("window", "Focus Left", "Move focus to left window")
        if 'direction = "right"' in al: return ("window", "Focus Right", "Move focus to right window")
        if 'direction = "up"' in al: return ("window", "Focus Up", "Move focus to upper window")
        if 'direction = "down"' in al: return ("window", "Focus Down", "Move focus to lower window")
        if 'workspace = "e+1"' in al: return ("window", "Next Workspace", "Switch to workspace e+1")
        if 'workspace = "e-1"' in al: return ("window", "Previous Workspace", "Switch to workspace e-1")
        if "hyprshutdown" in c: return ("window", "Exit Hyprland", "Shutdown or exit Hyprland session")
        return ("window", "Window Action", al)
    if "wpctl" in c or "playerctl" in c:
        if "DEFAULT_AUDIO_SINK" in c: return ("command", "Mute Audio Output", c)
        if "DEFAULT_AUDIO_SOURCE" in c: return ("command", "Mute Microphone", c)
        if "playerctl next" in c: return ("command", "Media: Next Track", c)
        if "playerctl previous" in c: return ("command", "Media: Previous Track", c)
        if "playerctl play-pause" in c: return ("command", "Media: Play / Pause", c)
    return ("command", c if c else al, c if c else al)

groups = {}
order = []
in_for = False

for raw_line in txt.splitlines():
    line = raw_line.strip()
    if not line or line.startswith("--"):
        continue
    if line.startswith("for ") and line.endswith("do"):
        in_for = True
        continue
    if in_for:
        if line == "end":
            in_for = False
        continue
    if not line.startswith("hl.bind("):
        continue
    # find balanced outer parens
    start = line.find("(")
    depth = 0
    in_q = None
    esc = False
    end = -1
    for idx in range(start, len(line)):
        ch = line[idx]
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
    args = split_lua_args(line[start+1:end])
    if len(args) < 2:
        continue
    combo_str = resolve_key(args[0])
    if "mouse:" in combo_str:
        continue
    action_lua = args[1].strip()
    opts_lua = args[2].strip() if len(args) >= 3 else ""
    cmd = extract_exec_cmd(action_lua)
    cat, title, subtitle = classify(action_lua, cmd)
    app_id = ""
    if cmd and cmd.startswith("gtk-launch "):
        app_id = cmd[len("gtk-launch "):].strip().strip('"').strip("'")
    combo_obj = {
        "combo": combo_str,
        "opts": opts_lua,
        "release": ("release = true" in opts_lua),
        "locked": ("locked = true" in opts_lua),
        "repeating": ("repeating = true" in opts_lua)
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
            "combos": [combo_obj],
            "readOnly": False
        }
        order.append(action_lua)
    else:
        groups[action_lua]["combos"].append(combo_obj)

res = [groups[k] for k in order]
# Append read-only summary cards for workspace loop & mouse drag/resize
res.append({
    "id": "builtin_ws_loop",
    "category": "window",
    "title": "Workspaces 1–10 (Focus & Move)",
    "subtitle": "Built-in Lua loop in binds.lua (SUPER + 1..0 / SUPER + SHIFT + 1..0)",
    "actionType": "window",
    "actionLua": "",
    "command": "",
    "appId": "",
    "combos": [{"combo": "SUPER + 1..0", "opts": ""}, {"combo": "SUPER + SHIFT + 1..0", "opts": ""}],
    "readOnly": True
})
res.append({
    "id": "builtin_mouse_drag",
    "category": "window",
    "title": "Mouse Drag & Resize",
    "subtitle": "Hold SUPER + Left/Right Click to move or resize windows",
    "actionType": "window",
    "actionLua": "",
    "command": "",
    "appId": "",
    "combos": [{"combo": "SUPER + LMB", "opts": ""}, {"combo": "SUPER + RMB", "opts": ""}],
    "readOnly": True
})
print(json.dumps(res))
`, root.shellDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                try {
                    const parsed = JSON.parse(this.text);
                    if (Array.isArray(parsed)) {
                        root.binds = parsed;
                        root.recomputeCounts(parsed);
                    }
                } catch (e) {
                    root.setTransientStatus("Failed to parse binds.lua", false);
                }
            }
        }
    }

    Process {
        id: writeProc
        property string payloadJson: "[]"
        property string pendingStatus: "Saved & Reloaded"
        command: ["python3", "-c", `
import os, sys, json

binds = json.loads(sys.argv[1])
binds_path = os.path.expanduser("~/.config/hypr/config/binds.lua")

def fmt_key(combo):
    c = combo.strip()
    if c.startswith("SUPER + "):
        return 'mainMod .. " + ' + c[len("SUPER + "):].replace('"', '\\\\"') + '"'
    return '"' + c.replace('"', '\\\\"') + '"'

cat_titles = [
    ("island", "Paithosh Dynamic Island & Shell IPC"),
    ("screenshot", "Screenshot & Capture"),
    ("apps", "Applications"),
    ("window", "Window & Workspace Management"),
    ("command", "Custom Commands & Media")
]

fallback_shell = (sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else os.path.expanduser("~/.config/paithosh/shell")).replace("\\\\", "\\\\\\\\").replace('"', '\\\\"')

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
    'local mainMod  = "SUPER"',
    ""
]

for cat_key, cat_header in cat_titles:
    cat_items = [b for b in binds if not b.get("readOnly") and b.get("category") == cat_key]
    if not cat_items:
        continue
    lines.append(f"-- {cat_header}")
    for b in cat_items:
        action_lua = b.get("actionLua", "").strip()
        if not action_lua:
            continue
        for c in b.get("combos", []):
            k_expr = fmt_key(c.get("combo", ""))
            opts = c.get("opts", "").strip()
            if opts:
                lines.append(f"hl.bind({k_expr}, {action_lua}, {opts})")
            else:
                lines.append(f"hl.bind({k_expr}, {action_lua})")
    lines.append("")

lines.extend([
    "-- Workspaces 1-10",
    "for i = 1, 10 do",
    "    local key = tostring(i % 10)",
    '    hl.bind(mainMod .. " + " .. key,          hl.dsp.focus({ workspace = i }))',
    '    hl.bind(mainMod .. " + SHIFT + " .. key,  hl.dsp.window.move({ workspace = i }))',
    "end",
    "",
    "-- Mouse drag & resize",
    'hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })',
    'hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })',
    ""
])

os.makedirs(os.path.dirname(binds_path), exist_ok=True)
with open(binds_path, "w", encoding="utf-8") as f:
    f.write("\\n".join(lines))
print("ok")
`, writeProc.payloadJson, root.shellDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.reloadHyprland();
                if (writeProc.pendingStatus) {
                    root.setTransientStatus(writeProc.pendingStatus + " ✓", true);
                }
            }
        }
    }
}
