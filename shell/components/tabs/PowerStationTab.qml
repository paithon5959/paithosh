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
            border.color: PowerService.charging
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

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Battery"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: PowerService.batteryPct + "%"
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: PowerService.timeRemaining + " • Health " + PowerService.healthPct + "%"
                        color: Theme.textSub
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    height: 22
                    width: pwrStatusText.implicitWidth + 14
                    radius: 8
                    color: PowerService.charging
                        ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.14)
                        : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
                    border.width: 1
                    border.color: PowerService.charging
                        ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.38)
                        : Theme.borderSubtle

                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    Text {
                        id: pwrStatusText
                        anchors.centerIn: parent
                        text: PowerService.charging ? "Charging" : "Discharging"
                        color: PowerService.charging ? Theme.ok : Theme.textSub
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
            columns: 3
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: ["Power Saver", "Balanced", "Performance"]
                delegate: PillButton {
                    required property string modelData
                    text: modelData
                    active: PowerService.powerProfile === modelData
                    fillWidth: true
                    radius: 10
                    verticalPadding: 10
                    onClicked: PowerService.setPowerProfile(modelData)
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: [
                    { label: "Lock", flash: "Locked", danger: false },
                    { label: "Logout", flash: "Logging out", danger: false },
                    { label: "Reboot", flash: "Rebooting", danger: false },
                    { label: "Shutdown", flash: "Shutting down", danger: true }
                ]
                delegate: PillButton {
                    id: pwrBtn
                    required property var modelData
                    property bool flashed: false
                    text: flashed ? modelData.flash : modelData.label
                    danger: modelData.danger
                    fillWidth: true
                    verticalPadding: 7
                    onClicked: {
                        flashed = true;
                        flashReset.restart();
                        PowerService.executeAction(modelData.label);
                    }

                    Timer {
                        id: flashReset
                        interval: 1200
                        repeat: false
                        onTriggered: pwrBtn.flashed = false
                    }
                }
            }
        }
    }
}
