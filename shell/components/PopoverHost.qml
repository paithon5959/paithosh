import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../services"

PanelWindow {
    id: root

    required property var shellState

    readonly property bool popoverActive: shellState.openPopover !== ""
    readonly property bool toastActive: !popoverActive && NotificationService.activeToast !== null
    readonly property bool showCard: popoverActive || toastActive
    readonly property string activeMode: popoverActive ? shellState.openPopover : (toastActive ? "toast" : "")

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
    WlrLayershell.keyboardFocus: (popoverActive && shellState.openPopover !== "search")
        ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.None

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    Item {
        id: fullScreenMask
        anchors.fill: parent
    }

    mask: Region {
        item: root.popoverActive ? fullScreenMask : (root.toastActive ? cardBox : emptyMask)
    }

    onPopoverActiveChanged: {
        if (popoverActive && shellState.openPopover === "launcher") {
            launcherView.resetAndFocus();
        }
        if (popoverActive && shellState.openPopover !== "search") {
            rootFocusItem.forceActiveFocus();
        }
    }

    Item {
        id: rootFocusItem
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.shellState.closePopovers()
    }

    // Outside click catcher (only active when popover is open)
    MouseArea {
        anchors.fill: parent
        enabled: root.popoverActive
        onClicked: root.shellState.closePopovers()
    }

    Rectangle {
        id: cardBox
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.showCard
            ? (Theme.topOffsetHover + Theme.islandHeight + 10)
            : (Theme.topOffsetHover + Theme.islandHeight - 2)
        width: {
            if (root.activeMode === "launcher") return launcherView.implicitWidth + 32;
            if (root.activeMode === "dashboard") return dashboardView.implicitWidth + 32;
            if (root.activeMode === "search") return searchResultsView.implicitWidth + 32;
            if (root.activeMode === "toast") return toastView.implicitWidth + 40;
            return 420;
        }
        height: {
            if (root.activeMode === "launcher") return launcherView.implicitHeight + 32;
            if (root.activeMode === "dashboard") return dashboardView.implicitHeight + 32;
            if (root.activeMode === "search") return searchResultsView.implicitHeight + 32;
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
        transformOrigin: Item.Top

        Behavior on width {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation {
                duration: root.showCard ? Theme.springMs : 200
                easing.type: root.showCard ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: 1.15
            }
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
