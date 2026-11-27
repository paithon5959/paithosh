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
    readonly property var appHits: AppService.searchAllApps(q, 4)
    readonly property var settingsHits: q !== "" ? SettingsSearchService.search(q).slice(0, 4) : []
    readonly property var quickActions: [
        { title: "Files", subtitle: "Open external file manager", icon: "folder", tag: "External", external: true, act: function() { AppService.openExternalFiles(); } },
        { title: "Settings", subtitle: "Open external system control", icon: "settings", tag: "External", external: true, act: function() { AppService.openExternalSettings(); } }
    ]

    implicitWidth: 460
    implicitHeight: Math.min(404, listCol.implicitHeight + footerBar.height + 10)
    clip: true

    Behavior on implicitHeight {
        NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
    }

    onQChanged: {
        scrollAnim.stop();
        scrollAnim.to = 0;
        scrollAnim.start();
    }

    function ensureSelectedVisible(item) {
        if (!item) return;
        const pos = item.mapToItem(listCol, 0, 0);
        const top = pos.y;
        const bottom = top + item.height;
        const viewTop = listFlick.contentY;
        const viewBottom = viewTop + listFlick.height;
        let target = viewTop;
        if (top < viewTop) {
            target = Math.max(0, top - 6);
        } else if (bottom > viewBottom) {
            target = Math.min(Math.max(0, listFlick.contentHeight - listFlick.height), bottom - listFlick.height + 6);
        } else {
            return;
        }
        scrollAnim.stop();
        scrollAnim.to = target;
        scrollAnim.start();
    }

    NumberAnimation {
        id: scrollAnim
        target: listFlick
        property: "contentY"
        duration: Theme.reduceMotion ? 60 : 160
        easing.type: Easing.OutCubic
    }

    component SectionHeader: RowLayout {
        property string label: ""
        property int count: 0
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 6

        Text {
            text: parent.label
            color: Theme.textMuted
            font.family: Theme.fontSans
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 0.6
        }

        Item { Layout.fillWidth: true }

        Text {
            visible: parent.count > 0
            text: String(parent.count)
            color: Theme.textMuted
            font.family: Theme.fontMono
            font.pixelSize: 10
        }
    }

    component ResultRow: Rectangle {
        id: rowRoot
        property bool selected: false
        property string title: ""
        property string subtitle: ""
        property string tag: ""
        property string iconPath: ""
        property string fallbackSvg: "settings"
        property bool external: false
        property bool accentIcon: false
        signal activated()

        readonly property bool hovered: rowMouse.containsMouse

        Layout.fillWidth: true
        height: 48
        radius: 14
        clip: true
        color: selected
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
            : (hovered ? Theme.cardHover : Theme.cardBg)
        border.width: selected ? 1.5 : 1
        border.color: selected
            ? Theme.accent
            : (hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.24) : Theme.borderSubtle)
        scale: rowMouse.pressed ? 0.98 : 1.0

        onSelectedChanged: {
            if (selected) Qt.callLater(function() { if (root && rowRoot) root.ensureSelectedVisible(rowRoot); });
        }

        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on border.width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on scale {
            NumberAnimation {
                duration: 180
                easing.type: Theme.motionEasing
                easing.overshoot: Theme.springOvershoot
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                width: 32
                height: 32
                radius: 10
                clip: true
                color: (rowRoot.selected || rowRoot.accentIcon)
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, rowRoot.selected ? 0.18 : 0.12)
                    : Theme.surfaceRaised
                border.width: 1
                border.color: rowRoot.selected
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.38)
                    : Theme.borderSubtle

                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

                IconImage {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    implicitSize: 20
                    mipmap: true
                    source: rowRoot.iconPath
                    visible: rowRoot.iconPath !== ""
                }

                SvgIcon {
                    anchors.centerIn: parent
                    sourceName: rowRoot.fallbackSvg
                    iconSize: 16
                    color: (rowRoot.selected || rowRoot.accentIcon) ? Theme.accent : Theme.textSub
                    visible: rowRoot.iconPath === ""
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: rowRoot.title
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    visible: rowRoot.subtitle !== ""
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: rowRoot.subtitle
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                Text {
                    visible: rowRoot.tag !== ""
                    Layout.maximumWidth: 116
                    text: rowRoot.tag
                    color: rowRoot.selected ? Theme.text : Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                SvgIcon {
                    visible: rowRoot.external
                    sourceName: "external-link"
                    iconSize: 12
                    color: rowRoot.selected ? Theme.accent : Theme.textMuted
                }
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: rowRoot.activated()
        }
    }

    Flickable {
        id: listFlick
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footerBar.top
        anchors.bottomMargin: 8
        contentWidth: width
        contentHeight: listCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: listCol
            width: listFlick.width - (listFlick.contentHeight > listFlick.height + 2 ? 8 : 0)
            spacing: 6

            SectionHeader {
                visible: root.appHits.length > 0
                label: "APPLICATIONS"
                count: root.appHits.length
            }

            Repeater {
                model: root.appHits
                delegate: ResultRow {
                    required property var modelData
                    required property int index
                    selected: index === root.shellState.searchSel
                    title: modelData.name || ""
                    subtitle: modelData.category || "Application"
                    tag: modelData.islandApp ? "Paithosh" : ""
                    iconPath: modelData.iconName ? Quickshell.iconPath(modelData.iconName, true) : ""
                    fallbackSvg: modelData.fallbackSvg || "settings"
                    accentIcon: !!modelData.islandApp
                    onActivated: AppService.openApp(modelData, root.shellState)
                }
            }

            SectionHeader {
                visible: root.settingsHits.length > 0
                Layout.topMargin: root.appHits.length > 0 ? 6 : 0
                label: "SETTINGS"
                count: root.settingsHits.length
            }

            Repeater {
                model: root.settingsHits
                delegate: ResultRow {
                    required property var modelData
                    required property int index
                    selected: (root.appHits.length + index) === root.shellState.searchSel
                    title: modelData.title || ""
                    subtitle: modelData.subtitle || ""
                    tag: modelData.pageLabel || ""
                    fallbackSvg: modelData.icon || "settings"
                    accentIcon: true
                    onActivated: {
                        const targetPage = modelData.page;
                        const targetQuery = root.q;
                        root.shellState.settingsSpotlight = targetQuery;
                        root.shellState.settingsPage = targetPage;
                        root.shellState.openIslandApp("settings", null);
                    }
                }
            }

            SectionHeader {
                Layout.topMargin: (root.appHits.length > 0 || root.settingsHits.length > 0) ? 6 : 0
                label: "QUICK ACTIONS"
                count: root.quickActions.length
            }

            Repeater {
                model: root.quickActions
                delegate: ResultRow {
                    required property var modelData
                    required property int index
                    selected: (root.appHits.length + root.settingsHits.length + index) === root.shellState.searchSel
                    title: modelData.title
                    subtitle: modelData.subtitle
                    tag: modelData.tag
                    fallbackSvg: modelData.icon
                    external: modelData.external
                    onActivated: {
                        root.shellState.closePopovers();
                        modelData.act();
                    }
                }
            }

            SectionHeader {
                visible: root.q !== ""
                Layout.topMargin: 6
                label: "WEB SEARCH"
            }

            ResultRow {
                visible: root.q !== ""
                selected: (root.appHits.length + root.settingsHits.length + 2) === root.shellState.searchSel
                title: "Search DuckDuckGo for “" + root.q + "”"
                subtitle: "Open in default browser"
                tag: "Web"
                fallbackSvg: "globe"
                external: true
                onActivated: {
                    const query = root.q;
                    root.shellState.closePopovers();
                    AppService.searchWeb(query);
                }
            }
        }

        // Minimal 4px scrollbar (visible only when content overflows)
        Rectangle {
            visible: listFlick.contentHeight > listFlick.height + 2
            anchors.right: parent.right
            anchors.rightMargin: 1
            width: 4
            radius: 2
            y: listFlick.visibleArea.yPosition * listFlick.height
            height: Math.max(24, listFlick.visibleArea.heightRatio * listFlick.height)
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, listFlick.moving ? 0.34 : 0.18)
            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
    }

    // Compact keyboard hint strip (mono keycaps + sans labels)
    RowLayout {
        id: footerBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        height: 20
        spacing: 12

        RowLayout {
            spacing: 4
            Text {
                text: "↑↓"
                color: Theme.textSub
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
            Text {
                text: "Navigate"
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 10
            }
        }

        RowLayout {
            spacing: 4
            Text {
                text: "↵"
                color: Theme.textSub
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
            Text {
                text: "Open"
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 10
            }
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            spacing: 4
            Text {
                text: "ESC"
                color: Theme.textSub
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
            Text {
                text: "Close"
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 10
            }
        }
    }
}
