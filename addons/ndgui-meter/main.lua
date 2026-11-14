-- ndGUI Damage Meter: a standalone window (Control Center > Actions > Addons > Damage Meter).
--
--   Damage / Healing / Taken  per source: amount, per second, share; click a source for its abilities
--   Targets                   damage per enemy; click one for who hit it
--   Deaths                    who died and when; click one to replay the last hits before it
-- Me / Team / Raid / All decides whose numbers count; < > walks through the last fights, Overall
-- sums them; Pets folds your pets into you. A live per-second graph and a stat strip (crit, miss,
-- biggest hit, best 5 s burst) sit on top. Data: game.combat, i.e. what this client observes.
local Window = ui.require("core.window")
local Meter = ui.require("ndgui.meter")
local Unit = ui.require("notum.ndgui-lib/unit")

local root = ui.load("root.xml")
ui.root(root)
local meter = Meter.create()
local content = ui.load("content.xml")
local function find(name) return ui.find(content, name) end
local host = find("meter_rows")
local summary, stats_line, peak = find("meter_summary"), find("meter_stats"), find("meter_peak")
local graph, graph_back, columns_host = find("meter_graph"), find("meter_graph_back"), find("meter_columns")
local fight_label, detail_bar, detail_title = find("meter_fight"), find("meter_detail"), find("meter_detail_title")
local mode_buttons = {
	damage = find("meter_damage"), healing = find("meter_healing"), taken = find("meter_taken"),
	targets = find("meter_targets"), deaths = find("meter_deaths"),
}
local filter_button, prev_button, next_button = find("meter_filter"), find("meter_prev"), find("meter_next")
local overall_button, pets_button, reset_button, back_button =
	find("meter_overall"), find("meter_pets"), find("meter_reset"), find("meter_back")

-- ---- sizes ---------------------------------------------------------------------------------
local MAX_ROWS, ROW_H = 15, 20 -- row.xml adds a 2px gap under each 18px bar
local SUMMARY_H, STATS_H, GRAPH_H = 18, 14, 34
local HEADER_H = 33 + 3 + SUMMARY_H + STATS_H + 3 + GRAPH_H + 4 + 22 + 3 + 22 + 4 + 3 + 6
local MIN_W, MAX_W = 420, 720
local GRAPH_COLUMNS = 60
local FIXED_ROW2 = 50 + 6 + 22 + 3 + 3 + 22 + 6 + 58 + 3 + 42 + 3 + 46 -- row-2 buttons and gaps

-- ---- words and colours -----------------------------------------------------------------
local NOUN = { damage = "damage", healing = "healing", taken = "taken", targets = "damage", deaths = "taken" }
local RATE = { damage = "DPS", healing = "HPS", taken = "DTPS", targets = "DPS", deaths = "DTPS" }
local KIND = { damage = "damage", healing = "healing", taken = "taken", targets = "damage", deaths = "taken" }
local COLOR = {
	you = "#4fb3e8", pet = "#5fb8a8",
	damage = "#b8743f", healing = "#4f9f5f", taken = "#a8434a", targets = "#b8743f", deaths = "#a8434a",
	enemy = "#8a5a5a", crit = "#d8a040",
}
-- profession tints for players we know (team / raid)
local PROFESSION_COLOR = {
	[1] = "#c45a4a", [2] = "#d9a441", [3] = "#b08a5a", [4] = "#6b9a4a", [5] = "#8a6db0", [6] = "#5fa05f",
	[7] = "#c9b458", [8] = "#8c8cb4", [9] = "#b0574a", [10] = "#58b08c", [11] = "#5a8ad0", [12] = "#a06ac0",
	[14] = "#c8c8a0", [15] = "#7a5a8a",
}
local FILTERS = { "me", "team", "raid", "all" }
local FILTER_LABEL = { me = "Me", team = "Team", raid = "Raid", all = "All" }
local FILTER_NOTE = {
	me = "you and your pets", team = "you, your pets and your team",
	raid = "you, your pets and your raid", all = "everyone this client sees",
}

-- ---- state ---------------------------------------------------------------------------------
local mode, filter, overall, merge = "damage", "me", false, true
local back = 0 -- 0 = newest fight, 1 = the one before...
local detail -- nil, or { kind = "actor" | "target" | "death", ... }
local shown, fit, row_w = true, 8, 400
local team_names, raid_names, professions = {}, {}, {} -- current roster by name
local rows, cols = {}, {}
local render

