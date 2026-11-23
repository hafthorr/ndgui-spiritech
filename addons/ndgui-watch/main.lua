-- ndGUI Buff Watch (standalone addon: Control Center > Actions > Addons > Buff Watch / Team Buffs).
ui.require("notum.ndgui-lib/grid") -- ndGUI: snap to grid while moving/resizing (ndgui-lib/lua/grid.lua)
--
--   Buff Watch  what needs attention as rows with draining timers: debuffs on you, buffs about to run
--               out (amber), buffs you pinned; every other buff as a small icon strip (hover for
--               details, right-click: Always show as a row / Hide); then what you put on your target.
--               The window menu sets the warning time, shows hidden buffs again, or lists everything
--   Team Buffs  a member per row, a buff per column (buffs anyone on the team has): time left, or red
--               when missing. Click a member to target them, then cast as usual (an addon cannot cast)
--   Alerts      a banner under the compass, always on (the Buff Watch window menu turns it off): low
--               health, a debuff landing on you, low nano, a long buff about to end
-- Data: game.effects ("self", "target", "team"), game.character, game.team. Read-only.
local Window = ui.require("core.window")
local Watch = ui.require("ndgui.watch")

local root = ui.load("root.xml")
ui.root(root)

local function pref(key, default)
	local ok, value = pcall(ui.preference.read, key)
	if not ok or value == nil or value == "" then
		return default
	end
	return value
end
local function set_pref(key, value, kind)
	pcall(ui.preference.write, key, value, kind)
end

-- ---- colours and sizes -------------------------------------------------------------------
local STEEL, AMBER, RED, HOSTILE, MINE = "#3D6F9A", "#B8902E", "#B8433A", "#7A2626", "#A0662E"
local TEXT, HOSTILE_TEXT, MUTED = "#E6EEF5", "#FFB0A0", "#7F9BB0"
local ROW_H, HEAD_H, EMPTY_H, GAP = 22, 14, 16, 8
local MAX_YOU, MAX_TARGET = 14, 8
local BUFF_MIN_W, BUFF_MAX_W = 200, 460
local TITLE_ENDS, BORDERS = 33, 6
local NAME_W, CELL_W, CELL_H = 110, 42, 22
local MAX_MEMBERS = 12
local ICON_STEP, ICON_LINES, ICONS_PER_LINE = 22, 5, 20
local ICON_OPACITY = 0.8 -- the strip is background next to the rows

-- ---- state -------------------------------------------------------------------------------
local self_id
local you = { effects = {}, sampled = 0 }
local target = { effects = {}, sampled = 0, name = nil }
local vitals = {}
local team = { members = {}, collections = {}, sampled = 0, in_team = false }
local debuff_refs, debuff_hits = nil, {}
local alerts_on = pref("NdguiWatchAlerts", "true") ~= "false"
local all_rows = pref("NdguiWatchAllRows", "false") == "true"
local warn = tonumber(pref("NdguiWatchWarn", "")) or Watch.WARN_DEFAULT
-- buff names for "Always show as a row" / "Hide this buff", saved as name|name
local function read_set(key)
	local set = {}
	for name in pref(key, ""):gmatch("[^|]+") do
		set[name] = true
	end
	return set
