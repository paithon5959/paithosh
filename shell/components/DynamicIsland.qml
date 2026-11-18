import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."
import "../services"
import "common"

PanelWindow {
    id: root

    required property var shellState
    property var modelData

    screen: modelData
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 132
    color: "transparent"

    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "paithosh-island"
    WlrLayershell.keyboardFocus: isSearchOnThisScreen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property bool isActiveScreen: shellState.activeScreen === modelData
    readonly property bool isPopoverOpenOnThisScreen: isActiveScreen && shellState.openPopover !== ""
    readonly property bool isSearchOnThisScreen: isActiveScreen && shellState.openPopover === "search"
    readonly property bool isHidden: shellState.manualHideBar || CompositorService.isFullscreenFor(modelData)

    readonly property string activeTitle: CompositorService.activeTitleFor(modelData)
    readonly property bool hasFocus: activeTitle !== ""
    readonly property bool hasNotifBadge: NotificationService.hasUnreadBadge
    readonly property bool hasMedia: MediaService.active
    readonly property int currentWs: CompositorService.workspaceIdFor(modelData)

    readonly property int alertMode: {
        if (shellState.previewAlertMode > 0) return shellState.previewAlertMode;
        if (TelemetryService.overheatAlert) return 1;
        if (PowerService.lowBatteryAlert) return 2;
        return 0;
    }
    readonly property bool hasAlert: alertMode > 0

    readonly property bool anyTransientSlot: isSearchOnThisScreen || shellState.osdOpen || shellState.wsSlotOpen || shellState.kdeSlotOpen || shellState.chargeSlotOpen

    property bool hovered: false
    property bool dropHovered: false
    property string clockText: Qt.formatTime(new Date(), "hh:mm")
    property real shownOsdVal: shellState.osdValue

    Behavior on shownOsdVal {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    onIsSearchOnThisScreenChanged: {
        if (isSearchOnThisScreen) {
            searchInput.text = shellState.searchQuery;
            searchFocusTimer.restart();
        } else {
            searchInput.focus = false;
        }
    }

    Timer {
        id: searchFocusTimer
        interval: 60
        repeat: false
        onTriggered: searchInput.forceActiveFocus()
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.clockText = Qt.formatTime(new Date(), "hh:mm")
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    mask: Region {
        item: root.isHidden ? emptyMask : hitbox
    }

    Item {
        id: hitbox
        x: stageContainer.x + Theme.shaderPad - 8
        y: stageContainer.y + Theme.shaderPad - 4
        width: contentRow.width + 16
        height: Theme.islandHeight + 10
    }

    Item {
        id: stageContainer
        anchors.horizontalCenter: parent.horizontalCenter
        y: (root.hovered || root.isPopoverOpenOnThisScreen ? Theme.topOffsetHover : Theme.topOffsetRest) - Theme.shaderPad + (root.isHidden ? -26 : 0)
        width: contentRow.width + Theme.shaderPad * 2
        height: Theme.islandHeight + Theme.shaderPad * 2
        opacity: root.isHidden ? 0.0 : 1.0
        scale: root.isHidden ? 0.65 : 1.0
        transformOrigin: Item.Top

        Behavior on y {
            NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
        }

        // Liquid Gooey Background Layer (1:1 geometry sync with foreground pills)
        Item {
            id: gooSource
            anchors.fill: parent
            layer.enabled: Theme.gooeyEnabled
            layer.effect: ShaderEffect {
                fragmentShader: Qt.resolvedUrl("../assets/shaders/gooey.frag.qsb")
                property size texelSize: Qt.size(1.0 / Math.max(1, gooSource.width), 1.0 / Math.max(1, gooSource.height))
                property real threshold: 0.46
                property real softness: 0.06
                property color pillColor: Theme.pillBg
            }

            Rectangle {
                id: mainBg
                x: Theme.shaderPad + mainPill.x
                y: Theme.shaderPad
                width: mainPill.width
                height: mainPill.height
                radius: Theme.islandRadius
                color: Theme.pillBg
            }

            Rectangle {
                id: mediaBg
                x: Theme.shaderPad + mediaSlotWrap.x + Theme.splitGap
                y: Theme.shaderPad
                width: Math.max(0, mediaSlotWrap.width - Theme.splitGap)
                height: mediaPill.height
                radius: Theme.islandRadius
                color: Theme.pillBg
                opacity: mediaSlotWrap.opacity
                visible: width > 1
            }

            Rectangle {
                id: alertBg
                x: Theme.shaderPad + alertSlotWrap.x + Theme.splitGap
                y: Theme.shaderPad
                width: Math.max(0, alertSlotWrap.width - Theme.splitGap)
                height: alertPill.height
                radius: Theme.islandRadius
                color: Theme.pillBg
                opacity: alertSlotWrap.opacity
                visible: width > 1
            }
        }

        // Crisp Foreground Content Layer
        Row {
            id: contentRow
            x: Theme.shaderPad
            y: Theme.shaderPad
            height: Theme.islandHeight
            spacing: 0

            // Main Status Pill
            Rectangle {
                id: mainPill
                height: Theme.islandHeight
                width: Math.max(260, Math.ceil(pillInner.implicitWidth) + 48)
                radius: Theme.islandRadius
                color: "transparent"
                clip: true
                border.width: root.dropHovered ? 2 : 0
                border.color: Theme.accent

                Behavior on width {
                    NumberAnimation {
                        duration: Theme.smoothMs
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    id: pillInner
                    anchors.centerIn: parent
                    height: Theme.islandHeight
                    spacing: 0

                    // Left Edge: Outdoor Weather Temperature
                    Text {
                        id: weatherLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: WeatherService.tempText
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 23
                        font.weight: Font.DemiBold
                    }

                    // 1. Focused Window Title Slot
                    IslandSlot {
                        id: slotWindow
                        open: root.hasFocus && !root.anyTransientSlot
                        maxSlotWidth: 340

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "  •  "
                            color: Theme.textMuted
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.activeTitle
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.9)
                            font.family: Theme.fontSans
                            font.pixelSize: 20
                            font.weight: Font.Normal
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 270)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "  •  "
                            color: Theme.textMuted
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                        }
                    }

                    // 2. Inline Global Search Slot
                    IslandSlot {
                        id: slotSearch
                        open: root.isSearchOnThisScreen
                        maxSlotWidth: 380

                        Item { width: 12; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "search"
                            iconSize: 15
                            color: Theme.text
                        }

                        Item { width: 8; height: 1 }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 34
                            width: Math.min(320, Math.max(240, 240 + searchInput.text.length * 5))
                            radius: 17
                            color: Qt.rgba(1, 1, 1, searchInput.activeFocus ? 0.16 : 0.10)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, searchInput.activeFocus ? 0.40 : 0.16)
                            clip: true

                            Behavior on width {
                                NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                            }

                            TextInput {
                                id: searchInput
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 15
                                clip: true
                                selectByMouse: true
                                onTextChanged: shellState.searchQuery = text
                                Keys.onEscapePressed: shellState.closePopovers()
                                Keys.onReturnPressed: {
                                    if (text.trim() !== "") {
                                        const apps = AppService.searchApps(text, "All");
                                        if (apps.length > 0) AppService.launchApp(apps[0]);
                                        else AppService.searchWeb(text.trim());
                                        shellState.closePopovers();
                                    }
                                }

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Search files, apps, web..."
                                    color: Theme.textMuted
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    visible: searchInput.text === ""
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Item { width: 12; height: 1 }
                    }

                    // 3. Inline Volume / Brightness OSD Slot
                    IslandSlot {
                        id: slotOsd
                        open: shellState.osdOpen && !root.isSearchOnThisScreen
                        maxSlotWidth: 290

                        Item { width: 16; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: shellState.osdKind === "bri" ? "sun" : "volume"
                            iconSize: 20
                            color: Theme.text
                        }

                        Item { width: 10; height: 1 }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 170
                            height: 8
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.18)
                            clip: true

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                radius: 4
                                color: Theme.text
                                width: Math.max(0, Math.min(parent.width, parent.width * (shellState.osdValue / 100.0)))

                                Behavior on width {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Item { width: 10; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(root.shownOsdVal) + "%"
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }

                        Item { width: 14; height: 1 }
                    }

                    // 4. Inline Workspace Switcher Slot
                    IslandSlot {
                        id: slotWs
                        open: shellState.wsSlotOpen && !root.isSearchOnThisScreen
                        maxSlotWidth: 280

                        Item { width: 14; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Workspace " + root.currentWs
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }

                        Item { width: 8; height: 1 }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Repeater {
                                model: 4
                                delegate: Rectangle {
                                    required property int index
                                    readonly property int wsNum: index + 1
                                    readonly property bool isCurrent: root.currentWs === wsNum
                                    width: isCurrent ? 34 : 26
                                    height: 26
                                    radius: 13
                                    color: isCurrent ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                                    scale: isCurrent ? 1.06 : 1.0

                                    Behavior on width {
                                        NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.25 }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 180 }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: String(wsNum)
                                        color: isCurrent ? Theme.accentFg : Qt.rgba(1, 1, 1, 0.72)
                                        font.family: Theme.fontSans
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }

                        Item { width: 14; height: 1 }
                    }

                    // 5. Inline KDE Connect Drag-Drop Status Slot
                    IslandSlot {
                        id: slotKde
                        open: shellState.kdeSlotOpen && !root.isSearchOnThisScreen
                        maxSlotWidth: 340

                        Item { width: 14; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "smartphone"
                            iconSize: 16
                            color: Theme.ok
                        }

                        Item { width: 8; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: shellState.kdeText
                            color: Theme.ok
                            font.family: Theme.fontSans
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 280)
                        }

                        Item { width: 14; height: 1 }
                    }

                    // 6. Inline Charger Connected Slot
                    IslandSlot {
                        id: slotCharge
                        open: shellState.chargeSlotOpen && !root.isSearchOnThisScreen
                        maxSlotWidth: 260

                        Item { width: 14; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "bolt"
                            iconSize: 16
                            color: shellState.chargeIsCharging ? Theme.ok : Theme.text
                        }

                        Item { width: 8; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: shellState.chargeText
                            color: shellState.chargeIsCharging ? Theme.ok : Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 210)
                        }

                        Item { width: 14; height: 1 }
                    }

                    // 7. Inline Notification Bell Slot
                    IslandSlot {
                        id: slotNotif
                        open: root.hasNotifBadge && !root.anyTransientSlot
                        maxSlotWidth: 64

                        Item {
                            width: 44
                            height: Theme.islandHeight
                            SvgIcon {
                                anchors.centerIn: parent
                                sourceName: "bell"
                                iconSize: 20
                                color: Theme.text
                            }
                            Rectangle {
                                width: 9
                                height: 9
                                radius: 4.5
                                color: Theme.danger
                                border.width: 2
                                border.color: Theme.pillBg
                                anchors.right: parent.right
                                anchors.rightMargin: 9
                                anchors.top: parent.top
                                anchors.topMargin: 15
                            }
                        }
                    }

                    // 8. Normal Mode Spacer
                    Item {
                        id: slotTimeSep
                        height: 1
                        width: (!root.hasFocus && !root.hasNotifBadge && !root.anyTransientSlot) ? 16 : 0
                        Behavior on width {
                            NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                        }
                    }

                    // Right Edge: Clock
                    Text {
                        id: clockLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.clockText
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 23
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    propagateComposedEvents: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hovered = true
                    onExited: root.hovered = false
                    onClicked: function(mouse) {
                        if (root.isSearchOnThisScreen) {
                            const pt = mapToItem(slotSearch, mouse.x, mouse.y);
                            if (pt.x >= 0 && pt.x <= slotSearch.width) {
                                mouse.accepted = false;
                                return;
                            }
                        }
                        if (mouse.button === Qt.RightButton) {
                            shellState.togglePopover("dashboard", root.modelData);
                        } else {
                            shellState.togglePopover("launcher", root.modelData);
                        }
                    }
                }

                DropArea {
                    anchors.fill: parent
                    onEntered: function(drag) {
                        root.dropHovered = true;
                        drag.accepted = true;
                    }
                    onExited: root.dropHovered = false
                    onDropped: function(drop) {
                        root.dropHovered = false;
                        if (drop.hasUrls && drop.urls.length > 0) {
                            KdeConnectService.sendFile(drop.urls[0]);
                        } else if (drop.hasText && drop.text !== "") {
                            KdeConnectService.sendFile(drop.text);
                        }
                    }
                }
            }

            // Liquid Split Pill 1: Media Player
            Item {
                id: mediaSlotWrap
                height: Theme.islandHeight
                clip: true
                width: root.hasMedia ? (Theme.splitGap + mediaPill.width) : 0
                opacity: root.hasMedia ? 1.0 : 0.0
                visible: width > 0.5 || opacity > 0.01

                Behavior on width {
                    NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }

                Item {
                    id: mediaPill
                    x: Theme.splitGap
                    height: Theme.islandHeight
                    width: Math.min(360, Math.max(150, Math.ceil(mediaRow.implicitWidth) + 40))

                    Row {
                        id: mediaRow
                        anchors.centerIn: parent
                        spacing: 12

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "music"
                            iconSize: 16
                            color: Theme.text
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: MediaService.trackTitle + (MediaService.trackArtist !== "" ? " — " + MediaService.trackArtist : "")
                            color: Qt.rgba(1, 1, 1, 0.92)
                            font.family: Theme.fontSans
                            font.pixelSize: 18
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 250)
                        }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: MediaService.isPlaying ? "pause" : "play"
                            iconSize: 14
                            color: Qt.rgba(1, 1, 1, 0.78)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.hovered = true
                        onExited: root.hovered = false
                        onClicked: MediaService.togglePlay()
                    }
                }
            }

            // Liquid Split Pill 2: Hardware / Thermal / Battery Alert
            Item {
                id: alertSlotWrap
                height: Theme.islandHeight
                clip: true
                width: root.hasAlert ? (Theme.splitGap + alertPill.width) : 0
                opacity: root.hasAlert ? 1.0 : 0.0
                visible: width > 0.5 || opacity > 0.01

                Behavior on width {
                    NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }

                Item {
                    id: alertPill
                    x: Theme.splitGap
                    height: Theme.islandHeight
                    width: Math.min(240, Math.max(140, Math.ceil(alertRow.implicitWidth) + 38))

                    readonly property color alertTint: root.alertMode === 1 ? Theme.dangerText : Theme.warn
                    readonly property string alertMsg: root.alertMode === 1
                        ? (TelemetryService.overheatAlert ? TelemetryService.cpuTempC + "℃ Overheat" : "92℃ Overheat")
                        : (PowerService.lowBatteryAlert ? PowerService.batteryPct + "% Low Battery" : "7% Low Battery")

                    Row {
                        id: alertRow
                        anchors.centerIn: parent
                        spacing: 9

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: root.alertMode === 1 ? "thermometer" : "battery-low"
                            iconSize: 18
                            color: alertPill.alertTint
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: alertPill.alertMsg
                            color: alertPill.alertTint
                            font.family: Theme.fontSans
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 165)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.hovered = true
                        onExited: root.hovered = false
                        onClicked: shellState.cycleAlert()
                    }
                }
            }
        }
    }
}
