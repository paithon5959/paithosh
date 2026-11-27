import QtQuick
import QtQuick.Effects
import "../.."

Item {
    id: root

    property string sourceName: ""
    property int iconSize: 16
    property color color: Theme.text
    property bool preserveColor: false

    readonly property bool _isMonochromeWhite: root.color.r >= 0.92 && root.color.g >= 0.92 && root.color.b >= 0.92
    readonly property bool _useDirectImg: root.preserveColor || (Theme.reduceMotion && _isMonochromeWhite)

    implicitWidth: iconSize
    implicitHeight: iconSize
    width: iconSize
    height: iconSize

    Image {
        id: img
        anchors.fill: parent
        source: root.sourceName ? Qt.resolvedUrl("../../assets/icons/" + root.sourceName + ".svg") : ""
        sourceSize.width: Theme.reduceMotion ? root.iconSize : root.iconSize * 2
        sourceSize.height: Theme.reduceMotion ? root.iconSize : root.iconSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: (Theme.reduceMotion && !root.preserveColor && root._isMonochromeWhite) ? root.color.a : 1.0
        visible: root._useDirectImg && root.sourceName !== ""
    }

    Loader {
        anchors.fill: img
        active: !Theme.reduceMotion && !root.preserveColor && root.sourceName !== ""
        sourceComponent: MultiEffect {
            source: img
            colorization: 1.0
            colorizationColor: root.color
        }
    }

    Loader {
        anchors.fill: img
        active: Theme.reduceMotion && !root.preserveColor && !root._isMonochromeWhite && root.sourceName !== ""
        sourceComponent: ShaderEffect {
            fragmentShader: Qt.resolvedUrl("../../assets/shaders/icon_tint.frag.qsb")
            property var source: img
            property color tintColor: root.color
        }
    }
}
