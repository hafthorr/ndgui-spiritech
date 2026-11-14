-- ndGUI Team window (prk.team), hand-made from the stock Team package.
-- Each member is an ndGUI unit frame (ndgui-lib unit.lua): profession portrait, name + level, exact HP
-- with a draining ghost of damage just taken, low-HP pulse, nano, profession / side, distance, and
-- floating damage / healing numbers. Leader = green name and stripe; absent members are greyed.
-- Kept from stock: left-click a member to target them, right-click for Leave / Kick / Make leader,
-- the NCU toggle with each member's buff strip, Leave and Recruit.
local Window = ui.require("core.window")
local Strip = ui.require("ncu.strip")
local Effects = ui.require("effects.presentation")
local Unit = ui.require("notum.ndgui-lib/unit")
local content = ui.load("content.xml")
local host = ui.find(content, "team_rows")
local toggle = ui.find(content, "ncu_toggle")
local compact_toggle = ui.find(content, "compact_toggle")
local invite = ui.find(content, "invite_button")
local leave = ui.find(content, "leave_button")
local rows, members, nanos = {}, {}, {}
local shows_ncu = false
local frame, state
local UNREPORTED_TEAM_LEVEL = 1
local ROW_SIDES = 6 -- row.xml borders 3 + 3
local HEADER_H = 33 + 3 + 21 + 30 -- title, borders, team info, button row
local BUTTON_WIDTH, BUTTON_HEIGHT, BUTTON_ROW_BORDERS, NCU_BUTTON_WITH_GAPS = 80, 24, 6, 64 + 74
local COMPACT_SCALE = 0.9
local LEADER, PRESENT, ABSENT, ACCENT = "#11EEAA", "#E6EEF5", "#888888", "#3d6f9a"
local sides = { [0] = "Neutral", "Clan", "Omni-Tek", "Monster", "Advisors", "Guardians", "Game Masters", "Mixed" }

-- Full Character per member (positions for distance); the roster summary carries the vitals.
local watched = {} -- reference -> { subscription, character }
local unit_width = 260
-- Compact: name, level and health bar only, a little smaller (remembered with the window)
local compact = false
if ui.preference and ui.preference.read then
	local ok, saved = pcall(ui.preference.read, "NdguiTeamCompact")
	compact = ok and saved == "true"
end
local function scale()
	return compact and COMPACT_SCALE or 1
end

local function fit_strips(width)
	local extra = 0
	for index, row in ipairs(rows) do
		local member = members[index]
		local effects = member and nanos[member.character.reference] or {}
		local height = row.strip:show(effects or {}, width - 19, shows_ncu and member ~= nil)
		extra = extra + (height > 0 and height + 2 or 0)
	end
	return extra
end

local function rows_height()
	local total = 0
	for index, row in ipairs(rows) do
		if members[index] then
			total = total + row.unit:height()
		end
	end
	return total
end

