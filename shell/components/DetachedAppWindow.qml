import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."
import "common"

FloatingWindow {
    id: root

    required property var shellState

    readonly property string appKind: shellState.detachedApp
    readonly property bool isOpen: appKind !== ""

    title: {
        if (appKind === "settings") return "Settings (Detached)";
        if (appKind === "files") return "Files (Detached)";
        if (appKind === "music") return "Music (Detached)";
        if (appKind === "picker") {
            if (shellState.pickerDirectory) return "Select Folder (Detached)";
            return shellState.pickerMode === "download" ? "Save Location (Detached)" : "Upload Location (Detached)";
        }
        return "Paithosh";
    }

    visible: isOpen
    implicitWidth: 900
    implicitHeight: 580
    minimumSize: Qt.size(640, 420)
    color: Theme.surfaceBg

    onVisibleChanged: {
        if (visible) {
            if (appKind === "settings" && settingsLoader.item) {
                settingsLoader.item.openPage(shellState.settingsPage || "home");
            } else if (appKind === "picker" && pickerLoader.item) {
                pickerLoader.item.initFromState();
                pickerLoader.item.forceActiveFocus();
            } else if (appKind === "files" && filesLoader.item) {
                filesLoader.item.forceActiveFocus();
            } else if (appKind === "music" && musicLoader.item) {
                musicLoader.item.forceActiveFocus();
            }
        } else if (isOpen) {
            shellState.closeDetachedApp();
        }
    }

    AdaptiveClipRect {
        anchors.fill: parent
        radius: 14
        color: Theme.surfaceBg
        border.width: 1
        border.color: Theme.borderSubtle

        ThemeGradientFill {
            anchors.fill: parent
            anchors.margins: 1
            enabled: Theme.surfaceGradientEnabled
            color1: Theme.surfaceBg
            colorMid: Theme.surfaceBgMid
            color2: Theme.surfaceBg2
            cornerRadius: 13
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Top Drag Strip (Native Wayland Move + Re-Attach to Dynamic Island)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                color: Theme.surfaceRaised
                topLeftRadius: 13
                topRightRadius: 13

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Theme.borderSubtle
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    onPressed: root.startSystemMove()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: root.title
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 44
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.25)
                    }

                    Item { Layout.fillWidth: true }

                    PillButton {
                        text: root.shellState.barPosition === "bottom" ? "Attach ↓" : "Attach ↑"
                        fontSize: 11
                        horizontalPadding: 10
                        verticalPadding: 4
                        radius: 8
                        onClicked: root.shellState.reattachIslandApp(root.appKind)
                    }

                    PillButton {
                        iconName: "close"
                        iconSize: 12
                        horizontalPadding: 7
                        verticalPadding: 5
                        radius: 8
                        onClicked: root.shellState.closeDetachedApp()
                    }
                }
            }

            // Detached App Content (Lazy-loaded to avoid idle RAM & background scans)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Loader {
                    id: settingsLoader
                    anchors.fill: parent
                    active: root.visible && root.appKind === "settings"
                    function ensureSource() {
                        if (active && source.toString() === "") setSource("SettingsView.qml", { shellState: root.shellState });
                    }
                    Component.onCompleted: ensureSource()
                    onActiveChanged: ensureSource()
                    onLoaded: if (item) item.openPage(root.shellState.settingsPage || "home")
                }

                Loader {
                    id: filesLoader
                    anchors.fill: parent
                    active: root.visible && root.appKind === "files"
                    function ensureSource() {
                        if (active && source.toString() === "") setSource("FilesView.qml", { shellState: root.shellState });
                    }
                    Component.onCompleted: ensureSource()
                    onActiveChanged: ensureSource()
                    onLoaded: if (item) Qt.callLater(() => { if (item) item.forceActiveFocus(); })
                }

                Loader {
                    id: musicLoader
                    anchors.fill: parent
                    active: root.visible && root.appKind === "music"
                    function ensureSource() {
                        if (active && source.toString() === "") setSource("MusicView.qml", { shellState: root.shellState });
                    }
                    Component.onCompleted: ensureSource()
                    onActiveChanged: ensureSource()
                    onLoaded: if (item) Qt.callLater(() => { if (item) item.forceActiveFocus(); })
                }

                Loader {
                    id: pickerLoader
                    anchors.fill: parent
                    active: root.visible && root.appKind === "picker"
                    function ensureSource() {
                        if (active && source.toString() === "") setSource("PickerView.qml", { shellState: root.shellState, isDetached: true });
                    }
                    Component.onCompleted: ensureSource()
                    onActiveChanged: ensureSource()
                    onLoaded: if (item) {
                        item.initFromState();
                        Qt.callLater(() => { if (item) item.forceActiveFocus(); });
                    }
                }
            }
        }
    }
}
