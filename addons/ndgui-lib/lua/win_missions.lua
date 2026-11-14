-- ndGUI missions window as a module: required by its own package or by ndgui-mission-hub, which
-- provides Info, Missions and Mission Terminal from one package so they can share mission briefs.
-- Returns its native callbacks; the requiring package routes the globals to them.
local M = {}
local BASE = "library://notum.ndgui-lib/missions_"
-- ndGUI Missions window (prk.missions), hand-made from the stock Missions package.
-- Folds to its title bar ("Missions (3) - 1:20" = the mission on your map); the mission list on the left (icon, name, time left with a draining bar) and the chosen mission on the right.
-- Every row and the detail icon carry the native mission binding, so right-click keeps the stock
-- Look at / Upload to map / Delete menu; left-click only chooses which mission the right pane shows.
-- The client gives this window icon, name, deadline and "on the map" only; the briefing, rewards and
-- location reach the Info window alone (right-click > Look at mission). In ndgui-mission-hub Info keeps
-- each briefing it shows (briefs.lua) and the right pane shows it from then on.
local Window = ui.require("core.window")
local Shell = ui.require("notum.ndgui-lib/shell")
local Table = ui.require("notum.ndgui-lib/table")
local Briefs = ui.require("notum.ndgui-lib/briefs")
local content = ui.load(BASE .. "content.xml")
local body = ui.find(content, "missions_body")
local list = ui.find(content, "mission_list")
local empty = ui.find(content, "missions_empty")
local detail = {
	root = ui.find(content, "mission_detail"),
	icon = ui.find(content, "detail_icon"),
	title = ui.find(content, "detail_title"),
	status = ui.find(content, "detail_status"),
	time_label = ui.find(content, "detail_time_label"),
	time = ui.find(content, "detail_time"),
	time_track = ui.find(content, "detail_time_track"),
	time_fill = ui.find(content, "detail_time_fill"),
	time_shadow = ui.find(content, "detail_time_shadow"),
	time_text = ui.find(content, "detail_time_text"),
	hint = ui.find(content, "detail_hint"),
	brief = ui.find(content, "detail_brief"),
	pay = ui.find(content, "detail_pay"),
	where = ui.find(content, "detail_where"),
	reward = ui.find(content, "detail_reward"),
	reward_icon = ui.find(content, "detail_reward_icon"),
	reward_name = ui.find(content, "detail_reward_name"),
	text = ui.find(content, "detail_text"),
}
local HINT_NONE = "Right-click > Look at mission once: its briefing, pay and reward then stay here."
local HINT_MENU = "Right-click the mission to look at it, upload it to your map or delete it."
local brief_rev

local TITLE_H, CONTENT_BORDERS = 33, 6
local FOLDED_H = 30 -- frame + title bar
local DETAIL_W, DETAIL_GAP, DETAIL_MIN_TOTAL = 250, 4, 460 -- the detail pane shows from this window width
local MIN_LIST_H, MAX_W, MAX_H = 90, 900, 1200
local TIME_W, TIME_BAR = 70, 62
local ON_MAP, NAME, MUTED = "#3DE33D", "#C5D7E6", "#9AA8B4"
local URGENT, SOON, PLENTY = "#E0503C", "#E0C040", "#4FB3E8"

local entries = {}
local frame, populate, fold, title
local chosen -- key of the mission shown on the right (nil: the one on the map, else the first)
local totals = {} -- key -> most minutes seen, so the time bar drains from where it started
local shown_detail, detail_w = false, DETAIL_W

local collapsed = false
local UNFOLD_MIN_H = 220
local unfolded_h = UNFOLD_MIN_H -- height to come back to after a fold
do
	local ok, saved = pcall(ui.preference.read, "NdguiMissionsCollapsed")
	collapsed = ok and saved == "true"
	local ok_h, h = pcall(ui.preference.read, "NdguiMissionsHeight")
	unfolded_h = ok_h and tonumber(h) or UNFOLD_MIN_H
end

local function key(entry)
	return tostring(entry.token) .. "|" .. (entry.name or "")
end

local function remaining(entry)
	if not entry.timed then
		return ""
	end
	return string.format("%d:%02d", math.floor(entry.minutes / 60), entry.minutes % 60)
end

local function fraction(entry)
	if not entry.timed then
		return 1
	end
	local total = math.max(totals[key(entry)] or entry.minutes, 1)
	return math.max(0, math.min(1, entry.minutes / total))
end

local function urgency(entry)
	if not entry.timed then
		return PLENTY
	end
	if entry.minutes < 10 then
		return URGENT
	elseif entry.minutes < 30 then
		return SOON
	end
	return PLENTY
