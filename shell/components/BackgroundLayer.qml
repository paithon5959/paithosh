import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."

PanelWindow {
    id: root

    property var wallpapers: []
    property int currentIndex: 0
    property int _pendingIndex: -1
    property bool usingA: true
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

    function applyWallpaperIndex(idx) {
        const target = Math.max(0, Math.round(idx));
        if (wallpapers.length > 0) {
            const cl = Math.min(target, wallpapers.length - 1);
            _pendingIndex = -1;
            currentIndex = cl;
            setWallpaper(wallpapers[cl]);
        } else {
            _pendingIndex = target;
        }
    }

    function nextWallpaper() {
        if (wallpapers.length === 0) return;
        currentIndex = (currentIndex + 1) % wallpapers.length;
        setWallpaper(wallpapers[currentIndex]);
    }

    function setWallpaper(path) {
        if (!path || path === "") return;
        const url = path.startsWith("file://") ? path : ("file://" + path);
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
        id: wallpaperScanProc
        command: [
            "sh", "-c",
            "find \"$HOME/Pictures\" -maxdepth 2 -type f -not -path '*/Screenshots/*' \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | LC_ALL=C sort | head -n 24"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n").map(s => s.trim()).filter(s => s.length > 0);
                const list = lines.map(p => p.startsWith("file://") ? p : ("file://" + p));
                root.wallpapers = list;
                if (list.length > 0) {
                    const target = root._pendingIndex >= 0 ? root._pendingIndex : root.currentIndex;
                    const cl = Math.max(0, Math.min(target, list.length - 1));
                    root._pendingIndex = -1;
                    root.currentIndex = cl;
                    if (imgA.source.toString() === "" && imgB.source.toString() === "") {
                        imgA.source = list[cl];
                    } else {
                        root.setWallpaper(list[cl]);
                    }
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
