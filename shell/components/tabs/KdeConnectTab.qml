import QtQuick
import QtQuick.Layouts
import "../.."
import "../../services"
import "../common"

Item {
    id: root

    implicitWidth: 408
    implicitHeight: col.implicitHeight

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            height: 54
            radius: 14
            color: Theme.cardBg
            clip: true

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: KdeConnectService.deviceName
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: (KdeConnectService.online ? "Connected" : "Standby") + " • Battery " + KdeConnectService.batteryPct + "% • 5GHz"
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Text {
                    text: KdeConnectService.online ? "Online" : "Standby"
                    color: KdeConnectService.online ? Theme.ok : Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: [
                    { label: "Ping Device", flash: "Pinged!", act: function() { KdeConnectService.ping(); } },
                    { label: "Send Clipboard", flash: "Sent!", act: function() { KdeConnectService.sendClipboard(); } },
                    { label: "Find My Phone", flash: "Ringing...", act: function() { KdeConnectService.ring(); } },
                    { label: "Browse Files", flash: "Opening...", act: function() { KdeConnectService.browseFiles(); } }
                ]
                delegate: PillButton {
                    id: kdeBtn
                    required property var modelData
                    property bool flashed: false
                    text: flashed ? modelData.flash : modelData.label
                    fillWidth: true
                    horizontalPadding: 10
                    verticalPadding: 8
                    onClicked: {
                        modelData.act();
                        flashed = true;
                        flashTimer.restart();
                    }

                    Timer {
                        id: flashTimer
                        interval: 1200
                        repeat: false
                        onTriggered: kdeBtn.flashed = false
                    }
                }
            }
        }
    }
}
