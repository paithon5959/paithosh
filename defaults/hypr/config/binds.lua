-- Keybindings

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local programs = require("config.programs")
local paithosh = require("config.paithosh")
local shellDir = paithosh.root .. "/shell"
local qsIpc    = "qs -p " .. shellQuote(shellDir) .. " ipc call paithosh "
local mainMod  = "SUPER"

-- Core applications & window management
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(programs.terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + ALT + Q", hl.dsp.window.kill())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(qsIpc .. "openFiles"))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(programs.menu))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

-- Paithosh shell IPC
hl.bind("Super_L",         hl.dsp.exec_cmd(qsIpc .. "superPressed"))
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd(qsIpc .. "superReleased"), { release = true })
hl.bind("ALT + space",     hl.dsp.exec_cmd(qsIpc .. "toggleSearch"))
hl.bind("SUPER + W",       hl.dsp.exec_cmd(qsIpc .. "toggleOverview"))
hl.bind("SUPER + V",       hl.dsp.exec_cmd(qsIpc .. "toggleClipboard"))

-- Focus movement
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Workspaces 1-10
for i = 1, 10 do
    local key = tostring(i % 10)
    hl.bind(mainMod .. " + " .. key,          hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key,  hl.dsp.window.move({ workspace = i }))
end

-- Screenshot (grim + slurp -> clipboard + status bar notification)
hl.bind(mainMod .. " + CTRL + S",  hl.dsp.exec_cmd("grim - | wl-copy && " .. qsIpc .. "notifyStatus \"Screenshot copied\""))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy && " .. qsIpc .. "notifyStatus \"Region copied\""))

-- Screen Recording (wf-recorder toggle -> <=20MB clipboard, >20MB ~/Videos)
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd(qsIpc .. "toggleScreenRecord"))

-- Cycle workspaces
hl.bind(mainMod .. " + F", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + A", hl.dsp.focus({ workspace = "e-1" }))

-- Mouse drag & resize
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media & brightness
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd(qsIpc .. "adjustVolume 5"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd(qsIpc .. "adjustVolume -5"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd(qsIpc .. "toggleMute"), { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(qsIpc .. "adjustBrightness 5"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(qsIpc .. "adjustBrightness -5"), { locked = true, repeating = true })

-- Playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
