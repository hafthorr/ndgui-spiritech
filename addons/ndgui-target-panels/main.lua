-- Dovvetech prk.target-panels provider. One VM per panel (friendly / hostile), two native slots each.
-- Each slot is a fixed-size unit frame: consider-colour accent, profession portrait (players) or
-- level (NPCs), name + level, HP bar with exact numbers and a draining "ghost" of recent damage,
-- nano bar when known, and an info row (profession / org or side, distance, weapon reach).
-- The native slot only carries name, colours and fractions; the rest comes from game.character
-- ("target", "fight", "self"), matched to a slot by name. Double-click a panel: Lock / Size / Compact.
-- The frame itself (ghost, pulse, floating combat numbers, "» You") is ndgui-lib's unit.lua.
local D = ui.require("notum.ndgui-lib/dovvetech")
local Unit = ui.require("notum.ndgui-lib/unit")
local root = ui.load("panel.xml")
ui.root(root)

local SIZES = { S = 1.0, M = 1.2, L = 1.45 }
local SIZE_ORDER = { "S", "M", "L" }
local BASE_W = 250 -- frame width at size S

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

-- One native slot -> one unit frame.
local function apply_slot(f, slot)
	if slot == nil or slot.name == nil or slot.name == "" then
		f:hide()
		return
	end
	f:show({
		name = slot.name, name_color = slot.name_color or 0xc5d7e6, header = slot.header,
		accent = slot.bar_color or 0x3d6f9a, bar_color = slot.bar_color or 0xc44747,
		fraction = slot.fraction or 0, has_bar = slot.has_bar, in_reach = slot.in_reach == true,
		character = character_for(slot.name),
	})
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
		f:layout(frame_width(), scale(), compact)
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

frames[1] = Unit.new(root, { target_of_target = true })
frames[2] = Unit.new(root, { target_of_target = true })
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
			if alias == "self" then
				Unit.set_self(characters.self)
			end
			apply_all()
		end)
	end
end

-- floating damage / healing numbers and "who it attacks"
Unit.watch_combat()

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
