-- Dovvetech prk.status-bars provider (classic ndGUI layout).
-- Native creates one VM per bar and calls status_bar_initialize(kind), then status_bar_apply.
-- HP/NP: vertical bars flanking the character with numbers underneath, or flat with the number
--        inside. Double-click one to show its Lock / Flat / Size strip (HUD pieces get no right-click).
--        Size cycles S / M / L / XL (M = the classic size), saved per bar like Flat.
-- XP/AXP: slim horizontal bars resting on the bottom menubar.
local Vitals = ui.require("character.vitals")
local D = ui.require("notum.ndgui-lib/dovvetech")
local Unit = ui.require("notum.ndgui-lib/unit")
local root = ui.load("window.xml")
ui.root(root)
local placement

local EDIT_H, EDIT_W = 26, 150 -- strip 22 + 4 gap; Lock + Flat + Size
-- upright: bar width/height, number plate width, font; flat: bar width/height, font
local SIZES = {
	{ id = "S", bar_w = 10, bar_h = 100, label_w = 84, font = 10, flat_w = 120, flat_h = 14, flat_font = 10 },
	{ id = "M", bar_w = 14, bar_h = 140, label_w = 96, font = 11, flat_w = 160, flat_h = 18, flat_font = 11 },
	{ id = "L", bar_w = 18, bar_h = 190, label_w = 112, font = 13, flat_w = 220, flat_h = 24, flat_font = 13 },
	{ id = "XL", bar_w = 24, bar_h = 240, label_w = 128, font = 15, flat_w = 300, flat_h = 30, flat_font = 15 },
}
local size_index = 2
local function size()
	return SIZES[size_index]
end
local function plate_h()
	return size().font + 7
end

local specs = {
	health = { label = "", tooltip = "Health", vital = true },
	nano = { label = "", tooltip = "Nano", vital = true },
	experience = { label = "XP  ", tooltip = "Experience" },
	alien = { label = "AXP  ", tooltip = "Alien Experience" },
}
local kind, spec
local content, bar, fill, caption, shadow
local edit, lock_button, flat_button, size_button
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
		local s = size()
		if flat then
			rw, rh = s.flat_w, s.flat_h
			bar_w, bar_h = s.flat_w, s.flat_h
		else
			-- the default spot stays centred on the classic 96-wide bar
			x = x + math.floor((rw - s.label_w) / 2)
			rw, rh = s.label_w, s.bar_h + 2 + plate_h()
			bar_w, bar_h = s.bar_w, s.bar_h
		end
		if editing then
			rw, rh = math.max(rw, EDIT_W), rh + EDIT_H
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
	ui.text(size_button, "Size " .. size().id)
end

-- Fit the loaded HP/NP views to the chosen size (the XML carries the M size).
local function apply_size()
	local s = size()
	local function fix(view, w, h)
		ui.limits(view, w, h, w, h)
	end
	local body = ui.find(content, "status_body")
	if flat then
		fix(body, s.flat_w, s.flat_h)
		fix(bar, s.flat_w, s.flat_h)
		for _, text in ipairs({ caption, shadow }) do
			fix(text, s.flat_w, s.flat_h)
			ui.font_size(text, s.flat_font)
		end
	else
		local ph = plate_h()
		fix(body, s.label_w, s.bar_h + 2 + ph)
		fix(bar, s.bar_w, s.bar_h)
		fix(ui.find(content, "status_caption_plate"), s.label_w, ph)
		fix(ui.find(content, "status_caption_back"), s.label_w - 12, ph - 1)
		for _, text in ipairs({ caption, shadow }) do
			fix(text, s.label_w, ph)
			ui.font_size(text, s.font)
		end
	end
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
	-- ui.find raises on a missing view: only HP/NP layouts carry the shadow text
	shadow = spec.vital and ui.find(content, "status_caption_shadow") or nil
	ui.text_color(caption, vertical() and D.color.text or "#FFFFFF")
	if spec.vital then
		apply_size()
		edit = ui.load("edit.xml")
		ui.add(root, edit)
		lock_button = ui.find(edit, "status_lock")
		flat_button = ui.find(edit, "status_flat")
		size_button = ui.find(edit, "status_size")
		ui.on_click(size_button, function()
			size_index = size_index % #SIZES + 1
			ui.state.write(root, "NdguiSize", size().id, "text")
			build()
		end)
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
		restored = spec.vital and function()
			local saved = ui.state.read(root, "NdguiFlat") == "true"
			local saved_size = size_index
			for index, s in ipairs(SIZES) do
				if s.id == ui.state.read(root, "NdguiSize") then
					saved_size = index
				end
			end
			if saved ~= flat or saved_size ~= size_index then
				flat, size_index = saved, saved_size
				if content then
					build()
				end
			elseif content then
				refresh_edit()
				show_text()
			end
		end or nil,
	})
	build()
end

local state_checked = false
function status_bar_apply(reading, shadowknowledge)
	if not state_checked then
		state_checked = true
		placement.reload()
	end
	layout()
	local label, tip = spec.label, spec.tooltip
	if shadowknowledge and kind == "experience" then
		label, tip = "SK  ", "Shadowknowledge"
	end
	-- thousands separators like the credits counter: 1396 / 4500 -> 1,396 / 4,500
	local text = Vitals.reading_text(reading):gsub("%d%d%d%d+", Unit.thousands)
	fraction = math.max(0, math.min(1, tonumber(reading.fraction) or 0))
	caption_text = label .. text
	tip_text = tip .. ": " .. text
	paint()
	show_text()
end
