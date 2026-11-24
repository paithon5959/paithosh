-- Environment variables

local paithosh = require("config.paithosh")

hl.env("HYPRCURSOR_THEME", "paithosh-sharp")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "paithosh-sharp")
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("XDPH_SHARE_PICKER", paithosh.root .. "/shell/scripts/xdph-share-picker.sh")
