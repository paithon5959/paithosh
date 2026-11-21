import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root
    anchors.fill: parent
    visible: isOpen || menuBox.opacity > 0.01
    z: 90

    property bool isOpen: false
    property var items: [] // [{ text, icon, separator, enabled, danger, checked, action }]
    property real menuWidth: 196
    property real targetX: 0
    property real targetY: 0

    function openAt(px, py, menuItems) {
        if (menuItems !== undefined) items = menuItems;
        const maxX = Math.max(8, width - menuWidth - 8);
        const estH = Math.min(460, (items ? items.length : 1) * 28 + 12);
        const maxY = Math.max(8, height - estH - 8);
        targetX = Math.max(8, Math.min(px, maxX));
        targetY = Math.max(8, Math.min(py, maxY));
        isOpen = true;
    }

    function close() {
        isOpen = false;
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.isOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.close()
    }

    Rectangle {
        id: menuBox
        x: root.targetX
        y: root.targetY
        width: root.menuWidth
        height: Math.min(460, menuCol.implicitHeight + 10)
        radius: 12
        color: "#121214"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        opacity: root.isOpen ? 1.0 : 0.0
        scale: root.isOpen ? 1.0 : 0.95
        transformOrigin: Item.TopLeft
        clip: true

        transform: Translate {
            y: root.isOpen ? 0 : -4
            Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }

        Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            onClicked: function(m) { m.accepted = true; }
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 5
            contentWidth: width
            contentHeight: menuCol.implicitHeight
            clip: true

            ColumnLayout {
                id: menuCol
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.items
                    delegate: Item {
                        required property var modelData
                        readonly property bool isSep: modelData.separator === true
                        readonly property bool isEnabled: modelData.enabled !== false
                        Layout.fillWidth: true
                        Layout.preferredHeight: isSep ? 7 : 27

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
                            color: (isEnabled && itemMouse.containsMouse) ? Theme.cardHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 110 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    visible: (modelData.icon || "") !== ""
                                    text: modelData.icon || ""
                                    color: modelData.danger ? Theme.danger : (isEnabled ? Theme.textSub : Theme.textMuted)
                                    font.pixelSize: 12
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.text || ""
                                    color: !isEnabled ? Theme.textMuted : (modelData.danger ? Theme.danger : Theme.text)
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: modelData.checked ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: modelData.checked === true
                                    text: "✓"
                                    color: Theme.accent
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: isEnabled
                                cursorShape: isEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
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
