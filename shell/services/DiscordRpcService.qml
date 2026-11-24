pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string defaultClientId: "920711890211053579"

    property bool enabled: true
    property string preset: "auto" // "auto" | "larper" | "satire" | "minimal" | "custom"
    property string customDetails: "Compiling kernel with -O3"
    property string customState: "I use Fedora btw"
    property bool showTheme: true
    property bool showElapsed: true
    property bool showActiveWindow: false
    property bool showUptime: false
    property int updateInterval: 60
    property string clientId: defaultClientId
    property string themeName: ""

    property bool discordRunning: false
    property bool connected: false
    property string currentDetails: ""
    property string currentState: ""

    property bool _hydrating: false

    readonly property string _scriptPath: Quickshell.shellDir + "/scripts/discord-rpc.py"

    function pushConfig() {
        if (root._hydrating) return;
        if (!rpcProc.running) {
            rpcProc.running = true;
            return;
        }
        const payload = {
            cmd: "config",
            config: {
                enabled: root.enabled,
                preset: root.preset,
                customDetails: root.customDetails,
                customState: root.customState,
                showTheme: root.showTheme,
                showElapsed: root.showElapsed,
                showActiveWindow: root.showActiveWindow,
                showUptime: root.showUptime,
                updateInterval: root.updateInterval,
                clientId: root.clientId.trim() !== "" ? root.clientId.trim() : root.defaultClientId,
                theme: root.themeName
            }
        };
        rpcProc.write(JSON.stringify(payload) + "\n");
    }

    function reroll() {
        if (!rpcProc.running || !root.enabled) return;
        rpcProc.write(JSON.stringify({ cmd: "reroll" }) + "\n");
    }

    function resetClientId() {
        root.clientId = root.defaultClientId;
        root.pushConfig();
    }

    onEnabledChanged: pushConfig()
    onPresetChanged: pushConfig()
    onCustomDetailsChanged: pushConfig()
    onCustomStateChanged: pushConfig()
    onShowThemeChanged: pushConfig()
    onShowElapsedChanged: pushConfig()
    onShowActiveWindowChanged: pushConfig()
    onShowUptimeChanged: pushConfig()
    onUpdateIntervalChanged: pushConfig()
    onClientIdChanged: pushConfig()
    onThemeNameChanged: pushConfig()

    property Process _rpcProc: Process {
        id: rpcProc
        running: true
        stdinEnabled: true
        command: {
            var cmd = ["python3", root._scriptPath];
            if (root.themeName !== "") {
                cmd.push("--theme", root.themeName);
            }
            return cmd;
        }
        stdout: SplitParser {
            onRead: function(line) {
                const trimmed = line.trim();
                if (!trimmed) return;
                try {
                    const data = JSON.parse(trimmed);
                    if (data.type === "config" && data.config) {
                        root._hydrating = true;
                        const c = data.config;
                        if (typeof c.enabled === "boolean") root.enabled = c.enabled;
                        if (typeof c.preset === "string") root.preset = c.preset;
                        if (typeof c.customDetails === "string") root.customDetails = c.customDetails;
                        if (typeof c.customState === "string") root.customState = c.customState;
                        if (typeof c.showTheme === "boolean") root.showTheme = c.showTheme;
                        if (typeof c.showElapsed === "boolean") root.showElapsed = c.showElapsed;
                        if (typeof c.showActiveWindow === "boolean") root.showActiveWindow = c.showActiveWindow;
                        if (typeof c.showUptime === "boolean") root.showUptime = c.showUptime;
                        if (typeof c.updateInterval === "number") root.updateInterval = Math.max(15, Math.min(300, Math.round(c.updateInterval)));
                        if (typeof c.clientId === "string" && c.clientId.trim() !== "") root.clientId = c.clientId.trim();
                        root._hydrating = false;
                    } else {
                        root.discordRunning = !!data.discord_running;
                        root.connected = !!data.connected;
                        root.currentDetails = data.details || "";
                        root.currentState = data.state || "";
                    }
                } catch (e) {
                    // Ignore non-JSON lines
                }
            }
        }
        onExited: function(_code, _status) {
            root.discordRunning = false;
            root.connected = false;
            restartTimer.restart();
        }
    }

    property Timer _restartTimer: Timer {
        id: restartTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (!rpcProc.running) {
                rpcProc.running = true;
            }
        }
    }
}
