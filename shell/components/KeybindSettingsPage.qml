import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../services"
import "common"

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 10

    property string selectedCategory: "all"
    property string searchQuery: ""
    property bool systemExpanded: false
    property bool confirmReset: false

    signal editRequested(var bindObj, int comboIndex, string defaultTab)

    onVisibleChanged: {
        if (visible && !KeybindService.busy) {
            KeybindService.refresh();
        }
    }

    Timer {
        id: resetConfirmTimer
        interval: 4000
        onTriggered: root.confirmReset = false
    }

    function iconColorFor(catKey) {
        const a = Theme.accent;
        const t = Theme.text;
        if (a.hslSaturation < 0.08) {
            if (catKey === "island" || catKey === "window") return t;
            if (catKey === "screenshot" || catKey === "apps") return Qt.rgba(t.r, t.g, t.b, 0.88);
            return Theme.textSub;
        }
        const s = Math.min(0.45, Math.max(0.24, a.hslSaturation * 0.88));
        if (catKey === "island") return a;
        if (catKey === "screenshot") return Qt.hsla((a.hslHue + 0.08) % 1.0, s, 0.76, 1.0);
        if (catKey === "apps") return Qt.hsla((a.hslHue + 0.16) % 1.0, s, 0.76, 1.0);
        if (catKey === "window") return Qt.hsla((a.hslHue + 0.24) % 1.0, s, 0.76, 1.0);
        return Qt.rgba(t.r, t.g, t.b, 0.78);
    }

    function iconNameForBind(bindObj) {
        if (!bindObj) return "terminal";
        if (bindObj.id === "builtin_ws_loop") return "grid";
        if (bindObj.id === "builtin_mouse_drag") return "edit";
        if (bindObj.id === "builtin_super_tap") return "bolt";
        const title = (bindObj.title || "").toLowerCase();
        const cmd = (bindObj.command || "").toLowerCase();
        if (cmd.indexOf("playerctl") !== -1) return "music";
        if (cmd.indexOf("wpctl") !== -1 || title.indexOf("volume") !== -1 || title.indexOf("mute") !== -1) return "volume";
        if (title.indexOf("brightness") !== -1) return "sun";
        if (title.indexOf("recording") !== -1) return "video";
        if (title.indexOf("clipboard") !== -1) return "clipboard";
        if (title.indexOf("terminal") !== -1) return "terminal";
        const meta = KeybindService.categoryMeta[bindObj.category];
        return meta ? meta.iconName : "terminal";
    }

    function matchesQuery(bindObj) {
        const q = root.searchQuery.trim().toLowerCase();
        if (q === "") return true;
        const comboText = (bindObj.combos || []).map(c => c.combo).join(" ").toLowerCase();
        const hay = ((bindObj.title || "") + " " + (bindObj.subtitle || "") + " " + (bindObj.command || "") + " " + comboText).toLowerCase();
        return hay.indexOf(q) !== -1;
    }

    function visibleCategories() {
        if (root.selectedCategory === "all") return KeybindService.categoryOrder;
        return [root.selectedCategory];
    }

    function coreBindsForCategory(cat) {
        const out = [];
        const all = KeybindService.binds || [];
        for (let i = 0; i < all.length; ++i) {
            const b = all[i];
            if (!b || b.category !== cat || b.groupTier === "system") continue;
            if (!matchesQuery(b)) continue;
            out.push(b);
        }
        return out;
    }

    readonly property var systemItems: {
        const out = [];
        const all = KeybindService.binds || [];
        for (let i = 0; i < all.length; ++i) {
            const b = all[i];
            if (!b || b.groupTier !== "system") continue;
            if (root.selectedCategory !== "all" && b.category !== root.selectedCategory) continue;
            if (!matchesQuery(b)) continue;
            out.push(b);
        }
        return out;
    }

    readonly property int totalVisibleCount: {
        let n = root.systemItems.length;
        const cats = visibleCategories();
        for (let i = 0; i < cats.length; ++i) {
            n += coreBindsForCategory(cats[i]).length;
        }
        return n;
    }

    // Shared Bind Row Component (Core & System/Hardware tiers)
    component BindRow: Item {
        id: rowItem
        property var bindData: ({})
        property bool showDivider: false
        readonly property bool isRo: Boolean(bindData.readOnly)

        Layout.fillWidth: true
        implicitHeight: Math.max(50, rowLayout.implicitHeight + 16)
        clip: true

        Rectangle {
            anchors.fill: parent
            color: (!rowItem.isRo && rowMouse.containsMouse) ? Theme.cardHover : "transparent"
            scale: (!rowItem.isRo && rowMouse.pressed) ? 0.99 : 1.0
            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !rowItem.isRo
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.editRequested(rowItem.bindData, -1, "")
            }
        }

        Rectangle {
            visible: rowItem.showDivider
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.borderSubtle
        }

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 10

            Rectangle {
                width: 28
                height: 28
                radius: 8
                color: Theme.surfaceRaised
                border.width: 1
                border.color: Theme.borderSubtle
                Layout.alignment: Qt.AlignVCenter

                SvgIcon {
                    anchors.centerIn: parent
                    sourceName: root.iconNameForBind(rowItem.bindData)
                    iconSize: 14
                    color: root.iconColorFor(rowItem.bindData.category || "command")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: rowItem.bindData.title || ""
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                Text {
                    visible: (rowItem.bindData.subtitle || "") !== ""
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: rowItem.bindData.subtitle || ""
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Flow {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                Layout.maximumWidth: Math.max(116, Math.min(276, root.width * 0.48))
                spacing: 5

                Repeater {
                    model: rowItem.bindData.combos || []
                    delegate: Rectangle {
                        id: chipRect
                        required property var modelData
                        required property int index
                        readonly property var parts: KeybindService.splitComboParts(modelData.combo)
                        readonly property string flagTag: modelData.locked && modelData.repeating
                            ? "LOCK • HOLD"
                            : (modelData.locked ? "LOCK" : (modelData.repeating ? "HOLD" : ""))

                        height: 26
                        implicitWidth: chipRow.implicitWidth + 14
                        radius: 7
                        clip: true
                        color: (!rowItem.isRo && chipMouse.containsMouse) ? Theme.cardHover : Theme.surfaceRaised
                        border.width: 1
                        border.color: (!rowItem.isRo && chipMouse.containsMouse)
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                            : Theme.borderSubtle
                        scale: (!rowItem.isRo && chipMouse.pressed) ? 0.95 : 1.0
                        Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 4

                            Repeater {
                                model: chipRect.parts
                                delegate: Row {
                                    required property string modelData
                                    required property int index
                                    spacing: 4

                                    Text {
                                        visible: index > 0
                                        text: "+"
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: KeybindService.prettyKeyLabel(modelData)
                                        color: KeybindService.isModPart(modelData) ? Theme.text : Theme.textSub
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        font.weight: KeybindService.isModPart(modelData) ? Font.DemiBold : Font.Medium
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            Text {
                                visible: chipRect.flagTag !== ""
                                text: "• " + chipRect.flagTag
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 9
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !rowItem.isRo
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: (mouse) => {
                                mouse.accepted = true;
                                root.editRequested(rowItem.bindData, index, "");
                            }
                        }
                    }
                }
            }
        }
    }

    // ==================== 1. SINGLE-ROW ACTION TOOLBAR ====================
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            height: 34
            radius: 9
            clip: true
            color: Theme.cardBg
            border.width: 1
            border.color: searchInput.activeFocus ? Theme.accent : Theme.borderSubtle
            Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 7

                SvgIcon {
                    sourceName: "search"
                    iconSize: 14
                    color: Theme.textSub
                }

                AnimatedTextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    textColor: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    clip: true
                    onTextChanged: root.searchQuery = text
                    Keys.onEscapePressed: (event) => {
                        if (text !== "") {
                            text = "";
                        } else {
                            focus = false;
                        }
                        event.accepted = true;
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Filter shortcuts, apps, or keys..."
                        color: Theme.textMuted
                        font: searchInput.font
                        visible: searchInput.text.length === 0
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    visible: searchInput.text.length > 0
                    width: 20
                    height: 20
                    radius: 5
                    color: clrM.containsMouse ? Theme.cardHover : "transparent"
                    scale: clrM.pressed ? 0.9 : 1.0
                    Behavior on color { ColorAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

                    SvgIcon {
                        anchors.centerIn: parent
                        sourceName: "close"
                        iconSize: 11
                        color: clrM.containsMouse ? Theme.text : Theme.textMuted
                    }
                    MouseArea {
                        id: clrM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: searchInput.text = ""
                    }
                }
            }
        }

        // Reload button
        Rectangle {
            height: 34
            implicitWidth: reloadRow.implicitWidth + 18
            radius: 8
            clip: true
            color: relM.containsMouse ? Theme.cardHover : Theme.surfaceRaised
            border.width: 1
            border.color: relM.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : Theme.borderSubtle
            scale: relM.pressed ? 0.95 : 1.0
            Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

            RowLayout {
                id: reloadRow
                anchors.centerIn: parent
                spacing: 6
                SvgIcon { sourceName: "refresh"; iconSize: 13; color: Theme.textSub }
                Text {
                    text: "Reload"
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }

            MouseArea {
                id: relM
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    KeybindService.refresh();
                    KeybindService.reloadHyprland();
                }
            }
        }

        // Add Shortcut button
        Rectangle {
            height: 34
            implicitWidth: addLbl.implicitWidth + 22
            radius: 8
            clip: true
            color: Theme.accent
            opacity: addM.containsMouse ? 0.88 : 1.0
            scale: addM.pressed ? 0.95 : 1.0
            Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

            Text {
                id: addLbl
                anchors.centerIn: parent
                text: "+ Add"
                color: Theme.accentFg
                font.family: Theme.fontSans
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            MouseArea {
                id: addM
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.editRequested(null, -1, root.selectedCategory === "all" ? "island" : root.selectedCategory)
            }
        }
    }

    // ==================== 2. ANIMATED STATUS + UNDO BANNER ====================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: KeybindService.statusText !== "" ? 34 : 0
        opacity: KeybindService.statusText !== "" ? 1.0 : 0.0
        visible: implicitHeight > 1 || opacity > 0.01
        radius: 9
        clip: true
        color: KeybindService.statusOk
            ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.12)
            : Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.14)
        border.width: 1
        border.color: KeybindService.statusOk
            ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.40)
            : Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.45)
        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            spacing: 8

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: KeybindService.statusText
                color: KeybindService.statusOk ? Theme.ok : Theme.dangerText
                font.family: Theme.fontSans
                font.pixelSize: 11
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Rectangle {
                visible: KeybindService.canUndo && KeybindService.statusOk
                height: 22
                implicitWidth: undoLbl.implicitWidth + 14
                radius: 6
                color: undoM.containsMouse ? Theme.cardHover : Theme.surfaceRaised
                border.width: 1
                border.color: Theme.borderSubtle
                scale: undoM.pressed ? 0.94 : 1.0
                Behavior on color { ColorAnimation { duration: 110 } }
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

                Text {
                    id: undoLbl
                    anchors.centerIn: parent
                    text: "Undo"
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: undoM
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: KeybindService.undoLastChange()
                }
            }
        }
    }

    // ==================== 3. CATEGORY FILTER PILLS ====================
    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: [
                { key: "all",        label: "All" },
                { key: "island",     label: "Island" },
                { key: "screenshot", label: "Capture" },
                { key: "apps",       label: "Apps" },
                { key: "window",     label: "Window" },
                { key: "command",    label: "Custom" }
            ]
            delegate: Rectangle {
                required property var modelData
                readonly property bool active: root.selectedCategory === modelData.key
                readonly property int count: KeybindService.categoryCounts[modelData.key] || 0

                height: 28
                implicitWidth: catRow.implicitWidth + 16
                radius: 8
                clip: true
                color: active ? Theme.accent : (catM.containsMouse ? Theme.cardHover : Theme.cardBg)
                border.width: 1
                border.color: active ? Theme.accent : Theme.borderSubtle
                scale: catM.pressed ? 0.95 : 1.0
                Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                Row {
                    id: catRow
                    anchors.centerIn: parent
                    spacing: 5

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

    // ==================== 4. CORE SHORTCUT GROUPS ====================
    Repeater {
        model: root.visibleCategories()
        delegate: ColumnLayout {
            required property string modelData
            readonly property string catKey: modelData
            readonly property var items: root.coreBindsForCategory(catKey)
            readonly property var meta: KeybindService.categoryMeta[catKey] || { label: catKey }

            Layout.fillWidth: true
            spacing: 6
            visible: items.length > 0

            Text {
                Layout.topMargin: 2
                text: meta.label.toUpperCase()
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 0.6
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: catCol.implicitHeight
                radius: 12
                clip: true
                color: Theme.cardBg
                border.width: 1
                border.color: Theme.borderSubtle

                ColumnLayout {
                    id: catCol
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: items
                        delegate: BindRow {
                            required property var modelData
                            required property int index
                            bindData: modelData
                            showDivider: index > 0
                        }
                    }
                }
            }
        }
    }

    // ==================== 5. COLLAPSIBLE SYSTEM & HARDWARE KEYS ====================
    Rectangle {
        id: sysCard
        readonly property bool isExpanded: root.systemExpanded || root.searchQuery.trim() !== ""
        visible: root.systemItems.length > 0
        Layout.fillWidth: true
        Layout.topMargin: 2
        implicitHeight: sysHeader.height + (isExpanded ? sysBodyCol.implicitHeight : 0)
        radius: 12
        clip: true
        color: Theme.cardBg
        border.width: 1
        border.color: sysHeadM.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Rectangle {
            id: sysHeader
            width: parent.width
            height: 48
            color: sysHeadM.containsMouse ? Theme.cardHover : "transparent"
            scale: sysHeadM.pressed ? 0.99 : 1.0
            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Rectangle {
                    width: 28
                    height: 28
                    radius: 8
                    color: Theme.surfaceRaised
                    border.width: 1
                    border.color: Theme.borderSubtle
                    SvgIcon {
                        anchors.centerIn: parent
                        sourceName: "settings"
                        iconSize: 14
                        color: Theme.textSub
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "System & Hardware Keys"
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: "Workspaces, mouse drag, Super tap & media keys"
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Text {
                    text: root.systemItems.length + " keys"
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }

                SvgIcon {
                    sourceName: "chevron-right"
                    iconSize: 14
                    color: Theme.textMuted
                    rotation: sysCard.isExpanded ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
            }

            MouseArea {
                id: sysHeadM
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.systemExpanded = !root.systemExpanded
            }
        }

        ColumnLayout {
            id: sysBodyCol
            y: sysHeader.height
            width: parent.width
            spacing: 0
            opacity: sysCard.isExpanded ? 1.0 : 0.0
            visible: sysCard.isExpanded || opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Repeater {
                model: root.systemItems
                delegate: BindRow {
                    required property var modelData
                    required property int index
                    bindData: modelData
                    showDivider: true
                }
            }
        }
    }

    // ==================== 6. EMPTY SEARCH STATE ====================
    Rectangle {
        visible: root.totalVisibleCount === 0
        Layout.fillWidth: true
        implicitHeight: emptyCol.implicitHeight + 28
        radius: 12
        clip: true
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle

        ColumnLayout {
            id: emptyCol
            anchors.centerIn: parent
            spacing: 8

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "No matching shortcuts"
                color: Theme.textSub
                font.family: Theme.fontSans
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            PillButton {
                Layout.alignment: Qt.AlignHCenter
                text: "Clear Filter"
                fixedHeight: 28
                radius: 8
                onClicked: {
                    searchInput.text = "";
                    root.searchQuery = "";
                    root.selectedCategory = "all";
                }
            }
        }
    }

    // ==================== 7. QUIET FOOTER ====================
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 10

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: "~/.config/hypr/config/binds.lua • " + KeybindService.totalComboCount + " binds"
            color: Theme.textMuted
            font.family: Theme.fontMono
            font.pixelSize: 10
            elide: Text.ElideMiddle
        }

        Rectangle {
            height: 28
            implicitWidth: rstRow.implicitWidth + 16
            radius: 7
            clip: true
            color: root.confirmReset
                ? Theme.danger
                : (rstM.containsMouse ? Theme.cardHover : Theme.surfaceRaised)
            border.width: 1
            border.color: root.confirmReset
                ? Theme.danger
                : (rstM.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.45) : Theme.borderSubtle)
            scale: rstM.pressed ? 0.95 : 1.0
            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

            RowLayout {
                id: rstRow
                anchors.centerIn: parent
                spacing: 5
                SvgIcon {
                    sourceName: "restore"
                    iconSize: 12
                    color: root.confirmReset ? "#ffffff" : Theme.textSub
                }
                Text {
                    text: root.confirmReset ? "Confirm Reset?" : "Reset Defaults"
                    color: root.confirmReset ? "#ffffff" : Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    font.weight: root.confirmReset ? Font.DemiBold : Font.Medium
                }
            }

            MouseArea {
                id: rstM
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!root.confirmReset) {
                        root.confirmReset = true;
                        resetConfirmTimer.restart();
                    } else {
                        resetConfirmTimer.stop();
                        root.confirmReset = false;
                        KeybindService.resetToDefaults();
                    }
                }
            }
        }
    }
}
