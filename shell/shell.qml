import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "services"
import "components"

ShellRoot {
    id: root

    QtObject {
        id: stateObj

        property var activeScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        property string openPopover: "" // "" | "launcher" | "dashboard" | "search"
        property string islandApp: "" // "" | "settings" | "files" | "picker"
        property string dashboardTab: "mission" // "mission" | "tasks" | "kde" | "power"
        property string settingsPage: "home"
        property string pickerMode: "upload"
        property bool manualHideBar: false

        property bool osdOpen: false
        property string osdKind: "vol"
        property int osdValue: 72

        property bool wsSlotOpen: false
        property bool chargeSlotOpen: false
        property bool chargeIsCharging: true
        property string chargeText: "Charging • 84% (65W PD)"

        property bool kdeSlotOpen: false
        property string kdeText: ""

        property string searchQuery: ""
        property int previewAlertMode: 0 // 0=auto/off, 1=overheat, 2=low-battery

        property string modalKind: "" // "" | "confirm" | "multi" | "monitor" | "progress"

        function ensureScreen(scr) {
            if (scr) {
                activeScreen = scr;
            } else if (!activeScreen && Quickshell.screens.length > 0) {
                activeScreen = Quickshell.screens[0];
            }
        }

        function closePopovers() {
            openPopover = "";
            searchQuery = "";
            islandApp = "";
        }

        function togglePopover(kind, scr) {
            ensureScreen(scr);
            islandApp = "";
            if (openPopover === kind && (!scr || activeScreen === scr)) {
                closePopovers();
            } else {
                openPopover = kind;
                if (kind === "search") searchQuery = "";
            }
        }

        function openIslandApp(appKind, scr) {
            ensureScreen(scr);
            openPopover = "";
            searchQuery = "";
            if (islandApp === appKind && (!scr || activeScreen === scr)) {
                islandApp = "";
            } else {
                islandApp = appKind;
            }
        }

        function collapseIslandApp() {
            islandApp = "";
        }

        function showOsd(kind, val) {
            if (openPopover === "search") closePopovers();
            osdKind = kind;
            osdValue = val;
            osdOpen = true;
            osdHideTimer.restart();
        }

        function showWorkspace(id) {
            if (openPopover === "search") closePopovers();
            CompositorService.switchWorkspace(id);
            wsSlotOpen = true;
            wsHideTimer.restart();
        }

        function cycleAlert() {
            previewAlertMode = (previewAlertMode + 1) % 3;
        }

        function openModal(kind) {
            closePopovers();
            modalKind = kind;
        }

        function closeModal() {
            modalKind = "";
        }
    }

    Timer {
        id: osdHideTimer
        interval: 1600
        repeat: false
        onTriggered: stateObj.osdOpen = false
    }

    Timer {
        id: wsHideTimer
        interval: 1400
        repeat: false
        onTriggered: stateObj.wsSlotOpen = false
    }

    Timer {
        id: chargeHideTimer
        interval: 2400
        repeat: false
        onTriggered: stateObj.chargeSlotOpen = false
    }

    Connections {
        target: AudioService
        function onOsdTriggered(kind, value) {
            stateObj.showOsd(kind, value);
        }
    }

    Connections {
        target: BrightnessService
        function onOsdTriggered(kind, value) {
            stateObj.showOsd(kind, value);
        }
    }

    Connections {
        target: PowerService
        function onChargerChanged(charging, pct) {
            stateObj.chargeIsCharging = charging;
            stateObj.chargeText = charging ? ("Charging • " + pct + "% (65W PD)") : ("Unplugged • " + pct + "%");
            stateObj.chargeSlotOpen = true;
            chargeHideTimer.restart();
        }
    }

    Connections {
        target: KdeConnectService
        function onDropStatusChanged(active, message, done) {
            stateObj.kdeSlotOpen = active;
            stateObj.kdeText = message;
        }
    }

    // Hyprland GlobalShortcuts (loaded only when running under Hyprland)
    Loader {
        active: CompositorService.isHyprland
        sourceComponent: Component {
            Scope {
                GlobalShortcut {
                    name: "paithosh-search"
                    description: "Toggle Paithosh Global Search"
                    onPressed: stateObj.togglePopover("search", null)
                }
                GlobalShortcut {
                    name: "paithosh-launcher"
                    description: "Toggle Paithosh App Launcher"
                    onPressed: stateObj.togglePopover("launcher", null)
                }
                GlobalShortcut {
                    name: "paithosh-dashboard"
                    description: "Toggle Paithosh Control Center"
                    onPressed: stateObj.togglePopover("dashboard", null)
                }
            }
        }
    }

    // Multi-Monitor Dynamic Island Instances
    Variants {
        model: Quickshell.screens
        DynamicIsland {
            shellState: stateObj
        }
    }

    // Anchored Popover Host (Launcher / Dashboard / Search Results / Notification Toast)
    PopoverHost {
        shellState: stateObj
    }

    // Reusable Monochrome Modal Overlay (Confirm / Multi / Monitor+Portal / Progress)
    ModalOverlay {
        shellState: stateObj
    }

    // IPC API for Hyprland keybindings & KDE preview verification
    IpcHandler {
        target: "paithosh"

        function toggleLauncher(): void {
            stateObj.togglePopover("launcher", null);
        }

        function toggleDashboard(tab: string): void {
            if (tab !== "") stateObj.dashboardTab = tab;
            stateObj.togglePopover("dashboard", null);
        }

        function toggleSearch(): void {
            stateObj.togglePopover("search", null);
        }

        function openSettings(page: string): void {
            stateObj.settingsPage = page !== "" ? page : "home";
            stateObj.openIslandApp("settings", null);
        }

        function openFiles(): void {
            stateObj.openIslandApp("files", null);
        }

        function openPicker(mode: string): void {
            stateObj.pickerMode = mode === "download" ? "download" : "upload";
            stateObj.openIslandApp("picker", null);
        }

        function toggleHideBar(): void {
            stateObj.manualHideBar = !stateObj.manualHideBar;
            if (stateObj.manualHideBar) stateObj.closePopovers();
        }

        function adjustVolume(delta: int): void {
            AudioService.adjustVolume(delta);
        }

        function adjustBrightness(delta: int): void {
            BrightnessService.adjustBrightness(delta);
        }

        function switchWorkspace(id: int): void {
            stateObj.showWorkspace(id);
        }

        function cycleAlert(): void {
            stateObj.cycleAlert();
        }

        function triggerCharger(): void {
            PowerService.triggerPreviewCharger();
        }

        function triggerKdeDrop(fileName: string): void {
            KdeConnectService.sendFile(fileName);
        }

        function triggerNotif(app: string, title: string, body: string): void {
            NotificationService.pushPreviewNotification(app, title, body);
        }

        function setPreviewFocus(title: string): void {
            CompositorService.previewTitle = title;
        }

        function togglePreviewMedia(): void {
            MediaService.togglePreviewMedia();
        }

        function togglePreviewNotif(): void {
            NotificationService.togglePreviewNotif();
        }

        function applyState(stateName: string): void {
            stateObj.closePopovers();
            stateObj.osdOpen = false;
            stateObj.wsSlotOpen = false;
            stateObj.chargeSlotOpen = false;
            stateObj.kdeSlotOpen = false;

            const hasFocus = stateName.indexOf("focus") !== -1 || stateName === "all";
            const hasMedia = stateName.indexOf("media") !== -1 || stateName === "all";
            const hasNotif = stateName.indexOf("notif") !== -1 || stateName === "all";

            CompositorService.previewTitle = hasFocus ? "kitty — ~/Projects/paithosh" : "";
            MediaService.previewMediaActive = hasMedia;
            NotificationService.previewNotifActive = hasNotif;
        }

        function openModal(kind: string): void {
            stateObj.openModal(kind);
        }

        function closeModal(): void {
            stateObj.closeModal();
        }
    }
}
