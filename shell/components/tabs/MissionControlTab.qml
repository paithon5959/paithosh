import QtQuick
import QtQuick.Layouts
import Quickshell
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

        // 2-Column Compact Toggle Row (Wi-Fi & DND)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Wi-Fi Card
            Rectangle {
                Layout.fillWidth: true
                height: 50
                radius: 14
                clip: true
                color: wifiMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                scale: wifiMouse.pressed ? 0.96 : 1.0

                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: NetworkService.wifiEnabled ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                        Behavior on color { ColorAnimation { duration: 180 } }

                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: "wifi"
                            iconSize: 14
                            color: NetworkService.wifiEnabled ? Theme.accentFg : Theme.text
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: "Wi-Fi"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: NetworkService.activeSsid
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    id: wifiMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "paithosh", "openSettings", "wifi"]);
                        } else {
                            NetworkService.toggleWifi();
                        }
                    }
                }
            }

            // Do Not Disturb Card
            Rectangle {
                Layout.fillWidth: true
                height: 50
                radius: 14
                clip: true
                color: dndMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                scale: dndMouse.pressed ? 0.96 : 1.0

                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: NotificationService.dnd ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                        Behavior on color { ColorAnimation { duration: 180 } }

                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: "moon"
                            iconSize: 13
                            color: NotificationService.dnd ? Theme.accentFg : Theme.text
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: "Do Not Disturb"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: NotificationService.dnd ? "On" : "Off"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    id: dndMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.dnd = !NotificationService.dnd
                }
            }
        }

        // MPRIS Media Hero Card
        Rectangle {
            Layout.fillWidth: true
            height: 108
            radius: 18
            color: Theme.cardBg
            clip: true
            visible: MediaService.active

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        width: 48
                        height: 48
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.14)
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: MediaService.trackArtUrl
                            fillMode: Image.PreserveAspectCrop
                            visible: MediaService.trackArtUrl !== ""
                        }

                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: "music"
                            iconSize: 20
                            color: Theme.text
                            visible: MediaService.trackArtUrl === ""
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: MediaService.trackTitle
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: MediaService.trackArtist + (MediaService.trackAlbum !== "" ? " • " + MediaService.trackAlbum : "")
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        spacing: 4

                        Repeater {
                            model: [
                                { icon: "prev", act: function() { MediaService.previous(); } },
                                { icon: MediaService.isPlaying ? "pause" : "play", act: function() { MediaService.togglePlay(); } },
                                { icon: "next", act: function() { MediaService.next(); } }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: 28
                                height: 28
                                radius: 14
                                color: mMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
                                scale: mMouse.pressed ? 0.86 : 1.0

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: modelData.icon
                                    iconSize: 14
                                    color: Theme.text
                                }

                                MouseArea {
                                    id: mMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.act()
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Rectangle {
                        Layout.fillWidth: true
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.14)
                        clip: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: 2
                            color: Theme.accent
                            width: parent.width * MediaService.progress
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: MediaService.positionText
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: MediaService.lengthText
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }

        // Volume & Brightness Sliders
        Rectangle {
            Layout.fillWidth: true
            height: 76
            radius: 18
            color: Theme.cardBg

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 10

                Repeater {
                    model: [
                        { key: "volume", label: "Volume", minV: 0 },
                        { key: "brightness", label: "Brightness", minV: 10 }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        readonly property int currentVal: modelData.key === "volume"
                            ? AudioService.volumePct
                            : BrightnessService.brightnessPct
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            width: 72
                            Layout.preferredWidth: 72
                            text: modelData.label
                            color: Qt.rgba(1, 1, 1, 0.78)
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                        }

                        Item {
                            Layout.fillWidth: true
                            height: 18

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 6
                                radius: 3
                                color: Qt.rgba(1, 1, 1, 0.16)
                                clip: true

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    radius: 3
                                    color: Theme.accent
                                    width: Math.max(0, Math.min(parent.width, parent.width * (currentVal / 100.0)))
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                radius: 7
                                color: Theme.accent
                                border.width: 1
                                border.color: Qt.rgba(0, 0, 0, 0.45)
                                x: Math.max(0, Math.min(parent.width - width, parent.width * (currentVal / 100.0) - width / 2))
                                scale: slMouse.pressed ? 1.15 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                            }

                            MouseArea {
                                id: slMouse
                                anchors.fill: parent
                                preventStealing: true
                                cursorShape: Qt.PointingHandCursor
                                function applyX(mx) {
                                    const ratio = Math.max(0, Math.min(1, mx / Math.max(1, width)));
                                    const pct = Math.max(modelData.minV, Math.min(100, Math.round(ratio * 100)));
                                    if (modelData.key === "volume") {
                                        AudioService.setVolume(pct, false);
                                    } else {
                                        BrightnessService.setBrightness(pct, false);
                                    }
                                }
                                onPressed: function(mouse) { applyX(mouse.x); }
                                onPositionChanged: function(mouse) { if (pressed) applyX(mouse.x); }
                            }
                        }

                        Text {
                            Layout.preferredWidth: 34
                            horizontalAlignment: Text.AlignRight
                            text: currentVal + "%"
                            color: Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        // Collapsible Notification Center List
        Rectangle {
            id: notifBox
            readonly property bool hasItems: NotificationService.unreadCount > 0
            Layout.fillWidth: true
            Layout.preferredHeight: hasItems ? Math.min(200, 44 + notifList.contentHeight) : 0
            radius: 18
            color: Qt.rgba(1, 1, 1, 0.06)
            clip: true
            opacity: hasItems ? 1.0 : 0.0
            visible: Layout.preferredHeight > 1 || opacity > 0.01

            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        text: "Notifications (" + NotificationService.unreadCount + ")"
                        color: Qt.rgba(1, 1, 1, 0.78)
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    PillButton {
                        text: "Clear all"
                        fontSize: 11
                        horizontalPadding: 9
                        verticalPadding: 3
                        radius: 8
                        onClicked: NotificationService.clearAll()
                    }
                }

                ListView {
                    id: notifList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: NotificationService.historyList

                    delegate: Item {
                        id: rowWrap
                        required property var modelData
                        property bool removing: false

                        width: notifList.width
                        height: removing ? 0 : 54
                        opacity: removing ? 0.0 : 1.0
                        clip: true

                        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        Timer {
                            id: removeDelay
                            interval: 220
                            repeat: false
                            onTriggered: NotificationService.dismissById(rowWrap.modelData.id)
                        }

                        Rectangle {
                            width: parent.width
                            height: 54
                            x: rowWrap.removing ? 16 : 0
                            radius: 14
                            color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
                            clip: true

                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 160 } }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: rowWrap.modelData.appName + " • " + rowWrap.modelData.timeText
                                        color: Theme.textMuted
                                        font.family: Theme.fontSans
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: rowWrap.modelData.summary
                                        color: Theme.text
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: text !== ""
                                        Layout.fillWidth: true
                                        text: rowWrap.modelData.body
                                        color: Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }

                                PillButton {
                                    iconName: "close"
                                    iconSize: 12
                                    horizontalPadding: 6
                                    verticalPadding: 4
                                    radius: 8
                                    onClicked: {
                                        if (!rowWrap.removing) {
                                            rowWrap.removing = true;
                                            removeDelay.restart();
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
