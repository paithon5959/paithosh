pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root

    property bool previewMediaActive: false
    property bool previewPlaying: true

    readonly property var mprisPlayer: {
        const list = Mpris.players ? Mpris.players.values : [];
        if (!list || list.length === 0) return null;
        for (let i = 0; i < list.length; ++i) {
            if (list[i] && list[i].isPlaying) return list[i];
        }
        return list[0] || null;
    }

    readonly property var player: mprisPlayer

    readonly property bool useMixcloud: MixcloudService.hasActiveSession && !(mprisPlayer && mprisPlayer.isPlaying && !MixcloudService.isPlaying)

    readonly property bool active: previewMediaActive || useMixcloud || (mprisPlayer !== null && ((mprisPlayer.trackTitle || "") !== "" || mprisPlayer.isPlaying))
    readonly property bool isPlaying: useMixcloud ? MixcloudService.isPlaying : (mprisPlayer ? mprisPlayer.isPlaying : (previewMediaActive ? previewPlaying : false))
    readonly property string trackTitle: useMixcloud
        ? (MixcloudService.currentTrack ? MixcloudService.currentTrack.name : "")
        : ((mprisPlayer && mprisPlayer.trackTitle) ? mprisPlayer.trackTitle : (previewMediaActive ? "Lofi Beats" : ""))
    readonly property string trackArtist: useMixcloud
        ? (MixcloudService.currentTrack ? MixcloudService.currentTrack.artist : "")
        : ((mprisPlayer && mprisPlayer.trackArtist) ? mprisPlayer.trackArtist : (previewMediaActive ? "Chillhop Music" : ""))
    readonly property string trackAlbum: useMixcloud
        ? "Mixcloud"
        : ((mprisPlayer && mprisPlayer.trackAlbum) ? mprisPlayer.trackAlbum : (previewMediaActive ? "Cozy Vinyl" : ""))
    readonly property url trackArtUrl: useMixcloud
        ? (MixcloudService.currentTrack ? MixcloudService.currentTrack.artSmall : "")
        : ((mprisPlayer && mprisPlayer.trackArtUrl) ? mprisPlayer.trackArtUrl : "")

    readonly property real progress: {
        if (useMixcloud) return MixcloudService.progress;
        if (mprisPlayer && mprisPlayer.length > 0) {
            return Math.max(0, Math.min(1, mprisPlayer.position / mprisPlayer.length));
        }
        return 0.54;
    }

    function formatTime(secs) {
        if (!secs || isNaN(secs) || secs < 0) return "0:00";
        const total = Math.floor(secs);
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const r = total % 60;
        const ss = r < 10 ? ("0" + r) : String(r);
        if (h > 0) {
            const mm = m < 10 ? ("0" + m) : String(m);
            return h + ":" + mm + ":" + ss;
        }
        return m + ":" + ss;
    }

    readonly property string positionText: useMixcloud
        ? formatTime(MixcloudService.position)
        : (mprisPlayer ? formatTime(mprisPlayer.position) : "1:42")
    readonly property string lengthText: useMixcloud
        ? formatTime(MixcloudService.effectiveDuration)
        : (mprisPlayer ? formatTime(mprisPlayer.length) : "3:18")

    Timer {
        interval: 1000
        running: !root.useMixcloud && root.mprisPlayer !== null && root.mprisPlayer.isPlaying
        repeat: true
        onTriggered: {
            if (root.mprisPlayer && root.mprisPlayer.positionSupported) {
                root.mprisPlayer.positionChanged();
            }
        }
    }

    function togglePlay() {
        if (useMixcloud) {
            MixcloudService.togglePlay();
        } else if (mprisPlayer) {
            mprisPlayer.togglePlaying();
        } else {
            previewPlaying = !previewPlaying;
        }
    }

    function next() {
        if (useMixcloud) MixcloudService.next();
        else if (mprisPlayer && mprisPlayer.canGoNext) mprisPlayer.next();
    }

    function previous() {
        if (useMixcloud) MixcloudService.previous();
        else if (mprisPlayer && mprisPlayer.canGoPrevious) mprisPlayer.previous();
    }

    function togglePreviewMedia() {
        previewMediaActive = !previewMediaActive;
    }
}