local laid_compact
local show_rows -- defined below; re-shows members after a compact switch
local DOCKED_COMPACT_W, DOCKED_NCU_W, DOCKED_GAP = 56, 40, 3
local compact_button_w, ncu_button_w -- floating sizes, from content.xml
local function layout(window, width, height)
	local docked = window.docking and window.docking.docked
	if docked then
		width = window.docking.width or width -- the column, not the saved floating width
	end
	width = math.max(docked and 1 or Window.MINIMUM_WIDTH, math.min(640, width))
	local w = width - Window.CONTENT_SIDES - ROW_SIDES
	if w ~= unit_width or compact ~= laid_compact then
		unit_width, laid_compact = w, compact
		for _, row in ipairs(rows) do
			row.unit:layout(unit_width, scale(), compact)
		end
	end
	local button_width, invite_width
	if docked then
		-- narrow Compact / NCU; Leave and Recruit share the rest (Recruit alone when not in a team)
		ui.limits(compact_toggle, DOCKED_COMPACT_W, BUTTON_HEIGHT, DOCKED_COMPACT_W, BUTTON_HEIGHT)
		ui.limits(toggle, DOCKED_NCU_W, BUTTON_HEIGHT, DOCKED_NCU_W, BUTTON_HEIGHT)
		local room = width - BUTTON_ROW_BORDERS - DOCKED_COMPACT_W - DOCKED_NCU_W - DOCKED_GAP * 3
		if ui.requested_visible(leave) then
			button_width = math.floor(room / 2)
			invite_width = room - button_width
		else
			button_width, invite_width = 1, room
		end
	else
		ui.limits(compact_toggle, compact_button_w, BUTTON_HEIGHT, compact_button_w, BUTTON_HEIGHT)
		ui.limits(toggle, ncu_button_w, BUTTON_HEIGHT, ncu_button_w, BUTTON_HEIGHT)
		local fixed = Window.CONTENT_SIDES + BUTTON_ROW_BORDERS + NCU_BUTTON_WITH_GAPS
		button_width = math.min(BUTTON_WIDTH, (width - fixed) / 2)
		invite_width = button_width
	end
	ui.size(leave, button_width, BUTTON_HEIGHT)
	ui.size(invite, invite_width, BUTTON_HEIGHT)
	local minimum_height = HEADER_H + rows_height() + fit_strips(width)
	if docked then
		-- the docked page follows its content (no empty floating height below the members)
		window.content_driven = true
		window:fit_content(width, minimum_height)
		return
	end
	window.content_driven = nil
	height = math.max(minimum_height, math.min(640, height))
	ui.limits(window.root, Window.MINIMUM_WIDTH, minimum_height, 640, math.max(640, minimum_height))
	ui.request_size(window.root, width, height)
	window:fit_title(width, true)
	window:fit_content(width, height)
end

for index = 1, 6 do
	local root = ui.load("row.xml")
	ui.add(host, root)
	local row = { root = root, unit_host = ui.find(root, "unit_host"), ncu_strip = ui.find(root, "ncu_strip") }
	row.unit = Unit.new(row.unit_host)
	row.unit:layout(unit_width, scale(), compact)
	local v = row.unit.v
	-- every visible piece of the row takes the click (the innermost view gets the press)
	row.inputs = { root, v.frame, v.plate, v.portrait, v.portrait_icon, v.portrait_level, v.body, v.name, v.level,
		v.hp, v.hp_text, v.np, v.row_info, v.info, v.distance }
	row.strip = Strip.create(row.ncu_strip, {
		template = "team_ncu_slot.xml", cell_width = 16, cell_height = 16, lines = 2,
	})
	ui.visible(root, false)
	rows[index] = row
end

compact_button_w, ncu_button_w = 68, 52 -- content.xml
frame = Window.create({
	template = "library://notum.ndgui-lib/window.xml",
	title = "Team", content = content, width = 300, height = 260,
	horizontal = "center", x = 10, y = 174, layout = layout,
})
ui.root(frame.root)
ui.selected(compact_toggle, compact)
ui.on_click(compact_toggle, function()
	compact = not compact
	ui.selected(compact_toggle, compact)
	if ui.preference and ui.preference.write then
		pcall(ui.preference.write, "NdguiTeamCompact", tostring(compact), "bool")
	end
	for _, row in ipairs(rows) do
		row.unit:layout(unit_width, scale(), compact)
	end
	laid_compact = compact
	show_rows()
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end)
ui.on_click(toggle, function()
	shows_ncu = not shows_ncu
	ui.selected(toggle, shows_ncu)
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end)

-- New members' names blink for a moment (stock behaviour), on the shared unit-frame ticker.
local function animate_names(now)
	local active = false
	for index, row in ipairs(rows) do
		local member = members[index]
		local flashing = member and member.flash_until_ms and member.flash_until_ms > now
		active = active or flashing
		local hidden = flashing and math.floor(now / 500) % 2 == 1
		ui.opacity(row.unit.v.name, hidden and 0 or 1)
	end
	return active
end
Unit.set_extra_tick(animate_names)

local function row_menu(row, member, context)
	if row.menu_context == context then return end
	row.menu_context = context
	ui.menu.clear(row.root)
	if not member then return end
	local character = member.character
	if character.is_self then
		ui.menu.prepared_action(row.root, "Leave", game.team.prepare_leave())
	elseif state.can_invite then
		ui.menu.prepared_action(row.root, "Kick " .. (character.name or "this player"),
			game.team.prepare_kick(character.reference))
		ui.menu.prepared_action(row.root, "Make " .. (character.name or "this player") .. " leader",
			game.team.prepare_leader(character.reference))
	end
