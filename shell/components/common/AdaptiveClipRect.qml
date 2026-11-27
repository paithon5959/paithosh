import QtQuick
import QtQuick.Effects
import "../.."

Rectangle {
    id: root

    property bool contentInsideBorder: true
    default property alias contentData: contentItem.data
    readonly property alias contentItem: contentItem

    clip: true

    Item {
        id: maskItem
        anchors.fill: contentItem
        visible: false
        layer.enabled: !Theme.reduceMotion && root.radius > 0

        Rectangle {
            anchors.fill: parent
            radius: Math.max(0, root.radius - (root.contentInsideBorder ? root.border.width : 0))
            color: "#ffffff"
        }
    }

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: root.contentInsideBorder ? root.border.width : 0
        clip: true
        layer.enabled: !Theme.reduceMotion && root.radius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskItem
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.5
        }
    }
}
