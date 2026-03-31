return {
  paddings = 3,
  group_paddings = 2,

  icons = "NerdFont",

  bar = {
    height = 30,
    notch_display_height = 38,
    y_offset = 0,
    margin = 6,
    corner_radius = 22,
    padding_left = 2,
    padding_right = 2,
    blur_radius = 10,
    notch_offset = 0,
  },

  -- Use nix-managed Nerd Fonts for all text and icon glyphs.
  font = {
    text = "MesloLGM Nerd Font Propo",
    numbers = "MesloLGM Nerd Font Mono",
    style_map = {
      ["Regular"] = "Regular",
      ["Semibold"] = "Bold",
      ["Bold"] = "Bold",
      ["Heavy"] = "Bold",
      ["Black"] = "Bold",
    },
  },
}
