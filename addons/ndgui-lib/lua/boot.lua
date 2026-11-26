-- Once per package VM: wrap core.window.create so DarkTech package chrome (buttons/pin)
-- is applied without GFX_NDGUI_* atlas entries. Loaded from grid.lua (every ndGUI package).
ui.define("notum.ndgui-lib/boot", function()
	-- Install the button visibility hook before this VM loads any more layouts.
	pcall(ui.require, "notum.ndgui-lib/button")
	local ok, Window = pcall(ui.require, "core.window")
	if not ok or type(Window) ~= "table" or type(Window.create) ~= "function" then
		return true
	end
	if Window.ndgui_boot then
		return true
	end
	local create = Window.create
	function Window.create(options)
		local window = create(options)
		local root = window and window.root
		if root then
			local bok, Button = pcall(ui.require, "notum.ndgui-lib/button")
			if bok and Button then
				pcall(Button.skin_tree, root)
				pcall(function()
					Button.bind_pin(ui.find(root, "window_pin"), ui.find(root, "ndgui_pin_on"))
				end)
			end
		end
		return window
	end
	Window.ndgui_boot = true
	return true
end)
