-- ndGUI Mission Terminal (prk.mission-terminal). Its own package so the real window exists
-- and the offer map is attached while this script loads, the way the built-in terminal does.
ui.require("notum.ndgui-lib/grid") -- ndGUI: snap to grid while moving/resizing (ndgui-lib/lua/grid.lua)
local Terminal = ui.require("notum.ndgui-lib/win_terminal")

mission_terminal_configure = Terminal.mission_terminal_configure
mission_terminal_sliders = Terminal.mission_terminal_sliders
mission_terminal_apply = Terminal.mission_terminal_apply
mission_terminal_map = Terminal.mission_terminal_map
mission_terminal_map_wheel = Terminal.mission_terminal_map_wheel
