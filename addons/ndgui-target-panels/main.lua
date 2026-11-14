-- Dovvetech prk.target-panels provider. One VM per panel (friendly / hostile), two native slots each.
-- Each slot is a fixed-size unit frame: consider-colour accent, profession portrait (players) or
-- level (NPCs), name + level, HP bar with exact numbers and a draining "ghost" of recent damage,
-- nano bar when known, and an info row (profession / org or side, distance, weapon reach).
-- The native slot only carries name, colours and fractions; the rest comes from game.character
-- ("target", "fight", "self"), matched to a slot by name. Double-click a panel: Lock / Size / Compact.
local D = ui.require("notum.ndgui-lib/dovvetech")
local root = ui.load("panel.xml")
ui.root(root)

local SIZES = { S = 1.0, M = 1.2, L = 1.45 }
local SIZE_ORDER = { "S", "M", "L" }
local BASE_W = 250 -- frame width at size S
local GHOST_HOLD_MS, GHOST_DRAIN = 450, 0.9 -- drain speed: fraction of the bar per second
local LOW_HP = 0.25
local ACCENT_W, PORTRAIT_GAP, PAD_L, PAD_R = 3, 5, 6, 7 -- must match frame.xml borders

local PROFESSIONS = {
	[1] = "Soldier", [2] = "Martial Artist", [3] = "Engineer", [4] = "Fixer", [5] = "Agent",
	[6] = "Adventurer", [7] = "Trader", [8] = "Bureaucrat", [9] = "Enforcer", [10] = "Doctor",
	[11] = "Nano-Technician", [12] = "Meta-Physicist", [14] = "Keeper", [15] = "Shade",
}
local SIDES = { [0] = "Neutral", [1] = "Clan", [2] = "Omni" }

local size, compact = "M", false
local editing = false
local placement
local edit, lock_button, size_button, compact_button
local frames = {}
local last_upper, last_lower
local characters = {} -- alias -> latest Character table

local function scale()
	return SIZES[size] or 1
end

local function frame_width()
	return math.floor(BASE_W * scale() + 0.5)
end

-- ---- frames ---------------------------------------------------------------------------
local function new_frame()
	local view = ui.load("frame.xml")
	ui.add(root, view)
	local f = { fraction = 0, ghost = 0, hold_until = 0, low = false }
	for _, name in ipairs({ "frame", "plate", "accent", "portrait", "portrait_back", "portrait_icon", "portrait_level",
		"body", "row_name", "name", "level", "hp", "hp_track", "hp_ghost", "hp_fill", "hp_shadow", "hp_text",
		"np", "np_track", "np_fill", "row_info", "info", "distance", "reach" }) do
		f[name] = ui.find(view, name)
	end
	ui.fill_color(f.portrait_back, "#C0080C10")
	ui.visible(f.frame, false)
	return f
end

-- Size every part of one frame for the current size / compact mode.
local function size_frame(f)
	local k, w = scale(), frame_width()
	local name_h, hp_h, np_h, info_h = math.floor(18 * k), math.floor(15 * k), math.floor(4 * k), math.floor(14 * k)
	local portrait = compact and 0 or (name_h + 2 + hp_h)
	local inner = w - ACCENT_W - (portrait > 0 and portrait + PORTRAIT_GAP or 0) - PAD_L - PAD_R
	local level_w = math.floor(52 * k)
	ui.size(f.frame, w, -1)
	ui.visible(f.portrait, portrait > 0)
	if portrait > 0 then
		ui.size(f.portrait, portrait, portrait)
		ui.size(f.portrait_back, portrait, portrait)
		local icon = math.floor(portrait * 0.86)
		ui.size(f.portrait_icon, icon, icon)
		ui.size(f.portrait_level, portrait, portrait)
		ui.font_size(f.portrait_level, math.floor(15 * k))
	end
	ui.size(f.body, inner, -1)
	ui.size(f.row_name, inner, name_h)
	ui.size(f.name, inner - level_w, name_h)
	ui.size(f.level, level_w, name_h)
	ui.font_size(f.name, math.floor(15 * k))
	ui.font_size(f.level, math.floor(11 * k))
	ui.size(f.hp, inner, hp_h)
	ui.size(f.hp_track, inner, hp_h)
	ui.size(f.hp_text, inner, hp_h)
	ui.size(f.hp_shadow, inner - 1, hp_h - 1)
	ui.font_size(f.hp_text, math.floor(11 * k))
	ui.font_size(f.hp_shadow, math.floor(11 * k))
	ui.size(f.np, inner, np_h)
	ui.size(f.np_track, inner, np_h)
	ui.visible(f.row_info, not compact)
	local distance_w, reach_w = math.floor(48 * k), math.floor(6 * k)
	ui.size(f.row_info, inner, info_h)
	ui.size(f.info, inner - distance_w - reach_w - 4, info_h)
	ui.size(f.distance, distance_w, info_h)
	ui.size(f.reach, reach_w, reach_w)
	ui.font_size(f.info, math.floor(10.5 * k))
	ui.font_size(f.distance, math.floor(10.5 * k))
	f.inner, f.hp_h, f.np_h, f.name_h, f.info_h, f.portrait_h = inner, hp_h, np_h, name_h, info_h, portrait