end

local function binding(entry)
	return entry.token
end

local mission_table = Table.create({
	host = list,
	fit_columns = true,
	preference = "listview_config",
	columns = {
		{
			id = "icon", title = "", width = 16, minimum = 16, maximum = 16, resizable = false, kind = "icon",
			icon = function(entry) return entry.icon end,
		},
		{
			id = "name", title = "Name", width = 200, minimum = 60,
			text = function(entry) return entry.name end,
			value = function(entry) return string.lower(entry.name) end,
			color = function(entry) return entry.selected and ON_MAP or NAME end,
		},
		{
			id = "remain", title = "Time left", width = TIME_W, minimum = TIME_W, maximum = TIME_W,
			resizable = false, kind = "custom", template = BASE .. "time_cell.xml",
			value = function(entry) return entry.timed and entry.minutes or math.huge end,
			create = function(cell)
				cell.fill = ui.find(cell.root, "time_fill")
				cell.label = ui.find(cell.root, "time_text")
				cell.track = ui.find(cell.root, "time_track")
			end,
			update = function(cell, entry)
				local timed = entry ~= nil and entry.timed
				ui.text(cell.label, entry and (timed and remaining(entry) or "-") or "")
				ui.visible(cell.track, timed)
				ui.visible(cell.fill, timed)
				if timed then
					ui.size(cell.fill, math.max(1, math.floor(TIME_BAR * fraction(entry) + 0.5)), 3)
					ui.graphic_tint(cell.fill, urgency(entry))
				end
			end,
		},
	},
	binding = binding,
	tooltip = function(entry)
		local time = entry.timed and ("\n" .. remaining(entry) .. " left") or ""
		return entry.name .. time .. (entry.selected and "\nOn your map" or "")
	end,
	selected = function(entry) return entry.selected end,
	activate = function(entry)
		chosen = key(entry)
		if populate then populate() end
	end,
	changed = function()
		if populate then populate() end
	end,
})

local function focused()
	local on_map, first
	for _, entry in ipairs(entries) do
		if chosen and key(entry) == chosen then
			return entry
		end
		if entry.selected and not on_map then on_map = entry end
		first = first or entry
	end
	return on_map or first
end

