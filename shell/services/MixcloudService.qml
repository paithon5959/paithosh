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

    readonly property string statePath: (Quickshell.env("HOME") || "/tmp") + "/.config/paithosh/mixcloud.json"
    readonly property string _daemonScript: Quickshell.shellDir + "/scripts/paithosh-mixcloud.py"

    // Dependency & daemon status
    property bool depsChecked: false
    property bool hasMpv: false
    property bool hasYtDlp: false
    readonly property bool depsReady: hasMpv && hasYtDlp
    property string installHint: "sudo dnf install -y mpv yt-dlp"

    // Playback state
    property string playbackState: "idle" // "idle" | "resolving" | "buffering" | "playing" | "paused" | "error"
    property var currentTrack: null
    readonly property bool hasTrack: currentTrack !== null
    readonly property bool isPlaying: playbackState === "playing"
    readonly property bool isBusy: playbackState === "resolving" || playbackState === "buffering"
    property real position: 0
    property real duration: 0
    property int volume: 80
    property bool muted: false
    property string repeatMode: "off" // "off" | "all" | "one"
    property bool shuffle: false
    property string errorMessage: ""

    // Smooth Media Audio Ducking (yields gracefully when Discord/Browser/other audio plays)
    property bool autoDuckEnabled: true
    property real duckLevel: 0.24
    property bool isDucking: false
    property string duckSource: ""

    readonly property real effectiveDuration: duration > 0 ? duration : (currentTrack && currentTrack.duration > 0 ? currentTrack.duration : 0)
    readonly property real progress: effectiveDuration > 0 ? Math.max(0, Math.min(1, position / effectiveDuration)) : 0

    // Feed & browsing state
    property string activeSection: "discover" // "discover" | "search" | "creator" | "queue" | "favorites" | "recent"
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
    property var _pendingCmds: []

    FileView {
        id: stateReader
        path: root.statePath
        preload: true
        printErrors: false
        onLoaded: {
            try {
                const raw = (text() || "").trim();
                if (raw !== "") {
                    const d = JSON.parse(raw);
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
                }
            } catch (e) {}
            root._loaded = true;
        }
        onLoadFailed: root._loaded = true
    }

    Process {
        id: stateWriter
        property string payload: "{}"
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"", "sh", root.statePath, payload]
    }

    Timer {
        id: saveTimer
        interval: 300
        repeat: false
        onTriggered: root.writeStateNow()
    }

    function scheduleSave() {
        if (!root._loaded) return;
        saveTimer.restart();
    }

    function writeStateNow() {
        if (!root._loaded) return;
        const payload = {
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
            prefListView: root.prefListView
        };
        stateWriter.payload = JSON.stringify(payload, null, 2);
        stateWriter.running = false;
        stateWriter.running = true;
    }

    Process {
        id: daemonProc
        running: false
        stdinEnabled: true
        command: ["python3", root._daemonScript]
        onRunningChanged: {
            if (running && root._pendingCmds.length > 0) {
                const queued = root._pendingCmds.slice();
                root._pendingCmds = [];
                for (let i = 0; i < queued.length; ++i) {
                    daemonProc.write(JSON.stringify(queued[i]) + "\n");
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

    function _handleDaemonMessage(msg) {
        if (!msg || typeof msg !== "object") return;
        if (msg.type === "deps") {
            root.hasMpv = Boolean(msg.mpv);
            root.hasYtDlp = Boolean(msg.yt_dlp);
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
        } else if (msg.type === "duck") {
            root.isDucking = Boolean(msg.ducking);
            root.duckSource = String(msg.source || "");
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

    function playTrack(track, contextList) {
        if (!track || !track.url) return;
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
        root.position = 0;
        root.duration = Number(track.duration || 0);
        root.errorMessage = "";
        root.playbackState = "resolving";
        root._recordRecent(track);

        const seq = ++root._playSeq;
        root._sendDaemon({
            cmd: "play",
            url: track.url,
            seq: seq,
            volume: root.volume,
            muted: root.muted,
            ducking: root.autoDuckEnabled
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
    }

    function clearQueue() {
        root.queue = [];
        root.queueIndex = -1;
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
            playTrack(root.currentTrack, null);
            return;
        }
        if (root.playbackState === "paused") {
            if (root.position === 0 && root.duration === 0) {
                playTrack(root.currentTrack, null);
            } else {
                root._sendDaemon({ cmd: "resume" });
            }
        } else if (root.playbackState === "playing" || root.playbackState === "buffering") {
            root._sendDaemon({ cmd: "pause" });
        }
    }

    function stop() {
        root._playSeq += 1;
        root.playbackState = "idle";
        root.position = 0;
        root.duration = 0;
        root.currentTrack = null;
        root.errorMessage = "";
        root.isDucking = false;
        root.duckSource = "";
        if (daemonProc.running) {
            root._sendDaemon({ cmd: "stop" });
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
        root._sendDaemon({ cmd: "seek", position: clamped });
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
        }
        if (daemonProc.running) {
            root._sendDaemon({ cmd: "set_ducking", enabled: root.autoDuckEnabled, level: root.duckLevel });
        }
        root.scheduleSave();
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
}
