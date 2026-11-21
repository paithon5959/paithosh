import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."
import "../services"
import "common"

Item {
    id: root
    required property var shellState

    property string currentPage: "home" // home | system | display | sound | power | network | wifi | personalization | island | themes | about
    property string themeStatusText: ""

    implicitWidth: 860
    implicitHeight: 540

    function openPage(pageKey) {
        currentPage = pageKey || "home";
        themeStatusText = "";
    }

    readonly property var navEntries: [
        { key: "home", label: "Home", sub: false },
        { key: "system", label: "System", sub: false },
        { key: "display", label: "Display", sub: true },
        { key: "sound", label: "Sound & Audio", sub: true },
        { key: "power", label: "Power & Battery", sub: true },
        { key: "network", label: "Network & internet", sub: false },
        { key: "wifi", label: "Wi-Fi", sub: true },
        { key: "personalization", label: "Personalization", sub: false },
        { key: "island", label: "Dynamic Island", sub: true },
        { key: "themes", label: "Import / Export Themes", sub: true },
        { key: "about", label: "About", sub: false }
    ]

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left Sidebar
        Rectangle {
            Layout.preferredWidth: 226
            Layout.fillHeight: true
            color: Theme.surfaceRaised
            radius: 16
            border.width: 1
            border.color: Theme.borderSubtle
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 17
                        color: Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: "P"
                            font.family: Theme.fontSans
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: Theme.accentFg
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: "Paithon"
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Theme.text
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "paithon@hyprland"
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            color: Theme.textSub
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderSubtle
                }

                ListView {
                    id: navList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.navEntries

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool isActive: root.currentPage === modelData.key
                        width: navList.width
                        height: modelData.sub ? 30 : 34
                        radius: 8
                        color: isActive ? Theme.cardHover : (navMouse.containsMouse ? Theme.cardBg : "transparent")

                        Behavior on color { ColorAnimation { duration: 140 } }

                        Rectangle {
                            width: 3
                            height: 16
                            radius: 2
                            anchors.left: parent.left
                            anchors.leftMargin: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.accent
                            opacity: isActive ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: modelData.sub ? 24 : 14
                            anchors.rightMargin: 10
                            text: modelData.label
                            font.family: Theme.fontSans
                            font.pixelSize: modelData.sub ? 12 : 13
                            font.weight: isActive ? Font.DemiBold : Font.Normal
                            color: isActive ? Theme.text : Theme.textSub
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: navMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openPage(modelData.key)
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
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 4
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                contentWidth: width
                contentHeight: pageCol.implicitHeight + 16
                clip: true

                ColumnLayout {
                    id: pageCol
                    width: parent.width - 8
                    spacing: 12

                    // Breadcrumb
                    Text {
                        Layout.fillWidth: true
                        text: {
                            switch (root.currentPage) {
                            case "system": return "System";
                            case "display": return "System › Display";
                            case "sound": return "System › Sound & Audio";
                            case "power": return "System › Power & Battery";
                            case "network": return "Network & internet";
                            case "wifi": return "Network & internet › Wi-Fi";
                            case "personalization": return "Personalization";
                            case "island": return "Personalization › Dynamic Island";
                            case "themes": return "Personalization › Import / Export Themes";
                            case "about": return "About";
                            default: return "Home";
                            }
                        }
                        font.family: Theme.fontSans
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: Theme.text
                        elide: Text.ElideRight
                    }

                    // 1. HOME PAGE
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: root.currentPage === "home"

                        Rectangle {
                            Layout.fillWidth: true
                            height: 68
                            radius: 12
                            color: Theme.cardBg
                            border.width: 1
                            border.color: Theme.borderSubtle

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 12
                                Rectangle {
                                    width: 38
                                    height: 38
                                    radius: 10
                                    color: Theme.accent
                                    Text {
                                        anchors.centerIn: parent
                                        text: "λ"
                                        font.pixelSize: 18
                                        font.weight: Font.Bold
                                        color: Theme.accentFg
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Paithosh OS — Arch Linux x86_64"
                                        font.family: Theme.fontSans
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                        color: Theme.text
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Hyprland (Wayland) • Quickshell Dynamic Island"
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        color: Theme.textSub
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Text {
                            text: "MAJOR CATEGORIES"
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Theme.textMuted
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 10

                            Repeater {
                                model: [
                                    { key: "system", title: "System", sub: "Display, Sound, Power", pill: "84% • Balanced" },
                                    { key: "network", title: "Network & internet", sub: "Wi-Fi, VPN, DNS", pill: NetworkService.activeSsid || "Connected" },
                                    { key: "personalization", title: "Personalization", sub: "Island, Theme, Motion", pill: "OLED Pure" },
                                    { key: "themes", title: "Import / Export Themes", sub: "JSON bundles & palettes", pill: "v1.2" }
                                ]
                                delegate: HubCard {
                                    Layout.fillWidth: true
                                    titleText: modelData.title
                                    subText: modelData.sub
                                    pillText: modelData.pill
                                    onClicked: root.openPage(modelData.key)
                                }
                            }
                        }
                    }

                    // 2. SYSTEM HUB (Large Multi-Option + Nearby Settings)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: root.currentPage === "system"

                        Text { text: "SYSTEM OPTIONS"; font.pixelSize: 11; font.weight: Font.DemiBold; color: Theme.textMuted }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 10

                            HubCard { Layout.fillWidth: true; titleText: "Display"; subText: "Scale, resolution & orientation"; pillText: "2560 × 1600 • 125%"; onClicked: root.openPage("display") }
                            HubCard { Layout.fillWidth: true; titleText: "Sound & Audio"; subText: "PipeWire sink & output level"; pillText: AudioService.volume + "% Output"; onClicked: root.openPage("sound") }
                            HubCard { Layout.fillWidth: true; titleText: "Power & Battery"; subText: "Profiles & charging status"; pillText: PowerService.percentage + "% • Balanced"; onClicked: root.openPage("power") }
                            HubCard { Layout.fillWidth: true; titleText: "About System"; subText: "Kernel, Hyprland & hardware"; pillText: "Arch Rolling"; onClicked: root.openPage("about") }
                        }

                        Text { text: "NEARBY SETTINGS"; font.pixelSize: 11; font.weight: Font.DemiBold; color: Theme.textMuted }
                        SettingToggleRow {
                            Layout.fillWidth: true
                            titleText: "Mute Audio Output"
                            descText: "Silence default PipeWire sink"
                            checked: AudioService.muted
                            onToggled: AudioService.toggleMute()
                        }
                        SettingActionRow {
                            Layout.fillWidth: true
                            titleText: "Master Volume"
                            descText: "Current: " + AudioService.volume + "%"
                            btnText: "+10%"
                            onTriggered: AudioService.adjustVolume(10)
                        }
                        SettingActionRow {
                            Layout.fillWidth: true
                            titleText: "Display Brightness"
                            descText: "Current: " + BrightnessService.brightness + "%"
                            btnText: "+10%"
                            onTriggered: BrightnessService.adjustBrightness(10)
                        }
                    }

                    // 3. NETWORK HUB (Large Multi-Option + Nearby Settings)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: root.currentPage === "network"

                        Text { text: "NETWORK OPTIONS"; font.pixelSize: 11; font.weight: Font.DemiBold; color: Theme.textMuted }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 10

                            HubCard { Layout.fillWidth: true; titleText: "Wi-Fi"; subText: "Wireless SSID & signal"; pillText: NetworkService.activeSsid || "wlan0"; onClicked: root.openPage("wifi") }
                            HubCard { Layout.fillWidth: true; titleText: "KDE Connect"; subText: "LAN pairing & file drop"; pillText: "Pixel 8 Pro"; onClicked: KdeConnectService.sendFile("hyprland.conf") }
                        }

                        Text { text: "NEARBY SETTINGS"; font.pixelSize: 11; font.weight: Font.DemiBold; color: Theme.textMuted }
                        SettingToggleRow {
                            Layout.fillWidth: true
                            titleText: "Wi-Fi Radio"
                            descText: NetworkService.wifiEnabled ? ("Connected to " + (NetworkService.activeSsid || "Wi-Fi")) : "Disconnected"
                            checked: NetworkService.wifiEnabled
                            onToggled: NetworkService.toggleWifi()
                        }
                    }

                    // 4. PERSONALIZATION HUB (Large Multi-Option + Nearby Settings)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: root.currentPage === "personalization"

                        Text { text: "PERSONALIZATION OPTIONS"; font.pixelSize: 11; font.weight: Font.DemiBold; color: Theme.textMuted }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 10

                            HubCard { Layout.fillWidth: true; titleText: "Dynamic Island"; subText: "Corner radius & gooey morph"; pillText: Theme.islandRadius + "px Pill"; onClicked: root.openPage("island") }
                            HubCard { Layout.fillWidth: true; titleText: "Import / Export Themes"; subText: "JSON bundles & global contrast"; pillText: "Bundle v1.2"; onClicked: root.openPage("themes") }
                        }

                        Text { text: "NEARBY SETTINGS"; font.pixelSize: 11; font.weight: Font.DemiBold; color: Theme.textMuted }
                        SettingToggleRow {
                            Layout.fillWidth: true
                            titleText: "Gooey Liquid Shader"
                            descText: "Smooth metaball bridge between split pills"
                            checked: Theme.gooeyEnabled
                            onToggled: Theme.gooeyEnabled = !Theme.gooeyEnabled
                        }
                        SettingActionRow {
                            Layout.fillWidth: true
                            titleText: "Island Corner Radius"
                            descText: "Current: " + Theme.islandRadius + "px"
                            btnText: Theme.islandRadius === 26 ? "18px" : "26px"
                            onTriggered: Theme.islandRadius = (Theme.islandRadius === 26 ? 18 : 26)
                        }
                    }

                    // 5. IMPORT / EXPORT THEMES PAGE
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: root.currentPage === "themes"

                        Text { text: "EXPORT CURRENT THEME"; font.pixelSize: 11; font.weight: Font.DemiBold; color: Theme.textMuted }
                        SettingActionRow {
                            Layout.fillWidth: true
                            titleText: "Export Theme Bundle (.json)"
                            descText: root.themeStatusText !== "" ? root.themeStatusText : "Package pill, surface & radius tokens"
                            btnText: "Export JSON"
                            onTriggered: {
                                root.themeStatusText = "Exported: " + Theme.exportBundle();
                            }
                        }

                        Text { text: "SAVED THEME BUNDLES"; font.pixelSize: 11; font.weight: Font.DemiBold; color: Theme.textMuted }
                        SettingActionRow {
                            Layout.fillWidth: true
                            titleText: "OLED Pure (Default)"
                            descText: "#000000 / #ffffff • High Contrast"
                            btnText: "Apply"
                            onTriggered: {
                                Theme.loadBundle(JSON.stringify({ palette: { colors: ["#000000", "#ffffff", "#0b0b0c"], islandRadius: 26 } }));
                                root.themeStatusText = "Applied OLED Pure";
                            }
                        }
                        SettingActionRow {
                            Layout.fillWidth: true
                            titleText: "Nord Frost"
                            descText: "#14161b / #d8dee9 • Cool Slate"
                            btnText: "Apply"
                            onTriggered: {
                                Theme.loadBundle(JSON.stringify({ palette: { colors: ["#14161b", "#d8dee9", "#1e222a"], islandRadius: 22 } }));
                                root.themeStatusText = "Applied Nord Frost";
                            }
                        }
                        SettingActionRow {
                            Layout.fillWidth: true
                            titleText: "Mica Monochrome"
                            descText: "#18181b / #fafafa • Frosted Slate"
                            btnText: "Apply"
                            onTriggered: {
                                Theme.loadBundle(JSON.stringify({ palette: { colors: ["#18181b", "#fafafa", "#222226"], islandRadius: 26 } }));
                                root.themeStatusText = "Applied Mica Monochrome";
                            }
                        }
                    }

                    // 6. SUBPAGES FALLBACK (display, sound, power, wifi, island, about)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: ["display", "sound", "power", "wifi", "island", "about"].indexOf(root.currentPage) !== -1

                        SettingActionRow {
                            Layout.fillWidth: true
                            titleText: "Active Section: " + root.currentPage.toUpperCase()
                            descText: "Synced live with Paithosh Quickshell services"
                            btnText: "Back to Hub"
                            onTriggered: {
                                if (root.currentPage === "wifi") root.openPage("network");
                                else if (root.currentPage === "island") root.openPage("personalization");
                                else if (root.currentPage === "about") root.openPage("home");
                                else root.openPage("system");
                            }
                        }
                    }
                }
            }
        }
    }

    component HubCard: Rectangle {
        id: hCard
        property string titleText: ""
        property string subText: ""
        property string pillText: ""
        signal clicked()

        height: 92
        radius: 12
        color: hMouse.containsMouse ? Theme.cardHover : Theme.cardBg
        border.width: 1
        border.color: hMouse.containsMouse ? Theme.borderSubtle : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08)
        scale: hMouse.pressed ? 0.98 : 1.0
        clip: true

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { Layout.fillWidth: true; text: hCard.titleText; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                    Text { Layout.fillWidth: true; text: hCard.subText; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
                }
                Text { text: "›"; font.pixelSize: 16; color: Theme.textSub }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
            }

            Text {
                Layout.fillWidth: true
                text: hCard.pillText
                font.family: Theme.fontSans
                font.pixelSize: 11
                color: Theme.textSub
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: hMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hCard.clicked()
        }
    }

    component SettingToggleRow: Rectangle {
        id: tRow
        property string titleText: ""
        property string descText: ""
        property bool checked: false
        signal toggled()

        height: 58
        radius: 10
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: tRow.titleText; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: tRow.descText; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
            }
            Rectangle {
                width: 42
                height: 22
                radius: 11
                color: tRow.checked ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.16)
                Behavior on color { ColorAnimation { duration: 160 } }
                Rectangle {
                    width: 16
                    height: 16
                    radius: 8
                    y: 3
                    x: tRow.checked ? 23 : 3
                    color: tRow.checked ? Theme.accentFg : Theme.text
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tRow.toggled()
                }
            }
        }
    }

    component SettingActionRow: Rectangle {
        id: aRow
        property string titleText: ""
        property string descText: ""
        property string btnText: "Run"
        signal triggered()

        height: 58
        radius: 10
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: aRow.titleText; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: aRow.descText; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
            }
            PillButton {
                text: aRow.btnText
                onClicked: aRow.triggered()
            }
        }
    }
}
