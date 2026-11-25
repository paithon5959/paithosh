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

    readonly property string _duckStatePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/paithosh-duck-state.json"
    readonly property int _duckStateTtlMs: 60000
    property int _recoverRetries: 0

    FileView {
        id: duckStateFile
        path: root._duckStatePath
        blockLoading: true
        printErrors: false
    }

    function _streamAppKey(node) {
        if (node && node.properties && node.properties["application.name"]) {
            return String(node.properties["application.name"]);
        }
        return (node && node.name) ? String(node.name) : "";
    }

    function _readPersistedOrig() {
        const cleaned = ({});
        try {
            duckStateFile.reload();
            duckStateFile.waitForJob();
            const raw = duckStateFile.text();
            if (!raw || raw.trim() === "") return cleaned;
            const parsed = JSON.parse(raw);
            if (!parsed || typeof parsed !== "object") return cleaned;
            const now = Date.now();
            for (const k in parsed) {
                const entry = parsed[k];
                if (typeof entry === "number") {
                    if (entry > 0.001 && entry <= 2.0) {
                        cleaned[k] = { orig: entry, app: "", ts: now };
                    }
                } else if (entry && typeof entry === "object") {
                    const orig = Number(entry.orig);
                    const ts = Number(entry.ts || 0);
                    if (orig > 0.001 && orig <= 2.0 && (!ts || (now - ts) <= root._duckStateTtlMs)) {
                        cleaned[k] = {
                            orig: orig,
                            app: entry.app ? String(entry.app) : "",
                            ts: ts || now
                        };
                    }
                }
            }
        } catch (e) {}
        return cleaned;
    }

    function _writePersistedOrig(map) {
        try {
            duckStateFile.setText(JSON.stringify(map || ({})));
            duckStateFile.waitForJob();
        } catch (e) {}
    }

    function recoverOrphanedDuck() {
        if (_activeSfx > 0 || duckAnim.running) return;
        const persisted = _readPersistedOrig();
        if (Object.keys(persisted).length > 0) {
            _recoverRetries = 0;
            reloadRecoverTimer.restart();
        }
    }

    Timer {
        id: reloadRecoverTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root._activeSfx > 0 || duckAnim.running) return;
            const persisted = root._readPersistedOrig();
            const keys = Object.keys(persisted);
            if (keys.length === 0) {
                root._writePersistedOrig({});
                return;
            }
            const streams = AudioService.playbackStreams;
            if (streams.length === 0 && root._recoverRetries < 6) {
                root._recoverRetries += 1;
                reloadRecoverTimer.restart();
                return;
            }
            let recovered = 0;
            let minRatio = 1.0;
            for (let i = 0; i < streams.length; i++) {
                const n = streams[i];
                if (!n || !n.audio) continue;
                const key = String(n.id);
                const rec = persisted[key];
                if (!rec || !(rec.orig > 0.001)) continue;
                if (rec.app && rec.app !== root._streamAppKey(n)) continue;
                root._savedStreams[key] = { node: n, orig: rec.orig };
                const live = n.audio.volume;
                if (!isNaN(live) && live >= 0) {
                    minRatio = Math.min(minRatio, Math.max(0.0, Math.min(1.0, live / rec.orig)));
                }
                recovered++;
            }
            if (recovered > 0 && minRatio < 0.995) {
                root._duckGain = minRatio;
                root._animateDuck(1.0, root.duckUpMs, Easing.InOutSine);
            } else {
                for (const id in root._savedStreams) {
                    const entry = root._savedStreams[id];
                    if (entry && entry.node && entry.node.audio) {
                        entry.node.audio.volume = entry.orig;
                    }
                }
                root._savedStreams = ({});
                root._writePersistedOrig({});
            }
        }
    }

    Component.onDestruction: {
        duckAnim.stop();
        sfxDelayTimer.stop();
        restoreHoldTimer.stop();
        savedClearTimer.stop();
        reloadRecoverTimer.stop();
    }

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
                root._writePersistedOrig({});
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
            const orig = (_mediaFadeStreams[key] !== undefined)
                ? _mediaFadeStreams[key].orig
                : (_savedStreams[key] !== undefined ? _savedStreams[key].orig : n.audio.volume);
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
        const liveKeys = ({});
        for (let i = 0; i < streams.length; i++) {
            const n = streams[i];
            if (n && n.audio) liveKeys[String(n.id)] = true;
        }
        let count = 0;
        for (const k in _savedStreams) {
            const entry = _savedStreams[k];
            if (!liveKeys[k] || !entry || !entry.node || !entry.node.audio) {
                delete _savedStreams[k];
            } else {
                count++;
            }
        }

        const persisted = _readPersistedOrig();
        let persistedDirty = false;
        let inheritedMinRatio = 1.0;
        let hasInherited = false;
        const now = Date.now();

        for (let i = 0; i < streams.length; i++) {
            const n = streams[i];
            if (!n || !n.audio) continue;
            const appName = n.properties ? n.properties["application.name"] : "";
            if (n.name === "pw-play" || appName === "pw-play" || appName === "paithosh-lock-ambient") continue;
            const key = String(n.id);
            if (_savedStreams[key] !== undefined) continue;
            const v = n.audio.volume;
            const appKey = _streamAppKey(n);

            const mediaEntry = _mediaFadeStreams[key];
            if (mediaEntry && mediaEntry.orig > 0.001) {
                _savedStreams[key] = { node: n, orig: mediaEntry.orig };
                persisted[key] = { orig: mediaEntry.orig, app: appKey, ts: now };
                persistedDirty = true;
                count++;
                continue;
            }

            const rec = persisted[key];
            if (rec && rec.orig > 0.001 && (!rec.app || rec.app === appKey)) {
                _savedStreams[key] = { node: n, orig: rec.orig };
                rec.ts = now;
                persistedDirty = true;
                if (!isNaN(v) && v >= 0) {
                    inheritedMinRatio = Math.min(inheritedMinRatio, Math.max(0.0, Math.min(1.0, v / rec.orig)));
                    hasInherited = true;
                }
                count++;
                continue;
            }

            if (isNaN(v) || n.audio.muted || v <= 0.001) continue;
            _savedStreams[key] = { node: n, orig: v };
            persisted[key] = { orig: v, app: appKey, ts: now };
            persistedDirty = true;
            count++;
        }
        if (persistedDirty) {
            _writePersistedOrig(persisted);
        }
        if (hasInherited && _activeSfx === 0 && !duckAnim.running && inheritedMinRatio < _duckGain) {
            _duckGain = Math.max(duckLevel, inheritedMinRatio);
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
        const proc = sfxProcComponent.createObject(root, {
            command: ["pw-play", "--volume=" + vol.toFixed(2), path]
        });
        if (!proc) {
            _onSfxDone();
        }
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

        reloadRecoverTimer.stop();
        savedClearTimer.stop();
        restoreHoldTimer.stop();
        _activeSfx += 1;
        if (_duckGain <= duckLevel + 0.02) {
            _spawnSfx(path, v);
        } else {
            _pendingSfx.push({ path: path, vol: v });
            const ratio = Math.max(0.0, Math.min(1.0, (_duckGain - duckLevel) / Math.max(0.01, 1.0 - duckLevel)));
            const downMs = Math.max(40, Math.round(duckDownMs * ratio));
            if (!(duckAnim.running && duckAnim.to === duckLevel)) {
                _animateDuck(duckLevel, downMs, Easing.InOutSine);
                sfxDelayTimer.interval = downMs;
                sfxDelayTimer.restart();
            } else if (!sfxDelayTimer.running) {
                sfxDelayTimer.interval = downMs;
                sfxDelayTimer.start();
            }
        }
    }

    function playShutter() { play("shutter-soft.wav", 1.0); }
    function playRecordStart() { play("record-start.wav", 0.9); }
    function playRecordStop() { play("record-stop.wav", 0.9); }
    function playNotify() { play("notify-gentle.wav", 0.85); }
    function playInstallerSplash() { play("icon-pop.wav", 0.80, false); }
    function playInstallerStep() { play("installer-step.wav", 0.65, false); }
    function playInstallerStart() { play("installer-start.wav", 0.85, false); }
    function playInstallerDone() { play("installer-done.wav", 0.90, false); }
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
