import QtQuick
import "../.."

Item {
    id: root

    property bool enabled: false
    property color color1: Theme.pillBg
    property color colorMid: Qt.rgba((color1.r + color2.r) * 0.5, (color1.g + color2.g) * 0.5, (color1.b + color2.b) * 0.5, (color1.a + color2.a) * 0.5)
    property color color2: Theme.pillBg2
    property real angle: Theme.gradientAngle
    property real cornerRadius: 0

    visible: enabled && !Theme.reduceMotion && width > 0 && height > 0

    Loader {
        anchors.fill: parent
        active: root.visible
        sourceComponent: ShaderEffect {
            fragmentShader: Qt.resolvedUrl("../../assets/shaders/theme_gradient.frag.qsb")
            property size size: Qt.size(width, height)
            property real cornerRadius: root.cornerRadius
            property real angleRad: root.angle * Math.PI / 180.0
            property color color1: root.color1
            property color colorMid: root.colorMid
            property color color2: root.color2
        }
    }
}
