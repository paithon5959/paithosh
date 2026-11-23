pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    property bool enabled: true
    property real volume: 0.72
    property double _lastKeyMs: 0
    property int _keyIdx: 0

    readonly property var _keyFiles: [
        "key-creamy-1.wav",
        "key-creamy-2.wav",
        "key-creamy-3.wav"
    ]

    function _soundPath(file) {
        return Qt.resolvedUrl("../assets/sounds/" + file).toString().replace(/^file:\/\//, "");
    }

    function play(file, volScale) {
        if (!enabled) return;
        const v = Math.max(0.0, Math.min(1.0, volume * (volScale !== undefined ? volScale : 1.0)));
        if (v <= 0.001) return;
        Quickshell.execDetached(["pw-play", "--volume=" + v.toFixed(2), _soundPath(file)]);
    }

    function playShutter() { play("shutter-soft.wav", 1.0); }
    function playRecordStart() { play("record-start.wav", 0.9); }
    function playRecordStop() { play("record-stop.wav", 0.9); }
    function playNotify() { play("notify-gentle.wav", 0.85); }
    function playInstallerStep() { play("installer-step.wav", 0.65); }
    function playInstallerStart() { play("installer-start.wav", 0.85); }
    function playInstallerDone() { play("installer-done.wav", 0.90); }
    function playIconPop() { play("icon-pop.wav", 0.45); }

    function playKey() {
        const now = Date.now();
        if (now - _lastKeyMs < 24) return;
        _lastKeyMs = now;
        _keyIdx = (_keyIdx + 1) % _keyFiles.length;
        play(_keyFiles[_keyIdx], 0.42);
    }
}
