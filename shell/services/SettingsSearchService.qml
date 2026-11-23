pragma Singleton
import QtQuick

QtObject {
    id: root

    readonly property var entries: [
        // Home / System Specs & Quick Settings
        {
            id: "home-specs",
            page: "home",
            pageLabel: "Home",
            title: "System specifications",
            subtitle: "Processor, memory, graphics and storage overview",
            keywords: "cpu ram gpu disk specs hardware",
            icon: "⌂"
        },
        {
            id: "home-volume",
            page: "home",
            pageLabel: "Home",
            title: "Master Volume",
            subtitle: "Quick audio output volume level",
            keywords: "sound audio speaker mute",
            icon: "🔊"
        },
        {
            id: "home-brightness",
            page: "home",
            pageLabel: "Home",
            title: "Display Brightness",
            subtitle: "Backlight brightness level",
            keywords: "screen backlight dim light",
            icon: "☀"
        },

        // System
        {
            id: "system-night-light",
            page: "system",
            pageLabel: "System",
            title: "Night Light",
            subtitle: "Shift display to warmer colors after sunset",
            keywords: "blue light warm temperature color eye",
            icon: "◐"
        },
        {
            id: "system-dnd",
            page: "system",
            pageLabel: "System",
            title: "Do Not Disturb",
            subtitle: "Silence popups on the Dynamic Island status bar",
            keywords: "dnd notifications silence quiet dynamic island",
            icon: "🔕"
        },
        {
            id: "system-power-mode",
            page: "system",
            pageLabel: "System",
            title: "Power mode",
            subtitle: "Tune CPU governor and thermal profile",
            keywords: "performance balanced powersave cpu",
            icon: "⚡"
        },

        // Display
        {
            id: "display-scale",
            page: "display",
            pageLabel: "Display",
            title: "Scale",
            subtitle: "Change the size of text, apps, and other items",
            keywords: "hidpi dpi zoom fractional scaling",
            icon: "⤢"
        },
        {
            id: "display-resolution",
            page: "display",
            pageLabel: "Display",
            title: "Display resolution",
            subtitle: "Adjust the resolution to fit your connected display",
            keywords: "monitor screen 1080p 1440p 4k refresh rate",
            icon: "▭"
        },
        {
            id: "display-orientation",
            page: "display",
            pageLabel: "Display",
            title: "Display orientation",
            subtitle: "Rotate screen layout for Wayland output",
            keywords: "rotate portrait landscape",
            icon: "↻"
        },
        {
            id: "display-rotation-lock",
            page: "display",
            pageLabel: "Display",
            title: "Rotation lock",
            subtitle: "Prevent automatic orientation changes",
            keywords: "sensor lock screen rotate",
            icon: "🔒"
        },

        // Sound & Audio
        {
            id: "sound-output",
            page: "sound",
            pageLabel: "Sound & Audio",
            title: "Output volume",
            subtitle: "Master playback volume and output devices",
            keywords: "speaker headphone pipewire sink audio",
            icon: "♪"
        },
        {
            id: "sound-input",
            page: "sound",
            pageLabel: "Sound & Audio",
            title: "Input volume",
            subtitle: "Master microphone gain and input devices",
            keywords: "mic microphone recording pipewire source",
            icon: "🎙"
        },

        // Power & Battery
        {
            id: "power-profile",
            page: "power",
            pageLabel: "Power & Battery",
            title: "Power profile",
            subtitle: "Battery status, performance, balanced and power saver",
            keywords: "battery charge ac thermal tlp power-profiles-daemon",
            icon: "⚡"
        },

        // Updates
        {
            id: "updates-packages",
            page: "updates",
            pageLabel: "Updates",
            title: "Updates",
            subtitle: "System repositories & installed packages",
            keywords: "pacman aur apt upgrade software check updates",
            icon: "↻"
        },

        // Backup & Restore
        {
            id: "backup-system",
            page: "backup",
            pageLabel: "Backup & Restore",
            title: "System Backup & Btrfs Snapshot",
            subtitle: "Verified Btrfs subvolume snapshots, kernel check & system rollback",
            keywords: "backup restore snapshot btrfs system rollback verify grubby update major",
            icon: "🛡"
        },
        {
            id: "backup-data",
            page: "backup",
            pageLabel: "Backup & Restore",
            title: "User Data Backup (.pak Store)",
            subtitle: "Save & restore important /home folders as .pak ZIP archives",
            keywords: "backup data pak zip store home documents projects pictures desktop archive restore verify import",
            icon: "⛁"
        },

        // Wi-Fi
        {
            id: "wifi-network",
            page: "wifi",
            pageLabel: "Wi-Fi",
            title: "Wi-Fi",
            subtitle: "Wireless networks, SSIDs and connection status",
            keywords: "wireless internet network ssid wlan",
            icon: "◈"
        },

        // VPN & Proxy
        {
            id: "vpn-wireguard",
            page: "vpn",
            pageLabel: "VPN & Proxy",
            title: "VPN & Proxy",
            subtitle: "Endpoint server, custom DNS, auto-connect & kill switch",
            keywords: "wireguard wg0 tunnel dns proxy privacy",
            icon: "⌖"
        },

        // Personalization
        {
            id: "pers-themes",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Theme presets",
            subtitle: "Quick desktop theme presets and live preview",
            keywords: "theme palette colors preset dark light",
            icon: "✎"
        },
        {
            id: "pers-share-code",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Quick Share Code",
            subtitle: "Export or import personalization & .paish profile files",
            keywords: "paish profile export import share theme",
            icon: "✎"
        },
        {
            id: "pers-window-blur",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Window Blur (Kawase)",
            subtitle: "Frosted translucency behind panels",
            keywords: "glass blur kawase transparency",
            icon: "✦"
        },
        {
            id: "pers-animations",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Hyprland Animations",
            subtitle: "Smooth spring window transitions",
            keywords: "motion spring bezier animations",
            icon: "⚡"
        },
        {
            id: "pers-dynamic-island-autohide",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Dynamic Island Auto-Hide",
            subtitle: "Hide status bar when fullscreen or overlapped",
            keywords: "dynamic island notch status bar autohide fullscreen overlap",
            icon: "⛶"
        },
        {
            id: "pers-active-border",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Active Border Highlight",
            subtitle: "Crisp outline on focused window",
            keywords: "focus border window outline",
            icon: "▢"
        },

        // Appearance
        {
            id: "app-surface-theme",
            page: "appearance",
            pageLabel: "Appearance",
            title: "Global Surface Theme",
            subtitle: "Contrast & backdrop style synced across apps",
            keywords: "dark light surface contrast backdrop",
            icon: "◐"
        },
        {
            id: "app-accent-style",
            page: "appearance",
            pageLabel: "Appearance",
            title: "Accent Style",
            subtitle: "Solid monochrome or directional gradient & HSV studio",
            keywords: "accent color hue saturation gradient",
            icon: "Aa"
        },
        {
            id: "app-wallpaper",
            page: "appearance",
            pageLabel: "Appearance",
            title: "Wallpaper & Transitions",
            subtitle: "Background image preview, Crossfade + Scale, Crossfade & Instant",
            keywords: "wallpaper background image picture transition crossfade",
            icon: "🖼"
        },
        {
            id: "app-decoration-blur",
            page: "appearance",
            pageLabel: "Appearance",
            title: "Decoration, Motion & Blur",
            subtitle: "Corner rounding, drop shadows, inactive opacity, spring & Kawase blur",
            keywords: "rounding radius shadow blur opacity spring stiffness damping",
            icon: "✦"
        },

        // Binding
        {
            id: "keybind-shortcuts",
            page: "keybind",
            pageLabel: "Binding",
            title: "Binding",
            subtitle: "Shortcuts, apps, screenshot & Island IPC",
            keywords: "keybind shortcut hotkey keys super",
            icon: "⌨"
        },

        // Layout
        {
            id: "layout-tiling",
            page: "layout",
            pageLabel: "Layout",
            title: "Layout & Tiling",
            subtitle: "Dwindle, Master, window gaps & borders",
            keywords: "hyprland tiling dwindle master gaps borders",
            icon: "◫"
        },
        {
            id: "layout-dynamic-island",
            page: "layout",
            pageLabel: "Layout",
            title: "Dynamic Island Bar",
            subtitle: "Control position (top/bottom), auto-hide, corner radius & screen edge offset",
            keywords: "dynamic island status bar position top bottom notch pill corner radius edge offset fullscreen overlap",
            icon: "◐"
        },

        // About
        {
            id: "about-system",
            page: "about",
            pageLabel: "About",
            title: "About",
            subtitle: "Paithosh shell version, OS & hardware info",
            keywords: "version os kernel info about",
            icon: "ⓘ"
        }
    ]

    function _tokens(query) {
        const clean = (query || "").trim().toLowerCase();
        if (clean === "") return [];
        return clean.split(/\s+/);
    }

    function scoreEntry(entry, tokens) {
        if (!tokens || tokens.length === 0) return 0;
        const title = (entry.title || "").toLowerCase();
        const sub = (entry.subtitle || "").toLowerCase();
        const kw = (entry.keywords || "").toLowerCase();
        const pageLbl = (entry.pageLabel || "").toLowerCase();
        const hay = title + " " + sub + " " + kw + " " + pageLbl;

        for (let i = 0; i < tokens.length; ++i) {
            if (hay.indexOf(tokens[i]) === -1) return 0;
        }

        let score = 10;
        const joined = tokens.join(" ");
        if (title === joined) score += 100;
        else if (title.indexOf(joined) === 0) score += 60;
        else if (title.indexOf(joined) !== -1) score += 35;
        else if (kw.indexOf(joined) !== -1) score += 20;

        return score;
    }

    function search(query) {
        const tokens = _tokens(query);
        if (tokens.length === 0) return [];
        const hits = [];
        for (let i = 0; i < entries.length; ++i) {
            const s = scoreEntry(entries[i], tokens);
            if (s > 0) {
                hits.push({
                    id: entries[i].id,
                    page: entries[i].page,
                    pageLabel: entries[i].pageLabel,
                    title: entries[i].title,
                    subtitle: entries[i].subtitle,
                    icon: entries[i].icon,
                    score: s
                });
            }
        }
        hits.sort(function(a, b) { return b.score - a.score; });
        return hits;
    }

    function pageHasMatch(pageKey, query) {
        const tokens = _tokens(query);
        if (tokens.length === 0) return true;
        for (let i = 0; i < entries.length; ++i) {
            if (entries[i].page === pageKey && scoreEntry(entries[i], tokens) > 0) {
                return true;
            }
        }
        return false;
    }

    function matchesText(query, title, subtitle, extraKeywords) {
        const tokens = _tokens(query);
        if (tokens.length === 0) return true;
        const hay = ((title || "") + " " + (subtitle || "") + " " + (extraKeywords || "")).toLowerCase();
        for (let i = 0; i < tokens.length; ++i) {
            if (hay.indexOf(tokens[i]) === -1) return false;
        }
        return true;
    }
}
