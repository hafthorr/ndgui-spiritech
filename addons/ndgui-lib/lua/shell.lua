-- One window frame that is mounted at load and filled later. The client wants every role's root widget
-- mounted while the script loads, but ndgui-mission-hub (Info + Missions in one
-- package) only learns which role a VM plays from the first callback. The hub mounts an empty frame
-- with S.mount(); the window module then calls S.window(options) instead of Window.create + ui.root
-- and gets that frame back, filled. Without a mounted shell S.window is plain Window.create + ui.root.
local Window = ui.require("core.window")
local S = {}
local TEMPLATE = "library://notum.ndgui-lib/window.xml"
local frame, layout_fn, adopted, fixed_size

function S.mount()
	local blank = ui.load("library://notum.ndgui-lib/hub_blank.xml")
	frame = Window.create({
		template = TEMPLATE, title = "", content = blank, width = 320, height = 200,
		layout = function(window, width, height)
			if fixed_size then
				-- a window that sizes itself (Mission Terminal): drop the size the frame was asked for
				-- before (placeholder, saved rectangle, a drag) so its height follows the content again
				ui.request_size(window.root, -1, -1)
			end
			if layout_fn then
				return layout_fn(window, width, height)
			end
			ui.request_size(window.root, width, height)
		end,
	})
	ui.root(frame.root)
	return frame
end

function S.window(options)
	if not frame or adopted then
		local window = Window.create(options)
		ui.root(window.root)
		return window
	end
	adopted = true
	local blank = frame.content
	ui.add(frame.content_slot, options.content)
	frame.content = options.content
	if not pcall(ui.destroy, blank) then
		ui.visible(blank, false)
	end
	ui.require("notum.ndgui-lib/title").set(frame.root, options.title or "") -- the docked page too
	if frame.placement and frame.placement.options then
		frame.placement.options.remember_open = options.remember_open ~= false
	end
	layout_fn = options.layout
	fixed_size = options.resizable == false
	local saved = frame.placement and frame.placement.intended
	if saved then
		frame:resize(saved.width, saved.height)
	else
		if options.horizontal or options.vertical then
			ui.align(frame.root, options.horizontal or "start", options.vertical or "start")
		end
		frame:resize(options.width or 320, options.height or 200)
	end
	return frame
end

return S
