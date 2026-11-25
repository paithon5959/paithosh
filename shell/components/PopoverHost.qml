import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../services"
import "common"

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

    property bool _loadedLauncher: false
    property bool _loadedClipboard: false
    property bool _loadedDashboard: false
    property bool _loadedSearch: false
    property bool _loadedOverview: false

    Connections {
        target: root.shellState
        function onOpenPopoverChanged() {
            const p = root.shellState.openPopover;
            if (p === "launcher") {
                root._loadedLauncher = true;
                Qt.callLater(function() { if (launcherLoader.item) launcherLoader.item.resetAndFocus(); });
            } else if (p === "clipboard") {
                root._loadedClipboard = true;
                Qt.callLater(function() { if (clipboardLoader.item) clipboardLoader.item.resetAndFocus(); });
            } else if (p === "dashboard") {
                root._loadedDashboard = true;
            } else if (p === "search") {
                root._loadedSearch = true;
            } else if (p === "overview") {
                root._loadedOverview = true;
                Qt.callLater(function() { if (overviewLoader.item) overviewLoader.item.resetAndFocus(); });
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
            if (root.activeMode === "launcher") return (launcherLoader.item ? launcherLoader.item.implicitWidth : 520) + 32;
            if (root.activeMode === "clipboard") return (clipboardLoader.item ? clipboardLoader.item.implicitWidth : 440) + 32;
            if (root.activeMode === "dashboard") return (dashboardLoader.item ? dashboardLoader.item.implicitWidth : 420) + 32;
            if (root.activeMode === "search") return (searchResultsLoader.item ? searchResultsLoader.item.implicitWidth : 520) + 32;
            if (root.activeMode === "overview") return (overviewLoader.item ? overviewLoader.item.implicitWidth : 760) + 32;
            if (root.activeMode === "toast") return toastView.implicitWidth + 40;
            return 420;
        }
        height: {
            if (root.activeMode === "launcher") return (launcherLoader.item ? launcherLoader.item.implicitHeight : 420) + 32;
            if (root.activeMode === "clipboard") return (clipboardLoader.item ? clipboardLoader.item.implicitHeight : 420) + 32;
            if (root.activeMode === "dashboard") return (dashboardLoader.item ? dashboardLoader.item.implicitHeight : 460) + 32;
            if (root.activeMode === "search") return (searchResultsLoader.item ? searchResultsLoader.item.implicitHeight : 360) + 32;
            if (root.activeMode === "overview") return (overviewLoader.item ? overviewLoader.item.implicitHeight : 420) + 32;
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
        ThemeGradientFill {
            anchors.fill: parent
            anchors.margins: 1
            enabled: Theme.shellGradientEnabled
            color1: Theme.pillBg
            color2: Theme.pillBg2
            cornerRadius: Math.max(0, cardBox.radius - 1)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) { mouse.accepted = true; }
        }

        Loader {
            id: launcherLoader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 16
            active: root._loadedLauncher || root.activeMode === "launcher"
            visible: root.activeMode === "launcher"
            function ensureSource() {
                if (active && source.toString() === "") setSource("LauncherView.qml", { shellState: root.shellState });
            }
            Component.onCompleted: ensureSource()
            onActiveChanged: ensureSource()
            onLoaded: {
                if (root.activeMode === "launcher" && item) item.resetAndFocus();
            }
        }

        Loader {
            id: clipboardLoader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 16
            active: root._loadedClipboard || root.activeMode === "clipboard"
            visible: root.activeMode === "clipboard"
            function ensureSource() {
                if (active && source.toString() === "") setSource("ClipboardView.qml", { shellState: root.shellState });
            }
            Component.onCompleted: ensureSource()
            onActiveChanged: ensureSource()
            onLoaded: {
                if (root.activeMode === "clipboard" && item) item.resetAndFocus();
            }
        }

        Loader {
            id: dashboardLoader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 16
            active: root._loadedDashboard || root.activeMode === "dashboard"
            visible: root.activeMode === "dashboard"
            function ensureSource() {
                if (active && source.toString() === "") setSource("DashboardView.qml", { shellState: root.shellState });
            }
            Component.onCompleted: ensureSource()
            onActiveChanged: ensureSource()
        }

        Loader {
            id: searchResultsLoader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 16
            active: root._loadedSearch || root.activeMode === "search"
            visible: root.activeMode === "search"
            function ensureSource() {
                if (active && source.toString() === "") setSource("SearchResultsView.qml", { shellState: root.shellState });
            }
            Component.onCompleted: ensureSource()
            onActiveChanged: ensureSource()
        }

        Loader {
            id: overviewLoader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 16
            active: root._loadedOverview || root.activeMode === "overview"
            visible: root.activeMode === "overview"
            function ensureSource() {
                if (active && source.toString() === "") setSource("WorkspaceOverview.qml", { shellState: root.shellState });
            }
            Component.onCompleted: ensureSource()
            onActiveChanged: ensureSource()
            onLoaded: {
                if (root.activeMode === "overview" && item) item.resetAndFocus();
            }
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
