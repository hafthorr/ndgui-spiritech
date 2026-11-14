-- ndGUI Damage Meter: a standalone window (Control Center > Actions > Addons > Damage Meter).
-- Damage / Healing / Taken per source as skinned bars scaled to the leader: amount, per second and
-- share. "This fight" or "Overall"; you are highlighted, pets teal. Data: game.combat (what this
-- client observes; others' fights far away are not seen).
local Window = ui.require("core.window")
local Meter = ui.require("ndgui.meter")
local Unit = ui.require("notum.ndgui-lib/unit")

local root = ui.load("root.xml")
ui.root(root)
local meter = Meter.create()
local content = ui.load("content.xml")
local host = ui.find(content, "meter_rows")
local summary = ui.find(content, "meter_summary")
local status = ui.find(content, "meter_status")
local buttons = {
	damage = ui.find(content, "meter_damage"),
	healing = ui.find(content, "meter_healing"),
	taken = ui.find(content, "meter_taken"),
}
local scope_button = ui.find(content, "meter_scope")
local reset_button = ui.find(content, "meter_reset")

local MAX_ROWS, ROW_H = 15, 20 -- row.xml adds a 2px gap under each 18px bar
local HEADER_H = 33 + 3 + 18 + 14 + 29 + 3 + 6 -- title, borders, summary, status, buttons, borders, frame
local MIN_W, MAX_W = 300, 640
local NOUN = { damage = "damage", healing = "healing", taken = "taken" }
local RATE = { damage = "DPS", healing = "HPS", taken = "DTPS" }
local COLOR = {
	you = "#4fb3e8", pet = "#5fb8a8",
	damage = "#b8743f", healing = "#4f9f5f", taken = "#a8434a",
}

local mode, scope = "damage", "fight"
local shown, fit, row_w = true, 10, 280
local rows = {}

for index = 1, MAX_ROWS do
	local view = ui.load("row.xml")
	ui.add(host, view)
	local row = { root = ui.find(view, "meter_row") }
	for _, name in ipairs({ "row_track", "row_fill", "row_name", "row_name_shadow", "row_value", "row_value_shadow" }) do
		row[name] = ui.find(view, name)
	end
	ui.visible(row.root, false)
	rows[index] = row
end

-- 12,345 / 12.3k / 1.23M
local function short(n)
	if n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fk", n / 1e3)
	end
	return Unit.thousands(n)
end

-- rates keep one decimal while small: 66.7/s, 1,234/s
local function rate(n)
	return n < 100 and string.format("%.1f", n) or short(n)
end

local function clock(seconds)
	seconds = math.floor(seconds + 0.5)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function render()
	local list, seg = meter:leaders(scope, mode)
	local seconds = Meter.seconds(seg)
	local total = seg and seg.total[mode] or 0
	local label = scope == "fight" and "Fight" or "Overall"
	ui.text(summary, seg and string.format("%s %s  ·  %s %s  ·  %s %s", label, clock(seg.active), short(total), NOUN[mode],
		rate(total / seconds), RATE[mode]) or "No combat yet")
	ui.text(status, meter.incomplete and "Some combat reports were lost; numbers are low"
		or meter.full and "Too many sources; the smallest are not listed"
		or "You, your pets and players this client sees")
	for key, button in pairs(buttons) do
		ui.selected(button, key == mode)
	end
	ui.text(scope_button, scope == "fight" and "This fight" or "Overall")
	local top = list[1] and list[1][mode] or 0
	for index, row in ipairs(rows) do
		local actor = index <= fit and list[index] or nil
		ui.visible(row.root, actor ~= nil)
		if actor then
			local amount = actor[mode]
			local share = total > 0 and amount / total or 0
			local filled = top > 0 and math.floor(row_w * amount / top + 0.5) or 0
			ui.visible(row.row_fill, filled > 0)
			if filled > 0 then
				ui.size(row.row_fill, filled, ROW_H - 2)
			end
			ui.graphic_tint(row.row_fill, actor.self and COLOR.you or actor.pet and COLOR.pet or COLOR[mode])
			local name = index .. ". " .. actor.name
			local value = string.format("%s  %s/s  %d%%", short(amount), rate(amount / seconds), math.floor(share * 100 + 0.5))
			ui.text(row.row_name, name)
			ui.text(row.row_name_shadow, name)
			ui.text(row.row_value, value)
			ui.text(row.row_value_shadow, value)
			ui.tooltip(row.root, string.format("%s: %s %s, %.1f %s, %.1f%%", actor.name, Unit.thousands(amount), NOUN[mode],
				amount / seconds, RATE[mode], share * 100))
		end
	end
end

local function layout(window, width, height)
	width = math.max(MIN_W, math.min(MAX_W, width))
	local minimum, maximum = HEADER_H + 3 * ROW_H, HEADER_H + MAX_ROWS * ROW_H
	height = math.max(minimum, math.min(maximum, height))
	fit = math.max(1, math.min(MAX_ROWS, math.floor((height - HEADER_H) / ROW_H)))
	row_w = width - Window.CONTENT_SIDES - 6
	for _, row in ipairs(rows) do
		ui.size(row.root, row_w, ROW_H - 2)
		ui.size(row.row_track, row_w, ROW_H - 2)
		local name_w = math.floor(row_w * 0.5)
		ui.size(row.row_name, name_w, ROW_H - 2)
		ui.size(row.row_name_shadow, name_w, ROW_H - 3)
		ui.size(row.row_value, row_w - name_w - 4, ROW_H - 2)
		ui.size(row.row_value_shadow, row_w - name_w - 4, ROW_H - 3)
	end
	ui.size(summary, row_w, 18)
	ui.size(status, row_w, 14)
	ui.limits(window.root, MIN_W, minimum, MAX_W, maximum)
	ui.request_size(window.root, width, height)
	window:fit_title(width, true)
	window:fit_content(width, height)
	render()
end

local frame = Window.create({
	template = "library://notum.ndgui-lib/window.xml",
	title = "Damage Meter", content = content, width = 340, height = HEADER_H + 8 * ROW_H,
	horizontal = "right", vertical = "center", layout = layout,
})
ui.add(root, frame.root)
ui.register_view(frame.root, "meter")

-- mode and scope are remembered with the window
local function save()
	if ui.preference and ui.preference.write then
		pcall(ui.preference.write, "NdguiMeterMode", mode, "text")
		pcall(ui.preference.write, "NdguiMeterScope", scope, "text")
	end
end
if ui.preference and ui.preference.read then
	local ok, saved = pcall(ui.preference.read, "NdguiMeterMode")
	if ok and NOUN[saved] then mode = saved end
	ok, saved = pcall(ui.preference.read, "NdguiMeterScope")
	if ok and (saved == "fight" or saved == "all") then scope = saved end
end

for key, button in pairs(buttons) do
	ui.on_click(button, function()
		mode = key
		save()
		render()
	end)
end
ui.on_click(scope_button, function()
	scope = scope == "fight" and "all" or "fight"
	save()
	render()
end)

local function observe()
	return game.combat.subscribe("damage,healing", function(batch, events)
		meter:apply(batch, events)
		if shown then
			render()
		end
	end)
end
local subscription = observe()
ui.on_click(reset_button, function()
	game.combat.unsubscribe(subscription)
	subscription = observe()
	meter:reset()
	render()
end)
ui.on_visibility(frame.root, function(visible)
	shown = visible
	if shown then
		render()
	end
end)
render()
