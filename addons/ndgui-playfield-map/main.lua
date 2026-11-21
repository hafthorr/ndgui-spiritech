-- ndGUI Local Map (prk.playfield-map). Hand-made; keeps the stock native contract
ui.require("notum.ndgui-lib/grid") -- ndGUI: snap to grid while moving/resizing (ndgui-lib/lua/grid.lua)
-- (playfield_map_* callbacks, pfmap_* widgets, protected waypoint commands) and adds:
--   toolbar (zoom -/+, centre, follow, trail, rings, marker filters, minimap mode),
--   live world X/Z, cursor world X/Z + distance, right-click "Set waypoint here",
--   breadcrumb trail, metre range rings, DarkTech markers with a live legend,
--   all settings remembered per character.
-- World <-> map calibration: the native map gives the character's projected (content)
-- position, game.character gives its world X/Z. Pairing the two while walking yields the
-- linear map projection (axis-aligned), remembered for the last few playfields.
local Window = ui.require("core.window")
local content = ui.load("content.xml")
local surface = ui.find(content, "pfmap_surface")
local controls = ui.find(content, "pfmap_controls")
local areas_button = ui.find(content, "pfmap_show_areas")
local unavailable = ui.find(content, "pfmap_unavailable")
local toolbar = ui.find(content, "ndmap_toolbar")
local status = ui.find(content, "ndmap_status")
local input_x, input_z = ui.find(content, "pfmap_x"), ui.find(content, "pfmap_z")
local context_menu = ui.load("menu.xml")
ui.add(content, context_menu)
local view = game.map_surface
view.attach(surface, true)
game.playfield_map.coordinates(input_x, input_z)

local TEMPLATE = "library://notum.ndgui-lib/window.xml"
local ZOOM_MIN, ZOOM_MAX = -9, 12          -- scale 2^(z/3): 0.125x .. 16x
local FULL_W, FULL_H = 440, 480
local MINI_W, MINI_H = 230, 236
local TOOLBAR_H, STATUS_H = 30, 25
local RING_METRES = { 25, 50, 100 }
local TRAIL_MAX, TRAIL_STEP = 120, 3       -- points, content units between points

-- ---- settings ---------------------------------------------------------------
local function read(key, default)
	local ok, value = pcall(ui.preference.read, key)
	if not ok or value == nil or value == "" then
		return default
	end
	if type(default) == "boolean" then
		return value == "true"
	end
	if type(default) == "number" then
		return tonumber(value) or default
	end
	return value
end

local function write(key, value)
	local kind = type(value) == "boolean" and "bool" or type(value) == "number" and "int" or "text"
	pcall(ui.preference.write, key, tostring(value), kind)
end

local settings = {
	follow = read("ndmap.follow", true),
	trail = read("ndmap.trail", true),
	rings = read("ndmap.rings", false),
	compact = read("ndmap.compact", false),
	zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, read("ndmap.zoom", 0))),
}
local hidden = read("ndmap.hidden", "")
for _, filter in ipairs(MAP_FILTERS) do
	MapOverlay.shown[filter.key] = not hidden:find("," .. filter.key .. ",", 1, true)
end

