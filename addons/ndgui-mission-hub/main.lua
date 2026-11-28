-- ndGUI Mission Hub: Info and Missions from one package, so Info can keep each mission
-- briefing it shows (ndgui-lib briefs.lua, in this package's ui.storage) and the Missions
-- side pane can show it. The Mission Terminal is its own package: the offer map has to be
-- attached while that package loads, on the window that stays. The client runs each role in
-- its own VM and every VM sees every game.* domain, so a VM only learns its role from the
-- first callback it receives. The client still wants a root widget mounted at load: an empty
-- frame (ndgui-lib shell.lua) that the window module fills on that first callback.
ui.require("notum.ndgui-lib/grid") -- ndGUI: snap to grid while moving/resizing (ndgui-lib/lua/grid.lua)
ui.require("notum.ndgui-lib/shell").mount()
-- an Info package must declare its page surface at load too (harmless in the Missions VM)
pcall(ui.require, "notum.ndgui-lib/info_page")
local kind, impl

local function get(wanted)
	if not kind then
		kind = wanted
		impl = ui.require("notum.ndgui-lib/win_" .. wanted)
	end
	return kind == wanted and impl or nil
end

local function route(wanted, name)
	return function(...)
		local window = get(wanted)
		if window and window[name] then
			return window[name](...)
		end
	end
end

info_show = route("info", "info_show")
info_navigate = route("info", "info_navigate")
info_update = route("info", "info_update")
info_impact_width = route("info", "info_impact_width")
missions_apply = route("missions", "missions_apply")
