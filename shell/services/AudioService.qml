pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    property int fallbackPct: 72
    property int fallbackInputPct: 50

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool hasLiveSink: sink !== null && sink.audio !== null

    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool hasLiveSource: source !== null && source.audio !== null

    readonly property int volumePct: {
        if (hasLiveSink && !isNaN(sink.audio.volume)) {
            return Math.max(0, Math.min(100, Math.round(sink.audio.volume * 100)));
        }
        return fallbackPct;
    }
    readonly property bool muted: hasLiveSink ? Boolean(sink.audio.muted) : false
    onMutedChanged: {
        if (hasLiveSink) {
            osdTriggered(muted ? "mute" : "vol", muted ? 0 : volumePct);
        }
    }

    readonly property int inputVolumePct: {
        if (hasLiveSource && !isNaN(source.audio.volume)) {
            return Math.max(0, Math.min(100, Math.round(source.audio.volume * 100)));
        }
        return fallbackInputPct;
    }
    readonly property bool inputMuted: hasLiveSource ? Boolean(source.audio.muted) : false

    readonly property var allNodes: Pipewire.nodes && Pipewire.nodes.values ? Pipewire.nodes.values : []

    readonly property var outputDevices: {
        const list = [];
        for (let i = 0; i < allNodes.length; i++) {
            const n = allNodes[i];
            if (n && n.audio && n.isSink && !n.isStream) {
                list.push(n);
            }
        }
        return list;
    }

    readonly property var inputDevices: {
        const list = [];
        for (let i = 0; i < allNodes.length; i++) {
            const n = allNodes[i];
            if (n && n.audio && !n.isSink && !n.isStream) {
                list.push(n);
            }
        }
        return list;
    }

    readonly property var playbackStreams: {
        const list = [];
        for (let i = 0; i < allNodes.length; i++) {
            const n = allNodes[i];
            if (n && n.audio && n.isStream && n.isSink) {
                list.push(n);
            }
        }
        return list;
    }

    signal osdTriggered(string kind, int value)

    PwObjectTracker {
        objects: {
            const objs = [];
            if (root.sink) objs.push(root.sink);
            if (root.source) objs.push(root.source);
            for (let i = 0; i < root.outputDevices.length; i++) {
                objs.push(root.outputDevices[i]);
            }
            for (let i = 0; i < root.inputDevices.length; i++) {
                objs.push(root.inputDevices[i]);
            }
            for (let i = 0; i < root.playbackStreams.length; i++) {
                objs.push(root.playbackStreams[i]);
            }
            return objs;
        }
    }

    function deviceDisplayName(node) {
        if (!node) return "Unknown Device";
        if (node.nickname && node.nickname.length > 0) return node.nickname;
        if (node.description && node.description.length > 0) return node.description;
        if (node.name && node.name.length > 0) return node.name;
        return "Device #" + node.id;
    }

    function deviceVolumePct(node) {
        if (node && node.audio && !isNaN(node.audio.volume)) {
            return Math.max(0, Math.min(100, Math.round(node.audio.volume * 100)));
        }
        return 0;
    }

    function isDeviceMuted(node) {
        return node && node.audio ? Boolean(node.audio.muted) : false;
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
            osdTriggered("mute", 0);
        }
    }

    function setInputVolume(pct) {
        const clamped = Math.max(0, Math.min(100, Math.round(pct)));
        fallbackInputPct = clamped;
        if (hasLiveSource) {
            source.audio.volume = clamped / 100.0;
        } else {
            Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", (clamped / 100.0).toFixed(2)]);
        }
    }

    function toggleInputMute() {
        if (hasLiveSource) {
            source.audio.muted = !source.audio.muted;
        } else {
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
        }
    }

    function setDeviceVolume(node, pct) {
        if (!node) return;
        const clamped = Math.max(0, Math.min(100, Math.round(pct)));
        if (node.audio) {
            node.audio.volume = clamped / 100.0;
        } else {
            Quickshell.execDetached(["wpctl", "set-volume", String(node.id), (clamped / 100.0).toFixed(2)]);
        }
    }

    function toggleDeviceMute(node) {
        if (!node) return;
        if (node.audio) {
            node.audio.muted = !node.audio.muted;
        } else {
            Quickshell.execDetached(["wpctl", "set-mute", String(node.id), "toggle"]);
        }
    }

    function setDefaultOutput(node) {
        if (!node) return;
        Pipewire.preferredDefaultAudioSink = node;
        Quickshell.execDetached(["wpctl", "set-default", String(node.id)]);
    }

    function setDefaultInput(node) {
        if (!node) return;
        Pipewire.preferredDefaultAudioSource = node;
        Quickshell.execDetached(["wpctl", "set-default", String(node.id)]);
    }
}
