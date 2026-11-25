-- Dovvetech prk.control-center provider: the stock Control Center contract and commands,
-- presented as one slim ndGUI strip on the bottom edge instead of two corner wings, plus the optional
-- top-right minibar and right-side docking column (both toggled in Options > Interface & HUD).
local root = ui.load("root.xml")
local left = ui.load("left.xml")
local right = ui.load("right.xml")
ui.add(ui.find(root, "left_wing_dock"), left)
ui.add(ui.find(root, "right_wing_dock"), right)
ui.root(root)
local strip = ui.find(root, "ndgui_strip")
local function fit_strip()
	local width = ui.parent_width(root)
	if width and width > 0 then
		ui.size(strip, width, 30)
	end
end
fit_strip()

local ncu = ui.find(left, "ncu")
local credits = ui.find(left, "credits")
local aggdef = ui.find(right, "aggdef")
local right_target = ui.find(right, "right_target")
local commands = {}
local latest_state = nil
local menu_state = {}
local top_menus = {}
local addon_windows = {}
-- Perk Actions / Attack Actions: submenus filled from control_center_apply (client 0.3)
local dynamic_menus = {}
for _, key in ipairs({ "perks", "attacks" }) do
	dynamic_menus[key] = { anchor = ui.load("menu_anchor.xml"), entries = {} }
	ui.add(root, dynamic_menus[key].anchor)
end

game.control_center.bind_aggdef(aggdef)

local AGGDEF_MIN = -100
local AGGDEF_MAX = 100

local function aggdef_progress(value)
	return (value - AGGDEF_MIN) / (AGGDEF_MAX - AGGDEF_MIN)
end

local function aggdef_value(progress)
	return math.floor(AGGDEF_MIN + progress * (AGGDEF_MAX - AGGDEF_MIN) + 0.5)
end

local function aggdef_tooltip(value)
	if value > 0 then
		return "Aggressive: " .. tostring(value) .. "%"
	elseif value < 0 then
		return "Defensive: " .. tostring(-value) .. "%"
	end
	return "Balanced (0%)"
end

local function show_aggdef(value)
	ui.tooltip(aggdef, aggdef_tooltip(value))
end

ui.on_value_changed(aggdef, function(progress)
	show_aggdef(aggdef_value(progress))
end)

local windows = {
	inventory = ui.destinations.require("prk.inventory"),
	wear = ui.destinations.require("prk.wear"),
	ncu = ui.destinations.require("prk.ncu"),
	nano = ui.destinations.require("prk.nano-programs"),
	missions = ui.destinations.require("prk.missions"),
	friends = ui.destinations.require("prk.friends"),
	aggdef = ui.destinations.require("prk.aggdef"),
	actions = ui.destinations.require("prk.actions"),
	stats = ui.destinations.require("prk.stats"),
	health = ui.destinations.require("prk.health-bar"),
	nano_bar = ui.destinations.require("prk.nano-bar"),
	experience = ui.destinations.require("prk.experience-bar"),
	alien_experience = ui.destinations.require("prk.alien-experience-bar"),
	chat = ui.destinations.require("prk.chat.default"),
	combat_chat = ui.destinations.require("prk.chat.combat"),
	tradeskills = ui.destinations.require("prk.tradeskills"),
	chat_config = ui.destinations.require("prk.chat-config"),
	skills = ui.destinations.require("prk.skills"),
	perks = ui.destinations.require("prk.perks"),
	planet_map = ui.destinations.require("prk.planet-map"),
	playfield_map = ui.destinations.require("prk.playfield-map"),
	team = ui.destinations.require("prk.team"),
	raid = ui.destinations.require("prk.raid"),
	team_search = ui.destinations.require("prk.team-search"),
	pets = ui.destinations.require("prk.pets"),
	faction = ui.destinations.require("prk.faction"),
	options = ui.destinations.require("prk.options"),
}

local function window_entry(label, window)
	return { label = label, window = window }
end

