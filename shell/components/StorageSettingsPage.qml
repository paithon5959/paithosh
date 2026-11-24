import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../services"
import "common"

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 12

    property var shellState: null
    signal confirmActionRequested(var payload)

    property string hoveredCategory: ""
    property var selectedPaths: ({})
    property int selectedCount: 0
    property double selectedBytes: 0

    onVisibleChanged: {
        if (visible) {
            StorageService.scanIfStale();
        }
    }

    Connections {
        target: StorageService
        function onStaleFilesChanged() {
            root.pruneSelection();
        }
    }

    function segmentColor(key) {
        const a = Theme.accent;
        const t = Theme.text;
        if (a.hslSaturation < 0.08) {
            if (key === "apps") return Qt.rgba(t.r, t.g, t.b, 0.90);
            if (key === "os") return Qt.rgba(t.r, t.g, t.b, 0.62);
            if (key === "cache") return Qt.rgba(t.r, t.g, t.b, 0.38);
            return Qt.rgba(t.r, t.g, t.b, 0.22);
        }
        const s = Math.min(0.45, Math.max(0.24, a.hslSaturation * 0.88));
        if (key === "apps") return a;
        if (key === "os") return Qt.hsla((a.hslHue + 0.09) % 1.0, s, 0.72, 1.0);
        if (key === "cache") return Qt.hsla((a.hslHue + 0.19) % 1.0, s, 0.70, 1.0);
        return Qt.hsla((a.hslHue + 0.30) % 1.0, s, 0.74, 1.0);
    }

    function togglePath(path) {
        const next = Object.assign({}, selectedPaths);
        if (next[path]) delete next[path];
        else next[path] = true;
        selectedPaths = next;
        recomputeSelection();
    }

    function selectAllStale() {
        const files = StorageService.staleFiles || [];
        if (selectedCount === files.length && files.length > 0) {
            selectedPaths = ({});
        } else {
            const next = {};
            for (let i = 0; i < files.length; ++i) {
                next[files[i].path] = true;
            }
            selectedPaths = next;
        }
        recomputeSelection();
    }

    function pruneSelection() {
        const files = StorageService.staleFiles || [];
        const valid = {};
        for (let i = 0; i < files.length; ++i) {
            if (selectedPaths[files[i].path]) valid[files[i].path] = true;
        }
        selectedPaths = valid;
        recomputeSelection();
    }

    function recomputeSelection() {
        const files = StorageService.staleFiles || [];
        let c = 0;
        let b = 0;
        for (let i = 0; i < files.length; ++i) {
            if (selectedPaths[files[i].path]) {
                c++;
                b += Number(files[i].sizeBytes || 0);
            }
        }
        selectedCount = c;
        selectedBytes = b;
    }

    function selectedListWithInfo() {
        const files = StorageService.staleFiles || [];
        const out = [];
        for (let i = 0; i < files.length; ++i) {
            if (selectedPaths[files[i].path]) out.push(files[i]);
        }
        return out;
    }

    // ── Header ──
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: "Storage & File Sight"
                color: Theme.text
                font.family: Theme.fontSans
                font.pixelSize: 16
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: StorageService.activeOpText !== ""
                    ? StorageService.activeOpText
                    : (StorageService.scanning
                        ? "Scanning filesystem & user directories..."
                        : ("Last scan: " + StorageService.lastScanText + " • " + StorageService.mountPoint + " (" + StorageService.fsType + ")"))
                color: StorageService.activeOpText !== "" ? Theme.info : Theme.textSub
                font.family: Theme.fontMono
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        PillButton {
            text: StorageService.scanning ? "Scanning..." : "Rescan"
            iconName: "refresh"
            enabled: !StorageService.scanning && !StorageService.cleaning
            onClicked: StorageService.scan(true)
        }
    }

    // ── Transient status / error banner ──
    Rectangle {
        Layout.fillWidth: true
        visible: StorageService.activeOpText !== "" || StorageService.lastResultText !== "" || StorageService.lastError !== ""
        implicitHeight: bannerRow.implicitHeight + 16
        radius: 10
        clip: true
        color: {
            const isBusy = StorageService.activeOpText !== "";
            const isErr = !isBusy && (StorageService.lastError !== "" || !StorageService.lastResultOk);
            const c = isBusy ? Theme.info : (isErr ? Theme.danger : Theme.ok);
            return Qt.rgba(c.r, c.g, c.b, 0.12);
        }
        border.width: 1
        border.color: {
            const isBusy = StorageService.activeOpText !== "";
            const isErr = !isBusy && (StorageService.lastError !== "" || !StorageService.lastResultOk);
            const c = isBusy ? Theme.info : (isErr ? Theme.danger : Theme.ok);
            return Qt.rgba(c.r, c.g, c.b, 0.40);
        }

        RowLayout {
            id: bannerRow
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            SvgIcon {
                sourceName: StorageService.activeOpText !== ""
                    ? "refresh"
                    : ((StorageService.lastError !== "" || !StorageService.lastResultOk) ? "info" : "check")
                iconSize: 14
                color: StorageService.activeOpText !== ""
                    ? Theme.info
                    : ((StorageService.lastError !== "" || !StorageService.lastResultOk) ? Theme.dangerText : Theme.ok)
            }
            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: StorageService.activeOpText !== ""
                    ? StorageService.activeOpText
                    : (StorageService.lastError !== "" ? StorageService.lastError : StorageService.lastResultText)
                color: Theme.text
                font.family: Theme.fontSans
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
    }

    // ── Card 1: Top Segmented Capacity Bar (Reference-inspired, Paithosh monochrome-adaptive) ──
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: overviewCol.implicitHeight + 28
        radius: 12
        clip: true
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle

        ColumnLayout {
            id: overviewCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    width: 30; height: 30; radius: 8
                    color: Theme.surfaceRaised
                    SvgIcon {
                        anchors.centerIn: parent
                        sourceName: "hard-drive"
                        iconSize: 15
                        color: StorageService.usedPct >= 90 ? Theme.dangerText : (StorageService.usedPct >= 80 ? Theme.warn : Theme.text)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: "System Volume (" + StorageService.mountPoint + ")"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Paithosh Shell: " + StorageService.formatBytes(StorageService.shellBytes) + " • Free: " + StorageService.formatBytes(StorageService.freeBytes)
                        color: Theme.textSub
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Text {
                    text: StorageService.hasScanned
                        ? ("Using " + StorageService.formatBytes(StorageService.usedBytes) + " of " + StorageService.formatBytes(StorageService.totalBytes))
                        : "Scanning..."
                    color: StorageService.usedPct >= 90 ? Theme.dangerText : Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }

            // Segmented horizontal bar
            Rectangle {
                id: segTrack
                Layout.fillWidth: true
                height: 14
                radius: 7
                clip: true
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                Row {
                    anchors.fill: parent
                    spacing: 3

                    Repeater {
                        model: StorageService.categories
                        delegate: Rectangle {
                            readonly property real share: StorageService.totalBytes > 0
                                ? Math.max(0.0, Math.min(1.0, Number(modelData.bytes || 0) / StorageService.totalBytes))
                                : 0.0
                            readonly property bool dimmed: root.hoveredCategory !== "" && root.hoveredCategory !== modelData.key
                            height: parent.height
                            width: share > 0.004 ? Math.max(6, Math.round((segTrack.width - 12) * share)) : 0
                            radius: 4
                            color: root.segmentColor(modelData.key)
                            opacity: dimmed ? 0.35 : 1.0

                            Behavior on width { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: root.hoveredCategory = modelData.key
                                onExited: if (root.hoveredCategory === modelData.key) root.hoveredCategory = ""
                            }
                        }
                    }
                }
            }

            // Legend
            Flow {
                Layout.fillWidth: true
                spacing: 14

                Repeater {
                    model: StorageService.categories
                    delegate: Row {
                        spacing: 6
                        opacity: (root.hoveredCategory !== "" && root.hoveredCategory !== modelData.key) ? 0.45 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                        Rectangle {
                            width: 9; height: 9; radius: 5
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.segmentColor(modelData.key)
                        }
                        Text {
                            text: modelData.label
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        Text {
                            text: "(" + StorageService.formatBytes(modelData.bytes) + ")"
                            color: Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.hoveredCategory = modelData.key
                            onExited: if (root.hoveredCategory === modelData.key) root.hoveredCategory = ""
                        }
                    }
                }

                Row {
                    spacing: 6
                    Rectangle {
                        width: 9; height: 9; radius: 5
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14)
                    }
                    Text {
                        text: "Unused"
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                    }
                    Text {
                        text: "(" + StorageService.formatBytes(StorageService.freeBytes) + ")"
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: StorageService.usedPct >= 85
                    ? ("Low disk space (" + StorageService.usedPct.toFixed(1) + "% used). Use Shredder below to reclaim cache or stale files.")
                    : ("Volume healthy (" + StorageService.usedPct.toFixed(1) + "% used). Categories sum cleanly without double-counting.")
                color: StorageService.usedPct >= 85 ? Theme.warn : Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Card 2: Category Breakdown (2x2) + Top User Folders ──
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: StorageService.categories
            delegate: Rectangle {
                id: catCard
                Layout.fillWidth: true
                implicitHeight: catCol.implicitHeight + 24
                radius: 12
                clip: true
                color: catMouse.containsMouse || root.hoveredCategory === modelData.key ? Theme.cardHover : Theme.cardBg
                border.width: 1
                border.color: root.hoveredCategory === modelData.key
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                    : Theme.borderSubtle
                scale: catMouse.pressed ? 0.98 : 1.0

                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                MouseArea {
                    id: catMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.hoveredCategory = modelData.key
                    onExited: if (root.hoveredCategory === modelData.key) root.hoveredCategory = ""
                }

                ColumnLayout {
                    id: catCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 30; height: 30; radius: 8
                            color: Theme.surfaceRaised
                            SvgIcon {
                                anchors.centerIn: parent
                                sourceName: modelData.iconName || "folder"
                                iconSize: 14
                                color: root.segmentColor(modelData.key)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.detail
                                color: Theme.textSub
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        ColumnLayout {
                            spacing: 1
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: StorageService.formatBytes(modelData.bytes)
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Text {
                                Layout.alignment: Qt.AlignRight
                                text: Number(modelData.pct || 0).toFixed(1) + "%"
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 4
                        radius: 2
                        clip: true
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)

                        Rectangle {
                            height: parent.height
                            radius: 2
                            width: Math.max(4, Math.round(parent.width * Math.min(1.0, Number(modelData.pct || 0) / 100.0)))
                            color: root.segmentColor(modelData.key)
                            Behavior on width { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }
    }

    // ── Top User Folders ──
    Rectangle {
        Layout.fillWidth: true
        visible: (StorageService.userFolders || []).length > 0
        implicitHeight: foldersCol.implicitHeight + 24
        radius: 12
        clip: true
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle

        ColumnLayout {
            id: foldersCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "TOP USER FOLDERS"
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 0.6
            }

            Repeater {
                model: StorageService.userFolders
                delegate: Rectangle {
                    id: folderRow
                    readonly property double maxBytes: (StorageService.userFolders && StorageService.userFolders.length > 0)
                        ? Math.max(1, Number(StorageService.userFolders[0].bytes || 1))
                        : 1
                    Layout.fillWidth: true
                    height: 30
                    radius: 8
                    clip: true
                    color: folderMouse.containsMouse ? Theme.cardHover : "transparent"
                    scale: folderMouse.pressed ? 0.985 : 1.0
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                    MouseArea {
                        id: folderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.shellState) root.shellState.openFilesAt(modelData.path, "");
                            else StorageService.revealInFiles(modelData.path);
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        SvgIcon { sourceName: "folder"; iconSize: 13; color: Theme.textSub }
                        Text {
                            Layout.preferredWidth: 110
                            Layout.minimumWidth: 0
                            text: modelData.name
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 5
                            radius: 3
                            clip: true
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.07)
                            Rectangle {
                                height: parent.height
                                radius: 3
                                width: Math.max(4, Math.round(parent.width * Math.min(1.0, Number(modelData.bytes || 0) / folderRow.maxBytes)))
                                color: root.segmentColor("docs")
                                Behavior on width { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
                            }
                        }
                        Text {
                            text: StorageService.formatBytes(modelData.bytes)
                            color: Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }

    // ── Card 3: Shredder (File Cleanup) ──
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: shredderCol.implicitHeight + 28
        radius: 12
        clip: true
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle

        ColumnLayout {
            id: shredderCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // Shredder Title + Cache Quick Actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    width: 30; height: 30; radius: 8
                    color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.14)
                    SvgIcon {
                        anchors.centerIn: parent
                        sourceName: "trash"
                        iconSize: 15
                        color: Theme.dangerText
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: "Shredder"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Cache cleanup & stale large file detection"
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                PillButton {
                    text: "Clean User Cache (" + StorageService.formatBytes(StorageService.userCacheBytes) + ")"
                    iconName: "trash"
                    enabled: !StorageService.cleaning && StorageService.userCacheBytes > 0
                    onClicked: root.confirmActionRequested({
                        kind: "user-cache",
                        title: "Clean User Cache & Trash?",
                        desc: "This removes safe application caches in ~/.cache (preserving fontconfig, shader, and compositor caches) and empties your Trash.",
                        bytes: StorageService.userCacheBytes,
                        count: 0,
                        paths: [],
                        needsRoot: false,
                        allowPermanentToggle: false
                    })
                }

                PillButton {
                    text: "System Cache (" + StorageService.formatBytes(StorageService.systemCacheBytes) + ")"
                    iconName: "archive"
                    danger: true
                    enabled: !StorageService.cleaning && StorageService.systemCacheBytes > 0
                    onClicked: root.confirmActionRequested({
                        kind: "system-cache",
                        title: "Clean System Cache (Root)?",
                        desc: "Cleans package manager caches (dnf/pacman), vacuums systemd journal logs older than 7 days, and removes stale /var/tmp files. You will be asked for your sudo password.",
                        bytes: StorageService.systemCacheBytes,
                        count: 0,
                        paths: [],
                        needsRoot: true,
                        allowPermanentToggle: false
                    })
                }
            }

            // Divider
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

            // Configurable Age & Size Filter Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Stale >"
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                }

                Repeater {
                    model: [14, 30, 60, 90]
                    delegate: PillButton {
                        text: modelData + "d"
                        fixedHeight: 26
                        horizontalPadding: 9
                        radius: 7
                        fontSize: 11
                        active: StorageService.staleDays === modelData
                        onClicked: {
                            customDaysInput.text = String(modelData);
                            StorageService.setStaleDays(modelData);
                        }
                    }
                }

                // Custom days input (AnimatedTextInput with textColor:)
                Rectangle {
                    width: 68; height: 26; radius: 7; clip: true
                    color: Theme.pillBg
                    border.width: 1
                    border.color: customDaysInput.activeFocus ? Theme.accent : Theme.borderSubtle
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 7
                        anchors.rightMargin: 7
                        spacing: 3
                        AnimatedTextInput {
                            id: customDaysInput
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: String(StorageService.staleDays)
                            textColor: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            validator: IntValidator { bottom: 1; top: 3650 }
                            onAccepted: StorageService.setStaleDays(text)
                            onActiveFocusChanged: if (!activeFocus && text !== String(StorageService.staleDays)) StorageService.setStaleDays(text)
                        }
                        Text {
                            text: "d"
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Min size"
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                }

                Repeater {
                    model: [10, 50, 100, 500]
                    delegate: PillButton {
                        text: modelData + "MB"
                        fixedHeight: 26
                        horizontalPadding: 8
                        radius: 7
                        fontSize: 11
                        active: StorageService.minSizeMb === modelData
                        onClicked: StorageService.setMinSizeMb(modelData)
                    }
                }
            }

            // Selection & Shred Action Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                PillButton {
                    text: (root.selectedCount === (StorageService.staleFiles || []).length && root.selectedCount > 0) ? "Deselect All" : "Select All"
                    fixedHeight: 28
                    subtle: true
                    enabled: (StorageService.staleFiles || []).length > 0
                    onClicked: root.selectAllStale()
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: (StorageService.staleFiles || []).length + " stale files (" + StorageService.formatBytes(StorageService.staleTotalBytes) + ")"
                        + (root.selectedCount > 0 ? (" • " + root.selectedCount + " selected (" + StorageService.formatBytes(root.selectedBytes) + ")") : "")
                    color: Theme.textSub
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                PillButton {
                    text: root.selectedCount > 0
                        ? ("Shred " + root.selectedCount + " (" + StorageService.formatBytes(root.selectedBytes) + ")")
                        : "Shred Selected"
                    iconName: "trash"
                    danger: true
                    active: root.selectedCount > 0
                    enabled: root.selectedCount > 0 && !StorageService.cleaning
                    onClicked: {
                        const items = root.selectedListWithInfo();
                        const paths = items.map(it => it.path);
                        const preview = items.slice(0, 5).map(it => it.relPath + " (" + StorageService.formatBytes(it.sizeBytes) + ")");
                        root.confirmActionRequested({
                            kind: "shred-files",
                            title: "Clean " + items.length + (items.length === 1 ? " Stale File?" : " Stale Files?"),
                            desc: "Selected files haven't been modified or accessed in over " + StorageService.staleDays + " days. By default they are moved safely to Trash.",
                            bytes: root.selectedBytes,
                            count: items.length,
                            paths: paths,
                            preview: preview,
                            needsRoot: false,
                            allowPermanentToggle: true
                        });
                    }
                }
            }

            // Stale Large Files List
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: (StorageService.staleFiles || []).length === 0 ? 74 : Math.min(260, (StorageService.staleFiles || []).length * 46 + 8)
                radius: 10
                clip: true
                color: Theme.surfaceBg
                border.width: 1
                border.color: Theme.borderSubtle

                Text {
                    anchors.centerIn: parent
                    visible: (StorageService.staleFiles || []).length === 0
                    text: StorageService.scanning
                        ? "Scanning user files..."
                        : ("No files >= " + StorageService.minSizeMb + " MB older than " + StorageService.staleDays + " days found.")
                    color: Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                }

                ListView {
                    id: staleList
                    anchors.fill: parent
                    anchors.margins: 4
                    visible: (StorageService.staleFiles || []).length > 0
                    model: StorageService.staleFiles
                    spacing: 4
                    clip: true
                    reuseItems: true
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: fileRow
                        readonly property bool isSelected: !!root.selectedPaths[modelData.path]
                        width: staleList.width
                        height: 42
                        radius: 8
                        clip: true
                        color: isSelected
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                            : (rowMouse.containsMouse ? Theme.cardHover : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.035))
                        border.width: 1
                        border.color: isSelected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : "transparent"
                        scale: rowMouse.pressed ? 0.985 : 1.0

                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.togglePath(modelData.path)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 8

                            // Checkbox
                            Rectangle {
                                width: 16; height: 16; radius: 4
                                color: fileRow.isSelected ? Theme.accent : "transparent"
                                border.width: 1.5
                                border.color: fileRow.isSelected ? Theme.accent : Theme.textMuted
                                Behavior on color { ColorAnimation { duration: 130 } }
                                SvgIcon {
                                    anchors.centerIn: parent
                                    visible: fileRow.isSelected
                                    sourceName: "check"
                                    iconSize: 11
                                    color: Theme.accentFg
                                }
                            }

                            SvgIcon {
                                sourceName: "document"
                                iconSize: 14
                                color: Theme.textSub
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: Theme.text
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.relPath
                                    color: Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    elide: Text.ElideMiddle
                                }
                            }

                            Rectangle {
                                implicitWidth: ageTxt.implicitWidth + 10
                                height: 20
                                radius: 5
                                color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.14)
                                Text {
                                    id: ageTxt
                                    anchors.centerIn: parent
                                    text: modelData.ageDays + "d"
                                    color: Theme.warn
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                text: StorageService.formatBytes(modelData.sizeBytes)
                                color: Theme.text
                                font.family: Theme.fontMono
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            PillButton {
                                iconName: "external-link"
                                iconSize: 12
                                fixedWidth: 26
                                fixedHeight: 26
                                radius: 6
                                subtle: true
                                onClicked: {
                                    if (root.shellState) root.shellState.openFilesAt(modelData.parentDir, modelData.path);
                                    else StorageService.revealInFiles(modelData.parentDir);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
