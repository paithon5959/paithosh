import QtQuick
import QtQuick.Layouts
import ".."
import "../services"
import "tabs"

Item {
    id: root

    required property var shellState

    readonly property string activeTab: shellState.dashboardTab
    readonly property int targetWidth: activeTab === "tasks" ? 468 : 408

    implicitWidth: targetWidth
    implicitHeight: tabBar.height + 12 + activeContentHeight

    readonly property real activeContentHeight: {
        if (activeTab === "tasks") return tasksTab.implicitHeight;
        if (activeTab === "kde") return kdeTab.implicitHeight;
        if (activeTab === "power") return powerTab.implicitHeight;
        return missionTab.implicitHeight;
    }

    onVisibleChanged: TelemetryService.setMonitorActive(visible && activeTab === "tasks")
    onActiveTabChanged: {
        TelemetryService.setMonitorActive(visible && activeTab === "tasks");
        if (activeTab === "tasks") tasksTab.animateSparklines();
    }

    // 4-Column Equal Tab Bar
    Rectangle {
        id: tabBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36
        radius: 14
        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.06)
        border.width: 1
        border.color: Theme.borderSubtle
        clip: true

        GridLayout {
            anchors.fill: parent
            anchors.margins: 4
            columns: 4
            columnSpacing: 4

            Repeater {
                model: [
                    { key: "mission", label: "Mission Control" },
                    { key: "tasks", label: "Task Manager" },
                    { key: "kde", label: "KDE Connect" },
                    { key: "power", label: "Power Station" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool isSelected: root.activeTab === modelData.key

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    radius: 10
                    clip: true
                    color: isSelected ? Theme.accent : (tabMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.08) : "transparent")
                    scale: tabMouse.pressed ? 0.94 : 1.0

                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.label
                        color: isSelected ? Theme.accentFg : (tabMouse.containsMouse ? Theme.text : Theme.textSub)
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight

                        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.shellState.dashboardTab = modelData.key
                    }
                }
            }
        }
    }

    // Tab Panels Container
    Item {
        id: panelsArea
        anchors.top: tabBar.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true

        MissionControlTab {
            id: missionTab
            shellState: root.shellState
            width: parent.width
            opacity: root.activeTab === "mission" ? 1.0 : 0.0
            y: root.activeTab === "mission" ? 0 : 8
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
        }

        TaskManagerTab {
            id: tasksTab
            width: parent.width
            opacity: root.activeTab === "tasks" ? 1.0 : 0.0
            y: root.activeTab === "tasks" ? 0 : 8
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
        }

        KdeConnectTab {
            id: kdeTab
            width: parent.width
            opacity: root.activeTab === "kde" ? 1.0 : 0.0
            y: root.activeTab === "kde" ? 0 : 8
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
        }

        PowerStationTab {
            id: powerTab
            width: parent.width
            opacity: root.activeTab === "power" ? 1.0 : 0.0
            y: root.activeTab === "power" ? 0 : 8
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
        }
    }
}
