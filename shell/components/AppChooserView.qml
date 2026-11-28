import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import ".."
import "../services"
import "common"

FocusScope {
    id: root

    required property var shellState

    property string query: ""
    property var filteredApps: []
    property int selectedIdx: 0
    property bool rememberChoice: false
    property bool submitted: false
    property bool copiedLink: false

    readonly property string uri: shellState.appChooserUri || ""
    readonly property string scheme: shellState.appChooserScheme || ""
    readonly property string contentType: shellState.appChooserContentType || ""
    readonly property string filename: shellState.appChooserFilename || ""
    readonly property string callerApp: shellState.appChooserCallerApp || "Application"
    readonly property bool noMatch: Boolean(shellState.appChooserNoMatch)
    readonly property var selectedApp: (selectedIdx >= 0 && selectedIdx < filteredApps.length) ? filteredApps[selectedIdx] : null

    function initFromState() {
        submitted = false;
        copiedLink = false;
        copiedResetTimer.stop();
        rememberChoice = false;
        query = "";
        searchBox.text = "";
        rebuildFiltered();
        const last = String(shellState.appChooserLastChoice || "").toLowerCase();
        if (last !== "") {
            for (let i = 0; i < filteredApps.length; ++i) {
                if (String(filteredApps[i].id || "").toLowerCase() === last) {
                    selectedIdx = i;
                    break;
                }
            }
        }
        grid.positionViewAtIndex(selectedIdx, GridView.Contain);
        focusTimer.restart();
    }

    function applyUpdatedChoices() {
        const prevId = selectedApp ? String(selectedApp.id || "") : "";
        rebuildFiltered();
        if (prevId !== "") {
            for (let i = 0; i < filteredApps.length; ++i) {
                if (String(filteredApps[i].id || "") === prevId) {
                    selectedIdx = i;
                    break;
                }
            }
        }
    }

    function rebuildFiltered() {
        const all = shellState.appChooserApps || [];
        const q = query.trim().toLowerCase();
        if (q === "") {
            filteredApps = all.slice();
        } else {
            const out = [];
            for (let i = 0; i < all.length; ++i) {
                const a = all[i];
                const hay = (
                    (a.name || "") + " " +
                    (a.genericName || "") + " " +
                    (a.comment || "") + " " +
                    (a.id || "") + " " +
                    (a.category || "") + " " +
                    (a.windowTitle || "")
                ).toLowerCase();
                if (hay.indexOf(q) !== -1) out.push(a);
            }
            filteredApps = out;
        }
        if (filteredApps.length === 0) {
            selectedIdx = 0;
        } else {
            selectedIdx = Math.max(0, Math.min(filteredApps.length - 1, selectedIdx));
        }
    }

    function moveSel(delta) {
        const n = filteredApps.length;
        if (n === 0) return;
        selectedIdx = Math.max(0, Math.min(n - 1, selectedIdx + delta));
        grid.positionViewAtIndex(selectedIdx, GridView.Contain);
    }

    function _normAddr(addr) {
        const s = String(addr || "").trim().toLowerCase();
        if (!s) return "";
        return s.indexOf("0x") === 0 ? s.slice(2) : s;
    }

    function resolveCaptureSource(app) {
        if (!app || !app.running) return null;
        const targetAddr = _normAddr(app.windowAddress);
        const targetCls = String(app.windowClass || "").toLowerCase();
        const targetTitle = String(app.windowTitle || "");
        if (Hyprland.toplevels && Hyprland.toplevels.values) {
            const vals = Hyprland.toplevels.values;
            if (targetAddr !== "") {
                for (let i = 0; i < vals.length; ++i) {
                    const tl = vals[i];
                    if (!tl || !tl.wayland) continue;
                    const ipc = tl.lastIpcObject || {};
                    const a1 = _normAddr(tl.address);
                    const a2 = _normAddr(ipc.address);
                    if (a1 === targetAddr || a2 === targetAddr) return tl.wayland;
                }
            }
            if (targetCls !== "") {
                for (let i = 0; i < vals.length; ++i) {
                    const tl = vals[i];
                    if (!tl || !tl.wayland) continue;
                    const ipc = tl.lastIpcObject || {};
                    const c = String(ipc.class || tl.wayland.appId || "").toLowerCase();
                    if (c === targetCls && (targetTitle === "" || tl.title === targetTitle)) {
                        return tl.wayland;
                    }
                }
            }
        }
        if (ToplevelManager.toplevels && ToplevelManager.toplevels.values) {
            const tvals = ToplevelManager.toplevels.values;
            for (let i = 0; i < tvals.length; ++i) {
                const tl = tvals[i];
                if (!tl) continue;
                const appId = String(tl.appId || "").toLowerCase();
                if (targetCls !== "" && appId === targetCls) return tl;
                if (targetTitle !== "" && tl.title === targetTitle) return tl;
            }
        }
        return null;
    }

    function adaptiveFallbackColor(cat) {
        const a = Theme.accent;
        const t = Theme.text;
        if (a.hslSaturation < 0.08) {
            if (cat === "Dev" || cat === "Games") return Qt.rgba(t.r, t.g, t.b, 0.90);
            if (cat === "Media") return Qt.rgba(t.r, t.g, t.b, 0.82);
            return Theme.textSub;
        }
        const s = Math.min(0.45, Math.max(0.24, a.hslSaturation * 0.88));
        if (cat === "Games") return Qt.hsla((a.hslHue + 0.08) % 1.0, s, 0.75, 1.0);
        if (cat === "Dev") return a;
        if (cat === "Media") return Qt.hsla((a.hslHue + 0.14) % 1.0, s, 0.75, 1.0);
        return Qt.rgba(t.r, t.g, t.b, 0.82);
    }

    function writeResult(payloadObj) {
        const resPath = shellState.appChooserResultPath;
        submitted = true;
        if (!resPath || resPath === "") return;
        shellState.appChooserResultPath = "";
        Quickshell.execDetached([
            "sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"",
            "_", JSON.stringify(payloadObj), resPath
        ]);
    }

    function submitSelection() {
        const app = selectedApp;
        if (!app) return;
        writeResult({
            status: "ok",
            choice: String(app.id || ""),
            remember: Boolean(rememberChoice && contentType !== ""),
            windowAddress: String(app.windowAddress || ""),
            appName: String(app.name || app.id || "")
        });
        if (app.windowAddress && app.windowAddress !== "") {
            CompositorService.focusWindow(app.windowAddress);
            shellState.notifyStatus("Switched to " + (app.name || app.id));
        } else {
            shellState.notifyStatus("Opening " + (app.name || app.id) + "…");
        }
        shellState.collapseIslandApp();
    }

    function cancelSelection() {
        submitted = true;
        shellState.cancelPendingAppChooser();
        shellState.collapseIslandApp();
    }

    Component.onCompleted: initFromState()

    Component.onDestruction: {
        if (!submitted && shellState.appChooserResultPath !== "") {
            shellState.cancelPendingAppChooser();
        }
    }

    onQueryChanged: {
        selectedIdx = 0;
        rebuildFiltered();
    }

    Connections {
        target: root.shellState
        function onAppChooserRequestIdChanged() {
            root.initFromState();
        }
        function onAppChooserAppsChanged() {
            if (root.shellState.islandApp === "appchooser") {
                root.applyUpdatedChoices();
            }
        }
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: searchBox.forceActiveFocus()
    }

    Timer {
        id: copiedResetTimer
        interval: 1400
        repeat: false
        onTriggered: root.copiedLink = false
    }

    Keys.onLeftPressed: (e) => { root.moveSel(-1); e.accepted = true; }
    Keys.onRightPressed: (e) => { root.moveSel(1); e.accepted = true; }
    Keys.onUpPressed: (e) => { root.moveSel(-3); e.accepted = true; }
    Keys.onDownPressed: (e) => { root.moveSel(3); e.accepted = true; }
    Keys.onReturnPressed: (e) => { root.submitSelection(); e.accepted = true; }
    Keys.onEscapePressed: (e) => {
        e.accepted = true;
        if (searchBox.text !== "") searchBox.text = "";
        else root.cancelSelection();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // Header Row (mirrors PortalView.qml Screen Share rhythm)
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.noMatch ? "No Matching App Found" : "Choose Application"
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: {
                        const target = root.uri !== ""
                            ? root.uri
                            : (root.filename !== "" ? root.filename : "Select an installed application");
                        return root.callerApp + " • " + target;
                    }
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }
            }

            PillButton {
                visible: root.uri !== ""
                subtle: true
                iconName: root.copiedLink ? "check" : "copy"
                text: root.copiedLink ? "Copied!" : "Copy Link"
                iconSize: 13
                horizontalPadding: 10
                verticalPadding: 5
                radius: 8
                fontSize: 11
                onClicked: {
                    FileService.copyToClipboard(root.uri);
                    root.copiedLink = true;
                    copiedResetTimer.restart();
                }
            }

            Text {
                text: root.filteredApps.length + (root.filteredApps.length === 1 ? " app" : " apps")
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 11
            }
        }

        // Unmatched Notice Card (Case 2a: no installed app matches URI/type)
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: root.noMatch ? (bannerRow.implicitHeight + 16) : 0
            visible: implicitHeight > 0.5 || opacity > 0.01
            opacity: root.noMatch ? 1.0 : 0.0
            radius: 12
            clip: true
            color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.10)
            border.width: root.noMatch ? 1 : 0
            border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.38)

            Behavior on implicitHeight {
                enabled: !Theme.reduceMotion
                NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            RowLayout {
                id: bannerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                SvgIcon {
                    sourceName: "alert-triangle"
                    iconSize: 16
                    color: Theme.warn
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: "No app on this device matches this request. Pick an app below to handle it."
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: root.scheme !== ""
                    radius: 6
                    clip: true
                    color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.35)
                    implicitWidth: schemeTag.implicitWidth + 14
                    implicitHeight: 22

                    Text {
                        id: schemeTag
                        anchors.centerIn: parent
                        text: root.scheme + "://"
                        color: Theme.warn
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        // Search Bar (concentric r=10, AnimatedTextInput)
        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: 10
            clip: true
            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, searchBox.activeFocus ? 0.11 : 0.07)
            border.width: 1
            border.color: searchBox.activeFocus
                ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.40)
                : (searchHover.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.24) : Theme.borderSubtle)

            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

            MouseArea {
                id: searchHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 8

                SvgIcon {
                    sourceName: "search"
                    iconSize: 15
                    color: Theme.textSub
                }

                AnimatedTextInput {
                    id: searchBox
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    verticalAlignment: TextInput.AlignVCenter
                    textColor: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    clip: true
                    selectByMouse: true
                    onTextChanged: root.query = text

                    Keys.onLeftPressed: (e) => {
                        if (text.length === 0) { root.moveSel(-1); e.accepted = true; }
                        else e.accepted = false;
                    }
                    Keys.onRightPressed: (e) => {
                        if (text.length === 0) { root.moveSel(1); e.accepted = true; }
                        else e.accepted = false;
                    }
                    Keys.onUpPressed: (e) => { root.moveSel(-3); e.accepted = true; }
                    Keys.onDownPressed: (e) => { root.moveSel(3); e.accepted = true; }
                    Keys.onReturnPressed: (e) => { root.submitSelection(); e.accepted = true; }
                    Keys.onEscapePressed: (e) => {
                        e.accepted = true;
                        if (text !== "") text = "";
                        else root.cancelSelection();
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Search installed apps..."
                        color: Theme.textMuted
                        font.family: searchBox.font.family
                        font.pixelSize: searchBox.font.pixelSize
                        visible: searchBox.text === ""
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: clearBtn
                    width: 22
                    height: 22
                    radius: 6
                    clip: true
                    opacity: searchBox.text !== "" ? 1.0 : 0.0
                    visible: opacity > 0.01
                    color: clearMouse.containsMouse ? Theme.cardHover : "transparent"
                    scale: clearMouse.pressed ? 0.92 : (searchBox.text !== "" ? 1.0 : 0.85)

                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                    SvgIcon {
                        anchors.centerIn: parent
                        sourceName: "close"
                        iconSize: 13
                        color: Theme.textSub
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        enabled: searchBox.text !== ""
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchBox.text = "";
                            searchBox.forceActiveFocus();
                        }
                    }
                }
            }
        }

        // 3-Column App Grid (mirrors PortalView.qml Screen Share card layout)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Text {
                anchors.centerIn: parent
                width: Math.max(0, parent.width - 32)
                horizontalAlignment: Text.AlignHCenter
                visible: root.filteredApps.length === 0
                text: root.query.trim() !== ""
                    ? ("No apps match \"" + root.query.trim() + "\"")
                    : "No installed applications available"
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            GridView {
                id: grid
                anchors.fill: parent
                visible: root.filteredApps.length > 0
                clip: true
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                cellWidth: Math.max(180, Math.floor(width / 3))
                cellHeight: 156
                model: root.filteredApps

                delegate: Item {
                    id: cardWrap
                    required property int index
                    required property var modelData
                    readonly property bool sel: root.selectedIdx === index

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        id: appCard
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: 12
                        clip: true
                        color: cardWrap.sel
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                            : (cardMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                        border.width: cardWrap.sel ? 1.5 : 1
                        border.color: cardWrap.sel
                            ? Theme.accent
                            : (cardMouse.containsMouse
                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42)
                                : Theme.borderSubtle)
                        scale: cardMouse.pressed ? 0.96 : 1.0

                        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutBack
                                easing.overshoot: Theme.springOvershoot
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 7

                            Rectangle {
                                id: previewStage
                                Layout.fillWidth: true
                                height: 86
                                radius: 8
                                clip: true
                                color: Theme.surfaceRaised
                                border.width: 1
                                border.color: Theme.borderSubtle

                                readonly property string resolvedIcon: (cardWrap.modelData && cardWrap.modelData.icon)
                                    ? Quickshell.iconPath(cardWrap.modelData.icon, true)
                                    : ""

                                ScreencopyView {
                                    id: previewView
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    captureSource: (cardWrap.modelData && cardWrap.modelData.running && grid.visible)
                                        ? root.resolveCaptureSource(cardWrap.modelData)
                                        : null
                                    live: !Theme.reduceMotion
                                    visible: captureSource !== null && hasContent
                                }

                                // Centered app icon when no live window preview is active
                                Item {
                                    anchors.centerIn: parent
                                    width: 38
                                    height: 38
                                    visible: !previewView.visible

                                    IconImage {
                                        anchors.fill: parent
                                        implicitSize: 38
                                        mipmap: true
                                        source: previewStage.resolvedIcon
                                        visible: previewStage.resolvedIcon !== ""
                                    }

                                    SvgIcon {
                                        anchors.centerIn: parent
                                        sourceName: (cardWrap.modelData && cardWrap.modelData.fallbackSvg) || "external-link"
                                        iconSize: 28
                                        color: root.adaptiveFallbackColor(cardWrap.modelData ? cardWrap.modelData.category : "System")
                                        visible: previewStage.resolvedIcon === ""
                                    }
                                }

                                // Compact corner app badge over live ScreencopyView
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 6
                                    width: 24
                                    height: 24
                                    radius: 6
                                    clip: true
                                    visible: previewView.visible
                                    color: Qt.rgba(Theme.pillBg.r, Theme.pillBg.g, Theme.pillBg.b, 0.86)
                                    border.width: 1
                                    border.color: Theme.borderSubtle

                                    IconImage {
                                        anchors.centerIn: parent
                                        width: 16
                                        height: 16
                                        implicitSize: 16
                                        mipmap: true
                                        source: previewStage.resolvedIcon
                                        visible: previewStage.resolvedIcon !== ""
                                    }

                                    SvgIcon {
                                        anchors.centerIn: parent
                                        sourceName: (cardWrap.modelData && cardWrap.modelData.fallbackSvg) || "external-link"
                                        iconSize: 14
                                        color: Theme.text
                                        visible: previewStage.resolvedIcon === ""
                                    }
                                }

                                // Monochrome top-right badge (Workspace number if running, else Match)
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 6
                                    radius: 6
                                    clip: true
                                    visible: Boolean(cardWrap.modelData && (cardWrap.modelData.running || cardWrap.modelData.recommended))
                                    color: Qt.rgba(Theme.pillBg.r, Theme.pillBg.g, Theme.pillBg.b, 0.86)
                                    border.width: 1
                                    border.color: Theme.borderSubtle
                                    implicitWidth: badgeText.implicitWidth + 12
                                    implicitHeight: 20

                                    Text {
                                        id: badgeText
                                        anchors.centerIn: parent
                                        text: (cardWrap.modelData && cardWrap.modelData.running)
                                            ? ("WS " + (cardWrap.modelData.windowWorkspace > 0 ? cardWrap.modelData.windowWorkspace : 1))
                                            : "Match"
                                        color: Theme.text
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: cardWrap.modelData ? (cardWrap.modelData.name || cardWrap.modelData.id || "") : ""
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: {
                                    const m = cardWrap.modelData;
                                    if (!m) return "";
                                    if (m.running) {
                                        const ws = m.windowWorkspace > 0 ? ("Workspace " + m.windowWorkspace) : "Active";
                                        return "Running • " + ws;
                                    }
                                    if (m.recommended) return "Recommended • " + (m.category || "System");
                                    return m.genericName ? ((m.category || "System") + " • " + m.genericName) : (m.category || "System");
                                }
                                color: Theme.textSub
                                font.family: Theme.fontSans
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedIdx = cardWrap.index;
                            }
                            onDoubleClicked: {
                                root.selectedIdx = cardWrap.index;
                                root.submitSelection();
                            }
                        }
                    }
                }
            }

            // Minimal 4px Scrollbar Indicator
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 1
                width: 4
                radius: 2
                visible: grid.visible && grid.contentHeight > grid.height + 2
                y: Math.max(0, Math.min(parent.height - height, grid.visibleArea.yPosition * grid.height))
                height: Math.max(24, Math.min(parent.height, grid.visibleArea.heightRatio * grid.height))
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.24)
            }
        }

        // Bottom Bar (mirrors PortalView.qml bottom checkbox + Cancel + Primary PillButton)
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                height: 36
                radius: 10
                clip: true
                enabled: root.contentType !== ""
                opacity: enabled ? 1.0 : 0.45
                color: (enabled && rememberMouse.containsMouse) ? Theme.cardHover : Theme.cardBg
                border.width: 1
                border.color: root.rememberChoice
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                    : Theme.borderSubtle
                scale: (enabled && rememberMouse.pressed) ? 0.98 : 1.0

                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 5
                        clip: true
                        color: root.rememberChoice ? Theme.accent : "transparent"
                        border.width: 1.5
                        border.color: root.rememberChoice
                            ? Theme.accent
                            : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.36)

                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: "check"
                            iconSize: 11
                            color: Theme.accentFg
                            opacity: root.rememberChoice ? 1.0 : 0.0
                            scale: root.rememberChoice ? 1.0 : 0.6

                            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.scheme !== ""
                            ? ("Always open " + root.scheme + ":// links with selected app")
                            : (root.contentType !== ""
                                ? ("Always open " + root.contentType + " with selected app")
                                : "Remember default unavailable for this request")
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: rememberMouse
                    anchors.fill: parent
                    enabled: parent.enabled
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.rememberChoice = !root.rememberChoice
                }
            }

            PillButton {
                text: "Cancel"
                horizontalPadding: 18
                verticalPadding: 8
                onClicked: root.cancelSelection()
            }

            PillButton {
                text: (root.selectedApp && root.selectedApp.running) ? "Switch & Open" : "Open App"
                active: true
                enabled: root.selectedApp !== null
                horizontalPadding: 18
                verticalPadding: 8
                onClicked: root.submitSelection()
            }
        }
    }
}
