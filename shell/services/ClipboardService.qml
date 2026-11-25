pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var entries: []
    property var pinnedIds: ({})
    property bool loading: false
    property string lastCopiedId: ""
    property var thumbCache: ({})
    property var _thumbCallbacks: ({})

    readonly property int count: entries.length
    readonly property string thumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || ("/tmp/paithosh-" + (Quickshell.env("USER") || "user"))) + "/paithosh-clip-thumbs"

    function extractLocalPath(preview) {
        const p = (preview || "").trim();
        if (!p || p.indexOf("\n") !== -1) return "";
        if (p.startsWith("file://")) {
            const raw = p.slice(7);
            try { return decodeURIComponent(raw); } catch (e) { return raw; }
        }
        if (p.startsWith("/")) return p;
        return "";
    }

    function isBinaryImage(preview) {
        return /^\[\[ binary data .* (png|jpe?g|webp|bmp|gif|tiff)/i.test((preview || "").trim());
    }

    function detectKind(preview) {
        const p = (preview || "").trim();
        if (isBinaryImage(p)) return "image";
        const localPath = extractLocalPath(p);
        if (localPath !== "") {
            if (/\.(png|jpe?g|webp|bmp|gif|tiff|avif|svg)$/i.test(localPath)) return "image";
            if (/\.(mp4|mkv|webm|mov|avi|m4v|flv|wmv|ts)$/i.test(localPath)) return "video";
        }
        if (/^https?:\/\/\S+$/i.test(p)) return "url";
        if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(p) || /^rgba?\(/i.test(p)) return "color";
        if (/[{};=>]|^\s*(import|const|let|var|function|def|class|fn)\b/.test(p)) return "code";
        return "text";
    }

    function requestThumbnail(item, cb) {
        if (!item || !cb) return;
        if (item.kind === "image" && item.mediaPath) {
            cb("file://" + item.mediaPath);
            return;
        }
        if (item.kind !== "image" && item.kind !== "video") return;

        const key = item.kind === "video" ? ("vid:" + item.mediaPath) : ("bin:" + item.id);
        const cached = thumbCache[key];
        if (cached !== undefined) {
            if (cached !== "") cb(cached);
            return;
        }

        if (_thumbCallbacks[key]) {
            _thumbCallbacks[key].push(cb);
            return;
        }
        _thumbCallbacks[key] = [cb];

        let cmd;
        let outPath;
        if (item.kind === "video") {
            outPath = thumbDir + "/vid-" + Qt.md5(item.mediaPath) + ".jpg";
            cmd = [
                "sh", "-c",
                "mkdir -p \"$3\" && ([ -s \"$2\" ] || ffmpeg -y -loglevel error -i \"$1\" -frames:v 1 -vf \"scale=320:-1\" -q:v 5 \"$2\")",
                "sh", item.mediaPath, outPath, thumbDir
            ];
        } else {
            const numId = String(Number(item.id));
            outPath = item.displayLocation || (thumbDir + "/clip-" + numId + ".img");
            cmd = [
                "sh", "-c",
                "mkdir -p \"$3\" && ([ -s \"$2\" ] || cliphist decode \"$1\" > \"$2\")",
                "sh", numId, outPath, thumbDir
            ];
        }

        thumbProcComp.createObject(root, {
            command: cmd,
            cacheKey: key,
            outPath: outPath,
            running: true
        });
    }

    function refresh() {
        if (listProc.running) return;
        loading = true;
        listProc.buffer = "";
        listProc.running = true;
    }

    function copyEntry(id) {
        if (!id) return;
        lastCopiedId = id;
        copyProc.command = ["sh", "-c", "cliphist decode " + Number(id) + " | wl-copy"];
        copyProc.running = true;
    }

    function deleteEntry(rawLine, id) {
        if (!rawLine) return;
        const escaped = rawLine.replace(/'/g, "'\\''");
        deleteProc.command = ["sh", "-c", "printf '%s\\n' '" + escaped + "' | cliphist delete"];
        deleteProc.running = true;
        if (pinnedIds[id]) {
            const next = Object.assign({}, pinnedIds);
            delete next[id];
            pinnedIds = next;
        }
    }

    function clearAll() {
        pinnedIds = ({});
        wipeProc.running = true;
    }

    function togglePin(id) {
        const next = Object.assign({}, pinnedIds);
        if (next[id]) delete next[id];
        else next[id] = true;
        pinnedIds = next;
        rebuildSorted();
    }

    function isPinned(id) {
        return !!pinnedIds[id];
    }

    function rebuildSorted() {
        const copy = entries.slice();
        copy.sort(function(a, b) {
            const pa = !!pinnedIds[a.id];
            const pb = !!pinnedIds[b.id];
            if (pa !== pb) return pa ? -1 : 1;
            return Number(b.id) - Number(a.id);
        });
        entries = copy;
    }

    function search(query, kindFilter) {
        const q = (query || "").trim().toLowerCase();
        const k = kindFilter || "All";
        const out = [];
        for (let i = 0; i < entries.length; ++i) {
            const item = entries[i];
            if (k === "Pinned" && !pinnedIds[item.id]) continue;
            if (k === "Text" && item.kind !== "text" && item.kind !== "code") continue;
            if (k === "Links" && item.kind !== "url") continue;
            if (k === "Images" && item.kind !== "image") continue;
            if (k === "Media" && item.kind !== "image" && item.kind !== "video") continue;
            if (q !== "" && item.preview.toLowerCase().indexOf(q) === -1) continue;
            out.push(item);
        }
        return out;
    }

    // Keep wl-paste --watch cliphist store alive as long as the shell runs
    Process {
        id: watchTextProc
        command: ["wl-paste", "--type", "text", "--watch", "cliphist", "store"]
        running: true
    }

    Process {
        id: watchImageProc
        command: ["wl-paste", "--type", "image", "--watch", "cliphist", "store"]
        running: true
    }

    Process {
        id: listProc
        property string buffer: ""
        command: ["cliphist", "list"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { listProc.buffer += data; }
        }
        onExited: (code, status) => {
            root.loading = false;
            if (code !== 0) return;
            const lines = listProc.buffer.split("\n");
            const parsed = [];
            for (let i = 0; i < lines.length && parsed.length < 150; ++i) {
                const line = lines[i];
                if (!line) continue;
                const tabIdx = line.indexOf("\t");
                if (tabIdx <= 0) continue;
                const id = line.slice(0, tabIdx);
                const preview = line.slice(tabIdx + 1);
                const kind = root.detectKind(preview);
                const isBinImg = root.isBinaryImage(preview);
                let displayTitle = "";
                let displayLocation = "";
                if (isBinImg) {
                    const extMatch = preview.match(/\b(png|jpe?g|webp|bmp|gif|tiff)\b/i);
                    const ext = extMatch ? extMatch[1].toLowerCase() : "png";
                    const dateStr = Qt.formatDate(new Date(), "yyyy-MM-dd");
                    displayTitle = "image-" + dateStr;
                    displayLocation = root.thumbDir + "/image-" + dateStr + "-" + Number(id) + "." + ext;
                }
                parsed.push({
                    id: id,
                    rawLine: line,
                    preview: preview,
                    kind: kind,
                    mediaPath: (kind === "image" || kind === "video") ? root.extractLocalPath(preview) : "",
                    isBinaryImage: isBinImg,
                    displayTitle: displayTitle,
                    displayLocation: displayLocation
                });
            }
            root.entries = parsed;
            root.rebuildSorted();
        }
    }

    Process {
        id: copyProc
        onExited: (code, status) => {
            if (code === 0) refreshTimer.restart();
        }
    }

    Process {
        id: deleteProc
        onExited: (code, status) => {
            root.refresh();
        }
    }

    Process {
        id: wipeProc
        command: ["cliphist", "wipe"]
        onExited: (code, status) => {
            root.refresh();
        }
    }

    Timer {
        id: refreshTimer
        interval: 120
        onTriggered: root.refresh()
    }

    Component {
        id: thumbProcComp
        Process {
            property string cacheKey: ""
            property string outPath: ""
            onExited: (code, status) => {
                const url = (code === 0 && outPath) ? ("file://" + outPath) : "";
                root.thumbCache[cacheKey] = url;
                const cbs = root._thumbCallbacks[cacheKey] || [];
                delete root._thumbCallbacks[cacheKey];
                if (url !== "") {
                    for (let i = 0; i < cbs.length; ++i) {
                        try { cbs[i](url); } catch (e) {}
                    }
                }
                destroy();
            }
        }
    }

    Component.onCompleted: refresh()
}
