import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import ".."
import "../services"
import "common"

FocusScope {
    id: root
    anchors.fill: parent
    z: 210
    visible: open || backdrop.opacity > 0.01
    focus: open

    property var selectMenu: null
    property var menuRoot: null

    property bool open: false
    property string editingBindId: ""
    property int editingComboIdx: -1
    property string editorTab: "island"

    property string selectedTitle: ""
    property string selectedSubtitle: ""
    property string selectedActionLua: ""
    property string selectedCommand: ""
    property string selectedAppId: ""
    property bool rawLuaFallback: false

    property string customCmdInput: ""
    property string appSearchQuery: ""
    property var desktopApps: []

    property var workingCombos: []
    property int activeComboIdx: 0
    property bool listeningKey: false
    property bool _modsManuallyEdited: false
    property bool modSuper: true
    property bool modCtrl: false
    property bool modAlt: false
    property bool modShift: false
    property string recordedKey: ""

    property bool confirmDelete: false
    property string validationError: ""

    readonly property var filteredAppChoices: {
        const q = root.appSearchQuery.trim().toLowerCase();
        const out = [];
        const defs = KeybindService.defaultAppActions || [];
        for (let i = 0; i < defs.length; ++i) {
            const d = defs[i];
            if (q === "" || (d.label + " " + d.desc).toLowerCase().indexOf(q) !== -1) {
                out.push({
                    isDefault: true,
                    id: d.id,
                    label: d.label,
                    sub: d.desc,
                    lua: d.lua
                });
            }
        }
        const apps = root.desktopApps || [];
        for (let j = 0; j < apps.length; ++j) {
            const a = apps[j];
            if (q === "" || (a.name + " " + a.id + " " + a.genericName).toLowerCase().indexOf(q) !== -1) {
                out.push({
                    isDefault: false,
                    id: a.id,
                    label: a.name,
                    sub: a.id,
                    lua: ""
                });
            }
        }
        return out;
    }

    readonly property var activeSlot: (root.activeComboIdx >= 0 && root.activeComboIdx < root.workingCombos.length)
        ? root.workingCombos[root.activeComboIdx]
        : ({ combo: "", opts: "", release: false, locked: false, repeating: false })

    readonly property var activeConflicts: {
        const out = [];
        const seen = {};
        const list = root.workingCombos || [];
        for (let i = 0; i < list.length; ++i) {
            const c = list[i];
            if (!c || !c.combo) continue;
            const parts = KeybindService.splitComboParts(c.combo);
            const hasMain = parts.some(p => !KeybindService.isModPart(p));
            if (!hasMain) continue;
            const norm = KeybindService.normalizeComboKey(c.combo) + "|" + (c.release ? "1" : "0");
            if (seen[norm]) {
                out.push("Duplicate shortcut in this action: " + c.combo);
                continue;
            }
            seen[norm] = true;
            const hit = KeybindService.findConflict(
                c.combo,
                root.editingBindId,
                -1,
                Boolean(c.release)
            );
            if (hit) {
                out.push("Already bound to \"" + hit.title + "\"");
            }
        }
        return out;
    }

    Component.onCompleted: refreshDesktopApps()

    Connections {
        target: root.selectMenu
        function onClosed() {
            if (root.open) {
                root.forceActiveFocus();
            }
        }
    }

    Timer {
        id: deleteResetTimer
        interval: 4000
        onTriggered: root.confirmDelete = false
    }

    function refreshDesktopApps() {
        const entries = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        const list = [];
        if (entries) {
            for (let i = 0; i < entries.length; ++i) {
                const e = entries[i];
                if (!e || e.noDisplay || !e.name || !e.id) continue;
                list.push({
                    id: e.id,
                    name: e.name,
                    genericName: e.genericName || ""
                });
            }
        }
        list.sort((a, b) => a.name.localeCompare(b.name));
        root.desktopApps = list;
    }

    function openNew(defaultTab) {
        refreshDesktopApps();
        root.editingBindId = "";
        root.editingComboIdx = -1;
        root.editorTab = (defaultTab && defaultTab !== "all") ? defaultTab : "island";
        root.rawLuaFallback = false;
        root.customCmdInput = "";
        cmdInput.text = "";
        root.appSearchQuery = "";
        appSearchInput.text = "";
        root.selectedAppId = "";
        root.workingCombos = [{ combo: "", opts: "", release: false, locked: false, repeating: false }];
        root.activeComboIdx = 0;
        root._modsManuallyEdited = false;
        root.modSuper = true;
        root.modCtrl = false;
        root.modAlt = false;
        root.modShift = false;
        root.recordedKey = "";
        root.confirmDelete = false;
        root.validationError = "";
        applyDefaultActionForTab(root.editorTab);
        root.open = true;
        root.listeningKey = true;
        root.forceActiveFocus();
    }

    function openEdit(bindObj, comboIndex) {
        refreshDesktopApps();
        root.editingBindId = bindObj.id;
        const rawCombos = (bindObj.combos || []).map(c => ({
            combo: c.combo || "",
            opts: c.opts || "",
            release: Boolean(c.release),
            locked: Boolean(c.locked),
            repeating: Boolean(c.repeating)
        }));
        if (rawCombos.length === 0) {
            rawCombos.push({ combo: "", opts: "", release: false, locked: false, repeating: false });
        }
        root.workingCombos = rawCombos;
        root.editingComboIdx = (typeof comboIndex === "number" && comboIndex >= 0 && comboIndex < rawCombos.length) ? comboIndex : -1;
        root.activeComboIdx = root.editingComboIdx >= 0 ? root.editingComboIdx : 0;

        root.editorTab = bindObj.category || "command";
        root.selectedTitle = bindObj.title || "";
        root.selectedSubtitle = bindObj.subtitle || "";
        root.selectedActionLua = bindObj.actionLua || "";
        root.selectedCommand = bindObj.command || "";
        root.selectedAppId = bindObj.appId || "";
        root.rawLuaFallback = (root.editorTab === "command" && root.selectedCommand === "" && root.selectedActionLua !== "");
        root.customCmdInput = root.selectedCommand;
        cmdInput.text = root.customCmdInput;
        root.appSearchQuery = "";
        appSearchInput.text = "";
        root.confirmDelete = false;
        root.validationError = "";
        root._modsManuallyEdited = false;

        loadSlotIntoControls(root.activeComboIdx);
        root.open = true;
        root.listeningKey = (root.editingComboIdx >= 0);
        root.forceActiveFocus();
    }

    function close() {
        if (root.selectMenu && root.selectMenu.isOpen) root.selectMenu.close();
        root.listeningKey = false;
        root.confirmDelete = false;
        deleteResetTimer.stop();
        root.open = false;
    }

    function applyDefaultActionForTab(tab) {
        root.rawLuaFallback = false;
        if (tab === "island" && KeybindService.islandActions.length > 0) {
            const a = KeybindService.islandActions[0];
            selectPresetAction("island", a.label, "", a.lua, "", a.opts || "");
        } else if (tab === "screenshot" && KeybindService.screenshotActions.length > 0) {
            const a = KeybindService.screenshotActions[0];
            selectPresetAction("screenshot", a.label, a.desc, a.lua, "", a.opts || "");
        } else if (tab === "window" && KeybindService.windowActions.length > 0) {
            const a = KeybindService.windowActions[0];
            selectPresetAction("window", a.label, a.desc, a.lua, "", "");
        } else if (tab === "apps") {
            const defs = KeybindService.defaultAppActions || [];
            if (defs.length > 0) {
                selectAppChoice({ isDefault: true, id: defs[0].id, label: defs[0].label, sub: defs[0].desc, lua: defs[0].lua });
            } else if (root.desktopApps.length > 0) {
                const app = root.desktopApps[0];
                selectAppChoice({ isDefault: false, id: app.id, label: app.name, sub: app.id, lua: "" });
            }
        } else {
            root.selectedActionLua = "";
            root.selectedCommand = "";
            root.selectedTitle = "";
            root.selectedSubtitle = "";
            root.selectedAppId = "";
        }
    }

    function selectPresetAction(cat, label, desc, luaExpr, cmd, defaultOpts) {
        root.selectedTitle = label;
        root.selectedSubtitle = desc || "";
        root.selectedActionLua = luaExpr;
        root.selectedCommand = cmd || "";
        root.selectedAppId = "";
        root.validationError = "";
        if (root.editingBindId === "" && defaultOpts !== undefined && root.workingCombos.length > 0) {
            const copy = root.workingCombos.slice();
            const cur = Object.assign({}, copy[root.activeComboIdx]);
            cur.opts = defaultOpts;
            cur.locked = defaultOpts.indexOf("locked = true") !== -1;
            cur.repeating = defaultOpts.indexOf("repeating = true") !== -1;
            cur.release = defaultOpts.indexOf("release = true") !== -1;
            copy[root.activeComboIdx] = cur;
            root.workingCombos = copy;
        }
    }

    function selectAppChoice(choice) {
        if (!choice) return;
        root.validationError = "";
        if (choice.isDefault) {
            root.selectedAppId = "";
            root.selectedTitle = choice.label.replace(/^Default /, "");
            root.selectedSubtitle = choice.sub;
            root.selectedCommand = "";
            root.selectedActionLua = choice.lua;
        } else {
            const built = KeybindService.buildGtkLaunchLua(choice.id);
            root.selectedAppId = choice.id;
            root.selectedTitle = "Launch " + choice.label;
            root.selectedSubtitle = choice.id;
            root.selectedCommand = built.cmd;
            root.selectedActionLua = built.lua;
        }
    }

    function loadSlotIntoControls(idx) {
        const list = root.workingCombos || [];
        if (idx < 0 || idx >= list.length) return;
        const comboStr = list[idx].combo || "";
        const parts = KeybindService.splitComboParts(comboStr);
        const upper = parts.map(p => p.toUpperCase());
        root.modSuper = upper.indexOf("SUPER") !== -1;
        root.modCtrl = upper.indexOf("CTRL") !== -1 || upper.indexOf("CONTROL") !== -1;
        root.modAlt = upper.indexOf("ALT") !== -1;
        root.modShift = upper.indexOf("SHIFT") !== -1;
        let mainKey = "";
        for (let i = 0; i < parts.length; ++i) {
            if (!KeybindService.isModPart(parts[i])) {
                mainKey = parts[i];
            }
        }
        root.recordedKey = mainKey;
    }

    function currentDraftCombo() {
        const parts = [];
        if (root.modSuper) parts.push("SUPER");
        if (root.modCtrl) parts.push("CTRL");
        if (root.modAlt) parts.push("ALT");
        if (root.modShift) parts.push("SHIFT");
        if (root.recordedKey !== "") parts.push(root.recordedKey);
        return parts.join(" + ");
    }

    function syncControlsToActiveSlot() {
        const copy = root.workingCombos.slice();
        if (root.activeComboIdx < 0 || root.activeComboIdx >= copy.length) return;
        const item = Object.assign({}, copy[root.activeComboIdx]);
        item.combo = root.recordedKey !== "" ? root.currentDraftCombo() : "";
        copy[root.activeComboIdx] = item;
        root.workingCombos = copy;
        root.validationError = "";
    }

    function addAlternateSlot() {
        const copy = root.workingCombos.slice();
        copy.push({ combo: "", opts: "", release: false, locked: false, repeating: false });
        root.workingCombos = copy;
        root.activeComboIdx = copy.length - 1;
        root._modsManuallyEdited = false;
        root.modSuper = true;
        root.modCtrl = false;
        root.modAlt = false;
        root.modShift = false;
        root.recordedKey = "";
        root.listeningKey = true;
        root.forceActiveFocus();
    }

    function removeSlotAt(idx) {
        if (root.workingCombos.length <= 1) return;
        const copy = root.workingCombos.slice();
        copy.splice(idx, 1);
        root.workingCombos = copy;
        root.activeComboIdx = Math.max(0, Math.min(root.activeComboIdx, copy.length - 1));
        loadSlotIntoControls(root.activeComboIdx);
    }

    function toggleSlotOption(flagName) {
        const copy = root.workingCombos.slice();
        if (root.activeComboIdx < 0 || root.activeComboIdx >= copy.length) return;
        const item = Object.assign({}, copy[root.activeComboIdx]);
        if (flagName === "locked") item.locked = !item.locked;
        else if (flagName === "repeating") item.repeating = !item.repeating;
        item.opts = KeybindService.buildOptsLua(item.opts, item.locked, item.repeating);
        copy[root.activeComboIdx] = item;
        root.workingCombos = copy;
    }

    function triggerShake() {
        shakeAnim.restart();
    }

    function openMenuFor(anchorItem, menuItems, minWidth) {
        if (!root.selectMenu || !root.menuRoot) return;
        root.listeningKey = false;
        const pt = anchorItem.mapToItem(root.menuRoot, 0, anchorItem.height + 4);
        root.selectMenu.menuWidth = Math.max(minWidth || 200, anchorItem.width);
        root.selectMenu.openAt(pt.x, pt.y, menuItems);
    }

    function commitEditor() {
        if (root.editorTab === "command") {
            const c = root.customCmdInput.trim();
            if (c !== "") {
                root.selectedCommand = c;
                root.selectedTitle = c;
                root.selectedSubtitle = "";
                root.selectedActionLua = KeybindService.buildExecCmdLua(c);
            } else if (!root.rawLuaFallback || root.selectedActionLua === "") {
                root.validationError = "Enter a shell command to run";
                triggerShake();
                return;
            }
        }
        if (root.selectedActionLua === "") {
            root.validationError = "Select an action first";
            triggerShake();
            return;
        }

        const cleanCombos = [];
        const seen = {};
        for (let i = 0; i < root.workingCombos.length; ++i) {
            const c = root.workingCombos[i];
            if (!c || !c.combo) continue;
            const parts = KeybindService.splitComboParts(c.combo);
            const hasMain = parts.some(p => !KeybindService.isModPart(p));
            if (!hasMain) continue;
            const norm = KeybindService.normalizeComboKey(c.combo) + "|" + (c.release ? "1" : "0");
            if (seen[norm]) continue;
            seen[norm] = true;
            cleanCombos.push(c);
        }

        if (cleanCombos.length === 0) {
            root.validationError = "Press a key combination to bind";
            root.listeningKey = true;
            root.forceActiveFocus();
            triggerShake();
            return;
        }

        if (root.editingBindId !== "") {
            KeybindService.updateBind(
                root.editingBindId,
                root.editorTab,
                root.selectedTitle,
                root.selectedSubtitle,
                root.selectedActionLua,
                root.selectedCommand,
                root.selectedAppId,
                cleanCombos
            );
        } else {
            KeybindService.addOrMergeBind(
                root.editorTab,
                root.selectedTitle,
                root.selectedSubtitle,
                root.selectedActionLua,
                root.selectedCommand,
                root.selectedAppId,
                cleanCombos
            );
        }
        root.close();
    }

    function mapQtKeyToHypr(event) {
        const k = event.key;
        if (k === Qt.Key_Super_L || k === Qt.Key_Super_R || k === Qt.Key_Meta ||
            k === Qt.Key_Control || k === Qt.Key_Alt || k === Qt.Key_Shift || k === Qt.Key_AltGr) {
            return "";
        }
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(65 + (k - Qt.Key_A));
        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(48 + (k - Qt.Key_0));
        if (k >= Qt.Key_F1 && k <= Qt.Key_F24) return "F" + (k - Qt.Key_F1 + 1);
        switch (k) {
            case Qt.Key_Space: return "space";
            case Qt.Key_Return:
            case Qt.Key_Enter: return "Return";
            case Qt.Key_Escape: return "Escape";
            case Qt.Key_Tab:
            case Qt.Key_Backtab: return "Tab";
            case Qt.Key_Backspace: return "BackSpace";
            case Qt.Key_Delete: return "Delete";
            case Qt.Key_Insert: return "Insert";
            case Qt.Key_Left: return "left";
            case Qt.Key_Right: return "right";
            case Qt.Key_Up: return "up";
            case Qt.Key_Down: return "down";
            case Qt.Key_Print: return "Print";
            case Qt.Key_Home: return "Home";
            case Qt.Key_End: return "End";
            case Qt.Key_PageUp: return "Prior";
            case Qt.Key_PageDown: return "Next";
            case Qt.Key_QuoteLeft:
            case Qt.Key_AsciiTilde: return "grave";
            case Qt.Key_Exclam: return "1";
            case Qt.Key_At: return "2";
            case Qt.Key_NumberSign: return "3";
            case Qt.Key_Dollar: return "4";
            case Qt.Key_Percent: return "5";
            case Qt.Key_AsciiCircum: return "6";
            case Qt.Key_Ampersand: return "7";
            case Qt.Key_Asterisk: return "8";
            case Qt.Key_ParenLeft: return "9";
            case Qt.Key_ParenRight: return "0";
            case Qt.Key_Minus:
            case Qt.Key_Underscore: return "minus";
            case Qt.Key_Equal:
            case Qt.Key_Plus: return "equal";
            case Qt.Key_BracketLeft:
            case Qt.Key_BraceLeft: return "bracketleft";
            case Qt.Key_BracketRight:
            case Qt.Key_BraceRight: return "bracketright";
            case Qt.Key_Backslash:
            case Qt.Key_Bar: return "backslash";
            case Qt.Key_Semicolon:
            case Qt.Key_Colon: return "semicolon";
            case Qt.Key_Apostrophe:
            case Qt.Key_QuoteDbl: return "apostrophe";
            case Qt.Key_Comma:
            case Qt.Key_Less: return "comma";
            case Qt.Key_Period:
            case Qt.Key_Greater: return "period";
            case Qt.Key_Slash:
            case Qt.Key_Question: return "slash";
            case Qt.Key_VolumeUp: return "XF86AudioRaiseVolume";
            case Qt.Key_VolumeDown: return "XF86AudioLowerVolume";
            case Qt.Key_VolumeMute: return "XF86AudioMute";
            case Qt.Key_MicMute: return "XF86AudioMicMute";
            case Qt.Key_MonBrightnessUp: return "XF86MonBrightnessUp";
            case Qt.Key_MonBrightnessDown: return "XF86MonBrightnessDown";
            case Qt.Key_MediaPlay:
            case Qt.Key_MediaTogglePlayPause: return "XF86AudioPlay";
            case Qt.Key_MediaPause: return "XF86AudioPause";
            case Qt.Key_MediaStop: return "XF86AudioStop";
            case Qt.Key_MediaNext: return "XF86AudioNext";
            case Qt.Key_MediaPrevious: return "XF86AudioPrev";
        }
        return "";
    }

    Keys.onPressed: (event) => {
        if (!root.open) return;

        if (event.key === Qt.Key_Escape) {
            if (root.selectMenu && root.selectMenu.isOpen) {
                root.selectMenu.close();
            } else if (root.listeningKey) {
                root.listeningKey = false;
            } else {
                root.close();
            }
            event.accepted = true;
            return;
        }

        if (!root.listeningKey) return;
        const mapped = root.mapQtKeyToHypr(event);
        if (mapped === "") return;

        const hasRealMods = Boolean(event.modifiers & (Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier));
        if (mapped.indexOf("XF86") === 0 && !hasRealMods) {
            root.modSuper = false;
            root.modCtrl = false;
            root.modAlt = false;
            root.modShift = false;
        } else if (hasRealMods) {
            if (root._modsManuallyEdited) {
                if (event.modifiers & Qt.MetaModifier) root.modSuper = true;
                if (event.modifiers & Qt.ControlModifier) root.modCtrl = true;
                if (event.modifiers & Qt.AltModifier) root.modAlt = true;
                if (event.modifiers & Qt.ShiftModifier) root.modShift = true;
            } else {
                root.modSuper = Boolean(event.modifiers & Qt.MetaModifier);
                root.modCtrl = Boolean(event.modifiers & Qt.ControlModifier);
                root.modAlt = Boolean(event.modifiers & Qt.AltModifier);
                root.modShift = Boolean(event.modifiers & Qt.ShiftModifier);
            }
        }

        root.recordedKey = mapped;
        root.syncControlsToActiveSlot();
        event.accepted = true;
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.56)
        opacity: root.open ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            enabled: root.open
            onClicked: root.close()
        }
    }

    Rectangle {
        id: modalCard
        anchors.centerIn: parent
        width: Math.min(460, Math.max(280, parent.width - 36))
        height: Math.max(160, Math.min(Math.max(160, parent.height - 36), headerBar.implicitHeight + bodyCol.implicitHeight + footerBar.implicitHeight + 52))
        radius: 14
        clip: true
        color: Theme.surfaceBg
        border.width: 1
        border.color: Theme.borderSubtle
        opacity: root.open ? 1.0 : 0.0
        scale: root.open ? 1.0 : 0.94

        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: modalCard; property: "anchors.horizontalCenterOffset"; to: -8; duration: 45 }
            NumberAnimation { target: modalCard; property: "anchors.horizontalCenterOffset"; to: 8; duration: 45 }
            NumberAnimation { target: modalCard; property: "anchors.horizontalCenterOffset"; to: -6; duration: 45 }
            NumberAnimation { target: modalCard; property: "anchors.horizontalCenterOffset"; to: 0; duration: 45 }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: modalCol
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // Header
            RowLayout {
                id: headerBar
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.editingBindId !== "" ? "Edit Shortcut" : "Add Shortcut"
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: 26; height: 26; radius: 7
                    color: closeM.containsMouse ? Theme.cardHover : "transparent"
                    scale: closeM.pressed ? 0.92 : 1.0
                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                    SvgIcon {
                        anchors.centerIn: parent
                        sourceName: "close"
                        iconSize: 14
                        color: closeM.containsMouse ? Theme.text : Theme.textSub
                    }
                    MouseArea {
                        id: closeM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }

            // Scrollable Body
            Flickable {
                id: bodyFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: bodyCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: bodyFlick.contentHeight > bodyFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    width: 4
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.25)
                    }
                }

                ColumnLayout {
                    id: bodyCol
                    width: bodyFlick.width
                    spacing: 12

                    // ==================== STEP 1: ACTION ====================
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "ACTION"
                            color: Theme.textMuted
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 0.6
                        }

                        // Category Tabs
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: [
                                    { key: "island",     label: "Island" },
                                    { key: "screenshot", label: "Capture" },
                                    { key: "apps",       label: "App" },
                                    { key: "window",     label: "Window" },
                                    { key: "command",    label: "Command" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool active: root.editorTab === modelData.key
                                    height: 28
                                    implicitWidth: tabLbl.implicitWidth + 18
                                    radius: 8
                                    clip: true
                                    color: active ? Theme.accent : (tabM.containsMouse ? Theme.cardHover : Theme.cardBg)
                                    border.width: 1
                                    border.color: active ? Theme.accent : Theme.borderSubtle
                                    scale: tabM.pressed ? 0.95 : 1.0
                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }

                                    Text {
                                        id: tabLbl
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: active ? Theme.accentFg : Theme.text
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        font.weight: active ? Font.DemiBold : Font.Medium
                                    }
                                    MouseArea {
                                        id: tabM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.editorTab === modelData.key) return;
                                            root.editorTab = modelData.key;
                                            root.applyDefaultActionForTab(modelData.key);
                                            root.validationError = "";
                                        }
                                    }
                                }
                            }
                        }

                        // Preset Dropdown (Island / Capture / Window)
                        Rectangle {
                            id: actionDropBox
                            visible: root.editorTab === "island" || root.editorTab === "screenshot" || root.editorTab === "window"
                            Layout.fillWidth: true
                            height: 36
                            radius: 9
                            clip: true
                            color: actM.containsMouse ? Theme.cardHover : Theme.surfaceRaised
                            border.width: 1
                            border.color: actM.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : Theme.borderSubtle
                            scale: actM.pressed ? 0.98 : 1.0
                            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: root.selectedTitle !== "" ? root.selectedTitle : "Choose action..."
                                    color: root.selectedTitle !== "" ? Theme.text : Theme.textMuted
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                SvgIcon {
                                    sourceName: "chevron-right"
                                    iconSize: 13
                                    color: Theme.textMuted
                                    rotation: 90
                                }
                            }

                            MouseArea {
                                id: actM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    let opts = [];
                                    if (root.editorTab === "island") {
                                        opts = KeybindService.islandActions.map(a => ({
                                            text: a.label,
                                            checked: root.selectedActionLua === a.lua,
                                            action: () => root.selectPresetAction("island", a.label, "", a.lua, "", a.opts || "")
                                        }));
                                    } else if (root.editorTab === "screenshot") {
                                        opts = KeybindService.screenshotActions.map(a => ({
                                            text: a.label,
                                            checked: root.selectedActionLua === a.lua,
                                            action: () => root.selectPresetAction("screenshot", a.label, a.desc, a.lua, "", a.opts || "")
                                        }));
                                    } else if (root.editorTab === "window") {
                                        opts = KeybindService.windowActions.map(a => ({
                                            text: a.label,
                                            checked: root.selectedActionLua === a.lua,
                                            action: () => root.selectPresetAction("window", a.label, a.desc, a.lua, "", "")
                                        }));
                                    }
                                    root.openMenuFor(actionDropBox, opts, actionDropBox.width);
                                }
                            }
                        }

                        // Searchable App Picker (Apps tab)
                        ColumnLayout {
                            visible: root.editorTab === "apps"
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                height: 34
                                radius: 9
                                clip: true
                                color: Theme.cardBg
                                border.width: 1
                                border.color: appSearchInput.activeFocus ? Theme.accent : Theme.borderSubtle
                                Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    SvgIcon { sourceName: "search"; iconSize: 14; color: Theme.textSub }

                                    AnimatedTextInput {
                                        id: appSearchInput
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        textColor: Theme.text
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        clip: true
                                        onActiveFocusChanged: {
                                            if (activeFocus) root.listeningKey = false;
                                        }
                                        onTextChanged: root.appSearchQuery = text
                                        Keys.onEscapePressed: (event) => {
                                            if (text !== "") {
                                                text = "";
                                            } else {
                                                root.forceActiveFocus();
                                            }
                                            event.accepted = true;
                                        }

                                        Text {
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            text: "Search default or installed apps..."
                                            color: Theme.textMuted
                                            font: appSearchInput.font
                                            visible: appSearchInput.text.length === 0
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        visible: appSearchInput.text.length > 0
                                        width: 20; height: 20; radius: 5
                                        color: clrAppM.containsMouse ? Theme.cardHover : "transparent"
                                        scale: clrAppM.pressed ? 0.9 : 1.0
                                        Behavior on color { ColorAnimation { duration: 110 } }
                                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

                                        SvgIcon { anchors.centerIn: parent; sourceName: "close"; iconSize: 11; color: Theme.textMuted }
                                        MouseArea {
                                            id: clrAppM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: appSearchInput.text = ""
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(132, Math.max(44, root.filteredAppChoices.length * 36 + 8))
                                radius: 10
                                clip: true
                                color: Theme.cardBg
                                border.width: 1
                                border.color: Theme.borderSubtle

                                ListView {
                                    id: appListView
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 2
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: root.filteredAppChoices

                                    ScrollBar.vertical: ScrollBar {
                                        policy: appListView.contentHeight > appListView.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                        width: 4
                                        contentItem: Rectangle {
                                            implicitWidth: 4
                                            radius: 2
                                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.25)
                                        }
                                    }

                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool isChosen: modelData.isDefault
                                            ? (root.selectedActionLua === modelData.lua)
                                            : (root.selectedAppId === modelData.id)

                                        width: appListView.width
                                        height: 34
                                        radius: 8
                                        clip: true
                                        color: isChosen
                                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                            : (appItemM.containsMouse ? Theme.cardHover : "transparent")
                                        border.width: isChosen ? 1 : 0
                                        border.color: isChosen ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : "transparent"
                                        scale: appItemM.pressed ? 0.98 : 1.0
                                        Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 8

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: modelData.label
                                                color: Theme.text
                                                font.family: Theme.fontSans
                                                font.pixelSize: 12
                                                font.weight: isChosen ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.maximumWidth: 140
                                                text: modelData.sub
                                                color: Theme.textMuted
                                                font.family: Theme.fontMono
                                                font.pixelSize: 10
                                                elide: Text.ElideMiddle
                                            }
                                            SvgIcon {
                                                visible: isChosen
                                                sourceName: "check"
                                                iconSize: 13
                                                color: Theme.accent
                                            }
                                        }

                                        MouseArea {
                                            id: appItemM
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.selectAppChoice(modelData)
                                        }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: root.filteredAppChoices.length === 0
                                    text: "No matching apps"
                                    color: Theme.textMuted
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                }
                            }
                        }

                        // Custom Command Input (Command tab)
                        ColumnLayout {
                            visible: root.editorTab === "command"
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                height: 36
                                radius: 9
                                clip: true
                                color: Theme.surfaceRaised
                                border.width: 1
                                border.color: cmdInput.activeFocus ? Theme.accent : Theme.borderSubtle
                                Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    SvgIcon { sourceName: "terminal"; iconSize: 14; color: Theme.textSub }

                                    AnimatedTextInput {
                                        id: cmdInput
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        textColor: Theme.text
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                        clip: true
                                        onActiveFocusChanged: {
                                            if (activeFocus) root.listeningKey = false;
                                        }
                                        onTextChanged: {
                                            root.customCmdInput = text;
                                            root.validationError = "";
                                        }
                                        Keys.onEscapePressed: (event) => {
                                            root.forceActiveFocus();
                                            event.accepted = true;
                                        }

                                        Text {
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            text: root.rawLuaFallback
                                                ? ("Lua: " + root.selectedActionLua)
                                                : "e.g. kitty, playerctl play-pause"
                                            color: Theme.textMuted
                                            font: cmdInput.font
                                            visible: cmdInput.text.length === 0
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                    // ==================== STEP 2: SHORTCUT ====================
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.editingComboIdx >= 0 ? "SHORTCUT (REBINDING)" : "SHORTCUT"
                                color: Theme.textMuted
                                font.family: Theme.fontSans
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 0.6
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: root.listeningKey
                                text: "Listening..."
                                color: Theme.accent
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }

                        // Alternate combo slots selector (shown when > 1 combo or adding alternate)
                        Flow {
                            visible: root.workingCombos.length > 1
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: root.workingCombos
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    readonly property bool selected: index === root.activeComboIdx
                                    height: 26
                                    implicitWidth: slotRow.implicitWidth + 14
                                    radius: 7
                                    clip: true
                                    color: selected
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                        : (slotM.containsMouse ? Theme.cardHover : Theme.surfaceRaised)
                                    border.width: 1
                                    border.color: selected ? Theme.accent : Theme.borderSubtle
                                    scale: slotM.pressed ? 0.95 : 1.0
                                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

                                    RowLayout {
                                        id: slotRow
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            text: modelData.combo !== "" ? modelData.combo : ("Slot " + (index + 1))
                                            color: modelData.combo !== "" ? Theme.text : Theme.textMuted
                                            font.family: Theme.fontMono
                                            font.pixelSize: 10
                                            font.weight: Font.Medium
                                        }

                                        Rectangle {
                                            visible: root.workingCombos.length > 1
                                            width: 14; height: 14; radius: 4
                                            color: rmSlotM.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.22) : "transparent"
                                            SvgIcon {
                                                anchors.centerIn: parent
                                                sourceName: "close"
                                                iconSize: 9
                                                color: rmSlotM.containsMouse ? Theme.dangerText : Theme.textMuted
                                            }
                                            MouseArea {
                                                id: rmSlotM
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: (m) => {
                                                    m.accepted = true;
                                                    root.removeSlotAt(index);
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: slotM
                                        anchors.fill: parent
                                        z: -1
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.activeComboIdx = index;
                                            root.loadSlotIntoControls(index);
                                            root.listeningKey = true;
                                            root.forceActiveFocus();
                                        }
                                    }
                                }
                            }
                        }

                        // Capture Pad
                        Rectangle {
                            id: capturePad
                            Layout.fillWidth: true
                            height: 52
                            radius: 10
                            clip: true
                            color: root.listeningKey
                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                                : (capM.containsMouse ? Theme.cardHover : Theme.surfaceRaised)
                            border.width: root.listeningKey ? 1.5 : 1
                            border.color: root.listeningKey ? Theme.accent : Theme.borderSubtle
                            scale: capM.pressed ? 0.99 : 1.0
                            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                            MouseArea {
                                id: capM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.listeningKey = true;
                                    root.forceActiveFocus();
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                spacing: 8

                                // Live keycaps preview
                                Row {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 5
                                    clip: true

                                    readonly property var draftParts: KeybindService.splitComboParts(root.currentDraftCombo())

                                    Repeater {
                                        model: parent.draftParts
                                        delegate: Row {
                                            required property string modelData
                                            required property int index
                                            spacing: 5

                                            Text {
                                                visible: index > 0
                                                text: "+"
                                                color: Theme.textMuted
                                                font.family: Theme.fontMono
                                                font.pixelSize: 11
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Rectangle {
                                                height: 24
                                                implicitWidth: Math.max(26, capKeyLbl.implicitWidth + 12)
                                                radius: 6
                                                color: KeybindService.isModPart(modelData) ? Theme.cardBg : Theme.pillBg
                                                border.width: 1
                                                border.color: Theme.borderSubtle
                                                anchors.verticalCenter: parent.verticalCenter

                                                Text {
                                                    id: capKeyLbl
                                                    anchors.centerIn: parent
                                                    text: KeybindService.prettyKeyLabel(modelData)
                                                    color: Theme.text
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 11
                                                    font.weight: Font.Medium
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        visible: root.recordedKey === ""
                                        height: 24
                                        verticalAlignment: Text.AlignVCenter
                                        text: root.listeningKey ? "  Press any key..." : "  Click to capture key"
                                        color: Theme.textMuted
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                    }
                                }

                                // Quick Special Key picker
                                Rectangle {
                                    id: specialKeyBtn
                                    height: 28
                                    implicitWidth: spRow.implicitWidth + 14
                                    radius: 7
                                    color: spM.containsMouse ? Theme.cardHover : Theme.cardBg
                                    border.width: 1
                                    border.color: Theme.borderSubtle
                                    scale: spM.pressed ? 0.94 : 1.0
                                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

                                    RowLayout {
                                        id: spRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            text: "Keys"
                                            color: Theme.textSub
                                            font.family: Theme.fontSans
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }
                                        SvgIcon {
                                            sourceName: "chevron-right"
                                            iconSize: 11
                                            color: Theme.textMuted
                                            rotation: 90
                                        }
                                    }
                                    MouseArea {
                                        id: spM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const commonKeys = [
                                                "space", "Return", "Escape", "Tab", "Print",
                                                "left", "right", "up", "down",
                                                "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute",
                                                "XF86MonBrightnessUp", "XF86MonBrightnessDown",
                                                "XF86AudioPlay", "XF86AudioPause", "XF86AudioNext", "XF86AudioPrev"
                                            ];
                                            const opts = commonKeys.map(k => ({
                                                text: KeybindService.prettyKeyLabel(k),
                                                shortcut: k.indexOf("XF86") === 0 ? "Media" : "",
                                                checked: root.recordedKey === k,
                                                action: () => {
                                                    if (k.indexOf("XF86") === 0) {
                                                        root.modSuper = false;
                                                        root.modCtrl = false;
                                                        root.modAlt = false;
                                                        root.modShift = false;
                                                    }
                                                    root.recordedKey = k;
                                                    root.syncControlsToActiveSlot();
                                                }
                                            }));
                                            root.openMenuFor(specialKeyBtn, opts, 190);
                                        }
                                    }
                                }
                            }
                        }

                        // Direct 4 Modifier Toggle Pills + "+ Alt" button
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: [
                                    { key: "super", label: "SUPER", on: root.modSuper },
                                    { key: "ctrl",  label: "CTRL",  on: root.modCtrl },
                                    { key: "alt",   label: "ALT",   on: root.modAlt },
                                    { key: "shift", label: "SHIFT", on: root.modShift }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    height: 26
                                    implicitWidth: modPLbl.implicitWidth + 16
                                    radius: 7
                                    clip: true
                                    color: modelData.on ? Theme.accent : (modPM.containsMouse ? Theme.cardHover : Theme.cardBg)
                                    border.width: 1
                                    border.color: modelData.on ? Theme.accent : Theme.borderSubtle
                                    scale: modPM.pressed ? 0.94 : 1.0
                                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

                                    Text {
                                        id: modPLbl
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: modelData.on ? Theme.accentFg : Theme.textSub
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                    }

                                    MouseArea {
                                        id: modPM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root._modsManuallyEdited = true;
                                            if (modelData.key === "super") root.modSuper = !root.modSuper;
                                            else if (modelData.key === "ctrl") root.modCtrl = !root.modCtrl;
                                            else if (modelData.key === "alt") root.modAlt = !root.modAlt;
                                            else if (modelData.key === "shift") root.modShift = !root.modShift;
                                            root.syncControlsToActiveSlot();
                                            root.listeningKey = true;
                                            root.forceActiveFocus();
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                height: 26
                                implicitWidth: altLbl.implicitWidth + 14
                                radius: 7
                                clip: true
                                color: altM.containsMouse ? Theme.cardHover : Theme.surfaceRaised
                                border.width: 1
                                border.color: Theme.borderSubtle
                                scale: altM.pressed ? 0.94 : 1.0
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

                                Text {
                                    id: altLbl
                                    anchors.centerIn: parent
                                    text: "+ Alt"
                                    color: Theme.textSub
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                                MouseArea {
                                    id: altM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.addAlternateSlot()
                                }
                            }
                        }

                        // Compact Behavior Flags (Lockscreen / Repeat)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: [
                                    { key: "locked",    label: "Work on Lockscreen", on: Boolean(root.activeSlot.locked) },
                                    { key: "repeating", label: "Hold to Repeat",     on: Boolean(root.activeSlot.repeating) }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    height: 26
                                    implicitWidth: flRow.implicitWidth + 14
                                    radius: 7
                                    clip: true
                                    color: modelData.on
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                        : (flM.containsMouse ? Theme.cardHover : "transparent")
                                    border.width: 1
                                    border.color: modelData.on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.50) : Theme.borderSubtle
                                    scale: flM.pressed ? 0.95 : 1.0
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }
                                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

                                    RowLayout {
                                        id: flRow
                                        anchors.centerIn: parent
                                        spacing: 5
                                        SvgIcon {
                                            sourceName: "check"
                                            iconSize: 11
                                            color: modelData.on ? Theme.accent : Theme.textMuted
                                            opacity: modelData.on ? 1.0 : 0.35
                                        }
                                        Text {
                                            text: modelData.label
                                            color: modelData.on ? Theme.text : Theme.textSub
                                            font.family: Theme.fontSans
                                            font.pixelSize: 11
                                        }
                                    }
                                    MouseArea {
                                        id: flM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleSlotOption(modelData.key)
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Real-time Conflict Warning Banner
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: root.activeConflicts.length > 0 ? (confLbl.implicitHeight + 14) : 0
                            opacity: root.activeConflicts.length > 0 ? 1.0 : 0.0
                            visible: implicitHeight > 1 || opacity > 0.01
                            radius: 9
                            clip: true
                            color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.12)
                            border.width: 1
                            border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.42)
                            Behavior on implicitHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                            Text {
                                id: confLbl
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 10
                                text: root.activeConflicts.length > 0 ? root.activeConflicts[0] : ""
                                color: Theme.warn
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Validation Error Message
                        Text {
                            visible: root.validationError !== ""
                            Layout.fillWidth: true
                            text: root.validationError
                            color: Theme.dangerText
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // Footer Actions
            RowLayout {
                id: footerBar
                Layout.fillWidth: true
                spacing: 8

                PillButton {
                    visible: root.editingBindId !== ""
                    text: root.confirmDelete ? "Confirm Delete?" : "Delete"
                    iconName: "trash"
                    danger: true
                    active: root.confirmDelete
                    fixedHeight: 32
                    radius: 8
                    onClicked: {
                        if (!root.confirmDelete) {
                            root.confirmDelete = true;
                            deleteResetTimer.restart();
                        } else {
                            deleteResetTimer.stop();
                            const idToDelete = root.editingBindId;
                            root.close();
                            KeybindService.deleteBind(idToDelete);
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                PillButton {
                    text: "Cancel"
                    fixedHeight: 32
                    radius: 8
                    onClicked: root.close()
                }

                PillButton {
                    text: "Save"
                    active: true
                    fixedHeight: 32
                    radius: 8
                    onClicked: root.commitEditor()
                }
            }
        }
    }
}
