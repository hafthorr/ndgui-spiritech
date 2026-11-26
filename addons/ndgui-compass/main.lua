-- Dovvetech prk.compass provider: a clean heading strip centred on the top edge.
-- Marketplace build: letters and 15-degree ticks are TextViews/Views placed with ui.place at
-- 3 px per degree (same scale as the old atlas band: 320 px wide shows about 107°). Waypoint
-- and caret use library:// PNGs. Falls back to the stock band if the package strip is missing.
ui.require("notum.ndgui-lib/grid")
local D = ui.require("notum.ndgui-lib/dovvetech")
local root = ui.load("window.xml")
ui.root(root)
local placement = D.movable(root)

local function try_find(name)
	local ok, view = pcall(ui.find, root, name)
	return ok and view or nil
end

local pkg = try_find("compass_pkg")
local marks_box = try_find("pkg_marks")
local baseline = try_find("pkg_baseline")
local pkg_waypoint = try_find("pkg_waypoint")
local pkg_caret = try_find("pkg_caret")
local box = ui.find(root, "compass_box")
local band = ui.find(root, "compass_band")
local back = ui.find(root, "ndgui_compass_back")
local frame = ui.find(root, "ndgui_compass_frame")
local label = ui.find(root, "compass_label")
local distance = ui.find(root, "compass_distance")
local distance_shadow = ui.find(root, "compass_distance_shadow")

local STOCK = { band = "GFX_GUI_COMPASS_SCALE", waypoint = "GFX_GUI_COMPASS_WAYPOINT" }
local VIEW_W, BAND_H, LABEL_H = 320, 54, 14
local PX_PER_DEG = 3
local BAND_W = 360 * PX_PER_DEG -- 1080, matches skin.py COMPASS_W
local WAYPOINT_W, WAYPOINT_H = 23, 29
local CARET_W, CARET_H = 15, 9
local LINE_Y, MARKER_Y, CARET_Y = 27, 14, 48
local EDGE = 14
local turn = math.pi * 2
local INK, NORTH = "#C8E6FF", "#FFD84A"
local use_pkg, band_width, view_width, view_height = true, BAND_W, VIEW_W, BAND_H

local marks = {}

local function load_mark(file, name)
	local view = ui.load(file)
	ui.add(marks_box, view)
	return ui.find(view, name)
end

