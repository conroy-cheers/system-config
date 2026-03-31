return {
	black = 0xff181819,
	white = 0xffe2e2e3,
	red = 0xfffc5d7c,
	green = 0xff9ed072,
	blue = 0xff2b82c9,
	yellow = 0xffe7c664,
	orange = 0xffd9774f,
	magenta = 0xffb39df3,
	grey = 0xff7f8490,
	dark_grey = 0xff4b4e5a,
	purple = 0xff8b5cf6,
	dark_purple = 0xff5e42a6,
	transparent = 0x00000000,
    navy = 0xff202040,
	bar = {
		bg = 0xf02c2e34,
		border = 0xff2c2e34,
	},
	popup = {
		bg = 0xc02c2e34,
		border = 0xff7f8490,
	},
	bg1 = 0xff363944,
	bg2 = 0xff3e4150,

	with_alpha = function(color, alpha)
		if alpha > 1.0 or alpha < 0.0 then
			return color
		end
		return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
	end,
}
