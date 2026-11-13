-- Dovvetech prk.compass provider: stock band math, centred on the top edge (classic ndGUI).
local D = ui.require("notum.ndgui-lib/dovvetech")
local root = ui.load("window.xml")
ui.root(root)
local placement = D.movable(root)

local extent_width = 136
local extent_height = 21
local frame_inset = 4
local width = extent_width + 1
local height = extent_height + 1
local view_width = width - frame_inset * 2
local view_height = height - frame_inset * 2
local band = ui.find(root, "compass_band")
local band_graphic = "GFX_GUI_COMPASS_SCALE"
local waypoint_graphic = "GFX_GUI_COMPASS_WAYPOINT"
local band_width = 0
local turn = math.pi * 2

ui.size(root, width, height)
ui.graphic_tint(ui.find(root, "ndgui_compass_frame"), D.color.border)

function compass_place(screen_width)
	D.place_default(placement, root, math.floor(screen_width * 0.5 - width / 2), D.TOP_Y)
end

function compass_apply(reading)
	if band_width == 0 then
		band_width = ui.compass.graphic_width(band_graphic)
	end
	if band_width <= 0 or not reading.has_heading then
		return
	end

	local offset = (band_width * (-(reading.heading - math.pi / 2) / turn) - view_width / 2) % band_width
	local centre_y = view_height / 2
	ui.compass.offset(band, offset, 0)
	ui.compass.begin(band)
	ui.compass.sprite(band, band_graphic, band_width / 2, centre_y)
	ui.compass.sprite(band, band_graphic, band_width * 1.5, centre_y)
	if reading.has_waypoint and reading.has_position and reading.waypoint_playfield == reading.playfield then
		local bearing = math.atan(reading.waypoint_z - reading.z, reading.waypoint_x - reading.x) % turn
		local shift = (reading.heading - bearing) / turn * band_width
		local column = view_width / 2 + shift - math.floor(shift / band_width + 0.5) * band_width
		ui.compass.sprite(band, waypoint_graphic, offset + column, centre_y)
	end
	ui.compass.finish(band)
end
