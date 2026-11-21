pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root

    property bool previewMediaActive: false
    property bool previewPlaying: true

    readonly property var player: {
        const list = Mpris.players ? Mpris.players.values : [];
        if (!list || list.length === 0) return null;
        for (let i = 0; i < list.length; ++i) {
            if (list[i] && list[i].isPlaying) return list[i];
        }
        return list[0] || null;
    }

    readonly property bool active: previewMediaActive || (player !== null && ((player.trackTitle || "") !== "" || player.isPlaying))
    readonly property bool isPlaying: player ? player.isPlaying : (previewMediaActive ? previewPlaying : false)
    readonly property string trackTitle: (player && player.trackTitle) ? player.trackTitle : "Lofi Beats"
    readonly property string trackArtist: (player && player.trackArtist) ? player.trackArtist : "Chillhop Music"
    readonly property string trackAlbum: (player && player.trackAlbum) ? player.trackAlbum : "Cozy Vinyl"
    readonly property url trackArtUrl: (player && player.trackArtUrl) ? player.trackArtUrl : ""

    readonly property real progress: {
        if (player && player.length > 0) {
            return Math.max(0, Math.min(1, player.position / player.length));
        }
        return 0.54;
    }

    function formatTime(secs) {
        if (!secs || isNaN(secs) || secs < 0) return "0:00";
        const s = Math.floor(secs);
        const m = Math.floor(s / 60);
        const r = s % 60;
        return m + ":" + (r < 10 ? "0" + r : r);
    }

    readonly property string positionText: player ? formatTime(player.position) : "1:42"
    readonly property string lengthText: player ? formatTime(player.length) : "3:18"

    Timer {
        interval: 1000
        running: root.player !== null && root.player.isPlaying
        repeat: true
        onTriggered: {
            if (root.player && root.player.positionSupported) {
                root.player.positionChanged();
            }
        }
    }

    function togglePlay() {
        if (player) {
            player.togglePlaying();
        } else {
            previewPlaying = !previewPlaying;
        }
    }

    function next() {
        if (player && player.canGoNext) player.next();
    }

    function previous() {
        if (player && player.canGoPrevious) player.previous();
    }

    function togglePreviewMedia() {
        previewMediaActive = !previewMediaActive;
    }
}
