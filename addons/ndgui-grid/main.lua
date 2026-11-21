-- ndGUI Grid Overlay (standalone addon: Control Center > Actions > Addons > Grid Overlay).
-- Draws the snap grid (ndgui-lib/lua/grid.lua, the installer's grid size) over the whole screen,
-- with amber lines through the screen centre, to help line up and centre windows and HUD pieces.
-- It takes no clicks: open it, arrange things, close it again from the same menu.
local Grid = ui.require("notum.ndgui-lib/grid")

local M = {}
M.MIN_STEP = 20          -- a smaller grid draws every 2nd/3rd... line, so a 5 px grid stays readable
M.MAX_LINES = 160        -- per direction, so a tiny grid on a huge screen stays inside the widget budget
M.LINE = "#28FFFFFF"     -- faint white
M.MAJOR = "#50FFFFFF"    -- every 5th drawn line
M.CENTER = "#A0FFB040"   -- amber centre lines

function M.step(size, extent)
	if size < 2 then
		size = 10
	end
	local step = size * math.max(1, math.ceil(M.MIN_STEP / size))
	while extent / step > M.MAX_LINES do
		step = step + size
	end
	return step
end

local root = ui.load("root.xml")
ui.root(root)
local grid = ui.load("grid.xml")
ui.add(root, grid)
ui.register_view(grid, "grid")
ui.click_through(grid, true) -- clicks go to whatever is under the lines

local layers = {}
local shown_w, shown_h, shown_size

-- one direction of lines: cells of `step` pixels, each starting with a 1 px line
local function lines(horizontal, extent, other, step, color_of)
	local layer = ui.load(horizontal and "layer_h.xml" or "layer_v.xml")
	ui.add(grid, layer)
	local index, at = 0, 0
	while at < extent do
		local width = math.min(step, extent - at)
		local cell = ui.load(horizontal and "cell_h.xml" or "cell_v.xml")
		ui.add(layer, cell)
		local line = ui.find(cell, "grid_line")
		if horizontal then
			ui.limits(cell, width, other, width, other)
			ui.limits(line, 1, other, 1, other)
		else
			ui.limits(cell, other, width, other, width)
			ui.limits(line, other, 1, other, 1)
		end
		ui.fill_color(line, color_of(index, at))
		index, at = index + 1, at + step
	end
	layers[#layers + 1] = layer
end

-- the centre line: an empty cell up to the middle, then a 1 px amber line
local function centre(horizontal, extent, other)
	local layer = ui.load(horizontal and "layer_h.xml" or "layer_v.xml")
	ui.add(grid, layer)
	local half = math.floor(extent / 2)
	for part = 1, 2 do
		local cell = ui.load(horizontal and "cell_h.xml" or "cell_v.xml")
		ui.add(layer, cell)
		local line = ui.find(cell, "grid_line")
		local length = part == 1 and half or 1
		if horizontal then
			ui.limits(cell, length, other, length, other)
			ui.limits(line, 1, other, 1, other)
		else
			ui.limits(cell, other, length, other, length)
			ui.limits(line, other, 1, other, 1)
		end
		ui.fill_color(line, part == 1 and "" or M.CENTER)
	end
	layers[#layers + 1] = layer
end

function M.build(w, h, size)
	for _, layer in ipairs(layers) do
		ui.destroy(layer)
	end
	layers = {}
	ui.limits(grid, w, h, w, h)
	ui.request_size(grid, w, h)
	local step = M.step(size, math.max(w, h))
	local function color(index)
		return index % 5 == 0 and M.MAJOR or M.LINE
	end
	lines(true, w, h, step, color)
	lines(false, h, w, step, color)
	centre(true, w, h)
	centre(false, h, w)
	shown_w, shown_h, shown_size = w, h, size
end

local function refresh()
	local w, h = math.floor(ui.parent_width(grid)), math.floor(ui.parent_height(grid))
	if w > 0 and h > 0 and (w ~= shown_w or h ~= shown_h or Grid.size ~= shown_size) then
		M.build(w, h, Grid.size)
	end
end

refresh()
ui.on_update(refresh) -- follows window resizes / resolution changes


