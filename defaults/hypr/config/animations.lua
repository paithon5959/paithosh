-- Animations (tuned to Paithosh spring/smooth motion curves)

hl.config({
    animations = {
        enabled = true,
    },
})

-- Bezier & spring curves
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
hl.curve("paithoshSpring", { type = "spring", mass = 1, stiffness = 270, damping = 23 })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.0,  bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.5,  spring = "paithoshSpring" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.2,  spring = "paithoshSpring", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.8,  bezier = "quick",          style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 2.0,  bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.6,  bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.2,  bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 4.0,  bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4.2,  bezier = "easeOutQuint",   style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.8,  bezier = "quick",          style = "fade" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 3.2,  bezier = "easeOutQuint",   style = "slidefade 15%" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 3.2,  bezier = "easeOutQuint",   style = "slidefade 15%" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 2.6,  bezier = "easeOutQuint",   style = "slidefade 15%" })
