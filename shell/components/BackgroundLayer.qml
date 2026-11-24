import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."

PanelWindow {
    id: root

    readonly property string wallpaperDir: (Quickshell.env("HOME") || "/tmp") + "/.config/paithosh/wallpapers"
    readonly property int maxWallpapers: 16

    property var wallpapers: []
    property int currentIndex: 0
    property string currentWallpaperPath: ""
    property int _pendingIndex: -1
    property string _pendingPath: ""
    property bool usingA: true
    property bool importing: false
    property string transitionMode: "crossfade-scale" // "crossfade-scale" | "crossfade" | "instant"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "paithosh-background"
    exclusionMode: ExclusionMode.Ignore
    color: Theme.pillBg

    function _toUrl(path) {
        if (!path || path === "") return "";
        return path.startsWith("file://") ? path : ("file://" + path);
    }

    function _toLocalPath(path) {
        if (!path || path === "") return "";
        return path.startsWith("file://") ? path.slice(7) : path;
    }

    function _promoteInList(url) {
        if (!url || url === "") return;
        const next = [url];
        for (let i = 0; i < wallpapers.length; i++) {
            if (wallpapers[i] !== url && next.length < maxWallpapers) {
                next.push(wallpapers[i]);
            }
        }
        wallpapers = next;
        currentIndex = 0;
        currentWallpaperPath = _toLocalPath(url);
    }

    function refreshWallpapers() {
        if (wallpaperScanProc.running) wallpaperScanProc.running = false;
        wallpaperScanProc.running = true;
    }

    function applyWallpaperIndex(idx) {
        const target = Math.max(0, Math.round(idx));
        if (wallpapers.length > 0) {
            const cl = Math.min(target, wallpapers.length - 1);
            _pendingIndex = -1;
            currentIndex = cl;
            currentWallpaperPath = _toLocalPath(wallpapers[cl]);
            setWallpaper(wallpapers[cl]);
        } else {
            _pendingIndex = target;
        }
    }

    function applyWallpaperPath(path) {
        const local = _toLocalPath(path);
        if (!local) return;
        const url = _toUrl(local);
        if (wallpapers.length > 0) {
            const idx = wallpapers.indexOf(url);
            if (idx >= 0) {
                _pendingPath = "";
                _pendingIndex = -1;
                currentIndex = idx;
                currentWallpaperPath = local;
                setWallpaper(url);
                return;
            }
            // Fallback if file still exists externally or outside top 16
            _pendingPath = "";
            currentWallpaperPath = local;
            setWallpaper(url);
        } else {
            _pendingPath = local;
        }
    }

    function selectWallpaper(path) {
        const local = _toLocalPath(path);
        if (!local) return;
        const url = _toUrl(local);
        _promoteInList(url);
        setWallpaper(url);
        Quickshell.execDetached(["touch", "--", local]);
    }

    function addAndApplyWallpaper(sourcePath) {
        const local = _toLocalPath(sourcePath);
        if (!local) return;
        importing = true;
        wallpaperImportProc.command = [
            "sh", "-c",
            "src=\"$1\"; dir=\"$2\"; mkdir -p \"$dir\"; " +
            "if [ ! -f \"$src\" ]; then exit 1; fi; " +
            "src_real=$(realpath \"$src\" 2>/dev/null || echo \"$src\"); " +
            "dir_real=$(realpath \"$dir\" 2>/dev/null || echo \"$dir\"); " +
            "case \"$src_real\" in \"$dir_real\"/*) " +
            "  touch -- \"$src_real\"; printf '%s\\n' \"$src_real\"; exit 0 ;; " +
            "esac; " +
            "base=$(basename -- \"$src\"); " +
            "dst=\"$dir_real/$base\"; " +
            "if [ -e \"$dst\" ]; then " +
            "  name=\"${base%.*}\"; ext=\"${base##*.}\"; ts=$(date +%Y%m%d%H%M%S); " +
            "  if [ \"$name\" = \"$base\" ]; then dst=\"$dir_real/${base}-${ts}\"; else dst=\"$dir_real/${name}-${ts}.${ext}\"; fi; " +
            "fi; " +
            "cp -- \"$src\" \"$dst\" && touch -- \"$dst\" && printf '%s\\n' \"$dst\"",
            "_", local, wallpaperDir
        ];
        if (wallpaperImportProc.running) wallpaperImportProc.running = false;
        wallpaperImportProc.running = true;
    }

    function nextWallpaper() {
        if (wallpapers.length === 0) return;
        currentIndex = (currentIndex + 1) % wallpapers.length;
        const url = wallpapers[currentIndex];
        currentWallpaperPath = _toLocalPath(url);
        setWallpaper(url);
    }

    function setWallpaper(path) {
        if (!path || path === "") return;
        const url = _toUrl(path);
        currentWallpaperPath = _toLocalPath(url);
        const startScale = transitionMode === "crossfade-scale" ? 1.03 : 1.0;
        if (usingA) {
            imgB.source = url;
            imgB.scale = startScale;
            usingA = false;
        } else {
            imgA.source = url;
            imgA.scale = startScale;
            usingA = true;
        }
    }

    Process {
        id: wallpaperImportProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.importing = false;
                const dest = (this.text || "").trim();
                if (!dest) return;
                const url = root._toUrl(dest);
                root._promoteInList(url);
                root.setWallpaper(url);
            }
        }
        onExited: function(code) {
            if (code !== 0) root.importing = false;
        }
    }

    Process {
        id: wallpaperScanProc
        command: [
            "sh", "-c",
            "mkdir -p \"$1\" && find \"$1\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) -printf '%T@ %p\\n' 2>/dev/null | sort -rn | head -n 16 | cut -d' ' -f2-",
            "_", root.wallpaperDir
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n").map(s => s.trim()).filter(s => s.length > 0);
                const list = lines.map(p => root._toUrl(p));
                root.wallpapers = list;
                if (list.length > 0) {
                    let cl = 0;
                    if (root._pendingPath !== "") {
                        const targetUrl = root._toUrl(root._pendingPath);
                        const found = list.indexOf(targetUrl);
                        root._pendingPath = "";
                        root._pendingIndex = -1;
                        if (found >= 0) {
                            cl = found;
                        } else {
                            root.currentIndex = 0;
                            root.currentWallpaperPath = root._toLocalPath(targetUrl);
                            if (imgA.source.toString() === "" && imgB.source.toString() === "") {
                                imgA.source = targetUrl;
                            } else {
                                root.setWallpaper(targetUrl);
                            }
                            return;
                        }
                    } else {
                        const target = root._pendingIndex >= 0 ? root._pendingIndex : root.currentIndex;
                        cl = Math.max(0, Math.min(target, list.length - 1));
                        root._pendingIndex = -1;
                    }
                    root.currentIndex = cl;
                    root.currentWallpaperPath = root._toLocalPath(list[cl]);
                    if (imgA.source.toString() === "" && imgB.source.toString() === "") {
                        imgA.source = list[cl];
                    } else {
                        root.setWallpaper(list[cl]);
                    }
                } else {
                    root.currentIndex = 0;
                    root._pendingIndex = -1;
                    root._pendingPath = "";
                }
            }
        }
    }

    Image {
        id: imgA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        opacity: root.usingA ? 1.0 : 0.0
        scale: root.usingA ? 1.0 : (root.transitionMode === "crossfade-scale" ? 1.03 : 1.0)

        Behavior on opacity {
            NumberAnimation {
                duration: root.transitionMode === "instant" ? 0 : Theme.smoothMs * 1.5
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.transitionMode === "instant" ? 0 : Theme.smoothMs * 1.8
                easing.type: Easing.OutCubic
            }
        }
    }

    Image {
        id: imgB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        opacity: root.usingA ? 0.0 : 1.0
        scale: root.usingA ? (root.transitionMode === "crossfade-scale" ? 1.03 : 1.0) : 1.0

        Behavior on opacity {
            NumberAnimation {
                duration: root.transitionMode === "instant" ? 0 : Theme.smoothMs * 1.5
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.transitionMode === "instant" ? 0 : Theme.smoothMs * 1.8
                easing.type: Easing.OutCubic
            }
        }
    }
}
