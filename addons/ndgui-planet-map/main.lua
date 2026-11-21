-- ndGUI Planet Map (prk.planet-map). Hand-made; keeps the stock native contract
ui.require("notum.ndgui-lib/grid") -- ndGUI: snap to grid while moving/resizing (ndgui-lib/lua/grid.lua)
-- (planet_map_* callbacks, planet_* widgets, protected teleport) and adds:
--   DarkTech toolbar (zoom -/+ with level readout, Me, Mission, Follow, Route, Maps),
--   status line with map name and mission distance + bearing,
--   DarkTech beacons for you and the mission, a dotted route between them and a halo
--   so you can find yourself at a glance. Follow/Route remembered per character.
-- Distance: the planet map gives the character's projected position, game.character its
-- world X/Z; walking pairs the two into a content-per-metre scale for each zoom record.
local Window = ui.require("core.window")
local content = ui.load("content.xml")
local surface = ui.find(content, "planet_tiles")
local toolbar = ui.find(content, "ndplanet_toolbar")
local status = ui.find(content, "ndplanet_status")
local zoom_in = ui.find(content, "planet_zoom_in")
local zoom_out = ui.find(content, "planet_zoom_out")
local character = ui.find(content, "planet_centre_character")
local quest = ui.find(content, "planet_centre_quest")
local follow_button = ui.find(content, "ndplanet_follow")
local route_button = ui.find(content, "ndplanet_route")
local maps_button = ui.find(content, "ndplanet_maps")
local choices_menu = ui.load("menu.xml")
local context_menu = ui.load("menu.xml")
ui.add(content, choices_menu)
ui.add(content, context_menu)
local view = game.map_surface
view.attach(surface, false)

local TEMPLATE = "library://notum.ndgui-lib/window.xml"
local FIRST_W, FIRST_H = 460, 500
local HALO_PX, ROUTE_PX = 13, 7          -- screen pixels: halo radius, route dot spacing
local MEASURE_M = 40                     -- metres walked before trusting a scale sample

-- ---- settings ---------------------------------------------------------------
local function read(key, default)
	local ok, value = pcall(ui.preference.read, key)
	if not ok or value == nil or value == "" then
		return default
	end
	if type(default) == "boolean" then
		return value == "true"
	end
	return value
end

local function write(key, value)
	local kind = type(value) == "boolean" and "bool" or "text"
	pcall(ui.preference.write, key, tostring(value), kind)
end

local settings = {
	follow = read("ndplanet.follow", false),
	route = read("ndplanet.route", true),
}

local function num(value)
	return type(value) == "number" and value or 0
end

local function point(field)
	local ok, value = pcall(game.planet_map.point, field)
	return ok and num(value) or 0
end

-- ---- state ------------------------------------------------------------------
local opened, buttons, first_time = false, true, true
local first_pending, centre_pending = false, false
local zoom, records, revision, extras = 0, 0, -1, 0
local frame
local menu_character, menu_quest
local rebuild_menu
local choices = {}
local map_name = ""
local previous_cx, previous_cy
local me = { x = nil, z = nil, playfield = nil }

-- ---- sprites (DarkTech from tools/skin.py, stock fallback) ----------------------
local FALLBACK = {
	GFX_GUI_NDGUI_MAP_YOU = "GFX_GUI_PLANETMAP_PLAYER_MARKER",
	GFX_GUI_NDGUI_MAP_MARKED = "GFX_GUI_PLANETMAP_MISSION_MARKER2",
}
local rejected = {}
local function sprite(graphic, x, y)
	if rejected[graphic] then
		if FALLBACK[graphic] then
			pcall(view.sprite, FALLBACK[graphic], x, y, 0)
		end
		return
	end
	if not pcall(view.sprite, graphic, x, y, 0) then
		rejected[graphic] = true
		if FALLBACK[graphic] then
			pcall(view.sprite, FALLBACK[graphic], x, y, 0)
		end
	end
end
PlanetSpriteRejected = rejected

-- ---- scale (content units per metre, per zoom record) ----------------------------
local scales = {}
for entry in read("ndplanet.scale", ""):gmatch("[^;]+") do
	local record, scale = entry:match("^(%d+):([%d%.eE%-]+)$")
	if record and tonumber(scale) then
		scales[tonumber(record)] = tonumber(scale)
	end
