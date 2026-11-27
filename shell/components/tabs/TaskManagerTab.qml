import QtQuick
import QtQuick.Layouts
import "../.."
import ".."
import "../../services"
import "../common"

Item {
    id: root

    property string procFilter: ""
    property string activeSection: "apps" // "apps" | "procs"

    readonly property var filteredApps: {
        const q = procFilter.trim().toLowerCase();
        const src = TelemetryService.appList || [];
        if (q === "") return src;
        const out = [];
        for (let i = 0; i < src.length; ++i) {
            const nameMatch = (src[i].name || "").toLowerCase().indexOf(q) !== -1;
            const titleMatch = (src[i].title || "").toLowerCase().indexOf(q) !== -1;
            if (nameMatch || titleMatch) out.push(src[i]);
        }
        return out;
    }

    readonly property var filteredProcs: {
        const q = procFilter.trim().toLowerCase();
        const src = TelemetryService.processList || [];
        if (q === "") return src;
        const out = [];
        for (let i = 0; i < src.length; ++i) {
            if (src[i].name.toLowerCase().indexOf(q) !== -1) out.push(src[i]);
        }
        return out;
    }

    implicitWidth: 468
    implicitHeight: col.implicitHeight

    function animateSparklines() {
        cpuSpark.animateDraw();
        ramSpark.animateDraw();
        gpuSpark.animateDraw();
        netSpark.animateDraw();
    }

    onActiveSectionChanged: listSwitchAnim.restart()

    SequentialAnimation {
        id: listSwitchAnim
        ParallelAnimation {
            NumberAnimation { target: listContainer; property: "opacity"; from: 0.35; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
            NumberAnimation { target: listContainer; property: "y"; from: 6; to: 0; duration: 220; easing.type: Easing.OutCubic }
        }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        // CPU & RAM Sparkline Cards
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // CPU Sparkline Card
            Rectangle {
                readonly property bool isHigh: TelemetryService.cpuPct >= 85
                readonly property bool isCrit: TelemetryService.cpuPct >= 95
                readonly property color metricColor: isCrit ? Theme.danger : (isHigh ? Theme.warn : Theme.accent)

                Layout.fillWidth: true
                height: 92
                radius: 14
                color: Theme.cardBg
                border.width: 1
                border.color: isCrit
                    ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.45)
                    : (isHigh ? Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.40) : Theme.borderSubtle)
                clip: true

                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        SvgIcon {
                            sourceName: "cpu"
                            iconSize: 14
                            color: Theme.textSub
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: "CPU"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: TelemetryService.cpuPct + "%"
                            color: parent.parent.parent.isCrit
                                ? Theme.dangerText
                                : (parent.parent.parent.isHigh ? Theme.warn : Theme.text)
                            font.family: Theme.fontMono
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                    }

                    Sparkline {
                        id: cpuSpark
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        points: TelemetryService.cpuHistory
                        lineColor: parent.parent.metricColor
                    }
                }
            }

            // RAM Sparkline Card
            Rectangle {
                readonly property bool isHigh: TelemetryService.ramPct >= 85
                readonly property bool isCrit: TelemetryService.ramPct >= 95
                readonly property color metricColor: isCrit ? Theme.danger : (isHigh ? Theme.warn : Theme.accent)

                Layout.fillWidth: true
                height: 92
                radius: 14
                color: Theme.cardBg
                border.width: 1
                border.color: isCrit
                    ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.45)
                    : (isHigh ? Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.40) : Theme.borderSubtle)
                clip: true

                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        SvgIcon {
                            sourceName: "activity"
                            iconSize: 14
                            color: Theme.textSub
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: "RAM"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: TelemetryService.ramPct + "%"
                            color: parent.parent.parent.isCrit
                                ? Theme.dangerText
                                : (parent.parent.parent.isHigh ? Theme.warn : Theme.text)
                            font.family: Theme.fontMono
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                    }

                    Sparkline {
                        id: ramSpark
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        points: TelemetryService.ramHistory
                        lineColor: parent.parent.metricColor
                    }
                }
            }
        }

        // GPU & Network (Upload / Download) Sparkline Cards
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // GPU Sparkline Card
            Rectangle {
                readonly property bool isHigh: TelemetryService.gpuPct >= 85
                readonly property bool isCrit: TelemetryService.gpuPct >= 95
                readonly property color metricColor: isCrit ? Theme.danger : (isHigh ? Theme.warn : Theme.accent)

                Layout.fillWidth: true
                height: 92
                radius: 14
                color: Theme.cardBg
                border.width: 1
                border.color: isCrit
                    ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.45)
                    : (isHigh ? Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.40) : Theme.borderSubtle)
                clip: true

                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        SvgIcon {
                            sourceName: "monitor"
                            iconSize: 14
                            color: Theme.textSub
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: "GPU"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: TelemetryService.gpuDetail
                            visible: text.length > 0
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                        }
                        Item {
                            Layout.fillWidth: true
                            visible: TelemetryService.gpuDetail.length === 0
                        }
                        Text {
                            text: TelemetryService.gpuPct + "%"
                            color: parent.parent.parent.isCrit
                                ? Theme.dangerText
                                : (parent.parent.parent.isHigh ? Theme.warn : Theme.text)
                            font.family: Theme.fontMono
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                    }

                    Sparkline {
                        id: gpuSpark
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        points: TelemetryService.gpuHistory
                        lineColor: parent.parent.metricColor
                    }
                }
            }

            // Network Upload & Download Sparkline Card
            Rectangle {
                Layout.fillWidth: true
                height: 92
                radius: 14
                color: Theme.cardBg
                border.width: 1
                border.color: Theme.borderSubtle
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        SvgIcon {
                            sourceName: "globe"
                            iconSize: 14
                            color: Theme.textSub
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: "NET"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "↓" + TelemetryService.netDownText
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                        }
                        Text {
                            text: "↑" + TelemetryService.netUpText
                            color: Theme.info
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                        }
                    }

                    Sparkline {
                        id: netSpark
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        points: TelemetryService.netDownHistory
                        lineColor: Theme.accent
                        secondaryPoints: TelemetryService.netUpHistory
                        secondaryLineColor: Theme.info
                    }
                }
            }
        }

        // System Meta Strip
        Rectangle {
            readonly property bool tempWarn: TelemetryService.cpuTempC >= 75
            readonly property bool tempCrit: TelemetryService.cpuTempC >= 90

            Layout.fillWidth: true
            height: 34
            radius: 12
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.04)
            border.width: 1
            border.color: tempCrit
                ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.40)
                : Theme.borderSubtle
            clip: true

            Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                RowLayout {
                    spacing: 4
                    Layout.minimumWidth: 0

                    SvgIcon {
                        sourceName: "thermometer"
                        iconSize: 12
                        color: parent.parent.parent.tempCrit
                            ? Theme.dangerText
                            : (parent.parent.parent.tempWarn ? Theme.warn : Theme.textSub)
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: TelemetryService.cpuTempC > 0 ? (TelemetryService.cpuTempC + "°C") : "--°C"
                        color: parent.parent.parent.tempCrit
                            ? Theme.dangerText
                            : (parent.parent.parent.tempWarn ? Theme.warn : Theme.textSub)
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: TelemetryService.memSummary
                    color: Theme.textSub
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: TelemetryService.swapSummary
                    color: Theme.textSub
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: TelemetryService.uptimeText
                    color: Theme.textSub
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                }
            }
        }

        // Section Switcher: Applications | Processes
        Rectangle {
            Layout.fillWidth: true
            height: 34
            radius: 12
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
            border.width: 1
            border.color: Theme.borderSubtle
            clip: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 4

                // Applications Tab
                Rectangle {
                    readonly property bool selected: root.activeSection === "apps"

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    radius: 9
                    clip: true
                    color: selected
                        ? Theme.accent
                        : (appsTabMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08) : "transparent")
                    scale: appsTabMouse.pressed ? 0.96 : 1.0

                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                    RowLayout {
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, Math.max(0, parent.width - 12))
                        spacing: 6

                        Text {
                            text: "Applications"
                            color: parent.parent.selected ? Theme.accentFg : (appsTabMouse.containsMouse ? Theme.text : Theme.textSub)
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.minimumWidth: 0
                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        Rectangle {
                            height: 16
                            width: Math.max(20, appCountText.implicitWidth + 10)
                            radius: 5
                            color: parent.parent.selected
                                ? Qt.rgba(Theme.accentFg.r, Theme.accentFg.g, Theme.accentFg.b, 0.16)
                                : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Text {
                                id: appCountText
                                anchors.centerIn: parent
                                text: String(TelemetryService.appList ? TelemetryService.appList.length : 0)
                                color: parent.parent.parent.selected ? Theme.accentFg : Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    MouseArea {
                        id: appsTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeSection = "apps"
                    }
                }

                // Processes Tab
                Rectangle {
                    readonly property bool selected: root.activeSection === "procs"

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    radius: 9
                    clip: true
                    color: selected
                        ? Theme.accent
                        : (procsTabMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08) : "transparent")
                    scale: procsTabMouse.pressed ? 0.96 : 1.0

                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                    RowLayout {
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, Math.max(0, parent.width - 12))
                        spacing: 6

                        Text {
                            text: "Processes"
                            color: parent.parent.selected ? Theme.accentFg : (procsTabMouse.containsMouse ? Theme.text : Theme.textSub)
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.minimumWidth: 0
                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        Rectangle {
                            height: 16
                            width: Math.max(20, procCountText.implicitWidth + 10)
                            radius: 5
                            color: parent.parent.selected
                                ? Qt.rgba(Theme.accentFg.r, Theme.accentFg.g, Theme.accentFg.b, 0.16)
                                : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Text {
                                id: procCountText
                                anchors.centerIn: parent
                                text: String(TelemetryService.processList ? TelemetryService.processList.length : 0)
                                color: parent.parent.parent.selected ? Theme.accentFg : Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    MouseArea {
                        id: procsTabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeSection = "procs"
                    }
                }
            }
        }

        // Process / Application Search Input
        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: 12
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, procInput.activeFocus ? 0.11 : 0.07)
            border.width: 1
            border.color: procInput.activeFocus
                ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.40)
                : Theme.borderSubtle
            clip: true

            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 8

                SvgIcon {
                    sourceName: "search"
                    iconSize: 15
                    color: procInput.activeFocus ? Theme.text : Theme.textSub
                    Layout.alignment: Qt.AlignVCenter
                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                AnimatedTextInput {
                    id: procInput
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    verticalAlignment: TextInput.AlignVCenter
                    textColor: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    clip: true
                    selectByMouse: true
                    onTextChanged: root.procFilter = text
                    Keys.onEscapePressed: {
                        if (text.length > 0) {
                            text = "";
                        } else {
                            focus = false;
                        }
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: root.activeSection === "apps"
                            ? "Filter applications (firefox, kitty, code...)"
                            : "Filter processes (kitty, firefox, code, pipewire...)"
                        color: Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        visible: procInput.text === ""
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: 22
                    height: 22
                    radius: 7
                    color: clearMouse.containsMouse ? Theme.cardHover : "transparent"
                    opacity: procInput.text.length > 0 ? 1.0 : 0.0
                    visible: opacity > 0.01
                    scale: clearMouse.pressed ? 0.90 : 1.0
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                    SvgIcon {
                        anchors.centerIn: parent
                        sourceName: "close"
                        iconSize: 12
                        color: Theme.textSub
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: procInput.text = ""
                    }
                }
            }
        }

        // Scrollable Applications / Processes List
        Item {
            Layout.fillWidth: true
            height: 186
            clip: true

            readonly property var activeModel: root.activeSection === "apps" ? root.filteredApps : root.filteredProcs

            Item {
                id: listContainer
                width: parent.width
                height: parent.height
                y: 0

                Text {
                    anchors.centerIn: parent
                    visible: parent.parent.activeModel.length === 0
                    text: root.activeSection === "apps" ? "No matching applications" : "No matching processes"
                    color: Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                }

                ListView {
                    id: procListView
                    anchors.fill: parent
                    visible: parent.parent.activeModel.length > 0
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: parent.parent.activeModel

                    delegate: Item {
                        id: procWrap
                        required property var modelData
                        property bool removing: false

                        width: procListView.width
                        height: removing ? 0 : 44
                        opacity: removing ? 0.0 : 1.0
                        clip: true

                        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        Timer {
                            id: killDelay
                            interval: 220
                            repeat: false
                            onTriggered: {
                                if (root.activeSection === "apps") {
                                    TelemetryService.closeApp(procWrap.modelData.address, procWrap.modelData.pid);
                                } else {
                                    TelemetryService.killProcess(procWrap.modelData.pid);
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 44
                            x: procWrap.removing ? 18 : 0
                            radius: 14
                            color: pMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                            border.width: 1
                            border.color: pMouse.containsMouse
                                ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.22)
                                : Theme.borderSubtle
                            scale: (root.activeSection === "apps" && pMouse.pressed) ? 0.985 : 1.0
                            clip: true

                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                            MouseArea {
                                id: pMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.activeSection === "apps" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.activeSection === "apps" && procWrap.modelData.address) {
                                        TelemetryService.focusApp(procWrap.modelData.address);
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 10
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: procWrap.modelData.name
                                        color: Theme.text
                                        font.family: Theme.fontSans
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        visible: root.activeSection === "apps" && (procWrap.modelData.title || "") !== ""
                                        text: procWrap.modelData.title || ""
                                        color: Theme.textMuted
                                        font.family: Theme.fontSans
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    text: "CPU " + procWrap.modelData.cpu + "% • " + procWrap.modelData.memText
                                    color: Theme.textSub
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                PillButton {
                                    text: root.activeSection === "apps" ? "Close" : "Kill"
                                    textColorOverride: Theme.accent
                                    fontSize: 11
                                    horizontalPadding: 10
                                    verticalPadding: 4
                                    radius: 9
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: {
                                        if (!procWrap.removing) {
                                            procWrap.removing = true;
                                            killDelay.restart();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
