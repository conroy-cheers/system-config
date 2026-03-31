local apple = require("items.apple")
require("items.menus")
local spaces = require("items.spaces")
local front_app = require("items.front_app")
local calendar = require("items.calendar")
local widgets = require("items.widgets")
-- require("items.media")
local colors = require("colors")

-- local right_elements = {}
-- right_elements[#right_elements + 1] = apple.name
-- for k,v in pairs(spaces) do
--     right_elements[#right_elements + 1] = v.name
-- end
-- -- right_elements[#right_elements + 1] = front_app.name
--
--
-- local right_bar = sbar.add("bracket", right_elements, {
--     background ={
--         color = colors.bg2,
--         border_color = colors.bg2,
--         height = 32,
--         -- width=40,
--         -- border_width = 2
--     }
-- })
--
-- local left_bar = sbar.add("bracket", {
--     "widgets.battery",
--     "widgets.volume.bracket",
--     "widgets.wifi.bracket",
--     "widgets.cpu"
-- }, {
--     background ={
--         color = colors.bg2,
--         border_color = colors.bg2,
--         height = 32,
--         -- width=40,
--         -- border_width = 2
--     }
-- })
