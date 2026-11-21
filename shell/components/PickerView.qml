import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."
import "common"

Item {
    id: root
    required property var shellState

    property string pickerMode: "upload" // "upload" | "download"
    property string currentDir: "Home"
    property var historyStack: ["Home"]
    property int historyIdx: 0
    property bool isListView: true
    property bool isEditingPath: false
    property bool placesOpen: true
    property string searchQuery: ""
    property string selectedName: ""
    property string filterType: "all" // "all" | "code" | "archive"

    implicitWidth: 880
    implicitHeight: 540

    readonly property var dirPaths: ({
        "Home": "/home/paithon",
        "Documents": "/home/paithon/Documents",
        "Dev": "/home/paithon/Dev",
        "Downloads": "/home/paithon/Downloads",
        "Music": "/home/paithon/Music",
        "Pictures": "/home/paithon/Pictures",
        "Root": "/"
    })

    readonly property var fsData: ({
        "Home": [
            { name: "Documents", type: "folder", meta: "14 items" },
            { name: "Dev", type: "folder", meta: "8 items" },
            { name: "Downloads", type: "folder", meta: "23 items" },
            { name: "Music", type: "folder", meta: "42 items" },
            { name: "Pictures", type: "folder", meta: "19 items" },
            { name: "hyprland.conf", type: "code", meta: "4.2 KB" },
            { name: "waybar.css", type: "code", meta: "2.8 KB" },
            { name: "notes.txt", type: "file", meta: "1.1 KB" }
        ],
        "Documents": [
            { name: "Hyprland-Rice-Spec.md", type: "file", meta: "8.5 KB" },
            { name: "Keybindings.txt", type: "file", meta: "2.1 KB" }
        ],
        "Dev": [
            { name: "paithosh", type: "folder", meta: "Quickshell" },
            { name: "shell.qml", type: "code", meta: "9.4 KB" },
            { name: "Theme.qml", type: "code", meta: "2.2 KB" }
        ],
        "Downloads": [
            { name: "archlinux-2026.iso", type: "file", meta: "1.1 GB" },
            { name: "OpenSans.zip", type: "archive", meta: "4.8 MB" },
            { name: "paithosh-oled-2026.json", type: "code", meta: "2.4 KB" }
        ],
        "Music": [
            { name: "Lofi Beats — Chillhop.flac", type: "file", meta: "34 MB" }
        ],
        "Pictures": [
            { name: "wallpaper-oled.png", type: "file", meta: "3.2 MB" },
            { name: "desktop-shot.png", type: "file", meta: "1.8 MB" }
        ],
        "Root": [
            { name: "etc", type: "folder", meta: "System" },
            { name: "home", type: "folder", meta: "Users" },
            { name: "usr", type: "folder", meta: "Binaries" }
        ]
    })

    readonly property var visibleItems: {
        const items = fsData[currentDir] || fsData["Home"] || [];
        const q = searchQuery.trim().toLowerCase();
        const out = [];
        for (let i = 0; i < items.length; ++i) {
            const it = items[i];
            if (q !== "" && it.name.toLowerCase().indexOf(q) === -1) continue;
            if (it.type !== "folder" && filterType !== "all" && it.type !== filterType) continue;
            out.push(it);
        }
        return out;
    }

    function setMode(mode) {
        pickerMode = mode === "download" ? "download" : "upload";
        if (pickerMode === "download") {
            nameField.text = "paithosh-theme-2026.json";
            navigateTo("Downloads", false);
        } else {
            nameField.text = "";
            navigateTo("Home", false);
        }
    }

    function navigateTo(dirKey, pushHist) {
        const key = fsData[dirKey] ? dirKey : "Home";
        currentDir = key;
        selectedName = "";
        isEditingPath = false;
        if (pushHist !== false && historyStack[historyIdx] !== key) {
            const next = historyStack.slice(0, historyIdx + 1);
            next.push(key);
            historyStack = next;
            historyIdx = next.length - 1;
        }
    }

    function iconFor(type) {
        if (type === "folder") return "folder";
        if (type === "archive") return "archive";
        if (type === "code") return "code";
        return "file";
    }

    function submit() {
        const f = nameField.text.trim();
        if (f === "") return;
        shellState.closePopovers();
    }

    Component.onCompleted: setMode(shellState.pickerMode || "upload")

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left Sidebar
        Rectangle {
            Layout.preferredWidth: 226
            Layout.fillHeight: true
            color: Theme.surfaceRaised
            radius: 0
            clip: true

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.borderSubtle
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        width: 34
                        height: 34
                        radius: 10
                        color: Theme.accent
                        SvgIcon { anchors.centerIn: parent; sourceName: "folder"; iconSize: 16; color: Theme.accentFg }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { Layout.fillWidth: true; text: "File Chooser"; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.Bold; color: Theme.text; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: "xdg-desktop-portal"; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 8
                    color: Qt.rgba(1, 1, 1, filterBox.activeFocus ? 0.10 : 0.05)
                    border.width: 1
                    border.color: filterBox.activeFocus ? Theme.accent : Theme.borderSubtle

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 6
                        TextInput {
                            id: filterBox
                            Layout.fillWidth: true
                            color: Theme.text
                            font.pixelSize: 12
                            clip: true
                            onTextChanged: root.searchQuery = text
                            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "Filter files..."; color: Theme.textMuted; visible: filterBox.text === "" }
                        }
                        SvgIcon { sourceName: "search"; iconSize: 13; color: Theme.textSub }
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: pNavCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: pNavCol
                        width: parent.width
                        spacing: 2

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 8
                            color: root.currentDir === "Home" ? Qt.rgba(1, 1, 1, 0.09) : (pHomeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                            Rectangle { width: 3; height: 18; radius: 1.5; color: Theme.accent; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; opacity: root.currentDir === "Home" ? 1 : 0 }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; spacing: 10
                                SvgIcon { sourceName: "folder"; iconSize: 14; color: Theme.text }
                                Text { text: "Home"; color: Theme.text; font.pixelSize: 13; font.weight: root.currentDir === "Home" ? Font.DemiBold : Font.Normal }
                            }
                            MouseArea { id: pHomeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.navigateTo("Home", true) }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 8
                            color: pPlaceHdr.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 10
                                SvgIcon { sourceName: "folder"; iconSize: 14; color: Theme.text }
                                Text { Layout.fillWidth: true; text: "Places"; color: Theme.text; font.pixelSize: 13 }
                                SvgIcon {
                                    sourceName: "chevron-right"
                                    iconSize: 12
                                    color: Theme.textSub
                                    rotation: root.placesOpen ? 90 : 0
                                    Behavior on rotation { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                                }
                            }
                            MouseArea { id: pPlaceHdr; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.placesOpen = !root.placesOpen }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.placesOpen ? pSubCol.implicitHeight : 0
                            opacity: root.placesOpen ? 1.0 : 0.0
                            clip: true
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            Rectangle { width: 1; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.topMargin: 4; anchors.bottomMargin: 6; x: 18; color: Qt.rgba(1, 1, 1, 0.12) }

                            ColumnLayout {
                                id: pSubCol
                                anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 24
                                spacing: 2
                                Repeater {
                                    model: ["Documents", "Dev", "Downloads", "Music", "Pictures"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        readonly property bool active: root.currentDir === modelData
                                        Layout.fillWidth: true; height: 30; radius: 7
                                        color: active ? Qt.rgba(1, 1, 1, 0.09) : (pm.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                                        Rectangle { width: 3; height: 16; radius: 1.5; color: Theme.accent; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; opacity: active ? 1 : 0 }
                                        Text { anchors.fill: parent; anchors.leftMargin: 12; verticalAlignment: Text.AlignVCenter; text: modelData; color: active ? Theme.text : Theme.textSub; font.pixelSize: 12; font.weight: active ? Font.DemiBold : Font.Normal }
                                        MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.navigateTo(modelData, true) }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 8
                            color: root.currentDir === "Root" ? Qt.rgba(1, 1, 1, 0.09) : (pRootMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                            Rectangle { width: 3; height: 18; radius: 1.5; color: Theme.accent; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; opacity: root.currentDir === "Root" ? 1 : 0 }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; spacing: 10
                                SvgIcon { sourceName: "terminal"; iconSize: 14; color: Theme.text }
                                Text { text: "/ (Root)"; color: Theme.text; font.pixelSize: 13; font.weight: root.currentDir === "Root" ? Font.DemiBold : Font.Normal }
                            }
                            MouseArea { id: pRootMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.navigateTo("Root", true) }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 50
                    radius: 10
                    color: Theme.cardBg
                    border.width: 1
                    border.color: Theme.borderSubtle
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 9; spacing: 2
                        Text { text: "PORTAL MODE"; color: Theme.textSub; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.5 }
                        Text { text: root.pickerMode === "download" ? "Download (Save As)" : "Upload (Open File)"; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                }
            }
        }

        // Right Content Pane
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 18
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.currentDir === "Home" ? "~" : ("~ › " + root.currentDir)
                    color: Theme.text
                    font.pixelSize: 20
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                PillButton {
                    text: "‹"
                    horizontalPadding: 9; verticalPadding: 4
                    onClicked: {
                        if (root.historyIdx > 0) { root.historyIdx -= 1; root.navigateTo(root.historyStack[root.historyIdx], false); }
                    }
                }
                PillButton {
                    text: "›"
                    horizontalPadding: 9; verticalPadding: 4
                    onClicked: {
                        if (root.historyIdx < root.historyStack.length - 1) { root.historyIdx += 1; root.navigateTo(root.historyStack[root.historyIdx], false); }
                    }
                }
                PillButton { text: "Grid"; active: !root.isListView; horizontalPadding: 10; verticalPadding: 4; onClicked: root.isListView = false }
                PillButton { text: "List"; active: root.isListView; horizontalPadding: 10; verticalPadding: 4; onClicked: root.isListView = true }
            }

            GridView {
                id: pGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: root.isListView ? width : Math.max(126, Math.floor(width / 4))
                cellHeight: root.isListView ? 44 : 108
                model: root.visibleItems
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    required property var modelData
                    width: pGrid.cellWidth
                    height: pGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: root.isListView ? 2 : 4
                        radius: root.isListView ? 9 : 11
                        color: root.selectedName === modelData.name ? Qt.rgba(1, 1, 1, 0.13) : (pmMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                        border.width: 1
                        border.color: root.selectedName === modelData.name ? Qt.rgba(1, 1, 1, 0.45) : Theme.borderSubtle
                        scale: pmMouse.pressed ? 0.97 : 1.0
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                        RowLayout {
                            visible: root.isListView
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                            SvgIcon { sourceName: root.iconFor(modelData.type); iconSize: 18; color: Theme.text }
                            Text { Layout.fillWidth: true; text: modelData.name; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            Text { text: modelData.meta; color: Theme.textSub; font.pixelSize: 11 }
                        }

                        ColumnLayout {
                            visible: !root.isListView
                            anchors.fill: parent; anchors.margins: 10; spacing: 6
                            SvgIcon { Layout.alignment: Qt.AlignHCenter; sourceName: root.iconFor(modelData.type); iconSize: 26; color: Theme.text }
                            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData.name; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData.meta; color: Theme.textSub; font.pixelSize: 10; elide: Text.ElideRight }
                        }

                        MouseArea {
                            id: pmMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.type === "folder") {
                                    if (root.fsData[modelData.name]) root.navigateTo(modelData.name, true);
                                    return;
                                }
                                root.selectedName = modelData.name;
                                nameField.text = modelData.name;
                            }
                            onDoubleClicked: {
                                if (modelData.type !== "folder" && nameField.text.trim() !== "") root.submit();
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight; text: "Name:"; color: Theme.textSub; font.pixelSize: 12 }
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 8
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.width: 1
                    border.color: nameField.activeFocus ? Qt.rgba(1, 1, 1, 0.42) : Theme.borderSubtle
                    TextInput {
                        id: nameField
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text; font.pixelSize: 12; clip: true
                        Keys.onReturnPressed: root.submit()
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; text: "Select a file or type filename..."; color: Theme.textMuted; visible: nameField.text === "" }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight; text: "File type:"; color: Theme.textSub; font.pixelSize: 12 }
                Row {
                    spacing: 6
                    Repeater {
                        model: [
                            { key: "all", label: "All Files (*.*)" },
                            { key: "code", label: "Config & Code" },
                            { key: "archive", label: "Archives (*.zip)" }
                        ]
                        delegate: PillButton {
                            required property var modelData
                            text: modelData.label
                            active: root.filterType === modelData.key
                            fontSize: 11
                            onClicked: root.filterType = modelData.key
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: root.visibleItems.length + " items • " + (root.dirPaths[root.currentDir] || "/home/paithon")
                    color: Theme.textSub
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                PillButton { text: "✕ Cancel"; onClicked: root.shellState.closePopovers() }
                PillButton {
                    text: root.pickerMode === "download" ? "✓ Save" : "✓ Open"
                    active: nameField.text.trim() !== ""
                    onClicked: { if (nameField.text.trim() !== "") root.submit(); }
                }
            }
        }
    }
}
