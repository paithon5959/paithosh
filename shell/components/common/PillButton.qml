import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property string text: ""
    property string iconName: ""
    property int iconSize: 14
    property bool active: false
    property bool danger: false
    property color textColorOverride: "transparent"
    property int horizontalPadding: 12
    property int verticalPadding: 6
    property int radius: 10
    property int fontSize: 12
    property int fontWeight: Font.DemiBold
    property bool fillWidth: false

    signal clicked()

    implicitWidth: contentRow.implicitWidth + horizontalPadding * 2
    implicitHeight: Math.max(28, contentRow.implicitHeight + verticalPadding * 2)
    Layout.fillWidth: fillWidth

    scale: mouseArea.pressed ? 0.94 : (mouseArea.containsMouse ? 1.0 : 1.0)

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
            if (root.active) return Theme.accent;
            if (mouseArea.containsMouse) return Theme.cardHover;
            return Theme.cardBg;
        }

        Behavior on color {
            ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            width: Math.min(implicitWidth, Math.max(0, parent.width - root.horizontalPadding * 2))
            spacing: 6

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
                    if (root.danger) return Theme.danger;
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
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
