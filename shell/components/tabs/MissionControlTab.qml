import QtQuick
import QtQuick.Layouts
import Quickshell
import "../.."
import "../../services"
import "../common"

Item {
    id: root

    required property var shellState

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
                border.width: 1
                border.color: wifiMouse.containsMouse
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42)
                    : (NetworkService.wifiEnabled ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Theme.borderSubtle)
                scale: wifiMouse.pressed ? 0.96 : 1.0

                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 14
                        color: NetworkService.wifiEnabled ? Theme.accent : Theme.surfaceRaised
                        border.width: NetworkService.wifiEnabled ? 0 : 1
                        border.color: Theme.borderSubtle
                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

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
                border.width: 1
                border.color: dndMouse.containsMouse
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42)
                    : (NotificationService.dnd ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Theme.borderSubtle)
                scale: dndMouse.pressed ? 0.96 : 1.0

                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 14
                        color: NotificationService.dnd ? Theme.accent : Theme.surfaceRaised
                        border.width: NotificationService.dnd ? 0 : 1
                        border.color: Theme.borderSubtle
                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

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

        // Weather Location & Current Conditions Banner (click -> 7-day forecast in Dynamic Island)
        Rectangle {
            id: weatherCard
            Layout.fillWidth: true
            height: 62
            radius: 14
            clip: true
            color: weatherMouse.containsMouse ? Theme.cardHover : Theme.cardBg
            border.width: 1
            border.color: weatherMouse.containsMouse
                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42)
                : Theme.borderSubtle
            scale: weatherMouse.pressed ? 0.97 : 1.0

            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Rectangle {
                    width: 34
                    height: 34
                    radius: 10
                    color: Theme.surfaceRaised
                    border.width: 1
                    border.color: Theme.borderSubtle

                    SvgIcon {
                        anchors.centerIn: parent
                        sourceName: WeatherService.conditionIcon
                        iconSize: 18
                        color: Theme.accent.hslSaturation < 0.08 ? Theme.text : Theme.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: WeatherService.locationName
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: WeatherService.conditionText + " • " + WeatherService.windKmh + " km/h"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: WeatherService.tempCelsius + "°C"
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }

                    Row {
                        Layout.alignment: Qt.AlignRight
                        spacing: 3

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "droplet"
                            iconSize: 11
                            color: Theme.textSub
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: WeatherService.humidityPct + "%"
                            color: Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                }

                SvgIcon {
                    sourceName: "chevron-right"
                    iconSize: 14
                    color: weatherMouse.containsMouse ? Theme.text : Theme.textMuted
                }
            }

            MouseArea {
                id: weatherMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.shellState.openIslandApp("weather", null)
            }
        }

        // MPRIS Media Hero Card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: MediaService.active ? 108 : 0
            radius: 14
            color: Theme.cardBg
            border.width: 1
            border.color: Theme.borderSubtle
            clip: true
            opacity: MediaService.active ? 1.0 : 0.0
            visible: Layout.preferredHeight > 1 || opacity > 0.01

            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

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
                        radius: 10
                        color: Theme.surfaceRaised
                        border.width: 1
                        border.color: Theme.borderSubtle
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
                                color: mMouse.containsMouse ? Theme.cardHover : "transparent"
                                scale: mMouse.pressed ? 0.92 : 1.0

                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

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
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14)
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
            radius: 14
            color: Theme.cardBg
            border.width: 1
            border.color: Theme.borderSubtle
            clip: true

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
                            color: Theme.textSub
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
                                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.16)
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
                                border.color: Qt.rgba(Theme.pillBg.r, Theme.pillBg.g, Theme.pillBg.b, 0.45)
                                x: Math.max(0, Math.min(parent.width - width, parent.width * (currentVal / 100.0) - width / 2))
                                scale: slMouse.pressed ? 1.15 : (slMouse.containsMouse ? 1.08 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                            }

                            MouseArea {
                                id: slMouse
                                anchors.fill: parent
                                hoverEnabled: true
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
            Layout.preferredHeight: hasItems ? Math.min(220, notifHeader.implicitHeight + 32 + notifList.contentHeight) : 0
            radius: 14
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
            border.width: 1
            border.color: Theme.borderSubtle
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
                    id: notifHeader
                    Layout.fillWidth: true

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 6

                        Text {
                            text: "Notifications"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            height: 16
                            width: Math.max(18, notifCountText.implicitWidth + 8)
                            radius: 5
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                            Text {
                                id: notifCountText
                                anchors.centerIn: parent
                                text: String(NotificationService.unreadCount)
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }

                        Item { Layout.fillWidth: true }
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
                            radius: 10
                            color: rowMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                            border.width: 1
                            border.color: rowMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.24) : Theme.borderSubtle
                            clip: true

                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

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

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 4

                                        Text {
                                            Layout.maximumWidth: 160
                                            text: rowWrap.modelData.appName
                                            color: Theme.textMuted
                                            font.family: Theme.fontSans
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: "• " + rowWrap.modelData.timeText
                                            color: Theme.textMuted
                                            font.family: Theme.fontMono
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                        }
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
