import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."
import "common"
import "../services"

Item {
    id: root

    required property var shellState
    required property var menuHost
    required property var selectMenu

    readonly property bool inputFocused: duckIgnoreInput ? duckIgnoreInput.activeFocus : false
    readonly property string activeTab: MixcloudService.settingsTab || "audio"
    readonly property int tabIndex: {
        const t = activeTab;
        if (t === "mix") return 1;
        if (t === "ducking") return 2;
        if (t === "playback") return 3;
        if (t === "data") return 4;
        return 0;
    }

    // Inline 2-click safety confirmation states + transient badges
    property string confirmAction: ""
    property bool jsonCopied: false
    property string duckApplyLabel: "Apply"

    Timer {
        id: confirmResetTimer
        interval: 3200
        repeat: false
        onTriggered: root.confirmAction = ""
    }

    Timer {
        id: transientResetTimer
        interval: 1600
        repeat: false
        onTriggered: {
            root.jsonCopied = false;
            root.duckApplyLabel = "Apply";
        }
    }

    function requestTwoStepAction(key, fn) {
        if (confirmAction === key) {
            confirmAction = "";
            confirmResetTimer.stop();
            fn();
        } else {
            confirmAction = key;
            confirmResetTimer.restart();
        }
    }

    function signedDb(val) {
        const v = Number(val || 0);
        const s = v.toFixed(1);
        return (v > 0.04 ? "+" : "") + s + " dB";
    }

    function signedMs(val) {
        const v = Math.round(Number(val || 0));
        return (v > 0 ? "+" : "") + v + " ms";
    }

    function curveLabel(c) {
        if (c === "equal_power") return "Equal Power";
        if (c === "smooth_s") return "Smooth S-Curve";
        if (c === "linear") return "Linear";
        return "Progressive";
    }

    function curveId(label) {
        if (label === "Equal Power") return "equal_power";
        if (label === "Smooth S-Curve") return "smooth_s";
        if (label === "Linear") return "linear";
        return "progressive";
    }

    function eqModeLabel(m) {
        if (m === "stem_eq") return "3-Band Vocal Pocket";
        if (m === "filter_sweep") return "Warm Filter Sweep";
        if (m === "clean") return "Clean Gain";
        return "Bass Swap";
    }

    function eqModeId(label) {
        if (label === "3-Band Vocal Pocket") return "stem_eq";
        if (label === "Warm Filter Sweep") return "filter_sweep";
        if (label === "Clean Gain") return "clean";
        return "bass_swap";
    }

    function bufferLabel(bp) {
        if (bp === "low") return "Low (16 MiB / 10s)";
        if (bp === "high") return "High (64 MiB / 45s)";
        return "Balanced (32 MiB / 20s)";
    }

    function bufferId(label) {
        if (label.indexOf("Low") === 0) return "low";
        if (label.indexOf("High") === 0) return "high";
        return "balanced";
    }

    function mixStageLabel(st) {
        if (st === "cueing") return "Cueing Next";
        if (st === "analyzing") return "Analyzing PCM";
        if (st === "syncing") return "Beat & Offset Sync";
        if (st === "blending") return "Blending " + Math.round(MixcloudService.mixProgress * 100) + "%";
        if (st === "swapping") return "Swapping Deck";
        return MixcloudService.mixEnabled ? "Armed" : "Off";
    }

    // ------------------------------------------------------------------
    // Paithosh Canonical Inline Primitives
    // ------------------------------------------------------------------

    component MSectionLabel: Text {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.topMargin: 4
        font.family: Theme.fontSans
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: Theme.textMuted
        elide: Text.ElideRight
    }

    component MSettingGroup: Rectangle {
        default property alias rows: groupCol.data
        Layout.fillWidth: true
        implicitHeight: groupCol.implicitHeight
        radius: 12
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle
        clip: true
        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: groupCol
            width: parent.width
            spacing: 0
        }
    }

    component MSettingRow: Item {
        id: sRow
        property string iconName: ""
        property color iconColor: Theme.textSub
        property string title: ""
        property string subtitle: ""
        property bool showDivider: true
        default property alias control: ctrlSlot.data

        Layout.fillWidth: true
        implicitHeight: Math.max(54, rowLayout.implicitHeight + 20)
        clip: true

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
                visible: sRow.iconName !== ""
                width: 30
                height: 30
                radius: 8
                color: Theme.surfaceRaised
                border.width: 1
                border.color: Theme.borderSubtle

                SvgIcon {
                    anchors.centerIn: parent
                    sourceName: sRow.iconName
                    iconSize: 15
                    color: sRow.iconColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
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
                    Layout.minimumWidth: 0
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

    component MPresetCard: Rectangle {
        id: pCard
        property string title: ""
        property string subtitle: ""
        property string badge: ""
        property string iconName: ""
        property bool active: false
        signal triggered()

        Layout.fillWidth: true
        Layout.preferredWidth: 100
        Layout.minimumWidth: 0
        implicitHeight: 74
        radius: 11
        clip: true
        color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : (pMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
        border.width: active ? 2 : 1
        border.color: active ? Theme.accent : (pMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
        scale: pMouse.pressed ? 0.97 : 1.0

        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 11
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                SvgIcon {
                    visible: pCard.iconName !== ""
                    sourceName: pCard.iconName
                    iconSize: 15
                    color: pCard.active ? Theme.accent : Theme.textSub
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: pCard.title
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: pCard.active || pCard.badge !== ""
                    implicitWidth: badgeLbl.implicitWidth + 10
                    height: 18
                    radius: 9
                    clip: true
                    color: pCard.active ? Theme.accent : Theme.pillBg

                    ThemeGradientFill {
                        anchors.fill: parent
                        enabled: pCard.active && Theme.accentGradientEnabled
                        color1: Theme.accent
                        colorMid: Theme.accentMid
                        color2: Theme.accent2
                        cornerRadius: 9
                    }

                    Text {
                        id: badgeLbl
                        anchors.centerIn: parent
                        text: pCard.active ? "Active" : pCard.badge
                        color: pCard.active ? Theme.accentFg : Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: pCard.subtitle
                color: Theme.textSub
                font.family: Theme.fontSans
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: pMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pCard.triggered()
        }
    }

    component MAdvancedSection: Rectangle {
        id: advRoot
        property bool expanded: false
        property string title: "Advanced Parameters"
        property string subtitle: "Fine-tune raw DSP, timings & thresholds"
        default property alias content: advCol.data

        Layout.fillWidth: true
        implicitHeight: advHeader.height + (expanded ? advBody.implicitHeight : 0)
        radius: 12
        color: Theme.cardBg
        border.width: 1
        border.color: advMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : Theme.borderSubtle
        clip: true

        Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Rectangle {
            id: advHeader
            width: parent.width
            height: 50
            color: advMouse.containsMouse ? Theme.cardHover : "transparent"
            scale: advMouse.pressed ? 0.99 : 1.0
            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                SvgIcon {
                    sourceName: "sliders"
                    iconSize: 15
                    color: advRoot.expanded ? Theme.accent : (advMouse.containsMouse ? Theme.text : Theme.textMuted)
                    Behavior on color { ColorAnimation { duration: 140 } }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: advRoot.title
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: advRoot.subtitle
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    implicitWidth: advPillRow.implicitWidth + 16
                    height: 24
                    radius: 12
                    color: advMouse.containsMouse ? Theme.surfaceRaised : Theme.pillBg
                    border.width: 1
                    border.color: advMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    RowLayout {
                        id: advPillRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: advRoot.expanded ? "Hide" : "Show"
                            color: advMouse.containsMouse ? Theme.text : Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        SvgIcon {
                            sourceName: "chevron-right"
                            iconSize: 11
                            color: advMouse.containsMouse ? Theme.text : Theme.textSub
                            rotation: advRoot.expanded ? 90 : 0
                            Behavior on rotation { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }

            MouseArea {
                id: advMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: advRoot.expanded = !advRoot.expanded
            }
        }

        Item {
            id: advBody
            y: advHeader.height
            width: parent.width
            implicitHeight: advCol.implicitHeight
            opacity: advRoot.expanded ? 1.0 : 0.0
            visible: opacity > 0.01 || advRoot.expanded
            clip: true

            Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

            Rectangle { width: parent.width; height: 1; color: Theme.borderSubtle }
            ColumnLayout {
                id: advCol
                width: parent.width
                spacing: 0
            }
        }
    }

    component MCtrlSwitch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled(bool nextVal)

        width: 38
        height: 22
        radius: 11
        clip: true
        opacity: enabled ? 1.0 : 0.40
        color: checked ? Theme.accent : (swMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.22) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14))
        border.width: 1
        border.color: checked ? Theme.accent : (swMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
        scale: (sw.enabled && swMouse.pressed) ? 0.94 : 1.0

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

        ThemeGradientFill {
            anchors.fill: parent
            anchors.margins: 1
            enabled: sw.checked && Theme.accentGradientEnabled
            color1: Theme.accent
            colorMid: Theme.accentMid
            color2: Theme.accent2
            cornerRadius: 10
        }

        Rectangle {
            width: 16
            height: 16
            radius: 8
            y: 3
            x: sw.checked ? 19 : 3
            color: sw.checked ? Theme.accentFg : Theme.text
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: swMouse
            anchors.fill: parent
            enabled: sw.enabled
            hoverEnabled: sw.enabled
            cursorShape: sw.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: sw.toggled(!sw.checked)
        }
    }

    component MCtrlSlider: RowLayout {
        id: cSlider
        property real from: 0
        property real to: 100
        property real value: 50
        property string unit: "%"
        property string valueText: ""
        property int sliderWidth: 128
        property real stepSize: 0
        signal moved(real newVal)

        spacing: 10
        opacity: enabled ? 1.0 : 0.42

        Slider {
            id: sl
            Layout.preferredWidth: cSlider.sliderWidth
            implicitHeight: 22
            padding: 0
            from: cSlider.from
            to: cSlider.to
            value: cSlider.value
            stepSize: cSlider.stepSize
            onMoved: {
                const v = (cSlider.stepSize > 0 && cSlider.stepSize < 1)
                    ? Math.round(value / cSlider.stepSize) * cSlider.stepSize
                    : Math.round(value);
                cSlider.moved(v);
            }

            HoverHandler {
                cursorShape: cSlider.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            }

            background: Rectangle {
                x: sl.leftPadding
                y: sl.topPadding + sl.availableHeight / 2 - height / 2
                implicitWidth: cSlider.sliderWidth
                implicitHeight: 6
                width: sl.availableWidth
                height: 6
                radius: 3
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14)
                clip: true

                Rectangle {
                    width: Math.max(0, Math.min(parent.width, sl.visualPosition * parent.width))
                    height: parent.height
                    radius: 3
                    clip: true
                    color: Theme.accent
                    ThemeGradientFill {
                        anchors.fill: parent
                        enabled: Theme.accentGradientEnabled
                        color1: Theme.accent
                        colorMid: Theme.accentMid
                        color2: Theme.accent2
                        cornerRadius: 3
                    }
                }
            }

            handle: Rectangle {
                x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
                y: sl.topPadding + sl.availableHeight / 2 - height / 2
                width: 14
                height: 14
                radius: 7
                color: Theme.accent
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.45)
                scale: sl.pressed ? 1.18 : (sl.hovered ? 1.08 : 1.0)
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
            }
        }

        Text {
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignRight
            text: cSlider.valueText !== "" ? cSlider.valueText : (Math.round(cSlider.value) + cSlider.unit)
            color: Theme.textSub
            font.family: Theme.fontMono
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }

    component MCtrlSelect: Rectangle {
        id: cSel
        property var options: []
        property string currentText: ""
        signal selected(string val)

        height: 30
        implicitWidth: Math.min(240, Math.max(132, selLbl.implicitWidth + 44))
        radius: 8
        clip: true
        opacity: enabled ? 1.0 : 0.42
        color: (cSel.enabled && selMouse.containsMouse) ? Theme.cardHover : Theme.surfaceRaised
        border.width: 1
        border.color: (cSel.enabled && selMouse.containsMouse) ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : Theme.borderSubtle
        scale: (cSel.enabled && selMouse.pressed) ? 0.96 : 1.0

        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 6

            Text {
                id: selLbl
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: cSel.currentText
                color: Theme.text
                font.family: Theme.fontSans
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            SvgIcon {
                sourceName: "chevron-right"
                iconSize: 12
                color: Theme.textMuted
                rotation: 90
            }
        }

        MouseArea {
            id: selMouse
            anchors.fill: parent
            enabled: cSel.enabled
            hoverEnabled: cSel.enabled
            cursorShape: cSel.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (!root.selectMenu || !root.menuHost) return;
                const mw = Math.max(186, cSel.width);
                const pt = cSel.mapToItem(root.menuHost, cSel.width - mw, cSel.height + 4);
                const opts = [];
                for (let i = 0; i < cSel.options.length; ++i) {
                    const optVal = cSel.options[i];
                    opts.push({
                        text: optVal,
                        checked: optVal === cSel.currentText,
                        action: () => cSel.selected(optVal)
                    });
                }
                root.selectMenu.menuWidth = mw;
                root.selectMenu.openAt(pt.x, pt.y, opts);
            }
        }
    }

    // ------------------------------------------------------------------
    // Main Settings Layout
    // ------------------------------------------------------------------

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Top Sub-Navigation Segmented Bar
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 50

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Theme.borderSubtle
            }

            Rectangle {
                id: tabTrack
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 9
                anchors.bottomMargin: 9
                radius: 9
                color: Theme.cardBg
                border.width: 1
                border.color: Theme.borderSubtle
                clip: true

                readonly property real slotW: Math.max(1, (width - 4) / 5)

                Rectangle {
                    x: 2 + root.tabIndex * tabTrack.slotW
                    y: 2
                    width: Math.max(0, tabTrack.slotW)
                    height: parent.height - 4
                    radius: 7
                    color: Theme.surfaceRaised
                    border.width: 1
                    border.color: Theme.borderSubtle

                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 0.85 } }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 2

                    Repeater {
                        model: [
                            { key: "audio", label: "Audio & EQ", icon: "sliders" },
                            { key: "mix", label: "Mix", icon: "layers" },
                            { key: "ducking", label: "Ducking", icon: "media-duck" },
                            { key: "playback", label: "Playback", icon: "music" },
                            { key: "data", label: "Data", icon: "hard-drive" }
                        ]

                        delegate: Item {
                            id: tabBtn
                            required property var modelData
                            readonly property bool isSel: root.activeTab === modelData.key
                            width: tabTrack.slotW
                            height: parent.height
                            clip: true
                            scale: tabMouse.pressed ? 0.96 : 1.0

                            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                            RowLayout {
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, Math.max(0, parent.width - 8))
                                spacing: 5

                                SvgIcon {
                                    visible: tabBtn.width >= 96
                                    sourceName: modelData.icon
                                    iconSize: 12
                                    color: tabBtn.isSel ? Theme.accent : (tabMouse.containsMouse ? Theme.text : Theme.textMuted)
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }

                                Text {
                                    Layout.fillWidth: implicitWidth > (tabBtn.width - 12)
                                    Layout.minimumWidth: 0
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.label
                                    color: tabBtn.isSel ? Theme.text : (tabMouse.containsMouse ? Theme.text : Theme.textSub)
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: tabBtn.isSel ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }
                            }

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    MixcloudService.settingsTab = modelData.key;
                                    pageFlick.contentY = 0;
                                    if (modelData.key === "data") {
                                        MixcloudService.refreshStateDiagnostics();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Scrollable Workspace Body
        Flickable {
            id: pageFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: bodyHost.implicitHeight + 28
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ScrollBar.vertical: ScrollBar {
                policy: pageFlick.contentHeight > pageFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                width: 4
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.25)
                }
            }

            Item {
                id: bodyHost
                x: 14
                y: 12
                width: Math.max(0, pageFlick.width - 28)
                implicitHeight: {
                    if (root.activeTab === "mix") return mixCol.implicitHeight;
                    if (root.activeTab === "ducking") return duckCol.implicitHeight;
                    if (root.activeTab === "playback") return playbackCol.implicitHeight;
                    if (root.activeTab === "data") return dataCol.implicitHeight;
                    return audioCol.implicitHeight;
                }

                // ======================================================
                // TAB 1: AUDIO & EQ (Standard -> Advanced DSP)
                // ======================================================
                ColumnLayout {
                    id: audioCol
                    width: parent.width
                    spacing: 10
                    opacity: root.activeTab === "audio" ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    // Live Tone Summary Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: toneSummaryRow.implicitHeight + 18
                        radius: 11
                        color: Theme.surfaceRaised
                        border.width: 1
                        border.color: MixcloudService.audioDspEnabled ? Theme.borderSubtle : Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.35)
                        clip: true

                        RowLayout {
                            id: toneSummaryRow
                            anchors.fill: parent
                            anchors.margins: 9
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 10

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 9
                                color: Theme.cardBg
                                border.width: 1
                                border.color: Theme.borderSubtle

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: "activity"
                                    iconSize: 15
                                    color: MixcloudService.audioDspEnabled ? Theme.accent : Theme.textMuted
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: MixcloudService.audioDspEnabled ? "Live Audio EQ & DSP Active" : "Audio DSP Bypassed (Pure Bitstream)"
                                    color: Theme.text
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: "Bass " + root.signedDb(MixcloudService.eqBassDb)
                                        + " • Mid " + root.signedDb(MixcloudService.eqMidDb)
                                        + " • High " + root.signedDb(MixcloudService.eqHighDb)
                                        + (MixcloudService.audioLimiter ? " • Limiter" : "")
                                        + (MixcloudService.audioNormalize ? " • Norm" : "")
                                    color: Theme.textSub
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            PillButton {
                                text: "Flat"
                                iconName: "refresh"
                                iconSize: 12
                                fixedHeight: 28
                                radius: 8
                                onClicked: MixcloudService.applyAudioPreset("standard")
                            }
                        }
                    }

                    MSectionLabel { text: "Sound Presets" }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: pageFlick.width >= 560 ? 3 : 2
                        columnSpacing: 8
                        rowSpacing: 8

                        MPresetCard {
                            title: "Standard"
                            subtitle: "Flat reference • Limiter ON"
                            iconName: "music"
                            active: MixcloudService.audioPreset === "standard"
                            onTriggered: MixcloudService.applyAudioPreset("standard")
                        }
                        MPresetCard {
                            title: "Warm & Deep"
                            subtitle: "+4.5 dB Bass • Smooth highs"
                            iconName: "droplet"
                            active: MixcloudService.audioPreset === "warm"
                            onTriggered: MixcloudService.applyAudioPreset("warm")
                        }
                        MPresetCard {
                            title: "Bass Boost"
                            subtitle: "+7.0 dB Sub • Headroom guard"
                            iconName: "bolt"
                            active: MixcloudService.audioPreset === "bass"
                            onTriggered: MixcloudService.applyAudioPreset("bass")
                        }
                        MPresetCard {
                            title: "Vocal & Clear"
                            subtitle: "+3.5 dB Mid • Loudness norm"
                            iconName: "mic"
                            active: MixcloudService.audioPreset === "vocal"
                            onTriggered: MixcloudService.applyAudioPreset("vocal")
                        }
                        MPresetCard {
                            title: "Club / Bright"
                            subtitle: "+4 dB Low/High • Wide 1.15x"
                            iconName: "sparkles"
                            active: MixcloudService.audioPreset === "club"
                            onTriggered: MixcloudService.applyAudioPreset("club")
                        }
                        MPresetCard {
                            title: "Custom"
                            subtitle: "Parametric Hz, Q & spatial"
                            iconName: "sliders"
                            active: MixcloudService.audioPreset === "custom"
                            onTriggered: {
                                MixcloudService.applyAudioPreset("custom");
                                audioAdv.expanded = true;
                            }
                        }
                    }

                    MSectionLabel { text: "Tone & Dynamics" }

                    MSettingGroup {
                        MSettingRow {
                            showDivider: false
                            iconName: "volume"
                            title: "Enable Audio Engine (EQ & DSP)"
                            subtitle: "Apply live real-time tone shaping during playback"
                            MCtrlSwitch {
                                checked: MixcloudService.audioDspEnabled
                                onToggled: (v) => {
                                    MixcloudService.audioDspEnabled = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "gauge"
                            title: "Bass"
                            subtitle: "Low-frequency punch & warmth (" + Math.round(MixcloudService.eqBassFreq) + " Hz)"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled
                                from: -12; to: 12; stepSize: 0.5
                                value: MixcloudService.eqBassDb
                                valueText: root.signedDb(MixcloudService.eqBassDb)
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.eqBassDb = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "sliders"
                            title: "Mid"
                            subtitle: "Vocal clarity, synths & mix presence (" + Math.round(MixcloudService.eqMidFreq) + " Hz)"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled
                                from: -12; to: 12; stepSize: 0.5
                                value: MixcloudService.eqMidDb
                                valueText: root.signedDb(MixcloudService.eqMidDb)
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.eqMidDb = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "sparkles"
                            title: "High"
                            subtitle: "Treble air, hi-hats & crisp sparkle (" + Math.round(MixcloudService.eqHighFreq) + " Hz)"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled
                                from: -12; to: 12; stepSize: 0.5
                                value: MixcloudService.eqHighDb
                                valueText: root.signedDb(MixcloudService.eqHighDb)
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.eqHighDb = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "activity"
                            title: "Loudness Normalization"
                            subtitle: "Dynamic gain leveling across quiet & loud DJ sets"
                            MCtrlSwitch {
                                enabled: MixcloudService.audioDspEnabled
                                checked: MixcloudService.audioNormalize
                                onToggled: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.audioNormalize = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "shield"
                            title: "Soft-Clip Limiter"
                            subtitle: "Prevent digital clipping when boosting Bass/Mid/High"
                            MCtrlSwitch {
                                enabled: MixcloudService.audioDspEnabled
                                checked: MixcloudService.audioLimiter
                                onToggled: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.audioLimiter = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }
                    }

                    MAdvancedSection {
                        id: audioAdv
                        title: "Advanced Parametric & Spatial DSP"
                        subtitle: "Preamp headroom, Hz centers, Q widths, stereo & headphone crossfeed"

                        MSettingRow {
                            showDivider: false
                            iconName: "volume"
                            title: "Preamp Gain"
                            subtitle: "Input trim before EQ stages"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled
                                from: -12; to: 6; stepSize: 0.5
                                value: MixcloudService.audioPreampDb
                                valueText: root.signedDb(MixcloudService.audioPreampDb)
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.audioPreampDb = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "shield"
                            title: "Auto Headroom Guard"
                            subtitle: "Automatically trim preamp by half of highest EQ boost"
                            MCtrlSwitch {
                                enabled: MixcloudService.audioDspEnabled
                                checked: MixcloudService.audioAutoHeadroom
                                onToggled: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.audioAutoHeadroom = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "gauge"
                            title: "Bass Center Frequency"
                            subtitle: "Low-shelf anchor frequency"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled
                                from: 40; to: 250; stepSize: 5
                                value: MixcloudService.eqBassFreq
                                valueText: Math.round(MixcloudService.eqBassFreq) + " Hz"
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.eqBassFreq = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "sliders"
                            title: "Bass Q Slope"
                            subtitle: "Shelf steepness (lower = wider)"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled
                                from: 0.3; to: 2.0; stepSize: 0.05
                                value: MixcloudService.eqBassQ
                                valueText: MixcloudService.eqBassQ.toFixed(2) + " Q"
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.eqBassQ = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "sliders"
                            title: "Mid Center Frequency"
                            subtitle: "Peaking filter target frequency"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled
                                from: 300; to: 4000; stepSize: 50
                                value: MixcloudService.eqMidFreq
                                valueText: Math.round(MixcloudService.eqMidFreq) + " Hz"
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.eqMidFreq = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "sliders"
                            title: "Mid Q Bandwidth"
                            subtitle: "Higher Q narrows the affected vocal band"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled
                                from: 0.4; to: 3.0; stepSize: 0.1
                                value: MixcloudService.eqMidQ
                                valueText: MixcloudService.eqMidQ.toFixed(1) + " Q"
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.eqMidQ = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "sparkles"
                            title: "High Center Frequency"
                            subtitle: "High-shelf treble corner frequency"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled
                                from: 4000; to: 16000; stepSize: 250
                                value: MixcloudService.eqHighFreq
                                valueText: Math.round(MixcloudService.eqHighFreq) + " Hz"
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.eqHighFreq = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "sliders"
                            title: "High Q Slope"
                            subtitle: "Treble shelf transition slope"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled
                                from: 0.3; to: 2.0; stepSize: 0.05
                                value: MixcloudService.eqHighQ
                                valueText: MixcloudService.eqHighQ.toFixed(2) + " Q"
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.eqHighQ = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "globe"
                            title: "Stereo Width"
                            subtitle: "Expand or narrow stereo soundstage (1.00x = neutral)"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled
                                from: 0.5; to: 1.8; stepSize: 0.05
                                value: MixcloudService.audioStereoWidth
                                valueText: MixcloudService.audioStereoWidth.toFixed(2) + "x"
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.audioStereoWidth = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "headphones"
                            title: "Headphone Crossfeed"
                            subtitle: "Gentle L/R bleed for natural speaker-like imaging"
                            MCtrlSwitch {
                                enabled: MixcloudService.audioDspEnabled
                                checked: MixcloudService.audioCrossfeed
                                onToggled: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.audioCrossfeed = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "headphones"
                            title: "Crossfeed Strength"
                            subtitle: "Amount of cross-channel acoustic blend"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled && MixcloudService.audioCrossfeed
                                from: 0.10; to: 0.80; stepSize: 0.05
                                value: MixcloudService.audioCrossfeedStrength
                                valueText: Math.round(MixcloudService.audioCrossfeedStrength * 100) + "%"
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.audioCrossfeedStrength = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "activity"
                            title: "Normalizer Peak Target"
                            subtitle: "Target peak ceiling when normalization is active"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled && MixcloudService.audioNormalize
                                from: 0.75; to: 0.98; stepSize: 0.01
                                value: MixcloudService.audioNormPeak
                                valueText: Math.round(MixcloudService.audioNormPeak * 100) + "%"
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.audioNormPeak = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "clock"
                            title: "Normalizer Analysis Window"
                            subtitle: "Shorter frames adapt faster; longer frames preserve dynamics"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled && MixcloudService.audioNormalize
                                from: 100; to: 500; stepSize: 20
                                value: MixcloudService.audioNormFrameMs
                                valueText: Math.round(MixcloudService.audioNormFrameMs) + " ms"
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.audioNormFrameMs = Math.round(v);
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "shield"
                            title: "Limiter Ceiling"
                            subtitle: "Maximum output peak ceiling"
                            MCtrlSlider {
                                enabled: MixcloudService.audioDspEnabled && MixcloudService.audioLimiter
                                from: -6.0; to: -0.1; stepSize: 0.1
                                value: MixcloudService.audioLimiterCeilingDb
                                valueText: root.signedDb(MixcloudService.audioLimiterCeilingDb)
                                onMoved: (v) => {
                                    MixcloudService.audioPreset = "custom";
                                    MixcloudService.audioLimiterCeilingDb = v;
                                    MixcloudService.scheduleAudioDspSync();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "refresh"
                            title: "Reset Audio Parameters"
                            subtitle: "Restore Standard flat response & default DSP settings"
                            PillButton {
                                text: "Reset Audio"
                                iconName: "refresh"
                                fixedHeight: 28
                                radius: 8
                                onClicked: MixcloudService.applyAudioPreset("standard")
                            }
                        }
                    }
                }

                // ======================================================
                // TAB 2: PROGRESSIVE AUDIO MIX
                // ======================================================
                ColumnLayout {
                    id: mixCol
                    width: parent.width
                    spacing: 10
                    opacity: root.activeTab === "mix" ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    // Live Progressive Mix Status & Telemetry Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: mixStatusCol.implicitHeight + 20
                        radius: 12
                        clip: true
                        color: MixcloudService.isMixing
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                            : Theme.surfaceRaised
                        border.width: 1
                        border.color: MixcloudService.isMixing
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                            : Theme.borderSubtle

                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            id: mixStatusCol
                            anchors.fill: parent
                            anchors.margins: 10
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    width: 34
                                    height: 34
                                    radius: 9
                                    color: Theme.cardBg
                                    border.width: 1
                                    border.color: MixcloudService.isMixing ? Theme.accent : Theme.borderSubtle

                                    SvgIcon {
                                        anchors.centerIn: parent
                                        sourceName: "layers"
                                        iconSize: 16
                                        color: MixcloudService.isMixing ? Theme.accent : Theme.textSub
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: {
                                                if (MixcloudService.isMixing && MixcloudService.mixNextTrack) {
                                                    return "Next: " + MixcloudService.mixNextTrack.name;
                                                }
                                                const nxt = MixcloudService.peekNextQueueEntry();
                                                if (nxt && nxt.track) return "Up Next: " + nxt.track.name;
                                                return "Progressive Dual-Deck Mix";
                                            }
                                            color: Theme.text
                                            font.family: Theme.fontSans
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            Layout.preferredHeight: 18
                                            Layout.preferredWidth: stageBadgeLbl.implicitWidth + 12
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: 9
                                            clip: true
                                            color: MixcloudService.isMixing
                                                ? Theme.accent
                                                : (MixcloudService.mixEnabled ? Theme.cardBg : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08))

                                            Text {
                                                id: stageBadgeLbl
                                                anchors.centerIn: parent
                                                text: root.mixStageLabel(MixcloudService.mixStage)
                                                color: MixcloudService.isMixing ? Theme.accentFg : Theme.textSub
                                                font.family: Theme.fontMono
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: {
                                            if (MixcloudService.isMixing) {
                                                const parts = [];
                                                if (MixcloudService.mixBpmA > 0 || MixcloudService.mixBpmB > 0) {
                                                    parts.push("BPM " + MixcloudService.mixBpmA.toFixed(0) + "→" + MixcloudService.mixBpmB.toFixed(0));
                                                }
                                                if (MixcloudService.mixKeyA !== "" && MixcloudService.mixKeyB !== "") {
                                                    const compat = MixcloudService.mixKeyCompat !== "" ? (" (" + MixcloudService.mixKeyCompat + ")") : "";
                                                    parts.push("Key " + MixcloudService.mixKeyA + "→" + MixcloudService.mixKeyB + compat);
                                                }
                                                if (MixcloudService.mixActiveEqMode !== "") {
                                                    parts.push(root.eqModeLabel(MixcloudService.mixActiveEqMode));
                                                }
                                                parts.push("Trim " + root.signedDb(MixcloudService.mixGainTrimDb));
                                                if (MixcloudService.mixStage === "blending" && Math.abs(MixcloudService.mixPhaseErrMs) > 0.5) {
                                                    parts.push("Phase " + root.signedMs(MixcloudService.mixPhaseErrMs));
                                                } else {
                                                    parts.push("Off " + Math.round(MixcloudService.mixOffsetMs) + "ms");
                                                }
                                                parts.push("Spd " + MixcloudService.mixSpeedRatio.toFixed(3) + "x");
                                                if (MixcloudService.mixBufferMs > 0) parts.push("Buf " + Math.round(MixcloudService.mixBufferMs) + "ms");
                                                return parts.join(" • ");
                                            }
                                            if (MixcloudService.mixNote !== "") return MixcloudService.mixNote;
                                            return MixcloudService.hasFfmpeg
                                                ? "Cues Deck B silently at vol 0, matches loudness, key, EQ & beat phase"
                                                : "Using smooth gain crossfade (advanced beat analysis unavailable)";
                                        }
                                        color: Theme.textSub
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }

                                PillButton {
                                    readonly property bool canMix: MixcloudService.isMixing || (MixcloudService.hasTrack && MixcloudService.peekNextQueueEntry() !== null)
                                    text: MixcloudService.isMixing ? "Cancel" : "Mix Now"
                                    iconName: MixcloudService.isMixing ? "close" : "play"
                                    danger: MixcloudService.isMixing
                                    active: !MixcloudService.isMixing && canMix
                                    fixedHeight: 28
                                    radius: 8
                                    enabled: canMix
                                    onClicked: {
                                        if (MixcloudService.isMixing) MixcloudService.cancelMix();
                                        else MixcloudService.mixNow();
                                    }
                                }
                            }

                            // Animated Blend Progress Bar (visible during active mix)
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: MixcloudService.isMixing ? 6 : 0
                                opacity: MixcloudService.isMixing ? 1.0 : 0.0
                                clip: true

                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 4
                                    radius: 2
                                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14)
                                    clip: true

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        radius: 2
                                        color: Theme.accent
                                        width: Math.max(0, Math.min(parent.width, parent.width * MixcloudService.mixProgress))
                                        Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }

                    MSectionLabel { text: "Mix Presets" }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: pageFlick.width >= 560 ? 3 : 2
                        columnSpacing: 8
                        rowSpacing: 8

                        MPresetCard {
                            title: "Off"
                            subtitle: "Play queue tracks sequentially"
                            iconName: "minus"
                            active: MixcloudService.mixPreset === "off"
                            onTriggered: MixcloudService.applyMixPreset("off")
                        }
                        MPresetCard {
                            title: "Seamless"
                            subtitle: "8s Equal Power • Vol + Offset"
                            iconName: "link"
                            active: MixcloudService.mixPreset === "seamless"
                            onTriggered: MixcloudService.applyMixPreset("seamless")
                        }
                        MPresetCard {
                            title: "Progressive DJ"
                            subtitle: "14s Blend • Bass Swap & Phrase"
                            iconName: "layers"
                            active: MixcloudService.mixPreset === "progressive"
                            onTriggered: MixcloudService.applyMixPreset("progressive")
                        }
                        MPresetCard {
                            title: "Melodic Flow"
                            subtitle: "16s Smooth • Warm Filter Sweep"
                            iconName: "wind"
                            active: MixcloudService.mixPreset === "melodic"
                            onTriggered: MixcloudService.applyMixPreset("melodic")
                        }
                        MPresetCard {
                            title: "Long Club Blend"
                            subtitle: "22s Extended • 3-Band Vocal Pocket"
                            iconName: "sparkles"
                            active: MixcloudService.mixPreset === "club"
                            onTriggered: MixcloudService.applyMixPreset("club")
                        }
                        MPresetCard {
                            title: "Custom"
                            subtitle: "Lead time, tempo cap & ms offset"
                            iconName: "sliders"
                            active: MixcloudService.mixPreset === "custom"
                            onTriggered: {
                                MixcloudService.applyMixPreset("custom");
                                mixAdv.expanded = true;
                            }
                        }
                    }

                    MSectionLabel { text: "Progressive Transition & Matching" }

                    MSettingGroup {
                        MSettingRow {
                            showDivider: false
                            iconName: "layers"
                            title: "Enable Progressive Mix"
                            subtitle: "Pre-cue next track silently & blend smoothly before track end"
                            MCtrlSwitch {
                                checked: MixcloudService.mixEnabled
                                onToggled: (v) => {
                                    MixcloudService.mixPreset = v ? (MixcloudService.mixPreset === "off" ? "progressive" : MixcloudService.mixPreset) : "off";
                                    MixcloudService.mixEnabled = v;
                                    if (!v && MixcloudService.isMixing) MixcloudService.cancelMix();
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "clock"
                            title: "Blend Duration"
                            subtitle: "Total overlap time while Track 1 yields to Track 2"
                            MCtrlSlider {
                                enabled: MixcloudService.mixEnabled
                                from: 4; to: 30; stepSize: 1
                                value: MixcloudService.mixDurationSec
                                valueText: Math.round(MixcloudService.mixDurationSec) + " s"
                                onMoved: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixDurationSec = Math.round(v);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "activity"
                            title: "Crossfade Curve"
                            subtitle: "Volume envelope shape between Deck A and Deck B"
                            MCtrlSelect {
                                enabled: MixcloudService.mixEnabled
                                options: ["Progressive", "Equal Power", "Smooth S-Curve", "Linear"]
                                currentText: root.curveLabel(MixcloudService.mixCurve)
                                onSelected: (label) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixCurve = root.curveId(label);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "sliders"
                            title: "Transition EQ Style"
                            subtitle: "Swap bass or carve vocal/melody pocket so tracks never clash"
                            MCtrlSelect {
                                enabled: MixcloudService.mixEnabled
                                options: ["Bass Swap", "3-Band Vocal Pocket", "Warm Filter Sweep", "Clean Gain"]
                                currentText: root.eqModeLabel(MixcloudService.mixEqMode)
                                onSelected: (label) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixEqMode = root.eqModeId(label);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "music"
                            title: "Harmonic Key Continuity"
                            subtitle: "Detect Camelot key & adapt overlap cleanly on harmonic clashes"
                            MCtrlSwitch {
                                enabled: MixcloudService.mixEnabled
                                checked: MixcloudService.mixHarmonicAdapt
                                onToggled: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixHarmonicAdapt = v;
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "volume"
                            title: "Match Volume (Perceptual Loudness)"
                            subtitle: "Compare K-weighted outro vs intro loudness & trim incoming gain"
                            MCtrlSwitch {
                                enabled: MixcloudService.mixEnabled
                                checked: MixcloudService.mixMatchVolume
                                onToggled: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixMatchVolume = v;
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "gauge"
                            title: "Match Tempo (BPM + Micro-PLL)"
                            subtitle: "Detect 3-band BPM, couple deck speeds & lock beat phase live"
                            MCtrlSwitch {
                                enabled: MixcloudService.mixEnabled
                                checked: MixcloudService.mixMatchTempo
                                onToggled: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixMatchTempo = v;
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "bolt"
                            title: "Align Beat, Phrase & Buffer Offset"
                            subtitle: "Skip intro silence, exact-seek cue & lock beat/downbeat phase"
                            MCtrlSwitch {
                                enabled: MixcloudService.mixEnabled
                                checked: MixcloudService.mixMatchOffset
                                onToggled: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixMatchOffset = v;
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }
                    }

                    MAdvancedSection {
                        id: mixAdv
                        title: "Advanced Mix Calibration & Thresholds"
                        subtitle: "Spectral crossover, EQ depth, phrase lock, smart outro & ms calibration"

                        MSettingRow {
                            showDivider: false
                            iconName: "sliders"
                            title: "EQ Crossover Frequency"
                            subtitle: "Sub-bass swap boundary frequency during transitions"
                            MCtrlSlider {
                                enabled: MixcloudService.mixEnabled && MixcloudService.mixEqMode !== "clean"
                                from: 100; to: 320; stepSize: 10
                                value: MixcloudService.mixEqCrossoverHz
                                valueText: Math.round(MixcloudService.mixEqCrossoverHz) + " Hz"
                                onMoved: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixEqCrossoverHz = Math.round(v);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "sliders"
                            title: "EQ Swap Depth"
                            subtitle: "Bass attenuation depth during spectral transition"
                            MCtrlSlider {
                                enabled: MixcloudService.mixEnabled && MixcloudService.mixEqMode !== "clean"
                                from: 6; to: 24; stepSize: 1
                                value: MixcloudService.mixEqSwapDepthDb
                                valueText: "-" + Math.round(MixcloudService.mixEqSwapDepthDb) + " dB"
                                onMoved: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixEqSwapDepthDb = Math.round(v);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "layers"
                            title: "Phrase / Downbeat Sync (4-Beat)"
                            subtitle: "Align Beat-1 downbeats across 4-beat bars on auto transitions"
                            MCtrlSwitch {
                                enabled: MixcloudService.mixEnabled && MixcloudService.mixMatchOffset
                                checked: MixcloudService.mixPhraseSync
                                onToggled: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixPhraseSync = v;
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "bolt"
                            title: "Smart Outro Cue"
                            subtitle: "Detect energy fade-outs and mix before quiet reverb tails"
                            MCtrlSwitch {
                                enabled: MixcloudService.mixEnabled
                                checked: MixcloudService.mixSmartOutro
                                onToggled: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixSmartOutro = v;
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "gauge"
                            title: "Coupled Dual-Deck Tempo Glide"
                            subtitle: "Nudge both decks smoothly in lockstep for zero beat drift"
                            MCtrlSwitch {
                                enabled: MixcloudService.mixEnabled && MixcloudService.mixMatchTempo
                                checked: MixcloudService.mixCoupledTempo
                                onToggled: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixCoupledTempo = v;
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "clock"
                            title: "Pre-Cue Lead Time"
                            subtitle: "Seconds before track end to start resolving & buffering Deck B"
                            MCtrlSlider {
                                enabled: MixcloudService.mixEnabled
                                from: 15; to: 60; stepSize: 1
                                value: MixcloudService.mixCueLeadSec
                                valueText: Math.round(MixcloudService.mixCueLeadSec) + " s"
                                onMoved: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixCueLeadSec = Math.round(v);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "activity"
                            title: "PCM Analysis Window"
                            subtitle: "Audio slice duration probed from Track A outro & Track B intro"
                            MCtrlSlider {
                                enabled: MixcloudService.mixEnabled
                                from: 6; to: 20; stepSize: 1
                                value: MixcloudService.mixAnalysisWindowSec
                                valueText: Math.round(MixcloudService.mixAnalysisWindowSec) + " s"
                                onMoved: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixAnalysisWindowSec = Math.round(v);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "gauge"
                            title: "Max Tempo Shift Cap"
                            subtitle: "Skip BPM stretch if track speeds differ by more than this %"
                            MCtrlSlider {
                                enabled: MixcloudService.mixEnabled && MixcloudService.mixMatchTempo
                                from: 0; to: 12; stepSize: 1
                                value: MixcloudService.mixMaxTempoShiftPct
                                valueText: "±" + Math.round(MixcloudService.mixMaxTempoShiftPct) + "%"
                                onMoved: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixMaxTempoShiftPct = Math.round(v);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "refresh"
                            title: "Tempo Glide Release"
                            subtitle: "Seconds to smoothly return Deck B to 1.00x native tempo"
                            MCtrlSlider {
                                enabled: MixcloudService.mixEnabled && MixcloudService.mixMatchTempo
                                from: 4; to: 24; stepSize: 1
                                value: MixcloudService.mixTempoReleaseSec
                                valueText: Math.round(MixcloudService.mixTempoReleaseSec) + " s"
                                onMoved: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixTempoReleaseSec = Math.round(v);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "volume"
                            title: "Max Volume Trim"
                            subtitle: "Maximum automatic loudness adjustment on incoming track"
                            MCtrlSlider {
                                enabled: MixcloudService.mixEnabled && MixcloudService.mixMatchVolume
                                from: 0; to: 12; stepSize: 1
                                value: MixcloudService.mixMaxGainTrimDb
                                valueText: "±" + Math.round(MixcloudService.mixMaxGainTrimDb) + " dB"
                                onMoved: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixMaxGainTrimDb = Math.round(v);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "volume-x"
                            title: "Intro Silence Threshold"
                            subtitle: "Skip leading silence quieter than this level before mixing"
                            MCtrlSlider {
                                enabled: MixcloudService.mixEnabled && MixcloudService.mixMatchOffset
                                from: -55; to: -24; stepSize: 1
                                value: MixcloudService.mixSilenceThresholdDb
                                valueText: Math.round(MixcloudService.mixSilenceThresholdDb) + " dBFS"
                                onMoved: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixSilenceThresholdDb = Math.round(v);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "sliders"
                            title: "Manual Buffer Offset Calibration"
                            subtitle: "Fine-tune Deck B seek compensation (+ later / - earlier)"
                            MCtrlSlider {
                                enabled: MixcloudService.mixEnabled && MixcloudService.mixMatchOffset
                                from: -250; to: 250; stepSize: 10
                                value: MixcloudService.mixManualOffsetMs
                                valueText: root.signedMs(MixcloudService.mixManualOffsetMs)
                                onMoved: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixManualOffsetMs = Math.round(v);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "clock"
                            title: "Minimum Track Duration"
                            subtitle: "Only auto-cue tracks at least this long"
                            MCtrlSlider {
                                enabled: MixcloudService.mixEnabled
                                from: 20; to: 120; stepSize: 5
                                value: MixcloudService.mixMinTrackDurationSec
                                valueText: Math.round(MixcloudService.mixMinTrackDurationSec) + " s"
                                onMoved: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixMinTrackDurationSec = Math.round(v);
                                    MixcloudService.syncMixConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "media-shuffle"
                            title: "Mix on Shuffle / Repeat All"
                            subtitle: "Allow progressive transitions when Shuffle or Repeat All is active"
                            MCtrlSwitch {
                                enabled: MixcloudService.mixEnabled
                                checked: MixcloudService.mixAllowOnShuffle
                                onToggled: (v) => {
                                    MixcloudService.mixPreset = "custom";
                                    MixcloudService.mixAllowOnShuffle = v;
                                    MixcloudService.scheduleSave();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "refresh"
                            title: "Reset Mix Settings"
                            subtitle: "Restore Progressive DJ default configuration"
                            PillButton {
                                text: "Reset Mix"
                                iconName: "refresh"
                                fixedHeight: 28
                                radius: 8
                                onClicked: MixcloudService.applyMixPreset("progressive")
                            }
                        }
                    }
                }

                // ======================================================
                // TAB 3: AUDIO DUCKING (Full Sidechain RMS Controls)
                // ======================================================
                ColumnLayout {
                    id: duckCol
                    width: parent.width
                    spacing: 10
                    opacity: root.activeTab === "ducking" ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    // Live Ducking Status Card (earned Theme.info ONLY while actively ducking)
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: duckStatusRow.implicitHeight + 18
                        radius: 12
                        clip: true
                        color: MixcloudService.isDucking
                            ? Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.14)
                            : Theme.surfaceRaised
                        border.width: 1
                        border.color: MixcloudService.isDucking
                            ? Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.45)
                            : Theme.borderSubtle

                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        RowLayout {
                            id: duckStatusRow
                            anchors.fill: parent
                            anchors.margins: 9
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Rectangle {
                                width: 34
                                height: 34
                                radius: 9
                                color: Theme.cardBg
                                border.width: 1
                                border.color: MixcloudService.isDucking ? Theme.info : Theme.borderSubtle

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: "media-duck"
                                    iconSize: 16
                                    color: MixcloudService.isDucking ? Theme.info : (MixcloudService.autoDuckEnabled ? Theme.accent : Theme.textMuted)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: MixcloudService.isDucking
                                        ? ("Ducking for " + (MixcloudService.duckSource || "External Audio"))
                                        : (MixcloudService.autoDuckEnabled ? "Sidechain Ducking Armed" : "Auto-Ducking Disabled")
                                    color: MixcloudService.isDucking ? Theme.info : Theme.text
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: "Gain " + Math.round(MixcloudService.duckGain * 100) + "% • Target "
                                        + Math.round(MixcloudService.duckLevel * 100) + "% • Monitoring "
                                        + MixcloudService.duckMonitoredCount + " stream(s)"
                                    color: Theme.textSub
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                Layout.preferredHeight: 22
                                Layout.preferredWidth: duckPillLbl.implicitWidth + 14
                                Layout.alignment: Qt.AlignVCenter
                                radius: 11
                                color: MixcloudService.isDucking ? Theme.info : Theme.cardBg
                                border.width: MixcloudService.isDucking ? 0 : 1
                                border.color: Theme.borderSubtle

                                Text {
                                    id: duckPillLbl
                                    anchors.centerIn: parent
                                    text: MixcloudService.isDucking ? "ACTIVE" : (MixcloudService.duckMode === "rms" ? "RMS 4kHz" : "Presence")
                                    color: MixcloudService.isDucking ? "#ffffff" : Theme.textSub
                                    font.family: Theme.fontMono
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                }
                            }
                        }
                    }

                    MSectionLabel { text: "Ducking Presets" }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 8

                        MPresetCard {
                            title: "Gentle"
                            subtitle: "40% music volume • Soft slow restore"
                            iconName: "droplet"
                            active: MixcloudService.duckPreset === "gentle"
                            onTriggered: MixcloudService.applyDuckPreset("gentle")
                        }
                        MPresetCard {
                            title: "Balanced"
                            subtitle: "24% music volume • Hybrid RMS sidechain"
                            iconName: "media-duck"
                            active: MixcloudService.duckPreset === "balanced"
                            onTriggered: MixcloudService.applyDuckPreset("balanced")
                        }
                        MPresetCard {
                            title: "Focus / Call"
                            subtitle: "10% music volume • Long voice hold"
                            iconName: "mic"
                            active: MixcloudService.duckPreset === "focus"
                            onTriggered: MixcloudService.applyDuckPreset("focus")
                        }
                        MPresetCard {
                            title: "Custom"
                            subtitle: "Attack, hold, threshold & app exclusions"
                            iconName: "sliders"
                            active: MixcloudService.duckPreset === "custom"
                            onTriggered: {
                                MixcloudService.applyDuckPreset("custom");
                                duckAdv.expanded = true;
                            }
                        }
                    }

                    MSectionLabel { text: "Ducking Behavior" }

                    MSettingGroup {
                        MSettingRow {
                            showDivider: false
                            iconName: "media-duck"
                            title: "Enable Smart Auto-Ducking"
                            subtitle: "Yield music gracefully when Discord, calls or videos emit sound"
                            MCtrlSwitch {
                                checked: MixcloudService.autoDuckEnabled
                                onToggled: (v) => {
                                    MixcloudService.autoDuckEnabled = v;
                                    if (!v) {
                                        MixcloudService.isDucking = false;
                                        MixcloudService.duckSource = "";
                                        MixcloudService.duckGain = 1.0;
                                    }
                                    MixcloudService.syncDuckingNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "volume"
                            title: "Duck Volume Level"
                            subtitle: "Target music level relative to master volume while ducking"
                            MCtrlSlider {
                                enabled: MixcloudService.autoDuckEnabled
                                from: 8; to: 75; stepSize: 2
                                value: Math.round(MixcloudService.duckLevel * 100)
                                valueText: Math.round(MixcloudService.duckLevel * 100) + "%"
                                onMoved: (v) => {
                                    MixcloudService.duckPreset = "custom";
                                    MixcloudService.duckLevel = Math.max(0.08, Math.min(0.75, v / 100.0));
                                    MixcloudService.syncDuckingNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "activity"
                            title: "Detection Mode"
                            subtitle: "RMS listens to actual audio energy; Presence triggers on any open stream"
                            MCtrlSelect {
                                enabled: MixcloudService.autoDuckEnabled
                                options: ["RMS Audio Level", "Stream Active"]
                                currentText: MixcloudService.duckMode === "presence" ? "Stream Active" : "RMS Audio Level"
                                onSelected: (label) => {
                                    MixcloudService.duckPreset = "custom";
                                    MixcloudService.duckMode = (label === "Stream Active") ? "presence" : "rms";
                                    MixcloudService.syncDuckingNow();
                                }
                            }
                        }
                    }

                    MAdvancedSection {
                        id: duckAdv
                        title: "Advanced Sidechain Timings & Exclusions"
                        subtitle: "Debounce, release hold, fade ramps, dBFS gate & ignored apps"

                        MSettingRow {
                            showDivider: false
                            iconName: "bolt"
                            title: "Attack Debounce"
                            subtitle: "Wait duration before ducking to filter brief UI clicks"
                            MCtrlSlider {
                                enabled: MixcloudService.autoDuckEnabled
                                from: 20; to: 300; stepSize: 10
                                value: MixcloudService.duckAttackMs
                                valueText: MixcloudService.duckAttackMs + " ms"
                                onMoved: (v) => {
                                    MixcloudService.duckPreset = "custom";
                                    MixcloudService.duckAttackMs = Math.round(v);
                                    MixcloudService.syncDuckingNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "clock"
                            title: "Release Hold"
                            subtitle: "Bridge short speech pauses before restoring music volume"
                            MCtrlSlider {
                                enabled: MixcloudService.autoDuckEnabled
                                from: 100; to: 2000; stepSize: 20
                                value: MixcloudService.duckReleaseHoldMs
                                valueText: MixcloudService.duckReleaseHoldMs + " ms"
                                onMoved: (v) => {
                                    MixcloudService.duckPreset = "custom";
                                    MixcloudService.duckReleaseHoldMs = Math.round(v);
                                    MixcloudService.syncDuckingNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "arrow-left"
                            title: "Duck-In Fade Duration"
                            subtitle: "Cosine S-curve fade duration when lowering music"
                            MCtrlSlider {
                                enabled: MixcloudService.autoDuckEnabled
                                from: 80; to: 1000; stepSize: 20
                                value: MixcloudService.duckFadeDownMs
                                valueText: MixcloudService.duckFadeDownMs + " ms"
                                onMoved: (v) => {
                                    MixcloudService.duckPreset = "custom";
                                    MixcloudService.duckFadeDownMs = Math.round(v);
                                    MixcloudService.syncDuckingNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "arrow-right"
                            title: "Restore Fade Duration"
                            subtitle: "Cosine S-curve fade duration when returning to full volume"
                            MCtrlSlider {
                                enabled: MixcloudService.autoDuckEnabled
                                from: 150; to: 2000; stepSize: 25
                                value: MixcloudService.duckFadeUpMs
                                valueText: MixcloudService.duckFadeUpMs + " ms"
                                onMoved: (v) => {
                                    MixcloudService.duckPreset = "custom";
                                    MixcloudService.duckFadeUpMs = Math.round(v);
                                    MixcloudService.syncDuckingNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "gauge"
                            title: "RMS Sensitivity Gate"
                            subtitle: "Ignore background noise quieter than this dBFS threshold"
                            MCtrlSlider {
                                enabled: MixcloudService.autoDuckEnabled && MixcloudService.duckMode === "rms"
                                from: -60; to: -25; stepSize: 1
                                value: MixcloudService.duckRmsThresholdDb
                                valueText: Math.round(MixcloudService.duckRmsThresholdDb) + " dBFS"
                                onMoved: (v) => {
                                    MixcloudService.duckPreset = "custom";
                                    MixcloudService.duckRmsThresholdDb = Math.round(v);
                                    MixcloudService.syncDuckingNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "bell-off"
                            title: "Ignored Apps"
                            subtitle: "Comma-separated PipeWire app names that never trigger ducking"

                            Rectangle {
                                width: 156
                                height: 30
                                radius: 8
                                clip: true
                                color: Theme.pillBg
                                border.width: 1
                                border.color: duckIgnoreInput.activeFocus ? Theme.accent : Theme.borderSubtle
                                Behavior on border.color { ColorAnimation { duration: 140 } }

                                AnimatedTextInput {
                                    id: duckIgnoreInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 9
                                    anchors.rightMargin: 9
                                    verticalAlignment: TextInput.AlignVCenter
                                    textColor: Theme.text
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    clip: true
                                    selectByMouse: true
                                    Component.onCompleted: text = MixcloudService.duckIgnoredApps
                                    Connections {
                                        target: MixcloudService
                                        function onDuckIgnoredAppsChanged() {
                                            if (!duckIgnoreInput.activeFocus && duckIgnoreInput.text !== MixcloudService.duckIgnoredApps) {
                                                duckIgnoreInput.text = MixcloudService.duckIgnoredApps;
                                            }
                                        }
                                    }
                                    onEditingFinished: {
                                        MixcloudService.duckIgnoredApps = text.trim();
                                        MixcloudService.syncDuckingNow();
                                    }
                                    Keys.onReturnPressed: {
                                        MixcloudService.duckIgnoredApps = text.trim();
                                        MixcloudService.syncDuckingNow();
                                        root.duckApplyLabel = "Saved!";
                                        transientResetTimer.restart();
                                        duckIgnoreInput.focus = false;
                                    }

                                    Text {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        text: "e.g. obs, steam"
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        visible: duckIgnoreInput.text === ""
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            PillButton {
                                text: root.duckApplyLabel
                                iconName: root.duckApplyLabel === "Saved!" ? "check" : ""
                                fixedHeight: 30
                                radius: 8
                                onClicked: {
                                    MixcloudService.duckIgnoredApps = duckIgnoreInput.text.trim();
                                    MixcloudService.syncDuckingNow();
                                    root.duckApplyLabel = "Saved!";
                                    transientResetTimer.restart();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "refresh"
                            title: "Reset Ducking Defaults"
                            subtitle: "Restore Balanced sidechain timings & threshold"
                            PillButton {
                                text: "Reset Ducking"
                                iconName: "refresh"
                                fixedHeight: 28
                                radius: 8
                                onClicked: {
                                    MixcloudService.duckIgnoredApps = "";
                                    MixcloudService.applyDuckPreset("balanced");
                                }
                            }
                        }
                    }
                }

                // ======================================================
                // TAB 4: PLAYBACK PREFERENCES
                // ======================================================
                ColumnLayout {
                    id: playbackCol
                    width: parent.width
                    spacing: 10
                    opacity: root.activeTab === "playback" ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    MSectionLabel { text: "Discovery & Library Defaults" }

                    MSettingGroup {
                        MSettingRow {
                            showDivider: false
                            iconName: "globe"
                            title: "Default Discover Genre"
                            subtitle: "Initial Mixcloud genre loaded when launching Music"
                            MCtrlSelect {
                                options: MixcloudService.genres.map(g => g.label)
                                currentText: MixcloudService.genreLabel(MixcloudService.activeGenre)
                                onSelected: (label) => {
                                    for (let i = 0; i < MixcloudService.genres.length; ++i) {
                                        if (MixcloudService.genres[i].label === label) {
                                            MixcloudService.activeGenre = MixcloudService.genres[i].slug;
                                            MixcloudService.scheduleSave();
                                            break;
                                        }
                                    }
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "sort"
                            title: "Default Feed Sort"
                            subtitle: "Order Mixcloud Discover shows by Popular or Latest"
                            MCtrlSelect {
                                options: ["Popular", "Latest"]
                                currentText: MixcloudService.sortMode === "latest" ? "Latest" : "Popular"
                                onSelected: (label) => {
                                    MixcloudService.sortMode = (label === "Latest") ? "latest" : "popular";
                                    MixcloudService.scheduleSave();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "grid"
                            title: "Default View Layout"
                            subtitle: "Card Grid artwork or dense List rows"
                            MCtrlSelect {
                                options: ["Grid", "List"]
                                currentText: MixcloudService.prefListView ? "List" : "Grid"
                                onSelected: (label) => {
                                    MixcloudService.setPrefListView(label === "List");
                                }
                            }
                        }
                    }

                    MSectionLabel { text: "Stream Engine & Transport" }

                    MSettingGroup {
                        MSettingRow {
                            showDivider: false
                            iconName: "clock"
                            title: "Remember Playback Position"
                            subtitle: "Resume last track timestamp across reloads & Quit"
                            MCtrlSwitch {
                                checked: MixcloudService.rememberPosition
                                onToggled: (v) => {
                                    MixcloudService.rememberPosition = v;
                                    MixcloudService.scheduleSave();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "hard-drive"
                            title: "Stream Buffer Cache"
                            subtitle: "Stream readahead buffer budget (applies on next track)"
                            MCtrlSelect {
                                options: ["Low (16 MiB / 10s)", "Balanced (32 MiB / 20s)", "High (64 MiB / 45s)"]
                                currentText: root.bufferLabel(MixcloudService.bufferPreset)
                                onSelected: (label) => {
                                    MixcloudService.bufferPreset = root.bufferId(label);
                                    MixcloudService.syncPlaybackConfigNow();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "music"
                            title: "Pitch-Preserving Tempo Sync"
                            subtitle: "Keep musical key natural when Progressive Mix adjusts BPM speed"
                            MCtrlSwitch {
                                checked: MixcloudService.pitchCorrection
                                onToggled: (v) => {
                                    MixcloudService.pitchCorrection = v;
                                    MixcloudService.syncPlaybackConfigNow();
                                }
                            }
                        }
                    }
                }

                // ======================================================
                // TAB 5: DATA & DIAGNOSTICS
                // ======================================================
                ColumnLayout {
                    id: dataCol
                    width: parent.width
                    spacing: 10
                    opacity: root.activeTab === "data" ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    // Storage & Backend Health Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: healthCol.implicitHeight + 22
                        radius: 12
                        color: Theme.surfaceRaised
                        border.width: 1
                        border.color: Theme.borderSubtle
                        clip: true

                        ColumnLayout {
                            id: healthCol
                            anchors.fill: parent
                            anchors.margins: 11
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: "Music State & Audio Engine"
                                        color: Theme.text
                                        font.family: Theme.fontSans
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: MixcloudService.statePath
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        elide: Text.ElideMiddle
                                    }
                                }

                                Rectangle {
                                    Layout.preferredHeight: 22
                                    Layout.preferredWidth: sizeChipLbl.implicitWidth + 14
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 11
                                    color: Theme.cardBg
                                    border.width: 1
                                    border.color: Theme.borderSubtle

                                    Text {
                                        id: sizeChipLbl
                                        anchors.centerIn: parent
                                        text: MixcloudService.formatBytes(MixcloudService.stateFileSizeBytes)
                                        color: Theme.text
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            // Mono Collection Counters
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Repeater {
                                    model: [
                                        { label: "Queue", val: MixcloudService.queue.length },
                                        { label: "Favorites", val: MixcloudService.favorites.length },
                                        { label: "Recent", val: MixcloudService.recent.length },
                                        { label: "Backups", val: MixcloudService.backupCount }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        height: 44
                                        radius: 9
                                        color: Theme.cardBg
                                        border.width: 1
                                        border.color: Theme.borderSubtle
                                        clip: true

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 1
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: String(modelData.val)
                                                color: Theme.text
                                                font.family: Theme.fontMono
                                                font.pixelSize: 14
                                                font.weight: Font.Bold
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.label
                                                color: Theme.textMuted
                                                font.family: Theme.fontSans
                                                font.pixelSize: 10
                                            }
                                        }
                                    }
                                }
                            }

                            // Audio Engine Readiness Summary (monochrome at rest, fault-only semantic tint)
                            Rectangle {
                                id: engineSummaryBar
                                readonly property int readyCount: (MixcloudService.hasMpv ? 1 : 0)
                                    + (MixcloudService.hasYtDlp ? 1 : 0)
                                    + (MixcloudService.hasFfmpeg ? 1 : 0)
                                    + (MixcloudService.hasPactl ? 1 : 0)
                                    + (MixcloudService.hasParec ? 1 : 0)
                                readonly property bool allReady: readyCount === 5
                                readonly property bool degraded: MixcloudService.depsChecked && !allReady

                                Layout.fillWidth: true
                                height: 32
                                radius: 9
                                clip: true
                                color: degraded
                                    ? Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.10)
                                    : Theme.cardBg
                                border.width: 1
                                border.color: degraded
                                    ? Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.35)
                                    : Theme.borderSubtle
                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    SvgIcon {
                                        sourceName: !MixcloudService.depsChecked
                                            ? "activity"
                                            : (engineSummaryBar.allReady ? "check" : "alert-triangle")
                                        iconSize: 13
                                        color: !MixcloudService.depsChecked
                                            ? Theme.textMuted
                                            : (engineSummaryBar.allReady ? Theme.textSub : Theme.warn)
                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: !MixcloudService.depsChecked
                                            ? "Checking audio components..."
                                            : (engineSummaryBar.allReady
                                                ? "All audio components ready"
                                                : (MixcloudService.depsReady
                                                    ? "Core playback ready — some mixing or ducking features limited"
                                                    : "Audio playback unavailable — required components missing"))
                                        color: engineSummaryBar.degraded ? Theme.warn : Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    }

                                    Text {
                                        visible: MixcloudService.depsChecked
                                        text: engineSummaryBar.readyCount + "/5"
                                        color: engineSummaryBar.degraded ? Theme.warn : Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }

                    MSectionLabel { text: "Library Data" }

                    MSettingGroup {
                        MSettingRow {
                            showDivider: false
                            iconName: "list"
                            title: "Clear Up Next Queue"
                            subtitle: MixcloudService.queue.length + " queued mix(es)"
                            PillButton {
                                text: root.confirmAction === "queue" ? "Confirm?" : "Clear Queue"
                                iconName: root.confirmAction === "queue" ? "check" : "trash"
                                danger: true
                                active: root.confirmAction === "queue"
                                enabled: MixcloudService.queue.length > 0
                                fixedHeight: 28
                                radius: 8
                                onClicked: root.requestTwoStepAction("queue", () => MixcloudService.clearQueue())
                            }
                        }

                        MSettingRow {
                            iconName: "clock"
                            title: "Clear Recently Played"
                            subtitle: MixcloudService.recent.length + " history item(s)"
                            PillButton {
                                text: root.confirmAction === "recent" ? "Confirm?" : "Clear History"
                                iconName: root.confirmAction === "recent" ? "check" : "trash"
                                danger: true
                                active: root.confirmAction === "recent"
                                enabled: MixcloudService.recent.length > 0
                                fixedHeight: 28
                                radius: 8
                                onClicked: root.requestTwoStepAction("recent", () => MixcloudService.clearRecent())
                            }
                        }

                        MSettingRow {
                            iconName: "star"
                            title: "Clear Favorites"
                            subtitle: MixcloudService.favorites.length + " saved favorite(s)"
                            PillButton {
                                text: root.confirmAction === "favorites" ? "Confirm?" : "Clear Favorites"
                                iconName: root.confirmAction === "favorites" ? "check" : "trash"
                                danger: true
                                active: root.confirmAction === "favorites"
                                enabled: MixcloudService.favorites.length > 0
                                fixedHeight: 28
                                radius: 8
                                onClicked: root.requestTwoStepAction("favorites", () => MixcloudService.clearFavorites())
                            }
                        }
                    }

                    MSectionLabel { text: "Backup & Diagnostics" }

                    MSettingGroup {
                        MSettingRow {
                            showDivider: false
                            iconName: "copy"
                            title: "Copy State JSON"
                            subtitle: "Copy settings, queue & favorites snapshot to clipboard"
                            PillButton {
                                text: root.jsonCopied ? "Copied!" : "Copy JSON"
                                iconName: root.jsonCopied ? "check" : "copy"
                                fixedHeight: 28
                                radius: 8
                                onClicked: {
                                    FileService.copyToClipboard(MixcloudService.getExportJson());
                                    root.jsonCopied = true;
                                    transientResetTimer.restart();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "download"
                            title: "Export & Restore Backup"
                            subtitle: MixcloudService.lastBackupStatus !== ""
                                ? MixcloudService.lastBackupStatus
                                : "Save timestamped snapshot to ~/.config/paithosh/backups"

                            PillButton {
                                text: "Backup"
                                iconName: "download"
                                fixedHeight: 28
                                radius: 8
                                onClicked: MixcloudService.exportBackup()
                            }

                            PillButton {
                                text: "Restore Latest"
                                iconName: "restore"
                                enabled: MixcloudService.backupCount > 0
                                fixedHeight: 28
                                radius: 8
                                onClicked: MixcloudService.restoreLatestBackup()
                            }
                        }

                        MSettingRow {
                            iconName: "refresh"
                            title: "Recheck Audio Engine"
                            subtitle: "Verify playback, streaming, mixing & ducking components"
                            PillButton {
                                text: "Recheck"
                                iconName: "refresh"
                                fixedHeight: 28
                                radius: 8
                                onClicked: {
                                    MixcloudService.recheckDeps();
                                    MixcloudService.refreshStateDiagnostics();
                                }
                            }
                        }

                        MSettingRow {
                            iconName: "alert-triangle"
                            title: "Reset Music Settings"
                            subtitle: "Restore EQ, Mix, Ducking & Playback defaults (keeps Favorites)"
                            PillButton {
                                text: root.confirmAction === "resetAll" ? "Confirm Reset?" : "Reset Settings"
                                iconName: root.confirmAction === "resetAll" ? "check" : "refresh"
                                danger: true
                                active: root.confirmAction === "resetAll"
                                fixedHeight: 28
                                radius: 8
                                onClicked: root.requestTwoStepAction("resetAll", () => MixcloudService.resetAllSettings())
                            }
                        }
                    }
                }
            }
        }
    }
}
