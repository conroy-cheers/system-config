-- don't use sbar.exec here. This needs to block until we know if there's a battery
batt_info = io.popen("pmset -g batt"):read("*a")
local found, _, _ = batt_info:find("(%d+)%%")
if found then
    require("items.widgets.battery")
end
require("items.widgets.volume")
require("items.widgets.wifi")
require("items.widgets.cpu")