end
local function write_set(key, set)
	local names = {}
	for name in pairs(set) do
		names[#names + 1] = name
	end
	table.sort(names)
	set_pref(key, table.concat(names, "|"), "text")
end
local pinned, hidden = read_set("NdguiWatchPinned"), read_set("NdguiWatchHidden")
local quiet = read_set("NdguiWatchQuiet") -- "Don't warn about this buff" (team auras...)

-- =========================================================================================
-- Buff Watch window
-- =========================================================================================
local buffs = ui.load("buffs.xml")
local function bfind(name) return ui.find(buffs, name) end
local you_host, target_host, icons_host = bfind("you_rows"), bfind("target_rows"), bfind("you_icons")
local you_head, you_empty = bfind("you_head"), bfind("you_empty")
local target_head, target_empty = bfind("target_head"), bfind("target_empty")
local buff_w = tonumber(pref("NdguiWatchWidth", "")) or 250

local function make_rows(host, count)
	local rows = {}
	for index = 1, count do
		local view = ui.load("buff_row.xml")
		ui.add(host, view)
		local row = { root = ui.find(view, "buff_row") }
		for _, name in ipairs({ "buff_track", "buff_fill", "buff_icon", "buff_name", "buff_time" }) do
			row[name] = ui.find(view, name)
		end
		ui.visible(row.root, false)
		rows[index] = row
	end
	return rows
end
local you_rows = make_rows(you_host, MAX_YOU)
local target_rows = make_rows(target_host, MAX_TARGET)

local you_list, target_list, icon_list = {}, {}, {}
local refresh_lists, set_warn -- below

-- right-click a buff (row or icon): pin it as a row, stop warning about it, or hide it
local function buff_menu(anchor, entry)
	if not entry or entry.hostile then
		return -- debuffs on you always show
	end
	local name = entry.effect.name or ""
	if name == "" then
		return
	end
	ui.menu.clear(anchor)
	ui.menu.add(anchor, "Always show as a row", pinned[name] == true, function()
		pinned[name] = not pinned[name] or nil
		write_set("NdguiWatchPinned", pinned)
		refresh_lists(ui.time())
	end)
	ui.menu.add(anchor, "Don't warn about this buff", quiet[name] == true, function()
		quiet[name] = not quiet[name] or nil
		write_set("NdguiWatchQuiet", quiet)
		refresh_lists(ui.time())
	end)
	ui.menu.add(anchor, "Hide this buff", false, function()
		hidden[name], pinned[name] = true, nil
		write_set("NdguiWatchHidden", hidden)
		write_set("NdguiWatchPinned", pinned)
		refresh_lists(ui.time())
	end)
	ui.menu.show(anchor)
end
for _, row in ipairs(you_rows) do
	ui.on_pointer_release(row.root, "right", function() buff_menu(row.root, row.entry) end)
end

-- icon strip: ICON_LINES lines of up to ICONS_PER_LINE icons, as many per line as the width allows
local icon_lines, icon_cells = {}, {}
for line = 1, ICON_LINES do
	local view = ui.load("icon_line.xml")
	ui.add(icons_host, view)
	icon_lines[line] = ui.find(view, "icon_line")
	ui.visible(icon_lines[line], false)
	for column = 1, ICONS_PER_LINE do
		local cell_view = ui.load("icon_cell.xml")
		ui.add(icon_lines[line], cell_view)
		local cell = { root = ui.find(cell_view, "icon_cell"), slot = ui.find(cell_view, "icon_slot"),
			line = line, column = column }
		ui.opacity(cell.slot, ICON_OPACITY)
		ui.visible(cell.root, false)
		ui.on_pointer_release(cell.root, "right", function() buff_menu(cell.root, cell.entry) end)
		icon_cells[#icon_cells + 1] = cell
	end
end

local function per_line(inner)
	return math.max(1, math.min(ICONS_PER_LINE, inner // ICON_STEP))
end
local function icon_line_count(inner)
	return math.min(ICON_LINES, math.ceil(#icon_list / per_line(inner)))
end

local function caster_text(effect)
	if effect.caster == nil then
		return ""
	end
	return (self_id ~= nil and effect.caster == self_id) and "Cast by you" or "Cast by someone else"
end

local function icon_tooltip(effect, left)
	local nl = string.char(10)
	local tip = effect.name or ""
	local clock = Watch.clock(left)
	if clock ~= "" then
		tip = tip .. "  (" .. clock .. " left)"
	end
	local who = caster_text(effect)
	if who ~= "" then
		tip = tip .. nl .. who
	end
	if effect.description and effect.description ~= "" then
		tip = tip .. nl .. effect.description
	end
	return tip .. nl .. "Right-click: always show as a row / hide"
end

local function render_icons(inner, now)
	local per = per_line(inner)
	local lines = icon_line_count(inner)
	for line = 1, ICON_LINES do
		ui.visible(icon_lines[line], line <= lines)
	end
	for _, cell in ipairs(icon_cells) do
		local entry = nil
		if cell.column <= per and cell.line <= lines then
			entry = icon_list[(cell.line - 1) * per + cell.column]
		end
		ui.visible(cell.root, entry ~= nil)
		cell.entry = entry
		if entry then
			local effect = entry.effect
			if cell.ref ~= effect.reference then
				cell.ref = effect.reference
				ui.icon(cell.slot, effect.icon or 0)
				ui.content(cell.slot, (effect.icon or 0) ~= 0)
			end
			local tip = icon_tooltip(effect, Watch.left(effect, you.sampled, now))
			if cell.tip ~= tip then
				cell.tip = tip
				ui.tooltip(cell.root, tip)
			end
		else
			cell.ref = nil
		end
	end
end

local function fill_color(entry, left, mine)
	if entry.hostile then
		return HOSTILE
	end
	if mine then
		return left <= Watch.EXPIRING and RED or MINE
	end
	if left <= Watch.EXPIRING then
		return RED
	elseif entry.expiring or left <= 60 then
		return AMBER
	end
	return STEEL
end

local function show_row(row, entry, sampled, now, inner, mine)
	ui.visible(row.root, entry ~= nil)
	row.entry = entry
	if not entry then
		row.ref = nil
		return
	end
	local effect = entry.effect
	local left = Watch.left(effect, sampled, now)
	local fraction = Watch.fraction(effect, left)
	ui.size(row.root, inner, ROW_H - 2)
	ui.size(row.buff_track, inner, ROW_H - 2)
	ui.size(row.buff_fill, math.max(1, math.floor(inner * fraction + 0.5)), ROW_H - 2)
	ui.graphic_tint(row.buff_fill, fill_color(entry, left, mine))
	local time_w = 44
	ui.size(row.buff_name, math.max(20, inner - 20 - 5 - time_w - 4), ROW_H - 2)
	ui.size(row.buff_time, time_w, ROW_H - 2)
	if row.ref ~= effect.reference then
		row.ref = effect.reference
		ui.icon(row.buff_icon, effect.icon or 0)
		ui.content(row.buff_icon, (effect.icon or 0) ~= 0)
		ui.text(row.buff_name, effect.name or "")
		ui.text_color(row.buff_name, entry.hostile and HOSTILE_TEXT or TEXT)
		local tip = effect.name or ""
		local who = caster_text(effect)
		if who ~= "" then
			tip = tip .. string.char(10) .. who
		end
		if effect.description and effect.description ~= "" then
			tip = tip .. string.char(10) .. effect.description
		end
		if not entry.hostile and not mine then
			tip = tip .. string.char(10) .. "Right-click: always show as a row / hide"
		end
		ui.tooltip(row.root, tip)
	end
	-- the last ten seconds blink
	local blink = left < 10 and left ~= math.huge and (now // 500) % 2 == 0
	ui.text(row.buff_time, Watch.clock(left))
	ui.text_color(row.buff_time, blink and "#FFD84A" or TEXT)
end

local buff_frame
local function inner_width()
	return buff_w - Window.CONTENT_SIDES - BORDERS
end
local function buffs_height()
	local lines = icon_line_count(inner_width())
	local h = HEAD_H + math.min(#you_list, MAX_YOU) * ROW_H + lines * ICON_STEP + (lines > 0 and 2 or 0)
	if #you_list == 0 and lines == 0 then h = HEAD_H + EMPTY_H end
	h = h + GAP + HEAD_H
	h = h + (#target_list > 0 and math.min(#target_list, MAX_TARGET) * ROW_H or EMPTY_H)
	return TITLE_ENDS + BORDERS + h + 4
end

local function render_buffs(now)
	local inner = inner_width()
	for index, row in ipairs(you_rows) do
		show_row(row, you_list[index], you.sampled, now, inner, false)
	end
	render_icons(inner, now)
	for index, row in ipairs(target_rows) do
		show_row(row, target_list[index], target.sampled, now, inner, true)
	end
end

local function buffs_layout(window, width)
	buff_w = math.max(BUFF_MIN_W, math.min(BUFF_MAX_W, math.floor(width or buff_w)))
	local inner = buff_w - Window.CONTENT_SIDES - BORDERS
	ui.size(you_head, inner, HEAD_H)
	ui.size(target_head, inner, HEAD_H)
	ui.size(you_empty, inner, EMPTY_H)
	ui.size(target_empty, inner, EMPTY_H)
	ui.visible(you_empty, #you_list == 0 and #icon_list == 0)
	ui.visible(target_empty, #target_list == 0)
	local height = buffs_height()
	ui.limits(window.root, BUFF_MIN_W, height, BUFF_MAX_W, height)
	ui.request_size(window.root, buff_w, height)
	window:fit_title(buff_w, true)
	window:fit_content(buff_w, height)
	render_buffs(ui.time())
end

buff_frame = Window.create({
	template = "library://notum.ndgui-lib/window.xml",
	title = "Buff Watch", content = buffs, width = buff_w, height = 200,
	horizontal = "end", vertical = "center", layout = buffs_layout,
	menu = {
		{ label = "Alerts banner", checked = alerts_on, invoke = function()
			alerts_on = not alerts_on
			set_pref("NdguiWatchAlerts", tostring(alerts_on), "bool")
			pcall(ui.menu.checked, buff_frame.icon, 1, alerts_on)
		end },
		{ label = "Show every buff as a row", checked = all_rows, invoke = function()
			all_rows = not all_rows
			set_pref("NdguiWatchAllRows", tostring(all_rows), "bool")
			pcall(ui.menu.checked, buff_frame.icon, 2, all_rows)
			refresh_lists(ui.time())
		end },
		{ label = "Warn under 30 s", checked = warn == 30, invoke = function() set_warn(30) end },
		{ label = "Warn under 1 min", checked = warn == 60, invoke = function() set_warn(60) end },
		{ label = "Warn under 5 min", checked = warn == 300, invoke = function() set_warn(300) end },
		{ label = "Show hidden buffs again, warn about all", checked = false, invoke = function()
			hidden, quiet = {}, {}
			write_set("NdguiWatchHidden", hidden)
			write_set("NdguiWatchQuiet", quiet)
			refresh_lists(ui.time())
		end },
	},
})

-- menu entries 3-5: the warning time (a buff becomes an amber row when it has less left)
function set_warn(seconds)
	warn = seconds
	set_pref("NdguiWatchWarn", tostring(seconds), "int")
	for index, choice in ipairs(Watch.WARN_CHOICES) do
		pcall(ui.menu.checked, buff_frame.icon, 2 + index, choice == seconds)
	end
	refresh_lists(ui.time())
end
ui.add(root, buff_frame.root)
ui.register_view(buff_frame.root, "buffs")

local function relayout_buffs()
	local before = buff_frame.last_height
	local height = buffs_height()
	if before ~= height then
		buff_frame.last_height = height
		buff_frame:resize(buff_w, height)
		set_pref("NdguiWatchWidth", tostring(buff_w), "int")
	else
		render_buffs(ui.time())
	end
end

function refresh_lists(now)
	you_list, icon_list = Watch.split_you(you.effects, you.sampled, now, {
		warn = warn, pinned = pinned, hidden = hidden, quiet = quiet, all_rows = all_rows, max_rows = MAX_YOU,
	})
	local on_self = target.name ~= nil and (target.is_self or (self_id ~= nil and target.id == self_id))
	-- targeting yourself: "On you" already lists all of it
	target_list = on_self and {} or Watch.on_target(target.effects, self_id, target.sampled, now)
	if on_self then
		ui.text(target_head, "ON YOURSELF")
		ui.text(target_empty, "Same as above.")
	elseif target.name then
		ui.text(target_head, "ON " .. string.upper(target.name))
		ui.text(target_empty, "Nothing of yours on it.")
	else
		ui.text(target_head, "ON TARGET")
		ui.text(target_empty, "No target.")
	end
	relayout_buffs()
end

-- =========================================================================================
-- Team Buffs window
-- =========================================================================================
local grid = ui.load("team.xml")
local function tfind(name) return ui.find(grid, name) end
local head_host, rows_host = tfind("team_head"), tfind("team_rows")
local team_empty, team_hint = tfind("team_empty"), tfind("team_hint")
local head_pad = tfind("team_head_pad") -- keeps the icons over their columns
local heads = {}
for index = 1, Watch.MAX_COLUMNS do
	local view = ui.load("team_head.xml")
	ui.add(head_host, view)
	heads[index] = ui.find(view, "head_icon")
	ui.visible(heads[index], false)
end
local members_rows = {}
for index = 1, MAX_MEMBERS do
	local view = ui.load("team_row.xml")
	ui.add(rows_host, view)
	local row = {
		root = ui.find(view, "member_row"), back = ui.find(view, "member_back"),
		name = ui.find(view, "member_name"), hit = ui.find(view, "member_hit"), cells = {},
	}
	local cells_host = ui.find(view, "member_cells")
	for column = 1, Watch.MAX_COLUMNS do
		local cell_view = ui.load("team_cell.xml")
		ui.add(cells_host, cell_view)
		row.cells[column] = { root = ui.find(cell_view, "cell"), back = ui.find(cell_view, "cell_back"),
			text = ui.find(cell_view, "cell_text") }
		ui.visible(row.cells[column].root, false)
	end
	ui.visible(row.root, false)
	members_rows[index] = row
end
local current_grid = { columns = {}, rows = {} }
local team_frame

local function team_size()
	local columns = math.max(1, #current_grid.columns)
	local width = Window.CONTENT_SIDES + BORDERS + NAME_W + columns * CELL_W + 4
	local shown_rows = math.min(#current_grid.rows, MAX_MEMBERS)
	local height = TITLE_ENDS + BORDERS + 28 + shown_rows * (CELL_H + 2) + 4 + 14 + 4
	if shown_rows == 0 then height = TITLE_ENDS + BORDERS + EMPTY_H + 4 + 14 + 4 end
	return math.max(Window.MINIMUM_WIDTH, math.max(240, width)), height
end

local function cell_look(effect, sampled, now)
	if effect == false then
		return "#1A222B", "?", MUTED
	elseif effect == nil then
		return "#5A1A1A", "", TEXT
	end
	local left = Watch.left(effect, sampled, now)
	if left == math.huge then
		return "#24452E", "on", "#9CD69C"
	end
	local look = left <= Watch.EXPIRING and "#6A2A1A" or left <= 120 and "#5A4A18" or "#24452E"
	local text = left >= 3600 and string.format("%dh", left // 3600) or left >= 60 and string.format("%dm", left // 60)
		or Watch.clock(left)
	return look, text, TEXT
end

local function render_team(now)
	local columns = #current_grid.columns
	for index, row in ipairs(members_rows) do
		local data = current_grid.rows[index]
		ui.visible(row.root, data ~= nil)
		if data then
			for column, cell in ipairs(row.cells) do
				ui.visible(cell.root, column <= columns)
				if column <= columns then
					local back, text, color = cell_look(data.cells[column], team.sampled, now)
					ui.fill_color(cell.back, back)
					ui.text(cell.text, text)
					ui.text_color(cell.text, color)
				end
			end
		end
	end
end

local function team_layout(window)
	local width, height = team_size()
	ui.limits(window.root, width, height, width, height)
	ui.request_size(window.root, width, height)
	local inner = width - Window.CONTENT_SIDES - BORDERS
	ui.size(head_pad, NAME_W, 24)
	ui.size(team_empty, inner, EMPTY_H)
	ui.size(team_hint, inner, 14)
	for _, row in ipairs(members_rows) do
		ui.size(row.root, inner, CELL_H)
		ui.size(row.back, inner, CELL_H)
		ui.size(row.hit, inner, CELL_H)
		ui.size(row.name, NAME_W - 4, CELL_H)
	end
	window:fit_title(width, true)
	window:fit_content(width, height)
	render_team(ui.time())
end

team_frame = Window.create({
	template = "library://notum.ndgui-lib/window.xml",
	title = "Team Buffs", content = grid, width = 360, height = 160,
	horizontal = "center", vertical = "center", layout = team_layout,
})
ui.add(root, team_frame.root)
ui.register_view(team_frame.root, "team_buffs")

local function refresh_team()
	current_grid = Watch.team_grid(team.members, team.collections)
	ui.visible(team_empty, #current_grid.rows == 0)
	ui.text(team_empty, team.in_team and "Waiting for the team's buffs..." or "Not in a team.")
	for index, head in ipairs(heads) do
		local column = current_grid.columns[index]
		ui.visible(head, column ~= nil)
		if column then
			ui.icon(head, column.icon or 0)
			ui.content(head, (column.icon or 0) ~= 0)
			ui.tooltip(head, column.name .. "  (" .. column.count .. " of " .. #current_grid.rows .. ")")
		end
	end
	for index, row in ipairs(members_rows) do
		local data = current_grid.rows[index]
		if data then
			local member = data.member
			local label = member.name or "?"
			if data.missing > 0 then
				label = label .. "  -" .. data.missing
			end
			ui.text(row.name, label)
			ui.text_color(row.name, data.stale and MUTED or member.is_self and "#4FB3E8" or TEXT)
			ui.fill_color(row.back, index % 2 == 0 and "#600A1016" or "#900A1016")
			ui.tooltip(row.hit, (member.name or "") .. (data.missing > 0
				and string.format(": missing %d of %d", data.missing, #current_grid.columns) or ": has them all"))
			if row.reference ~= member.reference and not ui.in_combat() then
				row.reference = member.reference
				local ok, action = pcall(game.targeting.prepare_select, member.reference)
				pcall(ui.actions.bind, row.hit, ok and action or 0, "left", "press")
			end
		end
	end
	local width, height = team_size()
	team_frame:resize(width, height)
end

-- =========================================================================================
-- Alerts banner
-- =========================================================================================
local banner = ui.load("alert.xml")
local alert = {
	root = ui.find(banner, "alert"), back = ui.find(banner, "alert_back"), edge = ui.find(banner, "alert_edge"),
	icon = ui.find(banner, "alert_icon"), text = ui.find(banner, "alert_text"), shadow = ui.find(banner, "alert_shadow"),
}
ui.add(root, alert.root)
-- under the compass, centred (children of the addon root are aligned, not placed)
local ALERT_TOP = 170
ui.align(alert.root, "center", "start")
ui.borders(alert.root, 0, ALERT_TOP, 0, 0)
local LEVEL = { danger = { "#C0381A1A", "#E0503C" }, warn = { "#C0182A40", "#4FB3E8" }, info = { "#C0302810", "#E0C040" } }
local shown_alert

local function render_alert(now)
	local list = alerts_on and Watch.alerts({
		health = vitals.health, max_health = vitals.max_health, nano = vitals.nano, max_nano = vitals.max_nano,
		effects = you.effects, sampled = you.sampled, debuffs = debuff_hits, quiet = quiet,
	}, now) or {}
	local top = list[1]
	ui.visible(alert.root, top ~= nil)
	if not top then
		shown_alert = nil
		return
	end
	local look = LEVEL[top.level] or LEVEL.info
	local w = math.max(220, #top.text * 10 + 60)
	ui.size(alert.root, w, 34)
	ui.size(alert.back, w, 34)
	ui.size(alert.edge, w, 2)
	ui.fill_color(alert.back, look[1])
	-- danger pulses
	local pulse = top.level == "danger" and (now // 400) % 2 == 0
	ui.fill_color(alert.edge, pulse and "#FFFFFF" or look[2])
	ui.text(alert.text, top.text)
	ui.text(alert.shadow, top.text)
	ui.text_color(alert.text, top.level == "danger" and (pulse and "#FFD0C0" or "#FF8A70") or "#FFFFFF")
	if shown_alert ~= top.key then
		shown_alert = top.key
		ui.visible(alert.icon, top.icon ~= nil)
		if top.icon then
			ui.icon(alert.icon, top.icon)
			ui.content(alert.icon, true)
		end
	end
end

-- =========================================================================================
-- data
-- =========================================================================================
local function collection_for(update, reference)
	for _, collection in ipairs(update.data or {}) do
		if reference == nil or collection.subject == reference then
			return collection
		end
	end
end

game.effects.subscribe("self", function(update)
	local collection = collection_for(update)
	you.effects = collection and collection.effects or {}
	you.sampled = update.sampled_at_ms or ui.time()
	local fresh
	fresh, debuff_refs = Watch.new_debuffs(debuff_refs, you.effects)
	if update.reset then
		fresh = {}
	end
	local now = ui.time()
	for _, effect in ipairs(fresh) do
		debuff_hits[#debuff_hits + 1] = { name = effect.name or "Debuff", at = now }
	end
	while #debuff_hits > 4 do
		table.remove(debuff_hits, 1)
	end
	refresh_lists(now)
	-- the update loop only runs while a view of this package is visible: data drives the banner too
	render_alert(now)
end)

game.effects.subscribe("target", function(update)
	local collection = collection_for(update)
	target.effects = collection and collection.effects or {}
	target.sampled = update.sampled_at_ms or ui.time()
	refresh_lists(ui.time())
end)

game.character.subscribe("self", "", function(_, character)
	if character then
		if self_id ~= character.id then
			self_id = character.id
			refresh_lists(ui.time()) -- the target section depends on who you are
		end
		vitals.health, vitals.max_health = character.health, character.max_health
		vitals.nano, vitals.max_nano = character.nano, character.max_nano
		render_alert(ui.time())
	end
end)

game.character.subscribe("target", "", function(_, character)
	target.name = character and character.name or nil
	target.id = character and character.id or nil
	target.is_self = character and character.is_self == true or false
	refresh_lists(ui.time())
end)

game.team.subscribe(function(update)
	local state = update.data or {}
	team.in_team = state.in_team == true
	team.members = {}
	for _, member in ipairs(state.members or {}) do
		local character = member.character
		if character and member.own_team ~= false and #team.members < MAX_MEMBERS then
			team.members[#team.members + 1] = {
				name = character.name, reference = character.reference,
				profession = character.profession, is_self = character.is_self,
			}
		end
	end
	refresh_team()
end)

game.effects.subscribe("team", function(update)
	team.collections = {}
	for _, collection in ipairs(update.data or {}) do
		team.collections[collection.subject] = collection
	end
	team.sampled = update.sampled_at_ms or ui.time()
	refresh_team()
end)

-- timers tick between native samples (about 4 times a second is plenty)
local next_tick = 0
ui.on_update(function(now)
	now = now or ui.time()
	if now < next_tick then
		return
	end
	next_tick = now + 250
	refresh_lists(now) -- buffs move from the icon strip to the rows as they reach the warning time
	render_team(now)
	render_alert(now)
end)

refresh_lists(ui.time())
refresh_team()
