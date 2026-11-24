pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pam

Singleton {
    id: root

    property bool locked: false
    property bool sessionLocked: false
    property bool transitionVisible: false
    property real transitionProgress: 0.0
    property bool exiting: false
    property bool authenticating: false
    property bool isError: false
    property bool unlockSuccess: false
    property string activeScreenName: ""
    property string _pendingPassword: ""

    // Lock Screen Customization (persisted in settings.json via shell.qml)
    property string effectPreset: "none"       // "none" | "snow" | "rain" | "wind"
    property string ambientSound: "wind"       // "none" | "wind" | "rain" | "snow"
    property bool silentMode: false            // Master silence override while locked
    property bool sfxEnabled: true             // Lock / unlock / error / key SFX
    property bool showNotifications: true
    property bool hideNotifContent: false
    property bool showMedia: true
    property bool showSystemAlerts: true
    property int effectIntensity: 100          // 50..150
    property int ambientVolume: 35             // 5..100
    property int dimOpacity: 36                // 15..75

    signal authFailed()

    PamContext {
        id: pam
        config: "login"

        onResponseRequiredChanged: {
            if (pam.responseRequired && root._pendingPassword !== "") {
                const pw = root._pendingPassword;
                root._pendingPassword = "";
                pam.respond(pw);
            }
        }

        onCompleted: (result) => {
            pamWatchdogTimer.stop();
            root._pendingPassword = "";
            root.authenticating = false;

            if (result === PamResult.Success) {
                root.isError = false;
                root.unlockSuccess = true;
                root.exiting = true;
                SoundService.stopLockAmbient();
                if (!root.silentMode && root.sfxEnabled) {
                    SoundService.playIconPop();
                }
                unlockReleaseTimer.restart();
            } else {
                root._handleAuthFailure();
            }
        }

        onError: (err) => {
            pamWatchdogTimer.stop();
            root._pendingPassword = "";
            root.authenticating = false;
            root._handleAuthFailure();
        }
    }

    // Phase 1 (Lock): Wait for pre-lock wallpaper+dim fade to cover apps, then engage WlSessionLock.
    // Keep transitionVisible = true underneath WlSessionLock so Hyprland never replays layersIn on unlock.
    Timer {
        id: lockEngageTimer
        interval: 260
        repeat: false
        onTriggered: {
            root.sessionLocked = true;
        }
    }

    // Phase 1 (Unlock): Allow password slot to collapse smoothly, then release WlSessionLock
    // directly onto the already-mapped 100% opaque transition overlay and fade out once.
    Timer {
        id: unlockReleaseTimer
        interval: 180
        repeat: false
        onTriggered: {
            root.sessionLocked = false;
            Qt.callLater(function() {
                root.transitionProgress = 0.0;
                unlockFinishTimer.restart();
            });
        }
    }

    // Phase 2 (Unlock): Clean up after fade-out completes (overlay is already at opacity 0.0)
    Timer {
        id: unlockFinishTimer
        interval: 270
        repeat: false
        onTriggered: {
            root.transitionVisible = false;
            root.locked = false;
            root.exiting = false;
            root.unlockSuccess = false;
            root.activeScreenName = "";
            SoundService.stopLockAmbient();
        }
    }

    Timer {
        id: errorResetTimer
        interval: 2200
        repeat: false
        onTriggered: root.isError = false
    }

    Timer {
        id: pamWatchdogTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (pam.active) pam.abort();
            root._pendingPassword = "";
            root.authenticating = false;
            root._handleAuthFailure();
        }
    }

    function lock(screenName) {
        if (root.locked) return;
        lockEngageTimer.stop();
        unlockReleaseTimer.stop();
        unlockFinishTimer.stop();
        errorResetTimer.stop();
        pamWatchdogTimer.stop();

        root.exiting = false;
        root.authenticating = false;
        root.isError = false;
        root.unlockSuccess = false;
        root._pendingPassword = "";
        root.activeScreenName = screenName || "";

        root.locked = true;
        root.transitionProgress = 0.0;
        root.transitionVisible = true;
        if (!root.silentMode && root.sfxEnabled) {
            SoundService.playLock();
        }
        if (!root.silentMode && root.ambientSound !== "none") {
            SoundService.startLockAmbient(root.ambientSound);
        } else {
            SoundService.stopLockAmbient();
        }
        Qt.callLater(function() {
            root.transitionProgress = 1.0;
            lockEngageTimer.restart();
        });
    }

    function clearError() {
        errorResetTimer.stop();
        root.isError = false;
    }

    function submitPassword(password) {
        if (!root.locked || root.authenticating || root.unlockSuccess || root.exiting) return;
        if (!password || password.length === 0) return;

        clearError();
        root.authenticating = true;
        root._pendingPassword = password;
        pamWatchdogTimer.restart();

        if (pam.active) {
            if (pam.responseRequired) {
                const pw = root._pendingPassword;
                root._pendingPassword = "";
                pam.respond(pw);
                return;
            }
            pam.abort();
        }

        if (!pam.start()) {
            pamWatchdogTimer.stop();
            root.authenticating = false;
            root._pendingPassword = "";
            root._handleAuthFailure();
        }
    }

    function _handleAuthFailure() {
        root.isError = true;
        if (!root.silentMode && root.sfxEnabled) {
            SoundService.playLockError();
        }
        errorResetTimer.restart();
        root.authFailed();
    }
}