local function save_filters()
	local parts = { "," }
	for _, filter in ipairs(MAP_FILTERS) do
		if not MapOverlay.shown[filter.key] then
			parts[#parts + 1] = filter.key .. ","
		end
	end
	write("ndmap.hidden", table.concat(parts))
end

-- ---- state ------------------------------------------------------------------
local opened, available, buttons, areas = false, true, false, false
local window_visible, native_shown = false, nil
local zoom_pending, last_update_at, shown_at = false, nil, nil
local first_pending, centre_pending, follow_pending = false, false, false
-- After a zone change the new map can arrive before your position does: keep centring on you
-- for a few seconds (whatever Follow says) until the position settles.
local SETTLE_MS = 12000 -- after zoning, keep following you this long (zone loads can be slow)
local settle_until, centred_x, centred_y = 0, nil, nil
local previous_x, previous_y, previous_character
local cap_width, cap_height
local wheel = 0
local wanted_width, wanted_height = FULL_W, FULL_H
local shown_width, shown_height
local frame
local last_facts
local me = { x = nil, z = nil, playfield = nil }   -- world position from game.character
local cursor                                     -- { x, y } content coordinates under the pointer

local function num(value)
	return type(value) == "number" and value or 0
end

-- ---- calibration (content <-> world) ------------------------------------------
-- Per axis keep the samples with the smallest and largest world value; their slope is
-- the projection scale. Stored as "pf:ax:bx:az:bz" for the last 3 playfields.
local cal, cal_pf
local samples = { x = {}, z = {} }

local function load_calibration(playfield)
	cal, cal_pf, samples = nil, playfield, { x = {}, z = {} }
	for entry in read("ndmap.cal", ""):gmatch("[^;]+") do
		local pf, ax, bx, az, bz = entry:match("^(%-?%d+):([^:]+):([^:]+):([^:]+):([^:]+)$")
		if pf and tonumber(pf) == playfield then
			cal = { ax = tonumber(ax), bx = tonumber(bx), az = tonumber(az), bz = tonumber(bz) }
		end
	end
end

local function store_calibration()
	if not cal or not cal_pf then
		return
	end
	local kept = { string.format("%d:%.6g:%.6g:%.6g:%.6g", cal_pf, cal.ax, cal.bx, cal.az, cal.bz) }
	for entry in read("ndmap.cal", ""):gmatch("[^;]+") do
		local pf = tonumber(entry:match("^(%-?%d+):"))
		if pf and pf ~= cal_pf and #kept < 3 then
			kept[#kept + 1] = entry
		end
	end
	write("ndmap.cal", table.concat(kept, ";"))
end

local function sample(cx, cy, wx, wz)
	if not samples then
		return
	end
	local changed = false
	for axis, pair in pairs({ x = { wx, cx }, z = { wz, cy } }) do
		local s = samples[axis]
		local w, c = pair[1], pair[2]
		if not s.low or w < s.low[1] then s.low = { w, c }; changed = true end
		if not s.high or w > s.high[1] then s.high = { w, c }; changed = true end
	end
	if not changed then
		return
	end
	local sx, sz = samples.x, samples.z
	if sx.high[1] - sx.low[1] < 8 or sz.high[1] - sz.low[1] < 8 then
		return  -- need ~8 m of travel on each axis before trusting the slope
	end
	local ax = (sx.high[2] - sx.low[2]) / (sx.high[1] - sx.low[1])
	local az = (sz.high[2] - sz.low[2]) / (sz.high[1] - sz.low[1])
	if ax == 0 or az == 0 then
		return
	end
	cal = { ax = ax, bx = sx.low[2] - ax * sx.low[1], az = az, bz = sz.low[2] - az * sz.low[1] }
	store_calibration()
end

local function to_world(cx, cy)
	if not cal then
		return nil
	end
	return (cx - cal.bx) / cal.ax, (cy - cal.bz) / cal.az
end

local function metres_scale()
	return cal and (math.abs(cal.ax) + math.abs(cal.az)) / 2 or nil
end

if game.character and game.character.subscribe then
	pcall(game.character.subscribe, "self", "", function(_, character)
		if type(character) == "table" and character.x and character.z then
			me.x, me.z = character.x, character.z
			if character.playfield and character.playfield ~= me.playfield then
				me.playfield = character.playfield
				load_calibration(character.playfield)
				MapOverlay.trail = {}
			end
		end
	end)
end

-- ---- screen <-> content -------------------------------------------------------
local function to_content(px, py)
	local w, h = num(ui.width(surface)), num(ui.height(surface))
	if w <= 0 or h <= 0 then
		return nil
	end
	return num(view.read("x")) + (px - num(ui.x(surface))) * num(view.read("width")) / w,
		num(view.read("y")) + (py - num(ui.y(surface))) * num(view.read("height")) / h
end

-- ---- presentation -------------------------------------------------------------
local function zoom_scale()
	return 2 ^ (settings.zoom / 3)
end

local function legend_text()
	local counts = MapOverlay.counts
	local parts = {}
	local short = { monster = "Mobs", players = "Players", team = "Team", shop = "Shops", mission = "Missions" }
	for _, filter in ipairs(MAP_FILTERS) do
		local label = short[filter.key]
		if label and (counts[filter.key] or 0) > 0 and MapOverlay.shown[filter.key] then
			parts[#parts + 1] = label .. " " .. counts[filter.key]
		end
	end
	return table.concat(parts, "  ")
end

local function refresh_status()
	if settings.compact then
		return
	end
	if me.x then
		ui.text(ui.find(content, "ndmap_position"), string.format("X %d  Z %d", math.floor(me.x + .5), math.floor(me.z + .5)))
	else
		ui.text(ui.find(content, "ndmap_position"), "X --  Z --")
	end
	local text = ""
	-- No hover: show where the waypoint is and how far.
	local wp = MapOverlay.waypoint
	if not cursor and wp then
		local wx, wz = to_world(wp[1], wp[2])
		if wx and me.x then
			text = string.format("WP %d, %d   %d m", math.floor(wx + .5), math.floor(wz + .5),
				math.floor(math.sqrt((wx - me.x) ^ 2 + (wz - me.z) ^ 2) + .5))
		end
	end
	if cursor then
		local wx, wz = to_world(cursor[1], cursor[2])
		if wx and me.x then
			text = string.format("-> %d, %d   %d m", math.floor(wx + .5), math.floor(wz + .5),
				math.floor(math.sqrt((wx - me.x) ^ 2 + (wz - me.z) ^ 2) + .5))
		elseif not cal then
			text = "walk a few steps to calibrate"
		end
	end
	ui.text(ui.find(content, "ndmap_cursor"), text)
	ui.text(ui.find(content, "ndmap_legend"), legend_text())
end

local function update_overlays()
	local facts = last_facts
	local scale = metres_scale()
	MapOverlay.rings = nil
	if settings.rings and scale and facts and facts.has_character then
		MapOverlay.rings = { x = facts.x, y = facts.y, scale = scale, metres = RING_METRES }
	end
	local w = num(ui.width(surface))
	MapOverlay.dot_step = w > 0 and 6 * num(view.read("width")) / w or 6
	MapOverlay.reticle = cursor
end

local function recompose()
	update_overlays()
	local saved = MapOverlay.trail
	if not settings.trail then
		MapOverlay.trail = {}
	end
	MapOverlay.compose()
	MapOverlay.trail = saved
	refresh_status()
end

local function paint_toolbar()
	ui.text(ui.find(content, "ndmap_zoom"), string.format("%gx", math.floor(zoom_scale() * 100 + .5) / 100))
	ui.selected(ui.find(content, "ndmap_follow"), settings.follow)
	ui.selected(ui.find(content, "ndmap_trail"), settings.trail)
	ui.selected(ui.find(content, "ndmap_rings"), settings.rings)
	ui.selected(ui.find(content, "ndmap_mini"), settings.compact)
	ui.visible(toolbar, not settings.compact)
	ui.visible(status, not settings.compact)
end

local extras = 0
local function publish(changed)
	ui.publish("buttons", tostring(buttons))
	if changed then
		extras = extras + 1
		ui.publish("extras", tostring(extras))
	end
end

local function chrome_height()
	return (buttons and 152 or 0) + (settings.compact and 0 or TOOLBAR_H + STATUS_H)
end

local function layout(window, width, height)
	if width ~= shown_width then
		wanted_width = width
	end
	if height ~= shown_height then
		wanted_height = height
	end
	local control_height = chrome_height()
	local minimum_width = buttons and 203 or (settings.compact and 111 or 330)
	local minimum_height = 133 + control_height
	local screen_width, screen_height = num(view.read("screen_width")), num(view.read("screen_height"))
	local maximum_width = screen_width > 0 and screen_width or 16384
	local maximum_height = screen_height > 0 and screen_height or 16384
	ui.limits(window.root, math.min(minimum_width, maximum_width), math.min(minimum_height, maximum_height), maximum_width, maximum_height)
	ui.request_size(window.root, wanted_width, wanted_height)
	shown_width, shown_height = ui.chosen_width(window.root), ui.chosen_height(window.root)
	window:fit_title(shown_width, true)
	window:fit_content(shown_width, shown_height)
	local new_width, new_height = maximum_width - 11, maximum_height - 33 - control_height
	if cap_width and (math.min(wanted_width - 11, new_width) ~= math.min(wanted_width - 11, cap_width)
		or math.min(wanted_height - 33 - control_height, new_height) ~= math.min(wanted_height - 33 - control_height, cap_height)) then
		follow_pending = true
	end
	cap_width, cap_height = new_width, new_height
end

local function centre(facts)
	facts = facts or last_facts
	if not facts then
		return
	end
	local x = facts.has_character and facts.x or facts.width / 2
	local y = facts.has_character and facts.y or facts.height / 2
	view.pan(x - num(view.read("width")) / 2, y - num(view.read("height")) / 2)
	centred_x, centred_y = facts.has_character and x or nil, facts.has_character and y or nil
end

-- True when the viewport shows none of the map (panned onto the black void, e.g. after zoning).
local function off_map(facts)
	if not facts or (facts.width or 0) <= 0 or (facts.height or 0) <= 0 then
		return false
	end
	local x, y = num(view.read("x")), num(view.read("y"))
	local w, h = num(view.read("width")), num(view.read("height"))
	if w <= 0 or h <= 0 then
		return false
	end
	return x + w <= 0 or y + h <= 0 or x >= facts.width or y >= facts.height
end

local function apply_zoom(level, anchor_x, anchor_y)
	level = math.max(ZOOM_MIN, math.min(ZOOM_MAX, level))
	if level == settings.zoom and anchor_x then
		return
	end
	-- Stop zooming out once the whole map already fits (no black void around it).
	if level < settings.zoom and last_facts and last_facts.width > 0 and last_facts.height > 0
		and num(view.read("width")) >= last_facts.width and num(view.read("height")) >= last_facts.height then
		return
	end
	settings.zoom = level
	write("ndmap.zoom", level)
	if not anchor_x then
		anchor_x = num(ui.x(surface)) + num(ui.width(surface)) / 2
		anchor_y = num(ui.y(surface)) + num(ui.height(surface)) / 2
	end
	view.zoom(zoom_scale(), anchor_x, anchor_y)
	if settings.follow then
		centre_pending = true
	end
	paint_toolbar()
	recompose()
end

-- ---- toggles -------------------------------------------------------------------
local MENU_BUTTONS, MENU_COMPACT = 1, 2

local function show_buttons(value)
	buttons = value
	ui.visible(controls, buttons)
	if frame then
		ui.menu.checked(frame.icon, MENU_BUTTONS, buttons)
		frame:resize(wanted_width, wanted_height)
	end
	publish(false)
end

function playfield_map_toggle_buttons()
	show_buttons(not buttons)
	publish(true)
end

local function set_compact(value)
	settings.compact = value
	write("ndmap.compact", value)
	if value then
		settings.follow = true
	end
	paint_toolbar()
	if frame then
		ui.menu.checked(frame.icon, MENU_COMPACT, value)
		wanted_width, wanted_height = value and MINI_W or FULL_W, value and MINI_H or FULL_H
		frame:resize(wanted_width, wanted_height)
	end
	centre_pending = true
end

local function toggle(key)
	settings[key] = not settings[key]
	write("ndmap." .. key, settings[key])
	if key == "follow" and settings.follow then
		centre_pending = true
	end
	paint_toolbar()
	recompose()
end

frame = Window.create({
	template = TEMPLATE,
	title = "Local Map",
	content = content,
	width = wanted_width,
	height = wanted_height,
	layout = layout,
	-- window visibility (no host calls may run from here: they cannot re-enter Lua)
	on_visibility = function(visible)
		window_visible = visible

	end,
	menu = {
		{ label = "Show Buttons", checked = buttons, invoke = playfield_map_toggle_buttons },
		{ label = "Minimap", checked = settings.compact, invoke = function() set_compact(not settings.compact) end },
	},
})
ui.root(frame.root)

ui.on_click(ui.find(content, "ndmap_zoom_in"), function() apply_zoom(settings.zoom + 1) end)
ui.on_click(ui.find(content, "ndmap_zoom_out"), function() apply_zoom(settings.zoom - 1) end)
ui.on_click(ui.find(content, "ndmap_centre"), function() centre() end)
ui.on_click(ui.find(content, "ndmap_follow"), function() toggle("follow") end)
ui.on_click(ui.find(content, "ndmap_trail"), function() toggle("trail") end)
ui.on_click(ui.find(content, "ndmap_rings"), function() toggle("rings") end)
ui.on_click(ui.find(content, "ndmap_mini"), function() set_compact(not settings.compact) end)

local filter_button = ui.find(content, "ndmap_filters")
local function build_filter_menu(anchor)
	ui.menu.clear(anchor)
	for index, filter in ipairs(MAP_FILTERS) do
		ui.menu.add(anchor, filter.label, MapOverlay.shown[filter.key], function()
			MapOverlay.shown[filter.key] = not MapOverlay.shown[filter.key]
			ui.menu.checked(anchor, index, MapOverlay.shown[filter.key])
			save_filters()
			recompose()
		end)
	end
end
pcall(ui.menu.style, filter_button, "context")
build_filter_menu(filter_button)
ui.on_click(filter_button, function()
	build_filter_menu(filter_button)
	ui.menu.show(filter_button)
end)

-- Pointer: hover shows the reticle + cursor world position.
ui.on_pointer(surface, function(phase, x, y)
	if phase == "hover" or phase == "move" then
		local cx, cy = to_content(x, y)
		cursor = cx and { cx, cy } or nil
	elseif phase == "cancel" then
		cursor = nil
	end
	if opened then
		recompose()
	end
end)

-- ---- native contract -------------------------------------------------------------
function playfield_map_context(x, y)
	if not opened then
		return
	end
	ui.menu.clear(context_menu)
	-- Waypoints are parked: the native add/remove commands refuse our input in this client
	-- (stock X/Z panel stays available under Show buttons).
	ui.menu.add(context_menu, "Centre on me", false, function() centre() end)
	ui.menu.add(context_menu, "Follow me", settings.follow, function() toggle("follow") end)
	ui.menu.add(context_menu, "Trail", settings.trail, function() toggle("trail") end)
	ui.menu.add(context_menu, "Clear trail", false, function() MapOverlay.trail = {}; recompose() end)
	ui.menu.add(context_menu, "Range rings", settings.rings, function() toggle("rings") end)
	ui.menu.separator(context_menu)
	ui.menu.add(context_menu, "Minimap (hides toolbar)", settings.compact, function() set_compact(not settings.compact) end)
	ui.menu.add(context_menu, "Show buttons", buttons, playfield_map_toggle_buttons)
	ui.menu.show_at(context_menu, x, y)
end

function playfield_map_configure(first_open, areas_text, build_tooltip, war_tooltip)
	first_pending = first_open
	ui.text(areas_button, areas_text)
	ui.tooltip(ui.find(content, "pfmap_build"), build_tooltip)
	ui.tooltip(ui.find(content, "pfmap_war"), war_tooltip)
end

ui.on_click(areas_button, function() areas = not areas end)
ui.bind(ui.find(content, "pfmap_add_waypoint"), 1)
ui.action(ui.find(content, "pfmap_add_waypoint"), "game.playfield_map.add_waypoint", 1, "left")
ui.bind(ui.find(content, "pfmap_remove_waypoint"), 1)
ui.action(ui.find(content, "pfmap_remove_waypoint"), "game.playfield_map.remove_waypoint", 1, "left")

function playfield_map_restore(saved_buttons)
	show_buttons(saved_buttons)
end

-- After each open: apply the deferred zoom once the view has a size (at login the client shows the
-- map while its view is still 0x0), then stop ticking.
local watching = false
local function start_watchdog()
	if watching or not ui.on_update then
		return
	end
	watching = true
	ui.on_update(function(now)
		local w, h = num(ui.width(surface)), num(ui.height(surface))
		if opened and zoom_pending and w > 0 and h > 0 then
			zoom_pending = false
			view.zoom(zoom_scale(), num(ui.x(surface)) + w / 2, num(ui.y(surface)) + h / 2)
		end
		if not opened or not zoom_pending then
			watching = false
			ui.stop_updates()
		end
	end)
end

function playfield_map_visibility(shown)
	if shown then
	end
	native_shown = shown
	opened = shown
	centre_pending, follow_pending = shown, false
	previous_x, previous_y, previous_character = nil, nil, nil
	if shown then
		-- At login the client shows the map before its view has a size; zooming a 0x0 view left the map
		-- black (no updates ever came) until the next open. Zoom only once the view has a size.
		last_update_at, shown_at = nil, ui.time()
		if num(ui.width(surface)) > 0 and num(ui.height(surface)) > 0 then
			view.zoom(zoom_scale(), num(ui.x(surface)) + num(ui.width(surface)) / 2, num(ui.y(surface)) + num(ui.height(surface)) / 2)
			zoom_pending = false
		else
			zoom_pending = true
		end
		start_watchdog()
		paint_toolbar()
	else
		available = true
		cursor = nil
		ui.visible(unavailable, false)
		publish(true)
	end
end

function playfield_map_wheel(turn, x, y)
	if not opened or not available then
		return
	end
	wheel = wheel + turn
	local detents = wheel < 0 and math.ceil(wheel) or math.floor(wheel)
	wheel = wheel - detents
	if detents ~= 0 then
		apply_zoom(settings.zoom + detents, x, y)
	end
end

function playfield_map_markers(readings)
	MapOverlay.readings = readings or {}
	recompose()
end

local function track(facts)
	if not facts.has_character then
		return
	end
	if me.x then
		sample(facts.x, facts.y, me.x, me.z)
	end
	local trail = MapOverlay.trail
	local last = trail[#trail]
	if not last or (facts.x - last[1]) ^ 2 + (facts.y - last[2]) ^ 2 >= TRAIL_STEP * TRAIL_STEP then
		trail[#trail + 1] = { facts.x, facts.y }
		if #trail > TRAIL_MAX then
			table.remove(trail, 1)
		end
	end
end

function playfield_map_update(facts)
	last_update_at = ui.time()
	if not opened then
		if not window_visible then
			return
		end
		-- the window is on screen but the client never said "shown" (seen at login): open from here,
		-- inside a normal native callback (never from the visibility observer)
		playfield_map_visibility(true)
	end
	last_facts = facts
	if facts.changed then
		centre_pending, follow_pending = true, false
		previous_x, previous_y, previous_character = nil, nil, nil
		MapOverlay.trail = {}
		if samples then
			samples = { x = {}, z = {} }
		end
		-- the old zone's world position must not calibrate the new map
		me.x, me.z = nil, nil
		settle_until, centred_x, centred_y = ui.time() + SETTLE_MS, nil, nil
		-- a new map view: put our zoom back on it
		view.zoom(zoom_scale(), num(ui.x(surface)) + num(ui.width(surface)) / 2, num(ui.y(surface)) + num(ui.height(surface)) / 2)
	end
	track(facts)
	local resizing = false
	if first_pending then
		first_pending = false
		wanted_width, wanted_height = settings.compact and MINI_W or FULL_W, settings.compact and MINI_H or FULL_H
		frame:resize(wanted_width, wanted_height)
		resizing = true
	end
	local old_width, old_height = shown_width, shown_height
	frame:resize(wanted_width, wanted_height)
	resizing = resizing or old_width ~= shown_width or old_height ~= shown_height
	ui.enabled(areas_button, facts.land_control)
	if not facts.land_control then
		areas = false
	end
	ui.selected(areas_button, areas)
	local show_areas = areas and facts.has_areas
	local accessible = facts.accessible or show_areas
	if accessible ~= available then
		available = accessible
		ui.visible(unavailable, not available)
		if available then
			centre_pending = true
		else
			view.pan(0, 0)
			game.playfield_map.clear()
		end
	end
	if not available then
		if facts.changed then
			game.playfield_map.clear()
		end
		return
	end
	if centre_pending then
		if resizing or num(view.read("width")) <= 0 or num(view.read("height")) <= 0 then
			return
		end
		centre(facts)
		-- no position yet right after zoning: try again on the next update
		centre_pending = not facts.has_character and ui.time() < settle_until
	elseif not resizing and off_map(facts) then
		-- nothing of the map in view: come back to you (or the map's middle)
		centre(facts)
	elseif not resizing and facts.has_character and ui.time() < settle_until
		and num(view.read("dragged")) == 0 and (facts.x ~= centred_x or facts.y ~= centred_y) then
		centre(facts)
	elseif not resizing and settings.follow then
		follow_pending = follow_pending or facts.has_character and
			(not previous_character or facts.x ~= previous_x or facts.y ~= previous_y)
		previous_x, previous_y, previous_character = facts.x, facts.y, facts.has_character
		if follow_pending and num(view.read("dragged")) == 0 then
			follow_pending = false
			centre(facts)
		end
	end
	game.playfield_map.render(show_areas)
	refresh_status()
end

show_buttons(buttons)
paint_toolbar()
