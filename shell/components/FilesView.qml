import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."
import "common"
import "../services"

Item {
    id: root
    required property var shellState

    implicitWidth: 880
    implicitHeight: 540

    // Real filesystem state
    property string currentPath: FileService.homeDir
    property string virtualMode: "" // "", "recent", "starred"
    property var currentItems: []
    property var history: [FileService.homeDir]
    property int historyIdx: 0
    property bool isListView: false
    property bool showHidden: false
    property string searchQuery: ""
    property string selectedName: ""
    property var selectedItem: null
    property string statusMessage: ""
    property string diskInfo: ""
    property bool isLoading: false

    // Clipboard for Copy / Cut / Paste
    property var clipboardPaths: []
    property string clipboardMode: "" // "copy" | "cut"

    // Starred paths
    property var starredPaths: []

    // Collapsible sidebar groups
    property bool placesOpen: true
    property bool libraryOpen: false

    // Real transfer progress state
    property bool transferActive: false
    property string transferLabel: ""
    property string transferSub: ""
    property int transferPct: 0
    property string transferDestDir: ""
    property double transferBaselineBytes: 0
    property double transferTotalBytes: 0

    // Inline path editing
    property bool pathEditing: false

    // Archiver & Password modal state
    property bool archiverActive: false
    property string archiverArchivePath: ""
    property string archiverArchiveName: ""
    property var archiverEntries: []
    property string archiverStatus: ""

    property bool passwordOpen: false
    property string passwordTargetPath: ""
    property string passwordTargetName: ""
    property string passwordError: ""

    // Input modal state ("mkdir" | "mkfile" | "rename")
    property bool inputModalOpen: false
    property string inputModalMode: ""
    property string inputModalTitle: ""
    property string inputModalValue: ""
    property string inputModalTargetName: ""

    // Confirm delete modal state
    property bool confirmDeleteOpen: false
    property bool confirmDeletePermanent: false
    property var confirmDeletePaths: []
    property string confirmDeleteLabel: ""

    // Properties modal state
    property bool propsOpen: false
    property string propsName: ""
    property string propsPath: ""
    property var propsData: null

    readonly property var placeItems: [
        { key: "Home", label: "Home", path: FileService.homeDir },
        { key: "Documents", label: "Documents", path: FileService.homeDir + "/Documents" },
        { key: "Dev", label: "Dev", path: FileService.homeDir + "/Dev" },
        { key: "Projects", label: "Projects", path: FileService.homeDir + "/Projects" },
        { key: "Music", label: "Music", path: FileService.homeDir + "/Music" },
        { key: "Pictures", label: "Pictures", path: FileService.homeDir + "/Pictures" },
        { key: "Downloads", label: "Downloads", path: FileService.homeDir + "/Downloads" },
        { key: "Trash", label: "Trash", path: FileService.trashDir }
    ]

    readonly property var libraryItems: [
        { key: "recent", label: "Recent" },
        { key: "starred", label: "Starred" }
    ]

    readonly property var visibleItems: {
        const list = currentItems || [];
        const q = searchQuery.trim().toLowerCase();
        if (q === "") return list;
        const out = [];
        for (let i = 0; i < list.length; ++i) {
            if (list[i].name.toLowerCase().indexOf(q) !== -1) out.push(list[i]);
        }
        return out;
    }

    function displayPath(p) {
        if (!p) return "~";
        if (p === FileService.homeDir) return "~";
        if (p.startsWith(FileService.homeDir + "/")) return "~" + p.slice(FileService.homeDir.length);
        return p;
    }

    function expandUserPath(raw) {
        const s = String(raw || "").trim();
        if (!s || s === "~") return FileService.homeDir;
        if (s.startsWith("~/")) return FileService.homeDir + s.slice(1);
        return s;
    }

    function isStarred(path) {
        return starredPaths.indexOf(path) !== -1;
    }

    function toggleStar(item) {
        if (!item || !item.path) return;
        const next = starredPaths.slice();
        const idx = next.indexOf(item.path);
        if (idx === -1) next.push(item.path);
        else next.splice(idx, 1);
        starredPaths = next;
        if (virtualMode === "starred") loadStarred();
    }

    function refreshCurrent() {
        if (virtualMode === "recent") {
            loadRecent();
            return;
        }
        if (virtualMode === "starred") {
            loadStarred();
            return;
        }
        isLoading = true;
        const target = currentPath;
        FileService.listDir(target, showHidden, (ok, items, err) => {
            isLoading = false;
            if (!ok) {
                currentItems = [];
                statusMessage = err || "Cannot open directory";
                return;
            }
            currentItems = items;
            statusMessage = items.length + " items";
            FileService.getDiskUsage(target, (info) => {
                diskInfo = info;
            });
        });
    }

    function loadRecent() {
        virtualMode = "recent";
        isLoading = true;
        selectedName = "";
        selectedItem = null;
        FileService.listRecent((ok, items) => {
            isLoading = false;
            currentItems = items || [];
            statusMessage = currentItems.length + " recent files";
        });
    }

    function loadStarred() {
        virtualMode = "starred";
        selectedName = "";
        selectedItem = null;
        const out = [];
        for (let i = 0; i < starredPaths.length; ++i) {
            const p = starredPaths[i];
            const name = p.split("/").pop() || p;
            out.push({
                name: name,
                path: p,
                type: FileService.classifyType(name, "f"),
                size: 0,
                meta: displayPath(p)
            });
        }
        currentItems = out;
        statusMessage = out.length + " starred items";
    }

    function navigateTo(rawPath) {
        const target = expandUserPath(rawPath);
        virtualMode = "";
        archiverActive = false;
        selectedName = "";
        selectedItem = null;
        if (history[historyIdx] !== target) {
            const next = history.slice(0, historyIdx + 1);
            next.push(target);
            history = next;
            historyIdx = next.length - 1;
        }
        currentPath = target;
        refreshCurrent();
    }

    function goBack() {
        if (historyIdx > 0) {
            historyIdx--;
            virtualMode = "";
            archiverActive = false;
            currentPath = history[historyIdx];
            refreshCurrent();
        }
    }

    function goForward() {
        if (historyIdx < history.length - 1) {
            historyIdx++;
            virtualMode = "";
            archiverActive = false;
            currentPath = history[historyIdx];
            refreshCurrent();
        }
    }

    function goUp() {
        if (virtualMode !== "") {
            navigateTo(currentPath);
            return;
        }
        if (currentPath === "/" || !currentPath) return;
        const idx = currentPath.lastIndexOf("/");
        const parent = idx <= 0 ? "/" : currentPath.slice(0, idx);
        navigateTo(parent);
    }

    function startTransfer(label, sub, destDir, totalBytes) {
        transferLabel = label;
        transferSub = sub;
        transferDestDir = destDir || "";
        transferTotalBytes = totalBytes > 0 ? totalBytes : 0;
        transferPct = 12;
        transferActive = true;
        if (destDir && totalBytes > 0) {
            FileService.dirSize(destDir, (baseBytes) => {
                transferBaselineBytes = baseBytes;
                transferPollTimer.restart();
            });
        } else {
            transferPollTimer.restart();
        }
    }

    function finishTransfer(finalSub) {
        transferPollTimer.stop();
        transferPct = 100;
        if (finalSub) transferSub = finalSub;
        transferHideTimer.restart();
    }

    Timer {
        id: transferPollTimer
        interval: 250
        repeat: true
        onTriggered: {
            if (root.transferTotalBytes > 0 && root.transferDestDir !== "") {
                FileService.dirSize(root.transferDestDir, (cur) => {
                    const delta = Math.max(0, cur - root.transferBaselineBytes);
                    const pct = Math.min(96, Math.max(15, Math.round((delta / root.transferTotalBytes) * 100)));
                    root.transferPct = pct;
                });
            } else {
                root.transferPct = Math.min(92, root.transferPct + 12);
            }
        }
    }

    Timer {
        id: transferHideTimer
        interval: 1400
        onTriggered: root.transferActive = false
    }

    function openItem(item) {
        if (!item) return;
        if (item.type === "folder") {
            navigateTo(item.path);
        } else if (item.type === "archive") {
            openArchiveInspector(item);
        } else {
            FileService.openFile(item.path);
        }
    }

    function openArchiveInspector(item) {
        archiverArchivePath = item.path;
        archiverArchiveName = item.name;
        archiverStatus = "Reading archive...";
        archiverEntries = [];
        archiverActive = true;
        FileService.inspectArchive(item.path, (ok, entries, err) => {
            if (!ok) {
                archiverStatus = err || "Unable to list archive (may be encrypted)";
                return;
            }
            archiverEntries = entries;
            archiverStatus = entries.length + " entries inside " + item.name;
        });
    }

    function beginExtract(archivePath, archiveName, password) {
        startTransfer("Extracting " + archiveName, "To " + displayPath(currentPath), "", 0);
        FileService.extractArchive(archivePath, currentPath, password || "", (ok, outDir, errText, needsPwd) => {
            if (!ok && needsPwd) {
                transferPollTimer.stop();
                transferActive = false;
                passwordTargetPath = archivePath;
                passwordTargetName = archiveName;
                passwordError = (password && password.length > 0) ? "Incorrect password" : "";
                passwordField.text = "";
                passwordOpen = true;
                passwordField.forceActiveFocus();
                if (password && password.length > 0) pwdShake.restart();
                return;
            }
            if (!ok) {
                finishTransfer("Failed: " + (errText || "extract error"));
                statusMessage = errText || "Extract failed";
                return;
            }
            passwordOpen = false;
            archiverActive = false;
            finishTransfer("Extracted to " + outDir.split("/").pop());
            refreshCurrent();
        });
    }

    function submitPassword() {
        const pwd = passwordField.text;
        if (pwd.length === 0) {
            passwordError = "Password cannot be empty";
            pwdShake.restart();
            return;
        }
        beginExtract(passwordTargetPath, passwordTargetName, pwd);
    }

    function performPaste() {
        if (!clipboardPaths || clipboardPaths.length === 0 || virtualMode !== "") return;
        const paths = clipboardPaths.slice();
        const isCut = clipboardMode === "cut";
        const dest = currentPath;
        FileService.measureSize(paths, (totalBytes) => {
            startTransfer((isCut ? "Moving " : "Copying ") + paths.length + " item(s)", "To " + displayPath(dest), dest, totalBytes);
            const doneCb = (ok, err) => {
                if (!ok) {
                    finishTransfer("Error: " + (err || "operation failed"));
                    statusMessage = err || "Paste failed";
                } else {
                    if (isCut) {
                        clipboardPaths = [];
                        clipboardMode = "";
                    }
                    finishTransfer("Completed in " + displayPath(dest));
                    refreshCurrent();
                }
            };
            if (isCut) FileService.moveItems(paths, dest, doneCb);
            else FileService.copyItems(paths, dest, doneCb);
        });
    }

    function openInputModal(mode, title, initialValue, targetName) {
        inputModalMode = mode;
        inputModalTitle = title;
        inputModalValue = initialValue || "";
        inputModalTargetName = targetName || "";
        inputModalOpen = true;
        modalTextField.text = inputModalValue;
        modalTextField.forceActiveFocus();
        modalTextField.selectAll();
    }

    function submitInputModal() {
        const val = modalTextField.text.trim();
        if (!val) return;
        if (inputModalMode === "mkdir") {
            FileService.createFolder(currentPath, val, (ok, err) => {
                inputModalOpen = false;
                if (!ok) statusMessage = err || "Failed to create folder";
                refreshCurrent();
            });
        } else if (inputModalMode === "mkfile") {
            FileService.createFile(currentPath, val, (ok, err) => {
                inputModalOpen = false;
                if (!ok) statusMessage = err || "Failed to create file";
                refreshCurrent();
            });
        } else if (inputModalMode === "rename") {
            FileService.renameItem(currentPath, inputModalTargetName, val, (ok, err) => {
                inputModalOpen = false;
                if (!ok) statusMessage = err || "Rename failed";
                refreshCurrent();
            });
        }
    }

    function requestDelete(item, permanent) {
        if (!item || !item.path) return;
        confirmDeletePaths = [item.path];
        confirmDeletePermanent = permanent;
        confirmDeleteLabel = (permanent ? "Permanently delete \"" : "Move to Trash \"") + item.name + "\"?";
        confirmDeleteOpen = true;
    }

    function executeDelete() {
        const paths = confirmDeletePaths.slice();
        const permanent = confirmDeletePermanent;
        confirmDeleteOpen = false;
        FileService.deleteItems(paths, permanent, (ok, err) => {
            if (!ok) statusMessage = err || "Delete failed";
            refreshCurrent();
        });
    }

    function compressItem(item) {
        if (!item) return;
        const zipName = item.name + ".zip";
        startTransfer("Compressing " + item.name, "Creating " + zipName, "", 0);
        FileService.createArchive(currentPath, [item.name], zipName, (ok, err) => {
            if (!ok) {
                finishTransfer("Failed: " + (err || "zip error"));
                statusMessage = err || "Compress failed";
            } else {
                finishTransfer("Created " + zipName);
                refreshCurrent();
            }
        });
    }

    function openProperties(item) {
        if (!item || !item.path) return;
        propsName = item.name;
        propsPath = item.path;
        propsData = null;
        propsOpen = true;
        FileService.getProperties(item.path, (ok, data) => {
            if (ok) propsData = data;
        });
    }

    function iconFor(type) {
        return FileService.iconForType(type);
    }

    Component.onCompleted: refreshCurrent()

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar
        Rectangle {
            Layout.preferredWidth: 224
            Layout.fillHeight: true
            color: Theme.pillBg

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

                // App Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        width: 34; height: 34; radius: 10
                        color: Theme.surfaceRaised
                        border.width: 1; border.color: Theme.borderSubtle
                        SvgIcon { anchors.centerIn: parent; sourceName: "folder"; iconSize: 16; color: Theme.text }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { Layout.fillWidth: true; text: "Files"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: "Linux • Coreutils"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
                    }
                }

                // Search input
                Rectangle {
                    Layout.fillWidth: true
                    height: 30; radius: 8
                    color: Theme.cardBg
                    border.width: 1
                    border.color: searchField.activeFocus ? Theme.accent : Theme.borderSubtle
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                        Text { text: "⌕"; color: Theme.textMuted; font.pixelSize: 12 }
                        TextInput {
                            id: searchField
                            Layout.fillWidth: true
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            clip: true
                            onTextChanged: root.searchQuery = text
                            Keys.onReturnPressed: {
                                if (root.virtualMode === "" && text.trim() !== "") {
                                    root.isLoading = true;
                                    FileService.searchFiles(root.currentPath, text.trim(), root.showHidden, (ok, items) => {
                                        root.isLoading = false;
                                        if (ok) {
                                            root.currentItems = items;
                                            root.statusMessage = items.length + " matches";
                                        }
                                    });
                                }
                            }
                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "Find a file (Enter = deep)"
                                color: Theme.textMuted
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                visible: searchField.text === ""
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                // Tree Navigation
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: treeCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: treeCol
                        width: parent.width
                        spacing: 3

                        // Places Tree Group
                        Rectangle {
                            Layout.fillWidth: true; height: 32; radius: 8
                            color: placesHeadMouse.containsMouse ? Theme.cardBg : "transparent"
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
                                SvgIcon { sourceName: "folder"; iconSize: 14; color: Theme.textSub }
                                Text { Layout.fillWidth: true; text: "Places"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13 }
                                Text {
                                    text: "›"; color: Theme.textMuted; font.pixelSize: 14
                                    rotation: root.placesOpen ? 90 : 0
                                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                            }
                            MouseArea {
                                id: placesHeadMouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.placesOpen = !root.placesOpen
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.placesOpen ? placesSubCol.implicitHeight : 0
                            clip: true
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Rectangle {
                                width: 1; x: 16; y: 2; height: Math.max(0, parent.height - 4)
                                color: Theme.borderSubtle
                            }

                            ColumnLayout {
                                id: placesSubCol
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: 22; spacing: 2

                                Repeater {
                                    model: root.placeItems
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool isActive: root.virtualMode === "" && root.currentPath === modelData.path
                                        Layout.fillWidth: true; height: 29; radius: 7
                                        color: isActive ? Theme.cardHover : (pMouse.containsMouse ? Theme.cardBg : "transparent")
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Rectangle {
                                            width: 3; height: 16; radius: 2
                                            anchors.left: parent.left; anchors.leftMargin: 3; anchors.verticalCenter: parent.verticalCenter
                                            color: Theme.accent
                                            opacity: isActive ? 1.0 : 0.0
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left; anchors.right: parent.right
                                            anchors.leftMargin: 12; anchors.rightMargin: 8
                                            text: modelData.label
                                            color: isActive ? Theme.text : Theme.textSub
                                            font.family: Theme.fontSans; font.pixelSize: 12
                                            font.weight: isActive ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }

                                        MouseArea {
                                            id: pMouse
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.navigateTo(modelData.path)
                                        }
                                    }
                                }
                            }
                        }

                        // Library Tree Group
                        Rectangle {
                            Layout.fillWidth: true; height: 32; radius: 8
                            color: libHeadMouse.containsMouse ? Theme.cardBg : "transparent"
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
                                Text { text: "◔"; color: Theme.textSub; font.pixelSize: 13 }
                                Text { Layout.fillWidth: true; text: "Library"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13 }
                                Text {
                                    text: "›"; color: Theme.textMuted; font.pixelSize: 14
                                    rotation: root.libraryOpen ? 90 : 0
                                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                            }
                            MouseArea {
                                id: libHeadMouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.libraryOpen = !root.libraryOpen
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.libraryOpen ? libSubCol.implicitHeight : 0
                            clip: true
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Rectangle {
                                width: 1; x: 16; y: 2; height: Math.max(0, parent.height - 4)
                                color: Theme.borderSubtle
                            }

                            ColumnLayout {
                                id: libSubCol
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: 22; spacing: 2

                                Repeater {
                                    model: root.libraryItems
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool isActive: root.virtualMode === modelData.key
                                        Layout.fillWidth: true; height: 29; radius: 7
                                        color: isActive ? Theme.cardHover : (lMouse.containsMouse ? Theme.cardBg : "transparent")

                                        Rectangle {
                                            width: 3; height: 16; radius: 2
                                            anchors.left: parent.left; anchors.leftMargin: 3; anchors.verticalCenter: parent.verticalCenter
                                            color: Theme.accent
                                            opacity: isActive ? 1.0 : 0.0
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left; anchors.right: parent.right
                                            anchors.leftMargin: 12; anchors.rightMargin: 8
                                            text: modelData.label
                                            color: isActive ? Theme.text : Theme.textSub
                                            font.family: Theme.fontSans; font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }

                                        MouseArea {
                                            id: lMouse
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.key === "recent") root.loadRecent();
                                                else root.loadStarred();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // / (Root)
                        Rectangle {
                            id: rootNavItem
                            readonly property bool isActive: root.virtualMode === "" && root.currentPath === "/"
                            Layout.fillWidth: true; height: 32; radius: 8
                            color: rootNavItem.isActive ? Theme.cardHover : (rootMouse.containsMouse ? Theme.cardBg : "transparent")
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
                                Text { text: "▤"; color: Theme.textSub; font.pixelSize: 13 }
                                Text { Layout.fillWidth: true; text: "/ (Root)"; color: rootNavItem.isActive ? Theme.text : Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 13 }
                            }
                            MouseArea {
                                id: rootMouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.navigateTo("/")
                            }
                        }
                    }
                }

                // Transfer Progress Card
                Rectangle {
                    id: transferBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.transferActive ? 74 : 0
                    opacity: root.transferActive ? 1.0 : 0.0
                    radius: 10
                    color: Theme.surfaceRaised
                    border.width: root.transferActive ? 1 : 0
                    border.color: Theme.borderSubtle
                    clip: true

                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: root.transferLabel; color: Theme.text; font.pixelSize: 11; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            Text { text: root.transferPct >= 100 ? "Done" : (root.transferPct + "%"); color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 10 }
                        }

                        Rectangle {
                            Layout.fillWidth: true; height: 4; radius: 2
                            color: Qt.rgba(1, 1, 1, 0.1)
                            Rectangle {
                                height: parent.height; radius: 2
                                color: Theme.text
                                width: parent.width * (root.transferPct / 100.0)
                                Behavior on width { NumberAnimation { duration: 160 } }
                            }
                        }

                        Text { Layout.fillWidth: true; text: root.transferSub; color: Theme.textSub; font.pixelSize: 10; elide: Text.ElideRight }
                    }
                }
            }
        }

        // Main Content Pane
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Top Bar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    PillButton { text: "‹"; onClicked: root.goBack() }
                    PillButton { text: "›"; onClicked: root.goForward() }
                    PillButton { text: "↑"; onClicked: root.goUp() }
                    PillButton { text: "↻"; onClicked: root.refreshCurrent() }

                    // Inline Path Breadcrumb / Input
                    Rectangle {
                        Layout.fillWidth: true
                        height: 32; radius: 8
                        color: root.pathEditing ? Theme.cardBg : "transparent"
                        border.width: root.pathEditing ? 1 : 0
                        border.color: Theme.accent

                        Text {
                            visible: !root.pathEditing
                            anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                            verticalAlignment: Text.AlignVCenter
                            text: root.virtualMode === "recent" ? "Recent Files" : (root.virtualMode === "starred" ? "Starred Items" : root.displayPath(root.currentPath))
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            elide: Text.ElideMiddle
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.IBeamCursor
                                onClicked: {
                                    pathField.text = root.currentPath;
                                    root.pathEditing = true;
                                    pathField.forceActiveFocus();
                                    pathField.selectAll();
                                }
                            }
                        }

                        TextInput {
                            id: pathField
                            visible: root.pathEditing
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            clip: true
                            Keys.onReturnPressed: {
                                root.pathEditing = false;
                                root.navigateTo(text);
                            }
                            Keys.onEscapePressed: root.pathEditing = false
                            onActiveFocusChanged: { if (!activeFocus) root.pathEditing = false; }
                        }
                    }

                    PillButton {
                        text: "Paste (" + root.clipboardPaths.length + ")"
                        visible: root.clipboardPaths.length > 0 && root.virtualMode === ""
                        active: true
                        onClicked: root.performPaste()
                    }
                    PillButton {
                        text: ".hidden"
                        active: root.showHidden
                        onClicked: {
                            root.showHidden = !root.showHidden;
                            root.refreshCurrent();
                        }
                    }
                    PillButton {
                        text: "+Dir"
                        visible: root.virtualMode === ""
                        onClicked: root.openInputModal("mkdir", "New Folder", "New Folder", "")
                    }
                    PillButton {
                        text: "+File"
                        visible: root.virtualMode === ""
                        onClicked: root.openInputModal("mkfile", "New File", "untitled.txt", "")
                    }
                    PillButton { text: "Grid"; active: !root.isListView; onClicked: root.isListView = false }
                    PillButton { text: "List"; active: root.isListView; onClicked: root.isListView = true }
                }

                // Inline Archiver Bar
                Rectangle {
                    visible: root.archiverActive
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.archiverActive ? 168 : 0
                    radius: 12
                    color: Theme.surfaceRaised
                    border.width: 1
                    border.color: Theme.borderSubtle
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            SvgIcon { sourceName: "archive"; iconSize: 16; color: Theme.text }
                            Text { Layout.fillWidth: true; text: root.archiverArchiveName + " — " + root.archiverStatus; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            PillButton {
                                text: "Extract Here"
                                active: true
                                onClicked: root.beginExtract(root.archiverArchivePath, root.archiverArchiveName, "")
                            }
                            PillButton { text: "✕"; onClicked: root.archiverActive = false }
                        }

                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            clip: true; spacing: 4
                            model: root.archiverEntries
                            delegate: Rectangle {
                                required property var modelData
                                width: ListView.view.width; height: 26; radius: 6
                                color: Theme.cardBg
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                    SvgIcon { sourceName: root.iconFor(modelData.type); iconSize: 13; color: Theme.textSub }
                                    Text { Layout.fillWidth: true; text: modelData.name; color: Theme.text; font.pixelSize: 11; elide: Text.ElideRight }
                                    Text { text: modelData.meta; color: Theme.textMuted; font.pixelSize: 10 }
                                }
                            }
                        }
                    }
                }

                // Grid / List File View
                Flickable {
                    id: filesFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: root.isListView ? listCol.implicitHeight : gridFlow.implicitHeight
                    clip: true

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton | Qt.LeftButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                root.selectedItem = null;
                                ctxMenu.popup();
                            } else {
                                root.selectedName = "";
                                root.selectedItem = null;
                            }
                        }
                    }

                    GridLayout {
                        id: gridFlow
                        visible: !root.isListView
                        width: filesFlick.width
                        columns: Math.max(2, Math.floor((filesFlick.width + 10) / 150))
                        columnSpacing: 10
                        rowSpacing: 10

                        Repeater {
                            model: root.visibleItems
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool isSel: root.selectedName === modelData.name
                                Layout.fillWidth: true
                                height: 106
                                radius: 12
                                color: isSel ? Theme.cardHover : (gMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                border.width: 1
                                border.color: isSel ? Qt.rgba(1, 1, 1, 0.35) : Theme.borderSubtle
                                scale: gMouse.pressed ? 0.97 : 1.0
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 12; spacing: 6
                                    SvgIcon { Layout.alignment: Qt.AlignHCenter; sourceName: root.iconFor(modelData.type); iconSize: 28; color: Theme.text }
                                    Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData.name; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                    Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData.meta; color: Theme.textSub; font.pixelSize: 10; elide: Text.ElideRight }
                                }

                                MouseArea {
                                    id: gMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        root.selectedName = modelData.name;
                                        root.selectedItem = modelData;
                                        if (mouse.button === Qt.RightButton) ctxMenu.popup();
                                    }
                                    onDoubleClicked: root.openItem(modelData)
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: listCol
                        visible: root.isListView
                        width: filesFlick.width
                        spacing: 4

                        Repeater {
                            model: root.visibleItems
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool isSel: root.selectedName === modelData.name
                                Layout.fillWidth: true
                                height: 38; radius: 9
                                color: isSel ? Theme.cardHover : (rowMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                border.width: 1
                                border.color: isSel ? Qt.rgba(1, 1, 1, 0.35) : Theme.borderSubtle

                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                                    SvgIcon { sourceName: root.iconFor(modelData.type); iconSize: 16; color: Theme.text }
                                    Text { Layout.fillWidth: true; text: modelData.name; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                    Text { text: modelData.meta; color: Theme.textSub; font.pixelSize: 11 }
                                }

                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        root.selectedName = modelData.name;
                                        root.selectedItem = modelData;
                                        if (mouse.button === Qt.RightButton) ctxMenu.popup();
                                    }
                                    onDoubleClicked: root.openItem(modelData)
                                }
                            }
                        }
                    }
                }

                // Bottom Status Bar
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: root.isLoading ? "Loading..." : (root.statusMessage || (root.visibleItems.length + " items"))
                        color: Theme.textSub; font.pixelSize: 11; elide: Text.ElideRight
                    }
                    Text { text: root.diskInfo; color: Theme.textSub; font.pixelSize: 11 }
                }
            }

            // Right-Click Context Menu
            Menu {
                id: ctxMenu
                MenuItem {
                    text: "Open"
                    enabled: root.selectedItem !== null
                    onTriggered: root.openItem(root.selectedItem)
                }
                MenuItem {
                    text: "Open in Terminal"
                    onTriggered: {
                        const target = (root.selectedItem && root.selectedItem.type === "folder") ? root.selectedItem.path : root.currentPath;
                        FileService.openTerminal(target);
                    }
                }
                MenuSeparator {}
                MenuItem {
                    text: "Copy"
                    enabled: root.selectedItem !== null
                    onTriggered: {
                        root.clipboardPaths = [root.selectedItem.path];
                        root.clipboardMode = "copy";
                        root.statusMessage = "Copied " + root.selectedItem.name;
                    }
                }
                MenuItem {
                    text: "Cut"
                    enabled: root.selectedItem !== null
                    onTriggered: {
                        root.clipboardPaths = [root.selectedItem.path];
                        root.clipboardMode = "cut";
                        root.statusMessage = "Cut " + root.selectedItem.name;
                    }
                }
                MenuItem {
                    text: "Paste (" + root.clipboardPaths.length + ")"
                    enabled: root.clipboardPaths.length > 0 && root.virtualMode === ""
                    onTriggered: root.performPaste()
                }
                MenuItem {
                    text: "Copy Path"
                    enabled: root.selectedItem !== null
                    onTriggered: {
                        FileService.copyToClipboard(root.selectedItem.path);
                        root.statusMessage = "Path copied to clipboard";
                    }
                }
                MenuSeparator {}
                MenuItem {
                    text: "Rename"
                    enabled: root.selectedItem !== null && root.virtualMode === ""
                    onTriggered: root.openInputModal("rename", "Rename Item", root.selectedItem.name, root.selectedItem.name)
                }
                MenuItem {
                    text: (root.selectedItem && root.isStarred(root.selectedItem.path)) ? "Unstar" : "Star"
                    enabled: root.selectedItem !== null
                    onTriggered: root.toggleStar(root.selectedItem)
                }
                MenuItem {
                    text: "Compress (.zip)"
                    enabled: root.selectedItem !== null && root.virtualMode === ""
                    onTriggered: root.compressItem(root.selectedItem)
                }
                MenuItem {
                    text: "Extract Here"
                    enabled: root.selectedItem !== null && root.selectedItem.type === "archive" && root.virtualMode === ""
                    onTriggered: root.beginExtract(root.selectedItem.path, root.selectedItem.name, "")
                }
                MenuSeparator {}
                MenuItem {
                    text: "Move to Trash"
                    enabled: root.selectedItem !== null
                    onTriggered: root.requestDelete(root.selectedItem, false)
                }
                MenuItem {
                    text: "Delete Permanently"
                    enabled: root.selectedItem !== null
                    onTriggered: root.requestDelete(root.selectedItem, true)
                }
                MenuSeparator {}
                MenuItem {
                    text: "Properties"
                    enabled: root.selectedItem !== null
                    onTriggered: root.openProperties(root.selectedItem)
                }
            }

            // Password Modal for Encrypted Archives
            Rectangle {
                visible: root.passwordOpen
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.58)
                z: 40

                MouseArea { anchors.fill: parent }

                Rectangle {
                    id: pwdBox
                    width: 340; height: 196; radius: 14
                    anchors.centerIn: parent
                    color: Theme.surfaceBg
                    border.width: 1; border.color: Theme.borderSubtle

                    SequentialAnimation {
                        id: pwdShake
                        NumberAnimation { target: pwdBox; property: "anchors.horizontalCenterOffset"; to: -8; duration: 45 }
                        NumberAnimation { target: pwdBox; property: "anchors.horizontalCenterOffset"; to: 8; duration: 45 }
                        NumberAnimation { target: pwdBox; property: "anchors.horizontalCenterOffset"; to: -6; duration: 45 }
                        NumberAnimation { target: pwdBox; property: "anchors.horizontalCenterOffset"; to: 0; duration: 45 }
                    }

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 16; spacing: 10
                        Text { text: "Encrypted Archive"; color: Theme.text; font.pixelSize: 14; font.weight: Font.Bold }
                        Text { Layout.fillWidth: true; text: "Enter password for " + root.passwordTargetName; color: Theme.textSub; font.pixelSize: 11; elide: Text.ElideRight }
                        Rectangle {
                            Layout.fillWidth: true; height: 34; radius: 8
                            color: Theme.cardBg; border.width: 1
                            border.color: passwordField.activeFocus ? Theme.accent : Theme.borderSubtle
                            TextInput {
                                id: passwordField
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                color: Theme.text; font.pixelSize: 12; clip: true
                                Keys.onReturnPressed: root.submitPassword()
                                Keys.onEscapePressed: root.passwordOpen = false
                            }
                        }
                        Text {
                            visible: root.passwordError !== ""
                            text: root.passwordError
                            color: Theme.danger
                            font.pixelSize: 11
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            PillButton { text: "Cancel"; onClicked: root.passwordOpen = false }
                            PillButton { text: "Extract"; active: true; onClicked: root.submitPassword() }
                        }
                    }
                }
            }

            // Input Modal (New Folder / New File / Rename)
            Rectangle {
                visible: root.inputModalOpen
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.58)
                z: 41
                MouseArea { anchors.fill: parent }

                Rectangle {
                    width: 340; height: 168; radius: 14
                    anchors.centerIn: parent
                    color: Theme.surfaceBg
                    border.width: 1; border.color: Theme.borderSubtle

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 16; spacing: 10
                        Text { text: root.inputModalTitle; color: Theme.text; font.pixelSize: 14; font.weight: Font.Bold }
                        Rectangle {
                            Layout.fillWidth: true; height: 34; radius: 8
                            color: Theme.cardBg; border.width: 1
                            border.color: modalTextField.activeFocus ? Theme.accent : Theme.borderSubtle
                            TextInput {
                                id: modalTextField
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.text; font.pixelSize: 12; clip: true
                                Keys.onReturnPressed: root.submitInputModal()
                                Keys.onEscapePressed: root.inputModalOpen = false
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            PillButton { text: "Cancel"; onClicked: root.inputModalOpen = false }
                            PillButton { text: "Confirm"; active: true; onClicked: root.submitInputModal() }
                        }
                    }
                }
            }

            // Confirm Delete Modal
            Rectangle {
                visible: root.confirmDeleteOpen
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.58)
                z: 42
                MouseArea { anchors.fill: parent }

                Rectangle {
                    width: 350; height: 150; radius: 14
                    anchors.centerIn: parent
                    color: Theme.surfaceBg
                    border.width: 1; border.color: Theme.borderSubtle

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 16; spacing: 10
                        Text { text: root.confirmDeletePermanent ? "Permanent Delete" : "Move to Trash"; color: Theme.text; font.pixelSize: 14; font.weight: Font.Bold }
                        Text { Layout.fillWidth: true; text: root.confirmDeleteLabel; color: Theme.textSub; font.pixelSize: 12; wrapMode: Text.WordWrap }
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            PillButton { text: "Cancel"; onClicked: root.confirmDeleteOpen = false }
                            PillButton { text: root.confirmDeletePermanent ? "Delete" : "Trash"; active: true; onClicked: root.executeDelete() }
                        }
                    }
                }
            }

            // Properties Modal
            Rectangle {
                visible: root.propsOpen
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.58)
                z: 43
                MouseArea { anchors.fill: parent }

                Rectangle {
                    width: 360; height: 240; radius: 14
                    anchors.centerIn: parent
                    color: Theme.surfaceBg
                    border.width: 1; border.color: Theme.borderSubtle

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 16; spacing: 8
                        Text { Layout.fillWidth: true; text: "Properties — " + root.propsName; color: Theme.text; font.pixelSize: 14; font.weight: Font.Bold; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: "Path: " + root.propsPath; color: Theme.textSub; font.pixelSize: 11; elide: Text.ElideMiddle }
                        Text { Layout.fillWidth: true; text: "Type: " + (root.propsData ? root.propsData.kind : "..."); color: Theme.textSub; font.pixelSize: 11 }
                        Text { Layout.fillWidth: true; text: "Size: " + (root.propsData ? root.propsData.size : "..."); color: Theme.textSub; font.pixelSize: 11 }
                        Text { Layout.fillWidth: true; text: "Owner: " + (root.propsData ? root.propsData.owner : "..."); color: Theme.textSub; font.pixelSize: 11 }
                        Text { Layout.fillWidth: true; text: "Permissions: " + (root.propsData ? root.propsData.permissions : "..."); color: Theme.textMono || Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 11 }
                        Text { Layout.fillWidth: true; text: "Modified: " + (root.propsData ? root.propsData.modified : "..."); color: Theme.textSub; font.pixelSize: 11 }
                        RowLayout {
                            Layout.fillWidth: true
                            PillButton {
                                visible: root.propsData !== null
                                text: (root.propsData && root.propsData.executable) ? "Remove +x" : "Make Executable (+x)"
                                onClicked: {
                                    const nextExec = !(root.propsData && root.propsData.executable);
                                    FileService.setExecutable(root.propsPath, nextExec, () => {
                                        FileService.getProperties(root.propsPath, (ok, data) => { if (ok) root.propsData = data; });
                                    });
                                }
                            }
                            Item { Layout.fillWidth: true }
                            PillButton { text: "Close"; active: true; onClicked: root.propsOpen = false }
                        }
                    }
                }
            }
        }
    }
}
