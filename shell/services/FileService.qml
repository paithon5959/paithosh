pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string homeDir: Quickshell.env("HOME") || "/tmp"
    readonly property string trashDir: homeDir + "/.local/share/Trash/files"
    readonly property string statePath: homeDir + "/.config/paithosh/files-state.json"

    // Shared & Persistent UI/Manager State (synced between Island Files, Detached Files & Picker)
    property var starredPaths: []
    property var clipboardPaths: []
    property string clipboardMode: "" // "" | "copy" | "cut"
    property string lastPath: homeDir
    property bool prefListView: false
    property bool prefShowHidden: false
    property string prefSortBy: "name" // "name" | "mtime" | "size" | "type"
    property bool prefSortAsc: true
    property bool _stateLoaded: false

    property var resolvedPlaces: [
        { key: "Home", label: "Home", icon: "home", path: homeDir },
        { key: "Documents", label: "Documents", icon: "document", path: homeDir + "/Documents" },
        { key: "Downloads", label: "Downloads", icon: "download", path: homeDir + "/Downloads" },
        { key: "Pictures", label: "Pictures", icon: "image", path: homeDir + "/Pictures" },
        { key: "Music", label: "Music", icon: "music", path: homeDir + "/Music" },
        { key: "Projects", label: "Projects", icon: "code", path: homeDir + "/Projects" },
        { key: "Trash", label: "Trash", icon: "trash", path: trashDir }
    ]

    Component {
        id: procComp
        Process {
            id: proc
            property var cb: null
            property string outBuf: ""
            property string errBuf: ""

            stdout: StdioCollector {
                onStreamFinished: proc.outBuf = text
            }
            stderr: StdioCollector {
                onStreamFinished: proc.errBuf = text
            }
            onExited: (exitCode, exitStatus) => {
                if (cb) cb(exitCode === 0, outBuf, errBuf, exitCode);
                destroy();
            }
        }
    }

    Timer {
        id: saveStateTimer
        interval: 180
        repeat: false
        onTriggered: root.writeStateNow()
    }

    Component.onCompleted: {
        loadState();
        probePlaces();
    }

    function runCmd(cmdArray, cb) {
        procComp.createObject(root, {
            command: cmdArray,
            cb: cb || null,
            running: true
        });
    }

    function loadState() {
        runCmd(["sh", "-c", "cat \"$1\" 2>/dev/null || true", "sh", statePath], (ok, out) => {
            try {
                const raw = (out || "").trim();
                if (raw !== "") {
                    const obj = JSON.parse(raw);
                    if (Array.isArray(obj.starredPaths)) starredPaths = obj.starredPaths.filter(p => typeof p === "string" && p !== "");
                    if (typeof obj.prefListView === "boolean") prefListView = obj.prefListView;
                    if (typeof obj.prefShowHidden === "boolean") prefShowHidden = obj.prefShowHidden;
                    if (typeof obj.prefSortBy === "string") prefSortBy = obj.prefSortBy;
                    if (typeof obj.prefSortAsc === "boolean") prefSortAsc = obj.prefSortAsc;
                }
            } catch (e) {}
            _stateLoaded = true;
        });
    }

    function saveState() {
        if (!_stateLoaded) return;
        saveStateTimer.restart();
    }

    function writeStateNow() {
        const data = JSON.stringify({
            starredPaths: starredPaths || [],
            prefListView: prefListView,
            prefShowHidden: prefShowHidden,
            prefSortBy: prefSortBy,
            prefSortAsc: prefSortAsc
        }, null, 2);
        runCmd([
            "python3", "-c",
            "import os,sys,tempfile; p=sys.argv[1]; d=os.path.dirname(p); os.makedirs(d, exist_ok=True); fd,tp=tempfile.mkstemp(dir=d); os.write(fd, sys.argv[2].encode()); os.close(fd); os.replace(tp, p)",
            statePath, data
        ], null);
    }

    function probePlaces() {
        const py = `
import json, os, re

home = os.path.expanduser("~")
user_dirs = {}
cfg = os.path.join(home, ".config", "user-dirs.dirs")
if os.path.isfile(cfg):
    try:
        with open(cfg, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.match(r'^\\s*(XDG_\\w+_DIR)\\s*=\\s*"(.*)"\\s*$', line)
                if m:
                    val = m.group(2).replace("$HOME", home)
                    user_dirs[m.group(1)] = os.path.expanduser(val)
    except OSError:
        pass

candidates = [
    ("Home", "Home", "home", home, True),
    ("Desktop", "Desktop", "folder", user_dirs.get("XDG_DESKTOP_DIR", os.path.join(home, "Desktop")), False),
    ("Documents", "Documents", "document", user_dirs.get("XDG_DOCUMENTS_DIR", os.path.join(home, "Documents")), False),
    ("Downloads", "Downloads", "download", user_dirs.get("XDG_DOWNLOAD_DIR", os.path.join(home, "Downloads")), False),
    ("Pictures", "Pictures", "image", user_dirs.get("XDG_PICTURES_DIR", os.path.join(home, "Pictures")), False),
    ("Music", "Music", "music", user_dirs.get("XDG_MUSIC_DIR", os.path.join(home, "Music")), False),
    ("Videos", "Videos", "video", user_dirs.get("XDG_VIDEOS_DIR", os.path.join(home, "Videos")), False),
    ("Projects", "Projects", "code", user_dirs.get("XDG_PROJECTS_DIR", os.path.join(home, "Projects")), False),
    ("Trash", "Trash", "trash", os.path.join(home, ".local", "share", "Trash", "files"), True),
]

out = []
seen = set()
for key, label, icon, path, force in candidates:
    norm = os.path.normpath(path)
    if norm in seen and key != "Trash":
        continue
    if force or os.path.isdir(norm):
        seen.add(norm)
        out.append({"key": key, "label": label, "icon": icon, "path": norm})

print(json.dumps(out))
`;
        runCmd(["python3", "-c", py], (ok, out) => {
            if (!ok || !out) return;
            try {
                const parsed = JSON.parse(out.trim());
                if (Array.isArray(parsed) && parsed.length > 0) {
                    resolvedPlaces = parsed;
                }
            } catch (e) {}
        });
    }

    function isStarred(path) {
        return starredPaths.indexOf(path) !== -1;
    }

    function toggleStar(path) {
        if (!path) return;
        const next = starredPaths.slice();
        const idx = next.indexOf(path);
        if (idx === -1) next.push(path);
        else next.splice(idx, 1);
        starredPaths = next;
        saveState();
    }

    function setClipboard(paths, mode) {
        clipboardPaths = (paths || []).slice();
        clipboardMode = clipboardPaths.length > 0 ? (mode || "copy") : "";
    }

    function clearClipboard() {
        clipboardPaths = [];
        clipboardMode = "";
    }

    function setViewPref(listView) {
        prefListView = Boolean(listView);
        saveState();
    }

    function setHiddenPref(hidden) {
        prefShowHidden = Boolean(hidden);
        saveState();
    }

    function setSortPref(by, asc) {
        prefSortBy = by || "name";
        prefSortAsc = Boolean(asc);
        saveState();
    }

    function formatSize(bytes) {
        if (isNaN(bytes) || bytes < 0) return "";
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
        if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + " MB";
        return (bytes / 1073741824).toFixed(2) + " GB";
    }

    function formatDate(epochSec) {
        if (!epochSec || isNaN(epochSec) || epochSec <= 0) return "";
        const d = new Date(epochSec * 1000);
        const now = new Date();
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        const yestStart = todayStart - 86400000;
        const t = d.getTime();
        if (t >= todayStart) return "Today " + Qt.formatTime(d, "hh:mm");
        if (t >= yestStart) return "Yesterday";
        if (d.getFullYear() === now.getFullYear()) return Qt.formatDate(d, "MMM d");
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function classifyType(name, rawType) {
        if (rawType === "d") return "folder";
        const lower = (name || "").toLowerCase();
        if (/\.(pak|zip|tar|tar\.gz|tgz|tar\.xz|txz|tar\.bz2|7z|rar|zst|osz)$/.test(lower)) return "archive";
        if (/\.(png|jpg|jpeg|webp|gif|svg|bmp|ico|avif|tiff|heic)$/.test(lower)) return "image";
        if (/\.(mp4|mkv|webm|mov|avi|flv|wmv|m4v)$/.test(lower)) return "video";
        if (/\.(mp3|flac|wav|ogg|m4a|opus|aac)$/.test(lower)) return "music";
        if (/\.(pdf|doc|docx|odt|rtf|txt|csv|xls|xlsx|ppt|pptx|epub)$/.test(lower)) return "document";
        if (/\.(qml|js|ts|tsx|jsx|py|sh|zsh|bash|conf|cfg|ini|css|scss|html|xml|json|md|rs|go|c|cpp|h|hpp|java|kt|yaml|yml|toml|lua|sql|nix|dockerfile)$/.test(lower)) return "code";
        return "file";
    }

    function iconForType(type) {
        if (type === "folder") return "folder";
        if (type === "archive") return "archive";
        if (type === "image") return "image";
        if (type === "video") return "video";
        if (type === "music") return "music";
        if (type === "document") return "document";
        if (type === "code") return "code";
        return "file";
    }

    function sortItems(items, sortBy, sortAsc) {
        if (!items || items.length === 0) return [];
        const by = sortBy || "name";
        const dir = (sortAsc === false) ? -1 : 1;
        const arr = items.slice();
        arr.sort((a, b) => {
            const aDir = a.type === "folder" ? 0 : 1;
            const bDir = b.type === "folder" ? 0 : 1;
            if (aDir !== bDir) return aDir - bDir;
            let cmp = 0;
            if (by === "mtime") {
                cmp = (a.mtime || 0) - (b.mtime || 0);
            } else if (by === "size") {
                cmp = (a.size || 0) - (b.size || 0);
            } else if (by === "type") {
                cmp = (a.type || "").localeCompare(b.type || "");
            }
            if (cmp === 0) {
                cmp = (a.name || "").localeCompare(b.name || "", undefined, { numeric: true, sensitivity: "base" });
            }
            return cmp * dir;
        });
        return arr;
    }

    function listDir(path, showHidden, cb) {
        const target = path || homeDir;
        if (target === trashDir) {
            runCmd([
                "sh", "-c",
                "if [ ! -d \"$1\" ]; then exit 0; fi; find -L \"$1\" -mindepth 1 -maxdepth 1 -printf '%y\\t%s\\t%T@\\t%f\\n' 2>/dev/null || true",
                "sh", target
            ], (ok, out, err) => {
                _parseListDirOutput(target, showHidden, true, out, err, cb);
            });
            return;
        }
        runCmd([
            "sh", "-c",
            "if [ ! -d \"$1\" ]; then echo 'Directory not found' >&2; exit 1; fi; if [ ! -r \"$1\" ]; then echo 'Permission denied' >&2; exit 1; fi; find -L \"$1\" -mindepth 1 -maxdepth 1 -printf '%y\\t%s\\t%T@\\t%f\\n' 2>/dev/null || true",
            "sh", target
        ], (ok, out, err) => {
            _parseListDirOutput(target, showHidden, ok, out, err, cb);
        });
    }

    function _parseListDirOutput(target, showHidden, ok, out, err, cb) {
        if (!ok) {
            if (cb) cb(false, [], (err || "").trim() || "Failed to read directory");
            return;
        }
        const items = [];
        const lines = (out || "").split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i];
            if (!line) continue;
            const parts = line.split("\t");
            if (parts.length < 4) continue;
            const rawType = parts[0];
            const sizeNum = parseInt(parts[1], 10);
            const mtimeNum = parseFloat(parts[2]) || 0;
            const name = parts.slice(3).join("\t");
            if (!name) continue;
            if (!showHidden && name.startsWith(".")) continue;
            const type = classifyType(name, rawType);
            const fullPath = (target === "/" ? "" : target) + "/" + name;
            items.push({
                name: name,
                path: fullPath,
                parentDir: target,
                type: type,
                size: isNaN(sizeNum) ? 0 : sizeNum,
                mtime: mtimeNum,
                modifiedText: formatDate(mtimeNum),
                isHidden: name.startsWith("."),
                meta: type === "folder" ? "Folder" : formatSize(sizeNum)
            });
        }
        if (cb) cb(true, items, "");
    }

    function getDiskUsage(path, cb) {
        const target = path || homeDir;
        runCmd([
            "sh", "-c",
            "df -BG --output=size,avail \"$1\" 2>/dev/null | tail -n1",
            "sh", target
        ], (ok, out) => {
            const parts = (out || "").trim().split(/\s+/);
            if (ok && parts.length >= 2) {
                if (cb) cb(parts[0].replace("G", " GB") + " • " + parts[1].replace("G", " GB") + " free");
            } else {
                if (cb) cb("");
            }
        });
    }

    function openFile(path) {
        if (!path) return;
        Quickshell.execDetached(["xdg-open", path]);
    }

    function openTerminal(dirPath) {
        const target = dirPath || homeDir;
        Quickshell.execDetached([
            "sh", "-c",
            "command -v kitty >/dev/null && exec kitty --directory \"$1\"; command -v konsole >/dev/null && exec konsole --workdir \"$1\"; exec xdg-open \"$1\"",
            "sh", target
        ]);
    }

    function createFile(dirPath, name, cb) {
        const clean = String(name || "").trim();
        if (!clean || clean === "." || clean === ".." || clean.indexOf("/") !== -1) {
            if (cb) cb(false, "Invalid file name");
            return;
        }
        const full = (dirPath === "/" ? "" : dirPath) + "/" + clean;
        runCmd([
            "sh", "-c",
            "if [ -e \"$1\" ]; then echo 'An item with that name already exists' >&2; exit 1; fi; touch -- \"$1\"",
            "sh", full
        ], (ok, out, err) => {
            if (cb) cb(ok, (err || "").trim());
        });
    }

    function listRecent(cb) {
        runCmd([
            "sh", "-c",
            "find \"$HOME\" -maxdepth 3 -type f -mtime -7 -not -path '*/.*' -printf '%T@\\t%s\\t%p\\n' 2>/dev/null | sort -nr | head -n 50"
        ], (ok, out) => {
            const items = [];
            const lines = (out || "").split("\n");
            for (let i = 0; i < lines.length; ++i) {
                const line = lines[i];
                if (!line) continue;
                const parts = line.split("\t");
                if (parts.length < 3) continue;
                const mtimeNum = parseFloat(parts[0]) || 0;
                const sizeNum = parseInt(parts[1], 10);
                const fullPath = parts.slice(2).join("\t");
                const slash = fullPath.lastIndexOf("/");
                const name = slash >= 0 ? fullPath.slice(slash + 1) : fullPath;
                const parent = slash > 0 ? fullPath.slice(0, slash) : "/";
                if (!name) continue;
                const type = classifyType(name, "f");
                items.push({
                    name: name,
                    path: fullPath,
                    parentDir: parent,
                    type: type,
                    size: isNaN(sizeNum) ? 0 : sizeNum,
                    mtime: mtimeNum,
                    modifiedText: formatDate(mtimeNum),
                    isHidden: name.startsWith("."),
                    meta: formatSize(sizeNum)
                });
            }
            if (cb) cb(true, items, "");
        });
    }

    function searchFiles(dirPath, query, showHidden, cb) {
        const target = dirPath || homeDir;
        const q = String(query || "").trim();
        if (!q) {
            listDir(target, showHidden, cb);
            return;
        }
        const py = `
import os, stat, sys

root_dir = sys.argv[1]
q = sys.argv[2].lower()
show_hidden = sys.argv[3] == "1"
max_depth = 4
limit = 150
count = 0

if not os.path.isdir(root_dir):
    sys.stderr.write("Directory not found\\n")
    sys.exit(1)

root_norm = root_dir.rstrip("/") or "/"

def walk(cur, depth):
    global count
    if depth > max_depth or count >= limit:
        return
    try:
        entries = list(os.scandir(cur))
    except OSError:
        return
    sub_dirs = []
    for entry in entries:
        if count >= limit:
            break
        name = entry.name
        if not show_hidden and name.startswith("."):
            continue
        try:
            st = entry.stat(follow_symlinks=True)
        except OSError:
            continue
        is_dir = stat.S_ISDIR(st.st_mode)
        if q in name.lower():
            tchar = "d" if is_dir else "f"
            print(f"{tchar}\\t{st.st_size}\\t{st.st_mtime:.3f}\\t{entry.path}")
            count += 1
        if is_dir and depth < max_depth:
            sub_dirs.append(entry.path)
    for sd in sub_dirs:
        if count >= limit:
            break
        walk(sd, depth + 1)

walk(root_dir, 1)
`;
        runCmd(["python3", "-c", py, target, q, showHidden ? "1" : "0"], (ok, out, err) => {
            if (!ok) {
                if (cb) cb(false, [], (err || "").trim() || "Search failed");
                return;
            }
            const items = [];
            const lines = (out || "").split("\n");
            for (let i = 0; i < lines.length; ++i) {
                const line = lines[i];
                if (!line) continue;
                const parts = line.split("\t");
                if (parts.length < 4) continue;
                const rawType = parts[0];
                const sizeNum = parseInt(parts[1], 10);
                const mtimeNum = parseFloat(parts[2]) || 0;
                const fullPath = parts.slice(3).join("\t");
                const slash = fullPath.lastIndexOf("/");
                const name = slash >= 0 ? fullPath.slice(slash + 1) : fullPath;
                const parent = slash > 0 ? fullPath.slice(0, slash) : "/";
                if (!name) continue;
                const type = classifyType(name, rawType);
                let relParent = "";
                if (parent !== target) {
                    relParent = parent.startsWith(target + "/") ? parent.slice(target.length + 1) : parent;
                }
                const baseMeta = type === "folder" ? "Folder" : formatSize(sizeNum);
                items.push({
                    name: name,
                    path: fullPath,
                    parentDir: parent,
                    relPath: relParent,
                    type: type,
                    size: isNaN(sizeNum) ? 0 : sizeNum,
                    mtime: mtimeNum,
                    modifiedText: formatDate(mtimeNum),
                    isHidden: name.startsWith("."),
                    meta: relParent !== "" ? (relParent + " • " + baseMeta) : baseMeta
                });
            }
            if (cb) cb(true, items, "");
        });
    }

    function getProperties(path, cb) {
        if (!path) return;
        runCmd([
            "sh", "-c",
            "stat --printf='%A\\t%U:%G\\t%s\\t%y\\t%F\\n' -- \"$1\" 2>/dev/null && if [ -d \"$1\" ]; then find -L \"$1\" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l; fi",
            "sh", path
        ], (ok, out, err) => {
            if (!ok || !out.trim()) {
                if (cb) cb(false, null, (err || "").trim() || "stat failed");
                return;
            }
            const lines = out.trim().split("\n");
            const parts = lines[0].split("\t");
            const perms = parts[0] || "";
            const isDir = perms.startsWith("d");
            const rawBytes = parseInt(parts[2] || "0", 10);
            const itemCount = lines.length > 1 ? parseInt(lines[1].trim(), 10) : -1;
            const sizeLabel = isDir && !isNaN(itemCount) && itemCount >= 0
                ? (itemCount + (itemCount === 1 ? " item" : " items"))
                : formatSize(rawBytes);
            if (cb) cb(true, {
                permissions: perms,
                owner: parts[1] || "",
                size: sizeLabel,
                modified: (parts[3] || "").split(".")[0],
                kind: parts[4] || (isDir ? "directory" : "regular file"),
                isDir: isDir,
                executable: !isDir && perms.indexOf("x") !== -1
            }, "");
        });
    }

    function setExecutable(path, enabled, cb) {
        if (!path) return;
        runCmd(["chmod", enabled ? "+x" : "-x", "--", path], (ok, out, err) => {
            if (cb) cb(ok, (err || "").trim());
        });
    }

    function copyToClipboard(text) {
        if (!text) return;
        Quickshell.execDetached([
            "sh", "-c",
            "if command -v wl-copy >/dev/null; then printf '%s' \"$1\" | wl-copy; elif command -v xclip >/dev/null; then printf '%s' \"$1\" | xclip -selection clipboard; fi",
            "sh", text
        ]);
    }

    function measureSize(paths, cb) {
        if (!paths || paths.length === 0) {
            if (cb) cb(0);
            return;
        }
        const cmd = ["sh", "-c", "du -sb -- \"$@\" 2>/dev/null | awk '{s+=$1} END {print s+0}'", "sh"].concat(paths);
        runCmd(cmd, (ok, out) => {
            const bytes = parseInt((out || "").trim(), 10);
            if (cb) cb(isNaN(bytes) ? 0 : bytes);
        });
    }

    function dirSize(path, cb) {
        if (!path) {
            if (cb) cb(0);
            return;
        }
        runCmd(["sh", "-c", "du -sb -- \"$1\" 2>/dev/null | awk '{print $1+0}'", "sh", path], (ok, out) => {
            const bytes = parseInt((out || "").trim(), 10);
            if (cb) cb(isNaN(bytes) ? 0 : bytes);
        });
    }

    function createFolder(dirPath, name, cb) {
        const clean = String(name || "").trim();
        if (!clean || clean === "." || clean === ".." || clean.indexOf("/") !== -1) {
            if (cb) cb(false, "Invalid folder name");
            return;
        }
        const full = (dirPath === "/" ? "" : dirPath) + "/" + clean;
        runCmd([
            "sh", "-c",
            "if [ -e \"$1\" ]; then echo 'An item with that name already exists' >&2; exit 1; fi; mkdir -p -- \"$1\"",
            "sh", full
        ], (ok, out, err) => {
            if (cb) cb(ok, (err || "").trim());
        });
    }

    function renameItem(fullPath, newName, cb) {
        const clean = String(newName || "").trim();
        if (!fullPath || !clean || clean === "." || clean === ".." || clean.indexOf("/") !== -1) {
            if (cb) cb(false, "Invalid name");
            return;
        }
        const slash = fullPath.lastIndexOf("/");
        const parent = slash > 0 ? fullPath.slice(0, slash) : "/";
        const oldName = slash >= 0 ? fullPath.slice(slash + 1) : fullPath;
        if (clean === oldName) {
            if (cb) cb(true, "");
            return;
        }
        const dest = (parent === "/" ? "" : parent) + "/" + clean;
        runCmd([
            "sh", "-c",
            "if [ -e \"$2\" ]; then echo 'An item with that name already exists' >&2; exit 1; fi; mv -- \"$1\" \"$2\"",
            "sh", fullPath, dest
        ], (ok, out, err) => {
            if (cb) cb(ok, (err || "").trim());
        });
    }

    function copyItems(paths, destDir, cb) {
        if (!paths || paths.length === 0) return;
        const py = `
import os, shutil, sys

dest_dir = os.path.abspath(sys.argv[1])
srcs = sys.argv[2:]

if not os.path.isdir(dest_dir):
    sys.stderr.write("Destination directory does not exist\\n")
    sys.exit(1)

def unique_target(d, name, is_dir):
    cand = os.path.join(d, name)
    if not os.path.exists(cand):
        return cand
    if is_dir or "." not in name or name.startswith(".") and name.count(".") == 1:
        stem, ext = name, ""
    else:
        stem, ext = os.path.splitext(name)
    idx = 1
    while True:
        suffix = " (copy)" if idx == 1 else f" (copy {idx})"
        cand = os.path.join(d, f"{stem}{suffix}{ext}")
        if not os.path.exists(cand):
            return cand
        idx += 1

for s in srcs:
    src = os.path.abspath(s)
    if not os.path.lexists(src):
        continue
    is_dir = os.path.isdir(src) and not os.path.islink(src)
    if is_dir:
        real_s = os.path.realpath(src)
        real_d = os.path.realpath(dest_dir)
        if real_d == real_s or real_d.startswith(real_s + os.sep):
            sys.stderr.write(f"Cannot copy '{os.path.basename(src)}' into itself\\n")
            sys.exit(1)
    dst = unique_target(dest_dir, os.path.basename(src), is_dir)
    if is_dir:
        shutil.copytree(src, dst, symlinks=True)
    else:
        shutil.copy2(src, dst, follow_symlinks=False)
`;
        runCmd(["python3", "-c", py, destDir].concat(paths), (ok, out, err) => {
            if (cb) cb(ok, (err || "").trim());
        });
    }

    function moveItems(paths, destDir, cb) {
        if (!paths || paths.length === 0) return;
        const py = `
import os, shutil, sys

dest_dir = os.path.abspath(sys.argv[1])
srcs = sys.argv[2:]

if not os.path.isdir(dest_dir):
    sys.stderr.write("Destination directory does not exist\\n")
    sys.exit(1)

def unique_target(d, name, is_dir):
    cand = os.path.join(d, name)
    if not os.path.exists(cand):
        return cand
    if is_dir or "." not in name or (name.startswith(".") and name.count(".") == 1):
        stem, ext = name, ""
    else:
        stem, ext = os.path.splitext(name)
    idx = 1
    while True:
        suffix = " (moved)" if idx == 1 else f" (moved {idx})"
        cand = os.path.join(d, f"{stem}{suffix}{ext}")
        if not os.path.exists(cand):
            return cand
        idx += 1

for s in srcs:
    src = os.path.abspath(s)
    if not os.path.lexists(src):
        continue
    if os.path.dirname(src) == dest_dir:
        continue
    is_dir = os.path.isdir(src) and not os.path.islink(src)
    if is_dir:
        real_s = os.path.realpath(src)
        real_d = os.path.realpath(dest_dir)
        if real_d == real_s or real_d.startswith(real_s + os.sep):
            sys.stderr.write(f"Cannot move '{os.path.basename(src)}' into itself\\n")
            sys.exit(1)
    dst = unique_target(dest_dir, os.path.basename(src), is_dir)
    shutil.move(src, dst)
`;
        runCmd(["python3", "-c", py, destDir].concat(paths), (ok, out, err) => {
            if (cb) cb(ok, (err || "").trim());
        });
    }

    function deleteItems(paths, permanent, cb) {
        if (!paths || paths.length === 0) return;
        if (permanent) {
            runCmd(["rm", "-rf", "--"].concat(paths), (ok, out, err) => {
                if (cb) cb(ok, (err || "").trim());
            });
            return;
        }
        const py = `
import datetime, os, shutil, sys, urllib.parse

trash_base = os.path.expanduser("~/.local/share/Trash")
files_dir = os.path.join(trash_base, "files")
info_dir = os.path.join(trash_base, "info")
os.makedirs(files_dir, exist_ok=True)
os.makedirs(info_dir, exist_ok=True)

now_str = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")

for raw in sys.argv[1:]:
    src = os.path.abspath(raw)
    if not os.path.lexists(src):
        continue
    base = os.path.basename(src)
    if not base:
        continue
    tname = base
    n = 2
    while os.path.lexists(os.path.join(files_dir, tname)) or os.path.lexists(os.path.join(info_dir, tname + ".trashinfo")):
        tname = f"{base}.{n}"
        n += 1
    info_path = os.path.join(info_dir, tname + ".trashinfo")
    quoted = urllib.parse.quote(src, safe="/")
    with open(info_path, "w", encoding="utf-8") as f:
        f.write(f"[Trash Info]\\nPath={quoted}\\nDeletionDate={now_str}\\n")
    shutil.move(src, os.path.join(files_dir, tname))
`;
        runCmd(["python3", "-c", py].concat(paths), (ok, out, err) => {
            if (cb) cb(ok, (err || "").trim());
        });
    }

    function restoreFromTrash(paths, cb) {
        if (!paths || paths.length === 0) return;
        const py = `
import os, shutil, sys, urllib.parse

trash_base = os.path.expanduser("~/.local/share/Trash")
files_dir = os.path.join(trash_base, "files")
info_dir = os.path.join(trash_base, "info")

def unique_dest(path):
    if not os.path.lexists(path):
        return path
    d = os.path.dirname(path)
    name = os.path.basename(path)
    if os.path.isdir(path) or "." not in name:
        stem, ext = name, ""
    else:
        stem, ext = os.path.splitext(name)
    i = 1
    while True:
        sfx = " (restored)" if i == 1 else f" (restored {i})"
        cand = os.path.join(d, f"{stem}{sfx}{ext}")
        if not os.path.lexists(cand):
            return cand
        i += 1

for p in sys.argv[1:]:
    base = os.path.basename(p.rstrip("/"))
    src = os.path.join(files_dir, base)
    info = os.path.join(info_dir, base + ".trashinfo")
    if not os.path.lexists(src):
        continue
    orig = None
    if os.path.isfile(info):
        with open(info, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith("Path="):
                    orig = urllib.parse.unquote(line[5:].strip())
                    break
    if not orig:
        orig = os.path.join(os.path.expanduser("~"), base)
    if not os.path.isabs(orig):
        orig = os.path.join(os.path.expanduser("~"), orig)
    os.makedirs(os.path.dirname(orig), exist_ok=True)
    dst = unique_dest(orig)
    shutil.move(src, dst)
    if os.path.exists(info):
        os.remove(info)
`;
        runCmd(["python3", "-c", py].concat(paths), (ok, out, err) => {
            if (cb) cb(ok, (err || "").trim());
        });
    }

    function emptyTrash(cb) {
        const py = `
import os, shutil

trash_base = os.path.expanduser("~/.local/share/Trash")
for sub in ("files", "info"):
    d = os.path.join(trash_base, sub)
    if os.path.isdir(d):
        for entry in os.listdir(d):
            fp = os.path.join(d, entry)
            if os.path.isdir(fp) and not os.path.islink(fp):
                shutil.rmtree(fp, ignore_errors=True)
            else:
                try:
                    os.unlink(fp)
                except OSError:
                    pass
ds = os.path.join(trash_base, "directorysizes")
if os.path.isfile(ds):
    try:
        os.unlink(ds)
    except OSError:
        pass
`;
        runCmd(["python3", "-c", py], (ok, out, err) => {
            if (cb) cb(ok, (err || "").trim());
        });
    }

    function inspectArchive(archivePath, cb) {
        const lower = archivePath.toLowerCase();
        let cmd;
        if (lower.endsWith(".zip") || lower.endsWith(".osz") || lower.endsWith(".pak")) {
            cmd = ["unzip", "-Z1", archivePath];
        } else if (lower.endsWith(".7z")) {
            cmd = ["sh", "-c", "7z l -ba \"$1\" | awk '{print $NF}'", "sh", archivePath];
        } else {
            cmd = ["tar", "-tf", archivePath];
        }
        runCmd(cmd, (ok, out, err) => {
            if (!ok) {
                if (cb) cb(false, [], (err || "").trim() || "Cannot read archive");
                return;
            }
            const lines = (out || "").trim().split("\n");
            const entries = [];
            for (let i = 0; i < lines.length; ++i) {
                const entryName = lines[i].trim();
                if (!entryName) continue;
                const isDir = entryName.endsWith("/");
                entries.push({
                    name: entryName,
                    path: "",
                    type: isDir ? "folder" : classifyType(entryName, "f"),
                    meta: "Compressed"
                });
            }
            if (cb) cb(true, entries, "");
        });
    }

    function createArchive(paths, destDir, zipName, cb) {
        if (!paths || paths.length === 0) return;
        const cleanName = String(zipName || "Archive.zip").trim();
        const finalName = cleanName.toLowerCase().endsWith(".zip") ? cleanName : (cleanName + ".zip");
        const outPath = (destDir === "/" ? "" : destDir) + "/" + finalName;
        const py = `
import os, sys, zipfile

out_zip = sys.argv[1]
srcs = sys.argv[2:]

with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for raw in srcs:
        s = os.path.abspath(raw)
        if not os.path.lexists(s):
            continue
        base_parent = os.path.dirname(s)
        if os.path.isdir(s) and not os.path.islink(s):
            for root_dir, dirs, files in os.walk(s):
                rel_dir = os.path.relpath(root_dir, base_parent)
                if not dirs and not files:
                    zf.write(root_dir, rel_dir)
                for fn in files:
                    fp = os.path.join(root_dir, fn)
                    zf.write(fp, os.path.relpath(fp, base_parent))
        else:
            zf.write(s, os.path.basename(s))
`;
        runCmd(["python3", "-c", py, outPath].concat(paths), (ok, out, err) => {
            if (cb) cb(ok, (err || "").trim());
        });
    }

    function extractArchive(archivePath, destDir, password, cb) {
        const lower = archivePath.toLowerCase();
        const base = archivePath.split("/").pop().replace(/\.(pak|zip|osz|7z|tar\.gz|tgz|tar\.xz|txz|tar\.bz2|tar)$/i, "") || "extracted";
        const outDir = (destDir === "/" ? "" : destDir) + "/" + base;
        let cmd;
        if (lower.endsWith(".zip") || lower.endsWith(".osz") || lower.endsWith(".pak")) {
            if (password && password.length > 0) {
                cmd = ["sh", "-c", "mkdir -p \"$3\" && unzip -o -P \"$2\" \"$1\" -d \"$3\"", "sh", archivePath, password, outDir];
            } else {
                cmd = ["sh", "-c", "mkdir -p \"$2\" && unzip -o -P \"\" \"$1\" -d \"$2\"", "sh", archivePath, outDir];
            }
        } else if (lower.endsWith(".7z")) {
            const pFlag = password ? ("-p" + password) : "-p";
            cmd = ["sh", "-c", "mkdir -p \"$3\" && 7z x -y \"$2\" \"$1\" -o\"$3\"", "sh", archivePath, pFlag, outDir];
        } else {
            cmd = ["sh", "-c", "mkdir -p \"$2\" && tar -xf \"$1\" -C \"$2\"", "sh", archivePath, outDir];
        }
        runCmd(cmd, (ok, out, err) => {
            const errText = (err || out || "").trim();
            const needsPwd = !ok && /password|encrypted|skipping:.*incorrect/i.test(errText);
            if (cb) cb(ok, outDir, errText, needsPwd);
        });
    }
}
