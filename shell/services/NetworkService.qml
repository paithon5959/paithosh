pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Singleton {
    id: root

    readonly property bool wifiEnabled: Networking.wifiEnabled
    property string wifiDevice: "wlan0"
    property var networks: []
    property bool scanning: false
    property bool connecting: false
    property string connectingSsid: ""
    property string lastError: ""

    readonly property string activeSsid: {
        const devs = Networking.devices ? Networking.devices.values : [];
        if (devs) {
            for (let i = 0; i < devs.length; ++i) {
                const dev = devs[i];
                if (dev && dev.type === DeviceType.Wifi && dev.networks && dev.networks.values) {
                    const nets = dev.networks.values;
                    for (let j = 0; j < nets.length; ++j) {
                        if (nets[j] && nets[j].connected) {
                            return nets[j].name || "Connected";
                        }
                    }
                }
            }
        }
        for (let k = 0; k < networks.length; ++k) {
            if (networks[k].inUse) return networks[k].ssid;
        }
        return wifiEnabled ? "Disconnected" : "Off";
    }

    function splitNmcliLine(line) {
        const parts = [];
        let cur = "";
        for (let i = 0; i < line.length; ++i) {
            if (line[i] === "\\" && i + 1 < line.length && line[i + 1] === ":") {
                cur += ":";
                ++i;
            } else if (line[i] === ":") {
                parts.push(cur);
                cur = "";
            } else {
                cur += line[i];
            }
        }
        parts.push(cur);
        return parts;
    }

    function parseBand(freqStr) {
        const mhz = parseInt(freqStr, 10);
        if (isNaN(mhz)) return "";
        return mhz >= 4900 ? "5 GHz" : "2.4 GHz";
    }

    Process {
        id: deviceProc
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE", "device", "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                for (let i = 0; i < lines.length; ++i) {
                    const cols = root.splitNmcliLine(lines[i]);
                    if (cols.length >= 2 && cols[1] === "wifi" && cols[0] !== "") {
                        root.wifiDevice = cols[0];
                        break;
                    }
                }
            }
        }
    }

    Process {
        id: scanProc
        property bool rescan: false
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ", "device", "wifi", "list", "--rescan", rescan ? "yes" : "no"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const bySsid = {};
                for (let i = 0; i < lines.length; ++i) {
                    const raw = lines[i];
                    if (!raw) continue;
                    const cols = root.splitNmcliLine(raw);
                    if (cols.length < 5) continue;
                    const inUse = cols[0].trim() === "*";
                    const ssid = cols[1];
                    if (!ssid) continue;
                    const signal = parseInt(cols[2], 10) || 0;
                    const security = cols[3].trim();
                    const band = root.parseBand(cols[4]);

                    const existing = bySsid[ssid];
                    if (!existing || inUse || (!existing.inUse && signal > existing.signal)) {
                        bySsid[ssid] = {
                            ssid: ssid,
                            signal: signal,
                            security: security,
                            band: band,
                            inUse: inUse
                        };
                    }
                }
                const list = Object.keys(bySsid).map((k) => bySsid[k]);
                list.sort((a, b) => {
                    if (a.inUse !== b.inUse) return a.inUse ? -1 : 1;
                    return b.signal - a.signal;
                });
                root.networks = list;
            }
        }
        onExited: {
            root.scanning = false;
        }
    }

    Process {
        id: radioProc
        property bool targetEnabled: true
        command: ["nmcli", "radio", "wifi", targetEnabled ? "on" : "off"]
        onExited: {
            if (radioProc.targetEnabled) {
                root.refreshNetworks(true);
            } else {
                root.networks = [];
            }
        }
    }

    Process {
        id: connectProc
        property string targetSsid: ""
        property string errOut: ""
        stderr: StdioCollector {
            onStreamFinished: connectProc.errOut = text.trim()
        }
        onExited: (exitCode) => {
            root.connecting = false;
            root.connectingSsid = "";
            if (exitCode !== 0) {
                root.lastError = connectProc.errOut || ("Failed to connect to " + connectProc.targetSsid);
            } else {
                root.lastError = "";
            }
            root.refreshNetworks(false);
        }
    }

    Process {
        id: disconnectProc
        command: ["nmcli", "device", "disconnect", root.wifiDevice]
        onExited: {
            root.lastError = "";
            root.refreshNetworks(false);
        }
    }

    function toggleWifi() {
        setWifiEnabled(!wifiEnabled);
    }

    function setWifiEnabled(enabled) {
        if (Networking.wifiEnabled !== enabled) {
            Networking.wifiEnabled = enabled;
        }
        radioProc.targetEnabled = enabled;
        radioProc.running = false;
        radioProc.running = true;
    }

    function refreshNetworks(rescan) {
        if (!wifiEnabled) {
            networks = [];
            return;
        }
        scanning = true;
        scanProc.rescan = !!rescan;
        scanProc.running = false;
        scanProc.running = true;
    }

    function connectToNetwork(ssid, password, isHidden) {
        if (!ssid || connecting) return;
        lastError = "";
        connecting = true;
        connectingSsid = ssid;
        connectProc.targetSsid = ssid;
        connectProc.errOut = "";

        const args = ["nmcli", "device", "wifi", "connect", ssid];
        if (password && password.length > 0) {
            args.push("password");
            args.push(password);
        }
        if (isHidden) {
            args.push("hidden");
            args.push("yes");
        }
        connectProc.command = args;
        connectProc.running = false;
        connectProc.running = true;
    }

    function disconnectActive() {
        if (disconnectProc.running) return;
        disconnectProc.running = true;
    }
}
