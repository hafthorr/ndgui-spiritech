-- Dovvetech prk.compass provider: a clean heading strip centred on the top edge.
ui.require("notum.ndgui-lib/grid") -- ndGUI: snap to grid while moving/resizing (ndgui-lib/lua/grid.lua)
-- Our own art (skin.py GFX_GUI_NDGUI_COMPASS_*): a dotted line with N / E / S / W, NE..NW and 15-degree ticks,
-- a green waypoint marker riding the line, a caret where you face, and the waypoint distance under it.
-- Light ink with a black outline, no backing plate, so it reads on snow and at night.
-- Falls back to the stock band if the ndGUI skin is not installed.
local D = ui.require("notum.ndgui-lib/dovvetech")
local root = ui.load("window.xml")
ui.root(root)
local placement = D.movable(root)

local band = ui.find(root, "compass_band")
local box = ui.find(root, "compass_box")
local back = ui.find(root, "ndgui_compass_back")
local frame = ui.find(root, "ndgui_compass_frame")
local label = ui.find(root, "compass_label")
local distance = ui.find(root, "compass_distance")
local distance_shadow = ui.find(root, "compass_distance_shadow")

local OURS = { band = "GFX_GUI_NDGUI_COMPASS_BAND", waypoint = "GFX_GUI_NDGUI_COMPASS_WAYPOINT",
	caret = "GFX_GUI_NDGUI_COMPASS_CARET" }
local STOCK = { band = "GFX_GUI_COMPASS_SCALE", waypoint = "GFX_GUI_COMPASS_WAYPOINT" }
local VIEW_W, BAND_H, LABEL_H = 320, 54, 14
local LINE_Y, MARKER_Y, CARET_Y = 27, 14, 48 -- band line, waypoint marker centre (its tip on the line), caret
local EDGE = 14 -- a waypoint outside the visible arc sticks to this far from the edge
local turn = math.pi * 2
local art, band_width, view_width, view_height

local function choose_art()
	local width = ui.compass.graphic_width(OURS.band)
	if width > 0 then
		art, band_width = OURS, width
		view_width, view_height = VIEW_W, BAND_H
	else
		art, band_width = STOCK, ui.compass.graphic_width(STOCK.band)
		view_width, view_height = 129, 14
	end
	local framed = art == STOCK
	local box_w, box_h = framed and 137 or view_width, framed and 22 or view_height
	ui.visible(back, framed)
	ui.visible(frame, framed)
	ui.size(box, box_w, box_h)
	ui.size(back, box_w, box_h)
	ui.size(frame, box_w, box_h)
	ui.borders(band, framed and 4 or 0, framed and 4 or 0, framed and 4 or 0, framed and 4 or 0)
	if framed then
		ui.graphic_tint(frame, D.color.border)
	end
	ui.size(band, view_width, view_height)
	ui.size(label, box_w, LABEL_H)
	ui.size(distance, view_width, LABEL_H)
	ui.size(distance_shadow, view_width - 1, LABEL_H - 1)
	ui.size(root, box_w, box_h + LABEL_H)
end

local function metres(d)
	if d >= 1000 then
		return string.format("%.1f km", d / 1000)
	end
	return string.format("%d m", math.floor(d + 0.5))
end

function compass_place(screen_width)
	if not art then choose_art() end
	D.place_default(placement, root, math.floor(screen_width * 0.5 - view_width / 2), D.TOP_Y)
end

function compass_apply(reading)
	if not art or band_width <= 0 then
		choose_art()
	end
	if band_width <= 0 or not reading.has_heading then
		return
	end
	local ours = art == OURS
	local line_y = ours and LINE_Y or view_height / 2
	local offset = (band_width * (-(reading.heading - math.pi / 2) / turn) - view_width / 2) % band_width
	ui.compass.offset(band, offset, 0)
	ui.compass.begin(band)
	ui.compass.sprite(band, art.band, band_width / 2, line_y)
	ui.compass.sprite(band, art.band, band_width * 1.5, line_y)
	local text = ""
	if reading.has_waypoint and reading.has_position and reading.waypoint_playfield == reading.playfield then
		local dx, dz = reading.waypoint_x - reading.x, reading.waypoint_z - reading.z
		local bearing = math.atan(dz, dx) % turn
		local shift = (reading.heading - bearing) / turn * band_width
		local column = view_width / 2 + shift - math.floor(shift / band_width + 0.5) * band_width
		if ours then
			column = math.max(EDGE, math.min(view_width - EDGE, column))
		end
		ui.compass.sprite(band, art.waypoint, offset + column, ours and MARKER_Y or line_y)
		text = metres(math.sqrt(dx * dx + dz * dz))
	end
	if ours then
		ui.compass.sprite(band, art.caret, offset + view_width / 2, CARET_Y)
	end
	ui.compass.finish(band)
	ui.text(distance, text)
	ui.text(distance_shadow, text)
end
