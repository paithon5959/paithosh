import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../services"

PanelWindow {
    id: root

    required property var shellState

    readonly property bool isBottom: shellState.barPosition === "bottom"
    readonly property bool popoverActive: shellState.openPopover !== ""
    readonly property bool toastActive: !popoverActive && NotificationService.activeToast !== null
    readonly property bool showCard: popoverActive || toastActive
    readonly property string activeMode: popoverActive ? shellState.openPopover : (toastActive ? "toast" : "")
    readonly property bool barHidden: (shellState.manualHideBar
        || (shellState.hideBarFullscreen && CompositorService.isFullscreenFor(screen))
        || (shellState.autoHideOnOverlap && CompositorService.isOverlappedFor(screen, shellState.barPosition)))
        && !(shellState.superPeekBar && shellState.activeScreen === screen)

    screen: shellState.activeScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    visible: showCard || cardBox.opacity > 0.01

    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "paithosh-popover"
    WlrLayershell.keyboardFocus: {
        if (!popoverActive || shellState.openPopover === "search") return WlrKeyboardFocus.None;
        if (shellState.openPopover === "overview") return WlrKeyboardFocus.Exclusive;
        return WlrKeyboardFocus.OnDemand;
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    Item {
        id: fullScreenMask
        anchors.fill: parent
        anchors.topMargin: root.isBottom ? 0 : (Theme.topOffsetHover + Theme.islandHeight)
        anchors.bottomMargin: root.isBottom ? (Theme.topOffsetHover + Theme.islandHeight) : 0
    }

    mask: Region {
        item: root.popoverActive ? fullScreenMask : (root.toastActive ? cardBox : emptyMask)
    }

    Connections {
        target: root.shellState
        function onOpenPopoverChanged() {
            const p = root.shellState.openPopover;
            if (p === "launcher") {
                launcherView.resetAndFocus();
            } else if (p === "clipboard") {
                clipboardView.resetAndFocus();
            } else if (p === "overview") {
                overviewView.resetAndFocus();
            }
            if (p !== "" && p !== "search" && p !== "overview") {
                rootFocusItem.forceActiveFocus();
            }
        }
    }

    Item {
        id: rootFocusItem
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.shellState.closePopovers()
    }

    // Smooth dim backdrop when Workspace Overview is active
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.activeMode === "overview" ? 0.42 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
    }

    // Outside click catcher (only active when popover is open)
    MouseArea {
        anchors.fill: parent
        enabled: root.popoverActive
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.shellState.closePopovers()
    }

    Rectangle {
        id: cardBox
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property real baseMargin: (root.toastActive && root.barHidden)
            ? Theme.topOffsetHover
            : (Theme.topOffsetHover + Theme.islandHeight + 10)
        property real slideOffset: root.showCard ? 0 : (root.isBottom ? 12 : -12)
        Behavior on slideOffset {
            NumberAnimation {
                duration: root.showCard ? Theme.springMs : 200
                easing.type: root.showCard ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: 1.15
            }
        }
        y: (root.isBottom ? (root.height - height - baseMargin) : baseMargin) + slideOffset
        width: {
            if (root.activeMode === "launcher") return launcherView.implicitWidth + 32;
            if (root.activeMode === "clipboard") return clipboardView.implicitWidth + 32;
            if (root.activeMode === "dashboard") return dashboardView.implicitWidth + 32;
            if (root.activeMode === "search") return searchResultsView.implicitWidth + 32;
            if (root.activeMode === "overview") return overviewView.implicitWidth + 32;
            if (root.activeMode === "toast") return toastView.implicitWidth + 40;
            return 420;
        }
        height: {
            if (root.activeMode === "launcher") return launcherView.implicitHeight + 32;
            if (root.activeMode === "clipboard") return clipboardView.implicitHeight + 32;
            if (root.activeMode === "dashboard") return dashboardView.implicitHeight + 32;
            if (root.activeMode === "search") return searchResultsView.implicitHeight + 32;
            if (root.activeMode === "overview") return overviewView.implicitHeight + 32;
            if (root.activeMode === "toast") return toastView.implicitHeight + 32;
            return 200;
        }
        radius: root.activeMode === "toast" ? 22 : 26
        color: Theme.pillBg
        border.width: 1
        border.color: Theme.borderSubtle
        clip: true
        opacity: root.showCard ? 1.0 : 0.0
        scale: root.showCard ? 1.0 : 0.95
        transformOrigin: root.isBottom ? Item.Bottom : Item.Top

        Behavior on width {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: root.showCard ? 220 : 160; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.showCard ? Theme.springMs : 200
                easing.type: root.showCard ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: 1.15
            }
        }

        // Prevent clicks inside card from propagating to outside-click MouseArea
        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) { mouse.accepted = true; }
        }

        LauncherView {
            id: launcherView
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 16
            shellState: root.shellState
            visible: root.activeMode === "launcher"
        }

        ClipboardView {
            id: clipboardView
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 16
            shellState: root.shellState
            visible: root.activeMode === "clipboard"
        }

        DashboardView {
            id: dashboardView
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 16
            shellState: root.shellState
            visible: root.activeMode === "dashboard"
        }

        SearchResultsView {
            id: searchResultsView
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 16
            shellState: root.shellState
            visible: root.activeMode === "search"
        }

        WorkspaceOverview {
            id: overviewView
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 16
            shellState: root.shellState
            visible: root.activeMode === "overview"
        }

        NotificationToast {
            id: toastView
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.topMargin: 16
            visible: root.activeMode === "toast"
        }
    }
}
