-- ndGUI Mission Terminal (prk.mission-terminal), hand-made from the stock MissionTerminal package.
-- Clicksaver-style, within what the client allows (every Request / Select / Accept is still your click):
--   * offers are rows with the server's full summary instead of six bare icons
--   * a watch list (comma separated words) lights matching offers gold and logs them for the session
--   * four slider presets: left-click applies, right-click saves the current sliders
--   * the chosen-reward panel shows the cost per roll and what this session's rolls cost
--   * recent chosen rewards are remembered (shared by all characters)
local Window = ui.require("core.window")
local content = ui.load("content.xml")
local status = ui.find(content, "status")
local offers_host = ui.find(content, "offers")
local watch_input = ui.find(content, "watch")
local watch_clear = ui.find(content, "watch_clear")
local request = ui.find(content, "request")
local accept = ui.find(content, "accept")
local cancel = ui.find(content, "cancel")
local mode_random = ui.find(content, "mode_random")
local mode_pinned = ui.find(content, "mode_pinned")
local reward_row = ui.find(content, "reward_row")
local reward_back = ui.find(content, "reward_back")
local reward_slot = ui.find(content, "reward_slot")
local reward_name = ui.find(content, "reward_name")
local reward_ql = ui.find(content, "reward_ql")
local reward_clear = ui.find(content, "reward_clear")
local reward_cost = ui.find(content, "reward_cost")
local recent_view = ui.find(content, "recent")
local log_head = ui.find(content, "log_head")
local log_view = ui.find(content, "log")
local row_difficulty = ui.find(content, "row_difficulty")

local WIDTH = 380
local OFFERS = 6
local ICON, TEXT_LEFT = 40, 6 + 40 + 7 + 4
local GOLD, STEEL, SELECTED_BACK, BACK, MATCH_BACK = "#FFD84A", "#3D6F9A", "#C0183048", "#A00A1016", "#B03A3010"
local LOG_MAX, RECENT_MAX = 8, 6
local ROWS = { "difficulty", "good", "order", "open", "physical", "headon", "credits" }

local width = WIDTH
local request_label = "Request"
local sliders = {}
local values = {} -- current staged slider values (1..7)
local watch_terms = {}
local rows = {}
local last_offers_key
local rolls, spent, matches = 0, 0, 0
local match_log = {} -- newest first: { text = summary, terms = "x, y", roll = n }
local last_reward
local frame

-- ---- storage (shared by every character) -------------------------------------------------
-- ui.storage (shared by every character) where the client offers it to this window, else the
-- window's own preferences (per character); both are written, the first non-empty one is read.
local function pref_key(key)
	return "Ndgui_" .. key
end
local function stored(key)
	local ok, value = pcall(function() return ui.storage.read(key) end)
	if ok and type(value) == "string" and value ~= "" then
		return value
	end
	ok, value = pcall(function() return ui.preference.read(pref_key(key)) end)
	return ok and type(value) == "string" and value or ""
end
local function store(key, value)
	pcall(function() ui.storage.write(key, value) end)
	pcall(function() ui.preference.write(pref_key(key), value, "text") end)
end

