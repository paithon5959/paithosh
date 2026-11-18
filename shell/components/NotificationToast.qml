import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../services"
import "common"

Item {
    id: root

    readonly property var toast: NotificationService.activeToast
    property bool copied: false

    implicitWidth: 380
    implicitHeight: toastCol.implicitHeight

    onToastChanged: copied = false

    ColumnLayout {
        id: toastCol
        width: parent.width
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                width: 7
                height: 7
                radius: 3.5
                color: Theme.danger
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.toast ? root.toast.appName : ""
                color: Qt.rgba(1, 1, 1, 0.8)
                font.family: Theme.fontSans
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                text: root.toast ? root.toast.timeText : "now"
                color: Theme.textSub
                font.family: Theme.fontSans
                font.pixelSize: 12
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: root.toast ? root.toast.summary : ""
            color: Theme.text
            font.family: Theme.fontSans
            font.pixelSize: 17
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            visible: text !== ""
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: root.toast ? root.toast.body : ""
            color: Qt.rgba(1, 1, 1, 0.72)
            font.family: Theme.fontSans
            font.pixelSize: 13
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Row {
            Layout.topMargin: 4
            spacing: 8

            PillButton {
                visible: root.toast && root.toast.body !== ""
                text: root.copied ? "Copied!" : "Copy"
                onClicked: {
                    if (root.toast && root.toast.body !== "") {
                        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy 2>/dev/null || true", "sh", root.toast.body]);
                        root.copied = true;
                    }
                }
            }

            PillButton {
                text: "Dismiss"
                onClicked: NotificationService.dismissToast()
            }
        }
    }
}
