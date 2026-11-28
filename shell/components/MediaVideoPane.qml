import QtQuick
import QtQuick.Layouts
import QtMultimedia
import ".."
import "common"

Item {
    id: root

    property url source: ""
    property bool active: false
    property real lastVolume: 0.85

    readonly property var speedSteps: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    property int speedIdx: 2
    property bool scrubbing: false
    property real scrubRatio: 0
    property string pulseIcon: ""

    signal openExternalRequested()

    function formatTime(ms) {
        const totalSec = Math.max(0, Math.floor((ms || 0) / 1000));
        const h = Math.floor(totalSec / 3600);
        const m = Math.floor((totalSec % 3600) / 60);
        const s = totalSec % 60;
        const mm = (h > 0 && m < 10 ? "0" : "") + m;
        const ss = (s < 10 ? "0" : "") + s;
        return h > 0 ? (h + ":" + mm + ":" + ss) : (mm + ":" + ss);
    }

    function formatSpeed(val) {
        return (Math.round(val * 100) / 100) + "×";
    }

    function triggerPulse(iconName) {
        pulseIcon = iconName;
        pulseBadge.opacity = 0.92;
        pulseBadge.scale = 1.0;
        pulseFadeTimer.restart();
    }

    function togglePlay() {
        if (player.error !== MediaPlayer.NoError) return;
        if (player.playbackState === MediaPlayer.PlayingState) {
            player.pause();
            triggerPulse("media-pause");
        } else {
            if (player.mediaStatus === MediaPlayer.EndOfMedia) player.position = 0;
            player.play();
            triggerPulse("media-play");
        }
    }

    function seekRelative(deltaMs) {
        if (player.duration <= 0) return;
        const next = Math.max(0, Math.min(player.duration, player.position + deltaMs));
        player.position = next;
    }

    function toggleMute() {
        if (audioOut.muted || audioOut.volume <= 0.01) {
            audioOut.muted = false;
            if (audioOut.volume <= 0.01) audioOut.volume = Math.max(0.2, lastVolume);
        } else {
            lastVolume = audioOut.volume;
            audioOut.muted = true;
        }
    }

    function cycleSpeed(delta) {
        const len = speedSteps.length;
        speedIdx = ((speedIdx + delta) % len + len) % len;
        player.playbackRate = speedSteps[speedIdx];
    }

    function resetSpeed() {
        speedIdx = 2;
        player.playbackRate = 1.0;
    }

    function stopMedia() {
        player.stop();
        player.source = "";
    }

    onSourceChanged: {
        scrubbing = false;
        scrubRatio = 0;
        player.stop();
        player.source = source;
        player.playbackRate = speedSteps[speedIdx];
        if (active && source.toString() !== "") {
            player.play();
        }
    }

    onActiveChanged: {
        if (!active) {
            player.pause();
        } else if (source.toString() !== "" && player.source.toString() !== source.toString()) {
            player.source = source;
            player.playbackRate = speedSteps[speedIdx];
            player.play();
        }
    }

    Component.onCompleted: {
        if (active && source.toString() !== "") {
            player.source = source;
            player.playbackRate = speedSteps[speedIdx];
            player.play();
        }
    }

    Component.onDestruction: stopMedia()

    AudioOutput {
        id: audioOut
        volume: 0.85
        muted: false
    }

    MediaPlayer {
        id: player
        audioOutput: audioOut
        videoOutput: videoOut
        playbackRate: root.speedSteps[root.speedIdx]
    }

    Timer {
        id: pulseFadeTimer
        interval: 340
        onTriggered: {
            pulseBadge.opacity = 0.0;
            pulseBadge.scale = 1.12;
        }
    }

    // Video Surface
    Item {
        id: videoStage
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: controlBar.top
        anchors.bottomMargin: 10
        clip: true

        VideoOutput {
            id: videoOut
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectFit
            visible: player.error === MediaPlayer.NoError
        }

        MouseArea {
            anchors.fill: parent
            enabled: player.error === MediaPlayer.NoError
            cursorShape: Qt.PointingHandCursor
            onClicked: root.togglePlay()
        }

        // Transient Play/Pause center pulse
        Rectangle {
            id: pulseBadge
            width: 54; height: 54; radius: 27
            anchors.centerIn: parent
            color: Theme.pillBg
            border.width: 1; border.color: Theme.borderSubtle
            opacity: 0.0
            scale: 0.88
            visible: opacity > 0.01
            clip: true

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

            SvgIcon {
                anchors.centerIn: parent
                sourceName: root.pulseIcon || "media-play"
                iconSize: 22
                color: Theme.text
            }
        }

        // Error state (monochrome, plain consumer copy)
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 10
            visible: player.error !== MediaPlayer.NoError
            width: Math.min(320, parent.width - 32)

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 44; height: 44; radius: 12
                color: Theme.surfaceRaised
                border.width: 1; border.color: Theme.borderSubtle
                SvgIcon {
                    anchors.centerIn: parent
                    sourceName: "video"
                    iconSize: 20
                    color: Theme.warn
                }
            }

            Text {
                Layout.fillWidth: true; Layout.minimumWidth: 0
                horizontalAlignment: Text.AlignHCenter
                text: "Unable to play this video"
                color: Theme.text
                font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            PillButton {
                Layout.alignment: Qt.AlignHCenter
                text: "Open Externally"
                iconName: "external-link"
                onClicked: root.openExternalRequested()
            }
        }
    }

    // Minimalist Floating Control Bar
    Rectangle {
        id: controlBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: Math.min(620, Math.max(260, parent.width - 24))
        height: 68
        radius: 12
        color: Theme.pillBg
        border.width: 1; border.color: Theme.borderSubtle
        clip: true

        ThemeGradientFill {
            anchors.fill: parent
            anchors.margins: 1
            enabled: Theme.effectiveShellGradient
            color1: Theme.pillBg
            colorMid: Theme.pillBgMid
            color2: Theme.pillBg2
            cornerRadius: 11
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 12; anchors.rightMargin: 12
            anchors.topMargin: 8; anchors.bottomMargin: 8
            spacing: 6

            // Seek Bar
            Item {
                id: seekTrackHit
                Layout.fillWidth: true
                Layout.preferredHeight: 16

                readonly property real liveRatio: player.duration > 0 ? Math.max(0, Math.min(1, player.position / player.duration)) : 0
                readonly property real displayRatio: root.scrubbing ? root.scrubRatio : liveRatio

                Rectangle {
                    id: seekTrack
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.right: parent.right
                    height: 6; radius: 3
                    color: Theme.cardBg
                    clip: true

                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: Math.round(parent.width * seekTrackHit.displayRatio)
                        radius: 3
                        color: Theme.accent
                    }
                }

                Rectangle {
                    id: seekHandle
                    width: 14; height: 14; radius: 7
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, Math.round(parent.width * seekTrackHit.displayRatio - width / 2)))
                    color: Theme.text
                    border.width: 1; border.color: Theme.borderSubtle
                    scale: seekMouse.pressed ? 1.15 : (seekMouse.containsMouse ? 1.0 : 0.78)
                    opacity: (seekMouse.containsMouse || seekMouse.pressed || player.duration > 0) ? 1.0 : 0.0
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: seekMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: player.duration > 0

                    function ratioForX(mx) {
                        return Math.max(0, Math.min(1, mx / Math.max(1, width)));
                    }

                    onPressed: (mouse) => {
                        root.scrubbing = true;
                        root.scrubRatio = ratioForX(mouse.x);
                    }
                    onPositionChanged: (mouse) => {
                        if (pressed) root.scrubRatio = ratioForX(mouse.x);
                    }
                    onReleased: (mouse) => {
                        const r = ratioForX(mouse.x);
                        root.scrubRatio = r;
                        if (player.duration > 0) player.position = Math.round(r * player.duration);
                        root.scrubbing = false;
                    }
                }
            }

            // Bottom Controls Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                PillButton {
                    iconName: player.playbackState === MediaPlayer.PlayingState ? "media-pause" : "media-play"
                    iconSize: 13
                    fixedWidth: 32; fixedHeight: 28; radius: 8
                    onClicked: root.togglePlay()
                }

                Text {
                    readonly property real shownMs: root.scrubbing ? (root.scrubRatio * player.duration) : player.position
                    text: root.formatTime(shownMs) + " / " + root.formatTime(player.duration)
                    color: Theme.textSub
                    font.family: Theme.fontMono; font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.minimumWidth: 0
                }

                Item { Layout.fillWidth: true }

                // Playback Speed Selector (click cycles, right-click resets to 1x)
                Item {
                    implicitWidth: speedBtn.implicitWidth
                    implicitHeight: speedBtn.implicitHeight

                    PillButton {
                        id: speedBtn
                        text: root.formatSpeed(root.speedSteps[root.speedIdx])
                        fontFamily: Theme.fontMono
                        fontSize: 11
                        fixedHeight: 28; horizontalPadding: 9; radius: 8
                        active: root.speedIdx !== 2
                        onClicked: root.cycleSpeed(1)
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: root.resetSpeed()
                    }
                }

                // Mute Toggle
                PillButton {
                    iconName: (audioOut.muted || audioOut.volume <= 0.01)
                        ? "media-vol-mute"
                        : (audioOut.volume < 0.5 ? "media-vol-low" : "media-vol-high")
                    iconSize: 14
                    fixedWidth: 28; fixedHeight: 28; radius: 8; subtle: true
                    onClicked: root.toggleMute()
                }

                // Compact Volume Slider
                Item {
                    id: volHit
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 20

                    readonly property real volRatio: audioOut.muted ? 0 : Math.max(0, Math.min(1, audioOut.volume))

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.right: parent.right
                        height: 4; radius: 2
                        color: Theme.cardBg
                        clip: true

                        Rectangle {
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: Math.round(parent.width * volHit.volRatio)
                            radius: 2
                            color: Theme.accent
                        }
                    }

                    Rectangle {
                        width: 12; height: 12; radius: 6
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(parent.width - width, Math.round(parent.width * volHit.volRatio - width / 2)))
                        color: Theme.text
                        border.width: 1; border.color: Theme.borderSubtle
                        scale: volMouse.pressed ? 1.15 : (volMouse.containsMouse ? 1.0 : 0.85)
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                    }

                    MouseArea {
                        id: volMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        function setVol(mx) {
                            const r = Math.max(0, Math.min(1, mx / Math.max(1, width)));
                            audioOut.muted = (r <= 0.01);
                            audioOut.volume = r;
                            if (r > 0.01) root.lastVolume = r;
                        }

                        onPressed: (mouse) => setVol(mouse.x)
                        onPositionChanged: (mouse) => { if (pressed) setVol(mouse.x); }
                    }
                }
            }
        }
    }
}
