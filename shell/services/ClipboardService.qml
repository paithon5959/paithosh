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

    readonly property int count: entries.length

    function detectKind(preview) {
        const p = preview.trim();
        if (/^\[\[ binary data .* (png|jpe?g|webp|bmp|gif|tiff)/i.test(p)) return "image";
        if (/^https?:\/\/\S+$/i.test(p)) return "url";
        if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(p) || /^rgba?\(/i.test(p)) return "color";
        if (/[{};=>]|^\s*(import|const|let|var|function|def|class|fn)\b/.test(p)) return "code";
        return "text";
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
                parsed.push({
                    id: id,
                    rawLine: line,
                    preview: preview,
                    kind: root.detectKind(preview)
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

    Component.onCompleted: refresh()
}
