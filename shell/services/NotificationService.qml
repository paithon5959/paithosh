pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    property bool dnd: false
    property bool previewNotifActive: false
    property int nextPreviewId: 1000
    property var historyList: []
    property var activeToast: null

    readonly property int unreadCount: historyList.length
    readonly property bool hasUnreadBadge: previewNotifActive || (!dnd && unreadCount > 0)

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        onNotification: function(notif) {
            notif.tracked = true;
            const entry = {
                id: "n-" + notif.id + "-" + Date.now(),
                appName: notif.appName || "System",
                desktopEntry: notif.desktopEntry || "",
                summary: notif.summary || "Notification",
                body: notif.body || "",
                timeText: "now",
                notifObj: notif
            };
            root.historyList = [entry].concat(root.historyList).slice(0, 30);
            if (!root.dnd && !notif.lastGeneration) {
                root.activeToast = entry;
                toastExpireTimer.restart();
                if (!(LockService.locked && LockService.silentMode)) {
                    SoundService.playNotify();
                }
            }
        }
    }

    Timer {
        id: toastExpireTimer
        interval: 4500
        repeat: false
        onTriggered: root.activeToast = null
    }

    function dismissToast() {
        toastExpireTimer.stop();
        activeToast = null;
    }

    function activateToast() {
        if (activeToast) {
            activateNotification(activeToast);
        }
    }

    function activateNotification(entry) {
        if (!entry) return;
        if (entry.notifObj && entry.notifObj.actions) {
            const actions = entry.notifObj.actions;
            for (let i = 0; i < actions.length; ++i) {
                if (actions[i] && actions[i].identifier === "default") {
                    try { actions[i].invoke(); } catch (e) {}
                    break;
                }
            }
        }
        CompositorService.focusWindowByApp(entry.appName, entry.desktopEntry, entry.summary);
        dismissToast();
    }

    function dismissById(id) {
        const next = [];
        for (let i = 0; i < historyList.length; ++i) {
            const item = historyList[i];
            if (item.id === id) {
                if (item.notifObj) {
                    try { item.notifObj.dismiss(); } catch (e) {}
                }
                continue;
            }
            next.push(item);
        }
        historyList = next;
        if (activeToast && activeToast.id === id) dismissToast();
    }

    function clearAll() {
        for (let i = 0; i < historyList.length; ++i) {
            const item = historyList[i];
            if (item.notifObj) {
                try { item.notifObj.dismiss(); } catch (e) {}
            }
        }
        historyList = [];
        dismissToast();
        previewNotifActive = false;
    }

    function pushPreviewNotification(appName, summary, body) {
        nextPreviewId += 1;
        const entry = {
            id: "preview-" + nextPreviewId,
            appName: appName || "Hyprland",
            summary: summary || "Screenshot saved",
            body: body || "~/Pictures/Screenshots/2026-11-18.png",
            timeText: "now",
            notifObj: null
        };
        historyList = [entry].concat(historyList).slice(0, 30);
        if (!dnd) {
            activeToast = entry;
            toastExpireTimer.restart();
        }
    }

    function togglePreviewNotif() {
        previewNotifActive = !previewNotifActive;
    }
}
