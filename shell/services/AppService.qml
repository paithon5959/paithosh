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

    function searchPaithoshApps(query, category) {
        const q = String(query || "").trim().toLowerCase();
        const catFilter = category || "All";
        const builtins = [
            { id: "paithosh-files", name: "Files", category: "System", keywords: "file manager folder explorer paithosh", iconName: "", fallbackSvg: "folder", islandApp: "files" },
            { id: "paithosh-settings", name: "Settings", category: "System", keywords: "preferences control panel config paithosh", iconName: "", fallbackSvg: "settings", islandApp: "settings" },
            { id: "paithosh-music", name: "Music", category: "Media", keywords: "mixcloud audio radio dj player stream paithosh", iconName: "", fallbackSvg: "music", islandApp: "music" }
        ];
        const out = [];
        for (let i = 0; i < builtins.length; ++i) {
            const b = builtins[i];
            if (catFilter !== "All" && b.category !== catFilter) continue;
            const hay = (b.name + " " + b.category + " " + b.keywords).toLowerCase();
            if (q !== "" && hay.indexOf(q) === -1) continue;
            out.push(b);
        }
        return out;
    }

    function searchAllApps(query, limit) {
        const q = String(query || "").trim();
        const max = limit || 4;
        const hits = q !== "" ? searchPaithoshApps(q, "All") : [];
        const sys = searchApps(q, "All");
        for (let i = 0; i < sys.length && hits.length < max; ++i) {
            hits.push(sys[i]);
        }
        return hits.slice(0, max);
    }

    function openApp(appItem, shellState) {
        if (!appItem) return;
        if (appItem.islandApp && shellState) {
            if (appItem.islandApp === "settings") {
                shellState.settingsSpotlight = "";
                shellState.settingsPage = "home";
            }
            shellState.openIslandApp(appItem.islandApp, null);
            return;
        }
        if (shellState) shellState.closePopovers();
        launchApp(appItem);
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
