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
            border.width: 1
            border.color: KdeConnectService.online
                ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.40)
                : Theme.borderSubtle
            clip: true

            Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

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
                        Layout.minimumWidth: 0
                        text: KdeConnectService.deviceName
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: (KdeConnectService.online ? "Connected" : "Standby") + " • " + KdeConnectService.batteryPct + "% • 5GHz"
                        color: Theme.textSub
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    height: 22
                    width: kdeStatusText.implicitWidth + 14
                    radius: 8
                    color: KdeConnectService.online
                        ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.14)
                        : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                    border.width: 1
                    border.color: KdeConnectService.online
                        ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.38)
                        : Theme.borderSubtle

                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    Text {
                        id: kdeStatusText
                        anchors.centerIn: parent
                        text: KdeConnectService.online ? "Online" : "Standby"
                        color: KdeConnectService.online ? Theme.ok : Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }
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