local function command_entry(key, label)
	return { key = key, label = label }
end

local function menu_entry(label, children)
	return { label = label, children = children }
end

local function command_list(values)
	local result = {}
	for _, value in ipairs(values) do
		result[#result + 1] = command_entry(value[1], value[2])
	end
	return result
end

local actions_menu = {
	menu_entry("Emotes", {
		menu_entry("Greetings", command_list({
			{ "bow", "Bow" }, { "curt", "Curtsey" }, { "greet", "Greet" }, { "kneel", "Kneel" },
			{ "salute", "Salute" }, { "scared", "Scared" }, { "surprised", "Surprised" },
			{ "surrender", "Surrender" }, { "wave", "Wave" },
		})),
		menu_entry("Gestures", command_list({
			{ "cross", "Cross Arms" }, { "fishsize", "Fish Size" }, { "gloat", "Gloat" },
			{ "italian", "Italian" }, { "nod", "Nod" }, { "nono", "No No" }, { "pray", "Pray" },
			{ "shrug", "Shrug" }, { "speech", "Speech" }, { "thinker", "Thinker" },
		})),
		menu_entry("Approval", command_list({
			{ "applause", "Applause" }, { "blowkiss", "Blow Kiss" }, { "giggle", "Giggle" },
			{ "kisshigh", "Kiss High" }, { "kisslow", "Kiss Low" }, { "laugh-b", "Laugh-b" },
			{ "laugh-s", "Laugh-s" }, { "prostrate", "Prostrate" }, { "swroyal", "Swroyal" },
			{ "thumbs", "Thumbs Up" },
		})),
		menu_entry("Dislike", command_list({
			{ "angry", "Angry" }, { "bulge", "Bulge" }, { "fblock", "Fblock" }, { "flip", "Flip" },
			{ "moon", "Moon" }, { "puke", "Puke" }, { "shake", "Shake" }, { "slap", "Slap" },
			{ "spit", "Spit" },
		})),
		menu_entry("Dancing", command_list({
			{ "ballet", "Ballet" }, { "chicken", "Chicken" }, { "disco", "Disco" },
			{ "flamenco", "Flamenco" }, { "pulp", "Pulp" }, { "rocky", "Rocky" }, { "ymca", "YMCA" },
		})),
		menu_entry("Athletic", command_list({
			{ "backflip", "Backflip" }, { "strong1", "Strong 1" }, { "strong2", "Strong 2" },
			{ "strong3", "Strong 3" }, { "strong4", "Strong 4" },
		})),
		menu_entry("Relaxing", command_list({
			{ "adjust", "Adjust" }, { "drink", "Drink" }, { "eat", "Eat" }, { "itch", "Itch" },
			{ "legshake", "Leg Shake" }, { "lounge", "Lounge" }, { "read", "Read" },
			{ "scratch", "Scratch" },
		})),
		menu_entry("Directions", command_list({
			{ "apachi", "Apachi" }, { "lookout", "Lookout" }, { "pointba", "Point Back" },
			{ "pointfor", "Point Forward" }, { "pointlef", "Point Left" },
			{ "pointrig", "Point Right" }, { "pointup", "Point Up" },
		})),
	}),
	{ label = "Pets", state = "pets", children = {
		window_entry("Pet Info", windows.pets),
		command_entry("pet-attack", "Attack"), command_entry("pet-behind", "Behind"),
		command_entry("pet-follow", "Follow"), command_entry("pet-guard", "Guard"),
		command_entry("pet-heal", "Heal"), command_entry("pet-report", "Report"),
		command_entry("pet-terminate", "Terminate"), command_entry("pet-wait", "Wait"),
	}},
	menu_entry("Camera", command_list({
		{ "camera-first", "First Person" }, { "camera-trail", "Third Person Trail" },
		{ "camera-locked", "Third Person Locked" }, { "camera-rubber", "Third Person Rubber" },
	})),
	menu_entry("Movement", command_list({
		{ "sit", "Sit" }, { "stand", "Stand" }, { "crawl", "Crawl" }, { "walk", "Walk" }, { "run", "Run" },
	})),
	menu_entry("Normal Actions", command_list({ { "invite", "Invite" }, { "quit", "Quit" } })),
	{ label = "Attack Actions", dynamic = "attacks" },
	{ label = "Perk Actions", dynamic = "perks" },
	window_entry("Stats", windows.stats),
	menu_entry("Status Bars", {
		window_entry("Health", windows.health), window_entry("Nano", windows.nano_bar),
		window_entry("Experience", windows.experience), window_entry("Alien Experience", windows.alien_experience),
	}),
	menu_entry("Chat", {
		window_entry("Default Window", windows.chat), window_entry("Combat", windows.combat_chat),
	}),
	window_entry("Tradeskill Kit", windows.tradeskills),
	window_entry("Control Panel", windows.actions),
	menu_entry("Help/Settings", {
		command_entry("help", "Help"), window_entry("Settings", windows.options),
		window_entry("Chat Configuration", windows.chat_config),
	}),
}

local character_menu = {
	window_entry("Skills", windows.skills),
	window_entry("Faction", windows.faction),
	{ label = "Perks", state = "perks_window", window = windows.perks },
	{ label = "Research" },
}

local map_menu = {
	window_entry("Planet Map", windows.planet_map),
	window_entry("Local Map", windows.playfield_map),
}

local shop_menu = {
	{ label = "Item Store" }, { label = "Daily Rewards" }, { label = "Pending Rewards" },
}

local team_menu = {
	window_entry("Team", windows.team), window_entry("Raid", windows.raid), window_entry("Find Team", windows.team_search),
}

local function new_anchor()
	local anchor = ui.load("menu_anchor.xml")
	ui.add(root, anchor)
	return anchor
end

local function populate(anchor, items, path)
	for index, item in ipairs(items) do
		local menu_index
		if item.children then
			local child = new_anchor()
			populate(child, item.children, path .. "." .. tostring(index))
			menu_index = ui.menu.submenu(anchor, item.label, child)
		elseif item.dynamic then
			menu_index = ui.menu.submenu(anchor, item.label, dynamic_menus[item.dynamic].anchor)
			dynamic_menus[item.dynamic].index = menu_index
		elseif item.window then
			menu_index = ui.menu.destination(anchor, item.label, item.window)
		elseif item.key and commands[item.key] then
			menu_index = ui.menu.action(anchor, item.label, "game.control_center.activate", commands[item.key])
		else
			menu_index = ui.menu.label(anchor, item.label)
		end
		if item.state then
			menu_state[item.state .. "_index"] = menu_index
		end
	end
end

local function bind_window(name, window)
	local button = ui.find(root, name)
	ui.bind(button, window)
	ui.action(button, "ui.destinations.toggle", window, "left")
	ui.on_click(button, function()
		ui.visual_selected(button, ui.destinations.is_open(window))
	end)
	return button
end

local window_buttons = {
	{ bind_window("aggdef_info", windows.aggdef), windows.aggdef },
	{ bind_window("inventory", windows.inventory), windows.inventory },
	{ bind_window("wear", windows.wear), windows.wear },
	{ bind_window("ncu_window", windows.ncu), windows.ncu },
	{ bind_window("nano", windows.nano), windows.nano },
	{ bind_window("missions", windows.missions), windows.missions },
	{ bind_window("friends", windows.friends), windows.friends },
}

-- Minibar (Options > Interface & HUD > Show minibar): the stock top-right row of window buttons.
local Column = ui.require("core.hud_column")
local minibar = ui.load("minibar.xml")
ui.size(minibar, Column.WIDTH, Column.TOP)
ui.add(root, minibar)
for _, entry in ipairs({
	{ "wear", windows.wear }, { "actions", windows.actions }, { "missions", windows.missions },
	{ "team", windows.team }, { "playfield_map", windows.playfield_map }, { "friends", windows.friends },
	{ "programs", windows.nano }, { "stats", windows.stats }, { "ncu", windows.ncu },
}) do
	window_buttons[#window_buttons + 1] = { bind_window("minibar_" .. entry[1], entry[2]), entry[2] }
end

-- Right-side docking column (Options > Show rollup panel): windows dragged onto it by their title bar dock
-- here. It runs from under the minibar (when shown) down to the ndGUI strip. Pages are Column.WIDTH wide;
-- the column adds a lane for the scroll bar so a tall stack scrolls without the bar covering the pages.
local SCROLL_LANE = 12
local column = nil
if ui.docking and ui.docking.available() then
	column = { root = ui.load("rollup_panel.xml") }
	column.background = ui.find(column.root, "rollup_background")
	function column:refresh()
		local top = ui.requested_visible(minibar) and Column.TOP or 0
		local height = math.max(0, ui.parent_height(self.root) - top - ui.minimum_height(strip))
		if height == self.height and top == self.top then
			return
		end
		self.height, self.top = height, top
		ui.size(self.root, Column.WIDTH + SCROLL_LANE, height)
		ui.place(self.root, 0, top)
		ui.align(self.root, "end", "start")
	end
	function column:show(shown, opacity)
		ui.visible(self.root, shown)
		ui.opacity(self.background, opacity or 1)
		self:refresh()
	end
	ui.attach(root, column.root, function() column:refresh() end)
	ui.rollup_host(column.root, ui.find(column.root, "rollup_pages"), Column.WIDTH)
	column:refresh()
end

local AGGDEF_SLIDER_WIDTH = 128
local AGGDEF_INFO_WIDTH = 19
local aggdef_info = ui.find(right, "aggdef_info")
local aggdef_advanced_shown = false

local function show_aggdef_advanced(advanced)
	if advanced == aggdef_advanced_shown then
		return
	end
	aggdef_advanced_shown = advanced
	ui.visible(aggdef_info, advanced)
	ui.size(aggdef, advanced and AGGDEF_SLIDER_WIDTH - AGGDEF_INFO_WIDTH or AGGDEF_SLIDER_WIDTH, 18)
	if not advanced then
		ui.destinations.close(windows.aggdef)
	end
end

local function bind_action(name, reference)
	local button = ui.find(root, name)
	ui.bind(button, reference)
	ui.action(button, "game.control_center.activate", reference, "left")
end

local function update_selections()
	for _, entry in ipairs(window_buttons) do
		ui.visual_selected(entry[1], ui.destinations.is_open(entry[2]))
	end
	for _, entry in ipairs(top_menus) do
		local selected = ui.menu.is_open(entry.button)
		for _, window in ipairs(entry.windows) do
			selected = selected or ui.destinations.is_open(window)
		end
		ui.visual_selected(entry.button, selected)
	end
end

local function same_entries(shown, entries)
	if shown == nil or #shown ~= #entries then
		return false
	end
	for index, entry in ipairs(entries) do
		if shown[index].key ~= entry.key or shown[index].label ~= entry.label then
			return false
		end
	end
	return true
end

-- rebuilt only when the list changes (an open submenu is not cleared under the mouse)
local function rebuild_dynamic(menu)
	if same_entries(menu.shown, menu.entries) then
		return
	end
	menu.shown = menu.entries
	ui.menu.clear(menu.anchor)
	for _, entry in ipairs(menu.entries) do
		ui.menu.action_icon(menu.anchor, entry.label, "game.control_center.activate", entry.reference, entry.icon)
	end
	if menu.index then
		ui.menu.visible(ui.find(left, "actions"), menu.index, #menu.entries > 0)
	end
end

local function update_menu_state()
	if not latest_state or ui.in_combat() then
		return
	end
	if menu_state.pets_index then
		ui.menu.visible(ui.find(left, "actions"), menu_state.pets_index, latest_state.has_pets)
	end
	if menu_state.perks_window_index then
		ui.menu.visible(ui.find(left, "character"), menu_state.perks_window_index, latest_state.perks_available)
	end
	for _, menu in pairs(dynamic_menus) do
		rebuild_dynamic(menu)
	end
end

function control_center_configure(actions, registered_commands, registered_windows)
	for _, command in ipairs(registered_commands) do
		commands[command.key] = command.reference
	end
	table.sort(registered_windows, function(left_window, right_window)
		if left_window.label == right_window.label then
			return left_window.key < right_window.key
		end
		return left_window.label < right_window.label
	end)
	local addon_entries = {}
	for _, registered_window in ipairs(registered_windows) do
		local window = ui.destinations.require(registered_window.key)
		addon_windows[#addon_windows + 1] = window
		addon_entries[#addon_entries + 1] = window_entry(registered_window.label, window)
	end
	if #addon_entries > 0 then
		table.insert(actions_menu, 1, menu_entry("Addons", addon_entries))
	end
	bind_action("left_target", actions.select_self)
	bind_action("right_target", actions.toggle_attack)
	bind_action("left_previous", actions.friendly_previous)
	bind_action("left_next", actions.friendly_next)
	bind_action("right_previous", actions.hostile_previous)
	bind_action("right_next", actions.hostile_next)

	local actions_button = ui.find(left, "actions")
	local character_button = ui.find(left, "character")
	local map_button = ui.find(right, "map")
	local shop_button = ui.find(right, "store")
	local team_button = ui.find(right, "team")
	for _, button in ipairs({ actions_button, character_button, map_button, shop_button, team_button }) do
		ui.menu.style(button, "context")
	end
	populate(actions_button, actions_menu, "actions")
	populate(character_button, character_menu, "character")
	populate(map_button, map_menu, "map")
	populate(shop_button, shop_menu, "shop")
	populate(team_button, team_menu, "team")
	top_menus = {
		{ button = actions_button, windows = { windows.actions, windows.stats, windows.health, windows.nano_bar,
			windows.experience, windows.alien_experience, windows.chat, windows.combat_chat,
			windows.tradeskills, windows.chat_config, windows.pets } },
		{ button = character_button, windows = { windows.skills, windows.perks } },
		{ button = map_button, windows = { windows.planet_map, windows.playfield_map } },
		{ button = team_button, windows = { windows.team, windows.raid, windows.team_search } },
	}
	for _, window in ipairs(addon_windows) do
		top_menus[1].windows[#top_menus[1].windows + 1] = window
	end
end

local function number(value)
	return value >= 0 and tostring(value) or "--"
end

local function grouped(value)
	if value < 0 then
		return "--"
	end
	local text = tostring(value)
	local first = #text % 3
	if first == 0 then
		first = 3
	end
	local result = string.sub(text, 1, first)
	for index = first + 1, #text, 3 do
		result = result .. "," .. string.sub(text, index, index + 2)
	end
	return result
end

function control_center_refresh()
	fit_strip()
	update_selections()
	if column then
		column:refresh()
	end
end

function control_center_apply(state, perks, attacks)
	latest_state = state
	dynamic_menus.perks.entries = perks or {}
	dynamic_menus.attacks.entries = attacks or {}
	ui.visible(minibar, state.minibar_shown == true)
	if column then
		column:show(state.rollup_shown == true, state.rollup_background_opacity)
	end
	ui.text(ncu, "NCU " .. number(state.used_ncu) .. "/" .. number(state.max_ncu))
	ui.text(credits, "CRED " .. grouped(state.credits))
	show_aggdef_advanced(state.aggdef_advanced == true)
	if state.aggdef >= AGGDEF_MIN then
		ui.progress(aggdef, aggdef_progress(state.aggdef))
		show_aggdef(state.aggdef)
	end
	ui.visual_selected(right_target, state.fighting)
	update_selections()
	update_menu_state()
end

ui.on_lockdown(function(locked)
	if not locked then
		update_menu_state()
		update_selections()
	end
end)
