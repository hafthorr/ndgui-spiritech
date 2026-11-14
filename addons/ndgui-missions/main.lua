-- ndGUI Missions (prk.missions): the window lives in ndgui-lib (win_missions.lua) so ndgui-mission-hub
-- can provide it too. On its own it cannot see mission briefings (those reach the Info window only).
local W = ui.require("notum.ndgui-lib/win_missions")
missions_apply = W.missions_apply
