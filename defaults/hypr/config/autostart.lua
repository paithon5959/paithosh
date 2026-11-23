-- Autostart processes

local paithosh = require("config.paithosh")

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("command -v fcitx5 >/dev/null 2>&1 && fcitx5 -d --replace")
    hl.exec_cmd("qs -p " .. paithosh.root .. "/shell")
end)
