import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../services"
import "common"

Item {
    id: root

    readonly property var liveToast: NotificationService.activeToast
    property var cachedToast: null
    readonly property var toast: liveToast || cachedToast
    property bool copied: false

    implicitWidth: 380
    implicitHeight: toastCol.implicitHeight
    clip: true

    onLiveToastChanged: {
        if (liveToast) {
            cachedToast = liveToast;
            copied = false;
        }
    }

    HoverHandler {
        id: toastHover
        onHoveredChanged: {
            if (hovered) {
                NotificationService.pauseToastTimer();
            } else {
                NotificationService.resumeToastTimer();
            }
        }
    }

    ColumnLayout {
        id: toastCol
        width: parent.width
        spacing: 10

        // Interactive content area (click to open / focus app)
        Rectangle {
            id: contentCard
            Layout.fillWidth: true
            implicitHeight: contentCol.implicitHeight + 16
            radius: 12
            clip: true
            color: bodyMouse.containsMouse ? Theme.cardBg : "transparent"
            border.width: 1
            border.color: bodyMouse.containsMouse ? Theme.borderSubtle : "transparent"
            scale: bodyMouse.pressed ? 0.985 : 1.0

            Behavior on color {
                ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
            Behavior on border.color {
                ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutBack
                    easing.overshoot: Theme.springOvershoot
                }
            }

            MouseArea {
                id: bodyMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: NotificationService.activateToast()
            }

            ColumnLayout {
                id: contentCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Concentric 36x36 icon well
                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        Layout.alignment: Qt.AlignTop
                        radius: 10
                        clip: true
                        color: Theme.surfaceRaised
                        border.width: 1
                        border.color: Theme.borderSubtle

                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: "bell"
                            iconSize: 16
                            color: Theme.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.toast ? root.toast.appName : ""
                                color: Theme.textSub
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                text: root.toast ? root.toast.timeText : "now"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.toast ? root.toast.summary : ""
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }
                    }
                }

                Text {
                    visible: text !== ""
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.leftMargin: 46
                    text: root.toast ? root.toast.body : ""
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }

        // Full-width, easy-to-click action bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            PillButton {
                fillWidth: true
                fixedHeight: 34
                radius: 10
                active: true
                iconName: "external-link"
                iconSize: 14
                text: "Open"
                onClicked: NotificationService.activateToast()
            }

            PillButton {
                visible: root.toast && root.toast.body !== ""
                fillWidth: true
                fixedHeight: 34
                radius: 10
                iconName: root.copied ? "check" : "copy"
                iconSize: 14
                text: root.copied ? "Copied" : "Copy"
                bgOverride: root.copied ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.16) : "transparent"
                textColorOverride: root.copied ? Theme.ok : "transparent"
                onClicked: {
                    if (root.toast && root.toast.body !== "") {
                        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy 2>/dev/null || true", "sh", root.toast.body]);
                        root.copied = true;
                    }
                }
            }

            PillButton {
                fillWidth: true
                fixedHeight: 34
                radius: 10
                iconName: "close"
                iconSize: 14
                text: "Dismiss"
                onClicked: NotificationService.dismissToast()
            }
        }
    }
}