local function show_detail()
	local entry = focused()
	ui.visible(detail.root, shown_detail and entry ~= nil and not collapsed)
	if not entry then
		return
	end
	ui.icon(detail.icon, entry.icon or 0)
	ui.content(detail.icon, (entry.icon or 0) ~= 0)
	if not ui.in_combat() and ui.binding(detail.icon) ~= entry.token then
		pcall(ui.bind, detail.icon, entry.token)
	end
	ui.tooltip(detail.icon, entry.name)
	ui.text(detail.title, entry.name or "")
	ui.text(detail.status, entry.selected and "On your map" or "Not on your map")
	ui.text_color(detail.status, entry.selected and ON_MAP or MUTED)
	local inner = detail_w - 16
	ui.visible(detail.time_label, entry.timed)
	ui.visible(detail.time, entry.timed)
	if entry.timed then
		local text = remaining(entry) .. " left"
		ui.text(detail.time_text, text)
		ui.text(detail.time_shadow, text)
		ui.size(detail.time_fill, math.max(1, math.floor(inner * fraction(entry) + 0.5)), 18)
		ui.graphic_tint(detail.time_fill, urgency(entry))
	end
	-- the briefing Info kept for this mission
	local brief = Briefs.find(entry.name)
	ui.visible(detail.brief, brief ~= nil)
	ui.text(detail.hint, brief and HINT_MENU or HINT_NONE)
	if brief then
		local pay = Briefs.summary(brief, false)
		ui.text(detail.pay, pay ~= "" and pay or "No cash or XP")
		ui.visible(detail.where, brief.zone ~= nil)
		ui.text(detail.where, brief.zone and ("Where: " .. brief.zone) or "")
		ui.visible(detail.reward, brief.item ~= nil)
		ui.text(detail.reward_name, brief.item or "")
		ui.icon(detail.reward_icon, brief.icon or 0)
		ui.content(detail.reward_icon, (brief.icon or 0) ~= 0)
		local text = brief.text or ""
		ui.text(detail.text, text)
		ui.tooltip(detail.text, text)
		local per_line = math.max(16, math.floor(inner / 6.2))
		ui.size(detail.text, inner, math.max(14, math.ceil(#text / per_line) * 14 + 4))
	end
end

-- "Missions (2)"; folded it also shows the time left on the mission on your map (or the first one)
local function show_header()
	if not title then
		return
	end
	local text = #entries > 0 and string.format("Missions (%d)", #entries) or "Missions"
	local lead = focused()
	if collapsed and lead and lead.timed then
		text = text .. " - " .. remaining(lead)
	end
	ui.text(title, text)
	pcall(function() ui.text(ui.find(frame.root, "rollup_title"), text) end) -- the docked page (Missions can dock)
	if fold then
		ui.selected(fold, collapsed)
		ui.tooltip(fold, collapsed and "Unfold the mission list" or "Fold to the title bar")
	end
end

local function layout(window, width, height)
	local fixed = TITLE_H + CONTENT_BORDERS
	width = math.max(Window.MINIMUM_WIDTH, math.min(MAX_W, width))
	if collapsed then
		ui.limits(window.root, Window.MINIMUM_WIDTH, FOLDED_H, MAX_W, FOLDED_H)
		height = FOLDED_H
	else
		ui.limits(window.root, Window.MINIMUM_WIDTH, fixed + MIN_LIST_H, MAX_W, MAX_H)
		height = math.max(fixed + MIN_LIST_H, math.min(MAX_H, height))
	end
	ui.visible(body, not collapsed)
	local inner_w = width - Window.CONTENT_SIDES - CONTENT_BORDERS
	shown_detail = width >= DETAIL_MIN_TOTAL and #entries > 0
	local body_h = math.max(0, height - fixed)
	local list_w = shown_detail and inner_w - DETAIL_W - DETAIL_GAP or inner_w
	detail_w = DETAIL_W
	ui.visible(list, #entries > 0)
	ui.visible(empty, #entries == 0)
	ui.size(empty, inner_w, body_h)
	ui.size(list, list_w, body_h)
	ui.size(detail.root, detail_w, body_h)
	ui.size(ui.find(content, "detail_back"), detail_w, body_h)
	local inner = detail_w - 16
	ui.size(detail.title, inner - 56, 36)
	ui.size(detail.status, inner - 56, 16)
	ui.size(detail.time_label, inner, 14)
	ui.size(detail.time, inner, 18)
	ui.size(detail.time_track, inner, 18)
	ui.size(detail.time_shadow, inner, 18)
	ui.size(detail.time_text, inner, 18)
	ui.size(detail.hint, inner, 44)
	ui.size(detail.pay, inner, 16)
	ui.size(detail.where, inner, 15)
	ui.size(detail.reward, inner, 32)
	ui.size(detail.reward_name, inner - 38, 32)
	window:fit_title(width, true)
	ui.request_size(window.root, width, height)
	window:fit_content(width, height)
	mission_table:set_width(list_w)
	if populate then populate() end
end

frame = Shell.window({
	template = "library://notum.ndgui-lib/window.xml",
	title = "Missions", content = content, width = 520, height = 220, layout = layout,
})
title = ui.find(frame.root, "window_title")
fold = ui.find(frame.root, "window_fold")
ui.visible(fold, true)
ui.on_click(fold, function()
	collapsed = not collapsed
	pcall(ui.preference.write, "NdguiMissionsCollapsed", tostring(collapsed), "bool")
	if not collapsed then
		-- unfold back to the height it had before folding
		frame:resize(ui.chosen_width(frame.root), math.max(unfolded_h, UNFOLD_MIN_H))
	else
		unfolded_h = math.max(ui.chosen_height(frame.root), UNFOLD_MIN_H)
		pcall(ui.preference.write, "NdguiMissionsHeight", tostring(math.floor(unfolded_h)), "int")
		frame:resize(ui.chosen_width(frame.root), FOLDED_H)
	end
	show_header()
end)

populate = function()
	show_header()
	if not collapsed then
		mission_table:show(entries, mission_table:order(entries))
	end
	show_detail()
end

function M.missions_apply(snapshot)
	entries = snapshot or {}
	local present = {}
	for _, entry in ipairs(entries) do
		local k = key(entry)
		present[k] = true
		if entry.timed then
			totals[k] = math.max(totals[k] or 0, entry.minutes)
		end
	end
	for k in pairs(totals) do
		if not present[k] then totals[k] = nil end
	end
	if chosen and not present[chosen] then chosen = nil end
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end

-- Info saves briefs from another VM: look for new ones about once a second
local next_check = 0
pcall(ui.on_update, function(now)
	if (now or 0) < next_check then
		return
	end
	next_check = (now or 0) + 1000
	local rev = Briefs.revision()
	if rev ~= brief_rev then
		brief_rev = rev
		if not collapsed then show_detail() end
	end
end)

ui.text(detail.time_label, "Time left")
ui.fill_color(ui.find(content, "detail_back"), "#B00A1016")
populate()

return M
