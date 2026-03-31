local settings = require("settings")
local colors = require("colors")

-- Padding item required because of bracket
sbar.add("item", { position = "right", width = settings.group_paddings })

local cal = sbar.add("item", {
	icon = {
		color = colors.white,
		padding_left = 8,
		-- padding_right = 20,
		font = {
			style = settings.font.style_map["Regular"],
			size = 12.0,
		},
	},
	label = {
		color = colors.white,
		padding_right = 8,
		-- padding_left = 20,
		-- width = 49,
		align = "right",
		font = { style = "Regular", family = settings.font.numbers, size = 12.0 },
	},
	position = "right",

	update_freq = 1,
	padding_left = 1,
	padding_right = 1,
	-- background = {
	-- color = colors.bg2,
	-- border_color = colors.black,
	-- border_width = 1
	-- },
	-- click_script = "open -a 'Calendar'"
})

-- Double border for calendar using a single item bracket
sbar.add("bracket", { cal.name }, {
	background = {
		color = colors.with_alpha(colors.bg2, 0.5),
		border_color = colors.with_alpha(colors.bg2, 0.5),
		-- border_width = 1,
		height = 30,
		-- border_color = colors.grey,
	},
})

-- Padding item required because of bracket
sbar.add("item", { position = "right", width = 6 })

cal:subscribe({ "forced", "routine", "system_woke" }, function(env)
	cal:set({ icon = os.date("%a %d %b"), label = os.date("%I:%M:%S %p") })
end)

return cal
