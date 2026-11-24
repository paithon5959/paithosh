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
        { id: "config", title: "Shell Config", detail: "Waiting to check...", status: "ok" },
        { id: "compositor", title: "Compositor IPC", detail: "Waiting to check...", status: "ok" },
        { id: "shader", title: "Gooey Shader", detail: "Waiting to check...", status: "ok" },
        { id: "cli", title: "Core CLI Tools", detail: "Waiting to check...", status: "ok" },
        { id: "disk", title: "Storage", detail: "Waiting to check...", status: "ok" },
        { id: "battery", title: "Battery", detail: "Waiting to check...", status: "ok" },
        { id: "thermal", title: "System Temperature", detail: "Waiting to check...", status: "ok" }
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
                        title: "Shell Config",
                        detail: cfgOk
                            ? (setOk ? "~/.config/paithosh/settings.json writable" : "Config dir ready (settings.json pending)")
                            : "~/.config/paithosh missing or not writable",
                        status: cfgOk ? "ok" : "warn"
                    },
                    {
                        id: "compositor",
                        title: "Compositor IPC",
                        detail: isHypr
                            ? ("Connected • " + TelemetryService.hyprVersion)
                            : ("KDE Preview Fallback (" + (root.sessionDesktop || "Wayland") + ")"),
                        status: isHypr ? "ok" : "warn"
                    },
                    {
                        id: "shader",
                        title: "Gooey Shader",
                        detail: qsbBytes > 0
                            ? ("gooey.frag.qsb compiled (" + (qsbBytes / 1024).toFixed(1) + " KB)")
                            : "gooey.frag.qsb missing — run build-shaders.sh",
                        status: qsbBytes > 0 ? "ok" : "error"
                    },
                    {
                        id: "cli",
                        title: "Core CLI Tools",
                        detail: missing === ""
                            ? "All core & media CLI tools available"
                            : ("Missing: " + missing),
                        status: missing === "" ? "ok" : "warn"
                    },
                    {
                        id: "disk",
                        title: "Storage",
                        detail: diskPct + "% used • " + diskAvail + " free of " + diskTotal + " on /",
                        status: diskPct >= 95 ? "error" : (diskPct >= 85 ? "warn" : "ok")
                    },
                    {
                        id: "battery",
                        title: "Battery",
                        detail: batDetail,
                        status: batStatus
                    },
                    {
                        id: "thermal",
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
                    font.family: Theme.fontSans
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

    component AboutPillBtn: Rectangle {
        id: btn
        property string label: ""
        property string iconName: ""
        property bool active: false
        property color activeBg: Theme.accent
        property color activeFg: Theme.accentFg
        signal triggered()

        implicitWidth: Math.max(30, btnRow.implicitWidth + (label !== "" ? 20 : 12))
        height: 28
        radius: 14
        clip: true
        color: active ? activeBg : (btnMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised)
        border.width: 1
        border.color: active ? activeBg : Theme.borderSubtle
        scale: btnMouse.pressed ? 0.94 : 1.0
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        RowLayout {
            id: btnRow
            anchors.centerIn: parent
            spacing: 5
            SvgIcon {
                visible: btn.iconName !== ""
                sourceName: btn.iconName
                iconSize: 12
                color: btn.active ? btn.activeFg : Theme.text
            }
            Text {
                visible: btn.label !== ""
                text: btn.label
                color: btn.active ? btn.activeFg : Theme.text
                font.family: Theme.fontSans
                font.pixelSize: 11
                font.weight: Font.DemiBold
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

    component MetaChip: Rectangle {
        id: chip
        property string text: ""
        property color dotColor: "transparent"
        property bool mono: false

        height: 22
        implicitWidth: chipRow.implicitWidth + 14
        radius: 11
        color: Theme.surfaceRaised
        border.width: 1
        border.color: Theme.borderSubtle
        clip: true

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5
            Rectangle {
                visible: chip.dotColor !== "transparent"
                width: 6; height: 6; radius: 3
                color: chip.dotColor
            }
            Text {
                text: chip.text
                color: Theme.textSub
                font.family: chip.mono ? Theme.fontMono : Theme.fontSans
                font.pixelSize: 10
                elide: Text.ElideRight
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

            // Dynamic Island emblem
            Rectangle {
                width: 44; height: 44; radius: 12
                color: Theme.surfaceRaised
                border.width: 1
                border.color: Theme.borderSubtle
                clip: true

                Column {
                    anchors.centerIn: parent
                    spacing: 3
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 24; height: 8; radius: 4
                        color: Theme.accent
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 3
                        Rectangle { width: 7; height: 4; radius: 2; color: Theme.textSub }
                        Rectangle { width: 12; height: 4; radius: 2; color: Theme.textMuted }
                    }
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
                        text: "Paithosh Shell"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    MetaChip {
                        text: "v" + root.shellVersion + " · " + root.gitBranch + "@" + root.gitCommit
                        mono: true
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
                AboutPillBtn {
                    iconName: root.copiedFeedback ? "check" : "copy"
                    label: root.copiedFeedback ? "Copied" : "Copy"
                    active: root.copiedFeedback
                    activeBg: Theme.ok
                    activeFg: Theme.pillBg
                    onTriggered: root.copySystemSummary()
                }
                AboutPillBtn {
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
            MetaChip {
                text: TelemetryService.kernel || "Linux"
                mono: true
            }
        }
        AboutRow {
            iconName: "settings"
            title: "Compositor"
            subtitle: TelemetryService.hyprVersion
            MetaChip {
                dotColor: CompositorService.isHyprland ? Theme.ok : Theme.warn
                text: CompositorService.isHyprland ? "Hyprland" : "KDE Preview"
            }
        }
        AboutRow {
            iconName: "keyboard"
            title: "Host & Shell"
            subtitle: TelemetryService.hostname + " • " + TelemetryService.shellName
            MetaChip {
                text: (root.shellState ? root.shellState.activeProfile : "default") + ".paish"
                mono: true
            }
        }
        AboutRow {
            iconName: "cpu"
            title: "Processor & Graphics"
            subtitle: TelemetryService.cpuModel + (TelemetryService.cpuCores !== "" ? (" (" + TelemetryService.cpuCores + ")") : "")
            MetaChip {
                text: TelemetryService.gpuName
            }
        }
        AboutRow {
            iconName: "hard-drive"
            title: "Memory & Storage"
            subtitle: "RAM " + TelemetryService.memDetail + " (" + TelemetryService.ramPct + "%) • " + TelemetryService.swapSummary
            MetaChip {
                text: TelemetryService.storageTotal + (TelemetryService.storageDetail !== "" ? (" • " + TelemetryService.storageDetail) : "")
                mono: true
            }
        }
    }

    // ==================== 3. HEALTH CHECK ====================
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 8

        AboutSectionLabel {
            Layout.topMargin: 0
            text: "Health Check"
        }

        MetaChip {
            dotColor: root.healthRunning
                ? Theme.info
                : (root.healthOkCount === root.healthTotalCount ? Theme.ok : Theme.warn)
            text: root.healthRunning
                ? "Checking..."
                : (root.healthOkCount + "/" + root.healthTotalCount + " Passed • " + root.lastCheckTime)
        }

        AboutPillBtn {
            height: 26
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
                iconName: modelData.status === "ok" ? "check" : (modelData.status === "error" ? "close" : "alert-triangle")
                title: modelData.title
                subtitle: modelData.detail

                Rectangle {
                    height: 22
                    implicitWidth: stRow.implicitWidth + 14
                    radius: 6
                    clip: true
                    color: Theme.surfaceRaised
                    border.width: 1
                    border.color: modelData.status === "ok"
                        ? Theme.borderSubtle
                        : (modelData.status === "error"
                            ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.35)
                            : Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.35))
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    RowLayout {
                        id: stRow
                        anchors.centerIn: parent
                        spacing: 5

                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            color: modelData.status === "ok"
                                ? Theme.ok
                                : (modelData.status === "error" ? Theme.danger : Theme.warn)
                            Behavior on color { ColorAnimation { duration: 180 } }
                        }

                        Text {
                            id: stLbl
                            text: modelData.status === "ok" ? "OK" : (modelData.status === "error" ? "Fail" : "Warn")
                            color: modelData.status === "ok"
                                ? Theme.textSub
                                : (modelData.status === "error" ? Theme.dangerText : Theme.warn)
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }
}
