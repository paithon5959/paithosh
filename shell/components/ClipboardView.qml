import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../services"
import "common"

Item {
    id: root

    required property var shellState

    property string selectedFilter: "All"
    property string query: ""
    property var filteredEntries: []
    property int sel: 0

    readonly property var filterTabs: ["All", "Pinned", "Text", "Links", "Images"]

    implicitWidth: 580
    implicitHeight: {
        const listH = filteredEntries.length === 0
            ? 96
            : Math.min(340, filteredEntries.length * 56 + Math.max(0, filteredEntries.length - 1) * 6);
        return 42 + 10 + 30 + 10 + listH;
    }

    Behavior on implicitHeight {
        NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
    }

    function refreshList() {
        filteredEntries = ClipboardService.search(query, selectedFilter);
        if (sel >= filteredEntries.length) sel = Math.max(0, filteredEntries.length - 1);
    }

    function resetAndFocus() {
        query = "";
        searchBox.text = "";
        selectedFilter = "All";
        sel = 0;
        ClipboardService.refresh();
        refreshList();
        focusTimer.restart();
    }

    function moveSel(delta) {
        const n = filteredEntries.length;
        if (n === 0) return;
        sel = Math.max(0, Math.min(n - 1, sel + delta));
        listView.positionViewAtIndex(sel, ListView.Contain);
    }

    function activateSelected() {
        if (sel < 0 || sel >= filteredEntries.length) return;
        const item = filteredEntries[sel];
        ClipboardService.copyEntry(item.id);
        shellState.closePopover();
    }

    Connections {
        target: ClipboardService
        function onEntriesChanged() {
            root.refreshList();
        }
    }

    Timer {
        id: focusTimer
        interval: 40
        onTriggered: searchBox.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Search & Clear All row
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredHeight: 42
                radius: 14
                color: Theme.cardBg
                border.color: searchBox.activeFocus ? Qt.rgba(1, 1, 1, 0.32) : Theme.borderSubtle
                border.width: 1
                clip: true

                Behavior on border.color {
                    ColorAnimation { duration: Theme.smoothMs }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    SvgIcon {
                        sourceName: "search"
                        iconSize: 16
                        color: Theme.textSub
                    }

                    AnimatedTextInput {
                        id: searchBox
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        textColor: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Search clipboard history..."
                            color: Theme.textMuted
                            font: searchBox.font
                            visible: searchBox.text.length === 0
                        }
                        onTextChanged: {
                            root.query = text;
                            root.sel = 0;
                            root.refreshList();
                        }
                        Keys.onUpPressed: root.moveSel(-1)
                        Keys.onDownPressed: root.moveSel(1)
                        Keys.onReturnPressed: root.activateSelected()
                        Keys.onEnterPressed: root.activateSelected()
                        Keys.onEscapePressed: root.shellState.closePopover()
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                                if (root.sel >= 0 && root.sel < root.filteredEntries.length) {
                                    ClipboardService.togglePin(root.filteredEntries[root.sel].id);
                                }
                                event.accepted = true;
                            }
                        }
                    }

                    Text {
                        visible: root.filteredEntries.length > 0
                        text: root.filteredEntries.length + " items"
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
            }

            // Clear All button
            Rectangle {
                id: clearBtn
                Layout.preferredWidth: 76
                Layout.preferredHeight: 42
                radius: 14
                clip: true
                color: clearMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                border.color: clearMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.28) : Theme.borderSubtle
                border.width: 1
                scale: clearMouse.pressed ? 0.93 : 1.0

                Behavior on color { ColorAnimation { duration: Theme.smoothMs } }
                Behavior on border.color { ColorAnimation { duration: Theme.smoothMs } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                Text {
                    anchors.centerIn: parent
                    text: "Clear"
                    color: clearMouse.containsMouse ? Theme.text : Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Behavior on color { ColorAnimation { duration: Theme.smoothMs } }
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ClipboardService.clearAll()
                }
            }
        }

        // Filter tabs
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 6

            Repeater {
                model: root.filterTabs
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool active: root.selectedFilter === modelData

                    Layout.preferredHeight: 28
                    Layout.preferredWidth: tabLabel.implicitWidth + 24
                    radius: 14
                    clip: true
                    color: active ? Theme.accent : (tabMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                    border.color: active ? Theme.accent : Theme.borderSubtle
                    border.width: 1
                    scale: tabMouse.pressed ? 0.93 : 1.0

                    Behavior on color { ColorAnimation { duration: Theme.smoothMs } }
                    Behavior on border.color { ColorAnimation { duration: Theme.smoothMs } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                    Text {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: modelData
                        color: active ? Theme.accentFg : Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        font.weight: active ? Font.DemiBold : Font.Medium
                        Behavior on color { ColorAnimation { duration: Theme.smoothMs } }
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedFilter = modelData;
                            root.sel = 0;
                            root.refreshList();
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "Enter copy • Ctrl+P pin"
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
        }

        // Clipboard entries list
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: listView
                anchors.fill: parent
                spacing: 6
                clip: true
                model: root.filteredEntries
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: rowWrapper
                    required property var modelData
                    required property int index

                    property bool removing: false
                    readonly property bool selected: index === root.sel
                    readonly property bool pinned: ClipboardService.isPinned(modelData.id)

                    width: listView.width
                    height: removing ? 0 : 56
                    opacity: removing ? 0 : 1
                    scale: removing ? 0.92 : (rowMouse.pressed ? 0.97 : 1.0)
                    clip: true

                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                    Timer {
                        id: removeTimer
                        interval: 185
                        onTriggered: ClipboardService.deleteEntry(rowWrapper.modelData.rawLine, rowWrapper.modelData.id)
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        clip: true
                        color: rowWrapper.selected
                            ? Qt.rgba(1, 1, 1, 0.14)
                            : (rowMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                        border.color: rowWrapper.selected
                            ? Qt.rgba(1, 1, 1, 0.30)
                            : (rowWrapper.pinned ? Qt.rgba(1, 1, 1, 0.22) : Theme.borderSubtle)
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: Theme.smoothMs } }
                        Behavior on border.color { ColorAnimation { duration: Theme.smoothMs } }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.sel = rowWrapper.index
                            onClicked: {
                                ClipboardService.copyEntry(rowWrapper.modelData.id);
                                root.shellState.closePopover();
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 10

                            // Kind badge or color swatch
                            Rectangle {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 24
                                radius: 8
                                clip: true
                                color: rowWrapper.modelData.kind === "color"
                                    ? rowWrapper.modelData.preview.trim()
                                    : Qt.rgba(1, 1, 1, 0.08)
                                border.color: Theme.borderSubtle
                                border.width: 1

                                Text {
                                    visible: rowWrapper.modelData.kind !== "color"
                                    anchors.centerIn: parent
                                    text: {
                                        const k = rowWrapper.modelData.kind;
                                        if (k === "image") return "IMG";
                                        if (k === "url") return "URL";
                                        if (k === "code") return "CODE";
                                        return "TXT";
                                    }
                                    color: Theme.textSub
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }

                            // Preview text (strictly contained)
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: rowWrapper.modelData.preview.replace(/\s+/g, " ").trim()
                                    color: Theme.text
                                    font.family: rowWrapper.modelData.kind === "code" ? Theme.fontMono : Theme.fontSans
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: (rowWrapper.pinned ? "Pinned • " : "") + "#" + rowWrapper.modelData.id
                                    color: Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            // Pin button
                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 9
                                clip: true
                                color: rowWrapper.pinned
                                    ? Theme.accent
                                    : (pinMouse.containsMouse ? Theme.cardHover : Qt.rgba(1, 1, 1, 0.05))
                                scale: pinMouse.pressed ? 0.90 : 1.0

                                Behavior on color { ColorAnimation { duration: Theme.smoothMs } }
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: "bolt"
                                    iconSize: 13
                                    color: rowWrapper.pinned ? Theme.accentFg : Theme.textSub
                                }

                                MouseArea {
                                    id: pinMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ClipboardService.togglePin(rowWrapper.modelData.id)
                                }
                            }

                            // Delete button
                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 9
                                clip: true
                                color: delMouse.containsMouse
                                    ? Theme.cardHover
                                    : Qt.rgba(1, 1, 1, 0.05)
                                scale: delMouse.pressed ? 0.90 : 1.0

                                Behavior on color { ColorAnimation { duration: Theme.smoothMs } }
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: "close"
                                    iconSize: 13
                                    color: delMouse.containsMouse ? Theme.text : Theme.textSub
                                }

                                MouseArea {
                                    id: delMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        rowWrapper.removing = true;
                                        removeTimer.start();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty state
            Text {
                visible: root.filteredEntries.length === 0
                anchors.centerIn: parent
                text: root.query !== "" ? "No matching clipboard items" : "Clipboard history is empty"
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 13
            }
        }
    }
}
