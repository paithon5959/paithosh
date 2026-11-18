import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."
import "../services"
import "common"

Item {
    id: root

    required property var shellState

    readonly property string q: shellState.searchQuery.trim()
    readonly property var appHits: AppService.searchApps(q, "All").slice(0, 4)

    implicitWidth: 440
    implicitHeight: Math.min(340, col.implicitHeight)
    clip: true

    Behavior on implicitHeight {
        NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 6

        Text {
            visible: root.appHits.length > 0
            text: "APPLICATIONS"
            color: Theme.textMuted
            font.family: Theme.fontSans
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 0.6
            Layout.leftMargin: 4
        }

        Repeater {
            model: root.appHits
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                height: 54
                radius: 14
                clip: true
                color: appMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.11)
                border.width: 1
                border.color: Theme.borderSubtle
                scale: appMouse.pressed ? 0.97 : 1.0

                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 14
                    spacing: 12

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 10
                        color: Qt.rgba(1, 1, 1, 0.12)

                        readonly property string resolvedIcon: modelData.iconName ? Quickshell.iconPath(modelData.iconName, true) : ""
                        IconImage {
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            implicitSize: 20
                            mipmap: true
                            source: parent.resolvedIcon
                            visible: parent.resolvedIcon !== ""
                        }
                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: modelData.fallbackSvg || "settings"
                            iconSize: 18
                            color: Theme.text
                            visible: parent.resolvedIcon === ""
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: modelData.name || ""
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    Text {
                        text: (modelData.category || "App") + " • Launch ↵"
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: appMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.shellState.closePopovers();
                        AppService.launchApp(modelData);
                    }
                }
            }
        }

        Text {
            text: "QUICK ACTIONS"
            color: Theme.textMuted
            font.family: Theme.fontSans
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 0.6
            Layout.topMargin: 4
            Layout.leftMargin: 4
        }

        Repeater {
            model: [
                { title: "Files — File Manager", sub: "External app", act: function() { AppService.openExternalFiles(); } },
                { title: "Settings — System Control", sub: "External app", act: function() { AppService.openExternalSettings(); } }
            ]
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                height: 38
                radius: 12
                clip: true
                color: actMouse.containsMouse ? Theme.cardHover : Qt.rgba(1, 1, 1, 0.07)
                scale: actMouse.pressed ? 0.97 : 1.0

                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: modelData.title
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }

                    Text {
                        text: modelData.sub
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                    }
                }

                MouseArea {
                    id: actMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.shellState.closePopovers();
                        modelData.act();
                    }
                }
            }
        }

        Text {
            visible: root.q !== ""
            text: "SEARCH ENGINE"
            color: Theme.textMuted
            font.family: Theme.fontSans
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 0.6
            Layout.topMargin: 4
            Layout.leftMargin: 4
        }

        Rectangle {
            visible: root.q !== ""
            Layout.fillWidth: true
            height: 38
            radius: 12
            clip: true
            color: webMouse.containsMouse ? Theme.cardHover : Qt.rgba(1, 1, 1, 0.07)
            scale: webMouse.pressed ? 0.97 : 1.0

            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: "Search DuckDuckGo for “" + root.q + "”"
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                Text {
                    text: "Web ↗"
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                }
            }

            MouseArea {
                id: webMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const query = root.q;
                    root.shellState.closePopovers();
                    AppService.searchWeb(query);
                }
            }
        }
    }
}