-- ---- rows and graph columns ----------------------------------------------------------------
for index = 1, MAX_ROWS do
	local view = ui.load("row.xml")
	ui.add(host, view)
	local row = { root = ui.find(view, "meter_row") }
	for _, name in ipairs({ "row_track", "row_fill", "row_name", "row_name_shadow", "row_value", "row_value_shadow", "row_hit" }) do
		row[name] = ui.find(view, name)
	end
	row.parts = { row.root, row.row_track, row.row_fill, row.row_name, row.row_name_shadow, row.row_value, row.row_value_shadow, row.row_hit }
	-- left clicks land on the flat button laid over the row (pointer release is right-only)
	ui.on_click(row.row_hit, function()
		if row.click then
			row.click()
			render()
		end
	end)
	ui.visible(row.root, false)
	rows[index] = row
end
for index = 1, GRAPH_COLUMNS do
	local view = ui.load("column.xml")
	ui.add(columns_host, view)
	cols[index] = ui.find(view, "meter_column")
	ui.visible(cols[index], false)
end

-- ---- formatting ----------------------------------------------------------------------------
local function short(n)
	if n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fk", n / 1e3)
	end
	return Unit.thousands(n)
end

local function rate(n)
	return n < 100 and string.format("%.1f", n) or short(n)
end

local function clock(seconds)
	seconds = math.floor(seconds + 0.5)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function pct(part, whole)
	return whole > 0 and math.floor(part / whole * 100 + 0.5) or 0
end

-- ---- who counts ----------------------------------------------------------------------------
local function keep(actor)
	if filter == "all" or actor.self or actor.pet then
		return true
	end
	if filter == "team" then
		return team_names[actor.raw] == true
	elseif filter == "raid" then
		return raid_names[actor.raw] == true
	end
	return false
end

local function actor_color(actor, fallback)
	if actor.self then
		return COLOR.you
	elseif actor.pet then
		return COLOR.pet
	end
	local profession = professions[actor.raw]
	return profession and PROFESSION_COLOR[profession] or fallback
end

