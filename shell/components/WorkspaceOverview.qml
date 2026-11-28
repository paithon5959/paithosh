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

    readonly property int totalWindows: {
        let total = 0;
        for (let i = 0; i < workspaces.length; ++i) {
            total += workspaces[i].windows ? workspaces[i].windows.length : 0;
        }
        return total;
    }

    readonly property bool multiMonitor: Quickshell.screens.length > 1

    readonly property var keyHints: [
        { key: "1–0", label: "Jump" },
        { key: "↑↓←→", label: "Move" },
        { key: "↵", label: "Focus" },
        { key: "Esc", label: "Close" }
    ]

    implicitWidth: 1060
    implicitHeight: headerRow.implicitHeight + 12 + grid.implicitHeight + 10 + previewStrip.implicitHeight

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

    function primaryAppLabel(winList) {
        if (!winList || winList.length === 0) return "Empty";
        for (let i = 0; i < winList.length; ++i) {
            if (winList[i].focused) return winList[i].appClass || winList[i].title || "Window";
        }
        return winList[0].appClass || winList[0].title || "Window";
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
        implicitHeight: 30
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            radius: 8
            clip: true
            color: Theme.surfaceRaised
            border.width: 1
            border.color: Theme.borderSubtle

            SvgIcon {
                anchors.centerIn: parent
                sourceName: "layers"
                iconSize: 15
                color: Theme.textSub
            }
        }

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
            Layout.preferredHeight: 22
            Layout.preferredWidth: countText.implicitWidth + 16
            radius: 11
            clip: true
            color: Theme.surfaceRaised
            border.width: 1
            border.color: Theme.borderSubtle

            Text {
                id: countText
                anchors.centerIn: parent
                text: root.totalWindows + (root.totalWindows === 1 ? " window" : " windows")
                color: Theme.textSub
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            spacing: 10

            Repeater {
                model: root.keyHints

                delegate: RowLayout {
                    required property var modelData
                    spacing: 5

                    Rectangle {
                        Layout.preferredHeight: 20
                        Layout.preferredWidth: hintKey.implicitWidth + 10
                        radius: 5
                        clip: true
                        color: Theme.surfaceRaised
                        border.width: 1
                        border.color: Theme.borderSubtle

                        Text {
                            id: hintKey
                            anchors.centerIn: parent
                            text: modelData.key
                            color: Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }

                    Text {
                        text: modelData.label
                        color: Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    // 5x2 Workspace Grid
    GridLayout {
        id: grid
        anchors.top: headerRow.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        columns: 5
        columnSpacing: 10
        rowSpacing: 10

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
                Layout.preferredHeight: 154
                radius: 16
                clip: true

                color: {
                    if (isFocused) {
                        return wsMouse.containsMouse
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                            : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14);
                    }
                    if (wsMouse.containsMouse || isSelected) return Theme.cardHover;
                    if (hasWindows) return Theme.cardBg;
                    return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.035);
                }
                border.width: isFocused ? 1.5 : 1
                border.color: {
                    if (isFocused) return Theme.accent;
                    if (isSelected || wsMouse.containsMouse) {
                        return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45);
                    }
                    return Theme.borderSubtle;
                }

                scale: wsMouse.pressed ? 0.96 : 1.0

                Behavior on color {
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on border.color {
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on border.width {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
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

                    // Mini Desktop Geometry Preview (concentric: 16 - 8 = 8)
                    Rectangle {
                        id: previewArea
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        clip: true
                        color: Theme.surfaceBg
                        border.width: 1
                        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, wsCard.hasWindows ? 0.10 : 0.06)

                        Behavior on border.color {
                            ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }

                        // Empty Workspace Watermark
                        Text {
                            anchors.centerIn: parent
                            visible: !wsCard.hasWindows
                            text: wsCard.modelData.id
                            color: wsCard.isFocused ? Theme.accent : Theme.textMuted
                            opacity: (wsCard.isFocused || wsCard.isSelected || wsMouse.containsMouse) ? 0.85 : 0.35
                            font.family: Theme.fontMono
                            font.pixelSize: 20
                            font.weight: Font.Bold

                            Behavior on opacity {
                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }
                            Behavior on color {
                                ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }
                        }

                        // Miniature Window Tiles
                        Repeater {
                            model: wsCard.winList

                            delegate: AdaptiveClipRect {
                                id: winTile
                                required property var modelData

                                readonly property real pad: 3
                                readonly property real areaW: Math.max(1, previewArea.width - pad * 2)
                                readonly property real areaH: Math.max(1, previewArea.height - pad * 2)

                                x: pad + modelData.relX * areaW
                                y: pad + modelData.relY * areaH
                                width: Math.max(22, Math.min(areaW - (x - pad), modelData.relW * areaW))
                                height: Math.max(18, Math.min(areaH - (y - pad), modelData.relH * areaH))
                                radius: 5
                                clip: true

                                color: {
                                    if (winMouse.containsMouse) return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.20);
                                    if (modelData.focused) return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15);
                                    return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.09);
                                }
                                border.width: 1
                                border.color: {
                                    if (modelData.focused) return Theme.accent;
                                    if (winMouse.containsMouse) return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45);
                                    return Theme.borderSubtle;
                                }
                                scale: winMouse.pressed ? 0.94 : 1.0

                                Behavior on color {
                                    ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                                }
                                Behavior on border.color {
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
                                    live: !Theme.reduceMotion
                                    visible: captureSource !== null && hasContent
                                }

                                // Subtle hover scrim over live thumbnail
                                Rectangle {
                                    anchors.fill: parent
                                    visible: liveThumb.visible
                                    color: Qt.rgba(Theme.pillBg.r, Theme.pillBg.g, Theme.pillBg.b, winMouse.containsMouse ? 0.24 : 0.08)

                                    Behavior on color {
                                        ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                }

                                MouseArea {
                                    id: winMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.selectedIdx = wsCard.index
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
                                    radius: 4
                                    clip: true
                                    color: liveThumb.visible
                                        ? Qt.rgba(Theme.pillBg.r, Theme.pillBg.g, Theme.pillBg.b, 0.78)
                                        : "transparent"

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

                                // Hover Close Button (top-right, animated opacity & scale)
                                Rectangle {
                                    id: closeBtn
                                    readonly property bool shouldShow: (winMouse.containsMouse || closeMouse.containsMouse)
                                        && winTile.width >= 36 && winTile.height >= 24
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 4
                                    width: 16
                                    height: 16
                                    radius: 8
                                    clip: true
                                    opacity: shouldShow ? 1.0 : 0.0
                                    visible: opacity > 0.01
                                    color: closeMouse.containsMouse
                                        ? Theme.danger
                                        : Qt.rgba(Theme.pillBg.r, Theme.pillBg.g, Theme.pillBg.b, 0.80)
                                    scale: closeMouse.pressed ? 0.88 : (shouldShow ? 1.0 : 0.82)

                                    Behavior on opacity {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 160
                                            easing.type: Easing.OutBack
                                            easing.overshoot: Theme.springOvershoot
                                        }
                                    }

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
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 18
                            radius: 5
                            clip: true
                            color: wsCard.isFocused
                                ? Theme.accent
                                : (wsCard.hasWindows ? Theme.surfaceRaised : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06))

                            Behavior on color {
                                ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: wsCard.modelData.id
                                color: wsCard.isFocused
                                    ? Theme.accentFg
                                    : (wsCard.hasWindows ? Theme.text : Theme.textMuted)
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                font.weight: Font.Bold

                                Behavior on color {
                                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: root.primaryAppLabel(wsCard.winList)
                            color: wsCard.isFocused
                                ? Theme.text
                                : (wsCard.hasWindows ? Theme.textSub : Theme.textMuted)
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: wsCard.isFocused ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight

                            Behavior on color {
                                ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }
                        }

                        Rectangle {
                            visible: wsCard.winList.length > 1
                            Layout.preferredHeight: 16
                            Layout.preferredWidth: winCountTxt.implicitWidth + 8
                            radius: 5
                            clip: true
                            color: Theme.surfaceRaised
                            border.width: 1
                            border.color: Theme.borderSubtle

                            Text {
                                id: winCountTxt
                                anchors.centerIn: parent
                                text: "+" + (wsCard.winList.length - 1)
                                color: Theme.textSub
                                font.family: Theme.fontMono
                                font.pixelSize: 9
                                font.weight: Font.Medium
                            }
                        }

                        Rectangle {
                            visible: root.multiMonitor && wsCard.modelData.monitorName !== "" && wsCard.hasWindows
                            Layout.preferredHeight: 16
                            Layout.preferredWidth: Math.min(54, monTxt.implicitWidth + 8)
                            radius: 5
                            clip: true
                            color: Theme.surfaceRaised
                            border.width: 1
                            border.color: Theme.borderSubtle

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

    // Selected Workspace Inspector Strip
    Rectangle {
        id: previewStrip
        anchors.top: grid.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: 40
        radius: 14
        clip: true
        color: Theme.surfaceRaised
        border.width: 1
        border.color: Theme.borderSubtle

        readonly property var selWs: (root.selectedIdx >= 0 && root.selectedIdx < root.workspaces.length)
            ? root.workspaces[root.selectedIdx]
            : null
        readonly property var selWins: (selWs && selWs.windows) ? selWs.windows : []
        readonly property bool selFocused: Boolean(selWs && selWs.isFocused)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 20
                radius: 6
                clip: true
                color: previewStrip.selFocused ? Theme.accent : Theme.cardBg

                Behavior on color {
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    text: previewStrip.selWs ? previewStrip.selWs.id : (root.selectedIdx + 1)
                    color: previewStrip.selFocused ? Theme.accentFg : Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    font.weight: Font.Bold

                    Behavior on color {
                        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                }
            }

            Text {
                visible: previewStrip.selWins.length === 0
                text: "Workspace " + (root.selectedIdx + 1) + " • Empty"
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
                        id: winChip
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.maximumWidth: 220
                        Layout.minimumWidth: 64
                        Layout.preferredHeight: 26
                        radius: 7
                        clip: true
                        color: {
                            if (chipMouse.containsMouse) return Theme.cardHover;
                            if (modelData.focused) return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14);
                            return Theme.cardBg;
                        }
                        border.width: 1
                        border.color: {
                            if (modelData.focused) return Theme.accent;
                            if (chipMouse.containsMouse) return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45);
                            return Theme.borderSubtle;
                        }
                        scale: chipMouse.pressed ? 0.95 : 1.0

                        Behavior on color {
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on border.color {
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutBack
                                easing.overshoot: Theme.springOvershoot
                            }
                        }

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

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.MiddleButton) {
                                    CompositorService.closeWindow(winChip.modelData.address);
                                    refreshDebounce.restart();
                                } else {
                                    root.activateWindow(winChip.modelData.address);
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: previewStrip.selWins.length > 4
                    text: "+" + (previewStrip.selWins.length - 4)
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
            }
        }
    }
}
