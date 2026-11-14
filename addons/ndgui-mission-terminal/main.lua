-- ndGUI Mission Terminal (prk.mission-terminal): the window lives in ndgui-lib (win_terminal.lua) so
-- ndgui-mission-hub can provide it too, with the briefings Info kept.
local W = ui.require("notum.ndgui-lib/win_terminal")
mission_terminal_configure = W.mission_terminal_configure
mission_terminal_sliders = W.mission_terminal_sliders
mission_terminal_apply = W.mission_terminal_apply