local function current_segment()
	if overall then
		return meter.all
	end
	local fights = meter.fights
	return fights[#fights - math.min(back, #fights - 1)]
end

-- ---- painting --------------------------------------------------------------------------------
local function paint_row(row, entry, top)
	ui.visible(row.root, entry ~= nil)
	row.click = entry and entry.click or nil
	if not entry then
		return
	end
	local filled = top > 0 and math.floor(row_w * math.max(0, entry.value) / top + 0.5) or 0
	ui.visible(row.row_fill, filled > 0)
	if filled > 0 then
		ui.size(row.row_fill, filled, ROW_H - 2)
	end
	ui.graphic_tint(row.row_fill, entry.color)
	ui.text(row.row_name, entry.name)
	ui.text(row.row_name_shadow, entry.name)
	ui.text(row.row_value, entry.text)
	ui.text(row.row_value_shadow, entry.text)
	for _, part in ipairs(row.parts) do
		ui.tooltip(part, entry.tooltip or "")
	end
end

local function paint_graph(seg, kind)
	local series = Meter.series(seg, kind, keep)
	local count = #series
	local first = math.max(1, count - GRAPH_COLUMNS + 1)
	local top = 0
	for i = first, count do
		if series[i] > top then top = series[i] end
	end
	local col_w = math.max(2, math.floor((row_w - 4) / GRAPH_COLUMNS))
	local height = GRAPH_H - 3
	for index, col in ipairs(cols) do
		local value = series[first + index - 1]
		local h = value and top > 0 and math.max(value > 0 and 1 or 0, math.floor(height * value / top + 0.5)) or 0
		ui.visible(col, h > 0)
		if h > 0 then
			ui.size(col, col_w - 1, h)
			ui.graphic_tint(col, COLOR[mode])
		end
	end
	ui.text(peak, top > 0 and ("peak " .. rate(top) .. "/s") or (seg and not seg.buckets and "overall: no graph" or ""))
end

-- crit / miss / biggest hit / best 5 s for one actor in one kind
local function stat_text(actor, kind, who)
	if not actor then
		return ""
	end
	local st = actor.stats[kind]
	local swings = st.hits + st.misses
	local parts = { who }
	if st.hits > 0 then
		parts[#parts + 1] = "crit " .. pct(st.crits, st.hits) .. "%"
	end
	if swings > 0 and (kind == "damage" or kind == "taken") then
		parts[#parts + 1] = (kind == "taken" and "evaded " or "miss ") .. pct(st.misses, swings) .. "%"
	end
	parts[#parts + 1] = "max " .. short(st.max)
	parts[#parts + 1] = "best 5s " .. rate(st.burst) .. "/s"
	return table.concat(parts, "  ·  ")
end

-- entries for the list part of the window
local function list_entries(seg, seconds)
	local entries, total, top = {}, 0, 0
	if mode == "targets" then
		local list
		list, total = Meter.targets(seg, keep, merge)
		for i, target in ipairs(list) do
			entries[i] = {
				name = i .. ". " .. target.name, value = target.amount, color = COLOR.enemy,
				text = string.format("%s  %s/s  %d%%", short(target.amount), rate(target.amount / seconds), pct(target.amount, total)),
				tooltip = target.name .. ": " .. Unit.thousands(target.amount) .. " damage from the shown players. Click for who.",
				click = function() detail = { kind = "target", key = target.key, name = target.name } end,
			}
		end
		top = list[1] and list[1].amount or 0
	elseif mode == "deaths" then
		for i, d in ipairs(Meter.deaths(seg, keep)) do
			local last = d.hits[#d.hits]
			entries[i] = {
				name = d.name .. "  " .. clock(d.at), value = 1, color = actor_color(d, COLOR.deaths),
				text = d.killer and ("by " .. d.killer .. (last and ("  " .. short(last.amount)) or "")) or "",
				tooltip = string.format("%s died at %s. Click for the last %d hits.", d.name, clock(d.at), #d.hits),
				click = function() detail = { kind = "death", death = d } end,
			}
		end
		top = 1
	else
		local list
		list, total = Meter.leaders(seg, mode, keep, merge)
		for i, actor in ipairs(list) do
			local amount = actor[mode]
			entries[i] = {
				name = i .. ". " .. actor.name, value = amount, color = actor_color(actor, COLOR[mode]),
				text = string.format("%s  %s/s  %d%%", short(amount), rate(amount / seconds), pct(amount, total)),
				tooltip = string.format("%s: %s %s, %.1f %s, %.1f%%. Click for the breakdown.", actor.name, Unit.thousands(amount),
					NOUN[mode], amount / seconds, RATE[mode], total > 0 and amount / total * 100 or 0),
				click = function() detail = { kind = "actor", key = actor.key, name = actor.name } end,
			}
		end
		top = list[1] and list[1][mode] or 0
	end
	return entries, total, top
end

-- entries for a drill-down
local function detail_entries(seg, seconds)
	local entries, top, title = {}, 0, ""
	if detail.kind == "actor" then
		local actor = Meter.actor(seg, detail.key, merge)
		local kind = KIND[mode]
		title = (actor and actor.name or detail.name) .. "  ·  " .. NOUN[mode] .. " by " .. (kind == "taken" and "source" or "ability")
		if actor then
			local total = actor[kind]
			for i, ability in ipairs(Meter.abilities(actor, kind)) do
				entries[i] = {
					name = ability.label, value = ability.amount, color = actor_color(actor, COLOR[mode]),
					text = string.format("%s  %d%%  %dx  max %s", short(ability.amount), pct(ability.amount, total), ability.hits, short(ability.max)),
					tooltip = string.format("%s: %s in %d hits (avg %s), %d%% crit, biggest %s, %.1f/s",
						ability.label, Unit.thousands(ability.amount), ability.hits, short(ability.amount / math.max(1, ability.hits)),
						pct(ability.crits, ability.hits), Unit.thousands(ability.max), ability.amount / seconds),
				}
				if ability.amount > top then top = ability.amount end
			end
		end
	elseif detail.kind == "target" then
		local target = seg and seg.targets[detail.key]
		title = detail.name .. "  ·  who hit it"
		if target then
			local list, total = Meter.sources_of(seg, target, keep, merge)
			for i, source in ipairs(list) do
				entries[i] = {
					name = i .. ". " .. source.name, value = source.amount, color = actor_color(source, COLOR.damage),
					text = string.format("%s  %s/s  %d%%", short(source.amount), rate(source.amount / seconds), pct(source.amount, total)),
					tooltip = source.name .. ": " .. Unit.thousands(source.amount) .. " on " .. detail.name,
				}
			end
			top = list[1] and list[1].amount or 0
		end
	else
		local d = detail.death
		title = d.name .. " died at " .. clock(d.at) .. (d.killer and ("  ·  by " .. d.killer) or "")
		for i, hit in ipairs(d.hits) do
			local before = d.t - hit.t
			entries[i] = {
				name = string.format("-%.1fs  %s", before, hit.source), value = hit.amount, color = hit.crit and COLOR.crit or COLOR.taken,
				text = hit.label .. "  " .. short(hit.amount) .. (hit.crit and "!" or ""),
				tooltip = string.format("%.1f s before: %s hit for %s with %s%s", before, hit.source, Unit.thousands(hit.amount),
					hit.label, hit.crit and " (critical)" or ""),
			}
			if hit.amount > top then top = hit.amount end
		end
		if #d.hits == 0 then
			entries[1] = { name = "No hits seen before this death", value = 0, color = COLOR.taken, text = "" }
		end
	end
	return entries, top, title
end

local function render_now()
	local seg = current_segment()
	local seconds = meter:seconds(seg)
	local kind = KIND[mode]

	local entries, total, top
	if detail then
		local title
		entries, top, title = detail_entries(seg, seconds)
		total = 0
		ui.text(detail_title, title)
	else
		entries, total, top = list_entries(seg, seconds)
	end
	-- summary: which fight, how long, how much
	local where = overall and "Overall" or Meter.name(seg)
	if not seg then
		ui.text(summary, "No combat yet")
	elseif not detail and mode ~= "deaths" then
		ui.text(summary, string.format("%s  ·  %s  ·  %s %s  ·  %s %s", where, clock(seconds),
			short(total), NOUN[mode], rate(total / seconds), RATE[mode]))
	else
		ui.text(summary, where .. "  ·  " .. clock(seconds))
	end
	-- stat strip: the drilled-in actor, otherwise you
	local strip = ""
	if seg then
		if detail and detail.kind == "actor" then
			local actor = Meter.actor(seg, detail.key, merge)
			strip = stat_text(actor, kind, actor and actor.name or "")
		elseif mode ~= "targets" then
			strip = stat_text(Meter.actor(seg, "self", merge), kind, "You")
		end
	end
	ui.text(stats_line, meter.incomplete and "Some combat reports were lost; numbers are low"
		or meter.full and "Too many sources; the smallest are not listed"
		or strip ~= "" and strip or ("Showing " .. FILTER_NOTE[filter]))

	paint_graph(seg, kind)

	-- controls
	for key, button in pairs(mode_buttons) do
		ui.selected(button, key == mode)
	end
	ui.text(filter_button, FILTER_LABEL[filter])
	ui.tooltip(filter_button, "Showing " .. FILTER_NOTE[filter] .. ". Click: Me / Team / Raid / All")
	ui.selected(overall_button, overall)
	ui.selected(pets_button, merge)
	local fights = #meter.fights
	ui.enabled(prev_button, not overall and back < fights - 1)
	ui.enabled(next_button, not overall and back > 0)
	ui.text(fight_label, overall and "All fights" or fights == 0 and "-" or
		string.format("%s %d/%d", back == 0 and meter:live() and "Live" or "Fight", fights - back, fights))
	ui.visible(detail_bar, detail ~= nil)

	local room = detail and math.max(1, fit - 1) or fit
	for index, row in ipairs(rows) do
		paint_row(row, index <= room and entries[index] or nil, top)
	end
end

render = function()
	if shown then
		render_now()
	end
end

-- ---- layout --------------------------------------------------------------------------------
local function layout(window, width, height)
	width = math.max(MIN_W, math.min(MAX_W, width))
	local minimum, maximum = HEADER_H + 3 * ROW_H, HEADER_H + MAX_ROWS * ROW_H
	height = math.max(minimum, math.min(maximum, height))
	fit = math.max(1, math.min(MAX_ROWS, math.floor((height - HEADER_H) / ROW_H)))
	row_w = width - Window.CONTENT_SIDES - 6
	for _, row in ipairs(rows) do
		ui.size(row.root, row_w, ROW_H - 2)
		ui.size(row.row_track, row_w, ROW_H - 2)
		ui.size(row.row_hit, row_w, ROW_H - 2)
		local name_w = math.floor(row_w * 0.48)
		ui.size(row.row_name, name_w, ROW_H - 2)
		ui.size(row.row_name_shadow, name_w, ROW_H - 3)
		ui.size(row.row_value, row_w - name_w - 4, ROW_H - 2)
		ui.size(row.row_value_shadow, row_w - name_w - 4, ROW_H - 3)
	end
	ui.size(summary, row_w, SUMMARY_H)
	ui.size(stats_line, row_w, STATS_H)
	ui.size(graph, row_w, GRAPH_H)
	ui.size(graph_back, row_w, GRAPH_H)
	ui.size(columns_host, row_w - 4, GRAPH_H - 3)
	ui.size(peak, 120, 12)
	ui.size(fight_label, math.max(40, row_w - FIXED_ROW2), 22)
	ui.size(detail_title, row_w - 52, 22)
	ui.limits(window.root, MIN_W, minimum, MAX_W, maximum)
	ui.request_size(window.root, width, height)
	window:fit_title(width, true)
	window:fit_content(width, height)
	render()
end

local frame = Window.create({
	template = "library://notum.ndgui-lib/window.xml",
	title = "Damage Meter", content = content, width = 440, height = HEADER_H + 8 * ROW_H,
	horizontal = "end", vertical = "center", layout = layout,
})
ui.add(root, frame.root)
ui.register_view(frame.root, "meter")

-- ---- remembered choices ------------------------------------------------------------------
local function save()
	if ui.preference and ui.preference.write then
		pcall(ui.preference.write, "NdguiMeterMode", mode, "text")
		pcall(ui.preference.write, "NdguiMeterFilter", filter, "text")
		pcall(ui.preference.write, "NdguiMeterOverall", tostring(overall), "bool")
		pcall(ui.preference.write, "NdguiMeterPets", tostring(merge), "bool")
	end
end
if ui.preference and ui.preference.read then
	local function read(key)
		local ok, value = pcall(ui.preference.read, key)
		return ok and value or ""
	end
	if NOUN[read("NdguiMeterMode")] then mode = read("NdguiMeterMode") end
	if FILTER_LABEL[read("NdguiMeterFilter")] then filter = read("NdguiMeterFilter") end
	overall = read("NdguiMeterOverall") == "true"
	merge = read("NdguiMeterPets") ~= "false"
end

-- ---- controls --------------------------------------------------------------------------------
local function changed()
	save()
	render()
end
for key, button in pairs(mode_buttons) do
	ui.on_click(button, function()
		mode, detail = key, nil
		changed()
	end)
end
ui.on_click(filter_button, function()
	for i, f in ipairs(FILTERS) do
		if f == filter then
			filter = FILTERS[i % #FILTERS + 1]
			break
		end
	end
	changed()
end)
ui.on_click(prev_button, function()
	back, detail = math.min(back + 1, math.max(0, #meter.fights - 1)), nil
	render()
end)
ui.on_click(next_button, function()
	back, detail = math.max(0, back - 1), nil
	render()
end)
ui.on_click(overall_button, function()
	overall, detail = not overall, nil
	changed()
end)
ui.on_click(pets_button, function()
	merge, detail = not merge, nil
	changed()
end)
ui.on_click(back_button, function()
	detail = nil
	render()
end)

-- ---- data ----------------------------------------------------------------------------------
-- a live fight ticks once a second so its clock and rates keep moving
local ticking, last_tick = false, 0
local function tick(now)
	now = now or ui.time()
	if not meter:live() then
		ticking = false
		render()
		ui.stop_updates()
		return
	end
	if now - last_tick >= 1000 then
		last_tick = now
		render()
	end
end

local function observe()
	return game.combat.subscribe("damage,healing,miss,death", function(batch, events)
		local fights = #meter.fights
		meter:apply(batch, events)
		-- keep looking at the same old fight when a new one starts
		if back > 0 and #meter.fights > fights then
			back = math.min(back + 1, #meter.fights - 1)
		end
		render()
		if not ticking and meter:live() then
			ticking = true
			ui.on_update(tick)
		end
	end)
end
local subscription = observe()
ui.on_click(reset_button, function()
	game.combat.unsubscribe(subscription)
	subscription = observe()
	meter:reset()
	back, detail = 0, nil
	render()
end)

-- who is in your team / raid right now (own_team = your raid subgroup or ordinary team)
if game.team and game.team.subscribe then
	pcall(game.team.subscribe, function(update)
		team_names, raid_names, professions = {}, {}, {}
		local data = update and update.data
		for _, member in ipairs(data and data.members or {}) do
			local character = member.character or {}
			if character.name then
				raid_names[character.name] = true
				if member.own_team then
					team_names[character.name] = true
				end
				professions[character.name] = character.profession
			end
		end
		render()
	end)
end

ui.on_visibility(frame.root, function(visible)
	shown = visible
	render()
end)
render()
