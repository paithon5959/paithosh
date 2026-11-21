import QtQuick
import ".."

Item {
    id: root

    property bool open: false
    property int maxSlotWidth: 340
    property int spacing: 0
    default property alias content: inner.data

    clip: true
    implicitHeight: Theme.islandHeight
    implicitWidth: open ? Math.min(maxSlotWidth, Math.ceil(inner.implicitWidth)) : 0
    opacity: open ? 1.0 : 0.0
    scale: open ? 1.0 : 0.90
    visible: implicitWidth > 0.5 || opacity > 0.01

    Behavior on implicitWidth {
        NumberAnimation {
            duration: root.open ? Theme.springMs : Theme.smoothMs
            easing.type: root.open ? Easing.OutBack : Easing.OutCubic
            easing.overshoot: 0.75
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: root.open ? 240 : 160
            easing.type: Easing.OutCubic
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: root.open ? Theme.springMs : 200
            easing.type: root.open ? Easing.OutBack : Easing.OutCubic
            easing.overshoot: 1.15
        }
    }

    Row {
        id: inner
        anchors.centerIn: parent
        spacing: root.spacing
    }
}
