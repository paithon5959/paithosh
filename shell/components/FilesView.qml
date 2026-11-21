import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."
import "common"

Item {
    id: root
    required property var shellState

    property string currentDir: "Home"
    property bool isListView: false
    property bool isEditingPath: false
    property string selectedName: ""
    property string statusMessage: ""
    property bool pwdOpen: false
    property string pendingArchive: ""

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
            { name: "secret-keys.zip", type: "archive", meta: "Encrypted • 2.4 MB" }
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

    function navigateTo(dirKey) {
        currentDir = fsData[dirKey] ? dirKey : "Home";
        selectedName = "";
        isEditingPath = false;
        statusMessage = (fsData[currentDir] || []).length + " items • " + (dirPaths[currentDir] || "/home/paithon");
    }

    function openItem(item) {
        if (item.type === "folder") {
            if (fsData[item.name]) navigateTo(item.name);
        } else if (item.type === "archive") {
            pendingArchive = item.name;
            pwdInput.text = "";
            pwdOpen = true;
            pwdInput.forceActiveFocus();
        } else {
            statusMessage = "Opened " + item.name;
        }
    }

    Component.onCompleted: navigateTo("Home")

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left Sidebar
        Rectangle {
            Layout.preferredWidth: 236
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
                        Text { Layout.fillWidth: true; text: "Files"; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.Bold; color: Theme.text; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: "paithon@hyprland"; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
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
                        color: isActive ? Theme.cardHover : (sideMouse.containsMouse ? Theme.cardBg : "transparent")
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
                            id: sideMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.navigateTo(modelData)
                        }
                    }
                }
            }
        }

        // Right Content Pane
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 18
            Layout.rightMargin: 4
            spacing: 10

            // Header with Editable Path Breadcrumb + Grid/List Toggle
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    height: 36
                    radius: 9
                    color: root.isEditingPath ? Theme.cardHover : (pathMouse.containsMouse ? Theme.cardBg : "transparent")
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
                        id: pathField
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
                        id: pathMouse
                        anchors.fill: parent
                        visible: !root.isEditingPath
                        hoverEnabled: true
                        cursorShape: Qt.IBeamCursor
                        onClicked: {
                            pathField.text = root.dirPaths[root.currentDir] || "/home/paithon";
                            root.isEditingPath = true;
                            pathField.forceActiveFocus();
                            pathField.selectAll();
                        }
                    }
                }

                PillButton {
                    text: root.isListView ? "Grid" : "List"
                    onClicked: root.isListView = !root.isListView
                }
            }

            // File Grid / List
            GridView {
                id: fileGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: root.isListView ? width : 148
                cellHeight: root.isListView ? 46 : 106
                model: root.fsData[root.currentDir] || []

                delegate: Item {
                    required property var modelData
                    width: fileGrid.cellWidth
                    height: fileGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 10
                        readonly property bool isSel: root.selectedName === modelData.name
                        color: isSel ? Theme.cardHover : (fMouse.containsMouse ? Theme.cardBg : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03))
                        border.width: 1
                        border.color: isSel ? Theme.accent : Theme.borderSubtle
                        scale: fMouse.pressed ? 0.97 : 1.0
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
                            SvgIcon { Layout.alignment: Qt.AlignHCenter; sourceName: modelData.type === "folder" ? "folder" : "file"; iconSize: 26; color: Theme.text }
                            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData.name; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData.meta; font.family: Theme.fontSans; font.pixelSize: 10; color: Theme.textSub; elide: Text.ElideRight }
                        }

                        MouseArea {
                            id: fMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedName = modelData.name
                            onDoubleClicked: root.openItem(modelData)
                        }
                    }
                }
            }

            // Footer Bar
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.borderSubtle
            }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: root.statusMessage
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textSub
                    elide: Text.ElideRight
                }
                Text {
                    text: "512 GB NVMe • 218 GB free"
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textSub
                }
            }
        }
    }

    // Encrypted Archive Password Input Dialog
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)
        radius: 16
        visible: root.pwdOpen
        z: 20

        MouseArea { anchors.fill: parent; onClicked: root.pwdOpen = false }

        Rectangle {
            width: 340
            height: 170
            anchors.centerIn: parent
            radius: 16
            color: Theme.surfaceRaised
            border.width: 1
            border.color: Theme.borderSubtle

            MouseArea { anchors.fill: parent; onClicked: function(m) { m.accepted = true; } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10
                Text { text: "Encrypted Archive"; font.family: Theme.fontSans; font.pixelSize: 15; font.weight: Font.Bold; color: Theme.text }
                Text { text: "Enter password for " + root.pendingArchive; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight; Layout.fillWidth: true }
                TextField {
                    id: pwdInput
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: "Archive password..."
                    color: Theme.text
                    background: Rectangle { radius: 8; color: Theme.cardBg; border.width: 1; border.color: Theme.borderSubtle }
                    onAccepted: {
                        if (text.trim() !== "") {
                            root.statusMessage = "Extracted " + root.pendingArchive;
                            root.pwdOpen = false;
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    PillButton { text: "Cancel"; onClicked: root.pwdOpen = false }
                    PillButton {
                        text: "Unlock"
                        active: true
                        onClicked: {
                            if (pwdInput.text.trim() !== "") {
                                root.statusMessage = "Extracted " + root.pendingArchive;
                                root.pwdOpen = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
