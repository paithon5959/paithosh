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
            icon: "home"
        },
        {
            id: "home-volume",
            page: "home",
            pageLabel: "Home",
            title: "Master Volume",
            subtitle: "Quick audio output volume level",
            keywords: "sound audio speaker mute",
            icon: "volume"
        },
        {
            id: "home-brightness",
            page: "home",
            pageLabel: "Home",
            title: "Display Brightness",
            subtitle: "Backlight brightness level",
            keywords: "screen backlight dim light",
            icon: "sun"
        },

        // System
        {
            id: "system-night-light",
            page: "system",
            pageLabel: "System",
            title: "Night Light",
            subtitle: "Shift display to warmer colors after sunset",
            keywords: "blue light warm temperature color eye",
            icon: "moon"
        },
        {
            id: "system-dnd",
            page: "system",
            pageLabel: "System",
            title: "Do Not Disturb",
            subtitle: "Silence popups on the Dynamic Island status bar",
            keywords: "dnd notifications silence quiet dynamic island",
            icon: "bell-off"
        },
        {
            id: "system-power-mode",
            page: "system",
            pageLabel: "System",
            title: "Power mode",
            subtitle: "Tune CPU governor and thermal profile",
            keywords: "performance balanced powersave cpu",
            icon: "bolt"
        },

        // Display
        {
            id: "display-scale",
            page: "display",
            pageLabel: "Display",
            title: "Scale",
            subtitle: "Change the size of text, apps, and other items",
            keywords: "hidpi dpi zoom fractional scaling",
            icon: "maximize"
        },
        {
            id: "display-resolution",
            page: "display",
            pageLabel: "Display",
            title: "Display resolution",
            subtitle: "Adjust the resolution to fit your connected display",
            keywords: "monitor screen 1080p 1440p 4k refresh rate",
            icon: "monitor"
        },
        {
            id: "display-orientation",
            page: "display",
            pageLabel: "Display",
            title: "Display orientation",
            subtitle: "Rotate screen layout for Wayland output",
            keywords: "rotate portrait landscape",
            icon: "refresh"
        },
        {
            id: "display-rotation-lock",
            page: "display",
            pageLabel: "Display",
            title: "Rotation lock",
            subtitle: "Prevent automatic orientation changes",
            keywords: "sensor lock screen rotate",
            icon: "lock"
        },

        // Sound & Audio
        {
            id: "sound-output",
            page: "sound",
            pageLabel: "Sound & Audio",
            title: "Output volume",
            subtitle: "Master playback volume and output devices",
            keywords: "speaker headphone pipewire sink audio",
            icon: "volume"
        },
        {
            id: "sound-input",
            page: "sound",
            pageLabel: "Sound & Audio",
            title: "Input volume",
            subtitle: "Master microphone gain and input devices",
            keywords: "mic microphone recording pipewire source",
            icon: "mic"
        },
        {
            id: "sound-apps",
            page: "sound",
            pageLabel: "Sound & Audio",
            title: "Application volume",
            subtitle: "Per-application playback volume and mute",
            keywords: "app application mixer stream volume mute pipewire",
            icon: "music"
        },

        // Power & Battery
        {
            id: "power-profile",
            page: "power",
            pageLabel: "Power & Battery",
            title: "Power profile",
            subtitle: "Battery status, performance, balanced and power saver",
            keywords: "battery charge ac thermal tlp power-profiles-daemon",
            icon: "bolt"
        },

        // Updates
        {
            id: "system-reload-shell",
            page: "system",
            pageLabel: "System",
            title: "Reload Shell",
            subtitle: "Smoothly reload Quickshell and Hyprland config",
            keywords: "reload shell restart quickshell qs hyprctl",
            icon: "refresh"
        },
        {
            id: "updates-shell",
            page: "updates",
            pageLabel: "Updates",
            title: "Paithosh Shell Update",
            subtitle: "Update shell from GitHub main branch or stable releases",
            keywords: "paithosh shell git repo pull self update reload release stable main github",
            icon: "bolt"
        },
        {
            id: "updates-shell-stream",
            page: "updates",
            pageLabel: "Updates",
            title: "Shell Update Stream",
            subtitle: "Choose between Main (GitHub) and Release (Stable)",
            keywords: "update stream channel release stable main github branch",
            icon: "download"
        },
        {
            id: "updates-hypr-sync",
            page: "updates",
            pageLabel: "Updates",
            title: "Hyprland Default Config",
            subtitle: "Sync defaults/hypr Lua config & automatic backup",
            keywords: "hyprland config lua defaults sync backup",
            icon: "code"
        },
        {
            id: "updates-packages",
            page: "updates",
            pageLabel: "Updates",
            title: "Updates",
            subtitle: "System repositories & installed packages",
            keywords: "pacman aur apt upgrade software check updates",
            icon: "package-update"
        },

        // Backup & Restore
        {
            id: "backup-system",
            page: "backup",
            pageLabel: "Backup & Restore",
            title: "System Backup & Btrfs Snapshot",
            subtitle: "Verified Btrfs subvolume snapshots, kernel check & system rollback",
            keywords: "backup restore snapshot btrfs system rollback verify grubby update major",
            icon: "shield"
        },
        {
            id: "backup-data",
            page: "backup",
            pageLabel: "Backup & Restore",
            title: "User Data Backup (.pak Store)",
            subtitle: "Save & restore important /home folders as .pak ZIP archives",
            keywords: "backup data pak zip store home documents projects pictures desktop archive restore verify import",
            icon: "archive"
        },

        // Storage
        {
            id: "storage-overview",
            page: "storage",
            pageLabel: "Storage",
            title: "Storage & File Sight",
            subtitle: "Disk breakdown across apps, OS, shell, tmp/cache and user documents",
            keywords: "storage disk space gb usage apps os shell cache documents folders",
            icon: "hard-drive"
        },
        {
            id: "storage-shredder",
            page: "storage",
            pageLabel: "Storage",
            title: "Shredder (File Cleanup)",
            subtitle: "Clean caches and stale large user files with configurable age threshold",
            keywords: "shredder cleanup stale old large files cache trash root sudo",
            icon: "trash"
        },

        // Wi-Fi
        {
            id: "wifi-network",
            page: "wifi",
            pageLabel: "Wi-Fi",
            title: "Wi-Fi",
            subtitle: "Wireless networks, SSIDs and connection status",
            keywords: "wireless internet network ssid wlan",
            icon: "wifi"
        },

        // VPN & Proxy
        {
            id: "vpn-wireguard",
            page: "vpn",
            pageLabel: "VPN & Proxy",
            title: "VPN & Proxy",
            subtitle: "Endpoint server, custom DNS, auto-connect & kill switch",
            keywords: "wireguard wg0 tunnel dns proxy privacy",
            icon: "shield"
        },
        {
            id: "network-discord-rpc",
            page: "discord_rpc",
            pageLabel: "Discord RPC",
            title: "Discord RPC",
            subtitle: "Live Discord Rich Presence, Linux larper presets & custom flex",
            keywords: "discord rpc rich presence larper satire status custom client id",
            icon: "message-square"
        },

        // Personalization
        {
            id: "pers-themes",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Theme presets",
            subtitle: "Quick desktop theme presets and live preview",
            keywords: "theme palette colors preset dark light",
            icon: "palette"
        },
        {
            id: "pers-share-code",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Quick Share Code",
            subtitle: "Export or import personalization & .paish profile files",
            keywords: "paish profile export import share theme",
            icon: "copy"
        },
        {
            id: "pers-window-blur",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Window Blur (Kawase)",
            subtitle: "Frosted translucency behind panels",
            keywords: "glass blur kawase transparency",
            icon: "droplet"
        },
        {
            id: "pers-animations",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Hyprland Animations",
            subtitle: "Smooth spring window transitions",
            keywords: "motion spring bezier animations",
            icon: "sparkles"
        },
        {
            id: "pers-dynamic-island-autohide",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Dynamic Island Auto-Hide",
            subtitle: "Hide status bar when fullscreen or overlapped",
            keywords: "dynamic island notch status bar autohide fullscreen overlap dodge cursor hover ghost",
            icon: "maximize"
        },
        {
            id: "pers-active-border",
            page: "personalization",
            pageLabel: "Personalization",
            title: "Active Border Highlight",
            subtitle: "Crisp outline on focused window",
            keywords: "focus border window outline",
            icon: "square-rounded"
        },

        // Appearance
        {
            id: "app-wallpaper-color",
            page: "appearance",
            pageLabel: "Appearance",
            title: "Adjust colors based on what you see",
            subtitle: "Automatically match Solid (3–5) or Gradient (10–12) colors to wallpaper",
            keywords: "adjust colors based on what you see wallpaper adaptive dynamic solid gradient match palette",
            icon: "eye"
        },
        {
            id: "app-surface-theme",
            page: "appearance",
            pageLabel: "Appearance",
            title: "Global Surface Theme",
            subtitle: "Contrast & backdrop style synced across apps",
            keywords: "dark light surface contrast backdrop",
            icon: "contrast"
        },
        {
            id: "app-accent-style",
            page: "appearance",
            pageLabel: "Appearance",
            title: "Surface & Gradients",
            subtitle: "Per-tier Shell, Surface & Accent gradient switches, angle & palette swatches",
            keywords: "accent color hue saturation gradient shell surface pillbg surfacebg angle",
            icon: "sparkles"
        },
        {
            id: "app-theme-studio",
            page: "appearance",
            pageLabel: "Appearance",
            title: "Theme Color & Gradient Studio",
            subtitle: "Edit shell, surface, accent, raised, text & border colors with HSV & hex",
            keywords: "shell color pillbg surfacebg surface raised text border palette hex studio",
            icon: "palette"
        },
        {
            id: "app-wallpaper",
            page: "appearance",
            pageLabel: "Appearance",
            title: "Wallpaper & Transitions",
            subtitle: "Background image preview, Crossfade + Scale, Crossfade & Instant",
            keywords: "wallpaper background image picture transition crossfade",
            icon: "image"
        },
        {
            id: "app-decoration-blur",
            page: "appearance",
            pageLabel: "Appearance",
            title: "Decoration, Motion & Blur",
            subtitle: "Corner rounding, drop shadows, inactive opacity, spring & Kawase blur",
            keywords: "rounding radius shadow blur opacity spring stiffness damping",
            icon: "sparkles"
        },
        {
            id: "cursor-style",
            page: "cursor",
            pageLabel: "Appearance › Cursor",
            title: "Cursor Style",
            subtitle: "Classic Sharp, Soft Stem & Smooth Wedge Paithosh custom cursors",
            keywords: "cursor pointer mouse theme shape style sharp soft wedge hyprcursor",
            icon: "pointer"
        },
        {
            id: "cursor-size",
            page: "cursor",
            pageLabel: "Appearance › Cursor",
            title: "Cursor Size",
            subtitle: "Scale custom cursor consistently across Hyprland, GTK and Qt",
            keywords: "cursor size scale px pointer xcursor hyprcursor gtk qt",
            icon: "maximize"
        },
        {
            id: "cursor-color",
            page: "cursor",
            pageLabel: "Appearance › Cursor",
            title: "Cursor Color & Auto Contrast",
            subtitle: "Screen-adaptive contrast, follow theme accent or fixed color",
            keywords: "cursor color auto contrast adaptive theme accent fixed hex",
            icon: "contrast"
        },
        {
            id: "cursor-motion-blur",
            page: "cursor",
            pageLabel: "Appearance › Cursor",
            title: "Motion Blur Cursor (Experimental)",
            subtitle: "Velocity-aligned directional ghost trail overlay",
            keywords: "cursor motion blur trail experimental overlay afterimage",
            icon: "sparkles"
        },

        // Binding
        {
            id: "keybind-shortcuts",
            page: "keybind",
            pageLabel: "Binding",
            title: "Binding",
            subtitle: "Shortcuts, apps, screenshot & Island IPC",
            keywords: "keybind shortcut hotkey keys super",
            icon: "keyboard"
        },

        // Layout
        {
            id: "layout-tiling",
            page: "layout",
            pageLabel: "Layout",
            title: "Layout & Tiling",
            subtitle: "Dwindle, Master, window gaps & borders",
            keywords: "hyprland tiling dwindle master gaps borders",
            icon: "layout"
        },
        {
            id: "layout-dynamic-island",
            page: "layout",
            pageLabel: "Layout",
            title: "Dynamic Island Bar",
            subtitle: "Control position (top/bottom), auto-hide, corner radius & screen edge offset",
            keywords: "dynamic island status bar position top bottom notch pill corner radius edge offset fullscreen overlap",
            icon: "move-vertical"
        },

        // Lock Screen
        {
            id: "lockscreen-effects",
            page: "lockscreen",
            pageLabel: "Lock Screen",
            title: "Ambient visual effects",
            subtitle: "Snowfall, rain, wind breeze & particle intensity on lock screen",
            keywords: "lock screen snow snowfall rain wind breeze particles weather effect",
            icon: "snowflake"
        },
        {
            id: "lockscreen-audio",
            page: "lockscreen",
            pageLabel: "Lock Screen",
            title: "Ambient sound & Silent mode",
            subtitle: "Gentle wind, soft rain, winter air, silent lock screen & lock SFX",
            keywords: "lock screen sound audio silent mute wind rain snow sfx quiet",
            icon: "music"
        },
        {
            id: "lockscreen-notifications",
            page: "lockscreen",
            pageLabel: "Lock Screen",
            title: "Lock screen notifications",
            subtitle: "Unread bell badge, toast cards & hide sensitive content",
            keywords: "lock screen notifications toast bell privacy hide sensitive content",
            icon: "bell"
        },
        {
            id: "lockscreen-media",
            page: "lockscreen",
            pageLabel: "Lock Screen",
            title: "Lock screen media player",
            subtitle: "Floating media split-pill with playback controls on lock screen",
            keywords: "lock screen media player music controls mpris",
            icon: "play"
        },
        {
            id: "lockscreen-alerts",
            page: "lockscreen",
            pageLabel: "Lock Screen",
            title: "Lock screen system alerts",
            subtitle: "Low battery, high temperature overheat & charger alerts",
            keywords: "lock screen system alerts low battery high temperature overheat thermal charger",
            icon: "bolt"
        },

        // About
        {
            id: "about-system",
            page: "about",
            pageLabel: "About",
            title: "About",
            subtitle: "Paithosh shell version, OS & hardware info",
            keywords: "version os kernel info about",
            icon: "info"
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
