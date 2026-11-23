-- DarkTech prk.hotbar provider: stock hotbar_apply contract. Framed steel plate per bar,
ui.require("notum.ndgui-lib/grid") -- ndGUI: snap to grid while moving/resizing (ndgui-lib/lua/grid.lua)
-- recessed slot wells (native slot tile disabled with slot_gfx=""), lit blue rail on the active bar
-- (no key labels: the client doesn't tell addons the real bindings), slim spinner that doubles as the drag handle.
local root = ui.load("bar.xml")
local horizontal = ui.find(root, "shortcut_bar_horizontal")
local vertical = ui.find(root, "shortcut_bar_vertical")
local horizontal_slots = ui.find(horizontal, "shortcut_bar_slots")
local vertical_slots = ui.find(vertical, "shortcut_bar_slots")
local LIB = "library://notum.ndgui-lib/hotbar/"
local slots = {}
local cells = {}
local arranged_vertical

for index = 1, 10 do
	-- Each cell is ndGUI slot art with the native ItemSlotView on top.
	cells[index] = ui.load("slot.xml")
	slots[index] = ui.find(cells[index], "shortcut_slot")
	ui.add(horizontal_slots, cells[index])
end

ui.root(root)
local Move = ui.require("core.move")
local placement = ui.require("core.placement").attach(root, { only_moved = true })
Move.attach(root, { handle = ui.find(horizontal, "shortcut_bar_spinner"), placement = placement })
Move.attach(root, { handle = ui.find(vertical, "shortcut_bar_spinner"), placement = placement })

local function controls(host, state)
	local active = ui.find(host, "shortcut_bar_active")
	local previous = ui.find(host, "shortcut_bar_previous")
	local next = ui.find(host, "shortcut_bar_next")
	ui.bind(active, state.activate)
	ui.action(active, "game.hotbar.activate", state.activate, "left")
	ui.bind(previous, state.previous)
	ui.action(previous, "game.hotbar.previous", state.previous, "left")
	ui.bind(next, state.next)
	ui.action(next, "game.hotbar.next", state.next, "left")
	ui.bind(ui.find(host, "shortcut_bar_spinner"), state.spinner)
end

local function arrange(vertical_mode)
	if arranged_vertical == vertical_mode then
		return
	end
	if ui.in_combat() then
		return
	end
	local target = vertical_mode and vertical_slots or horizontal_slots
	for _, cell in ipairs(cells) do
		ui.add(target, cell)
	end
	ui.visible(horizontal, not vertical_mode)
	ui.visible(vertical, vertical_mode)
	ui.size(root, vertical_mode and 44 or 398, vertical_mode and 398 or 44)
	arranged_vertical = vertical_mode
end

-- "2m", "30s", "1h", "1:20", "1m 30s": a time, not a stack count
local function is_timer(text)
	return text:find("%d") ~= nil and text:find("[smhd:]") ~= nil and text:find("^[%d%s:%.smhd]+$") ~= nil
end

local function present(slot, entry)
	ui.bind(slot, entry.token)
	ui.action(slot, "game.hotbar.use", entry.token, "left")
	ui.icon(slot, entry.icon)
	ui.content(slot, entry.content)
	ui.tooltip(slot, entry.tooltip)
	ui.badge(slot, entry.badge)
	ui.fade(slot, entry.faded, "")
	ui.image(slot, entry.graphic ~= "" and "gfx://" .. entry.graphic or "")
	ui.caption(slot, entry.caption)
	-- Items send their cooldown as centered countdown text (big, readable); perks send theirs as small corner
	-- text (2m). Show both the same way: a timer in the corner moves to the centre. Plain counts (stacks) stay.
	local corner, center = entry.corner, entry.countdown
	if center == "" and is_timer(corner) then
		corner, center = "", corner
	end
	ui.corner(slot, corner)
	ui.center(slot, center)
end

function hotbar_apply(state, entries)
	controls(horizontal, state)
	controls(vertical, state)
	arrange(state.vertical)
	local lit = state.active and "active_on_" or "active_off_"
	ui.image(ui.find(horizontal, "shortcut_bar_active_icon"), LIB .. lit .. "h.png")
	ui.image(ui.find(vertical, "shortcut_bar_active_icon"), LIB .. lit .. "v.png")
	for _, host in ipairs({ horizontal, vertical }) do
		ui.text(ui.find(host, "shortcut_bar_row"), tostring(state.row))
	end
	for index, slot in ipairs(slots) do
		present(slot, entries[index])
	end
end
