import QtQuick
import Quickshell
import "../services"

FocusScope {
    id: root
    required property var shellState

    property bool isDetached: false
    property string pickerMode: "upload" // "upload" | "download"
    property bool submitted: false
    property bool _initialized: false
    property int _lastInitReqId: -1

    implicitWidth: 880
    implicitHeight: 540

    function initFromState() {
        const reqId = shellState.pickerRequestId || 0;
        if (_lastInitReqId === reqId && _initialized) return;
        _lastInitReqId = reqId;
        _initialized = true;
        submitted = false;
        pickerMode = (shellState.pickerMode === "download") ? "download" : "upload";

        const isRealPortal = Boolean(shellState.pickerResultPath && shellState.pickerResultPath !== "");
        const initialName = pickerMode === "download"
            ? (shellState.pickerInitialName || (isRealPortal ? "" : "untitled.txt"))
            : (shellState.pickerInitialName || "");

        const startDir = shellState.pickerInitialFolder
            ? shellState.pickerInitialFolder
            : (pickerMode === "download" ? (FileService.homeDir + "/Downloads") : (FileService.lastPath || FileService.homeDir));

        if (shellState.pickerFilters && shellState.pickerFilters.length > 0) {
            filesView.filterType = "portal";
            filesView.activePortalFilterIdx = 0;
        } else {
            filesView.filterType = "all";
            filesView.activePortalFilterIdx = -1;
        }
        filesView.resetNavigation(startDir, initialName);
    }

    function setMode(mode) {
        if (shellState) {
            initFromState();
            return;
        }
        pickerMode = mode === "download" ? "download" : "upload";
        if (pickerMode === "download") {
            filesView.resetNavigation(FileService.homeDir + "/Downloads", "untitled.txt");
        } else {
            filesView.resetNavigation(FileService.homeDir, "");
        }
    }

    function writePortalResult(payloadObj) {
        if (!shellState) return;
        const resultPath = shellState.pickerResultPath;
        if (!resultPath || resultPath === "") return;
        submitted = true;
        shellState.pickerResultPath = "";
        const line = JSON.stringify(payloadObj);
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"", "_", line, resultPath]);
    }

    function cancel() {
        writePortalResult({ status: "cancel" });
        if (!shellState) return;
        if (isDetached || shellState.detachedApp === "picker") {
            shellState.closeDetachedApp();
        }
        if (shellState.islandApp === "picker") {
            shellState.collapseIslandApp();
        }
    }

    Connections {
        target: root.shellState
        function onPickerRequestIdChanged() {
            root.initFromState();
        }
    }

    Component.onCompleted: initFromState()

    FilesView {
        id: filesView
        anchors.fill: parent
        focus: true
        shellState: root.shellState
        isPicker: true
        pickerActionMode: root.pickerMode
        pickerMultiple: Boolean(root.shellState.pickerMultiple)
        pickerDirectory: Boolean(root.shellState.pickerDirectory)
        pickerTitle: root.shellState.pickerTitle || "File Chooser"
        pickerSubtitle: root.shellState.pickerAppId
            ? ((root.shellState.pickerResultPath ? "portal • " : "Settings • ") + root.shellState.pickerAppId)
            : (root.shellState.pickerResultPath ? "xdg-desktop-portal" : "Paithosh Shell")
        pickerAcceptLabel: root.shellState.pickerAcceptLabel || ""
        pickerFilters: root.shellState.pickerFilters || []
        pickerBadgeText: root.shellState.pickerDirectory
            ? "Select Folder"
            : (root.pickerMode === "download"
                ? "Download (Save As)"
                : (root.shellState.pickerMultiple ? "Upload (Multiple)" : "Upload (Open File)"))

        onPickerSubmitted: function(paths) {
            root.writePortalResult({ status: "ok", paths: paths });
            if (root.shellState && typeof root.shellState.onPickerSelected === "function" && paths && paths.length > 0) {
                const cb = root.shellState.onPickerSelected;
                root.shellState.onPickerSelected = null;
                cb(paths[0], paths);
            }
            if (root.isDetached || root.shellState.detachedApp === "picker") {
                root.shellState.closeDetachedApp();
            }
            if (root.shellState.islandApp === "picker") {
                root.shellState.collapseIslandApp();
            }
        }

        onPickerCancelled: root.cancel()
    }
}
