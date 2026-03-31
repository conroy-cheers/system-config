local colors = require("colors")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

local MAX_SPACES = 10
local MAX_ICONS = 5

local spaces = {}
local space_items = {}
local current_space = nil

local function trim(value)
  return ((value or ""):gsub("%s+$", ""))
end

local function set_space_opacity(sid, active)
  local item = spaces[sid]
  if not item then
    return
  end

  local alpha = active and 0.7 or 0.3
  item:set({
    background = {
      color = colors.with_alpha(colors.bg2, alpha),
      border_color = colors.with_alpha(colors.bg2, alpha),
    },
  })
end

local function refresh_space(sid, active_space, present_spaces, apps_by_space)
  local present = present_spaces[sid] or false
  local space = spaces[sid]
  local items = space_items[sid]

  if not present then
    space:set({ drawing = false, updates = false })
    items.label:set({ drawing = false, updates = false })
    for index = 1, MAX_ICONS do
      items.apps[index]:set({ drawing = false, updates = false })
    end
    items.ellipsis:set({ drawing = false, updates = false })
    return
  end

  local apps = apps_by_space[sid] or {}
  local selected = active_space == sid

  items.label:set({
    drawing = true,
    updates = true,
    icon = {
      highlight = selected,
      color = selected and colors.white or colors.grey,
    },
  })

  for index = 1, MAX_ICONS do
    local app_name = apps[index]
    if app_name then
      local icon = app_icons[app_name] or app_icons["Default"]
      items.apps[index]:set({
        drawing = true,
        updates = true,
        icon = {
          string = icon,
          color = colors.with_alpha(colors.white, selected and 1.0 or 0.65),
          highlight_color = colors.white,
        },
      })
    else
      items.apps[index]:set({ drawing = false, updates = false })
    end
  end

  items.ellipsis:set({
    drawing = #apps > MAX_ICONS,
    updates = #apps > MAX_ICONS,
  })

  space:set({
    drawing = true,
    updates = true,
  })
  set_space_opacity(sid, selected)
end

local function parse_space_snapshot(result)
  local active_space = nil
  local present_spaces = {}
  local apps_by_space = {}

  for line in (result or ""):gmatch("[^\r\n]+") do
    local kind, first, second = line:match("^(%u)\t([^\t]+)\t?(.*)$")
    local sid = tonumber(first)
    if kind == "S" and sid then
      present_spaces[sid] = true
      if trim(second) == "true" then
        active_space = sid
      end
    elseif kind == "W" and sid then
      apps_by_space[sid] = apps_by_space[sid] or {}
      apps_by_space[sid][#apps_by_space[sid] + 1] = trim(second)
    end
  end

  return active_space, present_spaces, apps_by_space
end

local function refresh_spaces()
  sbar.exec(
    "yabai -m query --spaces | jq -r '.[] | \"S\\t\\(.index)\\t\\(.[\"has-focus\"])\"'; " ..
    "yabai -m query --windows | jq -r '.[] | select(.\"is-minimized\" == false) | \"W\\t\\(.space)\\t\\(.app)\"'",
    function(result)
      local active_space, present_spaces, apps_by_space = parse_space_snapshot(result)
      if not active_space then
        return
      end

      current_space = active_space
      for sid = 1, MAX_SPACES do
        refresh_space(sid, active_space, present_spaces, apps_by_space)
      end
    end
  )
end

for sid = 1, MAX_SPACES do
  local members = {}

  local label = sbar.add("item", "space" .. sid .. ".label", {
    position = "left",
    icon = {
      font = { family = settings.font.numbers, size = 16.0 },
      string = sid,
      padding_left = 4,
      padding_right = 0,
      color = colors.grey,
      highlight_color = colors.white,
    },
    drawing = false,
  })
  members[#members + 1] = label.name

  local apps = {}
  for index = 1, MAX_ICONS do
    local item = sbar.add("item", "space" .. sid .. ".app." .. index, {
      position = "left",
      drawing = false,
      updates = false,
      icon = {
        string = ":default:",
        font = "sketchybar-app-font:Regular:18.0",
        padding_left = 0,
        padding_right = 0,
        width = 18,
      },
      label = { drawing = false },
      background = { drawing = false },
    })
    apps[index] = item
    members[#members + 1] = item.name
  end

  local ellipsis = sbar.add("item", "space" .. sid .. ".app.ellipsis", {
    position = "left",
    drawing = false,
    updates = false,
    icon = {
      string = "...",
      color = colors.grey,
      highlight_color = colors.white,
      font = "sketchybar-app-font:Regular:16.0",
      padding_left = 0,
      padding_right = 0,
    },
    label = { drawing = false },
    background = { drawing = false },
  })
  members[#members + 1] = ellipsis.name

  local space = sbar.add("bracket", "space" .. sid, members, {
    drawing = false,
    updates = false,
    background = {
      color = colors.with_alpha(colors.bg2, 0.3),
      border_color = colors.with_alpha(colors.bg2, 0.3),
      height = 30,
    },
  })

  spaces[sid] = space
  space_items[sid] = {
    label = label,
    apps = apps,
    ellipsis = ellipsis,
  }

  for _, name in ipairs(members) do
    sbar.subscribe(name, "mouse.clicked", function()
      if current_space ~= sid then
        sbar.exec("yabai -m space --focus " .. sid)
      end
    end)
  end
end

sbar.add("item", "spaces.padding", {
  position = "left",
  width = settings.group_paddings,
  label = { drawing = false },
  icon = { drawing = false },
  background = { drawing = false },
})

local observer = sbar.add("item", {
  drawing = false,
  updates = true,
})

observer:subscribe({ "space_change", "space_windows_change", "display_change", "front_app_switched", "system_woke" }, function()
  refresh_spaces()
end)

refresh_spaces()

return spaces
