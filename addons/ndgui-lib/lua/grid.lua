-- ndGUI: snap to a grid while moving or resizing any ndGUI window or HUD piece.
--
-- It follows the game's own snapping switch: Options > Interface & HUD > Windows and HUD >
-- magnetism above 0 turns on both edge snapping and this grid; 0 turns both off.
-- Edge snapping to another window wins when it catches; otherwise the dragged edge
-- (the nearer of the two when moving) lands on a grid line.
--
-- Every ndGUI package requires this once at load. Core's movement code looks up
-- Snapping.offset on each drag, so wrapping it here covers Window, Move and the HUD pieces
-- in this package's VM. SIZE is in pixels (below 2 = off). The installer sets it
-- (menu: Snap-to-grid size, or install.py --grid 20) and keeps it across updates.
local SIZE = 10

local M = { size = SIZE }

-- offset that puts the leading (left/top) or trailing (right/bottom) edge on the grid.
-- start/size: the proposed rectangle on one axis; room: the parent's size on that axis.
-- When sizing, only the dragged edge moves (start shifts for the leading edge, size changes for
-- either); minimum/maximum bound the size. Returns 0 when no grid line fits.
function M.snap(start, size, room, leading, trailing, sizing, minimum, maximum)
	local g = M.size
	if g < 2 then
		return 0
	end
	minimum, maximum = minimum or size, maximum or size
	local best
	local function try(offset, edge)
		local next_start, next_size = start, size
		if not sizing or edge == 1 then
			next_start = start + offset
		end
		if sizing then
			next_size = size + (edge == 1 and -offset or offset)
		end
		if next_start < 0 or next_start + next_size > room or next_size < minimum or next_size > maximum then
			return
		end
		if best == nil or math.abs(offset) < math.abs(best) then
			best = offset
		end
	end
	if leading then
		try(math.floor(start / g + 0.5) * g - start, 1)
	end
	if trailing then
		local finish = start + size
		try(math.floor(finish / g + 0.5) * g - finish, 2)
		if not sizing then
			try(room - finish, 2) -- flush with the screen edge counts as on the grid
		end
	end
	if best == nil or math.abs(best) > g / 2 + 0.001 then
		return 0
	end
	return best
end

local ok, Snapping = pcall(ui.require, "core.snapping")
if ok and type(Snapping) == "table" and type(Snapping.offset) == "function" and not Snapping.ndgui_grid then
	local edges = Snapping.offset
	local function wrapped(view, x, y, width, height, left, right, top, bottom, sizing)
		local dx, dy = edges(view, x, y, width, height, left, right, top, bottom, sizing)
		if M.size < 2 or ui.movable_geometry.magnetism() <= 0 then
			return dx, dy
		end
		local min_w, max_w, min_h, max_h = width, width, height, height
		if sizing then
			min_w, min_h = math.max(1, ui.minimum_width(view)), math.max(1, ui.minimum_height(view))
			max_w, max_h = ui.maximum_width(view), ui.maximum_height(view)
			if max_w < 0 then max_w = ui.parent_width(view) end
			if max_h < 0 then max_h = ui.parent_height(view) end
		end
		if dx == 0 and (left or right) then
			dx = M.snap(x, width, ui.parent_width(view), left, right, sizing, min_w, max_w)
		end
		if dy == 0 and (top or bottom) then
			dy = M.snap(y, height, ui.parent_height(view), top, bottom, sizing, min_h, max_h)
		end
		return dx, dy
	end
	M.active = pcall(function()
		Snapping.offset = wrapped
		Snapping.ndgui_grid = M
	end)
end

return M
