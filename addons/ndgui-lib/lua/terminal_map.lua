-- ndGUI Mission Terminal offer map (client 0.3.5+, game.mission_map): the planet map beside the offer
-- rows, one numbered marker per offer (gold when it matches the watch list), the selected one ringed,
-- and you. Clicking a number picks that offer (native hit targets). Drawing follows the stock
-- MissionTerminal package; the look is ndGUI's.
--
-- The map surface has to be attached while the package loads, but ndgui-mission-hub only learns which
-- role a VM plays from its first callback. So the hub calls M.mount() at load in every VM (it does
-- nothing harmful in Info / Missions), and the terminal later moves M.pane into its window.
local M = { available = false }

local MARKER_RADIUS, SELECTED_RADIUS, MARKER_RIM, SELECTED_HALO = 9, 11, 2, 4
local FILL, INK, TEXT = "#3D6F9A", "#0A1016", "#FFFFFF"
local WATCH_FILL, WATCH_TEXT = "#FFD84A", "#3A2A00"
local HALO = "#9FD8FF"
local TEXT_SIZE = 12
local FULL_TURN = 2 * math.pi
local WHEEL_STEPS_PER_DOUBLING, MAX_WHEEL_STEPS = 3, 6
local MARKER_GAP, DOOR_RADIUS = 1, 3
local LEADER_WIDTH, LEADER_BORDER, LEADER_LENGTH = 2, 1, 10
local MARKER_REACH = SELECTED_RADIUS + SELECTED_HALO
local PLAYER_MARKER = "GFX_GUI_PLANETMAP_PLAYER_MARKER"

local view = game and game.map_surface
local mission_map = game and game.mission_map
local zoom_in, zoom_out
local offers, watched = {}, {}
local wheel_step, wheel_turn, scale = 0, 0, 1
local revision, records, record, fit_pending = -1, 0, 0, false
local revealed
local drawn_placed, drawn_x, drawn_y = 0, 0, 0

function M.mount(parent)
	if M.pane then
		return M.pane
	end
	local ok, pane = pcall(ui.load, "library://notum.ndgui-lib/terminal_map.xml")
	if not ok or not pane then
		return nil
	end
	M.pane = pane
	if parent then
		ui.add(parent, pane)
	end
	ui.fill_color(ui.find(pane, "terminal_map_back"), "#FF2A3F55")
	zoom_in, zoom_out = ui.find(pane, "terminal_map_zoom_in"), ui.find(pane, "terminal_map_zoom_out")
	M.available = view ~= nil and mission_map ~= nil
		and pcall(view.attach, ui.find(pane, "terminal_map_tiles"), true)
	return pane
end

local function placed(index)
	return mission_map.offer(index, "placed") ~= 0
end

local function disc(x, y, radius, color)
	view.fan(x, y, radius, 0, FULL_TURN, color)
end

