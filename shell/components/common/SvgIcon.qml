import QtQuick
import QtQuick.Effects
import "../.."

Item {
    id: root

    property string sourceName: ""
    property int iconSize: 16
    property color color: Theme.text

    implicitWidth: iconSize
    implicitHeight: iconSize
    width: iconSize
    height: iconSize

    Image {
        id: img
        anchors.fill: parent
        source: root.sourceName ? Qt.resolvedUrl("../../assets/icons/" + root.sourceName + ".svg") : ""
        sourceSize.width: root.iconSize * 2
        sourceSize.height: root.iconSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: false
    }

    MultiEffect {
        anchors.fill: img
        source: img
        colorization: 1.0
        colorizationColor: root.color
        visible: root.sourceName !== ""
    }
}
