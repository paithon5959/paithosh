import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import ".."
import "../services"
import "common"

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 12

    property var shellState: null

    // Shell & Runtime metadata
    property string shellVersion: "1.0.3"
    property string gitBranch: "master"
    property string gitCommit: "local"
    property string qsVersion: "Quickshell"
    property string qtVersion: "Qt 6"
    property string sessionDesktop: ""
    property bool copiedFeedback: false

    // Health check state
    property bool healthRunning: false
    property string lastCheckTime: "--:--:--"
    property int healthOkCount: 0
    property int healthTotalCount: 7
    property var healthItems: [
        { id: "config", icon: "document", title: "Shell Config", detail: "Waiting to check...", status: "ok" },
        { id: "compositor", icon: "layers", title: "Compositor IPC", detail: "Waiting to check...", status: "ok" },
        { id: "shader", icon: "sparkles", title: "Gooey Shader", detail: "Waiting to check...", status: "ok" },
        { id: "cli", icon: "terminal", title: "Core CLI Tools", detail: "Waiting to check...", status: "ok" },
        { id: "disk", icon: "hard-drive", title: "Storage", detail: "Waiting to check...", status: "ok" },
        { id: "battery", icon: "bolt", title: "Battery", detail: "Waiting to check...", status: "ok" },
        { id: "thermal", icon: "thermometer", title: "System Temperature", detail: "Waiting to check...", status: "ok" }
    ]

    readonly property string projectRoot: Quickshell.shellDir.replace(/\/shell\/?$/, "")
    readonly property string configDir: (Quickshell.env("HOME") || "~") + "/.config/paithosh"

    Component.onCompleted: {
        shellMetaProc.running = true;
        releaseProc.running = true;
        runHealthCheck();
    }

    onVisibleChanged: {
        if (visible) {
            TelemetryService.refreshSpecs();
            runHealthCheck();
        }
    }

    function runHealthCheck() {
        if (healthRunning) return;
        healthRunning = true;
        healthProc.running = false;
        healthProc.running = true;
    }

    function refreshAll() {
        TelemetryService.refreshSpecs();
        shellMetaProc.running = false;
        shellMetaProc.running = true;
        releaseProc.running = false;
        releaseProc.running = true;
        runHealthCheck();
    }

    function copySystemSummary() {
        const lines = [
            "Paithosh Shell v" + root.shellVersion + " (" + root.gitBranch + "@" + root.gitCommit + ")",
            "Runtime: " + root.qsVersion + " • " + root.qtVersion,
            "OS: " + TelemetryService.osName + " (" + TelemetryService.arch + ")",
            "Kernel: " + TelemetryService.kernel,
            "Compositor: " + TelemetryService.hyprVersion + (CompositorService.isHyprland ? " [Hyprland]" : " [KDE Preview]"),
            "Host: " + TelemetryService.hostname + " • Shell: " + TelemetryService.shellName,
            "CPU: " + TelemetryService.cpuModel + (TelemetryService.cpuCores ? " (" + TelemetryService.cpuCores + ")" : ""),
            "GPU: " + TelemetryService.gpuName,
            "Memory: " + TelemetryService.memDetail + " (" + TelemetryService.ramPct + "%)",
            "Storage: " + TelemetryService.storageTotal + " — " + TelemetryService.storageDetail,
            "Health: " + root.healthOkCount + "/" + root.healthTotalCount + " passed"
        ];
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | wl-copy 2>/dev/null || true", "sh", lines.join("\n")]);
        root.copiedFeedback = true;
        copyResetTimer.restart();
    }

    Timer {
        id: copyResetTimer
        interval: 2000
        onTriggered: root.copiedFeedback = false
    }

    Process {
        id: shellMetaProc
        command: [
            "sh", "-c",
            "printf 'QS=%s\\n' \"$(qs --version 2>/dev/null | head -n1 | sed 's/ (revision.*//')\"; " +
            "printf 'VER=%s\\n' \"$(git -C \"$1\" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')\"; " +
            "printf 'BRANCH=%s\\n' \"$(git -C \"$1\" rev-parse --abbrev-ref HEAD 2>/dev/null || echo local)\"; " +
            "printf 'HASH=%s\\n' \"$(git -C \"$1\" rev-parse --short HEAD 2>/dev/null || echo dev)\"; " +
            "printf 'QT=%s\\n' \"$(qmake6 -query QT_VERSION 2>/dev/null || qtdiag6 2>/dev/null | head -n1 | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+' || echo 6)\"; " +
            "printf 'DE=%s\\n' \"${XDG_CURRENT_DESKTOP:-Wayland}\"",
            "sh", root.projectRoot
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (text || "").trim().split("\n");
                for (let i = 0; i < lines.length; ++i) {
                    const eq = lines[i].indexOf("=");
                    if (eq === -1) continue;
                    const k = lines[i].slice(0, eq);
                    const v = lines[i].slice(eq + 1).trim();
                    if (!v) continue;
                    if (k === "QS") root.qsVersion = v;
                    else if (k === "VER") root.shellVersion = v;
                    else if (k === "BRANCH") root.gitBranch = v;
                    else if (k === "HASH") root.gitCommit = v;
                    else if (k === "QT") root.qtVersion = v.startsWith("Qt") ? v : ("Qt " + v);
                    else if (k === "DE") root.sessionDesktop = v;
                }
            }
        }
    }

    Process {
        id: releaseProc
        command: [
            "python3", "-c",
            "import json, urllib.request\n" +
            "url = 'https://api.github.com/repos/paithon5959/paithosh/releases/latest'\n" +
            "req = urllib.request.Request(url, headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'paithosh-shell'})\n" +
            "with urllib.request.urlopen(req, timeout=5) as resp:\n" +
            "    d = json.loads(resp.read().decode('utf-8'))\n" +
            "tag = (d.get('tag_name') or '').lstrip('v').strip()\n" +
            "if tag: print(tag)\n"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const ver = (text || "").trim();
                if (ver) root.shellVersion = ver;
            }
        }
    }

    Process {
        id: healthProc
        command: [
            "sh", "-c",
            "CFG_OK=0; [ -d \"$1\" ] && [ -w \"$1\" ] && CFG_OK=1; " +
            "SET_OK=0; [ -f \"$1/settings.json\" ] && SET_OK=1; " +
            "QSB_SIZE=0; [ -f \"$2/shell/assets/shaders/gooey.frag.qsb\" ] && QSB_SIZE=$(wc -c < \"$2/shell/assets/shaders/gooey.frag.qsb\" 2>/dev/null || echo 0); " +
            "MISSING=''; " +
            "for cmd in hyprctl hyprcursor-util wl-copy nmcli pw-play grim slurp cliphist wf-recorder python3 unzip xdg-open; do command -v \"$cmd\" >/dev/null 2>&1 || MISSING=\"$MISSING $cmd\"; done; " +
            "if ! command -v wpctl >/dev/null 2>&1 && ! command -v pactl >/dev/null 2>&1; then MISSING=\"$MISSING wpctl/pactl\"; fi; " +
            "DISK_LINE=$(df -hP / 2>/dev/null | tail -n1); " +
            "DISK_PCT=$(printf '%s' \"$DISK_LINE\" | awk '{print $5}' | tr -d '%'); " +
            "DISK_AVAIL=$(printf '%s' \"$DISK_LINE\" | awk '{print $4}'); " +
            "DISK_TOTAL=$(printf '%s' \"$DISK_LINE\" | awk '{print $2}'); " +
            "BAT_DIR=''; for d in /sys/class/power_supply/BAT*; do [ -d \"$d\" ] && BAT_DIR=\"$d\" && break; done; " +
            "BAT_CAP=''; BAT_STAT='AC'; BAT_HLTH=''; " +
            "if [ -n \"$BAT_DIR\" ]; then " +
            "  BAT_CAP=$(cat \"$BAT_DIR/capacity\" 2>/dev/null || echo ''); " +
            "  BAT_STAT=$(cat \"$BAT_DIR/status\" 2>/dev/null || echo 'Unknown'); " +
            "  BAT_FULL=$(cat \"$BAT_DIR/energy_full\" \"$BAT_DIR/charge_full\" 2>/dev/null | head -n1); " +
            "  BAT_DES=$(cat \"$BAT_DIR/energy_full_design\" \"$BAT_DIR/charge_full_design\" 2>/dev/null | head -n1); " +
            "  if [ -n \"$BAT_FULL\" ] && [ -n \"$BAT_DES\" ] && [ \"$BAT_DES\" -gt 0 ] 2>/dev/null; then " +
            "    BAT_HLTH=$(( BAT_FULL * 100 / BAT_DES )); [ \"$BAT_HLTH\" -gt 100 ] && BAT_HLTH=100; " +
            "  fi; " +
            "fi; " +
            "TEMP_C=0; TEMP_SRC=''; " +
            "for z in /sys/class/thermal/thermal_zone*; do " +
            "  [ -r \"$z/temp\" ] || continue; " +
            "  ZT=$(cat \"$z/type\" 2>/dev/null || echo ''); " +
            "  TV=$(cat \"$z/temp\" 2>/dev/null || echo 0); " +
            "  TC=$(( TV > 1000 ? TV / 1000 : TV )); " +
            "  case \"$ZT\" in x86_pkg_temp|k10temp|coretemp|Tctl|Package*) TEMP_C=$TC; TEMP_SRC=\"$ZT\"; break ;; esac; " +
            "  if [ \"$TC\" -gt \"$TEMP_C\" ]; then TEMP_C=$TC; TEMP_SRC=\"$ZT\"; fi; " +
            "done; " +
            "NOW=$(date '+%H:%M:%S'); " +
            "printf 'CFG=%s\\nSET=%s\\nQSB=%s\\nMISSING=%s\\nDISK_PCT=%s\\nDISK_AVAIL=%s\\nDISK_TOTAL=%s\\nBAT_CAP=%s\\nBAT_STAT=%s\\nBAT_HLTH=%s\\nTEMP_C=%s\\nTEMP_SRC=%s\\nNOW=%s\\n' " +
            "\"$CFG_OK\" \"$SET_OK\" \"$QSB_SIZE\" \"${MISSING# }\" \"${DISK_PCT:-0}\" \"${DISK_AVAIL:-?}\" \"${DISK_TOTAL:-?}\" \"$BAT_CAP\" \"$BAT_STAT\" \"$BAT_HLTH\" \"$TEMP_C\" \"$TEMP_SRC\" \"$NOW\"",
            "sh", root.configDir, root.projectRoot
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                const lines = (text || "").trim().split("\n");
                for (let i = 0; i < lines.length; ++i) {
                    const eq = lines[i].indexOf("=");
                    if (eq !== -1) map[lines[i].slice(0, eq)] = lines[i].slice(eq + 1).trim();
                }

                const cfgOk = map.CFG === "1";
                const setOk = map.SET === "1";
                const qsbBytes = parseInt(map.QSB || "0", 10) || 0;
                const missing = map.MISSING || "";
                const diskPct = parseInt(map.DISK_PCT || "0", 10) || 0;
                const diskAvail = map.DISK_AVAIL || "--";
                const diskTotal = map.DISK_TOTAL || "--";
                const hasBat = (map.BAT_CAP || "") !== "";
                const batCap = hasBat ? (parseInt(map.BAT_CAP, 10) || 0) : PowerService.batteryPct;
                const batStat = hasBat ? (map.BAT_STAT || "Unknown") : (PowerService.hasBattery ? (PowerService.charging ? "Charging" : "Discharging") : "AC Power");
                const batHealth = (map.BAT_HLTH || "") !== "" ? (parseInt(map.BAT_HLTH, 10) || 0) : -1;
                const tempC = parseInt(map.TEMP_C || "0", 10) || TelemetryService.cpuTempC;
                const tempSrc = map.TEMP_SRC || "";
                root.lastCheckTime = map.NOW || "--:--:--";

                const isHypr = CompositorService.isHyprland;

                let batDetail = "AC Power • No battery detected";
                let batStatus = "ok";
                if (hasBat || PowerService.hasBattery) {
                    batDetail = batCap + "% • " + batStat + (batHealth >= 0 ? (" • Health " + batHealth + "%") : "");
                    const discharging = batStat.toLowerCase() === "discharging";
                    if (discharging && batCap <= 5) batStatus = "error";
                    else if ((discharging && batCap <= 15) || (batHealth >= 0 && batHealth < 60)) batStatus = "warn";
                }

                const tempLabel = tempC >= 90 ? "Overheating" : (tempC >= 80 ? "Warm" : "Normal");
                const tempStatus = tempC >= 90 ? "error" : (tempC >= 80 ? "warn" : "ok");
                const tempDetail = "CPU " + tempC + "°C" + (tempSrc !== "" ? (" (" + tempSrc + ")") : "") + " • " + tempLabel;

                const items = [
                    {
                        id: "config",
                        icon: "document",
                        title: "Shell Config",
                        detail: cfgOk
                            ? (setOk ? "~/.config/paithosh/settings.json writable" : "Config dir ready (settings.json pending)")
                            : "~/.config/paithosh missing or not writable",
                        status: cfgOk ? "ok" : "warn"
                    },
                    {
                        id: "compositor",
                        icon: "layers",
                        title: "Compositor IPC",
                        detail: isHypr
                            ? ("Connected • " + TelemetryService.hyprVersion)
                            : ("KDE Preview Fallback (" + (root.sessionDesktop || "Wayland") + ")"),
                        status: isHypr ? "ok" : "warn"
                    },
                    {
                        id: "shader",
                        icon: "sparkles",
                        title: "Gooey Shader",
                        detail: qsbBytes > 0
                            ? ("gooey.frag.qsb compiled (" + (qsbBytes / 1024).toFixed(1) + " KB)")
                            : "gooey.frag.qsb missing — run build-shaders.sh",
                        status: qsbBytes > 0 ? "ok" : "error"
                    },
                    {
                        id: "cli",
                        icon: "terminal",
                        title: "Core CLI Tools",
                        detail: missing === ""
                            ? "All core & media CLI tools available"
                            : ("Missing: " + missing),
                        status: missing === "" ? "ok" : "warn"
                    },
                    {
                        id: "disk",
                        icon: "hard-drive",
                        title: "Storage",
                        detail: diskPct + "% used • " + diskAvail + " free of " + diskTotal + " on /",
                        status: diskPct >= 95 ? "error" : (diskPct >= 85 ? "warn" : "ok")
                    },
                    {
                        id: "battery",
                        icon: "bolt",
                        title: "Battery",
                        detail: batDetail,
                        status: batStatus
                    },
                    {
                        id: "thermal",
                        icon: "thermometer",
                        title: "System Temperature",
                        detail: tempDetail,
                        status: tempStatus
                    }
                ];

                let okCount = 0;
                for (let j = 0; j < items.length; ++j) {
                    if (items[j].status === "ok") okCount++;
                }
                root.healthOkCount = okCount;
                root.healthTotalCount = items.length;
                root.healthItems = items;
                root.healthRunning = false;
            }
        }
    }

    // ==================== NATIVE PAITHOSH PRIMITIVES ====================
    component AboutSectionLabel: Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        font.family: Theme.fontSans
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: Theme.textMuted
        elide: Text.ElideRight
    }

    component AboutGroup: Rectangle {
        default property alias rows: groupCol.data
        Layout.fillWidth: true
        implicitHeight: groupCol.implicitHeight
        radius: 12
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle
        clip: true
        Behavior on implicitHeight { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: groupCol
            width: parent.width
            spacing: 0
        }
    }

    component AboutRow: Item {
        id: aRow
        property string iconName: ""
        property string title: ""
        property string subtitle: ""
        property bool monoSubtitle: false
        property bool showDivider: true
        default property alias control: ctrlSlot.data

        Layout.fillWidth: true
        implicitHeight: Math.max(54, rowLay.implicitHeight + 20)
        clip: true

        Rectangle {
            visible: aRow.showDivider
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.borderSubtle
        }

        RowLayout {
            id: rowLay
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 12

            Rectangle {
                visible: aRow.iconName !== ""
                width: 30; height: 30; radius: 8
                color: Theme.surfaceRaised
                border.width: 1; border.color: Theme.borderSubtle
                clip: true
                SvgIcon {
                    anchors.centerIn: parent
                    sourceName: aRow.iconName
                    iconSize: 15
                    color: Theme.textSub
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: aRow.title
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    visible: aRow.subtitle !== ""
                    Layout.fillWidth: true
                    text: aRow.subtitle
                    color: Theme.textSub
                    font.family: aRow.monoSubtitle ? Theme.fontMono : Theme.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: ctrlSlot
                spacing: 8
            }
        }
    }

    component AboutActionBtn: Rectangle {
        id: btn
        property string label: ""
        property string iconName: ""
        property bool active: false
        property color activeBg: Theme.accent
        property color activeFg: Theme.accentFg
        signal triggered()

        implicitWidth: Math.max(30, btnRow.implicitWidth + (label !== "" ? 20 : 12))
        height: 30
        radius: 8
        clip: true
        color: active ? activeBg : (btnMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised)
        border.width: 1
        border.color: active ? activeBg : Theme.borderSubtle
        scale: btnMouse.pressed ? 0.94 : 1.0
        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

        RowLayout {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6
            SvgIcon {
                visible: btn.iconName !== ""
                sourceName: btn.iconName
                iconSize: 13
                color: btn.active ? btn.activeFg : Theme.text
            }
            Text {
                visible: btn.label !== ""
                text: btn.label
                color: btn.active ? btn.activeFg : Theme.text
                font.family: Theme.fontSans
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.triggered()
        }
    }

    component AboutExpandableSection: Rectangle {
        id: expRoot
        property bool expanded: false
        property string iconName: "sliders"
        property string title: "Hardware & Runtime Details"
        property string subtitle: "Kernel, graphics, storage & session info"
        default property alias content: expCol.data

        Layout.fillWidth: true
        implicitHeight: expHeader.height + (expanded ? expBody.implicitHeight : 0)
        radius: 12
        color: Theme.cardBg
        border.width: 1
        border.color: expMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : Theme.borderSubtle
        scale: expMouse.pressed ? 0.99 : 1.0
        clip: true
        Behavior on implicitHeight { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

        Rectangle {
            id: expHeader
            width: parent.width
            height: 54
            color: expMouse.containsMouse ? Theme.cardHover : "transparent"
            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12

                Rectangle {
                    width: 30; height: 30; radius: 8
                    color: Theme.surfaceRaised
                    border.width: 1; border.color: Theme.borderSubtle
                    clip: true
                    SvgIcon {
                        anchors.centerIn: parent
                        sourceName: expRoot.iconName
                        iconSize: 15
                        color: expMouse.containsMouse ? Theme.text : Theme.textSub
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: expRoot.title
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: expRoot.subtitle
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: 26; height: 26; radius: 8
                    color: expMouse.containsMouse ? Theme.surfaceRaised : "transparent"
                    border.width: 1
                    border.color: expMouse.containsMouse ? Theme.borderSubtle : "transparent"
                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    SvgIcon {
                        anchors.centerIn: parent
                        sourceName: "chevron-right"
                        iconSize: 14
                        color: expMouse.containsMouse ? Theme.text : Theme.textSub
                        rotation: expRoot.expanded ? 90 : 0
                        Behavior on rotation { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
                    }
                }
            }

            MouseArea {
                id: expMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: expRoot.expanded = !expRoot.expanded
            }
        }

        Item {
            id: expBody
            y: expHeader.height
            width: parent.width
            implicitHeight: expCol.implicitHeight
            opacity: expRoot.expanded ? 1.0 : 0.0
            enabled: expRoot.expanded
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            ColumnLayout {
                id: expCol
                width: parent.width
                spacing: 0
            }
        }
    }

    // ==================== 1. SHELL OVERVIEW CARD ====================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: heroRow.implicitHeight + 24
        radius: 12
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle
        clip: true

        RowLayout {
            id: heroRow
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            // Paithosh Orbital Nucleus emblem
            Rectangle {
                width: 44; height: 44; radius: 10
                color: Theme.surfaceRaised
                border.width: 1
                border.color: Theme.borderSubtle
                clip: true

                SvgIcon {
                    anchors.centerIn: parent
                    sourceName: "paithosh"
                    iconSize: 26
                    preserveColor: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.alignment: Qt.AlignBaseline
                        text: "Paithosh Shell"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.alignment: Qt.AlignBaseline
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "v" + root.shellVersion + " · " + root.gitBranch + "@" + root.gitCommit
                        color: Theme.textSub
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.qsVersion + " • " + root.qtVersion + " • " + TelemetryService.uptimeText
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                spacing: 6
                AboutActionBtn {
                    iconName: root.copiedFeedback ? "check" : "copy"
                    label: root.copiedFeedback ? "Copied" : "Copy"
                    active: root.copiedFeedback
                    activeBg: Theme.accent
                    activeFg: Theme.accentFg
                    onTriggered: root.copySystemSummary()
                }
                AboutActionBtn {
                    iconName: "refresh"
                    onTriggered: root.refreshAll()
                }
            }
        }
    }

    // ==================== 2. SYSTEM & HARDWARE ====================
    AboutSectionLabel { text: "System & Hardware" }

    AboutGroup {
        AboutRow {
            showDivider: false
            iconName: "terminal"
            title: "OS"
            subtitle: TelemetryService.osName + " (" + TelemetryService.arch + ")"
        }
        AboutRow {
            iconName: "settings"
            title: "Compositor"
            subtitle: TelemetryService.hyprVersion + (CompositorService.isHyprland ? "" : " • KDE Preview")
        }
        AboutRow {
            iconName: "keyboard"
            title: "Host & Shell"
            subtitle: TelemetryService.hostname + " • " + TelemetryService.shellName
        }
        AboutRow {
            iconName: "cpu"
            title: "Processor"
            subtitle: TelemetryService.cpuModel + (TelemetryService.cpuCores !== "" ? (" (" + TelemetryService.cpuCores + ")") : "")
        }
        AboutRow {
            iconName: "hard-drive"
            title: "Memory & Storage"
            monoSubtitle: true
            subtitle: "RAM " + TelemetryService.memDetail + " (" + TelemetryService.ramPct + "%) • " + TelemetryService.storageTotal
        }
    }

    AboutExpandableSection {
        iconName: "sliders"
        title: "Hardware & Runtime Details"
        subtitle: "Kernel, graphics, storage breakdown & active profile"

        AboutRow {
            iconName: "code"
            title: "Kernel"
            monoSubtitle: true
            subtitle: TelemetryService.kernel || "Linux"
        }
        AboutRow {
            iconName: "monitor"
            title: "Graphics"
            subtitle: TelemetryService.gpuName || "Integrated / Unknown"
        }
        AboutRow {
            iconName: "archive"
            title: "Swap & Storage"
            monoSubtitle: true
            subtitle: TelemetryService.swapSummary + (TelemetryService.storageDetail !== "" ? (" • " + TelemetryService.storageDetail) : "")
        }
        AboutRow {
            iconName: "layers"
            title: "Active Profile"
            monoSubtitle: true
            subtitle: (root.shellState ? root.shellState.activeProfile : "default") + ".paish"
        }
        AboutRow {
            iconName: "info"
            title: "Session & Runtime"
            subtitle: (root.sessionDesktop || "Wayland") + " • " + root.qsVersion + " • " + root.qtVersion
        }
    }

    // ==================== 3. HEALTH CHECK ====================
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 10

        AboutSectionLabel {
            Layout.topMargin: 0
            text: "Health Check"
        }

        RowLayout {
            spacing: 5
            SvgIcon {
                sourceName: root.healthRunning
                    ? "clock"
                    : (root.healthOkCount === root.healthTotalCount ? "check" : "alert-triangle")
                iconSize: 13
                color: root.healthRunning
                    ? Theme.info
                    : (root.healthOkCount === root.healthTotalCount ? Theme.accent : Theme.warn)
            }
            Text {
                text: root.healthRunning
                    ? "Checking..."
                    : (root.healthOkCount + "/" + root.healthTotalCount + " Passed • " + root.lastCheckTime)
                color: root.healthRunning
                    ? Theme.info
                    : (root.healthOkCount === root.healthTotalCount ? Theme.accent : Theme.warn)
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.weight: Font.Medium
                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
            }
        }

        AboutActionBtn {
            height: 28
            iconName: root.healthRunning ? "clock" : "refresh"
            label: root.healthRunning ? "Running" : "Run Check"
            onTriggered: root.runHealthCheck()
        }
    }

    AboutGroup {
        Repeater {
            model: root.healthItems
            delegate: AboutRow {
                required property var modelData
                required property int index
                showDivider: index > 0
                iconName: modelData.icon || "info"
                title: modelData.title
                subtitle: modelData.detail

                SvgIcon {
                    sourceName: modelData.status === "ok"
                        ? "check"
                        : (modelData.status === "error" ? "close" : "alert-triangle")
                    iconSize: 16
                    color: modelData.status === "ok"
                        ? Theme.accent
                        : (modelData.status === "error" ? Theme.dangerText : Theme.warn)
                }
            }
        }
    }
}
