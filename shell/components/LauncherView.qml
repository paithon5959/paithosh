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

    property string selectedCategory: "All"
    property string query: ""
    property var filteredApps: []

    implicitWidth: 500
    implicitHeight: mainCol.implicitHeight

    function refreshApps() {
        const pinned = [];
        if (selectedCategory === "All" || selectedCategory === "System") {
            pinned.push({
                id: "paithosh-files",
                name: "Files",
                category: "System",
                iconName: "",
                fallbackSvg: "folder",
                action: function() { root.shellState.openIslandApp("files", null); }
            });
            pinned.push({
                id: "paithosh-settings",
                name: "Settings",
                category: "System",
                iconName: "",
                fallbackSvg: "settings",
                action: function() {
                    root.shellState.settingsPage = "home";
                    root.shellState.openIslandApp("settings", null);
                }
            });
            pinned.push({
                id: "paithosh-upload",
                name: "Upload Picker",
                category: "System",
                iconName: "",
                fallbackSvg: "folder",
                action: function() {
                    root.shellState.pickerMode = "upload";
                    root.shellState.openIslandApp("picker", null);
                }
            });
            pinned.push({
                id: "paithosh-download",
                name: "Download Picker",
                category: "System",
                iconName: "",
                fallbackSvg: "folder",
                action: function() {
                    root.shellState.pickerMode = "download";
                    root.shellState.openIslandApp("picker", null);
                }
            });
        }
        const q = query.trim().toLowerCase();
        const combined = [];
        for (let i = 0; i < pinned.length; ++i) {
            if (q === "" || pinned[i].name.toLowerCase().indexOf(q) !== -1 || pinned[i].category.toLowerCase().indexOf(q) !== -1) {
                combined.push(pinned[i]);
            }
        }
        const systemApps = AppService.searchApps(query, selectedCategory);
        for (let j = 0; j < systemApps.length; ++j) {
            combined.push(systemApps[j]);
        }
        filteredApps = combined;
    }

    function resetAndFocus() {
        query = "";
        searchBox.text = "";
        selectedCategory = "All";
        refreshApps();
        focusTimer.restart();
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: searchBox.forceActiveFocus()
    }

    onSelectedCategoryChanged: refreshApps()
    onQueryChanged: refreshApps()
    Component.onCompleted: refreshApps()

    ColumnLayout {
        id: mainCol
        width: parent.width
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: 10
            color: Qt.rgba(1, 1, 1, searchBox.activeFocus ? 0.11 : 0.07)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, searchBox.activeFocus ? 0.40 : 0.12)
            clip: true

            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on border.color { ColorAnimation { duration: 180 } }

            TextInput {
                id: searchBox
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.fontSans
                font.pixelSize: 13
                clip: true
                selectByMouse: true
                onTextChanged: root.query = text
                Keys.onEscapePressed: root.shellState.closePopovers()
                Keys.onReturnPressed: {
                    if (root.filteredApps.length > 0) {
                        const first = root.filteredApps[0];
                        root.shellState.closePopovers();
                        if (first.action) first.action();
                        else AppService.launchApp(first);
                    }
                }

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "Search apps, games (osu!, Minecraft, VS Code...)"
                    color: Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    visible: searchBox.text === ""
                    elide: Text.ElideRight
                }
            }
        }

        Row {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: ["All", "System", "Games", "Dev", "Media"]
                delegate: PillButton {
                    required property string modelData
                    text: modelData
                    active: root.selectedCategory === modelData
                    horizontalPadding: 11
                    verticalPadding: 4
                    radius: 999
                    fontSize: 11
                    onClicked: root.selectedCategory = modelData
                }
            }
        }

        Item {
            Layout.fillWidth: true
            height: root.filteredApps.length === 0 ? 72 : Math.min(268, Math.max(88, Math.ceil(root.filteredApps.length / 4) * 88))
            clip: true

            Behavior on height {
                NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
            }

            Text {
                anchors.centerIn: parent
                visible: root.filteredApps.length === 0
                text: "No matching applications"
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 13
            }

            GridView {
                id: grid
                anchors.fill: parent
                visible: root.filteredApps.length > 0
                clip: true
                cellWidth: Math.floor(width / 4)
                cellHeight: 88
                model: root.filteredApps
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        id: tile
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 14
                        clip: true
                        color: tileMouse.containsMouse ? Theme.cardHover : Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, tileMouse.containsMouse ? 0.16 : 0.08)
                        y: tileMouse.containsMouse && !tileMouse.pressed ? -2 : 0
                        scale: tileMouse.pressed ? 0.94 : 1.0

                        Behavior on color { ColorAnimation { duration: 160 } }
                        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                width: 24
                                height: 24

                                readonly property string resolvedIcon: modelData.iconName ? Quickshell.iconPath(modelData.iconName, true) : ""

                                IconImage {
                                    anchors.fill: parent
                                    implicitSize: 24
                                    mipmap: true
                                    source: parent.resolvedIcon
                                    visible: parent.resolvedIcon !== ""
                                }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: modelData.fallbackSvg || "settings"
                                    iconSize: 20
                                    color: Theme.text
                                    visible: parent.resolvedIcon === ""
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.name || ""
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.shellState.closePopovers();
                                if (modelData.action) modelData.action();
                                else AppService.launchApp(modelData);
                            }
                        }
                    }
                }
            }
        }
    }
}
