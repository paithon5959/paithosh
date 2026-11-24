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
    property int sel: 0
    function moveSel(d) {
        const n = filteredApps.length;
        if (n === 0) return;
        sel = Math.max(0, Math.min(n - 1, sel + d));
        grid.positionViewAtIndex(sel, GridView.Contain);
    }

    implicitWidth: 580
    implicitHeight: {
        const gridH = filteredApps.length === 0 ? 84 : Math.min(3, Math.max(1, Math.ceil(filteredApps.length / 4))) * 88;
        return 42 + 12 + 28 + 12 + gridH;
    }

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
                    root.shellState.settingsSpotlight = "";
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
        if (q !== "" && (selectedCategory === "All" || selectedCategory === "System")) {
            const settingHits = SettingsSearchService.search(query).slice(0, 4);
            const rawQuery = query.trim();
            for (let k = 0; k < settingHits.length; ++k) {
                const hit = settingHits[k];
                combined.push({
                    id: "paithosh-setting-" + hit.id,
                    name: hit.title,
                    category: "Settings • " + hit.pageLabel,
                    iconName: "",
                    fallbackSvg: hit.icon || "settings",
                    action: (function(targetHit, targetQuery) {
                        return function() {
                            root.shellState.settingsSpotlight = targetQuery;
                            root.shellState.settingsPage = targetHit.page;
                            root.shellState.openIslandApp("settings", null);
                        };
                    })(hit, rawQuery)
                });
            }
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

    onSelectedCategoryChanged: { sel = 0; refreshApps(); }
    onQueryChanged: { sel = 0; refreshApps(); }
    Component.onCompleted: refreshApps()

    Timer {
        id: appsChangedTimer
        interval: 50
        repeat: false
        onTriggered: root.refreshApps()
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            appsChangedTimer.restart();
        }
    }

    ColumnLayout {
        id: mainCol
        width: parent.width
        spacing: 12

        Rectangle {
            Layout.fillWidth: true
            height: 42
            radius: 12
            color: Qt.rgba(1, 1, 1, searchBox.activeFocus ? 0.11 : 0.07)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, searchBox.activeFocus ? 0.40 : 0.12)
            clip: true

            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on border.color { ColorAnimation { duration: 180 } }

            AnimatedTextInput {
                id: searchBox
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                textColor: Theme.text
                font.family: Theme.fontSans
                font.pixelSize: 14
                clip: true
                selectByMouse: true
                onTextChanged: root.query = text
                Keys.onEscapePressed: root.shellState.closePopovers()
                Keys.onLeftPressed: (e) => { if (cursorPosition === 0 || root.sel > 0) root.moveSel(-1); else e.accepted = false; }
                Keys.onRightPressed: (e) => { if (cursorPosition === text.length || root.sel > 0) root.moveSel(1); else e.accepted = false; }
                Keys.onUpPressed: root.moveSel(-4)
                Keys.onDownPressed: root.moveSel(4)
                Keys.onReturnPressed: {
                    if (root.filteredApps.length > 0) {
                        const first = root.filteredApps[Math.min(root.sel, root.filteredApps.length - 1)];
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
                    font.pixelSize: 14
                    visible: searchBox.text === ""
                    elide: Text.ElideRight
                }
            }
        }

        Row {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: ["All", "System", "Games", "Dev", "Media"]
                delegate: PillButton {
                    required property string modelData
                    text: modelData
                    active: root.selectedCategory === modelData
                    horizontalPadding: 13
                    verticalPadding: 5
                    radius: 999
                    fontSize: 12
                    onClicked: root.selectedCategory = modelData
                }
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: root.filteredApps.length === 0 ? 84 : Math.min(3, Math.max(1, Math.ceil(root.filteredApps.length / 4))) * 88
            height: implicitHeight
            clip: true

            Behavior on implicitHeight {
                NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
            }

            Text {
                anchors.centerIn: parent
                visible: root.filteredApps.length === 0
                text: "No matching applications"
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 14
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
                    id: tileWrap
                    required property int index
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Component.onCompleted: hitInAnim.restart()

                    ParallelAnimation {
                        id: hitInAnim
                        NumberAnimation { target: tile; property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                        NumberAnimation { target: tile; property: "scale"; from: 0.98; to: 1.0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                    }

                    Rectangle {
                        id: tile
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: 16
                        clip: true
                        color: (tileMouse.containsMouse || tileWrap.index === root.sel) ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, tileWrap.index === root.sel ? 0.40 : (tileMouse.containsMouse ? 0.16 : 0.08))
                        y: tileMouse.containsMouse && !tileMouse.pressed ? -2 : 0
                        scale: tileMouse.pressed ? 0.94 : 1.0

                        Behavior on color { ColorAnimation { duration: 180 } }
                        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.topMargin: 12
                            anchors.bottomMargin: 10
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                width: 26
                                height: 26

                                readonly property string resolvedIcon: modelData.iconName ? Quickshell.iconPath(modelData.iconName, true) : ""

                                IconImage {
                                    anchors.fill: parent
                                    implicitSize: 26
                                    mipmap: true
                                    source: parent.resolvedIcon
                                    visible: parent.resolvedIcon !== ""
                                }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: modelData.fallbackSvg || "settings"
                                    iconSize: 26
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
                                font.pixelSize: 12
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
                                const act = modelData.action;
                                const appData = modelData;
                                if (act) {
                                    act();
                                } else {
                                    root.shellState.closePopovers();
                                    AppService.launchApp(appData);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
