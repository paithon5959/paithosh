import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import ".."
import "../services"

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 12

    property var selectMenu: null
    property var menuRoot: null

    property string selectedCategory: "all"
    property string searchQuery: ""

    // Editor state
    property bool editorOpen: false
    property string editingBindId: ""
    property string editorTab: "island" // island | screenshot | apps | window | command
    property string selectedActionLua: ""
    property string selectedCommand: ""
    property string selectedTitle: ""
    property string selectedSubtitle: ""
    property string selectedAppId: ""
    property string selectedOpts: ""
    property string customCmdInput: ""
    property var desktopApps: []

    // Key recorder & multi-select modifier state
    property bool listeningKey: false
    property bool modPickerOpen: false
    property bool modSuper: true
    property bool modCtrl: false
    property bool modAlt: false
    property bool modShift: false
    property string recordedKey: ""
    property var stagedCombos: [] // [{ combo: "SUPER + T", opts: "" }]

    Component.onCompleted: refreshDesktopApps()

    function refreshDesktopApps() {
        const entries = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        const list = [];
        if (entries) {
            for (let i = 0; i < entries.length; ++i) {
                const e = entries[i];
                if (!e || e.noDisplay || !e.name) continue;
                list.push({
                    id: e.id || e.name,
                    name: e.name,
                    genericName: e.genericName || "",
                    category: AppService.mapCategory(e.categories)
                });
            }
        }
        list.sort((a, b) => a.name.localeCompare(b.name));
        root.desktopApps = list;
    }

    function categoryLabel(key) {
        if (key === "island") return "Dynamic Island";
        if (key === "screenshot") return "Screenshot";
        if (key === "apps") return "Open App (.desktop)";
        if (key === "window") return "Window & Workspace";
        if (key === "command") return "Custom Command";
        return key;
    }

    function modifiersSummary() {
        const parts = [];
        if (root.modSuper) parts.push("SUPER");
        if (root.modCtrl) parts.push("CTRL");
        if (root.modAlt) parts.push("ALT");
        if (root.modShift) parts.push("SHIFT");
        return parts.length > 0 ? parts.join(" + ") : "None";
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

    function setModsFromCombo(comboStr) {
        const parts = KeybindService.splitComboParts(comboStr).map(p => p.toUpperCase());
        root.modSuper = parts.indexOf("SUPER") !== -1;
        root.modCtrl = parts.indexOf("CTRL") !== -1;
        root.modAlt = parts.indexOf("ALT") !== -1;
        root.modShift = parts.indexOf("SHIFT") !== -1;
        let mainKey = "";
        const rawParts = KeybindService.splitComboParts(comboStr);
        for (let i = 0; i < rawParts.length; ++i) {
            const up = rawParts[i].toUpperCase();
            if (up !== "SUPER" && up !== "CTRL" && up !== "ALT" && up !== "SHIFT") {
                mainKey = rawParts[i];
            }
        }
        root.recordedKey = mainKey;
    }

    function openMenuFor(anchorItem, menuItems, minWidth) {
        if (!root.selectMenu || !root.menuRoot) return;
        const pt = anchorItem.mapToItem(root.menuRoot, 0, anchorItem.height + 4);
        root.selectMenu.menuWidth = Math.max(minWidth || 200, anchorItem.width);
        root.selectMenu.openAt(pt.x, pt.y, menuItems);
    }

    function openNewEditor(defaultTab) {
        root.editingBindId = "";
        root.editorTab = defaultTab || "island";
        root.stagedCombos = [];
        root.modPickerOpen = false;
        root.modSuper = true;
        root.modCtrl = false;
        root.modAlt = false;
        root.modShift = false;
        root.recordedKey = "";
        root.customCmdInput = "";
        root.selectedAppId = "";
        root.selectedOpts = "";
        applyDefaultActionForTab(root.editorTab);
        root.editorOpen = true;
        root.listeningKey = true;
        keyCaptureScope.forceActiveFocus();
    }

    function applyDefaultActionForTab(tab) {
        if (tab === "island" && KeybindService.islandActions.length > 0) {
            const a = KeybindService.islandActions[0];
            selectPresetAction("island", a.label, a.desc, 'hl.dsp.exec_cmd("' + a.cmd.replace(/"/g, '\\"') + '")', a.cmd, a.opts || "");
        } else if (tab === "screenshot" && KeybindService.screenshotActions.length > 0) {
            const a = KeybindService.screenshotActions[0];
            selectPresetAction("screenshot", a.label, a.desc, 'hl.dsp.exec_cmd("' + a.cmd.replace(/"/g, '\\"') + '")', a.cmd, a.opts || "");
        } else if (tab === "apps" && root.desktopApps.length > 0) {
            selectDesktopApp(root.desktopApps[0]);
        } else if (tab === "window" && KeybindService.windowActions.length > 0) {
            const a = KeybindService.windowActions[0];
            selectPresetAction("window", a.label, a.desc, a.lua, "", "");
        } else {
            root.selectedActionLua = "";
            root.selectedCommand = "";
            root.selectedTitle = "";
            root.selectedSubtitle = "";
        }
    }

    function openEditBind(bindObj, focusAddCombo) {
        root.editingBindId = bindObj.id;
        root.editorTab = bindObj.category || "command";
        root.selectedTitle = bindObj.title || "";
        root.selectedSubtitle = bindObj.subtitle || "";
        root.selectedActionLua = bindObj.actionLua || "";
        root.selectedCommand = bindObj.command || "";
        root.selectedAppId = bindObj.appId || "";
        root.customCmdInput = bindObj.command || "";
        root.stagedCombos = (bindObj.combos || []).map(c => Object.assign({}, c));
        root.selectedOpts = (bindObj.combos && bindObj.combos.length > 0) ? (bindObj.combos[0].opts || "") : "";
        root.modPickerOpen = false;
        if (focusAddCombo) {
            root.modSuper = true;
            root.modCtrl = false;
            root.modAlt = false;
            root.modShift = false;
            root.recordedKey = "";
        } else if (root.stagedCombos.length > 0) {
            setModsFromCombo(root.stagedCombos[0].combo);
        }
        root.editorOpen = true;
        root.listeningKey = true;
        keyCaptureScope.forceActiveFocus();
    }

    function selectPresetAction(cat, label, desc, luaExpr, cmd, opts) {
        root.selectedTitle = label;
        root.selectedSubtitle = desc;
        root.selectedActionLua = luaExpr;
        root.selectedCommand = cmd || "";
        root.selectedOpts = opts || "";
        root.selectedAppId = "";
    }

    function selectDesktopApp(app) {
        const launchCmd = "gtk-launch " + app.id;
        root.selectedAppId = app.id;
        root.selectedTitle = "Launch " + app.name;
        root.selectedSubtitle = launchCmd;
        root.selectedCommand = launchCmd;
        root.selectedActionLua = 'hl.dsp.exec_cmd("' + launchCmd.replace(/"/g, '\\"') + '")';
        root.selectedOpts = "";
    }

    function stageCurrentDraft() {
        if (root.recordedKey === "") return false;
        const draft = currentDraftCombo();
        const norm = KeybindService.normalizeComboKey(draft);
        const list = root.stagedCombos.slice();
        if (!list.some(c => KeybindService.normalizeComboKey(c.combo) === norm)) {
            list.push({ combo: draft, opts: root.selectedOpts });
            root.stagedCombos = list;
        }
        root.recordedKey = "";
        return true;
    }

    function commitEditor() {
        if (root.editorTab === "command") {
            const c = root.customCmdInput.trim();
            if (c === "") return;
            root.selectedCommand = c;
            root.selectedTitle = c;
            root.selectedSubtitle = "Custom command";
            root.selectedActionLua = 'hl.dsp.exec_cmd("' + c.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '")';
        }
        if (root.selectedActionLua === "") return;

        if (root.recordedKey !== "") {
            stageCurrentDraft();
        }
        if (root.stagedCombos.length === 0) return;

        if (root.editingBindId !== "") {
            KeybindService.updateBind(
                root.editingBindId,
                root.editorTab,
                root.selectedTitle,
                root.selectedSubtitle,
                root.selectedActionLua,
                root.selectedCommand,
                root.selectedAppId,
                root.stagedCombos
            );
        } else {
            KeybindService.addOrMergeBind(
                root.editorTab,
                root.selectedTitle,
                root.selectedSubtitle,
                root.selectedActionLua,
                root.selectedCommand,
                root.selectedAppId,
                root.stagedCombos
            );
        }
        root.editorOpen = false;
        root.listeningKey = false;
        root.modPickerOpen = false;
    }

    function mapQtKeyToHypr(event) {
        const k = event.key;
        if (k === Qt.Key_Super_L || k === Qt.Key_Super_R || k === Qt.Key_Meta ||
            k === Qt.Key_Control || k === Qt.Key_Alt || k === Qt.Key_Shift) {
            return "";
        }
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(65 + (k - Qt.Key_A));
        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(48 + (k - Qt.Key_0));
        if (k >= Qt.Key_F1 && k <= Qt.Key_F12) return "F" + (k - Qt.Key_F1 + 1);
        switch (k) {
            case Qt.Key_Space: return "space";
            case Qt.Key_Return:
            case Qt.Key_Enter: return "Return";
            case Qt.Key_Escape: return "Escape";
            case Qt.Key_Tab: return "Tab";
            case Qt.Key_Backspace: return "BackSpace";
            case Qt.Key_Delete: return "Delete";
            case Qt.Key_Left: return "left";
            case Qt.Key_Right: return "right";
            case Qt.Key_Up: return "up";
            case Qt.Key_Down: return "down";
            case Qt.Key_Print: return "Print";
            case Qt.Key_Home: return "Home";
            case Qt.Key_End: return "End";
            case Qt.Key_PageUp: return "Prior";
            case Qt.Key_PageDown: return "Next";
            case Qt.Key_Minus: return "minus";
            case Qt.Key_Equal: return "equal";
            case Qt.Key_BracketLeft: return "bracketleft";
            case Qt.Key_BracketRight: return "bracketright";
            case Qt.Key_Slash: return "slash";
            case Qt.Key_Backslash: return "backslash";
            case Qt.Key_Semicolon: return "semicolon";
            case Qt.Key_Comma: return "comma";
            case Qt.Key_Period: return "period";
            case Qt.Key_VolumeUp: return "XF86AudioRaiseVolume";
            case Qt.Key_VolumeDown: return "XF86AudioLowerVolume";
            case Qt.Key_VolumeMute: return "XF86AudioMute";
            case Qt.Key_MonBrightnessUp: return "XF86MonBrightnessUp";
            case Qt.Key_MonBrightnessDown: return "XF86MonBrightnessDown";
            case Qt.Key_MediaPlay:
            case Qt.Key_MediaTogglePlayPause: return "XF86AudioPlay";
            case Qt.Key_MediaNext: return "XF86AudioNext";
            case Qt.Key_MediaPrevious: return "XF86AudioPrev";
        }
        return "";
    }

    function prettyKeyLabel(part) {
        const p = String(part || "").trim();
        const low = p.toLowerCase();
        if (low === "super") return "SUPER";
        if (low === "ctrl" || low === "control") return "CTRL";
        if (low === "alt") return "ALT";
        if (low === "shift") return "SHIFT";
        if (low === "space") return "SPACE";
        if (low === "return") return "ENTER";
        if (low === "escape") return "ESC";
        if (low === "left") return "LEFT";
        if (low === "right") return "RIGHT";
        if (low === "up") return "UP";
        if (low === "down") return "DOWN";
        if (p === "XF86AudioRaiseVolume") return "VOL +";
        if (p === "XF86AudioLowerVolume") return "VOL -";
        if (p === "XF86AudioMute") return "MUTE";
        if (p === "XF86AudioMicMute") return "MIC MUTE";
        if (p === "XF86MonBrightnessUp") return "BRI +";
        if (p === "XF86MonBrightnessDown") return "BRI -";
        if (p === "XF86AudioNext") return "NEXT";
        if (p === "XF86AudioPrev") return "PREV";
        if (p === "XF86AudioPlay" || p === "XF86AudioPause") return "PLAY";
        if (p === "Super_L") return "SUPER (Tap)";
        return p.toUpperCase();
    }

    function isModPart(part) {
        const up = String(part || "").toUpperCase();
        return up === "SUPER" || up === "CTRL" || up === "ALT" || up === "SHIFT";
    }

    function visibleCategories() {
        if (root.selectedCategory === "all") return KeybindService.categoryOrder;
        return [root.selectedCategory];
    }

    function bindsForCategory(cat) {
        const q = root.searchQuery.trim().toLowerCase();
        const out = [];
        const all = KeybindService.binds || [];
        for (let i = 0; i < all.length; ++i) {
            const b = all[i];
            if (b.category !== cat) continue;
            if (q !== "") {
                const comboText = (b.combos || []).map(c => c.combo).join(" ").toLowerCase();
                const hay = ((b.title || "") + " " + (b.subtitle || "") + " " + comboText).toLowerCase();
                if (hay.indexOf(q) === -1) continue;
            }
            out.push(b);
        }
        return out;
    }

    // Shell-native Keycap Chip Group
    component KeycapChipGroup: Rectangle {
        id: kcGroup
        property string comboText: ""
        property bool editable: true
        signal clicked()
        signal removeClicked()

        readonly property var parts: KeybindService.splitComboParts(comboText)

        height: 28
        implicitWidth: kcRow.implicitWidth + (editable ? 28 : 14)
        radius: 8
        clip: true
        color: kcMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised
        border.width: 1
        border.color: Theme.borderSubtle
        scale: kcMouse.pressed ? 0.95 : 1.0
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

        MouseArea {
            id: kcMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: kcGroup.editable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (kcGroup.editable) kcGroup.clicked();
            }
        }

        Row {
            id: kcRow
            anchors.left: parent.left
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Repeater {
                model: kcGroup.parts
                delegate: Row {
                    required property string modelData
                    required property int index
                    spacing: 4

                    Text {
                        visible: index > 0
                        text: "+"
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        height: 20
                        implicitWidth: Math.max(22, kLbl.implicitWidth + 10)
                        radius: 5
                        color: root.isModPart(modelData) ? Theme.cardBg : "transparent"
                        border.width: 1
                        border.color: Theme.borderSubtle
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            id: kLbl
                            anchors.centerIn: parent
                            text: root.prettyKeyLabel(modelData)
                            color: root.isModPart(modelData) ? Theme.text : Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: kcGroup.editable
            anchors.right: parent.right
            anchors.rightMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16; radius: 4
            color: rmMouse.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.20) : "transparent"
            scale: rmMouse.pressed ? 0.9 : 1.0
            Behavior on color { ColorAnimation { duration: 100 } }
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }

            Text {
                anchors.centerIn: parent
                text: "×"
                color: rmMouse.containsMouse ? Theme.dangerText : Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 12
                font.weight: Font.Bold
            }
            MouseArea {
                id: rmMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    mouse.accepted = true;
                    kcGroup.removeClicked();
                }
            }
        }
    }

    // ==================== HEADER CARD ====================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 58
        radius: 12
        clip: true
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2

                RowLayout {
                    spacing: 8
                    Text {
                        text: "Hyprland Keybinds"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Rectangle {
                        height: 18
                        implicitWidth: expLbl.implicitWidth + 12
                        radius: 9
                        color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.16)
                        border.width: 1
                        border.color: Theme.danger
                        Text {
                            id: expLbl
                            anchors.centerIn: parent
                            text: "Experimental"
                            color: Theme.dangerText
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }
                    Text {
                        text: KeybindService.totalComboCount + " shortcuts"
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                    }
                    Rectangle {
                        visible: KeybindService.statusText !== ""
                        height: 18
                        implicitWidth: stLbl.implicitWidth + 12
                        radius: 9
                        color: KeybindService.statusOk
                            ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.16)
                            : Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.18)
                        border.width: 1
                        border.color: KeybindService.statusOk ? Theme.ok : Theme.danger
                        Text {
                            id: stLbl
                            anchors.centerIn: parent
                            text: KeybindService.statusText
                            color: KeybindService.statusOk ? Theme.ok : Theme.dangerText
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "~/.config/hypr/config/binds.lua"
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            // Reload button (matching CtrlBtn ghost)
            Rectangle {
                height: 30
                implicitWidth: reloadLbl.implicitWidth + 22
                radius: 8
                color: relMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised
                border.width: 1; border.color: Theme.borderSubtle
                scale: relMouse.pressed ? 0.95 : 1.0
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                Text {
                    id: reloadLbl
                    anchors.centerIn: parent
                    text: "Reload"
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: relMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: KeybindService.reloadHyprland()
                }
            }

            // Add Keybind button (matching CtrlBtn primary)
            Rectangle {
                height: 30
                implicitWidth: addLbl.implicitWidth + 22
                radius: 8
                color: Theme.accent
                scale: addMouse.pressed ? 0.95 : 1.0
                opacity: addMouse.containsMouse ? 0.9 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: 120 } }

                Text {
                    id: addLbl
                    anchors.centerIn: parent
                    text: root.editorOpen ? "Close" : "+ Add Keybind"
                    color: Theme.accentFg
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: addMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.editorOpen) {
                            root.editorOpen = false;
                            root.listeningKey = false;
                            root.modPickerOpen = false;
                        } else {
                            root.openNewEditor(root.selectedCategory === "all" ? "island" : root.selectedCategory);
                        }
                    }
                }
            }
        }
    }

    // ==================== MINIMALIST BINDING EDITOR (SELECT BOXES) ====================
    Rectangle {
        id: editorCard
        Layout.fillWidth: true
        implicitHeight: root.editorOpen ? editorCol.implicitHeight : 0
        opacity: root.editorOpen ? 1.0 : 0.0
        visible: implicitHeight > 2
        clip: true
        radius: 12
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle

        Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: editorCol
            width: parent.width
            spacing: 0

            // Row 1: Category & Action Select Boxes
            Item {
                Layout.fillWidth: true
                implicitHeight: Math.max(58, row1Layout.implicitHeight + 20)

                RowLayout {
                    id: row1Layout
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: root.editingBindId !== "" ? "Edit Action" : "Action"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Choose category and target"
                            color: Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    // Category Select Box
                    Rectangle {
                        id: catSelectBox
                        height: 30
                        implicitWidth: Math.max(132, catSelLbl.implicitWidth + 30)
                        radius: 8
                        color: catSelM.containsMouse ? Theme.cardHover : Theme.surfaceRaised
                        border.width: 1; border.color: Theme.borderSubtle
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                            Text {
                                id: catSelLbl
                                Layout.fillWidth: true
                                text: root.categoryLabel(root.editorTab)
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text { text: "▾"; color: Theme.textMuted; font.pixelSize: 11 }
                        }
                        MouseArea {
                            id: catSelM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const cats = [
                                    { key: "island",     label: "Dynamic Island" },
                                    { key: "screenshot", label: "Screenshot" },
                                    { key: "apps",       label: "Open App (.desktop)" },
                                    { key: "window",     label: "Window & Workspace" },
                                    { key: "command",    label: "Custom Command" }
                                ];
                                const opts = cats.map(c => ({
                                    text: c.label,
                                    checked: c.key === root.editorTab,
                                    action: () => {
                                        root.editorTab = c.key;
                                        root.applyDefaultActionForTab(c.key);
                                    }
                                }));
                                root.openMenuFor(catSelectBox, opts, 190);
                            }
                        }
                    }

                    // Target Action Select Box (for preset / .desktop apps)
                    Rectangle {
                        id: actSelectBox
                        visible: root.editorTab !== "command"
                        height: 30
                        implicitWidth: Math.min(220, Math.max(150, actSelLbl.implicitWidth + 30))
                        radius: 8
                        color: actSelM.containsMouse ? Theme.cardHover : Theme.surfaceRaised
                        border.width: 1; border.color: Theme.borderSubtle
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                            Text {
                                id: actSelLbl
                                Layout.fillWidth: true
                                text: root.selectedTitle !== "" ? root.selectedTitle : "Select action..."
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text { text: "▾"; color: Theme.textMuted; font.pixelSize: 11 }
                        }
                        MouseArea {
                            id: actSelM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                let opts = [];
                                if (root.editorTab === "island") {
                                    opts = KeybindService.islandActions.map(a => {
                                        const lua = 'hl.dsp.exec_cmd("' + a.cmd.replace(/"/g, '\\"') + '")';
                                        return {
                                            text: a.label,
                                            checked: root.selectedActionLua === lua,
                                            action: () => root.selectPresetAction("island", a.label, a.desc, lua, a.cmd, a.opts || "")
                                        };
                                    });
                                } else if (root.editorTab === "screenshot") {
                                    opts = KeybindService.screenshotActions.map(a => {
                                        const lua = 'hl.dsp.exec_cmd("' + a.cmd.replace(/"/g, '\\"') + '")';
                                        return {
                                            text: a.label,
                                            checked: root.selectedActionLua === lua,
                                            action: () => root.selectPresetAction("screenshot", a.label, a.desc, lua, a.cmd, a.opts || "")
                                        };
                                    });
                                } else if (root.editorTab === "window") {
                                    opts = KeybindService.windowActions.map(a => ({
                                        text: a.label,
                                        checked: root.selectedActionLua === a.lua,
                                        action: () => root.selectPresetAction("window", a.label, a.desc, a.lua, "", "")
                                    }));
                                } else if (root.editorTab === "apps") {
                                    opts = root.desktopApps.map(app => ({
                                        text: app.name,
                                        checked: root.selectedAppId === app.id,
                                        action: () => root.selectDesktopApp(app)
                                    }));
                                }
                                root.openMenuFor(actSelectBox, opts, 230);
                            }
                        }
                    }

                    // Custom Command Input (only when editorTab === "command")
                    TextField {
                        visible: root.editorTab === "command"
                        Layout.preferredWidth: 220
                        implicitHeight: 30
                        placeholderText: "e.g. kitty, playerctl play-pause"
                        placeholderTextColor: Theme.textMuted
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        text: root.customCmdInput
                        onTextChanged: root.customCmdInput = text
                        Keys.onEscapePressed: (event) => {
                            focus = false;
                            event.accepted = true;
                        }
                        background: Rectangle {
                            radius: 8
                            color: Theme.surfaceRaised
                            border.width: 1
                            border.color: parent.activeFocus ? Theme.accent : Theme.borderSubtle
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

            // Row 2: Modifiers Multi-Select + Key Recorder
            FocusScope {
                id: keyCaptureScope
                Layout.fillWidth: true
                implicitHeight: Math.max(58, row2Col.implicitHeight + 20)

                Keys.onPressed: (event) => {
                    if (!root.listeningKey) return;
                    const mapped = root.mapQtKeyToHypr(event);
                    if (event.modifiers & Qt.MetaModifier) root.modSuper = true;
                    if (event.modifiers & Qt.ControlModifier) root.modCtrl = true;
                    if (event.modifiers & Qt.AltModifier) root.modAlt = true;
                    if (event.modifiers & Qt.ShiftModifier) root.modShift = true;
                    if (mapped !== "") {
                        root.recordedKey = mapped;
                        event.accepted = true;
                    }
                }

                ColumnLayout {
                    id: row2Col
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: "Key Combination"
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.listeningKey ? "Listening — press any key on keyboard" : "Click key box to record or pick"
                                color: root.listeningKey ? Theme.accent : Theme.textSub
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        // Multi-Select Modifiers Box
                        Rectangle {
                            id: modSelectBox
                            height: 30
                            implicitWidth: Math.max(128, modSelLbl.implicitWidth + 30)
                            radius: 8
                            color: modSelM.containsMouse ? Theme.cardHover : Theme.surfaceRaised
                            border.width: 1
                            border.color: root.modPickerOpen ? Theme.accent : Theme.borderSubtle
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                                Text {
                                    id: modSelLbl
                                    Layout.fillWidth: true
                                    text: root.modifiersSummary()
                                    color: Theme.text
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                Text { text: "▾"; color: Theme.textMuted; font.pixelSize: 11 }
                            }
                            MouseArea {
                                id: modSelM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.modPickerOpen = !root.modPickerOpen
                            }
                        }

                        // Key Capture + Quick Key Select Box
                        Rectangle {
                            id: keySelectBox
                            height: 30
                            implicitWidth: 144
                            radius: 8
                            color: root.listeningKey ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10) : Theme.surfaceRaised
                            border.width: 1
                            border.color: root.listeningKey ? Theme.accent : Theme.borderSubtle
                            Behavior on color { ColorAnimation { duration: 130 } }
                            Behavior on border.color { ColorAnimation { duration: 130 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 6; spacing: 4
                                Text {
                                    Layout.fillWidth: true
                                    text: root.recordedKey !== "" ? root.prettyKeyLabel(root.recordedKey) : "Press key..."
                                    color: root.recordedKey !== "" ? Theme.text : Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.listeningKey = true;
                                            root.modPickerOpen = false;
                                            keyCaptureScope.forceActiveFocus();
                                        }
                                    }
                                }
                                Rectangle {
                                    width: 22; height: 22; radius: 5
                                    color: kPickM.containsMouse ? Theme.cardHover : "transparent"
                                    Text { anchors.centerIn: parent; text: "▾"; color: Theme.textMuted; font.pixelSize: 11 }
                                    MouseArea {
                                        id: kPickM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const commonKeys = ["space", "Return", "Escape", "Print", "Tab", "left", "right", "up", "down"];
                                            const opts = commonKeys.map(k => ({
                                                text: root.prettyKeyLabel(k),
                                                checked: root.recordedKey === k,
                                                action: () => { root.recordedKey = k; }
                                            }));
                                            root.openMenuFor(keySelectBox, opts, 150);
                                        }
                                    }
                                }
                            }
                        }

                        // "+" Stage Shortcut button
                        Rectangle {
                            width: 30; height: 30; radius: 8
                            color: stgM.containsMouse && root.recordedKey !== "" ? Theme.cardHover : Theme.surfaceRaised
                            border.width: 1; border.color: Theme.borderSubtle
                            opacity: root.recordedKey !== "" ? 1.0 : 0.45
                            scale: (stgM.pressed && root.recordedKey !== "") ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
                            Text { anchors.centerIn: parent; text: "+"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.Medium }
                            MouseArea {
                                id: stgM
                                anchors.fill: parent
                                enabled: root.recordedKey !== ""
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.stageCurrentDraft()
                            }
                        }
                    }

                    // Inline Multi-Select Modifier Checklist (smoothly expands when clicked)
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: root.modPickerOpen ? 36 : 0
                        opacity: root.modPickerOpen ? 1.0 : 0.0
                        visible: implicitHeight > 2
                        clip: true
                        radius: 8
                        color: Theme.surfaceRaised
                        border.width: 1; border.color: Theme.borderSubtle
                        Behavior on implicitHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 140 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 10
                            spacing: 14

                            Repeater {
                                model: [
                                    { key: "super", label: "SUPER", on: root.modSuper },
                                    { key: "ctrl",  label: "CTRL",  on: root.modCtrl },
                                    { key: "alt",   label: "ALT",   on: root.modAlt },
                                    { key: "shift", label: "SHIFT", on: root.modShift }
                                ]
                                delegate: Row {
                                    required property var modelData
                                    spacing: 6
                                    Rectangle {
                                        width: 16; height: 16; radius: 4
                                        color: modelData.on ? Theme.accent : "transparent"
                                        border.width: 1
                                        border.color: modelData.on ? Theme.accent : Theme.textMuted
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text {
                                            anchors.centerIn: parent
                                            visible: modelData.on
                                            text: "✓"
                                            color: Theme.accentFg
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                        }
                                    }
                                    Text {
                                        text: modelData.label
                                        color: Theme.text
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.key === "super") root.modSuper = !root.modSuper;
                                            else if (modelData.key === "ctrl") root.modCtrl = !root.modCtrl;
                                            else if (modelData.key === "alt") root.modAlt = !root.modAlt;
                                            else if (modelData.key === "shift") root.modShift = !root.modShift;
                                            keyCaptureScope.forceActiveFocus();
                                        }
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

            // Row 3: Staged Shortcuts + Conflict + Save/Cancel
            Item {
                Layout.fillWidth: true
                implicitHeight: Math.max(52, row3Layout.implicitHeight + 18)

                RowLayout {
                    id: row3Layout
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 9
                    anchors.bottomMargin: 9
                    spacing: 10

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: root.stagedCombos
                            delegate: KeycapChipGroup {
                                required property var modelData
                                required property int index
                                comboText: modelData.combo
                                editable: true
                                onRemoveClicked: {
                                    const copy = root.stagedCombos.slice();
                                    copy.splice(index, 1);
                                    root.stagedCombos = copy;
                                }
                            }
                        }

                        readonly property var conflictInfo: root.recordedKey !== ""
                            ? KeybindService.findConflict(root.currentDraftCombo(), root.editingBindId, -1)
                            : null

                        Text {
                            visible: parent.conflictInfo !== null
                            text: parent.conflictInfo ? ("Conflict: " + parent.conflictInfo.title) : ""
                            color: Theme.warn
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            height: 28
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Rectangle {
                        height: 30; implicitWidth: 72; radius: 8
                        color: canM.containsMouse ? Theme.cardHover : Theme.surfaceRaised
                        border.width: 1; border.color: Theme.borderSubtle
                        scale: canM.pressed ? 0.95 : 1.0
                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
                        Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold }
                        MouseArea {
                            id: canM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.editorOpen = false;
                                root.listeningKey = false;
                                root.modPickerOpen = false;
                            }
                        }
                    }

                    Rectangle {
                        readonly property bool canSave: (root.recordedKey !== "" || root.stagedCombos.length > 0) &&
                            (root.editorTab === "command" ? root.customCmdInput.trim() !== "" : root.selectedActionLua !== "")
                        height: 30; implicitWidth: 88; radius: 8
                        color: Theme.accent
                        opacity: canSave ? (savM.containsMouse ? 0.9 : 1.0) : 0.4
                        scale: (savM.pressed && canSave) ? 0.95 : 1.0
                        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        Text { anchors.centerIn: parent; text: "Save"; color: Theme.accentFg; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold }
                        MouseArea {
                            id: savM
                            anchors.fill: parent
                            enabled: parent.canSave
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.commitEditor()
                        }
                    }
                }
            }
        }
    }

    // ==================== CATEGORY PILLS & SEARCH ====================
    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: [
                { key: "all",        label: "All" },
                { key: "island",     label: "Dynamic Island" },
                { key: "screenshot", label: "Screenshot" },
                { key: "apps",       label: "Apps" },
                { key: "window",     label: "Windows" },
                { key: "command",    label: "Commands" }
            ]
            delegate: Rectangle {
                required property var modelData
                readonly property bool active: root.selectedCategory === modelData.key
                readonly property int count: KeybindService.categoryCounts[modelData.key] || 0
                height: 28
                implicitWidth: catRow.implicitWidth + 18
                radius: 8
                color: active ? Theme.accent : (catM.containsMouse ? Theme.cardHover : Theme.cardBg)
                border.width: 1
                border.color: active ? Theme.accent : Theme.borderSubtle
                scale: catM.pressed ? 0.95 : 1.0
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                Row {
                    id: catRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: modelData.label
                        color: active ? Theme.accentFg : Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: active ? Font.DemiBold : Font.Medium
                    }
                    Text {
                        text: count
                        color: active ? Theme.accentFg : Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        opacity: active ? 0.8 : 1.0
                    }
                }
                MouseArea {
                    id: catM
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectedCategory = modelData.key
                }
            }
        }
    }

    TextField {
        Layout.fillWidth: true
        implicitHeight: 34
        placeholderText: "Filter keybinds by action, app, or key..."
        placeholderTextColor: Theme.textMuted
        color: Theme.text
        font.family: Theme.fontSans
        font.pixelSize: 12
        text: root.searchQuery
        onTextChanged: root.searchQuery = text
        Keys.onEscapePressed: (event) => {
            focus = false;
            event.accepted = true;
        }
        background: Rectangle {
            radius: 10
            color: Theme.cardBg
            border.width: 1
            border.color: parent.activeFocus ? Theme.accent : Theme.borderSubtle
        }
    }

    // ==================== CATEGORIZED KEYBIND LIST ====================
    Repeater {
        model: root.visibleCategories()
        delegate: ColumnLayout {
            required property string modelData
            readonly property string catKey: modelData
            readonly property var items: root.bindsForCategory(catKey)
            readonly property var meta: KeybindService.categoryMeta[catKey] || { label: catKey, desc: "" }

            Layout.fillWidth: true
            spacing: 6
            visible: items.length > 0

            Text {
                Layout.topMargin: 4
                text: meta.label
                color: Theme.textSub
                font.family: Theme.fontSans
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: catListCol.implicitHeight
                radius: 12
                clip: true
                color: Theme.cardBg
                border.width: 1
                border.color: Theme.borderSubtle

                ColumnLayout {
                    id: catListCol
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: items
                        delegate: Item {
                            id: bindRow
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            implicitHeight: Math.max(54, rowContent.implicitHeight + 20)

                            Rectangle {
                                visible: index > 0
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 1
                                color: Theme.borderSubtle
                            }

                            RowLayout {
                                id: rowContent
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                anchors.topMargin: 10
                                anchors.bottomMargin: 10
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 140
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: bindRow.modelData.title
                                        color: Theme.text
                                        font.family: Theme.fontSans
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: bindRow.modelData.subtitle
                                        color: Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }

                                Flow {
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    Layout.maximumWidth: 340
                                    spacing: 6

                                    Repeater {
                                        model: bindRow.modelData.combos || []
                                        delegate: KeycapChipGroup {
                                            required property var modelData
                                            required property int index
                                            comboText: modelData.combo
                                            editable: !bindRow.modelData.readOnly
                                            onClicked: root.openEditBind(bindRow.modelData, false)
                                            onRemoveClicked: KeybindService.removeComboFromBind(bindRow.modelData.id, index)
                                        }
                                    }

                                    Rectangle {
                                        visible: !bindRow.modelData.readOnly
                                        height: 28
                                        implicitWidth: 28
                                        radius: 8
                                        color: pkMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised
                                        border.width: 1; border.color: Theme.borderSubtle
                                        scale: pkMouse.pressed ? 0.93 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutBack } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "+"
                                            color: Theme.textSub
                                            font.family: Theme.fontSans
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                        }
                                        MouseArea {
                                            id: pkMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openEditBind(bindRow.modelData, true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
