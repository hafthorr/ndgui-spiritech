-- Dovvetech prk.status-bars provider (classic ndGUI layout).
-- Native creates one VM per bar and calls status_bar_initialize(kind), then status_bar_apply.
-- HP/NP: vertical bars flanking the character with numbers underneath, or flat with the number
--        inside. Double-click one to show its Lock / Flat strip (HUD pieces get no right-click).
-- XP/AXP: slim horizontal bars resting on the bottom menubar.
local Vitals = ui.require("character.vitals")
local D = ui.require("notum.ndgui-lib/dovvetech")
local root = ui.load("window.xml")
ui.root(root)
local placement

local FLAT_W, FLAT_H = 160, 18
local EDIT_H = 26 -- strip 22 + 4 gap

local specs = {
	health = { label = "", tooltip = "Health", vital = true },
	nano = { label = "", tooltip = "Nano", vital = true },
	experience = { label = "XP  ", tooltip = "Experience" },
	alien = { label = "AXP  ", tooltip = "Alien Experience" },
}
local kind, spec
local content, bar, fill, caption, shadow
local edit, lock_button, flat_button
local flat, editing = false, false
local bar_w, bar_h, fraction = 0, 0, 0
local caption_text, tip_text = "-- / --", ""
local last_w, last_h

local function vertical()
	return spec.vital and not flat
end

local function hint()
	if not spec.vital then
		return ""
	end
	return placement.locked() and "\nLocked - double-click for options" or "\nDouble-click for options"
end

local function layout(force)
	local w, h = ui.parent_width(root), ui.parent_height(root)
	if not force and w == last_w and h == last_h then
		return
	end
	last_w, last_h = w, h
	local x, y, rw, rh = D.status_rect(kind, w, h)
	if spec.vital then
		if flat then
			rw, rh = FLAT_W, FLAT_H
			bar_w, bar_h = FLAT_W, FLAT_H
		else
			bar_w, bar_h = D.VITAL_W, D.VITAL_BAR_H
		end
		if editing then
			rw, rh = math.max(rw, 96), rh + EDIT_H
		end
	else
		bar_w, bar_h = rw, rh
		ui.size(bar, rw, rh)
	end
	ui.size(root, rw, rh)
	D.place_default(placement, root, x, y)
end

-- Fill is a stretched art strip sized to the reading; vertical fills grow upward.
local function paint()
	if not fill then
		return
	end
	local length = vertical() and bar_h or bar_w
	local filled = math.floor(length * fraction + 0.5)
	ui.visible(fill, filled > 0)
	if filled > 0 then
		if vertical() then
			ui.size(fill, bar_w, filled)
		else
			ui.size(fill, filled, bar_h)
		end
	end
end

local function show_text()
	ui.text(caption, caption_text)
	if shadow then
		ui.text(shadow, caption_text)
	end
	ui.tooltip(bar, tip_text .. hint())
end

local function refresh_edit()
	if not edit then
		return
	end
	ui.visible(edit, editing)
	ui.selected(lock_button, placement.locked())
	ui.selected(flat_button, flat)
end

-- (Re)build the bar for the current orientation; the edit strip always sits underneath.
local function build()
	if content then
		ui.destroy(content)
	end
	if edit then
		ui.destroy(edit)
		edit = nil
	end
	local name = kind
	if spec.vital and flat then
		name = kind .. "_h"
	end
	content = ui.load(name .. ".xml")
	ui.add(root, content)
	bar = ui.find(content, "status_bar")
	fill = ui.find(content, "status_fill")
	caption = ui.find(content, "status_caption")
	shadow = ui.find(content, "status_caption_shadow")
	ui.text_color(caption, vertical() and D.color.text or "#FFFFFF")
	if spec.vital then
		edit = ui.load("edit.xml")
		ui.add(root, edit)
		lock_button = ui.find(edit, "status_lock")
		flat_button = ui.find(edit, "status_flat")
		ui.on_click(lock_button, function()
			placement.set_locked(not placement.locked())
			refresh_edit()
			show_text()
		end)
		ui.on_click(flat_button, function()
			flat = not flat
			ui.state.write(root, "NdguiFlat", tostring(flat), "bool")
			build()
		end)
	end
	refresh_edit()
	layout(true)
	paint()
	show_text()
end

function status_bar_initialize(which)
	spec = assert(specs[which], "Unknown player status bar")
	kind = which
	-- XP/AXP moved into the strip in v2; a new pose field lets them dock there once.
	placement = D.movable(root, {
		field = spec.vital and D.PLACEMENT_FIELD or "NdguiStrip",
		lock_key = spec.vital and "NdguiLocked" or nil,
		double_click = spec.vital and function()
			editing = not editing
			refresh_edit()
			layout(true)
		end or nil,
	})
	if spec.vital then
		flat = ui.state.read(root, "NdguiFlat") == "true"
	end
	build()
end

function status_bar_apply(reading, shadowknowledge)
	layout()
	local label, tip = spec.label, spec.tooltip
	if shadowknowledge and kind == "experience" then
		label, tip = "SK  ", "Shadowknowledge"
	end
	local text = Vitals.reading_text(reading)
	fraction = math.max(0, math.min(1, tonumber(reading.fraction) or 0))
	caption_text = label .. text
	tip_text = tip .. ": " .. text
	paint()
	show_text()
end
