-- Dovvetech prk.status-bars provider (classic ndGUI layout).
-- Native creates one VM per bar and calls status_bar_initialize(kind), then status_bar_apply.
-- HP/NP: vertical bars flanking the character with numbers underneath.
-- XP/AXP: slim horizontal bars resting on the bottom menubar.
local Vitals = ui.require("character.vitals")
local D = ui.require("notum.ndgui-lib/dovvetech")
local root = ui.load("window.xml")
ui.root(root)
local placement

local specs = {
	health = { label = "", tooltip = "Health", vertical = true },
	nano = { label = "", tooltip = "Nano", vertical = true },
	experience = { label = "XP  ", tooltip = "Experience" },
	alien = { label = "AXP  ", tooltip = "Alien Experience" },
}
local kind, spec, bar, fill, caption, shadow
local bar_w, bar_h, fraction = 0, 0, 0
local last_w, last_h

local function layout()
	local w, h = ui.parent_width(root), ui.parent_height(root)
	if w == last_w and h == last_h then
		return
	end
	last_w, last_h = w, h
	local x, y, rw, rh = D.status_rect(kind, w, h)
	ui.size(root, rw, rh)
	if spec.vertical then
		bar_w, bar_h = D.VITAL_W, D.VITAL_BAR_H
	else
		bar_w, bar_h = rw, rh
		ui.size(bar, rw, rh)
	end
	D.place_default(placement, root, x, y)
end

-- Fill is a stretched art strip sized to the reading; vertical fills grow upward.
local function paint()
	if not fill then
		return
	end
	local length = spec.vertical and bar_h or bar_w
	local filled = math.floor(length * fraction + 0.5)
	ui.visible(fill, filled > 0)
	if filled > 0 then
		if spec.vertical then
			ui.size(fill, bar_w, filled)
		else
			ui.size(fill, filled, bar_h)
		end
	end
end

function status_bar_initialize(which)
	spec = assert(specs[which], "Unknown player status bar")
	kind = which
	-- XP/AXP moved into the strip in v2; a new pose field lets them dock there once.
	-- HP/NP: right-click -> Lock position (saved per bar)
	placement = D.movable(root, {
		field = spec.vertical and D.PLACEMENT_FIELD or "NdguiStrip",
		lock_key = spec.vertical and "NdguiLocked" or nil,
	})
	local content = ui.load(kind .. ".xml")
	ui.add(root, content)
	bar = ui.find(content, "status_bar")
	fill = ui.find(content, "status_fill")
	caption = ui.find(content, "status_caption")
	shadow = spec.vertical and ui.find(content, "status_caption_shadow") or nil
	ui.text_color(caption, spec.vertical and D.color.text or "#FFFFFF")
	layout()
	paint()
end

function status_bar_apply(reading, shadowknowledge)
	layout()
	local label, tip = spec.label, spec.tooltip
	if shadowknowledge and kind == "experience" then
		label, tip = "SK  ", "Shadowknowledge"
	end
	local text = Vitals.reading_text(reading)
	fraction = math.max(0, math.min(1, tonumber(reading.fraction) or 0))
	paint()
	ui.text(caption, label .. text)
	if shadow then
		ui.text(shadow, label .. text)
	end
	ui.tooltip(bar, tip .. ": " .. text)
end
