pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool enabled: true
    property bool duckingEnabled: true
    property real duckLevel: 0.30
    property int duckDownMs: 180
    property int duckHoldMs: 220
    property int duckUpMs: 420
    property real volume: 0.72
    property double _lastKeyMs: 0
    property double _lastVolSfxMs: 0
    property int _keyIdx: 0

    property real _duckGain: 1.0
    property int _activeSfx: 0
    property var _savedStreams: ({})
    property var _pendingSfx: []

    readonly property var _keyFiles: [
        "key-creamy-1.wav",
        "key-creamy-2.wav",
        "key-creamy-3.wav"
    ]

    on_DuckGainChanged: {
        for (const id in _savedStreams) {
            const entry = _savedStreams[id];
            if (entry && entry.node && entry.node.audio) {
                entry.node.audio.volume = entry.orig * _duckGain;
            }
        }
    }

    NumberAnimation {
        id: duckAnim
        target: root
        property: "_duckGain"
        onStopped: {
            if (root._activeSfx === 0 && root._duckGain >= 0.999) {
                root._savedStreams = ({});
            }
        }
    }

    Timer {
        id: sfxDelayTimer
        interval: root.duckDownMs
        repeat: false
        onTriggered: root._flushPending()
    }

    Timer {
        id: restoreHoldTimer
        interval: root.duckHoldMs
        repeat: false
        onTriggered: {
            if (root._activeSfx === 0) {
                root._animateDuck(1.0, root.duckUpMs, Easing.InOutSine);
            }
        }
    }

    Component {
        id: sfxProcComponent
        Process {
            running: true
            onExited: {
                root._onSfxDone();
                destroy();
            }
        }
    }

    property bool _windActive: false

    Process {
        id: windLoopProc
        running: false
        command: ["pw-play", "--volume=" + Math.max(0.0, Math.min(1.0, root.volume * 0.16)).toFixed(2), root._soundPath("lock-wind.wav")]
        onExited: {
            if (root._windActive && root.enabled) {
                windLoopProc.running = true;
            }
        }
    }

    function _soundPath(file) {
        return Qt.resolvedUrl("../assets/sounds/" + file).toString().replace(/^file:\/\//, "");
    }

    function _snapshotStreams() {
        const streams = AudioService.playbackStreams;
        let count = 0;
        for (const k in _savedStreams) {
            if (_savedStreams[k]) count++;
        }
        for (let i = 0; i < streams.length; i++) {
            const n = streams[i];
            if (!n || !n.audio) continue;
            const appName = n.properties ? n.properties["application.name"] : "";
            if (n.name === "pw-play" || appName === "pw-play") continue;
            const key = String(n.id);
            if (_savedStreams[key] !== undefined) continue;
            const v = n.audio.volume;
            if (isNaN(v) || n.audio.muted || v <= 0.001) continue;
            _savedStreams[key] = { node: n, orig: v };
            count++;
        }
        return count;
    }

    function _animateDuck(toGain, durationMs, easingType) {
        duckAnim.stop();
        duckAnim.from = _duckGain;
        duckAnim.to = toGain;
        duckAnim.duration = durationMs;
        duckAnim.easing.type = easingType;
        duckAnim.start();
    }

    function _spawnSfx(path, vol) {
        sfxProcComponent.createObject(root, {
            command: ["pw-play", "--volume=" + vol.toFixed(2), path]
        });
    }

    function _flushPending() {
        const queue = _pendingSfx;
        _pendingSfx = [];
        for (let i = 0; i < queue.length; i++) {
            _spawnSfx(queue[i].path, queue[i].vol);
        }
    }

    function _onSfxDone() {
        _activeSfx = Math.max(0, _activeSfx - 1);
        if (_activeSfx === 0) {
            restoreHoldTimer.restart();
        }
    }

    function play(file, volScale, duck) {
        if (!enabled) return;
        const v = Math.max(0.0, Math.min(1.0, volume * (volScale !== undefined ? volScale : 1.0)));
        if (v <= 0.001) return;
        const path = _soundPath(file);

        if (!duckingEnabled || duck === false) {
            Quickshell.execDetached(["pw-play", "--volume=" + v.toFixed(2), path]);
            return;
        }

        if (_snapshotStreams() === 0 && _activeSfx === 0) {
            Quickshell.execDetached(["pw-play", "--volume=" + v.toFixed(2), path]);
            return;
        }

        restoreHoldTimer.stop();
        _activeSfx += 1;
        if (_duckGain <= duckLevel + 0.02) {
            _spawnSfx(path, v);
        } else {
            _animateDuck(duckLevel, duckDownMs, Easing.InOutSine);
            _pendingSfx.push({ path: path, vol: v });
            if (!sfxDelayTimer.running) sfxDelayTimer.start();
        }
    }

    function playShutter() { play("shutter-soft.wav", 1.0); }
    function playRecordStart() { play("record-start.wav", 0.9); }
    function playRecordStop() { play("record-stop.wav", 0.9); }
    function playNotify() { play("notify-gentle.wav", 0.85); }
    function playInstallerStep() { play("installer-step.wav", 0.65); }
    function playInstallerStart() { play("installer-start.wav", 0.85); }
    function playInstallerDone() { play("installer-done.wav", 0.90); }
    function playIconPop() { play("icon-pop.wav", 0.45); }
    function playLock() { play("lock.wav", 0.75); }
    function playLockError() { play("lock-error.wav", 0.75); }

    function startLockWind() {
        if (!enabled) return;
        _windActive = true;
        if (!windLoopProc.running) windLoopProc.running = true;
    }

    function stopLockWind() {
        _windActive = false;
        if (windLoopProc.running) windLoopProc.running = false;
    }
    function playAudioMuted() { play("audio-muted.wav", 0.85, true); }

    function playVolumeUp() {
        const now = Date.now();
        if (now - _lastVolSfxMs < 35) return;
        _lastVolSfxMs = now;
        play("volume-up.wav", 0.55, false);
    }

    function playVolumeDown() {
        const now = Date.now();
        if (now - _lastVolSfxMs < 35) return;
        _lastVolSfxMs = now;
        play("volume-down.wav", 0.55, false);
    }

    function playKey() {
        const now = Date.now();
        if (now - _lastKeyMs < 24) return;
        _lastKeyMs = now;
        _keyIdx = (_keyIdx + 1) % _keyFiles.length;
        play(_keyFiles[_keyIdx], 0.42, false);
    }
}
