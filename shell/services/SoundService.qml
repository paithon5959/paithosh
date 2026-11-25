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
                for (const id in root._savedStreams) {
                    const entry = root._savedStreams[id];
                    if (entry && entry.node && entry.node.audio) {
                        entry.node.audio.volume = entry.orig;
                    }
                }
                savedClearTimer.restart();
            }
        }
    }

    Timer {
        id: savedClearTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root._activeSfx === 0 && !duckAnim.running && root._duckGain >= 0.999) {
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

    readonly property var _ambientFiles: ({
        "wind": "lock-wind.wav",
        "rain": "lock-rain.wav",
        "snow": "lock-snow.wav"
    })
    property bool _ambientActive: false
    property bool _ambientPreview: false
    property string _ambientPreset: "wind"
    property real _ambientGain: 0.0
    property real _ambientTargetGain: 0.0
    property int _ambientPendingFadeMs: 0
    property real _mediaFadeGain: 1.0
    property var _mediaFadeStreams: ({})
    property var _mediaFadeOutCallback: null
    readonly property bool _mediaPlaying: MediaService.isPlaying
    readonly property bool previewAmbientPlaying: _ambientPreview && _ambientTargetGain > 0.01
    readonly property real _effectiveAmbientVol: Math.max(0.0, Math.min(1.0, root.volume * (LockService.ambientVolume / 100.0) * 0.45))

    function _findAmbientNode() {
        const streams = AudioService.playbackStreams;
        for (let i = 0; i < streams.length; i++) {
            const n = streams[i];
            if (!n || !n.audio || !n.properties) continue;
            if (n.properties["application.name"] === "paithosh-lock-ambient") return n;
        }
        return null;
    }

    function _applyAmbientVolume() {
        const n = _findAmbientNode();
        if (n && n.audio) {
            const targetLinear = Math.max(0.0, Math.min(1.0, _effectiveAmbientVol));
            const targetPerceptual = targetLinear > 0.0001 ? Math.pow(targetLinear, 1.0 / 3.0) : 0.0;
            n.audio.volume = Math.max(0.0, Math.min(1.0, targetPerceptual * _ambientGain));
        }
    }

    function _beginAmbientFade(toGain, durationMs) {
        ambientFadeAnim.stop();
        _ambientTargetGain = toGain;
        const dist = Math.abs(toGain - _ambientGain);
        if (dist < 0.005) {
            _ambientGain = toGain;
            _applyAmbientVolume();
            if (toGain <= 0.001 && ambientLoopProc.running) {
                ambientLoopProc.running = false;
            }
            return;
        }
        ambientFadeAnim.from = _ambientGain;
        ambientFadeAnim.to = toGain;
        ambientFadeAnim.duration = Math.max(160, Math.round(durationMs * dist));
        ambientFadeAnim.start();
    }

    function _fadeInAmbient(durationMs) {
        const file = _ambientFiles[_ambientPreset];
        if (!file || !enabled || LockService.silentMode) return;
        _ambientTargetGain = 1.0;
        if (!ambientLoopProc.running) {
            _ambientGain = 0.0;
            _ambientPendingFadeMs = durationMs;
            ambientLoopProc.command = _ambientCmd(file, 1.0);
            ambientLoopProc.running = true;
            ambientAttachTimer.restart();
        } else {
            _ambientPendingFadeMs = 0;
            ambientAttachTimer.stop();
            _beginAmbientFade(1.0, durationMs);
        }
    }

    function _fadeOutAmbient(durationMs) {
        _ambientTargetGain = 0.0;
        _ambientPendingFadeMs = 0;
        ambientAttachTimer.stop();
        if (!ambientLoopProc.running) {
            _ambientGain = 0.0;
            return;
        }
        if (_findAmbientNode()) {
            _beginAmbientFade(0.0, durationMs);
        } else {
            ambientFadeAnim.stop();
            _ambientGain = 0.0;
            ambientLoopProc.running = false;
        }
    }

    function _restoreMediaFadeStreams() {
        mediaFadeAnim.stop();
        mediaRestoreTimer.stop();
        mediaRestoreFallbackTimer.stop();
        _mediaFadeOutCallback = null;
        for (const id in _mediaFadeStreams) {
            const entry = _mediaFadeStreams[id];
            if (entry && entry.node && entry.node.audio) {
                entry.node.audio.volume = entry.orig;
            }
        }
        _mediaFadeStreams = ({});
        _mediaFadeGain = 1.0;
    }

    function fadeOutMediaAndRun(durationMs, callback) {
        mediaFadeAnim.stop();
        mediaRestoreTimer.stop();
        const streams = AudioService.appPlaybackStreams;
        const map = ({});
        let count = 0;
        for (let i = 0; i < streams.length; i++) {
            const n = streams[i];
            if (!n || !n.audio || n.audio.muted) continue;
            const key = String(n.id);
            const orig = (_mediaFadeStreams[key] !== undefined) ? _mediaFadeStreams[key].orig : n.audio.volume;
            if (isNaN(orig) || orig <= 0.001) continue;
            map[key] = { node: n, orig: orig };
            count++;
        }
        if (count === 0) {
            if (typeof callback === "function") callback();
            return;
        }
        _mediaFadeStreams = map;
        _mediaFadeOutCallback = typeof callback === "function" ? callback : null;
        // Begin ambient fade-in early so media fade-out & ambient fade-in crossfade smoothly
        if (_ambientActive && !_ambientPreview && enabled && !LockService.silentMode && Boolean(_ambientFiles[_ambientPreset])) {
            _fadeInAmbient(1400);
        }
        mediaFadeAnim.from = _mediaFadeGain;
        mediaFadeAnim.to = 0.0;
        mediaFadeAnim.duration = Math.max(180, Math.round((durationMs || 550) * _mediaFadeGain));
        mediaFadeAnim.start();
    }

    Timer {
        id: mediaRestoreTimer
        interval: 180
        repeat: false
        onTriggered: root._restoreMediaFadeStreams()
    }

    Timer {
        id: mediaRestoreFallbackTimer
        interval: 1800
        repeat: false
        onTriggered: root._restoreMediaFadeStreams()
    }

    function _fadeInMediaStreams(durationMs) {
        _restoreMediaFadeStreams();
        const streams = AudioService.appPlaybackStreams;
        const map = ({});
        let count = 0;
        for (let i = 0; i < streams.length; i++) {
            const n = streams[i];
            if (!n || !n.audio || n.audio.muted) continue;
            const v = n.audio.volume;
            if (isNaN(v) || v <= 0.001) continue;
            map[String(n.id)] = { node: n, orig: v };
            n.audio.volume = 0.0;
            count++;
        }
        if (count === 0) return;
        _mediaFadeStreams = map;
        _mediaFadeGain = 0.0;
        mediaFadeAnim.from = 0.0;
        mediaFadeAnim.to = 1.0;
        mediaFadeAnim.duration = durationMs;
        mediaFadeAnim.start();
    }

    on_MediaFadeGainChanged: {
        for (const id in _mediaFadeStreams) {
            const entry = _mediaFadeStreams[id];
            if (entry && entry.node && entry.node.audio) {
                entry.node.audio.volume = entry.orig * _mediaFadeGain;
            }
        }
    }

    NumberAnimation {
        id: mediaFadeAnim
        target: root
        property: "_mediaFadeGain"
        easing.type: Easing.InOutSine
        onStopped: {
            if (root._mediaFadeGain >= 0.995) {
                root._restoreMediaFadeStreams();
            } else if (root._mediaFadeGain <= 0.005 && root._mediaFadeOutCallback) {
                const cb = root._mediaFadeOutCallback;
                root._mediaFadeOutCallback = null;
                cb();
                mediaRestoreFallbackTimer.restart();
            }
        }
    }

    function _syncLockAmbientState() {
        const shouldPlay = _ambientActive && enabled && !LockService.silentMode && !_mediaPlaying && Boolean(_ambientFiles[_ambientPreset]);
        if (shouldPlay) {
            _fadeInAmbient(1400);
        } else {
            _fadeOutAmbient(850);
        }
    }

    on_AmbientGainChanged: _applyAmbientVolume()
    on_EffectiveAmbientVolChanged: _applyAmbientVolume()
    on_MediaPlayingChanged: {
        if (LockService.locked) {
            if (_mediaPlaying) {
                _fadeInMediaStreams(950);
            } else {
                mediaRestoreFallbackTimer.stop();
                mediaRestoreTimer.restart();
            }
        }
        if (_ambientActive && !_ambientPreview) {
            _syncLockAmbientState();
        }
    }

    Connections {
        target: AudioService
        function onPlaybackStreamsChanged() {
            if (!ambientLoopProc.running) return;
            const n = root._findAmbientNode();
            if (!n) return;
            root._applyAmbientVolume();
            if (root._ambientPendingFadeMs > 0 && root._ambientTargetGain > 0.01) {
                const dur = root._ambientPendingFadeMs;
                root._ambientPendingFadeMs = 0;
                ambientAttachTimer.stop();
                root._beginAmbientFade(1.0, dur);
            }
        }
    }

    NumberAnimation {
        id: ambientFadeAnim
        target: root
        property: "_ambientGain"
        easing.type: Easing.InOutSine
        onStopped: {
            if (root._ambientTargetGain <= 0.001 && root._ambientGain <= 0.005) {
                ambientLoopProc.running = false;
            }
        }
    }

    Timer {
        id: ambientAttachTimer
        interval: 160
        repeat: false
        onTriggered: {
            if (root._ambientPendingFadeMs > 0 && root._ambientTargetGain > 0.01 && ambientLoopProc.running) {
                const dur = root._ambientPendingFadeMs;
                root._ambientPendingFadeMs = 0;
                root._applyAmbientVolume();
                root._beginAmbientFade(1.0, dur);
            }
        }
    }

    function _ambientCmd(file, vol) {
        return [
            "bash", "-c",
            "exec pw-cat -p --raw --rate=48000 --channels=1 --format=s16 --volume=\"$2\" -P application.name=paithosh-lock-ambient - < <(while tail -c +45 \"$1\"; do :; done)",
            "_",
            _soundPath(file),
            vol.toFixed(2)
        ];
    }

    Timer {
        id: previewRestartTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (root._ambientPreview && root.enabled && !LockService.silentMode) {
                const file = root._ambientFiles[root._ambientPreset];
                if (file) {
                    ambientFadeAnim.stop();
                    ambientLoopProc.running = false;
                    root._ambientGain = 0.0;
                    root._ambientTargetGain = 1.0;
                    root._ambientPendingFadeMs = 520;
                    ambientLoopProc.command = root._ambientCmd(file, 1.0);
                    ambientLoopProc.running = true;
                    ambientAttachTimer.restart();
                } else {
                    root._ambientPreview = false;
                    root._fadeOutAmbient(320);
                }
            }
        }
    }

    Process {
        id: ambientLoopProc
        running: false
        command: root._ambientCmd("lock-wind.wav", 0.0)
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
            if (n.name === "pw-play" || appName === "pw-play" || appName === "paithosh-lock-ambient") continue;
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

        savedClearTimer.stop();
        restoreHoldTimer.stop();
        _activeSfx += 1;
        if (_duckGain <= duckLevel + 0.02) {
            _spawnSfx(path, v);
        } else {
            if (!(duckAnim.running && duckAnim.to === duckLevel)) {
                _animateDuck(duckLevel, duckDownMs, Easing.InOutSine);
            }
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
    function playPowerPlug() { play("power-plug.wav", 0.80, true); }
    function playPowerUnplug() { play("power-unplug.wav", 0.72, true); }

    function startLockAmbient(preset) {
        previewRestartTimer.stop();
        _ambientPreview = false;
        const file = _ambientFiles[preset];
        if (!enabled || LockService.silentMode || !file) {
            _ambientActive = false;
            _fadeOutAmbient(360);
            return;
        }
        const presetChanged = (_ambientPreset !== preset);
        _ambientPreset = preset;
        _ambientActive = true;
        if (presetChanged && ambientLoopProc.running) {
            ambientFadeAnim.stop();
            ambientLoopProc.running = false;
            _ambientGain = 0.0;
        }
        _syncLockAmbientState();
    }

    function stopLockAmbient() {
        _ambientActive = false;
        _restoreMediaFadeStreams();
        if (!_ambientPreview) {
            _fadeOutAmbient(380);
        }
    }

    function startPreviewAmbient(preset) {
        const target = preset || LockService.ambientSound;
        const file = _ambientFiles[target];
        if (!enabled || LockService.silentMode || !file) {
            stopPreviewAmbient();
            return;
        }
        _ambientPreset = target;
        _ambientPreview = true;
        previewRestartTimer.restart();
    }

    function togglePreviewAmbient(preset) {
        if (_ambientPreview) {
            stopPreviewAmbient();
            return;
        }
        startPreviewAmbient(preset);
    }

    function refreshPreviewAmbient(preset) {
        if (preset !== undefined && preset !== _ambientPreset) {
            _ambientPreset = preset;
            if (!_ambientPreview) return;
            if (LockService.silentMode || !_ambientFiles[_ambientPreset]) {
                stopPreviewAmbient();
            } else {
                previewRestartTimer.restart();
            }
            return;
        }
        if (!_ambientPreview) return;
        if (LockService.silentMode || !_ambientFiles[_ambientPreset]) {
            stopPreviewAmbient();
        } else {
            _applyAmbientVolume();
        }
    }

    function stopPreviewAmbient() {
        previewRestartTimer.stop();
        _ambientPreview = false;
        if (!_ambientActive) {
            _fadeOutAmbient(380);
        }
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