local function build_marks()
	if not marks_box or #marks > 0 then
		return
	end
	local letters = {
		{ "N", math.pi / 2, true }, { "NE", math.pi / 4 }, { "E", 0, true }, { "SE", -math.pi / 4 },
		{ "S", -math.pi / 2, true }, { "SW", -3 * math.pi / 4 }, { "W", math.pi, true }, { "NW", 3 * math.pi / 4 },
	}
	for _, spec in ipairs(letters) do
		local view = load_mark("letter.xml", "letter")
		ui.text(view, spec[1])
		ui.text_color(view, spec[1] == "N" and NORTH or INK)
		ui.font_size(view, spec[3] and 12 or 10)
		marks[#marks + 1] = { view = view, angle = spec[2], kind = "letter", major = spec[3], width = 0, height = 14 }
	end
	for step = 0, 23 do
		if step % 3 ~= 0 then
			local view = load_mark("tick.xml", "tick")
			ui.fill_color(view, INK)
			marks[#marks + 1] = { view = view, angle = step * math.pi / 12, kind = "tick", width = 1, height = 5 }
		end
	end
end

local function layout_pkg()
	view_width, view_height, band_width = VIEW_W, BAND_H, BAND_W
	build_marks()
	ui.visible(pkg, true)
	ui.visible(box, false)
	ui.visible(back, false)
	ui.visible(frame, false)
	ui.size(pkg, view_width, view_height)
	if marks_box then
		ui.size(marks_box, view_width, view_height)
	end
	if baseline then
		ui.size(baseline, view_width, 1)
		ui.place(baseline, 0, LINE_Y)
	end
	ui.size(pkg_waypoint, WAYPOINT_W, WAYPOINT_H)
	ui.size(pkg_caret, CARET_W, CARET_H)
	for _, mark in ipairs(marks) do
		if mark.kind == "tick" then
			ui.size(mark.view, 1, mark.height)
		end
		mark.width = 0
	end
	ui.size(label, view_width, LABEL_H)
	ui.size(distance, view_width, LABEL_H)
	ui.size(distance_shadow, view_width - 1, LABEL_H - 1)
	ui.size(root, view_width, view_height + LABEL_H)
end

local function layout_stock()
	use_pkg = false
	band_width = ui.compass.graphic_width(STOCK.band)
	view_width, view_height = 129, 14
	local box_w, box_h = 137, 22
	if pkg then
		ui.visible(pkg, false)
	end
	ui.visible(box, true)
	ui.visible(back, true)
	ui.visible(frame, true)
	ui.size(box, box_w, box_h)
	ui.size(back, box_w, box_h)
	ui.size(frame, box_w, box_h)
	ui.borders(band, 4, 4, 4, 4)
	ui.graphic_tint(frame, D.color.border)
	ui.size(band, view_width, view_height)
	ui.size(label, box_w, LABEL_H)
	ui.size(distance, view_width, LABEL_H)
	ui.size(distance_shadow, view_width - 1, LABEL_H - 1)
	ui.size(root, box_w, box_h + LABEL_H)
end

local sized = false

local function choose_art()
	if marks_box and pkg_waypoint and pkg_caret and pkg then
		use_pkg = true
		layout_pkg()
	else
		layout_stock()
	end
	sized = true
end

local function metres(d)
	if d >= 1000 then
		return string.format("%.1f km", d / 1000)
	end
	return string.format("%d m", math.floor(d + 0.5))
end

local function wrap(angle)
	return (angle + math.pi) % turn - math.pi
end

-- x on the strip for a world angle; on_strip when it falls inside the visible arc
local function column(heading, angle)
	local offset = wrap(heading - angle)
	local x = view_width / 2 + offset * (band_width / turn)
	return x, math.abs(offset) <= (view_width / 2) * (turn / band_width)
end

function compass_place(screen_width)
	if not sized then choose_art() end
	D.place_default(placement, root, math.floor(screen_width * 0.5 - view_width / 2), D.TOP_Y)
end

local function apply_pkg(reading)
	local heading = reading.heading
	for _, mark in ipairs(marks) do
		if mark.kind == "letter" and mark.width == 0 then
			mark.width = ui.text_width(mark.view)
		end
		local x, on_strip = column(heading, mark.angle)
		local left = math.floor(x - mark.width / 2 + 0.5)
		local fits = on_strip and left >= 2 and left + mark.width <= view_width - 2
		ui.visible(mark.view, fits)
		if fits then
			if mark.kind == "letter" then
				ui.place(mark.view, left, math.floor(LINE_Y - mark.height / 2 + 0.5))
			else
				ui.place(mark.view, left, LINE_Y - mark.height)
			end
		end
	end

	local text = ""
	if reading.has_waypoint and reading.has_position and reading.waypoint_playfield == reading.playfield then
		local dx, dz = reading.waypoint_x - reading.x, reading.waypoint_z - reading.z
		local bearing = math.atan(dz, dx)
		local x = column(heading, bearing)
		x = math.max(EDGE, math.min(view_width - EDGE, x))
		ui.visible(pkg_waypoint, true)
		ui.place(pkg_waypoint, math.floor(x - WAYPOINT_W / 2 + 0.5), MARKER_Y - math.floor(WAYPOINT_H / 2))
		text = metres(math.sqrt(dx * dx + dz * dz))
	else
		ui.visible(pkg_waypoint, false)
	end
	ui.place(pkg_caret, math.floor(view_width / 2 - CARET_W / 2 + 0.5), CARET_Y - math.floor(CARET_H / 2))
	ui.text(distance, text)
	ui.text(distance_shadow, text)
end

local function apply_stock(reading)
	if band_width <= 0 then
		return
	end
	local line_y = view_height / 2
	local offset = (band_width * (-(reading.heading - math.pi / 2) / turn) - view_width / 2) % band_width
	ui.compass.offset(band, offset, 0)
	ui.compass.begin(band)
	ui.compass.sprite(band, STOCK.band, band_width / 2, line_y)
	ui.compass.sprite(band, STOCK.band, band_width * 1.5, line_y)
	local text = ""
	if reading.has_waypoint and reading.has_position and reading.waypoint_playfield == reading.playfield then
		local dx, dz = reading.waypoint_x - reading.x, reading.waypoint_z - reading.z
		local bearing = math.atan(dz, dx) % turn
		local shift = (reading.heading - bearing) / turn * band_width
		local col = view_width / 2 + shift - math.floor(shift / band_width + 0.5) * band_width
		ui.compass.sprite(band, STOCK.waypoint, offset + col, line_y)
		text = metres(math.sqrt(dx * dx + dz * dz))
	end
	ui.compass.finish(band)
	ui.text(distance, text)
	ui.text(distance_shadow, text)
end

function compass_apply(reading)
	if not sized then
		choose_art()
	end
	if not reading.has_heading then
		return
	end
	if use_pkg then
		apply_pkg(reading)
	else
		apply_stock(reading)
	end
end