end

for _, row in ipairs(rows) do
	for _, view in ipairs(row.inputs) do
		ui.on_pointer_release(view, "right", function() ui.menu.show(row.root) end)
	end
end

-- Summary vitals + the full Character's position (for distance), as one read-only view.
local function merged(summary)
	local full = watched[summary.reference] and watched[summary.reference].character
	if not full then
		return summary
	end
	return setmetatable({ x = full.x, y = full.y, z = full.z }, { __index = summary })
end

function show_rows()
	for index, row in ipairs(rows) do
		local member = members[index]
		ui.visible(row.root, member ~= nil)
		if member then
			local character = member.character
			local name = character.name or "?"
			if member.ignored then name = name .. " [ i ]" end
			row.unit:show({
				name = name, character = merged(character), player = true, header = character.name or "",
				name_color = member.leader and LEADER or character.present and PRESENT or ABSENT,
				accent = member.leader and LEADER or ACCENT, dim = not character.present,
			})
		else
			row.unit:hide()
		end
	end
end

-- Keep one character subscription per member (budget: 16 per package) for positions.
local function watch_members()
	local wanted = {}
	for _, member in ipairs(members) do
		local reference = member.character.reference
		if reference and not member.character.is_self then
			wanted[reference] = true
			if not watched[reference] and game.character and game.character.subscribe then
				local entry = {}
				watched[reference] = entry
				local ok, subscription = pcall(game.character.subscribe, reference, "", function(_, character)
					entry.character = type(character) == "table" and character or nil
					show_rows()
				end)
				entry.subscription = ok and subscription or nil
			end
		end
	end
	for reference, entry in pairs(watched) do
		if not wanted[reference] then
			if entry.subscription and game.character.unsubscribe then
				pcall(game.character.unsubscribe, entry.subscription)
			end
			watched[reference] = nil
		end
	end
end

local function present(update)
	state = update.data or { in_team = false, can_invite = false, members = {} }
	members = {}
	local context = tostring(state.context) .. ":" .. tostring(state.can_invite)
	for _, member in ipairs(state.members) do
		context = context .. ":" .. member.character.reference .. ":" .. tostring(member.leader)
			.. ":" .. (member.character.name or "")
		if member.own_team and #members < #rows then members[#members + 1] = member end
	end
	ui.text(ui.find(content, "team_info"), state.in_team
		and "Team level: " .. UNREPORTED_TEAM_LEVEL .. "  Team side: " .. (sides[state.side] or "Unknown") or "No team")
	ui.visible(leave, state.in_team)
	ui.enabled(invite, state.can_invite)
	ui.actions.bind(leave, game.team.prepare_leave(), "left", "release")
	ui.actions.bind(invite, game.team.prepare_invite("target"), "left", "release")
	for index, row in ipairs(rows) do
		local member = members[index]
		local character = member and member.character
		local subject = character and character.reference
		if row.subject ~= subject then
			ui.cancel_input(row.root)
			row.subject = subject
		end
		row_menu(row, member, context .. ":" .. tostring(subject))
		local selection = subject and game.targeting.prepare_select(subject) or 0
		for _, view in ipairs(row.inputs) do
			ui.actions.bind(view, selection, "left", "press")
		end
		ui.tooltip(row.root, character and character.name or "")
	end
	watch_members()
	show_rows()
	if animate_names(ui.time()) then Unit.wake() end
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end

game.team.subscribe(present)
game.targeting.subscribe(function()
	ui.actions.bind(invite, game.team.prepare_invite("target"), "left", "release")
end)
game.effects.subscribe("team", function(update)
	nanos = Effects.collections(update)
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end)
-- your own position, for distances
if game.character and game.character.subscribe then
	pcall(game.character.subscribe, "self", "", function(_, character)
		Unit.set_self(character)
		show_rows()
	end)
end
-- floating damage / healing numbers on members
Unit.watch_combat()
