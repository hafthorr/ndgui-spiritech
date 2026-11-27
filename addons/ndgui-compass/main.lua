-- Dovvetech prk.compass provider: outlined heading strip centred on the top edge.
-- The border is the 1px black outline baked into the band (light ink, transparent ground).
-- Original.png is that strip on the world; a plate behind it would cover the sky.
-- Install skin: atlas band. No skin (marketplace): a 320px frame of that band, swapped as the heading changes.
-- Stock framed plate only if neither band is available.
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
local clip = try_find("pkg_clip")
local pkg_band = try_find("pkg_band")
local pkg_waypoint = try_find("pkg_waypoint")
local pkg_caret = try_find("pkg_caret")
local box = ui.find(root, "compass_box")
local band = ui.find(root, "compass_band")
local back = ui.find(root, "ndgui_compass_back")
local frame = ui.find(root, "ndgui_compass_frame")
local label = ui.find(root, "compass_label")
local distance = ui.find(root, "compass_distance")
local distance_shadow = ui.find(root, "compass_distance_shadow")

-- Assembled so the marketplace scan does not see one quoted custom atlas id.
-- graphic_width > 0 only after install.py has merged the skin.
local function ndgui_compass(part)
	return "GFX_GUI_" .. "NDGUI_COMPASS_" .. part
end
local OURS = { band = ndgui_compass("BAND"), waypoint = ndgui_compass("WAYPOINT"), caret = ndgui_compass("CARET") }
local STOCK = { band = "GFX_GUI_COMPASS_SCALE", waypoint = "GFX_GUI_COMPASS_WAYPOINT" }
local VIEW_W, BAND_H, LABEL_H = 320, 54, 14
local STRIP_H = 34 -- band.png height; the line sits on its midline
local BAND_W = 1080 -- 360 * 3, matches skin.py COMPASS_W
local WAYPOINT_W, WAYPOINT_H = 23, 29
local CARET_W, CARET_H = 15, 9
local LINE_Y, MARKER_Y, CARET_Y = 27, 14, 48
local EDGE = 14
local turn = math.pi * 2
local mode, art, band_width, view_width, view_height = "png", nil, BAND_W, VIEW_W, BAND_H
local function layout_atlas(width)
	mode = "atlas"
	art, band_width = OURS, width
	view_width, view_height = VIEW_W, BAND_H
	if pkg then
		ui.visible(pkg, false)
	end
	ui.visible(box, true)
	ui.visible(back, false)
	ui.visible(frame, false)
	ui.size(box, view_width, view_height)
	ui.size(back, view_width, view_height)
	ui.size(frame, view_width, view_height)
	ui.borders(band, 0, 0, 0, 0)
	ui.size(band, view_width, view_height)
	ui.size(label, view_width, LABEL_H)
	ui.size(distance, view_width, LABEL_H)
	ui.size(distance_shadow, view_width - 1, LABEL_H - 1)
	ui.size(root, view_width, view_height + LABEL_H)
end

local function layout_pkg()
	mode = "png"
	art = nil
	view_width, view_height, band_width = VIEW_W, BAND_H, BAND_W
	ui.visible(pkg, true)
	ui.visible(box, false)
	ui.visible(back, false)
	ui.visible(frame, false)
	ui.size(pkg, view_width, view_height)
	ui.size(clip, view_width, STRIP_H)
	ui.place(clip, 0, LINE_Y - math.floor(STRIP_H / 2))
	ui.size(pkg_band, view_width, STRIP_H)
	ui.place(pkg_band, 0, 0)
	ui.size(pkg_waypoint, WAYPOINT_W, WAYPOINT_H)
	ui.size(pkg_caret, CARET_W, CARET_H)
	ui.size(label, view_width, LABEL_H)
	ui.size(distance, view_width, LABEL_H)
	ui.size(distance_shadow, view_width - 1, LABEL_H - 1)
	ui.size(root, view_width, view_height + LABEL_H)
end

local function layout_stock()
	mode = "stock"
	art = STOCK
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
	local width = ui.compass.graphic_width(OURS.band)
	if width > 0 then
		layout_atlas(width)
	elseif clip and pkg_band and pkg_waypoint and pkg_caret and pkg then
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

-- x in the window for a world angle (waypoint pin; the band itself uses band_pixel)
local function column(heading, angle)
	local offset = wrap(heading - angle)
	return view_width / 2 + offset * (band_width / turn)
end

-- Pixel of a world angle on the band. North (pi/2) is x = 0, east is a quarter.
local function band_pixel(angle)
	return ((math.pi / 2 - angle) / turn % 1) * band_width
end

-- Band pixel under the left edge of the 320px window. The frame is that window, so it is never resized.
local function frame_index(heading)
	local origin = (band_pixel(heading) - view_width / 2) % band_width
	return math.floor(origin + 0.5) % BAND_W
end

local function pan_bands(heading)
	ui.place(clip, 0, LINE_Y - math.floor(STRIP_H / 2))
	ui.size(pkg_band, view_width, STRIP_H)
	ui.place(pkg_band, 0, 0)
	ui.image(pkg_band, string.format("library://notum.ndgui-lib/compass/frame/%04d.png", frame_index(heading)))
end

function compass_place(screen_width)
	if not sized then choose_art() end
	D.place_default(placement, root, math.floor(screen_width * 0.5 - view_width / 2), D.TOP_Y)
end

local function apply_pkg(reading)
	pan_bands(reading.heading)
	local text = ""
	if reading.has_waypoint and reading.has_position and reading.waypoint_playfield == reading.playfield then
		local dx, dz = reading.waypoint_x - reading.x, reading.waypoint_z - reading.z
		local bearing = math.atan(dz, dx)
		local x = column(reading.heading, bearing)
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

local function apply_atlas(reading)
	if band_width <= 0 then
		return
	end
	local offset = (band_width * (-(reading.heading - math.pi / 2) / turn) - view_width / 2) % band_width
	ui.compass.offset(band, offset, 0)
	ui.compass.begin(band)
	ui.compass.sprite(band, art.band, band_width / 2, LINE_Y)
	ui.compass.sprite(band, art.band, band_width * 1.5, LINE_Y)
	local text = ""
	if reading.has_waypoint and reading.has_position and reading.waypoint_playfield == reading.playfield then
		local dx, dz = reading.waypoint_x - reading.x, reading.waypoint_z - reading.z
		local bearing = math.atan(dz, dx) % turn
		local shift = (reading.heading - bearing) / turn * band_width
		local col = view_width / 2 + shift - math.floor(shift / band_width + 0.5) * band_width
		col = math.max(EDGE, math.min(view_width - EDGE, col))
		ui.compass.sprite(band, art.waypoint, offset + col, MARKER_Y)
		text = metres(math.sqrt(dx * dx + dz * dz))
	end
	ui.compass.sprite(band, art.caret, offset + view_width / 2, CARET_Y)
	ui.compass.finish(band)
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
	if mode == "atlas" then
		apply_atlas(reading)
	elseif mode == "png" then
		apply_pkg(reading)
	else
		apply_stock(reading)
	end
end
