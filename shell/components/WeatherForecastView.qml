import QtQuick
import QtQuick.Layouts
import ".."
import "../services"
import "common"

Item {
    id: root

    required property var shellState

    readonly property bool isMonochrome: Theme.accent.hslSaturation < 0.08
    readonly property color iconAccent: isMonochrome ? Theme.text : Theme.accent

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Top Current Summary Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                width: 42
                height: 42
                radius: 12
                color: Theme.surfaceRaised
                border.width: 1
                border.color: Theme.borderSubtle

                SvgIcon {
                    anchors.centerIn: parent
                    sourceName: WeatherService.conditionIcon
                    iconSize: 22
                    color: root.iconAccent
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
                    font.pixelSize: 17
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                Row {
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: WeatherService.conditionText
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "droplet"
                            iconSize: 12
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

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "wind"
                            iconSize: 12
                            color: Theme.textSub
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: WeatherService.windKmh + " km/h"
                            color: Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                }
            }

            Text {
                text: WeatherService.tempCelsius + "°C"
                color: Theme.text
                font.family: Theme.fontMono
                font.pixelSize: 22
                font.weight: Font.Bold
            }

            Row {
                spacing: 6

                PillButton {
                    iconName: "refresh"
                    iconSize: 13
                    horizontalPadding: 8
                    verticalPadding: 6
                    radius: 8
                    onClicked: WeatherService.refresh()
                }

                PillButton {
                    iconName: "close"
                    iconSize: 13
                    horizontalPadding: 8
                    verticalPadding: 6
                    radius: 8
                    onClicked: root.shellState.collapseIslandApp()
                }
            }
        }

        // Section Label
        Text {
            Layout.fillWidth: true
            text: "7-DAY FORECAST"
            color: Theme.textMuted
            font.family: Theme.fontSans
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 0.6
        }

        // 7-Day Forecast Cards Row
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            Repeater {
                model: WeatherService.dailyForecast
                delegate: Rectangle {
                    id: dayCard
                    required property var modelData
                    required property int index
                    readonly property bool isToday: index === 0

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    radius: 12
                    clip: true
                    color: isToday
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                        : (dayMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                    border.width: isToday ? 1.5 : 1
                    border.color: isToday
                        ? Theme.accent
                        : (dayMouse.containsMouse
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40)
                            : Theme.borderSubtle)
                    scale: dayMouse.pressed ? 0.96 : 1.0

                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: dayCard.modelData.dayLabel
                            color: dayCard.isToday ? Theme.text : Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: dayCard.isToday ? Font.Bold : Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Item { Layout.fillHeight: true }

                        SvgIcon {
                            Layout.alignment: Qt.AlignHCenter
                            sourceName: dayCard.modelData.icon
                            iconSize: 22
                            color: dayCard.isToday ? root.iconAccent : Theme.text
                        }

                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 3
                            opacity: dayCard.modelData.rainPct > 0 ? 1.0 : 0.35

                            SvgIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                sourceName: "droplet"
                                iconSize: 10
                                color: Theme.textSub
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: dayCard.modelData.rainPct + "%"
                                color: Theme.textSub
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                            }
                        }

                        Item { Layout.fillHeight: true }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: dayCard.modelData.tempMax + "°"
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: dayCard.modelData.tempMin + "°"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                            }
                        }
                    }

                    MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
        }
    }
}
