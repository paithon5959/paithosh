-- Paithosh Monochrome OLED Palette
-- Matches shell/Theme.qml

local M = {
    -- Core Surfaces
    pill_bg        = "rgb(000000)", -- #000000 pure OLED black
    surface_bg     = "rgb(0b0b0c)", -- #0b0b0c
    surface_raised = "rgb(101012)", -- #101012

    -- Text & Foreground
    text           = "rgb(ffffff)", -- #ffffff
    text_sub       = "rgba(ffffff99)", -- 60% white
    text_muted     = "rgba(ffffff73)", -- 45% white

    -- Borders (subtle monochrome glass)
    border_active_a = "rgba(ffffffcc)", -- crisp white highlight
    border_active_b = "rgba(ffffff44)", -- soft fade
    border_inactive = "rgba(ffffff24)", -- 14% white (Theme.borderSubtle)

    -- Shadows
    shadow_color    = "rgba(000000cc)",

    -- Semantic Accents
    ok              = "rgb(30d158)",
    info            = "rgb(0a84ff)",
    danger          = "rgb(ff453a)",
    warn            = "rgb(ff9f0a)",
}

return M
