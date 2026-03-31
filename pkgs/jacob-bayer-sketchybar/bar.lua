local colors = require("colors")
local settings = require("settings")

-- Equivalent to the --bar domain
sbar.bar({
    height = settings.bar.height,
    notch_display_height = settings.bar.notch_display_height,
    notch_offset = settings.bar.notch_offset,
    color = colors.with_alpha(colors.bar.bg, 0.5),
    topmost = "window",
    sticky = true,
    -- color=colors.transparent,
    padding_right = settings.bar.padding_right,
    padding_left = settings.bar.padding_left,
    corner_radius = settings.bar.corner_radius,
    y_offset = settings.bar.y_offset,
    shadow = false,
    blur_radius = settings.bar.blur_radius,
    margin = settings.bar.margin
})