local function groups_of()
	local groups = {}
	for index = 1, #offers do
		if placed(index) then
			local x, y = mission_map.offer(index, "x"), mission_map.offer(index, "y")
			local joined
			for _, group in ipairs(groups) do
				if math.abs(group.x - x) * scale < MARKER_REACH * 2 and math.abs(group.y - y) * scale < MARKER_REACH * 2 then
					joined = group
					break
				end
			end
			if joined then
				joined[#joined + 1] = index
			else
				groups[#groups + 1] = { x = x, y = y, index }
			end
		end
	end
	return groups
end

-- offers in the same spot fan out on a ring, with leader lines back to the door
local function spots_of(groups)
	local spots = {}
	for _, group in ipairs(groups) do
		if #group == 1 then
			spots[group[1]] = { x = group.x, y = group.y }
		else
			local spaced = (MARKER_REACH + MARKER_GAP / 2) / math.sin(math.pi / #group)
			local ring = math.max(spaced, MARKER_REACH + LEADER_LENGTH) / scale
			for slot, index in ipairs(group) do
				local angle = FULL_TURN * (slot - 1) / #group - math.pi / 2
				spots[index] = { x = group.x + ring * math.cos(angle), y = group.y + ring * math.sin(angle) }
			end
		end
	end
	return spots
end

local function marker(index, spot, selected)
	local radius = (selected and SELECTED_RADIUS or MARKER_RADIUS) / scale
	local outline = radius + MARKER_RIM / scale
	if selected then
		outline = radius + SELECTED_HALO / scale
		disc(spot.x, spot.y, outline, HALO)
	end
	mission_map.target(index, spot.x, spot.y, outline)
	local gold = watched[index]
	disc(spot.x, spot.y, radius + MARKER_RIM / scale, INK)
	disc(spot.x, spot.y, radius, gold and WATCH_FILL or FILL)
	view.text(tostring(index), spot.x, spot.y, TEXT_SIZE / scale, gold and WATCH_TEXT or TEXT)
end

local function selected_offer()
	for index, offer in ipairs(offers) do
		if offer.selected and placed(index) then
			return index
		end
	end
end

local function centre_on(x, y)
	view.pan(x - view.read("width") / 2, y - view.read("height") / 2)
end

local function centre_on_offers()
	local left, top, right, bottom
	for index = 1, #offers do
		if placed(index) then
			local x, y = mission_map.offer(index, "x"), mission_map.offer(index, "y")
			left, right = math.min(left or x, x), math.max(right or x, x)
			top, bottom = math.min(top or y, y), math.max(bottom or y, y)
		end
	end
	if not left then
		centre_on(mission_map.planet("x"), mission_map.planet("y"))
		return
	end
	if mission_map.player("placed") ~= 0 then
		local x, y = mission_map.player("x"), mission_map.player("y")
		left, right = math.min(left, x), math.max(right, x)
		top, bottom = math.min(top, y), math.max(bottom, y)
	end
	local chosen = selected_offer()
	if chosen and (right - left > view.read("width") or bottom - top > view.read("height")) then
		centre_on(mission_map.offer(chosen, "x"), mission_map.offer(chosen, "y"))
	else
		centre_on((left + right) / 2, (top + bottom) / 2)
	end
end

-- keep a newly selected offer in view
local function reveal_selected()
	local chosen = selected_offer()
	if not chosen or chosen == revealed then
		revealed = chosen
		return
	end
	revealed = chosen
	local x, y = mission_map.offer(chosen, "x"), mission_map.offer(chosen, "y")
	local left, top = view.read("x"), view.read("y")
	local reach = MARKER_REACH / scale
	if x - reach < left or y - reach < top or x + reach > left + view.read("width") or y + reach > top + view.read("height") then
		centre_on(x, y)
	end
end

local function draw()
	if not M.available or records == 0 or fit_pending then
		return
	end
	reveal_selected()
	local groups = groups_of()
	local spots = spots_of(groups)
	mission_map.clear_targets()
	view.markers_begin()
	for _, pass in ipairs({ { LEADER_WIDTH + 2 * LEADER_BORDER, INK }, { LEADER_WIDTH, FILL } }) do
		for _, group in ipairs(groups) do
			if #group > 1 then
				for _, index in ipairs(group) do
					view.line(group.x, group.y, spots[index].x, spots[index].y, pass[1] / scale, pass[2])
				end
			end
		end
	end
	for _, group in ipairs(groups) do
		if #group > 1 then
			disc(group.x, group.y, DOOR_RADIUS / scale, INK)
		end
	end
	local chosen
	for index, offer in ipairs(offers) do
		if spots[index] then
			if offer.selected then
				chosen = index
			else
				marker(index, spots[index], false)
			end
		end
	end
	if chosen then
		marker(chosen, spots[chosen], true)
	end
	drawn_placed = mission_map.player("placed")
	drawn_x, drawn_y = mission_map.player("x"), mission_map.player("y")
	if drawn_placed ~= 0 then
		view.sprite(PLAYER_MARKER, drawn_x, drawn_y, 0, 1 / scale)
	end
	view.markers_end()
end

local function set_wheel_step(step, x, y)
	wheel_step = step
	scale = 2 ^ (wheel_step / WHEEL_STEPS_PER_DOUBLING)
	view.zoom(scale, x, y)
end

local function show_record(zoom)
	record = math.max(0, math.min(records - 1, zoom))
	wheel_turn = 0
	set_wheel_step(0, 0, 0)
	mission_map.record(record)
	centre_on_offers()
	revealed = selected_offer()
	draw()
	ui.enabled(zoom_in, record < records - 1)
	ui.enabled(zoom_out, record > 0)
end

-- the terminal's offers changed (or the watch list): redraw; watch = { [index] = true }
function M.show(next_offers, watch)
	offers, watched = next_offers or {}, watch or {}
	pcall(draw)
end

-- native callbacks, routed here by the terminal
function M.map(next_revision, next_records)
	if not M.available then
		return
	end
	if next_revision ~= revision or next_records ~= records then
		revision, records = next_revision, next_records
		fit_pending = true
		ui.enabled(zoom_in, false)
		ui.enabled(zoom_out, false)
	end
	local w, h = view.read("width"), view.read("height")
	if fit_pending and records > 0 and w > 0 and h > 0 then
		fit_pending = false
		show_record(mission_map.fit(w, h))
	elseif records > 0 and not fit_pending and (mission_map.player("placed") ~= drawn_placed
		or mission_map.player("x") ~= drawn_x or mission_map.player("y") ~= drawn_y) then
		draw()
	end
end

function M.wheel(turn, x, y)
	if not M.available or records == 0 or fit_pending then
		return
	end
	wheel_turn = wheel_turn + turn
	local detents = wheel_turn < 0 and math.ceil(wheel_turn) or math.floor(wheel_turn)
	wheel_turn = wheel_turn - detents
	local step = math.max(0, math.min(MAX_WHEEL_STEPS, wheel_step + detents))
	if step ~= wheel_step then
		set_wheel_step(step, x, y)
		draw()
	end
end

function M.wire()
	if zoom_in then
		ui.on_click(zoom_in, function() if records > 0 then show_record(record + 1) end end)
		ui.on_click(zoom_out, function() if records > 0 then show_record(record - 1) end end)
	end
end

return M
