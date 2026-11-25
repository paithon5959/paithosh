import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property string text: ""
    property string iconName: ""
    property int iconSize: 14
    property bool active: false
    property bool subtle: false
    property bool danger: false
    property color textColorOverride: "transparent"
    property color bgOverride: "transparent"
    property int horizontalPadding: 12
    property int verticalPadding: 6
    property int fixedWidth: 0
    property int fixedHeight: 0
    property int radius: 10
    property int fontSize: 12
    property int fontWeight: Font.DemiBold
    property bool fillWidth: false

    signal clicked()

    implicitWidth: fixedWidth > 0 ? fixedWidth : (contentRow.implicitWidth + horizontalPadding * 2)
    implicitHeight: fixedHeight > 0 ? fixedHeight : Math.max(28, contentRow.implicitHeight + verticalPadding * 2)
    Layout.fillWidth: fillWidth

    opacity: root.enabled ? 1.0 : 0.36
    scale: (root.enabled && mouseArea.pressed) ? 0.94 : 1.0

    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutBack
            easing.overshoot: Theme.springOvershoot
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.radius
        clip: true
        color: {
            if (root.danger && root.active) {
                return (root.enabled && mouseArea.containsMouse) ? Qt.darker(Theme.danger, 1.12) : Theme.danger;
            }
            if (root.active) return Theme.accent;
            if (root.enabled && mouseArea.containsMouse) {
                if (root.danger) return Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.18);
                return root.subtle ? Theme.cardBg : Theme.cardHover;
            }
            if (root.bgOverride.a > 0) return root.bgOverride;
            return root.subtle ? "transparent" : Theme.cardBg;
        }
        border.width: (root.subtle && (!root.enabled || !mouseArea.containsMouse) && !root.active) ? 0 : (root.active && !root.danger ? 0 : 1)
        border.color: {
            if (root.danger && root.active) return Theme.danger;
            if (root.danger) return Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.35);
            if (root.subtle && mouseArea.containsMouse && root.enabled) return Theme.borderSubtle;
            return Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08);
        }

        Behavior on color {
            ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on border.color {
            ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        ThemeGradientFill {
            anchors.fill: parent
            enabled: root.active && !root.danger && Theme.accentGradientEnabled
            color1: Theme.accent
            colorMid: Theme.accentMid
            color2: Theme.accent2
            cornerRadius: root.radius
        }

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            width: Math.min(implicitWidth, Math.max(0, parent.width - (root.fixedWidth > 0 ? 4 : root.horizontalPadding * 2)))
            spacing: (root.iconName !== "" && root.text !== "") ? 6 : 0

            SvgIcon {
                visible: root.iconName !== ""
                sourceName: root.iconName
                iconSize: root.iconSize
                color: label.color
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                id: label
                visible: root.text !== ""
                text: root.text
                font.family: Theme.fontSans
                font.pixelSize: root.fontSize
                font.weight: root.fontWeight
                color: {
                    if (root.textColorOverride.a > 0) return root.textColorOverride;
                    if (root.danger && root.active) return "#ffffff";
                    if (root.danger) return Theme.dangerText;
                    if (root.active) return Theme.accentFg;
                    return Theme.text;
                }
                elide: Text.ElideRight
                Layout.fillWidth: root.fillWidth
                Layout.minimumWidth: 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
