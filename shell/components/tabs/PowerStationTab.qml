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
                        text: "Battery " + PowerService.batteryPct + "%"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: PowerService.timeRemaining + " • Health " + PowerService.healthPct + "%"
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Text {
                    text: PowerService.charging ? "Charging" : "Discharging"
                    color: PowerService.charging ? Theme.ok : Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
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
                    radius: 14
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
                    { label: "Suspend", flash: "Suspending", danger: false },
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
