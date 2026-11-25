import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../.."

Item {
    id: root
    anchors.fill: parent
    visible: isOpen || menuBox.opacity > 0.01
    z: 90

    property bool isOpen: false
    property var items: [] // [{ text, iconName, icon, shortcut, separator, enabled, danger, checked, action }]
    property real menuWidth: 210
    property real targetX: 0
    property real targetY: 0
    property bool openFlipX: false
    property bool openFlipY: false
    property int highlightedIndex: -1

    signal closed()

    readonly property bool hasAnyIcon: {
        const arr = root.items || [];
        for (let i = 0; i < arr.length; ++i) {
            const it = arr[i];
            if (it && !it.separator && ((it.iconName || "") !== "" || (it.icon || "") !== "")) {
                return true;
            }
        }
        return false;
    }

    function openAt(px, py, menuItems) {
        if (menuItems !== undefined) items = menuItems;
        const arr = items || [];
        let estH = 12;
        for (let i = 0; i < arr.length; ++i) {
            const it = arr[i];
            estH += (it && it.separator) ? 9 : 30;
            if (i > 0) estH += 2;
        }
        estH = Math.min(460, Math.max(42, estH));

        const flipX = (px + menuWidth + 8) > width;
        const flipY = (py + estH + 8) > height;
        openFlipX = flipX;
        openFlipY = flipY;

        const maxX = Math.max(8, width - menuWidth - 8);
        const maxY = Math.max(8, height - estH - 8);
        const rawX = flipX ? (px - menuWidth) : px;
        const rawY = flipY ? (py - estH) : py;
        targetX = Math.max(8, Math.min(rawX, maxX));
        targetY = Math.max(8, Math.min(rawY, maxY));
        highlightedIndex = -1;
        menuFlick.contentY = 0;
        isOpen = true;
        menuBox.forceActiveFocus();
    }

    function close() {
        if (!isOpen) return;
        isOpen = false;
        highlightedIndex = -1;
        closed();
    }

    function stepHighlight(delta) {
        const arr = root.items || [];
        if (arr.length === 0) return;
        let idx = highlightedIndex;
        for (let tries = 0; tries < arr.length; ++tries) {
            if (idx < 0) idx = delta > 0 ? 0 : arr.length - 1;
            else idx = (idx + delta + arr.length) % arr.length;
            const it = arr[idx];
            if (it && it.separator !== true && it.enabled !== false) {
                highlightedIndex = idx;
                return;
            }
        }
    }

    function triggerHighlighted() {
        const arr = root.items || [];
        if (highlightedIndex < 0 || highlightedIndex >= arr.length) return;
        const it = arr[highlightedIndex];
        if (!it || it.separator === true || it.enabled === false) return;
        root.close();
        if (it.action) it.action();
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.isOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: root.close()
    }

    // Subtle Elevation Halo
    Rectangle {
        x: menuBox.x - 4
        y: menuBox.y - 2
        width: menuBox.width + 8
        height: menuBox.height + 8
        radius: menuBox.radius + 3
        color: Qt.rgba(0, 0, 0, 0.36)
        opacity: menuBox.opacity * 0.9
        scale: menuBox.scale
        transformOrigin: menuBox.transformOrigin
        transform: Translate {
            y: menuTrans.y
        }
    }

    Rectangle {
        id: menuBox
        x: root.targetX
        y: root.targetY
        width: root.menuWidth
        height: Math.min(460, menuCol.implicitHeight + 12)
        radius: 12
        color: Theme.pillBg
        border.width: 1
        border.color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.18)
        opacity: root.isOpen ? 1.0 : 0.0
        scale: root.isOpen ? 1.0 : 0.94
        transformOrigin: root.openFlipY
            ? (root.openFlipX ? Item.BottomRight : Item.BottomLeft)
            : (root.openFlipX ? Item.TopRight : Item.TopLeft)
        clip: true
        focus: root.isOpen

        transform: Translate {
            id: menuTrans
            y: root.isOpen ? 0 : (root.openFlipY ? 4 : -4)
            Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }

        ThemeGradientFill {
            anchors.fill: parent
            anchors.margins: 1
            enabled: Theme.shellGradientEnabled
            color1: Theme.pillBg
            colorMid: Theme.pillBgMid
            color2: Theme.pillBg2
            cornerRadius: 11
        }

        Keys.onPressed: (event) => {
            if (!root.isOpen) return;
            if (event.key === Qt.Key_Escape) {
                root.close();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                root.stepHighlight(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                root.stepHighlight(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.triggerHighlighted();
                event.accepted = true;
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(m) { m.accepted = true; }
        }

        Flickable {
            id: menuFlick
            anchors.fill: parent
            anchors.margins: 6
            contentWidth: width
            contentHeight: menuCol.implicitHeight
            clip: true

            ScrollBar.vertical: ScrollBar {
                policy: menuFlick.contentHeight > menuFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                width: 4
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.25)
                }
            }

            ColumnLayout {
                id: menuCol
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.items
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property bool isSep: modelData.separator === true
                        readonly property bool isEnabled: modelData.enabled !== false
                        readonly property bool isDanger: modelData.danger === true
                        readonly property bool isHovered: isEnabled && (itemMouse.containsMouse || root.highlightedIndex === index)
                        readonly property color fgColor: {
                            if (!isEnabled) return Theme.textMuted;
                            if (isDanger) return Theme.dangerText;
                            return Theme.text;
                        }
                        readonly property color iconColor: {
                            if (!isEnabled) return Theme.textMuted;
                            if (isDanger) return Theme.dangerText;
                            return isHovered ? Theme.text : Theme.textSub;
                        }
                        Layout.fillWidth: true
                        Layout.preferredHeight: isSep ? 9 : 30

                        Rectangle {
                            visible: isSep
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            height: 1
                            color: Theme.borderSubtle
                        }

                        Rectangle {
                            visible: !isSep
                            anchors.fill: parent
                            radius: 8
                            color: {
                                if (!isHovered) return "transparent";
                                if (isDanger) return Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.16);
                                return Theme.cardHover;
                            }
                            scale: (isEnabled && itemMouse.pressed) ? 0.97 : 1.0
                            Behavior on color { ColorAnimation { duration: 110; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: 1.0 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                spacing: 8

                                Item {
                                    visible: root.hasAnyIcon
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    Layout.alignment: Qt.AlignVCenter

                                    SvgIcon {
                                        anchors.centerIn: parent
                                        visible: (modelData.iconName || "") !== ""
                                        sourceName: modelData.iconName || ""
                                        iconSize: 14
                                        color: iconColor
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: (modelData.iconName || "") === "" && (modelData.icon || "") !== ""
                                        text: modelData.icon || ""
                                        color: iconColor
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: modelData.text || ""
                                    color: fgColor
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: modelData.checked ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    visible: (modelData.shortcut || "") !== "" && modelData.checked !== true
                                    text: modelData.shortcut || ""
                                    color: !isEnabled ? Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.5) : Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    verticalAlignment: Text.AlignVCenter
                                }

                                SvgIcon {
                                    visible: modelData.checked === true
                                    sourceName: "check"
                                    iconSize: 13
                                    color: Theme.accent
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: isEnabled
                                cursorShape: isEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onEntered: if (isEnabled) root.highlightedIndex = index
                                onClicked: {
                                    root.close();
                                    if (modelData.action) modelData.action();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
