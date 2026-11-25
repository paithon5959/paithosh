-- Look and feel (Paithosh Monochrome OLED aesthetic)

local colors = require("theme.colors")

hl.config({
    general = {
        gaps_in     = 6,
        gaps_out    = 12,
        border_size = 1,

        col = {
            active_border   = { colors = { colors.border_active_a, colors.border_active_b }, angle = 45 },
            inactive_border = colors.border_inactive,
        },

        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding       = 16,
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 0.95,

        shadow = {
            enabled      = true,
            range        = 16,
            render_power = 3,
            color        = colors.shadow_color,
        },

        blur = {
            enabled  = true,
            size     = 8,
            passes   = 2,
            vibrancy = 0.16,
        },
    },

    layers = {
        allow_new_top_layers_over_existing_fullscreen = true,
    },

    misc = {
        force_default_wallpaper  = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = colors.pill_bg,
    },

    cursor = {
        enable_hyprcursor    = true,
        sync_gsettings_theme = true,
    },
})
