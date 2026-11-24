pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // WireGuard state
    property var tunnels: []          // [{ name, path, active, endpoint, dns, address, allowedIps, userOwned }]
    property string activeTunnel: ""
    readonly property bool vpnActive: activeTunnel !== ""
    property bool busy: false
    property string busyTunnel: ""
    property string lastError: ""

    signal importCompleted()

    // Selected / active tunnel details for summary
    readonly property var currentTunnelObj: {
        for (let i = 0; i < tunnels.length; ++i) {
            if (tunnels[i].active) return tunnels[i];
        }
        return tunnels.length > 0 ? tunnels[0] : null;
    }
    readonly property string vpnEndpoint: currentTunnelObj && currentTunnelObj.endpoint ? currentTunnelObj.endpoint : "—"
    readonly property string vpnDns: currentTunnelObj && currentTunnelObj.dns ? currentTunnelObj.dns : "—"
    readonly property string vpnAddress: currentTunnelObj && currentTunnelObj.address ? currentTunnelObj.address : "—"

    // Proxy state
    property bool proxyEnabled: false
    property string proxyHost: "127.0.0.1"
    property int proxyPort: 7890
    property string socksHost: "127.0.0.1"
    property int socksPort: 7891
    property string noProxy: "localhost,127.0.0.1,::1"
    property bool proxyBusy: false

    readonly property string userWgDir: (Quickshell.env("HOME") || "/tmp") + "/.config/paithosh/wg"
    readonly property string proxyEnvPath: (Quickshell.env("HOME") || "/tmp") + "/.config/paithosh/proxy.env"

    Component.onCompleted: {
        refresh();
        loadProxySettings();
    }

    function refresh() {
        listProc.running = true;
    }

    function parseWgConfig(text) {
        const res = { endpoint: "", dns: "", address: "", allowedIps: "" };
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim();
            if (!line || line.startsWith("#") || line.startsWith(";")) continue;
            const eq = line.indexOf("=");
            if (eq === -1) continue;
            const key = line.slice(0, eq).trim().toLowerCase();
            const val = line.slice(eq + 1).trim();
            if (key === "endpoint" && !res.endpoint) res.endpoint = val;
            else if (key === "dns" && !res.dns) res.dns = val;
            else if (key === "address" && !res.address) res.address = val;
            else if (key === "allowedips" && !res.allowedIps) res.allowedIps = val;
        }
        return res;
    }

    function sanitizeName(name) {
        return name.trim().replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 15);
    }

    function toggleTunnel(name) {
        if (busy) return;
        let target = null;
        for (let i = 0; i < tunnels.length; ++i) {
            if (tunnels[i].name === name) {
                target = tunnels[i];
                break;
            }
        }
        if (!target) return;

        lastError = "";
        busy = true;
        busyTunnel = name;
        const action = target.active ? "down" : "up";
        const title = target.active ? "Disconnect WireGuard" : "Connect WireGuard";
        const desc = (target.active ? "Disconnect" : "Connect") + " tunnel \"" + name + "\" using wg-quick.";
        BackupService.runPrivileged(
            title,
            desc,
            target.active ? "Disconnect" : "Connect",
            ["wg-quick", action, target.path],
            (ok, parsed, out, err, code) => {
                root.busy = false;
                root.busyTunnel = "";
                if (!ok) {
                    const errText = (err || "").trim();
                    if (errText) {
                        root.lastError = errText.split("\n").slice(-2).join(" ");
                    } else if (!root.lastError) {
                        root.lastError = "wg-quick failed (exit " + code + ")";
                    }
                }
                root.refresh();
            },
            null,
            true
        );
    }

    function importConfigFile() {
        if (busy) return;
        lastError = "";
        filePickerProc.running = true;
    }

    function normalizeConfig(content) {
        let out = content.split("\n").map(line => {
            const m = line.match(/^(\s*(?:Address|DNS|AllowedIPs)\s*=\s*)(.+)$/i);
            if (!m) return line;
            const parts = m[2].split(",").map(s => s.trim()).filter(Boolean);
            const v4 = parts.filter(p => p.indexOf(":") === -1);
            return v4.length > 0 ? (m[1] + v4.join(", ")) : line;
        }).join("\n");
        if (!/^\s*MTU\s*=/im.test(out)) {
            out = out.replace(/(\[Interface\][^\n]*\n?)/i, "$1MTU = 1280\n");
        }
        return out;
    }

    function saveConfigText(rawName, content) {
        const name = sanitizeName(rawName);
        if (!name) {
            lastError = "Invalid tunnel name (use letters, numbers, - or _).";
            return false;
        }
        if (!content || content.indexOf("[Interface]") === -1) {
            lastError = "Invalid wg-quick config: missing [Interface] section.";
            return false;
        }
        lastError = "";
        const b64 = Qt.btoa(normalizeConfig(content));
        const dest = userWgDir + "/" + name + ".conf";
        saveConfigProc.command = [
            "bash", "-c",
            "mkdir -p \"$1\" && printf '%s' \"$2\" | base64 -d > \"$3\" && chmod 600 \"$3\"",
            "sh", userWgDir, b64, dest
        ];
        saveConfigProc.running = true;
        return true;
    }

    function deleteConfig(name) {
        if (busy) return;
        let target = null;
        for (let i = 0; i < tunnels.length; ++i) {
            if (tunnels[i].name === name) {
                target = tunnels[i];
                break;
            }
        }
        if (!target || !target.userOwned) return;
        if (target.active) {
            lastError = "Disconnect tunnel before deleting.";
            return;
        }
        lastError = "";
        deleteProc.command = ["rm", "-f", target.path];
        deleteProc.running = true;
    }

    function loadProxySettings() {
        proxyReadProc.running = true;
    }

    function applyProxySettings(enabled, hHost, hPort, sHost, sPort, noProx) {
        proxyEnabled = enabled;
        proxyHost = hHost.trim() || "127.0.0.1";
        proxyPort = parseInt(hPort, 10) || 7890;
        socksHost = sHost.trim() || proxyHost;
        socksPort = parseInt(sPort, 10) || 7891;
        noProxy = noProx.trim() || "localhost,127.0.0.1,::1";

        proxyBusy = true;
        const mode = proxyEnabled ? "manual" : "none";
        const envContent = proxyEnabled
            ? ("export HTTP_PROXY=\"http://" + proxyHost + ":" + proxyPort + "\"\n" +
               "export HTTPS_PROXY=\"http://" + proxyHost + ":" + proxyPort + "\"\n" +
               "export ALL_PROXY=\"socks5://" + socksHost + ":" + socksPort + "\"\n" +
               "export NO_PROXY=\"" + noProxy + "\"\n")
            : "# Proxy disabled\n";
        const b64Env = Qt.btoa(envContent);

        proxyWriteProc.command = [
            "bash", "-c",
            "gsettings set org.gnome.system.proxy mode \"$1\" && " +
            "gsettings set org.gnome.system.proxy.http host \"$2\" && " +
            "gsettings set org.gnome.system.proxy.http port \"$3\" && " +
            "gsettings set org.gnome.system.proxy.https host \"$2\" && " +
            "gsettings set org.gnome.system.proxy.https port \"$3\" && " +
            "gsettings set org.gnome.system.proxy.socks host \"$4\" && " +
            "gsettings set org.gnome.system.proxy.socks port \"$5\" && " +
            "mkdir -p \"$(dirname \"$6\")\" && printf '%s' \"$7\" | base64 -d > \"$6\"",
            "sh",
            mode,
            proxyHost,
            String(proxyPort),
            socksHost,
            String(socksPort),
            proxyEnvPath,
            b64Env
        ];
        proxyWriteProc.running = true;
    }

    // List active wireguard interfaces & .conf files
    Process {
        id: listProc
        command: [
            "bash", "-c",
            "mkdir -p \"$1\"; " +
            "echo '===ACTIVE==='; " +
            "ip -o link show type wireguard 2>/dev/null | awk -F': ' '{print $2}' | cut -d'@' -f1; " +
            "echo '===FILES==='; " +
            "for f in \"$1\"/*.conf /etc/wireguard/*.conf; do " +
            "  [ -e \"$f\" ] || continue; " +
            "  echo \"---FILE:$f---\"; " +
            "  cat \"$f\" 2>/dev/null || echo '__UNREADABLE__'; " +
            "done",
            "sh", root.userWgDir
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                let section = "";
                const activeSet = {};
                const parsed = [];
                let curPath = "";
                let curLines = [];

                function flushFile() {
                    if (!curPath) return;
                    const base = curPath.split("/").pop();
                    const name = base.replace(/\.conf$/, "");
                    const content = curLines.join("\n");
                    const meta = content.indexOf("__UNREADABLE__") !== -1
                        ? { endpoint: "Requires root to read", dns: "—", address: "—", allowedIps: "—" }
                        : root.parseWgConfig(content);
                    parsed.push({
                        name: name,
                        path: curPath,
                        active: !!activeSet[name],
                        endpoint: meta.endpoint || "—",
                        dns: meta.dns || "—",
                        address: meta.address || "—",
                        allowedIps: meta.allowedIps || "—",
                        userOwned: curPath.indexOf(root.userWgDir) === 0
                    });
                    curPath = "";
                    curLines = [];
                }

                for (let i = 0; i < lines.length; ++i) {
                    const l = lines[i];
                    if (l === "===ACTIVE===") { section = "active"; continue; }
                    if (l === "===FILES===") { section = "files"; continue; }
                    if (section === "active") {
                        const iface = l.trim();
                        if (iface) activeSet[iface] = true;
                    } else if (section === "files") {
                        if (l.startsWith("---FILE:") && l.endsWith("---")) {
                            flushFile();
                            curPath = l.slice(8, -3);
                        } else if (curPath) {
                            curLines.push(l);
                        }
                    }
                }
                flushFile();

                let act = "";
                for (let j = 0; j < parsed.length; ++j) {
                    if (parsed[j].active) {
                        act = parsed[j].name;
                        break;
                    }
                }
                if (!act) {
                    const keys = Object.keys(activeSet);
                    if (keys.length > 0) act = keys[0];
                }
                root.activeTunnel = act;
                root.tunnels = parsed;
            }
        }
    }

    Process {
        id: filePickerProc
        command: [
            "zenity", "--file-selection",
            "--title=Import WireGuard (.conf) Config",
            "--file-filter=WireGuard Config (*.conf) | *.conf",
            "--file-filter=All Files | *"
        ]
        property bool pickedFile: false
        onRunningChanged: if (running) pickedFile = false
        stdout: StdioCollector {
            onStreamFinished: {
                const picked = text.trim();
                if (!picked) return;
                filePickerProc.pickedFile = true;
                const base = picked.split("/").pop().replace(/\.conf$/i, "");
                const clean = root.sanitizeName(base) || "wg0";
                const dest = root.userWgDir + "/" + clean + ".conf";
                copyImportProc.command = [
                    "python3", "-c",
                    "import os, re, sys\ndir_, src, dst = sys.argv[1:4]\nos.makedirs(dir_, exist_ok=True)\nwith open(src, 'r', encoding='utf-8', errors='replace') as f: txt = f.read()\nlines = []\nfor line in txt.splitlines():\n    m = re.match(r'^(\\s*(?:Address|DNS|AllowedIPs)\\s*=\\s*)(.+)$', line, re.I)\n    if m:\n        v4 = [p.strip() for p in m.group(2).split(',') if p.strip() and ':' not in p]\n        if v4: line = m.group(1) + ', '.join(v4)\n    lines.append(line)\nout = '\\n'.join(lines) + '\\n'\nif not re.search(r'^\\s*MTU\\s*=', out, re.I | re.M):\n    out = re.sub(r'(\\[Interface\\][^\\n]*\\n?)', r'\\1MTU = 1280\\n', out, count=1, flags=re.I)\nwith open(dst, 'w', encoding='utf-8') as f: f.write(out)\nos.chmod(dst, 0o600)\n",
                    root.userWgDir, picked, dest
                ];
                copyImportProc.running = true;
            }
        }
        onExited: () => {
            if (!pickedFile) root.importCompleted();
        }
    }

    Process {
        id: copyImportProc
        onExited: (exitCode) => {
            if (exitCode !== 0) root.lastError = "Failed to import config file.";
            root.refresh();
            root.importCompleted();
        }
    }

    Process {
        id: saveConfigProc
        onExited: (exitCode) => {
            if (exitCode !== 0) root.lastError = "Failed to save config file.";
            root.refresh();
        }
    }

    Process {
        id: deleteProc
        onExited: () => root.refresh()
    }

    Process {
        id: proxyReadProc
        command: [
            "bash", "-c",
            "echo \"mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null)\"; " +
            "echo \"hhost=$(gsettings get org.gnome.system.proxy.http host 2>/dev/null)\"; " +
            "echo \"hport=$(gsettings get org.gnome.system.proxy.http port 2>/dev/null)\"; " +
            "echo \"shost=$(gsettings get org.gnome.system.proxy.socks host 2>/dev/null)\"; " +
            "echo \"sport=$(gsettings get org.gnome.system.proxy.socks port 2>/dev/null)\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                for (let i = 0; i < lines.length; ++i) {
                    const eq = lines[i].indexOf("=");
                    if (eq === -1) continue;
                    const k = lines[i].slice(0, eq);
                    const v = lines[i].slice(eq + 1).trim().replace(/^'|'$/g, "");
                    if (k === "mode") root.proxyEnabled = (v === "manual");
                    else if (k === "hhost" && v) root.proxyHost = v;
                    else if (k === "hport" && parseInt(v, 10) > 0) root.proxyPort = parseInt(v, 10);
                    else if (k === "shost" && v) root.socksHost = v;
                    else if (k === "sport" && parseInt(v, 10) > 0) root.socksPort = parseInt(v, 10);
                }
            }
        }
    }

    Process {
        id: proxyWriteProc
        onExited: (exitCode) => {
            root.proxyBusy = false;
            if (exitCode !== 0) root.lastError = "Failed to update system proxy.";
        }
    }
}