end
local anchor  -- { cx, cy, wx, wz, record, playfield }

local function store_scales()
	local parts = {}
	for record, scale in pairs(scales) do
		parts[#parts + 1] = string.format("%d:%.6g", record, scale)
	end
	table.sort(parts)
	write("ndplanet.scale", table.concat(parts, ";"))
end

local function measure()
	if not me.x or point("character") == 0 then
		return
	end
	local cx, cy = point("character_x"), point("character_y")
	if not anchor or anchor.record ~= zoom or anchor.playfield ~= me.playfield then
		anchor = { cx = cx, cy = cy, wx = me.x, wz = me.z, record = zoom, playfield = me.playfield }
		return
	end
	local metres = math.sqrt((me.x - anchor.wx) ^ 2 + (me.z - anchor.wz) ^ 2)
	if metres < MEASURE_M then
		return
	end
	local units = math.sqrt((cx - anchor.cx) ^ 2 + (cy - anchor.cy) ^ 2)
	if units > 0 then
		local scale = units / metres
		scales[zoom] = scales[zoom] and (scales[zoom] * 0.7 + scale * 0.3) or scale
		store_scales()
	end
	anchor = { cx = cx, cy = cy, wx = me.x, wz = me.z, record = zoom, playfield = me.playfield }
end

if game.character and game.character.subscribe then
	pcall(game.character.subscribe, "self", "", function(_, subject)
		if type(subject) == "table" and subject.x and subject.z then
			me.x, me.z = subject.x, subject.z
			if subject.playfield then
				me.playfield = subject.playfield
			end
		end
	end)
end

-- ---- presentation -------------------------------------------------------------
local function per_pixel()
	local w = num(ui.width(surface))
	return w > 0 and num(view.read("width")) / w or 1
end

local BEARINGS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function bearing(dx, dy)
	local angle = math.atan(dx, -dy) % (2 * math.pi)
	return BEARINGS[math.floor(angle / (math.pi / 4) + .5) % 8 + 1]
end

local function distance_text(metres)
	if metres >= 1000 then
		return string.format("%.1f km", metres / 1000)
	end
	return string.format("%d m", math.floor(metres + .5))
end

local function refresh_status()
	local name = map_name ~= "" and map_name or "Planet Map"
	if records > 0 then
		name = string.format("%s   zoom %d/%d", name, zoom + 1, records)
	end
	ui.text(ui.find(content, "ndplanet_name"), name)
	local text = "No mission"
	if point("quest") ~= 0 then
		text = "Mission"
		if point("character") ~= 0 then
			local dx = point("quest_x") - point("character_x")
			local dy = point("quest_y") - point("character_y")
			local units = math.sqrt(dx * dx + dy * dy)
			local scale = scales[zoom]
			if scale and scale > 0 then
				text = string.format("Mission  %s  %s", distance_text(units / scale), units > 0 and bearing(dx, dy) or "")
			else
				text = string.format("Mission  %s  (walk to measure)", units > 0 and bearing(dx, dy) or "here")
			end
		end
	end
	ui.text(ui.find(content, "ndplanet_mission"), text)
	ui.text(ui.find(content, "ndplanet_zoom"), records > 0 and string.format("%d/%d", zoom + 1, records) or "-")
end

local function compose_markers()
	view.markers_begin()
	local step = per_pixel()
	local has_me, has_quest = point("character") ~= 0, point("quest") ~= 0
	local mx, my = point("character_x"), point("character_y")
	local qx, qy = point("quest_x"), point("quest_y")
	if settings.route and has_me and has_quest then
		local dx, dy = qx - mx, qy - my
		local length = math.sqrt(dx * dx + dy * dy)
		local count = math.min(300, math.floor(length / math.max(0.01, ROUTE_PX * step)))
		for i = 2, count - 2 do
			sprite("GFX_GUI_NDGUI_MAP_ROUTE", mx + dx * i / count, my + dy * i / count)
		end
	end
	if has_me then
		local radius = HALO_PX * step
		for i = 0, 15 do
			local a = 2 * math.pi * i / 16
			sprite("GFX_GUI_NDGUI_MAP_RING", mx + radius * math.cos(a), my + radius * math.sin(a))
		end
	end
	if has_quest then
		sprite("GFX_GUI_NDGUI_MAP_MARKED", qx, qy)
	end
	if has_me then
		sprite("GFX_GUI_NDGUI_MAP_YOU", mx, my)
	end
	view.markers_end()
end

local function publish(changed)
	ui.publish("buttons", tostring(buttons))
	ui.publish("zoom", tostring(zoom))
	if changed then
		extras = extras + 1
		ui.publish("extras", tostring(extras))
	end
end

local function show_buttons(value)
	buttons = value
	ui.visible(toolbar, buttons)
	ui.visible(status, buttons)
	publish(false)
end

function planet_map_toggle_buttons()
	show_buttons(not buttons)
	ui.menu.checked(frame.icon, 4, buttons)
	publish(true)
end

local function layout(window, width, height)
	local screen_width, screen_height = num(view.read("screen_width")), num(view.read("screen_height"))
	local maximum_width = screen_width > 0 and screen_width or 1600
	local maximum_height = screen_height > 0 and screen_height or 1600
	local minimum_width = buttons and 330 or 160
	ui.limits(window.root, math.min(minimum_width, maximum_width), math.min(200, maximum_height), maximum_width, maximum_height)
	ui.request_size(window.root, width, height)
	window:fit_title(ui.chosen_width(window.root), true)
	window:fit_content(ui.chosen_width(window.root), ui.chosen_height(window.root))
end

frame = Window.create({
	template = TEMPLATE,
	title = "Planet Map",
	content = content,
	width = FIRST_W,
	height = FIRST_H,
	x = 95,
	y = 72,
	layout = layout,
})
ui.root(frame.root)

function planet_map_centre(subject)
	if point(subject) == 0 then
		return
	end
	view.pan(point(subject .. "_x") - num(view.read("width")) / 2,
		point(subject .. "_y") - num(view.read("height")) / 2)
end

local function toggle(key)
	settings[key] = not settings[key]
	write("ndplanet." .. key, settings[key])
	ui.selected(key == "follow" and follow_button or route_button, settings[key])
	if key == "follow" and settings.follow then
		planet_map_centre("character")
	end
	if opened then
		compose_markers()
	end
end

local function compose_menu(anchor)
	ui.menu.clear(anchor)
	if point("character") ~= 0 then
		ui.menu.add(anchor, "Center on player", false, function() planet_map_centre("character") end)
	else
		ui.menu.label(anchor, "Center on player")
	end
	if point("quest") ~= 0 then
		ui.menu.add(anchor, "Center on mission", false, function() planet_map_centre("quest") end)
	else
		ui.menu.label(anchor, "Center on mission")
	end
	ui.menu.submenu(anchor, "Select Map", choices_menu)
	ui.menu.add(anchor, "Show toolbar", buttons, planet_map_toggle_buttons)
end

rebuild_menu = function()
	menu_character = point("character") ~= 0
	menu_quest = point("quest") ~= 0
	compose_menu(frame.icon)
	ui.menu.separator(frame.icon)
	ui.menu.close(frame.icon, frame.root)
end

function planet_map_context(x, y, teleport)
	if not opened then
		return
	end
	compose_menu(context_menu)
	ui.menu.separator(context_menu)
	ui.menu.add(context_menu, "Follow me", settings.follow, function() toggle("follow") end)
	ui.menu.add(context_menu, "Route to mission", settings.route, function() toggle("route") end)
	if teleport ~= 0 then
		ui.menu.separator(context_menu)
		ui.menu.action(context_menu, "Teleport To Location", "game.planet_map.teleport", teleport)
	end
	ui.menu.show_at(context_menu, x, y)
end

local function fill_choices(anchor)
	ui.menu.clear(anchor)
	for _, choice in ipairs(choices) do
		ui.menu.add(anchor, choice.name, choice.chosen, function()
			game.planet_map.choose(choice.index)
		end)
	end
end

function planet_map_choices(list)
	choices = list or {}
	map_name = ""
	for _, choice in ipairs(choices) do
		if choice.chosen then
			map_name = choice.name
		end
	end
	fill_choices(choices_menu)
	rebuild_menu()
	refresh_status()
end

pcall(ui.menu.style, maps_button, "context")
ui.on_click(maps_button, function()
	fill_choices(maps_button)
	ui.menu.show(maps_button)
end)

local function refresh_buttons()
	ui.enabled(zoom_in, zoom < records - 1)
	ui.enabled(zoom_out, records > 0 and zoom > 0)
	ui.enabled(character, point("character") ~= 0)
	ui.enabled(quest, point("held_quest") ~= 0)
	ui.enabled(maps_button, #choices > 1)
	ui.selected(follow_button, settings.follow)
	ui.selected(route_button, settings.route)
	if menu_character ~= (point("character") ~= 0) or menu_quest ~= (point("quest") ~= 0) then
		rebuild_menu()
	end
	ui.menu.checked(frame.icon, 4, buttons)
end

local function change_zoom(step)
	local chosen = math.max(0, math.min(records - 1, zoom + step))
	if records == 0 or chosen == zoom then
		return
	end
	-- Keep the point at the centre of the view in place across detail records.
	local w, h = num(view.read("width")), num(view.read("height"))
	local has_me = point("character") ~= 0
	local old_cx, old_cy = point("character_x"), point("character_y")
	local centre_x, centre_y = num(view.read("x")) + w / 2, num(view.read("y")) + h / 2
	zoom = chosen
	game.planet_map.record(zoom)
	if has_me and point("character") ~= 0 and old_cx ~= 0 then
		-- Re-project the old centre through the character's position in both records.
		local ratio = (point("character_x") ~= 0 and old_cx ~= 0) and point("character_x") / old_cx or 1
		local ratio_y = (point("character_y") ~= 0 and old_cy ~= 0) and point("character_y") / old_cy or ratio
		view.pan(centre_x * ratio - w / 2, centre_y * ratio_y - h / 2)
	else
		view.pan(num(view.read("x")), num(view.read("y")))
	end
	anchor = nil
	if settings.follow then
		planet_map_centre("character")
	end
	refresh_buttons()
	refresh_status()
	publish(true)
end

ui.on_click(zoom_in, function() change_zoom(1) end)
ui.on_click(zoom_out, function() change_zoom(-1) end)
ui.on_click(character, function() planet_map_centre("character") end)
ui.on_click(quest, function() planet_map_centre("quest") end)
ui.on_click(follow_button, function() toggle("follow") end)
ui.on_click(route_button, function() toggle("route") end)

function planet_map_restore(saved_zoom, saved_buttons, saved_first_time)
	zoom = math.max(0, saved_zoom)
	first_time = saved_first_time
	show_buttons(saved_buttons)
	ui.menu.checked(frame.icon, 4, buttons)
end

function planet_map_visibility(shown)
	opened = shown
	first_pending = shown and first_time
	centre_pending = shown
	previous_cx, previous_cy = nil, nil
	if not shown then
		first_time = false
		publish(true)
	end
end

function planet_map_update(current_revision, count)
	if not opened then
		return
	end
	records = count
	if revision ~= current_revision then
		revision = current_revision
		zoom = math.max(0, math.min(zoom, records - 1))
		if records > 0 then
			game.planet_map.record(zoom)
		end
		view.pan(0, 0)
		centre_pending = true
		anchor = nil
		publish(false)
	end
	if first_pending then
		first_pending = false
		frame:resize(FIRST_W, FIRST_H)
		ui.place(frame.root, 95, 72)
	elseif centre_pending and num(view.read("width")) > 0 and num(view.read("height")) > 0 then
		centre_pending = false
		planet_map_centre("character")
	elseif settings.follow and point("character") ~= 0 and num(view.read("dragged")) == 0 then
		local cx, cy = point("character_x"), point("character_y")
		if cx ~= previous_cx or cy ~= previous_cy then
			previous_cx, previous_cy = cx, cy
			planet_map_centre("character")
		end
	end
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
	measure()
	refresh_buttons()
	compose_markers()
	refresh_status()
end

show_buttons(buttons)
rebuild_menu()
refresh_buttons()
refresh_status()
