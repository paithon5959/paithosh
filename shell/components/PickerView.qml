import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."
import "../services"
import "common"

Item {
    id: root
    required property var shellState

    property string pickerMode: "upload" // "upload" | "download"
    property string currentDir: "Home"
    property bool isListView: true
    property bool isEditingPath: false
    property string selectedName: ""
    property string filterType: "all" // "all" | "code" | "archive"

    implicitWidth: 860
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

    function setMode(mode) {
        pickerMode = mode === "download" ? "download" : "upload";
        if (pickerMode === "download") {
            nameField.text = "paithosh-theme-2026.json";
            navigateTo("Downloads");
        } else {
            nameField.text = "";
            navigateTo("Home");
        }
    }

    function navigateTo(dirKey) {
        currentDir = fsData[dirKey] ? dirKey : "Home";
        selectedName = "";
        isEditingPath = false;
    }

    function filteredItems() {
        const list = fsData[currentDir] || [];
        if (filterType === "all") return list;
        return list.filter(function(it) {
            return it.type === "folder" || it.type === filterType;
        });
    }

    function confirmSelection() {
        const f = nameField.text.trim();
        if (f === "") return;
        const full = (dirPaths[currentDir] || "/home/paithon") + "/" + f;
        NotificationService.pushPreviewNotification(
            pickerMode === "download" ? "Download Location" : "Upload Location",
            pickerMode === "download" ? "Saved File" : "Selected File",
            full
        );
        shellState.closePopovers();
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left Sidebar (Inherits FilesView)
        Rectangle {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            color: Theme.surfaceRaised
            radius: 16
            border.width: 1
            border.color: Theme.borderSubtle
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        width: 34
                        height: 34
                        radius: 10
                        color: Theme.accent
                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: "folder"
                            iconSize: 16
                            color: Theme.accentFg
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: root.pickerMode === "download" ? "Save Location" : "This page wants to open"
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: Theme.text
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "xdg-desktop-portal"
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            color: Theme.textSub
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: ["Home", "Documents", "Dev", "Downloads", "Music", "Pictures", "Root"]

                    delegate: Rectangle {
                        required property string modelData
                        readonly property bool isActive: root.currentDir === modelData
                        width: ListView.view.width
                        height: 32
                        radius: 8
                        color: isActive ? Theme.cardHover : (pSideMouse.containsMouse ? Theme.cardBg : "transparent")
                        Behavior on color { ColorAnimation { duration: 140 } }

                        Rectangle {
                            width: 3
                            height: 16
                            radius: 2
                            anchors.left: parent.left
                            anchors.leftMargin: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.accent
                            opacity: isActive ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10
                            text: modelData === "Root" ? "/ (Root)" : modelData
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: isActive ? Font.DemiBold : Font.Normal
                            color: isActive ? Theme.text : Theme.textSub
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: pSideMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.navigateTo(modelData)
                        }
                    }
                }
            }
        }

        // Right Content + Portal Bottom Bar
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 18
            Layout.rightMargin: 4
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    height: 36
                    radius: 9
                    color: root.isEditingPath ? Theme.cardHover : (pPathMouse.containsMouse ? Theme.cardBg : "transparent")
                    border.width: root.isEditingPath ? 1 : 0
                    border.color: Theme.borderSubtle
                    clip: true

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        visible: !root.isEditingPath
                        text: root.currentDir === "Home" ? "~" : ("~ › " + root.currentDir)
                        font.family: Theme.fontSans
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        color: Theme.text
                        elide: Text.ElideRight
                    }

                    TextField {
                        id: pPathField
                        anchors.fill: parent
                        anchors.margins: 2
                        visible: root.isEditingPath
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        background: Item {}
                        onAccepted: {
                            const seg = text.replace(/\/+$/, "").split("/").pop().toLowerCase();
                            const keys = Object.keys(root.fsData);
                            let target = "Home";
                            for (let i = 0; i < keys.length; i++) {
                                if (keys[i].toLowerCase() === seg) { target = keys[i]; break; }
                            }
                            root.navigateTo(target);
                        }
                        Keys.onEscapePressed: root.isEditingPath = false
                    }

                    MouseArea {
                        id: pPathMouse
                        anchors.fill: parent
                        visible: !root.isEditingPath
                        hoverEnabled: true
                        cursorShape: Qt.IBeamCursor
                        onClicked: {
                            pPathField.text = root.dirPaths[root.currentDir] || "/home/paithon";
                            root.isEditingPath = true;
                            pPathField.forceActiveFocus();
                            pPathField.selectAll();
                        }
                    }
                }

                PillButton {
                    text: root.isListView ? "Grid" : "List"
                    onClicked: root.isListView = !root.isListView
                }
            }

            GridView {
                id: pickerGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: root.isListView ? width : 148
                cellHeight: root.isListView ? 44 : 102
                model: root.filteredItems()

                delegate: Item {
                    required property var modelData
                    width: pickerGrid.cellWidth
                    height: pickerGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 10
                        readonly property bool isSel: root.selectedName === modelData.name
                        color: isSel ? Theme.cardHover : (pfMouse.containsMouse ? Theme.cardBg : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03))
                        border.width: 1
                        border.color: isSel ? Theme.accent : Theme.borderSubtle
                        scale: pfMouse.pressed ? 0.97 : 1.0
                        clip: true

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            visible: root.isListView
                            spacing: 10
                            SvgIcon { sourceName: modelData.type === "folder" ? "folder" : "file"; iconSize: 16; color: Theme.text }
                            Text { Layout.fillWidth: true; text: modelData.name; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                            Text { text: modelData.meta; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            visible: !root.isListView
                            spacing: 4
                            SvgIcon { Layout.alignment: Qt.AlignHCenter; sourceName: modelData.type === "folder" ? "folder" : "file"; iconSize: 24; color: Theme.text }
                            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData.name; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData.meta; font.family: Theme.fontSans; font.pixelSize: 10; color: Theme.textSub; elide: Text.ElideRight }
                        }

                        MouseArea {
                            id: pfMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.type === "folder") {
                                    if (root.fsData[modelData.name]) root.navigateTo(modelData.name);
                                    return;
                                }
                                root.selectedName = modelData.name;
                                nameField.text = modelData.name;
                            }
                            onDoubleClicked: {
                                if (modelData.type !== "folder") {
                                    nameField.text = modelData.name;
                                    root.confirmSelection();
                                }
                            }
                        }
                    }
                }
            }

            // Bottom Upload / Download Dialog Controls
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 10
                rowSpacing: 8

                Text {
                    text: "Name:"
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    color: Theme.textSub
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 64
                }
                TextField {
                    id: nameField
                    Layout.fillWidth: true
                    placeholderText: "Select a file or type filename..."
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    background: Rectangle { radius: 8; color: Theme.cardBg; border.width: 1; border.color: Theme.borderSubtle }
                    onAccepted: root.confirmSelection()
                }

                Text {
                    text: "File type:"
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    color: Theme.textSub
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 64
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { key: "all", label: "All Files (*.*)" },
                            { key: "code", label: "Config & Code" },
                            { key: "archive", label: "Archives (.zip)" }
                        ]
                        delegate: PillButton {
                            required property var modelData
                            text: modelData.label
                            active: root.filterType === modelData.key
                            onClicked: root.filterType = modelData.key
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: root.dirPaths[root.currentDir] || "/home/paithon"
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textSub
                    elide: Text.ElideRight
                }
                PillButton {
                    text: "✕ Cancel"
                    onClicked: root.shellState.closePopovers()
                }
                PillButton {
                    text: root.pickerMode === "download" ? "✓ Save" : "✓ Open"
                    active: true
                    enabled: nameField.text.trim() !== ""
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: root.confirmSelection()
                }
            }
        }
    }
}
