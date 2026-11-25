-- Autostart processes

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local paithosh = require("config.paithosh")

hl.on("hyprland.start", function ()
    hl.exec_cmd("QS_NO_RELOAD_POPUP=1 qs -p " .. shellQuote(paithosh.root .. "/shell"))
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDPH_SHARE_PICKER HYPRCURSOR_THEME HYPRCURSOR_SIZE XCURSOR_THEME XCURSOR_SIZE")
    hl.exec_cmd("command -v fcitx5 >/dev/null 2>&1 && fcitx5 -d --replace")
end)
