import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."
import "common"

PanelWindow {
    id: root
    reloadableId: "paithoshBackground"

    readonly property string wallpaperDir: (Quickshell.env("HOME") || "/tmp") + "/.config/paithosh/wallpapers"
    readonly property string defaultWallpaperAsset: Quickshell.shellDir + "/assets/wallpapers/default.png"
    readonly property int maxWallpapers: 16

    property string initialWallpaperPath: ""
    property real initialVeilOpacity: 0.0
    property real targetVeilOpacity: 0.0
    property real targetStageScale: 1.0
    readonly property int exitFadeMs: Math.max(140, Math.round(280 / Math.max(0.5, Theme.speedMultiplier)))
    readonly property int enterFadeMs: Math.max(200, Math.round(460 / Math.max(0.5, Theme.speedMultiplier)))
    property bool _bootRevealed: false
    property bool _reloadVeilSettled: false
    property var wallpapers: []
    property int currentIndex: 0
    property string currentWallpaperPath: ""
    property int _pendingIndex: -1
    property string _pendingPath: ""
    property bool usingA: true
    property bool importing: false
    property string transitionMode: "crossfade-scale" // "crossfade-scale" | "crossfade" | "instant"
    readonly property string effectiveTransitionMode: Theme.reduceMotion ? "crossfade" : transitionMode

    readonly property real effectiveVeilOpacity: (!_reloadVeilSettled && initialVeilOpacity > 0.001)
        ? initialVeilOpacity
        : targetVeilOpacity
    readonly property real effectiveStageScale: {
        if (!_bootRevealed) return 1.035;
        if (!_reloadVeilSettled && initialVeilOpacity > 0.001) return 1.02;
        return targetStageScale;
    }

    Component.onCompleted: {
        const initLocal = _toLocalPath(initialWallpaperPath);
        if (initLocal !== "") {
            // Soft reload: wallpaper is already cached & ready, start from opaque veil and reveal smoothly
            currentWallpaperPath = initLocal;
            imgA.source = _toUrl(initLocal);
            usingA = true;
            _bootRevealed = true;
            if (initialVeilOpacity > 0.001) {
                reloadVeilSettleTimer.restart();
            } else {
                _reloadVeilSettled = true;
            }
        } else {
            // Cold boot: wait for saved settings / first wallpaper scan before revealing
            _reloadVeilSettled = true;
            bootFallbackTimer.restart();
        }
    }

    Timer {
        id: reloadVeilSettleTimer
        interval: 45
        repeat: false
        onTriggered: root._reloadVeilSettled = true
    }

    Timer {
        id: bootFallbackTimer
        interval: 260
        repeat: false
        onTriggered: root._bootRevealed = true
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "paithosh-background"
    exclusionMode: ExclusionMode.Ignore
    color: Theme.surfaceBg

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
            if (!wallpaperScanProc.running) wallpaperScanProc.running = true;
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
            currentWallpaperPath = local;
            if (imgA.source.toString() === "" && imgB.source.toString() === "") {
                imgA.source = url;
                usingA = true;
            }
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
        if (Theme.wallpapersDisabled || wallpapers.length === 0) return;
        currentIndex = (currentIndex + 1) % wallpapers.length;
        const url = wallpapers[currentIndex];
        currentWallpaperPath = _toLocalPath(url);
        setWallpaper(url);
    }

    function setWallpaper(path) {
        if (!path || path === "") return;
        const url = _toUrl(path);
        currentWallpaperPath = _toLocalPath(url);
        const activeUrl = usingA ? imgA.source.toString() : imgB.source.toString();
        if (activeUrl === url) return;
        const startScale = effectiveTransitionMode === "crossfade-scale" ? 1.03 : 1.0;
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

    Timer {
        id: deferredWallpaperScanTimer
        interval: 1200
        running: true
        repeat: false
        onTriggered: {
            if (root.wallpapers.length === 0 && !wallpaperScanProc.running) {
                wallpaperScanProc.running = true;
            }
        }
    }

    Process {
        id: wallpaperScanProc
        command: [
            "sh", "-c",
            "mkdir -p \"$1\"; " +
            "if [ -z \"$(find \"$1\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) -print -quit 2>/dev/null)\" ] && [ -f \"$2\" ]; then " +
            "  cp -- \"$2\" \"$1/paithosh-default.png\" 2>/dev/null || true; " +
            "fi; " +
            "find \"$1\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) -printf '%T@ %p\\n' 2>/dev/null | sort -rn | head -n 16 | cut -d' ' -f2-",
            "_", root.wallpaperDir, root.defaultWallpaperAsset
        ]
        running: false
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
                    if (imgA.source.toString() === "" && imgB.source.toString() === "") {
                        root.currentWallpaperPath = root.defaultWallpaperAsset;
                        imgA.source = root._toUrl(root.defaultWallpaperAsset);
                    }
                }
            }
        }
    }

    // Theme-colored background layer (always beneath wallpaperStage; becomes the active desktop backdrop when wallpapers are disabled)
    Rectangle {
        id: themeBackdrop
        anchors.fill: parent
        color: Theme.surfaceBg

        ThemeGradientFill {
            anchors.fill: parent
            enabled: Theme.surfaceGradientEnabled
            color1: Theme.surfaceBg
            colorMid: Theme.surfaceBgMid
            color2: Theme.surfaceBg2
            angle: Theme.gradientAngle
        }
    }

    Item {
        id: wallpaperStage
        anchors.fill: parent
        opacity: (root._bootRevealed && !Theme.wallpapersDisabled) ? 1.0 : 0.0
        visible: opacity > 0.002
        scale: (Theme.wallpapersDisabled && root.effectiveTransitionMode === "crossfade-scale")
            ? 1.03
            : (Theme.reduceMotion ? 1.0 : root.effectiveStageScale)

        Behavior on opacity {
            NumberAnimation {
                duration: root.effectiveTransitionMode === "instant"
                    ? 0
                    : (Theme.reduceMotion ? 120 : (Theme.wallpapersDisabled ? root.exitFadeMs : root.enterFadeMs))
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            enabled: !Theme.reduceMotion
            NumberAnimation {
                duration: root.effectiveTransitionMode === "instant"
                    ? 0
                    : ((Theme.wallpapersDisabled || root.targetVeilOpacity > 0.01) ? root.exitFadeMs : root.enterFadeMs)
                easing.type: (Theme.wallpapersDisabled || root.targetVeilOpacity > 0.01) ? Easing.InOutCubic : Easing.OutCubic
            }
        }

        Image {
            id: imgA
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            sourceSize.width: Theme.reduceMotion ? Math.max(1, root.width) : 0
            sourceSize.height: Theme.reduceMotion ? Math.max(1, root.height) : 0
            opacity: root.usingA ? 1.0 : 0.0
            scale: root.usingA ? 1.0 : (root.effectiveTransitionMode === "crossfade-scale" ? 1.03 : 1.0)
            onStatusChanged: {
                if (status === Image.Ready && !root._bootRevealed) {
                    bootFallbackTimer.stop();
                    root._bootRevealed = true;
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: root.effectiveTransitionMode === "instant" ? 0 : (Theme.reduceMotion ? 120 : Theme.smoothMs * 1.5)
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                enabled: !Theme.reduceMotion
                NumberAnimation {
                    duration: root.effectiveTransitionMode === "instant" ? 0 : Theme.smoothMs * 1.8
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
            sourceSize.width: Theme.reduceMotion ? Math.max(1, root.width) : 0
            sourceSize.height: Theme.reduceMotion ? Math.max(1, root.height) : 0
            opacity: root.usingA ? 0.0 : 1.0
            scale: root.usingA ? (root.effectiveTransitionMode === "crossfade-scale" ? 1.03 : 1.0) : 1.0
            onStatusChanged: {
                if (status === Image.Ready && !root._bootRevealed) {
                    bootFallbackTimer.stop();
                    root._bootRevealed = true;
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: root.effectiveTransitionMode === "instant" ? 0 : (Theme.reduceMotion ? 120 : Theme.smoothMs * 1.5)
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                enabled: !Theme.reduceMotion
                NumberAnimation {
                    duration: root.effectiveTransitionMode === "instant" ? 0 : Theme.smoothMs * 1.8
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // Cohesive OLED fade veil for Reload & Logout/Reboot/Shutdown lifecycle transitions
    Rectangle {
        id: transitionVeil
        anchors.fill: parent
        color: Theme.pillBg
        opacity: root.effectiveVeilOpacity
        visible: opacity > 0.002

        Behavior on opacity {
            NumberAnimation {
                duration: root.effectiveVeilOpacity > transitionVeil.opacity
                    ? root.exitFadeMs
                    : root.enterFadeMs
                easing.type: root.effectiveVeilOpacity > transitionVeil.opacity ? Easing.InOutCubic : Easing.OutCubic
            }
        }
    }
}
