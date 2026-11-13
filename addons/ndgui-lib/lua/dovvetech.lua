-- Shared Dovvetech tokens and HUD geometry for every notum.ndgui-* package.
-- Colors mirror theme.lua (darktech, "Notum Dovvetech Dark"); tests check they match.
-- Layout follows classic ndGUI: slim menubar on the bottom edge, vertical HP/NP bars
-- flanking the character, compass top-centre, XP strip sitting on the menubar.
local M = {}

M.color = {
	panel = "#0e141b",
	panel_alt = "#16202a",
	border = "#3d6f9a",
	text = "#c5d7e6",
	text_dim = "#7f9bb0",
	accent = "#3d8fd4",
	health = "#c44747",
	nano = "#2f7ec4",
	xp = "#c6a24e",
	bar_track = "#080c10",
	menu = "#0a1016",
	focus = "#6cb6ff",
}

-- Bottom strip (ndgui-control-center) height and the space its two icon clusters take.
M.MENU_H = 30
M.STRIP_LEFT_W = 440
M.STRIP_RIGHT_W = 470
M.STRIP_GAP = 12
M.MARGIN = 8

-- Vertical vitals: ndGUI art bars (track + fill), 14 wide, 140 tall, caption below.
M.VITAL_W = 14
M.VITAL_BAR_H = 140
M.VITAL_H = 142
M.VITAL_LABEL_W = 96
M.VITAL_LABEL_H = 18
-- Horizontal distance from screen centre to each vertical bar.
M.VITAL_OFFSET = 190

-- XP strip: thin horizontal bars just above the bottom menubar.
M.XP_H = 16
M.XP_GAP = 4

function M.xp_width(viewport_width)
	viewport_width = viewport_width or 1920
	local room = viewport_width - M.STRIP_LEFT_W - M.STRIP_RIGHT_W - 3 * M.STRIP_GAP
	return math.max(160, math.min(560, math.floor(room / 2)))
end

-- Returns x, y, w, h for a status-bar kind's root view.
function M.status_rect(kind, viewport_width, viewport_height)
	viewport_width = viewport_width or 1920
	viewport_height = viewport_height or 1080
	local centre_x = math.floor(viewport_width * 0.5)
	local vital_y = math.floor(viewport_height * 0.5)
	local label_w = M.VITAL_LABEL_W
	local h = M.VITAL_H + M.VITAL_LABEL_H
	if kind == "health" then
		return centre_x - M.VITAL_OFFSET - math.floor(label_w / 2), vital_y, label_w, h
	elseif kind == "nano" then
		return centre_x + M.VITAL_OFFSET - math.floor(label_w / 2), vital_y, label_w, h
	end
	-- XP and AXP dock inside the bottom strip, between the two icon clusters.
	local w = M.xp_width(viewport_width)
	local y = viewport_height - M.MENU_H + math.floor((M.MENU_H - M.XP_H) / 2)
	local x = M.STRIP_LEFT_W + M.STRIP_GAP
	if kind == "experience" then
		return x, y, w, M.XP_H
	end
	return x + w + M.STRIP_GAP, y, w, M.XP_H -- alien
end

-- Make a provider root draggable with its own saved pose (separate from stock poses,
-- so old stock positions do not drag ndGUI pieces back). Returns the placement object;
-- callers apply default positions only while placement.moved is false.
M.PLACEMENT_FIELD = "NdguiFrame"

-- options.lock_key: adds a right-click "Lock position" toggle, saved in the view's own state scope
-- (ui.state, like the pose; HUD VMs have no ui.preference).
function M.movable(view, options)
	options = options or {}
	local placement = ui.require("core.placement").attach(view, { only_moved = true, field = options.field or M.PLACEMENT_FIELD })
	local move = ui.require("core.move")
	local key, locked = options.lock_key, false
	if key then
		locked = ui.state.read(view, key) == "true"
	end
	move.attach(view, {
		placement = placement,
		handle = options.handle,
		enabled = function(x, y)
			if locked then
				return false
			end
			return not options.enabled or options.enabled(x, y)
		end,
	})
	if key then
		local anchor = options.handle or view
		ui.on_pointer_release(anchor, "right", function()
			ui.menu.clear(anchor)
			pcall(ui.menu.style, anchor, "context")
			ui.menu.add(anchor, "Lock position", locked, function()
				locked = not locked
				ui.state.write(view, key, tostring(locked), "bool")
			end)
			ui.menu.show(anchor)
		end)
	end
	return placement
end

function M.place_default(placement, view, x, y)
	if placement and placement.moved then
		return false
	end
	ui.place(view, x, y)
	return true
end

-- Top edge: compass centred, target panels either side.
M.TOP_Y = 4
M.COMPASS_CLEARANCE = 90

return M