end

local function paint_bar(f)
	local inner = f.inner or 1
	local filled = math.floor(inner * f.fraction + 0.5)
	local ghost = math.floor(inner * math.max(f.ghost, f.fraction) + 0.5)
	ui.visible(f.hp_fill, filled > 0)
	if filled > 0 then
		ui.size(f.hp_fill, filled, f.hp_h)
	end
	ui.visible(f.hp_ghost, ghost > filled)
	if ghost > filled then
		ui.size(f.hp_ghost, ghost, f.hp_h)
	end
end

-- ---- character facts ------------------------------------------------------------------
local function character_for(name)
	if name == nil or name == "" then
		return nil
	end
	for _, alias in ipairs({ "target", "fight", "self" }) do
		local c = characters[alias]
		if c and c.name == name then
			return c
		end
	end
	return nil
end

local function thousands(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function distance_to(c)
	local me = characters.self
	if not (c and me and not c.is_self and c.x and c.z and me.x and me.z) then
		return nil
	end
	local dx, dy, dz = c.x - me.x, (c.y or 0) - (me.y or 0), c.z - me.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function info_line(c)
	if not c then
		return ""
	end
	if c.is_npc then
		return c.organization and c.organization ~= "" and c.organization or "NPC"
	end
	local parts = {}
	if c.profession and PROFESSIONS[c.profession] then
		parts[#parts + 1] = PROFESSIONS[c.profession]
	end
	if c.organization and c.organization ~= "" then
		parts[#parts + 1] = c.organization
	elseif c.side and SIDES[c.side] then
		parts[#parts + 1] = SIDES[c.side]
	end
	return table.concat(parts, " · ")
end

-- ---- animation: ghost of recent damage drains away, low HP pulses -----------------------
local animating = false
local function animate(now)
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
		if f.low then
			ui.opacity(f.hp_fill, 0.6 + 0.4 * (0.5 + 0.5 * math.sin(now / 140)))
			active = true
		end
		paint_bar(f)
	end
	if not active then
		animating = false
		for _, f in ipairs(frames) do
			ui.opacity(f.hp_fill, 1)
		end
		ui.stop_updates()
	end
end

local function start_animation()
	if animating then
		return
	end
	animating = true
	for _, f in ipairs(frames) do
		f.last_tick = nil
	end
	ui.on_update(animate)
end

-- ---- apply one native slot ------------------------------------------------------------
local function apply_slot(f, slot)
	local visible = slot ~= nil and slot.name ~= nil and slot.name ~= ""
	ui.visible(f.frame, visible)
	if not visible then
		f.fraction, f.ghost, f.low = 0, 0, false
		return
	end
	local c = character_for(slot.name)
	local fraction = math.max(0, math.min(1, slot.fraction or 0))
	local now = ui.time()

	ui.fill_color(f.accent, string.format("#%06x", slot.bar_color or 0x3d6f9a))
	ui.text(f.name, slot.name)
	ui.text_color(f.name, string.format("#%06x", slot.name_color or 0xc5d7e6))
	ui.tooltip(f.frame, slot.header or "")

	-- portrait: profession icon for players, level for NPCs / unknown
	local is_player = c ~= nil and c.is_npc == false
	if not compact then
		local icon = is_player and c.profession and PROFESSIONS[c.profession] and c.profession or nil
		ui.image(f.portrait_icon, icon and ("gfx://GFX_GUI_ICON_PROFESSION_LARGE_" .. icon) or "")
		ui.visible(f.portrait_icon, icon ~= nil)
		ui.text(f.portrait_level, icon and "" or (c and c.level and tostring(c.level) or "?"))
	end
	ui.text(f.level, (is_player or compact) and c and c.level and ("Lv " .. c.level) or "")

	-- health: exact numbers when known; a pale ghost marks damage just taken
	ui.visible(f.hp, slot.has_bar ~= false)
	ui.graphic_tint(f.hp_fill, string.format("#%06x", slot.bar_color or 0xc44747))
	if fraction < f.fraction - 0.0005 then
		f.ghost = math.max(f.ghost, f.fraction)
		f.hold_until = now + GHOST_HOLD_MS
	elseif fraction > f.ghost then
		f.ghost = fraction
	end
	f.fraction = fraction
	f.low = fraction > 0 and fraction < LOW_HP
	local pct = tostring(math.floor(fraction * 100 + 0.5)) .. "%"
	local text = pct
	if c and c.health and c.max_health and c.max_health > 0 then
		text = thousands(c.health) .. " / " .. thousands(c.max_health) .. "   " .. pct
	end
	ui.text(f.hp_text, text)
	ui.text(f.hp_shadow, text)
	paint_bar(f)
	if f.ghost > f.fraction or f.low then
		start_animation()
	end

	-- nano: known for you, your team and inspected players
	local has_nano = not compact and c ~= nil and c.nano ~= nil and (c.max_nano or 0) > 0
	ui.visible(f.np, has_nano)
	if has_nano then
		local n = math.floor(f.inner * math.max(0, math.min(1, c.nano / c.max_nano)) + 0.5)
		ui.visible(f.np_fill, n > 0)
		if n > 0 then
			ui.size(f.np_fill, n, f.np_h)
		end
	end

	-- the accent stripe is an empty view: give it the frame's real height
	local body_h = 4 + f.name_h + (slot.has_bar ~= false and 2 + f.hp_h or 0) + (has_nano and 2 + f.np_h or 0)
		+ (compact and 0 or 2 + f.info_h) + 5
	ui.size(f.accent, ACCENT_W, math.max(body_h, f.portrait_h + 8))

	-- info row: who, how far, in reach
	if not compact then
		ui.text(f.info, info_line(c))
		local d = distance_to(c)
		ui.text(f.distance, d and (d < 10 and string.format("%.1f m", d) or string.format("%d m", math.floor(d + 0.5))) or "")
		ui.fill_color(f.reach, slot.in_reach and "#6fd46f" or "#33424f")
		ui.tooltip(f.reach, slot.in_reach and "In weapon reach" or "Out of weapon reach")
	end
end

local function apply_all()
	if not last_upper then
		return
	end
	apply_slot(frames[1], last_upper)
	apply_slot(frames[2], last_lower)
end

-- ---- options strip (double-click) ----------------------------------------------------
local function refresh_edit()
	ui.visible(edit, editing)
	ui.selected(lock_button, placement.locked())
	ui.selected(compact_button, compact)
	ui.text(size_button, "Size " .. size)
end

local function relayout()
	ui.size(root, frame_width(), -1)
	for _, f in ipairs(frames) do
		size_frame(f)
	end
	apply_all()
end

local function load_settings()
	size = ui.state.read(root, "NdguiSize")
	if not SIZES[size] then
		size = "M"
	end
	compact = ui.state.read(root, "NdguiCompact") == "true"
end

placement = D.movable(root, {
	lock_key = "NdguiLocked",
	double_click = function()
		editing = not editing
		refresh_edit()
	end,
	-- saved settings become readable at restore, not at load
	restored = function()
		load_settings()
		if edit then
			refresh_edit()
			relayout()
		end
	end,
})

frames[1] = new_frame()
frames[2] = new_frame()
edit = ui.load("edit.xml")
ui.add(root, edit)
lock_button = ui.find(edit, "target_lock")
size_button = ui.find(edit, "target_size")
compact_button = ui.find(edit, "target_compact")
ui.on_click(lock_button, function()
	placement.set_locked(not placement.locked())
	refresh_edit()
end)
ui.on_click(size_button, function()
	for i, s in ipairs(SIZE_ORDER) do
		if s == size then
			size = SIZE_ORDER[i % #SIZE_ORDER + 1]
			break
		end
	end
	ui.state.write(root, "NdguiSize", size, "text")
	refresh_edit()
	relayout()
end)
ui.on_click(compact_button, function()
	compact = not compact
	ui.state.write(root, "NdguiCompact", tostring(compact), "bool")
	refresh_edit()
	relayout()
end)
refresh_edit()
relayout()

-- aliases follow whoever is currently your target / fight target / you
if game.character and game.character.subscribe then
	for _, alias in ipairs({ "target", "fight", "self" }) do
		pcall(game.character.subscribe, alias, "", function(_, character)
			characters[alias] = type(character) == "table" and character or nil
			apply_all()
		end)
	end
end

function target_panel_place(viewport_width, hostile)
	local width = frame_width()
	local centre = viewport_width * 0.5
	local clearance = D.COMPASS_CLEARANCE
	local x = hostile and (centre + clearance) or (centre - clearance - width)
	D.place_default(placement, root, math.floor(math.max(0, x)), D.TOP_Y)
end

local state_checked = false
function target_panel_apply(upper_slot, lower_slot)
	last_upper, last_lower = upper_slot, lower_slot
	if not state_checked then
		state_checked = true
		placement.reload()
	end
	ui.size(root, frame_width(), -1)
	apply_all()
end
