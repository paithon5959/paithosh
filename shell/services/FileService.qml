pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string homeDir: Quickshell.env("HOME") || "/home/paithon"
    readonly property string trashDir: homeDir + "/.local/share/Trash/files"

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

    function runCmd(cmdArray, cb) {
        procComp.createObject(root, {
            command: cmdArray,
            cb: cb || null,
            running: true
        });
    }

    function formatSize(bytes) {
        if (isNaN(bytes) || bytes < 0) return "";
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
        if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + " MB";
        return (bytes / 1073741824).toFixed(2) + " GB";
    }

    function classifyType(name, rawType) {
        if (rawType === "d") return "folder";
        const lower = name.toLowerCase();
        if (/\.(zip|tar|tar\.gz|tgz|tar\.xz|txz|tar\.bz2|7z|rar|zst)$/.test(lower)) return "archive";
        if (/\.(qml|js|ts|py|sh|conf|css|html|json|md|rs|go|c|cpp|h|yaml|yml|toml)$/.test(lower)) return "code";
        if (/\.(mp3|flac|wav|ogg|m4a|opus)$/.test(lower)) return "music";
        return "file";
    }

    function iconForType(type) {
        if (type === "folder") return "folder";
        if (type === "archive") return "archive";
        if (type === "code") return "code";
        if (type === "music") return "music";
        return "file";
    }

    function listDir(path, showHidden, cb) {
        const target = path || homeDir;
        runCmd([
            "sh", "-c",
            "if [ ! -d \"$1\" ]; then echo 'Directory not found' >&2; exit 1; fi; find -L \"$1\" -mindepth 1 -maxdepth 1 -printf '%y\\t%s\\t%T@\\t%f\\n' 2>/dev/null || true",
            "sh", target
        ], (ok, out, err) => {
            if (!ok) {
                if (cb) cb(false, [], err.trim() || "Failed to read directory");
                return;
            }
            const items = [];
            const lines = out.split("\n");
            for (let i = 0; i < lines.length; ++i) {
                const line = lines[i];
                if (!line) continue;
                const parts = line.split("\t");
                if (parts.length < 4) continue;
                const rawType = parts[0];
                const sizeNum = parseInt(parts[1], 10);
                const name = parts.slice(3).join("\t");
                if (!name) continue;
                if (!showHidden && name.startsWith(".")) continue;
                const type = classifyType(name, rawType);
                const fullPath = (target === "/" ? "" : target) + "/" + name;
                items.push({
                    name: name,
                    path: fullPath,
                    type: type,
                    size: sizeNum,
                    meta: type === "folder" ? "Folder" : formatSize(sizeNum)
                });
            }
            items.sort((a, b) => {
                const aDir = a.type === "folder" ? 0 : 1;
                const bDir = b.type === "folder" ? 0 : 1;
                if (aDir !== bDir) return aDir - bDir;
                return a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
            });
            if (cb) cb(true, items, "");
        });
    }

    function getDiskUsage(path, cb) {
        const target = path || homeDir;
        runCmd([
            "sh", "-c",
            "df -BG --output=size,avail \"$1\" 2>/dev/null | tail -n1",
            "sh", target
        ], (ok, out) => {
            const parts = out.trim().split(/\s+/);
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
        if (!clean || clean.indexOf("/") !== -1) {
            if (cb) cb(false, "Invalid file name");
            return;
        }
        const full = (dirPath === "/" ? "" : dirPath) + "/" + clean;
        runCmd(["touch", "--", full], (ok, out, err) => {
            if (cb) cb(ok, err.trim());
        });
    }

    function listRecent(cb) {
        runCmd([
            "sh", "-c",
            "find \"$HOME\" -maxdepth 3 -type f -mtime -7 -not -path '*/.*' -printf '%T@\\t%s\\t%p\\n' 2>/dev/null | sort -nr | head -n 40"
        ], (ok, out, err) => {
            const items = [];
            const lines = out.split("\n");
            for (let i = 0; i < lines.length; ++i) {
                const line = lines[i];
                if (!line) continue;
                const parts = line.split("\t");
                if (parts.length < 3) continue;
                const sizeNum = parseInt(parts[1], 10);
                const fullPath = parts.slice(2).join("\t");
                const name = fullPath.split("/").pop();
                if (!name) continue;
                const type = classifyType(name, "f");
                items.push({
                    name: name,
                    path: fullPath,
                    type: type,
                    size: sizeNum,
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
        runCmd([
            "sh", "-c",
            "find -L \"$1\" -maxdepth 3 -iname \"*$2*\" -printf '%y\\t%s\\t%T@\\t%p\\n' 2>/dev/null | head -n 120",
            "sh", target, q
        ], (ok, out, err) => {
            const items = [];
            const lines = out.split("\n");
            for (let i = 0; i < lines.length; ++i) {
                const line = lines[i];
                if (!line) continue;
                const parts = line.split("\t");
                if (parts.length < 4) continue;
                const rawType = parts[0];
                const sizeNum = parseInt(parts[1], 10);
                const fullPath = parts.slice(3).join("\t");
                if (fullPath === target) continue;
                const name = fullPath.split("/").pop();
                if (!name) continue;
                if (!showHidden && name.startsWith(".")) continue;
                const type = classifyType(name, rawType);
                items.push({
                    name: name,
                    path: fullPath,
                    type: type,
                    size: sizeNum,
                    meta: type === "folder" ? "Folder" : formatSize(sizeNum)
                });
            }
            if (cb) cb(true, items, "");
        });
    }

    function getProperties(path, cb) {
        if (!path) return;
        runCmd([
            "sh", "-c",
            "stat -c '%A\\t%U:%G\\t%s\\t%y\\t%F' -- \"$1\" 2>/dev/null",
            "sh", path
        ], (ok, out, err) => {
            if (!ok || !out.trim()) {
                if (cb) cb(false, null, err.trim() || "stat failed");
                return;
            }
            const parts = out.trim().split("\t");
            const perms = parts[0] || "";
            if (cb) cb(true, {
                permissions: perms,
                owner: parts[1] || "",
                size: formatSize(parseInt(parts[2] || "0", 10)),
                modified: (parts[3] || "").split(".")[0],
                kind: parts[4] || "",
                executable: perms.indexOf("x") !== -1
            }, "");
        });
    }

    function setExecutable(path, enabled, cb) {
        if (!path) return;
        runCmd(["chmod", enabled ? "+x" : "-x", "--", path], (ok, out, err) => {
            if (cb) cb(ok, err.trim());
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
            const bytes = parseInt(out.trim(), 10);
            if (cb) cb(isNaN(bytes) ? 0 : bytes);
        });
    }

    function dirSize(path, cb) {
        if (!path) {
            if (cb) cb(0);
            return;
        }
        runCmd(["sh", "-c", "du -sb -- \"$1\" 2>/dev/null | awk '{print $1+0}'", "sh", path], (ok, out) => {
            const bytes = parseInt(out.trim(), 10);
            if (cb) cb(isNaN(bytes) ? 0 : bytes);
        });
    }

    function createFolder(dirPath, name, cb) {
        const clean = String(name || "").trim();
        if (!clean || clean.indexOf("/") !== -1) {
            if (cb) cb(false, "Invalid folder name");
            return;
        }
        const full = (dirPath === "/" ? "" : dirPath) + "/" + clean;
        runCmd(["mkdir", "-p", "--", full], (ok, out, err) => {
            if (cb) cb(ok, err.trim());
        });
    }

    function renameItem(dirPath, oldName, newName, cb) {
        const clean = String(newName || "").trim();
        if (!clean || clean === oldName || clean.indexOf("/") !== -1) {
            if (cb) cb(false, "Invalid name");
            return;
        }
        const prefix = dirPath === "/" ? "" : dirPath;
        runCmd(["mv", "-n", "--", prefix + "/" + oldName, prefix + "/" + clean], (ok, out, err) => {
            if (cb) cb(ok, err.trim());
        });
    }

    function copyItems(paths, destDir, cb) {
        if (!paths || paths.length === 0) return;
        const cmd = ["sh", "-c", "dest=\"$1\"; shift; cp -rn -t \"$dest\" -- \"$@\"", "sh", destDir].concat(paths);
        runCmd(cmd, (ok, out, err) => {
            if (cb) cb(ok, err.trim());
        });
    }

    function moveItems(paths, destDir, cb) {
        if (!paths || paths.length === 0) return;
        const cmd = ["sh", "-c", "dest=\"$1\"; shift; mv -n -t \"$dest\" -- \"$@\"", "sh", destDir].concat(paths);
        runCmd(cmd, (ok, out, err) => {
            if (cb) cb(ok, err.trim());
        });
    }

    function deleteItems(paths, permanent, cb) {
        if (!paths || paths.length === 0) return;
        const cmd = permanent
            ? ["rm", "-rf", "--"].concat(paths)
            : ["sh", "-c", "if command -v gio >/dev/null; then gio trash -- \"$@\"; else rm -rf -- \"$@\"; fi", "sh"].concat(paths);
        runCmd(cmd, (ok, out, err) => {
            if (cb) cb(ok, err.trim());
        });
    }

    function inspectArchive(archivePath, cb) {
        const lower = archivePath.toLowerCase();
        let cmd;
        if (lower.endsWith(".zip")) {
            cmd = ["unzip", "-Z1", archivePath];
        } else if (lower.endsWith(".7z")) {
            cmd = ["sh", "-c", "7z l -ba \"$1\" | awk '{print $NF}'", "sh", archivePath];
        } else {
            cmd = ["tar", "-tf", archivePath];
        }
        runCmd(cmd, (ok, out, err) => {
            if (!ok) {
                if (cb) cb(false, [], err.trim() || "Cannot read archive");
                return;
            }
            const lines = out.trim().split("\n");
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

    function createArchive(dirPath, names, zipName, cb) {
        if (!names || names.length === 0) return;
        const cmd = ["sh", "-c", "cd \"$1\" && out=\"$2\" && shift 2 && zip -r \"$out\" -- \"$@\"", "sh", dirPath, zipName].concat(names);
        runCmd(cmd, (ok, out, err) => {
            if (cb) cb(ok, err.trim());
        });
    }

    function extractArchive(archivePath, destDir, password, cb) {
        const lower = archivePath.toLowerCase();
        const base = archivePath.split("/").pop().replace(/\.(zip|7z|tar\.gz|tgz|tar\.xz|txz|tar\.bz2|tar)$/i, "") || "extracted";
        const outDir = (destDir === "/" ? "" : destDir) + "/" + base;
        let cmd;
        if (lower.endsWith(".zip")) {
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
