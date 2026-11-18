pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    property int fallbackPct: 72
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool hasLiveSink: sink !== null && sink.audio !== null

    readonly property int volumePct: {
        if (hasLiveSink && !isNaN(sink.audio.volume)) {
            return Math.max(0, Math.min(100, Math.round(sink.audio.volume * 100)));
        }
        return fallbackPct;
    }
    readonly property bool muted: hasLiveSink ? Boolean(sink.audio.muted) : false

    signal osdTriggered(string kind, int value)

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    function setVolume(pct, emitOsd) {
        const clamped = Math.max(0, Math.min(100, Math.round(pct)));
        fallbackPct = clamped;
        if (hasLiveSink) {
            sink.audio.volume = clamped / 100.0;
        } else {
            Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", (clamped / 100.0).toFixed(2)]);
        }
        if (emitOsd !== false) osdTriggered("vol", clamped);
    }

    function adjustVolume(delta) {
        setVolume(volumePct + delta, true);
    }

    function toggleMute() {
        if (hasLiveSink) {
            sink.audio.muted = !sink.audio.muted;
        } else {
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        }
        osdTriggered("vol", muted ? 0 : volumePct);
    }
}