local function split_terms(text)
	local terms = {}
	for term in (text or ""):gmatch("[^,;]+") do
		term = term:match("^%s*(.-)%s*$")
		if #term >= 2 then
			terms[#terms + 1] = term
		end
	end
	return terms
end

local function credits(amount)
	local digits = tostring(math.floor(amount or 0))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end

-- every watch term found in the text (plain, case-insensitive)
local function matched_terms(text)
	local found = {}
	local lower = string.lower(text or "")
	for _, term in ipairs(watch_terms) do
		if lower:find(string.lower(term), 1, true) then
			found[#found + 1] = term
		end
	end
	return found
end

-- Diagnostics (one-off): which game domains this window's VM can see, and whether ui.storage works here.
-- Read back from addon-data/*.json; decides how the Info window can share mission briefings.
do
	local seen = {}
	for _, name in ipairs({ "info", "missions", "mission_terminal", "mission_reward", "playfield_map", "team", "character", "combat" }) do
		local ok, value = pcall(function() return game[name] end)
		seen[#seen + 1] = name .. "=" .. (ok and type(value) or "error")
	end
	local ok_storage = pcall(function() ui.storage.write("diag", table.concat(seen, " ")) end)
	pcall(function() ui.preference.write("Ndgui_diag", table.concat(seen, " ") .. " storage=" .. tostring(ok_storage), "text") end)
end

-- ---- offer rows ------------------------------------------------------------------------
for index = 1, OFFERS do
	local root = ui.load("offer.xml")
	ui.add(offers_host, root)
	rows[index] = {
		root = root,
		back = ui.find(root, "offer_back"),
		stripe = ui.find(root, "offer_stripe"),
		icon = ui.find(root, "offer_icon"),
		badge = ui.find(root, "offer_badge"),
		text = ui.find(root, "offer_text"),
		hit = ui.find(root, "offer_hit"),
	}
	ui.visible(root, false)
end

local function offer_height(text)
	-- two lines fit beside the icon; longer summaries get more lines
	local chars_per_line = math.max(20, math.floor((width - 11 - 10 - TEXT_LEFT) / 6.2))
	local lines = math.max(2, math.ceil(#(text or "") / chars_per_line))
	return math.max(ICON + 6, lines * 14 + 8)
end

local function show_offer(row, offer)
	ui.visible(row.root, offer ~= nil)
	if not offer then
		return
	end
	local found = matched_terms(offer.description)
	local hit = #found > 0
	local inner = width - 11 - 10
	local text_w = inner - TEXT_LEFT
	local badge_h = hit and 13 or 0
	local h = offer_height(offer.description) + badge_h
	ui.size(row.root, inner, h)
	ui.size(row.back, inner, h)
	ui.size(row.hit, inner, h)
	ui.size(row.stripe, 3, h)
	ui.size(row.badge, text_w, badge_h)
	ui.size(row.text, text_w, h - 6 - badge_h)
	ui.fill_color(row.back, offer.selected and SELECTED_BACK or hit and MATCH_BACK or BACK)
	ui.fill_color(row.stripe, hit and GOLD or offer.selected and "#4FB3E8" or STEEL)
	ui.visible(row.badge, hit)
	ui.text(row.badge, hit and ("WATCHED: " .. table.concat(found, ", ")) or "")
	ui.text(row.text, offer.description ~= "" and offer.description or "(no summary)")
	ui.text_color(row.text, hit and "#FFF2C0" or "#C5D7E6")
	ui.icon(row.icon, offer.icon or 0)
	ui.content(row.icon, (offer.icon or 0) ~= 0)
	ui.tooltip(row.hit, offer.description or "")
	ui.selected(row.hit, offer.selected == true)
	if not ui.in_combat() and row.reference ~= offer.reference then
		row.reference = offer.reference
		pcall(ui.bind, row.hit, offer.reference)
		pcall(ui.action, row.hit, "game.mission_terminal.choose", offer.reference, "left")
	end
	return hit, found
end

-- ---- status / log ---------------------------------------------------------------------
local function show_status()
	local parts = { "Roll " .. rolls }
	if matches > 0 then
		parts[#parts + 1] = matches .. (matches == 1 and " match" or " matches")
	end
	if spent > 0 then
		parts[#parts + 1] = credits(spent) .. " credits spent"
	end
	if #watch_terms == 0 then
		parts[#parts + 1] = "add words to watch for below"
	end
	ui.text(status, table.concat(parts, "  ·  "))
end

local function show_log()
	ui.visible(log_head, #match_log > 0)
	ui.visible(log_view, #match_log > 0)
	local lines = {}
	for _, item in ipairs(match_log) do
		lines[#lines + 1] = "Roll " .. item.roll .. "  [" .. item.terms .. "]  " .. item.text
	end
	ui.text(log_view, table.concat(lines, "\n"))
	local chars_per_line = math.max(20, math.floor((width - 21) / 5.6))
	local n = 0
	for _, line in ipairs(lines) do
		n = n + math.max(1, math.ceil(#line / chars_per_line))
	end
	ui.size(log_view, width - 21, n * 13 + 2)
end

-- ---- recent chosen rewards --------------------------------------------------------------
local recent = {}
do
	for line in stored("recent_rewards"):gmatch("[^\n]+") do
		local name, ql = line:match("^(.-)\t(%d+)$")
		if name then
			recent[#recent + 1] = { name = name, ql = tonumber(ql) }
		end
	end
end
local function remember_reward(name, ql)
	if not name or name == "" then
		return
	end
	for i = #recent, 1, -1 do
		if recent[i].name == name and recent[i].ql == ql then
			table.remove(recent, i)
		end
	end
	table.insert(recent, 1, { name = name, ql = ql })
	while #recent > RECENT_MAX do
		table.remove(recent)
	end
	local lines = {}
	for _, r in ipairs(recent) do
		lines[#lines + 1] = r.name .. "\t" .. r.ql
	end
	store("recent_rewards", table.concat(lines, "\n"))
end
local function show_recent(pinned_mode)
	local others = {}
	for _, r in ipairs(recent) do
		others[#others + 1] = r.name .. " QL " .. r.ql
	end
	local on = pinned_mode and #others > 0
	ui.visible(recent_view, on)
	if on then
		local text = "Recent: " .. table.concat(others, "  ·  ")
		ui.text(recent_view, text)
		ui.size(recent_view, width - 21, math.max(1, math.ceil(#text / math.floor((width - 21) / 5.6))) * 13 + 2)
	end
end

-- ---- sliders + presets ------------------------------------------------------------------
for index, name in ipairs(ROWS) do
	sliders[index] = ui.find(content, "slider_" .. name)
	ui.on_value_committed(sliders[index], function(value)
		values[index] = value
		game.mission_terminal.slider(index, value)
	end)
end

local function preset_text(index)
	return stored("preset_" .. index)
end
local function preset_label(index)
	local saved = preset_text(index)
	local name = saved:match("^([^|]*)|")
	return (name and name ~= "") and name or ("Preset " .. index)
end
local function paint_presets()
	for index = 1, 4 do
		local button = ui.find(content, "preset_" .. index)
		local saved = preset_text(index)
		ui.text(button, preset_label(index))
		ui.opacity(button, saved ~= "" and 1 or 0.55)
		ui.tooltip(button, saved ~= "" and "Left-click: apply these preferences\nRight-click: save the current ones here"
			or "Empty. Right-click to save the current preferences here")
	end
end
local function apply_preset(index)
	local saved = preset_text(index)
	local numbers = saved:match("|(.*)$")
	if not numbers then
		return
	end
	local i = 0
	for value in numbers:gmatch("[^,]+") do
		i = i + 1
		local v = tonumber(value)
		if v and sliders[i] then
			v = math.max(0, math.min(1, v))
			values[i] = v
			ui.progress(sliders[i], v)
			game.mission_terminal.slider(i, v)
		end
	end
end
local function save_preset(index)
	local parts = {}
	for i = 1, #ROWS do
		parts[i] = string.format("%.3f", values[i] or 0.5)
	end
	-- a short name from the strongest leanings, e.g. "Stealth Credits"
	local names = {}
	local labels = { "Easy|Hard", "Good|Bad", "Order|Chaos", "Open|Hidden", "Physical|Mystical", "Head on|Stealth", "Credits|XP" }
	local strongest = {}
	for i = 2, #ROWS do
		local v = values[i] or 0.5
		if math.abs(v - 0.5) >= 0.25 then
			strongest[#strongest + 1] = { i = i, d = math.abs(v - 0.5), side = v < 0.5 and 1 or 2 }
		end
	end
	table.sort(strongest, function(a, b) return a.d > b.d end)
	for k = 1, math.min(2, #strongest) do
		local pick = strongest[k]
		local left, right = labels[pick.i]:match("^(.-)|(.-)$")
		names[#names + 1] = pick.side == 1 and left or right
	end
	local name = #names > 0 and table.concat(names, " ") or ("Preset " .. index)
	store("preset_" .. index, name .. "|" .. table.concat(parts, ","))
	paint_presets()
end
for index = 1, 4 do
	local button = ui.find(content, "preset_" .. index)
	ui.on_click(button, function() apply_preset(index) end)
	ui.on_pointer_release(button, "right", function() save_preset(index) end)
end
paint_presets()

-- ---- watch list -------------------------------------------------------------------------
local refresh_offers
ui.text(watch_input, stored("watch"))
watch_terms = split_terms(stored("watch"))
ui.on_text_changed(watch_input, function(text)
	store("watch", text)
	watch_terms = split_terms(text)
	if refresh_offers then refresh_offers() end
end)
ui.on_click(watch_clear, function()
	ui.text(watch_input, "")
	store("watch", "")
	watch_terms = {}
	if refresh_offers then refresh_offers() end
end)

-- ---- window -----------------------------------------------------------------------------
frame = Window.create({
	template = "library://notum.ndgui-lib/window.xml",
	title = "Mission Terminal",
	content = content,
	width = width,
	resizable = false,
	horizontal = "center",
	vertical = "center",
	layout = function(window)
		ui.size(window.root, width, -1)
		ui.size(content, width - 11, -1)
		ui.size(status, width - 21, 15)
		ui.size(reward_back, width - 21, 48)
		window:fit_title(width, true)
	end,
})
ui.root(frame.root)
ui.fill_color(reward_back, BACK)

local current_offers = {}
refresh_offers = function()
	local any_hit = false
	for index, row in ipairs(rows) do
		local hit = show_offer(row, current_offers[index])
		any_hit = any_hit or hit
	end
	ui.text(ui.find(frame.root, "window_title"), any_hit and "Mission Terminal  -  MATCH!" or "Mission Terminal")
	show_status()
	frame:resize(width, -1)
end

function mission_terminal_configure(label_request, accept_label, labels)
	request_label = label_request
	ui.text(request, request_label)
	ui.text(accept, accept_label)
	local widest = 0
	for index, name in ipairs(ROWS) do
		local minimum = ui.find(content, "row_" .. name .. "_min")
		local maximum = ui.find(content, "row_" .. name .. "_max")
		ui.text(minimum, labels[index].minimum)
		ui.text(maximum, labels[index].maximum)
		local a, b = ui.text_width(minimum), ui.text_width(maximum)
		widest = math.max(widest, type(a) == "number" and a or 0, type(b) == "number" and b or 0)
		values[index] = labels[index].progress
		ui.progress(sliders[index], labels[index].progress)
	end
	local column = math.ceil(widest) + 5
	for _, name in ipairs(ROWS) do
		for _, bound in ipairs({ "_min", "_max" }) do
			local label = ui.find(content, "row_" .. name .. bound)
			ui.size(label, column, 17)
			ui.maximum(label, column, -1)
		end
	end
	width = math.max(WIDTH, column * 2 + 120 + 21)
	frame:resize(width, -1)
end

function mission_terminal_sliders(next_values)
	for index, value in ipairs(next_values) do
		values[index] = value
		ui.progress(sliders[index], value)
	end
end

local function command(view, name, reference)
	if ui.in_combat() then
		return
	end
	pcall(ui.bind, view, reference)
	pcall(ui.action, view, name, reference, "left")
end

local function apply_reward(reward)
	ui.selected(mode_random, not reward.pinned_mode)
	ui.selected(mode_pinned, reward.pinned_mode)
	command(mode_random, "game.mission_terminal.random", reward.random)
	command(mode_pinned, "game.mission_terminal.pinned", reward.pinned)
	ui.visible(reward_row, reward.pinned_mode)
	ui.visible(row_difficulty, not reward.pinned_mode)
	command(reward_slot, "game.mission_terminal.choose_reward", reward.choose)
	ui.icon(reward_slot, reward.icon or 0)
	ui.content(reward_slot, reward.has_pin)
	ui.text(reward_name, reward.has_pin and reward.name or "No reward chosen")
	ui.text(reward_ql, reward.has_pin and ("QL " .. reward.ql) or "Click the slot to choose one")
	ui.visible(reward_clear, reward.has_pin)
	ui.text(reward_cost, reward.has_pin and reward.cost > 0
		and ("Each roll costs " .. credits(reward.cost) .. " credits") or "")
	command(reward_clear, "game.mission_terminal.clear_reward", reward.clear)
	ui.text(request, reward.pinned_mode and "Request chain" or request_label)
	if reward.has_pin then
		remember_reward(reward.name, reward.ql)
	end
	show_recent(reward.pinned_mode)
end

function mission_terminal_apply(state, offers, reward)
	offers = offers or {}
	-- a new set of offers = one roll
	local parts = {}
	for _, offer in ipairs(offers) do
		parts[#parts + 1] = tostring(offer.reference) .. ":" .. (offer.description or "")
	end
	local key = table.concat(parts, "\n")
	if #offers > 0 and key ~= last_offers_key then
		rolls = rolls + 1
		if reward.pinned_mode and reward.has_pin and (reward.cost or 0) > 0 then
			spent = spent + reward.cost
		end
		for _, offer in ipairs(offers) do
			local found = matched_terms(offer.description)
			if #found > 0 then
				matches = matches + 1
				table.insert(match_log, 1, { text = offer.description, terms = table.concat(found, ", "), roll = rolls })
			end
		end
		while #match_log > LOG_MAX do
			table.remove(match_log)
		end
		show_log()
	end
	last_offers_key = key
	current_offers = offers
	last_reward = reward
	command(request, "game.mission_terminal.request", state.request)
	ui.enabled(request, not reward.pinned_mode or reward.has_pin)
	apply_reward(reward)
	command(accept, "game.mission_terminal.accept", state.accept)
	ui.enabled(accept, state.selected)
	command(cancel, "game.mission_terminal.cancel", state.cancel)
	refresh_offers()
end

show_status()
show_log()
