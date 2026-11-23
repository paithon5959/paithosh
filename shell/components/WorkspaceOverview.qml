import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import ".."
import "../services"
import "common"

Item {
    id: root

    required property var shellState

    property var workspaces: []
    property int selectedIdx: 0

    implicitWidth: 1060
    implicitHeight: headerRow.implicitHeight + 14 + grid.implicitHeight + 12 + 40

    function refresh() {
        workspaces = CompositorService.workspaceOverviewModel();
    }

    function resetAndFocus() {
        CompositorService.refreshOverviewData();
        refresh();
        refreshDebounce.restart();
        let focusedIdx = 0;
        for (let i = 0; i < workspaces.length; ++i) {
            if (workspaces[i].isFocused) {
                focusedIdx = i;
                break;
            }
        }
        selectedIdx = focusedIdx;
        focusTimer.restart();
    }

    function activateWorkspace(wsId) {
        CompositorService.switchWorkspace(wsId);
        shellState.closePopovers();
    }

    function activateWindow(addr) {
        if (addr && addr !== "") {
            CompositorService.focusWindow(addr);
        }
        shellState.closePopovers();
    }

    function moveSelection(delta) {
        const next = selectedIdx + delta;
        if (next >= 0 && next < 10) {
            selectedIdx = next;
        }
    }

    function totalWindowCount() {
        let total = 0;
        for (let i = 0; i < workspaces.length; ++i) {
            total += workspaces[i].windows ? workspaces[i].windows.length : 0;
        }
        return total;
    }

    Timer {
        id: focusTimer
        interval: 50
        repeat: false
        onTriggered: root.forceActiveFocus()
    }

    Timer {
        id: refreshDebounce
        interval: 45
        repeat: false
        onTriggered: root.refresh()
    }

    Connections {
        target: Hyprland
        enabled: CompositorService.isHyprland && root.visible
        function onRawEvent(event) {
            const n = event.name;
            if (n === "workspacev2" || n === "openwindow" || n === "closewindow"
                || n === "movewindow" || n === "activewindow" || n === "fullscreen") {
                refreshDebounce.restart();
            }
        }
    }

    Component.onCompleted: refresh()

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            root.shellState.closePopovers();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateWorkspace(root.selectedIdx + 1);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Left) {
            root.moveSelection(-1);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Right) {
            root.moveSelection(1);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Up) {
            root.moveSelection(-5);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Down) {
            root.moveSelection(5);
            event.accepted = true;
            return;
        }
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.activateWorkspace(event.key - Qt.Key_0);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_0) {
            root.activateWorkspace(10);
            event.accepted = true;
            return;
        }
    }

    // Header Row
    RowLayout {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        Text {
            text: "Workspaces"
            color: Theme.text
            font.family: Theme.fontSans
            font.pixelSize: 15
            font.weight: Font.Bold
            elide: Text.ElideRight
            Layout.minimumWidth: 0
        }

        Rectangle {
            height: 22
            width: countText.implicitWidth + 16
            radius: 11
            clip: true
            color: Theme.cardBg
            border.width: 1
            border.color: Theme.borderSubtle

            Text {
                id: countText
                anchors.centerIn: parent
                text: root.totalWindowCount() + " windows"
                color: Theme.textSub
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }

        Item { Layout.fillWidth: true }

        Text {
            text: "1–0 Jump  •  Arrows Navigate  •  Enter Focus  •  Esc Close"
            color: Theme.textMuted
            font.family: Theme.fontSans
            font.pixelSize: 11
            elide: Text.ElideRight
            Layout.minimumWidth: 0
            Layout.maximumWidth: 420
        }
    }

    // 5x2 Workspace Grid
    GridLayout {
        id: grid
        anchors.top: headerRow.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        columns: 5
        columnSpacing: 12
        rowSpacing: 12

        Repeater {
            model: root.workspaces

            delegate: Rectangle {
                id: wsCard
                required property var modelData
                required property int index

                readonly property bool isSelected: root.selectedIdx === index
                readonly property bool isFocused: Boolean(modelData.isFocused)
                readonly property var winList: modelData.windows || []
                readonly property bool hasWindows: winList.length > 0

                Layout.fillWidth: true
                Layout.preferredHeight: 158
                radius: 16
                clip: true

                color: {
                    if (wsMouse.containsMouse) return Theme.cardHover;
                    if (isFocused) return Qt.rgba(1, 1, 1, 0.11);
                    return Theme.cardBg;
                }
                border.width: (isFocused || isSelected) ? 1.5 : 1
                border.color: {
                    if (isFocused) return Theme.accent;
                    if (isSelected) return Qt.rgba(1, 1, 1, 0.48);
                    return Theme.borderSubtle;
                }

                scale: wsMouse.pressed ? 0.95 : 1.0

                Behavior on color {
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on border.color {
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutBack
                        easing.overshoot: Theme.springOvershoot
                    }
                }

                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selectedIdx = wsCard.index
                    onClicked: root.activateWorkspace(wsCard.modelData.id)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    // Mini Desktop Geometry Preview
                    Rectangle {
                        id: previewArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
                        clip: true
                        color: Theme.surfaceBg
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)

                        // Empty Workspace Watermark
                        Text {
                            anchors.centerIn: parent
                            visible: !wsCard.hasWindows
                            text: wsCard.modelData.id
                            color: wsCard.isFocused ? Theme.textSub : Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 20
                            font.weight: Font.Bold
                        }

                        // Miniature Window Tiles
                        Repeater {
                            model: wsCard.winList

                            delegate: ClippingRectangle {
                                id: winTile
                                required property var modelData

                                readonly property real pad: 3
                                readonly property real areaW: Math.max(1, previewArea.width - pad * 2)
                                readonly property real areaH: Math.max(1, previewArea.height - pad * 2)

                                x: pad + modelData.relX * areaW
                                y: pad + modelData.relY * areaH
                                width: Math.max(22, Math.min(areaW - (x - pad), modelData.relW * areaW))
                                height: Math.max(18, Math.min(areaH - (y - pad), modelData.relH * areaH))
                                radius: 7
                                clip: true

                                color: {
                                    if (winMouse.containsMouse) return Qt.rgba(1, 1, 1, 0.24);
                                    if (modelData.focused) return Qt.rgba(1, 1, 1, 0.20);
                                    return Qt.rgba(1, 1, 1, 0.11);
                                }
                                border.width: 1
                                border.color: modelData.focused ? Theme.accent : Qt.rgba(1, 1, 1, 0.18)
                                scale: winMouse.pressed ? 0.94 : 1.0

                                Behavior on color {
                                    ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                                }
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 160
                                        easing.type: Easing.OutBack
                                        easing.overshoot: Theme.springOvershoot
                                    }
                                }

                                // Live window thumbnail via Wayland ScreencopyView
                                ScreencopyView {
                                    id: liveThumb
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    captureSource: root.visible && winTile.modelData.wayland ? winTile.modelData.wayland : null
                                    live: true
                                    visible: captureSource !== null && hasContent
                                }

                                // Subtle hover tint over thumbnail
                                Rectangle {
                                    anchors.fill: parent
                                    visible: liveThumb.visible
                                    color: winMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(0, 0, 0, 0.08)
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }

                                MouseArea {
                                    id: winMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.MiddleButton) {
                                            CompositorService.closeWindow(winTile.modelData.address);
                                            refreshDebounce.restart();
                                        } else {
                                            root.activateWindow(winTile.modelData.address);
                                        }
                                    }
                                }

                                // Bottom compact app label pill
                                Rectangle {
                                    visible: winTile.width >= 38 && winTile.height >= 24
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 4
                                    height: 16
                                    radius: 5
                                    clip: true
                                    color: liveThumb.visible ? Qt.rgba(0, 0, 0, 0.72) : "transparent"

                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: 5
                                        anchors.rightMargin: 5
                                        verticalAlignment: Text.AlignVCenter
                                        text: winTile.modelData.appClass || winTile.modelData.title
                                        color: Theme.text
                                        font.family: Theme.fontSans
                                        font.pixelSize: 9
                                        font.weight: winTile.modelData.focused ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                    }
                                }

                                // Hover Close Button (top-right)
                                Rectangle {
                                    id: closeBtn
                                    visible: winMouse.containsMouse && winTile.width >= 36 && winTile.height >= 24
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 4
                                    width: 16
                                    height: 16
                                    radius: 8
                                    clip: true
                                    color: closeMouse.containsMouse ? Theme.danger : Qt.rgba(0, 0, 0, 0.72)
                                    scale: closeMouse.pressed ? 0.88 : 1.0

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                                    SvgIcon {
                                        anchors.centerIn: parent
                                        sourceName: "close"
                                        iconSize: 8
                                        color: Theme.text
                                    }

                                    MouseArea {
                                        id: closeMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            CompositorService.closeWindow(winTile.modelData.address);
                                            refreshDebounce.restart();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Card Footer
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            width: 20
                            height: 18
                            radius: 6
                            clip: true
                            color: wsCard.isFocused ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)

                            Behavior on color { ColorAnimation { duration: 160 } }

                            Text {
                                anchors.centerIn: parent
                                text: wsCard.modelData.id
                                color: wsCard.isFocused ? Theme.accentFg : Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: {
                                if (wsCard.winList.length === 0) return "Empty";
                                if (wsCard.winList.length === 1) return wsCard.winList[0].appClass || "1 window";
                                return wsCard.winList.length + " windows";
                            }
                            color: wsCard.isFocused ? Theme.text : Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: wsCard.isFocused ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            visible: wsCard.modelData.monitorName !== "" && wsCard.hasWindows
                            height: 16
                            width: Math.min(54, monTxt.implicitWidth + 8)
                            radius: 5
                            clip: true
                            color: Qt.rgba(1, 1, 1, 0.08)

                            Text {
                                id: monTxt
                                anchors.centerIn: parent
                                width: parent.width - 6
                                horizontalAlignment: Text.AlignHCenter
                                text: wsCard.modelData.monitorName
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    // Hovered / Selected Workspace Preview Strip
    Rectangle {
        id: previewStrip
        anchors.top: grid.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: 38
        radius: 12
        clip: true
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle

        readonly property var selWs: (root.selectedIdx >= 0 && root.selectedIdx < root.workspaces.length)
            ? root.workspaces[root.selectedIdx]
            : null
        readonly property var selWins: (selWs && selWs.windows) ? selWs.windows : []

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Rectangle {
                width: 22
                height: 20
                radius: 6
                clip: true
                color: (previewStrip.selWs && previewStrip.selWs.isFocused) ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)

                Text {
                    anchors.centerIn: parent
                    text: previewStrip.selWs ? previewStrip.selWs.id : (root.selectedIdx + 1)
                    color: (previewStrip.selWs && previewStrip.selWs.isFocused) ? Theme.accentFg : Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
            }

            Text {
                visible: previewStrip.selWins.length === 0
                text: "Workspace " + (root.selectedIdx + 1) + " — Empty"
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }

            RowLayout {
                visible: previewStrip.selWins.length > 0
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 6

                Repeater {
                    model: previewStrip.selWins.slice(0, 4)

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.maximumWidth: 210
                        Layout.minimumWidth: 60
                        height: 24
                        radius: 8
                        clip: true
                        color: modelData.focused ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        border.color: modelData.focused ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.title || modelData.appClass
                            color: modelData.focused ? Theme.text : Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: modelData.focused ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                    }
                }

                Text {
                    visible: previewStrip.selWins.length > 4
                    text: "+" + (previewStrip.selWins.length - 4) + " more"
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
            }
        }
    }
}
