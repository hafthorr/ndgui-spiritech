-- ndGUI unit frame, shared by the target panels and the team window.
-- A frame shows: accent stripe, portrait (profession icon for players, level otherwise), name + level,
-- HP bar with exact numbers and a pale "ghost" of damage just taken that drains away, a pulse under
-- 25% HP, nano bar when known, an info row (profession / org or side, distance, reach dot), floating
-- combat numbers from game.combat, and optionally who this unit is attacking ("» You").
--
-- One VM owns one ticker: every frame in the VM animates from it. Packages that also animate something
-- else hand that to M.set_extra_tick instead of calling ui.on_update themselves.
local M = {}

M.PROFESSIONS = {
	[1] = "Soldier", [2] = "Martial Artist", [3] = "Engineer", [4] = "Fixer", [5] = "Agent",
	[6] = "Adventurer", [7] = "Trader", [8] = "Bureaucrat", [9] = "Enforcer", [10] = "Doctor",
	[11] = "Nano-Technician", [12] = "Meta-Physicist", [14] = "Keeper", [15] = "Shade",
}
M.SIDES = { [0] = "Neutral", [1] = "Clan", [2] = "Omni" }

local XML = "library://notum.ndgui-lib/unit.xml"
local GHOST_HOLD_MS, GHOST_DRAIN = 450, 0.9 -- drain speed: fraction of the bar per second
local LOW_HP = 0.25
local MARQUEE_PAUSE_MS, MARQUEE_STEP_MS = 1500, 180 -- long names: rest at each end, then one letter a step
local BRIGHT = 0.45 -- bar luminance above which its HP text turns black
local FLOATERS, FLOAT_MS = 5, 1100
local TOT_MS = 8000 -- how long "who it attacks" stays after the last observed attack
local ACCENT_W, PORTRAIT_GAP, PAD_L, PAD_R = 3, 5, 6, 7 -- must match unit.xml borders
local COLORS = {
	damage = "#ff6b5b", critical = "#ffd84a", healing = "#6fe08a", miss = "#9aa8b4",
	tot_self = "#ffa040", tot_other = "#c5d7e6", reach_on = "#6fd46f", reach_off = "#33424f",
}
M.COLORS = COLORS

local frames = {}
local me -- latest Character for "self", for distances

