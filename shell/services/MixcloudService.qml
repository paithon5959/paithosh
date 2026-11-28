pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var genres: [
        { slug: "lo-fi", label: "Lo-Fi" },
        { slug: "electronic", label: "Electronic" },
        { slug: "house", label: "House" },
        { slug: "deep-house", label: "Deep House" },
        { slug: "techno", label: "Techno" },
        { slug: "ambient", label: "Ambient" },
        { slug: "jazz", label: "Jazz" },
        { slug: "hip-hop", label: "Hip-Hop" },
        { slug: "drum-and-bass", label: "Drum & Bass" },
        { slug: "synthwave", label: "Synthwave" }
    ]

    readonly property string configDir: (Quickshell.env("HOME") || "/tmp") + "/.config/paithosh"
    readonly property string statePath: configDir + "/mixcloud.json"
    readonly property string backupDir: configDir + "/backups"
    readonly property string _daemonScript: Quickshell.shellDir + "/scripts/paithosh-mixcloud.py"

    // Dependency & daemon status
    property bool depsChecked: false
    property bool hasMpv: false
    property bool hasYtDlp: false
    property bool hasFfmpeg: false
    property bool hasPactl: false
    property bool hasParec: false
    readonly property bool depsReady: hasMpv && hasYtDlp
    property string installHint: "sudo dnf install -y mpv yt-dlp ffmpeg"

    // Playback state
    property string playbackState: "idle" // "idle" | "resolving" | "buffering" | "playing" | "paused" | "error"
    property var currentTrack: null
    readonly property bool hasTrack: currentTrack !== null
    readonly property bool hasActiveSession: currentTrack !== null && !_needsResumeReload
    readonly property bool isPlaying: playbackState === "playing"
    readonly property bool isBusy: playbackState === "resolving" || playbackState === "buffering"
    property real position: 0
    property real duration: 0
    property int volume: 80
    property bool muted: false
    property string repeatMode: "off" // "off" | "all" | "one"
    property bool shuffle: false
    property string errorMessage: ""

    // Audio & EQ Settings (Standard -> Advanced DSP)
    property string audioPreset: "standard" // "standard" | "warm" | "bass" | "vocal" | "club" | "custom"
    property bool audioDspEnabled: true
    property real eqBassDb: 0.0
    property real eqMidDb: 0.0
    property real eqHighDb: 0.0
    property real eqBassFreq: 90
    property real eqBassQ: 0.7
    property real eqMidFreq: 1000
    property real eqMidQ: 1.0
    property real eqHighFreq: 10000
    property real eqHighQ: 0.7
    property real audioPreampDb: 0.0
    property bool audioAutoHeadroom: true
    property bool audioNormalize: false
    property real audioNormPeak: 0.92
    property int audioNormFrameMs: 200
    property real audioStereoWidth: 1.0
    property bool audioCrossfeed: false
    property real audioCrossfeedStrength: 0.25
    property bool audioLimiter: true
    property real audioLimiterCeilingDb: -0.5

    // Smooth Media Audio Ducking Settings + Live Telemetry
    property string duckPreset: "balanced" // "gentle" | "balanced" | "focus" | "custom"
    property bool autoDuckEnabled: true
    property real duckLevel: 0.24
    property string duckMode: "rms" // "rms" | "presence"
    property int duckAttackMs: 60
    property int duckReleaseHoldMs: 320
    property int duckFadeDownMs: 260
    property int duckFadeUpMs: 520
    property real duckRmsThresholdDb: -46
    property string duckIgnoredApps: ""
    property bool isDucking: false
    property string duckSource: ""
    property real duckGain: 1.0
    property int duckMonitoredCount: 0
    property var _externalDuckHolds: ({})

    // Progressive Audio Mix Settings + Live Telemetry
    property string mixPreset: "progressive" // "off" | "seamless" | "progressive" | "melodic" | "club" | "custom"
    property bool mixEnabled: true
    property int mixDurationSec: 14
    property string mixCurve: "progressive" // "progressive" | "equal_power" | "smooth_s" | "linear"
    property string mixEqMode: "bass_swap" // "bass_swap" | "stem_eq" | "filter_sweep" | "clean"
    property bool mixHarmonicAdapt: true
    property bool mixPhraseSync: true
    property bool mixSmartOutro: true
    property bool mixCoupledTempo: true
    property int mixEqCrossoverHz: 180
    property int mixEqSwapDepthDb: 18
    property bool mixMatchVolume: true
    property bool mixMatchTempo: true
    property bool mixMatchOffset: true
    property int mixCueLeadSec: 30
    property int mixAnalysisWindowSec: 12
    property int mixMaxTempoShiftPct: 6
    property int mixTempoReleaseSec: 10
    property int mixMaxGainTrimDb: 6
    property real mixSilenceThresholdDb: -38
    property int mixManualOffsetMs: 0
    property int mixMinTrackDurationSec: 45
    property bool mixAllowOnShuffle: true

    property string mixStage: "idle" // "idle" | "cueing" | "analyzing" | "syncing" | "blending" | "swapping"
    property real mixProgress: 0.0
    property var mixNextTrack: null
    property int mixNextQueueIndex: -1
    property real mixBpmA: 0.0
    property real mixBpmB: 0.0
    property real mixGainTrimDb: 0.0
    property real mixOffsetMs: 0.0
    property real mixSpeedRatio: 1.0
    property real mixBufferMs: 0.0
    property string mixKeyA: ""
    property string mixKeyB: ""
    property string mixKeyCompat: ""
    property string mixActiveEqMode: ""
    property real mixPhaseErrMs: 0.0
    property string mixNote: ""
    readonly property bool isMixing: mixStage !== "idle"

    // Playback Preferences
    property bool rememberPosition: true
    property string bufferPreset: "balanced" // "low" | "balanced" | "high"
    property bool pitchCorrection: true

    // Data & Diagnostics
    property real stateFileSizeBytes: 0
    property int backupCount: 0
    property string lastBackupStatus: ""
    property bool lastBackupOk: true

    readonly property real effectiveDuration: duration > 0 ? duration : (currentTrack && currentTrack.duration > 0 ? currentTrack.duration : 0)
    readonly property real progress: effectiveDuration > 0 ? Math.max(0, Math.min(1, position / effectiveDuration)) : 0

    // Feed, Browsing & Settings Navigation State
    property string activeSection: "discover" // "discover" | "search" | "creator" | "queue" | "favorites" | "recent" | "settings"
    property string settingsTab: "audio" // "audio" | "mix" | "ducking" | "playback" | "data"
    property string activeGenre: "lo-fi"
    property string sortMode: "popular" // "popular" | "latest"
    property string searchQuery: ""
    property string creatorUsername: ""
    property string creatorName: ""
    property var feedItems: []
    property bool feedLoading: false
    property bool feedLoadingMore: false
    property string feedError: ""
    property string nextPageUrl: ""

    // Persisted collections & view preferences
    property var queue: []
    property int queueIndex: -1
    property var favorites: []
    property var recent: []
    property bool prefListView: false

    property int _feedSeq: 0
    property int _playSeq: 0
    property bool _loaded: false
    property bool _needsResumeReload: false
    property var _pendingCmds: []
    property string _lastAutoCueTag: ""
    property var _pendingMixEntry: null

    FileView {
        id: stateReader
        path: root.statePath
        preload: true
        printErrors: false
        onLoaded: {
            try {
                const raw = (text() || "").trim();
                if (raw !== "") {
                    root._applyLoadedPayload(JSON.parse(raw), true);
                }
            } catch (e) {}
            root._loaded = true;
            root.refreshStateDiagnostics();
            if (daemonProc.running) {
                root.syncAllDaemonConfigs();
            }
        }
        onLoadFailed: {
            root._loaded = true;
            root.refreshStateDiagnostics();
        }
    }

    function _applyLoadedPayload(d, restorePlaybackTrack) {
        if (!d || typeof d !== "object") return;
        if (Array.isArray(d.favorites)) root.favorites = d.favorites;
        if (Array.isArray(d.recent)) root.recent = d.recent.slice(0, 30);
        if (typeof d.volume === "number") root.volume = Math.max(0, Math.min(100, Math.round(d.volume)));
        if (typeof d.muted === "boolean") root.muted = d.muted;
        if (d.repeatMode === "off" || d.repeatMode === "all" || d.repeatMode === "one") root.repeatMode = d.repeatMode;
        if (typeof d.shuffle === "boolean") root.shuffle = d.shuffle;
        if (typeof d.autoDuckEnabled === "boolean") root.autoDuckEnabled = d.autoDuckEnabled;
        if (typeof d.duckLevel === "number") root.duckLevel = Math.max(0.08, Math.min(0.75, d.duckLevel));
        if (typeof d.lastGenre === "string" && d.lastGenre !== "") root.activeGenre = d.lastGenre;
        if (d.sortMode === "popular" || d.sortMode === "latest") root.sortMode = d.sortMode;
        if (typeof d.prefListView === "boolean") root.prefListView = d.prefListView;
        if (Array.isArray(d.lastQueue)) root.queue = d.lastQueue.slice(0, 50);
        if (typeof d.lastQueueIndex === "number") {
            root.queueIndex = Math.max(-1, Math.min(root.queue.length - 1, Math.round(d.lastQueueIndex)));
        }

        // Audio & EQ Settings
        if (d.audioSettings && typeof d.audioSettings === "object") {
            const a = d.audioSettings;
            if (typeof a.preset === "string") root.audioPreset = a.preset;
            if (typeof a.enabled === "boolean") root.audioDspEnabled = a.enabled;
            if (typeof a.bassDb === "number") root.eqBassDb = Math.max(-12, Math.min(12, a.bassDb));
            if (typeof a.midDb === "number") root.eqMidDb = Math.max(-12, Math.min(12, a.midDb));
            if (typeof a.highDb === "number") root.eqHighDb = Math.max(-12, Math.min(12, a.highDb));
            if (typeof a.bassFreq === "number") root.eqBassFreq = Math.max(40, Math.min(250, a.bassFreq));
            if (typeof a.bassQ === "number") root.eqBassQ = Math.max(0.3, Math.min(2.0, a.bassQ));
            if (typeof a.midFreq === "number") root.eqMidFreq = Math.max(300, Math.min(4000, a.midFreq));
            if (typeof a.midQ === "number") root.eqMidQ = Math.max(0.4, Math.min(3.0, a.midQ));
            if (typeof a.highFreq === "number") root.eqHighFreq = Math.max(4000, Math.min(16000, a.highFreq));
            if (typeof a.highQ === "number") root.eqHighQ = Math.max(0.3, Math.min(2.0, a.highQ));
            if (typeof a.preampDb === "number") root.audioPreampDb = Math.max(-12, Math.min(6, a.preampDb));
            if (typeof a.autoHeadroom === "boolean") root.audioAutoHeadroom = a.autoHeadroom;
            if (typeof a.normalize === "boolean") root.audioNormalize = a.normalize;
            if (typeof a.normPeak === "number") root.audioNormPeak = Math.max(0.75, Math.min(0.98, a.normPeak));
            if (typeof a.normFrameMs === "number") root.audioNormFrameMs = Math.max(100, Math.min(500, Math.round(a.normFrameMs)));
            if (typeof a.stereoWidth === "number") root.audioStereoWidth = Math.max(0.5, Math.min(1.8, a.stereoWidth));
            if (typeof a.crossfeed === "boolean") root.audioCrossfeed = a.crossfeed;
            if (typeof a.crossfeedStrength === "number") root.audioCrossfeedStrength = Math.max(0.1, Math.min(0.8, a.crossfeedStrength));
            if (typeof a.limiter === "boolean") root.audioLimiter = a.limiter;
            if (typeof a.limiterCeilingDb === "number") root.audioLimiterCeilingDb = Math.max(-6.0, Math.min(-0.1, a.limiterCeilingDb));
        }

        // Ducking Settings
        if (d.duckSettings && typeof d.duckSettings === "object") {
            const dk = d.duckSettings;
            if (typeof dk.preset === "string") root.duckPreset = dk.preset;
            if (typeof dk.enabled === "boolean") root.autoDuckEnabled = dk.enabled;
            if (typeof dk.level === "number") root.duckLevel = Math.max(0.08, Math.min(0.75, dk.level));
            if (dk.mode === "rms" || dk.mode === "presence") root.duckMode = dk.mode;
            if (typeof dk.attackMs === "number") root.duckAttackMs = Math.max(20, Math.min(300, Math.round(dk.attackMs)));
            if (typeof dk.releaseHoldMs === "number") root.duckReleaseHoldMs = Math.max(100, Math.min(2000, Math.round(dk.releaseHoldMs)));
            if (typeof dk.fadeDownMs === "number") root.duckFadeDownMs = Math.max(80, Math.min(1000, Math.round(dk.fadeDownMs)));
            if (typeof dk.fadeUpMs === "number") root.duckFadeUpMs = Math.max(150, Math.min(2000, Math.round(dk.fadeUpMs)));
            if (typeof dk.rmsThresholdDb === "number") root.duckRmsThresholdDb = Math.max(-60, Math.min(-25, dk.rmsThresholdDb));
            if (typeof dk.ignoredApps === "string") root.duckIgnoredApps = dk.ignoredApps;
        }

        // Progressive Mix Settings
        if (d.mixSettings && typeof d.mixSettings === "object") {
            const m = d.mixSettings;
            if (typeof m.preset === "string") root.mixPreset = m.preset;
            if (typeof m.enabled === "boolean") root.mixEnabled = m.enabled;
            if (typeof m.durationSec === "number") root.mixDurationSec = Math.max(4, Math.min(30, Math.round(m.durationSec)));
            if (m.curve === "progressive" || m.curve === "equal_power" || m.curve === "smooth_s" || m.curve === "linear") root.mixCurve = m.curve;
            if (m.eqMode === "bass_swap" || m.eqMode === "stem_eq" || m.eqMode === "filter_sweep" || m.eqMode === "clean") root.mixEqMode = m.eqMode;
            if (typeof m.harmonicAdapt === "boolean") root.mixHarmonicAdapt = m.harmonicAdapt;
            if (typeof m.phraseSync === "boolean") root.mixPhraseSync = m.phraseSync;
            if (typeof m.smartOutro === "boolean") root.mixSmartOutro = m.smartOutro;
            if (typeof m.coupledTempo === "boolean") root.mixCoupledTempo = m.coupledTempo;
            if (typeof m.eqCrossoverHz === "number") root.mixEqCrossoverHz = Math.max(100, Math.min(320, Math.round(m.eqCrossoverHz)));
            if (typeof m.eqSwapDepthDb === "number") root.mixEqSwapDepthDb = Math.max(6, Math.min(24, Math.round(m.eqSwapDepthDb)));
            if (typeof m.matchVolume === "boolean") root.mixMatchVolume = m.matchVolume;
            if (typeof m.matchTempo === "boolean") root.mixMatchTempo = m.matchTempo;
            if (typeof m.matchOffset === "boolean") root.mixMatchOffset = m.matchOffset;
            if (typeof m.cueLeadSec === "number") root.mixCueLeadSec = Math.max(15, Math.min(60, Math.round(m.cueLeadSec)));
            if (typeof m.analysisWindowSec === "number") root.mixAnalysisWindowSec = Math.max(6, Math.min(20, Math.round(m.analysisWindowSec)));
            if (typeof m.maxTempoShiftPct === "number") root.mixMaxTempoShiftPct = Math.max(0, Math.min(12, Math.round(m.maxTempoShiftPct)));
            if (typeof m.tempoReleaseSec === "number") root.mixTempoReleaseSec = Math.max(4, Math.min(24, Math.round(m.tempoReleaseSec)));
            if (typeof m.maxGainTrimDb === "number") root.mixMaxGainTrimDb = Math.max(0, Math.min(12, Math.round(m.maxGainTrimDb)));
            if (typeof m.silenceThresholdDb === "number") root.mixSilenceThresholdDb = Math.max(-55, Math.min(-24, m.silenceThresholdDb));
            if (typeof m.manualOffsetMs === "number") root.mixManualOffsetMs = Math.max(-250, Math.min(250, Math.round(m.manualOffsetMs)));
            if (typeof m.minTrackDurationSec === "number") root.mixMinTrackDurationSec = Math.max(20, Math.min(120, Math.round(m.minTrackDurationSec)));
            if (typeof m.allowOnShuffle === "boolean") root.mixAllowOnShuffle = m.allowOnShuffle;
        }

        // Playback Preferences
        if (d.playbackSettings && typeof d.playbackSettings === "object") {
            const p = d.playbackSettings;
            if (typeof p.rememberPosition === "boolean") root.rememberPosition = p.rememberPosition;
            if (p.bufferPreset === "low" || p.bufferPreset === "balanced" || p.bufferPreset === "high") root.bufferPreset = p.bufferPreset;
            if (typeof p.pitchCorrection === "boolean") root.pitchCorrection = p.pitchCorrection;
        }

        if (restorePlaybackTrack && d.lastTrack && typeof d.lastTrack === "object" && d.lastTrack.url) {
            root.currentTrack = d.lastTrack;
            root.position = (root.rememberPosition && typeof d.lastPosition === "number" && d.lastPosition > 0) ? d.lastPosition : 0;
            root.duration = (typeof d.lastDuration === "number" && d.lastDuration > 0)
                ? d.lastDuration
                : Number(d.lastTrack.duration || 0);
            root.playbackState = "paused";
            root._needsResumeReload = true;
        }
    }

    Process {
        id: stateWriter
        property string payload: "{}"
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"", "sh", root.statePath, payload]
        onExited: root.refreshStateDiagnostics()
    }

    Process {
        id: diagProc
        property string outBuf: ""
        command: [
            "sh", "-c",
            "sz=$(stat -c%s \"$1\" 2>/dev/null || echo 0); bc=$(ls -1 \"$2\"/mixcloud-backup-*.json 2>/dev/null | wc -l); echo \"$sz $bc\"",
            "sh", root.statePath, root.backupDir
        ]
        stdout: StdioCollector { onStreamFinished: diagProc.outBuf = text }
        onExited: (code) => {
            if (code !== 0) return;
            const parts = (diagProc.outBuf || "").trim().split(/\s+/);
            if (parts.length >= 1) root.stateFileSizeBytes = Number(parts[0]) || 0;
            if (parts.length >= 2) root.backupCount = Number(parts[1]) || 0;
        }
    }

    Process {
        id: backupProc
        property string outPath: ""
        property string payload: "{}"
        command: [
            "sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"",
            "sh", outPath, payload
        ]
        onExited: (code) => {
            if (code === 0) {
                root.lastBackupOk = true;
                root.lastBackupStatus = "Backup saved";
                root.refreshStateDiagnostics();
            } else {
                root.lastBackupOk = false;
                root.lastBackupStatus = "Backup failed";
            }
        }
    }

    Process {
        id: restoreProc
        property string outBuf: ""
        command: [
            "sh", "-c",
            "f=$(ls -1t \"$1\"/mixcloud-backup-*.json 2>/dev/null | head -n 1); [ -n \"$f\" ] && cat \"$f\"",
            "sh", root.backupDir
        ]
        stdout: StdioCollector { onStreamFinished: restoreProc.outBuf = text }
        onExited: (code) => {
            if (code !== 0 || (restoreProc.outBuf || "").trim() === "") {
                root.lastBackupOk = false;
                root.lastBackupStatus = "No backup found";
                return;
            }
            try {
                const parsed = JSON.parse(restoreProc.outBuf);
                root._applyLoadedPayload(parsed, false);
                root.writeStateNow();
                root.syncAllDaemonConfigs();
                root.lastBackupOk = true;
                root.lastBackupStatus = "Restored latest backup";
            } catch (e) {
                root.lastBackupOk = false;
                root.lastBackupStatus = "Invalid backup file";
            }
        }
    }

    Timer {
        id: saveTimer
        interval: 300
        repeat: false
        onTriggered: root.writeStateNow()
    }

    Timer {
        id: dspSyncTimer
        interval: 75
        repeat: false
        onTriggered: root.syncAudioDspNow()
    }

    Timer {
        id: positionSaveTimer
        interval: 5000
        repeat: true
        running: root._loaded && root.isPlaying && root.hasTrack
        onTriggered: root.writeStateNow()
    }

    Component.onDestruction: {
        root.writeStateNow();
        if (daemonProc.running) {
            daemonProc.write(JSON.stringify({ cmd: "quit" }) + "\n");
            daemonProc.running = false;
        }
    }

    function refreshStateDiagnostics() {
        diagProc.outBuf = "";
        diagProc.running = false;
        diagProc.running = true;
    }

    function scheduleSave() {
        if (!root._loaded) return;
        saveTimer.restart();
    }

    function buildStatePayload() {
        return {
            favorites: root.favorites,
            recent: root.recent.slice(0, 30),
            volume: root.volume,
            muted: root.muted,
            repeatMode: root.repeatMode,
            shuffle: root.shuffle,
            autoDuckEnabled: root.autoDuckEnabled,
            duckLevel: root.duckLevel,
            lastGenre: root.activeGenre,
            sortMode: root.sortMode,
            prefListView: root.prefListView,
            lastTrack: root.currentTrack,
            lastPosition: (root.rememberPosition && root.currentTrack) ? Math.max(0, Math.floor(root.position)) : 0,
            lastDuration: root.currentTrack ? Math.max(0, Math.floor(root.effectiveDuration)) : 0,
            lastQueue: root.queue.slice(0, 50),
            lastQueueIndex: root.queueIndex,
            audioSettings: {
                preset: root.audioPreset,
                enabled: root.audioDspEnabled,
                bassDb: root.eqBassDb,
                midDb: root.eqMidDb,
                highDb: root.eqHighDb,
                bassFreq: root.eqBassFreq,
                bassQ: root.eqBassQ,
                midFreq: root.eqMidFreq,
                midQ: root.eqMidQ,
                highFreq: root.eqHighFreq,
                highQ: root.eqHighQ,
                preampDb: root.audioPreampDb,
                autoHeadroom: root.audioAutoHeadroom,
                normalize: root.audioNormalize,
                normPeak: root.audioNormPeak,
                normFrameMs: root.audioNormFrameMs,
                stereoWidth: root.audioStereoWidth,
                crossfeed: root.audioCrossfeed,
                crossfeedStrength: root.audioCrossfeedStrength,
                limiter: root.audioLimiter,
                limiterCeilingDb: root.audioLimiterCeilingDb
            },
            duckSettings: {
                preset: root.duckPreset,
                enabled: root.autoDuckEnabled,
                level: root.duckLevel,
                mode: root.duckMode,
                attackMs: root.duckAttackMs,
                releaseHoldMs: root.duckReleaseHoldMs,
                fadeDownMs: root.duckFadeDownMs,
                fadeUpMs: root.duckFadeUpMs,
                rmsThresholdDb: root.duckRmsThresholdDb,
                ignoredApps: root.duckIgnoredApps
            },
            mixSettings: {
                preset: root.mixPreset,
                enabled: root.mixEnabled,
                durationSec: root.mixDurationSec,
                curve: root.mixCurve,
                eqMode: root.mixEqMode,
                harmonicAdapt: root.mixHarmonicAdapt,
                phraseSync: root.mixPhraseSync,
                smartOutro: root.mixSmartOutro,
                coupledTempo: root.mixCoupledTempo,
                eqCrossoverHz: root.mixEqCrossoverHz,
                eqSwapDepthDb: root.mixEqSwapDepthDb,
                matchVolume: root.mixMatchVolume,
                matchTempo: root.mixMatchTempo,
                matchOffset: root.mixMatchOffset,
                cueLeadSec: root.mixCueLeadSec,
                analysisWindowSec: root.mixAnalysisWindowSec,
                maxTempoShiftPct: root.mixMaxTempoShiftPct,
                tempoReleaseSec: root.mixTempoReleaseSec,
                maxGainTrimDb: root.mixMaxGainTrimDb,
                silenceThresholdDb: root.mixSilenceThresholdDb,
                manualOffsetMs: root.mixManualOffsetMs,
                minTrackDurationSec: root.mixMinTrackDurationSec,
                allowOnShuffle: root.mixAllowOnShuffle
            },
            playbackSettings: {
                rememberPosition: root.rememberPosition,
                bufferPreset: root.bufferPreset,
                pitchCorrection: root.pitchCorrection
            }
        };
    }

    function writeStateNow() {
        if (!root._loaded) return;
        stateWriter.payload = JSON.stringify(root.buildStatePayload(), null, 2);
        stateWriter.running = false;
        stateWriter.running = true;
    }

    Process {
        id: daemonProc
        running: false
        stdinEnabled: true
        command: ["python3", root._daemonScript]
        onRunningChanged: {
            if (running) {
                if (root._pendingCmds.length > 0) {
                    const queued = root._pendingCmds.slice();
                    root._pendingCmds = [];
                    for (let i = 0; i < queued.length; ++i) {
                        daemonProc.write(JSON.stringify(queued[i]) + "\n");
                    }
                }
                if (root._loaded) {
                    root.syncAllDaemonConfigs();
                }
            }
        }
        stdout: SplitParser {
            onRead: function(line) {
                const trimmed = (line || "").trim();
                if (!trimmed) return;
                try {
                    const msg = JSON.parse(trimmed);
                    root._handleDaemonMessage(msg);
                } catch (e) {}
            }
        }
        onExited: function(_code, _status) {
            root.isDucking = false;
            root.duckSource = "";
            root.duckGain = 1.0;
            root.duckMonitoredCount = 0;
            root._resetMixTelemetry();
            if (root.playbackState === "playing" || root.playbackState === "buffering" || root.playbackState === "resolving") {
                root.playbackState = "error";
                if (root.errorMessage === "") root.errorMessage = "Audio backend stopped unexpectedly";
            }
        }
    }

    function _sendDaemon(obj) {
        if (!daemonProc.running) {
            const next = _pendingCmds.slice();
            next.push(obj);
            _pendingCmds = next;
            daemonProc.running = true;
            return;
        }
        daemonProc.write(JSON.stringify(obj) + "\n");
    }

    function ensureBackend() {
        if (!daemonProc.running) {
            daemonProc.running = true;
        }
    }

    function recheckDeps() {
        _sendDaemon({ cmd: "check_deps" });
    }

    // ------------------------------------------------------------------
    // Config Sync & Presets
    // ------------------------------------------------------------------

    function syncAllDaemonConfigs() {
        syncPlaybackConfigNow();
        syncAudioDspNow();
        syncDuckingNow();
        syncMixConfigNow();
    }

    function scheduleAudioDspSync() {
        scheduleSave();
        if (daemonProc.running) dspSyncTimer.restart();
    }

    function syncAudioDspNow() {
        if (!daemonProc.running) return;
        _sendDaemon({
            cmd: "set_audio_dsp",
            enabled: root.audioDspEnabled,
            bass_db: root.eqBassDb,
            mid_db: root.eqMidDb,
            high_db: root.eqHighDb,
            bass_freq: root.eqBassFreq,
            bass_q: root.eqBassQ,
            mid_freq: root.eqMidFreq,
            mid_q: root.eqMidQ,
            high_freq: root.eqHighFreq,
            high_q: root.eqHighQ,
            preamp_db: root.audioPreampDb,
            auto_headroom: root.audioAutoHeadroom,
            normalize: root.audioNormalize,
            norm_peak: root.audioNormPeak,
            norm_frame_ms: root.audioNormFrameMs,
            stereo_width: root.audioStereoWidth,
            crossfeed: root.audioCrossfeed,
            crossfeed_strength: root.audioCrossfeedStrength,
            limiter: root.audioLimiter,
            limiter_ceiling_db: root.audioLimiterCeilingDb
        });
    }

    function syncDuckingNow() {
        scheduleSave();
        if (!daemonProc.running) return;
        const ignored = root.duckIgnoredApps.split(",").map(s => s.trim()).filter(s => s !== "");
        _sendDaemon({
            cmd: "set_ducking",
            enabled: root.autoDuckEnabled,
            level: root.duckLevel,
            mode: root.duckMode,
            attack_ms: root.duckAttackMs,
            release_hold_ms: root.duckReleaseHoldMs,
            fade_down_ms: root.duckFadeDownMs,
            fade_up_ms: root.duckFadeUpMs,
            rms_threshold_db: root.duckRmsThresholdDb,
            ignored_apps: ignored
        });
        for (const k in root._externalDuckHolds) {
            _sendDaemon({
                cmd: "set_duck_hold",
                key: k,
                active: true,
                source: root._externalDuckHolds[k]
            });
        }
    }

    function setExternalDuck(key, active, sourceLabel) {
        const k = String(key || "internal");
        const src = String(sourceLabel || "Video");
        const wasActive = root._externalDuckHolds[k] !== undefined;
        if (Boolean(active) === wasActive && (!active || root._externalDuckHolds[k] === src)) return;
        const next = Object.assign({}, root._externalDuckHolds);
        if (active) next[k] = src;
        else delete next[k];
        root._externalDuckHolds = next;
        if (!daemonProc.running) return;
        _sendDaemon({
            cmd: "set_duck_hold",
            key: k,
            active: Boolean(active),
            source: src
        });
    }

    function syncMixConfigNow() {
        scheduleSave();
        if (!daemonProc.running) return;
        _sendDaemon({
            cmd: "set_mix_config",
            enabled: root.mixEnabled,
            duration_s: root.mixDurationSec,
            curve: root.mixCurve,
            eq_mode: root.mixEqMode,
            harmonic_adapt: root.mixHarmonicAdapt,
            phrase_sync: root.mixPhraseSync,
            smart_outro: root.mixSmartOutro,
            coupled_tempo: root.mixCoupledTempo,
            eq_crossover_hz: root.mixEqCrossoverHz,
            eq_swap_depth_db: root.mixEqSwapDepthDb,
            match_volume: root.mixMatchVolume,
            match_tempo: root.mixMatchTempo,
            match_offset: root.mixMatchOffset,
            cue_lead_s: root.mixCueLeadSec,
            analysis_window_s: root.mixAnalysisWindowSec,
            max_tempo_shift_pct: root.mixMaxTempoShiftPct,
            tempo_release_s: root.mixTempoReleaseSec,
            max_gain_trim_db: root.mixMaxGainTrimDb,
            silence_threshold_db: root.mixSilenceThresholdDb,
            manual_offset_ms: root.mixManualOffsetMs,
            min_track_duration_s: root.mixMinTrackDurationSec
        });
    }

    function syncPlaybackConfigNow() {
        scheduleSave();
        if (!daemonProc.running) return;
        _sendDaemon({
            cmd: "set_playback_config",
            buffer_preset: root.bufferPreset,
            pitch_correction: root.pitchCorrection
        });
    }

    function applyAudioPreset(presetId) {
        root.audioPreset = presetId;
        if (presetId === "custom") {
            root.scheduleSave();
            return;
        }
        root.audioDspEnabled = true;
        root.eqBassQ = 0.7;
        root.eqMidQ = 1.0;
        root.eqHighQ = 0.7;
        root.audioPreampDb = 0.0;
        root.audioAutoHeadroom = true;
        root.audioCrossfeed = false;
        root.audioCrossfeedStrength = 0.25;
        root.audioLimiter = true;
        root.audioLimiterCeilingDb = -0.5;
        root.audioNormPeak = 0.92;
        root.audioNormFrameMs = 200;

        if (presetId === "warm") {
            root.eqBassDb = 4.5; root.eqMidDb = 0.5; root.eqHighDb = -1.0;
            root.eqBassFreq = 85; root.eqMidFreq = 900; root.eqHighFreq = 9500;
            root.audioNormalize = false; root.audioStereoWidth = 1.05;
        } else if (presetId === "bass") {
            root.eqBassDb = 7.0; root.eqMidDb = -1.0; root.eqHighDb = 1.5;
            root.eqBassFreq = 75; root.eqBassQ = 0.8; root.eqMidFreq = 1000; root.eqMidQ = 1.1; root.eqHighFreq = 10500;
            root.audioNormalize = false; root.audioStereoWidth = 1.05;
        } else if (presetId === "vocal") {
            root.eqBassDb = -1.0; root.eqMidDb = 3.5; root.eqHighDb = 2.0;
            root.eqBassFreq = 95; root.eqMidFreq = 1600; root.eqMidQ = 1.2; root.eqHighFreq = 9000;
            root.audioNormalize = true; root.audioStereoWidth = 1.0;
        } else if (presetId === "club") {
            root.eqBassDb = 4.0; root.eqMidDb = -1.5; root.eqHighDb = 4.5;
            root.eqBassFreq = 80; root.eqBassQ = 0.75; root.eqMidFreq = 1000; root.eqHighFreq = 10000; root.eqHighQ = 0.75;
            root.audioNormalize = false; root.audioStereoWidth = 1.15;
        } else {
            // "standard"
            root.audioPreset = "standard";
            root.eqBassDb = 0.0; root.eqMidDb = 0.0; root.eqHighDb = 0.0;
            root.eqBassFreq = 90; root.eqMidFreq = 1000; root.eqHighFreq = 10000;
            root.audioNormalize = false; root.audioStereoWidth = 1.0;
        }
        root.scheduleSave();
        root.syncAudioDspNow();
    }

    function applyDuckPreset(presetId) {
        root.duckPreset = presetId;
        if (presetId === "custom") {
            root.scheduleSave();
            return;
        }
        root.autoDuckEnabled = true;
        root.duckMode = "rms";
        if (presetId === "gentle") {
            root.duckLevel = 0.40;
            root.duckAttackMs = 90;
            root.duckReleaseHoldMs = 420;
            root.duckFadeDownMs = 340;
            root.duckFadeUpMs = 680;
            root.duckRmsThresholdDb = -44;
        } else if (presetId === "focus") {
            root.duckLevel = 0.10;
            root.duckAttackMs = 35;
            root.duckReleaseHoldMs = 550;
            root.duckFadeDownMs = 180;
            root.duckFadeUpMs = 450;
            root.duckRmsThresholdDb = -50;
        } else {
            // "balanced"
            root.duckPreset = "balanced";
            root.duckLevel = 0.24;
            root.duckAttackMs = 60;
            root.duckReleaseHoldMs = 320;
            root.duckFadeDownMs = 260;
            root.duckFadeUpMs = 520;
            root.duckRmsThresholdDb = -46;
        }
        root.syncDuckingNow();
    }

    function applyMixPreset(presetId) {
        root.mixPreset = presetId;
        if (presetId === "custom") {
            root.scheduleSave();
            return;
        }
        if (presetId === "off") {
            root.mixEnabled = false;
            if (root.isMixing) root.cancelMix();
            root.syncMixConfigNow();
            return;
        }
        root.mixEnabled = true;
        root.mixAnalysisWindowSec = 12;
        root.mixMaxGainTrimDb = 6;
        root.mixSilenceThresholdDb = -38;
        root.mixManualOffsetMs = 0;
        root.mixMinTrackDurationSec = 45;
        root.mixAllowOnShuffle = true;

        if (presetId === "seamless") {
            root.mixDurationSec = 8;
            root.mixCurve = "equal_power";
            root.mixEqMode = "clean";
            root.mixMatchVolume = true;
            root.mixMatchTempo = false;
            root.mixMatchOffset = true;
            root.mixHarmonicAdapt = false;
            root.mixPhraseSync = false;
            root.mixSmartOutro = true;
            root.mixCoupledTempo = true;
            root.mixCueLeadSec = 22;
            root.mixMaxTempoShiftPct = 4;
            root.mixTempoReleaseSec = 6;
            root.mixEqCrossoverHz = 180;
            root.mixEqSwapDepthDb = 16;
        } else if (presetId === "melodic") {
            root.mixDurationSec = 16;
            root.mixCurve = "smooth_s";
            root.mixEqMode = "filter_sweep";
            root.mixMatchVolume = true;
            root.mixMatchTempo = true;
            root.mixMatchOffset = true;
            root.mixHarmonicAdapt = true;
            root.mixPhraseSync = false;
            root.mixSmartOutro = true;
            root.mixCoupledTempo = true;
            root.mixCueLeadSec = 32;
            root.mixMaxTempoShiftPct = 5;
            root.mixTempoReleaseSec = 12;
            root.mixEqCrossoverHz = 160;
            root.mixEqSwapDepthDb = 14;
        } else if (presetId === "club") {
            root.mixDurationSec = 22;
            root.mixCurve = "progressive";
            root.mixEqMode = "stem_eq";
            root.mixMatchVolume = true;
            root.mixMatchTempo = true;
            root.mixMatchOffset = true;
            root.mixHarmonicAdapt = true;
            root.mixPhraseSync = true;
            root.mixSmartOutro = true;
            root.mixCoupledTempo = true;
            root.mixCueLeadSec = 40;
            root.mixMaxTempoShiftPct = 8;
            root.mixTempoReleaseSec = 14;
            root.mixEqCrossoverHz = 200;
            root.mixEqSwapDepthDb = 20;
        } else {
            // "progressive"
            root.mixPreset = "progressive";
            root.mixDurationSec = 14;
            root.mixCurve = "progressive";
            root.mixEqMode = "bass_swap";
            root.mixMatchVolume = true;
            root.mixMatchTempo = true;
            root.mixMatchOffset = true;
            root.mixHarmonicAdapt = true;
            root.mixPhraseSync = true;
            root.mixSmartOutro = true;
            root.mixCoupledTempo = true;
            root.mixCueLeadSec = 30;
            root.mixMaxTempoShiftPct = 6;
            root.mixTempoReleaseSec = 10;
            root.mixEqCrossoverHz = 180;
            root.mixEqSwapDepthDb = 18;
        }
        root.syncMixConfigNow();
    }

    // ------------------------------------------------------------------
    // Daemon Message Handling & Queue Lookahead Progressive Mixing
    // ------------------------------------------------------------------

    function _resetMixTelemetry() {
        root.mixStage = "idle";
        root.mixProgress = 0.0;
        root.mixNextTrack = null;
        root.mixNextQueueIndex = -1;
        root.mixBpmA = 0.0;
        root.mixBpmB = 0.0;
        root.mixGainTrimDb = 0.0;
        root.mixOffsetMs = 0.0;
        root.mixSpeedRatio = 1.0;
        root.mixBufferMs = 0.0;
        root.mixKeyA = "";
        root.mixKeyB = "";
        root.mixKeyCompat = "";
        root.mixActiveEqMode = "";
        root.mixPhaseErrMs = 0.0;
        root.mixNote = "";
        root._pendingMixEntry = null;
    }

    function peekNextQueueEntry() {
        if (!root.queue || root.queue.length === 0) return null;
        if (root.queue.length === 1 && root.repeatMode !== "all") return null;
        if (root.shuffle && root.queue.length > 1) {
            if (!root.mixAllowOnShuffle) return null;
            if (root._pendingMixEntry && root._pendingMixEntry.index >= 0 && root._pendingMixEntry.index < root.queue.length) {
                return root._pendingMixEntry;
            }
            let cand = root.queueIndex;
            for (let t = 0; t < 6; ++t) {
                const r = Math.floor(Math.random() * root.queue.length);
                if (r !== root.queueIndex) {
                    cand = r;
                    break;
                }
            }
            if (cand < 0 || cand >= root.queue.length) cand = 0;
            return { track: root.queue[cand], index: cand };
        }
        const nextIdx = root.queueIndex + 1;
        if (nextIdx < root.queue.length) {
            return { track: root.queue[nextIdx], index: nextIdx };
        }
        if (root.repeatMode === "all" && root.queue.length > 0) {
            return { track: root.queue[0], index: 0 };
        }
        return null;
    }

    function _triggerMix(immediate) {
        if (!root.currentTrack || !root.hasMpv || !root.hasYtDlp) return false;
        const entry = root.peekNextQueueEntry();
        if (!entry || !entry.track || !entry.track.url) return false;

        root._pendingMixEntry = entry;
        root.mixNextTrack = entry.track;
        root.mixNextQueueIndex = entry.index;
        root.mixStage = "cueing";
        root.mixProgress = 0.0;
        root.mixNote = immediate ? "Starting Mix Now..." : "Pre-cueing next track...";
        if (!immediate && root.currentTrack) {
            root._lastAutoCueTag = root.currentTrack.key + ":" + root._playSeq;
        }

        // Do NOT mutate root._playSeq yet so Deck A continues reporting live state until mix_swapped.
        root._sendDaemon({
            cmd: immediate ? "mix_now" : "prepare_mix",
            url: entry.track.url,
            next_seq: root._playSeq + 1,
            next_queue_index: entry.index,
            immediate: Boolean(immediate)
        });
        return true;
    }

    function mixNow() {
        if (!root.currentTrack || root.isMixing) return false;
        if (root.playbackState === "paused") {
            if (root._needsResumeReload || !daemonProc.running) return false;
            root._sendDaemon({ cmd: "resume" });
        }
        return root._triggerMix(true);
    }

    function cancelMix() {
        if (daemonProc.running) {
            root._sendDaemon({ cmd: "cancel_mix" });
        }
        root._resetMixTelemetry();
    }

    function _handleDaemonMessage(msg) {
        if (!msg || typeof msg !== "object") return;
        if (msg.type === "deps") {
            root.hasMpv = Boolean(msg.mpv);
            root.hasYtDlp = Boolean(msg.yt_dlp);
            root.hasFfmpeg = Boolean(msg.ffmpeg);
            root.hasPactl = Boolean(msg.pactl);
            root.hasParec = Boolean(msg.parec);
            if (typeof msg.install_hint === "string" && msg.install_hint !== "") {
                root.installHint = msg.install_hint;
            }
            root.depsChecked = true;
        } else if (msg.type === "state") {
            if (typeof msg.seq === "number" && msg.seq !== 0 && msg.seq !== root._playSeq) {
                return;
            }
            if (typeof msg.state === "string") {
                root.playbackState = msg.state;
                if (msg.state === "playing" || msg.state === "buffering") {
                    root.errorMessage = "";
                }
            }
            if (typeof msg.position === "number" && !isNaN(msg.position)) {
                root.position = Math.max(0, msg.position);
            }
            if (typeof msg.duration === "number" && msg.duration > 0) {
                root.duration = msg.duration;
            }

            // Automatic Progressive Mix Lookahead Watcher
            if (
                root.mixEnabled
                && root.isPlaying
                && root.mixStage === "idle"
                && root.repeatMode !== "one"
                && root.currentTrack
                && root.effectiveDuration >= root.mixMinTrackDurationSec
            ) {
                const remaining = root.effectiveDuration - root.position;
                const tag = root.currentTrack.key + ":" + root._playSeq;
                if (remaining > 3.0 && remaining <= root.mixCueLeadSec && root._lastAutoCueTag !== tag) {
                    root._triggerMix(false);
                }
            }
        } else if (msg.type === "duck") {
            root.isDucking = Boolean(msg.ducking);
            root.duckSource = String(msg.source || "");
            if (typeof msg.gain === "number") root.duckGain = msg.gain;
            if (typeof msg.monitored_count === "number") root.duckMonitoredCount = msg.monitored_count;
        } else if (msg.type === "mix") {
            const st = String(msg.stage || "idle");
            root.mixStage = st;
            if (typeof msg.progress === "number") root.mixProgress = msg.progress;
            if (typeof msg.bpm_a === "number") root.mixBpmA = msg.bpm_a;
            if (typeof msg.bpm_b === "number") root.mixBpmB = msg.bpm_b;
            if (typeof msg.gain_trim_db === "number") root.mixGainTrimDb = msg.gain_trim_db;
            if (typeof msg.offset_ms === "number") root.mixOffsetMs = msg.offset_ms;
            if (typeof msg.speed_ratio === "number") root.mixSpeedRatio = msg.speed_ratio;
            if (typeof msg.buffer_ms === "number") root.mixBufferMs = msg.buffer_ms;
            if (typeof msg.key_a === "string") root.mixKeyA = msg.key_a;
            if (typeof msg.key_b === "string") root.mixKeyB = msg.key_b;
            if (typeof msg.key_compat === "string") root.mixKeyCompat = msg.key_compat;
            if (typeof msg.eq_mode === "string") root.mixActiveEqMode = msg.eq_mode;
            if (typeof msg.phase_err_ms === "number") root.mixPhaseErrMs = msg.phase_err_ms;
            if (typeof msg.note === "string") root.mixNote = msg.note;
            if (st === "idle") {
                root.mixNextTrack = null;
                root.mixNextQueueIndex = -1;
                root._pendingMixEntry = null;
                root.mixProgress = 0.0;
                root.mixKeyA = "";
                root.mixKeyB = "";
                root.mixKeyCompat = "";
                root.mixActiveEqMode = "";
                root.mixPhaseErrMs = 0.0;
            }
        } else if (msg.type === "mix_swapped") {
            const nextSeq = typeof msg.seq === "number" ? msg.seq : (root._playSeq + 1);
            root._playSeq = nextSeq;
            const promoted = root._pendingMixEntry ? root._pendingMixEntry.track : root.mixNextTrack;
            const promotedIdx = typeof msg.queue_index === "number" ? msg.queue_index : root.mixNextQueueIndex;
            if (promoted) {
                root.currentTrack = promoted;
                root._recordRecent(promoted);
            }
            if (promotedIdx >= 0 && promotedIdx < root.queue.length) {
                root.queueIndex = promotedIdx;
            }
            root.position = (typeof msg.position === "number" && msg.position >= 0) ? msg.position : 0;
            root.duration = (typeof msg.duration === "number" && msg.duration > 0)
                ? msg.duration
                : Number(promoted && promoted.duration ? promoted.duration : 0);
            root._resetMixTelemetry();
            root.scheduleSave();
        } else if (msg.type === "eof") {
            if (typeof msg.seq === "number" && msg.seq !== root._playSeq) return;
            root._handleTrackEnded();
        } else if (msg.type === "error") {
            if (typeof msg.seq === "number" && msg.seq !== root._playSeq) return;
            root.playbackState = "error";
            root.errorMessage = String(msg.message || "Failed to play Mixcloud stream");
        }
    }

    function _handleTrackEnded() {
        if (!root.currentTrack) return;
        if (root.repeatMode === "one") {
            root.playTrack(root.currentTrack, null);
            return;
        }
        if (root.queue.length > 0) {
            if (root.shuffle && root.queue.length > 1) {
                let nextIdx = root.queueIndex;
                for (let tries = 0; tries < 6; ++tries) {
                    const cand = Math.floor(Math.random() * root.queue.length);
                    if (cand !== root.queueIndex) {
                        nextIdx = cand;
                        break;
                    }
                }
                root.playQueueAt(nextIdx);
                return;
            }
            const nextIdx = root.queueIndex + 1;
            if (nextIdx < root.queue.length) {
                root.playQueueAt(nextIdx);
                return;
            }
            if (root.repeatMode === "all" && root.queue.length > 0) {
                root.playQueueAt(0);
                return;
            }
        }
        root.position = 0;
        root.playbackState = "paused";
    }

    // ------------------------------------------------------------------
    // Mixcloud API Browsing
    // ------------------------------------------------------------------

    function normalizeCloudcast(raw) {
        if (!raw || typeof raw !== "object") return null;
        const pics = raw.pictures || {};
        const user = raw.user || {};
        const tagList = [];
        if (Array.isArray(raw.tags)) {
            for (let i = 0; i < Math.min(4, raw.tags.length); ++i) {
                if (raw.tags[i] && raw.tags[i].name) tagList.push(String(raw.tags[i].name));
            }
        }
        const key = String(raw.key || "");
        const url = String(raw.url || (key ? ("https://www.mixcloud.com" + key) : ""));
        if (!key || !url) return null;
        return {
            key: key,
            url: url,
            name: String(raw.name || "Untitled Mix"),
            artist: String(user.name || user.username || "Unknown Creator"),
            username: String(user.username || ""),
            artSmall: String(pics.medium || pics.large || pics.medium_mobile || ""),
            artLarge: String(pics.large || pics.extra_large || pics["640wx640h"] || pics.medium || ""),
            duration: Number(raw.audio_length || 0),
            plays: Number(raw.play_count || 0),
            favorites: Number(raw.favorite_count || 0),
            listeners: Number(raw.listener_count || 0),
            tags: tagList,
            createdTime: String(raw.created_time || "")
        };
    }

    function _fetchFeed(url, append) {
        const seq = ++_feedSeq;
        if (append) {
            root.feedLoadingMore = true;
        } else {
            root.feedLoading = true;
            root.feedError = "";
        }

        const xhr = new XMLHttpRequest();
        xhr.open("GET", url);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (seq !== root._feedSeq) return;
            root.feedLoading = false;
            root.feedLoadingMore = false;

            if (xhr.status < 200 || xhr.status >= 300) {
                if (!append) root.feedItems = [];
                root.feedError = "Mixcloud API error (HTTP " + xhr.status + ")";
                return;
            }
            try {
                const parsed = JSON.parse(xhr.responseText);
                if (parsed && parsed.error) {
                    root.feedError = String(parsed.error.message || "Mixcloud API error");
                    if (!append) root.feedItems = [];
                    return;
                }
                const rows = Array.isArray(parsed.data) ? parsed.data : [];
                const normalized = [];
                for (let i = 0; i < rows.length; ++i) {
                    const item = root.normalizeCloudcast(rows[i]);
                    if (item) normalized.push(item);
                }
                root.feedItems = append ? root.feedItems.concat(normalized) : normalized;
                root.nextPageUrl = (parsed.paging && parsed.paging.next) ? String(parsed.paging.next) : "";
                root.feedError = "";
            } catch (e) {
                if (!append) root.feedItems = [];
                root.feedError = "Failed to parse Mixcloud response";
            }
        };
        xhr.send();
    }

    function loadDiscover(genreSlug, sort, append) {
        const g = genreSlug || root.activeGenre || "lo-fi";
        const s = (sort === "latest") ? "latest" : "popular";
        root.activeSection = "discover";
        root.activeGenre = g;
        root.sortMode = s;
        if (!append) {
            root.nextPageUrl = "";
            root.scheduleSave();
        }
        const url = (append && root.nextPageUrl !== "")
            ? root.nextPageUrl
            : ("https://api.mixcloud.com/discover/" + encodeURIComponent(g) + "/" + s + "/?limit=20");
        _fetchFeed(url, Boolean(append));
    }

    function searchShows(query, append) {
        const q = String(query || "").trim();
        if (q === "") {
            loadDiscover(root.activeGenre, root.sortMode, false);
            return;
        }
        root.activeSection = "search";
        root.searchQuery = q;
        if (!append) root.nextPageUrl = "";
        const url = (append && root.nextPageUrl !== "")
            ? root.nextPageUrl
            : ("https://api.mixcloud.com/search/?q=" + encodeURIComponent(q) + "&type=cloudcast&limit=20");
        _fetchFeed(url, Boolean(append));
    }

    function loadCreator(username, displayName, append) {
        const u = String(username || "").trim().replace(/^\/+|\/+$/g, "");
        if (u === "") return;
        root.activeSection = "creator";
        root.creatorUsername = u;
        root.creatorName = displayName || u;
        if (!append) root.nextPageUrl = "";
        const url = (append && root.nextPageUrl !== "")
            ? root.nextPageUrl
            : ("https://api.mixcloud.com/" + encodeURIComponent(u) + "/cloudcasts/?limit=20");
        _fetchFeed(url, Boolean(append));
    }

    function loadMore() {
        if (root.feedLoading || root.feedLoadingMore || root.nextPageUrl === "") return;
        _fetchFeed(root.nextPageUrl, true);
    }

    function refreshFeed() {
        if (root.activeSection === "discover") {
            loadDiscover(root.activeGenre, root.sortMode, false);
        } else if (root.activeSection === "search") {
            searchShows(root.searchQuery, false);
        } else if (root.activeSection === "creator") {
            loadCreator(root.creatorUsername, root.creatorName, false);
        }
    }

    function parseMixcloudUrl(rawUrl) {
        const s = String(rawUrl || "").trim();
        const m = s.match(/^(?:https?:\/\/)?(?:www\.|m\.)?mixcloud\.com\/([^\/?#]+)\/([^\/?#]+)\/?/i);
        if (!m) return null;
        const user = m[1];
        const slug = m[2];
        const reserved = ["discover", "search", "categories", "live", "select", "pro", "upload", "settings"];
        if (reserved.indexOf(user.toLowerCase()) !== -1) return null;
        return "/" + user + "/" + slug + "/";
    }

    function resolveAndFetchUrl(rawUrl, callback) {
        const key = parseMixcloudUrl(rawUrl);
        if (!key) {
            if (callback) callback(false, null, "Enter a valid mixcloud.com/<creator>/<mix>/ link");
            return;
        }
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.mixcloud.com" + key);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status < 200 || xhr.status >= 300) {
                if (callback) callback(false, null, "Mix not found on Mixcloud (HTTP " + xhr.status + ")");
                return;
            }
            try {
                const raw = JSON.parse(xhr.responseText);
                const item = root.normalizeCloudcast(raw);
                if (!item) {
                    if (callback) callback(false, null, "Invalid Mixcloud show metadata");
                    return;
                }
                if (callback) callback(true, item, "");
            } catch (e) {
                if (callback) callback(false, null, "Failed to read Mixcloud metadata");
            }
        };
        xhr.send();
    }

    function fetchShowDetail(key, callback) {
        const cleanKey = String(key || "").trim();
        if (!cleanKey) {
            if (callback) callback(false, null);
            return;
        }
        const apiKey = cleanKey.startsWith("/") ? cleanKey : ("/" + cleanKey);
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.mixcloud.com" + apiKey);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status < 200 || xhr.status >= 300) {
                if (callback) callback(false, null);
                return;
            }
            try {
                const raw = JSON.parse(xhr.responseText);
                if (callback) callback(true, raw);
            } catch (e) {
                if (callback) callback(false, null);
            }
        };
        xhr.send();
    }

    // ------------------------------------------------------------------
    // Playback & Queue Controls
    // ------------------------------------------------------------------

    function _recordRecent(track) {
        if (!track || !track.key) return;
        const next = [track];
        for (let i = 0; i < root.recent.length; ++i) {
            if (root.recent[i] && root.recent[i].key !== track.key) {
                next.push(root.recent[i]);
                if (next.length >= 30) break;
            }
        }
        root.recent = next;
        root.scheduleSave();
    }

    function playTrack(track, contextList, startPosition) {
        if (!track || !track.url) return;
        root._resetMixTelemetry();
        root._lastAutoCueTag = "";

        const startPos = (typeof startPosition === "number" && !isNaN(startPosition) && startPosition > 0)
            ? startPosition
            : 0;
        if (Array.isArray(contextList) && contextList.length > 0) {
            const copy = contextList.slice();
            let idx = -1;
            for (let i = 0; i < copy.length; ++i) {
                if (copy[i] && copy[i].key === track.key) {
                    idx = i;
                    break;
                }
            }
            if (idx === -1) {
                copy.unshift(track);
                idx = 0;
            }
            root.queue = copy;
            root.queueIndex = idx;
        } else {
            let existingIdx = -1;
            for (let i = 0; i < root.queue.length; ++i) {
                if (root.queue[i] && root.queue[i].key === track.key) {
                    existingIdx = i;
                    break;
                }
            }
            if (existingIdx !== -1) {
                root.queueIndex = existingIdx;
            } else {
                const nextQ = root.queue.slice();
                nextQ.push(track);
                root.queue = nextQ;
                root.queueIndex = nextQ.length - 1;
            }
        }

        root.currentTrack = track;
        root.position = startPos;
        root.duration = Number(track.duration || 0);
        root.errorMessage = "";
        root.playbackState = "resolving";
        root._needsResumeReload = false;
        root._recordRecent(track);

        const seq = ++root._playSeq;
        root._sendDaemon({
            cmd: "play",
            url: track.url,
            seq: seq,
            volume: root.volume,
            muted: root.muted,
            ducking: root.autoDuckEnabled,
            start_position: startPos
        });
    }

    function enqueueTrack(track) {
        if (!track || !track.key) return false;
        for (let i = 0; i < root.queue.length; ++i) {
            if (root.queue[i] && root.queue[i].key === track.key) return false;
        }
        const nextQ = root.queue.slice();
        nextQ.push(track);
        root.queue = nextQ;
        if (!root.currentTrack) {
            playQueueAt(0);
        }
        root.scheduleSave();
        return true;
    }

    function playNextInQueue(track) {
        if (!track || !track.key) return;
        const filtered = [];
        let newCurIdx = root.queueIndex;
        for (let i = 0; i < root.queue.length; ++i) {
            if (root.queue[i] && root.queue[i].key === track.key) {
                if (i < root.queueIndex) newCurIdx--;
                continue;
            }
            filtered.push(root.queue[i]);
        }
        const insertAt = Math.max(0, Math.min(filtered.length, newCurIdx + 1));
        filtered.splice(insertAt, 0, track);
        root.queue = filtered;
        root.queueIndex = newCurIdx;
        if (!root.currentTrack) {
            playQueueAt(insertAt);
        }
        root.scheduleSave();
    }

    function playQueueAt(idx) {
        if (idx < 0 || idx >= root.queue.length) return;
        root.queueIndex = idx;
        playTrack(root.queue[idx], null);
    }

    function removeQueueAt(idx) {
        if (idx < 0 || idx >= root.queue.length) return;
        const nextQ = root.queue.slice();
        nextQ.splice(idx, 1);
        root.queue = nextQ;
        if (nextQ.length === 0) {
            root.queueIndex = -1;
        } else if (idx < root.queueIndex) {
            root.queueIndex = root.queueIndex - 1;
        } else if (idx === root.queueIndex) {
            if (root.queueIndex >= nextQ.length) {
                root.queueIndex = nextQ.length - 1;
            }
        }
        root.scheduleSave();
    }

    function clearQueue() {
        if (root.isMixing) root.cancelMix();
        root.queue = [];
        root.queueIndex = -1;
        root.scheduleSave();
    }

    function togglePlay() {
        if (!root.currentTrack) {
            if (root.queue.length > 0) {
                playQueueAt(Math.max(0, root.queueIndex));
            } else if (root.feedItems.length > 0) {
                playTrack(root.feedItems[0], root.feedItems);
            }
            return;
        }
        if (root.playbackState === "error") {
            playTrack(root.currentTrack, null, root.position);
            return;
        }
        if (root.playbackState === "paused") {
            if (root._needsResumeReload || !daemonProc.running || (root.position === 0 && root.duration === 0)) {
                playTrack(root.currentTrack, null, root.position);
            } else {
                root._sendDaemon({ cmd: "resume" });
            }
        } else if (root.playbackState === "playing" || root.playbackState === "buffering") {
            root._sendDaemon({ cmd: "pause" });
            root.scheduleSave();
        }
    }

    function stop() {
        root._playSeq += 1;
        root._resetMixTelemetry();
        root._lastAutoCueTag = "";
        root.playbackState = "idle";
        root.position = 0;
        root.duration = 0;
        root.currentTrack = null;
        root._needsResumeReload = false;
        root.errorMessage = "";
        root.isDucking = false;
        root.duckSource = "";
        root.duckGain = 1.0;
        if (daemonProc.running) {
            root._sendDaemon({ cmd: "stop" });
        }
        root.scheduleSave();
    }

    function quitApp() {
        root.writeStateNow();
        root._playSeq += 1;
        root._resetMixTelemetry();
        root._needsResumeReload = root.currentTrack !== null;
        root.playbackState = root.currentTrack ? "paused" : "idle";
        root.errorMessage = "";
        root.isDucking = false;
        root.duckSource = "";
        root.duckGain = 1.0;
        root._pendingCmds = [];
        if (daemonProc.running) {
            daemonProc.write(JSON.stringify({ cmd: "quit" }) + "\n");
            daemonProc.running = false;
        }
    }

    function next() {
        if (root.queue.length === 0) return;
        if (root.shuffle && root.queue.length > 1) {
            let cand = root.queueIndex;
            for (let t = 0; t < 6; ++t) {
                const r = Math.floor(Math.random() * root.queue.length);
                if (r !== root.queueIndex) {
                    cand = r;
                    break;
                }
            }
            playQueueAt(cand);
            return;
        }
        const nextIdx = (root.queueIndex + 1) % root.queue.length;
        playQueueAt(nextIdx);
    }

    function previous() {
        if (root.currentTrack && root.position > 5 && (root.playbackState === "playing" || root.playbackState === "paused")) {
            seekTo(0);
            return;
        }
        if (root.queue.length === 0) return;
        const prevIdx = root.queueIndex <= 0 ? (root.queue.length - 1) : (root.queueIndex - 1);
        playQueueAt(prevIdx);
    }

    function seekTo(seconds) {
        if (!root.currentTrack || root.effectiveDuration <= 0) return;
        const clamped = Math.max(0, Math.min(root.effectiveDuration, Number(seconds) || 0));
        root.position = clamped;
        if (root.mixStage === "blending" || (root.isMixing && (root.effectiveDuration - clamped) > (root.mixCueLeadSec + 4))) {
            root.cancelMix();
            root._lastAutoCueTag = "";
        }
        if (!root._needsResumeReload && daemonProc.running) {
            root._sendDaemon({ cmd: "seek", position: clamped });
        }
        root.scheduleSave();
    }

    function seekFraction(fraction) {
        if (!root.currentTrack || root.effectiveDuration <= 0) return;
        const f = Math.max(0, Math.min(1, Number(fraction) || 0));
        seekTo(f * root.effectiveDuration);
    }

    function setVolume(val) {
        const clamped = Math.max(0, Math.min(100, Math.round(Number(val) || 0)));
        root.volume = clamped;
        if (clamped > 0 && root.muted) {
            root.muted = false;
            if (daemonProc.running) root._sendDaemon({ cmd: "mute", value: false });
        }
        if (daemonProc.running) {
            root._sendDaemon({ cmd: "volume", value: clamped });
        }
        root.scheduleSave();
    }

    function toggleMute() {
        root.muted = !root.muted;
        if (daemonProc.running) {
            root._sendDaemon({ cmd: "mute", value: root.muted });
        }
        root.scheduleSave();
    }

    function cycleRepeat() {
        if (root.repeatMode === "off") root.repeatMode = "all";
        else if (root.repeatMode === "all") root.repeatMode = "one";
        else root.repeatMode = "off";
        root.scheduleSave();
    }

    function toggleShuffle() {
        root.shuffle = !root.shuffle;
        root.scheduleSave();
    }

    function toggleAutoDuck() {
        root.autoDuckEnabled = !root.autoDuckEnabled;
        if (!root.autoDuckEnabled) {
            root.isDucking = false;
            root.duckSource = "";
            root.duckGain = 1.0;
        }
        root.syncDuckingNow();
    }

    function isFavorite(key) {
        if (!key) return false;
        for (let i = 0; i < root.favorites.length; ++i) {
            if (root.favorites[i] && root.favorites[i].key === key) return true;
        }
        return false;
    }

    function toggleFavorite(track) {
        if (!track || !track.key) return false;
        const next = [];
        let removed = false;
        for (let i = 0; i < root.favorites.length; ++i) {
            const it = root.favorites[i];
            if (it && it.key === track.key) {
                removed = true;
            } else if (it) {
                next.push(it);
            }
        }
        if (!removed) {
            next.unshift(track);
        }
        root.favorites = next;
        root.scheduleSave();
        return !removed;
    }

    function setPrefListView(isList) {
        root.prefListView = Boolean(isList);
        root.scheduleSave();
    }

    // ------------------------------------------------------------------
    // Data Management & Resets
    // ------------------------------------------------------------------

    function clearRecent() {
        root.recent = [];
        root.writeStateNow();
    }

    function clearFavorites() {
        root.favorites = [];
        root.writeStateNow();
    }

    function getExportJson() {
        return JSON.stringify(root.buildStatePayload(), null, 2);
    }

    function exportBackup() {
        const d = new Date();
        function p2(n) { return n < 10 ? ("0" + n) : String(n); }
        const stamp = d.getFullYear() + p2(d.getMonth() + 1) + p2(d.getDate()) + "-" + p2(d.getHours()) + p2(d.getMinutes()) + p2(d.getSeconds());
        backupProc.outPath = root.backupDir + "/mixcloud-backup-" + stamp + ".json";
        backupProc.payload = root.getExportJson();
        backupProc.running = false;
        backupProc.running = true;
    }

    function restoreLatestBackup() {
        restoreProc.outBuf = "";
        restoreProc.running = false;
        restoreProc.running = true;
    }

    function resetAllSettings() {
        root.applyAudioPreset("standard");
        root.duckIgnoredApps = "";
        root.applyDuckPreset("balanced");
        root.applyMixPreset("progressive");
        root.activeGenre = "lo-fi";
        root.sortMode = "popular";
        root.prefListView = false;
        root.rememberPosition = true;
        root.bufferPreset = "balanced";
        root.pitchCorrection = true;
        root.syncPlaybackConfigNow();
        root.writeStateNow();
    }

    // ------------------------------------------------------------------
    // Formatting Helpers
    // ------------------------------------------------------------------

    function genreLabel(slug) {
        for (let i = 0; i < root.genres.length; ++i) {
            if (root.genres[i].slug === slug) return root.genres[i].label;
        }
        return slug || "Mixcloud";
    }

    function formatDuration(secs) {
        if (!secs || isNaN(secs) || secs < 0) return "0:00";
        const total = Math.floor(secs);
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        const ss = s < 10 ? ("0" + s) : String(s);
        if (h > 0) {
            const mm = m < 10 ? ("0" + m) : String(m);
            return h + ":" + mm + ":" + ss;
        }
        return m + ":" + ss;
    }

    function formatCount(n) {
        const val = Number(n || 0);
        if (val >= 1000000) return (val / 1000000).toFixed(1).replace(/\.0$/, "") + "M";
        if (val >= 1000) return (val / 1000).toFixed(1).replace(/\.0$/, "") + "K";
        return String(Math.round(val));
    }

    function formatBytes(bytes) {
        const b = Number(bytes || 0);
        if (b < 1024) return Math.round(b) + " B";
        if (b < 1024 * 1024) return (b / 1024).toFixed(1) + " KB";
        return (b / (1024 * 1024)).toFixed(2) + " MB";
    }
}
