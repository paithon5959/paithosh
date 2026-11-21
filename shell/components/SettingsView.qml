import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."
import "common"

Item {
    id: root
    implicitWidth: 860
    implicitHeight: 540

    property var shellState: null
    property string currentPage: "home"
    property string searchQuery: ""
    property bool systemOpen: true
    property bool networkOpen: false
    property bool personalizationOpen: false

    // Shared UI state matching settings.html
    property string activeThemePreset: "OLED Pure"
    property int quickVolume: 72
    property bool nightLight: false
    property string powerMode: "Balanced"
    property bool dndEnabled: false

    // Display
    property string displayScale: "125% (Recommended)"
    property string displayRes: "2560 × 1600 (Recommended)"
    property string displayOrient: "Landscape"
    property bool rotationLock: true

    // Sound
    property bool soundMute: true

    // Updates
    property var updateChecks: [true, true, true, true]
    readonly property int selectedUpdateCount: {
        let c = 0;
        for (let i = 0; i < updateChecks.length; ++i) if (updateChecks[i]) c++;
        return c;
    }

    // Network / Wi-Fi / VPN
    property bool wifiRadio: true
    property bool airplaneMode: false
    property string dnsProvider: "Cloudflare (1.1.1.1)"
    property bool meteredConn: false
    property string connectedSsid: "Paithon_5G"
    property bool vpnActive: false
    property string vpnEndpoint: "wg.paithon.dev:51820"
    property string vpnDns: "1.1.1.1"
    property bool vpnAutostart: true
    property bool vpnKillSwitch: false

    // Personalization / Island / Hyprland / Layouts / Decoration / Fonts / Animations
    property bool islandAutoHide: false
    property bool kawaseBlur: true
    property string globalSurfaceTheme: "OLED Pure"
    property bool activeBorderHighlight: true
    property string islandCornerRadius: "26px (Default)"
    property bool topEdgeOffset: true
    property bool hideBarFullscreen: false
    property string windowGapsPreset: "Balanced (6 / 12)"
    property bool blurBezierGlobal: true
    property string activeLayout: "dwindle"
    property int masterRatio: 55
    property bool preserveSplit: true
    property int cornerRounding: 14
    property int borderSize: 2
    property int activeOpacity: 100
    property int shadowRange: 24
    property string activeBorderHex: "#e8e8e8"
    property bool dropShadow: true
    property bool dimInactive: false
    property bool blurBehindIsland: true
    property bool zeroDeadAnims: true

    // Colors & Fonts
    property string accentMode: "Solid"
    property real hueVal: 0.0
    property real satVal: 0.0
    property real valVal: 0.92
    property int gradientAngle: 135

    // Themes
    property bool exportIncHypr: true
    property bool exportIncPalette: true
    property string themeExportStatus: ""

    readonly property var navItems: [
        { key: "home", label: "Home", icon: "⌂", group: "", sub: false },
        { key: "system", label: "System", icon: "⚙", group: "system", sub: false, hasChildren: true },
        { key: "display", label: "Display", icon: "", group: "system", sub: true },
        { key: "sound", label: "Sound & Audio", icon: "", group: "system", sub: true },
        { key: "power", label: "Power & Battery", icon: "", group: "system", sub: true },
        { key: "updates", label: "Update Packages", icon: "", group: "system", sub: true },
        { key: "network", label: "Network & internet", icon: "◈", group: "network", sub: false, hasChildren: true },
        { key: "wifi", label: "Wi-Fi", icon: "", group: "network", sub: true },
        { key: "vpn", label: "VPN & Proxy", icon: "", group: "network", sub: true },
        { key: "personalization", label: "Personalization", icon: "✎", group: "personalization", sub: false, hasChildren: true },
        { key: "island", label: "Dynamic Island", icon: "", group: "personalization", sub: true },
        { key: "fonts", label: "Colors & Fonts", icon: "", group: "personalization", sub: true },
        { key: "hyprland", label: "Gaps & Borders", icon: "", group: "personalization", sub: true },
        { key: "layouts", label: "Layouts", icon: "", group: "personalization", sub: true },
        { key: "decoration", label: "Decoration", icon: "", group: "personalization", sub: true },
        { key: "animations", label: "Animations & Blur", icon: "", group: "personalization", sub: true },
        { key: "themes", label: "Import / Export Themes", icon: "", group: "personalization", sub: true },
        { key: "about", label: "About", icon: "ⓘ", group: "", sub: false }
    ]

    function isGroupOpen(group) {
        if (group === "system") return systemOpen;
        if (group === "network") return networkOpen;
        if (group === "personalization") return personalizationOpen;
        return true;
    }

    function toggleGroup(group) {
        if (group === "system") systemOpen = !systemOpen;
        else if (group === "network") networkOpen = !networkOpen;
        else if (group === "personalization") personalizationOpen = !personalizationOpen;
    }

    function openPage(pageKey) {
        if (currentPage === pageKey) return;
        currentPage = pageKey;
        if (["display", "sound", "power", "updates"].indexOf(pageKey) !== -1) systemOpen = true;
        if (["wifi", "vpn"].indexOf(pageKey) !== -1) networkOpen = true;
        if (["island", "fonts", "hyprland", "layouts", "decoration", "animations", "themes"].indexOf(pageKey) !== -1) personalizationOpen = true;
        pageInAnim.restart();
    }

    function matchesSearch(item) {
        if (searchQuery.trim() === "") return true;
        return item.label.toLowerCase().indexOf(searchQuery.trim().toLowerCase()) !== -1;
    }

    function toggleUpdateCheck(idx) {
        const next = updateChecks.slice();
        next[idx] = !next[idx];
        updateChecks = next;
    }

    // Inline reusable components matching settings.html CSS
    component SectionLabel: Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        font.family: Theme.fontSans
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: Theme.textMuted
        elide: Text.ElideRight
    }

    component SettingGroup: Rectangle {
        default property alias rows: groupCol.data
        Layout.fillWidth: true
        implicitHeight: groupCol.implicitHeight
        radius: 12
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle
        clip: true

        ColumnLayout {
            id: groupCol
            width: parent.width
            spacing: 0
        }
    }

    component SettingRow: Item {
        id: sRow
        property string iconChar: ""
        property string title: ""
        property string subtitle: ""
        property bool showDivider: true
        default property alias control: ctrlSlot.data

        Layout.fillWidth: true
        implicitHeight: Math.max(54, rowLayout.implicitHeight + 20)

        Rectangle {
            visible: sRow.showDivider
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.borderSubtle
        }

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 12

            Rectangle {
                visible: sRow.iconChar !== ""
                width: 30; height: 30; radius: 8
                color: Theme.surfaceRaised
                border.width: 1; border.color: Theme.borderSubtle
                Text {
                    anchors.centerIn: parent
                    text: sRow.iconChar
                    color: Theme.textSub
                    font.pixelSize: 13
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: sRow.title
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    visible: sRow.subtitle !== ""
                    Layout.fillWidth: true
                    text: sRow.subtitle
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: ctrlSlot
                spacing: 8
            }
        }
    }

    component HubCard: Rectangle {
        id: hCard
        property string iconChar: ""
        property string title: ""
        property string subtitle: ""
        property string pillText: ""
        signal triggered()

        Layout.fillWidth: true
        height: 62
        radius: 12
        color: hMouse.containsMouse ? Theme.cardHover : Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle
        Behavior on color { ColorAnimation { duration: 120 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            Rectangle {
                width: 32; height: 32; radius: 8
                color: Theme.surfaceRaised
                border.width: 1; border.color: Theme.borderSubtle
                Text { anchors.centerIn: parent; text: hCard.iconChar; color: Theme.text; font.pixelSize: 14 }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: hCard.title; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: hCard.subtitle; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
            }

            Rectangle {
                visible: hCard.pillText !== ""
                height: 24
                implicitWidth: pillLbl.implicitWidth + 18
                radius: 12
                color: Theme.surfaceRaised
                border.width: 1; border.color: Theme.borderSubtle
                Text { id: pillLbl; anchors.centerIn: parent; text: hCard.pillText; color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 10 }
            }

            Text { text: "›"; color: Theme.textMuted; font.pixelSize: 16 }
        }

        MouseArea {
            id: hMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hCard.triggered()
        }
    }

    component CtrlSwitch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled(bool nextVal)

        width: 38
        height: 22
        radius: 11
        color: checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
        border.width: 1
        border.color: checked ? Theme.accent : Theme.borderSubtle
        Behavior on color { ColorAnimation { duration: 150 } }

        Rectangle {
            width: 16; height: 16; radius: 8
            y: 3
            x: sw.checked ? 19 : 3
            color: sw.checked ? Theme.accentFg : Theme.text
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled(!sw.checked)
        }
    }

    component CtrlTickBox: Rectangle {
        id: tb
        property bool checked: false
        signal toggled(bool nextVal)

        width: 18
        height: 18
        radius: 5
        color: checked ? Theme.accent : "transparent"
        border.width: 1
        border.color: checked ? Theme.accent : Theme.textMuted
        Behavior on color { ColorAnimation { duration: 130 } }

        Text {
            anchors.centerIn: parent
            visible: tb.checked
            text: "✓"
            color: Theme.accentFg
            font.pixelSize: 11
            font.weight: Font.Bold
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.toggled(!tb.checked)
        }
    }

    component CtrlSlider: RowLayout {
        id: cSlider
        property real from: 0
        property real to: 100
        property real value: 50
        property string unit: "%"
        signal moved(real newVal)

        spacing: 8
        Slider {
            Layout.preferredWidth: 120
            from: cSlider.from
            to: cSlider.to
            value: cSlider.value
            onMoved: cSlider.moved(Math.round(value))
        }
        Text {
            Layout.preferredWidth: 42
            horizontalAlignment: Text.AlignRight
            text: Math.round(cSlider.value) + cSlider.unit
            color: Theme.textSub
            font.family: Theme.fontMono
            font.pixelSize: 11
        }
    }

    component CtrlSelect: Rectangle {
        id: cSel
        property var options: []
        property string currentText: ""
        signal selected(string val)

        height: 30
        implicitWidth: Math.max(126, selLbl.implicitWidth + 32)
        radius: 8
        color: selMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised
        border.width: 1
        border.color: Theme.borderSubtle

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 6
            Text {
                id: selLbl
                Layout.fillWidth: true
                text: cSel.currentText
                color: Theme.text
                font.family: Theme.fontSans
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            Text { text: "▾"; color: Theme.textMuted; font.pixelSize: 11 }
        }

        Menu {
            id: selMenu
            Repeater {
                model: cSel.options
                delegate: MenuItem {
                    required property string modelData
                    text: modelData
                    onTriggered: cSel.selected(modelData)
                }
            }
        }

        MouseArea {
            id: selMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: selMenu.popup()
        }
    }

    component CtrlBtn: Rectangle {
        id: cBtn
        property string text: ""
        property bool ghost: false
        signal clicked()

        height: 30
        implicitWidth: btnLbl.implicitWidth + 22
        radius: 8
        color: ghost ? (bMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised) : Theme.accent
        border.width: 1
        border.color: ghost ? Theme.borderSubtle : Theme.accent

        Text {
            id: btnLbl
            anchors.centerIn: parent
            text: cBtn.text
            color: cBtn.ghost ? Theme.text : Theme.accentFg
            font.family: Theme.fontSans
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: bMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cBtn.clicked()
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left Sidebar
        Rectangle {
            Layout.preferredWidth: 248
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
                spacing: 10

                // Profile Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        width: 34; height: 34; radius: 17
                        color: Theme.accent
                        Text { anchors.centerIn: parent; text: "P"; font.family: Theme.fontSans; font.pixelSize: 15; font.weight: Font.Bold; color: Theme.accentFg }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { Layout.fillWidth: true; text: "Paithon"; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: "paithon@hyprland"; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
                    }
                }

                // Search Box
                Rectangle {
                    Layout.fillWidth: true
                    height: 32; radius: 8
                    color: Theme.cardBg
                    border.width: 1
                    border.color: searchInput.activeFocus ? Theme.accent : Theme.borderSubtle
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                        Text { text: "⌕"; font.pixelSize: 13; color: Theme.textMuted }
                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.family: Theme.fontSans; font.pixelSize: 12; color: Theme.text; clip: true
                            onTextChanged: root.searchQuery = text
                            Text {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: "Find a setting"; font.family: Theme.fontSans; font.pixelSize: 12; color: Theme.textMuted
                                visible: searchInput.text.length === 0
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                // Tree Navigation List
                ListView {
                    id: navList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.navItems

                    delegate: Item {
                        id: navDelegate
                        required property var modelData
                        readonly property bool isVisible: {
                            if (root.searchQuery.trim() !== "") return root.matchesSearch(modelData);
                            if (!modelData.sub) return true;
                            return root.isGroupOpen(modelData.group);
                        }
                        readonly property bool isActive: root.currentPage === modelData.key

                        width: navList.width
                        height: isVisible ? (modelData.sub ? 30 : 34) : 0
                        visible: height > 0
                        clip: true

                        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: navDelegate.isActive ? Theme.cardHover : (navMouse.containsMouse ? Theme.cardBg : "transparent")
                            Behavior on color { ColorAnimation { duration: 140 } }

                            Rectangle {
                                width: 3; height: 18; radius: 2
                                anchors.left: parent.left; anchors.leftMargin: 3; anchors.verticalCenter: parent.verticalCenter
                                color: Theme.accent
                                opacity: navDelegate.isActive ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                            }

                            Rectangle {
                                visible: modelData.sub
                                width: 1
                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.left: parent.left; anchors.leftMargin: 15
                                color: Theme.borderSubtle
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: modelData.sub ? 26 : 12
                                anchors.rightMargin: 8
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    font.family: Theme.fontSans
                                    font.pixelSize: modelData.sub ? 12 : 13
                                    font.weight: navDelegate.isActive ? Font.DemiBold : Font.Normal
                                    color: navDelegate.isActive ? Theme.text : Theme.textSub
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: modelData.hasChildren === true && root.searchQuery.trim() === ""
                                    text: "›"
                                    font.pixelSize: 14
                                    color: Theme.textMuted
                                    rotation: root.isGroupOpen(modelData.group) ? 90 : 0
                                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                            }

                            MouseArea {
                                id: navMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.hasChildren) root.toggleGroup(modelData.group);
                                    root.openPage(modelData.key);
                                }
                            }
                        }
                    }
                }
            }
        }

        // Right Content Area
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Flickable {
                id: pageFlick
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 16
                anchors.topMargin: 14
                anchors.bottomMargin: 14
                contentWidth: width
                contentHeight: pageContainer.implicitHeight + 20
                clip: true

                Item {
                    id: pageContainer
                    width: pageFlick.width
                    implicitHeight: pageCol.implicitHeight

                    ParallelAnimation {
                        id: pageInAnim
                        NumberAnimation { target: pageCol; property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                        NumberAnimation { target: pageCol; property: "y"; from: 10; to: 0; duration: 180; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        id: pageCol
                        width: parent.width
                        spacing: 12

                        // Page Heading
                        Text {
                            Layout.fillWidth: true
                            text: {
                                for (let i = 0; i < root.navItems.length; ++i) {
                                    if (root.navItems[i].key === root.currentPage) return root.navItems[i].label;
                                }
                                return "Settings";
                            }
                            font.family: Theme.fontSans
                            font.pixelSize: 20
                            font.weight: Font.Bold
                            color: Theme.text
                            elide: Text.ElideRight
                        }

                        // ==================== 1. HOME ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 12
                            visible: root.currentPage === "home"

                            Rectangle {
                                Layout.fillWidth: true; height: 68; radius: 12
                                color: Theme.cardBg; border.width: 1; border.color: Theme.borderSubtle
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 14; spacing: 12
                                    Rectangle {
                                        width: 40; height: 40; radius: 10; color: Theme.surfaceRaised; border.width: 1; border.color: Theme.borderSubtle
                                        Text { anchors.centerIn: parent; text: "λ"; font.family: Theme.fontMono; font.pixelSize: 18; font.weight: Font.Bold; color: Theme.text }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        Text { Layout.fillWidth: true; text: "Paithosh OS — Arch Linux x86_64"; font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                                        Text { Layout.fillWidth: true; text: "Hyprland 0.45.0 (Wayland) • Kernel 6.11.8-arch1-1 • zsh 5.9"; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
                                    }
                                    Rectangle {
                                        width: 78; height: 24; radius: 12; color: Theme.surfaceRaised; border.width: 1; border.color: Theme.borderSubtle
                                        Text { anchors.centerIn: parent; text: "Up 3h 14m"; font.family: Theme.fontMono; font.pixelSize: 10; color: Theme.textSub }
                                    }
                                }
                            }

                            SectionLabel { text: "System specifications" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 2; columnSpacing: 10; rowSpacing: 10
                                Repeater {
                                    model: [
                                        { title: "PROCESSOR", main: "AMD Ryzen 7 7840HS", sub: "8 Cores / 16 Threads • Load 18%" },
                                        { title: "MEMORY", main: "16 GB DDR5-5600", sub: "6.4 GB in use (40%) • 0.2 GB Swap" },
                                        { title: "GRAPHICS", main: "AMD Radeon 780M", sub: "2560 × 1600 @ 165Hz (Wayland DRM)" },
                                        { title: "STORAGE", main: "512 GB NVMe SSD", sub: "294 GB used • 218 GB free (Btrfs)" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true; height: 68; radius: 10
                                        color: Theme.cardBg; border.width: 1; border.color: Theme.borderSubtle
                                        ColumnLayout {
                                            anchors.fill: parent; anchors.margins: 12; spacing: 2
                                            Text { text: modelData.title; font.family: Theme.fontSans; font.pixelSize: 9; font.weight: Font.DemiBold; color: Theme.textMuted }
                                            Text { Layout.fillWidth: true; text: modelData.main; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; text: modelData.sub; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "Quick Settings & Theme" }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                Repeater {
                                    model: [
                                        { name: "OLED Pure", bg: "#050505", accent: "#ffffff" },
                                        { name: "Mica Dark", bg: "#14161a", accent: "#a8c7fa" },
                                        { name: "Adaptive", bg: "#101418", accent: "#80cbc4" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool active: root.activeThemePreset === modelData.name
                                        Layout.fillWidth: true; height: 74; radius: 10
                                        color: Theme.cardBg
                                        border.width: active ? 2 : 1
                                        border.color: active ? Theme.accent : Theme.borderSubtle
                                        ColumnLayout {
                                            anchors.fill: parent; anchors.margins: 10; spacing: 6
                                            Rectangle {
                                                Layout.fillWidth: true; height: 32; radius: 6; color: modelData.bg
                                                border.width: 1; border.color: Theme.borderSubtle
                                                Rectangle { width: 32; height: 6; radius: 3; anchors.top: parent.top; anchors.topMargin: 5; anchors.horizontalCenter: parent.horizontalCenter; color: modelData.accent }
                                            }
                                            Text { Layout.alignment: Qt.AlignHCenter; text: modelData.name; color: Theme.text; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.activeThemePreset = modelData.name }
                                    }
                                }
                            }

                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconChar: "🔊"; title: "Master Volume"; subtitle: "Quick output level for default PipeWire sink"
                                    CtrlSlider { from: 0; to: 100; value: root.quickVolume; unit: "%"; onMoved: (v) => root.quickVolume = v }
                                }
                            }

                            SectionLabel { text: "Most used pages" }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                CtrlBtn { text: "Display"; ghost: true; onClicked: root.openPage("display") }
                                CtrlBtn { text: "Dynamic Island"; ghost: true; onClicked: root.openPage("island") }
                                CtrlBtn { text: "Colors & Fonts"; ghost: true; onClicked: root.openPage("fonts") }
                                CtrlBtn { text: "Import / Export Themes"; ghost: true; onClicked: root.openPage("themes") }
                            }
                        }

                        // ==================== 2. SYSTEM ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "system"
                            SectionLabel { text: "System options" }
                            HubCard { iconChar: "▭"; title: "Display"; subtitle: "Resolution, scaling & orientation"; pillText: "2560 × 1600 • 125%"; onTriggered: root.openPage("display") }
                            HubCard { iconChar: "♪"; title: "Sound & Audio"; subtitle: "PipeWire sinks, input & balance"; pillText: "Built-in Speakers"; onTriggered: root.openPage("sound") }
                            HubCard { iconChar: "⚡"; title: "Power & Battery"; subtitle: "Profiles, sleep & AC behavior"; pillText: "Balanced Profile"; onTriggered: root.openPage("power") }
                            HubCard { iconChar: "↻"; title: "Update Packages"; subtitle: "Arch & Hyprland repositories"; pillText: root.selectedUpdateCount + " Updates Ready"; onTriggered: root.openPage("updates") }

                            SectionLabel { text: "Nearby settings" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "◐"; title: "Night Light"; subtitle: "Shift display to warmer colors after sunset"
                                    CtrlSwitch { checked: root.nightLight; onToggled: (v) => root.nightLight = v }
                                }
                                SettingRow {
                                    iconChar: "🔊"; title: "Master Volume"; subtitle: "Quick output level for default PipeWire sink"
                                    CtrlSlider { from: 0; to: 100; value: root.quickVolume; unit: "%"; onMoved: (v) => root.quickVolume = v }
                                }
                                SettingRow {
                                    iconChar: "⚡"; title: "Power mode"; subtitle: "Tune CPU governor and thermal profile"
                                    CtrlSelect { options: ["Power Saver", "Balanced", "Performance"]; currentText: root.powerMode; onSelected: (v) => root.powerMode = v }
                                }
                                SettingRow {
                                    iconChar: "🔕"; title: "Do Not Disturb"; subtitle: "Silence popups on the Dynamic Island status bar"
                                    CtrlSwitch { checked: root.dndEnabled; onToggled: (v) => root.dndEnabled = v }
                                }
                            }
                        }

                        // ==================== 3. DISPLAY ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "display"
                            SectionLabel { text: "Scale & layout" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "⤢"; title: "Scale"; subtitle: "Change the size of text, apps, and other items"
                                    CtrlSelect { options: ["100%", "125% (Recommended)", "150%", "200%"]; currentText: root.displayScale; onSelected: (v) => root.displayScale = v }
                                }
                                SettingRow {
                                    iconChar: "▭"; title: "Display resolution"; subtitle: "Adjust the resolution to fit your connected display"
                                    CtrlSelect { options: ["2560 × 1600 (Recommended)", "1920 × 1200", "1920 × 1080"]; currentText: root.displayRes; onSelected: (v) => root.displayRes = v }
                                }
                                SettingRow {
                                    iconChar: "↻"; title: "Display orientation"; subtitle: "Rotate screen layout for Wayland output"
                                    CtrlSelect { options: ["Landscape", "Portrait"]; currentText: root.displayOrient; onSelected: (v) => root.displayOrient = v }
                                }
                                SettingRow {
                                    iconChar: "🔒"; title: "Rotation lock"; subtitle: "Prevent automatic orientation changes"
                                    CtrlSwitch { checked: root.rotationLock; onToggled: (v) => root.rotationLock = v }
                                }
                            }
                        }

                        // ==================== 4. SOUND ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "sound"
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "♪"; title: "Output device"; subtitle: "PipeWire • Built-in Audio Analog Stereo (" + root.quickVolume + "%)"
                                    CtrlSwitch { checked: root.soundMute; onToggled: (v) => root.soundMute = v }
                                }
                            }
                        }

                        // ==================== 5. POWER ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "power"
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "⚡"; title: "Power profile"; subtitle: "Balanced • Battery 84% (3h 42m remaining)"
                                    CtrlSelect { options: ["Power Saver", "Balanced", "Performance"]; currentText: root.powerMode; onSelected: (v) => root.powerMode = v }
                                }
                            }
                        }

                        // ==================== 6. UPDATES ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "updates"
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "↻"; title: "Pacman & AUR Sync"; subtitle: "4 packages available to upgrade (148 MB)"
                                    CtrlBtn { text: "Update selected (" + root.selectedUpdateCount + ")"; onClicked: root.updateChecks = [false, false, false, false] }
                                }
                            }
                            SectionLabel { text: "Pending packages" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; title: "hyprland"; subtitle: "0.45.0-1 → 0.45.2-1 • 18.4 MB"
                                    CtrlTickBox { checked: root.updateChecks[0]; onToggled: root.toggleUpdateCheck(0) }
                                }
                                SettingRow {
                                    title: "linux"; subtitle: "6.11.8.arch1-1 → 6.11.9.arch1-1 • 112 MB"
                                    CtrlTickBox { checked: root.updateChecks[1]; onToggled: root.toggleUpdateCheck(1) }
                                }
                                SettingRow {
                                    title: "mesa"; subtitle: "24.2.6-1 → 24.2.7-1 • 14.2 MB"
                                    CtrlTickBox { checked: root.updateChecks[2]; onToggled: root.toggleUpdateCheck(2) }
                                }
                                SettingRow {
                                    title: "pipewire"; subtitle: "1.2.5-1 → 1.2.6-1 • 3.4 MB"
                                    CtrlTickBox { checked: root.updateChecks[3]; onToggled: root.toggleUpdateCheck(3) }
                                }
                            }
                        }

                        // ==================== 7. NETWORK ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "network"
                            SectionLabel { text: "Network options" }
                            HubCard { iconChar: "◈"; title: "Wi-Fi"; subtitle: "Wireless networks, SSID & signal"; pillText: root.connectedSsid + " • Connected"; onTriggered: root.openPage("wifi") }
                            HubCard { iconChar: "🛡"; title: "VPN & Proxy"; subtitle: "WireGuard tunnels & HTTP proxy"; pillText: root.vpnActive ? "WireGuard • Active" : "WireGuard • Standby"; onTriggered: root.openPage("vpn") }
                            HubCard { iconChar: "◉"; title: "DNS & Routing"; subtitle: "Encrypted DoH & split-horizon"; pillText: "1.1.1.1 • DoH Active"; onTriggered: {} }
                            HubCard { iconChar: "📱"; title: "KDE Connect & Share"; subtitle: "Local LAN pairing & file drop"; pillText: "Pixel 8 Pro • Paired"; onTriggered: {} }

                            SectionLabel { text: "Nearby settings" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "◈"; title: "Wi-Fi Radio (wlan0)"; subtitle: "Connected to Paithon_5G • 5 GHz WPA3"
                                    CtrlSwitch { checked: root.wifiRadio; onToggled: (v) => root.wifiRadio = v }
                                }
                                SettingRow {
                                    iconChar: "✈"; title: "Airplane mode"; subtitle: "Stop all wireless communication"
                                    CtrlSwitch { checked: root.airplaneMode; onToggled: (v) => root.airplaneMode = v }
                                }
                                SettingRow {
                                    iconChar: "◉"; title: "DNS Provider"; subtitle: "Resolver used for all system queries"
                                    CtrlSelect { options: ["Cloudflare (1.1.1.1)", "Quad9 (9.9.9.9)", "System Auto (DHCP)"]; currentText: root.dnsProvider; onSelected: (v) => root.dnsProvider = v }
                                }
                                SettingRow {
                                    iconChar: "◔"; title: "Metered connection"; subtitle: "Pause automatic background package sync"
                                    CtrlSwitch { checked: root.meteredConn; onToggled: (v) => root.meteredConn = v }
                                }
                            }
                        }

                        // ==================== 8. WIFI ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "wifi"
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "◈"; title: "Wi-Fi Adapter (wlan0)"; subtitle: "Connected to " + root.connectedSsid + " • 866 Mbps"
                                    CtrlSwitch { checked: root.wifiRadio; onToggled: (v) => root.wifiRadio = v }
                                }
                            }
                            SectionLabel { text: "Available networks" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "●"; title: "Paithon_5G"; subtitle: "Connected • 5 GHz • WPA3"
                                    CtrlBtn { text: root.connectedSsid === "Paithon_5G" ? "Disconnect" : "Connect"; ghost: true; onClicked: root.connectedSsid = (root.connectedSsid === "Paithon_5G" ? "" : "Paithon_5G") }
                                }
                                SettingRow {
                                    iconChar: "○"; title: "Studio_Mesh"; subtitle: "Secured • 5 GHz • Strong"
                                    CtrlBtn { text: root.connectedSsid === "Studio_Mesh" ? "Disconnect" : "Connect"; ghost: true; onClicked: root.connectedSsid = "Studio_Mesh" }
                                }
                                SettingRow {
                                    iconChar: "○"; title: "Cafe_Guest"; subtitle: "Open • 2.4 GHz • Fair"
                                    CtrlBtn { text: root.connectedSsid === "Cafe_Guest" ? "Disconnect" : "Connect"; ghost: true; onClicked: root.connectedSsid = "Cafe_Guest" }
                                }
                                SettingRow {
                                    iconChar: "+"; title: "Hidden network"; subtitle: "Enter SSID manually"
                                    CtrlBtn { text: "Join"; onClicked: {} }
                                }
                            }
                        }

                        // ==================== 9. VPN ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "vpn"
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "🛡"; title: "WireGuard Tunnel (wg0)"; subtitle: "Encrypted peer-to-peer VPN"
                                    CtrlSwitch { checked: root.vpnActive; onToggled: (v) => root.vpnActive = v }
                                }
                                SettingRow {
                                    iconChar: "⌖"; title: "Endpoint server"; subtitle: "Host and port for WireGuard peer"
                                    Text { text: root.vpnEndpoint; color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 11 }
                                }
                                SettingRow {
                                    iconChar: "⊞"; title: "Custom DNS"; subtitle: "Override system resolver"
                                    Text { text: root.vpnDns; color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 11 }
                                }
                                SettingRow {
                                    title: "Auto-connect on boot"; subtitle: "Start wg0 automatically with Hyprland"
                                    CtrlTickBox { checked: root.vpnAutostart; onToggled: (v) => root.vpnAutostart = v }
                                }
                                SettingRow {
                                    title: "Kill switch"; subtitle: "Block non-VPN traffic if tunnel drops"
                                    CtrlTickBox { checked: root.vpnKillSwitch; onToggled: (v) => root.vpnKillSwitch = v }
                                }
                            }
                        }

                        // ==================== 10. PERSONALIZATION ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "personalization"
                            SectionLabel { text: "Personalization options" }
                            HubCard { iconChar: "⛶"; title: "Dynamic Island"; subtitle: "Corner radius, top offset & auto-hide"; pillText: "26px Pill • 12px Offset"; onTriggered: root.openPage("island") }
                            HubCard { iconChar: "◐"; title: "Colors & Fonts"; subtitle: "Global contrast & UI typography"; pillText: "JetBrains • High Contrast"; onTriggered: root.openPage("fonts") }
                            HubCard { iconChar: "❖"; title: "Gaps & Borders"; subtitle: "Inner/outer gaps & border width"; pillText: "8px / 16px • 2px Border"; onTriggered: root.openPage("hyprland") }
                            HubCard { iconChar: "◫"; title: "Layouts"; subtitle: "Dwindle, Master & smart split"; pillText: "Dwindle Active"; onTriggered: root.openPage("layouts") }
                            HubCard { iconChar: "▢"; title: "Decoration"; subtitle: "Window rounding & drop shadows"; pillText: "Rounding " + root.cornerRounding + "px"; onTriggered: root.openPage("decoration") }
                            HubCard { iconChar: "✦"; title: "Animations & Blur"; subtitle: "Spring bezier & Kawase frosted blur"; pillText: "Spring 1.0× • 6px Blur"; onTriggered: root.openPage("animations") }
                            HubCard { iconChar: "⇪"; title: "Import / Export Themes"; subtitle: "Backup, share or load .json theme bundles across devices"; pillText: "paithosh-oled-2026.json"; onTriggered: root.openPage("themes") }

                            SectionLabel { text: "Nearby settings" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "⛶"; title: "Dynamic Island Auto-Hide"; subtitle: "Collapse status bar when a window is fullscreen"
                                    CtrlSwitch { checked: root.islandAutoHide; onToggled: (v) => root.islandAutoHide = v }
                                }
                                SettingRow {
                                    iconChar: "✦"; title: "Window Blur (Kawase)"; subtitle: "Dual-pass frosted glass behind floating panels"
                                    CtrlSwitch { checked: root.kawaseBlur; onToggled: (v) => root.kawaseBlur = v }
                                }
                                SettingRow {
                                    iconChar: "◐"; title: "Global Surface Theme"; subtitle: "Contrast & backdrop style synced across apps"
                                    CtrlSelect { options: ["OLED Pure", "Mica Dark", "Adaptive"]; currentText: root.globalSurfaceTheme; onSelected: (v) => root.globalSurfaceTheme = v }
                                }
                                SettingRow {
                                    iconChar: "▢"; title: "Active Border Highlight"; subtitle: "Show crisp white outline on focused window"
                                    CtrlSwitch { checked: root.activeBorderHighlight; onToggled: (v) => root.activeBorderHighlight = v }
                                }
                            }
                        }

                        // ==================== 11. DYNAMIC ISLAND ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "island"
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "◐"; title: "Status bar corner radius"; subtitle: "Roundness of Dynamic Island pills"
                                    CtrlSelect { options: ["12px", "18px", "26px (Default)"]; currentText: root.islandCornerRadius; onSelected: (v) => root.islandCornerRadius = v }
                                }
                                SettingRow {
                                    iconChar: "↕"; title: "Top edge offset"; subtitle: "12px at rest, 16px on hover / Dashboard"
                                    CtrlSwitch { checked: root.topEdgeOffset; onToggled: (v) => root.topEdgeOffset = v }
                                }
                                SettingRow {
                                    iconChar: "⛶"; title: "Hide status bar (Fullscreen)"; subtitle: "Collapse entire Dynamic Island when an app goes fullscreen"
                                    CtrlSwitch { checked: root.hideBarFullscreen; onToggled: (v) => root.hideBarFullscreen = v }
                                }
                            }
                        }

                        // ==================== 12. COLORS & FONTS ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "fonts"

                            Rectangle {
                                Layout.fillWidth: true; height: 220; radius: 12
                                color: Theme.cardBg; border.width: 1; border.color: Theme.borderSubtle
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 14; spacing: 10
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: "Accent & Contrast Studio"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                                        CtrlBtn { text: "Reset B&W"; ghost: true; onClicked: { root.satVal = 0; root.valVal = 0.92; root.hueVal = 0; } }
                                        RowLayout {
                                            spacing: 4
                                            CtrlBtn { text: "Solid"; ghost: root.accentMode !== "Solid"; onClicked: root.accentMode = "Solid" }
                                            CtrlBtn { text: "Gradient"; ghost: root.accentMode !== "Gradient"; onClicked: root.accentMode = "Gradient" }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 14
                                        Rectangle {
                                            id: svBox
                                            width: 130; height: 130; radius: 8
                                            color: Qt.hsva(root.hueVal, 1.0, 1.0, 1.0)
                                            border.width: 1; border.color: Theme.borderSubtle
                                            Rectangle {
                                                anchors.fill: parent; radius: 8
                                                gradient: Gradient {
                                                    orientation: Gradient.Horizontal
                                                    GradientStop { position: 0.0; color: "#ffffff" }
                                                    GradientStop { position: 1.0; color: "transparent" }
                                                }
                                            }
                                            Rectangle {
                                                anchors.fill: parent; radius: 8
                                                gradient: Gradient {
                                                    orientation: Gradient.Vertical
                                                    GradientStop { position: 0.0; color: "transparent" }
                                                    GradientStop { position: 1.0; color: "#000000" }
                                                }
                                            }
                                            Rectangle {
                                                width: 10; height: 10; radius: 5
                                                x: root.satVal * (svBox.width - 10)
                                                y: (1.0 - root.valVal) * (svBox.height - 10)
                                                color: "transparent"; border.width: 2; border.color: "#ffffff"
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onPositionChanged: (m) => { if (pressed) { root.satVal = Math.max(0, Math.min(1, m.x / width)); root.valVal = Math.max(0, Math.min(1, 1.0 - m.y / height)); } }
                                                onClicked: (m) => { root.satVal = Math.max(0, Math.min(1, m.x / width)); root.valVal = Math.max(0, Math.min(1, 1.0 - m.y / height)); }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text { text: "Hue"; color: Theme.textSub; font.pixelSize: 11 }
                                            Slider { Layout.fillWidth: true; from: 0; to: 1; value: root.hueVal; onMoved: root.hueVal = value }
                                            Text { text: "Gradient Angle: " + root.gradientAngle + "°"; color: Theme.textSub; font.pixelSize: 11 }
                                            Slider { Layout.fillWidth: true; from: 0; to: 360; value: root.gradientAngle; onMoved: root.gradientAngle = Math.round(value) }
                                            Rectangle {
                                                Layout.fillWidth: true; height: 28; radius: 14
                                                color: Theme.pillBg; border.width: 1; border.color: Theme.borderSubtle
                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                                    Text { text: "27°C"; color: Theme.text; font.pixelSize: 11; font.weight: Font.Bold }
                                                    Item { Layout.fillWidth: true }
                                                    Rectangle { width: 42; height: 14; radius: 7; color: Qt.hsva(root.hueVal, root.satVal, root.valVal, 1.0) }
                                                    Item { Layout.fillWidth: true }
                                                    Text { text: "09:12"; color: Theme.text; font.pixelSize: 11 }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ==================== 13. HYPRLAND (GAPS & BORDERS) ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "hyprland"
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "❖"; title: "Window gaps"; subtitle: "Gaps in: 6px • Gaps out: 12px"
                                    CtrlSelect { options: ["Compact (4 / 8)", "Balanced (6 / 12)", "Spacious (10 / 20)"]; currentText: root.windowGapsPreset; onSelected: (v) => root.windowGapsPreset = v }
                                }
                                SettingRow {
                                    iconChar: "✦"; title: "Blur & bezier curves"; subtitle: "Zero dead animations enabled globally"
                                    CtrlSwitch { checked: root.blurBezierGlobal; onToggled: (v) => root.blurBezierGlobal = v }
                                }
                            }
                        }

                        // ==================== 14. LAYOUTS ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "layouts"
                            SectionLabel { text: "Window tiling & behavior" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 2; columnSpacing: 10; rowSpacing: 10
                                Repeater {
                                    model: [
                                        { id: "dwindle", name: "Dwindle", desc: "Binary space partitioning that splits each new window cleanly." },
                                        { id: "master", name: "Master", desc: "Large primary workspace on the left with stacked auxiliaries." },
                                        { id: "monocle", name: "Monocle", desc: "Single distraction-free window expanded edge-to-edge." },
                                        { id: "floating", name: "Floating", desc: "Free-form overlapping windows detached from the Status Bar." }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool selected: root.activeLayout === modelData.id
                                        Layout.fillWidth: true; height: 108; radius: 12
                                        color: selected ? Theme.cardHover : Theme.cardBg
                                        border.width: 1; border.color: selected ? Theme.accent : Theme.borderSubtle
                                        RowLayout {
                                            anchors.fill: parent; anchors.margins: 12; spacing: 12
                                            Rectangle {
                                                width: 68; height: 48; radius: 6; color: Theme.surfaceRaised; border.width: 1; border.color: Theme.borderSubtle
                                                Rectangle {
                                                    x: 4; y: 4
                                                    width: modelData.id === "monocle" ? 60 : (modelData.id === "floating" ? 34 : 28)
                                                    height: modelData.id === "monocle" ? 40 : (modelData.id === "floating" ? 24 : 40)
                                                    radius: 3; color: Theme.accent; opacity: 0.88
                                                }
                                                Rectangle {
                                                    visible: modelData.id !== "monocle"
                                                    x: modelData.id === "floating" ? 26 : 36
                                                    y: modelData.id === "floating" ? 16 : 4
                                                    width: 28; height: modelData.id === "floating" ? 24 : 18
                                                    radius: 3; color: Theme.textSub; opacity: 0.65
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 3
                                                Text { text: modelData.name; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                                                Text { Layout.fillWidth: true; text: modelData.desc; color: Theme.textSub; font.pixelSize: 11; wrapMode: Text.WordWrap }
                                            }
                                        }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.activeLayout = modelData.id }
                                    }
                                }
                            }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "◫"; title: "Master split ratio"; subtitle: "Percentage width reserved for primary window"
                                    CtrlSlider { from: 30; to: 80; value: root.masterRatio; unit: "%"; onMoved: (v) => root.masterRatio = v }
                                }
                                SettingRow {
                                    title: "Preserve split direction"; subtitle: "Keep orientation consistent when closing windows"
                                    CtrlTickBox { checked: root.preserveSplit; onToggled: (v) => root.preserveSplit = v }
                                }
                            }
                        }

                        // ==================== 15. DECORATION ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "decoration"
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "▢"; title: "Corner rounding"; subtitle: "Window & pill border radius"
                                    CtrlSlider { from: 0; to: 28; value: root.cornerRounding; unit: "px"; onMoved: (v) => root.cornerRounding = v }
                                }
                                SettingRow {
                                    iconChar: "□"; title: "Border size"; subtitle: "Window outline thickness"
                                    CtrlSlider { from: 0; to: 6; value: root.borderSize; unit: "px"; onMoved: (v) => root.borderSize = v }
                                }
                                SettingRow {
                                    iconChar: "◈"; title: "Active opacity"; subtitle: "Transparency of focused window"
                                    CtrlSlider { from: 60; to: 100; value: root.activeOpacity; unit: "%"; onMoved: (v) => root.activeOpacity = v }
                                }
                                SettingRow {
                                    iconChar: "◐"; title: "Shadow range"; subtitle: "Drop shadow spread radius"
                                    CtrlSlider { from: 0; to: 48; value: root.shadowRange; unit: "px"; onMoved: (v) => root.shadowRange = v }
                                }
                                SettingRow {
                                    iconChar: "#"; title: "Active border hex"; subtitle: "Monochrome highlight color"
                                    Text { text: root.activeBorderHex; color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 12 }
                                }
                                SettingRow {
                                    title: "Drop shadow"; subtitle: "Render soft ambient window shadows"
                                    CtrlTickBox { checked: root.dropShadow; onToggled: (v) => root.dropShadow = v }
                                }
                                SettingRow {
                                    title: "Dim inactive windows"; subtitle: "Darken unfocused windows by 15%"
                                    CtrlTickBox { checked: root.dimInactive; onToggled: (v) => root.dimInactive = v }
                                }
                                SettingRow {
                                    title: "Blur behind Dynamic Island"; subtitle: "Enable Kawase blur on top layer"
                                    CtrlTickBox { checked: root.blurBehindIsland; onToggled: (v) => root.blurBehindIsland = v }
                                }
                            }
                        }

                        // ==================== 16. ANIMATIONS & BLUR ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "animations"
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "✦"; title: "Zero Dead Animations"; subtitle: "Spring bezier curves active across all windows & pills"
                                    CtrlSwitch { checked: root.zeroDeadAnims; onToggled: (v) => root.zeroDeadAnims = v }
                                }
                            }
                        }

                        // ==================== 17. IMPORT / EXPORT THEMES ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "themes"
                            SectionLabel { text: "Export current theme" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "⇪"; title: "Theme bundle file"; subtitle: "Package Dynamic Island, global colors & Hyprland rules"
                                    CtrlBtn { text: "Copy JSON"; ghost: true; onClicked: root.themeExportStatus = "Copied JSON (" + Theme.exportBundle().length + " bytes)" }
                                    CtrlBtn { text: "Export"; onClicked: root.themeExportStatus = "Exported paithosh-oled-2026.json" }
                                }
                                SettingRow {
                                    iconChar: "⊞"; title: "Include Hyprland compositor rules"; subtitle: "Export gaps, borders, rounding & Kawase blur values"
                                    CtrlSwitch { checked: root.exportIncHypr; onToggled: (v) => root.exportIncHypr = v }
                                }
                                SettingRow {
                                    iconChar: "◐"; title: "Include Dynamic Island & global palette"; subtitle: "Export surface contrast, accent & typography tokens"
                                    CtrlSwitch { checked: root.exportIncPalette; onToggled: (v) => root.exportIncPalette = v }
                                }
                            }
                            Text {
                                visible: root.themeExportStatus !== ""
                                text: root.themeExportStatus
                                color: Theme.ok
                                font.pixelSize: 11
                            }

                            SectionLabel { text: "Saved theme bundles" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; title: "OLED Pure (Default)"; subtitle: "paithosh-oled-2026.json • v1.2 • High Contrast"
                                    CtrlBtn { text: "Export"; ghost: true; onClicked: root.themeExportStatus = "Exported paithosh-oled-2026.json" }
                                    CtrlBtn { text: root.activeThemePreset === "OLED Pure" ? "Active" : "Load"; ghost: root.activeThemePreset !== "OLED Pure"; onClicked: root.activeThemePreset = "OLED Pure" }
                                }
                                SettingRow {
                                    title: "Nord Frost"; subtitle: "nord-frost-hypr.json • v1.2 • Cool Slate"
                                    CtrlBtn { text: "Export"; ghost: true; onClicked: root.themeExportStatus = "Exported nord-frost-hypr.json" }
                                    CtrlBtn { text: root.activeThemePreset === "Nord Frost" ? "Active" : "Load"; ghost: root.activeThemePreset !== "Nord Frost"; onClicked: root.activeThemePreset = "Nord Frost" }
                                }
                                SettingRow {
                                    title: "Mica Monochrome"; subtitle: "mica-mono-glass.json • v1.2 • Frosted Blur"
                                    CtrlBtn { text: "Export"; ghost: true; onClicked: root.themeExportStatus = "Exported mica-mono-glass.json" }
                                    CtrlBtn { text: root.activeThemePreset === "Mica Monochrome" ? "Active" : "Load"; ghost: root.activeThemePreset !== "Mica Monochrome"; onClicked: root.activeThemePreset = "Mica Monochrome" }
                                }
                            }
                        }

                        // ==================== 18. ABOUT ====================
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: root.currentPage === "about"
                            SettingGroup {
                                SettingRow { showDivider: false; iconChar: "λ"; title: "OS Name"; subtitle: "Paithosh OS (Arch Linux Rolling)" }
                                SettingRow { iconChar: "⚙"; title: "Compositor"; subtitle: "Hyprland 0.45.0 • Wayland" }
                                SettingRow { iconChar: "⌨"; title: "Hostname"; subtitle: "paithon-hypr" }
                            }
                        }
                    }
                }
            }
        }
    }
}