-- ---- helpers ---------------------------------------------------------------------------
function M.thousands(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function M.set_self(character)
	me = type(character) == "table" and character or nil
end

function M.distance(c)
	if not (c and me and not c.is_self and c.x and c.z and me.x and me.z) then
		return nil
	end
	local dx, dy, dz = c.x - me.x, (c.y or 0) - (me.y or 0), c.z - me.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function M.info_line(c)
	if not c then
		return ""
	end
	if c.is_npc then
		return c.organization and c.organization ~= "" and c.organization or "NPC"
	end
	local parts = {}
	if c.profession and M.PROFESSIONS[c.profession] then
		parts[#parts + 1] = M.PROFESSIONS[c.profession]
	end
	if c.organization and c.organization ~= "" then
		parts[#parts + 1] = c.organization
	elseif c.side and M.SIDES[c.side] then
		parts[#parts + 1] = M.SIDES[c.side]
	end
	return table.concat(parts, " · ")
end

local function hex(color, default)
	if type(color) == "number" then
		return string.format("#%06x", color)
	end
	return color or default
end

-- 0..1 perceived brightness of "#rrggbb"
local function luminance(color)
	local r, g, b = tostring(color):match("^#?(%x%x)(%x%x)(%x%x)")
	if not r then
		return 0
	end
	return (0.299 * tonumber(r, 16) + 0.587 * tonumber(g, 16) + 0.114 * tonumber(b, 16)) / 255
end
M.luminance = luminance

-- ---- ticker ----------------------------------------------------------------------------
local ticking, extra = false, nil

-- Long names scroll inside the name box: pause, slide to the end a letter at a time, pause, jump back.
local function step_marquee(f, now)
	local m = f.marquee
	if not m then
		return false
	end
	if now >= m.next_at then
		if m.pos >= m.last then
			m.pos, m.next_at = 1, now + MARQUEE_PAUSE_MS
		else
			m.pos = m.pos + 1
			m.next_at = now + (m.pos >= m.last and MARQUEE_PAUSE_MS or MARQUEE_STEP_MS)
		end
		ui.text(f.v.name, m.full:sub(m.pos, m.pos + m.fit - 1))
	end
	return f.visible
end

local function place_float(f, fl, t)
	local start = 4 + f.name_h + 2 -- top of the HP bar
	local top = math.max(0, math.floor(start * (1 - t) + 0.5))
	local right = PAD_R + 4 + fl.lane * math.floor(30 * f.k)
	ui.borders(fl.box, 0, top, right, 0)
	local alpha = t < 0.6 and 1 or math.max(0, 1 - (t - 0.6) / 0.4)
	ui.opacity(fl.text, alpha)
	ui.opacity(fl.shadow, alpha)
end

local function tot_on(f, now)
	return f.show_tot and not f.compact and f.tot_until ~= nil and now < f.tot_until
end

local function paint_tot(f, now)
	local on = tot_on(f, now or ui.time())
	ui.visible(f.v.tot, on)
	local tot_w = on and f.tot_w or 0
	ui.size(f.v.info, math.max(0, f.inner - f.distance_w - f.reach_w - 4 - tot_w), f.info_h)
	if on then
		ui.text(f.v.tot, "» " .. (f.tot_self and "You" or f.tot_name))
		ui.text_color(f.v.tot, f.tot_self and COLORS.tot_self or COLORS.tot_other)
	end
end

local function paint_bar(f)
	local inner = f.inner or 1
	local filled = math.floor(inner * f.fraction + 0.5)
	local ghost = math.floor(inner * math.max(f.ghost, f.fraction) + 0.5)
	ui.visible(f.v.hp_fill, filled > 0)
	if filled > 0 then
		ui.size(f.v.hp_fill, filled, f.hp_h)
	end
	ui.visible(f.v.hp_ghost, ghost > filled)
	if ghost > filled then
		ui.size(f.v.hp_ghost, ghost, f.hp_h)
	end
end

local function tick(now)
	now = now or ui.time()
	local active = false
	for _, f in ipairs(frames) do
		if f.ghost > f.fraction then
			if now >= f.hold_until then
				-- drain only for time after the hold ended, so it starts smoothly
				local from = math.max(f.last_tick or now, f.hold_until)
				local step = GHOST_DRAIN * math.max(0, now - from) / 1000
				f.ghost = math.max(f.fraction, f.ghost - step)
			end
			active = true
		end
		f.last_tick = now
		if f.low and f.visible then
			ui.opacity(f.v.hp_fill, 0.6 + 0.4 * (0.5 + 0.5 * math.sin(now / 140)))
			active = true
		end
		paint_bar(f)
		for _, fl in ipairs(f.floats) do
			if fl.born then
				local t = (now - fl.born) / FLOAT_MS
				if t >= 1 then
					fl.born = nil
					ui.visible(fl.box, false)
				else
					place_float(f, fl, t)
					active = true
				end
			end
		end
		if step_marquee(f, now) then
			active = true
		end
		if f.tot_until then
			if now >= f.tot_until then
				f.tot_until = nil
				paint_tot(f, now)
			else
				active = true
			end
		end
	end
	if extra and extra(now) then
		active = true
	end
	if not active then
		ticking = false
		for _, f in ipairs(frames) do
			ui.opacity(f.v.hp_fill, 1)
		end
		ui.stop_updates()
	end
end

function M.wake()
	if ticking then
		return
	end
	ticking = true
	for _, f in ipairs(frames) do
		f.last_tick = nil
	end
	ui.on_update(tick)
end

-- fn(now) -> true while it still needs ticks; called from the shared ticker.
function M.set_extra_tick(fn)
	extra = fn
end

-- ---- frame -----------------------------------------------------------------------------
local Frame = {}
Frame.__index = Frame

local NAMES = { "frame", "plate", "accent", "portrait", "portrait_back", "portrait_icon", "portrait_level",
	"body", "row_name", "name", "level", "hp", "hp_track", "hp_ghost", "hp_fill", "hp_shadow", "hp_text",
	"np", "np_track", "np_fill", "row_info", "info", "tot", "distance", "reach", "floats" }

-- options.target_of_target: show who this unit attacks (target panels).
function M.new(parent, options)
	local view = ui.load(XML)
	ui.add(parent, view)
	local f = setmetatable({
		view = view, v = {}, floats = {}, next_float = 1, lane = 0,
		fraction = 0, ghost = 0, hold_until = 0, low = false, visible = false,
		k = 1, compact = false, show_tot = options and options.target_of_target or false,
	}, Frame)
	for _, name in ipairs(NAMES) do
		f.v[name] = ui.find(view, name)
	end
	for i = 1, FLOATERS do
		f.floats[i] = { box = ui.find(view, "float_" .. i), text = ui.find(view, "float_" .. i .. "_text"),
			shadow = ui.find(view, "float_" .. i .. "_shadow"), lane = 0 }
	end
	ui.click_through(f.v.floats, true) -- numbers never eat clicks meant for the frame
	ui.fill_color(f.v.portrait_back, "#C0080C10")
	ui.visible(f.v.frame, false)
	frames[#frames + 1] = f
	f:layout(250, 1, false)
	return f
end

-- Size every part for a frame width, scale k and compact mode.
function Frame:layout(width, k, compact)
	local v = self.v
	self.k, self.compact, self.width = k, compact, width
	local name_h, hp_h, np_h, info_h = math.floor(18 * k), math.floor(15 * k), math.floor(4 * k), math.floor(14 * k)
	local portrait = compact and 0 or (name_h + 2 + hp_h)
	local inner = width - ACCENT_W - (portrait > 0 and portrait + PORTRAIT_GAP or 0) - PAD_L - PAD_R
	local level_w = math.floor(52 * k)
	ui.size(v.frame, width, -1)
	ui.visible(v.portrait, portrait > 0)
	if portrait > 0 then
		ui.size(v.portrait, portrait, portrait)
		ui.size(v.portrait_back, portrait, portrait)
		local icon = math.floor(portrait * 0.86)
		ui.size(v.portrait_icon, icon, icon)
		ui.size(v.portrait_level, portrait, portrait)
		ui.font_size(v.portrait_level, math.floor(15 * k))
	end
	ui.size(v.body, inner, -1)
	ui.size(v.row_name, inner, name_h)
	ui.size(v.name, inner - level_w, name_h)
	ui.size(v.level, level_w, name_h)
	ui.font_size(v.name, math.floor(15 * k))
	ui.font_size(v.level, math.floor(11 * k))
	ui.size(v.hp, inner, hp_h)
	ui.size(v.hp_track, inner, hp_h)
	ui.size(v.hp_text, inner, hp_h)
	ui.size(v.hp_shadow, inner - 1, hp_h - 1)
	ui.font_size(v.hp_text, math.floor(11 * k))
	ui.font_size(v.hp_shadow, math.floor(11 * k))
	ui.size(v.np, inner, np_h)
	ui.size(v.np_track, inner, np_h)
	ui.visible(v.row_info, not compact)
	self.distance_w, self.reach_w, self.tot_w = math.floor(48 * k), math.floor(6 * k), math.floor(96 * k)
	ui.size(v.row_info, inner, info_h)
	ui.size(v.tot, self.tot_w, info_h)
	ui.size(v.distance, self.distance_w, info_h)
	ui.size(v.reach, self.reach_w, self.reach_w)
	for _, name in ipairs({ "info", "tot", "distance" }) do
		ui.font_size(v[name], math.floor(10.5 * k))
	end
	self.inner, self.hp_h, self.np_h, self.name_h, self.info_h, self.portrait_h = inner, hp_h, np_h, name_h, info_h, portrait
	self.name_w = inner - level_w
	paint_tot(self)
	paint_bar(self)
	self:fit_name()
end

-- Show the whole name, or start it scrolling when it is wider than its box.
function Frame:fit_name()
	local name = self.char_name
	self.marquee = nil
	if not name then
		return
	end
	ui.text(self.v.name, name)
	local box = self.name_w or 0
	local full = ui.text_width and ui.text_width(self.v.name)
	full = type(full) == "number" and full or 0
	if box <= 0 or full <= box or #name < 4 then
		return
	end
	local fit = math.max(3, math.floor(#name * box / full) - 1)
	self.marquee = { full = name, fit = fit, last = #name - fit + 1, pos = 1, next_at = ui.time() + MARQUEE_PAUSE_MS }
	ui.text(self.v.name, name:sub(1, fit))
	M.wake()
end

function Frame:hide()
	ui.visible(self.v.frame, false)
	self.visible = false
	self.marquee = nil
	self.fraction, self.ghost, self.low = 0, 0, false
	self.char_name, self.char_id, self.is_self = nil, nil, nil
	self.tot_until = nil
	for _, fl in ipairs(self.floats) do
		fl.born = nil
		ui.visible(fl.box, false)
	end
end

-- Total frame height (with its 4px bottom gap) as last shown.
function Frame:height()
	return (self.body_h or 0) + 4
end

-- s: name, name_color, accent, bar_color, fraction (nil: from the character), has_bar,
--    character (Character / CharacterSummary or nil), player (bool), in_reach (nil hides the dot),
--    header (tooltip), dim (absent: greyed).
function Frame:show(s)
	if not s or not s.name or s.name == "" then
		self:hide()
		return
	end
	local v, c, now = self.v, s.character, ui.time()
	if self.char_name ~= s.name then
		-- a different unit: no ghost, numbers or attack line carried over
		self.ghost, self.tot_until = 0, nil
		self.fraction = s.fraction or 0
	end
	ui.visible(v.frame, true)
	self.visible = true
	local renamed = self.char_name ~= s.name
	self.char_name, self.char_id, self.is_self = s.name, c and c.id, c and c.is_self or false

	local fraction = s.fraction
	if fraction == nil then
		fraction = c and c.health and c.max_health and c.max_health > 0 and c.health / c.max_health or 0
	end
	fraction = math.max(0, math.min(1, fraction))
	local bar_color = hex(s.bar_color, "#c44747")

	ui.fill_color(v.accent, hex(s.accent, "#3d6f9a"))
	if renamed or not self.marquee then
		self:fit_name()
	end
	ui.text_color(v.name, hex(s.name_color, "#c5d7e6"))
	ui.tooltip(v.frame, s.header or "")
	ui.opacity(v.body, s.dim and 0.55 or 1)

	-- portrait: profession icon for players, level otherwise
	local is_player = s.player
	if is_player == nil then
		is_player = c ~= nil and c.is_npc == false
	end
	if not self.compact then
		local icon = is_player and c and c.profession and M.PROFESSIONS[c.profession] and c.profession or nil
		ui.image(v.portrait_icon, icon and ("gfx://GFX_GUI_ICON_PROFESSION_LARGE_" .. icon) or "")
		ui.visible(v.portrait_icon, icon ~= nil)
		ui.text(v.portrait_level, icon and "" or (c and c.level and tostring(c.level) or "?"))
	end
	ui.text(v.level, (is_player or self.compact) and c and c.level and ("Lv " .. c.level) or "")

	-- health: exact numbers when known; a pale ghost marks damage just taken
	local has_bar = s.has_bar ~= false
	ui.visible(v.hp, has_bar)
	ui.graphic_tint(v.hp_fill, bar_color)
	if fraction < self.fraction - 0.0005 then
		self.ghost = math.max(self.ghost, self.fraction)
		self.hold_until = now + GHOST_HOLD_MS
	elseif fraction > self.ghost then
		self.ghost = fraction
	end
	self.fraction = fraction
	self.low = fraction > 0 and fraction < LOW_HP
	if not self.low then
		ui.opacity(v.hp_fill, 1)
	end
	local pct = tostring(math.floor(fraction * 100 + 0.5)) .. "%"
	local text = pct
	if c and c.health and c.max_health and c.max_health > 0 then
		text = M.thousands(c.health) .. " / " .. M.thousands(c.max_health) .. " (" .. pct .. ")"
	end
	ui.text(v.hp_text, text)
	ui.text(v.hp_shadow, text)
	-- black text on a bright bar (green, yellow) when the fill is under it, white otherwise
	local dark = luminance(bar_color) > BRIGHT and fraction >= 0.55
	ui.text_color(v.hp_text, dark and "#000000" or "#FFFFFF")
	ui.text_color(v.hp_shadow, dark and "#FFFFFF" or "#000000")
	ui.opacity(v.hp_shadow, dark and 0.25 or 1)
	paint_bar(self)
	if self.ghost > self.fraction or self.low then
		M.wake()
	end

	-- nano: known for you, your team and inspected players
	local has_nano = not self.compact and c ~= nil and c.nano ~= nil and (c.max_nano or 0) > 0
	ui.visible(v.np, has_nano)
	if has_nano then
		local n = math.floor(self.inner * math.max(0, math.min(1, c.nano / c.max_nano)) + 0.5)
		ui.visible(v.np_fill, n > 0)
		if n > 0 then
			ui.size(v.np_fill, n, self.np_h)
		end
	end

	-- the accent stripe is an empty view: give it the frame's real height
	self.body_h = math.max(4 + self.name_h + (has_bar and 2 + self.hp_h or 0) + (has_nano and 2 + self.np_h or 0)
		+ (self.compact and 0 or 2 + self.info_h) + 5, self.portrait_h + 8)
	ui.size(v.accent, ACCENT_W, self.body_h)

	-- info row: who, how far, in reach
	if not self.compact then
		ui.text(v.info, M.info_line(c))
		local d = M.distance(c)
		ui.text(v.distance, d and (d < 10 and string.format("%.1f m", d) or string.format("%d m", math.floor(d + 0.5))) or "")
		ui.visible(v.reach, s.in_reach ~= nil)
		if s.in_reach ~= nil then
			ui.fill_color(v.reach, s.in_reach and COLORS.reach_on or COLORS.reach_off)
			ui.tooltip(v.reach, s.in_reach and "In weapon reach" or "Out of weapon reach")
		end
		paint_tot(self, now)
	end
end

-- A floating number rising over the right end of the HP bar.
function Frame:float(text, color, big)
	if not self.visible then
		return
	end
	local fl = self.floats[self.next_float]
	self.next_float = self.next_float % FLOATERS + 1
	fl.born, fl.lane = ui.time(), self.lane
	self.lane = (self.lane + 1) % 3
	local size = math.floor((big and 15 or 12) * self.k)
	ui.text(fl.text, text)
	ui.text(fl.shadow, text)
	ui.text_color(fl.text, color)
	ui.font_size(fl.text, size)
	ui.font_size(fl.shadow, size)
	ui.visible(fl.box, true)
	place_float(self, fl, 0)
	M.wake()
end

function Frame:attacking(name, is_self)
	self.tot_name, self.tot_self, self.tot_until = name, is_self, ui.time() + TOT_MS
	paint_tot(self)
	M.wake()
end

-- ---- combat ----------------------------------------------------------------------------
-- Combat actor ids are matched to character ids once one event proves they agree; until then (or
-- when an id is missing) names decide. Names alone would mix up mobs that share a name.
local ids_agree = false

local function matches(f, id, name, is_self)
	if not f.visible then
		return false
	end
	if is_self then
		return f.is_self == true
	end
	if ids_agree and id and id ~= 0 and f.char_id then
		return id == f.char_id
	end
	if name and name ~= "" and name == f.char_name then
		if id and id ~= 0 and f.char_id and id == f.char_id then
			ids_agree = true
		end
		return true
	end
	return false
end
M._matches = matches

local function observe(events)
	for _, e in ipairs(events) do
		local amount = tonumber(e.amount) or 0
		for _, f in ipairs(frames) do
			if matches(f, e.target, e.target_name, e.target_is_self) then
				if e.kind == "damage" and amount > 0 then
					f:float("-" .. M.thousands(amount) .. (e.critical and "!" or ""),
						e.critical and COLORS.critical or COLORS.damage, e.critical)
				elseif e.kind == "healing" and amount > 0 then
					f:float("+" .. M.thousands(amount), COLORS.healing)
				elseif e.kind == "miss" then
					f:float("miss", COLORS.miss)
				end
			end
			if f.show_tot and (e.kind == "attack_started" or e.kind == "damage" or e.kind == "miss")
				and matches(f, e.source, e.source_name, e.source_is_self)
				and (e.target_is_self or (e.target_name or "") ~= "") then
				f:attacking(e.target_name, e.target_is_self)
			end
		end
	end
end
M._observe = observe

local watching = false
function M.watch_combat()
	if watching or not (game.combat and game.combat.subscribe) then
		return
	end
	watching = true
	pcall(game.combat.subscribe, "damage,healing,miss,attack_started", function(_, events)
		if type(events) == "table" then
			observe(events)
		end
	end)
end

return M
