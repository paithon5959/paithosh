import QtQuick
import ".."
import "../services"

TextInput {
    id: root

    property color textColor: Theme.text
    property color cursorColor: Theme.accent
    property int cursorSlideDuration: 85
    property int charFadeDuration: 180
    property bool soundEnabled: true

    property string _lastText: ""

    Keys.onPressed: function(event) {
        if (event.key !== Qt.Key_Shift && event.key !== Qt.Key_Control &&
            event.key !== Qt.Key_Alt && event.key !== Qt.Key_Meta) {
            if (root.soundEnabled) SoundService.playKey();
        }
    }

    color: preeditText.length > 0 ? textColor : "transparent"
    selectedTextColor: "transparent"
    selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.32)
    cursorDelegate: Item { width: 0; height: 0; visible: false }

    ListModel {
        id: charModel
    }

    function syncCharModel(newText, animate) {
        const oldText = _lastText;
        if (oldText === newText)
            return;

        const oldLen = oldText.length;
        const newLen = newText.length;
        const minLen = Math.min(oldLen, newLen);

        let prefix = 0;
        while (prefix < minLen && oldText.charCodeAt(prefix) === newText.charCodeAt(prefix))
            prefix++;

        let suffix = 0;
        while (suffix < (minLen - prefix) &&
               oldText.charCodeAt(oldLen - 1 - suffix) === newText.charCodeAt(newLen - 1 - suffix)) {
            suffix++;
        }

        const removeCount = oldLen - prefix - suffix;
        if (removeCount > 0)
            charModel.remove(prefix, removeCount);

        const insertCount = newLen - prefix - suffix;
        for (let i = 0; i < insertCount; i++) {
            charModel.insert(prefix + i, {
                ch: newText.charAt(prefix + i),
                fade: animate
            });
        }

        _lastText = newText;
    }

    Component.onCompleted: {
        if (text.length > 0)
            syncCharModel(text, false);
    }

    onTextChanged: {
        syncCharModel(text, activeFocus);
        smoothCursor.restartBlink();
    }
    onCursorPositionChanged: smoothCursor.restartBlink()

    Repeater {
        id: charRepeater
        model: charModel
        visible: root.preeditText.length === 0

        delegate: Text {
            id: charText
            readonly property rect charRect: {
                const _t = root.text;
                const _c = root.cursorPosition;
                const _w = root.width;
                const _i = index;
                return root.positionToRectangle(_i);
            }
            x: charRect.x
            y: charRect.y
            height: charRect.height
            verticalAlignment: Text.AlignVCenter
            font: root.font
            color: root.textColor
            text: root.echoMode === TextInput.Password ? "•" : model.ch
            opacity: 1.0

            Component.onCompleted: {
                if (model.fade) {
                    opacity = 0.0;
                    fadeAnim.start();
                }
            }

            NumberAnimation {
                id: fadeAnim
                target: charText
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: root.charFadeDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        id: smoothCursor
        x: root.cursorRectangle.x
        y: root.cursorRectangle.y + 2
        width: 2
        height: Math.max(12, root.cursorRectangle.height - 4)
        radius: 1
        color: root.cursorColor
        visible: root.activeFocus && !root.readOnly
        opacity: 1.0

        function restartBlink() {
            if (visible) blinkAnim.restart();
        }

        Behavior on x {
            NumberAnimation {
                duration: root.cursorSlideDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: root.cursorSlideDuration
                easing.type: Easing.OutCubic
            }
        }

        SequentialAnimation {
            id: blinkAnim
            running: smoothCursor.visible
            loops: Animation.Infinite
            NumberAnimation { target: smoothCursor; property: "opacity"; to: 1.0; duration: 0 }
            PauseAnimation { duration: 480 }
            NumberAnimation { target: smoothCursor; property: "opacity"; to: 0.15; duration: 240; easing.type: Easing.InOutSine }
            PauseAnimation { duration: 180 }
            NumberAnimation { target: smoothCursor; property: "opacity"; to: 1.0; duration: 240; easing.type: Easing.InOutSine }
        }
    }
}
