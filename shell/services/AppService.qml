pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    function mapCategory(cats) {
        if (!cats || cats.length === 0) return "System";
        for (let i = 0; i < cats.length; ++i) {
            const c = String(cats[i]).toLowerCase();
            if (c.indexOf("game") !== -1) return "Games";
            if (c.indexOf("development") !== -1 || c.indexOf("ide") !== -1) return "Dev";
            if (c.indexOf("audio") !== -1 || c.indexOf("video") !== -1 || c.indexOf("music") !== -1) return "Media";
        }
        return "System";
    }

    function iconForCategory(cat, appId) {
        const id = String(appId || "").toLowerCase();
        if (id.indexOf("kitty") !== -1 || id.indexOf("terminal") !== -1 || id.indexOf("konsole") !== -1) return "terminal";
        if (id.indexOf("dolphin") !== -1 || id.indexOf("files") !== -1 || id.indexOf("thunar") !== -1) return "folder";
        if (id.indexOf("settings") !== -1 || id.indexOf("systemsettings") !== -1) return "settings";
        if (cat === "Media") return "music";
        if (cat === "Dev") return "terminal";
        return "settings";
    }

    function searchApps(query, category) {
        const q = String(query || "").trim().toLowerCase();
        const catFilter = category || "All";
        const entries = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        const out = [];

        if (entries) {
            for (let i = 0; i < entries.length; ++i) {
                const e = entries[i];
                if (!e || e.noDisplay || !e.name) continue;
                const cat = mapCategory(e.categories);
                if (catFilter !== "All" && cat !== catFilter) continue;
                const hay = (e.name + " " + (e.genericName || "") + " " + (e.comment || "") + " " + cat).toLowerCase();
                if (q !== "" && hay.indexOf(q) === -1) continue;
                out.push({
                    id: e.id || e.name,
                    name: e.name,
                    category: cat,
                    iconName: e.icon || "",
                    fallbackSvg: iconForCategory(cat, e.id),
                    entry: e
                });
                if (out.length >= 24) break;
            }
        }
        return out;
    }

    function launchApp(appItem) {
        if (!appItem) return;
        if (appItem.entry && typeof appItem.entry.execute === "function") {
            appItem.entry.execute();
        } else if (appItem.cmd) {
            launchCommand(appItem.cmd);
        }
    }

    function launchCommand(cmdArray) {
        if (Array.isArray(cmdArray)) {
            Quickshell.execDetached(cmdArray);
        } else if (typeof cmdArray === "string" && cmdArray !== "") {
            Quickshell.execDetached(["sh", "-c", cmdArray]);
        }
    }

    function openExternalFiles() {
        Quickshell.execDetached(["sh", "-c", "command -v dolphin >/dev/null && dolphin || xdg-open \"$HOME\""]);
    }

    function openExternalSettings() {
        Quickshell.execDetached(["sh", "-c", "command -v systemsettings >/dev/null && systemsettings || notify-send 'Paithosh' 'Settings app external launcher'"]);
    }

    function searchWeb(query) {
        Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(query)]);
    }
}
