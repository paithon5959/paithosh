import QtQuick
import QtQuick.Layouts
import "../.."
import "../../services"
import "../common"

Item {
    id: root

    property string procFilter: ""

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
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // CPU Sparkline Card
            Rectangle {
                Layout.fillWidth: true
                height: 92
                radius: 16
                color: Theme.cardBg
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "CPU"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: TelemetryService.cpuPct + "%"
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                    }

                    Sparkline {
                        id: cpuSpark
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        points: TelemetryService.cpuHistory
                        lineColor: Theme.ok
                    }
                }
            }

            // RAM Sparkline Card
            Rectangle {
                Layout.fillWidth: true
                height: 92
                radius: 16
                color: Theme.cardBg
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "RAM"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: TelemetryService.ramPct + "%"
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                    }

                    Sparkline {
                        id: ramSpark
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        points: TelemetryService.ramHistory
                        lineColor: Theme.info
                    }
                }
            }
        }

        // System Meta Strip
        Rectangle {
            Layout.fillWidth: true
            height: 32
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.05)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Text {
                    text: "Temp: " + TelemetryService.cpuTempC + "℃"
                    color: Theme.textSub
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: TelemetryService.memSummary
                    color: Theme.textSub
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: TelemetryService.swapSummary
                    color: Theme.textSub
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: TelemetryService.uptimeText
                    color: Theme.textSub
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
            }
        }

        // Process Search Input
        Rectangle {
            Layout.fillWidth: true
            height: 34
            radius: 10
            color: Qt.rgba(1, 1, 1, procInput.activeFocus ? 0.11 : 0.07)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, procInput.activeFocus ? 0.40 : 0.12)
            clip: true

            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on border.color { ColorAnimation { duration: 160 } }

            TextInput {
                id: procInput
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.fontSans
                font.pixelSize: 12
                clip: true
                selectByMouse: true
                onTextChanged: root.procFilter = text

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "Filter processes (kitty, firefox, code, pipewire...)"
                    color: Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    visible: procInput.text === ""
                    elide: Text.ElideRight
                }
            }
        }

        // Scrollable Process List
        Item {
            Layout.fillWidth: true
            height: 186
            clip: true

            Text {
                anchors.centerIn: parent
                visible: root.filteredProcs.length === 0
                text: "No matching processes"
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 12
            }

            ListView {
                id: procListView
                anchors.fill: parent
                visible: root.filteredProcs.length > 0
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: root.filteredProcs

                delegate: Item {
                    id: procWrap
                    required property var modelData
                    property bool removing: false

                    width: procListView.width
                    height: removing ? 0 : 42
                    opacity: removing ? 0.0 : 1.0
                    clip: true

                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    Timer {
                        id: killDelay
                        interval: 220
                        repeat: false
                        onTriggered: TelemetryService.killProcess(procWrap.modelData.pid)
                    }

                    Rectangle {
                        width: parent.width
                        height: 42
                        x: procWrap.removing ? 18 : 0
                        radius: 14
                        color: pMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                        clip: true

                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MouseArea {
                            id: pMouse
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: procWrap.modelData.name
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }

                            Text {
                                text: "CPU " + procWrap.modelData.cpu + "% • " + procWrap.modelData.memText
                                color: Theme.textSub
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }

                            PillButton {
                                text: "Kill"
                                fontSize: 11
                                horizontalPadding: 10
                                verticalPadding: 4
                                radius: 8
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
